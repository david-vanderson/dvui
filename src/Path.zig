//! A shape made of lines, circular arcs and Béziers that can later be rendered to the screen.
//!
//! Build one with `Path.Builder`. svg2tvg's `mesh` module turns it into
//! triangles with a coverage per vertex, dvui colors them.

/// The first point, null for an empty path.
start: ?Point.Physical = null,
/// Every segment starts where the previous one ends.
segments: []const Segment = &.{},

pub const Path = @This();
pub const Segment = svg2tvg_mesh.Segment;

/// A builder with an ArrayList to add segments to.
///
/// If a OutOfMemory error occurs, the builder with log it and ignore it,
/// meaning that you would get an incomplete path in that case. For rendering,
/// this will produce an incorrect output but will largely tend to work.
///
/// `Builder.deinit` should always be called as `Builder.build` does not give ownership
/// of the memory
pub const Builder = struct {
    start: ?Point.Physical = null,
    segments: std.array_list.Managed(Segment),
    oom_error_occurred: bool = false,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .segments = .init(allocator) };
    }

    pub fn deinit(path: *Builder) void {
        path.segments.deinit();
    }

    /// Returns a non-owned `Path`. Calling `deinit` on the `Builder` is still required to free memory
    pub fn build(path: *Builder) Path {
        if (path.oom_error_occurred) {
            // This does not allow for error return traces, but
            // reduces spam caused by logs on every call to `addPoint`
            dvui.logError(@src(), std.mem.Allocator.Error.OutOfMemory, "Path encountered error and is likely incomplete", .{});
        }
        return .{ .start = path.start, .segments = path.segments.items };
    }

    /// Add a point to the path
    pub fn addPoint(path: *Builder, p: Point.Physical) void {
        if (path.start == null) {
            path.start = p;
            return;
        }
        path.addSegment(.{ .line = .{ p.x, p.y } });
    }

    fn addSegment(path: *Builder, segment: Segment) void {
        std.debug.assert(path.start != null);
        path.segments.append(segment) catch {
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

    fn addCorner(
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
                path.addArc(.{ .x = origin_x + offset_x, .y = origin_y + offset_y }, r_cur.x, pi_start, pi_end);
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

    /// Add an arc to path: a line to its start, then the arc.
    ///
    /// `start` >= `end`, both are radians that go clockwise from the positive x axis.
    ///
    /// The points lie on a fixed angle grid within 0.5 physical pixels of
    /// the circle, which prevents shimmering on things like a spinner. An
    /// end point within half a pixel of the next point is left out.
    pub fn addArc(path: *Builder, center: Point.Physical, radius: f32, start: f32, end: f32) void {
        if (radius == 0) {
            path.addPoint(center);
            return;
        }
        if (path.start == null) path.start = .{ .x = center.x + radius * @cos(start), .y = center.y + radius * @sin(start) };
        path.addSegment(.{ .circle_arc = .{ .center = .{ center.x, center.y }, .radius = radius, .start_angle = start, .end_angle = end } });
    }

    /// Add a quadratic bezier curve to path.
    ///
    /// `p0`, `control`, `p1` are all explicit (no implicit "current point" -
    /// consistent with `addArc` taking full explicit geometry). `p0` is
    /// added, then the curve ending with `p1`.
    pub fn addQuadBezier(path: *Builder, p0: Point.Physical, control: Point.Physical, p1: Point.Physical) void {
        path.addPoint(p0);
        path.addSegment(.{ .quadratic = .{ .control = .{ control.x, control.y }, .end = .{ p1.x, p1.y } } });
    }

    /// Add a cubic bezier curve to path.
    ///
    /// `p0`, `c1`, `c2`, `p1` are all explicit (no implicit "current point" -
    /// consistent with `addArc`/`addQuadBezier`). `p0` is added, then the
    /// curve ending with `p1`.
    pub fn addCubicBezier(path: *Builder, p0: Point.Physical, c1: Point.Physical, c2: Point.Physical, p1: Point.Physical) void {
        path.addPoint(p0);
        path.addSegment(.{ .cubic = .{ .control_0 = .{ c1.x, c1.y }, .control_1 = .{ c2.x, c2.y }, .end = .{ p1.x, p1.y } } });
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
    try std.testing.expectEqual(3, path.segments.len);
    var triangles = try path.fillConvexTriangles(std.testing.allocator, .{ .color = .{ .color = Color.white } });
    defer triangles.deinit(std.testing.allocator);
    try std.testing.expectApproxEqRel(10, triangles.bounds.x, 0.05);
    try std.testing.expectApproxEqRel(20, triangles.bounds.y, 0.05);
    try std.testing.expectApproxEqRel(30, triangles.bounds.w, 0.05);
    try std.testing.expectApproxEqRel(40, triangles.bounds.h, 0.05);
}

pub fn dupe(path: Path, allocator: std.mem.Allocator) std.mem.Allocator.Error!Path {
    return .{ .start = path.start, .segments = try allocator.dupe(Segment, path.segments) };
}

fn contour(path: Path, closed: bool) ?svg2tvg_mesh.Contour {
    const start = path.start orelse return null;
    return .{ .start = .{ start.x, start.y }, .segments = path.segments, .closed = closed };
}

/// Bounding box of the points and control points, arcs as their whole circle.
fn controlBounds(path: Path) Rect.Physical {
    const start = path.start.?;
    var min: [2]f32 = .{ start.x, start.y };
    var max = min;
    for (path.segments) |segment| {
        var points: [3][2]f32 = undefined;
        const used: []const [2]f32 = switch (segment) {
            .line => |end| end: {
                points[0] = end;
                break :end points[0..1];
            },
            .quadratic => |curve| curve: {
                points[0..2].* = .{ curve.control, curve.end };
                break :curve points[0..2];
            },
            .cubic => |curve| curve: {
                points = .{ curve.control_0, curve.control_1, curve.end };
                break :curve points[0..3];
            },
            .arc => |arc| arc: {
                points[0] = arc.end;
                break :arc points[0..1];
            },
            .circle_arc => |arc| arc: {
                points[0..2].* = .{ .{ arc.center[0] - arc.radius, arc.center[1] - arc.radius }, .{ arc.center[0] + arc.radius, arc.center[1] + arc.radius } };
                break :arc points[0..2];
            },
        };
        for (used) |point| {
            min = .{ @min(min[0], point[0]), @min(min[1], point[1]) };
            max = .{ @max(max[0], point[0]), @max(max[1], point[1]) };
        }
    }
    return .{ .x = min[0], .y = min[1], .w = max[0] - min[0], .h = max[1] - min[1] };
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
    if (path.start == null) {
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
pub fn fillConvexTriangles(path: Path, allocator: std.mem.Allocator, opts: FillConvexOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    const start = path.start orelse return .empty;
    const center: ?[2]f32 = if (opts.center) |c| .{ c.x - @floor(start.x), c.y - @floor(start.y) } else null;
    return cachedTriangles(allocator, .fill_convex, &.{path}, opts.color, .{ opts.fade, center }, buildFillConvexTriangles, .{ path, allocator, opts });
}

fn buildFillConvexTriangles(path: Path, allocator: std.mem.Allocator, opts: FillConvexOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    const outline = path.contour(true) orelse return .empty;
    var options: svg2tvg_mesh.ConvexOptions = .{
        .fade = opts.fade,
        .center = if (opts.center) |center| .{ center.x, center.y } else null,
    };
    if (opts.center == null and opts.color == .gradient and opts.color.gradient == .radial) {
        // A radial gradient needs a vertex at the shape's actual center so it
        // samples the base color there; without it the fan pivots on
        // a corner and the gradient looks lopsided.
        const center = path.controlBounds().center();
        options.center = .{ center.x, center.y };
    }
    const size = svg2tvg_mesh.convexSize(outline, options);
    if (size.indices == 0) return .empty;
    if (size.vertices > std.math.maxInt(Vertex.Index)) {
        dvui.log.err("fill skipped, {d} vertexes exceed the vertex index type", .{size.vertices});
        return .empty;
    }

    var builder: Triangles.Builder = try .init(allocator, size.vertices, size.indices);
    errdefer builder.deinit(allocator);
    // One allocation for the three buffers, all of 4 byte words.
    const words = try allocator.alloc(u32, size.vertices * 3 + size.indices);
    defer allocator.free(words);
    const positions: []svg2tvg_mesh.Point = @ptrCast(words[0 .. size.vertices * 2]);
    const coverages: []f32 = @ptrCast(words[size.vertices * 2 ..][0..size.vertices]);
    const indices = words[size.vertices * 3 ..];
    const written = svg2tvg_mesh.fillConvex(outline, options, .{ .positions = positions, .coverages = coverages, .indices = indices });
    if (written.indices == 0) {
        builder.deinit(allocator);
        return .empty;
    }
    return colorMesh(&builder, .{
        .positions = positions[0..written.vertices],
        .coverages = coverages[0..written.vertices],
        .indices = indices[0..written.indices],
    }, opts.color);
}

pub const StrokeOptions = struct {
    /// true => Render this after normal drawing on that subwindow.  Useful for
    /// debugging on cross-gui drawing.
    after: bool = false,
    thickness: f32,
    color: ColorOrGradient,
    /// true => Stroke includes from path end to path start.
    closed: bool = false,
    /// Ends of an open path. A path of one point draws a disc for `.round`
    /// and a square for `.square`, both `thickness` wide. If every path is a
    /// single point, `.none` draws like `.round` and logs a debug message.
    endcap_style: EndCapStyle = .none,
    /// How consecutive segments meet. A miter longer than 4 times
    /// `thickness` becomes a bevel.
    join: Join = .miter,
    /// Size (physical pixels) of fade to transparent on both sides, 0 for
    /// hard edges. Up to 1 it is centered on the edge, above 1 it starts a
    /// half-pixel inside and the rest outside.
    ///
    /// Above 1 every stroke takes the direct strip, translucent or not:
    /// joins, crossings and the fade at sharp corners overlap, which shows
    /// with translucent color.
    fade: f32 = 1,

    pub const EndCapStyle = enum {
        none,
        /// Extends the end by half of `thickness`.
        square,
        round,
    };

    pub const Join = svg2tvg_mesh.Join;
};

/// Stroke `paths` as one shape.  See `Rect.stroke`.
///
/// A translucent color covers every pixel once, also where the paths overlap.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn stroke(paths: []const Path, opts: StrokeOptions) void {
    if (paths.len == 0) return;

    const cw = dvui.currentWindow();

    if (opts.after or !cw.render_target.rendering) {
        var new_opts = opts;
        const new_paths = dupeContours(paths, cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        new_opts.color = opts.color.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate gradient for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathStroke = .{ .paths = new_paths, .opts = new_opts } }, opts.after);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = strokeTriangles(cw.lifo(), paths, options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, triangles.texture) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{opts});
        return;
    };
}

/// Generates triangles to stroke `paths` as one shape.
///
/// Vertexes will have unset uv and color is alpha multiplied opts.color
/// fading to transparent at the edge. Opaque strokes take a direct strip,
/// translucent ones an outline that covers every pixel once.
pub fn strokeTriangles(allocator: std.mem.Allocator, paths: []const Path, opts: StrokeOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    if (dvui.clipGet().empty()) {
        return .empty;
    }
    return cachedTriangles(allocator, .stroke, paths, opts.color, .{ opts.thickness, opts.closed, opts.endcap_style, opts.join, opts.fade }, buildStrokeTriangles, .{ allocator, paths, opts });
}

fn buildStrokeTriangles(allocator: std.mem.Allocator, paths: []const Path, opts: StrokeOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    const scratch = scratchAllocator(allocator);
    const lines = try scratch.alloc(svg2tvg_mesh.Contour, paths.len);
    defer scratch.free(lines);
    var line_count: usize = 0;
    var single_point_count: usize = 0;
    for (paths) |path| {
        lines[line_count] = path.contour(opts.closed) orelse continue;
        line_count += 1;
        if (path.segments.len == 0) single_point_count += 1;
    }
    if (line_count == 0) return .empty;
    std.debug.assert(single_point_count <= line_count);
    var endcap_style = opts.endcap_style;
    if (endcap_style == .none and single_point_count == line_count) {
        dvui.log.debug("stroke of {d} single points with endcap_style .none, drawn as .round", .{single_point_count});
        endcap_style = .round;
    }
    const mesh = svg2tvg_mesh.stroke(scratch, lines[0..line_count], .{
        .width = opts.thickness,
        .join = opts.join,
        .cap = switch (endcap_style) {
            .none => .butt,
            .square => .square,
            .round => .round,
        },
        .fade = opts.fade,
        .translucent = isTranslucent(opts.color),
    }) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.InvalidInput, error.TooComplex => {
            dvui.log.err("stroke skipped, svg2tvg failed with {s} for {d} paths", .{ @errorName(err), paths.len });
            return .empty;
        },
    };
    defer mesh.deinit(scratch);
    return meshTriangles(allocator, mesh, opts.color);
}

/// The svg2tvg mesh is freed after the triangles are allocated, which breaks
/// the free order `Window.lifo` needs, so it goes to the frame arena.
fn scratchAllocator(allocator: std.mem.Allocator) std.mem.Allocator {
    const cw = dvui.current_window orelse return allocator;
    return cw.arena();
}

fn isTranslucent(color: ColorOrGradient) bool {
    switch (color) {
        .color => |c| return c.a < 255,
        .gradient => |gradient| switch (gradient) {
            inline else => |g| {
                if (g.alpha < 1) return true;
                for (g.stops) |stop| if (stop.color.a < 255) return true;
                return false;
            },
        },
    }
}

/// Colors a mesh from svg2tvg in physical pixels: every vertex gets its
/// coverage times `color`, a gradient then adds its texture and uv.
pub fn meshTriangles(allocator: std.mem.Allocator, mesh: svg2tvg_mesh.Mesh, color: ColorOrGradient) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    if (mesh.indices.len == 0) return .empty;
    if (mesh.positions.len > std.math.maxInt(Vertex.Index)) {
        dvui.log.err("mesh skipped, {d} vertexes exceed the vertex index type", .{mesh.positions.len});
        return .empty;
    }
    var builder: Triangles.Builder = try .init(allocator, mesh.positions.len, mesh.indices.len);
    errdefer builder.deinit(allocator);
    return colorMesh(&builder, mesh, color);
}

