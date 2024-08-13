const std = @import("std");
const dvui = @import("dvui");

pub fn IntFieldOptions(comptime T: type) type {
    return ?struct {
        min: T = std.math.intMin(T),
        max: T = std.math.intMax(T),
        widget_type: enum { value_box, slider } = .value_box,
    };
}

pub fn intFieldWidget(src: std.builtin.SourceLocation, comptime T: type, result: *T, int_opt: IntFieldOptions(T), options: dvui.Options) !void {
    _ = src; // autofix
    _ = result; // autofix
    _ = int_opt; // autofix
    _ = options; // autofix
}

pub fn FloatFieldOptions(comptime T: type) type {
    return ?struct {
        min: ?T = null,
        max: ?T = null,
        widget_type: enum { value_box, slider } = .value_box,
    };
}

pub fn floatFieldWidget(src: std.builtin.SourceLocation, comptime T: type, result: *T, float_opt: FloatFieldOptions(T), options: dvui.Options) !void {
    _ = float_opt; // autofix
    _ = src; // autofix
    _ = result; // autofix
    _ = options; // autofix
}

const EnumFieldOptions = ?struct {
    widget_type: enum { radio, dropdown } = .dropdown,
};

pub fn enumFieldWidget(src: std.builtin.SourceLocation, comptime T: type, result: *T, enum_opt: EnumFieldOptions, options: dvui.Options) !void {
    _ = enum_opt; // autofix
    _ = src; // autofix
    _ = result; // autofix
    _ = options; // autofix
}

const BoolFieldOptions = ?struct {
    widget_type: enum { radio, checkbox, dropdown, toggle } = .checkbox,
};

pub fn boolFieldWidget(src: std.builtin.SourceLocation, comptime T: type, result: *T, bool_opt: BoolFieldOptions(T), options: dvui.Options) !void {
    _ = bool_opt; // autofix
    _ = src; // autofix
    _ = result; // autofix
    _ = options; // autofix
}

pub fn StructOptions(comptime T: type) type {
    var fields: [@typeInfo(T).Struct.fields.len]std.builtin.Type.StructField = undefined;
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        fields[i] = switch (@typeInfo(field.type)) {
            .Int => .{ .alignment = 1, .default_value = &null, .is_comptime = false, .name = field.name, .type = IntFieldOptions(field.type) },
            .Float => .{ .alignment = 1, .default_value = &null, .is_comptime = false, .name = field.name, .type = FloatFieldOptions(field.type) },
            .Bool => .{ .alignment = 1, .default_value = &null, .is_comptime = false, .name = field.name, .type = BoolFieldOptions },
            .Enum => .{ .alignment = 1, .default_value = &null, .is_comptime = false, .name = field.name, .type = EnumFieldOptions },
            .Struct => .{ .alignment = 1, .default_value = &(StructOptions(field.type){}), .is_comptime = false, .name = field.name, .type = StructOptions(field.type) },
            else => @compileError("Invalid type for field"),
        };
    }

    return @Type(std.builtin.Type{ .Struct = .{ .decls = &.{}, .fields = fields, .is_tuple = false, .layout = .auto } });
}

pub fn structWidget(src: std.builtin.SourceLocation, comptime T: type, result: *T, struct_opts: StructOptions(T), options: dvui.Options) !void {
    _ = options; // autofix
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");

    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {

        // zig fmt: off
        switch (@typeInfo(field.type)) {
            .Int => try intFieldWidget(src, field.type, &@field(result, field.name), @field(struct_opts, field.name), .{ .id_extra = i * 10000 }),
            .Float, try floatFieldWidget(src, field.type, &@field(result, field.name), @field(struct_opts, field.name), .{ .id_extra = i * 10000 }),
            .Bool => try boolFieldWidget(src, field.type, &@field(result, field.name), @field(struct_opts, field.name), .{ .id_extra = i * 10000 }),
            .Enum => try enumFieldWidget(src, field.type, &@field(result, field.name), @field(struct_opts, field.name), .{ .id_extra = i * 10000 }),
            .Struct => try structWidget(src, field.type, &@field(result, field.name), @field(struct_opts, field.name), .{ .id_extra = i * 10000 }),
            else => @compileError("Invalid type given"),
        }
        // zig fmt: on
    }
}
