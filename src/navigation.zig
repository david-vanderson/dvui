//! Helpers for mouse and keyboard navigation.
//!

const std = @import("std");
const dvui = @import("dvui.zig");
const GridWidget = dvui.GridWidget;
const Event = dvui.Event;
const WidgetData = dvui.WidgetData;
const WidgetId = dvui.WidgetId;
const Point = dvui.Point;
const Cell = GridWidget.Cell;

/// Adds keyboard navigation to the grid
/// Provides a "cursor" that can be moved using
/// - tab, shift-tab, left-arrow, right-arrow
pub const GridKeyboard = struct {
    /// Direction keys.
    /// - use defaultKeys() or provide your own bindings.
    pub const NavigationKeys = struct {
        up: dvui.enums.Keybind,
        down: dvui.enums.Keybind,
        left: dvui.enums.Keybind,
        right: dvui.enums.Keybind,
        first: dvui.enums.Keybind,
        last: dvui.enums.Keybind,
        col_first: dvui.enums.Keybind,
        col_last: dvui.enums.Keybind,
        scroll_up: dvui.enums.Keybind,
        scroll_down: dvui.enums.Keybind,

        pub const none: NavigationKeys = .{
            .up = .{},
            .down = .{},
            .left = .{},
            .right = .{},
            .first = .{},
            .last = .{},
            .col_first = .{},
            .col_last = .{},
            .scroll_up = .{},
            .scroll_down = .{},
        };

        pub fn defaults() NavigationKeys {
            const cw = dvui.currentWindow();
            return .{
                .up = cw.keybinds.get("grid_cell_up") orelse unreachable,
                .down = cw.keybinds.get("grid_cell_down") orelse unreachable,
                .left = cw.keybinds.get("prev_widget") orelse unreachable,
                .right = cw.keybinds.get("next_widget") orelse unreachable,
                .first = cw.keybinds.get("text_start") orelse unreachable,
                .last = cw.keybinds.get("text_end") orelse unreachable,
                .col_first = .{},
                .col_last = .{},
                .scroll_up = .{ .key = .page_up },
                .scroll_down = .{ .key = .page_down },
            };
        }
    };

    /// Should the cursor wrap to the next row at the end of a column.
    wrap_cursor: bool,
    /// Should we tab out of the grid at the first/last row_col. TODO: Rename this
    tab_out: bool,

    /// Number of rows to move the cursor up/down on scroll_up/scroll_down
    num_scroll: isize,

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

    /// Must be called after all body cells are created.
    /// and before any new widgets are created.
    pub fn gridEnd(self: *GridKeyboard) void {
        self.last_focused_widget = dvui.lastFocusedIdInFrame(null);
    }

    pub fn numScrollDefault(grid: *GridWidget) isize {
        const default: isize = 5;
        if (grid.row_height < 1) {
            return default;
        }
        return @intFromFloat(@round(grid.bsi.viewport.h / grid.row_height));
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

    pub fn scrollBy(self: *GridKeyboard, num_cols: isize, num_rows: isize) void {
        var should_wrap: bool = false;
        if (num_cols < 0) {
            if (self.cursor.col_num >= -num_cols) {
                self.cursor.col_num -= @intCast(-num_cols);
            } else {
                self.cursor.col_num = 0;
                should_wrap = true;
            }
        } else if (num_cols > 0) {
            if (self.cursor.col_num < self.num_cols - 1) {
                self.cursor.col_num += @intCast(num_cols);
            } else {
                should_wrap = true;
            }
        }
        if (num_rows < 0) {
            if (self.cursor.row_num >= -num_rows) {
                self.cursor.row_num -= @intCast(-num_rows);
            } else {
                self.cursor.row_num = 0;
            }
        } else if (num_rows > 0) {
            if (self.cursor.row_num < self.num_rows - 1) {
                self.cursor.row_num += @intCast(num_rows);
            } else {
                self.cursor.row_num = self.num_rows - 1;
            }
        }
        if (should_wrap and self.wrap_cursor) {
            if (self.cursor.col_num == 0) {
                if (self.cursor.row_num > 0) {
                    self.cursor.col_num = self.num_cols - 1;
                    self.cursor.row_num -= 1;
                }
            } else if (self.cursor.col_num == self.num_cols - 1) {
                self.cursor.col_num = 0;
                if (self.cursor.row_num < self.num_rows - 1) {
                    self.cursor.row_num += 1;
                }
            }
        }
        self.enforceCursorLimits();
    }

    pub fn processEvents(self: *GridKeyboard, grid: *GridWidget) void {
        self.processEventsCustom(grid, GridWidget.pointToCell);
    }

    /// Call this once per frame before the grid body cells are created.
    pub fn processEventsCustom(self: *GridKeyboard, grid: *GridWidget, cellConverter: fn (
        grid: *GridWidget,
        point: Point.Physical,
    ) ?Cell) void {
        self.enforceCursorLimits();

        self.is_focused = self.last_focused_widget == dvui.focusedWidgetId() and dvui.lastFocusedIdInFrame(null) == .zero;

        for (dvui.events()) |*e| {
            self.processEvent(e, grid, cellConverter);
        }
    }

    pub fn processEvent(self: *GridKeyboard, e: *Event, grid: *GridWidget, cellConverter: fn (
        grid: *GridWidget,
        point: Point.Physical,
    ) ?Cell) void {
        defer self.enforceCursorLimits();
        switch (e.evt) {
            .key => |*ke| {
                if (!self.is_focused or e.handled) return;
                if (ke.action == .down or ke.action == .repeat) {
                    if (ke.matchKeyBind(self.navigation_keys.first)) {
                        e.handle(@src(), grid.data());
                        self.scrollTo(0, 0);
                    } else if (ke.matchKeyBind(self.navigation_keys.last)) {
                        e.handle(@src(), grid.data());
                        self.scrollTo(self.num_cols - 1, self.num_rows - 1);
                    } else if (ke.matchKeyBind(self.navigation_keys.col_first)) {
                        e.handle(@src(), grid.data());
                        self.scrollTo(0, self.cursor.row_num);
                    } else if (ke.matchKeyBind(self.navigation_keys.col_last)) {
                        e.handle(@src(), grid.data());
                        self.scrollTo(self.num_cols - 1, self.cursor.row_num);
                    } else if (ke.matchKeyBind(self.navigation_keys.scroll_up)) {
                        e.handle(@src(), grid.data());
                        self.scrollBy(0, -self.num_scroll);
                        grid.bsi.scrollPageUp(.vertical);
                    } else if (ke.matchKeyBind(self.navigation_keys.scroll_down)) {
                        e.handle(@src(), grid.data());
                        self.scrollBy(0, self.num_scroll);
                        grid.bsi.scrollPageDown(.vertical);
                    } else if (ke.matchKeyBind(self.navigation_keys.up)) {
                        e.handle(@src(), grid.data());
                        self.scrollBy(0, -1);
                    } else if (ke.matchKeyBind(self.navigation_keys.down)) {
                        e.handle(@src(), grid.data());
                        self.scrollBy(0, 1);
                    } else if (ke.matchKeyBind(self.navigation_keys.left)) {
                        e.handle(@src(), grid.data());
                        if (self.tab_out and self.cursor.eqColRow(0, 0)) {
                            dvui.tabIndexPrev(e.num);
                            self.is_focused = false;
                        } else {
                            self.scrollBy(-1, 0);
                        }
                    } else if (ke.matchKeyBind(self.navigation_keys.right)) {
                        e.handle(@src(), grid.data());
                        if (self.tab_out and self.cursor.eqColRow(self.num_cols - 1, self.num_rows - 1)) {
                            dvui.tabIndexNext(e.num);
                            self.is_focused = false;
                        } else {
                            self.scrollBy(1, 0);
                        }
                    }
                }
            },
            .mouse => |*me| {
                if (me.action == .focus) {
                    // pointToRowCol will return null if the mouse focus event
                    // is outside the grid.
                    const focused_cell = cellConverter(grid, me.p);
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
    pub fn cellCursor(self: *GridKeyboard) Cell {
        return self.cursor;
    }

    /// Should the widget in cellCursor() be focused this frame?
    pub fn shouldFocus(self: *const GridKeyboard) bool {
        return self.is_focused;
    }
};
