const std = @import("std");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");
const gui = @import("src/gui.zig");
const MachGuiBackend = @import("src/MachBackend.zig");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

win: gui.Window,
win_backend: MachGuiBackend,

pub const App = @This();

pub fn init(app: *App, engine: *mach.Core) !void {
    app.win_backend = try MachGuiBackend.init(engine);
    app.win = gui.Window.init(gpa, app.win_backend.guiBackend());
}

pub fn deinit(app: *App, _: *mach.Core) void {
    app.win.deinit();
    app.win_backend.deinit();
}

pub fn update(app: *App, engine: *mach.Core) !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    var nstime = app.win.beginWait(engine.hasEvent());
    app.win.begin(arena, nstime);

    const quit = app.win_backend.addAllEvents(&app.win);
    if (quit) {
        return engine.setShouldClose(true);
    }

    const shown = gui.examples.demo();
    if (!shown) {
        return engine.setShouldClose(true);
    }

    const end_micros = app.win.end();

    if (app.win.cursorRequestedFloating()) |cursor| {
        app.win_backend.setCursor(cursor);
    } else {
        app.win_backend.setCursor(.bad);
    }

    engine.swap_chain.?.present();

    const wait_event_micros = app.win.wait(end_micros, null);
    app.win_backend.waitEventTimeout(wait_event_micros);
}
