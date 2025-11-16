var custom_theme = modified_adwaita_theme;
var custom_theme_name_buffer: [128]u8 = "Adwaita modified".* ++ @as([128 - 16]u8, @splat(0));
var hsv_color: Color.HSV = .fromColor(.black);
/// Used so that the `content` style can use the same logic as the other styles
var content_style: Theme.Style = .{};

const modified_adwaita_theme = blk: {
    var theme = Theme.builtin.adwaita_light;

    theme.name = "Adwaita modified";
    theme.font_body.id = .Aleo;
    theme.font_heading.id = .AleoBd;
    theme.fill = .teal;

    break :blk theme;
};

const ThemeEditingPage = enum {
    // Colors,
    Styles,
    Fonts,
};

/// ![image](Examples-theming.png)
pub fn theming() void {
    const paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = 400 }, .{ .expand = .both });
    defer paned.deinit();

    if (paned.showFirst()) {
        {
            const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            if (paned.collapsed() and dvui.button(@src(), "To Preview", .{}, .{ .gravity_x = 1 })) {
                paned.animateSplit(0);
            }
            if (dvui.button(@src(), "Use custom theme", .{}, .{})) {
                dvui.themeSet(custom_theme);
            }

            var theme_reset_dropdown = dvui.DropdownWidget.init(@src(), .{ .label = "Reset" }, .{});
            theme_reset_dropdown.install();
            if (theme_reset_dropdown.dropped()) {
                for (.{modified_adwaita_theme} ++ Theme.builtins) |builtin_theme| {
                    if (theme_reset_dropdown.addChoiceLabel(builtin_theme.name)) {
                        custom_theme = builtin_theme;
                        const len = @min(custom_theme_name_buffer.len, builtin_theme.name.len);
                        @memcpy(custom_theme_name_buffer[0..len], builtin_theme.name[0..len]);
                        @memset(custom_theme_name_buffer[len..], 0);
                    }
                }
            }
            theme_reset_dropdown.deinit();
        }

        {
            const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();

            dvui.labelNoFmt(@src(), "Name:", .{}, .{ .gravity_y = 0.5 });
            const text_entry = dvui.textEntry(@src(), .{
                .text = .{ .buffer = &custom_theme_name_buffer },
            }, .{});
            defer text_entry.deinit();
            if (text_entry.text_changed) {
                custom_theme.name = text_entry.getText();
            }
        }

        {
            var custom_label: ?[]const u8 = null;
            const max: f32 = 10;
            var max_cor_rad: f32 = max;
            if (custom_theme.max_default_corner_radius) |mdcr| {
                max_cor_rad = mdcr;
            } else {
                custom_label = "Max Corner Radius: null";
            }
            if (dvui.sliderEntry(@src(), "Max Corner Radius: {d:0}", .{ .min = 0, .max = max, .interval = 1, .value = &max_cor_rad, .label = custom_label }, .{})) {
                if (max_cor_rad >= max) {
                    custom_theme.max_default_corner_radius = null;
                } else {
                    custom_theme.max_default_corner_radius = max_cor_rad;
                }
            }
        }

        const active_page = dvui.dataGetPtrDefault(null, paned.data().id, "Page", ThemeEditingPage, .Styles);
        {
            var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            tabs.install();
            defer tabs.deinit();
            inline for (std.meta.tags(ThemeEditingPage), 0..) |page, i| {
                var tab = tabs.addTab(active_page.* == page, .{
                    .expand = .horizontal,
                    .padding = .all(2),
                    .id_extra = i,
                });
                defer tab.deinit();
                if (tab.clicked()) {
                    active_page.* = page;
                }
                dvui.labelNoFmt(@src(), @tagName(page), .{}, tab.style());
            }
        }

        switch (active_page.*) {
            .Styles => _ = styles(&custom_theme),
            .Fonts => _ = fonts(&custom_theme),
        }
    }

    if (paned.showSecond()) {
        const prev_theme = dvui.themeGet();
        defer dvui.themeSet(prev_theme);
        dvui.themeSet(custom_theme);

        if (paned.collapsed() and dvui.button(@src(), "To Editor", .{}, .{ .gravity_x = 1 })) {
            paned.animateSplit(1);
        }

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .background = true, .padding = .all(10), .corner_radius = .all(10) });
            defer hbox.deinit();
            {
                var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{});
                defer vbox.deinit();

                _ = dvui.button(@src(), "Control", .{}, .{ .style = .control });
                _ = dvui.button(@src(), "Highlight", .{}, .{ .style = .highlight });
                _ = dvui.button(@src(), "Error", .{}, .{ .style = .err });
                _ = dvui.button(@src(), "Window", .{}, .{ .style = .window });
                _ = dvui.button(@src(), "Content", .{}, .{ .style = .content });
            }

            var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{});
            defer vbox.deinit();
            inline for (@typeInfo(Options.FontStyle).@"enum".fields, 0..) |font_style, i| {
                dvui.labelNoFmt(@src(), font_style.name, .{}, .{ .font = @field(custom_theme, "font_" ++ font_style.name), .id_extra = i });
            }
        }

        const tl = dvui.textLayout(@src(), .{}, .{ .border = .all(1), .background = true });
        tl.addText(
            \\Lorem ipsum dolor sit amet, consectetur adipiscing elit. Curabitur semper consequat sapien, eu tempus neque cursus quis. Vestibulum tincidunt ex ac mi aliquet, non molestie tellus pharetra. Donec egestas nisi vel varius condimentum. Aenean id sagittis purus. Curabitur ultrices, nulla vel facilisis fermentum, risus dolor finibus mauris, consequat tincidunt eros mauris id orci.
        , .{});

        tl.addTextTooltip(@src(),
            \\Vestibulum aliquam malesuada nibh, quis dignissim elit sollicitudin ac. Donec bibendum tortor nec odio suscipit, non laoreet nulla viverra. Ut dignissim cursus sodales. Sed vel neque sollicitudin, pretium urna non, efficitur felis. Integer in sapien cursus, ullamcorper leo sed, pharetra ex. Donec porta sollicitudin arcu id malesuada. Sed sollicitudin iaculis elit quis convallis. Duis ac risus ac erat molestie finibus. Nunc eget posuere augue. Nulla ut metus enim. Curabitur quis erat vitae diam volutpat lacinia et non metus. Suspendisse vel ullamcorper nulla, eu tristique sem.
        , "Praesent gravida felis sed ipsum placerat", .{});

        tl.deinit();
    }
}

