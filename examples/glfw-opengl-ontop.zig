const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("glfw-opengl-backend");
const zglfw = Backend.zglfw;
const zgl = Backend.zgl;

// This can optionally be added in source file to manage how opengl
// errors are handled.
pub const opengl_error_handling = zgl.ErrorHandling.assert;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();
var window: *zglfw.Window = undefined;

fn glGetProcAddress(p: zglfw.GlProc, proc: [:0]const u8) ?zgl.binding.FunctionPointer {
    _ = p;
    return @alignCast(zglfw.getProcAddress(proc));
}

pub fn main() !void {
    dvui.Examples.show_demo_window = true;

    try app_init();
}

pub fn app_init() !void {
    try zglfw.init();
    //Recommended hints
    zglfw.windowHint(.context_version_major, 3);
    zglfw.windowHint(.context_version_minor, 3);
    zglfw.windowHint(.opengl_profile, .opengl_core_profile);
    zglfw.windowHint(.client_api, .opengl_api);
    // Optional
    zglfw.windowHint(.doublebuffer, true);
    window = try zglfw.Window.create(640, 480, "Hello World", null);
    // You need to call makeContextCurrent before calling any of the
    // backend functions
    zglfw.makeContextCurrent(window);
    zglfw.swapInterval(1);

    // The backend currently initializes zgl context in Backend.init in case the
    // user doesn't use zgl. Therefore, the user doesn't have to initialize it
    // themselves, but doing so results in no error.
    // const proc: zglfw.GlProc = undefined;
    // try zgl.loadExtensions(proc, glGetProcAddress);

    var impl = Backend.init(gpa, window);
    defer impl.deinit();

    const backend = dvui.Backend.init(&impl);
    var win = try dvui.Window.init(@src(), gpa, backend, .{});
    defer win.deinit();

    while (!window.shouldClose()) {
        // Poll events can be placed anywhere since the backend keeps its own
        // event queue. Here we instead use a separate method shown below, that
        // uses dvui to poll for events and only wakes on new input or dvui
        // events. In case your library has its own time-dependent render logic,
        // zglfw.pollEvents should be used.
        //
        // zglfw.pollEvents();
        zgl.clearColor(0.1, 0.4, 0.25, 1.0);
        zgl.clear(.{ .color = true, .stencil = true, .depth = true });

        // This needs to be called after pollEvents and before or just
        // after win.begin
        impl.addAllEvents(&win);
        try win.begin(std.time.nanoTimestamp());
        dvui.Examples.demo();

        const endtime = try win.end(.{});
        window.swapBuffers();

        // Should be placed after all rendering and after buffer swap. This is
        // instead of `zglfw.pollEvents`, see comment above.
        impl.pollEventsTimeout(&win, endtime);
    }
}
