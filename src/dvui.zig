const builtin = @import("builtin");
const std = @import("std");
const tvg = @import("tinyvg/tinyvg.zig");

const math = std.math;
const fnv = std.hash.Fnv1a_32;

pub const Backend = @import("Backend.zig");
pub const Color = @import("Color.zig");
pub const Examples = @import("Examples.zig");
pub const Font = @import("Font.zig");
pub const Options = @import("Options.zig");
pub const Point = @import("Point.zig");
pub const Rect = @import("Rect.zig");
pub const ScrollInfo = @import("ScrollInfo.zig");
pub const Size = @import("Size.zig");
pub const Theme = @import("Theme.zig");
pub const Vertex = @import("Vertex.zig");
pub const bitstream_vera = @import("fonts/bitstream_vera.zig");
pub const entypo = @import("icons/entypo.zig");
pub const Adwaita = @import("themes/Adwaita.zig");

pub const enums = @import("enums.zig");

const c = @cImport({
    @cInclude("freetype/ftadvanc.h");
    @cInclude("freetype/ftbbox.h");
    @cInclude("freetype/ftbitmap.h");
    @cInclude("freetype/ftcolor.h");
    @cInclude("freetype/ftlcdfil.h");
    @cInclude("freetype/ftsizes.h");
    @cInclude("freetype/ftstroke.h");
    @cInclude("freetype/fttrigon.h");
});

pub const Error = error{ OutOfMemory, InvalidUtf8, freetypeError, tvgError };

const log = std.log.scoped(.dvui);
const dvui = @This();

var current_window: ?*Window = null;

pub fn currentWindow() *Window {
    return current_window orelse unreachable;
}

pub var log_debug: bool = false;
pub fn debug(comptime str: []const u8, args: anytype) void {
    if (log_debug) {
        log.debug(str, args);
    }
}

pub fn themeGet() *Theme {
    return currentWindow().theme;
}

pub fn themeSet(theme: *Theme) void {
    currentWindow().theme = theme;
}

pub fn toggleDebugWindow() void {
    var cw = currentWindow();
    cw.debug_window_show = !cw.debug_window_show;
}

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

pub fn frameTimeNS() i128 {
    return currentWindow().frame_time_ns;
}

const GlyphInfo = struct {
    minx: f32,
    maxx: f32,
    advance: f32,
    miny: f32,
    maxy: f32,
    uv: @Vector(2, f32),
};

const FontCacheEntry = struct {
    used: bool = true,
    face: c.FT_Face,
    height: f32,
    ascent: f32,
    glyph_info: std.AutoHashMap(u32, GlyphInfo),
    texture_atlas: *anyopaque,
    texture_atlas_size: Size,
    texture_atlas_regen: bool,

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
        h.update(std.mem.asBytes(&font.ttf_bytes.ptr));
        h.update(std.mem.asBytes(&font.size));
        return h.final();
    }

    pub fn glyphInfoGet(self: *FontCacheEntry, codepoint: u32, font_name: []const u8) !GlyphInfo {
        if (self.glyph_info.get(codepoint)) |gi| {
            return gi;
        }

        FontCacheEntry.intToError(c.FT_Load_Char(self.face, codepoint, @as(i32, @bitCast(LoadFlags{ .render = false })))) catch |err| {
            std.debug.print("glyphInfoGet: freetype error {!} font {s} codepoint {d}\n", .{ err, font_name, codepoint });
            return error.freetypeError;
        };

        const m = self.face.*.glyph.*.metrics;
        const minx = @as(f32, @floatFromInt(m.horiBearingX)) / 64.0;
        const miny = self.ascent - @as(f32, @floatFromInt(m.horiBearingY)) / 64.0;

        const gi = GlyphInfo{
            .minx = @floor(minx),
            .maxx = @ceil(minx + @as(f32, @floatFromInt(m.width)) / 64.0),
            .advance = @ceil(@as(f32, @floatFromInt(m.horiAdvance)) / 64.0),
            .miny = @floor(miny),
            .maxy = @ceil(miny + @as(f32, @floatFromInt(m.height)) / 64.0),
            .uv = .{ 0, 0 },
        };

        // new glyph, need to regen texture atlas on next render
        //std.debug.print("new glyph {}\n", .{codepoint});
        self.texture_atlas_regen = true;

        try self.glyph_info.put(codepoint, gi);
        return gi;
    }
};

pub fn fontCacheGet(font: Font) !*FontCacheEntry {
    var cw = currentWindow();
    const fontHash = FontCacheEntry.hash(font);
    if (cw.font_cache.getPtr(fontHash)) |fce| {
        fce.used = true;
        return fce;
    }

    //std.debug.print("FontCacheGet creating font size {d} name \"{s}\"\n", .{font.size, font.name});

    var face: c.FT_Face = undefined;
    var args: c.FT_Open_Args = undefined;
    args.flags = @as(u32, @bitCast(FontCacheEntry.OpenFlags{ .memory = true }));
    args.memory_base = font.ttf_bytes.ptr;
    args.memory_size = @as(u31, @intCast(font.ttf_bytes.len));
    FontCacheEntry.intToError(c.FT_Open_Face(cw.ft2lib, &args, 0, &face)) catch |err| {
        std.debug.print("fontCacheGet: freetype error {!} trying to FT_Open_Face font {s}\n", .{ err, font.name });
        return error.freetypeError;
    };

    const pixel_size = @as(u32, @intFromFloat(font.size));
    FontCacheEntry.intToError(c.FT_Set_Pixel_Sizes(face, pixel_size, pixel_size)) catch |err| {
        std.debug.print("fontCacheGet: freetype error {!} trying to FT_Set_Pixel_Sizes font {s}\n", .{ err, font.name });
        return error.freetypeError;
    };

    const ascender = @as(f32, @floatFromInt(face.*.ascender)) / 64.0;
    const ss = @as(f32, @floatFromInt(face.*.size.*.metrics.y_scale)) / 0x10000;
    const ascent = ascender * ss;
    const height = @as(f32, @floatFromInt(face.*.size.*.metrics.height)) / 64.0;
    //std.debug.print("fontcache size {d} ascender {d} scale {d} ascent {d} height {d}\n", .{ font.size, ascender, ss, ascent, height });

    // make debug texture atlas so we can see if something later goes wrong
    const size = .{ .w = 10, .h = 10 };
    var pixels = try cw.arena.alloc(u8, @as(usize, @intFromFloat(size.w * size.h)) * 4);
    @memset(pixels, 255);

    const entry = FontCacheEntry{
        .face = face,
        .height = @ceil(height),
        .ascent = @floor(ascent),
        .glyph_info = std.AutoHashMap(u32, GlyphInfo).init(cw.gpa),
        .texture_atlas = cw.backend.textureCreate(pixels, @as(u32, @intFromFloat(size.w)), @as(u32, @intFromFloat(size.h))),
        .texture_atlas_size = size,
        .texture_atlas_regen = true,
    };
    try cw.font_cache.put(fontHash, entry);

    return cw.font_cache.getPtr(fontHash).?;
}

const IconCacheEntry = struct {
    texture: *anyopaque,
    size: Size,
    used: bool = true,

    pub fn hash(tvg_bytes: []const u8, height: u32) u32 {
        var h = fnv.init();
        h.update(std.mem.asBytes(&tvg_bytes.ptr));
        h.update(std.mem.asBytes(&height));
        return h.final();
    }
};

pub fn iconWidth(name: []const u8, tvg_bytes: []const u8, height: f32) !f32 {
    if (height == 0) return 0.0;
    var stream = std.io.fixedBufferStream(tvg_bytes);
    var parser = tvg.parse(currentWindow().arena, stream.reader()) catch |err| {
        std.debug.print("iconWidth: Tinyvg error {!} parsing icon {s}\n", .{ err, name });
        return error.tvgError;
    };
    defer parser.deinit();

    return height * @as(f32, @floatFromInt(parser.header.width)) / @as(f32, @floatFromInt(parser.header.height));
}

pub fn iconTexture(name: []const u8, tvg_bytes: []const u8, height: u32) !IconCacheEntry {
    var cw = currentWindow();
    const icon_hash = IconCacheEntry.hash(tvg_bytes, height);

    if (cw.icon_cache.getPtr(icon_hash)) |ice| {
        ice.used = true;
        return ice.*;
    }

    _ = try currentWindow().arena.create(u8);
    var image = tvg.rendering.renderBuffer(
        cw.arena,
        cw.arena,
        tvg.rendering.SizeHint{ .height = height },
        @as(tvg.rendering.AntiAliasing, @enumFromInt(2)),
        tvg_bytes,
    ) catch |err| {
        std.debug.print("iconTexture: Tinyvg error {!} rendering icon {s} at height {d}\n", .{ err, name, height });
        return error.tvgError;
    };
    defer image.deinit(cw.arena);

    var pixels: []u8 = undefined;
    pixels.ptr = @as([*]u8, @ptrCast(image.pixels.ptr));
    pixels.len = image.pixels.len * 4;

    const texture = cw.backend.textureCreate(pixels, image.width, image.height);

    //std.debug.print("created icon texture \"{s}\" ask height {d} size {d}x{d}\n", .{ name, height, image.width, image.height });

    const entry = IconCacheEntry{ .texture = texture, .size = .{ .w = @as(f32, @floatFromInt(image.width)), .h = @as(f32, @floatFromInt(image.height)) } };
    try cw.icon_cache.put(icon_hash, entry);

    return entry;
}

pub const RenderCmd = struct {
    clip: Rect,
    snap: bool,
    cmd: union(enum) {
        text: renderTextOptions,
        debug_font_atlases: struct {
            rs: RectScale,
            color: Color,
        },
        icon: struct {
            name: []const u8,
            tvg_bytes: []const u8,
            rs: RectScale,
            rotation: f32,
            colormod: Color,
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

pub fn focusedSubwindowId() u32 {
    const cw = currentWindow();
    const sw = cw.subwindowFocused();
    return sw.id;
}

pub fn focusSubwindow(subwindow_id: ?u32, event_num: ?u16) void {
    const cw = currentWindow();
    const winId = subwindow_id orelse cw.subwindow_currentId;
    if (cw.focused_subwindowId != winId) {
        cw.focused_subwindowId = winId;
        refresh();
        if (event_num) |en| {
            for (cw.subwindows.items) |*sw| {
                if (cw.focused_subwindowId == sw.id) {
                    focusRemainingEvents(en, sw.id, sw.focused_widgetId);
                    break;
                }
            }
        }
    }
}

pub fn focusRemainingEvents(event_num: u16, focusWindowId: u32, focusWidgetId: ?u32) void {
    var evts = events();
    var k: usize = 0;
    while (k < evts.len) : (k += 1) {
        var e: *Event = &evts[k];
        if (e.num > event_num and e.focus_windowId != null) {
            e.focus_windowId = focusWindowId;
            e.focus_widgetId = focusWidgetId;
        }
    }
}

pub fn raiseSubwindow(subwindow_id: u32) void {
    const cw = currentWindow();
    // don't check against subwindows[0] - that's that main window
    var items = cw.subwindows.items[1..];
    for (items, 0..) |sw, i| {
        if (sw.id == subwindow_id) {
            if (sw.stay_above_parent != null) {
                //std.debug.print("raiseSubwindow: tried to raise a subwindow {x} with stay_above_parent set\n", .{subwindow_id});
                return;
            }

            if (i == (items.len - 1)) {
                // already on top
                return;
            }

            // move it to the end, also move any stay_above_parent subwindows
            // directly on top of it as well - we know from above that the
            // first window does not have stay_above_parent so this loop ends
            var first = true;
            while (first or items[i].stay_above_parent != null) {
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

    std.debug.print("raiseSubwindow: couldn't find subwindow {x}\n", .{subwindow_id});
    return;
}

// Focus a widget in the given subwindow (if null, the current subwindow).  If
// you are focusing in the context of processing events, you can pass the
// event_num so that remaining events get the new focus.
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
                refresh();
            }
            break;
        }
    }
}

// Return the id of the focused widget (if any) in the focused subwindow.
pub fn focusedWidgetId() ?u32 {
    const cw = currentWindow();
    for (cw.subwindows.items) |*sw| {
        if (cw.focused_subwindowId == sw.id) {
            return sw.focused_widgetId;
        }
    }

    return null;
}

// Return the id of the focused widget (if any) in the current subwindow (the
// one that widgets are being added to).
pub fn focusedWidgetIdInCurrentSubwindow() ?u32 {
    const cw = currentWindow();
    const sw = cw.subwindowCurrent();
    return sw.focused_widgetId;
}

pub const Cursor = enum(u8) {
    arrow,
    ibeam,
    wait,
    wait_arrow,
    crosshair,
    arrow_nw_se,
    arrow_ne_sw,
    arrow_w_e,
    arrow_n_s,
    arrow_all,
    bad,
    hand,
};

pub fn cursorGetDragging() ?Cursor {
    const cw = currentWindow();
    return cw.cursor_dragging;
}

pub fn cursorSet(cursor: Cursor) void {
    const cw = currentWindow();
    cw.cursor_requested = cursor;
}

pub fn pathAddPoint(p: Point) !void {
    const cw = currentWindow();
    try cw.path.append(p);
}

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
    try pathAddArc(tl, rad.x, math.pi * 1.5, math.pi, @fabs(tl.y - bl.y) < 0.5);
    try pathAddArc(bl, rad.h, math.pi, math.pi * 0.5, @fabs(bl.x - br.x) < 0.5);
    try pathAddArc(br, rad.w, math.pi * 0.5, 0, @fabs(br.y - tr.y) < 0.5);
    try pathAddArc(tr, rad.y, math.pi * 2.0, math.pi * 1.5, @fabs(tr.x - tl.x) < 0.5);
}

pub fn pathAddArc(center: Point, rad: f32, start: f32, end: f32, skip_end: bool) !void {
    if (rad == 0) {
        try pathAddPoint(center);
        return;
    }

    // how close our points will be to the perfect circle
    const err = 0.1;

    // angle that has err error between circle and segments
    const theta = math.acos(rad / (rad + err));

    // make sure we never have less than 4 segments
    // so a full circle can't be less than a diamond
    const num_segments = @max(@ceil((start - end) / theta), 4.0);

    const step = (start - end) / num_segments;

    const num = @as(u32, @intFromFloat(num_segments));
    var a: f32 = start;
    var i: u32 = 0;
    while (i < num) : (i += 1) {
        try pathAddPoint(Point{ .x = center.x + rad * @cos(a), .y = center.y + rad * @sin(a) });
        a -= step;
    }

    if (!skip_end) {
        a = end;
        try pathAddPoint(Point{ .x = center.x + rad * @cos(a), .y = center.y + rad * @sin(a) });
    }
}

pub fn pathFillConvex(col: Color) !void {
    const cw = currentWindow();
    if (cw.path.items.len < 3) {
        cw.path.clearAndFree();
        return;
    }

    if (!cw.rendering) {
        var path_copy = std.ArrayList(Point).init(cw.arena);
        try path_copy.appendSlice(cw.path.items);
        var cmd = RenderCmd{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .pathFillConvex = .{ .path = path_copy, .color = col } } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);

        cw.path.clearAndFree();
        return;
    }

    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena, cw.path.items.len * 2);
    defer vtx.deinit();
    const idx_count = (cw.path.items.len - 2) * 3 + cw.path.items.len * 6;
    var idx = try std.ArrayList(u32).initCapacity(cw.arena, idx_count);
    defer idx.deinit();
    var col_trans = col;
    col_trans.a = 0;

    var i: usize = 0;
    while (i < cw.path.items.len) : (i += 1) {
        const ai = (i + cw.path.items.len - 1) % cw.path.items.len;
        const bi = i % cw.path.items.len;
        const ci = (i + 1) % cw.path.items.len;
        const aa = cw.path.items[ai];
        const bb = cw.path.items[bi];
        const cc = cw.path.items[ci];

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

        // outer vertex
        v.pos.x = bb.x + halfnorm.x;
        v.pos.y = bb.y + halfnorm.y;
        v.col = col_trans;
        try vtx.append(v);

        // indexes for fill
        if (i > 1) {
            try idx.append(@as(u32, @intCast(0)));
            try idx.append(@as(u32, @intCast(ai * 2)));
            try idx.append(@as(u32, @intCast(bi * 2)));
        }

        // indexes for aa fade from inner to outer
        try idx.append(@as(u32, @intCast(ai * 2)));
        try idx.append(@as(u32, @intCast(ai * 2 + 1)));
        try idx.append(@as(u32, @intCast(bi * 2)));
        try idx.append(@as(u32, @intCast(ai * 2 + 1)));
        try idx.append(@as(u32, @intCast(bi * 2 + 1)));
        try idx.append(@as(u32, @intCast(bi * 2)));
    }

    cw.backend.renderGeometry(null, vtx.items, idx.items);

    cw.path.clearAndFree();
}

pub const EndCapStyle = enum {
    none,
    square,
};

pub fn pathStroke(closed_in: bool, thickness: f32, endcap_style: EndCapStyle, col: Color) !void {
    try pathStrokeAfter(false, closed_in, thickness, endcap_style, col);
}

pub fn pathStrokeAfter(after: bool, closed_in: bool, thickness: f32, endcap_style: EndCapStyle, col: Color) !void {
    const cw = currentWindow();

    if (cw.path.items.len == 0) {
        return;
    }

    if (after or !cw.rendering) {
        var path_copy = std.ArrayList(Point).init(cw.arena);
        try path_copy.appendSlice(cw.path.items);
        var cmd = RenderCmd{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .pathStroke = .{ .path = path_copy, .closed = closed_in, .thickness = thickness, .endcap_style = endcap_style, .color = col } } };

        var sw = cw.subwindowCurrent();
        if (after) {
            try sw.render_cmds_after.append(cmd);
        } else {
            try sw.render_cmds.append(cmd);
        }

        cw.path.clearAndFree();
    } else {
        try pathStrokeRaw(closed_in, thickness, endcap_style, col);
    }
}

pub fn pathStrokeRaw(closed_in: bool, thickness: f32, endcap_style: EndCapStyle, col: Color) !void {
    const cw = currentWindow();

    if (cw.path.items.len == 1) {
        // draw a circle with radius thickness at that point
        const center = cw.path.items[0];

        // remove old path so we don't have a center point
        cw.path.clearAndFree();

        try pathAddArc(center, thickness, math.pi * 2.0, 0, true);
        try pathFillConvex(col);
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
    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena, vtx_count);
    defer vtx.deinit();
    var idx_count = (cw.path.items.len - 1) * 18;
    if (closed) {
        idx_count += 18;
    } else {
        idx_count += 8 * 3;
    }
    var idx = try std.ArrayList(u32).initCapacity(cw.arena, idx_count);
    defer idx.deinit();
    var col_trans = col;
    col_trans.a = 0;

    var vtx_start: usize = 0;
    var i: usize = 0;
    while (i < cw.path.items.len) : (i += 1) {
        const ai = (i + cw.path.items.len - 1) % cw.path.items.len;
        const bi = i % cw.path.items.len;
        const ci = (i + 1) % cw.path.items.len;
        const aa = cw.path.items[ai];
        var bb = cw.path.items[bi];
        const cc = cw.path.items[ci];

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

                v.pos.x = bb.x - halfnorm.x * (thickness + 1.0) + diffbc.x;
                v.pos.y = bb.y - halfnorm.y * (thickness + 1.0) + diffbc.y;
                v.col = col_trans;
                try vtx.append(v);

                v.pos.x = bb.x + halfnorm.x * (thickness + 1.0) + diffbc.x;
                v.pos.y = bb.y + halfnorm.y * (thickness + 1.0) + diffbc.y;
                v.col = col_trans;
                try vtx.append(v);

                // add indexes for endcap fringe
                try idx.append(@as(u32, @intCast(0)));
                try idx.append(@as(u32, @intCast(vtx_start)));
                try idx.append(@as(u32, @intCast(vtx_start + 1)));

                try idx.append(@as(u32, @intCast(0)));
                try idx.append(@as(u32, @intCast(1)));
                try idx.append(@as(u32, @intCast(vtx_start)));

                try idx.append(@as(u32, @intCast(1)));
                try idx.append(@as(u32, @intCast(vtx_start)));
                try idx.append(@as(u32, @intCast(vtx_start + 2)));

                try idx.append(@as(u32, @intCast(1)));
                try idx.append(@as(u32, @intCast(vtx_start + 2)));
                try idx.append(@as(u32, @intCast(vtx_start + 2 + 1)));
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

        // side 1 AA vertex
        v.pos.x = bb.x - halfnorm.x * (thickness + 1.0);
        v.pos.y = bb.y - halfnorm.y * (thickness + 1.0);
        v.col = col_trans;
        try vtx.append(v);

        // side 2 inner vertex
        v.pos.x = bb.x + halfnorm.x * thickness;
        v.pos.y = bb.y + halfnorm.y * thickness;
        v.col = col;
        try vtx.append(v);

        // side 2 AA vertex
        v.pos.x = bb.x + halfnorm.x * (thickness + 1.0);
        v.pos.y = bb.y + halfnorm.y * (thickness + 1.0);
        v.col = col_trans;
        try vtx.append(v);

        if (closed or ((i + 1) != cw.path.items.len)) {
            // indexes for fill
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4)));

            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4)));

            // indexes for aa fade from inner to outer side 1
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 1)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4 + 1)));

            try idx.append(@as(u32, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4 + 1)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4)));

            // indexes for aa fade from inner to outer side 2
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 3)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4 + 3)));

            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + ci * 4 + 3)));
        } else if (!closed and (i + 1) == cw.path.items.len) {
            // add 2 extra vertexes for endcap fringe
            v.pos.x = bb.x - halfnorm.x * (thickness + 1.0) - diffab.x;
            v.pos.y = bb.y - halfnorm.y * (thickness + 1.0) - diffab.y;
            v.col = col_trans;
            try vtx.append(v);

            v.pos.x = bb.x + halfnorm.x * (thickness + 1.0) - diffab.x;
            v.pos.y = bb.y + halfnorm.y * (thickness + 1.0) - diffab.y;
            v.col = col_trans;
            try vtx.append(v);

            // add indexes for endcap fringe
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 1)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 4)));

            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 4)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 2)));

            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 4)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 5)));

            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 2)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 3)));
            try idx.append(@as(u32, @intCast(vtx_start + bi * 4 + 5)));
        }
    }

    cw.backend.renderGeometry(null, vtx.items, idx.items);

    cw.path.clearAndFree();
}

pub fn subwindowAdd(id: u32, rect: Rect, modal: bool, stay_above_parent: ?u32) !void {
    const cw = currentWindow();

    for (cw.subwindows.items) |*sw| {
        if (id == sw.id) {
            // this window was here previously, just update data, so it stays in the same place in the stack
            sw.used = true;
            sw.rect = rect;
            sw.modal = modal;
            sw.stay_above_parent = stay_above_parent;

            if (sw.render_cmds.items.len > 0 or sw.render_cmds_after.items.len > 0) {
                std.debug.print("dvui: subwindowAdd {x} is clearing some drawing commands (did you try to draw between subwindowCurrentSet and subwindowAdd?)\n", .{id});
            }

            sw.render_cmds = std.ArrayList(RenderCmd).init(cw.arena);
            sw.render_cmds_after = std.ArrayList(RenderCmd).init(cw.arena);
            return;
        }
    }

    // haven't seen this window before
    const sw = Window.Subwindow{ .id = id, .rect = rect, .modal = modal, .stay_above_parent = stay_above_parent, .render_cmds = std.ArrayList(RenderCmd).init(cw.arena), .render_cmds_after = std.ArrayList(RenderCmd).init(cw.arena) };
    if (stay_above_parent) |subwin_id| {
        // it wants to be above subwin_id
        var i: usize = 0;
        while (i < cw.subwindows.items.len and cw.subwindows.items[i].id != subwin_id) {
            i += 1;
        }

        if (i < cw.subwindows.items.len) {
            i += 1;
        }

        // i points just past subwin_id, go until we run out of subwindows that want to be on top of this subwin_id
        while (i < cw.subwindows.items.len and cw.subwindows.items[i].stay_above_parent == subwin_id) {
            i += 1;
        }

        // i points just past all subwindows that want to be on top of this subwin_id
        try cw.subwindows.insert(i, sw);
    } else {
        // just put it on the top
        try cw.subwindows.append(sw);
    }
}

pub fn subwindowCurrentSet(id: u32) u32 {
    const cw = currentWindow();
    const ret = cw.subwindow_currentId;
    cw.subwindow_currentId = id;
    return ret;
}

pub fn subwindowCurrentId() u32 {
    const cw = currentWindow();
    return cw.subwindow_currentId;
}

pub fn dragPreStart(p: Point, cursor: ?Cursor, offset: Point) void {
    const cw = currentWindow();
    cw.drag_state = .prestart;
    cw.drag_pt = p;
    cw.drag_offset = offset;
    cw.cursor_dragging = cursor;
}

pub fn dragStart(p: Point, cursor: ?Cursor, offset: Point) void {
    const cw = currentWindow();
    cw.drag_state = .dragging;
    cw.drag_pt = p;
    cw.drag_offset = offset;
    cw.cursor_dragging = cursor;
}

pub fn dragOffset() Point {
    const cw = currentWindow();
    return cw.drag_offset;
}

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
            if (@fabs(dps.x) > 3 or @fabs(dps.y) > 3) {
                cw.drag_pt = p;
                cw.drag_state = .dragging;
                return dp;
            } else {
                return null;
            }
        },
    }
}

pub fn dragEnd() void {
    const cw = currentWindow();
    cw.drag_state = .none;
}

pub fn mouseTotalMotion() Point {
    const cw = currentWindow();
    return Point.diff(cw.mouse_pt, cw.mouse_pt_prev);
}

pub fn captureMouse(id: ?u32) void {
    const cw = currentWindow();
    cw.captureID = id;
    if (id != null) {
        cw.captured_last_frame = true;
    } else {
        dragEnd();
    }
}

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
                return;
            }
        }
    }
}

pub fn captured(id: u32) bool {
    return id == captureMouseId();
}

pub fn captureMouseId() ?u32 {
    return currentWindow().captureID;
}

pub fn clipGet() Rect {
    return currentWindow().clipRect;
}

pub fn clip(new: Rect) Rect {
    const cw = currentWindow();
    var ret = cw.clipRect;
    clipSet(cw.clipRect.intersect(new));
    return ret;
}

pub fn clipSet(r: Rect) void {
    currentWindow().clipRect = r;
}

pub fn snapToPixelsSet(snap: bool) bool {
    const cw = currentWindow();
    const old = cw.snap_to_pixels;
    cw.snap_to_pixels = snap;
    return old;
}

pub fn snapToPixels() bool {
    const cw = currentWindow();
    return cw.snap_to_pixels;
}

pub fn refresh() void {
    currentWindow().refresh();
}

// caller responsible for calling backendFree on result.ptr
pub fn clipboardText() []u8 {
    const cw = currentWindow();
    return cw.backend.clipboardText();
}

pub fn clipboardTextSet(text: []u8) error{OutOfMemory}!void {
    const cw = currentWindow();
    try cw.backend.clipboardTextSet(text);
}

pub fn backendFree(p: *anyopaque) void {
    const cw = currentWindow();
    cw.backend.free(p);
}

pub fn seconds_since_last_frame() f32 {
    return currentWindow().secs_since_last_frame;
}

pub fn FPS() f32 {
    return currentWindow().FPS();
}

pub fn parentGet() Widget {
    return currentWindow().wd.parent;
}

pub fn parentSet(w: Widget) Widget {
    const cw = currentWindow();
    const ret = cw.wd.parent;
    cw.wd.parent = w;
    return ret;
}

pub fn popupSet(p: ?*PopupWidget) ?*PopupWidget {
    const cw = currentWindow();
    const ret = cw.popup_current;
    cw.popup_current = p;
    return ret;
}

pub fn menuGet() ?*MenuWidget {
    return currentWindow().menu_current;
}

pub fn menuSet(m: ?*MenuWidget) ?*MenuWidget {
    var cw = currentWindow();
    const ret = cw.menu_current;
    cw.menu_current = m;
    return ret;
}

pub fn windowRect() Rect {
    return currentWindow().wd.rect;
}

pub fn windowRectPixels() Rect {
    return currentWindow().rect_pixels;
}

pub fn windowNaturalScale() f32 {
    return currentWindow().natural_scale;
}

pub fn firstFrame(id: u32) bool {
    return minSizeGet(id) == null;
}

pub fn minSizeGet(id: u32) ?Size {
    var cw = currentWindow();
    const saved_size = cw.min_sizes.getPtr(id);
    if (saved_size) |ss| {
        debug("{x} minSizeGet {}", .{ id, ss.size });
        return ss.size;
    } else {
        debug("{x} minSizeGet null", .{id});
        return null;
    }
}

