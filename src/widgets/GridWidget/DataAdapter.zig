//! DataAdapters provide ....
//! All DataAdapters must implement
//! - pub fn value(row_num: usize) T
//! - pub fn setValue(row_num: usize, val: T) void
//! - pub fn len() usize
//!

//
// Now about setValue. Nothing currently needs it except for
// the selection actions and we don't really want to promote patterns
// where dvui widgets are modifying user data.
//

const std = @import("std");

/// This DataAdapter returns the same void value for all rows and columns
/// You almost certainly want to use one of the specialised adapters.
// TODO: This doesn't yet work for virtual scrolling.
// The adapaters either needs to take a start / end index or a start_offset or similar
// as we only want the user to pass the visible part of the dataset to the adapters.
// Proposal

const DataAdapter = @This();

/// Check if a container has a method named 'method_name'
/// params is a tuple of parameter types, excluding the first 'self' parameter.
/// self is currently enforced to have type T, *T or *const T.
pub fn hasMethod(T: type, comptime method_name: []const u8, params: anytype) bool {
    // Is T a container?
    switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => {},
        else => return false,
    }
    if (!@hasDecl(T, method_name))
        return false;

    switch (@typeInfo(@TypeOf(@field(T, method_name)))) {
        .@"fn" => |func| {
            // Does the type of the first parameter equal Self?
            if (func.params.len < 1 or func.params.len != params.len + 1) return false;
            if ((func.params[0].type != T) and
                (func.params[0].type != *T) and
                (func.params[0].type != *const T)) return false;
            // Check other parameter types vs 'params'
            for (func.params[1..], params) |method_param, param_type| {
                if (method_param.type.? != param_type) {
                    return false;
                }
            }
        },
        else => return false,
    }
    return true;
}

pub fn requiresReadable(data_adapter: anytype) void {
    comptime {
        const T = @TypeOf(data_adapter);
        if (!hasMethod(T, "value", .{usize}))
            @compileError("data_adapter must implement: fn value(self: Self, row_nr: usize) anytype");
        if (!hasMethod(T, "len", .{}))
            @compileError("data_adapter must implement: fn len(self: Self) usize");
    }
}

pub fn requiresWriteable(data_adapter: anytype) void {
    comptime {
        const T = @TypeOf(data_adapter);
        if (!hasMethod(T, "setValue", .{ usize, @TypeOf(data_adapter.value(0)) }))
            @compileError("An updatable DataAdapter is required. data_adapter must implement: fn setValue(self: Self, row_nr: usize, val: anytype) void.");
    }
}

pub fn value(self: *DataAdapter, row_num: usize) void {
    _ = self;
    _ = row_num;
}

pub fn setValue(self: *DataAdapter, row_num: usize, val: void) void {
    _ = self;
    _ = row_num;
    _ = val;
}

pub fn len(self: *DataAdapter) usize {
    _ = self;
    return 0;
}

/// Convert a slice of T into a per-row value of T
/// Provides the following functions:
/// - value(row_num: usize): T
/// - len(): usize
pub fn Slice(T: type) type {
    return SliceImpl(T, false, noConversion(T));
}

/// Convert a slice of T into a per-row value of T
/// Allows updating of data via the adapter.
/// Provides the following functions:
/// - value(self: Self, row_num: usize): T
/// - setValue(self: Self, row_num: usize, val: T) void
/// - len(self: Self): usize
pub fn SliceUpdatable(T: type) type {
    return SliceImpl(T, true, noConversion(T));
}

/// Converts a slice of T into a per-row value of T
/// Converts the slice value using the provided converter function.
/// Provides the following functions:
/// - value(self: Self, row_num: usize): [converter result type]
/// - len(self: Self): usize
pub fn SliceConverter(T: type, converter: anytype) type {
    return SliceImpl(T, false, converter);
}

