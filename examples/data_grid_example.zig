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
var scale_val: f32 = 1.0;

var g_backend: ?Backend = null;
var g_win: ?*dvui.Window = null;
var filter_grid = false;
var frame_count: usize = 0;
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
    filtered_cars = try filterCars(gpa, cars[0..], filterLongModels);
    defer gpa.free(filtered_cars);

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(backend.hasEvent());

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
        backend.setCursor(win.cursorRequested());
        backend.textInputRect(win.textInputRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);
    }
}

const num_cars = 500_000;
pub const testing = false;
pub var scroll_info: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .given };
var virtual_scrolling = true;
var horizontal_scrolling = false;
var sortable = true;
var header_height: f32 = 0;
var row_height: f32 = 0;
var selectable = false;
const ColumnSizing = enum {
    equal_width,
    proportional,
    col_info,
    col_width,
    expand,
};
var column_sizing: ColumnSizing = .equal_width;
const prev_height: f32 = 0;
var resize_rows: bool = false;

const fixed_width_w: f32 = 50;
pub fn headerCheckboxOptions() dvui.Options {
    if (header_height == 0) {
        return .{
            .min_size_content = .{ .w = 40 },
            .max_size_content = .width(40),
        };
    } else {
        return .{
            .min_size_content = .{ .w = 40, .h = header_height },
            .max_size_content = .width(40),
        };
    }
}

//pub fn rowCheckboxOptions() dvui.Options {
//    return headerCheckboxOptions();
//}

const col_widths_default: [7]f32 = .{ 50, 20, 30, 40, 50, 60, 70 };
const col_widths_proportional: [7]f32 = .{ 50, -20, -30, -40, -20, -60, -70 };
var col_widths: [col_widths_default.len]f32 = col_widths_default;

fn colOptions(opts: dvui.GridWidget.ColOptions) dvui.GridWidget.ColOptions {
    if (column_sizing == .col_width) {
        var result = opts;
        result.width = 200;
        return result;
    }
    return opts;
}

fn headerCellOpts(opts: dvui.GridWidget.CellOptions) dvui.GridWidget.CellOptions {
    if (header_height > 0) {
        var result = opts;
        result.height = header_height;
        return result;
    }
    return opts;
}

fn bodyCellOpts(opts: dvui.GridWidget.CellOptions) dvui.CellOptionsOrCallback {
    if (row_height > 0) {
        var result = opts;
        result.height = row_height;
        return .{ .options = result };
    }
    return .{ .options = opts };
}

