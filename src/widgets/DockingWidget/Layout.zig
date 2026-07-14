//! Pure-data layout tree for the docking widget: a binary tree of splits with
//! tabbed leaves at the fringes, plus a list of floating leaves. No GUI
//! dependencies beyond `dvui.enums.Direction` and `dvui.Rect` (plain data
//! types), so this can be unit tested without a Window.
const std = @import("std");
const dvui = @import("../../dvui.zig");

/// App-owned slug identifying a dockable panel. `DockLayout` never dupes or
/// frees these: the caller must keep the underlying bytes alive for the
/// lifetime of the layout (typically a static string).
pub const PanelId = []const u8;

pub const NodeIndex = u32;

pub const Side = enum { left, right, top, bottom };

pub const Node = union(enum) {
    split: Split,
    leaf: Leaf,
    /// Free-list entry: node slots are stable and never compacted, so
    /// removed nodes are recycled via this singly linked free list.
    free: ?NodeIndex,

    pub const Split = struct {
        dir: dvui.enums.Direction,
        ratio: f32 = 0.5,
        first: NodeIndex,
        second: NodeIndex,
    };

    pub const Leaf = struct {
        tabs: std.ArrayList(PanelId) = .empty,
        active: usize = 0,
    };
};

pub const Float = struct {
    leaf: NodeIndex,
    rect: dvui.Rect,
};

pub const MoveTarget = union(enum) {
    tab: struct { leaf: NodeIndex, index: usize },
    split: struct { leaf: NodeIndex, side: Side },
    /// Splits the whole tree (root-edge drop zones), regardless of whether
    /// `root` currently holds a leaf or a split.
    split_root: Side,
};

pub const Mutation = union(enum) {
    move: struct { panel: PanelId, target: MoveTarget },
    remove: PanelId,
    set_active: struct { leaf: NodeIndex, index: usize },
    float: struct { panel: PanelId, rect: dvui.Rect },
};

pub const DockLayout = @This();

allocator: std.mem.Allocator,
nodes: std.ArrayList(Node) = .empty,
free_head: ?NodeIndex = null,
root: NodeIndex = 0,
floats: std.ArrayList(Float) = .empty,
/// When set, this layout owns its tab slug strings: `deinit`/`removePanel`
/// free them with `allocator`. `fromSnapshot` sets it (a loaded layout has no
/// other stable source for the slugs). Don't set it yourself unless every
/// `PanelId` you hand this layout is `allocator`-owned.
owns_panel_ids: bool = false,

pub fn init(allocator: std.mem.Allocator) DockLayout {
    return .{ .allocator = allocator };
}

/// Convenience constructor: a single leaf holding one panel as root.
pub fn initSingleLeaf(allocator: std.mem.Allocator, panel: PanelId) !DockLayout {
    var self = init(allocator);
    const idx = try self.allocNode();
    self.nodes.items[idx] = .{ .leaf = .{} };
    try self.nodes.items[idx].leaf.tabs.append(allocator, panel);
    self.root = idx;
    return self;
}

pub fn deinit(self: *DockLayout) void {
    for (self.nodes.items) |*n| {
        switch (n.*) {
            .leaf => |*l| self.freeLeafTabs(l),
            .split, .free => {},
        }
    }
    self.nodes.deinit(self.allocator);
    self.floats.deinit(self.allocator);
    self.* = undefined;
}

/// Frees the tab slug strings too when `owns_panel_ids`, then the tab list
/// container itself either way.
fn freeLeafTabs(self: *DockLayout, l: *Node.Leaf) void {
    if (self.owns_panel_ids) {
        for (l.tabs.items) |t| self.allocator.free(t);
    }
    l.tabs.deinit(self.allocator);
}

fn allocNode(self: *DockLayout) !NodeIndex {
    if (self.free_head) |idx| {
        self.free_head = self.nodes.items[idx].free;
        return idx;
    }
    const idx: NodeIndex = @intCast(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .free = null });
    return idx;
}

