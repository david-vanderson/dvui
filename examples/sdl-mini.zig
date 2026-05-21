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

var draw_on_other_window: [6]bool = @splat(false);
var spinner_main_win: bool = false;

var dd_results: struct {
    return_value: bool,
    choice: usize,
} = .{ .return_value = false, .choice = draw_on_other_window.len };

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

        try main_backend.addAllEvents(&main_win);

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

    for (0..draw_on_other_window.len) |i| {
        const draw_other_win_text = if (draw_on_other_window[i])
            std.fmt.allocPrint(dvui.currentWindow().arena(), "stop drawing on child win no {}", .{i}) catch @panic("OOM")
        else
            "Show me another win";
        if (dvui.button(@src(), draw_other_win_text, .{}, .{ .id_extra = i })) {
            draw_on_other_window[i] = !draw_on_other_window[i];
        }
        if (draw_on_other_window[i]) {
            const win_title = std.fmt.allocPrintSentinel(dvui.currentWindow().arena(), "Nice Window no {}", .{i}, 0) catch @panic("OOM");
            // FIXME : this breaks DVUI expectation, because if you forget to pass
            // the `id_extra`, you just get back the same window again, and draw
            // on top, clear screen and render, so you don't necessarly notice.
            // But I'm not sure how to deal with that.
            // Should `dvui.Window.ChildOsWindow` have a "rendered" field so we can warn the user if it has multiple draw cycle in one main_loop ?
            // Or maybe doing the rendering in `Window.end()` is not the best strategy after all ?
            const os_win = dvui.osWindow(@src(), .{ .title = win_title }, .{ .id_extra = i });
            defer os_win.deinit();

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
                draw_on_other_window[i] = false;
            }
            if (dvui.expander(@src(), "Show me a Spinner !!", .{ .default_expanded = true }, .{})) {
                dvui.spinner(@src(), .{});
            }
            float.deinit();
            dvui.label(@src(), "One last thing ;-)", .{}, .{});

            if (dd_results.choice == i) {
                dvui.Examples.demo(.lite);
            }
        }
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

    if (dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
        show_dialog_outside_frame = true;
    }

    const entries: [draw_on_other_window.len + 1][]const u8 = comptime blk: {
        var ens: [draw_on_other_window.len + 1][]const u8 = undefined;
        for (0..draw_on_other_window.len) |i| {
            ens[i] = std.fmt.comptimePrint("Show Demo on win {}", .{i});
        }
        ens[draw_on_other_window.len] = "Don't show Demo";
        break :blk ens;
    };
    if (dvui.dropdown(@src(), &entries, .{ .choice = &dd_results.choice }, .{}, .{})) {
        if (dd_results.choice == draw_on_other_window.len) {
            dvui.Examples.show_demo_window = false;
        } else {
            if (draw_on_other_window[dd_results.choice]) {
                dvui.Examples.show_demo_window = true;
            } else {
                dvui.Examples.show_demo_window = false;
                dvui.toast(@src(), .{ .message = "I can't ! This window is currently not displayed" });
                dd_results.choice = draw_on_other_window.len;
            }
        }
    } else {
        if (!dvui.Examples.show_demo_window) dd_results.choice = draw_on_other_window.len;
        if (dd_results.choice != draw_on_other_window.len) {
            if (!draw_on_other_window[dd_results.choice]) {
                dvui.toast(@src(), .{ .message = "Sad, you stop showing the os window with the demo" });
                dd_results.choice = draw_on_other_window.len;
            }
        }
    }

    // check for quitting
    for (dvui.events()) |*e| {
        // assume we only have a single window
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
    }

    return true;
}