// both dvui and SDL drawing
fn gui_frame() !void {
    //std.debug.print("frame: {d}\n", .{frame_count});
    defer frame_count += 1;
    const backend = g_backend orelse return;
    _ = backend;
    {
        var m = try dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
        }
    }
    var main_hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .background = true });
    defer main_hbox.deinit();
    if (testing) {
        const use_text_layout = true;
        const count = 6_000;
        var box = try dvui.box(@src(), .vertical, .{ .expand = .both });
        defer box.deinit();
        for (0..count) |i| {
            if (!use_text_layout) {
                try dvui.labelNoFmt(@src(), "Test", .{ .id_extra = i });
            } else {
                var text = try dvui.textLayout(@src(), .{}, .{ .id_extra = i });
                defer text.deinit();
                // Note: Passing id_extra = i here sometimes changes the behaviour.
                //try text.addText("Test", .{ .id_extra = i });
                //
                //
                try text.addText("Test", .{});
            }
        }
        return;
    }
    {
        scroll_info.horizontal = if (horizontal_scrolling) .auto else .none;
        const start_idx: usize = if (selectable) 0 else 1;

        var grid = try dvui.grid(
            @src(),
            .{ .scroll_opts = .{
                .scroll_info = if (virtual_scrolling) &scroll_info else null,
                .horizontal = if (!virtual_scrolling) .auto else null,
            }, .col_widths = switch (column_sizing) {
                .expand, .col_width => null,
                .col_info, .equal_width, .proportional => col_widths[start_idx..],
            }, .resize_rows = resize_rows },
            .{
                .expand = .both,
                .background = true,
                .max_size_content = .width(main_hbox.data().contentRect().w - 250),
                // TODO: Why is this 250 and not 200? I think the control panel should only be 200 wide.
                // But if I make this 200, the grid walks it's way from -250 to -200 on startup
            },
        );
        defer grid.deinit();
        resize_rows = false;
        const content_w: ?f32 = if (horizontal_scrolling) grid.data().contentRect().w + 1024 else null;
        switch (column_sizing) {
            .equal_width => {
                // Make all columns equal width, except for checbox which stays a fixed width.
                col_widths = @splat(-1);
                col_widths[0] = col_widths_default[0];
            },
            .proportional => {
                @memcpy(&col_widths, &col_widths_proportional);
            },
            .col_info => @memcpy(&col_widths, &col_widths_default),
            .col_width, .expand => {},
        }
        dvui.columnLayoutProportional(grid, col_widths[start_idx..], content_w);
        {
            const first: usize, const last: usize = range: {
                if (virtual_scrolling) {
                    var scroller = dvui.GridWidget.GridVirtualScroller.init(grid, .{ .scroll_info = &scroll_info, .total_rows = cars.len, .window_size = 1 });
                    break :range .{ scroller.rowFirstRendered(), scroller.rowLastRendered() };
                } else {
                    break :range .{ 0, cars.len };
                }
            };
            first_row = first;
            var selection: dvui.GridColumnSelectAllState = undefined;
            var sort_dir: dvui.GridWidget.SortDirection = undefined;
            if (selectable) {
                var col = try grid.column(@src(), colOptions(.{}));
                defer col.deinit();

                if (try dvui.gridHeadingCheckbox(@src(), grid, &selection, .{}, headerCheckboxOptions())) {
                    for (cars[0..]) |*car| {
                        switch (selection) {
                            .select_all => car.selected = true,
                            .select_none => car.selected = false,
                            .unchanged => {},
                        }
                    }
                }

                const changed = try dvui.gridColumnCheckbox(
                    @src(),
                    grid,
                    Car,
                    cars[first..last],
                    "selected",
                    .{ .border = dvui.Rect.all(1) },
                    .{},
                );
                if (changed) std.debug.print("selection changed\n", .{});
            }

            {
                var col = try grid.column(@src(), colOptions(.{}));
                defer col.deinit();
                if (sortable) {
                    if (try dvui.gridHeadingSortable(@src(), grid, "Make", &sort_dir, headerCellOpts(.{ .border = dvui.Rect.all(0) }), .{})) {
                        sort("Make", sort_dir);
                    }
                } else {
                    try dvui.gridHeading(@src(), grid, "Make", headerCellOpts(.{}), .{});
                }
                try dvui.gridColumnFromSlice(@src(), grid, Car, cars[first..last], "make", "{s}", .{ .callback = bandedRows }, .none);
            }
            {
                var col = try grid.column(@src(), colOptions(.{}));
                defer col.deinit();
                if (try dvui.gridHeadingSortable(@src(), grid, "Model", &sort_dir, .{}, .{})) {
                    sort("Model", sort_dir);
                }
                try dvui.gridColumnFromSlice(@src(), grid, Car, cars[first..last], "model", "{s}", .none, .none);
            }
            {
                var col = try grid.column(@src(), colOptions(.{}));
                defer col.deinit();
                if (try dvui.gridHeadingSortable(@src(), grid, "Year", &sort_dir, .{}, .{})) {
                    sort("Year", sort_dir);
                }
                try customColumn(@src(), grid, cars[first..last], .{});
            }
            {
                var col = try grid.column(@src(), colOptions(.{}));
                defer col.deinit();

                if (try dvui.gridHeadingSortable(@src(), grid, "Mileage", &sort_dir, .{}, .{})) {
                    sort("Mileage", sort_dir);
                }
                try dvui.gridColumnFromSlice(@src(), grid, Car, cars[first..last], "mileage", "{d}", bodyCellOpts(.{}), .{ .options = .{ .gravity_x = 1.0 } });
            }
            {
                var col = try grid.column(@src(), colOptions(.{}));
                defer col.deinit();

                if (try dvui.gridHeadingSortable(@src(), grid, "Condition", &sort_dir, .{}, .{})) {
                    sort("Condition", sort_dir);
                }
                try dvui.gridColumnFromSlice(@src(), grid, Car, cars[first..last], "condition", "{s}", bodyCellOpts(.{}), .{ .options = .{ .gravity_x = 0.5 } });
            }
            {
                var col = try grid.column(@src(), .{});
                defer col.deinit();
                if (try dvui.gridHeadingSortable(@src(), grid, "Description", &sort_dir, .{ .border = dvui.Rect.all(0) }, .{ .font_style = .title })) {
                    sort("Description", sort_dir);
                }
                try textAreaColumn(@src(), grid, cars[first..last]);
                //                    try dvui.gridColumnFromSlice(@src(), grid, Car, cars[0..], "description", "{s}", .{}, .{});
            }
        }
    }
    {
        // Control panel
        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .vertical, .min_size_content = .{ .w = 250 }, .max_size_content = .width(250) });
        defer vbox.deinit();
        try dvui.labelNoFmt(@src(), "Control Panel", .{ .font_style = .title_2 });
        _ = try dvui.checkbox(@src(), &sortable, "sortable", .{});
        _ = try dvui.checkbox(@src(), &virtual_scrolling, "virtual scrolling", .{});
        if (try dvui.expander(@src(), "Column Layout", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            var inner_vbox = try dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
            defer inner_vbox.deinit();

            if (try dvui.radio(@src(), column_sizing == .equal_width, "Equal Spacing", .{})) {
                column_sizing = .equal_width;
                resize_rows = true;
            }
            if (try dvui.radio(@src(), column_sizing == .proportional, "Proportional", .{})) {
                column_sizing = .proportional;
                resize_rows = true;
            }
            if (try dvui.radio(@src(), column_sizing == .col_info, "col_info", .{})) {
                column_sizing = .col_info;
                resize_rows = true;
            }
            if (try dvui.radio(@src(), column_sizing == .col_width, "col_width", .{})) {
                column_sizing = .col_width;
                resize_rows = true;
            }
            if (try dvui.radio(@src(), column_sizing == .expand, ".expand", .{})) {
                column_sizing = .expand;
                resize_rows = true;
            }
        }
        _ = try dvui.checkbox(@src(), &horizontal_scrolling, "Horizontal scrolling", .{});
        _ = try dvui.checkbox(@src(), &selectable, "Selection", .{});
        {
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox.deinit();
            try dvui.labelNoFmt(@src(), "Header Height: ", .{});
            const result = try dvui.textEntryNumber(@src(), f32, .{ .value = if (header_height == 0) null else &header_height }, .{});
            if (result.enter_pressed and result.value == .Valid) {
                header_height = result.value.Valid;
            }
        }
        {
            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox.deinit();
            try dvui.labelNoFmt(@src(), "Row Height: ", .{});
            const result = try dvui.textEntryNumber(@src(), f32, .{ .value = if (row_height == 0) null else &row_height }, .{});
            if (result.enter_pressed and result.value == .Valid) {
                row_height = result.value.Valid;
            }
        }
        {
            if (try dvui.expander(@src(), "Populate From", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
                if (try dvui.checkbox(@src(), &filter_grid, "Filter", .{})) {
                    gpa.free(filtered_cars);
                    filtered_cars = try filterCars(gpa, cars[0..], filterLongModels);
                }
            }
        }
    }
}

