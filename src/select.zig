//! Helpers for Multi and Single selection

const dvui = @import("dvui.zig");
const WidgetData = dvui.WidgetData;

/// Manage multi-selection.
/// supports single-click and shift-click selection.
/// - must persist accross frames
/// - call processEvents after the "selectables" have been deinit()-ed.
pub const MultiSelect = struct {
    first_selected_id: ?u64 = null,
    second_selected_id: ?u64 = null,
    should_select: bool = false,
    shift_held: bool = false,
    selection_changed: bool = false,

    pub fn processEvents(self: *MultiSelect, wd: *dvui.WidgetData) void {
        self.selection_changed = false;
        for (dvui.events()) |*e| {
            if (e.evt == .key) {
                if (e.evt != .key and e.evt != .selection) continue;
                const ke = e.evt.key;
                if (ke.code != .left_shift and ke.code != .right_shift) continue;
                self.shift_held = ke.action == .down or ke.action == .repeat;
            } else if (e.evt == .selection) {
                const se = e.evt.selection;
                (@import("std")).debug.print("se = {}\n", .{se});
                if (dvui.eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r })) {
                    e.handle(@src(), wd);
                    if (!self.shift_held) {
                        self.first_selected_id = se.selection_id;
                        self.second_selected_id = se.selection_id;
                        self.should_select = se.selected;
                        if (self.first_selected_id) |_| {
                            if (self.second_selected_id) |second_id| {
                                self.first_selected_id = second_id;
                            }
                            self.second_selected_id = se.selection_id;
                            self.should_select = se.selected;
                            self.selection_changed = true;
                        }
                    } else {
                        self.first_selected_id = se.selection_id;
                        self.should_select = se.selected;
                        self.selection_changed = true;
                    }
                }
            }
        }
    }

    pub fn selectionChanged(self: *MultiSelect) bool {
        return self.selection_changed;
    }

    // Returns the lowest id selected.
    pub fn selectionIdStart(self: *MultiSelect) u64 {
        return @min(self.first_selected_id orelse 0, self.second_selected_id orelse self.first_selected_id orelse 0);
    }

    // Returns the highest id selected.
    pub fn selectionIdEnd(self: *MultiSelect) u64 {
        return @max(self.first_selected_id orelse 0, self.second_selected_id orelse self.first_selected_id orelse 0);
    }
};

/// Implement single selection
/// deselects the previously selected item and selects the new item.
/// - must persist accross frames
/// - call processEvents after the "selectables" have been deinit()-ed.
pub const SingleSelect = struct {
    id_to_select: ?u64 = null,
    id_to_unselect: ?u64 = null,
    selection_changed: bool = false,

    pub fn processEvents(self: *SingleSelect, wd: *dvui.WidgetData) void {
        self.selection_changed = false;
        for (dvui.events()) |*e| {
            if (e.evt != .selection) continue;
            if (dvui.eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r })) {
                e.handle(@src(), wd);
                const se = e.evt.selection;
                if (se.selected == false) {
                    self.id_to_select = null;
                    self.id_to_unselect = se.selection_id;
                    self.selection_changed = true;
                } else {
                    if (self.id_to_select) |last_id| {
                        self.id_to_unselect = last_id;
                    }
                    self.id_to_select = se.selection_id;
                    self.selection_changed = true;
                }
            }
        }
    }

    pub fn selectionChanged(self: *SingleSelect) bool {
        return self.selection_changed;
    }
};