pub fn minSizeSet(id: u32, s: Size) !void {
    debug("{x} minSizeSet {}", .{ id, s });
    var cw = currentWindow();
    if (try cw.min_sizes.fetchPut(id, .{ .size = s })) |ss| {
        if (ss.value.used) {
            std.debug.print("dvui: id {x} already used this frame (highlighting), may need to pass .id_extra = <loop index> into Options\n", .{id});
            cw.debug_widget_id = id;
        }
    }
}

pub fn hashSrc(src: std.builtin.SourceLocation, id_extra: usize) u32 {
    var hash = fnv.init();
    hash.update(src.file);
    hash.update(std.mem.asBytes(&src.line));
    hash.update(std.mem.asBytes(&src.column));
    hash.update(std.mem.asBytes(&id_extra));
    return hash.final();
}

pub fn hashIdKey(id: u32, key: []const u8) u32 {
    var h = fnv.init();
    h.value = id;
    h.update(key);
    return h.final();
}

const DataOffset = struct {
    begin: u32,
    end: u32,
};

/// Set key/value pair for given id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
///
/// If you want to store the contents of a slice, use dataSetSlice().
pub fn dataSet(win: ?*Window, id: u32, key: []const u8, data: anytype) void {
    dataSetAdvanced(win, id, key, data, false);
}

/// Set key/value pair for given id, copying the slice contents. Can be passed
/// a slice or pointer to an array.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the data to.
pub fn dataSetSlice(win: ?*Window, id: u32, key: []const u8, data: anytype) void {
    const dt = @typeInfo(@TypeOf(data));
    if (dt == .Pointer and dt.Pointer.size == .Slice) {
        dataSetAdvanced(win, id, key, data, true);
    } else if (dt == .Pointer and dt.Pointer.size == .One and @typeInfo(dt.Pointer.child) == .Array) {
        dataSetAdvanced(win, id, key, @as([]@typeInfo(dt.Pointer.child).Array.child, @constCast(data)), true);
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
pub fn dataSetAdvanced(win: ?*Window, id: u32, key: []const u8, data: anytype, comptime copy_slice: bool) void {
    if (win) |w| {
        // we are being called from non gui thread or outside begin()/end()
        w.dataSetAdvanced(id, key, data, copy_slice);
    } else {
        if (current_window) |cw| {
            cw.dataSetAdvanced(id, key, data, copy_slice);
        } else {
            @panic("dataSet: current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
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
    if (dt != .Pointer or dt.Pointer.size != .Slice) {
        @compileError("dataGetSlice needs a slice, given " ++ @typeName(T));
    }

    if (dataGetInternal(win, id, key, T, true)) |bytes| {
        if (dt.Pointer.sentinel) |sentinel| {
            return @as([:@as(*const dt.Pointer.child, @alignCast(@ptrCast(sentinel))).*]align(@alignOf(dt.Pointer.child)) dt.Pointer.child, @alignCast(@ptrCast(std.mem.bytesAsSlice(dt.Pointer.child, bytes[0 .. bytes.len - @sizeOf(dt.Pointer.child)]))));
        } else {
            return @as([]align(@alignOf(dt.Pointer.child)) dt.Pointer.child, @alignCast(std.mem.bytesAsSlice(dt.Pointer.child, bytes)));
        }
    } else {
        return null;
    }
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
            @panic("dataGet: current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
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
            @panic("dataRemove: current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
        }
    }
}

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

pub fn placeIn(avail: Rect, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    var size = min_size;

    // you never get larger than available
    size.w = @min(size.w, avail.w);
    size.h = @min(size.h, avail.h);

    if (e.horizontal()) {
        size.w = avail.w;
    }

    if (e.vertical()) {
        size.h = avail.h;
    }

    var r = avail.shrinkToSize(size);
    r.x = avail.x + g.x * (avail.w - r.w);
    r.y = avail.y + g.y * (avail.h - r.h);

    return r;
}

pub fn events() []Event {
    return currentWindow().events.items;
}

pub const EventMatchOptions = struct {
    id: u32,
    r: Rect,
    id_capture: ?u32 = null,
    cleanup: bool = false,
};

// returns true if the given event should normally be processed according to
// the options given
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
                if (capture_id.? != (opts.id_capture orelse opts.id)) {
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
    }

    return true;
}

// Animations
// start_time and end_time are relative to the current frame time.  At the
// start of each frame both are reduced by the micros since the last frame.
//
// An animation will be active thru a frame where its end_time is <= 0, and be
// deleted at the beginning of the next frame.  See Spinner for an example of
// how to have a seemless continuous animation.

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

pub fn animation(id: u32, key: []const u8, a: Animation) void {
    var cw = currentWindow();
    const h = hashIdKey(id, key);
    cw.animations.put(h, a) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("animation: got {!} for id {x} key {s}\n", .{ err, id, key });
        },
    };
}

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

// returns true only on the frame where the animation expired
pub fn animationDone(id: u32, key: []const u8) bool {
    if (animationGet(id, key)) |a| {
        if (a.end_time <= 0) {
            return true;
        }
    }

    return false;
}

pub fn timer(id: u32, micros: i32) !void {
    try currentWindow().timer(id, micros);
}

pub fn timerGet(id: u32) ?i32 {
    if (animationGet(id, "_timer")) |a| {
        return a.end_time;
    } else {
        return null;
    }
}

pub fn timerExists(id: u32) bool {
    return timerGet(id) != null;
}

// returns true only on the frame where the timer expired
pub fn timerDone(id: u32) bool {
    if (timerGet(id)) |end_time| {
        if (end_time <= 0) {
            return true;
        }
    }

    return false;
}

const TabIndex = struct {
    windowId: u32,
    widgetId: u32,
    tabIndex: u16,
};

pub fn tabIndexSet(widget_id: u32, tab_index: ?u16) !void {
    var cw = currentWindow();
    const ti = TabIndex{ .windowId = cw.subwindow_currentId, .widgetId = widget_id, .tabIndex = (tab_index orelse math.maxInt(u16)) };
    try cw.tab_index.append(ti);
}

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
    var newtab: u16 = 0;
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

// maps to OS window
pub const Window = struct {
    const Self = @This();

    pub const Subwindow = struct {
        id: u32 = 0,
        rect: Rect = Rect{},
        focused_widgetId: ?u32 = null,
        render_cmds: std.ArrayList(RenderCmd),
        render_cmds_after: std.ArrayList(RenderCmd),
        used: bool = true,
        modal: bool = false,
        stay_above_parent: ?u32 = null,
    };

    const SavedSize = struct {
        size: Size,
        used: bool = true,
    };

    const SavedData = struct {
        used: bool = true,
        alignment: u8,
        data: []u8,

        type_str: (if (std.debug.runtime_safety) []const u8 else void) = undefined,
        copy_slice: if (std.debug.runtime_safety) bool else void = undefined,

        pub fn free(self: *const SavedData, allocator: std.mem.Allocator) void {
            allocator.rawFree(self.data, @ctz(self.alignment), @returnAddress());
        }
    };

    backend: Backend,
    previous_window: ?*Window = null,

    // list of subwindows including base, later windows are on top of earlier
    // windows
    subwindows: std.ArrayList(Subwindow),

    // id of the subwindow widgets are being added to
    subwindow_currentId: u32 = 0,

    // id of the subwindow that has focus
    focused_subwindowId: u32 = 0,

    snap_to_pixels: bool = true,
    alpha: f32 = 1.0,

    events: std.ArrayList(Event) = undefined,
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

    frame_time_ns: i128 = 0,
    loop_wait_target: ?i128 = null,
    loop_wait_target_event: bool = false,
    loop_target_slop: i32 = 0,
    loop_target_slop_frames: i32 = 0,
    frame_times: [30]u32 = [_]u32{0} ** 30,

    secs_since_last_frame: f32 = 0,
    extra_frames_needed: u8 = 0,
    clipRect: Rect = Rect{},

    menu_current: ?*MenuWidget = null,
    popup_current: ?*PopupWidget = null,
    theme: *Theme = &Adwaita.light,

    min_sizes: std.AutoHashMap(u32, SavedSize),
    data_mutex: std.Thread.Mutex,
    datas: std.AutoHashMap(u32, SavedData),
    animations: std.AutoHashMap(u32, Animation),
    tab_index_prev: std.ArrayList(TabIndex),
    tab_index: std.ArrayList(TabIndex),
    font_cache: std.AutoHashMap(u32, FontCacheEntry),
    icon_cache: std.AutoHashMap(u32, IconCacheEntry),
    dialog_mutex: std.Thread.Mutex,
    dialogs: std.ArrayList(Dialog),
    toasts: std.ArrayList(Toast),

    ft2lib: c.FT_Library = undefined,

    cursor_requested: Cursor = .arrow,
    cursor_dragging: ?Cursor = null,

    wd: WidgetData = undefined,
    rect_pixels: Rect = Rect{}, // pixels
    natural_scale: f32 = 1.0,
    content_scale: f32 = 1.0, // can set seperately but gets folded into natural_scale
    next_widget_ypos: f32 = 0,

    captureID: ?u32 = null,
    captured_last_frame: bool = false,

    gpa: std.mem.Allocator,
    _arena: std.heap.ArenaAllocator,
    arena: std.mem.Allocator = undefined,
    path: std.ArrayList(Point) = undefined,
    rendering: bool = false,

    debug_window_show: bool = false,
    debug_widget_id: u32 = 0,
    debug_info_name_rect: []u8 = "",
    debug_info_src_id_extra: []u8 = "",
    debug_under_mouse: bool = false,
    debug_under_mouse_esc_needed: bool = false,
    debug_under_mouse_quitting: bool = false,
    debug_under_mouse_info: []u8 = "",

    pub fn init(
        src: std.builtin.SourceLocation,
        id_extra: usize,
        gpa: std.mem.Allocator,
        backend: Backend,
    ) !Self {
        const hashval = hashSrc(src, id_extra);
        const arena = std.heap.ArenaAllocator.init(gpa);

        var self = Self{
            .gpa = gpa,
            ._arena = arena,
            .subwindows = std.ArrayList(Subwindow).init(gpa),
            .min_sizes = std.AutoHashMap(u32, SavedSize).init(gpa),
            .data_mutex = std.Thread.Mutex{},
            .datas = std.AutoHashMap(u32, SavedData).init(gpa),
            .animations = std.AutoHashMap(u32, Animation).init(gpa),
            .tab_index_prev = std.ArrayList(TabIndex).init(gpa),
            .tab_index = std.ArrayList(TabIndex).init(gpa),
            .font_cache = std.AutoHashMap(u32, FontCacheEntry).init(gpa),
            .icon_cache = std.AutoHashMap(u32, IconCacheEntry).init(gpa),
            .dialog_mutex = std.Thread.Mutex{},
            .dialogs = std.ArrayList(Dialog).init(gpa),
            .toasts = std.ArrayList(Toast).init(gpa),
            .wd = WidgetData{ .id = hashval, .init_options = .{ .subwindow = true }, .options = .{} },
            .backend = backend,
        };

        const winSize = self.backend.windowSize();
        const pxSize = self.backend.pixelSize();
        self.content_scale = self.backend.contentScale();
        const total_scale = self.content_scale * pxSize.w / winSize.w;
        if (total_scale >= 2.0) {
            self.snap_to_pixels = false;
        }

        errdefer self.deinit();

        self.focused_subwindowId = self.wd.id;
        self.frame_time_ns = std.time.nanoTimestamp();

        FontCacheEntry.intToError(c.FT_Init_FreeType(&self.ft2lib)) catch |err| {
            std.debug.print("init: freetype error {!} trying to init freetype library\n", .{err});
            return error.freetypeError;
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        var it = self.datas.iterator();
        while (it.next()) |item| item.value_ptr.free(self.gpa);

        self.subwindows.deinit();
        self.min_sizes.deinit();
        self.datas.deinit();
        self.animations.deinit();
        self.tab_index_prev.deinit();
        self.tab_index.deinit();
        self.font_cache.deinit();
        self.icon_cache.deinit();
        self.dialogs.deinit();
        self._arena.deinit();
    }

    pub fn refresh(self: *Self) void {
        self.extra_frames_needed = 1;
    }

    pub fn addEventKey(self: *Self, event: Event.Key) !bool {
        if (self.debug_under_mouse and self.debug_under_mouse_esc_needed and event.action == .down and event.code == .escape) {
            // a left click will stop the debug stuff from following the mouse,
            // but need to stop it at the end of the frame when we've gotten
            // the info
            self.debug_under_mouse_quitting = true;
            return true;
        }

        self.positionMouseEventRemove();

        self.event_num += 1;
        try self.events.append(Event{
            .num = self.event_num,
            .evt = .{ .key = event },
            .focus_windowId = self.focused_subwindowId,
            .focus_widgetId = self.subwindowFocused().focused_widgetId,
        });

        const ret = (self.wd.id != self.focused_subwindowId);
        try self.positionMouseEventAdd();
        return ret;
    }

    pub fn addEventText(self: *Self, text: []const u8) !bool {
        self.positionMouseEventRemove();

        self.event_num += 1;
        try self.events.append(Event{
            .num = self.event_num,
            .evt = .{ .text = try self.arena.dupe(u8, text) },
            .focus_windowId = self.focused_subwindowId,
            .focus_widgetId = self.subwindowFocused().focused_widgetId,
        });

        const ret = (self.wd.id != self.focused_subwindowId);
        try self.positionMouseEventAdd();
        return ret;
    }

    pub fn addEventMouseMotion(self: *Self, x: f32, y: f32) !bool {
        self.positionMouseEventRemove();

        const newpt = (Point{ .x = x, .y = y }).scale(self.natural_scale / self.content_scale);
        //std.debug.print("mouse motion {d} {d} -> {d} {d}\n", .{ x, y, newpt.x, newpt.y });
        const dp = newpt.diff(self.mouse_pt);
        self.mouse_pt = newpt;
        const winId = self.windowFor(self.mouse_pt);

        // TODO: focus follows mouse
        // - generate a .focus event here instead of just doing focusWindow(winId, null);
        // - how to make it optional?

        self.event_num += 1;
        try self.events.append(Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = .motion,
                .button = .none,
                .p = self.mouse_pt,
                .floating_win = winId,
                .data = .{ .motion = dp },
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    pub fn addEventMouseButton(self: *Self, b: enums.Button, action: Event.Mouse.Action) !bool {
        return addEventPointer(self, b, action, null);
    }

    pub fn addEventPointer(self: *Self, b: enums.Button, action: Event.Mouse.Action, xynorm: ?Point) !bool {
        if (self.debug_under_mouse and !self.debug_under_mouse_esc_needed and action == .press and b.pointer()) {
            // a left click or touch will stop the debug stuff from following
            // the mouse, but need to stop it at the end of the frame when
            // we've gotten the info
            self.debug_under_mouse_quitting = true;
            return true;
        }

        self.positionMouseEventRemove();

        if (xynorm) |xyn| {
            const newpt = (Point{ .x = xyn.x * self.wd.rect.w, .y = xyn.y * self.wd.rect.h }).scale(self.natural_scale / self.content_scale);
            self.mouse_pt = newpt;
        }

        const winId = self.windowFor(self.mouse_pt);

        if (action == .press and b.pointer()) {
            // normally the focus event is what focuses windows, but since the
            // base window is instantiated before events are added, it has to
            // do any event processing as the events come in, right now
            if (winId == self.wd.id) {
                // focus the window here so any more key events get routed
                // properly
                focusSubwindow(self.wd.id, null);
            }

            // add focus event
            self.event_num += 1;
            try self.events.append(Event{ .num = self.event_num, .evt = .{
                .mouse = .{
                    .action = .focus,
                    .button = b,
                    .p = self.mouse_pt,
                    .floating_win = winId,
                },
            } });
        }

        self.event_num += 1;
        try self.events.append(Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = action,
                .button = b,
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    pub fn addEventMouseWheel(self: *Self, ticks: f32) !bool {
        self.positionMouseEventRemove();

        const winId = self.windowFor(self.mouse_pt);

        var ticks_adj = ticks;
        // TODO: some real solution to interpreting the mouse wheel across OSes
        if (builtin.target.os.tag == .linux or builtin.target.os.tag == .windows) {
            ticks_adj = ticks * 20;
        }
        //std.debug.print("mouse wheel {d}\n", .{ticks_adj});

        self.event_num += 1;
        try self.events.append(Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .action = .wheel_y,
                .button = .none,
                .p = self.mouse_pt,
                .floating_win = winId,
                .data = .{ .wheel_y = ticks_adj },
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    pub fn addEventTouchMotion(self: *Self, finger: enums.Button, xnorm: f32, ynorm: f32, dxnorm: f32, dynorm: f32) !bool {
        self.positionMouseEventRemove();

        const newpt = (Point{ .x = xnorm * self.wd.rect.w, .y = ynorm * self.wd.rect.h }).scale(self.natural_scale / self.content_scale);
        //std.debug.print("touch motion {} {d} {d}\n", .{ finger, newpt.x, newpt.y });
        self.mouse_pt = newpt;

        const dp = (Point{ .x = dxnorm * self.wd.rect.w, .y = dynorm * self.wd.rect.h }).scale(self.natural_scale / self.content_scale);

        const winId = self.windowFor(self.mouse_pt);

        self.event_num += 1;
        try self.events.append(Event{ .num = self.event_num, .evt = .{
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
        var new_time = @max(self.frame_time_ns, std.time.nanoTimestamp());

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
                self.loop_target_slop_frames = @max(1, self.loop_target_slop_frames + 1);
                self.loop_target_slop += self.loop_target_slop_frames;
            } else if (new_time < target) {
                // woke up sooner than expected
                self.loop_target_slop_frames = @min(-1, self.loop_target_slop_frames - 1);
                self.loop_target_slop += self.loop_target_slop_frames;

                // since we are early, spin a bit to guarantee that we never run before
                // the target
                //var i: usize = 0;
                //var first_time = new_time;
                while (new_time < target) {
                    //i += 1;
                    std.time.sleep(0);
                    new_time = @max(self.frame_time_ns, std.time.nanoTimestamp());
                }

                //if (i > 0) {
                //  std.debug.print("    begin {d} spun {d} {d}us\n", .{self.loop_target_slop, i, @divFloor(new_time - first_time, 1000)});
                //}
            }
        }

        //std.debug.print("beginWait {d:6}\n", .{self.loop_target_slop});
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
        const so_far_nanos = @max(self.frame_time_ns, std.time.nanoTimestamp()) - self.frame_time_ns;
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
            std.time.sleep(min_micros * 1000);
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
        self.debug_info_name_rect = "";
        self.debug_info_src_id_extra = "";
        if (self.debug_under_mouse) {
            if (self.debug_under_mouse_info.len > 0) {
                self.gpa.free(self.debug_under_mouse_info);
            }
            self.debug_under_mouse_info = "";
        }

        _ = self._arena.reset(.retain_capacity);
        const arena = self._arena.allocator();
        self.arena = arena;

        self.path = std.ArrayList(Point).init(arena);

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

        self.event_num = 0;
        self.events = std.ArrayList(Event).init(arena);

        for (self.frame_times, 0..) |_, i| {
            if (i == (self.frame_times.len - 1)) {
                self.frame_times[i] = 0;
            } else {
                self.frame_times[i] = self.frame_times[i + 1] +| micros_since_last;
            }
        }

        {
            var deadSizes = std.ArrayList(u32).init(arena);
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

            var deadDatas = std.ArrayList(u32).init(arena);
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

        //std.debug.print("window size {d} x {d} renderer size {d} x {d} scale {d}", .{ self.wd.rect.w, self.wd.rect.h, self.rect_pixels.w, self.rect_pixels.h, self.natural_scale });

        try subwindowAdd(self.wd.id, self.wd.rect, false, null);

        _ = subwindowCurrentSet(self.wd.id);

        self.extra_frames_needed -|= 1;
        self.secs_since_last_frame = @as(f32, @floatFromInt(micros_since_last)) / 1_000_000;

        {
            const micros: i32 = if (micros_since_last > math.maxInt(i32)) math.maxInt(i32) else @as(i32, @intCast(micros_since_last));
            var deadAnimations = std.ArrayList(u32).init(arena);
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
                        self.refresh();
                    }
                }
            }

            for (deadAnimations.items) |id| {
                _ = self.animations.remove(id);
            }
        }

        {
            var deadFonts = std.ArrayList(u32).init(arena);
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
                _ = c.FT_Done_Face(tce.value.face);
            }

            //std.debug.print("font_cache {d}\n", .{self.font_cache.count()});
        }

        {
            var deadIcons = std.ArrayList(u32).init(arena);
            defer deadIcons.deinit();
            var it = self.icon_cache.iterator();
            while (it.next()) |kv| {
                if (kv.value_ptr.used) {
                    kv.value_ptr.used = false;
                } else {
                    try deadIcons.append(kv.key_ptr.*);
                }
            }

            for (deadIcons.items) |id| {
                const ice = self.icon_cache.fetchRemove(id).?;
                self.backend.textureDestroy(ice.value.texture);
            }

            //std.debug.print("icon_cache {d}\n", .{self.icon_cache.count()});
        }

        if (!self.captured_last_frame) {
            // widget that had capture went away, also end any drag that might
            // have been happening
            self.captureID = null;
            self.drag_state = .none;
        }
        self.captured_last_frame = false;

        self.wd.parent = self.widget();
        self.menu_current = null;

        self.next_widget_ypos = self.wd.rect.y;

        // We want a position mouse event to do mouse cursors.  It needs to be
        // final so if there was a drag end the cursor will still be set
        // correctly.  We don't know when the client gives us the last event,
        // so make our position event now, and addEvent* functions will remove
        // and re-add to keep it as the final event.
        try self.positionMouseEventAdd();

        if (self.inject_motion_event) {
            self.inject_motion_event = false;
            const pt = self.mouse_pt.scale(self.content_scale / self.natural_scale);
            _ = try self.addEventMouseMotion(pt.x, pt.y);
        }

        self.backend.begin(arena);
    }

    fn positionMouseEventAdd(self: *Self) !void {
        try self.events.append(.{ .evt = .{ .mouse = .{
            .action = .position,
            .button = .none,
            .p = self.mouse_pt,
            .floating_win = self.windowFor(self.mouse_pt),
        } } });
    }

    fn positionMouseEventRemove(self: *Self) void {
        const e = self.events.pop();
        if (e.evt != .mouse or e.evt.mouse.action != .position) {
            std.debug.print("dvui: positionMouseEventRemove removed a non-mouse or non-position event\n", .{});
        }
    }

    fn windowFor(self: *const Self, p: Point) u32 {
        var i = self.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &self.subwindows.items[i - 1];
            if (sw.modal or sw.rect.contains(p)) {
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

        std.debug.print("subwindowCurrent failed to find the current subwindow, returning base window\n", .{});
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

        std.debug.print("subwindowFocused failed to find the focused subwindow, returning base window\n", .{});
        return &self.subwindows.items[0];
    }

    // Return the cursor the gui wants.  Client code should cache this if
    // switching the platform's cursor is expensive.
    pub fn cursorRequested(self: *const Self) Cursor {
        if (self.drag_state == .dragging and self.cursor_dragging != null) {
            return self.cursor_dragging.?;
        } else {
            return self.cursor_requested;
        }
    }

    // Return the cursor the gui wants or null if mouse is not in gui windows.
    // Client code should cache this if switching the platform's cursor is
    // expensive.
    pub fn cursorRequestedFloating(self: *const Self) ?Cursor {
        if (self.captureID != null or self.windowFor(self.mouse_pt) != self.wd.id) {
            // gui owns the cursor if we have mouse capture or if the mouse is above
            // a floating window
            return self.cursorRequested();
        } else {
            // no capture, not above a floating window, so client owns the cursor
            return null;
        }
    }

    pub fn renderCommands(self: *Self, queue: *std.ArrayList(RenderCmd)) !void {
        self.rendering = true;
        defer self.rendering = false;
        for (queue.items) |*drc| {
            // don't need to reset these after because we reset them after
            // calling renderCommands
            currentWindow().snap_to_pixels = drc.snap;
            clipSet(drc.clip);
            switch (drc.cmd) {
                .text => |t| {
                    try renderText(t);
                },
                .debug_font_atlases => |t| {
                    try debugRenderFontAtlases(t.rs, t.color);
                },
                .icon => |i| {
                    try renderIcon(i.name, i.tvg_bytes, i.rs, i.rotation, i.colormod);
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

        queue.clearAndFree();
    }

    // data is copied into internal storage
    pub fn dataSetAdvanced(self: *Self, id: u32, key: []const u8, data_in: anytype, comptime copy_slice: bool) void {
        const hash = hashIdKey(id, key);

        const dt = @typeInfo(@TypeOf(data_in));
        const dt_type_str = @typeName(@TypeOf(data_in));
        var bytes: []const u8 = undefined;
        if (copy_slice) {
            bytes = std.mem.sliceAsBytes(data_in);
            if (dt.Pointer.sentinel != null) {
                bytes.len += @sizeOf(dt.Pointer.child);
            }
        } else {
            bytes = std.mem.asBytes(&data_in);
        }

        const alignment = comptime blk: {
            if (copy_slice) {
                break :blk dt.Pointer.alignment;
            } else {
                break :blk @alignOf(@TypeOf(data_in));
            }
        };

        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (self.datas.getPtr(hash)) |sd| {
            if (sd.data.len == bytes.len) {
                sd.used = true;
                if (std.debug.runtime_safety) {
                    sd.type_str = dt_type_str;
                    sd.copy_slice = copy_slice;
                }
                @memcpy(sd.data, bytes);
                return;
            } else {
                //std.debug.print("dataSet: already had data for id {x} key {s}, freeing previous data\n", .{ id, key });
                sd.free(self.gpa);
            }
        }

        var sd = SavedData{ .alignment = alignment, .data = self.gpa.allocWithOptions(u8, bytes.len, alignment, null) catch |err| switch (err) {
            error.OutOfMemory => {
                std.debug.print("dataSet: got {!} for id {x} key {s}\n", .{ err, id, key });
                return;
            },
        } };

        @memcpy(sd.data, bytes);

        if (std.debug.runtime_safety) {
            sd.type_str = dt_type_str;
            sd.copy_slice = copy_slice;
        }

        self.datas.put(hash, sd) catch |err| switch (err) {
            error.OutOfMemory => {
                std.debug.print("dataSet: got {!} for id {x} key {s}\n", .{ err, id, key });
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
            if (std.debug.runtime_safety) {
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

        self.refresh();

        return &self.dialog_mutex;
    }

    pub fn dialogRemove(self: *Self, id: u32) void {
        self.dialog_mutex.lock();
        defer self.dialog_mutex.unlock();

        for (self.dialogs.items, 0..) |*d, i| {
            if (d.id == id) {
                _ = self.dialogs.orderedRemove(i);
                self.refresh();
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
        // maybe cause a single frame and then expire
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

        self.refresh();

        return &self.dialog_mutex;
    }

    pub fn toastRemove(self: *Self, id: u32) void {
        self.dialog_mutex.lock();
        defer self.dialog_mutex.unlock();

        for (self.toasts.items, 0..) |*t, i| {
            if (t.id == id) {
                _ = self.toasts.orderedRemove(i);
                self.refresh();
                return;
            }
        }
    }

    // show any toasts that didn't have a subwindow_id set
    fn toastsShow(self: *Self) !void {
        var ti = dvui.toastsFor(null);
        if (ti) |*it| {
            var toast_win = FloatingWindowWidget.init(@src(), .{ .stay_above_parent = true }, .{ .background = false, .border = .{} });
            defer toast_win.deinit();

            toast_win.data().rect = dvui.placeIn(self.wd.rect, toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
            toast_win.autoSize();
            try toast_win.install(.{ .process_events = false });

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
            self.debug_under_mouse_quitting = false;
        }

        // disable so the widgets we are about to use to display this data
        // don't modify the data, otherwise our iterator will get corrupted and
        // even if you search for a widget here, the data won't be available
        var dum = self.debug_under_mouse;
        self.debug_under_mouse = false;
        defer self.debug_under_mouse = dum;

        var float = try dvui.floatingWindow(@src(), .{ .open_flag = &self.debug_window_show }, .{ .min_size_content = .{ .w = 300, .h = 400 } });
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
                .text = &buf,
            }, .{});
            te.deinit();

            self.debug_widget_id = std.fmt.parseInt(u32, std.mem.sliceTo(&buf, 0), 16) catch 0;
        }

        var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 80 } });
        try tl.addText(self.debug_info_name_rect, .{});
        try tl.addText("\n\n", .{});
        try tl.addText(self.debug_info_src_id_extra, .{});
        tl.deinit();

        if (try dvui.button(@src(), if (dum) "Stop (Or Left Click)" else "Debug Under Mouse (until click)", .{})) {
            dum = !dum;
        }

        if (try dvui.button(@src(), if (dum) "Stop (Or Press Esc)" else "Debug Under Mouse (until esc)", .{})) {
            dum = !dum;
            self.debug_under_mouse_esc_needed = dum;
        }

        var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false });
        defer scroll.deinit();

        var iter = std.mem.split(u8, self.debug_under_mouse_info, "\n");
        var i: usize = 0;
        while (iter.next()) |line| : (i += 1) {
            if (line.len > 0) {
                var hbox = try dvui.box(@src(), .horizontal, .{ .id_extra = i });
                defer hbox.deinit();

                if (try dvui.buttonIcon(@src(), 12, "find", entypo.magnifying_glass, .{})) {
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

        const oldsnap = self.snap_to_pixels;
        const oldclip = clipGet();
        for (self.subwindows.items) |*sw| {
            try self.renderCommands(&sw.render_cmds);
            try self.renderCommands(&sw.render_cmds_after);
        }
        clipSet(oldclip);
        self.snap_to_pixels = oldsnap;

        // events may have been tagged with a focus widget that never showed up, so
        // we wouldn't even get them bubbled
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.wd.id, .r = self.rect_pixels, .cleanup = true }))
                continue;

            // doesn't matter if we mark events has handled or not because this is
            // the end of the line for all events
            if (e.evt == .mouse) {
                if (e.evt.mouse.action == .focus) {
                    // unhandled click, clear focus
                    focusWidget(null, null, null);
                }
            } else if (e.evt == .key) {
                if (e.evt.key.code == .tab and e.evt.key.action == .down) {
                    if (e.evt.key.mod.shift()) {
                        tabIndexPrev(e.num);
                    } else {
                        tabIndexNext(e.num);
                    }
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

            self.refresh();
        }

        // Check that the final event was our synthetic mouse position event.
        // If one of the addEvent* functions forgot to add the synthetic mouse
        // event to the end this will print a debug message.
        self.positionMouseEventRemove();

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

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        var r = self.wd.rect;
        r.y = self.next_widget_ypos;
        r.h -= r.y;
        const ret = placeIn(r, minSize(id, min_size), e, g);
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

pub fn popup(src: std.builtin.SourceLocation, initialRect: Rect, opts: Options) !*PopupWidget {
    var ret = try currentWindow().arena.create(PopupWidget);
    ret.* = PopupWidget.init(src, initialRect, opts);
    try ret.install(.{});
    return ret;
}

pub const PopupWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .corner_radius = Rect.all(5),
        .border = Rect.all(1),
        .padding = Rect.all(4),
        .background = true,
        .color_style = .window,
    };

    wd: WidgetData = undefined,
    options: Options = undefined,
    prev_windowId: u32 = 0,
    parent_popup: ?*PopupWidget = null,
    have_popup_child: bool = false,
    menu: MenuWidget = undefined,
    initialRect: Rect = Rect{},
    prevClip: Rect = Rect{},
    scroll: ScrollAreaWidget = undefined,

    pub fn init(src: std.builtin.SourceLocation, initialRect: Rect, opts: Options) Self {
        var self = Self{};

        // options is really for our embedded MenuWidget, so save them for the
        // end of install()
        self.options = defaults.override(opts);

        // the popup itself doesn't have any styling, it comes from the
        // embedded MenuWidget
        // passing options.rect will stop WidgetData.init from calling
        // rectFor/minSizeForChild which is important because we are outside
        // normal layout
        self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{} });

        self.initialRect = initialRect;
        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());

        self.prev_windowId = subwindowCurrentSet(self.wd.id);
        self.parent_popup = popupSet(self);

        if (minSizeGet(self.wd.id)) |_| {
            self.wd.rect = Rect.fromPoint(self.initialRect.topleft());
            const ms = minSize(self.wd.id, self.options.min_sizeGet());
            self.wd.rect.w = ms.w;
            self.wd.rect.h = ms.h;
            self.wd.rect = placeOnScreen(windowRect(), self.initialRect, self.wd.rect);
        } else {
            self.wd.rect = placeOnScreen(windowRect(), self.initialRect, Rect.fromPoint(self.initialRect.topleft()));
            focusSubwindow(self.wd.id, null);

            // need a second frame to fit contents (FocusWindow calls refresh but
            // here for clarity)
            refresh();
        }

        const rs = self.wd.rectScale();

        try subwindowAdd(self.wd.id, rs.r, false, null);
        try self.wd.register("Popup", rs);

        // clip to just our window (using clipSet since we are not inside our parent)
        self.prevClip = clipGet();
        clipSet(rs.r);

        // we are using scroll to do border/background but floating windows
        // don't have margin, so turn that off
        self.scroll = ScrollAreaWidget.init(@src(), .{ .horizontal = .none }, self.options.override(.{ .margin = .{}, .expand = .both }));
        try self.scroll.install(.{});

        if (menuGet()) |pm| {
            pm.child_popup_rect = rs.r;
        }

        self.menu = MenuWidget.init(@src(), .{ .dir = .vertical, .submenus_activated_by_default = true }, self.options.strip().override(.{ .expand = .horizontal }));
        self.menu.parentSubwindowId = self.prev_windowId;
        try self.menu.install(.{});

        // if no widget in this popup has focus, make the menu have focus to handle keyboard events
        if (focusedWidgetIdInCurrentSubwindow() == null) {
            focusWidget(self.menu.wd.id, null, null);
        }
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        // popup does cleanup events, but not normal events
        switch (e.evt) {
            .close_popup => {
                self.wd.parent.processEvent(e, true);
            },
            else => {},
        }

        // otherwise popups don't bubble events
        _ = bubbling;
    }

    pub fn chainFocused(self: *Self, self_call: bool) bool {
        if (!self_call) {
            // if we got called by someone else, then we have a popup child
            self.have_popup_child = true;
        }

        var ret: bool = false;

        // we have to call chainFocused on our parent if we have one so we
        // can't return early

        if (self.wd.id == focusedSubwindowId()) {
            // we are focused
            ret = true;
        }

        if (self.parent_popup) |pp| {
            // we had a parent popup, is that focused
            if (pp.chainFocused(false)) {
                ret = true;
            }
        } else if (self.prev_windowId == focusedSubwindowId()) {
            // no parent popup, is our parent window focused
            ret = true;
        }

        return ret;
    }

    pub fn deinit(self: *Self) void {
        self.menu.deinit();
        self.scroll.deinit();

        self.options.min_size_content = self.scroll.si.virtual_size;
        self.wd.minSizeMax(self.options.min_sizeGet());

        const rs = self.wd.rectScale();
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.wd.id, .r = rs.r, .cleanup = true }))
                continue;

            if (e.evt == .mouse) {
                if (e.evt.mouse.action == .focus) {
                    // unhandled click, clear focus
                    focusWidget(null, null, null);
                }
            } else if (e.evt == .key) {
                // catch any tabs that weren't handled by widgets
                if (e.evt.key.code == .tab and e.evt.key.action == .down) {
                    e.handled = true;
                    if (e.evt.key.mod.shift()) {
                        tabIndexPrev(e.num);
                    } else {
                        tabIndexNext(e.num);
                    }
                }
            }
        }

        // check if a focus event is happening outside our window
        for (evts) |e| {
            if (!e.handled and e.evt == .mouse and e.evt.mouse.action == .focus) {
                var closeE = Event{ .evt = .{ .close_popup = .{} } };
                self.processEvent(&closeE, true);
            }
        }

        if (!self.have_popup_child and !self.chainFocused(true)) {
            // if a popup chain is open and the user focuses a different window
            // (not the parent of the popups), then we want to close the popups

            // only the last popup can do the check, you can't query the focus
            // status of children, only parents
            var closeE = Event{ .evt = .{ .close_popup = .{ .intentional = false } } };
            self.processEvent(&closeE, true);
        }

        self.wd.minSizeSetAndRefresh();

        // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

        _ = popupSet(self.parent_popup);
        _ = parentSet(self.wd.parent);
        _ = subwindowCurrentSet(self.prev_windowId);
        clipSet(self.prevClip);
    }
};

pub fn floatingWindow(src: std.builtin.SourceLocation, floating_opts: FloatingWindowWidget.InitOptions, opts: Options) !*FloatingWindowWidget {
    var ret = try currentWindow().arena.create(FloatingWindowWidget);
    ret.* = FloatingWindowWidget.init(src, floating_opts, opts);
    try ret.install(.{});
    return ret;
}

pub const FloatingWindowWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .corner_radius = Rect.all(5),
        .border = Rect.all(1),
        .background = true,
        .color_style = .window,
    };

    pub const InitOptions = struct {
        modal: bool = false,
        rect: ?*Rect = null,
        open_flag: ?*bool = null,
        stay_above_parent: bool = false,
        window_avoid: enum {
            none,

            // if we would spawn at the same position as an existing window,
            // move us downright a bit
            nudge,
        } = .none,
    };

    wd: WidgetData = undefined,
    init_options: InitOptions = undefined,
    options: Options = undefined,
    process_events: bool = true,
    prev_windowId: u32 = 0,
    layout: BoxWidget = undefined,
    prevClip: Rect = Rect{},
    auto_pos: bool = false,
    auto_size: bool = false,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        var self = Self{};

        // options is really for our embedded BoxWidget, so save them for the
        // end of install()
        self.options = defaults.override(opts);
        self.options.rect = null; // if the user passes in a rect, don't pass it to the BoxWidget

        // the floating window itself doesn't have any styling, it comes from
        // the embedded BoxWidget
        // passing options.rect will stop WidgetData.init from calling rectFor
        // which is important because we are outside normal layout
        self.wd = WidgetData.init(src, .{ .subwindow = true }, .{ .id_extra = opts.id_extra, .rect = .{} });

        self.init_options = init_opts;

        var autopossize = true;
        if (self.init_options.rect) |ior| {
            // user is storing the rect for us across open/close
            self.wd.rect = ior.*;
        } else if (opts.rect) |r| {
            // we were given a rect, just use that
            self.wd.rect = r;
            autopossize = false;
        } else {
            // we store the rect (only while the window is open)
            self.wd.rect = dataGet(null, self.wd.id, "_rect", Rect) orelse Rect{};
        }

        if (autopossize) {
            if (dataGet(null, self.wd.id, "_auto_size", @TypeOf(self.auto_size))) |as| {
                self.auto_size = as;
            } else {
                self.auto_size = (self.wd.rect.w == 0 and self.wd.rect.h == 0);
            }

            if (dataGet(null, self.wd.id, "_auto_pos", @TypeOf(self.auto_pos))) |ap| {
                self.auto_pos = ap;
            } else {
                self.auto_pos = (self.wd.rect.x == 0 and self.wd.rect.y == 0);
            }
        }

        if (minSizeGet(self.wd.id)) |min_size| {
            if (self.auto_size) {
                // only size ourselves once by default
                self.auto_size = false;

                var ms = Size.max(min_size, self.options.min_sizeGet());
                self.wd.rect.w = ms.w;
                self.wd.rect.h = ms.h;

                //std.debug.print("autosize to {}\n", .{self.wd.rect});
            }

            var prev_focus = windowRect();
            if (dataGet(null, self.wd.id, "_prev_focus_rect", Rect)) |r| {
                dataRemove(null, self.wd.id, "_prev_focus_rect");
                prev_focus = r;

                // second frame for us, but since new windows grab the
                // previously focused window rect, any focused window needs to
                // have a non-zero size
                focusSubwindow(self.wd.id, null);
            }

            if (self.auto_pos) {
                // only position ourselves once by default
                self.auto_pos = false;

                // center on prev_focus
                self.wd.rect.x = prev_focus.x + (prev_focus.w - self.wd.rect.w) / 2;
                self.wd.rect.y = prev_focus.y + (prev_focus.h - self.wd.rect.h) / 2;

                if (snapToPixels()) {
                    self.wd.rect.x = @round(self.wd.rect.x);
                    self.wd.rect.y = @round(self.wd.rect.y);
                }

                while (self.wd.rect.topleft().equals(prev_focus.topleft())) {
                    // if we ended up directly on top, nudge downright a bit
                    self.wd.rect.x += 24;
                    self.wd.rect.y += 24;
                }

                const cw = currentWindow();

                // we might nudge onto another window, so have to keep checking until we don't
                var nudge = true;
                while (nudge) {
                    nudge = false;
                    // don't check against subwindows[0] - that's that main window
                    for (cw.subwindows.items[1..]) |subw| {
                        if (subw.rect.topleft().equals(self.wd.rect.topleft())) {
                            self.wd.rect.x += 24;
                            self.wd.rect.y += 24;
                            nudge = true;
                        }
                    }

                    if (self.init_options.window_avoid == .nudge) {
                        continue;
                    } else {
                        break;
                    }
                }

                //std.debug.print("autopos to {}\n", .{self.wd.rect});
            }

            // always make sure we are on the screen
            var screen = windowRect();
            // okay if we are off the left or right but still see some
            const offleft = self.wd.rect.w - 48;
            screen.x -= offleft;
            screen.w += offleft + offleft;
            // okay if we are off the bottom but still see the top
            screen.h += self.wd.rect.h - 24;
            self.wd.rect = placeOnScreen(screen, .{}, self.wd.rect);
        }

        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        self.process_events = opts.process_events;

        if (firstFrame(self.wd.id)) {
            // write back before we hide ourselves for the first frame
            dataSet(null, self.wd.id, "_rect", self.wd.rect);
            if (self.init_options.rect) |ior| {
                // send rect back to user
                ior.* = self.wd.rect;
            }

            // there might be multiple new windows, so we aren't going to
            // switch focus until the second frame, which gives all the new
            // windows a chance to grab the previously focused rect

            const cw = currentWindow();
            dataSet(null, self.wd.id, "_prev_focus_rect", cw.subwindowFocused().rect);

            // need a second frame to fit contents
            refresh();

            // hide our first frame so the user doesn't see an empty window or
            // jump when we autopos/autosize - do this in install() because
            // animation stuff might be messing with out rect after init()
            self.wd.rect.w = 0;
            self.wd.rect.h = 0;
        }

        _ = parentSet(self.widget());
        self.prev_windowId = subwindowCurrentSet(self.wd.id);

        // reset clip to whole OS window
        // - if modal fade everything below us
        // - gives us all mouse events
        self.prevClip = clipGet();
        clipSet(windowRectPixels());

        captureMouseMaintain(self.wd.id);

        if (self.process_events) {
            // processEventsBefore can change self.wd.rect
            self.processEventsBefore();
        }

        const rs = self.wd.rectScale();
        try subwindowAdd(self.wd.id, rs.r, self.init_options.modal, if (self.init_options.stay_above_parent) self.prev_windowId else null);
        try self.wd.register("FloatingWindow", rs);

        if (self.init_options.modal) {
            // paint over everything below
            try pathAddRect(windowRectPixels(), Rect.all(0));
            var col = self.options.color(.text);
            col.a = if (themeGet().dark) 60 else 80;
            try pathFillConvex(col);
        }

        // clip to just our window
        clipSet(rs.r);

        // we are using BoxWidget to do border/background but floating windows
        // don't have margin, so turn that off
        self.layout = BoxWidget.init(@src(), .vertical, false, self.options.override(.{ .margin = .{}, .expand = .both }));
        try self.layout.install(.{});
    }

    pub fn processEventsBefore(self: *Self) void {
        const rs = self.wd.rectScale();
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.wd.id, .r = rs.r }))
                continue;

            if (e.evt == .mouse) {
                const me = e.evt.mouse;
                var corner: bool = false;
                const corner_size: f32 = if (me.button.touch()) 30 else 15;
                if (me.p.x > rs.r.x + rs.r.w - corner_size * rs.s and
                    me.p.y > rs.r.y + rs.r.h - corner_size * rs.s)
                {
                    // we are over the bottom-right resize corner
                    corner = true;
                }

                if (me.action == .focus) {
                    // focus but let the focus event propagate to widgets
                    focusSubwindow(self.wd.id, e.num);
                }

                if (captured(self.wd.id) or corner) {
                    if (me.action == .press and me.button.pointer()) {
                        // capture and start drag
                        captureMouse(self.wd.id);
                        dragStart(me.p, .arrow_all, Point.diff(rs.r.bottomRight(), me.p));
                        e.handled = true;
                    } else if (me.action == .release and me.button.pointer()) {
                        captureMouse(null); // stop drag and capture
                        e.handled = true;
                    } else if (me.action == .motion and captured(self.wd.id)) {
                        // move if dragging
                        if (dragging(me.p)) |dps| {
                            if (cursorGetDragging() == Cursor.crosshair) {
                                const dp = dps.scale(1 / rs.s);
                                self.wd.rect.x += dp.x;
                                self.wd.rect.y += dp.y;
                            } else if (cursorGetDragging() == Cursor.arrow_all) {
                                const p = me.p.plus(dragOffset()).scale(1 / rs.s);
                                self.wd.rect.w = @max(40, p.x - self.wd.rect.x);
                                self.wd.rect.h = @max(10, p.y - self.wd.rect.y);
                            }
                            // don't need refresh() because we're before drawing
                            e.handled = true;
                        }
                    } else if (me.action == .position) {
                        if (corner) {
                            cursorSet(.arrow_all);
                            e.handled = true;
                        }
                    }
                }
            }
        }
    }

    pub fn processEventsAfter(self: *Self) void {
        const rs = self.wd.rectScale();
        // duplicate processEventsBefore (minus corner stuff) because you could
        // have a click down, motion, and up in same frame and you wouldn't know
        // you needed to do anything until you got capture here
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.wd.id, .r = rs.r, .cleanup = true }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    switch (me.action) {
                        .focus => {
                            e.handled = true;
                            focusWidget(null, null, null);
                        },
                        .press => {
                            if (me.button.pointer()) {
                                e.handled = true;
                                // capture and start drag
                                captureMouse(self.wd.id);
                                dragPreStart(e.evt.mouse.p, .crosshair, Point{});
                            }
                        },
                        .release => {
                            if (me.button.pointer()) {
                                e.handled = true;
                                captureMouse(null); // stop drag and capture
                            }
                        },
                        .motion => {
                            if (captured(self.wd.id)) {
                                e.handled = true;
                                // move if dragging
                                if (dragging(me.p)) |dps| {
                                    if (cursorGetDragging() == Cursor.crosshair) {
                                        const dp = dps.scale(1 / rs.s);
                                        self.wd.rect.x += dp.x;
                                        self.wd.rect.y += dp.y;
                                    }
                                    refresh();
                                }
                            }
                        },
                        else => {},
                    }
                },
                .key => |ke| {
                    // catch any tabs that weren't handled by widgets
                    if (ke.code == .tab and ke.action == .down) {
                        e.handled = true;
                        if (ke.mod.shift()) {
                            tabIndexPrev(e.num);
                        } else {
                            tabIndexNext(e.num);
                        }
                    }
                },
                else => {},
            }
        }
    }

    // Call this to indicate that you want the window to resize to fit
    // contents.  The window's size next frame will fit the min size of the
    // contents from this frame.
    pub fn autoSize(self: *Self) void {
        self.auto_size = true;
    }

    pub fn close(self: *Self) void {
        if (self.init_options.open_flag) |of| {
            of.* = false;
        }
        refresh();
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        // floating window doesn't process events normally
        switch (e.evt) {
            .close_popup => |cp| {
                e.handled = true;
                if (cp.intentional) {
                    // when a popup is closed because the user chose to, the
                    // window that spawned it (which had focus previously)
                    // should become focused again
                    focusSubwindow(self.wd.id, null);
                }
            },
            else => {},
        }

        // floating windows don't bubble any events
        _ = bubbling;
    }

    pub fn deinit(self: *Self) void {
        if (self.process_events) {
            self.processEventsAfter();
        }

        self.layout.deinit();

        if (!firstFrame(self.wd.id)) {
            // if firstFrame, we already did this in install
            dataSet(null, self.wd.id, "_rect", self.wd.rect);
            if (self.init_options.rect) |ior| {
                // send rect back to user
                ior.* = self.wd.rect;
            }
        }

        dataSet(null, self.wd.id, "_auto_pos", self.auto_pos);
        dataSet(null, self.wd.id, "_auto_size", self.auto_size);
        self.wd.minSizeSetAndRefresh();

        // outside normal layout, don't call minSizeForChild or self.wd.minSizeReportToParent();

        _ = parentSet(self.wd.parent);
        _ = subwindowCurrentSet(self.prev_windowId);
        clipSet(self.prevClip);
    }
};

