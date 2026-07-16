//! A collection of points that make up a shape that can later be rendered to the screen.
//!
//! This is the basic tool to create rectangles and more complex polygons to later be
//! turned into `Triangles` and rendered to the screen.

points: []const Point.Physical,

pub const Path = @This();

/// A builder with an ArrayList to add points to.
///
/// If a OutOfMemory error occurs, the builder with log it and ignore it,
/// meaning that you would get an incomplete path in that case. For rendering,
/// this will produce an incorrect output but will largely tend to work.
///
/// `Builder.deinit` should always be called as `Builder.build` does not give ownership
/// of the memory
pub const Builder = struct {
    points: std.array_list.Managed(Point.Physical),
    oom_error_occurred: bool = false,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .points = .init(allocator) };
    }

    pub fn deinit(path: *Builder) void {
        path.points.deinit();
    }

    /// Returns a non-owned `Path`. Calling `deinit` on the `Builder` is still required to free memory
    pub fn build(path: *Builder) Path {
        if (path.oom_error_occurred) {
            // This does not allow for error return traces, but
            // reduces spam caused by logs on every call to `addPoint`
            dvui.logError(@src(), std.mem.Allocator.Error.OutOfMemory, "Path encountered error and is likely incomplete", .{});
        }
        return .{ .points = path.points.items };
    }

    /// Add a point to the path
    pub fn addPoint(path: *Builder, p: Point.Physical) void {
        path.points.append(p) catch {
            path.oom_error_occurred = true;
        };
    }

    /// Add rect to path with corners.  Starts from top left, and ends at top
    /// right unclosed.  See `Rect.fill`.
    pub fn addRect(path: *Builder, r: Rect.Physical, corners: CornerRect.Physical) void {
        const max_w = r.w / 2;
        const max_h = r.h / 2;

        const rad_tl = corners.tl.getRenderingOffsets(max_w, max_h);
        const rad_tr = corners.tr.getRenderingOffsets(max_w, max_h);
        const rad_bl = corners.bl.getRenderingOffsets(max_w, max_h);
        const rad_br = corners.br.getRenderingOffsets(max_w, max_h);

        path.addCorner(corners.tl, r, rad_tl, rad_bl, .tl);
        path.addCorner(corners.bl, r, rad_bl, rad_br, .bl);
        path.addCorner(corners.br, r, rad_br, rad_tr, .br);
        path.addCorner(corners.tr, r, rad_tr, rad_tl, .tr);
    }

    /// DO NOT USE this function as a user which you should always use addRect,
    /// this should only be used for the internal library
    pub fn addCorner(
        path: *Builder,
        corner: Corner.Physical,
        rect: Rect.Physical,
        r_cur: Point.Physical,
        r_next: Point.Physical,
        comptime p: CornerRect.Position,
    ) void {
        const origin_x: f32, const origin_y: f32 = getCornerOrigin(rect, p);
        const offset_x, const offset_y = getCornerOffset(r_cur, p);

        const p_next: CornerRect.Position = switch (p) {
            .tl => .bl,
            .bl => .br,
            .br => .tr,
            .tr => .tl,
        };
        const origin_x_next, const origin_y_next = getCornerOrigin(rect, p_next);
        const offset_x_next, const offset_y_next = getCornerOffset(r_next, p_next);

        switch (corner.kind) {
            .round => {
                const pi_start: f32, const pi_end: f32 = switch (p) {
                    .tl => .{ math.pi * 1.5, math.pi },
                    .tr => .{ math.pi * 2.0, math.pi * 1.5 },
                    .bl => .{ math.pi, math.pi * 0.5 },
                    .br => .{ math.pi * 0.5, 0 },
                };
                const skip_end: bool = switch (p) {
                    .tl, .br => @abs((origin_y + offset_y) - (origin_y_next + offset_y_next)) < 0.5,
                    .bl, .tr => @abs((origin_x + offset_x) - (origin_x_next + offset_x_next)) < 0.5,
                };
                path.addArc(.{ .x = origin_x + offset_x, .y = origin_y + offset_y }, r_cur.x, pi_start, pi_end, skip_end);
            },
            .nudge => path.addPoint(.{ .x = origin_x + offset_x, .y = origin_y + offset_y }),
            .angular, .chamfer => {
                var draw_last = switch (p) {
                    .tl => origin_y + offset_y < origin_y_next + offset_y_next,
                    .bl => origin_x + offset_x < origin_x_next + offset_x_next,
                    .br => origin_y + offset_y > origin_y_next + offset_y_next,
                    .tr => origin_x + offset_x > origin_x_next + offset_x_next,
                };
                draw_last = draw_last and (offset_x != 0 or offset_y != 0);
                switch (p) {
                    .tl, .br => {
                        path.addPoint(.{ .x = origin_x + offset_x, .y = origin_y });
                        if (draw_last) path.addPoint(.{ .x = origin_x, .y = origin_y + offset_y });
                    },
                    .tr, .bl => {
                        path.addPoint(.{ .x = origin_x, .y = origin_y + offset_y });
                        if (draw_last) path.addPoint(.{ .x = origin_x + offset_x, .y = origin_y });
                    },
                }
            },
            .square, .theme => {
                // INFO: .theme shouldn't be unhandled at this stage since there is no way to find the corner
                // INFO: and rect in physical size, thus treated same as the square mode, for now.
                path.addPoint(.{ .x = origin_x, .y = origin_y });
            },
        }
    }

    fn getCornerOrigin(rect: Rect.Physical, comptime p: CornerRect.Position) struct { f32, f32 } {
        return switch (p) {
            .tl => .{ rect.x, rect.y },
            .tr => .{ rect.x + rect.w, rect.y },
            .bl => .{ rect.x, rect.y + rect.h },
            .br => .{ rect.x + rect.w, rect.y + rect.h },
        };
    }

    fn getCornerOffset(r: Point.Physical, comptime p: CornerRect.Position) struct { f32, f32 } {
        return switch (p) {
            .tl => .{ r.x, r.y },
            .tr => .{ -r.x, r.y },
            .bl => .{ r.x, -r.y },
            .br => .{ -r.x, -r.y },
        };
    }

    /// Add line segments creating an arc to path.
    ///
    /// `start` >= `end`, both are radians that go clockwise from the positive x axis.
    ///
    /// If `skip_end`, the final point will not be added.  Useful if the next
    /// addition to path would duplicate the end of the arc.
    pub fn addArc(path: *Builder, center: Point.Physical, radius: f32, start: f32, end: f32, skip_end: bool) void {
        if (radius == 0) {
            path.addPoint(center);
            return;
        }

        // how close our points will be to the perfect circle
        const err = 0.5;

        // angle that has err error between circle and segments
        const theta = math.acos(radius / (radius + err));

        var a: f32 = start;
        path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });

        while (a - end > theta) {
            // move to next fixed theta, this prevents shimmering on things like a spinner
            a = @floor((a - 0.001) / theta) * theta;
            path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
        }

        if (!skip_end) {
            a = end;
            path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
        }
    }

    /// Add line segments flattening a quadratic bezier curve to path.
    ///
    /// `p0`, `control`, `p1` are all explicit (no implicit "current point" -
    /// consistent with `addArc` taking full explicit geometry).  `p0` is
    /// added, then the curve is adaptively subdivided until each segment is
    /// within 0.5 physical-pixel deviation of the true curve, ending with `p1`.
    pub fn addQuadBezier(path: *Builder, p0: Point.Physical, control: Point.Physical, p1: Point.Physical) void {
        path.addPoint(p0);
        path.addQuadBezierRecurse(p0, control, p1, 0);
    }

    fn addQuadBezierRecurse(path: *Builder, p0: Point.Physical, control: Point.Physical, p1: Point.Physical, depth: u8) void {
        // how close our points will be to the perfect curve
        const err = 0.5;
        const max_depth = 24;
        // max deviation of the curve from the chord p0-p1, see quadratic
        // bezier - chord difference derivation: t(1-t)*(2*control - p0 - p1),
        // maximized at t=0.5
        const dev = control.scale(2, Point.Physical).diff(p0).diff(p1).length() * 0.25;
        if (dev <= err or depth >= max_depth) {
            path.addPoint(p1);
            return;
        }
        const p01 = p0.plus(control).scale(0.5, Point.Physical);
        const p12 = control.plus(p1).scale(0.5, Point.Physical);
        const p012 = p01.plus(p12).scale(0.5, Point.Physical);
        path.addQuadBezierRecurse(p0, p01, p012, depth + 1);
        path.addQuadBezierRecurse(p012, p12, p1, depth + 1);
    }

    /// Add line segments flattening a cubic bezier curve to path.
    ///
    /// `p0`, `c1`, `c2`, `p1` are all explicit (no implicit "current point" -
    /// consistent with `addArc`/`addQuadBezier`).  `p0` is added, then the
    /// curve is adaptively subdivided until each segment is within 0.5
    /// physical-pixel deviation of the true curve, ending with `p1`.
    pub fn addCubicBezier(path: *Builder, p0: Point.Physical, c1: Point.Physical, c2: Point.Physical, p1: Point.Physical) void {
        path.addPoint(p0);
        path.addCubicBezierRecurse(p0, c1, c2, p1, 0);
    }

    fn addCubicBezierRecurse(path: *Builder, p0: Point.Physical, c1: Point.Physical, c2: Point.Physical, p1: Point.Physical, depth: u8) void {
        // how close our points will be to the perfect curve
        const err = 0.5;
        const max_depth = 24;
        if (cubicFlatEnough(p0, c1, c2, p1, err) or depth >= max_depth) {
            path.addPoint(p1);
            return;
        }
        const p01 = p0.plus(c1).scale(0.5, Point.Physical);
        const p12 = c1.plus(c2).scale(0.5, Point.Physical);
        const p23 = c2.plus(p1).scale(0.5, Point.Physical);
        const p012 = p01.plus(p12).scale(0.5, Point.Physical);
        const p123 = p12.plus(p23).scale(0.5, Point.Physical);
        const p0123 = p012.plus(p123).scale(0.5, Point.Physical);
        path.addCubicBezierRecurse(p0, p01, p012, p0123, depth + 1);
        path.addCubicBezierRecurse(p0123, p123, p23, p1, depth + 1);
    }

    /// Classic cubic bezier flatness test (Sederberg): flat enough if the
    /// control points' distance from the chord p0-p1 is within `err`.
    fn cubicFlatEnough(p0: Point.Physical, c1: Point.Physical, c2: Point.Physical, p1: Point.Physical, err: f32) bool {
        const ux = 3 * c1.x - 2 * p0.x - p1.x;
        const uy = 3 * c1.y - 2 * p0.y - p1.y;
        const vx = 3 * c2.x - p0.x - 2 * p1.x;
        const vy = 3 * c2.y - p0.y - 2 * p1.y;
        return @max(ux * ux, vx * vx) + @max(uy * uy, vy * vy) <= 16 * err * err;
    }
};

