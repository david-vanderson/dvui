const std = @import("std");
const testing = std.testing;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Public API:

/// Serializes the given `value: T` into the `stream`.
/// - `stream` is a instance of `std.Io.Writer`
/// - `T` is the type to serialize
/// - `value` is the instance to serialize.
pub fn serialize(stream: *std.Io.Writer, comptime T: type, value: T) std.Io.Writer.Error!void {
    comptime validateTopLevelType(T);
    const type_hash = comptime computeTypeHash(T);

    try stream.writeAll(type_hash[0..]);
    try serializeRecursive(stream, T, value);
    try stream.flush();
}

/// Deserializes a value of type `T` from the `stream`.
/// - `stream` is a instance of `std.Io.Reader`
/// - `T` is the type to deserialize
pub fn deserialize(
    stream: *std.Io.Reader,
    comptime T: type,
) (std.Io.Reader.Error || error{ UnexpectedData, EndOfStream })!T {
    comptime validateTopLevelType(T);
    if (comptime requiresAllocationForDeserialize(T))
        @compileError(@typeName(T) ++ " requires allocation to be deserialized. Use deserializeAlloc instead of deserialize!");
    return deserializeInternal(stream, T, null) catch |err| switch (err) {
        error.OutOfMemory => unreachable,
        else => |e| return e,
    };
}

/// Deserializes a value of type `T` from the `stream`.
/// - `stream` is a instance of `std.Io.Reader`
/// - `T` is the type to deserialize
/// - `allocator` is an allocator require to allocate slices and pointers.
/// Result must be freed by using `free()`.
pub fn deserializeAlloc(
    stream: *std.Io.Reader,
    comptime T: type,
    allocator: std.mem.Allocator,
) (std.Io.Reader.Error || error{ UnexpectedData, OutOfMemory, EndOfStream })!T {
    comptime validateTopLevelType(T);
    return try deserializeInternal(stream, T, allocator);
}

