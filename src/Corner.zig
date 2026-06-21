const std = @import("std");

const dvui = @import("dvui.zig");
pub const Point = dvui.Point;
pub const Theme = dvui.Theme;

pub const Corner = CornerType(.none);
pub const CornerRect = CornerRectType(.none);

pub fn CornerType(comptime units: dvui.enums.Units) type {
    return struct {
        pub const Style = enum {
            /// Based on the default corner setting, if there is none, arc will be used
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
        type: Style = .theme,
        /// radius or x offset
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

        // default helper functions
        pub fn default() Self {
            return .{ .type = .theme, .rx = -1, .y = -1 };
        }

        pub fn theme(r: f32) Self {
            return .{ .type = .theme, .rx = r, .y = r };
        }

        pub fn square() Self {
            return .{ .type = .square, .rx = 0, .y = 0 };
        }

        pub fn round(r: f32) Self {
            return .{ .type = .round, .rx = r, .y = r };
        }

        /// AKA The 45 degree corner cut
        pub fn chamfer(r: f32) Self {
            return .{ .type = .chamfer, .rx = r, .y = r };
        }

        /// Similar with the chamfer mode but with individual x, y control
        pub fn angular(x: f32, y: f32) Self {
            return .{ .type = .angular, .rx = x, .y = y };
        }

        /// Visually Move the corner instead of performing a cut
        pub fn nudge(x: f32, y: f32) Self {
            return .{ .type = .nudge, .rx = x, .y = y };
        }

        pub fn getRadius(self: Self) f32 {
            switch (self.type) {
                .square => return 0,
                .theme, .round, .chamfer => return self.rx,
                // If the corner modes are asymmetric, we will always use the longer side for proper padding
                .nudge, .angular => return @max(self.rx, self.y),
                // .oval => |c| return @max(c.x, c.y),
            }
        }

        /// PLEASE DON'T USE it as a user since this is made for the Path.addCorner() and other internal library functions Only.
        pub fn getRenderingOffsets(self: *const Corner.Physical, w: f32, h: f32) Point.Physical {
            switch (self.type) {
                .square => return .{ .x = 0, .y = 0 },
                .theme, .round, .chamfer => {
                    const min_r = @min(self.rx, w, h);
                    return .{ .x = min_r, .y = min_r };
                },
                .angular, .nudge => return .{ .x = @min(self.rx, w), .y = @min(self.y, h) },
            }
        }

        pub fn scale(self: *const Self, s: f32, comptime cornerType: type) cornerType {
            return cornerType{ .type = self.type, .rx = self.rx * s, .y = self.y * s };
        }

        /// Unless you are directly accessing the Path.addCorner() function, you don't need to run
        /// this since all the default widgets have this function called in the WidgetData type.
        pub fn determineDefaultCornerType(self: *Corner, theme_corner: ?Corner) void {
            if (self.type != .theme) return;
            self.type = if (theme_corner) |corner| if (corner.type == .theme) .round else corner.type else .round;
            if (self.rx == -1 or self.y == -1) {
                if (theme_corner) |corner| {
                    self.rx = corner.rx;
                    self.y = corner.y;
                } else {
                    self.rx = 5;
                    self.y = 5;
                }
            }
        }
    };
}

pub fn CornerRectType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        tl: CornerType(units) = .{ .type = .theme, .rx = 0, .y = 0 },
        tr: CornerType(units) = .{ .type = .theme, .rx = 0, .y = 0 },
        br: CornerType(units) = .{ .type = .theme, .rx = 0, .y = 0 },
        bl: CornerType(units) = .{ .type = .theme, .rx = 0, .y = 0 },

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

        pub fn defaults() Self {
            return .{ .tl = .default(), .tr = .default(), .bl = .default(), .br = .default() };
        }

        pub fn squares() Self {
            return .{ .tl = .square(), .tr = .square(), .bl = .square(), .br = .square() };
        }

        pub fn rounds(r: f32) Self {
            return CornerRectType(units).quadRounds(r, r, r, r);
        }

        pub fn quadRounds(r_tl: f32, r_tr: f32, r_br: f32, r_bl: f32) Self {
            return .{ .tl = .round(r_tl), .tr = .round(r_tr), .bl = .round(r_bl), .br = .round(r_br) };
        }

        pub fn chamfers(r: f32) Self {
            return CornerRectType(units).quadChamfers(r, r, r, r);
        }

        pub fn quadChamfers(r_tl: f32, r_tr: f32, r_br: f32, r_bl: f32) Self {
            return .{ .tl = .chamfer(r_tl), .tr = .chamfer(r_tr), .bl = .chamfer(r_bl), .br = .chamfer(r_br) };
        }

        pub fn all(r: f32) Self {
            return CornerRectType(units).quad(r, r, r, r);
        }

        /// With this mode, the program will use one of the primitive corner modes (none, arc, cut45)
        pub fn quad(r_tl: f32, r_tr: f32, r_br: f32, r_bl: f32) Self {
            // Since dvui current windows is not available upon compilation, the following method can't be used
            // This uses a hacky way since it is not allowed to have current_window to be null
            return .{ .tl = .{ .type = .theme, .rx = r_tl, .y = r_tl }, .tr = .{ .type = .theme, .rx = r_tr, .y = r_tr }, .bl = .{ .type = .theme, .rx = r_bl, .y = r_bl }, .br = .{ .type = .theme, .rx = r_br, .y = r_br } };
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
            const c_init: ?Corner = t.default_corner;

            ret.tl.determineDefaultCornerType(c_init);
            ret.tr.determineDefaultCornerType(c_init);
            ret.bl.determineDefaultCornerType(c_init);
            ret.br.determineDefaultCornerType(c_init);

            return ret;
        }
    };
}

