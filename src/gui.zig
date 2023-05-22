const builtin = @import("builtin");
const std = @import("std");
const math = std.math;
const tvg = @import("tinyvg/tinyvg.zig");
const fnv = std.hash.Fnv1a_32;
pub const icons = @import("icons.zig");
pub const fonts = @import("fonts.zig");
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

const log = std.log.scoped(.gui);
const gui = @This();

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

pub const Theme = struct {
    pub const ColorStyle = enum {
        content, // default
        accent,
        control,
        window,
        success,
        err,
    };

    pub const StyleColors = struct {
        // used to show focus
        accent: ?Color = null,

        text: ?Color = null,

        // background color contrasting the most with the text color, used when
        // displaying lots of text
        fill: ?Color = null,

        border: ?Color = null,
        hover: ?Color = null,
        press: ?Color = null,
    };

    name: []const u8,
    dark: bool,

    alpha: f32 = 1.0,

    // Options.color_style selects between these

    // content is default and must have all fields non-null
    style_content: StyleColors,

    // any null fields in these will use .content fields
    style_accent: StyleColors,
    style_control: StyleColors,
    style_window: StyleColors,
    style_success: StyleColors,
    style_err: StyleColors,

    font_body: Font,
    font_heading: Font,
    font_caption: Font,
    font_caption_heading: Font,
    font_title: Font,
    font_title_1: Font,
    font_title_2: Font,
    font_title_3: Font,
    font_title_4: Font,
};

pub const Adwaita = struct {
    const accent = Color{ .r = 0x35, .g = 0x84, .b = 0xe4 };
    const success = Color{ .r = 0x2e, .g = 0xc2, .b = 0x7e };
    const err = Color{ .r = 0xe0, .g = 0x1b, .b = 0x24 };

    pub var light = Theme{
        .name = "Adwaita",
        .dark = false,

        .font_body = Font{ .size = 11, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera },
        .font_heading = Font{ .size = 11, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_caption = Font{ .size = 9, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera },
        .font_caption_heading = Font{ .size = 9, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title = Font{ .size = 24, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera },
        .font_title_1 = Font{ .size = 20, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title_2 = Font{ .size = 17, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title_3 = Font{ .size = 15, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title_4 = Font{ .size = 13, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },

        .style_content = .{
            .accent = accent,
            .text = Color.black,
            .fill = Color.white,
            .border = Color.lerp(Color.white, 0.4, Color.black),
            .hover = Color.lerp(Color.white, 0.2, Color.black),
            .press = Color.lerp(Color.white, 0.3, Color.black),
        },

        .style_control = .{ .fill = Color{ .r = 0xe0, .g = 0xe0, .b = 0xe0 } },
        .style_window = .{ .fill = Color{ .r = 0xf0, .g = 0xf0, .b = 0xf0 } },

        .style_accent = .{
            .accent = accent.darken(0.3),
            .fill = accent,
            .text = Color.white,
            .border = Color.lerp(accent, 0.4, Color.black),
            .hover = Color.lerp(accent, 0.2, Color.black),
            .press = Color.lerp(accent, 0.3, Color.black),
        },
        .style_success = .{
            .accent = success.darken(0.3),
            .fill = success,
            .text = Color.white,
            .border = Color.lerp(success, 0.4, Color.black),
            .hover = Color.lerp(success, 0.2, Color.black),
            .press = Color.lerp(success, 0.3, Color.black),
        },
        .style_err = .{
            .accent = err.darken(0.3),
            .fill = err,
            .text = Color.white,
            .border = Color.lerp(err, 0.4, Color.black),
            .hover = Color.lerp(err, 0.2, Color.black),
            .press = Color.lerp(err, 0.3, Color.black),
        },
    };

    const dark_fill = Color{ .r = 0x1e, .g = 0x1e, .b = 0x1e };
    const dark_success = Color{ .r = 0x26, .g = 0xa2, .b = 0x69 };
    const dark_err = Color{ .r = 0xc0, .g = 0x1c, .b = 0x28 };

    pub var dark = Theme{
        .name = "Adwaita Dark",
        .dark = true,

        .font_body = Font{ .size = 11, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera },
        .font_heading = Font{ .size = 11, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_caption = Font{ .size = 9, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera },
        .font_caption_heading = Font{ .size = 9, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title = Font{ .size = 24, .name = "Vera", .ttf_bytes = fonts.bitstream_vera.Vera },
        .font_title_1 = Font{ .size = 20, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title_2 = Font{ .size = 17, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title_3 = Font{ .size = 15, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },
        .font_title_4 = Font{ .size = 13, .name = "VeraBd", .ttf_bytes = fonts.bitstream_vera.VeraBd },

        .style_content = .{
            .accent = accent,
            .text = Color.white,
            .fill = dark_fill,
            .border = Color.lerp(dark_fill, 0.4, Color.white),
            .hover = Color.lerp(dark_fill, 0.2, Color.white),
            .press = Color.lerp(dark_fill, 0.3, Color.white),
        },

        .style_control = .{ .fill = Color{ .r = 0x40, .g = 0x40, .b = 0x40 } },
        .style_window = .{ .fill = Color{ .r = 0x2b, .g = 0x2b, .b = 0x2b } },

        .style_accent = .{
            .accent = accent.lighten(0.3),
            .fill = accent,
            .text = Color.white,
            .border = Color.lerp(accent, 0.4, Color.white),
            .hover = Color.lerp(accent, 0.2, Color.white),
            .press = Color.lerp(accent, 0.3, Color.white),
        },
        .style_success = .{
            .accent = dark_success.lighten(0.3),
            .fill = dark_success,
            .text = Color.white,
            .border = Color.lerp(success, 0.4, Color.white),
            .hover = Color.lerp(success, 0.2, Color.white),
            .press = Color.lerp(success, 0.3, Color.white),
        },
        .style_err = .{
            .accent = dark_err.lighten(0.3),
            .fill = dark_err,
            .text = Color.white,
            .border = Color.lerp(err, 0.4, Color.white),
            .hover = Color.lerp(err, 0.2, Color.white),
            .press = Color.lerp(err, 0.3, Color.white),
        },
    };
};

pub const Options = struct {
    pub const Expand = enum {
        none,
        horizontal,
        vertical,
        both,

        pub fn horizontal(self: *const Expand) bool {
            return (self.* == .horizontal or self.* == .both);
        }

        pub fn vertical(self: *const Expand) bool {
            return (self.* == .vertical or self.* == .both);
        }
    };

    pub const Gravity = struct {
        // wraps Options.gravity_x and Options.gravity_y
        x: f32,
        y: f32,
    };

    pub const FontStyle = enum {
        body,
        heading,
        caption,
        caption_heading,
        title,
        title_1,
        title_2,
        title_3,
        title_4,
    };

    // used to adjust widget id when @src() is not enough (like in a loop)
    id_extra: ?usize = null,

    // null is normal, meaning parent picks a rect for the child widget.  If
    // non-null, child widget is choosing its own place, meaning its not being
    // placed normally.  w and h will still be expanded if expand is set.
    // Example is ScrollArea, where user code chooses widget placement. If
    // non-null, should not call rectFor or minSizeForChild.
    rect: ?Rect = null,

    // default is .none
    expand: ?Expand = null,

    // [0, 1] default is 0 (left)
    gravity_x: ?f32 = null,

    // [0, 1] default is 0 (top)
    gravity_y: ?f32 = null,

    // used to override the tab order, lower numbers first, null means highest
    // possible number, same tab_index goes in install() order
    tab_index: ?u16 = null,

    // used to override widget and theme defaults
    color_accent: ?Color = null,
    color_text: ?Color = null,
    color_fill: ?Color = null,
    color_border: ?Color = null,
    color_hover: ?Color = null,
    color_press: ?Color = null,

    // use to override font_style
    font: ?Font = null,

    // only used for icons, rotates around center, only rotates drawing
    rotation: ?f32 = null,

    // For the rest of these fields, if null, each widget uses its defaults

    // x left, y top, w right, h bottom
    margin: ?Rect = null,
    border: ?Rect = null,
    padding: ?Rect = null,

    // x topleft, y topright, w botright, h botleft
    corner_radius: ?Rect = null,

    // padding/border/margin will be added to this
    min_size_content: ?Size = null,

    // whether to fill the background
    background: ?bool = null,

    // use to pick a font from the theme
    font_style: ?FontStyle = null,

    // use to pick a color from the theme
    color_style: ?Theme.ColorStyle = null,

    pub const ColorKind = enum {
        accent,
        text,
        fill,
        border,
        hover,
        press,
    };

    pub fn color(self: *const Options, kind: ColorKind) Color {
        var ret: ?Color = switch (kind) {
            .accent => self.color_accent,
            .text => self.color_text,
            .fill => self.color_fill,
            .border => self.color_border,
            .hover => self.color_hover,
            .press => self.color_press,
        };

        // if we have a custom color, return it
        if (ret) |r| {
            return r.transparent(themeGet().alpha);
        }

        // find the colors in our style
        const cs: Theme.StyleColors = switch (self.color_style orelse .content) {
            .content => themeGet().style_content,
            .accent => themeGet().style_accent,
            .window => themeGet().style_window,
            .control => themeGet().style_control,
            .success => themeGet().style_success,
            .err => themeGet().style_err,
        };

        // return color from style or default
        switch (kind) {
            .accent => ret = cs.accent orelse themeGet().style_content.accent orelse unreachable,
            .text => ret = cs.text orelse themeGet().style_content.text orelse unreachable,
            .fill => ret = cs.fill orelse themeGet().style_content.fill orelse unreachable,
            .border => ret = cs.border orelse themeGet().style_content.border orelse unreachable,
            .hover => ret = cs.hover orelse themeGet().style_content.hover orelse unreachable,
            .press => ret = cs.press orelse themeGet().style_content.press orelse unreachable,
        }

        return (ret orelse unreachable).transparent(themeGet().alpha);
    }

    pub fn fontGet(self: *const Options) Font {
        if (self.font) |ff| {
            return ff;
        }

        return switch (self.font_style orelse .body) {
            .body => themeGet().font_body,
            .heading => themeGet().font_heading,
            .caption => themeGet().font_caption,
            .caption_heading => themeGet().font_caption_heading,
            .title => themeGet().font_title,
            .title_1 => themeGet().font_title_1,
            .title_2 => themeGet().font_title_2,
            .title_3 => themeGet().font_title_3,
            .title_4 => themeGet().font_title_4,
        };
    }

    pub fn idExtra(self: *const Options) usize {
        return self.id_extra orelse 0;
    }

    pub fn expandGet(self: *const Options) Expand {
        return self.expand orelse .none;
    }

    pub fn gravityGet(self: *const Options) Gravity {
        return .{ .x = self.gravity_x orelse 0.0, .y = self.gravity_y orelse 0.0 };
    }

    pub fn marginGet(self: *const Options) Rect {
        return self.margin orelse Rect{};
    }

    pub fn borderGet(self: *const Options) Rect {
        return self.border orelse Rect{};
    }

    pub fn backgroundGet(self: *const Options) bool {
        return self.background orelse false;
    }

    pub fn paddingGet(self: *const Options) Rect {
        return self.padding orelse Rect{};
    }

    pub fn corner_radiusGet(self: *const Options) Rect {
        return self.corner_radius orelse Rect{};
    }

    pub fn min_sizeGet(self: *const Options) Size {
        return self.min_size_contentGet().pad(self.paddingGet()).pad(self.borderGet()).pad(self.marginGet());
    }

    pub fn min_size_contentGet(self: *const Options) Size {
        return self.min_size_content orelse Size{};
    }

    pub fn rotationGet(self: *const Options) f32 {
        return self.rotation orelse 0.0;
    }

    // Used in compound widgets to strip out the styling that should only apply
    // to the outermost container widget.  For example, with a button
    // (container with label) the container uses:
    // - rect
    // - min_size_content
    // - margin
    // - border
    // - background
    // - padding
    // - corner_radius
    // - expand
    // - gravity
    // while the label uses:
    // - fonts
    // - colors
    pub fn strip(self: *const Options) Options {
        return Options{
            // reset to defaults of internal widgets
            .id_extra = null,
            .rect = null,
            .min_size_content = null,
            .expand = null,
            .gravity_x = null,
            .gravity_y = null,

            // ignore defaults of internal widgets
            .tab_index = null,
            .margin = Rect{},
            .border = Rect{},
            .padding = Rect{},
            .corner_radius = Rect{},
            .background = false,

            // keep the rest
            .color_accent = self.color_accent,
            .color_text = self.color_text,
            .color_fill = self.color_fill,
            .color_border = self.color_border,
            .color_hover = self.color_hover,
            .color_press = self.color_press,
            .font = self.font,
            .color_style = self.color_style,
            .font_style = self.font_style,
            .rotation = self.rotation,
        };
    }

    pub fn override(self: *const Options, over: Options) Options {
        var ret = self.*;

        inline for (@typeInfo(Options).Struct.fields) |f| {
            if (@field(over, f.name)) |fval| {
                @field(ret, f.name) = fval;
            }
        }

        return ret;
    }

    //pub fn format(self: *const Options, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    //    try std.fmt.format(writer, "Options{{ .background = {?}, .color_style = {?} }}", .{ self.background, self.color_style });
    //}
};

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

pub fn placeOnScreen(spawner: Rect, start: Rect) Rect {
    var r = start;
    const wr = windowRect();
    if ((r.x + r.w) > wr.w) {
        if (spawner.w == 0) {
            r.x = wr.w - r.w;
        } else {
            r.x = spawner.x - spawner.w - r.w;
        }
    }

    if ((r.y + r.h) > wr.h) {
        if (spawner.h == 0) {
            r.y = wr.h - r.h;
        }
    }

    return r;
}

pub fn frameTimeNS() i128 {
    return currentWindow().frame_time_ns;
}

pub const Font = struct {
    size: f32,
    line_skip_factor: f32 = 1.0,
    name: []const u8,
    ttf_bytes: []const u8,

    pub fn resize(self: *const Font, s: f32) Font {
        return Font{ .size = s, .name = self.name, .ttf_bytes = self.ttf_bytes };
    }

    pub fn textSize(self: *const Font, text: []const u8) !Size {
        return try self.textSizeEx(text, null, null, .before);
    }

    pub const EndMetric = enum {
        before, // end_idx stops before text goes past max_width
        nearest, // end_idx stops at start of character closest to max_width
    };

    pub fn textSizeEx(self: *const Font, text: []const u8, max_width: ?f32, end_idx: ?*usize, end_metric: EndMetric) !Size {
        // ask for a font that matches the natural display pixels so we get a more
        // accurate size

        const ss = parentGet().screenRectScale(Rect{}).s;

        const ask_size = @ceil(self.size * ss);
        const max_width_sized = (max_width orelse 1000000.0) * ss;
        const sized_font = self.resize(ask_size);
        const s = try sized_font.textSizeRaw(text, max_width_sized, end_idx, end_metric);

        // do this check after calling textSizeRaw so that end_idx is set
        if (ss == 0) return Size{};

        const target_fraction = self.size / ask_size;
        //std.debug.print("textSize size {d} for \"{s}\" {d} {}\n", .{ self.size, text, target_fraction, s.scale(target_fraction) });
        return s.scale(target_fraction);
    }

    // doesn't scale the font or max_width
    pub fn textSizeRaw(self: *const Font, text: []const u8, max_width: ?f32, end_idx: ?*usize, end_metric: EndMetric) !Size {
        const fce = try fontCacheGet(self.*);

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
            const gi = try fce.glyphInfoGet(@intCast(u32, codepoint), self.name);

            minx = math.min(minx, x + gi.minx);
            maxx = math.max(maxx, x + gi.maxx);
            maxx = math.max(maxx, x + gi.advance);

            miny = math.min(miny, gi.miny);
            maxy = math.max(maxy, gi.maxy);

            // TODO: kerning

            if (codepoint == '\n') {
                // newlines always terminate, and don't use any space
                ei += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                break;
            }

            // always include the first codepoint
            if (ei > 0 and (maxx - minx) > mwidth) {
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

    pub fn lineSkip(self: *const Font) !f32 {
        // do the same sized thing as textSizeEx so they will cache the same font
        const ss = parentGet().screenRectScale(Rect{}).s;
        if (ss == 0) return 0;

        const ask_size = @ceil(self.size * ss);
        const target_fraction = self.size / ask_size;
        const sized_font = self.resize(ask_size);

        const fce = try fontCacheGet(sized_font);
        const skip = fce.height;
        //std.debug.print("lineSkip fontsize {d} is {d}\n", .{sized_font.size, skip});
        return skip * target_fraction * self.line_skip_factor;
    }
};

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

        FontCacheEntry.intToError(c.FT_Load_Char(self.face, codepoint, @bitCast(i32, LoadFlags{ .render = false }))) catch |err| {
            std.debug.print("glyphInfoGet: freetype error {!} font {s} codepoint {d}\n", .{ err, font_name, codepoint });
            return error.freetypeError;
        };

        const m = self.face.*.glyph.*.metrics;
        const minx = @intToFloat(f32, m.horiBearingX) / 64.0;
        const miny = self.ascent - @intToFloat(f32, m.horiBearingY) / 64.0;

        const gi = GlyphInfo{
            .minx = @floor(minx),
            .maxx = @ceil(minx + @intToFloat(f32, m.width) / 64.0),
            .advance = @ceil(@intToFloat(f32, m.horiAdvance) / 64.0),
            .miny = @floor(miny),
            .maxy = @ceil(miny + @intToFloat(f32, m.height) / 64.0),
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
    args.flags = @bitCast(u32, FontCacheEntry.OpenFlags{ .memory = true });
    args.memory_base = font.ttf_bytes.ptr;
    args.memory_size = @intCast(u31, font.ttf_bytes.len);
    FontCacheEntry.intToError(c.FT_Open_Face(cw.ft2lib, &args, 0, &face)) catch |err| {
        std.debug.print("fontCacheGet: freetype error {!} trying to FT_Open_Face font {s}\n", .{ err, font.name });
        return error.freetypeError;
    };

    const pixel_size = @floatToInt(u32, font.size);
    FontCacheEntry.intToError(c.FT_Set_Pixel_Sizes(face, pixel_size, pixel_size)) catch |err| {
        std.debug.print("fontCacheGet: freetype error {!} trying to FT_Set_Pixel_Sizes font {s}\n", .{ err, font.name });
        return error.freetypeError;
    };

    const ascender = @intToFloat(f32, face.*.ascender) / 64.0;
    const ss = @intToFloat(f32, face.*.size.*.metrics.y_scale) / 0x10000;
    const ascent = ascender * ss;
    //std.debug.print("fontcache size {d} ascender {d} scale {d} ascent {d}\n", .{font.size, ascender, scale, ascent});

    // make debug texture atlas so we can see if something later goes wrong
    const size = .{ .w = 10, .h = 10 };
    var pixels = try cw.arena.alloc(u8, @floatToInt(usize, size.w * size.h) * 4);
    @memset(pixels, 255);

    const entry = FontCacheEntry{
        .face = face,
        .height = @ceil(@intToFloat(f32, face.*.size.*.metrics.height) / 64.0),
        .ascent = @ceil(ascent),
        .glyph_info = std.AutoHashMap(u32, GlyphInfo).init(cw.gpa),
        .texture_atlas = cw.backend.textureCreate(pixels, @floatToInt(u32, size.w), @floatToInt(u32, size.h)),
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

    return height * @intToFloat(f32, parser.header.width) / @intToFloat(f32, parser.header.height);
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
        @intToEnum(tvg.rendering.AntiAliasing, 2),
        tvg_bytes,
    ) catch |err| {
        std.debug.print("iconTexture: Tinyvg error {!} rendering icon {s} at height {d}\n", .{ err, name, height });
        return error.tvgError;
    };
    defer image.deinit(cw.arena);

    var pixels: []u8 = undefined;
    pixels.ptr = @ptrCast([*]u8, image.pixels.ptr);
    pixels.len = image.pixels.len * 4;

    const texture = cw.backend.textureCreate(pixels, image.width, image.height);

    //std.debug.print("created icon texture \"{s}\" ask height {d} size {d}x{d}\n", .{ name, height, image.width, image.height });

    const entry = IconCacheEntry{ .texture = texture, .size = .{ .w = @intToFloat(f32, image.width), .h = @intToFloat(f32, image.height) } };
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
    var items = cw.subwindows.items;
    for (items, 0..) |sw, i| {
        if (sw.id == subwindow_id) {
            if (sw.stay_above_parent != null) {
                std.debug.print("raiseSubwindow: tried to raise a subwindow {x} with stay_above_parent set\n", .{subwindow_id});
                return;
            }

            if (i == (items.len - 1)) {
                // already on top
                return;
            }

            // move it to the end, also move any stay_above_parent subwindows
            // directly on top of it as well
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

// Focus a widget in the focused subwindow.  If you need to focus a widget in
// an arbitrary subwindow, focus the subwindow first.
pub fn focusWidget(id: ?u32, event_num: ?u16) void {
    const cw = currentWindow();
    for (cw.subwindows.items) |*sw| {
        if (cw.focused_subwindowId == sw.id) {
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
    const maxrad = math.min(r.w, r.h) / 2;
    rad.x = math.min(rad.x, maxrad);
    rad.y = math.min(rad.y, maxrad);
    rad.w = math.min(rad.w, maxrad);
    rad.h = math.min(rad.h, maxrad);
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
    const err = 1.0;
    // angle that has err error between circle and segments
    const theta = math.acos(1.0 - math.min(rad, err) / rad);
    // make sure we never have less than 4 segments
    // so a full circle can't be less than a diamond
    const num_segments = math.max(@ceil((start - end) / theta), 4.0);
    const step = (start - end) / num_segments;

    const num = @floatToInt(u32, num_segments);
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
            try idx.append(@intCast(u32, 0));
            try idx.append(@intCast(u32, ai * 2));
            try idx.append(@intCast(u32, bi * 2));
        }

        // indexes for aa fade from inner to outer
        try idx.append(@intCast(u32, ai * 2));
        try idx.append(@intCast(u32, ai * 2 + 1));
        try idx.append(@intCast(u32, bi * 2));
        try idx.append(@intCast(u32, ai * 2 + 1));
        try idx.append(@intCast(u32, bi * 2 + 1));
        try idx.append(@intCast(u32, bi * 2));
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
                try idx.append(@intCast(u32, 0));
                try idx.append(@intCast(u32, vtx_start));
                try idx.append(@intCast(u32, vtx_start + 1));

                try idx.append(@intCast(u32, 0));
                try idx.append(@intCast(u32, 1));
                try idx.append(@intCast(u32, vtx_start));

                try idx.append(@intCast(u32, 1));
                try idx.append(@intCast(u32, vtx_start));
                try idx.append(@intCast(u32, vtx_start + 2));

                try idx.append(@intCast(u32, 1));
                try idx.append(@intCast(u32, vtx_start + 2));
                try idx.append(@intCast(u32, vtx_start + 2 + 1));
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
            try idx.append(@intCast(u32, vtx_start + bi * 4));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + ci * 4));

            try idx.append(@intCast(u32, vtx_start + bi * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + ci * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + ci * 4));

            // indexes for aa fade from inner to outer side 1
            try idx.append(@intCast(u32, vtx_start + bi * 4));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 1));
            try idx.append(@intCast(u32, vtx_start + ci * 4 + 1));

            try idx.append(@intCast(u32, vtx_start + bi * 4));
            try idx.append(@intCast(u32, vtx_start + ci * 4 + 1));
            try idx.append(@intCast(u32, vtx_start + ci * 4));

            // indexes for aa fade from inner to outer side 2
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 3));
            try idx.append(@intCast(u32, vtx_start + ci * 4 + 3));

            try idx.append(@intCast(u32, vtx_start + bi * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + ci * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + ci * 4 + 3));
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
            try idx.append(@intCast(u32, vtx_start + bi * 4));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 1));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 4));

            try idx.append(@intCast(u32, vtx_start + bi * 4 + 4));
            try idx.append(@intCast(u32, vtx_start + bi * 4));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 2));

            try idx.append(@intCast(u32, vtx_start + bi * 4 + 4));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 5));

            try idx.append(@intCast(u32, vtx_start + bi * 4 + 2));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 3));
            try idx.append(@intCast(u32, vtx_start + bi * 4 + 5));
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

