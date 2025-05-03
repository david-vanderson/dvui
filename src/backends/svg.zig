//! This Backend that dumps SVG file for each frame.
//! This is intended for test and debug purpose, as well as images generation.
//!
//! By default, each frame will result in a single file in "cwd()/svg_render".
//! For generating extra debug files, and other customization, see `SvgRenderOptions`
//!
//! The generated svg files are trying to be a bit compact but still human readable.
//! The top of the file has one huge `<defs></defs>` section, and after that all the
//! triangles are batched by group of color/textures.
//!
//! The triangles batches and/or the relevant debug elements are as much as possible
//! groupped such that if you explore the file in and editor like inkscape you can
//! manipulate the blocks nicely.
//!

// TODO : check other function of dvui API to see if I miss something regarding textures

// TODO : find the nice API for rendering only some frames (snapshot style)
// TODO : check how integration with testing backend could go.

/// Size of the resulting svg (aka window size)
size: dvui.Size,

/// short lived allocator for current frame. (passed in `dvui.begin`)
arena: std.mem.Allocator = undefined,

/// long lived allocator, for e.g. textures. (passed in initWindow by client code)
alloc: std.mem.Allocator = undefined,

// Count frames to emit frameXX.svg
// Max 255 frames, fair enough
frame_count: u8 = 0,
// Count textures to emit frameXX-XXX.png
// Max 4096 texture per frame, seems enough and print nicely in 3 chars
texture_count: u12 = 0,
// Count each triangle per frame. Reset for each frame.
// u24 prints nicely in 6 chars
// ~16million triangle per frame. Probably more than enough
triangle_count: u24 = 0,
// Count each clipping rect per frame
// Max 4096 clipr per frame, prints in 3 chars, same than texture.
clipr_count: u12 = 0,
// Count each call to drawClippedTriangles with a texture
debug_texture_count: if (render_opts.emit_debug_textures) |_| u24 else u0 = 0,

svg_patterns: std.ArrayListUnmanaged(SvgPattern) = undefined,
svg_filters: std.AutoHashMapUnmanaged(SvgFilter, void) = undefined,
svg_clippaths: std.ArrayListUnmanaged(SvgClippath) = undefined,
svg_graphics: std.ArrayListUnmanaged(SvgGraphics) = undefined,
svg_b64_streams: if (render_opts.emit_textures) void else std.AutoHashMapUnmanaged(SvgTexture, []const u8) = undefined,

pub const InitOptions = struct {
    // Long lived allocator needed to keep the name of the textures from frame to frame.
    allocator: std.mem.Allocator,
    /// The size of the window we can render to
    size: dvui.Size,
};

