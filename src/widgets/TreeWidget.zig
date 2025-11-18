const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const AccessKit = dvui.AccessKit;

const TreeWidget = @This();

wd: WidgetData = undefined,
layout: dvui.BasicLayout = .{},
id_branch: ?usize = null, // matches Reorderable.reorder_id
drag_point: ?dvui.Point.Physical = null,
drag_ending: bool = false,
branch_size: Size = .{},
current_branch_focus_id: ?dvui.Id = null,
init_options: InitOptions = undefined,
/// SAFETY: Set in `install`
group: dvui.FocusGroupWidget = undefined,

pub const InitOptions = struct {
    enable_reordering: bool = true,

    /// If not null, drags give up mouse capture and set this drag name
    drag_name: ?[]const u8 = null,
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TreeWidget {
    var self = TreeWidget{};
    const defaults = Options{ .name = "Tree", .role = .tree };
    self.init_options = init_opts;
    self.wd = WidgetData.init(src, .{}, defaults.override(opts));
    self.id_branch = dvui.dataGet(null, self.wd.id, "_id_branch", usize) orelse null;
    self.drag_point = dvui.dataGet(null, self.wd.id, "_drag_point", dvui.Point.Physical) orelse null;
    self.branch_size = dvui.dataGet(null, self.wd.id, "_branch_size", dvui.Size) orelse dvui.Size{};
    if (init_opts.drag_name) |dn| {
        if (self.drag_point != null and !dvui.dragName(dn)) {
            self.drag_ending = true;
        }
    }

    return self;
}

pub fn install(self: *TreeWidget) void {
    self.data().register();
    self.data().borderAndBackground(.{});

    dvui.parentSet(self.widget());

    self.group = dvui.FocusGroupWidget.init(@src(), .{ .nav_key_dir = .vertical }, .{});
    self.group.install();

    if (self.group.data().accesskit_node()) |ak_node| {
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.focus);
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.click);
    }
}

pub fn tree(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) *TreeWidget {
    var ret = dvui.widgetAlloc(TreeWidget);
    ret.* = TreeWidget.init(src, init_opts, opts);
    ret.data().was_allocated_on_widget_stack = true;
    ret.install();
    ret.processEvents();
    return ret;
}

pub fn widget(self: *TreeWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *TreeWidget) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *TreeWidget, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return self.layout.rectFor(self.data().contentRect().justSize(), id, min_size, e, g);
}

pub fn screenRectScale(self: *TreeWidget, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *TreeWidget, s: Size) void {
    const ms = self.layout.minSizeForChild(s);
    self.data().minSizeMax(self.data().options.padSize(ms));
}

pub fn matchEvent(self: *TreeWidget, event: *dvui.Event) bool {
    if (dvui.captured(self.wd.id) or (self.init_options.drag_name != null and dvui.dragName(self.init_options.drag_name.?))) {
        // passively listen to mouse motion
        for (dvui.events()) |*e| {
            if (e.evt == .mouse and e.evt.mouse.action == .motion) {
                self.drag_point = e.evt.mouse.p;

                dvui.scrollDrag(.{
                    .mouse_pt = e.evt.mouse.p,
                    .screen_rect = self.wd.rectScale().r,
                });
            }
        }
    }

    if (self.init_options.drag_name) |dn| {
        if (dvui.dragName(dn)) {
            return dvui.eventMatch(event, .{ .id = self.data().id, .r = self.data().borderRectScale().r, .drag_name = dn });
        }
    }

    return dvui.eventMatchSimple(event, self.data());
}

pub fn processEvents(self: *TreeWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e);
    }
}

pub fn processEvent(self: *TreeWidget, e: *dvui.Event) void {
    if (dvui.captured(self.data().id) or (self.init_options.drag_name != null and dvui.dragName(self.init_options.drag_name.?))) {
        switch (e.evt) {
            .mouse => |me| {
                if ((me.action == .press or me.action == .release) and me.button.pointer()) {
                    e.handle(@src(), self.data());
                    self.drag_ending = true;
                    dvui.captureMouse(null, e.num);
                    dvui.dragEnd();
                }
            },
            else => {},
        }
    }
}

