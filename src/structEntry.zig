const std = @import("std");
const dvui = @import("dvui.zig");

const border = dvui.Rect.all(1);

//===============================================
//=============BASIC FIELD WIDGETS===============
//===============================================

// The field widgets in this section display actual
// inputs to the user for base types like ints
// and floats.

pub fn IntFieldOptions(comptime T: type) type {
    return struct {
        widget_type: enum { number_entry, slider } = .number_entry,
        min: T = std.math.minInt(T),
        max: T = std.math.maxInt(T),
        dvui_opts: dvui.Options = .{},
        disabled: bool = false,
        label_override: ?[]const u8 = null,
    };
}

fn intFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: IntFieldOptions(T),
) !void {
    if (opt.disabled) return;
    switch (opt.widget_type) {
        .number_entry => {
            var box = try dvui.box(@src(), .horizontal, .{});
            defer box.deinit();

            try dvui.label(@src(), "{s}", .{opt.label_override orelse name}, .{});
            const maybe_num = try dvui.textEntryNumber(@src(), T, .{
                .min = opt.min,
                .max = opt.max,
                .value = result,
            }, opt.dvui_opts);
            if (maybe_num == .Valid) {
                result.* = maybe_num.Valid;
            }
            try dvui.label(@src(), "{}", .{result.*}, .{});
        },
        .slider => {
            var box = try dvui.box(@src(), .horizontal, .{});
            defer box.deinit();

            try dvui.label(@src(), "{s}", .{name}, .{});

            var percent = intToNormalizedPercent(result.*, opt.min, opt.max);
            //TODO implement dvui_opts
            _ = try dvui.slider(@src(), .horizontal, &percent, .{
                .expand = .horizontal,
                .min_size_content = .{ .w = 100, .h = 20 },
            });
            result.* = normalizedPercentToInt(percent, T, opt.min, opt.max);
            try dvui.label(@src(), "{}", .{result.*}, .{});
        },
    }
}

fn normalizedPercentToInt(normalized_percent: f32, comptime T: type, min: T, max: T) T {
    if (@typeInfo(T) != .Int) @compileError("T is not an int type");
    std.debug.assert(normalized_percent >= 0);
    std.debug.assert(normalized_percent <= 1);
    const range: f32 = @floatFromInt(max - min);

    const result: T = @intFromFloat(@as(f32, @floatFromInt(min)) + (range * normalized_percent));

    return result;
}

fn intToNormalizedPercent(input_int: anytype, min: @TypeOf(input_int), max: @TypeOf(input_int)) f32 {
    const int = if (input_int < min) min else input_int;
    const range: f32 = @floatFromInt(max - min);
    const progress: f32 = (@as(f32, @floatFromInt(int)) - @as(f32, @floatFromInt(min)));
    const result = progress / range;

    return result;
}

pub fn FloatFieldOptions(comptime T: type) type {
    return struct {
        min: ?T = null, // you could also use floatMin/floatMax here, but that
        max: ?T = null, // would cause issues rendering min and max numbers
        dvui_opts: dvui.Options = .{},
        disabled: bool = false,
        label_override: ?[]const u8 = null,
    };
}

pub fn floatFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: FloatFieldOptions(T),
) !void {
    if (opt.disabled) return;

    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();
    try dvui.label(@src(), "{s}", .{opt.label_override orelse name}, .{});

    const maybe_num = try dvui.textEntryNumber(@src(), T, .{ .min = opt.min, .max = opt.max }, opt.dvui_opts);
    if (maybe_num == .Valid) {
        result.* = maybe_num.Valid;
    }
    try dvui.label(@src(), "{d}", .{result.*}, .{});
}

pub const EnumFieldOptions = struct {
    widget_type: enum { radio, dropdown } = .dropdown,
    dvui_opts: dvui.Options = .{},
    disabled: bool = false,
    label_override: ?[]const u8 = null,
};

