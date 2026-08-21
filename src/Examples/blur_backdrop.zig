//! ![image](Examples-blurBackdrop.png)

/// Showcase for `dvui.BlurBackdrop`: a cached, dual-Kawase-blurred backdrop
/// standing in for CSS `backdrop-filter: blur(radius_px)`
/// Draws a sharp-edged checkerboard behind a floating,
/// blurred panel, with a slider driving `radius_px` directly - the sharper
/// the checkerboard going in, the more obvious it is whether blur did
/// anything.
pub fn blurBackdrop() void {
    const stage = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 300, .h = 250 } });
    defer stage.deinit();

    const backdrop = dvui.BlurBackdrop.get(@src());

    _ = dvui.sliderEntry(@src(), "radius: {d:0.1}", .{ .value = &backdrop.radius_px, .min = 2, .max = 20 }, .{ .tag = "blur_radius_slider" });

    // Own box for the checkerboard/panel, below the slider - the
    // checkerboard positions its cells with absolute `.rect` coordinates,
    // which would otherwise land on top of (and hide) the slider if both
    // shared the same parent box.
    const canvas = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 300, .h = 220 }, .tag = "blur_canvas" });
    defer canvas.deinit();

    // Local (canvas-relative) coordinates for the checkerboard and the panel
    // that will show the blurred version of it. captureBegin/FloatingWidget
    // both want window-absolute natural coordinates, so convert once here.
    const canvas_rs = canvas.data().contentRectScale();
    const local_panel: dvui.Rect = .{ .x = 40, .y = 40, .w = 220, .h = 140 };
    const panel_abs = dvui.windowRectScale().rectFromPhysical(canvas_rs.rectToPhysical(local_panel));

    // Witness only needs `radius_px` - rect is already covered by
    // captureBegin's own hash, and nothing else here changes frame to frame.
    backdrop.init(panel_abs, .{backdrop.radius_px});
    defer backdrop.deinit();
    checkerboard();

    {
        var fw: dvui.FloatingWidget = undefined;
        fw.init(@src(), .{}, .{ .rect = panel_abs });
        defer fw.deinit();
        backdrop.draw();
        dvui.label(@src(), "backdrop-filter: blur()", .{}, .{ .color_text = .white, .gravity_x = 0.5, .gravity_y = 0.5 });
    }
}

/// Small, sharp-edged squares as children of `stage` (the current parent
/// when this is called), positioned with local `.rect` coordinates.
fn checkerboard() void {
    const swatches = [_]dvui.Color{
        .fromHex("#7c5cff"),
        .fromHex("#5ce1e6"),
        .fromHex("#ff9f43"),
    };
    const cell: f32 = 20;
    var y: f32 = 0;
    var row: usize = 0;
    while (y + cell <= 220) : (y += cell) {
        var x: f32 = 0;
        var col: usize = 0;
        while (x + cell <= 300) : (x += cell) {
            const on = (row + col) % 2 == 0;
            var b = dvui.box(@src(), .{}, .{
                .id_extra = row * 1000 + col,
                .rect = .{ .x = x, .y = y, .w = cell, .h = cell },
                .background = true,
                .color_fill = if (on) swatches[col % swatches.len] else .black,
            });
            b.deinit();
            col += 1;
        }
        row += 1;
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG blurBackdrop" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 340, .h = 260 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            blurBackdrop();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-blurBackdrop.png");
}

const dvui = @import("../dvui.zig");
