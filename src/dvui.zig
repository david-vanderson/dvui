//! [DVUI](https://david-vanderson.github.io/) is a general purpose Zig GUI toolkit.
//!
//! ![<Examples-demo.png>](Examples-demo.png)
//!
//! `dvui` module contains all the top level declarations provide all declarations required by client code. - i.e. `const dvui = @import("dvui");` is the only required import.
//!
//! Most UI element are expected to be created via high level function like `dvui.button`, which instantiate the corresponding lower level `dvui.ButtonWidget` for you.
//!
//! Custom widget can be done for simple cases my combining different high level function. For more advance usages, the user is expected to copy-paste the content of the high level functions as a starting point to combine the widgets on the lower level. More informations is available in the [project's readme](https://github.com/david-vanderson/dvui/blob/main/README.md).
//!
//! A complete list of available widgets can be found under `dvui.widgets`.
//!
//! ## Backends
//! - [SDL](#dvui.backends.sdl)
//! - [Web](#dvui.backends.web)
//! - [rayLib](#dvui.backends.raylib)
//! - [Dx11](#dvui.backends.dx11)
//! - [Testing](#dvui.backends.testing)
//!
const builtin = @import("builtin");
const std = @import("std");
/// Using this in application code will hinder ZLS from referencing the correct backend.
/// To avoid this import the backend directly from the applications build.zig
///
/// ```zig
/// // build.zig
/// mod.addImport("dvui", dvui_dep.module("dvui_sdl3"));
/// mod.addImport("backend", dvui_dep.module("sdl3"));
///
/// // src/main.zig
/// const dvui = @import("dvui");
/// const Backend = @import("backend");
/// ```
pub const backend = @import("backend");
const tvg = @import("svg2tvg");

pub const math = std.math;
pub const fnv = std.hash.Fnv1a_64;

pub const App = @import("App.zig");
pub const Backend = @import("Backend.zig");
pub const Window = @import("Window.zig");
pub const Examples = @import("Examples.zig");

pub const Color = @import("Color.zig");
pub const Event = @import("Event.zig");
pub const Font = @import("Font.zig");
pub const Options = @import("Options.zig");
pub const Point = @import("Point.zig").Point;
pub const Rect = @import("Rect.zig").Rect;
pub const RectScale = @import("RectScale.zig");
pub const ScrollInfo = @import("ScrollInfo.zig");
pub const Size = @import("Size.zig").Size;
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
pub const ColorPickerWidget = widgets.ColorPickerWidget;
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
pub const TreeWidget = widgets.TreeWidget;
pub const VirtualParentWidget = widgets.VirtualParentWidget;
pub const GridWidget = widgets.GridWidget;
const se = @import("structEntry.zig");
pub const structEntry = se.structEntry;
pub const structEntryEx = se.structEntryEx;
pub const structEntryAlloc = se.structEntryAlloc;
pub const structEntryExAlloc = se.structEntryExAlloc;
pub const StructFieldOptions = se.StructFieldOptions;

pub const enums = @import("enums.zig");
pub const easing = @import("easing.zig");
pub const testing = @import("testing.zig");
pub const selection = @import("selection.zig");
pub const ShrinkingArenaAllocator = @import("shrinking_arena_allocator.zig").ShrinkingArenaAllocator;
pub const TrackingAutoHashMap = @import("tracking_hash_map.zig").TrackingAutoHashMap;

pub const wasm = (builtin.target.cpu.arch == .wasm32 or builtin.target.cpu.arch == .wasm64);
pub const useFreeType = !wasm;

/// The amount of physical pixels to scroll per "tick" of the scroll wheel
pub var scroll_speed: f32 = 20;

/// Used as a default maximum in various places:
/// * Options.max_size_content
/// * Font.textSizeEx max_width
///
/// This is a compromise between desires:
/// * gives a decent range
/// * is a normal number (not nan/inf) that works in normal math
/// * can still have some extra added to it (like padding)
/// * float precision in this range (0.125) is small enough so integer stuff still works
///
/// If positions/sizes are getting into this range, then likely something is going wrong.
pub const max_float_safe: f32 = 1_000_000; // 1000000 and 1e6 for searchability

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

pub const Error = std.mem.Allocator.Error || StbImageError || TvgError || FontError;
pub const TvgError = error{tvgError};
pub const StbImageError = error{stbImageError};
pub const FontError = error{fontError};

pub const log = std.log.scoped(.dvui);
const dvui = @This();

/// A generic id created by hashing `std.builting.SourceLocation`'s (from `@src()`)
pub const Id = enum(u64) {
    zero = 0,
    // This may not work in future and is illegal behaviour / arch specific to compare to undefined.
    undef = 0xAAAAAAAAAAAAAAAA,
    _,

    /// Make a unique id from `src` and `id_extra`, possibly starting with start
    /// (usually a parent widget id).  This is how the initial parent widget id is
    /// created, and also toasts and dialogs from other threads.
    ///
    /// See `Widget.extendId` which calls this with the widget id as start.
    ///
    /// ```zig
    /// dvui.parentGet().extendId(@src(), id_extra)
    /// ```
    /// is how new widgets get their id, and can be used to make a unique id without
    /// making a widget.
    pub fn extendId(start: ?Id, src: std.builtin.SourceLocation, id_extra: usize) Id {
        var hash = fnv.init();
        if (start) |s| {
            hash.value = s.asU64();
        }
        hash.update(std.mem.asBytes(&src.module.ptr));
        hash.update(std.mem.asBytes(&src.file.ptr));
        hash.update(std.mem.asBytes(&src.line));
        hash.update(std.mem.asBytes(&src.column));
        hash.update(std.mem.asBytes(&id_extra));
        return @enumFromInt(hash.final());
    }

    /// Make a new id by combining id with some data, commonly a string key like `"_value"`.
    /// This is how dvui tracks things in `dataGet`/`dataSet`, `animation`, and `timer`.
    pub fn update(id: Id, input: []const u8) Id {
        var h = fnv.init();
        h.value = id.asU64();
        h.update(input);
        return @enumFromInt(h.final());
    }

    pub fn asU64(self: Id) u64 {
        return @intFromEnum(self);
    }

    /// ALWAYS prefer using `asU64` unless a `usize` is required as it could
    /// loose precision and uniqueness on non-64bit platforms (like wasm32).
    ///
    /// Using an `Id` as `Options.id_extra` would be a valid use of this function
    pub fn asUsize(self: Id) usize {
        // usize might be u32 (like on wasm32)
        return @truncate(@intFromEnum(self));
    }

    pub fn format(self: *const Id, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "{" ++ fmt ++ "}", .{self.asU64()});
    }
};

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

/// Allocates space for a widget to the alloc stack, or the arena
/// if the stack overflows.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn widgetAlloc(comptime T: type) *T {
    if (@import("build_options").zig_arena orelse false) {
        return currentWindow().arena().create(T) catch @panic("OOM");
    }

    const cw = currentWindow();
    const alloc = cw._widget_stack.allocator();
    const ptr = alloc.create(T) catch {
        log.debug("Widget stack overflowed, falling back to long term arena allocator", .{});
        return cw.arena().create(T) catch @panic("OOM");
    };
    // std.debug.print("PUSH {*} ({d}) {x}\n", .{ ptr, @alignOf(@TypeOf(ptr)), cw._widget_stack.end_index });
    return ptr;
}

/// Pops a widget off the alloc stack, if it was allocated there.
///
/// This should always be called in `deinit` to ensure the widget
/// is popped.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn widgetFree(ptr: anytype) void {
    if (@import("build_options").zig_arena orelse false) {
        return;
    }

    const ws = &currentWindow()._widget_stack;
    // NOTE: We cannot use `allocatorLIFO` because of widgets that
    //       store other widgets in their fields, which would cause
    //       errors when attempting to free as they are not on the
    //       top of the stack
    ws.allocator().destroy(ptr);
}

pub fn logError(src: std.builtin.SourceLocation, err: anyerror, comptime fmt: []const u8, args: anytype) void {
    @branchHint(.cold);
    const stack_trace_frame_count = @import("build_options").log_stack_trace orelse if (builtin.mode == .Debug) 12 else 0;
    const stack_trace_enabled = stack_trace_frame_count > 0;
    const err_trace_enabled = if (@import("build_options").log_error_trace) |enabled| enabled else stack_trace_enabled;

    var addresses: [stack_trace_frame_count]usize = @splat(0);
    var stack_trace = std.builtin.StackTrace{ .instruction_addresses = &addresses, .index = 0 };
    if (!builtin.strip_debug_info) std.debug.captureStackTrace(@returnAddress(), &stack_trace);

    const error_trace_fmt, const err_trace_arg = if (err_trace_enabled)
        .{ "\nError trace: {?}", @errorReturnTrace() }
    else
        .{ "{s}", "" }; // Needed to keep the arg count the same
    const stack_trace_fmt, const trace_arg = if (stack_trace_enabled)
        .{ "\nStack trace: {}", stack_trace }
    else
        .{ "{s}", "" }; // Needed to keep the arg count the sames

    // There is no nice way to combine a comptime tuple and a runtime tuple
    const combined_args = switch (std.meta.fields(@TypeOf(args)).len) {
        0 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), err_trace_arg, trace_arg },
        1 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], err_trace_arg, trace_arg },
        2 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], err_trace_arg, trace_arg },
        3 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], args[2], err_trace_arg, trace_arg },
        4 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], args[2], args[3], err_trace_arg, trace_arg },
        5 => .{ src.file, src.line, src.column, src.fn_name, @errorName(err), args[0], args[1], args[2], args[3], args[4], err_trace_arg, trace_arg },
        else => @compileError("Too many arguments"),
    };
    log.err("{s}:{d}:{d}: {s} got {s}: " ++ fmt ++ error_trace_fmt ++ stack_trace_fmt, combined_args);
}

/// Get the active theme.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn themeGet() Theme {
    return currentWindow().theme;
}

/// Set the active theme.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn themeSet(theme: Theme) void {
    currentWindow().theme = theme;
}

/// Toggle showing the debug window (run during `Window.end`).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toggleDebugWindow() void {
    var cw = currentWindow();
    cw.debug.open = !cw.debug.open;
}

pub const TagData = struct {
    id: Id,
    rect: Rect.Physical,
    visible: bool,
};

pub fn tag(name: []const u8, data: TagData) void {
    var cw = currentWindow();

    if (cw.tags.map.getPtr(name)) |old_data| {
        if (old_data.used) {
            dvui.log.err("duplicate tag name \"{s}\" id {x} (highlighted in red); you may need to pass .{{.id_extra=<loop index>}} as widget options (see https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids )\n", .{ name, data.id });
            cw.debug.widget_id = data.id;
        }

        old_data.*.inner = data;
        old_data.used = true;
        return;
    }

    //std.debug.print("tag dupe {s}\n", .{name});
    const name_copy = cw.gpa.dupe(u8, name) catch |err| {
        dvui.log.err("tag() got {!} for name {s}\n", .{ err, name });
        return;
    };

    cw.tags.put(cw.gpa, name_copy, data) catch |err| {
        dvui.log.err("tag() \"{s}\" got {!} for id {x}\n", .{ name, err, data.id });
        cw.gpa.free(name_copy);
    };
}

pub fn tagGet(name: []const u8) ?TagData {
    return currentWindow().tags.get(name);
}

/// Help left-align widgets by adding horizontal spacers.
///
/// Only valid between `Window.begin`and `Window.end`.
pub const Alignment = struct {
    id: Id,
    scale: f32,
    max: ?f32,
    next: f32,

    pub fn init(src: std.builtin.SourceLocation, id_extra: usize) Alignment {
        const parent = dvui.parentGet();
        const id = parent.extendId(src, id_extra);
        return .{
            .id = id,
            .scale = parent.data().rectScale().s,
            .max = dvui.dataGet(null, id, "_max_align", f32),
            .next = -1_000_000,
        };
    }

    /// Add spacer with margin.x so they all end at the same edge.
    pub fn spacer(self: *Alignment, src: std.builtin.SourceLocation, id_extra: usize) void {
        const uniqueId = dvui.parentGet().extendId(src, id_extra);
        var wd = dvui.spacer(src, .{ .margin = self.margin(uniqueId), .id_extra = id_extra });
        self.record(uniqueId, &wd);
    }

    /// Get the margin needed to align this id's left edge.
    pub fn margin(self: *Alignment, id: Id) Rect {
        if (self.max) |m| {
            if (dvui.dataGet(null, id, "_align", f32)) |a| {
                return .{ .x = @max(0, (m - a) / self.scale) };
            }
        }

        return .{};
    }

    /// Record where this widget ended up so we can align it next frame.
    pub fn record(self: *Alignment, id: Id, wd: *WidgetData) void {
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
        self.* = undefined;
    }
};

/// Controls how `placeOnScreen` will move start to avoid spawner.
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
pub fn placeOnScreen(screen: Rect.Natural, spawner: Rect.Natural, avoid: PlaceOnScreenAvoid, start: Rect.Natural) Rect.Natural {
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
/// Updated during `Window.begin`.  Will not go backwards.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn frameTimeNS() i128 {
    return currentWindow().frame_time_ns;
}

/// The bytes of a truetype font file and whether to free it.
pub const FontBytesEntry = struct {
    ttf_bytes: []const u8,
    name: []const u8,

    /// If not null, this will be used to free ttf_bytes.
    allocator: ?std.mem.Allocator,
};

