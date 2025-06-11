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
const ScrollBarWidget = dvui.ScrollBarWidget;

const GridWidget = @This();

pub var defaults: Options = .{
    .name = "GridWidget",
    .background = true,
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
    // Small padding to separate first column from left edge of the grid
    .padding = .{ .x = 5 },
};

pub var scrollbar_padding_defaults: Size = .{ .h = 10, .w = 10 };

pub const ColOptions = struct {
    width: ?f32 = null,
    border: ?Rect = null,
    background: ?bool = null,
    color_fill: ?ColorOrName = null,
    color_border: ?ColorOrName = null,

    pub fn toOptions(self: *const ColOptions) Options {
        return .{
            // height is not converted
            .border = self.border,
            .background = self.background,
            .color_fill = self.color_fill,
            .color_border = self.color_border,
        };
    }
};

pub const CellOptions = struct {
    height: ?f32 = null,
    margin: ?Rect = null,
    border: ?Rect = null,
    padding: ?Rect = null,
    background: ?bool = null,
    color_fill: ?ColorOrName = null,
    color_border: ?ColorOrName = null,

    pub fn toOptions(self: *const CellOptions) Options {
        return .{
            // does not convert height
            .margin = self.margin,
            .border = self.border,
            .padding = self.padding,
            .background = self.background,
            .color_fill = self.color_fill,
            .color_border = self.color_border,
        };
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
    scroll_opts: ?ScrollAreaWidget.InitOpts = null,
    col_widths: ?[]f32 = null,
    // Recalculate row heights. Only set this when row heights could have changed, .e.g on column resize.
    resize_rows: bool = false,
};
pub const default_col_width: f32 = 100;

vbox: BoxWidget = undefined,
scroll: ScrollAreaWidget = undefined,
hbox: BoxWidget = undefined,
init_opts: InitOpts = undefined,
current_col: ?*BoxWidget = null,
next_row_y: f32 = 0,
last_height: f32 = 0,
header_height: f32 = 0,
row_height: f32 = 0,
last_row_height: f32 = 0,
col_num: usize = std.math.maxInt(usize),
sort_col_number: usize = 0,
sort_direction: SortDirection = .unsorted,
saved_clip_rect: ?Rect.Physical = null,
resizing: bool = false,
rows_y_offset: f32 = 0,

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .{ .dir = .vertical }, options);
    if (dvui.dataGet(null, self.data().id, "_last_height", f32)) |last_height| {
        self.last_height = last_height;
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
    // Ensure resize on first initialization.
    if (self.last_height == 0) {
        self.resizing = true;
    }
    if (init_opts.resize_rows or self.resizing) {
        self.row_height = 0;
        dvui.refresh(null, @src(), self.data().id);
    }

    return self;
}

pub fn install(self: *GridWidget) !void {
    try self.vbox.install();
    try self.vbox.drawBackground();

    self.scroll = ScrollAreaWidget.init(@src(), self.init_opts.scroll_opts orelse .{}, .{ .name = "GridWidgetScrollArea", .expand = .both });
    try self.scroll.install();

    // Lay out columns horizontally.
    self.hbox = BoxWidget.init(@src(), .{ .dir = .horizontal }, .{
        .expand = .both,
    });
    try self.hbox.install();
    try self.hbox.drawBackground();
}

pub fn deinit(self: *GridWidget) void {
    defer dvui.widgetFree(self);
    self.clipReset();

    // resizing if row heights changed or a resize was requested via init options.
    self.resizing =
        self.init_opts.resize_rows or
        !std.math.approxEqAbs(f32, self.row_height, self.last_row_height, 0.01);

    dvui.dataSet(null, self.data().id, "_last_height", self.next_row_y);
    dvui.dataSet(null, self.data().id, "_header_height", self.header_height);
    dvui.dataSet(null, self.data().id, "_resizing", self.resizing);
    dvui.dataSet(null, self.data().id, "_row_height", self.row_height);
    dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
    dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);

    self.hbox.deinit();
    self.scroll.deinit();

    self.vbox.deinit();
    self.* = undefined;
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.vbox.wd;
}

