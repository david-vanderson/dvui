const C1 = struct {
    value1: usize = 0,
};

const C2 = struct {
    value2: f32 = 0,
};

const TestUnion = union(enum) {
    c1: C1,
    c2: C2,
};

const TestStruct = struct {
    var string_buf: [20]u8 = @splat('0');
    var ts_int: usize = 66;

    var c1: C1 = .{};
    var array_of_struct: [3]TestStruct = .{ .{}, .{}, .{} };

    int: i32 = 42,
    uint: usize = 38,
    opt_int: ?i32 = 43,
    rect3: dvui.Rect = .all(2),
    union_auto: TestUnion = .{ .c2 = .{ .value2 = 42 } },
    union_manual: TestUnion = .{ .c1 = .{ .value1 = 21 } },
    string_const: []const u8 = "ABCDEF",
    string_var: []u8 = &string_buf,
    c_string: [:0]const u8 = "C-String",
    array_u8: [13]u8 = @splat('#'),
    string_optional: ?[]u8 = &string_buf,
    opt_int_ptr: ?*usize = &ts_int,
    struct_ptr: *C1 = &c1,
    struct_slice: []TestStruct = &array_of_struct,

    pub const structui_options: dvui.struct_ui.StructOptions(TestStruct) = .initWithDefaults(.{
        .int = .{ .number = .{ .min = 5, .max = 50, .widget_type = .slider } },
        .uint = .{ .number = .{ .display = .read_only } },
        .opt_int_ptr = .{ .number = .{ .display = .none } },
        .array_u8 = .{ .text = .{ .display = .read_only } },
        .union_manual = .{ .standard = .{ .display = .none } },
    }, null);
};

var test_instance: TestStruct = .{};
var rect: dvui.Rect = .{ .h = 100, .w = 50, .x = 0, .y = 0 };

///![image](Examples-struct_ui.png)
pub fn structUI() void {
    var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
    defer b.deinit();

    dvui.label(@src(), "Show UI elements for all fields of a struct:", .{}, .{});

    // Simple display of struct with no options.
    dvui.structUI(@src(), "rect", &rect, 0, .{});

    // Customized, complex struct display
    //
    // displayStruct will return a *BoxWidget if the struct is being displayed.
    // The displayXXX and fieldWidgetXXX functions can be used to customize the display of the struct, including the addition of
    // user input widgets, such as buttons.
    dvui.label(@src(), "Customize display and editing of struct fields:", .{}, .{});
    {
        var alignment: dvui.Alignment = .init(@src(), 0);
        defer alignment.deinit();
        if (dvui.struct_ui.displayStruct(@src(), "test_struct", &test_instance, 1, .{ .standard = .{} }, .{TestStruct.structui_options}, &alignment)) |box| {
            defer box.deinit();

            // Treat the u8 array as a fixed buffer, passing itself as the backing buffer for the string.
            // Note: As the array is fixed size, 0 termination is used to indicate the end of the user-entered string.
            var slice: []u8 = &test_instance.array_u8;
            dvui.struct_ui.displayStringBuf(@src(), "array_u8_editable_1", &slice, .{ .text = .{} }, &alignment, &test_instance.array_u8);

            // Edit it instead as an array of ints.
            dvui.struct_ui.displayArray(@src(), "array_u8_editable_2", &test_instance.array_u8, 0, .{ .number = .{ .min = 0, .max = 126 } }, &alignment);

            // Optional pointers need to be handled manually by passing the pointer value to be set when the optional is selected.
            dvui.struct_ui.displayOptional(@src(), "opt_int_ptr", &test_instance.opt_int_ptr, 1, .{ .number = .{} }, .{}, &alignment, &TestStruct.ts_int);

            // Union fields can also be handled manually if custom initialization is required for different cases.
            if (dvui.struct_ui.displayContainer(@src(), "union_manual")) |union_box| {
                defer union_box.deinit();
                const selected_tag = dvui.struct_ui.unionFieldWidget(@src(), "union_manual", &test_instance.union_manual, .default);
                switch (selected_tag) {
                    .c1 => {
                        if (test_instance.union_manual != .c1)
                            test_instance.union_manual = .{ .c1 = .{ .value1 = 99 } };
                        dvui.struct_ui.displayField(@src(), "c1", &test_instance.union_manual.c1, 1, .default, .{}, &alignment);
                    },
                    .c2 => {
                        if (test_instance.union_manual != .c2)
                            test_instance.union_manual = .{ .c2 = .{ .value2 = 55 } };
                        dvui.struct_ui.displayField(@src(), "c2", &test_instance.union_manual.c2, 1, .default, .{}, &alignment);
                    },
                }
            }
        }
    }

    dvui.label(@src(), "String Handling:", .{}, .{});
    // demonstrate handling strings with dynamic allocation or using buffers.
    const read_only_options: dvui.struct_ui.StructOptions(StringStruct) = .init(.{
        .static_str = .{ .text = .{ .display = .read_only } },
        .var_str = .{ .text = .{ .display = .read_only } },
        .raw_buffer = .{ .text = .{ .display = .read_only } },
    }, .{});
    dvui.structUI(@src(), "dynamic_strings", &StringDemo.ss_1, 0, .{read_only_options});
    if (dvui.button(@src(), "Edit", .{}, .{})) {
        StringDemo.editing_dynamic = true;
    }
    dvui.structUI(@src(), "buffered_strings", &StringDemo.ss_2, 0, .{read_only_options});
    if (dvui.button(@src(), "Edit", .{}, .{})) {
        StringDemo.editing_buffer = true;
    }
    if (StringDemo.editing_dynamic) {
        editStringStuctDynamic("dynamic", &StringDemo.ss_1);
    } else if (StringDemo.editing_buffer) {
        editStringStructBuffered("buffer", &StringDemo.ss_2);
    }
    dvui.label(@src(), "Show UI elements for all fields of a struct:", .{}, .{});

    if (dvui.expander(@src(), "Edit Current Theme", .{}, .{ .expand = .horizontal })) {
        themeEditor();
    }
}