/// Add font to be referenced later by name.
///
/// ttf_bytes are the bytes of the ttf file
///
/// If ttf_bytes_allocator is not null, it will be used to free `ttf_bytes` AND `name` in
/// `Window.deinit`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn addFont(name: []const u8, ttf_bytes: []const u8, ttf_bytes_allocator: ?std.mem.Allocator) (std.mem.Allocator.Error || FontError)!void {
    var cw = currentWindow();

    // Test if we can successfully open this font
    const id = Font.FontId.fromName(name);
    _ = try fontCacheInit(ttf_bytes, .{ .id = id, .size = 14 }, name);
    try cw.font_bytes.put(cw.gpa, id, FontBytesEntry{
        .name = name,
        .ttf_bytes = ttf_bytes,
        .allocator = ttf_bytes_allocator,
    });
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
    face: if (useFreeType) c.FT_Face else c.stbtt_fontinfo,
    // This name should come from `Window.font_bytes` and lives as long as it does
    name: []const u8,
    scaleFactor: f32,
    height: f32,
    ascent: f32,
    glyph_info: std.AutoHashMap(u32, GlyphInfo),
    texture_atlas_cache: ?Texture = null,

    pub fn deinit(self: *FontCacheEntry, win: *Window) void {
        if (useFreeType) {
            _ = c.FT_Done_Face(self.face);
        }
        if (self.texture_atlas_cache) |tex| win.backend.textureDestroy(tex);
        self.* = undefined;
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

    pub fn invalidateTextureAtlas(self: *FontCacheEntry) void {
        if (self.texture_atlas_cache) |tex| {
            dvui.textureDestroyLater(tex);
        }
        self.texture_atlas_cache = null;
    }

    /// This needs to be called before rendering of glyphs as the uv coordinates
    /// of the glyphs will not be correct if the atlas needs to be generated.
    pub fn getTextureAtlas(fce: *FontCacheEntry) Backend.TextureError!Texture {
        if (fce.texture_atlas_cache) |tex| return tex;

        // number of extra pixels to add on each side of each glyph
        const pad = 1;

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

        const cw = currentWindow();

        var pixels = try cw.lifo().alloc(Color.PMA, @as(usize, @intFromFloat(size.w * size.h)));
        defer cw.lifo().free(pixels);
        // set all pixels to zero alpha
        @memset(pixels, .transparent);

        //const num_glyphs = fce.glyph_info.count();
        //std.debug.print("font size {d} regen glyph atlas num {d} max size {}\n", .{ sized_font.size, num_glyphs, size });

        var x: i32 = pad;
        var y: i32 = pad;
        var it = fce.glyph_info.iterator();
        var i: u32 = 0;
        while (it.next()) |e| {
            var gi = e.value_ptr;
            gi.uv[0] = @as(f32, @floatFromInt(x + pad)) / size.w;
            gi.uv[1] = @as(f32, @floatFromInt(y + pad)) / size.h;

            const codepoint = @as(u32, @intCast(e.key_ptr.*));

            if (useFreeType) blk: {
                FontCacheEntry.intToError(c.FT_Load_Char(fce.face, codepoint, @as(i32, @bitCast(FontCacheEntry.LoadFlags{ .render = true })))) catch |err| {
                    log.warn("renderText: freetype error {!} trying to FT_Load_Char codepoint {d}", .{ err, codepoint });
                    break :blk; // will skip the failing glyph
                };

                // https://freetype.org/freetype2/docs/tutorial/step1.html#section-6
                if (fce.face.*.glyph.*.format != c.FT_GLYPH_FORMAT_BITMAP) {
                    FontCacheEntry.intToError(c.FT_Render_Glyph(fce.face.*.glyph, c.FT_RENDER_MODE_NORMAL)) catch |err| {
                        log.warn("renderText freetype error {!} trying to FT_Render_Glyph codepoint {d}", .{ err, codepoint });
                        break :blk; // will skip the failing glyph
                    };
                }

                const bitmap = fce.face.*.glyph.*.bitmap;
                var row: i32 = 0;
                while (row < bitmap.rows) : (row += 1) {
                    var col: i32 = 0;
                    while (col < bitmap.width) : (col += 1) {
                        const src = bitmap.buffer[@as(usize, @intCast(row * bitmap.pitch + col))];

                        // because of the extra edge, offset by 1 row and 1 col
                        const di = @as(usize, @intCast((y + row + pad) * @as(i32, @intFromFloat(size.w)) + (x + col + pad)));

                        // premultiplied white
                        pixels[di] = .{ .r = src, .g = src, .b = src, .a = src };
                    }
                }
            } else {
                const out_w: u32 = @intFromFloat(gi.w);
                const out_h: u32 = @intFromFloat(gi.h);

                // single channel
                const bitmap = try cw.lifo().alloc(u8, @as(usize, out_w * out_h));
                defer cw.lifo().free(bitmap);

                //log.debug("makecodepointBitmap size x {d} y {d} w {d} h {d} out w {d} h {d}", .{ x, y, size.w, size.h, out_w, out_h });

                c.stbtt_MakeCodepointBitmapSubpixel(&fce.face, bitmap.ptr, @as(c_int, @intCast(out_w)), @as(c_int, @intCast(out_h)), @as(c_int, @intCast(out_w)), fce.scaleFactor, fce.scaleFactor, 0.0, 0.0, @as(c_int, @intCast(codepoint)));

                const stride = @as(usize, @intFromFloat(size.w));
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
                y += @as(i32, @intFromFloat(fce.height)) + 2 * pad;
            }
        }

        fce.texture_atlas_cache = try textureCreate(pixels, @as(u32, @intFromFloat(size.w)), @as(u32, @intFromFloat(size.h)), .linear);
        return fce.texture_atlas_cache.?;
    }

    /// If a codepoint is missing in the font it gets the glyph for
    /// `std.unicode.replacement_character`
    pub fn glyphInfoGetOrReplacement(self: *FontCacheEntry, codepoint: u32) std.mem.Allocator.Error!GlyphInfo {
        return self.glyphInfoGet(codepoint) catch |err| switch (err) {
            FontError.fontError => self.glyphInfoGet(std.unicode.replacement_character) catch unreachable,
            else => |e| e,
        };
    }

    pub fn glyphInfoGet(self: *FontCacheEntry, codepoint: u32) (std.mem.Allocator.Error || FontError)!GlyphInfo {
        if (self.glyph_info.get(codepoint)) |gi| {
            return gi;
        }

        var gi: GlyphInfo = undefined;

        if (useFreeType) {
            FontCacheEntry.intToError(c.FT_Load_Char(self.face, codepoint, @as(i32, @bitCast(LoadFlags{ .render = false })))) catch |err| {
                log.warn("glyphInfoGet freetype error {!} font {s} codepoint {d}\n", .{ err, self.name, codepoint });
                return FontError.fontError;
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
        self.invalidateTextureAtlas();

        try self.glyph_info.put(codepoint, gi);
        return gi;
    }

    /// Doesn't scale the font or max_width, always stops at newlines
    ///
    /// Assumes the text is valid utf8. Will exit early with non-full
    /// size on invalid utf8
    pub fn textSizeRaw(
        fce: *FontCacheEntry,
        text: []const u8,
        max_width: ?f32,
        end_idx: ?*usize,
        end_metric: Font.EndMetric,
    ) std.mem.Allocator.Error!Size {
        const mwidth = max_width orelse max_float_safe;

        var x: f32 = 0;
        var minx: f32 = 0;
        var maxx: f32 = 0;
        var miny: f32 = 0;
        var maxy: f32 = fce.height;
        var tw: f32 = 0;
        var th: f32 = fce.height;

        var ei: usize = 0;
        var nearest_break: bool = false;

        var utf8 = std.unicode.Utf8View.initUnchecked(text).iterator();
        var last_codepoint: u32 = 0;
        var last_glyph_index: u32 = 0;
        while (utf8.nextCodepoint()) |codepoint| {
            const gi = try fce.glyphInfoGetOrReplacement(codepoint);

            // kerning
            if (last_codepoint != 0) {
                if (useFreeType) {
                    if (last_glyph_index == 0) last_glyph_index = c.FT_Get_Char_Index(fce.face, last_codepoint);
                    const glyph_index: u32 = c.FT_Get_Char_Index(fce.face, codepoint);
                    var kern: c.FT_Vector = undefined;
                    FontCacheEntry.intToError(c.FT_Get_Kerning(fce.face, last_glyph_index, glyph_index, c.FT_KERNING_DEFAULT, &kern)) catch |err| {
                        log.warn("renderText freetype error {!} trying to FT_Get_Kerning font {s} codepoints {d} {d}\n", .{ err, fce.name, last_codepoint, codepoint });
                        // Set fallback kern and continue to the best of out ability
                        kern.x = 0;
                        kern.y = 0;
                        // return FontError.fontError;
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

// Get or load the underlying font at an integer size <= font.size (guaranteed to have a minimum pixel size of 1)
pub fn fontCacheGet(font: Font) std.mem.Allocator.Error!*FontCacheEntry {
    var cw = currentWindow();
    const fontHash = font.hash();
    if (cw.font_cache.getPtr(fontHash)) |fce| return fce;

    const ttf_bytes, const name = if (cw.font_bytes.get(font.id)) |fbe|
        .{ fbe.ttf_bytes, fbe.name }
    else blk: {
        log.warn("Font {} not in dvui database, using default", .{font.id});
        break :blk .{ Font.default_ttf_bytes, @tagName(Font.default_font_id) };
    };
    //log.debug("FontCacheGet creating font hash {x} ptr {*} size {d} name \"{s}\"", .{ fontHash, bytes.ptr, font.size, font.name });

    const entry = fontCacheInit(ttf_bytes, font, name) catch {
        if (font.id == Font.default_font_id) {
            @panic("Default font could not be loaded");
        }
        return fontCacheGet(font.switchFont(Font.default_font_id));
    };

    //log.debug("- size {d} ascent {d} height {d}", .{ font.size, entry.ascent, entry.height });

    try cw.font_cache.putNoClobber(cw.gpa, fontHash, entry);
    return cw.font_cache.getPtr(fontHash).?;
}

// Load the underlying font at an integer size <= font.size (guaranteed to have a minimum pixel size of 1)
pub fn fontCacheInit(ttf_bytes: []const u8, font: Font, name: []const u8) FontError!FontCacheEntry {
    const min_pixel_size = 1;

    if (useFreeType) {
        var face: c.FT_Face = undefined;
        var args: c.FT_Open_Args = undefined;
        args.flags = @as(u32, @bitCast(FontCacheEntry.OpenFlags{ .memory = true }));
        args.memory_base = ttf_bytes.ptr;
        args.memory_size = @as(u31, @intCast(ttf_bytes.len));
        FontCacheEntry.intToError(c.FT_Open_Face(ft2lib, &args, 0, &face)) catch |err| {
            log.warn("fontCacheInit freetype error {!} trying to FT_Open_Face font {s}\n", .{ err, name });
            return FontError.fontError;
        };

        // "pixel size" for freetype doesn't actually mean you'll get that height, it's more like using pts
        // so we search for a font that has a height <= font.size
        var pixel_size = @as(u32, @intFromFloat(@max(min_pixel_size, @floor(font.size))));

        while (true) : (pixel_size -= 1) {
            FontCacheEntry.intToError(c.FT_Set_Pixel_Sizes(face, pixel_size, pixel_size)) catch |err| {
                log.warn("fontCacheInit freetype error {!} trying to FT_Set_Pixel_Sizes font {s}\n", .{ err, name });
                return FontError.fontError;
            };

            const ascender = @as(f32, @floatFromInt(face.*.ascender)) / 64.0;
            const ss = @as(f32, @floatFromInt(face.*.size.*.metrics.y_scale)) / 0x10000;
            const ascent = ascender * ss;
            const height = @as(f32, @floatFromInt(face.*.size.*.metrics.height)) / 64.0;

            //std.debug.print("height {d} -> pixel_size {d}\n", .{ height, pixel_size });

            if (height <= font.size or pixel_size == min_pixel_size) {
                return FontCacheEntry{
                    .face = face,
                    .name = name,
                    .scaleFactor = 1.0, // not used with freetype
                    .height = @ceil(height),
                    .ascent = @floor(ascent),
                    .glyph_info = std.AutoHashMap(u32, GlyphInfo).init(currentWindow().gpa),
                };
            }
        }
    } else {
        const offset = c.stbtt_GetFontOffsetForIndex(ttf_bytes.ptr, 0);
        if (offset < 0) {
            log.warn("fontCacheInit stbtt error when calling stbtt_GetFontOffsetForIndex font {s}\n", .{name});
            return FontError.fontError;
        }
        var face: c.stbtt_fontinfo = undefined;
        if (c.stbtt_InitFont(&face, ttf_bytes.ptr, offset) != 1) {
            log.warn("fontCacheInit stbtt error when calling stbtt_InitFont font {s}\n", .{name});
            return FontError.fontError;
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

        return FontCacheEntry{
            .face = face,
            .name = name,
            .scaleFactor = SF,
            .height = @ceil(height),
            .ascent = @floor(ascent),
            .glyph_info = std.AutoHashMap(u32, GlyphInfo).init(currentWindow().gpa),
        };
    }
}

/// A texture held by the backend.  Can be drawn with `renderTexture`.
pub const Texture = struct {
    ptr: *anyopaque,
    width: u32,
    height: u32,

    pub const CacheKey = u64;

    /// Update a texture that was created with `textureCreate`. or fromImageSource
    ///
    /// The dimensions of the image must match the initial dimensions!
    /// Only valid to call while the underlying Texture is not destroyed!
    ///
    /// Only valid between `Window.begin` and `Window.end`.
    pub fn updateImageSource(self: *Texture, src: ImageSource) !void {
        switch (src) {
            .imageFile => |f| {
                const img = try Color.PMAImage.fromImageFile(f.name, currentWindow().arena(), f.bytes);
                defer currentWindow().arena().free(img.pma);
                try textureUpdate(self, img.pma, f.interpolation);
            },
            .pixels => |px| {
                const copy = try currentWindow().arena().dupe(u8, px.rgba);
                defer currentWindow().arena().free(copy);
                const pma = Color.PMA.sliceFromRGBA(copy);
                try textureUpdate(self, pma, px.interpolation);
            },
            .pixelsPMA => |px| {
                try textureUpdate(self, px.rgba, px.interpolation);
            },
            .texture => |_| @panic("this is not supported currently"),
        }
    }
    /// creates a new Texture from an ImageSource
    ///
    /// Only valid between `Window.begin` and `Window.end`.
    pub fn fromImageSource(source: ImageSource) !Texture {
        return switch (source) {
            .imageFile => |f| try Texture.fromImageFile(f.name, f.bytes, f.interpolation),
            .pixelsPMA => |px| try Texture.fromPixelsPMA(px.rgba, px.width, px.height, px.interpolation),
            .pixels => |px| blk: {
                // Using arena here instead of lifo as this buffer is likely to be large and we
                // prefer that lifo doesn't reallocate as often. Arena is intended for larger,
                // one of allocations and we can still free the buffer here
                const copy = try currentWindow().arena().dupe(u8, px.rgba);
                defer currentWindow().arena().free(copy);
                break :blk try Texture.fromPixelsPMA(Color.PMA.sliceFromRGBA(copy), px.width, px.height, px.interpolation);
            },
            .texture => |t| t,
        };
    }

    pub fn fromImageFile(name: []const u8, image_bytes: []const u8, interpolation: enums.TextureInterpolation) (Backend.TextureError || StbImageError)!Texture {
        const img = Color.PMAImage.fromImageFile(name, currentWindow().arena(), image_bytes) catch return StbImageError.stbImageError;
        defer currentWindow().arena().free(img.pma);
        return try textureCreate(img.pma, img.width, img.height, interpolation);
    }

    pub fn fromPixelsPMA(pma: []const dvui.Color.PMA, width: u32, height: u32, interpolation: enums.TextureInterpolation) Backend.TextureError!Texture {
        return try dvui.textureCreate(pma, width, height, interpolation);
    }

    /// Render `tvg_bytes` at `height` into a `Texture`.  Name is for debugging.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn fromTvgFile(name: []const u8, tvg_bytes: []const u8, height: u32, icon_opts: IconRenderOptions) (Backend.TextureError || TvgError)!Texture {
        const cw = currentWindow();
        const img = Color.PMAImage.fromTvgFile(name, cw.lifo(), cw.arena(), tvg_bytes, height, icon_opts) catch return TvgError.tvgError;
        defer cw.lifo().free(img.pma);
        return try textureCreate(img.pma, img.width, img.height, .linear);
    }
};

/// A texture held by the backend that can be drawn onto.  See `Picture`.
pub const TextureTarget = struct {
    ptr: *anyopaque,
    width: u32,
    height: u32,
};

/// Gets a texture from the internal texture cache. If a texture
/// isn't used for one frame it gets removed from the cache and
/// destroyed.
///
/// If you want to lazily create a texture, you could do:
/// ```zig
/// const texture = dvui.textureGetCached(key) orelse blk: {
///     const texture = ...; // Create your texture here
///     dvui.textureAddToCache(key, texture);
///     break :blk texture;
/// }
/// ```
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureGetCached(key: Texture.CacheKey) ?Texture {
    const cw = currentWindow();
    return cw.texture_cache.get(key);
}

/// Add a texture to the cache. This is useful if you want to load
/// and image from disk, create a texture from it and then unload
/// it from memory. The texture will remain in the cache as long
/// as it's key is accessed at least once per frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureAddToCache(key: Texture.CacheKey, texture: Texture) void {
    const cw = currentWindow();
    const prev = cw.texture_cache.fetchPut(cw.gpa, key, texture) catch |err| {
        logError(@src(), err, "Could not add texture with key {x} to cache", .{key});
        return;
    };
    if (prev) |kv| {
        dvui.textureDestroyLater(kv.value);
    }
}

/// Remove a key from the cache. This can force the re-creation
/// of a texture created by `ImageSource` for example.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureInvalidateCache(key: Texture.CacheKey) void {
    const cw = currentWindow();
    const prev = cw.texture_cache.fetchRemove(key);
    if (prev) |kv| {
        dvui.textureDestroyLater(kv.value);
    }
}

/// Takes in svg bytes and returns a tvg bytes that can be used
/// with `icon` or `iconTexture`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn svgToTvg(allocator: std.mem.Allocator, svg_bytes: []const u8) (std.mem.Allocator.Error || TvgError)![]const u8 {
    return tvg.tvg_from_svg(allocator, svg_bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => {
            log.debug("svgToTvg returned {!}", .{err});
            return TvgError.tvgError;
        },
    };
}

/// Get the width of an icon at a specified height.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn iconWidth(name: []const u8, tvg_bytes: []const u8, height: f32) TvgError!f32 {
    if (height == 0) return 0.0;
    var stream = std.io.fixedBufferStream(tvg_bytes);
    var parser = tvg.tvg.parse(currentWindow().arena(), stream.reader()) catch |err| {
        log.warn("iconWidth Tinyvg error {!} parsing icon {s}\n", .{ err, name });
        return TvgError.tvgError;
    };
    defer parser.deinit();

    return height * @as(f32, @floatFromInt(parser.header.width)) / @as(f32, @floatFromInt(parser.header.height));
}
pub const IconRenderOptions = struct {
    /// if null uses original fill colors, use .transparent to disable fill
    fill_color: ?Color = .white,
    /// if null uses original stroke width
    stroke_width: ?f32 = null,
    /// if null uses original stroke colors
    stroke_color: ?Color = .white,

    // note: IconWidget tests against default values
};

/// Represents a deferred call to one of the render functions.  This is how
/// dvui defers rendering of floating windows so they render on top of widgets
/// that run later in the frame.
pub const RenderCommand = struct {
    clip: Rect.Physical,
    alpha: f32,
    snap: bool,
    cmd: Command,

    pub const Command = union(enum) {
        text: renderTextOptions,
        texture: struct {
            tex: Texture,
            rs: RectScale,
            opts: RenderTextureOptions,
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

/// Id of the currently focused subwindow.  Used by `FloatingMenuWidget` to
/// detect when to stop showing.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusedSubwindowId() Id {
    const cw = currentWindow();
    const sw = cw.subwindowFocused();
    return sw.id;
}

/// Focus a subwindow.
///
/// If you are doing this in response to an `Event`, you can pass that `Event`'s
/// "num" to change the focus of any further `Event`s in the list.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusSubwindow(subwindow_id: ?Id, event_num: ?u16) void {
    currentWindow().focusSubwindowInternal(subwindow_id, event_num);
}

/// Raise a subwindow to the top of the stack.
///
/// Any subwindows directly above it with "stay_above_parent_window" set will also be moved to stay above it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn raiseSubwindow(subwindow_id: Id) void {
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
/// To focus a widget in a different subwindow (like from a menu), you must
/// have both the widget id and the subwindow id that widget is in.  See
/// `subwindowCurrentId()`.
///
/// If you are doing this in response to an `Event`, you can pass that `Event`'s
/// num to change the focus of any further `Event`s in the list.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusWidget(id: ?Id, subwindow_id: ?Id, event_num: ?u16) void {
    const cw = currentWindow();
    cw.scroll_to_focused = false;
    const swid = subwindow_id orelse subwindowCurrentId();
    for (cw.subwindows.items) |*sw| {
        if (swid == sw.id) {
            if (sw.focused_widgetId != id) {
                sw.focused_widgetId = id;
                if (event_num) |en| {
                    cw.focusEventsInternal(en, sw.id, sw.focused_widgetId);
                }
                refresh(null, @src(), null);

                if (id) |wid| {
                    cw.scroll_to_focused = true;

                    if (cw.last_registered_id_this_frame == wid) {
                        cw.last_focused_id_this_frame = wid;
                        cw.last_focused_id_in_subwindow = wid;
                    } else {
                        // walk parent chain
                        var wd = cw.data().parent.data();

                        while (true) : (wd = wd.parent.data()) {
                            if (wd.id == wid) {
                                cw.last_focused_id_this_frame = wid;
                                cw.last_focused_id_in_subwindow = wid;
                                break;
                            }

                            if (wd.id == cw.data().id) {
                                // got to base Window
                                break;
                            }
                        }
                    }
                }
            }
            break;
        }
    }
}

/// Id of the focused widget (if any) in the focused subwindow.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn focusedWidgetId() ?Id {
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
pub fn focusedWidgetIdInCurrentSubwindow() ?Id {
    const cw = currentWindow();
    const sw = cw.subwindowCurrent();
    return sw.focused_widgetId;
}

/// Last widget id we saw this frame that was the focused widget.
///
/// Pass result to `lastFocusedIdInFrameSince` to know if any widget was focused
/// between the two calls.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn lastFocusedIdInFrame() Id {
    return currentWindow().last_focused_id_this_frame;
}

/// Pass result from `lastFocusedIdInFrame`.  Returns the id of a widget that
/// was focused between the two calls, if any.
///
/// If so, this means one of:
/// * a widget had focus when it called `WidgetData.register`
/// * `focusWidget` with the id of the last widget to call `WidgetData.register`
/// * `focusWidget` with the id of a widget in the parent chain
///
/// If return is non null, can pass to `eventMatch` .focus_id to match key
/// events the focused widget got but didn't handle.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn lastFocusedIdInFrameSince(prev: Id) ?Id {
    const last_focused_id = lastFocusedIdInFrame();
    if (prev != last_focused_id) {
        return last_focused_id;
    } else {
        return null;
    }
}

/// Last widget id we saw in the current subwindow that was focused.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn lastFocusedIdInSubwindow() Id {
    return currentWindow().last_focused_id_in_subwindow;
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

/// Shows or hides the cursor, `true` meaning it's shown.
///
/// The previous value will be returned
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn cursorShow(value: ?bool) bool {
    return currentWindow().backend.cursorShow(value) catch |err| {
        logError(@src(), err, "Could not change cursor visibility", .{});
        return true;
    };
}

/// A collection of points that make up a shape that can later be rendered to the screen.
///
/// This is the basic tool to create rectangles and more complex polygons to later be
/// turned into `Triangles` and rendered to the screen.
pub const Path = struct {
    points: []const Point.Physical,

    /// A builder with an ArrayList to add points to.
    ///
    /// If a OutOfMemory error occurs, the builder with log it and ignore it,
    /// meaning that you would get an incomplete path in that case. For rendering,
    /// this will produce an incorrect output but will largely tend to work.
    ///
    /// `Builder.deinit` should always be called as `Builder.build` does not give ownership
    /// of the memory
    pub const Builder = struct {
        points: std.ArrayList(Point.Physical),
        oom_error_occurred: bool = false,

        pub fn init(allocator: std.mem.Allocator) Builder {
            return .{ .points = .init(allocator) };
        }

        pub fn deinit(path: *Builder) void {
            path.points.deinit();
        }

        /// Returns a non-owned `Path`. Calling `deinit` on the `Builder` is still required to free memory
        pub fn build(path: *Builder) Path {
            if (path.oom_error_occurred) {
                // This does not allow for error return traces, but
                // reduces spam caused by logs on every call to `addPoint`
                logError(@src(), std.mem.Allocator.Error.OutOfMemory, "Path encountered error and is likely incomplete", .{});
            }
            return .{ .points = path.points.items };
        }

        /// Add a point to the path
        pub fn addPoint(path: *Builder, p: Point.Physical) void {
            path.points.append(p) catch {
                path.oom_error_occurred = true;
            };
        }

        /// Add rounded rect to path.  Starts from top left, and ends at top right
        /// unclosed.  See `Rect.fill`.
        ///
        /// radius values:
        /// - x is top-left corner
        /// - y is top-right corner
        /// - w is bottom-right corner
        /// - h is bottom-left corner
        pub fn addRect(path: *Builder, r: Rect.Physical, radius: Rect.Physical) void {
            var rad = radius;
            const maxrad = @min(r.w, r.h) / 2;
            rad.x = @min(rad.x, maxrad);
            rad.y = @min(rad.y, maxrad);
            rad.w = @min(rad.w, maxrad);
            rad.h = @min(rad.h, maxrad);
            const tl = Point.Physical{ .x = r.x + rad.x, .y = r.y + rad.x };
            const bl = Point.Physical{ .x = r.x + rad.h, .y = r.y + r.h - rad.h };
            const br = Point.Physical{ .x = r.x + r.w - rad.w, .y = r.y + r.h - rad.w };
            const tr = Point.Physical{ .x = r.x + r.w - rad.y, .y = r.y + rad.y };
            path.addArc(tl, rad.x, math.pi * 1.5, math.pi, @abs(tl.y - bl.y) < 0.5);
            path.addArc(bl, rad.h, math.pi, math.pi * 0.5, @abs(bl.x - br.x) < 0.5);
            path.addArc(br, rad.w, math.pi * 0.5, 0, @abs(br.y - tr.y) < 0.5);
            path.addArc(tr, rad.y, math.pi * 2.0, math.pi * 1.5, @abs(tr.x - tl.x) < 0.5);
        }

        /// Add line segments creating an arc to path.
        ///
        /// `start` >= `end`, both are radians that go clockwise from the positive x axis.
        ///
        /// If `skip_end`, the final point will not be added.  Useful if the next
        /// addition to path would duplicate the end of the arc.
        pub fn addArc(path: *Builder, center: Point.Physical, radius: f32, start: f32, end: f32, skip_end: bool) void {
            if (radius == 0) {
                path.addPoint(center);
                return;
            }

            // how close our points will be to the perfect circle
            const err = 0.5;

            // angle that has err error between circle and segments
            const theta = math.acos(radius / (radius + err));

            var a: f32 = start;
            path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });

            while (a - end > theta) {
                // move to next fixed theta, this prevents shimmering on things like a spinner
                a = @floor((a - 0.001) / theta) * theta;
                path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
            }

            if (!skip_end) {
                a = end;
                path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
            }
        }
    };

    test Builder {
        var t = try dvui.testing.init(.{});
        defer t.deinit();

        var builder = Path.Builder.init(std.testing.allocator);
        // deinit should always be called on the builder
        defer builder.deinit();

        builder.addRect(.{ .x = 10, .y = 20, .w = 30, .h = 40 }, .all(0));
        const path = builder.build();
        // path does not have to be freed as the memory is still
        // owned by and will be freed by the Path.Builder
        try std.testing.expectEqual(4, path.points.len);

        var triangles = try path.fillConvexTriangles(std.testing.allocator, .{ .color = Color.white });
        defer triangles.deinit(std.testing.allocator);
        try std.testing.expectApproxEqRel(10, triangles.bounds.x, 0.05);
        try std.testing.expectApproxEqRel(20, triangles.bounds.y, 0.05);
        try std.testing.expectApproxEqRel(30, triangles.bounds.w, 0.05);
        try std.testing.expectApproxEqRel(40, triangles.bounds.h, 0.05);
    }

    pub fn dupe(path: Path, allocator: std.mem.Allocator) std.mem.Allocator.Error!Path {
        return .{ .points = try allocator.dupe(Point.Physical, path.points) };
    }

    pub const FillConvexOptions = struct {
        color: Color,

        /// Size (physical pixels) of fade to transparent centered on the edge.
        /// If >1, then starts a half-pixel inside and the rest outside.
        fade: f32 = 0.0,
        center: ?Point.Physical = null,
    };

    /// Fill path (must be convex) with `color` (or `Theme.color_fill`).  See `Rect.fill`.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn fillConvex(path: Path, opts: FillConvexOptions) void {
        if (path.points.len < 3) {
            return;
        }

        if (dvui.clipGet().empty()) {
            return;
        }

        const cw = currentWindow();

        if (!cw.render_target.rendering) {
            const new_path = path.dupe(cw.arena()) catch |err| {
                logError(@src(), err, "Could not reallocate path for render command", .{});
                return;
            };
            cw.addRenderCommand(.{ .pathFillConvex = .{ .path = new_path, .opts = opts } }, false);
            return;
        }

        var options = opts;
        options.color = options.color.opacity(cw.alpha);

        var triangles = path.fillConvexTriangles(cw.lifo(), options) catch |err| {
            logError(@src(), err, "Could not get triangles for path", .{});
            return;
        };
        defer triangles.deinit(cw.lifo());
        renderTriangles(triangles, null) catch |err| {
            logError(@src(), err, "Could not draw path, opts: {any}", .{options});
            return;
        };
    }

    /// Generates triangles to fill path (must be convex).
    ///
    /// Vertexes will have unset uv and color is alpha multiplied opts.color
    /// fading to transparent at the edge if fade is > 0.
    pub fn fillConvexTriangles(path: Path, allocator: std.mem.Allocator, opts: FillConvexOptions) std.mem.Allocator.Error!Triangles {
        if (path.points.len < 3) {
            return .empty;
        }

        var vtx_count = path.points.len;
        var idx_count = (path.points.len - 2) * 3;
        if (opts.fade > 0) {
            vtx_count *= 2;
            idx_count += path.points.len * 6;
        }
        if (opts.center) |_| {
            vtx_count += 1;
            idx_count += 6;
        }

        var builder = try Triangles.Builder.init(allocator, vtx_count, idx_count);
        errdefer comptime unreachable; // No errors from this point on

        const col: Color.PMA = .fromColor(opts.color);

        var i: usize = 0;
        while (i < path.points.len) : (i += 1) {
            const ai: u16 = @intCast((i + path.points.len - 1) % path.points.len);
            const bi: u16 = @intCast(i % path.points.len);
            const ci: u16 = @intCast((i + 1) % path.points.len);
            const aa = path.points[ai];
            const bb = path.points[bi];
            const cc = path.points[ci];

            const diffab = aa.diff(bb).normalize();
            const diffbc = bb.diff(cc).normalize();
            // average of normals on each side
            var norm: Point.Physical = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

            // inner vertex
            const inside_len = @min(0.5, opts.fade / 2);
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x - norm.x * inside_len,
                    .y = bb.y - norm.y * inside_len,
                },
                .col = col,
            });

            const idx_ai = if (opts.fade > 0) ai * 2 else ai;
            const idx_bi = if (opts.fade > 0) bi * 2 else bi;

            // indexes for fill
            // triangles must be counter-clockwise (y going down) to avoid backface culling
            if (opts.center) |_| {
                builder.appendTriangles(&.{ @intCast(vtx_count - 1), idx_ai, idx_bi });
            } else if (i > 1) {
                builder.appendTriangles(&.{ 0, idx_ai, idx_bi });
            }

            if (opts.fade > 0) {
                // scale averaged normal by angle between which happens to be the same as
                // dividing by the length^2
                const d2 = norm.x * norm.x + norm.y * norm.y;
                if (d2 > 0.000001) {
                    norm = norm.scale(1.0 / d2, Point.Physical);
                }

                // limit distance our vertexes can be from the point to 2 so
                // very small angles don't produce huge geometries
                const l = norm.length();
                if (l > 2.0) {
                    norm = norm.scale(2.0 / l, Point.Physical);
                }

                // outer vertex
                const outside_len = if (opts.fade <= 1) opts.fade / 2 else opts.fade - 0.5;
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + norm.x * outside_len,
                        .y = bb.y + norm.y * outside_len,
                    },
                    .col = .transparent,
                });

                // indexes for aa fade from inner to outer
                // triangles must be counter-clockwise (y going down) to avoid backface culling
                builder.appendTriangles(&.{
                    idx_ai,     idx_ai + 1, idx_bi,
                    idx_ai + 1, idx_bi + 1, idx_bi,
                });
            }
        }

        if (opts.center) |center| {
            builder.appendVertex(.{
                .pos = center,
                .col = col,
            });
        }

        return builder.build();
    }

    pub const StrokeOptions = struct {
        /// true => Render this after normal drawing on that subwindow.  Useful for
        /// debugging on cross-gui drawing.
        after: bool = false,

        thickness: f32,
        color: Color,

        /// true => Stroke includes from path end to path start.
        closed: bool = false,
        endcap_style: EndCapStyle = .none,

        pub const EndCapStyle = enum {
            none,
            square,
        };
    };

    /// Stroke path as a series of line segments.  See `Rect.stroke`.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn stroke(path: Path, opts: StrokeOptions) void {
        if (path.points.len == 0) {
            return;
        }

        const cw = currentWindow();

        if (opts.after or !cw.render_target.rendering) {
            const new_path = path.dupe(cw.arena()) catch |err| {
                logError(@src(), err, "Could not reallocate path for render command", .{});
                return;
            };
            cw.addRenderCommand(.{ .pathStroke = .{ .path = new_path, .opts = opts } }, opts.after);
            return;
        }

        var options = opts;
        options.color = options.color.opacity(cw.alpha);

        var triangles = path.strokeTriangles(cw.lifo(), options) catch |err| {
            logError(@src(), err, "Could not get triangles for path", .{});
            return;
        };
        defer triangles.deinit(cw.lifo());
        renderTriangles(triangles, null) catch |err| {
            logError(@src(), err, "Could not draw path, opts: {any}", .{opts});
            return;
        };
    }

    /// Generates triangles to stroke path.
    ///
    /// Vertexes will have unset uv and color is alpha multiplied opts.color
    /// fading to transparent at the edge.
    pub fn strokeTriangles(path: Path, allocator: std.mem.Allocator, opts: StrokeOptions) std.mem.Allocator.Error!Triangles {
        if (dvui.clipGet().empty()) {
            return .empty;
        }

        if (path.points.len == 1) {
            // draw a circle with radius thickness at that point
            const center = path.points[0];

            const other_allocator = if (current_window) |cw|
                if (cw.lifo().ptr != allocator.ptr) cw.lifo() else cw.arena()
            else
                // Using the same allocator will "leak" the tempPath on
                // arena allocators because it can only free the last allocation
                allocator;

            var tempPath: Path.Builder = .init(other_allocator);
            defer tempPath.deinit();

            tempPath.addArc(center, opts.thickness, math.pi * 2.0, 0, true);
            return tempPath.build().fillConvexTriangles(allocator, .{ .color = opts.color, .fade = 1.0 });
        }

        // a single segment can't be closed
        const closed: bool = if (path.points.len == 2) false else opts.closed;

        var vtx_count = path.points.len * 4;
        if (!closed) {
            vtx_count += 4;
        }
        var idx_count = (path.points.len - 1) * 18;
        if (closed) {
            idx_count += 18;
        } else {
            idx_count += 8 * 3;
        }

        var builder = try Triangles.Builder.init(allocator, vtx_count, idx_count);
        errdefer comptime unreachable; // No errors from this point on

        const col: Color.PMA = .fromColor(opts.color);

        const aa_size = 1.0;
        var vtx_start: u16 = 0;
        var i: usize = 0;
        while (i < path.points.len) : (i += 1) {
            const ai: u16 = @intCast((i + path.points.len - 1) % path.points.len);
            const bi: u16 = @intCast(i % path.points.len);
            const ci: u16 = @intCast((i + 1) % path.points.len);
            const aa = path.points[ai];
            var bb = path.points[bi];
            const cc = path.points[ci];

            // the amount to move from bb to the edge of the line
            var halfnorm: Point.Physical = undefined;
            var diffab: Point.Physical = undefined;

            if (!closed and ((i == 0) or ((i + 1) == path.points.len))) {
                if (i == 0) {
                    const diffbc = bb.diff(cc).normalize();
                    // rotate by 90 to get normal
                    halfnorm = .{ .x = diffbc.y / 2, .y = (-diffbc.x) / 2 };

                    if (opts.endcap_style == .square) {
                        // square endcaps move bb out by thickness
                        bb.x += diffbc.x * opts.thickness;
                        bb.y += diffbc.y * opts.thickness;
                    }

                    // add 2 extra vertexes for endcap fringe
                    vtx_start += 2;

                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - halfnorm.x * (opts.thickness + aa_size) + diffbc.x * aa_size,
                            .y = bb.y - halfnorm.y * (opts.thickness + aa_size) + diffbc.y * aa_size,
                        },
                        .col = .transparent,
                    });

                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + halfnorm.x * (opts.thickness + aa_size) + diffbc.x * aa_size,
                            .y = bb.y + halfnorm.y * (opts.thickness + aa_size) + diffbc.y * aa_size,
                        },
                        .col = .transparent,
                    });

                    // add indexes for endcap fringe
                    builder.appendTriangles(&.{
                        0, vtx_start,         vtx_start + 1,
                        0, 1,                 vtx_start,
                        1, vtx_start + 2,     vtx_start,
                        1, vtx_start + 2 + 1, vtx_start + 2,
                    });
                } else if ((i + 1) == path.points.len) {
                    diffab = aa.diff(bb).normalize();
                    // rotate by 90 to get normal
                    halfnorm = .{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                    if (opts.endcap_style == .square) {
                        // square endcaps move bb out by thickness
                        bb.x -= diffab.x * opts.thickness;
                        bb.y -= diffab.y * opts.thickness;
                    }
                }
            } else {
                diffab = aa.diff(bb).normalize();
                const diffbc = bb.diff(cc).normalize();
                // average of normals on each side
                halfnorm = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

                // scale averaged normal by angle between which happens to be the same as
                // dividing by the length^2
                const d2 = halfnorm.x * halfnorm.x + halfnorm.y * halfnorm.y;
                if (d2 > 0.000001) {
                    halfnorm = halfnorm.scale(0.5 / d2, Point.Physical);
                }

                // limit distance our vertexes can be from the point to 2 * thickness so
                // very small angles don't produce huge geometries
                const l = halfnorm.length();
                if (l > 2.0) {
                    halfnorm = halfnorm.scale(2.0 / l, Point.Physical);
                }
            }

            // side 1 inner vertex
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x - halfnorm.x * opts.thickness,
                    .y = bb.y - halfnorm.y * opts.thickness,
                },
                .col = col,
            });

            // side 1 AA vertex
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x - halfnorm.x * (opts.thickness + aa_size),
                    .y = bb.y - halfnorm.y * (opts.thickness + aa_size),
                },
                .col = .transparent,
            });

            // side 2 inner vertex
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x + halfnorm.x * opts.thickness,
                    .y = bb.y + halfnorm.y * opts.thickness,
                },
                .col = col,
            });

            // side 2 AA vertex
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x + halfnorm.x * (opts.thickness + aa_size),
                    .y = bb.y + halfnorm.y * (opts.thickness + aa_size),
                },
                .col = .transparent,
            });

            // triangles must be counter-clockwise (y going down) to avoid backface culling
            if (closed or ((i + 1) != path.points.len)) {
                builder.appendTriangles(&.{
                    // indexes for fill
                    vtx_start + bi * 4,     vtx_start + bi * 4 + 2, vtx_start + ci * 4,
                    vtx_start + bi * 4 + 2, vtx_start + ci * 4 + 2, vtx_start + ci * 4,

                    // indexes for aa fade from inner to outer side 1
                    vtx_start + bi * 4,     vtx_start + ci * 4 + 1, vtx_start + bi * 4 + 1,
                    vtx_start + bi * 4,     vtx_start + ci * 4,     vtx_start + ci * 4 + 1,

                    // indexes for aa fade from inner to outer side 2
                    vtx_start + bi * 4 + 2, vtx_start + bi * 4 + 3, vtx_start + ci * 4 + 3,
                    vtx_start + bi * 4 + 2, vtx_start + ci * 4 + 3, vtx_start + ci * 4 + 2,
                });
            } else if (!closed and (i + 1) == path.points.len) {
                // add 2 extra vertexes for endcap fringe
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x - halfnorm.x * (opts.thickness + aa_size) - diffab.x * aa_size,
                        .y = bb.y - halfnorm.y * (opts.thickness + aa_size) - diffab.y * aa_size,
                    },
                    .col = .transparent,
                });
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + halfnorm.x * (opts.thickness + aa_size) - diffab.x * aa_size,
                        .y = bb.y + halfnorm.y * (opts.thickness + aa_size) - diffab.y * aa_size,
                    },
                    .col = .transparent,
                });

                builder.appendTriangles(&.{
                    // add indexes for endcap fringe
                    vtx_start + bi * 4,     vtx_start + bi * 4 + 4, vtx_start + bi * 4 + 1,
                    vtx_start + bi * 4 + 4, vtx_start + bi * 4,     vtx_start + bi * 4 + 2,
                    vtx_start + bi * 4 + 4, vtx_start + bi * 4 + 2, vtx_start + bi * 4 + 5,
                    vtx_start + bi * 4 + 2, vtx_start + bi * 4 + 3, vtx_start + bi * 4 + 5,
                });
            }
        }

        return builder.build();
    }
};

