const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SvgBackend"));
}

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const zig_icon = @embedFile("zig-favicon.png");

const my_colors = struct {
    pub const red = dvui.Color{ .r = 0xff, .g = 0x00, .b = 0x00 };
    pub const green = dvui.Color{ .r = 0x00, .g = 0xff, .b = 0x00 };
    pub const blue = dvui.Color{ .r = 0x00, .g = 0x00, .b = 0xff };
    pub const yellow = dvui.Color{ .r = 0xff, .g = 0xff, .b = 0x00 };
    pub const cyan = dvui.Color{ .r = 0x00, .g = 0xff, .b = 0xff };
    pub const magenta = dvui.Color{ .r = 0xff, .g = 0x00, .b = 0xff };
};

pub fn main() !void {
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
    });
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    dvui.Examples.show_demo_window = true;
    for (0..5) |_| {
        try win.begin(0);

        const b = try dvui.box(@src(), .vertical, .{});
        // try dvui.Examples.basicWidgets(0);
        // const r = dvui.Rect{ .x = 80, .y = 40, .h = 350, .w = 500 };
        // try r.stroke(dvui.Rect.all(10), 42, my_colors.cyan, .{});
        // const r2 = dvui.Rect{ .x = 180, .y = 240, .h = 250, .w = 300 };
        // try r2.stroke(dvui.Rect.all(10), 42, my_colors.blue, .{});
        const s = try dvui.scale(@src(), 4.5, .{});
        if (try dvui.button(@src(), "my\n button", .{}, .{ .color_text = .{ .name = .accent } })) {
            // code of button
        }
        s.deinit();
        _ = try dvui.image(@src(), .{ .name = "zig", .bytes = zig_icon }, .{ .margin = dvui.Rect.all(50), .border = dvui.Rect{ .x = 10, .y = 20, .h = 30, .w = 30 } });
        b.deinit();
        _ = try win.end(.{});
    }
}

const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");
const dvui = @import("dvui");
