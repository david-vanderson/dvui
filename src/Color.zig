const std = @import("std");

const Color = @This();

r: u8 = 0xff,
g: u8 = 0xff,
b: u8 = 0xff,
a: u8 = 0xff,

pub fn transparent(x: Color, y: f32) Color {
    return Color{
        .r = x.r,
        .g = x.g,
        .b = x.b,
        .a = @as(u8, @intFromFloat(@as(f32, @floatFromInt(x.a)) * y)),
    };
}

pub fn darken(x: Color, y: f32) Color {
    return Color{
        .r = @as(u8, @intFromFloat(@max(@as(f32, @floatFromInt(x.r)) * (1 - y), 0))),
        .g = @as(u8, @intFromFloat(@max(@as(f32, @floatFromInt(x.g)) * (1 - y), 0))),
        .b = @as(u8, @intFromFloat(@max(@as(f32, @floatFromInt(x.b)) * (1 - y), 0))),
        .a = x.a,
    };
}

pub fn lighten(x: Color, y: f32) Color {
    return Color{
        .r = @as(u8, @intFromFloat(@min(@as(f32, @floatFromInt(x.r)) * (1 + y), 255))),
        .g = @as(u8, @intFromFloat(@min(@as(f32, @floatFromInt(x.g)) * (1 + y), 255))),
        .b = @as(u8, @intFromFloat(@min(@as(f32, @floatFromInt(x.b)) * (1 + y), 255))),
        .a = x.a,
    };
}

pub fn lerp(x: Color, y: f32, z: Color) Color {
    return Color{
        .r = @as(u8, @intFromFloat(@as(f32, @floatFromInt(x.r)) * (1 - y) + @as(f32, @floatFromInt(z.r)) * y)),
        .g = @as(u8, @intFromFloat(@as(f32, @floatFromInt(x.g)) * (1 - y) + @as(f32, @floatFromInt(z.g)) * y)),
        .b = @as(u8, @intFromFloat(@as(f32, @floatFromInt(x.b)) * (1 - y) + @as(f32, @floatFromInt(z.b)) * y)),
        .a = @as(u8, @intFromFloat(@as(f32, @floatFromInt(x.a)) * (1 - y) + @as(f32, @floatFromInt(z.a)) * y)),
    };
}

pub fn format(self: *const Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Color{{ {x} {x} {x} {x} }}", .{ self.r, self.g, self.b, self.a });
}

pub const white = Color{ .r = 0xff, .g = 0xff, .b = 0xff };
pub const black = Color{ .r = 0x00, .g = 0x00, .b = 0x00 };
