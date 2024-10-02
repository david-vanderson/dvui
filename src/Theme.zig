const dvui = @import("dvui.zig");
const std = @import("std");

const Color = dvui.Color;
const Font = dvui.Font;
const Options = dvui.Options;

pub const FallBack = @import("themes/Adwaita.zig").light;

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
            .font_body = .{ .size = @round(self.font_size), .name = font_name_body },
            .font_heading = .{ .size = @round(self.font_size), .name = font_name_heading },
            .font_caption = .{ .size = @round(self.font_size * 0.77), .name = font_name_caption },
            .font_caption_heading = .{ .size = @round(self.font_size * 0.77), .name = font_name_caption },
            .font_title = .{ .size = @round(self.font_size * 2.15), .name = font_name_title },
            .font_title_1 = .{ .size = @round(self.font_size * 1.77), .name = font_name_title },
            .font_title_2 = .{ .size = @round(self.font_size * 1.54), .name = font_name_title },
            .font_title_3 = .{ .size = @round(self.font_size * 1.3), .name = font_name_title },
            .font_title_4 = .{ .size = @round(self.font_size * 1.15), .name = font_name_title },
            .style_accent = .{
                .color_accent = .{ .color = Color.alphaAverage(color_accent, color_accent) },
                .color_text = .{ .color = Color.alphaAverage(color_accent, color_text) },
                .color_text_press = .{ .color = Color.alphaAverage(color_accent, color_text_press) },
                .color_fill = .{ .color = Color.alphaAverage(color_accent, color_fill) },
                .color_fill_hover = .{ .color = Color.alphaAverage(color_accent, color_fill_hover) },
                .color_fill_press = .{ .color = Color.alphaAverage(color_accent, color_fill_press) },
                .color_border = .{ .color = Color.alphaAverage(color_accent, color_border) },
            },
            .style_err = .{
                .color_accent = .{ .color = Color.alphaAverage(color_accent, color_accent) },
                .color_text = .{ .color = Color.alphaAverage(color_err, color_text) },
                .color_text_press = .{ .color = Color.alphaAverage(color_err, color_text_press) },
                .color_fill = .{ .color = Color.alphaAverage(color_err, color_fill) },
                .color_fill_hover = .{ .color = Color.alphaAverage(color_err, color_fill_hover) },
                .color_fill_press = .{ .color = Color.alphaAverage(color_err, color_fill_press) },
                .color_border = .{ .color = Color.alphaAverage(color_err, color_border) },
            },
        };
    }
};

pub const Database = struct {
    //const CacheEntry = std.StringHashMap(Theme).Entry;
    //const Cache = std.ArrayList(CacheEntry);

    const HashMap = std.StringArrayHashMap(Theme);

    themes: HashMap,
    arena: *std.heap.ArenaAllocator,
    sorted: bool = false,

    pub const builtin = struct {
        pub const jungle = @embedFile("themes/jungle.json");
        pub const dracula = @embedFile("themes/dracula.json");
        pub const gruvbox = @embedFile("themes/gruvbox.json");
        pub const adwaita_light = @embedFile("themes/adwaita_light.json");
        pub const adwaita_dark = @embedFile("themes/adwaita_dark.json");
        pub const opendyslexic = @embedFile("themes/opendyslexic.json");
    };

    pub fn get(self: *const @This(), name: []const u8) *Theme {
        return self.themes.getPtr(name) orelse @panic("Requested theme does not exist");
    }

    pub fn sort(self: *@This()) void {
        const Context = struct {
            hashmap: *HashMap,
            pub fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
                return std.ascii.orderIgnoreCase(ctx.hashmap.values()[lhs].name, ctx.hashmap.values()[rhs].name) == .lt;
            }
        };
        self.themes.sort(Context{ .hashmap = &self.themes });
    }

    pub fn getThemes(self: *@This()) []Theme {
        return self.themes.values();
    }

    pub fn picker(self: *@This(), src: std.builtin.SourceLocation) !void {
        var hbox = try dvui.box(src, .horizontal, .{});
        defer hbox.deinit();

        const theme_choice: usize = blk: {
            for (self.getThemes(), 0..) |val, i| {
                if (std.mem.eql(u8, dvui.themeGet().name, val.name)) {
                    break :blk i;
                }
            }
            break :blk 0;
        };

        var dd = dvui.DropdownWidget.init(
            @src(),
            .{ .selected_index = theme_choice, .label = dvui.themeGet().name },
            .{ .min_size_content = .{ .w = 120 } },
        );
        try dd.install();

        if (try dd.dropped()) {
            for (self.getThemes()) |theme| {
                if (try dd.addChoiceLabel(theme.name)) {
                    dvui.themeSet(self.get(theme.name));
                    break;
                }
            }
        }

        dd.deinit();
    }

    pub fn init(base_allocator: std.mem.Allocator) !@This() {
        var self: @This() = .{
            .arena = try base_allocator.create(std.heap.ArenaAllocator),
            .themes = undefined,
        };
        self.arena.* = std.heap.ArenaAllocator.init(base_allocator);
        const alloc = self.arena.allocator();

        self.themes = HashMap.init(alloc);
        inline for (@typeInfo(builtin).Struct.decls) |decl| {
            const quick_theme = QuickTheme.fromString(alloc, @field(builtin, decl.name)) catch {
                @panic("Failure loading builtin theme. This is a problem with DVUI.");
            };
            defer quick_theme.deinit();
            try self.themes.putNoClobber(quick_theme.value.name, try quick_theme.value.toTheme(alloc));
        }
        return self;
    }

    pub fn deinit(self: *@This(), base_allocator: std.mem.Allocator) void {
        self.arena.deinit();
        base_allocator.destroy(self.arena);
    }
};
