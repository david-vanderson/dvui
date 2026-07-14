//! Docking widget: walks a `Layout.DockLayout` tree, opening a `PanedWidget`
//! per split and a tabbed header + content box per leaf. Floating leaves are
//! drawn afterwards in their own `FloatingWindowWidget`s.
//!
//! Usage:
//! ```
//! var dock = dvui.dockspace(@src(), .{ .layout = &layout, .panelInfo = myPanelInfo }, .{ .expand = .both });
//! defer dock.deinit(); // applies queued mutations, sets dock.changed
//! while (dock.panel()) |p| {
//!     defer p.end();
//!     app.drawPanel(p.id);
//! }
//! ```
//!
//! The layout tree is treated as immutable for the duration of the walk:
//! tab clicks, closes, and (later) drag-and-drop only queue `Layout.Mutation`
//! entries, applied by `deinit` once the last pane has closed. This keeps
//! node indices (and thus `split_ratio` pointers) valid for the whole frame.
const std = @import("std");
const dvui = @import("../dvui.zig");

const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;

pub const Layout = @import("DockingWidget/Layout.zig");

const Dockspace = @This();

/// App-supplied display info for a panel slug, used to draw its tab.
pub const PanelInfo = struct {
    title: []const u8,
    icon: ?[]const u8 = null,
    closable: bool = true,
};

pub const CloseButtonVisibility = enum {
    /// Every closable tab always shows its close button.
    always,
    /// Only the active tab and the currently-hovered tab show a close button.
    hover,
};

pub const InitOptions = struct {
    layout: *Layout.DockLayout,
    panelInfo: *const fn (Layout.PanelId) PanelInfo,
    close_button_visibility: CloseButtonVisibility = .always,
    /// Draws into the trailing header space after a leaf's tab strip, given
    /// the leaf's active `panel`. The area expands to fill the rest of the
    /// header row and is entirely the app's — dvui draws nothing there. Null
    /// (default) leaves just the tab strip.
    drawHeaderExtra: ?*const fn (Layout.PanelId) void = null,
    /// Called every frame a tab's right-click context menu is open (each tab
    /// is wrapped in its own `dvui.context()`). `pt` anchors a `floatingMenu`;
    /// call `.close()` on it when a menu item is picked.
    onTabContextMenu: ?*const fn (panel: Layout.PanelId, pt: dvui.Point.Natural) void = null,
    /// Options for a box wrapping each docked leaf's whole area — tab strip and
    /// content together — so an app can theme the background/border around the
    /// header too, which wrapping `panel()`'s content alone can't reach. Null
    /// (default) opens no such box.
    panel_background: ?Options = null,
};

wd: WidgetData,
init_opts: InitOptions,

/// Mutations queued by tab clicks/closes/drags this frame; applied to
/// `init_opts.layout` in `deinit`.
mutations: std.ArrayList(Layout.Mutation) = .empty,
/// True after `deinit` if any mutation was applied (caller should persist).
changed: bool = false,

stack: std.ArrayList(StackFrame) = .empty,
started: bool = false,
float_index: usize = 0,
current_float: ?*dvui.FloatingWindowWidget = null,
content_box: ?*dvui.BoxWidget = null,
/// The `panel_background` box wrapping the current leaf's header + content,
/// when that option is set. Opened in `openLeaf`, closed last in
/// `closeContent` (outermost box).
panel_wrapper: ?*dvui.BoxWidget = null,

/// Drop target under the mouse during a "dvui_dock" drag, found while walking
/// leaves. Root-edge zones are a fallback checked in `deinit` only if no leaf
/// claimed the point (innermost zones win).
hover_target: ?DropTarget = null,
hover_rect: Rect.Physical = .{},

/// A drag-release seen mid-walk, resolved against `hover_target` in `deinit`
/// once every leaf (and thus every zone) has been visited this frame.
pending_drop: ?struct { slug: Layout.PanelId, point: dvui.Point.Physical } = null,

const StackFrame = struct {
    node: Layout.NodeIndex,
    paned: *dvui.PanedWidget,
    visited_first: bool = false,
    visited_second: bool = false,
};

