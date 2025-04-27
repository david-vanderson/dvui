//! Backend that dumps SVG file for each frame.
//!
//! This is intended for test and debug purpose, as well as images generation.
//!
//! TODO clean way to pass in debug flags and document
//! TODO encode png in base64 by default with opt-out and document

/// Size of the resulting svg (aka window size)
size: dvui.Size,

svg_patterns: std.ArrayListUnmanaged(SvgPattern) = undefined,
svg_filters: std.AutoHashMapUnmanaged(SvgFilter, void) = undefined,
svg_clippaths: std.ArrayListUnmanaged(SvgClippath) = undefined,
svg_graphics: std.ArrayListUnmanaged(SvgGraphics) = undefined,

/// temporary allocator for current frame. (passed in begin)
arena: std.mem.Allocator = undefined,
/// longer lived allocator, for e.g. textures. (passed in initWindow)
alloc: std.mem.Allocator = undefined,

/// Count frames to emit frameXX.svg
/// Max 255 frames, fair enough
frame_count: u8 = 0,
/// Count textures to emit frameXX-XXX.png
/// Max 4096 texture per frame, seems enough and print nicely in 3 chars
texture_count: u12 = 0,
/// Count each triangle per frame. Reset for each frame.
/// u24 prints nicely in 6 chars
/// ~16million triangle per frame. Probably more than enough
triangle_count: u24 = 0,
/// Count each clipping rect per frame
/// Max 4096 clipr per frame, prints in 3 chars, same than texture.
clipr_count: u12 = 0,

/// Stop output files after that many frames to avoid accidentyl crazy big folders.
const max_frame: u8 = 25;
/// If true, delete all previously emitted images (i.e. "frame**.svg|png)
const empty_render_folder: bool = true;

/// Paint color dots on triangle's angles.
const debughl_vertex = false;
/// Paint empty triangles vertexes in red.
const debughl_no_ccw_triangle = false;
/// Outline clipping rects passed to drawClippedTriangles
const debughl_clipr = false;
/// Output texture files with uv points on.
const emit_debug_texture = false;

const render_dir = "svg_render2/";
const texture_file_template = render_dir ++ "/frame{d:04}-texture{d:04}.png";

pub const SvgBackend = @This();
pub const Context = *SvgBackend;
pub const kind: dvui.enums.Backend = .svg;

pub const InitOptions = struct {
    // Long lived allocator needed to keep the name of the textures from frame to frame.
    allocator: std.mem.Allocator,
    /// The size of the window we can render to
    size: dvui.Size,
};

/// Generic struct for emitting graphics SVG tags
pub const SvgGraphics = union(enum) {
    clip_group: SvgClipGroup,
    color_group: SvgColorGroup,
    close_group: void,
    triangle: SvgTriangle,
};
/// Clip group only need an id corresponding to SvgClipPath.
///  Corresponds to <g clip-path="id">
pub const SvgClipGroup = struct {
    id: u12,
};
/// Simply wraps a dvui.Color.
///  Corresponds to <g fill="#xxxxxx" fill-opacity="d">
pub const SvgColorGroup = struct {
    col: dvui.Color,

    pub fn toU24Col(self: SvgColorGroup) u24 {
        const c: u24 = (@as(u24, self.col.r) << 16) | (@as(u24, self.col.g) << 8) | self.col.b;
        return c;
    }
    pub fn toNormOpacity(self: SvgColorGroup) f32 {
        const op: f32 = @as(f32, @floatFromInt(self.col.a)) / 255.0;
        return op;
    }
};
/// Effective triangle.
///  Holds a reference to the texture if any.
///  Otherwise the color is dealt with in a SvgColorGroup.
pub const SvgTriangle = struct {
    p1: dvui.Point,
    p2: dvui.Point,
    p3: dvui.Point,

    tex_info: ?TexInfo,

    const TexInfo = struct {
        // Pattern id to link to, i.e. pattern="url(#p{pattern_id})"
        pattern_id: u24,
        // Filter id to link to, i.e. filter="url(#f{filter_id})"
        filter_id: u32,
    };
};

