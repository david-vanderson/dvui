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
    var theme = dvui.Theme.builtin.adwaita_light;
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{ .theme = &theme });
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

// This example demonstrates an advanced usage of the keyboard navigation. The navigation maintains a virtual 8 column cursor
// over the 5 columns grid. That is because the first 3 columns have 2 widgets that can get keyboard focus.
// The 2 widgets in the first 3 columns are actually laid out vertically, even though the tab focus treats them as columns.
// This allows the user to arrow-down and just jump through the text boxes in the column, or just jump through the sliders,
// while still getting correct focus when tabbing through the widgets.
var keyboard_nav: dvui.navigation.GridKeyboard = .{ .num_cols = 8, .num_rows = 0, .wrap_cursor = true, .tab_out = true, .num_scroll = 5 };
var initialized = false;
var col_widths: [5]f32 = .{ 100, 100, 100, 35, 35 };
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
            if (dvui.button(@src(), "Add (NOT)", .{ .draw_focus = true }, .{})) {}
            _ = dvui.button(@src(), "Delete (NOT)", .{ .draw_focus = true }, .{});
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
            var grid = dvui.grid(@src(), .{ .col_widths = &col_widths }, .{}, .{});
            defer grid.deinit();
            //ui.currentWindow().debug_widget_id = dvui.focusedWidgetId() orelse .zero;
            // 3 real + 1 virtual column
            // TODO: Make the naming consistent.
            keyboard_nav.num_scroll = dvui.navigation.GridKeyboard.numScrollDefault(grid);
            keyboard_nav.setLimits(8, data.len);
            keyboard_nav.processEventsCustom(grid, pointToCellConverter);
            const focused_cell = keyboard_nav.cellCursor();

            const style_base = CellStyle{ .opts = .{
                .tab_index = null,
                .expand = .horizontal,
            } };
            //const style_base = CellStyle{ .opts = .{ .expand = .horizontal } };

            const style: CellStyleNav = .{ .base = style_base, .focus_cell = focused_cell, .tab_index = null };

            dvui.gridHeading(@src(), grid, 0, "X", .fixed, .{});
            dvui.gridHeading(@src(), grid, 1, "Y1", .fixed, .{});
            dvui.gridHeading(@src(), grid, 2, "Y2", .fixed, .{});
            var row_to_delete: ?usize = null;
            var row_to_add: ?usize = null;

            for (data.items(.x), data.items(.y1), data.items(.y2), 0..) |*x, *y1, *y2, row_num| {
                var cell_num: dvui.GridWidget.Cell = .colRow(0, row_num);
                var focus_cell: dvui.GridWidget.Cell = .colRow(0, row_num);
                // X Column
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    var cell_vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
                    defer cell_vbox.deinit();

                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = x, .min = 0, .max = 100, .show_min_max = true }, style.options(focus_cell).override(.{ .gravity_y = 0 }));
                    focus_cell.col_num += 1;

                    var fraction: f32 = @floatCast(x.*);
                    fraction /= 100;
                    if (dvui.slider(@src(), .horizontal, &fraction, style.options(focus_cell).override(.{ .gravity_y = 1 }))) {
                        x.* = fraction * 10000;
                        x.* = @round(x.*) / 100;
                    }
                    focus_cell.col_num += 1;
                }
                // Y1 Columnn
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    var cell_vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
                    defer cell_vbox.deinit();

                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = y1, .min = -100, .max = 100, .show_min_max = true }, style.options(focus_cell));
                    focus_cell.col_num += 1;

                    var fraction: f32 = @floatCast(y1.*);
                    fraction += 100;
                    fraction /= 200;
                    if (dvui.slider(@src(), .horizontal, &fraction, style.options(focus_cell).override(.{ .max_size_content = .width(50), .gravity_y = 1 }))) {
                        y1.* = fraction * 200;
                        y1.* = @round(y1.*) - 100;
                    }
                    focus_cell.col_num += 1;
                }
                // Y2 Column
                {
                    defer cell_num.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    var cell_vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
                    defer cell_vbox.deinit();

                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = y2, .min = -100, .max = 100, .show_min_max = true }, style.options(focus_cell));
                    focus_cell.col_num += 1;

                    var fraction: f32 = @floatCast(y2.*);
                    fraction += 100;
                    fraction /= 200;
                    if (dvui.slider(@src(), .horizontal, &fraction, style.options(focus_cell).override(.{ .max_size_content = .width(50), .gravity_y = 1 }))) {
                        y2.* = fraction * 200;
                        y2.* = @round(y2.*) - 100;
                    }
                    focus_cell.col_num += 1;
                }
                {
                    defer cell_num.col_num += 1;
                    defer focus_cell.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    if (dvui.buttonIcon(@src(), "Insert", dvui.entypo.add_to_list, .{}, .{}, style.options(focus_cell).override(.{ .expand = .horizontal }))) {
                        row_to_add = cell_num.row_num + 1;
                    }
                }
                {
                    defer cell_num.col_num += 1;
                    defer focus_cell.col_num += 1;
                    var cell = grid.bodyCell(@src(), cell_num, style.cellOptions(cell_num));
                    defer cell.deinit();
                    if (dvui.buttonIcon(@src(), "Delete", dvui.entypo.cross, .{}, .{}, style.options(focus_cell).override(.{ .expand = .horizontal }))) {
                        row_to_delete = cell_num.row_num;
                    }
                }
            }
            if (!initialized) {
                keyboard_nav.navigation_keys = .defaults();
                keyboard_nav.scrollTo(0, 0);
                keyboard_nav.is_focused = true; // We want the grid focused by default.
            }

            if (dvui.tagGet("grid_focus_next")) |focus_widget| {
                if ((keyboard_nav.shouldFocus()) or !initialized) {
                    dvui.focusWidget(focus_widget.id, null, null);
                    initialized = true;
                }
            }
            keyboard_nav.gridEnd();
            if (row_to_add) |row_num| {
                data.insert(gpa, row_num, .{ .x = 50, .y1 = 0, .y2 = 0 }) catch {};
            }
            if (row_to_delete) |row_num| {
                if (data.len > 1)
                    data.orderedRemove(row_num)
                else
                    data.set(0, .{ .x = 0, .y1 = 0, .y2 = 0 });
            }
        }
    }
    {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .border = dvui.Rect.all(1) });
        defer vbox.deinit();
        var x_axis: dvui.PlotWidget.Axis = .{ .name = "X", .min = 0, .max = 100 };
        var y_axis: dvui.PlotWidget.Axis = .{
            .name = "Y1\nY2",
            .min = @min(minVal(data.items(.y1)), minVal(data.items(.y2))),
            .max = @max(maxVal(data.items(.y1)), maxVal(data.items(.y2))),
        };
        var plot = dvui.plot(
            @src(),
            .{
                .title = "X vs Y",
                .x_axis = &x_axis,
                .y_axis = &y_axis,
                .mouse_hover = true,
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

/// The job of this function is to turn a screen position into a cell.
/// In this example, even though there are two widgets in the cell, the first one
/// always gets focus whenever someone clicks in the cell.
/// So all it needs to do is map the clicked in grid column to the correct virtual focus column .
pub fn pointToCellConverter(g: *dvui.GridWidget, p: dvui.Point.Physical) ?dvui.GridWidget.Cell {
    var result = g.pointToCell(p);
    if (result) |*r| {
        // This will always focus the text box on mouse click in the cell,
        // but still allow kb nav of the sliders.
        r.col_num = switch (r.col_num) {
            0 => 0, // Col 0 contains 2 focus widgets
            1 => 2, // Col 1 contains 2 focus widgets
            2 => 4, // Col 2 contains 2 focus widgets
            3 => 5, // Col 3 and 4 only have 1 widget.
            4 => 6,
            else => unreachable,
        };
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
