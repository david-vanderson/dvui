//! Zig port of mapbox/earcut, line-by-line from src/earcut.js @main.
//!
//! Reference: https://github.com/mapbox/earcut/blob/main/src/earcut.js
//!
//! Robust polygon triangulator with hole support.  Algorithm:
//!   1. Build doubly-linked rings (outer + holes).
//!   2. Link holes into outer via bridge edges (Eberly's algorithm).
//!   3. Ear-clipping loop with z-order spatial hash for fast point-in-
//!      triangle.
//!   4. Three rescue passes for non-simple input: collinear filter,
//!      cure local self-intersections, then split-into-halves.
//!
//! Ported from `lib-svg2tvg`, where it triangulates SVG/TVG icon fills.
//! This does not resolve a general nonzero-winding fill rule over arbitrary
//! self-intersecting/overlapping contours - it
//! assumes each contour is simple, and outer/hole grouping is done by
//! structural containment (see `fillTriangles` below), which matches the
//! nested-rings shape of real icon/font data but is not a strict
//! nonzero-winding-rule equivalent.

const std = @import("std");
const math = std.math;
const dvui = @import("dvui.zig");
const Path = @import("Path.zig");
const Triangles = dvui.Triangles;
const FillOptions = Path.FillOptions;
const Point = dvui.Point.Physical;
const Color = dvui.Color;

/// Triangulate a polygon (with optional holes) into a flat list of
/// triangle vertex indices (3 per triangle).  Caller owns the returned
/// slice.
///
/// `points` is the concatenation of outer + each hole's vertices.
/// `hole_starts[i]` is the index in `points` where hole `i` begins.
/// The outer contour is `points[0..hole_starts[0]]` (or all of points
/// if `hole_starts.len == 0`).
pub fn triangulate(
    alloc: std.mem.Allocator,
    points: []const Point,
    hole_starts: []const usize,
) ![]u32 {
    var tris = std.ArrayList(u32).empty;
    errdefer tris.deinit(alloc);

    if (points.len < 3) return tris.toOwnedSlice(alloc);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const outer_end = if (hole_starts.len > 0) hole_starts[0] else points.len;
    const outer_node_opt = try linkedList(a, points, 0, outer_end, true);
    if (outer_node_opt == null or outer_node_opt.?.next == outer_node_opt.?.prev) {
        return tris.toOwnedSlice(alloc);
    }

    var outer_node = outer_node_opt.?;

    if (hole_starts.len > 0) {
        outer_node = try eliminateHoles(a, points, hole_starts, outer_node);
    }

    var min_x: f32 = 0;
    var min_y: f32 = 0;
    var inv_size: f32 = 0;
    if (points.len > 80) {
        min_x = points[0].x;
        min_y = points[0].y;
        var max_x = min_x;
        var max_y = min_y;
        var i: usize = 1;
        while (i < outer_end) : (i += 1) {
            const p = points[i];
            if (p.x < min_x) min_x = p.x;
            if (p.y < min_y) min_y = p.y;
            if (p.x > max_x) max_x = p.x;
            if (p.y > max_y) max_y = p.y;
        }
        const sz = @max(max_x - min_x, max_y - min_y);
        inv_size = if (sz != 0) 32767.0 / sz else 0;
    }

    try earcutLinked(a, alloc, outer_node, &tris, min_x, min_y, inv_size, 0);

    return tris.toOwnedSlice(alloc);
}

// ---------------------------------------------------------------------------
// Node + linked list construction
// ---------------------------------------------------------------------------

const Node = struct {
    i: u32,
    x: f32,
    y: f32,
    prev: *Node,
    next: *Node,
    z: i32 = 0,
    prev_z: ?*Node = null,
    next_z: ?*Node = null,
    steiner: bool = false,
};

fn createNode(alloc: std.mem.Allocator, i: u32, x: f32, y: f32) !*Node {
    const n = try alloc.create(Node);
    n.* = .{ .i = i, .x = x, .y = y, .prev = n, .next = n };
    return n;
}

fn insertNode(alloc: std.mem.Allocator, i: u32, x: f32, y: f32, last: ?*Node) !*Node {
    const p = try createNode(alloc, i, x, y);
    if (last == null) {
        p.prev = p;
        p.next = p;
    } else {
        const l = last.?;
        p.next = l.next;
        p.prev = l;
        l.next.prev = p;
        l.next = p;
    }
    return p;
}

