const std = @import("std");

const dvui = @import("dvui.zig");
pub const Point = dvui.Point;
pub const Theme = dvui.Theme;

pub const Corner = CornerType(.none);
pub const CornerRect = CornerRectType(.none);

pub fn CornerType(comptime units: dvui.enums.Units) type {
    return struct {
        pub const Style = enum {
            /// Use theme corner kind.  If rx/y is -1, also use theme corner size.
            theme,
            square,
            round,
            chamfer,
            nudge, // offset the point by x or y axis, used for constructing trapezoid or diamonds
            angular,

            // The following mode is planned in the next iteration, but require more experiment
            // custom, // passing a function pointer so that it will cover all the niche "corner" cases
        };

        const Self = @This();
        kind: Style = .theme,
        /// radius or x offset, -1 means get size from theme
        rx: f32 = 0,
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

        pub const default: Self = .theme(-1);
        pub const square: Self = .{ .kind = .square };

        pub fn theme(r: f32) Self {
            return .{ .kind = .theme, .rx = r, .y = r };
        }

        pub fn round(r: f32) Self {
            return .{ .kind = .round, .rx = r, .y = r };
        }

        /// AKA The 45 degree corner cut
        pub fn chamfer(r: f32) Self {
            return .{ .kind = .chamfer, .rx = r, .y = r };
        }

        /// Similar with the chamfer mode but with individual x, y control
        pub fn angular(x: f32, y: f32) Self {
            return .{ .kind = .angular, .rx = x, .y = y };
        }

        /// Visually Move the corner instead of performing a cut
        pub fn nudge(x: f32, y: f32) Self {
            return .{ .kind = .nudge, .rx = x, .y = y };
        }

        pub fn radius(self: Self) f32 {
            switch (self.kind) {
                .square => return 0,
                .theme, .round, .chamfer => return @max(0, self.rx),
                // If the corner modes are asymmetric, we will always use the longer side for proper padding
                .nudge, .angular => return @max(self.rx, self.y),
            }
        }

        /// PLEASE DON'T USE it as a user since this is made for the Path.addCorner() and other internal library functions Only.
        pub fn getRenderingOffsets(self: *const Corner.Physical, w: f32, h: f32) Point.Physical {
            switch (self.kind) {
                .square => return .{ .x = 0, .y = 0 },
                .theme, .round, .chamfer => {
                    const min_r = @min(self.rx, w, h);
                    return .{ .x = min_r, .y = min_r };
                },
                .angular, .nudge => return .{ .x = @min(self.rx, w), .y = @min(self.y, h) },
            }
        }

        pub fn scale(self: *const Self, s: f32, comptime cornerType: type) cornerType {
            return cornerType{ .kind = self.kind, .rx = self.rx * s, .y = self.y * s };
        }

        /// Unless you are directly accessing the Path.addCorner() function, you don't need to run
        /// this since all the default widgets have this function called in the WidgetData type.
        pub fn finalize(self: *const Corner, theme_corner: Corner) Corner {
            if (self.kind != .theme) return self.*;

            var ret = self.*;
            ret.kind = theme_corner.kind;
            if (ret.rx == -1) ret.rx = theme_corner.rx;
            if (ret.y == -1) ret.y = theme_corner.y;
            return ret;
        }
    };
}

