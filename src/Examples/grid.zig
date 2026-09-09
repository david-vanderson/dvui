pub const sample_csv = @embedFile("with_header.csv");

pub fn gridStyling() void {
    const local = struct {
        var borders: Rect = .all(0);
        var banding: Banding = .none;
        var margin: f32 = 0;
        var padding: f32 = 0;
        const Banding = enum { none, rows, cols };
    };

    dvui.label(@src(), "Shows editing and styling", .{}, .{});

    var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .role = .tab_panel });
    defer outer_hbox.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const col_header = dvui.dataGetPtrDefault(null, uniqueId, "col_header", bool, true);
    const expand = dvui.dataGetPtrDefault(null, uniqueId, "expand", bool, true);
    const expand_cols = dvui.dataGetPtrDefault(null, uniqueId, "expand_cols", bool, false);
    const resizable = dvui.dataGetPtrDefault(null, uniqueId, "resizable", bool, true);
    const rows_visible = dvui.dataGetPtrDefault(null, uniqueId, "rows_visible", bool, true);
    const cols = dvui.dataGetPtrDefault(null, uniqueId, "cols", f32, 5);
    const rows = dvui.dataGetPtrDefault(null, uniqueId, "rows", f32, 100);
    var auto_size: ?dvui.GridWidget.AutoSize = null;
    const auto_size_max = dvui.dataGetPtrDefault(null, uniqueId, "auto_size_max", dvui.Size, .{ .w = 200, .h = 60 });

    {
        var outer_vbox = dvui.box(@src(), .{}, .{
            .expand = .vertical,
            .border = Rect.all(1),
            .gravity_x = 1.0,
        });
        defer outer_vbox.deinit();

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
        defer scroll.deinit();

        _ = dvui.checkbox(@src(), col_header, "Column Header", .{});
        if (dvui.checkbox(@src(), rows_visible, "Only Visible Rows", .{})) {
            if (!rows_visible.*) rows.* = @min(rows.*, 250);
        }
        _ = dvui.checkbox(@src(), expand, "Expand Horizontal", .{});
        _ = dvui.checkbox(@src(), expand_cols, "Expand Cols", .{});
        _ = dvui.checkbox(@src(), resizable, "Resizable", .{});
        _ = dvui.sliderEntry(@src(), "cols: {d}", .{ .value = cols, .min = 0, .max = 100, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "rows: {d}", .{ .value = rows, .min = 0, .max = 100_000, .interval = 1 }, .{});

        if (dvui.expander(@src(), "Auto Size", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            if (dvui.button(@src(), "Auto Size Both", .{}, .{})) {
                auto_size = .both;
            }
            if (dvui.button(@src(), "Auto Size Rows", .{}, .{})) {
                auto_size = .rows;
            }
            if (dvui.button(@src(), "Auto Size Cols", .{}, .{})) {
                auto_size = .cols;
            }
            _ = dvui.sliderEntry(@src(), "max w: {d}", .{ .value = &auto_size_max.*.w, .min = 0, .max = 500, .interval = 1 }, .{});
            _ = dvui.sliderEntry(@src(), "max h: {d}", .{ .value = &auto_size_max.*.h, .min = 0, .max = 500, .interval = 1 }, .{});
        }

        if (dvui.expander(@src(), "Borders", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            var top: bool = local.borders.y > 0;
            var bottom: bool = local.borders.h > 0;
            var left: bool = local.borders.x > 0;
            var right: bool = local.borders.w > 0;
            var fbox = dvui.flexbox(@src(), .{ .justify_content = .start }, .{});
            defer fbox.deinit();
            {
                var vbox = dvui.box(@src(), .{}, .{ .expand = .horizontal });
                defer vbox.deinit();
                _ = dvui.checkbox(@src(), &top, "Top", .{});
                _ = dvui.checkbox(@src(), &left, "Left", .{});
            }
            {
                var vbox = dvui.box(@src(), .{}, .{ .expand = .horizontal });
                defer vbox.deinit();
                _ = dvui.checkbox(@src(), &right, "Right", .{});
                _ = dvui.checkbox(@src(), &bottom, "Bottom", .{});
            }
            local.borders = .{
                .y = if (top) 1 else 0,
                .h = if (bottom) 1 else 0,
                .x = if (left) 1 else 0,
                .w = if (right) 1 else 0,
            };
        }
        if (dvui.expander(@src(), "Banding", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            if (dvui.radio(@src(), local.banding == .none, "None", .{})) {
                local.banding = .none;
            }
            if (dvui.radio(@src(), local.banding == .rows, "Rows", .{})) {
                local.banding = .rows;
            }
            if (dvui.radio(@src(), local.banding == .cols, "Cols", .{})) {
                local.banding = .cols;
            }
        }
        if (dvui.expander(@src(), "Other", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
            if (dvui.sliderEntry(@src(), "Margin {d}", .{ .value = &local.margin, .min = 0, .max = 10, .interval = 1 }, .{})) {
                auto_size = .both;
            }
            if (dvui.sliderEntry(@src(), "Padding {d}", .{ .value = &local.padding, .min = 0, .max = 10, .interval = 1 }, .{})) {
                auto_size = .both;
            }
        }
    }

    {
        var grid: dvui.GridWidget = undefined;
        grid.init(@src(), .{ .scroll_opts = .{ .horizontal = .auto }, .rows = if (rows_visible.*) @trunc(rows.*) else null }, .{ .expand = if (expand.*) .horizontal else null });
        defer grid.deinit();

        if (auto_size) |which| grid.autoSize(which);

        if (col_header.*) {
            for (0..@trunc(cols.*)) |col| {
                const cell = grid.colHeader(.{ .col = col, .resizable = resizable.* }, .{ .border = .all(1), .expand = if (expand_cols.*) .horizontal else .none });
                defer cell.deinit();

                dvui.label(@src(), "Column {d}", .{col}, .{ .gravity_x = 0.5 });
            }
        }

        var start_row: usize = 0;
        var end_row: usize = @trunc(rows.*);
        if (rows_visible.*) {
            start_row, end_row = grid.rowsVisible();
        }
        for (start_row..end_row) |row| {
            for (0..@trunc(cols.*)) |col| {
                const fill: ?dvui.ColorOrGradient = switch (local.banding) {
                    .none => null,
                    .rows => if (row % 2 == 1) .{ .color = dvui.themeGet().color(.control, .fill_press) } else null,
                    .cols => if (col % 2 == 1) .{ .color = dvui.themeGet().color(.control, .fill_press) } else null,
                };

                var cell = grid.cell(.{ .col = col, .row = row }, .{
                    .margin = .all(local.margin),
                    .border = local.borders,
                    .background = if (local.borders.nonZero() or fill != null) true else false,
                    .padding = .all(local.padding),
                    .color_fill = fill,
                    .expand = if (expand_cols.*) .horizontal else .none,
                    .max_size_content = .size(auto_size_max.*),
                });
                defer cell.deinit();

                const extra = " Hello this is a bunch of text that we are going to add to one cell to show text wrapping and auto sizing changes.";
                const txt = dvui.dataGetSlice(null, cell.data().id, "data", []u8) orelse std.fmt.allocPrint(dvui.currentWindow().arena(), "Cell {d} {d}{s}", .{ col, row, if (row == 5 and col == 1) extra else "" }) catch "Error";

                if (cell.editable(txt, .{})) |new_text| {
                    dvui.dataSetSlice(null, cell.data().id, "data", new_text);
                }
            }
        }
    }
}

pub fn gridCSV() void {
    dvui.label(@src(), "Shows column sorting", .{}, .{});

    var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .role = .tab_panel });
    defer outer_hbox.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const col_header = dvui.dataGetPtrDefault(null, uniqueId, "col_header", bool, true);
    var auto_size: ?dvui.GridWidget.AutoSize = null;

    const csv_table = dvui.dataGetPtr(null, uniqueId, "csv", ?csv_parse.Table) orelse blk: {
        const src = dvui.currentWindow().gpa.dupe(u8, sample_csv) catch @panic("OOM");
        const ct: ?csv_parse.Table = csv_parse.parse(dvui.currentWindow().gpa, src) catch @panic("OOM");
        dvui.dataSet(null, uniqueId, "csv", ct);
        break :blk dvui.dataGetPtr(null, uniqueId, "csv", ?csv_parse.Table).?;
    };

    if (dvui.firstFrame(outer_hbox.data().id)) {
        dvui.dataSetDeinitFunction(null, uniqueId, "csv", (struct {
            pub fn deinit(ptr: *anyopaque) void {
                const self: *?csv_parse.Table = @ptrCast(@alignCast(ptr));
                if (self.*) |ct| {
                    dvui.currentWindow().gpa.free(ct.src);
                    dvui.currentWindow().gpa.free(ct.cells);
                    self.* = null;
                }
            }
        }).deinit);
    }

    {
        var outer_vbox = dvui.box(@src(), .{}, .{
            .expand = .vertical,
            .border = Rect.all(1),
            .gravity_x = 1.0,
        });
        defer outer_vbox.deinit();

        const single_file_id = outer_vbox.widget().extendId(@src(), 0);

        if (dvui.button(@src(), "Load CSV", .{}, .{})) {
            if (dvui.backend.kind == .web) {
                dvui.dialogWasmFileOpen(single_file_id, .{ .accept = ".csv" });
            } else if (!dvui.useTinyFileDialogs) {
                dvui.toast(@src(), .{ .subwindow_id = dvui.subwindowCurrentId(), .message = "Tiny File Dilaogs disabled" });
            } else {
                const filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{
                    .title = "Load CSV",
                    .filters = &.{"*.csv"},
                    .filter_description = "csv files",
                }) catch @panic("dialogNative");
                if (filename) |f| {
                    const csv_content = std.Io.Dir.cwd().readFileAlloc(dvui.io, f, dvui.currentWindow().gpa, .unlimited) catch @panic("OOM");

                    if (csv_table.*) |ct| {
                        dvui.currentWindow().gpa.free(ct.src);
                        dvui.currentWindow().gpa.free(ct.cells);
                        csv_table.* = null;
                    }

                    errdefer dvui.currentWindow().gpa.free(csv_content);
                    errdefer csv_table.* = null;

                    csv_table.* = csv_parse.parse(dvui.currentWindow().gpa, csv_content) catch @panic("OOM");
                    auto_size = .both;
                }
            }

            if (dvui.backend.kind == .web) {
                if (dvui.wasmFileUploaded(single_file_id)) |file| {
                    const src = file.readData(dvui.currentWindow().gpa) catch @panic("OOM");

                    if (csv_table.*) |ct| {
                        dvui.currentWindow().gpa.free(ct.src);
                        dvui.currentWindow().gpa.free(ct.cells);
                        csv_table.* = null;
                    }

                    errdefer dvui.currentWindow().gpa.free(src);
                    errdefer csv_table.* = null;

                    csv_table.* = csv_parse.parse(dvui.currentWindow().gpa, src) catch @panic("OOM");
                    auto_size = .both;
                }
            }
        }

        if (dvui.checkbox(@src(), col_header, "1st Row Header", .{})) {
            // needed in case we are adding a header for the first time
            auto_size = .rows;
        }

        if (dvui.button(@src(), "Auto Size", .{}, .{})) {
            auto_size = .both;
        }
    }

    {
        const num_cols = if (csv_table.*) |ct| ct.num_cols else 1;

        var grid = dvui.grid(@src(), .{
            .scroll_opts = .{ .horizontal = .auto },
            .rows = if (csv_table.*) |ct| (if (col_header.*) ct.num_rows -| 1 else ct.num_rows) else 1,
        }, .{ .expand = .horizontal });
        defer grid.deinit();

        if (auto_size) |which| grid.autoSize(which);

        if (col_header.*) {
            for (0..num_cols) |col| {
                const cell = grid.colHeader(.{ .col = col }, .{ .border = .all(1) });
                defer cell.deinit();

                if (csv_table.*) |*ct| {
                    if (cell.headerSortable(ct.cell(0, col), .{})) |new_sort| {
                        csv_parse.sortDataRows(ct, 1, col, if (new_sort == .ascending) .ascending else .descending);
                    }
                } else {
                    dvui.label(@src(), "Column", .{}, .{});
                }
            }
        }

        const start_row, const end_row = grid.rowsVisible();
        for (start_row..end_row) |row| {
            for (0..num_cols) |col| {
                var cell = grid.cell(.{ .col = col, .row = row }, .{ .border = .all(1) });
                defer cell.deinit();

                if (csv_table.*) |ct| {
                    const r = if (col_header.*) row + 1 else row;
                    dvui.label(@src(), "{s}", .{ct.cell(r, col)}, .{});
                }
            }
        }
    }
}

const Car = struct {
    selected: bool = false,
    model: []const u8,
    make: []const u8,
    year: u32,
    mileage: u32,
    condition: Condition,
    description: []const u8,

    const Condition = enum { Poor, Fair, Good, Excellent, New };

    pub fn sortAsc(key: []const u8, lhs: Car, rhs: Car) bool {
        if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, lhs.model, rhs.model);
        if (std.mem.eql(u8, key, "Year")) return lhs.year < rhs.year;
        if (std.mem.eql(u8, key, "Mileage")) return lhs.mileage < rhs.mileage;
        if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(lhs.condition) < @intFromEnum(rhs.condition);
        if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, lhs.description, rhs.description);
        // default sort on Make
        return std.mem.lessThan(u8, lhs.make, rhs.make);
    }

    pub fn sortDesc(key: []const u8, lhs: Car, rhs: Car) bool {
        if (std.mem.eql(u8, key, "Model")) return std.mem.lessThan(u8, rhs.model, lhs.model);
        if (std.mem.eql(u8, key, "Year")) return rhs.year < lhs.year;
        if (std.mem.eql(u8, key, "Mileage")) return rhs.mileage < lhs.mileage;
        if (std.mem.eql(u8, key, "Condition")) return @intFromEnum(rhs.condition) < @intFromEnum(lhs.condition);
        if (std.mem.eql(u8, key, "Description")) return std.mem.lessThan(u8, rhs.description, lhs.description);
        // default sort on Make
        return std.mem.lessThan(u8, rhs.make, lhs.make);
    }
};

