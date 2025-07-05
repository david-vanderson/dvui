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
        .size = .{ .w = 1024.0, .h = 600.0 },
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
    try pirate_data.append(gpa, .{ .year = 1700, .pirates = 987232, .temperature = -1.02 });
    try pirate_data.append(gpa, .{ .year = 1708, .pirates = 939021, .temperature = -0.99 });
    try pirate_data.append(gpa, .{ .year = 1716, .pirates = 902102, .temperature = -0.87 });
    try pirate_data.append(gpa, .{ .year = 1724, .pirates = 854001, .temperature = -0.75 });
    try pirate_data.append(gpa, .{ .year = 1732, .pirates = 801234, .temperature = -0.63 });
    try pirate_data.append(gpa, .{ .year = 1740, .pirates = 756789, .temperature = -0.51 });
    try pirate_data.append(gpa, .{ .year = 1748, .pirates = 712345, .temperature = -0.39 });
    try pirate_data.append(gpa, .{ .year = 1756, .pirates = 667890, .temperature = -0.27 });
    try pirate_data.append(gpa, .{ .year = 1764, .pirates = 623456, .temperature = -0.15 });
    try pirate_data.append(gpa, .{ .year = 1772, .pirates = 578901, .temperature = -0.03 });
    try pirate_data.append(gpa, .{ .year = 1780, .pirates = 534567, .temperature = 0.09 });
    try pirate_data.append(gpa, .{ .year = 1788, .pirates = 490123, .temperature = 0.21 });
    try pirate_data.append(gpa, .{ .year = 1796, .pirates = 445678, .temperature = 0.33 });
    try pirate_data.append(gpa, .{ .year = 1804, .pirates = 401234, .temperature = 0.45 });
    try pirate_data.append(gpa, .{ .year = 1812, .pirates = 356789, .temperature = 0.57 });
    try pirate_data.append(gpa, .{ .year = 1820, .pirates = 312345, .temperature = 0.69 });
    try pirate_data.append(gpa, .{ .year = 1828, .pirates = 267890, .temperature = 0.81 });
    try pirate_data.append(gpa, .{ .year = 1836, .pirates = 223456, .temperature = 0.93 });
    try pirate_data.append(gpa, .{ .year = 1844, .pirates = 178901, .temperature = 1.05 });
    try pirate_data.append(gpa, .{ .year = 1852, .pirates = 134567, .temperature = 1.17 });
    try pirate_data.append(gpa, .{ .year = 1860, .pirates = 90123, .temperature = 1.29 });
    try pirate_data.append(gpa, .{ .year = 1868, .pirates = 85678, .temperature = 1.41 });
    try pirate_data.append(gpa, .{ .year = 1876, .pirates = 81234, .temperature = 1.53 });
    try pirate_data.append(gpa, .{ .year = 1884, .pirates = 76789, .temperature = 1.65 });
    try pirate_data.append(gpa, .{ .year = 1892, .pirates = 72345, .temperature = 1.77 });
    try pirate_data.append(gpa, .{ .year = 1900, .pirates = 67890, .temperature = 1.89 });
    try pirate_data.append(gpa, .{ .year = 1908, .pirates = 63456, .temperature = 2.01 });
    try pirate_data.append(gpa, .{ .year = 1916, .pirates = 58901, .temperature = 2.13 });
    try pirate_data.append(gpa, .{ .year = 1924, .pirates = 54567, .temperature = 2.25 });
    try pirate_data.append(gpa, .{ .year = 1932, .pirates = 50123, .temperature = 2.37 });
    try pirate_data.append(gpa, .{ .year = 1940, .pirates = 45678, .temperature = 2.49 });
    try pirate_data.append(gpa, .{ .year = 1948, .pirates = 41234, .temperature = 2.61 });
    try pirate_data.append(gpa, .{ .year = 1956, .pirates = 36789, .temperature = 2.73 });
    try pirate_data.append(gpa, .{ .year = 1964, .pirates = 32345, .temperature = 2.85 });
    try pirate_data.append(gpa, .{ .year = 1972, .pirates = 27890, .temperature = 2.97 });
    try pirate_data.append(gpa, .{ .year = 1980, .pirates = 23456, .temperature = 3.09 });
    try pirate_data.append(gpa, .{ .year = 1988, .pirates = 19012, .temperature = 3.21 });
    try pirate_data.append(gpa, .{ .year = 1996, .pirates = 14567, .temperature = 3.33 });
    try pirate_data.append(gpa, .{ .year = 2000, .pirates = 10000, .temperature = 3.4 });
    try pirate_data.append(gpa, .{ .year = 2004, .pirates = 8000, .temperature = 3.5 });
    try pirate_data.append(gpa, .{ .year = 2008, .pirates = 6000, .temperature = 3.6 });
    try pirate_data.append(gpa, .{ .year = 2012, .pirates = 4000, .temperature = 3.7 });
    try pirate_data.append(gpa, .{ .year = 2016, .pirates = 2000, .temperature = 3.8 });
    try pirate_data.append(gpa, .{ .year = 2020, .pirates = 1000, .temperature = 3.9 });
    try pirate_data.append(gpa, .{ .year = 2021, .pirates = 900, .temperature = 3.95 });
    try pirate_data.append(gpa, .{ .year = 2022, .pirates = 800, .temperature = 4.0 });
    try pirate_data.append(gpa, .{ .year = 2023, .pirates = 700, .temperature = 4.05 });
    try pirate_data.append(gpa, .{ .year = 2024, .pirates = 600, .temperature = 4.1 });
    try pirate_data.append(gpa, .{ .year = 2025, .pirates = 550, .temperature = 4.15 });
    try pirate_data.append(gpa, .{ .year = 2026, .pirates = 500, .temperature = 4.2 });
}

