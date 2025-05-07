//!
//! This module implements means to write/create TVG files.
//!

const std = @import("std");
const tvg = @import("tinyvg.zig");

pub fn create(writer: anytype) Builder(@TypeOf(writer)) {
    return .{ .writer = writer };
}

// normal types:
//   style.type
//   uint(length - 1)
//   style
//   (line_width)
//
// outline types:
//   fill_style.type
//   line_style.type
//
//   uint(length - 1)
//
//   fill_style
//   line_style
//   line_width

pub fn Builder(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub const Error = Writer.Error || error{OutOfRange};

        writer: Writer,
        state: State = .initial,

        scale: tvg.Scale = undefined,
        range: tvg.Range = undefined,
        color_encoding: tvg.ColorEncoding = undefined,

        pub fn writeHeader(self: *Self, width: u32, height: u32, scale: tvg.Scale, color_encoding: tvg.ColorEncoding, range: tvg.Range) Error!void {
            errdefer self.state = .faulted;
            std.debug.assert(self.state == .initial);

            try self.writer.writeAll(&[_]u8{
                0x72, 0x56, // magic
                tvg.current_version, // version
                @intFromEnum(scale) | (@as(u8, @intFromEnum(color_encoding)) << 4) | (@as(u8, @intFromEnum(range)) << 6),
            });
            switch (range) {
                .reduced => {
                    const rwidth = mapSizeToType(u8, width) catch return error.OutOfRange;
                    const rheight = mapSizeToType(u8, height) catch return error.OutOfRange;

                    try self.writer.writeInt(u8, rwidth, .little);
                    try self.writer.writeInt(u8, rheight, .little);
                },

                .default => {
                    const rwidth = mapSizeToType(u16, width) catch return error.OutOfRange;
                    const rheight = mapSizeToType(u16, height) catch return error.OutOfRange;

                    try self.writer.writeInt(u16, rwidth, .little);
                    try self.writer.writeInt(u16, rheight, .little);
                },

                .enhanced => {
                    try self.writer.writeInt(u32, width, .little);
                    try self.writer.writeInt(u32, height, .little);
                },
            }

            self.color_encoding = color_encoding;
            self.scale = scale;
            self.range = range;

            self.state = .color_table;
        }

        pub fn writeColorTable(self: *Self, colors: []const tvg.Color) (error{UnsupportedColorEncoding} || Error)!void {
            errdefer self.state = .faulted;
            std.debug.assert(self.state == .color_table);

            const count = std.math.cast(u32, colors.len) orelse return error.OutOfRange;
            try self.writeUint(count);

            switch (self.color_encoding) {
                .u565 => for (colors) |c| {
                    const rgb8 = c.toRgba8();

                    const value: u16 =
                        (@as(u16, ((rgb8[0] >> 3) & 0x1F)) << 0) |
                        (@as(u16, ((rgb8[1] >> 2) & 0x2F)) << 5) |
                        (@as(u16, ((rgb8[2] >> 3) & 0x1F)) << 11);

                    try self.writer.writeInt(u16, value, .little);
                },

                .u8888 => for (colors) |c| {
                    const rgba = c.toRgba8();
                    try self.writer.writeInt(u8, rgba[0], .little);
                    try self.writer.writeInt(u8, rgba[1], .little);
                    try self.writer.writeInt(u8, rgba[2], .little);
                    try self.writer.writeInt(u8, rgba[3], .little);
                },
                .f32 => for (colors) |c| {
                    try self.writer.writeInt(u32, @as(u32, @bitCast(c.r)), .little);
                    try self.writer.writeInt(u32, @as(u32, @bitCast(c.g)), .little);
                    try self.writer.writeInt(u32, @as(u32, @bitCast(c.b)), .little);
                    try self.writer.writeInt(u32, @as(u32, @bitCast(c.a)), .little);
                },

                .custom => return error.UnsupportedColorEncoding,
            }

            self.state = .body;
        }

        pub fn writeCustomColorTable(self: *Self) (error{UnsupportedColorEncoding} || Error)!void {
            errdefer self.state = .faulted;
            std.debug.assert(self.state == .color_table);

            if (self.color_encoding != .custom) {
                return error.UnsupportedColorEncoding;
            }

            self.state = .body;
        }

        pub fn writeFillPolygon(self: *Self, style: tvg.Style, points: []const tvg.Point) Error!void {
            try self.writeFillHeader(.fill_polygon, style, points.len);
            for (points) |pt| {
                try self.writePoint(pt);
            }
        }

        pub fn writeFillRectangles(self: *Self, style: tvg.Style, rectangles: []const tvg.Rectangle) Error!void {
            try self.writeFillHeader(.fill_rectangles, style, rectangles.len);
            for (rectangles) |rect| {
                try self.writeRectangle(rect);
            }
        }

        pub fn writeDrawLines(self: *Self, style: tvg.Style, line_width: f32, lines: []const tvg.Line) Error!void {
            try self.writeLineHeader(.draw_lines, style, line_width, lines.len);
            for (lines) |line| {
                try self.writePoint(line.start);
                try self.writePoint(line.end);
            }
        }

        pub fn writeDrawLineLoop(self: *Self, style: tvg.Style, line_width: f32, points: []const tvg.Point) Error!void {
            try self.writeLineHeader(.draw_line_loop, style, line_width, points.len);
            for (points) |pt| {
                try self.writePoint(pt);
            }
        }

        pub fn writeDrawLineStrip(self: *Self, style: tvg.Style, line_width: f32, points: []const tvg.Point) Error!void {
            try self.writeLineHeader(.draw_line_strip, style, line_width, points.len);
            for (points) |pt| {
                try self.writePoint(pt);
            }
        }

        pub fn writeOutlineFillPolygon(self: *Self, fill_style: tvg.Style, line_style: tvg.Style, line_width: f32, points: []const tvg.Point) Error!void {
            try self.writeOutlineFillHeader(.outline_fill_polygon, fill_style, line_style, line_width, points.len);
            for (points) |pt| {
                try self.writePoint(pt);
            }
        }

        pub fn writeOutlineFillRectangles(self: *Self, fill_style: tvg.Style, line_style: tvg.Style, line_width: f32, rectangles: []const tvg.Rectangle) Error!void {
            try self.writeOutlineFillHeader(.outline_fill_rectangles, fill_style, line_style, line_width, rectangles.len);
            for (rectangles) |rect| {
                try self.writeRectangle(rect);
            }
        }

        pub fn writeFillPath(self: *Self, style: tvg.Style, path: []const tvg.Path.Segment) Error!void {
            try validatePath(path);

            try self.writeFillHeader(.fill_path, style, path.len);
            try self.writePath(path);
        }

        pub fn writeDrawPath(self: *Self, style: tvg.Style, line_width: f32, path: []const tvg.Path.Segment) Error!void {
            try validatePath(path);

            try self.writeLineHeader(.draw_line_path, style, line_width, path.len);
            try self.writePath(path);
        }

        pub fn writeOutlineFillPath(self: *Self, fill_style: tvg.Style, line_style: tvg.Style, line_width: f32, path: []const tvg.Path.Segment) Error!void {
            try validatePath(path);

            try self.writeOutlineFillHeader(.outline_fill_path, fill_style, line_style, line_width, path.len);
            try self.writePath(path);
        }

        pub fn writeEndOfFile(self: *Self) Error!void {
            errdefer self.state = .faulted;
            std.debug.assert(self.state == .body);

            try self.writeCommandAndStyleType(.end_of_document, .flat);

            self.state = .end_of_file;
        }

        /// Writes the preamble for a `draw_*` command
        fn writeFillHeader(self: *Self, command: tvg.Command, style: tvg.Style, count: usize) Error!void {
            const actual_len = try validateLength(count);

            try self.writeCommandAndStyleType(command, style);
            try self.writeUint(actual_len);
            try self.writeStyle(style);
        }

        /// Writes the preamble for a `draw_*` command
        fn writeLineHeader(self: *Self, command: tvg.Command, style: tvg.Style, line_width: f32, count: usize) Error!void {
            const actual_len = try validateLength(count);

            try self.writeCommandAndStyleType(command, style);
            try self.writeUint(actual_len);
            try self.writeStyle(style);
            try self.writeUnit(line_width);
        }

        /// Writes the preamble for a `outline_fill_*` command
        fn writeOutlineFillHeader(self: *Self, command: tvg.Command, fill_style: tvg.Style, line_style: tvg.Style, line_width: f32, length: usize) Error!void {
            const total_count = try validateLength(length);
            const reduced_count: ReducedCount = if (total_count < std.math.maxInt(u6))
                @enumFromInt(@as(u6, @truncate(total_count)))
            else
                return error.OutOfRange;

            try self.writeCommandAndStyleType(command, fill_style);
            try self.writeStyleTypeAndCount(line_style, reduced_count);
            try self.writeStyle(fill_style);
            try self.writeStyle(line_style);
            try self.writeUnit(line_width);
        }

        fn validateLength(count: usize) Error!u32 {
            if (count == 0)
                return error.OutOfRange;
            return std.math.cast(u32, count - 1) orelse return error.OutOfRange;
        }

        fn validatePath(segments: []const tvg.Path.Segment) Error!void {
            _ = try validateLength(segments.len);
            for (segments) |segment| {
                _ = try validateLength(segment.commands.len);
            }
        }

        fn writeCommandAndStyleType(self: *Self, cmd: tvg.Command, style_type: tvg.StyleType) Error!void {
            try self.writer.writeByte((@as(u8, @intFromEnum(style_type)) << 6) | @intFromEnum(cmd));
        }

        /// Encodes a 6 bit count as well as a 2 bit style type.
        fn writeStyleTypeAndCount(self: *Self, style: tvg.StyleType, mapped_count: ReducedCount) !void {
            const data = (@as(u8, @intFromEnum(style)) << 6) | @intFromEnum(mapped_count);
            try self.writer.writeByte(data);
        }

        /// Writes a Style without encoding the type. This must be done via a second channel.
        fn writeStyle(self: *Self, style: tvg.Style) Error!void {
            return switch (style) {
                .flat => |value| try self.writeUint(value),
                .linear, .radial => |grad| {
                    try self.writePoint(grad.point_0);
                    try self.writePoint(grad.point_1);
                    try self.writeUint(grad.color_0);
                    try self.writeUint(grad.color_1);
                },
            };
        }

        fn writePath(self: *Self, path: []const tvg.Path.Segment) !void {
            for (path) |item| {
                std.debug.assert(item.commands.len > 0);
                try self.writeUint(@intCast(item.commands.len - 1));
            }
            for (path) |item| {
                try self.writePoint(item.start);
                for (item.commands) |node| {
                    const kind: u8 = @intFromEnum(std.meta.activeTag(node));

                    const line_width = switch (node) {
                        .line => |data| data.line_width,
                        .horiz => |data| data.line_width,
                        .vert => |data| data.line_width,
                        .bezier => |data| data.line_width,
                        .arc_circle => |data| data.line_width,
                        .arc_ellipse => |data| data.line_width,
                        .close => |data| data.line_width,
                        .quadratic_bezier => |data| data.line_width,
                    };

                    const tag: u8 = kind |
                        if (line_width != null) @as(u8, 0x10) else 0;

                    try self.writer.writeByte(tag);
                    if (line_width) |width| {
                        try self.writeUnit(width);
                    }

                    switch (node) {
                        .line => |data| try self.writePoint(data.data),
                        .horiz => |data| try self.writeUnit(data.data),
                        .vert => |data| try self.writeUnit(data.data),
                        .bezier => |data| {
                            try self.writePoint(data.data.c0);
                            try self.writePoint(data.data.c1);
                            try self.writePoint(data.data.p1);
                        },
                        .arc_circle => |data| {
                            const flags: u8 = 0 |
                                (@as(u8, @intFromBool(data.data.sweep)) << 1) |
                                (@as(u8, @intFromBool(data.data.large_arc)) << 0);
                            try self.writer.writeByte(flags);
                            try self.writeUnit(data.data.radius);
                            try self.writePoint(data.data.target);
                        },
                        .arc_ellipse => |data| {
                            const flags: u8 = 0 |
                                (@as(u8, @intFromBool(data.data.sweep)) << 1) |
                                (@as(u8, @intFromBool(data.data.large_arc)) << 0);
                            try self.writer.writeByte(flags);
                            try self.writeUnit(data.data.radius_x);
                            try self.writeUnit(data.data.radius_y);
                            try self.writeUnit(data.data.rotation);
                            try self.writePoint(data.data.target);
                        },
                        .quadratic_bezier => |data| {
                            try self.writePoint(data.data.c);
                            try self.writePoint(data.data.p1);
                        },
                        .close => {},
                    }
                }
            }
        }

        fn writeUint(self: *Self, value: u32) Error!void {
            var iter = value;
            while (iter >= 0x80) {
                try self.writer.writeByte(@as(u8, 0x80) | @as(u7, @truncate(iter)));
                iter >>= 7;
            }
            try self.writer.writeByte(@as(u7, @truncate(iter)));
        }

        fn writeUnit(self: *Self, value: f32) Error!void {
            const val = self.scale.map(value).raw();
            switch (self.range) {
                .reduced => {
                    const reduced_val = std.math.cast(i8, val) orelse return error.OutOfRange;
                    try self.writer.writeInt(i8, reduced_val, .little);
                },
                .default => {
                    const reduced_val = std.math.cast(i16, val) orelse return error.OutOfRange;
                    try self.writer.writeInt(i16, reduced_val, .little);
                },
                .enhanced => {
                    try self.writer.writeInt(i32, val, .little);
                },
            }
        }

        fn writePoint(self: *Self, point: tvg.Point) Error!void {
            try self.writeUnit(point.x);
            try self.writeUnit(point.y);
        }

        fn writeRectangle(self: *Self, rect: tvg.Rectangle) Error!void {
            try self.writeUnit(rect.x);
            try self.writeUnit(rect.y);
            try self.writeUnit(rect.width);
            try self.writeUnit(rect.height);
        }

        const State = enum {
            initial,
            color_table,
            body,
            end_of_file,
            faulted,
        };
    };
}