pub fn deinit(self: *TreeWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;

    self.group.deinit();

    if (self.drag_ending) {
        self.id_branch = null;
        self.drag_point = null;
        dvui.refresh(null, @src(), self.data().id);
    }

    if (self.id_branch) |idr| {
        dvui.dataSet(null, self.data().id, "_id_branch", idr);
    } else {
        dvui.dataRemove(null, self.data().id, "_id_branch");
    }

    if (self.drag_point) |dp| {
        dvui.dataSet(null, self.data().id, "_drag_point", dp);
    } else {
        dvui.dataRemove(null, self.data().id, "_drag_point");
    }

    dvui.dataSet(null, self.data().id, "_branch_size", self.branch_size);

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

pub fn dragStart(self: *TreeWidget, branch_id: usize, p: dvui.Point.Physical) void {
    self.id_branch = branch_id;
    self.drag_point = p;
    dvui.captureMouse(self.data(), 0);
    if (self.init_options.drag_name) |dn| {
        // have to call dragStart to set the drag name
        dvui.dragStart(p, .{ .name = dn });
        dvui.captureMouse(null, 0);
    }
}

pub fn branch(self: *TreeWidget, src: std.builtin.SourceLocation, init_opts: Branch.InitOptions, opts: Options) *Branch {
    const ret = dvui.widgetAlloc(Branch);
    ret.* = Branch.init(src, self, init_opts, opts);
    ret.install();
    ret.data().was_allocated_on_widget_stack = true;
    if (ret.data().accesskit_node()) |ak_node| {
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.focus);
        AccessKit.nodeAddAction(ak_node, AccessKit.Action.click);
        // Accessibility TODO: Support expand / collapse when available.
    }
    return ret;
}

