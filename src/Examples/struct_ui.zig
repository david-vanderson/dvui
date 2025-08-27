///![image](Examples-struct_ui.png)
pub fn structUI() void {
    var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer b.deinit();

    const Top = struct {
        const TopChild = struct {
            a_dir: dvui.enums.Direction = .vertical,
        };

        const SomeUnion = union(enum) {
            enum_field: enum { one, two, three, four },
            number_field: f32,
            struct_field: TopChild,
        };

        const init_data = [_]TopChild{ .{ .a_dir = .vertical }, .{ .a_dir = .horizontal } };
        var mut_array = init_data;
        var ptr: TopChild = TopChild{ .a_dir = .horizontal };
        var str: [7]u8 = .{ 'e', 'd', 'i', 't', ' ', 'm', 'e' };

        a_u8: u8 = 1,
        a_f32: f32 = 2.0,
        a_i8: i8 = 1,
        a_f64: f64 = 2.0,
        a_bool: bool = false,
        a_ptr: *TopChild = undefined,
        a_struct: TopChild = .{ .a_dir = .vertical },
        a_str_const: []const u8 = &[_]u8{'$'} ** 20,
        a_str_var: []u8 = &str,
        a_slice: []TopChild = undefined,
        a_union: SomeUnion,
        an_array: [4]u8 = .{ 1, 2, 3, 4 },

        var instance: @This() = .{ .a_slice = &mut_array, .a_ptr = &ptr, .a_union = .{ .enum_field = .three } };
    };

    dvui.label(@src(), "Show UI elements for all fields of a struct:", .{}, .{});
    {
        dvui.structUI(@src(), "Top.Instance", &Top.instance, 1, .{});
    }

    if (dvui.expander(@src(), "Edit Current Theme", .{}, .{ .expand = .horizontal })) {
        themeEditor();
    }
}

var font_buf: [50]u8 = @splat('z');

///![image](Examples-themeEditor.png)
pub fn themeEditor() void {
    var b2 = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer b2.deinit();

    // Initialize with just the r, g and b fields. a will not be displayed.
    // Each time a new colour struct is instantiated it will use the supplied defaults for r, g, b and a.
    const color_options: dvui.struct_ui.StructOptions(dvui.Color) = .init(.{
        .r = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        .g = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        .b = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
    }, .{ .r = 127, .g = 127, .b = 127, .a = 255 });
    const theme: *dvui.Theme = &dvui.currentWindow().theme; // Want a pointer to the actual theme, not a copy.
    if (dvui.struct_ui.displayStruct(
        "Theme",
        theme,
        2,
        .default,
        .{color_options},
        null,
    )) |box| {
        box.deinit();
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG struct_ui" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 700 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
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
    var serialize_box = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer serialize_box.deinit();

    dvui.labelNoFmt(@src(), "TODO: demonstrate loading a quicktheme here", .{}, .{});
}

const std = @import("std");
const dvui = @import("../dvui.zig");