fn mapSizeToType(comptime Dest: type, value: usize) error{OutOfRange}!Dest {
    if (value == 0 or value > std.math.maxInt(Dest) + 1) {
        return error.OutOfRange;
    }
    if (value == std.math.maxInt(Dest))
        return 0;
    return @intCast(value);
}

const ReducedCount = enum(u6) {
    // 0 = 64, everything else is equivalent
    _,
};

//const ground_truth = @import("../data/ground-truth.zig");
//
//test "encode shield (default range, scale 1/256)" {
//    var buffer: [1024]u8 = undefined;
//    var stream = std.io.fixedBufferStream(&buffer);
//
//    var writer = create(stream.writer());
//    try writer.writeHeader(24, 24, .@"1/256", .u8888, .default);
//    try ground_truth.renderShield(&writer);
//}
//
//test "encode shield (reduced range, scale 1/4)" {
//    var buffer: [1024]u8 = undefined;
//    var stream = std.io.fixedBufferStream(&buffer);
//
//    var writer = create(stream.writer());
//    try writer.writeHeader(24, 24, .@"1/4", .u8888, .reduced);
//    try ground_truth.renderShield(&writer);
//}

test "encode app_menu (default range, scale 1/256)" {
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    var writer = create(stream.writer());
    try writer.writeHeader(48, 48, .@"1/256", .u8888, .default);
    try writer.writeColorTable(&[_]tvg.Color{
        try tvg.Color.fromString("000000"),
    });
    try writer.writeFillRectangles(tvg.Style{ .flat = 0 }, &[_]tvg.Rectangle{
        tvg.rectangle(6, 12, 36, 4),
        tvg.rectangle(6, 22, 36, 4),
        tvg.rectangle(6, 32, 36, 4),
    });
    try writer.writeEndOfFile();
}

