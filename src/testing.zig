allocator: std.mem.Allocator,
backend: *Backend,
runner: *Runner,
window: *Window,

pub fn init(allocator: std.mem.Allocator, frameFn: *const fn () anyerror!void, window_size: dvui.Size) !Self {
    if (Backend.kind != .sdl) {
        @compileError("dvui.testing can only be used with the SDL backend");
    }

    // init SDL backend (creates and owns OS window)
    const backend = try allocator.create(Backend);
    backend.* = try Backend.initWindow(.{
        .allocator = allocator,
        .size = window_size,
        .vsync = false,
        .title = "",
    });

    const window = try allocator.create(Window);
    window.* = try dvui.Window.init(@src(), allocator, backend.backend(), .{});
    const runner = try allocator.create(Runner);
    runner.* = dvui.Runner.init(window, backend, frameFn);

    return .{
        .allocator = allocator,
        .backend = backend,
        .runner = runner,
        .window = window,
    };
}

pub fn deinit(self: *Self) void {
    self.runner.deinit();
    self.window.deinit();
    self.backend.deinit();
    self.allocator.destroy(self.runner);
    self.allocator.destroy(self.window);
    self.allocator.destroy(self.backend);
}

pub fn expectFocused(self: *Self, test_id: []const u8, id_extra: ?u32) !void {
    const info = try self.runner.getWidgetInfo(test_id, id_extra);
    try std.testing.expectEqual(self.window.last_focused_id_this_frame, info.wd.id);
}

const Self = @This();

const std = @import("std");
const dvui = @import("dvui.zig");

const Backend = dvui.backend;
const Runner = dvui.Runner;
const Window = dvui.Window;
