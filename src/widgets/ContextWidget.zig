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

wd: WidgetData = undefined,

winId: u32 = undefined,
focused: bool = false,
activePt: Point = Point{},

pub fn init(src: std.builtin.SourceLocation, opts: Options) ContextWidget {
    var self = ContextWidget{};
    const defaults = Options{ .name = "Context" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.winId = dvui.subwindowCurrentId();
    if (dvui.focusedWidgetIdInCurrentSubwindow()) |fid| {
        if (fid == self.wd.id) {
            self.focused = true;
        }
    }

    if (dvui.dataGet(null, self.wd.id, "_activePt", Point)) |a| {
        self.activePt = a;
    }

    return self;
}

pub fn install(self: *ContextWidget) !void {
    dvui.parentSet(self.widget());
    try self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn activePoint(self: *ContextWidget) ?Point {
    if (self.focused) {
        return self.activePt;
    }

    return null;
}

pub fn widget(self: *ContextWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ContextWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ContextWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ContextWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ContextWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *ContextWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    switch (e.evt) {
        .close_popup => {
            if (self.focused) {
                // we are getting a bubbled event, so the window we are in is not the current one
                dvui.focusWidget(null, self.winId, null);
            }
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn processMouseEventsAfter(self: *ContextWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatchSimple(e, self.data()))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus and me.button == .right) {
                    // eat any right button focus events so they don't get
                    // caught by the containing window cleanup and cause us
                    // to lose the focus we are about to get from the right
                    // press below
                    e.handled = true;
                } else if (me.action == .press and me.button == .right) {
                    e.handled = true;

                    dvui.focusWidget(self.wd.id, null, e.num);
                    self.focused = true;

                    // scale the point back to natural so we can use it in Popup
                    self.activePt = me.p.scale(1 / dvui.windowNaturalScale());

                    // offset just enough so when Popup first appears nothing is highlighted
                    self.activePt.x += 1;
                }
            },
            else => {},
        }
    }
}

pub fn deinit(self: *ContextWidget) void {
    self.processMouseEventsAfter();
    if (self.focused) {
        dvui.dataSet(null, self.wd.id, "_activePt", self.activePt);
    }
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