fn enumFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: EnumFieldOptions,
) !void {
    if (opt.disabled) return;

    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    try dvui.label(@src(), "{s}", .{opt.label_override orelse name}, .{});
    switch (opt.widget_type) {
        .dropdown => {
            const entries = std.meta.fieldNames(T);
            var choice: usize = @intFromEnum(result.*);
            _ = try dvui.dropdown(@src(), entries, &choice, opt.dvui_opts);
            result.* = @enumFromInt(choice);
        },
        .radio => {
            inline for (@typeInfo(T).Enum.fields) |field| {
                if (try dvui.radio(
                    @src(),
                    result.* == @as(T, @enumFromInt(field.value)),
                    field.name,
                    opt.dvui_opts,
                )) {
                    result.* = @enumFromInt(field.value);
                }
            }
        },
    }
}

pub const BoolFieldOptions = struct {
    widget_type: enum { checkbox, dropdown, toggle } = .toggle,
    dvui_opts: dvui.Options = .{},
    disabled: bool = false,
    label_override: ?[]const u8 = null,
};

fn boolFieldWidget(
    comptime name: []const u8,
    result: *bool,
    opt: BoolFieldOptions,
) !void {
    if (opt.disabled) return;
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    //TODO implement dvui_opts for other types
    switch (opt.widget_type) {
        .checkbox => {
            try dvui.label(@src(), "{s}", .{opt.label_override orelse name}, .{});
            _ = try dvui.checkbox(@src(), result, "", opt.dvui_opts);
        },
        .dropdown => {
            const entries = .{ "false", "true" };
            var choice: usize = if (result.* == false) 0 else 1;
            try dvui.labelNoFmt(@src(), opt.label_override orelse name, .{});
            _ = try dvui.dropdown(@src(), &entries, &choice, .{});
            result.* = if (choice == 0) false else true;
        },
        .toggle => {
            switch (result.*) {
                true => {
                    if (try dvui.button(@src(), name ++ " enabled", .{}, .{ .border = border, .background = true })) {
                        result.* = !result.*;
                    }
                },
                false => {
                    if (try dvui.button(@src(), name ++ " disabled", .{}, .{ .border = border, .background = true })) {
                        result.* = !result.*;
                    }
                },
            }
        },
    }
}

//==========Text Field Widget and Options============
pub const TextFieldOptions = struct {
    max_len: u16 = 64,
    dvui_opts: dvui.Options = .{},
    disabled: bool = false,
    label_override: ?[]const u8 = null,
};

fn textFieldWidget(
    comptime name: []const u8,
    result: *[]const u8,
    opt: TextFieldOptions,
    comptime alloc: bool,
) !void {
    if (opt.disabled) return;

    //TODO respect alloc setting
    _ = alloc; // autofix
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    try dvui.label(@src(), "{s}", .{opt.label_override orelse name}, .{});
    const buffer = dvui.dataGetSliceDefault(
        dvui.currentWindow(),
        box.widget().data().id,
        "buffer",
        []u8,
        result.*,
    );

    const text_box = try dvui.textEntry(@src(), .{ .text = .{ .buffer = buffer } }, opt.dvui_opts);
    defer text_box.deinit();

    result.* = text_box.getText();
}

//===============================================
//=========CONTAINER FIELD WIDGETS===============
//===============================================

// The field widgets in this section create widgets
// which contain other widgets (such as optional fields
// or unions)

//=======Optional Field Widget and Options=======
pub fn UnionFieldOptions(comptime T: type) type {
    return struct {
        fields: NamespaceFieldOptions(T) = .{},
        disabled: bool = false,
        label_override: ?[]const u8 = null,
    };
}

pub fn unionFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: UnionFieldOptions(T),
    comptime alloc: bool,
) !void {
    var box = try dvui.box(@src(), .vertical, .{});
    defer box.deinit();

    const FieldEnum = std.meta.FieldEnum(T);

    const entries = std.meta.fieldNames(T);
    var choice: usize = @intFromEnum(std.meta.activeTag(result.*));

    {
        var hbox = try dvui.box(@src(), .vertical, .{});
        defer hbox.deinit();
        const label = opt.label_override orelse name;
        if (label.len != 0) {
            try dvui.label(@src(), "{s}", .{label}, .{
                .border = border,
                .background = true,
            });
        }
        inline for (entries, 0..) |field_name, i| {
            if (try dvui.radio(@src(), choice == i, field_name, .{ .id_extra = i })) {
                choice = i;
            }
        }
    }

    inline for (@typeInfo(T).Union.fields, 0..) |field, i| {
        if (choice == i) {
            if (std.meta.activeTag(result.*) != @as(FieldEnum, @enumFromInt(i))) {
                result.* = @unionInit(T, field.name, undefined);
            }
            const field_result: *field.type = &@field(result.*, field.name);

            var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
            defer hbox.deinit();
            var line = try dvui.box(@src(), .vertical, .{
                .border = border,
                .expand = .vertical,
                .background = true,
                .margin = .{ .w = 10, .x = 10 },
            });
            line.deinit();

            try fieldWidget(
                field.name,
                field.type,
                @ptrCast(field_result),
                @field(opt.fields, field.name),
                alloc,
            );
        }
    }
}

