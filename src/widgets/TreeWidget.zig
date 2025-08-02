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
init_options: InitOptions = undefined,

pub const InitOptions = struct {
    enable_reordering: bool = true,
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TreeWidget {
    var self = TreeWidget{};
    const defaults = Options{ .name = "Tree" };
    self.init_options = init_opts;
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

pub fn tree(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) *TreeWidget {
    var ret = dvui.widgetAlloc(TreeWidget);
    ret.* = TreeWidget.init(src, init_opts, opts);
    ret.install();
    ret.processEvents();
    return ret;
}

pub fn widget(self: *TreeWidget) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
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

        self.processEvent(e);
    }
}

pub fn processEvent(self: *TreeWidget, e: *dvui.Event) void {
    if (dvui.captured(self.wd.id)) {
        switch (e.evt) {
            .mouse => |me| {
                if ((me.action == .press or me.action == .release) and me.button.pointer()) {
                    self.drag_ending = true;
                    dvui.captureMouse(null, e.num);
                    dvui.dragEnd();
                    dvui.refresh(null, @src(), self.wd.id);
                } else if (me.action == .motion) {
                    self.drag_point = me.p;

                    dvui.scrollDrag(.{
                        .mouse_pt = me.p,
                        .screen_rect = self.wd.rectScale().r,
                        .capture_id = self.wd.id,
                    });
                }
            },
            else => {},
        }
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
    dvui.captureMouse(self.data(), 0);
}

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

        // if null, uses widget id
        // if non-null, must be unique among reorderables in a single reorder
        branch_id: ?usize = null,
    };

    wd: WidgetData = undefined,
    button: dvui.ButtonWidget = undefined,
    hbox: dvui.BoxWidget = undefined,
    vbox: dvui.BoxWidget = undefined,
    expander_vbox: dvui.BoxWidget = undefined,
    tree: *TreeWidget = undefined,
    init_options: Branch.InitOptions = undefined,
    options: Options = undefined,
    installed: bool = false,
    floating_widget: ?dvui.FloatingWidget = null,
    target_rs: ?dvui.RectScale = null,
    expanded: bool = false,
    can_expand: bool = false,

    pub fn init(src: std.builtin.SourceLocation, reorder: *TreeWidget, init_opts: Branch.InitOptions, opts: Options) Branch {
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
        if (self.tree.drag_point != null and self.tree.id_branch.? == (self.init_options.branch_id orelse self.wd.id.asUsize()) and !self.tree.drag_ending) {
            return true;
        }

        return false;
    }

    pub fn install(self: *Branch) void {
        self.installed = true;
        var check_button_hovered: bool = false;
        if (self.tree.drag_point) |dp| {
            const topleft = dp.plus(dvui.dragOffset().plus(.{ .x = 5, .y = 5 }));
            if (self.tree.id_branch.? == (self.init_options.branch_id orelse self.wd.id.asUsize())) {
                // we are being dragged - put in floating widget
                self.wd.register();
                dvui.parentSet(self.widget());

                self.floating_widget = dvui.FloatingWidget.init(
                    @src(),
                    .{ .rect = Rect.fromPoint(.cast(topleft.toNatural())), .min_size_content = self.tree.branch_size },
                );
                self.floating_widget.?.install();
            } else {
                self.wd = WidgetData.init(self.wd.src, .{}, self.options);
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
            self.wd = WidgetData.init(self.wd.src, .{}, self.options);

            self.wd.register();
            dvui.parentSet(self.widget());
        }

        const no_padding = Options{
            .name = "Padding",
            .padding = dvui.Rect.all(0),
            .margin = dvui.Rect.all(0),
        };

        self.vbox = dvui.BoxWidget.init(@src(), .{ .dir = .vertical }, no_padding.override(self.options));
        self.vbox.install();
        self.vbox.drawBackground();

        self.button = dvui.ButtonWidget.init(@src(), .{}, no_padding.override(self.options));
        self.button.install();
        self.button.processEvents();
        self.button.drawBackground();

        // Check if the button is hovered if we are expanded, this allows us to set the target rs when
        // the entry is expanded
        if (self.button.hovered() and check_button_hovered) {
            var rs = self.wd.rectScale();
            self.target_rs = rs;
            rs.r.h = 2.0;
            rs.r.fill(.{}, .{ .color = dvui.themeGet().focus, .fade = 1.0 });
        }

        self.tree.branch_size = self.button.wd.rect.size();

        self.hbox = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal }, no_padding.override(self.options));
        self.hbox.install();
        self.hbox.drawBackground();

        if (self.tree.init_options.enable_reordering) {
            loop: for (dvui.events()) |*e| {
                if (!self.button.matchEvent(e))
                    continue;

                switch (e.evt) {
                    .mouse => |me| {
                        if (me.action == .press and me.button.pointer()) {
                            e.handle(@src(), self.button.data());
                            dvui.captureMouse(self.button.data(), e.num);
                            const top_left = self.button.wd.rectScale().r.topLeft();
                            dvui.dragPreStart(me.p, .{ .offset = top_left });
                        } else if (me.action == .motion) {
                            if (dvui.captured(self.button.wd.id)) {
                                e.handle(@src(), self.button.data());
                                if (dvui.dragging(me.p, null)) |_| {
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
        indent: f32 = 10.0,
    };

    pub fn expander(self: *Branch, src: std.builtin.SourceLocation, init_opts: ExpanderOptions, opts: Options) bool {
        if (self.button.clicked()) {
            self.expanded = !self.expanded;
        }

        self.hbox.deinit();
        self.button.deinit();

        const defaults = Options{
            .name = "Expander",
            .margin = .{ .x = init_opts.indent },
        };

        if (self.expanded) {
            self.expander_vbox = dvui.BoxWidget.init(src, .{ .dir = .vertical }, defaults.override(opts));
            self.expander_vbox.install();
            self.expander_vbox.drawBackground();

            // Since our items are padded, we need to add some extra space to the top
            _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = self.options.paddingGet().y * 2.0 } });
        }

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

    pub fn widget(self: *Branch) Widget {
        return Widget.init(self, Branch.data, Branch.rectFor, Branch.screenRectScale, Branch.minSizeForChild);
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

    pub fn deinit(self: *Branch) void {
        if (self.can_expand) {
            if (self.expanded)
                self.expander_vbox.deinit();

            dvui.dataSet(null, self.wd.id, "_expanded", self.expanded);
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

test {
    @import("std").testing.refAllDecls(@This());
}