fn colorMesh(builder: *Triangles.Builder, mesh: svg2tvg_mesh.Mesh, color: ColorOrGradient) dvui.Backend.TextureError!Triangles {
    std.debug.assert(mesh.positions.len == mesh.coverages.len and mesh.indices.len % 3 == 0);
    const split = color.split();
    const col: Color.PMA = .fromColor(split.color);
    var min: @Vector(2, f32) = @splat(std.math.floatMax(f32));
    var max: @Vector(2, f32) = @splat(-std.math.floatMax(f32));
    const vertexes = builder.vertexes.addManyAsSliceAssumeCapacity(mesh.positions.len);
    for (vertexes, mesh.positions, mesh.coverages) |*vertex, position, coverage| {
        std.debug.assert(coverage >= 0 and coverage <= 1);
        min = @min(min, @as(@Vector(2, f32), position));
        max = @max(max, @as(@Vector(2, f32), position));
        const alpha: u8 = @intFromFloat(@round(coverage * 255));
        vertex.* = .{
            .pos = .{ .x = position[0], .y = position[1] },
            .col = switch (alpha) {
                255 => col,
                0 => .transparent,
                else => col.multiply(.{ .r = alpha, .g = alpha, .b = alpha, .a = alpha }),
            },
        };
    }
    builder.bounds = .{ .x = min[0], .y = min[1], .w = max[0], .h = max[1] };
    for (builder.indices.addManyAsSliceAssumeCapacity(mesh.indices.len), mesh.indices) |*target, index| target.* = @intCast(index);
    var triangles = builder.build();
    if (split.gradient) |g| triangles.texture = try g.apply(&triangles, triangles.bounds);
    return triangles;
}

