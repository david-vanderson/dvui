const std = @import("std");
const dvui = @import("dvui.zig");
const Font = @import("Font.zig");
const c = dvui.c;

const Size = dvui.Size;
const Texture = dvui.Texture;
const Backend = dvui.Backend;

const Source = Font.Source;
const FreeType = Font.FreeType;
const Error = Font.Error;

const impl: enum { FreeType, STB } = if (dvui.useFreeType) .FreeType else .STB;

const Cache = @This();

database: std.ArrayList(Source) = .empty,
cache: dvui.TrackingAutoHashMap(u64, Entry, .get_and_put, void) = .empty,

pub fn deinit(self: *Cache, gpa: std.mem.Allocator, backend: Backend) void {
    defer self.* = undefined;
    var it = self.cache.iterator();
    while (it.next()) |item| {
        item.value_ptr.deinit(gpa, backend);
    }
    self.cache.deinit(gpa);

    for (self.database.items) |*source| {
        if (source.allocator) |a| {
            a.free(source.bytes);
        }
    }
    self.database.deinit(gpa);
}

pub fn reset(self: *Cache, gpa: std.mem.Allocator, backend: Backend) void {
    var it = self.cache.iterator();
    while (it.next_resetting()) |kv| {
        var fce = kv.value;
        fce.deinit(gpa, backend);
    }
}

pub fn findSource(self: *Cache, font: Font) struct { ?Source, ?Source } {
    var second_best: ?usize = null;
    for (self.database.items, 0..) |*source, i| {
        if (std.mem.eql(u8, font.familyName(), source.familyName())) {
            if (font.weight == source.weight and font.style == source.style) {
                return .{ source.*, null }; // exact match
            }

            if (font.weight == source.weight) {
                // second best is same family name and same weight
                second_best = i;
            } else if (second_best == null) {
                // at least the family name is the same
                second_best = i;
            }
        }
    }

    if (second_best) |sb| {
        return .{ null, self.database.items[sb] };
    }

    return .{ null, null };
}

pub fn getOrCreate(self: *Cache, gpa: std.mem.Allocator, font: Font) std.mem.Allocator.Error!*Entry {
    const entry = try self.cache.getOrPut(gpa, font.hash());
    if (entry.found_existing) return entry.value_ptr;

    const fname = font.name(gpa);
    defer gpa.free(fname);

    const exact, const second = self.findSource(font);

    const source = exact orelse second orelse Source.fallback;

    // Bold was requested but it's not available: thicken the face we do have
    const embolden = exact == null and font.weight == .bold and source.weight != .bold;

    if (exact == null) {
        const sname = source.name(gpa);
        defer gpa.free(sname);
        if (embolden) {
            dvui.log.debug("Font {s} not loaded in dvui, synthesizing bold from {s}", .{ fname, sname });
        } else {
            dvui.log.warn("Font {s} not loaded in dvui, using {s}", .{ fname, sname });
        }
    }

    //log.debug("FontCacheGet creating font hash {x} ptr {*} size {d} name \"{s}\"", .{ fontHash, bytes.ptr, font.size, font.name });

    entry.value_ptr.* = Entry.init(gpa, source, font, embolden) catch |err| {
        dvui.log.err("Font {s} init got {any}, using fallback", .{ fname, err });
        // Remove the invalid font cache entry, something went wrong reading the ttf_bytes
        self.cache.map.removeByPtr(entry.key_ptr);
        // Substitute the known good fallback font
        return self.getOrCreate(gpa, Source.fallback.font());
    };
    //log.debug("- size {d} ascent {d} height {d}", .{ font.size, entry.ascent, entry.height });
    return entry.value_ptr;
}