const DropTarget = union(enum) {
    tab: struct { leaf: Layout.NodeIndex, index: usize },
    split: struct { leaf: Layout.NodeIndex, side: Layout.Side },
    split_root: Layout.Side,

    fn toMoveTarget(self: DropTarget) Layout.MoveTarget {
        return switch (self) {
            .tab => |t| .{ .tab = .{ .leaf = t.leaf, .index = t.index } },
            .split => |s| .{ .split = .{ .leaf = s.leaf, .side = s.side } },
            .split_root => |side| .{ .split_root = side },
        };
    }
};

/// Yielded by `panel()`; caller draws content then calls `end()` (typically via `defer`).
pub const Panel = struct {
    id: Layout.PanelId,
    leaf: Layout.NodeIndex,
    dockspace: *Dockspace,

    pub fn end(self: Panel) void {
        self.dockspace.closeContent();
    }
};

/// It's expected to call this when `self` is `undefined`
pub fn init(self: *Dockspace, src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) void {
    const defaults = Options{ .name = "Dockspace" };
    self.* = .{ .wd = WidgetData.init(src, .{}, defaults.override(opts)), .init_opts = init_opts };
    dvui.parentSet(self.widget());
    self.data().register();
}

pub fn widget(self: *Dockspace) Widget {
    return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild);
}

pub fn data(self: *Dockspace) *WidgetData {
    return self.wd.validate();
}

pub fn rectFor(self: *Dockspace, id: dvui.Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    _ = id;
    return dvui.placeIn(self.data().contentRect().justSize(), min_size, e, g);
}

pub fn screenRectScale(self: *Dockspace, rect: Rect) RectScale {
    return self.data().contentRectScale().rectToRectScale(rect);
}

pub fn minSizeForChild(self: *Dockspace, s: Size) void {
    self.data().minSizeMax(self.data().options.padSize(s));
}

/// Position-independent id for a panel's widgets (tab, close button, content
/// box), so their state (scroll, etc.) survives the panel being dragged
/// elsewhere.
fn slugIdExtra(slug: Layout.PanelId) usize {
    return @truncate(std.hash.Wyhash.hash(0, slug));
}

/// Queues `m` for `deinit` to apply, and sets `self.changed` now so callers can
/// read it right after the `while (dock.panel())` loop, before `deinit` runs.
fn queueMutation(self: *Dockspace, m: Layout.Mutation) void {
    self.mutations.append(dvui.currentWindow().arena(), m) catch return;
    self.changed = true;
}

/// Advances the walk by one leaf, returning its active panel, or null once
/// the whole tree (and all floats) have been walked.
pub fn panel(self: *Dockspace) ?Panel {
    const layout = self.init_opts.layout;
    while (true) {
        if (self.stack.items.len == 0) {
            if (!self.started) {
                self.started = true;
                if (self.enterNode(layout.root)) |p| return p;
                continue;
            }
            return self.nextFloat();
        }

        const frame = &self.stack.items[self.stack.items.len - 1];
        if (!frame.visited_first) {
            frame.visited_first = true;
            if (frame.paned.showFirst()) {
                const child = layout.nodes.items[frame.node].split.first;
                if (self.enterNode(child)) |p| return p;
            }
            continue;
        }
        if (!frame.visited_second) {
            frame.visited_second = true;
            if (frame.paned.showSecond()) {
                const child = layout.nodes.items[frame.node].split.second;
                if (self.enterNode(child)) |p| return p;
            }
            continue;
        }

        frame.paned.deinit();
        _ = self.stack.pop();
    }
}

/// Enters `node`: for a split, opens a `PanedWidget` and pushes a stack frame
/// (returns null so the caller loop continues); for a leaf, draws the header
/// and opens the content box, returning the yielded `Panel`.
fn enterNode(self: *Dockspace, node: Layout.NodeIndex) ?Panel {
    const layout = self.init_opts.layout;
    switch (layout.nodes.items[node]) {
        .split => |sp| {
            const p = dvui.paned(@src(), .{
                .direction = sp.dir,
                .collapsed_size = 0,
                .split_ratio = &layout.nodes.items[node].split.ratio,
                .handle_margin = 4,
            }, .{ .expand = .both, .id_extra = node });
            self.stack.append(dvui.currentWindow().arena(), .{ .node = node, .paned = p }) catch {};
            return null;
        },
        .leaf => return self.openLeaf(node),
        .free => unreachable,
    }
}

