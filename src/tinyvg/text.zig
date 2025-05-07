//! Implements conversion from and to text representation

const std = @import("std");
const tvg = @import("tinyvg.zig");

/// Renders a binary TinyVG into its text representation.
/// - `allocator` will be used for temporary allocations in the TVG parser.
/// - `tvg_buffer` provides a binary TinyVG file
/// - `writer` will receive the UTF-8 encoded SVG text.
pub fn renderBinary(allocator: std.mem.Allocator, tvg_buffer: []const u8, writer: anytype) !void {
    var stream = std.io.fixedBufferStream(tvg_buffer);

    var parser = try tvg.parse(allocator, stream.reader());
    defer parser.deinit();

    return try renderStream(&parser, writer);
}

/// Renders a TinyVG command stream into the TinyVG text representation.
/// - `parser` is a pointer to a `tvg.parsing.Parser(Reader)`
/// - `writer` will receive the UTF-8 encoded TinyVG text.
pub fn renderStream(parser: anytype, writer: anytype) !void {
    try writer.print("(tvg {d}\n", .{parser.header.version});
    try writer.print("  ({d} {d} {s} {s} {s})\n", .{
        parser.header.width,
        parser.header.height,
        @tagName(parser.header.scale),
        @tagName(parser.header.color_encoding),
        @tagName(parser.header.coordinate_range),
    });

    try writer.writeAll("  (\n");
    for (parser.color_table) |color| {
        if (color.a != 1.0) {
            try writer.print("    ({d:.3} {d:.3} {d:.3} {d:.3})\n", .{
                color.r, color.g, color.b, color.a,
            });
        } else {
            try writer.print("    ({d:.3} {d:.3} {d:.3})\n", .{
                color.r, color.g, color.b,
            });
        }
    }
    try writer.writeAll("  )\n");

    try writer.writeAll("  (\n");
    while (try parser.next()) |command| {
        try writer.print("    (\n      {s}", .{@tagName(command)});
        switch (command) {
            .fill_rectangles => |data| {
                try renderStyle("\n      ", writer, data.style);
                try renderRectangles("\n      ", writer, data.rectangles);
            },

            .outline_fill_rectangles => |data| {
                try renderStyle("\n      ", writer, data.fill_style);
                try renderStyle("\n      ", writer, data.line_style);
                try writer.print("\n      {d}", .{data.line_width});
                try renderRectangles("\n      ", writer, data.rectangles);
            },

            .draw_lines => |data| {
                try renderStyle("\n      ", writer, data.style);
                try writer.print("\n      {d}", .{data.line_width});
                try renderLines("\n      ", writer, data.lines);
            },

            .draw_line_loop => |data| {
                try renderStyle("\n      ", writer, data.style);
                try writer.print("\n      {d}", .{data.line_width});
                try renderPoints("\n      ", writer, data.vertices);
            },

            .draw_line_strip => |data| {
                try renderStyle("\n      ", writer, data.style);
                try writer.print("\n      {d}", .{data.line_width});
                try renderPoints("\n      ", writer, data.vertices);
            },

            .fill_polygon => |data| {
                try renderStyle("\n      ", writer, data.style);
                try renderPoints("\n      ", writer, data.vertices);
            },

            .outline_fill_polygon => |data| {
                try renderStyle("\n      ", writer, data.fill_style);
                try renderStyle("\n      ", writer, data.line_style);
                try writer.print("\n      {d}", .{data.line_width});
                try renderPoints("\n      ", writer, data.vertices);
            },

            .draw_line_path => |data| {
                try renderStyle("\n      ", writer, data.style);
                try writer.print("\n      {d}", .{data.line_width});
                try renderPath("\n      ", writer, data.path);
            },

            .fill_path => |data| {
                try renderStyle("\n      ", writer, data.style);
                try renderPath("\n      ", writer, data.path);
            },

            .outline_fill_path => |data| {
                try renderStyle("\n      ", writer, data.fill_style);
                try renderStyle("\n      ", writer, data.line_style);
                try writer.print("\n      {d}", .{data.line_width});
                try renderPath("\n      ", writer, data.path);
            },
        }
        try writer.writeAll("\n    )\n");
    }
    try writer.writeAll("  )\n");

    try writer.writeAll(")\n");
}

