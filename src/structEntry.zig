const std = @import("std");
const dvui = @import("dvui.zig");

const border = dvui.Rect{ .h = 1, .w = 1, .x = 1, .y = 1 };

pub fn IntFieldOptions(comptime T: type) type {
    return struct {
        widget_type: enum { number_entry, slider } = .number_entry,
        min: T = std.math.minInt(T),
        max: T = std.math.maxInt(T),
        dvui_opts: dvui.Options = .{},
    };
}

fn intFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime int_opt: IntFieldOptions(T),
) !void {
    switch (int_opt.widget_type) {
        .number_entry => {
            var box = try dvui.box(@src(), .horizontal, .{});
            defer box.deinit();

            try dvui.label(@src(), "{s}", .{name}, .{});
            const maybe_num = try dvui.textEntryNumber(@src(), T, .{
                .min = int_opt.min,
                .max = int_opt.max,
                .value = result,
            }, int_opt.dvui_opts);
            if (maybe_num == .Valid) {
                result.* = maybe_num.Valid;
            }
            try dvui.label(@src(), "{}", .{result.*}, .{});
        },
        .slider => {
            var box = try dvui.box(@src(), .vertical, .{});
            defer box.deinit();

            try dvui.label(@src(), "{s}", .{name}, .{});

            var percent = intToNormalizedPercent(result.*, int_opt.min, int_opt.max);
            //TODO implement dvui_opts
            _ = try dvui.slider(@src(), .horizontal, &percent, .{
                .expand = .horizontal,
                .min_size_content = .{ .w = 100, .h = 20 },
            });
            result.* = normalizedPercentToInt(percent, T, int_opt.min, int_opt.max);
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
        min: ?T = null,
        max: ?T = null,
        dvui_opts: dvui.Options = .{},
    };
}

pub fn floatFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    opt: FloatFieldOptions(T),
) !void {
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();
    try dvui.label(@src(), "{s}", .{name}, .{});

    const maybe_num = try dvui.textEntryNumber(@src(), T, .{ .min = opt.min, .max = opt.max }, opt.dvui_opts);
    if (maybe_num == .Valid) {
        result.* = maybe_num.Valid;
    }
    try dvui.label(@src(), "{d}", .{result.*}, .{});
}

pub const EnumFieldOptions = struct {
    widget_type: enum { radio, dropdown } = .dropdown,
    dvui_opts: dvui.Options = .{},
};

