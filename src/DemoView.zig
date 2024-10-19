const dvui = @import("dvui.zig");
const std = @import("std");

const Rect = dvui.Rect;
const demo_box_size = 120; // size of demo image, obviously
const demo_pad      = 5;   // space between demos

const DemoFn = *const fn() anyerror!void;
pub const Demo = struct{
    scale: f32,
    ui_fn: DemoFn,
    label: [] const u8
};

fn demoButton(src: std.builtin.SourceLocation, demo: Demo) !bool {
    const USE_AUTOSCALING = false;
    const USE_STATIC_IMAGE = false;

    // initialize widget and get rectangle from parent
    var bw = dvui.ButtonWidget.init(src, .{}, .{ .id_extra = @intFromPtr(demo.ui_fn), .margin = .{}, .padding = .{} });

    // make ourselves the new parent
    try bw.install();

    // process events (mouse and keyboard)
    bw.processEvents();

    // use pressed text color if desired
    const click = bw.clicked();
    var options: dvui.Options = .{ .gravity_x = 0.5, .gravity_y = 0.5 };

    if (dvui.captured(bw.wd.id)) options = options.override(.{ .color_text = .{ .color = options.color(.text_press) } });

    // this child widget:
    // - has bw as parent
    // - gets a rectangle from bw
    // - draws itself
    // - reports its min size to bw
    {
        var demo_box = try dvui.box(
            @src(),
            .vertical,
            .{
                .border = Rect.all(1),
                .min_size_content = .{ .w = demo_box_size, .h = demo_box_size },
                .margin = Rect.all(demo_pad),
                .color_fill = .{ .name = if (bw.hover) .fill_hover else .fill }
            }
        );
        defer demo_box.deinit();


         if (USE_STATIC_IMAGE) {
            // This code uses an image for a thumbnail, instead of dynamically visualizing the UI code.

            const zig_favicon = @embedFile("zig-favicon.png");
            try dvui.image(@src(), "zig favicon", zig_favicon, .{
                .gravity_x = 0.5,
                .gravity_y = 0.5,
                .expand = .both,
                .min_size_content = .{ .w = 100, .h = 100 },
                .rotation = 0,
            });
        } else {
            const thumbnail_size = 100;
            const thumbnail_src = @src();
            const id = dvui.parentGet().extendId(src, 0);
            // Calling rectFor here seems especially important to reserve space for the label at the bottom
            const rect = dvui.parentGet().rectFor(id, .{ .w = thumbnail_size, .h = thumbnail_size-3 }, .none, .{ .x = 0.5, .y = 0.5 });

            var b = try dvui.box(
                thumbnail_src,
                .vertical,
                .{
                    .rect = .{ .x = rect.x, .y = rect.y, .w = thumbnail_size, .h = thumbnail_size },
                    .expand = .none,
                }
            );
            defer b.deinit();

            var _scaler = scaler: {
                if (!USE_AUTOSCALING) {
                    const scaler = try dvui.scale(@src(), demo.scale, .{ .expand = .horizontal });
                    break :scaler scaler;
                } if (USE_AUTOSCALING) {
                    // This code uses a PID/Monte Carlo-style approach to dynamically size the demos to fit in their boxes.

                    const scaler_src = @src();

                    const scaler_id = dvui.parentGet().extendId(scaler_src, 0);
                    const scale = dvui.dataGet(null, scaler_id, "_bestScale", f32) orelse 0.2;
                    const scaler = try dvui.scale(scaler_src, scale, .{ .expand = .horizontal });

                    if (scaler.box.wd.rect.h > 0) {
                        const ideal_scale = @max(0.1, scale / (scale * scaler.box.wd.rect.h / thumbnail_size));
                        const delta = (ideal_scale - scale);
                        const delta_magnitude = @abs(delta);
                        const delta_sign: f32 = if (delta < 0) -1.0 else 1.0;

                        dvui.dataSet(null, scaler_id, "_bestScale", scale + @min(0.05, delta_magnitude) * delta_sign);

                        std.debug.print("{s} utlization {d}\n", .{demo.label, ideal_scale});
                    }

                    break :scaler scaler;
                }
            };
            defer _scaler.deinit();
            
            try demo.ui_fn();
        }

        try dvui.labelNoFmt(@src(), demo.label, .{
            .margin = .{ .x = 4, .w = 4 },
            .gravity_x = 0.5,
            .font_style = .title_4
        });
    }

    // draw focus
    try bw.drawFocus();

    // restore previous parent
    // send our min size to parent
    bw.deinit();

    return click;
}

