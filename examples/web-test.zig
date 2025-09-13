const std = @import("std");
const dvui = @import("dvui");
const WebBackend = @import("web-backend");
comptime {
    std.debug.assert(@hasDecl(WebBackend, "WebBackend"));
}

var wasm_log_console_buffer: [512]u8 = undefined;
pub var js_console = WebBackend.Console.init(&wasm_log_console_buffer);

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (scope != .default) {
        js_console.writer.print("({s}): ", .{@tagName(scope)}) catch unreachable;
    }
    js_console.writer.print(format, args) catch unreachable;
    js_console.flushAtLevel(message_level);
}

pub const std_options: std.Options = .{
    // Overwrite default log handler
    .logFn = logFn,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var touchPoints: [2]?dvui.Point.Physical = [_]?dvui.Point.Physical{null} ** 2;
var orig_content_scale: f32 = 1.0;

const zig_favicon = @embedFile("src/zig-favicon.png");

export fn dvui_init(platform_ptr: [*]const u8, platform_len: usize) i32 {
    const platform = platform_ptr[0..platform_len];
    dvui.log.debug("platform: {s}", .{platform});
    const mac = if (std.mem.indexOf(u8, platform, "Mac") != null) true else false;

    WebBackend.back = WebBackend.init() catch {
        return 1;
    };
    WebBackend.win = dvui.Window.init(@src(), gpa, WebBackend.back.backend(), .{ .keybinds = if (mac) .mac else .windows }) catch {
        return 2;
    };

    WebBackend.win_ok = true;

    orig_content_scale = WebBackend.win.content_scale;

    return 0;
}

export fn dvui_deinit() void {
    WebBackend.win.deinit();
    WebBackend.back.deinit();
}

// return number of micros to wait (interrupted by events) for next frame
// return -1 to quit
export fn dvui_update() i32 {
    return update() catch |err| {
        std.log.err("{any}", .{err});
        const msg = std.fmt.allocPrint(gpa, "{any}", .{err}) catch "allocPrint OOM";
        WebBackend.wasm.wasm_panic(msg.ptr, msg.len);
        return -1;
    };
}

fn update() !i32 {
    const nstime = WebBackend.win.beginWait(WebBackend.back.hasEvent());

    try WebBackend.win.begin(nstime);

    // Instead of the backend saving the events and then calling this, the web
    // backend is directly sending the events to dvui
    //try backend.addAllEvents(&win);

    try dvui_frame();
    //try dvui.label(@src(), "test", .{}, .{ .color_text = .{ .color = dvui.Color.white } });

    //var indices: []const u32 = &[_]u32{ 0, 1, 2, 0, 2, 3 };
    //var vtx: []const dvui.Vertex = &[_]dvui.Vertex{
    //    .{ .pos = .{ .x = 100, .y = 150 }, .uv = .{ 0.0, 0.0 }, .col = .{} },
    //    .{ .pos = .{ .x = 200, .y = 150 }, .uv = .{ 1.0, 0.0 }, .col = .{ .g = 0, .b = 0, .a = 200 } },
    //    .{ .pos = .{ .x = 200, .y = 250 }, .uv = .{ 1.0, 1.0 }, .col = .{ .r = 0, .b = 0, .a = 100 } },
    //    .{ .pos = .{ .x = 100, .y = 250 }, .uv = .{ 0.0, 1.0 }, .col = .{ .r = 0, .g = 0 } },
    //};
    //backend.drawClippedTriangles(null, vtx, indices);

    const end_micros = try WebBackend.win.end(.{});

    WebBackend.back.setCursor(WebBackend.win.cursorRequested());
    WebBackend.back.textInputRect(WebBackend.win.textInputRequested());

    const wait_event_micros = WebBackend.win.waitTime(end_micros);
    return @intCast(@divTrunc(wait_event_micros, 1000));
}

fn dvui_frame() !void {
    var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
    scaler.deinit();

    {
        var m = dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                m.close();
            }
        }

        if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui in a web canvas.";
    tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- example menu at the top of the window
        \\- rest of the window is a scroll area
    , .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.", .{});
    tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.addText("\n\n", .{});
    tl2.format("Scale: {d:0.2} (try pinch-zoom)", .{dvui.windowNaturalScale()}, .{});
    tl2.deinit();

    if (dvui.button(@src(), "Reset Scale", .{}, .{})) {
        dvui.currentWindow().content_scale = orig_content_scale;
    }

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    dvui.Examples.demo();
}
