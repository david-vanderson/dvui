const std = @import("std");
const dvui = @import("dvui");
const WioBackend = @import("wio-backend");
const wio = WioBackend.wio;

comptime {
    std.debug.assert(@hasDecl(WioBackend, "wio"));
}

const vsync = true;
const show_demo = false;
var scale_val: f32 = 1.0;

var g_win: ?*dvui.Window = null;

/// This example shows how to use dvui with the wio backend for a normal
/// application, driving the wio main loop manually (rather than via dvui.App):
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    dvui.Examples.show_demo_window = show_demo;

    try wio.init(gpa, io, wio.EventQueue.eventFn, .{});
    defer wio.deinit();

    var events: wio.EventQueue = .empty;
    defer events.deinit();

    // dvui's wio backend uses the OpenGL render backend.
    const gl_options: wio.GlOptions = .{
        .major_version = 3,
        .minor_version = 2,
        .profile = .core,
    };

    // wio creates and owns the OS window.
    var window = try wio.Window.create(.{
        .event_fn_data = &events,
        .title = "DVUI wio Standalone Example",
        .size = .{ .width = 800, .height = 600 },
        .scale = 1,
        .gl_options = gl_options,
    });
    defer window.destroy();

    var context = try window.glCreateContext(.{ .options = gl_options });
    window.glMakeContextCurrent(context);
    defer context.destroy();

    if (vsync) window.glSwapInterval(1);

    // init the dvui OpenGL renderer
    var renderer = try dvui.render_backend.init(gpa, wio.glGetProcAddress, "150");
    defer renderer.deinit();

    // init the wio backend (wraps the wio window for dvui)
    var backend = try WioBackend.init(.{ .io = io, .window = window });
    defer backend.deinit();

    var window_open = true;
    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(&renderer), .{
        .open_flag = &window_open,
    });
    defer win.deinit();
    g_win = &win;

    main_loop: while (window_open) {
        // pump the OS event queue, then forward all wio events to dvui
        wio.update();
        while (events.pop()) |event| {
            _ = try backend.addEvent(&win, event);
        }

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(true);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        const keep_running = gui_frame();
        if (!keep_running) break :main_loop;

        // marks end of dvui frame, don't call dvui functions after this
        // by default, manages backend (cursor handling, rendering) as well.
        const end_micros = try win.end(.{});

        // wio's renderPresent is a no-op; present the frame ourselves
        window.glSwapBuffers();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        backend.waitEventTimeout(wait_event_micros);
    }
}

// return false if user wants to exit the app
fn gui_frame() bool {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal, .name = "main" });
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                m.close();
            }

            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                return false;
            }
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    tl.addText("This example shows how to use dvui with the wio backend in a normal application.", .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- example menu at the top of the window
        \\- rest of the window is a scroll area
        \\
        \\
    , .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.\n\n", .{});
    if (vsync) {
        tl2.addText("Framerate is capped by vsync.\n", .{});
    } else {
        tl2.addText("Framerate is uncapped.\n", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    {
        var scaler = dvui.scale(@src(), .{ .scale = &scale_val }, .{ .expand = .horizontal });
        defer scaler.deinit();

        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Zoom In", .{}, .{})) {
            scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;
        }

        if (dvui.button(@src(), "Zoom Out", .{}, .{})) {
            scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;
        }
    }

    // only shows the demo if dvui.Examples.show_demo_window is true
    dvui.Examples.demo(.full);

    return true;
}
