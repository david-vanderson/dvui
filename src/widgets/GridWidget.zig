const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const Size = dvui.Size;
const MaxSize = Options.MaxSize;
const ScrollInfo = dvui.ScrollInfo;
const WidgetData = dvui.WidgetData;
const BoxWidget = dvui.BoxWidget;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const GridWidget = @This();

pub var defaults: Options = .{
    .name = "GridWidget",
    .background = true,
    .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
};

pub const InitOpts = ScrollAreaWidget.InitOpts;

const ColWidth = struct {
    const RowType = enum { header, body };
    // Width of the header and body columns
    w: f32,
    last_updated_by: RowType,
    // When col width is set by a header/body, ignore the next update from the body/header as its
    // width will be 1 frame behind
    ignore_next_update: bool,
    // If width is controlled by header/body, then updates all from body/header are ignored.
    // This is set when the header is styled to expand horizontally or has a fixed width.
    controlled_by: ?RowType,
};

vbox: BoxWidget = undefined,
init_opts: InitOpts = undefined,
options: Options = undefined,
col_widths: std.ArrayListUnmanaged(ColWidth) = undefined,
si: *dvui.ScrollInfo = undefined,
// scroll used to keep header and body scrolling in sync
si_store: dvui.ScrollInfo = .{ .horizontal = .none, .vertical = .auto },

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) !GridWidget {
    var self = GridWidget{};
    self.init_opts = init_opts;
    const options = defaults.override(opts);
    self.vbox = BoxWidget.init(src, .vertical, false, options);

    if (dvui.dataGetSlice(null, self.data().id, "_col_widths", []ColWidth)) |col_widths| {
        try self.col_widths.ensureTotalCapacity(dvui.currentWindow().arena(), col_widths.len);
        self.col_widths.appendSliceAssumeCapacity(col_widths);
    } else {
        self.col_widths = .empty;
    }
    self.options = options;
    return self;
}

pub fn install(self: *GridWidget) !void {
    if (self.init_opts.scroll_info) |si| {
        self.si = si;
    } else {
        if (dvui.dataGet(null, self.data().id, "_si_store", ScrollInfo)) |*si| {
            self.si_store = si.*;
        }
        self.si = &self.si_store;

        if (self.init_opts.horizontal) |horizontal| {
            self.si.horizontal = horizontal;
            self.init_opts.horizontal = null;
        }
        if (self.init_opts.vertical) |vertical| {
            self.si.vertical = vertical;
            self.init_opts.vertical = null;
        }
    }
    self.init_opts.scroll_info = self.si;

    try self.vbox.install();
    try self.vbox.drawBackground();
}

pub fn data(self: *GridWidget) *WidgetData {
    return &self.vbox.wd;
}

pub fn deinit(self: *GridWidget) void {
    dvui.dataSetSlice(null, self.data().id, "_col_widths", self.col_widths.items[0..]);
    dvui.dataSet(null, self.data().id, "_si_store", self.si_store);
    self.vbox.deinit();
}

fn colWidthReport(self: *GridWidget, who: ColWidth.RowType, w: f32, col_num: usize, take_control: bool) !void {
    if (col_num == 99) {
        std.debug.print("colWidthReport({s}, {d}, {d}, {})\n", .{ @tagName(who), w, col_num, take_control });
    }

    if (col_num >= self.col_widths.items.len) {
        try self.col_widths.append(dvui.currentWindow().arena(), .{ .last_updated_by = who, .w = w, .ignore_next_update = true, .controlled_by = null });
        dvui.refresh(null, @src(), null);
        return;
    }
    const col_width = &self.col_widths.items[col_num];
    if (col_num == 99) std.debug.print("PRE Col_width = {}\n", .{col_width});
    defer if (col_num == 99) std.debug.print("POST Col_width = {}\n", .{col_width});

    if (take_control) {
        col_width.* = .{ .last_updated_by = who, .w = w, .ignore_next_update = true, .controlled_by = who };
    }
    const controlled_by = col_width.controlled_by orelse who;
    if (col_width.ignore_next_update and col_width.controlled_by != controlled_by) {
        // Ignore any changes from the header/body if the other one changed the width last frame
        col_width.ignore_next_update = false;
        return;
    } else if (!std.math.approxEqRel(f32, col_width.w, w, 0.01)) {
        // Col width has changed.
        col_width.* = .{ .last_updated_by = who, .w = w, .ignore_next_update = true, .controlled_by = null };
        dvui.refresh(null, @src(), null);
    } else {
        // If no changes this frame, then resume updating col widths
        col_width.ignore_next_update = false;
    }
}

