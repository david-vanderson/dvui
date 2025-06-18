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
        _ = winapi.AttachConsole(0xFFFFFFFF);
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
    //backend.log_events = true;

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

const Data = struct {
    pub const Parity = enum { odd, even };
    selected: bool = false,
    value: usize,
    text: []const u8 = "Nope",
    parity: Parity,
};

var data1 = makeData(20);
var data2 = makeData(20);
var data_ptr: [data1.len]*Data = makeDataPtr();

fn makeDataPtr() [data1.len]*Data {
    var result: [data1.len]*Data = undefined;
    for (0..data2.len) |i| {
        result[i] = &data1[i];
    }
    return result;
}

fn makeData(num: usize) [num]Data {
    var result: [num]Data = undefined;
    for (0..num) |i| {
        result[i] = .{ .value = i, .parity = if (i % 2 == 1) .odd else .even };
    }
    return result;
}

const icon_map: std.EnumArray(Data.Parity, []const u8) = .init(.{
    .even = dvui.entypo.aircraft_take_off,
    .odd = dvui.entypo.aircraft_landing,
});

var selections: [data2.len]bool = @splat(false);
var select_bitset: std.StaticBitSet(data2.len) = .initEmpty();

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
    if (false) {
        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true });
        defer vbox.deinit();
        var enter_pressed = false;
        {
            var text = dvui.textEntry(@src(), .{}, .{});
            defer text.deinit();
            enter_pressed = text.enter_pressed;
        }
        dvui.label(@src(), "Enter pressed = {}", .{enter_pressed}, .{});
        return;
    }
    if (false) {
        const local = struct {
            const num_rows = 500;
            var scroll_info: dvui.ScrollInfo = .{};
            var selections: std.StaticBitSet(num_rows) = .initEmpty();
            var select_info: dvui.SelectionInfo = .{};
        };
        var grid = dvui.grid(
            @src(),
            .{
                .scroll_opts = .{ .scroll_info = &local.scroll_info },
            },
            .{ .expand = .both },
        );
        defer grid.deinit();
        const Selection = dvui.GridWidget.DataAdapter.Selection;
        var selector: dvui.GridWidget.Actions.MultiSelectMouse = .{ .selection_info = &local.select_info };
        var selection_changed: bool = false;
        var scroller = dvui.GridWidget.VirtualScroller.init(
            grid,
            .{ .scroll_info = &local.scroll_info, .total_rows = local.num_rows },
        );
        const first = scroller.startRow();
        const last = scroller.endRow();
        const adapter = Selection.Bitset(@TypeOf(local.selections)){ .bitset = &local.selections, .start = first, .end = last };
        //const adapter = DataAdpater.SliceUpdatable()

        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            selection_changed = dvui.gridColumnCheckbox(
                @src(),
                grid,
                .{ .selection_info = &local.select_info },
                adapter,
                .{},
            );
        }
        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            for (first..last) |row| {
                var cell = grid.bodyCell(@src(), row, .{});
                defer cell.deinit();
                dvui.label(@src(), "{d}", .{row}, .{});
            }
        }
        selector.processEvents();
        selector.performAction(selection_changed, adapter);
    } else {
        const local = struct {
            var selection_info: dvui.SelectionInfo = .{};
            // This selector keeps state. so needs to be static.
            // TODO: We could think about storing the state between frames, but .. is that worth it?
            // I think I'd rather thave state visible to the user???
            var selector: dvui.GridWidget.Actions.MultiSelectMouse = .{ .selection_info = &selection_info };
            var frame_count: usize = 0;
        };

        var grid = dvui.grid(@src(), .{}, .{ .expand = .both });
        defer grid.deinit();

        // This is just to make sure nothing regarding data is comptime.
        const data = if (local.frame_count != std.math.maxInt(usize)) &data1 else &data2;
        defer local.frame_count += 1;
        var selection_changed = false;
        const DataAdapter = dvui.GridWidget.DataAdapter;
        const CellStyle = dvui.GridWidget.CellStyle;
        //const Selection = DataAdapter.Selection;
        const adapter = DataAdapter.SliceOfStructUpdatable(Data, "selected"){ .slice = data };
        //const adapter = DataAdapter.SliceUpdatable(bool){ .slice = &selections };
        //const adapter = DataAdapter.BitSetUpdateable(@TypeOf(select_bitset)){ .bitset = &select_bitset };
        //var single_select: dvui.GridWidget.Actions.SingleSelect = .{ .selection_info = &local.selection_info };

        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            var selection: dvui.GridColumnSelectAllState = undefined;
            _ = dvui.gridHeadingCheckbox(@src(), grid, &selection, .{});
            selection_changed = dvui.gridColumnCheckbox(@src(), grid, .{ .selection_info = &local.selection_info }, adapter, CellStyleTabIndex{});
        }
        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            dvui.gridHeading(@src(), grid, "Value", .fixed, .{});
            dvui.gridColumnLabel(@src(), grid, "{d}", DataAdapter.SliceOfStruct(Data, "value"){ .slice = data }, .{});
            //var tst = DataAdapterStructSlice(Data, "value"){ .slice = data };
            //tst.setValue(3, 69);
        }
        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            dvui.gridHeading(@src(), grid, "Selected", .fixed, .{});
            dvui.gridColumnLabel(@src(), grid, "{}", adapter, .{});
        }
        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            dvui.gridHeading(@src(), grid, "YN", .fixed, .{});
            dvui.gridColumnLabel(
                @src(),
                grid,
                "{s}",
                DataAdapter.SliceOfStructConvert(
                    Data,
                    "selected",
                    DataAdapter.boolToYN,
                ){ .slice = data },
                CellStyle{ .opts = .{ .gravity_x = 0.5 } },
            );
        }

        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            dvui.gridHeading(@src(), grid, "Parity", .fixed, .{});
            dvui.gridColumnLabel(
                @src(),
                grid,
                "{s}",
                DataAdapter.SliceOfStructConvert(Data, "parity", DataAdapter.enumToString){ .slice = data },
                .{},
            );
        }
        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            dvui.gridHeading(@src(), grid, "Icon", .fixed, .{});
            dvui.gridColumnIcon(
                @src(),
                grid,
                .{},
                DataAdapter.SliceOfStructConvert(
                    Data,
                    "parity",
                    DataAdapter.enumArrayLookup(icon_map),
                ){ .slice = data },
                CellStyle{ .opts = .{ .gravity_x = 0.5 } },
            );
        }
        {
            var col = grid.column(@src(), .{});
            defer col.deinit();
            dvui.gridHeading(@src(), grid, "Icon", .fixed, .{});
            if (dvui.gridColumnTextEntry(
                @src(),
                grid,
                .{},
                DataAdapter.SliceOfStructUpdatable(
                    Data,
                    "text",
                ){ .slice = data },
                CellStyleTabIndex{},
            )) |row_num| {
                std.debug.print("text changed: {}:{s}\n", .{ row_num, data[row_num].text });
            }
        }

        if (true) {
            if (selection_changed) {
                std.debug.print("user clicked on checkbox #: {?}\n", .{local.selection_info.this_changed});
            }
            //single_select.performAction(selection_changed, adapter);
            local.selector.processEvents();
            local.selector.performAction(selection_changed, adapter);
        }
    }
}

const CellStyleTabIndex = struct {
    cell_opts: dvui.GridWidget.CellOptions = .{},
    opts: dvui.Options = .{},

    pub fn cellOptions(self: *const CellStyleTabIndex, _: usize, _: usize) dvui.GridWidget.CellOptions {
        return self.cell_opts;
    }
    // Tab by col within rows. (Works up to 10 cols and 6550 rows)
    pub fn options(self: *const CellStyleTabIndex, col: usize, row: usize) dvui.Options {
        return self.opts.override(.{ .tab_index = @intCast(row * 10 + col + 1) });
    }
};

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