//=======Optional Field Widget and Options=======
pub fn OptionalFieldOptions(comptime T: type) type {
    return struct {
        child: FieldOptions(@typeInfo(T).Optional.child) = .{},
        disabled: bool = false,
        label_override: ?[]const u8 = null,
    };
}

pub fn optionalFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: OptionalFieldOptions(T),
    comptime alloc: bool,
) !void {
    if (opt.disabled) return;
    var box = try dvui.box(@src(), .vertical, .{});
    defer box.deinit();

    const Child = @typeInfo(T).Optional.child;

    const checkbox_state = dvui.dataGetPtrDefault(null, box.widget().data().id, "checked", bool, false);
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        try dvui.label(@src(), "{s}?", .{opt.label_override orelse name}, .{});
        _ = try dvui.checkbox(@src(), checkbox_state, null, .{});
    }

    if (checkbox_state.*) {
        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
        defer hbox.deinit();
        var line = try dvui.box(@src(), .vertical, .{
            .border = border,
            .expand = .vertical,
            .background = true,
            .margin = .{ .w = 10, .x = 10 },
        });
        line.deinit();
        try fieldWidget("", Child, @ptrCast(result), opt.child, alloc);
    } else {
        result.* = null;
    }
}

pub fn PointerFieldOptions(comptime T: type) type {
    const info = @typeInfo(T).Pointer;

    if (info.size == .Slice and info.child == u8) {
        return TextFieldOptions;
    } else if (info.size == .Slice) {
        return SliceFieldOptions(info.child);
    } else if (info.size == .One) {
        return SinglePointerFieldOptions(T);
    } else if (info.size == .C or info.size == .Many) {
        @compileError("Many item pointers disallowed");
    }
}

pub fn pointerFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: PointerFieldOptions(T),
    comptime alloc: bool,
) !void {
    const info = @typeInfo(T).Pointer;

    if (info.size == .Slice and info.child == u8) {
        try textFieldWidget(name, result, opt, alloc);
    } else if (info.size == .Slice) {
        try sliceFieldWidget(name, info.child, result, opt, alloc);
    } else if (info.size == .One) {
        try singlePointerFieldWidget(T, name, result, opt, alloc);
    } else if (info.size == .C or info.size == .Many) {
        @compileError("structEntry does not support *C or Many pointers");
    }
}

//=======Single Item pointer and options=======
pub fn SinglePointerFieldOptions(comptime T: type) type {
    return struct {
        child: FieldOptions(@typeInfo(T).Pointer.child) = .{},
        disabled: bool = false,
    };
}

pub fn singlePointerFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: SinglePointerFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    if (opt.disabled) return;
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    const Child = @typeInfo(T).Pointer.child;

    const destination = if (alloc)
        try dvui.dataGetPtrDefault(dvui.currentWindow(), box.widget().data().id, "ptr", T, undefined)
    else
        result;
    result.* = destination;

    try fieldWidget(@src(), name, Child, result.*, opt.child, alloc, paned);
}

//=======Single Item pointer and options=======
pub fn SliceFieldOptions(comptime T: type) type {
    return struct {
        child: FieldOptions(T) = .{},
        disabled: bool = false,
    };
}

