const std = @import("std");
const dvui = @import("dvui");

const StructUIOptions = struct {};

pub fn buildStructUI(comptime T: type, result: *T, opts: StructUIOptions) !void {
    _ = opts; // autofix
    if (@typeInfo(T) != .Struct) @compileError("Input Type Must Be A Struct");

    inline for (@typeInfo(T).Struct.fields, 0..) |field, i| {
        addInputWidget(@src(), field.type, &@field(result, field.name), .{ .id_extra = i });
    }
}

pub fn addInputWidget(src: std.builtin.SourceLocation, comptime T: type, result: *T, options: dvui.Options) !void {
    _ = src; // autofix
    _ = result; // autofix
    _ = options; // autofix
    switch (@typeInfo(T)) {
        .Int => {},
        .Float, .ComptimeFloat => {},
        .Pointer => |info| {
            _ = info; // autofix
        },
        .Array => {},
        .Vector => |info| {
            _ = info; // autofix
        },
        .Bool => {},
        .Enum => {},
        .Optional, .Null => {},
        .Struct => |info| {
            _ = info; // autofix
        },
        .Union => |info| {
            _ = info; // autofix
        },
        else => {
            @compileError("Invalid type given");
        },
    }
}
