const std = @import("std");
const gui = @import("gui");
const Backend = @import("SDLBackend");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;

var show_dialog_outside_frame: bool = false;

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
        const end_micros = try win.end(.{});

        // cursor management
        backend.setCursor(win.cursorRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            try gui.dialog(@src(), .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        }
    }
}

fn gui_frame() !void {
    {
        var m = try gui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try gui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try gui.popup(@src(), gui.Rect.fromPoint(gui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();

            if (try gui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                gui.menuGet().?.close();
            }
        }

        if (try gui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try gui.popup(@src(), gui.Rect.fromPoint(gui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();
            _ = try gui.menuItemLabel(@src(), "Cut", .{}, .{});
            _ = try gui.menuItemLabel(@src(), "Copy", .{}, .{});
            _ = try gui.menuItemLabel(@src(), "Paste", .{}, .{});
        }
    }

    var scroll = try gui.scrollArea(@src(), .{}, .{ .expand = .both, .color_style = .window });
    defer scroll.deinit();

    var tl = try gui.textLayout(@src(), .{}, .{ .expand = .both, .font_style = .title_4 });
    const lorem = "This example shows how to use gui in a normal application.";
    try tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = try gui.textLayout(@src(), .{}, .{ .expand = .both });
    try tl2.addText(
        \\The gui
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- example menu at the top of the window
        \\- rest of the window is a scroll area
    , .{});
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
        if (try gui.button(@src(), "Hide Demo Window", .{})) {
            gui.examples.show_demo_window = false;
        }
    } else {
        if (try gui.button(@src(), "Show Demo Window", .{})) {
            gui.examples.show_demo_window = true;
        }
    }

    if (try gui.button(@src(), "Show Dialog From\nOutside Frame", .{})) {
        show_dialog_outside_frame = true;
    }

    // look at demo() for examples of gui widgets, shows in a floating window
    try gui.examples.demo();
}
