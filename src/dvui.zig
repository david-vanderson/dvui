const builtin = @import("builtin");
const std = @import("std");
pub const backend_kind = @import("build_options").backend;
pub const backend = @import("backend");
const tvg = @import("tinyvg/tinyvg.zig");

pub const math = std.math;
pub const fnv = std.hash.Fnv1a_32;

pub const Backend = @import("Backend.zig");
pub const Color = @import("Color.zig");
pub const Examples = @import("Examples.zig");
pub const Event = @import("Event.zig");
pub const Font = @import("Font.zig");
pub const Options = @import("Options.zig");
pub const Point = @import("Point.zig");
pub const Rect = @import("Rect.zig");
pub const RectScale = @import("RectScale.zig");
pub const ScrollInfo = @import("ScrollInfo.zig");
pub const Size = @import("Size.zig");
pub const Theme = @import("Theme.zig");
pub const Vertex = @import("Vertex.zig");
pub const Widget = @import("Widget.zig");
pub const WidgetData = @import("WidgetData.zig");
pub const entypo = @import("icons/entypo.zig");
pub const AnimateWidget = @import("widgets/AnimateWidget.zig");
pub const BoxWidget = @import("widgets/BoxWidget.zig");
pub const CacheWidget = @import("widgets/CacheWidget.zig");
pub const FlexBoxWidget = @import("widgets/FlexBoxWidget.zig");
pub const ReorderWidget = @import("widgets/ReorderWidget.zig");
pub const Reorderable = ReorderWidget.Reorderable;
pub const ButtonWidget = @import("widgets/ButtonWidget.zig");
pub const ContextWidget = @import("widgets/ContextWidget.zig");
pub const FloatingWindowWidget = @import("widgets/FloatingWindowWidget.zig");
pub const FloatingWidget = @import("widgets/FloatingWidget.zig");
pub const FloatingMenuWidget = @import("widgets/FloatingMenuWidget.zig");
pub const IconWidget = @import("widgets/IconWidget.zig");
pub const ImageWidget = @import("widgets/ImageWidget.zig");
pub const LabelWidget = @import("widgets/LabelWidget.zig");
pub const MenuWidget = @import("widgets/MenuWidget.zig");
pub const MenuItemWidget = @import("widgets/MenuItemWidget.zig");
pub const OverlayWidget = @import("widgets/OverlayWidget.zig");
pub const PanedWidget = @import("widgets/PanedWidget.zig");
pub const ScaleWidget = @import("widgets/ScaleWidget.zig");
pub const ScrollAreaWidget = @import("widgets/ScrollAreaWidget.zig");
pub const ScrollBarWidget = @import("widgets/ScrollBarWidget.zig");
pub const ScrollContainerWidget = @import("widgets/ScrollContainerWidget.zig");
pub const TextEntryWidget = @import("widgets/TextEntryWidget.zig");
pub const TextLayoutWidget = @import("widgets/TextLayoutWidget.zig");
pub const VirtualParentWidget = @import("widgets/VirtualParentWidget.zig");

const se = @import("structEntry.zig");
pub const structEntry = se.structEntry;
pub const structEntryEx = se.structEntryEx;
pub const structEntryAlloc = se.structEntryAlloc;
pub const structEntryExAlloc = se.structEntryExAlloc;
pub const StructFieldOptions = se.StructFieldOptions;

pub const enums = @import("enums.zig");

pub const wasm = (builtin.target.cpu.arch == .wasm32);
pub const useFreeType = !wasm;

pub const c = @cImport({
    // musl fails to compile saying missing "bits/setjmp.h", and nobody should
    // be using setjmp anyway
    @cDefine("_SETJMP_H", "1");

    if (useFreeType) {
        @cInclude("freetype/ftadvanc.h");
        @cInclude("freetype/ftbbox.h");
        @cInclude("freetype/ftbitmap.h");
        @cInclude("freetype/ftcolor.h");
        @cInclude("freetype/ftlcdfil.h");
        @cInclude("freetype/ftsizes.h");
        @cInclude("freetype/ftstroke.h");
        @cInclude("freetype/fttrigon.h");
    } else {
        @cInclude("stb_truetype.h");
    }

    @cInclude("stb_image.h");

    if (!wasm) {
        @cInclude("tinyfiledialogs.h");
    }
});

var ft2lib: if (useFreeType) c.FT_Library else void = undefined;

pub const Error = error{ OutOfMemory, InvalidUtf8, freetypeError, tvgError, stbiError };

pub const log = std.log.scoped(.dvui);
const dvui = @This();

var current_window: ?*Window = null;

/// Get the current dvui.Window which corresponds to the OS window we are
/// currently adding widgets to.
///
/// Only valid between dvui.Window.begin() and end().
pub fn currentWindow() *Window {
    return current_window orelse unreachable;
}

/// Get a pointer to the active theme.
///
/// Only valid between dvui.Window.begin() and end().
pub fn themeGet() *Theme {
    return &currentWindow().theme;
}

/// Set the active theme (copies into internal storage).
///
/// Only valid between dvui.Window.begin() and end().
pub fn themeSet(theme: *const Theme) void {
    currentWindow().theme = theme.*;
}

/// Toggle showing the debug window (run during Window.end()).
///
/// Only valid between dvui.Window.begin() and end().
pub fn toggleDebugWindow() void {
    var cw = currentWindow();
    cw.debug_window_show = !cw.debug_window_show;
}

pub const Alignment = struct {
    id: u32 = undefined,
    scale: f32 = undefined,
    max: ?f32 = undefined,
    next: f32 = undefined,

    pub fn init() Alignment {
        const wd = dvui.parentGet().data();
        return .{
            .id = wd.id,
            .scale = wd.rectScale().s,
            .max = dvui.dataGet(null, wd.id, "_max_align", f32),
            .next = -1_000_000,
        };
    }

    pub fn spacer(self: *Alignment, src: std.builtin.SourceLocation, id: u32) !void {
        const uniqueId = dvui.parentGet().extendId(src, id);
        var wd = try dvui.spacer(src, .{}, .{ .margin = self.margin(uniqueId), .id_extra = id });
        self.record(uniqueId, &wd);
    }

    pub fn margin(self: *Alignment, id: u32) Rect {
        if (self.max) |m| {
            if (dvui.dataGet(null, id, "_align", f32)) |a| {
                return .{ .x = @max(0, (m - a) / self.scale) };
            }
        }

        return .{};
    }

    pub fn record(self: *Alignment, id: u32, wd: *WidgetData) void {
        const x = wd.rectScale().r.x;
        dvui.dataSet(null, id, "_align", x);
        self.next = @max(self.next, x);
    }

    pub fn deinit(self: *Alignment) void {
        dvui.dataSet(null, self.id, "_max_align", self.next);
        if (self.max) |m| {
            if (self.next != m) {
                // something changed
                refresh(null, @src(), self.id);
            }
        }
    }
};

/// Adjust start rect based on screen and spawner (like a context menu).
///
/// When adding a floating widget or window, often we want to guarantee that it
/// is visible.  Additionally, if start is logically connected to a spawning
/// rect (like a context menu spawning a submenu), then jump to the opposite
/// side if needed.
pub fn placeOnScreen(screen: Rect, spawner: Rect, start: Rect) Rect {
    var r = start;
    if ((r.x + r.w) > (screen.x + screen.w)) {
        if (spawner.w == 0) {
            // if we were given just point, we can slide just to be on the screen
            r.x = (screen.x + screen.w) - r.w;
        } else {
            // if spawner has content, then we want to jump to the other side
            r.x = spawner.x - spawner.w - r.w;
        }
    }

    // if off left, move
    if (r.x < screen.x) {
        r.x = screen.x;
    }

    // if off right, shrink to fit (but not to zero)
    // - if we went to zero, then a window could get into a state where you can
    // no longer see it or interact with it (like if you resize the OS window
    // to zero size and back)
    if ((r.x + r.w) > (screen.x + screen.w)) {
        r.w = @max(24, (screen.x + screen.w) - r.x);
    }

    // if off bottom, first try moving
    if ((r.y + r.h) > (screen.y + screen.h)) {
        r.y = (screen.y + screen.h) - r.h;
    }

    // if off top, move
    if (r.y < screen.y) {
        r.y = screen.y;
    }

    // if still off bottom, shrink to fit (but not to zero)
    if ((r.y + r.h) > (screen.y + screen.h)) {
        r.h = @max(24, (screen.y + screen.h) - r.y);
    }

    return r;
}

/// Nanosecond timestamp for this frame.
///
/// Updated during Window.begin().  Will not go backwards.
///
/// Only valid between dvui.Window.begin() and end().
pub fn frameTimeNS() i128 {
    return currentWindow().frame_time_ns;
}

/// The bytes of a truetype font file and whether to free it.
pub const FontBytesEntry = struct {
    ttf_bytes: []const u8,

    /// If not null, this will be used to free ttf_bytes.
    allocator: ?std.mem.Allocator,
};

const GlyphInfo = struct {
    advance: f32, // horizontal distance to move the pen
    leftBearing: f32, // horizontal distance from pen to bounding box left edge
    topBearing: f32, // vertical distance from font ascent to bounding box top edge
    w: f32, // width of bounding box
    h: f32, // height of bounding box
    uv: @Vector(2, f32),
};

const FontCacheEntry = struct {
    used: bool = true,
    face: if (useFreeType) c.FT_Face else c.stbtt_fontinfo,
    scaleFactor: f32,
    height: f32,
    ascent: f32,
    glyph_info: std.AutoHashMap(u32, GlyphInfo),
    texture_atlas: *anyopaque,
    texture_atlas_size: Size,
    texture_atlas_regen: bool,

    pub fn deinit(self: *FontCacheEntry, win: *Window) void {
        if (useFreeType) {
            _ = c.FT_Done_Face(self.face);
        }
        win.backend.textureDestroy(self.texture_atlas);
    }

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

    pub fn hash(font: Font) u32 {
        var h = fnv.init();
        var bytes: []const u8 = undefined;
        if (currentWindow().font_bytes.get(font.name)) |fbe| {
            bytes = fbe.ttf_bytes;
        } else {
            bytes = Font.default_ttf_bytes;
        }
        h.update(std.mem.asBytes(&bytes.ptr));
        h.update(std.mem.asBytes(&font.size));
        return h.final();
    }

    pub fn glyphInfoGet(self: *FontCacheEntry, codepoint: u32, font_name: []const u8) !GlyphInfo {
        if (self.glyph_info.get(codepoint)) |gi| {
            return gi;
        }

        var gi: GlyphInfo = undefined;

        if (useFreeType) {
            FontCacheEntry.intToError(c.FT_Load_Char(self.face, codepoint, @as(i32, @bitCast(LoadFlags{ .render = false })))) catch |err| {
                log.warn("glyphInfoGet freetype error {!} font {s} codepoint {d}\n", .{ err, font_name, codepoint });
                return error.freetypeError;
            };

            const m = self.face.*.glyph.*.metrics;
            const minx = @as(f32, @floatFromInt(m.horiBearingX)) / 64.0;
            const miny = self.ascent - @as(f32, @floatFromInt(m.horiBearingY)) / 64.0;

            gi = GlyphInfo{
                .advance = @ceil(@as(f32, @floatFromInt(m.horiAdvance)) / 64.0),
                .leftBearing = @floor(minx),
                .topBearing = @floor(miny),
                .w = @ceil(minx + @as(f32, @floatFromInt(m.width)) / 64.0) - @floor(minx),
                .h = @ceil(miny + @as(f32, @floatFromInt(m.height)) / 64.0) - @floor(miny),
                .uv = .{ 0, 0 },
            };
        } else {
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

            //std.debug.print("codepoint {d} stbtt x0 {d} x1 {d} y0 {d} y1 {d}\n", .{ codepoint, x0, x1, y0, y1 });

            gi = GlyphInfo{
                .advance = self.scaleFactor * @as(f32, @floatFromInt(advanceWidth)),
                .leftBearing = @floor(x0),
                .topBearing = self.ascent - @ceil(y1),
                .w = @ceil(x1) - @floor(x0),
                .h = @ceil(y1) - @floor(y0),
                .uv = .{ 0, 0 },
            };
        }

        //std.debug.print("codepoint {d} advance {d} leftBearing {d} topBearing {d} w {d} h {d}\n", .{ codepoint, gi.advance, gi.leftBearing, gi.topBearing, gi.w, gi.h });

        // new glyph, need to regen texture atlas on next render
        //std.debug.print("new glyph {}\n", .{codepoint});
        self.texture_atlas_regen = true;

        try self.glyph_info.put(codepoint, gi);
        return gi;
    }

    // doesn't scale the font or max_width, always stops at newlines
    pub fn textSizeRaw(fce: *FontCacheEntry, font_name: []const u8, text: []const u8, max_width: ?f32, end_idx: ?*usize, end_metric: Font.EndMetric) !Size {
        const mwidth = max_width orelse 1000000.0;

        var x: f32 = 0;
        var minx: f32 = 0;
        var maxx: f32 = 0;
        var miny: f32 = 0;
        var maxy: f32 = fce.height;
        var tw: f32 = 0;
        var th: f32 = fce.height;

        var ei: usize = 0;
        var nearest_break: bool = false;

        var utf8 = (try std.unicode.Utf8View.init(text)).iterator();
        while (utf8.nextCodepoint()) |codepoint| {
            const gi = try fce.glyphInfoGet(@as(u32, @intCast(codepoint)), font_name);

            minx = @min(minx, x + gi.leftBearing);
            maxx = @max(maxx, x + gi.leftBearing + gi.w);
            maxx = @max(maxx, x + gi.advance);

            miny = @min(miny, gi.topBearing);
            maxy = @max(maxy, gi.topBearing + gi.h);

            // TODO: kerning

            if (codepoint == '\n') {
                // newlines always terminate, and don't use any space
                ei += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                break;
            }

            if ((maxx - minx) > mwidth) {
                switch (end_metric) {
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
            ei += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;

            // update space taken by glyph
            tw = maxx - minx;
            th = maxy - miny;
            x += gi.advance;

            if (nearest_break) break;
        }

        // TODO: xstart and ystart

        if (end_idx) |endout| {
            endout.* = ei;
        }

        //std.debug.print("textSizeRaw size {d} for \"{s}\" {d}x{d} {d}\n", .{ self.size, text, tw, th, ei });
        return Size{ .w = tw, .h = th };
    }
};

// Load the underlying font at an integer size <= font.size (guaranteed to have a minimum pixel size of 1)
pub fn fontCacheGet(font: Font) !*FontCacheEntry {
    var cw = currentWindow();
    const fontHash = FontCacheEntry.hash(font);
    if (cw.font_cache.getPtr(fontHash)) |fce| {
        fce.used = true;
        return fce;
    }

    //ttf bytes
    const bytes = blk: {
        if (currentWindow().font_bytes.get(font.name)) |fbe| {
            break :blk fbe.ttf_bytes;
        } else {
            log.warn("Font \"{s}\" not in dvui database, using default", .{font.name});
            break :blk Font.default_ttf_bytes;
        }
    };
    //log.debug("FontCacheGet creating font hash {x} ptr {*} size {d} name \"{s}\"", .{ fontHash, bytes.ptr, font.size, font.name });

    var entry: FontCacheEntry = undefined;

    // make debug texture atlas so we can see if something later goes wrong
    const size = Size{ .w = 10, .h = 10 };
    const pixels = try cw.arena().alloc(u8, @as(usize, @intFromFloat(size.w * size.h)) * 4);
    @memset(pixels, 255);

    const min_pixel_size = 1;

    if (useFreeType) {
        var face: c.FT_Face = undefined;
        var args: c.FT_Open_Args = undefined;
        args.flags = @as(u32, @bitCast(FontCacheEntry.OpenFlags{ .memory = true }));
        args.memory_base = bytes.ptr;
        args.memory_size = @as(u31, @intCast(bytes.len));
        FontCacheEntry.intToError(c.FT_Open_Face(ft2lib, &args, 0, &face)) catch |err| {
            log.warn("fontCacheGet freetype error {!} trying to FT_Open_Face font {s}\n", .{ err, font.name });
            return error.freetypeError;
        };

        // "pixel size" for freetype doesn't actually mean you'll get that height, it's more like using pts
        // so we search for a font that has a height <= font.size
        var pixel_size = @as(u32, @intFromFloat(@max(min_pixel_size, @floor(font.size))));

        while (true) : (pixel_size -= 1) {
            FontCacheEntry.intToError(c.FT_Set_Pixel_Sizes(face, pixel_size, pixel_size)) catch |err| {
                log.warn("fontCacheGet freetype error {!} trying to FT_Set_Pixel_Sizes font {s}\n", .{ err, font.name });
                return error.freetypeError;
            };

            const ascender = @as(f32, @floatFromInt(face.*.ascender)) / 64.0;
            const ss = @as(f32, @floatFromInt(face.*.size.*.metrics.y_scale)) / 0x10000;
            const ascent = ascender * ss;
            const height = @as(f32, @floatFromInt(face.*.size.*.metrics.height)) / 64.0;

            //std.debug.print("height {d} -> pixel_size {d}\n", .{ height, pixel_size });

            if (height <= font.size or pixel_size == min_pixel_size) {
                entry = FontCacheEntry{
                    .face = face,
                    .scaleFactor = 1.0, // not used with freetype
                    .height = @ceil(height),
                    .ascent = @floor(ascent),
                    .glyph_info = std.AutoHashMap(u32, GlyphInfo).init(cw.gpa),
                    .texture_atlas = textureCreate(pixels.ptr, @as(u32, @intFromFloat(size.w)), @as(u32, @intFromFloat(size.h)), .linear),
                    .texture_atlas_size = size,
                    .texture_atlas_regen = true,
                };

                break;
            }
        }
    } else {
        var face: c.stbtt_fontinfo = undefined;
        _ = c.stbtt_InitFont(&face, bytes.ptr, c.stbtt_GetFontOffsetForIndex(bytes.ptr, 0));
        const SF: f32 = c.stbtt_ScaleForPixelHeight(&face, @max(min_pixel_size, @floor(font.size)));

        var face2_ascent: c_int = undefined;
        var face2_descent: c_int = undefined;
        var face2_linegap: c_int = undefined;
        c.stbtt_GetFontVMetrics(&face, &face2_ascent, &face2_descent, &face2_linegap);
        const ascent = SF * @as(f32, @floatFromInt(face2_ascent));
        const f2_descent = SF * @as(f32, @floatFromInt(face2_descent));
        const f2_linegap = SF * @as(f32, @floatFromInt(face2_linegap));
        const height = ascent - f2_descent + f2_linegap;

        entry = FontCacheEntry{
            .face = face,
            .scaleFactor = SF,
            .height = height,
            .ascent = ascent,
            .glyph_info = std.AutoHashMap(u32, GlyphInfo).init(cw.gpa),
            .texture_atlas = textureCreate(pixels.ptr, @as(u32, @intFromFloat(size.w)), @as(u32, @intFromFloat(size.h)), .linear),
            .texture_atlas_size = size,
            .texture_atlas_regen = true,
        };
    }
    //log.debug("- size {d} ascent {d} height {d}", .{ font.size, entry.ascent, entry.height });

    errdefer {
        std.debug.assert(false);
        textureDestroyLater(entry.texture_atlas);
    }
    try cw.font_cache.putNoClobber(fontHash, entry);

    return cw.font_cache.getPtr(fontHash).?;
}

pub const TextureCacheEntry = struct {
    texture: *anyopaque,
    size: Size,
    used: bool = true,

    pub fn hash(bytes: []const u8, height: u32) u32 {
        var h = fnv.init();
        h.update(std.mem.asBytes(&bytes.ptr));
        h.update(std.mem.asBytes(&height));
        return h.final();
    }
};

/// Get the width of an icon at a specified height.
///
/// Only valid between dvui.Window.begin() and end().
pub fn iconWidth(name: []const u8, tvg_bytes: []const u8, height: f32) !f32 {
    if (height == 0) return 0.0;
    var stream = std.io.fixedBufferStream(tvg_bytes);
    var parser = tvg.parse(currentWindow().arena(), stream.reader()) catch |err| {
        log.warn("iconWidth Tinyvg error {!} parsing icon {s}\n", .{ err, name });
        return error.tvgError;
    };
    defer parser.deinit();

    return height * @as(f32, @floatFromInt(parser.header.width)) / @as(f32, @floatFromInt(parser.header.height));
}

pub fn iconTexture(name: []const u8, tvg_bytes: []const u8, height: u32) !TextureCacheEntry {
    var cw = currentWindow();
    const icon_hash = TextureCacheEntry.hash(tvg_bytes, height);

    if (cw.texture_cache.getPtr(icon_hash)) |tce| {
        tce.used = true;
        return tce.*;
    }

    var render = tvg.rendering.renderBuffer(
        cw.arena(),
        cw.arena(),
        tvg.rendering.SizeHint{ .height = height },
        @as(tvg.rendering.AntiAliasing, @enumFromInt(2)),
        tvg_bytes,
    ) catch |err| {
        log.warn("iconTexture Tinyvg error {!} rendering icon {s} at height {d}\n", .{ err, name, height });
        return error.tvgError;
    };
    defer render.deinit(cw.arena());

    var pixels: []u8 = undefined;
    pixels.ptr = @ptrCast(render.pixels.ptr);
    pixels.len = render.width * render.height * 4;
    Color.alphaMultiplyPixels(pixels);

    const texture = textureCreate(pixels.ptr, render.width, render.height, .linear);

    //std.debug.print("created icon texture \"{s}\" ask height {d} size {d}x{d}\n", .{ name, height, render.width, render.height });

    const entry = TextureCacheEntry{ .texture = texture, .size = .{ .w = @as(f32, @floatFromInt(render.width)), .h = @as(f32, @floatFromInt(render.height)) } };
    try cw.texture_cache.put(icon_hash, entry);

    return entry;
}

pub const RenderCommand = struct {
    clip: Rect,
    snap: bool,
    cmd: union(enum) {
        text: renderTextOptions,
        debug_font_atlases: struct {
            rs: RectScale,
            color: Color,
        },
        texture: struct {
            tex: *anyopaque,
            rs: RectScale,
            opts: RenderTextureOptions,
        },
        pathFillConvex: struct {
            path: std.ArrayList(Point),
            color: Color,
        },
        pathStroke: struct {
            path: std.ArrayList(Point),
            closed: bool,
            thickness: f32,
            endcap_style: EndCapStyle,
            color: Color,
        },
    },
};

/// Id of the currently focused subwindow.  Used by FloatingMenuWidget to
/// detect when to stop showing.
///
/// Only valid between dvui.Window.begin() and end().
pub fn focusedSubwindowId() u32 {
    const cw = currentWindow();
    const sw = cw.subwindowFocused();
    return sw.id;
}

/// Focus a subwindow.
///
/// If you are doing this in response to an event, you can pass that event's
/// "num" to change the focus of any further events in the list.
///
/// Only valid between dvui.Window.begin() and end().
pub fn focusSubwindow(subwindow_id: ?u32, event_num: ?u16) void {
    currentWindow().focusSubwindowInternal(subwindow_id, event_num);
}

pub fn focusRemainingEvents(event_num: u16, focusWindowId: u32, focusWidgetId: ?u32) void {
    currentWindow().focusRemainingEventsInternal(event_num, focusWindowId, focusWidgetId);
}

/// Raise a subwindow to the top of the stack.
///
/// Any subwindows directly above it with "stay_above_parent_window" set will also be moved to stay above it.
///
/// Only valid between dvui.Window.begin() and end().
pub fn raiseSubwindow(subwindow_id: u32) void {
    const cw = currentWindow();
    // don't check against subwindows[0] - that's that main window
    var items = cw.subwindows.items[1..];
    for (items, 0..) |sw, i| {
        if (sw.id == subwindow_id) {
            if (sw.stay_above_parent_window != null) {
                //std.debug.print("raiseSubwindow: tried to raise a subwindow {x} with stay_above_parent_window set\n", .{subwindow_id});
                return;
            }

            if (i == (items.len - 1)) {
                // already on top
                return;
            }

            // move it to the end, also move any stay_above_parent_window subwindows
            // directly on top of it as well - we know from above that the
            // first window does not have stay_above_parent_window so this loop ends
            var first = true;
            while (first or items[i].stay_above_parent_window != null) {
                first = false;
                const item = items[i];
                for (items[i..(items.len - 1)], 0..) |*b, k| {
                    b.* = items[i + 1 + k];
                }
                items[items.len - 1] = item;
            }

            return;
        }
    }

    log.warn("raiseSubwindow couldn't find subwindow {x}\n", .{subwindow_id});
    return;
}

/// Focus a widget in the given subwindow (if null, the current subwindow).
///
/// If you are doing this in response to an event, you can pass that event's
/// "num" to change the focus of any further events in the list.
///
/// Only valid between dvui.Window.begin() and end().
pub fn focusWidget(id: ?u32, subwindow_id: ?u32, event_num: ?u16) void {
    const cw = currentWindow();
    const swid = subwindow_id orelse subwindowCurrentId();
    for (cw.subwindows.items) |*sw| {
        if (swid == sw.id) {
            if (sw.focused_widgetId != id) {
                sw.focused_widgetId = id;
                if (event_num) |en| {
                    focusRemainingEvents(en, sw.id, sw.focused_widgetId);
                }
                refresh(null, @src(), null);
            }
            break;
        }
    }
}

/// Id of the focused widget (if any) in the focused subwindow.
///
/// Only valid between dvui.Window.begin() and end().
pub fn focusedWidgetId() ?u32 {
    const cw = currentWindow();
    for (cw.subwindows.items) |*sw| {
        if (cw.focused_subwindowId == sw.id) {
            return sw.focused_widgetId;
        }
    }

    return null;
}

/// Id of the focused widget (if any) in the current subwindow.
///
/// Only valid between dvui.Window.begin() and end().
pub fn focusedWidgetIdInCurrentSubwindow() ?u32 {
    const cw = currentWindow();
    const sw = cw.subwindowCurrent();
    return sw.focused_widgetId;
}

/// Set cursor the app should use.
///
/// Only valid between dvui.Window.begin() and end().
pub fn cursorSet(cursor: enums.Cursor) void {
    const cw = currentWindow();
    cw.cursor_requested = cursor;
}

/// Add point to the current path.
///
/// Only valid between dvui.Window.begin() and end().
pub fn pathAddPoint(p: Point) !void {
    const cw = currentWindow();
    try cw.path.append(p);
}

/// Add rounded rect to current path.  Starts from top left, and ends at top
/// right unclosed.
///
/// radius values:
/// - x is top-left corner
/// - y is top-right corner
/// - w is bottom-right corner
/// - h is bottom-left corner
///
/// Only valid between dvui.Window.begin() and end().
pub fn pathAddRect(r: Rect, radius: Rect) !void {
    var rad = radius;
    const maxrad = @min(r.w, r.h) / 2;
    rad.x = @min(rad.x, maxrad);
    rad.y = @min(rad.y, maxrad);
    rad.w = @min(rad.w, maxrad);
    rad.h = @min(rad.h, maxrad);
    const tl = Point{ .x = r.x + rad.x, .y = r.y + rad.x };
    const bl = Point{ .x = r.x + rad.h, .y = r.y + r.h - rad.h };
    const br = Point{ .x = r.x + r.w - rad.w, .y = r.y + r.h - rad.w };
    const tr = Point{ .x = r.x + r.w - rad.y, .y = r.y + rad.y };
    try pathAddArc(tl, rad.x, math.pi * 1.5, math.pi, @abs(tl.y - bl.y) < 0.5);
    try pathAddArc(bl, rad.h, math.pi, math.pi * 0.5, @abs(bl.x - br.x) < 0.5);
    try pathAddArc(br, rad.w, math.pi * 0.5, 0, @abs(br.y - tr.y) < 0.5);
    try pathAddArc(tr, rad.y, math.pi * 2.0, math.pi * 1.5, @abs(tr.x - tl.x) < 0.5);
}

/// Add line segments creating an arc to the current path.
///
/// start >= end, both are radians that go clockwise from the positive x axis.
///
/// If skip_end, the final point will not be added.  Useful if the next
/// addition to the path would duplicate the end of the arc.
///
/// Only valid between dvui.Window.begin() and end().
pub fn pathAddArc(center: Point, radius: f32, start: f32, end: f32, skip_end: bool) !void {
    if (radius == 0) {
        try pathAddPoint(center);
        return;
    }

    // how close our points will be to the perfect circle
    const err = 0.1;

    // angle that has err error between circle and segments
    const theta = math.acos(radius / (radius + err));

    // make sure we never have less than 4 segments
    // so a full circle can't be less than a diamond
    const num_segments = @max(@ceil((start - end) / theta), 4.0);

    const step = (start - end) / num_segments;

    const num = @as(u32, @intFromFloat(num_segments));
    var a: f32 = start;
    var i: u32 = 0;
    while (i < num) : (i += 1) {
        try pathAddPoint(Point{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
        a -= step;
    }

    if (!skip_end) {
        a = end;
        try pathAddPoint(Point{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
    }
}

/// Fill the current path (must be convex) with col and free the path.
///
/// Only valid between dvui.Window.begin() and end().
pub fn pathFillConvex(color: Color) !void {
    const cw = currentWindow();

    if (cw.path.items.len < 3) {
        cw.path.clearAndFree();
        return;
    }

    if (dvui.clipGet().empty()) {
        cw.path.clearAndFree();
        return;
    }

    if (!cw.render_target.rendering) {
        var path_copy = std.ArrayList(Point).init(cw.arena());
        try path_copy.appendSlice(cw.path.items);
        const cmd = RenderCommand{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .pathFillConvex = .{ .path = path_copy, .color = color } } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);
        cw.path.clearAndFree();
        return;
    }

    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena(), cw.path.items.len * 2);
    defer vtx.deinit();
    const idx_count = (cw.path.items.len - 2) * 3 + cw.path.items.len * 6;
    var idx = try std.ArrayList(u16).initCapacity(cw.arena(), idx_count);
    defer idx.deinit();
    const col = color.alphaMultiply();
    const col_trans = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    var bounds = Rect{}; // w and h are maxx and maxy for now
    bounds.x = std.math.floatMax(f32);
    bounds.y = bounds.x;
    bounds.w = -bounds.x;
    bounds.h = -bounds.x;

    var i: usize = 0;
    while (i < cw.path.items.len) : (i += 1) {
        const ai = (i + cw.path.items.len - 1) % cw.path.items.len;
        const bi = i % cw.path.items.len;
        const ci = (i + 1) % cw.path.items.len;
        const aa = cw.path.items[ai].diff(cw.render_target.offset);
        const bb = cw.path.items[bi].diff(cw.render_target.offset);
        const cc = cw.path.items[ci].diff(cw.render_target.offset);

        const diffab = Point.diff(aa, bb).normalize();
        const diffbc = Point.diff(bb, cc).normalize();
        // average of normals on each side
        const halfnorm = (Point{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 }).normalize().scale(0.5);

        var v: Vertex = undefined;
        // inner vertex
        v.pos.x = bb.x - halfnorm.x;
        v.pos.y = bb.y - halfnorm.y;
        v.col = col;
        try vtx.append(v);
        bounds.x = @min(bounds.x, v.pos.x);
        bounds.y = @min(bounds.y, v.pos.y);
        bounds.w = @max(bounds.w, v.pos.x);
        bounds.h = @max(bounds.h, v.pos.y);

        // outer vertex
        v.pos.x = bb.x + halfnorm.x;
        v.pos.y = bb.y + halfnorm.y;
        v.col = col_trans;
        try vtx.append(v);
        bounds.x = @min(bounds.x, v.pos.x);
        bounds.y = @min(bounds.y, v.pos.y);
        bounds.w = @max(bounds.w, v.pos.x);
        bounds.h = @max(bounds.h, v.pos.y);

        // indexes for fill
        // triangles must be counter-clockwise (y going down) to avoid backface culling
        if (i > 1) {
            try idx.append(@as(u16, @intCast(0)));
            try idx.append(@as(u16, @intCast(ai * 2)));
            try idx.append(@as(u16, @intCast(bi * 2)));
        }

        // indexes for aa fade from inner to outer
        // triangles must be counter-clockwise (y going down) to avoid backface culling
        try idx.append(@as(u16, @intCast(ai * 2)));
        try idx.append(@as(u16, @intCast(ai * 2 + 1)));
        try idx.append(@as(u16, @intCast(bi * 2)));
        try idx.append(@as(u16, @intCast(ai * 2 + 1)));
        try idx.append(@as(u16, @intCast(bi * 2 + 1)));
        try idx.append(@as(u16, @intCast(bi * 2)));
    }

    // convert bounds back to normal rect
    bounds.w = bounds.w - bounds.x;
    bounds.h = bounds.h - bounds.y;

    const clip_offset = clipGet().offsetNegPoint(cw.render_target.offset);
    const clipr: ?Rect = if (bounds.clippedBy(clip_offset)) clip_offset else null;

    cw.backend.drawClippedTriangles(null, vtx.items, idx.items, clipr);

    cw.path.clearAndFree();
}

pub const EndCapStyle = enum {
    none,
    square,
};

/// Stroke the current path and free the path.
///
/// * if closed_in, stroke includes from path end to path start.
///
/// Only valid between dvui.Window.begin() and end().
///
/// If you want to stroke a path on top of normal drawing, see pathStrokeAfter().
pub fn pathStroke(closed_in: bool, thickness: f32, endcap_style: EndCapStyle, col: Color) !void {
    try pathStrokeAfter(false, closed_in, thickness, endcap_style, col);
}

/// Stroke the current path and free the path, but render it after normal
/// drawing on that subwindow (when after is true).  This is useful for
/// debugging or cross-gui drawing (like an arrow pointing to a widget).
///
/// Only valid between dvui.Window.begin() and end().
pub fn pathStrokeAfter(after: bool, closed_in: bool, thickness: f32, endcap_style: EndCapStyle, col: Color) !void {
    const cw = currentWindow();

    if (cw.path.items.len == 0) {
        return;
    }

    if (after or !cw.render_target.rendering) {
        var path_copy = std.ArrayList(Point).init(cw.arena());
        try path_copy.appendSlice(cw.path.items);
        const cmd = RenderCommand{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .pathStroke = .{ .path = path_copy, .closed = closed_in, .thickness = thickness, .endcap_style = endcap_style, .color = col } } };

        var sw = cw.subwindowCurrent();
        if (after) {
            try sw.render_cmds_after.append(cmd);
        } else {
            try sw.render_cmds.append(cmd);
        }

        cw.path.clearAndFree();
        return;
    }

    try pathStrokeRaw(closed_in, thickness, endcap_style, col);
}

pub fn pathStrokeRaw(closed_in: bool, thickness: f32, endcap_style: EndCapStyle, color: Color) !void {
    const cw = currentWindow();

    if (dvui.clipGet().empty()) {
        cw.path.clearAndFree();
        return;
    }

    if (cw.path.items.len == 1) {
        // draw a circle with radius thickness at that point
        const center = cw.path.items[0].diff(cw.render_target.offset);

        // remove old path so we don't have a center point
        cw.path.clearAndFree();

        try pathAddArc(center, thickness, math.pi * 2.0, 0, true);
        try pathFillConvex(color);
        cw.path.clearAndFree();
        return;
    }

    var closed: bool = closed_in;
    if (cw.path.items.len == 2) {
        // a single segment can't be closed
        closed = false;
    }

    var vtx_count = cw.path.items.len * 4;
    if (!closed) {
        vtx_count += 4;
    }
    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena(), vtx_count);
    defer vtx.deinit();
    var idx_count = (cw.path.items.len - 1) * 18;
    if (closed) {
        idx_count += 18;
    } else {
        idx_count += 8 * 3;
    }
    var idx = try std.ArrayList(u16).initCapacity(cw.arena(), idx_count);
    defer idx.deinit();
    const col = color.alphaMultiply();
    const col_trans = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    var bounds = Rect{}; // w and h are maxx and maxy for now
    bounds.x = std.math.floatMax(f32);
    bounds.y = bounds.x;
    bounds.w = -bounds.x;
    bounds.h = -bounds.x;

    const aa_size = 1.0;
    var vtx_start: usize = 0;
    var i: usize = 0;
    while (i < cw.path.items.len) : (i += 1) {
        const ai = (i + cw.path.items.len - 1) % cw.path.items.len;
        const bi = i % cw.path.items.len;
        const ci = (i + 1) % cw.path.items.len;
        const aa = cw.path.items[ai].diff(cw.render_target.offset);
        var bb = cw.path.items[bi].diff(cw.render_target.offset);
        const cc = cw.path.items[ci].diff(cw.render_target.offset);

        // the amount to move from bb to the edge of the line
        var halfnorm: Point = undefined;

        var v: Vertex = undefined;
        var diffab: Point = undefined;

        if (!closed and ((i == 0) or ((i + 1) == cw.path.items.len))) {
            if (i == 0) {
                const diffbc = Point.diff(bb, cc).normalize();
                // rotate by 90 to get normal
                halfnorm = Point{ .x = diffbc.y / 2, .y = (-diffbc.x) / 2 };

                if (endcap_style == .square) {
                    // square endcaps move bb out by thickness
                    bb.x += diffbc.x * thickness;
                    bb.y += diffbc.y * thickness;
                }

                // add 2 extra vertexes for endcap fringe
                vtx_start += 2;

                v.pos.x = bb.x - halfnorm.x * (thickness + aa_size) + diffbc.x * aa_size;
                v.pos.y = bb.y - halfnorm.y * (thickness + aa_size) + diffbc.y * aa_size;
                v.col = col_trans;
                try vtx.append(v);
                bounds.x = @min(bounds.x, v.pos.x);
                bounds.y = @min(bounds.y, v.pos.y);
                bounds.w = @max(bounds.w, v.pos.x);
                bounds.h = @max(bounds.h, v.pos.y);

                v.pos.x = bb.x + halfnorm.x * (thickness + aa_size) + diffbc.x * aa_size;
                v.pos.y = bb.y + halfnorm.y * (thickness + aa_size) + diffbc.y * aa_size;
                v.col = col_trans;
                try vtx.append(v);
                bounds.x = @min(bounds.x, v.pos.x);
                bounds.y = @min(bounds.y, v.pos.y);
                bounds.w = @max(bounds.w, v.pos.x);
                bounds.h = @max(bounds.h, v.pos.y);

                // add indexes for endcap fringe
                try idx.append(@as(u16, @intCast(0)));
                try idx.append(@as(u16, @intCast(vtx_start)));
                try idx.append(@as(u16, @intCast(vtx_start + 1)));

                try idx.append(@as(u16, @intCast(0)));
                try idx.append(@as(u16, @intCast(1)));
                try idx.append(@as(u16, @intCast(vtx_start)));

                try idx.append(@as(u16, @intCast(1)));
                try idx.append(@as(u16, @intCast(vtx_start + 2)));
                try idx.append(@as(u16, @intCast(vtx_start)));

                try idx.append(@as(u16, @intCast(1)));
                try idx.append(@as(u16, @intCast(vtx_start + 2 + 1)));
                try idx.append(@as(u16, @intCast(vtx_start + 2)));
            } else if ((i + 1) == cw.path.items.len) {
                diffab = Point.diff(aa, bb).normalize();
                // rotate by 90 to get normal
                halfnorm = Point{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                if (endcap_style == .square) {
                    // square endcaps move bb out by thickness
                    bb.x -= diffab.x * thickness;
                    bb.y -= diffab.y * thickness;
                }
            }
        } else {
            diffab = Point.diff(aa, bb).normalize();
            const diffbc = Point.diff(bb, cc).normalize();
            // average of normals on each side
            halfnorm = Point{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

            // scale averaged normal by angle between which happens to be the same as
            // dividing by the length^2
            const d2 = halfnorm.x * halfnorm.x + halfnorm.y * halfnorm.y;
            if (d2 > 0.000001) {
                halfnorm = halfnorm.scale(0.5 / d2);
            }

            // limit distance our vertexes can be from the point to 2 * thickness so
            // very small angles don't produce huge geometries
            const l = halfnorm.length();
            if (l > 2.0) {
                halfnorm = halfnorm.scale(2.0 / l);
            }
        }

        // side 1 inner vertex
        v.pos.x = bb.x - halfnorm.x * thickness;
        v.pos.y = bb.y - halfnorm.y * thickness;
        v.col = col;
        try vtx.append(v);
        bounds.x = @min(bounds.x, v.pos.x);
        bounds.y = @min(bounds.y, v.pos.y);
        bounds.w = @max(bounds.w, v.pos.x);
        bounds.h = @max(bounds.h, v.pos.y);

        // side 1 AA vertex
        v.pos.x = bb.x - halfnorm.x * (thickness + aa_size);
        v.pos.y = bb.y - halfnorm.y * (thickness + aa_size);
        v.col = col_trans;
        try vtx.append(v);
        bounds.x = @min(bounds.x, v.pos.x);
        bounds.y = @min(bounds.y, v.pos.y);
        bounds.w = @max(bounds.w, v.pos.x);
        bounds.h = @max(bounds.h, v.pos.y);

        // side 2 inner vertex
        v.pos.x = bb.x + halfnorm.x * thickness;
        v.pos.y = bb.y + halfnorm.y * thickness;
        v.col = col;
        try vtx.append(v);
        bounds.x = @min(bounds.x, v.pos.x);
        bounds.y = @min(bounds.y, v.pos.y);
        bounds.w = @max(bounds.w, v.pos.x);
        bounds.h = @max(bounds.h, v.pos.y);

        // side 2 AA vertex
        v.pos.x = bb.x + halfnorm.x * (thickness + aa_size);
        v.pos.y = bb.y + halfnorm.y * (thickness + aa_size);
        v.col = col_trans;
        try vtx.append(v);
        bounds.x = @min(bounds.x, v.pos.x);
        bounds.y = @min(bounds.y, v.pos.y);
        bounds.w = @max(bounds.w, v.pos.x);
        bounds.h = @max(bounds.h, v.pos.y);

        // triangles must be counter-clockwise (y going down) to avoid backface culling
        if (closed or ((i + 1) != cw.path.items.len)) {
            // indexes for fill
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4)));

            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4 + 2)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4)));

            // indexes for aa fade from inner to outer side 1
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4 + 1)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 1)));

            try idx.append(@as(u16, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4 + 1)));

            // indexes for aa fade from inner to outer side 2
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 3)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4 + 3)));

            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4 + 3)));
            try idx.append(@as(u16, @intCast(vtx_start + ci * 4 + 2)));
        } else if (!closed and (i + 1) == cw.path.items.len) {
            // add 2 extra vertexes for endcap fringe
            v.pos.x = bb.x - halfnorm.x * (thickness + aa_size) - diffab.x * aa_size;
            v.pos.y = bb.y - halfnorm.y * (thickness + aa_size) - diffab.y * aa_size;
            v.col = col_trans;
            try vtx.append(v);
            bounds.x = @min(bounds.x, v.pos.x);
            bounds.y = @min(bounds.y, v.pos.y);
            bounds.w = @max(bounds.w, v.pos.x);
            bounds.h = @max(bounds.h, v.pos.y);

            v.pos.x = bb.x + halfnorm.x * (thickness + aa_size) - diffab.x * aa_size;
            v.pos.y = bb.y + halfnorm.y * (thickness + aa_size) - diffab.y * aa_size;
            v.col = col_trans;
            try vtx.append(v);
            bounds.x = @min(bounds.x, v.pos.x);
            bounds.y = @min(bounds.y, v.pos.y);
            bounds.w = @max(bounds.w, v.pos.x);
            bounds.h = @max(bounds.h, v.pos.y);

            // add indexes for endcap fringe
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 4)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 1)));

            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 4)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 2)));

            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 4)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 5)));

            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 3)));
            try idx.append(@as(u16, @intCast(vtx_start + bi * 4 + 5)));
        }
    }

    // convert bounds back to normal rect
    bounds.w = bounds.w - bounds.x;
    bounds.h = bounds.h - bounds.y;

    const clip_offset = clipGet().offsetNegPoint(cw.render_target.offset);
    const clipr: ?Rect = if (bounds.clippedBy(clip_offset)) clip_offset else null;

    cw.backend.drawClippedTriangles(null, vtx.items, idx.items, clipr);

    cw.path.clearAndFree();
}

