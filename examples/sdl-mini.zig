const std = @import("std");
const print = std.debug.print;
const builtin = @import("builtin");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

var pnrg = std.Random.DefaultPrng.init(42);

comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

const my_app_data = struct {
    var float1: bool = false;
    var float2: bool = true;
    var float3: bool = false;
    var color: dvui.Color = .red;
};

var scale_val: f32 = 3.0;

var g_backend: ?*SDLBackend = null;
var g_win: ?*dvui.Window = null;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main(init: std.process.Init) !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    SDLBackend.enableSDLLogging();
    std.log.info("SDL version: {f}", .{SDLBackend.getSDLVersion()});

    // init SDL backend (creates and owns OS window)
    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .allocator = init.gpa,
        .size = .{ .w = 1300.0, .h = 800.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = true,
        .title = "DVUI SDL dirty playground",
    });
    backend.initial_scale = 1.6;
    // Okaaaay !! here I store a copy otherwise ...
    g_backend = &backend;
    defer backend.deinit();

    _ = SDLBackend.c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{
        // you can set the default theme here in the init options
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
    });
    defer win.deinit();

    var interrupted = false;

    main_loop: while (true) {
        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // for (win.subwindows.stack.items) |subw| {
        //     print("{f}\n", .{subw.id});
        // }
        // print("\n", .{});

        // send all SDL events to dvui for processing
        try backend.addAllEvents(&win);

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = SDLBackend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 0);
        _ = SDLBackend.c.SDL_RenderClear(backend.renderer);

        const keep_running = gui_frame();
        if (!keep_running) break :main_loop;

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);
    }
}

// both dvui and SDL drawing
// return false if user wants to exit the app
fn gui_frame() bool {
    var backend = g_backend orelse return false;
    _ = &backend; // autofix

    {
        const box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer box.deinit();
        if (dvui.button(@src(), "+", .{}, .{})) dvui.currentWindow().content_scale += 0.2;
        if (dvui.button(@src(), "-", .{ .draw_focus = false }, .{})) dvui.currentWindow().content_scale -= 0.2;
    }

    // if (dvui.button(@src(), "Create window", .{}, .{})) {
    //     backend.createExtraWindow() catch return false;
    // }
    if (dvui.button(@src(), "Change Color", .{}, .{})) {
        my_app_data.color.r = pnrg.random().int(u8);
        my_app_data.color.g = pnrg.random().int(u8);
        my_app_data.color.b = pnrg.random().int(u8);
    }
    // if (dvui.button(@src(), "Destroy window", .{}, .{})) {
    //     backend.destroyExtraWindow() catch return false;
    // }

    colorBox();

    if (dvui.button(@src(), "My test for dedicated OS Window", .{}, .{})) {
        my_app_data.float1 = !my_app_data.float1;
        // std.debug.print("my test button clicked, float1 visible ? {}\n", .{my_app_data.float1});
    }
    if (dvui.button(@src(), "My second test", .{}, .{})) {
        my_app_data.float2 = !my_app_data.float2;
    }
    if (my_app_data.float1) {
        var float = dvui.floatingWindow(
            @src(),
            // .{ .open_flag = &my_app_data.float1, .modal = false },
            .{ .dedicated_os_win = true },
            .{
                .min_size_content = .{ .w = 600, .h = 400 },
                .max_size_content = .width(800),
            },
        );
        defer float.deinit();

        _ = dvui.windowHeader("my win header", "", &my_app_data.float1);
        dvui.Examples.plots();
    }

    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    // check for quitting
    for (dvui.events()) |*e| {
        // assume we only have a single window
        if (e.evt == .window and e.evt.window.action == .close) return false;
        if (e.evt == .app and e.evt.app.action == .quit) return false;
    }
    a_second_float_win();

    return true;
}

fn a_second_float_win() void {
    if (my_app_data.float2) {
        var float = dvui.floatingWindow(
            @src(),
            .{},
            .{},
        );
        defer float.deinit();
        dvui.label(@src(), "No header in this window", .{}, .{});
        {
            const box = dvui.box(@src(), .{}, .{});
            defer box.deinit();

            _ = dvui.button(@src(), "test", .{}, .{});
            if (dvui.button(@src(), "test", .{}, .{})) {
                my_app_data.float3 = !my_app_data.float3;
            }
            if (my_app_data.float3) {
                var sub_float = dvui.floatingWindow(@src(), .{}, .{});
                sub_float.deinit();
                dvui.Examples.dialogDirect();
            }
        }
    }
}

fn colorBox() void {
    const backend = g_backend orelse unreachable;
    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 }, .background = true, .margin = .{ .x = 8, .w = 8 } });
    defer box.deinit();
    // get the screen rectangle for the box
    const rs = box.data().contentRectScale();
    var rect: SDLBackend.c.SDL_FRect = .{
        .x = (rs.r.x + 4 * rs.s),
        .y = (rs.r.y + 4 * rs.s),
        .w = (20 * rs.s),
        .h = (20 * rs.s),
    };
    _ = SDLBackend.c.SDL_SetRenderDrawColor(
        backend.renderer,
        my_app_data.color.r,
        my_app_data.color.g,
        my_app_data.color.b,
        my_app_data.color.a,
    );
    _ = SDLBackend.c.SDL_RenderFillRect(backend.renderer, &rect);

    for (backend.child_os_wins) |os_wins| {
        if (os_wins) |win| {
            var extra_rect: SDLBackend.c.SDL_FRect = .{ .x = 50, .y = 50, .w = 200, .h = 200 };
            _ = SDLBackend.c.SDL_SetRenderDrawColor(
                win.renderer,
                my_app_data.color.r,
                my_app_data.color.g,
                my_app_data.color.b,
                my_app_data.color.a,
            );
            _ = SDLBackend.c.SDL_RenderFillRect(win.renderer, &extra_rect);
        }
    }
}

test {
    try std.testing.expect(true);
}