pub const FillOptions = struct {
    color: ColorOrGradient,
    /// Size (physical pixels) of fade to transparent, 0 for hard edges. Up
    /// to 1 it is centered on the edge, above 1 it starts a half-pixel inside
    /// and the rest outside. A single convex contour fades exactly that wide,
    /// other fills fade 1 px for any `fade` up to 1.
    ///
    /// Above 1 a fill that is no single convex contour needs simple
    /// contours, nested contours alternate between fill and hole whatever
    /// `fill_rule` says, and at concave corners the fade overlaps itself,
    /// which shows with translucent color.
    fade: f32 = 1,
    fill_rule: FillRule = .nonzero,
    /// Tessellation budget shared with other fills, null gives this fill its own.
    work: ?*svg2tvg_mesh.Work = null,
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
/// sweep tessellator from svg2tvg. `opts.fade` fades to transparent at the
/// boundary.
///
/// Inputs the tessellator rejects are logged and produce no triangles.
pub fn fillTriangles(allocator: std.mem.Allocator, contours: []const Path, opts: FillOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    return cachedTriangles(allocator, .fill, contours, opts.color, .{ opts.fade, opts.fill_rule }, buildFillTriangles, .{ allocator, contours, opts });
}

fn buildFillTriangles(allocator: std.mem.Allocator, contours: []const Path, opts: FillOptions) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    const scratch = scratchAllocator(allocator);
    const mesh_contours = try scratch.alloc(svg2tvg_mesh.Contour, contours.len);
    defer scratch.free(mesh_contours);
    var contour_count: usize = 0;
    for (contours) |path| {
        mesh_contours[contour_count] = path.contour(true) orelse continue;
        contour_count += 1;
    }
    const mesh = svg2tvg_mesh.fill(scratch, mesh_contours[0..contour_count], .{
        .fill_rule = switch (opts.fill_rule) {
            .nonzero => .nonzero,
            .evenodd => .even_odd,
        },
        .fade = opts.fade,
        .work = opts.work,
    }) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.InvalidInput, error.TooComplex => {
            dvui.log.err("fill skipped, svg2tvg failed with {s} for {d} contours", .{ @errorName(err), contours.len });
            return .empty;
        },
    };
    defer mesh.deinit(scratch);
    return meshTriangles(allocator, mesh, opts.color);
}