fn colMinWidthGet(self: *const GridWidget, who: ColWidth.RowType, col_num: usize) f32 {
    if (col_num >= self.col_widths.items.len) {
        return 0;
    }
    const col_width = &self.col_widths.items[col_num];
    const controlled_by = col_width.controlled_by orelse who;
    if (controlled_by != who) {
        return col_width.w;
    } else if (col_width.last_updated_by == who) {
        return 0;
    } else {
        return col_width.w;
    }
}

fn colMaxWidthGet(self: *const GridWidget, who: ColWidth.RowType, col_num: usize) ?f32 {
    if (col_num < self.col_widths.items.len) {
        const col_width = &self.col_widths.items[col_num];

        // If column width is being fully controlled by header/body, then a max width is
        // required on the body/header as the body/header might be wider than the controller.
        if (col_width.controlled_by) |controller| {
            if (controller != who) {
                return col_width.w;
            }
        }
    }
    return null;
}

pub const GridHeaderWidget = struct {
    pub const InitOpts = struct {};

    // Sort direction for a column
    pub const SortDirection = enum {
        unsorted,
        ascending,
        descending,
    };

    pub var defaults: Options = .{
        .name = "GridHeaderWidget",
        // generally the top of a scroll area is against something flat (like
        // window header), and the bottom is against something curved (bottom
        // of a window)
    };

    hbox: BoxWidget = undefined,
    header_hbox: BoxWidget = undefined,
    header_scroll: ScrollAreaWidget = undefined,
    scroll_padding: BoxWidget = undefined,
    col_hbox: ?BoxWidget = null,
    grid: *GridWidget = undefined,
    col_number: usize = 0,
    sort_col_number: usize = 0,
    sort_direction: SortDirection = .unsorted,
    height: f32 = 0,
    height_this_frame: f32 = 0,
    si: ScrollInfo = .{ .horizontal = .given, .vertical = .none },

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridHeaderWidget.InitOpts, opts: Options) GridHeaderWidget {
        var self = GridHeaderWidget{};
        const options = GridHeaderWidget.defaults.override(opts);

        _ = init_opts;
        self.grid = grid;
        self.hbox = BoxWidget.init(src, .horizontal, false, options.override(.{ .expand = .horizontal }));

        if (dvui.dataGet(null, self.data().id, "_sort_col", usize)) |sort_col| {
            self.sort_col_number = sort_col;
        }
        if (dvui.dataGet(null, self.data().id, "_sort_direction", SortDirection)) |sort_direction| {
            self.sort_direction = sort_direction;
        }
        if (dvui.dataGet(null, self.data().id, "_height", f32)) |height| {
            self.height = height;
        }
        if (dvui.dataGet(null, self.data().id, "_si2", ScrollInfo)) |*si| {
            self.si = si.*;
        }

        return self;
    }

    pub fn deinit(self: *GridHeaderWidget) void {
        self.header_hbox.deinit();
        self.header_scroll.deinit();

        dvui.dataSet(null, self.data().id, "_height", self.height_this_frame);
        dvui.dataSet(null, self.data().id, "_sort_col", self.sort_col_number);
        dvui.dataSet(null, self.data().id, "_sort_direction", self.sort_direction);
        dvui.dataSet(null, self.data().id, "_si2", self.si);
        self.hbox.deinit();
    }

    pub fn install(self: *GridHeaderWidget) !void {
        try self.hbox.install();
        try self.hbox.drawBackground();
        self.scroll_padding = BoxWidget.init(@src(), .vertical, false, .{
            .min_size_content = .{ .w = 10 }, // TODO: 10 = scroll bar widget width
            .expand = .vertical,
            .gravity_x = 1.0,
            .border = Rect.all(0),
        });
        try self.scroll_padding.install();
        try self.scroll_padding.drawBackground();
        self.scroll_padding.deinit();

        self.si.virtual_size.w = self.grid.si.virtual_size.w + 10; // TODO: 10 = scroll bar widget width
        self.si.virtual_size.h = self.grid.si.viewport.h;
        self.si.viewport.x = self.grid.si.viewport.x;
        self.header_scroll = ScrollAreaWidget.init(@src(), .{ .scroll_info = &self.si, .horizontal_bar = .hide, .vertical_bar = .hide }, .{ .expand = .horizontal });
        try self.header_scroll.install();
        self.header_hbox = BoxWidget.init(@src(), .horizontal, false, .{ .expand = .horizontal });
        try self.header_hbox.install();
        try self.header_hbox.drawBackground();
    }

    pub fn data(self: *GridHeaderWidget) *WidgetData {
        return self.hbox.data();
    }

    /// Start a new column heading.
    /// must be called before any widgets are created.
    pub fn colBegin(self: *GridHeaderWidget, src: std.builtin.SourceLocation, opts: Options) !void {
        // Check if box is null. Log warning if not.
        // check not in_body. Log warning if not.
        var min_width = self.grid.colMinWidthGet(.header, self.col_number);
        const has_horizontal_expand = if (opts.expand) |expand| expand == .horizontal or expand == .vertical else false;
        if (has_horizontal_expand)
            min_width = 0;

        var col_options: Options = .{
            .min_size_content = .{ .w = min_width, .h = self.height },
            .max_size_content = opts.max_size_content,
            .expand = opts.expand,
        };
        if (opts.min_size_content) |min_size_content| {
            col_options.min_size_content = min_size_content;
        }
        self.col_hbox = BoxWidget.init(src, .horizontal, false, col_options);
        try self.col_hbox.?.install();
        try self.col_hbox.?.drawBackground();
    }

    /// End of a column heading.
    /// must be called after all column widgets are deinit-ed.
    pub fn colEnd(self: *GridHeaderWidget) void {
        // Check in_body, log warning if not?? Needed?
        if (self.col_hbox) |*hbox| {
            const header_width = hbox.data().contentRect().w;
            const header_height = hbox.data().contentRect().h;

            const control_width = switch (hbox.data().options.expand orelse .none) {
                .horizontal, .both, .ratio => true,
                else => false,
            };
            self.grid.colWidthReport(.header, header_width, self.col_number, control_width) catch {}; // Don't want to throw from a deinit.

            if (header_height > self.height_this_frame) {
                self.height_this_frame = header_height;
            }

            hbox.deinit();
            self.col_hbox = null;
        } // else log warning.

        self.col_number += 1;
    }

    /// Must be called from the column header when the current column's sort order has changed.
    pub fn sortChanged(self: *GridHeaderWidget) void {
        // If sorting on a new column, change current sort column to unsorted.
        if (self.col_number != self.sort_col_number) {
            self.sort_direction = .unsorted;
            self.sort_col_number = self.col_number;
        }
        // If new sort column, then ascending, otherwise opposite of current sort.
        self.sort_direction = if (self.sort_direction != .ascending) .ascending else .descending;
    }

    /// Returns the sort order for the current header.
    pub fn colSortOrder(self: *const GridHeaderWidget) SortDirection {
        if (self.col_number == self.sort_col_number) {
            return self.sort_direction;
        } else {
            return .unsorted;
        }
    }
};

