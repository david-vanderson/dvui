mutex: std.Thread.Mutex = .{},
storage: Storage = .empty,
trash: Trash = .empty,

pub const Data = @This();

pub const Key = dvui.Id;

pub const Storage = dvui.TrackingAutoHashMap(Key, SavedData, .{ .tracking = .get_and_put });
pub const Trash = std.ArrayListUnmanaged(SavedData);

const SavedData = struct {
    alignment: u8,
    data: []u8,

    debug: DebugInfo,

    pub const Kind = enum(u1) {
        /// Store the data pointer to by the slice
        single_item,
        /// Store the slice as ptr and len (not copying the data)
        slice,
    };

    pub const DebugInfo = if (builtin.mode == .Debug) struct {
        name: []const u8,
        kind: Kind,

        fn eq(self: DebugInfo, other: DebugInfo) bool {
            return std.mem.eql(u8, self.name, other.name) and self.kind == other.kind;
        }

        pub fn format(self: DebugInfo, writer: *std.Io.Writer) !void {
            try writer.print("{[name]s} ({[kind]t})", self);
        }
    } else void;

    pub fn free(self: *const SavedData, gpa: std.mem.Allocator) void {
        if (self.data.len != 0) {
            gpa.rawFree(
                self.data,
                std.mem.Alignment.fromByteUnits(self.alignment),
                @returnAddress(),
            );
        }
    }
};

fn Slice(S: type) type {
    const dt = @typeInfo(S);
    return if (dt == .pointer and dt.pointer.size == .slice)
        if (dt.pointer.sentinel()) |s|
            [:s]dt.pointer.child
        else
            []dt.pointer.child
    else if (dt == .pointer and dt.pointer.size == .one and @typeInfo(dt.pointer.child) == .array)
        if (@typeInfo(dt.pointer.child).array.sentinel()) |s|
            [:s]@typeInfo(dt.pointer.child).array.child
        else
            []@typeInfo(dt.pointer.child).array.child
    else
        @compileError("Data.Slice needs a slice or pointer to array, given " ++ @typeName(S));
}

pub fn set(self: *Data, gpa: std.mem.Allocator, key: Key, data: anytype, timeout: dvui.RemovalTimeout) std.mem.Allocator.Error!void {
    const value, _ = try self.getOrPutT(gpa, key, @TypeOf(data), timeout);
    value.* = data;
}

pub fn setSlice(self: *Data, gpa: std.mem.Allocator, key: Key, data: anytype, timeout: dvui.RemovalTimeout) std.mem.Allocator.Error!void {
    return setSliceCopies(self, gpa, key, data, 1, timeout);
}
pub fn setSliceCopies(self: *Data, gpa: std.mem.Allocator, key: Key, data: anytype, num_copies: usize, timeout: dvui.RemovalTimeout) std.mem.Allocator.Error!void {
    const S = @TypeOf(data);
    const sentinel = @typeInfo(Slice(S)).pointer.sentinel();
    const slice, _ = try self.getOrPutSliceT(gpa, key, Slice(S), data.len * num_copies + @intFromBool(sentinel != null), true, timeout);
    for (0..num_copies) |i| {
        @memcpy(slice[i * data.len ..][0..data.len], data);
    }
    if (sentinel) |s| slice[data.len] = s;
}

pub fn getPtr(self: *Data, key: Key, comptime T: type) ?*T {
    return @ptrCast(@alignCast(self.get(key, if (SavedData.DebugInfo == void) {} else .{ .name = @typeName(T), .kind = .single_item })));
}
pub fn getPtrDefault(self: *Data, gpa: std.mem.Allocator, key: Key, comptime T: type, default: T, timeout: dvui.RemovalTimeout) std.mem.Allocator.Error!*T {
    const value, const existing = try self.getOrPutT(gpa, key, T, timeout);
    if (!existing) value.* = default;
    return value;
}

pub fn getSlice(self: *Data, key: Key, comptime S: type) ?Slice(S) {
    return @ptrCast(@alignCast(self.get(key, if (SavedData.DebugInfo == void) {} else .{ .name = @typeName(@typeInfo(S).pointer.child), .kind = .slice })));
}
pub fn getSliceDefault(self: *Data, gpa: std.mem.Allocator, key: Key, comptime S: type, default: []const @typeInfo(S).pointer.child, timeout: dvui.RemovalTimeout) std.mem.Allocator.Error!Slice(S) {
    const sentinel = @typeInfo(Slice(S)).pointer.sentinel();
    const slice, const existing = try self.getOrPutSliceT(gpa, key, Slice(S), default.len, false, timeout);
    if (!existing) {
        @memcpy(slice, default);
        if (sentinel) |s| slice[default.len] = s;
    }
    return slice;
}