/// Keeps the triangles of `fillConvex`, `fill` and `stroke` across frames.
///
/// A shape is stored when its key shows up in a second consecutive frame and
/// dropped after a frame without use, so a shape that changes every frame
/// only costs its key. The key holds the paths relative to the whole pixel
/// below the first start point, a hit at another whole pixel offset is
/// shifted. Gradients are rebuilt every frame.
pub const MeshCache = struct {
    entries: dvui.TrackingAutoHashMap(u64, Entry, .get_and_put, void) = .empty,
    frame: u64 = 0,
    stored_bytes: usize = 0,
    /// Upper bound for the stored triangles, 0 turns the cache off.
    max_bytes: usize = 4 * 1024 * 1024,

    pub const Kind = enum(u8) { fill_convex, fill, stroke };

    const Entry = struct {
        frame_seen: u64,
        origin: [2]f32,
        triangles: ?Triangles = null,
    };

    /// Drops every entry not used since the last `reset`. Call once per frame.
    pub fn reset(cache: *MeshCache, gpa: std.mem.Allocator) void {
        var it = cache.entries.iterator();
        while (it.next_resetting()) |kv| cache.free(gpa, kv.value);
        cache.frame += 1;
    }

    pub fn deinit(cache: *MeshCache, gpa: std.mem.Allocator) void {
        defer cache.* = undefined;
        var it = cache.entries.iterator();
        while (it.next()) |entry| cache.free(gpa, entry.value_ptr.*);
        std.debug.assert(cache.stored_bytes == 0);
        cache.entries.deinit(gpa);
    }

    fn free(cache: *MeshCache, gpa: std.mem.Allocator, entry: Entry) void {
        var triangles = entry.triangles orelse return;
        cache.stored_bytes -= byteSize(triangles);
        triangles.deinit(gpa);
    }

    fn byteSize(triangles: Triangles) usize {
        return triangles.vertexes.len * @sizeOf(Vertex) + triangles.indices.len * @sizeOf(Vertex.Index);
    }
};

