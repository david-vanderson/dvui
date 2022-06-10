const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");
const gui = @import("src/gui.zig");
const Backend = @import("src/MachBackend.zig");


var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

win: gui.Window,
backend: Backend,

const App = @This();

pub fn init(app: *App, engine: *mach.Engine) !void {
    app.backend = try Backend.init(gpa, engine);
    app.win = gui.Window.init(gpa, app.backend.guiBackend());
}

pub fn deinit(app: *App, _: *mach.Engine) void {
    app.backend.deinit();
}

pub fn update(app: *App, engine: *mach.Engine) !void {

    //std.debug.print("UPDATE\n", .{});
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    const size = engine.getWindowSize();
    const psize = engine.getFramebufferSize();
    var nstime = app.win.beginWait(engine.hasEvent());
    app.win.begin(arena, nstime,
        gui.Size{.w = @intToFloat(f32, size.width), .h = @intToFloat(f32, size.height)},
        gui.Size{.w = @intToFloat(f32, psize.width), .h = @intToFloat(f32, psize.height)},
    );

    const quit = app.backend.pumpEvents(&app.win);
    if (quit) {
      return engine.setShouldClose(true);
    }

    app.win.endEvents();

    gui.demo();

    const end_micros = app.win.end();

    //if (app.win.CursorRequested()) |cursor| {
    //  backend.setCursor(cursor);
    //}

    app.backend.renderPresent();

    const wait_event_micros = app.win.wait(end_micros, null);
    if (wait_event_micros == std.math.maxInt(u32)) {
      app.backend.engine.setWaitEvent(std.math.floatMax(f64));
    }
    else {
      app.backend.engine.setWaitEvent(@intToFloat(f64, wait_event_micros) / 1_000_000);
    }
}


