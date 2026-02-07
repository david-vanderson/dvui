pub const SuggestionWidget = @This();

/// Is for the floating menu widget that might open
options: Options,
init_options: InitOptions,

menu: MenuWidget,
drop: ?*FloatingMenuWidget = null,
drop_mi: ?MenuItemWidget = null,
drop_mi_index: usize = 0,
selected_index: usize = 0, // 0 indexed
activate_selected: bool = false,

pub var defaults: Options = .{
    .role = .suggestion,
    .name = "Suggestions",
};

pub const InitOptions = struct {
    rs: RectScale,
    text_entry_id: dvui.Id,
};

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *SuggestionWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    self.* = .{
        .options = defaults.override(opts),
        .init_options = init_opts,
        // SAFETY: Set bellow
        .selected_index = undefined,
        // SAFETY: Set bellow
        .menu = undefined,
    };
    self.menu.init(src, .{ .dir = .horizontal, .close_without_focused_child = false }, .{ .role = .none, .rect = .{}, .id_extra = self.options.idExtra(), .name = "Suggestions Menu" });
    self.selected_index = dvui.dataGet(null, self.menu.data().id, "_selected", usize) orelse 0;
}

// Use this to see if dropped will return true without installing the
// floatingMenu which changes the current subwindow
pub fn willOpen(self: *SuggestionWidget) bool {
    return self.menu.submenus_activated;
}

pub fn open(self: *SuggestionWidget) void {
    self.menu.submenus_activated = true;
}

pub fn close(self: *SuggestionWidget) void {
    self.menu.submenus_activated = false;
}

pub fn dropped(self: *SuggestionWidget) bool {
    if (self.drop != null) {
        // protect against calling this multiple times
        return true;
    }

    if (self.menu.submenus_activated) {
        self.drop = dvui.floatingMenu(@src(), .{ .from = self.init_options.rs.r.toNatural() }, self.options);
        if (dvui.firstFrame(self.drop.?.data().id)) {
            // don't take focus away from text_entry when showing the suggestions
            dvui.focusWidget(self.init_options.text_entry_id, null, null);
        }
    }

    if (self.drop != null) {
        return true;
    }

    return false;
}

pub fn addChoiceLabel(self: *SuggestionWidget, label_str: []const u8) bool {
    var mi = self.addChoice();

    dvui.labelNoFmt(@src(), label_str, .{}, .{});

    var ret: bool = false;
    if (mi.activeRect()) |_| {
        self.close();
        ret = true;
    }

    mi.deinit();

    return ret;
}

pub fn addChoice(self: *SuggestionWidget) *MenuItemWidget {
    self.drop_mi = @as(MenuItemWidget, undefined); // Must be a non-null value for the `.?` bellow
    self.drop_mi.?.init(@src(), .{ .highlight_only = true }, .{
        .role = .list_item,
        .label = .{ .label_widget = .next },
        .id_extra = self.drop_mi_index,
        .expand = .horizontal,
        .padding = .{},
    });
    self.drop_mi.?.processEvents();
    if (self.drop_mi.?.data().id == dvui.focusedWidgetId()) {
        self.selected_index = self.drop_mi_index;
    }
    if (self.selected_index == self.drop_mi_index) {
        if (self.activate_selected) {
            self.drop_mi.?.activated = true;
            self.drop_mi.?.show_active = true;
        } else {
            self.drop_mi.?.highlight = true;
        }
    }
    self.drop_mi.?.drawBackground();

    self.drop_mi_index += 1;

    return &self.drop_mi.?;
}

pub fn deinit(self: *SuggestionWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.selected_index > (self.drop_mi_index -| 1)) {
        self.selected_index = self.drop_mi_index -| 1;
        dvui.refresh(null, @src(), self.menu.data().id);
    }
    dvui.dataSet(null, self.menu.data().id, "_selected", self.selected_index);
    if (self.drop != null) {
        self.drop.?.deinit();
        self.drop = null;
    }
    self.menu.deinit();
}

const Options = dvui.Options;
const RectScale = dvui.RectScale;

const MenuWidget = dvui.MenuWidget;
const MenuItemWidget = dvui.MenuItemWidget;
const FloatingMenuWidget = dvui.FloatingMenuWidget;

const std = @import("std");
const dvui = @import("../dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
