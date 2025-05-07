//!
//! This module implements means to read/decode TVG files.
//!

const std = @import("std");
const tvg = @import("tinyvg.zig");

pub const Header = struct {
    version: u8,
    scale: tvg.Scale,
    color_encoding: tvg.ColorEncoding,
    coordinate_range: tvg.Range,
    width: u32,
    height: u32,
};

const Point = tvg.Point;
const Rectangle = tvg.Rectangle;
const Line = tvg.Line;
const Path = tvg.Path;
const StyleType = tvg.StyleType;
const Style = tvg.Style;
const Gradient = tvg.Gradient;

pub const DrawCommand = union(enum) {
    fill_polygon: FillPolygon,
    fill_rectangles: FillRectangles,
    fill_path: FillPath,

    draw_lines: DrawLines,
    draw_line_loop: DrawLineSegments,
    draw_line_strip: DrawLineSegments,
    draw_line_path: DrawPath,

    outline_fill_polygon: OutlineFillPolygon,
    outline_fill_rectangles: OutlineFillRectangles,
    outline_fill_path: OutlineFillPath,

    pub const FillPolygon = struct {
        style: Style,
        vertices: []Point,
    };

    pub const FillRectangles = struct {
        style: Style,
        rectangles: []Rectangle,
    };

    pub const FillPath = struct {
        style: Style,
        path: Path,
    };

    pub const OutlineFillPolygon = struct {
        fill_style: Style,
        line_style: Style,
        line_width: f32,
        vertices: []Point,
    };

    pub const OutlineFillRectangles = struct {
        fill_style: Style,
        line_style: Style,
        line_width: f32,
        rectangles: []Rectangle,
    };

    pub const OutlineFillPath = struct {
        fill_style: Style,
        line_style: Style,
        line_width: f32,
        path: Path,
    };

    pub const DrawLines = struct {
        style: Style,
        line_width: f32,
        lines: []Line,
    };

    pub const DrawLineSegments = struct {
        style: Style,
        line_width: f32,
        vertices: []Point,
    };

    pub const DrawPath = struct {
        style: Style,
        line_width: f32,
        path: Path,
    };
};

pub const ParseError = error{ EndOfStream, InvalidData, OutOfMemory };
pub const ParseHeaderError = ParseError || error{ UnsupportedColorFormat, UnsupportedVersion };

