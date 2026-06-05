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
};

pub const InitOptions = struct {
    cols: ?usize = null,
    rows: ?usize = null,
    // Scroll options for the grid body
    scroll_opts: dvui.ScrollAreaWidget.InitOpts = .{},
};

pub const Cell = struct {
    col: usize,
    row: usize,
};

wd: dvui.WidgetData,
cols: usize,
rows: usize,
max_seen: Cell = .{ .col = 0, .row = 0 },
col_width: f32,
row_height: f32,
cursor: Cell = .{ .col = 0, .row = 0 },

msi: *dvui.ScrollInfo, // main scroll info
scroll: dvui.ScrollAreaWidget, // main scroll area
csi: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .none }, // column header scroll info
cscroll: ?dvui.ScrollAreaWidget = null, // column header scroll area
rscroll: ?dvui.ScrollAreaWidget = null, // row header scroll area
bscroll: ?dvui.ScrollContainerWidget = null, // body scroll container
frame_viewport: dvui.Point = .{}, // Fixed scroll viewport for this frame
scroll_to_cursor: bool = false,

pub fn init(self: *TableWidget, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: dvui.Options) void {
    const options = defaults.themeOverride(opts.theme).override(opts);
    self.* = .{
        .wd = dvui.WidgetData.init(src, .{ .scroll_when_focused = false }, options),
        .cols = undefined,
        .rows = undefined,
        .col_width = undefined,
        .row_height = undefined,
        .scroll = undefined,
        .msi = undefined,
    };

    self.data().register();
    dvui.parentSet(self.widget());
    self.data().borderAndBackground(.{});

    dvui.tabIndexSet(self.data().id, null, self.data().rectScale().r);

    self.cols = dvui.dataGet(null, self.data().id, "__cols", usize) orelse 0;
    self.rows = dvui.dataGet(null, self.data().id, "__rows", usize) orelse 0;
    self.col_width = dvui.dataGet(null, self.data().id, "__col_width", f32) orelse 10;
    self.row_height = dvui.dataGet(null, self.data().id, "__row_height", f32) orelse 10;
    self.cursor = dvui.dataGet(null, self.data().id, "__cursor", Cell) orelse .{ .col = 0, .row = 0 };
    self.scroll_to_cursor = dvui.dataGet(null, self.data().id, "__scroll_to_cursor", bool) orelse false;

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

pub const CellResult = struct {
    rect: dvui.Rect,
    id_extra: usize,
    focus: bool,
};

pub fn colHeader(self: *TableWidget, col: usize) CellResult {
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
        }
    }

    self.max_seen.col = @max(self.max_seen.col, col);
    var hash = fnv.init();
    hash.update("col");
    hash.update(std.mem.asBytes(&col));
    hash.update("header");

    const rect: dvui.Rect = .{
        .x = @as(f32, @floatFromInt(col)) * self.col_width,
        .y = 0,
        .w = self.col_width,
        .h = self.row_height,
    };

    return .{
        .rect = rect,
        .id_extra = hash.final(),
        .focus = false,
    };
}

fn ensureBodyScroll(self: *TableWidget) void {
    if (self.cscroll) |*cscroll| {
        var s: dvui.Size = .{ .w = @floatFromInt(self.max_seen.col + 1), .h = 1.0 };
        s.w *= self.col_width;
        s.h *= self.row_height;
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
        self.bscroll.?.processVelocity();
    }
}

pub fn cell(self: *TableWidget, col: usize, row: usize) CellResult {
    self.ensureBodyScroll();

    self.max_seen = .{
        .col = @max(self.max_seen.col, col),
        .row = @max(self.max_seen.row, row),
    };
    var hash = fnv.init();
    hash.update("col");
    hash.update(std.mem.asBytes(&col));
    hash.update("row");
    hash.update(std.mem.asBytes(&row));

    const rect: dvui.Rect = .{
        .x = @as(f32, @floatFromInt(col)) * self.col_width,
        .y = @as(f32, @floatFromInt(row)) * self.row_height,
        .w = self.col_width,
        .h = self.row_height,
    };

    const focus = self.data().id == dvui.focusedWidgetId() and col == self.cursor.col and row == self.cursor.row;

    if (focus and self.scroll_to_cursor) {
        self.scroll_to_cursor = false;
        dvui.scrollTo(.{ .screen_rect = self.bscroll.?.screenRectScale(rect).r });
    }

    return .{
        .rect = rect,
        .id_extra = hash.final(),
        .focus = focus,
    };
}

pub fn cellMinSize(self: *TableWidget, _: usize, _: usize, min_size: dvui.Size) void {
    self.col_width = @max(self.col_width, min_size.w);
    self.row_height = @max(self.row_height, min_size.h);
}

pub fn cellFromPoint(self: *TableWidget, p: dvui.Point.Physical) ?Cell {
    const logical = self.bscroll.?.pointFromPhysical(p);
    return .{
        .col = @trunc(logical.x / self.col_width),
        .row = @trunc(logical.y / self.row_height),
    };
}