fn removeNode(p: *Node) void {
    p.next.prev = p.prev;
    p.prev.next = p.next;
    if (p.prev_z) |pz| pz.next_z = p.next_z;
    if (p.next_z) |nz| nz.prev_z = p.prev_z;
}

fn linkedList(alloc: std.mem.Allocator, data: []const Point, start: usize, end: usize, clockwise: bool) !?*Node {
    if (end <= start) return null;
    var last: ?*Node = null;
    const sa = signedArea(data, start, end);
    if (clockwise == (sa > 0)) {
        var i = start;
        while (i < end) : (i += 1) {
            last = try insertNode(alloc, @intCast(i), data[i].x, data[i].y, last);
        }
    } else {
        var i = end;
        while (i > start) {
            i -= 1;
            last = try insertNode(alloc, @intCast(i), data[i].x, data[i].y, last);
        }
    }
    if (last) |l| {
        if (equals(l, l.next)) {
            removeNode(l);
            return l.next;
        }
    }
    return last;
}

fn filterPoints(start_in: ?*Node, end_in: ?*Node) ?*Node {
    if (start_in == null) return null;
    var start = start_in.?;
    var end = end_in orelse start;

    var p = start;
    var again: bool = false;
    while (true) {
        again = false;
        if (!p.steiner and (equals(p, p.next) or area(p.prev, p, p.next) == 0)) {
            removeNode(p);
            p = p.prev;
            end = p;
            if (p == p.next) break;
            again = true;
        } else {
            p = p.next;
        }
        if (!(again or p != end)) break;
    }
    _ = &start;
    return end;
}

// ---------------------------------------------------------------------------
// Main ear-cutting loop
// ---------------------------------------------------------------------------

fn earcutLinked(
    arena: std.mem.Allocator,
    out_alloc: std.mem.Allocator,
    ear_in: ?*Node,
    tris: *std.ArrayList(u32),
    min_x: f32,
    min_y: f32,
    inv_size: f32,
    pass: u8,
) std.mem.Allocator.Error!void {
    var ear = ear_in orelse return;

    if (pass == 0 and inv_size != 0) indexCurve(ear, min_x, min_y, inv_size);

    var stop = ear;

    while (ear.prev != ear.next) {
        const prev = ear.prev;
        const next = ear.next;

        const is_ear_now = if (inv_size != 0) isEarHashed(ear, min_x, min_y, inv_size) else isEar(ear);
        if (is_ear_now) {
            try tris.append(out_alloc, prev.i);
            try tris.append(out_alloc, ear.i);
            try tris.append(out_alloc, next.i);

            removeNode(ear);
            ear = next.next;
            stop = next.next;
            continue;
        }

        ear = next;
        if (ear == stop) {
            if (pass == 0) {
                if (filterPoints(ear, null)) |fp| {
                    try earcutLinked(arena, out_alloc, fp, tris, min_x, min_y, inv_size, 1);
                }
            } else if (pass == 1) {
                if (filterPoints(ear, null)) |fp| {
                    const cured = try cureLocalIntersections(out_alloc, fp, tris);
                    try earcutLinked(arena, out_alloc, cured, tris, min_x, min_y, inv_size, 2);
                }
            } else if (pass == 2) {
                try splitEarcut(arena, out_alloc, ear, tris, min_x, min_y, inv_size);
            }
            break;
        }
    }
}

fn isEar(ear: *Node) bool {
    const a = ear.prev;
    const b = ear;
    const c = ear.next;

    if (area(a, b, c) >= 0) return false;

    const ax = a.x;
    const bx = b.x;
    const cx = c.x;
    const ay = a.y;
    const by = b.y;
    const cy = c.y;

    const x0 = @min(ax, @min(bx, cx));
    const y0 = @min(ay, @min(by, cy));
    const x1 = @max(ax, @max(bx, cx));
    const y1 = @max(ay, @max(by, cy));

    var p = c.next;
    while (p != a) : (p = p.next) {
        if (p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1 and
            pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, p.x, p.y) and
            area(p.prev, p, p.next) >= 0) return false;
    }
    return true;
}

