const std = @import("std");
const dvui = @import("../dvui.zig");

pub const fnv = std.hash.Fnv1a_64;

const TableWidget = @This();

pub var defaults: dvui.Options = .{
    .name = "TableWidget",
    // role based on layout_only in init
    .corners = .{
        .tl = .square,
        .tr = .square,
        .br = .default,
        .bl = .default,
    },
    .style = .content,
    .background = true,
    .border = .all(1),
};

pub const InitOptions = struct {
    /// Scroll options for the grid body
    scroll_opts: dvui.ScrollAreaWidget.InitOpts = .{},

    /// How many rows in the table.  If null use the max cell row we saw last
    /// frame.  Required to use `rowsVisible`.
    rows: ?usize = null,

    /// Use solely for laying out child widgets.
    /// * disables keyboard navigation
    /// * implies autoSize always
    layout_only: bool = false,

    /// List of column indexes exempt from auto expanding/contracting.  Good
    /// for checkbox columns.
    cols_static: []const usize = &.{},
};

pub const Cell = struct {
    col: usize,
    row: usize,
};

pub const SortDirection = enum {
    unsorted,
    ascending,
    descending,
};

pub const AutoSize = enum {
    rows,
    cols,
    both,
};

pub const COL_MIN_WIDTH = 6;
pub const COL_MIN_START = 26;
pub const ROW_MIN_HEIGHT = 6;

const RowHeight = struct {
    row: usize,
    height: f32,

    pub fn lower(r: usize, item: RowHeight) bool {
        return item.row < r;
    }

    pub fn order(r: usize, item: RowHeight) std.math.Order {
        return std.math.order(r, item.row);
    }
};

wd: dvui.WidgetData,
layout_only: bool,
last_focus: dvui.Id = .zero,
cols: usize,
rows: usize,
rows_provided: bool = false,
max_seen_col: isize = -1,
max_seen_row: isize = -1,
first_visible_row: usize = 0,
first_visible_row_y: f32 = 0,
cursor: Cell = .{ .col = 0, .row = 0 },
cell_widget: CellWidget,

auto_size: ?AutoSize = null,
auto_size_max: *dvui.Size,

col_widths: []f32 = &.{},
cols_static: []const usize,
col_expand: f32 = 0,
col_widths_auto: std.ArrayList(f32) = .empty,
col_header_height: *f32,
col_header_height_auto: f32 = 0,
col_header_group: dvui.FocusGroupWidget,

row_height_default: *f32,
row_heights: []RowHeight = &.{},
row_heights_auto: std.ArrayList(RowHeight) = .empty,
// AccessKit support
ak_row_ids: std.array_hash_map.Auto(usize, dvui.Id) = .empty,

msi: *dvui.ScrollInfo, // main scroll info
scroll: dvui.ScrollAreaWidget, // main scroll area
csi: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .none }, // column header scroll info
cscroll: ?dvui.ScrollAreaWidget = null, // column header scroll area
rscroll: ?dvui.ScrollAreaWidget = null, // row header scroll area
bscroll: ?dvui.ScrollContainerWidget = null, // body scroll container
frame_viewport: dvui.Point = .{}, // Fixed scroll viewport for this frame
scroll_to_cursor: bool = false,

sort_dir: SortDirection = .unsorted,
sort_col: usize = 0,

focus_touch: bool = false, // true if the table was focused by a touch event