fn fonts(theme: *Theme) bool {
    var changed = false;

    const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .role = .tab_panel });
    defer hbox.deinit();

    const active_font = dvui.dataGetPtrDefault(null, hbox.data().id, "Fonts", Options.FontStyle, .body);
    {
        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .vertical }, .{ .expand = .vertical });
        tabs.install();
        defer tabs.deinit();

        inline for (comptime std.meta.tags(Options.FontStyle), 0..) |font_style, i| {
            const tab = tabs.addTab(active_font.* == font_style, .{
                .expand = .horizontal,
                .padding = .all(2),
                .id_extra = i,
            });
            defer tab.deinit();
            if (tab.clicked()) {
                active_font.* = font_style;
            }
            dvui.labelNoFmt(@src(), @tagName(font_style), .{}, tab.style());
        }
    }

    const edited_font: *dvui.Font = switch (active_font.*) {
        inline else => |f| &@field(theme, "font_" ++ @tagName(f)),
    };

    var vbox = dvui.box(@src(), .{}, .{ .expand = .both });
    defer vbox.deinit();

    if (dvui.sliderEntry(@src(), "Size: {d:0}", .{ .min = 4, .max = 100, .interval = 1, .value = &edited_font.size }, .{})) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "Line height: {d:0.1}", .{ .min = 0, .max = 10, .interval = 0.1, .value = &edited_font.line_height_factor }, .{})) {
        changed = true;
    }

    var current_font_index: ?usize = null;
    var current_font_name: []const u8 = "Unknown";
    var it = dvui.currentWindow().fonts.database.iterator();
    var i: usize = 0;
    while (it.next()) |entry| : (i += 1) {
        if (entry.key_ptr.* == edited_font.id) {
            current_font_index = i;
            current_font_name = entry.value_ptr.name;
        }
    }

    var dd = dvui.DropdownWidget.init(@src(), .{ .selected_index = current_font_index, .label = current_font_name }, .{});
    dd.install();
    if (dd.dropped()) {
        it = dvui.currentWindow().fonts.database.iterator();
        while (it.next()) |entry| {
            if (dd.addChoiceLabel(entry.value_ptr.name)) {
                edited_font.id = entry.key_ptr.*;
                changed = true;
            }
        }
    }
    dd.deinit();

    dvui.label(@src(), "Preview {s}\nwith multiple lines", .{@tagName(active_font.*)}, .{ .font = edited_font.* });

    return changed;
}

// The order of these fields determine the order of the tabs in the editor
const ColorNames = enum {
    fill,
    fill_hover,
    fill_press,
    text,
    text_hover,
    text_press,
    /// Only for `content`
    text_select,
    border,
    /// Not part of `Theme.ColorStyle`
    focus,
};

