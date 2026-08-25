const gradient_demo_orange: dvui.Color = .{ .r = 255, .g = 140, .b = 0, .a = 255 };
var hsluv_hsl: dvui.Color.HSLuv = .fromColor(gradient_demo_orange);
var hsv_color: dvui.Color.HSV = .fromColor(gradient_demo_orange);
var backbox_color: dvui.Color = gradient_demo_orange;

/// Shared controls for the gradient showcase below: kind (linear/radial/
/// scattered), linear angle or radial shape/extent/position or scattered
/// stop positions, an optional middle stop (linear/radial only), and the
/// base/stop-2 colors. `parent_id` should be the id of the currently-active
/// box so each demo's state is independent.
fn gradientDemoControls(parent_id: dvui.Id) dvui.ColorOrGradient {
    const kind = dvui.dataGetPtrDefault(null, parent_id, "kind", usize, 0);
    _ = dvui.dropdown(@src(), &.{ "linear", "radial", "scattered" }, .{ .choice = kind }, .{}, .{});

    const angle = dvui.dataGetPtrDefault(null, parent_id, "angle", f32, 147);
    const shape = dvui.dataGetPtrDefault(null, parent_id, "shape", usize, 1); // 0=circle, 1=ellipse
    const extent = dvui.dataGetPtrDefault(null, parent_id, "extent", usize, 3); // matches Gradient.Extent order
    const pos_x = dvui.dataGetPtrDefault(null, parent_id, "pos_x", f32, 0.5);
    const pos_y = dvui.dataGetPtrDefault(null, parent_id, "pos_y", f32, 0.5);

    const fixed_size = dvui.dataGetPtrDefault(null, parent_id, "fixed_size", bool, false);
    const size_x = dvui.dataGetPtrDefault(null, parent_id, "size_x", f32, 40);
    const size_y = dvui.dataGetPtrDefault(null, parent_id, "size_y", f32, 40);
    const use_focal = dvui.dataGetPtrDefault(null, parent_id, "use_focal", bool, false);
    const focal_x = dvui.dataGetPtrDefault(null, parent_id, "focal_x", f32, 0.5);
    const focal_y = dvui.dataGetPtrDefault(null, parent_id, "focal_y", f32, 0.5);
    const rotation = dvui.dataGetPtrDefault(null, parent_id, "rotation", f32, 0);

    if (kind.* == 0) {
        _ = dvui.sliderEntry(@src(), "angle: {d:0.0}", .{ .value = angle, .min = 0, .max = 360, .interval = 1 }, .{});
    } else if (kind.* == 1) {
        _ = dvui.dropdown(@src(), &.{ "circle", "ellipse" }, .{ .choice = shape }, .{}, .{});
        _ = dvui.checkbox(@src(), fixed_size, "fixed pixel size", .{});
        if (fixed_size.*) {
            _ = dvui.sliderEntry(@src(), "size x: {d:0.0}", .{ .value = size_x, .min = 1, .max = 150, .interval = 1 }, .{});
            if (shape.* != 0) _ = dvui.sliderEntry(@src(), "size y: {d:0.0}", .{ .value = size_y, .min = 1, .max = 150, .interval = 1 }, .{});
        } else {
            _ = dvui.dropdown(@src(), &.{ "closest_side", "farthest_side", "closest_corner", "farthest_corner" }, .{ .choice = extent }, .{}, .{});
        }
        _ = dvui.sliderEntry(@src(), "pos x: {d:0.2}", .{ .value = pos_x, .min = 0, .max = 1, .interval = 0.05 }, .{});
        _ = dvui.sliderEntry(@src(), "pos y: {d:0.2}", .{ .value = pos_y, .min = 0, .max = 1, .interval = 0.05 }, .{});
        if (shape.* != 0) _ = dvui.sliderEntry(@src(), "rotation: {d:0.0}", .{ .value = rotation, .min = 0, .max = 360, .interval = 1 }, .{});
        _ = dvui.checkbox(@src(), use_focal, "focal point", .{});
        if (use_focal.*) {
            _ = dvui.sliderEntry(@src(), "focal x: {d:0.2}", .{ .value = focal_x, .min = 0, .max = 1, .interval = 0.05 }, .{});
            _ = dvui.sliderEntry(@src(), "focal y: {d:0.2}", .{ .value = focal_y, .min = 0, .max = 1, .interval = 0.05 }, .{});
        }
    }

    if (kind.* != 2) {
        const multistop = dvui.dataGetPtrDefault(null, parent_id, "multistop", bool, false);
        const mid_color = dvui.dataGetPtrDefault(null, parent_id, "mid_color", dvui.Color, .purple);
        _ = dvui.checkbox(@src(), multistop, "extra middle stop", .{});
        if (multistop.*) {
            var midhbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer midhbox.deinit();
            dvui.label(@src(), "Mid: ", .{}, .{ .gravity_y = 0.5 });
            _ = dvui.textEntryColor(@src(), .{ .value = mid_color }, .{});
        }

        const base_color = dvui.dataGetPtrDefault(null, parent_id, "base_color", dvui.Color, .cyan);
        {
            var basehbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer basehbox.deinit();
            dvui.label(@src(), "Base: ", .{}, .{ .gravity_y = 0.5 });
            _ = dvui.textEntryColor(@src(), .{ .value = base_color }, .{});
        }
        {
            var stop2hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer stop2hbox.deinit();
            dvui.label(@src(), "Stop 2: ", .{}, .{ .gravity_y = 0.5 });
            if (dvui.textEntryColor(@src(), .{ .value = &backbox_color }, .{}).changed) {
                hsluv_hsl = .fromColor(backbox_color);
                hsv_color = .fromColor(backbox_color);
            }
        }

        // Frame-scoped: consumed immediately by the fill/border call below.
        // Base color is a stop at offset 0 and "Stop 2" at offset 1 -- chosen
        // for a familiar full-span gradient, not because Gradient.Stop requires
        // boundary stops (it doesn't: positions outside the stop range just
        // clamp to the nearest stop's color).
        const stops: []const dvui.Gradient.Stop = blk: {
            const n: usize = if (multistop.*) 3 else 2;
            const s = dvui.currentWindow().arena().alloc(dvui.Gradient.Stop, n) catch break :blk &.{};
            s[0] = .{ .color = base_color.*, .offset = 0 };
            if (multistop.*) {
                s[1] = .{ .color = mid_color.*, .offset = 0.5 };
                s[2] = .{ .color = backbox_color, .offset = 1 };
            } else {
                s[1] = .{ .color = backbox_color, .offset = 1 };
            }
            break :blk s;
        };

        const gradient: dvui.Gradient = if (kind.* == 0)
            .{ .linear = .{ .angle_degrees = angle.*, .stops = stops } }
        else
            .{ .radial = .{
                .shape = if (shape.* == 0)
                    .{ .circle = .{ .radius = if (fixed_size.*) size_x.* else null } }
                else
                    .{ .ellipse = .{
                        .size = if (fixed_size.*) .{ .x = size_x.*, .y = size_y.* } else null,
                        .rotation_degrees = rotation.*,
                    } },
                .extent = switch (extent.*) {
                    0 => .closest_side,
                    1 => .farthest_side,
                    2 => .closest_corner,
                    else => .farthest_corner,
                },
                .position = .{ .x = pos_x.*, .y = pos_y.* },
                .focal = if (use_focal.*) .{ .x = focal_x.*, .y = focal_y.* } else null,
                .stops = stops,
            } };

        return .{ .gradient = gradient };
    }

    // Scattered: a fixed set of freely-positioned color stops instead of a
    // linear/radial ramp -- each has its own x/y (fraction of the bounding
    // box) alongside its color.
    const scatter_stops = dvui.dataGetPtrDefault(null, parent_id, "scatter_stops", [3]dvui.Gradient.ScatterStop, .{
        .{ .color = .red, .x = 0.1, .y = 0.1 },
        .{ .color = .lime, .x = 0.9, .y = 0.2 },
        .{ .color = .blue, .x = 0.4, .y = 0.9 },
    });
    for (scatter_stops, 0..) |*stop, i| {
        var col = dvui.box(@src(), .{}, .{ .id_extra = i });
        defer col.deinit();
        {
            var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer row.deinit();
            dvui.label(@src(), "Stop {d}: ", .{i + 1}, .{ .gravity_y = 0.5 });
            _ = dvui.textEntryColor(@src(), .{ .value = &stop.color }, .{});
        }
        _ = dvui.sliderEntry(@src(), "x: {d:0.2}", .{ .value = &stop.x, .min = 0, .max = 1, .interval = 0.05 }, .{});
        _ = dvui.sliderEntry(@src(), "y: {d:0.2}", .{ .value = &stop.y, .min = 0, .max = 1, .interval = 0.05 }, .{});
    }

    return .{ .gradient = .{ .scattered = .{ .stops = scatter_stops } } };
}