pub const Triangles = struct {
    vertexes: []Vertex,
    indices: []u16,
    bounds: Rect.Physical,

    pub const empty = Triangles{
        .vertexes = &.{},
        .indices = &.{},
        .bounds = .{},
    };

    /// A builder for Triangles that assumes the exact number of
    /// vertexes and indices is known
    pub const Builder = struct {
        vertexes: std.ArrayListUnmanaged(Vertex),
        indices: std.ArrayListUnmanaged(u16),
        /// w and h is max_x and max_y
        bounds: Rect.Physical = .{
            .x = math.floatMax(f32),
            .y = math.floatMax(f32),
            .w = -math.floatMax(f32),
            .h = -math.floatMax(f32),
        },

        pub fn init(allocator: std.mem.Allocator, vtx_count: usize, idx_count: usize) std.mem.Allocator.Error!Builder {
            std.debug.assert(vtx_count >= 3);
            std.debug.assert(idx_count % 3 == 0);
            var vtx: @FieldType(Builder, "vertexes") = try .initCapacity(allocator, vtx_count);
            errdefer vtx.deinit(allocator);
            return .{
                .vertexes = vtx,
                .indices = try .initCapacity(allocator, idx_count),
            };
        }

        pub fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
            // NOTE: Should be in the opposite order to `init`
            self.indices.deinit(allocator);
            self.vertexes.deinit(allocator);
            self.* = undefined;
        }

        /// Appends a vertex and updates the bounds
        pub fn appendVertex(self: *Builder, v: Vertex) void {
            self.vertexes.appendAssumeCapacity(v);
            self.bounds.x = @min(self.bounds.x, v.pos.x);
            self.bounds.y = @min(self.bounds.y, v.pos.y);
            self.bounds.w = @max(self.bounds.w, v.pos.x);
            self.bounds.h = @max(self.bounds.h, v.pos.y);
        }

        /// Triangles must be counter-clockwise (y going down) to avoid backface culling
        ///
        /// Asserts that points is a multiple of 3
        pub fn appendTriangles(self: *Builder, points: []const u16) void {
            std.debug.assert(points.len % 3 == 0);
            self.indices.appendSliceAssumeCapacity(points);
        }

        /// Asserts that the entire array has been filled
        ///
        /// The memory ownership is transferred to `Triangles`.
        /// making `Builder.deinit` unnecessary, but safe, to call
        pub fn build(self: *Builder) Triangles {
            std.debug.assert(self.vertexes.items.len == self.vertexes.capacity);
            std.debug.assert(self.indices.items.len == self.indices.capacity);
            defer self.* = .{ .vertexes = .empty, .indices = .empty };
            // Ownership is transferred as the the full allocated slices are returned
            return self.build_unowned();
        }

        /// Creates `Triangles`, ignoring any extra capacity.
        ///
        /// Calling `Triangles.deinit` is invalid and `Builder.deinit`
        /// should always be called instead
        pub fn build_unowned(self: *Builder) Triangles {
            return .{
                .vertexes = self.vertexes.items,
                .indices = self.indices.items,
                // convert bounds w/h back to width/height
                .bounds = self.bounds.toPoint(.{
                    .x = self.bounds.w,
                    .y = self.bounds.h,
                }),
            };
        }
    };

    pub fn dupe(self: *const Triangles, allocator: std.mem.Allocator) std.mem.Allocator.Error!Triangles {
        const vtx = try allocator.dupe(Vertex, self.vertexes);
        errdefer allocator.free(vtx);
        return .{
            .vertexes = vtx,
            .indices = try allocator.dupe(u16, self.indices),
            .bounds = self.bounds,
        };
    }

    pub fn deinit(self: *Triangles, allocator: std.mem.Allocator) void {
        allocator.free(self.indices);
        allocator.free(self.vertexes);
        self.* = undefined;
    }

    /// Multiply `col` into vertex colors.
    pub fn color(self: *Triangles, col: Color) void {
        if (col.r == 0xff and col.g == 0xff and col.b == 0xff and col.a == 0xff)
            return;

        const pma_col: Color.PMA = .fromColor(col);
        for (self.vertexes) |*v| {
            v.col = v.col.multiply(pma_col);
        }
    }

    /// Set uv coords of vertexes according to position in r (with r_uv coords
    /// at corners), clamped to 0-1.
    pub fn uvFromRectuv(self: *Triangles, r: Rect.Physical, r_uv: Rect) void {
        for (self.vertexes) |*v| {
            const xfrac = (v.pos.x - r.x) / r.w;
            v.uv[0] = std.math.clamp(r_uv.x + xfrac * r_uv.w, 0, 1);

            const yfrac = (v.pos.y - r.y) / r.h;
            v.uv[1] = std.math.clamp(r_uv.y + yfrac * r_uv.h, 0, 1);
        }
    }

    /// Rotate vertexes around origin by radians (positive clockwise).
    pub fn rotate(self: *Triangles, origin: Point.Physical, radians: f32) void {
        if (radians == 0) return;

        const cos = @cos(radians);
        const sin = @sin(radians);

        for (self.vertexes) |*v| {
            // get vector from origin to point
            const d = v.pos.diff(origin);

            // rotate vector
            const rotated: Point.Physical = .{
                .x = d.x * cos - d.y * sin,
                .y = d.x * sin + d.y * cos,
            };

            v.pos = origin.plus(rotated);
        }

        // recalc bounds
        var points: [4]Point.Physical = .{
            self.bounds.topLeft(),
            self.bounds.topRight(),
            self.bounds.bottomRight(),
            self.bounds.bottomLeft(),
        };

        for (&points) |*p| {
            // get vector from origin to point
            const d = p.diff(origin);

            // rotate vector
            const rotated: Point.Physical = .{
                .x = d.x * cos - d.y * sin,
                .y = d.x * sin + d.y * cos,
            };

            p.* = origin.plus(rotated);
        }

        self.bounds.x = @min(points[0].x, points[1].x, points[2].x, points[3].x);
        self.bounds.y = @min(points[0].y, points[1].y, points[2].y, points[3].y);
        self.bounds.w = @max(points[0].x, points[1].x, points[2].x, points[3].x);
        self.bounds.w -= self.bounds.x;
        self.bounds.h = @max(points[0].y, points[1].y, points[2].y, points[3].y);
        self.bounds.h -= self.bounds.y;
    }
};

/// Rendered `Triangles` taking in to account the current clip rect
/// and deferred rendering through render targets.
///
/// Expect that `Window.alpha` has already been applied.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderTriangles(triangles: Triangles, tex: ?Texture) Backend.GenericError!void {
    if (triangles.vertexes.len == 0) {
        return;
    }

    if (dvui.clipGet().empty()) {
        return;
    }

    const cw = currentWindow();

    if (!cw.render_target.rendering) {
        const tri_copy = try triangles.dupe(cw.arena());
        cw.addRenderCommand(.{ .triangles = .{ .tri = tri_copy, .tex = tex } }, false);
        return;
    }

    // expand clipping to full pixels before testing
    var clipping = clipGet();
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

/// Called by floating widgets to participate in subwindow stacking - the order
/// in which multiple subwindows are drawn and which subwindow mouse events are
/// tagged with.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn subwindowAdd(id: Id, rect: Rect, rect_pixels: Rect.Physical, modal: bool, stay_above_parent_window: ?Id, mouse_events: bool) void {
    const cw = currentWindow();
    for (cw.subwindows.items) |*sw| {
        if (id == sw.id) {
            // this window was here previously, just update data, so it stays in the same place in the stack
            sw.used = true;
            sw.rect = rect;
            sw.rect_pixels = rect_pixels;
            sw.modal = modal;
            sw.stay_above_parent_window = stay_above_parent_window;
            sw.mouse_events = mouse_events;

            if (sw.render_cmds.items.len > 0 or sw.render_cmds_after.items.len > 0) {
                log.warn("subwindowAdd {x} is clearing some drawing commands (did you try to draw between subwindowCurrentSet and subwindowAdd?)\n", .{id});
            }

            sw.render_cmds = .empty;
            sw.render_cmds_after = .empty;
            return;
        }
    }

    // haven't seen this window before
    const sw = Window.Subwindow{
        .id = id,
        .rect = rect,
        .rect_pixels = rect_pixels,
        .modal = modal,
        .stay_above_parent_window = stay_above_parent_window,
        .mouse_events = mouse_events,
    };
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
        cw.subwindows.insert(cw.gpa, i, sw) catch |err| {
            logError(@src(), err, "Could not insert {x} {} into subwindow list, events in this other other subwindwos might not work properly", .{ id, rect_pixels });
        };
    } else {
        // just put it on the top
        cw.subwindows.append(cw.gpa, sw) catch |err| {
            logError(@src(), err, "Could not insert {x} {} into subwindow list, events in this other other subwindwos might not work properly", .{ id, rect_pixels });
        };
    }
}

pub const subwindowCurrentSetReturn = struct {
    id: Id,
    rect: Rect.Natural,
};

/// Used by floating windows (subwindows) to install themselves as the current
/// subwindow (the subwindow that widgets run now will be in).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn subwindowCurrentSet(id: Id, rect: ?Rect.Natural) subwindowCurrentSetReturn {
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
pub fn subwindowCurrentId() Id {
    const cw = currentWindow();
    return cw.subwindow_currentId;
}

/// Optional features you might want when doing a mouse/touch drag.
pub const DragStartOptions = struct {
    /// Use this cursor from when a drag starts to when it ends.
    cursor: ?enums.Cursor = null,

    /// Offset of point of interest from the mouse.  Useful during a drag to
    /// locate where to move the point of interest.
    offset: Point.Physical = .{},

    /// Used for cross-widget dragging.  See `draggingName`.
    name: ?[]const u8 = null,
};

/// Prepare for a possible mouse drag.  This will detect a drag, and also a
/// normal click (mouse down and up without a drag).
///
/// * `dragging` will return a Point once mouse motion has moved at least 3
/// natural pixels away from p.
///
/// * if cursor is non-null and a drag starts, use that cursor while dragging
///
/// * offset given here can be retrieved later with `dragOffset` - example is
/// dragging bottom right corner of floating window.  The drag can start
/// anywhere in the hit area (passing the offset to the true corner), then
/// during the drag, the `dragOffset` is added to the current mouse location to
/// recover where to move the true corner.
///
/// See `dragStart` to immediately start a drag.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragPreStart(p: Point.Physical, options: DragStartOptions) void {
    const cw = currentWindow();
    cw.drag_state = .prestart;
    cw.drag_pt = p;
    cw.drag_offset = options.offset;
    cw.cursor_dragging = options.cursor;
    cw.drag_name = options.name;
}

/// Start a mouse drag from p.  Use when only dragging is possible (normal
/// click would do nothing), otherwise use `dragPreStart`.
///
/// * if cursor is non-null, use that cursor while dragging
///
/// * offset given here can be retrieved later with `dragOffset` - example is
/// dragging bottom right corner of floating window.  The drag can start
/// anywhere in the hit area (passing the offset to the true corner), then
/// during the drag, the `dragOffset` is added to the current mouse location to
/// recover where to move the true corner.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragStart(p: Point.Physical, options: DragStartOptions) void {
    const cw = currentWindow();
    cw.drag_state = .dragging;
    cw.drag_pt = p;
    cw.drag_offset = options.offset;
    cw.cursor_dragging = options.cursor;
    cw.drag_name = options.name;
}

/// Get offset previously given to `dragPreStart` or `dragStart`.  See those.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragOffset() Point.Physical {
    const cw = currentWindow();
    return cw.drag_offset;
}

/// If a mouse drag is happening, return the pixel difference to p from the
/// previous dragging call or the drag starting location (from `dragPreStart`
/// or `dragStart`).  Otherwise return null, meaning a drag hasn't started yet.
///
/// If name is given, returns null immediately if it doesn't match the name /
/// given to `dragPreStart` or `dragStart`.  This is useful for widgets that need
/// multiple different kinds of drags.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragging(p: Point.Physical, name: ?[]const u8) ?Point.Physical {
    const cw = currentWindow();

    if (name) |n| {
        if (!std.mem.eql(u8, n, cw.drag_name orelse "")) return null;
    }

    switch (cw.drag_state) {
        .none => return null,
        .dragging => {
            const dp = p.diff(cw.drag_pt);
            cw.drag_pt = p;
            return dp;
        },
        .prestart => {
            const dp = p.diff(cw.drag_pt);
            const dps = dp.scale(1 / windowNaturalScale(), Point.Natural);
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

/// True if `dragging` and `dragStart` (or `dragPreStart`) was given name.
///
/// Use to know when a cross-widget drag is in progress.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn draggingName(name: []const u8) bool {
    const cw = currentWindow();
    return cw.drag_state == .dragging and cw.drag_name != null and std.mem.eql(u8, name, cw.drag_name.?);
}

/// Stop any mouse drag.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dragEnd() void {
    const cw = currentWindow();
    cw.drag_state = .none;
    cw.drag_name = null;
}

/// The difference between the final mouse position this frame and last frame.
/// Use `mouseTotalMotion().nonZero()` to detect if any mouse motion has occurred.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn mouseTotalMotion() Point.Physical {
    const cw = currentWindow();
    return .diff(cw.mouse_pt, cw.mouse_pt_prev);
}

/// Used to track which widget holds mouse capture.
pub const CaptureMouse = struct {
    /// widget ID
    id: Id,
    /// physical pixels (aka capture zone)
    rect: Rect.Physical,
    /// subwindow id the widget with capture is in
    subwindow_id: Id,
};

/// Capture the mouse for this widget's data.
/// (i.e. `eventMatch` return true for this widget and false for all others)
/// and capture is explicitly released when passing `null`.
///
/// Tracks the widget's id / subwindow / rect, so that `.position` mouse events can still
/// be presented to widgets who's rect overlap with the widget holding the capture.
/// (which is what you would expect for e.g. background highlight)
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouse(wd: ?*const WidgetData, event_num: u16) void {
    const cm = if (wd) |data| CaptureMouse{
        .id = data.id,
        .rect = data.borderRectScale().r,
        .subwindow_id = subwindowCurrentId(),
    } else null;
    captureMouseCustom(cm, event_num);
}
/// In most cases, use `captureMouse` but if you want to customize the
/// "capture zone" you can use this function instead.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captureMouseCustom(cm: ?CaptureMouse, event_num: u16) void {
    const cw = currentWindow();
    defer cw.capture = cm;
    if (cm) |capture| {
        // log.debug("Mouse capture (event {d}): {any}", .{ event_num, cm });
        cw.captured_last_frame = true;
        cw.captureEventsInternal(event_num, capture.id);
    } else {
        // Unmark all following mouse events
        cw.captureEventsInternal(event_num, null);
        // log.debug("Mouse uncapture (event {d}): {?any}", .{ event_num, cw.capture });
        // for (dvui.events()) |*e| {
        //     if (e.evt == .mouse) {
        //         log.debug("{s}: win {?x}, widget {?x}", .{ @tagName(e.evt.mouse.action), e.target_windowId, e.target_widgetId });
        //     }
        // }
    }
}
/// If the widget ID passed has mouse capture, this maintains that capture for
/// the next frame.  This is usually called for you in `WidgetData.init`.
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
                //
                // mark all events as not captured, we are being interrupted by
                // a modal dialog anyway
                captureMouse(null, 0);
                dragEnd();
                return;
            }
        }
    }
}

/// Test if the passed widget ID currently has mouse capture.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn captured(id: Id) bool {
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
pub fn clipGet() Rect.Physical {
    return currentWindow().clipRect;
}

/// Intersect the given physical rect with the current clipping rect and set
/// as the new clipping rect.
///
/// Returns the previous clipping rect, use `clipSet` to restore it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clip(new: Rect.Physical) Rect.Physical {
    const cw = currentWindow();
    const ret = cw.clipRect;
    clipSet(cw.clipRect.intersect(new));
    return ret;
}

/// Set the current clipping rect to the given physical rect.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipSet(r: Rect.Physical) void {
    currentWindow().clipRect = r;
}

