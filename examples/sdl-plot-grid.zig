const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
const CellStyle = dvui.GridWidget.CellStyle;
comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
var scale_val: f32 = 1.0;

var g_backend: ?Backend = null;
var g_win: ?*dvui.Window = null;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        _ = winapi.AttachConsole(0xFFFFFFFF);
    }
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    // TEMP disable
    // defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

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
    //backend.log_events = true;

    _ = Backend.c.SDL_EnableScreenSaver();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    var interrupted = false;
    initData() catch {};

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
        try gui_frame();

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

fn initData() !void {
    try pirate_data.append(gpa, .{ .year = 0, .pirates = 500, .temperature = -1 });
    try pirate_data.append(gpa, .{ .year = 1000, .pirates = 5000, .temperature = 0 });
    try pirate_data.append(gpa, .{ .year = 2000, .pirates = 500_000, .temperature = 2 });
    try pirate_data.append(gpa, .{ .year = 2020, .pirates = 1_000_000, .temperature = 5 });
}

// both dvui and SDL drawing
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
    }

    var main_box = dvui.box(@src(), .horizontal, .{ .expand = .both, .color_fill = .fill_window, .background = true });
    defer main_box.deinit();
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
        defer vbox.deinit();
        {
            var grid = dvui.grid(@src(), .numCols(3), .{}, .{});
            defer grid.deinit();

            const style_base = CellStyle{ .opts = .{ .tab_index = 0, .expand = .horizontal } };
            const focus_cell = grid.cellCursor();
            std.debug.print("focus cell = {}\n", .{focus_cell});
            const style: CellStyleNav = .{ .base = style_base, .focus_col = focus_cell.col_num, .focus_row = focus_cell.row_num };

            dvui.gridHeading(@src(), grid, 0, "Year", .fixed, .{});
            dvui.gridHeading(@src(), grid, 1, "Temperature", .fixed, .{});
            dvui.gridHeading(@src(), grid, 2, "Num Pirates", .fixed, .{});

            for (pirate_data.items(.year), pirate_data.items(.temperature), pirate_data.items(.pirates), 0..) |*year, *temp, *pirates, row_num| {
                var col_num: usize = 0;
                {
                    defer col_num += 1;
                    var cell = grid.bodyCell(@src(), col_num, row_num, style.cellOptions(col_num, row_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = year, .min = -9999, .max = 9999 }, style.options(col_num, row_num));
                }
                {
                    defer col_num += 1;
                    var cell = grid.bodyCell(@src(), col_num, row_num, style.cellOptions(col_num, row_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = temp, .min = -10, .max = 10 }, style.options(col_num, row_num));
                }
                {
                    defer col_num += 1;
                    var cell = grid.bodyCell(@src(), col_num, row_num, style.cellOptions(col_num, row_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = pirates, .min = 0, .max = 10_000_000_000 }, style.options(col_num, row_num));
                }
            }
            if (dvui.tagGet("grid_focus_next")) |focus_widget| {
                std.debug.print("got tag\n", .{});
                dvui.focusWidget(focus_widget.id, null, null);
            }
        }
    }
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
        defer vbox.deinit();
        dvui.plotXY(
            @src(),
            .{ .title = "Pirates vs Global Temperature" },
            5,
            pirate_data.items(.year),
            pirate_data.items(.temperature),
            .{ .expand = .both },
        );
    }
}

const CellStyleNav = struct {
    base: CellStyle,
    focus_col: usize,
    focus_row: usize,

    pub fn cellOptions(self: *const CellStyleNav, col_num: usize, row_num: usize) dvui.GridWidget.CellOptions {
        return self.base.cellOptions(col_num, row_num);
    }

    pub fn options(self: *const CellStyleNav, col_num: usize, row_num: usize) dvui.Options {
        if (row_num == self.focus_row and col_num == self.focus_col) {
            return self.base.options(col_num, row_num).override(.{ .tag = "grid_focus_next" });
        }
        return self.base.options(col_num, row_num);
    }
};

const PirateDatum = struct { year: f64, temperature: f64, pirates: f64 };

var pirate_data: std.MultiArrayList(PirateDatum) = .empty;
