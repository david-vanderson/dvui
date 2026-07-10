//! TVG (TinyVG) icon rendering.
//!
//! Parses a TVG byte stream and emits `dvui.Triangles` built from
//! `dvui.Path.fillTriangles` / `dvui.Path.fillConvexTriangles` /
//! `dvui.Path.strokeTriangles` - i.e. the same AA'd polygon-fill and
//! bezier-flattening machinery every other widget uses. No raster
//! intermediate, no bespoke triangulator: concave fills and fills with
//! holes go through `Path.fillTriangles` (earcut-backed), which resolves
//! overlaps/holes/self-intersections and gets real edge AA for free.
//!
//! Meshes are authored once at an integer pixel height and cached in
//! `Window.icon_mesh_cache` (see `renderIcon`), then replayed
//! scaled+translated every frame.

/// Render options for a TVG render.
pub const RenderOptions = struct {
    /// If set, overrides every flat-fill / stroke color.  Gradients are
    /// flattened to a single flat color when an override is active.
    color_override: ?Color = null,
    /// If set, overrides only fill colors (does not affect strokes).
    fill_color_override: ?Color = null,
    /// If set, overrides only stroke colors (does not affect fills).
    stroke_color_override: ?Color = null,
    /// If set, overrides the stroke width for all stroked paths.
    stroke_width_override: ?f32 = null,
    /// When true, all fill operations are skipped (only strokes are drawn).
    disable_fill: bool = false,
    /// Preserve TVG aspect ratio inside `rect` (letterbox).  When false the
    /// icon is stretched to fill the rect.
    keep_aspect: bool = true,
    /// Edge feather (physical px) for anti-aliasing of flat-colored fills
    /// and stroke caps/joins.  0 disables fill AA - sharp edges, useful for
    /// pixel-aligned UI strokes.  Gradient fills are never AA'd (see
    /// `fillContoursPhysical`).
    fade: f32 = 1.0,
};

/// Caller-owned accumulator that collects ALL triangles for a TVG render
/// (fills, stroke bands, round-join/cap discs) into one combined mesh, so
/// it can be cached once and replayed every frame with
/// `dvui.renderTriangles` instead of regenerating.
pub const MeshBuilder = struct {
    /// Allocator used to grow `vtx`/`idx`.  Stays with the builder so
    /// cached meshes can outlive the original render call.
    alloc: std.mem.Allocator,
    vtx: std.ArrayList(Vertex) = .empty,
    idx: std.ArrayList(Vertex.Index) = .empty,
    bounds_min_x: f32 = math.floatMax(f32),
    bounds_min_y: f32 = math.floatMax(f32),
    bounds_max_x: f32 = -math.floatMax(f32),
    bounds_max_y: f32 = -math.floatMax(f32),

    pub fn init(alloc: std.mem.Allocator) MeshBuilder {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *MeshBuilder) void {
        self.vtx.deinit(self.alloc);
        self.idx.deinit(self.alloc);
    }

    /// Append another mesh's vertices/indices into this one, rebasing
    /// indices by the current vertex count.  Borrows `src` - caller still
    /// owns and must free it.
    fn appendMesh(self: *MeshBuilder, src: Triangles) !void {
        if (src.vertexes.len == 0 or src.indices.len == 0) return;
        const base: Vertex.Index = @intCast(self.vtx.items.len);
        try self.vtx.appendSlice(self.alloc, src.vertexes);
        try self.idx.ensureUnusedCapacity(self.alloc, src.indices.len);
        for (src.indices) |i| self.idx.appendAssumeCapacity(base + i);
        for (src.vertexes) |v| {
            if (v.pos.x < self.bounds_min_x) self.bounds_min_x = v.pos.x;
            if (v.pos.y < self.bounds_min_y) self.bounds_min_y = v.pos.y;
            if (v.pos.x > self.bounds_max_x) self.bounds_max_x = v.pos.x;
            if (v.pos.y > self.bounds_max_y) self.bounds_max_y = v.pos.y;
        }
    }

    /// Borrowed view of the accumulated geometry as a `dvui.Triangles`.
    pub fn toTriangles(self: *const MeshBuilder) Triangles {
        const empty_bounds = self.vtx.items.len == 0;
        return .{
            .vertexes = self.vtx.items,
            .indices = self.idx.items,
            .bounds = if (empty_bounds) .{} else .{
                .x = self.bounds_min_x,
                .y = self.bounds_min_y,
                .w = self.bounds_max_x - self.bounds_min_x,
                .h = self.bounds_max_y - self.bounds_min_y,
            },
        };
    }
};

