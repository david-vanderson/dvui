pub const Target = struct {
    texture: ?Texture.Target,
    offset: Point.Physical,
    rendering: bool = true,

    /// Change where dvui renders.  Can pass output from `dvui.textureCreateTarget` or
    /// null for the screen.  Returns the previous target/offset.
    ///
    /// offset will be subtracted from all dvui rendering, useful as the point on
    /// the screen the texture will map to.
    ///
    /// Useful for caching expensive renders or to save a render for export.  See
    /// `Picture`.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn setAsCurrent(target: Target) Target {
        var cw = dvui.currentWindow();
        const ret = cw.render_target;
        cw.backend.renderTarget(target.texture) catch |err| {
            // TODO: This might be unrecoverable? Or brake rendering too badly?
            dvui.logError(@src(), err, "Failed to set render target", .{});
            return ret;
        };
        cw.render_target = target;
        return ret;
    }
};

/// Represents a deferred call to one of the render functions.  This is how
/// dvui defers rendering of floating windows so they render on top of widgets
/// that run later in the frame.
pub const RenderCommand = struct {
    clip: Rect.Physical,
    alpha: f32,
    snap: bool,
    kerning: bool,
    cmd: Command,

    pub const Command = union(enum) {
        text: TextOptions,
        texture: struct {
            tex: Texture,
            rs: RectScale,
            opts: TextureOptions,
        },
        pathFillConvex: struct {
            path: Path,
            opts: Path.FillConvexOptions,
        },
        pathStroke: struct {
            path: Path,
            opts: Path.StrokeOptions,
        },
        triangles: struct {
            tri: Triangles,
            tex: ?Texture,
        },
    };
};

/// Rendered `Triangles` taking in to account the current clip rect
/// and deferred rendering through render targets.
///
/// Expect that `dvui.Window.alpha` has already been applied.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderTriangles(triangles: Triangles, tex: ?Texture) Backend.GenericError!void {
    if (triangles.vertexes.len == 0) {
        return;
    }

    if (dvui.clipGet().empty()) {
        return;
    }

    const cw = dvui.currentWindow();

    if (!cw.render_target.rendering) {
        const tri_copy = try triangles.dupe(cw.arena());
        cw.addRenderCommand(.{ .triangles = .{ .tri = tri_copy, .tex = tex } }, false);
        return;
    }

    // expand clipping to full pixels before testing
    var clipping = dvui.clipGet();
    clipping.w = @max(0, @ceil(clipping.x - @floor(clipping.x) + clipping.w));
    clipping.x = @floor(clipping.x);
    clipping.h = @max(0, @ceil(clipping.y - @floor(clipping.y) + clipping.h));
    clipping.y = @floor(clipping.y);

    const clipr: ?Rect.Physical = if (triangles.bounds.clippedBy(clipping)) clipping.offsetNegPoint(cw.render_target.offset) else null;

    if (cw.render_target.offset.nonZero()) {
        const offset = cw.render_target.offset;
        for (triangles.vertexes) |*v| {
            v.pos = v.pos.diff(offset);
        }
    }

    try cw.backend.drawClippedTriangles(tex, triangles.vertexes, triangles.indices, clipr);
}

pub const TextOptions = struct {
    font: Font,
    text: []const u8,
    rs: RectScale,
    color: Color,
    background_color: ?Color = null,
    sel_start: ?usize = null,
    sel_end: ?usize = null,
    sel_color: ?Color = null,
    debug: bool = false,
    kerning: ?bool = null,
    kern_in: ?[]u32 = null,
};

