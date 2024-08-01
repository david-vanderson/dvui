const std = @import("std");
const hsluv = @import("hsluv.zig");

const Color = @This();

r: u8 = 0xff,
g: u8 = 0xff,
b: u8 = 0xff,
a: u8 = 0xff,

pub const HSLuv = struct {
    h: f32 = 0.0,
    s: f32 = 100.0,
    l: f32 = 100.0,
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

const clamp = std.math.clamp;

const FieldEnum = std.meta.FieldEnum(@This());

///extracts clamped field multiplied by alpha value
pub fn extract(self: Color, field: FieldEnum) u16 {
    const a: f32 = @floatFromInt(self.a);
    const normalized_a = a / 255.0;
    const value: f32 = @floatFromInt(switch (field) {
        .r => self.r,
        .g => self.g,
        .b => self.b,
        .a => @compileError("cannot extract alpha field from color"),
    });
    const result = normalized_a * value;
    return @intFromFloat(@floor(result));
}

pub fn merge(self: Color, other: Color) Color {
    return Color{
        .r = @intCast(clamp(self.extract(.r) + other.extract(.r), 0, 255)),
        .g = @intCast(clamp(self.extract(.g) + other.extract(.g), 0, 255)),
        .b = @intCast(clamp(self.extract(.b) + other.extract(.b), 0, 255)),
        .a = 255,
    };
}
