const std = @import("std");
const dvui = @import("dvui");

//pub fn IntFieldOptions(comptime T: type) type {
//    return struct {
//        min: T = std.math.intMin(T),
//        max: T = std.math.intMax(T),
//        widget_type: enum { value_box, slider } = .value_box,
//    };
//}
//
pub const IntFieldOptions = struct {
    widget_type: enum { value_box, slider } = .value_box,
};

fn intFieldWidget(comptime src: std.builtin.SourceLocation, comptime T: type, int_opt: ?IntFieldOptions(T)) !T {
    _ = src; // autofix
    _ = int_opt; // autofix
}

//fn FloatFieldOptions(comptime T: type) type {
//    const Result = struct {
//        min: ?T = null,
//        max: ?T = null,
//        widget_type: enum { value_box, slider } = .value_box,
//    };
//    @compileLog(T);
//    @compileLog(Result);
//    return Result;
//}

pub const FloatFieldOptions = struct {
    widget_type: enum { value_box, slider } = .value_box,
};

pub fn floatFieldWidget(comptime src: std.builtin.SourceLocation, comptime T: type, float_opt: ?FloatFieldOptions) !T {
    _ = float_opt; // autofix
    _ = src; // autofix
}

pub const EnumFieldOptions = struct {
    widget_type: enum { radio, dropdown } = .dropdown,
};

fn enumFieldWidget(comptime src: std.builtin.SourceLocation, comptime T: type, enum_opt: ?EnumFieldOptions) !T {
    _ = enum_opt; // autofix
    _ = src; // autofix
}

pub const BoolFieldOptions = struct {
    widget_type: enum { radio, checkbox, dropdown, toggle } = .checkbox,
};

fn boolFieldWidget(comptime src: std.builtin.SourceLocation, bool_opt: ?BoolFieldOptions) !bool {
    _ = bool_opt; // autofix
    _ = src; // autofix
}

pub fn StructOptions(comptime T: type) type {
    var fields: [@typeInfo(T).Struct.fields.len]std.builtin.Type.StructField = undefined;
    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        fields[i] = .{
            .alignment = 1,
            .default_value = null,
            .is_comptime = false,
            .name = field.name,
            .type = switch (@typeInfo(field.type)) {
                .Int => ?IntFieldOptions,
                .Float => ?FloatFieldOptions,
                .Bool => ?BoolFieldOptions,
                .Enum => ?EnumFieldOptions,
                .Struct => ?StructOptions(field.type),
                else => @compileError("Invalid type for field"),
            },
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

/// For making sure all elements have unique ids
const RecursionDepthTracker = struct {
    depth: usize = 0,

    const IdExtraType = @typeInfo(@TypeOf(dvui.Options.id_extra)).Optional.child;
    const id_extra_num_bits = @typeInfo(IdExtraType).Int.bits;
    const StructIdExtraType = u8;
    const max_bits_per_struct = @typeInfo(StructIdExtraType).Int.bits;
    const max_recursion_depth = id_extra_num_bits / max_bits_per_struct;

    pub fn getIdExtra(self: RecursionDepthTracker, index: StructIdExtraType) IdExtraType {
        return (1 << (self.depth * max_bits_per_struct)) + index;
    }

    pub fn descend(self: RecursionDepthTracker) RecursionDepthTracker {
        if (self.depth < max_bits_per_struct) {
            return .{ .depth = self.depth + 1 };
        } else {
            @compileError("Struct has too much recursion");
        }
    }
};

fn structFieldWidget(comptime src: std.builtin.SourceLocation, comptime T: type, comptime struct_opts: ?StructOptions(T), comptime depth: RecursionDepthTracker) !T {
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |field| {
        const options = if (struct_opts != null) @field(struct_opts.?, field.name) else null;
        @compileLog(options);

        // zig fmt: off
        @field(result, field.name) = switch (@typeInfo(field.type)) {
            .Int => try intFieldWidget(src, field.type, options),
            .Float, try floatFieldWidget(src, field.type, options),
            .Bool => try boolFieldWidget(src, field.type, options),
            .Enum => try enumFieldWidget(src, field.type, options),
            .Struct => try structFieldWidget(src, field.type, options, depth.descend()),
            else => @compileError("Invalid type given"),
        };
        // zig fmt: on
    }
    return result;
}

pub fn structWidget(comptime src: std.builtin.SourceLocation, comptime T: type, struct_opts: ?StructOptions(T)) !T {
    _ = struct_opts; // autofix
    return try structFieldWidget(src, T, null, .{});
}