fn getOrPutT(self: *Data, gpa: std.mem.Allocator, key: Key, comptime T: type, timeout: dvui.RemovalTimeout) std.mem.Allocator.Error!struct { *T, bool } {
    const bytes, const existing = try self.getOrPut(
        gpa,
        key,
        @sizeOf(T),
        @alignOf(T),
        true,
        timeout,
        if (SavedData.DebugInfo == void) {} else .{ .name = @typeName(T), .kind = .single_item },
    );
    return .{ @ptrCast(@alignCast(bytes)), existing };
}
fn getOrPutSliceT(self: *Data, gpa: std.mem.Allocator, key: Key, comptime S: type, len: usize, replace_existing: bool, timeout: dvui.RemovalTimeout) std.mem.Allocator.Error!struct { S, bool } {
    const st = @typeInfo(S);
    const T = st.pointer.child;
    const bytes, const existing = try self.getOrPut(
        gpa,
        key,
        @sizeOf(T) * len + @intFromBool(st.pointer.sentinel() != null),
        st.pointer.alignment,
        replace_existing,
        timeout,
        if (SavedData.DebugInfo == void) {} else .{ .name = @typeName(T), .kind = .slice },
    );
    return .{ @ptrCast(@alignCast(bytes)), existing };
}

/// Returns the backing byte slice and a boolean indicating if we found an existing entry
pub fn getOrPut(self: *Data, gpa: std.mem.Allocator, key: Key, len: usize, alignment: u8, replace_existing: bool, timeout: dvui.RemovalTimeout, debug: SavedData.DebugInfo) std.mem.Allocator.Error!struct { []u8, bool } {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (replace_existing) try self.trash.ensureUnusedCapacity(gpa, 1);
    const entry = try self.storage.getOrPutWithTimeout(gpa, key, timeout);
    errdefer _ = self.storage.remove(key);

    const should_trash = replace_existing and entry.found_existing and entry.value_ptr.data.len != len;
    if (should_trash) {
        // log.debug("dataSet: already had data for id {x} key {s}, freeing previous data\n", .{ id, key });
        if (@TypeOf(debug) != void) {
            if (!debug.eq(entry.value_ptr.debug)) {
                std.debug.panic("Date.getOrPut: stored type {f} doesn't match asked for type {f}", .{ entry.value_ptr.debug, debug });
            }
        }
        self.trash.appendAssumeCapacity(entry.value_ptr.*);
    }
    if (!entry.found_existing or should_trash) {
        entry.value_ptr.* = .{
            .alignment = alignment,
            .data = if (len == 0) &.{} else if (gpa.rawAlloc(len, .fromByteUnits(alignment), @returnAddress())) |ptr| ptr[0..len] else return std.mem.Allocator.Error.OutOfMemory,
            .debug = debug,
        };
    }
    return .{ entry.value_ptr.data, entry.found_existing };
}

/// returns the backing byte slice if we have one
pub fn get(self: *Data, key: Key, debug: SavedData.DebugInfo) ?[]u8 {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.storage.getPtr(key)) |sd| {
        if (@TypeOf(debug) != void) {
            if (!debug.eq(sd.debug)) {
                std.debug.panic("Data.get: stored type {f} doesn't match asked for type {f}", .{ sd.debug, debug });
            }
        }
        return sd.data;
    } else {
        return null;
    }
}

pub fn remove(self: *Data, gpa: std.mem.Allocator, key: Key) std.mem.Allocator.Error!void {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.trash.ensureUnusedCapacity(gpa, 1);

    if (self.storage.fetchRemove(key)) |dd| {
        self.trash.appendAssumeCapacity(dd.value);
    }
}

/// Destroys all unused and trashed textures since the last
/// call to `reset`
pub fn reset(self: *Data, gpa: std.mem.Allocator, micros_since_last_reset: u32) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    var it = self.storage.iterator();
    while (it.next_resetting(micros_since_last_reset)) |kv| {
        kv.value.free(gpa);
    }
    for (self.trash.items) |sd| {
        sd.free(gpa);
    }
    self.trash.clearRetainingCapacity();
}

pub fn deinit(self: *Data, gpa: std.mem.Allocator) void {
    defer self.* = undefined;
    var it = self.storage.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.free(gpa);
    }
    self.storage.deinit(gpa);
    for (self.trash.items) |sd| {
        sd.free(gpa);
    }
    self.trash.deinit(gpa);
}

const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("./dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
