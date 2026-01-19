pub const DropdownWidget = @This();

options: Options,
init_options: InitOptions,
menu: MenuWidget,
menuItem: MenuItemWidget,
drop: ?FloatingMenuWidget = null,
drop_first_frame: bool = false,
/// SAFETY: Will always be set by `addChoice` before use
drop_mi: MenuItemWidget = undefined,
drop_mi_id: ?dvui.Id = null,
drop_mi_index: usize = 0,
drop_height: f32 = 0,
drop_adjust: f32 = 0,

pub var defaults: Options = .{
    .name = "Dropdown",
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
    .background = true,
    .style = .control,
};

pub const InitOptions = struct {
    label: ?[]const u8 = null,
    selected_index: ?usize = null,
    was_allocated_on_widget_stack: bool = false,
};

pub fn wrapOuter(opts: Options) Options {
    var ret = opts;
    ret.tab_index = null;
    ret.border = Rect{};
    ret.padding = Rect{};
    ret.background = false;
    ret.role = .none;
    ret.label = null;
    return ret;
}

pub fn wrapInner(opts: Options) Options {
    return opts.strip().override(.{
        .role = .combo_box,
        .tab_index = opts.tab_index,
        .border = opts.border,
        .padding = opts.padding,
        .corner_radius = opts.corner_radius,
        .background = opts.background,
        .expand = .both,
        .label = opts.label orelse .{ .label_widget = .next },
    });
}

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *DropdownWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    const options = defaults.themeOverride(opts.theme).override(opts);
    self.* = .{
        .options = options,
        .init_options = init_opts,
        // SAFETY: Set bellow
        .menu = undefined,
        // SAFETY: Set bellow
        .menuItem = undefined,
    };
    self.menu.init(src, .{ .dir = .horizontal }, wrapOuter(options));

    self.menuItem.init(@src(), .{ .submenu = true, .focus_as_outline = true }, wrapInner(self.options));
    self.menuItem.processEvents();
    self.menuItem.drawBackground();

    if (dvui.dataGet(null, self.data().id, "_drop_adjust", f32)) |adjust| self.drop_adjust = adjust;

    if (self.init_options.label) |ll| {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });
        defer hbox.deinit();

        var lw: LabelWidget = undefined;
        lw.initNoFmt(@src(), ll, .{}, self.options.strip().override(.{ .gravity_y = 0.5 }));
        lw.draw();
        lw.deinit();
        _ = dvui.spacer(@src(), .{ .min_size_content = .width(6) });
        dvui.icon(
            @src(),
            "dropdown_triangle",
            dvui.entypo.chevron_small_down,
            .{},
            self.options.strip().override(.{ .gravity_y = 0.5, .gravity_x = 1.0, .role = .none }),
        );
    }
    if (self.menuItem.data().accesskit_node()) |ak_node| {
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.focus);
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.click);
        //TODO: Potential case for supporting expand.
        //AccessKit.nodeAddAction(ak_node, AccessKit.Action.expand);
    }
}

pub fn data(self: *DropdownWidget) *WidgetData {
    return self.menu.data();
}

pub fn close(self: *DropdownWidget) void {
    self.menu.close();
}

