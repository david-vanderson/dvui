const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const ReorderWidget = @This();

wd: WidgetData = undefined,
id_reorderable: ?usize = null, // matches Reorderable.reorder_id
drag_point: ?dvui.Point = null,
drag_ending: bool = false,
reorderable_size: Size = .{},
found_slot: bool = false,

pub fn init(src: std.builtin.SourceLocation, opts: Options) ReorderWidget {
    var self = ReorderWidget{};
    const defaults = Options{ .name = "Reorder" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.id_reorderable = dvui.dataGet(null, self.wd.id, "_id_reorderable", usize) orelse null;
    self.drag_point = dvui.dataGet(null, self.wd.id, "_drag_point", dvui.Point) orelse null;
    self.reorderable_size = dvui.dataGet(null, self.wd.id, "_reorderable_size", dvui.Size) orelse dvui.Size{};
    return self;
}

pub fn install(self: *ReorderWidget) !void {
    try self.wd.register();
    try self.wd.borderAndBackground(.{});

    dvui.parentSet(self.widget());
}

pub fn needFinalSlot(self: *ReorderWidget) bool {
    return self.drag_point != null and !self.found_slot;
}

pub fn finalSlot(self: *ReorderWidget) !bool {
    if (self.needFinalSlot()) {
        var r = try self.reorderable(@src(), .{ .last_slot = true }, .{});
        defer r.deinit();

        if (r.insertBefore()) {
            return true;
        }
    }

    return false;
}

pub fn widget(self: *ReorderWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *ReorderWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *ReorderWidget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *ReorderWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *ReorderWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn matchEvent(self: *ReorderWidget, e: *dvui.Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *ReorderWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn processEvent(self: *ReorderWidget, e: *dvui.Event, bubbling: bool) void {
    _ = bubbling;

    if (dvui.captured(self.wd.id)) {
        switch (e.evt) {
            .mouse => |me| {
                if ((me.action == .press or me.action == .release) and me.button.pointer()) {
                    self.drag_ending = true;
                    dvui.captureMouse(null);
                    dvui.dragEnd();
                    dvui.refresh(null, @src(), self.wd.id);
                } else if (me.action == .motion) {
                    self.drag_point = me.p;

                    var scrolldrag = dvui.Event{ .evt = .{ .scroll_drag = .{
                        .mouse_pt = me.p,
                        .screen_rect = self.wd.rectScale().r,
                        .capture_id = self.wd.id,
                    } } };
                    self.wd.parent.processEvent(&scrolldrag, true);
                }
            },
            else => {},
        }
    }

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *ReorderWidget) void {
    if (self.drag_ending) {
        self.id_reorderable = null;
        self.drag_point = null;
    }

    if (self.id_reorderable) |idr| {
        dvui.dataSet(null, self.wd.id, "_id_reorderable", idr);
    } else {
        dvui.dataRemove(null, self.wd.id, "_id_reorderable");
    }

    if (self.drag_point) |dp| {
        dvui.dataSet(null, self.wd.id, "_drag_point", dp);
    } else {
        dvui.dataRemove(null, self.wd.id, "_drag_point");
    }

    dvui.dataSet(null, self.wd.id, "_reorderable_size", self.reorderable_size);

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
}

pub fn dragStart(self: *ReorderWidget, reorder_id: usize, p: dvui.Point) void {
    self.id_reorderable = reorder_id;
    self.drag_point = p;
    self.found_slot = true;
    dvui.captureMouseWD(self.data());
}

pub const draggableInitOptions = struct {
    tvg_bytes: ?[]const u8 = null,
    top_left: ?dvui.Point = null,
    reorderable: ?*Reorderable = null,
};

pub fn draggable(src: std.builtin.SourceLocation, init_opts: draggableInitOptions, opts: dvui.Options) !?dvui.Point {
    var iw = try dvui.IconWidget.init(src, "reorder_drag_icon", init_opts.tvg_bytes orelse dvui.entypo.menu, opts);
    try iw.install();
    var ret: ?dvui.Point = null;
    loop: for (dvui.events()) |*e| {
        if (!iw.matchEvent(e))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .press and me.button.pointer()) {
                    e.handled = true;
                    dvui.captureMouseWD(iw.data());
                    const reo_top_left: ?dvui.Point = if (init_opts.reorderable) |reo| reo.wd.rectScale().r.topLeft() else null;
                    const top_left: ?dvui.Point = init_opts.top_left orelse reo_top_left;
                    dvui.dragPreStart(me.p, .{ .offset = (top_left orelse iw.wd.rectScale().r.topLeft()).diff(me.p) });
                } else if (me.action == .motion) {
                    if (dvui.captured(iw.wd.id)) {
                        e.handled = true;
                        if (dvui.dragging(me.p)) |_| {
                            ret = me.p;
                            if (init_opts.reorderable) |reo| {
                                reo.reorder.dragStart(reo.wd.id, me.p); // reorder grabs capture
                            }
                            break :loop;
                        }
                    }
                }
            },
            else => {},
        }
    }
    try iw.draw();
    iw.deinit();
    return ret;
}

