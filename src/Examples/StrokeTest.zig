pub const Self = @This();
pub var show: bool = false;
pub var show_rect = dvui.Rect{};
pub var pointsArray: [10]dvui.Point = [1]dvui.Point{.{}} ** 10;
pub var points: []dvui.Point = pointsArray[0..0];
pub var dragi: ?usize = null;
pub var thickness: f32 = 1.0;
pub var endcap_style: dvui.Path.StrokeOptions.EndCapStyle = .none;
pub var stroke_test_closed: bool = false;

wd: dvui.WidgetData = undefined,

pub fn install(self: *Self, src: std.builtin.SourceLocation, options: dvui.Options) void {
    _ = dvui.sliderEntry(@src(), "thick: {d:0.2}", .{ .value = &thickness }, .{ .expand = .horizontal });

    const defaults = dvui.Options{ .name = "StrokeTest" };
    self.wd = dvui.WidgetData.init(src, .{}, defaults.override(options));
    self.wd.register();

    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatchSimple(e, self.data()))
            continue;

        self.processEvent(e);
    }

    self.data().borderAndBackground(.{});

    _ = dvui.parentSet(self.widget());

    const rs = self.data().contentRectScale();
    const fill_color = dvui.Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
    for (points, 0..) |p, i| {
        const rect = dvui.Rect.fromPoint(p.plus(.{ .x = -10, .y = -10 })).toSize(.{ .w = 20, .h = 20 });
        rs.rectToPhysical(rect).fill(.all(1), .{ .color = fill_color });

        _ = i;
        //_ = dvui.button(@src(), i, "Floating", .{}, .{ .rect = dvui.Rect.fromPoint(p) });
    }

    if (dvui.currentWindow().lifo().alloc(dvui.Point.Physical, points.len) catch null) |path| {
        defer dvui.currentWindow().lifo().free(path);

        for (points, path) |p, *path_point| {
            path_point.* = rs.pointToPhysical(p);
        }

        const stroke_color = dvui.Color{ .r = 0, .g = 0, .b = 255, .a = 150 };
        dvui.Path.stroke(.{ .points = path }, .{ .thickness = rs.s * thickness, .color = stroke_color, .closed = stroke_test_closed, .endcap_style = Self.endcap_style });
    }
}

pub fn widget(self: *Self) dvui.Widget {
    return dvui.Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *Self) *dvui.WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *Self, id: dvui.WidgetId, min_size: dvui.Size, e: dvui.Options.Expand, g: dvui.Options.Gravity) dvui.Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *Self, rect: dvui.Rect) dvui.RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *Self, s: dvui.Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn processEvent(self: *Self, e: *dvui.Event) void {
    switch (e.evt) {
        .mouse => |me| {
            const rs = self.data().contentRectScale();
            const mp = rs.pointFromPhysical(me.p);
            switch (me.action) {
                .press => {
                    if (me.button == .left) {
                        e.handle(@src(), self.data());
                        dragi = null;

                        for (points, 0..) |p, i| {
                            const dp = dvui.Point.diff(p, mp);
                            if (@abs(dp.x) < 5 and @abs(dp.y) < 5) {
                                dragi = i;
                                break;
                            }
                        }

                        if (dragi == null and points.len < pointsArray.len) {
                            dragi = points.len;
                            points.len += 1;
                            points[dragi.?] = mp;
                        }

                        if (dragi != null) {
                            dvui.captureMouse(self.data(), e.num);
                            dvui.dragPreStart(me.p, .{ .cursor = .crosshair });
                        }
                    }
                },
                .release => {
                    if (me.button == .left) {
                        e.handle(@src(), self.data());
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                    }
                },
                .motion => {
                    e.handle(@src(), self.data());
                    if (dvui.dragging(me.p, null)) |dps| {
                        const dp = dps.scale(1 / rs.s, Point);
                        points[dragi.?].x += dp.x;
                        points[dragi.?].y += dp.y;
                        dvui.refresh(null, @src(), self.data().id);
                    }
                },
                .wheel_y => |ticks| {
                    e.handle(@src(), self.data());
                    const base: f32 = 1.02;
                    const zs = @exp(@log(base) * ticks);
                    if (zs != 1.0) {
                        thickness *= zs;
                        dvui.refresh(null, @src(), self.data().id);
                    }
                },
                else => {},
            }
        },
        else => {},
    }
}

pub fn deinit(self: *Self) void {
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();

    dvui.parentReset(self.data().id, self.data().parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Point = dvui.Point;
