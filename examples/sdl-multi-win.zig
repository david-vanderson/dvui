/// This is a dedicated example of how to use `dvui.osWindow` to spawn dedicated os windows
/// This is early stage feature, and is working with SDL3 only for now.
///
/// Long term plan is to add support for other backend, and maybe have a fallback to `dvui.floatingWindow` for backends that do not support multiple OS Windows.
const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
    // Not tested with sdl2 yet.
    std.debug.assert(dvui.backend.kind == .sdl3);
}

const window_icon_png = @embedFile("zig-favicon.png");

var show_dialog_outside_frame: bool = false;
var os_win_active: [6]bool = @splat(false);
var spinner_main_win: bool = false;

const DemoChoice = struct {
    // lower values index os_win_active
    const on_main: usize = os_win_active.len;
    const no_demo: usize = os_win_active.len + 1;
};
var dd_demo_res: struct {
    return_value: bool,
    choice: usize,
} = .{ .return_value = false, .choice = DemoChoice.no_demo };

pub fn main(init: std.process.Init) !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    SDLBackend.enableSDLLogging();
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = true,
        .title = "DVUI SDL Multi Win Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    defer backend.deinit();

    _ = SDLBackend.c.SDL_EnableScreenSaver();

    var window_open = true;
    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{
        // you can set the default theme here in the init options
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
        .open_flag = &window_open,
    });
    defer win.deinit();

    var interrupted = false;
    var frame_no: u32 = 0;

    main_loop: while (window_open) {
        std.debug.print("begin frame no {}\n", .{frame_no});
        frame_no += 1;

        const nstime = win.beginWait(interrupted);

        try win.begin(nstime);

        try backend.addAllEvents(&win);

        const keep_running = gui_frame();
        if (!keep_running) break :main_loop;

        const end_micros = try win.end(.{});

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        // Example of how to show a dialog from another thread (outside of win.begin/win.end)
        // TODO : If I want to show this guy on another os window, I need a way to reference said window reliably
        // but it can disappear beneath me any time, maybe `dvui.Window.ChildOsWindow` need an `active` field of sorts ?
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            dvui.dialog(@src(), .{}, .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
        }
    }
}

