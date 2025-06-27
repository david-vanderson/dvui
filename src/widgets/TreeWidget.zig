const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

const TreeWidget = @This();

wd: WidgetData = undefined,
vbox: dvui.BoxWidget = undefined,
id_branch: ?usize = null, // matches Reorderable.reorder_id
drag_point: ?dvui.Point.Physical = null,
drag_ending: bool = false,
branch_size: Size = .{},
found_slot: bool = false,

pub fn init(src: std.builtin.SourceLocation, opts: Options) TreeWidget {
    var self = TreeWidget{};
    const defaults = Options{ .name = "Tree" };
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.id_branch = dvui.dataGet(null, self.wd.id, "_id_branch", usize) orelse null;
    self.drag_point = dvui.dataGet(null, self.wd.id, "_drag_point", dvui.Point.Physical) orelse null;
    self.branch_size = dvui.dataGet(null, self.wd.id, "_branch_size", dvui.Size) orelse dvui.Size{};
    return self;
}

pub fn install(self: *TreeWidget) void {
    self.wd.register();
    self.wd.borderAndBackground(.{});

    dvui.parentSet(self.widget());

    self.vbox = dvui.BoxWidget.init(@src(), .{ .dir = .vertical }, self.wd.options);
    self.vbox.install();
    self.vbox.drawBackground();
}

pub fn tree(src: std.builtin.SourceLocation, opts: Options) *TreeWidget {
    var ret = dvui.widgetAlloc(TreeWidget);
    ret.* = TreeWidget.init(src, opts);
    ret.install();
    ret.processEvents();
    return ret;
}

pub fn needFinalSlot(self: *TreeWidget) bool {
    return self.drag_point != null and !self.found_slot;
}

pub fn finalSlot(self: *TreeWidget) bool {
    if (self.needFinalSlot()) {
        var r = self.branch(@src(), .{ .last_slot = true }, .{});
        defer r.deinit();

        if (r.insertBefore()) {
            return true;
        }
    }

    return false;
}

pub fn widget(self: *TreeWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
}

pub fn data(self: *TreeWidget) *WidgetData {
    return &self.wd;
}

pub fn rectFor(self: *TreeWidget, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *TreeWidget, rect: Rect) RectScale {
    return self.wd.contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *TreeWidget, s: Size) void {
    self.wd.minSizeMax(self.wd.options.padSize(s));
}