fn isEarHashed(ear: *Node, min_x: f32, min_y: f32, inv_size: f32) bool {
    const a = ear.prev;
    const b = ear;
    const c = ear.next;

    if (area(a, b, c) >= 0) return false;

    const ax = a.x;
    const bx = b.x;
    const cx = c.x;
    const ay = a.y;
    const by = b.y;
    const cy = c.y;

    const x0 = @min(ax, @min(bx, cx));
    const y0 = @min(ay, @min(by, cy));
    const x1 = @max(ax, @max(bx, cx));
    const y1 = @max(ay, @max(by, cy));

    const min_z = zOrder(x0, y0, min_x, min_y, inv_size);
    const max_z = zOrder(x1, y1, min_x, min_y, inv_size);

    var p = ear.prev_z;
    var n = ear.next_z;

    while (p != null and p.?.z >= min_z and n != null and n.?.z <= max_z) {
        if (p.?.x >= x0 and p.?.x <= x1 and p.?.y >= y0 and p.?.y <= y1 and
            p != a and p != c and
            pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, p.?.x, p.?.y) and
            area(p.?.prev, p.?, p.?.next) >= 0) return false;
        p = p.?.prev_z;

        if (n.?.x >= x0 and n.?.x <= x1 and n.?.y >= y0 and n.?.y <= y1 and
            n != a and n != c and
            pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, n.?.x, n.?.y) and
            area(n.?.prev, n.?, n.?.next) >= 0) return false;
        n = n.?.next_z;
    }

    while (p != null and p.?.z >= min_z) {
        if (p.?.x >= x0 and p.?.x <= x1 and p.?.y >= y0 and p.?.y <= y1 and
            p != a and p != c and
            pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, p.?.x, p.?.y) and
            area(p.?.prev, p.?, p.?.next) >= 0) return false;
        p = p.?.prev_z;
    }

    while (n != null and n.?.z <= max_z) {
        if (n.?.x >= x0 and n.?.x <= x1 and n.?.y >= y0 and n.?.y <= y1 and
            n != a and n != c and
            pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, n.?.x, n.?.y) and
            area(n.?.prev, n.?, n.?.next) >= 0) return false;
        n = n.?.next_z;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Rescue strategies
// ---------------------------------------------------------------------------

fn cureLocalIntersections(out_alloc: std.mem.Allocator, start_in: *Node, tris: *std.ArrayList(u32)) !*Node {
    var p = start_in;
    var start = start_in;
    while (true) {
        const a = p.prev;
        const b = p.next.next;
        if (!equals(a, b) and intersects(a, p, p.next, b) and
            locallyInside(a, b) and locallyInside(b, a))
        {
            try tris.append(out_alloc, a.i);
            try tris.append(out_alloc, p.i);
            try tris.append(out_alloc, b.i);
            removeNode(p);
            removeNode(p.next);
            p = b;
            start = b;
        }
        p = p.next;
        if (p == start) break;
    }
    return filterPoints(p, null) orelse p;
}

fn splitEarcut(
    arena: std.mem.Allocator,
    out_alloc: std.mem.Allocator,
    start: *Node,
    tris: *std.ArrayList(u32),
    min_x: f32,
    min_y: f32,
    inv_size: f32,
) std.mem.Allocator.Error!void {
    var a = start;
    while (true) {
        var b = a.next.next;
        while (b != a.prev) : (b = b.next) {
            if (a.i != b.i and isValidDiagonal(a, b)) {
                var c = splitPolygon(arena, a, b) catch return;
                const a_filtered = filterPoints(a, a.next) orelse a;
                const c_filtered = filterPoints(c, c.next) orelse c;
                try earcutLinked(arena, out_alloc, a_filtered, tris, min_x, min_y, inv_size, 0);
                try earcutLinked(arena, out_alloc, c_filtered, tris, min_x, min_y, inv_size, 0);
                _ = &c;
                return;
            }
        }
        a = a.next;
        if (a == start) break;
    }
}

// ---------------------------------------------------------------------------
// Hole elimination
// ---------------------------------------------------------------------------

fn eliminateHoles(alloc: std.mem.Allocator, data: []const Point, hole_starts: []const usize, outer_in: *Node) !*Node {
    var queue = std.ArrayList(*Node).empty;
    defer queue.deinit(alloc);

    var i: usize = 0;
    while (i < hole_starts.len) : (i += 1) {
        const start = hole_starts[i];
        const end = if (i + 1 < hole_starts.len) hole_starts[i + 1] else data.len;
        const list_opt = try linkedList(alloc, data, start, end, false);
        const list = list_opt orelse continue;
        if (list == list.next) list.steiner = true;
        try queue.append(alloc, getLeftmost(list));
    }

    std.mem.sort(*Node, queue.items, {}, compareXYSlope);

    var outer = outer_in;
    for (queue.items) |hole| {
        outer = try eliminateHole(alloc, hole, outer);
    }
    return outer;
}