var all_cars = [_]Car{
    .{ .model = "Civic", .make = "Honda", .year = 2022, .mileage = 8500, .condition = .New, .description = "Still smells like optimism and plastic wrap." },
    .{ .model = "Model 3", .make = "Tesla", .year = 2021, .mileage = 15000, .condition = .Excellent, .description = "Drives itself better than I drive myself." },
    .{ .model = "Camry", .make = "Toyota", .year = 2018, .mileage = 43000, .condition = .Good, .description = "Reliable enough to make your toaster jealous." },
    .{ .model = "F-150", .make = "Ford", .year = 2015, .mileage = 78000, .condition = .Fair, .description = "Hauls stuff, occasional emotions." },
    .{ .model = "Altima", .make = "Nissan", .year = 2010, .mileage = 129000, .condition = .Poor, .description = "Drives like it’s got beef with the road." },
    .{ .model = "Accord", .make = "Honda", .year = 2019, .mileage = 78000, .condition = .Excellent, .description = "Sensible and smooth, like your friend with a Costco card." },
    .{ .model = "Impreza", .make = "Subaru", .year = 2016, .mileage = 78000, .condition = .Good, .description = "All-wheel drive and all-weather vibes." },
    .{ .model = "Charger", .make = "Dodge", .year = 2014, .mileage = 97000, .condition = .Fair, .description = "Goes fast, stops… usually." },
    .{ .model = "Beetle", .make = "Volkswagen", .year = 2006, .mileage = 142000, .condition = .Poor, .description = "Quirky, creaky, and still kinda cute." },
    .{ .model = "Mustang", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
    .{ .model = "CX-5", .make = "Mazda", .year = 2019, .mileage = 32000, .condition = .Excellent, .description = "Zoom zoom, but responsibly." },
    .{ .model = "Outback", .make = "Subaru", .year = 2017, .mileage = 61000, .condition = .Good, .description = "Always looks ready for a camping trip, even when it's not." },
    .{ .model = "Mustang with a really long name", .make = "Ford", .year = 2020, .mileage = 24000, .condition = .Good, .description = "Makes you feel 20% cooler just sitting in it." },
};

pub fn gridSelection() void {
    var outer_box = dvui.box(@src(), .{}, .{ .expand = .both, .role = .tab_panel });
    defer outer_box.deinit();

    const multi_select = dvui.dataGetPtrDefault(null, outer_box.data().id, "multi_select", bool, true);
    const row_select = dvui.dataGetPtrDefault(null, outer_box.data().id, "row_select", bool, true);

    var auto_size = false;
    var filter: []u8 = &.{};
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer hbox.deinit();

        dvui.label(@src(), "Filter", .{}, .{ .gravity_y = 0.5 });

        var te = dvui.textEntry(@src(), .{}, .{ .label = .{ .label_widget = .prev } });
        filter = te.textGet();
        te.deinit();

        _ = dvui.checkbox(@src(), multi_select, "Multi Select", .{ .gravity_y = 0.5 });
        _ = dvui.checkbox(@src(), row_select, "Row Select", .{ .gravity_y = 0.5 });

        if (dvui.button(@src(), "Auto Size", .{}, .{})) {
            auto_size = true;
        }
    }

    const last_focus = dvui.lastFocusedIdInFrame();

    var grid = dvui.grid(@src(), .{}, .{ .expand = .horizontal });
    defer grid.deinit();

    if (auto_size) grid.autoSize(.both);

    if (multi_select.*) {
        const cell = grid.colHeader(.{ .col = 0, .resizable = false }, .{});
        defer cell.deinit();

        var all_selected = true;
        for (all_cars) |car| {
            if (!car.selected) all_selected = false;
        }
        if (dvui.checkbox(@src(), &all_selected, null, .{})) {
            for (&all_cars) |*car| car.selected = all_selected;
        }
    }
    {
        const cell = grid.colHeader(.{ .col = 1 }, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Make", .{})) |sort_dir| {
            if (sort_dir == .ascending) {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Make"), Car.sortAsc);
            } else {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Make"), Car.sortDesc);
            }
        }
    }
    {
        const cell = grid.colHeader(.{ .col = 2 }, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Model", .{})) |sort_dir| {
            if (sort_dir == .ascending) {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Model"), Car.sortAsc);
            } else {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Model"), Car.sortDesc);
            }
        }
    }
    {
        const cell = grid.colHeader(.{ .col = 3 }, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Year", .{})) |sort_dir| {
            if (sort_dir == .ascending) {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Year"), Car.sortAsc);
            } else {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Year"), Car.sortDesc);
            }
        }
    }
    {
        const cell = grid.colHeader(.{ .col = 4 }, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Condition", .{})) |sort_dir| {
            if (sort_dir == .ascending) {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Condition"), Car.sortAsc);
            } else {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Condition"), Car.sortDesc);
            }
        }
    }
    {
        const cell = grid.colHeader(.{ .col = 5 }, .{ .border = .all(1), .expand = .horizontal });
        defer cell.deinit();

        if (cell.headerSortable("Description", .{})) |sort_dir| {
            if (sort_dir == .ascending) {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Description"), Car.sortAsc);
            } else {
                std.mem.sort(Car, &all_cars, @as([]const u8, "Description"), Car.sortDesc);
            }
        }
    }

    var cell_hovered: ?dvui.GridWidget.Cell = null;
    if (row_select.*) cell_hovered = grid.cellHovered();

    if (row_select.*) {
        if (grid.cellActivated()) |ca| {
            if (all_cars[ca.cell.row].selected) {
                all_cars[ca.cell.row].selected = false;
            } else {
                if (!multi_select.*) {
                    for (&all_cars) |*car| car.selected = false;
                }
                all_cars[ca.cell.row].selected = true;
            }
        }
    }

    var row: usize = 0;
    for (&all_cars) |*car| {
        if (filter.len != 0 and std.mem.find(u8, car.description, filter) == null and std.mem.find(u8, car.make, filter) == null and std.mem.find(u8, car.model, filter) == null)
            continue;

        defer row += 1;

        var opts: dvui.Options = .{};
        if (cell_hovered) |cell| {
            if (cell.row == row) {
                opts.color_fill = .{ .color = dvui.themeGet().color(.control, .fill_press) };
                opts.background = true;

                // this makes keyboard nav pickup from wherever the mouse ended
                grid.ensureFocus();
                grid.moveCursor(0, cell.row);
            }
        }

        // Selection
        {
            var cell = grid.cell(.{ .col = 0, .row = row, .draw_focus = false }, opts);
            defer cell.deinit();

            const src = @src();
            const id = dvui.parentGet().extendId(src, 0);
            cell.focusOnWidget(.{ .id = id, .row = row_select.* });
            // checkbox is focused by focusOnWidget, remove it from the normal tab index
            if (dvui.checkbox(src, &car.selected, null, .{ .tab_index = 0 })) {
                if (!multi_select.* and car.selected == true) {
                    for (&all_cars) |*cart| cart.selected = false;
                    car.selected = true;
                }
            }
        }
        // Make
        {
            var cell = grid.cell(.{ .col = 1, .row = row }, opts);
            defer cell.deinit();

            dvui.labelNoFmt(@src(), car.make, .{}, .{});
        }
        // Model
        {
            var cell = grid.cell(.{ .col = 2, .row = row }, opts);
            defer cell.deinit();

            dvui.labelNoFmt(@src(), car.model, .{}, .{});
        }
        // Year
        {
            var cell = grid.cell(.{ .col = 3, .row = row }, opts);
            defer cell.deinit();

            dvui.label(@src(), "{d}", .{car.year}, .{});
        }
        // Condition
        {
            var cell = grid.cell(.{ .col = 4, .row = row }, opts);
            defer cell.deinit();

            const col = switch (car.condition) {
                .New => dvui.Color.fromHex("#4bbfc3"),
                .Excellent => dvui.Color.fromHex("#6ca96c"),
                .Good => dvui.Color.fromHex("#a3b76b"),
                .Fair => dvui.Color.fromHex("#d3b95f"),
                .Poor => dvui.Color.fromHex("#c96b6b"),
            };
            dvui.labelNoFmt(@src(), @tagName(car.condition), .{}, .{ .color_text = .{ .color = col } });
        }
        // Description
        {
            var cell = grid.cell(.{ .col = 5, .row = row }, opts);
            defer cell.deinit();

            var tl: dvui.TextLayoutWidget = undefined;
            tl.init(@src(), .{ .break_lines = true, .process_events_in_deinit = false }, .{ .expand = .both, .background = false });
            defer tl.deinit();
            tl.addText(car.description, .{});
        }
    }

    if (dvui.lastFocusedIdInFrameSince(last_focus)) |wid| {
        for (dvui.events()) |*e| {
            switch (e.evt) {
                .key => |ke| {
                    if (ke.action == .down and ke.matchBind("select_all")) {
                        if (dvui.eventMatch(e, .{ .id = wid, .r = .{} })) {
                            e.handle(@src(), grid.data());
                            dvui.refresh(null, @src(), wid);

                            for (&all_cars) |*car| car.selected = true;
                        }
                    }
                },
                else => {},
            }
        }
    }
}

