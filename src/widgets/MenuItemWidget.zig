const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

/// The parent menu of this item
const menu = dvui.MenuWidget.current;

const MenuItemWidget = @This();

pub var defaults: Options = .{
    .name = "MenuItem",
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
    .style = .control,
};

pub const InitOptions = struct {
    submenu: bool = false,
    highlight_only: bool = false,
    focus_as_outline: bool = false,
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

pub fn drawBackground(self: *MenuItemWidget) void {
    var focused: bool = false;
    if (self.data().id == dvui.focusedWidgetId()) {
        focused = true;
    }

    if (focused and menu().?.mouse_over and !self.mouse_over and (menu().?.submenus_activated or menu().?.floating())) {
        // our menu got a mouse over but we didn't even though we were focused
        focused = false;
        dvui.focusWidget(menu().?.data().id, null, null);
    }

    if (focused or ((self.data().id == dvui.focusedWidgetIdInCurrentSubwindow()) and self.highlight)) {
        if (!self.init_opts.submenu or !menu().?.submenus_activated) {
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
        const cols = self.colors();
        const rs = self.data().backgroundRectScale();
        const cr = self.data().options.corner_radiusGet().scale(rs.s, Rect.Physical);
        if (self.show_active) {
            if (self.init_opts.focus_as_outline) {
                self.data().focusBorder();
                if (self.highlight) {
                    rs.r.fill(cr, .{ .color = cols.color(.fill), .fade = 1.0 });
                }
            } else {
                rs.r.fill(cr, .{ .color = cols.color(.fill), .fade = 1.0 });
            }
        } else if ((self.data().id == dvui.focusedWidgetIdInCurrentSubwindow()) or self.highlight) {
            rs.r.fill(cr, .{ .color = cols.color(.fill), .fade = 1.0 });
        } else if (self.data().options.backgroundGet()) {
            rs.r.fill(cr, .{ .color = cols.color(.fill), .fade = 1.0 });
        }
    }
}

/// Returns an `Options` struct with color/style overrides for the hover and press state
pub fn colors(self: *MenuItemWidget) Options {
    var opts: Options = .{ .style = self.data().options.style };
    if (self.show_active and !self.init_opts.focus_as_outline) {
        opts.style = .highlight;
    } else if (self.highlight or (self.data().id == dvui.focusedWidgetIdInCurrentSubwindow())) {
        opts.color_fill = self.data().options.color(.fill_hover);
        opts.color_text = self.data().options.color(.text_hover);
    }
    return opts;
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
        if (menu().?.submenus_activated and (self.data().id == dvui.focusedWidgetIdInCurrentSubwindow())) {
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

pub fn rectFor(self: *MenuItemWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
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
                menu().?.mouse_mode = true;
                e.handle(@src(), self.data());
                self.mouse_over = true;
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
                    dvui.dataRemove(null, menu().?.data().id, "_submenus_activating");
                    if (!menu().?.floating() and !menu().?.submenus_activated) {
                        // If not floating, then we are toggling focus-on-hover, set a bit
                        dvui.dataSet(null, menu().?.data().id, "_submenus_activating", {});
                    }
                    menu().?.submenus_activated = true;
                }

                if (me.button.touch()) {
                    // with touch we have to capture otherwise any motion will
                    // cause scroll to capture
                    dvui.captureMouse(self.data(), e.num);
                    dvui.dragPreStart(me.p, .{});
                }
            } else if (me.action == .release) {
                menu().?.mouse_mode = true;
                e.handle(@src(), self.data());
                if (self.init_opts.submenu) {
                    // Only non floating menus can toggle focus-on-hover
                    if (!menu().?.floating() and dvui.dataGet(null, menu().?.data().id, "_submenus_activating", void) == null) {
                        // Toggle the submenu closed
                        menu().?.submenus_activated = false;
                        dvui.refresh(null, @src(), self.data().id);
                    }
                } else if (self.data().id == dvui.focusedWidgetIdInCurrentSubwindow()) {
                    self.activated = true;
                    dvui.refresh(null, @src(), self.data().id);
                }

                if (dvui.captured(self.data().id)) {
                    // should only happen with touch
                    dvui.captureMouse(null, e.num);
                }
                dvui.dragEnd();
            } else if (me.action == .motion and me.button.touch()) {
                if (dvui.captured(self.data().id)) {
                    if (dvui.dragging(me.p, null)) |_| {
                        // if we overcame the drag threshold, then that
                        // means the person probably didn't want to touch
                        // this, maybe they were trying to scroll
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                    }
                }
            } else if (me.action == .position) {
                // We get a .position mouse event every frame.  If we
                // focus the menu item under the mouse even if it's not
                // moving then it breaks keyboard navigation.
                if (dvui.mouseTotalMotion().nonZero()) {
                    menu().?.mouse_mode = true;
                    self.mouse_over = true;

                    if (menu().?.has_focused_child or menu().?.submenus_activated or menu().?.floating()) {
                        // we shouldn't have gotten this event if the motion
                        // was towards a submenu (caught in MenuWidget)
                        dvui.focusSubwindow(null, null); // focuses the window we are in
                        dvui.focusWidget(self.data().id, null, null);

                        if (self.init_opts.submenu and menu().?.floating()) {
                            menu().?.submenus_activated = true;
                        }
                    }
                }

                if (menu().?.mouse_mode) {
                    dvui.cursorSet(.arrow);
                    self.highlight = true;
                }
            }
        },
        .key => |ke| {
            if (ke.action == .down and ke.matchBind("activate")) {
                menu().?.mouse_mode = false;
                e.handle(@src(), self.data());
                if (self.init_opts.submenu) {
                    menu().?.submenus_activated = true;
                } else {
                    self.activated = true;
                    dvui.refresh(null, @src(), self.data().id);
                }
            } else if (ke.code == .right and ke.action == .down) {
                if (self.init_opts.submenu and menu().?.init_opts.dir == .vertical) {
                    menu().?.mouse_mode = false;
                    e.handle(@src(), self.data());
                    menu().?.submenus_activated = true;
                }
            } else if (ke.code == .down and ke.action == .down) {
                if (self.init_opts.submenu and menu().?.init_opts.dir == .horizontal) {
                    menu().?.mouse_mode = false;
                    e.handle(@src(), self.data());
                    menu().?.submenus_activated = true;
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
        var last_focused_id_set: ?dvui.Id = null;

        fn frame() !dvui.App.Result {
            var m = dvui.menu(@src(), .vertical, .{ .padding = .all(10), .tag = "menu" });
            defer m.deinit();

            const last_focused = dvui.lastFocusedIdInFrame();

            if (dvui.menuItemLabel(@src(), "item 1", .{}, .{ .tag = "item 1" })) |_| {
                dvui.focusWidget(m.data().id, null, null);
            }
            _ = dvui.menuItemLabel(@src(), "item 2", .{}, .{ .tag = "item 2" });

            last_focused_id_set = dvui.lastFocusedIdInFrameSince(last_focused);

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
