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
    /// added, then the curve is flattened with svg2tvg's flattener so each
    /// segment is within 0.5 physical-pixel deviation of the true curve,
    /// ending with `p1`.
    pub fn addQuadBezier(path: *Builder, p0: Point.Physical, control: Point.Physical, p1: Point.Physical) void {
        path.addBezier(&.{ p0, control, p1 });
    }

    /// Add line segments flattening a cubic bezier curve to path.
    ///
    /// `p0`, `c1`, `c2`, `p1` are all explicit (no implicit "current point" -
    /// consistent with `addArc`/`addQuadBezier`).  `p0` is added, then the
    /// curve is flattened with svg2tvg's flattener so each segment is within
    /// 0.5 physical-pixel deviation of the true curve, ending with `p1`.
    pub fn addCubicBezier(path: *Builder, p0: Point.Physical, c1: Point.Physical, c2: Point.Physical, p1: Point.Physical) void {
        path.addBezier(&.{ p0, c1, c2, p1 });
    }

    fn addBezier(path: *Builder, controls: []const Point.Physical) void {
        std.debug.assert(controls.len == 3 or controls.len == 4);
        path.addPoint(controls[0]);
        var tessellation_controls: [4]tessellation.tvg.Point = undefined;
        for (tessellation_controls[0..controls.len], controls) |*tessellation_control, control| {
            tessellation_control.* = .{ .x = control.x, .y = control.y };
        }
        const allocator = path.points.allocator;
        var flat: std.ArrayList(tessellation.tvg.Point) = .empty;
        defer flat.deinit(allocator);
        tessellation.arrangement.flattenBezier(allocator, tessellation_controls[0..controls.len], 0.5, (tessellation.Limits{}).max_points, &flat) catch |err| switch (err) {
            error.OutOfMemory => {
                path.oom_error_occurred = true;
                return;
            },
            error.TooComplex => {
                dvui.log.err("bezier skipped, flattening failed with {s}", .{@errorName(err)});
                return;
            },
        };
        for (flat.items) |point| path.addPoint(.{ .x = point.x, .y = point.y });
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
    var triangles = try path.fillConvexTriangles(std.testing.allocator, .{ .color = .{ .color = Color.white } });
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
    for ([_]f32{ 0.1, 0.25, 0.5, 0.75, 0.9 }) |t_value| {
        try std.testing.expect(distanceToPolyline(small.points.items, quadBezierPoint(p0, control, p1, t_value)) <= 0.51);
    }
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
    for ([_]f32{ 0.1, 0.25, 0.5, 0.75, 0.9 }) |t_value| {
        try std.testing.expect(distanceToPolyline(small.points.items, cubicBezierPoint(p0, c1, c2, p1, t_value)) <= 0.51);
    }
}

fn distanceToPolyline(points: []const Point.Physical, query: Point.Physical) f32 {
    std.debug.assert(points.len >= 2);
    var min_distance: f32 = std.math.floatMax(f32);
    for (points[0 .. points.len - 1], points[1..]) |segment_start, segment_end| {
        const segment = segment_end.diff(segment_start);
        const to_query = query.diff(segment_start);
        const segment_length_squared = segment.x * segment.x + segment.y * segment.y;
        const t_on_segment = if (segment_length_squared == 0) 0 else std.math.clamp((to_query.x * segment.x + to_query.y * segment.y) / segment_length_squared, 0, 1);
        const closest = segment_start.plus(segment.scale(t_on_segment, Point.Physical));
        min_distance = @min(min_distance, query.diff(closest).length());
    }
    return min_distance;
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
    /// Flat color, or a gradient drawn across the fill's bounding box. See
    /// `ColorOrGradient`.
    color: ColorOrGradient,

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
        var new_opts = opts;
        const new_path = path.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        new_opts.color = opts.color.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate gradient for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathFillConvex = .{ .path = new_path, .opts = new_opts } }, false);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = path.fillConvexTriangles(cw.lifo(), options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, triangles.texture) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{options});
        return;
    };
}

