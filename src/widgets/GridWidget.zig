//! A scrollable grid widget for displaying tabular data.
//! Features:
//!  - Optional headers.
//!  - Consistent or variable row heights.
//!  - Horizontal and vertical scrolling.
//!  - Individual cell styling.
//!
//! If `var_row_heights` is false, rows and columns can be laid out in any order,
//! including sparse layouts where not all rows or columns are provided.
//!
//! If `var_row_heights` is true, rows must be laid out sequentially—either:
//!  1. All rows for a column before moving to the next column, or
//!  2. All columns for a row before moving to the next row.
//!
//! See also:
//!  - `CellStyle`: helpers to style grid cells and widgets.
//!  - `HeaderResizeWidget`: draggable header resizing.
//!  - `VirtualScroller`: virtual scrolling through large datasets.

const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const ColorOrName = Options.ColorOrName;
const Rect = dvui.Rect;
const Size = dvui.Size;
const Point = dvui.Point;
const Direction = dvui.enums.Direction;
const Cursor = dvui.enums.Cursor;
const MaxSize = Options.MaxSize;
const ScrollInfo = dvui.ScrollInfo;
const WidgetData = dvui.WidgetData;
const Event = dvui.Event;
const BoxWidget = dvui.BoxWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const ScrollContainerWidget = dvui.ScrollContainerWidget;
const ScrollBarWidget = dvui.ScrollBarWidget;

pub const CellStyle = @import("GridWidget/CellStyle.zig");
const GridWidget = @This();

pub var defaults: Options = .{
    .name = "GridWidget",
    .background = true,
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
    // Small padding to separate first column from left edge of the grid
    .padding = .{ .x = 5 },
};

pub var scrollbar_padding_defaults: Size = .{ .h = 10, .w = 10 };

pub const CellOptions = struct {
    // Set the height or width of a cell.
    // height is ignored unless var_row_heights = true.
    // width is ignored when col_widths is supplied to init_opts.
    size: ?Size = null,
    margin: ?Rect = null,
    border: ?Rect = null,
    padding: ?Rect = null,
    background: ?bool = null,
    color_fill: ?ColorOrName = null,
    color_fill_hover: ?ColorOrName = null,
    color_border: ?ColorOrName = null,

    pub fn height(self: *const CellOptions) f32 {
        return if (self.size) |size| size.h else 0;
    }

    pub fn width(self: *const CellOptions) f32 {
        return if (self.size) |size| size.w else 0;
    }

    pub fn toOptions(self: *const CellOptions) Options {
        return .{
            // does not convert size
            .margin = self.margin,
            .border = self.border,
            .padding = self.padding,
            .background = self.background,
            .color_fill = self.color_fill,
            .color_fill_hover = self.color_fill_hover,
            .color_border = self.color_border,
        };
    }

    pub fn override(self: *const CellOptions, over: CellOptions) CellOptions {
        var ret = self.*;

        inline for (@typeInfo(CellOptions).@"struct".fields) |f| {
            if (@field(over, f.name)) |fval| {
                @field(ret, f.name) = fval;
            }
        }

        return ret;
    }
};

pub const SortDirection = enum {
    unsorted,
    ascending,
    descending,

    pub fn reverse(dir: SortDirection) SortDirection {
        return switch (dir) {
            .descending => .ascending,
            else => .descending,
        };
    }
};

pub const InitOpts = struct {
    // Scroll options for the grid body
    scroll_opts: ?ScrollAreaWidget.InitOpts = null,
    // Recalculate row heights. Only set this when row heights could have changed, .e.g on column resize.
    resize_rows: bool = false,
    // Only used when cols.num is specified. Allows col widths to shrink this frame.
    resize_cols: bool = false,
    // If var row heights is set to false, size.h is ignored.
    // When using var row heights row_nr must be populated sequentially for each column when creating bodyCells.
    var_row_heights: bool = false,
};

pub const WidthsOrNum = union(enum) {
    col_widths: []f32,
    num_cols: usize,

    pub fn colWidths(col_widths: []f32) WidthsOrNum {
        return .{ .col_widths = col_widths };
    }

    pub fn numCols(num: usize) WidthsOrNum {
        return .{ .num_cols = num };
    }
};

pub const default_col_width: f32 = 100;

