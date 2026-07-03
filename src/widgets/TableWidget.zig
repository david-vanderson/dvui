const std = @import("std");
const dvui = @import("../dvui.zig");

pub const fnv = std.hash.Fnv1a_64;

const TableWidget = @This();

pub var defaults: dvui.Options = .{
    .name = "TableWidget",
    .role = .grid,
    .corner_radius = .{ .x = 0, .y = 0, .w = 5, .h = 5 },
    .style = .content,
    .background = true,
    .border = .all(1),
};

pub const InitOptions = struct {
    /// Scroll options for the grid body
    scroll_opts: dvui.ScrollAreaWidget.InitOpts = .{},

    /// How many rows in the table.  If null use the max cell row we saw last
    /// frame.  Required to use `rowsVisible`.
    rows: ?usize,
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

pub const ROWS_SAME_HEIGHT = true;

wd: dvui.WidgetData,
cols: usize,
rows: usize,
rows_provided: bool = false,
max_seen_col: isize = -1,
max_seen_row: isize = -1,
row_height: f32,
cursor: Cell = .{ .col = 0, .row = 0 },
cell_widget: CellWidget,

auto_size: bool = false,
col_widths: []f32 = &.{},
col_expand: f32 = 0,
col_widths_auto: std.ArrayList(f32) = .empty,
col_header_height: f32 = 30,
col_header_height_auto: f32 = 0,
col_header_group: dvui.FocusGroupWidget,
row_height_auto: f32 = 10,

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
    const options = defaults.themeOverride(opts.theme).override(opts);
    self.* = .{
        .wd = dvui.WidgetData.init(src, .{ .scroll_when_focused = false }, options),
        .cell_widget = undefined,
        .cols = undefined,
        .rows = undefined,
        .col_header_group = undefined,
        .row_height = undefined,
        .scroll = undefined,
        .msi = undefined,
    };

    self.data().register();
    dvui.parentSet(self.widget());
    self.data().borderAndBackground(.{});

    self.cols = dvui.dataGet(null, self.data().id, "__cols", usize) orelse 0;
    self.rows = init_opts.rows orelse dvui.dataGet(null, self.data().id, "__rows", usize) orelse 0;
    if (init_opts.rows) |_| self.rows_provided = true;
    self.col_header_height = dvui.dataGet(null, self.data().id, "__col_header_height", f32) orelse self.col_header_height;
    self.col_widths = dvui.dataGetSlice(null, self.data().id, "__col_widths", []f32) orelse &.{};
    if (self.cols != self.col_widths.len) {
        dvui.dataSetSliceCopies(null, self.data().id, "__col_widths", @as([]const f32, &.{100.0}), self.cols);
        const old = self.col_widths;
        self.col_widths = dvui.dataGetSlice(null, self.data().id, "__col_widths", []f32).?;
        const len = @min(old.len, self.col_widths.len);
        @memcpy(self.col_widths[0..len], old[0..len]);
    }
    self.row_height = dvui.dataGet(null, self.data().id, "__row_height", f32) orelse 30;
    self.cursor = dvui.dataGet(null, self.data().id, "__cursor", Cell) orelse .{ .col = 0, .row = 0 };
    self.scroll_to_cursor = dvui.dataGet(null, self.data().id, "__scroll_to_cursor", bool) orelse false;

    self.sort_dir = dvui.dataGet(null, self.data().id, "__sort_dir", SortDirection) orelse .unsorted;
    self.sort_col = dvui.dataGet(null, self.data().id, "__sort_col", usize) orelse 0;

    self.focus_touch = dvui.dataGet(null, self.data().id, "__focus_touch", bool) orelse false;

    if (dvui.firstFrame(self.data().id)) {
        self.autoSize();
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

    if (options.expandGet().isHorizontal() and self.col_widths.len > 0) {
        var total: f32 = 0;
        for (self.col_widths) |w| total += w;
        if (total < self.msi.viewport.w) {
            self.col_expand = (self.msi.viewport.w - total) / @as(f32, @floatFromInt(self.col_widths.len));
        }
    }
}

/// Request we resize our cols/rows to fit the contents provided this frame
pub fn autoSize(self: *TableWidget) void {
    self.auto_size = true;
}

/// Return first/last row in the viewport.  Must pass `.rows` to `init`.
pub fn rowsVisible(self: *TableWidget) struct { usize, usize } {
    if (!self.rows_provided) {
        dvui.log.err("TableWidget: {x} rowsVisible() requires InitOptions.rows", .{self.data().id});
        dvui.Debug.errorOutline(self.data().rectScale().r);
        return .{ 0, self.rows };
    }

    if (self.msi.viewport.h == 0) {
        // First frame, run at least one row to auto size properly
        return .{ 0, @min(1, self.rows) };
    }

    // expand the visible rows by this on each side so keyboard navigation
    // works to unseen rows
    const extra: usize = 1;
    const start_y: f32 = @max(0, self.frame_viewport.y);
    const end_y: f32 = self.frame_viewport.y + self.msi.viewport.h;

    if (ROWS_SAME_HEIGHT) {
        const start: usize = @trunc(start_y / self.row_height);
        const end: usize = @ceil(end_y / self.row_height);
        return .{ @min(start -| extra, self.rows), @min(end + extra, self.rows) };
    }

    var s: usize = 0;
    var y: f32 = self.row_height;

    // go until bottom of row is visible
    while (s < self.rows and y < start_y) {
        s += 1;
        y += self.row_height;
    }

    const start = s;

    // switch to tracking top of row
    if (s < self.rows) s += 1;

    // go until top is not visible
    while (s < self.rows and y < end_y) {
        s += 1;
        y += self.row_height;
    }

    return .{ start -| extra, @min(s + extra, self.rows) };
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

        if (self.grid_focus) {
            const rs = self.data().backgroundRectScale();
            if (!rs.r.empty()) {
                const fill = (dvui.themeGet().text_select orelse dvui.themeGet().color(.highlight, .fill)).opacity(0.75);
                rs.r.fill(self.data().options.corner_radiusGet().scale(rs.s, dvui.Rect.Physical), .{
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
        const defs: dvui.Options = .{ .name = "Cell.editable", .margin = .{}, .border = .{}, .corner_radius = .{}, .min_size_content = .{}, .expand = .both };
        const opts = defs.override(options);
        var ret: ?[]u8 = null;

        const src = @src();
        const id = dvui.parentGet().extendId(src, opts.idExtra());
        const editing = dvui.dataGet(null, id, "__editing", bool) orelse false;

        if (!editing) {
            dvui.labelNoFmt(src, text, .{}, opts);

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
            te.init(src, .{}, opts);

            var escape = false;
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
                            self.table.moveCursorTab();
                            dvui.refresh(null, @src(), id);
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

            if (te.enter_pressed) {
                if (!std.mem.eql(u8, text, te.textGet())) ret = te.textGet();
                dvui.dataRemove(null, id, "__editing");
                dvui.focusWidget(self.table.data().id, null, 0);
                dvui.refresh(null, @src(), id);
                self.table.moveCursor(self.table.cursor.col, self.table.cursor.row + 1);
            }

            te.deinit();
        }

        return ret;
    }

    pub fn headerSortable(self: *CellWidget, text: []const u8, options: dvui.Options) ?SortDirection {
        const defs: dvui.Options = .{ .name = "Cell.headerSortable", .margin = .{}, .border = .{}, .corner_radius = .{}, .min_size_content = .{}, .expand = .both };
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

pub fn colWidth(self: *TableWidget, col: usize) f32 {
    if (col < self.col_widths.len) return self.col_widths[col] + self.col_expand;
    return 100;
}

pub fn colOffset(self: *TableWidget, col: usize) f32 {
    var x: f32 = 0;
    for (0..col) |i| x += self.colWidth(i);
    return x;
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
            self.col_header_group.init(@src(), .{ .nav_key_dir = .horizontal }, .{ .tab_index = self.data().options.tab_index });
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
        .h = self.col_header_height,
    };

    const defs: dvui.Options = .{ .rect = rect, .id_extra = @truncate(hash.final()) };

    self.cell_widget.init(@src(), .{ .table = self, .col = col, .row = std.math.maxInt(usize), .grid_focus = false }, defs.override(opts));
    return &self.cell_widget;
}

fn ensureBodyScroll(self: *TableWidget) void {
    if (self.cscroll) |*cscroll| {
        self.col_header_group.deinit();

        const s: dvui.Size = .{ .w = self.colOffset(self.cols), .h = self.col_header_height };
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
    }
}

pub fn cell(self: *TableWidget, col: usize, row: usize, opts: dvui.Options) *CellWidget {
    self.ensureBodyScroll();

    self.max_seen_col = @max(self.max_seen_col, @as(isize, @intCast(col)));
    self.max_seen_row = @max(self.max_seen_row, @as(isize, @intCast(row)));
    var hash = fnv.init();
    hash.update("col");
    hash.update(std.mem.asBytes(&col));
    hash.update("row");
    hash.update(std.mem.asBytes(&row));

    var ry: f32 = 0;
    if (ROWS_SAME_HEIGHT) {
        ry = @as(f32, @floatFromInt(row)) * self.row_height;
    } else {
        for (0..row) |_| ry += self.row_height;
    }

    const rect: dvui.Rect = .{
        .x = self.colOffset(col),
        .y = ry,
        .w = self.colWidth(col),
        .h = self.row_height,
    };

    const grid_focus = self.data().id == dvui.focusedWidgetId() and col == self.cursor.col and row == self.cursor.row;

    if (grid_focus and self.scroll_to_cursor) {
        self.scroll_to_cursor = false;
        dvui.scrollTo(.{ .screen_rect = self.bscroll.?.screenRectScale(rect).r });
    }

    const defs: dvui.Options = .{ .rect = rect, .id_extra = @truncate(hash.final()) };

    self.cell_widget.init(@src(), .{ .table = self, .col = col, .row = row, .grid_focus = grid_focus }, defs.override(opts));
    return &self.cell_widget;
}

pub fn cellMinSize(self: *TableWidget, col: usize, row: usize, min_size: dvui.Size) void {
    while (col >= self.col_widths_auto.items.len) {
        self.col_widths_auto.append(dvui.currentWindow().arena(), 10) catch {};
    }
    if (col < self.col_widths_auto.items.len) {
        self.col_widths_auto.items[col] = @max(self.col_widths_auto.items[col], min_size.w);
    }

    if (row == std.math.maxInt(usize)) {
        self.col_header_height_auto = @max(self.col_header_height_auto, min_size.h);
    } else {
        self.row_height_auto = @max(self.row_height_auto, min_size.h);
    }
}

pub fn cellFromPoint(self: *TableWidget, p: dvui.Point.Physical) ?Cell {
    var logical = self.bscroll.?.pointFromPhysical(p);
    var col: usize = 0;
    while (logical.x > 0) {
        logical.x -= self.colWidth(col);
        col += 1;
    }
    return .{
        .col = col -| 1,
        .row = @trunc(logical.y / self.row_height),
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

pub fn moveCursorTab(self: *TableWidget) void {
    if (self.cursor.col + 1 == self.cols) {
        if (self.cursor.row + 1 == self.rows) {
            // at the final cell, nowhere to go
        } else {
            self.moveCursor(0, self.cursor.row + 1);
        }
    } else {
        self.moveCursor(self.cursor.col + 1, self.cursor.row);
    }
}

pub fn deinit(self: *TableWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;

    self.ensureBodyScroll();

    // do this at the end so the body of the table comes after the headers
    dvui.tabIndexSet(self.data().id, self.data().options.tab_index, self.data().rectScale().r);

    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e)) continue;

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
                        dvui.refresh(null, @src(), self.data().id);
                        continue;
                    }
                    if (ke.matchBind("char_down")) {
                        e.handle(@src(), self.data());
                        self.moveCursor(self.cursor.col, self.cursor.row + 1);
                        dvui.refresh(null, @src(), self.data().id);
                        continue;
                    }
                    if (ke.matchBind("char_left")) {
                        e.handle(@src(), self.data());
                        self.moveCursor(self.cursor.col -| 1, self.cursor.row);
                        dvui.refresh(null, @src(), self.data().id);
                        continue;
                    }
                    if (ke.matchBind("char_right")) {
                        e.handle(@src(), self.data());
                        self.moveCursor(self.cursor.col + 1, self.cursor.row);
                        dvui.refresh(null, @src(), self.data().id);
                        continue;
                    }
                    if (ke.code == .tab) {
                        e.handle(@src(), self.data());
                        self.moveCursorTab();
                        dvui.refresh(null, @src(), self.data().id);
                        continue;
                    }
                }
            },
            else => {},
        }
    }

    const s: dvui.Size = .{ .w = self.colOffset(self.cols), .h = self.row_height * @as(f32, @floatFromInt(self.rows)) };
    self.bscroll.?.minSizeForChild(s);
    self.bscroll.?.deinit();

    self.scroll.deinit();

    // sync header and main scroll info
    if (self.csi.viewport.x != self.frame_viewport.x) self.msi.viewport.x = self.csi.viewport.x;
    if (self.msi.viewport.x != self.frame_viewport.x) self.csi.viewport.x = self.msi.viewport.x;

    dvui.dataSet(null, self.data().id, "__cols", @as(usize, @intCast(self.max_seen_col + 1)));
    dvui.dataSet(null, self.data().id, "__rows", @as(usize, @intCast(self.max_seen_row + 1)));
    dvui.dataSet(null, self.data().id, "__col_header_height", if (self.auto_size) self.col_header_height_auto else self.col_header_height);
    dvui.dataSetSlice(null, self.data().id, "__col_widths", if (self.auto_size) self.col_widths_auto.items else self.col_widths);
    dvui.dataSet(null, self.data().id, "__row_height", if (self.auto_size) self.row_height_auto else self.row_height);
    dvui.dataSet(null, self.data().id, "__cursor", self.cursor);
    dvui.dataSet(null, self.data().id, "__scroll_to_cursor", self.scroll_to_cursor);

    dvui.dataSet(null, self.data().id, "__sort_dir", self.sort_dir);
    dvui.dataSet(null, self.data().id, "__sort_col", self.sort_col);

    dvui.dataSet(null, self.data().id, "__csi", self.csi);

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}
