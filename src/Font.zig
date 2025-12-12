const std = @import("std");
const dvui = @import("dvui.zig");
const c = dvui.c;

const Rect = dvui.Rect;
const Size = dvui.Size;
const Texture = dvui.Texture;
const Backend = dvui.Backend;

/// Font represents the parameters that dvui will try to satisfy when rendering
/// text.  If a matching font is not found, dvui will log an error and use the
/// internal fallback font.
///
/// Usually specified with `find`:
/// const f: Font = .find(.{ .family = "Vera", .size = 20 });
const Font = @This();

const impl: enum { FreeType, STB } = if (dvui.useFreeType) .FreeType else .STB;
pub const Error = error{FontError};
pub const NAME_MAX_LEN = 50;

pub fn array(s: []const u8) [NAME_MAX_LEN:0]u8 {
    var v: [NAME_MAX_LEN:0]u8 = @splat(0);
    @memcpy(v[0..s.len], s);
    return v;
}

pub fn string(s: *const [NAME_MAX_LEN:0]u8) [:0]const u8 {
    return std.mem.sliceTo(s, 0);
}

pub const Weight = enum {
    normal,
    bold,
};

pub const Style = enum {
    normal,
    italic,
};

/// Changing any of these might query for a font.
family: [NAME_MAX_LEN:0]u8 = @splat(0),
size: f32 = 16,
weight: Weight = .normal,
style: Style = .normal,

/// Can be changed for any font, no query.
line_height_factor: f32 = 1.2,

pub const FindOptions = struct {
    family: []const u8,
    size: f32 = 16,
    weight: Weight = .normal,
    style: Style = .normal,
    line_height_factor: f32 = 1.2,
};

pub fn find(opts: FindOptions) Font {
    return (Font{}).withFamily(opts.family).withSize(opts.size).withWeight(opts.weight).withStyle(opts.style).withLineHeight(opts.line_height_factor);
}

pub fn withFamily(self: Font, n: []const u8) Font {
    var r: Font = self;
    r.family = array(n);
    return r;
}

pub fn withSize(self: Font, s: f32) Font {
    var r = self;
    r.size = s;
    return r;
}

pub fn larger(self: Font, ds: f32) Font {
    var r = self;
    r.size += ds;
    return r;
}

pub fn withWeight(self: Font, w: Weight) Font {
    var r = self;
    r.weight = w;
    return r;
}

pub fn withStyle(self: Font, s: Style) Font {
    var r = self;
    r.style = s;
    return r;
}

pub fn withLineHeight(self: Font, factor: f32) Font {
    var r = self;
    r.line_height_factor = factor;
    return r;
}

pub fn familyName(self: *const Font) []const u8 {
    return string(&self.family);
}

pub fn name(self: *const Font, allocator: std.mem.Allocator) []const u8 {
    const weight = switch (self.weight) {
        .normal => "",
        .bold => " Bold",
    };
    const style = switch (self.style) {
        .normal => "",
        .italic => " Italic",
    };
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ self.familyName(), weight, style }) catch "";
}

/// Fonts that hash the same value use the same glyphs (same Font.Entry).
pub fn hash(self: *const Font) u64 {
    var h = dvui.fnv.init();
    h.update(&self.family);
    h.update(std.mem.asBytes(&self.size));
    h.update(std.mem.asBytes(&self.weight));
    h.update(std.mem.asBytes(&self.style));
    return h.final();
}

/// Only valid between Window.begin/end
pub fn findSource(self: *const Font) ?Source {
    const cw = dvui.currentWindow();
    return cw.fonts.findSource(self.*).@"0";
}

