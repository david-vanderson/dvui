const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const MenuWidget = dvui.MenuWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;

const FloatingMenuWidget = @This();

pub const FloatingMenuAvoid = enum {
    none,
    horizontal,
    vertical,

    /// Pick horizontal or vertical based on the direction of the current
    /// parent menu (if any).
    auto,
};

// this lets us maintain a chain of all the nested FloatingMenuWidgets without
// forcing the user to manually do it
var popup_current: ?*FloatingMenuWidget = null;

fn popupSet(p: ?*FloatingMenuWidget) ?*FloatingMenuWidget {
    const ret = popup_current;
    popup_current = p;
    return ret;
}

pub var defaults: Options = .{
    .name = "FloatingMenu",
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .padding = Rect.all(4),
    .background = true,
    .color_fill = .{ .name = .fill_window },
};

pub const InitOptions = struct {
    from: Rect.Natural,
    avoid: FloatingMenuAvoid = .auto,
};

prev_rendering: bool = undefined,
wd: WidgetData = undefined,
options: Options = undefined,
prev_windowId: dvui.WidgetId = .zero,
parent_popup: ?*FloatingMenuWidget = null,
have_popup_child: bool = false,
menu: MenuWidget = undefined,
init_options: InitOptions = undefined,
prevClip: Rect.Physical = .{},
scale_val: f32 = undefined,
scaler: dvui.ScaleWidget = undefined,
scroll: ScrollAreaWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) FloatingMenuWidget {
    var self = FloatingMenuWidget{};

    // options is really for our embedded ScrollAreaWidget, so save them for the
    // end of install()
    self.options = defaults.override(opts);

    // the widget itself doesn't have any styling, it comes from the
    // embedded MenuWidget
    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{} });

    // get scale from parent
    self.scale_val = self.wd.parent.screenRectScale(Rect{}).s / dvui.windowNaturalScale();

    self.init_options = init_opts;
    if (self.init_options.avoid == .auto) {
        if (dvui.MenuWidget.current()) |pm| {
            self.init_options.avoid = switch (pm.init_opts.dir) {
                .horizontal => .vertical,
                .vertical => .horizontal,
            };
        } else {
            self.init_options.avoid = .none;
        }
    }
    return self;
}

pub fn install(self: *FloatingMenuWidget) !void {
    self.prev_rendering = dvui.renderingSet(false);

    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.wd.id, null).id;
    self.parent_popup = popupSet(self);

    const avoid: dvui.PlaceOnScreenAvoid = switch (self.init_options.avoid) {
        .none => .none,
        .horizontal => .horizontal,
        .vertical => .vertical,
        .auto => unreachable,
    };

    self.wd.rect = Rect.fromPoint(.cast(self.init_options.from.topLeft()));
    if (dvui.minSizeGet(self.wd.id)) |_| {
        const ms = dvui.minSize(self.wd.id, self.options.min_sizeGet());
        self.wd.rect = self.wd.rect.toSize(ms);
        self.wd.rect = .cast(dvui.placeOnScreen(dvui.windowRect(), self.init_options.from, avoid, .cast(self.wd.rect)));
    } else {
        self.wd.rect = .cast(dvui.placeOnScreen(dvui.windowRect(), self.init_options.from, avoid, .cast(self.wd.rect)));
        dvui.focusSubwindow(self.wd.id, null);

        // need a second frame to fit contents (FocusWindow calls refresh but
        // here for clarity)
        dvui.refresh(null, @src(), self.wd.id);
    }

    const rs = self.wd.rectScale();

    try dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, null);
    dvui.captureMouseMaintain(.{ .id = self.wd.id, .rect = rs.r, .subwindow_id = self.wd.id });
    try self.wd.register();

    // first break out of whatever clip we were in (so box shadows work, since
    // they are outside our window)
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());

    self.scaler = dvui.ScaleWidget.init(@src(), .{ .scale = &self.scale_val }, .{ .expand = .both });
    try self.scaler.install();

    // we are using scroll to do border/background but floating windows
    // don't have margin, so turn that off
    self.scroll = ScrollAreaWidget.init(@src(), .{ .horizontal = .none }, self.options.override(.{ .margin = .{}, .expand = .both }));
    try self.scroll.install();

    // clip to just our window (using clipSet since we are not inside our parent)
    _ = dvui.clip(rs.r);

    if (dvui.MenuWidget.current()) |pm| {
        pm.child_popup_rect = rs.r;
    }

    self.menu = MenuWidget.init(@src(), .{ .dir = .vertical }, self.options.strip().override(.{ .expand = .horizontal }));
    self.menu.parentSubwindowId = self.prev_windowId;
    try self.menu.install();

    // if no widget in this popup has focus, make the menu have focus to handle keyboard events
    if (dvui.focusedWidgetIdInCurrentSubwindow() == null) {
        dvui.focusWidget(self.menu.wd.id, null, null);
    }
}