pub const Entry = struct {
    face: if (impl == .FreeType) c.FT_Face else c.stbtt_fontinfo,
    name: []const u8, // gpa
    scaleFactor: f32,
    height: f32, // ascender - descender
    ascent: f32, // ascender (integer)
    em_height: f32, // height of M
    glyph_info: std.AutoHashMapUnmanaged(u32, GlyphInfo) = .empty,
    /// Kerning per adjacent codepoint pair, keyed `(cp1 << 32) | cp2`. Each
    /// pair is asked for twice per frame for text that is measured and then
    /// rendered, and a miss costs a cmap lookup per codepoint plus a kern-table
    /// scan (freetype) or a `stbtt_GetCodepointKernAdvance` scan, so the result
    /// is cached per font size.
    kern_cache: std.AutoHashMapUnmanaged(u64, f32) = .empty,
    /// Measured line layouts, keyed by the text and every input that changes the
    /// measurement (max_width, kerning, snap, end_metric). A frame asks for the
    /// same lines again and again, and the loop that answers is UTF-8 decode
    /// plus a glyph lookup, a kern probe and min/max tracking per codepoint.
    line_cache: std.AutoHashMapUnmanaged(u64, LineLayout) = .empty,
    glyph_info_ascii: [ascii_size - ascii_start]GlyphInfo,
    texture_atlas_cache: ?Texture = null,
    embolden: bool = false, // true if this entry is synthetically bolded

    const ascii_size = 127;
    const ascii_start = 32;

    /// One measured line: the size, where it stopped, the byte positions that
    /// got kerning, and the trailing marker the callers' buffers expect.
    pub const LineLayout = struct {
        size: Size,
        end_idx: u32,
        end_marker: u32,
        text_len: u32,
        kern: [max_kern]u32 = @splat(0),
        kern_n: u8 = 0,

        /// Writes the caller's `end_idx`/`kern_out` outputs and returns the size.
        pub fn apply(self: LineLayout, opts: Font.TextSizeOptions) Size {
            if (opts.end_idx) |endout| endout.* = self.end_idx;
            if (opts.kern_out) |ko| {
                for (self.kern[0..self.kern_n]) |pos| {
                    var placed = false;
                    for (ko) |*k| {
                        if (k.* == 0) {
                            k.* = pos;
                            placed = true;
                            break;
                        }
                    }
                    if (!placed) break;
                }
                for (ko) |*k| {
                    if (k.* == 0) {
                        k.* = self.end_marker;
                        break;
                    }
                }
            }
            return self.size;
        }
    };
    /// Matches the `kern_out` buffers callers pass today (a `[10]u32`).
    pub const max_kern = 10;
    /// Per-size bounds on the caches, cleared on overflow so a UI that measures
    /// unbounded distinct text or sees unbounded distinct pairs stays bounded.
    const line_cache_max = 256;
    const kern_cache_max = 4096;

    const GlyphInfo = struct {
        advance: f32, // horizontal distance to move the pen
        leftBearing: f32, // horizontal distance from pen to glyph pixels left edge (integer)
        topBearing: f32, // vertical distance from pen to glyph pixels top edge (integer)
        w: f32, // width of bounding box (integer)
        h: f32, // height of bounding box (integer)
        uv: @Vector(2, f32),
    };

    /// Load the underlying font at an integer size <= font.size (guaranteed to have a minimum pixel size of 1)
    pub fn init(gpa: std.mem.Allocator, source: Source, font: Font, embolden: bool) Error!Entry {
        const min_pixel_size = 1;

        var fname = source.name(gpa);
        if (embolden) {
            const old = fname;
            defer gpa.free(old);
            fname = std.fmt.allocPrint(gpa, "{s} Bold Synth", .{old}) catch "OOM";
        }
        errdefer gpa.free(fname);

        var self: Entry = if (impl == .FreeType) blk: {
            var face: c.FT_Face = undefined;
            var args: c.FT_Open_Args = undefined;
            args.flags = @as(u32, @bitCast(FreeType.OpenFlags{ .memory = true }));
            args.memory_base = source.bytes.ptr;
            args.memory_size = @as(u31, @intCast(source.bytes.len));
            FreeType.intToError(c.FT_Open_Face(dvui.ft2lib, &args, 0, &face)) catch |err| {
                dvui.log.warn("Font.Cache.Entry.init() freetype error {any} trying to FT_Open_Face font {s}\n", .{ err, fname });
                return Error.FontError;
            };

            // "pixel size" for freetype doesn't actually mean you'll get that height, it's more like using pts
            // so we search for a font that has a height <= font.size
            var pixel_size = @as(u32, @trunc(@max(min_pixel_size, @floor(font.size))));
            pixel_size += 20;

            while (true) : (pixel_size -= 1) {
                FreeType.intToError(c.FT_Set_Pixel_Sizes(face, pixel_size, pixel_size)) catch |err| {
                    dvui.log.warn("Font.Cache.Entry.init() freetype error {any} trying to FT_Set_Pixel_Sizes font {s}\n", .{ err, fname });
                    return Error.FontError;
                };

                const ascender = @as(f32, @floatFromInt(face.*.ascender)) / 64.0;
                const ss = @as(f32, @floatFromInt(face.*.size.*.metrics.y_scale)) / 0x10000;
                const fascent = ascender * ss;
                const descender = @as(f32, @floatFromInt(face.*.descender)) / 64.0;
                const descent = descender * ss;

                var entry: Entry = .{
                    .face = face,
                    .name = fname,
                    .scaleFactor = 1.0, // not used with freetype
                    .height = fascent - descent,
                    .ascent = @trunc(fascent), // cheat ascent a bit, must be an integer
                    .em_height = undefined, // below
                    .glyph_info_ascii = undefined,
                };

                const M = try entry.glyphInfoGenerate('M');
                if (M.h <= 0) {
                    dvui.log.warn("Font.Cache.Entry.init() freetype error getting M font {s} size {d}\n", .{ fname, font.size });
                    return error.FontError;
                }

                if (M.h <= font.size or pixel_size == min_pixel_size) {
                    //std.debug.print("{s} pixel_size {d} ascent {d} descent {d} height {d}\n", .{fname, pixel_size, ascent, descent, ascent - descent});
                    entry.em_height = M.h;
                    // set after sizing so synthetic bold renders at the correct size
                    entry.embolden = embolden;
                    break :blk entry;
                }
            }
        } else blk: {
            const offset = c.stbtt_GetFontOffsetForIndex(source.bytes.ptr, 0);
            if (offset < 0) {
                dvui.log.warn("Font.Cache.Entry.init() stbtt error when calling stbtt_GetFontOffsetForIndex font {s}\n", .{fname});
                return Error.FontError;
            }
            var face: c.stbtt_fontinfo = undefined;
            if (c.stbtt_InitFont(&face, source.bytes.ptr, offset) != 1) {
                dvui.log.warn("Font.Cache.Entry.init() stbtt error when calling stbtt_InitFont font {s}\n", .{fname});
                return Error.FontError;
            }

            var face_ascent: c_int = undefined;
            var face_descent: c_int = undefined;
            c.stbtt_GetFontVMetrics(&face, &face_ascent, &face_descent, null);

            var entry: Entry = .{
                .face = face,
                .name = fname,
                .scaleFactor = 1.0, // adjusted below
                .height = 1.0, // adjusted below
                .ascent = 1.0, // adjusted below
                .em_height = undefined, // below
                .glyph_info_ascii = undefined,
            };

            const M = try entry.glyphInfoGenerate('M');
            if (M.h <= 0) {
                dvui.log.warn("Font.Cache.Entry.init() stbtt error getting M font {s} size {d}\n", .{ fname, font.size });
                return error.FontError;
            }
            entry.scaleFactor = @max(min_pixel_size, @floor(font.size)) / M.h;
            const ascender = entry.scaleFactor * @as(f32, @floatFromInt(face_ascent));
            const descender = entry.scaleFactor * @as(f32, @floatFromInt(face_descent));
            entry.ascent = @trunc(ascender); // cheat the ascent a bit, must be integer
            entry.height = ascender - descender;
            entry.em_height = entry.scaleFactor * M.h;
            entry.embolden = embolden;

            //std.debug.print("{s} ascent {d} descent {d} computed ascent {d} height {d}\n", .{fname, ascender, descender, entry.ascent, entry.height});
            break :blk entry;
        };

        // Pre-generate the ascii glyphs
        //std.debug.print("char,codepoint,hx,w,hy,h,adv\n", .{});
        for (0..self.glyph_info_ascii.len) |i| {
            self.glyph_info_ascii[i] = try self.glyphInfoGenerate(@intCast(i + ascii_start));
        }

        //const gi = self.glyph_info_ascii['M' - ascii_start];
        //std.debug.print("{s} size {d} height {d} M left {d} top {d} wxh {d}x{d}\n", .{ fname, font.size, self.height, gi.leftBearing, gi.topBearing, gi.w, gi.h});

        return self;
    }

    pub fn deinit(self: *Entry, gpa: std.mem.Allocator, backend: Backend) void {
        defer self.* = undefined;
        gpa.free(self.name);
        self.glyph_info.deinit(gpa);
        self.kern_cache.deinit(gpa);
        self.line_cache.deinit(gpa);
        if (impl == .FreeType) {
            _ = c.FT_Done_Face(self.face);
        }
        if (self.texture_atlas_cache) |tex| backend.textureDestroy(tex);
    }

    pub fn invalidateTextureAtlas(self: *Entry) void {
        if (self.texture_atlas_cache) |tex| {
            dvui.textureDestroyLater(tex);
        }
        self.texture_atlas_cache = null;
    }

    /// This needs to be called before rendering of glyphs as the uv coordinates
    /// of the glyphs will not be correct if the atlas needs to be generated.
    pub fn getTextureAtlas(self: *Entry, gpa: std.mem.Allocator, backend: Backend) Backend.TextureError!Texture {
        if (self.texture_atlas_cache) |tex| return tex;

        // number of extra pixels to add on each side of each glyph
        const pad = 1;

        const total = self.glyph_info_ascii.len + self.glyph_info.count();
        const row_glyphs: u32 = @ceil(@as(f32, @sqrt(@as(f32, @floatFromInt(total)))));

        var s = Size{};
        {
            var i: u32 = 0;
            var row: Size = .{};
            var it = self.glyph_info.iterator();

            while (i < total) {
                const gi, const codepoint = if (i < self.glyph_info_ascii.len) .{ &self.glyph_info_ascii[i], i + ascii_start } else blk: {
                    const e = it.next().?;
                    break :blk .{ e.value_ptr, e.key_ptr.* };
                };
                _ = codepoint;

                row.w += gi.w + 2 * pad;
                row.h = @max(row.h, gi.h + 2 * pad);

                i += 1;
                if (i % row_glyphs == 0) {
                    s.w = @max(s.w, row.w);
                    s.h += row.h;
                    row = .{};
                }
            } else {
                s.w = @max(s.w, row.w);
                s.h += row.h;
            }

            s = s.ceil();
        }

        // also add an extra padding around whole texture
        s.w += 2 * pad;
        s.h += 2 * pad;

        var pixels = try gpa.alloc(dvui.Color.PMA, @as(usize, @trunc(s.w * s.h)));
        defer gpa.free(pixels);
        // set all pixels to zero alpha
        @memset(pixels, .transparent);

        //const num_glyphs = fce.glyph_info.count();
        //std.debug.print("font size {d} regen glyph atlas num {d} max size {}\n", .{ sized_font.size, num_glyphs, s });

        var x: i32 = pad;
        var y: i32 = pad;
        var it = self.glyph_info.iterator();
        var row_height: u32 = 0;
        var i: u32 = 0;
        while (i < total) {
            var gi, const codepoint = if (i < self.glyph_info_ascii.len) .{ &self.glyph_info_ascii[i], i + ascii_start } else blk: {
                const e = it.next().?;
                break :blk .{ e.value_ptr, e.key_ptr.* };
            };

            gi.uv[0] = @as(f32, @floatFromInt(x + pad)) / s.w;
            gi.uv[1] = @as(f32, @floatFromInt(y + pad)) / s.h;

            if (impl == .FreeType) blk: {
                FreeType.intToError(c.FT_Load_Char(self.face, codepoint, @as(i32, @bitCast(FreeType.LoadFlags{ .render = false })))) catch |err| {
                    dvui.log.warn("renderText: freetype error {any} trying to FT_Load_Char codepoint {d}", .{ err, codepoint });
                    break :blk; // will skip the failing glyph
                };
                if (self.embolden) c.FT_GlyphSlot_Embolden(self.face.*.glyph);

                // https://freetype.org/freetype2/docs/tutorial/step1.html#section-6
                if (self.face.*.glyph.*.format != c.FT_GLYPH_FORMAT_BITMAP) {
                    FreeType.intToError(c.FT_Render_Glyph(self.face.*.glyph, c.FT_RENDER_MODE_NORMAL)) catch |err| {
                        dvui.log.warn("renderText freetype error {any} trying to FT_Render_Glyph codepoint {d}", .{ err, codepoint });
                        break :blk; // will skip the failing glyph
                    };
                }

                const bitmap = self.face.*.glyph.*.bitmap;
                //std.debug.print("bitmap,{d},{d},{d}\n", .{codepoint, bitmap.width, bitmap.rows});
                row_height = @max(row_height, bitmap.rows);
                var row: i32 = 0;
                while (row < bitmap.rows) : (row += 1) {
                    var col: i32 = 0;
                    while (col < bitmap.width) : (col += 1) {
                        const src = bitmap.buffer[@as(usize, @intCast(row * bitmap.pitch + col))];

                        // because of the extra edge, offset by 1 row and 1 col
                        const di = @as(usize, @intCast((y + row + pad) * @as(i32, @trunc(s.w)) + (x + col + pad)));

                        // premultiplied white
                        pixels[di] = .{ .r = src, .g = src, .b = src, .a = src };
                    }
                }
            } else {
                //var ow: c_int = undefined;
                //var oh: c_int = undefined;
                //const bm = c.stbtt_GetCodepointBitmap(&self.face, self.scaleFactor, self.scaleFactor, @as(c_int, @intCast(codepoint)), &ow, &oh, null, null);
                //std.debug.print("bitmap,{d},{d},{d}\n", .{codepoint, ow, oh});

                //c.stbtt_FreeBitmap(bm, null);

                const out_w: u32 = @trunc(gi.w);
                const out_h: u32 = @trunc(gi.h);
                row_height = @max(row_height, out_h);

                // single channel
                const bitmap = try gpa.alloc(u8, @as(usize, out_w * out_h));
                defer gpa.free(bitmap);

                //log.debug("makecodepointBitmap size x {d} y {d} w {d} h {d} out w {d} h {d}", .{ x, y, s.w, s.h, out_w, out_h });

                c.stbtt_MakeCodepointBitmapSubpixel(&self.face, bitmap.ptr, @as(c_int, @intCast(out_w)), @as(c_int, @intCast(out_h)), @as(c_int, @intCast(out_w)), self.scaleFactor, self.scaleFactor, 0.0, 0.0, @as(c_int, @intCast(codepoint)));

                if (self.embolden) {
                    // glyphInfoGenerate already widened gi.w by k, so the smear has room
                    const k = self.emboldenPx();
                    for (0..out_h) |row| {
                        const line = bitmap[row * out_w ..][0..out_w];
                        var col = out_w;
                        while (col > 0) {
                            col -= 1;
                            var v = line[col];
                            for (1..k + 1) |shift| {
                                if (col >= shift) v = @max(v, line[col - shift]);
                            }
                            line[col] = v;
                        }
                    }
                }

                const stride: usize = @trunc(s.w);
                const di = @as(usize, @intCast(y)) * stride + @as(usize, @intCast(x));
                for (0..out_h) |row| {
                    for (0..out_w) |col| {
                        const src = bitmap[row * out_w + col];
                        const dest = di + (row + pad) * stride + (col + pad);

                        // premultiplied white
                        pixels[dest] = .{ .r = src, .g = src, .b = src, .a = src };
                    }
                }
            }

            x += @as(i32, @trunc(gi.w)) + 2 * pad;

            i += 1;
            if (i % row_glyphs == 0) {
                x = pad;
                y += @intCast(row_height + 2 * pad);
                row_height = 0;
            }
        }

        self.texture_atlas_cache = try backend.textureCreate(@ptrCast(pixels.ptr), .{ .width = @trunc(s.w), .height = @trunc(s.h) });
        return self.texture_atlas_cache.?;
    }

    /// If a codepoint is missing in the font it gets the glyph for
    /// `std.unicode.replacement_character`
    pub fn glyphInfoGetOrReplacement(self: *Entry, gpa: std.mem.Allocator, codepoint: u32) std.mem.Allocator.Error!GlyphInfo {
        return self.glyphInfoGet(gpa, codepoint) catch |err| switch (err) {
            Error.FontError => self.glyphInfoGet(gpa, std.unicode.replacement_character) catch unreachable,
            else => |e| e,
        };
    }

    pub fn glyphInfoGet(self: *Entry, gpa: std.mem.Allocator, codepoint: u32) (std.mem.Allocator.Error || Error)!GlyphInfo {
        if (ascii_start <= codepoint and codepoint < ascii_size)
            return self.glyph_info_ascii[codepoint - ascii_start];

        if (self.glyph_info.get(codepoint)) |gi| return gi;

        const gi = try self.glyphInfoGenerate(codepoint);

        // new glyph, need to regen texture atlas on next render
        //std.debug.print("new glyph {}\n", .{codepoint});
        self.invalidateTextureAtlas();

        try self.glyph_info.put(gpa, codepoint, gi);
        return gi;
    }

    fn emboldenPx(self: *Entry) usize {
        const em_px = self.scaleFactor / c.stbtt_ScaleForMappingEmToPixels(&self.face, 1.0);
        return @max(1, @as(usize, @intFromFloat(@round(em_px / 24.0))));
    }

    pub fn glyphInfoGenerate(self: *Entry, codepoint: u32) Error!GlyphInfo {
        const gi: GlyphInfo = if (impl == .FreeType) blk: {
            FreeType.intToError(c.FT_Load_Char(self.face, codepoint, @as(i32, @bitCast(FreeType.LoadFlags{ .render = false })))) catch |err| {
                dvui.log.warn("glyphInfoGet freetype error {any} font {s} codepoint {d}\n", .{ err, self.name, codepoint });
                return Error.FontError;
            };
            if (self.embolden) c.FT_GlyphSlot_Embolden(self.face.*.glyph);

            const m = self.face.*.glyph.*.metrics;
            const minx = @as(f32, @floatFromInt(m.horiBearingX)) / 64.0;
            const miny = @as(f32, @floatFromInt(m.horiBearingY)) / 64.0;

            //const hx = @as(f32, @floatFromInt(m.horiBearingX)) / 64.0;
            //const w = @as(f32, @floatFromInt(m.width)) / 64.0;
            //const hy = @as(f32, @floatFromInt(m.horiBearingY)) / 64.0;
            //const h = @as(f32, @floatFromInt(m.height)) / 64.0;
            const adv = @as(f32, @floatFromInt(m.horiAdvance)) / 64.0;
            //std.debug.print("{c},{d},{d},{d},{d},{d},{d}\n", .{@as(u8, @intCast(codepoint)), codepoint, hx, w, hy, h, adv});

            // All these values should be integers, but just in case.
            // bitmap assumes pen position is at a pixel boundary.

            break :blk .{
                .advance = adv,
                .leftBearing = @floor(minx),
                .topBearing = @floor(miny),
                .w = @ceil(minx + @as(f32, @floatFromInt(m.width)) / 64.0) - @floor(minx),
                .h = @ceil(miny + @as(f32, @floatFromInt(m.height)) / 64.0) - @floor(miny),
                .uv = .{ 0, 0 },
            };
        } else blk: {
            var advanceWidth: c_int = undefined;
            c.stbtt_GetCodepointHMetrics(&self.face, @as(c_int, @intCast(codepoint)), &advanceWidth, null);
            var ix0: c_int = undefined;
            var iy0: c_int = undefined;
            var ix1: c_int = undefined;
            var iy1: c_int = undefined;
            const ret = c.stbtt_GetCodepointBox(&self.face, @as(c_int, @intCast(codepoint)), &ix0, &iy0, &ix1, &iy1);
            const x0: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(ix0));
            const y0: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(iy0));
            const x1: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(ix1));
            const y1: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(iy1));
            const adv: f32 = self.scaleFactor * @as(f32, @floatFromInt(advanceWidth));
            const k: f32 = if (self.embolden) @floatFromInt(self.emboldenPx()) else 0;

            //std.debug.print("{c},{d},{d},{d},{d},{d},{d}\n", .{@as(u8, @intCast(codepoint)), codepoint, x0, x1, y0, y1, adv});
            //std.debug.print("{d} codepoint {d} stbtt x0 {d} {d} x1 {d} {d} y0 {d} {d} y1 {d} {d}\n", .{ self.ascent, codepoint, ix0, x0, ix1, x1, iy0, y0, iy1, y1 });

            // bitmap assumes pen position is at a pixel boundary, so we
            // extend the box in each direction to a full pixel (so floor
            // x0/y0, and ceil x1/y1)

            break :blk .{
                .advance = adv + k,
                .leftBearing = @floor(x0),
                .topBearing = @ceil(y1),
                .w = @ceil(x1 + k) - @floor(x0),
                .h = @ceil(y1) - @floor(y0),
                .uv = .{ 0, 0 },
            };
        };
        //std.debug.print("codepoint {d} advance {d} leftBearing {d} topBearing {d} w {d} h {d}\n", .{ codepoint, gi.advance, gi.leftBearing, gi.topBearing, gi.w, gi.h });
        return gi;
    }

    pub fn kern(fce: *Entry, gpa: std.mem.Allocator, codepoint1: u32, codepoint2: u32) f32 {
        const key = (@as(u64, codepoint1) << 32) | @as(u64, codepoint2);
        if (fce.kern_cache.get(key)) |k| return k;

        const pair_kern: f32 = if (impl == .FreeType) blk: {
            const index1 = c.FT_Get_Char_Index(fce.face, codepoint1);
            const index2 = c.FT_Get_Char_Index(fce.face, codepoint2);
            var k: c.FT_Vector = undefined;
            FreeType.intToError(c.FT_Get_Kerning(fce.face, index1, index2, c.FT_KERNING_DEFAULT, &k)) catch |err| {
                dvui.log.warn("renderText freetype error {any} trying to FT_Get_Kerning font {s} codepoints {d} {d}\n", .{ err, fce.name, codepoint1, codepoint2 });
                k.x = 0;
                k.y = 0;
            };

            break :blk @as(f32, @floatFromInt(k.x)) / 64.0;
        } else blk: {
            const kern_adv: c_int = c.stbtt_GetCodepointKernAdvance(&fce.face, @as(c_int, @intCast(codepoint1)), @as(c_int, @intCast(codepoint2)));
            break :blk fce.scaleFactor * @as(f32, @floatFromInt(kern_adv));
        };

        if (fce.kern_cache.count() >= kern_cache_max) fce.kern_cache.clearRetainingCapacity();
        fce.kern_cache.put(gpa, key, pair_kern) catch {};
        return pair_kern;
    }

    /// Doesn't scale the font or max_width, always stops at newlines
    ///
    /// Assumes the text is valid utf8. Will exit early with non-full
    /// size on invalid utf8
    pub fn textSizeRaw(
        self: *Entry,
        gpa: std.mem.Allocator,
        text: []const u8,
        opts: Font.TextSizeOptions,
    ) std.mem.Allocator.Error!Size {
        const mwidth = opts.max_width orelse dvui.max_float_safe;

        const snap = dvui.snapToPixels();
        const kerning: bool = opts.kerning orelse true;

        // `kern_in` means "kernel only where this list says", which makes the
        // result depend on the list, not just the text; those calls stay uncached.
        const cacheable = opts.kern_in == null;
        var cache_key: u64 = 0;
        if (cacheable) {
            cache_key = std.hash.Wyhash.hash(0, text);
            cache_key ^= @as(u64, @as(u32, @bitCast(mwidth))) *% 0x9E3779B97F4A7C15;
            cache_key ^= @as(u64, @intFromBool(kerning)) << 1;
            cache_key ^= @as(u64, @intFromBool(snap)) << 2;
            cache_key ^= @as(u64, @as(u32, @backingInt(opts.end_metric))) << 3;
            if (self.line_cache.get(cache_key)) |cached| {
                if (cached.text_len == text.len) return cached.apply(opts);
            }
        }

        var x: f32 = 0;
        var minx: f32 = 0;
        var maxx: f32 = 0;
        var miny: f32 = 0;
        var maxy: f32 = self.height;
        var tw: f32 = 0;
        var th: f32 = self.height;

        var ei: usize = 0;
        var nearest_break: bool = false;

        var last_codepoint: u32 = 0;
        var next_kern_idx: u32 = 0;
        var next_kern_byte: u32 = 0;
        if (opts.kern_in) |ki| {
            next_kern_byte = ki[next_kern_idx];
            next_kern_idx += 1;
        }

        var kern_list: [max_kern]u32 = @splat(0);
        var kern_n: u8 = 0;

        var i: usize = 0;
        while (i < text.len) {
            const cplen = std.unicode.utf8ByteSequenceLength(text[i]) catch unreachable;
            const codepoint = std.unicode.utf8Decode(text[i..][0..cplen]) catch unreachable;

            if (codepoint == '\n') {
                // newlines always terminate, and don't use any space
                ei += 1;
                break;
            }

            const gi = try self.glyphInfoGetOrReplacement(gpa, codepoint);

            if (kerning and last_codepoint != 0 and i >= next_kern_byte) {
                const kk = self.kern(gpa, last_codepoint, codepoint);
                x += if (snap) @round(kk) else kk;

                if (opts.kern_in) |ki| {
                    if (next_kern_idx < ki.len) {
                        next_kern_byte = ki[next_kern_idx];
                        next_kern_idx += 1;
                    }
                }

                if (kk != 0 and kern_n < max_kern) {
                    kern_list[kern_n] = @intCast(i);
                    kern_n += 1;
                }
            }

            i += cplen;
            last_codepoint = codepoint;

            const adv = if (snap) @round(gi.advance) else gi.advance;

            minx = @min(minx, x + gi.leftBearing);
            maxx = @max(maxx, x + gi.leftBearing + gi.w);
            maxx = @max(maxx, x + adv);

            miny = @min(miny, self.ascent - gi.topBearing);
            maxy = @max(maxy, self.ascent - gi.topBearing + gi.h);

            if ((maxx - minx) > mwidth) {
                switch (opts.end_metric) {
                    .before => break, // went too far
                    .nearest => {
                        if ((maxx - minx) - mwidth >= mwidth - tw) {
                            break; // current one is closest
                        } else {
                            // get the next glyph and then break
                            nearest_break = true;
                        }
                    },
                }
            }

            // record that we processed this codepoint
            ei += cplen;

            // update space taken by glyph
            tw = maxx - minx;
            th = maxy - miny;
            x += adv;

            if (nearest_break) break;
        }

        // TODO: xstart and ystart

        const layout = LineLayout{
            .size = .{ .w = tw, .h = th },
            .end_idx = @intCast(ei),
            .end_marker = @intCast(i),
            .text_len = @intCast(text.len),
            .kern = kern_list,
            .kern_n = kern_n,
        };

        if (cacheable) {
            if (self.line_cache.count() >= line_cache_max) self.line_cache.clearRetainingCapacity();
            self.line_cache.put(gpa, cache_key, layout) catch {};
        }

        return layout.apply(opts);
    }
};