fn openLeaf(self: *Dockspace, node: Layout.NodeIndex) ?Panel {
    const layout = self.init_opts.layout;
    const leaf = layout.nodes.items[node].leaf;
    if (leaf.tabs.items.len == 0) return null; // tolerated empty root leaf

    if (self.init_opts.panel_background) |bg_opts| {
        const defaults = Options{ .name = "Dockspace.panel_background", .expand = .both };
        self.panel_wrapper = dvui.box(@src(), .{}, defaults.override(bg_opts).override(.{ .id_extra = node }));
    }

    const header_rect = self.drawHeader(node, leaf);

    const active_slug = leaf.tabs.items[leaf.active];
    const box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .id_extra = slugIdExtra(active_slug) });
    self.content_box = box;

    if (dvui.dragName("dvui_dock")) {
        self.checkHeaderZone(node, header_rect);
        self.checkLeafZones(node, box.data().contentRectScale().r);
    }

    return .{ .id = active_slug, .leaf = node, .dockspace = self };
}

/// The header (tab strip + trailing space) is always an "insert as tab" target:
/// a drop there adds the dragged tab as a sibling, never a split (unlike
/// `checkLeafZones`' N/S/E/W content zones).
fn checkHeaderZone(self: *Dockspace, node: Layout.NodeIndex, r: Rect.Physical) void {
    const mouse = dvui.currentWindow().mouse_pt;
    if (!r.contains(mouse)) return;
    const leaf = self.init_opts.layout.nodes.items[node].leaf;
    self.hover_target = .{ .tab = .{ .leaf = node, .index = leaf.tabs.items.len } };
    self.hover_rect = r;
}

/// Drop-zone geometry for one leaf's content rect `r` (physical): a center
/// zone (append as a new tab) inset 30% each side from `r`, and N/S/E/W edge
/// strips (split that side) filling the rest, clamped to 40 logical px thick.
fn checkLeafZones(self: *Dockspace, node: Layout.NodeIndex, r: Rect.Physical) void {
    const mouse = dvui.currentWindow().mouse_pt;
    if (!r.contains(mouse)) return;

    const max_edge = 40.0 * dvui.windowNaturalScale();
    const inset_x = @min(r.w * 0.3, max_edge);
    const inset_y = @min(r.h * 0.3, max_edge);

    const center: Rect.Physical = .{ .x = r.x + inset_x, .y = r.y + inset_y, .w = @max(0, r.w - 2 * inset_x), .h = @max(0, r.h - 2 * inset_y) };
    if (center.contains(mouse)) {
        const leaf = self.init_opts.layout.nodes.items[node].leaf;
        self.hover_target = .{ .tab = .{ .leaf = node, .index = leaf.tabs.items.len } };
        self.hover_rect = center;
        return;
    }

    const left: Rect.Physical = .{ .x = r.x, .y = r.y, .w = inset_x, .h = r.h };
    if (left.contains(mouse)) {
        self.hover_target = .{ .split = .{ .leaf = node, .side = .left } };
        self.hover_rect = left;
        return;
    }
    const right: Rect.Physical = .{ .x = r.x + r.w - inset_x, .y = r.y, .w = inset_x, .h = r.h };
    if (right.contains(mouse)) {
        self.hover_target = .{ .split = .{ .leaf = node, .side = .right } };
        self.hover_rect = right;
        return;
    }
    const top: Rect.Physical = .{ .x = r.x, .y = r.y, .w = r.w, .h = inset_y };
    if (top.contains(mouse)) {
        self.hover_target = .{ .split = .{ .leaf = node, .side = .top } };
        self.hover_rect = top;
        return;
    }
    const bottom: Rect.Physical = .{ .x = r.x, .y = r.y + r.h - inset_y, .w = r.w, .h = inset_y };
    if (bottom.contains(mouse)) {
        self.hover_target = .{ .split = .{ .leaf = node, .side = .bottom } };
        self.hover_rect = bottom;
    }
}

