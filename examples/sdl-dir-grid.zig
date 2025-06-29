const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
const CellStyle = dvui.GridWidget.CellStyle;
comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

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
    selections = try .initEmpty(gpa, 0);

    // TODO: temp disable
    //defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

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

var mode: enum { raw, cached } = .raw;
var selection_mode: enum { multi_select, single_select } = .multi_select;
var row_select: bool = false;
var highlight_style: CellStyle.HoveredRow = .{ .cell_opts = .{ .color_fill_hover = .fill_hover, .background = true } };

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
    var main_box = dvui.box(@src(), .vertical, .{ .expand = .both, .color_fill = .fill_window, .background = true });
    defer main_box.deinit();
    {
        var vbox = dvui.box(@src(), .vertical, .{ .gravity_y = 1.0 });
        defer vbox.deinit();
        if (dvui.expander(@src(), "Options", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox.deinit();
            if (dvui.radio(@src(), mode == .raw, "Raw", .{ .margin = dvui.Rect.all(6) })) {
                mode = .raw;
                selectAllCache(.select_none);
                filtering_changed = true;
            }
            if (dvui.radio(@src(), mode == .cached, "Cached", .{ .margin = dvui.Rect.all(6) })) {
                filtering_changed = true;
                selectAllRaw(.select_none);
                mode = .cached;
            }
            var selected = selection_mode == .multi_select;
            if (dvui.checkbox(@src(), &selected, "Multi-Select", .{ .margin = dvui.Rect.all(6) })) {
                selection_mode = if (selected) .multi_select else .single_select;
                if (selection_mode == .single_select) {
                    switch (mode) {
                        .raw => selectAllRaw(.select_none),
                        .cached => selectAllCache(.select_none),
                    }
                }
            }
            _ = dvui.checkbox(@src(), &row_select, "Row Select", .{ .margin = dvui.Rect.all(6) });
            dvui.labelNoFmt(@src(), "Filter: (contains): ", .{}, .{ .margin = dvui.Rect.all(6) });
            var text = dvui.textEntry(@src(), .{}, .{ .gravity_y = 0.5, .margin = dvui.Rect.all(6) });
            defer text.deinit();
            filename_filter = text.getText();
        }
    }
    {
        var grid = dvui.grid(@src(), .numCols(6), .{}, .{ .expand = .both, .background = true });
        defer grid.deinit();

        const row_clicked: ?usize = blk: {
            if (!row_select) break :blk null;
            for (dvui.events()) |*e| {
                if (!dvui.eventMatchSimple(e, grid.data())) continue;
                if (e.evt != .mouse) continue;
                const me = e.evt.mouse;
                if (me.action != .press) continue;
                if (grid.pointToColRow(me.p)) |cell| {
                    if (cell.col_num > 0) break :blk cell.row_num;
                }
            }
            break :blk null;
        };

        var select_all_state: dvui.GridColumnSelectAllState = undefined;
        // Note: The extra "selection_changed" here is because I've chosen to unselect anything that was filtered.
        // If we were just doing selection it just needs multi_select.selectionChanged();
        const selection_changed = filtering_changed or multi_select.selectionChanged();
        if (selection_mode == .multi_select) {
            if (dvui.gridHeadingCheckbox(@src(), grid, 0, &select_all_state, selection_changed, .{})) {
                switch (mode) {
                    .raw => selectAllRaw(select_all_state),
                    .cached => selectAllCache(select_all_state),
                }
            }
        }
        dvui.gridHeading(@src(), grid, 1, "Name", .fixed, CellStyle{ .cell_opts = .{ .size = .{ .w = 300 } } });
        dvui.gridHeading(@src(), grid, 2, "Kind", .fixed, .{});
        dvui.gridHeading(@src(), grid, 3, "Size", .fixed, .{});
        dvui.gridHeading(@src(), grid, 4, "Mode", .fixed, .{});
        dvui.gridHeading(@src(), grid, 5, "MTime", .fixed, .{});

        if (row_select)
            highlight_style.processEvents(grid);
        const was_filtering = filtering;

        switch (mode) {
            .raw => directoryDisplay(grid, row_clicked) catch return,
            .cached => directoryDisplayCached(grid, row_clicked),
        }
        filtering_changed = (was_filtering != filtering);
        if (selection_mode == .multi_select) {
            multi_select.processEvents(grid.data());
            if (multi_select.selectionChanged()) {
                for (multi_select.selectionIdStart()..multi_select.selectionIdEnd() + 1) |row_num| {
                    switch (mode) {
                        .raw => selections.setValue(row_num, multi_select.should_select),
                        .cached => dir_cache.items[row_num].selected = multi_select.should_select,
                    }
                }
            }
        } else {
            single_select.processEvents(grid.data());
            if (single_select.selectionChanged()) {
                if (single_select.id_to_unselect) |unselect_row| {
                    switch (mode) {
                        .raw => selections.unset(unselect_row),
                        .cached => dir_cache.items[unselect_row].selected = false,
                    }
                }
                if (single_select.id_to_select) |select_row| {
                    switch (mode) {
                        .raw => selections.set(select_row),
                        .cached => dir_cache.items[select_row].selected = true,
                    }
                }
            }
        }
    }
}
var multi_select: dvui.select.MultiSelect = .{};
var single_select: dvui.select.SingleSelect = .{};
var filename_filter: []u8 = "";
var filtering: bool = false;
var filtering_changed = false;

