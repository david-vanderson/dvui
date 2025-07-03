//! Helpers for mouse and keyboard navigation.
//!

const std = @import("std");
const dvui = @import("dvui.zig");
const GridWidget = dvui.GridWidget;
const Event = dvui.Event;
const WidgetData = dvui.WidgetData;
const WidgetId = dvui.WidgetId;

/// Adds keyboard navigation to the grid
/// Provides a "cursor" that can be moved using
/// - tab, shift-tab, left-arrow, right-arrow
pub const GridKeyboard = struct {
    pub const Cell = struct {
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
                .up = cw.keybinds.get("grid_cell_up") orelse unreachable,
                .down = cw.keybinds.get("grid_cell_down") orelse unreachable,
                .left = cw.keybinds.get("prev_widget") orelse unreachable,
                .right = cw.keybinds.get("next_widget") orelse unreachable,
            };
        }
    };

    /// Should the cursor wrap to the next row at the end of a column.
    wrap_cursor: bool,
    /// Should we tab out of the grid at the last row_col. TODO: Rename this
    tab_out: bool,

    /// col_num will always be less than this value.
    num_cols: usize,
    /// row_num will always be less than this value.
    num_rows: usize,
    /// Customize navigation keys
    /// - use .defaults() for default keys.
    navigation_keys: NavigationKeys = .none,

    /// Cursor should only be used if the grid or children have focus.
    /// using cellCursor() is prefered.
    is_focused: bool = false,

    /// result cursor. prefer to use cellCursor() instead.
    cursor: Cell = .{ .col_num = 0, .row_num = 0 },

    last_focused_widget: WidgetId = .zero,

    pub fn reset(self: *GridKeyboard) void {
        self.last_focused_widget = dvui.lastFocusedIdInFrame(null);
    }

    /// Change max row and col limits
    pub fn setLimits(self: *GridKeyboard, max_cols: usize, max_rows: usize) void {
        self.num_cols = max_cols;
        self.num_rows = max_rows;
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

        self.is_focused = self.last_focused_widget == dvui.focusedWidgetId() and dvui.lastFocusedIdInFrame(null) == .zero;

        for (dvui.events()) |*e| {
            self.processEvent(e, grid);
        }
    }

    pub fn processEvent(self: *GridKeyboard, e: *Event, grid: *GridWidget) void {
        defer self.enforceCursorLimits();
        switch (e.evt) {
            .key => |*ke| {
                if (!self.is_focused or e.handled) return;
                if (ke.action == .down) {
                    if (ke.matchKeyBind(self.navigation_keys.up)) {
                        e.handle(@src(), grid.data());
                        self.cursor.row_num = if (self.cursor.row_num > 0) self.cursor.row_num - 1 else 0;
                    } else if (ke.matchKeyBind(self.navigation_keys.down)) {
                        e.handle(@src(), grid.data());
                        self.cursor.row_num += 1;
                    } else if (ke.matchKeyBind(self.navigation_keys.left)) {
                        e.handle(@src(), grid.data());
                        if (self.tab_out and self.cursor.eq(0, 0)) {
                            std.debug.print("tabbing out\n", .{});
                            dvui.tabIndexPrev(e.num);
                            self.is_focused = false;
                        } else if (self.cursor.col_num > 0) {
                            self.cursor.col_num -= 1;
                        } else if (self.wrap_cursor) {
                            if (self.cursor.row_num > 0) {
                                self.cursor.col_num = self.num_cols;
                                self.cursor.row_num -= 1;
                            }
                        }
                    } else if (ke.matchKeyBind(self.navigation_keys.right)) {
                        e.handle(@src(), grid.data());
                        if (self.tab_out and self.cursor.col_num == self.num_cols - 1 and self.cursor.row_num == self.num_rows - 1) {
                            std.debug.print("tabbing out\n", .{});
                            dvui.tabIndexNext(e.num);
                            self.is_focused = false;
                        } else if (self.cursor.col_num < self.num_cols) {
                            self.cursor.col_num += 1;
                        }
                        if (self.wrap_cursor and self.cursor.col_num >= self.num_cols) {
                            if (self.cursor.row_num < self.num_rows - 1) {
                                self.cursor.col_num = 0;
                                self.cursor.row_num += 1;
                            }
                        }
                    }
                }
            },
            .mouse => |*me| {
                if (me.action == .focus) {
                    // pointToRowCol will return null if the mouse focus event
                    // is outside the grid.
                    const focused_cell = grid.pointToColRow(me.p);
                    if (focused_cell) |cell| {
                        self.cursor.col_num = cell.col_num;
                        self.cursor.row_num = cell.row_num;
                        self.is_focused = true;
                    } else {
                        self.is_focused = false;
                    }
                }
            },
            else => {},
        }
    }

    pub fn enforceCursorLimits(self: *GridKeyboard) void {
        if (self.num_cols > 0)
            self.cursor.col_num = @min(self.cursor.col_num, self.num_cols - 1)
        else
            self.cursor.col_num = 0;
        if (self.num_rows > 0)
            self.cursor.row_num = @min(self.cursor.row_num, self.num_rows - 1)
        else
            self.cursor.row_num = 0;
    }

    /// returns the current cursor if the grid or one if
    /// its children has focus
    pub fn cellCursor(self: *GridKeyboard) ?Cell {
        return self.cursor;
    }
};