/// Root-edge drop zones (24 logical px), checked only if no leaf already
/// claimed the mouse point: innermost (leaf) zones win over root zones.
fn checkRootZones(self: *Dockspace) void {
    if (self.hover_target != null) return;
    if (!dvui.dragName("dvui_dock")) return;

    const r = self.data().contentRectScale().r;
    const mouse = dvui.currentWindow().mouse_pt;
    if (!r.contains(mouse)) return;
    const thick = 24.0 * dvui.windowNaturalScale();

    const left: Rect.Physical = .{ .x = r.x, .y = r.y, .w = thick, .h = r.h };
    if (left.contains(mouse)) {
        self.hover_target = .{ .split_root = .left };
        self.hover_rect = left;
        return;
    }
    const right: Rect.Physical = .{ .x = r.x + r.w - thick, .y = r.y, .w = thick, .h = r.h };
    if (right.contains(mouse)) {
        self.hover_target = .{ .split_root = .right };
        self.hover_rect = right;
        return;
    }
    const top: Rect.Physical = .{ .x = r.x, .y = r.y, .w = r.w, .h = thick };
    if (top.contains(mouse)) {
        self.hover_target = .{ .split_root = .top };
        self.hover_rect = top;
        return;
    }
    const bottom: Rect.Physical = .{ .x = r.x, .y = r.y + r.h - thick, .w = r.w, .h = thick };
    if (bottom.contains(mouse)) {
        self.hover_target = .{ .split_root = .bottom };
        self.hover_rect = bottom;
    }
}

/// Resolves a completed drop: moves `slug` to the currently hovered zone, or
/// (per spec) floats it at the release point if it was dropped outside any zone.
fn resolveDrop(self: *Dockspace, slug: Layout.PanelId, release_point: dvui.Point.Physical) void {
    if (self.hover_target) |target| {
        self.queueMutation(.{ .move = .{ .panel = slug, .target = target.toMoveTarget() } });
    } else {
        const p = release_point.toNatural();
        const size: Size = .{ .w = 300, .h = 200 };
        self.queueMutation(.{ .float = .{ .panel = slug, .rect = .{ .x = p.x - size.w / 2, .y = p.y - size.h / 2, .w = size.w, .h = size.h } } });
    }
}

fn closeContent(self: *Dockspace) void {
    if (self.content_box) |b| {
        b.deinit();
        self.content_box = null;
    }
    if (self.current_float) |f| {
        f.deinit();
        self.current_float = null;
    }
    // Closed last (outermost): wraps this leaf's header + content. Only set for
    // docked leaves, never floats.
    if (self.panel_wrapper) |w| {
        w.deinit();
        self.panel_wrapper = null;
    }
}

