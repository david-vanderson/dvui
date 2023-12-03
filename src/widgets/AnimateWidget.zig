const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const AnimateWidget = @This();

pub const Kind = enum {
    alpha,
    vert,
    horz,
};

wd: WidgetData = undefined,
kind: Kind = undefined,
duration: i32 = undefined,
val: ?f32 = null,

prev_alpha: f32 = 1.0,

pub fn init(src: std.builtin.SourceLocation, kind: Kind, duration_micros: i32, opts: Options) AnimateWidget {
    const defaults = Options{ .name = "Animate" };
    return AnimateWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)), .kind = kind, .duration = duration_micros };
}

pub fn install(self: *AnimateWidget) !void {
    dvui.parentSet(self.widget());
    try self.wd.register();

    if (dvui.firstFrame(self.wd.id)) {
        // start begin animation
        dvui.animation(self.wd.id, "_start", .{ .start_val = 0.0, .end_val = 1.0, .end_time = self.duration });
    }

    if (dvui.animationGet(self.wd.id, "_end")) |a| {
        self.val = a.lerp();
    } else if (dvui.animationGet(self.wd.id, "_start")) |a| {
        self.val = a.lerp();
    }

    if (self.val) |v| {
        switch (self.kind) {
            .alpha => {
                self.prev_alpha = dvui.themeGet().alpha;
                dvui.themeGet().alpha *= v;
            },
            .vert => {},
            .horz => {},
        }
    }

    try self.wd.borderAndBackground(.{});
}

pub fn startEnd(self: *AnimateWidget) void {
    dvui.animation(self.wd.id, "_end", .{ .start_val = 1.0, .end_val = 0.0, .end_time = self.duration });
}

pub fn end(self: *AnimateWidget) bool {
    return dvui.animationDone(self.wd.id, "_end");
}

pub fn widget(self: *AnimateWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *AnimateWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *AnimateWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
}

pub fn screenRectScale(self: *AnimateWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *AnimateWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
}

pub fn processEvent(self: *AnimateWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *AnimateWidget) void {
    if (self.val) |v| {
        switch (self.kind) {
            .alpha => {
                dvui.themeGet().alpha = self.prev_alpha;
            },
            .vert => {
                self.wd.min_size.h *= v;
            },
            .horz => {
                self.wd.min_size.w *= v;
            },
        }
    }

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