pub const GridBodyWidget = struct {
    pub const defaults: Options = .{
        .name = "GridBodyWidget",
        .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
        // Must either provide .expand or .min_size_content for virtual scrolling to work.
        .expand = .vertical,
    };
    pub const InitOpts = struct {};

    grid: *GridWidget = undefined,
    scroll: ScrollAreaWidget = undefined,
    hbox: BoxWidget = undefined,
    col_vbox: ?BoxWidget = null,
    row_hbox: ?BoxWidget = null,
    col_number: usize = 0,
    cell_number: usize = 0,
    // invisible_height is used to pad the top of the scroll area in virtual scrolling mode
    // The padded area will contain the "invisibile" rows at the start of the grid.
    invisible_height: f32 = 0,
    row_height: f32 = 0,
    row_height_this_frame: f32 = 0,
    min_size: ?Size = null,
    max_size: ?MaxSize = null,

    pub fn init(src: std.builtin.SourceLocation, grid: *GridWidget, init_opts: GridBodyWidget.InitOpts, opts: Options) GridBodyWidget {
        var self = GridBodyWidget{};
        const options = GridBodyWidget.defaults.override(opts);
        _ = init_opts;

        self.grid = grid;
        self.scroll = ScrollAreaWidget.init(src, self.grid.init_opts, options);

        if (dvui.dataGet(null, self.data().id, "_row_height", f32)) |row_height| {
            self.row_height = row_height;
        }
        self.min_size = opts.min_size_content;
        self.max_size = opts.max_size_content;

        return self;
    }

    pub fn install(self: *GridBodyWidget) !void {
        try self.scroll.install();
        self.hbox = BoxWidget.init(@src(), .horizontal, false, .{ .expand = .vertical });

        try self.hbox.install();
        try self.hbox.drawBackground();
    }

    pub fn deinit(self: *GridBodyWidget) void {
        dvui.dataSet(null, self.data().id, "_row_height", if (self.row_height_this_frame > 0) self.row_height_this_frame else self.row_height);
        self.hbox.deinit();
        self.scroll.deinit();
    }

    pub fn data(self: *GridBodyWidget) *WidgetData {
        return self.scroll.data();
    }

    /// Begin a new grid column
    /// must be called before any widgets are created in the column
    pub fn colBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation, opts: Options) !void {

        // TODO: Check if box is null. Log warning if not.
        const min_width = self.grid.colMinWidthGet(.body, self.col_number);
        const max_width = self.grid.colMaxWidthGet(.body, self.col_number);
        if (self.col_number == 99) {
            std.debug.print("Min width = {d}, max_width = {d}\n", .{ min_width, max_width orelse 0 });
        }

        var col_options: Options = .{
            .min_size_content = .{ .w = min_width },
            .max_size_content = if (max_width) |mw| .width(mw) else opts.max_size_content,
        };
        if (opts.min_size_content) |min_size_content| {
            col_options.min_size_content = min_size_content;
        }
        if (self.col_number == 99) {
            std.debug.print("Col opts = {}\n", .{col_options});
        }
        self.col_vbox = BoxWidget.init(src, .vertical, false, col_options);
        try self.col_vbox.?.install();
        try self.col_vbox.?.drawBackground();

        // Create a vbox to pad out space for any invisible rows.
        if (self.invisible_height > 0) {
            var vbox = BoxWidget.init(src, .vertical, false, .{
                .expand = .horizontal,
                .min_size_content = .{ .h = self.invisible_height },
                .max_size_content = .height(self.invisible_height),
            });
            try vbox.install();
            vbox.deinit();
        }
    }

    /// End a new column
    /// must be called after all widgets in the column have been deinit-ed.
    pub fn colEnd(self: *GridBodyWidget) void {
        if (self.col_vbox) |*vbox| {
            const current_width = vbox.data().contentRect().w;
            self.grid.colWidthReport(.body, current_width, self.col_number, false) catch {}; // Don't want to throw from a deinit.

            vbox.deinit();
            self.col_vbox = null;
        } // else log warning.
        self.col_number += 1;
    }

    // Start a new cell.
    // must be called before any widgets are created in the cell
    pub fn cellBegin(self: *GridBodyWidget, src: std.builtin.SourceLocation) !void {
        self.row_hbox = BoxWidget.init(src, .horizontal, false, .{ .id_extra = self.cell_number, .expand = .both });
        try self.row_hbox.?.install();
        try self.row_hbox.?.drawBackground();
    }

    // End a new cell
    // must be called after all widgets in the cell have been deinit-ed.
    pub fn cellEnd(self: *GridBodyWidget) void {
        if (self.row_hbox) |*hbox| {
            if (hbox.wd.rect.h > self.row_height_this_frame) {
                self.row_height_this_frame = hbox.wd.rect.h;
            }
            hbox.deinit();
            self.row_hbox = null;
        }
        self.cell_number += 1;
    }

    pub fn virtualScroller(self: *GridBodyWidget, init_opts: GridVirtualScroller.InitOpts) GridVirtualScroller {
        return GridVirtualScroller.init(self, init_opts);
    }
};

