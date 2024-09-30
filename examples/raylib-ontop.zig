const std = @import("std");
const dvui = @import("dvui");
comptime {
    std.debug.assert(dvui.backend_kind == .raylib);
}
const RaylibBackend = dvui.backend;
const ray = RaylibBackend.c;

const window_icon_png = @embedFile("zig-favicon.png");

const alloc = std.heap.c_allocator;
//TODO:
//Figure out the best way to integrate raylib and dvui Event Handling

pub fn main() !void {
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
    var backend = RaylibBackend.init();
    defer backend.deinit();
    backend.log_events = true;

    // init dvui Window (maps onto a single OS window)
    // OS window is managed by raylib, not dvui
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{ .theme = &dvui.Theme.Jungle });
    defer win.deinit();

    //var selected_color: dvui.Color = dvui.Color.white;

    var quick_theme = try dvui.Theme.QuickTheme.initDefault(std.heap.c_allocator);

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(std.time.nanoTimestamp());

        // send all Raylib events to dvui for processing
        _ = try backend.addAllEvents(&win);

        if (backend.shouldBlockRaylibInput()) {
            // NOTE: I am using raygui here because it has a simple lock-unlock system
            // Non-raygui raylib apps could also easily implement such a system
            ray.GuiLock();
        } else {
            ray.GuiUnlock();
        }
        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        ray.ClearBackground(RaylibBackend.dvuiColorToRaylib(dvui.themeGet().color_fill_window));

        {
            var b = try dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer b.deinit();

            if (ray.GuiIsLocked()) {
                try dvui.label(@src(), "Raygui Status: Locked", .{}, .{ .gravity_y = 0.5 });
            } else {
                try dvui.label(@src(), "Raygui Status: Unlocked", .{}, .{ .gravity_y = 0.5 });
            }

            if (try dvui.expander(@src(), "Pick Color Using Raygui", .{}, .{})) {
                //try colorPicker(&selected_color);
                try quickTheme(&quick_theme);
            }
        }

        //        ray.DrawText("Congrats! You Combined Raylib, Raygui and DVUI!", 20, 400, 20, ray.RAYWHITE);
        //
        //        try dvuiStuff();

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

fn quickTheme(result: *dvui.Theme.QuickTheme) !void {
    var overall_box = try dvui.box(@src(), .horizontal, .{});
    defer overall_box.deinit();

    try dvui.structEntryExAlloc(@src(), std.heap.c_allocator, "", dvui.Theme.QuickTheme, result, .{
        .fields = .{
            .color_focus = .{ .disabled = true },
            .color_text = .{ .disabled = true },
            .color_text_press = .{ .disabled = true },
            .color_fill_text = .{ .disabled = true },
            .color_fill_container = .{ .disabled = true },
            .color_fill_control = .{ .disabled = true },
            .color_fill_hover = .{ .disabled = true },
            .color_fill_press = .{ .disabled = true },
            .color_border = .{ .disabled = true },
        },
    });

    _ = try dvui.spacer(@src(), .{ .w = 10, .h = 10 }, .{});

    {
        var vbox = try dvui.box(@src(), .vertical, .{ .min_size_content = .{ .h = 500 } });
        defer vbox.deinit();

        var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .vertical });
        defer scroll.deinit();

        inline for (dvui.Theme.QuickTheme.colorFieldNames, 0..) |name, i| {
            var box = try dvui.box(@src(), .vertical, .{ .id_extra = i });
            defer box.deinit();
            var color: ray.Color = RaylibBackend.dvuiColorToRaylib(try dvui.Color.fromHex(@field(result, name)));

            _ = try dvui.spacer(@src(), .{ .w = 10, .h = 10 }, .{});

            {
                var hbox = try dvui.box(@src(), .horizontal, .{ .id_extra = i });
                defer hbox.deinit();
                try dvui.labelNoFmt(@src(), name, .{});
                try dvui.label(@src(), ": {s}", .{@field(result, name)}, .{});
            }

            try colorPicker(&color);

            std.mem.copyForwards(u8, &@field(result, name), &try RaylibBackend.raylibColorToDvui(color).toHexString());

            _ = try dvui.spacer(@src(), .{ .w = 10, .h = 10 }, .{});
        }
    }
}

fn colorPicker(result: *ray.Color) !void {
    var hbox = try dvui.box(@src(), .vertical, .{});
    defer hbox.deinit();
    _ = try dvui.spacer(@src(), .{ .w = 10, .h = 10 }, .{});
    {
        var overlay = try dvui.overlay(@src(), .{ .min_size_content = .{ .w = 100, .h = 100 } });
        defer overlay.deinit();

        const bounds = RaylibBackend.dvuiRectToRaylib(overlay.data().contentRectScale().r);
        _ = ray.GuiColorPicker(bounds, "Pick Color", result);
        //result.* = RaylibBackend.raylibColorToDvui(c_color);
    }

    //const color_hex = try result.toHexString();

    //{
    //    var hbox = try dvui.box(@src(), .horizontal, .{});
    //    defer hbox.deinit();

    //    try dvui.labelNoFmt(@src(), &color_hex, .{
    //        .color_text = .{ .color = result.* },
    //        .gravity_y = 0.5,
    //    });

    //    const copy = try dvui.button(@src(), "Copy", .{}, .{});

    //    if (copy) {
    //        try dvui.clipboardTextSet(&color_hex);
    //        try dvui.toast(@src(), .{ .message = "Copied!" });
    //    }
    //}
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