/// Multiplies the current alpha value with the passed in multiplier.
/// If `mult` is 0 then it will be completely transparent, 0.5 would be
/// half of the current alpha and so on.
///
/// Returns the previous alpha value, use `alphaSet` to restore it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn alpha(mult: f32) f32 {
    const cw = currentWindow();
    const ret = cw.alpha;
    alphaSet(cw.alpha * mult);
    return ret;
}

/// Set the current alpha value [0-1] where 1 is fully opaque.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn alphaSet(a: f32) void {
    const cw = currentWindow();
    cw.alpha = std.math.clamp(a, 0, 1);
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

/// Get current snap_to_pixels setting.  See `snapToPixelsSet`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn snapToPixels() bool {
    const cw = currentWindow();
    return cw.snap_to_pixels;
}

/// Requests another frame to be shown.
///
/// This only matters if you are using dvui to manage the framerate (by calling
/// `Window.waitTime` and using the return value to wait with event
/// interruption - for example `sdl_backend.waitEventTimeout` at the end of each
/// frame).
///
/// src and id are for debugging, which is enabled by calling
/// `Window.debugRefresh(true)`.  The debug window has a toggle button for this.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the Window you want to refresh.  In that case dvui will
/// go through the backend because the gui thread might be waiting.
pub fn refresh(win: ?*Window, src: std.builtin.SourceLocation, id: ?Id) void {
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
pub fn clipboardText() []const u8 {
    const cw = currentWindow();
    return cw.backend.clipboardText() catch |err| blk: {
        logError(@src(), err, "Could not get clipboard text", .{});
        break :blk "";
    };
}

/// Set the textual content of the system clipboard.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn clipboardTextSet(text: []const u8) void {
    const cw = currentWindow();
    cw.backend.clipboardTextSet(text) catch |err| {
        logError(@src(), err, "Could not set clipboard text '{s}'", .{text});
    };
}

/// Ask the system to open the given url.
/// http:// and https:// urls can be opened.
/// returns true if the backend reports the URL was opened.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn openURL(url: []const u8) bool {
    const parsed = std.Uri.parse(url) catch return false;
    if (!std.ascii.eqlIgnoreCase(parsed.scheme, "http") and
        !std.ascii.eqlIgnoreCase(parsed.scheme, "https"))
    {
        return false;
    }
    if (parsed.host != null and parsed.host.?.isEmpty()) {
        return false;
    }

    const cw = currentWindow();
    cw.backend.openURL(url) catch |err| {
        logError(@src(), err, "Could not open url '{s}'", .{url});
        return false;
    };
    return true;
}

test openURL {
    try std.testing.expect(openURL("notepad.exe") == false);
    try std.testing.expect(openURL("https://") == false);
    try std.testing.expect(openURL("file:///") == false);
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
/// ```zig
/// dvui.parentGet().extendId(@src(), id_extra)
/// ```
/// is how new widgets get their id, and can be used to make a unique id without
/// making a widget.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentGet() Widget {
    return currentWindow().data().parent;
}

/// Make w the new parent widget.  See `parentGet`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentSet(w: Widget) void {
    const cw = currentWindow();
    cw.data().parent = w;
}

/// Make a previous parent widget the current parent.
///
/// Pass the current parent's id.  This is used to detect a coding error where
/// a widget's `.deinit()` was accidentally not called.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn parentReset(id: Id, w: Widget) void {
    const cw = currentWindow();
    const actual_current = cw.data().parent.data().id;
    if (id != actual_current) {
        cw.debug.widget_id = actual_current;

        var wd = cw.data().parent.data();

        log.err("widget is not closed within its parent. did you forget to call `.deinit()`?", .{});

        while (true) : (wd = wd.parent.data()) {
            log.err("  {s}:{d} {s} {x}{s}", .{
                wd.src.file,
                wd.src.line,
                wd.options.name orelse "???",
                wd.id,
                if (wd.id == cw.data().id) "\n" else "",
            });

            if (wd.id == cw.data().id) {
                // got to base Window
                break;
            }
        }
    }
    cw.data().parent = w;
}

/// Set if dvui should immediately render, and return the previous setting.
///
/// If false, the render functions defer until `Window.end`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderingSet(r: bool) bool {
    const cw = currentWindow();
    const ret = cw.render_target.rendering;
    cw.render_target.rendering = r;
    return ret;
}

/// Get the OS window size in natural pixels.  Physical pixels might be more on
/// a hidpi screen or if the user has content scaling.  See `windowRectPixels`.
///
/// Natural pixels is the unit for subwindow sizing and placement.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRect() Rect.Natural {
    // Window.data().rect is the definition of natural
    return .cast(currentWindow().data().rect);
}

/// Get the OS window size in pixels.  See `windowRect`.
///
/// Pixels is the unit for rendering and user input.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRectPixels() Rect.Physical {
    return currentWindow().rect_pixels;
}

/// Get the Rect and scale factor for the OS window.  The Rect is in pixels,
/// and the scale factor is how many pixels per natural pixel.  See
/// `windowRect`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowRectScale() RectScale {
    return currentWindow().rectScale();
}

/// The natural scale is how many pixels per natural pixel.  Useful for
/// converting between user input and subwindow size/position.  See
/// `windowRect`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowNaturalScale() f32 {
    return currentWindow().natural_scale;
}

/// True if this is the first frame we've seen this widget id, meaning we don't
/// know its min size yet.  The widget will record its min size in `.deinit()`.
///
/// If a widget is not seen for a frame, its min size will be forgotten and
/// firstFrame will return true the next frame we see it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn firstFrame(id: Id) bool {
    return minSizeGet(id) == null;
}

/// Get the min size recorded for id from last frame or null if id was not seen
/// last frame.
///
/// Usually you want `minSize` to combine min size from last frame with a min
/// size provided by the user code.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn minSizeGet(id: Id) ?Size {
    return currentWindow().min_sizes.get(id);
}

/// Return the maximum of min_size and the min size for id from last frame.
///
/// See `minSizeGet` to get only the min size from last frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn minSize(id: Id, min_size: Size) Size {
    var size = min_size;

    // Need to take the max of both given and previous.  ScrollArea could be
    // passed a min size Size{.w = 0, .h = 200} meaning to get the width from the
    // previous min size.
    if (minSizeGet(id)) |ms| {
        size = Size.max(size, ms);
    }

    return size;
}

/// DEPRECATED: See `dvui.Id.extendId`
pub const hashSrc = void;
/// DEPRECATED: See `dvui.Id.update`
pub const hashIdKey = void;

/// Set key/value pair for given id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Stored data with the same id/key will be overwritten if it has the same size,
/// otherwise the data will be freed at the next call to `Window.end`. This means
/// that if a pointer to the same id/key was retrieved earlier, the value behind
/// that pointer would be modified.
///
/// If you want to store the contents of a slice, use `dataSetSlice`.
pub fn dataSet(win: ?*Window, id: Id, key: []const u8, data: anytype) void {
    dataSetAdvanced(win, id, key, data, false, 1);
}

/// Set key/value pair for given id, copying the slice contents. Can be passed
/// a slice or pointer to an array.
///
/// Can be called from any thread.
///
/// Stored data with the same id/key will be overwritten if it has the same size,
/// otherwise the data will be freed at the next call to `Window.end`. This means
/// that if the slice with the same id/key was retrieved earlier, the value behind
/// that slice would be modified.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
pub fn dataSetSlice(win: ?*Window, id: Id, key: []const u8, data: anytype) void {
    dataSetSliceCopies(win, id, key, data, 1);
}

/// Same as `dataSetSlice`, but will copy data `num_copies` times all concatenated
/// into a single slice.  Useful to get dvui to allocate a specific number of
/// entries that you want to fill in after.
pub fn dataSetSliceCopies(win: ?*Window, id: Id, key: []const u8, data: anytype, num_copies: usize) void {
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
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Stored data with the same id/key will be freed at next `win.end()`.
///
/// If `copy_slice` is true, data must be a slice or pointer to array, and the
/// contents are copied into internal storage. If false, only the slice itself
/// (ptr and len) and stored.
pub fn dataSetAdvanced(win: ?*Window, id: Id, key: []const u8, data: anytype, comptime copy_slice: bool, num_copies: usize) void {
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
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// If you want a pointer to the stored data, use `dataGetPtr`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGet(win: ?*Window, id: Id, key: []const u8, comptime T: type) ?T {
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
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// If you want a pointer to the stored data, use `dataGetPtrDefault`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGetDefault(win: ?*Window, id: Id, key: []const u8, comptime T: type, default: T) T {
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
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Returns a pointer to internal storage, which will be freed after a frame
/// where there is no call to any `dataGet`/`dataSet` functions for that id/key
/// combination.
///
/// The pointer will always be valid until the next call to `Window.end`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGetPtrDefault(win: ?*Window, id: Id, key: []const u8, comptime T: type, default: T) *T {
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
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// Returns a pointer to internal storage, which will be freed after a frame
/// where there is no call to any `dataGet`/`dataSet` functions for that id/key
/// combination.
///
/// The pointer will always be valid until the next call to `Window.end`.
///
/// If you want to get the contents of a stored slice, use `dataGetSlice`.
pub fn dataGetPtr(win: ?*Window, id: Id, key: []const u8, comptime T: type) ?*T {
    if (dataGetInternal(win, id, key, T, false)) |bytes| {
        return @as(*T, @alignCast(@ptrCast(bytes.ptr)));
    } else {
        return null;
    }
}

/// Retrieve slice contents for given key associated with id.
///
/// `dataSetSlice` strips const from the slice type, so always call
/// `dataGetSlice` with a mutable slice type ([]u8, not []const u8).
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// The returned slice points to internal storage, which will be freed after
/// a frame where there is no call to any `dataGet`/`dataSet` functions for that
/// id/key combination.
///
/// The slice will always be valid until the next call to `Window.end`.
pub fn dataGetSlice(win: ?*Window, id: Id, key: []const u8, comptime T: type) ?T {
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
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the data to.
///
/// The returned slice points to internal storage, which will be freed after
/// a frame where there is no call to any `dataGet`/`dataSet` functions for that
/// id/key combination.
///
/// The slice will always be valid until the next call to `Window.end`.
pub fn dataGetSliceDefault(win: ?*Window, id: Id, key: []const u8, comptime T: type, default: []const @typeInfo(T).pointer.child) T {
    return dataGetSlice(win, id, key, T) orelse blk: {
        dataSetSlice(win, id, key, default);
        break :blk dataGetSlice(win, id, key, T).?;
    };
}

// returns the backing slice of bytes if we have it
pub fn dataGetInternal(win: ?*Window, id: Id, key: []const u8, comptime T: type, slice: bool) ?[]u8 {
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
/// `Window.end`.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the `Window` you want to add the dialog to.
pub fn dataRemove(win: ?*Window, id: Id, key: []const u8) void {
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
/// `min_size`.
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

/// Get the slice of `Event`s for this frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn events() []Event {
    return currentWindow().events.items;
}

/// Wrapper around `eventMatch` for normal usage.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn eventMatchSimple(e: *Event, wd: *WidgetData) bool {
    return eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r });
}

/// Data for matching events to widgets.  See `eventMatch`.
pub const EventMatchOptions = struct {
    /// Id of widget, used for keyboard focus and mouse capture.
    id: Id,

    /// Additional Id for keyboard focus, use to match children with
    /// `lastFocusedIdInFrame()`.
    focus_id: ?Id = null,

    /// Physical pixel rect used to match pointer events.
    r: Rect.Physical,

    /// During a drag, only match pointer events if this is the draggingName.
    dragging_name: ?[]const u8 = null,

    /// true means match all focus-based events routed to the subwindow with
    /// id.  This is how subwindows catch things like tab if no widget in that
    /// subwindow has focus.
    cleanup: bool = false,

    /// (Only in Debug) If true, `eventMatch` will log a reason when returning
    /// false.  Useful to understand why you aren't matching some event.
    debug: if (builtin.mode == .Debug) bool else void = if (builtin.mode == .Debug) false else undefined,
};

/// Should e be processed by a widget with the given id and screen rect?
///
/// This is the core event matching logic and includes keyboard focus and mouse
/// capture.  Call this on each event in `events` to know whether to process.
///
/// If asking whether an existing widget would process an event (if you are
/// wrapping a widget), that widget should have a `matchEvent` which calls this
/// internally but might extend the logic, or use that function to track state
/// (like whether a modifier key is being pressed).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn eventMatch(e: *Event, opts: EventMatchOptions) bool {
    if (e.handled) {
        if (builtin.mode == .Debug and opts.debug) {
            log.debug("eventMatch {} already handled", .{e});
        }
        return false;
    }

    switch (e.evt) {
        .key, .text => {
            if (e.target_windowId) |wid| {
                // focusable event
                if (opts.cleanup) {
                    // window is catching all focus-routed events that didn't get
                    // processed (maybe the focus widget never showed up)
                    if (wid != opts.id) {
                        // not the focused window
                        if (builtin.mode == .Debug and opts.debug) {
                            log.debug("eventMatch {} (cleanup) focus not to this window", .{e});
                        }
                        return false;
                    }
                } else {
                    if (e.target_widgetId != opts.id and (opts.focus_id == null or opts.focus_id.? != e.target_widgetId)) {
                        // not the focused widget
                        if (builtin.mode == .Debug and opts.debug) {
                            log.debug("eventMatch {} focus not to this widget", .{e});
                        }
                        return false;
                    }
                }
            }
        },
        .mouse => |me| {
            var other_capture = false;
            if (e.target_widgetId) |fwid| {
                // this event is during a mouse capture
                if (fwid == opts.id) {
                    // we have capture, we get all capturable mouse events (excludes wheel)
                    return true;
                } else {
                    // someone else has capture
                    other_capture = true;
                }
            }

            const cw = currentWindow();
            if (cw.drag_state == .dragging and cw.drag_name != null and (opts.dragging_name == null or !std.mem.eql(u8, cw.drag_name.?, opts.dragging_name.?))) {
                // a cross-widget drag is happening that we don't know about
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {} dragging name ({?s}) didn't match given ({?s})", .{ e, cw.drag_name, opts.dragging_name });
                }
                return false;
            }

            if (me.floating_win != subwindowCurrentId()) {
                // floating window is above us
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {} floating window above", .{e});
                }
                return false;
            }

            if (!opts.r.contains(me.p)) {
                // mouse not in our rect
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {} not in rect", .{e});
                }
                return false;
            }

            if (!clipGet().contains(me.p)) {
                // mouse not in clip region

                // prevents widgets that are scrolled off a
                // scroll area from processing events
                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {} not in clip", .{e});
                }
                return false;
            }

            if (other_capture) {
                if (captureMouseGet()) |capture| {
                    // someone else has capture, but otherwise we would have gotten
                    // this mouse event
                    if (me.action == .position and capture.subwindow_id == subwindowCurrentId() and !capture.rect.intersect(opts.r).empty()) {
                        // we might be trying to highlight a background around the widget with capture:
                        // * we are in the same subwindow
                        // * our rect overlaps with the capture rect
                        return true;
                    }
                }

                if (builtin.mode == .Debug and opts.debug) {
                    log.debug("eventMatch {} captured by other widget", .{e});
                }
                return false;
            }
        },
    }

    return true;
}

pub const ClickOptions = struct {
    /// Is set to true if the cursor is hovering the click rect
    hovered: ?*bool = null,
    /// If not null, this will be set when the cursor is within the click rect
    hover_cursor: ?enums.Cursor = .hand,
    /// The rect in which clicks are checked
    ///
    /// Defaults to the border rect of the `WidgetData`
    rect: ?Rect.Physical = null,
};

/// Handles all events needed for clicking behaviour, used by `ButtonWidget`.
pub fn clicked(wd: *const WidgetData, opts: ClickOptions) bool {
    var is_clicked = false;
    const click_rect = opts.rect orelse wd.borderRectScale().r;
    for (dvui.events()) |*e| {
        if (!dvui.eventMatch(e, .{ .id = wd.id, .r = click_rect }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .focus) {
                    e.handle(@src(), wd);

                    // focus this widget for events after this one (starting with e.num)
                    dvui.focusWidget(wd.id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    e.handle(@src(), wd);
                    dvui.captureMouse(wd, e.num);

                    // for touch events, we want to cancel our click if a drag is started
                    dvui.dragPreStart(me.p, .{});
                } else if (me.action == .release and me.button.pointer()) {
                    // mouse button was released, do we still have mouse capture?
                    if (dvui.captured(wd.id)) {
                        e.handle(@src(), wd);

                        // cancel our capture
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();

                        // if the release was within our border, the click is successful
                        if (click_rect.contains(me.p)) {
                            is_clicked = true;

                            // if the user interacts successfully with a
                            // widget, it usually means part of the GUI is
                            // changing, so the convention is to call refresh
                            // so the user doesn't have to remember
                            dvui.refresh(null, @src(), wd.id);
                        }
                    }
                } else if (me.action == .motion and me.button.touch()) {
                    if (dvui.captured(wd.id)) {
                        if (dvui.dragging(me.p, null)) |_| {
                            // touch: if we overcame the drag threshold, then
                            // that means the person probably didn't want to
                            // touch this button, they were trying to scroll
                            dvui.captureMouse(null, e.num);
                            dvui.dragEnd();
                        }
                    }
                } else if (me.action == .position) {
                    // TODO: Should this mark this event as handled? If the click_rect
                    //       is above another widget with hover effects or click behaviour,
                    //       we don't want that widget to highlight as if the next click
                    //       would apply to it.

                    // a single .position mouse event is at the end of each
                    // frame, so this means the mouse ended above us
                    if (opts.hover_cursor) |cursor| {
                        dvui.cursorSet(cursor);
                    }
                    if (opts.hovered) |hovered| {
                        hovered.* = true;
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down and ke.matchBind("activate")) {
                    e.handle(@src(), wd);
                    is_clicked = true;
                    dvui.refresh(null, @src(), wd.id);
                }
            },
            else => {},
        }
    }
    return is_clicked;
}

/// Animation state - see `animation` and `animationGet`.
///
/// start_time and `end_time` are relative to the current frame time.  At the
/// start of each frame both are reduced by the micros since the last frame.
///
/// An animation will be active thru a frame where its `end_time` is <= 0, and be
/// deleted at the beginning of the next frame.  See `spinner` for an example of
/// how to have a seamless continuous animation.
pub const Animation = struct {
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

/// Add animation a to key associated with id.  See `Animation`.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn animation(id: Id, key: []const u8, a: Animation) void {
    var cw = currentWindow();
    const h = id.update(key);
    cw.animations.put(cw.gpa, h, a) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("animation got {!} for id {x} key {s}\n", .{ err, id, key });
        },
    };
}

/// Retrieve an animation previously added with `animation`.  See `Animation`.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn animationGet(id: Id, key: []const u8) ?Animation {
    const h = id.update(key);
    return currentWindow().animations.get(h);
}

/// Add a timer for id that will be `timerDone` on the first frame after micros
/// has passed.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timer(id: Id, micros: i32) void {
    currentWindow().timer(id, micros);
}

/// Return the number of micros left on the timer for id if there is one.  If
/// `timerDone`, this value will be <= 0 and represents how many micros this
/// frame is past the timer expiration.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerGet(id: Id) ?i32 {
    if (animationGet(id, "_timer")) |a| {
        return a.end_time;
    } else {
        return null;
    }
}

/// Return true on the first frame after a timer has expired.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerDone(id: Id) bool {
    if (timerGet(id)) |end_time| {
        if (end_time <= 0) {
            return true;
        }
    }

    return false;
}

/// Return true if `timerDone` or if there is no timer.  Useful for periodic
/// events (see Clock example in `Examples.animations`).
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn timerDoneOrNone(id: Id) bool {
    return timerDone(id) or (timerGet(id) == null);
}

pub const ScrollToOptions = struct {
    // rect in screen coords we want to be visible (might be outside
    // scrollarea's clipping region - we want to scroll to bring it inside)
    screen_rect: dvui.Rect.Physical,

    // whether to scroll outside the current scroll bounds (useful if the
    // current action might be expanding the scroll area)
    over_scroll: bool = false,
};

/// Scroll the current containing scroll area to show the passed in screen rect
pub fn scrollTo(scroll_to: ScrollToOptions) void {
    if (ScrollContainerWidget.current()) |scroll| {
        scroll.processScrollTo(scroll_to);
    }
}

pub const ScrollDragOptions = struct {
    // mouse point from motion event
    mouse_pt: dvui.Point.Physical,

    // rect in screen coords of the widget doing the drag (scrolling will stop
    // if it wouldn't show more of this rect)
    screen_rect: dvui.Rect.Physical,

    // id of the widget that has mouse capture during the drag (needed to
    // inject synthetic motion events into the next frame to keep scrolling)
    capture_id: dvui.Id,
};

/// Bubbled from inside a scrollarea to ensure scrolling while dragging
/// if the mouse moves to the edge or outside the scrollarea.
///
/// During dragging, a widget should call this on each pointer motion event.
pub fn scrollDrag(scroll_drag: ScrollDragOptions) void {
    if (ScrollContainerWidget.current()) |scroll| {
        scroll.processScrollDrag(scroll_drag);
    }
}

pub const TabIndex = struct {
    windowId: Id,
    widgetId: Id,
    tabIndex: u16,
};

/// Set the tab order for this widget.  `tab_index` values are visited starting
/// with 1 and going up.
///
/// A zero `tab_index` means this function does nothing and the widget is not
/// added to the tab order.
///
/// A null `tab_index` means it will be visited after all normal values.  All
/// null widgets are visited in order of calling `tabIndexSet`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn tabIndexSet(widget_id: Id, tab_index: ?u16) void {
    if (tab_index != null and tab_index.? == 0)
        return;

    var cw = currentWindow();
    const ti = TabIndex{ .windowId = cw.subwindow_currentId, .widgetId = widget_id, .tabIndex = (tab_index orelse math.maxInt(u16)) };
    cw.tab_index.append(cw.gpa, ti) catch |err| {
        logError(@src(), err, "Could not set tab index. This might break keyboard navigation as the widget may become unreachable via tab", .{});
    };
}

/// Move focus to the next widget in tab index order.  Uses the tab index values from last frame.
///
/// If you are calling this due to processing an event, you can pass `Event`'s num
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
    var newId: ?Id = null;
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
/// If you are calling this due to processing an event, you can pass `Event`'s num
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
    var newId: ?Id = null;
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

/// Widgets that accept text input should call this on frames they have focus.
///
/// It communicates:
/// * text input should happen (maybe shows an on screen keyboard)
/// * rect on screen (position possible IME window)
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn wantTextInput(r: Rect.Natural) void {
    const cw = currentWindow();
    cw.text_input_rect = r;
}

/// Temporary menu that floats above current layer.  Usually contains multiple
/// `menuItemLabel`, `menuItemIcon`, or `menuItem`, but can contain any
/// widgets.
///
/// Clicking outside of the menu or any child menus closes it.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn floatingMenu(src: std.builtin.SourceLocation, init_opts: FloatingMenuWidget.InitOptions, opts: Options) *FloatingMenuWidget {
    var ret = widgetAlloc(FloatingMenuWidget);
    ret.* = FloatingMenuWidget.init(src, init_opts, opts);
    ret.install();
    return ret;
}

/// Subwindow that the user can generally resize and move around.
///
/// Usually you want to add `windowHeader` as the first child.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn floatingWindow(src: std.builtin.SourceLocation, floating_opts: FloatingWindowWidget.InitOptions, opts: Options) *FloatingWindowWidget {
    var ret = widgetAlloc(FloatingWindowWidget);
    ret.* = FloatingWindowWidget.init(src, floating_opts, opts);
    ret.install();
    ret.processEventsBefore();
    ret.drawBackground();
    return ret;
}

