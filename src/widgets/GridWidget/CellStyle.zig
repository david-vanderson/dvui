//! Provides cell options and widget options for grid cells.
//! styling options can vary by row and column
//!
//! CellStyle structs must provide the following functions:
//! - pub fn cellOptions(self: *const T, col: usize, row: usize) CellOptions
//! - pub fn options(self: *const T, col: usize, row: usize) Options

const dvui = @import("../../dvui.zig");
const GridWidget = dvui.GridWidget;
const CellOptions = GridWidget.CellOptions;
const Cell = GridWidget.Cell;
const Options = dvui.Options;
const Rect = dvui.Rect;

/// The default cell styling provides the same CellOptions
/// and Options to all cells.
/// - cell_opts is used to style the cell
/// - opts is used to style the widgets within the cell.
const CellStyle = @This();

pub const none: CellStyle = .{};

cell_opts: CellOptions = .{},
opts: Options = .{},

/// Returns the cellOptions for this cell. col and row are ignored.
pub fn cellOptions(self: *const CellStyle, cell: Cell) CellOptions {
    _ = cell;
    return self.cell_opts;
}

/// Return widget options for this cell. col and row are ignored.
pub fn options(self: *const CellStyle, cell: Cell) Options {
    _ = cell;
    return self.opts;
}

/// Return a new CellStyle with overridden CellOptions
pub fn cellOptionsOverride(self: *const CellStyle, cell_opts: CellOptions) CellStyle {
    return .{
        .cell_opts = self.cell_opts.override(cell_opts),
        .opts = self.opts,
    };
}

/// Return a new CellStyle with overridden Options
pub fn optionsOverride(self: *const CellStyle, opts: Options) CellStyle {
    return .{
        .cell_opts = self.cell_opts,
        .opts = self.opts.override(opts),
    };
}

/// Allow two CellStyles to be used together.
/// Returns the result of style1.override(style2) for cellOptions() and options()
pub fn Combine(T1: type, T2: type) type {
    return struct {
        const Self = @This();
        style1: T1,
        style2: T2,

        pub fn init(style1: T1, style2: T2) Self {
            return .{ .style1 = style1, .style2 = style2 };
        }

        pub fn cellOptions(self: Self, cell: Cell) CellOptions {
            return self.style1.cellOptions(cell).override(self.style2.cellOptions(cell));
        }

        pub fn options(self: Self, cell: Cell) Options {
            return self.style1.options(cell).override(self.style2.options(cell));
        }
    };
}

/// Banded cell styling.
/// - cell_opts returned for even rows
/// - alt_cell_opts returned for odd rows.
/// - opts is returned for all rows.
pub const Banded = struct {
    const Banding = enum { rows, cols };
    banding: Banding = .rows,
    cell_opts: CellOptions = .{},
    alt_cell_opts: CellOptions = .{},
    opts: Options = .{},

    pub fn cellOptions(self: *const Banded, cell: Cell) CellOptions {
        switch (self.banding) {
            .rows => {
                return if (cell.row_num % 2 == 0)
                    self.cell_opts
                else
                    self.alt_cell_opts;
            },
            .cols => {
                return if (cell.col_num % 2 == 0)
                    self.cell_opts
                else
                    self.alt_cell_opts;
            },
        }
    }

    pub fn cellOptionsOverride(self: *const Banded, cell_opts: CellOptions) Banded {
        return .{
            .banding = self.banding,
            .cell_opts = self.cell_opts.override(cell_opts),
            .alt_cell_opts = self.alt_cell_opts,
            .opts = self.opts,
        };
    }

    pub fn altCellOptionsOverride(self: *const Banded, alt_cell_opts: CellOptions) Banded {
        return .{
            .banding = self.banding,
            .cell_opts = self.cell_opts,
            .alt_cell_opts = self.alt_cell_opts.override(alt_cell_opts),
            .opts = self.opts,
        };
    }

    pub fn options(self: *const Banded, cell: Cell) Options {
        _ = cell;
        return self.opts;
    }

    pub fn optionsOverride(self: *const Banded, opts: Options) Banded {
        return .{
            .banding = self.banding,
            .cell_opts = self.cell_opts,
            .alt_cell_opts = self.alt_cell_opts,
            .opts = self.opts.override(opts),
        };
    }
};