pub fn subwindowAdd(id: u32, rect: Rect, rect_pixels: Rect, modal: bool, stay_above_parent_window: ?u32) !void {
    const cw = currentWindow();
    const arena = cw.arena();

    for (cw.subwindows.items) |*sw| {
        if (id == sw.id) {
            // this window was here previously, just update data, so it stays in the same place in the stack
            sw.used = true;
            sw.rect = rect;
            sw.rect_pixels = rect_pixels;
            sw.modal = modal;
            sw.stay_above_parent_window = stay_above_parent_window;

            if (sw.render_cmds.items.len > 0 or sw.render_cmds_after.items.len > 0) {
                log.warn("subwindowAdd {x} is clearing some drawing commands (did you try to draw between subwindowCurrentSet and subwindowAdd?)\n", .{id});
            }

            sw.render_cmds = std.ArrayList(RenderCommand).init(arena);
            sw.render_cmds_after = std.ArrayList(RenderCommand).init(arena);
            return;
        }
    }

    // haven't seen this window before
    const sw = Window.Subwindow{ .id = id, .rect = rect, .rect_pixels = rect_pixels, .modal = modal, .stay_above_parent_window = stay_above_parent_window, .render_cmds = std.ArrayList(RenderCommand).init(arena), .render_cmds_after = std.ArrayList(RenderCommand).init(arena) };
    if (stay_above_parent_window) |subwin_id| {
        // it wants to be above subwin_id
        var i: usize = 0;
        while (i < cw.subwindows.items.len and cw.subwindows.items[i].id != subwin_id) {
            i += 1;
        }

        if (i < cw.subwindows.items.len) {
            i += 1;
        }

        // i points just past subwin_id, go until we run out of subwindows that want to be on top of this subwin_id
        while (i < cw.subwindows.items.len and cw.subwindows.items[i].stay_above_parent_window == subwin_id) {
            i += 1;
        }

        // i points just past all subwindows that want to be on top of this subwin_id
        try cw.subwindows.insert(i, sw);
    } else {
        // just put it on the top
        try cw.subwindows.append(sw);
    }
}

pub const subwindowCurrentSetReturn = struct {
    id: u32,
    rect: Rect, // natural pixels
};

pub fn subwindowCurrentSet(id: u32, rect: ?Rect) subwindowCurrentSetReturn {
    const cw = currentWindow();
    const ret: subwindowCurrentSetReturn = .{ .id = cw.subwindow_currentId, .rect = cw.subwindow_currentRect };
    cw.subwindow_currentId = id;
    if (rect) |r| {
        cw.subwindow_currentRect = r;
    }
    return ret;
}

pub fn subwindowCurrentId() u32 {
    const cw = currentWindow();
    return cw.subwindow_currentId;
}

pub const DragStartOptions = struct {
    cursor: ?enums.Cursor = null,
    offset: Point = .{},
    name: []const u8 = "",
};

/// Prepare for a possible mouse drag.  This will detect a drag, and also a
/// normal click (mouse down and up without a drag).
///
/// * dragging() will return a Point once mouse motion has moved at least 3
/// natural pixels away from p.
///
/// * if cursor is non-null and a drag starts, use that cursor while dragging
///
/// * offset given here can be retrieved later with dragOffset() - example is
/// dragging bottom right corner of floating window.  The drag can start
/// anywhere in the hit area (passing the offset to the true corner), then
/// during the drag, the dragOffset() is added to the current mouse location to
/// recover where to move the true corner.
///
/// See dragStart() to immediately start a drag.
///
/// Only valid between dvui.Window.begin() and end().
pub fn dragPreStart(p: Point, options: DragStartOptions) void {
    const cw = currentWindow();
    cw.drag_state = .prestart;
    cw.drag_pt = p;
    cw.drag_offset = options.offset;
    cw.cursor_dragging = options.cursor;
    cw.drag_name = options.name;
}

/// Start a mouse drag from p.  Use when only dragging is possible (normal
/// click would do nothing), otherwise use dragPreStart().
///
/// * if cursor is non-null, use that cursor while dragging
///
/// * offset given here can be retrieved later with dragOffset() - example is
/// dragging bottom right corner of floating window.  The drag can start
/// anywhere in the hit area (passing the offset to the true corner), then
/// during the drag, the dragOffset() is added to the current mouse location to
/// recover where to move the true corner.
///
/// Only valid between dvui.Window.begin() and end().
pub fn dragStart(p: Point, options: DragStartOptions) void {
    const cw = currentWindow();
    cw.drag_state = .dragging;
    cw.drag_pt = p;
    cw.drag_offset = options.offset;
    cw.cursor_dragging = options.cursor;
    cw.drag_name = options.name;
}

/// Get offset previously given to dragPreStart() or dragStart().  See those.
///
/// Only valid between dvui.Window.begin() and end().
pub fn dragOffset() Point {
    const cw = currentWindow();
    return cw.drag_offset;
}

/// If a mouse drag is happening, return the pixel difference to p from the
/// previous dragging call or the drag starting location (from dragPreStart()
/// or dragStart()).  Otherwise return null, meaning a drag hasn't started yet.
///
/// Only valid between dvui.Window.begin() and end().
pub fn dragging(p: Point) ?Point {
    const cw = currentWindow();
    switch (cw.drag_state) {
        .none => return null,
        .dragging => {
            const dp = Point.diff(p, cw.drag_pt);
            cw.drag_pt = p;
            return dp;
        },
        .prestart => {
            const dp = Point.diff(p, cw.drag_pt);
            const dps = dp.scale(1 / windowNaturalScale());
            if (@abs(dps.x) > 3 or @abs(dps.y) > 3) {
                cw.drag_pt = p;
                cw.drag_state = .dragging;
                return dp;
            } else {
                return null;
            }
        },
    }
}

/// True if dragging and dragStart (or dragPreStart) was given name.
///
/// Useful for cross-widget drags.
///
/// Only valid between dvui.Window.begin() and end().
pub fn draggingName(name: []const u8) bool {
    const cw = currentWindow();
    return cw.drag_state == .dragging and cw.drag_name.len > 0 and std.mem.eql(u8, name, cw.drag_name);
}

/// Stop any mouse drag.
///
/// Only valid between dvui.Window.begin() and end().
pub fn dragEnd() void {
    const cw = currentWindow();
    cw.drag_state = .none;
}

/// The difference between the final mouse position this frame and last frame.
/// Use mouseTotalMotion().nonZero() to detect if any mouse motion has occured.
///
/// Only valid between dvui.Window.begin() and end().
pub fn mouseTotalMotion() Point {
    const cw = currentWindow();
    return Point.diff(cw.mouse_pt, cw.mouse_pt_prev);
}

/// Pass a widget ID for that widget to receive all mouse events (wheel events
/// still filtered normally).
///
/// To keep mouse capture, must call captureMouseMaintain() each frame, and can
/// call it every frame regardless of capture.
///
/// Only valid between dvui.Window.begin() and end().
pub fn captureMouse(id: ?u32) void {
    const cw = currentWindow();
    cw.captureID = id;
    if (id != null) {
        cw.captured_last_frame = true;
    }
}

/// If the widget ID passed has mouse capture, this maintains that capture for
/// the next frame.
///
/// This can be called every frame regardless of capture.
///
/// Only valid between dvui.Window.begin() and end().
pub fn captureMouseMaintain(id: u32) void {
    const cw = currentWindow();
    if (cw.captureID == id) {
        // to maintain capture, we must be on or above the
        // top modal window
        var i = cw.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &cw.subwindows.items[i - 1];
            if (sw.id == cw.subwindow_currentId) {
                // maintaining capture
                // either our floating window is above the top modal
                // or there are no floating modal windows
                cw.captured_last_frame = true;
                return;
            } else if (sw.modal) {
                // found modal before we found current
                // cancel the capture, and cancel
                // any drag being done
                captureMouse(null);
                dragEnd();
                return;
            }
        }
    }
}

/// Test if the passed widget ID currently has mouse capture.
///
/// Only valid between dvui.Window.begin() and end().
pub fn captured(id: u32) bool {
    return id == captureMouseId();
}

/// Get the widget ID that currently has mouse capture or null if none.
///
/// Only valid between dvui.Window.begin() and end().
pub fn captureMouseId() ?u32 {
    return currentWindow().captureID;
}

/// Get current screen rectangle in pixels that drawing is being clipped to.
///
/// Only valid between dvui.Window.begin() and end().
pub fn clipGet() Rect {
    return currentWindow().clipRect;
}

/// Intersect the given rect (in pixels) with the current clipping rect and set
/// as the new clipping rect.
///
/// Returns the previous clipping rect, use clipSet to restore it.
///
/// Only valid between dvui.Window.begin() and end().
pub fn clip(new: Rect) Rect {
    const cw = currentWindow();
    const ret = cw.clipRect;
    clipSet(cw.clipRect.intersect(new));
    return ret;
}

/// Set the current clipping rect to the given rect (in pixels).
///
/// Only valid between dvui.Window.begin() and end().
pub fn clipSet(r: Rect) void {
    currentWindow().clipRect = r;
}

/// Set snap_to_pixels setting.  If true:
/// * fonts are rendered at @floor(font.size)
/// * drawing is generally rounded to the nearest pixel
///
/// Returns the previous setting.
///
/// Only valid between dvui.Window.begin() and end().
pub fn snapToPixelsSet(snap: bool) bool {
    const cw = currentWindow();
    const old = cw.snap_to_pixels;
    cw.snap_to_pixels = snap;
    return old;
}

/// Get current snap_to_pixels setting.  See snapToPixelsSet().
///
/// Only valid between dvui.Window.begin() and end().
pub fn snapToPixels() bool {
    const cw = currentWindow();
    return cw.snap_to_pixels;
}

/// Requests another frame to be shown.
///
/// This only matters if you are using dvui to manage the framerate (by calling
/// Window.waitTime() and using the return value to wait with event
/// interruption - for example sdl_backend.waitEventTimeout at the end of each
/// frame).
///
/// src and id are for debugging, which is enabled by calling
/// Window.debugRefresh(true).  The debug window has a toggle button for this.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to refresh.  In that case dvui will
/// go through the backend because the gui thread might be waiting.
pub fn refresh(win: ?*Window, src: std.builtin.SourceLocation, id: ?u32) void {
    if (win) |w| {
        // we are being called from non gui thread, the gui thread might be
        // sleeping, so need to trigger a wakeup via the backend
        w.refreshBackend(src, id);
    } else {
        if (current_window) |cw| {
            cw.refreshWindow(src, id);
        } else {
            log.err("{s}:{d} refresh current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()", .{ src.file, src.line });
        }
    }
}

/// Get the textual content of the system clipboard.  Caller must copy.
///
/// Only valid between dvui.Window.begin() and end().
pub fn clipboardText() error{OutOfMemory}![]const u8 {
    const cw = currentWindow();
    return cw.backend.clipboardText();
}

/// Set the textual content of the system clipboard.
///
/// Only valid between dvui.Window.begin() and end().
pub fn clipboardTextSet(text: []const u8) error{OutOfMemory}!void {
    const cw = currentWindow();
    try cw.backend.clipboardTextSet(text);
}

/// Ask the system to open the given url.
///
/// Only valid between dvui.Window.begin() and end().
pub fn openURL(url: []const u8) !void {
    const cw = currentWindow();
    try cw.backend.openURL(url);
}

/// Seconds elapsed between last frame and current.  This value can be quite
/// high after a period with no user interaction.
///
/// Only valid between dvui.Window.begin() and end().
pub fn secondsSinceLastFrame() f32 {
    return currentWindow().secs_since_last_frame;
}

/// Average frames per second over the past 30 frames.
///
/// Only valid between dvui.Window.begin() and end().
pub fn FPS() f32 {
    return currentWindow().FPS();
}

/// Get the Widget that would be the parent of a new widget.
///
/// dvui.parentGet().extendId(@src(), id_extra) is how new widgets get their
/// id, and can be used to make a unique id without making a widget.
///
/// Only valid between dvui.Window.begin() and end().
pub fn parentGet() Widget {
    return currentWindow().wd.parent;
}

/// Make w the new parent widget.  See parentGet().
///
/// Only valid between dvui.Window.begin() and end().
pub fn parentSet(w: Widget) void {
    const cw = currentWindow();
    cw.wd.parent = w;
}

/// Make a previous parent widget the current parent.
///
/// Pass the current parent's id.  This is used to detect a coding error where
/// a widget's deinit() was accidentally not called.
pub fn parentReset(id: u32, w: Widget) void {
    const cw = currentWindow();
    const actual_current = cw.wd.parent.data().id;
    if (id != actual_current) {
        cw.debug_widget_id = actual_current;

        var ww = cw.wd.parent;
        var wd = ww.data();
        var widget_name = wd.options.name orelse "???";

        log.err("widget is not closed within its parent. did you forget to call `.deinit()`?", .{});

        while (true) : (ww = ww.data().parent) {
            wd = ww.data();
            widget_name = wd.options.name orelse "???";
            log.err("  {s} id={x} was initialized at [{s}:{d}:{d}]", .{ widget_name, wd.id, wd.src.file, wd.src.line, wd.src.column });

            if (wd.id == cw.wd.id) {
                // got to base Window
                break;
            }
        }
    }
    cw.wd.parent = w;
}

pub fn renderingSet(r: bool) bool {
    const cw = currentWindow();
    const ret = cw.render_target.rendering;
    cw.render_target.rendering = r;
    return ret;
}

/// Get the OS window size in natural pixels.  Physical pixels might be more on
/// a hidpi screen or if the user has content scaling.  See windowRectPixels().
///
/// Natural pixels is the unit for subwindow sizing and placement.
///
/// Only valid between dvui.Window.begin() and end().
pub fn windowRect() Rect {
    return currentWindow().wd.rect;
}

/// Get the OS window size in pixels.  See windowRect().
///
/// Pixels is the unit for rendering and user input.
///
/// Only valid between dvui.Window.begin() and end().
pub fn windowRectPixels() Rect {
    return currentWindow().rect_pixels;
}

/// Get the Rect and scale factor for the OS window.  The Rect is in pixels,
/// and the scale factor is how many pixels per natural pixel.  See
/// windowRect().
///
/// Only valid between dvui.Window.begin() and end().
pub fn windowRectScale() RectScale {
    return .{ .r = currentWindow().rect_pixels, .s = currentWindow().natural_scale };
}

/// The natural scale is how many pixels per natural pixel.  Useful for
/// converting between user input and subwindow size/position.  See
/// windowRect().
///
/// Only valid between dvui.Window.begin() and end().
pub fn windowNaturalScale() f32 {
    return currentWindow().natural_scale;
}

/// True if this is the first frame we've seen this widget id, meaning we don't
/// know its min size yet.  The widget will record its min size in deinit().
///
/// If a widget is not seen for a frame, its min size will be forgotten and
/// firstFrame will return true the next frame we see it.
///
/// Only valid between dvui.Window.begin() and end().
pub fn firstFrame(id: u32) bool {
    return minSizeGet(id) == null;
}

/// Get the min size recorded for id from last frame or null if id was not seen
/// last frame.
///
/// Usually you want minSize() to combine min size from last frame with a min
/// size provided by the user code.
///
/// Only valid between dvui.Window.begin() and end().
pub fn minSizeGet(id: u32) ?Size {
    var cw = currentWindow();
    const saved_size = cw.min_sizes.getPtr(id);
    if (saved_size) |ss| {
        return ss.size;
    } else {
        return null;
    }
}