/// Draws the tab strip (plus `drawHeaderExtra`'s trailing content, if set) and
/// returns the header row's rect (used by `checkHeaderZone`).
fn drawHeader(self: *Dockspace, node: Layout.NodeIndex, leaf: Layout.Node.Leaf) Rect.Physical {
    var header_row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = node });
    defer header_row.deinit();

    {
        // When `drawHeaderExtra` is set, its box (below) claims the leftover
        // width instead, so drops and right-clicks on the empty space reach the
        // app rather than an oversized tab strip.
        const tw_expand: Options.Expand = if (self.init_opts.drawHeaderExtra != null) .none else .horizontal;
        var tw = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = tw_expand, .id_extra = node });
        defer tw.deinit();

        for (leaf.tabs.items, 0..) |slug, i| {
            const info = self.init_opts.panelInfo(slug);
            var tab = tw.addTab(i == leaf.active, .{ .process_events = false }, .{ .id_extra = slugIdExtra(slug), .tag = slug });
            defer tab.deinit();

            {
                var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });
                defer row.deinit();
                if (info.icon) |ic| dvui.icon(@src(), "docktab_icon", ic, .{}, .{ .gravity_y = 0.5 });
                dvui.label(@src(), "{s}", .{info.title}, .{ .gravity_y = 0.5 });
                const show_close = info.closable and switch (self.init_opts.close_button_visibility) {
                    .always => true,
                    .hover => i == leaf.active or tab.hovered(),
                };
                if (show_close) {
                    const close_tag = std.fmt.allocPrint(dvui.currentWindow().arena(), "docktab_close:{s}", .{slug}) catch null;
                    // Processed before the tab's own click handling below, so a
                    // close click isn't also read as a tab-select.
                    if (dvui.buttonIcon(@src(), "docktab_close", dvui.entypo.cross, .{}, .{}, .{
                        .id_extra = slugIdExtra(slug),
                        .tag = close_tag,
                        .gravity_y = 0.5,
                        .padding = Rect.all(2),
                        .margin = Rect.all(2),
                    })) {
                        self.queueMutation(.{ .remove = slug });
                    }
                }
            }

            self.processTabEvents(tab.data(), node, i, slug);
        }
    }

    if (self.init_opts.onTabContextMenu) |cb| {
        for (leaf.tabs.items) |slug| {
            // Each tab was tagged with its slug above; read that rect back.
            const td = dvui.tagGet(slug) orelse continue;
            var cxt = dvui.context(@src(), .{ .rect = td.rect }, .{ .id_extra = slugIdExtra(slug) });
            defer cxt.deinit();
            if (cxt.activePoint()) |cp| cb(slug, cp);
        }
    }

    if (self.init_opts.drawHeaderExtra) |drawFn| {
        // Claims the leftover width so the callback owns the whole trailing
        // area (e.g. to catch a right-click on empty space), not just what it
        // visibly draws.
        var extra = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .gravity_y = 0.5 });
        defer extra.deinit();
        drawFn(leaf.tabs.items[leaf.active]);
    }

    return header_row.data().contentRectScale().r;
}

/// Raw press/motion/release handling for one tab button: a press+release with no
/// significant motion selects the tab; crossing the drag threshold starts a named
/// "dvui_dock" drag instead, resolved against `hover_target` on release. Bypasses
/// `ButtonWidget`'s click detection, which has no notion of a drag.
fn processTabEvents(self: *Dockspace, wd: *WidgetData, node: Layout.NodeIndex, index: usize, slug: Layout.PanelId) void {
    for (dvui.events()) |*e| {
        if (!dvui.eventMatchSimple(e, wd)) continue;
        const me = switch (e.evt) {
            .mouse => |me| me,
            else => continue,
        };
        switch (me.action) {
            .press => if (me.button.pointer()) {
                e.handle(@src(), wd);
                dvui.captureMouse(wd, e.num);
                dvui.dragPreStart(me.button, me.p, .{ .name = "dvui_dock", .cursor = .arrow_all });
            },
            .motion => if (dvui.captured(wd.id)) {
                e.handle(@src(), wd);
                _ = dvui.dragging(me.p, "dvui_dock");
            },
            .release => if (me.button.pointer() and dvui.captured(wd.id)) {
                e.handle(@src(), wd);
                dvui.captureMouse(null, e.num);
                if (dvui.dragName("dvui_dock")) {
                    // Don't `dragEnd()` yet: leaves later in this walk still need
                    // the drag active to compute their own drop zones.
                    self.pending_drop = .{ .slug = slug, .point = me.p };
                } else {
                    dvui.dragEnd();
                    self.queueMutation(.{ .set_active = .{ .leaf = node, .index = index } });
                }
            },
            else => {},
        }
    }
}

fn nextFloat(self: *Dockspace) ?Panel {
    const layout = self.init_opts.layout;
    while (self.float_index < layout.floats.items.len) {
        const idx = self.float_index;
        self.float_index += 1;

        const fwin = dvui.floatingWindow(@src(), .{
            .rect = &layout.floats.items[idx].rect,
        }, .{ .id_extra = layout.floats.items[idx].leaf });
        self.current_float = fwin;

        if (self.openLeaf(layout.floats.items[idx].leaf)) |p| return p;

        // Empty float leaf (shouldn't normally happen): close and try the next one.
        fwin.deinit();
        self.current_float = null;
    }
    return null;
}