fn compareXYSlope(_: void, a: *Node, b: *Node) bool {
    var result = a.x - b.x;
    if (result == 0) {
        result = a.y - b.y;
        if (result == 0) {
            const a_slope = (a.next.y - a.y) / (a.next.x - a.x);
            const b_slope = (b.next.y - b.y) / (b.next.x - b.x);
            result = a_slope - b_slope;
        }
    }
    return result < 0;
}

fn eliminateHole(alloc: std.mem.Allocator, hole: *Node, outer_node: *Node) !*Node {
    const bridge = findHoleBridge(hole, outer_node) orelse return outer_node;
    const bridge_reverse = try splitPolygon(alloc, bridge, hole);
    _ = filterPoints(bridge_reverse, bridge_reverse.next);
    return filterPoints(bridge, bridge.next) orelse bridge;
}

fn findHoleBridge(hole: *Node, outer_node: *Node) ?*Node {
    var p: *Node = outer_node;
    const hx = hole.x;
    const hy = hole.y;
    var qx: f32 = -math.floatMax(f32);
    var m: ?*Node = null;

    if (equals(hole, p)) return p;

    while (true) {
        if (equals(hole, p.next)) return p.next;
        if (hy <= p.y and hy >= p.next.y and p.next.y != p.y) {
            const x = p.x + (hy - p.y) * (p.next.x - p.x) / (p.next.y - p.y);
            if (x <= hx and x > qx) {
                qx = x;
                m = if (p.x < p.next.x) p else p.next;
                if (x == hx) return m;
            }
        }
        p = p.next;
        if (p == outer_node) break;
    }

    if (m == null) return null;

    // Look for a better visible vertex inside the triangle (hole, ray hit, m).
    const stop = m.?;
    const mx = m.?.x;
    const my = m.?.y;
    var tan_min: f32 = math.floatMax(f32);
    var best = m.?;

    p = m.?;
    while (true) {
        if (hx >= p.x and p.x >= mx and hx != p.x and
            pointInTriangle(
            if (hy < my) hx else qx,
            hy,
            mx,
            my,
            if (hy < my) qx else hx,
            hy,
            p.x,
            p.y,
        )) {
            const tan_val = @abs(hy - p.y) / (hx - p.x);
            if (locallyInside(p, hole) and
                (tan_val < tan_min or
                    (tan_val == tan_min and
                        (p.x > best.x or (p.x == best.x and sectorContainsSector(best, p))))))
            {
                best = p;
                tan_min = tan_val;
            }
        }
        p = p.next;
        if (p == stop) break;
    }
    return best;
}

fn sectorContainsSector(m: *Node, p: *Node) bool {
    return area(m.prev, m, p.prev) < 0 and area(p.next, m, m.next) < 0;
}

fn getLeftmost(start: *Node) *Node {
    var p = start;
    var leftmost = start;
    while (true) {
        if (p.x < leftmost.x or (p.x == leftmost.x and p.y < leftmost.y)) leftmost = p;
        p = p.next;
        if (p == start) break;
    }
    return leftmost;
}

// ---------------------------------------------------------------------------
// Geometry primitives
// ---------------------------------------------------------------------------

fn pointInTriangle(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32, px: f32, py: f32) bool {
    return (cx - px) * (ay - py) >= (ax - px) * (cy - py) and
        (ax - px) * (by - py) >= (bx - px) * (ay - py) and
        (bx - px) * (cy - py) >= (cx - px) * (by - py);
}

fn pointInTriangleExceptFirst(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32, px: f32, py: f32) bool {
    return !(ax == px and ay == py) and pointInTriangle(ax, ay, bx, by, cx, cy, px, py);
}

fn isValidDiagonal(a: *Node, b: *Node) bool {
    return a.next.i != b.i and a.prev.i != b.i and !intersectsPolygon(a, b) and
        ((locallyInside(a, b) and locallyInside(b, a) and middleInside(a, b) and
            (area(a.prev, a, b.prev) != 0 or area(a, b.prev, b) != 0)) or
            (equals(a, b) and area(a.prev, a, a.next) > 0 and area(b.prev, b, b.next) > 0));
}

fn area(p: *Node, q: *Node, r: *Node) f32 {
    return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y);
}

fn equals(a: *Node, b: *Node) bool {
    return a.x == b.x and a.y == b.y;
}

