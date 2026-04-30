const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("glfw-backend");
const zgl = @import("zgl");
const zglfw = Backend.zglfw;

// This can optionally be added in source file to manage how opengl
// errors are handled.
pub const opengl_error_handling = zgl.ErrorHandling.assert;

var window: *zglfw.Window = undefined;

fn glGetProcAddress(p: zglfw.GlProc, proc: [:0]const u8) ?zgl.binding.FunctionPointer {
    _ = p;
    return @alignCast(zglfw.getProcAddress(proc));
}

pub fn main(main_init: std.process.Init) !void {
    dvui.Examples.show_demo_window = true;

    if (dvui.render_backend.kind != .opengl) @compileError("unsupported renderer");

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

    const proc: zglfw.GlProc = undefined;
    try zgl.loadExtensions(proc, glGetProcAddress);

    var renderer = try dvui.render_backend.init(main_init.gpa, zglfw.getProcAddress, "330");

    var impl = Backend.init(main_init.io, main_init.gpa, window);
    defer impl.deinit();

    const backend = dvui.Backend.init(&impl, &renderer);
    var win = try dvui.Window.init(@src(), main_init.gpa, backend, .{});
    defer win.deinit();

    while (!window.shouldClose()) {
        // Poll events can be placed anywhere since the backend keeps its own
        // event queue. Here we instead use a separate method shown below, that
        // uses dvui to poll for events and only wakes on new input or dvui
        // events. In case your library has its own time-dependent render logic,
        // zglfw.pollEvents should be used.
        //
        // zglfw.pollEvents();

        // temporarily disabled due to "unable to perform tail call: compiler backend 'stage2_x86_64' does not support tail calls"
        //zgl.clearColor(0.1, 0.4, 0.25, 1.0);
        //zgl.clear(.{ .color = true, .stencil = true, .depth = true });

        // This needs to be called after pollEvents and before or just
        // after win.begin
        impl.addAllEvents(&win);
        try win.begin(impl.nanoTime());

        // only shows the demo if dvui.Examples.show_demo_window is true
        // .full -> .lite or comment out to speed up compile times
        dvui.Examples.demo(.full);

        const endtime = try win.end(.{});
        window.swapBuffers();

        // Should be placed after all rendering and after buffer swap. This is
        // instead of `zglfw.pollEvents`, see comment above.
        impl.pollEventsTimeout(&win, endtime);
    }
}
