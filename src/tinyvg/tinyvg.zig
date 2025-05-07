const std = @import("std");
const builtin = @import("builtin");

/// This is the TinyVG magic number which recognizes the icon format.
/// Magic numbers might seem unnecessary, but they will be the first
/// guard in line against bad input and prevent unnecessary cycles
/// to detect those.
pub const magic_number = [2]u8{ 0x72, 0x56 };

/// This is the latest TinyVG version supported by this library.
pub const current_version = 1;

// submodules

/// This module provides a runtime usable builder
pub const builder = @import("builder.zig");

/// Module that provides a generic purpose TinyVG parser. This parser exports all data as
/// pre-scaled `f32` values.
pub const parsing = @import("parsing.zig");

/// A TinyVG software renderer based on the parsing module. Takes a parser stream as input.
pub const rendering = @import("rendering.zig");

/// This module provides means to render SVG files from TinyVG.
pub const svg = @import("svg.zig");

/// This module provides means to render and parse TinyVG text.
pub const text = @import("text.zig");

/// Returns a stream of TinyVG commands as well as the document header.
/// - `allocator` is used to allocate temporary data like the current set of vertices for *FillPolygon*. This can be a fixed-buffer allocator.
/// - `reader` is a generic stream that provides the TinyVG byte data.
pub fn parse(allocator: std.mem.Allocator, reader: anytype) !parsing.Parser(@TypeOf(reader)) {
    return try parsing.Parser(@TypeOf(reader)).init(allocator, reader);
}

pub fn renderStream(
    /// Allocator for temporary allocations
    allocator: std.mem.Allocator,
    /// A struct that exports a single function `setPixel(x: isize, y: isize, color: [4]u8) void` as well as two fields width and height
    framebuffer: anytype,
    /// The icon data
    reader: anytype,
) !void {
    var parser = try parse(allocator, reader);
    defer parser.deinit();

    while (try parser.next()) |cmd| {
        try rendering.renderCommand(
            framebuffer,
            parser.header,
            parser.color_table,
            cmd,
            allocator,
        );
    }
}

pub fn render(
    /// Allocator for temporary allocations
    allocator: std.mem.Allocator,
    /// A struct that exports a single function `setPixel(x: isize, y: isize, color: [4]u8) void` as well as two fields width and height
    framebuffer: anytype,
    /// The icon data
    icon: []const u8,
) !void {
    var stream = std.io.fixedBufferStream(icon);
    return try renderStream(allocator, framebuffer, stream.reader());
}

comptime {
    if (builtin.is_test) {
        _ = @import("builder.zig"); // import file for tests
        _ = parsing;
        _ = rendering;
    }
}

/// The value range used in the encoding.
pub const Range = enum(u2) {
    /// unit uses 16 bit,
    default = 0,

    /// unit takes only 8 bit
    reduced = 1,

    // unit uses 32 bit,
    enhanced = 2,
};

/// The color encoding used in a TinyVG file. This enum describes how the data in the color table section of the format looks like.
pub const ColorEncoding = enum(u2) {
    /// A classic 4-tuple with 8 bit unsigned channels.
    /// Encodes red, green, blue and alpha. If not specified otherwise (via external means) the color channels encode sRGB color data
    /// and the alpha stores linear transparency.
    u8888 = 0,

    /// A 16 bit color format with 5 bit for red and blue, and 6 bit color depth for green channel.
    /// This format is typically used in embedded devices or cheaper displays. If not specified otherwise (via external means) the color channels encode sRGB color data.
    u565 = 1,

    /// A format with 16 byte per color and 4 channels. Each channel is encoded as a `binary32` IEEE 754 value.
    /// The first three channels encode color data, the fourth channel encodes linear alpha.
    /// If not specified otherwise (via external means) the color channels encode sRGB color data and the alpha stores linear transparency.
    f32 = 2,

    /// This format is specified by external means and is meant to signal that these files are *valid*, but it's not possible
    /// to decode them without external knowledge about the color encoding. This is meant for special cases where huge savings
    /// might be possible by not encoding any color information in the files itself or special device dependent color formats are required.
    ///
    /// Possible uses cases are:
    ///
    /// - External fixed or shared color palettes
    /// - CMYK format for printing
    /// - High precision 16 bit color formats
    /// - Using non-sRGB color spaces
    /// - Using RAL numbers for painting
    /// - ...
    ///
    /// **NOTE:** A conforming parser is allowed to reject any file with a custom color encoding, as these are meant to be parsed with a specific use case.
    custom = 3,
};

/// A TinyVG scale value. Defines the scale for all units inside a graphic.
/// The scale is defined by the number of decimal bits in a `i32`, thus scaling
/// can be trivially implemented by shifting the integers right by the scale bits.
pub const Scale = enum(u4) {
    const Self = @This();

    @"1/1" = 0,
    @"1/2" = 1,
    @"1/4" = 2,
    @"1/8" = 3,
    @"1/16" = 4,
    @"1/32" = 5,
    @"1/64" = 6,
    @"1/128" = 7,
    @"1/256" = 8,
    @"1/512" = 9,
    @"1/1024" = 10,
    @"1/2048" = 11,
    @"1/4096" = 12,
    @"1/8192" = 13,
    @"1/16384" = 14,
    @"1/32768" = 15,

    pub fn map(self: *const Self, value: f32) Unit {
        return Unit.init(self.*, value);
    }

    pub fn getShiftBits(self: *const Self) u4 {
        return @intFromEnum(self.*);
    }

    pub fn getScaleFactor(self: *const Self) u15 {
        return @as(u15, 1) << self.getShiftBits();
    }
};