const StringStruct = struct {
    var string_buf: [20]u8 = @splat('*');

    static_str: []const u8 = "abcde",
    var_str: []u8 = string_buf[0..10],
    raw_buffer: []const u8 = &string_buf,
};

const StringDemo = struct {
    var editing_dynamic: bool = false;
    var editing_buffer: bool = false;
    var ss_1: StringStruct = .{};
    var ss_2: StringStruct = .{};
};

pub fn editStringStuctDynamic(comptime field_name: []const u8, ss: *StringStruct) void {
    var win = dvui.floatingWindow(@src(), .{
        .modal = true,
        .open_flag = &StringDemo.editing_dynamic,
    }, .{});
    defer win.deinit();
    win.autoSize();
    win.dragAreaSet(dvui.windowHeader("String Handling", "", &StringDemo.editing_dynamic));

    const options: dvui.struct_ui.StructOptions(StringStruct) = .initWithDefaults(.{ .static_str = .{ .text = .{ .display = .read_write } } }, null);
    dvui.structUI(@src(), field_name, ss, 0, .{options});
}

pub fn editStringStructBuffered(comptime field_name: []const u8, ss: *StringStruct) void {
    const local = struct {
        var string_buffer: [10]u8 = @splat('_');
    };

    var win = dvui.floatingWindow(@src(), .{
        .modal = true,
        .open_flag = &StringDemo.editing_buffer,
    }, .{});
    defer win.deinit();
    win.autoSize();
    win.dragAreaSet(dvui.windowHeader("String Handling", "", &StringDemo.editing_buffer));

    var alignment: dvui.Alignment = .init(@src(), 0);
    defer alignment.deinit();
    const options: dvui.struct_ui.StructOptions(StringStruct) = .init(.{ .raw_buffer = .{ .text = .{ .display = .read_only } } }, null);

    if (dvui.struct_ui.displayStruct(@src(), field_name, ss, 0, .default, .{options}, &alignment)) |box| {
        defer box.deinit();
        {
            dvui.struct_ui.displayStringBuf(@src(), "static_str", &ss.static_str, .{ .text = .{} }, &alignment, &local.string_buffer);
        }
        {
            dvui.struct_ui.displayStringBuf(@src(), "var_str", &ss.var_str, .{ .text = .{} }, &alignment, &StringStruct.string_buf);
        }
    }
}

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
        @src(),
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