/// Generates triangles to fill path (must be convex).
///
/// Vertexes will have unset uv and color is alpha multiplied opts.color
/// fading to transparent at the edge if fade is > 0.
pub fn fillConvexTriangles(path: Path, allocator: std.mem.Allocator, opts_in: FillConvexOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    if (path.points.len < 3) {
        return .empty;
    }

    var opts = opts_in;
    const split = opts.color.split();
    if (opts.center == null and split.gradient != null and split.gradient.? == .radial) {
        // A radial gradient needs a vertex at the shape's actual center so it
        // samples the base color there; without it the fan pivots on
        // points[0] (a corner) and the gradient looks lopsided.
        var min = path.points[0];
        var max = path.points[0];
        for (path.points[1..]) |p| {
            min.x = @min(min.x, p.x);
            min.y = @min(min.y, p.y);
            max.x = @max(max.x, p.x);
            max.y = @max(max.y, p.y);
        }
        opts.center = .{ .x = (min.x + max.x) / 2, .y = (min.y + max.y) / 2 };
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

    const flat_col: Color.PMA = .fromColor(split.color);

    // Normals and triangle winding assume counter-clockwise (y going down).
    // Walk clockwise paths backwards so the fade lands outside the shape.
    var area: f32 = 0;
    for (path.points, 0..) |p, j| {
        const q = path.points[(j + 1) % path.points.len];
        area += p.x * q.y - q.x * p.y;
    }
    const n = path.points.len;
    const reversed = area > 0;

    var i: usize = 0;
    while (i < path.points.len) : (i += 1) {
        const ai: u16 = @intCast((i + path.points.len - 1) % path.points.len);
        const bi: u16 = @intCast(i % path.points.len);
        const ci: u16 = @intCast((i + 1) % path.points.len);
        const aa = path.points[if (reversed) n - 1 - ai else ai];
        const bb = path.points[if (reversed) n - 1 - bi else bi];
        const cc = path.points[if (reversed) n - 1 - ci else ci];

        const diffab = aa.diff(bb).normalize();
        const diffbc = bb.diff(cc).normalize();
        // average of normals on each side
        var norm: Point.Physical = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

        // inner vertex
        const inside_len = @min(0.5, opts.fade / 2);
        const vpos: Point.Physical = .{
            .x = bb.x - norm.x * inside_len,
            .y = bb.y - norm.y * inside_len,
        };
        builder.appendVertex(.{
            .pos = vpos,
            .col = flat_col,
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
            .col = flat_col,
        });
    }

    var triangles = builder.build();
    if (split.gradient) |g| triangles.texture = try g.apply(&triangles, triangles.bounds);
    return triangles;
}

pub const StrokeOptions = struct {
    /// true => Render this after normal drawing on that subwindow.  Useful for
    /// debugging on cross-gui drawing.
    after: bool = false,
    thickness: f32,
    color: ColorOrGradient,
    /// true => Stroke includes from path end to path start.
    closed: bool = false,
    endcap_style: EndCapStyle = .none,
    /// Size (physical pixels) of fade to transparent on each edge of the
    /// stroke. Default matches the previous hardcoded ~1px AA fringe.
    fade: f32 = 1.0,
    /// How consecutive segments meet. `.miter` is the historical mesh
    /// (icons, `Rect.stroke`, borders). `.strip` shares edge vertices so a
    /// translucent stroke composites once per pixel; corners may thin.
    join: Join = .miter,

    pub const EndCapStyle = enum {
        none,
        square,
    };

    pub const Join = enum {
        miter,
        strip,
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
        var new_opts = opts;
        const new_path = path.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        new_opts.color = opts.color.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate gradient for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathStroke = .{ .path = new_path, .opts = new_opts } }, opts.after);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = path.strokeTriangles(cw.lifo(), options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, triangles.texture) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{opts});
        return;
    };
}

/// Generates triangles to stroke path.
///
/// Vertexes will have unset uv and color is alpha multiplied opts.color
/// fading to transparent at the edge.
pub fn strokeTriangles(path: Path, allocator: std.mem.Allocator, opts: StrokeOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
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
        return tempPath.build().fillConvexTriangles(allocator, .{ .color = opts.color, .fade = opts.fade });
    }

    if (opts.join == .strip) {
        return strokeStripTriangles(path, allocator, opts);
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

    const split = opts.color.split();
    const col: Color.PMA = .fromColor(split.color);

    const aa_size = opts.fade;
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

    var triangles = builder.build();
    if (split.gradient) |g| triangles.texture = try g.apply(&triangles, triangles.bounds);
    return triangles;
}