/// Normal widgets seen at the top of `floatingWindow`.  Includes a close
/// button, centered title str, and right_str on the right.
///
/// Handles raising and focusing the subwindow on click.  To make
/// `floatingWindow` only move on a click-drag in the header, use:
///
/// floating_win.dragAreaSet(dvui.windowHeader("Title", "", show_flag));
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn windowHeader(str: []const u8, right_str: []const u8, openflag: ?*bool) Rect.Physical {
    var over = dvui.overlay(@src(), .{ .expand = .horizontal, .name = "WindowHeader" });

    dvui.labelNoFmt(@src(), str, .{ .align_x = 0.5 }, .{ .expand = .horizontal, .font_style = .heading, .padding = .{ .x = 6, .y = 6, .w = 6, .h = 4 } });

    if (openflag) |of| {
        if (dvui.buttonIcon(
            @src(),
            "close",
            entypo.cross,
            .{},
            .{},
            .{ .font_style = .heading, .corner_radius = Rect.all(1000), .padding = Rect.all(2), .margin = Rect.all(2), .gravity_y = 0.5, .expand = .ratio },
        )) {
            of.* = false;
        }
    }

    dvui.labelNoFmt(@src(), right_str, .{}, .{ .gravity_x = 1.0 });

    const evts = events();
    for (evts) |*e| {
        if (!eventMatch(e, .{ .id = over.data().id, .r = over.data().contentRectScale().r }))
            continue;

        if (e.evt == .mouse and e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
            // raise this subwindow but let the press continue so the window
            // will do the drag-move
            raiseSubwindow(subwindowCurrentId());
        } else if (e.evt == .mouse and e.evt.mouse.action == .focus) {
            // our window will already be focused, but this prevents the window
            // from clearing the focused widget
            e.handle(@src(), over.data());
        }
    }

    var ret = over.data().rectScale().r;

    over.deinit();

    const swd = dvui.separator(@src(), .{ .expand = .horizontal });
    ret.h += swd.rectScale().r.h;

    return ret;
}

pub const DialogDisplayFn = *const fn (Id) anyerror!void;
pub const DialogCallAfterFn = *const fn (Id, enums.DialogResponse) anyerror!void;

pub const Dialog = struct {
    id: Id,
    display: DialogDisplayFn,
};

pub const IdMutex = struct {
    id: Id,
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
pub fn dialogAdd(win: ?*Window, src: std.builtin.SourceLocation, id_extra: usize, display: DialogDisplayFn) IdMutex {
    if (win) |w| {
        // we are being called from non gui thread
        const id = Id.extendId(null, src, id_extra);
        const mutex = w.dialogAdd(id, display);
        refresh(win, @src(), id); // will wake up gui thread
        return .{ .id = id, .mutex = mutex };
    } else {
        if (current_window) |cw| {
            const parent = parentGet();
            const id = parent.extendId(src, id_extra);
            const mutex = cw.dialogAdd(id, display);
            refresh(win, @src(), id);
            return .{ .id = id, .mutex = mutex };
        } else {
            std.debug.panic("{s}:{d} dialogAdd current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()\n", .{ src.file, src.line });
        }
    }
}

/// Only called from gui thread.
pub fn dialogRemove(id: Id) void {
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
    default: ?enums.DialogResponse = .ok,
    max_size: ?Options.MaxSize = null,
    displayFn: DialogDisplayFn = dialogDisplay,
    callafterFn: ?DialogCallAfterFn = null,
};

/// Add a dialog to be displayed on the GUI thread during `Window.end`.
///
/// user_struct can be anytype, each field will be stored using
/// `dataSet`/`dataSetSlice` for use in `opts.displayFn`
///
/// Can be called from any thread, but if calling from a non-GUI thread or
/// outside `Window.begin`/`Window.end` you must set opts.window.
pub fn dialog(src: std.builtin.SourceLocation, user_struct: anytype, opts: DialogOptions) void {
    const id_mutex = dialogAdd(opts.window, src, opts.id_extra, opts.displayFn);
    const id = id_mutex.id;
    dataSet(opts.window, id, "_modal", opts.modal);
    dataSetSlice(opts.window, id, "_title", opts.title);
    dataSetSlice(opts.window, id, "_message", opts.message);
    dataSetSlice(opts.window, id, "_ok_label", opts.ok_label);
    dataSet(opts.window, id, "_center_on", (opts.window orelse currentWindow()).subwindow_currentRect);
    if (opts.cancel_label) |cl| {
        dataSetSlice(opts.window, id, "_cancel_label", cl);
    }
    if (opts.default) |d| {
        dataSet(opts.window, id, "_default", d);
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

pub fn dialogDisplay(id: Id) !void {
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

    const center_on = dvui.dataGet(null, id, "_center_on", Rect.Natural) orelse currentWindow().subwindow_currentRect;

    const cancel_label = dvui.dataGetSlice(null, id, "_cancel_label", []u8);
    const default = dvui.dataGet(null, id, "_default", enums.DialogResponse);

    const callafter = dvui.dataGet(null, id, "_callafter", DialogCallAfterFn);

    const maxSize = dvui.dataGet(null, id, "_max_size", Options.MaxSize);

    var win = floatingWindow(@src(), .{ .modal = modal, .center_on = center_on, .window_avoid = .nudge }, .{ .id_extra = id.asUsize(), .max_size_content = maxSize });
    defer win.deinit();

    var header_openflag = true;
    win.dragAreaSet(dvui.windowHeader(title, "", &header_openflag));
    if (!header_openflag) {
        dvui.dialogRemove(id);
        if (callafter) |ca| {
            ca(id, .cancel) catch |err| {
                log.debug("Dialog callafter for {x} returned {!}", .{ id, err });
            };
        }
        return;
    }

    {
        // Add the buttons at the bottom first, so that they are guaranteed to be shown
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 0.5, .gravity_y = 1.0 });
        defer hbox.deinit();

        if (cancel_label) |cl| {
            var cancel_data: WidgetData = undefined;
            const gravx: f32, const tindex: u16 = switch (currentWindow().button_order) {
                .cancel_ok => .{ 0.0, 1 },
                .ok_cancel => .{ 1.0, 3 },
            };
            if (dvui.button(@src(), cl, .{}, .{ .tab_index = tindex, .data_out = &cancel_data, .gravity_x = gravx })) {
                dvui.dialogRemove(id);
                if (callafter) |ca| {
                    ca(id, .cancel) catch |err| {
                        log.debug("Dialog callafter for {x} returned {!}", .{ id, err });
                    };
                }
                return;
            }
            if (default != null and dvui.firstFrame(hbox.data().id) and default.? == .cancel) {
                dvui.focusWidget(cancel_data.id, null, null);
            }
        }

        var ok_data: WidgetData = undefined;
        if (dvui.button(@src(), ok_label, .{}, .{ .tab_index = 2, .data_out = &ok_data })) {
            dvui.dialogRemove(id);
            if (callafter) |ca| {
                ca(id, .ok) catch |err| {
                    log.debug("Dialog callafter for {x} returned {!}", .{ id, err });
                };
            }
            return;
        }
        if (default != null and dvui.firstFrame(hbox.data().id) and default.? == .ok) {
            dvui.focusWidget(ok_data.id, null, null);
        }
    }

    // Now add the scroll area which will get the remaining space
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
    var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .gravity_x = 0.5 });
    tl.addText(message, .{});
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
    id: Id,
    index: usize,
    /// The size of the data in bytes
    size: usize,
    /// The filename of the uploaded file. Does not include the path of the file
    name: [:0]const u8,

    pub fn readData(self: *WasmFile, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        std.debug.assert(wasm); // WasmFile shouldn't be used outside wasm builds
        const data = try allocator.alloc(u8, self.size);
        dvui.backend.readFileData(self.id, self.index, data.ptr);
        return data;
    }
};

/// Opens a file picker WITHOUT blocking. The file can be accessed by calling `wasmFileUploaded` with the same id
///
/// This function does nothing in non-wasm builds
pub fn dialogWasmFileOpen(id: Id, opts: DialogWasmFileOptions) void {
    if (!wasm) return;
    dvui.backend.openFilePicker(id, opts.accept, false);
}

/// Will only return a non-null value for a single frame
///
/// This function does nothing in non-wasm builds
pub fn wasmFileUploaded(id: Id) ?WasmFile {
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

/// Opens a file picker WITHOUT blocking. The files can be accessed by calling `wasmFileUploadedMultiple` with the same id
///
/// This function does nothing in non-wasm builds
pub fn dialogWasmFileOpenMultiple(id: Id, opts: DialogWasmFileOptions) void {
    if (!wasm) return;
    dvui.backend.openFilePicker(id, opts.accept, true);
}

/// Will only return a non-null value for a single frame
///
/// This function does nothing in non-wasm builds
pub fn wasmFileUploadedMultiple(id: Id) ?[]WasmFile {
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
/// path or null if cancelled.  See `dialogNativeFileOpenMultiple`
///
/// Not thread safe, but can be used from any thread.
///
/// Returned string is created by passed allocator.  Not implemented for web (returns null).
pub fn dialogNativeFileOpen(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) std.mem.Allocator.Error!?[:0]const u8 {
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
pub fn dialogNativeFileOpenMultiple(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) std.mem.Allocator.Error!?[][:0]const u8 {
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
pub fn dialogNativeFileSave(alloc: std.mem.Allocator, opts: DialogNativeFileOptions) std.mem.Allocator.Error!?[:0]const u8 {
    if (wasm) {
        return null;
    }

    return dialogNativeFileInternal(false, false, alloc, opts);
}

fn dialogNativeFileInternal(comptime open: bool, comptime multiple: bool, alloc: std.mem.Allocator, opts: DialogNativeFileOptions) if (multiple) std.mem.Allocator.Error!?[][:0]const u8 else std.mem.Allocator.Error!?[:0]const u8 {
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
pub fn dialogNativeFolderSelect(alloc: std.mem.Allocator, opts: DialogNativeFolderSelectOptions) std.mem.Allocator.Error!?[]const u8 {
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
    id: Id,
    subwindow_id: ?Id,
    display: DialogDisplayFn,
};

/// Add a toast.  Use `toast` for a simple message.
///
/// If subwindow_id is null, the toast will be shown during `Window.end`.  If
/// subwindow_id is not null, separate code must call `toastsShow` or
/// `toastsFor` with that subwindow_id to retrieve this toast and display it.
///
/// Returns an id and locked mutex that must be unlocked by the caller. Caller
/// does any `dataSet` calls before unlocking the mutex to ensure that data is
/// available before the toast is displayed.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside `Window.begin`/`Window.end`, you must
/// pass a pointer to the Window you want to add the toast to.
pub fn toastAdd(win: ?*Window, src: std.builtin.SourceLocation, id_extra: usize, subwindow_id: ?Id, display: DialogDisplayFn, timeout: ?i32) IdMutex {
    if (win) |w| {
        // we are being called from non gui thread
        const id = Id.extendId(null, src, id_extra);
        const mutex = w.toastAdd(id, subwindow_id, display, timeout);
        refresh(win, @src(), id);
        return .{ .id = id, .mutex = mutex };
    } else {
        if (current_window) |cw| {
            const parent = parentGet();
            const id = parent.extendId(src, id_extra);
            const mutex = cw.toastAdd(id, subwindow_id, display, timeout);
            refresh(win, @src(), id);
            return .{ .id = id, .mutex = mutex };
        } else {
            std.debug.panic("{s}:{d} toastAdd current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()", .{ src.file, src.line });
        }
    }
}

/// Remove a previously added toast.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toastRemove(id: Id) void {
    const cw = currentWindow();
    cw.toastRemove(id);
    refresh(null, @src(), id);
}

/// Returns toasts that were previously added with non-null subwindow_id.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toastsFor(subwindow_id: ?Id) ?ToastIterator {
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
    subwindow_id: ?Id,
    i: usize,
    last_id: ?Id = null,

    pub fn init(win: *Window, subwindow_id: ?Id, i: usize) Self {
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
    subwindow_id: ?Id = null,
    timeout: ?i32 = 5_000_000,
    message: []const u8,
    displayFn: DialogDisplayFn = toastDisplay,
};

/// Add a simple toast.  Use `toastAdd` for more complex toasts.
///
/// If `opts.subwindow_id` is null, the toast will be shown during
/// `Window.end`.  If `opts.subwindow_id` is not null, separate code must call
/// `toastsShow` or `toastsFor` with that subwindow_id to retrieve this toast
/// and display it.
///
/// Can be called from any thread, but if called from a non-GUI thread or
/// outside `Window.begin`/`Window.end`, you must set `opts.window`.
pub fn toast(src: std.builtin.SourceLocation, opts: ToastOptions) void {
    const id_mutex = dvui.toastAdd(opts.window, src, opts.id_extra, opts.subwindow_id, opts.displayFn, opts.timeout);
    const id = id_mutex.id;
    dvui.dataSetSlice(opts.window, id, "_message", opts.message);
    id_mutex.mutex.unlock();
}

pub fn toastDisplay(id: Id) !void {
    const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse {
        log.err("toastDisplay lost data for toast {x}\n", .{id});
        return;
    };

    var animator = dvui.animate(@src(), .{ .kind = .alpha, .duration = 500_000 }, .{ .id_extra = id.asUsize() });
    defer animator.deinit();
    dvui.labelNoFmt(@src(), message, .{}, .{ .background = true, .corner_radius = dvui.Rect.all(1000), .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 } });

    if (dvui.timerDone(id)) {
        animator.startEnd();
    }

    if (animator.end()) {
        dvui.toastRemove(id);
    }
}

/// Standard way of showing toasts.  For the main window, this is called with
/// null in Window.end().
///
/// For floating windows or other widgets, pass non-null id. Then it shows
/// toasts that were previously added with non-null subwindow_id, and they are
/// shown on top of the current subwindow.
///
/// Toasts are shown in rect centered horizontally and 70% down vertically.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn toastsShow(id: ?Id, rect: Rect.Natural) void {
    var ti = dvui.toastsFor(id);
    if (ti) |*it| {
        var toast_win = dvui.FloatingWindowWidget.init(@src(), .{ .stay_above_parent_window = id != null, .process_events_in_deinit = false }, .{ .background = false, .border = .{} });
        defer toast_win.deinit();

        toast_win.data().rect = dvui.placeIn(.cast(rect), toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
        toast_win.install();
        toast_win.drawBackground();
        toast_win.autoSize(); // affects next frame

        var vbox = dvui.box(@src(), .{}, .{});
        defer vbox.deinit();

        while (it.next()) |t| {
            t.display(t.id) catch |err| {
                log.warn("Toast {x} got {!} from its display function", .{ t.id, err });
            };
        }
    }
}

/// Wrapper widget that takes a single child and animates it.
///
/// `AnimateWidget.start` is called for you on the first frame.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn animate(src: std.builtin.SourceLocation, init_opts: AnimateWidget.InitOptions, opts: Options) *AnimateWidget {
    var ret = widgetAlloc(AnimateWidget);
    ret.* = AnimateWidget.init(src, init_opts, opts);
    ret.install();
    return ret;
}

/// Show chosen entry, and click to display all entries in a floating menu.
///
/// See `DropdownWidget` for more advanced usage.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn dropdown(src: std.builtin.SourceLocation, entries: []const []const u8, choice: *usize, opts: Options) bool {
    var dd = dvui.DropdownWidget.init(src, .{ .selected_index = choice.*, .label = entries[choice.*] }, opts);
    dd.install();

    var ret = false;
    if (dd.dropped()) {
        for (entries, 0..) |e, i| {
            if (dd.addChoiceLabel(e)) {
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
    open_on_text_change: bool = true,
    open_on_focus: bool = true,
};

/// Wraps a textEntry to provide an attached menu (dropdown) of choices.
///
/// Use after TextEntryWidget.install(), and handles events, so don't call
/// TextEntryWidget.processEvents().
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn suggestion(te: *TextEntryWidget, init_opts: SuggestionInitOptions) *SuggestionWidget {
    var open_sug = init_opts.opened;

    if (init_opts.button) {
        if (dvui.buttonIcon(
            @src(),
            "combobox_triangle",
            entypo.chevron_small_down,
            .{},
            .{},
            .{ .expand = .ratio, .margin = dvui.Rect.all(2), .gravity_x = 1.0, .tab_index = 0 },
        )) {
            open_sug = true;
            dvui.focusWidget(te.data().id, null, null);
        }
    }

    const min_width = te.textLayout.data().backgroundRect().w;

    var sug = widgetAlloc(SuggestionWidget);
    sug.* = dvui.SuggestionWidget.init(@src(), .{ .rs = te.data().borderRectScale(), .text_entry_id = te.data().id }, .{ .min_size_content = .{ .w = min_width }, .padding = .{}, .border = te.data().options.borderGet() });
    sug.install();
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
                    e.handle(@src(), sug.menu.data());
                    if (sug.willOpen()) {
                        sug.selected_index -|= 1;
                    } else {
                        sug.open();
                    }
                },
                .down => {
                    e.handle(@src(), sug.menu.data());
                    if (sug.willOpen()) {
                        sug.selected_index += 1;
                    } else {
                        sug.open();
                    }
                },
                .escape => {
                    e.handle(@src(), sug.menu.data());
                    sug.close();
                },
                .enter => {
                    if (sug.willOpen()) {
                        e.handle(@src(), sug.menu.data());
                        sug.activate_selected = true;
                    }
                },
                else => {
                    if (sug.willOpen() and e.evt.key.action == .down) {
                        if (e.evt.key.matchBind("next_widget")) {
                            e.handle(@src(), sug.menu.data());
                            sug.close();
                        } else if (e.evt.key.matchBind("prev_widget")) {
                            e.handle(@src(), sug.menu.data());
                            sug.close();
                        }
                    }
                },
            }
        }

        if (!e.handled) {
            te.processEvent(e);
        }
    }

    if (init_opts.open_on_text_change and te.text_changed) {
        sug.open();
    }

    if (init_opts.open_on_focus) {
        const focused_last_frame = dvui.dataGet(null, te.data().id, "_focused_last_frame", bool) orelse false;
        const focused_now = dvui.focusedWidgetIdInCurrentSubwindow() == te.data().id;

        if (!focused_last_frame and focused_now) {
            sug.open();
        }

        dvui.dataSet(null, te.data().id, "_focused_last_frame", focused_now);
    }

    return sug;
}

pub const ComboBox = struct {
    te: *TextEntryWidget = undefined,
    sug: *SuggestionWidget = undefined,

    /// Returns index of entry if one was selected
    pub fn entries(self: *ComboBox, items: []const []const u8) ?usize {
        if (self.sug.dropped()) {
            for (items, 0..) |entry, i| {
                if (self.sug.addChoiceLabel(entry)) {
                    self.te.textSet(entry, false);
                    return i;
                }
            }
        }
        return null;
    }

    pub fn deinit(self: *ComboBox) void {
        defer widgetFree(self);
        self.sug.deinit();
        self.te.deinit();
        self.* = undefined;
    }
};

/// Text entry widget with dropdown choices.
///
/// Call `ComboBox.entries` after this with the choices.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn comboBox(src: std.builtin.SourceLocation, init_opts: TextEntryWidget.InitOptions, opts: Options) *ComboBox {
    var combo = widgetAlloc(ComboBox);
    combo.te = widgetAlloc(TextEntryWidget);
    combo.te.* = dvui.TextEntryWidget.init(src, init_opts, opts);
    combo.te.install();

    combo.sug = dvui.suggestion(combo.te, .{ .button = true, .open_on_focus = false, .open_on_text_change = false });
    // suggestion forwards events to textEntry, so don't call te.processEvents()
    combo.te.draw();

    return combo;
}

pub var expander_defaults: Options = .{
    .padding = Rect.all(4),
    .font_style = .heading,
};

pub const ExpanderOptions = struct {
    default_expanded: bool = false,
};

/// Arrow icon and label that remembers if it has been clicked (expanded).
///
/// Use to divide lots of content into expandable sections.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn expander(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: ExpanderOptions, opts: Options) bool {
    const options = expander_defaults.override(opts);

    // Use the ButtonWidget to do margin/border/padding, but use strip so we
    // don't get any of ButtonWidget's defaults
    var bc = ButtonWidget.init(src, .{}, options.strip().override(options));
    bc.install();
    bc.processEvents();
    bc.drawBackground();
    bc.drawFocus();
    defer bc.deinit();

    var expanded: bool = init_opts.default_expanded;
    if (dvui.dataGet(null, bc.data().id, "_expand", bool)) |e| {
        expanded = e;
    }

    if (bc.clicked()) {
        expanded = !expanded;
    }

    var bcbox = BoxWidget.init(@src(), .{ .dir = .horizontal }, options.strip());
    defer bcbox.deinit();
    bcbox.install();
    bcbox.drawBackground();
    if (expanded) {
        icon(@src(), "down_arrow", entypo.triangle_down, .{}, .{ .gravity_y = 0.5 });
    } else {
        icon(
            @src(),
            "right_arrow",
            entypo.triangle_right,
            .{},
            .{ .gravity_y = 0.5 },
        );
    }
    labelNoFmt(@src(), label_str, .{}, options.strip());

    dvui.dataSet(null, bc.data().id, "_expand", expanded);

    return expanded;
}

/// Splits area in two with a user-moveable sash between.
///
/// Automatically collapses (only shows one of the two sides) when it has less
/// than init_opts.collapsed_size space.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn paned(src: std.builtin.SourceLocation, init_opts: PanedWidget.InitOptions, opts: Options) *PanedWidget {
    var ret = widgetAlloc(PanedWidget);
    ret.* = PanedWidget.init(src, init_opts, opts);
    ret.install();
    ret.processEvents();
    return ret;
}

/// Show text with wrapping (optional).  Supports mouse and touch selection.
///
/// Text is added incrementally with `TextLayoutWidget.addText` or
/// `TextLayoutWidget.format`.  Each call can have different styling.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textLayout(src: std.builtin.SourceLocation, init_opts: TextLayoutWidget.InitOptions, opts: Options) *TextLayoutWidget {
    var ret = widgetAlloc(TextLayoutWidget);
    ret.* = TextLayoutWidget.init(src, init_opts, opts);
    ret.install(.{});

    // can install corner widgets here
    //_ = dvui.button(@src(), "upright", .{}, .{ .gravity_x = 1.0 });

    if (ret.touchEditing()) |floating_widget| {
        defer floating_widget.deinit();
        ret.touchEditingMenu();
    }

    ret.processEvents();

    // call addText() any number of times

    // can call addTextDone() (will be called automatically if you don't)
    return ret;
}

/// Context menu.  Pass a screen space pixel rect in `init_opts`, then
/// `.activePoint()` says whether to show a menu.
///
/// The menu code should happen before `.deinit()`, but don't put regular widgets
/// directly inside Context.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn context(src: std.builtin.SourceLocation, init_opts: ContextWidget.InitOptions, opts: Options) *ContextWidget {
    var ret = widgetAlloc(ContextWidget);
    ret.* = ContextWidget.init(src, init_opts, opts);
    ret.install();
    ret.processEvents();
    return ret;
}

/// Show a floating text tooltip as long as the mouse is inside init_opts.active_rect.
///
/// Use init_opts.interactive = true to allow mouse interaction with the
/// tooltip contents.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn tooltip(src: std.builtin.SourceLocation, init_opts: FloatingTooltipWidget.InitOptions, comptime fmt: []const u8, fmt_args: anytype, opts: Options) void {
    var tt: dvui.FloatingTooltipWidget = .init(src, init_opts, opts);
    if (tt.shown()) {
        var tl2 = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl2.format(fmt, fmt_args, .{});
        tl2.deinit();
    }
    tt.deinit();
}

/// Shim to make widget ids unique.
///
/// Useful when you wrap some widgets into a function, but that function does
/// not have a parent widget.  See makeLabels() in src/Examples.zig
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn virtualParent(src: std.builtin.SourceLocation, opts: Options) *VirtualParentWidget {
    var ret = widgetAlloc(VirtualParentWidget);
    ret.* = VirtualParentWidget.init(src, opts);
    ret.install();
    return ret;
}

/// Lays out children according to gravity anywhere inside.  Useful to overlap
/// children.
///
/// See `box`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn overlay(src: std.builtin.SourceLocation, opts: Options) *OverlayWidget {
    var ret = widgetAlloc(OverlayWidget);
    ret.* = OverlayWidget.init(src, opts);
    ret.install();
    ret.drawBackground();
    return ret;
}