/// Per-icon triangle-mesh cache.  Entries are keyed by a hash of the tvg
/// bytes pointer, authoring height, and icon render options; evicted if
/// not accessed since the previous `reset`.
pub const MeshCache = struct {
    cache: Storage = .empty,

    pub const Storage = dvui.TrackingAutoHashMap(u64, MeshBuilder, .get_and_put, void);

    pub fn get(self: *MeshCache, key: u64) ?MeshBuilder {
        return self.cache.get(key);
    }

    /// Add a mesh to the cache. Frees any mesh it replaces.
    pub fn add(self: *MeshCache, gpa: std.mem.Allocator, key: u64, mesh: MeshBuilder) std.mem.Allocator.Error!void {
        const prev = try self.cache.fetchPut(gpa, key, mesh);
        if (prev) |kv| {
            var m = kv.value;
            m.deinit();
        }
    }

    /// Frees every mesh that was not accessed since the last call to `reset`.
    pub fn reset(self: *MeshCache) void {
        var it = self.cache.iterator();
        while (it.next_resetting()) |kv| {
            var m = kv.value;
            m.deinit();
        }
    }

    pub fn deinit(self: *MeshCache, gpa: std.mem.Allocator) void {
        defer self.* = undefined;
        var it = self.cache.iterator();
        while (it.next()) |item| item.value_ptr.deinit();
        self.cache.deinit(gpa);
    }
};

/// Draws `tvg_bytes` scaled to fit `rs`, using `Window.icon_mesh_cache` to
/// avoid re-triangulating unchanged icons every frame.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: dvui.RectScale, opts: dvui.render.TextureOptions, icon_opts: dvui.IconRenderOptions) Backend.GenericError!void {
    if (rs.s == 0) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;

    // Ask for an integer size icon (used as the mesh authoring size).
    const ask_height = @ceil(rs.r.h);
    if (ask_height <= 0) return;

    var h = dvui.fnv.init();
    h.update(std.mem.asBytes(&tvg_bytes.ptr));
    h.update(std.mem.asBytes(&ask_height));
    h.update(std.mem.asBytes(&icon_opts));
    const hash = h.final();

    const cw = dvui.currentWindow();

    const mesh: MeshBuilder = cw.icon_mesh_cache.get(hash) orelse blk: {
        var mesh = MeshBuilder.init(cw.gpa);
        errdefer mesh.deinit();

        var scratch = std.heap.ArenaAllocator.init(cw.gpa);
        defer scratch.deinit();

        const local_rect: Rect = .{ .x = 0, .y = 0, .w = ask_height, .h = ask_height };
        const render_opts: RenderOptions = .{
            .fill_color_override = icon_opts.fill_color,
            .stroke_color_override = icon_opts.stroke_color,
            .stroke_width_override = icon_opts.stroke_width,
            .disable_fill = if (icon_opts.fill_color) |c| c.a == 0 else false,
            .keep_aspect = true,
            .fade = 1.0,
        };

        appendTvg(scratch.allocator(), &mesh, tvg_bytes, local_rect, render_opts) catch |err| {
            mesh.deinit();
            dvui.logError(@src(), err, "Could not build mesh from tvg file \"{s}\"", .{name});
            return;
        };

        cw.icon_mesh_cache.add(cw.gpa, hash, mesh) catch |err| {
            mesh.deinit();
            dvui.logError(@src(), err, "Could not cache mesh for icon \"{s}\"", .{name});
            return;
        };
        break :blk mesh;
    };

    if (mesh.idx.items.len == 0) return;

    // Dupe the cached (0,0)-anchored mesh into the per-frame arena, then
    // scale/translate from authoring size to `rs.r`.
    var tri = mesh.toTriangles().dupe(cw.lifo()) catch |err| {
        dvui.logError(@src(), err, "Could not dupe mesh for icon \"{s}\"", .{name});
        return;
    };
    defer tri.deinit(cw.lifo());

    const scale_f: f32 = rs.r.h / ask_height;
    const tx = rs.r.x;
    const ty = rs.r.y;
    for (tri.vertexes) |*v| {
        v.pos.x = v.pos.x * scale_f + tx;
        v.pos.y = v.pos.y * scale_f + ty;
    }
    tri.bounds.x = tri.bounds.x * scale_f + tx;
    tri.bounds.y = tri.bounds.y * scale_f + ty;
    tri.bounds.w *= scale_f;
    tri.bounds.h *= scale_f;

    if (opts.rotation != 0) {
        tri.rotate(rs.r.center(), opts.rotation);
    }

    tri.color(opts.colormod.opacity(cw.alpha));

    try dvui.renderTriangles(tri, null);
}

/// Walk a TVG byte stream and APPEND its triangles to `mesh`, anchored at
/// `rect`'s origin in physical pixels.  No submission happens - caller
/// decides when (and how many times) to draw the resulting mesh.
///
/// `scratch_alloc` is used for the parser and all transient triangle data;
/// pass an arena so it can be freed in bulk.  The persistent vertex/index
/// storage lives in `mesh.alloc`.
pub fn appendTvg(
    scratch_alloc: std.mem.Allocator,
    mesh: *MeshBuilder,
    tvg_bytes: []const u8,
    rect: Rect,
    opts: RenderOptions,
) !void {
    var fbs: std.Io.Reader = .fixed(tvg_bytes);
    var parser = try tvg.parse(scratch_alloc, &fbs);
    defer parser.deinit();

    const xf = Transform.fromRect(rect, @floatFromInt(parser.header.width), @floatFromInt(parser.header.height), opts.keep_aspect);

    while (try parser.next()) |cmd| {
        try renderCommand(scratch_alloc, mesh, parser.color_table, cmd, xf, opts);
    }
}

