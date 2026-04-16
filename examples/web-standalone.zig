const std = @import("std");
const dvui = @import("dvui");
const WebBackend = @import("web-backend");

comptime {
    std.debug.assert(@hasDecl(WebBackend, "WebBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

/// This example shows how to use dvui for a normal application on the web:
/// - dvui renders the whole application
/// - render frames only when needed
/// - runs in a Web Worker with blocking main loop (same as native backends)
///
/// The user code is near-identical to sdl-standalone.zig.
///
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI Web Standalone Example",
            .icon = window_icon_png,
        },
    },
    .frameFn = gui_frame,
    .initFn = null,
    .deinitFn = null,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var show_demo = false;

fn gui_frame() !dvui.App.Result {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                m.close();
            }
        }

        if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    tl.addText("This example runs in standalone mode using a Web Worker.", .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI Web Standalone
        \\- runs in a Web Worker with a blocking main loop
        \\- same code structure as SDL/DX11 standalone examples
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\
        \\
    , .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.\n\n", .{});
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

    // only shows the demo if dvui.Examples.show_demo_window is true
    dvui.Examples.demo(.full);

    return .ok;
}