//Widgets
vbox: BoxWidget = undefined,
scroll: ScrollAreaWidget = undefined, // main scroll area
hscroll: ?ScrollAreaWidget = null, // header scroll area
bscroll: ?ScrollContainerWidget = null, // body scroll container
bbox: BoxWidget = undefined, // has the same lifetime as bscroll.

// Not valid until after install()
hsi: ScrollInfo = undefined, // Header scroll info
bsi: *ScrollInfo = undefined, // Body scroll info
frame_viewport: Point = undefined, // Fixed scroll viewport for this frame
col_widths: []f32 = undefined, // Internal or user-supplied column widths
starting_col_widths: ?[]f32 = null, // If grid is storing col widths, keep a copy of the starting widths.

// Persistent state
resizing: bool = false, // true when row height is being recalculated
last_size: Size = .zero, // virtual height of the grid body for the previous frame
header_height: f32 = 0,
last_row_height: f32 = 0, // row height last frame
sort_direction: SortDirection = .unsorted,
sort_col_number: usize = 0,
default_scroll_info: ScrollInfo = .{},

// Non-persistent state
cols: WidthsOrNum = undefined,
row_height: f32 = 0,
max_row: usize = 0,
cur_row: usize = std.math.maxInt(usize), // current row being rendered
rows_y_offset: f32 = 0, // y value to offset rendering of the first body cell
next_row_y: f32 = 0, // Next y position for laying out rows with variable heights
this_row_y: f32 = 0, // This y position for laying out rows with variable heights

// Options
init_opts: InitOpts = undefined,

pub fn init(src: std.builtin.SourceLocation, cols: WidthsOrNum, init_opts: InitOpts, opts: Options) GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    self.cols = cols;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .{ .dir = .vertical }, options);
    if (dvui.dataGet(null, self.data().id, "_last_size", Size)) |last_size| {
        self.last_size = last_size;
    }
    if (dvui.dataGet(null, self.data().id, "_resizing", bool)) |resizing| {
        self.resizing = resizing;
    }
    if (dvui.dataGet(null, self.data().id, "_header_height", f32)) |header_height| {
        self.header_height = header_height;
    }
    if (dvui.dataGet(null, self.data().id, "_row_height", f32)) |row_height| {
        self.last_row_height = row_height;
        self.row_height = row_height;
    }
    if (dvui.dataGet(null, self.data().id, "_sort_col", usize)) |sort_col| {
        self.sort_col_number = sort_col;
    }
    if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
        self.sort_direction = sort_direction;
    }
    if (dvui.dataGet(null, self.data().id, "_hsi", ScrollInfo)) |hsi| {
        self.hsi = hsi;
    } else {
        self.hsi = .{ .horizontal = .auto, .vertical = .none };
    }
    if (dvui.dataGet(null, self.data().id, "_default_si", ScrollInfo)) |default_si| {
        self.default_scroll_info = default_si;
    }

    // Ensure resize on first initialization.
    if (dvui.firstFrame(self.data().id)) {
        self.resizing = true;
    }
    if (init_opts.resize_rows or self.resizing) {
        self.row_height = 0;
        dvui.refresh(null, @src(), self.data().id);
    }

    return self;
}

// Default col_widths slice to use if allocation fails this frame.
var oom_col_width: [1]f32 = .{0};

