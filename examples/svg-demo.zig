const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SvgBackend"));
}

const zig_icon = @embedFile("zig-favicon.png");

// Customize some behaviours, mostly debug features
pub const svg_render_options = Backend.SvgRenderOptions{
    // .draw_background = dvui.Color.black,
    // .emit_textures = true,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var backend = try Backend.initWindow(.{
        .allocator = allocator,
        .size = .{ .w = 800.0, .h = 600.0 },
    });
    defer backend.deinit();

    // init dvui Window (In that case only prepare the svg backend to dump files)
    var win = try dvui.Window.init(@src(), allocator, backend.backend(), .{});
    defer win.deinit();

    dvui.Examples.show_demo_window = true;
    for (0..2) |_| {
        try win.begin(std.time.nanoTimestamp());
        try dvui.Examples.calculator();
        _ = try win.end(.{});
    }

    for (0..2) |_| {
        try win.begin(std.time.nanoTimestamp());
        try dvui.Examples.styling();
        _ = try win.end(.{});
    }

    for (0..2) |_| {
        try win.begin(std.time.nanoTimestamp());
        try dvui.Examples.plots();
        _ = try win.end(.{});
    }

    for (0..2) |_| {
        try win.begin(std.time.nanoTimestamp());
        try dvui.Examples.demo();
        _ = try win.end(.{});
    }
}

const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");
const dvui = @import("dvui");
