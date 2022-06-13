const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");
const gui = @import("src/gui.zig");
const Backend = @import("src/MachBackend.zig");


var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

win: gui.Window,
gui_backend: Backend,

const App = @This();

pub fn init(app: *App, engine: *mach.Engine) !void {
    app.gui_backend = try Backend.init(gpa, engine);
    app.win = gui.Window.init(gpa, app.gui_backend.guiBackend());
}

pub fn deinit(app: *App, _: *mach.Engine) void {
    app.gui_backend.deinit();
}

pub fn update(app: *App, engine: *mach.Engine) !void {

    //std.debug.print("UPDATE\n", .{});
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    var nstime = app.win.beginWait(engine.hasEvent());
    app.win.begin(arena, nstime);

    const quit = app.gui_backend.addAllEvents(&app.win);
    if (quit) {
      return engine.setShouldClose(true);
    }

    gui.demo();

    const end_micros = app.win.end();

    //if (app.win.CursorRequested()) |cursor| {
    //  gui_backend.setCursor(cursor);
    //}

    engine.swap_chain.?.present();

    const wait_event_micros = app.win.wait(end_micros, null);
    app.gui_backend.waitEventTimeout(wait_event_micros);
}


