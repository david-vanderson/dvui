const std = @import("std");
const hsluv = @import("hsluv.zig");

const Color = @This();

r: u8 = 0xff,
g: u8 = 0xff,
b: u8 = 0xff,
a: u8 = 0xff,

/// Convert normal color to premultiplied alpha.
pub fn alphaMultiply(self: @This()) @This() {
    var c = self;
    c.r = @intCast(@divTrunc(@as(u16, c.r) * c.a, 255));
    c.g = @intCast(@divTrunc(@as(u16, c.g) * c.a, 255));
    c.b = @intCast(@divTrunc(@as(u16, c.b) * c.a, 255));
    return c;
}

pub fn alphaMultiplyPixels(pixels: []u8) void {
    for (0..pixels.len / 4) |ii| {
        const i = ii * 4;
        const a = pixels[i + 3];
        pixels[i + 0] = @intCast(@divTrunc(@as(u16, pixels[i + 0]) * a, 255));
        pixels[i + 1] = @intCast(@divTrunc(@as(u16, pixels[i + 1]) * a, 255));
        pixels[i + 2] = @intCast(@divTrunc(@as(u16, pixels[i + 2]) * a, 255));
    }
}

/// Returns brightness of the color as a value between 0 and 1
pub fn brightness(self: @This()) f32 {
    const red: f32 = @as(f32, @floatFromInt(self.r)) / 255.0;
    const green: f32 = @as(f32, @floatFromInt(self.g)) / 255.0;
    const blue: f32 = @as(f32, @floatFromInt(self.b)) / 255.0;

    return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

/// Hue Saturation Lightness
///
/// https://www.hsluv.org/
/// src/hsluv.zig is hand-translated from https://github.com/hsluv/hsluv-c
pub const HSLuv = struct {
    /// Hue 0-360
    h: f32 = 0.0,

    /// Saturation 0-100
    s: f32 = 100.0,

    /// Lightness 0-100
    l: f32 = 100.0,

    /// Alpha 0-100
    a: f32 = 100.0,

    pub fn color(self: HSLuv) Color {
        return Color.fromHSLuv(self.h, self.s, self.l, self.a);
    }

    pub fn fromColor(c: Color) HSLuv {
        var ret: HSLuv = undefined;
        hsluv.rgb2hsluv(
            @as(f32, @floatFromInt(c.r)) / 255.0,
            @as(f32, @floatFromInt(c.g)) / 255.0,
            @as(f32, @floatFromInt(c.b)) / 255.0,
            &ret.h,
            &ret.s,
            &ret.l,
        );
        ret.a = @as(f32, @floatFromInt(c.a)) * 100.0 / 255.0;
        return ret;
    }

    pub fn lighten(self: HSLuv, deltal: f32) HSLuv {
        return .{
            .h = self.h,
            .s = self.s,
            .l = std.math.clamp(self.l + deltal, 0, 100),
            .a = self.a,
        };
    }
};

pub fn fromHSLuv(h: f32, s: f32, l: f32, a: f32) Color {
    var r: f32 = undefined;
    var g: f32 = undefined;
    var b: f32 = undefined;
    hsluv.hsluv2rgb(h, s, l, &r, &g, &b);
    return Color{
        .r = @intFromFloat(r * 255.99),
        .g = @intFromFloat(g * 255.99),
        .b = @intFromFloat(b * 255.99),
        .a = @intFromFloat(a / 100.0 * 255.99),
    };
}

pub fn transparent(x: Color, y: f32) Color {
    return Color{
        .r = x.r,
        .g = x.g,
        .b = x.b,
        .a = @as(u8, @intFromFloat(@as(f32, @floatFromInt(x.a)) * y)),
    };
}

pub fn format(self: *const Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Color{{ {x} {x} {x} {x} }}", .{ self.r, self.g, self.b, self.a });
}

pub const white = Color{ .r = 0xff, .g = 0xff, .b = 0xff };
pub const black = Color{ .r = 0x00, .g = 0x00, .b = 0x00 };
pub const magenta = Color{ .r = 0xFD, .g = 0x3D, .b = 0xB5 };

/// Average two colors component-wise
pub fn average(self: Color, other: Color) Color {
    return Color{
        .r = @intCast((@as(u9, @intCast(self.r)) + other.r) / 2),
        .g = @intCast((@as(u9, @intCast(self.g)) + other.g) / 2),
        .b = @intCast((@as(u9, @intCast(self.b)) + other.b) / 2),
        .a = @intCast((@as(u9, @intCast(self.a)) + other.a) / 2),
    };
}

/// Multiply two colors component-wise.
pub fn multiply(self: Color, other: Color) Color {
    return Color{
        .r = @intCast(@divTrunc(@as(u16, self.r) * other.r, 255)),
        .g = @intCast(@divTrunc(@as(u16, self.g) * other.g, 255)),
        .b = @intCast(@divTrunc(@as(u16, self.b) * other.b, 255)),
        .a = @intCast(@divTrunc(@as(u16, self.a) * other.a, 255)),
    };
}

const clamp = std.math.clamp;

const FieldEnum = std.meta.FieldEnum(@This());

/// extracts clamped field multiplied by alpha value
pub fn extract(self: Color, field: FieldEnum) u16 {
    const a: f32 = @floatFromInt(self.a);
    const normalized_a = a / 255.0;
    const value: f32 = @floatFromInt(switch (field) {
        .r => self.r,
        .g => self.g,
        .b => self.b,
        .a => {
            @panic("This should never be called");
        },
    });
    const result = normalized_a * value;
    return @intFromFloat(@floor(result));
}

/// Adds two colors rgb component-wise premultiplied by alpha
pub fn alphaAdd(self: Color, other: Color) Color {
    return Color{
        .r = @intCast(clamp(self.extract(.r) + other.extract(.r), 0, 255)),
        .g = @intCast(clamp(self.extract(.g) + other.extract(.g), 0, 255)),
        .b = @intCast(clamp(self.extract(.b) + other.extract(.b), 0, 255)),
        .a = 255,
    };
}

/// Adds two colors rgb component-wise premultiplied by alpha
pub fn alphaAverage(self: Color, other: Color) Color {
    return Color{
        .r = @intCast((self.extract(.r) + other.extract(.r)) / (255 * 2)),
        .g = @intCast((self.extract(.g) + other.extract(.g)) / (255 * 2)),
        .b = @intCast((self.extract(.b) + other.extract(.b)) / (255 * 2)),
        .a = 255,
    };
}

pub const HexString = [7]u8;

/// Returns a hex color string in the format "#rrggbb"
pub fn toHexString(self: Color) !HexString {
    var result: HexString = undefined;
    _ = try std.fmt.bufPrint(&result, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
    return result;
}

test toHexString {
    try std.testing.expectEqual((Color{ .r = 0x1, .g = 0x2, .b = 0x3, .a = 0xFF }).toHexString(), "#010203".*);
    try std.testing.expectEqual((Color{ .r = 0x1, .g = 0x2, .b = 0x3, .a = 0x4 }).toHexString(), "#010203".*);
    try std.testing.expectEqual((Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xFF }).toHexString(), "#a1a2a3".*);
    try std.testing.expectEqual((Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xa4 }).toHexString(), "#a1a2a3".*);
}

