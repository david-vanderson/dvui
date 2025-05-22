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

wd: WidgetData = undefined,
init_options: InitOptions = undefined,
scale: *f32 = undefined,
touchPoints: *[2]?dvui.Point.Physical = undefined,
old_dist: ?f32 = null,
old_scale: f32 = undefined,
layout: dvui.BasicLayout = .{},

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) ScaleWidget {
    var self = ScaleWidget{};
    const defaults = Options{ .name = "Scale" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.init_options = init_opts;
    self.touchPoints = dvui.dataGetPtrDefault(null, self.wd.id, "_touchPoints", [2]?dvui.Point.Physical, .{ null, null });
    return self;
}

pub fn install(self: *ScaleWidget) !void {
    if (self.init_options.scale) |init_s| {
        self.scale = init_s;
    } else {
        self.scale = dvui.dataGetPtrDefault(null, self.wd.id, "_scale", f32, 1.0);
    }

    dvui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn matchEvent(self: *ScaleWidget, e: *Event) bool {
    // normal match logic except we ignore mouse capture
    return (self.init_options.pinch_zoom != .none) and
        !e.handled and
        e.evt == .mouse and
        (self.init_options.pinch_zoom == .global or e.evt.mouse.floating_win == dvui.subwindowCurrentId()) and
        self.wd.borderRectScale().r.contains(e.evt.mouse.p) and
        dvui.clipGet().contains(e.evt.mouse.p) and
        (e.evt.mouse.button == .touch0 or e.evt.mouse.button == .touch1);
}

pub fn processEvents(self: *ScaleWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn processEvent(self: *ScaleWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;

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
                    dvui.captureMouse(self.data());
                }
            },
            .release => {
                self.touchPoints[idx] = null;
                if (dvui.captured(self.wd.id)) {
                    e.handle(@src(), self.data());
                    dvui.captureMouse(null);
                }
            },
            .motion => {
                if (self.touchPoints[0] != null and self.touchPoints[1] != null) {
                    e.handle(@src(), self.data());
                    var dx: f32 = undefined;
                    var dy: f32 = undefined;

                    if (self.old_dist == null) {
                        dx = self.touchPoints[0].?.x - self.touchPoints[1].?.x;
                        dy = self.touchPoints[0].?.y - self.touchPoints[1].?.y;
                        self.old_dist = @sqrt(dx * dx + dy * dy);
                        self.old_scale = self.scale.*;
                    }

                    self.touchPoints[idx] = e.evt.mouse.p;

                    dx = self.touchPoints[0].?.x - self.touchPoints[1].?.x;
                    dy = self.touchPoints[0].?.y - self.touchPoints[1].?.y;
                    const new_dist: f32 = @sqrt(dx * dx + dy * dy);

                    self.scale.* = std.math.clamp(self.old_scale * new_dist / self.old_dist.?, 0.1, 10);
                }
            },
            else => {},
        }
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn widget(self: *ScaleWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ScaleWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ScaleWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    var s: f32 = undefined;
    if (self.scale.* > 0) {
        s = 1.0 / self.scale.*;
    } else {
        // prevent divide by zero
        s = 1_000_000.0;
    }

    return self.layout.rectFor(self.wd.contentRect().justSize().scale(s, Rect), id, min_size, e, g);
}

pub fn screenRectScale(self: *ScaleWidget, rect: Rect) RectScale {
    var rs = self.wd.contentRectScale();
    rs.s *= self.scale.*;
    return rs.rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ScaleWidget, s: Size) void {
    const ms = self.layout.minSizeForChild(s.scale(self.scale.*, Size));
    self.wd.minSizeMax(self.wd.options.padSize(ms));
}

pub fn deinit(self: *ScaleWidget) void {
    dvui.dataSet(null, self.wd.id, "_scale", self.scale.*);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