/// Start a new grid column.
/// Returns a vbox.
/// Ensure deinit() is called on the returned vbox before creating a new column.
/// Column width is determined from:
/// 1) init_opts.col_width if supplied
/// 2) opts.width if supplied
/// 3) Otherewise column will expand to the available space.
/// It is recommended that widths are provided for all columns.
pub fn column(self: *GridWidget, src: std.builtin.SourceLocation, opts: ColOptions) !*BoxWidget {
    self.clipReset();
    self.current_col = null;

    self.col_num +%= 1; // maxint wraps to 0 for first col.
    self.next_row_y = self.rows_y_offset;

    const w: f32, const expand: ?Options.Expand = width: {
        // Take width from col_opts if it is set.
        if (self.init_opts.col_widths) |col_info| {
            if (self.col_num < col_info.len) {
                break :width .{ col_info[self.col_num], null };
            } else {
                dvui.log.debug("GridWidget {x} has more columns than set in init_opts.col_widths. Using default column width of {d}\n", .{ self.data().id, default_col_width });
                break :width .{ default_col_width, null };
            }
        } else {
            if (opts.width) |w| {
                if (w > 0) {
                    break :width .{ w, null };
                } else {
                    dvui.log.debug("GridWidget {x} invalid opts.width provided to column(). Using default column width of {d}\n", .{ self.data().id, default_col_width });
                    break :width .{ default_col_width, null };
                }
            } else {
                // If there is no width specified either in col_info or col_opts,
                // just expand to fill available width.
                break :width .{ 0, .horizontal };
            }
        }
    };
    var col_opts = opts.toOptions();
    col_opts.expand = expand;
    col_opts.min_size_content = .{ .w = w, .h = self.last_height };
    col_opts.max_size_content = if (w > 0) .width(w) else null;
    col_opts.id_extra = self.col_num;

    var col = dvui.widgetAlloc(BoxWidget);
    col.* = BoxWidget.init(src, .{ .dir = .vertical }, col_opts);
    try col.install();
    try col.drawBackground();
    self.current_col = col;
    return col;
}

/// Restore saved clip region.
fn clipReset(self: *GridWidget) void {
    if (self.saved_clip_rect) |cr| {
        dvui.clipSet(cr);
        self.saved_clip_rect = null;
    }
}

/// Create a new header cell within a column
/// Returns a hbox. deinit() must be called on this hbox before creating a new cell.
/// Only one header cell is allowed per column.
/// Height is taken from opts.height if provided, otherwise height is automatically determined.
pub fn headerCell(self: *GridWidget, src: std.builtin.SourceLocation, opts: CellOptions) !*BoxWidget {
    const y: f32 = self.scroll.si.viewport.y;
    const parent_rect = self.current_col.?.data().contentRect();

    const header_height: f32 = height: {
        if (opts.height) |height| {
            break :height height;
        } else {
            break :height if (self.resizing) 0 else self.header_height;
        }
    };
    var cell_opts = opts.toOptions();
    cell_opts.rect = .{ .x = 0, .y = y, .w = parent_rect.w, .h = header_height };

    // Create the cell and install as parent.
    var cell = dvui.widgetAlloc(BoxWidget);
    cell.* = BoxWidget.init(src, .{ .dir = .horizontal }, cell_opts);
    try cell.install();
    try cell.drawBackground();

    // Determine heights for next frame.
    if (cell.data().contentRect().h > 0) {
        const height = cell.data().rect.h;
        self.header_height = @max(self.header_height, height);
    }
    self.next_row_y += self.header_height;
    return cell;
}

/// Create a new body cell within a column
/// Returns a hbox. deinit() must be called on this hbox before creating a new cell.
/// Height is taken from opts.height if provided, otherwise height is automatically determined.
pub fn bodyCell(self: *GridWidget, src: std.builtin.SourceLocation, row_num: usize, opts: CellOptions) !*BoxWidget {
    const parent_rect = self.current_col.?.data().contentRect();

    const cell_height: f32 = height: {
        if (opts.height) |height| {
            break :height height;
        } else {
            break :height if (self.resizing) 0 else self.row_height;
        }
    };

    // Prevent the header from being overwritten when scrolling.
    if (self.saved_clip_rect == null) {
        const rect_scale = self.vbox.data().rectScale();
        const header_height_scaled = self.header_height * rect_scale.s;

        var clip_rect = rect_scale.r;
        clip_rect.y += header_height_scaled;
        clip_rect.h = self.scroll.si.viewport.h * rect_scale.s - header_height_scaled;

        self.saved_clip_rect = dvui.clip(clip_rect);
    }

    var cell_opts = opts.toOptions();
    cell_opts.rect = .{ .x = 0, .y = self.next_row_y, .w = parent_rect.w, .h = cell_height };
    cell_opts.id_extra = row_num;

    var cell = dvui.widgetAlloc(BoxWidget);
    cell.* = BoxWidget.init(src, .{ .dir = .horizontal }, cell_opts);
    try cell.install();
    try cell.drawBackground();

    if (cell.data().contentRect().h > 0) {
        const measured_cell_height = cell.data().rect.h;
        self.row_height = @max(self.row_height, measured_cell_height);
    }

    // If user provided a height, use that to position the next row, otherwise use the
    // calculated row_height.
    self.next_row_y += opts.height orelse self.row_height;

    return cell;
}

