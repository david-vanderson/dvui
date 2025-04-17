//! [DVUI](https://david-vanderson.github.io/) is a general purpose Zig GUI toolkit.
//!
//! `dvui` module contains all the top level declarations provide all declarations required by client code. - i.e. `const dvui = @import("dvui");` is the only required import.
//!
//! Most UI element are expected to be created via high level function like `dvui.button`, which instantiate the corresponding lower level `dvui.ButtonWidget` for you.
//!
//! Custom widget can be done for simple cases my combining different high level function. For more advance usages, the user is expected to copy-paste the content of the high level functions as a starting point to combine the widgets on the lower level. More informations is available in the [project's readme](https://github.com/david-vanderson/dvui/blob/main/README.md).
//!
//! A complete list of available widgets can be found under `dvui.widgets`.
//!
const builtin = @import("builtin");
const std = @import("std");
pub const backend = @import("backend");
const tvg = @import("tinyvg/tinyvg.zig");
comptime {
    if (@hasDecl(backend, "deprecated")) {
        @compileError(backend.deprecated);
    }
}

pub const math = std.math;
pub const fnv = std.hash.Fnv1a_32;

pub const App = @import("App.zig");
pub const Backend = @import("Backend.zig");
pub const Window = @import("Window.zig");
pub const Examples = @import("Examples.zig");

pub const Color = @import("Color.zig");
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

// Note : Import widgets this way (i.e. importing them via `src/import_widgets.zig`
// so they are nicely referenced in docs.
// Having `pub const widgets = ` allow to refer the page with `dvui.widgets` in doccoment
pub const widgets = @import("import_widgets.zig");
pub const AnimateWidget = widgets.AnimateWidget;
pub const BoxWidget = widgets.BoxWidget;
pub const CacheWidget = widgets.CacheWidget;
pub const FlexBoxWidget = widgets.FlexBoxWidget;
pub const ReorderWidget = widgets.ReorderWidget;
pub const Reorderable = ReorderWidget.Reorderable;
pub const ButtonWidget = widgets.ButtonWidget;
pub const ContextWidget = widgets.ContextWidget;
pub const DropdownWidget = widgets.DropdownWidget;
pub const FloatingWindowWidget = widgets.FloatingWindowWidget;
pub const FloatingWidget = widgets.FloatingWidget;
pub const FloatingTooltipWidget = widgets.FloatingTooltipWidget;
pub const FloatingMenuWidget = widgets.FloatingMenuWidget;
pub const IconWidget = widgets.IconWidget;
pub const LabelWidget = widgets.LabelWidget;
pub const MenuWidget = widgets.MenuWidget;
pub const MenuItemWidget = widgets.MenuItemWidget;
pub const OverlayWidget = widgets.OverlayWidget;
pub const PanedWidget = widgets.PanedWidget;
pub const PlotWidget = widgets.PlotWidget;
pub const ScaleWidget = widgets.ScaleWidget;
pub const ScrollAreaWidget = widgets.ScrollAreaWidget;
pub const ScrollBarWidget = widgets.ScrollBarWidget;
pub const ScrollContainerWidget = widgets.ScrollContainerWidget;
pub const SuggestionWidget = widgets.SuggestionWidget;
pub const TabsWidget = widgets.TabsWidget;
pub const TextEntryWidget = widgets.TextEntryWidget;
pub const TextLayoutWidget = widgets.TextLayoutWidget;
pub const VirtualParentWidget = widgets.VirtualParentWidget;

const se = @import("structEntry.zig");
pub const structEntry = se.structEntry;
pub const structEntryEx = se.structEntryEx;
pub const structEntryAlloc = se.structEntryAlloc;
pub const structEntryExAlloc = se.structEntryExAlloc;
pub const StructFieldOptions = se.StructFieldOptions;

pub const enums = @import("enums.zig");
pub const easing = @import("easing.zig");
pub const testing = @import("testing.zig");

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

    if (wasm) {
        @cDefine("STBI_NO_STDIO", "1");
        @cDefine("STBI_NO_STDLIB", "1");
        @cDefine("STBIW_NO_STDLIB", "1");
    }
    @cInclude("stb_image.h");
    @cInclude("stb_image_write.h");

    if (!wasm) {
        @cInclude("tinyfiledialogs.h");
    }
});

pub var ft2lib: if (useFreeType) c.FT_Library else void = undefined;

pub const Error = error{ OutOfMemory, InvalidUtf8, freetypeError, tvgError, stbiError };

pub const log = std.log.scoped(.dvui);
const dvui = @This();

/// Current `Window` (i.e. the one that widgets will be added to).
/// Managed by `Window.begin` / `Window.end`
pub var current_window: ?*Window = null;

/// Get the current `dvui.Window` which corresponds to the OS window we are
/// currently adding widgets to.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn currentWindow() *Window {
    return current_window orelse unreachable;
}

/// Get a pointer to the active theme.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn themeGet() *Theme {
    return &currentWindow().theme;
}

/// Set the active theme (copies into internal storage).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn themeSet(theme: *const Theme) void {
    currentWindow().theme = theme.*;
}

/// Toggle showing the debug window (run during Window.end()).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toggleDebugWindow() void {
    var cw = currentWindow();
    cw.debug_window_show = !cw.debug_window_show;
}

pub const TagData = struct {
    id: u32,
    rect: Rect,
    visible: bool,
};

pub fn tag(name: []const u8, data: TagData) void {
    var cw = currentWindow();
    const existing_tag = cw.tags.fetchPut(name, .{ .data = data }) catch |err| blk: {
        dvui.log.err("tag() got {!} for it {x}\n", .{ err, data.id });

        break :blk null;
    };

    if (existing_tag) |kv| {
        if (kv.value.used) {
            dvui.log.err("duplicate tag name \"{s}\" id {x} (highlighted in red); you may need to pass .{{.id_extra=<loop index>}} as widget options (see https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids )\n", .{ name, data.id });
            cw.debug_widget_id = data.id;
        }
    }
}

pub fn tagGet(name: []const u8) ?TagData {
    var cw = currentWindow();
    const saved_tag = cw.tags.getPtr(name);
    if (saved_tag) |st| {
        return st.data;
    } else {
        return null;
    }
}

/// Help left-align widgets by adding horizontal spacers.
///
/// Only valid between `Window.begin`and `Window.end`.
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

    /// Add spacer with margin.x so they all end at the same edge.
    pub fn spacer(self: *Alignment, src: std.builtin.SourceLocation, id: u32) !void {
        const uniqueId = dvui.parentGet().extendId(src, id);
        var wd = try dvui.spacer(src, .{}, .{ .margin = self.margin(uniqueId), .id_extra = id });
        self.record(uniqueId, &wd);
    }

    /// Get the margin needed to align this id's left edge.
    pub fn margin(self: *Alignment, id: u32) Rect {
        if (self.max) |m| {
            if (dvui.dataGet(null, id, "_align", f32)) |a| {
                return .{ .x = @max(0, (m - a) / self.scale) };
            }
        }

        return .{};
    }

    /// Record where this widget ended up so we can align it next frame.
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

/// Controls how placeOnScreen() will move start to avoid spawner.
pub const PlaceOnScreenAvoid = enum {
    /// Don't avoid spawner
    none,
    /// Move to right of spawner, or jump to left
    horizontal,
    /// Move to bottom of spawner, or jump to top
    vertical,
};

