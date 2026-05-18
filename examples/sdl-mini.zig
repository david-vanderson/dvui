const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

const vsync = true;
var scale_val: f32 = 1.0;

var show_dialog_outside_frame: bool = false;

var draw_on_second_win: bool = false;
var spinner_main_win: bool = false;

var backend: SDLBackend = undefined;
var backend2: SDLBackend = undefined;
var win: dvui.Window = undefined;
var win2: dvui.Window = undefined;

var win2_end_micros: ?u32 = null;

pub fn main(init: std.process.Init) !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    SDLBackend.enableSDLLogging();
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    // Init two backends separately
    // The second one as a flag do avoid double SDL initialization
    backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .allocator = init.gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example win1",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    defer backend.deinit();
    backend2 = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .allocator = init.gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example win2",
        .icon = window_icon_png, // can also call setIconFromFileContent()
        .sdl_init = false,
    });
    defer backend2.deinit();

    _ = SDLBackend.c.SDL_SetWindowPosition(backend2.window, 850, 150);
    _ = SDLBackend.c.SDL_EnableScreenSaver();

    // init 2 windows, one of each backend
    win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{
        // you can set the default theme here in the init options
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });
    defer win.deinit();
    win2 = try dvui.Window.init(@src(), init.gpa, backend2.backend(), .{
        // you can set the default theme here in the init options
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });
    defer win2.deinit();

    var interrupted = false;
    var frame_no: u32 = 0;

    main_loop: while (true) {
        std.debug.print("begin frame no {}\n", .{frame_no});
        frame_no += 1;

        // FIXME : need to "reset" this here, otherwise when I don't run the
        // win2.begin() / win2.end() I stay stuck on the last value, which can break
        // the variable framerate (i.e. no wait for event anymore)
        win2_end_micros = null;

        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);

        // FIXME : addAllEvents swallow events for the second windows,
        // so we need to dispatch on windowID here.
        var event: SDLBackend.c.SDL_Event = undefined;
        const poll_got_event = if (SDLBackend.sdl3) true else 1;
        while (SDLBackend.c.SDL_PollEvent(&event) == poll_got_event) {
            if (event.window.windowID == SDLBackend.c.SDL_GetWindowID(backend.window)) {
                _ = try backend.addEvent(&win, event);
            } else if (event.window.windowID == SDLBackend.c.SDL_GetWindowID(backend2.window)) {
                _ = try backend2.addEvent(&win2, event);
            }
        }

        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 0);
        _ = SDLBackend.c.SDL_RenderClear(backend.renderer);
        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend2.renderer, 0, 0, 0, 0);
        _ = SDLBackend.c.SDL_RenderClear(backend2.renderer);

        const keep_running = gui_frame();
        if (!keep_running) break :main_loop;

        const end_micros = try win.end(.{});

        try backend.setCursor(win.cursorRequested());
        try backend2.setCursor(win2.cursorRequested());

        // FIXME : did not care about textInputRequested yet
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();
        try backend2.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        const wait_event_micros2 = win2.waitTime(win2_end_micros);

        interrupted = try backend.waitEventTimeout(@min(wait_event_micros, wait_event_micros2));

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            dvui.dialog(@src(), .{}, .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        }
    }
}

// both dvui and SDL drawing
// return false if user wants to exit the app
fn gui_frame() bool {
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem = "This example shows how to use dvui in a normal application.";
    tl.addText(lorem, .{});
    tl.deinit();

    // FIXME : debug is contained in one window.
    // Opening the debugWindow in win2 works but it should be possible to make it highlight widgets in both windows.
    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        std.debug.print("  Debug Window button clicked\n", .{});
        dvui.toggleDebugWindow();
    }

    if (dvui.button(@src(), "draw on second window", .{}, .{})) {
        draw_on_second_win = !draw_on_second_win;
    }
    if (dvui.button(@src(), "show spinner here", .{}, .{})) {
        spinner_main_win = !spinner_main_win;
    }
    if (spinner_main_win) {
        dvui.spinner(@src(), .{});
    }

    if (draw_on_second_win) {
        win2.begin(win.frame_time_ns) catch unreachable;
        defer win2_end_micros = win2.end(.{}) catch unreachable;

        var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
        const lorem2 = "This example shows some stuff in second window.";
        tl2.addText(lorem2, .{});
        tl2.deinit();

        if (dvui.button(@src(), "button test", .{}, .{})) {
            std.debug.print("clicked on button in second window\n", .{});
        }
        var float = dvui.floatingWindow(@src(), .{}, .{ .min_size_content = .{ .h = 350 } });
        dvui.label(@src(), "I'm floating", .{}, .{});
        if (dvui.button(@src(), "button test in floating", .{}, .{})) {
            std.debug.print("clicked on test button in floating\n", .{});
        }
        if (dvui.button(@src(), "stop showing stuff here", .{}, .{})) {
            draw_on_second_win = false;
        }
        if (dvui.expander(@src(), "Spinner", .{}, .{})) {
            dvui.spinner(@src(), .{});
        }
        float.deinit();
    }

    if (dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
        show_dialog_outside_frame = true;
    }

    // check for quitting
    for (dvui.events()) |*e| {
        // assume we only have a single window
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
    }

    return true;
}