/// A scalable fixed-point number.
pub const Unit = enum(i32) {
    const Self = @This();

    _,

    pub fn init(scale: Scale, value: f32) Self {
        return @enumFromInt(@as(i32, @intFromFloat(value * @as(f32, @floatFromInt(scale.getScaleFactor())) + 0.5)));
    }

    pub fn raw(self: *const Self) i32 {
        return @intFromEnum(self.*);
    }

    pub fn toFloat(self: *const Self, scale: Scale) f32 {
        return @as(f32, @floatFromInt(@intFromEnum(self.*))) / @as(f32, @floatFromInt(scale.getScaleFactor()));
    }

    pub fn toInt(self: *const Self, scale: Scale) i32 {
        const factor = scale.getScaleFactor();
        return @divFloor(@intFromEnum(self.*) + (@divExact(factor, 2)), factor);
    }

    pub fn toUnsignedInt(self: *const Self, scale: Scale) !u31 {
        const i = toInt(self, scale);
        if (i < 0)
            return error.InvalidData;
        return @intCast(i);
    }
};

pub const Color = extern struct {
    const Self = @This();

    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn toRgba8(self: *const Self) [4]u8 {
        return [4]u8{
            @intFromFloat(std.math.clamp(255.0 * self.r, 0.0, 255.0)),
            @intFromFloat(std.math.clamp(255.0 * self.g, 0.0, 255.0)),
            @intFromFloat(std.math.clamp(255.0 * self.b, 0.0, 255.0)),
            @intFromFloat(std.math.clamp(255.0 * self.a, 0.0, 255.0)),
        };
    }

    pub fn lerp(lhs: Self, rhs: Self, factor: f32) Self {
        const l = struct {
            fn l(a: f32, b: f32, c: f32) u8 {
                return @intFromFloat(@as(f32, @floatFromInt(a)) + (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(a))) * std.math.clamp(c, 0, 1));
            }
        }.l;

        return Self{
            .r = l(lhs.r, rhs.r, factor),
            .g = l(lhs.g, rhs.g, factor),
            .b = l(lhs.b, rhs.b, factor),
            .a = l(lhs.a, rhs.a, factor),
        };
    }

    pub fn fromString(str: []const u8) !Self {
        return switch (str.len) {
            6 => Self{
                .r = @as(f32, @floatFromInt(try std.fmt.parseInt(u8, str[0..2], 16))) / 255.0,
                .g = @as(f32, @floatFromInt(try std.fmt.parseInt(u8, str[2..4], 16))) / 255.0,
                .b = @as(f32, @floatFromInt(try std.fmt.parseInt(u8, str[4..6], 16))) / 255.0,
                .a = 1.0,
            },
            else => error.InvalidFormat,
        };
    }
};

pub const Command = enum(u6) {
    end_of_document = 0,

    fill_polygon = 1,
    fill_rectangles = 2,
    fill_path = 3,

    draw_lines = 4,
    draw_line_loop = 5,
    draw_line_strip = 6,
    draw_line_path = 7,

    outline_fill_polygon = 8,
    outline_fill_rectangles = 9,
    outline_fill_path = 10,

    _,
};

/// Constructs a new point
pub fn point(x: f32, y: f32) Point {
    return .{ .x = x, .y = y };
}

pub const Point = struct {
    x: f32,
    y: f32,
};

pub fn rectangle(x: f32, y: f32, width: f32, height: f32) Rectangle {
    return .{ .x = x, .y = y, .width = width, .height = height };
}

pub const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub fn line(start: Point, end: Point) Line {
    return Line{ .start = start, .end = end };
}

pub const Line = struct {
    start: Point,
    end: Point,
};

pub const Path = struct {
    segments: []Segment,

    pub const Segment = struct {
        start: Point,
        commands: []const Node,
    };

    pub const Node = union(Type) {
        const Self = @This();

        line: NodeData(Point),
        horiz: NodeData(f32),
        vert: NodeData(f32),
        bezier: NodeData(Bezier),
        arc_circle: NodeData(ArcCircle),
        arc_ellipse: NodeData(ArcEllipse),
        close: NodeData(void),
        quadratic_bezier: NodeData(QuadraticBezier),

        pub fn NodeData(comptime Payload: type) type {
            return struct {
                line_width: ?f32 = null,
                data: Payload,

                pub fn init(line_width: ?f32, data: Payload) @This() {
                    return .{ .line_width = line_width, .data = data };
                }
            };
        }

        pub const ArcCircle = struct {
            radius: f32,
            large_arc: bool,
            sweep: bool,
            target: Point,
        };

        pub const ArcEllipse = struct {
            radius_x: f32,
            radius_y: f32,
            rotation: f32,
            large_arc: bool,
            sweep: bool,
            target: Point,
        };

        pub const Bezier = struct {
            c0: Point,
            c1: Point,
            p1: Point,
        };

        pub const QuadraticBezier = struct {
            c: Point,
            p1: Point,
        };
    };

    pub const Type = enum(u3) {
        line = 0, // x,y
        horiz = 1, // x
        vert = 2, // y
        bezier = 3, // c0x,c0y,c1x,c1y,x,y
        arc_circle = 4, //r,x,y
        arc_ellipse = 5, // rx,ry,x,y
        close = 6,
        quadratic_bezier = 7,
    };
};

pub const StyleType = enum(u2) {
    flat = 0,
    linear = 1,
    radial = 2,
};

pub const Style = union(StyleType) {
    const Self = @This();

    flat: u32, // color index
    linear: Gradient,
    radial: Gradient,
};

pub const Gradient = struct {
    point_0: Point,
    point_1: Point,
    color_0: u32,
    color_1: u32,
};

test {
    _ = builder;
    _ = parsing;
    _ = rendering;
}