pub fn close(self: *FloatingMenuWidget) void {
    self.menu.close();
}

pub fn widget(self: *FloatingMenuWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *FloatingMenuWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *FloatingMenuWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingMenuWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingMenuWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *FloatingMenuWidget, e: *Event, bubbling: bool) void {
    // popup does cleanup events, but not normal events
    switch (e.evt) {
        .close_popup => {
            self.wd.parent.processEvent(e, true);
        },
        else => {},
    }

    // otherwise popups don't bubble events
    _ = bubbling;
}

pub fn chainFocused(self: *FloatingMenuWidget, self_call: bool) bool {
    if (!self_call) {
        // if we got called by someone else, then we have a popup child
        self.have_popup_child = true;
    }

    var ret: bool = false;

    // we have to call chainFocused on our parent if we have one so we
    // can't return early

    if (self.wd.id == dvui.focusedSubwindowId()) {
        // we are focused
        ret = true;
    }

    if (self.parent_popup) |pp| {
        // we had a parent popup, is that focused
        if (pp.chainFocused(false)) {
            ret = true;
        }
    } else if (self.prev_windowId == dvui.focusedSubwindowId()) {
        // no parent popup, is our parent window focused
        ret = true;
    }

    return ret;
}

pub fn deinit(self: *FloatingMenuWidget) void {
    self.menu.deinit();
    self.scroll.deinit();
    self.scaler.deinit();

    const rs = self.wd.rectScale();
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r, .cleanup = true }))
            continue;

        if (e.evt == .mouse) {
            if (e.evt.mouse.action == .focus) {
                // unhandled click, clear focus
                e.handle(@src(), self.data());
                dvui.focusWidget(null, null, null);
            }
        } else if (e.evt == .key) {
            // catch any tabs that weren't handled by widgets
            if (e.evt.key.action == .down and e.evt.key.matchBind("next_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexNext(e.num);
            }

            if (e.evt.key.action == .down and e.evt.key.matchBind("prev_widget")) {
                e.handle(@src(), self.data());
                dvui.tabIndexPrev(e.num);
            }
        }
    }

    // check if a focus event is happening outside our window
    for (evts) |e| {
        if (!e.handled and e.evt == .mouse and e.evt.mouse.action == .focus) {
            var closeE = Event{ .evt = .{ .close_popup = .{} } };
            self.processEvent(&closeE, true);
        }
    }

    if (!self.have_popup_child and !self.chainFocused(true)) {
        // if a popup chain is open and the user focuses a different window
        // (not the parent of the popups), then we want to close the popups

        // only the last popup can do the check, you can't query the focus
        // status of children, only parents
        var closeE = Event{ .evt = .{ .close_popup = .{ .intentional = false } } };
        self.processEvent(&closeE, true);
    }

    // in case no children ever show up, this will provide a visual indication
    // that there is an empty floating menu
    self.wd.minSizeMax(self.wd.options.padSize(.{ .w = 20, .h = 20 }));

    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    _ = popupSet(self.parent_popup);
    dvui.parentReset(self.wd.id, self.wd.parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowId, null);
    dvui.clipSet(self.prevClip);
    _ = dvui.renderingSet(self.prev_rendering);
}

test {
    @import("std").testing.refAllDecls(@This());
}