// ---------------------------------------------------------------------------
// Transform: TVG-space -> physical-pixel space
// ---------------------------------------------------------------------------

const Transform = struct {
    ox: f32,
    oy: f32,
    sx: f32,
    sy: f32,

    fn fromRect(rect: Rect, w: f32, h: f32, keep_aspect: bool) Transform {
        var sx = rect.w / w;
        var sy = rect.h / h;
        var ox = rect.x;
        var oy = rect.y;
        if (keep_aspect) {
            const s = @min(sx, sy);
            sx = s;
            sy = s;
            ox = rect.x + (rect.w - w * s) * 0.5;
            oy = rect.y + (rect.h - h * s) * 0.5;
        }
        return .{ .ox = ox, .oy = oy, .sx = sx, .sy = sy };
    }

    fn apply(self: Transform, p: tvg.Point) Point {
        return .{ .x = self.ox + p.x * self.sx, .y = self.oy + p.y * self.sy };
    }

    fn applyXY(self: Transform, x: f32, y: f32) Point {
        return .{ .x = self.ox + x * self.sx, .y = self.oy + y * self.sy };
    }

    /// Average of x/y scale - for stroke widths.
    fn meanScale(self: Transform) f32 {
        return (@abs(self.sx) + @abs(self.sy)) * 0.5;
    }
};

// ---------------------------------------------------------------------------
// Command dispatch
// ---------------------------------------------------------------------------

fn renderCommand(
    allocator: std.mem.Allocator,
    mesh: *MeshBuilder,
    color_table: []const tvg.Color,
    cmd: parsing.DrawCommand,
    xf: Transform,
    opts: RenderOptions,
) !void {
    switch (cmd) {
        .fill_polygon => |fp| {
            if (!opts.disable_fill) {
                try fillPolygonTvg(allocator, mesh, fp.vertices, fp.style, color_table, xf, opts);
            }
        },
        .fill_rectangles => |fr| {
            if (!opts.disable_fill) {
                const col = resolveStyleSource(fr.style, color_table, opts, xf, false);
                for (fr.rectangles) |r| try fillTvgRect(allocator, mesh, r, col, xf, opts.fade);
            }
        },
        .fill_path => |fp| {
            if (!opts.disable_fill) {
                try fillPathTvg(allocator, mesh, fp.path, fp.style, color_table, xf, opts);
            }
        },
        .draw_lines => |dl| {
            const col = resolveStyleSource(dl.style, color_table, opts, xf, true);
            const thickness = (opts.stroke_width_override orelse dl.line_width) * xf.meanScale();
            for (dl.lines) |ln| try strokeLine(allocator, mesh, xf.apply(ln.start), xf.apply(ln.end), col, thickness);
        },
        .draw_line_loop => |ls| {
            const col = resolveStyleSource(ls.style, color_table, opts, xf, true);
            try strokePolylineTvg(allocator, mesh, ls.vertices, true, opts.stroke_width_override orelse ls.line_width, col, xf);
        },
        .draw_line_strip => |ls| {
            const col = resolveStyleSource(ls.style, color_table, opts, xf, true);
            try strokePolylineTvg(allocator, mesh, ls.vertices, false, opts.stroke_width_override orelse ls.line_width, col, xf);
        },
        .draw_line_path => |dp| {
            const col = resolveStyleSource(dp.style, color_table, opts, xf, true);
            try strokePathTvg(allocator, mesh, dp.path, opts.stroke_width_override orelse dp.line_width, col, xf);
        },
        .outline_fill_polygon => |o| {
            if (!opts.disable_fill) {
                try fillPolygonTvg(allocator, mesh, o.vertices, o.fill_style, color_table, xf, opts);
            }
            const stroke_col = resolveStyleSource(o.line_style, color_table, opts, xf, true);
            try strokePolylineTvg(allocator, mesh, o.vertices, true, opts.stroke_width_override orelse o.line_width, stroke_col, xf);
        },
        .outline_fill_rectangles => |o| {
            const stroke_col = resolveStyleSource(o.line_style, color_table, opts, xf, true);
            const thickness = (opts.stroke_width_override orelse o.line_width) * xf.meanScale();
            for (o.rectangles) |r| {
                if (!opts.disable_fill) {
                    const fill_col = resolveStyleSource(o.fill_style, color_table, opts, xf, false);
                    try fillTvgRect(allocator, mesh, r, fill_col, xf, opts.fade);
                }
                try strokeTvgRect(allocator, mesh, r, stroke_col, thickness, xf);
            }
        },
        .outline_fill_path => |o| {
            if (!opts.disable_fill) {
                try fillPathTvg(allocator, mesh, o.path, o.fill_style, color_table, xf, opts);
            }
            try strokePathTvg(allocator, mesh, o.path, opts.stroke_width_override orelse o.line_width, resolveStyleSource(o.line_style, color_table, opts, xf, true), xf);
        },
    }
}

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

