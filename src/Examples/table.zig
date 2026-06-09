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
        table.init(@src(), .{ .scroll_opts = .{ .horizontal = .auto }, .rows = if (rows_visible.*) @trunc(rows.*) else null }, .{});
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

const std = @import("std");
const dvui = @import("../dvui.zig");
const Size = dvui.Size;
const Rect = dvui.Rect;
const Options = dvui.Options;