fn freeNode(self: *DockLayout, idx: NodeIndex) void {
    switch (self.nodes.items[idx]) {
        .leaf => |*l| self.freeLeafTabs(l),
        .split, .free => {},
    }
    self.nodes.items[idx] = .{ .free = self.free_head };
    self.free_head = idx;
}

/// Finds the leaf node containing `panel` as one of its tabs (main tree or floats).
pub fn findPanel(self: *const DockLayout, panel: PanelId) ?NodeIndex {
    for (self.nodes.items, 0..) |n, i| {
        switch (n) {
            .leaf => |l| for (l.tabs.items) |t| {
                if (std.mem.eql(u8, t, panel)) return @intCast(i);
            },
            .split, .free => {},
        }
    }
    return null;
}

pub fn contains(self: *const DockLayout, panel: PanelId) bool {
    return self.findPanel(panel) != null;
}

pub fn isFloat(self: *const DockLayout, leaf_idx: NodeIndex) bool {
    for (self.floats.items) |f| {
        if (f.leaf == leaf_idx) return true;
    }
    return false;
}

/// Returns the first leaf reached by always descending into `first`, starting at `start`.
pub fn firstLeaf(self: *const DockLayout, start: NodeIndex) NodeIndex {
    var idx = start;
    while (true) {
        switch (self.nodes.items[idx]) {
            .split => |s| idx = s.first,
            .leaf => return idx,
            .free => unreachable,
        }
    }
}

/// Appends the active panel of every leaf (main tree, depth-first, then floats) to `list`.
pub fn collectActivePanels(self: *const DockLayout, list: *std.ArrayList(PanelId), allocator: std.mem.Allocator) !void {
    try self.collectActiveFrom(self.root, list, allocator);
    for (self.floats.items) |f| try self.collectActiveFrom(f.leaf, list, allocator);
}

fn collectActiveFrom(self: *const DockLayout, idx: NodeIndex, list: *std.ArrayList(PanelId), allocator: std.mem.Allocator) !void {
    switch (self.nodes.items[idx]) {
        .split => |s| {
            try self.collectActiveFrom(s.first, list, allocator);
            try self.collectActiveFrom(s.second, list, allocator);
        },
        .leaf => |l| if (l.tabs.items.len > 0) try list.append(allocator, l.tabs.items[l.active]),
        .free => unreachable,
    }
}

const Parent = struct { idx: NodeIndex, side: enum { first, second } };

/// Linear search from root for the split node whose first/second == `target`.
/// Floats have no parent (returns null for a float leaf).
fn findParent(self: *const DockLayout, target: NodeIndex) ?Parent {
    return self.findParentFrom(self.root, target);
}

fn findParentFrom(self: *const DockLayout, idx: NodeIndex, target: NodeIndex) ?Parent {
    switch (self.nodes.items[idx]) {
        .split => |s| {
            if (s.first == target) return .{ .idx = idx, .side = .first };
            if (s.second == target) return .{ .idx = idx, .side = .second };
            if (self.findParentFrom(s.first, target)) |p| return p;
            return self.findParentFrom(s.second, target);
        },
        .leaf, .free => return null,
    }
}

/// Splits `leaf_idx` into a new split node (same index, so external
/// references stay valid) with the existing content moved to one side and a
/// fresh single-tab leaf holding `panel` on the other side.
pub fn splitLeaf(self: *DockLayout, leaf_idx: NodeIndex, side: Side, panel: PanelId) !void {
    const old_leaf = self.nodes.items[leaf_idx].leaf;

    const moved_idx = try self.allocNode();
    self.nodes.items[moved_idx] = .{ .leaf = old_leaf };

    const new_idx = try self.allocNode();
    var new_tabs: std.ArrayList(PanelId) = .empty;
    try new_tabs.append(self.allocator, panel);
    self.nodes.items[new_idx] = .{ .leaf = .{ .tabs = new_tabs, .active = 0 } };

    const dir: dvui.enums.Direction = switch (side) {
        .left, .right => .horizontal,
        .top, .bottom => .vertical,
    };
    const first, const second = switch (side) {
        .left, .top => .{ new_idx, moved_idx },
        .right, .bottom => .{ moved_idx, new_idx },
    };

    self.nodes.items[leaf_idx] = .{ .split = .{ .dir = dir, .ratio = 0.5, .first = first, .second = second } };
}