/// Box that packs children with gravity 0 or 1, or anywhere with gravity
/// between (0,1).
///
/// A child with gravity between (0,1) in dir direction is not packed, and
/// instead positioned in the whole box area, like `overlay`.
///
/// A child with gravity 0 or 1 in dir direction is packed either at the start
/// (gravity 0) or end (gravity 1).
///
/// Extra space is allocated evenly to all packed children expanded in dir
/// direction.
///
/// If init_opts.equal_space is true, all packed children get equal space.
///
/// See `flexbox`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn box(src: std.builtin.SourceLocation, init_opts: BoxWidget.InitOptions, opts: Options) *BoxWidget {
    var ret = widgetAlloc(BoxWidget);
    ret.* = BoxWidget.init(src, init_opts, opts);
    ret.install();
    ret.drawBackground();
    return ret;
}

/// Box laying out children horizontally, making new rows as needed.
///
/// See `box`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn flexbox(src: std.builtin.SourceLocation, init_opts: FlexBoxWidget.InitOptions, opts: Options) *FlexBoxWidget {
    var ret = widgetAlloc(FlexBoxWidget);
    ret.* = FlexBoxWidget.init(src, init_opts, opts);
    ret.install();
    ret.drawBackground();
    return ret;
}

pub fn cache(src: std.builtin.SourceLocation, init_opts: CacheWidget.InitOptions, opts: Options) *CacheWidget {
    var ret = widgetAlloc(CacheWidget);
    ret.* = CacheWidget.init(src, init_opts, opts);
    ret.install();
    return ret;
}

pub fn reorder(src: std.builtin.SourceLocation, opts: Options) *ReorderWidget {
    var ret = widgetAlloc(ReorderWidget);
    ret.* = ReorderWidget.init(src, opts);
    ret.install();
    ret.processEvents();
    return ret;
}

pub fn scrollArea(src: std.builtin.SourceLocation, init_opts: ScrollAreaWidget.InitOpts, opts: Options) *ScrollAreaWidget {
    var ret = widgetAlloc(ScrollAreaWidget);
    ret.* = ScrollAreaWidget.init(src, init_opts, opts);
    ret.install();
    return ret;
}

pub fn grid(src: std.builtin.SourceLocation, cols: GridWidget.WidthsOrNum, init_opts: GridWidget.InitOpts, opts: Options) *GridWidget {
    const ret = widgetAlloc(GridWidget);
    ret.* = GridWidget.init(src, cols, init_opts, opts);
    ret.install();
    return ret;
}

/// Create either a draggable separator (resize_options != null)
/// or a standard separator (resize_options = null) for a grid heading.
pub fn gridHeadingSeparator(resize_options: ?GridWidget.HeaderResizeWidget.InitOptions) void {
    if (resize_options) |resize_opts| {
        var handle: GridWidget.HeaderResizeWidget = .init(
            @src(),
            .vertical,
            resize_opts,
            .{ .gravity_x = 1.0 },
        );
        handle.install();
        handle.processEvents();
        handle.deinit();
    } else {
        _ = separator(@src(), .{ .expand = .vertical, .gravity_x = 1.0 });
    }
}

/// Create a heading with a static label
pub fn gridHeading(
    src: std.builtin.SourceLocation,
    g: *GridWidget,
    col_num: usize,
    heading: []const u8,
    resize_opts: ?GridWidget.HeaderResizeWidget.InitOptions,
    cell_style: anytype, // GridWidget.CellStyle
) void {
    const label_defaults: Options = .{
        .corner_radius = Rect.all(0),
        .expand = .horizontal,
        .gravity_x = 0.5,
        .gravity_y = 0.5,
        .background = true,
    };
    const opts = if (@TypeOf(cell_style) == @TypeOf(.{})) GridWidget.CellStyle.none else cell_style;

    const label_options = label_defaults.override(opts.options(.colRow(col_num, 0)));
    var cell = g.headerCell(src, col_num, opts.cellOptions(.colRow(col_num, 0)));
    defer cell.deinit();

    labelNoFmt(@src(), heading, .{}, label_options);
    gridHeadingSeparator(resize_opts);
}

/// Create a heading and allow the column to be sorted.
///
/// Returns true if the sort direction has changed.
/// sort_dir is an out parameter containing the current sort direction.
pub fn gridHeadingSortable(
    src: std.builtin.SourceLocation,
    g: *GridWidget,
    col_num: usize,
    heading: []const u8,
    dir: *GridWidget.SortDirection,
    resize_opts: ?GridWidget.HeaderResizeWidget.InitOptions,
    cell_style: anytype, // GridWidget.CellStyle
) bool {
    const icon_ascending = dvui.entypo.chevron_small_up;
    const icon_descending = dvui.entypo.chevron_small_down;

    // Pad buttons with extra space if there is no sort indicator.
    const heading_defaults: Options = .{
        .expand = .horizontal,
        .corner_radius = Rect.all(0),
    };
    const opts = if (@TypeOf(cell_style) == @TypeOf(.{})) GridWidget.CellStyle.none else cell_style;
    const heading_opts = heading_defaults.override(opts.options(.col(col_num)));

    var cell = g.headerCell(src, col_num, opts.cellOptions(.col(col_num)));
    defer cell.deinit();

    gridHeadingSeparator(resize_opts);

    const sort_changed = switch (g.colSortOrder(col_num)) {
        .unsorted => button(@src(), heading, .{ .draw_focus = false }, heading_opts),
        .ascending => buttonLabelAndIcon(@src(), heading, icon_ascending, .{ .draw_focus = false }, heading_opts),
        .descending => buttonLabelAndIcon(@src(), heading, icon_descending, .{ .draw_focus = false }, heading_opts),
    };

    if (sort_changed) {
        g.sortChanged(col_num);
    }
    dir.* = g.sort_direction;
    return sort_changed;
}

/// A grid heading with a checkbox for select-all and select-none
///
/// Returns true if the selection state has changed.
/// selection - out parameter containing the current selection state.
pub fn gridHeadingCheckbox(
    src: std.builtin.SourceLocation,
    g: *GridWidget,
    col_num: usize,
    select_state: *selection.SelectAllState,
    cell_style: anytype, // GridWidget.CellStyle
) bool {
    const header_defaults: Options = .{
        .background = true,
        .expand = .both,
        .margin = ButtonWidget.defaults.marginGet(),
        .gravity_x = 0.5,
        .gravity_y = 0.5,
    };

    const opts = if (@TypeOf(cell_style) == @TypeOf(.{})) GridWidget.CellStyle.none else cell_style;

    const header_options = header_defaults.override(opts.options(.col(col_num)));
    var checkbox_opts: Options = header_options.strip();
    checkbox_opts.padding = ButtonWidget.defaults.paddingGet();
    checkbox_opts.gravity_x = header_options.gravity_x;
    checkbox_opts.gravity_y = header_options.gravity_y;

    var cell = g.headerCell(src, col_num, opts.cellOptions(.col(col_num)));
    defer cell.deinit();

    var is_clicked = false;
    var selected = select_state.* == .select_all;
    {
        _ = dvui.separator(@src(), .{ .expand = .vertical, .gravity_x = 1.0 });

        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, header_options);
        defer hbox.deinit();

        is_clicked = dvui.checkbox(@src(), &selected, null, checkbox_opts);
    }
    if (is_clicked) {
        select_state.* = if (selected) .select_all else .select_none;
    }
    return is_clicked;
}

/// Size columns widths using ratios.
///
/// Positive widths are treated as fixed widths and are not modified.
/// Negative widths are treated as ratios and are replaced by a calculated width.
/// Results are returned in col_widths, which will always be positive (or zero) values.
/// If content_width is larger than the grid's visible area, horizontal scrolling should be enabled via the grid's init_opts.
///
/// Examples:
/// To lay out three columns with equal widths, use the same negative ratio for each column:
///     { -1, -1, -1 } or { -0.33, -0.33, -0.33 }
/// To make the second column with twice the width of the first, use a negative ratio twice as large.
///     {-1, -2 } or { -50, -100 }
/// To lay out a fixed column width with all other columns sharing the remaining, use a positive width for the fixed column and
/// the same negative ratio for the variable columns.
///     { -1, 50, -1 }.
pub fn columnLayoutProportional(ratio_widths: []const f32, col_widths: []f32, content_width: f32) void {
    const scroll_bar_w: f32 = GridWidget.scrollbar_padding_defaults.w;
    std.debug.assert(ratio_widths.len == col_widths.len); // input and output slices must be the same length

    // Count all of the positive widths as reserved widths.
    // Total all of the negative widths.
    const reserved_w, const ratio_w_total: f32 = blk: {
        var res_width: f32 = 0;
        var total_ratio_w: f32 = 0;
        for (ratio_widths) |w| {
            if (w <= 0) {
                total_ratio_w += -w;
            } else {
                res_width += w;
            }
        }
        break :blk .{ res_width, total_ratio_w };
    };
    const available_w = content_width - reserved_w - scroll_bar_w;

    // For each negative width, replace it width a positive calculated width.
    for (col_widths, ratio_widths) |*col_w, ratio_w| {
        if (ratio_w <= 0) {
            col_w.* = -ratio_w / ratio_w_total * available_w;
        } else {
            col_w.* = ratio_w;
        }
    }
}

/// Widget for making thin lines to visually separate other widgets.  Use
/// .min_size_content to control size.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn separator(src: std.builtin.SourceLocation, opts: Options) WidgetData {
    const defaults: Options = .{
        .name = "Separator",
        .background = true, // TODO: remove this when border and background are no longer coupled
        .color_fill = dvui.themeGet().border,
        .min_size_content = .{ .w = 1, .h = 1 },
    };

    var wd = WidgetData.init(src, .{}, defaults.override(opts));
    wd.register();
    wd.borderAndBackground(.{});
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
    return wd;
}

/// Empty widget used to take up space with .min_size_content.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn spacer(src: std.builtin.SourceLocation, opts: Options) WidgetData {
    const defaults: Options = .{ .name = "Spacer" };
    var wd = WidgetData.init(src, .{}, defaults.override(opts));
    wd.register();
    wd.borderAndBackground(.{});
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
    return wd;
}

pub fn spinner(src: std.builtin.SourceLocation, opts: Options) void {
    var defaults: Options = .{
        .name = "Spinner",
        .min_size_content = .{ .w = 50, .h = 50 },
    };
    const options = defaults.override(opts);
    var wd = WidgetData.init(src, .{}, options);
    wd.register();
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

    var path: Path.Builder = .init(dvui.currentWindow().lifo());
    defer path.deinit();

    const full_circle = 2 * std.math.pi;
    // start begins fast, speeding away from end
    const start = full_circle * easing.outSine(t);
    // end begins slow, catching up to start
    const end = full_circle * easing.inSine(t);

    path.addArc(r.center(), @min(r.w, r.h) / 3, start, end, false);
    path.build().stroke(.{ .thickness = 3.0 * rs.s, .color = options.color(.text) });
}

pub fn scale(src: std.builtin.SourceLocation, init_opts: ScaleWidget.InitOptions, opts: Options) *ScaleWidget {
    var ret = widgetAlloc(ScaleWidget);
    ret.* = ScaleWidget.init(src, init_opts, opts);
    ret.install();
    ret.processEvents();
    return ret;
}

pub fn menu(src: std.builtin.SourceLocation, dir: enums.Direction, opts: Options) *MenuWidget {
    var ret = widgetAlloc(MenuWidget);
    ret.* = MenuWidget.init(src, .{ .dir = dir }, opts);
    ret.install();
    return ret;
}

pub fn menuItemLabel(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) ?Rect.Natural {
    var mi = menuItem(src, init_opts, opts);

    var labelopts = opts.strip();

    var ret: ?Rect.Natural = null;
    if (mi.activeRect()) |r| {
        ret = r;
    }

    if (mi.show_active) {
        labelopts.style = .highlight;
    }

    labelNoFmt(@src(), label_str, .{}, labelopts);

    mi.deinit();

    return ret;
}

pub fn menuItemIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: MenuItemWidget.InitOptions, opts: Options) ?Rect.Natural {
    var mi = menuItem(src, init_opts, opts);

    // pass min_size_content through to the icon so that it will figure out the
    // min width based on the height
    var iconopts = opts.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = opts.min_size_content, .expand = .ratio, .color_text = opts.color_text });

    var ret: ?Rect.Natural = null;
    if (mi.activeRect()) |r| {
        ret = r;
    }

    if (mi.show_active) {
        iconopts.style = .highlight;
    }

    icon(@src(), name, tvg_bytes, .{}, iconopts);

    mi.deinit();

    return ret;
}

pub fn menuItem(src: std.builtin.SourceLocation, init_opts: MenuItemWidget.InitOptions, opts: Options) *MenuItemWidget {
    var ret = widgetAlloc(MenuItemWidget);
    ret.* = MenuItemWidget.init(src, init_opts, opts);
    ret.install();
    ret.processEvents();
    ret.drawBackground();
    return ret;
}

/// A clickable label.  Good for hyperlinks.
/// Returns true if it's been clicked.
pub fn labelClick(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, init_opts: LabelWidget.InitOptions, opts: Options) bool {
    var lw = LabelWidget.init(src, fmt, args, init_opts, opts.override(.{ .name = "LabelClick" }));
    // draw border and background
    lw.install();

    dvui.tabIndexSet(lw.data().id, lw.data().options.tab_index);

    const ret = dvui.clicked(lw.data(), .{});

    // draw text
    lw.draw();

    // draw an accent border if we are focused
    if (lw.data().id == dvui.focusedWidgetId()) {
        lw.data().focusBorder();
    }

    // done with lw, have it report min size to parent
    lw.deinit();

    return ret;
}

/// Format and display a label.
///
/// See `labelEx` and `labelNoFmt`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn label(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) void {
    var lw = LabelWidget.init(src, fmt, args, .{}, opts);
    lw.install();
    lw.draw();
    lw.deinit();
}

/// Format and display a label with extra label options.
///
/// See `label` and `labelNoFmt`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn labelEx(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, init_opts: LabelWidget.InitOptions, opts: Options) void {
    var lw = LabelWidget.init(src, fmt, args, init_opts, opts);
    lw.install();
    lw.draw();
    lw.deinit();
}

/// Display a label (no formatting) with extra label options.
///
/// See `label` and `labelEx`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn labelNoFmt(src: std.builtin.SourceLocation, str: []const u8, init_opts: LabelWidget.InitOptions, opts: Options) void {
    var lw = LabelWidget.initNoFmt(src, str, init_opts, opts);
    lw.install();
    lw.draw();
    lw.deinit();
}

/// Display an icon rasterized lazily from tvg_bytes.
///
/// See `buttonIcon` and `buttonLabelAndIcon`.
///
/// icon_opts controls the rasterization, and opts.color_text is multiplied in
/// the shader.  If icon_opts is the default, then the text color is multiplied
/// in the shader even if not passed in opts.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn icon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, icon_opts: IconRenderOptions, opts: Options) void {
    var iw = IconWidget.init(src, name, tvg_bytes, icon_opts, opts);
    iw.install();
    iw.draw();
    iw.deinit();
}

/// Source data for `image()` and `imageSize()`.
pub const ImageSource = union(enum) {
    /// bytes of an supported image file (i.e. png, jpeg, gif, ...)
    imageFile: struct {
        bytes: []const u8,
        // Optional name/filename for debugging
        name: []const u8 = "imageFile",
        interpolation: enums.TextureInterpolation = .linear,
        invalidation: InvalidationStrategy = .ptr,
    },

    /// bytes of an premultiplied rgba u8 array in row major order
    pixelsPMA: struct {
        rgba: []Color.PMA,
        width: u32,
        height: u32,
        interpolation: enums.TextureInterpolation = .linear,
        invalidation: InvalidationStrategy = .ptr,
    },

    /// bytes of a non premultiplied rgba u8 array in row major order, will
    /// be converted to premultiplied when making a texture
    pixels: struct {
        /// FIXME: This cannot use `[]const Color` because it's not marked `extern`
        ///        and doesn't have a stable memory layout
        rgba: []const u8,
        width: u32,
        height: u32,
        interpolation: enums.TextureInterpolation = .linear,
        invalidation: InvalidationStrategy = .ptr,
    },

    /// When providing a texture directly, `hash` will return 0 and it will
    /// not be inserted into the texture cache.
    texture: Texture,

    pub const InvalidationStrategy = enum {
        /// The pointer will be used to determine if the source has changed.
        ///
        /// Changing the data behind the pointer will NOT invalidate the texture
        ptr,
        /// The bytes will be used to determine if the source has changed.
        ///
        /// Changing the data behind the pointer WILL invalidate the texture,
        /// but checking all the bytes every frame can be costly
        bytes,
        /// Do not cache the texture at all and generate a new texture each frame
        always,
    };

    /// Pass the return value of this to `dvui.textureInvalidate` to
    /// remove the texture from the cache.
    ///
    /// When providing a texture directly with `ImageSource.texture`,
    /// this function will always return 0 as it doesn't interact with
    /// the texture cache.
    pub fn hash(self: ImageSource) u64 {
        var h = fnv.init();
        // .always hashes ptr (for uniqueness) and image dimensions so we can update the texture if dimensions stay the same
        const img_dimensions = imageSize(self) catch Size{ .w = 0, .h = 0 };
        var dim: [2]u32 = .{ @intFromFloat(img_dimensions.w), @intFromFloat(img_dimensions.h) };
        const img_dim_bytes = std.mem.asBytes(&dim); // hashing u32 here instead of float because of unstable bit representation in floating point numbers

        switch (self) {
            .imageFile => |file| {
                switch (file.invalidation) {
                    .ptr => h.update(std.mem.asBytes(&file.bytes.ptr)),
                    .bytes => h.update(file.bytes),
                    .always => {
                        h.update(std.mem.asBytes(&file.bytes.ptr));
                        h.update(img_dim_bytes);
                    },
                }
                h.update(std.mem.asBytes(&@intFromEnum(file.interpolation)));
            },
            .pixelsPMA => |pixels| {
                switch (pixels.invalidation) {
                    .ptr, .always => h.update(std.mem.asBytes(&pixels.rgba.ptr)),
                    .bytes => h.update(@ptrCast(pixels.rgba)),
                }
                h.update(std.mem.asBytes(&@intFromEnum(pixels.interpolation)));
                h.update(img_dim_bytes);
            },
            .pixels => |pixels| {
                switch (pixels.invalidation) {
                    .ptr, .always => h.update(std.mem.asBytes(&pixels.rgba.ptr)),
                    .bytes => h.update(std.mem.sliceAsBytes(pixels.rgba)),
                }
                h.update(std.mem.asBytes(&@intFromEnum(pixels.interpolation)));
                h.update(img_dim_bytes);
            },
            .texture => return 0,
        }
        return h.final();
    }

    /// Will get the texture from cache or create it if it doesn't already exist
    ///
    /// Only valid between `Window.begin` and `Window.end`
    pub fn getTexture(self: ImageSource) !Texture {
        const key = self.hash();
        const invalidate = switch (self) {
            .imageFile => |f| f.invalidation,
            .pixels => |px| px.invalidation,
            .pixelsPMA => |px| px.invalidation,
            // return texture directly
            .texture => |tex| return tex,
        };
        if (textureGetCached(key)) |cached_texture| {
            // if invalidate = always, we update the texture using updateImageSource for efficency, otherwise return the cached Texture
            if (invalidate == .always) {
                var tex_mut = cached_texture;
                try tex_mut.updateImageSource(self);
                return tex_mut;
            } else return cached_texture;
        } else {
            // cache was empty we create a new Texture
            const new_texture = try Texture.fromImageSource(self);
            textureAddToCache(key, new_texture);
            return new_texture;
        }
    }
};

/// Get the size of a raster image.  If source is .imageFile, this only decodes
/// enough info to get the size.
///
/// See `image`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn imageSize(source: ImageSource) !Size {
    switch (source) {
        .imageFile => |file| {
            var w: c_int = undefined;
            var h: c_int = undefined;
            var n: c_int = undefined;
            const ok = c.stbi_info_from_memory(file.bytes.ptr, @as(c_int, @intCast(file.bytes.len)), &w, &h, &n);
            if (ok == 1) {
                return .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
            } else {
                log.warn("imageSize stbi_info error on image \"{s}\": {s}\n", .{ file.name, c.stbi_failure_reason() });
                return StbImageError.stbImageError;
            }
        },
        .pixelsPMA => |a| return .{ .w = @floatFromInt(a.width), .h = @floatFromInt(a.height) },
        .pixels => |a| return .{ .w = @floatFromInt(a.width), .h = @floatFromInt(a.height) },
        .texture => |tex| return .{ .w = @floatFromInt(tex.width), .h = @floatFromInt(tex.height) },
    }
}

pub const ImageInitOptions = struct {
    /// Data to create the texture.
    source: ImageSource,

    /// If min size is larger than the rect we got, how to shrink it:
    /// - null => use expand setting
    /// - none => crop
    /// - horizontal => crop height, fit width
    /// - vertical => crop width, fit height
    /// - both => fit in rect ignoring aspect ratio
    /// - ratio => fit in rect maintaining aspect ratio
    shrink: ?Options.Expand = null,

    uv: Rect = .{ .w = 1, .h = 1 },
};

/// Show raster image.  dvui will handle texture creation/destruction for you,
/// unless the source is .texture.  See ImageSource.InvalidationStrategy.
///
/// See `imageSize`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn image(src: std.builtin.SourceLocation, init_opts: ImageInitOptions, opts: Options) WidgetData {
    const options = (Options{ .name = "image" }).override(opts);

    var size = Size{};
    if (options.min_size_content) |msc| {
        // user gave us a min size, use it
        size = msc;
    } else {
        // user didn't give us one, use natural size
        size = dvui.imageSize(init_opts.source) catch .{ .w = 10, .h = 10 };
    }

    var wd = WidgetData.init(src, .{}, options.override(.{ .min_size_content = size }));
    wd.register();

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

    if (too_big and e != .ratio) {
        if (ms.w > cr.w and !e.isHorizontal()) {
            rect.w = ms.w;
            rect.x -= g.x * (ms.w - cr.w);
        }

        if (ms.h > cr.h and !e.isVertical()) {
            rect.h = ms.h;
            rect.y -= g.y * (ms.h - cr.h);
        }
    }

    // rect is the content rect, so expand to the whole rect
    wd.rect = rect.outset(wd.options.paddingGet()).outset(wd.options.borderGet()).outset(wd.options.marginGet());

    var renderBackground: ?Color = if (wd.options.backgroundGet()) wd.options.color(.fill) else null;

    if (wd.options.rotationGet() == 0.0) {
        wd.borderAndBackground(.{});
        renderBackground = null;
    } else {
        if (wd.options.borderGet().nonZero()) {
            dvui.log.debug("image {x} can't render border while rotated\n", .{wd.id});
        }
    }
    const render_tex_opts = RenderTextureOptions{
        .rotation = wd.options.rotationGet(),
        .corner_radius = wd.options.corner_radiusGet(),
        .uv = init_opts.uv,
        .background_color = renderBackground,
    };
    const content_rs = wd.contentRectScale();
    renderImage(init_opts.source, content_rs, render_tex_opts) catch |err| logError(@src(), err, "Could not render image {?s} at {}", .{ opts.name, content_rs });
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    return wd;
}

