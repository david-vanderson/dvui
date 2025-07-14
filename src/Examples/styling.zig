var hsluv_hsl: dvui.Color.HSLuv = .fromColor(.black);
var hsv_color: dvui.Color.HSV = .fromColor(.black);
var backbox_color: dvui.Color = .black;

/// ![image](Examples-styling.png)
pub fn styling() void {
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        _ = dvui.button(@src(), "Accent", .{}, dvui.themeGet().accent());
        _ = dvui.button(@src(), "Error", .{}, dvui.themeGet().err());
        _ = dvui.button(@src(), "Window", .{}, .{ .color_fill = .fill_window });
        _ = dvui.button(@src(), "Content", .{}, .{ .color_fill = .fill });
        _ = dvui.button(@src(), "Control", .{}, .{});
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 9 } });
        defer hbox.deinit();

        dvui.label(@src(), "separators", .{}, .{ .gravity_y = 0.5 });

        _ = dvui.separator(@src(), .{ .expand = .horizontal, .gravity_y = 0.5 });
    }

    dvui.label(@src(), "corner radius", .{}, .{});
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const opts: Options = .{ .border = Rect.all(1), .background = true, .min_size_content = .{ .w = 20 } };

        _ = dvui.button(@src(), "0", .{}, opts.override(.{ .corner_radius = Rect.all(0) }));
        _ = dvui.button(@src(), "2", .{}, opts.override(.{ .corner_radius = Rect.all(2) }));
        _ = dvui.button(@src(), "7", .{}, opts.override(.{ .corner_radius = Rect.all(7) }));
        _ = dvui.button(@src(), "100", .{}, opts.override(.{ .corner_radius = Rect.all(100) }));
        _ = dvui.button(@src(), "mixed", .{}, opts.override(.{ .corner_radius = .{ .x = 0, .y = 2, .w = 7, .h = 100 } }));
    }

    dvui.label(@src(), "directly set colors", .{}, .{});
    {
        var picker = dvui.ColorPickerWidget.init(@src(), .{ .hsv = &hsv_color, .dir = .horizontal }, .{ .expand = .horizontal });
        picker.install();
        defer picker.deinit();
        if (picker.color_changed) {
            backbox_color = hsv_color.toColor();
            hsluv_hsl = .fromColor(backbox_color);
        }

        {
            var vbox = dvui.box(@src(), .vertical, .{});
            defer vbox.deinit();

            var backbox = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .h = 40 }, .expand = .horizontal, .background = true, .color_fill = .{ .color = backbox_color } });
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
            var vbox = dvui.box(@src(), .vertical, .{});
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
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        const border = dvui.dataGetPtrDefault(null, hbox.data().id, "border", bool, true);
        const radius = dvui.dataGetPtrDefault(null, hbox.data().id, "radius", f32, 5);
        const blur = dvui.dataGetPtrDefault(null, hbox.data().id, "blur", f32, 2);
        const shrink = dvui.dataGetPtrDefault(null, hbox.data().id, "shrink", f32, 0);
        const offset = dvui.dataGetPtrDefault(null, hbox.data().id, "offset", dvui.Point, .{ .x = 1, .y = 1 });
        const alpha = dvui.dataGetPtrDefault(null, hbox.data().id, "alpha", f32, 0.5);

        // We are using two boxes here so the box shadow can have different corner_radius values.

        {
            var vbox = dvui.box(@src(), .vertical, .{ .margin = dvui.Rect.all(30), .min_size_content = .{ .w = 200, .h = 100 }, .corner_radius = dvui.Rect.all(5), .background = true, .border = if (border.*) dvui.Rect.all(1) else null, .box_shadow = .{ .color = .fromColor(backbox_color), .corner_radius = dvui.Rect.all(radius.*), .shrink = shrink.*, .offset = offset.*, .blur = blur.*, .alpha = alpha.* } });
            defer vbox.deinit();
            dvui.label(@src(), "Box shadows", .{}, .{ .gravity_x = 0.5 });
            _ = dvui.checkbox(@src(), border, "border", .{});
            _ = dvui.sliderEntry(@src(), "radius: {d:0.0}", .{ .value = radius, .min = 0, .max = 50, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "blur: {d:0.1}", .{ .value = blur, .min = 0, .max = 50, .interval = 0.1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "shrink: {d:0.0}", .{ .value = shrink, .min = -10, .max = 50, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "x: {d:0.0}", .{ .value = &offset.x, .min = -20, .max = 20, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "y: {d:0.0}", .{ .value = &offset.y, .min = -20, .max = 20, .interval = 1 }, .{ .gravity_x = 0.5 });
            _ = dvui.sliderEntry(@src(), "alpha: {d:0.2}", .{ .value = alpha, .min = 0, .max = 1, .interval = 0.01 }, .{ .gravity_x = 0.5 });
        }
        {
            var vbox2 = dvui.box(@src(), .vertical, .{ .margin = .{ .y = 30 } });
            defer vbox2.deinit();

            const gradient = dvui.dataGetPtrDefault(null, vbox2.data().id, "gradient", usize, 0);

            {
                var gbox = dvui.box(@src(), .horizontal, .{});
                defer gbox.deinit();
                dvui.label(@src(), "Gradient", .{}, .{ .gravity_y = 0.5 });
                _ = dvui.dropdown(@src(), &.{ "flat", "horizontal", "vertical", "radial" }, gradient, .{});
            }

            var drawBox = dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 200, .h = 100 } });
            defer drawBox.deinit();
            const rs = drawBox.data().contentRectScale();

            var path: dvui.Path.Builder = .init(dvui.currentWindow().lifo());
            defer path.deinit();
            path.addRect(rs.r, dvui.Rect.Physical.all(5));

            var triangles = path.build().fillConvexTriangles(dvui.currentWindow().lifo(), .{ .center = rs.r.center() }) catch dvui.Triangles.empty;
            defer triangles.deinit(dvui.currentWindow().lifo());

            const ca0 = backbox_color;
            const ca1 = backbox_color.opacity(0);

            switch (gradient.*) {
                1, 2 => |choice| {
                    for (triangles.vertexes) |*v| {
                        const t = if (choice == 1)
                            (v.pos.x - rs.r.x) / rs.r.w
                        else
                            (v.pos.y - rs.r.y) / rs.r.h;
                        v.col = v.col.multiply(.fromColor(dvui.Color.lerp(ca0, ca1, t)));
                    }
                },
                3 => {
                    const center = rs.r.center();
                    const max = rs.r.bottomRight().diff(center).length();
                    for (triangles.vertexes) |*v| {
                        const l: f32 = v.pos.diff(center).length();
                        const t = l / max;
                        v.col = v.col.multiply(.fromColor(dvui.Color.lerp(ca0, ca1, t)));
                    }
                },
                else => {
                    triangles.color(ca0);
                },
            }
            dvui.renderTriangles(triangles, null) catch |err| {
                dvui.logError(@src(), err, "Could not render gradient triangles", .{});
            };
        }
    }
}

// Let's wrap the sliderEntry widget so we have 3 that represent a Color
pub fn rgbSliders(src: std.builtin.SourceLocation, color: *dvui.Color, opts: Options) bool {
    var hbox = dvui.boxEqual(src, .horizontal, opts);
    defer hbox.deinit();

    var red: f32 = @floatFromInt(color.r);
    var green: f32 = @floatFromInt(color.g);
    var blue: f32 = @floatFromInt(color.b);

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

    color.r = @intFromFloat(red);
    color.g = @intFromFloat(green);
    color.b = @intFromFloat(blue);

    return changed;
}

// Let's wrap the sliderEntry widget so we have 3 that represent a HSLuv Color
pub fn hsluvSliders(src: std.builtin.SourceLocation, hsluv: *dvui.Color.HSLuv, opts: Options) bool {
    var hbox = dvui.boxEqual(src, .horizontal, opts);
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
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
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
const Options = dvui.Options;
const Rect = dvui.Rect;
