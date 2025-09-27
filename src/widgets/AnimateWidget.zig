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
    none,
    alpha,
    vertical,
    horizontal,
};

wd: WidgetData,
init_opts: InitOptions,
val: ?f32 = null,

prev_alpha: f32 = 1.0,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) AnimateWidget {
    const defaults = Options{ .name = "Animate" };
    return AnimateWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)), .init_opts = init_opts };
}

pub fn install(self: *AnimateWidget) void {
    if (self.init_opts.kind != .none) {
        if (dvui.firstFrame(self.data().id)) {
            // start begin animation
            self.start();
        }

        if (dvui.animationGet(self.data().id, "_end")) |a| {
            self.val = a.value();
        } else if (dvui.animationGet(self.data().id, "_start")) |a| {
            self.val = a.value();
        }
    }

    if (self.val) |v| {
        switch (self.init_opts.kind) {
            .none => {},
            .alpha => {
                self.prev_alpha = dvui.alpha(v);
            },
            .vertical => {
                if (dvui.minSizeGet(self.data().id)) |ms| {
                    if (self.data().rect.h > ms.h + 0.001) {
                        // we are bigger than our min size (maybe expanded) - account for floating point
                        const h = self.data().rect.h;
                        self.data().rect.h *= @max(v, 0);
                        self.data().rect.y += self.data().options.gravityGet().y * (h - self.data().rect.h);
                    }
                }
            },
            .horizontal => {
                if (dvui.minSizeGet(self.data().id)) |ms| {
                    if (self.data().rect.w > ms.w + 0.001) {
                        // we are bigger than our min size (maybe expanded) - account for floating point
                        const w = self.data().rect.w;
                        self.data().rect.w *= @max(v, 0);
                        self.data().rect.x += self.data().options.gravityGet().x * (w - self.data().rect.w);
                    }
                }
            },
        }
    }

    dvui.parentSet(self.widget());
    self.data().register();
    self.data().borderAndBackground(.{});
}

pub fn start(self: *AnimateWidget) void {
    dvui.animation(self.data().id, "_start", .{
        .start_val = 0.0,
        .end_val = 1.0,
        .end_time = self.init_opts.duration,
        .easing = self.init_opts.easing orelse dvui.easing.linear,
    });
}

pub fn startEnd(self: *AnimateWidget) void {
    dvui.animation(self.data().id, "_end", .{
        .start_val = 1.0,
        .end_val = 0.0,
        .end_time = self.init_opts.duration,
        .easing = self.init_opts.easing orelse dvui.easing.linear,
    });
}

pub fn end(self: *AnimateWidget) bool {
    if (dvui.animationGet(self.data().id, "_end")) |a| {
        return a.done();
    }

    return false;
}

pub fn widget(self: *AnimateWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *AnimateWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *AnimateWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *AnimateWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *AnimateWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn deinit(self: *AnimateWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.val) |v| {
        switch (self.init_opts.kind) {
            .none => {},
            .alpha => {
                dvui.alphaSet(self.prev_alpha);
            },
            .vertical => {
                // Negative height messes with layout
                self.data().min_size.h *= @max(v, 0);
            },
            .horizontal => {
                // Negative width messes with layout
                self.data().min_size.w *= @max(v, 0);
            },
        }
    }

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

pub const Helpers = struct {
    /// Wrapper widget that takes a single child and animates it.
    ///
    /// `AnimateWidget.start` is called for you on the first frame.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn animate(src: std.builtin.SourceLocation, init_opts: AnimateWidget.InitOptions, opts: Options) *AnimateWidget {
        var ret = dvui.widgetAlloc(AnimateWidget);
        ret.* = AnimateWidget.init(src, init_opts, opts);
        ret.data().was_allocated_on_widget_stack = true;
        ret.install();
        return ret;
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
