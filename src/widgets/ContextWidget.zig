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

wd: WidgetData = undefined,
init_options: InitOptions = undefined,

winId: dvui.WidgetId = undefined,
focused: bool = false,
activePt: Point.Natural = .{},

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) ContextWidget {
    var self = ContextWidget{};
    const defaults = Options{ .name = "Context" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts).override(.{ .rect = dvui.parentGet().data().rectScale().rectFromPhysical(init_opts.rect) }));
    self.init_options = init_opts;
    self.winId = dvui.subwindowCurrentId();
    if (dvui.focusedWidgetIdInCurrentSubwindow()) |fid| {
        if (fid == self.wd.id) {
            self.focused = true;
        }
    }

    if (dvui.dataGet(null, self.wd.id, "_activePt", Point.Natural)) |a| {
        self.activePt = a;
    }

    return self;
}

pub fn install(self: *ContextWidget) void {
    dvui.parentSet(self.widget());
    self.wd.register();
    self.wd.borderAndBackground(.{});
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

pub fn widget(self: *ContextWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *ContextWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ContextWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    dvui.log.debug("{s}:{d} ContextWidget should not have normal child widgets, only menu stuff", .{ self.wd.src.file, self.wd.src.line });
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ContextWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ContextWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
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

                dvui.focusWidget(self.wd.id, null, e.num);
                self.focused = true;

                // scale the point back to natural so we can use it in Popup
                self.activePt = me.p.toNatural();

                // offset just enough so when Popup first appears nothing is highlighted
                self.activePt.x += 1;
            }
        },
        else => {},
    }
}

pub fn deinit(self: *ContextWidget) void {
    defer dvui.widgetFree(self);
    if (self.focused) {
        dvui.dataSet(null, self.wd.id, "_activePt", self.activePt);
    }

    // we are always given a rect, so we don't do normal layout, don't do these
    //self.wd.minSizeSetAndRefresh();
    //self.wd.minSizeReportToParent();

    dvui.parentReset(self.wd.id, self.wd.parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
