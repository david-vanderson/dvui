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
//  - Get rid of all the setValues.
//  - Introduce writable data adapters for only those things that actually need them.
// - Issue is that this is at minimum 3 adapters. Bitset, bool and struct of bool, not to mention slice of pointer to struct.

const DataAdapter = @This();

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

pub fn Slice(T: type) type {
    return SliceImpl(T, false, nullConverter(T));
}

pub fn SliceUpdatable(T: type) type {
    return SliceImpl(T, true, nullConverter(T));
}

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
pub fn SliceOfStruct(T: type, field_name: []const u8) type {
    return SliceOfStructImpl(T, field_name, false, nullConverter(@FieldType(T, field_name)));
}

pub fn SliceOfStructUpdatable(T: type, field_name: []const u8) type {
    return SliceOfStructImpl(T, field_name, true, nullConverter(@FieldType(T, field_name)));
}

pub fn SliceOfStructConvert(T: type, field_name: []const u8, converter: anytype) type {
    return SliceOfStructImpl(T, field_name, false, converter);
}

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

pub fn BitSetUpdateable(T: type) type {
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

pub fn nullConverter(T: type) fn (val: T) T {
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
