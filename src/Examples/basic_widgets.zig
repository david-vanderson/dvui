var checkbox_gray: bool = true;
var checkbox_enabled: bool = true;
var checkbox_bool: bool = false;
var slider_vector_array = [_]f32{ 0, 1, 2 };
var slider_val: f32 = 0.0;
var slider_entry_val: f32 = 0.05;
var slider_entry_min: bool = true;
var slider_entry_max: bool = true;
var slider_entry_interval: bool = true;
var slider_entry_vector: bool = false;
var slider_entry_label: bool = false;
var icon_image_size_extra: f32 = 0;
var icon_image_rotation: f32 = 0;

const RadioChoice = enum(u8) {
    one = 1,
    two,
    _,
};
var radio_choice: RadioChoice = @enumFromInt(0);
var dropdown_val: usize = 1;

/// ![image](Examples-basic_widgets.png)
pub fn basicWidgets() void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Label", .{}, .{ .gravity_y = 0.5 });

        dvui.labelEx(@src(), "Multi-line\nLabel", .{}, .{ .align_x = 0.5 }, .{ .gravity_y = 0.5 });

        _ = dvui.button(@src(), "Button", .{}, .{ .gravity_y = 0.5 });
        _ = dvui.button(@src(), "Multi-line\nButton", .{}, .{ .gravity_y = 0.5 });

        var ttout: dvui.WidgetData = undefined;
        _ = dvui.button(@src(), "Button\nwith Tooltip", .{}, .{ .gravity_y = 0.5, .data_out = &ttout });
        dvui.tooltip(@src(), .{ .active_rect = ttout.borderRectScale().r }, "Here's a tooltip", .{}, .{});

        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            {
                var color: ?dvui.Options.ColorOrName = null;
                if (checkbox_gray) {
                    // blend text and control colors
                    color = .{ .color = dvui.Color.average(dvui.themeGet().color_text, dvui.themeGet().color_fill_control) };
                }
                var bw = dvui.ButtonWidget.init(@src(), .{}, .{
                    .color_text = color,
                    // If not enabled don't include in tab order (tab_index = 0). Otherwise use default tab index (tab_index = null).
                    .tab_index = if (checkbox_enabled) null else 0,
                });
                defer bw.deinit();
                bw.install();
                if (checkbox_enabled)
                    bw.processEvents();
                bw.drawBackground();
                bw.drawFocus();

                const opts = bw.data().options.strip().override(.{ .gravity_y = 0.5 });

                var bbox = dvui.box(@src(), .horizontal, opts);
                defer bbox.deinit();

                dvui.icon(
                    @src(),
                    "cycle",
                    entypo.cycle,
                    .{},
                    opts,
                );
                _ = dvui.spacer(@src(), .{ .min_size_content = .width(4) });
                dvui.labelNoFmt(@src(), "Icon+Gray", .{}, opts);

                if (bw.clicked() and checkbox_gray) {
                    dvui.toast(@src(), .{ .message = "This button is grayed out\nbut still clickable." });
                }
            }
            {
                var hbox_inner = dvui.box(@src(), .horizontal, .{});
                defer hbox_inner.deinit();
                _ = dvui.checkbox(@src(), &checkbox_gray, "Gray", .{});
                _ = dvui.checkbox(@src(), &checkbox_enabled, "Enabled", .{});
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Link:", .{}, .{ .gravity_y = 0.5 });

        if (dvui.labelClick(@src(), "https://david-vanderson.github.io/", .{}, .{}, .{ .gravity_y = 0.5, .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            _ = dvui.openURL("https://david-vanderson.github.io/");
        }

        if (dvui.labelClick(@src(), "docs", .{}, .{}, .{ .gravity_y = 0.5, .margin = .{ .x = 10 }, .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } } })) {
            _ = dvui.openURL("https://david-vanderson.github.io/docs");
        }
    }

    _ = dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Text Entry", .{}, .{ .gravity_y = 0.5 });
        var te = dvui.textEntry(@src(), .{}, .{});
        te.deinit();
    }

    inline for (@typeInfo(RadioChoice).@"enum".fields, 0..) |field, i| {
        if (dvui.radio(@src(), radio_choice == @as(RadioChoice, @enumFromInt(field.value)), "Radio " ++ field.name, .{ .id_extra = i })) {
            radio_choice = @enumFromInt(field.value);
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const entries = [_][]const u8{ "First", "Second", "Third is a really long one that doesn't fit" };

        _ = dvui.dropdown(@src(), &entries, &dropdown_val, .{ .min_size_content = .{ .w = 100 }, .gravity_y = 0.5 });

        dropdownAdvanced();
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 } });
        defer hbox.deinit();

        dvui.label(@src(), "Sliders", .{}, .{ .gravity_y = 0.5 });
        _ = dvui.slider(@src(), .horizontal, &slider_val, .{ .expand = .horizontal, .gravity_y = 0.5, .corner_radius = dvui.Rect.all(100) });
        _ = dvui.slider(@src(), .vertical, &slider_val, .{ .expand = .vertical, .min_size_content = .{ .w = 10 }, .corner_radius = dvui.Rect.all(100) });
        dvui.label(@src(), "Value: {d:2.2}", .{slider_val}, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Slider Entry", .{}, .{ .gravity_y = 0.5 });
        if (!slider_entry_vector) {
            var custom_label: ?[]u8 = null;
            if (slider_entry_label) {
                const whole = @round(slider_entry_val);
                const part = @round((slider_entry_val - whole) * 100);
                custom_label = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d} and {d}p", .{ whole, part }) catch null;
            }
            defer if (custom_label) |cl| dvui.currentWindow().lifo().free(cl);
            _ = dvui.sliderEntry(@src(), "val: {d:0.3}", .{ .value = &slider_entry_val, .min = (if (slider_entry_min) 0 else null), .max = (if (slider_entry_max) 1 else null), .interval = (if (slider_entry_interval) 0.1 else null), .label = custom_label }, .{ .gravity_y = 0.5 });
            dvui.label(@src(), "(enter, ctrl-click or touch-tap)", .{}, .{ .gravity_y = 0.5 });
        } else {
            _ = dvui.sliderVector(@src(), "{d:0.2}", 3, &slider_vector_array, .{ .min = (if (slider_entry_min) 0 else null), .max = (if (slider_entry_max) 1 else null), .interval = (if (slider_entry_interval) 0.1 else null) }, .{});
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .padding = .{ .x = 10 } });
        defer hbox.deinit();

        _ = dvui.checkbox(@src(), &slider_entry_min, "Min", .{});
        _ = dvui.checkbox(@src(), &slider_entry_max, "Max", .{});
        _ = dvui.checkbox(@src(), &slider_entry_interval, "Interval", .{});
        _ = dvui.checkbox(@src(), &slider_entry_vector, "Vector", .{});
        _ = dvui.checkbox(@src(), &slider_entry_label, "Custom Label", .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(4) });

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Raster Images", .{}, .{ .gravity_y = 0.5 });

        const image_source: dvui.ImageSource = .{ .imageFile = .{ .bytes = zig_favicon, .name = "zig favicon" } };
        const imgsize = dvui.imageSize(image_source) catch dvui.Size.all(50);
        _ = dvui.image(@src(), .{ .source = image_source }, .{
            .gravity_y = 0.5,
            .min_size_content = .{ .w = imgsize.w + icon_image_size_extra, .h = imgsize.h + icon_image_size_extra },
            .rotation = icon_image_rotation,
        });
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Svg Images", .{}, .{ .gravity_y = 0.5 });

        const zig_tvg_bytes = if (dvui.dataGetSlice(null, hbox.data().id, "_zig_tvg", []u8)) |tvg| tvg else blk: {
            // Could fail on OutOfMemory, but then the dataGetSlice would also panic
            const zig_tvg_bytes = dvui.svgToTvg(dvui.currentWindow().arena(), zig_svg) catch unreachable;
            defer dvui.currentWindow().arena().free(zig_tvg_bytes);
            dvui.dataSetSlice(null, hbox.data().id, "_zig_tvg", zig_tvg_bytes);
            break :blk dvui.dataGetSlice(null, hbox.data().id, "_zig_tvg", []u8).?;
        };

        const icon_opts = dvui.Options{ .gravity_y = 0.5, .min_size_content = .{ .h = 16 + icon_image_size_extra }, .rotation = icon_image_rotation };
        dvui.icon(@src(), "zig favicon", zig_tvg_bytes, .{}, icon_opts);
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Icons", .{}, .{ .gravity_y = 0.5 });

        const icon_opts = dvui.Options{ .gravity_y = 0.5, .min_size_content = .{ .h = 16 + icon_image_size_extra }, .rotation = icon_image_rotation };
        dvui.icon(@src(), "cycle", entypo.cycle, .{}, icon_opts);
        dvui.icon(@src(), "aircraft", entypo.aircraft, .{}, icon_opts);
        dvui.icon(@src(), "notes", entypo.beamed_note, .{}, icon_opts);

        if (dvui.button(@src(), "Icon Browser", .{}, .{ .gravity_y = 0.5 })) {
            Examples.icon_browser_show = true;
        }
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Resize Rotate Icons/Images", .{}, .{ .gravity_y = 0.5 });

        if (dvui.buttonIcon(
            @src(),
            "plus",
            entypo.plus,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_size_extra += 1;
        }

        if (dvui.buttonIcon(
            @src(),
            "minus",
            entypo.minus,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_size_extra = @max(0, icon_image_size_extra - 1);
        }

        if (dvui.buttonIcon(
            @src(),
            "cw",
            entypo.cw,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_rotation = icon_image_rotation + 5 * std.math.pi / 180.0;
        }

        if (dvui.buttonIcon(
            @src(),
            "ccw",
            entypo.ccw,
            .{},
            .{},
            .{ .gravity_y = 0.5 },
        )) {
            icon_image_rotation = icon_image_rotation - 5 * std.math.pi / 180.0;
        }
    }
}

pub fn dropdownAdvanced() void {
    const g = struct {
        var choice: ?usize = null;
    };

    var dd = dvui.DropdownWidget.init(@src(), .{ .selected_index = g.choice }, .{ .min_size_content = .{ .w = 100 } });
    dd.install();
    defer dd.deinit();

    // Here's what is shown when the dropdown is not dropped
    {
        var hbox2 = dvui.box(@src(), .horizontal, .{ .expand = .both });
        dvui.icon(
            @src(),
            "air",
            entypo.air,
            .{},
            .{ .gravity_y = 0.5 },
        );

        if (g.choice) |c| {
            dvui.label(@src(), "Dropdown Choice {d}", .{c}, .{ .gravity_y = 0.5, .padding = .{ .x = 6, .w = 6 } });
        } else {
            dvui.label(@src(), "Advanced Dropdown", .{}, .{ .gravity_y = 0.5, .padding = .{ .x = 6, .w = 6 } });
        }

        dvui.icon(
            @src(),
            "dropdown_triangle",
            entypo.chevron_small_down,
            .{},
            .{ .gravity_y = 0.5 },
        );

        hbox2.deinit();
    }

    if (dd.dropped()) {
        // The dropdown is dropped, now add all the choices
        {
            var mi = dd.addChoice();
            defer mi.deinit();

            var hbox2 = dvui.box(@src(), .horizontal, .{ .expand = .both });
            defer hbox2.deinit();

            var opts: Options = if (mi.show_active) dvui.themeGet().style_accent else .{};

            dvui.icon(
                @src(),
                "aircraft landing",
                entypo.aircraft_landing,
                .{},
                opts.override(.{ .gravity_y = 0.5 }),
            );
            dvui.labelNoFmt(@src(), "icon with text", .{}, opts.override(.{ .padding = .{ .x = 6 } }));

            if (mi.activeRect()) |_| {
                dd.close();
                g.choice = 0;
            }
        }

        if (dd.addChoiceLabel("just text")) {
            g.choice = 1;
        }
        {
            var mi = dd.addChoice();
            defer mi.deinit();

            var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
            defer vbox.deinit();

            var opts: Options = if (mi.show_active) dvui.themeGet().style_accent else .{};

            _ = dvui.image(@src(), .{ .source = .{ .imageFile = .{ .bytes = zig_favicon, .name = "zig favicon" } } }, opts.override(.{ .gravity_x = 0.5 }));
            dvui.labelNoFmt(@src(), "image above text", .{}, opts.override(.{ .gravity_x = 0.5, .padding = .{} }));

            if (mi.activeRect()) |_| {
                dd.close();
                g.choice = 2;
            }
        }
    }
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = @import("../Examples.zig");
const icon_browser = @import("icon_browser.zig").icon_browser;
const entypo = dvui.entypo;
const Options = dvui.Options;

const zig_favicon = Examples.zig_favicon;
const zig_svg = Examples.zig_svg;