/// Applies the fill_hover colour to all cells on the hovered row.
/// - requires that all rows are the same heights
pub const HoveredRow = struct {
    cell_opts: CellOptions = .{},
    opts: Options = .{},
    // highlighted_row is calculated in processEvents()
    highlighted_row: ?usize = null,

    /// Process mouse position events to find the hovered row.
    /// - scroll_info must be the same as pass to the GriwWidget init_option.
    pub fn processEvents(self: *HoveredRow, grid: *GridWidget) void {
        // Check if a row is being hovered.
        const evts = dvui.events();
        self.highlighted_row = row: {
            for (evts) |*e| {
                if (e.evt == .mouse and
                    e.evt.mouse.action == .position)
                // and
                //dvui.eventMatchSimple(e, grid.data()))
                // TODO: Don't understand why this event match doesn't work.
                // It doesn't really matter as below checks anyway. But is vey strange.
                // This is one for the debugger, whenever I get that working again.
                {
                    // Translate mouse screen position to a logical position relative to the top-left of the grid body.
                    if (grid.pointToCell(e.evt.mouse.p)) |cell| {
                        break :row cell.row_num;
                    }
                }
            }
            break :row null;
        };
    }

    pub fn cellOptions(self: *const HoveredRow, cell: Cell) CellOptions {
        const highlighted_row = self.highlighted_row orelse return self.cell_opts;
        if (cell.row_num != highlighted_row) return self.cell_opts;

        return self.cell_opts.override(.{ .color_fill = self.cell_opts.color_fill_hover });
    }

    pub fn options(self: *const HoveredRow, cell: Cell) Options {
        const highlighted_row = self.highlighted_row orelse return self.opts;
        if (cell.row != highlighted_row) return self.opts;

        return self.opts.override(.{ .color_fill = self.opts.color_fill_hover });
    }

    pub fn cellOptionsOverride(self: *const HoveredRow, cell_opts: CellOptions) HoveredRow {
        return .{
            .cell_opts = self.cell_opts.override(cell_opts),
            .opts = self.opts,
            .highlighted_row = self.highlighted_row,
        };
    }

    pub fn optionsOverride(self: *const HoveredRow, opts: Options) HoveredRow {
        return .{
            .cell_opts = self.cell_opts,
            .opts = self.opts.override(opts),
            .highlighted_row = self.highlighted_row,
        };
    }
};

/// Draw borders around cells.
/// - external is used for any border touching the edge of the grid
/// - internal is used for all other borders
// TODO: Maybe set defaults so it draws a box nicely?
pub const Borders = struct {
    external: Rect,
    internal: Rect,
    num_cols: usize,
    num_rows: usize,
    cell_opts: CellOptions = .{},
    opts: Options = .{},

    pub fn initBox(num_cols: usize, num_rows: usize, border_width: f32) Borders {
        return .{
            .external = Rect.all(border_width),
            .internal = .{ .w = 1, .h = 1 },
            .num_cols = num_cols,
            .num_rows = num_rows,
        };
    }

    pub fn initOutline(num_cols: usize, num_rows: usize, border_width: f32) Borders {
        return .{
            .external = Rect.all(border_width),
            .internal = Rect.all(0),
            .num_cols = num_cols,
            .num_rows = num_rows,
        };
    }

    pub fn cellOptions(self: *const Borders, cell: Cell) CellOptions {
        var border = self.internal;
        if (cell.col_num == 0)
            border.x = self.external.x;
        if (cell.row_num == 0)
            border.y = self.external.y;
        if (cell.row_num == self.num_rows - 1)
            border.h = self.external.h;
        if (cell.col_num == self.num_cols - 1)
            border.w = self.external.w;
        return self.cell_opts.override(.{ .border = border, .background = true });
    }

    pub fn cellOptionsOverride(self: *const Borders, cell_opts: CellOptions) Borders {
        return .{
            .external = self.borders_external,
            .internal = self.borders_internal,
            .color_border = self.border_color,
            .num_cols = self.num_cols,
            .num_rows = self.num_rows,
            .cell_opts = self.cell_opts.override(cell_opts),
            .opts = self.opts,
        };
    }

    pub fn options(self: *const Borders, cell: Cell) Options {
        _ = cell;
        return self.opts;
    }

    pub fn optionsOverride(self: *const Borders, opts: Options) Borders {
        return .{
            .external = self.borders_external,
            .internal = self.borders_internal,
            .color_border = self.border_color,
            .num_cols = self.num_cols,
            .num_rows = self.num_rows,
            .cell_opts = self.cell_opts,
            .opts = self.opts.override(opts),
        };
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