/// Adjust start rect based on screen and spawner (like a context menu).
///
/// When adding a floating widget or window, often we want to guarantee that it
/// is visible.  Additionally, if start is logically connected to a spawning
/// rect (like a context menu spawning a submenu), then jump to the opposite
/// side if needed.
pub fn placeOnScreen(screen: Rect, spawner: Rect, avoid: PlaceOnScreenAvoid, start: Rect) Rect {
    var r = start;

    // first move to avoid spawner
    if (!r.intersect(spawner).empty()) {
        switch (avoid) {
            .none => {},
            .horizontal => r.x = spawner.x + spawner.w,
            .vertical => r.y = spawner.y + spawner.h,
        }
    }

    // fix up if we ran off right side of screen
    switch (avoid) {
        .none, .vertical => {
            // if off right, move
            if ((r.x + r.w) > (screen.x + screen.w)) {
                r.x = (screen.x + screen.w) - r.w;
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
        },
        .horizontal => {
            // if off right, is there more room on left
            if ((r.x + r.w) > (screen.x + screen.w)) {
                if ((spawner.x - screen.x) > (screen.x + screen.w - (spawner.x + spawner.w))) {
                    // more room on left, switch
                    r.x = spawner.x - r.w;

                    if (r.x < screen.x) {
                        // off left, shrink
                        r.x = screen.x;
                        r.w = spawner.x - screen.x;
                    }
                } else {
                    // more room on left, shrink
                    r.w = @max(24, (screen.x + screen.w) - r.x);
                }
            }
        },
    }

    // fix up if we ran off bottom of screen
    switch (avoid) {
        .none, .horizontal => {
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
        },
        .vertical => {
            // if off bottom, is there more room on top?
            if ((r.y + r.h) > (screen.y + screen.h)) {
                if ((spawner.y - screen.y) > (screen.y + screen.h - (spawner.y + spawner.h))) {
                    // more room on top, switch
                    r.y = spawner.y - r.h;

                    if (r.y < screen.y) {
                        // off top, shrink
                        r.y = screen.y;
                        r.h = spawner.y - screen.y;
                    }
                } else {
                    // more room on bottom, shrink
                    r.h = @max(24, (screen.y + screen.h) - r.y);
                }
            }
        },
    }

    return r;
}

/// Nanosecond timestamp for this frame.
///
/// Updated during Window.begin().  Will not go backwards.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn frameTimeNS() i128 {
    return currentWindow().frame_time_ns;
}

/// The bytes of a truetype font file and whether to free it.
pub const FontBytesEntry = struct {
    ttf_bytes: []const u8,

    /// If not null, this will be used to free ttf_bytes.
    allocator: ?std.mem.Allocator,
};

/// Add font to be referenced later by name.
///
/// ttf_bytes are the bytes of the ttf file
///
/// If ttf_bytes_allocator is not null, it will be used to free ttf_bytes in
/// Window.deinit().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn addFont(name: []const u8, ttf_bytes: []const u8, ttf_bytes_allocator: ?std.mem.Allocator) !void {
    var cw = currentWindow();
    try cw.font_bytes.put(name, FontBytesEntry{ .ttf_bytes = ttf_bytes, .allocator = ttf_bytes_allocator });

    errdefer _ = cw.font_bytes.remove(name);

    // Test if we can successfully open this font
    _ = try dvui.fontCacheGet(.{ .name = name, .size = 14 });
}

const GlyphInfo = struct {
    advance: f32, // horizontal distance to move the pen
    leftBearing: f32, // horizontal distance from pen to bounding box left edge
    topBearing: f32, // vertical distance from font ascent to bounding box top edge
    w: f32, // width of bounding box
    h: f32, // height of bounding box
    uv: @Vector(2, f32),
};

pub const FontCacheEntry = struct {
    used: bool = true,
    face: if (useFreeType) c.FT_Face else c.stbtt_fontinfo,
    scaleFactor: f32,
    height: f32,
    ascent: f32,
    glyph_info: std.AutoHashMap(u32, GlyphInfo),
    texture_atlas: Texture,
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

            //std.debug.print("{d} codepoint {d} stbtt x0 {d} {d} x1 {d} {d} y0 {d} {d} y1 {d} {d}\n", .{ self.ascent, codepoint, ix0, x0, ix1, x1, iy0, y0, iy1, y1 });

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
        var last_codepoint: u32 = 0;
        var last_glyph_index: u32 = 0;
        while (utf8.nextCodepoint()) |codepoint| {
            const gi = try fce.glyphInfoGet(@as(u32, @intCast(codepoint)), font_name);

            // kerning
            if (last_codepoint != 0) {
                if (useFreeType) {
                    if (last_glyph_index == 0) last_glyph_index = c.FT_Get_Char_Index(fce.face, last_codepoint);
                    const glyph_index: u32 = c.FT_Get_Char_Index(fce.face, codepoint);
                    var kern: c.FT_Vector = undefined;
                    FontCacheEntry.intToError(c.FT_Get_Kerning(fce.face, last_glyph_index, glyph_index, c.FT_KERNING_DEFAULT, &kern)) catch |err| {
                        log.warn("renderText freetype error {!} trying to FT_Get_Kerning font {s} codepoints {d} {d}\n", .{ err, font_name, last_codepoint, codepoint });
                        return error.freetypeError;
                    };
                    last_glyph_index = glyph_index;

                    const kern_x: f32 = @as(f32, @floatFromInt(kern.x)) / 64.0;

                    x += kern_x;
                } else {
                    const kern_adv: c_int = c.stbtt_GetCodepointKernAdvance(&fce.face, @as(c_int, @intCast(last_codepoint)), @as(c_int, @intCast(codepoint)));
                    const kern_x = fce.scaleFactor * @as(f32, @floatFromInt(kern_adv));

                    x += kern_x;
                }
            }
            last_codepoint = codepoint;

            minx = @min(minx, x + gi.leftBearing);
            maxx = @max(maxx, x + gi.leftBearing + gi.w);
            maxx = @max(maxx, x + gi.advance);

            miny = @min(miny, gi.topBearing);
            maxy = @max(maxy, gi.topBearing + gi.h);

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
    const pixels = cw.arena().alloc(u8, @as(usize, @intFromFloat(size.w * size.h)) * 4) catch @panic("OOM");
    @memset(pixels, 255);
    defer cw.arena().free(pixels);

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
            .height = @ceil(height),
            .ascent = @floor(ascent),
            .glyph_info = std.AutoHashMap(u32, GlyphInfo).init(cw.gpa),
            .texture_atlas = textureCreate(pixels.ptr, @as(u32, @intFromFloat(size.w)), @as(u32, @intFromFloat(size.h)), .linear),
            .texture_atlas_regen = true,
        };
    }
    //log.debug("- size {d} ascent {d} height {d}", .{ font.size, entry.ascent, entry.height });

    errdefer {
        textureDestroyLater(entry.texture_atlas);
    }
    try cw.font_cache.putNoClobber(fontHash, entry);

    return cw.font_cache.getPtr(fontHash).?;
}

/// A texture held by the backend.  Can be drawn with renderTexture().
pub const Texture = struct {
    ptr: *anyopaque,
    width: u32,
    height: u32,
};

/// A texture that will be held by dvui until a frame it is not used.  This is
/// how dvui caches icon and image rasterizations.
pub const TextureCacheEntry = struct {
    texture: Texture,
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
/// Only valid between `Window.begin`and `Window.end`.
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

/// Render tvg_bytes at height into a texture.  Name is for debugging.
///
/// Only valid between `Window.begin`and `Window.end`.
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

    const entry = TextureCacheEntry{ .texture = texture };
    try cw.texture_cache.put(icon_hash, entry);

    return entry;
}

/// Represents a deferred call to one of the render functions.  This is how
/// dvui defers rendering of floating windows so they render on top of widgets
/// that run later in the frame.
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
            tex: Texture,
            rs: RectScale,
            opts: RenderTextureOptions,
        },
        pathFillConvex: struct {
            path: []const Point,
            color: Color,
        },
        pathStroke: struct {
            path: []const Point,
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusSubwindow(subwindow_id: ?u32, event_num: ?u16) void {
    currentWindow().focusSubwindowInternal(subwindow_id, event_num);
}

/// Helper used by focusWidget.  Overwrites the focus information for events with num >
/// event_num.  This is how a button can get a tab, move focus to a textEntry,
/// and that textEntry get a keydown all in the same frame.
pub fn focusRemainingEvents(event_num: u16, focusWindowId: u32, focusWidgetId: ?u32) void {
    currentWindow().focusRemainingEventsInternal(event_num, focusWindowId, focusWidgetId);
}

/// Raise a subwindow to the top of the stack.
///
/// Any subwindows directly above it with "stay_above_parent_window" set will also be moved to stay above it.
///
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusedWidgetIdInCurrentSubwindow() ?u32 {
    const cw = currentWindow();
    const sw = cw.subwindowCurrent();
    return sw.focused_widgetId;
}

/// Last widget id we saw this frame that was the focused widget when it called
/// WidgetData.register().
///
/// If two calls to this function return different values, then some widget
/// that ran between them had focus.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn lastFocusedIdInFrame() u32 {
    return currentWindow().last_focused_id_this_frame;
}

/// Set cursor the app should use if not already set this frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn cursorSet(cursor: enums.Cursor) void {
    const cw = currentWindow();
    if (cw.cursor_requested == null) {
        cw.cursor_requested = cursor;
    }
}

