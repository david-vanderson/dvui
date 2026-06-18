const std = @import("std");

const dvui = @import("dvui.zig");
pub const Point = dvui.Point;
pub const Theme = dvui.Theme;

pub const Corner = CornerType(.none);
pub const CornerRect = CornerRectType(.none);

pub fn CornerType(comptime units: dvui.enums.Units) type {
    return struct {
        pub const Style = enum {
            /// DON'T use this unless you are defining the default option for your widgets
            widget_default,
            /// Based on the default corner setting, if there is none, arc will be used
            theme,
            arc,
            cut45,
            nudge, // offset the point by x or y axis, used for constructing trapezoid or diamonds
            angular,

            // The following modes are planned, but due to the niche use case and the restriction,
            // to the corner mode, I am not going to release them in the current iteration

            // oval,
            // intrude_x, // radius and intrude depth
            // intrude_y, // same but in y direction
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
        pub fn widgetDefault(x: f32, y: f32) Self {
            return .{ .type = .widget_default, .rx = x, .y = y };
        }

        pub fn none() Self {
            return .{ .type = .arc, .rx = 0, .y = 0 };
        }

        pub fn arc(r: f32) Self {
            return .{ .type = .arc, .rx = r, .y = r };
        }

        pub fn cut45(r: f32) Self {
            return .{ .type = .cut45, .rx = r, .y = r };
        }

        pub fn angular(x: f32, y: f32) Self {
            return .{ .type = .angular, .rx = x, .y = y };
        }

        pub fn nudge(x: f32, y: f32) Self {
            return .{ .type = .nudge, .rx = x, .y = y };
        }

        pub fn getRadius(self: Self) f32 {
            switch (self.type) {
                .theme, .arc, .cut45, .widget_default => return self.rx,
                // If the corner modes are asymmetric, we will always use the longer side for proper padding
                .nudge, .angular => return @max(self.rx, self.y),
                // .oval => |c| return @max(c.x, c.y),
            }
        }

        /// This is should only be used in the rendering process
        pub fn getRenderingOffsets(self: *const Corner.Physical, w: f32, h: f32) Point.Physical {
            switch (self.type) {
                .theme, .arc, .cut45, .widget_default => {
                    const min_r = @min(self.rx, w, h);
                    return .{ .x = min_r, .y = min_r };
                },
                .angular, .nudge => return .{ .x = @min(self.rx, w), .y = @min(self.y, h) },
            }
        }

        pub fn scale(self: *const Self, s: f32, comptime cornerType: type) cornerType {
            return cornerType{ .type = self.type, .rx = self.rx * s, .y = self.y * s };
        }

        /// This can only be used within this type
        fn _determineDefaultCornerType(self: *Corner, theme_corner: ?Corner) void {
            if (self.type != .theme and self.type != .widget_default) return;
            if (theme_corner == null or theme_corner.?.type == .widget_default or theme_corner.?.type == .theme) {
                self.type = .arc;
                return;
            }
            switch (self.type) {
                .widget_default => {
                    self.type = theme_corner.?.type;
                    self.rx = @min(self.rx, theme_corner.?.rx);
                    self.y = @min(self.y, theme_corner.?.y);
                },
                .theme => {
                    self.type = theme_corner.?.type;
                },
                else => {},
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

        pub fn allWidgetDefault(x: f32, y: f32) Self {
            return .{ .tl = .widgetDefault(x, y), .tr = .widgetDefault(x, y), .bl = .widgetDefault(x, y), .br = .widgetDefault(x, y) };
        }

        pub fn allNone() Self {
            return .{ .tl = .none(), .tr = .none(), .bl = .none(), .br = .none() };
        }

        pub fn allArc(r: f32) Self {
            return CornerRectType(units).quadArc(r, r, r, r);
        }

        pub fn quadArc(r_tl: f32, r_tr: f32, r_br: f32, r_bl: f32) Self {
            return .{ .tl = .arc(r_tl), .tr = .arc(r_tr), .bl = .arc(r_bl), .br = .arc(r_br) };
        }

        pub fn all45Cut(r: f32) Self {
            return CornerRectType(units).quad45Cut(r, r, r, r);
        }

        pub fn quad45Cut(r_tl: f32, r_tr: f32, r_br: f32, r_bl: f32) Self {
            return .{ .tl = .cut45(r_tl), .tr = .cut45(r_tr), .bl = .cut45(r_bl), .br = .cut45(r_br) };
        }

        /// With this mode, the program will use one of the primitive corner modes (none, arc, cut45)
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
        /// if the corner mode is in .theme. To simplify the process, .Physical and
        /// Natural type are forbidden in this mode, and scale() should be used for that
        /// purpose.
        pub fn finalize(self: *const CornerRect, theme: ?*const Theme) CornerRect {
            var ret = self.*;
            const t: *const Theme = theme orelse &dvui.themeGet();
            const c_init: ?Corner = t.default_corner;

            ret.tl._determineDefaultCornerType(c_init);
            ret.tr._determineDefaultCornerType(c_init);
            ret.bl._determineDefaultCornerType(c_init);
            ret.br._determineDefaultCornerType(c_init);

            return ret;
        }
    };
}

test "CornerRect allArc" {
    const b = CornerRect.allArc(4);
    try std.testing.expectEqual(4, b.tl.rx);
    try std.testing.expectEqual(4, b.tr.rx);
    try std.testing.expectEqual(4, b.bl.rx);
    try std.testing.expectEqual(4, b.br.rx);
    try std.testing.expectEqual(Corner.Style.arc, b.tl.type);
    try std.testing.expectEqual(Corner.Style.arc, b.tr.type);
    try std.testing.expectEqual(Corner.Style.arc, b.bl.type);
    try std.testing.expectEqual(Corner.Style.arc, b.br.type);

    try std.testing.expectEqual(CornerRectType(.none), @TypeOf(b));
}

test "CornerRect Physical all45Cut" {
    const b = CornerRect.Physical.all45Cut(4);
    try std.testing.expectEqual(4, b.tl.y);
    try std.testing.expectEqual(4, b.tr.y);
    try std.testing.expectEqual(4, b.bl.y);
    try std.testing.expectEqual(4, b.br.y);
    try std.testing.expectEqual(Corner.Style.cut45, b.tl.type);
    try std.testing.expectEqual(Corner.Style.cut45, b.tr.type);
    try std.testing.expectEqual(Corner.Style.cut45, b.bl.type);
    try std.testing.expectEqual(Corner.Style.cut45, b.br.type);

    try std.testing.expectEqual(CornerRectType(.physical), @TypeOf(b));
}

test "Corner Type Tests" {
    const c = Corner.arc(10);
    try std.testing.expectEqual(Corner.Style.arc, c.type);
    try std.testing.expectEqual(10, c.rx);
    try std.testing.expectEqual(10, c.y);

    const c2 = Corner.cut45(12);
    try std.testing.expectEqual(Corner.Style.cut45, c2.type);
    try std.testing.expectEqual(12, c2.rx);
    try std.testing.expectEqual(12, c2.y);

    const c3 = Corner.angular(14, 16);
    try std.testing.expectEqual(Corner.Style.angular, c3.type);
    try std.testing.expectEqual(14, c3.rx);
    try std.testing.expectEqual(16, c3.y);

    const c4 = Corner.widgetDefault(18, 20);
    try std.testing.expectEqual(Corner.Style.widget_default, c4.type);
    try std.testing.expectEqual(18, c4.rx);
    try std.testing.expectEqual(20, c4.y);
}

test "Corner Function Tests" {
    const win89_theme = dvui.Theme.builtin.win98;
    var c = Corner.widgetDefault(10, 20);
    c._determineDefaultCornerType(win89_theme.default_corner.?);

    try std.testing.expectEqual(Corner.Style.arc, c.type);
    try std.testing.expectEqual(0, c.rx);
    try std.testing.expectEqual(0, c.y);

    var c2 = Corner.cut45(10);
    const cp = c2.scale(15.0, Corner.Physical);
    try std.testing.expectEqual(150, cp.rx);
    try std.testing.expectEqual(150, cp.y);
    try std.testing.expectEqual(Corner.Physical, Corner.Physical);
}
