//! Runtime profiling mode for dvui's mapping data structures: the
//! `TrackingAutoHashMap`s that back widget tags, per-widget data, animations,
//! min sizes, textures, fonts, path meshes and child OS windows.
//!
//! Turn it on with `dvui.profiling.recording = true`, or build with
//! `-Dprofiling`, which makes every build record from the first frame. Every
//! map that called `profileAs` then counts the operations it serves: puts, get
//! hits and misses, explicit removes, retains, and how many entries a `reset`
//! dropped as dead versus kept because a retain token still held them.
//!
//! The counters sit inline in the map (`TrackingAutoHashMap.prof`), so a
//! recording site is one predictable branch plus one increment: no lookup, no
//! allocation, no pointer chase per operation. Two `u64`s per map carry the
//! live count and its high-water mark, so memory per map stays at 14 words.
//!
//! `report` formats every registered map as a table and is what a headless
//! run uses to collect usage; `Profiler.mappingsPanel` renders the same numbers
//! live in the devtools sidebar.

const std = @import("std");
const build_options = @import("build_options");

/// True while a profiling session records. Off unless built with
/// `-Dprofiling`; the only gate in the hot path of every tracked map.
pub var recording: bool = build_options.profiling;

/// Whether the counters were compiled in at all (`-Dprofiling`). Recording
/// sites read this at comptime so a normal build carries no branch.
pub const compile_time = build_options.profiling;

pub const Counters = struct {
    /// `put`/`putNoClobber`/`fetchPut`/`getOrPut` calls.
    puts: u64 = 0,
    /// Puts that replaced an existing key. Only `fetchPut`/`getOrPut` can know
    /// this without a second lookup, so plain `put`/`putNoClobber` do not
    /// count here.
    puts_existing: u64 = 0,
    /// Lookups: `get`/`getPtr`/`getOrPut`/`containsUsed`.
    gets: u64 = 0,
    /// Lookups that found an entry.
    hits: u64 = 0,
    /// Lookups that found nothing.
    misses: u64 = 0,
    /// Explicit `remove`/`fetchRemove` calls.
    removes: u64 = 0,
    /// `retain`/`retainClear` calls.
    retains: u64 = 0,
    /// Entries a `reset` dropped because nothing accessed them.
    dead: u64 = 0,
    /// Entries a `reset` kept only because a retain token held them.
    retained: u64 = 0,
    /// `reset` calls (one full pass over the map each).
    rescans: u64 = 0,
    /// Entries in the map after the last recorded operation.
    live: u64 = 0,
    /// High-water mark of `live`.
    peak: u64 = 0,

    /// The activity that `after` added on top of `before`. `live`/`peak` are
    /// taken from `after`, since a difference of two counts is not a count.
    pub fn delta(after: Counters, before: Counters) Counters {
        return .{
            .puts = after.puts - before.puts,
            .puts_existing = after.puts_existing - before.puts_existing,
            .gets = after.gets - before.gets,
            .hits = after.hits - before.hits,
            .misses = after.misses - before.misses,
            .removes = after.removes - before.removes,
            .retains = after.retains - before.retains,
            .dead = after.dead - before.dead,
            .retained = after.retained - before.retained,
            .rescans = after.rescans - before.rescans,
            .live = after.live,
            .peak = after.peak,
        };
    }

    /// Fraction of lookups that found an entry, 0 when there were none.
    pub fn hitRate(self: Counters) f64 {
        if (self.gets == 0) return 0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(self.gets));
    }
};

/// One map's registration: its name plus the counters the map writes.
pub const Node = struct {
    name: []const u8 = "",
    /// `dvui.Id` of the owning window, so multi-window apps can tell two
    /// same-named maps apart. 0 for maps not owned by a window.
    owner_id: u64 = 0,
    counters: Counters = .{},
    next: ?*Node = null,
};

var head: ?*Node = null;

/// Adds `node` to the registry. Called from `TrackingAutoHashMap.profileAs`;
/// the node lives in the map, so the registry holds no memory.
pub fn register(node: *Node, name: []const u8, owner_id: u64) void {
    node.name = name;
    node.owner_id = owner_id;
    if (node.next != null or head == node) return; // already linked
    node.next = head;
    head = node;
}

/// Removes `node` from the registry. Called from `TrackingAutoHashMap.deinit`.
pub fn unregister(node: *Node) void {
    var prev: ?*Node = null;
    var cur = head;
    while (cur) |n| {
        if (n == node) {
            if (prev) |p| p.next = n.next else head = n.next;
            n.next = null;
            return;
        }
        prev = n;
        cur = n.next;
    }
}

pub const Iterator = struct {
    cur: ?*Node,

    pub fn next(self: *Iterator) ?*Node {
        const n = self.cur orelse return null;
        self.cur = n.next;
        return n;
    }
};

pub fn iterator() Iterator {
    return .{ .cur = head };
}

