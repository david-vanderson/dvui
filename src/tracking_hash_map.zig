pub fn Tracked(comptime V: type) type {
    return struct {
        /// The value to reset to
        reset_state: RemovalTimeout = .immediate,
        state: RemovalTimeout = .used,

        inner: V,

        pub fn used(self: *const @This()) bool {
            return self.state == .used;
        }

        pub fn usedLastReset(self: *const @This()) bool {
            return self.state == self.reset_state;
        }

        pub fn setUsed(self: *@This(), new_used: bool) void {
            self.state = if (new_used) .used else self.reset_state;
        }
    };
}

pub const TrackingKind = enum {
    /// Sets the used flag when an item is added or accessed
    get_and_put,
    /// Only set the used flag when adding an item. Useful for
    /// detecting if items are added more than once per `reset`
    put_only,
};

pub const RemovalTimeout = enum(u32) {
    /// Immediately remove the item on the first call to `reset` where the
    /// item wasn't used
    immediate = 0,
    /// Used internally to denote that the item has been used
    used = std.math.maxInt(u32),
    /// Any other number of microseconds of not being used until the item should be removed
    _,

    pub fn from_micros(micros: u32) @This() {
        return @enumFromInt(micros);
    }

    pub fn as_micros(self: @This()) u32 {
        return @intFromEnum(self);
    }

    fn decrement(self: *@This(), micros: u32) void {
        self.* = @enumFromInt(self.as_micros() -| micros);
    }
};

pub const InitOptions = struct {
    tracking: TrackingKind,
};

