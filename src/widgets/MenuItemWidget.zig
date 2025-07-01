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
    .padding = Rect.all(6),
};

pub const InitOptions = struct {
    submenu: bool = false,
    highlight_only: bool = false,
};

wd: WidgetData,
focused_last_frame: bool,
highlight: bool = false,
init_opts: InitOptions,
activated: bool = false,
show_active: bool = false,
mouse_over: bool = false,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) MenuItemWidget {
    const options = defaults.override(opts);
    const wd = WidgetData.init(src, .{}, options);
    return .{
        .wd = wd,
        .init_opts = init_opts,
        .focused_last_frame = dvui.dataGet(null, wd.id, "_focus_last", bool) orelse false,
    };
}

pub fn install(self: *MenuItemWidget) void {
    self.data().register();

    dvui.tabIndexSet(self.data().id, self.data().options.tab_index);

    self.data().borderAndBackground(.{});

    dvui.parentSet(self.widget());
}

pub fn drawBackground(self: *MenuItemWidget, opts: struct { focus_as_outline: bool = false }) void {
    var focused: bool = false;
    if (self.data().id == dvui.focusedWidgetId()) {
        focused = true;
    }

    if (focused and dvui.MenuWidget.current().?.mouse_over and !self.mouse_over) {
        // our menu got a mouse over but we didn't even though we were focused
        focused = false;
        dvui.focusWidget(null, null, null);
    }

    if (focused or ((self.data().id == dvui.focusedWidgetIdInCurrentSubwindow()) and self.highlight)) {
        if (!self.init_opts.submenu or !dvui.MenuWidget.current().?.submenus_activated) {
            if (!self.init_opts.highlight_only) {
                self.show_active = true;
            }

            if (!self.focused_last_frame) {
                // in case we are in a scrollable dropdown, scroll
                dvui.scrollTo(.{ .screen_rect = self.data().borderRectScale().r });
            }
        }
    }

    self.focused_last_frame = focused;

    if (self.data().visible()) {
        if (self.show_active) {
            if (opts.focus_as_outline) {
                self.data().focusBorder();
            } else {
                const rs = self.data().backgroundRectScale();
                rs.r.fill(self.data().options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = self.data().options.color(.accent) });
            }
        } else if ((self.data().id == dvui.focusedWidgetIdInCurrentSubwindow()) or self.highlight) {
            const rs = self.data().backgroundRectScale();
            rs.r.fill(self.data().options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = self.data().options.color(.fill_hover) });
        } else if (self.data().options.backgroundGet()) {
            const rs = self.data().backgroundRectScale();
            rs.r.fill(self.data().options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = self.data().options.color(.fill) });
        }
    }
}

pub fn matchEvent(self: *MenuItemWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *MenuItemWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e);
    }
}

pub fn activeRect(self: *const MenuItemWidget) ?Rect.Natural {
    var act = false;
    if (self.init_opts.submenu) {
        if (dvui.MenuWidget.current().?.submenus_activated and (self.data().id == dvui.focusedWidgetIdInCurrentSubwindow())) {
            act = true;
        }
    } else if (self.activated) {
        act = true;
    }

    if (act) {
        return self.data().backgroundRectScale().r.toNatural();
    } else {
        return null;
    }
}