fn tvgColorToDvui(c: tvg.Color) Color {
    return .{
        .r = @intFromFloat(math.clamp(c.r * 255.0, 0.0, 255.0)),
        .g = @intFromFloat(math.clamp(c.g * 255.0, 0.0, 255.0)),
        .b = @intFromFloat(math.clamp(c.b * 255.0, 0.0, 255.0)),
        .a = @intFromFloat(math.clamp(c.a * 255.0, 0.0, 255.0)),
    };
}

/// A position-keyed color source used to colour every vertex of a fill or
/// stroke primitive.  Gradients are sampled per-vertex (Gouraud-shaded -
/// close enough to a true gradient at icon resolutions).  Override
/// short-circuits gradients to a flat color.
const ColorSource = union(enum) {
    flat: Color.PMA,
    linear: struct {
        c0: Color,
        c1: Color,
        p0: Point,
        p1: Point,
    },
    radial: struct {
        c0: Color,
        c1: Color,
        center: Point,
        edge: Point,
    },

    fn sampleColor(self: ColorSource, p: Point) Color {
        return switch (self) {
            .flat => |pma| pma.toColor(),
            .linear => |g| blk: {
                const dx = g.p1.x - g.p0.x;
                const dy = g.p1.y - g.p0.y;
                const dlen_sq = dx * dx + dy * dy;
                if (dlen_sq < 1e-9) break :blk g.c0;
                const t = math.clamp(((p.x - g.p0.x) * dx + (p.y - g.p0.y) * dy) / dlen_sq, 0, 1);
                break :blk lerpColor(g.c0, g.c1, t);
            },
            .radial => |g| blk: {
                const rdx = g.edge.x - g.center.x;
                const rdy = g.edge.y - g.center.y;
                const radius = @sqrt(rdx * rdx + rdy * rdy);
                if (radius < 1e-9) break :blk g.c0;
                const dx = p.x - g.center.x;
                const dy = p.y - g.center.y;
                const t = math.clamp(@sqrt(dx * dx + dy * dy) / radius, 0, 1);
                break :blk lerpColor(g.c0, g.c1, t);
            },
        };
    }

    fn sample(self: ColorSource, p: Point) Color.PMA {
        return switch (self) {
            .flat => |pma| pma,
            else => .fromColor(self.sampleColor(p)),
        };
    }
};

fn lerpU8(a: u8, b: u8, t: f32) u8 {
    const af = @as(f32, @floatFromInt(a));
    const bf = @as(f32, @floatFromInt(b));
    return @intFromFloat(math.clamp(af + (bf - af) * t, 0, 255));
}

fn lerpColor(a: Color, b: Color, t: f32) Color {
    return .{
        .r = lerpU8(a.r, b.r, t),
        .g = lerpU8(a.g, b.g, t),
        .b = lerpU8(a.b, b.b, t),
        .a = lerpU8(a.a, b.a, t),
    };
}

/// Build a `ColorSource` from a TVG style.  Override forces flat.  Gradient
/// endpoints are transformed into physical pixel space so per-vertex
/// sampling is a single dot product / distance.
fn resolveStyleSource(style: tvg.Style, color_table: []const tvg.Color, opts: RenderOptions, xf: Transform, is_stroke: bool) ColorSource {
    if (opts.color_override) |c| return .{ .flat = .fromColor(c) };
    if (is_stroke) {
        if (opts.stroke_color_override) |c| return .{ .flat = .fromColor(c) };
    } else {
        if (opts.fill_color_override) |c| return .{ .flat = .fromColor(c) };
    }
    return switch (style) {
        .flat => |idx| .{ .flat = .fromColor(tvgColorToDvui(color_table[idx])) },
        .linear => |g| .{ .linear = .{
            .c0 = tvgColorToDvui(color_table[g.color_0]),
            .c1 = tvgColorToDvui(color_table[g.color_1]),
            .p0 = xf.apply(g.point_0),
            .p1 = xf.apply(g.point_1),
        } },
        .radial => |g| .{ .radial = .{
            .c0 = tvgColorToDvui(color_table[g.color_0]),
            .c1 = tvgColorToDvui(color_table[g.color_1]),
            .center = xf.apply(g.point_0),
            .edge = xf.apply(g.point_1),
        } },
    };
}

// ---------------------------------------------------------------------------
// Fill / stroke primitives in physical-pixel space
// ---------------------------------------------------------------------------