/// Return the maximum of min_size and the min size for id from last frame.
///
/// See minSizeGet() to get only the min size from last frame.
///
/// Only valid between dvui.Window.begin() and end().
pub fn minSize(id: u32, min_size: Size) Size {
    var size = min_size;

    // Need to take the max of both given and previous.  ScrollArea could be
    // passed a min size Size{.w = 0, .h = 200} meaning to get the width from the
    // previous min size.
    if (minSizeGet(id)) |ms| {
        size = Size.max(size, ms);
    }

    return size;
}

/// Make a unique id from src and id_extra, without a parent widget.  This is
/// how the initial parent widget id is created, and also toasts and dialogs
/// from other threads.
///
/// See Widget.extendId() which does similar but on top of a parent id.
///
/// dvui.parentGet().extendId(@src(), id_extra) is how new widgets get their
/// id, and can be used to make a unique id without making a widget.
pub fn hashSrc(src: std.builtin.SourceLocation, id_extra: usize) u32 {
    var hash = fnv.init();
    hash.update(src.file);
    hash.update(std.mem.asBytes(&src.line));
    hash.update(std.mem.asBytes(&src.column));
    hash.update(std.mem.asBytes(&id_extra));
    return hash.final();
}

/// Make a new id by combining id with the contents of key.  This is how dvui
/// tracks things in dataGet/Set, animation, and timer.
pub fn hashIdKey(id: u32, key: []const u8) u32 {
    var h = fnv.init();
    h.value = id;
    h.update(key);
    return h.final();
}

/// Set key/value pair for given id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// If you want to store the contents of a slice, use dataSetSlice().
pub fn dataSet(win: ?*Window, id: u32, key: []const u8, data: anytype) void {
    dataSetAdvanced(win, id, key, data, false, 1);
}

/// Set key/value pair for given id, copying the slice contents. Can be passed
/// a slice or pointer to an array.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
pub fn dataSetSlice(win: ?*Window, id: u32, key: []const u8, data: anytype) void {
    dataSetSliceCopies(win, id, key, data, 1);
}

/// Same as dataSetSlice, but will copy data num_copies times all concatenated
/// into a single slice.  Useful to get dvui to allocate a specific number of
/// entries that you want to fill in after.
pub fn dataSetSliceCopies(win: ?*Window, id: u32, key: []const u8, data: anytype, num_copies: usize) void {
    const dt = @typeInfo(@TypeOf(data));
    if (dt == .pointer and dt.pointer.size == .slice) {
        if (dt.pointer.sentinel()) |s| {
            dataSetAdvanced(win, id, key, @as([:s]dt.pointer.child, @constCast(data)), true, num_copies);
        } else {
            dataSetAdvanced(win, id, key, @as([]dt.pointer.child, @constCast(data)), true, num_copies);
        }
    } else if (dt == .pointer and dt.pointer.size == .one and @typeInfo(dt.pointer.child) == .array) {
        const child_type = @typeInfo(dt.pointer.child);
        if (child_type.array.sentinel()) |s| {
            dataSetAdvanced(win, id, key, @as([:s]child_type.array.child, @constCast(data)), true, num_copies);
        } else {
            dataSetAdvanced(win, id, key, @as([]child_type.array.child, @constCast(data)), true, num_copies);
        }
    } else {
        @compileError("dataSetSlice needs a slice or pointer to array, given " ++ @typeName(@TypeOf(data)));
    }
}

/// Set key/value pair for given id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// If copy_slice is true, data must be a slice or pointer to array, and the
/// contents are copied into internal storage. If false, only the slice itself
/// (ptr and len) and stored.
pub fn dataSetAdvanced(win: ?*Window, id: u32, key: []const u8, data: anytype, comptime copy_slice: bool, num_copies: usize) void {
    if (win) |w| {
        // we are being called from non gui thread or outside begin()/end()
        w.dataSetAdvanced(id, key, data, copy_slice, num_copies);
    } else {
        if (current_window) |cw| {
            cw.dataSetAdvanced(id, key, data, copy_slice, num_copies);
        } else {
            @panic("dataSet current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
        }
    }
}

/// Retrieve the value for given key associated with id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// If you want a pointer to the stored data, use dataGetPtr().
///
/// If you want to get the contents of a stored slice, use dataGetSlice().
pub fn dataGet(win: ?*Window, id: u32, key: []const u8, comptime T: type) ?T {
    if (dataGetInternal(win, id, key, T, false)) |bytes| {
        return @as(*T, @alignCast(@ptrCast(bytes.ptr))).*;
    } else {
        return null;
    }
}

/// Retrieve the value for given key associated with id.  If no value was stored, store default and then return it.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// If you want a pointer to the stored data, use dataGetPtrDefault().
///
/// If you want to get the contents of a stored slice, use dataGetSlice().
pub fn dataGetDefault(win: ?*Window, id: u32, key: []const u8, comptime T: type, default: T) T {
    if (dataGetInternal(win, id, key, T, false)) |bytes| {
        return @as(*T, @alignCast(@ptrCast(bytes.ptr))).*;
    } else {
        dataSet(win, id, key, default);
        return default;
    }
}

/// Retrieve a pointer to the value for given key associated with id.  If no
/// value was stored, store default and then return a pointer to the stored
/// value.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// Returns a pointer to internal storage, which will be freed after a frame
/// where there is no call to any dataGet/dataSet functions for that id/key
/// combination.
///
/// If you want to get the contents of a stored slice, use dataGetSlice().
pub fn dataGetPtrDefault(win: ?*Window, id: u32, key: []const u8, comptime T: type, default: T) *T {
    if (dataGetPtr(win, id, key, T)) |ptr| {
        return ptr;
    } else {
        dataSet(win, id, key, default);
        return dataGetPtr(win, id, key, T).?;
    }
}

/// Retrieve a pointer to the value for given key associated with id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// Returns a pointer to internal storage, which will be freed after a frame
/// where there is no call to any dataGet/dataSet functions for that id/key
/// combination.
///
/// If you want to get the contents of a stored slice, use dataGetSlice().
pub fn dataGetPtr(win: ?*Window, id: u32, key: []const u8, comptime T: type) ?*T {
    if (dataGetInternal(win, id, key, T, false)) |bytes| {
        return @as(*T, @alignCast(@ptrCast(bytes.ptr)));
    } else {
        return null;
    }
}

/// Retrieve slice contents for given key associated with id.
///
/// dataSetSlice() strips const from the slice type, so always call
/// dataGetSlice() with a mutable slice type ([]u8, not []const u8).
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// The returned slice points to internal storage, which will be freed after
/// a frame where there is no call to any dataGet/dataSet functions for that
/// id/key combination.
pub fn dataGetSlice(win: ?*Window, id: u32, key: []const u8, comptime T: type) ?T {
    const dt = @typeInfo(T);
    if (dt != .pointer or dt.pointer.size != .slice) {
        @compileError("dataGetSlice needs a slice, given " ++ @typeName(T));
    }

    if (dataGetInternal(win, id, key, T, true)) |bytes| {
        if (dt.pointer.sentinel()) |sentinel| {
            return @as([:sentinel]align(@alignOf(dt.pointer.child)) dt.pointer.child, @alignCast(@ptrCast(std.mem.bytesAsSlice(dt.pointer.child, bytes[0 .. bytes.len - @sizeOf(dt.pointer.child)]))));
        } else {
            return @as([]align(@alignOf(dt.pointer.child)) dt.pointer.child, @alignCast(std.mem.bytesAsSlice(dt.pointer.child, bytes)));
        }
    } else {
        return null;
    }
}

/// Retrieve slice contents for given key associated with id.
///
/// If the id/key doesn't exist yet, store the default slice into internal
/// storage, and then return the internal storage slice.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// The returned slice points to internal storage, which will be freed after
/// a frame where there is no call to any dataGet/dataSet functions for that
/// id/key combination.
pub fn dataGetSliceDefault(win: ?*Window, id: u32, key: []const u8, comptime T: type, default: []const @typeInfo(T).pointer.child) T {
    return dataGetSlice(win, id, key, T) orelse blk: {
        dataSetSlice(win, id, key, default);
        break :blk dataGetSlice(win, id, key, T).?;
    };
}

// returns the backing slice of bytes if we have it
pub fn dataGetInternal(win: ?*Window, id: u32, key: []const u8, comptime T: type, slice: bool) ?[]u8 {
    if (win) |w| {
        // we are being called from non gui thread or outside begin()/end()
        return w.dataGetInternal(id, key, T, slice);
    } else {
        if (current_window) |cw| {
            return cw.dataGetInternal(id, key, T, slice);
        } else {
            @panic("dataGet current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
        }
    }
}

/// Remove key (and associated value if any) for given id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the dialog to.
pub fn dataRemove(win: ?*Window, id: u32, key: []const u8) void {
    if (win) |w| {
        // we are being called from non gui thread or outside begin()/end()
        return w.dataRemove(id, key);
    } else {
        if (current_window) |cw| {
            return cw.dataRemove(id, key);
        } else {
            @panic("dataRemove current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
        }
    }
}

/// Make the Rect a widget will get given the available space, the min size
/// wanted, expand, and gravity.
pub fn placeIn(avail: Rect, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    var size = min_size;

    // you never get larger than available
    size.w = @min(size.w, avail.w);
    size.h = @min(size.h, avail.h);

    switch (e) {
        .none => {},
        .horizontal => {
            size.w = avail.w;
        },
        .vertical => {
            size.h = avail.h;
        },
        .both => {
            size = avail.size();
        },
        .ratio => {
            if (min_size.w != 0 and min_size.h != 0) {
                const ratio = min_size.w / min_size.h;
                const aratio = (avail.w - size.w) / (avail.h - size.h);
                if (aratio > ratio) {
                    // height is constraint
                    size.w = avail.h * ratio;
                    size.h = avail.h;
                } else {
                    // width is constraint
                    size.w = avail.w;
                    size.h = avail.w / ratio;
                }
            }
        },
    }

    var r = avail.shrinkToSize(size);
    r.x = avail.x + g.x * (avail.w - r.w);
    r.y = avail.y + g.y * (avail.h - r.h);

    return r;
}

/// Get the slice of Events for this frame.
///
/// Only valid between dvui.Window.begin() and end().
pub fn events() []Event {
    return currentWindow().events.items;
}

/// Wrapper around eventMatch for normal usage.
///
/// Only valid between dvui.Window.begin() and end().
pub fn eventMatchSimple(e: *Event, wd: *WidgetData) bool {
    return eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r });
}

pub const EventMatchOptions = struct {
    id: u32,
    r: Rect,
    cleanup: bool = false,
};

/// Should e be processed by a widget with the given id and screen rect?
///
/// This is the core event matching logic and includes keyboard focus and mouse
/// capture.  Call this on each event in events() to know whether to process.
///
/// If asking whether an existing widget would process an event (if you are
/// wrapping a widget), that widget should have a matchEvent() which calls this
/// internally but might extend the logic, or use that function to track state
/// (like whether a modifier key is being pressed).
///
/// Only valid between dvui.Window.begin() and end().
pub fn eventMatch(e: *Event, opts: EventMatchOptions) bool {
    if (e.handled) return false;

    if (e.focus_windowId) |wid| {
        // focusable event
        if (opts.cleanup) {
            // window is catching all focus-routed events that didn't get
            // processed (maybe the focus widget never showed up)
            if (wid != opts.id) {
                // not the focused window
                return false;
            }
        } else {
            if (e.focus_widgetId != opts.id) {
                // not the focused widget
                return false;
            }
        }
    }

    switch (e.evt) {
        .key => {},
        .text => {},
        .mouse => |me| {
            const capture_id = captureMouseId();
            if (capture_id != null and me.action != .wheel_y) {
                if (capture_id.? != opts.id) {
                    // mouse is captured by a different widget
                    return false;
                }
            } else {
                if (me.floating_win != subwindowCurrentId()) {
                    // floating window is above us
                    return false;
                }

                if (!opts.r.contains(me.p)) {
                    // mouse not in our rect
                    return false;
                }

                if (!clipGet().contains(me.p)) {
                    // mouse not in clip region

                    // prevents widgets that are scrolled off a
                    // scroll area from processing events
                    return false;
                }
            }
        },

        .close_popup => unreachable,
        .scroll_drag => unreachable,
        .scroll_to => unreachable,
        .scroll_propogate => unreachable,
    }

    return true;
}

/// Animation state - see animation() and animationGet().
///
/// start_time and end_time are relative to the current frame time.  At the
/// start of each frame both are reduced by the micros since the last frame.
///
/// An animation will be active thru a frame where its end_time is <= 0, and be
/// deleted at the beginning of the next frame.  See Spinner for an example of
/// how to have a seemless continuous animation.
pub const Animation = struct {
    used: bool = true,
    start_val: f32 = 0,
    end_val: f32 = 1,
    start_time: i32 = 0,
    end_time: i32,

    pub fn lerp(a: *const Animation) f32 {
        var frac = @as(f32, @floatFromInt(-a.start_time)) / @as(f32, @floatFromInt(a.end_time - a.start_time));
        frac = @max(0, @min(1, frac));
        return (a.start_val * (1.0 - frac)) + (a.end_val * frac);
    }

    // return true on the last frame for this animation
    pub fn done(a: *const Animation) bool {
        if (a.end_time <= 0) {
            return true;
        }

        return false;
    }
};

/// Add animation a to key associated with id.  See Animation.
///
/// Only valid between dvui.Window.begin() and end().
pub fn animation(id: u32, key: []const u8, a: Animation) void {
    var cw = currentWindow();
    const h = hashIdKey(id, key);
    cw.animations.put(h, a) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("animation got {!} for id {x} key {s}\n", .{ err, id, key });
        },
    };
}

/// Retrieve an animation previously added with animation().  See Animation.
///
/// Only valid between dvui.Window.begin() and end().
pub fn animationGet(id: u32, key: []const u8) ?Animation {
    var cw = currentWindow();
    const h = hashIdKey(id, key);
    const val = cw.animations.getPtr(h);
    if (val) |v| {
        v.used = true;
        return v.*;
    }

    return null;
}

/// Add a timer for id that will be timerDone() on the first frame after micros
/// has passed.
///
/// Only valid between dvui.Window.begin() and end().
pub fn timer(id: u32, micros: i32) !void {
    try currentWindow().timer(id, micros);
}

/// Return the number of micros left on the timer for id if there is one.  If
/// timerDone(), this value will be <= 0 and represents how many micros this
/// frame is past the timer expiration.
///
/// Only valid between dvui.Window.begin() and end().
pub fn timerGet(id: u32) ?i32 {
    if (animationGet(id, "_timer")) |a| {
        return a.end_time;
    } else {
        return null;
    }
}

/// Return true on the first frame after a timer has expired.
///
/// Only valid between dvui.Window.begin() and end().
pub fn timerDone(id: u32) bool {
    if (timerGet(id)) |end_time| {
        if (end_time <= 0) {
            return true;
        }
    }

    return false;
}

/// Return true if timerDone() or if there is no timer.  Useful for periodic
/// events (see Clock example).
///
/// Only valid between dvui.Window.begin() and end().
pub fn timerDoneOrNone(id: u32) bool {
    return timerDone(id) or (timerGet(id) == null);
}

const TabIndex = struct {
    windowId: u32,
    widgetId: u32,
    tabIndex: u16,
};

/// Set the tab order for this widget.  Tab_index values are visited starting
/// with 1 and going up.
///
/// A zero tab_index means this function does nothing and the widget is not
/// added to the tab order.
///
/// A null tab_index means it will be visited after all normal values.  All
/// null widgets are visited in order of calling tabIndexSet.
///
/// Only valid between dvui.Window.begin() and end().
pub fn tabIndexSet(widget_id: u32, tab_index: ?u16) !void {
    if (tab_index != null and tab_index.? == 0)
        return;

    var cw = currentWindow();
    const ti = TabIndex{ .windowId = cw.subwindow_currentId, .widgetId = widget_id, .tabIndex = (tab_index orelse math.maxInt(u16)) };
    try cw.tab_index.append(ti);
}

/// Move focus to the next widget in tab index order.  Uses the tab index values from last frame.
///
/// If you are calling this due to processing an event, you can pass Event.num
/// and any further events will have their focus adjusted.
///
/// Only valid between dvui.Window.begin() and end().
pub fn tabIndexNext(event_num: ?u16) void {
    const cw = currentWindow();
    const widgetId = focusedWidgetId();
    var oldtab: ?u16 = null;
    if (widgetId != null) {
        for (cw.tab_index_prev.items) |ti| {
            if (ti.windowId == cw.focused_subwindowId and ti.widgetId == widgetId.?) {
                oldtab = ti.tabIndex;
                break;
            }
        }
    }

    // find the first widget with a tabindex greater than oldtab
    // or the first widget with lowest tabindex if oldtab is null
    var newtab: u16 = math.maxInt(u16);
    var newId: ?u32 = null;
    var foundFocus = false;

    for (cw.tab_index_prev.items) |ti| {
        if (ti.windowId == cw.focused_subwindowId) {
            if (ti.widgetId == widgetId) {
                foundFocus = true;
            } else if (foundFocus == true and oldtab != null and ti.tabIndex == oldtab.?) {
                // found the first widget after current that has the same tabindex
                newtab = ti.tabIndex;
                newId = ti.widgetId;
                break;
            } else if (oldtab == null or ti.tabIndex > oldtab.?) {
                if (newId == null or ti.tabIndex < newtab) {
                    newtab = ti.tabIndex;
                    newId = ti.widgetId;
                }
            }
        }
    }

    focusWidget(newId, null, event_num);
}

/// Move focus to the previous widget in tab index order.  Uses the tab index values from last frame.
///
/// If you are calling this due to processing an event, you can pass Event.num
/// and any further events will have their focus adjusted.
///
/// Only valid between dvui.Window.begin() and end().
pub fn tabIndexPrev(event_num: ?u16) void {
    const cw = currentWindow();
    const widgetId = focusedWidgetId();
    var oldtab: ?u16 = null;
    if (widgetId != null) {
        for (cw.tab_index_prev.items) |ti| {
            if (ti.windowId == cw.focused_subwindowId and ti.widgetId == widgetId.?) {
                oldtab = ti.tabIndex;
                break;
            }
        }
    }

    // find the last widget with a tabindex less than oldtab
    // or the last widget with highest tabindex if oldtab is null
    var newtab: u16 = 1;
    var newId: ?u32 = null;
    var foundFocus = false;

    for (cw.tab_index_prev.items) |ti| {
        if (ti.windowId == cw.focused_subwindowId) {
            if (ti.widgetId == widgetId) {
                foundFocus = true;

                if (oldtab != null and newtab == oldtab.?) {
                    // use last widget before that has the same tabindex
                    // might be none before so we'll go to null
                    break;
                }
            } else if (oldtab == null or ti.tabIndex < oldtab.? or (!foundFocus and ti.tabIndex == oldtab.?)) {
                if (ti.tabIndex >= newtab) {
                    newtab = ti.tabIndex;
                    newId = ti.widgetId;
                }
            }
        }
    }

    focusWidget(newId, null, event_num);
}

/// Wigets that accept text input should call this on frames they have focus.
///
/// r is in pixels.
///
/// It communicates:
/// * text input should happen (maybe shows an on screen keyboard)
/// * rect on screen (position possible IME window)
///
/// Only valid between dvui.Window.begin() and end().
pub fn wantTextInput(r: Rect) void {
    const cw = currentWindow();
    cw.text_input_rect = r.scale(1 / cw.natural_scale);
}

