// //![image](Examples-struct_ui.png)
pub fn structUI() void {
    var b = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer b.deinit();

    const Top = struct {
        const TopChild = struct {
            a_dir: dvui.enums.Direction = undefined,
        };

        const init_data = [_]TopChild{ .{ .a_dir = .vertical }, .{ .a_dir = .horizontal } };
        var mut_array = init_data;
        var ptr: TopChild = TopChild{ .a_dir = .horizontal };

        a_u8: u8 = 1,
        a_f32: f32 = 2.0,
        a_i8: i8 = 1,
        a_f64: f64 = 2.0,
        a_bool: bool = false,
        a_ptr: *TopChild = undefined,
        a_struct: TopChild = .{ .a_dir = .vertical },
        a_str: []const u8 = &[_]u8{0} ** 20,
        a_slice: []TopChild = undefined,
        an_array: [4]u8 = .{ 1, 2, 3, 4 },

        var instance: @This() = .{ .a_slice = &mut_array, .a_ptr = &ptr };
    };

    dvui.label(@src(), "Show UI elements for all fields of a struct:", .{}, .{});
    {
        var al: dvui.Alignment = .init(@src(), 0);
        dvui.se.displayStruct("Top.instance", &Top.instance, 1, .standard_options, .{}, &al);
    }

    if (dvui.expander(@src(), "Edit Current Theme", .{}, .{ .expand = .horizontal })) {
        themeEditor();
    }
}

var font_buf: [50]u8 = @splat('z');
// //![image](Examples-themeEditor.png)
pub fn themeEditor() void {
    var b2 = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer b2.deinit();

    const color_options: dvui.se.StructOptions(dvui.Color) = .init(.{
        .r = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        .g = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        .b = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        .a = .{ .number = .{ .display = .none } },
    }, null);
    const color_or_name_options: dvui.se.StructOptions(dvui.Options.ColorOrName) = .initDefaults(.{ .color = .{} });
    const font_options: dvui.se.StructOptions(dvui.Font) = .init(.{
        .name = .{ .text = .{ .buffer = &font_buf } },
    }, .{ .name = "new", .size = 10, .line_height_factor = 1.0 });
    var alignment: dvui.Alignment = .init(@src(), 0);

    dvui.se.displayStruct("dvui.Options", dvui.themeGet(), 2, .standard_options, .{
        color_options,
        color_or_name_options,
        font_options,
    }, &alignment);
    //    dvui.structEntryEx(@src(), "dvui.Theme", dvui.Theme, .{ .style_err, .style_accent }, dvui.themeGet(), .{
    //        .use_expander = false,
    //        .label_override = "",
    //        .fields = .{
    //            .name = .{ .disabled = true },
    //            .dark = .{ .widget_type = .toggle },
    //            .font_body = .{ .disabled = true },
    //            .font_heading = .{ .disabled = true },
    //            .font_caption = .{ .disabled = true },
    //            .font_caption_heading = .{ .disabled = true },
    //            .font_title = .{ .disabled = true },
    //            .font_title_1 = .{ .disabled = true },
    //            .font_title_2 = .{ .disabled = true },
    //            .font_title_3 = .{ .disabled = true },
    //            .font_title_4 = .{ .disabled = true },
    //            .color_accent = color_field_options,
    //            .color_err = color_field_options,
    //            .color_text = color_field_options,
    //            .color_text_press = color_field_options,
    //            .color_fill = color_field_options,
    //            .color_fill_window = color_field_options,
    //            .color_fill_control = color_field_options,
    //            .color_fill_hover = color_field_options,
    //            .color_fill_press = color_field_options,
    //            .color_border = color_field_options,
    //        },
    //    });
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG struct_ui" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 700 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            structUI();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-struct_ui.png");
}

//test "DOCIMG themeEditor" {
//    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 500 } });
//    defer t.deinit();
//
//    const frame = struct {
//        fn frame() !dvui.App.Result {
//            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
//            defer box.deinit();
//            themeEditor();
//            return .ok;
//        }
//    }.frame;
//
//    // tab to a color editor expander and open it
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.tab, .none);
//    _ = try dvui.testing.step(frame);
//    try dvui.testing.pressKey(.enter, .none);
//
//    try dvui.testing.settle(frame);
//    try t.saveImage(frame, null, "Examples-themeEditor.png");
//}

pub fn themeSerialization() void {
    var serialize_box = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer serialize_box.deinit();

    dvui.labelNoFmt(@src(), "TODO: demonstrate loading a quicktheme here", .{}, .{});
}

const std = @import("std");
const dvui = @import("../dvui.zig");
