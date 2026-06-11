const std = @import("std");

const dvui = @import("dvui.zig");
pub const Point = dvui.Point;

pub const Corner = CornerType(.none);
pub const CornerRect = CornerRectType(.none);
pub const CornerKind = enum {
    // primitive modes
    /// Only for primitive corner modes, including none, arc, cut45
    theme,
    none,
    arc,
    cut45,
    // extended mode, users have to call them manually since they are geometrically instable for default theming
    nudge_x, // offset the point by x or y axis, used for constructing trapezoid or diamonds
    nudge_y,
    angular,
    // oval,
    // intrude_x, // radius and intrude depth
    // intrude_y, // same but in y direction
};

pub fn CornerType(comptime units: dvui.enums.Units) type {
    return union(CornerKind) {
        const Self = @This();
        // primitive modes
        theme: f32,
        none,
        arc: f32,
        cut45: f32,
        // extended mode
        nudge_x: f32,
        nudge_y: f32,
        angular: struct { x: f32, y: f32 },
        // oval: struct { x: f32, y: f32 },

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) CornerType(.natural) else @compileError("tried to nest Point.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        ///
        /// To convert between Point and Point.Physical, use `RectScale.pointToPhysical` and `RectScale.pointFromPhysical`
        pub const Physical = if (units == .none) CornerType(.physical) else @compileError("tried to nest Point.Physical");

        pub fn getRadius(self: Self) f32 {
            switch (self) {
                .none => return 0,
                .theme, .arc, .nudge_x, .nudge_y, .cut45 => |r| return r,
                // If the corner modes are asymmetric, we will always use the longer side for proper padding
                .angular => |c| return @max(c.x, c.y),
                // .oval => |c| return @max(c.x, c.y),
            }
        }

        /// This is should only be used in the rendering process
        pub fn getRenderingOffsets(self: Corner.Physical, w: f32, h: f32) Point.Physical {
            switch (self) {
                .none => return .{ .x = 0, .y = 0 },
                .theme, .arc, .nudge_x, .nudge_y, .cut45 => |r| {
                    const min_r = @min(r, w, h);
                    return .{ .x = min_r, .y = min_r };
                },
                .angular => |c| return .{ .x = @min(c.x, w), .y = @min(c.y, h) },
                // .oval => |c| return .{ c.x, c.y },
            }
        }

        /// The is the substitution to the original radius @min comparison used in the themeOverride function
        pub fn min(self: Self, other: Self) Self {
            const otheradius = other.getRadius();
            switch (self) {
                .none => return .{ .none = {} },
                .theme => |r| return .{ .theme = @min(r, otheradius) },
                .arc => |r| return .{ .arc = @min(r, otheradius) },
                .cut45 => |r| return .{ .cut45 = @min(r, otheradius) },
                .nudge_x => |r| return .{ .nudge_x = @min(r, otheradius) },
                .nudge_y => |r| return .{ .nudge_y = @min(r, otheradius) },
                .angular => |p| return .{ .angular = .{ .x = @min(p.y, otheradius), .y = @min(p.x, otheradius) } },
                // .oval => |p| return .{ .oval = .{ .x = @min(p.y, otheradius), .y = @min(p.x, otheradius) } },
            }
        }

        pub fn scale(self: Self, s: f32, comptime cornerType: type) cornerType {
            return switch (self) {
                .none => cornerType{ .none = {} },
                .theme => |r| cornerType{ .theme = r * s },
                .arc => |r| cornerType{ .arc = r * s },
                .cut45 => |r| cornerType{ .cut45 = r * s },
                .nudge_x => |r| cornerType{ .nudge_x = r * s },
                .nudge_y => |r| cornerType{ .nudge_y = r * s },
                .angular => |p| cornerType{ .angular = .{ .x = p.x * s, .y = p.y * s } },
            };
        }
    };
}

pub fn CornerRectType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        tl: CornerType(units) = .{ .theme = 0 },
        tr: CornerType(units) = .{ .theme = 0 },
        bl: CornerType(units) = .{ .theme = 0 },
        br: CornerType(units) = .{ .theme = 0 },

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) CornerRectType(.natural) else @compileError("tried to nest Point.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        ///
        /// To convert between Point and Point.Physical, use `RectScale.pointToPhysical` and `RectScale.pointFromPhysical`
        pub const Physical = if (units == .none) CornerRectType(.physical) else @compileError("tried to nest Point.Physical");

        pub fn allNone() Self {
            return .{
                .tl = .{ .none = {} },
                .tr = .{ .none = {} },
                .bl = .{ .none = {} },
                .br = .{ .none = {} },
            };
        }

        pub fn allArc(r: f32) Self {
            return CornerRectType(units).quadArc(r, r, r, r);
        }

        pub fn quadArc(rtl: f32, rtr: f32, rbr: f32, rbl: f32) Self {
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

        pub fn quad45Cut(rtl: f32, rtr: f32, rbr: f32, rbl: f32) Self {
            return .{
                .tl = .{ .angular = .{ .x = rtl, .y = rtl } },
                .tr = .{ .angular = .{ .x = rtr, .y = rtr } },
                .bl = .{ .angular = .{ .x = rbl, .y = rbl } },
                .br = .{ .angular = .{ .x = rbr, .y = rbr } },
            };
        }

        /// With this mode, the program will use one of the primitive corner modes (none, arc, cut45)
        pub fn all(r: f32) Self {
            return CornerRectType(units).quad(r, r, r, r);
        }

        /// With this mode, the program will use one of the primitive corner modes (none, arc, cut45)
        pub fn quad(rtl: f32, rtr: f32, rbr: f32, rbl: f32) Self {
            // Since dvui current windows is not available upon compilation, the following method can't be used
            // This uses a hacky way since it is not allowed to have current_window to be null
            return .{
                .tl = .{ .theme = rtl },
                .tr = .{ .theme = rtr },
                .bl = .{ .theme = rbl },
                .br = .{ .theme = rbr },
            };
        }

        pub fn scale(self: Self, s: f32, comptime cornerRectType: type) cornerRectType {
            const cornerType = switch (cornerRectType) {
                CornerRect => Corner,
                CornerRect.Physical => Corner.Physical,
                CornerRect.Natural => Corner.Natural,
                else => @compileError("Invalid Type. Please make sure your type is either CornerRect, CornerRect.Physical or CornerRect.Natural"),
            };

            return cornerRectType{
                .bl = self.bl.scale(s, cornerType),
                .br = self.br.scale(s, cornerType),
                .tl = self.tl.scale(s, cornerType),
                .tr = self.tr.scale(s, cornerType),
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
