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
/// Set by `parseJson`: unlike the normal live-tree contract (app-owned
/// static `PanelId` strings), a parsed file has no other stable source for
/// the slugs, so `parseJson` duplicates them with `allocator` and `deinit`
/// frees those copies. Don't set this yourself unless you also allocated
/// every current and future `PanelId` you hand this layout with `allocator`.
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

/// Frees the tab slug strings too when `owns_panel_ids` (set by `parseJson`),
/// then the tab list container itself either way.
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

/// Like `insertTab`, but safe to call with a borrowed/static `panel` string
/// regardless of `owns_panel_ids`: duplicates it first when set, since
/// `deinit`/`removePanel` will otherwise try to free a string they don't
/// own (this is how a static id from an app's panel registry — e.g. a "show
/// this panel again" menu action — safely ends up in a layout that was
/// loaded from `parseJson`).
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

/// Removes `panel` from `leaf_idx` (must currently contain it), fixing up
/// `active` and collapsing the tree/floats if the leaf becomes empty.
/// Removal of the active tab activates the previous tab index, not 0.
/// Removes `panel` from `leaf_idx` and returns the removed `PanelId` (the
/// same string that was stored — still alive, just no longer in the tree),
/// or null if it wasn't there. Callers relocating the panel elsewhere should
/// ignore the return value; only a true deletion (`removePanel`) should free
/// it (and only when `owns_panel_ids`).
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

/// Schema:
/// ```json
/// { "version": 1,
///   "root": { "split": { "dir": "horizontal", "ratio": 0.5,
///     "first": { "leaf": { "tabs": ["a"], "active": 0 } },
///     "second": { "leaf": { "tabs": ["b"], "active": 0 } } } },
///   "floats": [ { "rect": [x,y,w,h], "leaf": { "tabs": ["c"], "active": 0 } } ] }
/// ```
/// No dvui dependency beyond `std.json` and the plain data types already
/// used elsewhere in this file.
pub fn writeJson(self: *const DockLayout, writer: *std.Io.Writer) !void {
    var s: std.json.Stringify = .{ .writer = writer };
    try s.beginObject();

    try s.objectField("version");
    try s.write(1);

    try s.objectField("root");
    try self.writeNodeJson(&s, self.root);

    try s.objectField("floats");
    try s.beginArray();
    for (self.floats.items) |f| {
        try s.beginObject();
        try s.objectField("rect");
        try s.beginArray();
        try s.write(f.rect.x);
        try s.write(f.rect.y);
        try s.write(f.rect.w);
        try s.write(f.rect.h);
        try s.endArray();
        try s.objectField("leaf");
        try writeLeafJson(&s, self.nodes.items[f.leaf].leaf);
        try s.endObject();
    }
    try s.endArray();

    try s.endObject();
}

fn writeNodeJson(self: *const DockLayout, s: *std.json.Stringify, idx: NodeIndex) !void {
    switch (self.nodes.items[idx]) {
        .split => |sp| {
            try s.beginObject();
            try s.objectField("split");
            try s.beginObject();
            try s.objectField("dir");
            try s.write(@tagName(sp.dir));
            try s.objectField("ratio");
            try s.write(sp.ratio);
            try s.objectField("first");
            try self.writeNodeJson(s, sp.first);
            try s.objectField("second");
            try self.writeNodeJson(s, sp.second);
            try s.endObject();
            try s.endObject();
        },
        .leaf => |l| {
            try s.beginObject();
            try s.objectField("leaf");
            try writeLeafJson(s, l);
            try s.endObject();
        },
        .free => unreachable,
    }
}

fn writeLeafJson(s: *std.json.Stringify, l: Node.Leaf) !void {
    try s.beginObject();
    try s.objectField("tabs");
    try s.beginArray();
    for (l.tabs.items) |t| try s.write(t);
    try s.endArray();
    try s.objectField("active");
    try s.write(l.active);
    try s.endObject();
}

/// Deserializes a layout written by `writeJson`. `version` is required and
/// must be `1`; any structural problem fails the whole parse (forward-fail —
/// callers should catch, log, and fall back to a default layout rather than
/// trying to salvage a partial tree).
///
/// Panel slug strings are duplicated with `allocator` (the `PanelId` contract
/// elsewhere in this file — layout never dupes/frees — assumes app-owned
/// static strings, which a parsed file can't provide). This sets
/// `owns_panel_ids`, so a plain `deinit()` frees those slug copies too, same
/// as any other allocation this layout owns — no arena required. If you
/// reconcile the parsed slugs against your own static registry (dropping
/// unknown ones, say), do that before relying on `owns_panel_ids`-driven
/// freeing, since it frees whatever strings are still in the tree at
/// `deinit()`, not specifically "the ones parseJson allocated".
pub fn parseJson(allocator: std.mem.Allocator, slice: []const u8) !DockLayout {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, slice, .{});
    defer parsed.deinit();

    const root_obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.InvalidFormat,
    };

    const version = switch (root_obj.get("version") orelse return error.InvalidVersion) {
        .integer => |i| i,
        else => return error.InvalidVersion,
    };
    if (version != 1) return error.InvalidVersion;

    var self = DockLayout.init(allocator);
    self.owns_panel_ids = true;
    errdefer self.deinit();

    self.root = try parseNode(&self, root_obj.get("root") orelse return error.InvalidFormat);

    if (root_obj.get("floats")) |floats_v| {
        const floats_arr = switch (floats_v) {
            .array => |a| a,
            else => return error.InvalidFormat,
        };
        for (floats_arr.items) |fv| {
            const fo = switch (fv) {
                .object => |o| o,
                else => return error.InvalidFormat,
            };
            const rect_arr = switch (fo.get("rect") orelse return error.InvalidFormat) {
                .array => |a| a,
                else => return error.InvalidFormat,
            };
            if (rect_arr.items.len != 4) return error.InvalidFormat;
            const rect: dvui.Rect = .{
                .x = try jsonNumber(rect_arr.items[0]),
                .y = try jsonNumber(rect_arr.items[1]),
                .w = try jsonNumber(rect_arr.items[2]),
                .h = try jsonNumber(rect_arr.items[3]),
            };
            const leaf = try parseLeaf(&self, fo.get("leaf") orelse return error.InvalidFormat);
            const idx = try self.allocNode();
            self.nodes.items[idx] = .{ .leaf = leaf };
            try self.floats.append(allocator, .{ .leaf = idx, .rect = rect });
        }
    }

    return self;
}

