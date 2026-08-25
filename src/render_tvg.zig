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
    /// If set, overrides every fill / stroke color or gradient in the TVG.
    color_override: ?ColorOrGradient = null,
    /// If set, overrides only fill colors (does not affect strokes).
    fill_color_override: ?ColorOrGradient = null,
    /// If set, overrides only stroke colors (does not affect fills).
    stroke_color_override: ?ColorOrGradient = null,
    /// If set, overrides the stroke width for all stroked paths.
    stroke_width_override: ?f32 = null,
    /// When true, all fill operations are skipped (only strokes are drawn).
    disable_fill: bool = false,
    /// Preserve TVG aspect ratio inside `rect` (letterbox).  When false the
    /// icon is stretched to fill the rect.
    keep_aspect: bool = true,
    /// Edge feather (physical px) for anti-aliasing of fills and stroke
    /// caps/joins (flat or gradient - see `fillContoursPhysical`).  0
    /// disables fill AA - sharp edges, useful for pixel-aligned UI strokes.
    fade: f32 = 1.0,
    /// Physical-pixel bounds a `color_override`/`fill_color_override`/
    /// `stroke_color_override` gradient is sampled against. Set by
    /// `appendTvg` from `rect`.
    bounds: Rect = .{},
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

/// Hashes `v` field-by-field, following only the active tag of unions and
/// the contents (not pointer) of slices. `icon_opts.fill_color`/
/// `stroke_color` are `?ColorOrGradient`, a union whose `.gradient` payload
/// is much larger than `.color` - `std.mem.asBytes` on the union would read
/// uninitialized trailing bytes whenever the active tag is `.color`, making
/// the cache key nondeterministic. `std.hash.autoHashStrat` can't be used
/// directly since it rejects float fields (`Gradient` has many); bitcast
/// floats to same-width ints ourselves instead.
fn hashValue(h: *dvui.fnv, v: anytype) void {
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .float => |f| {
            const Bits = std.meta.Int(.unsigned, f.bits);
            const bits: Bits = @bitCast(v);
            h.update(std.mem.asBytes(&bits));
        },
        .optional => {
            h.update(&[_]u8{if (v == null) 0 else 1});
            if (v) |val| hashValue(h, val);
        },
        .pointer => |p| switch (p.size) {
            .slice => {
                h.update(std.mem.asBytes(&v.len));
                for (v) |item| hashValue(h, item);
            },
            else => @compileError("hashValue: unsupported pointer type " ++ @typeName(T)),
        },
        .@"struct" => |s| inline for (s.fields) |field| hashValue(h, @field(v, field.name)),
        .@"union" => |u| {
            const tag = std.meta.activeTag(v);
            hashValue(h, tag);
            inline for (u.fields) |field| {
                if (@field(std.meta.Tag(T), field.name) == tag) {
                    if (field.type != void) hashValue(h, @field(v, field.name));
                }
            }
        },
        .@"enum" => h.update(std.mem.asBytes(&@intFromEnum(v))),
        else => h.update(std.mem.asBytes(&v)),
    }
}

