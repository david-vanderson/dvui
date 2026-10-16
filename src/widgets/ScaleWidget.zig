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

pub const InitOptions = struct {
    scale: ?*f32 = null,
};

wd: WidgetData,
init_options: InitOptions,
scale: *f32 = undefined,
layout: dvui.BasicLayout = .{},

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *ScaleWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    const defaults = Options{ .name = "Scale" };
    const wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.* = .{
        .wd = wd,
        .init_options = init_opts,
    };

    if (self.init_options.scale) |init_s| {
        self.scale = init_s;
    } else {
        self.scale = dvui.dataGetPtrDefault(null, self.data().id, "_scale", f32, 1.0);
    }

    dvui.parentSet(self.widget());
    self.data().register();
    self.data().borderAndBackground(.{});
}

pub fn widget(self: *ScaleWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *ScaleWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *ScaleWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    const s = if (self.scale.* > 0)
        1.0 / self.scale.*
    else
        // prevent divide by zero
        1_000_000.0;

    return self.layout.rectFor(self.data().contentRect().justSize().scale(s, Rect), id, min_size, e, g);
}

pub fn screenRectScale(self: *ScaleWidget, rect: Rect) RectScale {
    var rs = self.data().contentRectScale();
    rs.s *= self.scale.*;
    return rs.rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ScaleWidget, s: Size) void {
    const ms = self.layout.minSizeForChild(s.scale(self.scale.*, Size));
    self.data().minSizeMax(self.data().options.padSize(ms));
}

pub fn deinit(self: *ScaleWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;
    dvui.dataSet(null, self.data().id, "_scale", self.scale.*);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
