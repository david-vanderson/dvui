const std = @import("std");
const dvui = @import("dvui.zig");

const Point = dvui.Point;
const Size = dvui.Size;

const Rect = @This();

x: f32 = 0,
y: f32 = 0,
w: f32 = 0,
h: f32 = 0,

pub fn equals(self: *const Rect, r: Rect) bool {
    return (self.x == r.x and self.y == r.y and self.w == r.w and self.h == r.h);
}

pub fn plus(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w + r.w, .h = self.h + r.h };
}

pub fn nonZero(self: *const Rect) bool {
    return (self.x != 0 or self.y != 0 or self.w != 0 or self.h != 0);
}

pub fn all(v: f32) Rect {
    return Rect{ .x = v, .y = v, .w = v, .h = v };
}

pub fn fromPoint(p: Point) Rect {
    return Rect{ .x = p.x, .y = p.y };
}

pub fn toPoint(self: *const Rect, p: Point) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = p.x - self.x, .h = p.y - self.y };
}

pub fn toSize(self: *const Rect, s: Size) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = s.w, .h = s.h };
}

pub fn justSize(self: *const Rect) Rect {
    return Rect{ .x = 0, .y = 0, .w = self.w, .h = self.h };
}

pub fn topLeft(self: *const Rect) Point {
    return Point{ .x = self.x, .y = self.y };
}

pub fn topRight(self: *const Rect) Point {
    return Point{ .x = self.x + self.w, .y = self.y };
}

pub fn bottomLeft(self: *const Rect) Point {
    return Point{ .x = self.x, .y = self.y + self.h };
}

pub fn bottomRight(self: *const Rect) Point {
    return Point{ .x = self.x + self.w, .y = self.y + self.h };
}

pub fn center(self: *const Rect) Point {
    return Point{ .x = self.x + self.w / 2, .y = self.y + self.h / 2 };
}

pub fn size(self: *const Rect) Size {
    return Size{ .w = self.w, .h = self.h };
}

pub fn contains(self: *const Rect, p: Point) bool {
    return (p.x >= self.x and p.x <= (self.x + self.w) and p.y >= self.y and p.y <= (self.y + self.h));
}

pub fn empty(self: *const Rect) bool {
    return (self.w == 0 or self.h == 0);
}

/// ![image](Rect-scale.png)
pub fn scale(self: *const Rect, s: f32) Rect {
    return Rect{ .x = self.x * s, .y = self.y * s, .w = self.w * s, .h = self.h * s };
}

/// ![image](Rect-offset.png)
pub fn offset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w, .h = self.h };
}

/// Same as `offsetNegPoint` but takes a rect, ignoring the width and height
pub fn offsetNeg(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w, .h = self.h };
}

/// ![image](Rect-offsetNegPoint.png)
pub fn offsetNegPoint(self: *const Rect, p: Point) Rect {
    return Rect{ .x = self.x - p.x, .y = self.y - p.y, .w = self.w, .h = self.h };
}

/// ![image](Rect-intersect.png)
pub fn intersect(a: Rect, b: Rect) Rect {
    const ax2 = a.x + a.w;
    const ay2 = a.y + a.h;
    const bx2 = b.x + b.w;
    const by2 = b.y + b.h;
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    const x2 = @min(ax2, bx2);
    const y2 = @min(ay2, by2);
    return Rect{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
}

/// ![image](Rect-unionWith.png)
pub fn unionWith(a: Rect, b: Rect) Rect {
    const ax2 = a.x + a.w;
    const ay2 = a.y + a.h;
    const bx2 = b.x + b.w;
    const by2 = b.y + b.h;
    const x = @min(a.x, b.x);
    const y = @min(a.y, b.y);
    const x2 = @max(ax2, bx2);
    const y2 = @max(ay2, by2);
    return Rect{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
}

pub fn shrinkToSize(self: *const Rect, s: Size) Rect {
    return Rect{ .x = self.x, .y = self.y, .w = @min(self.w, s.w), .h = @min(self.h, s.h) };
}

/// ![image](Rect-inset.png)
pub fn inset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x + r.x, .y = self.y + r.y, .w = @max(0, self.w - r.x - r.w), .h = @max(0, self.h - r.y - r.h) };
}

/// See `inset`
pub fn insetAll(self: *const Rect, p: f32) Rect {
    return self.inset(Rect.all(p));
}

/// ![image](Rect-outset.png)
pub fn outset(self: *const Rect, r: Rect) Rect {
    return Rect{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w + r.x + r.w, .h = self.h + r.y + r.h };
}

