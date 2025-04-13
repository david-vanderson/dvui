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

// Runs before the first frame, after backend and dvui.Window.init()
pub fn AppInit(win: *dvui.Window) void {
    _ = win;
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

pub fn frame() !dvui.App.Result {
    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    defer scroll.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This is a dvui.App example that can compile on multiple backends.";
    try tl.addText(lorem, .{});
    try tl.addText("\n\n", .{});
    try tl.format("Current backend {s} : {s}", .{ @tagName(dvui.backend.kind), dvui.backend.description() }, .{});
    tl.deinit();

    var tl2 = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    try tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- rest of the window is a scroll area
    , .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Framerate is capped by vsync.", .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Cursor is always being set by dvui.", .{});
    try tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        try tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        try tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (try dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    //if (try dvui.button(@src(), "Panic", .{}, .{})) {
    //std.debug.panic("This is a panic message after {d}s", .{@divTrunc(dvui.currentWindow().frame_time_ns, std.time.ns_per_s)});
    //}
    if (try dvui.button(@src(), if (dvui.wasm) "Stop" else "Close", .{}, .{})) {
        return .close;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();

    return .ok;
}

test "tab order" {
    var t = try dvui.testing.init(
        std.testing.allocator,
        .{ .w = 600, .h = 400 },
    );
    defer t.deinit();

    try dvui.testing.settle(frame);

    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(frame);

    try dvui.testing.expectFocused("show-demo-btn");

    //try dvui.testing.snapshot(@src());

    //try t.snapshot(@src());
}