pub const Branch = struct {
    pub const InitOptions = struct {
        // if true, the branch is currently expanded
        expanded: bool = false,

        // if null, uses widget id
        // if non-null, must be unique among reorderables in a single reorder
        branch_id: ?usize = null,

        // If animation duration is greater than 0, the expander will animate accordingly
        animation_duration: i32 = 100_000,

        animation_easing: *const dvui.easing.EasingFn = dvui.easing.outQuad,
    };

    wd: WidgetData = undefined,
    layout: dvui.BasicLayout = .{},
    button: dvui.ButtonWidget = undefined,
    hbox: dvui.BoxWidget = undefined,
    expander_vbox: dvui.BoxWidget = undefined,
    tree: *TreeWidget = undefined,
    init_options: Branch.InitOptions = undefined,
    options: Options = undefined,
    installed: bool = false,
    floating_widget: ?dvui.FloatingWidget = null,
    target_rs: ?dvui.RectScale = null,
    expanded: bool = false,
    can_expand: bool = false,
    anim: ?*dvui.AnimateWidget = null,
    /// SAFETY: Set in `install`
    parent_focus_id: ?dvui.Id = undefined,

    pub fn wrapOuter(opts: Options) Options {
        var ret = opts;
        ret.tab_index = null;
        ret.border = Rect{};
        ret.padding = Rect{};
        ret.margin = .{};
        ret.background = false;
        ret.role = .none;
        ret.label = null;
        return ret;
    }

    pub fn wrapInner(opts: Options) Options {
        var ret = opts;
        ret.name = null;
        ret.expand = .horizontal;
        return ret;
    }

    pub var defaults = Options{
        .name = "Branch",
        .role = .tree_item,
        .label = .{ .label_widget = .next },
        .margin = dvui.Rect.all(1),
        .padding = dvui.Rect.all(2),
    };

    pub fn init(src: std.builtin.SourceLocation, reorder: *TreeWidget, init_opts: Branch.InitOptions, opts: Options) Branch {
        var self = Branch{};
        self.tree = reorder;
        self.init_options = init_opts;
        self.options = defaults.override(opts);
        self.wd = WidgetData.init(src, .{}, wrapOuter(self.options).override(.{ .rect = .{} }));
        self.expanded = if (dvui.dataGet(null, self.wd.id, "_expanded", bool)) |e| e else init_opts.expanded;

        return self;
    }

    // can call this after init before install
    pub fn floating(self: *Branch) bool {
        // if drag_point is non-null, id_reorderable is non-null
        if (self.tree.drag_point != null and self.tree.id_branch.? == (self.init_options.branch_id orelse self.data().id.asUsize()) and !self.tree.drag_ending) {
            return true;
        }

        return false;
    }

    pub fn install(self: *Branch) void {
        self.installed = true;
        var check_button_hovered: bool = false;
        if (self.tree.drag_point) |dp| {
            const topleft = dp.plus(dvui.dragOffset().plus(.{ .x = 5, .y = 5 }));
            if (self.tree.id_branch.? == (self.init_options.branch_id orelse self.data().id.asUsize())) {
                // we are being dragged - put in floating widget
                self.data().register();
                dvui.parentSet(self.widget());

                self.floating_widget = dvui.FloatingWidget.init(
                    @src(),
                    .{ .mouse_events = false },
                    .{ .rect = Rect.fromPoint(.cast(topleft.toNatural())), .min_size_content = self.tree.branch_size },
                );
                self.floating_widget.?.install();
            } else {
                self.wd = WidgetData.init(self.wd.src, .{}, wrapOuter(self.options));
                self.wd.register();
                dvui.parentSet(self.widget());

                var rs = self.wd.rectScale();

                var dragRect = Rect.Physical.fromPoint(topleft).toSize(self.tree.branch_size.scale(rs.s, Size.Physical));
                dragRect.h = 2.0;

                if (!rs.r.intersect(dragRect).empty()) {
                    // user is dragging a reorderable over this rect
                    if (!self.expanded) {
                        if (dvui.timerDone(self.data().id)) {
                            self.expanded = true;
                        } else {
                            _ = dvui.timer(self.data().id, 500_000);
                        }
                    }

                    if (!self.expanded) {
                        self.target_rs = rs;
                    } else {
                        check_button_hovered = true;
                    }

                    if (self.target_rs != null) {
                        rs.r.h = 2.0;
                        rs.r.fill(.{}, .{ .color = dvui.themeGet().focus, .fade = 1.0 });
                    }
                }
            }
        } else {
            self.wd = WidgetData.init(self.wd.src, .{}, wrapOuter(self.options));

            self.wd.register();
            dvui.parentSet(self.widget());
        }

        self.button = dvui.ButtonWidget.init(@src(), .{}, wrapInner(self.options));
        self.button.install();
        self.button.processEvents();
        self.button.drawBackground();
        self.button.drawFocus();

        // Check if the button is hovered if we are expanded, this allows us to set the target rs when
        // the entry is expanded
        if (self.button.hovered() and check_button_hovered) {
            var rs = self.data().rectScale();
            self.target_rs = rs;
            rs.r.h = 2.0;
            rs.r.fill(.{}, .{ .color = dvui.themeGet().focus, .fade = 1.0 });
        }

        self.tree.branch_size = self.button.data().rect.size();

        self.parent_focus_id = self.tree.current_branch_focus_id;
        self.tree.current_branch_focus_id = self.button.data().id;

        self.hbox.init(@src(), .{ .dir = .horizontal }, .{ .expand = .both });

        for (dvui.events()) |*e| {
            if (!self.button.matchEvent(e))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (!self.tree.init_options.enable_reordering) continue;
                    if (me.action == .motion) {
                        if (dvui.captured(self.button.data().id)) {
                            e.handle(@src(), self.button.data());
                            if (dvui.dragging(me.p, null)) |_| {
                                self.tree.dragStart(self.data().id.asUsize(), me.p);
                            }
                        }
                    }
                },
                .key => |ke| {
                    if (ke.action != .down and ke.action != .repeat)
                        continue;

                    switch (ke.code) {
                        .right => {
                            e.handle(@src(), self.button.data());
                            if (self.expanded) {
                                dvui.tabIndexNextEx(e.num, self.tree.group.tab_index_prev);
                            } else {
                                self.expanded = true;
                            }
                        },
                        .left => {
                            e.handle(@src(), self.button.data());
                            if (self.expanded) {
                                self.expanded = false;
                            } else if (self.parent_focus_id) |pid| {
                                dvui.focusWidget(pid, null, e.num);
                            } else {
                                // no parent, so focus the first branch of the tree
                                while (dvui.focusedWidgetId() != null) {
                                    dvui.tabIndexPrevEx(e.num, self.tree.group.tab_index_prev);
                                }
                                dvui.tabIndexNextEx(e.num, self.tree.group.tab_index_prev);
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }

    pub const ExpanderOptions = struct {
        indent: f32 = 10.0,
    };

    pub fn expander(self: *Branch, src: std.builtin.SourceLocation, init_opts: ExpanderOptions, opts: Options) bool {
        if (self.button.clicked()) {
            self.expanded = !self.expanded;
        }

        self.hbox.deinit();
        self.button.deinit();

        const default_opts = Options{
            .name = "Expander",
            .margin = .{ .x = init_opts.indent },
        };

        if (self.expanded) {
            self.anim = dvui.animate(
                @src(),
                .{
                    .duration = self.init_options.animation_duration,
                    .easing = self.init_options.animation_easing,
                    .kind = if (self.init_options.animation_duration > 0) .vertical else .none,
                },
                default_opts.override(opts),
            );

            // Always expand the inner box to fill the animation
            const expander_opts = dvui.Options{ .expand = .both };

            self.expander_vbox.init(src, .{ .dir = .vertical }, expander_opts.override(opts.strip()));
            self.expander_vbox.drawBackground();
        }

        self.can_expand = true;

        return self.expanded;
    }

    pub fn targetRectScale(self: *Branch) ?dvui.RectScale {
        return self.target_rs;
    }

    pub fn removed(self: *Branch) bool {
        // if drag_ending is true, id_reorderable is non-null
        if (self.tree.drag_ending and self.tree.id_branch.? == (self.init_options.branch_id orelse self.data().id.asUsize())) {
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

    pub fn widget(self: *Branch) Widget {
        return Widget.init(self, Branch.data, Branch.rectFor, Branch.screenRectScale, Branch.minSizeForChild);
    }

    pub fn data(self: *Branch) *WidgetData {
        return self.wd.validate();
    }

    pub fn rectFor(self: *Branch, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return self.layout.rectFor(self.data().contentRect().justSize(), id, min_size, e, g);
    }

    pub fn screenRectScale(self: *Branch, rect: Rect) RectScale {
        return self.data().contentRectScale().rectToRectScale(rect);
    }

    pub fn minSizeForChild(self: *Branch, s: Size) void {
        const ms = self.layout.minSizeForChild(s);
        self.data().minSizeMax(self.data().options.padSize(ms));
    }

    pub fn deinit(self: *Branch) void {
        const should_free = self.data().was_allocated_on_widget_stack;
        defer if (should_free) dvui.widgetFree(self);
        defer self.* = undefined;

        if (self.can_expand) {
            if (self.expanded) {
                self.expander_vbox.deinit();
                if (self.anim) |a| {
                    a.deinit();
                }
            }

            dvui.dataSet(null, self.data().id, "_expanded", self.expanded);
        } else {
            self.hbox.deinit();
            self.button.deinit();
        }

        if (self.floating_widget) |*fw| {
            self.data().minSizeMax(fw.data().min_size);
            fw.deinit();
        }

        self.data().minSizeSetAndRefresh();
        self.data().minSizeReportToParent();

        self.tree.current_branch_focus_id = self.parent_focus_id;
        dvui.parentReset(self.data().id, self.data().parent);
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