pub fn deinit(self: *Dockspace) void {
    defer if (dvui.widgetIsAllocated(self)) dvui.widgetFree(self);
    defer self.* = undefined;

    self.checkRootZones();
    if (self.hover_target != null) {
        // Drawn last (on top of everything else this widget drew this frame).
        self.hover_rect.fill(dvui.CornerRect.Physical.all(0), .{ .color = dvui.themeGet().focus.opacity(0.25) });
    }

    if (self.pending_drop) |pd| {
        self.resolveDrop(pd.slug, pd.point);
        dvui.dragEnd();
    }

    for (self.mutations.items) |m| self.init_opts.layout.apply(m) catch {};

    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
    dvui.parentReset(self.data().id, self.data().parent);
}

fn testPanelInfo(id: Layout.PanelId) PanelInfo {
    return .{ .title = id, .closable = true };
}

test "dockspace renders nested splits, floats, and applies tab mutations" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fns = struct {
        var layout: Layout.DockLayout = undefined;
        var inited = false;
        var last_changed = false;

        fn frame() !dvui.App.Result {
            if (!inited) {
                layout = try Layout.DockLayout.initSingleLeaf(std.testing.allocator, "a");
                try layout.splitLeaf(layout.root, .right, "b");
                try layout.insertTab(layout.findPanel("b").?, 1, "c");
                // Kept away from the header row (y ~0-30) of either dock leaf,
                // so it doesn't sit on top of and steal clicks meant for them.
                try layout.floatPanel("c", .{ .x = 150, .y = 300, .w = 150, .h = 80 });
                inited = true;
            }

            var dock = dvui.dockspace(@src(), .{ .layout = &layout, .panelInfo = testPanelInfo }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "content:{s}", .{p.id}, .{});
            }
            if (dock.changed) last_changed = true;

            return .ok;
        }
    };
    defer fns.layout.deinit();

    try dvui.testing.settle(fns.frame);
    try std.testing.expect(fns.layout.contains("a"));
    try std.testing.expect(fns.layout.contains("b"));
    try std.testing.expect(fns.layout.contains("c"));
    try std.testing.expect(fns.layout.isFloat(fns.layout.findPanel("c").?));

    // Clicking tab "b" activates it (set_active mutation applied on deinit).
    fns.last_changed = false;
    try dvui.testing.moveTo("b");
    try dvui.testing.click(.left);
    try dvui.testing.settle(fns.frame);
    try std.testing.expect(fns.last_changed);
    const b_leaf = fns.layout.findPanel("b").?;
    try std.testing.expectEqualStrings("b", fns.layout.nodes.items[b_leaf].leaf.tabs.items[fns.layout.nodes.items[b_leaf].leaf.active]);

    // Closing tab "a" removes it from the layout (remove mutation applied on deinit).
    fns.last_changed = false;
    try dvui.testing.moveTo("docktab_close:a");
    try dvui.testing.click(.left);
    try dvui.testing.settle(fns.frame);
    try std.testing.expect(fns.last_changed);
    try std.testing.expect(!fns.layout.contains("a"));
}

test "dockspace drawHeaderExtra: called once per leaf for the active tab, app owns the content" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fns = struct {
        var layout: Layout.DockLayout = undefined;
        var inited = false;
        var drawn_for: std.ArrayList(Layout.PanelId) = .empty;

        fn drawHeaderExtra(id: Layout.PanelId) void {
            drawn_for.append(std.testing.allocator, id) catch {};
            // The app can put whatever it wants here — a button, an icon,
            // several of each — dvui neither knows nor cares. `id_extra`
            // disambiguates the two leaves' otherwise-identical buttons,
            // same as any other app code drawing per-panel widgets.
            _ = dvui.button(@src(), "extra", .{}, .{ .id_extra = slugIdExtra(id) });
        }

        fn frame() !dvui.App.Result {
            if (!inited) {
                layout = try Layout.DockLayout.initSingleLeaf(std.testing.allocator, "a");
                try layout.splitLeaf(layout.root, .right, "b");
                inited = true;
            }

            var dock = dvui.dockspace(@src(), .{
                .layout = &layout,
                .panelInfo = testPanelInfo,
                .drawHeaderExtra = drawHeaderExtra,
            }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "content:{s}", .{p.id}, .{});
            }

            return .ok;
        }
    };
    defer fns.layout.deinit();
    defer fns.drawn_for.deinit(std.testing.allocator);

    try dvui.testing.settle(fns.frame);

    // `settle` may run `frame` more than once, so don't assume an exact
    // call count — just that both leaves' active tabs got a call.
    try std.testing.expect(fns.drawn_for.items.len >= 2);
    var saw_a = false;
    var saw_b = false;
    for (fns.drawn_for.items) |id| {
        if (std.mem.eql(u8, id, "a")) saw_a = true;
        if (std.mem.eql(u8, id, "b")) saw_b = true;
    }
    try std.testing.expect(saw_a);
    try std.testing.expect(saw_b);
}

