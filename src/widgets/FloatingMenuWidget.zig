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

/// SAFETY: Set by `install`
prev_rendering: bool = undefined,
wd: WidgetData,
/// options is for our embedded ScrollAreaWidget
options: Options,
prev_windowId: dvui.WidgetId = .zero,
prev_last_focus: dvui.WidgetId = undefined,
parent_popup: ?*FloatingMenuWidget = null,
have_popup_child: bool = false,
init_options: InitOptions,
/// SAFETY: Set by `install`
prevClip: Rect.Physical = undefined,
scale_val: f32,
/// TODO: If `install` isn't called, this will panic in `deinti`. Should we handle that?
/// SAFETY: Set by `install`
menu: MenuWidget = undefined,
/// SAFETY: Set by `install`
scaler: dvui.ScaleWidget = undefined,
/// SAFETY: Set by `install`
scroll: ScrollAreaWidget = undefined,

pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) FloatingMenuWidget {
    // the widget itself doesn't have any styling, it comes from the
    // embedded MenuWidget
    // passing options.rect will stop WidgetData.init from calling
    // rectFor/minSizeForChild which is important because we are outside
    // normal layout
    const wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{} });

    var self = FloatingMenuWidget{
        .wd = wd,
        // options is really for our embedded ScrollAreaWidget, so save them for the
        // end of install()
        .options = defaults.override(opts),
        // get scale from parent
        .scale_val = wd.parent.screenRectScale(Rect{}).s / dvui.windowNaturalScale(),
        .init_options = init_options,
    };

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

pub fn install(self: *FloatingMenuWidget) void {
    self.prev_rendering = dvui.renderingSet(false);

    dvui.parentSet(self.widget());

    self.prev_windowId = dvui.subwindowCurrentSet(self.data().id, null).id;
    self.parent_popup = popupSet(self);
    // prevents parents from processing key events if focus is inside the floating window:w
    self.prev_last_focus = dvui.lastFocusedIdInFrame(null);

    const avoid: dvui.PlaceOnScreenAvoid = switch (self.init_options.avoid) {
        .none => .none,
        .horizontal => .horizontal,
        .vertical => .vertical,
        .auto => unreachable,
    };

    self.data().rect = Rect.fromPoint(.cast(self.init_options.from.topLeft()));
    if (dvui.minSizeGet(self.data().id)) |_| {
        const ms = dvui.minSize(self.data().id, self.options.min_sizeGet());
        self.data().rect = self.data().rect.toSize(ms);
        self.data().rect = .cast(dvui.placeOnScreen(dvui.windowRect(), self.init_options.from, avoid, .cast(self.data().rect)));
    } else {
        self.data().rect = .cast(dvui.placeOnScreen(dvui.windowRect(), self.init_options.from, avoid, .cast(self.data().rect)));
        dvui.focusSubwindow(self.data().id, null);

        // need a second frame to fit contents (FocusWindow calls refresh but
        // here for clarity)
        dvui.refresh(null, @src(), self.data().id);
    }

    const rs = self.data().rectScale();

    dvui.subwindowAdd(self.data().id, self.data().rect, rs.r, false, null);
    dvui.captureMouseMaintain(.{ .id = self.data().id, .rect = rs.r, .subwindow_id = self.data().id });
    self.data().register();

    // first break out of whatever clip we were in (so box shadows work, since
    // they are outside our window)
    self.prevClip = dvui.clipGet();
    dvui.clipSet(dvui.windowRectPixels());

    self.scaler = dvui.ScaleWidget.init(@src(), .{ .scale = &self.scale_val }, .{ .expand = .both });
    self.scaler.install();

    // we are using scroll to do border/background but floating windows
    // don't have margin, so turn that off
    self.scroll = ScrollAreaWidget.init(@src(), .{ .horizontal = .none }, self.options.override(.{ .margin = .{}, .expand = .both }));
    self.scroll.install();

    // clip to just our window (using clipSet since we are not inside our parent)
    _ = dvui.clip(rs.r);

    if (dvui.MenuWidget.current()) |pm| {
        pm.child_popup_rect = rs.r;
    }

    self.menu = MenuWidget.init(@src(), .{ .dir = .vertical }, self.options.strip().override(.{ .expand = .horizontal }));
    self.menu.parentSubwindowId = self.prev_windowId;
    self.menu.install();

    // if no widget in this popup has focus, make the menu have focus to handle keyboard events
    if (dvui.focusedWidgetIdInCurrentSubwindow() == null) {
        dvui.focusWidget(self.menu.data().id, null, null);
    }
}

pub fn close(self: *FloatingMenuWidget) void {
    self.menu.close();
}

pub fn widget(self: *FloatingMenuWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *FloatingMenuWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *FloatingMenuWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *FloatingMenuWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *FloatingMenuWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn chainFocused(self: *FloatingMenuWidget, self_call: bool) bool {
    if (!self_call) {
        // if we got called by someone else, then we have a popup child
        self.have_popup_child = true;
    }

    var ret: bool = false;

    // we have to call chainFocused on our parent if we have one so we
    // can't return early

    if (self.data().id == dvui.focusedSubwindowId()) {
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
    defer dvui.widgetFree(self);

    const evts = dvui.events();
    const rs = self.data().rectScale();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = rs.r, .cleanup = true }))
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
            self.close();
        }
    }

    if (!self.have_popup_child and !self.chainFocused(true)) {
        // if a popup chain is open and the user focuses a different window
        // (not the parent of the popups), then we want to close the popups

        // only the last popup can do the check, you can't query the focus
        // status of children, only parents
        self.menu.close_chain(.unintentional);
        dvui.refresh(null, @src(), self.data().id);
    }

    self.menu.deinit();
    self.scroll.deinit();
    self.scaler.deinit();

    // in case no children ever show up, this will provide a visual indication
    // that there is an empty floating menu
    self.data().minSizeMax(self.data().options.padSize(.{ .w = 20, .h = 20 }));

    self.data().minSizeSetAndRefresh();

    // outside normal layout, don't call minSizeForChild or self.data().minSizeReportToParent();

    _ = popupSet(self.parent_popup);
    dvui.parentReset(self.data().id, self.data().parent);
    dvui.currentWindow().last_focused_id_this_frame = self.prev_last_focus;
    _ = dvui.subwindowCurrentSet(self.prev_windowId, null);
    dvui.clipSet(self.prevClip);
    _ = dvui.renderingSet(self.prev_rendering);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
