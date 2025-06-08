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

pub const InitOptions = struct {
    kind: Kind,
    /// Duration in microseconds
    duration: i32,
    easing: ?*const dvui.easing.EasingFn = null,
};

pub const Kind = enum {
    alpha,
    vertical,
    horizontal,
};

wd: WidgetData = undefined,
init_opts: InitOptions = undefined,
val: ?f32 = null,

prev_alpha: f32 = 1.0,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) AnimateWidget {
    const defaults = Options{ .name = "Animate" };
    return AnimateWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)), .init_opts = init_opts };
}

pub fn install(self: *AnimateWidget) !void {
    if (dvui.firstFrame(self.wd.id)) {
        // start begin animation
        self.start();
    }

    if (dvui.animationGet(self.wd.id, "_end")) |a| {
        self.val = a.value();
    } else if (dvui.animationGet(self.wd.id, "_start")) |a| {
        self.val = a.value();
    }

    if (self.val) |v| {
        switch (self.init_opts.kind) {
            .alpha => {
                self.prev_alpha = dvui.themeGet().alpha;
                // alpha crashed if v is not between 0 and 1, which some easing functions may output
                dvui.themeGet().alpha *= std.math.clamp(v, 0, 1);
            },
            .vertical => {
                if (dvui.minSizeGet(self.wd.id)) |ms| {
                    if (self.wd.rect.h > ms.h + 0.001) {
                        // we are bigger than our min size (maybe expanded) - account for floating point
                        const h = self.wd.rect.h;
                        self.wd.rect.h *= @max(v, 0);
                        self.wd.rect.y += self.wd.options.gravityGet().y * (h - self.wd.rect.h);
                    }
                }
            },
            .horizontal => {
                if (dvui.minSizeGet(self.wd.id)) |ms| {
                    if (self.wd.rect.w > ms.w + 0.001) {
                        // we are bigger than our min size (maybe expanded) - account for floating point
                        const w = self.wd.rect.w;
                        self.wd.rect.w *= @max(v, 0);
                        self.wd.rect.x += self.wd.options.gravityGet().x * (w - self.wd.rect.w);
                    }
                }
            },
        }
    }

    dvui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn start(self: *AnimateWidget) void {
    dvui.animation(self.wd.id, "_start", .{
        .start_val = 0.0,
        .end_val = 1.0,
        .end_time = self.init_opts.duration,
        .easing = self.init_opts.easing orelse dvui.easing.linear,
    });
}

pub fn startEnd(self: *AnimateWidget) void {
    dvui.animation(self.wd.id, "_end", .{
        .start_val = 1.0,
        .end_val = 0.0,
        .end_time = self.init_opts.duration,
        .easing = self.init_opts.easing orelse dvui.easing.linear,
    });
}

pub fn end(self: *AnimateWidget) bool {
    if (dvui.animationGet(self.wd.id, "_end")) |a| {
        return a.done();
    }

    return false;
}

pub fn widget(self: *AnimateWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *AnimateWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *AnimateWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *AnimateWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *AnimateWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *AnimateWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *AnimateWidget) void {
    if (self.val) |v| {
        switch (self.init_opts.kind) {
            .alpha => {
                dvui.themeGet().alpha = self.prev_alpha;
            },
            .vertical => {
                // Negative height messes with layout
                self.wd.min_size.h *= @max(v, 0);
            },
            .horizontal => {
                // Negative width messes with layout
                self.wd.min_size.w *= @max(v, 0);
            },
        }
    }

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