pub fn windowHeader(str: []const u8, right_str: []const u8, openflag: ?*bool) !void {
    var over = try dvui.overlay(@src(), .{ .expand = .horizontal });

    if (openflag) |of| {
        if (try dvui.buttonIcon(@src(), 16, "close", entypo.cross, .{ .corner_radius = Rect.all(16), .padding = Rect.all(0), .margin = Rect.all(2) })) {
            of.* = false;
        }
    }

    try dvui.labelNoFmt(@src(), str, .{ .gravity_x = 0.5, .gravity_y = 0.5, .expand = .horizontal, .font_style = .heading });
    try dvui.labelNoFmt(@src(), right_str, .{ .gravity_x = 1.0 });

    var evts = events();
    for (evts) |*e| {
        if (!eventMatch(e, .{ .id = over.wd.id, .r = over.wd.contentRectScale().r }))
            continue;

        if (e.evt == .mouse and e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
            raiseSubwindow(subwindowCurrentId());
        } else if (e.evt == .mouse and e.evt.mouse.action == .focus) {
            // our window will already be focused, but this prevents the window from clearing the focused widget
            e.handled = true;
        }
    }

    over.deinit();

    try dvui.separator(@src(), .{ .expand = .horizontal });
}

pub const DialogDisplayFn = *const fn (u32) Error!void;
pub const DialogCallAfterFn = *const fn (u32, enums.DialogResponse) Error!void;

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
        return .{ .id = id, .mutex = mutex };
    } else {
        if (current_window) |cw| {
            const parent = parentGet();
            const id = parent.extendId(src, id_extra);
            const mutex = try cw.dialogAdd(id, display);
            return .{ .id = id, .mutex = mutex };
        } else {
            @panic("dialogAdd: current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
        }
    }
}

pub fn dialogRemove(id: u32) void {
    const cw = currentWindow();
    cw.dialogRemove(id);
}

pub const DialogOptions = struct {
    id_extra: usize = 0,
    window: ?*Window = null,
    modal: bool = true,
    title: []const u8 = "",
    message: []const u8,
    displayFn: DialogDisplayFn = dialogDisplay,
    callafterFn: ?DialogCallAfterFn = null,
};

pub fn dialog(src: std.builtin.SourceLocation, opts: DialogOptions) !void {
    const id_mutex = try dialogAdd(opts.window, src, opts.id_extra, opts.displayFn);
    const id = id_mutex.id;
    dataSet(opts.window, id, "_modal", opts.modal);
    dataSetSlice(opts.window, id, "_title", opts.title);
    dataSetSlice(opts.window, id, "_message", opts.message);
    if (opts.callafterFn) |ca| {
        dataSet(opts.window, id, "_callafter", ca);
    }
    id_mutex.mutex.unlock();
}

pub fn dialogDisplay(id: u32) !void {
    const modal = dvui.dataGet(null, id, "_modal", bool) orelse {
        std.debug.print("Error: lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const title = dvui.dataGetSlice(null, id, "_title", []const u8) orelse {
        std.debug.print("Error: lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const message = dvui.dataGetSlice(null, id, "_message", []const u8) orelse {
        std.debug.print("Error: lost data for dialog {x}\n", .{id});
        dvui.dialogRemove(id);
        return;
    };

    const callafter = dvui.dataGet(null, id, "_callafter", DialogCallAfterFn);

    var win = try floatingWindow(@src(), .{ .modal = modal }, .{ .id_extra = id });
    defer win.deinit();

    var header_openflag = true;
    try dvui.windowHeader(title, "", &header_openflag);
    if (!header_openflag) {
        dvui.dialogRemove(id);
        if (callafter) |ca| {
            try ca(id, .closed);
        }
        return;
    }

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
    try tl.addText(message, .{});
    tl.deinit();

    if (try dvui.button(@src(), "Ok", .{ .gravity_x = 0.5, .gravity_y = 0.5, .tab_index = 1 })) {
        dvui.dialogRemove(id);
        if (callafter) |ca| {
            try ca(id, .ok);
        }
        return;
    }
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
        return .{ .id = id, .mutex = mutex };
    } else {
        if (current_window) |cw| {
            const parent = parentGet();
            const id = parent.extendId(src, id_extra);
            const mutex = try cw.toastAdd(id, subwindow_id, display, timeout);
            return .{ .id = id, .mutex = mutex };
        } else {
            @panic("toastAdd: current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
        }
    }
}

pub fn toastRemove(id: u32) void {
    const cw = currentWindow();
    cw.toastRemove(id);
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

        var items = self.cw.toasts.items;
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

pub fn toast(src: std.builtin.SourceLocation, opts: ToastOptions) !void {
    const id_mutex = try dvui.toastAdd(opts.window, src, opts.id_extra, opts.subwindow_id, opts.displayFn, opts.timeout);
    const id = id_mutex.id;
    dvui.dataSetSlice(opts.window, id, "_message", opts.message);
    id_mutex.mutex.unlock();
}

pub fn toastDisplay(id: u32) !void {
    const message = dvui.dataGetSlice(null, id, "_message", []const u8) orelse {
        std.debug.print("Error: lost message for toast {x}\n", .{id});
        return;
    };

    var animator = try dvui.animate(@src(), .alpha, 500_000, .{ .id_extra = id });
    defer animator.deinit();
    try dvui.labelNoFmt(@src(), message, .{ .background = true, .corner_radius = dvui.Rect.all(1000) });

    if (dvui.timerDone(id)) {
        animator.startEnd();
    }

    if (animator.end()) {
        dvui.toastRemove(id);
    }
}

pub fn animate(src: std.builtin.SourceLocation, kind: AnimateWidget.Kind, duration_micros: i32, opts: Options) !*AnimateWidget {
    var ret = try currentWindow().arena.create(AnimateWidget);
    ret.* = AnimateWidget.init(src, kind, duration_micros, opts);
    try ret.install(.{});
    return ret;
}

pub const AnimateWidget = struct {
    const Self = @This();
    pub const Kind = enum {
        alpha,
        vert,
        horz,
    };

    wd: WidgetData = undefined,
    kind: Kind = undefined,
    duration: i32 = undefined,
    val: ?f32 = null,

    prev_alpha: f32 = 1.0,

    pub fn init(src: std.builtin.SourceLocation, kind: Kind, duration_micros: i32, opts: Options) Self {
        return Self{ .wd = WidgetData.init(src, .{}, opts), .kind = kind, .duration = duration_micros };
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());
        try self.wd.register("Animate", null);

        if (firstFrame(self.wd.id)) {
            // start begin animation
            dvui.animation(self.wd.id, "_start", .{ .start_val = 0.0, .end_val = 1.0, .end_time = self.duration });
        }

        if (dvui.animationGet(self.wd.id, "_end")) |a| {
            self.val = a.lerp();
        } else if (dvui.animationGet(self.wd.id, "_start")) |a| {
            self.val = a.lerp();
        }

        if (self.val) |v| {
            switch (self.kind) {
                .alpha => {
                    self.prev_alpha = themeGet().alpha;
                    themeGet().alpha *= v;
                },
                .vert => {},
                .horz => {},
            }
        }

        try self.wd.borderAndBackground(.{});
    }

    pub fn startEnd(self: *Self) void {
        dvui.animation(self.wd.id, "_end", .{ .start_val = 1.0, .end_val = 0.0, .end_time = self.duration });
    }

    pub fn end(self: *Self) bool {
        return dvui.animationDone(self.wd.id, "_end");
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.val) |v| {
            switch (self.kind) {
                .alpha => {
                    themeGet().alpha = self.prev_alpha;
                },
                .vert => {
                    self.wd.min_size.h *= v;
                },
                .horz => {
                    self.wd.min_size.w *= v;
                },
            }
        }

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub var dropdown_defaults: Options = .{
    .color_style = .control,
    .margin = Rect.all(4),
    .corner_radius = Rect.all(5),
    .padding = Rect.all(4),
    .background = true,
    .name = "Dropdown",
};

pub fn dropdown(src: std.builtin.SourceLocation, entries: []const []const u8, choice: *usize, opts: Options) !bool {
    const options = dropdown_defaults.override(opts);

    var m = try dvui.menu(@src(), .horizontal, options.wrapOuter());
    defer m.deinit();

    var b = MenuItemWidget.init(src, .{ .submenu = true }, options.wrapInner());
    try b.install(.{ .focus_as_outline = true });
    defer b.deinit();

    var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
    defer hbox.deinit();

    var lw = try LabelWidget.initNoFmt(@src(), entries[choice.*], options.strip().override(.{ .gravity_y = 0.5 }));
    const lw_rect = lw.wd.contentRectScale().r.scale(1 / windowNaturalScale());
    try lw.install(.{});
    lw.deinit();
    try icon(@src(), "dropdown_triangle", entypo.chevron_small_down, options.strip().override(.{ .gravity_y = 0.5, .gravity_x = 1.0 }));

    var ret = false;
    if (b.activeRect()) |r| {
        var pop = PopupWidget.init(@src(), lw_rect, .{ .min_size_content = r.size() });
        var first_frame = firstFrame(pop.wd.id);

        // move popup to align first item with b
        pop.initialRect.x -= MenuItemWidget.defaults.borderGet().x;
        pop.initialRect.x -= MenuItemWidget.defaults.paddingGet().x;
        pop.initialRect.y -= MenuItemWidget.defaults.borderGet().y;
        pop.initialRect.y -= MenuItemWidget.defaults.paddingGet().y;

        pop.initialRect.x -= pop.options.borderGet().x;
        pop.initialRect.x -= pop.options.paddingGet().x;
        pop.initialRect.y -= pop.options.borderGet().y;
        pop.initialRect.y -= pop.options.paddingGet().y;

        // move popup up so selected entry is aligned with b
        const h = pop.wd.contentRect().inset(pop.options.borderGet()).inset(pop.options.paddingGet()).h;
        pop.initialRect.y -= (h / @as(f32, @floatFromInt(entries.len))) * @as(f32, @floatFromInt(choice.*));

        try pop.install(.{});
        defer pop.deinit();

        // without this, if you trigger the dropdown with the keyboard and then
        // move the mouse, the entries are highlighted but not focused
        pop.menu.submenus_activated = true;

        // only want a mouse-up to choose something if the mouse has moved in the popup
        var eat_mouse_up = dataGet(null, pop.wd.id, "_eat_mouse_up", bool) orelse true;

        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = pop.data().id, .r = pop.data().rectScale().r }))
                continue;

            if (eat_mouse_up and e.evt == .mouse) {
                if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                    e.handled = true;
                    eat_mouse_up = false;
                    dataSet(null, pop.wd.id, "_eat_mouse_up", eat_mouse_up);
                } else if (e.evt.mouse.action == .motion or (e.evt.mouse.action == .press and e.evt.mouse.button.pointer())) {
                    eat_mouse_up = false;
                    dataSet(null, pop.wd.id, "_eat_mouse_up", eat_mouse_up);
                }
            }
        }

        for (entries, 0..) |_, i| {
            var mi = try menuItem(@src(), .{}, .{ .id_extra = i });
            if (first_frame and (i == choice.*)) {
                focusWidget(mi.wd.id, null, null);
            }
            defer mi.deinit();

            var labelopts = options.strip();

            if (mi.show_active) {
                labelopts = labelopts.override(.{ .color_style = .accent });
            }

            try labelNoFmt(@src(), entries[i], labelopts);

            if (mi.activeRect()) |_| {
                choice.* = i;
                ret = true;
                dvui.menuGet().?.close();
            }
        }
    }

    return ret;
}