fn fillTvgRect(allocator: std.mem.Allocator, mesh: *MeshBuilder, r: tvg.Rectangle, source: ColorSource, xf: Transform, fade: f32) !void {
    const pts = [_]Point{
        xf.applyXY(r.x, r.y),
        xf.applyXY(r.x + r.width, r.y),
        xf.applyXY(r.x + r.width, r.y + r.height),
        xf.applyXY(r.x, r.y + r.height),
    };
    try fillContoursPhysical(allocator, mesh, &.{&pts}, source, fade);
}

fn strokeTvgRect(allocator: std.mem.Allocator, mesh: *MeshBuilder, r: tvg.Rectangle, source: ColorSource, thickness: f32, xf: Transform) !void {
    const pts = [_]Point{
        xf.applyXY(r.x, r.y),
        xf.applyXY(r.x + r.width, r.y),
        xf.applyXY(r.x + r.width, r.y + r.height),
        xf.applyXY(r.x, r.y + r.height),
    };
    try strokePolylineRoundJoined(allocator, mesh, &pts, true, thickness, source);
}

fn strokeLine(allocator: std.mem.Allocator, mesh: *MeshBuilder, p0: Point, p1: Point, source: ColorSource, thickness: f32) !void {
    const pts = [_]Point{ p0, p1 };
    try strokePolylineRoundJoined(allocator, mesh, &pts, false, thickness, source);
}

/// Fill one or more closed contours (outers AND holes, any winding) via
/// `dvui.Path.fillTriangles`'s nonzero-winding trapezoidal decomposition -
/// concave shapes, holes, and small self-intersections (left over from
/// bezier/arc flattening) are all handled without a bespoke triangulator.
///
/// Flat colors get real edge AA (`opts.fade`).  Gradients can't ride that
/// fade (it assumes a single flat color fading to transparent, not a
/// varying interior color), so gradient fills disable it and Gouraud-shade
/// every vertex from `source` instead - still correctly filled, just
/// without edge AA.
fn fillContoursPhysical(
    allocator: std.mem.Allocator,
    mesh: *MeshBuilder,
    contours: []const []const Point,
    source: ColorSource,
    fade: f32,
) !void {
    if (contours.len == 0) return;

    const paths = try allocator.alloc(Path, contours.len);
    defer allocator.free(paths);
    for (contours, 0..) |c, i| paths[i] = .{ .points = c };

    switch (source) {
        .flat => |pma| {
            var tri = try Path.fillTriangles(allocator, paths, .{
                .color = pma.toColor(),
                .fade = fade,
                .fill_rule = .nonzero,
            });
            defer tri.deinit(allocator);
            try mesh.appendMesh(tri);
        },
        else => {
            var tri = try Path.fillTriangles(allocator, paths, .{
                .color = .white,
                .fade = 0,
                .fill_rule = .nonzero,
            });
            defer tri.deinit(allocator);
            for (tri.vertexes) |*v| v.col = source.sample(v.pos);
            try mesh.appendMesh(tri);
        },
    }
}

/// Spec-compliant-ish stroke with round joins AND round caps - the style
/// SVG-origin icons (feather, lucide, entypo, ...) are authored for.
///
/// `dvui.Path.strokeTriangles` only does miter joins and square/none caps,
/// so each edge is stroked separately with butt caps (no overlap, no miter
/// spikes at sharp corners), and a filled disc is placed at every vertex to
/// act as the round join (filling the wedge between adjacent edges) and,
/// for open paths, the round cap at each endpoint.  Both primitives get
/// `dvui`'s normal 1px AA fade.
fn strokePolylineRoundJoined(
    allocator: std.mem.Allocator,
    mesh: *MeshBuilder,
    pts: []const Point,
    closed: bool,
    thickness: f32,
    source: ColorSource,
) !void {
    if (pts.len < 2) return;
    const radius = thickness * 0.5;
    if (radius <= 0) return;
    const n = pts.len;
    const edge_count: usize = if (closed) n else n - 1;

    var ei: usize = 0;
    while (ei < edge_count) : (ei += 1) {
        const a = pts[ei];
        const b = pts[(ei + 1) % n];
        if (a.diff(b).length() < 1e-6) continue;

        const edge_path: Path = .{ .points = &.{ a, b } };
        const col = switch (source) {
            .flat => |pma| pma.toColor(),
            else => source.sampleColor(mid(a, b)),
        };
        var tri = try edge_path.strokeTriangles(allocator, .{
            .thickness = thickness,
            .color = col,
            .closed = false,
            .endcap_style = .none,
        });
        defer tri.deinit(allocator);
        try mesh.appendMesh(tri);
    }

    for (pts) |p| {
        var builder: Path.Builder = .init(allocator);
        defer builder.deinit();
        builder.addArc(p, radius, math.pi * 2.0, 0, true);
        const disc = builder.build();
        const col = switch (source) {
            .flat => |pma| pma.toColor(),
            else => source.sampleColor(p),
        };
        var tri = try disc.fillConvexTriangles(allocator, .{ .color = col, .fade = 1.0 });
        defer tri.deinit(allocator);
        try mesh.appendMesh(tri);
    }
}

