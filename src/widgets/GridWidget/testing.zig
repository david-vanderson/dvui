const std = @import("std");
const dvui = @import("../../dvui.zig");
const GridWidget = dvui.GridWidget;

test "GridWidget: basic by col" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{ .expand = .both }); // TODO: .expand!
            defer grid.deinit();
            {
                for (0..10) |col| {
                    var cell = grid.headerCell(@src(), col, .{ .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..10) |col| {
                    for (0..10) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{});
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }

            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-basic_by_col.png");
}

test "GridWidget: basic by row" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{ .expand = .both }); // TODO: .expand!
            defer grid.deinit();
            {
                for (0..10) |col| {
                    var cell = grid.headerCell(@src(), col, .{ .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..10) |row| {
                    for (0..10) |col| {
                        var cell = grid.bodyCell(@src(), col, row, .{});
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }

            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-basic_by_row.png");
}

test "GridWidget: empty grid" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            var grid = dvui.grid(@src(), .{ .cols = .numCols(0) }, .{});
            defer grid.deinit();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-empty.png");
}

test "GridWidget: one cell" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();

            var grid = dvui.grid(@src(), .{ .cols = .numCols(1) }, .{ .expand = .both }); // TODO:
            defer grid.deinit();
            var cell = grid.bodyCell(@src(), 0, 0, .{});
            defer cell.deinit();
            dvui.labelNoFmt(@src(), "0:0", .{}, .{});
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-one_cell.png");
}

test "GridWidget: populate by col" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{}); // TODO:
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    var cell = grid.bodyCell(@src(), col, row, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-by_col.png");
}

test "GridWidget: populate by col no expand" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{}); // TODO:
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    var cell = grid.bodyCell(@src(), col, row, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-by_col_no_expand.png");
}

test "GridWidget: populate by row" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{}); // TODO:
            defer grid.deinit();
            for (0..10) |row| {
                for (0..10) |col| {
                    var cell = grid.bodyCell(@src(), col, row, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-by_row.png");
}

test "GridWidget: populate by reverse rol, col" {
    // This should be the most difficult as the layout starts in the bottom right and moves to the top-left.
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{}); // TODO:
            defer grid.deinit();
            for (0..10) |row| {
                for (0..10) |col| {
                    var cell = grid.bodyCell(@src(), 9 - col, 9 - row, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ 9 - col, 9 - row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-by_reverse_row_col.png");
}

test "GridWidget: col out of bounds" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(5) }, .{});
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    var cell = grid.bodyCell(@src(), col, row, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-col_out_of_bounds.png");
}

test "GridWidget: col widths" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var col_widths: [10]f32 = @splat(50);
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .colWidths(&col_widths) }, .{ .expand = .horizontal }); // TODO: No .expand
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    var cell = grid.bodyCell(@src(), col, row, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-col_widths.png");
}

test "GridWidget: cell widths" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            // TODO: This should work without .expand
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{ .expand = .horizontal });
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    var cell = grid.bodyCell(@src(), col, row, .{ .size = .{ .w = 50 } });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-cell_widths.png");
}

test "GridWidget: ignore cell_heights" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{});
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    var cell = grid.bodyCell(@src(), col, row, .{ .size = .{ .h = 200 }, .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-ignore_cell_height.png");
}

test "GridWidget: variable cell_heights by col" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10), .var_row_heights = true }, .{ .expand = .both });
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    const row_f: f32 = @floatFromInt(row);
                    var cell = grid.bodyCell(@src(), col, row, .{ .size = .{ .h = @abs(5 - row_f) * 15 + 30 }, .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-variable_cell_height_col.png");
}

test "GridWidget: variable cell_heights by row" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10), .var_row_heights = true }, .{ .expand = .vertical }); // TODO: no expand
            defer grid.deinit();
            for (0..10) |row| {
                for (0..10) |col| {
                    const row_f: f32 = @floatFromInt(row);
                    var cell = grid.bodyCell(@src(), col, row, .{ .size = .{ .h = @abs(5 - row_f) * 15 + 30 }, .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-variable_cell_height_row.png");
}

test "GridWidget: styling" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{ .expand = .both }); // TODO: no expand
            defer grid.deinit();
            for (0..10) |row| {
                for (0..10) |col| {
                    var cell = grid.bodyCell(@src(), col, row, .{
                        .border = dvui.Rect.all(15),
                        .padding = dvui.Rect.all(15),
                        .margin = dvui.Rect.all(15),
                    });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-styling.png");
}

test "GridWidget: styling empty" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{ .expand = .both }); // TODO: no expand
            defer grid.deinit();
            for (0..10) |row| {
                for (0..10) |col| {
                    var cell = grid.bodyCell(@src(), col, row, .{
                        .border = dvui.Rect.all(15),
                        .padding = dvui.Rect.all(15),
                        .margin = dvui.Rect.all(15),
                    });
                    defer cell.deinit();
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-styling_empty.png");
}

test "GridWidget: heading only" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{ .expand = .both }); // TODO: no expand
            defer grid.deinit();
            for (0..10) |col| {
                var cell = grid.headerCell(@src(), col, .{ .color_fill = .fill_control, .background = true });
                defer cell.deinit();
                dvui.label(@src(), "Col {}", .{col}, .{});
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-heading_only.png");
}

test "GridWidget: body then header" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .{ .cols = .numCols(10) }, .{ .expand = .both }); // TODO: no expand
            defer grid.deinit();
            {
                var cell = grid.bodyCell(@src(), 0, 0, .{});
                defer cell.deinit();
                dvui.labelNoFmt(@src(), "Body", .{}, .{});
            }
            {
                var cell = grid.headerCell(@src(), 0, .{});
                defer cell.deinit();
                dvui.labelNoFmt(@src(), "Header", .{}, .{});
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-body_then_header.png");
}

test "GridWidget: vary header height" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            var grid = dvui.grid(@src(), .{ .cols = .numCols(4) }, .{});
            defer grid.deinit();
            {
                for (0..4) |col| {
                    var cell = grid.headerCell(@src(), col, .{ .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{ .font_style = switch (col) {
                        0 => .title_2,
                        1 => .title_3,
                        2 => .title_1,
                        3 => .title_4,
                        else => unreachable,
                    } });
                }
                for (0..4) |col| {
                    for (0..4) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{});
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }

            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-vary_header_height.png");
}

test "GridWidget: vary row height" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            var grid = dvui.grid(@src(), .{ .cols = .numCols(4) }, .{});
            defer grid.deinit();
            {
                for (0..4) |col| {
                    var cell = grid.headerCell(@src(), col, .{ .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..4) |col| {
                    for (0..4) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{
                            .font_style = switch (row) {
                                0 => .title_2,
                                1 => .title_3,
                                2 => .title_1,
                                3 => .title_4,
                                else => unreachable,
                            },
                        });
                    }
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-vary_row_height.png");
}