pub const Source = struct {
    family: [NAME_MAX_LEN:0]u8 = @splat(0),
    size: f32 = 0, // zero means this source can be any size
    weight: Weight = .normal,
    style: Style = .normal,

    // currently we assume that a single ttf only produces one
    bytes: []const u8, // points to ttf bytes
    /// If not null, this will be used to free ttf_bytes.
    allocator: ?std.mem.Allocator = null,

    pub fn familyName(self: *const Source) []const u8 {
        return string(&self.family);
    }

    pub fn name(self: *const Source, allocator: std.mem.Allocator) []const u8 {
        const weight = switch (self.weight) {
            .normal => "",
            .bold => " Bold",
        };
        const style = switch (self.style) {
            .normal => "",
            .italic => " Italic",
        };
        return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ self.familyName(), weight, style }) catch "";
    }

    /// Return a Font that will render from this source.
    pub fn font(self: *const Source) Font {
        return .{
            .family = self.family,
            .weight = self.weight,
            .style = self.style,
        };
    }

    pub fn deinit(self: *Source) void {
        defer self.* = undefined;
        if (self.allocator) |alloc| {
            alloc.free(self.bytes);
        }
    }

    pub const fallback = Source{
        .family = array("Vera"),
        .bytes = @embedFile("fonts/bitstream-vera/Vera.ttf"),
    };
};

pub fn textHeight(self: Font) f32 {
    return self.sizeM(1, 1).h;
}

pub fn lineHeight(self: Font) f32 {
    return self.textHeight() * self.line_height_factor;
}

pub fn sizeM(self: Font, wide: f32, tall: f32) Size {
    const msize: Size = self.textSize("M");
    return .{ .w = msize.w * wide, .h = msize.h * tall };
}

/// handles multiple lines
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textSize(self: Font, text: []const u8) Size {
    if (text.len == 0) {
        // just want the normal text height
        return .{ .w = 0, .h = self.textHeight() };
    }

    var ret = Size{};

    var line_height_adj: f32 = undefined;
    var end: usize = 0;
    while (end < text.len) {
        if (end > 0) {
            ret.h += line_height_adj;
        }

        var end_idx: usize = undefined;
        const s = self.textSizeEx(text[end..], .{ .end_idx = &end_idx, .end_metric = .before });
        line_height_adj = s.h * (self.line_height_factor - 1.0);
        ret.h += s.h;
        ret.w = @max(ret.w, s.w);

        end += end_idx;
    }

    return ret;
}

pub const EndMetric = enum {
    before, // end_idx stops before text goes past max_width
    nearest, // end_idx stops at start of character closest to max_width
};

pub const TextSizeOptions = struct {
    max_width: ?f32 = null,
    end_idx: ?*usize = null,
    end_metric: EndMetric = .before,
    kerning: ?bool = null,
    kern_in: ?[]u32 = null,
    kern_out: ?[]u32 = null,
};

/// textSizeEx always stops at a newline, use textSize to get multiline sizes
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textSizeEx(self: Font, text: []const u8, opts: TextSizeOptions) Size {
    // ask for a font that matches the natural display pixels so we get a more
    // accurate size
    const ss = dvui.parentGet().screenRectScale(Rect{}).s;
    const ask_size = self.size * ss;
    const sized_font = self.withSize(ask_size);

    const cw = dvui.currentWindow();

    // might give us a slightly smaller font
    const fce = dvui.fontCacheGet(sized_font) catch return .{ .w = 10, .h = 10 };

    // this must be synced with dvui.renderText()
    const target_fraction = if (cw.snap_to_pixels) 1.0 / ss else self.size / fce.height;

    var options = opts;
    if (opts.max_width) |mwidth| {
        // convert max_width into font units
        options.max_width = mwidth / target_fraction;
    }
    options.kerning = opts.kerning orelse cw.kerning;

    var s = fce.textSizeRaw(cw.gpa, text, options) catch return .{ .w = 10, .h = 10 };

    // do this check after calling textSizeRaw so that end_idx is set
    if (ask_size == 0.0) return Size{};

    // convert size back from font units
    return s.scale(target_fraction, Size);
}