pub var expander_defaults: Options = .{
    .padding = Rect.all(2),
    .font_style = .heading,
};

pub fn expander(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) !bool {
    const options = expander_defaults.override(opts);

    // Use the ButtonWidget to do margin/border/padding, but use strip so we
    // don't get any of ButtonWidget's defaults
    var bc = ButtonWidget.init(src, options.strip().override(options));
    try bc.install(.{});
    defer bc.deinit();

    var expanded: bool = false;
    if (dvui.dataGet(null, bc.wd.id, "_expand", bool)) |e| {
        expanded = e;
    }

    if (bc.clicked()) {
        expanded = !expanded;
    }

    var bcbox = BoxWidget.init(@src(), .horizontal, false, options.strip());
    defer bcbox.deinit();
    try bcbox.install(.{});
    const size = try options.fontGet().lineHeight();
    if (expanded) {
        try icon(@src(), "down_arrow", entypo.triangle_down, .{ .gravity_y = 0.5, .min_size_content = .{ .h = size } });
    } else {
        try icon(@src(), "right_arrow", entypo.triangle_right, .{ .gravity_y = 0.5, .min_size_content = .{ .h = size } });
    }
    try labelNoFmt(@src(), label_str, options.strip());

    dvui.dataSet(null, bc.wd.id, "_expand", expanded);

    return expanded;
}

pub fn paned(src: std.builtin.SourceLocation, dir: enums.Direction, collapse_size: f32, opts: Options) !*PanedWidget {
    var ret = try currentWindow().arena.create(PanedWidget);
    ret.* = PanedWidget.init(src, dir, collapse_size, opts);
    try ret.install(.{});
    return ret;
}

pub const PanedWidget = struct {
    const Self = @This();

    const SavedData = struct {
        split_ratio: f32,
        rect: Rect,
    };

    const handle_size = 4;

    wd: WidgetData = undefined,

    split_ratio: f32 = undefined,
    dir: enums.Direction = undefined,
    collapse_size: f32 = 0,
    hovered: bool = false,
    saved_data: SavedData = undefined,
    first_side_id: ?u32 = null,
    prevClip: Rect = Rect{},

    pub fn init(src: std.builtin.SourceLocation, dir: enums.Direction, collapse_size: f32, opts: Options) Self {
        var self = Self{};
        self.wd = WidgetData.init(src, .{}, opts);
        self.dir = dir;
        self.collapse_size = collapse_size;
        captureMouseMaintain(self.wd.id);

        const rect = self.wd.contentRect();

        if (dvui.dataGet(null, self.wd.id, "_data", SavedData)) |d| {
            self.split_ratio = d.split_ratio;
            switch (self.dir) {
                .horizontal => {
                    if (d.rect.w >= self.collapse_size and rect.w < self.collapse_size) {
                        // collapsing
                        self.animate(1.0);
                    } else if (d.rect.w < self.collapse_size and rect.w >= self.collapse_size) {
                        // expanding
                        self.animate(0.5);
                    }
                },
                .vertical => {
                    if (d.rect.w >= self.collapse_size and rect.w < self.collapse_size) {
                        // collapsing
                        self.animate(1.0);
                    } else if (d.rect.w < self.collapse_size and rect.w >= self.collapse_size) {
                        // expanding
                        self.animate(0.5);
                    }
                },
            }
        } else {
            // first frame
            switch (self.dir) {
                .horizontal => {
                    if (rect.w < self.collapse_size) {
                        self.split_ratio = 1.0;
                    } else {
                        self.split_ratio = 0.5;
                    }
                },
                .vertical => {
                    if (rect.w < self.collapse_size) {
                        self.split_ratio = 1.0;
                    } else if (rect.w >= self.collapse_size) {
                        self.split_ratio = 0.5;
                    }
                },
            }
        }

        if (dvui.animationGet(self.wd.id, "_split_ratio")) |a| {
            self.split_ratio = a.lerp();
        }

        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        try self.wd.register("Paned", null);

        if (opts.process_events) {
            var evts = events();
            for (evts) |*e| {
                if (!eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r }))
                    continue;

                self.processEvent(e, false);
            }
        }

        try self.wd.borderAndBackground(.{});
        self.prevClip = clip(self.wd.contentRectScale().r);

        if (!self.collapsed()) {
            if (self.hovered) {
                const rs = self.wd.contentRectScale();
                var r = rs.r;
                const thick = handle_size * rs.s;
                switch (self.dir) {
                    .horizontal => {
                        r.x += r.w * self.split_ratio - thick / 2;
                        r.w = thick;
                        const height = r.h / 5;
                        r.y += r.h / 2 - height / 2;
                        r.h = height;
                    },
                    .vertical => {
                        r.y += r.h * self.split_ratio - thick / 2;
                        r.h = thick;
                        const width = r.w / 5;
                        r.x += r.w / 2 - width / 2;
                        r.w = width;
                    },
                }
                try pathAddRect(r, Rect.all(thick));
                try pathFillConvex(self.wd.options.color(.text).transparent(0.5));
            }
        }

        _ = parentSet(self.widget());
    }

    pub fn collapsed(self: *Self) bool {
        const rect = self.wd.contentRect();
        switch (self.dir) {
            .horizontal => return (rect.w < self.collapse_size),
            .vertical => return (rect.h < self.collapse_size),
        }
    }

    pub fn showOther(self: *Self) void {
        if (self.split_ratio == 0.0) {
            self.animate(1.0);
        } else if (self.split_ratio == 1.0) {
            self.animate(0.0);
        } else {
            // if we are expanded, then the user means for something to happen
            refresh();
        }
    }

    fn animate(self: *Self, end_val: f32) void {
        dvui.animation(self.wd.id, "_split_ratio", dvui.Animation{ .start_val = self.split_ratio, .end_val = end_val, .end_time = 250_000 });
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) dvui.Rect {
        var r = self.wd.contentRect().justSize();
        if (self.first_side_id == null or self.first_side_id.? == id) {
            self.first_side_id = id;
            if (self.collapsed()) {
                if (self.split_ratio == 0.0) {
                    r.w = 0;
                    r.h = 0;
                } else {
                    switch (self.dir) {
                        .horizontal => r.x -= (r.w - (r.w * self.split_ratio)),
                        .vertical => r.y -= (r.h - (r.h * self.split_ratio)),
                    }
                }
            } else {
                switch (self.dir) {
                    .horizontal => r.w = r.w * self.split_ratio - handle_size / 2,
                    .vertical => r.h = r.h * self.split_ratio - handle_size / 2,
                }
            }
            return dvui.placeIn(r, minSize(id, min_size), e, g);
        } else {
            if (self.collapsed()) {
                if (self.split_ratio == 1.0) {
                    r.w = 0;
                    r.h = 0;
                } else {
                    switch (self.dir) {
                        .horizontal => {
                            r.x = r.w * self.split_ratio;
                        },
                        .vertical => {
                            r.y = r.h * self.split_ratio;
                        },
                    }
                }
            } else {
                switch (self.dir) {
                    .horizontal => {
                        const first = r.w * self.split_ratio - handle_size / 2;
                        r.w -= first + handle_size;
                        r.x += first + handle_size;
                    },
                    .vertical => {
                        const first = r.h * self.split_ratio - handle_size / 2;
                        r.h -= first + handle_size;
                        r.y += first + handle_size;
                    },
                }
            }
            return dvui.placeIn(r, minSize(id, min_size), e, g);
        }
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: dvui.Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.evt == .mouse) {
            const rs = self.wd.contentRectScale();
            var target: f32 = undefined;
            var mouse: f32 = undefined;
            var cursor: Cursor = undefined;
            switch (self.dir) {
                .horizontal => {
                    target = rs.r.x + rs.r.w * self.split_ratio;
                    mouse = e.evt.mouse.p.x;
                    cursor = .arrow_w_e;
                },
                .vertical => {
                    target = rs.r.y + rs.r.h * self.split_ratio;
                    mouse = e.evt.mouse.p.y;
                    cursor = .arrow_n_s;
                },
            }

            if (captured(self.wd.id) or @fabs(mouse - target) < (5 * rs.s)) {
                self.hovered = true;
                e.handled = true;
                if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                    // capture and start drag
                    captureMouse(self.wd.id);
                    dragPreStart(e.evt.mouse.p, cursor, Point{});
                } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                    // stop possible drag and capture
                    captureMouse(null);
                } else if (e.evt.mouse.action == .motion and captured(self.wd.id)) {
                    // move if dragging
                    if (dragging(e.evt.mouse.p)) |dps| {
                        _ = dps;
                        switch (self.dir) {
                            .horizontal => {
                                self.split_ratio = (e.evt.mouse.p.x - rs.r.x) / rs.r.w;
                            },
                            .vertical => {
                                self.split_ratio = (e.evt.mouse.p.y - rs.r.y) / rs.r.h;
                            },
                        }

                        self.split_ratio = @max(0.0, @min(1.0, self.split_ratio));
                    }
                } else if (e.evt.mouse.action == .position) {
                    cursorSet(cursor);
                }
            }
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        clipSet(self.prevClip);
        dvui.dataSet(null, self.wd.id, "_data", SavedData{ .split_ratio = self.split_ratio, .rect = self.wd.contentRect() });
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = dvui.parentSet(self.wd.parent);
    }
};

// TextLayout doesn't have a natural width.  If it's min_size.w was 0, then it
// would calculate a huge min_size.h assuming only 1 character per line can
// fit.  To prevent starting in weird situations, TextLayout defaults to having
// a min_size.w so at least you can see what is going on.
pub fn textLayout(src: std.builtin.SourceLocation, init_opts: TextLayoutWidget.InitOptions, opts: Options) !*TextLayoutWidget {
    const cw = currentWindow();
    var ret = try cw.arena.create(TextLayoutWidget);
    ret.* = TextLayoutWidget.init(src, init_opts, opts);
    try ret.install();
    // can install corner widgets here
    //_ = try dvui.button(@src(), "upright", .{ .gravity_x = 1.0 });
    ret.processEvents();
    // now call addText() any number of times
    return ret;
}