/// Represent a <pattern> tag.
///  Each textured triangle has to refer one.
pub const SvgPattern = struct {
    /// Id of the <pattern>, match the triangle_id using it in this frame.
    id: u24,
    /// Allow to link to a texture, i.e. the <image> tag.
    texture: SvgTexture,

    width: u32,
    height: u32,
    a: f32,
    b: f32,
    c: f32,
    d: f32,
    e: f32,
    f: f32,
};
/// Represent a <filter> tag.
///  The packed struct allow easy conversion to u32 that
///  acts as a id for the filter as well as the actual content
///  of the <feColorMatrix>
pub const SvgFilter = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn fromCol(color: dvui.Color) SvgFilter {
        return SvgFilter{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }
    pub fn toId(self: SvgFilter) u32 {
        const val: u32 = @bitCast(self);
        return val;
    }

    pub fn rNorm(self: SvgFilter) f32 {
        return @as(f32, @floatFromInt(self.r)) / 255.0;
    }
    pub fn gNorm(self: SvgFilter) f32 {
        return @as(f32, @floatFromInt(self.g)) / 255.0;
    }
    pub fn bNorm(self: SvgFilter) f32 {
        return @as(f32, @floatFromInt(self.b)) / 255.0;
    }
    pub fn aNorm(self: SvgFilter) f32 {
        return @as(f32, @floatFromInt(self.a)) / 255.0;
    }
};
/// Represent a <clipPath> tag.
///  Batch on triangle use ref to this via SvgClipGroup
pub const SvgClippath = struct {
    rect: dvui.Rect,
    /// clipPath id, corresponds to `clipr_count`, per frame.
    id: u12,
};
/// Hold info for a texture.
///  Texture itself is dumped as png file, or embedded in base64 encoding.
///  Each texture is used multiple times in `SvgPattern`, so needs to have unique id.
pub const SvgTexture = struct {
    frame_id: u8,
    texture_create_id: u12,

    const filename_template = "f{X:02}-{X:03}.png";
    // To keep in sync with string below.
    const filename_len = filename_template.len - 4 - 3;
    /// Prints the filename in buf.
    /// buf must be at least [`filename_len`]u8
    pub fn filenamePrint(self: SvgTexture, buf: []u8) void {
        std.debug.assert(buf.len == filename_len);
        _ = std.fmt.bufPrint(
            buf,
            filename_template,
            .{ self.frame_id, self.texture_create_id },
        ) catch unreachable;
    }

    pub fn toId(self: SvgTexture) u20 {
        return @as(u20, self.frame_id) << 12 | self.texture_create_id;
    }
    pub fn fromId(id: u20) SvgTexture {
        return SvgTexture{ .frame_id = @intCast((id >> 12) & 0xFF), .texture_create_id = @intCast(id & 0xFFF) };
    }

    // Dirty cast : Don't really need a pointer here, just returning the id
    // casted so it fits the existing API.
    pub fn toPtr(self: SvgTexture) *anyopaque {
        // Ptr cannot be NULL, so add some stuff above
        const id: usize = @intCast(self.toId());
        return @ptrFromInt(0xACF00000 | id);
    }
    // Dirty cast : Just get back my ID. I know it's u20
    pub fn fromPtr(ptr: *anyopaque) SvgTexture {
        const int_ptr = @intFromPtr(ptr);
        const id: u20 = @intCast(0xFFFFF & int_ptr);
        return SvgTexture{
            .frame_id = @intCast((id >> 12) & 0xFF),
            .texture_create_id = @intCast(id & 0xFFF),
        };
    }
};

pub const SvgCircle = struct { // for debug function, left aside for now
};