/// Only renders a single line of text
///
/// Selection will be colored with the current themes accent color,
/// with the text color being set to the themes fill color.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderText(opts: TextOptions) Backend.GenericError!void {
    if (opts.rs.s == 0) return;
    if (opts.text.len == 0) return;
    if (dvui.clipGet().intersect(opts.rs.r).empty()) return;

    var cw = dvui.currentWindow();
    const utf8_text = try dvui.toUtf8(cw.lifo(), opts.text);
    defer if (opts.text.ptr != utf8_text.ptr) cw.lifo().free(utf8_text);

    if (!cw.render_target.rendering) {
        var opts_copy = opts;
        opts_copy.text = try cw.arena().dupe(u8, utf8_text);
        if (opts.kern_in) |ki| opts_copy.kern_in = try cw.arena().dupe(u32, ki);
        cw.addRenderCommand(.{ .text = opts_copy }, false);
        return;
    }

    const target_size = opts.font.size * opts.rs.s;
    const sized_font = opts.font.resize(target_size);

    // might get a slightly smaller font
    var fce = try cw.fonts.getOrCreate(cw.gpa, sized_font);

    // this must be synced with Font.textSizeEx()
    const target_fraction = if (cw.snap_to_pixels) 1.0 else target_size / fce.height;

    // make sure the cache has all the glyphs we need
    if (opts.kern_in == null) {
        // if kern_in is given, assume we already did this when measuring the text
        var utf8it = std.unicode.Utf8View.initUnchecked(utf8_text).iterator();
        while (utf8it.nextCodepoint()) |codepoint| {
            _ = try fce.glyphInfoGetOrReplacement(cw.gpa, codepoint);
        }
    }

    // Generate new texture atlas if needed to update glyph uv coords
    const texture_atlas = fce.getTextureAtlas(cw.gpa, cw.backend) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => {
            dvui.log.err("Could not get texture atlas for font {f}, text area marked in magenta, to display '{s}'", .{ opts.font.id, opts.text });
            opts.rs.r.fill(.{}, .{ .color = .magenta });
            return;
        },
    };

    // Over allocate the internal buffers assuming each byte is a character
    var builder = try dvui.Triangles.Builder.init(cw.lifo(), 4 * utf8_text.len, 6 * utf8_text.len);
    defer builder.deinit(cw.lifo());

    const col: Color.PMA = .fromColor(opts.color.opacity(cw.alpha));

    const x_start: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.x) else opts.rs.r.x;
    var x = x_start;
    var max_x = x_start;
    const y: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.y) else opts.rs.r.y;

    if (opts.debug) {
        dvui.log.debug("renderText x {d} y {d}\n", .{ x, y });
    }

    var sel_in: bool = false;
    var sel_start_x: f32 = x;
    var sel_end_x: f32 = x;
    var sel_max_y: f32 = y;
    var sel_start: usize = opts.sel_start orelse 0;
    sel_start = @min(sel_start, utf8_text.len);
    var sel_end: usize = opts.sel_end orelse 0;
    sel_end = @min(sel_end, utf8_text.len);
    // if we will definitely have a selected region or not
    const sel: bool = sel_start < sel_end;

    const atlas_size: Size = .{ .w = @floatFromInt(texture_atlas.width), .h = @floatFromInt(texture_atlas.height) };

    var bytes_seen: usize = 0;
    var last_codepoint: u32 = 0;

    const kerning: bool = opts.kerning orelse cw.kerning;
    var next_kern_idx: u32 = 0;
    var next_kern_byte: u32 = 0;
    if (opts.kern_in) |ki| {
        next_kern_byte = ki[next_kern_idx];
        next_kern_idx += 1;
    }

    var i: usize = 0;
    while (i < opts.text.len) {
        const cplen = std.unicode.utf8ByteSequenceLength(opts.text[i]) catch unreachable;
        const codepoint = std.unicode.utf8Decode(opts.text[i..][0..cplen]) catch unreachable;
        const gi = try fce.glyphInfoGetOrReplacement(cw.gpa, codepoint);

        if (kerning and last_codepoint != 0 and i >= next_kern_byte) {
            const kk = fce.kern(last_codepoint, codepoint);
            x += kk;

            if (opts.kern_in) |ki| {
                if (next_kern_idx < ki.len) {
                    next_kern_byte = ki[next_kern_idx];
                    next_kern_idx += 1;
                }
            }
        }

        i += cplen;
        last_codepoint = codepoint;

        if (x + gi.leftBearing * target_fraction < x_start) {
            // Glyph extends left of the start, like the first letter being
            // "j", which has a negative left bearing.
            //
            // Shift the whole line over so it starts at x_start.  textSize()
            // includes this extra space.

            //std.debug.print("moving x from {d} to {d}\n", .{ x, x_start - gi.leftBearing * target_fraction });
            x = x_start - gi.leftBearing * target_fraction;
        }

        const nextx = x + gi.advance * target_fraction;
        const leftx = x + gi.leftBearing * target_fraction;

        if (sel) {
            bytes_seen += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            if (!sel_in and bytes_seen > sel_start and bytes_seen <= sel_end) {
                // entering selection
                sel_in = true;
                sel_start_x = @min(x, leftx);
            } else if (sel_in and bytes_seen > sel_end) {
                // leaving selection
                sel_in = false;
            }

            if (sel_in) {
                // update selection
                sel_end_x = nextx;
            }
        }

        // don't output triangles for a zero-width glyph (space seems to be the only one)
        if (gi.w > 0) {
            const vtx_offset: u16 = @intCast(builder.vertexes.items.len);
            var v: Vertex = undefined;

            v.pos.x = leftx;
            v.pos.y = y + gi.topBearing * target_fraction;
            v.col = col;
            v.uv = gi.uv;
            builder.appendVertex(v);

            if (opts.debug) {
                dvui.log.debug(" - x {d} y {d}", .{ v.pos.x, v.pos.y });
            }

            if (opts.debug) {
                //log.debug("{d} pad {d} minx {d} maxx {d} miny {d} maxy {d} x {d} y {d}", .{ bytes_seen, pad, gi.minx, gi.maxx, gi.miny, gi.maxy, v.pos.x, v.pos.y });
                //log.debug("{d} pad {d} left {d} top {d} w {d} h {d} advance {d}", .{ bytes_seen, pad, gi.f2_leftBearing, gi.f2_topBearing, gi.f2_w, gi.f2_h, gi.f2_advance });
            }

            v.pos.x = x + (gi.leftBearing + gi.w) * target_fraction;
            max_x = v.pos.x;
            v.uv[0] = gi.uv[0] + gi.w / atlas_size.w;
            builder.appendVertex(v);

            v.pos.y = y + (gi.topBearing + gi.h) * target_fraction;
            sel_max_y = @max(sel_max_y, v.pos.y);
            v.uv[1] = gi.uv[1] + gi.h / atlas_size.h;
            builder.appendVertex(v);

            v.pos.x = leftx;
            v.uv[0] = gi.uv[0];
            builder.appendVertex(v);

            // triangles must be counter-clockwise (y going down) to avoid backface culling
            builder.appendTriangles(&.{
                vtx_offset + 0, vtx_offset + 2, vtx_offset + 1,
                vtx_offset + 0, vtx_offset + 3, vtx_offset + 2,
            });
        }

        x = nextx;
    }

    if (opts.background_color) |bgcol| {
        opts.rs.r.toPoint(.{
            .x = max_x,
            .y = @max(sel_max_y, opts.rs.r.y + fce.height * target_fraction * opts.font.line_height_factor),
        }).fill(.{}, .{ .color = bgcol, .fade = 0 });
    }

    if (sel) {
        Rect.Physical.fromPoint(.{ .x = sel_start_x, .y = opts.rs.r.y })
            .toPoint(.{
                .x = sel_end_x,
                .y = @max(sel_max_y, opts.rs.r.y + fce.height * target_fraction * opts.font.line_height_factor),
            })
            .fill(.{}, .{ .color = opts.sel_color orelse dvui.themeGet().focus, .fade = 0 });
    }

    try renderTriangles(builder.build_unowned(), texture_atlas);
}