test Builder {
    var t = try dvui.testing.init(.{});
    defer t.deinit();
    var builder = Path.Builder.init(std.testing.allocator);
    // deinit should always be called on the builder
    defer builder.deinit();
    builder.addRect(.{ .x = 10, .y = 20, .w = 30, .h = 40 }, .round(0));
    const path = builder.build();
    // path does not have to be freed as the memory is still
    // owned by and will be freed by the Path.Builder
    try std.testing.expectEqual(4, path.points.len);
    var triangles = try path.fillConvexTriangles(std.testing.allocator, .{ .color = Color.white });
    defer triangles.deinit(std.testing.allocator);
    try std.testing.expectApproxEqRel(10, triangles.bounds.x, 0.05);
    try std.testing.expectApproxEqRel(20, triangles.bounds.y, 0.05);
    try std.testing.expectApproxEqRel(30, triangles.bounds.w, 0.05);
    try std.testing.expectApproxEqRel(40, triangles.bounds.h, 0.05);
}

test "Builder.addQuadBezier" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const p0: Point.Physical = .{ .x = 0, .y = 0 };
    const control: Point.Physical = .{ .x = 50, .y = 100 };
    const p1: Point.Physical = .{ .x = 100, .y = 0 };

    var small = Path.Builder.init(std.testing.allocator);
    defer small.deinit();
    small.addQuadBezier(p0, control, p1);

    // scale the same curve up 10x - more points should be needed since the
    // (fixed, physical-pixel) error tolerance is now a tighter relative bound
    var big = Path.Builder.init(std.testing.allocator);
    defer big.deinit();
    big.addQuadBezier(p0.scale(10, Point.Physical), control.scale(10, Point.Physical), p1.scale(10, Point.Physical));
    try std.testing.expect(big.points.items.len > small.points.items.len);
    try std.testing.expectEqual(p0, small.points.items[0]);
    try std.testing.expectEqual(p1, small.points.items[small.points.items.len - 1]);
    // deviation check at the true curve midpoint (t=0.5): some flattened
    // point must land close to it (within the ~0.5px error tolerance)
    const mid = quadBezierPoint(p0, control, p1, 0.5);
    var min_dist: f32 = std.math.floatMax(f32);
    for (small.points.items) |pt| {
        min_dist = @min(min_dist, mid.diff(pt).length());
    }
    try std.testing.expect(min_dist <= 1.0);
}