pub const TextLayoutWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .margin = Rect.all(4),
        .padding = Rect.all(4),
        .background = true,
        .color_style = .content,
        .min_size_content = .{ .w = 250 },
    };

    pub const InitOptions = struct {
        selection: ?*Selection = null,
        break_lines: bool = true,
    };

    pub const Selection = struct {
        cursor: usize = 0,
        start: usize = 0,
        end: usize = 0,

        pub fn empty(self: *Selection) bool {
            return self.start == self.end;
        }

        pub fn incCursor(self: *Selection) void {
            self.cursor += 1;
        }

        pub fn decCursor(self: *Selection) void {
            if (self.cursor <= 0) {
                self.cursor = 0;
            } else self.cursor -= 1;
        }

        pub fn incStart(self: *Selection) void {
            self.start += 1;
        }

        pub fn decStart(self: *Selection) void {
            if (self.start <= 0) {
                self.start = 0;
            } else self.start -= 1;
        }

        pub fn incEnd(self: *Selection) void {
            self.end += 1;
        }

        pub fn decEnd(self: *Selection) void {
            if (self.end <= 0) {
                self.end = 0;
            } else self.end -= 1;
        }

        pub fn order(self: *Selection) void {
            if (self.end < self.start) {
                const tmp = self.start;
                self.start = self.end;
                self.end = tmp;
            }
        }
    };

    wd: WidgetData = undefined,
    corners: [4]?Rect = [_]?Rect{null} ** 4,
    corners_min_size: [4]?Size = [_]?Size{null} ** 4,
    corners_last_seen: ?u8 = null,
    insert_pt: Point = Point{},
    prevClip: Rect = Rect{},
    first_line: bool = true,
    break_lines: bool = undefined,

    bytes_seen: usize = 0,
    selection_in: ?*Selection = null,
    selection: *Selection = undefined,
    selection_store: Selection = .{},
    sel_mouse_down_pt: ?Point = null,
    sel_mouse_down_bytes: ?usize = null,
    sel_mouse_drag_pt: ?Point = null,
    sel_left_right: i32 = 0,
    touch_selection: bool = false,

    cursor_seen: bool = false,
    cursor_rect: ?Rect = null,
    cursor_updown: i8 = 0, // positive is down
    cursor_updown_drag: bool = true,
    cursor_updown_pt: ?Point = null,
    scroll_to_cursor: bool = false,

    add_text_done: bool = false,

    copy_sel: ?Selection = null,
    copy_slice: ?[]u8 = null,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        const options = defaults.override(opts);
        var self = Self{ .wd = WidgetData.init(src, .{}, options), .selection_in = init_opts.selection };
        self.break_lines = init_opts.break_lines;

        return self;
    }

    pub fn install(self: *Self) !void {
        try self.wd.register("TextLayout", null);
        _ = parentSet(self.widget());

        if (self.selection_in) |sel| {
            self.selection = sel;
        } else {
            if (dataGet(null, self.wd.id, "_selection", Selection)) |s| {
                self.selection_store = s;
            }
            self.selection = &self.selection_store;
        }

        if (dataGet(null, self.wd.id, "_touch_selection", bool)) |ts| {
            self.touch_selection = ts;
        }

        if (dataGet(null, self.wd.id, "_sel_left_right", i32)) |slf| {
            self.sel_left_right = slf;
        }

        captureMouseMaintain(self.wd.id);

        if (captured(self.wd.id)) {
            if (dataGet(null, self.wd.id, "_sel_mouse_down_bytes", usize)) |p| {
                self.sel_mouse_down_bytes = p;
            }
        }

        if (dataGet(null, self.wd.id, "_cursor_updown_pt", Point)) |p| {
            self.cursor_updown_pt = p;
            dataRemove(null, self.wd.id, "_cursor_updown_pt");
            if (dataGet(null, self.wd.id, "_cursor_updown_drag", bool)) |cud| {
                self.cursor_updown_drag = cud;
            }
        }

        const rs = self.wd.contentRectScale();

        if (!rs.r.empty()) {
            try self.wd.borderAndBackground(.{});
        }

        self.prevClip = clip(rs.r);
    }

    pub fn format(self: *Self, comptime fmt: []const u8, args: anytype, opts: Options) !void {
        var cw = currentWindow();
        const l = try std.fmt.allocPrint(cw.arena, fmt, args);
        try self.addText(l, opts);
    }

    pub fn addText(self: *Self, text: []const u8, opts: Options) !void {
        const options = self.wd.options.override(opts);
        const msize = try options.fontGet().textSize("m");
        const line_height = try options.fontGet().lineHeight();
        var txt = text;

        const rect = self.wd.contentRect();
        var container_width = rect.w;
        if (container_width == 0) {
            // if we are not being shown at all, probably this is the first
            // frame for us and we should calculate our min height assuming we
            // get at least our min width

            // do this dance so we aren't repeating the contentRect
            // calculations here
            const given_width = self.wd.rect.w;
            self.wd.rect.w = @max(given_width, self.wd.min_size.w);
            container_width = self.wd.contentRect().w;
            self.wd.rect.w = given_width;
        }

        while (txt.len > 0) {
            var linestart: f32 = 0;
            var linewidth = container_width;
            var width = linewidth - self.insert_pt.x;
            var width_after: f32 = 0;
            for (self.corners, 0..) |corner, i| {
                if (corner) |cor| {
                    if (@max(cor.y, self.insert_pt.y) < @min(cor.y + cor.h, self.insert_pt.y + line_height)) {
                        linewidth -= cor.w;
                        if (linestart == cor.x) {
                            // used below - if we moved over for a widget, we
                            // can drop to the next line expecting more room
                            // later
                            linestart = (cor.x + cor.w);
                        }

                        if (self.insert_pt.x <= (cor.x + cor.w)) {
                            width -= cor.w;
                            if (self.insert_pt.x >= cor.x) {
                                // widget on left side, skip over it
                                self.insert_pt.x = (cor.x + cor.w);
                            } else {
                                // widget on right side, need to add width to min_size below
                                width_after = self.corners_min_size[i].?.w;
                            }
                        }
                    }
                }
            }

            var end: usize = undefined;

            // get slice of text that fits within width or ends with newline
            var s = try options.fontGet().textSizeEx(txt, if (self.break_lines) width else null, &end, .before);

            // ensure we always get at least 1 codepoint so we make progress
            if (end == 0) {
                end = std.unicode.utf8ByteSequenceLength(txt[0]) catch 1;
                s = try options.fontGet().textSize(txt[0..end]);
            }

            const newline = (txt[end - 1] == '\n');

            //std.debug.print("{d} 1 txt to {d} \"{s}\"\n", .{ container_width, end, txt[0..end] });

            // if we are boxed in too much by corner widgets drop to next line
            if (self.break_lines and s.w > width and linewidth < container_width) {
                self.insert_pt.y += line_height;
                self.insert_pt.x = 0;
                continue;
            }

            // try to break on space if:
            // - slice ended due to width (not newline)
            // - linewidth is long enough (otherwise too narrow to break on space)
            if (self.break_lines and end < txt.len and !newline and linewidth > (10 * msize.w)) {
                const space: []const u8 = &[_]u8{' '};
                // now we are under the length limit but might be in the middle of a word
                // look one char further because we might be right at the end of a word
                const spaceIdx = std.mem.lastIndexOfLinear(u8, txt[0 .. end + 1], space);
                if (spaceIdx) |si| {
                    end = si + 1;
                    s = try options.fontGet().textSize(txt[0..end]);
                } else if (self.insert_pt.x > linestart) {
                    // can't fit breaking on space, but we aren't starting at the left edge
                    // so drop to next line
                    self.insert_pt.y += line_height;
                    self.insert_pt.x = 0;
                    continue;
                }
            }

            // now we know the line of text we are about to render
            // see if selection needs to be updated

            // if the text changed our selection might be in the middle of utf8 chars, so fix it up
            while (self.selection.start >= self.bytes_seen and self.selection.start < self.bytes_seen + end and txt[self.selection.start - self.bytes_seen] & 0xc0 == 0x80) {
                self.selection.start += 1;
            }

            while (self.selection.cursor >= self.bytes_seen and self.selection.cursor < self.bytes_seen + end and txt[self.selection.cursor - self.bytes_seen] & 0xc0 == 0x80) {
                self.selection.cursor += 1;
            }

            while (self.selection.end >= self.bytes_seen and self.selection.end < self.bytes_seen + end and txt[self.selection.end - self.bytes_seen] & 0xc0 == 0x80) {
                self.selection.end += 1;
            }

            if (self.sel_left_right != 0 and !self.cursor_seen and self.selection.cursor <= self.bytes_seen + end) {
                while (self.sel_left_right < 0 and self.selection.cursor > self.bytes_seen) {
                    var move_start: bool = undefined;
                    if (self.selection.cursor == self.selection.start) {
                        move_start = true;
                    } else {
                        move_start = false;
                    }

                    // move cursor one utf8 char left
                    self.selection.cursor -|= 1;
                    while (self.selection.cursor > self.bytes_seen and txt[self.selection.cursor - self.bytes_seen] & 0xc0 == 0x80) {
                        // in the middle of a multibyte char
                        self.selection.cursor -|= 1;
                    }

                    if (move_start) {
                        self.selection.start = self.selection.cursor;
                    } else {
                        self.selection.end = self.selection.cursor;
                    }
                    self.sel_left_right += 1;
                }

                if (self.sel_left_right < 0 and self.selection.cursor == 0) {
                    self.sel_left_right = 0;
                }

                while (self.sel_left_right > 0 and self.selection.cursor < (self.bytes_seen + end)) {
                    var move_start: bool = undefined;
                    if (self.selection.cursor == self.selection.end) {
                        move_start = false;
                    } else {
                        move_start = true;
                    }

                    // move cursor one utf8 char right
                    self.selection.cursor += std.unicode.utf8ByteSequenceLength(txt[self.selection.cursor - self.bytes_seen]) catch 1;

                    if (move_start) {
                        self.selection.start = self.selection.cursor;
                    } else {
                        self.selection.end = self.selection.cursor;
                    }
                    self.sel_left_right -= 1;
                }
            }

            if (self.sel_mouse_down_pt) |p| {
                const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                    // point is before this text
                    self.sel_mouse_down_bytes = self.bytes_seen;
                    self.selection.cursor = self.sel_mouse_down_bytes.?;
                    self.selection.start = self.sel_mouse_down_bytes.?;
                    self.selection.end = self.sel_mouse_down_bytes.?;
                    self.sel_mouse_down_pt = null;
                } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                    // point is in this text
                    const how_far = p.x - rs.x;
                    var pt_end: usize = undefined;
                    _ = try options.fontGet().textSizeEx(txt, how_far, &pt_end, .nearest);
                    self.sel_mouse_down_bytes = self.bytes_seen + pt_end;
                    self.selection.cursor = self.sel_mouse_down_bytes.?;
                    self.selection.start = self.sel_mouse_down_bytes.?;
                    self.selection.end = self.sel_mouse_down_bytes.?;
                    self.sel_mouse_down_pt = null;
                } else {
                    if (newline and p.y < (rs.y + rs.h)) {
                        // point is after this text on this same horizontal line
                        self.sel_mouse_down_bytes = self.bytes_seen + end - 1;
                        self.sel_mouse_down_pt = null;
                    } else {
                        // point is after this text, but we might not get anymore
                        self.sel_mouse_down_bytes = self.bytes_seen + end;
                    }
                    self.selection.cursor = self.sel_mouse_down_bytes.?;
                    self.selection.start = self.sel_mouse_down_bytes.?;
                    self.selection.end = self.sel_mouse_down_bytes.?;
                }
                self.scroll_to_cursor = true;
            }

            if (self.sel_mouse_drag_pt) |p| {
                const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                    // point is before this text
                    self.selection.cursor = self.bytes_seen;
                    self.selection.start = @min(self.sel_mouse_down_bytes.?, self.bytes_seen);
                    self.selection.end = @max(self.sel_mouse_down_bytes.?, self.bytes_seen);
                    self.sel_mouse_drag_pt = null;
                } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                    // point is in this text
                    const how_far = p.x - rs.x;
                    var pt_end: usize = undefined;
                    _ = try options.fontGet().textSizeEx(txt, how_far, &pt_end, .nearest);
                    self.selection.cursor = self.bytes_seen + pt_end;
                    self.selection.start = @min(self.sel_mouse_down_bytes.?, self.bytes_seen + pt_end);
                    self.selection.end = @max(self.sel_mouse_down_bytes.?, self.bytes_seen + pt_end);
                    self.sel_mouse_drag_pt = null;
                } else {
                    // point is after this text, but we might not get anymore
                    self.selection.cursor = self.bytes_seen + end;
                    self.selection.start = @min(self.sel_mouse_down_bytes.?, self.bytes_seen + end);
                    self.selection.end = @max(self.sel_mouse_down_bytes.?, self.bytes_seen + end);
                }

                // don't set scroll_to_cursor here because when we are dragging
                // we are already doing a scroll_drag in processEvent
            }

            if (self.cursor_updown == 0) {
                if (self.cursor_updown_pt) |p| {
                    const rs = Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = s.w, .h = s.h };
                    if (p.y < rs.y or (p.y < (rs.y + rs.h) and p.x < rs.x)) {
                        // point is before this text
                        if (self.cursor_updown_drag) {
                            if (self.selection.cursor == self.selection.start) {
                                self.selection.cursor = self.bytes_seen;
                                self.selection.start = self.bytes_seen;
                            } else {
                                self.selection.cursor = self.bytes_seen;
                                self.selection.end = self.bytes_seen;
                            }
                        } else {
                            self.selection.cursor = self.bytes_seen;
                            self.selection.start = self.bytes_seen;
                            self.selection.end = self.bytes_seen;
                        }
                        self.cursor_updown_pt = null;
                        self.selection.order();
                        self.scroll_to_cursor = true;
                    } else if (p.y < (rs.y + rs.h) and p.x < (rs.x + rs.w)) {
                        // point is in this text
                        const how_far = p.x - rs.x;
                        var pt_end: usize = undefined;
                        _ = try options.fontGet().textSizeEx(txt, how_far, &pt_end, .nearest);
                        if (self.cursor_updown_drag) {
                            if (self.selection.cursor == self.selection.start) {
                                self.selection.cursor = self.bytes_seen + pt_end;
                                self.selection.start = self.bytes_seen + pt_end;
                            } else {
                                self.selection.cursor = self.bytes_seen + pt_end;
                                self.selection.end = self.bytes_seen + pt_end;
                            }
                        } else {
                            self.selection.cursor = self.bytes_seen + pt_end;
                            self.selection.start = self.bytes_seen + pt_end;
                            self.selection.end = self.bytes_seen + pt_end;
                        }
                        self.cursor_updown_pt = null;
                        self.selection.order();
                        self.scroll_to_cursor = true;
                    } else {
                        if (newline and p.y < (rs.y + rs.h)) {
                            // point is after this text on this same horizontal line
                            if (self.cursor_updown_drag) {
                                if (self.selection.cursor == self.selection.start) {
                                    self.selection.cursor = self.bytes_seen + end - 1;
                                    self.selection.start = self.bytes_seen + end - 1;
                                } else {
                                    self.selection.cursor = self.bytes_seen + end - 1;
                                    self.selection.end = self.bytes_seen + end - 1;
                                }
                            } else {
                                self.selection.cursor = self.bytes_seen + end - 1;
                                self.selection.start = self.bytes_seen + end - 1;
                                self.selection.end = self.bytes_seen + end - 1;
                            }
                            self.cursor_updown_pt = null;
                        } else {
                            // point is after this text, but we might not get anymore
                            if (self.cursor_updown_drag) {
                                if (self.selection.cursor == self.selection.start) {
                                    self.selection.cursor = self.bytes_seen + end;
                                    self.selection.start = self.bytes_seen + end;
                                } else {
                                    self.selection.cursor = self.bytes_seen + end;
                                    self.selection.end = self.bytes_seen + end;
                                }
                            } else {
                                self.selection.cursor = self.bytes_seen + end;
                                self.selection.start = self.bytes_seen + end;
                                self.selection.end = self.bytes_seen + end;
                            }
                        }
                        self.selection.order();
                        self.scroll_to_cursor = true;
                    }
                }
            }

            const rs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = width, .h = @max(0, rect.h - self.insert_pt.y) });
            //std.debug.print("renderText: {} {s}\n", .{ rs.r, txt[0..end] });
            const rtxt = if (newline) txt[0 .. end - 1] else txt[0..end];
            try renderText(.{
                .font = options.fontGet(),
                .text = rtxt,
                .rs = rs,
                .color = options.color(.text),
                .sel_start = self.selection.start -| self.bytes_seen,
                .sel_end = self.selection.end -| self.bytes_seen,
                .sel_color = options.color(.fill),
                .sel_color_bg = options.color(.accent),
            });

            if (!self.cursor_seen and self.selection.cursor < self.bytes_seen + end) {
                self.cursor_seen = true;
                const size = try options.fontGet().textSize(txt[0 .. self.selection.cursor - self.bytes_seen]);
                const cr = Rect{ .x = self.insert_pt.x + size.w, .y = self.insert_pt.y, .w = 1, .h = try options.fontGet().lineHeight() };

                if (self.cursor_updown != 0 and self.cursor_updown_pt == null) {
                    const cr_new = cr.add(.{ .y = @as(f32, @floatFromInt(self.cursor_updown)) * try options.fontGet().lineHeight() });
                    self.cursor_updown_pt = cr_new.topleft().plus(.{ .y = cr_new.h / 2 });

                    // might have already passed, so need to go again next frame
                    refresh();

                    var scrollto = Event{ .evt = .{ .scroll_to = .{
                        .screen_rect = self.screenRectScale(cr_new).r,
                    } } };
                    self.processEvent(&scrollto, true);
                }

                if (self.scroll_to_cursor) {
                    var scrollto = Event{ .evt = .{ .scroll_to = .{
                        .screen_rect = self.screenRectScale(cr.outset(self.wd.options.paddingGet())).r,
                    } } };
                    self.processEvent(&scrollto, true);
                }

                if (self.selection.start == self.selection.end) {
                    self.cursor_rect = cr;
                }
            }

            // even if we don't actually render, need to update insert_pt and minSize
            // like we did because our parent might size based on that (might be in a
            // scroll area)
            self.insert_pt.x += s.w;
            const size = self.wd.padSize(.{ .w = self.insert_pt.x, .h = self.insert_pt.y + s.h });
            if (!self.break_lines) {
                self.wd.min_size.w = @max(self.wd.min_size.w, size.w + width_after);
            }
            self.wd.min_size.h = @max(self.wd.min_size.h, size.h);

            if (self.copy_sel) |sel| {
                // we are copying to clipboard
                if (sel.start < self.bytes_seen + end) {
                    // need to copy some
                    const cstart = if (sel.start < self.bytes_seen) 0 else (sel.start - self.bytes_seen);
                    const cend = if (sel.end < self.bytes_seen + end) (sel.end - self.bytes_seen) else end;

                    // initialize or realloc
                    if (self.copy_slice) |slice| {
                        const old_len = slice.len;
                        self.copy_slice = try currentWindow().arena.realloc(slice, slice.len + (cend - cstart));
                        @memcpy(self.copy_slice.?[old_len..], txt[cstart..cend]);
                    } else {
                        self.copy_slice = try currentWindow().arena.dupe(u8, txt[cstart..cend]);
                    }

                    // push to clipboard if done
                    if (sel.end <= self.bytes_seen + end) {
                        try dvui.clipboardTextSet(self.copy_slice.?);

                        self.copy_sel = null;
                        currentWindow().arena.free(self.copy_slice.?);
                        self.copy_slice = null;
                    }
                }
            }

            // discard bytes we've dealt with
            txt = txt[end..];
            self.bytes_seen += end;

            // move insert_pt to next line if we have more text
            if (txt.len > 0 or newline) {
                self.insert_pt.y += line_height;
                self.insert_pt.x = 0;
                if (newline) {
                    const newline_size = self.wd.padSize(.{ .w = self.insert_pt.x, .h = self.insert_pt.y + s.h });
                    if (!self.break_lines) {
                        self.wd.min_size.w = @max(self.wd.min_size.w, newline_size.w);
                    }
                    self.wd.min_size.h = @max(self.wd.min_size.h, newline_size.h);
                }
            }

            if (self.wd.options.rect != null) {
                // we were given a rect, so don't need to calculate our min height,
                // so stop as soon as we run off the end of the clipping region
                // this helps for performance
                const nextrs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y });
                if (nextrs.r.y > (clipGet().y + clipGet().h)) {
                    //std.debug.print("stopping after: {s}\n", .{rtxt});
                    break;
                }
            }
        }
    }

    pub fn addTextDone(self: *Self, opts: Options) !void {
        self.add_text_done = true;

        if (self.copy_sel) |_| {
            // we are copying to clipboard and never stopped
            try dvui.clipboardTextSet(self.copy_slice.?);

            self.copy_sel = null;
            currentWindow().arena.free(self.copy_slice.?);
            self.copy_slice = null;
        }

        // if we had mouse/keyboard interaction, need to handle things if addText never gets called
        if (self.sel_mouse_down_pt) |_| {
            self.sel_mouse_down_bytes = self.bytes_seen;
        }

        self.selection.cursor = @min(self.selection.cursor, self.bytes_seen);
        self.selection.start = @min(self.selection.start, self.bytes_seen);
        self.selection.end = @min(self.selection.end, self.bytes_seen);

        if (self.sel_left_right > 0 and self.selection.cursor == self.bytes_seen) {
            self.sel_left_right = 0;
        } else if (self.sel_left_right < 0 and self.selection.cursor == 0) {
            self.sel_left_right = 0;
        }

        if (!self.cursor_seen) {
            self.cursor_seen = true;
            self.selection.cursor = self.bytes_seen;

            const options = self.wd.options.override(opts);
            const size = try options.fontGet().textSize("");
            const cr = Rect{ .x = self.insert_pt.x + size.w, .y = self.insert_pt.y, .w = 1, .h = try options.fontGet().lineHeight() };

            if (self.cursor_updown != 0 and self.cursor_updown_pt == null) {
                const cr_new = cr.add(.{ .y = @as(f32, @floatFromInt(self.cursor_updown)) * try options.fontGet().lineHeight() });
                self.cursor_updown_pt = cr_new.topleft().plus(.{ .y = cr_new.h / 2 });

                // might have already passed, so need to go again next frame
                refresh();

                var scrollto = Event{ .evt = .{ .scroll_to = .{
                    .screen_rect = self.screenRectScale(cr_new).r,
                } } };
                self.processEvent(&scrollto, true);
            }

            if (self.scroll_to_cursor) {
                var scrollto = Event{ .evt = .{ .scroll_to = .{
                    .screen_rect = self.screenRectScale(cr.outset(self.wd.options.paddingGet())).r,
                } } };
                self.processEvent(&scrollto, true);
            }

            if (self.selection.start == self.selection.end) {
                self.cursor_rect = cr;
            }
        }
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        const ret = placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
        var i: usize = undefined;
        if (g.y < 0.5) {
            if (g.x < 0.5) {
                i = 0; // upleft
            } else {
                i = 1; // upright
            }
        } else {
            if (g.x < 0.5) {
                i = 2; // downleft
            } else {
                i = 3; // downright
            }
        }

        self.corners[i] = ret;
        self.corners_last_seen = @intCast(i);
        return ret;
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        if (self.corners_last_seen) |ls| {
            self.corners_min_size[ls] = s;
        }
        // we calculate our min size in deinit() after we have seen our text
    }

    pub fn selectionGet(self: *Self, opts: struct { check_updown: bool = true }) ?*Selection {
        if (self.sel_mouse_down_pt == null and
            self.sel_mouse_drag_pt == null and
            self.cursor_updown_pt == null and
            (!opts.check_updown or self.cursor_updown == 0))
        {
            return self.selection;
        } else {
            return null;
        }
    }

    pub fn eventMatchOptions(self: *Self) EventMatchOptions {
        return .{ .id = self.data().id, .r = self.data().borderRectScale().r };
    }

    pub fn processEvents(self: *Self) void {
        const emo = self.eventMatchOptions();
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, emo))
                continue;

            self.processEvent(e, false);
        }
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.evt == .mouse) {
            if (e.evt.mouse.action == .focus) {
                e.handled = true;
                // focus so that we can receive keyboard input
                focusWidget(self.wd.id, null, e.num);
            } else if (e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
                e.handled = true;
                // capture and start drag
                captureMouse(self.wd.id);
                dragPreStart(e.evt.mouse.p, .ibeam, Point{});

                // Normally a touch-motion-release over text will cause a
                // scroll. To support selection with touch, first you
                // touch-release (without crossing the drag threshold) which
                // does a select-all, then you can select a subset.  If you
                // select an empty selection (touch-release without drag) then
                // you go back to normal scroll behavior.
                if (!e.evt.mouse.button.touch() or !self.selection.empty()) {
                    self.touch_selection = true;
                    self.sel_mouse_down_pt = self.wd.contentRectScale().pointFromScreen(e.evt.mouse.p);
                    self.sel_mouse_drag_pt = null;
                    self.cursor_updown = 0;
                    self.cursor_updown_pt = null;
                }
            } else if (e.evt.mouse.action == .release and e.evt.mouse.button.pointer()) {
                e.handled = true;
                if (captured(self.wd.id)) {
                    if (e.evt.mouse.button.touch() and !self.touch_selection) {
                        // select all text
                        self.selection.start = 0;
                        self.selection.cursor = 0;
                        self.selection.end = std.math.maxInt(usize);
                    }
                    self.touch_selection = false;
                    captureMouse(null); // stop possible drag and capture
                }
            } else if (e.evt.mouse.action == .motion and captured(self.wd.id)) {
                // move if dragging
                if (dragging(e.evt.mouse.p)) |dps| {
                    if (self.touch_selection) {
                        e.handled = true;
                        self.sel_mouse_drag_pt = self.wd.contentRectScale().pointFromScreen(e.evt.mouse.p);
                        self.cursor_updown = 0;
                        self.cursor_updown_pt = null;
                        var scrolldrag = Event{ .evt = .{ .scroll_drag = .{
                            .mouse_pt = e.evt.mouse.p,
                            .screen_rect = self.wd.rectScale().r,
                            .capture_id = self.wd.id,
                            .injected = (dps.x == 0 and dps.y == 0),
                        } } };
                        self.processEvent(&scrolldrag, true);
                    } else {
                        // user intended to scroll with a finger swipe
                        captureMouse(null); // stop possible drag and capture
                    }
                }
            }
        } else if (e.evt == .key and (e.evt.key.action == .down or e.evt.key.action == .repeat) and e.evt.key.mod.shift()) {
            switch (e.evt.key.code) {
                .left => {
                    e.handled = true;
                    if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown == 0) {
                        // only change selection if mouse isn't trying to change it
                        self.sel_left_right -= 1;
                        self.scroll_to_cursor = true;
                    }
                },
                .right => {
                    e.handled = true;
                    if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown == 0) {
                        // only change selection if mouse isn't trying to change it
                        self.sel_left_right += 1;
                        self.scroll_to_cursor = true;
                    }
                },
                .up, .down => |code| {
                    e.handled = true;
                    if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown_pt == null) {
                        self.cursor_updown += if (code == .down) 1 else -1;
                    }
                },
                else => {},
            }
        } else if (e.evt == .key and e.evt.key.mod.controlCommand() and e.evt.key.code == .c and e.evt.key.action == .down) {
            // copy
            e.handled = true;
            if (self.selectionGet(.{})) |sel| {
                if (!sel.empty()) {
                    self.copy_sel = sel.*;
                }
            }
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        if (!self.add_text_done) {
            self.addTextDone(.{}) catch {};
        }
        dataSet(null, self.wd.id, "_selection", self.selection.*);
        dataSet(null, self.wd.id, "_touch_selection", self.touch_selection);
        if (self.sel_left_right != 0) {
            // user might have pressed left a few times, but we couldn't
            // process them all this frame because they crossed calls to
            // addText
            dataSet(null, self.wd.id, "_sel_left_right", self.sel_left_right);
            refresh();
        }
        if (captured(self.wd.id) and self.sel_mouse_down_bytes != null) {
            // once we figure out where the mousedown was, we need to save it
            // as long as we are dragging
            dataSet(null, self.wd.id, "_sel_mouse_down_bytes", self.sel_mouse_down_bytes.?);
        }
        if (self.cursor_updown != 0) {
            // user pressed keys to move the cursor up/down, and on this frame
            // we figured out the pixel position where the new cursor should
            // be, but need to save this for next frame to figure out the byte
            // position based on this pixel position
            dataSet(null, self.wd.id, "_cursor_updown_pt", self.cursor_updown_pt);
            dataSet(null, self.wd.id, "_cursor_updown_drag", self.cursor_updown_drag);
        }
        clipSet(self.prevClip);

        // check if the widgets are taller than the text
        const left_height = (self.corners_min_size[0] orelse Size{}).h + (self.corners_min_size[2] orelse Size{}).h;
        const right_height = (self.corners_min_size[1] orelse Size{}).h + (self.corners_min_size[3] orelse Size{}).h;
        self.wd.min_size.h = @max(self.wd.min_size.h, self.wd.padSize(.{ .h = @max(left_height, right_height) }).h);

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub fn context(src: std.builtin.SourceLocation, opts: Options) !*ContextWidget {
    var ret = try currentWindow().arena.create(ContextWidget);
    ret.* = ContextWidget.init(src, opts);
    try ret.install(.{});
    return ret;
}

pub const ContextWidget = struct {
    const Self = @This();
    wd: WidgetData = undefined,

    winId: u32 = undefined,
    process_events: bool = true,
    focused: bool = false,
    activePt: Point = Point{},

    pub fn init(src: std.builtin.SourceLocation, opts: Options) Self {
        var self = Self{};
        self.wd = WidgetData.init(src, .{}, opts);
        self.winId = subwindowCurrentId();
        if (focusedWidgetIdInCurrentSubwindow()) |fid| {
            if (fid == self.wd.id) {
                self.focused = true;
            }
        }

        if (dataGet(null, self.wd.id, "_activePt", Point)) |a| {
            self.activePt = a;
        }

        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        self.process_events = opts.process_events;
        _ = parentSet(self.widget());
        try self.wd.register("Context", null);
        try self.wd.borderAndBackground(.{});
    }

    pub fn activePoint(self: *Self) ?Point {
        if (self.focused) {
            return self.activePt;
        }

        return null;
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        switch (e.evt) {
            .close_popup => {
                if (self.focused) {
                    // we are getting a bubbled event, so the window we are in is not the current one
                    focusWidget(null, self.winId, null);
                }
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn processMouseEventsAfter(self: *Self) void {
        const rs = self.wd.borderRectScale();
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.wd.id, .r = rs.r }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .focus and me.button == .right) {
                        // eat any right button focus events so they don't get
                        // caught by the containing window cleanup and cause us
                        // to lose the focus we are about to get from the right
                        // press below
                        e.handled = true;
                    } else if (me.action == .press and me.button == .right) {
                        e.handled = true;

                        focusWidget(self.wd.id, null, e.num);
                        self.focused = true;

                        // scale the point back to natural so we can use it in Popup
                        self.activePt = me.p.scale(1 / windowNaturalScale());

                        // offset just enough so when Popup first appears nothing is highlighted
                        self.activePt.x += 1;
                    }
                },
                else => {},
            }
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.process_events) {
            self.processMouseEventsAfter();
        }
        if (self.focused) {
            dataSet(null, self.wd.id, "_activePt", self.activePt);
        }
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub fn overlay(src: std.builtin.SourceLocation, opts: Options) !*OverlayWidget {
    var ret = try currentWindow().arena.create(OverlayWidget);
    ret.* = OverlayWidget.init(src, opts);
    try ret.install(.{});
    return ret;
}

pub const OverlayWidget = struct {
    const Self = @This();
    wd: WidgetData = undefined,

    pub fn init(src: std.builtin.SourceLocation, opts: Options) Self {
        return Self{ .wd = WidgetData.init(src, .{}, opts) };
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());
        try self.wd.register("Overlay", null);
        try self.wd.borderAndBackground(.{});
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub fn box(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) !*BoxWidget {
    var ret = try currentWindow().arena.create(BoxWidget);
    ret.* = BoxWidget.init(src, dir, false, opts);
    try ret.install(.{});
    return ret;
}

pub fn boxEqual(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) !*BoxWidget {
    var ret = try currentWindow().arena.create(BoxWidget);
    ret.* = BoxWidget.init(src, dir, true, opts);
    try ret.install(.{});
    return ret;
}

pub const BoxWidget = struct {
    const Self = @This();

    const Data = struct {
        total_weight_prev: ?f32 = null,
        min_space_taken_prev: ?f32 = null,
    };

    wd: WidgetData = undefined,
    dir: enums.Direction = undefined,
    equal_space: bool = undefined,
    max_thick: f32 = 0,
    data_prev: Data = Data{},
    min_space_taken: f32 = 0,
    total_weight: f32 = 0,
    childRect: Rect = Rect{},
    extra_pixels: f32 = 0,

    pub fn init(src: std.builtin.SourceLocation, dir: enums.Direction, equal_space: bool, opts: Options) BoxWidget {
        var self = Self{};
        self.wd = WidgetData.init(src, .{}, opts);
        self.dir = dir;
        self.equal_space = equal_space;
        if (dataGet(null, self.wd.id, "_data", Data)) |d| {
            self.data_prev = d;
        }
        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        try self.wd.register(self.wd.options.name orelse "Box", null);
        try self.wd.borderAndBackground(.{});

        // our rect for children has to start at 0,0
        self.childRect = self.wd.contentRect().justSize();

        if (self.data_prev.min_space_taken_prev) |taken_prev| {
            if (self.dir == .horizontal) {
                if (self.equal_space) {
                    self.extra_pixels = self.childRect.w;
                } else {
                    self.extra_pixels = @max(0, self.childRect.w - taken_prev);
                }
            } else {
                if (self.equal_space) {
                    self.extra_pixels = self.childRect.h;
                } else {
                    self.extra_pixels = @max(0, self.childRect.h - taken_prev);
                }
            }
        }

        _ = parentSet(self.widget());
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        var current_weight: f32 = 0.0;
        if (self.equal_space or (self.dir == .horizontal and e.horizontal()) or (self.dir == .vertical and e.vertical())) {
            current_weight = 1.0;
        }
        self.total_weight += current_weight;

        var pixels_per_w: f32 = 0;
        if (self.data_prev.total_weight_prev) |w| {
            if (w > 0) {
                pixels_per_w = self.extra_pixels / w;
            }
        }

        var child_size = minSize(id, min_size);

        var rect = self.childRect;
        rect.w = @min(rect.w, child_size.w);
        rect.h = @min(rect.h, child_size.h);

        if (self.dir == .horizontal) {
            rect.h = self.childRect.h;
            if (self.equal_space) {
                rect.w = pixels_per_w * current_weight;
            } else {
                rect.w += pixels_per_w * current_weight;
            }

            if (g.x <= 0.5) {
                self.childRect.w = @max(0, self.childRect.w - rect.w);
                self.childRect.x += rect.w;
            } else {
                rect.x += @max(0, self.childRect.w - rect.w);
                self.childRect.w = @max(0, self.childRect.w - rect.w);
            }
        } else if (self.dir == .vertical) {
            rect.w = self.childRect.w;
            if (self.equal_space) {
                rect.h = pixels_per_w * current_weight;
            } else {
                rect.h += pixels_per_w * current_weight;
            }

            if (g.y <= 0.5) {
                self.childRect.h = @max(0, self.childRect.h - rect.h);
                self.childRect.y += rect.h;
            } else {
                rect.y += @max(0, self.childRect.h - rect.h);
                self.childRect.h = @max(0, self.childRect.h - rect.h);
            }
        }

        return placeIn(rect, child_size, e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        if (self.dir == .horizontal) {
            if (self.equal_space) {
                self.min_space_taken = @max(self.min_space_taken, s.w);
            } else {
                self.min_space_taken += s.w;
            }
            self.max_thick = @max(self.max_thick, s.h);
        } else {
            if (self.equal_space) {
                self.min_space_taken = @max(self.min_space_taken, s.h);
            } else {
                self.min_space_taken += s.h;
            }
            self.max_thick = @max(self.max_thick, s.w);
        }
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        var ms: Size = undefined;
        if (self.dir == .horizontal) {
            if (self.equal_space) {
                ms.w = self.min_space_taken * self.total_weight;
            } else {
                ms.w = self.min_space_taken;
            }
            ms.h = self.max_thick;
            if (self.total_weight > 0 and self.childRect.w > 0.001) {
                // we have expanded children, but didn't use all the space, so something has changed
                // equal_space could mean we don't exactly use all the space (due to floating point)
                refresh();
            }
        } else {
            if (self.equal_space) {
                ms.h = self.min_space_taken * self.total_weight;
            } else {
                ms.h = self.min_space_taken;
            }
            ms.w = self.max_thick;
            if (self.total_weight > 0 and self.childRect.h > 0.001) {
                // we have expanded children, but didn't use all the space, so something has changed
                // equal_space could mean we don't exactly use all the space (due to floating point)
                refresh();
            }
        }

        self.wd.minSizeMax(self.wd.padSize(ms));
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();

        dataSet(null, self.wd.id, "_data", Data{ .total_weight_prev = self.total_weight, .min_space_taken_prev = self.min_space_taken });

        _ = parentSet(self.wd.parent);
    }
};

pub fn scrollArea(src: std.builtin.SourceLocation, init_opts: ScrollAreaWidget.InitOpts, opts: Options) !*ScrollAreaWidget {
    var ret = try currentWindow().arena.create(ScrollAreaWidget);
    ret.* = ScrollAreaWidget.init(src, init_opts, opts);
    try ret.install(.{});
    return ret;
}

pub const ScrollAreaWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .background = true,
        // generally the top of a scroll area is against something flat (like
        // window header), and the bottom is against something curved (bottom
        // of a window)
        .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
        .color_style = .content,
    };

    pub const InitOpts = struct {
        scroll_info: ?*ScrollInfo = null,
        vertical: ?ScrollInfo.ScrollMode = null, // .auto is default
        vertical_bar: ScrollInfo.ScrollBarMode = .auto,
        horizontal: ?ScrollInfo.ScrollMode = null, // .none is default
        horizontal_bar: ScrollInfo.ScrollBarMode = .auto,
    };

    hbox: BoxWidget = undefined,
    vbar: ?ScrollBarWidget = undefined,
    vbox: BoxWidget = undefined,
    hbar: ?ScrollBarWidget = undefined,
    init_opts: InitOpts = undefined,
    si: *ScrollInfo = undefined,
    si_store: ScrollInfo = .{},
    scroll: ScrollContainerWidget = undefined,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOpts, opts: Options) Self {
        var self = Self{};
        self.init_opts = init_opts;
        const options = defaults.override(opts);

        self.hbox = BoxWidget.init(src, .horizontal, false, options.override(.{ .name = "ScrollAreaWidget" }));

        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true, focus_id: ?u32 = null }) !void {
        if (self.init_opts.scroll_info) |si| {
            self.si = si;
            if (self.init_opts.vertical != null) {
                std.debug.print("dvui: ScrollAreaWidget {x} init_opts.vertical .{s} overridden by init_opts.scroll_info.vertical .{s}\n", .{ self.hbox.wd.id, @tagName(self.init_opts.vertical.?), @tagName(si.vertical) });
            }
            if (self.init_opts.horizontal != null) {
                std.debug.print("dvui: ScrollAreaWidget {x} init_opts.horizontal .{s} overridden by init_opts.scroll_info.horizontal .{s}\n", .{ self.hbox.wd.id, @tagName(self.init_opts.horizontal.?), @tagName(si.horizontal) });
            }
        } else if (dataGet(null, self.hbox.data().id, "_scroll_info", ScrollInfo)) |si| {
            self.si_store = si;
            self.si = &self.si_store; // can't take pointer to self in init, so we do it in install
        } else {
            self.si = &self.si_store; // can't take pointer to self in init, so we do it in install
            self.si.vertical = self.init_opts.vertical orelse .auto;
            self.si.horizontal = self.init_opts.horizontal orelse .none;
        }

        try self.hbox.install(.{});

        // the viewport is also set in ScrollContainer but we need it here in
        // case the scroll bar modes are auto
        const crect = self.hbox.wd.contentRect();
        self.si.viewport.w = crect.w;
        self.si.viewport.h = crect.h;

        const focus_target = opts.focus_id orelse dataGet(null, self.hbox.data().id, "_scroll_id", u32);

        if (self.si.vertical != .none) {
            if (self.init_opts.vertical_bar == .show or (self.init_opts.vertical_bar == .auto and (self.si.virtual_size.h > self.si.viewport.h))) {
                // do the scrollbars first so that they still appear even if there's not enough space
                self.vbar = ScrollBarWidget.init(@src(), .{ .scroll_info = self.si, .focus_id = focus_target }, .{ .gravity_x = 1.0 });
                try self.vbar.?.install(.{});
            }
        }

        self.vbox = BoxWidget.init(@src(), .vertical, false, self.hbox.data().options.strip().override(.{ .expand = .both, .name = "ScrollAreaWidget vbox" }));
        try self.vbox.install(.{});

        if (self.si.horizontal != .none) {
            if (self.init_opts.horizontal_bar == .show or (self.init_opts.horizontal_bar == .auto and (self.si.virtual_size.w > self.si.viewport.w))) {
                self.hbar = ScrollBarWidget.init(@src(), .{ .direction = .horizontal, .scroll_info = self.si, .focus_id = focus_target }, .{ .expand = .horizontal, .gravity_y = 1.0 });
                try self.hbar.?.install(.{});
            }
        }

        var container_opts = self.hbox.data().options.strip().override(.{ .expand = .both });
        self.scroll = ScrollContainerWidget.init(@src(), self.si, container_opts);

        try self.scroll.install(.{ .process_events = opts.process_events });
    }

    pub fn deinit(self: *Self) void {
        dataSet(null, self.hbox.data().id, "_scroll_id", self.scroll.wd.id);
        self.scroll.deinit();

        if (self.hbar) |*hbar| {
            hbar.deinit();
        }

        self.vbox.deinit();

        if (self.vbar) |*vbar| {
            vbar.deinit();
        }

        dataSet(null, self.hbox.data().id, "_scroll_info", self.si.*);

        self.hbox.deinit();
    }
};