/// Converts hex color string to `Color`
///
/// If `hex_color` is invalid, an error is logged and a default color is returned.
/// In comptime an invalid `hex_color` will cause a compile error.
///
/// See `tryFromHex` for a version that returns an error.
///
/// Supports the following formats:
/// - `#RGB`
/// - `#RGBA`
/// - `#RRGGBB`
/// - `#RRGGBBAA`
/// - `RGB`
/// - `RGBA`
/// - `RRGGBB`
/// - `RRGGBBAA`
pub fn fromHex(hex_color: []const u8) Color {
    return tryFromHex(hex_color) catch |err| if (@inComptime()) {
        @compileError(std.fmt.comptimePrint("Failed to parse hex color string: {!}", .{err}));
    } else {
        std.log.err("Failed to parse hex color string: {!}", .{err});
        return magenta;
    };
}

pub const FromHexError = std.fmt.ParseIntError || error{
    /// The string had a different length that expected for the supported formats
    InvalidHexStringLength,
};

/// Converts hex color string to `Color`
///
/// Supports the following formats:
/// - `#RGB`
/// - `#RGBA`
/// - `#RRGGBB`
/// - `#RRGGBBAA`
/// - `RGB`
/// - `RGBA`
/// - `RRGGBB`
/// - `RRGGBBAA`
pub fn tryFromHex(hex_color: []const u8) FromHexError!Color {
    const hex = if (hex_color[0] == '#') hex_color[1..] else hex_color;

    const is_nibble_size, const has_alpha = switch (hex.len) {
        3 => .{ true, false },
        4 => .{ true, true },
        6 => .{ false, false },
        8 => .{ false, true },
        else => return error.InvalidHexStringLength,
    };
    const num = std.fmt.parseUnsigned(u32, hex, 16) catch |err| switch (err) {
        std.fmt.ParseIntError.Overflow => unreachable, // Length and base is known, cannot overflow
        std.fmt.ParseIntError.InvalidCharacter => |e| return e,
    };

    const mask: u32 = if (is_nibble_size) 0xf else 0xff;
    const step: u5 = if (is_nibble_size) 4 else 8;
    const offset: u5 = @intFromBool(has_alpha);
    return .{
        .r = @intCast((num >> step * (2 + offset)) & mask),
        .g = @intCast((num >> step * (1 + offset)) & mask),
        .b = @intCast((num >> step * (0 + offset)) & mask),
        .a = if (has_alpha) @intCast(num & mask) else 0xff,
    };
}

test tryFromHex {
    try std.testing.expectEqual(Color{ .r = 0x1, .g = 0x2, .b = 0x3, .a = 0xff }, Color.tryFromHex("123"));
    try std.testing.expectEqual(Color{ .r = 0x1, .g = 0x2, .b = 0x3, .a = 0xff }, Color.tryFromHex("#123"));
    try std.testing.expectEqual(Color{ .r = 0x1, .g = 0x2, .b = 0x3, .a = 0x4 }, Color.tryFromHex("1234"));
    try std.testing.expectEqual(Color{ .r = 0x1, .g = 0x2, .b = 0x3, .a = 0x4 }, Color.tryFromHex("#1234"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xff }, Color.tryFromHex("a1a2a3"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xff }, Color.tryFromHex("#a1a2a3"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xa4 }, Color.tryFromHex("a1a2a3a4"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xa4 }, Color.tryFromHex("#a1a2a3a4"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xff }, Color.tryFromHex("A1A2A3"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xff }, Color.tryFromHex("#A1A2A3"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xa4 }, Color.tryFromHex("A1A2A3A4"));
    try std.testing.expectEqual(Color{ .r = 0xa1, .g = 0xa2, .b = 0xa3, .a = 0xa4 }, Color.tryFromHex("#A1A2A3A4"));
    try std.testing.expectEqual(FromHexError.InvalidCharacter, Color.tryFromHex("XXX"));
    try std.testing.expectEqual(FromHexError.InvalidHexStringLength, Color.tryFromHex("#12"));
}

test {
    @import("std").testing.refAllDecls(@This());
}
