const std = @import("std");
const hsluv = @import("hsluv.zig");

const Color = @This();
const dvui = @import("dvui.zig");
const ColorsFromTheme = dvui.Options.ColorsFromTheme;

r: u8 = 0xff,
g: u8 = 0xff,
b: u8 = 0xff,
a: u8 = 0xff,

// Basic web colors
// https://en.wikipedia.org/wiki/Web_colors#Basic_colors
pub const white = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF };
pub const silver = Color{ .r = 0xC0, .g = 0xC0, .b = 0xC0 };
pub const gray = Color{ .r = 0x80, .g = 0x80, .b = 0x80 };
pub const black = Color{ .r = 0x00, .g = 0x00, .b = 0x00 };
pub const red = Color{ .r = 0xFF, .g = 0x00, .b = 0x00 };
pub const maroon = Color{ .r = 0x80, .g = 0x00, .b = 0x00 };
pub const yellow = Color{ .r = 0xFF, .g = 0xFF, .b = 0x00 };
pub const olive = Color{ .r = 0x80, .g = 0x80, .b = 0x00 };
pub const lime = Color{ .r = 0x00, .g = 0xFF, .b = 0x00 };
pub const green = Color{ .r = 0x00, .g = 0x80, .b = 0x00 };
pub const aqua = Color{ .r = 0x00, .g = 0xFF, .b = 0xFF };
pub const teal = Color{ .r = 0x00, .g = 0x80, .b = 0x80 };
pub const blue = Color{ .r = 0x00, .g = 0x00, .b = 0xFF };
pub const navy = Color{ .r = 0x00, .g = 0x00, .b = 0x80 };
pub const fuchsia = Color{ .r = 0xFF, .g = 0x00, .b = 0xFF };
pub const purple = Color{ .r = 0x80, .g = 0x00, .b = 0x80 };

// Aliases for basic colors that are already defined
// https://en.wikipedia.org/wiki/Web_colors#Extended_colors
pub const cyan = aqua;
pub const magenta = fuchsia;
pub const darl_cyan = teal;
pub const dark_magenta = purple;

pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

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
    const r: f32 = @as(f32, @floatFromInt(self.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(self.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(self.b)) / 255.0;

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

pub fn toRGBA(self: @This()) [4]u8 {
    return .{ self.r, self.g, self.b, self.a };
}

/// https://en.wikipedia.org/wiki/HSL_and_HSV#HSV_to_RGB
pub const HSV = struct {
    /// Hue 0-360 (degrees)
    h: f32 = 0.0,

    /// Saturation 0-1 (%)
    s: f32 = 1.0,

    /// Value 0-1 (%)
    v: f32 = 1.0,

    /// Alpha 0-1 (%)
    a: f32 = 1.0,

    pub fn fromColor(color: Color) HSV {
        const r: f32 = @as(f32, @floatFromInt(color.r)) / 255.0;
        const g: f32 = @as(f32, @floatFromInt(color.g)) / 255.0;
        const b: f32 = @as(f32, @floatFromInt(color.b)) / 255.0;
        const a: f32 = @as(f32, @floatFromInt(color.a)) / 255.0;

        const max = @max(r, g, b);
        const min = @min(r, g, b);
        const delta = max - min;

        const h = 60 * (if (delta == 0)
            0
        else if (max == r)
            @mod((g - b) / delta, 6)
        else if (max == g)
            (b - r) / delta + 2
        else if (max == b)
            (r - g) / delta + 4
        else
            unreachable);

        const s = if (max == 0) 0 else delta / max;

        return .{ .h = h, .s = s, .v = max, .a = a };
    }

    pub fn toColor(self: HSV) Color {
        const c = self.v * self.s;
        const x = c * (1 - @abs(@mod(self.h / 60, 2) - 1));
        const m = self.v - c;

        const step: i8 = @intFromFloat(self.h / 60);

        const r, const g, const b = switch (step) {
            0 => .{ c, x, 0 },
            1 => .{ x, c, 0 },
            2 => .{ 0, c, x },
            3 => .{ 0, x, c },
            4 => .{ x, 0, c },
            5 => .{ c, 0, x },
            else => return .magenta, // hue was < 0 or >= 360
        };

        return .{
            .r = @intFromFloat(@round((r + m) * 255)),
            .g = @intFromFloat(@round((g + m) * 255)),
            .b = @intFromFloat(@round((b + m) * 255)),
            .a = @intFromFloat(@round(self.a * 255)),
        };
    }

    test toColor {
        try std.testing.expectEqualDeep(Color.black, HSV.toColor(.{ .h = 0, .s = 0, .v = 0 }));
        try std.testing.expectEqualDeep(Color.white, HSV.toColor(.{ .h = 0, .s = 0, .v = 1 }));

        // Hue shouldn't matter with 0 saturation
        try std.testing.expectEqualDeep(Color.black, HSV.toColor(.{ .h = 123, .s = 0, .v = 0 }));
        try std.testing.expectEqualDeep(Color.white, HSV.toColor(.{ .h = 123, .s = 0, .v = 1 }));

        try std.testing.expectEqualDeep(Color.red, HSV.toColor(.{ .h = 0 }));
        try std.testing.expectEqualDeep(Color.yellow, HSV.toColor(.{ .h = 60 }));
        try std.testing.expectEqualDeep(Color.lime, HSV.toColor(.{ .h = 120 }));
        try std.testing.expectEqualDeep(Color.cyan, HSV.toColor(.{ .h = 180 }));
        try std.testing.expectEqualDeep(Color.blue, HSV.toColor(.{ .h = 240 }));
        try std.testing.expectEqualDeep(Color.magenta, HSV.toColor(.{ .h = 300 }));

        // our silver color is 0xC0, and v == 0.75 is 0xBF
        try std.testing.expectEqualDeep(Color{ .r = 0xBF, .g = 0xBF, .b = 0xBF }, HSV.toColor(.{ .h = 0, .s = 0, .v = 0.75 }));
        try std.testing.expectEqualDeep(Color.gray, HSV.toColor(.{ .h = 0, .s = 0, .v = 0.5 }));

        try std.testing.expectEqualDeep(Color.maroon, HSV.toColor(.{ .h = 0, .v = 0.5 }));
        try std.testing.expectEqualDeep(Color.olive, HSV.toColor(.{ .h = 60, .v = 0.5 }));
        try std.testing.expectEqualDeep(Color.green, HSV.toColor(.{ .h = 120, .v = 0.5 }));
        try std.testing.expectEqualDeep(Color.teal, HSV.toColor(.{ .h = 180, .v = 0.5 }));
        try std.testing.expectEqualDeep(Color.purple, HSV.toColor(.{ .h = 300, .v = 0.5 }));
    }

    test fromColor {
        try std.testing.expectEqualDeep(Color.black, HSV.fromColor(.black).toColor());
        try std.testing.expectEqualDeep(Color.white, HSV.fromColor(.white).toColor());

        try std.testing.expectEqualDeep(Color.red, HSV.fromColor(.red).toColor());
        try std.testing.expectEqualDeep(Color.yellow, HSV.fromColor(.yellow).toColor());
        try std.testing.expectEqualDeep(Color.lime, HSV.fromColor(.lime).toColor());
        try std.testing.expectEqualDeep(Color.cyan, HSV.fromColor(.cyan).toColor());
        try std.testing.expectEqualDeep(Color.blue, HSV.fromColor(.blue).toColor());
        try std.testing.expectEqualDeep(Color.magenta, HSV.fromColor(.magenta).toColor());

        // our silver color is 0xC0, and v == 0.75 is 0xBF
        try std.testing.expectEqualDeep(Color{ .r = 0xBF, .g = 0xBF, .b = 0xBF }, HSV.fromColor(.{ .r = 0xBF, .g = 0xBF, .b = 0xBF }).toColor());
        try std.testing.expectEqualDeep(Color.gray, HSV.fromColor(.gray).toColor());

        try std.testing.expectEqualDeep(Color.maroon, HSV.fromColor(.maroon).toColor());
        try std.testing.expectEqualDeep(Color.olive, HSV.fromColor(.olive).toColor());
        try std.testing.expectEqualDeep(Color.green, HSV.fromColor(.green).toColor());
        try std.testing.expectEqualDeep(Color.teal, HSV.fromColor(.teal).toColor());
        try std.testing.expectEqualDeep(Color.purple, HSV.fromColor(.purple).toColor());
    }
};

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

/// Multiply the current opacity with `mult`, usually between 0 and 1
pub fn opacity(self: Color, mult: f32) Color {
    if (mult > 1) return self;
    return Color{
        .r = self.r,
        .g = self.g,
        .b = self.b,
        .a = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(self.a)) * mult, 0, 255)),
    };
}