fn SliceImpl(T: type, writeable: bool, converter: anytype) type {
    const ReturnType =
        if (@typeInfo(@TypeOf(converter)).@"fn".return_type) |return_type|
            return_type
        else
            @compileError("converter function must return a value");

    return struct {
        const Self = @This();
        slice: []T,

        pub fn value(self: Self, row: usize) ReturnType {
            return converter(self.slice[row]);
        }

        // Optionally include setValue for writeable adapters.
        pub const setValue = if (writeable) struct {
            pub fn setValue(self: Self, row: usize, val: T) void {
                self.slice[row] = val;
            }
        }.setValue else void;

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}

/// Provides a per-row value for a field in a struct.
/// Provides the following functions:
/// - value(self: Self, row_num: usize): [type of struct field]
/// - len(self: Self): usize
pub fn SliceOfStruct(T: type, field_name: []const u8) type {
    return SliceOfStructImpl(T, field_name, false, noConversion(@FieldType(T, field_name)));
}

/// Provides a per-row value for a field in a struct which can be modified
/// Implements the following functions:
/// - value(self: Self, row_num: usize) [type of struct field]
/// - setValue(self: Self, row_num: usize, val: [type of struct field]) void
/// - len(self: Self): usize
pub fn SliceOfStructUpdatable(T: type, field_name: []const u8) type {
    return SliceOfStructImpl(T, field_name, true, noConversion(@FieldType(T, field_name)));
}

/// Provides a per-row value for a field in a struct which can be
/// converted via the provided conversion function.
/// Implements the following functions:
/// - value(self: Self, row_num: usize) [converter result type]
/// - len(self: Self): usize
pub fn SliceOfStructConvert(T: type, field_name: []const u8, converter: anytype) type {
    return SliceOfStructImpl(T, field_name, false, converter);
}

///Implementation for SliceOfStruct adapters.
/// T - Type of the struct
/// field_name - name of the field in the struct
/// writeable - includes setValue() if true.
/// converter - any function that takes a value and returns a converted value.
pub fn SliceOfStructImpl(T: type, field_name: []const u8, writeable: bool, converter: anytype) type {
    comptime switch (@typeInfo(T)) {
        .@"struct" => {
            if (!@hasField(T, field_name)) {
                @compileError(std.fmt.comptimePrint("{s} does not contain field {s}.", .{ @typeName(T), field_name }));
            }
        },
        else => @compileError(@typeName(T) ++ " is not a struct."),
    };
    const ReturnType = @typeInfo(@TypeOf(converter)).@"fn".return_type.?;

    return struct {
        const Self = @This();
        slice: []T,

        pub fn value(self: Self, row: usize) ReturnType {
            return converter(@field(self.slice[row], field_name));
        }

        pub const setValue = if (writeable) struct {
            pub fn setValue(self: Self, row: usize, val: @FieldType(T, field_name)) void {
                @field(self.slice[row], field_name) = val;
            }
        }.setValue else void;

        pub fn len(self: Self) usize {
            return self.slice.len;
        }
    };
}

pub fn BitSet(T: type) type {
    return BitSetImpl(T, false);
}

pub fn BitSetUpdatable(T: type) type {
    return BitSetImpl(T, true);
}

pub fn BitSetImpl(T: type, writeable: bool) type {
    return struct {
        const Self = @This();
        bitset: *T,
        //        start: usize = 0,
        //        end: usize = 0,

        pub fn value(self: Self, row: usize) bool {
            //            return self.bitset.isSet(self.start + row);
            return self.bitset.isSet(row);
        }

        pub const setValue = if (writeable) struct {
            pub fn setValue(self: Self, row: usize, val: bool) void {
                self.bitset.setValue(row, val);
                //                self.bitset.setValue(self.start + row, val);
            }
        }.setValue else void;

        pub fn len(self: Self) usize {
            return self.bitset.capacity();
            //          return self.end - self.start;
        }
    };
}

// TODO: What if conversion invloves looking up other rows.
// You we need an context? (icky) or is that just "out of scope"

// Note: This can't use anytype because it can't be resolved at comptime.
pub fn noConversion(T: type) fn (val: T) T {
    return struct {
        pub fn convert(val: T) T {
            return val;
        }
    }.convert;
}

pub fn enumToString(enum_value: anytype) []const u8 {
    return @tagName(enum_value);
}

pub fn boolToYN(val: bool) []const u8 {
    return if (val) "Y" else "N";
}

pub fn enumArrayLookup(enum_array: anytype) fn (enum_value: @TypeOf(enum_array).Key) @TypeOf(enum_array).Value {
    const T = @TypeOf(enum_array);
    return struct {
        fn convert(enum_value: T.Key) T.Value {
            return enum_array.get(enum_value);
        }
    }.convert;
}