const years: [50][]const u8 = createYears();

fn createYears() [50][]const u8 {
    var result: [50][]const u8 = undefined;
    for (0..50) |i| {
        const y = 1700 + i * 8;
        result[i] = std.fmt.comptimePrint("{d}", .{y});
    }
    return result;
}
// 3 real cols, but 4 virtual cols as first cell is split into 2.
var keyboard_nav: dvui.navigation.GridKeyboard = .{ .num_cols = 4, .num_rows = 0, .wrap_cursor = true, .tab_out = true, .num_scroll = 5 };
var initialized = false;

// both dvui and SDL drawing
fn gui_frame() !void {
    {
        dvui.currentWindow().debug_window_show = false;
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

    var main_box = dvui.box(@src(), .horizontal, .{ .expand = .both, .color_fill = .fill_window, .background = true, .border = dvui.Rect.all(1) });
    defer main_box.deinit();
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .border = dvui.Rect.all(1) });
        defer vbox.deinit();
        {
            var bottom_panel = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .gravity_y = 1.0 });
            defer bottom_panel.deinit();
            var text = dvui.textEntry(@src(), .{}, .{});
            text.deinit();
            text = dvui.textEntry(@src(), .{}, .{});
            text.deinit();
        }
        {
            var top_panel = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .gravity_y = 0 });
            defer top_panel.deinit();
            var text = dvui.textEntry(@src(), .{}, .{});
            text.deinit();
            text = dvui.textEntry(@src(), .{}, .{});
            text.deinit();
            var choice: usize = 2;
            _ = dvui.dropdown(@src(), &years, &choice, .{});
        }
        {
            //            const focus_cell = keyboard_nav.cellCursor();

            var grid = dvui.grid(@src(), .numCols(3), .{}, .{});
            defer grid.deinit();
            //ui.currentWindow().debug_widget_id = dvui.focusedWidgetId() orelse .zero;
            // 3 real + 1 virtual column
            // TODO: Make the naming consistent.
            keyboard_nav.num_scroll = dvui.navigation.GridKeyboard.numScrollDefault(grid);
            keyboard_nav.setLimits(4, pirate_data.len);
            keyboard_nav.processEventsCustom(grid, pointToCellConverter);
            const focused_cell = keyboard_nav.cellCursor();

            const style_base = CellStyle{ .opts = .{ .tab_index = null, .expand = .horizontal } };
            //const style_base = CellStyle{ .opts = .{ .expand = .horizontal } };

            const style: CellStyleNav = .{ .base = style_base, .focus_cell = focused_cell, .tab_index = null };

            dvui.gridHeading(@src(), grid, 0, "Year", .fixed, .{});
            dvui.gridHeading(@src(), grid, 1, "Temperature", .fixed, .{});
            dvui.gridHeading(@src(), grid, 2, "Num Pirates", .fixed, .{});

            for (pirate_data.items(.year), pirate_data.items(.temperature), pirate_data.items(.pirates), 0..) |*year, *temp, *pirates, row_num| {
                var col_num: usize = 0;
                var focus_col: usize = 0;
                {
                    defer col_num += 1;
                    var cell = grid.bodyCell(@src(), col_num, row_num, style.cellOptions(col_num, row_num));
                    defer cell.deinit();
                    //var choice: usize = 2;
                    var text = dvui.textEntry(@src(), .{}, style.options(focus_col, row_num));
                    focus_col += 1;
                    text.deinit();
                    //_ = dvui.dropdown(@src(), &years, &choice, style.options(col_num, row_num));
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = year, .min = -9999, .max = 9999 }, style.options(focus_col, row_num));
                    focus_col += 1;
                }
                {
                    defer col_num += 1;
                    defer focus_col += 1;

                    var cell = grid.bodyCell(@src(), col_num, row_num, style.cellOptions(col_num, row_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = temp, .min = -10, .max = 10 }, style.options(focus_col, row_num));
                }
                {
                    defer col_num += 1;
                    defer focus_col += 1;
                    var cell = grid.bodyCell(@src(), col_num, row_num, style.cellOptions(col_num, row_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = pirates, .min = 0, .max = 10_000_000_000 }, style.options(focus_col, row_num));
                }
            }
            if (!initialized) {
                // TODO: Need to make this initialization better.
                keyboard_nav.navigation_keys = .defaults();
                keyboard_nav.scrollTo(0, 0);
                keyboard_nav.is_focused = true;
            }

            if (dvui.tagGet("grid_focus_next")) |focus_widget| {
                // TODO: can we tighten up the api here somehow? is_focused seems difficult to discover or
                // know why you would need to use it here. Maybe rename this to shouldFocus? or focusChanged????
                if ((keyboard_nav.is_focused and !dvui.navigation.was_mouse_focus) or !initialized) {
                    dvui.focusWidget(focus_widget.id, null, null);
                    initialized = true;
                }
            }
            keyboard_nav.reset();
        }
    }
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .border = dvui.Rect.all(1) });
        defer vbox.deinit();

        var plot = dvui.plot(
            @src(),
            .{ .title = "Pirates vs Global Temperature" },
            .{
                .padding = .{},
                .expand = .both,
                .background = true,
                .min_size_content = .{ .w = 500 },
            },
        );
        defer plot.deinit();
        const thick = 2;
        const scale = 200_000;
        {
            var s1 = plot.line();
            defer s1.deinit();
            for (pirate_data.items(.year), pirate_data.items(.temperature)) |x, y| {
                s1.point(x, y);
            }
            s1.stroke(thick, .red);
        }
        {
            var s2 = plot.line();
            defer s2.deinit();
            for (pirate_data.items(.year), pirate_data.items(.pirates)) |x, y| {
                s2.point(x, (1_000_000 - y) / scale);
            }
            s2.stroke(thick, .blue);
        }
    }
}