test "kern is cached per codepoint pair" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fce = try dvui.fontCacheGet(dvui.themeGet().font_body);
    const before = fce.kern_cache.count();

    const av = fce.kern(t.allocator, 'A', 'V');
    const va = fce.kern(t.allocator, 'V', 'A');
    const av_again = fce.kern(t.allocator, 'A', 'V');
    const va_again = fce.kern(t.allocator, 'V', 'A');

    // A pair is looked up twice a frame for text that is measured and then
    // rendered, and the second lookup is the cached value.  The reversed pair is
    // a distinct key, not a hit on the same entry.
    try std.testing.expectEqual(av, av_again);
    try std.testing.expectEqual(va, va_again);
    try std.testing.expectEqual(before + 2, fce.kern_cache.count());
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "line layout cache agrees with the uncached measurement" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const fce = try dvui.fontCacheGet(dvui.themeGet().font_body);
    const text = "AVATAR World 123";

    // Cached path (no kern_in).
    var end_cached: usize = 0;
    var kern_cached: [10]u32 = @splat(0);
    const cached = try fce.textSizeRaw(t.allocator, text, .{ .end_idx = &end_cached, .kern_out = &kern_cached });

    // Same measurement through the uncached path: an all-zero kern_in list
    // gates nothing, so the loop runs as if there were no list at all.
    var kern_in: [10]u32 = @splat(0);
    var end_raw: usize = 0;
    var kern_raw: [10]u32 = @splat(0);
    const raw = try fce.textSizeRaw(t.allocator, text, .{
        .end_idx = &end_raw,
        .kern_out = &kern_raw,
        .kern_in = &kern_in,
    });

    try std.testing.expectEqual(raw, cached);
    try std.testing.expectEqual(end_raw, end_cached);
    try std.testing.expectEqualSlices(u32, &kern_raw, &kern_cached);
}

test {
    @import("std").testing.refAllDecls(@This());
}
