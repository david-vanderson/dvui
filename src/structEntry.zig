const std = @import("std");
const dvui = @import("dvui.zig");

const border = dvui.Rect{ .h = 1, .w = 1, .x = 1, .y = 1 };

pub const IntFieldOptions = struct {
    widget_type: enum { number_entry, slider } = .number_entry,
};

fn intFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime int_opt: IntFieldOptions,
) !void {
    switch (int_opt.widget_type) {
        .number_entry => {
            var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
            defer box.deinit();

            try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next(), .border = border, .background = true, .expand = .horizontal });
            const maybe_num = try dvui.textEntryNumber(src, T, .{}, .{ .id_extra = id_allocator.next() });
            if (maybe_num == .Valid) {
                result.* = maybe_num.Valid;
            }
            try dvui.label(src, "{}", .{result.*}, .{ .id_extra = id_allocator.next() });
        },
        .slider => {
            var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
            defer box.deinit();

            try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next(), .border = border, .background = true, .expand = .horizontal });

            var percent = intToNormalizedPercent(result.*);
            _ = try dvui.slider(
                src,
                .horizontal,
                &percent,
                .{ .id_extra = id_allocator.next(), .expand = .horizontal, .min_size_content = .{ .w = 100, .h = 20 } },
            );
            result.* = normalizedPercentToInt(percent, T);
            try dvui.label(src, "{}", .{result.*}, .{ .id_extra = id_allocator.next() });
        },
    }
}

fn normalizedPercentToInt(normalized_percent: f32, comptime T: type) T {
    if (@typeInfo(T) != .Int) @compileError("T is not an int type");
    std.debug.assert(normalized_percent >= 0);
    std.debug.assert(normalized_percent <= 1);

    const min: f32 = @floatFromInt(std.math.minInt(T));
    const max: f32 = @floatFromInt(std.math.maxInt(T));
    const range = max + @abs(min);

    return @intFromFloat(min + (range * normalized_percent));
}

fn intToNormalizedPercent(int: anytype) f32 {
    const min: f32 = @floatFromInt(std.math.minInt(@TypeOf(int)));
    const max: f32 = @floatFromInt(std.math.maxInt(@TypeOf(int)));
    const range = max + @abs(min);
    const progress: f32 = @as(f32, @floatFromInt(int)) + @abs(min);
    const result = progress / range;

    std.debug.assert(result >= 0);
    std.debug.assert(result <= 1);

    return result;
}

pub const FloatFieldOptions = struct {
    //TODO implement min and max
};

pub fn floatFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    _: FloatFieldOptions,
) !void {
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();
    try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next(), .border = border, .background = true, .expand = .horizontal });

    const maybe_num = try dvui.textEntryNumber(src, T, .{}, .{ .id_extra = id_allocator.next() });
    if (maybe_num == .Valid) {
        result.* = maybe_num.Valid;
    }
    try dvui.label(src, "{d}", .{result.*}, .{ .id_extra = id_allocator.next() });
}

pub const EnumFieldOptions = struct {
    widget_type: enum { radio, dropdown } = .dropdown,
};

fn enumFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    enum_opt: EnumFieldOptions,
) !void {
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next(), .border = border, .background = true, .expand = .horizontal });
    switch (enum_opt.widget_type) {
        .dropdown => {
            const entries = std.meta.fieldNames(T);
            var choice: usize = @intFromEnum(result.*);
            _ = try dvui.dropdown(src, entries, &choice, .{ .id_extra = id_allocator.next() });
            result.* = @enumFromInt(choice);
        },
        .radio => {
            inline for (@typeInfo(T).Enum.fields) |field| {
                if (try dvui.radio(
                    @src(),
                    result.* == @as(T, @enumFromInt(field.value)),
                    field.name,
                    .{ .id_extra = id_allocator.next() },
                )) {
                    result.* = @enumFromInt(field.value);
                }
            }
        },
    }
}

pub const BoolFieldOptions = struct {
    widget_type: enum { checkbox, dropdown, toggle } = .toggle,
};

fn boolFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    result: *bool,
    id_allocator: IdAllocator,
    comptime bool_opt: BoolFieldOptions,
) !void {
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    switch (bool_opt.widget_type) {
        .checkbox => {
            try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next(), .border = border, .background = true, .expand = .horizontal });
            _ = try dvui.checkbox(src, result, "", .{ .id_extra = id_allocator.next() });
        },
        .dropdown => {
            const entries = .{ "false", "true" };
            var choice: usize = if (result.* == false) 0 else 1;
            try dvui.labelNoFmt(src, name, .{ .id_extra = id_allocator.next(), .background = true, .border = border });
            _ = try dvui.dropdown(src, &entries, &choice, .{ .id_extra = id_allocator.next() });
            result.* = if (choice == 0) false else true;
        },
        .toggle => {
            switch (result.*) {
                true => {
                    if (try dvui.button(src, name ++ " enabled", .{}, .{ .id_extra = id_allocator.next(), .border = border, .background = true })) {
                        result.* = !result.*;
                    }
                },
                false => {
                    if (try dvui.button(src, name ++ " disabled", .{}, .{ .id_extra = id_allocator.next(), .border = border, .background = true })) {
                        result.* = !result.*;
                    }
                },
            }
        },
    }
}

