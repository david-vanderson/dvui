const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const ScaleWidget = @This();

/// How ScaleWidget handles pinch zoom touch guesture.
pub const PinchZoom = enum {
    /// Ignore it.
    none,
    /// Handle if the guesture happens inside ScaleWidget.
    local,
    /// Same as local but ignores subwindow.  Useful for globally changing
    /// content scale.  See examples/app.zig.
    global,
};

pub const InitOptions = struct {
    scale: ?*f32 = null,

    /// Adjust scale based on touch pinch zoom guesture
    pinch_zoom: PinchZoom = .none,
};

wd: WidgetData,
init_options: InitOptions,
/// SAFETY: Set in `install`
scale: *f32 = undefined,
touchPoints: *[2]?dvui.Point.Physical,
old_dist: ?f32 = null,
/// SAFETY: Will be set when `old_dist` is not null
old_scale: f32 = undefined,
layout: dvui.BasicLayout = .{},

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *ScaleWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    const defaults = Options{ .name = "Scale" };
    const wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.* = .{
        .wd = wd,
        .init_options = init_opts,
        .touchPoints = dvui.dataGetPtrDefault(null, wd.id, "_touchPoints", [2]?dvui.Point.Physical, .{ null, null }),
    };

    if (self.init_options.scale) |init_s| {
        self.scale = init_s;
    } else {
        self.scale = dvui.dataGetPtrDefault(null, self.data().id, "_scale", f32, 1.0);
    }

    dvui.parentSet(self.widget());
    self.data().register();
    self.data().borderAndBackground(.{});
}

pub fn matchEvent(self: *ScaleWidget, e: *Event) bool {
    // normal match logic except we ignore mouse capture
    return (self.init_options.pinch_zoom != .none) and
        !e.handled and
        e.evt == .mouse and
        (self.init_options.pinch_zoom == .global or e.evt.mouse.floating_win == dvui.subwindowCurrentId()) and
        self.data().borderRectScale().r.contains(e.evt.mouse.p) and
        dvui.clipGet().contains(e.evt.mouse.p) and
        (e.evt.mouse.button == .touch0 or e.evt.mouse.button == .touch1);
}

pub fn processEvents(self: *ScaleWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e);
    }
}

pub fn processEvent(self: *ScaleWidget, e: *Event) void {
    if (e.evt == .mouse and (e.evt.mouse.button == .touch0 or e.evt.mouse.button == .touch1)) {
        const idx: usize = if (e.evt.mouse.button == .touch0) 0 else 1;
        switch (e.evt.mouse.action) {
            .press => {
                self.touchPoints[idx] = e.evt.mouse.p;
                if (self.touchPoints[1 - idx] != null) {
                    // both fingers down, grab capture
                    e.handle(@src(), self.data());

                    // end any drag that might have been happening
                    dvui.dragEnd();
                    dvui.captureMouse(self.data(), e.num);
                }
            },
            .release => {
                self.touchPoints[idx] = null;
                if (dvui.captured(self.data().id)) {
                    e.handle(@src(), self.data());
                    dvui.captureMouse(null, e.num);
                }
            },
            .motion => {
                if (self.touchPoints[0] != null and self.touchPoints[1] != null) {
                    e.handle(@src(), self.data());

                    if (self.old_dist == null) {
                        const dx = self.touchPoints[0].?.x - self.touchPoints[1].?.x;
                        const dy = self.touchPoints[0].?.y - self.touchPoints[1].?.y;
                        self.old_dist = @sqrt(dx * dx + dy * dy);
                        self.old_scale = self.scale.*;
                    }

                    self.touchPoints[idx] = e.evt.mouse.p;

                    const dx = self.touchPoints[0].?.x - self.touchPoints[1].?.x;
                    const dy = self.touchPoints[0].?.y - self.touchPoints[1].?.y;
                    const new_dist: f32 = @sqrt(dx * dx + dy * dy);

                    self.scale.* = std.math.clamp(self.old_scale * new_dist / self.old_dist.?, 0.1, 10);
                }
            },
            else => {},
        }
    }
}

pub fn widget(self: *ScaleWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *ScaleWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *ScaleWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    const s = if (self.scale.* > 0)
        1.0 / self.scale.*
    else
        // prevent divide by zero
        1_000_000.0;

    return self.layout.rectFor(self.data().contentRect().justSize().scale(s, Rect), id, min_size, e, g);
}

pub fn screenRectScale(self: *ScaleWidget, rect: Rect) RectScale {
    var rs = self.data().contentRectScale();
    rs.s *= self.scale.*;
    return rs.rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ScaleWidget, s: Size) void {
    const ms = self.layout.minSizeForChild(s.scale(self.scale.*, Size));
    self.data().minSizeMax(self.data().options.padSize(ms));
}

pub fn deinit(self: *ScaleWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    dvui.dataSet(null, self.data().id, "_scale", self.scale.*);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