test "dockspace onTabContextMenu: fires while a tab's context menu is open, closes on pick" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fns = struct {
        var layout: Layout.DockLayout = undefined;
        var inited = false;
        var call_count: usize = 0;
        var last_id: ?Layout.PanelId = null;

        fn onTabContextMenu(id: Layout.PanelId, pt: dvui.Point.Natural) void {
            call_count += 1;
            last_id = id;

            var fw = dvui.floatingMenu(@src(), .{ .from = dvui.Rect.Natural.fromPoint(pt) }, .{});
            defer fw.deinit();
            if (dvui.menuItemLabel(@src(), "Add Something", .{}, .{ .tag = "ctx_add" }) != null) {
                fw.close();
            }
        }

        fn frame() !dvui.App.Result {
            if (!inited) {
                layout = try Layout.DockLayout.initSingleLeaf(std.testing.allocator, "a");
                try layout.insertTab(layout.root, 1, "b");
                inited = true;
            }

            var dock = dvui.dockspace(@src(), .{
                .layout = &layout,
                .panelInfo = testPanelInfo,
                .onTabContextMenu = onTabContextMenu,
            }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "content:{s}", .{p.id}, .{});
            }

            return .ok;
        }
    };
    defer fns.layout.deinit();

    try dvui.testing.settle(fns.frame);
    try std.testing.expectEqual(@as(usize, 0), fns.call_count);

    try dvui.testing.moveTo("a");
    try dvui.testing.click(.right);
    try dvui.testing.settle(fns.frame);

    try std.testing.expect(fns.call_count > 0);
    try std.testing.expectEqualStrings("a", fns.last_id.?);

    // Picking the item closes the context menu: further frames stop calling back.
    try dvui.testing.moveTo("ctx_add");
    try dvui.testing.click(.left);
    try dvui.testing.settle(fns.frame);

    const count_after_pick = fns.call_count;
    try dvui.testing.settle(fns.frame);
    try std.testing.expectEqual(count_after_pick, fns.call_count);
}

test "dockspace drag: dropping directly onto another leaf's tab (not just its content) adds a tab there" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fns = struct {
        var layout: Layout.DockLayout = undefined;
        var inited = false;

        fn frame() !dvui.App.Result {
            if (!inited) {
                layout = try Layout.DockLayout.initSingleLeaf(std.testing.allocator, "a");
                try layout.splitLeaf(layout.root, .right, "b");
                inited = true;
            }

            var dock = dvui.dockspace(@src(), .{ .layout = &layout, .panelInfo = testPanelInfo }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "content:{s}", .{p.id}, .{});
            }

            return .ok;
        }
    };
    defer fns.layout.deinit();

    try dvui.testing.settle(fns.frame);

    const cw = dvui.currentWindow();
    const a_center = dvui.tagGet("a").?.rect.center();
    // "b"'s own tab button (in the header, not its content area below).
    const b_tab = dvui.tagGet("b").?.rect.center();

    _ = try cw.addEventMouseMotion(.{ .pt = a_center });
    _ = try cw.addEventMouseButton(.left, .press);
    _ = try dvui.testing.step(fns.frame);

    _ = try cw.addEventMouseMotion(.{ .pt = b_tab });
    _ = try dvui.testing.step(fns.frame);

    _ = try cw.addEventMouseButton(.left, .release);
    try dvui.testing.settle(fns.frame);

    const b_leaf = fns.layout.findPanel("b").?;
    try std.testing.expect(!fns.layout.isFloat(b_leaf));
    try std.testing.expectEqual(@as(usize, 2), fns.layout.nodes.items[b_leaf].leaf.tabs.items.len);
    try std.testing.expectEqual(fns.layout.root, b_leaf);
}

