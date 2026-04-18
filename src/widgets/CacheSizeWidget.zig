const std = @import("std");
const dvui = @import("../dvui.zig");

const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const Options = dvui.Options;
const Size = dvui.Size;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;

/// Use to maintain the size of an offscreen widget.  Useful for performance of
/// large scroll areas.
const CacheSizeWidget = @This();

pub const InitOptions = struct {};

wd: WidgetData,
init_opts: InitOptions,
refresh_prev_value: u8,
stable: bool,

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *CacheSizeWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    const defaults = Options{ .name = "CacheSize" };
    self.* = .{
        .wd = .init(src, .{}, defaults.override(opts)),
        .init_opts = init_opts,
        .refresh_prev_value = dvui.currentWindow().extra_frames_needed,
        .stable = undefined,
    };

    self.stable = dvui.dataGetDefault(null, self.data().id, "stable", bool, false);
    if (self.data().visible()) self.stable = false;

    dvui.currentWindow().extra_frames_needed = 0;
    dvui.parentSet(self.widget());
    self.data().register();
    self.data().borderAndBackground(.{});
}

/// Must be called after install().
pub fn uncached(self: *const CacheSizeWidget) bool {
    return !self.stable;
}

pub fn widget(self: *CacheSizeWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *CacheSizeWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *CacheSizeWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *CacheSizeWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *CacheSizeWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn deinit(self: *CacheSizeWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;

    if (!self.stable and dvui.currentWindow().extra_frames_needed == 0) {
        // mark we had a stable frame, we will use this frame's min size going forward
        self.stable = true;
    } else {
        // use min size from last frame
        if (dvui.minSizeGet(self.data().id)) |ms| self.data().minSizeMax(ms);
    }

    dvui.dataSet(null, self.data().id, "stable", self.stable);

    const cw = dvui.currentWindow();
    cw.extra_frames_needed = @max(cw.extra_frames_needed, self.refresh_prev_value);

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
