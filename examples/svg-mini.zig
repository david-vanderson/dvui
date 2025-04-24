const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SvgBackend"));
}

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const zig_icon = @embedFile("zig-favicon.png");

pub fn main() !void {
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
    });
    defer backend.deinit();

    // init dvui Window (In that case only prepare the svg backend to dump files)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    dvui.Examples.show_demo_window = true;
    for (0..5) |_| {
        try win.begin(0);

        try dvui.Examples.styling();

        _ = try win.end(.{});
    }
}

const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");
const dvui = @import("dvui");
