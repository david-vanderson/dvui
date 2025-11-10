const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl3gpu-backend");
comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

// straight copy-paste of sdl3 backend example,

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

pub const c = SDLBackend.c;

const vsync = false;
const show_demo = false;

var window: *c.SDL_Window = undefined;
var device: *c.SDL_GPUDevice = undefined;

/// This example shows how to use dvui for floating windows on top of an existing application
/// - dvui renders only floating windows
/// - framerate is managed by application, not dvui
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    SDLBackend.enableSDLLogging();
    dvui.Examples.show_demo_window = show_demo;

    // app_init is a stand-in for what your application is already doing to set things up
    try app_init();

    // create SDL backend using existing window and renderer, app still owns the window/renderer
    var backend = SDLBackend.init(window, device);
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

        // draw hello-triangle with sdl-gpu

        dvui_floating_stuff();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        _ = try win.end(.{});

        // cursor management
        if (win.cursorRequestedFloating()) |cursor| {
            // cursor is over floating window, dvui sets it
            try backend.setCursor(cursor);
        } else {
            // cursor should be handled by application
            try backend.setCursor(.bad);
        }
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();
    }

    c.SDL_DestroyGPUDevice(device);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

fn dvui_floating_stuff() void {
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
    tl2.addText("Framerate is managed by the application", .{});
    if (vsync) {
        tl2.addText(" (capped at vsync)", .{});
    } else {
        tl2.addText(" (uncapped - no vsync)", .{});
    }
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

fn app_init() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != if (SDLBackend.sdl3) true else 0) {
        std.debug.print("Couldn't initialize SDL: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    }

    const hidden_flag = if (dvui.accesskit_enabled) c.SDL_WINDOW_HIDDEN else 0;

    window = c.SDL_CreateWindow("DVUI SDLGPU Ontop Example", @as(c_int, @intCast(640)), @as(c_int, @intCast(480)), c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE | hidden_flag) orelse {
        std.debug.print("Failed to open window: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL, true, null) orelse {
        std.debug.print("Failed to create device: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    std.debug.print("sdl gpu device created", .{});
}