/// Add rounded rect to path.  Starts from top left, and ends at top right
/// unclosed.  See Rect.fill().
///
/// radius values:
/// - x is top-left corner
/// - y is top-right corner
/// - w is bottom-right corner
/// - h is bottom-left corner
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn pathAddRect(path: *std.ArrayList(Point), r: Rect, radius: Rect) !void {
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
    try pathAddArc(path, tl, rad.x, math.pi * 1.5, math.pi, @abs(tl.y - bl.y) < 0.5);
    try pathAddArc(path, bl, rad.h, math.pi, math.pi * 0.5, @abs(bl.x - br.x) < 0.5);
    try pathAddArc(path, br, rad.w, math.pi * 0.5, 0, @abs(br.y - tr.y) < 0.5);
    try pathAddArc(path, tr, rad.y, math.pi * 2.0, math.pi * 1.5, @abs(tr.x - tl.x) < 0.5);
}

/// Add line segments creating an arc to path.
///
/// start >= end, both are radians that go clockwise from the positive x axis.
///
/// If skip_end, the final point will not be added.  Useful if the next
/// addition to path would duplicate the end of the arc.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn pathAddArc(path: *std.ArrayList(Point), center: Point, radius: f32, start: f32, end: f32, skip_end: bool) !void {
    if (radius == 0) {
        try path.append(center);
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
        try path.append(Point{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
        a -= step;
    }

    if (!skip_end) {
        a = end;
        try path.append(Point{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
    }
}

/// Fill path (must be convex) with color.  See Rect.fill().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn pathFillConvex(path: []const Point, color: Color) !void {
    if (path.len < 3) {
        return;
    }

    if (dvui.clipGet().empty()) {
        return;
    }

    const cw = currentWindow();

    if (!cw.render_target.rendering) {
        const path_copy = try cw.arena().dupe(Point, path);
        const cmd = RenderCommand{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .pathFillConvex = .{ .path = path_copy, .color = color } } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);
        return;
    }

    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena(), path.len * 2);
    defer vtx.deinit();
    const idx_count = (path.len - 2) * 3 + path.len * 6;
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
    while (i < path.len) : (i += 1) {
        const ai = (i + path.len - 1) % path.len;
        const bi = i % path.len;
        const ci = (i + 1) % path.len;
        const aa = path[ai].diff(cw.render_target.offset);
        const bb = path[bi].diff(cw.render_target.offset);
        const cc = path[ci].diff(cw.render_target.offset);

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
}

pub const EndCapStyle = enum {
    none,
    square,
};

pub const PathStrokeOptions = struct {
    /// true => Render this after normal drawing on that subwindow.  Useful for
    /// debugging on cross-gui drawing.
    after: bool = false,

    /// true => Stroke includes from path end to path start.
    closed: bool = false,

    endcap_style: EndCapStyle = .none,
};

/// Stroke path as a series of line segments.  See Rect.stroke().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn pathStroke(path: []const Point, thickness: f32, color: Color, opts: PathStrokeOptions) !void {
    if (path.len == 0) {
        return;
    }

    const cw = currentWindow();

    if (opts.after or !cw.render_target.rendering) {
        const path_copy = try cw.arena().dupe(Point, path);
        const cmd = RenderCommand{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .pathStroke = .{ .path = path_copy, .closed = opts.closed, .thickness = thickness, .endcap_style = opts.endcap_style, .color = color } } };

        var sw = cw.subwindowCurrent();
        if (opts.after) {
            try sw.render_cmds_after.append(cmd);
        } else {
            try sw.render_cmds.append(cmd);
        }

        return;
    }

    try pathStrokeRaw(path, thickness, color, opts.closed, opts.endcap_style);
}

pub fn pathStrokeRaw(path: []const Point, thickness: f32, color: Color, closed_in: bool, endcap_style: EndCapStyle) !void {
    if (dvui.clipGet().empty()) {
        return;
    }

    const cw = currentWindow();

    if (path.len == 1) {
        // draw a circle with radius thickness at that point
        const center = path[0].diff(cw.render_target.offset);

        var tempPath: std.ArrayList(Point) = .init(cw.arena());
        defer tempPath.deinit();

        try pathAddArc(&tempPath, center, thickness, math.pi * 2.0, 0, true);
        try pathFillConvex(tempPath.items, color);

        return;
    }

    var closed: bool = closed_in;
    if (path.len == 2) {
        // a single segment can't be closed
        closed = false;
    }

    var vtx_count = path.len * 4;
    if (!closed) {
        vtx_count += 4;
    }
    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena(), vtx_count);
    defer vtx.deinit();
    var idx_count = (path.len - 1) * 18;
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
    while (i < path.len) : (i += 1) {
        const ai = (i + path.len - 1) % path.len;
        const bi = i % path.len;
        const ci = (i + 1) % path.len;
        const aa = path[ai].diff(cw.render_target.offset);
        var bb = path[bi].diff(cw.render_target.offset);
        const cc = path[ci].diff(cw.render_target.offset);

        // the amount to move from bb to the edge of the line
        var halfnorm: Point = undefined;

        var v: Vertex = undefined;
        var diffab: Point = undefined;

        if (!closed and ((i == 0) or ((i + 1) == path.len))) {
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
            } else if ((i + 1) == path.len) {
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
        if (closed or ((i + 1) != path.len)) {
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
        } else if (!closed and (i + 1) == path.len) {
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
}

/// Called by floating widgets to participate in subwindow stacking - the order
/// in which multiple subwindows are drawn and which subwindow mouse events are
/// tagged with.
///
/// Only valid between `Window.begin`and `Window.end`.
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

/// Used by floating windows (subwindows) to install themselves as the current
/// subwindow (the subwindow that widgets run now will be in).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn subwindowCurrentSet(id: u32, rect: ?Rect) subwindowCurrentSetReturn {
    const cw = currentWindow();
    const ret: subwindowCurrentSetReturn = .{ .id = cw.subwindow_currentId, .rect = cw.subwindow_currentRect };
    cw.subwindow_currentId = id;
    if (rect) |r| {
        cw.subwindow_currentRect = r;
    }
    return ret;
}

/// Id of current subwindow (the one widgets run now will be in).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn subwindowCurrentId() u32 {
    const cw = currentWindow();
    return cw.subwindow_currentId;
}

/// Optional features you might want when doing a mouse/touch drag.
pub const DragStartOptions = struct {
    /// Use this cursor from when a drag starts to when it ends.
    cursor: ?enums.Cursor = null,

    /// Offset of point of interest from the mouse.  Useful during a drag to
    /// locate where to move the point of interest.
    offset: Point = .{},

    /// Used for cross-widget dragging.  See draggingName().
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragOffset() Point {
    const cw = currentWindow();
    return cw.drag_offset;
}

/// If a mouse drag is happening, return the pixel difference to p from the
/// previous dragging call or the drag starting location (from dragPreStart()
/// or dragStart()).  Otherwise return null, meaning a drag hasn't started yet.
///
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn draggingName(name: []const u8) bool {
    const cw = currentWindow();
    return cw.drag_state == .dragging and cw.drag_name.len > 0 and std.mem.eql(u8, name, cw.drag_name);
}

/// Stop any mouse drag.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragEnd() void {
    const cw = currentWindow();
    cw.drag_state = .none;
}

/// The difference between the final mouse position this frame and last frame.
/// Use mouseTotalMotion().nonZero() to detect if any mouse motion has occurred.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn mouseTotalMotion() Point {
    const cw = currentWindow();
    return Point.diff(cw.mouse_pt, cw.mouse_pt_prev);
}

