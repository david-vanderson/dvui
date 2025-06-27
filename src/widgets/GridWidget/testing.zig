const std = @import("std");
const dvui = @import("../../dvui.zig");
const GridWidget = dvui.GridWidget;

test "basic by col" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "basic by row" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "empty grid" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(0), .{}, .{});
            defer grid.deinit();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-empty.png");
}

test "one cell" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(1), .{}, .{});
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

test "populate by col expand" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{ .expand = .both });
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
    try t.saveImage(frame, null, "GridWidget-by_col_expand.png");
}

test "populate by col no expand" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "populate by row" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "populate by reverse rol, col" {
    // This should be the most difficult as the layout starts in the bottom right and moves to the top-left.
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "col out of bounds" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(5), .{}, .{});
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

test "col widths" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var col_widths: [10]f32 = @splat(50);
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .colWidths(&col_widths), .{}, .{});
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

test "cell widths" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "cell heights non variable" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |row| {
                    const row_f: f32 = @floatFromInt(row);
                    var cell = grid.bodyCell(@src(), col, row, .{ .size = .{ .h = 20 * row_f }, .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-cell_height_nonvar.png");
}

test "cell heights non variable reverse" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            for (0..10) |col| {
                for (0..10) |i| {
                    const i_f: f32 = @floatFromInt(i);
                    const row = 9 - i;
                    var cell = grid.bodyCell(@src(), col, row, .{ .size = .{ .h = 20 * i_f }, .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-cell_height_nonvar_rev.png");
}

test "variable cell_heights by col" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{ .var_row_heights = true }, .{});
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
    try t.saveImage(frame, null, "GridWidget-cell_height_var.png");
}

test "variable cell_heights by row" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{ .var_row_heights = true }, .{});
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

test "styling" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "styling empty" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "heading only" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            for (0..10) |col| {
                var cell = grid.headerCell(@src(), col, .{ .color_fill = .fill_control, .background = true, .border = dvui.Rect.all(1) });
                defer cell.deinit();
                dvui.label(@src(), "Col {}", .{col}, .{});
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-heading_only.png");
}

test "body then header" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
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

test "vary header height" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(4), .{}, .{});
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

test "vary row height" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(4), .{}, .{});
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

test "sparse" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            {
                for (0..10) |col_row| {
                    var cell = grid.bodyCell(@src(), col_row, col_row, .{
                        .border = dvui.Rect.all(1),
                    });
                    defer cell.deinit();
                    dvui.label(@src(), "{[col_row]}:{[col_row]}", .{ .col_row = col_row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-sparse.png");
}

test "sparse reverse" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            {
                for (0..10) |i| {
                    const col_row = 9 - i;
                    var cell = grid.bodyCell(@src(), col_row, col_row, .{
                        .border = dvui.Rect.all(1),
                    });
                    defer cell.deinit();
                    dvui.label(@src(), "{[col_row]}:{[col_row]}", .{ .col_row = col_row }, .{});
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-sparse_reverse.png");
}

test "more header cells than body cells" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(4), .{}, .{});
            defer grid.deinit();
            {
                for (0..4) |col| {
                    var cell = grid.headerCell(@src(), col, .{ .border = dvui.Rect.all(1) });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..2) |col| {
                    for (0..4) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-more_headers_than_body.png");
}

test "more body cells than header cells" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(4), .{}, .{});
            defer grid.deinit();
            {
                for (0..2) |col| {
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
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "GridWidget-more_body_than_header.png");
}

test "resize cols" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        var action: enum { wide, resize, narrow } = .wide;
        var frame_count: usize = 0;
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(4), .{ .resize_cols = action == .resize }, .{});
            defer grid.deinit();
            {
                for (0..4) |col| {
                    var cell = grid.headerCell(@src(), col, .{
                        .border = dvui.Rect.all(1),
                        .size = .{ .w = if (action == .wide) 100 else 50 },
                    });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..4) |col| {
                    for (0..4) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            if (action == .resize) action = .narrow;
            return .ok;
        }
    };
    frame.action = .wide;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-resize_cols_wide.png");
    frame.action = .resize;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-resize_cols_narrow.png");
}

test "resize rows" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();

    const frame = struct {
        var action: enum { tall, resize, short } = .tall;
        var frame_count: usize = 0;
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(4), .{ .resize_rows = action == .resize }, .{});
            defer grid.deinit();
            {
                for (0..4) |col| {
                    var cell = grid.headerCell(@src(), col, .{
                        .border = dvui.Rect.all(1),
                    });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..4) |col| {
                    for (0..4) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{ .font_style = if (action == .tall) .title_1 else null });
                    }
                }
            }
            if (action == .resize) action = .short;
            return .ok;
        }
    };
    frame.action = .tall;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-resize_rows_tall.png");
    frame.action = .resize;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-resize_rows_short.png");
}