pub fn init(self: *TableWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: dvui.Options) void {
    var defs = defaults;
    if (!init_opts.layout_only) defs.role = .grid;
    const options = defs.override(opts);

    const default_row_height = options.fontGet().sizeM(1, 1).h + dvui.TextLayoutWidget.defaults.paddingGet().y + dvui.TextLayoutWidget.defaults.paddingGet().h;

    self.* = .{
        .wd = dvui.WidgetData.init(src, .{ .scroll_when_focused = false }, options),
        .layout_only = init_opts.layout_only,
        .cell_widget = undefined,
        .cols = undefined,
        .rows = undefined,
        .cols_static = init_opts.cols_static,
        .col_header_group = undefined,
        .row_height_default = dvui.dataGetPtrDefault(null, self.data().id, "__row_height_default", f32, default_row_height),
        .col_header_height = dvui.dataGetPtrDefault(null, self.data().id, "__col_header_height", f32, default_row_height),
        .scroll = undefined,
        .msi = undefined,
        .auto_size_max = dvui.dataGetPtrDefault(null, self.data().id, "__auto_size_max", dvui.Size, options.fontGet().sizeM(20, 5)),
    };

    self.data().register();
    dvui.parentSet(self.widget());
    self.data().borderAndBackground(.{});

    if (dvui.dataGet(null, self.data().id, "__auto_size", AutoSize)) |which| {
        self.auto_size = which;
        dvui.dataRemove(null, self.data().id, "__auto_size");
    }

    self.cols = dvui.dataGet(null, self.data().id, "__cols", usize) orelse 0;
    self.rows = init_opts.rows orelse dvui.dataGet(null, self.data().id, "__rows", usize) orelse 0;
    if (init_opts.rows) |_| self.rows_provided = true;

    self.col_widths = dvui.dataGetSlice(null, self.data().id, "__col_widths", []f32) orelse &.{};
    if (self.cols != self.col_widths.len) {
        dvui.dataSetSliceCopies(null, self.data().id, "__col_widths", @as([]const f32, &.{100.0}), self.cols);
        const old = self.col_widths;
        self.col_widths = dvui.dataGetSlice(null, self.data().id, "__col_widths", []f32).?;
        const len = @min(old.len, self.col_widths.len);
        @memcpy(self.col_widths[0..len], old[0..len]);
    }

    self.row_heights = dvui.dataGetSlice(null, self.data().id, "__row_heights", []RowHeight) orelse &.{};

    self.cursor = dvui.dataGet(null, self.data().id, "__cursor", Cell) orelse .{ .col = 0, .row = 0 };
    self.scroll_to_cursor = dvui.dataGet(null, self.data().id, "__scroll_to_cursor", bool) orelse false;

    self.sort_dir = dvui.dataGet(null, self.data().id, "__sort_dir", SortDirection) orelse .unsorted;
    self.sort_col = dvui.dataGet(null, self.data().id, "__sort_col", usize) orelse 0;

    self.focus_touch = dvui.dataGet(null, self.data().id, "__focus_touch", bool) orelse false;

    if (self.layout_only) {
        self.autoSize(.{ .auto = .both, .max_width = dvui.max_float_safe, .max_height = dvui.max_float_safe });
    } else if (dvui.firstFrame(self.data().id)) {
        self.autoSize(.{ .auto = .both });
    }

    if (dvui.dataGet(null, self.data().id, "__csi", dvui.ScrollInfo)) |stored| self.csi = stored;

    var scroll_opts = init_opts.scroll_opts;
    scroll_opts.frame_viewport_out = scroll_opts.frame_viewport_out orelse &self.frame_viewport;
    scroll_opts.container = false;

    self.scroll.init(
        @src(),
        scroll_opts,
        .{
            .name = "TableWidgetScrollArea",
            .role = .none,
            .expand = .both,
            .background = false,
        },
    );

    self.msi = self.scroll.si;
    self.frame_viewport = scroll_opts.frame_viewport_out.?.*; // noop unless frame_viewport_out was passed into us

    // expand or shrink horizontally
    if ((options.expandGet().isHorizontal() or self.msi.horizontal == .none) and self.col_widths.len > 0) {
        var total: f32 = 0;
        for (self.col_widths) |w| total += w;

        var total_weight: f32 = 0;
        for (0..self.cols) |col| total_weight += self.colWeight(col);
        if (total_weight > 0) {
            self.col_expand = (self.msi.viewport.w - total) / total_weight;
        }

        if (self.msi.horizontal != .none) {
            // horizontal scroll available, so don't shrink
            self.col_expand = @max(0, self.col_expand);
        }

        if (!options.expandGet().isHorizontal()) {
            // not expanding, so only shrink
            self.col_expand = @min(0, self.col_expand);
        }
    }
}

pub const AutoSizeOptions = struct {
    auto: AutoSize,
    max_width: ?f32 = null,
    max_height: ?f32 = null,
};

/// Resize cols/rows to fit the contents.
/// * max width/height forced to be at least 6
/// * max width/height default to sizeM(20, 5) if null
///
/// autoSize goes multiple frames until all run cells are settled.
pub fn autoSize(self: *TableWidget, opts: AutoSizeOptions) void {
    self.auto_size = opts.auto;
    const default = self.data().options.fontGet().sizeM(20, 5);

    self.auto_size_max.*.w = opts.max_width orelse default.w;
    self.auto_size_max.*.w = @max(self.auto_size_max.w, COL_MIN_WIDTH);

    self.auto_size_max.*.h = opts.max_height orelse default.h;
    self.auto_size_max.*.h = @max(self.auto_size_max.h, ROW_MIN_HEIGHT);
}