/// Wraps the whole tree in a new split (root-edge drop zones): `root`'s
/// current content (leaf or split) moves to one side, unchanged, and a fresh
/// single-tab leaf holding `panel` goes on the other side. `root` itself
/// keeps its index (now holding the new split), same trick as `splitLeaf`.
pub fn splitRoot(self: *DockLayout, side: Side, panel: PanelId) !void {
    const old_root = self.nodes.items[self.root];

    const moved_idx = try self.allocNode();
    self.nodes.items[moved_idx] = old_root;

    const new_idx = try self.allocNode();
    var new_tabs: std.ArrayList(PanelId) = .empty;
    try new_tabs.append(self.allocator, panel);
    self.nodes.items[new_idx] = .{ .leaf = .{ .tabs = new_tabs, .active = 0 } };

    const dir: dvui.enums.Direction = switch (side) {
        .left, .right => .horizontal,
        .top, .bottom => .vertical,
    };
    const first, const second = switch (side) {
        .left, .top => .{ new_idx, moved_idx },
        .right, .bottom => .{ moved_idx, new_idx },
    };

    self.nodes.items[self.root] = .{ .split = .{ .dir = dir, .ratio = 0.5, .first = first, .second = second } };
}

/// Inserts `panel` as a new tab in `leaf_idx` at `tab_idx` (clamped) and activates it.
pub fn insertTab(self: *DockLayout, leaf_idx: NodeIndex, tab_idx: usize, panel: PanelId) !void {
    const leaf = &self.nodes.items[leaf_idx].leaf;
    const idx = @min(tab_idx, leaf.tabs.items.len);
    try leaf.tabs.insert(self.allocator, idx, panel);
    leaf.active = idx;
}

/// Like `insertTab`, but duplicates `panel` when `owns_panel_ids` is set, so a
/// borrowed/static id (e.g. from an app's panel registry) can be safely added
/// to a layout that owns its ids — `deinit`/`removePanel` would otherwise try
/// to free a string they don't own.
pub fn insertTabOwned(self: *DockLayout, leaf_idx: NodeIndex, tab_idx: usize, panel: PanelId) !void {
    const id = if (self.owns_panel_ids) try self.allocator.dupe(u8, panel) else panel;
    errdefer if (self.owns_panel_ids) self.allocator.free(id);
    try self.insertTab(leaf_idx, tab_idx, id);
}

/// Reorders `panel` (already in `leaf_idx`) to `new_index` within the same leaf.
fn reorderTab(self: *DockLayout, leaf_idx: NodeIndex, panel: PanelId, new_index: usize) void {
    const leaf = &self.nodes.items[leaf_idx].leaf;
    const cur = for (leaf.tabs.items, 0..) |t, i| {
        if (std.mem.eql(u8, t, panel)) break i;
    } else return;
    const item = leaf.tabs.orderedRemove(cur);
    const idx = @min(new_index, leaf.tabs.items.len);
    leaf.tabs.insert(self.allocator, idx, item) catch return;
    leaf.active = idx;
}