fn jsonNumber(v: std.json.Value) !f32 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => error.InvalidFormat,
    };
}

fn parseLeaf(self: *DockLayout, v: std.json.Value) !Node.Leaf {
    const obj = switch (v) {
        .object => |o| o,
        else => return error.InvalidFormat,
    };
    const tabs_arr = switch (obj.get("tabs") orelse return error.InvalidFormat) {
        .array => |a| a,
        else => return error.InvalidFormat,
    };

    var tabs: std.ArrayList(PanelId) = .empty;
    for (tabs_arr.items) |tv| {
        const str = switch (tv) {
            .string => |str| str,
            else => return error.InvalidFormat,
        };
        try tabs.append(self.allocator, try self.allocator.dupe(u8, str));
    }

    const active_raw: i64 = switch (obj.get("active") orelse std.json.Value{ .integer = 0 }) {
        .integer => |i| i,
        else => 0,
    };
    const active: usize = if (tabs.items.len == 0) 0 else @intCast(std.math.clamp(active_raw, 0, @as(i64, @intCast(tabs.items.len - 1))));

    return .{ .tabs = tabs, .active = active };
}

fn parseNode(self: *DockLayout, v: std.json.Value) !NodeIndex {
    const obj = switch (v) {
        .object => |o| o,
        else => return error.InvalidFormat,
    };

    if (obj.get("split")) |split_v| {
        const so = switch (split_v) {
            .object => |o| o,
            else => return error.InvalidFormat,
        };
        const dir_str = switch (so.get("dir") orelse return error.InvalidFormat) {
            .string => |str| str,
            else => return error.InvalidFormat,
        };
        const dir = std.meta.stringToEnum(dvui.enums.Direction, dir_str) orelse return error.InvalidFormat;
        const ratio = try jsonNumber(so.get("ratio") orelse std.json.Value{ .float = 0.5 });
        const first = try parseNode(self, so.get("first") orelse return error.InvalidFormat);
        const second = try parseNode(self, so.get("second") orelse return error.InvalidFormat);

        const idx = try self.allocNode();
        self.nodes.items[idx] = .{ .split = .{ .dir = dir, .ratio = ratio, .first = first, .second = second } };
        return idx;
    }

    if (obj.get("leaf")) |leaf_v| {
        const leaf = try parseLeaf(self, leaf_v);
        const idx = try self.allocNode();
        self.nodes.items[idx] = .{ .leaf = leaf };
        return idx;
    }

    return error.InvalidFormat;
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

test "insertTabOwned: a borrowed static id in an owning (parseJson'd) layout doesn't crash on deinit" {
    // A real parseJson'd layout has every string duped from the start (never
    // a mix); "a" here stands in for that, so deinit freeing it afterward is valid.
    const owned_a = try std.testing.allocator.dupe(u8, "a");
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, owned_a);
    defer layout.deinit();
    layout.owns_panel_ids = true; // simulates a layout loaded via parseJson

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

test "writeJson/parseJson round-trip preserves tree, tabs, and floats" {
    var layout = try DockLayout.initSingleLeaf(std.testing.allocator, "a");
    defer layout.deinit();
    try layout.splitLeaf(layout.root, .right, "b");
    try layout.insertTab(layout.findPanel("b").?, 1, "c");
    try layout.floatPanel("c", .{ .x = 10, .y = 20, .w = 300, .h = 200 });

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try layout.writeJson(&out.writer);

    // Plain `std.testing.allocator` (no arena): exercises that `deinit`
    // actually frees the slug strings `parseJson` duplicated, not just the
    // node/tab-list containers — `owns_panel_ids` is what makes that safe.
    var loaded = try DockLayout.parseJson(std.testing.allocator, out.written());
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

test "parseJson forward-fails on missing or wrong version" {
    try std.testing.expectError(error.InvalidVersion, DockLayout.parseJson(std.testing.allocator, "{}"));
    try std.testing.expectError(error.InvalidVersion, DockLayout.parseJson(std.testing.allocator,
        \\{"version": 2, "root": {"leaf": {"tabs": ["a"], "active": 0}}}
    ));
}

test "parseJson forward-fails on malformed root" {
    try std.testing.expectError(error.InvalidFormat, DockLayout.parseJson(std.testing.allocator,
        \\{"version": 1, "root": {"nonsense": true}}
    ));
}

test {
    std.testing.refAllDecls(@This());
}
