var line_height_factor: f32 = 1.2;

/// ![image](Examples-text_layout.png)
pub fn layoutText() void {
    {
        var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer box.deinit();

        const show_large_doc: *bool = dvui.dataGetPtrDefault(null, box.data().id, "show_large_doc", bool, false);

        _ = dvui.sliderEntry(@src(), "line height: {d:0.2}", .{ .value = &line_height_factor, .min = 0.1, .max = 2, .interval = 0.1 }, .{});

        if (dvui.button(@src(), "Large Doc", .{}, .{ .gravity_x = 1.0 })) {
            show_large_doc.* = !show_large_doc.*;
        }

        if (show_large_doc.*) {
            var fw = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .width(500) });
            defer fw.deinit();

            var buf: [100]u8 = undefined;
            const fps_str = std.fmt.bufPrint(&buf, "{d:0>3.0} fps", .{dvui.FPS()}) catch unreachable;

            fw.dragAreaSet(dvui.windowHeader("Large Text Layout", fps_str, show_large_doc));

            var cache_ok = true;

            const copies: *usize = dvui.dataGetPtrDefault(null, box.data().id, "copies", usize, 100);
            const break_lines: *bool = dvui.dataGetPtrDefault(null, box.data().id, "break_lines", bool, false);
            const kerning: *usize = dvui.dataGetPtrDefault(null, box.data().id, "kerning", usize, 0);
            const refresh: *bool = dvui.dataGetPtrDefault(null, box.data().id, "refresh", bool, false);
            {
                var box2 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
                defer box2.deinit();

                var copies_val: f32 = @floatFromInt(copies.*);
                if (dvui.sliderEntry(@src(), "copies: {d:0.0}", .{ .value = &copies_val, .min = 0, .max = 1000, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                    copies.* = @intFromFloat(@round(copies_val));
                    cache_ok = false;
                }

                _ = dvui.checkbox(@src(), refresh, "Refresh", .{});

                if (refresh.*) {
                    dvui.refresh(null, @src(), null);
                }
            }

            {
                var box2 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
                defer box2.deinit();

                if (dvui.checkbox(@src(), break_lines, "Break Lines", .{ .gravity_y = 0.5 })) {
                    cache_ok = false;
                }

                if (dvui.dropdown(@src(), &.{ "Kern null", "Kern true", "Kern false" }, kerning, .{ .gravity_y = 0.5, .min_size_content = .width(120) })) {
                    cache_ok = false;
                }

                if (dvui.checkbox(@src(), &dvui.currentWindow().kerning, "Kern Global", .{ .gravity_y = 0.5 })) {
                    cache_ok = false;
                }
            }

            var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
            defer scroll.deinit();

            var kern: ?bool = null;
            if (kerning.* == 1) kern = true;
            if (kerning.* == 2) kern = false;
            var tl = dvui.textLayout(@src(), .{ .cache_layout = cache_ok, .break_lines = break_lines.*, .kerning = kern }, .{ .expand = .both });
            defer tl.deinit();

            const lorem1 = "Header line with 9 indented (kerning test T.)\n";
            const lorem2 = "    an indented line\n";

            for (0..copies.*) |i| {
                tl.format("{d} ", .{i}, .{});
                tl.addText(lorem1, .{});
                for (0..9) |_| {
                    tl.addText(lorem2, .{});
                }
            }
        }
    }

    {
        var tl = TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
        tl.install(.{});
        defer tl.deinit();

        var cbox = dvui.box(@src(), .{ .dir = .vertical }, .{ .margin = dvui.Rect.all(6), .min_size_content = .{ .w = 40 } });
        if (dvui.buttonIcon(
            @src(),
            "play",
            entypo.controller_play,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Play", .message = "You clicked play" });
        }
        if (dvui.buttonIcon(
            @src(),
            "more",
            entypo.dots_three_vertical,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "More", .message = "You clicked more" });
        }
        cbox.deinit();

        cbox = dvui.box(@src(), .{}, .{ .margin = Rect.all(4), .padding = Rect.all(4), .gravity_x = 1.0, .background = true, .style = .window, .min_size_content = .{ .w = 160 }, .max_size_content = .width(160) });
        dvui.icon(@src(), "aircraft", entypo.aircraft, .{}, .{ .min_size_content = .{ .h = 30 }, .gravity_x = 0.5 });
        dvui.label(@src(), "Caption Heading", .{}, .{ .font_style = .caption_heading, .gravity_x = 0.5 });
        var tl_caption = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        tl_caption.addText("Here is some caption text that is in it's own text layout.", .{ .font_style = .caption });
        tl_caption.deinit();
        cbox.deinit();

        if (tl.touchEditing()) |floating_widget| {
            defer floating_widget.deinit();
            tl.touchEditingMenu();
        }

        tl.processEvents();

        const lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. ";
        const lorem2 = " Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.\n";
        tl.addText(lorem, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        if (tl.addTextClick("This text is a link that is part of the text layout and goes to the dvui home page.", .{ .color_text = .{ .r = 0x35, .g = 0x84, .b = 0xe4 }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) })) {
            _ = dvui.openURL(.{ .url = "https://david-vanderson.github.io/" });
        }

        tl.addText(lorem2, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        const start = "\nNotice that the text in this box is wrapping around the stuff in the corners.\n\n";
        tl.addText(start, .{ .font_style = .title_4 });

        const col = dvui.Color.average(tl.data().options.color(.text), tl.data().options.color(.fill));
        tl.addTextTooltip(@src(), "Hover this for a tooltip.\n\n", "This is some tooltip", .{ .color_text = col, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        tl.format("This line uses zig format strings: {d}\n\n", .{12345}, .{});

        tl.addText("Title ", .{ .font_style = .title });
        tl.addText("Title-1 ", .{ .font_style = .title_1 });
        tl.addText("Title-2 ", .{ .font_style = .title_2 });
        tl.addText("Title-3 ", .{ .font_style = .title_3 });
        tl.addText("Title-4 ", .{ .font_style = .title_4 });
        tl.addText("Heading\n", .{ .font_style = .heading });

        tl.addText("Here ", .{ .font_style = .title, .color_text = .{ .r = 100, .b = 100 } });
        tl.addText("is some ", .{ .font_style = .title_2, .color_text = .{ .b = 100, .g = 100 }, .color_fill = .green });
        tl.addText("ugly text ", .{ .font_style = .title_1, .color_text = .{ .r = 100, .g = 100 }, .color_fill = .teal });
        tl.addText("that shows styling.", .{ .font_style = .caption, .color_text = .{ .r = 100, .g = 50, .b = 50 } });
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG text_layout" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            layoutText();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-text_layout.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const entypo = dvui.entypo;
const TextLayoutWidget = dvui.TextLayoutWidget;
const Rect = dvui.Rect;