pub fn install(self: *GridWidget) void {
    // Set the self.col_widths slice to point to the user-supplied col_widths or the
    // internally stored col_widths.
    blk: {
        switch (self.cols) {
            .num_cols => |num_cols| {
                if (dvui.dataGetSlice(null, self.data().id, "_col_widths", []f32)) |col_widths| {
                    if (col_widths.len == num_cols) {
                        self.col_widths = col_widths;
                        if (self.init_opts.resize_cols) {
                            @memset(self.col_widths, 0);
                        }
                        break :blk;
                    }
                }
                // If there are no saved col_widths or the number of columns has changed.
                self.col_widths = dvui.currentWindow().arena().alloc(f32, num_cols) catch |err| default: {
                    dvui.logError(@src(), err, "GridWidget {x} could not allocate column widths", .{self.data().id});
                    dvui.currentWindow().debug_widget_id = self.data().id;
                    break :default &oom_col_width;
                };
                @memset(self.col_widths, 0);
            },
            .col_widths => |col_widths| {
                self.col_widths = col_widths;
            },
        }
    }
    // If the grid is keep track of col widths then keep a copy of the starting col widths.
    if (self.cols == .num_cols) {
        self.starting_col_widths = dvui.currentWindow().arena().alloc(f32, self.col_widths.len) catch |err| default: {
            dvui.logError(@src(), err, "GridWidget {x} could not allocate column widths", .{self.data().id});
            dvui.currentWindow().debug_widget_id = self.data().id;
            break :default null;
        };
        if (self.starting_col_widths) |starting| {
            @memcpy(starting, self.col_widths);
        }
    }
    if (self.init_opts.scroll_opts) |*scroll_opts| {
        if (scroll_opts.scroll_info) |scroll_info| {
            self.bsi = scroll_info;
        } else {
            self.bsi = &self.default_scroll_info;
            scroll_opts.scroll_info = self.bsi;
            // Move the .horizontal and .vertical settings from scroll_opts to scroll_info
            self.bsi.horizontal = scroll_opts.horizontal orelse .none;
            self.bsi.vertical = scroll_opts.vertical orelse .auto;
            scroll_opts.horizontal = null;
            scroll_opts.vertical = null;
        }
    } else {
        self.bsi = &self.default_scroll_info;
    }

    self.frame_viewport = self.bsi.viewport.topLeft();

    self.vbox.install();
    self.vbox.drawBackground();

    const scroll_opts: ScrollAreaWidget.InitOpts = self.init_opts.scroll_opts orelse .{ .frame_viewport = self.frame_viewport, .scroll_info = self.bsi };
    self.scroll = ScrollAreaWidget.init(
        @src(),
        scroll_opts,
        .{
            .name = "GridWidgetScrollArea",
            .expand = .both,
        },
    );
    self.scroll.installScrollBars();
}

pub fn deinit(self: *GridWidget) void {
    defer self.* = undefined;
    defer dvui.widgetFree(self);

    if (self.hsi.viewport.x != self.frame_viewport.x) self.hsi.viewport.x = self.bsi.viewport.x;

    // resizing if row heights changed or a resize was requested via init options.
    self.resizing =
        self.init_opts.resize_rows or
        !std.math.approxEqAbs(f32, self.row_height, self.last_row_height, 0.01);

    const max_row_f: f32 = @floatFromInt(self.max_row);
    const this_height: f32 = if (self.init_opts.var_row_heights) self.next_row_y else (max_row_f + 1) * self.row_height;
    const this_size: Size = .{ .h = this_height, .w = self.totalWidth() };

    if (self.resizing or
        self.init_opts.resize_cols or
        !this_size.eq(self.last_size))
    {
        dvui.refresh(null, @src(), self.data().id);
    }

    if (self.hscroll) |*hscroll| {
        hscroll.deinit();
    }

    if (self.bscroll) |*bscroll| {
        self.bbox.deinit();
        bscroll.deinit();
    }
    self.scroll.deinit();
    dvui.dataSet(null, self.data().id, "_last_size", this_size);
    dvui.dataSet(null, self.data().id, "_header_height", self.header_height);
    dvui.dataSet(null, self.data().id, "_resizing", self.resizing);
    dvui.dataSet(null, self.data().id, "_row_height", self.row_height);
    dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
    dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);
    dvui.dataSet(null, self.data().id, "_hsi", self.hsi);
    if (self.bsi == &self.default_scroll_info) {
        dvui.dataSet(null, self.data().id, "_default_si", self.default_scroll_info);
    }
    if (self.cols == .num_cols) {
        dvui.dataSetSlice(null, self.data().id, "_col_widths", self.col_widths);
    }

    self.vbox.deinit();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.vbox.wd;
}

