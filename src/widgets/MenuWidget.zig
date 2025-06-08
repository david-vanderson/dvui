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
    dir: enums.Direction = undefined,
};

wd: WidgetData = undefined,

init_opts: InitOptions = undefined,
winId: dvui.WidgetId = undefined,
parentMenu: ?*MenuWidget = null,
parentSubwindowId: ?dvui.WidgetId = null,
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
    var self = MenuWidget{};
    const options = defaults.override(opts);
    self.wd = WidgetData.init(src, .{}, options);
    self.init_opts = init_opts;

    self.winId = dvui.subwindowCurrentId();
    if (dvui.dataGet(null, self.wd.id, "_sub_act", bool)) |a| {
        self.submenus_activated = a;
    } else if (current()) |pm| {
        self.submenus_activated = pm.submenus_in_child;
    }

    self.mouse_mode = dvui.dataGet(null, self.wd.id, "_mouse_mode", bool) orelse false;

    return self;
}

pub fn install(self: *MenuWidget) !void {
    dvui.parentSet(self.widget());
    self.parentMenu = menuSet(self);
    self.wd.register();
    try self.wd.borderAndBackground(.{});

    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatchSimple(e, self.data()))
            continue;

        self.processEvent(e, false);
    }

    self.box = BoxWidget.init(@src(), self.init_opts.dir, false, self.wd.options.strip().override(.{ .expand = .both }));
    try self.box.install();
    try self.box.drawBackground();
}

pub fn close(self: *MenuWidget) void {
    // bubble this event to close all popups that had submenus leading to this
    var e = Event{ .evt = .{ .close_popup = .{} } };
    self.processEvent(&e, true);
    dvui.refresh(null, @src(), self.wd.id);
}

pub fn widget(self: *MenuWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *MenuWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *MenuWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *MenuWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *MenuWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn processEvent(self: *MenuWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .position) {
                if (dvui.mouseTotalMotion().nonZero()) {
                    self.mouse_mode = true;
                    if (dvui.dataGet(null, self.wd.id, "_child_popup", Rect.Physical)) |r| {
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
        .key => |ke| {
            if (ke.action == .down or ke.action == .repeat) {
                switch (ke.code) {
                    .escape => {
                        self.mouse_mode = false;
                        e.handle(@src(), self.data());
                        var closeE = Event{ .evt = .{ .close_popup = .{} } };
                        self.processEvent(&closeE, true);
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
        .close_popup => {
            self.submenus_activated = false;
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *MenuWidget) void {
    self.box.deinit();
    dvui.dataSet(null, self.wd.id, "_mouse_mode", self.mouse_mode);
    dvui.dataSet(null, self.wd.id, "_sub_act", self.submenus_activated);
    if (self.child_popup_rect) |r| {
        dvui.dataSet(null, self.wd.id, "_child_popup", r);
    }
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    _ = menuSet(self.parentMenu);
    dvui.parentReset(self.wd.id, self.wd.parent);
}

test {
    @import("std").testing.refAllDecls(@This());
}