/// Releases all memory allocated by `deserializeAlloc`.
/// - `allocator` is the allocator passed to `deserializeAlloc`.
/// - `T` is the type that was passed to `deserializeAlloc`.
/// - `value` is the value that was returned by `deserializeAlloc`.
pub fn free(allocator: std.mem.Allocator, comptime T: type, value: *T) void {
    recursiveFree(allocator, T, value);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Implementation:

fn serializeRecursive(stream: *std.Io.Writer, comptime T: type, value: T) std.Io.Writer.Error!void {
    switch (@typeInfo(T)) {
        // Primitive types:
        .void => {}, // no data
        .bool => try stream.writeByte(@intFromBool(value)),
        .float => switch (T) {
            f16 => try stream.writeInt(u16, @bitCast(value), .little),
            f32 => try stream.writeInt(u32, @bitCast(value), .little),
            f64 => try stream.writeInt(u64, @bitCast(value), .little),
            f80 => try stream.writeInt(u80, @bitCast(value), .little),
            f128 => try stream.writeInt(u128, @bitCast(value), .little),
            else => unreachable,
        },

        .int => {
            if (T == usize) {
                try stream.writeInt(u64, value, .little);
            } else {
                try stream.writeInt(AlignedInt(T), value, .little);
            }
        },
        .pointer => |ptr| {
            if (ptr.sentinel() != null) @compileError("Sentinels are not supported yet!");
            switch (ptr.size) {
                .one => try serializeRecursive(stream, ptr.child, value.*),
                .slice => {
                    try stream.writeInt(u64, value.len, .little);
                    if (ptr.child == u8) {
                        try stream.writeAll(value);
                    } else {
                        for (value) |item| {
                            try serializeRecursive(stream, ptr.child, item);
                        }
                    }
                },
                .c => unreachable,
                .many => unreachable,
            }
        },
        .array => |arr| {
            if (arr.child == u8) {
                try stream.writeAll(&value);
            } else {
                for (value) |item| {
                    try serializeRecursive(stream, arr.child, item);
                }
            }
            if (arr.sentinel() != null) @compileError("Sentinels are not supported yet!");
        },
        .@"struct" => |str| {
            // we can safely ignore the struct layout here as we will serialize the data by field order,
            // instead of memory representation

            inline for (str.field_names, str.field_types) |name, FieldType| {
                try serializeRecursive(stream, FieldType, @field(value, name));
            }
        },
        .optional => |opt| {
            if (value) |item| {
                try stream.writeInt(u8, 1, .little);
                try serializeRecursive(stream, opt.child, item);
            } else {
                try stream.writeInt(u8, 0, .little);
            }
        },
        .error_union => |eu| {
            if (value) |item| {
                try stream.writeInt(u8, 1, .little);
                try serializeRecursive(stream, eu.payload, item);
            } else |item| {
                try stream.writeInt(u8, 0, .little);
                try serializeRecursive(stream, eu.error_set, item);
            }
        },
        .error_set => {
            // Error unions are serialized by "index of sorted name", so we
            // hash all names in the right order
            const names = comptime getSortedErrorNames(T);

            const index = for (names, 0..) |name, i| {
                if (std.mem.eql(u8, name, @errorName(value)))
                    break @as(u16, @intCast(i));
            } else unreachable;

            try stream.writeInt(u16, index, .little);
        },
        .@"enum" => |list| {
            const Tag = if (list.tag_type == usize) u64 else list.tag_type;
            try stream.writeInt(AlignedInt(Tag), @intFromEnum(value), .little);
        },
        .@"union" => |un| {
            const Tag = un.tag_type orelse @compileError("Untagged unions are not supported!");

            const active_tag = std.meta.activeTag(value);

            try serializeRecursive(stream, Tag, active_tag);

            inline for (un.field_names, un.field_types) |name, FieldType| {
                if (@field(Tag, name) == active_tag) {
                    try serializeRecursive(stream, FieldType, @field(value, name));
                }
            }
        },
        .vector => |vec| {
            const array: [vec.len]vec.child = value;
            try serializeRecursive(stream, @TypeOf(array), array);
        },

        // Unsupported types:
        .noreturn,
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        .spirv,
        => unreachable,
    }
}

fn deserializeInternal(
    stream: *std.Io.Reader,
    comptime T: type,
    allocator: ?std.mem.Allocator,
) (std.Io.Reader.Error || error{ UnexpectedData, OutOfMemory, EndOfStream })!T {
    const type_hash = comptime computeTypeHash(T);

    var ref_hash: [type_hash.len]u8 = undefined;
    try stream.readSliceAll(&ref_hash);
    if (!std.mem.eql(u8, type_hash[0..], ref_hash[0..]))
        return error.UnexpectedData;

    var result: T = undefined;
    try recursiveDeserialize(stream, T, allocator, &result);
    return result;
}

///Determines the size of the next byte aligned integer type that can accommodate the same range of values as `T`
fn AlignedInt(comptime T: type) type {
    return std.math.ByteAlignedInt(T);
}

fn recursiveDeserialize(
    stream: *std.Io.Reader,
    comptime T: type,
    allocator: ?std.mem.Allocator,
    target: *T,
) (std.Io.Reader.Error || error{ UnexpectedData, OutOfMemory, EndOfStream })!void {
    switch (@typeInfo(T)) {
        // Primitive types:
        .void => target.* = {},
        .bool => target.* = (try stream.takeByte()) != 0,
        .float => target.* = @bitCast(switch (T) {
            f16 => try stream.takeInt(u16, .little),
            f32 => try stream.takeInt(u32, .little),
            f64 => try stream.takeInt(u64, .little),
            f80 => try stream.takeInt(u80, .little),
            f128 => try stream.takeInt(u128, .little),
            else => unreachable,
        }),

        .int => target.* = if (T == usize)
            std.math.cast(usize, try stream.takeInt(u64, .little)) orelse return error.UnexpectedData
        else
            @truncate(try stream.takeInt(AlignedInt(T), .little)),

        .pointer => |ptr| {
            if (ptr.sentinel() != null) @compileError("Sentinels are not supported yet!");
            switch (ptr.size) {
                .one => {
                    const pointer = try allocator.?.create(ptr.child);
                    errdefer allocator.?.destroy(pointer);

                    try recursiveDeserialize(stream, ptr.child, allocator, pointer);

                    target.* = pointer;
                },
                .slice => {
                    const length = std.math.cast(usize, try stream.takeInt(u64, .little)) orelse return error.UnexpectedData;

                    const slice = try allocator.?.alloc(ptr.child, length);
                    errdefer allocator.?.free(slice);

                    if (ptr.child == u8) {
                        try stream.readSliceAll(slice);
                    } else {
                        for (slice) |*item| {
                            try recursiveDeserialize(stream, ptr.child, allocator, item);
                        }
                    }

                    target.* = slice;
                },
                .c => unreachable,
                .many => unreachable,
            }
        },
        .array => |arr| {
            if (arr.child == u8) {
                try stream.readSliceAll(target);
            } else {
                for (&target.*) |*item| {
                    try recursiveDeserialize(stream, arr.child, allocator, item);
                }
            }
        },
        .@"struct" => |str| {
            // we can safely ignore the struct layout here as we will serialize the data by field order,
            // instead of memory representation

            inline for (str.field_names, str.field_types) |name, FieldType| {
                try recursiveDeserialize(stream, FieldType, allocator, &@field(target.*, name));
            }
        },
        .optional => |opt| {
            const is_set = try stream.takeInt(u8, .little);

            if (is_set != 0) {
                target.* = @as(opt.child, undefined);
                try recursiveDeserialize(stream, opt.child, allocator, &target.*.?);
            } else {
                target.* = null;
            }
        },
        .error_union => |eu| {
            const is_value = try stream.takeInt(u8, .little);
            if (is_value != 0) {
                var value: eu.payload = undefined;
                try recursiveDeserialize(stream, eu.payload, allocator, &value);
                target.* = value;
            } else {
                var err: eu.error_set = undefined;
                try recursiveDeserialize(stream, eu.error_set, allocator, &err);
                target.* = err;
            }
        },
        .error_set => {
            // Error unions are serialized by "index of sorted name", so we
            // hash all names in the right order
            const names = comptime getSortedErrorNames(T);
            const index = try stream.takeInt(u16, .little);

            switch (index) {
                inline 0...names.len - 1 => |idx| target.* = @field(T, names[idx]),
                else => return error.UnexpectedData,
            }
        },
        .@"enum" => |list| {
            const Tag = if (list.tag_type == usize) u64 else list.tag_type;
            const tag_value: Tag = @truncate(try stream.takeInt(AlignedInt(Tag), .little));
            if (list.mode == .exhaustive) {
                target.* = std.enums.fromInt(T, tag_value) orelse return error.UnexpectedData;
            } else {
                target.* = @enumFromInt(tag_value);
            }
        },
        .@"union" => |un| {
            const Tag = un.tag_type orelse @compileError("Untagged unions are not supported!");

            var active_tag: Tag = undefined;
            try recursiveDeserialize(stream, Tag, allocator, &active_tag);

            inline for (un.field_names, un.field_types) |name, FieldType| {
                if (@field(Tag, name) == active_tag) {
                    var union_value: FieldType = undefined;
                    try recursiveDeserialize(stream, FieldType, allocator, &union_value);
                    target.* = @unionInit(T, name, union_value);
                    return;
                }
            }

            return error.UnexpectedData;
        },
        .vector => |vec| {
            var array: [vec.len]vec.child = undefined;
            try recursiveDeserialize(stream, @TypeOf(array), allocator, &array);
            target.* = array;
        },

        // Unsupported types:
        .noreturn,
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        .spirv,
        => unreachable,
    }
}

fn makeMutableSlice(comptime T: type, slice: []const T) []T {
    if (slice.len == 0) {
        return &[_]T{};
    } else {
        return @as([*]T, @constCast(slice.ptr))[0..slice.len];
    }
}

fn recursiveFree(allocator: std.mem.Allocator, comptime T: type, value: *T) void {
    switch (@typeInfo(T)) {
        // Non-allocating primitives:
        .void, .bool, .float, .int, .error_set, .@"enum" => {},

        // Composite types:
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    const mut_ptr = @constCast(value.*);
                    recursiveFree(allocator, ptr.child, mut_ptr);
                    allocator.destroy(mut_ptr);
                },
                .slice => {
                    const mut_slice = makeMutableSlice(ptr.child, value.*);
                    for (mut_slice) |*item| {
                        recursiveFree(allocator, ptr.child, item);
                    }
                    allocator.free(mut_slice);
                },
                .c => unreachable,
                .many => unreachable,
            }
        },
        .array => |arr| {
            for (&value.*) |*item| {
                recursiveFree(allocator, arr.child, item);
            }
        },
        .@"struct" => |str| {
            // we can safely ignore the struct layout here as we will serialize the data by field order,
            // instead of memory representation

            inline for (str.field_names, str.field_types) |name, FieldType| {
                recursiveFree(allocator, FieldType, &@field(value.*, name));
            }
        },
        .optional => |opt| {
            if (value.*) |*item| {
                recursiveFree(allocator, opt.child, item);
            }
        },
        .error_union => |eu| {
            if (value.*) |*item| {
                recursiveFree(allocator, eu.payload, item);
            } else |_| {
                // errors aren't meant to be freed
            }
        },
        .@"union" => |un| {
            const Tag = un.tag_type orelse @compileError("Untagged unions are not supported!");

            const active_tag: Tag = value.*;

            inline for (un.field_names, un.field_types) |name, FieldType| {
                if (@field(Tag, name) == active_tag) {
                    recursiveFree(allocator, FieldType, &@field(value.*, name));
                    return;
                }
            }
        },
        .vector => |vec| {
            var array: [vec.len]vec.child = value.*;
            for (&array) |*item| {
                recursiveFree(allocator, vec.child, item);
            }
        },

        // Unsupported types:
        .noreturn,
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        .spirv,
        => unreachable,
    }
}