fn strokeStripNormal(path: Path, i: usize, closed: bool) Point.Physical {
    const n = path.points.len;
    const bb = path.points[i];
    if (!closed and i == 0) {
        const t = path.points[1].diff(bb).normalize();
        return .{ .x = t.y, .y = -t.x };
    }
    if (!closed and i + 1 == n) {
        const t = bb.diff(path.points[n - 2]).normalize();
        return .{ .x = t.y, .y = -t.x };
    }
    const aa = path.points[(i + n - 1) % n];
    const cc = path.points[(i + 1) % n];
    const t_in = bb.diff(aa).normalize();
    const t_out = cc.diff(bb).normalize();
    const norm: Point.Physical = .{
        .x = t_in.y + t_out.y,
        .y = -t_in.x - t_out.x,
    };
    const d2 = norm.x * norm.x + norm.y * norm.y;
    if (d2 > 0.000001) {
        return norm.scale(1.0 / @sqrt(d2), Point.Physical);
    }
    return .{ .x = t_out.y, .y = -t_out.x };
}

fn strokeStripTriangles(path: Path, allocator: std.mem.Allocator, opts: StrokeOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    const n = path.points.len;
    const closed: bool = if (n == 2) false else opts.closed;
    const has_fade = opts.fade > 0;
    const vpp: usize = if (has_fade) 4 else 2;
    const segs: usize = if (closed) n else n - 1;
    const vtx_count = n * vpp;
    const idx_count = segs * @as(usize, if (has_fade) 18 else 6);

    var builder = try Triangles.Builder.init(allocator, vtx_count, idx_count);
    const split = opts.color.split();
    const col: Color.PMA = .fromColor(split.color);
    const half = opts.thickness * 0.5;
    const fade = opts.fade;

    for (0..n) |i| {
        const p = path.points[i];
        const nxny = strokeStripNormal(path, i, closed);
        if (has_fade) {
            builder.appendVertex(.{
                .pos = .{ .x = p.x - nxny.x * (half + fade), .y = p.y - nxny.y * (half + fade) },
                .col = .transparent,
            });
        }
        builder.appendVertex(.{
            .pos = .{ .x = p.x - nxny.x * half, .y = p.y - nxny.y * half },
            .col = col,
        });
        builder.appendVertex(.{
            .pos = .{ .x = p.x + nxny.x * half, .y = p.y + nxny.y * half },
            .col = col,
        });
        if (has_fade) {
            builder.appendVertex(.{
                .pos = .{ .x = p.x + nxny.x * (half + fade), .y = p.y + nxny.y * (half + fade) },
                .col = .transparent,
            });
        }
    }

    var s: usize = 0;
    while (s < segs) : (s += 1) {
        const a: u16 = @intCast(s * vpp);
        const c: u16 = @intCast(((s + 1) % n) * vpp);
        if (has_fade) {
            const fl0 = a;
            const l0 = a + 1;
            const r0 = a + 2;
            const fr0 = a + 3;
            const fl1 = c;
            const l1 = c + 1;
            const r1 = c + 2;
            const fr1 = c + 3;
            builder.appendTriangles(&.{
                l0,  r0,  r1,  l0,  r1,  l1,
                fl0, l0,  l1,  fl0, l1,  fl1,
                r0,  fr0, fr1, r0,  fr1, r1,
            });
        } else {
            builder.appendTriangles(&.{ a, a + 1, c + 1, a, c + 1, c });
        }
    }

    var triangles = builder.build();
    if (split.gradient) |g| triangles.texture = try g.apply(&triangles, triangles.bounds);
    return triangles;
}

