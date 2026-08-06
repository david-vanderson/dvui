const std = @import("std");
const dvui = @import("dvui");
const PuglBackend = @import("pugl-backend");
const pugl = PuglBackend.pugl;

comptime {
    std.debug.assert(@hasDecl(PuglBackend, "pugl"));
}

const State = struct {
    backend: *PuglBackend,
    window: *dvui.Window,
    io: std.Io,
    run: bool = true,
    scale: f32 = 1,
    end_us: ?u32 = 0,
    wait_us: u32 = 0,

    pub fn guiFrame(self: *State) bool {
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal, .name = "main" });
            defer hbox.deinit();

            var m = dvui.menu(@src(), .horizontal, .{});
            defer m.deinit();

            if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();

                if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                    m.close();
                }

                if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                    return false;
                }
            }
        }

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
        tl.addText("This example shows how to use dvui with the pugl backend in a normal application.", .{});
        tl.deinit();

        const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
        if (dvui.button(@src(), label, .{}, .{})) {
            dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
        }

        if (dvui.button(@src(), "Debug Window", .{}, .{})) {
            dvui.toggleDebugWindow();
        }

        {
            var scaler = dvui.scale(@src(), .{ .scale = &self.scale }, .{ .expand = .horizontal });
            defer scaler.deinit();

            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            if (dvui.button(@src(), "Zoom In", .{}, .{})) {
                self.scale = @round(dvui.themeGet().font_body.size * self.scale + 1.0) / dvui.themeGet().font_body.size;
            }

            if (dvui.button(@src(), "Zoom Out", .{}, .{})) {
                self.scale = @round(dvui.themeGet().font_body.size * self.scale - 1.0) / dvui.themeGet().font_body.size;
            }
        }

        // only shows the demo if dvui.Examples.show_demo_window is true
        dvui.Examples.demo(.full);

        return true;
    }
};

pub fn main(init: std.process.Init) !void {
    dvui.Examples.show_demo_window = true;

    const world = try pugl.World.init(.program, .{});
    defer world.deinit();

    const view = try pugl.View.init(&world);
    defer view.deinit();

    try view.setSizeHint(.default, .{ .width = 800, .height = 600 });
    try view.setStringHint(.window_title, "DVUI pugl example");
    try view.setBoolHint(.resizable, true);

    try view.setEventFunc(onEvent);

    var state: State = .{
        .backend = undefined,
        .window = undefined,
        .io = init.io,
    };

    view.setHandle(&state);

    var backend = try PuglBackend.init(.{
        .io = init.io,
        .gpa = init.gpa,
        .view = view,
    });
    defer backend.deinit();
    state.backend = &backend;

    var window = try dvui.Window.init(@src(), init.gpa, backend.backend(), .{});
    defer window.deinit();
    state.window = &window;

    try view.show(.raise);

    while (state.run) {
        state.backend.waitEventTimeout(state.wait_us);
        state.wait_us = state.window.waitTime(state.end_us);
    }
}

fn onEvent(view: *const pugl.View, event: pugl.event.Event) pugl.Error!void {
    const state: *State = @ptrCast(@alignCast(view.getHandle()));
    try state.backend.handleEvent(event, state.window);

    switch (event) {
        .expose => {
            const nstime = state.window.beginWait(true);
            state.window.begin(nstime) catch return error.BackendFailed;

            state.backend.renderer.clear();
            if (!state.guiFrame()) {
                state.run = false;
                return;
            }

            state.end_us = state.window.end(.{}) catch return error.BackendFailed;
        },
        .update => if (state.end_us != null) try view.obscure(),
        .close => state.run = false,
        .configure, .realize, .unrealize => {},
        else => try view.obscure(),
    }
}
