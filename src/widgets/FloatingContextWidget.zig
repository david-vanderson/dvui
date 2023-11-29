const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const FloatingContextWidget = @This();

pub var defaults: Options = .{
    .name = "FloatingContext",
};

pub const InitOptions = struct {
    parent_rectscale: RectScale,
};

wd: WidgetData = undefined,
init_opts: InitOptions = undefined,
options: Options = undefined,
prev_windowId: u32 = 0,
prevClip: Rect = Rect{},

/// FloatingContextWidget is a subwindow to show a small floating context menu.
/// It doesn't focus itself (as a subwindow), and whether it is shown or not is
/// entirely up to the calling code.
///
/// Don't put menus or menuItems in a floating context because those depend on
/// focus to work.
pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FloatingContextWidget {
    var self = FloatingContextWidget{};
    self.init_opts = init_opts;

    self.options = defaults.override(opts);

    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{} });

    return self;
}

pub fn install(self: *FloatingContextWidget) !void {
    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.wd.id);
    var r = self.init_opts.parent_rectscale.r.offsetNeg(dvui.windowRectPixels()).scale(1.0 / dvui.windowNaturalScale());

    if (dvui.minSizeGet(self.wd.id)) |_| {
        const ms = dvui.minSize(self.wd.id, self.options.min_sizeGet());
        self.wd.rect.w = ms.w;
        self.wd.rect.h = ms.h;

        self.wd.rect.x = r.x + r.w - self.wd.rect.w;
        self.wd.rect.y = r.y - self.wd.rect.h;

        self.wd.rect = dvui.placeOnScreen(dvui.windowRect(), .{ .x = self.wd.rect.x, .y = self.wd.rect.y }, self.wd.rect);
    } else {
        // need another frame to get our min size
        dvui.refresh(null, @src(), self.wd.id);
    }

    const rs = self.wd.rectScale();

    try dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, null);
    dvui.captureMouseMaintain(self.wd.id);
    try self.wd.register();

    // clip to just our window (using clipSet since we are not inside our parent)
    self.prevClip = dvui.clipGet();
    dvui.clipSet(rs.r);
}

pub fn widget(self: *FloatingContextWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FloatingContextWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingContextWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
}

pub fn screenRectScale(self: *FloatingContextWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToScreen(rect);
}

pub fn minSizeForChild(self: *FloatingContextWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
}

pub fn processEvent(self: *FloatingContextWidget, e: *Event, bubbling: bool) void {
    // no normal events, just forward close_popup
    switch (e.evt) {
        .close_popup => {
            self.wd.parent.processEvent(e, true);
        },
        else => {},
    }

    // otherwise don't bubble events
    _ = bubbling;
}

pub fn deinit(self: *FloatingContextWidget) void {
    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    dvui.parentReset(self.wd.id, self.wd.parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowId);
    dvui.clipSet(self.prevClip);
}
