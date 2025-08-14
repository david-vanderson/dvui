const std = @import("std");
const dvui = @import("dvui.zig");

pub const Rect = RectType(.none);

pub fn RectType(comptime units: dvui.enums.Units) type {
    return struct {
        const Self = @This();

        x: f32 = 0,
        y: f32 = 0,
        w: f32 = 0,
        h: f32 = 0,

        /// Natural pixels is the unit for subwindows. It differs from
        /// physical pixels on hidpi screens or with content scaling.
        pub const Natural = if (units == .none) RectType(.natural) else @compileError("tried to nest Rect.Natural");

        /// Physical pixels is the units for rendering and dvui events.
        /// Regardless of dpi or content scaling, physical pixels always
        /// matches the output screen.
        ///
        /// To convert between Rect and Rect.Physical, use `RectScale.rectToPhysical` and `RectScale.rectFromPhysical`
        pub const Physical = if (units == .none) RectType(.physical) else @compileError("tried to nest Rect.Physical");

        pub const PointType = switch (units) {
            .none => dvui.Point,
            .natural => dvui.Point.Natural,
            .physical => dvui.Point.Physical,
        };

        pub const SizeType = switch (units) {
            .none => dvui.Size,
            .natural => dvui.Size.Natural,
            .physical => dvui.Size.Physical,
        };

        pub fn cast(r: anytype) Self {
            return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        }

        pub fn equals(self: *const Self, r: Self) bool {
            return (self.x == r.x and self.y == r.y and self.w == r.w and self.h == r.h);
        }

        pub fn plus(self: *const Self, r: Self) Self {
            return .{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w + r.w, .h = self.h + r.h };
        }

        pub fn nonZero(self: *const Self) bool {
            return (self.x != 0 or self.y != 0 or self.w != 0 or self.h != 0);
        }

        pub fn all(v: f32) Self {
            return .{ .x = v, .y = v, .w = v, .h = v };
        }

        pub fn rect(x: f32, y: f32, w: f32, h: f32) Self {
            return .{ .x = x, .y = y, .w = w, .h = h };
        }

        pub fn fromPoint(p: PointType) Self {
            return .{ .x = p.x, .y = p.y };
        }

        pub fn toPoint(self: *const Self, p: PointType) Self {
            return .{ .x = self.x, .y = self.y, .w = p.x - self.x, .h = p.y - self.y };
        }

        pub fn fromSize(s: SizeType) Self {
            return .{ .w = s.w, .h = s.h };
        }

        pub fn toSize(self: *const Self, s: SizeType) Self {
            return .{ .x = self.x, .y = self.y, .w = s.w, .h = s.h };
        }

        pub fn justSize(self: *const Self) Self {
            return .{ .x = 0, .y = 0, .w = self.w, .h = self.h };
        }

        pub fn size(self: *const Self) SizeType {
            return .{ .w = self.w, .h = self.h };
        }

        pub fn topLeft(self: *const Self) PointType {
            return .{ .x = self.x, .y = self.y };
        }

        pub fn topRight(self: *const Self) PointType {
            return .{ .x = self.x + self.w, .y = self.y };
        }

        pub fn bottomLeft(self: *const Self) PointType {
            return .{ .x = self.x, .y = self.y + self.h };
        }

        pub fn bottomRight(self: *const Self) PointType {
            return .{ .x = self.x + self.w, .y = self.y + self.h };
        }

        pub fn center(self: *const Self) PointType {
            return .{ .x = self.x + self.w / 2, .y = self.y + self.h / 2 };
        }

        pub fn contains(self: *const Self, p: PointType) bool {
            return (p.x >= self.x and p.x <= (self.x + self.w) and p.y >= self.y and p.y <= (self.y + self.h));
        }

        pub fn empty(self: *const Self) bool {
            return (self.w == 0 or self.h == 0);
        }

        /// Pass the scale and the type of Rect it now represents.
        /// ![image](Rect-scale.png)
        pub fn scale(self: *const Self, s: f32, rectType: type) rectType {
            return .{ .x = self.x * s, .y = self.y * s, .w = self.w * s, .h = self.h * s };
        }

        /// ![image](Rect-offset.png)
        pub fn offset(self: *const Self, r: Self) Self {
            return .{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w, .h = self.h };
        }

        pub fn offsetPoint(self: *const Self, p: PointType) Self {
            return .{ .x = self.x + p.x, .y = self.y + p.y, .w = self.w, .h = self.h };
        }

        /// Same as `offsetNegPoint` but takes a rect, ignoring the width and height
        pub fn offsetNeg(self: *const Self, r: Self) Self {
            return .{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w, .h = self.h };
        }

        /// ![image](Rect-offsetNegPoint.png)
        pub fn offsetNegPoint(self: *const Self, p: PointType) Self {
            return .{ .x = self.x - p.x, .y = self.y - p.y, .w = self.w, .h = self.h };
        }

        /// ![image](Rect-intersect.png)
        pub fn intersect(a: Self, b: Self) Self {
            const ax2 = a.x + a.w;
            const ay2 = a.y + a.h;
            const bx2 = b.x + b.w;
            const by2 = b.y + b.h;
            const x = @max(a.x, b.x);
            const y = @max(a.y, b.y);
            const x2 = @min(ax2, bx2);
            const y2 = @min(ay2, by2);
            return .{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
        }

        /// ![image](Rect-unionWith.png)
        pub fn unionWith(a: Self, b: Self) Self {
            const ax2 = a.x + a.w;
            const ay2 = a.y + a.h;
            const bx2 = b.x + b.w;
            const by2 = b.y + b.h;
            const x = @min(a.x, b.x);
            const y = @min(a.y, b.y);
            const x2 = @max(ax2, bx2);
            const y2 = @max(ay2, by2);
            return .{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
        }

        pub fn shrinkToSize(self: *const Self, s: SizeType) Self {
            return .{ .x = self.x, .y = self.y, .w = @min(self.w, s.w), .h = @min(self.h, s.h) };
        }

        /// ![image](Rect-inset.png)
        pub fn inset(self: *const Self, r: Self) Self {
            return .{ .x = self.x + r.x, .y = self.y + r.y, .w = @max(0, self.w - r.x - r.w), .h = @max(0, self.h - r.y - r.h) };
        }

        /// See `inset`
        pub fn insetAll(self: *const Self, p: f32) Self {
            return self.inset(Self.all(p));
        }

        /// ![image](Rect-outset.png)
        pub fn outset(self: *const Self, r: Self) Self {
            return .{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w + r.x + r.w, .h = self.h + r.y + r.h };
        }

        /// See `outset`
        pub fn outsetAll(self: *const Self, p: f32) Self {
            return self.outset(Self.all(p));
        }

        pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            const type_name = switch (units) {
                .none => "Rect",
                .natural => "Rect.Natural",
                .physical => "Rect.Physical",
            };
            try std.fmt.format(writer, "{s}{{ {d} {d} {d} {d} }}", .{ type_name, self.x, self.y, self.w, self.h });
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
        pub fn stroke(self: Rect.Physical, radius: Rect.Physical, opts: dvui.Path.StrokeOptions) void {
            var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
            defer path.deinit();

            path.addRect(self, radius);
            var options = opts;
            options.closed = true;
            path.build().stroke(options);
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
        pub fn fill(self: Rect.Physical, radius: Rect.Physical, opts: dvui.Path.FillConvexOptions) void {
            var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
            defer path.deinit();

            path.addRect(self, radius);
            path.build().fillConvex(opts);
        }

        /// True if self would be modified when clipped by r.
        pub fn clippedBy(self: *const Rect.Physical, r: Rect.Physical) bool {
            return self.x < r.x or self.y < r.y or
                (self.x + self.w > r.x + r.w) or
                (self.y + self.h > r.y + r.h);
        }

        /// Only valid between `dvui.Window.begin`and `dvui.Window.end`.
        pub fn toNatural(self: Rect.Physical) Rect.Natural {
            return self.scale(1 / dvui.windowNaturalScale(), Rect.Natural);
        }

        test scale {
            const r = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
            const res = r.scale(0.5, Rect);
            try std.testing.expectEqualDeep(Rect{ .x = 25, .y = 25, .w = 75, .h = 75 }, res);
        }

        test "DOCIMG scale" {
            if (units != .none) return;
            var t = try dvui.testing.init(.{ .window_size = .all(250) });
            defer t.deinit();

            const frame = struct {
                fn frame() !dvui.App.Result {
                    // NOTE: Should be kept up to date with the doctest
                    const r = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
                    const res = r.scale(0.5, Rect);
                    try std.testing.expectEqualDeep(Rect{ .x = 25, .y = 25, .w = 75, .h = 75 }, res);

                    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .style = .window, .expand = .both });
                    defer box.deinit();
                    Rect.Physical.cast(r).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(res).stroke(.{}, .{ .thickness = 1, .color = .red, .closed = true });
                    return .ok;
                }
            }.frame;

            try t.saveImage(frame, null, "Rect-scale.png");
        }

        test offset {
            const r = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const res = r.offset(.{ .x = 50, .y = 50 }); // width and height does nothing
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 100, .h = 100 }, res);
        }

        test "DOCIMG offset" {
            if (units != .none) return;
            var t = try dvui.testing.init(.{ .window_size = .all(250) });
            defer t.deinit();

            const frame = struct {
                fn frame() !dvui.App.Result {
                    // NOTE: Should be kept up to date with the doctest
                    const r = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
                    const res = r.offset(.{ .x = 50, .y = 50 }); // width and height does nothing
                    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 100, .h = 100 }, res);

                    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .style = .window, .expand = .both });
                    defer box.deinit();
                    Rect.Physical.cast(r).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(res).stroke(.{}, .{ .thickness = 1, .color = .red, .closed = true });
                    return .ok;
                }
            }.frame;

            try t.saveImage(frame, null, "Rect-offset.png");
        }

        test offsetNeg {
            const r = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
            const res = r.offsetNeg(.{ .x = 50, .y = 50 }); // width and height does nothing
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);
        }

        test offsetNegPoint {
            const r = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
            const res = r.offsetNegPoint(.{ .x = 50, .y = 50 });
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);
        }

        test "DOCIMG offsetNegPoint" {
            if (units != .none) return;
            var t = try dvui.testing.init(.{ .window_size = .all(250) });
            defer t.deinit();

            const frame = struct {
                fn frame() !dvui.App.Result {
                    // NOTE: Should be kept up to date with the doctest
                    const r = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };
                    const res = r.offsetNegPoint(.{ .x = 50, .y = 50 });
                    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 100, .h = 100 }, res);

                    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .style = .window, .expand = .both });
                    defer box.deinit();
                    Rect.Physical.cast(r).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(res).stroke(.{}, .{ .thickness = 1, .color = .red, .closed = true });
                    return .ok;
                }
            }.frame;

            try t.saveImage(frame, null, "Rect-offsetNegPoint.png");
        }

        test intersect {
            const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

            const ab = Rect.intersect(a, b);
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, ab);
        }

        test "DOCIMG intersect" {
            if (units != .none) return;
            var t = try dvui.testing.init(.{ .window_size = .all(250) });
            defer t.deinit();

            const frame = struct {
                fn frame() !dvui.App.Result {
                    // NOTE: Should be kept up to date with the doctest
                    const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
                    const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

                    const ab = Rect.intersect(a, b);
                    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, ab);

                    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .style = .window, .expand = .both });
                    defer box.deinit();
                    Rect.Physical.cast(a).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(b).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(ab).stroke(.{}, .{ .thickness = 1, .color = .red, .closed = true });
                    return .ok;
                }
            }.frame;

            try t.saveImage(frame, null, "Rect-intersect.png");
        }

        test unionWith {
            const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
            const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

            const ab = Rect.unionWith(a, b);
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, ab);
        }

        test "DOCIMG unionWith" {
            if (units != .none) return;
            var t = try dvui.testing.init(.{ .window_size = .all(250) });
            defer t.deinit();

            const frame = struct {
                fn frame() !dvui.App.Result {
                    // NOTE: Should be kept up to date with the doctest
                    const a = Rect{ .x = 50, .y = 50, .w = 100, .h = 100 };
                    const b = Rect{ .x = 100, .y = 100, .w = 100, .h = 100 };

                    const ab = Rect.unionWith(a, b);
                    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, ab);

                    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .style = .window, .expand = .both });
                    defer box.deinit();
                    Rect.Physical.cast(a).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(b).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(ab).stroke(.{}, .{ .thickness = 1, .color = .red, .closed = true });
                    return .ok;
                }
            }.frame;

            try t.saveImage(frame, null, "Rect-unionWith.png");
        }

        test inset {
            const r = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
            const res = r.inset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 75, .h = 75 }, res);
        }
        test "DOCIMG inset" {
            if (units != .none) return;
            var t = try dvui.testing.init(.{ .window_size = .all(250) });
            defer t.deinit();

            const frame = struct {
                fn frame() !dvui.App.Result {
                    // NOTE: Should be kept up to date with the doctest
                    const r = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
                    const res = r.inset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
                    try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 75, .h = 75 }, res);

                    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .style = .window, .expand = .both });
                    defer box.deinit();
                    Rect.Physical.cast(r).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(res).stroke(.{}, .{ .thickness = 1, .color = .red, .closed = true });
                    return .ok;
                }
            }.frame;

            try t.saveImage(frame, null, "Rect-inset.png");
        }

        test insetAll {
            const r = Rect{ .x = 50, .y = 50, .w = 150, .h = 150 };
            const res = r.insetAll(50);
            try std.testing.expectEqualDeep(Rect{ .x = 100, .y = 100, .w = 50, .h = 50 }, res);
        }

        test outset {
            const r = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
            const res = r.outset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 125, .h = 125 }, res);
        }
        test "DOCIMG outset" {
            if (units != .none) return;
            var t = try dvui.testing.init(.{ .window_size = .all(250) });
            defer t.deinit();

            const frame = struct {
                fn frame() !dvui.App.Result {
                    // NOTE: Should be kept up to date with the doctest
                    const r = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
                    const res = r.outset(.{ .x = 50, .y = 50, .w = 25, .h = 25 });
                    try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 125, .h = 125 }, res);

                    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .background = true, .style = .window, .expand = .both });
                    defer box.deinit();
                    Rect.Physical.cast(r).stroke(.{}, .{ .thickness = 1, .color = .gray, .closed = true });
                    Rect.Physical.cast(res).stroke(.{}, .{ .thickness = 1, .color = .red, .closed = true });
                    return .ok;
                }
            }.frame;

            try t.saveImage(frame, null, "Rect-outset.png");
        }

        test outsetAll {
            const r = Rect{ .x = 100, .y = 100, .w = 50, .h = 50 };
            const res = r.outsetAll(50);
            try std.testing.expectEqualDeep(Rect{ .x = 50, .y = 50, .w = 150, .h = 150 }, res);
        }
    };
}

test {
    @import("std").testing.refAllDecls(@This());
}