test "encode workspace (default range, scale 1/256)" {
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    var writer = create(stream.writer());
    try writer.writeHeader(48, 48, .@"1/256", .u8888, .default);
    try writer.writeColorTable(&[_]tvg.Color{
        try tvg.Color.fromString("008751"),
        try tvg.Color.fromString("83769c"),
        try tvg.Color.fromString("1d2b53"),
    });

    try writer.writeFillRectangles(tvg.Style{ .flat = 0 }, &[_]tvg.Rectangle{tvg.rectangle(6, 6, 16, 36)});
    try writer.writeFillRectangles(tvg.Style{ .flat = 1 }, &[_]tvg.Rectangle{tvg.rectangle(26, 6, 16, 16)});
    try writer.writeFillRectangles(tvg.Style{ .flat = 2 }, &[_]tvg.Rectangle{tvg.rectangle(26, 26, 16, 16)});
    try writer.writeEndOfFile();
}

test "encode workspace_add (default range, scale 1/256)" {
    const Node = tvg.Path.Node;

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    var writer = create(stream.writer());
    try writer.writeHeader(48, 48, .@"1/256", .u8888, .default);
    try writer.writeColorTable(&[_]tvg.Color{
        try tvg.Color.fromString("008751"),
        try tvg.Color.fromString("83769c"),
        try tvg.Color.fromString("ff004d"),
    });

    try writer.writeFillRectangles(tvg.Style{ .flat = 0 }, &[_]tvg.Rectangle{tvg.rectangle(6, 6, 16, 36)});
    try writer.writeFillRectangles(tvg.Style{ .flat = 1 }, &[_]tvg.Rectangle{tvg.rectangle(26, 6, 16, 16)});

    try writer.writeFillPath(tvg.Style{ .flat = 2 }, &[_]tvg.Path.Segment{
        tvg.Path.Segment{
            .start = tvg.point(26, 32),
            .commands = &[_]Node{
                Node{ .horiz = .{ .data = 32 } },
                Node{ .vert = .{ .data = 26 } },
                Node{ .horiz = .{ .data = 36 } },
                Node{ .vert = .{ .data = 32 } },
                Node{ .horiz = .{ .data = 42 } },
                Node{ .vert = .{ .data = 36 } },
                Node{ .horiz = .{ .data = 36 } },
                Node{ .vert = .{ .data = 42 } },
                Node{ .horiz = .{ .data = 32 } },
                Node{ .vert = .{ .data = 36 } },
                Node{ .horiz = .{ .data = 26 } },
            },
        },
    });

    try writer.writeEndOfFile();
}

