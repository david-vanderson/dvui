var custom_theme = modified_adwaita_theme;
var custom_theme_name_buffer: [128]u8 = "Adwaita modified".* ++ @as([128 - 16]u8, @splat(0));
var hsv_color: dvui.Color.HSV = .fromColor(.black);

const modified_adwaita_theme = blk: {
    var theme = dvui.Theme.builtin.adwaita_light;

    theme.name = "Adwaita modified";
    theme.font_body.id = .Aleo;
    theme.font_heading.id = .AleoBd;
    theme.color_fill = .teal;

    break :blk theme;
};

/// ![image](Examples-theming.png)
pub fn theming() void {
    const paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = 400 }, .{ .expand = .both });
    defer paned.deinit();

    //if (paned.showFirst()) {
    //    const vbox = dvui.box(@src(), .{}, .{ .expand = .both, .margin = .{ .y = 10 } });
    //    defer vbox.deinit();

    //    {
    //        const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
    //        defer hbox.deinit();
    //        if (paned.collapsed() and dvui.button(@src(), "To Preview", .{}, .{ .gravity_x = 1 })) {
    //            paned.animateSplit(0);
    //        }
    //        if (dvui.button(@src(), "Use custom theme", .{}, .{})) {
    //            dvui.themeSet(&custom_theme);
    //        }

    //        var theme_reset_dropdown = dvui.DropdownWidget.init(@src(), .{ .label = "Reset" }, .{});
    //        theme_reset_dropdown.install();
    //        if (theme_reset_dropdown.dropped()) {
    //            for (.{modified_adwaita_theme} ++ dvui.Theme.builtins) |builtin_theme| {
    //                if (theme_reset_dropdown.addChoiceLabel(builtin_theme.name)) {
    //                    custom_theme = builtin_theme;
    //                    const len = @min(custom_theme_name_buffer.len, builtin_theme.name.len);
    //                    @memcpy(custom_theme_name_buffer[0..len], builtin_theme.name[0..len]);
    //                    @memset(custom_theme_name_buffer[len..], 0);
    //                }
    //            }
    //        }
    //        theme_reset_dropdown.deinit();
    //    }

    //    {
    //        const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
    //        defer hbox.deinit();

    //        dvui.labelNoFmt(@src(), "Name:", .{}, .{ .gravity_y = 0.5 });
    //        const text_entry = dvui.textEntry(@src(), .{
    //            .text = .{ .buffer = &custom_theme_name_buffer },
    //        }, .{});
    //        defer text_entry.deinit();
    //        if (text_entry.text_changed) {
    //            custom_theme.name = text_entry.getText();
    //        }
    //    }

    //    const active_page = dvui.dataGetPtrDefault(null, vbox.data().id, "Page", ThemeEditingPage, .Colors);
    //    {
    //        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
    //        tabs.install();
    //        defer tabs.deinit();
    //        inline for (std.meta.tags(ThemeEditingPage), 0..) |page, i| {
    //            var tab = tabs.addTab(active_page.* == page, .{
    //                .expand = .horizontal,
    //                .padding = .all(2),
    //                .id_extra = i,
    //            });
    //            defer tab.deinit();
    //            if (tab.clicked()) {
    //                active_page.* = page;
    //            }
    //            var label_opts = tab.data().options.strip();
    //            if (dvui.captured(tab.data().id)) {
    //                label_opts.color_text = .{ .name = .text_press };
    //            }
    //            dvui.labelNoFmt(@src(), @tagName(page), .{}, .{});
    //        }
    //    }

    //    switch (active_page.*) {
    //        .Colors => _ = colors(&custom_theme),
    //        .Fonts => _ = fonts(&custom_theme),
    //        .Styles => _ = styles(&custom_theme),
    //    }
    //}

    //if (paned.showSecond()) {
    //    const prev_theme = dvui.themeGet().*;
    //    defer dvui.themeSet(&prev_theme);
    //    dvui.themeSet(&custom_theme);

    //    var vbox = dvui.box(@src(), .{}, .{ .background = true, .padding = .all(10), .corner_radius = .all(10) });
    //    defer vbox.deinit();

    //    if (paned.collapsed() and dvui.button(@src(), "To Editor", .{}, .{ .gravity_x = 1 })) {
    //        paned.animateSplit(1);
    //    }

    //    {
    //        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
    //        defer hbox.deinit();

    //        _ = dvui.button(@src(), "Accent", .{}, dvui.themeGet().accent());
    //        _ = dvui.button(@src(), "Error", .{}, dvui.themeGet().err());
    //        _ = dvui.button(@src(), "Window", .{}, .{ .color_fill = .fill_window });
    //        _ = dvui.button(@src(), "Content", .{}, .{ .color_fill = .fill });
    //        _ = dvui.button(@src(), "Control", .{}, .{});
    //    }

    //    inline for (@typeInfo(Options.FontStyle).@"enum".fields, 0..) |font_style, i| {
    //        dvui.labelNoFmt(@src(), font_style.name, .{}, .{ .font = @field(custom_theme, "font_" ++ font_style.name), .id_extra = i });
    //    }

    //    const tl = dvui.textLayout(@src(), .{}, .{ .border = .all(1), .background = true });
    //    tl.addText(
    //        \\Lorem ipsum dolor sit amet, consectetur adipiscing elit. Curabitur semper consequat sapien, eu tempus neque cursus quis. Vestibulum tincidunt ex ac mi aliquet, non molestie tellus pharetra. Donec egestas nisi vel varius condimentum. Aenean id sagittis purus. Curabitur ultrices, nulla vel facilisis fermentum, risus dolor finibus mauris, consequat tincidunt eros mauris id orci.
    //    , .{});

    //    tl.addTextTooltip(@src(),
    //        \\Vestibulum aliquam malesuada nibh, quis dignissim elit sollicitudin ac. Donec bibendum tortor nec odio suscipit, non laoreet nulla viverra. Ut dignissim cursus sodales. Sed vel neque sollicitudin, pretium urna non, efficitur felis. Integer in sapien cursus, ullamcorper leo sed, pharetra ex. Donec porta sollicitudin arcu id malesuada. Sed sollicitudin iaculis elit quis convallis. Duis ac risus ac erat molestie finibus. Nunc eget posuere augue. Nulla ut metus enim. Curabitur quis erat vitae diam volutpat lacinia et non metus. Suspendisse vel ullamcorper nulla, eu tristique sem.
    //    , "Praesent gravida felis sed ipsum placerat", .{});

    //    tl.deinit();
    //}
}

