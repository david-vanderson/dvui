const std = @import("std");

pub fn main() !void {
    const sub_path = "/lib/x86_64-linux-gnu";
    const sub_path_c = try std.os.toPosixPath(sub_path);
    const index = std.mem.indexOfScalar(u8, &sub_path_c, 0);
    std.debug.print("sub_path {s} -> {?d} {s}\n", .{ sub_path, index, sub_path_c });
}
