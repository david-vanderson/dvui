pub fn Tracked(comptime V: type) type {
    return struct {
        inner: V,
        used: bool = true,
    };
}

pub const TrackingKind = enum {
    /// Sets the used flag when an item is added or accessed
    get_and_put,
    /// Only set the used flag when adding an item. Useful for
    /// detecting if items are added more than once per `reset`
    put_only,
};

/// A wrapper around `std.HashMapUnmanaged` that stores a `used` flag next
/// to the value to allow for removal on unused values.
///
/// Calling `TrackingAutoHashMap.reset` gives a list of keys that has not been
/// accessed since the last call to `TrackingAutoHashMap.reset`.
pub fn TrackingAutoHashMap(
    comptime K: type,
    comptime V: type,
    comptime tracking: TrackingKind,
) type {
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

            /// Sets each entry as used if get tracking is enabled
            pub fn next(it: *Iterator) ?Entry {
                const entry = it.map_it.next() orelse return null;
                if (tracking != .put_only) entry.value_ptr.used = true;
                return .{
                    .key_ptr = entry.key_ptr,
                    .value_ptr = &entry.value_ptr.inner,
                };
            }

            /// A version of `next` that only returns items that has been used
            pub fn next_used(it: *Iterator) ?Entry {
                var entry = it.map_it.next() orelse return null;
                while (!entry.value_ptr.used) {
                    entry = it.map_it.next() orelse return null;
                }
                return .{
                    .key_ptr = entry.key_ptr,
                    .value_ptr = &entry.value_ptr.inner,
                };
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
        pub fn iterator(self: *const Self) Iterator {
            return .{ .map_it = self.map.iterator() };
        }

        /// See `HashMap.put`
        pub fn put(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!void {
            return self.map.put(allocator, key, .{ .inner = value });
        }

        /// See `HashMap.putNoClobber`
        pub fn putNoClobber(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!void {
            return self.map.putNoClobber(allocator, key, .{ .inner = value });
        }

        /// See `HashMap.fetchPut`
        ///
        /// Additionally contains `KV.used` to indicate if the value was used before the fetch
        pub fn fetchPut(self: *Self, allocator: Allocator, key: K, value: V) Allocator.Error!?KV {
            const kv = try self.map.fetchPut(allocator, key, .{ .inner = value }) orelse return null;
            return .{ .key = kv.key, .value = kv.value.inner, .used = kv.value.used };
        }

        /// See `HashMap.getPtr`
        pub fn getPtr(self: Self, key: K) ?*V {
            const item = self.map.getPtr(key) orelse return null;
            if (tracking != .put_only) item.used = true;
            return &item.inner;
        }

        /// See `HashMap.get`
        pub fn get(self: Self, key: K) ?V {
            return if (self.getPtr(key)) |v| v.* else null;
        }

        /// See `HashMap.getOrPut`
        pub fn getOrPut(self: *Self, allocator: Allocator, key: K) Allocator.Error!GetOrPutResult {
            const entry = try self.map.getOrPut(allocator, key);
            if (tracking != .put_only) entry.value_ptr.used = true;
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
            return .{ .key = kv.key, .value = kv.value.inner, .used = kv.value.used };
        }

        /// Takes a `value_ptr` from and iterator `Entry` or from `getPtr`and sets the used
        /// state to the value provided.
        pub fn setUsed(value_ptr: *V, used: bool) void {
            const tracked: *Tracked(V) = @fieldParentPtr("inner", value_ptr);
            tracked.used = used;
        }

        /// Returns all keys that had not been used since the last call to this function
        pub fn reset(self: *Self, allocator: std.mem.Allocator) ![]const K {
            var unused = std.ArrayListUnmanaged(K).empty;
            var map_it = self.map.iterator();
            while (map_it.next()) |entry| {
                if (entry.value_ptr.used) {
                    entry.value_ptr.used = false;
                } else {
                    try unused.append(allocator, entry.key_ptr.*);
                }
            }
            return unused.toOwnedSlice(allocator);
        }
    };
}

test TrackingAutoHashMap {
    var map = TrackingAutoHashMap(u32, u32, .get_and_put).empty;
    defer map.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, map.count());

    try map.put(std.testing.allocator, 1, 11);
    try map.put(std.testing.allocator, 2, 22);
    try map.put(std.testing.allocator, 3, 33);

    try std.testing.expectEqual(3, map.count());

    { // Reset
        const unused_keys = try map.reset(std.testing.allocator);
        defer std.testing.allocator.free(unused_keys);
        try std.testing.expectEqualSlices(u32, &.{}, unused_keys);
    }

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

    { // Reset
        const unused_keys = try map.reset(std.testing.allocator);
        defer std.testing.allocator.free(unused_keys);
        try std.testing.expectEqualSlices(u32, &.{1}, unused_keys);
    }
}

const std = @import("std");
const Allocator = std.mem.Allocator;

test {
    @import("std").testing.refAllDecls(@This());
}
