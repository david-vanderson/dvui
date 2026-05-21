const std = @import("std");
const print = std.debug.print;
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

var main_backend: SDLBackend = undefined;
var main_win: dvui.Window = undefined;

var user_gpa: std.mem.Allocator = undefined;

pub fn main(init: std.process.Init) !void {
    user_gpa = init.gpa;

    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    SDLBackend.enableSDLLogging();
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    main_backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .allocator = init.gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example win1",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    defer main_backend.deinit();

    _ = SDLBackend.c.SDL_EnableScreenSaver();

    main_win = try dvui.Window.init(@src(), init.gpa, main_backend.backend(), .{
        // you can set the default theme here in the init options
        .theme = switch (main_backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });
    defer main_win.deinit();

    var interrupted = false;
    var frame_no: u32 = 0;

    main_loop: while (true) {
        std.debug.print("begin frame no {}\n", .{frame_no});
        frame_no += 1;

        const nstime = main_win.beginWait(interrupted);

        try main_win.begin(nstime, .{});

        // FIXME : addAllEvents swallow events for the second windows,
        // so we need to dispatch on windowID here.
        var event: SDLBackend.c.SDL_Event = undefined;
        const poll_got_event = if (SDLBackend.sdl3) true else 1;
        while (SDLBackend.c.SDL_PollEvent(&event) == poll_got_event) {
            if (event.window.windowID == SDLBackend.c.SDL_GetWindowID(main_backend.window)) {
                _ = try main_backend.addEvent(&main_win, event);
            }
            var it = main_win.child_os_wins.iterator();
            // Use next_peek because the fact we had events since last frame doesn't mean
            // the child Os Window will still be used in the upcoming frame, we don't know that yet.
            while (it.next_peek()) |alive_win| {
                const b = alive_win.value.backend;
                if (event.window.windowID == SDLBackend.c.SDL_GetWindowID(b.window)) {
                    _ = try b.addEvent(alive_win.value.dvui_win, event);
                }
            }
        }

        const keep_running = gui_frame();
        if (!keep_running) break :main_loop;

        const end_micros = try main_win.end(.{});

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = main_win.waitTime(end_micros);

        interrupted = try main_backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            dvui.dialog(@src(), .{}, .{ .window = &main_win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
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

    const draw_second_win_btn_text = if (draw_on_second_win) "stop drawing on second win" else "draw_on_second_win";
    if (dvui.button(@src(), draw_second_win_btn_text, .{}, .{})) {
        draw_on_second_win = !draw_on_second_win;
    }
    if (dvui.button(@src(), "show spinner here", .{}, .{})) {
        spinner_main_win = !spinner_main_win;
    }
    if (spinner_main_win) {
        dvui.spinner(@src(), .{});
    }
    if (dvui.button(@src(), "simple test", .{}, .{})) {
        print("clicked on simple test button\n", .{});
    }

    if (draw_on_second_win) {
        const win_maybe = dvui.currentWindow().child_os_wins.getOrPut(main_win.gpa, 1) catch unreachable;
        const os_win: *dvui.Window.ChildOsWindow = if (win_maybe.found_existing)
            win_maybe.value_ptr
        else blk: {
            // Create a new window/backend with `gpa`
            const new_backend = main_win.gpa.create(SDLBackend) catch unreachable;
            new_backend.* = SDLBackend.initWindow(.{
                .io = dvui.io,
                // .environ_map = init.environ_map,
                .allocator = main_win.gpa,
                .size = .{ .w = 800.0, .h = 600.0 },
                .min_size = .{ .w = 250.0, .h = 350.0 },
                .vsync = vsync,
                .title = "DVUI SDL Standalone Example win2",
                .icon = window_icon_png, // can also call setIconFromFileContent()
                .sdl_init = false,
            }) catch unreachable;
            _ = SDLBackend.c.SDL_SetWindowPosition(new_backend.window, 850, 150);

            const new_dvui_win = main_win.gpa.create(dvui.Window) catch unreachable;
            new_dvui_win.* = dvui.Window.init(@src(), main_win.gpa, new_backend.backend(), .{
                // you can set the default theme here in the init options
                .theme = switch (new_backend.preferredColorScheme() orelse .light) {
                    .light => dvui.Theme.builtin.adwaita_light,
                    .dark => dvui.Theme.builtin.adwaita_dark,
                },
            }) catch unreachable;

            win_maybe.value_ptr.* = .{ .backend = new_backend, .dvui_win = new_dvui_win };
            break :blk win_maybe.value_ptr;
        };
        os_win.dvui_win.begin(main_win.frame_time_ns, .{}) catch unreachable;
        defer os_win.end_micros = os_win.dvui_win.end(.{}) catch unreachable;

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
        if (dvui.expander(@src(), "Show me a Spinner !!", .{ .default_expanded = true }, .{})) {
            dvui.spinner(@src(), .{});
        }
        float.deinit();
        dvui.label(@src(), "One last thing ;-)", .{}, .{});
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