/// Maps to an OS window, and saves all the state needed between frames.
/// Usually this is created at app startup and deinit() called on app shutdown.
///
/// currentWindow() returns this when between begin()/end().
pub const Window = struct {
    const Self = @This();

    pub const Subwindow = struct {
        id: u32 = 0,
        rect: Rect = Rect{},
        rect_pixels: Rect = Rect{},
        focused_widgetId: ?u32 = null,
        render_cmds: std.ArrayList(RenderCommand),
        render_cmds_after: std.ArrayList(RenderCommand),
        used: bool = true,
        modal: bool = false,
        stay_above_parent_window: ?u32 = null,
    };

    const SavedSize = struct {
        size: Size,
        used: bool = true,
    };

    const SavedData = struct {
        used: bool = true,
        alignment: u8,
        data: []u8,

        type_str: if (builtin.mode == .Debug) []const u8 else void = undefined,
        copy_slice: if (builtin.mode == .Debug) bool else void = undefined,

        pub fn free(self: *const SavedData, allocator: std.mem.Allocator) void {
            if (self.data.len != 0) {
                allocator.rawFree(self.data, @ctz(self.alignment), @returnAddress());
            }
        }
    };

    backend: Backend,
    previous_window: ?*Window = null,

    // list of subwindows including base, later windows are on top of earlier
    // windows
    subwindows: std.ArrayList(Subwindow),

    // id of the subwindow widgets are being added to
    subwindow_currentId: u32 = 0,

    // pixel screen rect of the last subwindow to give us one, dialogs use this
    // to center themselves on
    // - FloatingWindowWidget does
    // - FloatingWidget and FloatingMenuWidget do not
    subwindow_currentRect: Rect = .{},

    // id of the subwindow that has focus
    focused_subwindowId: u32 = 0,

    // rect on screen (in natural pixels) telling the backend where our text input box is:
    // * when non-null, we want an on screen keyboard if needed (phones)
    // * when showing the IME input window, position it near this
    text_input_rect: ?Rect = null,

    snap_to_pixels: bool = true,
    alpha: f32 = 1.0,

    events: std.ArrayListUnmanaged(Event) = .{},
    event_num: u16 = 0,
    // mouse_pt tracks the last position we got a mouse event for
    // 1) used to add position info to mouse wheel events
    // 2) used to highlight the widget under the mouse (Event.Mouse.Action.position event)
    // 3) used to change the cursor (Event.Mouse.Action.position event)
    // Start off screen so nothing is highlighted on the first frame
    mouse_pt: Point = Point{ .x = -1, .y = -1 },
    mouse_pt_prev: Point = Point{ .x = -1, .y = -1 },
    inject_motion_event: bool = false,

    drag_state: enum {
        none,
        prestart,
        dragging,
    } = .none,
    drag_pt: Point = Point{},
    drag_offset: Point = Point{},
    drag_name: []const u8 = "",

    frame_time_ns: i128 = 0,
    loop_wait_target: ?i128 = null,
    loop_wait_target_event: bool = false,
    loop_target_slop: i32 = 1000, // 1ms frame overhead seems a good place to start
    loop_target_slop_frames: i32 = 0,
    frame_times: [30]u32 = [_]u32{0} ** 30,

    secs_since_last_frame: f32 = 0,
    extra_frames_needed: u8 = 0,
    clipRect: Rect = Rect{},

    theme: Theme = undefined,

    min_sizes: std.AutoHashMap(u32, SavedSize),
    data_mutex: std.Thread.Mutex,
    datas: std.AutoHashMap(u32, SavedData),
    animations: std.AutoHashMap(u32, Animation),
    tab_index_prev: std.ArrayList(TabIndex),
    tab_index: std.ArrayList(TabIndex),
    font_cache: std.AutoHashMap(u32, FontCacheEntry),
    font_bytes: std.StringHashMap(FontBytesEntry),
    texture_cache: std.AutoHashMap(u32, TextureCacheEntry),
    dialog_mutex: std.Thread.Mutex,
    dialogs: std.ArrayList(Dialog),
    toasts: std.ArrayList(Toast),
    keybinds: std.StringHashMap(enums.Keybind),
    themes: std.StringArrayHashMap(Theme),

    cursor_requested: enums.Cursor = .arrow,
    cursor_dragging: ?enums.Cursor = null,

    wd: WidgetData = undefined,
    rect_pixels: Rect = Rect{}, // pixels
    natural_scale: f32 = 1.0,
    content_scale: f32 = 1.0, // can set seperately but gets folded into natural_scale
    next_widget_ypos: f32 = 0,

    captureID: ?u32 = null,
    captured_last_frame: bool = false,

    gpa: std.mem.Allocator,
    _arena: std.heap.ArenaAllocator,
    texture_trash: std.ArrayList(*anyopaque) = undefined,
    path: std.ArrayList(Point) = undefined,
    render_target: RenderTarget = .{ .texture = null, .offset = .{} },

    debug_window_show: bool = false,
    debug_widget_id: u32 = 0, // 0 means no widget is selected
    debug_info_name_rect: []const u8 = "",
    debug_info_src_id_extra: []const u8 = "",
    debug_under_focus: bool = false,
    debug_under_mouse: bool = false,
    debug_under_mouse_esc_needed: bool = false,
    debug_under_mouse_quitting: bool = false,
    debug_under_mouse_info: []u8 = "",

    debug_refresh_mutex: std.Thread.Mutex,
    debug_refresh: bool = false,

    debug_touch_simulate_events: bool = false, // when true, left mouse button works like a finger
    debug_touch_simulate_down: bool = false,

    pub const InitOptions = struct {
        id_extra: usize = 0,
        arena: ?std.heap.ArenaAllocator = null,
        theme: ?*Theme = null,
        keybinds: ?enum {
            none,
            windows,
            mac,
        } = null,
    };

    pub fn init(
        src: std.builtin.SourceLocation,
        gpa: std.mem.Allocator,
        backend_ctx: Backend,
        init_opts: InitOptions,
    ) !Self {
        const hashval = hashSrc(src, init_opts.id_extra);

        var self = Self{
            .gpa = gpa,
            ._arena = init_opts.arena orelse std.heap.ArenaAllocator.init(gpa),
            .subwindows = std.ArrayList(Subwindow).init(gpa),
            .min_sizes = std.AutoHashMap(u32, SavedSize).init(gpa),
            .data_mutex = std.Thread.Mutex{},
            .datas = std.AutoHashMap(u32, SavedData).init(gpa),
            .animations = std.AutoHashMap(u32, Animation).init(gpa),
            .tab_index_prev = std.ArrayList(TabIndex).init(gpa),
            .tab_index = std.ArrayList(TabIndex).init(gpa),
            .font_cache = std.AutoHashMap(u32, FontCacheEntry).init(gpa),
            .texture_cache = std.AutoHashMap(u32, TextureCacheEntry).init(gpa),
            .dialog_mutex = std.Thread.Mutex{},
            .dialogs = std.ArrayList(Dialog).init(gpa),
            .toasts = std.ArrayList(Toast).init(gpa),
            .keybinds = std.StringHashMap(enums.Keybind).init(gpa),
            .debug_refresh_mutex = std.Thread.Mutex{},
            .wd = WidgetData{ .src = src, .id = hashval, .init_options = .{ .subwindow = true }, .options = .{ .name = "Window" } },
            .backend = backend_ctx,
            .font_bytes = try Font.initTTFBytesDatabase(gpa),
            .themes = std.StringArrayHashMap(Theme).init(gpa),
        };

        try self.themes.putNoClobber("Adwaita Light", @import("themes/Adwaita.zig").light);
        try self.themes.putNoClobber("Adwaita Dark", @import("themes/Adwaita.zig").dark);

        inline for (@typeInfo(Theme.QuickTheme.builtin).@"struct".decls) |decl| {
            const quick_theme = Theme.QuickTheme.fromString(self.arena(), @field(Theme.QuickTheme.builtin, decl.name)) catch {
                @panic("Failure loading builtin theme. This is a problem with DVUI.");
            };
            defer quick_theme.deinit();
            const theme = try quick_theme.value.toTheme(self.gpa);
            try self.themes.putNoClobber(theme.name, theme);
        }

        // Sort themes alphabetically
        const Context = struct {
            hashmap: *std.StringArrayHashMap(Theme),
            pub fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
                return std.ascii.orderIgnoreCase(ctx.hashmap.values()[lhs].name, ctx.hashmap.values()[rhs].name) == .lt;
            }
        };
        self.themes.sort(Context{ .hashmap = &self.themes });
        if (init_opts.theme) |t| {
            self.theme = t.*;
        } else {
            self.theme = self.themes.get("Adwaita Light").?;
        }

        try self.initEvents();

        const kb = init_opts.keybinds orelse blk: {
            if (builtin.os.tag.isDarwin()) {
                break :blk .mac;
            } else {
                break :blk .windows;
            }
        };

        if (kb == .windows or kb == .mac) {
            try self.keybinds.putNoClobber("activate", .{ .key = .enter, .also = "activate_1" });
            try self.keybinds.putNoClobber("activate_1", .{ .key = .space });

            try self.keybinds.putNoClobber("next_widget", .{ .key = .tab, .shift = false });
            try self.keybinds.putNoClobber("prev_widget", .{ .key = .tab, .shift = true });
        }

        switch (kb) {
            .none => {},
            .windows => {
                // zig fmt: off
                try self.keybinds.putNoClobber("cut",        .{ .key = .x, .control = true });
                try self.keybinds.putNoClobber("copy",       .{ .key = .c, .control = true });
                try self.keybinds.putNoClobber("paste",      .{ .key = .v, .control = true });
                try self.keybinds.putNoClobber("select_all", .{ .key = .a, .control = true });

                try self.keybinds.putNoClobber("ctrl/cmd",   .{ .key = .left_control, .also = "ctrl/cmd_1" });
                try self.keybinds.putNoClobber("ctrl/cmd_1", .{ .key = .right_control });

                try self.keybinds.putNoClobber("text_start",        .{ .key = .home, .shift = false, .control = true });
                try self.keybinds.putNoClobber("text_end",          .{ .key = .end,  .shift = false, .control = true });
                try self.keybinds.putNoClobber("text_start_select", .{ .key = .home, .shift = true,  .control = true });
                try self.keybinds.putNoClobber("text_end_select",   .{ .key = .end,  .shift = true,  .control = true });

                try self.keybinds.putNoClobber("line_start",        .{ .key = .home, .shift = false, .control = false });
                try self.keybinds.putNoClobber("line_end",          .{ .key = .end,  .shift = false, .control = false });
                try self.keybinds.putNoClobber("line_start_select", .{ .key = .home, .shift = true,  .control = false });
                try self.keybinds.putNoClobber("line_end_select",   .{ .key = .end,  .shift = true,  .control = false });

                try self.keybinds.putNoClobber("word_left",         .{ .key = .left,  .shift = false, .control = true });
                try self.keybinds.putNoClobber("word_right",        .{ .key = .right, .shift = false, .control = true });
                try self.keybinds.putNoClobber("word_left_select",  .{ .key = .left,  .shift = true,  .control = true });
                try self.keybinds.putNoClobber("word_right_select", .{ .key = .right, .shift = true,  .control = true });

                try self.keybinds.putNoClobber("char_left",         .{ .key = .left,  .shift = false, .control = false });
                try self.keybinds.putNoClobber("char_right",        .{ .key = .right, .shift = false, .control = false });
                try self.keybinds.putNoClobber("char_left_select",  .{ .key = .left,  .shift = true,  .control = false });
                try self.keybinds.putNoClobber("char_right_select", .{ .key = .right, .shift = true,  .control = false });

                try self.keybinds.putNoClobber("char_up",          .{ .key = .up,   .shift = false });
                try self.keybinds.putNoClobber("char_down",        .{ .key = .down, .shift = false });
                try self.keybinds.putNoClobber("char_up_select",   .{ .key = .up,   .shift = true });
                try self.keybinds.putNoClobber("char_down_select", .{ .key = .down, .shift = true });

                try self.keybinds.putNoClobber("delete_prev_word", .{ .key = .backspace, .control = true });
                try self.keybinds.putNoClobber("delete_next_word", .{ .key = .delete,    .control = true });
                // zig fmt: on
            },
            .mac => {
                // zig fmt: off
                try self.keybinds.putNoClobber("cut",        .{ .key = .x, .command = true });
                try self.keybinds.putNoClobber("copy",       .{ .key = .c, .command = true });
                try self.keybinds.putNoClobber("paste",      .{ .key = .v, .command = true });
                try self.keybinds.putNoClobber("select_all", .{ .key = .a, .command = true });

                try self.keybinds.putNoClobber("ctrl/cmd",   .{ .key = .left_command, .also = "ctrl/cmd_1" });
                try self.keybinds.putNoClobber("ctrl/cmd_1", .{ .key = .right_command });

                try self.keybinds.putNoClobber("text_start",        .{ .key = .up,   .shift = false, .command = true });
                try self.keybinds.putNoClobber("text_end",          .{ .key = .down, .shift = false, .command = true });
                try self.keybinds.putNoClobber("text_start_select", .{ .key = .up,   .shift = true,  .command = true });
                try self.keybinds.putNoClobber("text_end_select",   .{ .key = .down, .shift = true,  .command = true });

                try self.keybinds.putNoClobber("line_start",        .{ .key = .left,  .shift = false, .command = true });
                try self.keybinds.putNoClobber("line_end",          .{ .key = .right, .shift = false, .command = true });
                try self.keybinds.putNoClobber("line_start_select", .{ .key = .left,  .shift = true,  .command = true });
                try self.keybinds.putNoClobber("line_end_select",   .{ .key = .right, .shift = true,  .command = true });

                try self.keybinds.putNoClobber("word_left",         .{ .key = .left,  .shift = false, .alt = true });
                try self.keybinds.putNoClobber("word_right",        .{ .key = .right, .shift = false, .alt = true });
                try self.keybinds.putNoClobber("word_left_select",  .{ .key = .left,  .shift = true,  .alt = true });
                try self.keybinds.putNoClobber("word_right_select", .{ .key = .right, .shift = true,  .alt = true });

                try self.keybinds.putNoClobber("char_left",         .{ .key = .left,  .shift = false, .alt = false });
                try self.keybinds.putNoClobber("char_right",        .{ .key = .right, .shift = false, .alt = false });
                try self.keybinds.putNoClobber("char_left_select",  .{ .key = .left,  .shift = true,  .alt = false });
                try self.keybinds.putNoClobber("char_right_select", .{ .key = .right, .shift = true,  .alt = false });

                try self.keybinds.putNoClobber("char_up",          .{ .key = .up,   .shift = false, .command = false });
                try self.keybinds.putNoClobber("char_down",        .{ .key = .down, .shift = false, .command = false });
                try self.keybinds.putNoClobber("char_up_select",   .{ .key = .up,   .shift = true,  .command = false });
                try self.keybinds.putNoClobber("char_down_select", .{ .key = .down, .shift = true,  .command = false });

                try self.keybinds.putNoClobber("delete_prev_word", .{ .key = .backspace, .alt = true });
                try self.keybinds.putNoClobber("delete_next_word", .{ .key = .delete,    .alt = true });
                // zig fmt: on
            },
        }

        const winSize = self.backend.windowSize();
        const pxSize = self.backend.pixelSize();
        self.content_scale = self.backend.contentScale();

        // Even on hidpi screens I see slight flattening of the sides of glyphs
        // when snap_to_pixels is false, so we are going to default on for now.
        //const total_scale = self.content_scale * pxSize.w / winSize.w;
        //if (total_scale >= 2.0) {
        //    self.snap_to_pixels = false;
        //}

        log.info("window logical {} pixels {} natural scale {d} initial content scale {d} snap_to_pixels {}\n", .{ winSize, pxSize, pxSize.w / winSize.w, self.content_scale, self.snap_to_pixels });

        errdefer self.deinit();

        self.focused_subwindowId = self.wd.id;
        self.frame_time_ns = 1;

        if (useFreeType) {
            FontCacheEntry.intToError(c.FT_Init_FreeType(&ft2lib)) catch |err| {
                dvui.log.err("freetype error {!} trying to init freetype library\n", .{err});
                return error.freetypeError;
            };
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        {
            var it = self.datas.iterator();
            while (it.next()) |item| item.value_ptr.free(self.gpa);
            self.datas.deinit();
        }

        if (self.debug_under_mouse_info.len > 0) {
            self.gpa.free(self.debug_under_mouse_info);
            self.debug_under_mouse_info = "";
        }

        self.subwindows.deinit();
        self.min_sizes.deinit();
        self.animations.deinit();
        self.tab_index_prev.deinit();
        self.tab_index.deinit();

        {
            var it = self.font_cache.iterator();
            while (it.next()) |item| {
                item.value_ptr.glyph_info.deinit();
                item.value_ptr.deinit(self);
            }
            self.font_cache.deinit();
        }

        {
            var it = self.texture_cache.iterator();
            while (it.next()) |item| {
                self.backend.textureDestroy(item.value_ptr.texture);
            }
            self.texture_cache.deinit();
        }

        self.dialogs.deinit();
        self.toasts.deinit();
        self.keybinds.deinit();
        self._arena.deinit();

        {
            var it = self.font_bytes.valueIterator();
            while (it.next()) |fbe| {
                if (fbe.allocator) |a| {
                    a.free(fbe.ttf_bytes);
                }
            }
        }
        self.font_bytes.deinit();

        {
            for (self.themes.values()) |*theme| {
                theme.deinit(self.gpa);
            }
        }
        self.themes.deinit();
    }

    pub fn arena(self: *Self) std.mem.Allocator {
        return self._arena.allocator();
    }

    // called from any thread
    pub fn debugRefresh(self: *Self, val: ?bool) bool {
        self.debug_refresh_mutex.lock();
        defer self.debug_refresh_mutex.unlock();

        const previous = self.debug_refresh;
        if (val) |v| {
            self.debug_refresh = v;
        }

        return previous;
    }

    // called from gui thread
    pub fn refreshWindow(self: *Self, src: std.builtin.SourceLocation, id: ?u32) void {
        if (self.debugRefresh(null)) {
            log.debug("{s}:{d} refresh {?x}", .{ src.file, src.line, id });
        }
        self.extra_frames_needed = 1;
    }

    // called from any thread
    pub fn refreshBackend(self: *Self, src: std.builtin.SourceLocation, id: ?u32) void {
        if (self.debugRefresh(null)) {
            log.debug("{s}:{d} refreshBackend {?x}", .{ src.file, src.line, id });
        }
        self.backend.refresh();
    }

    pub fn focusSubwindowInternal(self: *Self, subwindow_id: ?u32, event_num: ?u16) void {
        const winId = subwindow_id orelse self.subwindow_currentId;
        if (self.focused_subwindowId != winId) {
            self.focused_subwindowId = winId;
            self.refreshWindow(@src(), null);
            if (event_num) |en| {
                for (self.subwindows.items) |*sw| {
                    if (self.focused_subwindowId == sw.id) {
                        self.focusRemainingEventsInternal(en, sw.id, sw.focused_widgetId);
                        break;
                    }
                }
            }
        }
    }

    pub fn focusRemainingEventsInternal(self: *Self, event_num: u16, focusWindowId: u32, focusWidgetId: ?u32) void {
        var evts = self.events.items;
        var k: usize = 0;
        while (k < evts.len) : (k += 1) {
            var e: *Event = &evts[k];
            if (e.num > event_num and e.focus_windowId != null) {
                e.focus_windowId = focusWindowId;
                e.focus_widgetId = focusWidgetId;
            }
        }
    }

    /// Add a keyboard event (key up/down/repeat) to the dvui event list.
    ///
    /// This can be called outside begin/end.  You should add all the events
    /// for a frame either before begin() or just after begin() and before
    /// calling normal dvui widgets.  end() clears the event list.
    pub fn addEventKey(self: *Self, event: Event.Key) !bool {
        if (self.debug_under_mouse and self.debug_under_mouse_esc_needed and event.action == .down and event.code == .escape) {
            // an escape will stop the debug stuff from following the mouse,
            // but need to stop it at the end of the frame when we've gotten
            // the info
            self.debug_under_mouse_quitting = true;
            return true;
        }

        self.positionMouseEventRemove();

        self.event_num += 1;
        try self.events.append(self.arena(), Event{
            .num = self.event_num,
            .evt = .{ .key = event },
            .focus_windowId = self.focused_subwindowId,
            .focus_widgetId = if (self.subwindows.items.len == 0) null else self.subwindowFocused().focused_widgetId,
        });

        const ret = (self.wd.id != self.focused_subwindowId);
        try self.positionMouseEventAdd();
        return ret;
    }

    /// Add an event that represents text being typed.  This is distinct from
    /// key up/down because the text could come from an IME (Input Method
    /// Editor).
    ///
    /// This can be called outside begin/end.  You should add all the events
    /// for a frame either before begin() or just after begin() and before
    /// calling normal dvui widgets.  end() clears the event list.
    pub fn addEventText(self: *Self, text: []const u8) !bool {
        return try self.addEventTextEx(text, false);
    }

    pub fn addEventTextEx(self: *Self, text: []const u8, selected: bool) !bool {
        self.positionMouseEventRemove();

        self.event_num += 1;
        try self.events.append(self.arena(), Event{
            .num = self.event_num,
            .evt = .{ .text = .{ .txt = try self._arena.allocator().dupe(u8, text), .selected = selected } },
            .focus_windowId = self.focused_subwindowId,
            .focus_widgetId = if (self.subwindows.items.len == 0) null else self.subwindowFocused().focused_widgetId,
        });

        const ret = (self.wd.id != self.focused_subwindowId);
        try self.positionMouseEventAdd();
        return ret;
    }

    /// Add a mouse motion event.  This is only for a mouse - for touch motion
    /// use addEventTouchMotion().
    ///
    /// This can be called outside begin/end.  You should add all the events
    /// for a frame either before begin() or just after begin() and before
    /// calling normal dvui widgets.  end() clears the event list.
    pub fn addEventMouseMotion(self: *Self, x: f32, y: f32) !bool {
        self.positionMouseEventRemove();

        const newpt = (Point{ .x = x, .y = y }).scale(self.natural_scale / self.content_scale);
        //log.debug("mouse motion {d} {d} -> {d} {d}", .{ x, y, newpt.x, newpt.y });
        const dp = newpt.diff(self.mouse_pt);
        self.mouse_pt = newpt;
        const winId = self.windowFor(self.mouse_pt);

        // maybe could do focus follows mouse here
        // - generate a .focus event here instead of just doing focusWindow(winId, null);
        // - how to make it optional?

        self.event_num += 1;
        try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = .motion,
                .button = if (self.debug_touch_simulate_events and self.debug_touch_simulate_down) .touch0 else .none,
                .p = self.mouse_pt,
                .floating_win = winId,
                .data = .{ .motion = dp },
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    /// Add a mouse button event (like left button down/up).
    ///
    /// This can be called outside begin/end.  You should add all the events
    /// for a frame either before begin() or just after begin() and before
    /// calling normal dvui widgets.  end() clears the event list.
    pub fn addEventMouseButton(self: *Self, b: enums.Button, action: Event.Mouse.Action) !bool {
        return addEventPointer(self, b, action, null);
    }

    /// Add a touch up/down event.  This is similar to addEventMouseButton but
    /// also includes a normalized (0-1) touch point.
    ///
    /// This can be called outside begin/end.  You should add all the events
    /// for a frame either before begin() or just after begin() and before
    /// calling normal dvui widgets.  end() clears the event list.
    pub fn addEventPointer(self: *Self, b: enums.Button, action: Event.Mouse.Action, xynorm: ?Point) !bool {
        if (self.debug_under_mouse and !self.debug_under_mouse_esc_needed and action == .press and b.pointer()) {
            // a left click or touch will stop the debug stuff from following
            // the mouse, but need to stop it at the end of the frame when
            // we've gotten the info
            self.debug_under_mouse_quitting = true;
            return true;
        }

        var bb = b;
        if (self.debug_touch_simulate_events and bb == .left) {
            bb = .touch0;
            if (action == .press) {
                self.debug_touch_simulate_down = true;
            } else if (action == .release) {
                self.debug_touch_simulate_down = false;
            }
        }

        self.positionMouseEventRemove();

        if (xynorm) |xyn| {
            const newpt = (Point{ .x = xyn.x * self.wd.rect.w, .y = xyn.y * self.wd.rect.h }).scale(self.natural_scale);
            self.mouse_pt = newpt;
        }

        const winId = self.windowFor(self.mouse_pt);

        if (action == .press and bb.pointer()) {
            // normally the focus event is what focuses windows, but since the
            // base window is instantiated before events are added, it has to
            // do any event processing as the events come in, right now
            if (winId == self.wd.id) {
                // focus the window here so any more key events get routed
                // properly
                self.focusSubwindowInternal(self.wd.id, null);
            }

            // add focus event
            self.event_num += 1;
            try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
                .mouse = .{
                    .action = .focus,
                    .button = bb,
                    .p = self.mouse_pt,
                    .floating_win = winId,
                },
            } });
        }

        self.event_num += 1;
        try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = action,
                .button = bb,
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    /// Add a mouse wheel event.  Positive ticks means scrolling up.
    ///
    /// This can be called outside begin/end.  You should add all the events
    /// for a frame either before begin() or just after begin() and before
    /// calling normal dvui widgets.  end() clears the event list.
    pub fn addEventMouseWheel(self: *Self, ticks: f32) !bool {
        self.positionMouseEventRemove();

        const winId = self.windowFor(self.mouse_pt);

        //std.debug.print("mouse wheel {d}\n", .{ticks});

        self.event_num += 1;
        try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = .wheel_y,
                .button = .none,
                .p = self.mouse_pt,
                .floating_win = winId,
                .data = .{ .wheel_y = ticks },
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    /// Add an event that represents a finger moving while touching the screen.
    ///
    /// This can be called outside begin/end.  You should add all the events
    /// for a frame either before begin() or just after begin() and before
    /// calling normal dvui widgets.  end() clears the event list.
    pub fn addEventTouchMotion(self: *Self, finger: enums.Button, xnorm: f32, ynorm: f32, dxnorm: f32, dynorm: f32) !bool {
        self.positionMouseEventRemove();

        const newpt = (Point{ .x = xnorm * self.wd.rect.w, .y = ynorm * self.wd.rect.h }).scale(self.natural_scale);
        //std.debug.print("touch motion {} {d} {d}\n", .{ finger, newpt.x, newpt.y });
        self.mouse_pt = newpt;

        const dp = (Point{ .x = dxnorm * self.wd.rect.w, .y = dynorm * self.wd.rect.h }).scale(self.natural_scale);

        const winId = self.windowFor(self.mouse_pt);

        self.event_num += 1;
        try self.events.append(self.arena(), Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = .motion,
                .button = finger,
                .p = self.mouse_pt,
                .floating_win = winId,
                .data = .{ .motion = dp },
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    pub fn FPS(self: *const Self) f32 {
        const diff = self.frame_times[0];
        if (diff == 0) {
            return 0;
        }

        const avg = @as(f32, @floatFromInt(diff)) / @as(f32, @floatFromInt(self.frame_times.len - 1));
        const fps = 1_000_000.0 / avg;
        return fps;
    }

    /// beginWait coordinates with waitTime() to run frames only when needed
    pub fn beginWait(self: *Self, has_event: bool) i128 {
        var new_time = @max(self.frame_time_ns, self.backend.nanoTime());

        if (self.loop_wait_target) |target| {
            if (self.loop_wait_target_event and has_event) {
                // interrupted by event, so don't adjust slop for target
                //std.debug.print("beginWait interrupted by event\n", .{});
                return new_time;
            }

            //std.debug.print("beginWait adjusting slop\n", .{});
            // we were trying to sleep for a specific amount of time, adjust slop to
            // compensate if we didn't hit our target
            if (new_time > target) {
                // woke up later than expected
                self.loop_target_slop_frames = math.clamp(self.loop_target_slop_frames * 2, 1, 1000);
                self.loop_target_slop += self.loop_target_slop_frames;
            } else if (new_time < target) {
                // woke up sooner than expected
                self.loop_target_slop_frames = math.clamp(self.loop_target_slop_frames * 2, -1000, -1);
                self.loop_target_slop += self.loop_target_slop_frames;

                const max_behind = std.time.ns_per_ms;
                if (new_time > target - max_behind) {
                    // we are early (but not too early), so spin a bit to try and hit target
                    //var i: usize = 0;
                    //var first_time = new_time;
                    while (new_time < target) {
                        //i += 1;
                        self.backend.sleep(0);
                        new_time = @max(self.frame_time_ns, self.backend.nanoTime());
                    }

                    //if (i > 0) {
                    //  std.debug.print("    begin {d} spun {d} {d}us\n", .{self.loop_target_slop, i, @divFloor(new_time - first_time, 1000)});
                    //}
                }
            }

            // make sure this never gets too crazy -1ms to 100ms
            self.loop_target_slop = math.clamp(self.loop_target_slop, -1_000, 100_000);
        }

        //std.debug.print("beginWait {d:6} {d}\n", .{ self.loop_target_slop, self.loop_target_slop_frames });
        return new_time;
    }

    // Takes output of end() and optionally a max fps.  Returns microseconds
    // the app should wait (with event interruption) before running the render
    // loop again.  Pass return value to backend.waitEventTimeout().
    // Cooperates with beginWait() to estimate how much time is being spent
    // outside the render loop and account for that.
    pub fn waitTime(self: *Self, end_micros: ?u32, maxFPS: ?f32) u32 {
        // end_micros is the naive value we want to be between last begin and next begin

        // minimum time to wait to hit max fps target
        var min_micros: u32 = 0;
        if (maxFPS) |mfps| {
            min_micros = @as(u32, @intFromFloat(1_000_000.0 / mfps));
        }

        //std.debug.print("  end {d:6} min {d:6}", .{end_micros, min_micros});

        // wait_micros is amount on top of min_micros we will conditionally wait
        var wait_micros = (end_micros orelse 0) -| min_micros;

        // assume that we won't target a specific time to sleep but if we do
        // calculate the targets before removing so_far and slop
        self.loop_wait_target = null;
        self.loop_wait_target_event = false;
        const target_min = min_micros;
        const target = min_micros + wait_micros;

        // how long it's taken from begin to here
        const so_far_nanos = @max(self.frame_time_ns, self.backend.nanoTime()) - self.frame_time_ns;
        var so_far_micros = @as(u32, @intCast(@divFloor(so_far_nanos, 1000)));
        //std.debug.print("  far {d:6}", .{so_far_micros});

        // take time from min_micros first
        const min_so_far = @min(so_far_micros, min_micros);
        so_far_micros -= min_so_far;
        min_micros -= min_so_far;

        // then take time from wait_micros
        const min_so_far2 = @min(so_far_micros, wait_micros);
        so_far_micros -= min_so_far2;
        wait_micros -= min_so_far2;

        var slop = self.loop_target_slop;

        // get slop we can take out of min_micros
        const min_us_slop = @min(slop, @as(i32, @intCast(min_micros)));
        slop -= min_us_slop;
        if (min_us_slop >= 0) {
            min_micros -= @as(u32, @intCast(min_us_slop));
        } else {
            min_micros += @as(u32, @intCast(-min_us_slop));
        }

        // remaining slop we can take out of wait_micros
        const wait_us_slop = @min(slop, @as(i32, @intCast(wait_micros)));
        slop -= wait_us_slop;
        if (wait_us_slop >= 0) {
            wait_micros -= @as(u32, @intCast(wait_us_slop));
        } else {
            wait_micros += @as(u32, @intCast(-wait_us_slop));
        }

        //std.debug.print("  min {d:6}", .{min_micros});
        if (min_micros > 0) {
            // wait unconditionally for fps target
            self.backend.sleep(min_micros * 1000);
            self.loop_wait_target = self.frame_time_ns + (@as(i128, @intCast(target_min)) * 1000);
        }

        if (end_micros == null) {
            // no target, wait indefinitely for next event
            self.loop_wait_target = null;
            //std.debug.print("  wait indef\n", .{});
            return std.math.maxInt(u32);
        } else if (wait_micros > 0) {
            // wait conditionally
            // since we have a timeout we will try to hit that target but set our
            // flag so that we don't adjust for the target if we wake up to an event
            self.loop_wait_target = self.frame_time_ns + (@as(i128, @intCast(target)) * 1000);
            self.loop_wait_target_event = true;
            //std.debug.print("  wait {d:6}\n", .{wait_micros});
            return wait_micros;
        } else {
            // trying to hit the target but ran out of time
            //std.debug.print("  wait none\n", .{});
            return 0;
            // if we had a wait target from min_micros leave it
        }
    }

    pub fn begin(
        self: *Self,
        time_ns: i128,
    ) !void {
        const larena = self._arena.allocator();

        var micros_since_last: u32 = 1;
        if (time_ns > self.frame_time_ns) {
            // enforce monotinicity
            var nanos_since_last = time_ns - self.frame_time_ns;

            // make sure the @intCast below doesn't panic
            const max_nanos_since_last: i128 = std.math.maxInt(u32) * std.time.ns_per_us;
            nanos_since_last = @min(nanos_since_last, max_nanos_since_last);

            micros_since_last = @as(u32, @intCast(@divFloor(nanos_since_last, std.time.ns_per_us)));
            micros_since_last = @max(1, micros_since_last);
            self.frame_time_ns = time_ns;
        }

        //std.debug.print(" frame_time_ns {d}\n", .{self.frame_time_ns});

        self.previous_window = current_window;
        current_window = self;

        self.cursor_requested = .arrow;
        self.text_input_rect = null;
        self.debug_info_name_rect = "";
        self.debug_info_src_id_extra = "";
        if (self.debug_under_mouse) {
            if (self.debug_under_mouse_info.len > 0) {
                self.gpa.free(self.debug_under_mouse_info);
            }
            self.debug_under_mouse_info = "";
        }

        self.texture_trash = std.ArrayList(*anyopaque).init(larena);
        self.path = std.ArrayList(Point).init(larena);

        {
            var i: usize = 0;
            while (i < self.subwindows.items.len) {
                var sw = &self.subwindows.items[i];
                if (sw.used) {
                    sw.used = false;
                    i += 1;
                } else {
                    _ = self.subwindows.orderedRemove(i);
                }
            }
        }

        for (self.frame_times, 0..) |_, i| {
            if (i == (self.frame_times.len - 1)) {
                self.frame_times[i] = 0;
            } else {
                self.frame_times[i] = self.frame_times[i + 1] +| micros_since_last;
            }
        }

        {
            var deadSizes = std.ArrayList(u32).init(larena);
            defer deadSizes.deinit();
            var it = self.min_sizes.iterator();
            while (it.next()) |kv| {
                if (kv.value_ptr.used) {
                    kv.value_ptr.used = false;
                } else {
                    try deadSizes.append(kv.key_ptr.*);
                }
            }

            for (deadSizes.items) |id| {
                _ = self.min_sizes.remove(id);
            }

            //std.debug.print("min_sizes {d}\n", .{self.min_sizes.count()});
        }

        {
            self.data_mutex.lock();
            defer self.data_mutex.unlock();

            var deadDatas = std.ArrayList(u32).init(larena);
            defer deadDatas.deinit();
            var it = self.datas.iterator();
            while (it.next()) |kv| {
                if (kv.value_ptr.used) {
                    kv.value_ptr.used = false;
                } else {
                    try deadDatas.append(kv.key_ptr.*);
                }
            }

            for (deadDatas.items) |id| {
                var dd = self.datas.fetchRemove(id).?;
                dd.value.free(self.gpa);
            }

            //std.debug.print("datas {d}\n", .{self.datas.count()});
        }

        self.tab_index_prev.deinit();
        self.tab_index_prev = self.tab_index;
        self.tab_index = @TypeOf(self.tab_index).init(self.tab_index.allocator);

        self.rect_pixels = self.backend.pixelSize().rect();
        clipSet(self.rect_pixels);

        self.wd.rect = self.backend.windowSize().rect().scale(1.0 / self.content_scale);
        self.natural_scale = self.rect_pixels.w / self.wd.rect.w;

        //dvui.log.debug("window size {d} x {d} renderer size {d} x {d} scale {d}", .{ self.wd.rect.w, self.wd.rect.h, self.rect_pixels.w, self.rect_pixels.h, self.natural_scale });

        try subwindowAdd(self.wd.id, self.wd.rect, self.rect_pixels, false, null);

        _ = subwindowCurrentSet(self.wd.id, self.wd.rect);

        self.extra_frames_needed -|= 1;
        self.secs_since_last_frame = @as(f32, @floatFromInt(micros_since_last)) / 1_000_000;

        {
            const micros: i32 = if (micros_since_last > math.maxInt(i32)) math.maxInt(i32) else @as(i32, @intCast(micros_since_last));
            var deadAnimations = std.ArrayList(u32).init(larena);
            defer deadAnimations.deinit();
            var it = self.animations.iterator();
            while (it.next()) |kv| {
                if (!kv.value_ptr.used or kv.value_ptr.end_time <= 0) {
                    try deadAnimations.append(kv.key_ptr.*);
                } else {
                    kv.value_ptr.used = false;
                    kv.value_ptr.start_time -|= micros;
                    kv.value_ptr.end_time -|= micros;
                    if (kv.value_ptr.start_time <= 0 and kv.value_ptr.end_time > 0) {
                        refresh(null, @src(), null);
                    }
                }
            }

            for (deadAnimations.items) |id| {
                _ = self.animations.remove(id);
            }
        }

        {
            var deadFonts = std.ArrayList(u32).init(larena);
            defer deadFonts.deinit();
            var it = self.font_cache.iterator();
            while (it.next()) |kv| {
                if (kv.value_ptr.used) {
                    kv.value_ptr.used = false;
                } else {
                    try deadFonts.append(kv.key_ptr.*);
                }
            }

            for (deadFonts.items) |id| {
                var tce = self.font_cache.fetchRemove(id).?;
                tce.value.glyph_info.deinit();
                tce.value.deinit(self);
            }

            //std.debug.print("font_cache {d}\n", .{self.font_cache.count()});
        }

        {
            var deadIcons = std.ArrayList(u32).init(larena);
            defer deadIcons.deinit();
            var it = self.texture_cache.iterator();
            while (it.next()) |kv| {
                if (kv.value_ptr.used) {
                    kv.value_ptr.used = false;
                } else {
                    try deadIcons.append(kv.key_ptr.*);
                }
            }

            for (deadIcons.items) |id| {
                const ice = self.texture_cache.fetchRemove(id).?;
                self.backend.textureDestroy(ice.value.texture);
            }

            //std.debug.print("texture_cache {d}\n", .{self.texture_cache.count()});
        }

        if (!self.captured_last_frame) {
            // widget that had capture went away
            self.captureID = null;
        }
        self.captured_last_frame = false;

        self.wd.parent = self.widget();

        // Window's wd is kept frame to frame, so manually reset the cache.
        self.wd.rect_scale_cache = null;
        try self.wd.register();

        self.next_widget_ypos = self.wd.rect.y;

        self.backend.begin(larena);
    }

    fn positionMouseEventAdd(self: *Self) !void {
        try self.events.append(self.arena(), .{ .evt = .{ .mouse = .{
            .action = .position,
            .button = .none,
            .p = self.mouse_pt,
            .floating_win = self.windowFor(self.mouse_pt),
        } } });
    }

    fn positionMouseEventRemove(self: *Self) void {
        const e = self.events.pop();
        if (e.evt != .mouse or e.evt.mouse.action != .position) {
            log.err("positionMouseEventRemove removed a non-mouse or non-position event\n", .{});
        }
    }

    pub fn windowFor(self: *const Self, p: Point) u32 {
        var i = self.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &self.subwindows.items[i - 1];
            if (sw.modal or sw.rect_pixels.contains(p)) {
                return sw.id;
            }
        }

        return self.wd.id;
    }

    pub fn subwindowCurrent(self: *const Self) *Subwindow {
        var i = self.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &self.subwindows.items[i - 1];
            if (sw.id == self.subwindow_currentId) {
                return sw;
            }
        }

        log.warn("subwindowCurrent failed to find the current subwindow, returning base window\n", .{});
        return &self.subwindows.items[0];
    }

    pub fn subwindowFocused(self: *const Self) *Subwindow {
        var i = self.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &self.subwindows.items[i - 1];
            if (sw.id == self.focused_subwindowId) {
                return sw;
            }
        }

        log.warn("subwindowFocused failed to find the focused subwindow, returning base window\n", .{});
        return &self.subwindows.items[0];
    }

    // Return the cursor the gui wants.  Client code should cache this if
    // switching the platform's cursor is expensive.
    pub fn cursorRequested(self: *const Self) enums.Cursor {
        if (self.drag_state == .dragging and self.cursor_dragging != null) {
            return self.cursor_dragging.?;
        } else {
            return self.cursor_requested;
        }
    }

    // Return the cursor the gui wants or null if mouse is not in gui windows.
    // Client code should cache this if switching the platform's cursor is
    // expensive.
    pub fn cursorRequestedFloating(self: *const Self) ?enums.Cursor {
        if (self.captureID != null or self.windowFor(self.mouse_pt) != self.wd.id) {
            // gui owns the cursor if we have mouse capture or if the mouse is above
            // a floating window
            return self.cursorRequested();
        } else {
            // no capture, not above a floating window, so client owns the cursor
            return null;
        }
    }

    /// If a widget called wantTextInput this frame, return the rect (in
    /// natural pixels) of where the text input is happening.
    ///
    /// Apps and backends should use this to show an on screen keyboard and/or
    /// position an IME window.
    pub fn textInputRequested(self: *const Self) ?Rect {
        return self.text_input_rect;
    }

    pub fn renderCommands(self: *Self, queue: std.ArrayList(RenderCommand)) !void {
        const oldsnap = snapToPixels();
        defer _ = snapToPixelsSet(oldsnap);

        const oldclip = clipGet();
        defer clipSet(oldclip);

        const old_rendering = renderingSet(true);
        defer _ = renderingSet(old_rendering);

        for (queue.items) |*drc| {
            _ = snapToPixelsSet(drc.snap);
            clipSet(drc.clip);
            switch (drc.cmd) {
                .text => |t| {
                    try renderText(t);
                },
                .debug_font_atlases => |t| {
                    try debugRenderFontAtlases(t.rs, t.color);
                },
                .texture => |t| {
                    try renderTexture(t.tex, t.rs, t.opts);
                },
                .pathFillConvex => |pf| {
                    try self.path.appendSlice(pf.path.items);
                    try pathFillConvex(pf.color);
                    pf.path.deinit();
                },
                .pathStroke => |ps| {
                    try self.path.appendSlice(ps.path.items);
                    try pathStrokeRaw(ps.closed, ps.thickness, ps.endcap_style, ps.color);
                    ps.path.deinit();
                },
            }
        }
    }

    // data is copied into internal storage
    pub fn dataSetAdvanced(self: *Self, id: u32, key: []const u8, data_in: anytype, comptime copy_slice: bool, num_copies: usize) void {
        const hash = hashIdKey(id, key);

        const dt = @typeInfo(@TypeOf(data_in));
        const dt_type_str = @typeName(@TypeOf(data_in));
        var bytes: []const u8 = undefined;
        if (copy_slice) {
            bytes = std.mem.sliceAsBytes(data_in);
            if (dt.pointer.sentinel() != null) {
                bytes.len += @sizeOf(dt.pointer.child);
            }
        } else {
            bytes = std.mem.asBytes(&data_in);
        }

        const alignment = comptime blk: {
            if (copy_slice) {
                break :blk dt.pointer.alignment;
            } else {
                break :blk @alignOf(@TypeOf(data_in));
            }
        };

        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (self.datas.getPtr(hash)) |sd| {
            if (sd.data.len == (bytes.len * num_copies)) {
                sd.used = true;
                if (builtin.mode == .Debug) {
                    sd.type_str = dt_type_str;
                    sd.copy_slice = copy_slice;
                }

                // Someone might do dataSetSlice on the slice they got from
                // dataGetSlice, and @memcpy would complain about aliasing
                if (sd.data.ptr != bytes.ptr) {
                    for (0..num_copies) |i| {
                        @memcpy(sd.data[i * bytes.len ..][0..bytes.len], bytes);
                    }
                }
                return;
            } else {
                //std.debug.print("dataSet: already had data for id {x} key {s}, freeing previous data\n", .{ id, key });
                sd.free(self.gpa);
            }
        }

        var sd = SavedData{ .alignment = alignment, .data = self.gpa.allocWithOptions(u8, bytes.len * num_copies, alignment, null) catch |err| switch (err) {
            error.OutOfMemory => {
                log.err("dataSet got {!} for id {x} key {s}\n", .{ err, id, key });
                return;
            },
        } };

        for (0..num_copies) |i| {
            @memcpy(sd.data[i * bytes.len ..][0..bytes.len], bytes);
        }

        if (builtin.mode == .Debug) {
            sd.type_str = dt_type_str;
            sd.copy_slice = copy_slice;
        }

        self.datas.put(hash, sd) catch |err| switch (err) {
            error.OutOfMemory => {
                log.err("dataSet got {!} for id {x} key {s}\n", .{ err, id, key });
                sd.free(self.gpa);
                return;
            },
        };
    }

    // returns the backing byte slice if we have one
    pub fn dataGetInternal(self: *Self, id: u32, key: []const u8, comptime T: type, slice: bool) ?[]u8 {
        const hash = hashIdKey(id, key);

        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (self.datas.getPtr(hash)) |sd| {
            if (builtin.mode == .Debug) {
                if (!std.mem.eql(u8, sd.type_str, @typeName(T)) or sd.copy_slice != slice) {
                    std.debug.panic("dataGetInternal: stored type {s} (slice {}) doesn't match asked for type {s} (slice {})", .{ sd.type_str, sd.copy_slice, @typeName(T), slice });
                }
            }

            sd.used = true;
            return sd.data;
        } else {
            return null;
        }
    }

    pub fn dataRemove(self: *Self, id: u32, key: []const u8) void {
        const hash = hashIdKey(id, key);

        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (self.datas.fetchRemove(hash)) |dd| {
            dd.value.free(self.gpa);
        }
    }

    // Add a dialog to be displayed on the GUI thread during Window.end(). Can
    // be called from any thread. Returns a locked mutex that must be unlocked
    // by the caller.  If calling from a non-GUI thread, do any dataSet() calls
    // before unlocking the mutex to ensure that data is available before the
    // dialog is displayed.
    pub fn dialogAdd(self: *Self, id: u32, display: DialogDisplayFn) !*std.Thread.Mutex {
        self.dialog_mutex.lock();

        for (self.dialogs.items) |*d| {
            if (d.id == id) {
                d.display = display;
                break;
            }
        } else {
            try self.dialogs.append(Dialog{ .id = id, .display = display });
        }

        return &self.dialog_mutex;
    }

    // Only called from gui thread.
    pub fn dialogRemove(self: *Self, id: u32) void {
        self.dialog_mutex.lock();
        defer self.dialog_mutex.unlock();

        for (self.dialogs.items, 0..) |*d, i| {
            if (d.id == id) {
                _ = self.dialogs.orderedRemove(i);
                return;
            }
        }
    }

    fn dialogsShow(self: *Self) !void {
        var i: usize = 0;
        var dia: ?Dialog = null;
        while (true) {
            self.dialog_mutex.lock();
            if (i < self.dialogs.items.len and
                dia != null and
                dia.?.id == self.dialogs.items[i].id)
            {
                // we just did this one, move to the next
                i += 1;
            }

            if (i < self.dialogs.items.len) {
                dia = self.dialogs.items[i];
            } else {
                dia = null;
            }
            self.dialog_mutex.unlock();

            if (dia) |d| {
                try d.display(d.id);
            } else {
                break;
            }
        }
    }

    pub fn timer(self: *Self, id: u32, micros: i32) !void {
        // when start_time is in the future, we won't spam frames, so this will
        // cause a single frame and then expire
        const a = Animation{ .start_time = micros, .end_time = micros };
        const h = hashIdKey(id, "_timer");
        try self.animations.put(h, a);
    }

    pub fn timerRemove(self: *Self, id: u32) void {
        const h = hashIdKey(id, "_timer");
        _ = self.animations.remove(h);
    }

    // Add a toast to be displayed on the GUI thread. Can be called from any
    // thread. Returns a locked mutex that must be unlocked by the caller.  If
    // calling from a non-GUI thread, do any dataSet() calls before unlocking
    // the mutex to ensure that data is available before the dialog is
    // displayed.
    pub fn toastAdd(self: *Self, id: u32, subwindow_id: ?u32, display: DialogDisplayFn, timeout: ?i32) !*std.Thread.Mutex {
        self.dialog_mutex.lock();

        for (self.toasts.items) |*t| {
            if (t.id == id) {
                t.display = display;
                t.subwindow_id = subwindow_id;
                break;
            }
        } else {
            try self.toasts.append(Toast{ .id = id, .subwindow_id = subwindow_id, .display = display });
        }

        if (timeout) |tt| {
            try self.timer(id, tt);
        } else {
            self.timerRemove(id);
        }

        return &self.dialog_mutex;
    }

    pub fn toastRemove(self: *Self, id: u32) void {
        self.dialog_mutex.lock();
        defer self.dialog_mutex.unlock();

        for (self.toasts.items, 0..) |*t, i| {
            if (t.id == id) {
                _ = self.toasts.orderedRemove(i);
                return;
            }
        }
    }

    // show any toasts that didn't have a subwindow_id set
    fn toastsShow(self: *Self) !void {
        var ti = dvui.toastsFor(null);
        if (ti) |*it| {
            var toast_win = FloatingWindowWidget.init(@src(), .{ .stay_above_parent_window = true, .process_events_in_deinit = false }, .{ .background = false, .border = .{} });
            defer toast_win.deinit();

            toast_win.data().rect = dvui.placeIn(self.wd.rect, toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
            toast_win.autoSize();
            try toast_win.install();
            try toast_win.drawBackground();

            var vbox = try dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            while (it.next()) |t| {
                try t.display(t.id);
            }
        }
    }

    fn debugWindowShow(self: *Self) !void {
        if (self.debug_under_mouse_quitting) {
            self.debug_under_mouse = false;
            self.debug_under_mouse_esc_needed = false;
            self.debug_under_mouse_quitting = false;
        }

        // disable so the widgets we are about to use to display this data
        // don't modify the data, otherwise our iterator will get corrupted and
        // even if you search for a widget here, the data won't be available
        var dum = self.debug_under_mouse;
        self.debug_under_mouse = false;
        defer self.debug_under_mouse = dum;

        var duf = self.debug_under_focus;
        self.debug_under_focus = false;
        defer self.debug_under_focus = duf;

        var float = try dvui.floatingWindow(@src(), .{ .open_flag = &self.debug_window_show }, .{ .min_size_content = .{ .w = 300, .h = 600 } });
        defer float.deinit();

        try dvui.windowHeader("DVUI Debug", "", &self.debug_window_show);

        {
            var hbox = try dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            try dvui.labelNoFmt(@src(), "Hex id of widget to highlight:", .{ .gravity_y = 0.5 });

            var buf = [_]u8{0} ** 20;
            if (self.debug_widget_id != 0) {
                _ = try std.fmt.bufPrint(&buf, "{x}", .{self.debug_widget_id});
            }
            var te = try dvui.textEntry(@src(), .{
                .text = .{ .buffer = &buf },
            }, .{});
            te.deinit();

            self.debug_widget_id = std.fmt.parseInt(u32, std.mem.sliceTo(&buf, 0), 16) catch 0;
        }

        var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 80 } });
        try tl.addText(self.debug_info_name_rect, .{});
        try tl.addText("\n\n", .{});
        try tl.addText(self.debug_info_src_id_extra, .{});
        tl.deinit();

        if (try dvui.button(@src(), if (dum) "Stop (Or Left Click)" else "Debug Under Mouse (until click)", .{}, .{})) {
            dum = !dum;
        }

        if (try dvui.button(@src(), if (dum) "Stop (Or Press Esc)" else "Debug Under Mouse (until esc)", .{}, .{})) {
            dum = !dum;
            self.debug_under_mouse_esc_needed = dum;
        }

        if (try dvui.button(@src(), if (duf) "Stop" else "Debug Focus", .{}, .{})) {
            duf = !duf;
        }

        const logit = self.debugRefresh(null);
        if (try dvui.button(@src(), if (logit) "Stop Refresh Logging" else "Start Refresh Logging", .{}, .{})) {
            _ = self.debugRefresh(!logit);
        }

        var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
        defer scroll.deinit();

        var iter = std.mem.splitScalar(u8, self.debug_under_mouse_info, '\n');
        var i: usize = 0;
        while (iter.next()) |line| : (i += 1) {
            if (line.len > 0) {
                var hbox = try dvui.box(@src(), .horizontal, .{ .id_extra = i });
                defer hbox.deinit();

                if (try dvui.buttonIcon(@src(), "find", entypo.magnifying_glass, .{}, .{ .min_size_content = .{ .h = 12 } })) {
                    self.debug_widget_id = std.fmt.parseInt(u32, std.mem.sliceTo(line, ' '), 16) catch 0;
                }

                try dvui.labelNoFmt(@src(), line, .{ .gravity_y = 0.5 });
            }
        }
    }

    pub const endOptions = struct {
        show_toasts: bool = true,
    };

    // End of this window gui's rendering.  Renders retained dialogs and all
    // deferred rendering (subwindows, focus highlights).  Returns micros we
    // want between last call to begin() and next call to begin() (or null
    // meaning wait for event).  If wanted, pass return value to waitTime() to
    // get a useful time to wait between render loops.
    pub fn end(self: *Self, opts: endOptions) !?u32 {
        if (opts.show_toasts) {
            try self.toastsShow();
        }
        try self.dialogsShow();

        if (self.debug_window_show) {
            try self.debugWindowShow();
        }

        for (self.subwindows.items) |*sw| {
            try self.renderCommands(sw.render_cmds);
            sw.render_cmds.clearAndFree();

            try self.renderCommands(sw.render_cmds_after);
            sw.render_cmds_after.clearAndFree();
        }

        for (self.texture_trash.items) |tex| {
            self.backend.textureDestroy(tex);
        }

        // events may have been tagged with a focus widget that never showed up, so
        // we wouldn't even get them bubbled
        const evts = events();
        for (evts) |*e| {
            if (self.drag_state == .dragging and e.evt == .mouse and e.evt.mouse.action == .release) {
                log.debug("clearing drag ({s}) for unhandled mouse release", .{self.drag_name});
                self.drag_state = .none;
                self.drag_name = "";
            }

            if (!eventMatch(e, .{ .id = self.wd.id, .r = self.rect_pixels, .cleanup = true }))
                continue;

            if (e.evt == .mouse) {
                if (e.evt.mouse.action == .focus) {
                    // unhandled click, clear focus
                    focusWidget(null, null, null);
                }
            } else if (e.evt == .key) {
                if (e.evt.key.action == .down and e.evt.key.matchBind("next_widget")) {
                    e.handled = true;
                    tabIndexNext(e.num);
                }

                if (e.evt.key.action == .down and e.evt.key.matchBind("prev_widget")) {
                    e.handled = true;
                    tabIndexPrev(e.num);
                }
            }
        }

        self.mouse_pt_prev = self.mouse_pt;

        if (!self.subwindowFocused().used) {
            // our focused subwindow didn't show this frame, focus the highest one that did
            var i = self.subwindows.items.len;
            while (i > 0) : (i -= 1) {
                const sw = self.subwindows.items[i - 1];
                if (sw.used) {
                    //std.debug.print("focused subwindow lost, focusing {d}\n", .{i - 1});
                    focusSubwindow(sw.id, null);
                    break;
                }
            }

            refresh(null, @src(), null);
        }

        // Check that the final event was our synthetic mouse position event.
        // If one of the addEvent* functions forgot to add the synthetic mouse
        // event to the end this will print a debug message.
        self.positionMouseEventRemove();

        _ = self._arena.reset(.retain_capacity);

        try self.initEvents();

        if (self.inject_motion_event) {
            self.inject_motion_event = false;
            const pt = self.mouse_pt.scale(self.content_scale / self.natural_scale);
            _ = try self.addEventMouseMotion(pt.x, pt.y);
        }

        self.backend.end();

        defer current_window = self.previous_window;

        // This is what refresh affects
        if (self.extra_frames_needed > 0) {
            return 0;
        }

        // If there are current animations, return 0 so we go as fast as we can.
        // If all animations are scheduled in the future, pick the soonest start.
        var ret: ?u32 = null;
        var it = self.animations.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.used) {
                if (kv.value_ptr.start_time > 0) {
                    const st = @as(u32, @intCast(kv.value_ptr.start_time));
                    ret = @min(ret orelse st, st);
                } else if (kv.value_ptr.end_time > 0) {
                    ret = 0;
                    break;
                }
            }
        }

        return ret;
    }

    fn initEvents(self: *Self) !void {
        self.events = .{};
        self.event_num = 0;

        // We want a position mouse event to do mouse cursors.  It needs to be
        // final so if there was a drag end the cursor will still be set
        // correctly.  We don't know when the client gives us the last event,
        // so make our position event now, and addEvent* functions will remove
        // and re-add to keep it as the final event.
        try self.positionMouseEventAdd();
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        _ = id;
        var r = self.wd.rect;
        r.y = self.next_widget_ypos;
        r.h -= r.y;
        const ret = placeIn(r, min_size, e, g);
        self.next_widget_ypos += ret.h;
        return ret;
    }

    pub fn screenRectScale(self: *Self, r: Rect) RectScale {
        const scaled = r.scale(self.natural_scale);
        return RectScale{ .r = scaled.offset(self.rect_pixels), .s = self.natural_scale };
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        // os window doesn't size itself based on children
        _ = self;
        _ = s;
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        // window does cleanup events, but not normal events
        switch (e.evt) {
            .close_popup => |cp| {
                e.handled = true;
                if (cp.intentional) {
                    // when a popup is closed due to a menu item being chosen,
                    // the window that spawned it (which had focus previously)
                    // should become focused again
                    focusSubwindow(self.wd.id, null);
                }
            },
            else => {},
        }

        // can't bubble past the base window
        _ = bubbling;
    }
};

