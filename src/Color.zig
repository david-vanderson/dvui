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
    return c.srgb_to_okhsl(.{ .r = __.r, .g = __.g, .b = __.b });
}
pub fn fromOkhsl(color: c.HSL, a: u8) Color {
    _ = color;
    _ = a;

    return undefined;
}

fn okhsl_to_vector(color: c.HSL) @Vector(3, f32) {
    return .{ color.h, color.s, color.l };
}
fn vector_to_okhsl(color: @Vector(3, f32)) c.HSL {
    return .{ .h = color[0], .s = color[1], .l = color[2] };
}
fn splat(__: f32) @Vector(3, f32) {
    return @splat(__);
}

pub fn lerp(current: Color, target_ratio: f32, target: Color) Color {
    const current_hsl = okhsl_to_vector(current.okhsl());
    const target_hsl = okhsl_to_vector(target.okhsl());
    const mix_hsl = vector_to_okhsl(current_hsl * splat(1.0 - target_ratio) + target_hsl * splat(target_ratio));
    const current_a: f32 = @floatFromInt(current.a);
    const target_a: f32 = @floatFromInt(target.a);
    const mix_a = current_a * (1.0 - target_ratio) + target_a * target_ratio; // this is cursed ,, if the two color's alpha was not originally similar, the mix will not be visually linear
    return fromOkhsl(mix_hsl, @intFromFloat(mix_a));
}