pub fn format(self: *const Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Color{{ {x} {x} {x} {x} }}", .{ self.r, self.g, self.b, self.a });
}

/// Linear interpolocation of colors component wise
pub fn lerp(self: Color, other: Color, t: f32) Color {
    if (t <= 0) return self;
    if (t >= 1) return other;
    const r: f32 = std.math.lerp(@as(f32, @floatFromInt(self.r)) / 255, @as(f32, @floatFromInt(other.r)) / 255, t);
    const g: f32 = std.math.lerp(@as(f32, @floatFromInt(self.g)) / 255, @as(f32, @floatFromInt(other.g)) / 255, t);
    const b: f32 = std.math.lerp(@as(f32, @floatFromInt(self.b)) / 255, @as(f32, @floatFromInt(other.b)) / 255, t);
    const a: f32 = std.math.lerp(@as(f32, @floatFromInt(self.a)) / 255, @as(f32, @floatFromInt(other.a)) / 255, t);
    return Color{
        .r = @intFromFloat(r * 255.99),
        .g = @intFromFloat(g * 255.99),
        .b = @intFromFloat(b * 255.99),
        .a = @intFromFloat(a * 255.99),
    };
}

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

/// A color premultiplied by alpha, mostly used for vertex colors
pub const PMA = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const transparent = PMA{ .r = 0, .g = 0, .b = 0, .a = 0 };

    pub fn toColor(self: PMA) Color {
        // FIXME: Should this undo the alpha multiply?
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
    }

    /// Convert normal color to premultiplied alpha.
    pub fn fromColor(color: Color) PMA {
        if (color.a == 0xFF) return .cast(color);
        return .{
            .r = @intCast(@divTrunc(@as(u16, color.r) * color.a, 255)),
            .g = @intCast(@divTrunc(@as(u16, color.g) * color.a, 255)),
            .b = @intCast(@divTrunc(@as(u16, color.b) * color.a, 255)),
            .a = color.a,
        };
    }

    /// Casts an opaque color (full alpha) to a PMA
    pub fn cast(color: Color) PMA {
        std.debug.assert(color.a == 0xFF);
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
};

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
    if (hex_color.len == 0) return error.InvalidHexStringLength;
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

    const mult: u32 = if (is_nibble_size) 0x10 else 1;
    const mask: u32 = if (is_nibble_size) 0xf else 0xff;
    const step: u5 = if (is_nibble_size) 4 else 8;
    const offset: u5 = @intFromBool(has_alpha);
    return .{
        .r = @intCast(mult * ((num >> step * (2 + offset)) & mask)),
        .g = @intCast(mult * ((num >> step * (1 + offset)) & mask)),
        .b = @intCast(mult * ((num >> step * (0 + offset)) & mask)),
        .a = if (has_alpha) @intCast(mult * (num & mask)) else 0xff,
    };
}

test tryFromHex {
    try std.testing.expectEqual(Color{ .r = 0x10, .g = 0x20, .b = 0x30, .a = 0xff }, Color.tryFromHex("123"));
    try std.testing.expectEqual(Color{ .r = 0x10, .g = 0x20, .b = 0x30, .a = 0xff }, Color.tryFromHex("#123"));
    try std.testing.expectEqual(Color{ .r = 0x10, .g = 0x20, .b = 0x30, .a = 0x40 }, Color.tryFromHex("1234"));
    try std.testing.expectEqual(Color{ .r = 0x10, .g = 0x20, .b = 0x30, .a = 0x40 }, Color.tryFromHex("#1234"));
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

/// Get a Color from the active Theme
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn fromTheme(theme_color: ColorsFromTheme) @This() {
    return switch (theme_color) {
        .accent => dvui.themeGet().color_accent,
        .text => dvui.themeGet().color_text,
        .text_press => dvui.themeGet().color_text_press,
        .fill => dvui.themeGet().color_fill,
        .fill_hover => dvui.themeGet().color_fill_hover,
        .fill_press => dvui.themeGet().color_fill_press,
        .border => dvui.themeGet().color_border,
        .err => dvui.themeGet().color_err,
        .fill_window => dvui.themeGet().color_fill_window,
        .fill_control => dvui.themeGet().color_fill_control,
    };
}

test {
    @import("std").testing.refAllDecls(@This());
}