/// If the user edits the value and presses enter or clicks away, we return
/// the edited value.
///
/// If the user makes no change or presses escape, return null.
pub fn cellEditable(self: *TableWidget, col: usize, row: usize, text: []const u8, options: dvui.Options) ?[]u8 {
    const cel = self.cell(col, row);

    const id = dvui.parentGet().extendId(@src(), cel.id_extra);
    const editing = dvui.dataGet(null, id, "editing", bool) orelse false;

    const src = @src();

    var wd_storage: dvui.WidgetData = undefined;
    var wd: *dvui.WidgetData = undefined;
    const defs: dvui.Options = .{ .data_out = &wd_storage, .id_extra = cel.id_extra, .rect = cel.rect, .border = .all(1), .margin = .{}, .corner_radius = .{}, .min_size_content = .{} };
    const opts = defs.override(options);
    var ret: ?[]u8 = null;

    if (!editing) {
        dvui.labelNoFmt(src, text, .{}, opts);
        wd = opts.data_out.?;

        if (cel.focus) {
            const evts = dvui.events();
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = self.data().id, .r = wd.rectScale().r })) continue;

                switch (e.evt) {
                    .mouse => |me| {
                        if (me.action == .focus) {
                            e.handle(@src(), wd);
                            // focus so that we can receive keyboard input
                            dvui.focusWidget(wd.id, null, e.num);
                        } else if (me.action == .press and me.button.pointer()) {
                            e.handle(@src(), wd);
                            dvui.dataSet(null, id, "editing", true);
                            dvui.dataSet(null, id, "editing_first_frame", true);
                            dvui.refresh(null, @src(), wd.id);
                        }
                    },
                    .key => |*ke| {
                        if (ke.action == .down and ke.code == .enter) {
                            e.handle(@src(), wd);
                            dvui.dataSet(null, id, "editing", true);
                            dvui.dataSet(null, id, "editing_first_frame", true);
                            dvui.focusWidget(wd.id, null, e.num);
                            dvui.refresh(null, @src(), wd.id);
                        }
                    },
                    else => {},
                }
            }
        }
    } else {
        var te: dvui.TextEntryWidget = undefined;
        te.init(src, .{}, opts);
        wd = opts.data_out.?;

        const evts = dvui.events();
        for (evts) |*e| {
            if (!te.matchEvent(e)) continue;

            switch (e.evt) {
                .key => |*ke| {
                    if (ke.action == .down and ke.code == .escape) {
                        e.handle(@src(), wd);
                        dvui.dataRemove(null, wd.id, "editing");
                        dvui.focusWidget(self.data().id, null, e.num);
                        dvui.refresh(null, @src(), wd.id);
                        continue;
                    }
                },
                else => {},
            }
        }

        te.processEvents();

        if (dvui.dataGet(null, id, "editing_first_frame", bool) orelse false) {
            dvui.dataRemove(null, id, "editing_first_frame");
            te.textTyped(text, false);
        }

        te.draw();

        if (wd.id != dvui.focusedWidgetIdInCurrentSubwindow()) {
            // we lost focus
            ret = te.textGet();
            dvui.dataRemove(null, id, "editing");
            dvui.refresh(null, @src(), wd.id);
        }

        if (te.enter_pressed) {
            ret = te.textGet();
            dvui.dataRemove(null, id, "editing");
            dvui.focusWidget(self.data().id, null, 0);
            dvui.refresh(null, @src(), wd.id);
            self.moveCursor(self.cursor.col, self.cursor.row + 1);
        }

        te.deinit();
    }

    self.cellMinSize(col, row, dvui.minSizeGet(wd.id).?);

    if (cel.focus) {
        const rs = dvui.parentGet().screenRectScale(cel.rect);
        rs.r.stroke(.{}, .{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus, .after = true });
    }

    return ret;
}

pub fn matchEvent(self: *TableWidget, e: *dvui.Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn moveCursor(self: *TableWidget, col: usize, row: usize) void {
    self.cursor.col = @min(self.cols, col);
    self.cursor.row = @min(self.rows, row);
    self.scroll_to_cursor = true;
}

pub fn deinit(self: *TableWidget) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;

    self.ensureBodyScroll();

    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e)) continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handle(@src(), self.data());
                    // focus so that we can receive keyboard input
                    dvui.focusWidget(self.data().id, null, e.num);
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
                }
            },
            else => {},
        }
    }

    var s: dvui.Size = .{ .w = @floatFromInt(self.max_seen.col + 1), .h = @floatFromInt(self.max_seen.row + 1) };
    s.w *= self.col_width;
    s.h *= self.row_height;
    self.bscroll.?.minSizeForChild(s);
    self.bscroll.?.deinit();

    self.scroll.deinit();

    dvui.dataSet(null, self.data().id, "__cols", self.max_seen.col);
    dvui.dataSet(null, self.data().id, "__rows", self.max_seen.row);
    dvui.dataSet(null, self.data().id, "__col_width", self.col_width);
    dvui.dataSet(null, self.data().id, "__row_height", self.row_height);
    dvui.dataSet(null, self.data().id, "__cursor", self.cursor);
    dvui.dataSet(null, self.data().id, "__scroll_to_cursor", self.scroll_to_cursor);

    dvui.dataSet(null, self.data().id, "__csi", self.csi);

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}
