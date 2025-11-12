const std = @import("std");
const dvui = @import("dvui");
const RaylibBackend = @import("raylib-backend");
comptime {
    std.debug.assert(@hasDecl(RaylibBackend, "RaylibBackend"));
}
const ray = RaylibBackend.c;

const window_icon_png = @embedFile("zig-favicon.png");

//TODO:
//Figure out the best way to integrate raylib and dvui Event Handling

pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        try dvui.Backend.Common.windowsAttachConsole();
    }
    RaylibBackend.enableRaylibLogging();
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();

    defer _ = gpa_instance.deinit();

    // create OS window directly with raylib
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    ray.InitWindow(800, 600, "DVUI Raylib Ontop Example");
    defer ray.CloseWindow();

    // init Raylib backend
    // init() means the app owns the window (and must call CloseWindow itself)
    var backend = RaylibBackend.init(gpa);
    defer backend.deinit();
    backend.log_events = true;

    // init dvui Window (maps onto a single OS window)
    // OS window is managed by raylib, not dvui
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    var selected_color: dvui.Color = dvui.Color.white;

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(std.time.nanoTimestamp());

        // send all Raylib events to dvui for processing
        try backend.addAllEvents(&win);

        if (backend.shouldBlockRaylibInput()) {
            // NOTE: I am using raygui here because it has a simple lock-unlock system
            // Non-raygui raylib apps could also easily implement such a system
            ray.GuiLock();
        } else {
            ray.GuiUnlock();
        }
        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        ray.ClearBackground(RaylibBackend.dvuiColorToRaylib(dvui.Color.black));

        {
            var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer b.deinit();

            if (ray.GuiIsLocked()) {
                dvui.label(@src(), "Raygui Status: Locked", .{}, .{});
            } else {
                dvui.label(@src(), "Raygui Status: Unlocked", .{}, .{});
            }

            if (dvui.expander(@src(), "Pick Color Using Raygui", .{}, .{})) {
                colorPicker(&selected_color);
            }
        }

        ray.DrawText("Congrats! You Combined Raylib, Raygui and DVUI!", 20, 400, 20, ray.RAYWHITE);

        dvuiStuff();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before EndDrawing()
        _ = try win.end(.{});

        // cursor management
        if (win.cursorRequestedFloating()) |cursor| {
            // cursor is over floating window, dvui sets it
            backend.setCursor(cursor);
        } else {
            // cursor should be handled by application
            backend.setCursor(.arrow);
        }

        ray.EndDrawing();
    }
}

fn colorPicker(result: *dvui.Color) void {
    _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });
    {
        var overlay = dvui.overlay(@src(), .{ .min_size_content = .{ .w = 100, .h = 100 } });
        defer overlay.deinit();

        const bounds = overlay.data().contentRectScale().r;
        const ray_bounds: ray.Rectangle = .{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.w,
            .height = bounds.h,
        };
        var c_color: ray.Color = RaylibBackend.dvuiColorToRaylib(result.*);
        _ = ray.GuiColorPicker(ray_bounds, "Pick Color", &c_color);
        result.* = RaylibBackend.raylibColorToDvui(c_color);
    }

    const color_hex = result.toHexString();

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.labelNoFmt(@src(), &color_hex, .{}, .{
            .color_text = result.*,
            .gravity_y = 0.5,
        });

        const copy = dvui.button(@src(), "Copy", .{}, .{});

        if (copy) {
            dvui.clipboardTextSet(&color_hex);
            dvui.toast(@src(), .{ .message = "Copied!" });
        }
    }
}

fn dvuiStuff() void {
    var float = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .w = 400, .h = 400 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("Floating Window", "", null));

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui for floating windows on top of an existing application.";
    tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText("The dvui is painting only floating windows and dialogs.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is managed by the application (in this demo capped at vsync).", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is only being set by dvui for floating windows.", .{});
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

    // look at demo() for examples of dvui widgets, shows in a floating window
    dvui.Examples.demo();
}