/// ![image](Examples-styling.png)
pub fn styling() void {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        const start = dvui.dataGetPtrDefault(null, hbox.data().id, "start", f32, 5);
        const end = dvui.dataGetPtrDefault(null, hbox.data().id, "end", f32, 7);

        const txt = "Highlighted Label";
        dvui.labelEx(@src(), txt, .{}, .{ .sel_start = @trunc(@min(start.*, end.*)), .sel_end = @trunc(@max(start.*, end.*)) }, .{});

        _ = dvui.sliderEntry(@src(), "start: {d:0.0}", .{ .value = start, .min = 0, .max = txt.len, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "end: {d:0.0}", .{ .value = end, .min = 0, .max = txt.len, .interval = 1 }, .{});
    }

    {
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            dvui.label(@src(), "Styling Buttons", .{}, .{});
            _ = dvui.sliderEntry(@src(), "hover fade: {d:0.2}", .{ .value = &dvui.hover_fade_secs, .min = 0, .max = 1.0, .interval = 0.01 }, .{ .min_size_content = .width(200) });
        }

        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        _ = dvui.button(@src(), "Highlight", .{}, .{ .style = .highlight });
        _ = dvui.button(@src(), "Error", .{}, .{ .style = .err });
        _ = dvui.button(@src(), "Window", .{}, .{ .style = .window });
        _ = dvui.button(@src(), "Content", .{}, .{ .style = .content });
        _ = dvui.button(@src(), "Control", .{}, .{});

        _ = dvui.button(@src(), "Custom Fill", .{}, .{
            .color_fill = .purple,
            .color_fill_hover = .maroon,
            .color_fill_press = .magenta,
        });

        _ = dvui.button(@src(), "Custom Text", .{}, .{
            .color_text = .green,
            .color_text_hover = .blue,
            .color_text_press = .cyan,
            .color_border = .yellow,
            .border = .all(1),
        });
    }

    {
        dvui.label(@src(), "Other Hover States", .{}, .{});

        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer hbox.deinit();

        const checked = dvui.dataGetPtrDefault(null, hbox.data().id, "checked", bool, false);
        const choice = dvui.dataGetPtrDefault(null, hbox.data().id, "choice", usize, 0);
        const fraction = dvui.dataGetPtrDefault(null, hbox.data().id, "fraction", f32, 0.5);
        const value = dvui.dataGetPtrDefault(null, hbox.data().id, "value", f32, 0.5);

        var controls = dvui.box(@src(), .{}, .{ .min_size_content = .width(220) });
        defer controls.deinit();

        _ = dvui.checkbox(@src(), checked, "Checkbox", .{});
        if (dvui.radio(@src(), choice.* == 0, "Radio One", .{})) choice.* = 0;
        if (dvui.radio(@src(), choice.* == 1, "Radio Two", .{})) choice.* = 1;
        _ = dvui.slider(@src(), .{ .fraction = fraction }, .{ .expand = .horizontal });
        _ = dvui.sliderEntry(@src(), "value: {d:0.2}", .{ .value = value, .min = 0, .max = 1, .interval = 0.01 }, .{});

        var scroll = dvui.scrollArea(@src(), .{ .vertical_bar = .show }, .{ .min_size_content = .{ .w = 180, .h = 100 }, .max_size_content = .{ .w = 180, .h = 100 }, .style = .content, .color_text = .{ .color = dvui.themeGet().focus } });
        defer scroll.deinit();
        for (0..12) |i| {
            dvui.label(@src(), "Scroll item {d}", .{i}, .{ .id_extra = i });
        }
    }

    {
        dvui.label(@src(), "Pass Theme Directly", .{}, .{});

        var fbox = dvui.flexbox(@src(), .{}, .{});
        defer fbox.deinit();

        for (dvui.Theme.builtins, 0..) |theme, i| {
            var buf: [100]u8 = undefined;
            const b = std.fmt.bufPrint(&buf, "{s}", .{theme.name}) catch unreachable;
            _ = dvui.button(@src(), b, .{}, .{
                .id_extra = i,
                .theme = &theme,
            });
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .min_size_content = .{ .h = 9 } });
        defer hbox.deinit();

        dvui.label(@src(), "separators", .{}, .{ .gravity_y = 0.5 });

        _ = dvui.separator(@src(), .{ .expand = .horizontal, .gravity_y = 0.5 });
    }

    {
        var left_alignment = dvui.Alignment.init(@src(), 0);
        defer left_alignment.deinit();

        dvui.label(@src(), "Corner Styles", .{}, .{});
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            dvui.label(@src(), "Theme: ", .{}, .{});
            left_alignment.spacer(@src(), 0);

            const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };
            _ = dvui.button(@src(), "0", .{}, opts.override(.{ .corners = .all(0) }));
            _ = dvui.button(@src(), "2", .{}, opts.override(.{ .corners = .all(2) }));
            _ = dvui.button(@src(), "7", .{}, opts.override(.{ .corners = .all(7) }));
            _ = dvui.button(@src(), "100", .{}, opts.override(.{ .corners = .all(100) }));
            _ = dvui.button(@src(), "mixed", .{}, opts.override(.{ .corners = .{ .tr = .theme(2), .br = .theme(7), .bl = .theme(100) } }));
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            dvui.label(@src(), "Square: ", .{}, .{});
            left_alignment.spacer(@src(), 0);

            const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };
            _ = dvui.button(@src(), "0", .{}, opts.override(.{ .corners = .square }));
            _ = dvui.button(@src(), "2", .{}, opts.override(.{ .corners = .square }));
            _ = dvui.button(@src(), "7", .{}, opts.override(.{ .corners = .square }));
            _ = dvui.button(@src(), "100", .{}, opts.override(.{ .corners = .square }));
            _ = dvui.button(@src(), "mixed", .{}, opts.override(.{ .corners = .square }));
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            dvui.label(@src(), "Round: ", .{}, .{});
            left_alignment.spacer(@src(), 0);

            const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };
            _ = dvui.button(@src(), "0", .{}, opts.override(.{ .corners = .round(0) }));
            _ = dvui.button(@src(), "2", .{}, opts.override(.{ .corners = .round(2) }));
            _ = dvui.button(@src(), "7", .{}, opts.override(.{ .corners = .round(7) }));
            _ = dvui.button(@src(), "100", .{}, opts.override(.{ .corners = .round(100) }));
            _ = dvui.button(@src(), "mixed", .{}, opts.override(.{ .corners = .{ .tr = .round(2), .br = .round(7), .bl = .round(100) } }));
        }
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            dvui.label(@src(), "Chamfer: ", .{}, .{});
            left_alignment.spacer(@src(), 0);

            const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };
            _ = dvui.button(@src(), "0", .{}, opts.override(.{ .corners = .chamfer(0) }));
            _ = dvui.button(@src(), "2", .{}, opts.override(.{ .corners = .chamfer(2) }));
            _ = dvui.button(@src(), "7", .{}, opts.override(.{ .corners = .chamfer(7) }));
            _ = dvui.button(@src(), "100", .{}, opts.override(.{ .corners = .chamfer(100) }));
            _ = dvui.button(@src(), "mixed", .{}, opts.override(.{ .corners = .{ .tr = .chamfer(2), .br = .chamfer(7), .bl = .chamfer(100) } }));
        }
    }

    dvui.label(@src(), "directly set colors", .{}, .{});
    {
        var picker: dvui.ColorPickerWidget = undefined;
        picker.init(@src(), .{ .hsv = &hsv_color, .dir = .horizontal }, .{ .expand = .horizontal });
        defer picker.deinit();
        if (picker.color_changed) {
            backbox_color = hsv_color.toColor();
            hsluv_hsl = .fromColor(backbox_color);
        }

        {
            var vbox = dvui.box(@src(), .{}, .{});
            defer vbox.deinit();

            var backbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .min_size_content = .{ .h = 40 }, .expand = .horizontal, .background = true, .color_fill = .{ .color = backbox_color } });
            backbox.deinit();

            if (dvui.sliderEntry(@src(), "A: {d:0.2}", .{ .value = &hsv_color.a, .min = 0, .max = 1, .interval = 0.01 }, .{ .min_size_content = .{}, .expand = .horizontal })) {
                backbox_color = hsv_color.toColor();
                hsluv_hsl = .fromColor(backbox_color);
            }

            const res = dvui.textEntryColor(@src(), .{ .value = &backbox_color }, .{});
            if (res.changed) {
                hsluv_hsl = .fromColor(backbox_color);
                hsv_color = .fromColor(backbox_color);
            }
        }
        {
            var vbox = dvui.box(@src(), .{}, .{});
            defer vbox.deinit();

            if (rgbSliders(@src(), &backbox_color, .{})) {
                hsluv_hsl = .fromColor(backbox_color);
                hsv_color = .fromColor(backbox_color);
            }
            if (hsluvSliders(@src(), &hsluv_hsl, .{})) {
                backbox_color = hsluv_hsl.color();
                hsv_color = .fromColor(backbox_color);
            }
        }
    }

    {
        var hbox = dvui.flexbox(@src(), .{}, .{ .expand = .horizontal });
        defer hbox.deinit();

        const border = dvui.dataGetPtrDefault(null, hbox.data().id, "border", bool, true);
        const radius = dvui.dataGetPtrDefault(null, hbox.data().id, "radius", f32, 5);
        const fade = dvui.dataGetPtrDefault(null, hbox.data().id, "fade", f32, 2);
        const shrink = dvui.dataGetPtrDefault(null, hbox.data().id, "shrink", f32, 0);
        const offset = dvui.dataGetPtrDefault(null, hbox.data().id, "offset", dvui.Point, .{ .x = 1, .y = 1 });
        const alpha = dvui.dataGetPtrDefault(null, hbox.data().id, "alpha", f32, 0.5);

        {
            var vbox = dvui.box(@src(), .{}, .{ .margin = dvui.Rect.all(30), .min_size_content = .{ .w = 200, .h = 100 }, .corners = .all(5), .background = true, .border = if (border.*) dvui.Rect.all(1) else null, .box_shadow = .{ .color = backbox_color, .corners = .all(radius.*), .shrink = shrink.*, .offset = offset.*, .fade = fade.*, .alpha = alpha.* } });
            defer vbox.deinit();
            dvui.label(@src(), "Box shadows", .{}, .{ .gravity_x = 0.5 });
            _ = dvui.checkbox(@src(), border, "border", .{});
            _ = dvui.sliderEntry(@src(), "radius: {d:0.0}", .{ .value = radius, .min = 0, .max = 50, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "fade: {d:0.1}", .{ .value = fade, .min = 0, .max = 50, .interval = 0.1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "shrink: {d:0.0}", .{ .value = shrink, .min = -10, .max = 50, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "x: {d:0.0}", .{ .value = &offset.x, .min = -20, .max = 20, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "y: {d:0.0}", .{ .value = &offset.y, .min = -20, .max = 20, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "alpha: {d:0.2}", .{ .value = alpha, .min = 0, .max = 1, .interval = 0.01 }, .{ .gravity_x = 0.5 });
        }
        {
            var showcase_box = dvui.box(@src(), .{}, .{ .margin = .{ .y = 30 } });
            defer showcase_box.deinit();
            const showcase_id = showcase_box.data().id;

            dvui.label(@src(), "Gradient Showcase", .{}, .{});

            // Controls (left) and demo output (right) are separate columns so
            // that switching gradient kind -- which changes how many sliders
            // are visible -- resizes only the controls column instead of
            // shoving the demo output around underneath it.
            var showcase_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer showcase_hbox.deinit();

            var controls_vbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 220 } });
            const shape = dvui.dataGetPtrDefault(null, showcase_id, "showcase_target", usize, 4);
            _ = dvui.dropdown(@src(), &.{ "Box fill", "Box border", "Path.fill (star)", "Thick stroke", "Text", "Icon" }, .{ .choice = shape }, .{}, .{});

            const thickness = dvui.dataGetPtrDefault(null, showcase_id, "thickness", f32, 8);
            if (shape.* == 1 or shape.* == 3) {
                _ = dvui.sliderEntry(@src(), "thickness: {d:0.0}", .{ .value = thickness, .min = 1, .max = 20, .interval = 1 }, .{});
            }

            const text_buf = dvui.dataGetPtrDefault(null, showcase_id, "text_buf", [64:0]u8, blk: {
                var b: [64:0]u8 = @splat(0);
                const default_text = "Gradient\nText Demo";
                @memcpy(b[0..default_text.len], default_text);
                break :blk b;
            });
            if (shape.* == 4) {
                var te = dvui.textEntry(@src(), .{ .text = .{ .buffer = text_buf[0..] }, .multiline = true }, .{ .min_size_content = .{ .w = 200, .h = 40 } });
                te.deinit();
            }

            const icon_choice = dvui.dataGetPtrDefault(null, showcase_id, "icon_choice", icon_browser.IconChoice, .{ .name = "star", .tvg_bytes = dvui.entypo.star });
            const icon_browser_show = dvui.dataGetPtrDefault(null, showcase_id, "icon_browser_show", bool, false);
            if (shape.* == 5) {
                if (dvui.button(@src(), "Choose Icon...", .{}, .{})) icon_browser_show.* = true;
                if (icon_browser_show.*) {
                    icon_browser.iconBrowser(@src(), icon_browser_show, "entypo", dvui.entypo, icon_choice);
                }
            }

            const demo = gradientDemoControls(showcase_id);
            controls_vbox.deinit();

            var demo_vbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 220, .h = 140 }, .gravity_y = 0 });
            defer demo_vbox.deinit();

            switch (shape.*) {
                0 => {
                    var gbox = dvui.box(@src(), .{}, .{
                        .min_size_content = .{ .w = 200, .h = 100 },
                        .corners = .all(5),
                        .background = true,
                        .color_fill = demo,
                    });
                    defer gbox.deinit();
                },
                1 => {
                    var bbox = dvui.box(@src(), .{}, .{
                        .min_size_content = .{ .w = 200, .h = 100 },
                        .corners = .all(5),
                        .border = dvui.Rect.all(thickness.*),
                        .color_border = demo,
                    });
                    defer bbox.deinit();
                },
                2 => {
                    var sbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 200, .h = 100 } });
                    defer sbox.deinit();

                    // Star is deliberately concave: it must go through
                    // earcut-based Path.fillTriangles (via Path.fill), not the
                    // convex fan path fillConvexTriangles uses.
                    const rs = sbox.data().contentRectScale();
                    var builder: dvui.Path.Builder = .init(dvui.currentWindow().arena());
                    defer builder.deinit();
                    const cx = 100;
                    const cy = 50;
                    const outer = 45;
                    const inner = 18;
                    var i: usize = 0;
                    while (i < 10) : (i += 1) {
                        const r: f32 = if (i % 2 == 0) outer else inner;
                        const a = -std.math.pi / 2.0 + @as(f32, @floatFromInt(i)) * std.math.pi / 5.0;
                        builder.addPoint(rs.pointToPhysical(.{ .x = cx + r * @cos(a), .y = cy + r * @sin(a) }));
                    }
                    const star = builder.build();

                    dvui.Path.fill(&.{star}, .{
                        .color = demo,
                    });
                },
                3 => {
                    var lbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 200, .h = 100 } });
                    defer lbox.deinit();

                    const rs = lbox.data().contentRectScale();
                    var builder: dvui.Path.Builder = .init(dvui.currentWindow().arena());
                    defer builder.deinit();
                    builder.addPoint(rs.pointToPhysical(.{ .x = 10, .y = 10 }));
                    builder.addPoint(rs.pointToPhysical(.{ .x = 190, .y = 30 }));
                    builder.addPoint(rs.pointToPhysical(.{ .x = 40, .y = 90 }));
                    const line = builder.build();

                    line.stroke(.{ .thickness = thickness.*, .color = demo });
                },
                4 => {
                    var tbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 200, .h = 100 } });
                    defer tbox.deinit();

                    // Vertex colors are sampled once per glyph corner against this
                    // label's own rect -- see `render.TextOptions.gradient`'s doc
                    // comment for why that's fine for text (unlike fills).
                    dvui.labelNoFmt(@src(), std.mem.sliceTo(text_buf[0..], 0), .{}, .{
                        .font = dvui.Font.theme(.title),
                        .color_text = demo,
                        .gravity_x = 0.5,
                        .gravity_y = 0.5,
                    });
                },
                else => {
                    var ibox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 200, .h = 100 }, .gravity_x = 0.5, .gravity_y = 0.5 });
                    defer ibox.deinit();

                    dvui.icon(@src(), icon_choice.name, icon_choice.tvg_bytes, .{ .fill_color = demo, .stroke_color = demo }, .{
                        .min_size_content = .{ .h = 80 },
                        .gravity_x = 0.5,
                        .gravity_y = 0.5,
                    });
                },
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer hbox.deinit();

        const width = dvui.dataGetPtrDefault(null, hbox.data().id, "width", f32, 24);
        const height = dvui.dataGetPtrDefault(null, hbox.data().id, "height", f32, 24);

        {
            var vbox = dvui.box(@src(), .{}, .{ .background = true, .border = .all(1) });
            defer vbox.deinit();

            dvui.label(@src(), "Ninepatch", .{}, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "width: {d:0.0}", .{ .value = width, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "height: {d:0.0}", .{ .value = height, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_x = 0.5 });
        }
        {
            var vbox = dvui.box(@src(), .{}, .{
                .min_size_content = .{ .w = width.*, .h = height.* },
                .max_size_content = .{ .w = width.*, .h = height.* },
                .gravity_x = 0.5,
                .gravity_y = 0.5,
            });
            defer vbox.deinit();

            var ninepatch = dvui.box(@src(), .{}, .{
                .expand = .both,
                .style = .control,
                .ninepatch_fill = &@import("../themes/win98.zig").raised,
                .background = true,
            });
            defer ninepatch.deinit();
        }
    }
}

