/// ![image](Examples-struct_ui.png)
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
        dvui.structEntryAlloc(@src(), dvui.currentWindow().gpa, Top, .{}, &Top.instance, .{ .margin = .{ .x = 10 } });
    }

    if (dvui.expander(@src(), "Edit Current Theme", .{}, .{ .expand = .horizontal })) {
        themeEditor();
    }
}

/// ![image](Examples-themeEditor.png)
pub fn themeEditor() void {
    var b2 = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer b2.deinit();

    const color_field_options = dvui.StructFieldOptions(dvui.Color, .{ .style_err, .style_accent }){ .fields = .{
        .r = .{ .min = 0, .max = 255, .widget_type = .slider },
        .g = .{ .min = 0, .max = 255, .widget_type = .slider },
        .b = .{ .min = 0, .max = 255, .widget_type = .slider },
        .a = .{ .disabled = true },
    } };

    dvui.structEntryEx(@src(), "dvui.Theme", dvui.Theme, .{ .style_err, .style_accent }, dvui.themeGet(), .{
        .use_expander = false,
        .label_override = "",
        .fields = .{
            .name = .{ .disabled = true },
            .dark = .{ .widget_type = .toggle },
            .font_body = .{ .disabled = true },
            .font_heading = .{ .disabled = true },
            .font_caption = .{ .disabled = true },
            .font_caption_heading = .{ .disabled = true },
            .font_title = .{ .disabled = true },
            .font_title_1 = .{ .disabled = true },
            .font_title_2 = .{ .disabled = true },
            .font_title_3 = .{ .disabled = true },
            .font_title_4 = .{ .disabled = true },
            .color_accent = color_field_options,
            .color_err = color_field_options,
            .color_text = color_field_options,
            .color_text_press = color_field_options,
            .color_fill = color_field_options,
            .color_fill_window = color_field_options,
            .color_fill_control = color_field_options,
            .color_fill_hover = color_field_options,
            .color_fill_press = color_field_options,
            .color_border = color_field_options,
        },
    });
}

pub fn themeSerialization() void {
    var serialize_box = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer serialize_box.deinit();

    dvui.labelNoFmt(@src(), "TODO: demonstrate loading a quicktheme here", .{}, .{});
}

const std = @import("std");
const dvui = @import("../dvui.zig");