/// Create a header cell for the requested column
/// Returns a hbox for the created cell.
/// - deinit() must be called on this hbox before any new cells are created.
/// - header cells can be created in any order, but it is more efficient to create them from left to right.
/// - no header cells should be created after the first body cell is created.
pub fn headerCell(self: *GridWidget, src: std.builtin.SourceLocation, col_num: usize, opts: CellOptions) *BoxWidget {
    if (self.hscroll == null) {
        if (self.bscroll != null) {
            dvui.log.debug("GridWidget {x} all header cells must be created before any body cells. Header will be placed in body.\n", .{self.data().id});
            dvui.currentWindow().debug_widget_id = self.bscroll.?.data().id;
        } else {
            self.headerScrollAreaCreate();
        }
    }
    const header_width: f32 = width: {
        if (opts.width() > 0) {
            break :width opts.width();
        } else {
            break :width self.colWidth(col_num);
        }
    };
    const header_height: f32 = height: {
        if (opts.height() > 0) {
            break :height opts.height();
        } else {
            break :height if (self.resizing) 0 else self.header_height;
        }
    };
    var cell_opts = opts.toOptions();
    const pos_x = self.posX(col_num);
    cell_opts.rect = .{ .x = pos_x, .y = 0, .w = header_width, .h = header_height };
    cell_opts.id_extra = col_num;

    // Create the cell and install as parent.
    var cell = dvui.widgetAlloc(BoxWidget);
    cell.* = BoxWidget.init(src, .{ .dir = .horizontal }, cell_opts);
    cell.install();
    cell.drawBackground();
    const first_frame = dvui.firstFrame(cell.data().id);
    // Determine heights for next frame.
    if (!first_frame) {
        const cell_size = cell.data().rect.size();
        self.header_height = @max(self.header_height, cell_size.h);
        self.colWidthSet(col_num, cell_size.w);
    }
    return cell;
}

/// Create a body cell for the requested column and row
/// Returns a hbox for the created cell.
/// - deinit() must be called on this hbox before any new body cells are created.
///
/// If var_row_heights is false:
///   - body cells can be created using any order or col_num row_num
/// if var_row_heights is true then either:
///   - All rows for a column must be created in ascending row order.
///   - All columns for a row must be created before creating moving to the next row.
pub fn bodyCell(self: *GridWidget, src: std.builtin.SourceLocation, col_num: usize, row_num: usize, opts: CellOptions) *BoxWidget {
    if (row_num < self.cur_row) {
        self.this_row_y = self.rows_y_offset;
        self.next_row_y = self.rows_y_offset;
        self.cur_row = row_num;
    } else if (row_num > self.cur_row) {
        self.this_row_y = self.next_row_y;
        self.cur_row = row_num;
    }
    self.max_row = @max(self.max_row, row_num);
    if (self.bscroll == null) {
        self.bodyScrollContainerCreate(src);
    }
    const cell_width = width: {
        if (opts.width() > 0) {
            break :width opts.width();
        } else {
            break :width self.colWidth(col_num);
        }
    };
    const cell_height: f32 = height: {
        if (self.init_opts.var_row_heights and opts.height() > 0) {
            break :height opts.height();
        } else {
            break :height if (self.resizing) 0 else self.row_height;
        }
    };

    const row_num_f: f32 = @floatFromInt(row_num);
    const pos_x = self.posX(col_num);
    const pos_y = if (self.init_opts.var_row_heights) self.this_row_y else self.row_height * row_num_f;
    var cell_opts = opts.toOptions();
    cell_opts.rect = .{ .x = pos_x, .y = pos_y, .w = cell_width, .h = cell_height };

    // To support being called in a loop, combine col and row numbers as id_extra.
    // 9_223_372_036_854_775K cols should be enough for anybody.
    cell_opts.id_extra = (col_num << @bitSizeOf(usize) / 2) | row_num;

    var cell = dvui.widgetAlloc(BoxWidget);
    cell.* = BoxWidget.init(src, .{ .dir = .horizontal }, cell_opts);
    cell.install();
    cell.drawBackground();
    const first_frame = dvui.firstFrame(cell.data().id);
    // Determine heights for next frame.
    if (!first_frame) {
        const cell_size = cell.data().rect.size();
        self.row_height = @max(self.row_height, cell_size.h);
        self.colWidthSet(col_num, cell_size.w);
    }
    self.next_row_y = @max(self.next_row_y, self.this_row_y + if (opts.height() > 0) opts.height() else self.row_height);

    return cell;
}

/// Set the starting y value in the scroll container to begin rendering rows.
/// Can be used to set the start of rendering if virtual scrolling using variable row heights.
pub fn offsetRowsBy(self: *GridWidget, offset: f32) void {
    self.rows_y_offset = offset;
}

/// Converts a physical point (e.g. a mouse position) into a logical point
/// relative to the top-left of the grid's body.
/// Return the logical point if it is located within the grid body,
/// otherwise return null.
pub fn pointToBodyRelative(self: *GridWidget, point: Point.Physical) ?Point {
    const scroll_wd = self.scroll.data();
    var result = scroll_wd.rectScale().pointFromPhysical(point);
    if (scroll_wd.rect.contains(result) and result.y >= self.header_height) {
        result.y -= self.header_height;
        return result;
    }
    return null;
}

