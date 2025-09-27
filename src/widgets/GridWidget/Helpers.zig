pub fn grid(src: std.builtin.SourceLocation, cols: GridWidget.WidthsOrNum, init_opts: GridWidget.InitOpts, opts: Options) *GridWidget {
    const ret = dvui.widgetAlloc(GridWidget);
    ret.* = GridWidget.init(src, cols, init_opts, opts);
    ret.init_opts.was_allocated_on_widget_stack = true;
    ret.install();
    return ret;
}

/// Create either a draggable separator (resize_options != null)
/// or a standard separator (resize_options = null) for a grid heading.
pub fn gridHeadingSeparator(resize_options: ?GridWidget.HeaderResizeWidget.InitOptions) void {
    if (resize_options) |resize_opts| {
        var handle: GridWidget.HeaderResizeWidget = .init(
            @src(),
            .vertical,
            resize_opts,
            .{ .gravity_x = 1.0 },
        );
        handle.install();
        handle.processEvents();
        handle.deinit();
    } else {
        _ = dvui.separator(@src(), .{ .expand = .vertical, .gravity_x = 1.0 });
    }
}

/// Create a heading with a static label
pub fn gridHeading(
    src: std.builtin.SourceLocation,
    g: *GridWidget,
    col_num: usize,
    heading: []const u8,
    resize_opts: ?GridWidget.HeaderResizeWidget.InitOptions,
    cell_style: anytype, // GridWidget.CellStyle
) void {
    const label_defaults: Options = .{
        .corner_radius = .all(0),
        .expand = .horizontal,
        .gravity_x = 0.5,
        .gravity_y = 0.5,
        .background = true,
    };
    const opts = if (@TypeOf(cell_style) == @TypeOf(.{})) GridWidget.CellStyle.none else cell_style;

    const label_options = label_defaults.override(opts.options(.colRow(col_num, 0)));
    var cell = g.headerCell(src, col_num, opts.cellOptions(.colRow(col_num, 0)));
    defer cell.deinit();

    dvui.labelNoFmt(@src(), heading, .{}, label_options);
    gridHeadingSeparator(resize_opts);
}

/// Create a heading and allow the column to be sorted.
///
/// Returns true if the sort direction has changed.
/// sort_dir is an out parameter containing the current sort direction.
pub fn gridHeadingSortable(
    src: std.builtin.SourceLocation,
    g: *GridWidget,
    col_num: usize,
    heading: []const u8,
    dir: *GridWidget.SortDirection,
    resize_opts: ?GridWidget.HeaderResizeWidget.InitOptions,
    cell_style: anytype, // GridWidget.CellStyle
) bool {
    const icon_ascending = dvui.entypo.chevron_small_up;
    const icon_descending = dvui.entypo.chevron_small_down;

    // Pad buttons with extra space if there is no sort indicator.
    const heading_defaults: Options = .{
        .expand = .horizontal,
        .corner_radius = .all(0),
    };
    const opts = if (@TypeOf(cell_style) == @TypeOf(.{})) GridWidget.CellStyle.none else cell_style;
    const heading_opts = heading_defaults.override(opts.options(.col(col_num)));

    var cell = g.headerCell(src, col_num, opts.cellOptions(.col(col_num)));
    defer cell.deinit();

    gridHeadingSeparator(resize_opts);

    const sort_changed = switch (g.colSortOrder(col_num)) {
        .unsorted => dvui.button(@src(), heading, .{ .draw_focus = false }, heading_opts),
        .ascending => dvui.buttonLabelAndIcon(@src(), heading, icon_ascending, .{ .draw_focus = false }, heading_opts),
        .descending => dvui.buttonLabelAndIcon(@src(), heading, icon_descending, .{ .draw_focus = false }, heading_opts),
    };

    if (sort_changed) {
        g.sortChanged(col_num);
    }
    dir.* = g.sort_direction;
    return sort_changed;
}

/// A grid heading with a checkbox for select-all and select-none
///
/// Returns true if the selection state has changed.
/// selection - out parameter containing the current selection state.
pub fn gridHeadingCheckbox(
    src: std.builtin.SourceLocation,
    g: *GridWidget,
    col_num: usize,
    select_state: *dvui.selection.SelectAllState,
    cell_style: anytype, // GridWidget.CellStyle
) bool {
    const header_defaults: Options = .{
        .background = true,
        .expand = .both,
        .margin = dvui.ButtonWidget.defaults.marginGet(),
        .gravity_x = 0.5,
        .gravity_y = 0.5,
    };

    const opts = if (@TypeOf(cell_style) == @TypeOf(.{})) GridWidget.CellStyle.none else cell_style;

    const header_options = header_defaults.override(opts.options(.col(col_num)));
    var checkbox_opts: Options = header_options.strip();
    checkbox_opts.padding = dvui.ButtonWidget.defaults.paddingGet();
    checkbox_opts.gravity_x = header_options.gravity_x;
    checkbox_opts.gravity_y = header_options.gravity_y;

    var cell = g.headerCell(src, col_num, opts.cellOptions(.col(col_num)));
    defer cell.deinit();

    var is_clicked = false;
    var selected = select_state.* == .select_all;
    {
        _ = dvui.separator(@src(), .{ .expand = .vertical, .gravity_x = 1.0 });

        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, header_options);
        defer hbox.deinit();

        is_clicked = dvui.checkbox(@src(), &selected, null, checkbox_opts);
    }
    if (is_clicked) {
        select_state.* = if (selected) .select_all else .select_none;
    }
    return is_clicked;
}

/// Size columns widths using ratios.
///
/// Positive widths are treated as fixed widths and are not modified.
/// Negative widths are treated as ratios and are replaced by a calculated width.
/// Results are returned in col_widths, which will always be positive (or zero) values.
/// If content_width is larger than the grid's visible area, horizontal scrolling should be enabled via the grid's init_opts.
///
/// Examples:
/// To lay out three columns with equal widths, use the same negative ratio for each column:
///     { -1, -1, -1 } or { -0.33, -0.33, -0.33 }
/// To make the second column with twice the width of the first, use a negative ratio twice as large.
///     {-1, -2 } or { -50, -100 }
/// To lay out a fixed column width with all other columns sharing the remaining, use a positive width for the fixed column and
/// the same negative ratio for the variable columns.
///     { -1, 50, -1 }.
pub fn columnLayoutProportional(ratio_widths: []const f32, col_widths: []f32, content_width: f32) void {
    const scroll_bar_w: f32 = GridWidget.scrollbar_padding_defaults.w;
    std.debug.assert(ratio_widths.len == col_widths.len); // input and output slices must be the same length

    // Count all of the positive widths as reserved widths.
    // Total all of the negative widths.
    const reserved_w, const ratio_w_total: f32 = blk: {
        var res_width: f32 = 0;
        var total_ratio_w: f32 = 0;
        for (ratio_widths) |w| {
            if (w <= 0) {
                total_ratio_w += -w;
            } else {
                res_width += w;
            }
        }
        break :blk .{ res_width, total_ratio_w };
    };
    const available_w = content_width - reserved_w - scroll_bar_w;

    // For each negative width, replace it width a positive calculated width.
    for (col_widths, ratio_widths) |*col_w, ratio_w| {
        if (ratio_w <= 0) {
            col_w.* = -ratio_w / ratio_w_total * available_w;
        } else {
            col_w.* = ratio_w;
        }
    }
}

const std = @import("std");
const dvui = @import("../../dvui.zig");

const GridWidget = dvui.GridWidget;
const Options = dvui.Options;