const ThemeEditingPage = enum {
    Colors,
    Fonts,
    Styles,
};

fn colors(theme: *dvui.Theme) bool {
    var changed = false;

    const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 5 } });
    defer hbox.deinit();

    const active_color = dvui.dataGetPtrDefault(null, hbox.data().id, "Color", Options.ColorsFromTheme, .accent);

    {
        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .vertical }, .{ .expand = .vertical });
        tabs.install();
        defer tabs.deinit();

        inline for (comptime std.meta.tags(Options.ColorsFromTheme), 0..) |color_name, i| {
            const color = @field(theme, "color_" ++ @tagName(color_name));

            const tab = tabs.addTab(active_color.* == color_name, .{
                .expand = .horizontal,
                .padding = .all(2),
                .id_extra = i,
            });
            defer tab.deinit();

            if (tab.clicked()) {
                hsv_color = .fromColor(color);
                active_color.* = color_name;
            }

            var label_opts = tab.data().options.strip();
            if (dvui.captured(tab.data().id)) {
                label_opts.color_text = .{ .name = .text_press };
            }

            const color_indicator = dvui.overlay(@src(), .{
                .expand = .ratio,
                .min_size_content = .all(10),
                .corner_radius = .all(100),
                .border = .all(1),
                .background = true,
                .color_fill = .fromColor(color),
            });
            const color_width = color_indicator.data().rectScale().r.w;
            color_indicator.deinit();
            dvui.labelNoFmt(@src(), @tagName(color_name), .{}, .{ .margin = .{ .x = color_width } });
        }
    }

    const rgba_color: *dvui.Color = switch (active_color.*) {
        inline else => |c| &@field(theme, "color_" ++ @tagName(c)),
    };
    if (dvui.firstFrame(hbox.data().id)) {
        hsv_color = .fromColor(rgba_color.*);
    }
    // We use a global variable for the hsv color to make the color picker behave better.
    // Recreating the hsv color every frame would reset the hue slider to 0 if the color
    // is white or black, making it feel glitchy
    if (dvui.colorPicker(@src(), .{ .hsv = &hsv_color, .dir = .vertical }, .{})) {
        changed = true;
        rgba_color.* = hsv_color.toColor();
    }

    return changed;
}