pub const popup = @compileError("popup renamed to floatingMenu");

pub fn floatingMenu(src: std.builtin.SourceLocation, initialRect: Rect, opts: Options) !*FloatingMenuWidget {
    var ret = try currentWindow().arena().create(FloatingMenuWidget);
    ret.* = FloatingMenuWidget.init(src, initialRect, opts);
    try ret.install();
    return ret;
}

pub fn floatingWindow(src: std.builtin.SourceLocation, floating_opts: FloatingWindowWidget.InitOptions, opts: Options) !*FloatingWindowWidget {
    var ret = try currentWindow().arena().create(FloatingWindowWidget);
    ret.* = FloatingWindowWidget.init(src, floating_opts, opts);
    try ret.install();
    ret.processEventsBefore();
    try ret.drawBackground();
    return ret;
}

pub fn windowHeader(str: []const u8, right_str: []const u8, openflag: ?*bool) !void {
    var over = try dvui.overlay(@src(), .{ .expand = .horizontal });

    try dvui.labelNoFmt(@src(), str, .{ .gravity_x = 0.5, .gravity_y = 0.5, .expand = .horizontal, .font_style = .heading, .padding = .{ .x = 6, .y = 6, .w = 6, .h = 4 } });

    if (openflag) |of| {
        if (try dvui.buttonIcon(@src(), "close", entypo.cross, .{}, .{ .font_style = .heading, .corner_radius = Rect.all(1000), .padding = Rect.all(2), .margin = Rect.all(2), .gravity_y = 0.5, .expand = .ratio })) {
            of.* = false;
        }
    }

    try dvui.labelNoFmt(@src(), right_str, .{ .gravity_x = 1.0 });

    const evts = events();
    for (evts) |*e| {
        if (!eventMatch(e, .{ .id = over.wd.id, .r = over.wd.contentRectScale().r }))
            continue;

        if (e.evt == .mouse and e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
            // raise this subwindow but let the press continue so the window
            // will do the drag-move
            raiseSubwindow(subwindowCurrentId());
        } else if (e.evt == .mouse and e.evt.mouse.action == .focus) {
            // our window will already be focused, but this prevents the window
            // from clearing the focused widget
            e.handled = true;
        }
    }

    over.deinit();

    try dvui.separator(@src(), .{ .expand = .horizontal });
}

pub const DialogDisplayFn = *const fn (u32) anyerror!void;
pub const DialogCallAfterFn = *const fn (u32, enums.DialogResponse) anyerror!void;

pub const Dialog = struct {
    id: u32,
    display: DialogDisplayFn,
};

pub const IdMutex = struct {
    id: u32,
    mutex: *std.Thread.Mutex,
};

/// Add a dialog to be displayed on the GUI thread during Window.end().
///
/// Returns an id and locked mutex that must be unlocked by the caller. Caller
/// does any Window.dataSet() calls before unlocking the mutex to ensure that
/// data is available before the dialog is displayed.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the dialog to.
pub fn dialogAdd(win: ?*Window, src: std.builtin.SourceLocation, id_extra: usize, display: DialogDisplayFn) !IdMutex {
    if (win) |w| {
        // we are being called from non gui thread
        const id = hashSrc(src, id_extra);
        const mutex = try w.dialogAdd(id, display);
        refresh(win, @src(), id); // will wake up gui thread
        return .{ .id = id, .mutex = mutex };
    } else {
        if (current_window) |cw| {
            const parent = parentGet();
            const id = parent.extendId(src, id_extra);
            const mutex = try cw.dialogAdd(id, display);
            refresh(win, @src(), id);
            return .{ .id = id, .mutex = mutex };
        } else {
            std.debug.panic("{s}:{d} dialogAdd current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()\n", .{ src.file, src.line });
        }
    }
}

/// Only called from gui thread.
pub fn dialogRemove(id: u32) void {
    const cw = currentWindow();
    cw.dialogRemove(id);
    refresh(null, @src(), id);
}

pub const DialogOptions = struct {
    id_extra: usize = 0,
    window: ?*Window = null,
    modal: bool = true,
    title: []const u8 = "",
    message: []const u8,
    ok_label: []const u8 = "Ok",
    cancel_label: ?[]const u8 = null,
    max_size: ?Size = null,
    displayFn: DialogDisplayFn = dialogDisplay,
    callafterFn: ?DialogCallAfterFn = null,
};

/// Add a dialog to be displayed on the GUI thread during Window.end().
///
/// Can be called from any thread, but if calling from a non-GUI thread or
/// outside window.begin()/end(), you must set opts.window.
pub fn dialog(src: std.builtin.SourceLocation, opts: DialogOptions) !void {
    const id_mutex = try dialogAdd(opts.window, src, opts.id_extra, opts.displayFn);
    const id = id_mutex.id;
    dataSet(opts.window, id, "_modal", opts.modal);
    dataSetSlice(opts.window, id, "_title", opts.title);
    dataSetSlice(opts.window, id, "_message", opts.message);
    dataSetSlice(opts.window, id, "_ok_label", opts.ok_label);
    dataSet(opts.window, id, "_center_on", (opts.window orelse currentWindow()).subwindow_currentRect);
    if (opts.cancel_label) |cl| {
        dataSetSlice(opts.window, id, "_cancel_label", cl);
    }
    if (opts.max_size) |ms| {
        dataSet(opts.window, id, "_max_size", ms);
    }
    if (opts.callafterFn) |ca| {
        dataSet(opts.window, id, "_callafter", ca);
    }
    id_mutex.mutex.unlock();
}

