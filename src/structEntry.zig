const std = @import("std");
const dvui = @import("dvui.zig");

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
            var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
            defer box.deinit();

            try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next() });
            const buffer = dvui.dataGetSliceDefault(
                dvui.currentWindow(),
                box.widget().data().id,
                "buffer",
                []u8,
                &([_]u8{0} ** 32),
            );
            const maybe_num = try dvui.textEntryNumber(src, T, .{ .text = buffer }, .{ .id_extra = id_allocator.next() });
            if (maybe_num) |num| {
                result.* = num;
            }
            try dvui.label(src, "{}", .{result.*}, .{ .id_extra = id_allocator.next() });
        },
        .slider => {
            var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
            defer box.deinit();

            try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next() });

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
    var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next() });
    const buffer = dvui.dataGetSliceDefault(
        dvui.currentWindow(),
        box.widget().data().id,
        "buffer",
        []u8,
        &([_]u8{0} ** 32),
    );
    const maybe_num = try dvui.textEntryNumber(src, T, .{ .text = buffer }, .{ .id_extra = id_allocator.next() });
    if (maybe_num) |num| {
        result.* = num;
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

    try dvui.label(src, "{s}:", .{name}, .{ .id_extra = id_allocator.next() });
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
    widget_type: enum { checkbox, dropdown, toggle } = .checkbox,
};

fn boolFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    result: *bool,
    id_allocator: IdAllocator,
    comptime bool_opt: BoolFieldOptions,
) !void {
    var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    switch (bool_opt.widget_type) {
        .checkbox => {
            try dvui.labelNoFmt(src, name, .{ .id_extra = id_allocator.next() });
            _ = try dvui.checkbox(src, result, "", .{ .id_extra = id_allocator.next() });
        },
        .dropdown => {
            const entries = .{ "false", "true" };
            var choice: usize = if (result.* == false) 0 else 1;
            try dvui.labelNoFmt(src, name, .{ .id_extra = id_allocator.next() });
            _ = try dvui.dropdown(src, &entries, &choice, .{ .id_extra = id_allocator.next() });
            result.* = if (choice == 0) false else true;
        },
        .toggle => {
            switch (result.*) {
                true => {
                    if (try dvui.button(src, name ++ " enabled", .{}, .{ .id_extra = id_allocator.next() })) {
                        result.* = !result.*;
                    }
                },
                false => {
                    if (try dvui.button(src, name ++ " disabled", .{}, .{ .id_extra = id_allocator.next() })) {
                        result.* = !result.*;
                    }
                },
            }
        },
    }
}

pub const TextFieldOptions = struct {
    max_len: u16 = 64,
};

fn textFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    result: *[]const u8,
    id_allocator: IdAllocator,
    comptime text_opt: TextFieldOptions,
) !void {
    var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
    defer box.deinit();

    try dvui.label(src, "{s}", .{name}, .{ .id_extra = id_allocator.next() });
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
        //return SliceFieldOptions(T);
    } else if (info.size == .One) {
        //return SinglePointerFieldOptions(T);
    } else if (info.size == .C or info.size == .Many) {
        //return ManyPointerFieldOptions(T);
    }

    @compileError("todo");
}

pub fn pointerFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    options: PointerFieldOptions(T),
    comptime alloc: bool,
    allocator: ?std.mem.Allocator,
) !void {
    if (!alloc) @compileError("allocator must exist for pointers");

    const info = @typeInfo(T).Pointer;

    if (info.size == .Slice and info.child == u8) {
        try textFieldWidget(src, name, result, id_allocator, options, allocator.?);
    } else if (info.size == .Slice) {
        //return SliceFieldOptions(T);
    } else if (info.size == .One) {
        //return SinglePointerFieldOptions(T);
    } else if (info.size == .C or info.size == .Many) {
        //return ManyPointerFieldOptions(T);
    }
}

//=======Single Item pointer and options=======
pub fn SinglePointerFieldOptions(comptime T: type) {
    
}