/// Removes `panel` from `leaf_idx`, fixing up `active` (removing the active tab
/// activates the previous index, not 0) and collapsing the tree/floats if the
/// leaf empties. Returns the removed `PanelId` — the same string, still alive,
/// just no longer in the tree — or null if it wasn't there. Callers relocating
/// the panel should ignore it; only `removePanel` frees it (and only when
/// `owns_panel_ids`).
fn removeFromLeaf(self: *DockLayout, leaf_idx: NodeIndex, panel: PanelId) ?PanelId {
    const leaf = &self.nodes.items[leaf_idx].leaf;
    const removed_idx = for (leaf.tabs.items, 0..) |t, i| {
        if (std.mem.eql(u8, t, panel)) break i;
    } else return null;
    const removed = leaf.tabs.orderedRemove(removed_idx);

    if (leaf.tabs.items.len == 0) {
        leaf.active = 0;
    } else {
        if (removed_idx <= leaf.active and leaf.active > 0) leaf.active -= 1;
        leaf.active = @min(leaf.active, leaf.tabs.items.len - 1);
    }

    if (leaf.tabs.items.len > 0) return removed;

    // Empty leaf: collapse it out of whichever structure holds it.
    for (self.floats.items, 0..) |f, i| {
        if (f.leaf == leaf_idx) {
            _ = self.floats.swapRemove(i);
            self.freeNode(leaf_idx);
            return removed;
        }
    }

    if (leaf_idx == self.root) return removed; // tolerate an empty root leaf

    const parent = self.findParent(leaf_idx) orelse return removed;
    const split = self.nodes.items[parent.idx].split;
    const sibling = switch (parent.side) {
        .first => split.second,
        .second => split.first,
    };

    // Promote the sibling's content into the parent's slot (stable index),
    // then free the emptied leaf and the now-unreferenced sibling slot.
    self.nodes.items[parent.idx] = self.nodes.items[sibling];
    self.nodes.items[sibling] = .{ .free = null };
    self.freeNode(sibling);
    self.freeNode(leaf_idx);
    return removed;
}

/// Removes `panel` from wherever it currently is (no-op if not present).
pub fn removePanel(self: *DockLayout, panel: PanelId) void {
    const leaf_idx = self.findPanel(panel) orelse return;
    const removed = self.removeFromLeaf(leaf_idx, panel);
    if (self.owns_panel_ids) {
        if (removed) |r| self.allocator.free(r);
    }
}

pub fn setActive(self: *DockLayout, leaf_idx: NodeIndex, index: usize) void {
    const leaf = &self.nodes.items[leaf_idx].leaf;
    if (index < leaf.tabs.items.len) leaf.active = index;
}

/// Moves `panel` (wherever it currently is) to `target`. No-op if `target`
/// re-specifies the panel's only current location.
pub fn movePanel(self: *DockLayout, panel: PanelId, target: MoveTarget) !void {
    const source_leaf = self.findPanel(panel) orelse return;

    switch (target) {
        .tab => |t| {
            if (t.leaf == source_leaf) {
                self.reorderTab(source_leaf, panel, t.index);
                return;
            }
            try self.insertTab(t.leaf, t.index, panel);
            _ = self.removeFromLeaf(source_leaf, panel);
        },
        .split => |s| {
            if (s.leaf == source_leaf) {
                const tabs_len = self.nodes.items[source_leaf].leaf.tabs.items.len;
                if (tabs_len <= 1) return; // only tab in this leaf: nothing to split against
                _ = self.removeFromLeaf(source_leaf, panel);
                try self.splitLeaf(source_leaf, s.side, panel);
                return;
            }
            try self.splitLeaf(s.leaf, s.side, panel);
            _ = self.removeFromLeaf(source_leaf, panel);
        },
        .split_root => |side| {
            if (source_leaf == self.root) {
                const tabs_len = self.nodes.items[source_leaf].leaf.tabs.items.len;
                if (tabs_len <= 1) return; // only tab in the whole tree: nothing to split against
                _ = self.removeFromLeaf(source_leaf, panel);
                try self.splitRoot(side, panel);
                return;
            }
            try self.splitRoot(side, panel);
            _ = self.removeFromLeaf(source_leaf, panel);
        },
    }
}

/// Detaches `panel` into a new floating leaf at `rect`.
pub fn floatPanel(self: *DockLayout, panel: PanelId, rect: dvui.Rect) !void {
    const source_leaf = self.findPanel(panel);

    const idx = try self.allocNode();
    var tabs: std.ArrayList(PanelId) = .empty;
    try tabs.append(self.allocator, panel);
    self.nodes.items[idx] = .{ .leaf = .{ .tabs = tabs, .active = 0 } };
    try self.floats.append(self.allocator, .{ .leaf = idx, .rect = rect });

    if (source_leaf) |sl| _ = self.removeFromLeaf(sl, panel);
}