test "Builder.addCubicBezier" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();
    const p0: Point.Physical = .{ .x = 0, .y = 0 };
    const c1: Point.Physical = .{ .x = 0, .y = 100 };
    const c2: Point.Physical = .{ .x = 100, .y = 100 };
    const p1: Point.Physical = .{ .x = 100, .y = 0 };
    var small = Path.Builder.init(std.testing.allocator);
    defer small.deinit();
    small.addCubicBezier(p0, c1, c2, p1);
    try std.testing.expect(small.points.items.len >= 2);
    try std.testing.expectEqual(p0, small.points.items[0]);
    try std.testing.expectEqual(p1, small.points.items[small.points.items.len - 1]);
    var big = Path.Builder.init(std.testing.allocator);
    defer big.deinit();
    big.addCubicBezier(p0.scale(10, Point.Physical), c1.scale(10, Point.Physical), c2.scale(10, Point.Physical), p1.scale(10, Point.Physical));
    try std.testing.expect(big.points.items.len > small.points.items.len);
    // sampled midpoint of the true curve must be near some flattened point
    const mid = cubicBezierPoint(p0, c1, c2, p1, 0.5);
    var min_dist: f32 = std.math.floatMax(f32);
    for (small.points.items) |pt| {
        min_dist = @min(min_dist, mid.diff(pt).length());
    }
    try std.testing.expect(min_dist <= 1.0);
}

fn quadBezierPoint(p0: Point.Physical, c: Point.Physical, p1: Point.Physical, t: f32) Point.Physical {
    const mt = 1 - t;
    return .{
        .x = mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x,
        .y = mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y,
    };
}

fn cubicBezierPoint(p0: Point.Physical, c1: Point.Physical, c2: Point.Physical, p1: Point.Physical, t: f32) Point.Physical {
    const mt = 1 - t;
    return .{
        .x = mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p1.x,
        .y = mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p1.y,
    };
}

pub fn dupe(path: Path, allocator: std.mem.Allocator) std.mem.Allocator.Error!Path {
    return .{ .points = try allocator.dupe(Point.Physical, path.points) };
}

pub const FillConvexOptions = struct {
    color: Color,

    /// Size (physical pixels) of fade to transparent centered on the edge.
    /// If >1, then starts a half-pixel inside and the rest outside.
    fade: f32 = 0.0,
    center: ?Point.Physical = null,
};

/// Fill path (must be convex) with `color` (or `Theme.color_fill`).  See `Rect.fill`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn fillConvex(path: Path, opts: FillConvexOptions) void {
    if (path.points.len < 3) {
        return;
    }

    if (dvui.clipGet().empty()) {
        return;
    }

    const cw = dvui.currentWindow();

    if (!cw.render_target.rendering) {
        const new_path = path.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathFillConvex = .{ .path = new_path, .opts = opts } }, false);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = path.fillConvexTriangles(cw.lifo(), options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, null) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{options});
        return;
    };
}