/// Set the grid's sort order when manually managing column sorting.
pub fn colSortSet(self: *GridWidget, col_num: usize, dir: SortDirection) void {
    self.sort_col_number = col_num;
    self.sort_direction = dir;
}

/// For automatic management of sort order, this must be called whenever
/// the sort order for any column has changed.
pub fn sortChanged(self: *GridWidget, col_num: usize) void {
    // If sorting on a new column, change current sort column to unsorted.
    if (col_num != self.sort_col_number) {
        self.sort_direction = .unsorted;
        self.sort_col_number = col_num;
    }
    // If new sort column, then ascending, otherwise opposite of current sort.
    self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
}

/// Returns the sort order for the current column.
pub fn colSortOrder(self: *const GridWidget, col_num: usize) SortDirection {
    if (col_num == self.sort_col_number) {
        return self.sort_direction;
    } else {
        return .unsorted;
    }
}

/// Returns the width of the requested column
pub fn colWidth(self: *GridWidget, col_num: usize) f32 {
    if (col_num >= self.col_widths.len) {
        dvui.log.debug("GridWidget {x} col_num {d} is greater than number of columns {d} using default col_width\n", .{ self.data().id, col_num, self.col_widths.len });
        return default_col_width;
    }
    if (self.starting_col_widths) |starting_col_widths| {
        return starting_col_widths[col_num];
    } else {
        return self.col_widths[col_num];
    }
}

/// Sets the column width of the requested column, only if the user didn't
/// supply their own col_widths slice. Otherwise ignore the change.
pub fn colWidthSet(self: *GridWidget, col_num: usize, width: f32) void {
    if (col_num >= self.col_widths.len) {
        dvui.log.debug("GridWidget {x} col_num {d} is greater than number of columns {d} ignoring col_width change\n", .{ self.data().id, col_num, self.col_widths.len });
        return;
    }
    if (self.cols == .num_cols) {
        self.col_widths[col_num] = @max(self.col_widths[col_num], width);
    }
}

/// Returns the x position of the requested column
pub fn posX(self: *GridWidget, col_num: usize) f32 {
    const end = @min(col_num, self.col_widths.len);
    var total: f32 = 0;
    for (self.col_widths[0..end]) |w| {
        total += w;
    }
    return total;
}

/// Returns the total width of all columns
pub fn totalWidth(self: *GridWidget) f32 {
    var total: f32 = 0;
    for (self.col_widths) |w| {
        total += w;
    }
    return total;
}

fn headerScrollAreaCreate(self: *GridWidget) void {
    if (self.hscroll == null) {
        self.hscroll = ScrollAreaWidget.init(@src(), .{
            .horizontal_bar = .hide,
            .vertical_bar = .hide,
            .scroll_info = &self.hsi,
            .frame_viewport = .{ .x = self.frame_viewport.x },
        }, .{
            .name = "GridWidgetHeaderScroll",
            .expand = .horizontal,
            .min_size_content = .{ .h = self.header_height, .w = self.totalWidth() },
        });
        self.hscroll.?.install();
    }

    // Any scroll-wheel events in the header should be applied to the body instead.
    const events = dvui.events();
    for (events) |*e| {
        if (e.evt == .mouse and dvui.eventMatchSimple(e, self.hscroll.?.data())) {
            const me = e.evt.mouse;
            if (me.action == .wheel_y) {
                e.handle(@src(), self.data());
                self.bsi.scrollByOffset(.vertical, -me.action.wheel_y);
            } else if (me.action == .wheel_x) {
                e.handle(@src(), self.data());
                self.bsi.scrollByOffset(.horizontal, me.action.wheel_x);
            }
        }
    }
}

fn bodyScrollContainerCreate(self: *GridWidget, src: std.builtin.SourceLocation) void {
    // Finished with headers.
    if (self.hscroll) |*hscroll| {
        hscroll.deinit();
        self.hscroll = null;
    }

    if (self.bscroll == null) {
        self.bscroll = ScrollContainerWidget.init(
            src,
            self.bsi,
            .{ .frame_viewport = self.frame_viewport },
            .{
                .name = "GridWidgetBodyScroll",
                .expand = .both,
            },
        );
        self.bscroll.?.install();
        self.bscroll.?.processEvents();
        self.bscroll.?.processVelocity();

        // This box is used to set the size of the scrollable area in the scroll container.
        self.bbox = BoxWidget.init(@src(), .{ .dir = .horizontal }, .{
            .min_size_content = self.last_size,
        });
        self.bbox.install();
    }
}

