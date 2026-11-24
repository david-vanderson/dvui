fn testError() !void {
    return error.TestError;
}

/// ![image](Examples-debugging.png)
pub fn debuggingErrors() void {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        dvui.label(@src(), "Scroll Speed", .{}, .{});
        _ = dvui.sliderEntry(@src(), "{d:0.1}", .{ .value = &dvui.scroll_speed, .min = 0.1, .max = 100, .interval = 0.1 }, .{});
    }

    _ = dvui.checkbox(@src(), &dvui.currentWindow().kerning, "Kerning", .{});

    _ = dvui.checkbox(@src(), &dvui.currentWindow().snap_to_pixels, "Snap to pixels", .{});
    dvui.label(@src(), "on non-hdpi screens watch the window title \"DVUI Demo\"", .{}, .{ .margin = .{ .x = 10 } });
    dvui.label(@src(), "- text, icons, and images rounded to nearest pixel", .{}, .{ .margin = .{ .x = 10 } });
    dvui.label(@src(), "- text rendered at the closest smaller font (not stretched)", .{}, .{ .margin = .{ .x = 10 } });

    if (dvui.button(@src(), "dvui.logError()", .{}, .{})) {
        testError() catch |err| {
            dvui.logError(@src(), err, "Test Error", .{});
        };
    }

    if (dvui.expander(@src(), "Virtual Parent (affects IDs but not layout)", .{}, .{ .expand = .horizontal })) {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = .{ .x = 10 } });
        defer hbox.deinit();
        dvui.label(@src(), "makeLabels twice:", .{}, .{});

        makeLabels(@src(), 0);
        makeLabels(@src(), 1);
    }

    if (dvui.expander(@src(), "Duplicate id (will log error)", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        for (0..2) |i| {
            dvui.label(@src(), "second should be highlighted (and error logged)", .{}, .{});
            dvui.label(@src(), " - fix by passing .id_extra = <loop index>", .{}, .{ .id_extra = i });
        }

        dvui.link(@src(), .{ .url = "https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids" }, .{});
    }

    if (dvui.expander(@src(), "Invalid utf-8 text", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        dvui.labelNoFmt(@src(), "this \xFFtext\xFF includes some \xFF invalid utf-8\xFF\xFF\xFF which is replaced with \xFF", .{}, .{});
        const tl = dvui.textLayout(@src(), .{}, .{});
        defer tl.deinit();
        tl.addText("Some \xFFinvalid utf-8 \xc3 in a text layout", .{});
    }

    if (dvui.expander(@src(), "Scroll child after expanded child (will log error)", .{}, .{ .expand = .horizontal })) {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .min_size_content = .{ .w = 200, .h = 80 } });
        defer scroll.deinit();

        _ = dvui.button(@src(), "Expanded\nChild\n", .{}, .{ .expand = .both });
        _ = dvui.button(@src(), "Second Child", .{}, .{});
    }

    if (dvui.expander(@src(), "Key bindings", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();

        const evts = dvui.events();
        for (evts) |e| {
            switch (e.evt) {
                .key => |ke| {
                    if (ke.action == .down) {
                        dvui.dataSetSlice(null, b.data().id, "latest_key", std.fmt.allocPrint(dvui.currentWindow().arena(), "{s} {f}", .{ @tagName(ke.code), ke.mod }) catch "");
                    }
                    var it = dvui.currentWindow().keybinds.iterator();
                    while (it.next()) |kv| {
                        if (ke.matchKeyBind(kv.value_ptr.*)) {
                            dvui.dataSetSlice(null, b.data().id, "latest_keybind", std.fmt.allocPrint(dvui.currentWindow().arena(), "{s}", .{kv.key_ptr.*}) catch "");
                        }
                    }
                },
                else => {},
            }
        }

        // just a place to test typing
        var te = dvui.textEntry(@src(), .{}, .{});
        te.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
        tl.addText("Latest key down: ", .{});
        tl.format("{?s}\n", .{dvui.dataGetSlice(null, b.data().id, "latest_key", []u8)}, .{ .font = .theme(.heading) });
        tl.addText("Latest matched keybinding: ", .{});
        tl.format("{?s}", .{dvui.dataGetSlice(null, b.data().id, "latest_keybind", []u8)}, .{ .font = .theme(.heading) });
        tl.deinit();

        if (dvui.expander(@src(), "All Key bindings", .{}, .{ .expand = .horizontal })) {
            var grid = dvui.grid(@src(), .{}, .{});
            defer grid.deinit();
            {
                const cell = grid.colHeader(.{ .col = 0 }, .{ .border = .all(1) });
                defer cell.deinit();
                dvui.label(@src(), "Name", .{}, .{});
            }
            {
                const cell = grid.colHeader(.{ .col = 1 }, .{ .border = .all(1) });
                defer cell.deinit();
                dvui.label(@src(), "Keybind", .{}, .{});
            }
            {
                const cell = grid.colHeader(.{ .col = 2 }, .{ .border = .all(1) });
                defer cell.deinit();
                dvui.label(@src(), "Also", .{}, .{});
            }

            var outer = dvui.currentWindow().keybinds.iterator();
            var i: usize = 0;
            while (outer.next()) |okv| {
                defer i += 1;
                {
                    var cell = grid.cell(.{ .col = 0, .row = i }, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{s}", .{okv.key_ptr.*}, .{});
                }
                {
                    var cell = grid.cell(.{ .col = 1, .row = i }, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{f}", .{okv.value_ptr}, .{});
                }
                if (okv.value_ptr.also) |als| {
                    var cell = grid.cell(.{ .col = 2, .row = i }, .{});
                    defer cell.deinit();
                    dvui.label(@src(), "{s}", .{als}, .{});
                }
            }
        }

        if (dvui.expander(@src(), "Overlapping Key bindings", .{}, .{ .expand = .horizontal })) {
            var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer tl2.deinit();

            var any_overlaps = false;
            var outer = dvui.currentWindow().keybinds.iterator();
            while (outer.next()) |okv| {
                var inner = outer;
                while (inner.next()) |ikv| {
                    const okb = okv.value_ptr.*;
                    const ikb = ikv.value_ptr.*;
                    if ((okb.shift == ikb.shift or okb.shift == null or ikb.shift == null) and
                        (okb.control == ikb.control or okb.control == null or ikb.control == null) and
                        (okb.alt == ikb.alt or okb.alt == null or ikb.alt == null) and
                        (okb.command == ikb.command or okb.command == null or ikb.command == null) and
                        (okb.key == ikb.key))
                    {
                        tl2.format("keybind \"{s}\" overlaps \"{s}\"\n", .{ okv.key_ptr.*, ikv.key_ptr.* }, .{});
                        any_overlaps = true;
                    }
                }
            }

            if (!any_overlaps) {
                tl2.addText("No keybind overlaps found.", .{});
            }
        }
    }

    if (dvui.expander(@src(), "Show Font Atlases", .{}, .{ .expand = .horizontal })) {
        dvui.debugFontAtlases(@src(), .{});
    }

    if (dvui.button(@src(), "Stroke Test", .{}, .{})) {
        Examples.stroke_test_show = true;
    }
}

fn makeLabels(src: std.builtin.SourceLocation, count: usize) void {
    // we want to add labels to the widget that is the parent when makeLabels
    // is called, but since makeLabels is called twice in the same parent we'll
    // get duplicate IDs

    // virtualParent helps by being a parent for ID purposes but leaves the
    // layout to the previous parent
    var vp = dvui.virtualParent(src, .{ .id_extra = count });
    defer vp.deinit();
    dvui.label(@src(), "one", .{}, .{});
    dvui.label(@src(), "two", .{}, .{});
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG debugging" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            debuggingErrors();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-debugging.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = @import("../Examples.zig");