// TODO: Merge this with the navigation struct. They need to talk to each other to work out if we are
// tabbing in or tabbing out of the widget.
const CellStyleNav = struct {
    base: CellStyle,
    focus_cell: ?dvui.GridWidget.Cell,
    tab_index: ?u16 = null,

    pub fn cellOptions(self: *const CellStyleNav, col_num: usize, row_num: usize) dvui.GridWidget.CellOptions {
        return self.base.cellOptions(col_num, row_num);
    }

    pub fn options(self: *const CellStyleNav, col_num: usize, row_num: usize) dvui.Options {
        if (self.focus_cell) |focus_cell| {
            if (row_num == focus_cell.row_num and col_num == focus_cell.col_num) {
                return self.base.options(col_num, row_num).override(.{ .tag = "grid_focus_next", .tab_index = self.tab_index });
            }
        }
        return self.base.options(col_num, row_num).override(.{ .tab_index = 0 });
    }
};

pub fn pointToCellConverter(g: *dvui.GridWidget, p: dvui.Point.Physical) ?dvui.GridWidget.Cell {
    var result = g.pointToCell(p);
    if (result) |*r| {
        if (r.col_num == 0) {
            if (p.toNatural().x > g.colWidth(0) / 2)
                r.col_num += 1;
        } else {
            r.col_num += 1;
        }
    }
    return result;
}

const PirateDatum = struct { year: f64, temperature: f64, pirates: f64 };

var pirate_data: std.MultiArrayList(PirateDatum) = .empty;
