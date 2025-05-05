const std = @import("std");
const dvui = @import("dvui.zig");

pub const Point = PointType(.none);

pub fn PointType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        x: f32 = 0,
        y: f32 = 0,

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) PointType(.natural) else @compileError("tried to nest Point.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        pub const Physical = if (units == .none) PointType(.physical) else @compileError("tried to nest Point.Physical");

        pub fn cast(self: *const Self, pointType: type) pointType {
            return .{ .x = self.x, .y = self.y };
        }

        pub fn nonZero(self: *const Self) bool {
            return (self.x != 0 or self.y != 0);
        }

        pub fn plus(self: *const Self, b: Self) Self {
            return .{ .x = self.x + b.x, .y = self.y + b.y };
        }

        pub fn diff(a: Self, b: Self) Self {
            return .{ .x = a.x - b.x, .y = a.y - b.y };
        }

        pub fn min(a: Self, b: Self) Self {
            return .{ .x = @min(a.x, b.x), .y = @min(a.y, b.y) };
        }

        pub fn max(a: Self, b: Self) Self {
            return .{ .x = @max(a.x, b.x), .y = @max(a.y, b.y) };
        }

        /// Pass the scale and the type of Point it now represents.
        pub fn scale(self: *const Self, s: f32, pointType: type) pointType {
            return pointType{ .x = self.x * s, .y = self.y * s };
        }

        pub fn equals(self: *const Self, b: Self) bool {
            return (self.x == b.x and self.y == b.y);
        }

        pub fn length(self: *const Self) f32 {
            return @sqrt((self.x * self.x) + (self.y * self.y));
        }

        pub fn normalize(self: *const Self) Self {
            const d2 = self.x * self.x + self.y * self.y;
            if (d2 == 0) {
                return Self{ .x = 1.0, .y = 0.0 };
            } else {
                const inv_len = 1.0 / @sqrt(d2);
                return Self{ .x = self.x * inv_len, .y = self.y * inv_len };
            }
        }

        /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
        pub fn toNatural(self: Point.Physical) Point.Natural {
            return self.scale(1 / dvui.windowNaturalScale(), Point.Natural);
        }

        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            const type_name = switch (units) {
                .none => "Point",
                .natural => "Point.Natural",
                .physical => "Point.Physical",
            };
            try std.fmt.format(writer, "{s}{{ {d} {d} }}", .{ type_name, self.x, self.y });
        }

    };
}

test {
    @import("std").testing.refAllDecls(@This());
}