/// Return first/last row in the viewport.  Must pass `.rows` to `init`.
pub fn rowsVisible(self: *TableWidget) struct { usize, usize } {
    if (!self.rows_provided) {
        dvui.log.err("TableWidget: {x} rowsVisible() requires InitOptions.rows", .{self.data().id});
        dvui.Debug.errorOutline(self.data().rectScale().r);
        return .{ 0, self.rows };
    }

    if (self.msi.viewport.h == 0) {
        // First frame, run the rows we are likely to see.
        return .{ 0, @min(50, self.rows) };
    }

    // expand the visible rows by this on each side so keyboard navigation
    // works to unseen rows
    const extra: usize = 1;
    const start_y: f32 = @max(0, self.frame_viewport.y);
    const end_y: f32 = self.frame_viewport.y + self.msi.viewport.h;

    var r: usize = 0;
    var y: f32 = 0;
    var rh: f32 = self.rowHeight(r);

    // find first row where bottom is visible
    while (r < self.rows and (y + rh) <= start_y) {
        r += 1;
        y += rh;
        rh = self.rowHeight(r);
    }

    const start = r;
    self.first_visible_row = r;
    self.first_visible_row_y = y;

    // go until first non-visible row (because last is exclusive)
    while (r < self.rows and y < end_y) {
        r += 1;
        y += rh;
        rh = self.rowHeight(r);
    }

    //std.debug.print("first {d} {d} to {d} {d} start {d} {d}\n", .{ self.first_visible_row, self.first_visible_row_y, r, y, start_y, end_y });

    return .{ start -| extra, @min(r + extra, self.rows) };
}

pub fn widget(self: *TableWidget) dvui.Widget {
    return dvui.Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *TableWidget) *dvui.WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *TableWidget, id: dvui.Id, min_size: dvui.Size, e: dvui.Options.Expand, g: dvui.Options.Gravity) dvui.Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *TableWidget, rect: dvui.Rect) dvui.RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *TableWidget, s: dvui.Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

