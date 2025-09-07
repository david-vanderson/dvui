/// This is a widget that forwards all parent calls to its parent.  Useful
/// where you want to wrap widgets but only to adjust their IDs.
const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const VirtualParentWidget = @This();

wd: WidgetData,
child_rect_union: ?Rect = null,

pub fn init(src: std.builtin.SourceLocation, opts: Options) VirtualParentWidget {
    const id = dvui.parentGet().extendId(src, opts.idExtra());
    const rect = dvui.dataGet(null, id, "_rect", Rect);
    const defaults = Options{ .name = "Virtual Parent", .rect = rect orelse .{} };
    return VirtualParentWidget{ .wd = WidgetData.init(src, .{}, defaults.override(opts)) };
}

pub fn install(self: *VirtualParentWidget) void {
    dvui.parentSet(self.widget());
    self.data().register();
}

pub fn widget(self: *VirtualParentWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *VirtualParentWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *VirtualParentWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    const ret = self.data().parent.rectFor(id, min_size, e, g);
    if (self.child_rect_union) |u| {
        self.child_rect_union = u.unionWith(ret);
    } else {
        self.child_rect_union = ret;
    }
    return ret;
}

pub fn screenRectScale(self: *VirtualParentWidget, rect: Rect) RectScale {
    return self.data().parent.screenRectScale(rect);
}

pub fn minSizeForChild(self: *VirtualParentWidget, s: Size) void {
    self.data().parent.minSizeForChild(s);
}

pub fn deinit(self: *VirtualParentWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.child_rect_union) |u| {
        dvui.dataSet(null, self.data().id, "_rect", u);
    }
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
