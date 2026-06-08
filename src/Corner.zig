const std = @import("std");
const dvui = @import("dvui.zig");

pub const Corner = CornerType(.none);
pub const CornerRect = CornerRectType(.none);

pub const CornerKind = enum {
    none,
    arc,
    angular,
    oval,
    // intrude_x, // radius and intrude depth
    // intrude_y, // same but in y direction
};

pub fn CornerType(comptime units: dvui.enums.Units) type {
    return union(CornerKind) {
        const Self = @This();

        none,
        arc: f32,
        angular: struct { x: f32, y: f32 },
        oval: struct { x: f32, y: f32 },

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) CornerType(.natural) else @compileError("tried to nest Point.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        ///
        /// To convert between Point and Point.Physical, use `RectScale.pointToPhysical` and `RectScale.pointFromPhysical`
        pub const Physical = if (units == .none) CornerType(.physical) else @compileError("tried to nest Point.Physical");

        pub fn get_radius(self: Self) f32 {
            switch (self) {
                .arc => |r| return r,
                // keeping the corner span within the similar bound as arc, thus getting the larger coordination
                .angular, .oval => |c| return @max(c.x, c.y),
            }
        }
    };
}

pub fn CornerRectType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        tl: CornerType(units) = .none,
        tr: CornerType(units) = .none,
        bl: CornerType(units) = .none,
        br: CornerType(units) = .none,

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) CornerRectType(.natural) else @compileError("tried to nest Point.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        ///
        /// To convert between Point and Point.Physical, use `RectScale.pointToPhysical` and `RectScale.pointFromPhysical`
        pub const Physical = if (units == .none) CornerRectType(.physical) else @compileError("tried to nest Point.Physical");

        pub fn allArc(r: f32) Self {
            return CornerRectType(units).quadArc(r, r, r, r);
        }

        pub fn quadArc(rtl: f32, rtr: f32, rbl: f32, rbr: f32) Self {
            return .{
                .tl = .{ .arc = rtl },
                .tr = .{ .arc = rtr },
                .bl = .{ .arc = rbl },
                .br = .{ .arc = rbr },
            };
        }

        pub fn all45Cut(r: f32) Self {
            return CornerRectType(units).quad45Cut(r, r, r, r);
        }

        pub fn quad45Cut(rtl: f32, rtr: f32, rbl: f32, rbr: f32) Self {
            return .{
                .tl = .{ .angular = .{ .x = rtl, .y = rtl } },
                .tr = .{ .angular = .{ .x = rtr, .y = rtr } },
                .bl = .{ .angular = .{ .x = rbl, .y = rbl } },
                .br = .{ .angular = .{ .x = rbr, .y = rbr } },
            };
        }
    };
}

test "CornerRect allArc" {
    const b = CornerRect.allArc(4);
    try std.testing.expectEqual(4, b.tl.arc);
    try std.testing.expectEqual(4, b.tr.arc);
    try std.testing.expectEqual(4, b.bl.arc);
    try std.testing.expectEqual(4, b.br.arc);

    try std.testing.expectEqual(CornerRectType(.none), @TypeOf(b));
}

test "CornerRect Physical all45Cut" {
    const b = CornerRect.Physical.allArc(4);
    try std.testing.expectEqual(4, b.tl.arc);
    try std.testing.expectEqual(4, b.tr.arc);
    try std.testing.expectEqual(4, b.bl.arc);
    try std.testing.expectEqual(4, b.br.arc);

    try std.testing.expectEqual(CornerRectType(.physical), @TypeOf(b));
}