fn fonts(theme: *dvui.Theme) bool {
    var changed = false;

    const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
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

            var label_opts = tab.data().options.strip();
            if (dvui.captured(tab.data().id)) {
                label_opts.color_text = .{ .name = .text_press };
            }

            dvui.labelNoFmt(@src(), @tagName(font_style), .{}, .{});
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
    var it = dvui.currentWindow().font_bytes.iterator();
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
        it = dvui.currentWindow().font_bytes.iterator();
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

const Styles = enum {
    accent,
    err,
};

fn styles(theme: *dvui.Theme) bool {
    var changed = false;

    const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 5 } });
    defer hbox.deinit();

    const active_style = dvui.dataGetPtrDefault(null, hbox.data().id, "Style", Styles, .accent);
    const style: *dvui.Theme.ColorStyles = switch (active_style.*) {
        inline else => |s| &@field(theme, "style_" ++ @tagName(s)),
    };

    const active_color = dvui.dataGetPtrDefault(null, hbox.data().id, "Color", Options.ColorAsk, .accent);

    {
        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .vertical }, .{ .expand = .vertical });
        tabs.install();
        defer tabs.deinit();

        inline for (comptime std.meta.tags(Options.ColorAsk), 0..) |color_ask, i| {
            const tab = tabs.addTab(active_color.* == color_ask, .{
                .expand = .horizontal,
                .padding = .all(2),
                .id_extra = i,
            });
            defer tab.deinit();

            if (tab.clicked()) {
                active_color.* = color_ask;
            }

            var label_opts = tab.data().options.strip();
            if (dvui.captured(tab.data().id)) {
                label_opts.color_text = .{ .name = .text_press };
            }

            const field = "color_" ++ @tagName(color_ask);
            const color: Options.ColorOrName = if (@field(style, field)) |color| color else switch (color_ask) {
                .accent => .{ .name = .accent },
                .text => .{ .name = .text },
                .text_press => .{ .name = .text_press },
                .fill => .{ .name = .fill },
                .fill_hover => .{ .name = .fill_hover },
                .fill_press => .{ .name = .fill_press },
                .border => .{ .name = .border },
            };

            const color_indicator = dvui.overlay(@src(), .{
                .expand = .ratio,
                .min_size_content = .all(10),
                .corner_radius = .all(100),
                .border = .all(1),
                .background = true,
                .color_fill = .fromColor(color.resolve()),
            });
            // Used to o
            const color_width = color_indicator.data().rectScale().r.w;
            color_indicator.deinit();
            dvui.labelNoFmt(@src(), @tagName(color_ask), .{}, .{ .margin = .{ .x = color_width } });
        }
    }

    var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .margin = .all(5) });
    defer vbox.deinit();

    var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
    tabs.install();
    defer tabs.deinit();

    inline for (comptime std.meta.tags(Styles), 0..) |style_choice, i| {
        const tab = tabs.addTab(active_style.* == style_choice, .{
            .expand = .horizontal,
            .padding = .all(2),
            .id_extra = i,
        });
        defer tab.deinit();

        if (tab.clicked()) {
            active_style.* = style_choice;
        }

        var label_opts = tab.data().options.strip();
        if (dvui.captured(tab.data().id)) {
            label_opts.color_text = .{ .name = .text_press };
        }
        dvui.labelNoFmt(@src(), @tagName(style_choice), .{}, .{});
    }

    const field: ?*Options.ColorOrName = switch (active_color.*) {
        inline else => |c| if (@field(style, "color_" ++ @tagName(c))) |*ptr| ptr else null,
    };
    const rgba_color: Options.ColorOrName = if (field) |ptr| ptr.* else switch (active_color.*) {
        .accent => .{ .name = .accent },
        .text => .{ .name = .text },
        .text_press => .{ .name = .text_press },
        .fill => .{ .name = .fill },
        .fill_hover => .{ .name = .fill_hover },
        .fill_press => .{ .name = .fill_press },
        .border => .{ .name = .border },
    };

    var hsv = dvui.Color.HSV.fromColor(rgba_color.resolve());
    if (dvui.colorPicker(@src(), .{ .hsv = &hsv, .dir = .horizontal }, .{})) {
        changed = true;
        if (field) |ptr| {
            ptr.* = .fromColor(hsv.toColor());
        } else switch (active_color.*) {
            inline else => |c| @field(style, "color_" ++ @tagName(c)) = .fromColor(hsv.toColor()),
        }
    }

    {
        const colors_from_theme = std.meta.tags(Options.ColorsFromTheme);
        const current_color: ?Options.ColorsFromTheme = if (field) |ptr| switch (ptr.*) {
            .name => |n| n,
            .color => null,
        } else null;
        var dd = dvui.DropdownWidget.init(@src(), .{
            .label = if (current_color) |c| @tagName(c) else "custom",
            .selected_index = if (current_color) |c| std.mem.indexOfScalar(Options.ColorsFromTheme, colors_from_theme, c) else null,
        }, .{
            .min_size_content = .{ .w = 110 },
        });
        dd.install();
        defer dd.deinit();
        if (dd.dropped()) {
            for (colors_from_theme) |color| {
                if (dd.addChoiceLabel(@tagName(color))) {
                    changed = true;
                    if (field) |ptr| {
                        ptr.* = .{ .name = color };
                    } else switch (active_color.*) {
                        inline else => |c| @field(style, "color_" ++ @tagName(c)) = .{ .name = color },
                    }
                }
            }
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
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .color_fill = .fill_window });
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
const Rect = dvui.Rect;