// Let's wrap the sliderEntry widget so we have 3 that represent a Color
pub fn rgbSliders(src: std.builtin.SourceLocation, color: *dvui.Color, opts: Options) bool {
    var hbox = dvui.box(src, .{ .dir = .horizontal, .equal_space = true }, opts);
    defer hbox.deinit();

    var red: f32 = color.r;
    var green: f32 = color.g;
    var blue: f32 = color.b;

    var changed = false;
    if (dvui.sliderEntry(@src(), "R: {d:0.0}", .{ .value = &red, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "G: {d:0.0}", .{ .value = &green, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "B: {d:0.0}", .{ .value = &blue, .min = 0, .max = 255, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }

    color.r = @trunc(red);
    color.g = @trunc(green);
    color.b = @trunc(blue);

    return changed;
}

// Let's wrap the sliderEntry widget so we have 3 that represent a HSLuv Color
pub fn hsluvSliders(src: std.builtin.SourceLocation, hsluv: *dvui.Color.HSLuv, opts: Options) bool {
    var hbox = dvui.box(src, .{ .dir = .horizontal, .equal_space = true }, opts);
    defer hbox.deinit();

    var changed = false;
    if (dvui.sliderEntry(@src(), "H: {d:0.0}", .{ .value = &hsluv.h, .min = 0, .max = 360, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "S: {d:0.0}", .{ .value = &hsluv.s, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }
    if (dvui.sliderEntry(@src(), "L: {d:0.0}", .{ .value = &hsluv.l, .min = 0, .max = 100, .interval = 1 }, .{ .gravity_y = 0.5 })) {
        changed = true;
    }

    return changed;
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG styling" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            styling();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-styling.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = @import("../Examples.zig");
const icon_browser = @import("icon_browser.zig");
const Options = dvui.Options;
const Rect = dvui.Rect;
const CornerRect = dvui.CornerRect;