/// Provides vitrual scrolling for a grid so that only the visibile rows are rendered.
/// GridVirtualScroller requires that a scroll_info has been passed as an init_option
/// to the GridBodyWidget.
/// Note: Requires that all rows are the same height for the entire grid, including rows
/// not yet displayed. It is highly recommended to supply the row height to each cell
/// when using the virtual scroller.
pub const VirtualScroller = struct {
    pub const InitOpts = struct {
        // Total number of rows in the underlying dataset
        total_rows: usize,
        scroll_info: *ScrollInfo,
    };
    grid: *GridWidget,
    si: *ScrollInfo,
    total_rows: usize,
    pub fn init(grid: *GridWidget, init_opts: VirtualScroller.InitOpts) VirtualScroller {
        const si = init_opts.scroll_info;
        const total_rows_f: f32 = @floatFromInt(init_opts.total_rows);
        si.virtual_size.h = @max(total_rows_f * grid.row_height + scrollbar_padding_defaults.h, si.viewport.h);

        return .{
            .grid = grid,
            .si = si,
            .total_rows = init_opts.total_rows,
        };
    }

    /// Return the first row to render (inclusive)
    pub fn startRow(self: *const VirtualScroller) usize {
        if (self.grid.row_height < 1) {
            return 0;
        }
        const first_row_in_viewport: usize = @intFromFloat(@round(self.grid.frame_viewport.y / self.grid.row_height));

        if (first_row_in_viewport == 0 or self.total_rows == 0) {
            return 0;
        }
        return @min(first_row_in_viewport - 1, self.total_rows - 1);
    }

    /// Return the end row to render (exclusive)
    /// Can be used as slice[startRow()..endRow()]
    pub fn endRow(self: *const VirtualScroller) usize {
        const last_row_in_viewport: usize =
            if (self.grid.row_height < 1)
                0
            else
                @intFromFloat(@round((self.grid.frame_viewport.y + self.si.viewport.h) / self.grid.row_height));
        return @min(last_row_in_viewport + 1, self.total_rows);
    }
};

