const std = @import("std");
const dvui = @import("dvui");
const RaylibBackend = @import("RaylibBackend");
const ray = RaylibBackend.c;

const window_icon_png = @embedFile("zig-favicon.png");

//TODO:
//Figure out the best way to integrate raylib and dvui Event Handling

pub fn main() !void {
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();

    defer _ = gpa_instance.deinit();

    //create actual OS window with raylib
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    ray.InitWindow(800, 600, "DVUI Raylib Ontop Example");

    // init Raylib backend
    var backend = try RaylibBackend.init();
    backend.log_events = true;

    // init dvui Window (maps onto a single OS window)
    // OS window is managed by raylib, not dvui
    var win = try dvui.Window.init(@src(), 0, gpa, backend.backend());

    var selected_color: ray.Color = ray.RAYWHITE;

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(std.time.nanoTimestamp());

        dvui.themeSet(&dvui.Theme.Jungle);

        // send all Raylib events to dvui for processing
        const lock_raygui = try backend.addAllEvents(&win);

        // NOTE locking raygui this way does not seem to work yet, it might be something with timing
        // TODO figure this out
        if (lock_raygui and !ray.GuiIsLocked()) {
            std.debug.print("raygui input disabled\n", .{});

            // NOTE: I am using raygui here because it has a simple lock-unlock system
            // Non-raygui raylib apps could also easily implement such a system
            ray.GuiLock();
        } else if (ray.GuiIsLocked()) {
            std.debug.print("raygui input enabled\n", .{});
            ray.GuiUnlock();
        }

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        backend.clear();

        {
            var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer b.deinit();
            try dvui.label(@src(), "DVUI layout and RAYGUI Widget", .{}, .{ .gravity_y = 0.5 });

            if (try dvui.expander(@src(), "Pick Color", .{}, .{ .expand = .horizontal, .margin = .{ .x = 10, .y = 10 } })) {
                var hbox = try dvui.box(@src(), .vertical, .{});
                defer hbox.deinit();

                var overlay = try dvui.overlay(@src(), .{ .min_size_content = .{ .w = 300, .h = 300 } });
                defer overlay.deinit();
                try overlay.install();

                //TODO I think I am getting the widget rectangle size wrong here
                //need to figure out how to ask dvui to allocate a minimum amount of empty space
                const bounds = RaylibBackend.dvuiRectToRaylib(overlay.data().contentRect());
                _ = ray.GuiColorPicker(bounds, "Pick Color", &selected_color);
            }
        }

        ray.DrawText("Congrats! You Combined Raylib, Raygui and DVUI!", 20, 400, 20, ray.RAYWHITE);

        try dvuiStuff();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before EndDrawing()
        _ = try win.end(.{});

        ray.EndDrawing();
    }

    win.deinit();
    backend.deinit();
    ray.CloseWindow();
}

fn dvuiStuff() !void {
    var float = try dvui.floatingWindow(@src(), .{}, .{ .min_size_content = .{ .w = 400, .h = 300 } });
    defer float.deinit();

    try dvui.windowHeader("Floating Window", "", null);

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    defer scroll.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui for floating windows on top of an existing application.";
    try tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    try tl2.addText("The dvui is painting only floating windows and dialogs.", .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Framerate is managed by the application (in this demo capped at vsync).", .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Cursor is only being set by dvui for floating windows.", .{});
    try tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        try tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        try tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (try dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}
