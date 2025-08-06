var layout_margin: Rect = Rect.all(4);
var layout_border: Rect = Rect.all(0);
var layout_padding: Rect = Rect.all(4);
var layout_gravity_x: f32 = 0.5;
var layout_gravity_y: f32 = 0.5;
var layout_rotation: f32 = 0;
var layout_corner_radius: Rect = Rect.all(5);
var layout_flex_content_justify: dvui.FlexBoxWidget.ContentPosition = .center;
var layout_expand: dvui.Options.Expand = .none;
var paned_collapsed_width: f32 = 400;

/// ![image](Examples-layout.png)
pub fn layout() void {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        const Static = struct {
            var img: bool = false;
            var shrink: bool = false;
            var background: bool = false;
            var border: bool = false;
            var shrinkE: dvui.Options.Expand = .none;
            var size: Size = .{ .w = 16, .h = 16 };
            var uv: Rect = .{ .w = 1, .h = 1 };
        };

        {
            var vbox = dvui.box(@src(), .{}, .{});
            defer vbox.deinit();

            {
                var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                defer hbox2.deinit();

                dvui.label(@src(), "Layout", .{}, .{});
                _ = dvui.checkbox(@src(), &Static.img, "Image", .{});
            }

            if (Static.img) {
                dvui.label(@src(), "Min Size", .{}, .{});
                _ = dvui.sliderEntry(@src(), "W: {d:0.0}", .{ .value = &Static.size.w, .min = 1, .max = 400, .interval = 1 }, .{});
                _ = dvui.sliderEntry(@src(), "H: {d:0.0}", .{ .value = &Static.size.h, .min = 1, .max = 280, .interval = 1 }, .{});

                _ = dvui.checkbox(@src(), &Static.shrink, "Shrink", .{});
                _ = dvui.checkbox(@src(), &Static.background, "Background", .{});
                _ = dvui.checkbox(@src(), &Static.border, "Border", .{});
            }

            var opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 200, .h = 140 } };
            if (Static.shrink) {
                opts.max_size_content = .size(opts.min_size_contentGet());
            }

            var o = dvui.box(@src(), .{}, opts);
            defer o.deinit();
            const old_clip = dvui.clip(o.data().backgroundRectScale().r);
            defer dvui.clipSet(old_clip);

            const options: Options = .{ .gravity_x = layout_gravity_x, .gravity_y = layout_gravity_y, .expand = layout_expand, .rotation = layout_rotation, .corner_radius = layout_corner_radius };
            if (Static.img) {
                _ = dvui.image(@src(), .{
                    .source = .{ .imageFile = .{ .bytes = Examples.zig_favicon, .name = "zig favicon" } },
                    .shrink = if (Static.shrink) Static.shrinkE else null,
                    .uv = Static.uv,
                }, options.override(
                    .{
                        .min_size_content = Static.size,
                        .background = Static.background,
                        .color_fill = .{ .color = dvui.themeGet().color_text },
                        .border = if (Static.border) Rect.all(1) else null,
                    },
                ));
            } else {
                var buf: [128]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "{d:0.2},{d:0.2}", .{ layout_gravity_x, layout_gravity_y }) catch unreachable;
                _ = dvui.button(@src(), label, .{}, options);
            }
        }

        {
            var vbox = dvui.box(@src(), .{}, .{});
            defer vbox.deinit();
            dvui.label(@src(), "Gravity", .{}, .{});
            _ = dvui.sliderEntry(@src(), "X: {d:0.2}", .{ .value = &layout_gravity_x, .min = 0, .max = 1.0, .interval = 0.01 }, .{});
            _ = dvui.sliderEntry(@src(), "Y: {d:0.2}", .{ .value = &layout_gravity_y, .min = 0, .max = 1.0, .interval = 0.01 }, .{});
            dvui.label(@src(), "Corner Radius", .{}, .{});
            inline for (0.., @typeInfo(dvui.Rect).@"struct".fields) |i, field| {
                _ = dvui.sliderEntry(@src(), field.name ++ ": {d:0}", .{ .min = 0, .max = 200, .interval = 1, .value = &@field(layout_corner_radius, field.name) }, .{ .id_extra = i });
            }
            if (Static.img) {
                dvui.label(@src(), "Rotation", .{}, .{});
                _ = dvui.sliderEntry(@src(), "{d:0.2} radians", .{ .value = &layout_rotation, .min = std.math.pi * -2, .max = std.math.pi * 2, .interval = 0.01 }, .{});
            }
        }

        {
            var vbox = dvui.box(@src(), .{}, .{});
            defer vbox.deinit();
            dvui.label(@src(), "Expand", .{}, .{});
            inline for (std.meta.tags(dvui.Options.Expand)) |opt| {
                if (dvui.radio(@src(), layout_expand == opt, @tagName(opt), .{ .id_extra = @intFromEnum(opt) })) {
                    layout_expand = opt;
                }
            }

            if (Static.img) {
                dvui.label(@src(), "UVs", .{}, .{});
                if (dvui.sliderEntry(@src(), "u x: {d:0.2}", .{ .min = 0, .max = 1, .value = &Static.uv.x }, .{})) {
                    Static.uv.w = std.math.clamp(Static.uv.w, 0.0, 1.0 - Static.uv.x);
                }
                _ = dvui.sliderEntry(@src(), "u w: {d:0.2}", .{ .min = 0, .max = 1.0 - Static.uv.x, .value = &Static.uv.w }, .{});
                if (dvui.sliderEntry(@src(), "v y: {d:0.2}", .{ .min = 0, .max = 1, .value = &Static.uv.y }, .{})) {
                    Static.uv.h = std.math.clamp(Static.uv.h, 0.0, 1.0 - Static.uv.y);
                }
                _ = dvui.sliderEntry(@src(), "v h: {d:0.2}", .{ .min = 0, .max = 1.0 - Static.uv.y, .value = &Static.uv.h }, .{});
            }
        }

        if (Static.shrink) {
            var vbox = dvui.box(@src(), .{}, .{});
            defer vbox.deinit();
            dvui.label(@src(), "Shrink", .{}, .{});
            inline for (std.meta.tags(dvui.Options.Expand)) |opt| {
                if (dvui.radio(@src(), Static.shrinkE == opt, @tagName(opt), .{ .id_extra = @intFromEnum(opt) })) {
                    Static.shrinkE = opt;
                }
            }
        }
    }

    dvui.label(@src(), "margin/border/padding", .{}, .{});
    {
        var vbox = dvui.box(@src(), .{}, .{});
        defer vbox.deinit();

        var vbox2 = dvui.box(@src(), .{}, .{ .gravity_x = 0.5 });
        _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.y, .min = 0, .max = 20.0, .interval = 1 }, .{});
        vbox2.deinit();
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();
            {
                vbox2 = dvui.box(@src(), .{}, .{ .gravity_y = 0.5 });
                defer vbox2.deinit();
                _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
                _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
                _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.x, .min = 0, .max = 20.0, .interval = 1 }, .{});
            }
            {
                var o = dvui.overlay(@src(), .{ .min_size_content = .{ .w = 164, .h = 140 } });
                defer o.deinit();
                var o2 = dvui.overlay(@src(), .{ .background = true, .gravity_x = 0.5, .gravity_y = 0.5 });
                defer o2.deinit();
                if (dvui.button(@src(), "reset", .{}, .{ .margin = layout_margin, .border = layout_border, .padding = layout_padding })) {
                    layout_margin = Rect.all(4);
                    layout_border = Rect.all(0);
                    layout_padding = Rect.all(4);
                }
            }
            {
                vbox2 = dvui.box(@src(), .{}, .{ .gravity_y = 0.5 });
                defer vbox2.deinit();
                _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
                _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
                _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.w, .min = 0, .max = 20.0, .interval = 1 }, .{});
            }
        }
        {
            vbox2 = dvui.box(@src(), .{}, .{ .gravity_x = 0.5 });
            defer vbox2.deinit();
            _ = dvui.sliderEntry(@src(), "margin {d:0.0}", .{ .value = &layout_margin.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
            _ = dvui.sliderEntry(@src(), "border {d:0.0}", .{ .value = &layout_border.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
            _ = dvui.sliderEntry(@src(), "padding {d:0.0}", .{ .value = &layout_padding.h, .min = 0, .max = 20.0, .interval = 1 }, .{});
        }
    }

    dvui.label(@src(), "Boxes", .{}, .{});
    {
        const opts: Options = .{ .expand = .both, .border = Rect.all(1), .background = true };

        const breakpoint: f32 = 400;
        const equal = dvui.parentGet().data().contentRect().w > breakpoint;

        var hbox = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal, .equal_space = equal, .num_packed_expanded = if (equal) 2 else 1 }, .{ .expand = .horizontal });
        hbox.install();
        hbox.drawBackground();
        defer hbox.deinit();
        {
            var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .min_size_content = .{ .w = breakpoint / 2, .h = 140 }, .max_size_content = .width(breakpoint / 2), .expand = if (equal) .horizontal else .none });
            defer hbox2.deinit();
            {
                var vbox = dvui.box(@src(), .{}, opts);
                defer vbox.deinit();

                _ = dvui.button(@src(), "vertical", .{}, .{ .gravity_x = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_x = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_x = 0.5 });
            }
            {
                var vbox = dvui.box(@src(), .{ .equal_space = true }, opts);
                defer vbox.deinit();

                _ = dvui.button(@src(), "vert equal", .{}, .{ .gravity_x = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_x = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_x = 0.5 });
            }
        }
        {
            var vbox2 = dvui.box(@src(), .{}, .{ .max_size_content = .zero, .expand = .both });
            defer vbox2.deinit();
            {
                var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, opts);
                defer hbox2.deinit();

                _ = dvui.button(@src(), "horizontal", .{}, .{ .gravity_y = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_y = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_y = 0.5 });
            }
            {
                var hbox2 = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, opts);
                defer hbox2.deinit();

                _ = dvui.button(@src(), "horiz\nequal", .{}, .{ .gravity_y = 0.5 });
                _ = dvui.button(@src(), "expand", .{}, .{ .expand = .both, .gravity_y = 0.5 });
                _ = dvui.button(@src(), "a", .{}, .{ .gravity_y = 0.5 });
            }
        }
    }
    {
        {
            var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox2.deinit();
            dvui.label(@src(), "FlexBox", .{}, .{});
            inline for (std.meta.tags(dvui.FlexBoxWidget.ContentPosition)) |opt| {
                if (dvui.radio(@src(), layout_flex_content_justify == opt, @tagName(opt), .{ .id_extra = @intFromEnum(opt) })) {
                    layout_flex_content_justify = opt;
                }
            }
        }
        {
            var fbox = dvui.flexbox(@src(), .{ .justify_content = layout_flex_content_justify }, .{
                .border = dvui.Rect.all(1),
                .background = true,
                .padding = .{ .w = 4, .h = 4 },
                .expand = .horizontal,
            });
            defer fbox.deinit();

            for (0..11) |i| {
                var labelbox = dvui.box(@src(), .{}, .{ .id_extra = i, .margin = .{ .x = 4, .y = 4 }, .border = dvui.Rect.all(1), .background = true });
                defer labelbox.deinit();

                if (i % 2 == 0) {
                    dvui.label(@src(), "Box {d}", .{i}, .{ .expand = .both, .gravity_x = 0.5, .gravity_y = 0.5 });
                } else {
                    dvui.label(@src(), "Large\nBox {d}", .{i}, .{ .expand = .both, .gravity_x = 0.5, .gravity_y = 0.5 });
                }
            }
        }
    }
    dvui.label(@src(), "Collapsible Pane with Draggable Sash", .{}, .{});
    {
        var paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = paned_collapsed_width, .handle_margin = 4 }, .{ .expand = .horizontal, .background = false, .min_size_content = .{ .h = 130 } });
        defer paned.deinit();

        if (paned.showFirst()) {
            var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .border = .all(1) });
            defer vbox.deinit();

            dvui.label(@src(), "Left Side", .{}, .{});
            dvui.label(@src(), "collapses when width < {d}", .{paned_collapsed_width}, .{});
            dvui.label(@src(), "current width {d}", .{paned.data().rect.w}, .{});
            if (paned.collapsed() and dvui.button(@src(), "Goto Right", .{}, .{})) {
                paned.animateSplit(0.0);
            }
        }

        if (paned.showSecond()) {
            var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .border = .all(1) });
            defer vbox.deinit();

            dvui.label(@src(), "Right Side", .{}, .{});
            if (paned.collapsed() and dvui.button(@src(), "Goto Left", .{}, .{})) {
                paned.animateSplit(1.0);
            }
        }
    }
    _ = dvui.sliderEntry(@src(), "collapse under {d:0.0}", .{ .value = &paned_collapsed_width, .min = 100, .max = 600, .interval = 10 }, .{});

    dvui.label(@src(), "Auto-Fit Panes", .{}, .{});
    {
        var paned = dvui.paned(@src(), .{
            .direction = .vertical,
            .handle_margin = 4,
            .collapsed_size = 0,
            .autofit_first = .{ .min_split = 0.2, .max_split = 0.8, .min_size = 50 },
        }, .{ .expand = .both, .background = false, .min_size_content = .{ .h = 250 } });
        defer paned.deinit();

        if (paned.showFirst()) {
            var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .border = .all(1) });
            defer vbox.deinit();

            dvui.label(@src(), "Top Side\nWith multiple lines of content\nWhere the first pane fits the content", .{}, .{});
            _ = dvui.button(@src(), "With this button right above the split", .{}, .{});
        }

        if (paned.showSecond()) {
            var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .border = .all(1) });
            defer vbox.deinit();

            dvui.label(@src(), "Bottom Side", .{}, .{});
        }
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG layout" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 800 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            layout();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-layout.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = @import("../Examples.zig");
const Size = dvui.Size;
const Rect = dvui.Rect;
const Options = dvui.Options;
