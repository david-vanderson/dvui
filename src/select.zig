//! Helpers for Multi and Single selection

const dvui = @import("dvui.zig");
const WidgetData = dvui.WidgetData;

pub const SelectAllState = enum {
    select_all,
    select_none,
};

pub const SelectOptions = struct {
    selection_id: u64 = 0,
    selection_info: ?*SelectionInfo = null,
};

pub const SelectionEvent = struct {
    selection_id: u64,
    selected: bool,
    screen_rect: dvui.Rect.Physical,

    pub fn eventMatch(self: *SelectionEvent, wd: *WidgetData) bool {
        return wd.borderRectScale().r.contains(self.screen_rect.topLeft()) or
            wd.borderRectScale().r.contains(self.screen_rect.bottomRight());
    }
};

pub const SelectionInfo = struct {
    const max_per_frame = 5;
    sel_events: [max_per_frame]SelectionEvent = undefined,
    event_count: u8 = 0,

    pub fn reset(self: *SelectionInfo) void {
        self.event_count = 0;
    }

    pub fn add(self: *SelectionInfo, selection_id: u64, selected: bool, wd: *WidgetData) void {
        if (self.event_count < max_per_frame) {
            self.sel_events[self.event_count] = .{ .selection_id = selection_id, .selected = selected, .screen_rect = wd.borderRectScale().r };
            self.event_count += 1;
        } else {
            dvui.log.debug("Dropping selection event for selection_id {d}\n", .{selection_id});
            return;
        }
    }

    pub fn events(self: *SelectionInfo) []SelectionEvent {
        return self.sel_events[0..self.event_count];
    }
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

    pub fn processEvents(self: *MultiSelectMouse, sel_info: *SelectionInfo, wd: *dvui.WidgetData) void {
        self.selection_changed = false;
        for (dvui.events()) |*e| {
            if (e.evt == .key) {
                const ke = e.evt.key;
                if (ke.code != .left_shift and ke.code != .right_shift) continue;
                self.shift_held = ke.action == .down or ke.action == .repeat;
            }
        }
        for (sel_info.events()) |*se| {
            if (se.eventMatch(wd)) {
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
            } else if (e.evt == .key and !e.handled) {
                const ke = e.evt.key;
                if (ke.matchBind("select_all") and ke.action == .down) {
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
            // Show the results of the selection change.
            dvui.refresh(null, @src(), null);
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

    pub fn processEvents(self: *SingleSelect, sel_info: *SelectionInfo, wd: *dvui.WidgetData) void {
        self.selection_changed = false;
        for (sel_info.events()) |*se| {
            if (se.eventMatch(wd)) {
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
