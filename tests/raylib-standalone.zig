const std = @import("std");
const dvui = @import("dvui");
const RaylibBackend = @import("RaylibBackend");

const window_icon_png = @embedFile("src/zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;

var show_dialog_outside_frame: bool = false;

pub const c = RaylibBackend.c;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
pub fn main() !void {
    defer _ = gpa_instance.deinit();

    // init Raylib backend (creates OS window)
    c.InitWindow(800, 450, "raylib [core] example - basic window");
    var backend = try RaylibBackend.init(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 450.0 },
        .vsync = vsync,
        .title = "DVUI Raylib Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), 0, gpa, backend.backend());
    defer win.deinit();

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        //const nstime = win.beginWait(backend.hasEvent());

        // marks the beginning of a frame for dvui, can call dvui functions after this
        //try win.begin(nstime);
        try win.begin(std.time.nanoTimestamp());

        // send all SDL events to dvui for processing
        const quit = c.WindowShouldClose();
        //const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        backend.clear();

        //c.DrawText("Congrats! You created your first window!", 190, 200, 20, c.LIGHTGRAY);
        try dvui_frame();

        //_ = try dvui.button(@src(), "Test Button", .{}, .{});
        //try dvui.pathAddRect(.{ .x = 0.2, .y = 0.2, .w = 0.1, .h = 0.1 }, .{});
        //try dvui.pathAddRect(.{ .x = 100, .y = 100, .w = 200, .h = 100 }, .{});
        //try dvui.pathFillConvex(.{ .r = 20, .g = 220, .b = 150 });

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});
        _ = end_micros;

        // cursor management
        //backend.setCursor(win.cursorRequested());

        // render frame to OS
        //backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        //const wait_event_micros = win.waitTime(end_micros, null);
        //backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        //if (show_dialog_outside_frame) {
        //show_dialog_outside_frame = false;
        //try dvui.dialog(@src(), .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        //}
    }
}

fn dvui_frame() !void {
    {
        var m = try dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), dvui.Rect.fromPoint(dvui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();

            if (try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                dvui.menuGet().?.close();
            }
        }

        if (try dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), dvui.Rect.fromPoint(dvui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();
            _ = try dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    defer scroll.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui in a normal application.";
    try tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    try tl2.addText(
        \\DVUI
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
    try tl2.addText("Cursor is always being set by dvui.", .{});
    try tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        try tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        try tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    if (dvui.Examples.show_demo_window) {
        if (try dvui.button(@src(), "Hide Demo Window", .{}, .{})) {
            dvui.Examples.show_demo_window = false;
        }
    } else {
        if (try dvui.button(@src(), "Show Demo Window", .{}, .{})) {
            dvui.Examples.show_demo_window = true;
        }
    }

    if (try dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
        show_dialog_outside_frame = true;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}
