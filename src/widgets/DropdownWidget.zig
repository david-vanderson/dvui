pub const DropdownWidget = @This();

options: Options = undefined,
init_options: InitOptions = undefined,
menu: MenuWidget = undefined,
menuItem: MenuItemWidget = undefined,
drop: ?FloatingMenuWidget = null,
drop_first_frame: bool = false,
drop_mi: ?MenuItemWidget = null,
drop_mi_index: usize = 0,
drop_height: f32 = 0,
drop_adjust: f32 = undefined,

pub var defaults: Options = .{
    .color_fill = .{ .name = .fill_control },
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(6),
    .background = true,
    .name = "Dropdown",
};

pub const InitOptions = struct {
    label: ?[]const u8 = null,
    selected_index: ?usize = null,
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) DropdownWidget {
    var self = DropdownWidget{};
    self.options = defaults.override(opts);
    self.init_options = init_opts;
    self.menu = MenuWidget.init(src, .{ .dir = .horizontal }, self.options.wrapOuter());
    self.drop_adjust = dvui.dataGet(null, self.menu.wd.id, "_drop_adjust", f32) orelse 0;
    return self;
}

pub fn install(self: *DropdownWidget) !void {
    try self.menu.install();

    self.menuItem = MenuItemWidget.init(@src(), .{ .submenu = true }, self.options.wrapInner());
    try self.menuItem.install();
    self.menuItem.processEvents();
    try self.menuItem.drawBackground(.{ .focus_as_outline = true });

    if (self.init_options.label) |ll| {
        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });

        var lw = LabelWidget.initNoFmt(@src(), ll, self.options.strip().override(.{ .gravity_y = 0.5 }));
        try lw.install();
        try lw.draw();
        lw.deinit();
        _ = try dvui.spacer(@src(), .{ .w = 6 }, .{});
        try dvui.icon(@src(), "dropdown_triangle", dvui.entypo.chevron_small_down, self.options.strip().override(.{ .gravity_y = 0.5, .gravity_x = 1.0 }));

        hbox.deinit();
    }
}

pub fn close(self: *DropdownWidget) void {
    self.menu.close();
}

pub fn dropped(self: *DropdownWidget) !bool {
    if (self.drop != null) {
        // protect against calling this multiple times
        return true;
    }

    if (self.menuItem.activeRect()) |r| {
        self.drop = FloatingMenuWidget.init(@src(), .{ .from = r, .avoid = .none }, .{ .min_size_content = r.size().cast(dvui.Size) });
        var drop = &self.drop.?;
        self.drop_first_frame = dvui.firstFrame(drop.wd.id);

        const s = drop.scale_val;

        // move drop up to align first item
        drop.init_options.from.x -= drop.options.borderGet().x * s;
        drop.init_options.from.x -= drop.options.paddingGet().x * s;
        drop.init_options.from.y -= drop.options.borderGet().y * s;
        drop.init_options.from.y -= drop.options.paddingGet().y * s;

        // move drop up so selected entry is aligned
        drop.init_options.from.y -= self.drop_adjust * s;

        try drop.install();

        // without this, if you trigger the dropdown with the keyboard and then
        // move the mouse, the entries are highlighted but not focused
        drop.menu.submenus_activated = true;

        // only want a mouse-up to choose something if the mouse has moved in the dropup
        var eat_mouse_up = dvui.dataGet(null, drop.wd.id, "_eat_mouse_up", bool) orelse true;
        var drag_scroll = dvui.dataGet(null, drop.wd.id, "_drag_scroll", bool) orelse false;

        const drop_rs = drop.data().rectScale();
        const scroll_rs = drop.scroll.data().contentRectScale();
        const evts = dvui.events();
        for (evts) |*e| {
            if (drag_scroll and e.evt == .mouse and !e.evt.mouse.button.touch() and (e.evt.mouse.action == .motion or e.evt.mouse.action == .position)) {
                if (e.evt.mouse.p.x >= scroll_rs.r.x and e.evt.mouse.p.x <= scroll_rs.r.x + scroll_rs.r.w and (e.evt.mouse.p.y <= scroll_rs.r.y or e.evt.mouse.p.y >= scroll_rs.r.y + scroll_rs.r.h)) {
                    if (e.evt.mouse.action == .motion) {
                        var scrolldrag = Event{ .evt = .{ .scroll_drag = .{
                            .mouse_pt = e.evt.mouse.p,
                            .screen_rect = drop.menu.data().rectScale().r,
                            .capture_id = drop.wd.id,
                        } } };
                        drop.scroll.scroll.processEvent(&scrolldrag, true);
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
                        e.handled = true;
                        eat_mouse_up = false;
                        dvui.dataSet(null, drop.wd.id, "_eat_mouse_up", eat_mouse_up);
                    }
                } else if (e.evt.mouse.action == .motion or (e.evt.mouse.action == .press and e.evt.mouse.button.pointer())) {
                    if (eat_mouse_up) {
                        eat_mouse_up = false;
                        dvui.dataSet(null, drop.wd.id, "_eat_mouse_up", eat_mouse_up);
                    }

                    if (!drag_scroll) {
                        drag_scroll = true;
                        dvui.dataSet(null, drop.wd.id, "_drag_scroll", drag_scroll);
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

pub fn addChoiceLabel(self: *DropdownWidget, label_text: []const u8) !bool {
    var mi = try self.addChoice();
    defer mi.deinit();

    var opts = self.options.strip();
    if (mi.show_active) {
        opts = opts.override(dvui.themeGet().style_accent);
    }

    try dvui.labelNoFmt(@src(), label_text, opts);

    if (mi.activeRect()) |_| {
        self.close();
        return true;
    }

    return false;
}

pub fn addChoice(self: *DropdownWidget) !*MenuItemWidget {
    // record how far down in our parent we would be
    if (self.drop_mi) |*mi| {
        self.drop_height += mi.data().min_size.h;
    }

    self.drop_mi = MenuItemWidget.init(@src(), .{}, .{ .id_extra = self.drop_mi_index, .expand = .horizontal });
    try self.drop_mi.?.install();
    self.drop_mi.?.processEvents();
    try self.drop_mi.?.drawBackground(.{});

    if (self.drop_first_frame) {
        if (self.init_options.selected_index) |si| {
            if (si == self.drop_mi_index) {
                dvui.focusWidgetSelf(self.drop_mi.?.wd.id, null);
                dvui.dataSet(null, self.menu.wd.id, "_drop_adjust", self.drop_height);
            }
        }
    }
    self.drop_mi_index += 1;

    return &self.drop_mi.?;
}

pub fn deinit(self: *DropdownWidget) void {
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

const MenuWidget = dvui.MenuWidget;
const MenuItemWidget = dvui.MenuItemWidget;
const FloatingMenuWidget = dvui.FloatingMenuWidget;
const LabelWidget = dvui.LabelWidget;

const std = @import("std");
const dvui = @import("../dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