pub const CellWidget = struct {
    table: *TableWidget,
    col: usize,
    row: usize,
    grid_focus: bool,
    wd: dvui.WidgetData,
    call: usize = 0,

    pub const InitOptions = struct {
        table: *TableWidget,
        col: usize,
        row: usize,
        grid_focus: bool,
        draw_focus: bool = true,
    };

    pub fn init(self: *CellWidget, src: std.builtin.SourceLocation, init_opts: CellWidget.InitOptions, opts: dvui.Options) void {
        const defs: dvui.Options = .{ .name = "Cell" };
        self.* = .{
            .table = init_opts.table,
            .col = init_opts.col,
            .row = init_opts.row,
            .grid_focus = init_opts.grid_focus,
            .wd = dvui.WidgetData.init(src, .{}, defs.override(opts)),
        };

        dvui.parentSet(self.widget());
        self.data().register();
        self.data().borderAndBackground(.{});

        if (self.grid_focus and init_opts.draw_focus) {
            const rs = self.data().backgroundRectScale();
            if (!rs.r.empty()) {
                const fill = (dvui.themeGet().text_select orelse dvui.themeGet().color(.highlight, .fill)).opacity(0.75);
                rs.r.fill(self.data().options.cornersGet().scale(rs.s, dvui.CornerRect.Physical), .{
                    .color = fill,
                    .fade = if (dvui.windowNaturalScale() >= 2.0) 0.0 else 1.0,
                });
            }
        }
    }

    pub fn widget(self: *CellWidget) dvui.Widget {
        return dvui.Widget.init(self, CellWidget.data, CellWidget.rectFor, CellWidget.screenRectScale, CellWidget.minSizeForChild);
    }

    pub fn data(self: *CellWidget) *dvui.WidgetData {
        return self.wd.validate();
    }

    pub fn rectFor(self: *CellWidget, id: dvui.Id, min_size: dvui.Size, e: dvui.Options.Expand, g: dvui.Options.Gravity) dvui.Rect {
        _ = id;
        return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
    }

    pub fn screenRectScale(self: *CellWidget, rect: dvui.Rect) dvui.RectScale {
        return self.data().contentRectScale().rectToRectScale(rect);
    }

    pub fn minSizeForChild(self: *CellWidget, s: dvui.Size) void {
        self.data().minSizeMax(self.data().options.padSize(s));
    }

    pub fn deinit(self: *CellWidget) void {
        defer self.* = undefined;

        self.wd.min_size = self.wd.min_size.min(self.wd.options.max_sizeGet());
        self.table.cellMinSize(self.col, self.row, self.wd.min_size);

        dvui.parentReset(self.data().id, self.data().parent);
    }

    /// If the user edits the value and presses enter or clicks away, we return
    /// the edited value.
    ///
    /// If the user makes no change or presses escape, return null.
    pub fn editable(self: *CellWidget, text: []const u8, options: dvui.Options) ?[]u8 {
        const defs: dvui.Options = .{ .name = "Cell.editable", .margin = .{}, .border = .{}, .corners = .{}, .min_size_content = .{}, .expand = .both, .background = false };
        const opts = defs.override(options);
        var ret: ?[]u8 = null;

        const src = @src();
        const id = dvui.parentGet().extendId(src, opts.idExtra());
        const editing = dvui.dataGet(null, id, "__editing", bool) orelse false;

        if (!editing) {
            var tl: dvui.TextLayoutWidget = undefined;
            tl.init(src, .{ .process_events_in_deinit = false }, opts);
            // specifically not calling touchEditing or processEvents
            tl.addText(text, .{});
            tl.deinit();

            if (self.grid_focus) {
                // On desktop we enable text events so the user can start
                // typing to transition to editing.  But phones show the on
                // screen keyboard, so don't if the table was focused by touch.
                if (!self.table.focus_touch) {
                    dvui.wantTextInput(self.data().borderRectScale().r.toNatural());
                }

                const evts = dvui.events();
                for (evts) |*e| {
                    if (!dvui.eventMatch(e, .{ .id = self.table.data().id, .r = self.data().rectScale().r })) continue;

                    switch (e.evt) {
                        .mouse => |me| {
                            if (me.action == .focus) {
                                e.handle(@src(), self.data());
                                dvui.dataSet(null, id, "__editing", true);
                                dvui.dataSet(null, id, "__editing_first_frame", true);
                                dvui.focusWidget(id, null, e.num);
                                dvui.refresh(null, @src(), self.data().id);
                            }
                        },
                        .key => |ke| {
                            if (ke.action == .down and ke.code == .enter) {
                                e.handle(@src(), self.data());
                                dvui.dataSet(null, id, "__editing", true);
                                dvui.dataSet(null, id, "__editing_first_frame", true);
                                dvui.focusWidget(id, null, e.num);
                                dvui.refresh(null, @src(), self.data().id);
                            } else if (ke.action == .down and (ke.code == .backspace or ke.code == .delete)) {
                                e.handle(@src(), self.data());
                                dvui.refresh(null, @src(), self.data().id);
                                return &.{};
                            }
                        },
                        .text => |te| {
                            if (te.action == .value) {
                                e.handle(@src(), self.data());
                                dvui.dataSet(null, id, "__editing", true);
                                dvui.dataSet(null, id, "__editing_first_frame", true);
                                dvui.focusWidget(id, null, e.num);
                                dvui.refresh(null, @src(), self.data().id);

                                dvui.dataSetSlice(null, id, "__editing_first_frame_text", te.action.value.txt);
                            }
                        },
                        else => {},
                    }
                }
            }
        } else {
            var te: dvui.TextEntryWidget = undefined;
            te.init(src, .{ .multiline = true, .break_lines = true, .scroll_horizontal = false }, opts);

            var escape = false;
            var enter = false;
            var enter_shift = false;
            const evts = dvui.events();
            for (evts) |*e| {
                if (!te.matchEvent(e)) continue;

                switch (e.evt) {
                    .key => |*ke| {
                        if (ke.action == .down and ke.code == .escape) {
                            e.handle(@src(), te.data());
                            dvui.dataRemove(null, id, "__editing");
                            dvui.focusWidget(self.table.data().id, null, e.num);
                            dvui.refresh(null, @src(), id);
                            escape = true;
                        } else if (ke.action == .down and ke.code == .tab) {
                            e.handle(@src(), te.data());
                            dvui.dataRemove(null, id, "__editing");
                            dvui.focusWidget(self.table.data().id, null, e.num);
                            _ = self.table.moveCursorTab(ke.mod.shift());
                            dvui.refresh(null, @src(), id);
                        } else if ((ke.action == .down or ke.action == .repeat) and ke.code == .enter) {
                            if (ke.mod.matchBind("ctrl/cmd")) {
                                // text entry will process enter like normal
                            } else {
                                e.handle(@src(), te.data());
                                enter = true;
                                if (ke.mod.shift()) enter_shift = true;
                            }
                        }
                    },
                    else => {},
                }
            }

            te.processEvents();

            if (dvui.dataGet(null, id, "__editing_first_frame", bool) orelse false) {
                dvui.dataRemove(null, id, "__editing_first_frame");
                if (dvui.dataGetSlice(null, id, "__editing_first_frame_text", []u8)) |txt| {
                    te.textTyped(txt, false);
                } else {
                    te.textTyped(text, false);
                }
            }

            te.draw();

            if (!escape and id != dvui.focusedWidgetIdInCurrentSubwindow()) {
                // we lost focus
                if (!std.mem.eql(u8, text, te.textGet())) ret = te.textGet();
                dvui.dataRemove(null, id, "__editing");
                dvui.refresh(null, @src(), id);
            }

            if (enter) {
                if (!std.mem.eql(u8, text, te.textGet())) ret = te.textGet();
                dvui.dataRemove(null, id, "__editing");
                dvui.focusWidget(self.table.data().id, null, 0);
                dvui.refresh(null, @src(), id);
                if (enter_shift) {
                    self.table.moveCursor(self.table.cursor.col, self.table.cursor.row -| 1);
                } else {
                    self.table.moveCursor(self.table.cursor.col, self.table.cursor.row + 1);
                }
            }

            te.deinit();
        }

        return ret;
    }

    pub fn headerSortable(self: *CellWidget, text: []const u8, options: dvui.Options) ?SortDirection {
        const defs: dvui.Options = .{ .name = "Cell.headerSortable", .margin = .{}, .border = .{}, .corners = .{}, .min_size_content = .{}, .expand = .both };
        const opts = defs.override(options);

        const sort: SortDirection = if (self.col == self.table.sort_col) self.table.sort_dir else .unsorted;
        const src = @src();
        const sort_changed = switch (sort) {
            // Use same src for each button so they get the same id and can retain focus accross frames.
            .unsorted => blk: {
                const clicked = dvui.button(src, text, .{}, opts);

                // bump up cell min size to account for possible icon
                const h = opts.fontGet().textHeight();
                const w = dvui.iconWidth("chevron_small_up", dvui.entypo.chevron_small_up, h) catch h;
                self.data().min_size.w += w;

                break :blk clicked;
            },
            .ascending => dvui.buttonLabelAndIcon(src, .{
                .label = text,
                .icon_label = "sorted ascending",
                .tvg_bytes = dvui.entypo.chevron_small_up,
            }, opts),
            .descending => dvui.buttonLabelAndIcon(src, .{
                .label = text,
                .icon_label = "sorted descending",
                .tvg_bytes = dvui.entypo.chevron_small_down,
            }, opts),
        };

        if (sort_changed) {
            if (self.col == self.table.sort_col) {
                self.table.sort_dir = if (self.table.sort_dir == .ascending) .descending else .ascending;
            } else {
                self.table.sort_col = self.col;
                self.table.sort_dir = .ascending;
            }

            return self.table.sort_dir;
        }

        return null;
    }
};

