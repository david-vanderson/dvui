const panel_size: Size = .{ .w = 200, .h = 250 };

pub fn tableStyling() void {
    const local = struct {
        var borders: Rect = .all(0);
        var banding: Banding = .none;
        var margin: f32 = 0;
        var padding: f32 = 0;
        const Banding = enum { none, rows, cols };
    };

    var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .role = .tab_panel });
    defer outer_hbox.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const col_header = dvui.dataGetPtrDefault(null, uniqueId, "col_header", bool, true);
    const expand = dvui.dataGetPtrDefault(null, uniqueId, "expand", bool, true);
    const rows_visible = dvui.dataGetPtrDefault(null, uniqueId, "rows_visible", bool, true);
    const cols = dvui.dataGetPtrDefault(null, uniqueId, "cols", f32, 5);
    const rows = dvui.dataGetPtrDefault(null, uniqueId, "rows", f32, 100);
    var auto_size = false;

    {
        var outer_vbox = dvui.box(@src(), .{}, .{
            .min_size_content = panel_size,
            .max_size_content = .size(panel_size),
            .expand = .vertical,
            .border = Rect.all(1),
            .gravity_x = 1.0,
        });
        defer outer_vbox.deinit();

        _ = dvui.checkbox(@src(), col_header, "Column Header", .{});
        if (dvui.checkbox(@src(), rows_visible, "Only Visible Rows", .{})) {
            if (!rows_visible.*) rows.* = @min(rows.*, 250);
        }
        if (dvui.button(@src(), "Auto Size", .{}, .{})) {
            auto_size = true;
        }
        _ = dvui.checkbox(@src(), expand, "Expand Horizontal", .{});
        _ = dvui.sliderEntry(@src(), "cols: {d}", .{ .value = cols, .min = 0, .max = 100, .interval = 1 }, .{});
        _ = dvui.sliderEntry(@src(), "rows: {d}", .{ .value = rows, .min = 0, .max = 100_000, .interval = 1 }, .{});

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
                auto_size = true;
            }
            if (dvui.sliderEntry(@src(), "Padding {d}", .{ .value = &local.padding, .min = 0, .max = 10, .interval = 1 }, .{})) {
                auto_size = true;
            }
        }
    }

    {
        var table: dvui.TableWidget = undefined;
        table.init(@src(), .{ .scroll_opts = .{ .horizontal = .auto }, .rows = if (rows_visible.*) @trunc(rows.*) else null }, .{ .expand = if (expand.*) .horizontal else null });
        defer table.deinit();

        if (auto_size) table.autoSize();

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

                var cell = table.cell(col, row, .{
                    .margin = .all(local.margin),
                    .border = local.borders,
                    .background = if (local.borders.nonZero() or fill != null) true else false,
                    .padding = .all(local.padding),
                    .color_fill = fill,
                });
                defer cell.deinit();

                const txt = dvui.dataGetSlice(null, cell.data().id, "data", []u8) orelse std.fmt.allocPrint(dvui.currentWindow().arena(), "Cell {d} {d}", .{ col, row }) catch "Error";

                if (cell.editable(txt, .{})) |new_text| {
                    dvui.dataSetSlice(null, cell.data().id, "data", new_text);
                }
            }
        }
    }
}

pub fn tableCSV() void {
    var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .role = .tab_panel });
    defer outer_hbox.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const csv_table = dvui.dataGetPtrDefault(null, uniqueId, "csv", ?csv_parse.Table, null);
    const col_header = dvui.dataGetPtrDefault(null, uniqueId, "col_header", bool, true);
    var auto_size = false;

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

        if (dvui.button(@src(), "Load CSV", .{}, .{})) {
            if (csv_table.*) |ct| {
                dvui.currentWindow().gpa.free(ct.src);
                dvui.currentWindow().gpa.free(ct.cells);
                csv_table.* = null;
            }

            const filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{
                .title = "Load CSV",
                .filters = &.{"*.csv"},
                .filter_description = "csv files",
            }) catch @panic("dialogNative");
            if (filename) |f| {
                const csv_content = std.Io.Dir.cwd().readFileAlloc(dvui.io, f, dvui.currentWindow().gpa, .unlimited) catch @panic("OOM");
                errdefer dvui.currentWindow().gpa.free(csv_content);
                errdefer csv_table.* = null;

                csv_table.* = csv_parse.parse(dvui.currentWindow().gpa, csv_content) catch @panic("OOM");
                auto_size = true;
            }
        }

        if (dvui.checkbox(@src(), col_header, "1st Row Header", .{})) {
            auto_size = true;
        }

        if (dvui.button(@src(), "Auto Size", .{}, .{})) {
            auto_size = true;
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

        if (auto_size) table.autoSize();

        if (col_header.*) {
            for (0..num_cols) |col| {
                const cell = table.colHeader(col, .{ .border = .all(1) });
                defer cell.deinit();

                if (csv_table.*) |*ct| {
                    if (cell.headerSortable(ct.cell(0, col), .{})) |new_sort| {
                        csv_parse.sortDataRows(ct, 1, col, if (new_sort == .ascending) .ascending else .descending);
                        table.autoSize();
                    }
                } else {
                    dvui.label(@src(), "Column", .{}, .{});
                }
            }
        }

        const start_row, const end_row = table.rowsVisible();
        for (start_row..end_row) |row| {
            for (0..num_cols) |col| {
                var cell = table.cell(col, row, .{ .border = .all(1) });
                defer cell.deinit();

                if (csv_table.*) |ct| {
                    const r = if (col_header.*) row + 1 else row;
                    dvui.label(@src(), "{s}", .{ct.cell(r, col)}, .{});
                }
            }
        }
    }
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Size = dvui.Size;
const Rect = dvui.Rect;
const Options = dvui.Options;
const csv_parse = @import("csv_parse.zig");
