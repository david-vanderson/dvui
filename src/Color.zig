//! color in backend colorspace
//! it is normally sRGB

const std = @import("std");
// const c = @cImport(@cInclude("ok_color.h"));
const c = @import("ok_color.zig");
const Color = @This();

r: u8 = 0xFF,
g: u8 = 0xFF,
b: u8 = 0xFF,
a: u8 = 0xFF,

pub fn format(self: *const Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Color{{ {x} {x} {x} {x} }}", .{ self.r, self.g, self.b, self.a });
}

pub const white = Color{ .r = 0xFF, .g = 0xFF, .b = 0xFF };
pub const black = Color{ .r = 0x00, .g = 0x00, .b = 0x00 };
pub const magenta = Color{ .r = 0xFF, .g = 0x00, .b = 0xFF };

pub fn multiply_alpha(x: Color, y: f32) Color {
    return Color{
        .r = x.r,
        .g = x.g,
        .b = x.b,
        .a = @as(u8, @intFromFloat(@as(f32, @floatFromInt(x.a)) * y)),
    };
}

// we choose okhsl because it has orthogonal lightness
// https://bottosson.github.io/posts/colorpicker/#summary-2
pub fn okhsl(__: Color) c.HSL {
    return c.srgb_to_okhsl(.{
        .r = @as(f32, @floatFromInt(__.r)) / 255.0,
        .g = @as(f32, @floatFromInt(__.g)) / 255.0,
        .b = @as(f32, @floatFromInt(__.b)) / 255.0,
    });
}
const round = std.math.round;
pub fn fromOkhsl(color: c.HSL, a: u8) Color {
    const rgb = c.okhsl_to_srgb(color);
    return Color{
        .r = @intFromFloat(round(rgb.r * 255.0)),
        .g = @intFromFloat(round(rgb.g * 255.0)),
        .b = @intFromFloat(round(rgb.b * 255.0)),
        .a = a,
    };
}

pub fn lerp(current: Color, target_ratio: f32, target: Color) Color {
    const current_hsl = current.okhsl();
    const target_hsl = target.okhsl();
    const mix_hsl = c.HSL{
        .h = current_hsl.h * (1.0 - target_ratio) + target_hsl.h * (target_ratio),
        .s = current_hsl.s * (1.0 - target_ratio) + target_hsl.s * (target_ratio),
        .l = current_hsl.l * (1.0 - target_ratio) + target_hsl.l * (target_ratio),
    };

    const current_a: f32 = @floatFromInt(current.a);
    const target_a: f32 = @floatFromInt(target.a);
    const mix_a = current_a * (1.0 - target_ratio) + target_a * target_ratio; // this is cursed ,, if the two color's alpha was not originally similar, the mix will not be visually linear

    @compileLog(current, current_hsl, target_hsl, mix_hsl);
    return fromOkhsl(mix_hsl, @intFromFloat(mix_a));
}
