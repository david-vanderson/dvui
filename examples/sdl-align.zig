const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
const show_demo = true;
var scale_val: f32 = 1.0;

var show_dialog_outside_frame: bool = false;
var g_backend: ?Backend = null;
var g_win: ?*dvui.Window = null;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    dvui.Examples.show_demo_window = show_demo;

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    g_backend = backend;
    defer backend.deinit();

    _ = Backend.c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    var interrupted = false;

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        // The demos we pass in here show up under "Platform-specific demos"
        gui_frame();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        try backend.setCursor(win.cursorRequested());
        try backend.textInputRect(win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        interrupted = try backend.waitEventTimeout(wait_event_micros);
    }
}

// both dvui and SDL drawing
fn gui_frame() void {
    //dvui.currentWindow().debug_window_show = true;
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
    }
    var vbox = dvui.box(@src(), .vertical, .{ .color_fill = .fill_window, .background = true, .expand = .both });
    defer vbox.deinit();
    var al2 = dvui.Alignment.init(@src(), 0);
    defer al2.deinit();
    var al = dvui.Alignment.init(@src(), 0);
    defer al.deinit();
    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hbox.deinit();
        dvui.labelNoFmt(@src(), "Sm", .{}, .{});
        al.spacer(@src(), 0);
        var hb2 = dvui.box(@src(), .horizontal, .{});
        defer hb2.deinit();
        _ = dvui.button(@src(), "Medium", .{}, .{});
        al2.spacer(@src(), 0);
        dvui.labelNoFmt(@src(), "Large...................", .{}, .{});
    }
    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hbox.deinit();
        dvui.labelNoFmt(@src(), "Medium", .{}, .{});
        al.spacer(@src(), 0);
        var hb2 = dvui.box(@src(), .horizontal, .{});
        defer hb2.deinit();
        _ = dvui.button(@src(), "Large...................", .{}, .{});
        al2.spacer(@src(), 0);
        dvui.labelNoFmt(@src(), "Sm", .{}, .{});
    }
    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hbox.deinit();
        dvui.labelNoFmt(@src(), "Large...................", .{}, .{});
        al.spacer(@src(), 0);
        var hb2 = dvui.box(@src(), .horizontal, .{});
        defer hb2.deinit();
        _ = dvui.button(@src(), "Sm", .{}, .{});
        al2.spacer(@src(), 0);
        dvui.labelNoFmt(@src(), "Medium", .{}, .{});
    }
}

pub fn defaultValue(T: type) ?T {
    return switch (@typeInfo(T)) {
        inline .bool => false,
        inline .int => 0,
        inline .float => 0.0,
        inline .@"struct" => return .{}, // If you see an error here, it is because your struct requires initialization.
        inline .@"enum" => |e| e.fields[0],
        inline else => null,
    };
}
