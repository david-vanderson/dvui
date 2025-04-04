const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;

const window_icon_png = @embedFile("zig-favicon.png");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .initFn = AppInit,
    .frameFn = AppFrame,
    .deinitFn = AppDeinit,
};
pub const main = dvui.backend.main;
pub const std_options: std.Options = .{
    .logFn = dvui.backend.logFn,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

// This is run before dvui does anything else.
pub fn AppInit() void {}

// Run as app is shutting down, need to know if cleanly?
pub fn AppDeinit() void {}

// Run on each frame, return micros to sleep, or something for the app to quit
pub fn AppFrame() void {
    frame() catch return;
}

pub fn frame() !void {
    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    defer scroll.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This is a dvui.App example that can compile on multiple backends.";
    try tl.addText(lorem, .{});
    try tl.addText("\n\n", .{});
    try tl.format("Current backend: {s}", .{"unknown"}, .{});
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
    if (try dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}