/// Generates triangles to fill path (must be convex).
///
/// Vertexes will have unset uv and color is alpha multiplied opts.color
/// fading to transparent at the edge if fade is > 0.
pub fn fillConvexTriangles(path: Path, allocator: std.mem.Allocator, opts: FillConvexOptions) std.mem.Allocator.Error!Triangles {
    if (path.points.len < 3) {
        return .empty;
    }

    var vtx_count = path.points.len;
    var idx_count = (path.points.len - 2) * 3;
    if (opts.fade > 0) {
        vtx_count *= 2;
        idx_count += path.points.len * 6;
    }
    if (opts.center) |_| {
        vtx_count += 1;
        idx_count += 6;
    }

    var builder = try Triangles.Builder.init(allocator, vtx_count, idx_count);
    errdefer comptime unreachable; // No errors from this point on

    const col: Color.PMA = .fromColor(opts.color);

    var i: usize = 0;
    while (i < path.points.len) : (i += 1) {
        const ai: u16 = @intCast((i + path.points.len - 1) % path.points.len);
        const bi: u16 = @intCast(i % path.points.len);
        const ci: u16 = @intCast((i + 1) % path.points.len);
        const aa = path.points[ai];
        const bb = path.points[bi];
        const cc = path.points[ci];

        const diffab = aa.diff(bb).normalize();
        const diffbc = bb.diff(cc).normalize();
        // average of normals on each side
        var norm: Point.Physical = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

        // inner vertex
        const inside_len = @min(0.5, opts.fade / 2);
        builder.appendVertex(.{
            .pos = .{
                .x = bb.x - norm.x * inside_len,
                .y = bb.y - norm.y * inside_len,
            },
            .col = col,
        });

        const idx_ai = if (opts.fade > 0) ai * 2 else ai;
        const idx_bi = if (opts.fade > 0) bi * 2 else bi;

        // indexes for fill
        // triangles must be counter-clockwise (y going down) to avoid backface culling
        if (opts.center) |_| {
            builder.appendTriangles(&.{ @intCast(vtx_count - 1), idx_ai, idx_bi });
        } else if (i > 1) {
            builder.appendTriangles(&.{ 0, idx_ai, idx_bi });
        }

        if (opts.fade > 0) {
            // scale averaged normal by angle between which happens to be the same as
            // dividing by the length^2
            const d2 = norm.x * norm.x + norm.y * norm.y;
            if (d2 > 0.000001) {
                norm = norm.scale(1.0 / d2, Point.Physical);
            }

            // limit distance our vertexes can be from the point to 2 so
            // very small angles don't produce huge geometries
            const l = norm.length();
            if (l > 2.0) {
                norm = norm.scale(2.0 / l, Point.Physical);
            }

            // outer vertex
            const outside_len = if (opts.fade <= 1) opts.fade / 2 else opts.fade - 0.5;
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x + norm.x * outside_len,
                    .y = bb.y + norm.y * outside_len,
                },
                .col = .transparent,
            });

            // indexes for aa fade from inner to outer
            // triangles must be counter-clockwise (y going down) to avoid backface culling
            builder.appendTriangles(&.{
                idx_ai,     idx_ai + 1, idx_bi,
                idx_ai + 1, idx_bi + 1, idx_bi,
            });
        }
    }

    if (opts.center) |center| {
        builder.appendVertex(.{
            .pos = center,
            .col = col,
        });
    }

    return builder.build();
}

pub const StrokeOptions = struct {
    /// true => Render this after normal drawing on that subwindow.  Useful for
    /// debugging on cross-gui drawing.
    after: bool = false,

    thickness: f32,
    color: Color,

    /// true => Stroke includes from path end to path start.
    closed: bool = false,
    endcap_style: EndCapStyle = .none,

    pub const EndCapStyle = enum {
        none,
        square,
    };
};

/// Stroke path as a series of line segments.  See `Rect.stroke`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn stroke(path: Path, opts: StrokeOptions) void {
    if (path.points.len == 0) {
        return;
    }

    const cw = dvui.currentWindow();

    if (opts.after or !cw.render_target.rendering) {
        const new_path = path.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathStroke = .{ .path = new_path, .opts = opts } }, opts.after);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = path.strokeTriangles(cw.lifo(), options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, null) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{opts});
        return;
    };
}

