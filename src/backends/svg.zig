/// Size of the resulting svg (aka window size)
size: dvui.Size,
/// Buffer to store the frame's svg code. Each frame gets a different
svg_bytes: std.ArrayList(u8) = undefined,
/// If true, delete all previously emitted images (i.e. "frame**.svg|png)
empty_render_folder: bool = true,

/// Stop output files after that many frames to avoid accidentyl crazy big folders.
/// (and u13 prevents more than 4 digits counter in filenames)
max_frame: u13 = 10,

// temporary allocator for current frame.
arena: std.mem.Allocator = undefined,
alloc: std.mem.Allocator = undefined,

// counters for filenames
frame_count: u32 = 0,
texture_create_count: u32 = 0,
triangle_render_count: u32 = 0,

// TODO : Useful debug hooks, to expose somehow at compile time
/// Paint color dots on triangle's angles.
const debughl_vertex = false;
/// Paint empty triangles vertexes in red.
const debughl_no_ccw_triangle = false;
/// Outline clipping rects passed to drawClippedTriangles
const debughl_clipr = false;
/// Output texture files with uv points on.
const emit_debug_texture = false;

const render_dir = "svg_render";
// Caution : Don't change the template without taking care of dirty cast in drawClippedTriangles
const texture_file_template = render_dir ++ "/frame{d:04}-texture{d:04}.{s}";

pub const SvgBackend = @This();
pub const Context = *SvgBackend;
pub const kind: dvui.enums.Backend = .svg;
pub fn description() [:0]const u8 {
    return "svg";
}

