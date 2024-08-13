const std = @import("std");
const dvui = @import("dvui.zig");

pub const IntFieldOptions = struct {
    widget_type: enum { value_box, slider } = .value_box,
};

fn intFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    id_extra_range: IdExtraRange,
    int_opt: IntFieldOptions,
) !void {
    _ = result; // autofix
    _ = int_opt; // autofix
    try dvui.labelNoFmt(src, @typeName(T), .{ .id_extra = id_extra_range.start });
}

pub const FloatFieldOptions = struct {
    widget_type: enum { value_box, slider } = .value_box,
};

pub fn floatFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    id_extra_range: IdExtraRange,
    float_opt: FloatFieldOptions,
) !void {
    _ = result; // autofix
    _ = float_opt; // autofix
    try dvui.labelNoFmt(src, @typeName(T), .{ .id_extra = id_extra_range.start });
}

pub const EnumFieldOptions = struct {
    widget_type: enum { radio, dropdown } = .dropdown,
};

fn enumFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    id_extra_range: IdExtraRange,
    enum_opt: EnumFieldOptions,
) !void {
    _ = result; // autofix
    _ = enum_opt; // autofix
    try dvui.labelNoFmt(src, @typeName(T), .{ .id_extra = id_extra_range.start });
}

pub const BoolFieldOptions = struct {
    widget_type: enum { radio, checkbox, dropdown, toggle } = .checkbox,
};

fn boolFieldWidget(
    comptime src: std.builtin.SourceLocation,
    retult: *bool,
    id_extra_range: IdExtraRange,
    bool_opt: BoolFieldOptions,
) !void {
    _ = retult; // autofix
    _ = bool_opt; // autofix
    //
    try dvui.labelNoFmt(src, "bool", .{ .id_extra = id_extra_range.start });
}

pub fn StructOptions(comptime T: type) type {
    var fields: [@typeInfo(T).Struct.fields.len]std.builtin.Type.StructField = undefined;
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        const FieldType = switch (@typeInfo(field.type)) {
            .Int => IntFieldOptions,
            .Float => FloatFieldOptions,
            .Bool => BoolFieldOptions,
            .Enum => EnumFieldOptions,
            .Struct => StructOptions(field.type),
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

/// For making sure all elements have unique ids
const RecursionDepthTracker = struct {
    depth: u8 = 0,

    const id_extra_num_bits = @typeInfo(IdExtraType).Int.bits;
    const max_bits_per_struct = 8;
    const max_recursion_depth = id_extra_num_bits / max_bits_per_struct;

    //depth 0
    pub fn getIdExtraRange(comptime self: RecursionDepthTracker, comptime field_widget_index: usize) IdExtraRange {
        const start_offset = (field_widget_index * IdExtraRange.len) + 1;
        const shift_amount: u6 = @intCast(self.depth * max_bits_per_struct);
        const start: IdExtraType = start_offset << shift_amount;
        //@compileLog("depth = ", self.depth);
        //@compileLog("index = ", field_widget_index);
        //@compileLog("start = ", start);
        return .{
            .start = @intCast(start),
            .end = @intCast(start + IdExtraRange.len),
        };
    }

    pub fn descend(comptime self: RecursionDepthTracker) RecursionDepthTracker {
        if (self.depth < max_bits_per_struct) {
            return .{ .depth = self.depth + 1 };
        } else {
            @compileError("Struct has too much recursion");
        }
    }
};

const IdExtraRange = struct {
    start: IdExtraType,
    end: IdExtraType,
    const len = 8;
};

fn structFieldWidget(
    comptime src: std.builtin.SourceLocation,
    comptime T: type,
    result: *T,
    comptime struct_opts: StructOptions(T),
    comptime depth: RecursionDepthTracker,
) !void {
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");

    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        const options = @field(struct_opts, field.name);
        const result_ptr = &@field(result.*, field.name);
        const id_extra_range = depth.getIdExtraRange(i);

        // zig fmt: off
        switch (@typeInfo(field.type)) {
            .Int => try intFieldWidget(      src, field.type, result_ptr, id_extra_range, options),
            .Float => try floatFieldWidget(  src, field.type, result_ptr, id_extra_range, options),
            .Bool => try boolFieldWidget(    src,             result_ptr, id_extra_range, options),
            .Enum => try enumFieldWidget(    src, field.type, result_ptr, id_extra_range, options),
            .Struct => try structFieldWidget(src, field.type, result_ptr, options, depth.descend()),
            else => @compileError("Invalid type given"),
        }
        // zig fmt: on
    }
}

pub fn structWidget(comptime src: std.builtin.SourceLocation, comptime T: type, comptime struct_opts: StructOptions(T)) !T {
    var result: T = undefined;
    try structFieldWidget(src, T, &result, struct_opts, .{});
    return result;
}