test "add rows" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var frame_number: usize = 0;
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            {
                const start: usize, const end: usize = if (frame_number == 0)
                    .{ 0, 5 }
                else
                    .{ 0, 10 };
                for (0..10) |col| {
                    for (start..end) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            return .ok;
        }
    };
    try dvui.testing.settle(frame.frame);
    frame.frame_number += 1;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-add_rows.png");
}

test "remove rows" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var frame_number: usize = 0;
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            {
                const start: usize, const end: usize = if (frame_number == 0)
                    .{ 0, 10 }
                else
                    .{ 0, 5 };
                for (0..10) |col| {
                    for (start..end) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            return .ok;
        }
    };
    try dvui.testing.settle(frame.frame);
    frame.frame_number += 1;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-remove_rows.png");
}

test "add cols" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var frame_number: usize = 0;
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            {
                const start: usize, const end: usize = if (frame_number == 0)
                    .{ 0, 5 }
                else
                    .{ 0, 10 };
                for (start..end) |col| {
                    for (0..10) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            return .ok;
        }
    };
    try dvui.testing.settle(frame.frame);
    frame.frame_number += 1;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-add_cols.png");
}

test "remove cols" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var frame_number: usize = 0;
        fn frame() !dvui.App.Result {
            const start: usize, const end: usize = if (frame_number == 0)
                .{ 0, 10 }
            else
                .{ 0, 5 };

            var grid = dvui.grid(@src(), .numCols(10), .{}, .{});
            defer grid.deinit();
            {
                for (start..end) |col| {
                    for (0..10) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            return .ok;
        }
    };
    try dvui.testing.settle(frame.frame);
    frame.frame_number += 1;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-remove_cols.png");
}

test "remove cols and shrink" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var frame_number: usize = 0;
        fn frame() !dvui.App.Result {
            const start: usize, const end: usize = if (frame_number == 0)
                .{ 0, 10 }
            else
                .{ 0, 5 };

            var grid = dvui.grid(@src(), .numCols(end), .{}, .{});
            defer grid.deinit();
            {
                for (start..end) |col| {
                    for (0..10) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{
                            .border = dvui.Rect.all(1),
                        });
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{});
                    }
                }
            }
            return .ok;
        }
    };
    try dvui.testing.settle(frame.frame);
    frame.frame_number += 1;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-remove_cols_shrink.png");
}

test "header size and shrink" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var action: enum { tall, resize, short } = .tall;
        fn frame() !dvui.App.Result {
            var grid = dvui.grid(@src(), .numCols(10), .{ .resize_rows = action == .resize }, .{});
            defer grid.deinit();
            {
                for (0..10) |col| {
                    var cell = grid.headerCell(@src(), col, .{
                        .size = .{ .h = if (action == .tall) 100 else 50 },
                        .border = dvui.Rect.all(1),
                    });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
            }
            if (action == .resize) action = .short;
            return .ok;
        }
    };
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-header_pre_resize.png");
    frame.action = .resize;
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-header_post_resize.png");
}

// Don't run in default tests.
// Performs frame-by-frame debugging of row resizing.
test "header body resize" {
    if (true)
        return error.SkipZigTest;

    var t = try dvui.testing.init(.{ .window_size = .{ .w = 800, .h = 600 } });
    defer t.deinit();
    const frame = struct {
        var action: enum { tall, resize, short } = .tall;
        var frame_number: usize = 0;
        fn frame() !dvui.App.Result {
            defer frame_number += 1;
            var grid = dvui.grid(@src(), .numCols(10), .{ .resize_rows = action == .resize }, .{});
            defer grid.deinit();
            {
                for (0..10) |col| {
                    var cell = grid.headerCell(@src(), col, .{
                        .border = dvui.Rect.all(1),
                        .size = if (action == .tall) .{ .h = 100 } else null,
                    });
                    defer cell.deinit();
                    dvui.label(@src(), "{}", .{col}, .{});
                }
                for (0..10) |col| {
                    for (0..10) |row| {
                        var cell = grid.bodyCell(@src(), col, row, .{});
                        defer cell.deinit();
                        dvui.label(@src(), "{}:{}", .{ col, row }, .{ .font_style = .heading });
                    }
                }
            }
            if (action == .resize) action = .short;
            return .ok;
        }
    };
    try dvui.testing.settle(frame.frame);
    try t.saveImage(frame.frame, null, "GridWidget-hb-start.png");
    frame.action = .resize;

    for (0..100) |i| {
        const wait_time = dvui.testing.step(frame.frame) catch null;
        var fn_buf: [4096]u8 = undefined;
        const filename = try std.fmt.bufPrint(&fn_buf, "GridWidget-hb-{d}.png", .{i});
        try t.saveImage(frame.frame, null, filename);

        if (wait_time == 0) {
            // need another frame, someone called refresh()
            continue;
        }
        break;
    }
    try t.saveImage(frame.frame, null, "GridWidget-hb-end.png");
}