fn colWeight(self: *TableWidget, col: usize) f32 {
    if (std.mem.findScalar(usize, self.cols_static, col) != null)
        return 0.0;

    if (col < self.col_widths.len) {
        const w = self.col_widths[col];
        if (w <= COL_MIN_WIDTH) return 0;
        if (w > COL_MIN_START) return 1.0;
        return (w - COL_MIN_WIDTH) / (COL_MIN_START - COL_MIN_WIDTH);
    }
    return 1.0;
}

pub fn colWidth(self: *TableWidget, col: usize) f32 {
    if (col < self.col_widths.len) {
        return @max(COL_MIN_WIDTH, self.col_widths[col] + self.col_expand * self.colWeight(col));
    }
    return 100;
}

pub fn colOffset(self: *TableWidget, col: usize) f32 {
    var x: f32 = 0;
    for (0..col) |i| x += self.colWidth(i);
    return x;
}

pub fn rowHeight(self: *TableWidget, row: usize) f32 {
    if (std.sort.binarySearch(RowHeight, self.row_heights, row, RowHeight.order)) |idx| {
        return self.row_heights[idx].height;
    }

    return self.row_height_default.*;
}

pub fn rowOffset(self: *TableWidget, row: usize) f32 {
    var r = self.first_visible_row;
    var ry = self.first_visible_row_y;
    while (r > row) {
        r -= 1;
        ry -= self.rowHeight(r);
    }
    while (r < row) {
        ry += self.rowHeight(r);
        r += 1;
    }

    return ry;
}

pub fn colHeader(self: *TableWidget, col: usize, opts: dvui.Options) *CellWidget {
    if (self.cscroll == null) {
        if (self.bscroll != null) {
            dvui.log.debug("TableWidget {x} colHeader called after cell", .{self.data().id});
            dvui.Debug.errorOutline(self.bscroll.?.data().rectScale().r);
        } else {
            self.cscroll = @as(dvui.ScrollAreaWidget, undefined);
            self.cscroll.?.init(@src(), .{
                .horizontal_bar = .hide,
                .vertical_bar = .hide,
                .scroll_info = &self.csi,
                .frame_viewport = .{ .x = self.frame_viewport.x },
                .process_events_after = false,
            }, .{
                .name = "TableWidgetColumnHeaderScroll",
                .role = .header,
                .expand = .horizontal,
            });
            if (!self.layout_only) {
                self.col_header_group.init(@src(), .{ .nav_key_dir = .horizontal }, .{ .tab_index = self.data().options.tab_index });
            }
        }
    }

    self.max_seen_col = @max(self.max_seen_col, @as(isize, @intCast(col)));
    var hash = fnv.init();
    hash.update("col");
    hash.update(std.mem.asBytes(&col));
    hash.update("header");

    const rect: dvui.Rect = .{
        .x = self.colOffset(col),
        .y = 0,
        .w = self.colWidth(col),
        .h = self.col_header_height.*,
    };

    const defs: dvui.Options = .{ .rect = rect, .id_extra = @truncate(hash.final()) };

    self.cell_widget.init(@src(), .{ .table = self, .col = col, .row = std.math.maxInt(usize), .grid_focus = false }, defs.override(opts));

    if (!self.layout_only) {
        // column resizing
        var rs = self.cell_widget.data().rectScale();
        rs.r.x = rs.r.x + rs.r.w - COL_MIN_WIDTH * rs.s;
        rs.r.w = COL_MIN_WIDTH * rs.s;
        const wd = self.cell_widget.data();
        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatch(e, .{ .id = wd.id, .r = rs.r })) continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .focus) {
                        e.handle(@src(), wd);
                    } else if (me.action == .press and me.button.pointer()) {
                        e.handle(@src(), wd);
                        dvui.captureMouse(wd, e.num);
                        dvui.dragPreStart(me.button, me.p, .{});
                    } else if (me.action == .release and me.button.pointer()) {
                        e.handle(@src(), wd);
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                    } else if (me.action == .motion) {
                        if (dvui.captured(wd.id)) {
                            e.handle(@src(), wd);
                            if (dvui.dragging(me.p, null)) |dp| {
                                const dx = dp.x / rs.s;
                                self.col_widths[col] = @max(COL_MIN_WIDTH, self.col_widths[col] + dx);
                                dvui.refresh(null, @src(), wd.id);
                            }
                        }
                    } else if (me.action == .position) {
                        dvui.cursorSet(.arrow_w_e);
                    }
                },
                else => {},
            }
        }
    }

    return &self.cell_widget;
}