fn customColumn(src: std.builtin.SourceLocation, g: *dvui.GridWidget, data: []Car, opts: dvui.GridWidget.CellOptions) !void {
    var cell_opts = opts;
    for (data, 0..) |*item, i| {
        cell_opts.color_fill = if (item.year % 2 == 0) .{ .name = .fill_press } else null;
        cell_opts.background = true;
        var cell = try g.bodyCell(
            src,
            i,
            cell_opts,
        );

        defer cell.deinit();
        try dvui.label(@src(), "{d}", .{item.year}, .{
            .id_extra = i,
            .gravity_x = if (item.year % 2 == 0) 0.0 else 1.0,
            .gravity_y = 0.5,
        });
    }
}

fn textAreaColumn(src: std.builtin.SourceLocation, g: *dvui.GridWidget, data: []Car) !void {
    for (data, 0..) |*item, i| {
        var cell = try g.bodyCell(
            src,
            i,
            .{},
        );
        defer cell.deinit();
        var text = try dvui.textLayout(@src(), .{ .break_lines = true }, .{ .expand = .both });
        defer text.deinit();
        try text.addText(item.description, .{ .expand = .both });
    }
}

// TODO: Is it worth providing in-built support for iterator population?
// the grid is laid out by column, so iterator would need to:
// 1) Implement a count if virtual scrolling.
// 2) Implement a reset of use multiple iterators to lay out each column
// Currently filtering uses a slice of pointers instead of iterators, due to the
// awkward interface.
// At least for large array-based data sets, user can store values in a MultiArrayList
// so that it is optimised for iterating through each colunm.
const CarsIterator = struct {
    const FilterFN = *const fn (car: *const Car) bool;
    filter_fn: FilterFN = undefined,
    index: usize,
    cars: []Car,

    pub fn init(_cars: []Car, filter_fn: ?FilterFN) CarsIterator {
        return .{
            .index = 0,
            .cars = _cars,
            .filter_fn = filter_fn orelse filterNone,
        };
    }

    pub fn next(self: *CarsIterator) ?*Car {
        while (self.index < self.cars.len) : (self.index += 1) {
            if (self.filter_fn(&cars[self.index])) {
                self.index += 1;
                return &cars[self.index - 1];
            }
        }
        return null;
    }

    pub fn reset(self: *CarsIterator) void {
        self.index = 0;
    }

    pub fn count(self: *CarsIterator) usize {
        var result_count: usize = 0;
        var count_itr: CarsIterator = .init(self.cars, self.filter_fn);
        while (count_itr.next() != null) {
            result_count += 1;
        }
        return result_count;
    }

    fn filterNone(_: *const Car) bool {
        return true;
    }
};