/// Used to track which widget holds mouse capture.
pub const CaptureMouse = struct {
    /// widget ID
    id: u32,
    /// physical pixels (aka capture zone)
    rect: Rect,
    /// subwindow id the widget with capture is in
    subwindow_id: u32,
};
/// Capture the mouse for this widget's data.
/// (i.e. eventMatch() return true for this widget and false for all others)
/// and capture is explicitly released when passing `null`.
///
/// Tracks the widget's id / subwindow / rect, so that `.position` mouse events can still
/// be presented to widgets who's rect overlap with the widget holding the capture.
/// (which is what you would expect for e.g. background highlight)
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouse(wd: ?*WidgetData) void {
    const cm = if (wd) |data| CaptureMouse{
        .id = data.id,
        .rect = data.borderRectScale().r,
        .subwindow_id = subwindowCurrentId(),
    } else null;
    captureMouseCustom(cm);
}
/// In most cases, use captureMouse() but if you want to customize the
/// "capture zone" you can use this function instead.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouseCustom(cm: ?CaptureMouse) void {
    const cw = currentWindow();
    cw.capture = cm;
    if (cm != null) {
        cw.captured_last_frame = true;
    }
}
/// If the widget ID passed has mouse capture, this maintains that capture for
/// the next frame.  This is usually called for you in WidgetData.init().
///
/// This can be called every frame regardless of capture.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouseMaintain(cm: CaptureMouse) void {
    const cw = currentWindow();
    if (cw.capture != null and cw.capture.?.id == cm.id) {
        // to maintain capture, we must be on or above the
        // top modal window
        var i = cw.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &cw.subwindows.items[i - 1];
            if (sw.id == cw.subwindow_currentId) {
                // maintaining capture
                // either our floating window is above the top modal
                // or there are no floating modal windows
                cw.capture.?.rect = cm.rect;
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn captured(id: u32) bool {
    if (captureMouseGet()) |cm| {
        return id == cm.id;
    }
    return false;
}

/// Get the widget ID that currently has mouse capture or null if none.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouseGet() ?CaptureMouse {
    return currentWindow().capture;
}

/// Get current screen rectangle in pixels that drawing is being clipped to.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipGet() Rect {
    return currentWindow().clipRect;
}

/// Intersect the given rect (in pixels) with the current clipping rect and set
/// as the new clipping rect.
///
/// Returns the previous clipping rect, use clipSet to restore it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clip(new: Rect) Rect {
    const cw = currentWindow();
    const ret = cw.clipRect;
    clipSet(cw.clipRect.intersect(new));
    return ret;
}

/// Set the current clipping rect to the given rect (in pixels).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipSet(r: Rect) void {
    currentWindow().clipRect = r;
}

/// Set snap_to_pixels setting.  If true:
/// * fonts are rendered at @floor(font.size)
/// * drawing is generally rounded to the nearest pixel
///
/// Returns the previous setting.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn snapToPixelsSet(snap: bool) bool {
    const cw = currentWindow();
    const old = cw.snap_to_pixels;
    cw.snap_to_pixels = snap;
    return old;
}

/// Get current snap_to_pixels setting.  See snapToPixelsSet().
///
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipboardText() error{OutOfMemory}![]const u8 {
    const cw = currentWindow();
    return cw.backend.clipboardText();
}

/// Set the textual content of the system clipboard.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipboardTextSet(text: []const u8) error{OutOfMemory}!void {
    const cw = currentWindow();
    try cw.backend.clipboardTextSet(text);
}

/// Ask the system to open the given url.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn openURL(url: []const u8) !void {
    const cw = currentWindow();
    try cw.backend.openURL(url);
}

/// Seconds elapsed between last frame and current.  This value can be quite
/// high after a period with no user interaction.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn secondsSinceLastFrame() f32 {
    return currentWindow().secs_since_last_frame;
}

/// Average frames per second over the past 30 frames.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn FPS() f32 {
    return currentWindow().FPS();
}

/// Get the Widget that would be the parent of a new widget.
///
/// dvui.parentGet().extendId(@src(), id_extra) is how new widgets get their
/// id, and can be used to make a unique id without making a widget.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentGet() Widget {
    return currentWindow().wd.parent;
}

/// Make w the new parent widget.  See parentGet().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentSet(w: Widget) void {
    const cw = currentWindow();
    cw.wd.parent = w;
}

/// Make a previous parent widget the current parent.
///
/// Pass the current parent's id.  This is used to detect a coding error where
/// a widget's deinit() was accidentally not called.
///
/// Only valid between `Window.begin`and `Window.end`.
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

/// Set if dvui should immediately render, and return the previous setting.
///
/// If false, the render functions defer until Window.end().
///
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRect() Rect {
    return currentWindow().wd.rect;
}

/// Get the OS window size in pixels.  See windowRect().
///
/// Pixels is the unit for rendering and user input.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRectPixels() Rect {
    return currentWindow().rect_pixels;
}

/// Get the Rect and scale factor for the OS window.  The Rect is in pixels,
/// and the scale factor is how many pixels per natural pixel.  See
/// windowRect().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRectScale() RectScale {
    return .{ .r = currentWindow().rect_pixels, .s = currentWindow().natural_scale };
}

/// The natural scale is how many pixels per natural pixel.  Useful for
/// converting between user input and subwindow size/position.  See
/// windowRect().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowNaturalScale() f32 {
    return currentWindow().natural_scale;
}

/// True if this is the first frame we've seen this widget id, meaning we don't
/// know its min size yet.  The widget will record its min size in deinit().
///
/// If a widget is not seen for a frame, its min size will be forgotten and
/// firstFrame will return true the next frame we see it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn firstFrame(id: u32) bool {
    return minSizeGet(id) == null;
}

/// Get the min size recorded for id from last frame or null if id was not seen
/// last frame.
///
/// Usually you want minSize() to combine min size from last frame with a min
/// size provided by the user code.
///
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
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

/// Make a unique id from src and id_extra, possibly starting with start
/// (usually a parent widget id).  This is how the initial parent widget id is
/// created, and also toasts and dialogs from other threads.
///
/// See Widget.extendId() which calls this with the widget id as start.
///
/// dvui.parentGet().extendId(@src(), id_extra) is how new widgets get their
/// id, and can be used to make a unique id without making a widget.
pub fn hashSrc(start: ?u32, src: std.builtin.SourceLocation, id_extra: usize) u32 {
    var hash = fnv.init();
    if (start) |s| {
        hash.value = s;
    }
    hash.update(std.mem.asBytes(&src.module.ptr));
    hash.update(std.mem.asBytes(&src.file.ptr));
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
/// Stored data with the same id/key will be freed at next win.end().
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
/// Stored data with the same id/key will be freed at next win.end().
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
/// Stored data with the same id/key will be freed at next win.end().
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

/// Remove key (and data if any) for given id.  The data will be freed at next
/// win.end().
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

/// Return a rect that fits inside avail given the options. avail wins over
/// min_size.
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
            if (min_size.w > 0 and min_size.h > 0 and avail.w > 0 and avail.h > 0) {
                const ratio = min_size.w / min_size.h;
                if (min_size.w > avail.w or min_size.h > avail.h) {
                    // contracting
                    const wratio = avail.w / min_size.w;
                    const hratio = avail.h / min_size.h;
                    if (wratio < hratio) {
                        // width is constraint
                        size.w = avail.w;
                        size.h = @min(avail.h, wratio * min_size.h);
                    } else {
                        // height is constraint
                        size.h = avail.h;
                        size.w = @min(avail.w, hratio * min_size.w);
                    }
                } else {
                    // expanding
                    const aratio = (avail.w - size.w) / (avail.h - size.h);
                    if (aratio > ratio) {
                        // height is constraint
                        size.w = @min(avail.w, avail.h * ratio);
                        size.h = avail.h;
                    } else {
                        // width is constraint
                        size.w = avail.w;
                        size.h = @min(avail.h, avail.w / ratio);
                    }
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn events() []Event {
    return currentWindow().events.items;
}

/// Wrapper around eventMatch for normal usage.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn eventMatchSimple(e: *Event, wd: *WidgetData) bool {
    return eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r });
}