pub const FillOptions = struct {
    color: ColorOrGradient,
    /// 1 adds a 1 physical pixel fade to transparent centered on the true
    /// (resolved) polygon boundary, 0 disables it. Other values are invalid.
    fade: f32 = 0.0,
    fill_rule: FillRule = .nonzero,
    /// Tessellation budget shared with other fills, null gives this fill its own.
    work: ?*tessellation.Work = null,
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
        var new_opts = opts;
        const new_contours = dupeContours(contours, cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        new_opts.color = opts.color.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate gradient for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathFill = .{ .contours = new_contours, .opts = new_opts } }, false);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = fillTriangles(cw.lifo(), contours, options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, triangles.texture) catch |err| {
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

/// Generates triangles filling the shape described by `contours` according
/// to `opts.fill_rule`, resolving overlaps/holes/self-intersections with the
/// sweep tessellator from svg2tvg. `opts.fade` 1 adds 1 px of anti-aliasing
/// centered on the boundary.
///
/// Inputs the tessellator rejects are logged and produce no triangles.
pub fn fillTriangles(allocator: std.mem.Allocator, contours: []const Path, opts: FillOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    std.debug.assert(opts.fade == 0 or opts.fade == 1);
    var point_count: usize = 0;
    for (contours) |contour| point_count += contour.points.len;
    const points = try allocator.alloc(tessellation.Point, point_count);
    defer allocator.free(points);
    const tessellation_contours = try allocator.alloc([]const tessellation.Point, contours.len);
    defer allocator.free(tessellation_contours);
    var start: usize = 0;
    for (contours, tessellation_contours) |contour, *tessellation_contour| {
        const converted = points[start..][0..contour.points.len];
        for (contour.points, converted) |point, *converted_point| converted_point.* = .{ point.x, point.y };
        tessellation_contour.* = converted;
        start += contour.points.len;
    }

    const mesh = tessellation.fill(allocator, tessellation_contours, .{
        .fill_rule = switch (opts.fill_rule) {
            .nonzero => .nonzero,
            .evenodd => .even_odd,
        },
        .anti_alias = opts.fade == 1,
        .work = opts.work,
    }) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.InvalidInput, error.TooComplex => {
            dvui.log.err("fill skipped, tessellation failed with {s} for {d} contours, {d} points", .{ @errorName(err), contours.len, point_count });
            return .empty;
        },
    };
    defer mesh.deinit(allocator);
    std.debug.assert(mesh.indices.len % 3 == 0);
    std.debug.assert(mesh.positions.len == mesh.coverages.len);
    if (mesh.indices.len == 0) return .empty;
    if (mesh.positions.len > std.math.maxInt(Vertex.Index)) {
        dvui.log.err("fill skipped, {d} vertexes exceed the vertex index type", .{mesh.positions.len});
        return .empty;
    }

    var builder: Triangles.Builder = try .init(allocator, mesh.positions.len, mesh.indices.len);
    errdefer builder.deinit(allocator);
    const col: Color.PMA = .fromColor(opts.color.split().color);
    for (mesh.positions, mesh.coverages) |position, coverage| {
        std.debug.assert(coverage >= 0 and coverage <= 1);
        const alpha: u8 = @intFromFloat(@round(coverage * 255));
        builder.appendVertex(.{
            .pos = .{ .x = position[0], .y = position[1] },
            .col = col.multiply(.{ .r = alpha, .g = alpha, .b = alpha, .a = alpha }),
        });
    }
    var index: usize = 0;
    while (index < mesh.indices.len) : (index += 3) {
        const triangle = mesh.indices[index..][0..3];
        // The tessellator winds the other way round than dvui (y down).
        builder.appendTriangles(&[3]Vertex.Index{ @intCast(triangle[0]), @intCast(triangle[2]), @intCast(triangle[1]) });
    }
    var triangles = builder.build();
    if (opts.color.split().gradient) |g| triangles.texture = try g.apply(&triangles, triangles.bounds);
    return triangles;
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

    var triangles = try fillTriangles(std.testing.allocator, &.{ outer, hole }, .{ .color = .{ .color = Color.white }, .fade = 1.0 });
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

test "stroke miter default vtx/idx counts" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const line: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 50, .y = 0 },
        .{ .x = 100, .y = 0 },
    } };
    const lifo = dvui.currentWindow().lifo();
    var triangles = try line.strokeTriangles(lifo, .{
        .thickness = 4,
        .color = .{ .color = Color.white },
    });
    defer triangles.deinit(lifo);

    try std.testing.expectEqual(@as(usize, 16), triangles.vertexes.len);
    try std.testing.expectEqual(@as(usize, 60), triangles.indices.len);
}