pub fn initWindow(options: InitOptions) !SvgBackend {
    std.fs.cwd().makeDir(render_dir) catch |err| {
        if (err != std.fs.Dir.MakeError.PathAlreadyExists) {
            log.warn("error creating `{s}` folder : {!}\n", .{ render_dir, err });
            unreachable;
        }
    };
    if (empty_render_folder) {
        var dir = std.fs.cwd().openDir(render_dir, .{ .iterate = true }) catch unreachable;
        defer dir.close();
        // Iterate through directory entries
        var dir_iterator = dir.iterate();
        while (dir_iterator.next() catch unreachable) |entry| {
            if (entry.kind == .file) {
                if (std.mem.startsWith(u8, entry.name, "frame") and (std.mem.endsWith(u8, entry.name, ".svg") or
                    std.mem.endsWith(u8, entry.name, ".png")))
                {
                    dir.deleteFile(entry.name) catch unreachable;
                }
            }
        }
    }
    return SvgBackend{
        .size = options.size,
        .alloc = options.allocator,
    };
}
/// Not used for now, kept for mirroring other backend API
pub fn deinit(_: *SvgBackend) void {}

pub fn backend(self: *SvgBackend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

/// Get monotonic nanosecond timestamp. Doesn't have to be system time.
pub fn nanoTime(_: *SvgBackend) i128 {
    return std.time.nanoTimestamp();
}
/// Sleep for nanoseconds.
pub fn sleep(_: *SvgBackend, ns: u64) void {
    std.time.sleep(ns);
}

/// Called by dvui during `dvui.Window.begin`, so prior to any dvui
/// rendering.  Use to setup anything needed for this frame.  The arena
/// arg is cleared before `dvui.Window.begin` is called next, useful for any
/// temporary allocations needed only for this frame.
pub fn begin(self: *SvgBackend, arena: std.mem.Allocator) void {
    self.arena = arena;

    self.svg_patterns = std.ArrayListUnmanaged(SvgPattern){};
    self.svg_filters = std.AutoHashMapUnmanaged(SvgFilter, void){};
    self.svg_clippaths = std.ArrayListUnmanaged(SvgClippath){};
    self.svg_graphics = std.ArrayListUnmanaged(SvgGraphics){};
}
/// Called during `dvui.Window.end` before freeing any memory for the current frame.
pub fn end(self: *SvgBackend) void {
    if (self.frame_count >= max_frame) {
        log.warn("SvgBackend.max_frame reached ({d}). not generating images anymore", .{max_frame});
        return;
    }

    const tmpl = render_dir ++ "frame{X:02}.svg";
    var buf: [tmpl.len - 4]u8 = undefined;
    const svg_file = std.fmt.bufPrint(&buf, tmpl, .{self.frame_count}) catch unreachable;

    const file = std.fs.cwd().createFile(svg_file, .{}) catch {
        log.warn("Unable to create {s}\n", .{svg_file});
        return;
    };
    defer log.info("{s} written disk", .{svg_file});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    var bufwriter = buffered.writer();

    bufwriter.print(
        \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        \\<svg
        \\    viewBox="0 0 {d} {d}" xmlns="http://www.w3.org/2000/svg"
        \\>
        \\<rect width="100%" height="100%" fill="black"/>
        \\
    , .{ self.size.w, self.size.h }) catch unreachable;

    bufwriter.print("<defs>\n", .{}) catch unreachable;
    for (self.svg_patterns.items) |p| {
        var png_file_name: [SvgTexture.filename_len]u8 = undefined;
        p.texture.filenamePrint(&png_file_name);
        bufwriter.print(
            \\  <pattern width="{d}" height="{d}"
            \\     patternUnits="userSpaceOnUse"
            \\     patternTransform="matrix({d} {d} {d} {d} {d} {d})"
            \\     id="p{X}">
            \\     <image href="{s}"/>
            \\  </pattern>
            \\
        , .{
            p.width, p.height,      p.a, p.b, p.c, p.d, p.e, p.f,
            p.id,    png_file_name,
        }) catch unreachable;
    }
    var filter_iter = self.svg_filters.keyIterator();
    while (filter_iter.next()) |f| {
        bufwriter.print(
            \\  <filter id="f{X}"
            \\    style="color-interpolation-filters:sRGB;">
            \\      <feColorMatrix type="matrix" values="
            \\        {d} 0 0 0 0
            \\        0 {d} 0 0 0
            \\        0 0 {d} 0 0
            \\        0 0 0 {d} 0 "/>
            \\  </filter>
            \\
        , .{ f.toId(), f.rNorm(), f.gNorm(), f.bNorm(), f.aNorm() }) catch unreachable;
    }
    for (self.svg_clippaths.items) |cp| {
        bufwriter.print(
            \\  <clipPath id="c{X}">
            \\    <rect x="{d}" y="{d}" width="{d}" height="{d}" fill="none"/>
            \\  </clipPath>
            \\
        , .{ cp.id, cp.rect.x, cp.rect.y, cp.rect.w, cp.rect.h }) catch unreachable;
    }
    bufwriter.print("</defs>\n", .{}) catch unreachable;

    for (self.svg_graphics.items) |graph_el| {
        switch (graph_el) {
            .triangle => |t| {
                bufwriter.print(
                    \\  <polygon points="{d},{d} {d},{d} {d},{d}"
                , .{ t.p1.x, t.p1.y, t.p2.x, t.p2.y, t.p3.x, t.p3.y }) catch unreachable;
                if (t.tex_info) |tex_info| {
                    bufwriter.print(
                        \\ fill="url(#p{X})" filter="url(#f{X})" 
                    , .{
                        tex_info.pattern_id, tex_info.filter_id,
                    }) catch unreachable;
                }
                _ = bufwriter.write("/>\n") catch unreachable; // closing <polygon
            },
            .color_group => |col_g| {
                bufwriter.print(
                    "<g fill=\"#{x:06}\" fill-opacity=\"{d}\">\n",
                    .{ col_g.toU24Col(), col_g.toNormOpacity() },
                ) catch unreachable;
            },
            .clip_group => |clip_g| {
                bufwriter.print("<g clip-path=\"url(#c{X})\">\n", .{clip_g.id}) catch unreachable;
            },
            .close_group => {
                _ = bufwriter.write("</g>\n") catch unreachable;
            },
        }
    }

    _ = bufwriter.write("</svg>") catch unreachable;
    buffered.flush() catch unreachable;

    self.frame_count += 1;
    self.texture_count = 0;
    self.triangle_count = 0;
    self.clipr_count = 0;
}

/// Return size of the window in physical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 600x400.
pub fn pixelSize(self: *SvgBackend) dvui.Size {
    return self.size;
}
/// Return size of the window in logical pixels.  For a 300x200 retina
/// window (so actually 600x400), this should return 300x200.
pub fn windowSize(self: *SvgBackend) dvui.Size {
    return self.size;
}
/// Return the detected additional scaling.  This represents the user's
/// additional display scaling (usually set in their window system's
/// settings).  Currently only called during Window.init(), so currently
/// this sets the initial content scale.
pub fn contentScale(_: *SvgBackend) f32 {
    return 1;
}

fn computePatternMatrix(v1: Vertex, v2: Vertex, v3: Vertex, trx_width: u32, trx_height: u32, pattern: *SvgPattern) void {
    // Transformation matrix in svg does :
    // newX = a * oldX + c * oldY + e
    // newY = b * oldX + d * oldY + f
    // Maybe I could make the assumption that v1.uv is always top-left of the bounding box, but in doubt I go for the general case directly.
    // (which turned out to be a bit more painful to compute than expected)

    // First we consider uv in texture pixel coordinates
    // This are the "old" position
    const txr_size: @Vector(2, f32) = .{ @as(f32, @floatFromInt(trx_width)), @as(f32, @floatFromInt(trx_height)) };
    const x1, const y1 = v1.uv * txr_size;
    const x2, const y2 = v2.uv * txr_size;
    const x3, const y3 = v3.uv * txr_size;

    // "New" positions
    const nx: @Vector(3, f32) = .{ v1.pos.x, v2.pos.x, v3.pos.x };
    const ny: @Vector(3, f32) = .{ v1.pos.y, v2.pos.y, v3.pos.y };
    // solving a,b,c,d,e,f
    // Batch the multiplication for more compact code more than runtime perf
    const ox: @Vector(3, f32) = .{ x1, x2, x3 };
    const ys: @Vector(3, f32) = .{ y3 - y2, y1 - y3, y2 - y1 };
    // compute a
    const a_num_v = ys * nx;
    const a_num = a_num_v[0] + a_num_v[1] + a_num_v[2];
    const a_den_v = ys * ox;
    const a_den = a_den_v[0] + a_den_v[1] + a_den_v[2];
    const a = a_num / a_den;
    // compute b
    const b_num_v = ys * ny;
    const b_num = b_num_v[0] + b_num_v[1] + b_num_v[2];
    const b_den_v = ys * ox;
    const b_den = b_den_v[0] + b_den_v[1] + b_den_v[2];
    const b = b_num / b_den;
    // compute c & d
    const c = (nx[1] - nx[0] + a * (x1 - x2)) / (y2 - y1);
    const d = (ny[1] - ny[0] + b * (x1 - x2)) / (y2 - y1);
    // compute e & f
    const e = nx[0] - x1 * a - y1 * c;
    const f = ny[0] - x1 * b - y1 * d;

    pattern.a = a;
    pattern.b = b;
    pattern.c = c;
    pattern.d = d;
    pattern.e = e;
    pattern.f = f;
}

/// Render a triangle list using the idx indexes into the vtx vertexes
/// clipped to to clipr (if given).  Vertex positions and clipr are in
/// physical pixels.  If texture is given, the vertexes uv coords are
/// normalized (0-1).
pub fn drawClippedTriangles(self: *SvgBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, clipr: ?dvui.Rect) void {
    if (clipr) |cr| {
        self.svg_clippaths.append(
            self.arena,
            SvgClippath{ .id = self.clipr_count, .rect = cr },
        ) catch unreachable;
        self.svg_graphics.append(
            self.arena,
            SvgGraphics{ .clip_group = SvgClipGroup{ .id = self.clipr_count } },
        ) catch unreachable;
        self.clipr_count += 1;
    }

    var last_vtx_color: ?dvui.Color = null;
    var i: usize = 0;
    while (i < idx.len) : (i += 3) {
        const v1, const v2, const v3 = .{ vtx[idx[i]], vtx[idx[i + 1]], vtx[idx[i + 2]] };

        var tex_info: ?SvgTriangle.TexInfo = null;
        if (texture) |txr| {
            const filter = SvgFilter.fromCol(v3.col);
            self.svg_filters.put(self.arena, filter, {}) catch unreachable;

            tex_info = SvgTriangle.TexInfo{
                .pattern_id = self.triangle_count,
                .filter_id = filter.toId(),
            };
            var pattern = SvgPattern{
                .id = self.triangle_count,
                .texture = SvgTexture.fromPtr(txr.ptr),
                .width = txr.width,
                .height = txr.height,
                .a = undefined,
                .b = undefined,
                .c = undefined,
                .d = undefined,
                .e = undefined,
                .f = undefined,
            };
            computePatternMatrix(v1, v2, v3, txr.width, txr.height, &pattern);
            self.svg_patterns.append(self.arena, pattern) catch unreachable;
        } else {
            // If I have no texture, it means I need to emit a color group instead
            // (in textured version, the vertex's color is express with a <filter>)
            if (last_vtx_color) |last_color| {
                if (last_color.toU32() != v3.col.toU32()) {
                    self.svg_graphics.append(self.arena, SvgGraphics{ .close_group = {} }) catch unreachable;
                    self.svg_graphics.append(self.arena, SvgGraphics{
                        .color_group = SvgColorGroup{ .col = last_color },
                    }) catch unreachable;
                }
            } else {
                self.svg_graphics.append(self.arena, SvgGraphics{
                    .color_group = SvgColorGroup{ .col = v3.col },
                }) catch unreachable;
                last_vtx_color = v3.col;
            }
        }
        const triangle = SvgTriangle{
            .p1 = v1.pos,
            .p2 = v2.pos,
            .p3 = v3.pos,
            .tex_info = tex_info,
        };
        self.svg_graphics.append(self.arena, SvgGraphics{ .triangle = triangle }) catch unreachable;

        self.triangle_count += 1;
    }
    if (last_vtx_color) |_| {
        self.svg_graphics.append(self.arena, SvgGraphics{ .close_group = {} }) catch unreachable;
    }
    if (clipr) |_| {
        self.svg_graphics.append(self.arena, SvgGraphics{ .close_group = {} }) catch unreachable;
    }
}

/// Create a texture from the given pixels in RGBA.  The returned
/// pointer is what will later be passed to drawClippedTriangles.
pub fn textureCreate(self: *SvgBackend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture {
    _ = interpolation; // autofix

    const texture = SvgTexture{
        .frame_id = self.frame_count,
        .texture_create_id = self.texture_count,
    };

    const png_bytes = dvui.pngEncode(self.arena, pixels[0 .. width * height * 4], width, height, .{ .resolution = null }) catch unreachable;

    var png_file_path: [render_dir.len + SvgTexture.filename_len]u8 = undefined;
    png_file_path[0..render_dir.len].* = render_dir.*;
    texture.filenamePrint(png_file_path[render_dir.len..png_file_path.len]);

    const file = std.fs.cwd().createFile(&png_file_path, .{}) catch unreachable;
    defer file.close();
    file.writeAll(png_bytes) catch unreachable;

    self.texture_count += 1;

    return dvui.Texture{ .ptr = texture.toPtr(), .height = height, .width = width };
}
/// Convert texture target made with `textureCreateTarget` into return texture
/// as if made by `textureCreate`.  After this call, texture target will not be
/// used by dvui.
pub fn textureFromTarget(_: *SvgBackend, texture: dvui.TextureTarget) dvui.Texture {
    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height };
}
/// Destroy texture that was previously made with textureCreate() or
/// textureFromTarget().  After this call, this texture pointer will not
/// be used by dvui.
pub fn textureDestroy(_: *SvgBackend, _: dvui.Texture) void {
    // Nothing to destroy, I pass and ID around.
}

/// Create a `dvui.Texture` that can be rendered to with `renderTarget`.  The
/// returned pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreateTarget(_: *SvgBackend, _: u32, _: u32, _: dvui.enums.TextureInterpolation) error{ OutOfMemory, TextureCreate }!dvui.TextureTarget {
    return error.TextureCreate;
}
/// Read pixel data (RGBA) from `texture` into `pixels_out`.
pub fn textureReadTarget(_: *SvgBackend, texture: dvui.TextureTarget, pixels: [*]u8) error{TextureRead}!void {
    const ptr: [*]const u8 = @ptrCast(texture.ptr);
    @memcpy(pixels, ptr[0..(texture.width * texture.height * 4)]);
}
/// Render future `drawClippedTriangles` to the passed `texture` (or screen
/// if null).
pub fn renderTarget(self: *SvgBackend, texture: ?dvui.TextureTarget) void {
    _ = self; // autofix
    _ = texture; // autofix
}

/// Get clipboard content (text only)
pub fn clipboardText(_: *SvgBackend) error{OutOfMemory}![]const u8 {
    return "";
}
/// Set clipboard content (text only)
pub fn clipboardTextSet(self: *SvgBackend, text: []const u8) error{OutOfMemory}!void {
    _ = self; // autofix
    _ = text; // autofix
}

/// Open URL in system browser
pub fn openURL(self: *SvgBackend, url: []const u8) error{OutOfMemory}!void {
    _ = self; // autofix
    _ = url; // autofix
}
/// Called by dvui.refresh() when it is called from a background
/// thread.  Used to wake up the gui thread.  It only has effect if you
/// are using waitTime() or some other method of waiting until a new
/// event comes in.
pub fn refresh(self: *SvgBackend) void {
    _ = self; // autofix
}

const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
const Vertex = dvui.Vertex;

const log = std.log.scoped(.dvui_svg_backend);
const print = std.debug.print;