pub fn dropped(self: *DropdownWidget) bool {
    if (self.drop != null) {
        // protect against calling this multiple times
        return true;
    }

    if (self.menuItem.activeRect()) |r| {
        var from = r;
        const s = dvui.parentGet().screenRectScale(Rect{}).s / dvui.windowNaturalScale();

        // move drop up-left to align first item
        const menuDefaults = dvui.FloatingMenuWidget.defaults;
        from.x -= menuDefaults.borderGet().x * s;
        from.x -= menuDefaults.paddingGet().x * s;
        from.y -= menuDefaults.borderGet().y * s;
        from.y -= menuDefaults.paddingGet().y * s;

        // move drop up so selected entry is aligned
        from.y -= self.drop_adjust * s;

        self.drop = @as(FloatingMenuWidget, undefined); // Needs to be a non-null value so `.?` bellow doesn't panic
        var drop = &self.drop.?;
        drop.init(@src(), .{ .from = from, .avoid = .none }, .{ .role = .none, .min_size_content = .cast(r.size()) });

        self.drop_first_frame = dvui.firstFrame(drop.data().id);

        // without this, if you trigger the dropdown with the keyboard and then
        // move the mouse, the entries are highlighted but not focused
        drop.menu.submenus_activated = true;

        // only want a mouse-up to choose something if the mouse has moved in the dropup
        var eat_mouse_up = dvui.dataGet(null, drop.data().id, "_eat_mouse_up", bool) orelse true;
        var drag_scroll = dvui.dataGet(null, drop.data().id, "_drag_scroll", bool) orelse false;

        const drop_rs = drop.data().rectScale();
        const scroll_rs = drop.scroll.data().contentRectScale();
        const evts = dvui.events();
        for (evts) |*e| {
            if (drag_scroll and e.evt == .mouse and !e.evt.mouse.button.touch() and (e.evt.mouse.action == .motion or e.evt.mouse.action == .position)) {
                if (e.evt.mouse.p.x >= scroll_rs.r.x and e.evt.mouse.p.x <= scroll_rs.r.x + scroll_rs.r.w and (e.evt.mouse.p.y <= scroll_rs.r.y or e.evt.mouse.p.y >= scroll_rs.r.y + scroll_rs.r.h)) {
                    if (e.evt.mouse.action == .motion) {
                        dvui.scrollDrag(.{
                            .mouse_pt = e.evt.mouse.p,
                            .screen_rect = drop.menu.data().rectScale().r,
                        });
                    } else if (e.evt.mouse.action == .position) {
                        dvui.currentWindow().inject_motion_event = true;
                    }
                }
            }

            if (!dvui.eventMatch(e, .{ .id = drop.data().id, .r = drop_rs.r }))
                continue;

            if (e.evt == .mouse) {
                if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                    if (eat_mouse_up) {
                        e.handle(@src(), drop.data());
                        eat_mouse_up = false;
                        dvui.dataSet(null, drop.data().id, "_eat_mouse_up", eat_mouse_up);
                    }
                } else if (e.evt.mouse.action == .motion or (e.evt.mouse.action == .press and e.evt.mouse.button.pointer())) {
                    if (eat_mouse_up) {
                        eat_mouse_up = false;
                        dvui.dataSet(null, drop.data().id, "_eat_mouse_up", eat_mouse_up);
                    }

                    if (!drag_scroll) {
                        drag_scroll = true;
                        dvui.dataSet(null, drop.data().id, "_drag_scroll", drag_scroll);
                    }
                }
            }
        }
    }

    if (self.drop != null) {
        return true;
    }

    return false;
}

pub fn addChoiceLabel(self: *DropdownWidget, label_text: []const u8) bool {
    var mi = self.addChoice();
    defer mi.deinit();

    dvui.labelNoFmt(@src(), label_text, .{}, mi.data().options.strip().override(mi.style()));

    if (mi.activeRect()) |_| {
        self.close();
        return true;
    }

    return false;
}

pub fn addChoice(self: *DropdownWidget) *MenuItemWidget {
    // record how far down in our parent we would be
    if (self.drop_mi_id) |mid| {
        if (dvui.minSizeGet(mid)) |ms| {
            self.drop_height += ms.h;
        }
    }

    self.drop_mi.init(@src(), .{}, self.options.styleOnly().override(.{
        .role = .list_item,
        .label = .{ .label_widget = .next },
        .id_extra = self.drop_mi_index,
        .expand = .horizontal,
    }));
    self.drop_mi_id = self.drop_mi.data().id;
    self.drop_mi.processEvents();
    self.drop_mi.drawBackground();

    if (self.drop_first_frame) {
        if (self.init_options.selected_index) |si| {
            if (si == self.drop_mi_index) {
                dvui.focusWidget(self.drop_mi.data().id, null, null);
                dvui.dataSet(null, self.data().id, "_drop_adjust", self.drop_height);
            }
        } else if (self.drop_mi_index == 0) {
            dvui.focusWidget(self.drop_mi.data().id, null, null);
        }
    }
    self.drop_mi_index += 1;

    return &self.drop_mi;
}

pub fn deinit(self: *DropdownWidget) void {
    const should_free = self.init_options.was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.drop != null) {
        self.drop.?.deinit();
        self.drop = null;
    }
    self.menuItem.deinit();
    self.menu.deinit();
}

const Options = dvui.Options;
const Rect = dvui.Rect;
const Event = dvui.Event;
const WidgetData = dvui.WidgetData;
const AccessKit = dvui.AccessKit;

const MenuWidget = dvui.MenuWidget;
const MenuItemWidget = dvui.MenuItemWidget;
const FloatingMenuWidget = dvui.FloatingMenuWidget;
const LabelWidget = dvui.LabelWidget;
const std = @import("std");
const dvui = @import("../dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
