const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const SDLBackend = @import("sdl3gpu-backend");
const window_icon_png = @embedFile("zig-favicon.png");
const c = SDLBackend.c;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
const show_demo = false;
var scale_val: f32 = 1.0;

var show_dialog_outside_frame: bool = false;

/// This example shows how to use dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) {
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

    SDLBackend.enableSDLLogging();
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    dvui.Examples.show_demo_window = show_demo;

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL3GPU backend (creates and owns OS window)
    var backend = try SDLBackend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL3GPU Standalone Example",
        .icon = window_icon_png,
    });

    defer backend.deinit();

    _ = c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });
    defer win.deinit();
    try win.fonts.addBuiltinFontsForTheme(win.gpa, dvui.Theme.builtin.adwaita_light);

    var interrupted = false;

    main_loop: while (true) {
        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        _ = try backend.addAllEvents(&win);

        // NOTE: SDL3GPU doesn't need manual clearing like SDL_Renderer
        // GPU backend handles clearing via render pass (LOAD_OP_CLEAR)

        const keep_running = gui_frame();
        if (!keep_running) {
            std.log.info("Exiting main loop, keep_running = false", .{});
            break :main_loop;
        }

        // marks end of dvui frame, don't call dvui functions after this
        const end_micros = try win.end(.{});

        // cursor management
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);

        // Example of dialog from another thread
        if (show_dialog_outside_frame) {
            show_dialog_outside_frame = false;
            dvui.dialog(@src(), .{}, .{
                .window = &win,
                .modal = false,
                .title = "Dialog from Outside",
                .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread.",
            });
        }
    }
}

fn gui_frame() bool {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .style = .window,
            .background = true,
            .expand = .horizontal,
            .name = "main",
        });
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
                std.log.info("Exit menu item clicked!", .{});
                return false;
            }
        }

        if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui in a standalone application with SDL3 GPU.";
    tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI with SDL3 GPU Backend
        \\- Uses modern GPU API (not SDL_Renderer)
        \\- Batched rendering with command buffers
        \\- Efficient texture uploads via transfer buffers
        \\- Render passes for structured GPU work
        \\- Supports multiple shader formats (SPIR-V, DXIL, MSL)
    , .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    tl2.addText("\n\n", .{});
    if (vsync) {
        tl2.addText("Framerate is capped by vsync (PRESENTMODE_VSYNC).", .{});
    } else {
        tl2.addText("Framerate is uncapped (PRESENTMODE_IMMEDIATE).", .{});
    }
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.", .{});
    tl2.addText("\n\n", .{});
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

    {
        var scaler = dvui.scale(@src(), .{ .scale = &scale_val }, .{ .expand = .horizontal });
        defer scaler.deinit();

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            if (dvui.button(@src(), "Zoom In", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;
            }

            if (dvui.button(@src(), "Zoom Out", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;
            }
        }

        // NOTE: Direct GPU drawing would be different from SDL_Renderer
        // SDL3GPU uses command buffers, render passes, and pipelines
        // For now, just show DVUI-only content
        dvui.labelNoFmt(@src(), "SDL3GPU backend uses batched GPU rendering for all DVUI content.", .{}, .{ .margin = .{ .x = 4 } });
    }

    if (dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
        show_dialog_outside_frame = true;
    }

    // look at demo() for examples of dvui widgets
    dvui.Examples.demo();

    // check for quitting
    for (dvui.events()) |*e| {
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
    }

    return true;
}
