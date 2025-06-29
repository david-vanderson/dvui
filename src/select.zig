//! Helpers for Multi and Single selection

const dvui = @import("dvui.zig");
const WidgetData = dvui.WidgetData;

pub const SelectAllState = enum {
    select_all,
    select_none,
};

/// Manage multi-selection.
/// supports single-click and shift-click selection.
/// - must persist accross frames
/// - call processEvents after the "selectables" have been deinit()-ed.
pub const MultiSelectMouse = struct {
    first_selected_id: ?u64 = null,
    second_selected_id: ?u64 = null,
    should_select: bool = false,
    shift_held: bool = false,
    selection_changed: bool = false,

    pub fn processEvents(self: *MultiSelectMouse, wd: *dvui.WidgetData) void {
        self.selection_changed = false;
        for (dvui.events()) |*e| {
            if (e.evt == .key) {
                const ke = e.evt.key;
                if (ke.code != .left_shift and ke.code != .right_shift) continue;
                self.shift_held = ke.action == .down or ke.action == .repeat;
            } else if (e.evt == .selection) {
                const se = e.evt.selection;
                if (dvui.eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r })) {
                    e.handle(@src(), wd);
                    if (!self.shift_held or self.first_selected_id == null) {
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

    pub fn selectionChanged(self: *MultiSelectMouse) bool {
        return self.selection_changed;
    }

    // Returns the lowest id selected.
    pub fn selectionIdStart(self: *MultiSelectMouse) u64 {
        return @min(self.first_selected_id orelse 0, self.second_selected_id orelse self.first_selected_id orelse 0);
    }

    // Returns the highest id selected.
    pub fn selectionIdEnd(self: *MultiSelectMouse) u64 {
        return @max(self.first_selected_id orelse 0, self.second_selected_id orelse self.first_selected_id orelse 0);
    }
};

/// Helper for select all support via the "select_all" keyboard binding.
pub const SelectAllKeyboard = struct {
    selection_changed: bool = false,

    pub fn processEvents(self: *SelectAllKeyboard, select_all_state: *dvui.select.SelectAllState, wd: *dvui.WidgetData) void {
        self.selection_changed = false;
        var is_select_all = false;
        var is_in_widget: bool = false;
        for (dvui.events()) |*e| {
            if (e.evt == .mouse and e.evt.mouse.action == .position) {
                if (wd.backgroundRectScale().r.contains(e.evt.mouse.p)) {
                    is_in_widget = true;
                }
            }
            if (e.evt == .key and !e.handled) {
                const ke = e.evt.key;
                if (ke.matchBind("select_all") and ke.action != .up) {
                    e.handle(@src(), wd);
                    is_select_all = true;
                }
            }
        }
        if (is_in_widget and is_select_all) {
            if (select_all_state.* == .select_all) {
                select_all_state.* = .select_none;
            } else {
                select_all_state.* = .select_all;
            }
            self.selection_changed = true;
        }
    }

    pub fn selectionChanged(self: *const SelectAllKeyboard) bool {
        return self.selection_changed;
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