/// Data for matching events to widgets.  See eventMatch().
pub const EventMatchOptions = struct {
    /// Id of widget, used to route non pointer events based on focus.
    id: u32,

    /// Physical pixel rect used to match pointer events.
    r: Rect,

    /// true means match all focus-based events routed to the subwindow with
    /// id.  This is how subwindows catch things like tab if no widget in that
    /// subwindow has focus.
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
/// Only valid between `Window.begin`and `Window.end`.
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
            const capture = captureMouseGet();
            var other_capture = false;
            if (capture) |cm| blk: {
                if (me.action == .wheel_x or me.action == .wheel_y) {
                    // wheel is not affected by mouse capture
                    break :blk;
                }

                if (cm.id == opts.id) {
                    // we have capture, we get all mouse events
                    return true;
                } else {
                    // someone else has capture
                    other_capture = true;
                }
            }

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

            if (other_capture) {
                // someone else has capture, but otherwise we would have gotten
                // this mouse event
                if (me.action == .position and capture.?.subwindow_id == subwindowCurrentId() and !capture.?.rect.intersect(opts.r).empty()) {
                    // we might be trying to highlight a background around the widget with capture:
                    // * we are in the same subwindow
                    // * our rect overlaps with the capture rect
                    return true;
                }

                return false;
            }
        },

        .close_popup => unreachable,
        .scroll_drag => unreachable,
        .scroll_to => unreachable,
        .scroll_propagate => unreachable,
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
/// how to have a seamless continuous animation.
pub const Animation = struct {
    used: bool = true,
    easing: *const easing.EasingFn = easing.linear,
    start_val: f32 = 0,
    end_val: f32 = 1,
    start_time: i32 = 0,
    end_time: i32,

    /// Get the interpolated value between `start_val` and `end_val`
    ///
    /// For some easing functions, this value can extend above or bellow
    /// `start_val` and `end_val`. If this is an issue, you can choose
    /// a different easing function or use `std.math.clamp`
    pub fn value(a: *const Animation) f32 {
        if (a.start_time >= 0) return a.start_val;
        if (a.done()) return a.end_val;
        const frac = @as(f32, @floatFromInt(-a.start_time)) / @as(f32, @floatFromInt(a.end_time - a.start_time));
        const t = a.easing(std.math.clamp(frac, 0, 1));
        return std.math.lerp(a.start_val, a.end_val, t);
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn timer(id: u32, micros: i32) !void {
    try currentWindow().timer(id, micros);
}

/// Return the number of micros left on the timer for id if there is one.  If
/// timerDone(), this value will be <= 0 and represents how many micros this
/// frame is past the timer expiration.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerGet(id: u32) ?i32 {
    if (animationGet(id, "_timer")) |a| {
        return a.end_time;
    } else {
        return null;
    }
}

/// Return true on the first frame after a timer has expired.
///
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerDoneOrNone(id: u32) bool {
    return timerDone(id) or (timerGet(id) == null);
}

pub const TabIndex = struct {
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn wantTextInput(r: Rect) void {
    const cw = currentWindow();
    cw.text_input_rect = r.scale(1 / cw.natural_scale);
}

pub const popup = if (!builtin.is_test) @compileError("popup renamed to floatingMenu");

pub fn floatingMenu(src: std.builtin.SourceLocation, init_opts: FloatingMenuWidget.InitOptions, opts: Options) !*FloatingMenuWidget {
    var ret = try currentWindow().arena().create(FloatingMenuWidget);
    ret.* = FloatingMenuWidget.init(src, init_opts, opts);
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

/// Add a dialog to be displayed on the GUI thread during `Window.end`.
///
/// Returns an id and locked mutex that **must** be unlocked by the caller. Caller
/// does any `Window.dataSet` calls before unlocking the mutex to ensure that
/// data is available before the dialog is displayed.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you
/// **must** pass a pointer to the Window you want to add the dialog to.
pub fn dialogAdd(win: ?*Window, src: std.builtin.SourceLocation, id_extra: usize, display: DialogDisplayFn) !IdMutex {
    if (win) |w| {
        // we are being called from non gui thread
        const id = hashSrc(null, src, id_extra);
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
/// user_struct can be anytype, each field will be stored using
/// dataSet/dataSetSlice for use in opts.displayFn
///
/// Can be called from any thread, but if calling from a non-GUI thread or
/// outside window.begin()/end(), you must set opts.window.
pub fn dialog(src: std.builtin.SourceLocation, user_struct: anytype, opts: DialogOptions) !void {
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

    // add all fields of user_struct
    inline for (@typeInfo(@TypeOf(user_struct)).@"struct".fields) |f| {
        const ft = @typeInfo(f.type);
        if (ft == .pointer and (ft.pointer.size == .slice or (ft.pointer.size == .one and @typeInfo(ft.pointer.child) == .array))) {
            dataSetSlice(opts.window, id, f.name, @field(user_struct, f.name));
        } else {
            dataSet(opts.window, id, f.name, @field(user_struct, f.name));
        }
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

pub const DialogWasmFileOptions = struct {
    /// Filter files shown by setting the [accept](https://developer.mozilla.org/en-US/docs/Web/HTML/Attributes/accept) attribute
    ///
    /// Example: ".pdf, image/*"
    accept: ?[]const u8 = null,
};

const WasmFile = struct {
    id: u32,
    index: usize,
    /// The size of the data in bytes
    size: usize,
    /// The filename of the uploaded file. Does not include the path of the file
    name: [:0]const u8,

    pub fn readData(self: *WasmFile, allocator: std.mem.Allocator) ![]u8 {
        std.debug.assert(wasm); // WasmFile shouldn't be used outside wasm builds
        const data = try allocator.alloc(u8, self.size);
        dvui.backend.readFileData(self.id, self.index, data.ptr);
        return data;
    }
};

/// Opens a file picker WITHOUT blocking. The file can be accessed by calling wasmFileUploaded(id) with the same id
///
/// This function does nothing in non-wasm builds
pub fn dialogWasmFileOpen(id: u32, opts: DialogWasmFileOptions) void {
    if (!wasm) return;
    dvui.backend.openFilePicker(id, opts.accept, false);
}

/// Will only return a non-null value for a single frame
///
/// This function does nothing in non-wasm builds
pub fn wasmFileUploaded(id: u32) ?WasmFile {
    if (!wasm) return null;
    const num_files = dvui.backend.getNumberOfFilesAvailable(id);
    if (num_files == 0) return null;
    if (num_files > 1) {
        log.err("Received more than one file for id {d}. Did you mean to call wasmFileUploadedMultiple?", .{id});
    }
    const name = dvui.backend.getFileName(id, 0);
    const size = dvui.backend.getFileSize(id, 0);
    if (name == null or size == null) {
        log.err("Could not get file metadata. Got size: {?d} and name: {?s}", .{ size, name });
        return null;
    }
    return WasmFile{
        .id = id,
        .index = 0,
        .size = size.?,
        .name = name.?,
    };
}

/// Opens a file picker WITHOUT blocking. The files can be accessed by calling wasmFileUploadedMultiple(id) with the same id
///
/// This function does nothing in non-wasm builds
pub fn dialogWasmFileOpenMultiple(id: u32, opts: DialogWasmFileOptions) void {
    if (!wasm) return;
    dvui.backend.openFilePicker(id, opts.accept, true);
}

/// Will only return a non-null value for a single frame
///
/// This function does nothing in non-wasm builds
pub fn wasmFileUploadedMultiple(id: u32) ?[]WasmFile {
    if (!wasm) return null;
    const num_files = dvui.backend.getNumberOfFilesAvailable(id);
    if (num_files == 0) return null;

    const files = dvui.currentWindow().arena().alloc(WasmFile, num_files) catch |err| {
        log.err("File upload skipped, failed to allocate space for file handles: {!}", .{err});
        return null;
    };
    for (0.., files) |i, *file| {
        const name = dvui.backend.getFileName(id, i);
        const size = dvui.backend.getFileSize(id, i);
        if (name == null or size == null) {
            log.err("Could not get file metadata for id {d} file number {d}. Got size: {?d} and name: {?s}", .{ id, i, size, name });
            return null;
        }
        file.* = WasmFile{
            .id = id,
            .index = i,
            .size = size.?,
            .name = name.?,
        };
    }
    return files;
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
pub fn dialogNativeFileOpen(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) !?[:0]const u8 {
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
pub fn dialogNativeFileOpenMultiple(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) !?[][:0]const u8 {
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
pub fn dialogNativeFileSave(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) !?[:0]const u8 {
    if (wasm) {
        return null;
    }

    return dialogNativeFileInternal(false, false, alloc, opts);
}

fn dialogNativeFileInternal(comptime open: bool, comptime multiple: bool, alloc: std.mem.Allocator, opts: DialogNativeFileOptions) if (multiple) error{OutOfMemory}!?[][:0]const u8 else error{OutOfMemory}!?[:0]const u8 {
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

    var result: if (multiple) ?[][:0]const u8 else ?[:0]const u8 = null;
    const tfd_ret: [*c]const u8 = blk: {
        if (open) {
            break :blk dvui.c.tinyfd_openFileDialog(title, path, @intCast(filter_count), filters, filter_desc, if (multiple) 1 else 0);
        } else {
            break :blk dvui.c.tinyfd_saveFileDialog(title, path, @intCast(filter_count), filters, filter_desc);
        }
    };

    if (tfd_ret) |r| {
        if (multiple) {
            const r_slice = std.mem.span(r);
            const num = std.mem.count(u8, r_slice, "|") + 1;
            result = try alloc.alloc([:0]const u8, num);
            var it = std.mem.splitScalar(u8, r_slice, '|');
            var i: usize = 0;
            while (it.next()) |f| {
                result.?[i] = try alloc.dupeZ(u8, f);
                i += 1;
            }
        } else {
            result = try alloc.dupeZ(u8, std.mem.span(r));
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
        const id = hashSrc(null, src, id_extra);
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

    var animator = try dvui.animate(@src(), .{ .kind = .alpha, .duration = 500_000 }, .{ .id_extra = id });
    defer animator.deinit();
    try dvui.labelNoFmt(@src(), message, .{ .background = true, .corner_radius = dvui.Rect.all(1000), .padding = Rect.all(8) });

    if (dvui.timerDone(id)) {
        animator.startEnd();
    }

    if (animator.end()) {
        dvui.toastRemove(id);
    }
}

pub fn animate(src: std.builtin.SourceLocation, init_opts: AnimateWidget.InitOptions, opts: Options) !*AnimateWidget {
    var ret = try currentWindow().arena().create(AnimateWidget);
    ret.* = AnimateWidget.init(src, init_opts, opts);
    try ret.install();
    return ret;
}

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

pub const SuggestionInitOptions = struct {
    button: bool = false,
    opened: bool = false,
    open_on_text_change: bool = false,
};

pub fn suggestion(te: *TextEntryWidget, init_opts: SuggestionInitOptions) !*SuggestionWidget {
    var open_sug = init_opts.opened;

    if (init_opts.button) {
        if (try dvui.buttonIcon(@src(), "combobox_triangle", entypo.chevron_small_down, .{}, .{ .expand = .ratio, .margin = dvui.Rect.all(2), .gravity_x = 1.0 })) {
            open_sug = true;
            dvui.focusWidget(te.data().id, null, null);
        }
    }

    const min_width = te.textLayout.data().backgroundRect().w;

    var sug = try currentWindow().arena().create(SuggestionWidget);
    sug.* = dvui.SuggestionWidget.init(@src(), .{ .rs = te.data().borderRectScale(), .text_entry_id = te.data().id }, .{ .min_size_content = .{ .w = min_width }, .padding = .{}, .border = te.data().options.borderGet() });
    try sug.install();
    if (open_sug) {
        sug.open();
    }

    // process events from textEntry
    const evts = dvui.events();
    for (evts) |*e| {
        if (!te.matchEvent(e)) {
            continue;
        }

        if (e.evt == .key and (e.evt.key.action == .down or e.evt.key.action == .repeat)) {
            switch (e.evt.key.code) {
                .up => {
                    e.handled = true;
                    if (sug.willOpen()) {
                        sug.selected_index -|= 1;
                    } else {
                        sug.open();
                    }
                },
                .down => {
                    e.handled = true;
                    if (sug.willOpen()) {
                        sug.selected_index += 1;
                    } else {
                        sug.open();
                    }
                },
                .escape => {
                    e.handled = true;
                    sug.close();
                },
                .enter => {
                    if (sug.willOpen()) {
                        e.handled = true;
                        sug.activate_selected = true;
                    }
                },
                else => {},
            }
        }

        if (!e.handled) {
            te.processEvent(e, false);
        }
    }

    if (init_opts.open_on_text_change and te.text_changed) {
        sug.open();
    }

    return sug;
}

pub fn comboBox(src: std.builtin.SourceLocation, entries: []const []const u8, init_opts: TextEntryWidget.InitOptions, opts: Options) !*TextEntryWidget {
    var te = try currentWindow().arena().create(TextEntryWidget);
    te.* = dvui.TextEntryWidget.init(src, init_opts, opts);
    try te.install();

    var sug = try dvui.suggestion(te, .{ .button = true });

    if (try sug.dropped()) {
        for (entries) |entry| {
            if (try sug.addChoiceLabel(entry)) {
                te.textSet(entry, false);
            }
        }
    }

    sug.deinit();

    // suggestion forwards events to textEntry, so don't call te.processEvents()
    try te.draw();
    return te;
}

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
    if (expanded) {
        try icon(@src(), "down_arrow", entypo.triangle_down, .{ .gravity_y = 0.5 });
    } else {
        try icon(@src(), "right_arrow", entypo.triangle_right, .{ .gravity_y = 0.5 });
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
/// Only valid between `Window.begin`and `Window.end`.
pub fn context(src: std.builtin.SourceLocation, init_opts: ContextWidget.InitOptions, opts: Options) !*ContextWidget {
    var ret = try currentWindow().arena().create(ContextWidget);
    ret.* = ContextWidget.init(src, init_opts, opts);
    try ret.install();
    ret.processEvents();
    return ret;
}

pub fn tooltip(src: std.builtin.SourceLocation, init_opts: FloatingTooltipWidget.InitOptions, comptime fmt: []const u8, fmt_args: anytype, opts: Options) !void {
    var tt: dvui.FloatingTooltipWidget = .init(src, init_opts, opts);
    if (try tt.shown()) {
        var tl2 = try dvui.textLayout(@src(), .{}, .{ .background = false });
        try tl2.format(fmt, fmt_args, .{});
        tl2.deinit();
    }
    tt.deinit();
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
    try wd.borderAndBackground(.{});
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

    var t: f32 = 0;
    const anim = Animation{ .end_time = 3_000_000 };
    if (animationGet(wd.id, "_t")) |a| {
        // existing animation
        var aa = a;
        if (aa.done()) {
            // this animation is expired, seamlessly transition to next animation
            aa = anim;
            aa.start_time = a.end_time;
            aa.end_time += a.end_time;
            animation(wd.id, "_t", aa);
        }
        t = aa.value();
    } else {
        // first frame we are seeing the spinner
        animation(wd.id, "_t", anim);
    }

    var path: std.ArrayList(dvui.Point) = .init(dvui.currentWindow().arena());
    defer path.deinit();

    const full_circle = 2 * std.math.pi;
    // start begins fast, speeding away from end
    const start = full_circle * easing.outSine(t);
    // end begins slow, catching up to start
    const end = full_circle * easing.inSine(t);

    const center = Point{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
    try pathAddArc(&path, center, @min(r.w, r.h) / 3, start, end, false);
    try pathStroke(path.items, 3.0 * rs.s, options.color(.text), .{});
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
    var iconopts = opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = opts.min_size_content, .expand = .ratio });

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

    var lw = LabelWidget.init(src, fmt, args, opts.override(.{ .name = "LabelClick" }));
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
                    dvui.captureMouse(lw.data());

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
    var lw = LabelWidget.init(src, fmt, args, opts);
    try lw.install();
    lw.processEvents();
    try lw.draw();
    lw.deinit();
}

pub fn labelNoFmt(src: std.builtin.SourceLocation, str: []const u8, opts: Options) !void {
    var lw = LabelWidget.initNoFmt(src, str, opts);
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

pub const ImageInitOptions = struct {
    /// Used for debugging output.
    name: []const u8 = "image",

    /// Bytes of the image file (like png), decoded lazily and cached.
    bytes: []const u8,

    /// If min size is larger than the rect we got, how to shrink it:
    /// - null => use expand setting
    /// - none => crop
    /// - horizontal => crop height, fit width
    /// - vertical => crop width, fit height
    /// - both => fit in rect ignoring aspect ratio
    /// - ratio => fit in rect maintaining aspect ratio
    shrink: ?Options.Expand = null,
};

/// Show raster image.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn image(src: std.builtin.SourceLocation, init_opts: ImageInitOptions, opts: Options) !WidgetData {
    const options = (Options{ .name = init_opts.name }).override(opts);

    var size = Size{};
    if (options.min_size_content) |msc| {
        // user gave us a min size, use it
        size = msc;
    } else {
        // user didn't give us one, use natural size
        size = dvui.imageSize(init_opts.name, init_opts.bytes) catch .{ .w = 10, .h = 10 };
    }

    var wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));
    try wd.register();
    try wd.borderAndBackground(.{});

    const cr = wd.contentRect();
    const ms = wd.options.min_size_contentGet();

    var too_big = false;
    if (ms.w > cr.w or ms.h > cr.h) {
        too_big = true;
    }

    var e = wd.options.expandGet();
    if (too_big) {
        e = init_opts.shrink orelse e;
    }
    const g = wd.options.gravityGet();
    var rect = dvui.placeIn(cr, ms, e, g);
    var doclip = false;
    var old_clip: Rect = undefined;

    if (too_big and e != .ratio) {
        if (ms.w > cr.w and !e.isHorizontal()) {
            doclip = true;

            rect.w = ms.w;
            rect.x -= g.x * (ms.w - cr.w);
        }

        if (ms.h > cr.h and !e.isVertical()) {
            doclip = true;

            rect.h = ms.h;
            rect.y -= g.y * (ms.h - cr.h);
        }
    }

    const rs = wd.parent.screenRectScale(rect);
    if (doclip) {
        old_clip = dvui.clip(wd.contentRectScale().r);
    }
    try dvui.renderImage(init_opts.name, init_opts.bytes, rs, wd.options.rotationGet(), .{});
    if (doclip) {
        dvui.clipSet(old_clip);
    }

    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    return wd;
}

pub fn debugFontAtlases(src: std.builtin.SourceLocation, opts: Options) !void {
    const cw = currentWindow();

    var width: u32 = 0;
    var height: u32 = 0;
    var it = cw.font_cache.iterator();
    while (it.next()) |kv| {
        width = @max(width, kv.value_ptr.texture_atlas.width);
        height += kv.value_ptr.texture_atlas.height;
    }

    var size: Size = .{ .w = @floatFromInt(width), .h = @floatFromInt(height) };

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
                    captureMouse(b.data());
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
                    dvui.cursorSet(.arrow);
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
        try part.fill(options.corner_radiusGet().scale(trackrs.s), options.color(.accent));
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
        try part.fill(options.corner_radiusGet().scale(trackrs.s), options.color(.fill));
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
    // min size calculated from font
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
                            refresh(null, @src(), b.data().id);
                        } else {
                            captureMouse(b.data());
                            dataSet(null, b.data().id, "_start_x", me.p.x);
                            dataSet(null, b.data().id, "_start_v", init_opts.value.*);

                            if (me.button.touch()) {
                                dvui.dragPreStart(me.p, .{});
                            } else {
                                // Only start tracking the position on press if this
                                // is not a touch to prevent the value from
                                // "jumping" when entering text mode on a
                                // touch-tap event
                                p = me.p;
                            }
                        }
                    } else if (me.action == .release and me.button.pointer()) {
                        if (me.button.touch() and dvui.dragging(me.p) == null) {
                            text_mode = true;
                            refresh(null, @src(), b.data().id);
                        }
                        e.handled = true;
                        captureMouse(null);
                        dragEnd();
                        dataRemove(null, b.data().id, "_start_x");
                        dataRemove(null, b.data().id, "_start_v");
                    } else if (me.action == .motion and captured(b.data().id)) {
                        e.handled = true;
                        // If this is a touch motion we need to make sure to
                        // only update the value if we are exceeding the
                        // drag threshold to prevent the value from jumping while
                        // entering text mode via a non-drag touch-tap
                        if (!me.button.touch() or dvui.dragging(me.p) != null) {
                            p = me.p;
                        }
                    } else if (me.action == .position) {
                        dvui.cursorSet(.arrow);
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

            try knobrs.r.fill(options.corner_radiusGet().scale(knobrs.s), options.color(.fill_press));
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

    try rs.r.fill(options.corner_radiusGet().scale(rs.s), options.color(.fill));

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
    try part.fill(options.corner_radiusGet().scale(rs.s), options.color(.accent));
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
    try rs.r.fill(opts.corner_radiusGet().scale(rs.s), opts.color(.border));

    if (focused) {
        try rs.r.stroke(opts.corner_radiusGet().scale(rs.s), 2 * rs.s, opts.color(.accent), .{});
    }

    var fill: Options.ColorAsk = .fill;
    if (pressed) {
        fill = .fill_press;
    } else if (hovered) {
        fill = .fill_hover;
    }

    var options = opts;
    if (checked) {
        options = opts.override(themeGet().style_accent);
        try rs.r.insetAll(0.5 * rs.s).fill(opts.corner_radiusGet().scale(rs.s), options.color(fill));
    } else {
        try rs.r.insetAll(rs.s).fill(opts.corner_radiusGet().scale(rs.s), options.color(fill));
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

        const path: []const Point = &.{
            .{ .x = x - third, .y = y - third },
            .{ .x = x, .y = y },
            .{ .x = x + third * 2, .y = y - third * 2 },
        };
        try pathStroke(path, thick, options.color(.text), .{ .endcap_style = .square });
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
    try rs.r.fill(Rect.all(1000), opts.color(.border));

    if (focused) {
        try rs.r.stroke(Rect.all(1000), 2 * rs.s, opts.color(.accent), .{});
    }

    var fill: Options.ColorAsk = .fill;
    if (pressed) {
        fill = .fill_press;
    } else if (hovered) {
        fill = .fill_hover;
    }

    if (active) {
        try rs.r.insetAll(0.5 * rs.s).fill(Rect.all(1000), opts.color(.accent));
    } else {
        try rs.r.insetAll(rs.s).fill(Rect.all(1000), opts.color(fill));
    }

    if (active) {
        const thick = @max(1.0, rs.r.w / 6);

        const p = Point{ .x = rs.r.x + rs.r.w / 2, .y = rs.r.y + rs.r.h / 2 };
        try pathStroke(&.{p}, thick, opts.color(fill), .{});
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
        try rs.r.outsetAll(1).stroke(te.data().options.corner_radiusGet(), 3 * rs.s, dvui.themeGet().color_err, .{ .after = true });
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

    const atlas_size: Size = .{ .w = @floatFromInt(fce.texture_atlas.width), .h = @floatFromInt(fce.texture_atlas.height) };

    var bytes_seen: usize = 0;
    var utf8 = (try std.unicode.Utf8View.init(opts.text)).iterator();
    var last_codepoint: u32 = 0;
    var last_glyph_index: u32 = 0;
    while (utf8.nextCodepoint()) |codepoint| {
        const gi = try fce.glyphInfoGet(@as(u32, @intCast(codepoint)), opts.font.name);

        // kerning
        if (last_codepoint != 0) {
            if (useFreeType) {
                if (last_glyph_index == 0) last_glyph_index = c.FT_Get_Char_Index(fce.face, last_codepoint);
                const glyph_index: u32 = c.FT_Get_Char_Index(fce.face, codepoint);
                var kern: c.FT_Vector = undefined;
                FontCacheEntry.intToError(c.FT_Get_Kerning(fce.face, last_glyph_index, glyph_index, c.FT_KERNING_DEFAULT, &kern)) catch |err| {
                    log.warn("renderText freetype error {!} trying to FT_Get_Kerning font {s} codepoints {d} {d}\n", .{ err, opts.font.name, last_codepoint, codepoint });
                    return error.freetypeError;
                };
                last_glyph_index = glyph_index;

                const kern_x: f32 = @as(f32, @floatFromInt(kern.x)) / 64.0;

                x += kern_x;
            } else {
                const kern_adv: c_int = c.stbtt_GetCodepointKernAdvance(&fce.face, @as(c_int, @intCast(last_codepoint)), @as(c_int, @intCast(codepoint)));
                const kern_x = fce.scaleFactor * @as(f32, @floatFromInt(kern_adv));

                x += kern_x;
            }
        }
        last_codepoint = codepoint;

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
        v.uv[0] = gi.uv[0] + gi.w / atlas_size.w;
        try vtx.append(v);

        v.pos.y = y + (gi.topBearing + gi.h) * target_fraction;
        sel_max_y = @max(sel_max_y, v.pos.y);
        v.uv[1] = gi.uv[1] + gi.h / atlas_size.h;
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

        v.pos.x = x + @as(f32, @floatFromInt(kv.value_ptr.texture_atlas.width));
        v.uv[0] = 1;
        try vtx.append(v);

        v.pos.y = y + offset + @as(f32, @floatFromInt(kv.value_ptr.texture_atlas.height));
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

        offset += @as(f32, @floatFromInt(kv.value_ptr.texture_atlas.height));
    }
}

/// Create a texture that can be rendered with renderTexture().  pixels is RGBA premultiplied alpha.
///
/// Remember to destroy the texture at some point, see textureDestroyLater().
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn textureCreate(pixels: [*]u8, width: u32, height: u32, interpolation: enums.TextureInterpolation) Texture {
    return currentWindow().backend.textureCreate(pixels, width, height, interpolation);
}

/// Create a texture that can be rendered with renderTexture() and drawn to
/// with renderTarget().  Starts transparent (all zero).
///
/// Remember to destroy the texture at some point, see textureDestroyLater().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureCreateTarget(width: u32, height: u32, interpolation: enums.TextureInterpolation) !Texture {
    return try currentWindow().backend.textureCreateTarget(width, height, interpolation);
}

/// Read pixels from texture created with textureCreateTarget().
///
/// Returns pixels allocated by arena.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureRead(arena: std.mem.Allocator, texture: Texture) ![]u8 {
    const size: usize = texture.width * texture.height * 4;
    const pixels = try arena.alloc(u8, size);
    errdefer arena.free(pixels);

    try currentWindow().backend.textureRead(texture, pixels.ptr);

    return pixels;
}

/// Destroy a texture created with textureCreate() or textureCreateTarget() at
/// the end of the frame.
///
/// While backend.textureDestroy() immediately destroys the texture, this
/// function deferres the destruction until the end of the frame, so it is safe
/// to use even in a subwindow where rendering is deferred.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureDestroyLater(texture: Texture) void {
    currentWindow().texture_trash.append(texture) catch |err| {
        dvui.log.err("textureDestroyLater got {!}\n", .{err});
    };
}

pub const RenderTarget = struct {
    texture: ?Texture,
    offset: Point,
    rendering: bool = true,
};

/// Change where dvui renders.  Can pass output from textureCreateTarget() or
/// null for the screen.  Returns the previous target/offset.
///
/// offset will be subtracted from all dvui rendering, useful as the point on
/// the screen the texture will map to.
///
/// Useful for caching expensive renders or to save a render for export.  See
/// Picture.
///
/// Only valid between `Window.begin`and `Window.end`.
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

pub fn renderTexture(tex: Texture, rs: RectScale, opts: RenderTextureOptions) !void {
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

    const entry = TextureCacheEntry{ .texture = texture };
    try cw.texture_cache.put(hash, entry);

    return entry;
}

pub fn renderImage(name: []const u8, image_bytes: []const u8, rs: RectScale, rotation: f32, colormod: Color) !void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    const tce = imageTexture(name, image_bytes) catch return;
    try renderTexture(tce.texture, rs, .{ .rotation = rotation, .colormod = colormod });
}

/// Captures dvui drawing to part of the screen in a texture.
pub const Picture = struct {
    r: Rect, // physical pixels captured
    texture: dvui.Texture = undefined,
    target: dvui.RenderTarget = undefined,

    /// Begin recording drawing to the physical pixels in rect (enlarged to pixel boundaries).
    ///
    /// Returns null in case of failure (e.g. if backend does not support texture targets, if the passed rect is empty ...).
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn start(rect: Rect) ?Picture {
        if (rect.empty()) {
            log.err("Picture.start() was called with an empty rect", .{});
            return null;
        }
        var ret: Picture = .{ .r = rect };

        // enlarge texture to pixels boundaries
        const x_start = @floor(ret.r.x);
        const x_end = @ceil(ret.r.x + ret.r.w);
        ret.r.x = x_start;
        ret.r.w = @round(x_end - x_start);

        const y_start = @floor(ret.r.y);
        const y_end = @ceil(ret.r.y + ret.r.h);
        ret.r.y = y_start;
        ret.r.h = @round(y_end - y_start);

        ret.texture = dvui.textureCreateTarget(@intFromFloat(ret.r.w), @intFromFloat(ret.r.h), .linear) catch return null;
        ret.target = dvui.renderTarget(.{ .texture = ret.texture, .offset = ret.r.topLeft() });

        return ret;
    }

    /// Stop recording and return texture (only valid this frame).
    pub fn stop(self: *Picture) dvui.Texture {
        _ = dvui.renderTarget(self.target);

        // copy pixels to regular texture
        const px = dvui.textureRead(dvui.currentWindow().arena(), self.texture) catch null;
        if (px) |pixels| {
            defer dvui.currentWindow().arena().free(pixels);

            dvui.textureDestroyLater(self.texture);
            self.texture = dvui.textureCreate(pixels.ptr, self.texture.width, self.texture.height, .linear);
        }

        // render the texture so you see the picture this frame
        dvui.renderTexture(self.texture, .{ .r = self.r }, .{}) catch {};

        dvui.textureDestroyLater(self.texture);
        return self.texture;
    }
};

pub const pngFromTextureOptions = struct {
    /// Physical size of image, pixels per meter added to png pHYs chunk.
    /// 0 => don't write the pHYs chunk
    /// null => dvui will use 72 dpi (2834.64 px/m) times windowNaturalScale()
    resolution: ?u32 = null,
};

/// Make a png encoded image from a texture.
///
/// Gives bytes of a png file (allocated by arena) with contents from texture.
pub fn pngFromTexture(arena: std.mem.Allocator, texture: Texture, opts: pngFromTextureOptions) ![]u8 {
    const px = try textureRead(arena, texture);

    var len: c_int = undefined;
    const png_bytes = c.stbi_write_png_to_mem(px.ptr, @intCast(texture.width * 4), @intCast(texture.width), @intCast(texture.height), 4, &len);
    arena.free(px);

    // 4 bytes: length of data
    // 4 bytes: "pHYs"
    // 9 bytes: data (2 4-byte numbers + 1 byte units)
    // 4 bytes: crc
    const pHYs_size = 4 + 4 + 9 + 4;
    var extra: usize = pHYs_size;
    var p_buf: [pHYs_size]u8 = undefined;
    var res: u32 = 0;
    if (opts.resolution) |r| {
        res = r;
    } else {
        res = @intFromFloat(@round(windowNaturalScale() * 72.0 / 0.0254));
    }

    if (res == 0) {
        extra = 0;
    } else {
        std.mem.writeInt(u32, p_buf[0..][0..4], 9, .big); // length of data
        @memcpy(p_buf[4..][0..4], "pHYs");
        std.mem.writeInt(u32, p_buf[8..][0..4], res, .big); // res horizontal
        std.mem.writeInt(u32, p_buf[12..][0..4], res, .big); // res vertical
        p_buf[16] = 1; // 1 => pixels/meter

        // crc includes "pHYs" and data
        std.mem.writeInt(u32, p_buf[17..][0..4], png_crc32(p_buf[4..][0..13]), .big);
    }

    var ret = try arena.alloc(u8, @as(usize, @intCast(len)) + extra);

    // find byte index of end of IDHR chunk
    const idhr_data_len: u32 = std.mem.readInt(u32, png_bytes[8..][0..4], .big);

    // 8 bytes PNG magic bytes
    // 4 bytes length of IDHR data
    // 4 bytes "IDHR"
    // IDHR data
    // 4 bytes IDHR crc
    const split: u32 = 8 + 4 + 4 + idhr_data_len + 4;

    @memcpy(ret[0..split], png_bytes[0..split]);
    if (res != 0) {
        @memcpy(ret[split..][0..extra], &p_buf);
    }
    @memcpy(ret[split + extra ..], png_bytes[split..@as(usize, @intCast(len))]);

    if (wasm) {
        backend.dvui_c_free(png_bytes);
    } else {
        c.free(png_bytes);
    }

    return ret;
}

/// Calculate a PNG crc value.
///
/// Code from stb_image_write.h
pub fn png_crc32(buf: []u8) u32 {
    // zig fmt: off
    const crc_table = [256]u32 {
      0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
      0x0eDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
      0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
      0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
      0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
      0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
      0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
      0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
      0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
      0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
      0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
      0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
      0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
      0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
      0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
      0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
      0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
      0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
      0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
      0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
      0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
      0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
      0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
      0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
      0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
      0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
      0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
      0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
      0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
      0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
      0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
      0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D
    };
    // zig fmt: on

    var crc: u32 = ~@as(u32, 0);
    for (buf) |ch| {
        crc = (crc >> 8) ^ crc_table[ch ^ (crc & 0xff)];
    }
    return ~crc;
}

pub fn plot(src: std.builtin.SourceLocation, plot_opts: PlotWidget.InitOptions, opts: Options) !*PlotWidget {
    var ret = try currentWindow().arena().create(PlotWidget);
    ret.* = PlotWidget.init(src, plot_opts, opts);
    try ret.install();
    return ret;
}

pub fn plotXY(src: std.builtin.SourceLocation, plot_opts: PlotWidget.InitOptions, thick: f32, xs: []const f64, ys: []const f64, opts: Options) !void {
    const defaults: Options = .{ .padding = .{} };
    var p = try dvui.plot(src, plot_opts, defaults.override(opts));

    var s1 = p.line();
    for (xs, ys) |x, y| {
        try s1.point(x, y);
    }

    try s1.stroke(thick, opts.color(.accent));

    s1.deinit();
    p.deinit();
}

test {
    std.testing.refAllDecls(@This());
}
