const dvui = @import("dvui.zig");
const std = @import("std");

const Color = dvui.Color;
const Font = dvui.Font;
const Options = dvui.Options;

/// List of theme pointers
pub const ptrs = [_]*dvui.Theme{
    &AdwaitaLight,
    &AdwaitaDark,
    &AdwaitaOpenDyslexicLight,
    &AdwaitaOpenDyslexicDark,
    &Jungle,
    &Dracula,
    &Flow,
    &Gruvbox,
};

//builtin themes
pub var AdwaitaLight = @import("themes/Adwaita.zig").light;
pub var AdwaitaDark = @import("themes/Adwaita.zig").dark;
pub var AdwaitaOpenDyslexicLight = @import("themes/AdwaitaOpenDyslexic.zig").light;
pub var AdwaitaOpenDyslexicDark = @import("themes/AdwaitaOpenDyslexic.zig").dark;
pub var Jungle = @import("themes/Jungle.zig").jungle;
pub var Dracula = @import("themes/Dracula.zig").dracula;
pub var Flow = @import("themes/Flow.zig").flow;
pub var Gruvbox = @import("themes/Gruvbox.zig").gruvbox;

const Theme = @This();

name: []const u8,

// widgets can use this if they need to adjust colors
dark: bool,

alpha: f32 = 1.0,

// used for focus
color_accent: Color,

color_err: Color,

// text/foreground color
color_text: Color,

// text/foreground color when widget is pressed
color_text_press: Color,

// background color for displaying lots of text
color_fill: Color,

// background color for containers that have other widgets inside
color_fill_window: Color,

// background color for controls like buttons
color_fill_control: Color,

color_fill_hover: Color,
color_fill_press: Color,

color_border: Color,

font_body: Font,
font_heading: Font,
font_caption: Font,
font_caption_heading: Font,
font_title: Font,
font_title_1: Font,
font_title_2: Font,
font_title_3: Font,
font_title_4: Font,

// used for highlighting menu/dropdown items
style_accent: Options,

// used for a button to perform dangerous actions
style_err: Options,

pub fn fontSizeAdd(self: *Theme, delta: f32) Theme {
    var ret = self.*;
    ret.font_body.size += delta;
    ret.font_heading.size += delta;
    ret.font_caption.size += delta;
    ret.font_caption_heading.size += delta;
    ret.font_title.size += delta;
    ret.font_title_1.size += delta;
    ret.font_title_2.size += delta;
    ret.font_title_3.size += delta;
    ret.font_title_4.size += delta;

    return ret;
}

//  "color_focus": "#638465",
//  "color_text": "#82a29f",
//  "color_text_press": "#97af81",
//  "color_fill_text": "#2c3332",
//  "color_fill_container": "#2b3a3a",
//  "color_fill_control": "#2c3334",
//  "color_fill_hover": "#334e57",
//  "color_fill_press": "#3b6357",
//  "color_border": "#60827d"

