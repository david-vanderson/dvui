const std = @import("std");
const dvui = @import("../../dvui.zig");
const GridWidget = dvui.GridWidget;

pub const SingleSelect = struct {
    selection_info: *dvui.SelectionInfo,

    pub fn performAction(self: *SingleSelect, selection_changed: bool, data_adapter: anytype) void {
        if (selection_changed) {
            const last_selected = self.selection_info.prev_changed orelse return;
            data_adapter.setValue(last_selected, false);
        }
    }
};

pub const MultiSelectMouse = struct {
    selection_info: *dvui.SelectionInfo,
    shift_held: bool = false,

    pub fn processEvents(self: *MultiSelectMouse) void {
        const evts = dvui.events();
        for (evts) |*e| {
            if (e.evt == .key and (e.evt.key.code == .left_shift or e.evt.key.code == .right_shift)) {
                switch (e.evt.key.action) {
                    .repeat, .down => self.shift_held = true,
                    .up => self.shift_held = false,
                }
            }
        }
    }

    pub fn performAction(self: *const MultiSelectMouse, selection_changed: bool, data_adapter: anytype) void {
        if (selection_changed and self.shift_held) {
            const this_selection = self.selection_info.this_changed orelse return;
            const prev_selection = self.selection_info.prev_changed orelse return;
            const first = @min(this_selection, prev_selection);
            const last = @max(this_selection, prev_selection);
            for (first..last + 1) |row| {
                data_adapter.setValue(row, self.selection_info.this_selected);
            }
        }
    }
};

//pub const ScrollToFocused = struct {
//    focused_wid: ?dvui.WidgetId = null,
//
//    pub fn init() ScrollToFocused {
//        return .{ .focused_wid = dvui.focusedWidgetId() };
//    }
//
//    pub fn performAction(self: *ScrollToFocused, grid: *GridWidget) void {
//        const current_focus_wid = dvui.focusedWidgetId();
//        if (current_focus_wid != self.focused_wid) {
//            std.debug.print("sf {x} cf {x}\n", .{ self.focused_wid orelse .zero, current_focus_wid orelse .zero });
//
//            self.focused_wid = current_focus_wid;
//        } else {
//            std.debug.print("return\n", .{});
//            return;
//        }
//        const sw = dvui.currentWindow().subwindowFocused();
//        if (sw.focused_widgetId != null) {
//            var scroll_to: dvui.Event = .{ .evt = .{ .scroll_to = .{
//                .screen_rect = sw.focused_widgetRect,
//                .over_scroll = false,
//            } } };
//            // TODO: Add a grid.scrollTo()? Can't just take a row number as the column might not be scrolled to
//            // Or a better way to
//            grid.scroll.scroll.processEvent(&scroll_to, true);
//        }
//    }
//};
