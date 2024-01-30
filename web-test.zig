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

        (LogWriter{ .context = {} }).print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;

        WebBackend.wasm.wasm_log_flush();
    }
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var win: dvui.Window = undefined;
var backend: WebBackend = undefined;

const zig_favicon = @embedFile("src/zig-favicon.png");

export fn app_init() i32 {
    std.log.debug("hello\n", .{});
    backend = WebBackend.init() catch {
        return 1;
    };
    std.log.debug("hello1\n", .{});
    win = dvui.Window.init(@src(), 0, gpa, backend.backend()) catch {
        return 2;
    };

    return 0;
}

export fn app_deinit() void {
    //win.deinit();
    backend.deinit();
}

export fn app_update() void {
    std.log.debug("app_update\n", .{});
    win.begin(1) catch unreachable;

    const imgsize = dvui.imageSize("zig favicon", zig_favicon) catch unreachable;
    std.log.debug("imgsize {}\n", .{imgsize});

    const tce = dvui.imageTexture("zig favicon", zig_favicon) catch unreachable;
    std.log.debug("texture {}\n", .{tce.texture});

    var indices: []const u32 = &[_]u32{ 0, 1, 2, 0, 2, 3 };

    var vtx: []const dvui.Vertex = &[_]dvui.Vertex{
        .{ .pos = .{ .x = 100, .y = 150 }, .uv = .{ 0.0, 0.0 }, .col = .{} },
        .{ .pos = .{ .x = 200, .y = 150 }, .uv = .{ 1.0, 0.0 }, .col = .{ .g = 0, .b = 0, .a = 200 } },
        .{ .pos = .{ .x = 200, .y = 250 }, .uv = .{ 1.0, 1.0 }, .col = .{ .r = 0, .b = 0, .a = 100 } },
        .{ .pos = .{ .x = 100, .y = 250 }, .uv = .{ 0.0, 1.0 }, .col = .{ .r = 0, .g = 0 } },
    };

    backend.renderGeometry(tce.texture, vtx, indices);
    //backend.renderGeometry(null, vtx, indices);

    //var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //const arena = arena_allocator.allocator();
    //defer arena_allocator.deinit();

    //// beginWait is not necessary, but cooperates with waitTime to properly
    //// wait for timers/animations.
    //var nstime = app.win.beginWait(engine.hasEvent());

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
