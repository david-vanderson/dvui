//! Helpers for mouse and keyboard navigation.
//!

const std = @import("std");
const dvui = @import("dvui.zig");
const GridWidget = dvui.GridWidget;
const Event = dvui.Event;
const WidgetData = dvui.WidgetData;

/// Adds keyboard navigation to the grid
/// Provides a "cursor" that can be moved using
/// - tab, shift-tab, left-arrow, right-arrow
pub const GridKeyboard = struct {
    const Cell = struct {
        col_num: usize,
        row_num: usize,

        pub fn eq(self: Cell, col_num: usize, row_num: usize) bool {
            return self.col_num == col_num and self.row_num == row_num;
        }
    };

    /// Direction keys.
    /// - use defaultKeys() or provide your own bindings.
    pub const NavigationKeys = struct {
        up: dvui.enums.Keybind,
        down: dvui.enums.Keybind,
        left: dvui.enums.Keybind,
        right: dvui.enums.Keybind,

        pub const none: NavigationKeys = .{
            .up = .{},
            .down = .{},
            .left = .{},
            .right = .{},
        };

        pub fn defaults() NavigationKeys {
            const cw = dvui.currentWindow();
            return .{
                .up = cw.keybinds.get("char_up") orelse unreachable,
                .down = cw.keybinds.get("char_down") orelse unreachable,
                .left = cw.keybinds.get("prev_widget") orelse unreachable,
                .right = cw.keybinds.get("next_widget") orelse unreachable,
            };
        }
    };
    /// col_num will always be less than this value.
    max_cols: usize,
    /// row_num will always be less than this value.
    max_rows: usize,
    /// Customize navigation keys
    /// - use .defaults() for default keys.
    navigation_keys: NavigationKeys = .none,

    /// result cursor. prefer to use cellCursor() instead.
    cursor: Cell = .{ .col_num = 0, .row_num = 0 },

    /// Change max row and col limits
    pub fn setLimits(self: *GridKeyboard, max_cols: usize, max_rows: usize) void {
        self.max_cols = max_cols;
        self.max_rows = max_rows;
        self.enforceCursorLimits();
    }

    /// Move the cursor to the specified col and row.
    pub fn scrollTo(self: *GridKeyboard, col_num: usize, row_num: usize) void {
        self.cursor.col_num = col_num;
        self.cursor.row_num = row_num;
        self.enforceCursorLimits();
    }

    /// Call this once per frame before the grid body cells are created.
    pub fn processEvents(self: *GridKeyboard, grid: *GridWidget) void {
        self.enforceCursorLimits();

        for (dvui.events()) |*e| {
            if (!matchEvent(e, grid.data()))
                continue;

            self.processEvent(e, grid);
        }
    }

    pub fn matchEvent(e: *Event, wd: *WidgetData) bool {
        const ret = dvui.eventMatch(e, .{
            .id = wd.id,
            .focus_id = dvui.focusedWidgetId() orelse .zero,
            .r = wd.borderRectScale().r,
        });
        return ret;
    }

    pub fn processEvent(self: *GridKeyboard, e: *Event, grid: *GridWidget) void {
        defer self.enforceCursorLimits();

        switch (e.evt) {
            .key => |*ke| {
                if (ke.action == .down) {
                    if (ke.matchKeyBind(self.navigation_keys.up)) {
                        e.handle(@src(), grid.data());
                        self.cursor.row_num = if (self.cursor.row_num > 0) self.cursor.row_num - 1 else 0;
                    } else if (ke.matchKeyBind(self.navigation_keys.down)) {
                        e.handle(@src(), grid.data());
                        self.cursor.row_num += 1;
                    } else if (ke.matchKeyBind(self.navigation_keys.left)) {
                        e.handle(@src(), grid.data());
                        self.cursor.col_num = if (self.cursor.col_num > 0) self.cursor.col_num - 1 else 0;
                    } else if (ke.matchKeyBind(self.navigation_keys.right)) {
                        e.handle(@src(), grid.data());
                        self.cursor.col_num += 1;
                    }
                }
            },
            .mouse => |*me| {
                if (me.action == .focus) {
                    const focused_cell = grid.pointToColRow(me.p);
                    if (focused_cell) |cell| {
                        self.cursor.col_num = cell.col_num;
                        self.cursor.row_num = cell.row_num;
                    }
                }
            },
            else => {},
        }
    }

    pub fn enforceCursorLimits(self: *GridKeyboard) void {
        if (self.max_cols > 0)
            self.cursor.col_num = @min(self.cursor.col_num, self.max_cols - 1)
        else
            self.cursor.col_num = 0;
        if (self.max_rows > 0)
            self.cursor.row_num = @min(self.cursor.row_num, self.max_rows - 1)
        else
            self.cursor.row_num = 0;
    }

    pub fn cellCursor(self: *GridKeyboard) Cell {
        return self.cursor;
    }
};
