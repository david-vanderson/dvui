const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const MenuItemWidget = @This();

pub var defaults: Options = .{
    .name = "MenuItem",
    .corner_radius = Rect.all(5),
    .padding = Rect.all(4),
};

pub const InitOptions = struct {
    submenu: bool = false,
};

wd: WidgetData = undefined,
focused_last_frame: bool = undefined,
highlight: bool = false,
init_opts: InitOptions = undefined,
activated: bool = false,
show_active: bool = false,
mouse_over: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) MenuItemWidget {
    var self = MenuItemWidget{};
    const options = defaults.override(opts);
    self.wd = WidgetData.init(src, .{}, options);
    self.init_opts = init_opts;
    self.focused_last_frame = dvui.dataGet(null, self.wd.id, "_focus_last", bool) orelse false;
    return self;
}

pub fn install(self: *MenuItemWidget) !void {
    try self.wd.register();

    // For most widgets we only tabIndexSet if they are visible, but menu
    // items are often in large dropdowns that are scrollable, plus the
    // up/down arrow keys get used to move between menu items, so you need
    // to be able to move to the next menu item even if it's not visible
    try dvui.tabIndexSet(self.wd.id, self.wd.options.tab_index);

    try self.wd.borderAndBackground(.{});

    dvui.parentSet(self.widget());
}

pub fn drawBackground(self: *MenuItemWidget, opts: struct { focus_as_outline: bool = false }) !void {
    var focused: bool = false;
    if (self.wd.id == dvui.focusedWidgetId()) {
        focused = true;
    }

    if (focused and dvui.menuGet().?.mouse_over and !self.mouse_over) {
        // our menu got a mouse over but we didn't even though we were focused
        focused = false;
        dvui.focusWidget(null, null, null);
    }

    if (focused or ((self.wd.id == dvui.focusedWidgetIdInCurrentSubwindow()) and self.highlight)) {
        if (!self.init_opts.submenu or !dvui.menuGet().?.submenus_activated) {
            self.show_active = true;

            if (!self.focused_last_frame) {
                // in case we are in a scrollable dropdown, scroll
                var scrollto = Event{ .evt = .{ .scroll_to = .{ .screen_rect = self.wd.borderRectScale().r } } };
                self.wd.parent.processEvent(&scrollto, true);
            }
        }
    }

    self.focused_last_frame = focused;

    if (self.show_active) {
        if (opts.focus_as_outline) {
            try self.wd.focusBorder();
        } else {
            const rs = self.wd.backgroundRectScale();
            try dvui.pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
            try dvui.pathFillConvex(self.wd.options.color(.accent));
        }
    } else if ((self.wd.id == dvui.focusedWidgetIdInCurrentSubwindow()) or self.highlight) {
        const rs = self.wd.backgroundRectScale();
        try dvui.pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
        try dvui.pathFillConvex(self.wd.options.color(.fill_hover));
    } else if (self.wd.options.backgroundGet()) {
        const rs = self.wd.backgroundRectScale();
        try dvui.pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
        try dvui.pathFillConvex(self.wd.options.color(.fill));
    }
}

pub fn matchEvent(self: *MenuItemWidget, e: *Event) bool {
    return dvui.eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r });
}

pub fn processEvents(self: *MenuItemWidget) void {
    var evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn activeRect(self: *const MenuItemWidget) ?Rect {
    var act = false;
    if (self.init_opts.submenu) {
        if (dvui.menuGet().?.submenus_activated and (self.wd.id == dvui.focusedWidgetIdInCurrentSubwindow())) {
            act = true;
        }
    } else if (self.activated) {
        act = true;
    }

    if (act) {
        const rs = self.wd.backgroundRectScale();
        return rs.r.scale(1 / dvui.windowNaturalScale());
    } else {
        return null;
    }
}

pub fn widget(self: *MenuItemWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *MenuItemWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *MenuItemWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
}

pub fn screenRectScale(self: *MenuItemWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *MenuItemWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.padSize(s));
}

pub fn processEvent(self: *MenuItemWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus) {
                e.handled = true;
                dvui.focusWidget(self.wd.id, null, e.num);
            } else if (me.action == .press and me.button.pointer()) {
                // this is how dropdowns are triggered
                e.handled = true;
                if (self.init_opts.submenu) {
                    dvui.menuGet().?.submenus_activated = true;
                    dvui.menuGet().?.submenus_in_child = true;
                }
            } else if (me.action == .release) {
                e.handled = true;
                if (!self.init_opts.submenu and (self.wd.id == dvui.focusedWidgetIdInCurrentSubwindow())) {
                    self.activated = true;
                    dvui.refresh(null, @src(), self.wd.id);
                }
            } else if (me.action == .position) {
                e.handled = true;

                // We get a .position mouse event every frame.  If we
                // focus the menu item under the mouse even if it's not
                // moving then it breaks keyboard navigation.
                if (dvui.mouseTotalMotion().nonZero()) {
                    self.highlight = true;
                    self.mouse_over = true;
                    if (dvui.menuGet().?.submenus_activated) {
                        // we shouldn't have gotten this event if the motion
                        // was towards a submenu (caught in MenuWidget)
                        dvui.focusSubwindow(null, null); // focuses the window we are in
                        dvui.focusWidget(self.wd.id, null, null);

                        if (self.init_opts.submenu) {
                            dvui.menuGet().?.submenus_in_child = true;
                        }
                    }
                }
            }
        },
        .key => |ke| {
            if (ke.code == .space and ke.action == .down) {
                e.handled = true;
                if (self.init_opts.submenu) {
                    dvui.menuGet().?.submenus_activated = true;
                } else {
                    self.activated = true;
                    dvui.refresh(null, @src(), self.wd.id);
                }
            } else if (ke.code == .right and ke.action == .down) {
                if (self.init_opts.submenu and dvui.menuGet().?.init_opts.dir == .vertical) {
                    e.handled = true;
                    dvui.menuGet().?.submenus_activated = true;
                }
            } else if (ke.code == .down and ke.action == .down) {
                if (self.init_opts.submenu and dvui.menuGet().?.init_opts.dir == .horizontal) {
                    e.handled = true;
                    dvui.menuGet().?.submenus_activated = true;
                }
            }
        },
        else => {},
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *MenuItemWidget) void {
    dvui.dataSet(null, self.wd.id, "_focus_last", self.focused_last_frame);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}
