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
const BoxWidget = dvui.BoxWidget;

const enums = dvui.enums;

const MenuWidget = @This();

/// This allows for other widgets to register as the root
/// of some widget chain to be notified when, for example,
/// the menu chain closes.
///
/// This is used by `dvui.ContextWidget`
pub const Root = struct {
    ptr: *anyopaque,
    close: *const fn (ptr: *anyopaque, reason: CloseReason) void,

    var current: ?Root = null;

    pub fn set(root: ?Root) ?Root {
        defer Root.current = root;
        return Root.current;
    }
};

pub const CloseReason = enum {
    /// The user pressed some button that causes the menu to close
    intentional,
    /// The menu lost focus or similar and should close, but the
    /// user didn't explicitly close the menu themselves.
    unintentional,
};

var menu_current: ?*MenuWidget = null;

pub fn current() ?*MenuWidget {
    return menu_current;
}

fn menuSet(m: ?*MenuWidget) ?*MenuWidget {
    const ret = menu_current;
    menu_current = m;
    return ret;
}

pub var defaults: Options = .{
    .name = "Menu",
    .color_fill = .{ .name = .fill_window },
};

pub const InitOptions = struct {
    dir: enums.Direction,
};

wd: WidgetData,

init_opts: InitOptions,
winId: dvui.WidgetId,
parentMenu: ?*MenuWidget = null,
parentSubwindowId: ?dvui.WidgetId = null,
last_focus: dvui.WidgetId,
/// SAFETY: Set in `install`
box: BoxWidget = undefined,

// whether submenus should be open
submenus_activated: bool = false,

// whether submenus in a child menu should default to open (for mouse interactions, not for keyboard)
submenus_in_child: bool = false,
mouse_over: bool = false,

// if we have a child popup menu, save it's rect for next frame
// supports mouse skipping over menu items if towards the submenu
child_popup_rect: ?Rect.Physical = null,

// false means the last interaction we got was keyboard, so don't highlight the
// entry that happens to be under the mouse
mouse_mode: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) MenuWidget {
    var self = MenuWidget{
        .wd = WidgetData.init(src, .{}, defaults.override(opts)),
        .init_opts = init_opts,
        .winId = dvui.subwindowCurrentId(),
        .last_focus = dvui.lastFocusedIdInFrame(null),
    };

    if (dvui.dataGet(null, self.wd.id, "_sub_act", bool)) |a| {
        self.submenus_activated = a;
    } else if (current()) |pm| {
        self.submenus_activated = pm.submenus_in_child;
    }

    if (dvui.dataGet(null, self.wd.id, "_mouse_mode", bool)) |mouse_mode| self.mouse_mode = mouse_mode;

    return self;
}

pub fn install(self: *MenuWidget) void {
    dvui.parentSet(self.widget());
    self.parentMenu = menuSet(self);
    self.data().register();
    self.data().borderAndBackground(.{});

    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatchSimple(e, self.data()))
            continue;

        self.processEvent(e);
    }

    self.box = BoxWidget.init(@src(), .{ .dir = self.init_opts.dir }, self.data().options.strip().override(.{ .expand = .both }));
    self.box.install();
    self.box.drawBackground();
}

pub fn close(self: *MenuWidget) void {
    dvui.refresh(null, @src(), self.data().id);
    self.close_chain(.intentional);
}

pub fn close_chain(self: *MenuWidget, reason: CloseReason) void {
    self.submenus_activated = false;
    // close all submenus in the chain
    if (self.parentMenu) |pm| {
        pm.close_chain(reason);
    } else {
        if (Root.current) |root| {
            root.close(root.ptr, reason);
        }
        if (reason == .intentional) {
            // when a popup is closed because the user chose to, the
            // window that spawned it (which had focus previously)
            // should become focused again
            dvui.focusSubwindow(self.parentSubwindowId, null);
        }
    }
}

pub fn widget(self: *MenuWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *MenuWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *MenuWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *MenuWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *MenuWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn processEvent(self: *MenuWidget, e: *Event) void {
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .position) {
                if (dvui.mouseTotalMotion().nonZero()) {
                    self.mouse_mode = true;
                    if (dvui.dataGet(null, self.data().id, "_child_popup", Rect.Physical)) |r| {
                        const center = Point.Physical{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
                        const cw = dvui.currentWindow();
                        const to_center = center.diff(cw.mouse_pt_prev);
                        const movement = cw.mouse_pt.diff(cw.mouse_pt_prev);
                        const dot_prod = movement.x * to_center.x + movement.y * to_center.y;
                        const cos = dot_prod / (to_center.length() * movement.length());
                        if (std.math.acos(cos) < std.math.pi / 3.0) {
                            // there is an existing submenu and motion is
                            // towards the popup, so eat this event to
                            // prevent any menu items from focusing
                            e.handle(@src(), self.data());
                        }
                    }

                    if (!e.handled) {
                        self.mouse_over = true;
                    }
                }
            }
        },
        else => {},
    }
}

pub fn processEventsAfter(self: *MenuWidget) void {
    const focus_id = dvui.lastFocusedIdInFrame(self.last_focus);

    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = self.data().id, .focus_id = focus_id, .r = self.data().borderRectScale().r }))
            continue;

        switch (e.evt) {
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .escape => {
                            self.mouse_mode = false;
                            e.handle(@src(), self.data());
                            self.close();
                        },
                        .up => {
                            self.mouse_mode = false;
                            if (self.init_opts.dir == .vertical) {
                                e.handle(@src(), self.data());
                                // TODO: don't do this if focus would move outside the menu
                                dvui.tabIndexPrev(e.num);
                            }
                        },
                        .down => {
                            self.mouse_mode = false;
                            if (self.init_opts.dir == .vertical) {
                                e.handle(@src(), self.data());
                                // TODO: don't do this if focus would move outside the menu
                                dvui.tabIndexNext(e.num);
                            }
                        },
                        .left => {
                            self.mouse_mode = false;
                            if (self.init_opts.dir == .vertical) {
                                e.handle(@src(), self.data());
                                if (self.parentMenu) |pm| {
                                    pm.submenus_activated = false;
                                    if (self.parentSubwindowId) |sid| {
                                        dvui.focusSubwindow(sid, null);
                                    }
                                }
                            } else {
                                e.handle(@src(), self.data());
                                // TODO: don't do this if focus would move outside the menu
                                dvui.tabIndexPrev(e.num);
                            }
                        },
                        .right => {
                            self.mouse_mode = false;
                            if (self.init_opts.dir == .horizontal) {
                                e.handle(@src(), self.data());
                                // TODO: don't do this if focus would move outside the menu
                                dvui.tabIndexNext(e.num);
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}

pub fn deinit(self: *MenuWidget) void {
    self.processEventsAfter();

    defer dvui.widgetFree(self);
    self.box.deinit();
    dvui.dataSet(null, self.data().id, "_mouse_mode", self.mouse_mode);
    dvui.dataSet(null, self.data().id, "_sub_act", self.submenus_activated);
    if (self.child_popup_rect) |r| {
        dvui.dataSet(null, self.data().id, "_child_popup", r);
    }
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    _ = menuSet(self.parentMenu);
    dvui.parentReset(self.data().id, self.data().parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
