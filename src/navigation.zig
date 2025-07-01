//! Helpers for mouse and keyboard
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
    max_cols: usize,
    max_rows: usize,
    cursor: Cell = .{ .col_num = 0, .row_num = 0 },

    pub fn setLimits(self: *GridKeyboard, max_cols: usize, max_rows: usize) void {
        self.max_cols = max_cols;
        self.max_rows = max_rows;
    }

    pub fn matchEvent(e: *Event, wd: *WidgetData) bool {
        const ret = dvui.eventMatch(e, .{
            .id = wd.id,
            .focus_id = dvui.focusedWidgetId() orelse .zero,
            .r = wd.borderRectScale().r,
        });
        return ret;
    }

    pub fn processEvents(self: *GridKeyboard, grid: *GridWidget) void {
        self.enforceCursorLimits();

        for (dvui.events()) |*e| {
            if (!matchEvent(e, grid.data()))
                continue;

            self.processEvent(e, grid);
        }
    }

    pub fn processEvent(self: *GridKeyboard, e: *Event, grid: *GridWidget) void {
        switch (e.evt) {
            .key => |*ke| {
                if (ke.action == .down) {
                    switch (ke.code) {
                        .up => {
                            e.handle(@src(), grid.data());
                            self.cursor.row_num = if (self.cursor.row_num > 0) self.cursor.row_num - 1 else 0;
                        },
                        .down => {
                            e.handle(@src(), grid.data());
                            self.cursor.row_num += 1;
                        },
                        .tab => {
                            if (ke.mod.shift()) {
                                e.handle(@src(), grid.data());
                                self.cursor.col_num = if (self.cursor.col_num > 0) self.cursor.col_num - 1 else 0;
                            } else {
                                e.handle(@src(), grid.data());
                                self.cursor.col_num += 1;
                            }
                        },
                        else => {},
                    }
                }
            },
            .mouse => |*me| {
                if (me.action == .focus) {
                    const clicked_cell = grid.pointToColRow(me.p);
                    if (clicked_cell) |cell| {
                        self.cursor.col_num = cell.col_num;
                        self.cursor.row_num = cell.row_num;
                    }
                }
            },
            else => {},
        }
        self.enforceCursorLimits();
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