var selections: std.DynamicBitSetUnmanaged = undefined;
// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};

pub fn directoryOpen() !std.fs.Dir {
    return try std.fs.cwd().openDir(".", .{ .iterate = true, .access_sub_paths = true });
}

pub fn directoryDisplay(grid: *dvui.GridWidget, row_selected: ?usize) !void {
    var dir = directoryOpen() catch return;
    defer dir.close();
    var itr = dir.iterate();
    var dir_num: usize = 0;
    var row_num: usize = 0;
    filtering = false;
    while (itr.next() catch null) |entry| : (dir_num += 1) {
        if (filename_filter.len > 0) {
            if (std.mem.indexOf(u8, entry.name, filename_filter)) |_| {} else {
                if (dir_num < selections.capacity()) {
                    selections.unset(dir_num);
                }
                filtering = true;
                continue;
            }
        }
        defer row_num += 1;
        var col_num: usize = 0;
        {
            defer col_num += 1;
            var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
            defer cell.deinit();
            var is_set = if (dir_num < selections.capacity()) selections.isSet(dir_num) else false;
            _ = dvui.checkbox(@src(), &is_set, null, .{ .selection_id = dir_num, .gravity_x = 0.5 });
            if (row_num == row_selected) {
                dvui.currentWindow().addSelectionEvent(dir_num, !is_set, cell.data().borderRectScale().r);
            }
        }
        {
            defer col_num += 1;
            var cell = grid.bodyCell(
                @src(),
                col_num,
                row_num,
                highlight_style.cellOptions(col_num, row_num).override(.{ .size = .{ .w = 300 } }),
            );
            defer cell.deinit();
            dvui.labelNoFmt(@src(), entry.name, .{}, .{});
        }
        {
            defer col_num += 1;
            var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
            defer cell.deinit();
            dvui.labelNoFmt(@src(), @tagName(entry.kind), .{}, .{});
        }
        if (entry.kind == .file) {
            const stats = dir.statFile(entry.name) catch |err| {
                std.debug.print("Error stat {s} : {s}\n", .{ entry.name, @errorName(err) });
                continue;
            };
            {
                defer col_num += 1;
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{d}", .{stats.size}, .{});
            }
            {
                defer col_num += 1;
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{d}", .{stats.mode}, .{});
            }
            {
                defer col_num += 1;
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{[year]:0>4}-{[month]:0>2}-{[day]:0>2} {[hour]:0>2}:{[minute]:0>2}:{[second]:0>2}", fromNsTimestamp(stats.mtime), .{});
            }
        } else {
            const end_col = col_num + 3;
            while (col_num != end_col) : (col_num += 1) {
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
            }
        }
    }
    if (selections.count() != dir_num)
        try selections.resize(gpa, dir_num, false);
}

pub fn selectAllRaw(state: dvui.GridColumnSelectAllState) void {
    switch (state) {
        .select_all => selections.setAll(), // TODO: This needs to set based off a filter.
        .select_none => selections.unsetAll(), // TODO: This needs to set/unset based off a filter.
        .unchanged => {},
    }
}

const CacheEntry = struct {
    selected: bool,
    name: []const u8,
    kind: std.fs.Dir.Entry.Kind,
    size: u65,
    mode: std.fs.File.Mode,
    mtime: i128,
};

const no_stat: std.fs.Dir.Stat = .{
    .inode = 0,
    .atime = 0,
    .ctime = 0,
    .kind = .directory,
    .mode = 0,
    .mtime = 0,
    .size = 0,
};
var dir_cache: std.ArrayListUnmanaged(CacheEntry) = .empty;
var cache_valid = false;

pub fn selectAllCache(state: dvui.GridColumnSelectAllState) void {
    for (dir_cache.items) |*entry| {
        switch (state) {
            .select_all => entry.selected = true,
            .select_none => entry.selected = false,
            .unchanged => {},
        }
    }
}

