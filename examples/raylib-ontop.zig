const std = @import("std");
const dvui = @import("dvui");
const RaylibBackend = @import("RaylibBackend");
const ray = @cImport({
    @cInclude("raylib.h");
});

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
    ray.InitWindow(800, 450, "DVUI Raylib Ontop Example");

    // init Raylib backend
    var backend = try RaylibBackend.init(.user, null);
    backend.log_events = true;

    // init dvui Window (maps onto a single OS window)
    // OS window is managed by raylib, not dvui
    var win = try dvui.Window.init(@src(), 0, gpa, backend.backend());

    while (!ray.WindowShouldClose()) {

        // beginWait coordinates with waitTime below to run frames only when needed
        //const nstime = win.beginWait(backend.hasEvent());

        //try win.begin(nstime);
        ray.BeginDrawing();

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        ray.ClearBackground(ray.BLACK);

        ray.DrawText("Congrats! You Combined Raylib and DVUI!", 190, 200, 20, ray.RAYWHITE);

        const rect = ray.Rectangle{ .x = 300, .y = 300, .width = 300, .height = 100 };
        ray.DrawRectangleGradientEx(rect, ray.RAYWHITE, ray.BLACK, ray.BLUE, ray.RED);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        // This function does NOT call ray.BeginDrawing because this backend was set as
        // user managed rather than dvui managed. Otherwise ray.BeginDrawing would be called
        try win.begin(std.time.nanoTimestamp());

        // send all Raylib events to dvui for processing
        _ = try backend.addAllEvents(&win);

        try dvuiFrame();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        // This function does NOT call ray.EndDrawing because this backend was set as
        // user managed rather than dvui managed
        const end_micros = try win.end(.{});
        _ = end_micros;

        ray.EndDrawing();
    }

    win.deinit();
    backend.deinit();
    ray.CloseWindow();
}

fn dvuiFrame() !void {
    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (try dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}
