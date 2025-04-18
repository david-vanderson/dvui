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

// counters for filenames
frame_count: u32 = 0,
texture_create_count: u32 = 0,
triangle_render_count: u32 = 0,

// TODO : Useful debug hooks, to expose somehow at compile time
/// Paint color dots on triangle's angles.
const debughl_vertex = true;
/// Paint empty triangles vertexes in red.
const debughl_emtpy_triangle = true;
/// Output texture files with uv points on.
const emit_debug_texture = true;

const render_dir = "svg_render";
// Caution : Don't change the template without taking care of dirty cast in drawClippedTriangles
const texture_file_template = render_dir ++ "/frame{d:04}-texture{d:04}.{s}";

// FIXME : this global allocator is never freed, find a cleaner approach.
var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub const SvgBackend = @This();
pub const Context = *SvgBackend;
pub const kind: dvui.enums.Backend = .svg;
pub fn description() [:0]const u8 {
    return "svg";
}

// pub const InitOptions = struct {
//     /// The allocator used for temporary allocations used during init()
//     // allocator: std.mem.Allocator,
//     /// The size of the window we can render to
//     size: dvui.Size,
// };
// pub fn initWindow(options: InitOptions) !SvgBackend {
//     _ = options; // autofix

//     return SvgBackend{};
// }

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
        \\<rect width="100%" height="100%" fill="black" />
        \\
    , .{ self.size.w, self.size.h }) catch unreachable;
    print("---> \n", .{});
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
pub fn end(self: *SvgBackend) void {
    self.svg_bytes.appendSlice("</svg>") catch unreachable;
    print("<---\n", .{});

    if (self.frame_count >= self.max_frame) {
        log.warn("SvgBackend.max_frame reached ({d}). not rendering images anymore", .{self.max_frame});
        return;
    } else {
        self.frame_count += 1;
    }

    const tmpl = render_dir ++ "/frame{d:04}.svg";
    var buf: [tmpl.len]u8 = undefined;
    const svg_file = std.fmt.bufPrint(&buf, tmpl, .{self.frame_count}) catch "render/frame.svg";

    std.fs.cwd().makeDir(render_dir) catch |err| {
        if (err != std.fs.Dir.MakeError.PathAlreadyExists) {
            log.warn("error creating `{s}` folder : {!}\n", .{ render_dir, err });
            return;
        }
    };
    const file = std.fs.cwd().createFile(svg_file, .{}) catch {
        log.warn("Unable to create {s}\n", .{svg_file});
        return;
    };
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
    // TODO : ase clip rect when provided
    if (clipr) |clip| {
        print("CLIP : {}\n", .{clip});
    }
    print("drawClippedTriangles called : \n   {}vertices passed\n   {}idx passed\n", .{ vtx.len, idx.len });

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
                "{s}/{s}-{d}-debug.{s}",
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
        self.svg_bytes.writer().print("<defs>\n", .{}) catch unreachable;
        var i: usize = 0;
        while (i < idx.len) : (i += 3) {
            const v1, const v2, const v3 = .{ vtx[idx[i]], vtx[idx[i + 1]], vtx[idx[i + 2]] };

            if (maybe_debug_txr_file) |debug_trx_file| {
                debug_trx_file.writer().print(
                    \\<circle cx="{d}" cy="{d}" r="2" fill-opacity="0.6" fill="gold"/>
                    \\<circle cx="{d}" cy="{d}" r="3" fill-opacity="0.6" fill="orchid"/>
                    \\<circle cx="{d}" cy="{d}" r="4" fill-opacity="0.6" fill="aqua"/>
                    \\
                , .{
                    v1.uv[0] * @as(f32, @floatFromInt(tx.width)),
                    v1.uv[1] * @as(f32, @floatFromInt(tx.height)),
                    v2.uv[0] * @as(f32, @floatFromInt(tx.width)),
                    v2.uv[1] * @as(f32, @floatFromInt(tx.height)),
                    v3.uv[0] * @as(f32, @floatFromInt(tx.width)),
                    v3.uv[1] * @as(f32, @floatFromInt(tx.height)),
                }) catch unreachable;
            }

            // TODO :
            // 1) find the transformation
            //    It must be doable based on the 2x3 points I have,
            //    i.e. vx.uv[i] * @as(f32, @floatFromInt(..)) which are the triangles
            //    in texture coordinates. I have to move theses points with a matrix to
            //    the triangles in screen coordinates.
            // 2) the missing piece of the puzzle is how to make the text blue ?
            self.svg_bytes.writer().print(
                \\  <pattern id="{s}-{d}-{d}" patternUnits="objectBoundingBox"
                // \\    patternTransform="rotate(20) skewX(30) scale(1 0.5)"
                \\     patternTransform="translate({d} {d})"
                // FIXME : width/height must be set to size of the pattern's texture / size of triangle using the pattern
                // Otherwise the pattern is clipped to the size of the triangle using it and when
                // I translate it wrap around.
                // This would be easier with a rect....
                \\     width="100%" height="100%">
                \\    <image href="{s}" width="{d}" height="{d}"/>
                \\  </pattern>
                \\
            , .{
                maybe_texture_id.?,
                self.triangle_render_count,
                i,
                v1.uv[0],
                v1.uv[1],
                png_file,
                tx.width,
                tx.height,
            }) catch unreachable;
        }
        self.svg_bytes.writer().print("</defs>\n", .{}) catch unreachable;
    }

    // actually draw the triangles. (i.e. emit <polygon> tags)
    var i: usize = 0;
    while (i < idx.len) : (i += 3) {
        const v1, const v2, const v3 = .{ vtx[idx[i]], vtx[idx[i + 1]], vtx[idx[i + 2]] };
        const opacity: f32 = @as(f32, @floatFromInt(v3.col.a)) / 255.0;
        var style: []const u8 = undefined;

        const a = (v2.pos.x - v1.pos.x) * (v2.pos.y + v1.pos.y);
        const b = (v3.pos.x - v2.pos.x) * (v3.pos.y + v2.pos.y);
        const c = (v1.pos.x - v3.pos.x) * (v1.pos.y + v3.pos.y);
        // Sanity check : triangles are always counter-clockwise
        // When testing, spotted some empty triangles. I don't think they're legit,
        // so the assert allows it but I draw them in red (see debughl_emtpy_triangle)
        std.debug.assert(a + b + c >= 0);

        if (maybe_texture_id) |texture_id| {
            style = std.fmt.allocPrint(
                self.arena,
                "stroke:magenta;fill:url(#{s}-{d}-{d});fill-opacity:{d}",
                .{ texture_id, self.triangle_render_count, i, opacity },
            ) catch unreachable;
        } else {
            style = std.fmt.allocPrint(
                self.arena,
                "stroke:none;fill:#{x:02}{x:02}{x:02};fill-opacity:{d}",
                .{ v3.col.r, v3.col.g, v3.col.b, opacity },
            ) catch unreachable;
        }
        const triangle = std.fmt.allocPrint(self.arena,
            \\<polygon points="{d},{d} {d},{d} {d},{d}" style="{s}"/>
        , .{
            v1.pos.x, v1.pos.y, v2.pos.x, v2.pos.y,
            v3.pos.x, v3.pos.y, style,
        }) catch unreachable;
        if (debughl_emtpy_triangle and a + b + c == 0) {
            self.svg_bytes.writer().print(
                \\<g>
                \\{s}
                \\<circle cx="{d}" cy="{d}" r="1" fill="red"/>
                \\<circle cx="{d}" cy="{d}" r="1" fill="red"/>
                \\<circle cx="{d}" cy="{d}" r="1" fill="red"/>
                \\</g>
                \\
            , .{
                triangle, v1.pos.x, v1.pos.y, v2.pos.x,
                v2.pos.y, v3.pos.x, v3.pos.y,
            }) catch unreachable;
        } else if (debughl_vertex) {
            self.svg_bytes.writer().print(
                \\<g>
                \\{s}
                \\<circle cx="{d}" cy="{d}" r=".15" fill="gold"/>
                \\<circle cx="{d}" cy="{d}" r=".2" fill="orchid"/>
                \\<circle cx="{d}" cy="{d}" r=".25" fill="aqua"/>
                \\</g>
                \\
            , .{
                triangle, v1.pos.x, v1.pos.y, v2.pos.x,
                v2.pos.y, v3.pos.x, v3.pos.y,
            }) catch unreachable;
        } else {
            self.svg_bytes.writer().print("{s}\n", .{triangle}) catch unreachable;
        }
    }
    self.triangle_render_count += 1;
}