pub const TextureOptions = struct {
    rotation: f32 = 0,
    colormod: Color = .{},
    corner_radius: Rect = .{},
    uv: Rect = .{ .w = 1, .h = 1 },
    background_color: ?Color = null,
    debug: bool = false,

    /// Size (physical pixels) of fade to transparent centered on the edge.
    /// If >1, then starts a half-pixel inside and the rest outside.
    fade: f32 = 0.0,
};

/// Only valid between `Window.begin`and `Window.end`.
pub fn renderTexture(tex: Texture, rs: RectScale, opts: TextureOptions) Backend.GenericError!void {
    if (rs.s == 0) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;

    const cw = dvui.currentWindow();

    if (!cw.render_target.rendering) {
        cw.addRenderCommand(.{ .texture = .{ .tex = tex, .rs = rs, .opts = opts } }, false);
        return;
    }

    var rect = rs.r;
    if (cw.snap_to_pixels) {
        rect.x = @round(rect.x);
        rect.y = @round(rect.y);
    }

    var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
    defer path.deinit();

    path.addRect(rect, opts.corner_radius.scale(rs.s, Rect.Physical));

    var triangles = try path.build().fillConvexTriangles(cw.lifo(), .{ .color = opts.colormod.opacity(cw.alpha), .fade = opts.fade });
    defer triangles.deinit(cw.lifo());

    triangles.uvFromRectuv(rect, opts.uv);
    triangles.rotate(rect.center(), opts.rotation);

    if (opts.background_color) |bg_col| {
        var back_tri = try triangles.dupe(cw.lifo());
        defer back_tri.deinit(cw.lifo());

        back_tri.color(bg_col);
        try renderTriangles(back_tri, null);
    }

    try renderTriangles(triangles, tex);
}