/// A copy of one map's counters, safe to keep across frames and to subtract
/// with `Counters.delta`.
pub const Sample = struct {
    name: []const u8,
    owner_id: u64,
    counters: Counters,
};

/// Copies every registered map's counters. The names are the maps' static
/// name slices, so only the returned slice is allocated.
pub fn sample(allocator: std.mem.Allocator) std.mem.Allocator.Error![]Sample {
    var n: usize = 0;
    var it = iterator();
    while (it.next()) |_| n += 1;

    const out = try allocator.alloc(Sample, n);
    it = iterator();
    var i: usize = 0;
    while (it.next()) |node| : (i += 1) {
        out[i] = .{ .name = node.name, .owner_id = node.owner_id, .counters = node.counters };
    }
    return out;
}

/// Totals across every registered map, for a one-line status readout.
pub const Totals = struct {
    maps: usize = 0,
    live: u64 = 0,
    peak: u64 = 0,
    puts: u64 = 0,
    gets: u64 = 0,
    hits: u64 = 0,
    dead: u64 = 0,
    rescans: u64 = 0,

    pub fn hitRate(self: Totals) f64 {
        if (self.gets == 0) return 0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(self.gets));
    }
};

pub fn totals() Totals {
    var t: Totals = .{};
    var it = iterator();
    while (it.next()) |node| {
        const c = node.counters;
        t.maps += 1;
        t.live += c.live;
        t.peak += c.peak;
        t.puts += c.puts;
        t.gets += c.gets;
        t.hits += c.hits;
        t.dead += c.dead;
        t.rescans += c.rescans;
    }
    return t;
}

/// Writes `samples` as a fixed-width table, one row per map. `samples` may come
/// from `sample` in a different frame; the header names the columns.
pub fn report(w: *std.Io.Writer, samples: []const Sample) std.Io.Writer.Error!void {
    try w.print("{s:<34} {s:>7} {s:>7} {s:>9} {s:>8} {s:>9} {s:>8} {s:>5} {s:>7} {s:>7}\n", .{
        "map", "live", "peak", "puts", "put_ex", "gets/hit%", "misses", "rm", "rescans", "dead",
    });
    for (samples) |s| {
        try w.print("{s:<34} {d:>7} {d:>7} {d:>9} {d:>8} {d:>4}/{d:>3.0} {d:>8} {d:>5} {d:>7} {d:>7}\n", .{
            s.name,                   s.counters.live,    s.counters.peak,              s.counters.puts,
            s.counters.puts_existing, s.counters.hits,    s.counters.hitRate() * 100.0, s.counters.misses,
            s.counters.removes,       s.counters.rescans, s.counters.dead,
        });
    }
}

/// Writes the current counters of every registered map.
pub fn reportNow(w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const samples = try sample(allocator);
    defer allocator.free(samples);
    try report(w, samples);
}

test "counters delta and hit rate" {
    const before: Counters = .{ .puts = 3, .gets = 10, .hits = 7, .dead = 2 };
    const after: Counters = .{ .puts = 5, .gets = 14, .hits = 9, .dead = 4, .live = 6, .peak = 8 };
    const d = Counters.delta(after, before);
    try std.testing.expectEqual(@as(u64, 2), d.puts);
    try std.testing.expectEqual(@as(u64, 4), d.gets);
    try std.testing.expectEqual(@as(u64, 2), d.hits);
    try std.testing.expectEqual(@as(u64, 2), d.dead);
    try std.testing.expectEqual(@as(u64, 6), d.live);
    try std.testing.expectEqual(@as(u64, 8), d.peak);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), d.hitRate(), 1e-9);
    try std.testing.expectEqual(@as(f64, 0), (Counters{}).hitRate());
}

test "registry keeps a map's node reachable until deinit" {
    var map = @import("tracking_hash_map.zig").TrackingAutoHashMap(u32, u32, .get_and_put, void).empty;
    map.profileAs("test.registry_map", 0);
    defer map.deinit(std.testing.allocator);

    var found = false;
    var it = iterator();
    while (it.next()) |node| {
        if (node.name.ptr == "test.registry_map".ptr) found = true;
    }
    try std.testing.expect(found);

    // registration is idempotent
    map.profileAs("test.registry_map", 0);
    var count: usize = 0;
    it = iterator();
    while (it.next()) |node| {
        if (node.name.ptr == "test.registry_map".ptr) count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "report writes a header and one row per map" {
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    const samples = [_]Sample{
        .{ .name = "a.b", .owner_id = 0, .counters = .{ .live = 2, .peak = 3, .puts = 5, .gets = 4, .hits = 3, .misses = 1, .removes = 1, .dead = 2, .rescans = 1 } },
        .{ .name = "c.d", .owner_id = 0, .counters = .{} },
    };
    try report(&aw.writer, &samples);

    const text = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, text, "live") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "a.b") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "75") != null); // 3/4 hit rate
    try std.testing.expect(std.mem.indexOf(u8, text, "c.d") != null);
}

test {
    @import("std").testing.refAllDecls(@This());
}