pub fn Parser(comptime Reader: type) type {
    return struct {
        const Self = @This();

        reader: Reader,
        allocator: std.mem.Allocator,
        temp_buffer: std.ArrayListAligned(u8, 16),
        end_of_document: bool = false,

        header: Header,
        color_table: []tvg.Color,

        pub fn init(allocator: std.mem.Allocator, reader: Reader) (Reader.Error || ParseHeaderError)!Self {
            var actual_magic_number: [2]u8 = undefined;
            reader.readNoEof(&actual_magic_number) catch return error.InvalidData;
            if (!std.mem.eql(u8, &actual_magic_number, &tvg.magic_number))
                return error.InvalidData;

            const version = reader.readByte() catch return error.InvalidData;

            var self = Self{
                .allocator = allocator,
                .reader = reader,
                .temp_buffer = std.ArrayListAligned(u8, 16).init(allocator),

                .header = undefined,
                .color_table = undefined,
            };

            switch (version) {
                1 => {
                    const ScaleAndFlags = packed struct {
                        scale: u4,
                        color_encoding: u2,
                        coordinate_range: u2,
                    };
                    comptime {
                        if (@sizeOf(ScaleAndFlags) != 1) @compileError("Invalid range!");
                    }

                    const scale_and_flags: ScaleAndFlags = @bitCast(try reader.readByte());

                    const scale: tvg.Scale = @enumFromInt(scale_and_flags.scale);
                    const color_encoding: tvg.ColorEncoding = @enumFromInt(scale_and_flags.color_encoding);
                    const range: tvg.Range = @enumFromInt(scale_and_flags.coordinate_range);

                    const width: u32 = switch (range) {
                        .reduced => mapZeroToMax(try reader.readInt(u8, .little)),
                        .default => mapZeroToMax(try reader.readInt(u16, .little)),
                        .enhanced => std.math.cast(u32, mapZeroToMax(try reader.readInt(u32, .little))) orelse return error.InvalidData,
                    };
                    const height: u32 = switch (range) {
                        .reduced => mapZeroToMax(try reader.readInt(u8, .little)),
                        .default => mapZeroToMax(try reader.readInt(u16, .little)),
                        .enhanced => std.math.cast(u32, mapZeroToMax(try reader.readInt(u32, .little))) orelse return error.InvalidData,
                    };

                    const color_count = try self.readUInt();

                    self.color_table = try allocator.alloc(tvg.Color, color_count);
                    errdefer allocator.free(self.color_table);

                    for (self.color_table) |*c| {
                        c.* = switch (color_encoding) {
                            .u8888 => tvg.Color{
                                .r = @as(f32, @floatFromInt(try reader.readInt(u8, .little))) / 255.0,
                                .g = @as(f32, @floatFromInt(try reader.readInt(u8, .little))) / 255.0,
                                .b = @as(f32, @floatFromInt(try reader.readInt(u8, .little))) / 255.0,
                                .a = @as(f32, @floatFromInt(try reader.readInt(u8, .little))) / 255.0,
                            },
                            .u565 => blk: {
                                const rgb = try reader.readInt(u16, .little);
                                break :blk tvg.Color{
                                    .r = @as(f32, @floatFromInt((rgb & 0x001F) >> 0)) / 31.0,
                                    .g = @as(f32, @floatFromInt((rgb & 0x07E0) >> 5)) / 63.0,
                                    .b = @as(f32, @floatFromInt((rgb & 0xF800) >> 11)) / 31.0,
                                    .a = 1.0,
                                };
                            },
                            .f32 => tvg.Color{
                                // TODO: Verify if this is platform independently correct:
                                .r = @as(f32, @bitCast(try reader.readInt(u32, .little))),
                                .g = @as(f32, @bitCast(try reader.readInt(u32, .little))),
                                .b = @as(f32, @bitCast(try reader.readInt(u32, .little))),
                                .a = @as(f32, @bitCast(try reader.readInt(u32, .little))),
                            },
                            .custom => return error.UnsupportedColorFormat,
                        };
                    }

                    self.header = Header{
                        .version = version,
                        .scale = scale,
                        .width = width,
                        .height = height,
                        .color_encoding = color_encoding,
                        .coordinate_range = range,
                    };
                },
                else => return error.UnsupportedVersion,
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.temp_buffer.deinit();
            self.allocator.free(self.color_table);
            self.* = undefined;
        }

        fn setTempStorage(self: *Self, comptime T: type, length: usize) ![]T {
            // temp_buffer is aligned to 16, so we don't have to worry about
            // alignment here
            try self.temp_buffer.resize(@sizeOf(T) * length);

            const items = std.mem.bytesAsSlice(T, self.temp_buffer.items[0..(@sizeOf(T) * length)]);
            std.debug.assert(items.len == length);
            return items;
        }

        fn setDualTempStorageReturn(T1: type, T2: type) type {
            return struct { first: []T1, second: []T2 };
        }

        fn setDualTempStorage(
            self: *Self,
            comptime T1: type,
            length1: usize,
            comptime T2: type,
            length2: usize,
        ) !setDualTempStorageReturn(T1, T2) {
            // temp_buffer is aligned to 16, so we don't have to worry about
            // alignment for T1
            try self.temp_buffer.resize(@sizeOf(T1) * length1 + @sizeOf(T2) * length2 + (@alignOf(T2) - 1));

            // T2 alignment could be larger than T1
            const offset = std.mem.alignForward(usize, @sizeOf(T1) * length1, @alignOf(T2));

            const result = setDualTempStorageReturn(T1, T2){
                .first = std.mem.bytesAsSlice(T1, self.temp_buffer.items[0 .. @sizeOf(T1) * length1]),
                .second = @as([]T2, @alignCast(std.mem.bytesAsSlice(T2, self.temp_buffer.items[offset..][0 .. @sizeOf(T2) * length2]))),
            };

            std.debug.assert(result.first.len == length1);
            std.debug.assert(result.second.len == length2);
            return result;
        }

        fn ValAndSize(comptime T: type) type {
            return struct { data: T, count: usize };
        }

        fn checkInit(comptime T: type, comptime fields: []const []const u8) void {
            inline for (fields) |fld| {
                if (!@hasField(T, fld))
                    @compileError("Invalid field");
            }

            if (fields.len != std.meta.fields(T).len) {
                @compileError("Uninitialized type");
            }
        }

        fn readFillHeader(self: *Self, primary_style_type: tvg.StyleType, comptime T: type, comptime uninit_field: []const u8) (Reader.Error || ParseError)!ValAndSize(T) {
            checkInit(T, &[_][]const u8{ "style", uninit_field });

            var value: T = undefined;

            const count = @as(usize, try self.readUInt()) + 1;
            value.style = try self.readStyle(primary_style_type);

            return ValAndSize(T){ .data = value, .count = count };
        }

        fn readLineHeader(self: *Self, primary_style_type: tvg.StyleType, comptime T: type, comptime uninit_field: []const u8) (Reader.Error || ParseError)!ValAndSize(T) {
            checkInit(T, &[_][]const u8{ "style", "line_width", uninit_field });

            var value: T = undefined;

            const count = @as(usize, try self.readUInt()) + 1;
            value.style = try self.readStyle(primary_style_type);
            value.line_width = try self.readUnit();

            return ValAndSize(T){ .data = value, .count = count };
        }

        fn readOutlineFillHeader(self: *Self, primary_style_type: tvg.StyleType, comptime T: type, comptime uninit_field: []const u8) (Reader.Error || ParseError)!ValAndSize(T) {
            checkInit(T, &[_][]const u8{ "fill_style", "line_style", "line_width", uninit_field });

            var value: T = undefined;

            const count_and_grad: CountAndStyleTag = @bitCast(try self.readByte());

            const count = count_and_grad.getCount();

            value.fill_style = try self.readStyle(primary_style_type);
            value.line_style = try self.readStyle(try count_and_grad.getStyleType());
            value.line_width = try self.readUnit();

            return ValAndSize(T){ .data = value, .count = count };
        }

        pub fn next(self: *Self) (Reader.Error || ParseError)!?DrawCommand {
            if (self.end_of_document)
                return null;
            const command_byte = try self.reader.readByte();
            const primary_style_type = std.meta.intToEnum(tvg.StyleType, @as(u2, @truncate(command_byte >> 6))) catch return error.InvalidData;
            const command: tvg.Command = @enumFromInt(@as(u6, @truncate(command_byte)));

            return switch (command) {
                .end_of_document => {
                    self.end_of_document = true;
                    return null;
                },
                .fill_polygon => blk: {
                    var data = try self.readFillHeader(primary_style_type, DrawCommand.FillPolygon, "vertices");

                    data.data.vertices = try self.setTempStorage(Point, data.count);
                    for (data.data.vertices) |*pt| {
                        pt.x = try self.readUnit();
                        pt.y = try self.readUnit();
                    }

                    break :blk DrawCommand{ .fill_polygon = data.data };
                },
                .fill_rectangles => blk: {
                    var data = try self.readFillHeader(primary_style_type, DrawCommand.FillRectangles, "rectangles");

                    data.data.rectangles = try self.setTempStorage(Rectangle, data.count);
                    for (data.data.rectangles) |*rect| {
                        rect.x = try self.readUnit();
                        rect.y = try self.readUnit();
                        rect.width = try self.readUnit();
                        rect.height = try self.readUnit();
                        if (rect.width <= 0 or rect.height <= 0)
                            return error.InvalidData;
                    }

                    break :blk DrawCommand{ .fill_rectangles = data.data };
                },
                .fill_path => blk: {
                    var data = try self.readFillHeader(primary_style_type, DrawCommand.FillPath, "path");

                    data.data.path = try self.readPath(data.count);

                    break :blk DrawCommand{ .fill_path = data.data };
                },
                .draw_lines => blk: {
                    var data = try self.readLineHeader(primary_style_type, DrawCommand.DrawLines, "lines");

                    data.data.lines = try self.setTempStorage(Line, data.count);
                    for (data.data.lines) |*line| {
                        line.start.x = try self.readUnit();
                        line.start.y = try self.readUnit();
                        line.end.x = try self.readUnit();
                        line.end.y = try self.readUnit();
                    }

                    break :blk DrawCommand{ .draw_lines = data.data };
                },
                .draw_line_loop => blk: {
                    var data = try self.readLineHeader(primary_style_type, DrawCommand.DrawLineSegments, "vertices");

                    data.data.vertices = try self.setTempStorage(Point, data.count);
                    for (data.data.vertices) |*point| {
                        point.x = try self.readUnit();
                        point.y = try self.readUnit();
                    }

                    break :blk DrawCommand{ .draw_line_loop = data.data };
                },
                .draw_line_strip => blk: {
                    var data = try self.readLineHeader(primary_style_type, DrawCommand.DrawLineSegments, "vertices");

                    data.data.vertices = try self.setTempStorage(Point, data.count);
                    for (data.data.vertices) |*point| {
                        point.x = try self.readUnit();
                        point.y = try self.readUnit();
                    }

                    break :blk DrawCommand{ .draw_line_strip = data.data };
                },
                .draw_line_path => blk: {
                    var data = try self.readLineHeader(primary_style_type, DrawCommand.DrawPath, "path");

                    data.data.path = try self.readPath(data.count);

                    break :blk DrawCommand{ .draw_line_path = data.data };
                },
                .outline_fill_polygon => blk: {
                    var data = try self.readOutlineFillHeader(primary_style_type, DrawCommand.OutlineFillPolygon, "vertices");

                    data.data.vertices = try self.setTempStorage(Point, data.count);
                    for (data.data.vertices) |*pt| {
                        pt.x = try self.readUnit();
                        pt.y = try self.readUnit();
                    }

                    break :blk DrawCommand{ .outline_fill_polygon = data.data };
                },
                .outline_fill_rectangles => blk: {
                    var data = try self.readOutlineFillHeader(primary_style_type, DrawCommand.OutlineFillRectangles, "rectangles");

                    data.data.rectangles = try self.setTempStorage(Rectangle, data.count);
                    for (data.data.rectangles) |*rect| {
                        rect.x = try self.readUnit();
                        rect.y = try self.readUnit();
                        rect.width = try self.readUnit();
                        rect.height = try self.readUnit();
                        if (rect.width <= 0 or rect.height <= 0)
                            return error.InvalidData;
                    }

                    break :blk DrawCommand{ .outline_fill_rectangles = data.data };
                },
                .outline_fill_path => blk: {
                    var data = try self.readOutlineFillHeader(primary_style_type, DrawCommand.OutlineFillPath, "path");

                    data.data.path = try self.readPath(data.count);

                    break :blk DrawCommand{ .outline_fill_path = data.data };
                },
                _ => {
                    return error.InvalidData;
                },
            };
        }

        fn readPath(self: *Self, path_length: usize) !Path {
            var segment_lengths: [1024]usize = undefined;
            std.debug.assert(path_length <= segment_lengths.len);

            var total_node_count: usize = 0;

            {
                var i: usize = 0;
                while (i < path_length) : (i += 1) {
                    segment_lengths[i] = @as(usize, try self.readUInt()) + 1;
                    total_node_count += segment_lengths[i];
                }
            }

            const buffers = try self.setDualTempStorage(
                Path.Segment,
                path_length,
                Path.Node,
                total_node_count,
            );

            var segment_start: usize = 0;
            for (buffers.first, 0..) |*segment, i| {
                const segment_len = segment_lengths[i];

                segment.start.x = try self.readUnit();
                segment.start.y = try self.readUnit();

                const commands = buffers.second[segment_start..][0..segment_len];
                for (commands) |*node| {
                    node.* = try self.readNode();
                }
                segment.commands = commands;

                segment_start += segment_len;
            }
            std.debug.assert(buffers.first.len == path_length);
            std.debug.assert(segment_start == total_node_count);

            return Path{
                .segments = buffers.first,
            };
        }

        fn readNode(self: *Self) !Path.Node {
            const Tag = packed struct {
                type: Path.Type,
                padding0: u1 = 0,
                has_line_width: bool,
                padding1: u3 = 0,
            };
            const tag: Tag = @bitCast(try self.readByte());

            const line_width: ?f32 = if (tag.has_line_width)
                try self.readUnit()
            else
                null;

            const PathNode = Path.Node;

            return switch (tag.type) {
                .line => PathNode{ .line = PathNode.NodeData(Point).init(line_width, .{
                    .x = try self.readUnit(),
                    .y = try self.readUnit(),
                }) },
                .horiz => PathNode{ .horiz = PathNode.NodeData(f32).init(line_width, try self.readUnit()) },
                .vert => PathNode{ .vert = PathNode.NodeData(f32).init(line_width, try self.readUnit()) },
                .bezier => PathNode{ .bezier = PathNode.NodeData(PathNode.Bezier).init(line_width, PathNode.Bezier{
                    .c0 = Point{
                        .x = try self.readUnit(),
                        .y = try self.readUnit(),
                    },
                    .c1 = Point{
                        .x = try self.readUnit(),
                        .y = try self.readUnit(),
                    },
                    .p1 = Point{
                        .x = try self.readUnit(),
                        .y = try self.readUnit(),
                    },
                }) },
                .arc_circle => blk: {
                    const flags = try self.readByte();
                    break :blk PathNode{ .arc_circle = PathNode.NodeData(PathNode.ArcCircle).init(line_width, PathNode.ArcCircle{
                        .radius = try self.readUnit(),
                        .large_arc = (flags & 1) != 0,
                        .sweep = (flags & 2) != 0,
                        .target = Point{
                            .x = try self.readUnit(),
                            .y = try self.readUnit(),
                        },
                    }) };
                },
                .arc_ellipse => blk: {
                    const flags = try self.readByte();
                    break :blk PathNode{ .arc_ellipse = PathNode.NodeData(PathNode.ArcEllipse).init(line_width, PathNode.ArcEllipse{
                        .radius_x = try self.readUnit(),
                        .radius_y = try self.readUnit(),
                        .rotation = try self.readUnit(),
                        .large_arc = (flags & 1) != 0,
                        .sweep = (flags & 2) != 0,
                        .target = Point{
                            .x = try self.readUnit(),
                            .y = try self.readUnit(),
                        },
                    }) };
                },
                .quadratic_bezier => PathNode{ .quadratic_bezier = PathNode.NodeData(PathNode.QuadraticBezier).init(line_width, PathNode.QuadraticBezier{
                    .c = Point{
                        .x = try self.readUnit(),
                        .y = try self.readUnit(),
                    },
                    .p1 = Point{
                        .x = try self.readUnit(),
                        .y = try self.readUnit(),
                    },
                }) },
                .close => PathNode{ .close = PathNode.NodeData(void).init(line_width, {}) },
            };
        }

        fn readStyle(self: *Self, kind: StyleType) !Style {
            return switch (kind) {
                .flat => Style{ .flat = try self.readUInt() },
                .linear => Style{ .linear = try self.readGradient() },
                .radial => Style{ .radial = try self.readGradient() },
            };
        }

        fn readGradient(self: *Self) !Gradient {
            var grad: Gradient = undefined;
            grad.point_0 = Point{
                .x = try self.readUnit(),
                .y = try self.readUnit(),
            };
            grad.point_1 = Point{
                .x = try self.readUnit(),
                .y = try self.readUnit(),
            };
            grad.color_0 = try self.readUInt();
            grad.color_1 = try self.readUInt();

            if (grad.color_0 >= self.color_table.len)
                return error.InvalidData;
            if (grad.color_1 >= self.color_table.len)
                return error.InvalidData;

            return grad;
        }

        fn readUInt(self: *Self) error{InvalidData}!u32 {
            var byte_count: u8 = 0;
            var result: u32 = 0;
            while (true) {
                const byte = self.reader.readByte() catch return error.InvalidData;
                // check for too long *and* out of range in a single check
                if (byte_count == 4 and (byte & 0xF0) != 0)
                    return error.InvalidData;
                const val = @as(u32, (byte & 0x7F)) << @as(u5, @intCast((7 * byte_count)));
                result |= val;
                if ((byte & 0x80) == 0)
                    break;
                byte_count += 1;
                std.debug.assert(byte_count <= 5);
            }
            return result;
        }

        fn readUnit(self: *const Self) !f32 {
            const unit: tvg.Unit = switch (self.header.coordinate_range) {
                .reduced => @enumFromInt(try self.reader.readInt(i8, .little)),
                .default => @enumFromInt(try self.reader.readInt(i16, .little)),
                .enhanced => @enumFromInt(try self.reader.readInt(i32, .little)),
            };
            return unit.toFloat(self.header.scale);
        }

        fn readByte(self: *Self) !u8 {
            return try self.reader.readByte();
        }

        fn readU16(self: *Self) !u16 {
            return try self.reader.readInt(u16, .little);
        }
    };
}

const CountAndStyleTag = packed struct {
    const Self = @This();
    raw_count: u6,
    style_kind: u2,

    pub fn getCount(self: *const Self) usize {
        return @as(usize, self.raw_count) + 1;
    }

    pub fn getStyleType(self: *const Self) !StyleType {
        return convertStyleType(self.style_kind);
    }
};

fn convertStyleType(value: u2) !StyleType {
    return switch (value) {
        @intFromEnum(StyleType.flat) => StyleType.flat,
        @intFromEnum(StyleType.linear) => StyleType.linear,
        @intFromEnum(StyleType.radial) => StyleType.radial,
        else => error.InvalidData,
    };
}

fn MapZeroToMax(comptime T: type) type {
    const info = @typeInfo(T).int;
    return std.meta.Int(.unsigned, info.bits + 1);
}
fn mapZeroToMax(value: anytype) MapZeroToMax(@TypeOf(value)) {
    return if (value == 0)
        std.math.maxInt(@TypeOf(value)) + 1
    else
        value;
}

test "mapZeroToMax" {
    try std.testing.expectEqual(@as(u9, 256), mapZeroToMax(@as(u8, 0)));
    try std.testing.expectEqual(@as(u17, 65536), mapZeroToMax(@as(u16, 0)));
}

// test "readUInt" {
//     const T = struct {
//         fn run(seq: []const u8) !u32 {
//             var stream = std.io.fixedBufferStream(seq);
//             return try readUInt(stream.reader());
//         }
//     };

//     std.testing.expectEqual(@as(u32, 0x00), try T.run(&[_]u8{0x00}));
//     std.testing.expectEqual(@as(u32, 0x40), try T.run(&[_]u8{0x40}));
//     std.testing.expectEqual(@as(u32, 0x80), try T.run(&[_]u8{ 0x80, 0x01 }));
//     std.testing.expectEqual(@as(u32, 0x100000), try T.run(&[_]u8{ 0x80, 0x80, 0x40 }));
//     std.testing.expectEqual(@as(u32, 0x8000_0000), try T.run(&[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x08 }));
//     std.testing.expectError(error.InvalidData, T.run(&[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x10 })); // out of range
//     std.testing.expectError(error.InvalidData, T.run(&[_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x10 })); // too long
// }

//test "coverage test" {
//    var source_buf: [2048]u8 = undefined;
//    var stream = std.io.fixedBufferStream(&source_buf);
//
//    @import("../data/ground-truth.zig").writeEverything(stream.writer(), .default) catch unreachable;
//
//    try stream.seekTo(0);
//
//    var parser = try Parser(@TypeOf(stream).Reader).init(std.testing.allocator, stream.reader());
//    defer parser.deinit();
//
//    while (try parser.next()) |node| {
//        _ = node;
//    }
//}