fn cachedTriangles(
    allocator: std.mem.Allocator,
    kind: MeshCache.Kind,
    paths: []const Path,
    color: ColorOrGradient,
    geometry: anytype,
    comptime build: anytype,
    build_args: anytype,
) (std.mem.Allocator.Error || dvui.Backend.TextureError)!Triangles {
    const cw = dvui.current_window orelse return @call(.auto, build, build_args);
    const cache = &cw.path_mesh_cache;
    if (cache.max_bytes == 0 or color == .gradient) return @call(.auto, build, build_args);
    const first_start = for (paths) |path| {
        if (path.start) |start| break start;
    } else return @call(.auto, build, build_args);
    const origin: [2]f32 = .{ @floor(first_start.x), @floor(first_start.y) };

    var hasher: dvui.Hasher = .init(@backingInt(kind));
    hashPathsRelative(&hasher, paths, origin);
    dvui.render_tvg.hashValue(&hasher, geometry);
    hasher.update(std.mem.asBytes(&color.color));
    const key = hasher.final();

    const entry = cache.entries.getOrPut(cw.gpa, key) catch return @call(.auto, build, build_args);
    if (!entry.found_existing) {
        entry.value_ptr.* = .{ .frame_seen = cache.frame, .origin = origin };
        return @call(.auto, build, build_args);
    }
    if (entry.value_ptr.triangles) |stored| {
        var triangles = try stored.dupe(allocator);
        const shift_x = origin[0] - entry.value_ptr.origin[0];
        const shift_y = origin[1] - entry.value_ptr.origin[1];
        if (shift_x != 0 or shift_y != 0) {
            for (triangles.vertexes) |*vertex| {
                vertex.pos.x += shift_x;
                vertex.pos.y += shift_y;
            }
            triangles.bounds.x += shift_x;
            triangles.bounds.y += shift_y;
        }
        return triangles;
    }
    const seen_last_frame = entry.value_ptr.frame_seen != cache.frame;
    std.debug.assert(!seen_last_frame or entry.value_ptr.frame_seen + 1 == cache.frame);
    entry.value_ptr.frame_seen = cache.frame;
    const triangles = try @call(.auto, build, build_args);
    if (!seen_last_frame or triangles.vertexes.len == 0) return triangles;
    if (cache.stored_bytes + MeshCache.byteSize(triangles) > cache.max_bytes) return triangles;
    std.debug.assert(triangles.texture == null);
    entry.value_ptr.* = .{
        .frame_seen = cache.frame,
        .origin = origin,
        .triangles = triangles.dupe(cw.gpa) catch return triangles,
    };
    cache.stored_bytes += MeshCache.byteSize(triangles);
    return triangles;
}