pub fn ensureBodyScroll(self: *TableWidget) void {
    if (self.cscroll) |*cscroll| {
        if (!self.layout_only) {
            self.col_header_group.deinit();
        }

        var tw: f32 = 0;
        for (self.col_widths) |w| tw += w;
        const s: dvui.Size = .{ .w = tw, .h = self.col_header_height.* };
        cscroll.scroll.?.minSizeForChild(s);

        cscroll.deinit();
        self.cscroll = null;
    }

    if (self.bscroll == null) {
        self.bscroll = @as(dvui.ScrollContainerWidget, undefined);
        self.bscroll.?.init(@src(), self.msi, .{
            .scroll_area = &self.scroll,
            .frame_viewport = self.frame_viewport,
            .event_rect = self.scroll.data().borderRectScale().r,
        }, .{
            .name = "TableWidgetBodyScroll",
            .expand = .both,
            .background = false,
        });
        self.bscroll.?.processEvents();

        // record last_focus here so it doesn't cover the column headers
        self.last_focus = dvui.lastFocusedIdInFrame();
    }
}

pub const CellOptions = struct {
    col: usize,
    row: usize,
    draw_focus: bool = true,
};

pub fn cell(self: *TableWidget, cell_opts: CellOptions, opts: dvui.Options) *CellWidget {
    self.ensureBodyScroll();

    self.max_seen_col = @max(self.max_seen_col, @as(isize, @intCast(cell_opts.col)));
    self.max_seen_row = @max(self.max_seen_row, @as(isize, @intCast(cell_opts.row)));

    const rect: dvui.Rect = .{
        .x = self.colOffset(cell_opts.col),
        .y = self.rowOffset(cell_opts.row),
        .w = self.colWidth(cell_opts.col),
        .h = self.rowHeight(cell_opts.row),
    };

    const grid_focus = self.data().id == dvui.focusedWidgetId() and cell_opts.col == self.cursor.col and cell_opts.row == self.cursor.row;

    if (grid_focus and self.scroll_to_cursor) {
        self.scroll_to_cursor = false;
        dvui.scrollTo(.{ .screen_rect = self.bscroll.?.screenRectScale(rect).r });
    }

    if (dvui.accesskit_enabled and !self.layout_only) {
        // If this is a new row, then create an accessible row node to parent all the cells
        // grid_cell_row must be set before the cell's box widget is created.
        if (self.ak_row_ids.get(cell_opts.row)) |row_id| {
            dvui.currentWindow().accesskit.grid_cell_row = row_id;
        } else {
            const rowrect: dvui.Rect = .{
                .x = 0,
                .y = self.rowOffset(cell_opts.row),
                .w = self.colOffset(self.cols),
                .h = self.rowHeight(cell_opts.row),
            };
            var vp = dvui.overlay(@src(), .{ .role = .row, .name = "GridRow", .id_extra = cell_opts.row, .rect = rowrect });
            defer vp.deinit();
            self.ak_row_ids.put(dvui.currentWindow().arena(), cell_opts.row, vp.data().id) catch {};
            dvui.currentWindow().accesskit.grid_cell_row = vp.data().id;
        }
    }

    const id_extra: usize = (cell_opts.col << @bitSizeOf(usize) / 2) | cell_opts.row;
    const defs: dvui.Options = .{ .role = .grid_cell, .rect = rect, .id_extra = id_extra };

    self.cell_widget.init(@src(), .{ .table = self, .col = cell_opts.col, .row = cell_opts.row, .grid_focus = grid_focus, .draw_focus = cell_opts.draw_focus }, defs.override(opts));

    // now that cell_widget has done init/register, we can reset grid_cell_row
    dvui.currentWindow().accesskit.grid_cell_row = .zero;
    if (!self.layout_only) {
        if (self.cell_widget.data().accesskit_node()) |ak_node| {
            dvui.AccessKit.nodeSetRowIndex(ak_node, cell_opts.row);
            dvui.AccessKit.nodeSetColumnIndex(ak_node, cell_opts.col);
        }
    }

    return &self.cell_widget;
}