/// Generates triangles to stroke path.
///
/// Vertexes will have unset uv and color is alpha multiplied opts.color
/// fading to transparent at the edge.
pub fn strokeTriangles(path: Path, allocator: std.mem.Allocator, opts: StrokeOptions) std.mem.Allocator.Error!Triangles {
    if (dvui.clipGet().empty()) {
        return .empty;
    }

    if (path.points.len == 1) {
        // draw a circle with radius thickness at that point
        const center = path.points[0];

        const other_allocator = if (dvui.current_window) |cw|
            if (cw.lifo().ptr != allocator.ptr) cw.lifo() else cw.arena()
        else
            // Using the same allocator will "leak" the tempPath on
            // arena allocators because it can only free the last allocation
            allocator;

        var tempPath: Path.Builder = .init(other_allocator);
        defer tempPath.deinit();

        tempPath.addArc(center, opts.thickness, math.pi * 2.0, 0, true);
        return tempPath.build().fillConvexTriangles(allocator, .{ .color = opts.color, .fade = 1.0 });
    }

    const Side = enum {
        none,
        left,
        right,
    };

    // a single segment can't be closed
    const closed: bool = if (path.points.len == 2) false else opts.closed;

    var vtx_count = path.points.len * 8;
    if (!closed) {
        vtx_count += 4;
    }
    // max is 18 per leg (2 tri fill plus 4 tri fade)
    // plus (if miter is too long) 18 for fill and fade at each corner
    var idx_count = (path.points.len - 1) * 18 + (path.points.len - 2) * 18;
    if (closed) {
        idx_count += 18 + 2 * 18;
    } else {
        idx_count += 8 * 3;
    }

    var builder = try Triangles.Builder.init(allocator, vtx_count, idx_count);

    const col: Color.PMA = .fromColor(opts.color);

    const aa_size = 1.0;
    var vtx_left: u16 = 0;
    var vtx_right: u16 = 0;
    var i: usize = 0;
    const last_i: usize = if (closed) path.points.len + 1 else path.points.len;
    while (i < last_i) : (i += 1) {
        const ai: u16 = @intCast((i + path.points.len - 1) % path.points.len);
        const bi: u16 = @intCast(i % path.points.len);
        const ci: u16 = @intCast((i + 1) % path.points.len);
        const aa = path.points[ai];
        var bb = path.points[bi];
        const cc = path.points[ci];
        var miter_break: Side = .none;

        // the amount to move from bb to the edge of the line
        var halfnorm: Point.Physical = undefined;
        var halfnorm_miter: Point.Physical = undefined;
        var diffab: Point.Physical = undefined;

        if (!closed and ((i == 0) or ((i + 1) == path.points.len))) {
            if (i == 0) {
                const diffbc = bb.diff(cc).normalize();
                // rotate by 90 to get normal
                halfnorm = .{ .x = diffbc.y / 2, .y = (-diffbc.x) / 2 };

                if (opts.endcap_style == .square) {
                    // square endcaps move bb out by thickness
                    bb.x += diffbc.x * opts.thickness;
                    bb.y += diffbc.y * opts.thickness;
                }

                // add 2 extra vertexes for endcap fringe
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x - halfnorm.x * (opts.thickness + aa_size) + diffbc.x * aa_size,
                        .y = bb.y - halfnorm.y * (opts.thickness + aa_size) + diffbc.y * aa_size,
                    },
                    .col = .transparent,
                });

                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + halfnorm.x * (opts.thickness + aa_size) + diffbc.x * aa_size,
                        .y = bb.y + halfnorm.y * (opts.thickness + aa_size) + diffbc.y * aa_size,
                    },
                    .col = .transparent,
                });

                // add indexes for endcap fringe
                builder.appendTriangles(&.{
                    0, 2, 3,
                    0, 1, 2,
                    1, 4, 2,
                    1, 5, 4,
                });
            } else if ((i + 1) == path.points.len) {
                diffab = aa.diff(bb).normalize();
                // rotate by 90 to get normal
                halfnorm = .{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                if (opts.endcap_style == .square) {
                    // square endcaps move bb out by thickness
                    bb.x -= diffab.x * opts.thickness;
                    bb.y -= diffab.y * opts.thickness;
                }
            }
        } else {
            diffab = aa.diff(bb).normalize();
            const diffbc = bb.diff(cc).normalize();
            // average of normals on each side
            halfnorm = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

            // scale averaged normal by angle between which happens to be the same as
            // dividing by the length^2
            const d2 = halfnorm.x * halfnorm.x + halfnorm.y * halfnorm.y;
            if (d2 > 0.000001) {
                halfnorm = halfnorm.scale(0.5 / d2, Point.Physical);
            } else {
                // degenerate case - ab and bc are on top of each other
                halfnorm = aa.diff(bb);
            }

            // limit distance our vertexes can be from the point to 2 * thickness so
            // very small angles don't produce huge geometries
            const l = halfnorm.length();
            if (l > 2.0) {
                halfnorm_miter = halfnorm.scale(2.0 / l, Point.Physical);

                const hn_len = halfnorm.length() * (opts.thickness + aa_size);
                const ab_len = aa.diff(bb).length();
                const bc_len = bb.diff(cc).length();
                const max_len = @min(hn_len, ab_len, bc_len);
                if (max_len < hn_len) {
                    halfnorm = halfnorm.scale(max_len / hn_len, Point.Physical);
                }

                const dot = diffab.x * halfnorm.x + diffab.y * halfnorm.y;
                if (dot > 0) {
                    miter_break = .left;
                } else {
                    miter_break = .right;
                }
            }
        }

        const vtx_base: u16 = if (i == path.points.len) 0 else @intCast(builder.vertexes.items.len);
        var vtx_left_in = vtx_base;
        var vtx_right_in = vtx_left_in + 2;

        var vtx_left_out = vtx_left_in;
        var vtx_right_out = vtx_right_in;

        switch (miter_break) {
            .none => {},
            .left => {
                vtx_left_in += 4;
                vtx_left_out += 6;
            },
            .right => {
                vtx_right_in += 2;
                vtx_right_out += 4;
            },
        }

        if (i < path.points.len) {
            {
                const hn = if (miter_break == .left) halfnorm_miter else halfnorm;
                // left inner vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x - hn.x * opts.thickness,
                        .y = bb.y - hn.y * opts.thickness,
                    },
                    .col = col,
                });

                // left AA vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x - hn.x * (opts.thickness + aa_size),
                        .y = bb.y - hn.y * (opts.thickness + aa_size),
                    },
                    .col = .transparent,
                });
            }

            {
                const hn = if (miter_break == .right) halfnorm_miter else halfnorm;
                // right inner vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + hn.x * opts.thickness,
                        .y = bb.y + hn.y * opts.thickness,
                    },
                    .col = col,
                });

                // right AA vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + hn.x * (opts.thickness + aa_size),
                        .y = bb.y + hn.y * (opts.thickness + aa_size),
                    },
                    .col = .transparent,
                });
            }

            switch (miter_break) {
                .none => {},
                .left => {
                    const hn = .{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                    // left bump start inner (vtx_left_in)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * opts.thickness,
                            .y = bb.y - hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // left bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * (opts.thickness + aa_size),
                            .y = bb.y - hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // right bump start inner (vtx_left_out)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * opts.thickness,
                            .y = bb.y + hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // right bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * (opts.thickness + aa_size),
                            .y = bb.y + hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // add triangles to fill the miter (counter clockwise y going down)
                    builder.appendTriangles(&.{
                        // indexes for fill
                        vtx_left_in, vtx_base + 2,     vtx_base,
                        vtx_base,    vtx_base + 2,     vtx_left_out,

                        // aa fade
                        vtx_left_in, vtx_base,         vtx_left_in + 1,
                        vtx_base,    vtx_base + 1,     vtx_left_in + 1,

                        vtx_base,    vtx_left_out,     vtx_left_out + 1,
                        vtx_base,    vtx_left_out + 1, vtx_base + 1,
                    });
                },
                .right => {
                    const hn = .{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                    // right bump start inner (vtx_right_in)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * opts.thickness,
                            .y = bb.y + hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // right bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * (opts.thickness + aa_size),
                            .y = bb.y + hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // left bump start inner (vtx_right_out)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * opts.thickness,
                            .y = bb.y - hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // left bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * (opts.thickness + aa_size),
                            .y = bb.y - hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // add triangles to fill the miter (counter clockwise y going down)
                    builder.appendTriangles(&.{
                        // indexes for fill
                        vtx_right_in,     vtx_base + 2,      vtx_base,
                        vtx_base,         vtx_base + 2,      vtx_right_out,

                        // aa fade
                        vtx_right_in,     vtx_right_in + 1,  vtx_base + 2,
                        vtx_right_in + 1, vtx_base + 3,      vtx_base + 2,

                        vtx_base + 2,     vtx_base + 3,      vtx_right_out,
                        vtx_base + 3,     vtx_right_out + 1, vtx_right_out,
                    });
                },
            }
        }

        // triangles must be counter-clockwise (y going down) to avoid backface culling
        if ((i > 0) and (closed or (i < path.points.len))) {
            // vtx1 wraps when closed
            builder.appendTriangles(&.{
                // indexes for fill
                vtx_left,  vtx_right,        vtx_left_in,
                vtx_right, vtx_right_in,     vtx_left_in,

                // indexes for aa fade from inner to outer left side
                vtx_left,  vtx_left_in + 1,  vtx_left + 1,
                vtx_left,  vtx_left_in,      vtx_left_in + 1,

                // indexes for aa fade from inner to outer right side
                vtx_right, vtx_right + 1,    vtx_right_in + 1,
                vtx_right, vtx_right_in + 1, vtx_right_in,
            });
        }

        if (!closed and (i + 1) == path.points.len) {
            // add 2 extra vertexes for endcap fringe

            const vtx: u16 = @intCast(builder.vertexes.items.len);
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x - halfnorm.x * (opts.thickness + aa_size) - diffab.x * aa_size,
                    .y = bb.y - halfnorm.y * (opts.thickness + aa_size) - diffab.y * aa_size,
                },
                .col = .transparent,
            });
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x + halfnorm.x * (opts.thickness + aa_size) - diffab.x * aa_size,
                    .y = bb.y + halfnorm.y * (opts.thickness + aa_size) - diffab.y * aa_size,
                },
                .col = .transparent,
            });

            builder.appendTriangles(&.{
                // add indexes for endcap fringe
                vtx_left_in,  vtx,              vtx_left_in + 1,
                vtx,          vtx_left_in,      vtx_right_in,
                vtx,          vtx_right_in,     vtx + 1,
                vtx_right_in, vtx_right_in + 1, vtx + 1,
            });
        }

        vtx_left = vtx_left_out;
        vtx_right = vtx_right_out;
    }

    return builder.build();
}