var filtered_cars: []*Car = undefined;

/// Filter the cars data based on the filter function: const fn (*const Car) bool
/// caller is responsible for freeing the returned slice.
fn filterCars(allocator: std.mem.Allocator, src: []Car, filter_fn: fn (*Car) bool) ![]*Car {
    var result: std.ArrayListUnmanaged(*Car) = try .initCapacity(allocator, src.len);
    for (src) |*car| {
        if (filter_fn(car)) { // TODO: FIX
            result.appendAssumeCapacity(car);
        }
    }
    return result.toOwnedSlice(allocator);
}

fn filterLongModels(car: *const Car) bool {
    return (car.model.len < 10);
}

fn sort(key: []const u8, direction: dvui.GridWidget.SortDirection) void {
    switch (direction) {
        .descending,
        => std.mem.sort(Car, &cars, key, sortDesc),
        .ascending,
        .unsorted,
        => std.mem.sort(Car, &cars, key, sortAsc),
    }
}

fn sortAsc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, lhs.model, rhs.model);
    if (std.mem.eql(u8, key, "Year")) return lhs.year < rhs.year;
    if (std.mem.eql(u8, key, "Mileage")) return lhs.mileage < rhs.mileage;
    if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(lhs.condition) < @intFromEnum(rhs.condition);
    if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, lhs.description, rhs.description);
    // default sort on Make
    return std.mem.lessThan(u8, lhs.make, rhs.make);
}