/// A wrapper around `std.HashMapUnmanaged` that stores a `used` flag next
/// to the value to allow for removal on unused values.
///
/// Calling `TrackingAutoHashMap.reset` gives a list of keys that has not been
/// accessed since the last call to `TrackingAutoHashMap.reset`.
pub fn TrackingAutoHashMap(comptime K: type, comptime V: type, comptime opts: InitOptions) type {
    return struct {
        map: HashMap = .empty,

        pub const empty = Self{};

        const Self = @This();

        pub const HashMap = std.HashMapUnmanaged(K, Tracked(V), if (K == []const u8) std.hash_map.StringContext else std.hash_map.AutoContext(K), std.hash_map.default_max_load_percentage);

        pub const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        pub const KV = struct {
            key: K,
            value: V,
            used: bool,
        };

        const GetOrPutResult = struct {
            key_ptr: *K,
            value_ptr: *V,
            found_existing: bool,
        };

        /// See `HashMap.Iterator`
        pub const Iterator = struct {
            map_it: HashMap.Iterator,
            // The current std hashmap can remove keys without invalidating
            // the iterator or any pointers, which is used by this iterator
            map: *HashMap,

            /// Sets each entry as used if get tracking is enabled
            pub fn next(it: *Iterator) ?Entry {
                const entry = it.map_it.next() orelse return null;
                if (opts.tracking != .put_only) entry.value_ptr.setUsed(true);
                return .{
                    .key_ptr = entry.key_ptr,
                    .value_ptr = &entry.value_ptr.inner,
                };
            }

            /// A version of `next` that only returns items that has been used
            pub fn next_used(it: *Iterator) ?Entry {
                var entry = it.map_it.next() orelse return null;
                while (entry.value_ptr.state != .used) : (entry = it.map_it.next() orelse return null) {}
                return .{
                    .key_ptr = entry.key_ptr,
                    .value_ptr = &entry.value_ptr.inner,
                };
            }

            /// Resets the used state of all entries, removing the unused values and returning their entries
            pub fn next_resetting(it: *Iterator, micros_past_since_last_reset: u32) ?KV {
                // This locking asserts that the removal doesn't invalidate the iterator
                it.map.lockPointers();
                defer it.map.unlockPointers();
                var entry = it.map_it.next() orelse return null;
                while (entry.value_ptr.state != .immediate) : (entry = it.map_it.next() orelse return null) {
                    if (entry.value_ptr.used()) {
                        entry.value_ptr.state = entry.value_ptr.reset_state;
                    } else {
                        entry.value_ptr.state.decrement(micros_past_since_last_reset);
                    }
                }
                defer it.map.removeByPtr(entry.key_ptr);
                return .{ .key = entry.key_ptr.*, .value = entry.value_ptr.inner, .used = entry.value_ptr.state == .used };
            }
        };

        /// See `HashMap.deinit`
        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.map.deinit(allocator);
            self.* = undefined;
        }

        /// See `HashMap.count`
        pub fn count(self: Self) HashMap.Size {
            return self.map.size;
        }

        /// See `HashMap.iterator`
        pub fn iterator(self: *Self) Iterator {
            return .{ .map_it = self.map.iterator(), .map = &self.map };
        }

        /// See `HashMap.put`
        pub fn put(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!void {
            return self.putWithTimeout(allocator, key, value, .immediate);
        }
        /// See `HashMap.put`
        ///
        /// The timeout decides how much time must pass after a value has been used before it's removed from the map
        pub fn putWithTimeout(self: *Self, allocator: Allocator, key: K, value: V, timeout: RemovalTimeout) Allocator.Error!void {
            return self.map.put(allocator, key, .{ .inner = value, .reset_state = timeout });
        }

        /// See `HashMap.putNoClobber`
        pub fn putNoClobber(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!void {
            return self.putNoClobberWithTimeout(allocator, key, value, .immediate);
        }
        /// See `HashMap.putNoClobber`
        ///
        /// The timeout decides how much time must pass after a value has been used before it's removed from the map
        pub fn putNoClobberWithTimeout(self: *Self, allocator: Allocator, key: K, value: V, timeout: RemovalTimeout) Allocator.Error!void {
            return self.map.putNoClobber(allocator, key, .{ .inner = value, .reset_state = timeout });
        }

        /// See `HashMap.fetchPut`
        ///
        /// Return value additionally contains `KV.used` to indicate if the value was used before the fetch
        pub fn fetchPut(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!?KV {
            return self.fetchPutWithTimeout(allocator, key, value, .immediate);
        }
        /// See `HashMap.fetchPut`
        ///
        /// The timeout decides how much time must pass after a value has been used before it's removed from the map
        ///
        /// Return value additionally contains `KV.used` to indicate if the value was used before the fetch
        pub fn fetchPutWithTimeout(self: *Self, allocator: Allocator, key: K, value: V, timeout: RemovalTimeout) Allocator.Error!?KV {
            const kv = try self.map.fetchPut(allocator, key, .{ .inner = value, .reset_state = timeout }) orelse return null;
            return .{ .key = kv.key, .value = kv.value.inner, .used = kv.value.state == .used };
        }

        /// See `HashMap.getPtr`
        pub fn getPtr(self: Self, key: K) ?*V {
            const item = self.map.getPtr(key) orelse return null;
            if (opts.tracking != .put_only) item.setUsed(true);
            return &item.inner;
        }

        /// See `HashMap.get`
        pub fn get(self: Self, key: K) ?V {
            return if (self.getPtr(key)) |v| v.* else null;
        }

        /// See `HashMap.getOrPut`
        pub fn getOrPut(self: *Self, allocator: Allocator, key: K) Allocator.Error!GetOrPutResult {
            return self.getOrPutWithTimeout(allocator, key, .immediate);
        }
        /// See `HashMap.getOrPut`
        ///
        /// The timeout decides how much time must pass after a value has been used before it's removed from the map
        pub fn getOrPutWithTimeout(self: *Self, allocator: Allocator, key: K, timeout: RemovalTimeout) Allocator.Error!GetOrPutResult {
            const entry = try self.map.getOrPut(allocator, key);
            if (!entry.found_existing) {
                entry.value_ptr.* = .{ .inner = undefined, .reset_state = timeout };
            }
            if (opts.tracking != .put_only) entry.value_ptr.setUsed(true);
            return .{
                .key_ptr = entry.key_ptr,
                .value_ptr = &entry.value_ptr.inner,
                .found_existing = entry.found_existing,
            };
        }

        /// See `HashMap.remove`
        pub fn remove(self: *Self, key: K) bool {
            return self.map.remove(key);
        }

        /// See `HashMap.fetchRemove`
        ///
        /// Additionally contains `KV.used` to indicate if the value was used before the fetch
        pub fn fetchRemove(self: *Self, key: K) ?KV {
            const kv = self.map.fetchRemove(key) orelse return null;
            return .{ .key = kv.key, .value = kv.value.inner, .used = kv.value.state == .used };
        }

        /// Takes a `value_ptr` from and iterator `Entry` or from `getPtr` and returns the internal tracked data
        pub fn getState(_: *const Self, value_ptr: *const V) *const Tracked(V) {
            return @fieldParentPtr("inner", value_ptr);
        }

        /// Takes a `value_ptr` from and iterator `Entry` or from `getPtr`and sets the used
        /// state to the value provided.
        pub fn setUsed(value_ptr: *V, used: bool) void {
            const tracked: *Tracked(V) = @fieldParentPtr("inner", value_ptr);
            tracked.setUsed(used);
        }

        /// Takes a `value_ptr` from and iterator `Entry` or from `getPtr`and sets the timeout
        pub fn setTimeout(value_ptr: *V, timeout: RemovalTimeout) void {
            const tracked: *Tracked(V) = @fieldParentPtr("inner", value_ptr);
            tracked.reset_state = timeout;
        }

        /// Resets and removes all unused values. It you need access to the removed key and values,
        /// use `Iterator.next_resetting` directly
        pub fn reset(self: *Self, micros_past_since_last_reset: u32) void {
            var map_it = self.iterator();
            while (map_it.next_resetting(micros_past_since_last_reset)) |_| {}
        }
    };
}

test TrackingAutoHashMap {
    var map = TrackingAutoHashMap(u32, u32, .{ .tracking = .get_and_put }).empty;
    defer map.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, map.count());

    try map.put(std.testing.allocator, 1, 11);
    try map.put(std.testing.allocator, 2, 22);
    try map.put(std.testing.allocator, 3, 33);

    try std.testing.expectEqual(3, map.count());

    map.reset(0);

    try map.put(std.testing.allocator, 4, 44);
    const prev = try map.fetchPut(std.testing.allocator, 3, 333);
    try std.testing.expect(prev != null);
    try std.testing.expectEqual(false, prev.?.used);
    try std.testing.expectEqual(33, prev.?.value);

    try std.testing.expectEqual(4, map.count());

    // key 2 is set to used because of `.get_and_put`. With `.put_only`
    // it would not be
    const get = map.get(2);
    try std.testing.expectEqual(22, get);

    map.reset(0);
}

test "TrackingAutoHashMap timeout" {
    var map = TrackingAutoHashMap(u32, u32, .{ .tracking = .get_and_put }).empty;
    defer map.deinit(std.testing.allocator);

    try map.putWithTimeout(std.testing.allocator, 1, 11, .immediate);
    try map.putWithTimeout(std.testing.allocator, 2, 22, .from_micros(10));
    try map.putWithTimeout(std.testing.allocator, 3, 33, .from_micros(100));

    // All values are used when inserted, so this reset will make then all unused
    // No timeouts will be decremented as they are all used at this point
    map.reset(5);

    // 10ms passes
    map.reset(10);
    // 1, the .immediate value, is removed the second reset
    try std.testing.expect(!map.map.contains(1));
    // 2 remain as 10ms hadn't passed before this reset
    try std.testing.expect(map.map.contains(2));
    // 3 remains
    try std.testing.expect(map.map.contains(3));

    // After 10ms has passed, and another 100ms passes
    map.reset(100);
    // 2 should be removed
    try std.testing.expect(!map.map.contains(2));
    // 3 remains...
    try std.testing.expect(map.map.contains(3));

    map.reset(1);
    // ...until next reset
    try std.testing.expect(!map.map.contains(3));
}

const std = @import("std");
const Allocator = std.mem.Allocator;

test {
    @import("std").testing.refAllDecls(@This());
}
