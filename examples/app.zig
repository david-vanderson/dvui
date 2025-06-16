const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const window_icon_png = @embedFile("zig-favicon.png");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .title = "DVUI App Example",
        .icon = window_icon_png,
    } },
    .frameFn = AppFrame,
    .initFn = AppInit,
    .deinitFn = AppDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var orig_content_scale: f32 = 1.0;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;
    //try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

pub fn frame() !dvui.App.Result {
    var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
    scaler.deinit();

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .fill_window });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This is a dvui.App example that can compile on multiple backends.";
    tl.addText(lorem, .{});
    tl.addText("\n\n", .{});
    tl.format("Current backend: {s}", .{@tagName(dvui.backend.kind)}, .{});
    if (dvui.backend.kind == .web) {
        tl.format(" : {s}", .{if (dvui.backend.wasm.wasm_about_webgl2() == 1) "webgl2" else "webgl (no mipmaps)"}, .{});
    }
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- rest of the window is a scroll area
    , .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is capped by vsync.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.", .{});
    tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        dvui.label(@src(), "Pinch Zoom or Scale", .{}, .{});
        if (dvui.buttonIcon(@src(), "plus", dvui.entypo.plus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale *= 1.1;
        }

        if (dvui.buttonIcon(@src(), "minus", dvui.entypo.minus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale /= 1.1;
        }

        if (dvui.currentWindow().content_scale != orig_content_scale) {
            if (dvui.button(@src(), "Reset Scale", .{}, .{})) {
                dvui.currentWindow().content_scale = orig_content_scale;
            }
        }
    }

    //if (dvui.button(@src(), "Panic", .{}, .{})) {
    //std.debug.panic("This is a panic message after {d}s", .{@divTrunc(dvui.currentWindow().frame_time_ns, std.time.ns_per_s)});
    //}
    if (dvui.backend.kind != .web) {
        if (dvui.button(@src(), "Close", .{}, .{})) {
            return .close;
        }
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    dvui.Examples.demo();

    return .ok;
}

test "tab order" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(frame);

    try dvui.testing.expectNotFocused("show-demo-btn");

    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(frame);

    try dvui.testing.expectFocused("show-demo-btn");
}

test "open example window" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(frame);

    // FIXME: The global show_demo_window variable makes tests order dependent
    dvui.Examples.show_demo_window = false;

    try std.testing.expect(dvui.tagGet(dvui.Examples.demo_window_tag) == null);

    try dvui.testing.moveTo("show-demo-btn");
    try dvui.testing.click(.left);
    try dvui.testing.settle(frame);

    try dvui.testing.expectVisible(dvui.Examples.demo_window_tag);
}

test "snapshot" {
    // snapshot tests are unstable
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    // FIXME: The global show_demo_window variable makes tests order dependent
    dvui.Examples.show_demo_window = false;

    try dvui.testing.settle(frame);

    // Try swapping the names of ./snapshots/app.zig-test.snapshot-X.png
    try t.snapshot(@src(), frame);

    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(frame);

    try t.snapshot(@src(), frame);
}