/// Draws `tvg_bytes` scaled to fit `rs`, using `Window.icon_mesh_cache` to
/// avoid re-triangulating unchanged icons every frame.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: dvui.RectScale, opts: dvui.render.TextureOptions, icon_opts: dvui.IconRenderOptions) Backend.TextureError!void {
    if (rs.s == 0) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;

    // Ask for an integer size icon (used as the mesh authoring size).
    const ask_height = @ceil(rs.r.h);
    if (ask_height <= 0) return;
    const ask_width = dvui.iconWidth(name, tvg_bytes, ask_height) catch ask_height;

    var h = dvui.fnv.init();
    h.update(std.mem.asBytes(&tvg_bytes.ptr));
    h.update(std.mem.asBytes(&ask_height));
    hashValue(&h, icon_opts);
    const hash = h.final();

    const cw = dvui.currentWindow();

    const mesh: MeshBuilder = cw.icon_mesh_cache.get(hash) orelse blk: {
        var mesh = MeshBuilder.init(cw.gpa);
        errdefer mesh.deinit();

        var scratch = std.heap.ArenaAllocator.init(cw.gpa);
        defer scratch.deinit();

        const local_rect: Rect = .{ .x = 0, .y = 0, .w = ask_width, .h = ask_height };
        const render_opts: RenderOptions = .{
            .fill_color_override = icon_opts.fill_color,
            .stroke_color_override = icon_opts.stroke_color,
            .stroke_width_override = icon_opts.stroke_width,
            .disable_fill = if (icon_opts.fill_color) |c| c.toColor().a == 0 else false,
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

    const scale_h: f32 = rs.r.h / ask_height;
    const scale_w: f32 = rs.r.w / ask_width;
    const tx = rs.r.x;
    const ty = rs.r.y;
    for (tri.vertexes) |*v| {
        v.pos.x = v.pos.x * scale_w + tx;
        v.pos.y = v.pos.y * scale_h + ty;
    }
    tri.bounds.x = tri.bounds.x * scale_w + tx;
    tri.bounds.y = tri.bounds.y * scale_h + ty;
    tri.bounds.w *= scale_w;
    tri.bounds.h *= scale_h;

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

    var opts_with_bounds = opts;
    opts_with_bounds.bounds = rect;

    while (try parser.next()) |cmd| {
        try renderCommand(scratch_alloc, mesh, parser.color_table, cmd, xf, opts_with_bounds);
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
    /// A caller-supplied `dvui.Gradient` override (from
    /// `IconRenderOptions.fill_color`/`stroke_color`), sampled analytically
    /// against the icon's bounding box.
    dvui_gradient: struct {
        gradient: Gradient,
        bounds: Rect,
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
            .dvui_gradient => |g| g.gradient.sample(g.bounds, p),
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
fn colorSourceFromOverride(c: ColorOrGradient, bounds: Rect) ColorSource {
    return switch (c) {
        .color => |col| .{ .flat = .fromColor(col) },
        .gradient => |g| .{ .dvui_gradient = .{ .gradient = g, .bounds = bounds } },
    };
}

fn resolveStyleSource(style: tvg.Style, color_table: []const tvg.Color, opts: RenderOptions, xf: Transform, is_stroke: bool) ColorSource {
    if (opts.color_override) |c| return colorSourceFromOverride(c, opts.bounds);
    if (is_stroke) {
        if (opts.stroke_color_override) |c| return colorSourceFromOverride(c, opts.bounds);
    } else {
        if (opts.fill_color_override) |c| return colorSourceFromOverride(c, opts.bounds);
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
/// Flat colors get their edge AA from `Path.fillTriangles`'s `fade` (a
/// uniform fade-to-transparent band works for a single color). Gradients
/// can't reuse that band directly - color varies across it - so instead we
/// Gouraud-shade the opaque interior (unchanged) and add a second band,
/// `gouraudFadeBand`, that analytically samples `source` per boundary vertex
/// while fading alpha to 0, giving gradients the same edge AA flat fills get.
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
                .color = .{ .color = pma.toColor() },
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
            var shaded = try gouraudShade(allocator, tri, source);
            defer shaded.deinit(allocator);
            try mesh.appendMesh(shaded);

            if (fade > 0) {
                var band = try gouraudFadeBand(allocator, contours, source, fade);
                defer band.deinit(allocator);
                try mesh.appendMesh(band);
            }
        },
    }
}

/// Edge-AA band for non-flat `ColorSource`s: same outward-normal offset
/// technique as `Path.fillConvexTriangles`/`fillAppendFade` (inner vertex on
/// the true boundary minus half the fade, outer vertex plus the rest, faded
/// to transparent), but sampling `source` analytically per boundary vertex
/// instead of using one flat color.
///
/// Operates on the raw per-subpath contours rather than `Path.fillTriangles`'s
/// resolved boundary, so overlapping/self-intersecting contours (rare - left
/// over from bezier/arc flattening) can double up faded coverage at the
/// overlap. Icons don't hit this in practice; revisit if one does.
///
/// `fillConvexTriangles`/`fillAppendFade` can hardcode which way the offset
/// formula points because their input winding is caller-controlled or
/// already normalized by earcut's boundary resolution. Raw TVG contours
/// carry whatever winding the source file used, so each contour's own
/// signed area decides which sign makes the offset point outward.
fn gouraudFadeBand(allocator: std.mem.Allocator, contours: []const []const Point, source: ColorSource, fade: f32) !Triangles {
    var vtx: std.ArrayList(Vertex) = .empty;
    errdefer vtx.deinit(allocator);
    var idx: std.ArrayList(Vertex.Index) = .empty;
    errdefer idx.deinit(allocator);

    const inside_len = @min(0.5, fade / 2);
    const outside_len = if (fade <= 1) fade / 2 else fade - 0.5;

    for (contours) |pts| {
        const n = pts.len;
        if (n < 3) continue;

        var area2: f32 = 0;
        for (0..n) |i| {
            const p = pts[i];
            const q = pts[(i + 1) % n];
            area2 += p.x * q.y - q.x * p.y;
        }
        const sign: f32 = if (area2 > 0) -1 else 1;

        const inner_idx = try allocator.alloc(Vertex.Index, n);
        defer allocator.free(inner_idx);
        const outer_idx = try allocator.alloc(Vertex.Index, n);
        defer allocator.free(outer_idx);

        for (0..n) |i| {
            const aa = pts[(i + n - 1) % n];
            const bb = pts[i];
            const cc = pts[(i + 1) % n];
            const diffab = aa.diff(bb).normalize();
            const diffbc = bb.diff(cc).normalize();
            var norm: Point = .{
                .x = sign * (diffab.y + diffbc.y) / 2,
                .y = sign * (-diffab.x - diffbc.x) / 2,
            };

            inner_idx[i] = @intCast(vtx.items.len);
            try vtx.append(allocator, .{
                .pos = .{ .x = bb.x - norm.x * inside_len, .y = bb.y - norm.y * inside_len },
                .col = .fromColor(source.sampleColor(bb)),
            });

            const d2 = norm.x * norm.x + norm.y * norm.y;
            if (d2 > 0.000001) norm = norm.scale(1.0 / d2, Point);
            const l = norm.length();
            if (l > 2.0) norm = norm.scale(2.0 / l, Point);

            outer_idx[i] = @intCast(vtx.items.len);
            try vtx.append(allocator, .{
                .pos = .{ .x = bb.x + norm.x * outside_len, .y = bb.y + norm.y * outside_len },
                .col = .transparent,
            });
        }

        for (0..n) |i| {
            const j = (i + 1) % n;
            try idx.appendSlice(allocator, &.{ inner_idx[i], outer_idx[i], inner_idx[j] });
            try idx.appendSlice(allocator, &.{ outer_idx[i], outer_idx[j], inner_idx[j] });
        }
    }

    return .{
        .vertexes = try vtx.toOwnedSlice(allocator),
        .indices = try idx.toOwnedSlice(allocator),
        .bounds = .{},
    };
}

/// Re-triangulates `tri` (a flat, white-colored fill straight out of
/// `Path.fillTriangles`) with per-vertex colors from `source`, adaptively
/// splitting each triangle wherever plain Gouraud interpolation (lerping the
/// 3 corner colors) would visibly diverge from the source's true analytic
/// color. Icon fills are just the polygon's own outline vertices - large,
/// sparse triangles - so a corner-only sample is exact for an affine color
/// function (flat, or 2-stop `linear`) but visibly wrong for anything
/// curved (`radial`, `scattered`, multi-stop `linear`): edge midpoints then
/// read closer to a straight blend of the corners than to the source's
/// actual (e.g. circular) isolines. Recursion bottoms out once every edge's
/// analytic midpoint color is within tolerance of its Gouraud-lerped color,
/// or at `max_depth`.
fn gouraudShade(allocator: std.mem.Allocator, tri: Triangles, source: ColorSource) !Triangles {
    var vtx = std.ArrayList(Vertex).empty;
    errdefer vtx.deinit(allocator);
    var idx = std.ArrayList(Vertex.Index).empty;
    errdefer idx.deinit(allocator);

    var i: usize = 0;
    while (i < tri.indices.len) : (i += 3) {
        const v0 = tri.vertexes[tri.indices[i]];
        const v1 = tri.vertexes[tri.indices[i + 1]];
        const v2 = tri.vertexes[tri.indices[i + 2]];
        try subdivideGouraudTri(
            allocator,
            &vtx,
            &idx,
            .{ .pos = v0.pos, .col = source.sample(v0.pos) },
            .{ .pos = v1.pos, .col = source.sample(v1.pos) },
            .{ .pos = v2.pos, .col = source.sample(v2.pos) },
            source,
            6, // max_depth: caps worst-case blowup at 4^6 leaf tris per source triangle
        );
    }

    return .{
        .vertexes = try vtx.toOwnedSlice(allocator),
        .indices = try idx.toOwnedSlice(allocator),
        .bounds = tri.bounds,
    };
}

/// Per-channel tolerance (out of 255) for `gouraudShade`'s divergence test.
const gouraud_tolerance: u8 = 6;

fn pmaClose(a: Color.PMA, b: Color.PMA) bool {
    return @abs(@as(i16, a.r) - b.r) <= gouraud_tolerance and
        @abs(@as(i16, a.g) - b.g) <= gouraud_tolerance and
        @abs(@as(i16, a.b) - b.b) <= gouraud_tolerance and
        @abs(@as(i16, a.a) - b.a) <= gouraud_tolerance;
}

fn pmaMid(a: Color.PMA, b: Color.PMA) Color.PMA {
    return .{
        .r = lerpU8(a.r, b.r, 0.5),
        .g = lerpU8(a.g, b.g, 0.5),
        .b = lerpU8(a.b, b.b, 0.5),
        .a = lerpU8(a.a, b.a, 0.5),
    };
}

fn subdivideGouraudTri(
    allocator: std.mem.Allocator,
    vtx: *std.ArrayList(Vertex),
    idx: *std.ArrayList(Vertex.Index),
    v0: Vertex,
    v1: Vertex,
    v2: Vertex,
    source: ColorSource,
    depth: u8,
) !void {
    if (depth > 0) {
        const m01p = mid(v0.pos, v1.pos);
        const m12p = mid(v1.pos, v2.pos);
        const m20p = mid(v2.pos, v0.pos);
        const m01c = source.sample(m01p);
        const m12c = source.sample(m12p);
        const m20c = source.sample(m20p);

        if (!pmaClose(m01c, pmaMid(v0.col, v1.col)) or
            !pmaClose(m12c, pmaMid(v1.col, v2.col)) or
            !pmaClose(m20c, pmaMid(v2.col, v0.col)))
        {
            const m01: Vertex = .{ .pos = m01p, .col = m01c };
            const m12: Vertex = .{ .pos = m12p, .col = m12c };
            const m20: Vertex = .{ .pos = m20p, .col = m20c };
            try subdivideGouraudTri(allocator, vtx, idx, v0, m01, m20, source, depth - 1);
            try subdivideGouraudTri(allocator, vtx, idx, m01, v1, m12, source, depth - 1);
            try subdivideGouraudTri(allocator, vtx, idx, m20, m12, v2, source, depth - 1);
            try subdivideGouraudTri(allocator, vtx, idx, m01, m12, m20, source, depth - 1);
            return;
        }
    }

    const base: Vertex.Index = @intCast(vtx.items.len);
    try vtx.appendSlice(allocator, &.{ v0, v1, v2 });
    try idx.appendSlice(allocator, &.{ base, base + 1, base + 2 });
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
            .color = .{ .color = col },
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
        var tri = try disc.fillConvexTriangles(allocator, .{ .color = .{ .color = col }, .fade = 1.0 });
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

/// Adaptive subdivision of a cubic Bezier, delegating to
/// `Path.Builder.addCubicBezier` (same 0.5px chord-deviation tolerance
/// already used everywhere else in dvui) instead of reimplementing de
/// Casteljau subdivision here. Endpoint p0 is assumed already in `out`;
/// only p1, intermediate, and final points are appended.
fn flattenCubic(
    out: *std.ArrayList(Point),
    alloc: std.mem.Allocator,
    xf: Transform,
    p0: tvg.Point,
    p1: tvg.Point,
    p2: tvg.Point,
    p3: tvg.Point,
) !void {
    var builder: Path.Builder = .init(alloc);
    defer builder.deinit();
    builder.addCubicBezier(xf.apply(p0), xf.apply(p1), xf.apply(p2), xf.apply(p3));
    // `addCubicBezier` includes p0, which is already in `out`.
    try out.appendSlice(alloc, builder.build().points[1..]);
}

fn flattenQuadratic(
    out: *std.ArrayList(Point),
    alloc: std.mem.Allocator,
    xf: Transform,
    p0: tvg.Point,
    p1: tvg.Point,
    p2: tvg.Point,
) !void {
    var builder: Path.Builder = .init(alloc);
    defer builder.deinit();
    builder.addQuadBezier(xf.apply(p0), xf.apply(p1), xf.apply(p2));
    try out.appendSlice(alloc, builder.build().points[1..]);
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

// Manual visual-verification tool (no assertions): renders an icon with a
// radial gradient fill so the adaptive Gouraud subdivision in
// `gouraudShade` can be screenshotted. Star/circle fills are just their
// outline vertices - large, sparse triangles where naive per-vertex
// Gouraud shading of a non-affine (radial) color function visibly
// diverges from a true circular gradient.
//
// Run with (from repo root): zig build test -Dtest-filter="DOCIMG icon gradient" -Dimage-dir=/tmp/gradient-compare/dvui
test "DOCIMG icon gradient radial" {
    const size: dvui.Size = .{ .w = 200, .h = 200 };
    var t = try dvui.testing.init(.{ .window_size = size });
    defer t.deinit();

    const red: Color = .{ .r = 255, .g = 80, .b = 80, .a = 255 };
    const blue: Color = .{ .r = 80, .g = 120, .b = 255, .a = 255 };

    const Sample = struct {
        fn frame() !dvui.App.Result {
            dvui.icon(@src(), "star", dvui.entypo.star, .{
                .fill_color = .{ .gradient = .{ .radial = .{
                    .stops = &.{ .{ .color = red, .offset = 0 }, .{ .color = blue, .offset = 1 } },
                } } },
            }, .{ .expand = .both });
            return .ok;
        }
    };
    try t.saveImage(Sample.frame, null, "icon-star-radial-gradient.png");
}

/// Mirrors `dvui.testing.capturePng`'s frame/Picture dance but returns raw
/// premultiplied pixels instead of encoding, so a test can inspect alpha
/// directly (e.g. to compare edge-AA ramps between two renders).
fn captureIconPixels(alloc: std.mem.Allocator, frame: dvui.App.frameFunction, rect: Rect) ![]Color.PMA {
    var picture = dvui.Picture.start(rect) orelse return error.Unsupported;
    if (try frame() == .close) return error.Closed;
    _ = dvui.currentWindow().endRendering(.{});
    picture.stop();
    const pixels = try dvui.textureReadTarget(alloc, picture.texture);
    picture.deinit();

    const cw = dvui.currentWindow();
    _ = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);
    return pixels;
}

// Regression test for the "gradient icons look pixelated compared to flat
// icons" bug: a flat fill and a same-colored 2-stop gradient fill of the
// same icon should produce (almost) identical rendered alpha, including the
// partially-transparent edge-AA ring. Before `gouraudFadeBand`, the
// gradient render had zero partially-transparent pixels (fade was forced to
// 0), so this would have failed on `partial_alpha_grad > 20`.
test "gradient icon fill AA matches flat" {
    const size: dvui.Size = .{ .w = 60, .h = 60 };
    var t = try dvui.testing.init(.{ .window_size = size });
    defer t.deinit();

    const white: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };

    const FlatSample = struct {
        fn frame() !dvui.App.Result {
            dvui.icon(@src(), "star", dvui.entypo.star, .{
                .fill_color = .{ .color = white },
            }, .{ .expand = .both });
            return .ok;
        }
    };
    const GradientSample = struct {
        fn frame() !dvui.App.Result {
            dvui.icon(@src(), "star", dvui.entypo.star, .{
                .fill_color = .{ .gradient = .{ .linear = .{
                    .stops = &.{ .{ .color = white, .offset = 0 }, .{ .color = white, .offset = 1 } },
                } } },
            }, .{ .expand = .both });
            return .ok;
        }
    };

    const rect = dvui.windowRectPixels();
    const flat = try captureIconPixels(std.testing.allocator, FlatSample.frame, rect);
    defer std.testing.allocator.free(flat);
    const grad = try captureIconPixels(std.testing.allocator, GradientSample.frame, rect);
    defer std.testing.allocator.free(grad);

    try std.testing.expectEqual(flat.len, grad.len);

    var partial_alpha_flat: usize = 0;
    var partial_alpha_grad: usize = 0;
    var max_alpha_diff: u8 = 0;
    for (flat, grad) |f, g| {
        if (f.a > 0 and f.a < 255) partial_alpha_flat += 1;
        if (g.a > 0 and g.a < 255) partial_alpha_grad += 1;
        const d: u8 = if (f.a > g.a) f.a - g.a else g.a - f.a;
        max_alpha_diff = @max(max_alpha_diff, d);
    }

    std.debug.print("partial_alpha_flat={d} partial_alpha_grad={d} max_alpha_diff={d}\n", .{ partial_alpha_flat, partial_alpha_grad, max_alpha_diff });
    try std.testing.expect(partial_alpha_flat > 20);
    try std.testing.expect(partial_alpha_grad > 20);
    try std.testing.expect(max_alpha_diff <= 2);
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
const Gradient = dvui.Gradient;
const ColorOrGradient = dvui.ColorOrGradient;

test {
    std.testing.refAllDecls(@This());
}