pub const ScrollContainerWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        // most of the time ScrollContainer is used inside ScrollArea which
        // overrides these
        .background = true,
        .color_style = .content,
        .min_size_content = .{ .w = 5, .h = 5 },
    };

    wd: WidgetData = undefined,

    si: *ScrollInfo = undefined,

    // si.viewport.x/y might be updated in the middle of a frame, this prevents
    // those visual artifacts
    frame_viewport: Point = Point{},

    process_events: bool = true,
    prevClip: Rect = Rect{},

    nextVirtualSize: Size = Size{},
    next_widget_ypos: f32 = 0, // goes from 0 to viritualSize.h

    inject_capture_id: ?u32 = null,
    inject_mouse_pt: Point = .{},

    pub fn init(src: std.builtin.SourceLocation, io_scroll_info: *ScrollInfo, opts: Options) Self {
        var self = Self{};
        const options = defaults.override(opts);

        self.wd = WidgetData.init(src, .{}, options);

        self.si = io_scroll_info;

        const crect = self.wd.contentRect();
        self.si.viewport.w = crect.w;
        self.si.viewport.h = crect.h;

        self.next_widget_ypos = 0;
        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        self.process_events = opts.process_events;
        try self.wd.register("ScrollContainer", null);

        captureMouseMaintain(self.wd.id);

        // user code might have changed our rect
        const crect = self.wd.contentRect();
        self.si.viewport.w = crect.w;
        self.si.viewport.h = crect.h;

        switch (self.si.horizontal) {
            .none => self.si.virtual_size.w = crect.w,
            .auto => {},
            .given => {},
        }
        switch (self.si.vertical) {
            .none => self.si.virtual_size.h = crect.h,
            .auto => {},
            .given => {},
        }

        if (opts.process_events) {
            var evts = events();
            for (evts) |*e| {
                if (!eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r }))
                    continue;

                self.processEvent(e, false);
            }
        }

        // damping is only for touch currently
        // exponential decay: v *= damping^secs_since
        // tweak the damping so we brake harder as the velocity slows down
        {
            const damping = 0.0001 + @min(1.0, @fabs(self.si.velocity.x) / 50.0) * (0.7 - 0.0001);
            self.si.velocity.x *= @exp(@log(damping) * seconds_since_last_frame());
            if (@fabs(self.si.velocity.x) > 1) {
                //std.debug.print("vel x {d}\n", .{self.si.velocity.x});
                self.si.viewport.x += self.si.velocity.x;
                refresh();
            } else {
                self.si.velocity.x = 0;
            }

            const max_scroll = self.si.scroll_max(.horizontal);
            if (self.si.viewport.x < 0) {
                self.si.velocity.x = 0;
                self.si.viewport.x = @min(0, @max(-20, self.si.viewport.x + 250 * seconds_since_last_frame()));
                if (self.si.viewport.x < 0) {
                    refresh();
                }
            } else if (self.si.viewport.x > max_scroll) {
                self.si.velocity.x = 0;
                self.si.viewport.x = @max(max_scroll, @min(max_scroll + 20, self.si.viewport.x - 250 * seconds_since_last_frame()));
                if (self.si.viewport.x > max_scroll) {
                    refresh();
                }
            }
        }

        {
            const damping = 0.0001 + @min(1.0, @fabs(self.si.velocity.y) / 50.0) * (0.7 - 0.0001);
            self.si.velocity.y *= @exp(@log(damping) * seconds_since_last_frame());
            if (@fabs(self.si.velocity.y) > 1) {
                //std.debug.print("vel y {d}\n", .{self.si.velocity.y});
                self.si.viewport.y += self.si.velocity.y;
                refresh();
            } else {
                self.si.velocity.y = 0;
            }

            const max_scroll = self.si.scroll_max(.vertical);

            if (self.si.viewport.y < 0) {
                self.si.velocity.y = 0;
                self.si.viewport.y = @min(0, @max(-20, self.si.viewport.y + 250 * seconds_since_last_frame()));
                if (self.si.viewport.y < 0) {
                    refresh();
                }
            } else if (self.si.viewport.y > max_scroll) {
                self.si.velocity.y = 0;
                self.si.viewport.y = @max(max_scroll, @min(max_scroll + 20, self.si.viewport.y - 250 * seconds_since_last_frame()));
                if (self.si.viewport.y > max_scroll) {
                    refresh();
                }
            }
        }

        try self.wd.borderAndBackground(.{});

        self.prevClip = clip(self.wd.contentRectScale().r);

        self.frame_viewport = self.si.viewport.topleft();

        _ = parentSet(self.widget());
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        var expand = e;
        const y = self.next_widget_ypos;
        const h = self.si.virtual_size.h - y;
        const rect = Rect{ .x = 0, .y = y, .w = self.si.virtual_size.w, .h = h };
        const ret = placeIn(rect, minSize(id, min_size), expand, g);
        self.next_widget_ypos = (ret.y + ret.h);
        return ret;
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        var r = rect;
        r.y -= self.frame_viewport.y;
        r.x -= self.frame_viewport.x;

        return self.wd.contentRectScale().rectToScreen(r);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.nextVirtualSize.h += s.h;
        self.nextVirtualSize.w = @max(self.nextVirtualSize.w, s.w);
        const padded = self.wd.padSize(self.nextVirtualSize);
        switch (self.si.vertical) {
            .none => self.wd.min_size.h = padded.h,
            .auto, .given => {},
        }
        switch (self.si.horizontal) {
            .none => self.wd.min_size.w = padded.w,
            .auto, .given => {},
        }
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        switch (e.evt) {
            .key => |ke| {
                if (bubbling or (self.wd.id == focusedWidgetId())) {
                    if (ke.code == .up and (ke.action == .down or ke.action == .repeat)) {
                        e.handled = true;
                        if (self.si.vertical != .none) {
                            self.si.viewport.y -= 10;
                            self.si.viewport.y = math.clamp(self.si.viewport.y, 0, self.si.scroll_max(.vertical));
                        }
                        refresh();
                    } else if (ke.code == .down and (ke.action == .down or ke.action == .repeat)) {
                        e.handled = true;
                        if (self.si.vertical != .none) {
                            self.si.viewport.y += 10;
                            self.si.viewport.y = math.clamp(self.si.viewport.y, 0, self.si.scroll_max(.vertical));
                        }
                        refresh();
                    } else if (ke.code == .left and (ke.action == .down or ke.action == .repeat)) {
                        e.handled = true;
                        if (self.si.horizontal != .none) {
                            self.si.viewport.x -= 10;
                            self.si.viewport.x = math.clamp(self.si.viewport.x, 0, self.si.scroll_max(.horizontal));
                        }
                        refresh();
                    } else if (ke.code == .right and (ke.action == .down or ke.action == .repeat)) {
                        e.handled = true;
                        if (self.si.horizontal != .none) {
                            self.si.viewport.x += 10;
                            self.si.viewport.x = math.clamp(self.si.viewport.x, 0, self.si.scroll_max(.horizontal));
                        }
                        refresh();
                    }
                }
            },
            .scroll_drag => |sd| {
                e.handled = true;
                const rs = self.wd.contentRectScale();
                var scrolly: f32 = 0;
                if (sd.mouse_pt.y <= rs.r.y and // want to scroll up
                    sd.screen_rect.y < rs.r.y and // scrolling would show more of child
                    self.si.viewport.y > 0) // can scroll up
                {
                    scrolly = if (sd.injected) -200 * seconds_since_last_frame() else -5;
                }

                if (sd.mouse_pt.y >= (rs.r.y + rs.r.h) and
                    (sd.screen_rect.y + sd.screen_rect.h) > (rs.r.y + rs.r.h) and
                    self.si.viewport.y < self.si.scroll_max(.vertical))
                {
                    scrolly = if (sd.injected) 200 * seconds_since_last_frame() else 5;
                }

                var scrollx: f32 = 0;
                if (sd.mouse_pt.x <= rs.r.x and // want to scroll left
                    sd.screen_rect.x < rs.r.x and // scrolling would show more of child
                    self.si.viewport.x > 0) // can scroll left
                {
                    scrollx = if (sd.injected) -200 * seconds_since_last_frame() else -5;
                }

                if (sd.mouse_pt.x >= (rs.r.x + rs.r.w) and
                    (sd.screen_rect.x + sd.screen_rect.w) > (rs.r.x + rs.r.w) and
                    self.si.viewport.x < self.si.scroll_max(.horizontal))
                {
                    scrollx = if (sd.injected) 200 * seconds_since_last_frame() else 5;
                }

                if (scrolly != 0 or scrollx != 0) {
                    if (scrolly != 0) {
                        self.si.viewport.y = @max(0.0, @min(self.si.scroll_max(.vertical), self.si.viewport.y + scrolly));
                    }
                    if (scrollx != 0) {
                        self.si.viewport.x = @max(0.0, @min(self.si.scroll_max(.horizontal), self.si.viewport.x + scrollx));
                    }

                    refresh();

                    // if we are scrolling, then we need a motion event next
                    // frame so that the child widget can adjust selection
                    self.inject_capture_id = sd.capture_id;
                    self.inject_mouse_pt = sd.mouse_pt;
                }
            },
            .scroll_to => |st| {
                e.handled = true;
                const rs = self.wd.contentRectScale();

                const ypx = @max(0.0, rs.r.y - st.screen_rect.y);
                if (ypx > 0) {
                    self.si.viewport.y = self.si.viewport.y - (ypx / rs.s);
                    if (!st.over_scroll) {
                        self.si.viewport.y = @max(0.0, @min(self.si.scroll_max(.vertical), self.si.viewport.y));
                    }
                    refresh();
                }

                const ypx2 = @max(0.0, (st.screen_rect.y + st.screen_rect.h) - (rs.r.y + rs.r.h));
                if (ypx2 > 0) {
                    self.si.viewport.y = self.si.viewport.y + (ypx2 / rs.s);
                    if (!st.over_scroll) {
                        self.si.viewport.y = @max(0.0, @min(self.si.scroll_max(.vertical), self.si.viewport.y));
                    }
                    refresh();
                }

                const xpx = @max(0.0, rs.r.x - st.screen_rect.x);
                if (xpx > 0) {
                    self.si.viewport.x = self.si.viewport.x - (xpx / rs.s);
                    if (!st.over_scroll) {
                        self.si.viewport.x = @max(0.0, @min(self.si.scroll_max(.horizontal), self.si.viewport.x));
                    }
                    refresh();
                }

                const xpx2 = @max(0.0, (st.screen_rect.x + st.screen_rect.w) - (rs.r.x + rs.r.w));
                if (xpx2 > 0) {
                    self.si.viewport.x = self.si.viewport.x + (xpx2 / rs.s);
                    if (!st.over_scroll) {
                        self.si.viewport.x = @max(0.0, @min(self.si.scroll_max(.horizontal), self.si.viewport.x));
                    }
                    refresh();
                }
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn processEventsAfter(self: *Self) void {
        const rs = self.wd.borderRectScale();
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.wd.id, .r = rs.r }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .focus) {
                        e.handled = true;
                        // focus so that we can receive keyboard input
                        focusWidget(self.wd.id, null, e.num);
                    } else if (me.action == .wheel_y) {
                        // scroll vertically if we can, otherwise try horizontal
                        if (self.si.vertical != .none) {
                            if ((me.data.wheel_y > 0 and self.si.viewport.y <= 0) or (me.data.wheel_y < 0 and self.si.viewport.y >= self.si.scroll_max(.vertical))) {
                                // propogate the scroll event because we are already maxxed out
                            } else {
                                e.handled = true;
                                self.si.viewport.y -= me.data.wheel_y;
                                self.si.viewport.y = math.clamp(self.si.viewport.y, 0, self.si.scroll_max(.vertical));
                                refresh();
                            }
                        } else if (self.si.horizontal != .none) {
                            if ((me.data.wheel_y > 0 and self.si.viewport.x <= 0) or (me.data.wheel_y < 0 and self.si.viewport.x >= self.si.scroll_max(.horizontal))) {
                                // propogate the scroll event because we are already maxxed out
                            } else {
                                e.handled = true;
                                self.si.viewport.x -= me.data.wheel_y;
                                self.si.viewport.x = math.clamp(self.si.viewport.x, 0, self.si.scroll_max(.horizontal));
                                refresh();
                            }
                        }
                    } else if (me.action == .press and me.button.touch()) {
                        // don't let this event go through to floating window
                        // which would capture the mouse preventing scrolling
                        e.handled = true;
                    } else if (me.action == .release and captured(self.wd.id)) {
                        e.handled = true;
                        captureMouse(null);
                    } else if (me.action == .motion and me.button.touch()) {
                        // Whether to propogate out to any containing scroll
                        // containers. Propogate unless we did the whole scroll
                        // in the main direction of movement.
                        //
                        // This helps prevent spurious propogation from a text
                        // entry box where you are trying to scroll vertically
                        // but the motion event has a small amount of
                        // horizontal.
                        var propogate: bool = true;

                        if (self.si.vertical != .none) {
                            self.si.viewport.y -= me.data.motion.y / rs.s;
                            self.si.velocity.y = -me.data.motion.y / rs.s;
                            refresh();
                            if (@fabs(me.data.motion.y) > @fabs(me.data.motion.x) and self.si.viewport.y >= 0 and self.si.viewport.y <= self.si.scroll_max(.vertical)) {
                                propogate = false;
                            }
                        }
                        if (self.si.horizontal != .none) {
                            self.si.viewport.x -= me.data.motion.x / rs.s;
                            self.si.velocity.x = -me.data.motion.x / rs.s;
                            refresh();
                            if (@fabs(me.data.motion.x) > @fabs(me.data.motion.y) and self.si.viewport.x >= 0 and self.si.viewport.x <= self.si.scroll_max(.horizontal)) {
                                propogate = false;
                            }
                        }

                        if (propogate) {
                            captureMouse(null);
                        } else {
                            e.handled = true;
                            captureMouse(self.wd.id);
                        }
                    }
                },
                else => {},
            }
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.process_events) {
            self.processEventsAfter();
        }

        if (self.inject_capture_id) |ci| {
            if (ci == captureMouseId()) {
                // inject a mouse motion event into next frame
                currentWindow().inject_motion_event = true;
            }
        }

        clipSet(self.prevClip);

        const crect = self.wd.contentRect();
        switch (self.si.horizontal) {
            .none => {},
            .auto => {
                self.nextVirtualSize.w = @max(self.nextVirtualSize.w, crect.w);
                if (self.nextVirtualSize.w != self.si.virtual_size.w) {
                    self.si.virtual_size.w = self.nextVirtualSize.w;
                    refresh();
                }
            },
            .given => {},
        }

        switch (self.si.vertical) {
            .none => {},
            .auto => {
                self.nextVirtualSize.h = @max(self.nextVirtualSize.h, crect.h);
                if (self.nextVirtualSize.h != self.si.virtual_size.h) {
                    self.si.virtual_size.h = self.nextVirtualSize.h;
                    refresh();
                }
            },
            .given => {},
        }

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub const ScrollBarWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .expand = .vertical,
        .color_style = .content,
        .min_size_content = .{ .w = 10, .h = 10 },
    };

    pub const InitOptions = struct {
        scroll_info: *ScrollInfo,
        direction: enums.Direction = .vertical,
        focus_id: ?u32 = null,
        overlay: bool = false,
    };

    wd: WidgetData = undefined,
    process_events: bool = true,
    grabRect: Rect = Rect{},
    si: *ScrollInfo = undefined,
    focus_id: ?u32 = null,
    dir: enums.Direction = undefined,
    overlay: bool = false,
    highlight: bool = false,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        var self = Self{};
        self.si = init_opts.scroll_info;
        self.focus_id = init_opts.focus_id;
        self.dir = init_opts.direction;
        self.overlay = init_opts.overlay;

        var options = defaults.override(opts);
        if (self.overlay) {
            // we don't want to take any space from parent
            options.min_size_content = .{ .w = 5, .h = 5 };
            options.rect = placeIn(parentGet().data().contentRect().justSize(), options.min_sizeGet(), opts.expandGet(), opts.gravityGet());
        }
        self.wd = WidgetData.init(src, .{}, options);

        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        self.process_events = opts.process_events;
        try self.wd.register("ScrollBar", null);
        try self.wd.borderAndBackground(.{});

        captureMouseMaintain(self.wd.id);

        self.grabRect = self.wd.contentRect();
        switch (self.dir) {
            .vertical => {
                self.grabRect.h = @min(self.grabRect.h, @max(20.0, self.grabRect.h * self.si.fraction_visible(self.dir)));
                const insideH = self.wd.contentRect().h - self.grabRect.h;
                self.grabRect.y += insideH * self.si.scroll_fraction(self.dir);
            },
            .horizontal => {
                self.grabRect.w = @min(self.grabRect.w, @max(20.0, self.grabRect.w * self.si.fraction_visible(self.dir)));
                const insideH = self.wd.contentRect().w - self.grabRect.w;
                self.grabRect.x += insideH * self.si.scroll_fraction(self.dir);
            },
        }

        if (opts.process_events) {
            const grabrs = self.wd.parent.screenRectScale(self.grabRect);
            self.processEvents(grabrs.r);
        }
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn processEvents(self: *Self, grabrs: Rect) void {
        const rs = self.wd.borderRectScale();
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.data().id, .r = rs.r }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    switch (me.action) {
                        .focus => {
                            if (self.focus_id) |fid| {
                                e.handled = true;
                                focusWidget(fid, null, e.num);
                            }
                        },
                        .press => {
                            if (me.button.pointer()) {
                                e.handled = true;
                                if (grabrs.contains(me.p)) {
                                    // capture and start drag
                                    _ = captureMouse(self.data().id);
                                    switch (self.dir) {
                                        .vertical => dragPreStart(me.p, .arrow, .{ .y = me.p.y - (grabrs.y + grabrs.h / 2) }),
                                        .horizontal => dragPreStart(me.p, .arrow, .{ .x = me.p.x - (grabrs.x + grabrs.w / 2) }),
                                    }
                                } else {
                                    var fi = self.si.fraction_visible(self.dir);
                                    // the last page is scroll fraction 1.0, so there is
                                    // one less scroll position between 0 and 1.0
                                    fi = 1.0 / ((1.0 / fi) - 1);
                                    var f: f32 = undefined;
                                    if (if (self.dir == .vertical) (me.p.y < grabrs.y) else (me.p.x < grabrs.x)) {
                                        // clicked above grab
                                        f = self.si.scroll_fraction(self.dir) - fi;
                                    } else {
                                        // clicked below grab
                                        f = self.si.scroll_fraction(self.dir) + fi;
                                    }
                                    self.si.scrollToFraction(self.dir, f);
                                    refresh();
                                }
                            }
                        },
                        .release => {
                            if (me.button.pointer()) {
                                e.handled = true;
                                // stop possible drag and capture
                                captureMouse(null);
                            }
                        },
                        .motion => {
                            if (captured(self.data().id)) {
                                e.handled = true;
                                // move if dragging
                                if (dragging(me.p)) |dps| {
                                    _ = dps;
                                    const min = switch (self.dir) {
                                        .vertical => rs.r.y + grabrs.h / 2,
                                        .horizontal => rs.r.x + grabrs.w / 2,
                                    };
                                    const max = switch (self.dir) {
                                        .vertical => rs.r.y + rs.r.h - grabrs.h / 2,
                                        .horizontal => rs.r.x + rs.r.w - grabrs.w / 2,
                                    };
                                    const grabmid = switch (self.dir) {
                                        .vertical => me.p.y - dragOffset().y,
                                        .horizontal => me.p.x - dragOffset().x,
                                    };
                                    var f: f32 = 0;
                                    if (max > min) {
                                        f = (grabmid - min) / (max - min);
                                    }
                                    self.si.scrollToFraction(self.dir, f);
                                    refresh();
                                }
                            }
                        },
                        .position => {
                            e.handled = true;
                            self.highlight = true;
                        },
                        .wheel_y => {
                            e.handled = true;
                            switch (self.dir) {
                                .vertical => {
                                    self.si.viewport.y -= me.data.wheel_y;
                                    self.si.viewport.y = math.clamp(self.si.viewport.y, 0, self.si.scroll_max(.vertical));
                                },
                                .horizontal => {
                                    self.si.viewport.x -= me.data.wheel_y;
                                    self.si.viewport.x = math.clamp(self.si.viewport.x, 0, self.si.scroll_max(.horizontal));
                                },
                            }
                            refresh();
                        },
                    }
                },
                else => {},
            }

            if (e.bubbleable()) {
                self.wd.parent.processEvent(e, true);
            }
        }
    }

    pub fn deinit(self: *Self) void {
        var fill = self.wd.options.color(.text).transparent(0.5);
        if (captured(self.wd.id) or self.highlight) {
            fill = self.wd.options.color(.text).transparent(0.3);
        }
        self.grabRect = self.grabRect.insetAll(2);
        const grabrs = self.wd.parent.screenRectScale(self.grabRect);
        pathAddRect(grabrs.r, Rect.all(100)) catch {};
        pathFillConvex(fill) catch {};

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
    }
};

pub fn separator(src: std.builtin.SourceLocation, opts: Options) !void {
    const defaults: Options = .{
        .background = true, // TODO: remove this when border and background are no longer coupled
        .border = .{ .x = 1, .y = 1, .w = 0, .h = 0 },
        .color_style = .content,
    };

    var wd = WidgetData.init(src, .{}, defaults.override(opts));
    try wd.register("Separator", null);
    try wd.borderAndBackground(.{});
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
}

pub fn spacer(src: std.builtin.SourceLocation, size: Size, opts: Options) WidgetData {
    if (opts.min_size_content != null) {
        std.debug.print("warning: spacer options had min_size but is being overwritten\n", .{});
    }
    var wd = WidgetData.init(src, .{}, opts.override(.{ .min_size_content = size }));
    wd.register("Spacer", null) catch {};
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
    return wd;
}

pub fn spinner(src: std.builtin.SourceLocation, opts: Options) !void {
    var defaults: Options = .{
        .min_size_content = .{ .w = 50, .h = 50 },
    };
    const options = defaults.override(opts);
    var wd = WidgetData.init(src, .{}, options);
    try wd.register("Spinner", null);
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    if (wd.rect.empty()) {
        return;
    }

    const rs = wd.contentRectScale();
    const r = rs.r;

    var angle: f32 = 0;
    var anim = Animation{ .start_val = 0, .end_val = 2 * math.pi, .end_time = 4_500_000 };
    if (animationGet(wd.id, "_angle")) |a| {
        // existing animation
        var aa = a;
        if (aa.end_time <= 0) {
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
    var ret = try currentWindow().arena.create(ScaleWidget);
    ret.* = ScaleWidget.init(src, scale_in, opts);
    try ret.install(.{});
    return ret;
}

pub const ScaleWidget = struct {
    const Self = @This();
    wd: WidgetData = undefined,
    scale: f32 = undefined,
    box: BoxWidget = undefined,

    pub fn init(src: std.builtin.SourceLocation, scale_in: f32, opts: Options) Self {
        var self = Self{};
        self.wd = WidgetData.init(src, .{}, opts);
        self.scale = scale_in;
        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());
        try self.wd.register("Scale", null);
        try self.wd.borderAndBackground(.{});

        self.box = BoxWidget.init(@src(), .vertical, false, self.wd.options.strip().override(.{ .expand = .both }));
        try self.box.install(.{});
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        var s: f32 = undefined;
        if (self.scale > 0) {
            s = 1.0 / self.scale;
        } else {
            // prevent divide by zero
            s = 1_000_000.0;
        }

        return placeIn(self.wd.contentRect().justSize().scale(s), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        var rs = self.wd.contentRectScale();
        rs.s *= self.scale;
        return rs.rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s.scale(self.scale)));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        self.box.deinit();
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub fn menu(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) !*MenuWidget {
    var ret = try currentWindow().arena.create(MenuWidget);
    ret.* = MenuWidget.init(src, .{ .dir = dir }, opts);
    try ret.install(.{});
    return ret;
}

pub const MenuWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .color_style = .window,
    };

    pub const InitOptions = struct {
        dir: enums.Direction = undefined,
        submenus_activated_by_default: bool = false,
    };

    wd: WidgetData = undefined,

    init_opts: InitOptions = undefined,
    winId: u32 = undefined,
    parentMenu: ?*MenuWidget = null,
    parentSubwindowId: ?u32 = null,
    box: BoxWidget = undefined,

    // whether submenus should be open
    submenus_activated: bool = false,

    // whether submenus in a child menu should default to open (for mouse interactions, not for keyboard)
    submenus_in_child: bool = false,
    mouse_over: bool = false,

    // if we have a child popup menu, save it's rect for next frame
    // supports mouse skipping over menu items if towards the submenu
    child_popup_rect: ?Rect = null,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) MenuWidget {
        var self = Self{};
        const options = defaults.override(opts);
        self.wd = WidgetData.init(src, .{}, options);
        self.init_opts = init_opts;

        self.winId = subwindowCurrentId();
        if (dataGet(null, self.wd.id, "_sub_act", bool)) |a| {
            self.submenus_activated = a;
        } else if (menuGet()) |pm| {
            self.submenus_activated = pm.submenus_in_child;
        } else {
            self.submenus_activated = init_opts.submenus_activated_by_default;
        }

        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());
        self.parentMenu = menuSet(self);
        try self.wd.register("Menu", null);
        try self.wd.borderAndBackground(.{});

        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r }))
                continue;

            self.processEvent(e, false);
        }

        self.box = BoxWidget.init(@src(), self.init_opts.dir, false, self.wd.options.strip().override(.{ .expand = .both }));
        try self.box.install(.{});
    }

    pub fn close(self: *Self) void {
        // bubble this event to close all popups that had submenus leading to this
        var e = Event{ .evt = .{ .close_popup = .{} } };
        self.processEvent(&e, true);
        refresh();
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .position) {
                    if (mouseTotalMotion().nonZero()) {
                        if (dataGet(null, self.wd.id, "_child_popup", Rect)) |r| {
                            const center = Point{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
                            const cw = currentWindow();
                            const to_center = Point.diff(center, cw.mouse_pt_prev);
                            const movement = Point.diff(cw.mouse_pt, cw.mouse_pt_prev);
                            const dot_prod = movement.x * to_center.x + movement.y * to_center.y;
                            const cos = dot_prod / (to_center.length() * movement.length());
                            if (std.math.acos(cos) < std.math.pi / 3.0) {
                                // there is an existing submenu and motion is
                                // towards the popup, so eat this event to
                                // prevent any menu items from focusing
                                e.handled = true;
                            }
                        }

                        if (!e.handled) {
                            self.mouse_over = true;
                        }
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .escape => {
                            e.handled = true;
                            var closeE = Event{ .evt = .{ .close_popup = .{} } };
                            self.processEvent(&closeE, true);
                        },
                        .up => {
                            if (self.init_opts.dir == .vertical) {
                                e.handled = true;
                                // TODO: don't do this if focus would move outside the menu
                                tabIndexPrev(e.num);
                            }
                        },
                        .down => {
                            if (self.init_opts.dir == .vertical) {
                                e.handled = true;
                                // TODO: don't do this if focus would move outside the menu
                                tabIndexNext(e.num);
                            }
                        },
                        .left => {
                            if (self.init_opts.dir == .vertical) {
                                e.handled = true;
                                if (self.parentMenu) |pm| {
                                    pm.submenus_activated = false;
                                }
                                if (self.parentSubwindowId) |sid| {
                                    focusSubwindow(sid, null);
                                }
                            } else {
                                // TODO: don't do this if focus would move outside the menu
                                tabIndexPrev(e.num);
                            }
                        },
                        .right => {
                            if (self.init_opts.dir == .vertical) {
                                e.handled = true;
                                if (self.parentMenu) |pm| {
                                    pm.submenus_activated = false;
                                }
                                if (self.parentSubwindowId) |sid| {
                                    focusSubwindow(sid, null);
                                }
                            } else {
                                e.handled = true;
                                // TODO: don't do this if focus would move outside the menu
                                tabIndexNext(e.num);
                            }
                        },
                        else => {},
                    }
                }
            },
            .close_popup => {
                self.submenus_activated = false;
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        self.box.deinit();
        dataSet(null, self.wd.id, "_sub_act", self.submenus_activated);
        if (self.child_popup_rect) |r| {
            dataSet(null, self.wd.id, "_child_popup", r);
        }
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = menuSet(self.parentMenu);
        _ = parentSet(self.wd.parent);
    }
};

pub fn menuItemLabel(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) !?Rect {
    var mi = try menuItem(src, init_opts, opts);

    var labelopts = opts.strip();

    var ret: ?Rect = null;
    if (mi.activeRect()) |r| {
        ret = r;
    }

    if (mi.show_active) {
        labelopts = labelopts.override(.{ .color_style = .accent });
    }

    try labelNoFmt(@src(), label_str, labelopts);

    mi.deinit();

    return ret;
}

pub fn menuItemIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) !?Rect {
    var mi = try menuItem(src, init_opts, opts);

    var iconopts = opts.strip();

    var ret: ?Rect = null;
    if (mi.activeRect()) |r| {
        ret = r;
    }

    if (mi.show_active) {
        iconopts = iconopts.override(.{ .color_style = .accent });
    }

    try icon(@src(), name, tvg_bytes, iconopts);

    mi.deinit();

    return ret;
}

pub fn menuItem(src: std.builtin.SourceLocation, init_opts: MenuItemWidget.InitOptions, opts: Options) !*MenuItemWidget {
    var ret = try currentWindow().arena.create(MenuItemWidget);
    ret.* = MenuItemWidget.init(src, init_opts, opts);
    try ret.install(.{});
    return ret;
}

