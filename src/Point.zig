const std = @import("std");
const dvui = @import("dvui.zig");

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

pub fn min(a: Point, b: Point) Point {
    return Point{ .x = @min(a.x, b.x), .y = @min(a.y, b.y) };
}

pub fn max(a: Point, b: Point) Point {
    return Point{ .x = @max(a.x, b.x), .y = @max(a.y, b.y) };
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

/// Natural pixels is the unit for subwindow sizing and placement.
pub const Natural = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub inline fn toPoint(self: Point.Natural) Point {
        return .{ .x = self.x, .y = self.y };
    }

    pub inline fn fromPoint(p: Point) Point.Natural {
        return .{ .x = p.x, .y = p.y };
    }

    /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
    pub inline fn toPhysical(self: Point.Natural) Point.Physical {
        return .fromPoint(self.toPoint().scale(dvui.windowNaturalScale()));
    }

    pub fn format(self: *const Point.Natural, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Point.Natural{{ {d} {d} }}", .{ self.x, self.y });
    }
};

/// Pixels is the unit for rendering and user input.
///
/// Physical pixels might be more on a hidpi screen or if the user has content scaling.
pub const Physical = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub inline fn toPoint(self: Point.Physical) Point {
        return .{ .x = self.x, .y = self.y };
    }

    pub inline fn fromPoint(p: Point) Point.Physical {
        return .{ .x = p.x, .y = p.y };
    }

    /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
    pub inline fn toNatural(self: Point.Physical) Point.Natural {
        return .fromPoint(self.toPoint().scale(1 / dvui.windowNaturalScale()));
    }

    pub inline fn nonZero(self: *const Point.Physical) bool {
        return self.toPoint().nonZero();
    }

    pub inline fn plus(a: Point.Physical, b: Point.Physical) Point.Physical {
        return .fromPoint(a.toPoint().plus(b.toPoint()));
    }

    pub inline fn diff(a: Point.Physical, b: Point.Physical) Point.Physical {
        return .fromPoint(a.toPoint().diff(b.toPoint()));
    }

    pub fn format(self: *const Point.Physical, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Point.Physical{{ {d} {d} }}", .{ self.x, self.y });
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