fn enumFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    enum_opt: EnumFieldOptions,
) !void {
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    try dvui.label(@src(), "{s}", .{name}, .{});
    switch (enum_opt.widget_type) {
        .dropdown => {
            const entries = std.meta.fieldNames(T);
            var choice: usize = @intFromEnum(result.*);
            _ = try dvui.dropdown(@src(), entries, &choice, enum_opt.dvui_opts);
            result.* = @enumFromInt(choice);
        },
        .radio => {
            inline for (@typeInfo(T).Enum.fields) |field| {
                if (try dvui.radio(
                    @src(),
                    result.* == @as(T, @enumFromInt(field.value)),
                    field.name,
                    enum_opt.dvui_opts,
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
};

fn boolFieldWidget(
    comptime name: []const u8,
    result: *bool,
    comptime bool_opt: BoolFieldOptions,
) !void {
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    //TODO implement dvui_opts for other types
    switch (bool_opt.widget_type) {
        .checkbox => {
            try dvui.label(@src(), "{s}", .{name}, .{});
            _ = try dvui.checkbox(@src(), result, "", bool_opt.dvui_opts);
        },
        .dropdown => {
            const entries = .{ "false", "true" };
            var choice: usize = if (result.* == false) 0 else 1;
            try dvui.labelNoFmt(@src(), name, .{});
            _ = try dvui.dropdown(@src(), &entries, &choice, .{});
            result.* = if (choice == 0) false else true;
        },
        .toggle => {
            switch (result.*) {
                true => {
                    if (try dvui.button(
                        @src(),
                        name ++ " enabled",
                        .{},
                        .{ .border = border, .background = true },
                    )) {
                        result.* = !result.*;
                    }
                },
                false => {
                    if (try dvui.button(
                        @src(),
                        name ++ " disabled",
                        .{},
                        .{ .border = border, .background = true },
                    )) {
                        result.* = !result.*;
                    }
                },
            }
        },
    }
}

//=======Optional Field Widget and Options=======
pub fn UnionFieldOptions(comptime T: type) type {
    //TODO
    _ = T; //autofix
    return struct {
        //child_opts: FieldOptions(@typeInfo(T).Optional.child) = .{},
    };
}

pub fn unionFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime options: UnionFieldOptions(T),
    comptime alloc: bool,
) !void {
    _ = options; // autofix
    var box = try dvui.box(@src(), .vertical, .{});
    defer box.deinit();

    const FieldEnum = std.meta.FieldEnum(T);

    const entries = std.meta.fieldNames(T);
    var choice: usize = @intFromEnum(std.meta.activeTag(result.*));

    {
        var hbox = try dvui.box(@src(), .vertical, .{});
        defer hbox.deinit();
        if (name.len != 0) {
            try dvui.label(@src(), "{s}", .{name}, .{
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

            //TODO support child opts
            try fieldWidget(
                field.name,
                field.type,
                @ptrCast(field_result),
                .{},
                alloc,
            );
        }
    }
}

//=======Optional Field Widget and Options=======
pub fn OptionalFieldOptions(comptime T: type) type {
    return struct {
        child_opts: FieldOptions(@typeInfo(T).Optional.child) = .{},
    };
}

pub fn optionalFieldWidget(
    //comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime options: OptionalFieldOptions(T),
    comptime alloc: bool,
) !void {
    var box = try dvui.box(@src(), .vertical, .{});
    defer box.deinit();

    const Child = @typeInfo(T).Optional.child;

    const checkbox_state = dvui.dataGetPtrDefault(
        null,
        box.widget().data().id,
        "checked",
        bool,
        false,
    );
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        try dvui.label(@src(), "{s}?", .{name}, .{});
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
        try fieldWidget("", Child, @ptrCast(result), options.child_opts, alloc);
    } else {
        result.* = null;
    }
}

//==========Text Field Widget and Options============

pub const TextFieldOptions = struct {
    max_len: u16 = 64,
    dvui_opts: dvui.Options = .{},
};

fn textFieldWidget(
    //comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    result: *[]const u8,
    comptime text_opt: TextFieldOptions,
    comptime alloc: bool,
) !void {

    //TODO respect alloc setting
    _ = alloc; // autofix
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    try dvui.label(@src(), "{s}", .{name}, .{});
    const buffer = dvui.dataGetSliceDefault(
        dvui.currentWindow(),
        box.widget().data().id,
        "buffer",
        []u8,
        result.*,
    );

    const text_box = try dvui.textEntry(@src(), .{ .text = buffer }, text_opt.dvui_opts);
    defer text_box.deinit();

    result.* = text_box.getText();
}

pub fn PointerFieldOptions(comptime T: type) type {
    const info = @typeInfo(T).Pointer;

    if (info.size == .Slice and info.child == u8) {
        return TextFieldOptions;
    } else if (info.size == .Slice) {
        return SliceFieldOptions(T);
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
    comptime options: PointerFieldOptions(T),
    comptime alloc: bool,
) !void {
    const info = @typeInfo(T).Pointer;

    if (info.size == .Slice and info.child == u8) {
        try textFieldWidget(name, result, options, alloc);
    } else if (info.size == .Slice) {
        try sliceFieldWidget(name, T, result, options, alloc);
    } else if (info.size == .One) {
        try singlePointerFieldWidget(T, name, result, options, alloc);
    } else if (info.size == .C or info.size == .Many) {
        @compileError("structEntry does not support *C or Many pointers");
    }
}

//=======Single Item pointer and options=======
pub fn SinglePointerFieldOptions(comptime T: type) type {
    return struct {
        child_opts: FieldOptions(@typeInfo(T).Pointer.child) = .{},
    };
}

pub fn singlePointerFieldWidget(
    //comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    options: SinglePointerFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    var box = try dvui.box(@src(), .horizontal, .{});
    defer box.deinit();

    const Child = @typeInfo(T).Pointer.child;

    const destination = if (alloc)
        try dvui.dataGetPtrDefault(dvui.currentWindow(), box.widget().data().id, "ptr", T, undefined)
    else
        result;
    result.* = destination;

    try fieldWidget(@src(), name, Child, result.*, options.child_opts, alloc, paned);
}

//=======Single Item pointer and options=======
pub fn SliceFieldOptions(comptime T: type) type {
    return struct {
        child_opts: FieldOptions(@typeInfo(T).Pointer.child) = .{},
    };
}

//TODO implement this using reorderable lists and use this as the backend for array and vector widgets
pub fn sliceFieldWidget(
    //comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    options: SliceFieldOptions(T),
    comptime alloc: bool,
) !void {
    _ = name; // autofix
    _ = result; // autofix
    _ = options; // autofix
    _ = alloc; // autofix
    @compileError("TODO");
}

//==========Struct Field Widget and Options
pub fn StructFieldOptions(comptime T: type) type {
    var fields: [@typeInfo(T).Struct.fields.len]std.builtin.Type.StructField = undefined;

    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
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

fn structFieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime struct_opts: StructFieldOptions(T),
    comptime alloc: bool,
) !void {
    _ = name; // autofix
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");
    const fields = @typeInfo(T).Struct.fields;

    var box = try dvui.box(@src(), .vertical, .{ .expand = .both });
    defer box.deinit();

    var left_alignment = dvui.Alignment.init();
    defer left_alignment.deinit();

    inline for (fields, 0..) |field, i| {
        const options = @field(struct_opts, field.name);
        const result_ptr = &@field(result.*, field.name);

        if (@typeInfo(field.type) == .Struct) {
            if (try dvui.expander(@src(), field.name, .{}, .{ .id_extra = i })) {
                var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .both, .id_extra = i });
                defer hbox.deinit();

                try dvui.separator(@src(), .{ .expand = .vertical, .min_size_content = .{ .w = 2 }, .margin = dvui.Rect.all(4) });

                {
                    //TODO get left align working
                    var vbox = try dvui.box(@src(), .vertical, .{
                        .expand = .both,
                        .id_extra = i,
                        //.margin = left_alignment.margin(box.data().id),
                    });
                    defer vbox.deinit();
                    try fieldWidget(field.name, field.type, result_ptr, options, alloc);
                    //left_alignment.record(hbox.data().id, vbox.data());
                }
            }
        } else {
            var vbox = try dvui.box(@src(), .vertical, .{
                .expand = .both,
                .id_extra = i,
            });
            defer vbox.deinit();
            try fieldWidget(field.name, field.type, result_ptr, options, alloc);
        }
    }
}

//=========Generic Field Widget and Options===========
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

pub fn fieldWidget(
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime options: FieldOptions(T),
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

//=========PUBLIC API FUNCTIONS===========
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
    comptime field_options: StructFieldOptions(T),
) !void {
    var box = try dvui.box(src, .vertical, .{ .expand = .both });
    defer box.deinit();
    try structFieldWidget(name, T, result, field_options, false);
}

pub fn structEntryAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
) !void {
    var box = try dvui.box(src, .vertical, .{ .expand = .both });
    defer box.deinit();
    try structFieldWidget("", T, result, .{}, true);
}

pub fn structEntryExAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime field_options: StructFieldOptions(T),
) !void {
    var box = try dvui.box(src, .vertical, .{ .expand = .both });
    defer box.deinit();
    try structFieldWidget(name, T, result, field_options, true);
}

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