/// Returns `true` if `T` requires allocation to be deserialized.
fn requiresAllocationForDeserialize(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .pointer => return true,
        .@"struct" => |str| {
            inline for (str.field_types) |FieldType| {
                if (requiresAllocationForDeserialize(FieldType)) {
                    return true;
                }
            }
            return false;
        },
        .@"union" => |un| {
            inline for (un.field_types) |FieldType| {
                if (requiresAllocationForDeserialize(FieldType)) {
                    return true;
                }
            }
            return false;
        },
        .error_union => |eu| return requiresAllocationForDeserialize(eu.payload),
        else => return false,
    }
}

const TypeHashFn = std.hash.Fnv1a_64;

fn intToLittleEndianBytes(val: anytype) [@sizeOf(@TypeOf(val))]u8 {
    const T = @TypeOf(val);
    var res: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(AlignedInt(T), &res, val, .little);
    return res;
}

/// Computes a unique type hash from `T` to identify deserializing invalid data.
/// Incorporates field order and field type, but not field names, so only checks
/// for structural equivalence. Compile errors on unsupported or comptime types.
fn computeTypeHash(comptime T: type) [8]u8 {
    var hasher = TypeHashFn.init();

    computeTypeHashInternal(&hasher, T);

    return intToLittleEndianBytes(hasher.final());
}
fn getSortedErrorNames(comptime T: type) []const []const u8 {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const error_set = @typeInfo(T).error_set orelse @compileError("Cannot serialize anyerror");
        const error_names = error_set.error_names orelse @compileError("Cannot serialize an error set without names");

        const sorted_names = blk: {
            var names: [error_names.len][]const u8 = undefined;
            for (error_names, 0..) |name, i| {
                names[i] = name;
            }

            std.mem.sortUnstable([]const u8, &names, {}, struct {
                fn order(ctx: void, lhs: []const u8, rhs: []const u8) bool {
                    _ = ctx;
                    return (std.mem.order(u8, lhs, rhs) == .lt);
                }
            }.order);
            break :blk names;
        };

        return &sorted_names;
    }
}