pub const Cache = struct {
    database: std.ArrayList(Source) = .empty,
    cache: dvui.TrackingAutoHashMap(u64, Entry, .get_and_put) = .empty,

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

        const source = exact orelse blk: {
            if (second) |s| {
                const sname = s.name(gpa);
                defer gpa.free(sname);
                dvui.log.err("Font {s} not in dvui database, using second best {s}", .{ fname, sname });
                break :blk s;
            } else {
                dvui.log.err("Font {s} not in dvui database, using fallback", .{fname});
                break :blk Source.fallback;
            }
        };

        //log.debug("FontCacheGet creating font hash {x} ptr {*} size {d} name \"{s}\"", .{ fontHash, bytes.ptr, font.size, font.name });

        entry.value_ptr.* = Entry.init(gpa, source.bytes, font) catch |err| {
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
        height: f32,
        ascent: f32,
        glyph_info: std.AutoHashMapUnmanaged(u32, GlyphInfo) = .empty,
        glyph_info_ascii: [ascii_size - ascii_start]GlyphInfo,
        texture_atlas_cache: ?Texture = null,

        const ascii_size = 127;
        const ascii_start = 32;

        const GlyphInfo = struct {
            advance: f32, // horizontal distance to move the pen
            leftBearing: f32, // horizontal distance from pen to bounding box left edge
            topBearing: f32, // vertical distance from font ascent to bounding box top edge
            w: f32, // width of bounding box
            h: f32, // height of bounding box
            uv: @Vector(2, f32),
        };

        /// Load the underlying font at an integer size <= font.size (guaranteed to have a minimum pixel size of 1)
        pub fn init(gpa: std.mem.Allocator, ttf_bytes: []const u8, font: Font) Error!Entry {
            const min_pixel_size = 1;

            const fname = font.name(gpa);
            errdefer gpa.free(fname);

            var self: Entry = if (impl == .FreeType) blk: {
                var face: c.FT_Face = undefined;
                var args: c.FT_Open_Args = undefined;
                args.flags = @as(u32, @bitCast(FreeType.OpenFlags{ .memory = true }));
                args.memory_base = ttf_bytes.ptr;
                args.memory_size = @as(u31, @intCast(ttf_bytes.len));
                FreeType.intToError(c.FT_Open_Face(dvui.ft2lib, &args, 0, &face)) catch |err| {
                    dvui.log.warn("Font.Cache.Entry.init() freetype error {any} trying to FT_Open_Face font {s}\n", .{ err, fname });
                    return Error.FontError;
                };

                // "pixel size" for freetype doesn't actually mean you'll get that height, it's more like using pts
                // so we search for a font that has a height <= font.size
                var pixel_size = @as(u32, @intFromFloat(@max(min_pixel_size, @floor(font.size))));

                while (true) : (pixel_size -= 1) {
                    FreeType.intToError(c.FT_Set_Pixel_Sizes(face, pixel_size, pixel_size)) catch |err| {
                        dvui.log.warn("Font.Cache.Entry.init() freetype error {any} trying to FT_Set_Pixel_Sizes font {s}\n", .{ err, fname });
                        return Error.FontError;
                    };

                    const ascender = @as(f32, @floatFromInt(face.*.ascender)) / 64.0;
                    const ss = @as(f32, @floatFromInt(face.*.size.*.metrics.y_scale)) / 0x10000;
                    const ascent = ascender * ss;
                    const height = @as(f32, @floatFromInt(face.*.size.*.metrics.height)) / 64.0;

                    //std.debug.print("height {d} -> pixel_size {d}\n", .{ height, pixel_size });

                    if (height <= font.size or pixel_size == min_pixel_size) {
                        break :blk .{
                            .face = face,
                            .name = fname,
                            .scaleFactor = 1.0, // not used with freetype
                            .height = @ceil(height),
                            .ascent = @floor(ascent),
                            .glyph_info_ascii = undefined,
                        };
                    }
                }
            } else blk: {
                const offset = c.stbtt_GetFontOffsetForIndex(ttf_bytes.ptr, 0);
                if (offset < 0) {
                    dvui.log.warn("Font.Cache.Entry.init() stbtt error when calling stbtt_GetFontOffsetForIndex font {s}\n", .{fname});
                    return Error.FontError;
                }
                var face: c.stbtt_fontinfo = undefined;
                if (c.stbtt_InitFont(&face, ttf_bytes.ptr, offset) != 1) {
                    dvui.log.warn("Font.Cache.Entry.init() stbtt error when calling stbtt_InitFont font {s}\n", .{fname});
                    return Error.FontError;
                }
                const SF: f32 = c.stbtt_ScaleForPixelHeight(&face, @max(min_pixel_size, @floor(font.size)));

                var face2_ascent: c_int = undefined;
                var face2_descent: c_int = undefined;
                var face2_linegap: c_int = undefined;
                c.stbtt_GetFontVMetrics(&face, &face2_ascent, &face2_descent, &face2_linegap);
                const ascent = SF * @as(f32, @floatFromInt(face2_ascent));
                const f2_descent = SF * @as(f32, @floatFromInt(face2_descent));
                const f2_linegap = SF * @as(f32, @floatFromInt(face2_linegap));
                const height = ascent - f2_descent + f2_linegap;

                break :blk .{
                    .face = face,
                    .name = fname,
                    .scaleFactor = SF,
                    .height = @ceil(height),
                    .ascent = @floor(ascent),
                    .glyph_info_ascii = undefined,
                };
            };

            // Pre-generate the ascii glyphs
            for (0..self.glyph_info_ascii.len) |i| {
                self.glyph_info_ascii[i] = try self.glyphInfoGenerate(@intCast(i + ascii_start));
            }

            return self;
        }

        pub fn deinit(self: *Entry, gpa: std.mem.Allocator, backend: Backend) void {
            defer self.* = undefined;
            gpa.free(self.name);
            self.glyph_info.deinit(gpa);
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
            const row_glyphs = @as(u32, @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(total))))));

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

            var pixels = try gpa.alloc(dvui.Color.PMA, @as(usize, @intFromFloat(s.w * s.h)));
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
                    FreeType.intToError(c.FT_Load_Char(self.face, codepoint, @as(i32, @bitCast(FreeType.LoadFlags{ .render = true })))) catch |err| {
                        dvui.log.warn("renderText: freetype error {any} trying to FT_Load_Char codepoint {d}", .{ err, codepoint });
                        break :blk; // will skip the failing glyph
                    };

                    // https://freetype.org/freetype2/docs/tutorial/step1.html#section-6
                    if (self.face.*.glyph.*.format != c.FT_GLYPH_FORMAT_BITMAP) {
                        FreeType.intToError(c.FT_Render_Glyph(self.face.*.glyph, c.FT_RENDER_MODE_NORMAL)) catch |err| {
                            dvui.log.warn("renderText freetype error {any} trying to FT_Render_Glyph codepoint {d}", .{ err, codepoint });
                            break :blk; // will skip the failing glyph
                        };
                    }

                    const bitmap = self.face.*.glyph.*.bitmap;
                    row_height = @max(row_height, bitmap.rows);
                    var row: i32 = 0;
                    while (row < bitmap.rows) : (row += 1) {
                        var col: i32 = 0;
                        while (col < bitmap.width) : (col += 1) {
                            const src = bitmap.buffer[@as(usize, @intCast(row * bitmap.pitch + col))];

                            // because of the extra edge, offset by 1 row and 1 col
                            const di = @as(usize, @intCast((y + row + pad) * @as(i32, @intFromFloat(s.w)) + (x + col + pad)));

                            // premultiplied white
                            pixels[di] = .{ .r = src, .g = src, .b = src, .a = src };
                        }
                    }
                } else {
                    const out_w: u32 = @intFromFloat(gi.w);
                    const out_h: u32 = @intFromFloat(gi.h);
                    row_height = @max(row_height, out_h);

                    // single channel
                    const bitmap = try gpa.alloc(u8, @as(usize, out_w * out_h));
                    defer gpa.free(bitmap);

                    //log.debug("makecodepointBitmap size x {d} y {d} w {d} h {d} out w {d} h {d}", .{ x, y, s.w, s.h, out_w, out_h });

                    c.stbtt_MakeCodepointBitmapSubpixel(&self.face, bitmap.ptr, @as(c_int, @intCast(out_w)), @as(c_int, @intCast(out_h)), @as(c_int, @intCast(out_w)), self.scaleFactor, self.scaleFactor, 0.0, 0.0, @as(c_int, @intCast(codepoint)));

                    const stride = @as(usize, @intFromFloat(s.w));
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

                x += @as(i32, @intFromFloat(gi.w)) + 2 * pad;

                i += 1;
                if (i % row_glyphs == 0) {
                    x = pad;
                    y += @intCast(row_height + 2 * pad);
                    row_height = 0;
                }
            }

            self.texture_atlas_cache = try backend.textureCreate(@ptrCast(pixels.ptr), @as(u32, @intFromFloat(s.w)), @as(u32, @intFromFloat(s.h)), .linear);
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

        pub fn glyphInfoGenerate(self: *Entry, codepoint: u32) Error!GlyphInfo {
            const gi: GlyphInfo = if (impl == .FreeType) blk: {
                FreeType.intToError(c.FT_Load_Char(self.face, codepoint, @as(i32, @bitCast(FreeType.LoadFlags{ .render = false })))) catch |err| {
                    dvui.log.warn("glyphInfoGet freetype error {any} font {s} codepoint {d}\n", .{ err, self.name, codepoint });
                    return Error.FontError;
                };

                const m = self.face.*.glyph.*.metrics;
                const minx = @as(f32, @floatFromInt(m.horiBearingX)) / 64.0;
                const miny = self.ascent - @as(f32, @floatFromInt(m.horiBearingY)) / 64.0;

                break :blk .{
                    .advance = @ceil(@as(f32, @floatFromInt(m.horiAdvance)) / 64.0),
                    .leftBearing = @floor(minx),
                    .topBearing = @floor(miny),
                    .w = @ceil(minx + @as(f32, @floatFromInt(m.width)) / 64.0) - @floor(minx),
                    .h = @ceil(miny + @as(f32, @floatFromInt(m.height)) / 64.0) - @floor(miny),
                    .uv = .{ 0, 0 },
                };
            } else blk: {
                var advanceWidth: c_int = undefined;
                var leftSideBearing: c_int = undefined;
                c.stbtt_GetCodepointHMetrics(&self.face, @as(c_int, @intCast(codepoint)), &advanceWidth, &leftSideBearing);
                var ix0: c_int = undefined;
                var iy0: c_int = undefined;
                var ix1: c_int = undefined;
                var iy1: c_int = undefined;
                const ret = c.stbtt_GetCodepointBox(&self.face, @as(c_int, @intCast(codepoint)), &ix0, &iy0, &ix1, &iy1);
                const x0: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(ix0));
                const y0: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(iy0));
                const x1: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(ix1));
                const y1: f32 = if (ret == 0) 0 else self.scaleFactor * @as(f32, @floatFromInt(iy1));

                //std.debug.print("{d} codepoint {d} stbtt x0 {d} {d} x1 {d} {d} y0 {d} {d} y1 {d} {d}\n", .{ self.ascent, codepoint, ix0, x0, ix1, x1, iy0, y0, iy1, y1 });

                break :blk .{
                    .advance = self.scaleFactor * @as(f32, @floatFromInt(advanceWidth)),
                    .leftBearing = @floor(x0),
                    .topBearing = self.ascent - @ceil(y1),
                    .w = @ceil(x1) - @floor(x0),
                    .h = @ceil(y1) - @floor(y0),
                    .uv = .{ 0, 0 },
                };
            };
            //std.debug.print("codepoint {d} advance {d} leftBearing {d} topBearing {d} w {d} h {d}\n", .{ codepoint, gi.advance, gi.leftBearing, gi.topBearing, gi.w, gi.h });
            return gi;
        }

        pub fn kern(fce: *Entry, codepoint1: u32, codepoint2: u32) f32 {
            if (impl == .FreeType) {
                const index1 = c.FT_Get_Char_Index(fce.face, codepoint1);
                const index2 = c.FT_Get_Char_Index(fce.face, codepoint2);
                var k: c.FT_Vector = undefined;
                FreeType.intToError(c.FT_Get_Kerning(fce.face, index1, index2, c.FT_KERNING_DEFAULT, &k)) catch |err| {
                    dvui.log.warn("renderText freetype error {any} trying to FT_Get_Kerning font {s} codepoints {d} {d}\n", .{ err, fce.name, codepoint1, codepoint2 });
                    k.x = 0;
                    k.y = 0;
                };

                return @as(f32, @floatFromInt(k.x)) / 64.0;
            } else {
                const kern_adv: c_int = c.stbtt_GetCodepointKernAdvance(&fce.face, @as(c_int, @intCast(codepoint1)), @as(c_int, @intCast(codepoint2)));
                return fce.scaleFactor * @as(f32, @floatFromInt(kern_adv));
            }
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

            var x: f32 = 0;
            var minx: f32 = 0;
            var maxx: f32 = 0;
            var miny: f32 = 0;
            var maxy: f32 = self.height;
            var tw: f32 = 0;
            var th: f32 = self.height;

            var ei: usize = 0;
            var nearest_break: bool = false;

            const kerning: bool = opts.kerning orelse true;
            var last_codepoint: u32 = 0;
            var next_kern_idx: u32 = 0;
            var next_kern_byte: u32 = 0;
            if (opts.kern_in) |ki| {
                next_kern_byte = ki[next_kern_idx];
                next_kern_idx += 1;
            }

            var i: usize = 0;
            while (i < text.len) {
                const cplen = std.unicode.utf8ByteSequenceLength(text[i]) catch unreachable;
                const codepoint = std.unicode.utf8Decode(text[i..][0..cplen]) catch unreachable;
                const gi = try self.glyphInfoGetOrReplacement(gpa, codepoint);

                if (kerning and last_codepoint != 0 and i >= next_kern_byte) {
                    const kk = self.kern(last_codepoint, codepoint);
                    x += kk;

                    if (opts.kern_in) |ki| {
                        if (next_kern_idx < ki.len) {
                            next_kern_byte = ki[next_kern_idx];
                            next_kern_idx += 1;
                        }
                    }

                    if (kk != 0) {
                        if (opts.kern_out) |ko| {
                            // fill in first 0
                            for (ko) |*k| {
                                if (k.* == 0) {
                                    k.* = @intCast(i);
                                    break;
                                }
                            }
                        }
                    }
                }

                i += cplen;
                last_codepoint = codepoint;

                minx = @min(minx, x + gi.leftBearing);
                maxx = @max(maxx, x + gi.leftBearing + gi.w);
                maxx = @max(maxx, x + gi.advance);

                miny = @min(miny, gi.topBearing);
                maxy = @max(maxy, gi.topBearing + gi.h);

                if (codepoint == '\n') {
                    // newlines always terminate, and don't use any space
                    ei += 1;
                    break;
                }

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
                x += gi.advance;

                if (nearest_break) break;
            }

            // TODO: xstart and ystart

            if (opts.end_idx) |endout| {
                endout.* = ei;
            }

            if (opts.kern_out) |ko| {
                // fill in first 0
                for (ko) |*k| {
                    if (k.* == 0) {
                        k.* = @intCast(i);
                        break;
                    }
                }
            }

            //std.debug.print("textSizeRaw size {d} for \"{s}\" {d}x{d} {d}\n", .{ self.size, text, tw, th, ei });
            return Size{ .w = tw, .h = th };
        }
    };
};