pub fn gridLayout() void {
    dvui.label(@src(), "Layout widgets in a grid.", .{}, .{});

    var main_box = dvui.box(@src(), .{}, .{ .style = .window, .border = dvui.Rect.all(1) });
    defer main_box.deinit();

    var grid = dvui.grid(@src(), .{ .layout_only = true }, .{ .expand = .both });

    var row: usize = 0;
    var wd: dvui.WidgetData = undefined;

    {
        var cell = grid.cell(.{ .col = 0, .row = row }, .{});
        defer cell.deinit();

        dvui.label(@src(), "Name", .{}, .{ .gravity_y = 0.5, .data_out = &wd });
    }
    {
        var cell = grid.cell(.{ .col = 1, .row = row }, .{});
        defer cell.deinit();

        var te = dvui.textEntry(@src(), .{}, .{ .label = .{ .by_id = wd.id } });
        te.deinit();
    }

    row += 1;

    {
        var cell = grid.cell(.{ .col = 0, .row = row }, .{});
        defer cell.deinit();

        dvui.label(@src(), "Favorite Animal", .{}, .{ .gravity_y = 0.5, .data_out = &wd });
    }
    {
        var cell = grid.cell(.{ .col = 1, .row = row }, .{});
        defer cell.deinit();

        var te = dvui.textEntry(@src(), .{}, .{ .label = .{ .by_id = wd.id } });
        te.deinit();
    }

    row += 1;

    {
        var cell = grid.cell(.{ .col = 1, .row = row }, .{ .max_size_content = .width(200) });
        defer cell.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{});
        defer tl.deinit();

        tl.addText("Here is a bunch of explanatory text in a textLayout.  I guess it doesn't really explain, just demonstrate.", .{});
    }

    row += 1;

    {
        var cell = grid.cell(.{ .col = 0, .row = row }, .{});
        defer cell.deinit();

        dvui.label(@src(), "Reason for Favoritism", .{}, .{ .gravity_y = 0.5, .data_out = &wd });
    }
    {
        var cell = grid.cell(.{ .col = 1, .row = row }, .{});
        defer cell.deinit();

        const dropdown_val: *?usize = dvui.dataGetPtrDefault(null, cell.data().id, "choice", ?usize, null);

        const entries = [_][]const u8{ "Cute", "Scary", "Super Weird", "Good Pet", "Great Pictures" };

        _ = dvui.dropdown(@src(), &entries, .{ .choice_nullable = dropdown_val }, .{ .placeholder = "Choose..." }, .{});
    }

    row += 1;
    {
        var cell = grid.cell(.{ .col = 0, .row = row }, .{});
        defer cell.deinit();

        dvui.label(@src(), "Comments", .{}, .{ .gravity_y = 0.5, .data_out = &wd });
    }
    {
        var cell = grid.cell(.{ .col = 1, .row = row }, .{ .min_size_content = .{ .w = 300, .h = 200 }, .max_size_content = .width(500) });
        defer cell.deinit();

        var te = dvui.textEntry(@src(), .{ .multiline = true }, .{ .label = .{ .by_id = wd.id }, .expand = .both });
        te.deinit();
    }

    grid.deinit();

    if (dvui.button(@src(), "Fake Submit", .{}, .{ .gravity_x = 0.5, .margin = .all(10), .style = .highlight })) {
        dvui.dialog(@src(), .{}, .{ .title = "Fake Form", .ok_label = "Ok", .message = "This is a fake form, nothing was done." });
    }
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Size = dvui.Size;
const Rect = dvui.Rect;
const Options = dvui.Options;
const csv_parse = @import("csv_parse.zig");