pub fn widget(self: *MenuItemWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *const MenuItemWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *MenuItemWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *MenuItemWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *MenuItemWidget, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub fn processEvent(self: *MenuItemWidget, e: *Event) void {
    switch (e.evt) {
        .mouse => |me| {
            if (me.action == .focus) {
                dvui.MenuWidget.current().?.mouse_mode = true;
                e.handle(@src(), self.data());
                dvui.focusWidget(self.data().id, null, e.num);
            } else if (me.action == .press and me.button.pointer()) {
                // This works differently than normal (like buttons) where we
                // captureMouse on press, to support the mouse
                // click-open-drag-select-release-activate pattern for menus
                // and dropdowns.  However, we still need to do the capture
                // pattern for touch.
                //
                // This is how dropdowns are triggered.
                e.handle(@src(), self.data());
                if (self.init_opts.submenu) {
                    dvui.MenuWidget.current().?.submenus_activated = true;
                    dvui.MenuWidget.current().?.submenus_in_child = true;
                }

                if (me.button.touch()) {
                    // with touch we have to capture otherwise any motion will
                    // cause scroll to capture
                    dvui.captureMouse(self.data());
                    dvui.dragPreStart(me.p, .{});
                }
            } else if (me.action == .release) {
                dvui.MenuWidget.current().?.mouse_mode = true;
                e.handle(@src(), self.data());
                if (!self.init_opts.submenu and (self.data().id == dvui.focusedWidgetIdInCurrentSubwindow())) {
                    self.activated = true;
                    dvui.refresh(null, @src(), self.data().id);
                }
                if (dvui.captured(self.data().id)) {
                    // should only happen with touch
                    dvui.captureMouse(null);
                    dvui.dragEnd();
                }
            } else if (me.action == .motion and me.button.touch()) {
                if (dvui.captured(self.data().id)) {
                    if (dvui.dragging(me.p)) |_| {
                        // if we overcame the drag threshold, then that
                        // means the person probably didn't want to touch
                        // this, maybe they were trying to scroll
                        dvui.captureMouse(null);
                        dvui.dragEnd();
                    }
                }
            } else if (me.action == .position) {
                if (dvui.MenuWidget.current().?.mouse_mode) {
                    dvui.cursorSet(.arrow);
                    self.highlight = true;
                }

                // We get a .position mouse event every frame.  If we
                // focus the menu item under the mouse even if it's not
                // moving then it breaks keyboard navigation.
                if (dvui.mouseTotalMotion().nonZero()) {
                    dvui.MenuWidget.current().?.mouse_mode = true;
                    self.mouse_over = true;
                    // we shouldn't have gotten this event if the motion
                    // was towards a submenu (caught in MenuWidget)
                    dvui.focusSubwindow(null, null); // focuses the window we are in
                    dvui.focusWidget(self.data().id, null, null);

                    if (self.init_opts.submenu) {
                        dvui.MenuWidget.current().?.submenus_in_child = true;
                    }
                }
            }
        },
        .key => |ke| {
            if (ke.action == .down and ke.matchBind("activate")) {
                dvui.MenuWidget.current().?.mouse_mode = false;
                e.handle(@src(), self.data());
                if (self.init_opts.submenu) {
                    dvui.MenuWidget.current().?.submenus_activated = true;
                } else {
                    self.activated = true;
                    dvui.refresh(null, @src(), self.data().id);
                }
            } else if (ke.code == .right and ke.action == .down) {
                if (self.init_opts.submenu and dvui.MenuWidget.current().?.init_opts.dir == .vertical) {
                    dvui.MenuWidget.current().?.mouse_mode = false;
                    e.handle(@src(), self.data());
                    dvui.MenuWidget.current().?.submenus_activated = true;
                }
            } else if (ke.code == .down and ke.action == .down) {
                if (self.init_opts.submenu and dvui.MenuWidget.current().?.init_opts.dir == .horizontal) {
                    dvui.MenuWidget.current().?.mouse_mode = false;
                    e.handle(@src(), self.data());
                    dvui.MenuWidget.current().?.submenus_activated = true;
                }
            }
        },
        else => {},
    }
}

pub fn deinit(self: *MenuItemWidget) void {
    defer dvui.widgetFree(self);
    dvui.dataSet(null, self.data().id, "_focus_last", self.focused_last_frame);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "menuItem click sets last_focused_id_this_frame" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fns = struct {
        var last_focused_id_set: dvui.WidgetId = .zero;

        fn frame() !dvui.App.Result {
            var m = dvui.menu(@src(), .vertical, .{ .padding = .all(10), .tag = "menu" });
            defer m.deinit();

            const last_focused = dvui.lastFocusedIdInFrame(null);

            if (dvui.menuItemLabel(@src(), "item 1", .{}, .{ .tag = "item 1" })) |_| {
                dvui.focusWidget(m.data().id, null, null);
            }
            _ = dvui.menuItemLabel(@src(), "item 2", .{}, .{ .tag = "item 2" });

            last_focused_id_set = dvui.lastFocusedIdInFrame(last_focused);

            return .ok;
        }
    };

    try dvui.testing.settle(fns.frame);

    // clicking on item 2 should tell us that it got focus this frame
    try dvui.testing.moveTo("item 2");
    try dvui.testing.click(.left);
    _ = try dvui.testing.step(fns.frame);
    try std.testing.expect(fns.last_focused_id_set == dvui.tagGet("item 2").?.id);
    try dvui.testing.expectFocused("item 2");

    // clicking on item 1 should tell us that menu got focus this frame
    try dvui.testing.moveTo("item 1");
    try dvui.testing.click(.left);
    _ = try dvui.testing.step(fns.frame);
    try std.testing.expect(fns.last_focused_id_set == dvui.tagGet("menu").?.id);
    try dvui.testing.expectFocused("menu");
}
