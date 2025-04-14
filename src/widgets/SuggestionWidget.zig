pub const SuggestionWidget = @This();

id: u32 = undefined,
options: Options = undefined,
init_options: InitOptions = undefined,

// menu catches the close_popup from drop if you click off of it
menu: *MenuWidget = undefined,
drop: ?*FloatingMenuWidget = null,
drop_mi: ?MenuItemWidget = null,
drop_mi_index: usize = 0,
selected_index: usize = undefined, // 0 indexed
activate_selected: bool = false,

pub var defaults: Options = .{
    .name = "Suggestions",
};

pub const InitOptions = struct {
    rs: RectScale,
    text_entry_id: u32,
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) SuggestionWidget {
    var self = SuggestionWidget{};
    self.id = dvui.parentGet().extendId(src, opts.idExtra());
    self.options = defaults.override(opts);
    self.init_options = init_opts;
    self.selected_index = dvui.dataGet(null, self.id, "_selected", usize) orelse 0;
    return self;
}

pub fn install(self: *SuggestionWidget) !void {
    self.menu = try dvui.menu(@src(), .horizontal, .{ .rect = .{}, .id_extra = self.options.idExtra() });
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

pub fn dropped(self: *SuggestionWidget) !bool {
    if (self.drop != null) {
        // protect against calling this multiple times
        return true;
    }

    if (self.menu.submenus_activated) {
        self.drop = try dvui.floatingMenu(@src(), .{ .from = self.init_options.rs.r }, self.options);
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

pub fn addChoiceLabel(self: *SuggestionWidget, label_str: []const u8) !bool {
    var mi = try self.addChoice();

    try dvui.labelNoFmt(@src(), label_str, .{});

    var ret: bool = false;
    if (mi.activeRect()) |_| {
        self.close();
        ret = true;
    }

    mi.deinit();

    return ret;
}

pub fn addChoice(self: *SuggestionWidget) !*MenuItemWidget {
    self.drop_mi = MenuItemWidget.init(@src(), .{ .highlight_only = true }, .{ .id_extra = self.drop_mi_index, .expand = .horizontal, .padding = .{} });
    if (self.selected_index == self.drop_mi_index) {
        if (self.activate_selected) {
            self.drop_mi.?.activated = true;
            self.drop_mi.?.show_active = true;
        } else {
            self.drop_mi.?.highlight = true;
        }
    }
    try self.drop_mi.?.install();
    self.drop_mi.?.processEvents();
    if (self.drop_mi.?.data().id == dvui.focusedWidgetId()) {
        self.selected_index = self.drop_mi_index;
    }
    try self.drop_mi.?.drawBackground(.{});

    self.drop_mi_index += 1;

    return &self.drop_mi.?;
}

pub fn deinit(self: *SuggestionWidget) void {
    if (self.selected_index > (self.drop_mi_index -| 1)) {
        self.selected_index = self.drop_mi_index -| 1;
        dvui.refresh(null, @src(), self.id);
    }
    dvui.dataSet(null, self.id, "_selected", self.selected_index);
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