pub fn dialogDisplay(id: u32) !void {
    const modal = dvui.dataGet(null, id, "_modal", bool) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const title = dvui.dataGetSlice(null, id, "_title", []u8) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const ok_label = dvui.dataGetSlice(null, id, "_ok_label", []u8) orelse {
        log.err("dialogDisplay lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const center_on = dvui.dataGet(null, id, "_center_on", Rect) orelse currentWindow().subwindow_currentRect;

    const cancel_label = dvui.dataGetSlice(null, id, "_cancel_label", []u8);

    const callafter = dvui.dataGet(null, id, "_callafter", DialogCallAfterFn);

    const maxSize = dvui.dataGet(null, id, "_max_size", Size);

    var win = try floatingWindow(@src(), .{ .modal = modal, .center_on = center_on, .window_avoid = .nudge }, .{ .id_extra = id, .max_size_content = maxSize });
    defer win.deinit();

    var header_openflag = true;
    try dvui.windowHeader(title, "", &header_openflag);
    if (!header_openflag) {
        dvui.dialogRemove(id);
        if (callafter) |ca| {
            try ca(id, .cancel);
        }
        return;
    }

    {
        // Add the buttons at the bottom first, so that they are guaranteed to be shown
        var hbox = try dvui.box(@src(), .horizontal, .{ .gravity_x = 0.5, .gravity_y = 1.0 });
        defer hbox.deinit();

        if (cancel_label) |cl| {
            if (try dvui.button(@src(), cl, .{}, .{ .tab_index = 2 })) {
                dvui.dialogRemove(id);
                if (callafter) |ca| {
                    try ca(id, .cancel);
                }
                return;
            }
        }

        if (try dvui.button(@src(), ok_label, .{}, .{ .tab_index = 1 })) {
            dvui.dialogRemove(id);
            if (callafter) |ca| {
                try ca(id, .ok);
            }
            return;
        }
    }

    // Now add the scroll area which will get the remaining space
    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    var tl = try dvui.textLayout(@src(), .{}, .{ .background = false, .gravity_x = 0.5 });
    try tl.addText(message, .{});
    tl.deinit();
    scroll.deinit();
}

pub const DialogNativeFileOptions = struct {
    /// Title of the dialog window
    title: ?[]const u8 = null,

    /// Starting file or directory (if ends with /)
    path: ?[]const u8 = null,

    /// Filter files shown .filters = .{"*.png", "*.jpg"}
    filters: ?[]const []const u8 = null,

    /// Description for filters given ("image files")
    filter_description: ?[]const u8 = null,
};

/// Block while showing a native file open dialog.  Return the selected file
/// path or null if cancelled.  See dialogNativeFileOpenMultiple()
///
/// Not thread safe, but can be used from any thread.
///
/// Returned string is created by passed allocator.  Not implemented for web (returns null).
pub fn dialogNativeFileOpen(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) !?[]const u8 {
    if (wasm) {
        return null;
    }

    return dialogNativeFileInternal(true, false, alloc, opts);
}

/// Block while showing a native file open dialog with multiple selection.
/// Return the selected file paths or null if cancelled.
///
/// Not thread safe, but can be used from any thread.
///
/// Returned slice and strings are created by passed allocator.  Not implemented for web (returns null).
pub fn dialogNativeFileOpenMultiple(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) !?[][]const u8 {
    if (wasm) {
        return null;
    }

    return dialogNativeFileInternal(true, true, alloc, opts);
}

/// Block while showing a native file save dialog.  Return the selected file
/// path or null if cancelled.
///
/// Not thread safe, but can be used from any thread.
///
/// Returned string is created by passed allocator.  Not implemented for web (returns null).
pub fn dialogNativeFileSave(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) !?[]const u8 {
    if (wasm) {
        return null;
    }

    return dialogNativeFileInternal(false, false, alloc, opts);
}

fn dialogNativeFileInternal(comptime open: bool, comptime multiple: bool, alloc: std.mem.Allocator, opts: DialogNativeFileOptions) if (multiple) error{OutOfMemory}!?[][]const u8 else error{OutOfMemory}!?[]const u8 {
    var backing: [500]u8 = undefined;
    var buf: []u8 = &backing;

    var title: ?[*:0]const u8 = null;
    if (opts.title) |t| {
        const dupe = std.fmt.bufPrintZ(buf, "{s}", .{t}) catch null;
        if (dupe) |dt| {
            title = dt.ptr;
            buf = buf[dt.len + 1 ..];
        }
    }

    var path: ?[*:0]const u8 = null;
    if (opts.path) |p| {
        const dupe = std.fmt.bufPrintZ(buf, "{s}", .{p}) catch null;
        if (dupe) |dp| {
            path = dp.ptr;
            buf = buf[dp.len + 1 ..];
        }
    }

    var filters_backing: [20:null]?[*:0]const u8 = undefined;
    var filters: ?[*:null]?[*:0]const u8 = null;
    var filter_count: usize = 0;
    if (opts.filters) |fs| {
        filters = &filters_backing;
        for (fs, 0..) |f, i| {
            if (i == filters_backing.len) {
                log.err("dialogNativeFileOpen got too many filters {d}, only using {d}", .{ fs.len, filters_backing.len });
                break;
            }
            const dupe = std.fmt.bufPrintZ(buf, "{s}", .{f}) catch null;
            if (dupe) |df| {
                filters.?[i] = df;
                filters.?[i + 1] = null;
                filter_count = i + 1;
                buf = buf[df.len + 1 ..];
            }
        }
    }

    var filter_desc: ?[*:0]const u8 = null;
    if (opts.filter_description) |fd| {
        const dupe = std.fmt.bufPrintZ(buf, "{s}", .{fd}) catch null;
        if (dupe) |dfd| {
            filter_desc = dfd.ptr;
            buf = buf[dfd.len + 1 ..];
        }
    }

    var result: if (multiple) ?[][]const u8 else ?[]const u8 = null;
    const tfd_ret = blk: {
        if (open) {
            break :blk dvui.c.tinyfd_openFileDialog(title, path, @intCast(filter_count), filters, filter_desc, if (multiple) 1 else 0);
        } else {
            break :blk dvui.c.tinyfd_saveFileDialog(title, path, @intCast(filter_count), filters, filter_desc);
        }
    };

    if (tfd_ret) |r| {
        if (multiple) {
            const r_slice = std.mem.sliceTo(r, 0);
            const num = std.mem.count(u8, r_slice, "|") + 1;
            result = try alloc.alloc([]const u8, num);
            var it = std.mem.splitScalar(u8, r_slice, '|');
            var i: usize = 0;
            while (it.next()) |f| {
                result.?[i] = try alloc.dupe(u8, f);
                i += 1;
            }
        } else {
            result = try alloc.dupe(u8, std.mem.sliceTo(r, 0));
        }
    }

    // TODO: tinyfd maintains malloced memory from call to call, and we should
    // figure out a way to get it to release that.

    return result;
}

pub const DialogNativeFolderSelectOptions = struct {
    /// Title of the dialog window
    title: ?[]const u8 = null,

    /// Starting file or directory (if ends with /)
    path: ?[]const u8 = null,
};

/// Block while showing a native folder select dialog. Return the selected
/// folder path or null if cancelled.
///
/// Not thread safe, but can be used from any thread.
///
/// Returned string is created by passed allocator.  Not implemented for web (returns null).
pub fn dialogNativeFolderSelect(alloc: std.mem.Allocator, opts: DialogNativeFolderSelectOptions) error{OutOfMemory}!?[]const u8 {
    if (wasm) {
        return null;
    }

    var backing: [500]u8 = undefined;
    var buf: []u8 = &backing;

    var title: ?[*:0]const u8 = null;
    if (opts.title) |t| {
        const dupe = std.fmt.bufPrintZ(buf, "{s}", .{t}) catch null;
        if (dupe) |dt| {
            title = dt.ptr;
            buf = buf[dt.len + 1 ..];
        }
    }

    var path: ?[*:0]const u8 = null;
    if (opts.path) |p| {
        const dupe = std.fmt.bufPrintZ(buf, "{s}", .{p}) catch null;
        if (dupe) |dp| {
            path = dp.ptr;
            buf = buf[dp.len + 1 ..];
        }
    }

    var result: ?[]const u8 = null;
    const tfd_ret = dvui.c.tinyfd_selectFolderDialog(title, path);
    if (tfd_ret) |r| {
        result = try alloc.dupe(u8, std.mem.sliceTo(r, 0));
    }

    // TODO: tinyfd maintains malloced memory from call to call, and we should
    // figure out a way to get it to release that.

    return result;
}

pub const Toast = struct {
    id: u32,
    subwindow_id: ?u32,
    display: DialogDisplayFn,
};

/// Add a toast.  If subwindow_id is null, the toast will be shown during
/// Window.end().  If subwindow_id is not null, separate code must call
/// toastsFor() with that subwindow_id to retrieve this toast and display it.
///
/// Returns an id and locked mutex that must be unlocked by the caller. Caller
/// does any dataSet() calls before unlocking the mutex to ensure that data is
/// available before the toast is displayed.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the toast to.
pub fn toastAdd(win: ?*Window, src: std.builtin.SourceLocation, id_extra: usize, subwindow_id: ?u32, display: DialogDisplayFn, timeout: ?i32) !IdMutex {
    if (win) |w| {
        // we are being called from non gui thread
        const id = hashSrc(src, id_extra);
        const mutex = try w.toastAdd(id, subwindow_id, display, timeout);
        refresh(win, @src(), id);
        return .{ .id = id, .mutex = mutex };
    } else {
        if (current_window) |cw| {
            const parent = parentGet();
            const id = parent.extendId(src, id_extra);
            const mutex = try cw.toastAdd(id, subwindow_id, display, timeout);
            refresh(win, @src(), id);
            return .{ .id = id, .mutex = mutex };
        } else {
            std.debug.panic("{s}:{d} toastAdd current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()", .{ src.file, src.line });
        }
    }
}

/// Only called from gui thread.
pub fn toastRemove(id: u32) void {
    const cw = currentWindow();
    cw.toastRemove(id);
    refresh(null, @src(), id);
}

pub fn toastsFor(subwindow_id: ?u32) ?ToastIterator {
    const cw = dvui.currentWindow();
    cw.dialog_mutex.lock();
    defer cw.dialog_mutex.unlock();

    for (cw.toasts.items, 0..) |*t, i| {
        if (t.subwindow_id == subwindow_id) {
            return ToastIterator.init(cw, subwindow_id, i);
        }
    }

    return null;
}

pub const ToastIterator = struct {
    const Self = @This();
    cw: *Window,
    subwindow_id: ?u32,
    i: usize,
    last_id: ?u32 = null,

    pub fn init(win: *Window, subwindow_id: ?u32, i: usize) Self {
        return Self{ .cw = win, .subwindow_id = subwindow_id, .i = i };
    }

    pub fn next(self: *Self) ?Toast {
        self.cw.dialog_mutex.lock();
        defer self.cw.dialog_mutex.unlock();

        // have to deal with toasts possibly removing themselves inbetween
        // calls to next()

        const items = self.cw.toasts.items;
        if (self.i < items.len and self.last_id != null and self.last_id.? == items[self.i].id) {
            // we already did this one, move to the next
            self.i += 1;
        }

        while (self.i < items.len and items[self.i].subwindow_id != self.subwindow_id) {
            self.i += 1;
        }

        if (self.i < items.len) {
            self.last_id = items[self.i].id;
            return items[self.i];
        }

        return null;
    }
};

pub const ToastOptions = struct {
    id_extra: usize = 0,
    window: ?*Window = null,
    subwindow_id: ?u32 = null,
    timeout: ?i32 = 5_000_000,
    message: []const u8,
    displayFn: DialogDisplayFn = toastDisplay,
};

/// Add a toast.  If opts.subwindow_id is null, the toast will be shown during
/// Window.end().  If opts.subwindow_id is not null, separate code must call
/// toastsFor() with that subwindow_id to retrieve this toast and display it.
///
/// Can be called from any thread, but if called from a non-GUI thread or
/// outside window.begin()/end(), you must set opts.window.
pub fn toast(src: std.builtin.SourceLocation, opts: ToastOptions) !void {
    const id_mutex = try dvui.toastAdd(opts.window, src, opts.id_extra, opts.subwindow_id, opts.displayFn, opts.timeout);
    const id = id_mutex.id;
    dvui.dataSetSlice(opts.window, id, "_message", opts.message);
    id_mutex.mutex.unlock();
}

pub fn toastDisplay(id: u32) !void {
    const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse {
        log.err("toastDisplay lost data for toast {x}\n", .{id});
        return;
    };

    var animator = try dvui.animate(@src(), .alpha, 500_000, .{ .id_extra = id });
    defer animator.deinit();
    try dvui.labelNoFmt(@src(), message, .{ .background = true, .corner_radius = dvui.Rect.all(1000), .padding = Rect.all(8) });

    if (dvui.timerDone(id)) {
        animator.startEnd();
    }

    if (animator.end()) {
        dvui.toastRemove(id);
    }
}

pub fn animate(src: std.builtin.SourceLocation, kind: AnimateWidget.Kind, duration_micros: i32, opts: Options) !*AnimateWidget {
    var ret = try currentWindow().arena().create(AnimateWidget);
    ret.* = AnimateWidget.init(src, kind, duration_micros, opts);
    try ret.install();
    return ret;
}

pub const DropdownWidget = struct {
    pub var defaults: Options = .{
        .color_fill = .{ .name = .fill_control },
        .margin = Rect.all(4),
        .corner_radius = Rect.all(5),
        .padding = Rect.all(6),
        .background = true,
        .name = "Dropdown",
    };

    pub const InitOptions = struct {
        label: ?[]const u8 = null,
        selected_index: ?usize = null,
    };

    options: Options = undefined,
    init_options: InitOptions = undefined,
    menu: MenuWidget = undefined,
    menuItem: MenuItemWidget = undefined,
    drop: ?FloatingMenuWidget = null,
    drop_first_frame: bool = false,
    drop_mi: ?MenuItemWidget = null,
    drop_mi_index: usize = 0,
    drop_height: f32 = 0,
    drop_adjust: f32 = undefined,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) DropdownWidget {
        var self = DropdownWidget{};
        self.options = defaults.override(opts);
        self.init_options = init_opts;
        self.menu = MenuWidget.init(src, .{ .dir = .horizontal }, self.options.wrapOuter());
        self.drop_adjust = dvui.dataGet(null, self.menu.wd.id, "_drop_adjust", f32) orelse 0;
        return self;
    }

    pub fn install(self: *DropdownWidget) !void {
        try self.menu.install();

        self.menuItem = MenuItemWidget.init(@src(), .{ .submenu = true }, self.options.wrapInner());
        try self.menuItem.install();
        self.menuItem.processEvents();
        try self.menuItem.drawBackground(.{ .focus_as_outline = true });

        if (self.init_options.label) |ll| {
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });

            var lw = try LabelWidget.initNoFmt(@src(), ll, self.options.strip().override(.{ .gravity_y = 0.5 }));
            try lw.install();
            try lw.draw();
            lw.deinit();
            _ = try spacer(@src(), .{ .w = 6 }, .{});
            try icon(@src(), "dropdown_triangle", entypo.chevron_small_down, self.options.strip().override(.{ .gravity_y = 0.5, .gravity_x = 1.0 }));

            hbox.deinit();
        }
    }

    pub fn close(self: *DropdownWidget) void {
        self.menu.close();
    }

    pub fn dropped(self: *DropdownWidget) !bool {
        if (self.drop != null) {
            // protect against calling this multiple times
            return true;
        }

        if (self.menuItem.activeRect()) |r| {
            self.drop = FloatingMenuWidget.init(@src(), r, .{ .min_size_content = r.size() });
            var drop = &self.drop.?;
            self.drop_first_frame = firstFrame(drop.wd.id);

            const s = drop.scale_val;

            // move drop up to align first item
            drop.initialRect.x -= drop.options.borderGet().x * s;
            drop.initialRect.x -= drop.options.paddingGet().x * s;
            drop.initialRect.y -= drop.options.borderGet().y * s;
            drop.initialRect.y -= drop.options.paddingGet().y * s;

            // move drop up so selected entry is aligned
            drop.initialRect.y -= self.drop_adjust * s;

            try drop.install();

            // without this, if you trigger the dropdown with the keyboard and then
            // move the mouse, the entries are highlighted but not focused
            drop.menu.submenus_activated = true;

            // only want a mouse-up to choose something if the mouse has moved in the dropup
            var eat_mouse_up = dataGet(null, drop.wd.id, "_eat_mouse_up", bool) orelse true;
            var drag_scroll = dataGet(null, drop.wd.id, "_drag_scroll", bool) orelse false;

            const drop_rs = drop.data().rectScale();
            const scroll_rs = drop.scroll.data().contentRectScale();
            const evts = events();
            for (evts) |*e| {
                if (drag_scroll and e.evt == .mouse and !e.evt.mouse.button.touch() and (e.evt.mouse.action == .motion or e.evt.mouse.action == .position)) {
                    if (e.evt.mouse.p.x >= scroll_rs.r.x and e.evt.mouse.p.x <= scroll_rs.r.x + scroll_rs.r.w and (e.evt.mouse.p.y <= scroll_rs.r.y or e.evt.mouse.p.y >= scroll_rs.r.y + scroll_rs.r.h)) {
                        if (e.evt.mouse.action == .motion) {
                            var scrolldrag = Event{ .evt = .{ .scroll_drag = .{
                                .mouse_pt = e.evt.mouse.p,
                                .screen_rect = drop.menu.data().rectScale().r,
                                .capture_id = drop.wd.id,
                            } } };
                            drop.scroll.scroll.processEvent(&scrolldrag, true);
                        } else if (e.evt.mouse.action == .position) {
                            dvui.currentWindow().inject_motion_event = true;
                        }
                    }
                }

                if (!eventMatch(e, .{ .id = drop.data().id, .r = drop_rs.r }))
                    continue;

                if (e.evt == .mouse) {
                    if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                        if (eat_mouse_up) {
                            e.handled = true;
                            eat_mouse_up = false;
                            dataSet(null, drop.wd.id, "_eat_mouse_up", eat_mouse_up);
                        }
                    } else if (e.evt.mouse.action == .motion or (e.evt.mouse.action == .press and e.evt.mouse.button.pointer())) {
                        if (eat_mouse_up) {
                            eat_mouse_up = false;
                            dataSet(null, drop.wd.id, "_eat_mouse_up", eat_mouse_up);
                        }

                        if (!drag_scroll) {
                            drag_scroll = true;
                            dataSet(null, drop.wd.id, "_drag_scroll", drag_scroll);
                        }
                    }
                }
            }
        }

        if (self.drop != null) {
            return true;
        }

        return false;
    }

    pub fn addChoiceLabel(self: *DropdownWidget, label_text: []const u8) !bool {
        var mi = try self.addChoice();
        defer mi.deinit();

        var opts = self.options.strip();
        if (mi.show_active) {
            opts = opts.override(dvui.themeGet().style_accent);
        }

        try labelNoFmt(@src(), label_text, opts);

        if (mi.activeRect()) |_| {
            self.close();
            return true;
        }

        return false;
    }

    pub fn addChoice(self: *DropdownWidget) !*MenuItemWidget {
        // record how far down in our parent we would be
        if (self.drop_mi) |*mi| {
            self.drop_height += mi.data().min_size.h;
        }

        self.drop_mi = MenuItemWidget.init(@src(), .{}, .{ .id_extra = self.drop_mi_index, .expand = .horizontal });
        try self.drop_mi.?.install();
        self.drop_mi.?.processEvents();
        try self.drop_mi.?.drawBackground(.{});

        if (self.drop_first_frame) {
            if (self.init_options.selected_index) |si| {
                if (si == self.drop_mi_index) {
                    focusWidget(self.drop_mi.?.wd.id, null, null);
                    dvui.dataSet(null, self.menu.wd.id, "_drop_adjust", self.drop_height);
                }
            }
        }
        self.drop_mi_index += 1;

        return &self.drop_mi.?;
    }

    pub fn deinit(self: *DropdownWidget) void {
        if (self.drop != null) {
            self.drop.?.deinit();
            self.drop = null;
        }
        self.menuItem.deinit();
        self.menu.deinit();
    }
};

pub fn dropdown(src: std.builtin.SourceLocation, entries: []const []const u8, choice: *usize, opts: Options) !bool {
    var dd = dvui.DropdownWidget.init(src, .{ .selected_index = choice.*, .label = entries[choice.*] }, opts);
    try dd.install();

    var ret = false;
    if (try dd.dropped()) {
        for (entries, 0..) |e, i| {
            if (try dd.addChoiceLabel(e)) {
                choice.* = i;
                ret = true;
            }
        }
    }

    dd.deinit();
    return ret;
}

pub const TabsWidget = struct {
    pub var defaults: Options = .{
        .background = false,
        .corner_radius = Rect{},
        .name = "Tabs",
    };

    pub const InitOptions = struct {
        dir: enums.Direction = .horizontal,
    };

    options: Options = undefined,
    init_options: InitOptions = undefined,
    scroll: ScrollAreaWidget = undefined,
    box: BoxWidget = undefined,
    tab_index: usize = 0,
    tab_button: ButtonWidget = undefined,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) TabsWidget {
        var self = TabsWidget{};
        self.options = defaults.override(opts);
        self.init_options = init_opts;
        var scroll_opts: ScrollAreaWidget.InitOpts = .{};
        switch (self.init_options.dir) {
            .horizontal => scroll_opts = .{ .vertical = .none, .horizontal = .auto, .horizontal_bar = .hide },
            .vertical => scroll_opts = .{ .vertical = .auto, .vertical_bar = .hide },
        }
        self.scroll = ScrollAreaWidget.init(src, scroll_opts, self.options.override(.{ .debug = true }));
        return self;
    }

    pub fn install(self: *TabsWidget) !void {
        try self.scroll.install();

        const margin: Rect = switch (self.init_options.dir) {
            .horizontal => .{ .y = 2 },
            .vertical => .{ .x = 2 },
        };
        self.box = BoxWidget.init(@src(), self.init_options.dir, false, .{ .margin = margin });
        try self.box.install();

        var r = self.scroll.data().contentRectScale().r;
        switch (self.init_options.dir) {
            .horizontal => {
                if (dvui.currentWindow().snap_to_pixels) {
                    r.x += 0.5;
                    r.w -= 1.0;
                    r.y = @floor(r.y) - 0.5;
                }
                try dvui.pathAddPoint(r.bottomLeft());
                try dvui.pathAddPoint(r.bottomRight());
                try dvui.pathStroke(false, 1, .none, dvui.themeGet().color_border);
            },
            .vertical => {
                if (dvui.currentWindow().snap_to_pixels) {
                    r.y += 0.5;
                    r.h -= 1.0;
                    r.x = @floor(r.x) - 0.5;
                }
                try dvui.pathAddPoint(r.topRight());
                try dvui.pathAddPoint(r.bottomRight());
                try dvui.pathStroke(false, 1, .none, dvui.themeGet().color_border);
            },
        }
    }

    pub fn addTabLabel(self: *TabsWidget, selected: bool, text: []const u8) !bool {
        var tab = try self.addTab(selected, .{});
        defer tab.deinit();

        var label_opts = tab.data().options.strip();
        if (dvui.captured(tab.data().id)) {
            label_opts.color_text = .{ .name = .text_press };
        }

        try dvui.labelNoFmt(@src(), text, label_opts);

        return tab.clicked();
    }

    pub fn addTab(self: *TabsWidget, selected: bool, opts: Options) !*ButtonWidget {
        var tab_defaults: Options = switch (self.init_options.dir) {
            .horizontal => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .y = 5 }, .margin = .{ .x = 2, .w = 2 } },
            .vertical => .{ .id_extra = self.tab_index, .background = true, .corner_radius = .{ .x = 5, .h = 5 }, .margin = .{ .y = 2, .h = 2 } },
        };

        self.tab_index += 1;

        if (selected) {
            tab_defaults.font_style = .heading;
            tab_defaults.color_fill = .{ .name = .fill_window };
            tab_defaults.border = switch (self.init_options.dir) {
                .horizontal => .{ .x = 1, .y = 1, .w = 1 },
                .vertical => .{ .x = 1, .y = 1, .h = 1 },
            };
        } else {
            tab_defaults.color_fill = .{ .name = .fill_control };
            switch (self.init_options.dir) {
                .horizontal => tab_defaults.margin.?.h = 1,
                .vertical => tab_defaults.margin.?.w = 1,
            }
        }

        switch (self.init_options.dir) {
            .horizontal => tab_defaults.gravity_y = 1.0,
            .vertical => tab_defaults.gravity_x = 1.0,
        }

        const options = tab_defaults.override(opts);

        self.tab_button = ButtonWidget.init(@src(), .{}, options);
        try self.tab_button.install();
        self.tab_button.processEvents();
        try self.tab_button.drawBackground();

        if (self.tab_button.focused() and self.tab_button.data().visible()) {
            const rs = self.tab_button.data().borderRectScale();
            const cr = self.tab_button.data().options.corner_radiusGet();

            switch (self.init_options.dir) {
                .horizontal => {
                    try dvui.pathAddPoint(rs.r.bottomRight());

                    const tr = Point{ .x = rs.r.x + rs.r.w - cr.y, .y = rs.r.y + cr.y };
                    try dvui.pathAddArc(tr, cr.y, math.pi * 2.0, math.pi * 1.5, false);

                    const tl = Point{ .x = rs.r.x + cr.x, .y = rs.r.y + cr.x };
                    try dvui.pathAddArc(tl, cr.x, math.pi * 1.5, math.pi, false);

                    try dvui.pathAddPoint(rs.r.bottomLeft());

                    try dvui.pathStrokeAfter(true, false, 2 * rs.s, .none, self.options.color(.accent));
                },
                .vertical => {
                    try dvui.pathAddPoint(rs.r.topRight());

                    const tl = Point{ .x = rs.r.x + cr.x, .y = rs.r.y + cr.x };
                    try dvui.pathAddArc(tl, cr.x, math.pi * 1.5, math.pi, false);

                    const bl = Point{ .x = rs.r.x + cr.h, .y = rs.r.y + rs.r.h - cr.h };
                    try dvui.pathAddArc(bl, cr.h, math.pi, math.pi * 0.5, false);

                    try dvui.pathAddPoint(rs.r.bottomRight());

                    try dvui.pathStrokeAfter(true, false, 2 * rs.s, .none, self.options.color(.accent));
                },
            }
        }

        return &self.tab_button;
    }

    pub fn deinit(self: *TabsWidget) void {
        self.box.deinit();
        self.scroll.deinit();
    }
};

pub var expander_defaults: Options = .{
    .padding = Rect.all(4),
    .font_style = .heading,
};

pub const ExpanderOptions = struct {
    default_expanded: bool = false,
};

pub fn expander(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: ExpanderOptions, opts: Options) !bool {
    const options = expander_defaults.override(opts);

    // Use the ButtonWidget to do margin/border/padding, but use strip so we
    // don't get any of ButtonWidget's defaults
    var bc = ButtonWidget.init(src, .{}, options.strip().override(options));
    try bc.install();
    bc.processEvents();
    try bc.drawBackground();
    try bc.drawFocus();
    defer bc.deinit();

    var expanded: bool = init_opts.default_expanded;
    if (dvui.dataGet(null, bc.wd.id, "_expand", bool)) |e| {
        expanded = e;
    }

    if (bc.clicked()) {
        expanded = !expanded;
    }

    var bcbox = BoxWidget.init(@src(), .horizontal, false, options.strip());
    defer bcbox.deinit();
    try bcbox.install();
    try bcbox.drawBackground();
    const size = options.fontGet().textHeight();
    if (expanded) {
        try icon(@src(), "down_arrow", entypo.triangle_down, .{ .gravity_y = 0.5, .min_size_content = .{ .h = size } });
    } else {
        try icon(@src(), "right_arrow", entypo.triangle_right, .{ .gravity_y = 0.5, .min_size_content = .{ .h = size } });
    }
    try labelNoFmt(@src(), label_str, options.strip());

    dvui.dataSet(null, bc.wd.id, "_expand", expanded);

    return expanded;
}

pub fn paned(src: std.builtin.SourceLocation, init_opts: PanedWidget.InitOptions, opts: Options) !*PanedWidget {
    var ret = try currentWindow().arena().create(PanedWidget);
    ret.* = PanedWidget.init(src, init_opts, opts);
    try ret.install();
    ret.processEvents();
    try ret.draw();
    return ret;
}

pub fn textLayout(src: std.builtin.SourceLocation, init_opts: TextLayoutWidget.InitOptions, opts: Options) !*TextLayoutWidget {
    const cw = currentWindow();
    var ret = try cw.arena().create(TextLayoutWidget);
    ret.* = TextLayoutWidget.init(src, init_opts, opts);
    try ret.install(.{});

    // can install corner widgets here
    //_ = try dvui.button(@src(), "upright", .{}, .{ .gravity_x = 1.0 });

    if (try ret.touchEditing()) |floating_widget| {
        defer floating_widget.deinit();
        try ret.touchEditingMenu();
    }

    ret.processEvents();

    // call addText() any number of times

    // can call addTextDone() (will be called automatically if you don't)
    return ret;
}

/// Context menu.  Pass a screen space pixel rect in init_opts, then
/// .activePoint() says whether to show a menu.
///
/// The menu code should happen before deinit(), but don't put regular widgets
/// directly inside Context.
///
/// Only valid between dvui.Window.begin() and end().
pub fn context(src: std.builtin.SourceLocation, init_opts: ContextWidget.InitOptions, opts: Options) !*ContextWidget {
    var ret = try currentWindow().arena().create(ContextWidget);
    ret.* = ContextWidget.init(src, init_opts, opts);
    try ret.install();
    ret.processEvents();
    return ret;
}

pub fn virtualParent(src: std.builtin.SourceLocation, opts: Options) !*VirtualParentWidget {
    var ret = try currentWindow().arena().create(VirtualParentWidget);
    ret.* = VirtualParentWidget.init(src, opts);
    try ret.install();
    return ret;
}

pub fn overlay(src: std.builtin.SourceLocation, opts: Options) !*OverlayWidget {
    var ret = try currentWindow().arena().create(OverlayWidget);
    ret.* = OverlayWidget.init(src, opts);
    try ret.install();
    return ret;
}

pub fn box(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) !*BoxWidget {
    var ret = try currentWindow().arena().create(BoxWidget);
    ret.* = BoxWidget.init(src, dir, false, opts);
    try ret.install();
    try ret.drawBackground();
    return ret;
}

pub fn boxEqual(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) !*BoxWidget {
    var ret = try currentWindow().arena().create(BoxWidget);
    ret.* = BoxWidget.init(src, dir, true, opts);
    try ret.install();
    try ret.drawBackground();
    return ret;
}

pub fn flexbox(src: std.builtin.SourceLocation, init_opts: FlexBoxWidget.InitOptions, opts: Options) !*FlexBoxWidget {
    var ret = try currentWindow().arena().create(FlexBoxWidget);
    ret.* = FlexBoxWidget.init(src, init_opts, opts);
    try ret.install();
    try ret.drawBackground();
    return ret;
}

pub fn cache(src: std.builtin.SourceLocation, init_opts: CacheWidget.InitOptions, opts: Options) !*CacheWidget {
    var ret = try currentWindow().arena().create(CacheWidget);
    ret.* = CacheWidget.init(src, init_opts, opts);
    if (init_opts.invalidate) {
        try ret.invalidate();
    }
    try ret.install();
    return ret;
}

pub fn reorder(src: std.builtin.SourceLocation, opts: Options) !*ReorderWidget {
    var ret = try currentWindow().arena().create(ReorderWidget);
    ret.* = ReorderWidget.init(src, opts);
    try ret.install();
    ret.processEvents();
    return ret;
}

pub fn scrollArea(src: std.builtin.SourceLocation, init_opts: ScrollAreaWidget.InitOpts, opts: Options) !*ScrollAreaWidget {
    var ret = try currentWindow().arena().create(ScrollAreaWidget);
    ret.* = ScrollAreaWidget.init(src, init_opts, opts);
    try ret.install();
    return ret;
}

pub fn separator(src: std.builtin.SourceLocation, opts: Options) !void {
    const defaults: Options = .{
        .name = "Separator",
        .background = true, // TODO: remove this when border and background are no longer coupled
        .color_fill = .{ .name = .border },
        .min_size_content = .{ .w = 1, .h = 1 },
    };

    var wd = WidgetData.init(src, .{}, defaults.override(opts));
    try wd.register();
    try wd.borderAndBackground(.{});
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
}

pub fn spacer(src: std.builtin.SourceLocation, size: Size, opts: Options) !WidgetData {
    if (opts.min_size_content != null) {
        log.debug("spacer options had min_size but is being overwritten\n", .{});
    }
    const defaults: Options = .{ .name = "Spacer" };
    var wd = WidgetData.init(src, .{}, defaults.override(opts).override(.{ .min_size_content = size }));
    try wd.register();
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
    return wd;
}

pub fn spinner(src: std.builtin.SourceLocation, opts: Options) !void {
    var defaults: Options = .{
        .name = "Spinner",
        .min_size_content = .{ .w = 50, .h = 50 },
    };
    const options = defaults.override(opts);
    var wd = WidgetData.init(src, .{}, options);
    try wd.register();
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    if (wd.rect.empty()) {
        return;
    }

    const rs = wd.contentRectScale();
    const r = rs.r;

    var angle: f32 = 0;
    const anim = Animation{ .start_val = 0, .end_val = 2 * math.pi, .end_time = 4_500_000 };
    if (animationGet(wd.id, "_angle")) |a| {
        // existing animation
        var aa = a;
        if (aa.done()) {
            // this animation is expired, seemlessly transition to next animation
            aa = anim;
            aa.start_time = a.end_time;
            aa.end_time += a.end_time;
            animation(wd.id, "_angle", aa);
        }
        angle = aa.lerp();
    } else {
        // first frame we are seeing the spinner
        animation(wd.id, "_angle", anim);
    }

    const center = Point{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
    try pathAddArc(center, @min(r.w, r.h) / 3, angle, 0, false);
    try pathStroke(false, 3.0 * rs.s, .none, options.color(.text));
}

pub fn scale(src: std.builtin.SourceLocation, scale_in: f32, opts: Options) !*ScaleWidget {
    var ret = try currentWindow().arena().create(ScaleWidget);
    ret.* = ScaleWidget.init(src, scale_in, opts);
    try ret.install();
    return ret;
}

pub fn menu(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) !*MenuWidget {
    var ret = try currentWindow().arena().create(MenuWidget);
    ret.* = MenuWidget.init(src, .{ .dir = dir }, opts);
    try ret.install();
    return ret;
}

pub fn menuItemLabel(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) !?Rect {
    var mi = try menuItem(src, init_opts, opts);

    var labelopts = opts.strip();

    var ret: ?Rect = null;
    if (mi.activeRect()) |r| {
        ret = r;
    }

    if (mi.show_active) {
        labelopts = labelopts.override(themeGet().style_accent);
    }

    try labelNoFmt(@src(), label_str, labelopts);

    mi.deinit();

    return ret;
}

pub fn menuItemIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) !?Rect {
    var mi = try menuItem(src, init_opts, opts);

    // pass min_size_content through to the icon so that it will figure out the
    // min width based on the height
    var iconopts = opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = opts.min_size_content });

    var ret: ?Rect = null;
    if (mi.activeRect()) |r| {
        ret = r;
    }

    if (mi.show_active) {
        iconopts = iconopts.override(themeGet().style_accent);
    }

    try icon(@src(), name, tvg_bytes, iconopts);

    mi.deinit();

    return ret;
}

pub fn menuItem(src: std.builtin.SourceLocation, init_opts: MenuItemWidget.InitOptions, opts: Options) !*MenuItemWidget {
    var ret = try currentWindow().arena().create(MenuItemWidget);
    ret.* = MenuItemWidget.init(src, init_opts, opts);
    try ret.install();
    ret.processEvents();
    try ret.drawBackground(.{});
    return ret;
}

