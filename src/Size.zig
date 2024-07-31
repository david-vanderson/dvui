const std = @import("std");
const dvui = @import("dvui.zig");

const Rect = dvui.Rect;

const Size = @This();

w: f32 = 0,
h: f32 = 0,

pub fn all(v: f32) Size {
    return Size{ .w = v, .h = v };
}

pub fn rect(self: *const Size) Rect {
    return Rect{ .x = 0, .y = 0, .w = self.w, .h = self.h };
}

pub fn ceil(self: *const Size) Size {
    return Size{ .w = @ceil(self.w), .h = @ceil(self.h) };
}

pub fn pad(s: *const Size, padding: Rect) Size {
    return Size{ .w = s.w + padding.x + padding.w, .h = s.h + padding.y + padding.h };
}

pub fn max(a: Size, b: Size) Size {
    return Size{ .w = @max(a.w, b.w), .h = @max(a.h, b.h) };
}

pub fn scale(self: *const Size, s: f32) Size {
    return Size{ .w = self.w * s, .h = self.h * s };
}

pub fn format(self: *const Size, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Size{{ {d} {d} }}", .{ self.w, self.h });
}

pub fn intWidth(self: *const Size) c_int {
    return @intFromFloat(self.w);
}

pub fn intHeight(self: *const Size) c_int {
    return @intFromFloat(self.h);
}