test "stroke strip two-point line" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const line: Path = .{ .points = &.{
        .{ .x = 0, .y = 50 },
        .{ .x = 100, .y = 50 },
    } };
    const lifo = dvui.currentWindow().lifo();

    {
        var triangles = try line.strokeTriangles(lifo, .{
            .thickness = 10,
            .color = .{ .color = Color.white },
            .fade = 0,
            .join = .strip,
        });
        defer triangles.deinit(lifo);
        try std.testing.expectEqual(@as(usize, 4), triangles.vertexes.len);
        try std.testing.expectEqual(@as(usize, 6), triangles.indices.len);
    }

    {
        var triangles = try line.strokeTriangles(lifo, .{
            .thickness = 10,
            .color = .{ .color = Color.white },
            .fade = 1,
            .join = .strip,
        });
        defer triangles.deinit(lifo);
        try std.testing.expectEqual(@as(usize, 8), triangles.vertexes.len);
        try std.testing.expectEqual(@as(usize, 18), triangles.indices.len);
    }
}

test "stroke strip translucent has no overlapping opaque coverage" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const line: Path = .{ .points = &.{
        .{ .x = 0, .y = 50 },
        .{ .x = 40, .y = 50 },
        .{ .x = 80, .y = 45 },
    } };
    const lifo = dvui.currentWindow().lifo();
    var triangles = try line.strokeTriangles(lifo, .{
        .thickness = 12,
        .color = .{ .color = .{ .r = 255, .g = 255, .b = 255, .a = 128 } },
        .fade = 0,
        .join = .strip,
    });
    defer triangles.deinit(lifo);

    var covered = false;
    var y: f32 = 44;
    while (y <= 56) : (y += 0.5) {
        var x: f32 = 36;
        while (x <= 44) : (x += 0.5) {
            const p: Point.Physical = .{ .x = x, .y = y };
            const n = opaqueCoverage(triangles, p);
            try std.testing.expect(n <= 1);
            if (n == 1) covered = true;
        }
    }
    try std.testing.expect(covered);
}

test "stroke strip closed wraps" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
        .{ .x = 100, .y = 100 },
        .{ .x = 0, .y = 100 },
    } };
    const lifo = dvui.currentWindow().lifo();
    var triangles = try square.strokeTriangles(lifo, .{
        .thickness = 8,
        .color = .{ .color = Color.white },
        .closed = true,
        .fade = 0,
        .join = .strip,
    });
    defer triangles.deinit(lifo);

    try std.testing.expectEqual(@as(usize, 8), triangles.vertexes.len);
    try std.testing.expectEqual(@as(usize, 24), triangles.indices.len);

    var wrapped = false;
    var i: usize = 0;
    while (i < triangles.indices.len) : (i += 3) {
        var uses0 = false;
        var uses_last = false;
        for (0..3) |k| {
            const idx = triangles.indices[i + k];
            if (idx < 2) uses0 = true;
            if (idx >= 6) uses_last = true;
        }
        if (uses0 and uses_last) wrapped = true;
    }
    try std.testing.expect(wrapped);
}

test "stroke strip gradient" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const line: Path = .{ .points = &.{
        .{ .x = 0, .y = 50 },
        .{ .x = 100, .y = 50 },
    } };

    const left_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const right_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    const lifo = dvui.currentWindow().lifo();
    var triangles = try line.strokeTriangles(lifo, .{
        .thickness = 5,
        .join = .strip,
        .color = .{ .gradient = .{ .linear = .{ .stops = &.{ .{ .color = left_color, .offset = 0 }, .{ .color = right_color, .offset = 1 } }, .angle_degrees = 0 } } },
    });
    defer triangles.deinit(lifo);

    try std.testing.expect(triangles.texture != null);
    var saw_left = false;
    var saw_right = false;
    for (triangles.vertexes) |v| {
        if (v.col.a != 255) continue;
        if (v.pos.x < 1) {
            try std.testing.expect(v.uv[0] < 0.5);
            saw_left = true;
        } else if (v.pos.x > 99) {
            try std.testing.expect(v.uv[0] > 0.5);
            saw_right = true;
        }
    }
    try std.testing.expect(saw_left and saw_right);
}