/// Provides vitrual scrolling for a grid so that only the visibile rows are rendered.
/// GridVirtualScroller requires that a scroll_info has been passed as an init_option
/// to the GridBodyWidget.
pub const GridVirtualScroller = struct {
    pub const InitOpts = struct {
        // Total rows in the columns displayed
        total_rows: usize,
        // The number of rows to render before and after the visible scroll area.
        // Larger windows can result in smoother scrolling but will take longer to render each frame.
        window_size: usize = 1,
    };
    body: *GridBodyWidget,
    si: *ScrollInfo,
    total_rows: usize,
    window_size: usize,
    pub fn init(body: *GridBodyWidget, init_opts: GridVirtualScroller.InitOpts) GridVirtualScroller {
        const total_rows_f: f32 = @floatFromInt(init_opts.total_rows);
        body.scroll.si.virtual_size.h = @max(total_rows_f * body.row_height, body.scroll.si.viewport.h);
        const window_size: f32 = @floatFromInt(init_opts.window_size);
        body.invisible_height = @max(0, body.scroll.si.viewport.y - body.row_height * window_size);
        return .{
            .body = body,
            .si = body.scroll.si,
            .total_rows = init_opts.total_rows,
            .window_size = init_opts.window_size,
        };
    }

    /// Return the first row within the visible scroll area, minus window_size
    pub fn rowFirstRendered(self: *const GridVirtualScroller) usize {
        if (self.body.row_height < 1) {
            return 0;
        }
        const first_row_in_viewport: usize = @intFromFloat(@round(self.si.viewport.y / self.body.row_height));
        if (first_row_in_viewport < self.window_size) {
            return @min(first_row_in_viewport, self.total_rows);
        }
        return @min(first_row_in_viewport - self.window_size, self.total_rows);
    }

    /// Return the first row within the visible scroll area, plus the window size.
    pub fn rowLastRendered(self: *const GridVirtualScroller) usize {
        if (self.body.row_height < 1) {
            return 1;
        }
        const last_row_in_viewport: usize = @intFromFloat(@round((self.si.viewport.y + self.si.viewport.h) / self.body.row_height));
        return @min(last_row_in_viewport + self.window_size, self.total_rows);
    }
};
