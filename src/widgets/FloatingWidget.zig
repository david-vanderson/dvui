const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const FloatingWidget = @This();

pub var defaults: Options = .{
    .name = "Floating",
};

prev_rendering: bool = undefined,
wd: WidgetData = undefined,
prev_windowId: dvui.WidgetId = undefined,
prevClip: Rect.Physical = .{},
scale_val: f32 = undefined,
scaler: dvui.ScaleWidget = undefined,

/// FloatingWidget is a subwindow to show any temporary floating thing.
/// It doesn't focus itself (as a subwindow), and whether it is shown or not is
/// entirely up to the calling code.
///
/// Don't put menus or menuItems in a floating widget because those depend on
/// focus to work.  FloatingMenu is made for that.
///
/// Use FloatingWindowWidget for a floating window that the user can change
/// size, move around, and adjust stacking.
pub fn init(src: std.builtin.SourceLocation, opts_in: Options) FloatingWidget {
    var self = FloatingWidget{};

    // get scale from parent
    self.scale_val = dvui.parentGet().screenRectScale(Rect{}).s / dvui.windowNaturalScale();
    var opts = opts_in;
    if (opts.min_size_content) |msc| {
        opts.min_size_content = msc.scale(self.scale_val, Size);
    }

    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, defaults.override(opts).override(.{ .rect = opts.rect orelse .{} }));

    return self;
}

pub fn install(self: *FloatingWidget) void {
    self.prev_rendering = dvui.renderingSet(false);

    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.wd.id, null).id;

    const rs = self.wd.rectScale();

    dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, self.prev_windowId);
    dvui.captureMouseMaintain(.{ .id = self.wd.id, .rect = rs.r, .subwindow_id = self.wd.id });
    self.wd.register();

    // first break out of whatever clipping we were in
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());

    self.wd.borderAndBackground(.{});

    // clip to just our window (using clipSet since we are not inside our parent)
    _ = dvui.clip(rs.r);

    self.scaler = dvui.ScaleWidget.init(@src(), .{ .scale = &self.scale_val }, .{ .expand = .both });
    self.scaler.install();
}

pub fn widget(self: *FloatingWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *FloatingWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn deinit(self: *FloatingWidget) void {
    defer dvui.widgetFree(self);
    self.scaler.deinit();
    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    dvui.parentReset(self.wd.id, self.wd.parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowId, null);
    dvui.clipSet(self.prevClip);
    _ = dvui.renderingSet(self.prev_rendering);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