/// Create a texture from the given pixels in RGBA.  The returned
/// pointer is what will later be passed to drawClippedTriangles.
pub fn textureCreate(self: *SvgBackend, pixels: [*]u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) dvui.Texture {
    _ = interpolation; // autofix
    print("textureCreate called for {}x{} pixels\n", .{ width, height });

    // Dump a tga file because it's easy
    const header = [_]u8{
        0, // ID length
        0, // No color map
        2, // Uncompressed RGB
        0, 0, 0, 0, 0, // Color map specification (unused)
        0, 0, // X origin
        0, 0, // Y origin
        @as(u8, @truncate(width & 0xFF)), // Width low byte
        @as(u8, @truncate(width >> 8)), // Width high byte
        @as(u8, @truncate(height & 0xFF)), // Height low byte
        @as(u8, @truncate(height >> 8)), // Height high byte
        32, // 32 bits per pixel (ARGB)
        0b100000, // Image descriptor (b5 = 1 for origin at top left)
    };
    var buf: [texture_file_template.len]u8 = undefined;
    const tga_file = std.fmt.bufPrint(&buf, texture_file_template, .{ self.frame_count, self.texture_create_count, "tga" }) catch "render/texture.tga";

    const file = std.fs.cwd().createFile(tga_file, .{}) catch unreachable;
    defer file.close();
    file.writeAll(&header) catch unreachable;

    // FIXME : this does pain the letters, but all upside-down.
    // Maybe it's ok when passed into the image somehow ...
    var i: usize = 0;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const r, const g, const b, const a = .{ pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3] };
            // const res: u32 = @as(u32, r) + @as(u32, g) + @as(u32, b) + @as(u32, a);
            // if (last_printed != res) {
            //     print("{} {} {} {}\n", .{ r, g, b, a });
            //     last_printed = res;
            // }
            // const bgra = (@as(u32, b) << 24) | (@as(u32, g) << 16) | (@as(u32, r) << 8) | a;
            const argb = (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | b;
            file.writer().writeInt(u32, argb, .little) catch unreachable;
            i += 4;
        }
    }

    // convert to png with magik cause tga don't get embedded in svg file well
    // (and let's check if this works before putting effort in a png exporter)
    const png_file = std.fmt.allocPrint(gpa, texture_file_template, .{ self.frame_count, self.texture_create_count, "png" }) catch "svg_render/texture.png";
    const argv = [_][]const u8{ "magick", tga_file, png_file };
    var proc = std.process.Child.init(&argv, self.arena);
    proc.spawn() catch unreachable;
    const term = proc.wait() catch unreachable;
    if (term.Exited != 0) unreachable;
    std.fs.cwd().deleteFile(tga_file) catch unreachable;

    self.texture_create_count += 1;

    // Dirty cast : just pass the pointer to the filename.
    const png_ref: *anyopaque = @constCast(@ptrCast(png_file.ptr));
    return dvui.Texture{ .ptr = png_ref, .height = height, .width = width };
}