// TODO: Allocate the filenames from an area that can be reset when the
// cache is invalidated.
// Invalidate cache on exit.
pub fn directoryDisplayCached(grid: *dvui.GridWidget, row_selected: ?usize) void {
    if (!cache_valid) {
        var dir = directoryOpen() catch return;
        defer dir.close();
        var itr = dir.iterate();
        while (itr.next() catch null) |entry| {
            const name = gpa.dupe(u8, entry.name) catch continue;
            const stat: std.fs.Dir.Stat = if (entry.kind == .file) dir.statFile(entry.name) catch no_stat else no_stat;

            dir_cache.append(gpa, .{
                .selected = false,
                .name = name,
                .kind = entry.kind,
                .size = stat.size,
                .mode = stat.mode,
                .mtime = stat.mtime,
            }) catch continue;
        }
        cache_valid = true;
    }
    filtering = false;

    var row_num: usize = 0;
    for (dir_cache.items, 0..) |*entry, dir_num| {
        var col_num: usize = 0;
        if (filename_filter.len > 0) {
            if (std.mem.indexOf(u8, entry.name, filename_filter)) |_| {} else {
                // Clear selection of anything filtered. Not all apps would want to do this.
                dir_cache.items[dir_num].selected = false;
                filtering = true;
                continue;
            }
        }
        defer row_num += 1;
        {
            defer col_num += 1;
            var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
            defer cell.deinit();
            var is_set = dir_cache.items[dir_num].selected;
            _ = dvui.checkbox(@src(), &is_set, null, .{ .selection_id = dir_num, .gravity_x = 0.5 });
            if (row_selected == dir_num) {
                dvui.currentWindow().addSelectionEvent(dir_num, !is_set, cell.data().borderRectScale().r);
            }
        }
        {
            defer col_num += 1;
            var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
            defer cell.deinit();
            dvui.labelNoFmt(@src(), entry.name, .{}, .{});
        }
        {
            defer col_num += 1;
            var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
            defer cell.deinit();
            dvui.labelNoFmt(@src(), @tagName(entry.kind), .{}, .{});
        }
        if (entry.kind == .file) {
            {
                defer col_num += 1;
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{d}", .{entry.size}, .{});
            }
            {
                defer col_num += 1;
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{d}", .{entry.mode}, .{});
            }
            {
                defer col_num += 1;
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
                dvui.label(@src(), "{[year]:0>4}-{[month]:0>2}-{[day]:0>2} {[hour]:0>2}:{[minute]:0>2}:{[second]:0>2}", fromNsTimestamp(entry.mtime), .{});
            }
        } else {
            const end_col = col_num + 3;
            while (col_num != end_col) : (col_num += 1) {
                var cell = grid.bodyCell(@src(), col_num, row_num, highlight_style.cellOptions(col_num, row_num));
                defer cell.deinit();
            }
        }
    }
}

pub fn fromNsTimestamp(timestamp_ns: i128) struct { year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8 } {
    const days_per_400_years = 146_097;
    const days_per_100_years = 36_524;
    const days_per_4_years = 1_460;

    // Split into days and nanoseconds of the day
    const days_since_epoch: i128 = @divTrunc(timestamp_ns, std.time.ns_per_day);
    const nanos_of_day: i128 = @rem(timestamp_ns, std.time.ns_per_day);

    // Convert nanoseconds of the day to hours, minutes, seconds
    const hour: u8 = @intCast(@divTrunc(nanos_of_day, (std.time.ns_per_s * 3_600)));
    const minute: u8 = @intCast(@divTrunc((@mod(nanos_of_day, (std.time.ns_per_s * 3_600))), (std.time.ns_per_s * 60)));
    const second: u8 = @intCast(@divTrunc((@mod(nanos_of_day, (std.time.ns_per_s * 60))), std.time.ns_per_s));

    // Shift to Gregorian calendar
    const days_since_gregorian_epoch: i128 = days_since_epoch + 719_468; // Difference between unix epoch and gregorian epoch

    // 400-year eras
    const era: i128 = @divTrunc(days_since_gregorian_epoch, days_per_400_years);
    const day_of_era: i128 = days_since_gregorian_epoch - era * days_per_400_years;

    const year_of_era: i128 = @divTrunc(
        day_of_era - @divTrunc(day_of_era, days_per_4_years) + @divTrunc(day_of_era, days_per_100_years) - @divTrunc(day_of_era, days_per_400_years - 1),
        365,
    );
    const day_of_year: i128 = day_of_era - (365 * year_of_era + @divTrunc(year_of_era, 4) - @divTrunc(year_of_era, 100));

    const month_part: i128 = @divTrunc(5 * day_of_year + 2, 153);
    const day: u8 = @intCast(day_of_year - @divTrunc(153 * month_part + 2, 5) + 1);
    const month: u8 = @intCast(month_part + 3 - 12 * @divTrunc(month_part, 10));
    const year: u16 = @intCast(year_of_era + era * 400 + @divTrunc(month_part, 10));

    return .{
        .year = year, // year 65535 bug.
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}