pub const QuickTheme = struct {
    name: []u8,

    // fonts
    font_size: f32 = 14,
    font_name_body: []u8,
    font_name_heading: []u8,
    font_name_caption: []u8,
    font_name_title: []u8,

    // used for focus
    color_focus: [7]u8 = "#638465".*,

    // text/foreground color
    color_text: [7]u8 = "$82a29f".*,

    // text/foreground color when widget is pressed
    color_text_press: [7]u8 = "#971f81".*,

    // background color for displaying lots of text
    color_fill_text: [7]u8 = "#2c3332".*,

    // background color for containers that have other widgets inside
    color_fill_container: [7]u8 = "#2b3a3a".*,

    // background color for controls like buttons
    color_fill_control: [7]u8 = "#2c3334".*,

    color_fill_hover: [7]u8 = "#333e57".*,
    color_fill_press: [7]u8 = "#3b6357".*,

    color_border: [7]u8 = "#60827d".*,

    pub const colorFieldNames = &.{
        "color_focus",
        "color_text",
        "color_text_press",
        "color_fill_text",
        "color_fill_container",
        "color_fill_control",
        "color_fill_hover",
        "color_fill_press",
        "color_border",
    };

    pub fn initDefault(alloc: std.mem.Allocator) !@This() {
        const padding = 32;
        return .{
            .name = try alloc.dupeZ(u8, "Default" ++ [_]u8{0} ** padding),
            .font_name_body = try alloc.dupeZ(u8, "Vera" ++ [_]u8{0} ** padding),
            .font_name_heading = try alloc.dupeZ(u8, "Vera" ++ [_]u8{0} ** padding),
            .font_name_caption = try alloc.dupeZ(u8, "Vera" ++ [_]u8{0} ** padding),
            .font_name_title = try alloc.dupeZ(u8, "Vera" ++ [_]u8{0} ** padding),
            //.color_focus = try alloc.dupe(u8, "#ffffff"),
            //.color_text = try alloc.dupe(u8, "#ffffff"),
            //.color_text_press = try alloc.dupe(u8, "#ffffff"),
            //.color_fill_text = try alloc.dupe(u8, "#000000"),
            //.color_fill_container = try alloc.dupe(u8, "#ffffff"),
            //.color_fill_control = try alloc.dupe(u8, "#ffffff"),
            //.color_fill_hover = try alloc.dupe(u8, "#ffffff"),
            //.color_fill_press = try alloc.dupe(u8, "#ffffff"),
            //.color_border = try alloc.dupe(u8, "#000000"),
        };
    }

    pub fn fromString(
        allocator: std.mem.Allocator,
        string: []const u8,
    ) !std.json.Parsed(QuickTheme) {
        return try std.json.parseFromSlice(
            QuickTheme,
            allocator,
            string,
            .{ .allocate = .alloc_always },
        );
    }

    pub fn toTheme(self: @This(), allocator: std.mem.Allocator) !Theme {
        const color_accent = try Color.fromHex(self.color_focus);
        const color_err = try Color.fromHex("#ffaaaa".*);
        const color_text = try Color.fromHex(self.color_text);
        const color_text_press = try Color.fromHex(self.color_text_press);
        const color_fill = try Color.fromHex(self.color_fill_text);
        const color_fill_window = try Color.fromHex(self.color_fill_container);
        const color_fill_control = try Color.fromHex(self.color_fill_control);
        const color_fill_hover = try Color.fromHex(self.color_fill_hover);
        const color_fill_press = try Color.fromHex(self.color_fill_press);
        const color_border = try Color.fromHex(self.color_border);

        const font_name_body = try allocator.dupeZ(u8, self.font_name_body);
        const font_name_heading = try allocator.dupeZ(u8, self.font_name_heading);
        const font_name_caption = try allocator.dupeZ(u8, self.font_name_caption);
        const font_name_title = try allocator.dupeZ(u8, self.font_name_title);

        return Theme{
            .name = try allocator.dupeZ(u8, self.name),
            .dark = color_text.brightness() > color_fill.brightness(),
            .alpha = 1.0,
            .color_accent = color_accent,
            .color_err = color_err,
            .color_text = color_text,
            .color_text_press = color_text_press,
            .color_fill = color_fill,
            .color_fill_window = color_fill_window,
            .color_fill_control = color_fill_control,
            .color_fill_hover = color_fill_hover,
            .color_fill_press = color_fill_press,
            .color_border = color_border,
            .font_body = .{ .size = self.font_size, .name = font_name_body },
            .font_heading = .{ .size = self.font_size, .name = font_name_heading },
            .font_caption = .{ .size = self.font_size * 0.7, .name = font_name_caption },
            .font_caption_heading = .{ .size = self.font_size * 0.7, .name = font_name_caption },
            .font_title = .{ .size = self.font_size * 2, .name = font_name_title },
            .font_title_1 = .{ .size = self.font_size * 1.8, .name = font_name_title },
            .font_title_2 = .{ .size = self.font_size * 1.6, .name = font_name_title },
            .font_title_3 = .{ .size = self.font_size * 1.4, .name = font_name_title },
            .font_title_4 = .{ .size = self.font_size * 1.2, .name = font_name_title },
            .style_accent = .{
                .color_accent = .{ .color = Color.alphaAdd(color_accent, color_accent) },
                .color_text = .{ .color = Color.alphaAdd(color_accent, color_text) },
                .color_text_press = .{ .color = Color.alphaAdd(color_accent, color_text_press) },
                .color_fill = .{ .color = Color.alphaAdd(color_accent, color_fill) },
                .color_fill_hover = .{ .color = Color.alphaAdd(color_accent, color_fill_hover) },
                .color_fill_press = .{ .color = Color.alphaAdd(color_accent, color_fill_press) },
                .color_border = .{ .color = Color.alphaAdd(color_accent, color_border) },
            },
            .style_err = .{
                .color_accent = .{ .color = Color.alphaAdd(color_accent, color_accent) },
                .color_text = .{ .color = Color.alphaAdd(color_err, color_text) },
                .color_text_press = .{ .color = Color.alphaAdd(color_err, color_text_press) },
                .color_fill = .{ .color = Color.alphaAdd(color_err, color_fill) },
                .color_fill_hover = .{ .color = Color.alphaAdd(color_err, color_fill_hover) },
                .color_fill_press = .{ .color = Color.alphaAdd(color_err, color_fill_press) },
                .color_border = .{ .color = Color.alphaAdd(color_err, color_border) },
            },
        };
    }
};

pub const Database = struct {
    themes: std.StringHashMap(Theme),
    arena: std.heap.ArenaAllocator,
    names: ?std.ArrayList([]const u8) = null,

    pub const builtin = struct {
        pub const jungle = @embedFile("themes/jungle.json");
        pub const dracula = @embedFile("themes/dracula.json");
        pub const gruvbox = @embedFile("themes/gruvbox.json");
        pub const papercolor_dark = @embedFile("themes/papercolor-dark.json");
    };

    pub fn get(self: *const @This(), name: []const u8) *Theme {
        return self.themes.getPtr(name) orelse @panic("Requested theme does not exist");
    }

    pub fn themeNames(self: *const @This()) []const []const u8 {
        if (self.names) |names| {
            if (names.len == self.themes.count()) {
                return self.names.items;
            } else {
                names.clearRetainingCapacity();
                var iter = self.themes.keyIterator();
                while (iter.next()) |key| {
                    names.append(key);
                }
                return themeNames(self);
            }
        } else {
            self.names = std.ArrayList([]const u8).init(self.arena);
            return themeNames(self);
        }
    }

    pub fn init(base_allocator: std.mem.Allocator) !@This() {
        var self: @This() = .{
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .themes = undefined,
        };
        const alloc = self.arena.allocator();
        self.themes = std.StringHashMap(Theme).init(alloc);
        inline for (@typeInfo(builtin).Struct.decls) |decl| {
            const quick_theme = QuickTheme.fromString(alloc, @field(builtin, decl.name)) catch {
                @panic("Failure loading builtin theme. This is a problem with DVUI.");
            };
            defer quick_theme.deinit();
            try self.themes.putNoClobber(decl.name, try quick_theme.value.toTheme(alloc));
        }
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }
};
