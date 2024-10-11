const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const BoxWidget = dvui.BoxWidget;

const ScaleWidget = @This();

wd: WidgetData = undefined,
scale: f32 = undefined,
box: BoxWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, scale_in: f32, opts: Options) ScaleWidget {
    var self = ScaleWidget{};
    const defaults = Options{ .name = "Scale" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.scale = scale_in;
    return self;
}

pub fn install(self: *ScaleWidget) !void {
    dvui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    self.box = BoxWidget.init(@src(), .vertical, false, self.wd.options.strip().override(.{ .expand = .both }));
    try self.box.install();
    try self.box.drawBackground();
}

pub fn widget(self: *ScaleWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ScaleWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ScaleWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    var s: f32 = undefined;
    if (self.scale > 0) {
        s = 1.0 / self.scale;
    } else {
        // prevent divide by zero
        s = 1_000_000.0;
    }

    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize().scale(s), min_size, e, g);
}

pub fn screenRectScale(self: *ScaleWidget, rect: Rect) RectScale {
    var rs = self.wd.contentRectScale();
    rs.s *= self.scale;
    return rs.rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ScaleWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s.scale(self.scale)));
}

pub fn processEvent(self: *ScaleWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *ScaleWidget) void {
    self.box.deinit();
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
