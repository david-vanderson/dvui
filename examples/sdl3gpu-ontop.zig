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

const log = std.log.scoped(.SDL3GPUBackend);

/// This example shows how to use dvui for floating windows on top of an existing application
/// - dvui renders only floating windows
/// - framerate is managed by application, not dvui
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

    defer std.debug.assert(gpa_instance.deinit() == .ok);

    SDLBackend.enableSDLLogging();
    dvui.Examples.show_demo_window = show_demo;

    // app_init is a stand-in for what your application is already doing to set things up
    try app_init();

    // create SDL backend using existing window and renderer, app still owns the window/renderer
    var backend = SDLBackend.init(window, device, gpa_instance.allocator());
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    main_loop: while (true) {
        const cmd = c.SDL_AcquireGPUCommandBuffer(backend.device);
        var swapchain_texture: ?*c.SDL_GPUTexture = null;

        // Acquire swapchain texture for this frame
        var swapchain_w: u32 = 0;
        var swapchain_h: u32 = 0;
        if (!c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd, backend.window, &swapchain_texture, &swapchain_w, &swapchain_h)) {
            log.err("Failed to acquire swapchain texture: {s}", .{c.SDL_GetError()});
            _ = c.SDL_SubmitGPUCommandBuffer(cmd);
            backend.cmd = null;
            backend.swapchain_texture = null;
            return;
        }

        // acquire the command buffer and loan it to the backend
        // if cmd is set before calling begin() we are responsible for submitting it
        backend.cmd = cmd;
        backend.swapchain_texture = swapchain_texture;

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(std.time.nanoTimestamp());

        // send events to dvui if they belong to floating windows
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            // some global quitting shortcuts
            switch (event.type) {
                c.SDL_EVENT_KEY_DOWN => {
                    const key = event.key.key;
                    const mod = event.key.mod;
                    const key_q = c.SDLK_Q;
                    const kmod_ctrl = c.SDL_KMOD_CTRL;
                    if (((mod & kmod_ctrl) > 0) and key == key_q) {
                        _ = try win.end(.{});
                        try backend.renderPresent();
                        break :main_loop;
                    }
                },
                c.SDL_EVENT_QUIT => {
                    _ = try win.end(.{});
                    try backend.renderPresent();
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
        var color_target = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
        color_target.texture = backend.swapchain_texture;
        color_target.clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
        color_target.load_op = c.SDL_GPU_LOADOP_CLEAR;
        color_target.store_op = c.SDL_GPU_STOREOP_STORE;

        const clearPass = c.SDL_BeginGPURenderPass(backend.cmd, &color_target, 1, null);
        c.SDL_EndGPURenderPass(clearPass);

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

        // its still on us to issue the submit and present
        const submitted = c.SDL_SubmitGPUCommandBuffer(cmd);
        if (!submitted) {
            log.err("Failed to submit GPU command buffer: {s}", .{c.SDL_GetError()});
            return error.CommandBufferSubmissionFailed;
        }
    }
}

fn dvui_floating_stuff() void {
    var float = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .w = 400, .h = 400 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("Floating Window", "", null));

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    const lorem = "This example shows how to use dvui for floating windows on top of an existing application.";
    tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText("The dvui is painting only floating windows and dialogs.\n\n", .{});
    tl2.addText("Framerate is managed by the application", .{});
    if (vsync) {
        tl2.addText(" (capped at vsync)\n", .{});
    } else {
        tl2.addText(" (uncapped - no vsync)\n", .{});
    }
    tl2.addText("\n", .{});
    tl2.addText("Cursor is only being set by dvui for floating windows.\n\n", .{});
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

    const debug = true;

    device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL, debug, null) orelse {
        std.debug.print("Failed to create device: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    if (!c.SDL_ClaimWindowForGPUDevice(device, window)) {
        return error.BackendError;
    }

    if (!c.SDL_SetGPUSwapchainParameters(
        device,
        window,
        c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        c.SDL_GPU_PRESENTMODE_IMMEDIATE,
    )) {
        std.debug.print("Failed to set IMMEDIATE present mode: {s}", .{c.SDL_GetError()});
    }

    std.debug.print("sdl gpu device created", .{});
}