fn sortDesc(key: []const u8, lhs: Car, rhs: Car) bool {
    if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, rhs.model, lhs.model);
    if (std.mem.eql(u8, key, "Year")) return rhs.year < lhs.year;
    if (std.mem.eql(u8, key, "Mileage")) return rhs.mileage < lhs.mileage;
    if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(rhs.condition) < @intFromEnum(lhs.condition);
    if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, rhs.description, lhs.description);

    // default sort on Make
    return std.mem.lessThan(u8, rhs.make, lhs.make);
}

const Car = struct {
    selected: bool = false,
    model: []const u8,
    make: []const u8,
    year: u32,
    mileage: u32,
    condition: Condition,
    description: []const u8,

    const Condition = enum(u32) { New, Excellent, Good, Fair, Poor };
};

var cars = initCars();
fn initCars() [num_cars]Car {
    comptime var result: [num_cars]Car = undefined;
    comptime {
        @setEvalBranchQuota(num_cars + 1);

        for (0..num_cars) |i| {
            result[i] = some_cars[i % some_cars.len];
            result[i].year = i;
        }
    }
    return result;
}

const some_cars = [_]Car{
    .{ .model = "Civic", .make = "Honda", .year = 2022, .mileage = 8500, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
    .{ .model = "Model 3", .make = "Tesla", .year = 2021, .mileage = 15000, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
    .{ .model = "Camry", .make = "Toyota", .year = 2018, .mileage = 43000, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
    .{ .model = "F-150", .make = "Ford", .year = 2015, .mileage = 78000, .condition = .Fair, .description = "Hauls stuff, occasionally emotions." },
    .{ .model = "Altima", .make = "Nissan", .year = 2010, .mileage = 129000, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
    .{ .model = "Accord", .make = "Honda", .year = 2019, .mileage = 78000, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
    .{ .model = "Impreza", .make = "Subaru", .year = 2016, .mileage = 78000, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
    .{ .model = "Charger", .make = "Dodge", .year = 2014, .mileage = 97000, .condition = .Fair, .description = "Goes fast, stops… usually." },
    .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .mileage = 142000, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
    .{ .model = "Mustang", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
    .{ .model = "CX-5", .make = "Mazda", .year = 2019, .mileage = 32000, .condition = .Excellent, .description = "Zoom zoom, but responsibly." },
    .{ .model = "Outback", .make = "Subaru", .year = 2017, .mileage = 61000, .condition = .Good, .description = "Always looks ready for a camping trip, even when it's not." },
    .{ .model = "Civic", .make = "Honda", .year = 2022, .mileage = 8500, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
    .{ .model = "Model 3", .make = "Tesla", .year = 2021, .mileage = 15000, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
    .{ .model = "Camry", .make = "Toyota", .year = 2018, .mileage = 43000, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
    .{ .model = "F-150", .make = "Ford", .year = 2015, .mileage = 78000, .condition = .Fair, .description = "Hauls stuff, occasionally emotions." },
    .{ .model = "Altima", .make = "Nissan", .year = 2010, .mileage = 129000, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
    .{ .model = "Accord", .make = "Honda", .year = 2019, .mileage = 78000, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
    .{ .model = "Impreza", .make = "Subaru", .year = 2016, .mileage = 78000, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
    .{ .model = "Charger", .make = "Dodge", .year = 2014, .mileage = 97000, .condition = .Fair, .description = "Goes fast, stops… usually." },
    .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .mileage = 142000, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
    .{ .model = "Mustang with a really long name", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
};
var first_row: usize = 0;
fn bandedRows(_: usize, row_num: usize) dvui.GridWidget.CellOptions {
    const result: dvui.GridWidget.CellOptions = .{
        .color_fill = if ((first_row + row_num) % 2 == 0) .{ .name = .fill_press } else null,
        .background = true,
    };
    return result;
}

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
