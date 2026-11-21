//! TVG (TinyVG) icon rendering.
//!
//! svg2tvg's `mesh.tvgMeshes` turns the document into one mesh per fill and
//! stroke, this file colors them (`Path.meshTriangles`) with the document's
//! paints or the overrides.
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
    /// 1 px anti-aliasing of fills and strokes. False gives sharp edges,
    /// useful for pixel-aligned UI strokes.
    anti_alias: bool = true,
};

/// Caller-owned accumulator that collects ALL triangles for a TVG render
/// (every fill and stroke) into one combined mesh, so
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
    /// Ramp texture from the first gradient fill appended, if any - see
    /// `appendMesh`. `renderIcon` binds this for the whole mesh's one draw
    /// call.
    tex: ?dvui.Texture = null,
    /// `dvui.textureRetain`/`textureRelease` key for `tex`, if set - see
    /// `renderIcon`. This mesh (unlike a normal per-frame gradient fill)
    /// gets cached and replayed across frames without re-touching `tex` in
    /// the global texture cache, so whoever puts this mesh in
    /// `Window.icon_mesh_cache` must retain `tex_key` explicitly or it gets
    /// destroyed out from under the cached mesh after one frame.
    tex_key: ?dvui.Texture.Cache.Key = null,

    pub fn init(alloc: std.mem.Allocator) MeshBuilder {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *MeshBuilder) void {
        self.vtx.deinit(self.alloc);
        self.idx.deinit(self.alloc);
    }

    fn appendMesh(self: *MeshBuilder, src: Triangles, tex_key: ?dvui.Texture.Cache.Key) !void {
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
        if (self.tex == null) {
            self.tex = src.texture;
            if (src.texture != null) self.tex_key = tex_key;
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
            .texture = self.tex,
        };
    }
};