pub fn dragPreStart(p: Point, cursor: Cursor, offset: Point) void {
    const cw = currentWindow();
    cw.drag_state = .prestart;
    cw.drag_pt = p;
    cw.drag_offset = offset;
    cw.cursor_dragging = cursor;
}

pub fn dragStart(p: Point, cursor: Cursor, offset: Point) void {
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

pub fn captureMouse(id: ?u32) bool {
    const cw = currentWindow();
    cw.captureID = id;
    if (id != null) {
        cw.captured_last_frame = true;
        return true;
    }
    return false;
}

pub fn captureMouseMaintain(id: u32) bool {
    const cw = currentWindow();
    if (cw.captureID == id) {
        // to maintain capture, we must be on or above the
        // top modal window
        var i = cw.subwindows.items.len;
        while (i > 0) : (i -= 1) {
            const sw = &cw.subwindows.items[i - 1];
            if (sw.id == cw.subwindow_currentId) {
                // maintaining capture
                break;
            } else if (sw.modal) {
                // found modal before we found current
                // cancel the capture, and cancel
                // any drag being done
                dragEnd();
                return false;
            }
        }

        // either our floating window is above the top modal
        // or there are no floating modal windows
        cw.captured_last_frame = true;
        return true;
    }

    return false;
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

pub fn refresh() void {
    currentWindow().refresh();
}

pub fn animationRate() f32 {
    return currentWindow().rate;
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
            std.debug.print("gui: id {x} was already used this frame (highlighting)\n", .{id});
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
/// pass a pointer to the Window you want to add the dialog to.
pub fn dataSet(win: ?*Window, id: u32, key: []const u8, data: anytype) void {
    if (win) |w| {
        // we are being called from non gui thread or outside begin()/end()
        w.dataSet(id, key, data);
    } else {
        if (current_window) |cw| {
            cw.dataSet(id, key, data);
        } else {
            @panic("dataSet: current_window was null, pass a *Window as first parameter if calling from other thread or outside window.begin()/end()");
        }
    }
}

/// Retrieve value for given key associated with id.
///
/// Can be called from any thread.
///
/// If called from non-GUI thread or outside window.begin()/end(), you must
/// pass a pointer to the Window you want to add the dialog to.
///
/// If T is a slice, returns slice of internal storage, so need to copy if
/// keeping the returned slice across frames
pub fn dataGet(win: ?*Window, id: u32, key: []const u8, comptime T: type) ?T {
    if (win) |w| {
        // we are being called from non gui thread or outside begin()/end()
        return w.dataGet(id, key, T);
    } else {
        if (current_window) |cw| {
            return cw.dataGet(id, key, T);
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

pub const EventIterator = struct {
    const Self = @This();
    id: u32,
    id_capture: u32,
    i: u32,
    r: Rect,

    pub fn init(id: u32, r: Rect, id_capture: ?u32) Self {
        return Self{ .id = id, .i = 0, .r = r, .id_capture = id_capture orelse id };
    }

    pub fn next(self: *Self) ?*Event {
        return self.nextCleanup(false);
    }

    pub fn nextCleanup(self: *Self, cleanup: bool) ?*Event {
        var evts = events();
        while (self.i < evts.len) : (self.i += 1) {
            var e: *Event = &evts[self.i];
            if (e.handled) {
                continue;
            }

            if (e.focus_windowId) |wid| {
                // focusable event
                if (cleanup) {
                    // window is catching all focus-routed events that didn't get
                    // processed (maybe the focus widget never showed up)
                    if (wid != self.id) {
                        // not the focused window
                        continue;
                    }
                } else {
                    if (e.focus_widgetId != self.id) {
                        // not the focused widget
                        continue;
                    }
                }
            }

            switch (e.evt) {
                .key => {},
                .text => {},
                .mouse => |me| {
                    const capture_id = captureMouseId();
                    if (capture_id != null and me.kind != .wheel_y) {
                        if (capture_id.? != self.id_capture) {
                            // mouse is captured by a different widget
                            continue;
                        }
                    } else {
                        if (me.floating_win != subwindowCurrentId()) {
                            // floating window is above us
                            continue;
                        }

                        if (!self.r.contains(me.p)) {
                            // mouse not in our rect
                            continue;
                        }

                        if (!clipGet().contains(me.p)) {
                            // mouse not in clip region

                            // prevents widgets that are scrolled off a
                            // scroll area from processing events
                            continue;
                        }
                    }
                },

                .close_popup => unreachable,
                .scroll_drag => unreachable,
                .scroll_to => unreachable,
            }

            self.i += 1;
            return e;
        }

        return null;
    }
};

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
        var frac = @intToFloat(f32, -a.start_time) / @intToFloat(f32, a.end_time - a.start_time);
        frac = math.max(0, math.min(1, frac));
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

    focusWidget(newId, event_num);
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

    focusWidget(newId, event_num);
}

pub const Vertex = struct {
    pos: Point,
    col: Color,
    uv: @Vector(2, f32),
};

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
        data: []u8,
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
    // 2) used to highlight the widget under the mouse (MouseEvent.Kind.position event)
    // 3) used to change the cursor (MouseEvent.Kind.position event)
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

    rate: f32 = 0,
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
    cursor_dragging: Cursor = .arrow,

    wd: WidgetData = undefined,
    rect_pixels: Rect = Rect{}, // pixels
    natural_scale: f32 = 1.0,
    next_widget_ypos: f32 = 0,

    captureID: ?u32 = null,
    captured_last_frame: bool = false,

    gpa: std.mem.Allocator = undefined,
    arena: std.mem.Allocator = undefined,
    path: std.ArrayList(Point) = undefined,
    rendering: bool = false,

    debug_window_show: bool = false,
    debug_widget_id: u32 = 0,
    debug_info_name_rect: []u8 = "",
    debug_info_src_id_extra: []u8 = "",
    debug_under_mouse: bool = false,
    debug_under_mouse_quitting: bool = false,
    debug_under_mouse_info: []u8 = "",

    pub fn init(
        src: std.builtin.SourceLocation,
        id_extra: usize,
        gpa: std.mem.Allocator,
        backend: Backend,
    ) !Self {
        const hashval = hashSrc(src, id_extra);
        var self = Self{
            .gpa = gpa,
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
            .wd = WidgetData{ .id = hashval },
            .backend = backend,
        };

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
        self.subwindows.deinit();
        self.min_sizes.deinit();
        self.datas.deinit();
        self.animations.deinit();
        self.tab_index_prev.deinit();
        self.tab_index.deinit();
        self.font_cache.deinit();
        self.icon_cache.deinit();
        self.dialogs.deinit();
    }

    pub fn refresh(self: *Self) void {
        self.extra_frames_needed = 1;
    }

    pub fn addEventKey(self: *Self, event: Event.Key) !bool {
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

        const newpt = (Point{ .x = x, .y = y }).scale(self.natural_scale);
        const dp = newpt.diff(self.mouse_pt);
        self.mouse_pt = newpt;
        const winId = self.windowFor(self.mouse_pt);

        // TODO: focus follows mouse
        // - generate a .focus event here instead of just doing focusWindow(winId, null);
        // - how to make it optional?

        self.event_num += 1;
        try self.events.append(Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .kind = .{ .motion = dp },
                .p = self.mouse_pt,
                .floating_win = winId,
            },
        } });

        const ret = (self.wd.id != winId);
        try self.positionMouseEventAdd();
        return ret;
    }

    pub fn addEventMouseButton(self: *Self, kind: Event.Mouse.Kind) !bool {
        if (self.debug_under_mouse and kind == .press and kind.press == .left) {
            // a left click will stop the debug stuff from following the mouse,
            // but need to stop it at the end of the frame when we've gotten
            // the info
            self.debug_under_mouse_quitting = true;
            return true;
        }

        self.positionMouseEventRemove();

        const winId = self.windowFor(self.mouse_pt);

        if (kind == .press and (kind.press == .left or kind.press == .right)) {
            // normally the focus event is what focuses windows, but since the
            // base window is instantiated before events are added, it has to
            // do any event processing as the events come in, right now
            if (winId == self.wd.id) {
                // focus the window here so any more key events get routed
                // properly
                focusSubwindow(self.wd.id, null);
            }

            // add mouse focus event
            self.event_num += 1;
            try self.events.append(Event{ .num = self.event_num, .evt = .{
                .mouse = .{
                    .kind = .{ .focus = kind.press },
                    .p = self.mouse_pt,
                    .floating_win = winId,
                },
            } });
        }

        self.event_num += 1;
        try self.events.append(Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .kind = kind,
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
        if (builtin.target.os.tag == .linux) {
            ticks_adj = ticks * 20;
        }
        //std.debug.print("mouse wheel {d}\n", .{ticks_adj});

        self.event_num += 1;
        try self.events.append(Event{ .num = self.event_num, .evt = .{
            .mouse = .{
                .kind = .{ .wheel_y = ticks_adj },
                .p = self.mouse_pt,
                .floating_win = winId,
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

        const avg = @intToFloat(f32, diff) / @intToFloat(f32, self.frame_times.len - 1);
        const fps = 1_000_000.0 / avg;
        return fps;
    }

    pub fn beginWait(self: *Self, has_event: bool) i128 {
        var new_time = math.max(self.frame_time_ns, std.time.nanoTimestamp());

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
                self.loop_target_slop_frames = math.max(1, self.loop_target_slop_frames + 1);
                self.loop_target_slop += self.loop_target_slop_frames;
            } else if (new_time < target) {
                // woke up sooner than expected
                self.loop_target_slop_frames = math.min(-1, self.loop_target_slop_frames - 1);
                self.loop_target_slop += self.loop_target_slop_frames;

                // since we are early, spin a bit to guarantee that we never run before
                // the target
                //var i: usize = 0;
                //var first_time = new_time;
                while (new_time < target) {
                    //i += 1;
                    std.time.sleep(0);
                    new_time = math.max(self.frame_time_ns, std.time.nanoTimestamp());
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
            min_micros = @floatToInt(u32, 1_000_000.0 / mfps);
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
        const so_far_nanos = math.max(self.frame_time_ns, std.time.nanoTimestamp()) - self.frame_time_ns;
        var so_far_micros = @intCast(u32, @divFloor(so_far_nanos, 1000));
        //std.debug.print("  far {d:6}", .{so_far_micros});

        // take time from min_micros first
        const min_so_far = math.min(so_far_micros, min_micros);
        so_far_micros -= min_so_far;
        min_micros -= min_so_far;

        // then take time from wait_micros
        const min_so_far2 = math.min(so_far_micros, wait_micros);
        so_far_micros -= min_so_far2;
        wait_micros -= min_so_far2;

        var slop = self.loop_target_slop;

        // get slop we can take out of min_micros
        const min_us_slop = math.min(slop, min_micros);
        slop -= min_us_slop;
        if (min_us_slop >= 0) {
            min_micros -= @intCast(u32, min_us_slop);
        } else {
            min_micros += @intCast(u32, -min_us_slop);
        }

        // remaining slop we can take out of wait_micros
        const wait_us_slop = math.min(slop, wait_micros);
        slop -= wait_us_slop;
        if (wait_us_slop >= 0) {
            wait_micros -= @intCast(u32, wait_us_slop);
        } else {
            wait_micros += @intCast(u32, -wait_us_slop);
        }

        //std.debug.print("  min {d:6}", .{min_micros});
        if (min_micros > 0) {
            // wait unconditionally for fps target
            std.time.sleep(min_micros * 1000);
            self.loop_wait_target = self.frame_time_ns + (@intCast(i128, target_min) * 1000);
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
            self.loop_wait_target = self.frame_time_ns + (@intCast(i128, target) * 1000);
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
        arena: std.mem.Allocator,
        time_ns: i128,
    ) !void {
        var micros_since_last: u32 = 1;
        if (time_ns > self.frame_time_ns) {
            // enforce monotinicity
            const nanos_since_last = time_ns - self.frame_time_ns;
            micros_since_last = @intCast(u32, @divFloor(nanos_since_last, std.time.ns_per_us));
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
                self.frame_times[i] = self.frame_times[i + 1] + micros_since_last;
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
                self.gpa.free(dd.value.data);
            }

            //std.debug.print("datas {d}\n", .{self.datas.count()});
        }

        self.tab_index_prev.deinit();
        self.tab_index_prev = self.tab_index;
        self.tab_index = @TypeOf(self.tab_index).init(self.tab_index.allocator);

        self.rect_pixels = self.backend.pixelSize().rect();
        clipSet(self.rect_pixels);

        self.wd.rect = self.backend.windowSize().rect();
        self.natural_scale = self.rect_pixels.w / self.wd.rect.w;

        debug("window size {d} x {d} renderer size {d} x {d} scale {d}", .{ self.wd.rect.w, self.wd.rect.h, self.rect_pixels.w, self.rect_pixels.h, self.natural_scale });

        try subwindowAdd(self.wd.id, self.wd.rect, false, null);

        _ = subwindowCurrentSet(self.wd.id);

        self.extra_frames_needed -|= 1;
        self.rate = @intToFloat(f32, micros_since_last) / 1_000_000;

        {
            const micros: i32 = if (micros_since_last > math.maxInt(i32)) math.maxInt(i32) else @intCast(i32, micros_since_last);
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
            self.captureID = null;
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
            const pt = self.mouse_pt.scale(1 / self.natural_scale);
            _ = try self.addEventMouseMotion(pt.x, pt.y);
        }

        self.backend.begin(arena);
    }

    fn positionMouseEventAdd(self: *Self) !void {
        try self.events.append(.{ .evt = .{ .mouse = .{
            .kind = .position,
            .p = self.mouse_pt,
            .floating_win = self.windowFor(self.mouse_pt),
        } } });
    }

    fn positionMouseEventRemove(self: *Self) void {
        const e = self.events.pop();
        if (e.evt != .mouse or e.evt.mouse.kind != .position) {
            // std.debug.print("positionMouseEventRemove removed a non-mouse or non-position event\n", .{});
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

        std.debug.print("subwindowFocused failed to find the current subwindow, returning base window\n", .{});
        return &self.subwindows.items[0];
    }

    // Return the cursor the gui wants.  Client code should cache this if
    // switching the platform's cursor is expensive.
    pub fn cursorRequested(self: *const Self) Cursor {
        if (self.drag_state == .dragging) {
            return self.cursor_dragging;
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
    pub fn dataSet(self: *Self, id: u32, key: []const u8, data_in: anytype) void {
        const hash = hashIdKey(id, key);
        var bytes: []const u8 = undefined;
        const dt = @typeInfo(@TypeOf(data_in));
        if (dt == .Pointer and (dt.Pointer.size == .Slice or
            (dt.Pointer.size == .One and @typeInfo(dt.Pointer.child) == .Array)))
        {
            bytes = std.mem.sliceAsBytes(data_in);
        } else {
            bytes = std.mem.asBytes(&data_in);
        }

        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (self.datas.getPtr(hash)) |sd| {
            if (sd.data.len == bytes.len) {
                sd.used = true;
                std.mem.copy(u8, sd.data, bytes);
                return;
            } else {
                std.debug.print("dataSet: already had data for id {x} key {s}, freeing previous data\n", .{ id, key });
                self.gpa.free(sd.data);
            }
        }

        var sd = SavedData{ .data = self.gpa.alloc(u8, bytes.len) catch |err| switch (err) {
            error.OutOfMemory => {
                std.debug.print("dataSet: got {!} for id {x} key {s}\n", .{ err, id, key });
                return;
            },
        } };
        std.mem.copy(u8, sd.data, bytes);
        self.datas.put(hash, sd) catch |err| switch (err) {
            error.OutOfMemory => {
                self.gpa.free(sd.data);
                std.debug.print("dataSet: got {!} for id {x} key {s}\n", .{ err, id, key });
                return;
            },
        };
    }

    // if T is a slice, returns slice of internal storage, so need to copy if
    // keeping the returned slice across frames
    pub fn dataGet(self: *Self, id: u32, key: []const u8, comptime T: type) ?T {
        const hash = hashIdKey(id, key);

        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (self.datas.getPtr(hash)) |sd| {
            sd.used = true;
            const dt = @typeInfo(T);
            if (dt == .Pointer and dt.Pointer.size == .Slice) {
                return sd.data;
            } else {
                return std.mem.bytesToValue(T, sd.data[0..@sizeOf(T)]);
            }
        } else {
            return null;
        }
    }

    pub fn dataRemove(self: *Self, id: u32, key: []const u8) void {
        const hash = hashIdKey(id, key);

        self.data_mutex.lock();
        defer self.data_mutex.unlock();

        if (self.datas.fetchRemove(hash)) |dd| {
            self.gpa.free(dd.value.data);
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
        var ti = gui.toastsFor(null);
        if (ti) |*it| {
            var toast_win = FloatingWindowWidget.init(@src(), .{ .stay_above_parent = true }, .{ .background = false, .border = .{} });
            defer toast_win.deinit();

            toast_win.data().rect = gui.placeIn(self.wd.rect, toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
            toast_win.autoSize();
            try toast_win.install(.{ .process_events = false });

            var vbox = try gui.box(@src(), .vertical, .{});
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

        var float = try gui.floatingWindow(@src(), .{ .open_flag = &self.debug_window_show }, .{ .min_size_content = .{ .w = 300, .h = 400 } });
        defer float.deinit();

        try gui.windowHeader("GUI Debug", "", &self.debug_window_show);

        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            try gui.labelNoFmt(@src(), "Hex id of widget to highlight:", .{ .gravity_y = 0.5 });

            var buf = [_]u8{0} ** 20;
            _ = try std.fmt.bufPrint(&buf, "{x}", .{self.debug_widget_id});
            try gui.textEntry(@src(), .{ .text = &buf }, .{});

            self.debug_widget_id = std.fmt.parseInt(u32, std.mem.sliceTo(&buf, 0), 16) catch 0;
        }

        var tl = try gui.textLayout(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 80 } });
        try tl.addText(self.debug_info_name_rect, .{});
        try tl.addText("\n\n", .{});
        try tl.addText(self.debug_info_src_id_extra, .{});
        tl.deinit();

        if (try gui.button(@src(), if (dum) "Stop (Or Left Click)" else "Debug Under Mouse", .{})) {
            dum = !dum;
        }

        var scroll = try gui.scrollArea(@src(), .{ .expand = .both, .background = false });
        defer scroll.deinit();

        var iter = std.mem.split(u8, self.debug_under_mouse_info, "\n");
        var i: usize = 0;
        while (iter.next()) |line| : (i += 1) {
            if (line.len > 0) {
                var hbox = try gui.box(@src(), .horizontal, .{ .id_extra = i });
                defer hbox.deinit();

                if (try gui.buttonIcon(@src(), 12, "find", gui.icons.papirus.actions.edit_find_symbolic, .{})) {
                    self.debug_widget_id = std.fmt.parseInt(u32, std.mem.sliceTo(line, ' '), 16) catch 0;
                }

                try gui.labelNoFmt(@src(), line, .{ .gravity_y = 0.5 });
            }
        }
    }

    // End of this window gui's rendering.  Renders retained dialogs and all
    // deferred rendering (subwindows, focus highlights).  Returns micros we
    // want between last call to begin() and next call to begin() (or null
    // meaning wait for event).  If wanted, pass return value to waitTime() to
    // get a useful time to wait between render loops.
    pub fn end(self: *Self) !?u32 {
        try self.toastsShow();
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
        var iter = EventIterator.init(self.wd.id, self.rect_pixels, null);
        while (iter.nextCleanup(true)) |e| {
            // doesn't matter if we mark events has handled or not because this is
            // the end of the line for all events
            if (e.evt == .mouse) {
                if (e.evt.mouse.kind == .focus) {
                    // unhandled click, clear focus
                    focusWidget(null, null);
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

        if (self.focusedSubwindowLost()) {
            // if the subwindow that was focused went away, focus the highest
            // one (there is always the base one)
            const sw = self.subwindows.items[self.subwindows.items.len - 1];
            focusSubwindow(sw.id, null);

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
                    const st = @intCast(u32, kv.value_ptr.start_time);
                    ret = math.min(ret orelse st, st);
                } else if (kv.value_ptr.end_time > 0) {
                    ret = 0;
                    break;
                }
            }
        }

        return ret;
    }

    pub fn focusedSubwindowLost(self: *Self) bool {
        for (self.subwindows.items) |*sw| {
            if (sw.id == self.focused_subwindowId) {
                return false;
            }
        }

        return true;
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
        const ret = placeIn(r, minSize(id, min_size), e, g);
        self.next_widget_ypos += ret.h;
        return ret;
    }

    pub fn screenRectScale(self: *Self, r: Rect) RectScale {
        // can't use WidgetData helper functions because our parent is undefined
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
    layout: MenuWidget = undefined,
    initialRect: Rect = Rect{},
    prevClip: Rect = Rect{},

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
        self.wd = WidgetData.init(src, .{ .id_extra = opts.id_extra, .rect = .{} });

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
            self.wd.rect = placeOnScreen(self.initialRect, self.wd.rect);
        } else {
            self.wd.rect = placeOnScreen(self.initialRect, Rect.fromPoint(self.initialRect.topleft()));
            focusSubwindow(self.wd.id, null);

            // need a second frame to fit contents (FocusWindow calls refresh but
            // here for clarity)
            refresh();
        }

        // outside normal flow, so don't get rect from parent
        const rs = self.ownScreenRectScale();
        try subwindowAdd(self.wd.id, rs.r, false, null);
        try self.wd.register("Popup", rs);

        // clip to just our window (using clipSet since we are not inside our parent)
        self.prevClip = clipGet();
        clipSet(rs.r);

        // we are using MenuWidget to do border/background but floating windows
        // don't have margin, so turn that off
        self.layout = MenuWidget.init(@src(), .vertical, self.options.override(.{ .margin = .{} }));
        try self.layout.install(.{});
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
        // outside normal flow, so don't get rect from parent
        return self.ownScreenRectScale().rectToScreen(rect);
    }

    pub fn ownScreenRectScale(self: *const Self) RectScale {
        const s = windowNaturalScale();
        const scaled = self.wd.rect.scale(s);
        return RectScale{ .r = scaled.offset(windowRectPixels()), .s = s };
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
        // outside normal flow, so don't get rect from parent
        const rs = self.ownScreenRectScale();
        var iter = EventIterator.init(self.wd.id, rs.r, null);
        while (iter.nextCleanup(true)) |e| {
            if (e.evt == .mouse) {
                // mark all events as handled so no mouse events are handled by
                // windows under us
                e.handled = true;
                if (e.evt.mouse.kind == .focus) {
                    // unhandled click, clear focus
                    focusWidget(null, null);
                }
            } else if (e.evt == .key) {
                if (e.evt.key.code == .escape and e.evt.key.action == .down) {
                    e.handled = true;
                    var closeE = Event{ .evt = .{ .close_popup = .{} } };
                    self.processEvent(&closeE, true);
                } else if (e.evt.key.code == .tab and e.evt.key.action == .down) {
                    e.handled = true;
                    if (e.evt.key.mod.shift()) {
                        tabIndexPrev(e.num);
                    } else {
                        tabIndexNext(e.num);
                    }
                } else if (e.evt.key.code == .up and e.evt.key.action == .down) {
                    e.handled = true;
                    tabIndexPrev(e.num);
                } else if (e.evt.key.code == .down and e.evt.key.action == .down) {
                    e.handled = true;
                    tabIndexNext(e.num);
                } else if (e.evt.key.code == .left and e.evt.key.action == .down) {
                    e.handled = true;
                    if (self.layout.parentMenu) |pm| {
                        pm.submenus_activated = false;
                        focusSubwindow(self.prev_windowId, e.num);
                    }
                }
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

        self.layout.deinit();
        self.wd.minSizeSetAndCue();

        // outside normal layout, don't call minSizeForChild or
        // self.wd.minSizeReportToParent();

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
    };

    wd: WidgetData = undefined,
    init_options: InitOptions = undefined,
    options: Options = undefined,
    process_events: bool = true,
    captured: bool = false,
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
        self.wd = WidgetData.init(src, .{ .id_extra = opts.id_extra, .rect = .{} });

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
                if (self.auto_pos and !self.auto_size) {
                    self.auto_pos = false;
                    self.wd.rect = placeIn(windowRect(), self.wd.rect.size(), .none, .{ .x = 0.5, .y = 0.5 });
                }
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

            if (self.auto_pos) {
                // only position ourselves once by default
                self.auto_pos = false;

                self.wd.rect = placeIn(windowRect(), self.wd.rect.size(), .none, .{ .x = 0.5, .y = 0.5 });

                //std.debug.print("autopos to {}\n", .{self.wd.rect});
            }
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

            // first frame we are being shown
            focusSubwindow(self.wd.id, null);

            // need a second frame to fit contents (FocusWindow calls
            // refresh but here for clarity)
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

        self.captured = captureMouseMaintain(self.wd.id);

        if (self.process_events) {
            // processEventsBefore can change self.wd.rect
            self.processEventsBefore();
        }

        // outside normal flow, so don't get rect from parent
        const rs = self.ownScreenRectScale();
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
        // outside normal flow, so don't get rect from parent
        const rs = self.ownScreenRectScale();
        var iter = EventIterator.init(self.wd.id, rs.r, null);
        while (iter.next()) |e| {
            if (e.evt == .mouse) {
                const me = e.evt.mouse;
                var corner: bool = false;
                if (me.p.x > rs.r.x + rs.r.w - 15 * rs.s and
                    me.p.y > rs.r.y + rs.r.h - 15 * rs.s)
                {
                    // we are over the bottom-right resize corner
                    corner = true;
                }

                if (me.kind == .focus) {
                    // focus but let the focus event propagate to widgets
                    focusSubwindow(self.wd.id, e.num);
                }

                if (self.captured or corner) {
                    if (me.kind == .press and me.kind.press == .left) {
                        // capture and start drag
                        self.captured = captureMouse(self.wd.id);
                        dragStart(me.p, .arrow_nw_se, Point.diff(rs.r.bottomRight(), me.p));
                        e.handled = true;
                    } else if (me.kind == .release and me.kind.release == .left) {
                        // stop drag and capture
                        self.captured = captureMouse(null);
                        dragEnd();
                        e.handled = true;
                    } else if (me.kind == .motion) {
                        // move if dragging
                        if (dragging(me.p)) |dps| {
                            if (cursorGetDragging() == Cursor.crosshair) {
                                const dp = dps.scale(1 / rs.s);
                                self.wd.rect.x += dp.x;
                                self.wd.rect.y += dp.y;
                            } else if (cursorGetDragging() == Cursor.arrow_nw_se) {
                                const p = me.p.plus(dragOffset()).scale(1 / rs.s);
                                self.wd.rect.w = math.max(40, p.x - self.wd.rect.x);
                                self.wd.rect.h = math.max(10, p.y - self.wd.rect.y);
                            }
                            // don't need refresh() because we're before drawing
                            e.handled = true;
                        }
                    } else if (me.kind == .position) {
                        if (corner) {
                            cursorSet(.arrow_nw_se);
                            e.handled = true;
                        }
                    }
                }
            }
        }
    }

    pub fn processEventsAfter(self: *Self) void {
        // outside normal flow, so don't get rect from parent
        const rs = self.ownScreenRectScale();
        var iter = EventIterator.init(self.wd.id, rs.r, null);
        // duplicate processEventsBefore (minus corner stuff) because you could
        // have a click down, motion, and up in same frame and you wouldn't know
        // you needed to do anything until you got capture here
        while (iter.nextCleanup(true)) |e| {
            // mark all events as handled so no mouse events are handled by windows
            // under us
            e.handled = true;
            switch (e.evt) {
                .mouse => |me| {
                    switch (me.kind) {
                        .focus => focusWidget(null, null),
                        .press => |b| {
                            if (b == .left) {
                                // capture and start drag
                                self.captured = captureMouse(self.wd.id);
                                dragPreStart(e.evt.mouse.p, .crosshair, Point{});
                            }
                        },
                        .release => |b| {
                            if (b == .left) {
                                // stop drag and capture
                                self.captured = captureMouse(null);
                                dragEnd();
                            }
                        },
                        .motion => {
                            // move if dragging
                            if (dragging(me.p)) |dps| {
                                if (cursorGetDragging() == Cursor.crosshair) {
                                    const dp = dps.scale(1 / rs.s);
                                    self.wd.rect.x += dp.x;
                                    self.wd.rect.y += dp.y;
                                }
                                refresh();
                            }
                        },
                        else => {},
                    }
                },
                .key => |ke| {
                    // catch any tabs that weren't handled by widgets
                    if (ke.code == .tab and ke.action == .down) {
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
        //subwindowClosing(self.wd.id);
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
        // outside normal flow, so don't get rect from parent
        return self.ownScreenRectScale().rectToScreen(rect);
    }

    pub fn ownScreenRectScale(self: *const Self) RectScale {
        const s = windowNaturalScale();
        const scaled = self.wd.rect.scale(s);
        return RectScale{ .r = scaled.offset(windowRectPixels()), .s = s };
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
        self.wd.minSizeSetAndCue();

        // outside normal layout, don't call minSizeForChild or
        // self.wd.minSizeReportToParent();

        _ = parentSet(self.wd.parent);
        _ = subwindowCurrentSet(self.prev_windowId);
        clipSet(self.prevClip);
    }
};

pub fn windowHeader(str: []const u8, right_str: []const u8, openflag: ?*bool) !void {
    var over = try gui.overlay(@src(), .{ .expand = .horizontal });

    if (try gui.buttonIcon(@src(), 14, "close", gui.icons.papirus.actions.window_close_symbolic, .{ .gravity_y = 0.5, .corner_radius = Rect.all(14), .padding = Rect.all(2), .margin = Rect.all(2) })) {
        if (openflag) |of| {
            of.* = false;
        }
    }

    try gui.labelNoFmt(@src(), str, .{ .gravity_x = 0.5, .gravity_y = 0.5, .expand = .horizontal, .font_style = .heading });
    try gui.labelNoFmt(@src(), right_str, .{ .gravity_x = 1.0 });

    var iter = EventIterator.init(over.wd.id, over.wd.contentRectScale().r, null);
    while (iter.next()) |e| {
        if (e.evt == .mouse and e.evt.mouse.kind == .press and e.evt.mouse.kind.press == .left) {
            raiseSubwindow(subwindowCurrentId());
        }
    }

    over.deinit();

    try gui.separator(@src(), .{ .expand = .horizontal });
}

pub const DialogDisplayFn = *const fn (u32) Error!void;
pub const DialogCallAfterFn = *const fn (u32, DialogResponse) Error!void;
pub const DialogResponse = enum(u8) {
    closed,
    ok,
    _,
};

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
            const id = parent.extendID(src, id_extra);
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
    dataSet(opts.window, id, "_title", opts.title);
    dataSet(opts.window, id, "_message", opts.message);
    if (opts.callafterFn) |ca| {
        dataSet(opts.window, id, "_callafter", ca);
    }
    id_mutex.mutex.unlock();
}

pub fn dialogDisplay(id: u32) !void {
    const modal = gui.dataGet(null, id, "_modal", bool) orelse {
        std.debug.print("Error: lost data for dialog {x}\n", .{id});
        gui.dialogRemove(id);
        return;
    };

    const title = gui.dataGet(null, id, "_title", []const u8) orelse {
        std.debug.print("Error: lost data for dialog {x}\n", .{id});
        gui.dialogRemove(id);
        return;
    };

    const message = gui.dataGet(null, id, "_message", []const u8) orelse {
        std.debug.print("Error: lost data for dialog {x}\n", .{id});
        gui.dialogRemove(id);
        return;
    };

    const callafter = gui.dataGet(null, id, "_callafter", DialogCallAfterFn);

    var win = try floatingWindow(@src(), .{ .modal = modal }, .{ .id_extra = id });
    defer win.deinit();

    var header_openflag = true;
    try gui.windowHeader(title, "", &header_openflag);
    if (!header_openflag) {
        gui.dialogRemove(id);
        if (callafter) |ca| {
            try ca(id, .closed);
        }
        return;
    }

    var tl = try gui.textLayout(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .w = 250 }, .background = false });
    try tl.addText(message, .{});
    tl.deinit();

    if (try gui.button(@src(), "Ok", .{ .gravity_x = 0.5, .gravity_y = 0.5, .tab_index = 1 })) {
        gui.dialogRemove(id);
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
            const id = parent.extendID(src, id_extra);
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
    const cw = gui.currentWindow();
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
    const id_mutex = try gui.toastAdd(opts.window, src, opts.id_extra, opts.subwindow_id, opts.displayFn, opts.timeout);
    const id = id_mutex.id;
    gui.dataSet(opts.window, id, "_message", opts.message);
    id_mutex.mutex.unlock();
}

pub fn toastDisplay(id: u32) !void {
    const message = gui.dataGet(null, id, "_message", []const u8) orelse {
        std.debug.print("Error: lost message for toast {x}\n", .{id});
        return;
    };

    var animator = try gui.animate(@src(), .alpha, 500_000, .{ .id_extra = id });
    defer animator.deinit();
    try gui.labelNoFmt(@src(), message, .{ .background = true, .corner_radius = gui.Rect.all(1000) });

    if (gui.timerDone(id)) {
        animator.startEnd();
    }

    if (animator.end()) {
        gui.toastRemove(id);
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
        return Self{ .wd = WidgetData.init(src, opts), .kind = kind, .duration = duration_micros };
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());
        try self.wd.register("Animate", null);

        if (firstFrame(self.wd.id)) {
            // start begin animation
            gui.animation(self.wd.id, "_start", .{ .start_val = 0.0, .end_val = 1.0, .end_time = self.duration });
        }

        if (gui.animationGet(self.wd.id, "_end")) |a| {
            self.val = a.lerp();
        } else if (gui.animationGet(self.wd.id, "_start")) |a| {
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
        gui.animation(self.wd.id, "_end", .{ .start_val = 1.0, .end_val = 0.0, .end_time = self.duration });
    }

    pub fn end(self: *Self) bool {
        return gui.animationDone(self.wd.id, "_end");
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

        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

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
    if (gui.dataGet(null, bc.wd.id, "_expand", bool)) |e| {
        expanded = e;
    }

    if (bc.clicked()) {
        expanded = !expanded;
    }

    var bcbox = BoxWidget.init(@src(), .horizontal, false, options.strip());
    defer bcbox.deinit();
    try bcbox.install(.{});
    const size = try options.fontGet().lineSkip();
    if (expanded) {
        try icon(@src(), "down_arrow", gui.icons.papirus.actions.pan_down_symbolic, .{ .gravity_y = 0.5, .min_size_content = .{ .h = size } });
    } else {
        try icon(@src(), "right_arrow", gui.icons.papirus.actions.pan_end_symbolic, .{ .gravity_y = 0.5, .min_size_content = .{ .h = size } });
    }
    try labelNoFmt(@src(), label_str, options.strip());

    gui.dataSet(null, bc.wd.id, "_expand", expanded);

    return expanded;
}

pub fn paned(src: std.builtin.SourceLocation, dir: gui.Direction, collapse_size: f32, opts: Options) !*PanedWidget {
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
    dir: gui.Direction = undefined,
    collapse_size: f32 = 0,
    captured: bool = false,
    hovered: bool = false,
    saved_data: SavedData = undefined,
    first_side_id: ?u32 = null,
    prevClip: Rect = Rect{},

    pub fn init(src: std.builtin.SourceLocation, dir: gui.Direction, collapse_size: f32, opts: Options) Self {
        var self = Self{};
        self.wd = WidgetData.init(src, opts);
        self.dir = dir;
        self.collapse_size = collapse_size;
        self.captured = captureMouseMaintain(self.wd.id);

        const rect = self.wd.contentRect();

        if (gui.dataGet(null, self.wd.id, "_data", SavedData)) |d| {
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

        if (gui.animationGet(self.wd.id, "_split_ratio")) |a| {
            self.split_ratio = a.lerp();
        }

        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        try self.wd.register("Paned", null);

        if (opts.process_events) {
            var iter = EventIterator.init(self.data().id, self.data().borderRectScale().r, null);
            while (iter.next()) |e| {
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
        gui.animation(self.wd.id, "_split_ratio", gui.Animation{ .start_val = self.split_ratio, .end_val = end_val, .end_time = 250_000 });
    }

    pub fn widget(self: *Self) Widget {
        return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn rectFor(self: *Self, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) gui.Rect {
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
            return gui.placeIn(r, minSize(id, min_size), e, g);
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
            return gui.placeIn(r, minSize(id, min_size), e, g);
        }
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: gui.Size) void {
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

            if (self.captured or @fabs(mouse - target) < (5 * rs.s)) {
                self.hovered = true;
                e.handled = true;
                if (e.evt.mouse.kind == .press and e.evt.mouse.kind.press == .left) {
                    // capture and start drag
                    self.captured = captureMouse(self.wd.id);
                    dragPreStart(e.evt.mouse.p, cursor, Point{});
                } else if (e.evt.mouse.kind == .release and e.evt.mouse.kind.release == .left) {
                    // stop possible drag and capture
                    self.captured = captureMouse(null);
                    dragEnd();
                } else if (e.evt.mouse.kind == .motion) {
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

                        self.split_ratio = math.max(0.0, math.min(1.0, self.split_ratio));
                    }
                } else if (e.evt.mouse.kind == .position) {
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
        gui.dataSet(null, self.wd.id, "_data", SavedData{ .split_ratio = self.split_ratio, .rect = self.wd.contentRect() });
        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();
        _ = gui.parentSet(self.wd.parent);
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
    try ret.install(.{});
    return ret;
}

pub const TextLayoutWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .margin = Rect.all(4),
        .padding = Rect.all(4),
        .background = true,
        .color_style = .content,
        .min_size_content = .{ .w = 25 },
    };

    pub const InitOptions = struct {
        selection: ?*Selection = null,
        break_lines: bool = true,
    };

    pub const Selection = struct {
        cursor: usize = 0,
        start: usize = 0,
        end: usize = 0,

        pub fn order(self: *Selection) void {
            if (self.end < self.start) {
                const tmp = self.start;
                self.start = self.end;
                self.end = tmp;
            }
        }
    };

    wd: WidgetData = undefined,
    corners: [2]?Rect = [_]?Rect{null} ** 2,
    insert_pt: Point = Point{},
    prevClip: Rect = Rect{},
    first_line: bool = true,
    break_lines: bool = undefined,

    bytes_seen: usize = 0,
    captured: bool = false,
    selection_in: ?*Selection = null,
    selection: *Selection = undefined,
    selection_store: Selection = .{},
    sel_mouse_down_pt: ?Point = null,
    sel_mouse_down_bytes: ?usize = null,
    sel_mouse_drag_pt: ?Point = null,

    cursor_seen: bool = false,
    cursor_rect: ?Rect = null,
    cursor_updown: i8 = 0, // positive is down
    cursor_updown_drag: bool = true,
    cursor_updown_pt: ?Point = null,
    scroll_to_cursor: bool = false,

    add_text_done: bool = false,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        const options = defaults.override(opts);
        var self = Self{ .wd = WidgetData.init(src, options), .selection_in = init_opts.selection };
        self.break_lines = init_opts.break_lines;

        if (self.selection_in) |sel| {
            self.selection = sel;
        } else {
            if (dataGet(null, self.wd.id, "_selection", Selection)) |s| {
                self.selection_store = s;
            }
            self.selection = &self.selection_store;
        }

        self.captured = captureMouseMaintain(self.wd.id);

        if (self.captured) {
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

        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        try self.wd.register("TextLayout", null);
        _ = parentSet(self.widget());

        if (opts.process_events) {
            self.processEvents();
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
        const lineskip = try options.fontGet().lineSkip();
        var txt = text;

        const rect = self.wd.contentRect();
        var container_width = rect.w;
        if (self.screenRectScale(rect).r.empty()) {
            // if we are not being shown at all, probably this is the first
            // frame for us and we should calculate our min height assuming we
            // get at least our min width

            // do this dance so we aren't repeating the contentRect
            // calculations here
            const given_width = self.wd.rect.w;
            self.wd.rect.w = math.max(given_width, self.wd.min_size.w);
            container_width = self.wd.contentRect().w;
            self.wd.rect.w = given_width;
        }

        while (txt.len > 0) {
            var linestart: f32 = 0;
            var linewidth = container_width;
            var width = linewidth - self.insert_pt.x;
            for (self.corners) |corner| {
                if (corner) |cor| {
                    if (math.max(cor.y, self.insert_pt.y) < math.min(cor.y + cor.h, self.insert_pt.y + lineskip)) {
                        linewidth -= cor.w;
                        if (linestart == cor.x) {
                            linestart = (cor.x + cor.w);
                        }

                        if (self.insert_pt.x <= (cor.x + cor.w)) {
                            width -= cor.w;
                            if (self.insert_pt.x >= cor.x) {
                                self.insert_pt.x = (cor.x + cor.w);
                            }
                        }
                    }
                }
            }

            var end: usize = undefined;

            // get slice of text that fits within width or ends with newline
            // - always get at least 1 codepoint so we make progress
            var s = try options.fontGet().textSizeEx(txt, if (self.break_lines) width else null, &end, .before);

            const newline = (txt[end - 1] == '\n');

            //std.debug.print("{d} 1 txt to {d} \"{s}\"\n", .{ container_width, end, txt[0..end] });

            // if we are boxed in too much by corner widgets drop to next line
            if (self.break_lines and s.w > width and linewidth < container_width) {
                self.insert_pt.y += lineskip;
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
                    self.insert_pt.y += lineskip;
                    self.insert_pt.x = 0;
                    continue;
                }
            }

            // see if selection needs to be updated
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
                    // point is after this text, but we might not get anymore
                    self.sel_mouse_down_bytes = self.bytes_seen + end;
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
                self.scroll_to_cursor = true;
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
                        self.selection.order();
                        self.scroll_to_cursor = true;
                    }
                }
            }

            const rs = self.screenRectScale(Rect{ .x = self.insert_pt.x, .y = self.insert_pt.y, .w = width, .h = math.max(0, rect.h - self.insert_pt.y) });
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
                const cr = Rect{ .x = self.insert_pt.x + size.w, .y = self.insert_pt.y, .w = 2, .h = size.h };

                if (self.cursor_updown != 0 and self.cursor_updown_pt == null) {
                    const cr_new = cr.add(.{ .y = @intToFloat(f32, self.cursor_updown) * size.h });
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
                        .screen_rect = self.screenRectScale(cr).r,
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
            const size = Size{ .w = self.insert_pt.x, .h = self.insert_pt.y + s.h };
            self.wd.min_size.w = math.max(self.wd.min_size.w, self.wd.padSize(size).w);
            self.wd.min_size.h = math.max(self.wd.min_size.h, self.wd.padSize(size).h);
            txt = txt[end..];
            self.bytes_seen += end;

            // move insert_pt to next line if we have more text
            if (txt.len > 0 or newline) {
                self.insert_pt.y += lineskip;
                self.insert_pt.x = 0;
            }
        }
    }

    pub fn addTextDone(self: *Self, opts: Options) !void {
        self.add_text_done = true;

        self.selection.cursor = @min(self.selection.cursor, self.bytes_seen);
        self.selection.start = @min(self.selection.start, self.bytes_seen);
        self.selection.end = @min(self.selection.end, self.bytes_seen);

        if (!self.cursor_seen) {
            self.cursor_seen = true;
            self.selection.cursor = self.bytes_seen;

            const options = self.wd.options.override(opts);
            const size = try options.fontGet().textSize("");
            const cr = Rect{ .x = self.insert_pt.x + size.w, .y = self.insert_pt.y, .w = 2, .h = size.h };

            if (self.cursor_updown != 0 and self.cursor_updown_pt == null) {
                const cr_new = cr.add(.{ .y = @intToFloat(f32, self.cursor_updown) * size.h });
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
                    .screen_rect = self.screenRectScale(cr).r,
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
        if (g.x < 0.5) {
            i = 0; // upleft
        } else {
            i = 1; // upright
        }

        self.corners[i] = ret;
        return ret;
    }

    pub fn screenRectScale(self: *Self, rect: Rect) RectScale {
        return self.wd.contentRectScale().rectToScreen(rect);
    }

    pub fn minSizeForChild(self: *Self, s: Size) void {
        const padded = self.wd.padSize(s);
        self.wd.min_size.w = math.max(self.wd.min_size.w, padded.w);
        self.wd.min_size.h += padded.h;
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

    pub fn processEvents(self: *Self) void {
        var iter = EventIterator.init(self.data().id, self.data().borderRectScale().r, null);
        while (iter.next()) |e| {
            self.processEvent(e, false);
        }
    }

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        if (e.evt == .mouse) {
            if (e.evt.mouse.kind == .focus) {
                e.handled = true;
                // focus so that we can receive keyboard input
                focusWidget(self.wd.id, e.num);
            } else if (e.evt.mouse.kind == .press and e.evt.mouse.kind.press == .left) {
                e.handled = true;
                // capture and start drag
                self.captured = captureMouse(self.wd.id);
                dragPreStart(e.evt.mouse.p, .ibeam, Point{});
                self.sel_mouse_down_pt = self.wd.contentRectScale().pointFromScreen(e.evt.mouse.p);
                self.sel_mouse_drag_pt = null;
                self.cursor_updown = 0;
                self.cursor_updown_pt = null;
            } else if (e.evt.mouse.kind == .release and e.evt.mouse.kind.release == .left) {
                e.handled = true;
                // stop possible drag and capture
                self.captured = captureMouse(null);
                dragEnd();
            } else if (e.evt.mouse.kind == .motion) {
                e.handled = true;
                // move if dragging
                if (dragging(e.evt.mouse.p)) |dps| {
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
                }
            }
        } else if (e.evt == .key and e.evt.key.mod.shift()) {
            switch (e.evt.key.code) {
                .left => {
                    e.handled = true;
                    if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown == 0) {
                        // only change selection if mouse isn't trying to change it
                        if (self.selection.cursor == self.selection.start) {
                            self.selection.start -|= 1;
                        } else {
                            self.selection.end -|= 1;
                        }
                        self.selection.cursor -|= 1;
                        self.scroll_to_cursor = true;
                    }
                },
                .right => {
                    e.handled = true;
                    if (self.sel_mouse_down_pt == null and self.sel_mouse_drag_pt == null and self.cursor_updown == 0) {
                        // only change selection if mouse isn't trying to change it
                        if (self.selection.cursor == self.selection.end) {
                            self.selection.end += 1;
                        } else {
                            self.selection.start += 1;
                        }
                        self.selection.cursor += 1;
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
        if (self.captured) {
            dataSet(null, self.wd.id, "_sel_mouse_down_bytes", self.sel_mouse_down_bytes);
        }
        if (self.cursor_updown != 0) {
            dataSet(null, self.wd.id, "_cursor_updown_pt", self.cursor_updown_pt);
            dataSet(null, self.wd.id, "_cursor_updown_drag", self.cursor_updown_drag);
        }
        clipSet(self.prevClip);
        self.wd.minSizeSetAndCue();
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
        self.wd = WidgetData.init(src, opts);
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
                    const focused_winId = focusedSubwindowId();
                    focusSubwindow(self.winId, null);
                    focusWidget(null, null);
                    focusSubwindow(focused_winId, null);
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
        var iter = EventIterator.init(self.wd.id, rs.r, null);
        while (iter.next()) |e| {
            switch (e.evt) {
                .mouse => |me| {
                    if (me.kind == .focus and me.kind.focus == .right) {
                        // eat any right button focus events so they don't get
                        // caught by the containing window cleanup and cause us
                        // to lose the focus we are about to get from the right
                        // press below
                        e.handled = true;
                    } else if (me.kind == .press and me.kind.press == .right) {
                        e.handled = true;
                        focusWidget(self.wd.id, e.num);
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
        self.wd.minSizeSetAndCue();
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
        return Self{ .wd = WidgetData.init(src, opts) };
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
        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub const Direction = enum {
    horizontal,
    vertical,
};

pub fn box(src: std.builtin.SourceLocation, dir: Direction, opts: Options) !*BoxWidget {
    var ret = try currentWindow().arena.create(BoxWidget);
    ret.* = BoxWidget.init(src, dir, false, opts);
    try ret.install(.{});
    return ret;
}

pub fn boxEqual(src: std.builtin.SourceLocation, dir: Direction, opts: Options) !*BoxWidget {
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
    dir: Direction = undefined,
    equal_space: bool = undefined,
    max_thick: f32 = 0,
    data_prev: Data = Data{},
    min_space_taken: f32 = 0,
    total_weight: f32 = 0,
    childRect: Rect = Rect{},
    extra_pixels: f32 = 0,

    pub fn init(src: std.builtin.SourceLocation, dir: Direction, equal_space: bool, opts: Options) BoxWidget {
        var self = Self{};
        self.wd = WidgetData.init(src, opts);
        self.dir = dir;
        self.equal_space = equal_space;
        if (dataGet(null, self.wd.id, "_data", Data)) |d| {
            self.data_prev = d;
        }
        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        try self.wd.register("Box", null);
        try self.wd.borderAndBackground(.{});

        // our rect for children has to start at 0,0
        self.childRect = self.wd.contentRect().justSize();

        if (self.data_prev.min_space_taken_prev) |taken_prev| {
            if (self.dir == .horizontal) {
                if (self.equal_space) {
                    self.extra_pixels = self.childRect.w;
                } else {
                    self.extra_pixels = math.max(0, self.childRect.w - taken_prev);
                }
            } else {
                if (self.equal_space) {
                    self.extra_pixels = self.childRect.h;
                } else {
                    self.extra_pixels = math.max(0, self.childRect.h - taken_prev);
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
        rect.w = math.min(rect.w, child_size.w);
        rect.h = math.min(rect.h, child_size.h);

        if (self.dir == .horizontal) {
            rect.h = self.childRect.h;
            if (self.equal_space) {
                rect.w = pixels_per_w * current_weight;
            } else {
                rect.w += pixels_per_w * current_weight;
            }

            if (g.x <= 0.5) {
                self.childRect.w = math.max(0, self.childRect.w - rect.w);
                self.childRect.x += rect.w;
            } else {
                rect.x += math.max(0, self.childRect.w - rect.w);
                self.childRect.w = math.max(0, self.childRect.w - rect.w);
            }
        } else if (self.dir == .vertical) {
            rect.w = self.childRect.w;
            if (self.equal_space) {
                rect.h = pixels_per_w * current_weight;
            } else {
                rect.h += pixels_per_w * current_weight;
            }

            if (g.y <= 0.5) {
                self.childRect.h = math.max(0, self.childRect.h - rect.h);
                self.childRect.y += rect.h;
            } else {
                rect.y += math.max(0, self.childRect.h - rect.h);
                self.childRect.h = math.max(0, self.childRect.h - rect.h);
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
                self.min_space_taken = math.max(self.min_space_taken, s.w);
            } else {
                self.min_space_taken += s.w;
            }
            self.max_thick = math.max(self.max_thick, s.h);
        } else {
            if (self.equal_space) {
                self.min_space_taken = math.max(self.min_space_taken, s.h);
            } else {
                self.min_space_taken += s.h;
            }
            self.max_thick = math.max(self.max_thick, s.w);
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
        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();

        dataSet(null, self.wd.id, "_data", Data{ .total_weight_prev = self.total_weight, .min_space_taken_prev = self.min_space_taken });

        _ = parentSet(self.wd.parent);
    }
};

pub fn scrollArea(src: std.builtin.SourceLocation, opts: Options) !*ScrollAreaWidget {
    var ret = try currentWindow().arena.create(ScrollAreaWidget);
    ret.* = ScrollAreaWidget.init(src, null, opts);
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

    hbox: BoxWidget = undefined,
    vbox: BoxWidget = undefined,
    io_scroll_info: ?*ScrollInfo = null,
    scroll_info: ScrollInfo = undefined,
    scroll: ScrollContainerWidget = undefined,
    focus_id: ?u32 = null,

    pub fn init(src: std.builtin.SourceLocation, io_si: ?*ScrollInfo, opts: Options) Self {
        var self = Self{};
        const options = defaults.override(opts);

        self.hbox = BoxWidget.init(src, .horizontal, false, options);
        self.io_scroll_info = io_si;
        self.scroll_info = if (io_si) |iosi| iosi.* else (dataGet(null, self.hbox.data().id, "_scroll_info", ScrollInfo) orelse ScrollInfo{});
        return self;
    }

    pub fn setVirtualSize(self: *Self, s: Size) void {
        if (s.w != 0) {
            self.scroll_info.virtual_size.w = s.w;
            if (self.io_scroll_info) |iosi| iosi.* = self.scroll_info;
        }

        if (s.h != 0) {
            self.scroll_info.virtual_size.h = s.h;
            self.scroll_info.vertical = .given;
            if (self.io_scroll_info) |iosi| iosi.* = self.scroll_info;
        }
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true, focus_id: ?u32 = null }) !void {
        self.focus_id = opts.focus_id;
        try self.hbox.install(.{});

        self.vbox = BoxWidget.init(@src(), .vertical, false, self.hbox.data().options.strip().override(.{ .expand = .both }));
        try self.vbox.install(.{});

        var si: *ScrollInfo = undefined;
        if (self.io_scroll_info) |iosi| {
            si = iosi;
        } else {
            si = &self.scroll_info;
        }

        var container_opts = self.hbox.data().options.strip().override(.{ .expand = .both });

        // since we have a scrollbar to the right of us, we only need to copy
        // corner_radius.h (lower-left)
        // TODO: revisit this when adding horizontal scroll and also when
        // making scrollbars disappear if not needed
        container_opts.corner_radius.?.h = self.hbox.data().options.corner_radiusGet().h;

        self.scroll = ScrollContainerWidget.init(@src(), si, container_opts);

        try self.scroll.install(.{ .process_events = opts.process_events });
    }

    pub fn deinit(self: *Self) void {
        var si: *ScrollInfo = undefined;
        if (self.io_scroll_info) |iosi| {
            si = iosi;
        } else {
            si = &self.scroll_info;
        }

        self.scroll.deinit();

        var hbar = ScrollBarWidget.init(@src(), .{ .direction = .horizontal, .scroll_info = si, .focus_id = self.focus_id orelse self.scroll.data().id }, .{ .expand = .horizontal, .gravity_y = 1.0 });
        hbar.install(.{}) catch {};
        hbar.deinit();

        self.vbox.deinit();

        var vbar = ScrollBarWidget.init(@src(), .{ .scroll_info = si, .focus_id = self.focus_id orelse self.scroll.data().id }, .{ .gravity_x = 1.0 });
        vbar.install(.{}) catch {};
        vbar.deinit();

        dataSet(null, self.hbox.data().id, "_scroll_info", if (self.io_scroll_info) |iosi| iosi.* else self.scroll_info);

        self.hbox.deinit();
    }
};

pub const ScrollInfo = struct {
    pub const ScrollType = enum(u8) {
        none, // no scrolling
        auto, // virtual size calculated from children
        given, // virtual size left as given
    };

    vertical: ScrollType = .auto,
    horizontal: ScrollType = .auto,
    virtual_size: Size = Size{},
    viewport: Rect = Rect{},

    pub fn scroll_max(self: ScrollInfo, dir: Direction) f32 {
        switch (dir) {
            .vertical => return @max(0.0, self.virtual_size.h - self.viewport.h),
            .horizontal => return @max(0.0, self.virtual_size.w - self.viewport.w),
        }
    }

    pub fn fraction_visible(self: ScrollInfo, dir: Direction) f32 {
        var viewport_start = switch (dir) {
            .vertical => self.viewport.y,
            .horizontal => self.viewport.x,
        };
        var viewport_size = switch (dir) {
            .vertical => self.viewport.h,
            .horizontal => self.viewport.w,
        };
        var virtual_size = switch (dir) {
            .vertical => self.virtual_size.h,
            .horizontal => self.virtual_size.w,
        };

        if (viewport_size == 0) return 1.0;

        const max_hard_scroll = self.scroll_max(dir);
        var length = math.max(viewport_size, virtual_size);
        if (viewport_start < 0) {
            // temporarily adding the dead space we are showing
            length += -viewport_start;
        } else if (viewport_start > max_hard_scroll) {
            length += (viewport_start - max_hard_scroll);
        }

        return viewport_size / length; // <= 1
    }

    pub fn scroll_fraction(self: ScrollInfo, dir: Direction) f32 {
        var viewport_start = switch (dir) {
            .vertical => self.viewport.y,
            .horizontal => self.viewport.x,
        };
        var viewport_size = switch (dir) {
            .vertical => self.viewport.h,
            .horizontal => self.viewport.w,
        };
        var virtual_size = switch (dir) {
            .vertical => self.virtual_size.h,
            .horizontal => self.virtual_size.w,
        };

        if (viewport_size == 0) return 0;

        const max_hard_scroll = self.scroll_max(dir);
        var length = math.max(viewport_size, virtual_size);
        if (viewport_start < 0) {
            // temporarily adding the dead space we are showing
            length += -viewport_start;
        } else if (viewport_start > max_hard_scroll) {
            length += (viewport_start - max_hard_scroll);
        }

        const max_scroll = math.max(0, length - viewport_size);
        if (max_scroll == 0) return 0;

        return math.max(0, math.min(1.0, viewport_start / max_scroll));
    }

    pub fn scrollToFraction(self: *ScrollInfo, dir: Direction, fin: f32) void {
        const f = math.max(0, math.min(1, fin));
        switch (dir) {
            .vertical => self.viewport.y = f * self.scroll_max(dir),
            .horizontal => self.viewport.x = f * self.scroll_max(dir),
        }
    }
};

pub const ScrollContainerWidget = struct {
    const Self = @This();
    pub var defaults: Options = .{
        .background = true,
        // generally the top of a scroll area is against something flat (like
        // window header), and the bottom is against something curved (bottom
        // of a window)
        .corner_radius = Rect{ .x = 0, .y = 0, .w = 5, .h = 5 },
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

        self.wd = WidgetData.init(src, options);

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
            var iter = EventIterator.init(self.data().id, self.data().borderRectScale().r, null);
            while (iter.next()) |e| {
                self.processEvent(e, false);
            }
        }

        {
            const max_scroll = self.si.scroll_max(.horizontal);
            if (self.si.viewport.x < 0) {
                self.si.viewport.x = math.min(0, math.max(-20, self.si.viewport.x + 250 * animationRate()));
                if (self.si.viewport.x < 0) {
                    refresh();
                }
            } else if (self.si.viewport.x > max_scroll) {
                self.si.viewport.x = math.max(max_scroll, math.min(max_scroll + 20, self.si.viewport.x - 250 * animationRate()));
                if (self.si.viewport.x > max_scroll) {
                    refresh();
                }
            }
        }

        {
            const max_scroll = self.si.scroll_max(.vertical);
            if (self.si.viewport.y < 0) {
                self.si.viewport.y = math.min(0, math.max(-20, self.si.viewport.y + 250 * animationRate()));
                if (self.si.viewport.y < 0) {
                    refresh();
                }
            } else if (self.si.viewport.y > max_scroll) {
                self.si.viewport.y = math.max(max_scroll, math.min(max_scroll + 20, self.si.viewport.y - 250 * animationRate()));
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
        var child_size = minSize(id, min_size);

        const y = self.next_widget_ypos;
        const h = self.si.virtual_size.h - y;
        const w = self.si.virtual_size.w;
        const rect = Rect{ .x = 0, .y = y, .w = math.min(w, child_size.w), .h = math.min(h, child_size.h) };
        const ret = placeIn(rect, minSize(id, child_size), e, g);
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
        self.nextVirtualSize.w = math.max(self.nextVirtualSize.w, s.w);
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
                        }
                        refresh();
                    } else if (ke.code == .down and (ke.action == .down or ke.action == .repeat)) {
                        e.handled = true;
                        if (self.si.vertical != .none) {
                            self.si.viewport.y += 10;
                        }
                        refresh();
                    } else if (ke.code == .left and (ke.action == .down or ke.action == .repeat)) {
                        e.handled = true;
                        if (self.si.horizontal != .none) {
                            self.si.viewport.x -= 10;
                        }
                        refresh();
                    } else if (ke.code == .right and (ke.action == .down or ke.action == .repeat)) {
                        e.handled = true;
                        if (self.si.horizontal != .none) {
                            self.si.viewport.x += 10;
                        }
                        refresh();
                    }
                }
            },
            .scroll_drag => |sd| {
                e.handled = true;
                const rs = self.wd.contentRectScale();
                var scrollval: f32 = 0;
                if (sd.mouse_pt.y <= rs.r.y and // want to scroll up
                    sd.screen_rect.y < rs.r.y and // scrolling would show more of child
                    self.si.viewport.y > 0) // can scroll up
                {
                    scrollval = if (sd.injected) -200 * animationRate() else -5;
                }

                if (sd.mouse_pt.y >= (rs.r.y + rs.r.h) and
                    (sd.screen_rect.y + sd.screen_rect.h) > (rs.r.y + rs.r.h) and
                    self.si.viewport.y < self.si.scroll_max(.vertical))
                {
                    scrollval = if (sd.injected) 200 * animationRate() else 5;
                }

                if (scrollval != 0) {
                    self.si.viewport.y = @max(0.0, @min(self.si.scroll_max(.vertical), self.si.viewport.y + scrollval));
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
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn processEventsAfter(self: *Self) void {
        const rs = self.wd.borderRectScale();
        var iter = EventIterator.init(self.wd.id, rs.r, null);
        while (iter.next()) |e| {
            switch (e.evt) {
                .mouse => |me| {
                    if (me.kind == .focus) {
                        e.handled = true;
                        // focus so that we can receive keyboard input
                        focusWidget(self.wd.id, e.num);
                    } else if (me.kind == .wheel_y) {
                        e.handled = true;
                        if (self.si.vertical != .none) {
                            self.si.viewport.y -= me.kind.wheel_y;
                        }
                        refresh();
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

        switch (self.si.horizontal) {
            .none => {},
            .auto => if (self.nextVirtualSize.w != self.si.virtual_size.w) {
                self.si.virtual_size.w = self.nextVirtualSize.w;
                refresh();
            },
            .given => {},
        }

        switch (self.si.vertical) {
            .none => {},
            .auto => if (self.nextVirtualSize.h != self.si.virtual_size.h) {
                self.si.virtual_size.h = self.nextVirtualSize.h;
                refresh();
            },
            .given => {},
        }

        self.wd.minSizeSetAndCue();
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
        direction: Direction = .vertical,
        focus_id: ?u32 = null,
    };

    wd: WidgetData = undefined,
    process_events: bool = true,
    grabRect: Rect = Rect{},
    si: *ScrollInfo = undefined,
    focus_id: ?u32 = null,
    dir: Direction = undefined,
    highlight: bool = false,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        var self = Self{};
        const options = defaults.override(opts);
        self.wd = WidgetData.init(src, options);

        self.si = init_opts.scroll_info;
        self.focus_id = init_opts.focus_id;
        self.dir = init_opts.direction;
        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        self.process_events = opts.process_events;
        try self.wd.register("ScrollBar", null);
        try self.wd.borderAndBackground(.{});

        const captured = captureMouseMaintain(self.wd.id);

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

        var fill = self.wd.options.color(.text).transparent(0.5);
        if (captured or self.highlight) {
            fill = self.wd.options.color(.text).transparent(0.3);
        }
        self.grabRect = self.grabRect.insetAll(2);
        const grabrs = self.wd.parent.screenRectScale(self.grabRect);
        try pathAddRect(grabrs.r, Rect.all(100));
        try pathFillConvex(fill);
    }

    pub fn data(self: *Self) *WidgetData {
        return &self.wd;
    }

    pub fn processEvents(self: *Self, grabrs: Rect) void {
        const rs = self.wd.borderRectScale();
        var iter = EventIterator.init(self.data().id, rs.r, null);
        while (iter.next()) |e| {
            switch (e.evt) {
                .mouse => |me| {
                    switch (me.kind) {
                        .focus => {
                            if (self.focus_id) |fid| {
                                e.handled = true;
                                focusWidget(fid, e.num);
                            }
                        },
                        .press => {
                            if (e.evt.mouse.kind.press == .left) {
                                e.handled = true;
                                if (grabrs.contains(e.evt.mouse.p)) {
                                    // capture and start drag
                                    _ = captureMouse(self.data().id);
                                    switch (self.dir) {
                                        .vertical => dragPreStart(e.evt.mouse.p, .arrow, .{ .y = e.evt.mouse.p.y - (grabrs.y + grabrs.h / 2) }),
                                        .horizontal => dragPreStart(e.evt.mouse.p, .arrow, .{ .x = e.evt.mouse.p.x - (grabrs.x + grabrs.w / 2) }),
                                    }
                                } else {
                                    var fi = self.si.fraction_visible(self.dir);
                                    // the last page is scroll fraction 1.0, so there is
                                    // one less scroll position between 0 and 1.0
                                    fi = 1.0 / ((1.0 / fi) - 1);
                                    var f: f32 = undefined;
                                    if (if (self.dir == .vertical) (e.evt.mouse.p.y < grabrs.y) else (e.evt.mouse.p.x < grabrs.x)) {
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
                            if (e.evt.mouse.kind.release == .left) {
                                e.handled = true;
                                // stop possible drag and capture
                                _ = captureMouse(null);
                                dragEnd();
                            }
                        },
                        .motion => {
                            e.handled = true;
                            // move if dragging
                            if (dragging(e.evt.mouse.p)) |dps| {
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
                                    .vertical => e.evt.mouse.p.y - dragOffset().y,
                                    .horizontal => e.evt.mouse.p.x - dragOffset().x,
                                };
                                var f: f32 = 0;
                                if (max > min) {
                                    f = (grabmid - min) / (max - min);
                                }
                                self.si.scrollToFraction(self.dir, f);
                                refresh();
                            }
                        },
                        .position => {
                            e.handled = true;
                            self.highlight = true;
                        },
                        .wheel_y => |ticks| {
                            e.handled = true;
                            switch (self.dir) {
                                .vertical => self.si.viewport.y -= ticks,
                                .horizontal => self.si.viewport.x -= ticks,
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
        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();
    }
};

pub fn separator(src: std.builtin.SourceLocation, opts: Options) !void {
    const defaults: Options = .{
        .background = true, // TODO: remove this when border and background are no longer coupled
        .border = .{ .x = 1, .y = 1, .w = 0, .h = 0 },
        .color_style = .content,
    };

    var wd = WidgetData.init(src, defaults.override(opts));
    try wd.register("Separator", null);
    try wd.borderAndBackground(.{});
    wd.minSizeSetAndCue();
    wd.minSizeReportToParent();
}

pub fn spacer(src: std.builtin.SourceLocation, size: Size, opts: Options) WidgetData {
    if (opts.min_size_content != null) {
        std.debug.print("warning: spacer options had min_size but is being overwritten\n", .{});
    }
    var wd = WidgetData.init(src, opts.override(.{ .min_size_content = size }));
    wd.register("Spacer", null) catch {};
    wd.minSizeSetAndCue();
    wd.minSizeReportToParent();
    return wd;
}

pub fn spinner(src: std.builtin.SourceLocation, opts: Options) !void {
    var defaults: Options = .{
        .min_size_content = .{ .w = 50, .h = 50 },
    };
    const options = defaults.override(opts);
    var wd = WidgetData.init(src, options);
    try wd.register("Spinner", null);
    wd.minSizeSetAndCue();
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
    try pathAddArc(center, math.min(r.w, r.h) / 3, angle, 0, false);
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

    pub fn init(src: std.builtin.SourceLocation, scale_in: f32, opts: Options) Self {
        var self = Self{};
        self.wd = WidgetData.init(src, opts);
        self.scale = scale_in;
        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());
        try self.wd.register("Scale", null);
        try self.wd.borderAndBackground(.{});
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
        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);
    }
};

pub fn menu(src: std.builtin.SourceLocation, dir: Direction, opts: Options) !*MenuWidget {
    var ret = try currentWindow().arena.create(MenuWidget);
    ret.* = MenuWidget.init(src, dir, opts);
    try ret.install(.{});
    return ret;
}

pub const MenuWidget = struct {
    const Self = @This();

    wd: WidgetData = undefined,

    winId: u32 = undefined,
    dir: Direction = undefined,
    parentMenu: ?*MenuWidget = null,
    box: BoxWidget = undefined,

    submenus_activated: bool = false,

    pub fn init(src: std.builtin.SourceLocation, dir: Direction, opts: Options) MenuWidget {
        var self = Self{};
        self.wd = WidgetData.init(src, opts);

        self.winId = subwindowCurrentId();
        self.dir = dir;
        if (dataGet(null, self.wd.id, "_sub_act", bool)) |a| {
            self.submenus_activated = a;
            //std.debug.print("menu dataGet {x} {}\n", .{self.wd.id, self.submenus_activated});
        } else if (menuGet()) |m| {
            self.submenus_activated = m.submenus_activated;
            //std.debug.print("menu menuGet {x} {}\n", .{self.wd.id, self.submenus_activated});
        }

        return self;
    }

    pub fn install(self: *Self, opts: struct {}) !void {
        _ = opts;
        _ = parentSet(self.widget());
        self.parentMenu = menuSet(self);
        try self.wd.register("Menu", null);
        try self.wd.borderAndBackground(.{});

        self.box = BoxWidget.init(@src(), self.dir, false, self.wd.options.strip());
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
        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();
        _ = menuSet(self.parentMenu);
        _ = parentSet(self.wd.parent);
    }
};

pub fn menuItemLabel(src: std.builtin.SourceLocation, label_str: []const u8, submenu: bool, opts: Options) !?Rect {
    var mi = try menuItem(src, submenu, opts);

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

pub fn menuItemIcon(src: std.builtin.SourceLocation, submenu: bool, name: []const u8, tvg_bytes: []const u8, opts: Options) !?Rect {
    var mi = try menuItem(src, submenu, opts);

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

pub fn menuItem(src: std.builtin.SourceLocation, submenu: bool, opts: Options) !*MenuItemWidget {
    var ret = try currentWindow().arena.create(MenuItemWidget);
    ret.* = MenuItemWidget.init(src, submenu, opts);
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

    wd: WidgetData = undefined,
    focused_in_win: bool = false,
    highlight: bool = false,
    submenu: bool = false,
    activated: bool = false,
    show_active: bool = false,

    pub fn init(src: std.builtin.SourceLocation, submenu: bool, opts: Options) Self {
        var self = Self{};
        const options = defaults.override(opts);
        self.wd = WidgetData.init(src, options);
        self.submenu = submenu;
        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        try self.wd.register("MenuItem", null);

        if (self.wd.visible()) {
            try tabIndexSet(self.wd.id, self.wd.options.tab_index);
        }

        if (opts.process_events) {
            var iter = EventIterator.init(self.data().id, self.data().borderRectScale().r, null);
            while (iter.next()) |e| {
                self.processEvent(e, false);
            }
        }

        if (self.wd.id == focusedWidgetIdInCurrentSubwindow()) {
            self.focused_in_win = true;
        }

        if (self.wd.options.borderGet().nonZero()) {
            const rs = self.wd.borderRectScale();
            try pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
            var col = self.wd.options.color(.border);
            try pathFillConvex(col);
        }

        var focused: bool = false;
        if (self.wd.id == focusedWidgetId()) {
            focused = true;
        }

        if (focused or (self.focused_in_win and self.highlight)) {
            if (!self.submenu or !menuGet().?.submenus_activated) {
                self.show_active = true;
            }
        }

        if (self.show_active) {
            const rs = self.wd.backgroundRectScale();
            try pathAddRect(rs.r, self.wd.options.corner_radiusGet().scale(rs.s));
            try pathFillConvex(self.wd.options.color(.accent));
        } else if (self.focused_in_win or self.highlight) {
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
        if (self.submenu) {
            if (menuGet().?.submenus_activated and self.focused_in_win) {
                act = true;
            }
        } else if (self.activated) {
            act = true;
        }

        if (act) {
            const rs = self.wd.borderRectScale();
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
                if (me.kind == .focus) {
                    e.handled = true;
                } else if (me.kind == .press and me.kind.press == .left) {
                    e.handled = true;
                    if (self.submenu) {
                        focusSubwindow(null, null); // focuses the window we are in
                        focusWidget(self.wd.id, e.num);
                        menuGet().?.submenus_activated = !menuGet().?.submenus_activated;
                    }
                } else if (me.kind == .release and me.kind.release == .left) {
                    e.handled = true;
                    if (!self.submenu) {
                        self.activated = true;
                    }
                } else if (me.kind == .position) {
                    e.handled = true;
                    self.highlight = true;

                    // We get a .position mouse event every frame.  If we
                    // focus the menu item under the mouse even if it's not
                    // moving then it breaks keyboard navigation.
                    if (mouseTotalMotion().nonZero()) {
                        // TODO don't do the rest here if the menu has an existing popup and the motion is towards the popup
                        focusSubwindow(null, null); // focuses the window we are in
                        focusWidget(self.wd.id, null);
                    }
                }
            },
            .key => |ke| {
                if (ke.code == .space and ke.action == .down) {
                    e.handled = true;
                    if (self.submenu) {
                        menuGet().?.submenus_activated = true;
                    } else {
                        self.activated = true;
                    }
                } else if (ke.code == .right and ke.action == .down) {
                    e.handled = true;
                    if (self.submenu) {
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
        self.wd.minSizeSetAndCue();
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

        var iter = std.mem.split(u8, self.label_str, "\n");
        var first: bool = true;
        var size = Size{};
        while (iter.next()) |line| {
            const s = try options.fontGet().textSize(line);
            if (first) {
                first = false;
                size = s;
            } else {
                size.h += try options.fontGet().lineSkip();
                size.w = math.max(size.w, s.w);
            }
        }

        size = Size.max(size, options.min_size_contentGet());

        self.wd = WidgetData.init(src, options.override(.{ .min_size_content = size }));

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
            });
            rs.r.y += rs.s * try self.wd.options.fontGet().lineSkip();
        }
        clipSet(oldclip);

        self.wd.minSizeSetAndCue();
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
            size.w = math.max(size.w, iconWidth(name, tvg_bytes, size.h) catch size.w);
        } else {
            // user didn't give us one, make it the height of text
            const h = options.fontGet().lineSkip() catch 10;
            size = Size{ .w = iconWidth(name, tvg_bytes, h) catch h, .h = h };
        }

        self.wd = WidgetData.init(src, options.override(.{ .min_size_content = size }));

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

        self.wd.minSizeSetAndCue();
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
        size.w = math.max(size.w, kv.value_ptr.texture_atlas_size.w);
        size.h += kv.value_ptr.texture_atlas_size.h;
    }

    // this size is a pixel size, so inverse scale to get natural pixels
    const ss = parentGet().screenRectScale(Rect{}).s;
    size = size.scale(1.0 / ss);

    var wd = WidgetData.init(src, opts.override(.{ .min_size_content = size }));
    try wd.register("debugFontAtlases", null);

    try wd.borderAndBackground(.{});

    const rs = wd.parent.screenRectScale(placeIn(wd.contentRect(), size, .none, opts.gravityGet()));
    try debugRenderFontAtlases(rs, opts.color(.text));

    wd.minSizeSetAndCue();
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
    capture: bool = false,
    focus: bool = false,
    click: bool = false,

    pub fn init(src: std.builtin.SourceLocation, opts: Options) Self {
        var self = Self{};
        self.wd = WidgetData.init(src, defaults.override(opts));
        self.capture = captureMouseMaintain(self.wd.id);
        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true, draw_focus: bool = true }) !void {
        try self.wd.register("Button", null);
        _ = parentSet(self.widget());

        if (self.wd.visible()) {
            try tabIndexSet(self.wd.id, self.wd.options.tab_index);
        }

        if (opts.process_events) {
            var iter = EventIterator.init(self.data().id, self.data().borderRectScale().r, null);
            while (iter.next()) |e| {
                self.processEvent(e, false);
            }
        }

        self.focus = (self.wd.id == focusedWidgetId());

        var fill_color: ?Color = null;
        if (self.capture) {
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

    pub fn captured(self: *Self) bool {
        return self.capture;
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
                if (me.kind == .focus) {
                    e.handled = true;
                    focusWidget(self.wd.id, e.num);
                } else if (me.kind == .press and me.kind.press == .left) {
                    e.handled = true;
                    self.capture = captureMouse(self.wd.id);
                } else if (me.kind == .release and me.kind.release == .left) {
                    e.handled = true;
                    if (self.capture) {
                        self.capture = captureMouse(null);
                        if (self.data().borderRectScale().r.contains(me.p)) {
                            self.click = true;
                            refresh();
                        }
                    }
                } else if (me.kind == .position) {
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
        self.wd.minSizeSetAndCue();
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
pub fn slider(src: std.builtin.SourceLocation, dir: gui.Direction, percent: *f32, opts: Options) !bool {
    const options = slider_defaults.override(opts);

    var b = try box(src, dir, options);
    defer b.deinit();

    if (b.data().visible()) {
        try tabIndexSet(b.data().id, options.tab_index);
    }

    var captured = captureMouseMaintain(b.data().id);
    var hovered: bool = false;
    var ret = false;

    const br = b.data().contentRect();
    const knobsize = math.min(br.w, br.h);
    const track = switch (dir) {
        .horizontal => Rect{ .x = knobsize / 2, .y = br.h / 2 - 2, .w = br.w - knobsize, .h = 4 },
        .vertical => Rect{ .x = br.w / 2 - 2, .y = knobsize / 2, .w = 4, .h = br.h - knobsize },
    };

    const trackrs = b.widget().screenRectScale(track);

    const rs = b.data().contentRectScale();
    var iter = EventIterator.init(b.data().id, rs.r, null);
    while (iter.next()) |e| {
        switch (e.evt) {
            .mouse => |me| {
                var p: ?Point = null;
                if (me.kind == .focus) {
                    e.handled = true;
                    focusWidget(b.data().id, e.num);
                } else if (me.kind == .press and me.kind.press == .left) {
                    // capture
                    captured = captureMouse(b.data().id);
                    e.handled = true;
                    p = me.p;
                } else if (me.kind == .release and me.kind.release == .left) {
                    // stop capture
                    captured = captureMouse(null);
                    e.handled = true;
                } else if (me.kind == .motion and captureMouseId() == b.data().id) {
                    // handle only if we have capture
                    e.handled = true;
                    p = me.p;
                } else if (me.kind == .position) {
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
                        percent.* = math.max(0, math.min(1, percent.*));
                        ret = true;
                    }
                }
            },
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .left, .down => {
                            e.handled = true;
                            percent.* = math.max(0, math.min(1, percent.* - 0.05));
                            ret = true;
                        },
                        .right, .up => {
                            e.handled = true;
                            percent.* = math.max(0, math.min(1, percent.* + 0.05));
                            ret = true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    const perc = math.max(0, math.min(1, percent.*));

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
    if (captured) {
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
    .corner_radius = gui.Rect.all(2),
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

    var check_size = try options.fontGet().lineSkip();
    const s = spacer(@src(), Size.all(check_size), .{ .gravity_x = 0.5, .gravity_y = 0.5 });

    var rs = s.borderRectScale();
    rs.r = rs.r.insetAll(0.5 * rs.s);

    try checkmark(target.*, bw.focused(), rs, bw.captured(), bw.hovered(), options);

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
        const pad = math.max(1.0, r.w / 6);

        var thick = math.max(1.0, r.w / 5);
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

pub fn textEntry(src: std.builtin.SourceLocation, init_opts: TextEntryWidget.InitOptions, opts: Options) !void {
    const cw = currentWindow();
    var ret = try cw.arena.create(TextEntryWidget);
    ret.* = TextEntryWidget.init(src, init_opts, opts);
    ret.allocator = cw.arena;
    try ret.install(.{});
    ret.deinit();
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
    };

    pub const InitOptions = struct {
        text: []u8,
    };

    wd: WidgetData = undefined,
    scroll: ScrollAreaWidget = undefined,
    textLayout: TextLayoutWidget = undefined,
    padding: Rect = undefined,

    allocator: ?std.mem.Allocator = null,
    text: []u8 = undefined,
    len: usize = undefined,
    scroll_to_cursor: bool = false,

    pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) Self {
        var self = Self{};
        const msize = opts.fontGet().textSize("M") catch unreachable;
        var options = defaults.override(.{ .min_size_content = .{ .w = msize.w * 14, .h = msize.h } }).override(opts);

        // padding is interpreted as the padding for the TextLayoutWidget, but
        // we also need to add it to content size because TextLayoutWidget is
        // inside the scroll area
        self.padding = options.paddingGet();
        options.padding = null;
        options.min_size_content.?.w += self.padding.x + self.padding.w;
        options.min_size_content.?.h += self.padding.y + self.padding.h;

        self.wd = WidgetData.init(src, options);

        self.text = init_opts.text;
        self.len = std.mem.indexOfScalar(u8, self.text, 0) orelse self.text.len;
        return self;
    }

    pub fn install(self: *Self, opts: struct { process_events: bool = true }) !void {
        try self.wd.register("TextEntry", null);

        if (self.wd.visible()) {
            try tabIndexSet(self.wd.id, self.wd.options.tab_index);
        }

        _ = parentSet(self.widget());

        try self.wd.borderAndBackground(.{});

        const oldclip = clipGet();

        self.scroll = ScrollAreaWidget.init(@src(), null, self.wd.options.strip().override(.{ .expand = .both }));
        // scrollbars process mouse events here
        try self.scroll.install(.{ .focus_id = self.wd.id });

        const scrollclip = clipGet();

        self.textLayout = TextLayoutWidget.init(@src(), .{}, self.wd.options.strip().override(.{ .expand = .both, .padding = self.padding }));
        try self.textLayout.install(.{ .process_events = false });

        // textLayout clips to its content, but we need to get events out to our border
        const textclip = clipGet();
        clipSet(oldclip);

        if (opts.process_events) {
            var iter = EventIterator.init(self.data().id, self.data().borderRectScale().r, self.textLayout.data().id);
            while (iter.next()) |e| {
                self.processEvent(e, false);
                if (!e.handled) {
                    self.scroll.scroll.processEvent(e, false);
                }
                if (!e.handled) {
                    self.textLayout.processEvent(e, false);
                }
            }
        }

        const focused = (self.wd.id == focusedWidgetId());

        // set clip back to what textLayout expects
        clipSet(textclip);

        try self.textLayout.addText(self.text[0..self.len], self.wd.options.strip());
        try self.textLayout.addTextDone(self.wd.options.strip());

        if (focused) {
            if (self.textLayout.cursor_rect) |cr| {
                // might draw the cursor slightly outside TextLayoutWidget's
                // clipping, so go back to scroll clipping
                clipSet(scrollclip);

                const crect = cr.add(.{ .x = -1 });
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

    pub fn processEvent(self: *Self, e: *Event, bubbling: bool) void {
        _ = bubbling;
        switch (e.evt) {
            .key => |ke| {
                switch (ke.code) {
                    .backspace => {
                        if (ke.action == .down or ke.action == .repeat) {
                            e.handled = true;
                            if (self.textLayout.selectionGet(.{})) |sel| {
                                if (sel.start != sel.end) {
                                    // just delete selection
                                    std.mem.copy(u8, self.text[sel.start..], self.text[sel.end..self.len]);
                                    self.len -= (sel.end - sel.start);
                                    self.text[self.len] = 0;
                                    sel.end = sel.start;
                                    sel.cursor = sel.start;
                                } else if (sel.cursor > 0) {
                                    // delete character just before cursor
                                    std.mem.copy(u8, self.text[sel.cursor - 1 ..], self.text[sel.cursor..self.len]);
                                    self.len -= 1;
                                    self.text[self.len] = 0;
                                    sel.cursor -= 1;
                                    sel.start = sel.cursor;
                                    sel.end = sel.cursor;
                                }
                            }
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
                        if (ke.action == .down and ke.mod.gui()) {
                            // TODO: paste
                            //e.handled = true;
                            //const ct = c.SDL_GetClipboardText();
                            //defer c.SDL_free(ct);

                            //var i = self.len;
                            //while (i < self.text.len and ct.* != 0) : (i += 1) {
                            //  self.text[i] = ct[i - self.len];
                            //}
                            //self.len = i;
                        }
                    },
                    .left, .right => |code| {
                        if ((ke.action == .down or ke.action == .repeat) and !ke.mod.shift()) {
                            e.handled = true;
                            if (self.textLayout.selectionGet(.{})) |sel| {
                                if (code == .left) {
                                    sel.cursor -|= 1;
                                } else {
                                    sel.cursor += 1;
                                    sel.cursor = @min(sel.cursor, self.len);
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
                if (self.textLayout.selectionGet(.{})) |sel| {
                    var new = std.mem.sliceTo(te, 0);
                    if (sel.start != sel.end) {
                        // delete selection
                        std.mem.copy(u8, self.text[sel.start..], self.text[sel.end..self.len]);
                        self.len -= (sel.end - sel.start);
                        sel.end = sel.start;
                        sel.cursor = sel.start;
                    }
                    new.len = math.min(new.len, self.text.len - self.len);

                    // make room if we can
                    if (sel.cursor + new.len < self.text.len) {
                        std.mem.copyBackwards(u8, self.text[sel.cursor + new.len ..], self.text[sel.cursor..self.len]);
                    }

                    // update our len and maintain 0 termination if possible
                    self.len += new.len;
                    if (self.len < self.text.len) {
                        self.text[self.len] = 0;
                    }

                    // insert
                    std.mem.copy(u8, self.text[sel.cursor..], new);
                    sel.cursor += new.len;
                    sel.end = sel.cursor;
                    sel.start = sel.cursor;

                    // we might have dropped to a new line, so make sure the cursor is visible
                    self.scroll_to_cursor = true;
                }
            },
            .mouse => |me| {
                if (me.kind == .focus) {
                    e.handled = true;
                    focusWidget(self.wd.id, e.num);
                }
            },
            else => {},
        }

        if (e.bubbleable()) {
            self.wd.parent.processEvent(e, true);
        }
    }

    pub fn deinit(self: *Self) void {
        self.wd.minSizeSetAndCue();
        self.wd.minSizeReportToParent();
        _ = parentSet(self.wd.parent);

        if (self.allocator) |a| {
            a.destroy(self);
        }
    }
};

pub const Color = struct {
    r: u8 = 0xff,
    g: u8 = 0xff,
    b: u8 = 0xff,
    a: u8 = 0xff,

    pub fn transparent(x: Color, y: f32) Color {
        return Color{
            .r = x.r,
            .g = x.g,
            .b = x.b,
            .a = @floatToInt(u8, @intToFloat(f32, x.a) * y),
        };
    }

    pub fn darken(x: Color, y: f32) Color {
        return Color{
            .r = @floatToInt(u8, math.max(@intToFloat(f32, x.r) * (1 - y), 0)),
            .g = @floatToInt(u8, math.max(@intToFloat(f32, x.g) * (1 - y), 0)),
            .b = @floatToInt(u8, math.max(@intToFloat(f32, x.b) * (1 - y), 0)),
            .a = x.a,
        };
    }

    pub fn lighten(x: Color, y: f32) Color {
        return Color{
            .r = @floatToInt(u8, math.min(@intToFloat(f32, x.r) * (1 + y), 255)),
            .g = @floatToInt(u8, math.min(@intToFloat(f32, x.g) * (1 + y), 255)),
            .b = @floatToInt(u8, math.min(@intToFloat(f32, x.b) * (1 + y), 255)),
            .a = x.a,
        };
    }

    pub fn lerp(x: Color, y: f32, z: Color) Color {
        return Color{
            .r = @floatToInt(u8, @intToFloat(f32, x.r) * (1 - y) + @intToFloat(f32, z.r) * y),
            .g = @floatToInt(u8, @intToFloat(f32, x.g) * (1 - y) + @intToFloat(f32, z.g) * y),
            .b = @floatToInt(u8, @intToFloat(f32, x.b) * (1 - y) + @intToFloat(f32, z.b) * y),
            .a = @floatToInt(u8, @intToFloat(f32, x.a) * (1 - y) + @intToFloat(f32, z.a) * y),
        };
    }

    pub fn format(self: *const Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Color{{ {x} {x} {x} {x} }}", .{ self.r, self.g, self.b, self.a });
    }

    pub const white = Color{ .r = 0xff, .g = 0xff, .b = 0xff };
    pub const black = Color{ .r = 0x00, .g = 0x00, .b = 0x00 };
};

pub const Point = struct {
    const Self = @This();
    x: f32 = 0,
    y: f32 = 0,

    pub fn nonZero(self: *const Self) bool {
        return (self.x != 0 or self.y != 0);
    }

    pub fn inRectScale(self: *const Self, rs: RectScale) Self {
        return Self{ .x = (self.x - rs.r.x) / rs.s, .y = (self.y - rs.r.y) / rs.s };
    }

    pub fn plus(self: *const Self, b: Self) Self {
        return Self{ .x = self.x + b.x, .y = self.y + b.y };
    }

    pub fn diff(a: Self, b: Self) Self {
        return Self{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(self: *const Self, s: f32) Self {
        return Self{ .x = self.x * s, .y = self.y * s };
    }

    pub fn equals(self: *const Self, b: Self) bool {
        return (self.x == b.x and self.y == b.y);
    }

    pub fn length(self: *const Self) f32 {
        return @sqrt((self.x * self.x) + (self.y * self.y));
    }

    pub fn normalize(self: *const Self) Self {
        const d2 = self.x * self.x + self.y * self.y;
        if (d2 == 0) {
            return Self{ .x = 1.0, .y = 0.0 };
        } else {
            const inv_len = 1.0 / @sqrt(d2);
            return Self{ .x = self.x * inv_len, .y = self.y * inv_len };
        }
    }

    pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Point{{ {d} {d} }}", .{ self.x, self.y });
    }
};

pub const Size = struct {
    const Self = @This();
    w: f32 = 0,
    h: f32 = 0,

    pub fn all(v: f32) Self {
        return Self{ .w = v, .h = v };
    }

    pub fn rect(self: *const Self) Rect {
        return Rect{ .x = 0, .y = 0, .w = self.w, .h = self.h };
    }

    pub fn ceil(self: *const Self) Self {
        return Self{ .w = @ceil(self.w), .h = @ceil(self.h) };
    }

    pub fn pad(s: *const Self, padding: Rect) Self {
        return Size{ .w = s.w + padding.x + padding.w, .h = s.h + padding.y + padding.h };
    }

    pub fn max(a: Self, b: Self) Self {
        return Self{ .w = math.max(a.w, b.w), .h = math.max(a.h, b.h) };
    }

    pub fn scale(self: *const Self, s: f32) Self {
        return Self{ .w = self.w * s, .h = self.h * s };
    }

    pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Size{{ {d} {d} }}", .{ self.w, self.h });
    }
};

pub const Rect = struct {
    const Self = @This();
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn add(self: *const Self, r: Self) Rect {
        return Self{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w + r.w, .h = self.h + r.h };
    }

    pub fn nonZero(self: *const Self) bool {
        return (self.x != 0 or self.y != 0 or self.w != 0 or self.h != 0);
    }

    pub fn all(v: f32) Self {
        return Self{ .x = v, .y = v, .w = v, .h = v };
    }

    pub fn fromPoint(p: Point) Self {
        return Self{ .x = p.x, .y = p.y };
    }

    pub fn toSize(self: *const Self, s: Size) Self {
        return Self{ .x = self.x, .y = self.y, .w = s.w, .h = s.h };
    }

    pub fn justSize(self: *const Self) Self {
        return Self{ .x = 0, .y = 0, .w = self.w, .h = self.h };
    }

    pub fn topleft(self: *const Self) Point {
        return Point{ .x = self.x, .y = self.y };
    }

    pub fn bottomRight(self: *const Self) Point {
        return Point{ .x = self.x + self.w, .y = self.y + self.h };
    }

    pub fn size(self: *const Self) Size {
        return Size{ .w = self.w, .h = self.h };
    }

    pub fn contains(self: *const Self, p: Point) bool {
        return (p.x >= self.x and p.x <= (self.x + self.w) and p.y >= self.y and p.y <= (self.y + self.h));
    }

    pub fn empty(self: *const Self) bool {
        return (self.w == 0 or self.h == 0);
    }

    pub fn scale(self: *const Self, s: f32) Self {
        return Self{ .x = self.x * s, .y = self.y * s, .w = self.w * s, .h = self.h * s };
    }

    pub fn offset(self: *const Self, r: Rect) Self {
        return Self{ .x = self.x + r.x, .y = self.y + r.y, .w = self.w, .h = self.h };
    }

    pub fn intersect(a: Self, b: Self) Self {
        const ax2 = a.x + a.w;
        const ay2 = a.y + a.h;
        const bx2 = b.x + b.w;
        const by2 = b.y + b.h;
        const x = math.max(a.x, b.x);
        const y = math.max(a.y, b.y);
        const x2 = math.min(ax2, bx2);
        const y2 = math.min(ay2, by2);
        return Self{ .x = x, .y = y, .w = math.max(0, x2 - x), .h = math.max(0, y2 - y) };
    }

    pub fn shrinkToSize(self: *const Self, s: Size) Self {
        return Self{ .x = self.x, .y = self.y, .w = math.min(self.w, s.w), .h = math.min(self.h, s.h) };
    }

    pub fn inset(self: *const Self, r: Rect) Self {
        return Self{ .x = self.x + r.x, .y = self.y + r.y, .w = math.max(0, self.w - r.x - r.w), .h = math.max(0, self.h - r.y - r.h) };
    }

    pub fn insetAll(self: *const Self, p: f32) Self {
        return self.inset(Rect.all(p));
    }

    pub fn outset(self: *const Self, r: Rect) Self {
        return Self{ .x = self.x - r.x, .y = self.y - r.y, .w = self.w + r.x + r.w, .h = self.h + r.y + r.h };
    }

    pub fn outsetAll(self: *const Self, p: f32) Self {
        return self.outset(Rect.all(p));
    }

    pub fn format(self: *const Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Rect{{ {d} {d} {d} {d} }}", .{ self.x, self.y, self.w, self.h });
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
};

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
        _ = try fce.glyphInfoGet(@intCast(u32, codepoint), opts.font.name);
    }

    // number of extra pixels to add on each side of each glyph
    const pad = 1;

    if (fce.texture_atlas_regen) {
        fce.texture_atlas_regen = false;
        cw.backend.textureDestroy(fce.texture_atlas);

        const row_glyphs = @floatToInt(u32, @ceil(@sqrt(@intToFloat(f32, fce.glyph_info.count()))));

        var size = Size{};
        {
            var it = fce.glyph_info.valueIterator();
            var i: u32 = 0;
            var rowlen: f32 = 0;
            while (it.next()) |gi| {
                if (i % row_glyphs == 0) {
                    size.w = math.max(size.w, rowlen);
                    size.h += fce.height + 2 * pad;
                    rowlen = 0;
                }

                rowlen += (gi.maxx - gi.minx) + 2 * pad;
                i += 1;
            } else {
                size.w = math.max(size.w, rowlen);
            }

            size = size.ceil();
        }

        // also add an extra padding around whole texture
        size.w += 2 * pad;
        size.h += 2 * pad;

        var pixels = try cw.arena.alloc(u8, @floatToInt(usize, size.w * size.h) * 4);
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
                e.value_ptr.uv[0] = @intToFloat(f32, x) / size.w;
                e.value_ptr.uv[1] = @intToFloat(f32, y) / size.h;

                const codepoint = @intCast(u32, e.key_ptr.*);
                FontCacheEntry.intToError(c.FT_Load_Char(fce.face, codepoint, @bitCast(i32, FontCacheEntry.LoadFlags{ .render = true }))) catch |err| {
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
                        const src = bitmap.buffer[@intCast(usize, row * bitmap.pitch + col)];

                        // because of the extra edge, offset by 1 row and 1 col
                        const di = @intCast(usize, (y + row + pad) * @floatToInt(i32, size.w) * 4 + (x + col + pad) * 4);

                        // not doing premultiplied alpha (yet), so keep the white color but adjust the alpha
                        //pixels[di] = src;
                        //pixels[di+1] = src;
                        //pixels[di+2] = src;
                        pixels[di + 3] = src;
                    }
                }

                x += @intCast(i32, bitmap.width) + 2 * pad;

                i += 1;
                if (i % row_glyphs == 0) {
                    x = pad;
                    y += @floatToInt(i32, fce.height) + 2 * pad;
                }
            }
        }

        fce.texture_atlas = cw.backend.textureCreate(pixels, @floatToInt(u32, size.w), @floatToInt(u32, size.h));
        fce.texture_atlas_size = size;
    }

    //std.debug.print("creating text texture size {} font size {d} for \"{s}\"\n", .{size, font.size, text});
    var vtx = std.ArrayList(Vertex).init(cw.arena);
    defer vtx.deinit();
    var idx = std.ArrayList(u32).init(cw.arena);
    defer idx.deinit();

    var x: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.x) else opts.rs.r.x;
    var y: f32 = if (cw.snap_to_pixels) @round(opts.rs.r.y) else opts.rs.r.y;

    var sel: bool = false;
    var sel_in: bool = false;
    var sel_start_x: f32 = x;
    var sel_end_x: f32 = x;
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
        const gi = try fce.glyphInfoGet(@intCast(u32, codepoint), opts.font.name);

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

        const len = @intCast(u32, vtx.items.len);
        var v: Vertex = undefined;

        v.pos.x = x + (gi.minx - pad) * target_fraction;
        v.pos.y = y + (gi.miny - pad) * target_fraction;
        v.col = if (sel_in) opts.sel_color orelse opts.color else opts.color;
        v.uv = gi.uv;
        try vtx.append(v);

        v.pos.x = x + (gi.maxx + pad) * target_fraction;
        v.uv[0] = gi.uv[0] + (gi.maxx - gi.minx + 2 * pad) / fce.texture_atlas_size.w;
        try vtx.append(v);

        v.pos.y = y + (gi.maxy + pad) * target_fraction;
        v.uv[1] = gi.uv[1] + (gi.maxy - gi.miny + 2 * pad) / fce.texture_atlas_size.h;
        try vtx.append(v);

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
            sel_vtx[3].pos.y = @max(y, opts.rs.r.y) + fce.height * target_fraction;
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

        const len = @intCast(u32, vtx.items.len);
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

    const ice = iconTexture(name, tvg_bytes, @floatToInt(u32, ask_height)) catch return;

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
        pub const Kind = union(enum) {
            // Focus events come right before their associated mouse event, usually
            // leftdown/rightdown or motion. Separated to enable changing what
            // causes focus changes.
            focus: enums.Button,
            press: enums.Button,
            release: enums.Button,
            wheel_y: f32,

            // motion Point is the change in position
            // if you just want to react to the current mouse position if it got
            // moved at all, use the .position event with mouseTotalMotion()
            motion: Point,

            // only one position event per frame, and it's always after all other
            // mouse events, used to change mouse cursor and do widget highlighting
            // - also useful with mouseTotalMotion() to respond to mouse motion but
            // only at the final location
            position: void,
        };

        p: Point,
        floating_win: u32,
        kind: Kind,
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
    id: u32 = undefined,
    parent: Widget = undefined,
    rect: Rect = Rect{},
    min_size: Size = Size{},
    options: Options = undefined,

    pub fn init(src: std.builtin.SourceLocation, opts: Options) WidgetData {
        var self = WidgetData{};
        self.options = opts;

        self.parent = parentGet();
        self.id = self.parent.extendID(src, opts.idExtra());

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
                cw.debug_info_name_rect = try std.fmt.allocPrint(cw.arena, "{x} {s}\n\n{}\nmargin {}\npadding {}", .{ self.id, name, rs.r, self.options.marginGet(), self.options.paddingGet() });
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
        return self.parent.screenRectScale(self.rect);
    }

    pub fn borderRect(self: *const WidgetData) Rect {
        return self.rect.inset(self.options.marginGet());
    }

    pub fn borderRectScale(self: *const WidgetData) RectScale {
        return self.parent.screenRectScale(self.borderRect());
    }

    pub fn backgroundRect(self: *const WidgetData) Rect {
        return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet());
    }

    pub fn backgroundRectScale(self: *const WidgetData) RectScale {
        return self.parent.screenRectScale(self.backgroundRect());
    }

    pub fn contentRect(self: *const WidgetData) Rect {
        return self.rect.inset(self.options.marginGet()).inset(self.options.borderGet()).inset(self.options.paddingGet());
    }

    pub fn contentRectScale(self: *const WidgetData) RectScale {
        return self.parent.screenRectScale(self.contentRect());
    }

    pub fn padSize(self: *const WidgetData, s: Size) Size {
        return s.pad(self.options.paddingGet()).pad(self.options.borderGet()).pad(self.options.marginGet());
    }

    pub fn minSizeMax(self: *WidgetData, s: Size) void {
        self.min_size = Size.max(self.min_size, s);
    }

    pub fn minSizeSetAndCue(self: *const WidgetData) void {
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
                //std.debug.print("{x} minSizeSetAndCue {} {} {}\n", .{ self.id, self.rect, ms, self.min_size });

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
                std.debug.print("minSizeSetAndCue: got {!} when trying to minSizeSet widget {x}\n", .{ err, self.id });
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
        const alignment = ptr_info.Pointer.alignment;

        const gen = struct {
            fn dataImpl(ptr: *anyopaque) *WidgetData {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, dataFn, .{self});
            }

            fn rectForImpl(ptr: *anyopaque, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, rectForFn, .{ self, id, min_size, e, g });
            }

            fn screenRectScaleImpl(ptr: *anyopaque, r: Rect) RectScale {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, screenRectScaleFn, .{ self, r });
            }

            fn minSizeForChildImpl(ptr: *anyopaque, s: Size) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, minSizeForChildFn, .{ self, s });
            }

            fn processEventImpl(ptr: *anyopaque, e: *Event, bubbling: bool) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
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

    pub fn extendID(self: Widget, src: std.builtin.SourceLocation, id_extra: usize) u32 {
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

pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        begin: *const fn (ptr: *anyopaque, arena: std.mem.Allocator) void,
        end: *const fn (ptr: *anyopaque) void,
        pixelSize: *const fn (ptr: *anyopaque) Size,
        windowSize: *const fn (ptr: *anyopaque) Size,
        renderGeometry: *const fn (ptr: *anyopaque, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void,
        textureCreate: *const fn (ptr: *anyopaque, pixels: []u8, width: u32, height: u32) *anyopaque,
        textureDestroy: *const fn (ptr: *anyopaque, texture: *anyopaque) void,
    };

    pub fn init(
        pointer: anytype,
        comptime beginFn: fn (ptr: @TypeOf(pointer), arena: std.mem.Allocator) void,
        comptime endFn: fn (ptr: @TypeOf(pointer)) void,
        comptime pixelSizeFn: fn (ptr: @TypeOf(pointer)) Size,
        comptime windowSizeFn: fn (ptr: @TypeOf(pointer)) Size,
        comptime renderGeometryFn: fn (ptr: @TypeOf(pointer), texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void,
        comptime textureCreateFn: fn (ptr: @TypeOf(pointer), pixels: []u8, width: u32, height: u32) *anyopaque,
        comptime textureDestroyFn: fn (ptr: @TypeOf(pointer), texture: *anyopaque) void,
    ) Backend {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);
        std.debug.assert(ptr_info == .Pointer); // Must be a pointer
        std.debug.assert(ptr_info.Pointer.size == .One); // Must be a single-item pointer
        const alignment = ptr_info.Pointer.alignment;

        const gen = struct {
            fn beginImpl(ptr: *anyopaque, arena: std.mem.Allocator) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, beginFn, .{ self, arena });
            }

            fn endImpl(ptr: *anyopaque) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, endFn, .{self});
            }

            fn pixelSizeImpl(ptr: *anyopaque) Size {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, pixelSizeFn, .{self});
            }

            fn windowSizeImpl(ptr: *anyopaque) Size {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, windowSizeFn, .{self});
            }

            fn renderGeometryImpl(ptr: *anyopaque, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, renderGeometryFn, .{ self, texture, vtx, idx });
            }

            fn textureCreateImpl(ptr: *anyopaque, pixels: []u8, width: u32, height: u32) *anyopaque {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, textureCreateFn, .{ self, pixels, width, height });
            }

            fn textureDestroyImpl(ptr: *anyopaque, texture: *anyopaque) void {
                const self = @ptrCast(Ptr, @alignCast(alignment, ptr));
                return @call(.always_inline, textureDestroyFn, .{ self, texture });
            }

            const vtable = VTable{
                .begin = beginImpl,
                .end = endImpl,
                .pixelSize = pixelSizeImpl,
                .windowSize = windowSizeImpl,
                .renderGeometry = renderGeometryImpl,
                .textureCreate = textureCreateImpl,
                .textureDestroy = textureDestroyImpl,
            };
        };

        return .{
            .ptr = pointer,
            .vtable = &gen.vtable,
        };
    }

    pub fn begin(self: *Backend, arena: std.mem.Allocator) void {
        self.vtable.begin(self.ptr, arena);
    }

    pub fn end(self: *Backend) void {
        self.vtable.end(self.ptr);
    }

    pub fn pixelSize(self: *Backend) Size {
        return self.vtable.pixelSize(self.ptr);
    }

    pub fn windowSize(self: *Backend) Size {
        return self.vtable.windowSize(self.ptr);
    }

    pub fn renderGeometry(self: *Backend, texture: ?*anyopaque, vtx: []const Vertex, idx: []const u32) void {
        self.vtable.renderGeometry(self.ptr, texture, vtx, idx);
    }

    pub fn textureCreate(self: *Backend, pixels: []u8, width: u32, height: u32) *anyopaque {
        return self.vtable.textureCreate(self.ptr, pixels, width, height);
    }

    pub fn textureDestroy(self: *Backend, texture: *anyopaque) void {
        self.vtable.textureDestroy(self.ptr, texture);
    }
};

pub const examples = struct {
    pub var show_demo_window: bool = false;
    var checkbox_bool: bool = false;
    var slider_val: f32 = 0.0;
    var text_entry_buf = std.mem.zeroes([30]u8);
    var show_dialog: bool = false;
    var scale_val: f32 = 1.0;

    const IconBrowser = struct {
        var show: bool = false;
        var rect = gui.Rect{};
        var row_height: f32 = 0;
    };

    const AnimatingDialog = struct {
        pub fn dialogDisplay(id: u32) !void {
            const modal = gui.dataGet(null, id, "_modal", bool) orelse unreachable;
            const title = gui.dataGet(null, id, "_title", []const u8) orelse unreachable;
            const message = gui.dataGet(null, id, "_message", []const u8) orelse unreachable;
            const callafter = gui.dataGet(null, id, "_callafter", DialogCallAfterFn);

            // once we record a response, refresh it until we close
            _ = gui.dataGet(null, id, "response", gui.DialogResponse);

            var win = FloatingWindowWidget.init(@src(), .{ .modal = modal }, .{ .id_extra = id });
            const first_frame = gui.firstFrame(win.data().id);

            // On the first frame the window size will be 0 so you won't see
            // anything, but we need the scaleval to be 1 so the window will
            // calculate its min_size correctly.
            var scaleval: f32 = 1.0;

            // To animate a window, we need both a percent and a target window
            // size (see calls to animate below).
            if (gui.animationGet(win.data().id, "rect_percent")) |a| {
                if (gui.dataGet(null, win.data().id, "window_size", Size)) |target_size| {
                    scaleval = a.lerp();

                    // since the window is animating, calculate the center to
                    // animate around that
                    var r = win.data().rect;
                    r.x += r.w / 2;
                    r.y += r.h / 2;

                    const dw = target_size.w * scaleval;
                    const dh = target_size.h * scaleval;
                    r.x -= dw / 2;
                    r.w = dw;
                    r.y -= dh / 2;
                    r.h = dh;

                    win.data().rect = r;

                    if (a.done() and a.end_val == 0) {
                        win.close();
                        gui.dialogRemove(id);

                        if (callafter) |ca| {
                            const response = gui.dataGet(null, id, "response", gui.DialogResponse) orelse {
                                std.debug.print("Error: no response for dialog {x}\n", .{id});
                                return;
                            };
                            try ca(id, response);
                        }

                        return;
                    }
                }
            }

            try win.install(.{});

            var scaler = try gui.scale(@src(), scaleval, .{ .expand = .horizontal });

            var vbox = try gui.box(@src(), .vertical, .{ .expand = .horizontal });

            var closing: bool = false;

            var header_openflag = true;
            try gui.windowHeader(title, "", &header_openflag);
            if (!header_openflag) {
                closing = true;
                gui.dataSet(null, id, "response", gui.DialogResponse.closed);
            }

            var tl = try gui.textLayout(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .w = 250 }, .background = false });
            try tl.addText(message, .{});
            tl.deinit();

            if (try gui.button(@src(), "Ok", .{ .gravity_x = 0.5, .gravity_y = 0.5, .tab_index = 1 })) {
                closing = true;
                gui.dataSet(null, id, "response", gui.DialogResponse.ok);
            }

            vbox.deinit();
            scaler.deinit();
            win.deinit();

            if (first_frame) {
                // On the first frame, scaler will have a scale value of 1 so
                // the min size of the window is our target, which is why we do
                // this after win.deinit so the min size will be available
                gui.animation(win.wd.id, "rect_percent", gui.Animation{ .start_val = 0, .end_val = 1.0, .end_time = 150_000 });
                gui.dataSet(null, win.data().id, "window_size", win.data().min_size);
            }

            if (closing) {
                // If we are closing, start from our current size
                gui.animation(win.wd.id, "rect_percent", gui.Animation{ .start_val = 1.0, .end_val = 0, .end_time = 150_000 });
                gui.dataSet(null, win.data().id, "window_size", win.data().rect.size());
            }
        }

        pub fn after(id: u32, response: gui.DialogResponse) gui.Error!void {
            _ = id;
            std.debug.print("You clicked \"{s}\"\n", .{@tagName(response)});
        }
    };

    pub fn demo() !void {
        if (!show_demo_window) {
            return;
        }

        var float = try gui.floatingWindow(@src(), .{ .open_flag = &show_demo_window }, .{ .min_size_content = .{ .w = 400, .h = 400 } });
        defer float.deinit();

        var buf: [100]u8 = undefined;
        const fps_str = std.fmt.bufPrint(&buf, "{d:4.0} fps", .{gui.FPS()}) catch unreachable;
        try gui.windowHeader("GUI Demo", fps_str, &show_demo_window);

        var ti = gui.toastsFor(float.data().id);
        if (ti) |*it| {
            var toast_win = FloatingWindowWidget.init(@src(), .{ .stay_above_parent = true }, .{ .background = false, .border = .{} });
            defer toast_win.deinit();

            toast_win.data().rect = gui.placeIn(float.data().rect, toast_win.data().rect.size(), .none, .{ .x = 0.5, .y = 0.7 });
            toast_win.autoSize();
            try toast_win.install(.{ .process_events = false });

            var vbox = try gui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            while (it.next()) |t| {
                try t.display(t.id);
            }
        }

        var scroll = try gui.scrollArea(@src(), .{ .expand = .both, .background = false });
        defer scroll.deinit();

        var scaler = try gui.scale(@src(), scale_val, .{ .expand = .horizontal });
        defer scaler.deinit();

        var vbox = try gui.box(@src(), .vertical, .{ .expand = .horizontal });
        defer vbox.deinit();

        if (try gui.button(@src(), "Toggle Debug Window", .{})) {
            gui.toggleDebugWindow();
        }

        if (try gui.expander(@src(), "Basic Widgets", .{ .expand = .horizontal })) {
            try basicWidgets();
        }

        if (try gui.expander(@src(), "Styling", .{ .expand = .horizontal })) {
            try styling();
        }

        if (try gui.expander(@src(), "Layout", .{ .expand = .horizontal })) {
            try layout();
        }

        if (try gui.expander(@src(), "Text Layout", .{ .expand = .horizontal })) {
            try layoutText();
        }

        if (try gui.expander(@src(), "Menus", .{ .expand = .horizontal })) {
            try menus();
        }

        if (try gui.expander(@src(), "Dialogs and Toasts", .{ .expand = .horizontal })) {
            try dialogs(float.data().id);
        }

        if (try gui.expander(@src(), "Animations", .{ .expand = .horizontal })) {
            try animations();
        }

        if (try gui.button(@src(), "Icon Browser", .{})) {
            IconBrowser.show = true;
        }

        if (try gui.button(@src(), "Toggle Theme", .{})) {
            if (gui.themeGet() == &gui.Adwaita.light) {
                gui.themeSet(&gui.Adwaita.dark);
            } else {
                gui.themeSet(&gui.Adwaita.light);
            }
        }

        if (try gui.button(@src(), "Zoom In", .{})) {
            scale_val = @round(themeGet().font_body.size * scale_val + 1.0) / themeGet().font_body.size;

            //std.debug.print("scale {d} {d}\n", .{ scale_val, scale_val * themeGet().font_body.size });
        }

        if (try gui.button(@src(), "Zoom Out", .{})) {
            scale_val = @round(themeGet().font_body.size * scale_val - 1.0) / themeGet().font_body.size;

            //std.debug.print("scale {d} {d}\n", .{ scale_val, scale_val * themeGet().font_body.size });
        }

        try gui.checkbox(@src(), &gui.currentWindow().snap_to_pixels, "Snap to Pixels", .{});
        try gui.labelNoFmt(@src(), "  - watch window title", .{});

        if (try gui.expander(@src(), "Show Font Atlases", .{ .expand = .horizontal })) {
            try debugFontAtlases(@src(), .{});
        }

        if (show_dialog) {
            try dialogDirect();
        }

        if (IconBrowser.show) {
            try icon_browser();
        }
    }

    pub fn basicWidgets() !void {
        var b = try gui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10, .y = 0, .w = 0, .h = 0 } });
        defer b.deinit();
        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            _ = try gui.button(@src(), "Button", .{});
            _ = try gui.button(@src(), "Multi-line\nButton", .{});
            _ = try gui.slider(@src(), .vertical, &slider_val, .{ .expand = .vertical, .min_size_content = .{ .w = 10 } });
        }

        _ = try gui.slider(@src(), .horizontal, &slider_val, .{ .expand = .horizontal });
        try gui.label(@src(), "slider value: {d:2.2}", .{slider_val}, .{});

        try gui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            try gui.label(@src(), "Text Entry", .{}, .{ .gravity_y = 0.5 });
            try gui.textEntry(@src(), .{ .text = &text_entry_buf }, .{});
        }
    }

    pub fn styling() !void {
        try gui.label(@src(), "color style:", .{}, .{});
        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            _ = try gui.button(@src(), "Accent", .{ .color_style = .accent });
            _ = try gui.button(@src(), "Success", .{ .color_style = .success });
            _ = try gui.button(@src(), "Error", .{ .color_style = .err });
            _ = try gui.button(@src(), "Window", .{ .color_style = .window });
            _ = try gui.button(@src(), "Content", .{ .color_style = .content });
            _ = try gui.button(@src(), "Control", .{ .color_style = .control });
        }

        try gui.label(@src(), "margin/border/padding:", .{}, .{});
        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            const opts: Options = .{ .color_style = .content, .border = gui.Rect.all(1), .background = true, .gravity_x = 0.5, .gravity_y = 0.5 };

            var o = try gui.overlay(@src(), opts);
            _ = try gui.button(@src(), "default", .{});
            o.deinit();

            o = try gui.overlay(@src(), opts);
            _ = try gui.button(@src(), "+border", .{ .border = gui.Rect.all(2) });
            o.deinit();

            o = try gui.overlay(@src(), opts);
            _ = try gui.button(@src(), "+padding 10", .{ .border = gui.Rect.all(2), .padding = gui.Rect.all(10) });
            o.deinit();

            o = try gui.overlay(@src(), opts);
            _ = try gui.button(@src(), "+margin 10", .{ .border = gui.Rect.all(2), .margin = gui.Rect.all(10), .padding = gui.Rect.all(10) });
            o.deinit();
        }

        try gui.label(@src(), "corner radius:", .{}, .{});
        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            const opts: Options = .{ .border = gui.Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };

            _ = try gui.button(@src(), "0", opts.override(.{ .corner_radius = gui.Rect.all(0) }));
            _ = try gui.button(@src(), "2", opts.override(.{ .corner_radius = gui.Rect.all(2) }));
            _ = try gui.button(@src(), "7", opts.override(.{ .corner_radius = gui.Rect.all(7) }));
            _ = try gui.button(@src(), "100", opts.override(.{ .corner_radius = gui.Rect.all(100) }));
            _ = try gui.button(@src(), "mixed", opts.override(.{ .corner_radius = .{ .x = 0, .y = 2, .w = 7, .h = 100 } }));
        }
    }

    pub fn layout() !void {
        const opts: Options = .{ .color_style = .content, .border = gui.Rect.all(1), .background = true, .min_size_content = .{ .w = 200, .h = 140 } };

        try gui.label(@src(), "gravity:", .{}, .{});
        {
            var o = try gui.overlay(@src(), opts);
            defer o.deinit();

            var buf: [128]u8 = undefined;

            inline for ([3]f32{ 0.0, 0.5, 1.0 }, 0..) |horz, hi| {
                inline for ([3]f32{ 0.0, 0.5, 1.0 }, 0..) |vert, vi| {
                    _ = try gui.button(@src(), try std.fmt.bufPrint(&buf, "{d},{d}", .{ horz, vert }), .{ .id_extra = hi * 3 + vi, .gravity_x = horz, .gravity_y = vert });
                }
            }
        }

        try gui.label(@src(), "expand:", .{}, .{});
        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();
            {
                var vbox = try gui.box(@src(), .vertical, opts);
                defer vbox.deinit();

                _ = try gui.button(@src(), "none", .{ .expand = .none });
                _ = try gui.button(@src(), "horizontal", .{ .expand = .horizontal });
                _ = try gui.button(@src(), "vertical", .{ .expand = .vertical });
            }
            {
                var vbox = try gui.box(@src(), .vertical, opts);
                defer vbox.deinit();

                _ = try gui.button(@src(), "both", .{ .expand = .both });
            }
        }

        try gui.label(@src(), "boxes:", .{}, .{});
        {
            const grav: Options = .{ .gravity_x = 0.5, .gravity_y = 0.5 };

            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();
            {
                var hbox2 = try gui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 200, .h = 140 } });
                defer hbox2.deinit();
                {
                    var vbox = try gui.box(@src(), .vertical, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                    defer vbox.deinit();

                    _ = try gui.button(@src(), "vertical", grav);
                    _ = try gui.button(@src(), "expand", grav.override(.{ .expand = .vertical }));
                    _ = try gui.button(@src(), "a", grav);
                }

                {
                    var vbox = try gui.boxEqual(@src(), .vertical, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                    defer vbox.deinit();

                    _ = try gui.button(@src(), "vert equal", grav);
                    _ = try gui.button(@src(), "expand", grav.override(.{ .expand = .vertical }));
                    _ = try gui.button(@src(), "a", grav);
                }
            }

            {
                var vbox2 = try gui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 200, .h = 140 } });
                defer vbox2.deinit();
                {
                    var hbox2 = try gui.box(@src(), .horizontal, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                    defer hbox2.deinit();

                    _ = try gui.button(@src(), "horizontal", grav);
                    _ = try gui.button(@src(), "expand", grav.override(.{ .expand = .horizontal }));
                    _ = try gui.button(@src(), "a", grav);
                }

                {
                    var hbox2 = try gui.boxEqual(@src(), .horizontal, opts.override(.{ .expand = .both, .min_size_content = .{} }));
                    defer hbox2.deinit();

                    _ = try gui.button(@src(), "horz\nequal", grav);
                    _ = try gui.button(@src(), "expand", grav.override(.{ .expand = .horizontal }));
                    _ = try gui.button(@src(), "a", grav);
                }
            }
        }
    }

    pub fn layoutText() !void {
        var b = try gui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10, .y = 0, .w = 0, .h = 0 } });
        defer b.deinit();
        try gui.label(@src(), "Title", .{}, .{ .font_style = .title });
        try gui.label(@src(), "Title-1", .{}, .{ .font_style = .title_1 });
        try gui.label(@src(), "Title-2", .{}, .{ .font_style = .title_2 });
        try gui.label(@src(), "Title-3", .{}, .{ .font_style = .title_3 });
        try gui.label(@src(), "Title-4", .{}, .{ .font_style = .title_4 });
        try gui.label(@src(), "Heading", .{}, .{ .font_style = .heading });
        try gui.label(@src(), "Caption-Heading", .{}, .{ .font_style = .caption_heading });
        try gui.label(@src(), "Caption", .{}, .{ .font_style = .caption });
        try gui.label(@src(), "Body", .{}, .{});

        {
            var tl = TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
            try tl.install(.{ .process_events = false });
            defer tl.deinit();

            var cbox = try gui.box(@src(), .vertical, .{});
            if (try gui.buttonIcon(@src(), 18, "play", gui.icons.papirus.actions.media_playback_start_symbolic, .{ .padding = gui.Rect.all(6) })) {
                try gui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "You clicked play" });
            }
            if (try gui.buttonIcon(@src(), 18, "more", gui.icons.papirus.actions.view_more_symbolic, .{ .padding = gui.Rect.all(6) })) {
                try gui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "You clicked more" });
            }
            cbox.deinit();

            tl.processEvents();

            const start = "Notice that the text in this box is wrapping around the buttons in the corners.";
            try tl.addText(start, .{ .font_style = .title_4 });

            try tl.addText("\n", .{});

            const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
            try tl.addText(lorem, .{});
        }
    }

    pub fn menus() !void {
        const ctext = try gui.context(@src(), .{ .expand = .horizontal });
        defer ctext.deinit();

        if (ctext.activePoint()) |cp| {
            var fw2 = try gui.popup(@src(), gui.Rect.fromPoint(cp), .{});
            defer fw2.deinit();

            _ = try gui.menuItemLabel(@src(), "Cut", false, .{});
            if ((try gui.menuItemLabel(@src(), "Close", false, .{})) != null) {
                gui.menuGet().?.close();
            }
            _ = try gui.menuItemLabel(@src(), "Paste", false, .{});
        }

        var vbox = try gui.box(@src(), .vertical, .{});
        defer vbox.deinit();

        {
            var m = try gui.menu(@src(), .horizontal, .{});
            defer m.deinit();

            if (try gui.menuItemLabel(@src(), "File", true, .{})) |r| {
                var fw = try gui.popup(@src(), gui.Rect.fromPoint(gui.Point{ .x = r.x, .y = r.y + r.h }), .{});
                defer fw.deinit();

                try submenus();

                if (try gui.menuItemLabel(@src(), "Close", false, .{}) != null) {
                    gui.menuGet().?.close();
                }

                try gui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

                if (try gui.menuItemLabel(@src(), "Dialog", false, .{}) != null) {
                    gui.menuGet().?.close();
                    show_dialog = true;
                }
            }

            if (try gui.menuItemLabel(@src(), "Edit", true, .{})) |r| {
                var fw = try gui.popup(@src(), gui.Rect.fromPoint(gui.Point{ .x = r.x, .y = r.y + r.h }), .{});
                defer fw.deinit();
                _ = try gui.menuItemLabel(@src(), "Cut", false, .{});
                _ = try gui.menuItemLabel(@src(), "Copy", false, .{});
                _ = try gui.menuItemLabel(@src(), "Paste", false, .{});
            }
        }

        try gui.labelNoFmt(@src(), "Right click for a context menu", .{});
    }

    pub fn submenus() !void {
        if (try gui.menuItemLabel(@src(), "Submenu...", true, .{})) |r| {
            var menu_rect = r;
            menu_rect.x += menu_rect.w;
            var fw2 = try gui.popup(@src(), menu_rect, .{});
            defer fw2.deinit();

            try submenus();

            if (try gui.menuItemLabel(@src(), "Close", false, .{}) != null) {
                gui.menuGet().?.close();
            }

            if (try gui.menuItemLabel(@src(), "Dialog", false, .{}) != null) {
                gui.menuGet().?.close();
                show_dialog = true;
            }
        }
    }

    pub fn dialogs(demo_win_id: u32) !void {
        var b = try gui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10, .y = 0, .w = 0, .h = 0 } });
        defer b.deinit();

        if (try gui.button(@src(), "Direct Dialog", .{})) {
            show_dialog = true;
        }

        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            if (try gui.button(@src(), "Ok Dialog", .{})) {
                try gui.dialog(@src(), .{ .modal = false, .title = "Ok Dialog", .message = "This is a non modal dialog with no callafter" });
            }

            const dialogsFollowup = struct {
                fn callafter(id: u32, response: gui.DialogResponse) gui.Error!void {
                    _ = id;
                    var buf: [100]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "You clicked \"{s}\"", .{@tagName(response)}) catch unreachable;
                    try gui.dialog(@src(), .{ .title = "Ok Followup Response", .message = text });
                }
            };

            if (try gui.button(@src(), "Ok Followup", .{})) {
                try gui.dialog(@src(), .{ .title = "Ok Followup", .message = "This is a modal dialog with modal followup", .callafterFn = dialogsFollowup.callafter });
            }
        }

        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            if (try gui.button(@src(), "Toast 1", .{})) {
                try gui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 1 to demo window" });
            }

            if (try gui.button(@src(), "Toast 2", .{})) {
                try gui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 2 to demo window" });
            }

            if (try gui.button(@src(), "Toast 3", .{})) {
                try gui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 3 to demo window" });
            }

            if (try gui.button(@src(), "Toast Main Window", .{})) {
                try gui.toast(@src(), .{ .message = "Toast to main window" });
            }
        }
    }

    pub fn animations() !void {
        var b = try gui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10, .y = 0, .w = 0, .h = 0 } });
        defer b.deinit();

        {
            var hbox = try gui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            _ = gui.spacer(@src(), .{ .w = 20 }, .{});
            var button_wiggle = gui.ButtonWidget.init(@src(), .{ .tab_index = 10 });
            defer button_wiggle.deinit();

            if (gui.animationGet(button_wiggle.data().id, "xoffset")) |a| {
                button_wiggle.data().rect.x += 20 * (1.0 - a.lerp()) * (1.0 - a.lerp()) * @sin(a.lerp() * std.math.pi * 50);
            }

            try button_wiggle.install(.{});
            try gui.labelNoFmt(@src(), "Wiggle", button_wiggle.data().options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));

            if (button_wiggle.clicked()) {
                const a = gui.Animation{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 500_000 };
                gui.animation(button_wiggle.data().id, "xoffset", a);
            }
        }

        if (try gui.button(@src(), "Animating Dialog", .{})) {
            try gui.dialog(@src(), .{ .modal = false, .title = "Animating Dialog", .message = "This shows how to animate dialogs and other floating windows", .displayFn = AnimatingDialog.dialogDisplay, .callafterFn = AnimatingDialog.after });
        }

        if (try gui.expander(@src(), "Spinner", .{ .expand = .horizontal })) {
            try gui.labelNoFmt(@src(), "Spinner maxes out frame rate", .{});
            try gui.spinner(@src(), .{ .color_text = .{ .r = 100, .g = 200, .b = 100 } });
        }

        if (try gui.expander(@src(), "Clock", .{ .expand = .horizontal })) {
            try gui.labelNoFmt(@src(), "Schedules a frame at the beginning of each second", .{});

            const millis = @divFloor(gui.frameTimeNS(), 1_000_000);
            const left = @intCast(i32, @rem(millis, 1000));

            var mslabel = try gui.LabelWidget.init(@src(), "{d} ms into second", .{@intCast(u32, left)}, .{});
            try mslabel.install(.{});
            mslabel.deinit();

            if (gui.timerDone(mslabel.wd.id) or !gui.timerExists(mslabel.wd.id)) {
                const wait = 1000 * (1000 - left);
                try gui.timer(mslabel.wd.id, wait);
            }
        }
    }

    pub fn dialogDirect() !void {
        const data = struct {
            var extra_stuff: bool = false;
        };
        var dialog_win = try gui.floatingWindow(@src(), .{ .modal = true, .open_flag = &show_dialog }, .{ .color_style = .window });
        defer dialog_win.deinit();

        try gui.windowHeader("Modal Dialog", "", &show_dialog);
        try gui.label(@src(), "Asking a Question", .{}, .{ .font_style = .title_4 });
        try gui.label(@src(), "This dialog is being shown in a direct style, controlled entirely in user code.", .{}, .{});

        if (try gui.button(@src(), "Toggle extra stuff and fit window", .{})) {
            data.extra_stuff = !data.extra_stuff;
            dialog_win.autoSize();
        }

        if (data.extra_stuff) {
            try gui.label(@src(), "This is some extra stuff\nwith a multi-line label\nthat has 3 lines", .{}, .{ .background = true });
        }

        {
            _ = gui.spacer(@src(), .{}, .{ .expand = .vertical });
            var hbox = try gui.box(@src(), .horizontal, .{ .gravity_x = 1.0 });
            defer hbox.deinit();

            if (try gui.button(@src(), "Yes", .{})) {
                dialog_win.close(); // can close the dialog this way
            }

            if (try gui.button(@src(), "No", .{})) {
                show_dialog = false; // can close by not running this code anymore
            }
        }
    }

    pub fn icon_browser() !void {
        var fwin = try gui.floatingWindow(@src(), .{ .rect = &IconBrowser.rect, .open_flag = &IconBrowser.show }, .{ .min_size_content = .{ .w = 300, .h = 400 } });
        defer fwin.deinit();
        try gui.windowHeader("Icon Browser", "", &IconBrowser.show);

        const num_icons = @typeInfo(gui.icons.papirus.actions).Struct.decls.len;
        const height = @intToFloat(f32, num_icons) * IconBrowser.row_height;

        var scroll = try gui.scrollArea(@src(), .{ .expand = .both });
        scroll.setVirtualSize(.{ .w = 0, .h = height });
        defer scroll.deinit();

        const visibleRect = scroll.scroll_info.viewport;
        var cursor: f32 = 0;

        inline for (@typeInfo(gui.icons.papirus.actions).Struct.decls, 0..) |d, i| {
            if (cursor <= (visibleRect.y + visibleRect.h) and (cursor + IconBrowser.row_height) >= visibleRect.y) {
                const r = gui.Rect{ .x = 0, .y = cursor, .w = 0, .h = IconBrowser.row_height };
                var iconbox = try gui.box(@src(), .horizontal, .{ .id_extra = i, .expand = .horizontal, .rect = r });

                _ = try gui.buttonIcon(@src(), 20, "gui.icons.papirus.actions." ++ d.name, @field(gui.icons.papirus.actions, d.name), .{});
                try gui.labelNoFmt(@src(), d.name, .{ .gravity_y = 0.5 });

                iconbox.deinit();

                IconBrowser.row_height = iconbox.wd.min_size.h;
            }

            cursor += IconBrowser.row_height;
        }
    }
};
