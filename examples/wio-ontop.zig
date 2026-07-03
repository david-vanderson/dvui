const std = @import("std");
const dvui = @import("dvui");
const WioBackend = @import("wio-backend");
const wio = WioBackend.wio;

const vsync = false;
const show_demo = false;

/// This example shows how to use dvui for floating windows on top of an existing application
/// - dvui renders only floating windows
/// - framerate is managed by application, not dvui
pub fn main(init: std.process.Init) !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    dvui.Examples.show_demo_window = show_demo;

    try wio.init(.{ .allocator = init.gpa, .io = init.io, .eventFn = wio.EventQueue.eventFn });
    defer wio.deinit();

    var events: wio.EventQueue = .empty;
    defer events.deinit();

    const gl_options: wio.GlOptions = .{
        .major_version = 3,
        .minor_version = 2,
        .profile = .core,
    };

    var window: wio.Window = try .create(.{
        .event_fn_data = &events,
        .title = "DVUI wio Ontop Example",
        .size = .{ .width = 800, .height = 600 },
        .scale = 1,
        .gl_options = gl_options,
    });
    defer window.destroy();

    var context = try window.glCreateContext(.{ .options = gl_options });
    defer context.destroy();
    window.glMakeContextCurrent(context);
    if (vsync) window.glSwapInterval(1);

    // init the dvui OpenGL renderer
    var renderer = try dvui.render_backend.init(init.gpa, wio.glGetProcAddress, "150");
    defer renderer.deinit();

    // create SDL backend using existing window and renderer, app still owns the window/renderer
    var backend = try WioBackend.init(.{ .io = init.io, .window = window });
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(&renderer), .{});
    defer win.deinit();

    main_loop: while (true) {
        wio.update();

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(backend.nanoTime());

        // send events to dvui if they belong to floating windows
        while (events.pop()) |event| {
            switch (event) {
                .close => break :main_loop,
                else => {},
            }

            if (try backend.addEvent(&win, event)) {
                // dvui handles this event as it's for a floating window
            } else {
                // dvui doesn't handle this event, send it to the underlying application
            }
        }

        // clear the window
        renderer.clear();

        dvuiStuff();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        _ = try win.end(.{ .manage_backend = false });

        // cursor management
        if (win.cursorRequestedFloating()) |cursor| {
            // cursor is over floating window, dvui sets it
            backend.setCursor(cursor);
        } else {
            // cursor should be handled by application
            backend.setCursor(.bad);
        }
        backend.textInputRect(win.textInputRequested());

        // render frame to OS
        window.glSwapBuffers();
    }
}

fn dvuiStuff() void {
    var float = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .w = 400, .h = 400 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("Floating Window", "", null));

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem = "This example shows how to use dvui for floating windows on top of an existing application.";
    tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText("The dvui is painting only floating windows and dialogs.\n\n", .{});
    tl2.addText("Framerate is managed by the application", .{});
    if (vsync) {
        tl2.addText(" (capped at vsync)\n", .{});
    } else {
        tl2.addText(" (uncapped - no vsync)\n", .{});
    }
    tl2.addText("\n", .{});
    tl2.addText("Cursor is only being set by dvui for floating windows.\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    // only shows the demo if dvui.Examples.show_demo_window is true
    // .full -> .lite or comment out to speed up compile times
    dvui.Examples.demo(.full);
}