pub const MenuItemWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .color_style = .content,
        .corner_radius = Rect.all(5),
        .padding = Rect.all(4),
        .expand = .horizontal,
    };

    pub const InitOptions = struct {
        submenu: bool = false,
    };

    wd: WidgetData = undefined,
    focused_last_frame: bool = undefined,
    highlight: bool = false,
    init_opts: InitOptions = undefined,
    activated: bool = false,
    show_active: bool = false,
    mouse_over: bool = false,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        var self = Self{};
        const options = defaults.override(opts);
        self.wd = WidgetData.init(src, .{}, options);
        self.init_opts = init_opts;
        self.focused_last_frame = dataGet(null, self.wd.id, "_focus_last", bool) orelse false;
        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true, focus_as_outline: bool = false }) !void {
        try self.wd.register("MenuItem", null);

        // For most widgets we only tabIndexSet if they are visible, but menu
        // items are often in large dropdowns that are scrollable, plus the
        // up/down arrow keys get used to move between menu items, so you need
        // to be able to move to the next menu item even if it's not visible
        try tabIndexSet(self.wd.id, self.wd.options.tab_index);

        if (opts.process_events) {
            var evts = events();
            for (evts) |*e| {
                if (!eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r }))
                    continue;

                self.processEvent(e, false);
            }
        }

        try self.wd.borderAndBackground(.{});

        var focused: bool = false;
        if (self.wd.id == focusedWidgetId()) {
            focused = true;
        }

        if (focused and menuGet().?.mouse_over and !self.mouse_over) {
            // our menu got a mouse over but we didn't even though we were focused
            focused = false;
            focusWidget(null, null, null);
        }

        if (focused or ((self.wd.id == focusedWidgetIdInCurrentSubwindow()) and self.highlight)) {
            if (!self.init_opts.submenu or !menuGet().?.submenus_activated) {
                self.show_active = true;

                if (!self.focused_last_frame) {
                    // in case we are in a scrollable dropdown, scroll
                    var scrollto = Event{ .evt = .{ .scroll_to = .{ .screen_rect = self.wd.borderRectScale().r } } };
                    self.wd.parent.processEvent(&scrollto, true);
                }
            }
        }

        self.focused_last_frame = focused;

        if (self.show_active) {
            if (opts.focus_as_outline) {
                try self.wd.focusBorder();
            } else {
                const rs = self.wd.backgroundRectScale();
                try pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
                try pathFillConvex(self.wd.options.color(.accent));
            }
        } else if ((self.wd.id == focusedWidgetIdInCurrentSubwindow()) or self.highlight) {
            const rs = self.wd.backgroundRectScale();
            try pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
            try pathFillConvex(self.wd.options.color(.hover));
        } else if (self.wd.options.backgroundGet()) {
            const rs = self.wd.backgroundRectScale();
            try pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
            try pathFillConvex(self.wd.options.color(.fill));
        }

        _ = parentSet(self.widget());
    }

    pub fn activeRect(self: *const Self) ?Rect {
        var act = false;
        if (self.init_opts.submenu) {
            if (menuGet().?.submenus_activated and (self.wd.id == focusedWidgetIdInCurrentSubwindow())) {
                act = true;
            }
        } else if (self.activated) {
            act = true;
        }

        if (act) {
            const rs = self.wd.backgroundRectScale();
            return rs.r.scale(1 / windowNaturalScale());
        } else {
            return null;
        }
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handled = true;
                    focusWidget(self.wd.id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    // this is how dropdowns are triggered
                    e.handled = true;
                    if (self.init_opts.submenu) {
                        menuGet().?.submenus_activated = true;
                        menuGet().?.submenus_in_child = true;
                    }
                } else if (me.action == .release) {
                    e.handled = true;
                    if (!self.init_opts.submenu and (self.wd.id == focusedWidgetIdInCurrentSubwindow())) {
                        self.activated = true;
                        refresh();
                    }
                } else if (me.action == .position) {
                    e.handled = true;

                    // We get a .position mouse event every frame.  If we
                    // focus the menu item under the mouse even if it's not
                    // moving then it breaks keyboard navigation.
                    if (mouseTotalMotion().nonZero()) {
                        self.highlight = true;
                        self.mouse_over = true;
                        if (menuGet().?.submenus_activated) {
                            // we shouldn't have gotten this event if the motion
                            // was towards a submenu (caught in MenuWidget)
                            focusSubwindow(null, null); // focuses the window we are in
                            focusWidget(self.wd.id, null, null);

                            if (self.init_opts.submenu) {
                                menuGet().?.submenus_in_child = true;
                            }
                        }
                    }
                }
            },
            .key => |ke| {
                if (ke.code == .space and ke.action == .down) {
                    e.handled = true;
                    if (self.init_opts.submenu) {
                        menuGet().?.submenus_activated = true;
                    } else {
                        self.activated = true;
                        refresh();
                    }
                } else if (ke.code == .right and ke.action == .down) {
                    if (self.init_opts.submenu and menuGet().?.init_opts.dir == .vertical) {
                        e.handled = true;
                        menuGet().?.submenus_activated = true;
                    }
                } else if (ke.code == .down and ke.action == .down) {
                    if (self.init_opts.submenu and menuGet().?.init_opts.dir == .horizontal) {
                        e.handled = true;
                        menuGet().?.submenus_activated = true;
                    }
                }
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        dataSet(null, self.wd.id, "_focus_last", self.focused_last_frame);
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub const LabelWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .padding = Rect.all(4),
    };

    wd: WidgetData = undefined,
    label_str: []const u8 = undefined,

    pub fn init(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) !Self {
        const l = try std.fmt.allocPrint(currentWindow().arena, fmt, args);
        return try Self.initNoFmt(src, l, opts);
    }

    pub fn initNoFmt(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) !Self {
        var self = Self{};
        const options = defaults.override(opts);
        self.label_str = label_str;

        var size = try options.fontGet().textSize(self.label_str);
        size = Size.max(size, options.min_size_contentGet());

        self.wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));

        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        try self.wd.register("Label", null);
        try self.wd.borderAndBackground(.{});

        var rect = placeIn(self.wd.contentRect(), self.wd.options.min_size_contentGet(), .none, self.wd.options.gravityGet());
        var rs = self.wd.parent.screenRectScale(rect);
        const oldclip = clip(rs.r);
        var iter = std.mem.split(u8, self.label_str, "\n");
        while (iter.next()) |line| {
            const lineRect = placeIn(self.wd.contentRect(), try self.wd.options.fontGet().textSize(line), .none, self.wd.options.gravityGet());
            const liners = self.wd.parent.screenRectScale(lineRect);

            rs.r.x = liners.r.x;
            try renderText(.{
                .font = self.wd.options.fontGet(),
                .text = line,
                .rs = rs,
                .color = self.wd.options.color(.text),
                .debug = self.wd.options.debugGet(),
            });
            rs.r.y += rs.s * try self.wd.options.fontGet().lineHeight();
        }
        clipSet(oldclip);

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

pub fn label(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) !void {
    var lw = try LabelWidget.init(src, fmt, args, opts);
    try lw.install(.{});
    lw.deinit();
}

pub fn labelNoFmt(src: std.builtin.SourceLocation, str: []const u8, opts: Options) !void {
    var lw = try LabelWidget.initNoFmt(src, str, opts);
    try lw.install(.{});
    lw.deinit();
}

pub const IconWidget = struct {
    const Self = @This();

    wd: WidgetData = undefined,
    name: []const u8 = undefined,
    tvg_bytes: []const u8 = undefined,

    pub fn init(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, opts: Options) !Self {
        var self = Self{};
        const options = opts;
        self.name = name;
        self.tvg_bytes = tvg_bytes;

        var size = Size{};
        if (options.min_size_content) |msc| {
            // user gave us a min size, use it
            size = msc;
            size.w = @max(size.w, iconWidth(name, tvg_bytes, size.h) catch size.w);
        } else {
            // user didn't give us one, make it the height of text
            const h = options.fontGet().lineHeight() catch 10;
            size = Size{ .w = iconWidth(name, tvg_bytes, h) catch h, .h = h };
        }

        self.wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));

        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        try self.wd.register("Icon", null);
        //debug("{x} Icon \"{s:<10}\" {} {d}", .{ self.wd.id, self.name, self.wd.rect, self.wd.options.rotationGet() });

        try self.wd.borderAndBackground(.{});

        var rect = placeIn(self.wd.contentRect(), self.wd.options.min_size_contentGet(), .none, self.wd.options.gravityGet());
        var rs = self.wd.parent.screenRectScale(rect);
        try renderIcon(self.name, self.tvg_bytes, rs, self.wd.options.rotationGet(), self.wd.options.color(.text));

        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

pub fn icon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, opts: Options) !void {
    var iw = try IconWidget.init(src, name, tvg_bytes, opts);
    try iw.install(.{});
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

    var wd = WidgetData.init(src, .{}, opts.override(.{ .min_size_content = size }));
    try wd.register("debugFontAtlases", null);

    try wd.borderAndBackground(.{});

    const rs = wd.parent.screenRectScale(placeIn(wd.contentRect(), size, .none, opts.gravityGet()));
    try debugRenderFontAtlases(rs, opts.color(.text));

    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
}

pub const ButtonWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .color_style = .control,
        .margin = Rect.all(4),
        .corner_radius = Rect.all(5),
        .padding = Rect.all(4),
        .background = true,
    };
    wd: WidgetData = undefined,
    hover: bool = false,
    focus: bool = false,
    click: bool = false,

    pub fn init(src: std.builtin.SourceLocation, opts: Options) Self {
        var self = Self{};
        self.wd = WidgetData.init(src, .{}, defaults.override(opts));
        captureMouseMaintain(self.wd.id);
        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true, draw_focus: bool = true }) !void {
        try self.wd.register("Button", null);
        _ = parentSet(self.widget());

        if (self.wd.visible()) {
            try tabIndexSet(self.wd.id, self.wd.options.tab_index);
        }

        if (opts.process_events) {
            var evts = events();
            for (evts) |*e| {
                if (!eventMatch(e, .{ .id = self.data().id, .r = self.data().borderRectScale().r }))
                    continue;

                self.processEvent(e, false);
            }
        }

        self.focus = (self.wd.id == focusedWidgetId());

        var fill_color: ?Color = null;
        if (captured(self.wd.id)) {
            fill_color = self.wd.options.color(.press);
        } else if (self.hover) {
            fill_color = self.wd.options.color(.hover);
        }

        try self.wd.borderAndBackground(.{ .fill_color = fill_color });

        if (opts.draw_focus and self.focus) {
            try self.wd.focusBorder();
        }
    }

    pub fn focused(self: *Self) bool {
        return self.focus;
    }

    pub fn hovered(self: *Self) bool {
        return self.hover;
    }

    pub fn capture(self: *Self) bool {
        return captured(self.wd.id);
    }

    pub fn clicked(self: *Self) bool {
        return self.click;
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handled = true;
                    focusWidget(self.wd.id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    e.handled = true;
                    captureMouse(self.wd.id);

                    // drag prestart is just for touch events
                    dragPreStart(me.p, null, Point{});
                } else if (me.action == .release and me.button.pointer()) {
                    if (captured(self.wd.id)) {
                        e.handled = true;
                        captureMouse(null);
                        if (self.data().borderRectScale().r.contains(me.p)) {
                            self.click = true;
                            refresh();
                        }
                    }
                } else if (me.action == .motion and me.button.touch()) {
                    if (captured(self.wd.id)) {
                        if (dragging(me.p)) |_| {
                            // if we overcame the drag threshold, then that
                            // means the person probably didn't want to touch
                            // this button, maybe they were trying to scroll
                            captureMouse(null);
                        }
                    }
                } else if (me.action == .position) {
                    e.handled = true;
                    self.hover = true;
                }
            },
            .key => |ke| {
                if (ke.code == .space and ke.action == .down) {
                    e.handled = true;
                    self.click = true;
                    refresh();
                }
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) !bool {
    var bw = ButtonWidget.init(src, opts);
    try bw.install(.{});

    try labelNoFmt(@src(), label_str, opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));

    var click = bw.clicked();
    bw.deinit();
    return click;
}

pub fn buttonIcon(src: std.builtin.SourceLocation, height: f32, name: []const u8, tvg_bytes: []const u8, opts: Options) !bool {
    // since we are given the icon height, we can precalculate our size, which can save a frame
    const width = iconWidth(name, tvg_bytes, height) catch height;
    const iconopts = opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = .{ .w = width, .h = height } });

    var bw = ButtonWidget.init(src, opts.override(.{ .min_size_content = iconopts.min_sizeGet() }));
    try bw.install(.{});

    try icon(@src(), name, tvg_bytes, iconopts);

    var click = bw.clicked();
    bw.deinit();
    return click;
}

pub var slider_defaults: Options = .{
    .padding = Rect.all(2),
    .min_size_content = .{ .w = 20, .h = 20 },
    .color_style = .control,
};

// returns true if percent was changed
pub fn slider(src: std.builtin.SourceLocation, dir: enums.Direction, percent: *f32, opts: Options) !bool {
    const options = slider_defaults.override(opts);

    var b = try box(src, dir, options);
    defer b.deinit();

    if (b.data().visible()) {
        try tabIndexSet(b.data().id, options.tab_index);
    }

    captureMouseMaintain(b.data().id);

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
    var evts = events();
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
                        percent.* = (v - min) / (max - min);
                        percent.* = @max(0, @min(1, percent.*));
                        ret = true;
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .left, .down => {
                            e.handled = true;
                            percent.* = @max(0, @min(1, percent.* - 0.05));
                            ret = true;
                        },
                        .right, .up => {
                            e.handled = true;
                            percent.* = @max(0, @min(1, percent.* + 0.05));
                            ret = true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    const perc = @max(0, @min(1, percent.*));

    var part = trackrs.r;
    switch (dir) {
        .horizontal => part.w *= perc,
        .vertical => {
            const h = part.h * (1 - perc);
            part.y += h;
            part.h = trackrs.r.h - h;
        },
    }
    try pathAddRect(part, Rect.all(100).scale(trackrs.s));
    try pathFillConvex(options.color(.accent));

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
    try pathAddRect(part, Rect.all(100).scale(trackrs.s));
    try pathFillConvex(options.color(.fill));

    var knobRect = switch (dir) {
        .horizontal => Rect{ .x = (br.w - knobsize) * perc, .w = knobsize, .h = knobsize },
        .vertical => Rect{ .y = (br.h - knobsize) * (1 - perc), .w = knobsize, .h = knobsize },
    };

    var fill_color: Color = undefined;
    if (captured(b.data().id)) {
        fill_color = options.color(.press);
    } else if (hovered) {
        fill_color = options.color(.hover);
    } else {
        fill_color = options.color(.fill);
    }
    var knob = BoxWidget.init(@src(), .horizontal, false, .{ .rect = knobRect, .padding = .{}, .margin = .{}, .background = true, .border = Rect.all(1), .corner_radius = Rect.all(100), .color_fill = fill_color });
    try knob.install(.{});
    if (b.data().id == focusedWidgetId()) {
        try knob.wd.focusBorder();
    }
    knob.deinit();

    if (ret) {
        refresh();
    }

    return ret;
}

pub var checkbox_defaults: Options = .{
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(4),
    .color_style = .content,
};

pub fn checkbox(src: std.builtin.SourceLocation, target: *bool, label_str: ?[]const u8, opts: Options) !void {
    const options = checkbox_defaults.override(opts);

    var bw = ButtonWidget.init(src, options.strip().override(options));

    // don't want to show a focus ring around the label
    try bw.install(.{ .draw_focus = false });
    defer bw.deinit();

    if (bw.clicked()) {
        target.* = !target.*;
    }

    var b = try box(@src(), .horizontal, options.strip().override(.{ .expand = .both }));
    defer b.deinit();

    var check_size = try options.fontGet().lineHeight();
    const s = spacer(@src(), Size.all(check_size), .{ .gravity_x = 0.5, .gravity_y = 0.5 });

    var rs = s.borderRectScale();
    rs.r = rs.r.insetAll(0.5 * rs.s);

    try checkmark(target.*, bw.focused(), rs, bw.capture(), bw.hovered(), options);

    if (label_str) |str| {
        _ = spacer(@src(), .{ .w = checkbox_defaults.paddingGet().w }, .{});
        try labelNoFmt(@src(), str, options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));
    }
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
        options = opts.override(.{ .color_style = .accent });
        try pathAddRect(rs.r.insetAll(0.5 * rs.s), opts.corner_radiusGet().scale(rs.s));
    } else {
        try pathAddRect(rs.r.insetAll(rs.s), opts.corner_radiusGet().scale(rs.s));
    }

    if (pressed) {
        try pathFillConvex(options.color(.press));
    } else if (hovered) {
        try pathFillConvex(options.color(.hover));
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
    var ret = try cw.arena.create(TextEntryWidget);
    ret.* = TextEntryWidget.init(src, init_opts, opts);
    try ret.install();
    // can install corner widgets here
    //_ = try dvui.button(@src(), "upright", .{ .gravity_x = 1.0 });
    ret.processEvents();
    try ret.draw();
    return ret;
}

pub const TextEntryWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .margin = Rect.all(4),
        .corner_radius = Rect.all(5),
        .border = Rect.all(1),
        .padding = Rect.all(4),
        .background = true,
        .color_style = .content,
        // min_size_content is calculated in init()
    };

    pub const InitOptions = struct {
        text: []u8,
        break_lines: bool = false,
        scroll_vertical: ?bool = null, // default is value of multiline
        scroll_vertical_bar: ?ScrollInfo.ScrollBarMode = null, // default .auto
        scroll_horizontal: ?bool = null, // default true
        scroll_horizontal_bar: ?ScrollInfo.ScrollBarMode = null, // default .auto if multiline, .hide if not

        // must be a single utf8 character
        password_char: ?[]const u8 = null,
        multiline: bool = false,
    };

    wd: WidgetData = undefined,
    prevClip: Rect = undefined,
    scroll: ScrollAreaWidget = undefined,
    scrollClip: Rect = undefined,
    textLayout: TextLayoutWidget = undefined,
    textClip: Rect = undefined,
    padding: Rect = undefined,

    init_opts: InitOptions = undefined,
    len: usize = undefined,
    scroll_to_cursor: bool = false,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        var self = Self{};
        self.init_opts = init_opts;

        const msize = opts.fontGet().textSize("M") catch unreachable;
        var options = defaults.override(.{ .min_size_content = .{ .w = msize.w * 14, .h = msize.h } }).override(opts);

        // padding is interpreted as the padding for the TextLayoutWidget, but
        // we also need to add it to content size because TextLayoutWidget is
        // inside the scroll area
        self.padding = options.paddingGet();
        options.padding = null;
        options.min_size_content.?.w += self.padding.x + self.padding.w;
        options.min_size_content.?.h += self.padding.y + self.padding.h;

        self.wd = WidgetData.init(src, .{}, options);

        self.len = std.mem.indexOfScalar(u8, self.init_opts.text, 0) orelse self.init_opts.text.len;
        self.len = findUtf8Start(self.init_opts.text[0..self.len], self.len);
        return self;
    }

    pub fn install(self: *Self) !void {
        try self.wd.register("TextEntry", null);

        if (self.wd.visible()) {
            try tabIndexSet(self.wd.id, self.wd.options.tab_index);
        }

        _ = parentSet(self.widget());

        try self.wd.borderAndBackground(.{});

        self.prevClip = clipGet();

        self.scroll = ScrollAreaWidget.init(@src(), .{
            .vertical = if (self.init_opts.scroll_vertical orelse self.init_opts.multiline) .auto else .none,
            .vertical_bar = self.init_opts.scroll_vertical_bar orelse .auto,
            .horizontal = if (self.init_opts.scroll_horizontal orelse true) .auto else .none,
            .horizontal_bar = self.init_opts.scroll_horizontal_bar orelse (if (self.init_opts.multiline) .auto else .hide),
        }, self.wd.options.strip().override(.{ .expand = .both }));
        // scrollbars process mouse events here
        try self.scroll.install(.{ .focus_id = self.wd.id });

        self.scrollClip = clipGet();

        self.textLayout = TextLayoutWidget.init(@src(), .{ .break_lines = self.init_opts.break_lines }, self.wd.options.strip().override(.{ .expand = .both, .padding = self.padding, .min_size_content = .{} }));
        try self.textLayout.install();
        self.textClip = clipGet();

        // don't call textLayout.processEvents here, we forward events inside our own processEvents

        // textLayout is maintaining the selection for us, but if the text
        // changed, we need to update the selection to be valid before we
        // process any events
        var sel = self.textLayout.selection;
        sel.start = findUtf8Start(self.init_opts.text[0..self.len], sel.start);
        sel.cursor = findUtf8Start(self.init_opts.text[0..self.len], sel.cursor);
        sel.end = findUtf8Start(self.init_opts.text[0..self.len], sel.end);

        // textLayout clips to its content, but we need to get events out to our border
        clipSet(self.prevClip);
    }

    pub fn eventMatchOptions(self: *Self) EventMatchOptions {
        return .{ .id = self.wd.id, .r = self.wd.borderRectScale().r, .id_capture = self.textLayout.data().id };
    }

    pub fn processEvents(self: *Self) void {
        const emo = self.eventMatchOptions();
        var evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, emo))
                continue;

            self.processEvent(e, false);
        }
    }

    pub fn draw(self: *Self) !void {
        const focused = (self.wd.id == focusedWidgetId());

        // set clip back to what textLayout had, so we don't draw over the scrollbars
        clipSet(self.textClip);

        if (self.init_opts.password_char) |pc| {
            // adjust selection for obfuscation
            var count: usize = 0;
            var bytes: usize = 0;
            var sel = self.textLayout.selection;
            var sstart: ?usize = null;
            var scursor: ?usize = null;
            var send: ?usize = null;
            var utf8it = (try std.unicode.Utf8View.init(self.init_opts.text[0..self.len])).iterator();
            while (utf8it.nextCodepoint()) |codepoint| {
                if (sstart == null and sel.start == bytes) sstart = count * pc.len;
                if (scursor == null and sel.cursor == bytes) scursor = count * pc.len;
                if (send == null and sel.end == bytes) send = count * pc.len;
                count += 1;
                bytes += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            } else {
                if (sstart == null and sel.start >= bytes) sstart = count * pc.len;
                if (scursor == null and sel.cursor >= bytes) scursor = count * pc.len;
                if (send == null and sel.end >= bytes) send = count * pc.len;
            }
            sel.start = sstart.?;
            sel.cursor = scursor.?;
            sel.end = send.?;
            var password_str: []u8 = try currentWindow().arena.alloc(u8, count * pc.len);
            for (0..count) |i| {
                for (0..pc.len) |pci| {
                    password_str[i * pc.len + pci] = pc[pci];
                }
            }
            try self.textLayout.addText(password_str, self.wd.options.strip());
        } else {
            try self.textLayout.addText(self.init_opts.text[0..self.len], self.wd.options.strip());
        }

        try self.textLayout.addTextDone(self.wd.options.strip());

        if (self.init_opts.password_char) |pc| {
            // reset selection
            var count: usize = 0;
            var bytes: usize = 0;
            var sel = self.textLayout.selection;
            var sstart: ?usize = null;
            var scursor: ?usize = null;
            var send: ?usize = null;
            var utf8it = (try std.unicode.Utf8View.init(self.init_opts.text[0..self.len])).iterator();
            while (utf8it.nextCodepoint()) |codepoint| {
                if (sstart == null and sel.start == count * pc.len) sstart = bytes;
                if (scursor == null and sel.cursor == count * pc.len) scursor = bytes;
                if (send == null and sel.end == count * pc.len) send = bytes;
                count += 1;
                bytes += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            } else {
                if (sstart == null and sel.start >= count * pc.len) sstart = bytes;
                if (scursor == null and sel.cursor >= count * pc.len) scursor = bytes;
                if (send == null and sel.end >= count * pc.len) send = bytes;
            }
            sel.start = sstart.?;
            sel.cursor = scursor.?;
            sel.end = send.?;
        }

        if (focused) {
            if (self.textLayout.cursor_rect) |cr| {
                // the cursor can be slightly outside the textLayout clip
                clipSet(self.scrollClip);

                var crect = cr.add(.{ .x = -1 });
                crect.w = 2;
                try pathAddRect(self.textLayout.screenRectScale(crect).r, Rect.all(0));
                try pathFillConvex(self.wd.options.color(.accent));

                if (self.scroll_to_cursor) {
                    var scrollto = Event{
                        .evt = .{
                            .scroll_to = .{
                                .screen_rect = self.textLayout.screenRectScale(crect.outset(self.padding)).r,
                                // cursor might just have transitioned to a new line, so scroll area has not expanded yet
                                .over_scroll = true,
                            },
                        },
                    };
                    self.scroll.scroll.processEvent(&scrollto, true);
                }
            }
        }

        self.textLayout.deinit();
        self.scroll.deinit();

        if (focused) {
            try self.wd.focusBorder();
        }
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return placeIn(self.wd.contentRect().justSize(), minSize(id, min_size), e, g);
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        self.wd.minSizeMax(self.wd.padSize(s));
    }

    pub fn textTyped(self: *Self, new: []const u8) void {
        if (self.textLayout.selectionGet(.{})) |sel| {
            if (!sel.empty()) {
                // delete selection
                std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
                self.len -= (sel.end - sel.start);
                sel.end = sel.start;
                sel.cursor = sel.start;
            }

            var new_len = @min(new.len, self.init_opts.text.len - self.len);

            // find start of last utf8 char
            var last: usize = new_len -| 1;
            while (last < new_len and new[last] & 0xc0 == 0x80) {
                last -|= 1;
            }

            // if the last utf8 char can't fit, don't include it
            if (last < new_len) {
                const utf8_size = std.unicode.utf8ByteSequenceLength(new[last]) catch 0;
                if (utf8_size != (new_len - last)) {
                    new_len = last;
                }
            }

            // make room if we can
            if (sel.cursor + new_len < self.init_opts.text.len) {
                std.mem.copyBackwards(u8, self.init_opts.text[sel.cursor + new_len ..], self.init_opts.text[sel.cursor..self.len]);
            }

            // update our len and maintain 0 termination if possible
            self.len += new_len;
            if (self.len < self.init_opts.text.len) {
                self.init_opts.text[self.len] = 0;
            }

            // insert
            std.mem.copy(u8, self.init_opts.text[sel.cursor..], new[0..new_len]);
            sel.cursor += new_len;
            sel.end = sel.cursor;
            sel.start = sel.cursor;

            // we might have dropped to a new line, so make sure the cursor is visible
            self.scroll_to_cursor = true;
        }
    }

    // Designed to run after event processing and before drawing
    pub fn filterOut(self: *Self, filter: []const u8) void {
        if (filter.len == 0) {
            return;
        }

        var i: usize = 0;
        var j: usize = 0;
        const n = self.len;
        while (i < n) {
            if (std.mem.startsWith(u8, self.init_opts.text[i..], filter)) {
                self.len -= filter.len;
                var sel = self.textLayout.selection;
                if (sel.start > i) sel.start -= filter.len;
                if (sel.cursor > i) sel.cursor -= filter.len;
                if (sel.end > i) sel.end -= filter.len;

                i += filter.len;
            } else {
                self.init_opts.text[j] = self.init_opts.text[i];
                i += 1;
                j += 1;
            }
        }

        if (j < self.init_opts.text.len)
            self.init_opts.text[j] = 0;
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        switch (e.evt) {
            .key => |ke| {
                switch (ke.code) {
                    .backspace => {
                        if (ke.action == .down or ke.action == .repeat) {
                            e.handled = true;
                            if (self.textLayout.selectionGet(.{})) |sel| {
                                if (!sel.empty()) {
                                    // just delete selection
                                    std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
                                    self.len -= (sel.end - sel.start);
                                    self.init_opts.text[self.len] = 0;
                                    sel.end = sel.start;
                                    sel.cursor = sel.start;
                                    self.scroll_to_cursor = true;
                                } else if (sel.cursor > 0) {
                                    // delete character just before cursor
                                    //
                                    // A utf8 char might consist of more than one byte.
                                    // Find the beginning of the last byte by iterating over
                                    // the string backwards. The first byte of a utf8 char
                                    // does not have the pattern 10xxxxxx.
                                    var i: usize = 1;
                                    while (self.init_opts.text[sel.cursor - i] & 0xc0 == 0x80) : (i += 1) {}
                                    std.mem.copy(u8, self.init_opts.text[sel.cursor - i ..], self.init_opts.text[sel.cursor..self.len]);
                                    self.len -= i;
                                    self.init_opts.text[self.len] = 0;
                                    sel.cursor -= i;
                                    sel.start = sel.cursor;
                                    sel.end = sel.cursor;
                                    self.scroll_to_cursor = true;
                                }
                            }
                        }
                    },
                    .delete => {
                        if (ke.action == .down or ke.action == .repeat) {
                            e.handled = true;
                            if (self.textLayout.selectionGet(.{})) |sel| {
                                if (!sel.empty()) {
                                    // just delete selection
                                    std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
                                    self.len -= (sel.end - sel.start);
                                    self.init_opts.text[self.len] = 0;
                                    sel.end = sel.start;
                                    sel.cursor = sel.start;
                                    self.scroll_to_cursor = true;
                                } else if (sel.cursor < self.len) {
                                    // delete the character just after the cursor
                                    //
                                    // A utf8 char might consist of more than one byte.
                                    const i = std.unicode.utf8ByteSequenceLength(self.init_opts.text[sel.cursor]) catch 1;
                                    std.mem.copy(u8, self.init_opts.text[sel.cursor..], self.init_opts.text[sel.cursor + i .. self.len]);
                                    self.len -= i;
                                    self.init_opts.text[self.len] = 0;
                                }
                            }
                        }
                    },
                    .enter => {
                        if (self.init_opts.multiline and ke.action == .down or ke.action == .repeat) {
                            e.handled = true;
                            self.textTyped("\n");
                        }
                    },
                    .tab => {
                        if (ke.action == .down) {
                            e.handled = true;
                            if (ke.mod.shift()) {
                                tabIndexPrev(e.num);
                            } else {
                                tabIndexNext(e.num);
                            }
                        }
                    },
                    .v => {
                        if (ke.action == .down and ke.mod.controlCommand()) {
                            // paste
                            e.handled = true;
                            const clip_text = dvui.clipboardText();
                            defer dvui.backendFree(clip_text.ptr);
                            if (self.init_opts.multiline) {
                                self.textTyped(clip_text);
                            } else {
                                var i: usize = 0;
                                while (i < clip_text.len) {
                                    if (std.mem.indexOfScalar(u8, clip_text[i..], '\n')) |idx| {
                                        self.textTyped(clip_text[i..][0..idx]);
                                        i += idx + 1;
                                    } else {
                                        self.textTyped(clip_text[i..]);
                                        break;
                                    }
                                }
                            }
                        }
                    },
                    .x => {
                        if (ke.action == .down and ke.mod.controlCommand()) {
                            // cut
                            e.handled = true;
                            if (self.textLayout.selectionGet(.{})) |sel| {
                                if (!sel.empty()) {
                                    // copy selection to clipboard
                                    clipboardTextSet(self.init_opts.text[sel.start..sel.end]) catch |err| {
                                        std.debug.print("clipboardTextSet: error {!}\n", .{err});
                                    };

                                    // delete selection
                                    std.mem.copy(u8, self.init_opts.text[sel.start..], self.init_opts.text[sel.end..self.len]);
                                    self.len -= (sel.end - sel.start);
                                    self.init_opts.text[self.len] = 0;
                                    sel.end = sel.start;
                                    sel.cursor = sel.start;
                                    self.scroll_to_cursor = true;
                                }
                            }
                        }
                    },
                    .left, .right => |code| {
                        if ((ke.action == .down or ke.action == .repeat) and !ke.mod.shift()) {
                            e.handled = true;
                            if (self.textLayout.selectionGet(.{})) |sel| {
                                if (code == .left) {
                                    // If the cursor is at position 0 do nothing...
                                    if (sel.cursor > 0) {
                                        // ... otherwise, "jump over" the utf8 char to the
                                        // left of the cursor.
                                        var i: usize = 1;
                                        while (sel.cursor -| i > 0 and self.init_opts.text[sel.cursor -| i] & 0xc0 == 0x80) : (i += 1) {}
                                        sel.cursor -|= i;
                                    }
                                } else {
                                    if (sel.cursor < self.len) {
                                        // Get the number of bytes of the current code point and
                                        // "jump" to the next code point to the right of the cursor.
                                        sel.cursor += std.unicode.utf8ByteSequenceLength(self.init_opts.text[sel.cursor]) catch 1;
                                        sel.cursor = @min(sel.cursor, self.len);
                                    }
                                }

                                sel.start = sel.cursor;
                                sel.end = sel.cursor;
                                self.scroll_to_cursor = true;
                            }
                        }
                    },
                    .up, .down => |code| {
                        if ((ke.action == .down or ke.action == .repeat) and !ke.mod.shift()) {
                            e.handled = true;
                            if (self.textLayout.selectionGet(.{ .check_updown = false })) |_| {
                                self.textLayout.cursor_updown += if (code == .down) 1 else -1;
                                self.textLayout.cursor_updown_drag = false;
                            }
                        }
                    },
                    else => {},
                }
            },
            .text => |te| {
                e.handled = true;
                var new = std.mem.sliceTo(te, 0);
                if (self.init_opts.multiline) {
                    self.textTyped(new);
                } else {
                    var i: usize = 0;
                    while (i < new.len) {
                        if (std.mem.indexOfScalar(u8, new[i..], '\n')) |idx| {
                            self.textTyped(new[i..][0..idx]);
                            i += idx + 1;
                        } else {
                            self.textTyped(new[i..]);
                            break;
                        }
                    }
                }
            },
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handled = true;
                    focusWidget(self.wd.id, null, e.num);
                }
            },
            else => {},
        }

        if (!e.handled and !bubbling) {
            self.textLayout.processEvent(e, false);
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        clipSet(self.prevClip);
        self.wd.minSizeSetAndRefresh();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub const RectScale = struct {
    r: Rect = Rect{},
    s: f32 = 0.0,

    pub fn rectToScreen(rs: *const RectScale, r: Rect) RectScale {
        return .{ .r = r.scale(rs.s).offset(rs.r), .s = rs.s };
    }

    pub fn pointToScreen(rs: *const RectScale, p: Point) Point {
        return p.scale(rs.s).plus(rs.r.topleft());
    }

    pub fn pointFromScreen(rs: *const RectScale, p: Point) Point {
        return Point.diff(p, rs.r.topleft()).scale(1 / rs.s);
    }
};

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
    if (clipGet().intersect(opts.rs.r).empty()) return;
    if (opts.text.len == 0) return;

    if (!std.unicode.utf8ValidateSlice(opts.text)) {
        std.debug.print("renderText: invalid utf8 for \"{s}\"\n", .{opts.text});
        return error.InvalidUtf8;
    }

    var cw = currentWindow();

    if (!cw.rendering) {
        var opts_copy = opts;
        opts_copy.text = try cw.arena.dupe(u8, opts.text);
        var cmd = RenderCmd{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .text = opts_copy } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);

        return;
    }

    // Make sure to always ask for a bigger size font, we'll reduce it down below
    const target_size = opts.font.size * opts.rs.s;
    const ask_size = @ceil(target_size);
    const target_fraction = target_size / ask_size;

    const sized_font = opts.font.resize(ask_size);
    var fce = try fontCacheGet(sized_font);

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

                rowlen += (gi.maxx - gi.minx) + 2 * pad;
                i += 1;
            } else {
                size.w = @max(size.w, rowlen);
            }

            size = size.ceil();
        }

        // also add an extra padding around whole texture
        size.w += 2 * pad;
        size.h += 2 * pad;

        var pixels = try cw.arena.alloc(u8, @as(usize, @intFromFloat(size.w * size.h)) * 4);
        // set all pixels as white but with zero alpha
        for (pixels, 0..) |*p, i| {
            if (i % 4 == 3) {
                p.* = 0;
            } else {
                p.* = 255;
            }
        }

        //const num_glyphs = fce.glyph_info.count();
        //std.debug.print("font size {d} regen glyph atlas num {d} max size {}\n", .{ sized_font.size, num_glyphs, size });

        {
            var x: i32 = pad;
            var y: i32 = pad;
            var it = fce.glyph_info.iterator();
            var i: u32 = 0;
            while (it.next()) |e| {
                e.value_ptr.uv[0] = @as(f32, @floatFromInt(x)) / size.w;
                e.value_ptr.uv[1] = @as(f32, @floatFromInt(y)) / size.h;

                const codepoint = @as(u32, @intCast(e.key_ptr.*));
                FontCacheEntry.intToError(c.FT_Load_Char(fce.face, codepoint, @as(i32, @bitCast(FontCacheEntry.LoadFlags{ .render = true })))) catch |err| {
                    std.debug.print("renderText: freetype error {!} trying to FT_Load_Char font {s} codepoint {d}\n", .{ err, opts.font.name, codepoint });
                    return error.freetypeError;
                };

                const bitmap = fce.face.*.glyph.*.bitmap;
                //std.debug.print("codepoint {d} gi {d}x{d} bitmap {d}x{d}\n", .{ e.key_ptr.*, e.value_ptr.maxx - e.value_ptr.minx, e.value_ptr.maxy - e.value_ptr.miny, bitmap.width(), bitmap.rows() });
                var row: i32 = 0;
                while (row < bitmap.rows) : (row += 1) {
                    var col: i32 = 0;
                    while (col < bitmap.width) : (col += 1) {
                        if (bitmap.buffer == null) {
                            std.debug.print("renderText: freetype error: bitmap null for font {s} codepoint {d}\n", .{ opts.font.name, codepoint });
                            return error.freetypeError;
                        }
                        const src = bitmap.buffer[@as(usize, @intCast(row * bitmap.pitch + col))];

                        // because of the extra edge, offset by 1 row and 1 col
                        const di = @as(usize, @intCast((y + row + pad) * @as(i32, @intFromFloat(size.w)) * 4 + (x + col + pad) * 4));

                        // not doing premultiplied alpha (yet), so keep the white color but adjust the alpha
                        //pixels[di] = src;
                        //pixels[di+1] = src;
                        //pixels[di+2] = src;
                        pixels[di + 3] = src;
                    }
                }

                x += @as(i32, @intCast(bitmap.width)) + 2 * pad;

                i += 1;
                if (i % row_glyphs == 0) {
                    x = pad;
                    y += @as(i32, @intFromFloat(fce.height)) + 2 * pad;
                }
            }
        }

        fce.texture_atlas = cw.backend.textureCreate(pixels, @as(u32, @intFromFloat(size.w)), @as(u32, @intFromFloat(size.h)));
        fce.texture_atlas_size = size;
    }

    //std.debug.print("creating text texture size {} font size {d} for \"{s}\"\n", .{size, font.size, text});
    var vtx = std.ArrayList(Vertex).init(cw.arena);
    defer vtx.deinit();
    var idx = std.ArrayList(u32).init(cw.arena);
    defer idx.deinit();

    var x: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.x) else opts.rs.r.x;
    var y: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.y) else opts.rs.r.y;

    if (opts.debug) {
        std.debug.print("renderText x {d} y {d}\n", .{ x, y });
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

        v.pos.x = x + (gi.minx - pad) * target_fraction;
        v.pos.y = y + (gi.miny - pad) * target_fraction;
        v.col = if (sel_in) opts.sel_color orelse opts.color else opts.color;
        v.uv = gi.uv;
        try vtx.append(v);

        if (opts.debug) {
            std.debug.print("{d} pad {d} minx {d} maxx {d} miny {d} maxy {d} x {d} y {d} ", .{ bytes_seen, pad, gi.minx, gi.maxx, gi.miny, gi.maxy, v.pos.x, v.pos.y });
        }

        v.pos.x = x + (gi.maxx + pad) * target_fraction;
        v.uv[0] = gi.uv[0] + (gi.maxx - gi.minx + 2 * pad) / fce.texture_atlas_size.w;
        try vtx.append(v);

        v.pos.y = y + (gi.maxy + pad) * target_fraction;
        sel_max_y = @max(sel_max_y, v.pos.y);
        v.uv[1] = gi.uv[1] + (gi.maxy - gi.miny + 2 * pad) / fce.texture_atlas_size.h;
        try vtx.append(v);

        if (opts.debug) {
            std.debug.print("    x {d} y {d}\n", .{ v.pos.x, v.pos.y });
        }

        v.pos.x = x + (gi.minx - pad) * target_fraction;
        v.uv[0] = gi.uv[0];
        try vtx.append(v);

        try idx.append(len + 0);
        try idx.append(len + 1);
        try idx.append(len + 2);
        try idx.append(len + 0);
        try idx.append(len + 2);
        try idx.append(len + 3);

        x = nextx;
    }

    if (sel) {
        if (opts.sel_color_bg) |bgcol| {
            var sel_vtx: [4]Vertex = undefined;
            sel_vtx[0].pos.x = sel_start_x;
            sel_vtx[0].pos.y = opts.rs.r.y;
            sel_vtx[3].pos.x = sel_start_x;
            sel_vtx[3].pos.y = @max(sel_max_y, opts.rs.r.y + fce.height * target_fraction * opts.font.line_height_factor);
            sel_vtx[1].pos.x = sel_end_x;
            sel_vtx[1].pos.y = sel_vtx[0].pos.y;
            sel_vtx[2].pos.x = sel_end_x;
            sel_vtx[2].pos.y = sel_vtx[3].pos.y;

            for (&sel_vtx) |*v| {
                v.col = bgcol;
                v.uv[0] = 0;
                v.uv[1] = 0;
            }
            cw.backend.renderGeometry(null, &sel_vtx, &[_]u32{ 0, 1, 2, 0, 2, 3 });
        }
    }

    cw.backend.renderGeometry(fce.texture_atlas, vtx.items, idx.items);
}

