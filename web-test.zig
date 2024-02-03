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
    return update() catch |err| {
        std.log.err("{!}", .{err});
        var msg = std.fmt.allocPrint(gpa, "{!}", .{err}) catch "allocPrint OOM";
        WebBackend.wasm.wasm_panic(msg.ptr, msg.len);
        return -1;
    };
}

fn update() !i32 {
    // beginWait is not necessary, but cooperates with waitTime to properly
    // wait for timers/animations.
    var nstime = win.beginWait(backend.hasEvent());

    try win.begin(nstime);
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

    //// set cursor only if it is above our demo window
    //if (app.win.cursorRequestedFloating()) |cursor| {
    //    app.win_backend.setCursor(cursor);
    //} else {
    //    app.win_backend.setCursor(.bad);
    //}

    const wait_event_micros = win.waitTime(end_micros, null);
    return @intCast(@divTrunc(wait_event_micros, 1000));
}