pub fn apply(self: *DockLayout, m: Mutation) !void {
    switch (m) {
        .move => |mv| try self.movePanel(mv.panel, mv.target),
        .remove => |p| self.removePanel(p),
        .set_active => |sa| self.setActive(sa.leaf, sa.index),
        .float => |f| try self.floatPanel(f.panel, f.rect),
    }
}

/// Serialization-facing description of a whole layout: a recursive tree of
/// splits and tabbed leaves plus the floating leaves. Holds only plain values
/// (enums, floats, slices, tagged unions), so callers can (de)serialize it in
/// whatever format they like — the widget never picks one. `snapshot` builds
/// one from a live layout; `fromSnapshot` rebuilds a layout from one.
pub const Snapshot = struct {
    root: Tree,
    floats: []const FloatNode = &.{},

    pub const Tree = union(enum) {
        split: Split,
        leaf: Leaf,

        pub const Split = struct {
            dir: dvui.enums.Direction,
            ratio: f32 = 0.5,
            first: *const Tree,
            second: *const Tree,
        };

        pub const Leaf = struct {
            tabs: []const PanelId,
            active: usize = 0,
        };
    };

    pub const FloatNode = struct {
        rect: dvui.Rect,
        leaf: Tree.Leaf,
    };

    /// Frees what `snapshot` allocated. Only valid on a `Snapshot` that
    /// `snapshot` returned, not one deserialized or built by other means.
    pub fn deinit(self: Snapshot, allocator: std.mem.Allocator) void {
        freeTree(self.root, allocator);
        for (self.floats) |f| allocator.free(f.leaf.tabs);
        allocator.free(self.floats);
    }

    fn freeTree(node: Tree, allocator: std.mem.Allocator) void {
        switch (node) {
            .split => |s| {
                freeTree(s.first.*, allocator);
                freeTree(s.second.*, allocator);
                allocator.destroy(s.first);
                allocator.destroy(s.second);
            },
            .leaf => |l| allocator.free(l.tabs),
        }
    }
};

/// Builds a `Snapshot` of the current layout. Tree nodes and tab arrays are
/// allocated with `allocator`; the panel-id strings are borrowed from the live
/// layout (valid until it next changes). Free with `Snapshot.deinit`.
pub fn snapshot(self: *const DockLayout, allocator: std.mem.Allocator) !Snapshot {
    const root = try self.snapshotNode(self.root, allocator);
    errdefer Snapshot.freeTree(root, allocator);

    var floats: std.ArrayList(Snapshot.FloatNode) = .empty;
    errdefer {
        for (floats.items) |f| allocator.free(f.leaf.tabs);
        floats.deinit(allocator);
    }
    for (self.floats.items) |f| {
        const leaf = try snapshotLeaf(self.nodes.items[f.leaf].leaf, allocator);
        errdefer allocator.free(leaf.tabs);
        try floats.append(allocator, .{ .rect = f.rect, .leaf = leaf });
    }

    return .{ .root = root, .floats = try floats.toOwnedSlice(allocator) };
}

fn snapshotNode(self: *const DockLayout, idx: NodeIndex, allocator: std.mem.Allocator) !Snapshot.Tree {
    switch (self.nodes.items[idx]) {
        .split => |sp| {
            const first = try allocator.create(Snapshot.Tree);
            errdefer allocator.destroy(first);
            first.* = try self.snapshotNode(sp.first, allocator);
            errdefer Snapshot.freeTree(first.*, allocator);

            const second = try allocator.create(Snapshot.Tree);
            errdefer allocator.destroy(second);
            second.* = try self.snapshotNode(sp.second, allocator);

            return .{ .split = .{ .dir = sp.dir, .ratio = sp.ratio, .first = first, .second = second } };
        },
        .leaf => |l| return .{ .leaf = try snapshotLeaf(l, allocator) },
        .free => unreachable,
    }
}

fn snapshotLeaf(l: Node.Leaf, allocator: std.mem.Allocator) !Snapshot.Tree.Leaf {
    return .{ .tabs = try allocator.dupe(PanelId, l.tabs.items), .active = l.active };
}