pub const MeshCache = struct {
    cache: Storage = .empty,

    pub const Storage = dvui.TrackingAutoHashMap(u64, MeshBuilder, .get_and_put, void);

    pub fn get(self: *MeshCache, key: u64) ?MeshBuilder {
        return self.cache.get(key);
    }

    pub fn add(self: *MeshCache, gpa: std.mem.Allocator, key: u64, mesh: MeshBuilder) std.mem.Allocator.Error!void {
        const prev = try self.cache.fetchPut(gpa, key, mesh);
        if (prev) |kv| {
            var m = kv.value;
            if (m.tex_key) |k| dvui.textureRelease(k);
            m.deinit();
        }
    }

    /// Frees every mesh that was not accessed since the last call to
    /// `reset`, releasing its retained gradient texture (see
    /// `MeshBuilder.tex_key`) first.
    pub fn reset(self: *MeshCache) void {
        var it = self.cache.iterator();
        while (it.next_resetting()) |kv| {
            var m = kv.value;
            if (m.tex_key) |k| dvui.textureRelease(k);
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

pub fn hashValue(h: *dvui.Hasher, v: anytype) void {
    const T = @TypeOf(v);
    switch (@typeInfo(T)) {
        .float => |f| {
            const Bits = @Int(.unsigned, f.bits);
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
        .@"struct" => |s| inline for (s.field_names) |field_name| hashValue(h, @field(v, field_name)),
        .@"union" => |u| {
            const tag = std.meta.activeTag(v);
            hashValue(h, tag);
            inline for (u.field_types, u.field_names) |field_type, field_name| {
                if (@field(std.meta.Tag(T), field_name) == tag) {
                    if (field_type != void) hashValue(h, @field(v, field_name));
                }
            }
        },
        .@"enum" => h.update(std.mem.asBytes(&@backingInt(v))),
        else => h.update(std.mem.asBytes(&v)),
    }
}

/// Only valid between `Window.begin` and `Window.end`.
pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: dvui.RectScale, opts: dvui.render.TextureOptions, icon_opts: dvui.IconRenderOptions) Backend.TextureError!void {
    if (rs.s == 0) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;

    // Ask for an integer size icon (used as the mesh authoring size).
    const ask_height = @ceil(rs.r.h);
    if (ask_height <= 0) return;
    const ask_width = dvui.iconWidth(name, tvg_bytes, ask_height) catch ask_height;

    var h = dvui.Hasher.init(0);
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
        };

        appendTvg(scratch.allocator(), &mesh, tvg_bytes, local_rect, render_opts) catch |err| {
            mesh.deinit();
            mesh = MeshBuilder.init(cw.gpa);
            dvui.logError(@src(), err, "Could not build mesh from tvg file \"{s}\"", .{name});
            // Cache invalid input as an empty mesh so it is not parsed again every frame.
            if (err == error.OutOfMemory) return;
        };

        // `mesh` outlives this single render call (it's about to go into
        // `icon_mesh_cache` and get replayed frame after frame), but its
        // gradient ramp texture (if any) lives in the global texture cache,
        // which frees anything not re-touched within one frame. Retain it
        // now so `MeshCache.add`'s errdefer path below can safely release
        // it; the retain that keeps it alive long-term is re-asserted
        // every frame this entry is actually used (see below).
        if (mesh.tex_key) |k| dvui.textureRetain(k);

        cw.icon_mesh_cache.add(cw.gpa, hash, mesh) catch |err| {
            if (mesh.tex_key) |k| dvui.textureRelease(k);
            mesh.deinit();
            dvui.logError(@src(), err, "Could not cache mesh for icon \"{s}\"", .{name});
            return;
        };
        break :blk mesh;
    };

    // Re-touch the retain every frame this cache entry is used (not just
    // when it's built): a gradient's ramp texture is keyed only by its
    // stops/alpha, so a *different* mesh entry can share this same
    // `tex_key` (e.g. this same icon rebuilt every frame while an angle
    // animates, evicting the previous frame's entry each time). Evicting
    // that other entry releases the shared key (see `MeshCache.reset`),
    // which would otherwise leave this still-live entry's texture
    // unretained and unretouched (a cache hit skips `Gradient.apply`)
    // until it's destroyed out from under a later frame's render.
    if (mesh.tex_key) |k| dvui.textureRetain(k);

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

    try dvui.renderTriangles(tri, tri.texture);
}

/// Appends the document drawn into `rect`. Malformed documents and documents
/// beyond svg2tvg's work budget fail with `error.InvalidInput` or
/// `error.TooComplex` and append nothing.
pub fn appendTvg(
    scratch_alloc: std.mem.Allocator,
    mesh: *MeshBuilder,
    tvg_bytes: []const u8,
    rect: Rect,
    opts: RenderOptions,
) !void {
    const meshes = try svg2tvg.mesh.tvgMeshes(scratch_alloc, tvg_bytes, .{
        .origin = .{ rect.x, rect.y },
        .size = .{ rect.w, rect.h },
        .keep_aspect = opts.keep_aspect,
        .line_width = opts.stroke_width_override,
        .fills = !opts.disable_fill,
        .anti_alias = opts.anti_alias,
    });
    defer meshes.deinit(scratch_alloc);
    for (meshes.parts) |part| {
        var storage: [2]Gradient.Stop = undefined;
        const color = partColor(part, opts, rect, &storage);
        const tex_key: ?dvui.Texture.Cache.Key = if (color == .gradient) color.gradient.textureCacheKey(.{}) else null;
        var triangles = try Path.meshTriangles(scratch_alloc, part.mesh, color);
        defer triangles.deinit(scratch_alloc);
        try mesh.appendMesh(triangles, tex_key);
    }
}

/// The override for the part's kind, else its paint. `storage` backs the stops
/// of a document gradient.
fn partColor(part: svg2tvg.mesh.TvgPart, opts: RenderOptions, rect: Rect, storage: *[2]Gradient.Stop) ColorOrGradient {
    const override = opts.color_override orelse switch (part.kind) {
        .fill => opts.fill_color_override,
        .stroke => opts.stroke_color_override,
    };
    if (override) |color| return switch (color) {
        .color => color,
        .gradient => |g| .{ .gradient = withDefaultAnchor(g, rect) },
    };
    return switch (part.paint) {
        .flat => |c| .{ .color = tvgColor(c) },
        .linear => |g| .{ .gradient = linearGradientBetween(storage, tvgColor(g.color_0), tvgColor(g.color_1), point(g.point_0), point(g.point_1)) },
        .radial => |g| .{ .gradient = radialGradientBetween(storage, tvgColor(g.color_0), tvgColor(g.color_1), point(g.center), point(g.edge)) },
    };
}

fn tvgColor(c: svg2tvg.mesh.Color) Color {
    return .{
        .r = @intFromFloat(math.clamp(c[0] * 255.0, 0.0, 255.0)),
        .g = @intFromFloat(math.clamp(c[1] * 255.0, 0.0, 255.0)),
        .b = @intFromFloat(math.clamp(c[2] * 255.0, 0.0, 255.0)),
        .a = @intFromFloat(math.clamp(c[3] * 255.0, 0.0, 255.0)),
    };
}

fn point(p: svg2tvg.mesh.Point) Point {
    return .{ .x = p[0], .y = p[1] };
}

/// Builds a `dvui.Gradient.linear` whose `t=0`/`t=1` points are exactly
/// `p0`/`p1` - not derived from any shape's bounding box - by picking a
/// synthetic `anchor` sized so `Gradient.linearT`'s box-projection formula
/// reduces to a plain projection onto the `p0->p1` segment (all the
/// projected half-extent is put on whichever axis the segment is more
/// aligned with; the other axis gets a zero half-extent, which
/// `Gradient.sampleRaw`'s degenerate check tolerates as long as the other
/// axis is nonzero). Lets TVG's native 2-point linear gradient style go
/// through `Path.meshTriangles`'s gradient support (ramp texture + UV)
/// instead of a bespoke per-vertex Gouraud shader.
fn linearGradientBetween(storage: *[2]Gradient.Stop, c0: Color, c1: Color, p0: Point, p1: Point) Gradient {
    storage.* = .{ .{ .color = c0, .offset = 0 }, .{ .color = c1, .offset = 1 } };
    const dx = p1.x - p0.x;
    const dy = p1.y - p0.y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
        return .{ .linear = .{ .stops = storage, .anchor = .{ .x = p0.x, .y = p0.y, .w = 0, .h = 0 } } };
    }
    const adx = @abs(dx) / len;
    const ady = @abs(dy) / len;
    const half = len / 2;
    var hx: f32 = 0;
    var hy: f32 = 0;
    if (adx >= ady) hx = half / adx else hy = half / ady;
    return .{ .linear = .{
        .stops = storage,
        .angle_degrees = math.radiansToDegrees(math.atan2(dy, dx)),
        .anchor = .{
            .x = (p0.x + p1.x) / 2 - hx,
            .y = (p0.y + p1.y) / 2 - hy,
            .w = 2 * hx,
            .h = 2 * hy,
        },
    } };
}

