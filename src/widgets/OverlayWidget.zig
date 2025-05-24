const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const OverlayWidget = @This();

wd: WidgetData = undefined,

pub fn init(src: std.builtin.SourceLocation, opts: Options) OverlayWidget {
    const defaults = Options{ .name = "Overlay" };
    return OverlayWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)) };
}

pub fn install(self: *OverlayWidget) !void {
    dvui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn widget(self: *OverlayWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *OverlayWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *OverlayWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *OverlayWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *OverlayWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *OverlayWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *OverlayWidget) void {
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