/// A clickable label.  Good for hyperlinks.
/// Returns true if it's been clicked.
pub fn labelClick(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) !bool {
    var ret = false;

    var lw = try LabelWidget.init(src, fmt, args, opts.override(.{ .name = "LabelClick" }));
    // now lw has a Rect from its parent but hasn't processed events or drawn

    const lwid = lw.data().id;

    // if lw is visible, we want to be able to keyboard navigate to it
    if (lw.data().visible()) {
        try dvui.tabIndexSet(lwid, lw.data().options.tab_index);
    }

    // draw border and background
    try lw.install();

    // loop over all events this frame in order of arrival
    for (dvui.events()) |*e| {

        // skip if lw would not normally process this event
        if (!lw.matchEvent(e))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handled = true;

                    // focus this widget for events after this one (starting with e.num)
                    dvui.focusWidget(lwid, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    e.handled = true;
                    dvui.captureMouse(lwid);

                    // for touch events, we want to cancel our click if a drag is started
                    dvui.dragPreStart(me.p, .{});
                } else if (me.action == .release and me.button.pointer()) {
                    // mouse button was released, do we still have mouse capture?
                    if (dvui.captured(lwid)) {
                        e.handled = true;

                        // cancel our capture
                        dvui.captureMouse(null);
                        dvui.dragEnd();

                        // if the release was within our border, the click is successful
                        if (lw.data().borderRectScale().r.contains(me.p)) {
                            ret = true;

                            // if the user interacts successfully with a
                            // widget, it usually means part of the GUI is
                            // changing, so the convention is to call refresh
                            // so the user doesn't have to remember
                            dvui.refresh(null, @src(), lwid);
                        }
                    }
                } else if (me.action == .motion and me.button.touch()) {
                    if (dvui.captured(lwid)) {
                        if (dvui.dragging(me.p)) |_| {
                            // touch: if we overcame the drag threshold, then
                            // that means the person probably didn't want to
                            // touch this button, they were trying to scroll
                            dvui.captureMouse(null);
                            dvui.dragEnd();
                        }
                    }
                } else if (me.action == .position) {
                    e.handled = true;

                    // a single .position mouse event is at the end of each
                    // frame, so this means the mouse ended above us
                    dvui.cursorSet(.hand);
                }
            },
            .key => |ke| {
                if (ke.action == .down and ke.matchBind("activate")) {
                    e.handled = true;
                    ret = true;
                    dvui.refresh(null, @src(), lwid);
                }
            },
            else => {},
        }

        // if we didn't handle this event, send it to lw - this means we don't
        // need to call lw.processEvents()
        if (!e.handled) {
            lw.processEvent(e, false);
        }
    }

    // draw text
    try lw.draw();

    // draw an accent border if we are focused
    if (lwid == dvui.focusedWidgetId()) {
        try lw.data().focusBorder();
    }

    // done with lw, have it report min size to parent
    lw.deinit();

    return ret;
}

pub fn label(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) !void {
    var lw = try LabelWidget.init(src, fmt, args, opts);
    try lw.install();
    lw.processEvents();
    try lw.draw();
    lw.deinit();
}

pub fn labelNoFmt(src: std.builtin.SourceLocation, str: []const u8, opts: Options) !void {
    var lw = try LabelWidget.initNoFmt(src, str, opts);
    try lw.install();
    lw.processEvents();
    try lw.draw();
    lw.deinit();
}

pub fn icon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, opts: Options) !void {
    var iw = try IconWidget.init(src, name, tvg_bytes, opts);
    try iw.install();
    try iw.draw();
    iw.deinit();
}

pub fn imageSize(name: []const u8, image_bytes: []const u8) !Size {
    var w: c_int = undefined;
    var h: c_int = undefined;
    var n: c_int = undefined;
    const ok = c.stbi_info_from_memory(image_bytes.ptr, @as(c_int, @intCast(image_bytes.len)), &w, &h, &n);
    if (ok == 1) {
        return .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
    } else {
        log.warn("imageSize stbi_info error on image \"{s}\": {s}\n", .{ name, c.stbi_failure_reason() });
        return Error.stbiError;
    }
}

pub fn image(src: std.builtin.SourceLocation, name: []const u8, image_bytes: []const u8, opts: Options) !void {
    var iw = try ImageWidget.init(src, name, image_bytes, opts);
    try iw.install();
    try iw.draw();
    iw.deinit();
}

pub fn debugFontAtlases(src: std.builtin.SourceLocation, opts: Options) !void {
    const cw = currentWindow();

    var size = Size{};
    var it = cw.font_cache.iterator();
    while (it.next()) |kv| {
        size.w = @max(size.w, kv.value_ptr.texture_atlas_size.w);
        size.h += kv.value_ptr.texture_atlas_size.h;
    }

    // this size is a pixel size, so inverse scale to get natural pixels
    const ss = parentGet().screenRectScale(Rect{}).s;
    size = size.scale(1.0 / ss);

    var wd = WidgetData.init(src, .{}, opts.override(.{ .name = "debugFontAtlases", .min_size_content = size }));
    try wd.register();

    try wd.borderAndBackground(.{});

    const rs = wd.parent.screenRectScale(placeIn(wd.contentRect(), size, .none, opts.gravityGet()));
    try debugRenderFontAtlases(rs, opts.color(.text));

    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
}

pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) !bool {
    // initialize widget and get rectangle from parent
    var bw = ButtonWidget.init(src, init_opts, opts);

    // make ourselves the new parent
    try bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();

    // draw background/border
    try bw.drawBackground();

    // use pressed text color if desired
    const click = bw.clicked();
    var options = opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 });

    if (bw.pressed()) options = options.override(.{ .color_text = .{ .color = opts.color(.text_press) } });

    // this child widget:
    // - has bw as parent
    // - gets a rectangle from bw
    // - draws itself
    // - reports its min size to bw
    try labelNoFmt(@src(), label_str, options);

    // draw focus
    try bw.drawFocus();

    // restore previous parent
    // send our min size to parent
    bw.deinit();

    return click;
}

pub fn buttonIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) !bool {
    const defaults = Options{ .padding = Rect.all(4) };
    var bw = ButtonWidget.init(src, init_opts, defaults.override(opts));
    try bw.install();
    bw.processEvents();
    try bw.drawBackground();

    // When someone passes min_size_content to buttonIcon, they want the icon
    // to be that size, so we pass it through.
    try icon(@src(), name, tvg_bytes, opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = opts.min_size_content, .expand = .ratio }));

    const click = bw.clicked();
    try bw.drawFocus();
    bw.deinit();
    return click;
}

pub var slider_defaults: Options = .{
    .padding = Rect.all(2),
    .min_size_content = .{ .w = 20, .h = 20 },
    .color_fill = .{ .name = .fill_control },
};

// returns true if fraction (0-1) was changed
pub fn slider(src: std.builtin.SourceLocation, dir: enums.Direction, fraction: *f32, opts: Options) !bool {
    std.debug.assert(fraction.* >= 0);
    std.debug.assert(fraction.* <= 1);

    const options = slider_defaults.override(opts);

    var b = try box(src, dir, options);
    defer b.deinit();

    if (b.data().visible()) {
        try tabIndexSet(b.data().id, options.tab_index);
    }

    var hovered: bool = false;
    var ret = false;

    const br = b.data().contentRect();
    const knobsize = @min(br.w, br.h);
    const track = switch (dir) {
        .horizontal => Rect{ .x = knobsize / 2, .y = br.h / 2 - 2, .w = br.w - knobsize, .h = 4 },
        .vertical => Rect{ .x = br.w / 2 - 2, .y = knobsize / 2, .w = 4, .h = br.h - knobsize },
    };

    const trackrs = b.widget().screenRectScale(track);

    const rs = b.data().contentRectScale();
    const evts = events();
    for (evts) |*e| {
        if (!eventMatch(e, .{ .id = b.data().id, .r = rs.r }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                var p: ?Point = null;
                if (me.action == .focus) {
                    e.handled = true;
                    focusWidget(b.data().id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    // capture
                    captureMouse(b.data().id);
                    e.handled = true;
                    p = me.p;
                } else if (me.action == .release and me.button.pointer()) {
                    // stop capture
                    captureMouse(null);
                    dragEnd();
                    e.handled = true;
                } else if (me.action == .motion and captured(b.data().id)) {
                    // handle only if we have capture
                    e.handled = true;
                    p = me.p;
                } else if (me.action == .position) {
                    e.handled = true;
                    hovered = true;
                }

                if (p) |pp| {
                    var min: f32 = undefined;
                    var max: f32 = undefined;
                    switch (dir) {
                        .horizontal => {
                            min = trackrs.r.x;
                            max = trackrs.r.x + trackrs.r.w;
                        },
                        .vertical => {
                            min = 0;
                            max = trackrs.r.h;
                        },
                    }

                    if (max > min) {
                        const v = if (dir == .horizontal) pp.x else (trackrs.r.y + trackrs.r.h - pp.y);
                        fraction.* = (v - min) / (max - min);
                        fraction.* = @max(0, @min(1, fraction.*));
                        ret = true;
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .left, .down => {
                            e.handled = true;
                            fraction.* = @max(0, @min(1, fraction.* - 0.05));
                            ret = true;
                        },
                        .right, .up => {
                            e.handled = true;
                            fraction.* = @max(0, @min(1, fraction.* + 0.05));
                            ret = true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    const perc = @max(0, @min(1, fraction.*));

    var part = trackrs.r;
    switch (dir) {
        .horizontal => part.w *= perc,
        .vertical => {
            const h = part.h * (1 - perc);
            part.y += h;
            part.h = trackrs.r.h - h;
        },
    }
    if (b.data().visible()) {
        try pathAddRect(part, options.corner_radiusGet().scale(trackrs.s));
        try pathFillConvex(options.color(.accent));
    }

    switch (dir) {
        .horizontal => {
            part.x = part.x + part.w;
            part.w = trackrs.r.w - part.w;
        },
        .vertical => {
            part = trackrs.r;
            part.h *= (1 - perc);
        },
    }
    if (b.data().visible()) {
        try pathAddRect(part, options.corner_radiusGet().scale(trackrs.s));
        try pathFillConvex(options.color(.fill));
    }

    const knobRect = switch (dir) {
        .horizontal => Rect{ .x = (br.w - knobsize) * perc, .w = knobsize, .h = knobsize },
        .vertical => Rect{ .y = (br.h - knobsize) * (1 - perc), .w = knobsize, .h = knobsize },
    };

    var fill_color: Color = undefined;
    if (captured(b.data().id)) {
        fill_color = options.color(.fill_press);
    } else if (hovered) {
        fill_color = options.color(.fill_hover);
    } else {
        fill_color = options.color(.fill);
    }
    var knob = BoxWidget.init(@src(), .horizontal, false, .{ .rect = knobRect, .padding = .{}, .margin = .{}, .background = true, .border = Rect.all(1), .corner_radius = Rect.all(100), .color_fill = .{ .color = fill_color } });
    try knob.install();
    try knob.drawBackground();
    if (b.data().id == focusedWidgetId()) {
        try knob.wd.focusBorder();
    }
    knob.deinit();

    if (ret) {
        refresh(null, @src(), b.data().id);
    }

    return ret;
}

pub var slider_entry_defaults: Options = .{
    .margin = Rect.all(4),
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(2),
    .color_fill = .{ .name = .fill_control },
    .background = true,
    // min size calulated from font
};

pub const SliderEntryInitOptions = struct {
    value: *f32,
    min: ?f32 = null,
    max: ?f32 = null,
    interval: ?f32 = null,
};

/// Combines a slider and a text entry box on key press.  Displays value on top of slider.
///
/// Returns true if value was changed.
pub fn sliderEntry(src: std.builtin.SourceLocation, comptime label_fmt: ?[]const u8, init_opts: SliderEntryInitOptions, opts: Options) !bool {

    // This widget swaps between either a slider with a label or a text entry.
    // The tricky part of this is maintaining focus.  Strategy is a containing
    // box that will keep focus, and forward events to the text entry.
    //
    // We are keeping this simple by only swapping between slider and textEntry
    // on a frame boundary.

    const exp_min_change = 0.1;
    const exp_stretch = 0.02;
    const key_percentage = 0.05;

    var options = slider_entry_defaults.min_sizeM(10, 1).override(opts);

    var ret = false;
    var hover = false;
    var b = BoxWidget.init(src, .horizontal, false, options);
    try b.install();
    defer b.deinit();

    if (b.data().visible()) {
        try tabIndexSet(b.data().id, options.tab_index);
    }

    const br = b.data().contentRect();
    const knobsize = @min(br.w, br.h);
    const rs = b.data().contentRectScale();

    var text_mode = dataGet(null, b.data().id, "_text_mode", bool) orelse false;
    var ctrl_down = dataGet(null, b.data().id, "_ctrl", bool) orelse false;

    // must call dataGet/dataSet on these every frame to prevent them from
    // getting purged
    _ = dataGet(null, b.data().id, "_start_x", f32);
    _ = dataGet(null, b.data().id, "_start_v", f32);

    if (text_mode) {
        var te_buf = dataGetSlice(null, b.data().id, "_buf", []u8) orelse blk: {
            var buf = [_]u8{0} ** 20;
            _ = std.fmt.bufPrintZ(&buf, "{d:0.3}", .{init_opts.value.*}) catch {};
            dataSetSlice(null, b.data().id, "_buf", &buf);
            break :blk dataGetSlice(null, b.data().id, "_buf", []u8).?;
        };

        // pass 0 for tab_index so you can't tab to TextEntry
        var te = TextEntryWidget.init(@src(), .{ .text = .{ .buffer = te_buf } }, options.strip().override(.{ .min_size_content = .{}, .expand = .both, .tab_index = 0 }));
        try te.install();

        if (firstFrame(te.wd.id)) {
            var sel = te.textLayout.selection;
            sel.start = 0;
            sel.cursor = 0;
            sel.end = std.math.maxInt(usize);
        }

        var new_val: ?f32 = null;

        const evts = events();
        for (evts) |*e| {
            if (e.evt == .key and e.evt.key.matchBind("ctrl/cmd")) {
                ctrl_down = (e.evt.key.action == .down or e.evt.key.action == .repeat);
            }

            if (!text_mode) {
                // if we are switching out of text mode, skip processing any
                // remaining events
                continue;
            }

            // te.matchEvent could be passively listening to events, so don't
            // short-circuit it
            const match1 = eventMatch(e, .{ .id = b.data().id, .r = rs.r });
            const match2 = te.matchEvent(e);

            if (!match1 and !match2)
                continue;

            if (e.evt == .key and e.evt.key.action == .down and e.evt.key.code == .enter) {
                e.handled = true;
                text_mode = false;
                new_val = std.fmt.parseFloat(f32, te_buf[0..te.len]) catch null;
            }

            if (e.evt == .key and e.evt.key.action == .down and e.evt.key.code == .escape) {
                e.handled = true;
                text_mode = false;
                // don't set new_val, we are escaping
            }

            // don't want TextEntry to get focus
            if (e.evt == .mouse and e.evt.mouse.action == .focus) {
                e.handled = true;
                focusWidget(b.data().id, null, e.num);
            }

            if (!e.handled) {
                te.processEvent(e, false);
            }
        }

        if (b.data().id == focusedWidgetId()) {
            dvui.wantTextInput(b.data().borderRectScale().r);
        } else {

            // we lost focus
            text_mode = false;
            new_val = std.fmt.parseFloat(f32, te_buf[0..te.len]) catch null;
        }

        if (!text_mode) {
            refresh(null, @src(), b.data().id);

            if (new_val) |nv| {
                init_opts.value.* = nv;
                ret = true;
            }
        }

        try te.draw();
        try te.drawCursor();
        te.deinit();
    } else {

        // show slider and label
        const trackrs = b.widget().screenRectScale(.{ .x = knobsize / 2, .w = br.w - knobsize });
        const min_x = trackrs.r.x;
        const max_x = trackrs.r.x + trackrs.r.w;
        const px_scale = trackrs.s;

        const evts = events();
        for (evts) |*e| {
            if (e.evt == .key and e.evt.key.matchBind("ctrl/cmd")) {
                ctrl_down = (e.evt.key.action == .down or e.evt.key.action == .repeat);
            }

            if (!eventMatch(e, .{ .id = b.data().id, .r = rs.r }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    var p: ?Point = null;
                    if (me.action == .focus) {
                        e.handled = true;
                        focusWidget(b.data().id, null, e.num);
                    } else if (me.action == .press and me.button.pointer()) {
                        e.handled = true;
                        if (ctrl_down) {
                            text_mode = true;
                        } else {
                            captureMouse(b.data().id);
                            p = me.p;
                            dataSet(null, b.data().id, "_start_x", me.p.x);
                            dataSet(null, b.data().id, "_start_v", init_opts.value.*);
                        }
                    } else if (me.action == .release and me.button.pointer()) {
                        e.handled = true;
                        captureMouse(null);
                        dragEnd();
                        dataRemove(null, b.data().id, "_start_x");
                        dataRemove(null, b.data().id, "_start_v");
                    } else if (me.action == .motion and captured(b.data().id)) {
                        e.handled = true;
                        p = me.p;
                    } else if (me.action == .position) {
                        e.handled = true;
                        hover = true;
                    }

                    if (p) |pp| {
                        if (max_x > min_x) {
                            ret = true;
                            if (init_opts.min != null and init_opts.max != null) {
                                // lerp but make sure we can hit the max
                                if (pp.x > max_x) {
                                    init_opts.value.* = init_opts.max.?;
                                } else {
                                    const px_lerp = @max(0, @min(1, (pp.x - min_x) / (max_x - min_x)));
                                    init_opts.value.* = init_opts.min.? + px_lerp * (init_opts.max.? - init_opts.min.?);
                                    if (init_opts.interval) |ival| {
                                        init_opts.value.* = init_opts.min.? + ival * @round((init_opts.value.* - init_opts.min.?) / ival);
                                    }
                                }
                            } else if (init_opts.min != null) {
                                // only have min, go exponentially to the right
                                if (pp.x < min_x) {
                                    init_opts.value.* = init_opts.min.?;
                                } else {
                                    const base = if (init_opts.min.? == 0) exp_min_change else @exp(math.ln10 * @floor(@log10(@abs(init_opts.min.?)))) * exp_min_change;
                                    const how_far = @max(0, (pp.x - min_x)) / px_scale;
                                    const how_much = (@exp(how_far * exp_stretch) - 1) * base;
                                    init_opts.value.* = init_opts.min.? + how_much;
                                    if (init_opts.interval) |ival| {
                                        init_opts.value.* = init_opts.min.? + ival * @round((init_opts.value.* - init_opts.min.?) / ival);
                                    }
                                }
                            } else if (init_opts.max != null) {
                                // only have max, go exponentially to the left
                                if (pp.x > max_x) {
                                    init_opts.value.* = init_opts.max.?;
                                } else {
                                    const base = if (init_opts.max.? == 0) exp_min_change else @exp(math.ln10 * @floor(@log10(@abs(init_opts.max.?)))) * exp_min_change;
                                    const how_far = @max(0, (max_x - pp.x)) / px_scale;
                                    const how_much = (@exp(how_far * exp_stretch) - 1) * base;
                                    init_opts.value.* = init_opts.max.? - how_much;
                                    if (init_opts.interval) |ival| {
                                        init_opts.value.* = init_opts.max.? - ival * @round((init_opts.max.? - init_opts.value.*) / ival);
                                    }
                                }
                            } else {
                                // neither min nor max, go exponentially away from starting value
                                if (dataGet(null, b.data().id, "_start_x", f32)) |start_x| {
                                    if (dataGet(null, b.data().id, "_start_v", f32)) |start_v| {
                                        const base = if (start_v == 0) exp_min_change else @exp(math.ln10 * @floor(@log10(@abs(start_v)))) * exp_min_change;
                                        const how_far = (pp.x - start_x) / px_scale;
                                        const how_much = (@exp(@abs(how_far) * exp_stretch) - 1) * base;
                                        init_opts.value.* = if (how_far < 0) start_v - how_much else start_v + how_much;
                                        if (init_opts.interval) |ival| {
                                            init_opts.value.* = start_v + ival * @round((init_opts.value.* - start_v) / ival);
                                        }
                                    }
                                }
                            }
                        }
                    }
                },
                .key => |ke| {
                    if (ke.code == .enter and ke.action == .down) {
                        text_mode = true;
                    } else if (ke.action == .down or ke.action == .repeat) {
                        switch (ke.code) {
                            .left, .right => {
                                e.handled = true;
                                ret = true;
                                if (init_opts.interval) |ival| {
                                    init_opts.value.* = init_opts.value.* + (if (ke.code == .left) -ival else ival);
                                } else {
                                    const how_much = @abs(init_opts.value.*) * key_percentage;
                                    init_opts.value.* = if (ke.code == .left) init_opts.value.* - how_much else init_opts.value.* + how_much;
                                }

                                if (init_opts.min) |min| {
                                    init_opts.value.* = @max(min, init_opts.value.*);
                                }

                                if (init_opts.max) |max| {
                                    init_opts.value.* = @min(max, init_opts.value.*);
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }

            if (e.bubbleable()) {
                b.wd.parent.processEvent(e, true);
            }
        }

        try b.wd.borderAndBackground(.{ .fill_color = if (hover) b.wd.options.color(.fill_hover) else b.wd.options.color(.fill) });

        // only draw handle if we have a min and max
        if (b.wd.visible() and init_opts.min != null and init_opts.max != null) {
            const how_far = (init_opts.value.* - init_opts.min.?) / (init_opts.max.? - init_opts.min.?);
            const knobRect = Rect{ .x = (br.w - knobsize) * math.clamp(how_far, 0, 1), .w = knobsize, .h = knobsize };
            const knobrs = b.widget().screenRectScale(knobRect);

            try pathAddRect(knobrs.r, options.corner_radiusGet().scale(knobrs.s));
            try pathFillConvex(options.color(.fill_press));
        }

        try label(@src(), label_fmt orelse "{d:.3}", .{init_opts.value.*}, options.strip().override(.{ .expand = .both, .gravity_x = 0.5, .gravity_y = 0.5 }));
    }

    if (b.data().id == focusedWidgetId()) {
        try b.data().focusBorder();
    }

    dataSet(null, b.data().id, "_text_mode", text_mode);
    dataSet(null, b.data().id, "_ctrl", ctrl_down);

    if (ret) {
        refresh(null, @src(), b.data().id);
    }

    return ret;
}

fn isF32Slice(comptime ptr: std.builtin.Type.Pointer, comptime child_info: std.builtin.Type) bool {
    const is_slice = ptr.size == .slice;
    const holds_f32 = switch (child_info) {
        .float => |f| f.bits == 32,
        else => false,
    };

    // If f32 slice, cast. Otherwise, throw an error.
    if (is_slice) {
        if (!holds_f32) {
            @compileError("Only f32 slices are supported!");
        }
        return true;
    }

    return false;
}

fn checkAndCastDataPtr(comptime num_components: u32, value: anytype) *[num_components]f32 {
    switch (@typeInfo(@TypeOf(value))) {
        .pointer => |ptr| {
            const child_info = @typeInfo(ptr.child);
            const is_f32_slice = comptime isF32Slice(ptr, child_info);

            if (is_f32_slice) {
                return @as(*[num_components]f32, @ptrCast(value.ptr));
            }

            // If not slice, need to check for arrays and vectors.
            // Need to also check the length.
            const data_len = switch (child_info) {
                .vector => |vec| vec.len,
                .array => |arr| arr.len,
                else => @compileError("Must supply a pointer to a vector or array!"),
            };

            if (data_len != num_components) {
                @compileError("Data and options have different lengths!");
            }

            return @ptrCast(value);
        },
        else => @compileError("Must supply a pointer to a vector or array!"),
    }
}

pub const SliderVectorInitOptions = struct {
    min: ?f32 = null,
    max: ?f32 = null,
    interval: ?f32 = null,
};

// Options are forwarded to the individual sliderEntries, including
// min_size_content
pub fn sliderVector(line: std.builtin.SourceLocation, comptime fmt: []const u8, comptime num_components: u32, value: anytype, init_opts: SliderVectorInitOptions, opts: Options) !bool {
    var data_arr = checkAndCastDataPtr(num_components, value);

    var any_changed = false;
    inline for (0..num_components) |i| {
        const component_opts = dvui.SliderEntryInitOptions{
            .value = &data_arr[i],
            .min = init_opts.min,
            .max = init_opts.max,
            .interval = init_opts.interval,
        };

        const component_changed = try dvui.sliderEntry(line, fmt, component_opts, opts.override(.{ .id_extra = i, .expand = .both }));
        any_changed = any_changed or component_changed;
    }

    return any_changed;
}

pub var progress_defaults: Options = .{
    .padding = Rect.all(2),
    .min_size_content = .{ .w = 10, .h = 10 },
    .color_fill = .{ .name = .fill_control },
};

pub const Progress_InitOptions = struct {
    dir: enums.Direction = .horizontal,
    percent: f32,
};

pub fn progress(src: std.builtin.SourceLocation, init_opts: Progress_InitOptions, opts: Options) !void {
    const options = progress_defaults.override(opts);

    var b = try box(src, init_opts.dir, options);
    defer b.deinit();

    const rs = b.data().contentRectScale();

    try pathAddRect(rs.r, options.corner_radiusGet().scale(rs.s));
    try pathFillConvex(options.color(.fill));

    const perc = @max(0, @min(1, init_opts.percent));
    if (perc == 0) return;

    var part = rs.r;
    switch (init_opts.dir) {
        .horizontal => {
            part.w *= perc;
        },
        .vertical => {
            const h = part.h * (1 - perc);
            part.y += h;
            part.h = rs.r.h - h;
        },
    }
    try pathAddRect(part, options.corner_radiusGet().scale(rs.s));
    try pathFillConvex(options.color(.accent));
}

pub var checkbox_defaults: Options = .{
    .name = "Checkbox",
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(6),
};

pub fn checkbox(src: std.builtin.SourceLocation, target: *bool, label_str: ?[]const u8, opts: Options) !bool {
    const options = checkbox_defaults.override(opts);
    var ret = false;

    var bw = ButtonWidget.init(src, .{}, options.strip().override(options));

    try bw.install();
    bw.processEvents();
    // don't call button drawBackground(), it wouldn't do anything anyway because we stripped the options so no border/background
    // don't call button drawFocus(), we don't want a focus ring around the label
    defer bw.deinit();

    if (bw.clicked()) {
        target.* = !target.*;
        ret = true;
    }

    var b = try box(@src(), .horizontal, options.strip().override(.{ .expand = .both }));
    defer b.deinit();

    const check_size = options.fontGet().textHeight();
    const s = try spacer(@src(), Size.all(check_size), .{ .gravity_x = 0.5, .gravity_y = 0.5 });

    const rs = s.borderRectScale();

    if (bw.wd.visible()) {
        try checkmark(target.*, bw.focused(), rs, bw.pressed(), bw.hovered(), options);
    }

    if (label_str) |str| {
        _ = try spacer(@src(), .{ .w = checkbox_defaults.paddingGet().w }, .{});
        try labelNoFmt(@src(), str, options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));
    }

    return ret;
}

pub fn checkmark(checked: bool, focused: bool, rs: RectScale, pressed: bool, hovered: bool, opts: Options) !void {
    try pathAddRect(rs.r, opts.corner_radiusGet().scale(rs.s));
    try pathFillConvex(opts.color(.border));

    if (focused) {
        try pathAddRect(rs.r, opts.corner_radiusGet().scale(rs.s));
        try pathStroke(true, 2 * rs.s, .none, opts.color(.accent));
    }

    var options = opts;
    if (checked) {
        options = opts.override(themeGet().style_accent);
        try pathAddRect(rs.r.insetAll(0.5 * rs.s), opts.corner_radiusGet().scale(rs.s));
    } else {
        try pathAddRect(rs.r.insetAll(rs.s), opts.corner_radiusGet().scale(rs.s));
    }

    if (pressed) {
        try pathFillConvex(options.color(.fill_press));
    } else if (hovered) {
        try pathFillConvex(options.color(.fill_hover));
    } else {
        try pathFillConvex(options.color(.fill));
    }

    if (checked) {
        const r = rs.r.insetAll(0.5 * rs.s);
        const pad = @max(1.0, r.w / 6);

        var thick = @max(1.0, r.w / 5);
        const size = r.w - (thick / 2) - pad * 2;
        const third = size / 3.0;
        const x = r.x + pad + (0.25 * thick) + third;
        const y = r.y + pad + (0.25 * thick) + size - (third * 0.5);

        thick /= 1.5;

        try pathAddPoint(Point{ .x = x - third, .y = y - third });
        try pathAddPoint(Point{ .x = x, .y = y });
        try pathAddPoint(Point{ .x = x + third * 2, .y = y - third * 2 });
        try pathStroke(false, thick, .square, options.color(.text));
    }
}

pub var radio_defaults: Options = .{
    .name = "Radio",
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(6),
};

pub fn radio(src: std.builtin.SourceLocation, active: bool, label_str: ?[]const u8, opts: Options) !bool {
    const options = radio_defaults.override(opts);
    var ret = false;

    var bw = ButtonWidget.init(src, .{}, options.strip().override(options));

    try bw.install();
    bw.processEvents();
    // don't call button drawBackground(), it wouldn't do anything anyway because we stripped the options so no border/background
    // don't call button drawFocus(), we don't want a focus ring around the label
    defer bw.deinit();

    if (bw.clicked()) {
        ret = true;
    }

    var b = try box(@src(), .horizontal, options.strip().override(.{ .expand = .both }));
    defer b.deinit();

    const radio_size = options.fontGet().textHeight();
    const s = try spacer(@src(), Size.all(radio_size), .{ .gravity_x = 0.5, .gravity_y = 0.5 });

    const rs = s.borderRectScale();

    if (bw.wd.visible()) {
        try radioCircle(active, bw.focused(), rs, bw.pressed(), bw.hovered(), options);
    }

    if (label_str) |str| {
        _ = try spacer(@src(), .{ .w = radio_defaults.paddingGet().w }, .{});
        try labelNoFmt(@src(), str, options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));
    }

    return ret;
}

pub fn radioCircle(active: bool, focused: bool, rs: RectScale, pressed: bool, hovered: bool, opts: Options) !void {
    try pathAddRect(rs.r, Rect.all(1000));
    try pathFillConvex(opts.color(.border));

    if (focused) {
        try pathAddRect(rs.r, Rect.all(1000));
        try pathStroke(true, 2 * rs.s, .none, opts.color(.accent));
    }

    var options = opts;
    if (active) {
        options = opts.override(themeGet().style_accent);
        try pathAddRect(rs.r.insetAll(0.5 * rs.s), Rect.all(1000));
    } else {
        try pathAddRect(rs.r.insetAll(rs.s), Rect.all(1000));
    }

    if (pressed) {
        try pathFillConvex(options.color(.fill_press));
    } else if (hovered) {
        try pathFillConvex(options.color(.fill_hover));
    } else {
        try pathFillConvex(options.color(.fill));
    }

    if (active) {
        const thick = @max(1.0, rs.r.w / 6);

        try pathAddPoint(Point{ .x = rs.r.x + rs.r.w / 2, .y = rs.r.y + rs.r.h / 2 });
        try pathStroke(false, thick, .square, options.color(.text));
    }
}

// pos is clamped to [0, text.len] then if it is in the middle of a multibyte
// utf8 char, we move it back to the beginning
pub fn findUtf8Start(text: []const u8, pos: usize) usize {
    var p = pos;
    p = @min(p, text.len);

    // find start of previous utf8 char
    var start = p -| 1;
    while (start < p and text[start] & 0xc0 == 0x80) {
        start -|= 1;
    }

    if (start < p) {
        const utf8_size = std.unicode.utf8ByteSequenceLength(text[start]) catch 0;
        if (utf8_size != (p - start)) {
            p = start;
        }
    }

    return p;
}

pub fn textEntry(src: std.builtin.SourceLocation, init_opts: TextEntryWidget.InitOptions, opts: Options) !*TextEntryWidget {
    const cw = currentWindow();
    var ret = try cw.arena().create(TextEntryWidget);
    ret.* = TextEntryWidget.init(src, init_opts, opts);
    try ret.install();
    // can install corner widgets here
    //_ = try dvui.button(@src(), "upright", .{}, .{ .gravity_x = 1.0 });
    ret.processEvents();
    try ret.draw();
    return ret;
}

pub fn TextEntryNumberInitOptions(comptime T: type) type {
    return struct {
        min: ?T = null,
        max: ?T = null,
        value: ?*T = null,
        show_min_max: bool = false,
    };
}

pub fn TextEntryNumberResult(comptime T: type) type {
    return struct {
        value: union(enum) {
            Valid: T,
            Invalid: void,
            TooBig: void,
            TooSmall: void,
            Empty: void,
        } = .Invalid,

        /// True if given a value pointer and wrote a valid value back to it.
        changed: bool = false,
        enter_pressed: bool = false,
    };
}

pub fn textEntryNumber(src: std.builtin.SourceLocation, comptime T: type, init_opts: TextEntryNumberInitOptions(T), opts: Options) !TextEntryNumberResult(T) {
    const base_filter = "1234567890";
    const filter = switch (@typeInfo(T)) {
        .int => |int| switch (int.signedness) {
            .signed => base_filter ++ "+-",
            .unsigned => base_filter ++ "+",
        },
        .float => base_filter ++ "+-.e",
        else => unreachable,
    };

    const id = dvui.parentGet().extendId(src, opts.idExtra());

    const buffer = dataGetSliceDefault(null, id, "buffer", []u8, &[_]u8{0} ** 32);

    //initialize with input number
    if (init_opts.value) |num| {
        const old_value = dataGet(null, id, "value", T);
        if (old_value == null or old_value.? != num.*) {
            dataSet(null, id, "value", num.*);
            @memset(buffer, 0); // clear out anything that was there before
            _ = try std.fmt.bufPrint(buffer, "{d}", .{num.*});
        }
    }

    const cw = currentWindow();
    var te = try cw.arena().create(TextEntryWidget);
    te.* = TextEntryWidget.init(src, .{ .text = .{ .buffer = buffer } }, opts);
    try te.install();
    te.processEvents();

    var result: TextEntryNumberResult(T) = .{ .enter_pressed = te.enter_pressed };

    // filter before drawing
    te.filterIn(filter);

    // validation
    const text = te.getText();
    const num = switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, text, 10) catch null,
        .float => std.fmt.parseFloat(T, text) catch null,
        else => unreachable,
    };

    //determine error if any
    if (text.len == 0 and num == null) {
        result.value = .Empty;
    } else if (num == null) {
        result.value = .Invalid;
    } else if (num != null and init_opts.min != null and num.? < init_opts.min.?) {
        result.value = .TooSmall;
    } else if (num != null and init_opts.max != null and num.? > init_opts.max.?) {
        result.value = .TooBig;
    } else {
        result.value = .{ .Valid = num.? };
        if (init_opts.value) |value_ptr| {
            if ((te.enter_pressed or te.text_changed) and value_ptr.* != num.?) {
                dataSet(null, id, "value", num.?);
                value_ptr.* = num.?;
                result.changed = true;
            }
        }
    }

    try te.draw();

    if (result.value != .Valid and (init_opts.value != null or result.value != .Empty)) {
        const rs = te.data().borderRectScale();
        try dvui.pathAddRect(rs.r.outsetAll(1), te.data().options.corner_radiusGet());
        const color = dvui.themeGet().color_err;
        try dvui.pathStrokeAfter(true, true, 3 * rs.s, .none, color);
    }

    // display min/max
    if (te.getText().len == 0 and init_opts.show_min_max) {
        var minmax_buffer: [64]u8 = undefined;
        var minmax_text: []const u8 = "";
        if (init_opts.min != null and init_opts.max != null) {
            minmax_text = try std.fmt.bufPrint(&minmax_buffer, "(min: {d}, max: {d})", .{ init_opts.min.?, init_opts.max.? });
        } else if (init_opts.min != null) {
            minmax_text = try std.fmt.bufPrint(&minmax_buffer, "(min: {d})", .{init_opts.min.?});
        } else if (init_opts.max != null) {
            minmax_text = try std.fmt.bufPrint(&minmax_buffer, "(max: {d})", .{init_opts.max.?});
        }
        try te.textLayout.addText(minmax_text, .{ .color_text = .{ .name = .fill_hover } });
    }

    te.deinit();

    return result;
}

pub const renderTextOptions = struct {
    font: Font,
    text: []const u8,
    rs: RectScale,
    color: Color,
    sel_start: ?usize = null,
    sel_end: ?usize = null,
    sel_color: ?Color = null,
    sel_color_bg: ?Color = null,
    debug: bool = false,
};

// only renders a single line of text
pub fn renderText(opts: renderTextOptions) !void {
    if (opts.rs.s == 0) return;
    if (opts.text.len == 0) return;
    if (clipGet().intersect(opts.rs.r).empty()) return;

    if (!std.unicode.utf8ValidateSlice(opts.text)) {
        log.warn("renderText invalid utf8 for \"{s}\"\n", .{opts.text});
        return error.InvalidUtf8;
    }

    var cw = currentWindow();

    if (!cw.render_target.rendering) {
        var opts_copy = opts;
        opts_copy.text = try cw.arena().dupe(u8, opts.text);
        const cmd = RenderCommand{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .text = opts_copy } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);
        return;
    }

    const r = opts.rs.r.offsetNegPoint(cw.render_target.offset);

    const target_size = opts.font.size * opts.rs.s;
    const sized_font = opts.font.resize(target_size);

    // might get a slightly smaller font
    var fce = try fontCacheGet(sized_font);

    // this must be synced with Font.textSizeEx()
    const target_fraction = if (cw.snap_to_pixels) 1.0 else target_size / fce.height;

    // make sure the cache has all the glyphs we need
    var utf8it = (try std.unicode.Utf8View.init(opts.text)).iterator();
    while (utf8it.nextCodepoint()) |codepoint| {
        _ = try fce.glyphInfoGet(@as(u32, @intCast(codepoint)), opts.font.name);
    }

    // number of extra pixels to add on each side of each glyph
    const pad = 1;

    if (fce.texture_atlas_regen) {
        fce.texture_atlas_regen = false;
        cw.backend.textureDestroy(fce.texture_atlas);

        const row_glyphs = @as(u32, @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(fce.glyph_info.count()))))));

        var size = Size{};
        {
            var it = fce.glyph_info.valueIterator();
            var i: u32 = 0;
            var rowlen: f32 = 0;
            while (it.next()) |gi| {
                if (i % row_glyphs == 0) {
                    size.w = @max(size.w, rowlen);
                    size.h += fce.height + 2 * pad;
                    rowlen = 0;
                }

                rowlen += gi.w + 2 * pad;

                i += 1;
            } else {
                size.w = @max(size.w, rowlen);
            }

            size = size.ceil();
        }

        // also add an extra padding around whole texture
        size.w += 2 * pad;
        size.h += 2 * pad;

        var pixels = try cw.arena().alloc(u8, @as(usize, @intFromFloat(size.w * size.h)) * 4);
        // set all pixels to zero alpha
        for (pixels) |*p| {
            p.* = 0;
            //if (i % 4 == 3) {
            //    p.* = 0;
            //} else {
            //    p.* = 255;
            //}
        }

        //const num_glyphs = fce.glyph_info.count();
        //std.debug.print("font size {d} regen glyph atlas num {d} max size {}\n", .{ sized_font.size, num_glyphs, size });

        {
            var x: i32 = pad;
            var y: i32 = pad;
            var it = fce.glyph_info.iterator();
            var i: u32 = 0;
            while (it.next()) |e| {
                var gi = e.value_ptr;
                gi.uv[0] = @as(f32, @floatFromInt(x + pad)) / size.w;
                gi.uv[1] = @as(f32, @floatFromInt(y + pad)) / size.h;

                const codepoint = @as(u32, @intCast(e.key_ptr.*));

                if (useFreeType) {
                    FontCacheEntry.intToError(c.FT_Load_Char(fce.face, codepoint, @as(i32, @bitCast(FontCacheEntry.LoadFlags{ .render = true })))) catch |err| {
                        log.warn("renderText: freetype error {!} trying to FT_Load_Char font {s} codepoint {d}\n", .{ err, opts.font.name, codepoint });
                        return error.freetypeError;
                    };

                    const bitmap = fce.face.*.glyph.*.bitmap;

                    //std.debug.print("codepoint {d} gi {d}x{d} bitmap {d}x{d}\n", .{ e.key_ptr.*, e.value_ptr.maxx - e.value_ptr.minx, e.value_ptr.maxy - e.value_ptr.miny, bitmap.width(), bitmap.rows() });
                    var row: i32 = 0;
                    while (row < bitmap.rows) : (row += 1) {
                        var col: i32 = 0;
                        while (col < bitmap.width) : (col += 1) {
                            if (bitmap.buffer == null) {
                                log.warn("renderText freetype bitmap null for font {s} codepoint {d}\n", .{ opts.font.name, codepoint });
                                return error.freetypeError;
                            }
                            const src = bitmap.buffer[@as(usize, @intCast(row * bitmap.pitch + col))];

                            // because of the extra edge, offset by 1 row and 1 col
                            const di = @as(usize, @intCast((y + row + pad) * @as(i32, @intFromFloat(size.w)) * 4 + (x + col + pad) * 4));

                            // premultiplied white
                            pixels[di + 0] = src;
                            pixels[di + 1] = src;
                            pixels[di + 2] = src;
                            pixels[di + 3] = src;
                        }
                    }
                } else {
                    const out_w: u32 = @intFromFloat(gi.w);
                    const out_h: u32 = @intFromFloat(gi.h);

                    // single channel
                    const bitmap = try cw.arena().alloc(u8, @as(usize, out_w * out_h));

                    //log.debug("makecodepointBitmap size x {d} y {d} w {d} h {d} out w {d} h {d}", .{ x, y, size.w, size.h, out_w, out_h });

                    c.stbtt_MakeCodepointBitmapSubpixel(&fce.face, bitmap.ptr, @as(c_int, @intCast(out_w)), @as(c_int, @intCast(out_h)), @as(c_int, @intCast(out_w)), fce.scaleFactor, fce.scaleFactor, 0.0, 0.0, @as(c_int, @intCast(codepoint)));

                    const stride = @as(usize, @intFromFloat(size.w)) * 4;
                    const di = @as(usize, @intCast(y)) * stride + @as(usize, @intCast(x * 4));
                    for (0..out_h) |row| {
                        for (0..out_w) |col| {
                            const src = bitmap[row * out_w + col];
                            const dest = di + (row + pad) * stride + (col + pad) * 4;

                            // premultiplied white
                            pixels[dest + 0] = src;
                            pixels[dest + 1] = src;
                            pixels[dest + 2] = src;
                            pixels[dest + 3] = src;
                        }
                    }
                }

                x += @as(i32, @intFromFloat(gi.w)) + 2 * pad;

                i += 1;
                if (i % row_glyphs == 0) {
                    x = pad;
                    y += @as(i32, @intFromFloat(fce.height)) + 2 * pad;
                }
            }
        }

        fce.texture_atlas = textureCreate(pixels.ptr, @as(u32, @intFromFloat(size.w)), @as(u32, @intFromFloat(size.h)), .linear);
        fce.texture_atlas_size = size;
    }

    var vtx = std.ArrayList(Vertex).init(cw.arena());
    defer vtx.deinit();
    var idx = std.ArrayList(u16).init(cw.arena());
    defer idx.deinit();

    const x_start: f32 = if (cw.snap_to_pixels) @round(r.x) else r.x;
    var x = x_start;
    var max_x = x_start;
    const y: f32 = if (cw.snap_to_pixels) @round(r.y) else r.y;

    if (opts.debug) {
        log.debug("renderText x {d} y {d}\n", .{ x, y });
    }

    var sel: bool = false;
    var sel_in: bool = false;
    var sel_start_x: f32 = x;
    var sel_end_x: f32 = x;
    var sel_max_y: f32 = y;
    var sel_start: usize = opts.sel_start orelse 0;
    sel_start = @min(sel_start, opts.text.len);
    var sel_end: usize = opts.sel_end orelse 0;
    sel_end = @min(sel_end, opts.text.len);
    if (sel_start < sel_end) {
        // we will definitely have a selected region
        sel = true;
    }

    var bytes_seen: usize = 0;
    var utf8 = (try std.unicode.Utf8View.init(opts.text)).iterator();
    while (utf8.nextCodepoint()) |codepoint| {
        const gi = try fce.glyphInfoGet(@as(u32, @intCast(codepoint)), opts.font.name);

        // TODO: kerning

        const nextx = x + gi.advance * target_fraction;

        if (sel) {
            bytes_seen += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            if (!sel_in and bytes_seen > sel_start and bytes_seen <= sel_end) {
                // entering selection
                sel_in = true;
                sel_start_x = x;
            } else if (sel_in and bytes_seen > sel_end) {
                // leaving selection
                sel_in = false;
            }

            if (sel_in) {
                // update selection
                sel_end_x = nextx;
            }
        }

        const len = @as(u32, @intCast(vtx.items.len));
        var v: Vertex = undefined;

        v.pos.x = x + gi.leftBearing * target_fraction;
        v.pos.y = y + gi.topBearing * target_fraction;
        v.col = if (sel_in) opts.sel_color orelse opts.color else opts.color;
        v.col = v.col.alphaMultiply();
        v.uv = gi.uv;
        try vtx.append(v);

        if (opts.debug) {
            log.debug(" - x {d} y {d}", .{ v.pos.x, v.pos.y });
        }

        if (opts.debug) {
            //log.debug("{d} pad {d} minx {d} maxx {d} miny {d} maxy {d} x {d} y {d}", .{ bytes_seen, pad, gi.minx, gi.maxx, gi.miny, gi.maxy, v.pos.x, v.pos.y });
            //log.debug("{d} pad {d} left {d} top {d} w {d} h {d} advance {d}", .{ bytes_seen, pad, gi.f2_leftBearing, gi.f2_topBearing, gi.f2_w, gi.f2_h, gi.f2_advance });
        }

        v.pos.x = x + (gi.leftBearing + gi.w) * target_fraction;
        max_x = v.pos.x;
        v.uv[0] = gi.uv[0] + gi.w / fce.texture_atlas_size.w;
        try vtx.append(v);

        v.pos.y = y + (gi.topBearing + gi.h) * target_fraction;
        sel_max_y = @max(sel_max_y, v.pos.y);
        v.uv[1] = gi.uv[1] + gi.h / fce.texture_atlas_size.h;
        try vtx.append(v);

        v.pos.x = x + gi.leftBearing * target_fraction;
        v.uv[0] = gi.uv[0];
        try vtx.append(v);

        // triangles must be counter-clockwise (y going down) to avoid backface culling
        try idx.append(@as(u16, @intCast(len + 0)));
        try idx.append(@as(u16, @intCast(len + 2)));
        try idx.append(@as(u16, @intCast(len + 1)));
        try idx.append(@as(u16, @intCast(len + 0)));
        try idx.append(@as(u16, @intCast(len + 3)));
        try idx.append(@as(u16, @intCast(len + 2)));

        x = nextx;
    }

    if (sel) {
        if (opts.sel_color_bg) |bgcol| {
            var sel_vtx: [4]Vertex = undefined;
            sel_vtx[0].pos.x = sel_start_x;
            sel_vtx[0].pos.y = r.y;
            sel_vtx[3].pos.x = sel_start_x;
            sel_vtx[3].pos.y = @max(sel_max_y, r.y + fce.height * target_fraction * opts.font.line_height_factor);
            sel_vtx[1].pos.x = sel_end_x;
            sel_vtx[1].pos.y = sel_vtx[0].pos.y;
            sel_vtx[2].pos.x = sel_end_x;
            sel_vtx[2].pos.y = sel_vtx[3].pos.y;

            for (&sel_vtx) |*v| {
                v.col = bgcol.alphaMultiply();
                v.uv[0] = 0;
                v.uv[1] = 0;
            }

            const selr = Rect.fromPoint(sel_vtx[0].pos).toPoint(sel_vtx[2].pos);
            const clip_offset = clipGet().offsetNegPoint(cw.render_target.offset);
            const clipr: ?Rect = if (selr.clippedBy(clip_offset)) clip_offset else null;

            // triangles must be counter-clockwise (y going down) to avoid backface culling
            cw.backend.drawClippedTriangles(null, &sel_vtx, &[_]u16{ 0, 2, 1, 0, 3, 2 }, clipr);
        }
    }

    // due to floating point inaccuracies, shrink by 1/1000 of a pixel before testing
    const txtr = (Rect{ .x = x_start, .y = y, .w = max_x - x_start, .h = sel_max_y - y }).insetAll(0.001);
    const clip_offset = clipGet().offsetNegPoint(cw.render_target.offset);
    const clipr: ?Rect = if (txtr.clippedBy(clip_offset)) clip_offset else null;

    cw.backend.drawClippedTriangles(fce.texture_atlas, vtx.items, idx.items, clipr);
}

pub fn debugRenderFontAtlases(rs: RectScale, color: Color) !void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    var cw = currentWindow();

    const cmd = RenderCommand{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .debug_font_atlases = .{ .rs = rs, .color = color } } };
    if (!cw.render_target.rendering) {
        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);
        return;
    }

    const r = rs.r.offsetNegPoint(cw.render_target.offset);

    const x: f32 = if (cw.snap_to_pixels) @round(r.x) else r.x;
    const y: f32 = if (cw.snap_to_pixels) @round(r.y) else r.y;
    const col = color.alphaMultiply();

    var offset: f32 = 0;
    var it = cw.font_cache.iterator();
    while (it.next()) |kv| {
        var vtx = std.ArrayList(Vertex).init(cw.arena());
        defer vtx.deinit();
        var idx = std.ArrayList(u16).init(cw.arena());
        defer idx.deinit();

        const len = @as(u32, @intCast(vtx.items.len));
        var v: Vertex = undefined;
        v.pos.x = x;
        v.pos.y = y + offset;
        v.col = col;
        v.uv = .{ 0, 0 };
        try vtx.append(v);

        v.pos.x = x + kv.value_ptr.texture_atlas_size.w;
        v.uv[0] = 1;
        try vtx.append(v);

        v.pos.y = y + offset + kv.value_ptr.texture_atlas_size.h;
        v.uv[1] = 1;
        try vtx.append(v);

        v.pos.x = x;
        v.uv[0] = 0;
        try vtx.append(v);

        // triangles must be counter-clockwise (y going down) to avoid backface culling
        try idx.append(@as(u16, @intCast(len + 0)));
        try idx.append(@as(u16, @intCast(len + 2)));
        try idx.append(@as(u16, @intCast(len + 1)));
        try idx.append(@as(u16, @intCast(len + 0)));
        try idx.append(@as(u16, @intCast(len + 3)));
        try idx.append(@as(u16, @intCast(len + 2)));

        const clip_offset = clipGet().offsetNegPoint(cw.render_target.offset);
        const clipr: ?Rect = if (r.clippedBy(clip_offset)) clip_offset else null;

        cw.backend.drawClippedTriangles(kv.value_ptr.texture_atlas, vtx.items, idx.items, clipr);

        offset += kv.value_ptr.texture_atlas_size.h;
    }
}

