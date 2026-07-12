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

pub const InitOptions = struct {
    layout: *Layout.DockLayout,
    panelInfo: *const fn (Layout.PanelId) PanelInfo,
};

wd: WidgetData,
init_opts: InitOptions,

/// Mutations queued by tab clicks/closes (and, later, drag-and-drop) this
/// frame; applied to `init_opts.layout` in `deinit`.
mutations: std.ArrayList(Layout.Mutation) = .empty,
/// True after `deinit` if any mutation was applied (caller should persist).
changed: bool = false,

stack: std.ArrayList(StackFrame) = .empty,
started: bool = false,
float_index: usize = 0,
current_float: ?*dvui.FloatingWindowWidget = null,
content_box: ?*dvui.BoxWidget = null,

const StackFrame = struct {
    node: Layout.NodeIndex,
    paned: *dvui.PanedWidget,
    visited_first: bool = false,
    visited_second: bool = false,
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

/// Stable id for widgets tied to a specific panel (tab button, close button,
/// content box): must not depend on tree position so state (scroll, etc.)
/// survives the panel being dragged elsewhere.
fn slugIdExtra(slug: Layout.PanelId) usize {
    return @truncate(std.hash.Wyhash.hash(0, slug));
}

/// Queues `m` for application in `deinit`, and marks `self.changed` right
/// away: callers typically read `changed` right after the `while (dock.panel())`
/// loop, before the `defer dock.deinit()` that applies the mutation actually runs.
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

    self.drawHeader(node, leaf);

    const active_slug = leaf.tabs.items[leaf.active];
    const box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .id_extra = slugIdExtra(active_slug) });
    self.content_box = box;

    return .{ .id = active_slug, .leaf = node, .dockspace = self };
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
}

fn drawHeader(self: *Dockspace, node: Layout.NodeIndex, leaf: Layout.Node.Leaf) void {
    var tw = dvui.tabs(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = node });
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
            if (info.closable) {
                const close_tag = std.fmt.allocPrint(dvui.currentWindow().arena(), "docktab_close:{s}", .{slug}) catch null;
                // Draw (and fully process) the close button before the tab's
                // own click handling below, so a close click doesn't also
                // register as a tab-select click.
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

        tab.processEvents();
        if (tab.clicked()) {
            self.queueMutation(.{ .set_active = .{ .leaf = node, .index = i } });
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

test {
    @import("std").testing.refAllDecls(@This());
}
