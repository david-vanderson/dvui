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

wd: WidgetData,

pub fn init(src: std.builtin.SourceLocation, opts: Options) OverlayWidget {
    const defaults = Options{ .name = "Overlay" };
    return OverlayWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)) };
}

pub fn install(self: *OverlayWidget) void {
    dvui.parentSet(self.widget());
    self.data().register();
}

pub fn drawBackground(self: *OverlayWidget) void {
    self.data().borderAndBackground(.{});
}

pub fn widget(self: *OverlayWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *OverlayWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *OverlayWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *OverlayWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *OverlayWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn deinit(self: *OverlayWidget) void {
    defer dvui.widgetFree(self);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
