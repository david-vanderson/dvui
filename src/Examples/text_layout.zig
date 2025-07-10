var line_height_factor: f32 = 1.2;

/// ![image](Examples-text_layout.png)
pub fn layoutText() void {
    _ = dvui.sliderEntry(@src(), "line height: {d:0.2}", .{ .value = &line_height_factor, .min = 0.1, .max = 2, .interval = 0.1 }, .{});

    {
        var tl = TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
        tl.install(.{});
        defer tl.deinit();

        var cbox = dvui.box(@src(), .vertical, .{ .margin = dvui.Rect.all(6), .min_size_content = .{ .w = 40 } });
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

        cbox = dvui.box(@src(), .vertical, .{ .margin = Rect.all(4), .padding = Rect.all(4), .gravity_x = 1.0, .background = true, .color_fill = .fill_window, .min_size_content = .{ .w = 160 }, .max_size_content = .width(160) });
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

        if (tl.addTextClick("This text is a link that is part of the text layout and goes to the dvui home page.", .{ .color_text = .{ .color = .{ .r = 0x35, .g = 0x84, .b = 0xe4 } }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) })) {
            _ = dvui.openURL("https://david-vanderson.github.io/");
        }

        tl.addText(lorem2, .{ .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        const start = "\nNotice that the text in this box is wrapping around the stuff in the corners.\n\n";
        tl.addText(start, .{ .font_style = .title_4 });

        const col = dvui.Color.average(dvui.themeGet().color_text, dvui.themeGet().color_fill);
        tl.addTextTooltip(@src(), "Hover this for a tooltip.\n\n", "This is some tooltip", .{ .color_text = .{ .color = col }, .font = dvui.themeGet().font_body.lineHeightFactor(line_height_factor) });

        tl.format("This line uses zig format strings: {d}\n\n", .{12345}, .{});

        tl.addText("Title ", .{ .font_style = .title });
        tl.addText("Title-1 ", .{ .font_style = .title_1 });
        tl.addText("Title-2 ", .{ .font_style = .title_2 });
        tl.addText("Title-3 ", .{ .font_style = .title_3 });
        tl.addText("Title-4 ", .{ .font_style = .title_4 });
        tl.addText("Heading\n", .{ .font_style = .heading });

        tl.addText("Here ", .{ .font_style = .title, .color_text = .{ .color = .{ .r = 100, .b = 100 } } });
        tl.addText("is some ", .{ .font_style = .title_2, .color_text = .{ .color = .{ .b = 100, .g = 100 } } });
        tl.addText("ugly text ", .{ .font_style = .title_1, .color_text = .{ .color = .{ .r = 100, .g = 100 } } });
        tl.addText("that shows styling.", .{ .font_style = .caption, .color_text = .{ .color = .{ .r = 100, .g = 50, .b = 50 } } });
    }
}

const dvui = @import("../dvui.zig");
const entypo = dvui.entypo;
const TextLayoutWidget = dvui.TextLayoutWidget;
const Rect = dvui.Rect;