//=======Optional Field Widget and Options=======
pub fn UnionFieldOptions(comptime T: type) type {
    _ = T; // autofix
    return struct {
        //child_opts: FieldOptions(@typeInfo(T).Optional.child) = .{},
    };
}

pub fn unionFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime options: UnionFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    _ = options; // autofix
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    const FieldEnum = std.meta.FieldEnum(T);

    const entries = std.meta.fieldNames(T);
    var choice: usize = @intFromEnum(std.meta.activeTag(result.*));

    try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next(), .border = border, .background = true });
    _ = try dvui.dropdown(src, entries, &choice, .{ .id_extra = id_allocator.next() });

    inline for (@typeInfo(T).Union.fields, 0..) |field, i| {
        if (choice == i) {
            if (std.meta.activeTag(result.*) != @as(FieldEnum, @enumFromInt(i))) {
                result.* = @unionInit(T, field.name, undefined);
            }
            const field_result: *field.type = &@field(result.*, field.name);
            //TODO support child opts
            try fieldWidget(src, field.name, field.type, @ptrCast(field_result), id_allocator, .{}, alloc, paned);
            //result.* = @unionInit(T, field.name, field_result.*);
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
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime options: OptionalFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    const Child = @typeInfo(T).Optional.child;

    const checkbox_state = dvui.dataGetPtrDefault(dvui.currentWindow(), box.widget().data().id, "checked", bool, false);
    {
        var hbox = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
        defer hbox.deinit();
        try dvui.label(src, "{s}?", .{name}, .{ .id_extra = id_allocator.next() });
        _ = try dvui.checkbox(src, checkbox_state, null, .{ .id_extra = id_allocator.next() });
    }

    if (checkbox_state.*) {
        try fieldWidget(src, "", Child, @ptrCast(result), id_allocator, options.child_opts, alloc, paned);
    } else {
        result.* = null;
    }
}

//==========Text Field Widget and Options============

pub const TextFieldOptions = struct {
    max_len: u16 = 64,
};

fn textFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    result: *[]const u8,
    id_allocator: IdAllocator,
    comptime text_opt: TextFieldOptions,
    comptime alloc: bool,
) !void {

    //TODO respect alloc setting
    _ = alloc; // autofix
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next(), .border = border, .background = true, .expand = .horizontal });
    const buffer = dvui.dataGetSliceDefault(
        dvui.currentWindow(),
        box.widget().data().id,
        "buffer",
        []u8,
        &([_]u8{0} ** text_opt.max_len),
    );

    const text_box = try dvui.textEntry(src, .{ .text = buffer }, .{ .id_extra = id_allocator.next() });
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
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime options: PointerFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    const info = @typeInfo(T).Pointer;

    if (info.size == .Slice and info.child == u8) {
        try textFieldWidget(src, name, result, id_allocator, options, alloc);
    } else if (info.size == .Slice) {
        try sliceFieldWidget(src, name, T, result, id_allocator, options, alloc, paned);
    } else if (info.size == .One) {
        try singlePointerFieldWidget(src, T, name, result, id_allocator, options, alloc, paned);
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
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    options: SinglePointerFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    const Child = @typeInfo(T).Pointer.child;

    const destination = if (alloc)
        try dvui.dataGetPtrDefault(dvui.currentWindow(), box.widget().data().id, "ptr", T, undefined)
    else
        result;
    result.* = destination;

    try fieldWidget(src, name, Child, result.*, id_allocator, options.child_opts, alloc, paned);
}

//=======Single Item pointer and options=======
pub fn SliceFieldOptions(comptime T: type) type {
    return struct {
        child_opts: FieldOptions(@typeInfo(T).Pointer.child) = .{},
        //capacity: ?usize = null, //if alloc is false the slice assumes max_len space is avaiable
    };
}

//TODO implement this using reorderable lists and use this as the backend for array and vector widgets
pub fn sliceFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    options: SliceFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    const Child = @typeInfo(T).Pointer.child;

    result.* = if (alloc)
        try dvui.dataGetSliceDefault(dvui.currentWindow(), box.widget().data().id, "slice", []T, [_]T{undefined})
    else
        result.*;

    for (0..result.*.len) |i| {
        try fieldWidget(src, name, Child, &(result.*[i]), id_allocator, options.child_opts, alloc, paned);
    }
}