pub const FillOptions = struct {
    color: Color,

    /// Size (physical pixels) of fade to transparent centered on the true
    /// (resolved) polygon boundary. If >1, then starts a half-pixel inside
    /// and the rest outside.
    fade: f32 = 0.0,

    fill_rule: FillRule = .nonzero,

    pub const FillRule = enum { nonzero, evenodd };
};

/// Fill a general shape made up of one or more closed contours (each a
/// `Path`) with `color`.  Contours may be concave, may contain holes (any
/// contour orientation is fine - overlap/containment relative to
/// `FillOptions.fill_rule` is what determines the hole), and may contain
/// small self-intersections (e.g. left over from upstream bezier
/// flattening) without producing garbage output.
///
/// For a single convex contour, prefer `fillConvex` (much cheaper).
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn fill(contours: []const Path, opts: FillOptions) void {
    if (contours.len == 0) return;

    if (dvui.clipGet().empty()) {
        return;
    }

    const cw = dvui.currentWindow();

    if (!cw.render_target.rendering) {
        const new_contours = dupeContours(contours, cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathFill = .{ .contours = new_contours, .opts = opts } }, false);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = fillTriangles(cw.lifo(), contours, options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, null) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{options});
        return;
    };
}

fn dupeContours(contours: []const Path, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const Path {
    const out = try allocator.alloc(Path, contours.len);
    for (contours, out) |c, *o| {
        o.* = try c.dupe(allocator);
    }
    return out;
}

/// Sink for accumulating output geometry - vertexes/indices are allocated
/// with the (long-lived, caller-owned) output allocator, everything else
/// used by `fillTriangles` is scratch allocated from an arena.
pub const FillSink = struct {
    vtx: std.ArrayList(Vertex) = .empty,
    idx: std.ArrayList(Vertex.Index) = .empty,
    bounds: Rect.Physical = .{
        .x = math.floatMax(f32),
        .y = math.floatMax(f32),
        .w = -math.floatMax(f32),
        .h = -math.floatMax(f32),
    },

    pub fn addVertex(self: *FillSink, allocator: std.mem.Allocator, v: Vertex) std.mem.Allocator.Error!u32 {
        try self.vtx.append(allocator, v);
        self.bounds.x = @min(self.bounds.x, v.pos.x);
        self.bounds.y = @min(self.bounds.y, v.pos.y);
        self.bounds.w = @max(self.bounds.w, v.pos.x);
        self.bounds.h = @max(self.bounds.h, v.pos.y);
        return @intCast(self.vtx.items.len - 1);
    }

    /// Appends a triangle, fixing winding order so the result is always
    /// counter-clockwise (y going down) to avoid backface culling.
    /// Degenerate (near zero area) triangles are dropped.
    pub fn addTri(self: *FillSink, allocator: std.mem.Allocator, p0: u32, p1: u32, p2: u32) std.mem.Allocator.Error!void {
        const P0 = self.vtx.items[p0].pos;
        const P1 = self.vtx.items[p1].pos;
        const P2 = self.vtx.items[p2].pos;
        const cross = (P1.x - P0.x) * (P2.y - P0.y) - (P1.y - P0.y) * (P2.x - P0.x);
        if (@abs(cross) < 1e-8) return;
        if (cross <= 0) {
            try self.idx.appendSlice(allocator, &.{ @intCast(p0), @intCast(p1), @intCast(p2) });
        } else {
            try self.idx.appendSlice(allocator, &.{ @intCast(p0), @intCast(p2), @intCast(p1) });
        }
    }

    pub fn build(self: *FillSink, allocator: std.mem.Allocator) std.mem.Allocator.Error!Triangles {
        return .{
            .vertexes = try self.vtx.toOwnedSlice(allocator),
            .indices = try self.idx.toOwnedSlice(allocator),
            .bounds = self.bounds.toPoint(.{ .x = self.bounds.w, .y = self.bounds.h }),
        };
    }
};

pub fn closeEnough(a: Point.Physical, b: Point.Physical) bool {
    return @abs(a.x - b.x) < 1e-5 and @abs(a.y - b.y) < 1e-5;
}

pub fn fillInsideRule(winding: i32, rule: FillOptions.FillRule) bool {
    return switch (rule) {
        .nonzero => winding != 0,
        .evenodd => @mod(winding, 2) != 0,
    };
}

/// Generates triangles filling the shape described by `contours` according
/// to `opts.fill_rule`, resolving overlaps/holes/self-intersections.
///
/// Delegates to `earcut.fillTriangles` - measured faster on real icon data
/// than prior intersect-everything and trapezoidal-decomposition approaches.
pub fn fillTriangles(allocator: std.mem.Allocator, contours: []const Path, opts: FillOptions) std.mem.Allocator.Error!Triangles {
    return @import("earcut.zig").fillTriangles(allocator, contours, opts);
}

pub const FillBoundaryEdge = struct { from: Point.Physical, to: Point.Physical };

pub fn fillAddBoundaryPiece(
    list: *std.ArrayList(FillBoundaryEdge),
    allocator: std.mem.Allocator,
    p_top: Point.Physical,
    p_bot: Point.Physical,
    inside_pt: Point.Physical,
) std.mem.Allocator.Error!void {
    if (closeEnough(p_top, p_bot)) return;
    const d = p_bot.diff(p_top);
    const cross = d.x * (inside_pt.y - p_top.y) - d.y * (inside_pt.x - p_top.x);
    if (cross < 0) {
        try list.append(allocator, .{ .from = p_top, .to = p_bot });
    } else {
        try list.append(allocator, .{ .from = p_bot, .to = p_top });
    }
}

/// Chains boundary edge pieces (oriented so the filled region is always to
/// their left) into closed loops, then fades each loop to transparent using
/// the same averaged-normal offset technique as `fillConvexTriangles`.
pub fn fillAppendFade(
    sink: *FillSink,
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    boundary: []const FillBoundaryEdge,
    col: Color.PMA,
    fade: f32,
) std.mem.Allocator.Error!void {
    const used = try arena.alloc(bool, boundary.len);
    @memset(used, false);

    // Same centered-fade contract as fillConvexTriangles: half the fade
    // width is inside the true edge, half outside. The opaque interior
    // triangles were already emitted (by the caller) reaching all the way
    // to the true (un-inset) boundary, so pull those matching vertices
    // inward here to meet the fade band's inner edge - otherwise the band
    // just overlays already-opaque pixels and never actually fades on the
    // inside half, leaving the AA entirely outside the true edge.
    const inside_len = @min(0.5, fade / 2);

    for (boundary, 0..) |start_e, si| {
        if (used[si]) continue;
        used[si] = true;

        var loop_pts: std.ArrayList(Point.Physical) = .empty;
        try loop_pts.append(arena, start_e.from);
        const start_from = start_e.from;
        var cur_to = start_e.to;

        var guard: usize = 0;
        while (!closeEnough(cur_to, start_from) and guard <= boundary.len) : (guard += 1) {
            try loop_pts.append(arena, cur_to);
            var found = false;
            for (boundary, 0..) |be, bi| {
                if (used[bi]) continue;
                if (closeEnough(be.from, cur_to)) {
                    used[bi] = true;
                    cur_to = be.to;
                    found = true;
                    break;
                }
            }
            if (!found) break; // dangling piece (shouldn't happen); use partial loop
        }

        if (loop_pts.items.len < 3) continue;
        const loop = loop_pts.items;
        const n = loop.len;

        const inner_idx = try arena.alloc(u32, n);
        const outer_idx = try arena.alloc(u32, n);
        for (0..n) |i| {
            const aa = loop[(i + n - 1) % n];
            const bb = loop[i];
            const cc = loop[(i + 1) % n];
            const diffab = aa.diff(bb).normalize();
            const diffbc = bb.diff(cc).normalize();
            var norm: Point.Physical = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

            const inner_pos: Point.Physical = .{
                .x = bb.x - norm.x * inside_len,
                .y = bb.y - norm.y * inside_len,
            };
            for (sink.vtx.items) |*v| {
                if (std.meta.eql(v.col, col) and closeEnough(v.pos, bb)) v.pos = inner_pos;
            }

            inner_idx[i] = try sink.addVertex(allocator, .{ .pos = inner_pos, .col = col });

            const d2 = norm.x * norm.x + norm.y * norm.y;
            if (d2 > 0.000001) norm = norm.scale(1.0 / d2, Point.Physical);
            const l = norm.length();
            if (l > 2.0) norm = norm.scale(2.0 / l, Point.Physical);

            const outside_len = if (fade <= 1) fade / 2 else fade - 0.5;
            outer_idx[i] = try sink.addVertex(allocator, .{
                .pos = .{ .x = bb.x + norm.x * outside_len, .y = bb.y + norm.y * outside_len },
                .col = .transparent,
            });
        }

        for (0..n) |i| {
            const j = (i + 1) % n;
            try sink.addTri(allocator, inner_idx[i], outer_idx[i], inner_idx[j]);
            try sink.addTri(allocator, outer_idx[i], outer_idx[j], inner_idx[j]);
        }
    }
}

test fill {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    // donut: outer square CW(y-down), inner square hole (opposite winding)
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

    // sample point in the hole must not be covered by any (fully opaque) fill triangle
    const hole_center: Point.Physical = .{ .x = 50, .y = 50 };
    var i: usize = 0;
    while (i < triangles.indices.len) : (i += 3) {
        const v0 = triangles.vertexes[triangles.indices[i]];
        const v1 = triangles.vertexes[triangles.indices[i + 1]];
        const v2 = triangles.vertexes[triangles.indices[i + 2]];
        if (v0.col.a != 255 or v1.col.a != 255 or v2.col.a != 255) continue;
        try std.testing.expect(!pointInTriangle(hole_center, v0.pos, v1.pos, v2.pos));
    }

    // sample point solidly inside the ring must be covered
    const ring_pt: Point.Physical = .{ .x = 10, .y = 50 };
    var covered = false;
    i = 0;
    while (i < triangles.indices.len) : (i += 3) {
        const v0 = triangles.vertexes[triangles.indices[i]];
        const v1 = triangles.vertexes[triangles.indices[i + 1]];
        const v2 = triangles.vertexes[triangles.indices[i + 2]];
        if (v0.col.a != 255 or v1.col.a != 255 or v2.col.a != 255) continue;
        if (pointInTriangle(ring_pt, v0.pos, v1.pos, v2.pos)) covered = true;
    }
    try std.testing.expect(covered);
}

test "fill self-intersecting star" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    // 5 point star, drawn as a single contour that self-intersects near
    // the center (as bezier-flattened paths sometimes produce).
    const cx: f32 = 50;
    const cy: f32 = 50;
    const outer_r: f32 = 50;
    const inner_r: f32 = 20;
    var pts: [10]Point.Physical = undefined;
    for (0..10) |i| {
        const r: f32 = if (i % 2 == 0) outer_r else inner_r;
        const a: f32 = @as(f32, @floatFromInt(i)) * math.pi / 5.0 - math.pi / 2.0;
        pts[i] = .{ .x = cx + r * @cos(a), .y = cy + r * @sin(a) };
    }
    const star: Path = .{ .points = &pts };

    var triangles = try fillTriangles(std.testing.allocator, &.{star}, .{ .color = Color.white, .fade = 1.0 });
    defer triangles.deinit(std.testing.allocator);

    try std.testing.expect(triangles.vertexes.len > 0);
    try std.testing.expect(triangles.indices.len > 0);

    // center of star must be filled
    var covered = false;
    var i: usize = 0;
    while (i < triangles.indices.len) : (i += 3) {
        const v0 = triangles.vertexes[triangles.indices[i]];
        const v1 = triangles.vertexes[triangles.indices[i + 1]];
        const v2 = triangles.vertexes[triangles.indices[i + 2]];
        if (v0.col.a != 255 or v1.col.a != 255 or v2.col.a != 255) continue;
        if (pointInTriangle(.{ .x = cx, .y = cy }, v0.pos, v1.pos, v2.pos)) covered = true;
    }
    try std.testing.expect(covered);
}

fn pointInTriangle(p: Point.Physical, a: Point.Physical, b: Point.Physical, c: Point.Physical) bool {
    const d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y);
    const d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y);
    const d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y);
    const has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0);
    const has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0);
    return !(has_neg and has_pos);
}

const std = @import("std");
const dvui = @import("dvui.zig");

const math = dvui.math;
const Rect = dvui.Rect;
const Corner = dvui.Corner;
const CornerRect = dvui.CornerRect;
const Point = dvui.Point;
const Color = dvui.Color;
const Triangles = dvui.Triangles;
const Vertex = dvui.Vertex;

test {
    @import("std").testing.refAllDecls(@This());
}
