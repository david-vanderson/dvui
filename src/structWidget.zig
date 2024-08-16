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
    _ = name; // autofix
    _ = int_opt; // autofix
    _ = result; // autofix
    var box = try dvui.box(src, .horizontal, .{ .id_extra = id_allocator.next() });
    defer box.deinit();
    //try dvui.label(src, "{s}: {s}", .{ name, @typeName(T) }, .{ .id_extra = id_allocator.next() });
    //switch(int_opt.widget_type) {
    //    .number_entry => {
    //        result.* = try dvui.textEntryNumber(src, T, 
    //    }
    //}
}

pub const FloatFieldOptions = struct {
    widget_type: enum { value_box, slider } = .value_box,
};

pub fn floatFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    float_opt: FloatFieldOptions,
) !void {
    _ = float_opt; // autofix
    _ = result; // autofix
    //
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();
    try dvui.label(src, "{s}: {s}", .{ name, @typeName(T) }, .{ .id_extra = id_allocator.next() });
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
    _ = enum_opt; // autofix
    _ = result; // autofix
    var box = try dvui.box(src, .vertical, .{ .id_extra = id_allocator.next() });
    defer box.deinit();
    try dvui.label(src, "{s}: {s}", .{ name, @typeName(T) }, .{ .id_extra = id_allocator.next() });
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
            _ = try dvui.checkbox(src, result, name, .{ .id_extra = id_allocator.next() });
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

pub fn StructFieldOptions(comptime T: type) type {
    var fields: [@typeInfo(T).Struct.fields.len]std.builtin.Type.StructField = undefined;
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        const FieldType = switch (@typeInfo(field.type)) {
            .Int => IntFieldOptions,
            .Float => FloatFieldOptions,
            .Bool => BoolFieldOptions,
            .Enum => EnumFieldOptions,
            .Struct => StructFieldOptions(field.type),
            else => @compileError("Invalid type for field"),
        };
        fields[i] = .{
            .alignment = 1,
            .default_value = @alignCast(@ptrCast(&(FieldType{}))),
            .is_comptime = false,
            .name = field.name,
            .type = FieldType,
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

const IdExtraType = u64; //@typeInfo(@TypeOf(dvui.Options.id_extra)).Optional.child;
const IdAllocator = struct {
    active_id: *IdExtraType,

    pub fn next(self: @This()) IdExtraType {
        const result = self.active_id.*;
        self.active_id.* += 1;
        return result;
    }
};

fn structFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime name: []const u8,
    comptime T: type,
    result: *T,
    id_allocator: IdAllocator,
    comptime struct_opts: StructFieldOptions(T),
) !void {
    _ = name; // autofix
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");

    inline for (@typeInfo(T).Struct.fields) |field| {
        const options = @field(struct_opts, field.name);
        const result_ptr = &@field(result.*, field.name);

        switch (@typeInfo(field.type)) {
            .Int => try intFieldWidget(src, field.name, field.type, result_ptr, id_allocator, options),
            .Float => try floatFieldWidget(src, field.name, field.type, result_ptr, id_allocator, options),
            .Bool => try boolFieldWidget(src, field.name, result_ptr, id_allocator, options),
            .Enum => try enumFieldWidget(src, field.name, field.type, result_ptr, id_allocator, options),
            .Struct => try structFieldWidget(src, field.name, field.type, result_ptr, id_allocator, options),
            else => @compileError("Invalid type given"),
        }
    }
}

pub fn structEntry(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
) !void {
    try structEntryEx(src, "", T, result, .{}, .{});
}

pub fn structEntryEx(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    comptime field_options: StructFieldOptions(T),
) !void {
    var starting_id_extra: IdExtraType = 1;
    const id_allocator = IdAllocator{ .active_id = &starting_id_extra };
    try structFieldWidget(src, "", T, result, id_allocator, field_options);
}
