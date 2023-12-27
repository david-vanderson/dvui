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

const PopupWidget = @This();

pub var defaults: Options = .{
    .name = "Popup",
    .corner_radius = Rect.all(5),
    .border = Rect.all(1),
    .padding = Rect.all(4),
    .background = true,
    .color_fill = .{ .name = .fill_window },
};

wd: WidgetData = undefined,
options: Options = undefined,
prev_windowId: u32 = 0,
parent_popup: ?*PopupWidget = null,
have_popup_child: bool = false,
menu: MenuWidget = undefined,
initialRect: Rect = Rect{},
prevClip: Rect = Rect{},
scroll: ScrollAreaWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, initialRect: Rect, opts: Options) PopupWidget {
    var self = PopupWidget{};

    // options is really for our embedded MenuWidget, so save them for the
    // end of install()
    self.options = defaults.override(opts);

    // the popup itself doesn't have any styling, it comes from the
    // embedded MenuWidget
    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{} });

    self.initialRect = initialRect;
    return self;
}

pub fn install(self: *PopupWidget) !void {
    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.wd.id);
    self.parent_popup = dvui.popupSet(self);

    if (dvui.minSizeGet(self.wd.id)) |_| {
        self.wd.rect = Rect.fromPoint(self.initialRect.topLeft());
        const ms = dvui.minSize(self.wd.id, self.options.min_sizeGet());
        self.wd.rect.w = ms.w;
        self.wd.rect.h = ms.h;
        self.wd.rect = dvui.placeOnScreen(dvui.windowRect(), self.initialRect, self.wd.rect);
    } else {
        self.wd.rect = dvui.placeOnScreen(dvui.windowRect(), self.initialRect, Rect.fromPoint(self.initialRect.topLeft()));
        dvui.focusSubwindow(self.wd.id, null);

        // need a second frame to fit contents (FocusWindow calls refresh but
        // here for clarity)
        dvui.refresh(null, @src(), self.wd.id);
    }

    const rs = self.wd.rectScale();

    try dvui.subwindowAdd(self.wd.id, self.wd.rect, rs.r, false, null);
    dvui.captureMouseMaintain(self.wd.id);
    try self.wd.register();

    // clip to just our window (using clipSet since we are not inside our parent)
    self.prevClip = dvui.clipGet();
    dvui.clipSet(rs.r);

    // we are using scroll to do border/background but floating windows
    // don't have margin, so turn that off
    self.scroll = ScrollAreaWidget.init(@src(), .{ .horizontal = .none }, self.options.override(.{ .margin = .{}, .expand = .both }));
    try self.scroll.install();

    if (dvui.menuGet()) |pm| {
        pm.child_popup_rect = rs.r;
    }

    self.menu = MenuWidget.init(@src(), .{ .dir = .vertical, .submenus_activated_by_default = true }, self.options.strip().override(.{ .expand = .horizontal }));
    self.menu.parentSubwindowId = self.prev_windowId;
    try self.menu.install();

    // if no widget in this popup has focus, make the menu have focus to handle keyboard events
    if (dvui.focusedWidgetIdInCurrentSubwindow() == null) {
        dvui.focusWidget(self.menu.wd.id, null, null);
    }
}

pub fn widget(self: *PopupWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *PopupWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *PopupWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
}

pub fn screenRectScale(self: *PopupWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *PopupWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
}

pub fn processEvent(self: *PopupWidget, e: *Event, bubbling: bool) void {
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

pub fn chainFocused(self: *PopupWidget, self_call: bool) bool {
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

pub fn deinit(self: *PopupWidget) void {
    self.menu.deinit();
    self.scroll.deinit();

    self.options.min_size_content = self.scroll.si.virtual_size;
    self.wd.minSizeMax(self.options.min_sizeGet());

    const rs = self.wd.rectScale();
    var evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r, .cleanup = true }))
            continue;

        if (e.evt == .mouse) {
            if (e.evt.mouse.action == .focus) {
                // unhandled click, clear focus
                e.handled = true;
                dvui.focusWidget(null, null, null);
            }
        } else if (e.evt == .key) {
            // catch any tabs that weren't handled by widgets
            if (e.evt.key.code == .tab and e.evt.key.action == .down) {
                e.handled = true;
                if (e.evt.key.mod.shift()) {
                    dvui.tabIndexPrev(e.num);
                } else {
                    dvui.tabIndexNext(e.num);
                }
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

    self.wd.minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

    _ = dvui.popupSet(self.parent_popup);
    dvui.parentReset(self.wd.id, self.wd.parent);
    _ = dvui.subwindowCurrentSet(self.prev_windowId);
    dvui.clipSet(self.prevClip);
}