/// Create a texture that can be rendered to with renderTarget().  The
/// returned pointer is what will later be passed to drawClippedTriangles.
pub fn textureCreateTarget(self: *SvgBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) error{ OutOfMemory, TextureCreate }!dvui.Texture {
    _ = interpolation; // autofix
    print("textureCreateTarget called for {}x{} pixels\n", .{ width, height });
    return dvui.Texture{ .ptr = self, .height = height, .width = width };
}

/// Read pixel data (RGBA) from texture into pixel.
pub fn textureRead(self: *SvgBackend, texture: dvui.Texture, pixels_out: [*]u8) error{TextureRead}!void {
    _ = self; // autofix
    _ = pixels_out; // autofix
    print("textureRead called for {}\n", .{texture});
}

/// Destroy texture that was previously made with textureCreate() or
/// textureCreateTarget().  After this call, this texture pointer will not
/// be used by dvui.
pub fn textureDestroy(self: *SvgBackend, texture: dvui.Texture) void {
    _ = self; // autofix
    print("textureDestroy for {}\n", .{texture});
}

/// Render future drawClippedTriangles() to the passed texture (or screen
/// if null).
pub fn renderTarget(self: *SvgBackend, texture: ?dvui.Texture) void {
    _ = self; // autofix
    print("renderTarget for {any}\n", .{texture});
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
const print = std.debug.print;
const log = std.log.scoped(.dvui_svg_backend);