/// Allow client code to custimize some of the backend's behaviour.
///
/// For this, the root file (where the `main()` function lives) must declare
/// ``` zig
/// pub const svg_render_options = SvgRenderOptions{
///     .render_dir = "my_render_dir_path",
///     ...
/// };
/// ```
/// Note that some debug features might result in difficult to manage files if the rendered
/// layout is a bit complex (think demo window) e.g. :
/// - `emit_debug_textures` creates a big amount of files.
/// - `debughl_vertexes` creates huge svg frame file that might kill your svg viewer.
///
pub const SvgRenderOptions = struct {
    /// Stop output files after that many frames to avoid accidentyl crazy big folders.
    max_frame: u8 = 25,
    /// If true, delete all previously emitted images (i.e. "f**.svg|png)
    empty_render_folder: bool = true,
    /// Folder to write files to, relative to current working directory
    render_dir: []const u8 = "svg_render",
    /// Specify a background color `<rect>` in the generated svg.
    /// If null (default), the background is transparent.
    /// This works for both the main sgv (frame) and the ones from `emit_debug_textures`
    draw_background: ?dvui.Color = null,
    /// If not `null`, triangle's edges will be drawn.
    /// The value is the stroke-width.
    ///
    /// It defaults to 0.5 as otherwise a small gap appears between the colored triangles.
    /// I'm not fully sure why this happens, but setting to `null` is a nice debug
    /// feature to better see how the triangles are drawn.
    /// For more explicit debugging of triangles, consider `debughl_edges` and `debughl_vertexes`.
    edges_width: ?f32 = 0.5,
    // If not null, the edges of the triangles will be drawn in that particular color
    // instead of the vertex color.
    //
    // For this to have an effect, `edges_width` must be set to a value.
    // Note that the color might not be respected on textured colors because they
    // apply an extra filter.
    debughl_edges: ?dvui.Color = null,
    /// If not `null`, draws circles at the position of each vertex.
    /// The value is the circle size.
    ///
    /// This can help for some low level debug. To help spotting the "direction" of the
    /// triangle, each 3 vertexes are respectively :
    /// - yellowish and slightly smaller
    /// - magentaish
    /// - cyanish and slightly bigger
    debughl_vertexes: ?f32 = null,
    /// If not `null`, stroke the empty and clockwise triangles in red.
    /// and emit a log warning for such triangles.
    ///
    /// The value is the stroke-width of the clockwise triangles.
    /// Empty ones will result in a circle of that size.
    debughl_no_ccw_triangles: ?f32 = null,
    /// If not `null`, stroke the clipping rects (as passed to drawClippedTriangles) in red.
    /// The value is the stroke-width of the rectangle.
    debughl_clipr: ?f32 = null,
    /// Do not apply the clipping rects passed to drawClippedTriangles.
    /// This is compatible with `debughl_clipr`, in which case the clip is drawn
    /// in red but doesn't hide anything.
    no_apply_clipr: bool = false,
    /// For each texture, emit the corresponding `.png` file, and link it
    /// in the svg instead of embedding a base64 encoded version.
    emit_textures: bool = false,
    /// Emit extra svg file for each texture, with the uv point for each
    /// vertex drawn on the texture.
    /// The value is a circle size (svg coordinates).
    ///
    /// This can help for some low level debug. To help spotting the "direction" of the
    /// triangle, each 3 vertexes are respectively :
    /// - yellowish and slightly smaller
    /// - magentaish
    /// - cyanish and slightly bigger
    emit_debug_textures: ?f32 = null,
    /// Emit a comment when closing the groups.
    /// Useful to debug the backend itself or for better readability in the svg.
    emit_close_group_comment: bool = false,
};
const root = @import("root");
const render_opts = if (@hasDecl(root, "svg_render_options"))
val: {
    if (@TypeOf(root.svg_render_options) != SvgRenderOptions) {
        @compileError("'svg_render_options' should be of 'SvgRenderOptions' type");
    }
    break :val root.svg_render_options;
} else SvgRenderOptions{};

pub const SvgBackend = @This();
pub const Context = *SvgBackend;
pub const kind: dvui.enums.Backend = .svg;

