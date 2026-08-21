const std = @import("std");
const dvui = @import("dvui");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 400.0, .h = 700.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI iOS Example",
        },
    },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};
pub const main = dvui.App.main;

// NOTE: this is a static lib (like the Android example), so zig's start.zig never runs and
// never builds the std.process.Init dvui.App.main needs. Xcode's main.c has the real C main()
// and calls this exported symbol; hand-build the same minimal Init here.
export fn dvui_main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    return runDvuiMain(argc, argv) catch |err| {
        std.log.err("dvui_main failed: {t}", .{err});
        return 1;
    };
}

extern "c" var environ: ?[*:null]?[*:0]u8;

fn runDvuiMain(argc: c_int, argv: [*][*:0]u8) !u8 {
    const gpa = std.heap.c_allocator;

    var arena_allocator: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_allocator.deinit();

    const args_vector: std.process.Args.Vector = argv[0..@intCast(argc)];
    const environ_block: std.process.Environ.Block = .{ .slice = std.mem.span(environ orelse @as([*:null]?[*:0]u8, @ptrFromInt(@alignOf(?[*:0]u8)))) };

    var threaded: std.Io.Threaded = .init(gpa, .{
        .argv0 = .init(.{ .vector = args_vector }),
        .environ = .{ .block = environ_block },
    });
    defer threaded.deinit();

    var environ_map = try std.process.Environ.createMap(.{ .block = environ_block }, gpa);
    defer environ_map.deinit();

    const preopens = try std.process.Preopens.init(arena_allocator.allocator());

    return dvui.App.main(.{
        .minimal = .{ .args = .{ .vector = args_vector }, .environ = .{ .block = environ_block } },
        .arena = &arena_allocator,
        .gpa = gpa,
        .io = threaded.io(),
        .environ_map = &environ_map,
        .preopens = preopens,
    });
}

pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

pub fn appInit(win: *dvui.Window) !void {
    _ = win;
    dvui.Examples.show_demo_window = true;
}

pub fn appDeinit(win: *dvui.Window) void {
    _ = win;
}

pub fn appFrame() !dvui.App.Result {
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window, .background = true });
    defer scroll.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    // NOTE: hardcoded top margin clears the status bar / Dynamic Island (dvui has no
    // safe-area API yet; switch to SDL_GetWindowSafeArea once the backend exposes it).
    if (dvui.button(@src(), label, .{}, .{ .margin = .{ .x = 0, .y = 50, .w = 0, .h = 0 } })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    dvui.Examples.demo(.full);

    return .ok;
}