pub fn cellMinSize(self: *TableWidget, col: usize, row: usize, min_size: dvui.Size) void {
    while (col >= self.col_widths_auto.items.len) {
        self.col_widths_auto.append(dvui.currentWindow().arena(), 10) catch {};
    }
    if (col < self.col_widths_auto.items.len) {
        const w = std.math.clamp(min_size.w, COL_MIN_WIDTH, self.auto_size_max.*.w);
        self.col_widths_auto.items[col] = @max(self.col_widths_auto.items[col], w);
    }

    if (row == std.math.maxInt(usize)) {
        self.col_header_height_auto = @max(self.col_header_height_auto, min_size.h);
    } else {
        const h = std.math.clamp(min_size.h, ROW_MIN_HEIGHT, self.auto_size_max.*.h);
        self.row_height_default.* = @max(ROW_MIN_HEIGHT, @min(self.row_height_default.*, h));

        const pp = std.sort.partitionPoint(RowHeight, self.row_heights_auto.items, row, RowHeight.lower);
        if (pp == self.row_heights_auto.items.len or self.row_heights_auto.items[pp].row > row) {
            self.row_heights_auto.insert(dvui.currentWindow().arena(), pp, .{ .row = row, .height = h }) catch {};
        } else {
            self.row_heights_auto.items[pp].height = @max(self.row_heights_auto.items[pp].height, h);
        }
    }
}

pub fn cellFromPoint(self: *TableWidget, p: dvui.Point.Physical) ?Cell {
    self.ensureBodyScroll();

    const logical = self.bscroll.?.pointFromPhysical(p);
    if (logical.x < 0 or logical.y < 0) return null;

    var col: usize = 0;
    var x: f32 = 0;
    while (x < logical.x) {
        x += self.colWidth(col);
        col += 1;
    }

    var row = self.first_visible_row;
    var y = self.first_visible_row_y;
    while (y < logical.y) {
        y += self.rowHeight(row);
        row += 1;
    }
    return .{
        .col = col -| 1,
        .row = row -| 1,
    };
}