pub fn sliceFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *[]T,
    options: SliceFieldOptions(T),
    comptime alloc: bool,
) !void {
    _ = name; // autofix

    var removed_idx: ?usize = null;
    var insert_before_idx: ?usize = null;

    var reorder = try dvui.reorder(@src(), .{ .min_size_content = .{ .w = 120 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });

    var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both });

    for (result.*, 0..) |_, i| {
        var reorderable = try reorder.reorderable(@src(), .{}, .{ .id_extra = i, .expand = .horizontal });
        defer reorderable.deinit();

        if (reorderable.removed()) {
            removed_idx = i; // this entry is being dragged
        } else if (reorderable.insertBefore()) {
            insert_before_idx = i; // this entry was dropped onto
        }

        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .color_fill = .{ .name = .fill_window } });
        defer hbox.deinit();

        _ = try dvui.ReorderWidget.draggable(@src(), .{ .reorderable = reorderable }, .{ .expand = .vertical, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 });

        try fieldWidget("name", T, @ptrCast(&result.*[i]), options.child, alloc);
    }

    // show a final slot that allows dropping an entry at the end of the list
    if (try reorder.finalSlot()) {
        insert_before_idx = result.*.len; // entry was dropped into the final slot
    }

    // returns true if the slice was reordered
    _ = dvui.ReorderWidget.reorderSlice(T, result.*, removed_idx, insert_before_idx);

    if (alloc) {
        const new_item: *T = dvui.dataGetPtrDefault(null, reorder.data().id, "new_item", T, T{});

        _ = try dvui.spacer(@src(), .{ .h = 4 }, .{});

        var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .color_fill = .{ .name = .fill_window } });
        defer hbox.deinit();

        if (try dvui.button(@src(), "Add New", .{}, .{})) {
            // want to add new_item to the end of the slice, but where is the allocator?
        }

        try fieldWidget(@typeName(T), T, @ptrCast(new_item), options.child, alloc);
    }

    vbox.deinit();

    reorder.deinit();
}

//==========Struct Field Widget and Options
pub fn StructFieldOptions(comptime T: type) type {
    return struct {
        fields: NamespaceFieldOptions(T) = .{},
        disabled: bool = false,
        label_override: ?[]const u8 = null,
        use_expander: bool = true,
    };
}

fn structFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: StructFieldOptions(T),
    comptime alloc: bool,
) !void {
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");
    if (opt.disabled) return;
    const fields = @typeInfo(T).Struct.fields;

    var box = try dvui.box(@src(), .vertical, .{ .expand = .both });
    defer box.deinit();

    const label = opt.label_override orelse name;

    var expand = false; //use expander
    var separate = false; //use separator to inset field

    if (label.len == 0) {
        expand = true;
        separate = false;
    } else if (opt.use_expander) {
        expand = try dvui.expander(@src(), label, .{}, .{});
        separate = expand;
    } else {
        try dvui.label(@src(), "{s}", .{label}, .{});
        expand = true;
        separate = false;
    }

    var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both });
    defer hbox.deinit();

    if (separate) {
        try dvui.separator(@src(), .{
            .expand = .vertical,
            .min_size_content = .{ .w = 2 },
            .margin = dvui.Rect.all(4),
        });
    }

    if (expand) {
        var vbox = try dvui.box(@src(), .vertical, .{ .expand = .both });
        defer vbox.deinit();
        inline for (fields, 0..) |field, i| {
            const options = @field(opt.fields, field.name);
            if (!options.disabled) {
                const result_ptr = &@field(result.*, field.name);

                var widgetbox = try dvui.box(@src(), .vertical, .{
                    .expand = .both,
                    .id_extra = i,
                });
                defer widgetbox.deinit();
                try fieldWidget(field.name, field.type, result_ptr, options, alloc);
            }
        }
    }
}

//=========Generic Field Widget and Options Implementations===========
pub fn FieldOptions(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Int => IntFieldOptions(T),
        .Float => FloatFieldOptions(T),
        .Enum => EnumFieldOptions,
        .Bool => BoolFieldOptions,
        .Struct => StructFieldOptions(T),
        .Union => UnionFieldOptions(T),
        .Optional => OptionalFieldOptions(T),
        .Pointer => PointerFieldOptions(T),
        else => @compileError("Invalid Type: " ++ @typeName(T)),
    };
}