/// Builds a `dvui.Gradient.radial` whose ending circle is exactly
/// `center`/`|edge - center|` - not derived from any shape's bounding box -
/// via an explicit `.circle{.radius=}` and an `anchor` centered on `center`.
/// See `linearGradientBetween`.
fn radialGradientBetween(storage: *[2]Gradient.Stop, c0: Color, c1: Color, center: Point, edge: Point) Gradient {
    storage.* = .{ .{ .color = c0, .offset = 0 }, .{ .color = c1, .offset = 1 } };
    const dx = edge.x - center.x;
    const dy = edge.y - center.y;
    const radius = @sqrt(dx * dx + dy * dy);
    if (radius < 1e-6) {
        return .{ .radial = .{ .stops = storage, .anchor = .{ .x = center.x, .y = center.y, .w = 0, .h = 0 } } };
    }
    return .{ .radial = .{
        .stops = storage,
        .shape = .{ .circle = .{ .radius = radius } },
        .anchor = .{ .x = center.x - radius, .y = center.y - radius, .w = 2 * radius, .h = 2 * radius },
    } };
}

fn withDefaultAnchor(g: Gradient, bounds: Rect) Gradient {
    var out = g;
    switch (out) {
        .linear => |*l| if (l.anchor == null) {
            l.anchor = bounds;
        },
        .radial => |*r| if (r.anchor == null) {
            r.anchor = bounds;
        },
        .scattered => |*s| if (s.anchor == null) {
            s.anchor = bounds;
        },
    }
    return out;
}

const std = @import("std");
const math = std.math;
const dvui = @import("dvui.zig");

const svg2tvg = @import("svg2tvg");

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
