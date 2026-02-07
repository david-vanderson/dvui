const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Point = dvui.Point;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const ContextWidget = @This();

pub const InitOptions = struct {
    /// physical rect where right-click triggers the context menu
    rect: Rect.Physical,
};

wd: WidgetData,
init_options: InitOptions,

prev_menu_root: ?dvui.MenuWidget.Root = null,
winId: dvui.Id,
focused: bool = false,
activePt: Point.Natural = .{},

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *ContextWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    const defaults = Options{ .name = "Context" };
    self.* = .{
        .wd = WidgetData.init(src, .{}, defaults.override(opts).override(.{ .rect = dvui.parentGet().data().contentRectScale().rectFromPhysical(init_opts.rect) })),
        .init_options = init_opts,
        .winId = dvui.subwindowCurrentId(),
    };
    if (dvui.focusedWidgetIdInCurrentSubwindow()) |fid| {
        if (fid == self.wd.id) {
            self.focused = true;
        }
    }

    if (dvui.dataGet(null, self.data().id, "_activePt", Point.Natural)) |a| {
        self.activePt = a;
    }

    dvui.parentSet(self.widget());
    self.prev_menu_root = dvui.MenuWidget.Root.set(.{ .ptr = self, .close = menu_root_close });
    self.data().register();
    self.data().borderAndBackground(.{});
}

pub fn activePoint(self: *ContextWidget) ?Point.Natural {
    if (self.focused) {
        return self.activePt;
    }

    return null;
}

pub fn close(self: *ContextWidget) void {
    self.focused = false;
    dvui.focusWidget(null, self.winId, null);
}

/// Used as a close callback for menus closing
fn menu_root_close(ptr: *anyopaque, _: dvui.MenuWidget.CloseReason) void {
    const self: *ContextWidget = @ptrCast(@alignCast(ptr));
    self.close();
}

pub fn widget(self: *ContextWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *ContextWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *ContextWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    dvui.log.debug("{s}:{d} ContextWidget should not have normal child widgets, only menu stuff", .{ self.data().src.file, self.data().src.line });
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ContextWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ContextWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn processEvents(self: *ContextWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatchSimple(e, self.data()))
            continue;

        self.processEvent(e);
    }
}

pub fn processEvent(self: *ContextWidget, e: *Event) void {
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus and me.button == .right) {
                // eat any right button focus events so they don't get
                // caught by the containing window cleanup and cause us
                // to lose the focus we are about to get from the right
                // press below
                e.handle(@src(), self.data());
            } else if (me.action == .press and me.button == .right) {
                e.handle(@src(), self.data());

                dvui.focusWidget(self.data().id, null, e.num);
                self.focused = true;

                // scale the point back to natural so we can use it in Popup
                self.activePt = me.p.toNatural();

                // offset just enough so when Popup first appears nothing is highlighted
                self.activePt.x += 1;

                // allows right-click-drag-release-activate
                dvui.dragStart(me.p, .{ .name = "_mi_mouse_down" });
            }
        },
        else => {},
    }
}

pub fn deinit(self: *ContextWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.focused) {
        dvui.dataSet(null, self.data().id, "_activePt", self.activePt);
    }

    // we are always given a rect, so we don't do normal layout, don't do these
    //self.data().minSizeSetAndRefresh();
    //self.data().minSizeReportToParent();

    _ = dvui.MenuWidget.Root.set(self.prev_menu_root);
    dvui.parentReset(self.data().id, self.data().parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