//==========Struct Field Widget and Options
pub fn StructFieldOptions(comptime T: type) type {
    var fields: [@typeInfo(T).Struct.fields.len]std.builtin.Type.StructField = undefined;

    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        const FieldType = FieldOptions(field.type);
        fields[i] = .{
            .alignment = 1,
            .default_value = @alignCast(@ptrCast(&(@as(?FieldType, FieldType{})))),
            .is_comptime = false,
            .name = field.name,
            .type = ?FieldType,
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
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime struct_opts: StructFieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");
    const fields = @typeInfo(T).Struct.fields;

    var hbox = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next(), .border = border, .expand = .both, .background = true });
    defer hbox.deinit();

    var selected: *?usize = undefined;
    {
        var box = try dvui.box(src, .vertical, .{
            .id_extra = id_allocator.next(),
            .border = border,
            .background = true,
            .expand = .both,
        });
        defer box.deinit();

        if (name.len != 0) {
            try dvui.label(src, "{s}", .{name}, .{
                .id_extra = id_allocator.next(),
                .border = border,
                .background = true,
                .expand = .horizontal,
                //.color_fill = .{ .name = .fill_hover },
            });
        }

        var scroll = try dvui.scrollArea(src, .{ .expand_to_fit = true }, .{ .id_extra = id_allocator.next() });
        defer scroll.deinit();

        selected = dvui.dataGetPtrDefault(dvui.currentWindow(), box.widget().data().id, "selected", ?usize, null);
        inline for (fields, 0..) |field, i| {
            const options: dvui.Options = .{
                .id_extra = id_allocator.next(),
                .background = true,
                .color_fill = .{ .name = if (selected.* == i) .fill_hover else .fill },
            };
            if (try dvui.button(src, field.name, .{}, options)) {
                if (selected.* != i) {
                    selected.* = i;
                } else {
                    selected.* = null;
                }
            }
        }

        if (paned.collapsed()) {
            paned.animateSplit(1.0);
        }
    }

    {
        inline for (fields, 0..) |field, i| {
            if (i == selected.*) {
                const options = @field(struct_opts, field.name);
                const result_ptr = &@field(result.*, field.name);

                //skip widget if set to null
                if (options != null) {
                    if (@typeInfo(field.type) == .Struct) {
                        try fieldWidget(src, field.name, field.type, result_ptr, id_allocator, options.?, alloc, paned);
                    } else {
                        try fieldWidget(src, field.name, field.type, result_ptr, id_allocator, options.?, alloc, paned);
                    }
                }
            }
        }
    }
}

//=========Generic Field Widget and Options===========
pub fn FieldOptions(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Int => IntFieldOptions,
        .Float => FloatFieldOptions,
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
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime options: FieldOptions(T),
    comptime alloc: bool,
    paned: *dvui.PanedWidget,
) !void {
    switch (@typeInfo(T)) {
        .Int => try intFieldWidget(src, name, T, result, id_allocator, options),
        .Float => try floatFieldWidget(src, name, T, result, id_allocator, options),
        .Bool => try boolFieldWidget(src, name, result, id_allocator, options),
        .Enum => try enumFieldWidget(src, name, T, result, id_allocator, options),
        .Pointer => try pointerFieldWidget(src, name, T, result, id_allocator, options, alloc, paned),
        .Optional => try optionalFieldWidget(src, name, T, result, id_allocator, options, alloc, paned),
        .Union => try unionFieldWidget(src, name, T, result, id_allocator, options, alloc, paned),
        .Struct => try structFieldWidget(src, name, T, result, id_allocator, options, alloc, paned),
        else => @compileError("Invalid type: " ++ @typeName(T)),
    }
}

//==========For Allocating Extra Ids===========
const IdExtraType = u64;
const IdAllocator = struct {
    active_id: *IdExtraType,

    pub fn next(self: @This()) IdExtraType {
        const result = self.active_id.*;
        self.active_id.* += 1;
        return result;
    }
};

//========Internal Struct Entry Entrypoint=========
fn structEntryInternal(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    comptime field_options: StructFieldOptions(T),
    comptime alloc: bool,
    comptime name: []const u8,
) !void {
    var starting_id_extra: IdExtraType = 1;
    const id_allocator = IdAllocator{ .active_id = &starting_id_extra };

    var box = try dvui.boxEqual(src, .vertical, .{ .id_extra = id_allocator.next(), .color_border = .{ .name = .border }, .expand = .both });
    defer box.deinit();

    var pane = try dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = 10 }, .{ .id_extra = id_allocator.next(), .background = true });
    defer pane.deinit();

    pane.collapsing = false;
    pane.collapsed_state = false;
    try structFieldWidget(src, name, T, result, id_allocator, field_options, alloc, pane);
}

//=========PUBLIC API FUNCTIONS===========
pub fn structEntry(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
) !void {
    try structEntryInternal(src, T, result, .{}, false, "");
}

pub fn structEntryEx(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime field_options: StructFieldOptions(T),
) !void {
    try structEntryInternal(src, T, result, field_options, false, name);
}

pub fn structEntryAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
) !void {
    try structEntryInternal(src, T, result, .{}, true, "");
}

pub fn structEntryExAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    comptime field_options: StructFieldOptions(T),
) !void {
    try structEntryInternal(src, T, result, field_options, true, name);
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