fn hashPathsRelative(hasher: *dvui.Hasher, paths: []const Path, origin: [2]f32) void {
    const ox = origin[0];
    const oy = origin[1];
    // Few large updates, the hasher is slow on many small ones.
    var words: HashWords = .{ .hasher = hasher };
    for (paths) |path| {
        const start = path.start orelse {
            words.reserve(1).* = .{0};
            continue;
        };
        words.reserve(3).* = .{ bits(start.x - ox), bits(start.y - oy), @truncate(path.segments.len) };
        for (path.segments) |segment| {
            const tag: u32 = @backingInt(std.meta.activeTag(segment));
            switch (segment) {
                .line => |end| words.reserve(3).* = .{ tag, bits(end[0] - ox), bits(end[1] - oy) },
                .quadratic => |curve| words.reserve(5).* = .{ tag, bits(curve.control[0] - ox), bits(curve.control[1] - oy), bits(curve.end[0] - ox), bits(curve.end[1] - oy) },
                .cubic => |curve| words.reserve(7).* = .{ tag, bits(curve.control_0[0] - ox), bits(curve.control_0[1] - oy), bits(curve.control_1[0] - ox), bits(curve.control_1[1] - oy), bits(curve.end[0] - ox), bits(curve.end[1] - oy) },
                .arc => |arc| words.reserve(7).* = .{ tag, bits(arc.radius[0]), bits(arc.radius[1]), bits(arc.rotation), bits(arc.end[0] - ox), bits(arc.end[1] - oy), @as(u32, @intFromBool(arc.large_arc)) | @as(u32, @intFromBool(arc.sweep)) << 1 },
                .circle_arc => |arc| words.reserve(6).* = .{ tag, bits(arc.center[0] - ox), bits(arc.center[1] - oy), bits(arc.radius), bits(arc.start_angle), bits(arc.end_angle) },
            }
        }
    }
    words.flush();
}

const HashWords = struct {
    hasher: *dvui.Hasher,
    words: [256]u32 = undefined,
    len: usize = 0,

    fn reserve(buffer: *HashWords, comptime count: usize) *[count]u32 {
        if (buffer.len + count > buffer.words.len) buffer.flush();
        defer buffer.len += count;
        return buffer.words[buffer.len..][0..count];
    }

    fn flush(buffer: *HashWords) void {
        buffer.hasher.update(std.mem.sliceAsBytes(buffer.words[0..buffer.len]));
        buffer.len = 0;
    }
};

fn bits(value: f32) u32 {
    return @bitCast(value);
}