/// Rebuilds a live layout from `snap` (typically freshly deserialized). Panel
/// ids are duplicated with `allocator` and owned by the result
/// (`owns_panel_ids`), so `snap` and its backing bytes may be freed right
/// after. Any well-formed `Snapshot` yields a valid layout.
pub fn fromSnapshot(allocator: std.mem.Allocator, snap: Snapshot) !DockLayout {
    var self = DockLayout.init(allocator);
    self.owns_panel_ids = true;
    errdefer self.deinit();

    self.root = try self.buildNode(snap.root);
    for (snap.floats) |f| {
        const idx = try self.allocNode();
        self.nodes.items[idx] = .{ .leaf = try self.buildLeaf(f.leaf) };
        try self.floats.append(allocator, .{ .leaf = idx, .rect = f.rect });
    }
    return self;
}

fn buildNode(self: *DockLayout, node: Snapshot.Tree) !NodeIndex {
    switch (node) {
        .split => |sp| {
            const first = try self.buildNode(sp.first.*);
            const second = try self.buildNode(sp.second.*);
            const idx = try self.allocNode();
            self.nodes.items[idx] = .{ .split = .{ .dir = sp.dir, .ratio = sp.ratio, .first = first, .second = second } };
            return idx;
        },
        .leaf => |l| {
            const idx = try self.allocNode();
            self.nodes.items[idx] = .{ .leaf = try self.buildLeaf(l) };
            return idx;
        },
    }
}

fn buildLeaf(self: *DockLayout, l: Snapshot.Tree.Leaf) !Node.Leaf {
    var tabs: std.ArrayList(PanelId) = .empty;
    errdefer {
        for (tabs.items) |t| self.allocator.free(t);
        tabs.deinit(self.allocator);
    }
    for (l.tabs) |t| {
        const dup = try self.allocator.dupe(u8, t);
        tabs.append(self.allocator, dup) catch |e| {
            self.allocator.free(dup);
            return e;
        };
    }
    const active: usize = if (tabs.items.len == 0) 0 else @min(l.active, tabs.items.len - 1);
    return .{ .tabs = tabs, .active = active };
}

test "single leaf init and find" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "hierarchy");
    defer layout.deinit();

    try std.testing.expect(layout.contains("hierarchy"));
    try std.testing.expect(!layout.contains("inspector"));
}

test "splitLeaf keeps parent index stable and creates two leaves" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "hierarchy");
    defer layout.deinit();

    const root = layout.root;
    try layout.splitLeaf(root, .right, "inspector");

    try std.testing.expect(layout.root == root); // root index unchanged
    try std.testing.expectEqual(Node.split, std.meta.activeTag(layout.nodes.items[root]));
    const split = layout.nodes.items[root].split;
    try std.testing.expectEqual(dvui.enums.Direction.horizontal, split.dir);
    try std.testing.expect(layout.contains("hierarchy"));
    try std.testing.expect(layout.contains("inspector"));

    const hier_leaf = layout.findPanel("hierarchy").?;
    const insp_leaf = layout.findPanel("inspector").?;
    try std.testing.expect(hier_leaf != insp_leaf);
    try std.testing.expectEqual(split.first, hier_leaf); // .right => existing moves first
    try std.testing.expectEqual(split.second, insp_leaf);
}

test "insertTab adds a tab to an existing leaf" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "hierarchy");
    defer layout.deinit();

    try layout.insertTab(layout.root, 0, "scene");
    const leaf = layout.nodes.items[layout.root].leaf;
    try std.testing.expectEqual(@as(usize, 2), leaf.tabs.items.len);
    try std.testing.expectEqualStrings("scene", leaf.tabs.items[0]);
    try std.testing.expectEqual(@as(usize, 0), leaf.active);
}

test "removePanel collapses single-child split, preserving parent index" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "hierarchy");
    defer layout.deinit();
    const root = layout.root;
    try layout.splitLeaf(root, .right, "inspector");

    layout.removePanel("inspector");

    try std.testing.expect(layout.root == root);
    try std.testing.expectEqual(Node.leaf, std.meta.activeTag(layout.nodes.items[root]));
    try std.testing.expect(layout.contains("hierarchy"));
    try std.testing.expect(!layout.contains("inspector"));
}