fn intersects(p1: *Node, q1: *Node, p2: *Node, q2: *Node) bool {
    const o1 = sign(area(p1, q1, p2));
    const o2 = sign(area(p1, q1, q2));
    const o3 = sign(area(p2, q2, p1));
    const o4 = sign(area(p2, q2, q1));
    if (o1 != o2 and o3 != o4) return true;
    if (o1 == 0 and onSegment(p1, p2, q1)) return true;
    if (o2 == 0 and onSegment(p1, q2, q1)) return true;
    if (o3 == 0 and onSegment(p2, p1, q2)) return true;
    if (o4 == 0 and onSegment(p2, q1, q2)) return true;
    return false;
}

fn onSegment(p: *Node, q: *Node, r: *Node) bool {
    return q.x <= @max(p.x, r.x) and q.x >= @min(p.x, r.x) and
        q.y <= @max(p.y, r.y) and q.y >= @min(p.y, r.y);
}

fn sign(v: f32) i32 {
    if (v > 0) return 1;
    if (v < 0) return -1;
    return 0;
}

fn intersectsPolygon(a: *Node, b: *Node) bool {
    var p = a;
    while (true) {
        if (p.i != a.i and p.next.i != a.i and p.i != b.i and p.next.i != b.i and
            intersects(p, p.next, a, b)) return true;
        p = p.next;
        if (p == a) break;
    }
    return false;
}

fn locallyInside(a: *Node, b: *Node) bool {
    return if (area(a.prev, a, a.next) < 0)
        area(a, b, a.next) >= 0 and area(a, a.prev, b) >= 0
    else
        area(a, b, a.prev) < 0 or area(a, a.next, b) < 0;
}

fn middleInside(a: *Node, b: *Node) bool {
    var p = a;
    var inside = false;
    const px = (a.x + b.x) / 2;
    const py = (a.y + b.y) / 2;
    while (true) {
        if (((p.y > py) != (p.next.y > py)) and p.next.y != p.y and
            (px < (p.next.x - p.x) * (py - p.y) / (p.next.y - p.y) + p.x))
            inside = !inside;
        p = p.next;
        if (p == a) break;
    }
    return inside;
}

fn splitPolygon(alloc: std.mem.Allocator, a: *Node, b: *Node) !*Node {
    const a2 = try createNode(alloc, a.i, a.x, a.y);
    const b2 = try createNode(alloc, b.i, b.x, b.y);
    const an = a.next;
    const bp = b.prev;

    a.next = b;
    b.prev = a;
    a2.next = an;
    an.prev = a2;
    b2.next = a2;
    a2.prev = b2;
    bp.next = b2;
    b2.prev = bp;
    return b2;
}

// ---------------------------------------------------------------------------
// Z-order curve (Morton code) spatial indexing
// ---------------------------------------------------------------------------

fn indexCurve(start: *Node, min_x: f32, min_y: f32, inv_size: f32) void {
    var p = start;
    while (true) {
        if (p.z == 0) p.z = zOrder(p.x, p.y, min_x, min_y, inv_size);
        p.prev_z = p.prev;
        p.next_z = p.next;
        p = p.next;
        if (p == start) break;
    }
    p.prev_z.?.next_z = null;
    p.prev_z = null;
    _ = sortLinked(p);
}

fn zOrder(x_in: f32, y_in: f32, min_x: f32, min_y: f32, inv_size: f32) i32 {
    var x: u32 = @intFromFloat(@max(0.0, (x_in - min_x) * inv_size));
    var y: u32 = @intFromFloat(@max(0.0, (y_in - min_y) * inv_size));

    x = (x | (x << 8)) & 0x00FF00FF;
    x = (x | (x << 4)) & 0x0F0F0F0F;
    x = (x | (x << 2)) & 0x33333333;
    x = (x | (x << 1)) & 0x55555555;

    y = (y | (y << 8)) & 0x00FF00FF;
    y = (y | (y << 4)) & 0x0F0F0F0F;
    y = (y | (y << 2)) & 0x33333333;
    y = (y | (y << 1)) & 0x55555555;

    return @bitCast(x | (y << 1));
}