fn getSortedEnumNames(comptime T: type) []const []const u8 {
    comptime {
        @setEvalBranchQuota(1_000_000);
        const type_info = @typeInfo(T).@"enum";

        const sorted_names = blk: {
            var names: [type_info.field_names.len][]const u8 = undefined;
            for (type_info.field_names, 0..) |name, i| {
                names[i] = name;
            }

            std.mem.sortUnstable([]const u8, &names, {}, struct {
                fn order(ctx: void, lhs: []const u8, rhs: []const u8) bool {
                    _ = ctx;
                    return (std.mem.order(u8, lhs, rhs) == .lt);
                }
            }.order);
            break :blk names;
        };

        return &sorted_names;
    }
}

fn computeTypeHashInternal(hasher: *TypeHashFn, comptime T: type) void {
    @setEvalBranchQuota(10_000);
    switch (@typeInfo(T)) {
        // Primitive types:
        .void,
        .bool,
        .float,
        => hasher.update(@typeName(T)),

        .int => {
            if (T == usize) {
                // special case: usize can differ between platforms, this
                // format uses u64 internally.
                hasher.update(@typeName(u64));
            } else {
                hasher.update(@typeName(T));
            }
        },
        .pointer => |ptr| {
            if (ptr.attrs.@"volatile") @compileError("Serializing volatile pointers is most likely a mistake.");
            if (ptr.sentinel() != null) @compileError("Sentinels are not supported yet!");
            switch (ptr.size) {
                .one => {
                    hasher.update("pointer");
                    computeTypeHashInternal(hasher, ptr.child);
                },
                .slice => {
                    hasher.update("slice");
                    computeTypeHashInternal(hasher, ptr.child);
                },
                .c => @compileError("C-pointers are not supported"),
                .many => @compileError("Many-pointers are not supported"),
            }
        },
        .array => |arr| {
            if (arr.sentinel() != null) @compileError("Sentinels are not supported yet!");
            hasher.update(&intToLittleEndianBytes(@as(u64, arr.len)));
            computeTypeHashInternal(hasher, arr.child);
        },
        .@"struct" => |str| {
            // we can safely ignore the struct layout here as we will serialize the data by field order,
            // instead of memory representation

            // add some generic marker to the hash so emtpy structs get
            // added as information
            hasher.update("struct");

            inline for (str.field_types, str.field_attrs) |FieldType, attrs| {
                if (attrs.@"comptime") @compileError("comptime fields are not supported.");
                computeTypeHashInternal(hasher, FieldType);
            }
        },
        .optional => |opt| {
            hasher.update("optional");
            computeTypeHashInternal(hasher, opt.child);
        },
        .error_union => |eu| {
            hasher.update("error union");
            computeTypeHashInternal(hasher, eu.error_set);
            computeTypeHashInternal(hasher, eu.payload);
        },
        .error_set => {
            // Error unions are serialized by "index of sorted name", so we
            // hash all names in the right order

            hasher.update("error set");
            const names = comptime getSortedErrorNames(T);
            for (names) |name| {
                hasher.update(name);
            }
        },
        .@"enum" => |list| {
            const Tag = if (list.tag_type == usize)
                u64
            else if (list.tag_type == isize)
                i64
            else
                list.tag_type;
            if (list.mode == .exhaustive) {
                // Exhaustive enums only allow certain values, so we
                // tag them via the value type
                hasher.update("enum.exhaustive");
                computeTypeHashInternal(hasher, Tag);
                const names = getSortedEnumNames(T);
                inline for (names) |name| {
                    hasher.update(name);
                    hasher.update(&intToLittleEndianBytes(@as(Tag, @intFromEnum(@field(T, name)))));
                }
            } else {
                // Non-exhaustive enums are basically integers. Treat them as such.
                hasher.update("enum.non-exhaustive");
                computeTypeHashInternal(hasher, Tag);
            }
        },
        .@"union" => |un| {
            const tag = un.tag_type orelse @compileError("Untagged unions are not supported!");
            hasher.update("union");
            computeTypeHashInternal(hasher, tag);
            for (un.field_types) |FieldType| {
                computeTypeHashInternal(hasher, FieldType);
            }
        },
        .vector => |vec| {
            hasher.update("vector");
            hasher.update(&intToLittleEndianBytes(@as(u64, vec.len)));
            computeTypeHashInternal(hasher, vec.child);
        },

        // Unsupported types:
        .noreturn,
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        .spirv,
        => @compileError("Unsupported type " ++ @typeName(T)),
    }
}

