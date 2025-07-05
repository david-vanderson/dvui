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

const Datum = struct { x: f64, y1: f64, y2: f64 };

var data: std.MultiArrayList(Datum) = .empty;

fn initData() !void {
    try data.append(gpa, .{ .x = 0, .y1 = -50, .y2 = 50 });
    try data.append(gpa, .{ .x = 25, .y1 = -25, .y2 = 25 });
    try data.append(gpa, .{ .x = 50, .y1 = 0, .y2 = 0 });
    try data.append(gpa, .{ .x = 75, .y1 = 25, .y2 = -25 });
    try data.append(gpa, .{ .x = 100, .y1 = 50, .y2 = -50 });
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
            keyboard_nav.setLimits(4, data.len);
            keyboard_nav.processEventsCustom(grid, pointToCellConverter);
            const focused_cell = keyboard_nav.cellCursor();

            const style_base = CellStyle{ .opts = .{ .tab_index = null, .expand = .horizontal } };
            //const style_base = CellStyle{ .opts = .{ .expand = .horizontal } };

            const style: CellStyleNav = .{ .base = style_base, .focus_cell = focused_cell, .tab_index = null };

            dvui.gridHeading(@src(), grid, 0, "X", .fixed, .{});
            dvui.gridHeading(@src(), grid, 1, "Y1", .fixed, .{});
            dvui.gridHeading(@src(), grid, 2, "Y2", .fixed, .{});

            for (data.items(.x), data.items(.y1), data.items(.y2), 0..) |*x, *y1, *y2, row_num| {
                var cell_num: dvui.GridWidget.Cell = .colRow(0, row_num);
                var focus_cell: dvui.GridWidget.Cell = .colRow(0, row_num);
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = x, .min = 0, .max = 100, .show_min_max = true }, style.options(focus_cell));
                    focus_cell.col_num += 1;
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = x, .min = 0, .max = 100, .show_min_max = true }, style.options(focus_cell));
                    focus_cell.col_num += 1;
                }
                {
                    defer cell_num.col_num += 1;
                    defer focus_cell.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = y1, .min = -100, .max = 100, .show_min_max = true }, style.options(focus_cell));
                }
                {
                    defer cell_num.col_num += 1;
                    defer focus_cell.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = y2, .min = -100, .max = 100, .show_min_max = true }, style.options(focus_cell));
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
                //                if ((keyboard_nav.is_focused and !dvui.navigation.was_mouse_focus) or !initialized) {
                if ((keyboard_nav.is_focused) or !initialized) {
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
        var x_axis: dvui.PlotWidget.Axis = .{ .name = "X", .min = 0, .max = 100 };
        var y_axis: dvui.PlotWidget.Axis = .{
            .name = "Y",
            .min = @min(minVal(data.items(.y1)), minVal(data.items(.y2))),
            .max = @max(maxVal(data.items(.y1)), maxVal(data.items(.y2))),
        };
        var plot = dvui.plot(
            @src(),
            .{
                .title = "X vs Y",
                .x_axis = &x_axis,
                .y_axis = &y_axis,
            },
            .{
                .padding = .{},
                .expand = .both,
                .background = true,
                .min_size_content = .{ .w = 500 },
            },
        );
        defer plot.deinit();
        const thick = 2;
        {
            var s1 = plot.line();
            defer s1.deinit();
            for (data.items(.x), data.items(.y1)) |x, y| {
                s1.point(x, y);
            }
            s1.stroke(thick, .red);
        }
        {
            var s2 = plot.line();
            defer s2.deinit();
            for (data.items(.x), data.items(.y2)) |x, y| {
                s2.point(x, y);
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

    pub fn cellOptions(self: *const CellStyleNav, cell: dvui.GridWidget.Cell) dvui.GridWidget.CellOptions {
        return self.base.cellOptions(cell);
    }

    pub fn options(self: *const CellStyleNav, cell: dvui.GridWidget.Cell) dvui.Options {
        if (self.focus_cell) |focus_cell| {
            if (focus_cell.eq(cell)) {
                return self.base.options(cell).override(.{ .tag = "grid_focus_next", .tab_index = self.tab_index });
            }
        }
        return self.base.options(cell).override(.{ .tab_index = 0 });
    }
};

pub fn pointToCellConverter(g: *dvui.GridWidget, p: dvui.Point.Physical) ?dvui.GridWidget.Cell {
    var result = g.pointToCell(p);
    if (result) |*r| {
        // For grid col 0 and click in 2nd half of cell, then count as virtual col 1
        // For all other columns, increase their col num by 1 to include the virtual column
        // + 12/2 = 6 pixels to account for margin/padding.
        if (r.col_num > 0 or p.toNatural().x > (g.colWidth(0) + 12) / 2) {
            r.col_num += 1;
        }
    }
    return result;
}

pub fn maxVal(slice: []f64) f64 {
    var max: f64 = -std.math.floatMin(f64);
    for (slice) |v| {
        if (v > max) max = v;
    }
    return max;
}

pub fn minVal(slice: []f64) f64 {
    var min: f64 = std.math.floatMax(f64);
    for (slice) |v| {
        if (v < min) min = v;
    }
    return min;
}