fn renderRectangles(line_prefix: []const u8, writer: anytype, rects: []const tvg.Rectangle) !void {
    try writer.print("{s}(", .{line_prefix});
    for (rects) |r| {
        try writer.print("{s}  ({d} {d} {d} {d})", .{
            line_prefix, r.x, r.y, r.width, r.height,
        });
    }
    try writer.print("{s})", .{line_prefix});
}

fn renderLines(line_prefix: []const u8, writer: anytype, lines: []const tvg.Line) !void {
    try writer.print("{s}(", .{line_prefix});
    for (lines) |l| {
        try writer.print("{s}  (({d} {d}) ({d} {d}))", .{
            line_prefix, l.start.x, l.start.y, l.end.x, l.end.y,
        });
    }
    try writer.print("{s})", .{line_prefix});
}

fn renderPoints(line_prefix: []const u8, writer: anytype, point: []const tvg.Point) !void {
    try writer.print("{s}(", .{line_prefix});
    for (point) |p| {
        try writer.print("{s}  ({d} {d})", .{
            line_prefix, p.x, p.y,
        });
    }
    try writer.print("{s})", .{line_prefix});
}

fn renderPath(line_prefix: []const u8, writer: anytype, path: tvg.Path) !void {
    try writer.print("{s}(", .{line_prefix});
    for (path.segments) |segment| {
        try writer.print("{s}  ({d} {d}){s}  (", .{ line_prefix, segment.start.x, segment.start.y, line_prefix });
        for (segment.commands) |node| {
            try writer.print("{s}    ", .{line_prefix});
            try renderPathNode(writer, node);
        }
        try writer.print("{s}  )", .{line_prefix});
    }
    try writer.print("{s})", .{line_prefix});
}

fn renderPathNode(writer: anytype, node: tvg.Path.Node) !void {
    const LineWidth = struct {
        lw: ?f32,

        pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writ: anytype) !void {
            _ = fmt;
            _ = options;
            if (self.lw) |lw| {
                try writ.print("{d}", .{lw});
            } else {
                try writ.writeAll("-");
            }
        }

        fn init(lw: ?f32) @This() {
            return @This(){ .lw = lw };
        }
    };
    const initLW = LineWidth.init;
    switch (node) {
        .line => |line| try writer.print("(line {} {d} {d})", .{ initLW(line.line_width), line.data.x, line.data.y }),
        .horiz => |horiz| try writer.print("(horiz {} {d})", .{ initLW(horiz.line_width), horiz.data }),
        .vert => |vert| try writer.print("(vert {} {d})", .{ initLW(vert.line_width), vert.data }),
        .bezier => |bezier| try writer.print("(bezier {} ({d} {d}) ({d} {d}) ({d} {d}))", .{
            initLW(bezier.line_width),
            bezier.data.c0.x,
            bezier.data.c0.y,
            bezier.data.c1.x,
            bezier.data.c1.y,
            bezier.data.p1.x,
            bezier.data.p1.y,
        }),
        .quadratic_bezier => |bezier| try writer.print("(quadratic_bezier {} ({d} {d}) ({d} {d}))", .{
            initLW(bezier.line_width),
            bezier.data.c.x,
            bezier.data.c.y,
            bezier.data.p1.x,
            bezier.data.p1.y,
        }),
        .arc_circle => |arc_circle| try writer.print("(arc_circle {} {d} {} {} ({d} {d}))", .{
            initLW(arc_circle.line_width),
            arc_circle.data.radius,
            arc_circle.data.large_arc,
            arc_circle.data.sweep,
            arc_circle.data.target.x,
            arc_circle.data.target.y,
        }),
        .arc_ellipse => |arc_ellipse| try writer.print("(arc_ellipse {} {d} {d} {d} {} {} ({d} {d}))", .{
            initLW(arc_ellipse.line_width),
            arc_ellipse.data.radius_x,
            arc_ellipse.data.radius_y,
            arc_ellipse.data.rotation,
            arc_ellipse.data.large_arc,
            arc_ellipse.data.sweep,
            arc_ellipse.data.target.x,
            arc_ellipse.data.target.y,
        }),
        .close => |close| try writer.print("(close {})", .{initLW(close.line_width)}),
        // else => unreachable,
    }
}

