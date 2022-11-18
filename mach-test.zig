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

    // beginWait is not necessary, but cooperates with waitTime to properly
    // wait for timers/animations.
    var nstime = app.win.beginWait(engine.hasEvent());

    // start gui, can call gui stuff after this
    try app.win.begin(arena, nstime);

    // add all the events, could also add one by one
    const quit = try app.win_backend.addAllEvents(&app.win);
    if (quit) {
        return engine.close();
    }

    const shown = try gui.examples.demo();
    if (!shown) {
        return engine.close();
    }

    // end gui, render retained dialogs, deferred rendering (floating windows, focus highlights)
    const end_micros = try app.win.end();

    // set cursor only if it is above our demo window
    if (app.win.cursorRequestedFloating()) |cursor| {
        app.win_backend.setCursor(cursor);
    } else {
        app.win_backend.setCursor(.bad);
    }

    engine.swap_chain.?.present();

    // wait for events/timers/animations
    const wait_event_micros = app.win.waitTime(end_micros, null);
    app.win_backend.waitEventTimeout(wait_event_micros);
}
