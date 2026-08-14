const std = @import("std");
const dvui = @import("dvui.zig");
const Backend = dvui.backend;

// Regression test: BlurBackdrop nested inside another floating window (as in
// the Blur Backdrop showcase tab, itself hosted in the "DVUI Demo" floating
// window) used to paint the bracketed background *early* (immediately,
// out of order, during build) whenever dirty, then have the enclosing
// window's own background fill - queued earlier but replayed *later* by
// `Window.endRendering` - draw right over it. Result: the checkerboard
// behind the blurred panel vanished on every dirty frame (every tick of a
// slider drag), self-healing only on the next non-dirty settle.
//
// Reads raw pixels straight off the SDL_Renderer target before each
// present, bypassing `dvui.Picture` (which redirects rendering into its own
// offscreen target and so can't see this ordering bug).
test "BlurBackdrop nested in floating window stays visible while dirty every frame" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 900, .h = 900 } });
    defer t.deinit();

    dvui.Examples.show_demo_window = true;
    dvui.Examples.demo_active = .basic_widgets;

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            dvui.Examples.demo(.full);
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try dvui.testing.moveTo("demo_button_blur_backdrop");
    try dvui.testing.click(.left);
    try dvui.testing.settle(frame);

    const canvas_tag = try dvui.testing.tagGet("blur_canvas");
    // A checkerboard cell well outside the blurred panel rect (top-left
    // corner of the canvas), so this only ever sees the enclosing window's
    // background peeking through if the checkerboard fails to draw.
    const sample_x: i32 = @intFromFloat(canvas_tag.rect.x + 4);
    const sample_y: i32 = @intFromFloat(canvas_tag.rect.y + 4);
    const expected_checkerboard: [4]u8 = .{ 124, 92, 255, 255 }; // #7c5cff

    const cw = dvui.currentWindow();
    const back: *Backend = t.backend;

    const slider_tag = try dvui.testing.tagGet("blur_radius_slider");
    _ = try cw.addEventMouseMotion(.{ .pt = slider_tag.rect.center() });
    _ = try cw.addEventMouseButton(.left, .press);

    var buf: [4]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        // drag the mouse a little each tick, forcing radius_px to change
        // every frame (mirrors an unsettled live drag - dirty every tick).
        const dx: f32 = @floatFromInt(i);
        _ = try cw.addEventMouseMotion(.{ .pt = .{ .x = slider_tag.rect.center().x + dx, .y = slider_tag.rect.center().y } });

        if (try frame() == .close) return error.closed;
        _ = try cw.end(.{ .manage_backend = false });

        // Read the real target before presenting - exactly what this frame
        // drew, no target redirection of our own.
        try readPixel(back, sample_x, sample_y, &buf);
        try std.testing.expectEqual(expected_checkerboard, buf);

        back.setCursor(cw.cursorRequested());
        back.textInputRect(cw.textInputRequested());
        back.renderPresent();

        try cw.begin(cw.frame_time_ns + 16 * std.time.ns_per_ms);
    }

    _ = try cw.addEventMouseButton(.left, .release);
    _ = try frame();
    _ = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 16 * std.time.ns_per_ms);
}

fn readPixel(back: *Backend, x: i32, y: i32, out: *[4]u8) !void {
    const c = Backend.c;
    var surface: *c.SDL_Surface = c.SDL_RenderReadPixels(back.renderer, &c.SDL_Rect{ .x = x, .y = y, .w = 1, .h = 1 }) orelse {
        return error.ReadFailed;
    };
    defer c.SDL_DestroySurface(surface);
    if (surface.*.format != c.SDL_PIXELFORMAT_ABGR8888) {
        surface = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_ABGR8888) orelse return error.ReadFailed;
    }
    const px: [*]u8 = @ptrCast(surface.*.pixels);
    out.* = px[0..4].*;
}