/// Generic struct for emitting graphics SVG tags
pub const SvgGraphics = union(enum) {
    clip_group: SvgClipGroup,
    color_group: SvgColorGroup,
    filter_group: SvgFilterGroup,
    // close group only needed content (so far at least) to debug the clip rect, because
    // I want to draw it after the triangle, when closing the group.
    // Otherwise, it's just `</g>` so doesn't carry metadata, but having distinct
    // groups still help to catch logic errors.
    group_close: union(enum) {
        clip_group: if (render_opts.debughl_clipr != null) SvgClipGroup else void,
        color_group: void,
        filter_group: void,
    },
    triangle: SvgTriangle,

    /// Simply wraps a SvgFilter
    ///  Corresponds to <g filter="#fXXXXXXXX">,
    ///  allowing to batch triangle using the same filter.
    pub const SvgFilterGroup = struct {
        filter: SvgFilter,
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
};
/// Effective triangle.
///  Holds a reference to the pattern_id if textured triangle.
///  The color is dealt with in a SvgColorGroup / SvgFilterGroup.
pub const SvgTriangle = struct {
    p1: dvui.Point,
    p2: dvui.Point,
    p3: dvui.Point,

    pattern_id: ?u24,
    filter_id: if (render_opts.debughl_vertexes != null) ?u32 else void,
};

/// Represent an <image> tag.
///   It's essentially a glorifield u20 id, that uniquely reference
///   a texture created by dvui, with convenience method to cast type.
pub const SvgTexture = struct {
    frame_id: u8,
    texture_create_id: u12,

    const filename_template = "f{X:02}-{X:03}.png";
    const filename_len = filename_template.len - 4 - 3;
    /// Returns filename for the texture
    pub fn filename(self: SvgTexture) [filename_len]u8 {
        var result: [filename_len]u8 = .{0} ** filename_len;
        _ = std.fmt.bufPrint(
            &result,
            filename_template,
            .{ self.frame_id, self.texture_create_id },
        ) catch unreachable;
        return result;
    }
    /// Same as `filename` but without extension.
    pub fn textId(self: SvgTexture) [filename_len - 4]u8 {
        var result: [filename_len - 4]u8 = .{0} ** (filename_len - 4);
        _ = std.fmt.bufPrint(
            &result,
            filename_template[0 .. filename_template.len - 4],
            .{ self.frame_id, self.texture_create_id },
        ) catch unreachable;
        return result;
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
/// Represent a <pattern> tag.
///  Each textured triangle has to refer one.
pub const SvgPattern = struct {
    /// Id of the <pattern>, match the triangle_id using it in this frame.
    id: u24,
    /// Allow to link to a texture, i.e. the <image> tag.
    texture_id: u20,

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

pub fn initWindow(options: InitOptions) !SvgBackend {
    std.fs.cwd().makeDir(render_opts.render_dir) catch |err| {
        if (err != std.fs.Dir.MakeError.PathAlreadyExists) {
            log.warn("error creating `{s}` folder : {!}\n", .{ render_opts.render_dir, err });
            unreachable;
        }
    };
    if (render_opts.empty_render_folder) {
        var dir = std.fs.cwd().openDir(render_opts.render_dir, .{ .iterate = true }) catch unreachable;
        defer dir.close();
        // Iterate through directory entries
        var dir_iterator = dir.iterate();
        while (dir_iterator.next() catch unreachable) |entry| {
            if (entry.kind == .file) {
                if (std.mem.startsWith(u8, entry.name, "f") and (std.mem.endsWith(u8, entry.name, ".svg") or
                    std.mem.endsWith(u8, entry.name, ".png")))
                {
                    dir.deleteFile(entry.name) catch unreachable;
                }
            }
        }
    }
    if (render_opts.emit_textures) {
        return SvgBackend{
            .size = options.size,
            .alloc = options.allocator,
        };
    } else {
        return SvgBackend{
            .size = options.size,
            .alloc = options.allocator,
            .svg_b64_streams = std.AutoHashMapUnmanaged(SvgTexture, []const u8){},
        };
    }
}
pub fn deinit(self: *SvgBackend) void {
    if (!render_opts.emit_textures) {
        self.svg_b64_streams.deinit(self.alloc);
    }
}

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

fn emitTriangle(bufwriter: anytype, t: SvgTriangle) void {
    bufwriter.print(
        \\  <polygon points="{d},{d} {d},{d} {d},{d}"
    , .{ t.p1.x, t.p1.y, t.p2.x, t.p2.y, t.p3.x, t.p3.y }) catch unreachable;
    if (t.pattern_id) |p| {
        bufwriter.print(" fill=\"url(#p{X})\"", .{p}) catch unreachable;
        if (render_opts.debughl_vertexes) |_| {
            if (t.filter_id) |filter_id| {
                bufwriter.print(" filter=\"url(#f{X})\"", .{filter_id}) catch unreachable;
            }
        }
    }

    if (render_opts.debughl_no_ccw_triangles) |hl_size| {
        const a = (t.p2.x - t.p1.x) * (t.p2.y + t.p1.y);
        const b = (t.p3.x - t.p2.x) * (t.p3.y + t.p2.y);
        const c = (t.p1.x - t.p3.x) * (t.p1.y + t.p3.y);
        if (a + b + c < 0) {
            bufwriter.print(
                \\ stroke="red" stroke-width="{d}"/>" 
                \\
            , .{hl_size}) catch unreachable;
            log.warn("clockwise triangle @{d},{d}\n", .{ t.p1.x, t.p1.y });
        } else if (a + b + c == 0) {
            bufwriter.print(
                \\/>
                \\  <circle cx="{d}" cy="{d}" r="{d}" fill="red"/>
                \\
            , .{ t.p1.x, t.p2.y, hl_size }) catch unreachable;
            log.warn("empty triangle @{d},{d}\n", .{ t.p1.x, t.p1.y });
        } else {
            _ = bufwriter.write("/>\n") catch unreachable;
        }
    } else {
        _ = bufwriter.write("/>\n") catch unreachable;
    }
}

fn emitTriangleAndVertexes(comptime dot_size: f32, bufwriter: anytype, t: SvgTriangle) void {
    // Do a sub-group for each triangle. Verbose but allow nice manipulation in inkscape
    bufwriter.print("  <g>\n", .{}) catch unreachable;

    emitTriangle(bufwriter, t);

    bufwriter.print(
        \\  <circle cx="{d}" cy="{d}" r="{d}" stroke="gold" stroke-width="{d}" stroke-opacity="0.6" fill="none"/>
        \\  <circle cx="{d}" cy="{d}" r="{d}" stroke="violet" stroke-width="{d}"  stroke-opacity="0.6" fill="none"/>
        \\  <circle cx="{d}" cy="{d}" r="{d}" stroke="turquoise" stroke-width="{d}" stroke-opacity="0.6" fill="none"/>
        \\  </g>
        \\
    , .{
        t.p1.x, t.p1.y, dot_size * 0.8, dot_size / 5,
        t.p2.x, t.p2.y, dot_size,       dot_size / 5,
        t.p3.x, t.p3.y, dot_size * 1.2, dot_size / 5,
    }) catch unreachable;
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
    if (self.frame_count >= render_opts.max_frame) {
        log.warn("SvgBackend.max_frame reached ({d}). not generating images anymore", .{render_opts.max_frame});
        return;
    }

    const filename_template = "frame{X:02}.svg";
    var filename: [filename_template.len - 4]u8 = undefined;
    _ = std.fmt.bufPrint(&filename, filename_template, .{self.frame_count}) catch unreachable;

    const dir = render_opts.render_dir;
    const svg_filepath = std.fs.path.join(self.arena, &.{ dir, &filename }) catch unreachable;

    const file = std.fs.cwd().createFile(svg_filepath, .{}) catch {
        log.warn("Unable to create {s}\n", .{svg_filepath});
        return;
    };
    defer log.info("{s} written disk", .{svg_filepath});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    var bufwriter = buffered.writer();

    bufwriter.print(
        \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
        \\<svg
        \\    viewBox="0 0 {d} {d}" xmlns="http://www.w3.org/2000/svg"
        \\>
        \\
    , .{ self.size.w, self.size.h }) catch unreachable;
    if (render_opts.edges_width) |w| {
        bufwriter.print(
            \\<style>
            \\  polygon {{
            \\    stroke-width: {d};
            \\    stroke-linejoin: round;
            \\  }}
            \\</style>
            \\
        , .{w}) catch unreachable;
    }
    if (render_opts.debughl_edges) |c| {
        bufwriter.print(
            \\<style>
            \\  polygon {{
            \\    stroke: {s};
            \\  }}
            \\</style>
            \\
        , .{c.toHexString() catch unreachable}) catch unreachable;
    }
    if (render_opts.draw_background) |background_col| {
        bufwriter.print(
            "<rect width=\"100%\" height=\"100%\" fill=\"{s}\"/>\n",
            .{background_col.toHexString() catch unreachable},
        ) catch unreachable;
    }

    bufwriter.print("<defs>\n", .{}) catch unreachable;

    for (self.svg_clippaths.items) |cp| {
        bufwriter.print(
            \\  <clipPath id="c{X}">
            \\    <rect x="{d}" y="{d}" width="{d}" height="{d}" fill="none"/>
            \\  </clipPath>
            \\
        , .{ cp.id, cp.rect.x, cp.rect.y, cp.rect.w, cp.rect.h }) catch unreachable;
        if (render_opts.debughl_clipr) |stroke_width| {
            // Emit a <rect> in the <defs> to be <use> later
            bufwriter.print(
                \\  <rect id="hlc{X}" x="{d}" y="{d}" width="{d}" height="{d}" stroke="red" stroke-width="{d}" fill="none"/>
                \\
            , .{ cp.id, cp.rect.x, cp.rect.y, cp.rect.w, cp.rect.h, stroke_width }) catch unreachable;
        }
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

    // Each triangle gets it's own <pattern> but only emit one <image> tag
    // for each different effective texture (i.e. unique png file)
    var unique_textures = std.AutoArrayHashMapUnmanaged(SvgTexture, void){};
    for (self.svg_patterns.items) |p| {
        const texture = SvgTexture.fromId(p.texture_id);
        bufwriter.print(
            \\  <pattern width="{d}" height="{d}"
            \\     patternUnits="userSpaceOnUse"
            \\     patternTransform="matrix({d} {d} {d} {d} {d} {d})"
            \\     id="p{X}">
            \\     <use href="#{s}"/>
            \\  </pattern>
            \\
        , .{
            p.width, p.height,         p.a, p.b, p.c, p.d, p.e, p.f,
            p.id,    texture.textId(),
        }) catch unreachable;
        unique_textures.put(self.arena, SvgTexture.fromId(p.texture_id), {}) catch unreachable;
    }
    var texture_iter = unique_textures.iterator();
    while (texture_iter.next()) |txr| {
        if (render_opts.emit_textures) {
            bufwriter.print(
                "  <image id=\"{s}\" href=\"{s}\"/>\n",
                .{ txr.key_ptr.textId(), txr.key_ptr.filename() },
            ) catch unreachable;
        } else {
            bufwriter.print(
                \\  <image id="{s}" href="data:image/png;base64,{s}"/>",
                \\
            ,
                .{ txr.key_ptr.*.textId(), self.svg_b64_streams.get(txr.key_ptr.*).? },
            ) catch unreachable;
            print("used {s} in frame{X}\n", .{ txr.key_ptr.*.filename(), self.frame_count });
        }
    }

    bufwriter.print("</defs>\n", .{}) catch unreachable;

    for (self.svg_graphics.items) |graph_el| {
        switch (graph_el) {
            .triangle => |t| {
                if (render_opts.debughl_vertexes) |dot_size| {
                    emitTriangleAndVertexes(dot_size, bufwriter, t);
                } else {
                    emitTriangle(bufwriter, t);
                }
            },
            .clip_group => |clip_g| {
                if (render_opts.no_apply_clipr) {
                    _ = bufwriter.write("<g>\n") catch unreachable;
                } else {
                    bufwriter.print("<g clip-path=\"url(#c{X})\">\n", .{clip_g.id}) catch unreachable;
                }
            },
            .color_group => |col_g| {
                bufwriter.print(
                    "<g fill=\"#{x:06}\" fill-opacity=\"{d}\"",
                    .{ col_g.toU24Col(), col_g.toNormOpacity() },
                ) catch unreachable;
                if (render_opts.edges_width) |_| {
                    // Only stroke color needed, stroke-width in document wide style.
                    bufwriter.print(
                        " stroke=\"#{x:06}\"",
                        .{col_g.toU24Col()},
                    ) catch unreachable;
                }
                _ = bufwriter.write(">\n") catch unreachable;
            },
            .filter_group => |filtr_group| {
                if (render_opts.debughl_vertexes) |_| {
                    // Cannot emit filter in the group in this case, because
                    // it override the color of the debug circles
                    bufwriter.print("<g>\n", .{}) catch unreachable;
                } else {
                    bufwriter.print(
                        "<g filter=\"url(#f{X})\">\n",
                        .{filtr_group.filter.toId()},
                    ) catch unreachable;
                }
            },
            .group_close => |group_close| {
                if (render_opts.debughl_clipr) |_| {
                    switch (group_close) {
                        .clip_group => |clip_g| {
                            bufwriter.print("<use href=\"#hlc{X}\"/>\n", .{clip_g.id}) catch unreachable;
                        },
                        .color_group, .filter_group => {},
                    }
                }
                if (render_opts.emit_close_group_comment) {
                    switch (group_close) {
                        .color_group => {
                            _ = bufwriter.write("</g><!--closing color group-->\n") catch unreachable;
                        },
                        .clip_group => {
                            _ = bufwriter.write("</g><!--closing clip group-->\n") catch unreachable;
                        },
                        .filter_group => {
                            _ = bufwriter.write("</g><!--closing filter group-->\n") catch unreachable;
                        },
                    }
                } else {
                    _ = bufwriter.write("</g>\n") catch unreachable;
                }
            },
        }
    }

    _ = bufwriter.write("</svg>") catch unreachable;
    buffered.flush() catch unreachable;

    self.frame_count += 1;
    self.texture_count = 0;
    self.triangle_count = 0;
    self.clipr_count = 0;
    if (render_opts.emit_debug_textures) |_| {
        self.debug_texture_count = 0;
    }
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
            SvgGraphics{ .clip_group = .{ .id = self.clipr_count } },
        ) catch unreachable;
    }

    var last_vtx_color: ?dvui.Color = null;
    var last_vtx_filter: ?SvgFilter = null;
    var i: usize = 0;
    while (i < idx.len) : (i += 3) {
        const v1, const v2, const v3 = .{ vtx[idx[i]], vtx[idx[i + 1]], vtx[idx[i + 2]] };

        var cur_pattern_id: ?u24 = null;
        if (texture) |txr| {
            const filter = SvgFilter.fromCol(v3.col);
            cur_pattern_id = self.triangle_count;
            if (last_vtx_filter) |last_filter| {
                if (last_filter.toId() != filter.toId()) {
                    // Close previous group
                    self.svg_graphics.append(
                        self.arena,
                        SvgGraphics{ .group_close = .filter_group },
                    ) catch unreachable;
                    // Open a new one
                    self.svg_graphics.append(
                        self.arena,
                        SvgGraphics{ .filter_group = .{ .filter = filter } },
                    ) catch unreachable;
                }
            } else {
                // Only open a new one
                self.svg_graphics.append(
                    self.arena,
                    SvgGraphics{ .filter_group = .{ .filter = filter } },
                ) catch unreachable;
                last_vtx_filter = filter;
            }
            self.svg_filters.put(self.arena, filter, {}) catch unreachable;

            var pattern = SvgPattern{
                .id = self.triangle_count,
                .texture_id = SvgTexture.fromPtr(txr.ptr).toId(),
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
                    // Close previous group
                    self.svg_graphics.append(
                        self.arena,
                        SvgGraphics{ .group_close = .color_group },
                    ) catch unreachable;
                    // Open a new one
                    self.svg_graphics.append(
                        self.arena,
                        SvgGraphics{ .color_group = .{ .col = last_color } },
                    ) catch unreachable;
                }
            } else {
                // Only open a new one.
                self.svg_graphics.append(self.arena, SvgGraphics{
                    .color_group = .{ .col = v3.col },
                }) catch unreachable;
                last_vtx_color = v3.col;
            }
        }
        const triangle = SvgTriangle{
            .p1 = v1.pos,
            .p2 = v2.pos,
            .p3 = v3.pos,
            .pattern_id = cur_pattern_id,
            .filter_id = if (render_opts.debughl_vertexes != null) SvgFilter.fromCol(v3.col).toId() else {},
        };
        self.svg_graphics.append(self.arena, SvgGraphics{ .triangle = triangle }) catch unreachable;

        self.triangle_count += 1;
    }
    if (last_vtx_color) |_| {
        self.svg_graphics.append(
            self.arena,
            SvgGraphics{ .group_close = .color_group },
        ) catch unreachable;
    }
    if (last_vtx_filter) |_| {
        self.svg_graphics.append(self.arena, SvgGraphics{ .group_close = .filter_group }) catch unreachable;
    }
    if (clipr) |_| {
        self.svg_graphics.append(
            self.arena,
            SvgGraphics{ .group_close = .{
                .clip_group = if (render_opts.debughl_clipr != null) .{ .id = self.clipr_count } else {},
            } },
        ) catch unreachable;
        self.clipr_count += 1;
    }

    if (render_opts.emit_debug_textures) |dot_size| {
        if (texture) |txr| {
            const svg_texture = SvgTexture.fromPtr(txr.ptr);

            const dir = render_opts.render_dir;
            const filename = std.fmt.allocPrint(
                self.arena,
                "frame{x:02}-{s}-{X}.svg",
                .{ self.frame_count, svg_texture.textId(), self.debug_texture_count },
            ) catch unreachable;
            const filepath = std.fs.path.join(self.arena, &.{ dir, filename }) catch unreachable;
            const debug_trx_file = std.fs.cwd().createFile(filepath, .{}) catch unreachable;
            var buffered = std.io.bufferedWriter(debug_trx_file.writer());
            var bufwriter = buffered.writer();
            bufwriter.print(
                \\<?xml version="1.0" encoding="UTF-8" standalone="no"?>
                \\<svg
                \\    viewBox="0 0 {d} {d}" xmlns="http://www.w3.org/2000/svg"
                \\>
                \\
            , .{ txr.width, txr.height }) catch unreachable;
            if (render_opts.draw_background) |background_col| {
                bufwriter.print(
                    "<rect width=\"100%\" height=\"100%\" fill=\"{s}\"/>\n",
                    .{background_col.toHexString() catch unreachable},
                ) catch unreachable;
            }
            if (render_opts.emit_textures) {
                bufwriter.print(
                    "  <image id=\"{s}\" href=\"{s}\"/>\n",
                    .{ svg_texture.toId(), svg_texture.filename() },
                ) catch unreachable;
            } else {
                bufwriter.print(
                    "  <image id=\"{s}\" href=\"data:image/png;base64,{s}\"/>\n",
                    .{ svg_texture.textId(), self.svg_b64_streams.get(svg_texture).? },
                ) catch unreachable;
            }

            i = 0;
            while (i < idx.len) : (i += 3) {
                const v1, const v2, const v3 = .{ vtx[idx[i]], vtx[idx[i + 1]], vtx[idx[i + 2]] };
                const txr_size: @Vector(2, f32) = .{ @as(f32, @floatFromInt(txr.width)), @as(f32, @floatFromInt(txr.height)) };
                const x1, const y1 = v1.uv * txr_size;
                const x2, const y2 = v2.uv * txr_size;
                const x3, const y3 = v3.uv * txr_size;
                bufwriter.print(
                    \\<g>
                    \\  <circle cx="{d}" cy="{d}" r="{d}" stroke="gold" stroke-width="{d}" stroke-opacity="0.8" fill="none"/>
                    \\  <circle cx="{d}" cy="{d}" r="{d}" stroke="violet" stroke-width="{d}"  stroke-opacity="0.8" fill="none"/>
                    \\  <circle cx="{d}" cy="{d}" r="{d}" stroke="turquoise" stroke-width="{d}" stroke-opacity="0.8" fill="none"/>
                    \\</g>
                    \\
                , .{
                    x1, y1, dot_size * 0.8, dot_size / 5,
                    x2, y2, dot_size,       dot_size / 5,
                    x3, y3, dot_size * 1.2, dot_size / 5,
                }) catch unreachable;
            }
            bufwriter.writeAll("</svg>") catch unreachable;
            buffered.flush() catch unreachable;

            self.debug_texture_count += 1;
        }
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
    print("textureCreate {s}\n", .{texture.filename()});

    const png_bytes = dvui.pngEncode(self.arena, pixels[0 .. width * height * 4], width, height, .{ .resolution = null }) catch unreachable;

    if (render_opts.emit_textures) {
        const dir = render_opts.render_dir;
        const png_file_path = std.fs.path.join(self.alloc, &.{ dir, &texture.filename() }) catch unreachable;
        defer self.alloc.free(png_file_path);

        const file = std.fs.cwd().createFile(png_file_path, .{}) catch unreachable;
        defer file.close();
        file.writeAll(png_bytes) catch unreachable;
    } else {
        const b64encoder = std.base64.standard.Encoder;
        const stream = self.alloc.alloc(u8, b64encoder.calcSize(png_bytes.len)) catch unreachable;
        const res = b64encoder.encode(stream, png_bytes);
        std.debug.assert(stream.ptr == res.ptr);
        std.debug.assert(stream.len == res.len);
        self.svg_b64_streams.put(self.alloc, texture, stream) catch unreachable;
    }

    self.texture_count += 1;

    return dvui.Texture{ .ptr = texture.toPtr(), .height = height, .width = width };
}
/// Convert texture target made with `textureCreateTarget` into return texture
/// as if made by `textureCreate`.  After this call, texture target will not be
/// used by dvui.
pub fn textureFromTarget(_: *SvgBackend, texture: dvui.TextureTarget) dvui.Texture {
    print("textureFromTarget for {s}\n", .{SvgTexture.fromPtr(texture.ptr).filename()});

    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height };
}
/// Destroy texture that was previously made with textureCreate() or
/// textureFromTarget().  After this call, this texture pointer will not
/// be used by dvui.
pub fn textureDestroy(self: *SvgBackend, texture: dvui.Texture) void {
    if (render_opts.emit_textures) {
        // Nothing to destroy, I pass and ID around that directly represent the filename
        // and the file is already on the disk straight after TextureCreate
    } else {
        print("destroy {s}\n", .{SvgTexture.fromPtr(texture.ptr).filename()});

        const txr = SvgTexture.fromPtr(texture.ptr);
        const stream = self.svg_b64_streams.get(txr);
        self.alloc.free(stream.?);
    }
}

/// Create a `dvui.Texture` that can be rendered to with `renderTarget`.  The
/// returned pointer is what will later be passed to `drawClippedTriangles`.
pub fn textureCreateTarget(_: *SvgBackend, x: u32, y: u32, _: dvui.enums.TextureInterpolation) error{ OutOfMemory, TextureCreate }!dvui.TextureTarget {
    print("Called textureCreateTarget {}x{}\n", .{ x, y });
    return error.TextureCreate;
}
/// Read pixel data (RGBA) from `texture` into `pixels_out`.
pub fn textureReadTarget(_: *SvgBackend, texture: dvui.TextureTarget, pixels: [*]u8) error{TextureRead}!void {
    print("Called textureReadTarget with {s}\n", .{SvgTexture.fromPtr(texture.ptr).filename()});
    const ptr: [*]const u8 = @ptrCast(texture.ptr);
    @memcpy(pixels, ptr[0..(texture.width * texture.height * 4)]);
}
/// Render future `drawClippedTriangles` to the passed `texture` (or screen
/// if null).
pub fn renderTarget(self: *SvgBackend, texture: ?dvui.TextureTarget) void {
    if (texture) |txr| {
        print("Called renderTarget with {s}\n", .{SvgTexture.fromPtr(txr.ptr).filename()});
    } else {
        print("Called renderTarget without TextureTarget\n", .{});
    }
    _ = self; // autofix
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