fn validateTopLevelType(comptime T: type) void {
    switch (@typeInfo(T)) {

        // Unsupported top level types:
        .error_set,
        .error_union,
        => @compileError("Unsupported top level type " ++ @typeName(T) ++ ". Wrap into struct to serialize these."),

        else => {},
    }
}

fn testSameHash(comptime T1: type, comptime T2: type) void {
    const hash_1 = comptime computeTypeHash(T1);
    const hash_2 = comptime computeTypeHash(T2);
    if (comptime !std.mem.eql(u8, hash_1[0..], hash_2[0..]))
        @compileError("The computed hash for " ++ @typeName(T1) ++ " and " ++ @typeName(T2) ++ " does not match.");
}

test "type hasher basics" {
    testSameHash(void, void);
    testSameHash(bool, bool);
    testSameHash(u1, u1);
    testSameHash(u32, u32);
    testSameHash(f32, f32);
    testSameHash(f64, f64);
    testSameHash(@Vector(4, u32), @Vector(4, u32));
    testSameHash(usize, u64);
    testSameHash([]const u8, []const u8);
    testSameHash([]const u8, []u8);
    testSameHash([]const u8, []u8);
    testSameHash(?*struct { a: f32, b: u16 }, ?*const struct { hello: f32, lol: u16 });
    testSameHash(enum { a, b, c }, enum { a, b, c });
    testSameHash(enum(u8) { a, b, c, _ }, enum(u8) { c, b, a, _ });

    testSameHash(enum(u8) { a, b, c }, enum(u8) { a, b, c });
    testSameHash(enum(u8) { a = 1, b = 6, c = 9 }, enum(u8) { a = 1, b = 6, c = 9 });

    testSameHash(enum(usize) { a, b, c }, enum(u64) { a, b, c });
    testSameHash(enum(isize) { a, b, c }, enum(i64) { a, b, c });
    testSameHash([5]@Vector(4, u32), [5]@Vector(4, u32));

    testSameHash(union(enum) { a: u32, b: f32 }, union(enum) { a: u32, b: f32 });

    testSameHash(error{ Foo, Bar }, error{ Foo, Bar });
    testSameHash(error{ Foo, Bar }, error{ Bar, Foo });
    testSameHash(error{ Foo, Bar }!void, error{ Bar, Foo }!void);
}