fn fillPolygonTvg(
    allocator: std.mem.Allocator,
    mesh: *MeshBuilder,
    vertices: []const tvg.Point,
    style: tvg.Style,
    color_table: []const tvg.Color,
    xf: Transform,
    opts: RenderOptions,
) !void {
    if (vertices.len < 3) return;
    const source = resolveStyleSource(style, color_table, opts, xf, false);

    const pts = try allocator.alloc(Point, vertices.len);
    defer allocator.free(pts);
    for (vertices, 0..) |v, i| pts[i] = xf.apply(v);

    try fillContoursPhysical(allocator, mesh, &.{pts}, source, opts.fade);
}

fn strokePolylineTvg(
    allocator: std.mem.Allocator,
    mesh: *MeshBuilder,
    vertices: []const tvg.Point,
    closed: bool,
    line_width: f32,
    source: ColorSource,
    xf: Transform,
) !void {
    if (vertices.len < 2) return;
    const thickness = line_width * xf.meanScale();
    const pts = try allocator.alloc(Point, vertices.len);
    defer allocator.free(pts);
    for (vertices, 0..) |v, i| pts[i] = xf.apply(v);
    try strokePolylineRoundJoined(allocator, mesh, pts, closed, thickness, source);
}

// ---------------------------------------------------------------------------
// Path flattening (TVG path -> polyline in physical pixels)
// ---------------------------------------------------------------------------

/// Flatten one TVG path segment into a polyline of physical points.
/// Per-node `line_width` is ignored - fills don't use it, and strokes use
/// the command-level line_width (per-node widths would need segment-wise
/// stroking, which isn't supported).
fn flattenSegment(
    segment: tvg.Path.Segment,
    xf: Transform,
    out: *std.ArrayList(Point),
    alloc: std.mem.Allocator,
) !void {
    var cur = segment.start;
    try out.append(alloc, xf.apply(cur));

    for (segment.commands) |node| {
        switch (node) {
            .line => |n| {
                cur = n.data;
                try out.append(alloc, xf.apply(cur));
            },
            .horiz => |n| {
                cur.x = n.data;
                try out.append(alloc, xf.apply(cur));
            },
            .vert => |n| {
                cur.y = n.data;
                try out.append(alloc, xf.apply(cur));
            },
            .bezier => |n| {
                try flattenCubic(out, alloc, xf, cur, n.data.c0, n.data.c1, n.data.p1);
                cur = n.data.p1;
            },
            .quadratic_bezier => |n| {
                try flattenQuadratic(out, alloc, xf, cur, n.data.c, n.data.p1);
                cur = n.data.p1;
            },
            .arc_circle => |n| {
                // NOTE: svg2tvg encodes the sweep bit INVERTED relative to
                // the SVG convention, so the flip here is required for
                // rounded corners to come out convex instead of concave.
                try flattenArc(out, alloc, xf, cur, n.data.radius, n.data.radius, 0, n.data.large_arc, !n.data.sweep, n.data.target);
                cur = n.data.target;
            },
            .arc_ellipse => |n| {
                try flattenArc(out, alloc, xf, cur, n.data.radius_x, n.data.radius_y, n.data.rotation, n.data.large_arc, !n.data.sweep, n.data.target);
                cur = n.data.target;
            },
            .close => {
                cur = segment.start;
                // For fill use, the caller adds the closing edge implicitly
                // (the polygon's last -> first vertex).  For stroke use,
                // append the start so the stroke draws the closing segment.
                try out.append(alloc, xf.apply(cur));
            },
        }
    }
}

/// Adaptive subdivision of a cubic Bezier - emits points up to a chord
/// tolerance of ~0.5 px in the OUTPUT (physical pixel) space.  Endpoint p0
/// is assumed already in `out`; only p1, intermediate, and final points
/// are appended.
fn flattenCubic(
    out: *std.ArrayList(Point),
    alloc: std.mem.Allocator,
    xf: Transform,
    p0: tvg.Point,
    p1: tvg.Point,
    p2: tvg.Point,
    p3: tvg.Point,
) !void {
    const tol_sq: f32 = 0.25;

    const Frame = struct { p0: Point, p1: Point, p2: Point, p3: Point, depth: u8 };
    var stack: [32]Frame = undefined;
    var sp: usize = 0;
    stack[sp] = .{
        .p0 = xf.apply(p0),
        .p1 = xf.apply(p1),
        .p2 = xf.apply(p2),
        .p3 = xf.apply(p3),
        .depth = 24,
    };
    sp += 1;

    while (sp > 0) {
        sp -= 1;
        const f = stack[sp];

        // Flatness test: max distance from p1, p2 to chord p0-p3.
        const d1 = pointLineDistSq(f.p1, f.p0, f.p3);
        const d2 = pointLineDistSq(f.p2, f.p0, f.p3);
        if (f.depth == 0 or @max(d1, d2) <= tol_sq) {
            try out.append(alloc, f.p3);
            continue;
        }

        // de Casteljau split.
        const m01 = mid(f.p0, f.p1);
        const m12 = mid(f.p1, f.p2);
        const m23 = mid(f.p2, f.p3);
        const m012 = mid(m01, m12);
        const m123 = mid(m12, m23);
        const m0123 = mid(m012, m123);

        // Push RIGHT half first so LEFT is processed next (preserves order).
        stack[sp] = .{ .p0 = m0123, .p1 = m123, .p2 = m23, .p3 = f.p3, .depth = f.depth - 1 };
        sp += 1;
        stack[sp] = .{ .p0 = f.p0, .p1 = m01, .p2 = m012, .p3 = m0123, .depth = f.depth - 1 };
        sp += 1;
    }
}