/// Simon Tatham's merge sort on the z-order linked list (prev_z/next_z).
fn sortLinked(list_in: *Node) *Node {
    var list: ?*Node = list_in;
    var in_size: usize = 1;
    while (true) {
        var p_opt: ?*Node = list;
        list = null;
        var tail: ?*Node = null;
        var num_merges: usize = 0;
        while (p_opt) |p_node_init| {
            num_merges += 1;
            var p: ?*Node = p_node_init;
            var q: ?*Node = p_node_init;
            var p_size: usize = 0;
            var k: usize = 0;
            while (k < in_size and q != null) : (k += 1) {
                p_size += 1;
                q = q.?.next_z;
            }
            var q_size: usize = in_size;

            while (p_size > 0 or (q_size > 0 and q != null)) {
                var e: *Node = undefined;
                if (p_size != 0 and (q_size == 0 or q == null or p.?.z <= q.?.z)) {
                    e = p.?;
                    p = p.?.next_z;
                    p_size -= 1;
                } else {
                    e = q.?;
                    q = q.?.next_z;
                    q_size -= 1;
                }
                if (tail) |t| t.next_z = e else list = e;
                e.prev_z = tail;
                tail = e;
            }
            p_opt = q;
        }
        if (tail) |t| t.next_z = null;
        in_size *= 2;
        if (num_merges <= 1) break;
    }
    return list orelse list_in;
}

// ---------------------------------------------------------------------------
// Signed area of a polygon range — earcut's convention (matches JS reference).
// ---------------------------------------------------------------------------

fn signedArea(data: []const Point, start: usize, end: usize) f32 {
    var sum: f32 = 0;
    if (end <= start) return 0;
    var j: usize = end - 1;
    var i: usize = start;
    while (i < end) : (i += 1) {
        sum += (data[j].x - data[i].x) * (data[i].y + data[j].y);
        j = i;
    }
    return sum;
}

// ---------------------------------------------------------------------------
// dvui Path integration: outer/hole grouping + AA
// ---------------------------------------------------------------------------

fn ringSignedArea(pts: []const Point) f32 {
    return signedArea(pts, 0, pts.len);
}

fn pointInPolygonEvenOdd(p: Point, poly: []const Point) bool {
    if (poly.len < 3) return false;
    var inside = false;
    var j: usize = poly.len - 1;
    for (poly, 0..) |a, i| {
        const b = poly[j];
        if (((a.y > p.y) != (b.y > p.y)) and
            (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x))
        {
            inside = !inside;
        }
        j = i;
    }
    return inside;
}

/// Triangulate one outer contour (+ its matched holes) via `triangulate`,
/// append opaque fill triangles to `sink`, and (if `opts.fade > 0`) collect
/// AA boundary pieces.
///
/// Boundary edges are found via the standard "silhouette edge" trick:
/// build every directed edge of every emitted triangle, keyed by its
/// (unordered) endpoint pair. Edges emitted by exactly one triangle are the
/// true polygon boundary (outer or hole); edges emitted by two triangles are
/// earcut-internal diagonals (incl. bridge edges, used once per side) and
/// cancel out. This needs no separate bookkeeping of which points came from
/// which contour.
fn emitGroup(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    sink: *Path.FillSink,
    boundary: *std.ArrayList(Path.FillBoundaryEdge),
    pts: []const Point,
    hole_starts: []const usize,
    col: Color.PMA,
    fade: f32,
) !void {
    const idx = try triangulate(arena, pts, hole_starts);
    if (idx.len == 0) return;

    var vtx_idx = try arena.alloc(u32, pts.len);
    @memset(vtx_idx, std.math.maxInt(u32));
    for (idx) |i| {
        if (vtx_idx[i] == std.math.maxInt(u32)) {
            vtx_idx[i] = try sink.addVertex(allocator, .{ .pos = pts[i], .col = col });
        }
    }

    const EdgeKey = struct { lo: u32, hi: u32 };
    var edge_count = std.AutoHashMap(EdgeKey, u8).init(arena);
    if (fade > 0) {
        var t: usize = 0;
        while (t < idx.len) : (t += 3) {
            inline for (.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 0 } }) |pair| {
                const p0 = idx[t + pair[0]];
                const p1 = idx[t + pair[1]];
                const key: EdgeKey = if (p0 < p1) .{ .lo = p0, .hi = p1 } else .{ .lo = p1, .hi = p0 };
                const gop = try edge_count.getOrPut(key);
                if (!gop.found_existing) gop.value_ptr.* = 0;
                gop.value_ptr.* += 1;
            }
        }
    }

    var t: usize = 0;
    while (t < idx.len) : (t += 3) {
        const idx0 = idx[t];
        const idx1 = idx[t + 1];
        const idx2 = idx[t + 2];
        try sink.addTri(allocator, vtx_idx[idx0], vtx_idx[idx1], vtx_idx[idx2]);

        if (fade > 0) {
            const centroid: Point = .{
                .x = (pts[idx0].x + pts[idx1].x + pts[idx2].x) / 3,
                .y = (pts[idx0].y + pts[idx1].y + pts[idx2].y) / 3,
            };
            inline for (.{ .{ idx0, idx1 }, .{ idx1, idx2 }, .{ idx2, idx0 } }) |pair| {
                const a = pair[0];
                const b = pair[1];
                const key: EdgeKey = if (a < b) .{ .lo = a, .hi = b } else .{ .lo = b, .hi = a };
                if ((edge_count.get(key) orelse 0) == 1) {
                    try Path.fillAddBoundaryPiece(boundary, arena, pts[a], pts[b], centroid);
                }
            }
        }
    }
}

