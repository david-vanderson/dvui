//! Helpers for Multi and Single selection
//! Implements an event queue for selections.
//! Selectable objects can optionally raise selection events which
//! are processed by these helpers

const std = @import("std");
const dvui = @import("dvui.zig");
const WidgetData = dvui.WidgetData;
const Id = dvui.Id;
const Rect = dvui.Rect;

pub const SelectAllState = enum {
    select_all,
    select_none,
};

pub const SelectOptions = struct {
    selection_id: usize = 0,
    selection_info: ?*SelectionInfo = null,
};

pub const SelectionEvent = struct {
    selection_id: usize,
    selected: bool,
    screen_rect: Rect.Physical,

    pub fn eventMatch(self: *SelectionEvent, wd: *WidgetData) bool {
        return wd.borderRectScale().r.contains(self.screen_rect.topLeft()) or
            wd.borderRectScale().r.contains(self.screen_rect.bottomRight());
    }
};

pub const SelectionInfo = struct {
    sel_events: std.ArrayListUnmanaged(SelectionEvent) = .empty,

    /// Clear queued selection events.
    /// must be called each frame before being used.
    pub fn reset(self: *SelectionInfo) void {
        self.sel_events = .empty;
    }

    /// Add a selection event.
    pub fn add(self: *SelectionInfo, selection_id: usize, selected: bool, wd: *WidgetData) void {
        self.sel_events.append(
            dvui.currentWindow().arena(),
            .{ .selection_id = selection_id, .selected = selected, .screen_rect = wd.borderRectScale().r },
        ) catch |err| {
            dvui.logError(@src(), err, "Dropping selection event for selection_id {d}\n", .{selection_id});
        };
    }

    pub fn events(self: *const SelectionInfo) []SelectionEvent {
        return self.sel_events.items;
    }
};

/// Manage multi-selection.
/// supports single-click and shift-click selection.
/// - must persist accross frames
/// - call processEvents after the "selectables" have been deinit()-ed.
pub const MultiSelectMouse = struct {
    first_selected_id: ?usize = null,
    second_selected_id: ?usize = null,
    should_select: bool = false,
    shift_held: bool = false,
    selection_changed: bool = false,

    /// Process any selection events
    /// - must be called after the selectables have been created and deinit-ed.
    pub fn processEvents(self: *MultiSelectMouse, sel_info: *SelectionInfo, wd: *WidgetData) void {
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
                    // Single select or shift held on first selection.
                    self.first_selected_id = se.selection_id;
                    self.second_selected_id = se.selection_id;
                    self.should_select = se.selected;
                    self.selection_changed = true;
                } else {
                    // Shift-select
                    self.second_selected_id = se.selection_id;
                    self.should_select = se.selected;
                    self.selection_changed = true;
                }
            }
        }
    }

    /// Returns true if any selections changed this frame.
    pub fn selectionChanged(self: *const MultiSelectMouse) bool {
        return self.selection_changed;
    }

    // Returns the lowest id selected.
    pub fn selectionIdStart(self: *const MultiSelectMouse) usize {
        return @min(self.first_selected_id orelse 0, self.second_selected_id orelse self.first_selected_id orelse 0);
    }

    // Returns the highest id selected.
    pub fn selectionIdEnd(self: *const MultiSelectMouse) usize {
        return @max(self.first_selected_id orelse 0, self.second_selected_id orelse self.first_selected_id orelse 0);
    }
};

/// Helper for select all support via the "select_all" keyboard binding.
pub const SelectAllKeyboard = struct {
    selection_changed: bool = false,
    last_focused_in_frame: Id = .zero,

    /// reset() should be called immediately before the first "selectable" is created.
    /// If using with a GridWidget, call reset before the first body cell is created.
    pub fn reset(self: *SelectAllKeyboard) void {
        self.last_focused_in_frame = dvui.lastFocusedIdInFrame();
    }

    // processEvents() should be called after all selectables have been created
    // If using with a GridWidget, call processEvents after all body cells have been created.
    pub fn processEvents(self: *SelectAllKeyboard, select_all_state: *SelectAllState, wd: *const WidgetData) void {
        self.selection_changed = false;
        for (dvui.events()) |*e| {
            if (self.last_focused_in_frame != dvui.lastFocusedIdInFrame()) {
                if (e.evt == .key and !e.handled) {
                    const ke = e.evt.key;
                    if (ke.matchBind("select_all") and ke.action == .down) {
                        e.handle(@src(), wd);
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
            }
        }
    }

    /// Returns true if any selections changed this frame.
    pub fn selectionChanged(self: *const SelectAllKeyboard) bool {
        return self.selection_changed;
    }
};

/// Implement single selection
/// deselects the previously selected item and selects the new item.
/// - must persist accross frames
/// - call processEvents after the "selectables" have been created.
/// Note: May be inaccurate if multiple selection events occur in a single frame.
///   Implement additonal checks or process the raw events if you need to ensure
///   that only a single item is selected. (required for very low frame rate environments)
pub const SingleSelect = struct {
    id_to_select: ?usize = null,
    id_to_unselect: ?usize = null,
    selection_changed: bool = false,

    pub fn processEvents(self: *SingleSelect, sel_info: *SelectionInfo, wd: *WidgetData) void {
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

    /// Returns true if any selections changed this frame.
    pub fn selectionChanged(self: *const SingleSelect) bool {
        return self.selection_changed;
    }
};