pub fn matchEvent(self: *TableWidget, e: *dvui.Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn moveCursor(self: *TableWidget, col: usize, row: usize) void {
    self.cursor.col = @min(self.cols -| 1, col);
    self.cursor.row = @min(self.rows -| 1, row);
    self.scroll_to_cursor = true;
}

/// False if trying to move past the last cell (or backwards past the first).
pub fn moveCursorTab(self: *TableWidget, shift: bool) bool {
    if (shift) {
        // move backwards
        if (self.cursor.col == 0) {
            if (self.cursor.row == 0) {
                // at the first cell, nowhere to go
                return false;
            } else {
                self.moveCursor(self.cols -| 1, self.cursor.row - 1);
            }
        } else {
            self.moveCursor(self.cursor.col - 1, self.cursor.row);
        }
    } else {
        if (self.cursor.col + 1 == self.cols) {
            if (self.cursor.row + 1 == self.rows) {
                // at the final cell, nowhere to go
                return false;
            } else {
                self.moveCursor(0, self.cursor.row + 1);
            }
        } else {
            self.moveCursor(self.cursor.col + 1, self.cursor.row);
        }
    }

    return true;
}

pub fn deinit(self: *TableWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;

    self.ensureBodyScroll();

    if (!self.layout_only) {
        // do this at the end so the body of the table comes after the headers
        dvui.tabIndexSet(self.data().id, self.data().options.tab_index, self.data().rectScale().r);

        const focus_id = dvui.lastFocusedIdInFrameSince(self.last_focus);

        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatch(e, .{ .id = self.data().id, .focus_id = focus_id, .r = self.data().borderRectScale().r })) continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .focus) {
                        e.handle(@src(), self.data());
                        // focus so that we can receive keyboard input
                        dvui.focusWidget(self.data().id, null, e.num);
                        dvui.dataSet(null, self.data().id, "__focus_touch", me.button.touch());
                    } else if (me.action == .press and me.button.pointer()) {
                        e.handle(@src(), self.data());
                        if (self.cellFromPoint(me.p)) |cel| {
                            self.moveCursor(cel.col, cel.row);
                            dvui.refresh(null, @src(), self.data().id);
                        }
                    }
                },
                .key => |*ke| {
                    if (ke.action == .down or ke.action == .repeat) {
                        if (ke.matchBind("char_up")) {
                            e.handle(@src(), self.data());
                            self.moveCursor(self.cursor.col, self.cursor.row -| 1);
                            dvui.focusWidget(self.data().id, null, e.num);
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                        if (ke.matchBind("char_down")) {
                            e.handle(@src(), self.data());
                            self.moveCursor(self.cursor.col, self.cursor.row + 1);
                            dvui.focusWidget(self.data().id, null, e.num);
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                        if (ke.matchBind("char_left")) {
                            e.handle(@src(), self.data());
                            self.moveCursor(self.cursor.col -| 1, self.cursor.row);
                            dvui.focusWidget(self.data().id, null, e.num);
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                        if (ke.matchBind("char_right")) {
                            e.handle(@src(), self.data());
                            self.moveCursor(self.cursor.col + 1, self.cursor.row);
                            dvui.focusWidget(self.data().id, null, e.num);
                            dvui.refresh(null, @src(), self.data().id);
                            continue;
                        }
                        if (ke.code == .tab) {
                            if (self.moveCursorTab(ke.mod.shift())) {
                                e.handle(@src(), self.data());
                                dvui.focusWidget(self.data().id, null, e.num);
                                dvui.refresh(null, @src(), self.data().id);
                            } else {
                                // let dvui move focus outside the table
                            }
                            continue;
                        }
                    }
                },
                else => {},
            }

            if (!e.handled) {
                self.bscroll.?.processEventAfter(e);
            }
        }
    }

    var tw: f32 = 0;
    for (self.col_widths) |w| tw += w;
    const s: dvui.Size = .{ .w = tw, .h = self.rowOffset(self.rows) };
    self.bscroll.?.minSizeForChild(s);
    self.bscroll.?.deinit();

    self.scroll.deinit();

    // sync header and main scroll info
    if (self.csi.viewport.x != self.frame_viewport.x) self.msi.viewport.x = self.csi.viewport.x;
    if (self.msi.viewport.x != self.frame_viewport.x) self.csi.viewport.x = self.msi.viewport.x;

    dvui.dataSet(null, self.data().id, "__cols", @as(usize, @intCast(self.max_seen_col + 1)));
    dvui.dataSet(null, self.data().id, "__rows", @as(usize, @intCast(self.max_seen_row + 1)));
    if (!self.layout_only) {
        if (self.data().accesskit_node()) |ak_node| {
            const num_rows = if (self.rows_provided) self.rows else @as(usize, @intCast(self.max_seen_row + 1));
            dvui.AccessKit.nodeSetRowCount(ak_node, num_rows);
            dvui.AccessKit.nodeSetColumnCount(ak_node, @intCast(self.max_seen_col + 1));
        }
    }

    if (self.auto_size) |which| {
        var auto_size_next_frame = false;

        if (which == .cols or which == .both) {
            for (self.col_widths_auto.items, 0..) |w, col| {
                if (col >= self.col_widths.len or w != self.col_widths[col]) {
                    //std.debug.print("col {d} prev {d} new {d}\n", .{ col, if (col >= self.col_widths.len) -1 else self.col_widths[col], w });
                    auto_size_next_frame = true;
                }
            }

            dvui.dataSetSlice(null, self.data().id, "__col_widths", self.col_widths_auto.items);
        }

        if (which == .rows or which == .both) {
            for (self.row_heights_auto.items) |rh| {
                if (rh.height != self.rowHeight(rh.row)) {
                    //std.debug.print("row {d} prev {d} new {d}\n", .{ rh.row, self.rowHeight(rh.row), rh.height });
                    auto_size_next_frame = true;
                }
            }

            // merge existing row heights into ones we saw this frame
            for (self.row_heights) |rh| {
                const pp = std.sort.partitionPoint(RowHeight, self.row_heights_auto.items, rh.row, RowHeight.lower);
                if (pp == self.row_heights_auto.items.len or self.row_heights_auto.items[pp].row > rh.row) {
                    self.row_heights_auto.insert(dvui.currentWindow().arena(), pp, rh) catch {};
                }
            }
            dvui.dataSetSlice(null, self.data().id, "__row_heights", self.row_heights_auto.items);
            self.col_header_height.* = self.col_header_height_auto;
        }

        if (auto_size_next_frame) {
            //std.debug.print("auto sizing next frame\n", .{});
            dvui.dataSet(null, self.data().id, "__auto_size", which);
            dvui.refresh(null, @src(), self.data().id);
        }
    }

    if (self.auto_size == null or self.auto_size.? == .rows) {
        dvui.dataSetSlice(null, self.data().id, "__col_widths", self.col_widths);
    }

    if (self.auto_size == null or self.auto_size.? == .cols) {
        dvui.dataSetSlice(null, self.data().id, "__row_heights", self.row_heights);
    }

    dvui.dataSet(null, self.data().id, "__cursor", self.cursor);
    dvui.dataSet(null, self.data().id, "__scroll_to_cursor", self.scroll_to_cursor);

    dvui.dataSet(null, self.data().id, "__sort_dir", self.sort_dir);
    dvui.dataSet(null, self.data().id, "__sort_col", self.sort_col);

    dvui.dataSet(null, self.data().id, "__csi", self.csi);

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}
