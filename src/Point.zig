const std = @import("std");

const Point = @This();

x: f32 = 0,
y: f32 = 0,

pub fn nonZero(self: *const Point) bool {
    return (self.x != 0 or self.y != 0);
}

pub fn plus(self: *const Point, b: Point) Point {
    return Point{ .x = self.x + b.x, .y = self.y + b.y };
}

pub fn diff(a: Point, b: Point) Point {
    return Point{ .x = a.x - b.x, .y = a.y - b.y };
}

pub fn scale(self: *const Point, s: f32) Point {
    return Point{ .x = self.x * s, .y = self.y * s };
}

pub fn equals(self: *const Point, b: Point) bool {
    return (self.x == b.x and self.y == b.y);
}

pub fn length(self: *const Point) f32 {
    return @sqrt((self.x * self.x) + (self.y * self.y));
}

pub fn normalize(self: *const Point) Point {
    const d2 = self.x * self.x + self.y * self.y;
    if (d2 == 0) {
        return Point{ .x = 1.0, .y = 0.0 };
    } else {
        const inv_len = 1.0 / @sqrt(d2);
        return Point{ .x = self.x * inv_len, .y = self.y * inv_len };
    }
}

pub fn format(self: *const Point, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Point{{ {d} {d} }}", .{ self.x, self.y });
}

test {
    @import("std").testing.refAllDecls(@This());
}
