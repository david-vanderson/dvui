const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub const c = SDLBackend.c;

const vsync = false;
const show_demo = false;

var window: *c.SDL_Window = undefined;
var renderer: *c.SDL_Renderer = undefined;

/// This example shows how to use dvui for floating windows on top of an existing application
/// - dvui renders only floating windows
/// - framerate is managed by application, not dvui
pub fn main() !void {
    dvui.Examples.show_demo_window = show_demo;

    // app_init is a stand-in for what your application is already doing to set things up
    try app_init();

    // create SDL backend using existing window and renderer, app still owns the window/renderer
    var backend = SDLBackend.init(window, renderer);
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    main_loop: while (true) {

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(std.time.nanoTimestamp());

        // send events to dvui if they belong to floating windows
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) == if (SDLBackend.sdl3) true else 1) {
            // some global quitting shortcuts
            switch (event.type) {
                if (SDLBackend.sdl3) c.SDL_EVENT_KEY_DOWN else c.SDL_KEYDOWN => {
                    const key = if (SDLBackend.sdl3) event.key.key else event.key.keysym.sym;
                    const mod = if (SDLBackend.sdl3) event.key.mod else event.key.keysym.mod;
                    const key_q = if (SDLBackend.sdl3) c.SDLK_Q else c.SDLK_q;
                    const kmod_ctrl = if (SDLBackend.sdl3) c.SDL_KMOD_CTRL else c.KMOD_CTRL;
                    if (((mod & kmod_ctrl) > 0) and key == key_q) {
                        break :main_loop;
                    }
                },
                if (SDLBackend.sdl3) c.SDL_EVENT_QUIT else c.SDL_QUIT => {
                    break :main_loop;
                },
                else => {},
            }

            if (try backend.addEvent(&win, event)) {
                // dvui handles this event as it's for a floating window
            } else {
                // dvui doesn't handle this event, send it to the underlying application
            }
        }

        // clear the window
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);

        // draw some SDL stuff with dvui floating stuff in the middle
        const rect: if (SDLBackend.sdl3) c.SDL_FRect else c.SDL_Rect = .{ .x = 10, .y = 10, .w = 20, .h = 20 };
        var rect2 = rect;
        _ = c.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
        _ = c.SDL_RenderFillRect(renderer, &rect2);

        try dvui_floating_stuff();

        rect2.x += 24;
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        _ = c.SDL_RenderFillRect(renderer, &rect2);

        rect2.x += 24;
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 255, 255);
        _ = c.SDL_RenderFillRect(renderer, &rect2);

        _ = c.SDL_SetRenderDrawColor(renderer, 255, 0, 255, 255);

        if (SDLBackend.sdl3) _ = c.SDL_RenderLine(renderer, rect.x, rect.y + 30, rect.x + 100, rect.y + 30) else _ = c.SDL_RenderDrawLine(renderer, rect.x, rect.y + 30, rect.x + 100, rect.y + 30);

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        _ = try win.end(.{});

        // cursor management
        if (win.cursorRequestedFloating()) |cursor| {
            // cursor is over floating window, dvui sets it
            backend.setCursor(cursor);
        } else {
            // cursor should be handled by application
            backend.setCursor(.bad);
        }
        backend.textInputRect(win.textInputRequested());

        // render frame to OS
        backend.renderPresent();
    }

    c.SDL_DestroyRenderer(renderer);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

fn dvui_floating_stuff() !void {
    var float = try dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .w = 400, .h = 400 } });
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
    try tl2.addText("Framerate is managed by the application", .{});
    if (vsync) {
        try tl2.addText(" (capped at vsync)", .{});
    } else {
        try tl2.addText(" (uncapped - no vsync)", .{});
    }
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

fn app_init() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != if (SDLBackend.sdl3) true else 0) {
        std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    }

    if (SDLBackend.sdl3) {
        window = c.SDL_CreateWindow("DVUI SDL Ontop Example", @as(c_int, @intCast(640)), @as(c_int, @intCast(480)), c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE) orelse {
            std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
        renderer = c.SDL_CreateRenderer(window, null) orelse {
            std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
    } else {
        window = c.SDL_CreateWindow("DVUI SDL Ontop Example", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, @as(c_int, @intCast(640)), @as(c_int, @intCast(480)), c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE) orelse {
            std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
        _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");
        renderer = c.SDL_CreateRenderer(window, -1, if (vsync) c.SDL_RENDERER_PRESENTVSYNC else 0) orelse {
            std.debug.print("Failed to create renderer: {s}\n", .{c.SDL_GetError()});
            return error.BackendError;
        };
    }

    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    _ = c.SDL_SetRenderDrawBlendMode(renderer, pma_blend);
}