/// Generates triangles filling the shape described by `contours` according
/// to `opts.color`/`opts.fade`, treating winding purely by structural
/// nesting (outer contours vs. holes contained in them) rather than a
/// general nonzero/evenodd winding-number rule - see module doc.
///
/// Grouping: each contour's immediate parent is the smallest-area other
/// contour that contains it (containment forest, via
/// `pointInPolygonEvenOdd` on one anchor vertex). A contour's depth in that
/// forest (ancestor count) then decides fill vs. hole by parity - even
/// depth (0 = top-level) fills, odd depth punches a hole from its immediate
/// parent, alternating from there. This matches how real icon/font data
/// nests rings-with-glyphs-with-counters (entypo `compass`: outer ring ->
/// inner ring as hole -> needle as inner outer -> needle's own hole)
/// *without* assuming every contour's raw signed-area sign alternates with
/// visual nesting - real SVG->TVG converters don't guarantee that, they
/// lean on the renderer's nonzero fill rule instead. Sign-vs-single-
/// reference-contour comparison (the previous approach here) breaks for
/// exactly that reason once there are 3+ nesting levels or several
/// independent sibling glyphs (e.g. entypo `creative-commons-sharealike`).
///
/// Still not a general nonzero-winding-number fill: two *overlapping*
/// same-depth contours need real winding-number resolution,
/// which this containment-forest approximation can't express.
pub fn fillTriangles(allocator: std.mem.Allocator, contours: []const Path, opts: FillOptions) std.mem.Allocator.Error!Triangles {
    if (contours.len == 0) return .empty;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var sink: Path.FillSink = .{};
    const col: Color.PMA = .fromColor(opts.color);
    var boundary: std.ArrayList(Path.FillBoundaryEdge) = .empty;

    if (contours.len == 1) {
        try emitGroup(allocator, arena, &sink, &boundary, contours[0].points, &.{}, col, opts.fade);
    } else {
        const areas = try arena.alloc(f32, contours.len);
        for (contours, 0..) |c, i| areas[i] = ringSignedArea(c.points);

        // Immediate containment parent: the smallest-area other contour
        // whose polygon contains this contour's anchor vertex.
        const parent = try arena.alloc(?usize, contours.len);
        for (contours, 0..) |c, ci| {
            if (c.points.len == 0) {
                parent[ci] = null;
                continue;
            }
            const anchor = c.points[0];
            var best_parent: ?usize = null;
            var best_area: f32 = math.floatMax(f32);
            for (contours, 0..) |other, oi| {
                if (oi == ci or other.points.len == 0) continue;
                if (!pointInPolygonEvenOdd(anchor, other.points)) continue;
                const a = @abs(areas[oi]);
                if (a < best_area) {
                    best_area = a;
                    best_parent = oi;
                }
            }
            parent[ci] = best_parent;
        }

        // Depth parity: even (0 = no parent) is an outer fill, odd is a
        // hole punched from its immediate parent. `parent` is only a forest
        // when containment is properly nested; two contours that merely
        // overlap (anchor-in-other true both ways, e.g. offset same-size
        // shapes in a "stack" icon) can point at each other. That's not a
        // real containment relationship this module can resolve (see doc
        // comment above), so cap the walk at `contours.len` steps and treat
        // a cycle as top-level rather than looping forever.
        const is_outer = try arena.alloc(bool, contours.len);
        for (0..contours.len) |ci| {
            var depth: usize = 0;
            var cur = parent[ci];
            while (cur) |p| : (cur = parent[p]) {
                depth += 1;
                if (depth > contours.len) break;
            }
            is_outer[ci] = (depth % 2 == 0);
        }

        for (contours, 0..) |outer, oi| {
            if (!is_outer[oi]) continue;

            var pts: std.ArrayList(Point) = .empty;
            var hole_idx: std.ArrayList(usize) = .empty;
            for (outer.points) |p| try pts.append(arena, p);
            for (contours, 0..) |hole, hi| {
                if (is_outer[hi] or parent[hi] != oi) continue;
                try hole_idx.append(arena, pts.items.len);
                for (hole.points) |p| try pts.append(arena, p);
            }

            try emitGroup(allocator, arena, &sink, &boundary, pts.items, hole_idx.items, col, opts.fade);
        }
    }

    if (opts.fade > 0 and boundary.items.len > 0) {
        try Path.fillAppendFade(&sink, allocator, arena, boundary.items, col, opts.fade);
    }

    return sink.build(allocator);
}