pub fn debugRenderFontAtlases(rs: RectScale, color: Color) !void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    var cw = currentWindow();

    if (!cw.rendering) {
        var cmd = RenderCmd{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .debug_font_atlases = .{ .rs = rs, .color = color } } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);

        return;
    }

    var x: f32 = if (cw.snap_to_pixels) @round(rs.r.x) else rs.r.x;
    var y: f32 = if (cw.snap_to_pixels) @round(rs.r.y) else rs.r.y;

    var offset: f32 = 0;
    var it = cw.font_cache.iterator();
    while (it.next()) |kv| {
        var vtx = std.ArrayList(Vertex).init(cw.arena);
        defer vtx.deinit();
        var idx = std.ArrayList(u32).init(cw.arena);
        defer idx.deinit();

        const len = @as(u32, @intCast(vtx.items.len));
        var v: Vertex = undefined;
        v.pos.x = x;
        v.pos.y = y + offset;
        v.col = color;
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

        try idx.append(len + 0);
        try idx.append(len + 1);
        try idx.append(len + 2);
        try idx.append(len + 0);
        try idx.append(len + 2);
        try idx.append(len + 3);

        cw.backend.renderGeometry(kv.value_ptr.texture_atlas, vtx.items, idx.items);

        offset += kv.value_ptr.texture_atlas_size.h;
    }
}

pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: RectScale, rotation: f32, colormod: Color) !void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    //if (true) return;

    var cw = currentWindow();

    if (!cw.rendering) {
        var name_copy = try cw.arena.dupe(u8, name);
        var cmd = RenderCmd{ .snap = cw.snap_to_pixels, .clip = clipGet(), .cmd = .{ .icon = .{ .name = name_copy, .tvg_bytes = tvg_bytes, .rs = rs, .rotation = rotation, .colormod = colormod } } };

        var sw = cw.subwindowCurrent();
        try sw.render_cmds.append(cmd);

        return;
    }

    // Make sure to always ask for a bigger size icon, we'll reduce it down below
    const target_size = rs.r.h;
    const ask_height = @ceil(target_size);
    const target_fraction = target_size / ask_height;

    const ice = iconTexture(name, tvg_bytes, @as(u32, @intFromFloat(ask_height))) catch return;

    var vtx = try std.ArrayList(Vertex).initCapacity(cw.arena, 4);
    defer vtx.deinit();
    var idx = try std.ArrayList(u32).initCapacity(cw.arena, 6);
    defer idx.deinit();

    var x: f32 = if (cw.snap_to_pixels) @round(rs.r.x) else rs.r.x;
    var y: f32 = if (cw.snap_to_pixels) @round(rs.r.y) else rs.r.y;

    var xw = x + ice.size.w * target_fraction;
    var yh = y + ice.size.h * target_fraction;

    var midx = (x + xw) / 2;
    var midy = (y + yh) / 2;

    var v: Vertex = undefined;
    v.pos.x = x;
    v.pos.y = y;
    v.col = colormod;
    v.uv[0] = 0;
    v.uv[1] = 0;
    if (rotation != 0) {
        v.pos.x = midx + (x - midx) * @cos(rotation) - (y - midy) * @sin(rotation);
        v.pos.y = midy + (x - midx) * @sin(rotation) + (y - midy) * @cos(rotation);
    }
    try vtx.append(v);

    v.pos.x = xw;
    v.uv[0] = 1;
    if (rotation != 0) {
        v.pos.x = midx + (xw - midx) * @cos(rotation) - (y - midy) * @sin(rotation);
        v.pos.y = midy + (xw - midx) * @sin(rotation) + (y - midy) * @cos(rotation);
    }
    try vtx.append(v);

    v.pos.y = yh;
    v.uv[1] = 1;
    if (rotation != 0) {
        v.pos.x = midx + (xw - midx) * @cos(rotation) - (yh - midy) * @sin(rotation);
        v.pos.y = midy + (xw - midx) * @sin(rotation) + (yh - midy) * @cos(rotation);
    }
    try vtx.append(v);

    v.pos.x = x;
    v.uv[0] = 0;
    if (rotation != 0) {
        v.pos.x = midx + (x - midx) * @cos(rotation) - (yh - midy) * @sin(rotation);
        v.pos.y = midy + (x - midx) * @sin(rotation) + (yh - midy) * @cos(rotation);
    }
    try vtx.append(v);

    try idx.append(0);
    try idx.append(1);
    try idx.append(2);
    try idx.append(0);
    try idx.append(2);
    try idx.append(3);

    cw.backend.renderGeometry(ice.texture, vtx.items, idx.items);
}

pub const Event = struct {
    handled: bool = false,
    focus_windowId: ?u32 = null,
    focus_widgetId: ?u32 = null,
    // num increments withing a frame, used in focusRemainingEvents
    num: u16 = 0,
    evt: union(enum) {
        // non-bubbleable
        mouse: Mouse,

        // bubbleable
        key: Key,
        text: []u8,
        close_popup: ClosePopup,
        scroll_drag: ScrollDrag,
        scroll_to: ScrollTo,
    },

    // All widgets have to bubble keyboard events if they can have keyboard focus
    // so that pressing the up key in any child of a scrollarea will scroll.  Call
    // this helper at the end of processEvent().
    pub fn bubbleable(self: *const Event) bool {
        return (!self.handled and (self.evt != .mouse));
    }

    pub const Key = struct {
        code: enums.Key,
        action: enum {
            down,
            repeat,
            up,
        },
        mod: enums.Mod,
    };

    pub const Mouse = struct {
        pub const Action = enum {
            // Focus events come right before their associated pointer event, usually
            // leftdown/rightdown or motion. Separated to enable changing what
            // causes focus changes.
            focus,
            press,
            release,

            wheel_y,

            // motion Point is the change in position
            // if you just want to react to the current mouse position if it got
            // moved at all, use the .position event with mouseTotalMotion()
            motion,

            // only one position event per frame, and it's always after all other
            // mouse events, used to change mouse cursor and do widget highlighting
            // - also useful with mouseTotalMotion() to respond to mouse motion but
            // only at the final location
            position,
        };

        action: Action,

        // This distinguishes between mouse and touch events.
        // .none is used for mouse motion, wheel, and position
        button: enums.Button,

        p: Point,
        floating_win: u32,

        data: union {
            none: void,
            motion: Point,
            wheel_y: f32,
        } = .{ .none = {} },
    };

    pub const ClosePopup = struct {
        // are we closing because of a specific user action (clicked on menu item,
        // pressed escape), or because they clicked off the menu somewhere?
        intentional: bool = true,
    };

    pub const ScrollDrag = struct {
        // bubbled up from a child to tell a containing scrollarea to
        // possibly scroll to show more of the child
        mouse_pt: Point,
        screen_rect: Rect,
        capture_id: u32,
        injected: bool,
    };

    pub const ScrollTo = struct {
        // bubbled up from a child to tell a containing scrollarea to
        // scroll to show the given rect
        screen_rect: Rect,

        // whether to scroll outside the current scroll bounds (useful if the
        // current action might be expanding the scroll area)
        over_scroll: bool = false,
    };
};

pub const WidgetData = struct {
    pub const InitOptions = struct {
        // if true, don't send our rect through our parent because we aren't located inside our parent
        subwindow: bool = false,
    };

    id: u32 = undefined,
    parent: Widget = undefined,
    init_options: InitOptions = undefined,
    rect: Rect = Rect{},
    min_size: Size = Size{},
    options: Options = undefined,

    pub fn init(src: std.builtin.SourceLocation, init_options: InitOptions, opts: Options) WidgetData {
        var self = WidgetData{};
        self.init_options = init_options;
        self.options = opts;

        self.parent = parentGet();
        self.id = self.parent.extendId(src, opts.idExtra());

        self.min_size = self.options.min_sizeGet();

        if (self.options.rect) |r| {
            self.rect = r;
            if (self.options.expandGet().horizontal()) {
                self.rect.w = self.parent.data().contentRect().w;
            } else if (self.rect.w == 0) {
                self.rect.w = minSize(self.id, self.min_size).w;
            }

            if (self.options.expandGet().vertical()) {
                self.rect.h = self.parent.data().contentRect().h;
            } else if (self.rect.h == 0) {
                self.rect.h = minSize(self.id, self.min_size).h;
            }
        } else {
            self.rect = self.parent.rectFor(self.id, self.min_size, self.options.expandGet(), self.options.gravityGet());
        }

        var cw = currentWindow();
        if (self.id == cw.debug_widget_id) {
            cw.debug_info_src_id_extra = std.fmt.allocPrint(cw.arena, "{s}:{d}\nid_extra {d}", .{ src.file, src.line, opts.idExtra() }) catch "";
        }

        return self;
    }

    pub fn register(self: *const WidgetData, name: []const u8, rect_scale: ?RectScale) !void {
        var cw = currentWindow();
        if (cw.debug_under_mouse or self.id == cw.debug_widget_id) {
            var rs: RectScale = undefined;
            if (rect_scale) |in| {
                rs = in;
            } else {
                rs = self.parent.screenRectScale(self.rect);
            }

            if (cw.debug_under_mouse and
                rs.r.contains(cw.mouse_pt) and
                // prevents stuff in scroll area outside viewport being caught
                clipGet().contains(cw.mouse_pt) and
                // prevents stuff in lower subwindows being caught
                cw.windowFor(cw.mouse_pt) == subwindowCurrentId())
            {
                var old = cw.debug_under_mouse_info;
                cw.debug_under_mouse_info = try std.fmt.allocPrint(cw.gpa, "{s}\n{x} {s}", .{ old, self.id, name });
                if (old.len > 0) {
                    cw.gpa.free(old);
                }

                cw.debug_widget_id = self.id;
            }

            if (self.id == cw.debug_widget_id) {
                cw.debug_info_name_rect = try std.fmt.allocPrint(cw.arena, "{x} {s}\n\n{}\n{}\nscale {d}\npadding {}\nborder {}\nmargin {}", .{ self.id, name, rs.r, self.options.expandGet(), rs.s, self.options.paddingGet().scale(rs.s), self.options.borderGet().scale(rs.s), self.options.marginGet().scale(rs.s) });
                try pathAddRect(rs.r.insetAll(0), .{});
                var color = (Options{ .color_style = .err }).color(.fill);
                try pathStrokeAfter(true, true, 3 * rs.s, .none, color);
            }
        }
    }

    pub fn visible(self: *const WidgetData) bool {
        return !clipGet().intersect(self.borderRectScale().r).empty();
    }

    pub fn borderAndBackground(self: *const WidgetData, opts: struct { fill_color: ?Color = null }) !void {
        var bg = self.options.backgroundGet();
        if (self.options.borderGet().nonZero()) {
            if (!bg) {
                std.debug.print("borderAndBackground: {x} forcing background on to support border\n", .{self.id});
                bg = true;
            }
            const rs = self.borderRectScale();
            try pathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
            var col = self.options.color(.border);
            try pathFillConvex(col);
        }

        if (bg) {
            const rs = self.backgroundRectScale();
            try pathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
            try pathFillConvex(opts.fill_color orelse self.options.color(.fill));
        }
    }

    pub fn focusBorder(self: *const WidgetData) !void {
        const rs = self.borderRectScale();
        const thick = 2 * rs.s;
        try pathAddRect(rs.r, self.options.corner_radiusGet().scale(rs.s));
        var color = self.options.color(.accent);
        try pathStrokeAfter(true, true, thick, .none, color);
    }

    pub fn rectScale(self: *const WidgetData) RectScale {
        if (self.init_options.subwindow) {
            const s = windowNaturalScale();
            const scaled = self.rect.scale(s);
            return RectScale{ .r = scaled.offset(windowRectPixels()), .s = s };
        }

        return self.parent.screenRectScale(self.rect);
    }

    pub fn borderRect(self: *const WidgetData) Rect {
        return self.rect.inset(self.options.marginGet());
    }

    pub fn borderRectScale(self: *const WidgetData) RectScale {
        const r = self.borderRect().offsetNeg(self.rect);
        return self.rectScale().rectToScreen(r);
    }

    pub fn backgroundRect(self: *const WidgetData) Rect {
        return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet());
    }

    pub fn backgroundRectScale(self: *const WidgetData) RectScale {
        const r = self.backgroundRect().offsetNeg(self.rect);
        return self.rectScale().rectToScreen(r);
    }

    pub fn contentRect(self: *const WidgetData) Rect {
        return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet()).inset(self.options.paddingGet());
    }

    pub fn contentRectScale(self: *const WidgetData) RectScale {
        const r = self.contentRect().offsetNeg(self.rect);
        return self.rectScale().rectToScreen(r);
    }

    pub fn padSize(self: *const WidgetData, s: Size) Size {
        return s.pad(self.options.paddingGet()).pad(self.options.borderGet()).pad(self.options.marginGet());
    }

    pub fn minSizeMax(self: *WidgetData, s: Size) void {
        self.min_size = Size.max(self.min_size, s);
    }

    pub fn minSizeSetAndRefresh(self: *const WidgetData) void {
        if (minSizeGet(self.id)) |ms| {
            // If the size we got was exactly our previous min size then our min size
            // was a binding constraint.  So if our min size changed it might cause
            // layout changes.

            // If this was like a Label where we knew the min size before getting our
            // rect, then either our min size is the same as previous, or our rect is
            // a different size than our previous min size.
            if ((self.rect.w == ms.w and ms.w != self.min_size.w) or
                (self.rect.h == ms.h and ms.h != self.min_size.h))
            {
                //std.debug.print("{x} minSizeSetAndRefresh {} {} {}\n", .{ self.id, self.rect, ms, self.min_size });

                refresh();
            }
        } else {
            // This is the first frame for this widget.  Almost always need a
            // second frame to appear correctly since nobody knew our min size the
            // first frame.
            refresh();
        }
        minSizeSet(self.id, self.min_size) catch |err| switch (err) {
            error.OutOfMemory => {
                // returning an error here means that all widgets deinit can return
                // it, which is very annoying because you can't "defer try
                // widget.deinit()".  Also if we are having memory issues then we
                // have larger problems than here.
                std.debug.print("minSizeSetAndRefresh: got {!} when trying to minSizeSet widget {x}\n", .{ err, self.id });
            },
        };
    }

    pub fn minSizeReportToParent(self: *const WidgetData) void {
        if (self.options.rect == null) {
            self.parent.minSizeForChild(self.min_size);
        }
    }
};

pub const Widget = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        data: *const fn (ptr: *anyopaque) *WidgetData,
        rectFor: *const fn (ptr: *anyopaque, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect,
        screenRectScale: *const fn (ptr: *anyopaque, r: Rect) RectScale,
        minSizeForChild: *const fn (ptr: *anyopaque, s: Size) void,
        processEvent: *const fn (ptr: *anyopaque, e: *Event, bubbling: bool) void,
    };

    pub fn init(
        pointer: anytype,
        comptime dataFn: fn (ptr: @TypeOf(pointer)) *WidgetData,
        comptime rectForFn: fn (ptr: @TypeOf(pointer), id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect,
        comptime screenRectScaleFn: fn (ptr: @TypeOf(pointer), r: Rect) RectScale,
        comptime minSizeForChildFn: fn (ptr: @TypeOf(pointer), s: Size) void,
        comptime processEventFn: fn (ptr: @TypeOf(pointer), e: *Event, bubbling: bool) void,
    ) Widget {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);
        std.debug.assert(ptr_info == .Pointer); // Must be a pointer
        std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer

        const gen = struct {
            fn dataImpl(ptr: *anyopaque) *WidgetData {
                const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
                return @call(.always_inline, dataFn, .{self});
            }

            fn rectForImpl(ptr: *anyopaque, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
                const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
                return @call(.always_inline, rectForFn, .{ self, id, min_size, e, g });
            }

            fn screenRectScaleImpl(ptr: *anyopaque, r: Rect) RectScale {
                const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
                return @call(.always_inline, screenRectScaleFn, .{ self, r });
            }

            fn minSizeForChildImpl(ptr: *anyopaque, s: Size) void {
                const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
                return @call(.always_inline, minSizeForChildFn, .{ self, s });
            }

            fn processEventImpl(ptr: *anyopaque, e: *Event, bubbling: bool) void {
                const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
                return @call(.always_inline, processEventFn, .{ self, e, bubbling });
            }

            const vtable = VTable{
                .data = dataImpl,
                .rectFor = rectForImpl,
                .screenRectScale = screenRectScaleImpl,
                .minSizeForChild = minSizeForChildImpl,
                .processEvent = processEventImpl,
            };
        };

        return .{
            .ptr = pointer,
            .vtable = &gen.vtable,
        };
    }

    pub fn data(self: Widget) *WidgetData {
        return self.vtable.data(self.ptr);
    }

    pub fn extendId(self: Widget, src: std.builtin.SourceLocation, id_extra: usize) u32 {
        var hash = fnv.init();
        hash.value = self.data().id;
        hash.update(src.file);
        hash.update(std.mem.asBytes(&src.line));
        hash.update(std.mem.asBytes(&src.column));
        hash.update(std.mem.asBytes(&id_extra));
        return hash.final();
    }

    pub fn rectFor(self: Widget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        return self.vtable.rectFor(self.ptr, id, min_size, e, g);
    }

    pub fn screenRectScale(self: Widget, r: Rect) RectScale {
        return self.vtable.screenRectScale(self.ptr, r);
    }

    pub fn minSizeForChild(self: Widget, s: Size) void {
        self.vtable.minSizeForChild(self.ptr, s);
    }

    pub fn processEvent(self: Widget, e: *Event, bubbling: bool) void {
        self.vtable.processEvent(self.ptr, e, bubbling);
    }
};