pub fn debugFontAtlases(src: std.builtin.SourceLocation, opts: Options) void {
    const cw = currentWindow();

    var width: u32 = 0;
    var height: u32 = 0;
    var it = cw.font_cache.iterator();
    while (it.next()) |kv| {
        const texture_atlas = kv.value_ptr.getTextureAtlas() catch |err| {
            // TODO: Maybe FontCacheEntry should keep the font name for debugging? (FIX BELLOW TOO)
            dvui.logError(@src(), err, "Could not get texture atlast with key {x} at height {d}", .{ kv.key_ptr.*, kv.value_ptr.height });
            continue;
        };
        width = @max(width, texture_atlas.width);
        height += texture_atlas.height;
    }

    const sizePhys: Size.Physical = .{ .w = @floatFromInt(width), .h = @floatFromInt(height) };

    const ss = parentGet().screenRectScale(Rect{}).s;
    const size = sizePhys.scale(1.0 / ss, Size);

    var wd = WidgetData.init(src, .{}, opts.override(.{ .name = "debugFontAtlases", .min_size_content = size }));
    wd.register();

    wd.borderAndBackground(.{});

    var rs = wd.parent.screenRectScale(placeIn(wd.contentRect(), size, .none, opts.gravityGet()));
    const color = opts.color(.text);

    if (cw.snap_to_pixels) {
        rs.r.x = @round(rs.r.x);
        rs.r.y = @round(rs.r.y);
    }

    it = cw.font_cache.iterator();
    while (it.next()) |kv| {
        const texture_atlas = kv.value_ptr.getTextureAtlas() catch continue;
        rs.r = rs.r.toSize(.{
            .w = @floatFromInt(texture_atlas.width),
            .h = @floatFromInt(texture_atlas.height),
        });
        renderTexture(texture_atlas, rs, .{ .colormod = color }) catch |err| {
            logError(@src(), err, "Could not render font atlast", .{});
        };
        rs.r.y += rs.r.h;
    }

    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();
}

pub fn button(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) bool {
    // initialize widget and get rectangle from parent
    var bw = ButtonWidget.init(src, init_opts, opts);

    // make ourselves the new parent
    bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();

    // draw background/border
    bw.drawBackground();

    // use pressed text color if desired
    const click = bw.clicked();

    // this child widget:
    // - has bw as parent
    // - gets a rectangle from bw
    // - draws itself
    // - reports its min size to bw
    labelNoFmt(@src(), label_str, .{ .align_x = 0.5, .align_y = 0.5 }, opts.strip()
        // override with the button colors to update the press and hover colors correctly
        .override(bw.colors())
        .override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));

    // draw focus
    bw.drawFocus();

    // restore previous parent
    // send our min size to parent
    bw.deinit();

    return click;
}

pub fn buttonIcon(src: std.builtin.SourceLocation, name: []const u8, tvg_bytes: []const u8, init_opts: ButtonWidget.InitOptions, icon_opts: IconRenderOptions, opts: Options) bool {
    const defaults = Options{ .padding = Rect.all(4) };
    var bw = ButtonWidget.init(src, init_opts, defaults.override(opts));
    bw.install();
    bw.processEvents();
    bw.drawBackground();

    // When someone passes min_size_content to buttonIcon, they want the icon
    // to be that size, so we pass it through.
    icon(
        @src(),
        name,
        tvg_bytes,
        icon_opts,
        opts.strip().override(bw.colors()).override(.{ .gravity_x = 0.5, .gravity_y = 0.5, .min_size_content = opts.min_size_content, .expand = .ratio, .color_text = opts.color_text }),
    );

    const click = bw.clicked();
    bw.drawFocus();
    bw.deinit();
    return click;
}

pub fn buttonLabelAndIcon(src: std.builtin.SourceLocation, label_str: []const u8, tvg_bytes: []const u8, init_opts: ButtonWidget.InitOptions, opts: Options) bool {
    // initialize widget and get rectangle from parent
    var bw = ButtonWidget.init(src, init_opts, opts);

    // make ourselves the new parent
    bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();
    const options = opts.strip().override(bw.colors()).override(.{ .gravity_y = 0.5 });

    // draw background/border
    bw.drawBackground();
    {
        var outer_hbox = box(src, .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer outer_hbox.deinit();
        icon(@src(), label_str, tvg_bytes, .{}, options.strip().override(.{ .gravity_x = 1.0, .color_text = opts.color_text }));
        labelEx(@src(), "{s}", .{label_str}, .{ .align_x = 0.5 }, options.strip().override(.{ .expand = .both }));
    }

    const click = bw.clicked();

    bw.drawFocus();

    bw.deinit();
    return click;
}

pub var slider_defaults: Options = .{
    .padding = Rect.all(2),
    .min_size_content = .{ .w = 20, .h = 20 },
    .name = "Slider",
    .style = .control,
};

/// returns true if fraction (0-1) was changed
///
/// `Options.color_accent` overrides the color of the left side of the slider
pub fn slider(src: std.builtin.SourceLocation, dir: enums.Direction, fraction: *f32, opts: Options) bool {
    std.debug.assert(fraction.* >= 0);
    std.debug.assert(fraction.* <= 1);

    const options = slider_defaults.override(opts);

    var b = box(src, .{ .dir = dir }, options);
    defer b.deinit();

    tabIndexSet(b.data().id, options.tab_index);

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
                var p: ?Point.Physical = null;
                if (me.action == .focus) {
                    e.handle(@src(), b.data());
                    focusWidget(b.data().id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    // capture
                    captureMouse(b.data(), e.num);
                    e.handle(@src(), b.data());
                    p = me.p;
                } else if (me.action == .release and me.button.pointer()) {
                    // stop capture
                    captureMouse(null, e.num);
                    dragEnd();
                    e.handle(@src(), b.data());
                } else if (me.action == .motion and captured(b.data().id)) {
                    // handle only if we have capture
                    e.handle(@src(), b.data());
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
                            e.handle(@src(), b.data());
                            fraction.* = @max(0, @min(1, fraction.* - 0.05));
                            ret = true;
                        },
                        .right, .up => {
                            e.handle(@src(), b.data());
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
        part.fill(options.corner_radiusGet().scale(trackrs.s, Rect.Physical), .{ .color = opts.color_accent orelse dvui.themeGet().color(.highlight, .fill), .fade = 1.0 });
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
        part.fill(options.corner_radiusGet().scale(trackrs.s, Rect.Physical), .{ .color = options.color(.fill), .fade = 1.0 });
    }

    const knobRect = switch (dir) {
        .horizontal => Rect{ .x = (br.w - knobsize) * perc, .w = knobsize, .h = knobsize },
        .vertical => Rect{ .y = (br.h - knobsize) * (1 - perc), .w = knobsize, .h = knobsize },
    };

    const fill_color: Color = if (captured(b.data().id))
        options.color(.fill_press)
    else if (hovered)
        options.color(.fill_hover)
    else
        options.color(.fill);
    var knob = BoxWidget.init(@src(), .{ .dir = .horizontal }, .{ .rect = knobRect, .padding = .{}, .margin = .{}, .background = true, .border = Rect.all(1), .corner_radius = Rect.all(100), .color_fill = fill_color });
    knob.install();
    knob.drawBackground();
    if (b.data().id == focusedWidgetId()) {
        knob.data().focusBorder();
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
    .background = true,
    // min size calculated from font
    .name = "SliderEntry",
    .style = .control,
};

pub const SliderEntryInitOptions = struct {
    value: *f32,
    min: ?f32 = null,
    max: ?f32 = null,
    interval: ?f32 = null,
    label: ?[]const u8 = null,
};

/// Combines a slider and a text entry box on key press.  Displays value on top of slider.
///
/// Returns true if value was changed.
pub fn sliderEntry(src: std.builtin.SourceLocation, comptime label_fmt: ?[]const u8, init_opts: SliderEntryInitOptions, opts: Options) bool {

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
    var b = BoxWidget.init(src, .{ .dir = .horizontal }, options);
    b.install();
    defer b.deinit();

    tabIndexSet(b.data().id, options.tab_index);

    const br = b.data().contentRect();
    const knobsize = @min(br.w, br.h);
    const rs = b.data().contentRectScale();

    var text_mode = dataGet(null, b.data().id, "_text_mode", bool) orelse false;

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
        te.install();

        if (firstFrame(te.data().id)) {
            var sel = te.textLayout.selection;
            sel.start = 0;
            sel.cursor = 0;
            sel.end = std.math.maxInt(usize);
        }

        var new_val: ?f32 = null;

        const evts = events();
        for (evts) |*e| {
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
                e.handle(@src(), b.data());
                text_mode = false;
                new_val = std.fmt.parseFloat(f32, te_buf[0..te.len]) catch null;
            }

            if (e.evt == .key and e.evt.key.action == .down and e.evt.key.code == .escape) {
                e.handle(@src(), b.data());
                text_mode = false;
                // don't set new_val, we are escaping
            }

            // don't want TextEntry to get focus
            if (e.evt == .mouse and e.evt.mouse.action == .focus) {
                e.handle(@src(), b.data());
                focusWidget(b.data().id, null, e.num);
            }

            if (!e.handled) {
                te.processEvent(e);
            }
        }

        if (b.data().id == focusedWidgetId()) {
            dvui.wantTextInput(b.data().borderRectScale().r.toNatural());
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

        te.draw();
        te.drawCursor();
        te.deinit();
    } else {

        // show slider and label
        const trackrs = b.widget().screenRectScale(.{ .x = knobsize / 2, .w = br.w - knobsize });
        const min_x = trackrs.r.x;
        const max_x = trackrs.r.x + trackrs.r.w;
        const px_scale = trackrs.s;

        const evts = events();
        for (evts) |*e| {
            if (!eventMatch(e, .{ .id = b.data().id, .r = rs.r }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    var p: ?Point.Physical = null;
                    if (me.action == .focus) {
                        e.handle(@src(), b.data());
                        focusWidget(b.data().id, null, e.num);
                    } else if (me.action == .press and me.button.pointer()) {
                        e.handle(@src(), b.data());
                        if (me.mod.matchBind("ctrl/cmd")) {
                            text_mode = true;
                            refresh(null, @src(), b.data().id);
                        } else {
                            captureMouse(b.data(), e.num);
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
                        if (me.button.touch() and dvui.dragging(me.p, null) == null) {
                            text_mode = true;
                            refresh(null, @src(), b.data().id);
                        }
                        e.handle(@src(), b.data());
                        captureMouse(null, e.num);
                        dragEnd();
                        dataRemove(null, b.data().id, "_start_x");
                        dataRemove(null, b.data().id, "_start_v");
                    } else if (me.action == .motion and captured(b.data().id)) {
                        e.handle(@src(), b.data());
                        // If this is a touch motion we need to make sure to
                        // only update the value if we are exceeding the
                        // drag threshold to prevent the value from jumping while
                        // entering text mode via a non-drag touch-tap
                        if (!me.button.touch() or dvui.dragging(me.p, null) != null) {
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
                                e.handle(@src(), b.data());
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
        }

        b.data().borderAndBackground(.{ .fill_color = if (hover) b.data().options.color(.fill_hover) else b.data().options.color(.fill) });

        // only draw handle if we have a min and max
        if (b.data().visible() and init_opts.min != null and init_opts.max != null) {
            const how_far = (init_opts.value.* - init_opts.min.?) / (init_opts.max.? - init_opts.min.?);
            const knobRect = Rect{ .x = (br.w - knobsize) * math.clamp(how_far, 0, 1), .w = knobsize, .h = knobsize };
            const knobrs = b.widget().screenRectScale(knobRect);

            knobrs.r.fill(options.corner_radiusGet().scale(knobrs.s, Rect.Physical), .{ .color = options.color(.fill_press), .fade = 1.0 });
        }

        const label_opts = options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 });
        if (init_opts.label) |l| {
            label(@src(), "{s}", .{l}, label_opts);
        } else {
            label(@src(), label_fmt orelse "{d:.3}", .{init_opts.value.*}, label_opts);
        }
    }

    if (b.data().id == focusedWidgetId()) {
        b.data().focusBorder();
    }

    dataSet(null, b.data().id, "_text_mode", text_mode);

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
pub fn sliderVector(line: std.builtin.SourceLocation, comptime fmt: []const u8, comptime num_components: u32, value: anytype, init_opts: SliderVectorInitOptions, opts: Options) bool {
    var data_arr = checkAndCastDataPtr(num_components, value);

    var any_changed = false;
    inline for (0..num_components) |i| {
        const component_opts = dvui.SliderEntryInitOptions{
            .value = &data_arr[i],
            .min = init_opts.min,
            .max = init_opts.max,
            .interval = init_opts.interval,
        };

        const component_changed = dvui.sliderEntry(line, fmt, component_opts, opts.override(.{ .id_extra = i, .expand = .both }));
        any_changed = any_changed or component_changed;
    }

    return any_changed;
}

pub var progress_defaults: Options = .{
    .padding = Rect.all(2),
    .min_size_content = .{ .w = 10, .h = 10 },
    .style = .control,
};

pub const Progress_InitOptions = struct {
    dir: enums.Direction = .horizontal,
    percent: f32,
};

/// `Options.color_accent` overrides the color of the left side of the progress bar
pub fn progress(src: std.builtin.SourceLocation, init_opts: Progress_InitOptions, opts: Options) void {
    const options = progress_defaults.override(opts);

    var b = box(src, .{ .dir = init_opts.dir }, options);
    defer b.deinit();

    const rs = b.data().contentRectScale();

    rs.r.fill(options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = options.color(.fill), .fade = 1.0 });

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
    part.fill(options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = opts.color_accent orelse dvui.themeGet().color(.highlight, .fill), .fade = 1.0 });
}

pub var checkbox_defaults: Options = .{
    .name = "Checkbox",
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(6),
};

pub fn checkbox(src: std.builtin.SourceLocation, target: *bool, label_str: ?[]const u8, opts: Options) bool {
    return checkboxEx(src, target, label_str, .{}, opts);
}

pub fn checkboxEx(src: std.builtin.SourceLocation, target: *bool, label_str: ?[]const u8, sel_opts: selection.SelectOptions, opts: Options) bool {
    const options = checkbox_defaults.override(opts);
    var ret = false;

    var bw = ButtonWidget.init(src, .{}, options.strip().override(options));

    bw.install();
    bw.processEvents();
    // don't call button drawBackground(), it wouldn't do anything anyway because we stripped the options so no border/background
    // don't call button drawFocus(), we don't want a focus ring around the label
    defer bw.deinit();

    if (bw.clicked()) {
        target.* = !target.*;
        ret = true;
        if (sel_opts.selection_info) |sel_info| {
            sel_info.add(sel_opts.selection_id, target.*, bw.data());
        }
    }

    var b = box(@src(), .{ .dir = .horizontal }, options.strip().override(.{ .expand = .both }));
    defer b.deinit();

    const check_size = options.fontGet().textHeight();
    const s = spacer(@src(), .{ .min_size_content = Size.all(check_size), .gravity_y = 0.5 });

    const rs = s.borderRectScale();

    if (bw.data().visible()) {
        checkmark(target.*, bw.focused(), rs, bw.pressed(), bw.hovered(), options);
    }

    if (label_str) |str| {
        _ = spacer(@src(), .{ .min_size_content = .width(checkbox_defaults.paddingGet().w) });
        labelNoFmt(@src(), str, .{}, options.strip().override(.{ .gravity_y = 0.5 }));
    }

    return ret;
}

pub fn checkmark(checked: bool, focused: bool, rs: RectScale, pressed: bool, hovered: bool, opts: Options) void {
    const cornerRad = opts.corner_radiusGet().scale(rs.s, Rect.Physical);
    rs.r.fill(cornerRad, .{ .color = opts.color(.border), .fade = 1.0 });

    if (focused) {
        rs.r.stroke(cornerRad, .{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus });
    }

    var fill: Options.ColorAsk = .fill;
    if (pressed) {
        fill = .fill_press;
    } else if (hovered) {
        fill = .fill_hover;
    }

    var options = opts;
    if (checked) {
        options.style = .highlight;
        rs.r.insetAll(0.5 * rs.s).fill(cornerRad, .{ .color = options.color(fill), .fade = 1.0 });
    } else {
        rs.r.insetAll(rs.s).fill(cornerRad, .{ .color = options.color(fill), .fade = 1.0 });
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

        const path: Path = .{ .points = &.{
            .{ .x = x - third, .y = y - third },
            .{ .x = x, .y = y },
            .{ .x = x + third * 2, .y = y - third * 2 },
        } };
        path.stroke(.{ .thickness = thick, .color = options.color(.text), .endcap_style = .square });
    }
}

pub var radio_defaults: Options = .{
    .name = "Radio",
    .corner_radius = dvui.Rect.all(2),
    .padding = Rect.all(6),
};

pub fn radio(src: std.builtin.SourceLocation, active: bool, label_str: ?[]const u8, opts: Options) bool {
    const options = radio_defaults.override(opts);
    var ret = false;

    var bw = ButtonWidget.init(src, .{}, options.strip().override(options));

    bw.install();
    bw.processEvents();
    // don't call button drawBackground(), it wouldn't do anything anyway because we stripped the options so no border/background
    // don't call button drawFocus(), we don't want a focus ring around the label
    defer bw.deinit();

    if (bw.clicked()) {
        ret = true;
    }

    var b = box(@src(), .{ .dir = .horizontal }, options.strip().override(.{ .expand = .both }));
    defer b.deinit();

    const radio_size = options.fontGet().textHeight();
    const s = spacer(@src(), .{ .min_size_content = Size.all(radio_size), .gravity_y = 0.5 });

    const rs = s.borderRectScale();

    if (bw.data().visible()) {
        radioCircle(active or bw.clicked(), bw.focused(), rs, bw.pressed(), bw.hovered(), options);
    }

    if (label_str) |str| {
        _ = spacer(@src(), .{ .min_size_content = .width(radio_defaults.paddingGet().w) });
        labelNoFmt(@src(), str, .{}, options.strip().override(.{ .gravity_y = 0.5 }));
    }

    return ret;
}

pub fn radioCircle(active: bool, focused: bool, rs: RectScale, pressed: bool, hovered: bool, opts: Options) void {
    const cornerRad = Rect.Physical.all(1000);
    const r = rs.r;
    r.fill(cornerRad, .{ .color = opts.color(.border), .fade = 1.0 });

    if (focused) {
        r.stroke(cornerRad, .{ .thickness = 2 * rs.s, .color = dvui.themeGet().focus });
    }

    var fill: Options.ColorAsk = .fill;
    if (pressed) {
        fill = .fill_press;
    } else if (hovered) {
        fill = .fill_hover;
    }

    var options = opts;
    if (active) {
        options.style = .highlight;
        r.insetAll(0.5 * rs.s).fill(cornerRad, .{ .color = options.color(fill), .fade = 1.0 });
    } else {
        r.insetAll(rs.s).fill(cornerRad, .{ .color = opts.color(fill), .fade = 1.0 });
    }

    if (active) {
        const thick = @max(1.0, r.w / 6);

        Path.stroke(.{ .points = &.{r.center()} }, .{ .thickness = thick, .color = options.color(.text) });
    }
}

/// The returned slice is guaranteed to be valid utf8. If the passed in slice
/// already was valid, the same slice will be returned. Otherwise, a new slice
/// will be allocated.
///
/// ```zig
/// const some_text = "This is some maybe utf8 text";
/// const utf8_text = try toUtf8(alloc, some_text);
/// // Detect if the text needs to be freed by checking the
/// defer if (utf8_text.ptr != some_text.ptr) alloc.free(utf8_text);
/// ```
pub fn toUtf8(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.unicode.utf8ValidateSlice(text)) return text;
    // Give some reasonable extra space for replacement bytes without the need to reallocate
    const replacements_before_realloc = 100;
    // We use array list directly to avoid `std.fmt.count` going over the string twice
    var out = try std.ArrayList(u8).initCapacity(allocator, text.len + replacements_before_realloc);
    const writer = out.writer();
    try std.unicode.fmtUtf8(text).format(undefined, undefined, writer);
    return out.toOwnedSlice();
}

test toUtf8 {
    const alloc = std.testing.allocator;
    const some_text = "This is some maybe utf8 text";
    const utf8_text = try toUtf8(alloc, some_text);
    // Detect if the text needs to be freed by checking the
    defer if (utf8_text.ptr != some_text.ptr) alloc.free(utf8_text);
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

pub fn textEntry(src: std.builtin.SourceLocation, init_opts: TextEntryWidget.InitOptions, opts: Options) *TextEntryWidget {
    var ret = widgetAlloc(TextEntryWidget);
    ret.* = TextEntryWidget.init(src, init_opts, opts);
    ret.install();
    // can install corner widgets here
    //_ = dvui.button(@src(), "upright", .{}, .{ .gravity_x = 1.0 });
    ret.processEvents();
    ret.draw();
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

pub fn textEntryNumber(src: std.builtin.SourceLocation, comptime T: type, init_opts: TextEntryNumberInitOptions(T), opts: Options) TextEntryNumberResult(T) {
    const base_filter = "1234567890";
    const filter = switch (@typeInfo(T)) {
        .int => |int| switch (int.signedness) {
            .signed => base_filter ++ "+-",
            .unsigned => base_filter ++ "+",
        },
        .float => base_filter ++ "+-.e",
        else => unreachable,
    };

    // @typeName is needed so that the id changes with the type for `data...` functions
    // https://github.com/david-vanderson/dvui/issues/502
    const id = dvui.parentGet().extendId(src, opts.idExtra()).update(@typeName(T));

    const buffer = dataGetSliceDefault(null, id, "buffer", []u8, &[_]u8{0} ** 32);

    //initialize with input number
    if (init_opts.value) |num| {
        const old_value = dataGet(null, id, "value", T);
        if (old_value == null or old_value.? != num.*) {
            dataSet(null, id, "value", num.*);
            @memset(buffer, 0); // clear out anything that was there before
            _ = std.fmt.bufPrint(buffer, "{d}", .{num.*}) catch unreachable;
        }
    }

    var te = TextEntryWidget.init(src, .{ .text = .{ .buffer = buffer } }, opts);
    te.install();
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

    te.draw();

    if (result.value != .Valid and (init_opts.value != null or result.value != .Empty)) {
        const rs = te.data().borderRectScale();
        rs.r.outsetAll(1).stroke(te.data().options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .thickness = 3 * rs.s, .color = dvui.themeGet().err.fill orelse .red, .after = true });
    }

    // display min/max
    if (te.getText().len == 0 and init_opts.show_min_max) {
        var minmax_buffer: [64]u8 = undefined;
        var minmax_text: []const u8 = "";
        if (init_opts.min != null and init_opts.max != null) {
            minmax_text = std.fmt.bufPrint(&minmax_buffer, "(min: {d}, max: {d})", .{ init_opts.min.?, init_opts.max.? }) catch unreachable;
        } else if (init_opts.min != null) {
            minmax_text = std.fmt.bufPrint(&minmax_buffer, "(min: {d})", .{init_opts.min.?}) catch unreachable;
        } else if (init_opts.max != null) {
            minmax_text = std.fmt.bufPrint(&minmax_buffer, "(max: {d})", .{init_opts.max.?}) catch unreachable;
        }
        te.textLayout.addText(minmax_text, .{ .color_text = opts.color(.fill_hover) });
    }

    te.deinit();

    return result;
}

test "textEntryNumber type swap issue #502" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const Temp = struct {
        const Types = enum { u8, u16, i16, f32, f16 };
        var cur_type: Types = .u8;
        fn frame() !dvui.App.Result {
            switch (cur_type) {
                inline else => |comp_t| {
                    const T = switch (comp_t) {
                        .u8 => u8,
                        .u16 => u16,
                        .i16 => i16,
                        .f32 => f32,
                        .f16 => f16,
                    };
                    var val: T = 0;
                    _ = dvui.textEntryNumber(@src(), T, .{ .value = &val }, .{});
                },
            }
            return .ok;
        }
    };

    try dvui.testing.settle(Temp.frame);
    for (std.meta.tags(Temp.Types)) |type_tag| {
        Temp.cur_type = type_tag;
        _ = try dvui.testing.step(Temp.frame);
    }
}

pub const TextEntryColorInitOptions = struct {
    value: ?*Color = null,
    placeholder: []const u8 = "#ff00ff",
    /// If this is true, the alpha with be taken from the last hex value,
    /// if it is included in the input
    allow_alpha: bool = true,
};

pub const TextEntryColorResult = struct {
    value: union(enum) {
        Valid: Color,
        Invalid: enum {
            non_hex_value,
            alpha_passed_when_not_allowed,
        },
        Empty: void,
    } = .{ .Invalid = .non_hex_value },

    /// True if given a value pointer and wrote a valid value back to it.
    changed: bool = false,
    enter_pressed: bool = false,
};

/// A text entry for hex color codes. Supports the same formats as `Color.fromHex`
pub fn textEntryColor(src: std.builtin.SourceLocation, init_opts: TextEntryColorInitOptions, opts: Options) TextEntryColorResult {
    const defaults = Options{ .name = "textEntryColor" };

    var options = defaults.override(opts);
    if (options.min_size_content == null) {
        options = options.override(.{ .min_size_content = opts.fontGet().textSize(if (init_opts.allow_alpha) "#DDDDDDDD" else "#DDDDDD") });
    }

    const id = dvui.parentGet().extendId(src, opts.idExtra());

    const buffer = dataGetSliceDefault(null, id, "buffer", []u8, &[_]u8{0} ** 9);

    var te = TextEntryWidget.init(src, .{ .text = .{ .buffer = buffer }, .placeholder = init_opts.placeholder }, options);
    te.install();

    //initialize with input number
    if (init_opts.value) |v| {
        const old_value = dataGet(null, id, "value", Color);
        if (old_value == null or
            old_value.?.r != v.r or
            old_value.?.g != v.g or
            old_value.?.b != v.b or
            old_value.?.a != v.a)
        {
            dataSet(null, id, "value", v.*);
            @memset(buffer, 0); // clear out anything that was there before
            if (init_opts.allow_alpha and v.a != 0xff) {
                _ = std.fmt.bufPrint(buffer, "#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ v.r, v.g, v.b, v.a }) catch unreachable;
                te.len = 9;
            } else {
                te.textSet(&(v.toHexString()), false);
            }
        }
    }

    te.processEvents();
    // filter before drawing
    te.filterIn(std.fmt.hex_charset ++ "ABCDEF" ++ "#");

    var result: TextEntryColorResult = .{ .enter_pressed = te.enter_pressed };

    // validation
    const text = te.getText();
    const color: ?Color = Color.tryFromHex(text) catch null;

    //determine error if any
    if (text.len == 0 and color == null) {
        result.value = .Empty;
    } else if (color == null) {
        result.value = .{ .Invalid = .non_hex_value };
    } else if (!init_opts.allow_alpha and color.?.a != 0xFF) {
        result.value = .{ .Invalid = .alpha_passed_when_not_allowed };
    } else {
        result.value = .{ .Valid = color.? };
        if (init_opts.value) |v| {
            if ((te.enter_pressed or te.text_changed) and
                (color.?.r != v.r or
                    color.?.g != v.g or
                    color.?.b != v.b or
                    color.?.a != v.a))
            {
                dataSet(null, id, "value", color.?);
                v.* = color.?;
                result.changed = true;
            }
        }
    }

    if (init_opts.value != null and result.value == .Empty and focusedWidgetId() != te.data().id) {
        // If the text entry is empty and we loose focus,
        // reset the hex value by invalidating the stored previous value
        dataRemove(null, id, "value");
        refresh(null, @src(), id);
    }

    te.draw();

    if (result.value != .Valid and (init_opts.value != null or result.value != .Empty)) {
        const rs = te.data().borderRectScale();
        rs.r.outsetAll(1).stroke(te.data().options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .thickness = 3 * rs.s, .color = dvui.themeGet().err.fill orelse .red, .after = true });
    }

    te.deinit();

    return result;
}

pub const ColorPickerInitOptions = struct {
    hsv: *Color.HSV,
    dir: enums.Direction = .horizontal,
    sliders: enum { rgb, hsv } = .rgb,
    alpha: bool = false,
    /// Shows a `textEntryColor`
    hex_text_entry: bool = true,
};

/// A photoshop style color picker
///
/// Returns true of the color was changed
pub fn colorPicker(src: std.builtin.SourceLocation, init_opts: ColorPickerInitOptions, opts: Options) bool {
    var picker = ColorPickerWidget.init(src, .{ .dir = init_opts.dir, .hsv = init_opts.hsv }, opts);
    picker.install();
    defer picker.deinit();

    var changed = picker.color_changed;
    var rgb = init_opts.hsv.toColor();

    var side_box = dvui.box(@src(), .{}, .{});
    defer side_box.deinit();

    const slider_expand = Options.Expand.fromDirection(.horizontal);
    switch (init_opts.sliders) {
        .rgb => {
            var r = @as(f32, @floatFromInt(rgb.r));
            var g = @as(f32, @floatFromInt(rgb.g));
            var b = @as(f32, @floatFromInt(rgb.b));
            var a = @as(f32, @floatFromInt(rgb.a));

            var slider_changed = false;
            if (dvui.sliderEntry(@src(), "R: {d:0.0}", .{ .value = &r, .min = 0, .max = 255, .interval = 1 }, .{ .expand = slider_expand })) {
                slider_changed = true;
            }
            if (dvui.sliderEntry(@src(), "G: {d:0.0}", .{ .value = &g, .min = 0, .max = 255, .interval = 1 }, .{ .expand = slider_expand })) {
                slider_changed = true;
            }
            if (dvui.sliderEntry(@src(), "B: {d:0.0}", .{ .value = &b, .min = 0, .max = 255, .interval = 1 }, .{ .expand = slider_expand })) {
                slider_changed = true;
            }
            if (init_opts.alpha and dvui.sliderEntry(@src(), "A: {d:0.0}", .{ .value = &a, .min = 0, .max = 255, .interval = 1 }, .{ .expand = slider_expand })) {
                slider_changed = true;
            }
            if (slider_changed) {
                init_opts.hsv.* = .fromColor(.{ .r = @intFromFloat(r), .g = @intFromFloat(g), .b = @intFromFloat(b), .a = @intFromFloat(a) });
                changed = true;
            }
        },
        .hsv => {
            if (dvui.sliderEntry(@src(), "H: {d:0.0}", .{ .value = &init_opts.hsv.h, .min = 0, .max = 359.99, .interval = 1 }, .{ .expand = slider_expand })) {
                changed = true;
            }
            if (dvui.sliderEntry(@src(), "S: {d:0.2}", .{ .value = &init_opts.hsv.s, .min = 0, .max = 1, .interval = 0.01 }, .{ .expand = slider_expand })) {
                changed = true;
            }
            if (dvui.sliderEntry(@src(), "V: {d:0.2}", .{ .value = &init_opts.hsv.v, .min = 0, .max = 1, .interval = 0.01 }, .{ .expand = slider_expand })) {
                changed = true;
            }
            if (init_opts.alpha and dvui.sliderEntry(@src(), "A: {d:0.2}", .{ .value = &init_opts.hsv.a, .min = 0, .max = 1, .interval = 0.01 }, .{ .expand = slider_expand })) {
                changed = true;
            }
        },
    }

    if (init_opts.hex_text_entry) {
        const res = textEntryColor(@src(), .{ .allow_alpha = init_opts.alpha, .value = &rgb }, .{ .expand = slider_expand });
        if (res.changed) {
            init_opts.hsv.* = .fromColor(rgb);
            changed = true;
        }
    }

    return changed;
}

pub const renderTextOptions = struct {
    font: Font,
    text: []const u8,
    rs: RectScale,
    color: Color,
    background_color: ?Color = null,
    sel_start: ?usize = null,
    sel_end: ?usize = null,
    sel_color: ?Color = null,
    debug: bool = false,
};

/// Only renders a single line of text
///
/// Selection will be colored with the current themes accent color,
/// with the text color being set to the themes fill color.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderText(opts: renderTextOptions) Backend.GenericError!void {
    if (opts.rs.s == 0) return;
    if (opts.text.len == 0) return;
    if (clipGet().intersect(opts.rs.r).empty()) return;

    var cw = currentWindow();
    const utf8_text = try toUtf8(cw.lifo(), opts.text);
    defer if (opts.text.ptr != utf8_text.ptr) cw.lifo().free(utf8_text);

    if (!cw.render_target.rendering) {
        var opts_copy = opts;
        opts_copy.text = try cw.arena().dupe(u8, utf8_text);
        cw.addRenderCommand(.{ .text = opts_copy }, false);
        return;
    }

    const target_size = opts.font.size * opts.rs.s;
    const sized_font = opts.font.resize(target_size);

    // might get a slightly smaller font
    var fce = try fontCacheGet(sized_font);

    // this must be synced with Font.textSizeEx()
    const target_fraction = if (cw.snap_to_pixels) 1.0 else target_size / fce.height;

    // make sure the cache has all the glyphs we need
    var utf8it = std.unicode.Utf8View.initUnchecked(utf8_text).iterator();
    while (utf8it.nextCodepoint()) |codepoint| {
        _ = try fce.glyphInfoGetOrReplacement(codepoint);
    }

    // Generate new texture atlas if needed to update glyph uv coords
    const texture_atlas = fce.getTextureAtlas() catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => {
            log.err("Could not get texture atlas for font {}, text area marked in magenta, to display '{s}'", .{ opts.font.id, opts.text });
            opts.rs.r.fill(.{}, .{ .color = .magenta });
            return;
        },
    };

    // Over allocate the internal buffers assuming each byte is a character
    var builder = try Triangles.Builder.init(cw.lifo(), 4 * utf8_text.len, 6 * utf8_text.len);
    defer builder.deinit(cw.lifo());

    const col: Color.PMA = .fromColor(opts.color.opacity(cw.alpha));

    const x_start: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.x) else opts.rs.r.x;
    var x = x_start;
    var max_x = x_start;
    const y: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.y) else opts.rs.r.y;

    if (opts.debug) {
        log.debug("renderText x {d} y {d}\n", .{ x, y });
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
    utf8it = std.unicode.Utf8View.initUnchecked(utf8_text).iterator();
    var last_codepoint: u32 = 0;
    var last_glyph_index: u32 = 0;
    while (utf8it.nextCodepoint()) |codepoint| {
        const gi = try fce.glyphInfoGetOrReplacement(codepoint);

        // kerning
        if (last_codepoint != 0) {
            if (useFreeType) {
                if (last_glyph_index == 0) last_glyph_index = c.FT_Get_Char_Index(fce.face, last_codepoint);
                const glyph_index: u32 = c.FT_Get_Char_Index(fce.face, codepoint);
                var kern: c.FT_Vector = undefined;
                FontCacheEntry.intToError(c.FT_Get_Kerning(fce.face, last_glyph_index, glyph_index, c.FT_KERNING_DEFAULT, &kern)) catch |err| {
                    log.warn("renderText freetype error {!} trying to FT_Get_Kerning font {s} codepoints {d} {d}\n", .{ err, fce.name, last_codepoint, codepoint });
                    // Set fallback kern and continue to the best of out ability
                    kern.x = 0;
                    kern.y = 0;
                    // return FontError.fontError;
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
                log.debug(" - x {d} y {d}", .{ v.pos.x, v.pos.y });
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
            .fill(.{}, .{ .color = opts.sel_color orelse themeGet().focus, .fade = 0 });
    }

    try renderTriangles(builder.build_unowned(), texture_atlas);
}

/// Create a texture that can be rendered with `renderTexture`.
///
/// Remember to destroy the texture at some point, see `textureDestroyLater`.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn textureCreate(pixels: []const Color.PMA, width: u32, height: u32, interpolation: enums.TextureInterpolation) Backend.TextureError!Texture {
    if (pixels.len != width * height) {
        log.err("Texture was created with an incorrect amount of pixels, expected {d} but got {d} (w: {d}, h: {d})", .{ pixels.len, width * height, width, height });
    }
    return currentWindow().backend.textureCreate(@ptrCast(pixels.ptr), width, height, interpolation);
}

/// Update a texture that was created with `textureCreate`.
///
/// If the backend does not support updating textures, it will be destroyed and
/// recreated, changing the pointer inside tex.
///
/// Only valid between `Window.begin` and `Window.end`.
pub fn textureUpdate(tex: *Texture, pma: []const dvui.Color.PMA, interpolation: enums.TextureInterpolation) !void {
    if (pma.len != tex.width * tex.height) @panic("Texture size and supplied Content did not match");
    currentWindow().backend.textureUpdate(tex.*, @ptrCast(pma.ptr)) catch |err| {
        // texture update not supported by backend, destroy and create texture
        if (err == Backend.TextureError.NotImplemented) {
            const new_tex = try textureCreate(pma, tex.width, tex.height, interpolation);
            textureDestroyLater(tex.*);
            tex.* = new_tex;
        } else {
            return err;
        }
    };
}

/// Create a texture that can be rendered with `renderTexture` and drawn to
/// with `renderTarget`.  Starts transparent (all zero).
///
/// Remember to destroy the texture at some point, see `textureDestroyLater`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureCreateTarget(width: u32, height: u32, interpolation: enums.TextureInterpolation) Backend.TextureError!TextureTarget {
    return try currentWindow().backend.textureCreateTarget(width, height, interpolation);
}

/// Read pixels from texture created with `textureCreateTarget`.
///
/// Returns pixels allocated by arena.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureReadTarget(arena: std.mem.Allocator, texture: TextureTarget) Backend.TextureError![]Color.PMA {
    const size: usize = texture.width * texture.height * @sizeOf(Color.PMA);
    const pixels = try arena.alloc(u8, size);
    errdefer arena.free(pixels);

    try currentWindow().backend.textureReadTarget(texture, pixels.ptr);

    return @ptrCast(pixels);
}