// ---------------------------------------------------------------------------
// Self-tests
// ---------------------------------------------------------------------------

test "triangulate unit square" {
    const pts = [_]Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 0 },
        .{ .x = 1, .y = 1 },
        .{ .x = 0, .y = 1 },
    };
    const tri = try triangulate(std.testing.allocator, &pts, &.{});
    defer std.testing.allocator.free(tri);
    try std.testing.expectEqual(@as(usize, 6), tri.len);
}

test "triangulate square with square hole" {
    const pts = [_]Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 10, .y = 10 },
        .{ .x = 0, .y = 10 },
        .{ .x = 3, .y = 3 },
        .{ .x = 3, .y = 7 },
        .{ .x = 7, .y = 7 },
        .{ .x = 7, .y = 3 },
    };
    const holes = [_]usize{4};
    const tri = try triangulate(std.testing.allocator, &pts, &holes);
    defer std.testing.allocator.free(tri);
    try std.testing.expectEqual(@as(usize, 24), tri.len);
}

test "triangulate L-shape" {
    const pts = [_]Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 10, .y = 4 },
        .{ .x = 4, .y = 4 },
        .{ .x = 4, .y = 10 },
        .{ .x = 0, .y = 10 },
    };
    const tri = try triangulate(std.testing.allocator, &pts, &.{});
    defer std.testing.allocator.free(tri);
    try std.testing.expectEqual(@as(usize, 12), tri.len);
}

test fillTriangles {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    // donut: outer square, inner square hole (opposite winding)
    const outer: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };
    const hole: Path = .{ .points = &.{
        .{ .x = 25, .y = 25 },
        .{ .x = 75, .y = 25 },
        .{ .x = 75, .y = 75 },
        .{ .x = 25, .y = 75 },
    } };

    var triangles = try fillTriangles(std.testing.allocator, &.{ outer, hole }, .{ .color = Color.white, .fade = 1.0 });
    defer triangles.deinit(std.testing.allocator);

    try std.testing.expect(triangles.vertexes.len > 0);

    const hole_center: Point = .{ .x = 50, .y = 50 };
    var i: usize = 0;
    while (i < triangles.indices.len) : (i += 3) {
        const v0 = triangles.vertexes[triangles.indices[i]];
        const v1 = triangles.vertexes[triangles.indices[i + 1]];
        const v2 = triangles.vertexes[triangles.indices[i + 2]];
        if (v0.col.a != 255 or v1.col.a != 255 or v2.col.a != 255) continue;
        try std.testing.expect(!testPointInTriangle(hole_center, v0.pos, v1.pos, v2.pos));
    }

    const ring_pt: Point = .{ .x = 10, .y = 50 };
    var covered = false;
    i = 0;
    while (i < triangles.indices.len) : (i += 3) {
        const v0 = triangles.vertexes[triangles.indices[i]];
        const v1 = triangles.vertexes[triangles.indices[i + 1]];
        const v2 = triangles.vertexes[triangles.indices[i + 2]];
        if (v0.col.a != 255 or v1.col.a != 255 or v2.col.a != 255) continue;
        if (testPointInTriangle(ring_pt, v0.pos, v1.pos, v2.pos)) covered = true;
    }
    try std.testing.expect(covered);
}

fn testPointInTriangle(p: Point, a: Point, b: Point, c: Point) bool {
    const d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y);
    const d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y);
    const d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y);
    const has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0);
    const has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0);
    return !(has_neg and has_pos);
}

test {
    std.testing.refAllDecls(@This());
}