test "CornerRect allArc" {
    const b = CornerRect.rounds(4);
    try std.testing.expectEqual(4, b.tl.rx);
    try std.testing.expectEqual(4, b.tr.rx);
    try std.testing.expectEqual(4, b.bl.rx);
    try std.testing.expectEqual(4, b.br.rx);
    try std.testing.expectEqual(Corner.Style.round, b.tl.type);
    try std.testing.expectEqual(Corner.Style.round, b.tr.type);
    try std.testing.expectEqual(Corner.Style.round, b.bl.type);
    try std.testing.expectEqual(Corner.Style.round, b.br.type);

    try std.testing.expectEqual(CornerRectType(.none), @TypeOf(b));
}

test "CornerRect Physical all45Cut" {
    const b = CornerRect.Physical.chamfers(4);
    try std.testing.expectEqual(4, b.tl.y);
    try std.testing.expectEqual(4, b.tr.y);
    try std.testing.expectEqual(4, b.bl.y);
    try std.testing.expectEqual(4, b.br.y);
    try std.testing.expectEqual(Corner.Style.chamfer, b.tl.type);
    try std.testing.expectEqual(Corner.Style.chamfer, b.tr.type);
    try std.testing.expectEqual(Corner.Style.chamfer, b.bl.type);
    try std.testing.expectEqual(Corner.Style.chamfer, b.br.type);

    try std.testing.expectEqual(CornerRectType(.physical), @TypeOf(b));
}

test "Corner Type Tests" {
    const c = Corner.round(10);
    try std.testing.expectEqual(Corner.Style.round, c.type);
    try std.testing.expectEqual(10, c.rx);
    try std.testing.expectEqual(10, c.y);

    const c2 = Corner.chamfer(12);
    try std.testing.expectEqual(Corner.Style.chamfer, c2.type);
    try std.testing.expectEqual(12, c2.rx);
    try std.testing.expectEqual(12, c2.y);

    const c3 = Corner.angular(14, 16);
    try std.testing.expectEqual(Corner.Style.angular, c3.type);
    try std.testing.expectEqual(14, c3.rx);
    try std.testing.expectEqual(16, c3.y);

    const c4 = Corner.default();
    try std.testing.expectEqual(Corner.Style.theme, c4.type);
    try std.testing.expectEqual(-1, c4.rx);
    try std.testing.expectEqual(-1, c4.y);
}

test "Corner Function Tests" {
    const t800_theme = dvui.Theme.builtin.tech_800;
    var c = Corner.default();
    c.determineDefaultCornerType(t800_theme.default_corner.?);

    try std.testing.expectEqual(Corner.Style.angular, c.type);
    try std.testing.expectEqual(16, c.rx);
    try std.testing.expectEqual(8, c.y);

    var c2 = Corner.chamfer(10);
    const cp = c2.scale(15.0, Corner.Physical);
    try std.testing.expectEqual(150, cp.rx);
    try std.testing.expectEqual(150, cp.y);
    try std.testing.expectEqual(Corner.Physical, Corner.Physical);
}