/// Provides a draggable separator between columns
/// size must be a pointer into the same col_widths slice
/// passed to the GridWidget init_option.
pub const HeaderResizeWidget = struct {
    pub const InitOptions = struct {
        // Input and output width (.vertical) or height (.horizontal)
        sizes: []f32,
        num: usize,
        // clicking on these extra pixels before/after (.vertical)
        // or above/below (.horizontal) the handle also counts
        // as clicking on the handle.
        grab_tolerance: f32 = 5,
        // Will not resize to less than this value
        min_size: ?f32 = null,
        // Will not resize to more than this value
        max_size: ?f32 = null,
        // The total width of all columns will not exceed this value.
        max_size_total: ?f32 = null,

        pub const fixed: ?InitOptions = null;
    };

    const defaults: Options = .{
        .name = "GridHeaderResize",
        .background = true, // TODO: remove this when border and background are no longer coupled
        .color_fill = .{ .name = .border },
        .min_size_content = .{ .w = 1, .h = 1 },
    };

    wd: WidgetData = undefined,
    direction: Direction = undefined,
    init_opts: InitOptions = undefined,
    // When user drags less than min_size or more than max_size
    // this offset is used to make them return the mouse back
    // to the min/max size before resizing can start again.
    offset: Point = .{},

    pub fn init(src: std.builtin.SourceLocation, dir: Direction, init_options: InitOptions, opts: Options) HeaderResizeWidget {
        var self = HeaderResizeWidget{};

        var widget_opts = HeaderResizeWidget.defaults.override(opts);
        widget_opts.expand = switch (dir) {
            .horizontal => .horizontal,
            .vertical => .vertical,
        };
        self.direction = dir;
        self.init_opts = init_options;
        self.wd = WidgetData.init(src, .{}, widget_opts);

        if (dvui.dataGet(null, self.wd.id, "_offset", Point)) |offset| {
            self.offset = offset;
        }

        return self;
    }

    pub fn install(self: *HeaderResizeWidget) void {
        self.wd.register();
        self.wd.borderAndBackground(.{});
    }

    pub fn size(self: *HeaderResizeWidget) f32 {
        if (self.init_opts.num < self.init_opts.sizes.len)
            return self.init_opts.sizes[self.init_opts.num]
        else
            return 0;
    }

    pub fn sizeOf(self: *HeaderResizeWidget, col_num: usize) f32 {
        if (col_num < self.init_opts.sizes.len)
            return self.init_opts.sizes[col_num]
        else
            return 0;
    }

    pub fn sizeSet(self: *HeaderResizeWidget, s: f32) void {
        if (self.init_opts.num < self.init_opts.sizes.len)
            self.init_opts.sizes[self.init_opts.num] = s;
    }

    pub fn sizeTotal(self: *HeaderResizeWidget) f32 {
        var total: f32 = switch (self.direction) {
            .vertical => scrollbar_padding_defaults.w,
            .horizontal => scrollbar_padding_defaults.h,
        };
        for (self.init_opts.sizes) |s| {
            total += s;
        }
        return total;
    }

    pub fn matchEvent(self: *HeaderResizeWidget, e: *Event) bool {
        var rs = self.wd.rectScale();

        // Clicking near the handle counts as clicking on the handle.
        const grab_extra = self.init_opts.grab_tolerance * rs.s;
        switch (self.direction) {
            .vertical => {
                rs.r.x -= grab_extra;
                rs.r.w += grab_extra;
            },
            .horizontal => {
                rs.r.y -= grab_extra;
                rs.r.h += grab_extra;
            },
        }
        return dvui.eventMatch(e, .{ .id = self.wd.id, .r = rs.r });
    }

    pub fn processEvents(self: *HeaderResizeWidget) void {
        const evts = dvui.events();
        for (evts) |*e| {
            if (!self.matchEvent(e))
                continue;

            self.processEvent(e, false);
        }
    }

    pub fn data(self: *HeaderResizeWidget) *WidgetData {
        return &self.wd;
    }

    pub fn processEvent(self: *HeaderResizeWidget, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.evt == .mouse) {
            const rs = self.wd.rectScale();
            const cursor: Cursor = switch (self.direction) {
                .vertical => .arrow_w_e,
                .horizontal => .arrow_n_s,
            };

            if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // capture and start drag
                dvui.captureMouse(self.data());
                dvui.dragPreStart(e.evt.mouse.p, .{ .cursor = cursor });
                self.offset = .{};
            } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                e.handle(@src(), self.data());
                // stop possible drag and capture
                dvui.captureMouse(null);
                dvui.dragEnd();
                self.offset = .{};
            } else if (e.evt.mouse.action == .motion and dvui.captured(self.wd.id)) {
                e.handle(@src(), self.data());
                // move if dragging
                if (dvui.dragging(e.evt.mouse.p)) |dps| {
                    dvui.refresh(null, @src(), self.wd.id);
                    const unclamped_size =
                        switch (self.direction) {
                            .vertical => self.size() + dps.x / rs.s + self.offset.x,
                            .horizontal => self.size() + dps.y / rs.s + self.offset.y,
                        };
                    const clamped_size = std.math.clamp(
                        unclamped_size,
                        self.init_opts.min_size orelse 1,
                        self.init_opts.max_size orelse dvui.max_float_safe,
                    );
                    const new_size = blk: {
                        if (self.init_opts.max_size_total) |total_size| {
                            // TODO: Make this less confusing!
                            const overcommit = @max(self.sizeTotal() - self.size() + clamped_size - total_size, 0);
                            break :blk @max(clamped_size - overcommit, self.init_opts.min_size orelse 1);
                        } else {
                            break :blk clamped_size;
                        }
                    };
                    self.sizeSet(new_size);
                    switch (self.direction) {
                        .vertical => self.offset.x = new_size - self.size(),
                        .horizontal => self.offset.y = new_size - self.size(),
                    }
                }
            } else if (e.evt.mouse.action == .position) {
                dvui.cursorSet(cursor);
            }
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *HeaderResizeWidget) void {
        dvui.dataSet(null, self.wd.id, "_offset", self.offset);
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        self.* = undefined;
    }
};
test {
    // TODO: Don't include grid tests yet.
    _ = @import("GridWidget/testing.zig");
    @import("std").testing.refAllDecls(@This());
}