/// See `outset`
pub fn outsetAll(self: *const Rect, p: f32) Rect {
    return self.outset(Rect.all(p));
}

pub fn format(self: *const Rect, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    try std.fmt.format(writer, "Rect{{ {d} {d} {d} {d} }}", .{ self.x, self.y, self.w, self.h });
}

/// Natural pixels is the unit for subwindow sizing and placement.
///
/// Usually received through `Rect.Physical.toNatural` or `dvui.windowRectScale`.
pub const Natural = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub inline fn toRect(self: Rect.Natural) Rect {
        return .{ .x = self.x, .y = self.y, .w = self.w, .h = self.h };
    }

    pub inline fn fromRect(r: Rect) Rect.Natural {
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }

    /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
    pub inline fn toPhysical(self: Rect.Natural) Rect.Natural {
        return .fromRect(self.toRect().scale(dvui.windowNaturalScale()));
    }

    pub fn format(self: *const Rect.Natural, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Rect.Natural{{ {d} {d} {d} {d} }}", .{ self.x, self.y, self.w, self.h });
    }
};

/// Pixels is the unit for rendering and user input.
///
/// Usually received via `dvui.RectScale` through `dvui.WidgetData.rectScale` or similar.
///
/// Physical pixels might be more on a hidpi screen or if the user has content scaling.
pub const Physical = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub inline fn toRect(self: Rect.Physical) Rect {
        return Rect{ .x = self.x, .y = self.y, .w = self.w, .h = self.h };
    }

    pub inline fn fromRect(r: Rect) Rect.Physical {
        return Rect.Physical{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }

    /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
    pub inline fn toNatural(self: Rect.Physical) Rect.Natural {
        return .fromRect(self.toRect().scale(1 / dvui.windowNaturalScale()));
    }

    /// Stroke (outline) a rounded rect.
    ///
    /// radius values:
    /// - x is top-left corner
    /// - y is top-right corner
    /// - w is bottom-right corner
    /// - h is bottom-left corner
    ///
    /// Only valid between dvui.Window.begin() and end().
    pub fn stroke(self: Rect.Physical, radius: Rect, thickness: f32, color: dvui.Color, opts: dvui.PathStrokeOptions) !void {
        var path: dvui.PathArrayList = .init(dvui.currentWindow().arena());
        defer path.deinit();

        try dvui.pathAddRect(&path, self, radius);
        var options = opts;
        options.closed = true;
        try dvui.pathStroke(path.items, thickness, color, options);
    }

    /// Fill a rounded rect.
    ///
    /// radius values:
    /// - x is top-left corner
    /// - y is top-right corner
    /// - w is bottom-right corner
    /// - h is bottom-left corner
    ///
    /// Only valid between dvui.Window.begin() and end().
    pub fn fill(self: Rect.Physical, radius: Rect, color: dvui.Color) !void {
        var path: dvui.PathArrayList = .init(dvui.currentWindow().arena());
        defer path.deinit();

        try dvui.pathAddRect(&path, self, radius);
        try dvui.pathFillConvex(path.items, color);
    }

    pub inline fn topLeft(self: *const Rect.Physical) Point.Physical {
        return .fromPoint(self.toRect().topLeft());
    }

    pub inline fn topRight(self: *const Rect.Physical) Point.Physical {
        return .fromPoint(self.toRect().topRight());
    }

    pub inline fn bottomLeft(self: *const Rect.Physical) Point.Physical {
        return .fromPoint(self.toRect().bottomLeft());
    }

    pub inline fn bottomRight(self: *const Rect.Physical) Point.Physical {
        return .fromPoint(self.toRect().bottomRight());
    }

    pub inline fn center(self: *const Rect.Physical) Point.Physical {
        return .fromPoint(self.toRect().center());
    }

    pub inline fn contains(self: *const Rect.Physical, p: Point.Physical) bool {
        return self.toRect().contains(p.toPoint());
    }

    pub inline fn empty(self: *const Rect.Physical) bool {
        return self.toRect().empty();
    }

    /// ![image](Rect-intersect.png)
    pub inline fn intersect(a: Rect.Physical, b: Rect.Physical) Rect.Physical {
        return .fromRect(a.toRect().intersect(b.toRect()));
    }

    /// ![image](Rect-inset.png)
    pub inline fn inset(self: *const Rect.Physical, r: Rect.Physical) Rect.Physical {
        return .fromRect(self.toRect().inset(r.toRect()));
    }
    /// See `inset`
    pub inline fn insetAll(self: *const Rect.Physical, p: f32) Rect.Physical {
        return .fromRect(self.toRect().insetAll(p));
    }
    /// ![image](Rect-outset.png)
    pub inline fn outset(self: *const Rect.Physical, r: Rect.Physical) Rect.Physical {
        return .fromRect(self.toRect().outset(r.toRect()));
    }
    /// See `outset`
    pub inline fn outsetAll(self: *const Rect.Physical, p: f32) Rect.Physical {
        return .fromRect(self.toRect().outsetAll(p));
    }

    /// ![image](Rect-offsetNegPoint.png)
    pub inline fn offsetNegPoint(self: *const Rect.Physical, p: Point.Physical) Rect.Physical {
        return .fromRect(self.toRect().offsetNegPoint(p.toPoint()));
    }

    /// True if self would be modified when clipped by r.
    pub fn clippedBy(self: *const Rect.Physical, r: Rect.Physical) bool {
        return self.x < r.x or self.y < r.y or
            (self.x + self.w > r.x + r.w) or
            (self.y + self.h > r.y + r.h);
    }

    pub fn format(self: *const Rect.Physical, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Rect.Physical{{ {d} {d} {d} {d} }}", .{ self.x, self.y, self.w, self.h });
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}

test scale {
    const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
    const res = rect.scale(0.5);
    try std.testing.expectEqualDeep(Rect{ .x = 25, .y = 25, .w = 75, .h = 75 }, res);
}

test "Rect-scale.png" {
    var t = try dvui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
            const res = rect.scale(0.5);
            try std.testing.expectEqualDeep(Rect{ .x = 25, .y = 25, .w = 75, .h = 75 }, res);

            var box = try dvui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test offset {
    const rect = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const res = rect.offset(.{ .x = 50, .y = 50 }); // width and height does nothing
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 100, .h = 100 }, res);
}

