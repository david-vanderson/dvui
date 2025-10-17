/// ![image](Examples-debugging.png)
pub fn debuggingErrors() void {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        dvui.label(@src(), "Scroll Speed", .{}, .{});
        _ = dvui.sliderEntry(@src(), "{d:0.1}", .{ .value = &dvui.scroll_speed, .min = 0.1, .max = 50, .interval = 0.1 }, .{});
    }

    _ = dvui.checkbox(@src(), &dvui.currentWindow().kerning, "Kerning", .{});

    _ = dvui.checkbox(@src(), &dvui.currentWindow().snap_to_pixels, "Snap to pixels", .{});
    dvui.label(@src(), "on non-hdpi screens watch the window title \"DVUI Demo\"", .{}, .{ .margin = .{ .x = 10 } });
    dvui.label(@src(), "- text, icons, and images rounded to nearest pixel", .{}, .{ .margin = .{ .x = 10 } });
    dvui.label(@src(), "- text rendered at the closest smaller font (not stretched)", .{}, .{ .margin = .{ .x = 10 } });

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
            dvui.label(@src(), "this should be highlighted (and error logged)", .{}, .{});
            dvui.label(@src(), " - fix by passing .id_extra = <loop index>", .{}, .{ .id_extra = i });
        }

        if (dvui.labelClick(@src(), "See https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids", .{}, .{}, .{ .color_text = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } })) {
            _ = dvui.openURL("https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids");
        }
    }

    if (dvui.expander(@src(), "Invalid utf-8 text", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();
        dvui.labelNoFmt(@src(), "this \xFFtext\xFF includes some \xFF invalid utf-8\xFF\xFF\xFF which is replaced with \xFF", .{}, .{});
        const tl = dvui.textLayout(@src(), .{ .cache_layout = true }, .{});
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

        const g = struct {
            const empty = [1]u8{0} ** 100;
            var latest_buf = empty;
            var latest_slice: []u8 = &.{};
        };

        const evts = dvui.events();
        for (evts) |e| {
            switch (e.evt) {
                .key => |ke| {
                    var it = dvui.currentWindow().keybinds.iterator();
                    while (it.next()) |kv| {
                        if (ke.matchKeyBind(kv.value_ptr.*)) {
                            g.latest_slice = std.fmt.bufPrintZ(&g.latest_buf, "{s}", .{kv.key_ptr.*}) catch g.latest_buf[0..0];
                        }
                    }
                },
                else => {},
            }
        }

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
        tl.format("Latest matched keybinding: {s}", .{g.latest_slice}, .{});
        tl.deinit();

        if (dvui.expander(@src(), "All Key bindings", .{}, .{ .expand = .horizontal })) {
            var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
            defer tl2.deinit();

            var outer = dvui.currentWindow().keybinds.iterator();
            while (outer.next()) |okv| {
                tl2.format("\n{s}\n    {any}\n", .{ okv.key_ptr.*, okv.value_ptr }, .{});
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
        StrokeTest.show = true;
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
    // This tests intentionally logs errors, which fails with the normal test runner.
    // We skip this test instead of downgrading all log.err to log.warn as we usually
    // want to fail if dvui logs errors (for duplicate id's or similar)
    if (!dvui.testing.is_dvui_doc_gen_runner) return error.SkipZigTest;

    std.debug.print("IGNORE ERROR LOGS FOR THIS TEST, IT IS EXPECTED\n", .{});

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

    // Tab to duplicate id expander and open it
    for (0..5) |_| {
        try dvui.testing.pressKey(.tab, .none);
        _ = try dvui.testing.step(frame);
    }
    try dvui.testing.pressKey(.enter, .none);
    _ = try dvui.testing.step(frame);

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-debugging.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = @import("../Examples.zig");
const StrokeTest = @import("StrokeTest.zig");