pub fn NamespaceFieldOptions(comptime T: type) type {
    var fields: [std.meta.fields(T).len]std.builtin.Type.StructField = undefined;

    inline for (std.meta.fields(T), 0..) |field, i| {
        const FieldType = FieldOptions(field.type);
        fields[i] = .{
            .alignment = 1,
            .default_value = @alignCast(@ptrCast(&(@as(FieldType, FieldType{})))),
            .is_comptime = false,
            .name = field.name,
            .type = FieldType,
        };
    }
    return @Type(.{ .Struct = .{
        .decls = &.{},
        .fields = &fields,
        .is_tuple = false,
        .layout = .auto,
    } });
}

pub fn fieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    options: FieldOptions(T),
    comptime alloc: bool,
) !void {
    switch (@typeInfo(T)) {
        .Int => try intFieldWidget(name, T, result, options),
        .Float => try floatFieldWidget(name, T, result, options),
        .Bool => try boolFieldWidget(name, result, options),
        .Enum => try enumFieldWidget(name, T, result, options),
        .Pointer => try pointerFieldWidget(name, T, result, options, alloc),
        .Optional => try optionalFieldWidget(name, T, result, options, alloc),
        .Union => try unionFieldWidget(name, T, result, options, alloc),
        .Struct => try structFieldWidget(name, T, result, options, alloc),
        else => @compileError("Invalid type: " ++ @typeName(T)),
    }
}

//===============================================
//============PUBLIC API FUNCTIONS===============
//===============================================

pub fn structEntry(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    opts: dvui.Options,
) !void {
    var box = try dvui.box(src, .vertical, opts);
    defer box.deinit();
    try structFieldWidget("", T, result, .{}, false);
}

pub fn structEntryEx(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    field_options: StructFieldOptions(T),
) !void {
    var box = try dvui.box(src, .vertical, .{ .expand = .both });
    defer box.deinit();
    try structFieldWidget(name, T, result, field_options, false);
}

pub fn structEntryAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    opts: dvui.Options,
) !void {
    var box = try dvui.box(src, .vertical, opts);
    defer box.deinit();
    try structFieldWidget("", T, result, .{}, true);
}

pub fn structEntryExAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    field_options: StructFieldOptions(T),
) !void {
    var box = try dvui.box(src, .vertical, .{ .expand = .both });
    defer box.deinit();
    try structFieldWidget(name, T, result, field_options, true);
}

//===============================================
//=============DEEP COPY FUNCTIONS===============
//===============================================

// For usage with structEntryAlloc
// Currently untested

//============Alloc result type========
pub fn getOwnedCopy(a: std.mem.Allocator, value: anytype) !Parsed(@TypeOf(value)) {
    var arena = std.heap.ArenaAllocator.init(a);

    //perform deep copy
    const copied = try deepCopyStruct(arena.allocator(), value);

    return .{ .value = copied, .arena = arena };
}

pub fn getOwnedCopyLeaky(a: std.mem.Allocator, value: anytype) !@TypeOf(value) {

    //perform deep copy
    return try deepCopyStruct(a, value);
}

//==========Deep Copy Function==========
pub fn Parsed(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            self.arena.deinit();
        }
    };
}

pub fn deepCopyStruct(allocator: std.mem.Allocator, value: anytype) !@TypeOf(value) {
    const T = @TypeOf(value);
    var result: T = undefined;

    inline for (@typeInfo(T).Struct.fields) |field| {
        const info = @typeInfo(field.type);
        if (info == .Pointer) {
            switch (info.size) {
                .Slice => {
                    @field(result, field.name) = try allocator.dupe(info.child, @field(value, field.name));
                    if (@typeInfo(info.child) == .Struct) {
                        for (@field(result, field.name), 0..) |*val, i| {
                            val.* = try deepCopyStruct(allocator, @field(value, field.name)[i]);
                        }
                    }
                },
                .One => {
                    @field(result, field.name) = try allocator.create(info.child);
                    if (@typeInfo(info.child) == .Struct) {
                        @field(result, field.name).* = try deepCopyStruct(allocator, @field(value, field.name));
                    } else {
                        @field(result, field.name).* = @field(value, field.name);
                    }
                },
                else => @compileError("Cannot copy *C and Many pointers"),
            }
        } else if (info == .Struct) {
            @field(result, field.name) = try deepCopyStruct(allocator, @field(value, field.name));
        } else {
            @field(result, field.name) = @field(value, field.name);
        }
    }
    return result;
}