/// Create a texture that can be rendered with renderTexture().  pixels is RGBA premultiplied alpha.
///
/// Remember to destroy the texture at some point, see textureDestroyLater().
///
/// Only valid between dvui.Window.begin() and end().
pub fn textureCreate(pixels: [*]u8, width: u32, height: u32, interpolation: enums.TextureInterpolation) *anyopaque {
    return currentWindow().backend.textureCreate(pixels, width, height, interpolation);
}

/// Create a texture that can be rendered with renderTexture() and drawn to
/// with renderTarget().  Starts transparent (all zero).
///
/// Remember to destroy the texture at some point, see textureDestroyLater().
///
/// Only valid between dvui.Window.begin() and end().
pub fn textureCreateTarget(width: u32, height: u32, interpolation: enums.TextureInterpolation) !*anyopaque {
    return try currentWindow().backend.textureCreateTarget(width, height, interpolation);
}

/// Read pixels from texture created with textureCreateTarget().
///
/// Only valid between dvui.Window.begin() and end().
pub fn textureRead(texture: *anyopaque, pixels_out: [*]u8, width: u32, height: u32) !void {
    try currentWindow().backend.textureRead(texture, pixels_out, width, height);
}

/// Destroy a texture created with textureCreate() or textureCreateTarget() at
/// the end of the frame.
///
/// While backend.textureDestroy() immediately destroys the texture, this
/// function deferres the destruction until the end of the frame, so it is safe
/// to use even in a subwindow where rendering is deferred.
///
/// Only valid between dvui.Window.begin() and end().
pub fn textureDestroyLater(texture: *anyopaque) void {
    currentWindow().texture_trash.append(texture) catch |err| {
        dvui.log.err("textureDestroyLater got {!}\n", .{err});
    };
}

pub const RenderTarget = struct {
    texture: ?*anyopaque,
    offset: Point,
    rendering: bool = true,
};

/// Change where dvui renders.  Can pass output from textureCreateTarget() or
/// null for the screen.  Returns the previous target/offset.
///
/// offset will be subtracted from all dvui rendering, useful as the point on
/// the screen the texture will map to.
///
/// Useful for caching expensive renders or to save a render for export.
///
/// Only valid between dvui.Window.begin() and end().
pub fn renderTarget(args: RenderTarget) RenderTarget {
    var cw = currentWindow();
    const ret = cw.render_target;
    cw.render_target = args;
    cw.backend.renderTarget(args.texture);
    return ret;
}

pub const RenderTextureOptions = struct {
    rotation: f32 = 0,
    colormod: Color = .{},
    uv: ?Rect = null,
    debug: bool = false,
};

pub fn renderTexture(tex: *anyopaque, rs: RectScale, opts: RenderTextureOptions) !void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    var cw = currentWindow();

    if (!cw.render_target.rendering) {
        const cmd = RenderCommand{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .texture = .{ .tex = tex, .rs = rs, .opts = opts } } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);
        return;
    }

    const uv: Rect = opts.uv orelse Rect{ .x = 0, .y = 0, .w = 1, .h = 1 };

    const r = rs.r.offsetNegPoint(cw.render_target.offset);

    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena(), 4);
    defer vtx.deinit();
    var idx = try std.ArrayList(u16).initCapacity(cw.arena(), 6);
    defer idx.deinit();

    const x: f32 = if (cw.snap_to_pixels) @round(r.x) else r.x;
    const y: f32 = if (cw.snap_to_pixels) @round(r.y) else r.y;

    if (opts.debug) {
        log.debug("renderTexture at {d} {d} {d}x{d} uv {}", .{ x, y, r.w, r.h, uv });
    }

    const xw = x + r.w;
    const yh = y + r.h;

    const midx = (x + xw) / 2;
    const midy = (y + yh) / 2;

    const rot = opts.rotation;

    var v: Vertex = undefined;
    v.pos.x = x;
    v.pos.y = y;
    v.col = opts.colormod.alphaMultiply();
    v.uv[0] = uv.x;
    v.uv[1] = uv.y;
    if (rot != 0) {
        v.pos.x = midx + (x - midx) * @cos(rot) - (y - midy) * @sin(rot);
        v.pos.y = midy + (x - midx) * @sin(rot) + (y - midy) * @cos(rot);
    }
    try vtx.append(v);

    v.pos.x = xw;
    v.uv[0] = uv.w;
    if (rot != 0) {
        v.pos.x = midx + (xw - midx) * @cos(rot) - (y - midy) * @sin(rot);
        v.pos.y = midy + (xw - midx) * @sin(rot) + (y - midy) * @cos(rot);
    }
    try vtx.append(v);

    v.pos.y = yh;
    v.uv[1] = uv.h;
    if (rot != 0) {
        v.pos.x = midx + (xw - midx) * @cos(rot) - (yh - midy) * @sin(rot);
        v.pos.y = midy + (xw - midx) * @sin(rot) + (yh - midy) * @cos(rot);
    }
    try vtx.append(v);

    v.pos.x = x;
    v.uv[0] = uv.x;
    if (rot != 0) {
        v.pos.x = midx + (x - midx) * @cos(rot) - (yh - midy) * @sin(rot);
        v.pos.y = midy + (x - midx) * @sin(rot) + (yh - midy) * @cos(rot);
    }
    try vtx.append(v);

    // triangles must be counter-clockwise (y going down) to avoid backface culling
    try idx.append(0);
    try idx.append(2);
    try idx.append(1);
    try idx.append(0);
    try idx.append(3);
    try idx.append(2);

    const clip_offset = clipGet().offsetNegPoint(cw.render_target.offset);
    const clipr: ?Rect = if (r.clippedBy(clip_offset)) clip_offset else null;

    cw.backend.drawClippedTriangles(tex, vtx.items, idx.items, clipr);
}

pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: RectScale, rotation: f32, colormod: Color) !void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    // Ask for an integer size icon, then render it to fit rs
    const target_size = rs.r.h;
    const ask_height = @ceil(target_size);

    const tce = iconTexture(name, tvg_bytes, @as(u32, @intFromFloat(ask_height))) catch return;

    try renderTexture(tce.texture, rs, .{ .rotation = rotation, .colormod = colormod });
}

pub fn imageTexture(name: []const u8, image_bytes: []const u8) !TextureCacheEntry {
    var cw = currentWindow();
    const hash = TextureCacheEntry.hash(image_bytes, 0);

    if (cw.texture_cache.getPtr(hash)) |tce| {
        tce.used = true;
        return tce.*;
    }

    var w: c_int = undefined;
    var h: c_int = undefined;
    var channels_in_file: c_int = undefined;
    const data = c.stbi_load_from_memory(image_bytes.ptr, @as(c_int, @intCast(image_bytes.len)), &w, &h, &channels_in_file, 4);
    if (data == null) {
        log.warn("imageTexture stbi_load error on image \"{s}\": {s}\n", .{ name, c.stbi_failure_reason() });
        return Error.stbiError;
    }

    defer c.stbi_image_free(data);

    var pixels: []u8 = undefined;
    pixels.ptr = data;
    pixels.len = @intCast(w * h * 4);
    Color.alphaMultiplyPixels(pixels);

    const texture = textureCreate(pixels.ptr, @intCast(w), @intCast(h), .linear);

    //std.debug.print("created image texture \"{s}\" size {d}x{d}\n", .{ name, w, h });
    //const usizeh: usize = @intCast(h);
    //for (0..@intCast(h)) |hi| {
    //    for (0..@intCast(w)) |wi| {
    //        std.debug.print("pixel {d} {d} {d}.{d}.{d}.{d}\n", .{
    //            hi,
    //            wi,
    //            data[hi * usizeh * 4 + wi * 4],
    //            data[hi * usizeh * 4 + wi * 4 + 1],
    //            data[hi * usizeh * 4 + wi * 4 + 2],
    //            data[hi * usizeh * 4 + wi * 4 + 3],
    //        });
    //    }
    //}

    const entry = TextureCacheEntry{ .texture = texture, .size = .{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) } };
    try cw.texture_cache.put(hash, entry);

    return entry;
}

pub fn renderImage(name: []const u8, image_bytes: []const u8, rs: RectScale, rotation: f32, colormod: Color) !void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    const tce = imageTexture(name, image_bytes) catch return;
    try renderTexture(tce.texture, rs, .{ .rotation = rotation, .colormod = colormod });
}