// both dvui and SDL drawing
// return false if user wants to exit the app
fn gui_frame() bool {
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title), .margin = .all(15) });
    const lorem = "This example shows how to use dvui with multiple OS windows.";
    tl.addText(lorem, .{});
    tl.deinit();

    var main_box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = .all(10) });
    defer main_box.deinit();

    { // Column : Some test buttons
        var b = dvui.box(@src(), .{}, .{ .margin = .all(10) });
        defer b.deinit();
        if (dvui.button(@src(), "show spinner here", .{}, .{})) {
            spinner_main_win = !spinner_main_win;
        }
        if (spinner_main_win) {
            dvui.spinner(@src(), .{});
        }
        if (dvui.button(@src(), "simple test", .{}, .{})) {
            print("clicked on simple test button\n", .{});
        }

        // FIXME : debug floating currently always shown on the "primary" window.
        // Either allow arbitrary window, or give the option to pop-out the debug window itself
        // as a osWindow
        if (dvui.button(@src(), "Debug Window", .{}, .{})) {
            std.debug.print("  Debug Window button clicked\n", .{});
            dvui.toggleDebugWindow();
        }

        _ = dvui.spacer(@src(), .{ .min_size_content = .{ .h = 50 } });

        // Yes, this is a bit of a silly exemple, but allow to test some edge cases,
        // and allow to demonstrate the recursive event delivery
        nestedOsWin(0);
    }

    { // Column : Spawn OS windows
        var b = dvui.box(@src(), .{}, .{ .margin = .all(10) });
        defer b.deinit();

        for (0..os_win_active.len) |i| {
            const draw_other_win_text = if (os_win_active[i])
                std.fmt.allocPrint(dvui.currentWindow().arena(), "stop drawing on child win no {}", .{i}) catch @panic("OOM")
            else
                "Show me another win";
            if (dvui.button(@src(), draw_other_win_text, .{}, .{ .id_extra = i })) {
                os_win_active[i] = !os_win_active[i];
            }
            if (os_win_active[i]) {
                const win_title = std.fmt.allocPrintSentinel(dvui.currentWindow().arena(), "Nice Window no {}", .{i}, 0) catch @panic("OOM");

                const os_win = dvui.osWindow(@src(), .{ .title = win_title }, .{ .id_extra = i, .open_flag = &os_win_active[i] });
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
                    os_win_active[i] = false;
                }
                if (dvui.expander(@src(), "Show me a Spinner !!", .{ .default_expanded = false }, .{})) {
                    dvui.spinner(@src(), .{});
                }
                float.deinit();
                dvui.label(@src(), "One last thing ;-)", .{}, .{});

                if (dd_demo_res.choice == i) {
                    dvui.Examples.demo(.lite);
                }
            }
        }
    }
    const entries: [os_win_active.len + 2][]const u8 = comptime blk: {
        var ens: [os_win_active.len + 2][]const u8 = undefined;
        for (0..os_win_active.len) |i| {
            ens[i] = std.fmt.comptimePrint("Show Demo on win {}", .{i});
        }
        ens[os_win_active.len] = "Show Demo on main window";
        ens[os_win_active.len + 1] = "Don't show Demo";
        break :blk ens;
    };

    { // Column : Show stuff on said windows
        var b = dvui.box(@src(), .{}, .{ .margin = .all(10) });
        defer b.deinit();

        if (dvui.dropdown(@src(), &entries, .{ .choice = &dd_demo_res.choice }, .{}, .{})) {
            if (dd_demo_res.choice == DemoChoice.no_demo) {
                dvui.Examples.show_demo_window = false;
            } else {
                if (dd_demo_res.choice == DemoChoice.on_main) {
                    dvui.Examples.show_demo_window = true;
                } else if (os_win_active[dd_demo_res.choice]) {
                    dvui.Examples.show_demo_window = true;
                } else {
                    dvui.Examples.show_demo_window = false;
                    dvui.toast(@src(), .{ .message = "I can't ! This window is currently not displayed" });
                    dd_demo_res.choice = DemoChoice.no_demo;
                }
            }
        } else {
            // When we close the window or the demo, update back the dropdown.
            if (!dvui.Examples.show_demo_window) dd_demo_res.choice = DemoChoice.no_demo;
            if (dd_demo_res.choice != DemoChoice.no_demo and dd_demo_res.choice != DemoChoice.on_main) {
                if (!os_win_active[dd_demo_res.choice]) {
                    dvui.toast(@src(), .{ .message = "Sad, you stop showing the os window with the demo" });
                    dd_demo_res.choice = DemoChoice.no_demo;
                }
            }
        }

        if (dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
            show_dialog_outside_frame = true;
        }
    }

    if (dd_demo_res.choice == DemoChoice.on_main) {
        dvui.Examples.demo(.lite);
    }

    return true;
}

var nested_wins: [10]bool = @splat(false);

pub fn nestedOsWin(n: usize) void {
    if (dvui.button(@src(), "Can we nest windows ?", .{}, .{})) {
        nested_wins[n] = true;
    }
    if (!nested_wins[n]) return;

    // Note that here id_extra is superfluous because the hash is derived from current_window therefore it's really two different windows.
    const os_win = dvui.osWindow(@src(), .{ .title = "I have the ambition to be an OS win ... (if the backend allows)" }, .{});
    defer os_win.deinit();

    nestedOsWin(n + 1);

    var tl3 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem2 = "This example shows some stuff in second window.";
    tl3.addText(lorem2, .{});
    tl3.deinit();

    if (dvui.button(@src(), "button test", .{}, .{})) {
        std.debug.print("clicked on button in window n={}\n", .{n});
    }
    var float = dvui.floatingWindow(@src(), .{}, .{ .min_size_content = .{ .h = 350 } });
    dvui.label(@src(), "I'm floating. In the child os window if there is one", .{}, .{});
    if (dvui.button(@src(), "button test in floating", .{}, .{})) {
        std.debug.print("clicked on test button in floating\n", .{});
    }
    if (dvui.button(@src(), "stop showing stuff in the child os window", .{}, .{})) {
        nested_wins[n] = false;
    }
    if (dvui.expander(@src(), "Show me a Spinner !!", .{ .default_expanded = false }, .{})) {
        dvui.spinner(@src(), .{});
    }
    float.deinit();
    dvui.label(@src(), "One last thing ;-)", .{}, .{});
}
