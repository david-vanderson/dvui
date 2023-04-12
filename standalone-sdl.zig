const std = @import("std");
const gui = @import("gui");
const Backend = @import("SDLBackend");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;

/// This example shows how to use the gui for a normal application:
/// - gui renders the whole application
/// - render frames only when needed
pub fn main() !void {
    // init SDL backend (creates OS window)
    var backend = try Backend.init(.{
        .width = 500,
        .height = 600,
        .vsync = vsync,
        .title = "GUI Standalone Example",
    });
    defer backend.deinit();

    // init gui Window (maps onto a single OS window)
    var win = try gui.Window.init(@src(), 0, gpa, backend.guiBackend());
    defer win.deinit();

    main_loop: while (true) {
        var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena_allocator.deinit();
        var arena = arena_allocator.allocator();

        // beginWait coordinates with waitTime below to run frames only when needed
        var nstime = win.beginWait(backend.hasEvent());

        // marks the beginning of a frame for gui, can call gui functions after this
        try win.begin(arena, nstime);

        // send all SDL events to gui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        try gui_frame();

        // marks end of gui frame, don't call gui functions after this
        // - sends all gui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end();

        // cursor management
        backend.setCursor(win.cursorRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);
    }
}

fn gui_frame() !void {
    var scroll = try gui.scrollArea(@src(), 0, .{ .expand = .both, .color_style = .window });
    defer scroll.deinit();

    var tl = try gui.textLayout(@src(), 0, .{ .expand = .both, .font_style = .title_4 });
    const lorem = "This example shows how to use gui in a normal application.";
    try tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = try gui.textLayout(@src(), 0, .{ .expand = .both });
    try tl2.addText("The gui is painting the entire window, and can also show floating windows and dialogs.", .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    try tl2.addText("\n\n", .{});
    if (vsync) {
        try tl2.addText("Framerate is capped by vsync.", .{});
    } else {
        try tl2.addText("Framerate is uncapped.", .{});
    }
    try tl2.addText("\n\n", .{});
    try tl2.addText("Cursor is always being set by gui.", .{});
    tl2.deinit();

    if (gui.examples.show_demo_window) {
        if (try gui.button(@src(), 0, "Hide Demo Window", .{})) {
            gui.examples.show_demo_window = false;
        }
    } else {
        if (try gui.button(@src(), 0, "Show Demo Window", .{})) {
            gui.examples.show_demo_window = true;
        }
    }

    // look at demo() for examples of gui widgets, shows in a floating window
    try gui.examples.demo();
}