test "remove last panel leaves an empty root leaf" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "hierarchy");
    defer layout.deinit();

    layout.removePanel("hierarchy");

    try std.testing.expectEqual(Node.leaf, std.meta.activeTag(layout.nodes.items[layout.root]));
    try std.testing.expectEqual(@as(usize, 0), layout.nodes.items[layout.root].leaf.tabs.items.len);
}

test "removing the active tab activates the previous index, not 0" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    try layout.insertTab(layout.root, 1, "b");
    try layout.insertTab(layout.root, 2, "c"); // active = 2 ("c")

    layout.removePanel("c");

    const leaf = layout.nodes.items[layout.root].leaf;
    try std.testing.expectEqualStrings("b", leaf.tabs.items[leaf.active]);
}

test "movePanel .tab moves panel between leaves and collapses source" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "hierarchy");
    defer layout.deinit();
    const root = layout.root;
    try layout.splitLeaf(root, .right, "inspector");
    const insp_leaf = layout.findPanel("inspector").?;
    const hier_leaf = layout.findPanel("hierarchy").?;

    try layout.movePanel("hierarchy", .{ .tab = .{ .leaf = insp_leaf, .index = 0 } });

    try std.testing.expect(layout.root == root);
    try std.testing.expectEqual(Node.leaf, std.meta.activeTag(layout.nodes.items[root]));
    const leaf = layout.nodes.items[root].leaf;
    try std.testing.expectEqual(@as(usize, 2), leaf.tabs.items.len);
    try std.testing.expectEqualStrings("hierarchy", leaf.tabs.items[0]);
    _ = hier_leaf;
}

test "movePanel .split onto sibling leaf (adjacent collapse) does not corrupt tree" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    const root = layout.root;
    try layout.splitLeaf(root, .right, "b"); // root: split(a | b)
    const b_leaf = layout.findPanel("b").?;

    // Drag the only tab ("a") into "b"'s leaf as a new split (adjacent sibling).
    try layout.movePanel("a", .{ .split = .{ .leaf = b_leaf, .side = .bottom } });

    try std.testing.expect(layout.contains("a"));
    try std.testing.expect(layout.contains("b"));
    try std.testing.expect(layout.root == root);
}

test "movePanel .split onto self is a no-op when it is the only tab" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    const root = layout.root;

    try layout.movePanel("a", .{ .split = .{ .leaf = root, .side = .right } });

    try std.testing.expectEqual(Node.leaf, std.meta.activeTag(layout.nodes.items[root]));
    try std.testing.expectEqual(@as(usize, 1), layout.nodes.items[root].leaf.tabs.items.len);
}

test "movePanel .split on own leaf with other tabs splits off the dragged one" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    try layout.insertTab(layout.root, 1, "b");
    const root = layout.root;

    try layout.movePanel("a", .{ .split = .{ .leaf = root, .side = .right } });

    try std.testing.expect(layout.root == root);
    try std.testing.expectEqual(Node.split, std.meta.activeTag(layout.nodes.items[root]));
    try std.testing.expect(layout.contains("a"));
    try std.testing.expect(layout.contains("b"));
}

test "movePanel .split_root wraps a multi-panel tree, keeping root index stable" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    try layout.splitLeaf(layout.root, .right, "b");
    const root = layout.root;

    try layout.movePanel("a", .{ .split_root = .bottom });

    try std.testing.expect(layout.root == root);
    try std.testing.expectEqual(Node.split, std.meta.activeTag(layout.nodes.items[root]));
    try std.testing.expectEqual(dvui.enums.Direction.vertical, layout.nodes.items[root].split.dir);
    try std.testing.expect(layout.contains("a"));
    try std.testing.expect(layout.contains("b"));
}

test "movePanel .split_root onto self is a no-op when it is the only tab in the whole tree" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    const root = layout.root;

    try layout.movePanel("a", .{ .split_root = .left });

    try std.testing.expect(layout.root == root);
    try std.testing.expectEqual(Node.leaf, std.meta.activeTag(layout.nodes.items[root]));
}