/// Convert a target texture to a normal texture.  target is destroyed.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureFromTarget(target: TextureTarget) Backend.TextureError!Texture {
    return currentWindow().backend.textureFromTarget(target);
}

/// Destroy a texture created with `textureCreate` at the end of the frame.
///
/// While `Backend.textureDestroy` immediately destroys the texture, this
/// function deferres the destruction until the end of the frame, so it is safe
/// to use even in a subwindow where rendering is deferred.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn textureDestroyLater(texture: Texture) void {
    const cw = currentWindow();
    cw.texture_trash.append(cw.arena(), texture) catch |err| {
        dvui.log.err("textureDestroyLater got {!}\n", .{err});
    };
}

pub const RenderTarget = struct {
    texture: ?TextureTarget,
    offset: Point.Physical,
    rendering: bool = true,
};

/// Change where dvui renders.  Can pass output from `textureCreateTarget` or
/// null for the screen.  Returns the previous target/offset.
///
/// offset will be subtracted from all dvui rendering, useful as the point on
/// the screen the texture will map to.
///
/// Useful for caching expensive renders or to save a render for export.  See
/// `Picture`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn renderTarget(args: RenderTarget) RenderTarget {
    var cw = currentWindow();
    const ret = cw.render_target;
    cw.backend.renderTarget(args.texture) catch |err| {
        // TODO: This might be unrecoverable? Or brake rendering too badly?
        logError(@src(), err, "Failed to set render target", .{});
        return ret;
    };
    cw.render_target = args;
    return ret;
}

pub const RenderTextureOptions = struct {
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
pub fn renderTexture(tex: Texture, rs: RectScale, opts: RenderTextureOptions) Backend.GenericError!void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    var cw = currentWindow();

    if (!cw.render_target.rendering) {
        cw.addRenderCommand(.{ .texture = .{ .tex = tex, .rs = rs, .opts = opts } }, false);
        return;
    }

    var path: Path.Builder = .init(dvui.currentWindow().lifo());
    defer path.deinit();

    path.addRect(rs.r, opts.corner_radius.scale(rs.s, Rect.Physical));

    var triangles = try path.build().fillConvexTriangles(cw.lifo(), .{ .color = opts.colormod.opacity(cw.alpha), .fade = opts.fade });
    defer triangles.deinit(cw.lifo());

    triangles.uvFromRectuv(rs.r, opts.uv);
    triangles.rotate(rs.r.center(), opts.rotation);

    if (opts.background_color) |bg_col| {
        var back_tri = try triangles.dupe(cw.lifo());
        defer back_tri.deinit(cw.lifo());

        back_tri.color(bg_col);
        try renderTriangles(back_tri, null);
    }

    try renderTriangles(triangles, tex);
}

/// Only valid between `Window.begin`and `Window.end`.
pub fn renderIcon(name: []const u8, tvg_bytes: []const u8, rs: RectScale, opts: RenderTextureOptions, icon_opts: IconRenderOptions) Backend.GenericError!void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;

    // Ask for an integer size icon, then render it to fit rs
    const target_size = rs.r.h;
    const ask_height = @ceil(target_size);

    var h = fnv.init();
    h.update(std.mem.asBytes(&tvg_bytes.ptr));
    h.update(std.mem.asBytes(&ask_height));
    h.update(std.mem.asBytes(&icon_opts));
    const hash = h.final();

    const texture = textureGetCached(hash) orelse blk: {
        const texture = Texture.fromTvgFile(name, tvg_bytes, @intFromFloat(ask_height), icon_opts) catch |err| {
            logError(@src(), err, "Could not create texture from tvg file \"{s}\"", .{name});
            return;
        };
        textureAddToCache(hash, texture);
        break :blk texture;
    };

    try renderTexture(texture, rs, opts);
}

/// Only valid between `Window.begin`and `Window.end`.
pub fn renderImage(source: ImageSource, rs: RectScale, opts: RenderTextureOptions) (Backend.TextureError || StbImageError)!void {
    if (rs.s == 0) return;
    if (clipGet().intersect(rs.r).empty()) return;
    try renderTexture(try source.getTexture(), rs, opts);
}

/// Captures dvui drawing to part of the screen in a `Texture`.
pub const Picture = struct {
    r: Rect.Physical, // pixels captured
    texture: dvui.TextureTarget,
    target: dvui.RenderTarget,

    /// Begin recording drawing to the physical pixels in rect (enlarged to pixel boundaries).
    ///
    /// Returns null in case of failure (e.g. if backend does not support texture targets, if the passed rect is empty ...).
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn start(rect: Rect.Physical) ?Picture {
        if (rect.empty()) {
            log.err("Picture.start() was called with an empty rect", .{});
            return null;
        }

        var r = rect;
        // enlarge texture to pixels boundaries
        const x_start = @floor(r.x);
        const x_end = @ceil(r.x + r.w);
        r.x = x_start;
        r.w = @round(x_end - x_start);

        const y_start = @floor(r.y);
        const y_end = @ceil(r.y + r.h);
        r.y = y_start;
        r.h = @round(y_end - y_start);

        const texture = dvui.textureCreateTarget(@intFromFloat(r.w), @intFromFloat(r.h), .linear) catch return null;
        const target = dvui.renderTarget(.{ .texture = texture, .offset = r.topLeft() });

        return .{
            .r = r,
            .texture = texture,
            .target = target,
        };
    }

    /// Stop recording.
    pub fn stop(self: *Picture) void {
        _ = dvui.renderTarget(self.target);
    }

    /// Encode texture as png.  Call after `stop` before `deinit`.
    pub fn png(self: *Picture, allocator: std.mem.Allocator) Backend.TextureError![]u8 {
        const pma_pixels = try dvui.textureReadTarget(allocator, self.texture);
        const pixels = Color.PMA.sliceToRGBA(pma_pixels);
        defer allocator.free(pixels);

        return try dvui.pngEncode(allocator, pixels, self.texture.width, self.texture.height, .{});
    }

    /// Draw recorded texture and destroy it.
    pub fn deinit(self: *Picture) void {
        widgetFree(self);
        // Ignore errors as drawing is not critical to Pictures function
        const texture = dvui.textureFromTarget(self.texture) catch return; // destroys self.texture
        dvui.textureDestroyLater(texture);
        dvui.renderTexture(texture, .{ .r = self.r }, .{}) catch {};
        self.* = undefined;
    }
};

pub const pngEncodeOptions = struct {
    /// Physical size of image, pixels per meter added to png pHYs chunk.
    /// 0 => don't write the pHYs chunk
    /// null => dvui will use 72 dpi (2834.64 px/m) times `windowNaturalScale`
    resolution: ?u32 = null,
};

/// Make a png encoded image from RGBA pixels.
///
/// Gives bytes of a png file (allocated by arena).
pub fn pngEncode(arena: std.mem.Allocator, pixels: []u8, width: u32, height: u32, opts: pngEncodeOptions) std.mem.Allocator.Error![]u8 {
    var len: c_int = undefined;
    const png_bytes = c.stbi_write_png_to_mem(pixels.ptr, @intCast(width * 4), @intCast(width), @intCast(height), 4, &len);
    defer {
        if (wasm) {
            backend.dvui_c_free(png_bytes);
        } else {
            c.free(png_bytes);
        }
    }

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

pub fn plot(src: std.builtin.SourceLocation, plot_opts: PlotWidget.InitOptions, opts: Options) *PlotWidget {
    var ret = widgetAlloc(PlotWidget);
    ret.* = PlotWidget.init(src, plot_opts, opts);
    ret.install();
    return ret;
}

/// `Options.color_accent` overrides the color of the plot line
pub fn plotXY(src: std.builtin.SourceLocation, plot_opts: PlotWidget.InitOptions, thick: f32, xs: []const f64, ys: []const f64, opts: Options) void {
    const defaults: Options = .{ .padding = .{} };
    var p = dvui.plot(src, plot_opts, defaults.override(opts));

    var s1 = p.line();
    for (xs, ys) |x, y| {
        s1.point(x, y);
    }

    s1.stroke(thick, opts.color_accent orelse dvui.themeGet().color(.highlight, .fill));

    s1.deinit();
    p.deinit();
}

/// Helper to layout widgets stacked vertically or horizontally.
///
/// If there is a widget expanded in that direction, it takes up the remaining
/// space and it is an error to have any widget after.
///
/// Widgets with .gravity_y (.gravity_x) not zero might overlap other widgets.
pub const BasicLayout = struct {
    dir: enums.Direction = .vertical,
    pos: f32 = 0,
    seen_expanded: bool = false,
    min_size_children: Size = .{},

    pub fn rectFor(self: *BasicLayout, contentRect: Rect, id: Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
        if (self.seen_expanded) {
            // A single vertically expanded child can take the rest of the
            // space, but it should be the last (usually only) child.
            //
            // Here we have a child after an expanded one, so it will get no space.
            //
            // If you want that to work, wrap the children in a vertical box.
            const cw = dvui.currentWindow();
            cw.debug.widget_id = id;
            dvui.log.err("{s}:{d} rectFor() got child {x} after expanded child", .{ @src().file, @src().line, id });
            var wd = dvui.parentGet().data();
            while (true) : (wd = wd.parent.data()) {
                dvui.log.err("  {s}:{d} {s} {x}{s}", .{
                    wd.src.file,
                    wd.src.line,
                    wd.options.name orelse "???",
                    wd.id,
                    if (wd.id == cw.data().id) "\n" else "",
                });
                if (wd.id == cw.data().id) {
                    break;
                }
            }
        }

        var r = contentRect;

        switch (self.dir) {
            .vertical => {
                if (e.isVertical()) {
                    self.seen_expanded = true;
                }
                r.y += self.pos;
                r.h = @max(0, r.h - self.pos);
            },
            .horizontal => {
                if (e.isHorizontal()) {
                    self.seen_expanded = true;
                }
                r.x += self.pos;
                r.w = @max(0, r.w - self.pos);
            },
        }

        const ret = dvui.placeIn(r, min_size, e, g);

        switch (self.dir) {
            .vertical => self.pos += ret.h,
            .horizontal => self.pos += ret.w,
        }

        return ret;
    }

    pub fn minSizeForChild(self: *BasicLayout, s: Size) Size {
        switch (self.dir) {
            .vertical => {
                // add heights
                self.min_size_children.h += s.h;

                // max of widths
                self.min_size_children.w = @max(self.min_size_children.w, s.w);
            },
            .horizontal => {
                // add widths
                self.min_size_children.w += s.w;

                // max of heights
                self.min_size_children.h = @max(self.min_size_children.h, s.h);
            },
        }

        return self.min_size_children;
    }
};

test {
    //std.debug.print("DVUI test\n", .{});
    std.testing.refAllDecls(@This());
}
