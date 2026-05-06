const std = @import("std");
const dvui = @import("dvui");
const WebBackend = @import("web-backend");

comptime {
    std.debug.assert(@hasDecl(WebBackend, "WebBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
const show_demo = false;
var scale_val: f32 = 1.0;

var show_dialog_outside_frame: bool = false;
var g_initialized = false;
var g_interrupted = true;

pub const panic = WebBackend.panic;
pub const std_options: std.Options = .{
    .logFn = WebBackend.logFn,
};

/// Worker entry hook used by web backend standalone mode.
pub fn dvui_web_main() !void {
    return main();
}

/// This example matches the SDL standalone structure:
/// - explicit backend and window setup
/// - explicit frame loop
/// - explicit event pump and wait
pub fn main() !void {
    try standaloneInit(null, 0);
    defer standaloneDeinit();

    main_loop: while (true) {
        const wait_event_micros = (try frameStep()) orelse break :main_loop;
        g_interrupted = try WebBackend.back.waitEventTimeout(wait_event_micros);
    }
}

pub fn dvui_web_init(platform_ptr: [*]const u8, platform_len: usize) !void {
    try standaloneInit(platform_ptr, platform_len);
}

pub fn dvui_web_update() !i32 {
    const wait_event_micros = (try frameStep()) orelse return -1;
    return @intCast(@divTrunc(wait_event_micros, 1000));
}

pub fn dvui_web_deinit() void {
    standaloneDeinit();
}

fn standaloneInit(platform_ptr: ?[*]const u8, platform_len: usize) !void {
    _ = platform_ptr;
    _ = platform_len;
    if (g_initialized) return;

    dvui.Examples.show_demo_window = show_demo;

    WebBackend.back = try WebBackend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI Web Standalone Example",
        .icon = window_icon_png,
    });

    WebBackend.win = try dvui.Window.init(@src(), gpa, WebBackend.back.backend(), .{
        .theme = switch (WebBackend.back.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });

    WebBackend.win_ok = true;

    g_interrupted = true;
    g_initialized = true;
}

/// Execute one standalone frame.
/// Returns micros to wait before next frame, or null when app should close.
fn frameStep() !?u32 {
    if (!g_initialized) return null;
    var back = &WebBackend.back;
    var win_ref = &WebBackend.win;

    const nstime = win_ref.beginWait(g_interrupted);
    try win_ref.begin(nstime);

    try back.addAllEvents(win_ref);

    const keep_running = gui_frame();
    if (!keep_running) return null;

    const end_micros = try win_ref.end(.{});

    back.setCursor(win_ref.cursorRequested());
    back.textInputRect(win_ref.textInputRequested());

    try back.renderPresent();

    if (show_dialog_outside_frame) {
        show_dialog_outside_frame = false;
        dvui.dialog(
            @src(),
            .{},
            .{
                .window = win_ref,
                .modal = false,
                .title = "Dialog from Outside",
                .message = "This is a non modal dialog created outside win.begin()/win.end().",
            },
        );
    }

    return win_ref.waitTime(end_micros);
}

fn standaloneDeinit() void {
    if (!g_initialized) return;
    WebBackend.win_ok = false;
    WebBackend.win.deinit();
    WebBackend.back.deinit();
    g_initialized = false;
}

// both dvui and backend drawing
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

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem = "This example shows how to use dvui in a normal standalone application on the web.";
    tl.addText(lorem, .{});
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
    tl2.addText("\n", .{});
    tl2.addText("Cursor is always being set by dvui.\n\n", .{});
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

        dvui.labelNoFmt(@src(), "Backend-direct drawing demo is SDL-specific and omitted for web.", .{}, .{ .margin = .{ .x = 4 } });
    }

    if (dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
        show_dialog_outside_frame = true;
    }

    dvui.Examples.demo(.full);

    for (dvui.events()) |*e| {
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
    }

    return true;
}
