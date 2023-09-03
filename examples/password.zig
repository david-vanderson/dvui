const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("SDLBackend");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    // init SDL backend (creates OS window)
    var backend = try Backend.init(.{
        .width = 500,
        .height = 600,
        .vsync = true,
        .title = "password example",
    });
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), 0, allocator, backend.backend());
    defer win.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();

    main_loop: while (true) {
        defer _ = arena_allocator.reset(.free_all);
        // beginWait coordinates with waitTime below to run frames only when needed
        var nstime = win.beginWait(backend.hasEvent());

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(arena, nstime);

        // send all SDL events to dvui for processing
        const q = try backend.addAllEvents(&win);
        if (q) break :main_loop;

        try password_prompt();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        backend.setCursor(win.cursorRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);
    }
}

fn password_prompt() !void {
    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_style = .window });
    defer scroll.deinit();

    const S = struct {
        var password: [128]u8 = std.mem.zeroes([128]u8);
        var len: usize = 0;
    };
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        try dvui.label(@src(), "Enter Password:", .{}, .{ .gravity_y = 0.5 });
        var te = try dvui.textEntry(@src(), .{
            .text = &S.password,
            .scroll_vertical = false,
            .scroll_horizontal_bar = .hide,
        }, .{});
        S.len = te.len;
        te.deinit();

        //if (try dvui.buttonIcon(
        //    @src(),
        //    12,
        //    "toggle",
        //    if (S.obfuscate) dvui.icons.entypo.eye_with_line else dvui.icons.entypo.eye,
        //    .{},
        //)) {
        //    S.obfuscate = !S.obfuscate;
        //}
    }

    if (try dvui.button(@src(), "Sign In", .{ .color_style = .success })) {}
}