fn flattenQuadratic(
    out: *std.ArrayList(Point),
    alloc: std.mem.Allocator,
    xf: Transform,
    p0: tvg.Point,
    p1: tvg.Point,
    p2: tvg.Point,
) !void {
    // Promote to cubic: c0 = p0 + 2/3 (p1 - p0), c1 = p2 + 2/3 (p1 - p2).
    const c0 = tvg.Point{
        .x = p0.x + (2.0 / 3.0) * (p1.x - p0.x),
        .y = p0.y + (2.0 / 3.0) * (p1.y - p0.y),
    };
    const c1 = tvg.Point{
        .x = p2.x + (2.0 / 3.0) * (p1.x - p2.x),
        .y = p2.y + (2.0 / 3.0) * (p1.y - p2.y),
    };
    try flattenCubic(out, alloc, xf, p0, c0, c1, p2);
}

/// SVG arc -> center-parameterization -> sampled chord.  Reference:
/// https://www.w3.org/TR/SVG/implnote.html#ArcImplementationNotes
fn flattenArc(
    out: *std.ArrayList(Point),
    alloc: std.mem.Allocator,
    xf: Transform,
    p0: tvg.Point,
    rx_in: f32,
    ry_in: f32,
    rotation_deg: f32,
    large_arc: bool,
    sweep: bool,
    p1: tvg.Point,
) !void {
    var rx = @abs(rx_in);
    var ry = @abs(ry_in);
    if (rx == 0 or ry == 0) {
        try out.append(alloc, xf.apply(p1));
        return;
    }

    const phi = rotation_deg * math.pi / 180.0;
    const cos_phi = @cos(phi);
    const sin_phi = @sin(phi);

    // Step 1: transform to origin-centered, axis-aligned ellipse.
    const dx = (p0.x - p1.x) * 0.5;
    const dy = (p0.y - p1.y) * 0.5;
    const x1p = cos_phi * dx + sin_phi * dy;
    const y1p = -sin_phi * dx + cos_phi * dy;

    // Ensure radii are large enough.
    const lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lambda > 1) {
        const s = @sqrt(lambda);
        rx *= s;
        ry *= s;
    }

    // Step 2: compute center in transformed coords.
    const sign: f32 = if (large_arc == sweep) -1.0 else 1.0;
    var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    const den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    if (num < 0) num = 0;
    const factor = sign * @sqrt(num / den);
    const cxp = factor * (rx * y1p) / ry;
    const cyp = factor * -(ry * x1p) / rx;

    // Step 3: untransform.
    const cx = cos_phi * cxp - sin_phi * cyp + (p0.x + p1.x) * 0.5;
    const cy = sin_phi * cxp + cos_phi * cyp + (p0.y + p1.y) * 0.5;

    // Step 4: start angle + sweep delta.
    const ux = (x1p - cxp) / rx;
    const uy = (y1p - cyp) / ry;
    const vx = (-x1p - cxp) / rx;
    const vy = (-y1p - cyp) / ry;

    const theta1 = math.atan2(uy, ux);
    var delta = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    if (!sweep and delta > 0) delta -= 2 * math.pi;
    if (sweep and delta < 0) delta += 2 * math.pi;

    // Chord-deviation budget of 0.5 px.
    const r_max = @max(rx, ry) * xf.meanScale();
    const err: f32 = 0.5;
    const theta_step = math.acos(math.clamp(r_max / (r_max + err), -1.0, 1.0));
    var n: usize = @intFromFloat(@ceil(@abs(delta) / @max(theta_step, 1e-4)));
    n = math.clamp(n, 4, 512);

    var i: usize = 1;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        const theta = theta1 + delta * t;
        const ct = @cos(theta);
        const st = @sin(theta);
        const x = cos_phi * rx * ct - sin_phi * ry * st + cx;
        const y = sin_phi * rx * ct + cos_phi * ry * st + cy;
        try out.append(alloc, xf.applyXY(x, y));
    }
    // ALWAYS land the final vertex on `target` exactly - floating-point
    // accumulation could otherwise leave a sub-pixel gap.
    try out.append(alloc, xf.apply(p1));
}

