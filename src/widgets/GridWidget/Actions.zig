const std = @import("std");
const dvui = @import("../../dvui.zig");

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
