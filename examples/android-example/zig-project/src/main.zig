const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const window_icon_png = @embedFile("zig-favicon.png");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI App Example",
            .icon = window_icon_png,
            .window_init_options = .{
                // Could set a default theme here
                // .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};
pub const main = dvui.App.main;

// NOTE: this is a static lib (like the iOS example), so zig's start.zig never runs and
// never builds the std.process.Init dvui.App.main needs. main.c has the real C main()
// and calls this exported symbol; hand-build the same minimal Init here.
export fn dvui_main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    return runDvuiMain(argc, argv) catch |err| {
        std.log.err("dvui_main failed: {t}", .{err});
        return 1;
    };
}

extern "c" var environ: ?[*:null]?[*:0]u8;

fn runDvuiMain(argc: c_int, argv: [*][*:0]u8) !u8 {
    const gpa = std.heap.c_allocator;

    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();

    const args_vector: std.process.Args.Vector = argv[0..@intCast(argc)];
    const environ_block: std.process.Environ.Block = .{ .slice = std.mem.span(environ orelse @as([*:null]?[*:0]u8, @ptrFromInt(@alignOf(?[*:0]u8)))) };

    var threaded: std.Io.Threaded = .init(gpa, .{
        .argv0 = .init(.{ .vector = args_vector }),
        .environ = .{ .block = environ_block },
    });
    defer threaded.deinit();

    var environ_map = try std.process.Environ.createMap(.{ .block = environ_block }, gpa);
    defer environ_map.deinit();

    const preopens = try std.process.Preopens.init(arena_allocator.allocator());

    return dvui.App.main(.{
        .minimal = .{ .args = .{ .vector = args_vector }, .environ = .{ .block = environ_block } },
        .arena = &arena_allocator,
        .gpa = gpa,
        .io = threaded.io(),
        .environ_map = &environ_map,
        .preopens = preopens,
    });
}
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var orig_content_scale: f32 = 1.0;
var warn_on_quit: bool = false;
var warn_on_quit_closing: bool = false;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn appInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;

    // Add your own bundled font files...:
    // try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    // If you want a custom theme use something like this:
    // const theme = switch (win.backend.preferredColorScheme() orelse .light) {
    //     .light => dvui.Theme.builtin.adwaita_light,
    //     .dark => dvui.Theme.builtin.adwaita_dark,
    // };
    // win.themeSet(theme);
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn appDeinit(win: *dvui.Window) void {
    _ = win;
}

// Run each frame to do normal UI
pub fn appFrame() !dvui.App.Result {
    {
        // Here's the dvui example content, replace/modify with your stuff

        var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
        scaler.deinit();

        if (menu()) |res| return res;

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
        defer scroll.deinit();

        if (content()) |res| return res;
    }

    // only shows the demo if dvui.Examples.show_demo_window is true
    // .full -> .lite or comment out to speed up compile times
    dvui.Examples.demo(.full);

    return .ok;
}

pub fn menu() ?dvui.App.Result {
    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
    defer hbox.deinit();

    var m = dvui.menu(@src(), .horizontal, .{});
    defer m.deinit();

    if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .tag = "first-focusable" })) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();

        if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
            m.close();
        }

        if (dvui.backend.kind != .web) {
            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                return .close;
            }
        }
    }

    return null;
}

pub fn content() ?dvui.App.Result {
    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem = "This is a dvui.App example that can compile on multiple backends.\n";
    tl.addText(lorem, .{});
    tl.format("Current backend: {s}", .{@tagName(dvui.backend.kind)}, .{});
    if (dvui.backend.kind == .web) {
        tl.format(" : {s}", .{if (dvui.backend.wasm.wasm_about_webgl2() == 1) "webgl2" else "webgl (no mipmaps)"}, .{});
    }
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- rest of the window is a scroll area
        \\
        \\
    , .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.\n\n", .{});
    tl2.addText("Framerate is capped by vsync.\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        dvui.label(@src(), "Pinch Zoom or Scale", .{}, .{});
        if (dvui.buttonIcon(@src(), "plus", dvui.entypo.plus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale *= 1.1;
        }

        if (dvui.buttonIcon(@src(), "minus", dvui.entypo.minus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale /= 1.1;
        }

        if (dvui.currentWindow().content_scale != orig_content_scale) {
            if (dvui.button(@src(), "Reset Scale", .{}, .{})) {
                dvui.currentWindow().content_scale = orig_content_scale;
            }
        }
    }

    if (dvui.backend.kind != .web) {
        _ = dvui.checkbox(@src(), &warn_on_quit, "Warn on Quit", .{});

        if (warn_on_quit) {
            if (warn_on_quit_closing) return .close;

            const wd = dvui.currentWindow().data();
            for (dvui.events()) |*e| {
                if (!dvui.eventMatchSimple(e, wd)) continue;

                if ((e.evt == .window and e.evt.window.action == .close) or (e.evt == .app and e.evt.app.action == .quit)) {
                    e.handle(@src(), wd);

                    const warnAfter: dvui.DialogCallAfterFn = struct {
                        fn warnAfter(_: dvui.Id, response: dvui.enums.DialogResponse) !void {
                            if (response == .ok) warn_on_quit_closing = true;
                        }
                    }.warnAfter;

                    dvui.dialog(@src(), .{}, .{ .message = "Really Quit?", .cancel_label = "Cancel", .callafterFn = warnAfter });
                }
            }
        }
    }

    return null;
}