fn fillPathTvg(
    allocator: std.mem.Allocator,
    mesh: *MeshBuilder,
    path: tvg.Path,
    style: tvg.Style,
    color_table: []const tvg.Color,
    xf: Transform,
    opts: RenderOptions,
) !void {
    const source = resolveStyleSource(style, color_table, opts, xf, false);

    // Flatten every segment into its own polyline.  Each becomes a
    // separate contour passed to `fillContoursPhysical` - outers and holes
    // alike, in whatever winding order they were authored.  Winding
    // resolution (nonzero rule) happens inside `Path.fillTriangles`.
    var subpaths = std.ArrayList([]Point).empty;
    defer {
        for (subpaths.items) |sp| allocator.free(sp);
        subpaths.deinit(allocator);
    }

    for (path.segments) |seg| {
        var pts = std.ArrayList(Point).empty;
        errdefer pts.deinit(allocator);
        try flattenSegment(seg, xf, &pts, allocator);
        stripTrailingDuplicatesOfFirst(&pts);
        // Degenerate Beziers (control points coincident with endpoints)
        // and encoders chaining straight segments through curves can
        // produce runs of identical points; collapse them.
        collapseRunDuplicates(&pts);
        if (pts.items.len < 3) {
            pts.deinit(allocator);
            continue;
        }
        try subpaths.append(allocator, try pts.toOwnedSlice(allocator));
    }

    if (subpaths.items.len == 0) return;
    try fillContoursPhysical(allocator, mesh, subpaths.items, source, opts.fade);
}

fn strokePathTvg(
    allocator: std.mem.Allocator,
    mesh: *MeshBuilder,
    path: tvg.Path,
    line_width: f32,
    source: ColorSource,
    xf: Transform,
) !void {
    const thickness = line_width * xf.meanScale();
    var pts = std.ArrayList(Point).empty;
    defer pts.deinit(allocator);
    for (path.segments) |seg| {
        pts.clearRetainingCapacity();
        try flattenSegment(seg, xf, &pts, allocator);
        if (pts.items.len < 2) continue;
        const closed = pts.items.len > 1 and approxEqPoint(pts.items[0], pts.items[pts.items.len - 1]);
        if (closed) stripTrailingDuplicatesOfFirst(&pts);
        collapseRunDuplicates(&pts);
        if (pts.items.len < 2) continue;
        try strokePolylineRoundJoined(allocator, mesh, pts.items, closed, thickness, source);
    }
}

// ---------------------------------------------------------------------------
// Small geometry helpers
// ---------------------------------------------------------------------------

fn mid(a: Point, b: Point) Point {
    return .{ .x = (a.x + b.x) * 0.5, .y = (a.y + b.y) * 0.5 };
}

fn pointLineDistSq(p: Point, a: Point, b: Point) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len_sq = dx * dx + dy * dy;
    if (len_sq < 1e-12) {
        const ex = p.x - a.x;
        const ey = p.y - a.y;
        return ex * ex + ey * ey;
    }
    // Perpendicular distance^2 from p to infinite line a-b (sufficient for
    // adaptive subdivision flatness).
    const num = dx * (a.y - p.y) - (a.x - p.x) * dy;
    return (num * num) / len_sq;
}

fn approxEqPoint(a: Point, b: Point) bool {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return (dx * dx + dy * dy) < 1e-6;
}

/// Pop every trailing point that coincides with `pts[0]`.  Common after
/// closing a sub-path: the last drawing command lands on `start` AND the
/// explicit `.close` node appends `start` again, producing two duplicates.
fn stripTrailingDuplicatesOfFirst(pts: *std.ArrayList(Point)) void {
    while (pts.items.len > 1 and approxEqPoint(pts.items[0], pts.items[pts.items.len - 1])) {
        _ = pts.pop();
    }
}

/// Compact consecutive duplicate points.  A near-zero-length edge produces
/// a degenerate join normal downstream.
fn collapseRunDuplicates(pts: *std.ArrayList(Point)) void {
    if (pts.items.len < 2) return;
    var w: usize = 1;
    for (pts.items[1..]) |p| {
        if (!approxEqPoint(pts.items[w - 1], p)) {
            pts.items[w] = p;
            w += 1;
        }
    }
    pts.shrinkRetainingCapacity(w);
}

const std = @import("std");
const math = std.math;
const dvui = @import("dvui.zig");

const svg2tvg = @import("svg2tvg");
const tvg = svg2tvg.tvg;
const parsing = tvg.parsing;

const Backend = dvui.Backend;
const Point = dvui.Point.Physical;
const Rect = dvui.Rect.Physical;
const Color = dvui.Color;
const Vertex = dvui.Vertex;
const Triangles = dvui.Triangles;
const Path = dvui.Path;

test {
    std.testing.refAllDecls(@This());
}