pub fn CornerRectType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        tl: CornerType(units) = .{},
        tr: CornerType(units) = .{},
        br: CornerType(units) = .{},
        bl: CornerType(units) = .{},

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

        /// Use theme corner kind and size.
        pub const default: Self = .{ .tl = .default, .tr = .default, .bl = .default, .br = .default };

        /// Sharp corners.
        pub const square: Self = .{ .tl = .square, .tr = .square, .bl = .square, .br = .square };

        /// Round corners with r radius.
        pub fn round(r: f32) Self {
            return .{ .tl = .round(r), .tr = .round(r), .bl = .round(r), .br = .round(r) };
        }

        /// Cut corners r distance in on a 45 deg angle.
        pub fn chamfer(r: f32) Self {
            return .{ .tl = .chamfer(r), .tr = .chamfer(r), .bl = .chamfer(r), .br = .chamfer(r) };
        }

        /// Use theme corner kind but with r size.
        pub fn all(r: f32) Self {
            return .{ .tl = .theme(r), .tr = .theme(r), .bl = .theme(r), .br = .theme(r) };
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

        /// Determine the final corner mode based on the default or given theme settings
        /// if the corner mode is in .theme. Unless you are directly accessing the
        /// Path.addCorner() function, you don't need to run this since all the default
        /// widgets have this function called in the WidgetData type.
        pub fn finalize(self: *const CornerRect, theme: ?*const Theme) CornerRect {
            var ret = self.*;
            const t: *const Theme = theme orelse &dvui.themeGet();

            ret.tl = ret.tl.finalize(t.corner);
            ret.tr = ret.tr.finalize(t.corner);
            ret.bl = ret.bl.finalize(t.corner);
            ret.br = ret.br.finalize(t.corner);

            return ret;
        }
    };
}

test "CornerRect allArc" {
    const b = CornerRect.round(4);
    try std.testing.expectEqual(4, b.tl.rx);
    try std.testing.expectEqual(4, b.tr.rx);
    try std.testing.expectEqual(4, b.bl.rx);
    try std.testing.expectEqual(4, b.br.rx);
    try std.testing.expectEqual(Corner.Style.round, b.tl.kind);
    try std.testing.expectEqual(Corner.Style.round, b.tr.kind);
    try std.testing.expectEqual(Corner.Style.round, b.bl.kind);
    try std.testing.expectEqual(Corner.Style.round, b.br.kind);

    try std.testing.expectEqual(CornerRectType(.none), @TypeOf(b));
}

test "CornerRect Physical all45Cut" {
    const b = CornerRect.Physical.chamfer(4);
    try std.testing.expectEqual(4, b.tl.y);
    try std.testing.expectEqual(4, b.tr.y);
    try std.testing.expectEqual(4, b.bl.y);
    try std.testing.expectEqual(4, b.br.y);
    try std.testing.expectEqual(Corner.Style.chamfer, b.tl.kind);
    try std.testing.expectEqual(Corner.Style.chamfer, b.tr.kind);
    try std.testing.expectEqual(Corner.Style.chamfer, b.bl.kind);
    try std.testing.expectEqual(Corner.Style.chamfer, b.br.kind);

    try std.testing.expectEqual(CornerRectType(.physical), @TypeOf(b));
}

test "Corner Type Tests" {
    const c = Corner.round(10);
    try std.testing.expectEqual(Corner.Style.round, c.kind);
    try std.testing.expectEqual(10, c.rx);
    try std.testing.expectEqual(10, c.y);

    const c2 = Corner.chamfer(12);
    try std.testing.expectEqual(Corner.Style.chamfer, c2.kind);
    try std.testing.expectEqual(12, c2.rx);
    try std.testing.expectEqual(12, c2.y);

    const c3 = Corner.angular(14, 16);
    try std.testing.expectEqual(Corner.Style.angular, c3.kind);
    try std.testing.expectEqual(14, c3.rx);
    try std.testing.expectEqual(16, c3.y);

    const c4 = Corner.default;
    try std.testing.expectEqual(Corner.Style.theme, c4.kind);
    try std.testing.expectEqual(-1, c4.rx);
    try std.testing.expectEqual(-1, c4.y);
}

test "Corner Function Tests" {
    const t800_theme = dvui.Theme.builtin.tech_800;
    const c = Corner.default.finalize(t800_theme.corner);

    try std.testing.expectEqual(Corner.Style.angular, c.kind);
    try std.testing.expectEqual(16, c.rx);
    try std.testing.expectEqual(8, c.y);

    var c2 = Corner.chamfer(10);
    const cp = c2.scale(15.0, Corner.Physical);
    try std.testing.expectEqual(150, cp.rx);
    try std.testing.expectEqual(150, cp.y);
    try std.testing.expectEqual(Corner.Physical, Corner.Physical);
}