test fill {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    // donut: outer square CW(y-down), inner square hole (opposite winding)
    const outer: Path = .{ .start = .{ .x = 0, .y = 0 }, .segments = &.{
        .{ .line = .{ 0, 100 } },
        .{ .line = .{ 100, 100 } },
        .{ .line = .{ 100, 0 } },
    } };
    const hole: Path = .{ .start = .{ .x = 25, .y = 25 }, .segments = &.{
        .{ .line = .{ 75, 25 } },
        .{ .line = .{ 75, 75 } },
        .{ .line = .{ 25, 75 } },
    } };

    var triangles = try fillTriangles(std.testing.allocator, &.{ outer, hole }, .{ .color = .{ .color = Color.white } });
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

test "stroke translucent covers every pixel once" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const line: Path = .{ .start = .{ .x = 0, .y = 50 }, .segments = &.{
        .{ .line = .{ 40, 50 } },
        .{ .line = .{ 80, 45 } },
    } };
    const lifo = dvui.currentWindow().lifo();
    var triangles = try strokeTriangles(lifo, &.{line}, .{
        .thickness = 12,
        .color = .{ .color = .{ .r = 255, .g = 255, .b = 255, .a = 128 } },
        .fade = 0,
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

test "stroke translucent plus of two paths covers the crossing once" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const horizontal: Path = .{ .start = .{ .x = 10, .y = 50 }, .segments = &.{.{ .line = .{ 90, 50 } }} };
    const vertical: Path = .{ .start = .{ .x = 50, .y = 10 }, .segments = &.{.{ .line = .{ 50, 90 } }} };
    const lifo = dvui.currentWindow().lifo();
    var triangles = try strokeTriangles(lifo, &.{ horizontal, vertical }, .{
        .thickness = 10,
        .color = .{ .color = .{ .r = 255, .g = 255, .b = 255, .a = 128 } },
        .fade = 0,
    });
    defer triangles.deinit(lifo);

    try std.testing.expectEqual(1, opaqueCoverage(triangles, .{ .x = 50.25, .y = 50.25 }));
    try std.testing.expectEqual(1, opaqueCoverage(triangles, .{ .x = 20.25, .y = 50.25 }));
    try std.testing.expectEqual(1, opaqueCoverage(triangles, .{ .x = 50.25, .y = 80.25 }));
    try std.testing.expectEqual(0, opaqueCoverage(triangles, .{ .x = 30.25, .y = 30.25 }));
}

test "stroke single point with endcap none draws a disc" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const point: Path = .{ .start = .{ .x = 50, .y = 50 } };
    const lifo = dvui.currentWindow().lifo();
    var triangles = try strokeTriangles(lifo, &.{point}, .{
        .thickness = 20,
        .color = .{ .color = .{ .r = 255, .g = 255, .b = 255, .a = 128 } },
        .fade = 0,
    });
    defer triangles.deinit(lifo);

    try std.testing.expectEqual(1, opaqueCoverage(triangles, .{ .x = 50.25, .y = 51.25 }));
    try std.testing.expectEqual(1, opaqueCoverage(triangles, .{ .x = 58.75, .y = 50.25 }));
    try std.testing.expectEqual(0, opaqueCoverage(triangles, .{ .x = 58.75, .y = 58.75 }));
}

test "fill fade 0" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .start = .{ .x = 0, .y = 0 }, .segments = &.{
        .{ .line = .{ 0, 100 } },
        .{ .line = .{ 100, 100 } },
        .{ .line = .{ 100, 0 } },
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
    const outer: Path = .{ .start = .{ .x = 0, .y = 0 }, .segments = &.{
        .{ .line = .{ 0, 100 } },
        .{ .line = .{ 100, 100 } },
        .{ .line = .{ 100, 0 } },
    } };
    const hole: Path = .{ .start = .{ .x = 25, .y = 25 }, .segments = &.{
        .{ .line = .{ 75, 25 } },
        .{ .line = .{ 75, 75 } },
        .{ .line = .{ 25, 75 } },
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
    var segments: [9]Segment = undefined;
    for (&segments, pts[1..]) |*segment, point| segment.* = .{ .line = .{ point.x, point.y } };
    const star: Path = .{ .start = pts[0], .segments = &segments };

    var triangles = try fillTriangles(std.testing.allocator, &.{star}, .{ .color = .{ .color = Color.white } });
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
const svg2tvg_mesh = @import("svg2tvg").mesh;

test {
    @import("std").testing.refAllDecls(@This());
}

test "fillConvex fade lands outside for either winding" {
    const ccw: Path = .{ .start = .{ .x = 0, .y = 0 }, .segments = &.{
        .{ .line = .{ 0, 10 } },
        .{ .line = .{ 10, 10 } },
        .{ .line = .{ 10, 0 } },
    } };
    const cw: Path = .{ .start = .{ .x = 0, .y = 0 }, .segments = &.{
        .{ .line = .{ 10, 0 } },
        .{ .line = .{ 10, 10 } },
        .{ .line = .{ 0, 10 } },
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

fn testShape(segments: *[4]Segment, x: f32, y: f32) Path {
    segments.* = .{
        .{ .line = .{ x + 40, y } },
        .{ .quadratic = .{ .control = .{ x + 20, y + 15 }, .end = .{ x + 40, y + 30 } } },
        .{ .line = .{ x, y + 30 } },
        .{ .line = .{ x + 10, y + 15 } },
    };
    return .{ .start = .{ .x = x, .y = y }, .segments = segments };
}

fn testFill(path: Path, opts: FillOptions) !void {
    var triangles = try fillTriangles(std.testing.allocator, &.{path}, opts);
    triangles.deinit(std.testing.allocator);
}

test "MeshCache stores on the second consecutive frame and shifts hits" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();
    const cw = dvui.currentWindow();
    const cache = &cw.path_mesh_cache;
    const opts: FillOptions = .{ .color = .{ .color = .{ .r = 200, .g = 100, .b = 50, .a = 180 } } };
    var segments: [4]Segment = undefined;

    try testFill(testShape(&segments, 10.25, 20.5), opts);
    try testFill(testShape(&segments, 10.25, 20.5), opts);
    try std.testing.expectEqual(1, cache.entries.count());
    try std.testing.expectEqual(0, cache.stored_bytes);

    cache.reset(cw.gpa);
    try testFill(testShape(&segments, 10.25, 20.5), opts);
    const stored_bytes = cache.stored_bytes;
    try std.testing.expect(stored_bytes > 0);

    cache.reset(cw.gpa);
    const shifted = testShape(&segments, 13.25, 27.5);
    var hit = try fillTriangles(std.testing.allocator, &.{shifted}, opts);
    defer hit.deinit(std.testing.allocator);
    try std.testing.expectEqual(1, cache.entries.count());
    try std.testing.expectEqual(stored_bytes, cache.stored_bytes);

    var rebuilt = try buildFillTriangles(std.testing.allocator, &.{shifted}, opts);
    defer rebuilt.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(Vertex.Index, rebuilt.indices, hit.indices);
    try std.testing.expectEqual(rebuilt.vertexes.len, hit.vertexes.len);
    for (rebuilt.vertexes, hit.vertexes) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected.pos.x, actual.pos.x, 1e-4);
        try std.testing.expectApproxEqAbs(expected.pos.y, actual.pos.y, 1e-4);
        try std.testing.expectEqual(expected.col, actual.col);
    }
    try std.testing.expectApproxEqAbs(rebuilt.bounds.x, hit.bounds.x, 1e-4);
    try std.testing.expectApproxEqAbs(rebuilt.bounds.y, hit.bounds.y, 1e-4);
}

test "MeshCache drops entries unused for a frame" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();
    const cw = dvui.currentWindow();
    const cache = &cw.path_mesh_cache;
    const opts: FillOptions = .{ .color = .{ .color = Color.white } };
    var segments: [4]Segment = undefined;

    try testFill(testShape(&segments, 0, 0), opts);
    cache.reset(cw.gpa);
    try testFill(testShape(&segments, 0, 0), opts);
    try std.testing.expect(cache.stored_bytes > 0);
    cache.reset(cw.gpa);
    cache.reset(cw.gpa);
    try std.testing.expectEqual(0, cache.entries.count());
    try std.testing.expectEqual(0, cache.stored_bytes);

    for (0..5) |frame| {
        try testFill(testShape(&segments, 0.1 * @as(f32, @floatFromInt(frame)), 0), opts);
        cache.reset(cw.gpa);
        try std.testing.expect(cache.entries.count() <= 1);
        try std.testing.expectEqual(0, cache.stored_bytes);
    }
}

test "MeshCache respects max_bytes and skips gradients" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();
    const cw = dvui.currentWindow();
    const cache = &cw.path_mesh_cache;
    var segments: [4]Segment = undefined;

    cache.max_bytes = 1;
    for (0..3) |_| {
        try testFill(testShape(&segments, 0, 0), .{ .color = .{ .color = Color.white } });
        cache.reset(cw.gpa);
    }
    try std.testing.expectEqual(0, cache.stored_bytes);

    cache.max_bytes = 4 * 1024 * 1024;
    const stops: []const Gradient.Stop = &.{ .{ .color = Color.white, .offset = 0 }, .{ .color = Color.black, .offset = 1 } };
    for (0..3) |_| {
        try testFill(testShape(&segments, 0, 0), .{ .color = .{ .gradient = .{ .linear = .{ .stops = stops } } } });
        cache.reset(cw.gpa);
    }
    try std.testing.expectEqual(0, cache.entries.count());
}
