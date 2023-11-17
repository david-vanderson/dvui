const std = @import("std");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();
var datas = std.AutoHashMap(u32, SavedData).init(gpa);

pub fn main() !void {
    try dataSetSlice(gpa, 1, @as([:0]const u8, "hello"));
    const hello = dataGetSlice(1, [:0]u8);
    std.debug.print("hello = \"{s}\" len {d} sentinel {d}\n", .{ hello, hello.len, hello[hello.len] });
    //var foo = try gpa.allocWithOptions(u8, 2, null, 5);
    //_ = gpa.resize(foo, 5);
}

pub const SavedData = struct {
    alignment: u8,
    data: []u8,

    pub fn free(self: *const SavedData, allocator: std.mem.Allocator) void {
        allocator.rawFree(self.data, @ctz(self.alignment), @returnAddress());
    }
};

pub fn dataGetSlice(id: u32, comptime T: type) T {
    const dt = @typeInfo(T);

    if (datas.getPtr(id)) |sd| {
        const bytes = sd.data;
        if (dt.Pointer.sentinel) |s_ptr| {
            const cast_s_ptr = @as(*const dt.Pointer.child, @alignCast(@ptrCast(s_ptr)));
            //return @as([:cast_s_ptr.*]align(@alignOf(dt.Pointer.child)) dt.Pointer.child, @alignCast(@ptrCast(std.mem.bytesAsSlice(dt.Pointer.child, bytes[0 .. bytes.len - @sizeOf(dt.Pointer.child)]))));
            return @as([:cast_s_ptr.*]align(@alignOf(dt.Pointer.child)) dt.Pointer.child, @alignCast(@ptrCast(std.mem.bytesAsSliceSentinel(dt.Pointer.child, cast_s_ptr, bytes))));
        } else {
            return @as([]align(@alignOf(dt.Pointer.child)) dt.Pointer.child, @alignCast(std.mem.bytesAsSlice(dt.Pointer.child, bytes)));
        }
    }

    unreachable;
}

pub fn dataSetSlice(allocator: std.mem.Allocator, id: u32, data_in: anytype) !void {
    const dt = @typeInfo(@TypeOf(data_in));
    var bytes: []const u8 = undefined;
    bytes = std.mem.sliceAsBytesSentinel(data_in);
    //if (dt.Pointer.sentinel != null) {
    //bytes.len += @sizeOf(dt.Pointer.child);
    //}

    const alignment = dt.Pointer.alignment;

    var sd = SavedData{ .alignment = alignment, .data = try allocator.allocWithOptions(u8, bytes.len, alignment, null) };

    @memcpy(sd.data, bytes);

    try datas.put(id, sd);
}