fn renderStyle(line_prefix: []const u8, writer: anytype, style: tvg.Style) !void {
    switch (style) {
        .flat => |color| try writer.print("{s}(flat {d})", .{ line_prefix, color }),
        .linear, .radial => |grad| {
            try writer.print("{s}({s} ({d} {d}) ({d} {d}) {d} {d} )", .{
                line_prefix,
                @tagName(style),
                grad.point_0.x,
                grad.point_0.y,
                grad.point_1.x,
                grad.point_1.y,
                grad.color_0,
                grad.color_1,
            });
        },
    }
}

/// Parses the TinyVG text representation and renders a binary file.
/// - `allocator` is used for temporary allocations inside the parser.
/// - `source` contains the textual TinyVG file.
/// - `writer` receives the binary file in small portions.
pub fn parse(allocator: std.mem.Allocator, source: []const u8, writer: anytype) !void {
    var builder = tvg.builder.create(writer);
    const Builder = @TypeOf(builder);

    const Parser = struct {
        const Parser = @This();
        const ptk = @import("ptk");

        const TokenType = enum {
            begin,
            end,
            space,
            atom,
        };
        const Pattern = ptk.Pattern(TokenType);
        const Tokenizer = ptk.Tokenizer(TokenType, &[_]Pattern{
            Pattern.create(.space, ptk.matchers.whitespace),
            Pattern.create(.begin, ptk.matchers.literal("(")),
            Pattern.create(.end, ptk.matchers.literal(")")),
            Pattern.create(.atom, matchAtom),
        });

        const Token = union(enum) {
            begin,
            end,
            atom: []const u8,

            pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writ: anytype) !void {
                _ = fmt;
                _ = options;
                switch (self) {
                    .begin => try writ.writeAll("'('"),
                    .end => try writ.writeAll("')'"),
                    .atom => |text| try writ.print("atom('{s}')", .{text}),
                }
            }
        };

        builder: *Builder,
        tokenizer: Tokenizer,
        allocator: std.mem.Allocator,

        fn next(self: *Parser) !?Token {
            while (true) {
                const maybe_tok = try self.tokenizer.next();
                if (maybe_tok) |tok| {
                    const token = switch (tok.type) {
                        .begin => .begin,
                        .end => .end,
                        .atom => Token{ .atom = tok.text },
                        .space => continue,
                    };
                    // std.debug.print("{}\n", .{token});
                    return token;
                } else {
                    return null;
                }
            }
        }

        fn matchAtom(slice: []const u8) ?usize {
            for (slice, 0..) |c, i| {
                if (c == ')' or c == '(' or std.ascii.isWhitespace(c))
                    return i;
            }
            return slice.len;
        }

        fn expectAny(self: *Parser) !Token {
            return (try self.next()) orelse return error.SyntaxError;
        }

        fn expectBegin(self: *Parser) !void {
            const tok = (try self.next()) orelse return error.SyntaxError;
            if (tok != .begin)
                return error.SyntaxError;
        }

        fn expectEnd(self: *Parser) !void {
            const tok = (try self.next()) orelse return error.SyntaxError;
            if (tok != .end)
                return error.SyntaxError;
        }

        fn expectAtom(self: *Parser) ![]const u8 {
            const tok = (try self.next()) orelse return error.SyntaxError;
            if (tok != .atom)
                return unexpectedToken(tok);
            return tok.atom;
        }

        fn unexpectedToken(tok: Token) error{SyntaxError} {
            std.log.err("unexpected token: {}", .{tok});
            return error.SyntaxError;
        }

        fn unexpectedText(str: []const u8) error{SyntaxError} {
            std.log.err("unexpected text: '{s}'", .{str});
            return error.SyntaxError;
        }

        fn parseNumber(self: *Parser) !f32 {
            const text = try self.expectAtom();
            return std.fmt.parseFloat(f32, text) catch return unexpectedText(text);
        }

        fn parseInteger(self: *Parser, comptime I: type) !I {
            const text = try self.expectAtom();
            return std.fmt.parseInt(I, text, 0) catch return unexpectedText(text);
        }

        fn parseEnum(self: *Parser, comptime E: type) !E {
            const text = try self.expectAtom();
            return std.meta.stringToEnum(E, text) orelse return unexpectedText(text);
        }

        fn parseBoolean(self: *Parser) !bool {
            const text = try self.expectAtom();
            return if (std.mem.eql(u8, text, "true"))
                true
            else if (std.mem.eql(u8, text, "false"))
                false
            else
                return unexpectedText(text);
        }

        fn parseOptionalNumber(self: *Parser) !?f32 {
            const text = try self.expectAtom();
            if (std.mem.eql(u8, text, "-")) {
                return null;
            }
            return std.fmt.parseFloat(f32, text) catch return unexpectedText(text);
        }

        fn parseHeader(self: *Parser) !tvg.parsing.Header {
            try self.expectBegin();

            const width = try self.parseInteger(u32);
            const height = try self.parseInteger(u32);
            const scale = try self.parseEnum(tvg.Scale);
            const format = try self.parseEnum(tvg.ColorEncoding);
            const range = try self.parseEnum(tvg.Range);

            try self.expectEnd();

            return tvg.parsing.Header{
                .version = 1,
                .width = width,
                .height = height,
                .scale = scale,
                .color_encoding = format,
                .coordinate_range = range,
            };
        }

        fn parseColorTable(self: *Parser) ![]tvg.Color {
            try self.expectBegin();

            var colors = std.ArrayList(tvg.Color).init(self.allocator);
            defer colors.deinit();

            while (true) {
                const item = try self.expectAny();
                if (item == .atom)
                    return error.SyntaxError;
                if (item == .end)
                    break;

                const r = try self.parseNumber();
                const g = try self.parseNumber();
                const b = try self.parseNumber();

                const maybe_a = try self.expectAny();
                if (maybe_a == .begin)
                    return error.SyntaxError;

                const a = if (maybe_a == .atom) blk: {
                    const a = try std.fmt.parseFloat(f32, maybe_a.atom);
                    try self.expectEnd();
                    break :blk a;
                } else @as(f32, 1.0);

                try colors.append(tvg.Color{ .r = r, .g = g, .b = b, .a = a });
            }

            return colors.toOwnedSlice();
        }

        fn parsePoint(self: *Parser) !tvg.Point {
            try self.expectBegin();

            const x = try self.parseNumber();
            const y = try self.parseNumber();

            try self.expectEnd();
            return tvg.point(x, y);
        }

        fn parseStyle(self: *Parser) !tvg.Style {
            try self.expectBegin();

            const style_type = try self.parseEnum(tvg.StyleType);
            const style = switch (style_type) {
                .flat => tvg.Style{
                    .flat = try self.parseInteger(u32),
                },
                .linear => tvg.Style{
                    .linear = tvg.Gradient{
                        .point_0 = try self.parsePoint(),
                        .point_1 = try self.parsePoint(),
                        .color_0 = try self.parseInteger(u32),
                        .color_1 = try self.parseInteger(u32),
                    },
                },
                .radial => tvg.Style{
                    .radial = tvg.Gradient{
                        .point_0 = try self.parsePoint(),
                        .point_1 = try self.parsePoint(),
                        .color_0 = try self.parseInteger(u32),
                        .color_1 = try self.parseInteger(u32),
                    },
                },
            };

            try self.expectEnd();

            return style;
        }

        fn readRectangles(self: *Parser) !std.ArrayList(tvg.Rectangle) {
            var items = std.ArrayList(tvg.Rectangle).init(self.allocator);
            errdefer items.deinit();

            try self.expectBegin();

            while (true) {
                const item = try self.expectAny();
                if (item == .atom)
                    return error.SyntaxError;
                if (item == .end)
                    break;

                const x = try self.parseNumber();
                const y = try self.parseNumber();
                const width = try self.parseNumber();
                const height = try self.parseNumber();

                try self.expectEnd();

                try items.append(tvg.rectangle(x, y, width, height));
            }

            return items;
        }

        fn readLines(self: *Parser) !std.ArrayList(tvg.Line) {
            var items = std.ArrayList(tvg.Line).init(self.allocator);
            errdefer items.deinit();

            try self.expectBegin();

            while (true) {
                const item = try self.expectAny();
                if (item == .atom)
                    return error.SyntaxError;
                if (item == .end)
                    break;

                const p0 = try self.parsePoint();
                const p1 = try self.parsePoint();

                try self.expectEnd();

                try items.append(tvg.line(p0, p1));
            }

            return items;
        }

        fn readPoints(self: *Parser) !std.ArrayList(tvg.Point) {
            var items = std.ArrayList(tvg.Point).init(self.allocator);
            errdefer items.deinit();

            try self.expectBegin();

            while (true) {
                const item = try self.expectAny();
                if (item == .atom)
                    return error.SyntaxError;
                if (item == .end)
                    break;

                const x = try self.parseNumber();
                const y = try self.parseNumber();

                try self.expectEnd();

                try items.append(tvg.point(x, y));
            }

            return items;
        }

        const Path = struct {
            arena: std.heap.ArenaAllocator,
            segments: []tvg.Path.Segment,

            fn deinit(self: *Path) void {
                self.arena.deinit();
                self.* = undefined;
            }
        };

        fn readPath(self: *Parser) !Path {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            errdefer arena.deinit();

            var segments = std.ArrayList(tvg.Path.Segment).init(arena.allocator());

            try self.expectBegin();

            while (true) {
                const head = try self.expectAny();
                switch (head) {
                    .end => break,
                    .atom => return error.SyntaxError,
                    .begin => {
                        const segment = try segments.addOne();

                        const x = try self.parseNumber();
                        const y = try self.parseNumber();

                        segment.start = tvg.point(x, y);
                        try self.expectEnd();

                        try self.expectBegin();

                        var elements = std.ArrayList(tvg.Path.Node).init(arena.allocator());

                        while (true) {
                            const cmd_start = try self.expectAny();
                            switch (cmd_start) {
                                .end => break,
                                .atom => return error.SyntaxError,
                                .begin => {
                                    const command = try self.parseEnum(tvg.Path.Type);
                                    const node: tvg.Path.Node = switch (command) {
                                        .line => tvg.Path.Node{ .line = .{ .line_width = try self.parseOptionalNumber(), .data = tvg.point(
                                            try self.parseNumber(),
                                            try self.parseNumber(),
                                        ) } },
                                        .horiz => tvg.Path.Node{ .horiz = .{ .line_width = try self.parseOptionalNumber(), .data = try self.parseNumber() } },
                                        .vert => tvg.Path.Node{ .vert = .{ .line_width = try self.parseOptionalNumber(), .data = try self.parseNumber() } },
                                        .bezier => tvg.Path.Node{ .bezier = .{ .line_width = try self.parseOptionalNumber(), .data = .{
                                            .c0 = try self.parsePoint(),
                                            .c1 = try self.parsePoint(),
                                            .p1 = try self.parsePoint(),
                                        } } },
                                        .quadratic_bezier => tvg.Path.Node{ .quadratic_bezier = .{ .line_width = try self.parseOptionalNumber(), .data = .{
                                            .c = try self.parsePoint(),
                                            .p1 = try self.parsePoint(),
                                        } } },
                                        .arc_circle => tvg.Path.Node{ .arc_circle = .{ .line_width = try self.parseOptionalNumber(), .data = .{
                                            .radius = try self.parseNumber(),
                                            .large_arc = try self.parseBoolean(),
                                            .sweep = try self.parseBoolean(),
                                            .target = try self.parsePoint(),
                                        } } },
                                        .arc_ellipse => tvg.Path.Node{
                                            .arc_ellipse = .{
                                                .line_width = try self.parseOptionalNumber(),
                                                .data = .{
                                                    .radius_x = try self.parseNumber(),
                                                    .radius_y = try self.parseNumber(),
                                                    .rotation = try self.parseNumber(),
                                                    .large_arc = try self.parseBoolean(),
                                                    .sweep = try self.parseBoolean(),
                                                    .target = try self.parsePoint(),
                                                },
                                            },
                                        },
                                        .close => tvg.Path.Node{ .close = .{ .line_width = try self.parseOptionalNumber(), .data = {} } },
                                    };
                                    try self.expectEnd();
                                    try elements.append(node);
                                },
                            }
                        }
                        segment.commands = try elements.toOwnedSlice();
                    },
                }
            }

            return Path{
                .arena = arena,
                .segments = try segments.toOwnedSlice(),
            };
        }

        fn parse(self: *Parser) !void {
            try self.expectBegin();

            if (!std.mem.eql(u8, "tvg", try self.expectAtom()))
                return error.SyntaxError;

            if ((try self.parseInteger(u8)) != 1)
                return error.UnsupportedVersion;

            const header = try self.parseHeader();

            try self.builder.writeHeader(header.width, header.height, header.scale, header.color_encoding, header.coordinate_range);

            const color_table = try self.parseColorTable();
            defer self.allocator.free(color_table);

            try self.builder.writeColorTable(color_table);

            try self.expectBegin();
            while (true) {
                const start_token = try self.expectAny();
                switch (start_token) {
                    .atom => return error.SyntaxError,
                    .end => break,
                    .begin => {
                        const command = try self.parseEnum(tvg.Command);
                        switch (command) {
                            .fill_polygon => {
                                const style = try self.parseStyle();

                                var points = try self.readPoints();
                                defer points.deinit();

                                try self.builder.writeFillPolygon(style, points.items);
                            },

                            .fill_rectangles => {
                                const style = try self.parseStyle();
                                var rects = try self.readRectangles();
                                defer rects.deinit();

                                try self.builder.writeFillRectangles(style, rects.items);
                            },

                            .fill_path => {
                                const style = try self.parseStyle();

                                var path = try self.readPath();
                                defer path.deinit();

                                try self.builder.writeFillPath(style, path.segments);
                            },

                            .draw_lines => {
                                const style = try self.parseStyle();
                                const line_width = try self.parseNumber();

                                var lines = try self.readLines();
                                defer lines.deinit();

                                try self.builder.writeDrawLines(style, line_width, lines.items);
                            },

                            .draw_line_loop => {
                                const style = try self.parseStyle();
                                const line_width = try self.parseNumber();

                                var points = try self.readPoints();
                                defer points.deinit();

                                try self.builder.writeDrawLineLoop(style, line_width, points.items);
                            },

                            .draw_line_strip => {
                                const style = try self.parseStyle();
                                const line_width = try self.parseNumber();

                                var points = try self.readPoints();
                                defer points.deinit();

                                try self.builder.writeDrawLineStrip(style, line_width, points.items);
                            },
                            .draw_line_path => {
                                const style = try self.parseStyle();
                                const line_width = try self.parseNumber();

                                const path = try self.readPath();

                                try self.builder.writeDrawPath(style, line_width, path.segments);
                            },

                            .outline_fill_polygon => {
                                const fill_style = try self.parseStyle();
                                const line_style = try self.parseStyle();
                                const line_width = try self.parseNumber();

                                var points = try self.readPoints();
                                defer points.deinit();

                                try self.builder.writeOutlineFillPolygon(fill_style, line_style, line_width, points.items);
                            },

                            .outline_fill_rectangles => {
                                const fill_style = try self.parseStyle();
                                const line_style = try self.parseStyle();
                                const line_width = try self.parseNumber();

                                var rects = try self.readRectangles();
                                defer rects.deinit();

                                try self.builder.writeOutlineFillRectangles(fill_style, line_style, line_width, rects.items);
                            },
                            .outline_fill_path => {
                                const fill_style = try self.parseStyle();
                                const line_style = try self.parseStyle();
                                const line_width = try self.parseNumber();

                                const path = try self.readPath();

                                try self.builder.writeOutlineFillPath(fill_style, line_style, line_width, path.segments);
                            },

                            .end_of_document => return error.SyntaxError,

                            _ => return error.SyntaxError,
                        }
                        try self.expectEnd();
                    },
                }
            }

            try self.builder.writeEndOfFile();
        }
    };

    var parser = Parser{ .builder = &builder, .tokenizer = Parser.Tokenizer.init(source, null), .allocator = allocator };
    try parser.parse();
}