fn testSerialize(comptime T: type, value: T) !void {
    var discarding: std.Io.Writer.Discarding = .init(&.{});

    try serialize(&discarding.writer, T, value);
}

const enable_failing_test = false;

test "serialize basics" {
    try testSerialize(void, {});
    try testSerialize(bool, false);
    try testSerialize(bool, true);
    try testSerialize(u1, 0);
    try testSerialize(u1, 1);
    try testSerialize(u8, 0xFF);
    try testSerialize(u32, 0xDEADBEEF);
    try testSerialize(usize, 0xDEADBEEF);

    try testSerialize(f16, std.math.pi);
    try testSerialize(f32, std.math.pi);
    try testSerialize(f64, std.math.pi);
    try testSerialize(f80, std.math.pi);
    try testSerialize(f128, std.math.pi);

    try testSerialize([3]u8, "hi!".*);
    try testSerialize([]const u8, "Hello, World!");
    try testSerialize(*const [3]u8, "foo");

    try testSerialize(enum { a, b, c }, .a);
    try testSerialize(enum { a, b, c }, .b);
    try testSerialize(enum { a, b, c }, .c);

    try testSerialize(enum(u8) { a, b, c }, .a);
    try testSerialize(enum(u8) { a, b, c }, .b);
    try testSerialize(enum(u8) { a, b, c }, .c);

    try testSerialize(enum(isize) { a, b, c }, .a);
    try testSerialize(enum(isize) { a, b, c }, .b);
    try testSerialize(enum(isize) { a, b, c }, .c);

    try testSerialize(enum(usize) { a, b, c }, .a);
    try testSerialize(enum(usize) { a, b, c }, .b);
    try testSerialize(enum(usize) { a, b, c }, .c);

    const TestEnum = enum(u8) { a, b, c, _ };
    try testSerialize(TestEnum, .a);
    try testSerialize(TestEnum, .b);
    try testSerialize(TestEnum, .c);
    try testSerialize(TestEnum, @as(TestEnum, @enumFromInt(0xB1)));

    if (enable_failing_test) {
        try testSerialize(struct { val: error{ Foo, Bar } }, .{ .val = error.Foo });
        try testSerialize(struct { val: error{ Bar, Foo } }, .{ .val = error.Bar });
        try testSerialize(struct { val: error{ Bar, Foo }!u32 }, .{ .val = error.Bar });
        try testSerialize(struct { val: error{ Bar, Foo }!u32 }, .{ .val = 0xFF });
    }
    try testSerialize(union(enum) { a: f32, b: u32 }, .{ .a = 1.5 });
    try testSerialize(union(enum) { a: f32, b: u32 }, .{ .b = 2.0 });

    try testSerialize(?u32, null);
    try testSerialize(?u32, 143);
}