pub fn matchEvent(self: *TreeWidget, e: *dvui.Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *TreeWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn processEvent(self: *TreeWidget, e: *dvui.Event, bubbling: bool) void {
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

pub fn deinit(self: *TreeWidget) void {
    self.vbox.deinit();

    defer dvui.widgetFree(self);
    if (self.drag_ending) {
        self.id_branch = null;
        self.drag_point = null;
    }

    if (self.id_branch) |idr| {
        dvui.dataSet(null, self.wd.id, "_id_branch", idr);
    } else {
        dvui.dataRemove(null, self.wd.id, "_id_branch");
    }

    if (self.drag_point) |dp| {
        dvui.dataSet(null, self.wd.id, "_drag_point", dp);
    } else {
        dvui.dataRemove(null, self.wd.id, "_drag_point");
    }

    dvui.dataSet(null, self.wd.id, "_branch_size", self.branch_size);

    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    dvui.parentReset(self.wd.id, self.wd.parent);
    self.* = undefined;
}

pub fn dragStart(self: *TreeWidget, branch_id: usize, p: dvui.Point.Physical) void {
    self.id_branch = branch_id;
    self.drag_point = p;
    self.found_slot = true;
    dvui.captureMouse(self.data());
}

// pub const draggableInitOptions = struct {
//     tvg_bytes: ?[]const u8 = null,
//     top_left: ?dvui.Point.Physical = null,
//     reorderable: ?*Branch = null,
// };

// pub fn draggable(src: std.builtin.SourceLocation, init_opts: draggableInitOptions, opts: dvui.Options) ?dvui.Point.Physical {
//     var iw = dvui.IconWidget.init(src, "reorder_drag_icon", init_opts.tvg_bytes orelse dvui.entypo.menu, .{}, opts);
//     iw.install();
//     var ret: ?dvui.Point.Physical = null;
//     loop: for (dvui.events()) |*e| {
//         if (!iw.matchEvent(e))
//             continue;

//         switch (e.evt) {
//             .mouse => |me| {
//                 if (me.action == .press and me.button.pointer()) {
//                     e.handle(@src(), iw.data());
//                     dvui.captureMouse(iw.data());
//                     const reo_top_left: ?dvui.Point.Physical = if (init_opts.reorderable) |reo| reo.wd.rectScale().r.topLeft() else null;
//                     const top_left: ?dvui.Point.Physical = init_opts.top_left orelse reo_top_left;
//                     dvui.dragPreStart(me.p, .{ .offset = (top_left orelse iw.wd.rectScale().r.topLeft()).diff(me.p) });
//                 } else if (me.action == .motion) {
//                     if (dvui.captured(iw.wd.id)) {
//                         e.handle(@src(), iw.data());
//                         if (dvui.dragging(me.p)) |_| {
//                             ret = me.p;
//                             if (init_opts.reorderable) |reo| {
//                                 reo.tree.dragStart(reo.wd.id.asUsize(), me.p); // reorder grabs capture
//                             }
//                             break :loop;
//                         }
//                     }
//                 }
//             },
//             else => {},
//         }
//     }
//     iw.draw();
//     iw.deinit();
//     return ret;
// }

pub fn branch(self: *TreeWidget, src: std.builtin.SourceLocation, init_opts: Branch.InitOptions, opts: Options) *Branch {
    const ret = dvui.widgetAlloc(Branch);
    ret.* = Branch.init(src, self, init_opts, opts);
    ret.install();
    return ret;
}

pub const Branch = struct {
    pub const InitOptions = struct {
        // if true, the branch is currently expanded
        expanded: bool = false,

        // set to true for a reorderable that represents a final empty slot in
        // the list shown during dragging
        last_slot: bool = false,

        // if null, uses widget id
        // if non-null, must be unique among reorderables in a single reorder
        branch_id: ?usize = null,

        // if false, caller responsible for drawing something when targetRectScale() returns true
        draw_target: bool = true,

        // if false, caller responsible for calling reinstall() when targetRectScale() returns true
        reinstall: bool = true,
    };

    wd: WidgetData = undefined,
    button: dvui.ButtonWidget = undefined,
    hbox: dvui.BoxWidget = undefined,
    vbox: dvui.BoxWidget = undefined,
    expander_vbox: dvui.BoxWidget = undefined,
    tree: *TreeWidget = undefined,
    init_options: InitOptions = undefined,
    options: Options = undefined,
    installed: bool = false,
    floating_widget: ?dvui.FloatingWidget = null,
    target_rs: ?dvui.RectScale = null,
    expanded: bool = false,
    can_expand: bool = false,

    pub fn init(src: std.builtin.SourceLocation, reorder: *TreeWidget, init_opts: InitOptions, opts: Options) Branch {
        var self = Branch{};
        self.tree = reorder;
        const defaults = Options{ .name = "Branch" };
        self.init_options = init_opts;
        self.options = defaults.override(opts);
        self.wd = WidgetData.init(src, .{}, self.options.override(.{ .rect = .{} }));
        self.expanded = if (dvui.dataGet(null, self.wd.id, "_expanded", bool)) |e| e else init_opts.expanded;

        return self;
    }

    // can call this after init before install
    pub fn floating(self: *Branch) bool {
        // if drag_point is non-null, id_reorderable is non-null
        if (self.tree.drag_point != null and self.tree.id_branch.? == (self.init_options.branch_id orelse self.wd.id.asUsize())) {
            return true;
        }

        return false;
    }

    pub fn install(self: *Branch) void {
        self.installed = true;
        if (self.tree.drag_point) |dp| {
            const topleft = dp.plus(dvui.dragOffset());
            if (self.tree.id_branch.? == (self.init_options.branch_id orelse self.wd.id.asUsize())) {
                // we are being dragged - put in floating widget
                self.wd.register();
                dvui.parentSet(self.widget());

                self.floating_widget = dvui.FloatingWidget.init(@src(), .{ .rect = Rect.fromPoint(.cast(topleft.toNatural())), .min_size_content = self.tree.branch_size });
                self.floating_widget.?.install();
            } else {
                if (self.init_options.last_slot) {
                    self.wd = WidgetData.init(self.wd.src, .{}, self.options.override(.{ .min_size_content = self.tree.branch_size }));
                } else {
                    self.wd = WidgetData.init(self.wd.src, .{}, self.options);
                }
                const rs = self.button.wd.rectScale();
                const dragRect = Rect.Physical.fromPoint(topleft).toSize(self.tree.branch_size.scale(rs.s, Size.Physical));

                if (!self.tree.found_slot and !rs.r.intersect(dragRect).empty()) {
                    // user is dragging a reorderable over this rect
                    self.target_rs = rs;
                    self.tree.found_slot = true;

                    if (self.init_options.draw_target) {
                        rs.r.fill(.{}, .{ .color = dvui.themeGet().color_accent });
                    }

                    if (self.init_options.reinstall and !self.init_options.last_slot) {
                        self.reinstall();
                    }
                }

                if (self.target_rs == null or self.init_options.last_slot) {
                    self.wd.register();
                    dvui.parentSet(self.widget());
                }
            }
        } else {
            self.wd = WidgetData.init(self.wd.src, .{}, self.options);

            self.wd.register();
            dvui.parentSet(self.widget());

            const no_padding = Options{
                .name = "Padding",
                .padding = dvui.Rect.all(0),
                .margin = dvui.Rect.all(0),
            };

            self.vbox = dvui.BoxWidget.init(@src(), .{ .dir = .vertical }, no_padding.override(self.options));
            self.vbox.install();
            self.vbox.drawBackground();

            self.tree.branch_size = self.vbox.wd.rect.size();

            self.button = dvui.ButtonWidget.init(@src(), .{}, no_padding.override(self.options));
            self.button.install();
            self.button.processEvents();
            self.button.drawBackground();

            self.hbox = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal }, no_padding.override(self.options));
            self.hbox.install();
            self.hbox.drawBackground();

            loop: for (dvui.events()) |*e| {
                if (!self.button.matchEvent(e))
                    continue;

                switch (e.evt) {
                    .mouse => |me| {
                        if (me.action == .press and me.button.pointer()) {
                            e.handle(@src(), self.button.data());
                            dvui.captureMouse(self.button.data());
                            const top_left = self.button.wd.rectScale().r.topLeft();
                            dvui.dragPreStart(me.p, .{ .offset = top_left });
                        } else if (me.action == .motion) {
                            if (dvui.captured(self.button.wd.id)) {
                                e.handle(@src(), self.button.data());
                                if (dvui.dragging(me.p)) |_| {
                                    self.tree.dragStart(self.wd.id.asUsize(), me.p); // reorder grabs capture

                                    break :loop;
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        }
    }

    pub const ExpanderOptions = struct {
        indent: u32 = 10,
    };

    pub fn expander(self: *Branch, src: std.builtin.SourceLocation, init_opts: ExpanderOptions, opts: Options) bool {
        if (self.button.clicked()) {
            self.expanded = !self.expanded;
        }

        self.hbox.deinit();
        self.button.deinit();

        const defaults = Options{
            .name = "Expander",
            .border = .{ .x = 1 },
            .margin = .{ .x = @as(f32, @floatFromInt(init_opts.indent)) },
            .background = true,
        };

        self.expander_vbox = dvui.BoxWidget.init(src, .{ .dir = .vertical }, defaults.override(opts));
        self.expander_vbox.install();
        self.expander_vbox.drawBackground();

        self.can_expand = true;

        return self.expanded;
    }

    pub fn targetRectScale(self: *Branch) ?dvui.RectScale {
        return self.target_rs;
    }

    pub fn removed(self: *Branch) bool {
        // if drag_ending is true, id_reorderable is non-null
        if (self.tree.drag_ending and self.tree.id_branch.? == (self.init_options.branch_id orelse self.wd.id.asUsize())) {
            return true;
        }

        return false;
    }

    // must be called after install()
    pub fn insertBefore(self: *Branch) bool {
        if (!self.installed) {
            dvui.log.err("Branch.insertBefore() must be called after install()", .{});
            std.debug.assert(false);
        }

        if (self.tree.drag_ending and self.target_rs != null) {
            return true;
        }

        return false;
    }

    pub fn reinstall(self: *Branch) void {
        // send our target rect to the parent for sizing
        self.wd.minSizeMax(self.button.wd.rect.size());
        self.wd.minSizeReportToParent();

        // reinstall ourselves getting the next rect from parent
        self.wd = WidgetData.init(self.wd.src, .{}, self.options);
        self.wd.register();
        dvui.parentSet(self.widget());

        self.button = dvui.ButtonWidget.init(@src(), .{}, self.options);
        self.button.install();
        self.button.processEvents();
        self.button.drawBackground();

        self.hbox = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal }, self.options);
        self.hbox.install();
        self.hbox.drawBackground();
    }

    pub fn widget(self: *Branch) Widget {
        return Widget.init(self, Branch.data, Branch.rectFor, Branch.screenRectScale, Branch.minSizeForChild, Branch.processEvent);
    }

    pub fn data(self: *Branch) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Branch, id: dvui.WidgetId, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        _ = id;
        return dvui.placeIn(self.wd.contentRect().justSize(), min_size, e, g);
    }

    pub fn screenRectScale(self: *Branch, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToRectScale(rect);
    }

    pub fn minSizeForChild(self: *Branch, s: Size) void {
        self.wd.minSizeMax(self.wd.options.padSize(s));
    }

    pub fn processEvent(self: *Branch, e: *dvui.Event, bubbling: bool) void {
        _ = bubbling;

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Branch) void {
        if (self.can_expand) {
            self.expander_vbox.deinit();

            if (self.expanded) {
                dvui.dataSet(null, self.wd.id, "_expanded", self.expanded);
            } else {
                dvui.dataRemove(null, self.wd.id, "_expanded");
            }
        } else {
            self.hbox.deinit();
            self.button.deinit();
        }
        self.vbox.deinit();

        defer dvui.widgetFree(self);
        if (self.floating_widget) |*fw| {
            self.wd.minSizeMax(fw.wd.min_size);
            fw.deinit();
        }

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();

        dvui.parentReset(self.wd.id, self.wd.parent);

        self.* = undefined;
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

test {
    @import("std").testing.refAllDecls(@This());
}