test "encode arc_variants (default range, scale 1/256)" {
    const Node = tvg.Path.Node;

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    var writer = create(stream.writer());
    try writer.writeHeader(92, 92, .@"1/256", .u8888, .default);
    try writer.writeColorTable(&[_]tvg.Color{
        try tvg.Color.fromString("40ff00"),
    });

    try writer.writeFillPath(tvg.Style{ .flat = 0 }, &[_]tvg.Path.Segment{
        tvg.Path.Segment{
            .start = tvg.point(48, 32),
            .commands = &[_]Node{
                Node{ .horiz = .{ .data = 64 } },
                Node{ .arc_ellipse = .{ .data = .{ .radius_x = 18.5, .radius_y = 18.5, .rotation = 0, .large_arc = false, .sweep = true, .target = tvg.point(80, 48) } } },
                Node{ .vert = .{ .data = 64 } },
                Node{ .arc_ellipse = .{ .data = .{ .radius_x = 18.5, .radius_y = 18.5, .rotation = 0, .large_arc = false, .sweep = false, .target = tvg.point(64, 80) } } },
                Node{ .horiz = .{ .data = 48 } },
                Node{ .arc_ellipse = .{ .data = .{ .radius_x = 18.5, .radius_y = 18.5, .rotation = 0, .large_arc = true, .sweep = true, .target = tvg.point(32, 64) } } },
                Node{ .vert = .{ .data = 64 } },
                Node{ .arc_ellipse = .{ .data = .{ .radius_x = 18.5, .radius_y = 18.5, .rotation = 0, .large_arc = true, .sweep = false, .target = tvg.point(48, 32) } } },
            },
        },
    });

    try writer.writeEndOfFile();
}