//==========Struct Field Widget and Options
pub fn StructFieldWidgetOptions(comptime T: type) type {
    var fields: [@typeInfo(T).Struct.fields.len]std.builtin.Type.StructField = undefined;
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        const FieldOptionType = switch (@typeInfo(field.type)) {
            .Int => IntFieldOptions,
            .Float => FloatFieldOptions,
            .Bool => BoolFieldOptions,
            .Enum => EnumFieldOptions,
            .Pointer => PointerFieldOptions(field.type),
            .Struct => StructFieldWidgetOptions(field.type),
            else => @compileError("Invalid type for field"),
        };
        fields[i] = .{
            .alignment = 1,
            .default_value = @alignCast(@ptrCast(&(FieldOptionType{}))),
            .is_comptime = false,
            .name = field.name,
            .type = FieldOptionType,
        };
    }

    return @Type(.{
        .Struct = .{
            .decls = &.{},
            .fields = &fields,
            .is_tuple = false,
            .layout = .auto,
        },
    });
}

fn structFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime struct_opts: StructFieldWidgetOptions(T),
    comptime expander: bool,
    comptime alloc: bool,
    allocator: ?std.mem.Allocator,
) !void {
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");

    var render: bool = true;
    if (expander) {
        render = try dvui.expander(src, name, .{}, .{ .id_extra = id_allocator.next() });
    }

    if (render) {
        inline for (@typeInfo(T).Struct.fields) |field| {
            const options = @field(struct_opts, field.name);
            const result_ptr = &@field(result.*, field.name);
            try fieldWidget(src, field.name, field.type, result_ptr, id_allocator, options, alloc, allocator);
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
        .Struct => StructFieldWidgetOptions(T),
        .Pointer => PointerFieldOptions(T),
        else => @compileError("Invalid Type"),
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
    allocator: ?std.mem.Allocator,
) !void {
    switch (@typeInfo(T)) {
        .Int => try intFieldWidget(src, name, T, result, id_allocator, options),
        .Float => try floatFieldWidget(src, name, T, result, id_allocator, options),
        .Bool => try boolFieldWidget(src, name, result, id_allocator, options),
        .Enum => try enumFieldWidget(src, name, T, result, id_allocator, options),
        .Pointer => try pointerFieldWidget(src, name, T, result, id_allocator, options, alloc, allocator),
        .Struct => try structFieldWidget(src, name, T, result, id_allocator, options, true, alloc, allocator),
        else => @compileError("Invalid type"),
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
    comptime field_options: StructFieldWidgetOptions(T),
    comptime alloc: bool,
) !StructEntryAllocResult(T){
    var result: StructEntryAllocResult(T) = .{.value = undefined};
    
    var starting_id_extra: IdExtraType = 1;
    const id_allocator = IdAllocator{ .active_id = &starting_id_extra };

    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next(), .color_border = .{ .name = .border } });
    defer box.deinit();

    try structFieldWidget(src, "", T, &result.value, id_allocator, field_options, false, alloc);

    return result;
}

//=========PUBLIC API FUNCTIONS===========
pub fn structEntry(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
) !void {
    result.* = (try structEntryInternal(src, T, .{}, false)).value;
}

pub fn structEntryEx(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    comptime field_options: StructFieldWidgetOptions(T),
) !void {
    result.* = (try structEntryInternal(src, T, field_options, false)).value;
}

pub fn structEntryAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
) !StructEntryAllocResult(T) {
    return try structEntryInternal(src, T, .{}, true);
}

pub fn structEntryExAlloc(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    comptime field_options: StructFieldWidgetOptions(T),
) !StructEntryAllocResult(T) {
    return structEntryInternal(src, T, field_options, true);
}

//============Alloc result type========
pub fn StructEntryAllocResult(comptime T: type) type {
    return struct {
        result: T,

        pub fn getOwnedCopy(self: *@This(), a: std.mem.Allocator) !Parsed(T) {
            var arena = std.heap.ArenaAllocator.init(a);

            //perform deep copy
            const value = try deepCopyStruct(arena.allocator(), self.result.*);

            return .{ .value = value, .arena = arena };
        }
    };
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