test "fill fade 0" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };

    var triangles = try fillTriangles(std.testing.allocator, &.{square}, .{ .color = .{ .color = Color.white }, .fade = 0 });
    defer triangles.deinit(std.testing.allocator);

    try std.testing.expect(triangles.vertexes.len > 0);
    for (triangles.vertexes) |v| {
        try std.testing.expectEqual(@as(u8, 255), v.col.a);
    }

    var covered = false;
    var i: usize = 0;
    while (i < triangles.indices.len) : (i += 3) {
        const v0 = triangles.vertexes[triangles.indices[i]];
        const v1 = triangles.vertexes[triangles.indices[i + 1]];
        const v2 = triangles.vertexes[triangles.indices[i + 2]];
        if (pointInTriangle(.{ .x = 50, .y = 50 }, v0.pos, v1.pos, v2.pos)) covered = true;
    }
    try std.testing.expect(covered);
}

test "fill gradient" {
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

    const left_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const right_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try fillTriangles(std.testing.allocator, &.{ outer, hole }, .{
        .color = .{ .gradient = .{ .linear = .{ .stops = &.{ .{ .color = left_color, .offset = 0 }, .{ .color = right_color, .offset = 1 } }, .angle_degrees = 0 } } },
    });
    defer triangles.deinit(std.testing.allocator);

    try std.testing.expect(triangles.texture != null);
    for (triangles.vertexes) |v| {
        if (v.col.a != 255) continue; // skip aa-fade/hole vertexes
        if (v.pos.x < 1) {
            try std.testing.expect(v.uv[0] < 0.5);
        } else if (v.pos.x > 99) {
            try std.testing.expect(v.uv[0] > 0.5);
        }
    }
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

    var triangles = try fillTriangles(std.testing.allocator, &.{star}, .{ .color = .{ .color = Color.white }, .fade = 1.0 });
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

fn pointInTriangleStrict(p: Point.Physical, a: Point.Physical, b: Point.Physical, c: Point.Physical) bool {
    const d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y);
    const d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y);
    const d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y);
    const eps: f32 = 1e-3;
    const has_neg = (d1 < -eps) or (d2 < -eps) or (d3 < -eps);
    const has_pos = (d1 > eps) or (d2 > eps) or (d3 > eps);
    if (has_neg and has_pos) return false;
    return (@abs(d1) > eps) and (@abs(d2) > eps) and (@abs(d3) > eps);
}

fn opaqueCoverage(triangles: Triangles, p: Point.Physical) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < triangles.indices.len) : (i += 3) {
        const v0 = triangles.vertexes[triangles.indices[i]];
        const v1 = triangles.vertexes[triangles.indices[i + 1]];
        const v2 = triangles.vertexes[triangles.indices[i + 2]];
        if (v0.col.a == 0 or v1.col.a == 0 or v2.col.a == 0) continue;
        if (pointInTriangleStrict(p, v0.pos, v1.pos, v2.pos)) count += 1;
    }
    return count;
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
const Gradient = dvui.Gradient;
const ColorOrGradient = dvui.ColorOrGradient;
const tessellation = @import("svg2tvg").tessellation;

test {
    @import("std").testing.refAllDecls(@This());
}

test "fillConvex fade lands outside for either winding" {
    const ccw: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 10 },
        .{ .x = 10, .y = 10 },
        .{ .x = 10, .y = 0 },
    } };
    const cw: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 10, .y = 10 },
        .{ .x = 0, .y = 10 },
    } };
    for ([_]Path{ ccw, cw }) |p| {
        var triangles = try p.fillConvexTriangles(std.testing.allocator, .{ .color = .{ .color = Color.white }, .fade = 1.0 });
        defer triangles.deinit(std.testing.allocator);
        for (triangles.vertexes) |v| {
            const inside = v.pos.x > 0 and v.pos.x < 10 and v.pos.y > 0 and v.pos.y < 10;
            try std.testing.expect(inside == (v.col.a != 0));
        }
    }
}