fn styles(theme: *Theme) bool {
    var changed = false;

    const first_box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .role = .tab_panel });
    defer first_box.deinit();

    const active_style = dvui.dataGetPtrDefault(null, first_box.data().id, "Style", Theme.Style.Name, .content);
    var style_changed: bool = false;

    var style: *Theme.Style = undefined;

    const active_color = dvui.dataGetPtrDefault(null, first_box.data().id, "Color", ColorNames, .fill);

    const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
    defer hbox.deinit();
    {
        const vbox = dvui.box(@src(), .{}, .{});
        defer vbox.deinit();

        {
            const theme_styles = comptime std.meta.tags(Theme.Style.Name);
            var dd = dvui.DropdownWidget.init(@src(), .{
                .label = @tagName(active_style.*),
                .selected_index = std.mem.indexOfScalar(Theme.Style.Name, theme_styles, active_style.*),
            }, .{
                .min_size_content = .{ .w = 110 },
                .expand = .horizontal,
                .margin = .{ .y = 2 + 3, .w = 1 + 2, .h = 2 + 3 },
            });
            dd.install();
            defer dd.deinit();
            if (dd.dropped()) {
                for (theme_styles) |theme_style| {
                    if (dd.addChoiceLabel(@tagName(theme_style))) {
                        style_changed = true;
                        active_style.* = theme_style;
                    }
                }
            }
        }

        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .vertical }, .{ .expand = .both });
        tabs.install();
        defer tabs.deinit();

        style = switch (active_style.*) {
            .content => blk: {
                inline for (@typeInfo(Theme.Style).@"struct".fields) |field| {
                    @field(content_style, field.name) = @field(theme, field.name);
                }
                break :blk &content_style;
            },
            inline else => |s| &@field(theme, @tagName(s)),
        };

        for (std.meta.tags(ColorNames), 0..) |color_name, i| {
            if (color_name == .text_select and active_style.* != .content) continue;

            const selected = active_color.* == color_name;
            const tab = tabs.addTab(selected, .{
                .expand = .horizontal,
                .padding = .all(2),
                .id_extra = i,
            });
            defer tab.deinit();
            if (tab.clicked()) {
                active_color.* = color_name;
            }

            const color: ?Color = switch (color_name) {
                .text_select => theme.text_select,
                .focus => theme.focus,
                inline else => |name| @field(style, @tagName(name)),
            };
            if ((style_changed and selected) or tab.clicked()) {
                hsv_color = Color.HSV.fromColor(color orelse .white);
            }

            var wd: dvui.WidgetData = undefined;
            dvui.icon(@src(), "Color indicator", dvui.entypo.cross, .{
                .fill_color = if (color) |_| .transparent else .white,
            }, .{
                .data_out = &wd,
                .expand = .ratio,
                .min_size_content = .all(10),
                .corner_radius = .all(100),
                .border = .all(1),
                .background = true,
                .color_fill = color,
            });
            dvui.labelNoFmt(@src(), @tagName(color_name), .{}, tab.style().override(.{ .margin = .{ .x = wd.rect.w }, .gravity_y = 0.5 }));
        }
    }

    var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both, .margin = .all(5) });
    defer vbox.deinit();

    const color: ?Color = switch (active_color.*) {
        .text_select => theme.text_select,
        .focus => theme.focus,
        inline else => |c| @field(style, @tagName(c)),
    };
    if (dvui.firstFrame(vbox.data().id)) {
        hsv_color = Color.HSV.fromColor(color orelse .white);
    }
    if (dvui.colorPicker(@src(), .{ .hsv = &hsv_color, .dir = .vertical }, .{})) {
        changed = true;
        switch (active_color.*) {
            .text_select => theme.text_select = hsv_color.toColor(),
            .focus => theme.focus = hsv_color.toColor(),
            inline else => |c| @field(style, @tagName(c)) = hsv_color.toColor(),
        }
    }

    {
        var dd = dvui.DropdownWidget.init(@src(), .{ .label = "Set color" }, .{ .min_size_content = .{ .w = 110 } });
        dd.install();
        defer dd.deinit();
        if (dd.dropped()) {
            // Only show this if the color is optional
            if (active_color.* != .focus and
                (active_style.* == .content and (active_color.* != .fill and active_color.* != .text and active_color.* != .border)) and
                dd.addChoiceLabel("Set to null"))
            {
                switch (active_color.*) {
                    .focus => unreachable,
                    .text_select => theme.text_select = null,
                    inline else => |c| @field(style, @tagName(c)) = null,
                }
            }

            for (std.meta.tags(Options.ColorAsk)) |color_ask| {
                if (dd.addChoiceLabel(@tagName(color_ask))) {
                    changed = true;
                    const col = dvui.themeGet().color(active_style.*, color_ask);
                    hsv_color = Color.HSV.fromColor(col);
                    switch (active_color.*) {
                        .text_select => theme.text_select = col,
                        .focus => theme.focus = col,
                        inline else => |c| @field(style, @tagName(c)) = col,
                    }
                }
            }
        }
    }

    // Reapply the content colors
    if (active_style.* == .content and changed) {
        switch (active_color.*) {
            .focus, .text_select => {},
            inline else => |name| if (@FieldType(Theme, @tagName(name)) == ?Color) {
                // Optional fields can get assigned directly
                @field(theme, @tagName(name)) = @field(style, @tagName(name));
            } else if (@field(style, @tagName(name))) |col| {
                // Non optionals only get set if the style color is not null
                @field(theme, @tagName(name)) = col;
            },
        }
    }

    return changed;
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG theming" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            theming();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-theming.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = @import("../Examples.zig");
const Options = dvui.Options;
const Theme = dvui.Theme;
const Color = dvui.Color;
const Rect = dvui.Rect;