test "dockspace drag: press+motion+release onto another leaf's center adds a new tab there" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fns = struct {
        var layout: Layout.DockLayout = undefined;
        var inited = false;

        fn frame() !dvui.App.Result {
            if (!inited) {
                layout = try Layout.DockLayout.initSingleLeaf(std.testing.allocator, "a");
                try layout.splitLeaf(layout.root, .right, "b");
                inited = true;
            }

            var dock = dvui.dockspace(@src(), .{ .layout = &layout, .panelInfo = testPanelInfo }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "content:{s}", .{p.id}, .{});
            }

            return .ok;
        }
    };
    defer fns.layout.deinit();

    try dvui.testing.settle(fns.frame);

    const cw = dvui.currentWindow();
    const a_center = dvui.tagGet("a").?.rect.center();
    // Window is 600x400 logical, "b" is the right half; scale to physical
    // so this lands well inside "b"'s content center zone regardless of dpi.
    const scale = dvui.windowNaturalScale();
    const b_target: dvui.Point.Physical = .{ .x = 450 * scale, .y = 200 * scale };

    _ = try cw.addEventMouseMotion(.{ .pt = a_center });
    _ = try cw.addEventMouseButton(.left, .press);
    _ = try dvui.testing.step(fns.frame);

    _ = try cw.addEventMouseMotion(.{ .pt = b_target });
    _ = try dvui.testing.step(fns.frame);

    _ = try cw.addEventMouseButton(.left, .release);
    try dvui.testing.settle(fns.frame);

    try std.testing.expect(fns.layout.contains("a"));
    try std.testing.expect(fns.layout.contains("b"));
    const b_leaf = fns.layout.findPanel("b").?;
    try std.testing.expect(!fns.layout.isFloat(b_leaf));
    try std.testing.expectEqual(Layout.Node.leaf, std.meta.activeTag(fns.layout.nodes.items[b_leaf]));
    try std.testing.expectEqual(@as(usize, 2), fns.layout.nodes.items[b_leaf].leaf.tabs.items.len);
    // "a"'s original leaf (empty) collapsed away: the whole tree is one leaf now.
    try std.testing.expectEqual(fns.layout.root, b_leaf);
}

test "dockspace drag: release outside any zone floats the panel at the drop point" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fns = struct {
        var layout: Layout.DockLayout = undefined;
        var inited = false;

        fn frame() !dvui.App.Result {
            if (!inited) {
                layout = try Layout.DockLayout.initSingleLeaf(std.testing.allocator, "a");
                try layout.insertTab(layout.root, 1, "b");
                inited = true;
            }

            var dock = dvui.dockspace(@src(), .{ .layout = &layout, .panelInfo = testPanelInfo }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "content:{s}", .{p.id}, .{});
            }

            return .ok;
        }
    };
    defer fns.layout.deinit();

    try dvui.testing.settle(fns.frame);

    const cw = dvui.currentWindow();
    const a_center = dvui.tagGet("a").?.rect.center();

    _ = try cw.addEventMouseMotion(.{ .pt = a_center });
    _ = try cw.addEventMouseButton(.left, .press);
    _ = try dvui.testing.step(fns.frame);

    // Drag well outside the whole dockspace rect: no leaf or root zone can
    // possibly contain this point, so the drop should float instead.
    _ = try cw.addEventMouseMotion(.{ .pt = .{ .x = a_center.x, .y = -50 } });
    _ = try dvui.testing.step(fns.frame);

    _ = try cw.addEventMouseButton(.left, .release);
    try dvui.testing.settle(fns.frame);

    const a_leaf = fns.layout.findPanel("a").?;
    try std.testing.expect(fns.layout.isFloat(a_leaf));
}

test {
    @import("std").testing.refAllDecls(@This());
}