/// Calls `renderTexture` with the texture created from `tvg_bytes`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: RectScale, opts: TextureOptions, icon_opts: IconRenderOptions) Backend.GenericError!void {
    if (rs.s == 0) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;

    // Ask for an integer size icon, then render it to fit rs
    const target_size = rs.r.h;
    const ask_height = @ceil(target_size);

    var h = dvui.fnv.init();
    h.update(std.mem.asBytes(&tvg_bytes.ptr));
    h.update(std.mem.asBytes(&ask_height));
    h.update(std.mem.asBytes(&icon_opts));
    const hash = h.final();

    const texture = dvui.textureGetCached(hash) orelse blk: {
        const texture = Texture.fromTvgFile(name, tvg_bytes, @intFromFloat(ask_height), icon_opts) catch |err| {
            dvui.logError(@src(), err, "Could not create texture from tvg file \"{s}\"", .{name});
            return;
        };
        dvui.textureAddToCache(hash, texture);
        break :blk texture;
    };

    try renderTexture(texture, rs, opts);
}

/// Calls `renderTexture` with the texture created from `source`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderImage(source: ImageSource, rs: RectScale, opts: TextureOptions) (Backend.TextureError || StbImageError)!void {
    if (rs.s == 0) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;
    try renderTexture(try source.getTexture(), rs, opts);
}

