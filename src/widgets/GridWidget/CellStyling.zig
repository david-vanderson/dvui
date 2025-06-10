/// Provides cell options and widget options for grid cells.
/// styling options can vary by row and column
const dvui = @import("../../dvui.zig");
const CellStyling = @This();
const GridWidget = dvui.GridWidget;
const CellOptions = GridWidget.CellOptions;
const Options = dvui.Options;
const ScrollInfo = dvui.ScrollInfo;

pub const none: CellStyling = .init(.{}, .{});
cell_opts: CellOptions,
opts: Options,

pub fn init(cell_opts: CellOptions, opts: Options) CellStyling {
    return .{
        .cell_opts = cell_opts,
        .opts = opts,
    };
}

pub fn cellOptions(self: *const CellStyling, col: usize, row: usize) CellOptions {
    _ = row;
    _ = col;
    return self.cell_opts;
}

pub fn options(self: *const CellStyling, col: usize, row: usize) Options {
    _ = row;
    _ = col;
    return self.opts;
}

pub fn cellOptionsOverride(self: *const CellStyling, cell_opts: CellOptions) CellStyling {
    return .{
        .cell_opts = self.cell_opts.override(cell_opts),
        .opts = self.opts,
    };
}

pub fn optionsOverride(self: *const CellStyling, opts: Options) CellStyling {
    return .{
        .cell_opts = self.cell_opts,
        .opts = self.opts.override(opts),
    };
}

// Returns cell_opts for even rows and alt_cell_opts for odd rows.
pub const Banded = struct {
    const Banding = enum { rows, cols };
    banding: Banding,
    alt_cell_opts: CellOptions,
    cell_opts: CellOptions,
    opts: Options,

    pub fn init(banding: Banding, cell_opts: CellOptions, alt_cell_opts: CellOptions, opts: Options) Banded {
        return .{
            .banding = banding,
            .cell_opts = cell_opts,
            .opts = opts,
            .alt_cell_opts = alt_cell_opts,
        };
    }

    pub fn cellOptions(self: *const Banded, col: usize, row: usize) CellOptions {
        switch (self.banding) {
            .rows => {
                return if (row % 2 == 0)
                    self.cell_opts
                else
                    self.alt_cell_opts;
            },
            .cols => {
                return if (col % 2 == 0)
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

    pub fn options(self: *const Banded, col: usize, row: usize) Options {
        _ = row;
        _ = col;
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

/// Applies the fill_hover colour to all cels on the hovered row.
/// - scroll_info must be the same scroll_info passed to the GridWidget init_option.
/// - requires that all rows are the same height.
pub const HoveredRow = struct {
    cell_opts: CellOptions,
    opts: Options,
    highlighted_row: ?usize,

    pub fn init(grid: *GridWidget, scroll_info: *ScrollInfo, cell_opts: CellOptions, opts: Options) HoveredRow {

        // Check if a row is being hovered.
        const evts = dvui.events();
        const highlighted_row: ?usize = row: {
            for (evts) |*e| {
                if (dvui.eventMatchSimple(e, grid.data()) and
                    (e.evt == .mouse and e.evt.mouse.action == .position) and
                    (grid.row_height > 1))
                {
                    // Translate mouse screen position to a logical position relative to the top-left of the grid body.
                    if (grid.pointToBodyRelative(e.evt.mouse.p)) |point| {
                        break :row @intFromFloat((scroll_info.viewport.y + point.y) / grid.row_height);
                    }
                }
            }
            break :row null;
        };

        return .{
            .cell_opts = cell_opts,
            .opts = opts,
            .highlighted_row = highlighted_row,
        };
    }

    pub fn cellOptions(self: *const HoveredRow, col: usize, row: usize) CellOptions {
        _ = col;
        const highlighted_row = self.highlighted_row orelse return self.cell_opts;
        if (row != highlighted_row) return self.cell_opts;

        var result = self.cell_opts;
        result.color_fill = result.color_fill_hover;
        return result;
    }

    pub fn options(self: *const HoveredRow, col: usize, row: usize) Options {
        _ = col;
        const highlighted_row = self.highlighted_row orelse return self.opts;
        if (row != highlighted_row) return self.opts;

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
        };
    }
};