var demo_active: ?Demo = null;
pub fn demoView(backend_demos: []const Demo) !void {

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    if (demo_active) |demo| {
        {
            var b = try dvui.box(@src(), .horizontal, .{});
            defer b.deinit();

            if (try dvui.button(@src(), "<", .{}, .{ .gravity_y = 0.5 })) {
                demo_active = null;
            }
            try dvui.labelNoFmt(@src(), demo.label, .{ .margin = .{ .x = 4, .y = 4, .w = 4 }, .font_style = .title_1 });
        }

        try demo.ui_fn();
    } else {
        try dvui.labelNoFmt(@src(), "DVUI Demos", .{ .margin = .{ .x = 4, .y = 12, .w = 4 }, .font_style = .title_1, .gravity_x = 0.5 });

        var demo_area_pad = try dvui.box(
            @src(),
            .horizontal,
            .{
                .padding = Rect.all(5),
                .expand = .both,
            }
        );
        defer demo_area_pad.deinit();
        var demo_area = try dvui.box(
            @src(),
            .vertical,
            .{
                .padding = Rect.all(5),
                .expand = .both,
            }
        );
        defer demo_area.deinit();

        const demo_area_space = @max(demo_area.childRect.w, demo_pad*2 + 1);

        try layoutDemos(demo_area_space, &[_]Demo{
            .{ .ui_fn = dvui.Examples.incrementor,        .scale = 1.150, .label = "Incrementor" },
            .{ .ui_fn = dvui.Examples.calculator,         .scale = 0.600, .label = "Calculator" },

            .{ .ui_fn = dvui.Examples.basicWidgets,       .scale = 0.330, .label = "Basic Widgets" },
            .{ .ui_fn = dvui.Examples.textEntryWidgets,   .scale = 0.449, .label = "Text Entry" },

            .{ .ui_fn = dvui.Examples.reorderLists,       .scale = 0.291, .label = "Reorderables" },
            .{ .ui_fn = dvui.Examples.menus,              .scale = 0.431, .label = "Menus" },
            .{ .ui_fn = dvui.Examples.focus,              .scale = 0.737, .label = "Focus" },

            .{ .ui_fn = dvui.Examples.scrolling,          .scale = 0.414, .label = "Scrolling" },
            .{ .ui_fn = dvui.Examples.animations,         .scale = 0.512, .label = "Animations" },

            .{ .ui_fn = dvui.Examples.themeEditor,        .scale = 0.434, .label = "Theme Editor" },
            .{ .ui_fn = dvui.Examples.themeSerialization, .scale = 0.812, .label = "Save Theme" },

            .{ .ui_fn = dvui.Examples.layout,             .scale = 0.200, .label = "Layout" },
            .{ .ui_fn = dvui.Examples.layoutText,         .scale = 0.350, .label = "Text Layout" },
            .{ .ui_fn = dvui.Examples.styling,            .scale = 0.516, .label = "Styling" },

            .{ .ui_fn = dvui.Examples.debuggingErrors,    .scale = 0.437, .label = "Debugging" },

            // TODO: toasts requires a window to point at ...
            // TODO: "auto-widget from struct" requires factoring into function

        });

        {
            var b = try dvui.box(
                @src(),
                .vertical,
                .{
                    .expand = .both,
                }
            );
            defer b.deinit();

            try dvui.labelNoFmt(
                @src(),
                "Platform-specific demos",
                .{
                    .margin = .{ .x = 4, .y = 12, .w = 4 },
                    .font_style = .title_1,
                    .gravity_x = 0.5
                }
            );
            try layoutDemos(demo_area_space, backend_demos);
        }
    }
}

fn layoutDemos(width: f32, demos: []const Demo) !void {
    const demo_area_space = width;
    const demos_per_row: usize = @intFromFloat(@floor((demo_area_space - demo_pad*2) / (demo_box_size + 2*demo_pad)));
    const demo_row_full_size: f32 = @floatFromInt(demo_pad*2 + demos_per_row * (demo_box_size + 2*demo_pad));

    var demo_i: usize = 0;
    for (0..(1 + demos.len / @max(1, demos_per_row))) |row_i| {
        var demo_row = try dvui.box(
            @src(),
            .horizontal,
            .{
                .id_extra = row_i,
                .gravity_x = 0.5,
                .min_size_content = .{ .w = demo_row_full_size }
            }
        );
        defer demo_row.deinit();

        for (0..demos_per_row) |_| {
            if (demo_i >= demos.len) continue;

            const demo = demos[demo_i];
            defer demo_i += 1;

            if (try demoButton(@src(), demo)) {
                demo_active = demo;
            }
        }
    }
}
