const std = @import("std");
const dvui = @import("dvui");
const Backend = dvui.backend;
const win32 = Backend.win32;

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const ExtraWindow = struct {
    state: *Backend.WindowState,
    backend: Backend.Context,
    fn deinit(self: ExtraWindow) void {
        self.backend.deinit();
        gpa.destroy(self.state);
    }
};
var extra_windows: std.ArrayListUnmanaged(ExtraWindow) = .{};

const vsync = true;

var show_dialog_outside_frame: bool = false;

const window_class = win32.L("DvuiStandaloneWindow");

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    defer _ = gpa_instance.deinit();

    Backend.RegisterClass(window_class, .{}) catch win32.panicWin32(
        "RegisterClass",
        win32.GetLastError(),
    );

    var window_state: Backend.WindowState = undefined;

    // init dx11 backend (creates and owns OS window)
    const first_backend = try Backend.initWindow(&window_state, .{
        .registered_class = window_class,
        .dvui_gpa = gpa,
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI DX11 Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    defer first_backend.deinit();

    defer {
        for (extra_windows.items) |window| {
            window.deinit();
        }
        extra_windows.deinit(gpa);
    }

    const win = first_backend.getWindow();
    while (true) switch (Backend.serviceMessageQueue()) {
        .queue_empty => {
            // beginWait coordinates with waitTime below to run frames only when needed
            const nstime = win.beginWait(first_backend.hasEvent());

            // marks the beginning of a frame for dvui, can call dvui functions after this
            try win.begin(nstime);

            // both dvui and dx11 drawing
            try gui_frame();

            // marks end of dvui frame, don't call dvui functions after this
            // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
            _ = try win.end(.{});

            for (extra_windows.items) |window| {
                try window.backend.getWindow().begin(nstime);
                try gui_frame();
                _ = try window.backend.getWindow().end(.{});
            }

            // cursor management
            first_backend.setCursor(win.cursorRequested());

            // Example of how to show a dialog from another thread (outside of win.begin/win.end)
            if (show_dialog_outside_frame) {
                show_dialog_outside_frame = false;
                dvui.dialog(@src(), .{}, .{ .window = win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
            }
        },
        .quit => break,
        .close_windows => {
            if (first_backend.receivedClose())
                break;
            extras: while (true) {
                const index: usize = blk: {
                    for (extra_windows.items, 0..) |window, i| {
                        if (window.backend.receivedClose()) break :blk i;
                    }
                    break :extras;
                };
                const window = extra_windows.swapRemove(index);
                window.deinit();
            }
        },
    };
}

fn gui_frame() !void {
    {
        var m = dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                m.close();
            }
        }

        if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .fill_window });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui in a normal application.";
    tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- example menu at the top of the window
        \\- rest of the window is a scroll area
    , .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    tl2.addText("\n\n", .{});
    if (vsync) {
        tl2.addText("Framerate is capped by vsync.", .{});
    } else {
        tl2.addText("Framerate is uncapped.", .{});
    }
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.", .{});
    tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    {
        dvui.labelNoFmt(@src(), "These are drawn directly by the backend, not going through DVUI.", .{}, .{ .margin = .{ .x = 4 } });

        var box = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 }, .background = true, .margin = .{ .x = 8, .w = 8 } });
        defer box.deinit();

        // Here is some arbitrary drawing that doesn't have to go through DVUI.
        // It can be interleaved with DVUI drawing.
        // NOTE: This only works in the main window (not floating subwindows
        // like dialogs).
    }

    if (dvui.button(@src(), "Show Dialog From\nOutside Frame", .{}, .{})) {
        show_dialog_outside_frame = true;
    }

    if (dvui.button(@src(), "Spawn Another OS window", .{}, .{})) {
        try extra_windows.ensureUnusedCapacity(gpa, 1);
        const state = try gpa.create(Backend.WindowState);
        errdefer gpa.destroy(state);
        const backend = try Backend.initWindow(state, .{
            .registered_class = window_class,
            .dvui_gpa = gpa,
            .allocator = gpa,
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .vsync = vsync,
            .title = "DVUI DX11 Standalone Example",
            .icon = window_icon_png, // can also call setIconFromFileContent()
        });
        extra_windows.appendAssumeCapacity(.{
            .state = state,
            .backend = backend,
        });
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    dvui.Examples.demo();
}