pub fn reorderable(self: *ReorderWidget, src: std.builtin.SourceLocation, init_opts: Reorderable.InitOptions, opts: Options) !*Reorderable {
    const ret = try dvui.currentWindow().arena().create(Reorderable);
    ret.* = Reorderable.init(src, self, init_opts, opts);
    try ret.install();
    return ret;
}

pub const Reorderable = struct {
    pub const InitOptions = struct {

        // set to true for a reorderable that represents a final empty slot in
        // the list shown during dragging
        last_slot: bool = false,

        // if null, uses widget id
        // if non-null, must be unique among reorderables in a single reorder
        reorder_id: ?usize = null,

        // if false, caller responsible for drawing something when targetRectScale() returns true
        draw_target: bool = true,

        // if false, caller responsible for calling reinstall() when targetRectScale() returns true
        reinstall: bool = true,
    };

    wd: WidgetData = undefined,
    reorder: *ReorderWidget = undefined,
    init_options: InitOptions = undefined,
    options: Options = undefined,
    installed: bool = false,
    floating_widget: ?dvui.FloatingWidget = null,
    target_rs: ?dvui.RectScale = null,

    pub fn init(src: std.builtin.SourceLocation, reorder: *ReorderWidget, init_opts: InitOptions, opts: Options) Reorderable {
        var self = Reorderable{};
        self.reorder = reorder;
        const defaults = Options{ .name = "Reorderable" };
        self.init_options = init_opts;
        self.options = defaults.override(opts);
        self.wd = WidgetData.init(src, .{}, self.options.override(.{ .rect = .{} }));

        return self;
    }

    // can call this after init before install
    pub fn floating(self: *Reorderable) bool {
        // if drag_point is non-null, id_reorderable is non-null
        if (self.reorder.drag_point != null and self.reorder.id_reorderable.? == (self.init_options.reorder_id orelse self.wd.id)) {
            return true;
        }

        return false;
    }

    pub fn install(self: *Reorderable) !void {
        self.installed = true;
        if (self.reorder.drag_point) |dp| {
            const topleft = dp.plus(dvui.dragOffset());
            if (self.reorder.id_reorderable.? == (self.init_options.reorder_id orelse self.wd.id)) {
                // we are being dragged - put in floating widget
                try self.wd.register();
                dvui.parentSet(self.widget());

                self.floating_widget = dvui.FloatingWidget.init(@src(), .{ .rect = Rect.fromPoint(topleft.scale(1 / dvui.windowNaturalScale())), .min_size_content = self.reorder.reorderable_size });
                try self.floating_widget.?.install();
            } else {
                if (self.init_options.last_slot) {
                    self.wd = WidgetData.init(self.wd.src, .{}, self.options.override(.{ .min_size_content = self.reorder.reorderable_size }));
                } else {
                    self.wd = WidgetData.init(self.wd.src, .{}, self.options);
                }
                const rs = self.wd.rectScale();
                const dragRect = Rect.fromPoint(topleft).toSize(self.reorder.reorderable_size.scale(rs.s));

                if (!self.reorder.found_slot and !rs.r.intersect(dragRect).empty()) {
                    // user is dragging a reorderable over this rect
                    self.target_rs = rs;
                    self.reorder.found_slot = true;

                    if (self.init_options.draw_target) {
                        try rs.r.fill(.{}, dvui.themeGet().color_accent);
                    }

                    if (self.init_options.reinstall and !self.init_options.last_slot) {
                        try self.reinstall();
                    }
                }

                if (self.target_rs == null or self.init_options.last_slot) {
                    try self.wd.register();
                    dvui.parentSet(self.widget());
                }
            }
        } else {
            self.wd = WidgetData.init(self.wd.src, .{}, self.options);
            self.reorder.reorderable_size = self.wd.rect.size();

            try self.wd.register();
            dvui.parentSet(self.widget());
        }
    }

    pub fn targetRectScale(self: *Reorderable) ?dvui.RectScale {
        return self.target_rs;
    }

    pub fn removed(self: *Reorderable) bool {
        // if drag_ending is true, id_reorderable is non-null
        if (self.reorder.drag_ending and self.reorder.id_reorderable.? == (self.init_options.reorder_id orelse self.wd.id)) {
            return true;
        }

        return false;
    }

    // must be called after install()
    pub fn insertBefore(self: *Reorderable) bool {
        if (!self.installed) {
            dvui.log.err("Reorderable.insertBefore() must be called after install()", .{});
            std.debug.assert(false);
        }

        if (self.reorder.drag_ending and self.target_rs != null) {
            return true;
        }

        return false;
    }

    pub fn reinstall(self: *Reorderable) !void {
        // send our target rect to the parent for sizing
        self.wd.minSizeMax(self.wd.rect.size());
        self.wd.minSizeReportToParent();

        // reinstall ourselves getting the next rect from parent
        self.wd = WidgetData.init(self.wd.src, .{}, self.options);
        try self.wd.register();
        dvui.parentSet(self.widget());
    }

    pub fn widget(self: *Reorderable) Widget {
        return Widget.init(self, Reorderable.data, Reorderable.rectFor, Reorderable.screenRectScale, Reorderable.minSizeForChild, Reorderable.processEvent);
    }

    pub fn data(self: *Reorderable) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Reorderable, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        _ = id;
        return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
    }

    pub fn screenRectScale(self: *Reorderable, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToRectScale(rect);
    }

    pub fn minSizeForChild(self: *Reorderable, s: Size) void {
        self.wd.minSizeMax(self.wd.options.padSize(s));
    }

    pub fn processEvent(self: *Reorderable, e: *dvui.Event, bubbling: bool) void {
        _ = bubbling;

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Reorderable) void {
        if (self.floating_widget) |*fw| {
            self.wd.minSizeMax(fw.wd.min_size);
            fw.deinit();
        }

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();

        dvui.parentReset(self.wd.id, self.wd.parent);
    }
};

pub fn reorderSlice(comptime T: type, slice: []T, removed_idx: ?usize, insert_before_idx: ?usize) bool {
    if (removed_idx) |ri| {
        if (insert_before_idx) |ibi| {
            // save this index
            const removed = slice[ri];
            if (ri < ibi) {
                // moving down, shift others up
                for (ri..ibi - 1) |i| {
                    slice[i] = slice[i + 1];
                }
                slice[ibi - 1] = removed;
            } else {
                // moving up, shift others down
                for (ibi..ri, 0..) |_, i| {
                    slice[ri - i] = slice[ri - i - 1];
                }
                slice[ibi] = removed;
            }

            return true;
        }
    }

    return false;
}
