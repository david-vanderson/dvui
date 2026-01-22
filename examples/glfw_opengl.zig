const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("glfw-opengl-backend");
const zglfw = Backend.zglfw;
const zgl = Backend.zgl;

const opengl_error_handling = zgl.ErrorHandling.assert;

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

    zglfw.windowHint(.context_version_major, 4);
    zglfw.windowHint(.context_version_minor, 5);
    zglfw.windowHint(.opengl_profile, .opengl_core_profile);
    zglfw.windowHint(.opengl_forward_compat, true);
    zglfw.windowHint(.client_api, .opengl_api);
    zglfw.windowHint(.doublebuffer, true);
    window = try zglfw.Window.create(640, 480, "Hello World", null);
    zglfw.makeContextCurrent(window);
    zglfw.swapInterval(1);
    const proc: zglfw.GlProc = undefined;
    try zgl.loadExtensions(proc, glGetProcAddress);

    var impl = Backend.init(gpa, window);
    defer impl.deinit();

    const backend = dvui.Backend.init(&impl);
    var win = try dvui.Window.init(@src(), gpa, backend, .{});
    defer win.deinit();

    while (!window.shouldClose()) {
        zgl.clearColor(0.1, 0.4, 0.25, 1.0);
        zgl.clear(.{ .color = true, .stencil = true, .depth = true });
        try win.begin(std.time.nanoTimestamp());
        zglfw.pollEvents();

        dvui.Examples.demo();

        _ = try win.end(.{});
        window.swapBuffers();
    }
}