fn testSerDesAlloc(comptime T: type, value: T) !void {
    var allocating: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer allocating.deinit();

    try serialize(&allocating.writer, T, value);

    var fixed: std.Io.Reader = .fixed(allocating.written());

    var deserialized = try deserializeAlloc(&fixed, T, std.testing.allocator);
    defer free(std.testing.allocator, T, &deserialized);

    try std.testing.expectEqual(value, deserialized);
}

fn testSerDesPtrContentEquality(comptime T: type, value: T) !void {
    var allocating: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer allocating.deinit();

    try serialize(&allocating.writer, T, value);

    var fixed: std.Io.Reader = .fixed(allocating.written());

    var deserialized = try deserializeAlloc(&fixed, T, std.testing.allocator);
    defer free(std.testing.allocator, T, &deserialized);

    try std.testing.expectEqual(value.*, deserialized.*);
}

fn testSerDesSliceContentEquality(comptime T: type, value: T) !void {
    var allocating: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer allocating.deinit();

    try serialize(&allocating.writer, T, value);

    var fixed: std.Io.Reader = .fixed(allocating.written());

    var deserialized = try deserializeAlloc(&fixed, T, std.testing.allocator);
    defer free(std.testing.allocator, T, &deserialized);

    try std.testing.expectEqualSlices(std.meta.Child(T), value, deserialized);
}

test "ser/des" {
    try testSerDesAlloc(void, {});
    try testSerDesAlloc(bool, false);
    try testSerDesAlloc(bool, true);
    try testSerDesAlloc(u1, 0);
    try testSerDesAlloc(u1, 1);
    try testSerDesAlloc(u8, 0xFF);
    try testSerDesAlloc(u32, 0xDEADBEEF);
    try testSerDesAlloc(usize, 0xDEADBEEF);

    try testSerDesAlloc(f16, std.math.pi);
    try testSerDesAlloc(f32, std.math.pi);
    try testSerDesAlloc(f64, std.math.pi);
    try testSerDesAlloc(f80, std.math.pi);
    try testSerDesAlloc(f128, std.math.pi);

    try testSerDesAlloc([3]u8, "hi!".*);
    try testSerDesSliceContentEquality([]const u8, "Hello, World!");
    try testSerDesPtrContentEquality(*const [3]u8, "foo");

    try testSerDesAlloc(enum { a, b, c }, .a);
    try testSerDesAlloc(enum { a, b, c }, .b);
    try testSerDesAlloc(enum { a, b, c }, .c);

    try testSerDesAlloc(enum(u8) { a, b, c }, .a);
    try testSerDesAlloc(enum(u8) { a, b, c }, .b);
    try testSerDesAlloc(enum(u8) { a, b, c }, .c);

    try testSerDesAlloc(enum(usize) { a, b, c }, .a);
    try testSerDesAlloc(enum(usize) { a, b, c }, .b);
    try testSerDesAlloc(enum(usize) { a, b, c }, .c);

    try testSerDesAlloc(enum(isize) { a, b, c }, .a);
    try testSerDesAlloc(enum(isize) { a, b, c }, .b);
    try testSerDesAlloc(enum(isize) { a, b, c }, .c);

    const TestEnum = enum(u8) { a, b, c, _ };
    try testSerDesAlloc(TestEnum, .a);
    try testSerDesAlloc(TestEnum, .b);
    try testSerDesAlloc(TestEnum, .c);
    try testSerDesAlloc(TestEnum, @as(TestEnum, @enumFromInt(0xB1)));

    if (enable_failing_test) {
        try testSerDesAlloc(struct { val: error{ Foo, Bar } }, .{ .val = error.Foo });
        try testSerDesAlloc(struct { val: error{ Bar, Foo } }, .{ .val = error.Bar });
        try testSerDesAlloc(struct { val: error{ Bar, Foo }!u32 }, .{ .val = error.Bar });
        try testSerDesAlloc(struct { val: error{ Bar, Foo }!u32 }, .{ .val = 0xFF });
    }

    try testSerDesAlloc(union(enum) { a: f32, b: u32 }, .{ .a = 1.5 });
    try testSerDesAlloc(union(enum) { a: f32, b: u32 }, .{ .b = 2.0 });

    try testSerDesAlloc(?u32, null);
    try testSerDesAlloc(?u32, 143);
}
