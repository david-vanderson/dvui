const panel_size: Size = .{ .w = 200, .h = 250 };

pub const sample_csv = @embedFile("with_header.csv");

pub fn tableStyling() void {
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
    const rows_visible = dvui.dataGetPtrDefault(null, uniqueId, "rows_visible", bool, true);
    const cols = dvui.dataGetPtrDefault(null, uniqueId, "cols", f32, 5);
    const rows = dvui.dataGetPtrDefault(null, uniqueId, "rows", f32, 100);
    var auto_size: ?dvui.TableWidget.AutoSize = null;
    const auto_size_max = dvui.dataGetPtrDefault(null, uniqueId, "auto_size_max", dvui.Size, .all(0));

    {
        var outer_vbox = dvui.box(@src(), .{}, .{
            .min_size_content = panel_size,
            .max_size_content = .size(panel_size),
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
        var table: dvui.TableWidget = undefined;
        table.init(@src(), .{ .scroll_opts = .{ .horizontal = .auto }, .rows = if (rows_visible.*) @trunc(rows.*) else null }, .{ .expand = if (expand.*) .horizontal else null });
        defer table.deinit();

        if (auto_size) |which| table.autoSize(.{
            .auto = which,
            .max_width = if (auto_size_max.*.w > 0) auto_size_max.*.w else null,
            .max_height = if (auto_size_max.*.h > 0) auto_size_max.*.h else null,
        });

        if (col_header.*) {
            for (0..@trunc(cols.*)) |col| {
                const cell = table.colHeader(col, .{ .border = .all(1) });
                defer cell.deinit();

                dvui.label(@src(), "Column {d}", .{col}, .{ .gravity_x = 0.5 });
            }
        }

        var start_row: usize = 0;
        var end_row: usize = @trunc(rows.*);
        if (rows_visible.*) {
            start_row, end_row = table.rowsVisible();
        }
        for (start_row..end_row) |row| {
            for (0..@trunc(cols.*)) |col| {
                const fill = switch (local.banding) {
                    .none => null,
                    .rows => if (row % 2 == 1) dvui.themeGet().color(.control, .fill_press) else null,
                    .cols => if (col % 2 == 1) dvui.themeGet().color(.control, .fill_press) else null,
                };

                var cell = table.cell(.{ .col = col, .row = row }, .{
                    .margin = .all(local.margin),
                    .border = local.borders,
                    .background = if (local.borders.nonZero() or fill != null) true else false,
                    .padding = .all(local.padding),
                    .color_fill = fill,
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

pub fn tableCSV() void {
    dvui.label(@src(), "Shows column sorting", .{}, .{});

    var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .role = .tab_panel });
    defer outer_hbox.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const col_header = dvui.dataGetPtrDefault(null, uniqueId, "col_header", bool, true);
    var auto_size: ?dvui.TableWidget.AutoSize = null;

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
            .min_size_content = panel_size,
            .max_size_content = .size(panel_size),
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

        var table: dvui.TableWidget = undefined;
        table.init(@src(), .{
            .scroll_opts = .{ .horizontal = .auto },
            .rows = if (csv_table.*) |ct| (if (col_header.*) ct.num_rows -| 1 else ct.num_rows) else 1,
        }, .{});
        defer table.deinit();

        if (auto_size) |which| table.autoSize(.{ .auto = which });

        if (col_header.*) {
            for (0..num_cols) |col| {
                const cell = table.colHeader(col, .{ .border = .all(1) });
                defer cell.deinit();

                if (csv_table.*) |*ct| {
                    if (cell.headerSortable(ct.cell(0, col), .{})) |new_sort| {
                        csv_parse.sortDataRows(ct, 1, col, if (new_sort == .ascending) .ascending else .descending);
                        table.autoSize(.{ .auto = .cols });
                    }
                } else {
                    dvui.label(@src(), "Column", .{}, .{});
                }
            }
        }

        const start_row, const end_row = table.rowsVisible();
        for (start_row..end_row) |row| {
            for (0..num_cols) |col| {
                var cell = table.cell(.{ .col = col, .row = row }, .{ .border = .all(1) });
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

pub fn tableSelection() void {
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

    var table: dvui.TableWidget = undefined;
    table.init(@src(), .{}, .{});
    defer table.deinit();

    if (auto_size) table.autoSize(.{ .auto = .both });

    if (multi_select.*) {
        const cell = table.colHeader(0, .{});
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
        const cell = table.colHeader(1, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Make", .{})) |_| {}
    }
    {
        const cell = table.colHeader(2, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Model", .{})) |_| {}
    }
    {
        const cell = table.colHeader(3, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Year", .{})) |_| {}
    }
    {
        const cell = table.colHeader(4, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Condition", .{})) |_| {}
    }
    {
        const cell = table.colHeader(5, .{ .border = .all(1) });
        defer cell.deinit();

        if (cell.headerSortable("Description", .{})) |_| {}
    }

    var cell_hovered: ?dvui.TableWidget.Cell = null;
    if (row_select.*) {
        // need to transition to the body scroll container to detect events
        table.ensureBodyScroll();
        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatchSimple(e, table.data())) continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .position) {
                        cell_hovered = table.cellFromPoint(me.p);
                        continue;
                    }
                    if (me.action == .press) {
                        if (table.cellFromPoint(me.p)) |cell| {
                            e.handle(@src(), table.data());

                            // move to the checkbox
                            table.moveCursor(0, cell.row);

                            if (all_cars[cell.row].selected) {
                                all_cars[cell.row].selected = false;
                            } else {
                                if (!multi_select.*) {
                                    for (&all_cars) |*car| car.selected = false;
                                }
                                all_cars[cell.row].selected = true;
                            }
                        }
                    }
                },
                else => {},
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
                opts.color_fill = dvui.themeGet().color(.control, .fill_press);
                opts.background = true;
            }
        }

        // Selection
        {
            var cell = table.cell(.{ .col = 0, .row = row, .draw_focus = false }, opts);
            defer cell.deinit();

            const src = @src();
            const id = dvui.parentGet().extendId(src, 0);
            if (cell.grid_focus) dvui.focusWidget(id, null, null);
            if (dvui.checkbox(src, &car.selected, null, .{})) {
                table.moveCursor(0, row); // user might have clicked directly from outside table

                if (!multi_select.* and car.selected == true) {
                    for (&all_cars) |*cart| cart.selected = false;
                    car.selected = true;
                }
            }
        }
        // Make
        {
            var cell = table.cell(.{ .col = 1, .row = row }, opts);
            defer cell.deinit();

            dvui.labelNoFmt(@src(), car.make, .{}, .{});
        }
        // Model
        {
            var cell = table.cell(.{ .col = 2, .row = row }, opts);
            defer cell.deinit();

            dvui.labelNoFmt(@src(), car.model, .{}, .{});
        }
        // Year
        {
            var cell = table.cell(.{ .col = 3, .row = row }, opts);
            defer cell.deinit();

            dvui.label(@src(), "{d}", .{car.year}, .{});
        }
        // Condition
        {
            var cell = table.cell(.{ .col = 4, .row = row }, opts);
            defer cell.deinit();

            const col = switch (car.condition) {
                .New => dvui.Color.fromHex("#4bbfc3"),
                .Excellent => dvui.Color.fromHex("#6ca96c"),
                .Good => dvui.Color.fromHex("#a3b76b"),
                .Fair => dvui.Color.fromHex("#d3b95f"),
                .Poor => dvui.Color.fromHex("#c96b6b"),
            };
            dvui.labelNoFmt(@src(), @tagName(car.condition), .{}, .{ .color_text = col });
        }
        // Description
        {
            var cell = table.cell(.{ .col = 5, .row = row }, opts);
            defer cell.deinit();

            var tl: dvui.TextLayoutWidget = undefined;
            tl.init(@src(), .{ .break_lines = true, .process_events_in_deinit = false }, .{ .expand = .both, .background = false });
            defer tl.deinit();
            tl.addText(car.description, .{});
        }
    }
}

pub fn tableLayout() void {
    var main_box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .style = .window, .background = true, .border = dvui.Rect.all(1) });
    defer main_box.deinit();

    const Datum = struct { x: f64, y1: f64, y2: f64 };
    var data: std.ArrayList(Datum) = .empty;
    if (dvui.dataGetSlice(null, main_box.data().id, "data", []Datum)) |data_last_frame| {
        data = .fromOwnedSlice(data_last_frame);
    } else {
        data.append(dvui.currentWindow().arena(), .{ .x = 0, .y1 = -50, .y2 = 50 }) catch {};
        data.append(dvui.currentWindow().arena(), .{ .x = 25, .y1 = -25, .y2 = 25 }) catch {};
        data.append(dvui.currentWindow().arena(), .{ .x = 50, .y1 = 0, .y2 = 0 }) catch {};
        data.append(dvui.currentWindow().arena(), .{ .x = 75, .y1 = 25, .y2 = -25 }) catch {};
        data.append(dvui.currentWindow().arena(), .{ .x = 100, .y1 = 50, .y2 = -50 }) catch {};
    }

    var title: []u8 = &.{};
    var x_axis_title: []u8 = &.{};
    var y_axis_title: []u8 = &.{};

    {
        var vbox = dvui.box(@src(), .{}, .{ .expand = .vertical, .border = dvui.Rect.all(1) });
        defer vbox.deinit();
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            dvui.labelNoFmt(@src(), "Plot Title:", .{}, .{ .gravity_y = 0.5 });
            var text = dvui.textEntry(@src(), .{}, .{});
            defer text.deinit();
            if (dvui.firstFrame(text.data().id)) text.textSet("X vs Y", false);
            title = text.getText();
        }

        // We are going to put the x/y axis stuff at the bottom first so it
        // always shows.  But need to swap hbox and table tab indexes.
        // First: wrap both hbox and table in a tabIndexGroup
        var main_tig = dvui.tabIndexGroup(@src(), .{});
        defer main_tig.deinit();

        {
            // Second: wrap hbox with a group tab_index of 2
            var tig = dvui.tabIndexGroup(@src(), .{ .tab_index = 2 });
            defer tig.deinit();

            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_y = 1.0 });
            defer hbox.deinit();
            {
                dvui.labelNoFmt(@src(), "X Axis:", .{}, .{ .gravity_y = 0.5 });
                var text = dvui.textEntry(@src(), .{}, .{ .max_size_content = .width(100) });
                defer text.deinit();
                if (dvui.firstFrame(text.data().id)) text.textSet("X", false);
                x_axis_title = text.getText();
            }
            {
                dvui.labelNoFmt(@src(), "Y Axis:", .{}, .{ .gravity_y = 0.5 });
                var text = dvui.textEntry(@src(), .{}, .{ .max_size_content = .width(100) });
                defer text.deinit();
                if (dvui.firstFrame(text.data().id)) text.textSet("Y", false);
                y_axis_title = text.getText();
            }
        }

        {
            // Third (final): wrap table with a group tab_index of 1
            var tig = dvui.tabIndexGroup(@src(), .{ .tab_index = 1 });
            defer tig.deinit();

            var table: dvui.TableWidget = undefined;
            table.init(@src(), .{ .layout_only = true }, .{});
            defer table.deinit();

            {
                const cell = table.colHeader(0, .{ .border = .all(1) });
                defer cell.deinit();
                dvui.label(@src(), "X", .{}, .{ .gravity_x = 0.5 });
            }
            {
                const cell = table.colHeader(1, .{ .border = .all(1) });
                defer cell.deinit();
                dvui.label(@src(), "Y1", .{}, .{ .gravity_x = 0.5 });
            }
            {
                const cell = table.colHeader(2, .{ .border = .all(1) });
                defer cell.deinit();
                dvui.label(@src(), "Y2", .{}, .{ .gravity_x = 0.5 });
            }

            const te_opts: dvui.Options = .{ .min_size_content = dvui.themeGet().font_body.sizeM(7, 1) };

            var row_to_delete: ?usize = null;
            var row_to_add: ?usize = null;

            for (data.items, 0..) |*d, row| {
                {
                    var cell = table.cell(.{ .col = 0, .row = row }, .{});
                    defer cell.deinit();
                    var dbox = dvui.box(@src(), .{}, .{});
                    defer dbox.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = &d.x, .min = 0, .max = 100, .show_min_max = true }, te_opts);
                    var fraction: f32 = @floatCast(d.x / 100);
                    if (dvui.slider(@src(), .{ .fraction = &fraction }, .{ .expand = .horizontal })) {
                        // need two steps or can end up with floating point
                        // weirdness where formatting it into textEntryNumber
                        // next frame gives a lot of decimal points
                        d.x = @round(fraction * 10000);
                        d.x = d.x / 100;
                    }
                }
                {
                    var cell = table.cell(.{ .col = 1, .row = row }, .{});
                    defer cell.deinit();
                    var dbox = dvui.box(@src(), .{}, .{});
                    defer dbox.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = &d.y1, .min = -100, .max = 100, .show_min_max = true }, te_opts);
                    var fraction: f32 = @floatCast(d.y1);
                    fraction += 100;
                    fraction /= 200;
                    if (dvui.slider(@src(), .{ .fraction = &fraction, .color_bar = .red }, .{ .expand = .horizontal })) {
                        // need two steps or can end up with floating point
                        // weirdness where formatting it into textEntryNumber
                        // next frame gives a lot of decimal points
                        d.y1 = @round(fraction * 20000 - 10000);
                        d.y1 = d.y1 / 100;
                    }
                }
                {
                    var cell = table.cell(.{ .col = 2, .row = row }, .{});
                    defer cell.deinit();
                    var dbox = dvui.box(@src(), .{}, .{});
                    defer dbox.deinit();
                    _ = dvui.textEntryNumber(@src(), f64, .{ .value = &d.y2, .min = -100, .max = 100, .show_min_max = true }, te_opts);
                    var fraction: f32 = @floatCast(d.y2);
                    fraction += 100;
                    fraction /= 200;
                    if (dvui.slider(@src(), .{ .fraction = &fraction, .color_bar = .blue }, .{ .expand = .horizontal })) {
                        // need two steps or can end up with floating point
                        // weirdness where formatting it into textEntryNumber
                        // next frame gives a lot of decimal points
                        d.y2 = @round(fraction * 20000 - 10000);
                        d.y2 = d.y2 / 100;
                    }
                }
                {
                    var cell = table.cell(.{ .col = 3, .row = row }, .{});
                    defer cell.deinit();
                    if (dvui.buttonIcon(@src(), "Insert", dvui.entypo.add_to_list, .{}, .{}, .{})) {
                        row_to_add = row + 1;
                    }
                }
                {
                    var cell = table.cell(.{ .col = 4, .row = row }, .{});
                    defer cell.deinit();
                    if (dvui.buttonIcon(@src(), "Delete", dvui.entypo.cross, .{}, .{}, .{})) {
                        row_to_delete = row;
                    }
                }
            }

            if (row_to_add) |row| {
                data.insert(dvui.currentWindow().arena(), row, .{ .x = 50, .y1 = 0, .y2 = 0 }) catch {};
            }
            if (row_to_delete) |row| {
                if (data.items.len > 1) {
                    _ = data.orderedRemove(row);
                } else {
                    data.items[0] = .{ .x = 0, .y1 = 0, .y2 = 0 };
                }
            }
        }
    }

    {
        var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .border = dvui.Rect.all(1) });
        defer vbox.deinit();
        var x_axis: dvui.PlotWidget.Axis = .{ .name = x_axis_title, .min = 0, .max = 100 };
        var min = std.math.floatMax(f64);
        var max = -min;
        for (data.items) |d| {
            min = @min(min, d.y1);
            min = @min(min, d.y2);
            max = @max(max, d.y1);
            max = @max(max, d.y2);
        }
        var y_axis: dvui.PlotWidget.Axis = .{ .name = y_axis_title, .min = min, .max = max };
        var plot = dvui.plot(
            @src(),
            .{
                .title = title,
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
            for (data.items) |d| {
                s1.point(d.x, d.y1);
            }
            s1.stroke(thick, .red);
        }
        {
            var s2 = plot.line();
            defer s2.deinit();
            for (data.items) |d| {
                s2.point(d.x, d.y2);
            }
            s2.stroke(thick, .blue);
        }
    }

    dvui.dataSetSlice(null, main_box.data().id, "data", data.items);
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Size = dvui.Size;
const Rect = dvui.Rect;
const Options = dvui.Options;
const csv_parse = @import("csv_parse.zig");