test "insertTabOwned: a borrowed static id in an owning layout doesn't crash on deinit" {
    // An owning layout has every string duped from the start (never a mix);
    // "a" here stands in for that, so deinit freeing it afterward is valid.
    const owned_a = try std.testing.allocator.dupe(u8, "a");
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, owned_a);
    defer layout.deinit();
    layout.owns_panel_ids = true; // simulates a layout loaded via fromSnapshot

    const static_id: PanelId = "profiler"; // NOT allocated by layout.allocator
    try layout.insertTabOwned(layout.root, 1, static_id);

    try std.testing.expect(layout.contains("profiler"));
    // Removing it exercises the free path too (not just deinit's).
    layout.removePanel("profiler");
    try std.testing.expect(!layout.contains("profiler"));
}

test "insertTabOwned: leaves a borrowed id borrowed when the layout doesn't own its ids" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();

    const static_id: PanelId = "profiler";
    try layout.insertTabOwned(layout.root, 1, static_id);

    try std.testing.expectEqual(static_id.ptr, layout.nodes.items[layout.root].leaf.tabs.items[1].ptr);
}

test "floatPanel detaches a panel and freeNode/free-list is reused" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    try layout.insertTab(layout.root, 1, "b");
    const node_count_before = layout.nodes.items.len;

    try layout.floatPanel("b", .{ .x = 10, .y = 10, .w = 200, .h = 200 });

    try std.testing.expectEqual(@as(usize, 1), layout.floats.items.len);
    try std.testing.expect(!layout.contains("b") or layout.isFloat(layout.findPanel("b").?));
    try std.testing.expectEqual(@as(usize, 1), layout.nodes.items[layout.root].leaf.tabs.items.len);

    // Float back out (last tab of the float leaf) -> float entry removed and its slot recycled.
    const float_leaf = layout.findPanel("b").?;
    layout.removePanel("b");
    try std.testing.expectEqual(@as(usize, 0), layout.floats.items.len);
    try std.testing.expectEqual(layout.free_head.?, float_leaf);
    try std.testing.expectEqual(node_count_before + 1, layout.nodes.items.len);
}

test "collectActivePanels walks tree and floats" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    try layout.splitLeaf(layout.root, .right, "b");
    try layout.floatPanel("b", .{ .x = 0, .y = 0, .w = 100, .h = 100 });

    var list: std.ArrayList(PanelId) = .empty;
    defer list.deinit(std.testing.allocator);
    try layout.collectActivePanels(&list, std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
}

test "snapshot/fromSnapshot round-trip preserves tree, tabs, and floats" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    try layout.splitLeaf(layout.root, .right, "b");
    try layout.insertTab(layout.findPanel("b").?, 1, "c");
    try layout.floatPanel("c", .{ .x = 10, .y = 20, .w = 300, .h = 200 });

    const snap = try layout.snapshot(std.testing.allocator);
    defer snap.deinit(std.testing.allocator);

    // Plain `std.testing.allocator` (no arena): exercises that `deinit`
    // actually frees the slug strings `fromSnapshot` duplicated, not just the
    // node/tab-list containers — `owns_panel_ids` is what makes that safe.
    var loaded = try DockLayout.fromSnapshot(std.testing.allocator, snap);
    defer loaded.deinit();

    try std.testing.expect(loaded.owns_panel_ids);
    try std.testing.expect(loaded.contains("a"));
    try std.testing.expect(loaded.contains("b"));
    try std.testing.expect(loaded.contains("c"));
    try std.testing.expect(loaded.isFloat(loaded.findPanel("c").?));
    try std.testing.expectEqual(Node.split, std.meta.activeTag(loaded.nodes.items[loaded.root]));

    const b_float = loaded.floats.items[0];
    try std.testing.expectApproxEqAbs(@as(f32, 10), b_float.rect.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 300), b_float.rect.w, 0.01);

    // Also exercise removePanel actually freeing an owned slug (not just deinit).
    loaded.removePanel("c");
    try std.testing.expect(!loaded.contains("c"));
}

test {
    std.testing.refAllDecls(@This());
}