pub const InitOptions = struct {
    // Long lived allocator needed to keep the name of the textures from frame to frame.
    allocator: std.mem.Allocator,
    /// The size of the window we can render to
    size: dvui.Size,
};
pub fn initWindow(options: InitOptions) !SvgBackend {
    std.fs.cwd().makeDir(render_dir) catch |err| {
        if (err != std.fs.Dir.MakeError.PathAlreadyExists) {
            log.warn("error creating `{s}` folder : {!}\n", .{ render_dir, err });
            unreachable;
        }
    };
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

/// Called by dvui during Window.begin(), so prior to any dvui
/// rendering.  Use to setup anything needed for this frame.  The arena
/// arg is cleared before begin is called next, useful for any temporary
/// allocations needed only for this frame.
pub fn begin(self: *SvgBackend, arena: std.mem.Allocator) void {
    self.arena = arena;
    self.svg_bytes = std.ArrayList(u8).init(arena);
    self.svg_bytes.writer().print(
        \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        \\<svg
        \\    viewBox="0 0 {d} {d}" xmlns="http://www.w3.org/2000/svg"
        \\>
        \\
    , .{ self.size.w, self.size.h }) catch unreachable;
    if (self.empty_render_folder) {
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
        self.empty_render_folder = false;
    }
}

/// Called by dvui during Window.end(), but currently unused by any
/// backends.  Probably will be removed.
// TODO : Change the doc of this method since it's usefull for this backend if merged
pub fn end(self: *SvgBackend) void {
    self.svg_bytes.appendSlice("</svg>") catch unreachable;

    if (self.frame_count >= self.max_frame) {
        log.warn("SvgBackend.max_frame reached ({d}). not generating images anymore", .{self.max_frame});
        return;
    } else {
        self.frame_count += 1;
    }

    const tmpl = render_dir ++ "/frame{d:04}.svg";
    var buf: [tmpl.len]u8 = undefined;
    const svg_file = std.fmt.bufPrint(&buf, tmpl, .{self.frame_count}) catch "render/frame.svg";

    const file = std.fs.cwd().createFile(svg_file, .{}) catch {
        log.warn("Unable to create {s}\n", .{svg_file});
        return;
    };
    defer log.info("{s} written disk", .{svg_file});
    defer file.close();
    file.writeAll(self.svg_bytes.items) catch unreachable;
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

/// Render a triangle list using the idx indexes into the vtx vertexes
/// clipped to to clipr (if given).  Vertex positions and clipr are in
/// physical pixels.  If texture is given, the vertexes uv coords are
/// normalized (0-1).
pub fn drawClippedTriangles(self: *SvgBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const u16, clipr: ?dvui.Rect) void {
    if (clipr) |clip| {
        self.svg_bytes.writer().print(
            \\<defs>
            \\  <clipPath id="clipr-t{d}">
            \\    <rect x="{d}" y="{d}" width="{d}" height="{d}" fille="none"/>
            \\  </clipPath>
            \\</defs>
            \\
        , .{ self.triangle_render_count, clip.x, clip.y, clip.w, clip.h }) catch unreachable;
    }

    var maybe_texture_id: ?[]const u8 = null;
    if (texture) |tx| {
        // Dirty cast : {d:04} in template result in 4 chars, 2x means 4char less in final string
        const png_file: []const u8 = @as([*]u8, @ptrCast(tx.ptr))[render_dir.len + 1 .. texture_file_template.len - 4];
        const texture_id = png_file[0 .. png_file.len - 4];
        maybe_texture_id = texture_id;

        var maybe_debug_txr_file: ?std.fs.File = null;
        if (emit_debug_texture) {
            const debug_txr_filename = std.fmt.allocPrint(
                self.arena,
                "{s}/{s}-t{d}-debug.{s}",
                .{ render_dir, texture_id, self.triangle_render_count, "svg" },
            ) catch unreachable;
            const debug_trx_file = std.fs.cwd().createFile(debug_txr_filename, .{}) catch {
                log.warn("Unable to create {s}\n", .{debug_txr_filename});
                return;
            };
            debug_trx_file.writer().print(
                \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
                \\<svg
                \\    viewBox="0 0 {d} {d}" xmlns="http://www.w3.org/2000/svg"
                \\>
                \\  <rect width="100%" height="100%" fill="black" />
                \\  <image href="{s}.png" width="{d}" height="{d}"/>
                \\
            , .{ tx.width, tx.height, texture_id, tx.width, tx.height }) catch unreachable;
            maybe_debug_txr_file = debug_trx_file;
        }
        defer {
            if (maybe_debug_txr_file) |debug_trx_file| {
                debug_trx_file.writeAll("</svg>") catch unreachable;
                debug_trx_file.close();
            }
        }

        // Need to emit a <pattern> tag for each triangle because svg doesn't allow to manipulate the patern inside the <polygon> tag.
        // <pattern> declaration must be within <defs> tags, so this require to iterate vertexes twice when we have a texture.
        // We also emit a <filter> def based on the vertex color.
        self.svg_bytes.writer().print("<defs>\n", .{}) catch unreachable;
        var i: usize = 0;
        while (i < idx.len) : (i += 3) {
            const v1, const v2, const v3 = .{ vtx[idx[i]], vtx[idx[i + 1]], vtx[idx[i + 2]] };
            // Transformation matrix in svg does :
            // newX = a * oldX + c * oldY + e
            // newY = b * oldX + d * oldY + f
            // Maybe I could make the assumption that v1.uv is always top-left of the bounding box, but in doubt I go for the general case directly.
            // (which turned out to be a bit more painful to compute than expected)

            // First we consider uv in texture pixel coordinates
            // This are the "old" position
            const txr_size: @Vector(2, f32) = .{ @as(f32, @floatFromInt(tx.width)), @as(f32, @floatFromInt(tx.height)) };
            const x1, const y1 = v1.uv * txr_size;
            const x2, const y2 = v2.uv * txr_size;
            const x3, const y3 = v3.uv * txr_size;

            if (maybe_debug_txr_file) |debug_trx_file| {
                debug_trx_file.writer().print(
                    \\<circle cx="{d}" cy="{d}" r="2" fill-opacity="0.6" fill="gold"/>
                    \\<circle cx="{d}" cy="{d}" r="3" fill-opacity="0.6" fill="orchid"/>
                    \\<circle cx="{d}" cy="{d}" r="4" fill-opacity="0.6" fill="aqua"/>
                    \\
                , .{ x1, y1, x2, y2, x3, y3 }) catch unreachable;
            }
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

            self.svg_bytes.writer().print(
                \\  <pattern width="{d}" height="{d}"
                \\     patternUnits="userSpaceOnUse"
                \\     patternTransform="matrix({d} {d} {d} {d} {d} {d})"
                \\     id="{s}-t{d}-{d}">
                \\     <image href="{s}"/>
                \\
            , .{
                tx.width,           tx.height,
                a,                  b,
                c,                  d,
                e,                  f,
                maybe_texture_id.?, self.triangle_render_count,
                i,                  png_file,
            }) catch unreachable;
            self.svg_bytes.writer().print("  </pattern>\n", .{}) catch unreachable;

            const r_norm = @as(f32, @floatFromInt(v3.col.r)) / 255.0;
            const g_norm = @as(f32, @floatFromInt(v3.col.g)) / 255.0;
            const b_norm = @as(f32, @floatFromInt(v3.col.b)) / 255.0;
            const opacity = @as(f32, @floatFromInt(v3.col.a)) / 255.0;
            self.svg_bytes.writer().print(
                \\  <filter id="color-{s}-t{d}-{d}"
                \\    style="color-interpolation-filters:sRGB;">
                \\      <feColorMatrix type="matrix" values="
                \\        {d:.2} 0 0 0 0
                \\        0 {d:.2} 0 0 0
                \\        0 0 {d:.2} 0 0
                \\        0 0 0 {d:.2} 0 "/>
                \\  </filter>
                \\
            , .{
                maybe_texture_id.?, self.triangle_render_count, i,
                r_norm,             g_norm,                     b_norm,
                opacity,
            }) catch unreachable;
        }
        self.svg_bytes.writer().print("</defs>\n\n", .{}) catch unreachable;
    }

    // actually draw the triangles. (i.e. emit <polygon> tags)
    var i: usize = 0;
    self.svg_bytes.writer().print("<g id=\"t-{d}\">\n", .{self.triangle_render_count}) catch unreachable;
    while (i < idx.len) : (i += 3) {
        const v1, const v2, const v3 = .{ vtx[idx[i]], vtx[idx[i + 1]], vtx[idx[i + 2]] };
        const opacity: f32 = @as(f32, @floatFromInt(v3.col.a)) / 255.0;
        var style: []const u8 = undefined;

        const a = (v2.pos.x - v1.pos.x) * (v2.pos.y + v1.pos.y);
        const b = (v3.pos.x - v2.pos.x) * (v3.pos.y + v2.pos.y);
        const c = (v1.pos.x - v3.pos.x) * (v1.pos.y + v3.pos.y);
        // FIXME : if all triangles are counter-clockwise, then
        // this assert would be legit but currently it's not the case in the demo window
        // std.debug.assert(a + b + c >= 0);

        if (maybe_texture_id) |texture_id| {
            style = std.fmt.allocPrint(
                self.arena,
                "stroke:none;fill:url(#{s}-t{d}-{d});filter:url(#color-{s}-t{d}-{d});fill-opacity:{d}",
                .{
                    texture_id, self.triangle_render_count, i,
                    texture_id, self.triangle_render_count, i,
                    opacity,
                },
            ) catch unreachable;
        } else {
            style = std.fmt.allocPrint(
                self.arena,
                "stroke:none;fill:#{x:02}{x:02}{x:02};fill-opacity:{d}",
                .{ v3.col.r, v3.col.g, v3.col.b, opacity },
            ) catch unreachable;
        }
        var triangle: []const u8 = undefined;
        if (clipr) |_| {
            triangle = std.fmt.allocPrint(self.arena,
                \\  <polygon points="{d:.2},{d:.2} {d:.2},{d:.2} {d:.2},{d:.2}" style="{s}" clip-path="url(#clipr-t{d})"/>
            , .{
                v1.pos.x, v1.pos.y, v2.pos.x, v2.pos.y,
                v3.pos.x, v3.pos.y, style,    self.triangle_render_count,
            }) catch unreachable;
        } else {
            triangle = std.fmt.allocPrint(self.arena,
                \\  <polygon points="{d:.2},{d:.2} {d:.2},{d:.2} {d:.2},{d:.2}" style="{s}"/>
            , .{
                v1.pos.x, v1.pos.y, v2.pos.x, v2.pos.y,
                v3.pos.x, v3.pos.y, style,
            }) catch unreachable;
        }
        if (debughl_no_ccw_triangle and a + b + c <= 0) {
            self.svg_bytes.writer().print(
                \\  <g id="no-ccw-t{d}">
                \\  {s}
                \\  <circle cx="{d}" cy="{d}" r="1" fill="red"/>
                \\  <circle cx="{d}" cy="{d}" r="1" fill="red"/>
                \\  <circle cx="{d}" cy="{d}" r="1" fill="red"/>
                \\  </g>
                \\
                \\
            , .{
                self.triangle_render_count, triangle, v1.pos.x, v1.pos.y,
                v2.pos.x,                   v2.pos.y, v3.pos.x, v3.pos.y,
            }) catch unreachable;
        } else if (debughl_vertex) {
            self.svg_bytes.writer().print(
                \\  <g>
                \\  {s}
                \\  <circle cx="{d}" cy="{d}" r=".15" fill="gold"/>
                \\  <circle cx="{d}" cy="{d}" r=".2" fill="orchid"/>
                \\  <circle cx="{d}" cy="{d}" r=".25" fill="aqua"/>
                \\  </g>
                \\
            , .{
                triangle, v1.pos.x, v1.pos.y, v2.pos.x,
                v2.pos.y, v3.pos.x, v3.pos.y,
            }) catch unreachable;
        } else {
            self.svg_bytes.writer().print("{s}\n", .{triangle}) catch unreachable;
        }
    }
    self.svg_bytes.writer().print("</g>\n", .{}) catch unreachable;
    self.triangle_render_count += 1;

    if (clipr) |clip| {
        if (debughl_clipr) {
            self.svg_bytes.writer().print(
                \\<rect id="clipr-hl-t{d}" x="{d}" y="{d}" width="{d}" height="{d}" stroke="red" fill="none"/>
                \\
            , .{ self.triangle_render_count, clip.x, clip.y, clip.w, clip.h }) catch unreachable;
        }
    }
}

/// Create a texture from the given pixels in RGBA.  The returned
/// pointer is what will later be passed to drawClippedTriangles.
pub fn textureCreate(self: *SvgBackend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture {
    _ = interpolation; // autofix

    // Simply dump the texture as png and use the filename as id for later

    const png_bytes = dvui.pngEncode(self.arena, pixels[0 .. width * height * 4], width, height, .{}) catch unreachable;

    // FIXME : don't remember why I alloc this one not with the arena...
    const png_filename = std.fmt.allocPrint(self.alloc, texture_file_template, .{ self.frame_count, self.texture_create_count, "png" }) catch "svg_render/texture.png";

    const file = std.fs.cwd().createFile(png_filename, .{}) catch unreachable;
    defer file.close();
    file.writeAll(png_bytes) catch unreachable;

    self.texture_create_count += 1;

    // Dirty cast : just pass the pointer to the filename.
    const png_ref: *anyopaque = @constCast(@ptrCast(png_filename.ptr));
    return dvui.Texture{ .ptr = png_ref, .height = height, .width = width };
}

/// Create a texture that can be rendered to with renderTarget().  The
/// returned pointer is what will later be passed to drawClippedTriangles.
pub fn textureCreateTarget(_: *SvgBackend, _: u32, _: u32, _: dvui.enums.TextureInterpolation) error{ OutOfMemory, TextureCreate }!dvui.TextureTarget {
    return error.TextureCreate;
}

/// Read pixel data (RGBA) from texture into pixel.
pub fn textureReadTarget(_: *SvgBackend, texture: dvui.TextureTarget, pixels: [*]u8) error{TextureRead}!void {
    const ptr: [*]const u8 = @ptrCast(texture.ptr);
    @memcpy(pixels, ptr[0..(texture.width * texture.height * 4)]);
}

/// Destroy texture that was previously made with textureCreate() or
/// textureFromTarget().  After this call, this texture pointer will not
/// be used by dvui.
pub fn textureDestroy(self: *SvgBackend, texture: dvui.Texture) void {
    _ = self; // autofix
    _ = texture; // autofix
}

pub fn textureFromTarget(_: *SvgBackend, texture: dvui.TextureTarget) dvui.Texture {
    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height };
}

/// Render future drawClippedTriangles() to the passed texture (or screen
/// if null).
pub fn renderTarget(_: *SvgBackend, _: ?dvui.TextureTarget) void {}

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
const log = std.log.scoped(.dvui_svg_backend);