/// Set the starting y value to begin rendering rows.
/// Used for setting the y location of the first row when virtual scrolling.
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
pub fn colSortSet(self: *GridWidget, dir: SortDirection) void {
    self.sort_col_number = self.col_num;
    self.sort_direction = dir;
}

/// For automatic management of sort order, this must be called whenever
/// the sort order for any column has changed.
pub fn sortChanged(self: *GridWidget) void {
    // If sorting on a new column, change current sort column to unsorted.
    if (self.col_num != self.sort_col_number) {
        self.sort_direction = .unsorted;
        self.sort_col_number = self.col_num;
    }
    // If new sort column, then ascending, otherwise opposite of current sort.
    self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
}

/// Returns the sort order for the current column.
pub fn colSortOrder(self: *const GridWidget) SortDirection {
    if (self.col_num == self.sort_col_number) {
        return self.sort_direction;
    } else {
        return .unsorted;
    }
}

/// Provides vitrual scrolling for a grid so that only the visibile rows are rendered.
/// GridVirtualScroller requires that a scroll_info has been passed as an init_option
/// to the GridBodyWidget.
/// Note: Requires that all rows are the same height for the entire grid, including rows
/// not yet displayed. It is highly recommended to supply row heights to each cell
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
        // Adding some tiny padding helps make sure the last row is displayed with very large virtual scroll sizes.
        // The actual padding required would depend on the row height, but this should help for normal text height grids.
        const end_padding = total_rows_f / 100_000;
        si.virtual_size.h = @max(total_rows_f * grid.row_height + scrollbar_padding_defaults.h + end_padding, si.viewport.h);

        const first_row: f32 = @floatFromInt(_startRow(grid, si, init_opts.total_rows));
        grid.offsetRowsBy(first_row * grid.row_height);
        return .{
            .grid = grid,
            .si = si,
            .total_rows = init_opts.total_rows,
        };
    }

    fn _startRow(grid: *const GridWidget, si: *ScrollInfo, total_rows: usize) usize {
        if (grid.row_height < 1) {
            return 0;
        }
        const first_row_in_viewport: usize = @intFromFloat(@round(si.viewport.y / grid.row_height));
        if (first_row_in_viewport == 0) {
            return 0;
        }
        return @min(first_row_in_viewport - 1, total_rows);
    }
    /// Return the first row to render (inclusive)
    pub fn startRow(self: *const VirtualScroller) usize {
        return _startRow(self.grid, self.si, self.total_rows);
    }

    /// Return the end row to render (exclusive)
    /// Can be used as slice[startRow()..endRow()]
    pub fn endRow(self: *const VirtualScroller) usize {
        const last_row_in_viewport: usize =
            if (self.grid.row_height < 1)
                0
            else
                @intFromFloat(@round((self.si.viewport.y + self.si.viewport.h) / self.grid.row_height));
        return @min(last_row_in_viewport + 1, self.total_rows);
    }
};

/// Provides a draggable separator between columns
/// size must be a pointer into the col_widths slice
/// passed to the GridWidget init_option.
pub const HeaderResizeWidget = struct {
    pub const InitOptions = struct {
        // Input and output width (.vertical) or height (.horizontal)
        size: *f32,
        // clicking on these extra pixels before/after (.vertical)
        // or above/below (.horizontal) the handle also counts
        // as clicking on the handle.
        grab_tolerance: f32 = 5,
        // Will not resize to less than this value
        min_size: ?f32 = null,
        // Will not resize to more than this value
        max_size: ?f32 = null,

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

    pub fn install(self: *HeaderResizeWidget) !void {
        self.wd.register();
        try self.wd.borderAndBackground(.{});
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
                    switch (self.direction) {
                        .vertical => {
                            const unclamped_width = self.init_opts.size.* + dps.x / rs.s + self.offset.x;
                            self.init_opts.size.* = std.math.clamp(
                                unclamped_width,
                                self.init_opts.min_size orelse 1,
                                self.init_opts.max_size orelse dvui.max_float_safe,
                            );
                            self.offset.x = unclamped_width - self.init_opts.size.*;
                        },
                        .horizontal => {
                            const unclamped_height = self.init_opts.size.* + dps.y / rs.s + self.offset.y;
                            self.init_opts.size.* = std.math.clamp(
                                unclamped_height,
                                self.init_opts.min_size orelse 1,
                                self.init_opts.max_size orelse dvui.max_float_safe,
                            );
                            self.offset.y = unclamped_height - self.init_opts.size.*;
                        },
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
    @import("std").testing.refAllDecls(@This());
}
