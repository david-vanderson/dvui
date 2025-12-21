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

    /// Draw text starting here (top left corner of start of text).  If null,
    /// use rs.r.topLeft().
    p: ?Point.Physical = null,
    color: Color,
    background_color: ?Color = null,

    /// radians clockwise, rotates around top-left corner (rs.x/rs.y)
    /// - doesn't support background or selection yet
    rotation: f32 = 0.0,
    sel_start: ?usize = null,
    sel_end: ?usize = null,
    sel_color: ?Color = null,
    debug: bool = false,
    kerning: ?bool = null,
    kern_in: ?[]u32 = null,
    ak_opts: ?AccessKit.TextRunOptions = null,
};

/// Only renders a single line of text
///
/// Selection will be colored with the current themes accent color,
/// with the text color being set to the themes fill color.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderText(opts: TextOptions) Backend.GenericError!void {
    var cw = dvui.currentWindow();
    // Record character heights and positions for AccessKit text_run role.
    var text_info: std.MultiArrayList(AccessKit.CharPositionInfo) = .empty;
    const clipped_rect = dvui.clipGet().intersect(opts.rs.r);

    // If accessibility is enabled, we still need create the associated text_run
    // even when the text is blank or not visible.
    if (opts.ak_opts) |ak_opts| {
        if (dvui.accesskit_enabled and opts.text.len == 0) {
            if (ak_opts.text[ak_opts.text.len - 1] == '\n') {
                text_info.append(cw.arena(), .{
                    .l = 1,
                    .w = 1,
                    .x = if (text_info.len > 0) text_info.items(.x)[text_info.len - 1] else 0,
                }) catch {};
            }
            cw.accesskit.textRunPopulate(ak_opts, &text_info, opts.rs.r);
            return;
        }
    } else {
        if (opts.text.len == 0) return;
        if (opts.rs.s == 0) return;
        if (clipped_rect.empty() and opts.ak_opts == null) return;
    }

    const utf8_text = try dvui.toUtf8(cw.lifo(), opts.text);
    defer if (opts.text.ptr != utf8_text.ptr) cw.lifo().free(utf8_text);

    if (!cw.render_target.rendering) {
        var opts_copy = opts;
        opts_copy.text = try cw.arena().dupe(u8, utf8_text);
        if (opts.ak_opts) |ak_opts| {
            opts_copy.ak_opts.?.text = cw.arena().dupe(u8, ak_opts.text) catch "";
        }
        if (opts.kern_in) |ki| opts_copy.kern_in = try cw.arena().dupe(u32, ki);
        cw.addRenderCommand(.{ .text = opts_copy }, false);
        return;
    }

    const target_size = opts.font.size * opts.rs.s;
    const sized_font = opts.font.withSize(target_size);

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
            const fname = opts.font.name(cw.arena());
            defer cw.arena().free(fname);
            dvui.log.err("Could not get texture atlas for font {s}, text area marked in magenta, to display '{s}'", .{ fname, opts.text });
            opts.rs.r.fill(.{}, .{ .color = .magenta });
            return;
        },
    };

    // Over allocate the internal buffers assuming each byte is a character
    var builder = try dvui.Triangles.Builder.init(cw.lifo(), 4 * utf8_text.len, 6 * utf8_text.len);
    defer builder.deinit(cw.lifo());

    const col: Color.PMA = .fromColor(opts.color.opacity(cw.alpha));

    var start = opts.p orelse opts.rs.r.topLeft();
    if (cw.snap_to_pixels) {
        start.x = @round(start.x);
        start.y = @round(start.y);
    }

    var x = start.x;
    var max_x = start.x;

    if (opts.debug) {
        dvui.log.debug("renderText {f}\n", .{start});
    }

    var sel_in: bool = false;
    var sel_start_x: f32 = x;
    var sel_end_x: f32 = x;
    var sel_max_y: f32 = start.y;
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

        if (x + gi.leftBearing * target_fraction < start.x) {
            // Glyph extends left of the start, like the first letter being
            // "j", which has a negative left bearing.
            //
            // Shift the whole line over so it starts at x_start.  textSize()
            // includes this extra space.

            //std.debug.print("moving x from {d} to {d}\n", .{ x, x_start - gi.leftBearing * target_fraction });
            start.x -= gi.leftBearing * target_fraction;
            x = start.x;
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
        if (dvui.accesskit_enabled) {
            if (opts.ak_opts) |_| {
                text_info.append(cw.arena(), .{
                    .l = cplen,
                    .w = if (gi.w == 0) nextx - x else gi.w,
                    .x = std.math.clamp(x - clipped_rect.x, 0, clipped_rect.w),
                }) catch {};
            }
        }

        // don't output triangles for a zero-width glyph (space seems to be the only one)
        if (gi.w > 0) {
            const vtx_offset: u16 = @intCast(builder.vertexes.items.len);
            var v: Vertex = undefined;

            v.pos.x = leftx;
            v.pos.y = start.y + gi.topBearing * target_fraction;
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

            v.pos.y = start.y + (gi.topBearing + gi.h) * target_fraction;
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

    var tri = builder.build();
    defer tri.deinit(cw.lifo());

    tri.rotate(.{ .x = start.x, .y = start.y }, opts.rotation);

    try renderTriangles(tri, texture_atlas);

    if (dvui.accesskit_enabled) if (opts.ak_opts) |ak_opts| {
        // Newlines aren't rendered, so add one if required.
        if (ak_opts.text[ak_opts.text.len - 1] == '\n') {
            text_info.append(cw.arena(), .{
                .l = 1,
                .w = 1,
                .x = std.math.clamp(x - clipped_rect.x, 0, clipped_rect.w),
            }) catch {};
        }
        cw.accesskit.textRunPopulate(ak_opts, &text_info, clipped_rect);
    };
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
    pub const none: Ninepatch = .{};

    /// Image to use, default means explicitly no ninepatch.
    source: Texture.ImageSource = .{ .imageFile = .{
        .bytes = &.{},
        .name = "Ninepatch.none",
    } },
    /// How many pixels of source make up each edge.
    edge: Rect = .{},
};

pub const NinepatchOptions = struct {
    debug: bool = false,
};

/// Renders a ninepatch with the given parameters.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderNinepatch(ninepatch: Ninepatch, rs: RectScale, opts: NinepatchOptions) Backend.GenericError!void {
    if (ninepatch.source.imageFile.bytes.len == 0) return;
    if (rs.s == 0) return;
    if (rs.r.empty()) return;
    if (dvui.clipGet().intersect(rs.r).empty()) return;

    const tex = ninepatch.source.getTexture() catch |err| {
        dvui.log.err("renderNinepatch() got {any}", .{err});
        return;
    };

    var rect = rs.r;
    if (dvui.currentWindow().snap_to_pixels) {
        rect.x = @round(rect.x);
        rect.y = @round(rect.y);
    }

    const ts: Size = .{
        .w = @floatFromInt(tex.width),
        .h = @floatFromInt(tex.width),
    };

    // scale ninepatch edge size
    const e = ninepatch.edge.scale(rs.s, Rect.Physical);

    // middle
    var r = rect.inset(e);
    if (!r.empty()) {
        try renderTexture(tex, .{ .r = r, .s = rs.s }, .{
            .uv = .{
                .x = ninepatch.edge.x / ts.w,
                .w = (ts.w - ninepatch.edge.x - ninepatch.edge.w) / ts.w,
                .y = ninepatch.edge.y / ts.h,
                .h = (ts.h - ninepatch.edge.y - ninepatch.edge.h) / ts.h,
            },
            .debug = opts.debug,
        });
    }

    // top and bottom edges
    r = rect.inset(.{ .x = e.x, .w = e.w });
    if (!r.empty()) {
        // bottom first, draw as much as possible from bottom up
        var height = @min(r.h, e.h);
        const bottom = r.y + r.h;
        var th = height / rs.s;
        try renderTexture(tex, .{ .r = .{
            .x = r.x,
            .w = r.w,
            .y = bottom - height,
            .h = height,
        }, .s = rs.s }, .{
            .uv = .{
                .x = ninepatch.edge.x / ts.w,
                .w = (ts.w - ninepatch.edge.x - ninepatch.edge.w) / ts.w,
                .y = (ts.h - th) / ts.h,
                .h = th / ts.h,
            },
            .debug = opts.debug,
        });

        // top edge
        height = @min(r.h, e.y);
        th = height / rs.s;
        try renderTexture(tex, .{ .r = .{
            .x = r.x,
            .w = r.w,
            .y = r.y,
            .h = height,
        }, .s = rs.s }, .{
            .uv = .{
                .x = ninepatch.edge.x / ts.w,
                .w = (ts.w - ninepatch.edge.x - ninepatch.edge.w) / ts.w,
                .y = 0,
                .h = th / ts.h,
            },
            .debug = opts.debug,
        });
    }

    // left and right edges
    r = rect.inset(.{ .y = e.y, .h = e.h });
    if (!r.empty()) {
        // right first, draw from right edge
        var width = @min(r.w, e.w);
        const right = r.x + r.w;
        var tw = width / rs.s;
        try renderTexture(tex, .{ .r = .{
            .x = right - width,
            .w = width,
            .y = r.y,
            .h = r.h,
        }, .s = rs.s }, .{
            .uv = .{
                .x = (ts.w - tw) / ts.w,
                .w = tw / ts.w,
                .y = ninepatch.edge.y / ts.h,
                .h = (ts.h - ninepatch.edge.y - ninepatch.edge.h) / ts.h,
            },
            .debug = opts.debug,
        });

        // left
        width = @min(r.w, e.x);
        tw = width / rs.s;
        try renderTexture(tex, .{ .r = .{
            .x = r.x,
            .w = width,
            .y = r.y,
            .h = r.h,
        }, .s = rs.s }, .{
            .uv = .{
                .x = 0,
                .w = tw / ts.w,
                .y = ninepatch.edge.y / ts.h,
                .h = (ts.h - ninepatch.edge.y - ninepatch.edge.h) / ts.h,
            },
            .debug = opts.debug,
        });
    }

    // bottom right corner
    {
        r = rect;
        const width = @min(r.w, e.w);
        const tw = width / rs.s;
        const height = @min(r.h, e.h);
        const th = height / rs.s;
        if (!r.empty()) {
            try renderTexture(tex, .{ .r = .{
                .x = r.x + r.w - width,
                .w = width,
                .y = r.y + r.h - height,
                .h = height,
            }, .s = rs.s }, .{
                .uv = .{
                    .x = (ts.w - tw) / ts.w,
                    .w = tw / ts.w,
                    .y = (ts.h - th) / ts.h,
                    .h = th / ts.h,
                },
                .debug = opts.debug,
            });
        }
    }

    // bottom left corner
    {
        r = rect;
        const width = @min(r.w, e.x);
        const tw = width / rs.s;
        const height = @min(r.h, e.h);
        const th = height / rs.s;
        if (!r.empty()) {
            try renderTexture(tex, .{ .r = .{
                .x = r.x,
                .w = width,
                .y = r.y + r.h - height,
                .h = height,
            }, .s = rs.s }, .{
                .uv = .{
                    .x = 0,
                    .w = tw / ts.w,
                    .y = (ts.h - th) / ts.h,
                    .h = th / ts.h,
                },
                .debug = opts.debug,
            });
        }
    }

    // top right corner
    {
        r = rect;
        const width = @min(r.w, e.w);
        const tw = width / rs.s;
        const height = @min(r.h, e.y);
        const th = height / rs.s;
        if (!r.empty()) {
            try renderTexture(tex, .{ .r = .{
                .x = r.x + r.w - width,
                .w = width,
                .y = r.y,
                .h = height,
            }, .s = rs.s }, .{
                .uv = .{
                    .x = (ts.w - tw) / ts.w,
                    .w = tw / ts.w,
                    .y = 0,
                    .h = th / ts.h,
                },
                .debug = opts.debug,
            });
        }
    }

    // top left corner
    {
        r = rect;
        const width = @min(r.w, e.x);
        const tw = width / rs.s;
        const height = @min(r.h, e.y);
        const th = height / rs.s;
        if (!r.empty()) {
            try renderTexture(tex, .{ .r = .{
                .x = r.x,
                .w = width,
                .y = r.y,
                .h = height,
            }, .s = rs.s }, .{
                .uv = .{
                    .x = 0,
                    .w = tw / ts.w,
                    .y = 0,
                    .h = th / ts.h,
                },
                .debug = opts.debug,
            });
        }
    }
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
const AccessKit = dvui.AccessKit;
const StbImageError = dvui.StbImageError;
const IconRenderOptions = dvui.IconRenderOptions;

test {
    @import("std").testing.refAllDecls(@This());
}