test "Rect-offset.png" {
    var t = try dvui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const res = rect.offset(.{ .x = 50, .y = 50 }); // width and height does nothing
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 100, .h = 100 }, res);

            var box = try dvui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test offsetNeg {
    const rect = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
    const res = rect.offsetNeg(.{ .x = 50, .y = 50 }); // width and height does nothing
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);
}

test offsetNegPoint {
    const rect = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
    const res = rect.offsetNegPoint(.{ .x = 50, .y = 50 });
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);
}

test "Rect-offsetNegPoint.png" {
    var t = try dvui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
            const res = rect.offsetNegPoint(.{ .x = 50, .y = 50 });
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);

            var box = try dvui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test intersect {
    const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

    const ab = Rect.intersect(a, b);
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, ab);
}

test "Rect-intersect.png" {
    var t = try dvui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

            const ab = Rect.intersect(a, b);
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, ab);

            var box = try dvui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try a.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try b.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try ab.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test unionWith {
    const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

    const ab = Rect.unionWith(a, b);
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, ab);
}

test "Rect-unionWith.png" {
    var t = try dvui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

            const ab = Rect.unionWith(a, b);
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, ab);

            var box = try dvui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try a.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try b.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try ab.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test inset {
    const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
    const res = rect.inset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 75, .h = 75 }, res);
}
test "Rect-inset.png" {
    var t = try dvui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
            const res = rect.inset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 75, .h = 75 }, res);

            var box = try dvui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test insetAll {
    const rect = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
    const res = rect.insetAll(50);
    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, res);
}

test outset {
    const rect = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
    const res = rect.outset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 125, .h = 125 }, res);
}
test "Rect-outset.png" {
    var t = try dvui.testing.init(.{ .window_size = .all(250) });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            // NOTE: Should be kept up to date with the doctest
            const rect = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
            const res = rect.outset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 125, .h = 125 }, res);

            var box = try dvui.box(@src(), .horizontal, .{ .background = true, .color_fill = .{ .name = .fill_window }, .expand = .both });
            defer box.deinit();
            try rect.stroke(.{}, 1, dvui.Color.black.transparent(0.5), .{ .closed = true });
            try res.stroke(.{}, 1, .{ .r = 0xff, .g = 0, .b = 0 }, .{ .closed = true });
            return .ok;
        }
    }.frame;

    try t.saveDocImage(@src(), .{}, frame);
}

test outsetAll {
    const rect = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
    const res = rect.outsetAll(50);
    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, res);
}