pub const Ninepatch = struct {
    tex: Texture,
    uv: [9]Rect,
    pub fn size(this: *const @This(), patch: usize) Size {
        return .{
            .w = @as(f32, @floatFromInt(this.tex.width)) * this.uv[patch].w,
            .h = @as(f32, @floatFromInt(this.tex.height)) * this.uv[patch].h,
        };
    }
};
pub const NinepatchOptions = struct {
    rotation: f32 = 0,
    colormod: Color = .{},
    background_color: ?Color = null,
    debug: bool = false,

    fade: f32 = 0.0,
};
pub fn renderNinepatch(ninepatch: Ninepatch, rs: RectScale, opts: NinepatchOptions) Backend.GenericError!void {
    const sz_top_left = ninepatch.size(0);
    const sz_top_right = ninepatch.size(2);
    const sz_bottom_left = ninepatch.size(6);
    const sz_bottom_right = ninepatch.size(8);

    const min_total_width_top = sz_top_left.w + sz_top_right.w;
    const min_total_width_bot = sz_bottom_left.w + sz_bottom_right.w;
    const min_total_height_left = sz_top_left.h + sz_bottom_left.h;
    const min_total_height_right = sz_top_right.h + sz_bottom_right.h;

    std.debug.assert(rs.r.w >= min_total_width_top);
    std.debug.assert(rs.r.w >= min_total_width_bot);
    std.debug.assert(min_total_width_top == min_total_width_bot);
    std.debug.assert(rs.r.h >= min_total_height_left);
    std.debug.assert(rs.r.h >= min_total_height_right);
    std.debug.assert(min_total_height_left == min_total_height_right);

    const rs_top_left = rs.rectToRectScale(.fromSize(sz_top_left));
    var rs_top_right = rs.rectToRectScale(.fromSize(sz_top_right));
    var rs_bottom_left = rs.rectToRectScale(.fromSize(sz_bottom_left));
    var rs_bottom_right = rs.rectToRectScale(.fromSize(sz_bottom_right));

    var rs_top_center = rs;
    var rs_center_left = rs;
    var rs_bottom_center = rs;
    var rs_center_right = rs;

    var rs_center_center = rs;

    rs_top_center.r.w -= rs_top_left.r.w + rs_top_right.r.w;
    rs_top_center.r.x += rs_top_left.r.w;
    rs_top_center.r.h = rs_top_left.r.h;

    rs_top_right.r.x += rs_top_right.r.w + rs_top_center.r.w;

    rs_center_left.r.h -= rs_top_left.r.h + rs_bottom_left.r.h;
    rs_center_left.r.y += rs_top_left.r.h;
    rs_center_left.r.w = rs_top_left.r.w;

    rs_bottom_left.r.y += rs_bottom_left.r.h + rs_center_left.r.h;

    rs_center_right.r.h -= rs_top_right.r.h + rs_bottom_right.r.h;
    rs_center_right.r.y += rs_top_right.r.h;
    rs_center_right.r.w = rs_top_right.r.w;
    rs_center_right.r.x = rs_top_right.r.x;

    rs_bottom_center.r.w -= rs_bottom_left.r.w + rs_bottom_right.r.w;
    rs_bottom_center.r.x += rs_top_left.r.w;
    rs_bottom_center.r.h = rs_bottom_left.r.h;
    rs_bottom_center.r.y = rs_bottom_left.r.y;

    rs_bottom_right.r.x = rs_top_right.r.x;
    rs_bottom_right.r.y = rs_bottom_left.r.y;

    rs_center_center.r.w = rs_top_center.r.w;
    rs_center_center.r.x = rs_top_center.r.x;
    rs_center_center.r.h = rs_center_left.r.h;
    rs_center_center.r.y = rs_center_left.r.y;

    try renderTexture(ninepatch.tex, rs_top_left, .{ .uv = ninepatch.uv[0], .background_color = opts.background_color, .rotation = opts.rotation });
    try renderTexture(ninepatch.tex, rs_top_right, .{ .uv = ninepatch.uv[2], .background_color = opts.background_color, .rotation = opts.rotation });
    try renderTexture(ninepatch.tex, rs_bottom_left, .{ .uv = ninepatch.uv[6], .background_color = opts.background_color, .rotation = opts.rotation });
    try renderTexture(ninepatch.tex, rs_bottom_right, .{ .uv = ninepatch.uv[8], .background_color = opts.background_color, .rotation = opts.rotation });

    try renderTexture(ninepatch.tex, rs_top_center, .{ .uv = ninepatch.uv[1], .background_color = opts.background_color, .rotation = opts.rotation });
    try renderTexture(ninepatch.tex, rs_bottom_center, .{ .uv = ninepatch.uv[7], .background_color = opts.background_color, .rotation = opts.rotation });
    try renderTexture(ninepatch.tex, rs_center_left, .{ .uv = ninepatch.uv[3], .background_color = opts.background_color, .rotation = opts.rotation });
    try renderTexture(ninepatch.tex, rs_center_right, .{ .uv = ninepatch.uv[5], .background_color = opts.background_color, .rotation = opts.rotation });

    try renderTexture(ninepatch.tex, rs_center_center, .{ .uv = ninepatch.uv[4], .background_color = opts.background_color, .rotation = opts.rotation });
}

pub fn renderNinepatchImage(source: ImageSource, uv: [9]Rect, rs: RectScale, opts: NinepatchOptions) (Backend.TextureError || StbImageError)!void {
    if (rs.s == 0) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;
    try renderNinepatch(.{ .tex = try source.getTexture(), .uv = uv }, rs, opts);
}

const std = @import("std");
const dvui = @import("dvui.zig");

const Backend = dvui.Backend;
const Font = dvui.Font;
const Color = dvui.Color;
const Point = dvui.Point;
const Size = dvui.Size;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Triangles = dvui.Triangles;
const Path = dvui.Path;
const Texture = dvui.Texture;
const Vertex = dvui.Vertex;
const ImageSource = dvui.ImageSource;

const StbImageError = dvui.StbImageError;
const IconRenderOptions = dvui.IconRenderOptions;

test {
    @import("std").testing.refAllDecls(@This());
}
