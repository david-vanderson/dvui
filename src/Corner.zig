const std = @import("std");

const dvui = @import("dvui.zig");
pub const Point = dvui.Point;
pub const Theme = dvui.Theme;

pub const Corner = CornerType(.none);
pub const CornerRect = CornerRectType(.none);
pub const CornerKind = enum {
    // primitive modes
    /// Only for primitive corner modes, including none, arc, cut45
    theme,
    arc,
    cut45,
    // extended mode, users have to call them manually since they are geometrically instable for default theming
    nudge, // offset the point by x or y axis, used for constructing trapezoid or diamonds
    angular,
    // oval,
    // intrude_x, // radius and intrude depth
    // intrude_y, // same but in y direction
};

pub fn CornerType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();
        type: CornerKind = .theme,
        x: f32 = 0,
        y: f32 = 0,

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) CornerType(.natural) else @compileError("tried to nest Point.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        ///
        /// To convert between Point and Point.Physical, use `RectScale.pointToPhysical` and `RectScale.pointFromPhysical`
        pub const Physical = if (units == .none) CornerType(.physical) else @compileError("tried to nest Point.Physical");

        // default helper functions
        pub fn none() Self {
            return .{ .type = .arc, .x = 0, .y = 0 };
        }

        pub fn arc(r: f32) Self {
            return .{ .type = .arc, .x = r, .y = r };
        }

        pub fn cut45(r: f32) Self {
            return .{ .type = .cut45, .x = r, .y = r };
        }

        pub fn getRadius(self: Self) f32 {
            switch (self.type) {
                .theme, .arc, .cut45 => return self.x,
                // If the corner modes are asymmetric, we will always use the longer side for proper padding
                .nudge, .angular => return @max(self.x, self.y),
                // .oval => |c| return @max(c.x, c.y),
            }
        }

        /// This is should only be used in the rendering process
        pub fn getRenderingOffsets(self: *const Corner.Physical, w: f32, h: f32) Point.Physical {
            switch (self.type) {
                .theme, .arc, .cut45 => {
                    const min_r = @min(self.x, w, h);
                    return .{ .x = min_r, .y = min_r };
                },
                .angular, .nudge => return .{ .x = @min(self.x, w), .y = @min(self.y, h) },
                // .oval => |c| return .{ c.x, c.y },
            }
        }

        /// The is the substitution to the original radius @min comparison used in the themeOverride function
        pub fn min(self: *const Self, other: Self) Self {
            var ret = self.*;
            ret.x = @min(ret.x, other.x);
            ret.y = @min(ret.y, other.y);

            return ret;
        }

        pub fn scale(self: *const Self, s: f32, comptime cornerType: type) cornerType {
            return cornerType{ .type = self.type, .x = self.x * s, .y = self.y * s };
        }

        /// This is used for transforming one type of union into another while retaining the
        /// original radius or dimension value. Usually used for converting between .theme into
        /// other default mode.
        pub fn asType(self: *const Self, new_type: CornerKind) Self {
            var ret = self.*;
            ret.type = new_type;

            return ret;
        }
    };
}

pub fn CornerRectType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        tl: CornerType(units) = .{ .type = .theme, .x = 0, .y = 0 },
        tr: CornerType(units) = .{ .type = .theme, .x = 0, .y = 0 },
        bl: CornerType(units) = .{ .type = .theme, .x = 0, .y = 0 },
        br: CornerType(units) = .{ .type = .theme, .x = 0, .y = 0 },

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) CornerRectType(.natural) else @compileError("tried to nest Point.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        ///
        /// To convert between Point and Point.Physical, use `RectScale.pointToPhysical` and `RectScale.pointFromPhysical`
        pub const Physical = if (units == .none) CornerRectType(.physical) else @compileError("tried to nest Point.Physical");

        /// Only for optimizing the performance of corner drawing, building the constants in comptime mode
        pub const Position = enum { tl, tr, bl, br };

        pub fn allNone() Self {
            return .{
                .tl = .none(),
                .tr = .none(),
                .bl = .none(),
                .br = .none(),
            };
        }

        pub fn allArc(r: f32) Self {
            return CornerRectType(units).quadArc(r, r, r, r);
        }

        pub fn quadArc(rtl: f32, rtr: f32, rbr: f32, rbl: f32) Self {
            return .{
                .tl = .arc(rtl),
                .tr = .arc(rtr),
                .bl = .arc(rbl),
                .br = .arc(rbr),
            };
        }

        pub fn all45Cut(r: f32) Self {
            return CornerRectType(units).quad45Cut(r, r, r, r);
        }

        pub fn quad45Cut(rtl: f32, rtr: f32, rbr: f32, rbl: f32) Self {
            return .{
                .tl = .cut45(rtl),
                .tr = .cut45(rtr),
                .bl = .cut45(rbl),
                .br = .cut45(rbr),
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
                .tl = .{ .type = .theme, .x = rtl, .y = rtl },
                .tr = .{ .type = .theme, .x = rtr, .y = rtr },
                .bl = .{ .type = .theme, .x = rbl, .y = rbl },
                .br = .{ .type = .theme, .x = rbr, .y = rbr },
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

        // /// Determine the final corner mode based on the default or given theme settings
        // /// if the corner mode is in .theme.
        // pub fn finalize(self: *const Self, theme: ?*const Theme) Self {
        //     var ret = self.*;
        //     const t: *const Theme = theme orelse &dvui.themeGet();

        //     const c_init: Corner = t.default_corner orelse Corner{ .arc = 0 };
        //     const c = switch (Self) {
        //         CornerRect.Physical => c_init.scale(dvui.windowNaturalScale(), Corner.Physical),
        //         CornerRect.Natural => c_init.scale(dvui.windowNaturalScale(), Corner.Natural),
        //         else => c_init,
        //     };

        //     if (ret.tl == .theme) ret.tl = c;
        //     if (ret.tr == .theme) ret.tr = c;
        //     if (ret.bl == .theme) ret.bl = c;
        //     if (ret.br == .theme) ret.br = c;

        //     return ret;
        // }
    };
}

test "CornerRect allArc" {
    const b = CornerRect.allArc(4);
    try std.testing.expectEqual(4, b.tl.x);
    try std.testing.expectEqual(4, b.tr.x);
    try std.testing.expectEqual(4, b.bl.x);
    try std.testing.expectEqual(4, b.br.x);
    try std.testing.expectEqual(CornerKind.arc, b.tl.type);
    try std.testing.expectEqual(CornerKind.arc, b.tr.type);
    try std.testing.expectEqual(CornerKind.arc, b.bl.type);
    try std.testing.expectEqual(CornerKind.arc, b.br.type);

    try std.testing.expectEqual(CornerRectType(.none), @TypeOf(b));
}

test "CornerRect Physical all45Cut" {
    const b = CornerRect.Physical.allArc(4);
    try std.testing.expectEqual(4, b.tl.y);
    try std.testing.expectEqual(4, b.tr.y);
    try std.testing.expectEqual(4, b.bl.y);
    try std.testing.expectEqual(4, b.br.y);
    try std.testing.expectEqual(CornerKind.arc, b.tl.type);
    try std.testing.expectEqual(CornerKind.arc, b.tr.type);
    try std.testing.expectEqual(CornerKind.arc, b.bl.type);
    try std.testing.expectEqual(CornerKind.arc, b.br.type);

    try std.testing.expectEqual(CornerRectType(.physical), @TypeOf(b));
}