pub const FreeType = struct {
    pub const OpenFlags = packed struct(c_int) {
        memory: bool = false,
        stream: bool = false,
        path: bool = false,
        driver: bool = false,
        params: bool = false,
        _padding: u27 = 0,
    };

    pub const LoadFlags = packed struct(c_int) {
        no_scale: bool = false,
        no_hinting: bool = false,
        render: bool = false,
        no_bitmap: bool = false,
        vertical_layout: bool = false,
        force_autohint: bool = false,
        crop_bitmap: bool = false,
        pedantic: bool = false,
        ignore_global_advance_with: bool = false,
        no_recurse: bool = false,
        ignore_transform: bool = false,
        monochrome: bool = false,
        linear_design: bool = false,
        no_autohint: bool = false,
        _padding: u1 = 0,
        target_normal: bool = false,
        target_light: bool = false,
        target_mono: bool = false,
        target_lcd: bool = false,
        target_lcd_v: bool = false,
        color: bool = false,
        compute_metrics: bool = false,
        bitmap_metrics_only: bool = false,
        _padding0: u9 = 0,
    };

    pub fn intToError(err: c_int) !void {
        return switch (err) {
            c.FT_Err_Ok => {},
            c.FT_Err_Cannot_Open_Resource => error.CannotOpenResource,
            c.FT_Err_Unknown_File_Format => error.UnknownFileFormat,
            c.FT_Err_Invalid_File_Format => error.InvalidFileFormat,
            c.FT_Err_Invalid_Version => error.InvalidVersion,
            c.FT_Err_Lower_Module_Version => error.LowerModuleVersion,
            c.FT_Err_Invalid_Argument => error.InvalidArgument,
            c.FT_Err_Unimplemented_Feature => error.UnimplementedFeature,
            c.FT_Err_Invalid_Table => error.InvalidTable,
            c.FT_Err_Invalid_Offset => error.InvalidOffset,
            c.FT_Err_Array_Too_Large => error.ArrayTooLarge,
            c.FT_Err_Missing_Module => error.MissingModule,
            c.FT_Err_Missing_Property => error.MissingProperty,
            c.FT_Err_Invalid_Glyph_Index => error.InvalidGlyphIndex,
            c.FT_Err_Invalid_Character_Code => error.InvalidCharacterCode,
            c.FT_Err_Invalid_Glyph_Format => error.InvalidGlyphFormat,
            c.FT_Err_Cannot_Render_Glyph => error.CannotRenderGlyph,
            c.FT_Err_Invalid_Outline => error.InvalidOutline,
            c.FT_Err_Invalid_Composite => error.InvalidComposite,
            c.FT_Err_Too_Many_Hints => error.TooManyHints,
            c.FT_Err_Invalid_Pixel_Size => error.InvalidPixelSize,
            c.FT_Err_Invalid_Handle => error.InvalidHandle,
            c.FT_Err_Invalid_Library_Handle => error.InvalidLibraryHandle,
            c.FT_Err_Invalid_Driver_Handle => error.InvalidDriverHandle,
            c.FT_Err_Invalid_Face_Handle => error.InvalidFaceHandle,
            c.FT_Err_Invalid_Size_Handle => error.InvalidSizeHandle,
            c.FT_Err_Invalid_Slot_Handle => error.InvalidSlotHandle,
            c.FT_Err_Invalid_CharMap_Handle => error.InvalidCharMapHandle,
            c.FT_Err_Invalid_Cache_Handle => error.InvalidCacheHandle,
            c.FT_Err_Invalid_Stream_Handle => error.InvalidStreamHandle,
            c.FT_Err_Too_Many_Drivers => error.TooManyDrivers,
            c.FT_Err_Too_Many_Extensions => error.TooManyExtensions,
            c.FT_Err_Out_Of_Memory => error.OutOfMemory,
            c.FT_Err_Unlisted_Object => error.UnlistedObject,
            c.FT_Err_Cannot_Open_Stream => error.CannotOpenStream,
            c.FT_Err_Invalid_Stream_Seek => error.InvalidStreamSeek,
            c.FT_Err_Invalid_Stream_Skip => error.InvalidStreamSkip,
            c.FT_Err_Invalid_Stream_Read => error.InvalidStreamRead,
            c.FT_Err_Invalid_Stream_Operation => error.InvalidStreamOperation,
            c.FT_Err_Invalid_Frame_Operation => error.InvalidFrameOperation,
            c.FT_Err_Nested_Frame_Access => error.NestedFrameAccess,
            c.FT_Err_Invalid_Frame_Read => error.InvalidFrameRead,
            c.FT_Err_Raster_Uninitialized => error.RasterUninitialized,
            c.FT_Err_Raster_Corrupted => error.RasterCorrupted,
            c.FT_Err_Raster_Overflow => error.RasterOverflow,
            c.FT_Err_Raster_Negative_Height => error.RasterNegativeHeight,
            c.FT_Err_Too_Many_Caches => error.TooManyCaches,
            c.FT_Err_Invalid_Opcode => error.InvalidOpcode,
            c.FT_Err_Too_Few_Arguments => error.TooFewArguments,
            c.FT_Err_Stack_Overflow => error.StackOverflow,
            c.FT_Err_Code_Overflow => error.CodeOverflow,
            c.FT_Err_Bad_Argument => error.BadArgument,
            c.FT_Err_Divide_By_Zero => error.DivideByZero,
            c.FT_Err_Invalid_Reference => error.InvalidReference,
            c.FT_Err_Debug_OpCode => error.DebugOpCode,
            c.FT_Err_ENDF_In_Exec_Stream => error.ENDFInExecStream,
            c.FT_Err_Nested_DEFS => error.NestedDEFS,
            c.FT_Err_Invalid_CodeRange => error.InvalidCodeRange,
            c.FT_Err_Execution_Too_Long => error.ExecutionTooLong,
            c.FT_Err_Too_Many_Function_Defs => error.TooManyFunctionDefs,
            c.FT_Err_Too_Many_Instruction_Defs => error.TooManyInstructionDefs,
            c.FT_Err_Table_Missing => error.TableMissing,
            c.FT_Err_Horiz_Header_Missing => error.HorizHeaderMissing,
            c.FT_Err_Locations_Missing => error.LocationsMissing,
            c.FT_Err_Name_Table_Missing => error.NameTableMissing,
            c.FT_Err_CMap_Table_Missing => error.CMapTableMissing,
            c.FT_Err_Hmtx_Table_Missing => error.HmtxTableMissing,
            c.FT_Err_Post_Table_Missing => error.PostTableMissing,
            c.FT_Err_Invalid_Horiz_Metrics => error.InvalidHorizMetrics,
            c.FT_Err_Invalid_CharMap_Format => error.InvalidCharMapFormat,
            c.FT_Err_Invalid_PPem => error.InvalidPPem,
            c.FT_Err_Invalid_Vert_Metrics => error.InvalidVertMetrics,
            c.FT_Err_Could_Not_Find_Context => error.CouldNotFindContext,
            c.FT_Err_Invalid_Post_Table_Format => error.InvalidPostTableFormat,
            c.FT_Err_Invalid_Post_Table => error.InvalidPostTable,
            c.FT_Err_Syntax_Error => error.Syntax,
            c.FT_Err_Stack_Underflow => error.StackUnderflow,
            c.FT_Err_Ignore => error.Ignore,
            c.FT_Err_No_Unicode_Glyph_Name => error.NoUnicodeGlyphName,
            c.FT_Err_Missing_Startfont_Field => error.MissingStartfontField,
            c.FT_Err_Missing_Font_Field => error.MissingFontField,
            c.FT_Err_Missing_Size_Field => error.MissingSizeField,
            c.FT_Err_Missing_Fontboundingbox_Field => error.MissingFontboundingboxField,
            c.FT_Err_Missing_Chars_Field => error.MissingCharsField,
            c.FT_Err_Missing_Startchar_Field => error.MissingStartcharField,
            c.FT_Err_Missing_Encoding_Field => error.MissingEncodingField,
            c.FT_Err_Missing_Bbx_Field => error.MissingBbxField,
            c.FT_Err_Bbx_Too_Big => error.BbxTooBig,
            c.FT_Err_Corrupted_Font_Header => error.CorruptedFontHeader,
            c.FT_Err_Corrupted_Font_Glyphs => error.CorruptedFontGlyphs,
            else => unreachable,
        };
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
