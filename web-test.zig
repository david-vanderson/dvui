const std = @import("std");
const dvui = @import("dvui");
const WebBackend = @import("WebBackend");
usingnamespace WebBackend.wasm;

const WriteError = error{};
const LogWriter = std.io.Writer(void, WriteError, writeLog);

fn writeLog(_: void, msg: []const u8) WriteError!usize {
    WebBackend.wasm.wasm_log_write(msg.ptr, msg.len);
    return msg.len;
}

pub const std_options = struct {
    /// Overwrite default log handler
    pub fn logFn(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const level_txt = switch (message_level) {
            .err => "error",
            .warn => "warning",
            .info => "info",
            .debug => "debug",
        };
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
        const msg = level_txt ++ prefix2 ++ format ++ "\n";

        (LogWriter{ .context = {} }).print(msg, args) catch return;
        WebBackend.wasm.wasm_log_flush();
    }
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var win: dvui.Window = undefined;
var backend: WebBackend = undefined;

const zig_favicon = @embedFile("src/zig-favicon.png");

export fn app_init() i32 {
    backend = WebBackend.init() catch {
        return 1;
    };
    win = dvui.Window.init(@src(), 0, gpa, backend.backend()) catch {
        return 2;
    };

    return 0;
}

export fn app_deinit() void {
    //win.deinit();
    backend.deinit();
}

// return number of micros to wait (interrupted by events) for next frame
// return -1 to quit
export fn app_update() i32 {
    update() catch |err| {
        std.log.err("{!}", .{err});
        var msg = std.fmt.allocPrint(gpa, "{!}", .{err}) catch "allocPrint OOM";
        WebBackend.wasm.wasm_panic(msg.ptr, msg.len);
        return -1;
    };

    return 1000000;
}

fn update() !void {
    // beginWait is not necessary, but cooperates with waitTime to properly
    // wait for timers/animations.
    //var nstime = win.beginWait(backend.hasEvent());

    try win.begin(backend.nanoTime());
    backend.clear();

    try backend.addAllEvents(&win);

    _ = try dvui.Examples.demo();

    var box = try dvui.box(@src(), .vertical, .{ .background = true, .color_fill = .{ .color = .{ .b = 0, .g = 0 } } });
    try dvui.label(@src(), "hello", .{}, .{ .gravity_x = 0.5 });

    if (try dvui.button(@src(), "Show Demo Window", .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    var buf: [100]u8 = undefined;
    const fps_str = std.fmt.bufPrint(&buf, "{d:0>4.0} fps", .{dvui.FPS()}) catch unreachable;
    try dvui.label(@src(), "{s}", .{fps_str}, .{ .gravity_x = 0.5 });

    try dvui.label(@src(), "nanoTime {d}", .{dvui.currentWindow().frame_time_ns}, .{ .gravity_x = 0.5 });

    //try dvui.debugFontAtlases(@src(), .{});
    box.deinit();

    const end_micros = try win.end(.{});
    _ = end_micros;

    //const imgsize = dvui.imageSize("zig favicon", zig_favicon) catch unreachable;
    //std.log.debug("imgsize {}\n", .{imgsize});

    //const tce = dvui.imageTexture("zig favicon", zig_favicon) catch unreachable;
    //std.log.debug("texture {}\n", .{tce.texture});

    //var indices: []const u32 = &[_]u32{ 0, 1, 2, 0, 2, 3 };
    //var vtx: []const dvui.Vertex = &[_]dvui.Vertex{
    //    .{ .pos = .{ .x = 100, .y = 150 }, .uv = .{ 0.0, 0.0 }, .col = .{} },
    //    .{ .pos = .{ .x = 200, .y = 150 }, .uv = .{ 1.0, 0.0 }, .col = .{ .g = 0, .b = 0, .a = 200 } },
    //    .{ .pos = .{ .x = 200, .y = 250 }, .uv = .{ 1.0, 1.0 }, .col = .{ .r = 0, .b = 0, .a = 100 } },
    //    .{ .pos = .{ .x = 100, .y = 250 }, .uv = .{ 0.0, 1.0 }, .col = .{ .r = 0, .g = 0 } },
    //};
    //backend.renderGeometry(.texture, vtx, indices);

    //const msize = dvui.themeGet().font_body.textSize("M") catch unreachable;
    //std.log.debug("msize {}\n", .{msize});

    //dvui.renderText(.{
    //    .font = dvui.themeGet().font_body,
    //    .text = "hello",
    //    .rs = .{ .r = .{ .x = 10, .y = 10, .w = 100, .h = 100 }, .s = 1.0 },
    //    .color = dvui.Color.white,
    //}) catch unreachable;

    //dvui.labelNoFmt(@src(), "hello", .{ .background = true }) catch unreachable;
    //backend.renderGeometry(null, vtx, indices);

    //var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //const arena = arena_allocator.allocator();
    //defer arena_allocator.deinit();

    //// start gui, can call gui stuff after this
    //try app.win.begin(arena, nstime);

    //// add all the events, could also add one by one
    //const quit = try app.win_backend.addAllEvents(&app.win);
    //if (quit) {
    //    return engine.close();
    //}

    //const shown = try gui.examples.demo();
    //if (!shown) {
    //    return engine.close();
    //}

    //// end gui, render retained dialogs, deferred rendering (floating windows, focus highlights)
    //const end_micros = try app.win.end();

    //// set cursor only if it is above our demo window
    //if (app.win.cursorRequestedFloating()) |cursor| {
    //    app.win_backend.setCursor(cursor);
    //} else {
    //    app.win_backend.setCursor(.bad);
    //}

    //engine.swap_chain.?.present();

    //// wait for events/timers/animations
    //const wait_event_micros = app.win.waitTime(end_micros, null);
    //app.win_backend.waitEventTimeout(wait_event_micros);
}
