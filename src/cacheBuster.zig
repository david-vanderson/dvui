const std = @import("std");

// hash all input files, replace string "TEMPLATE_HASH" in template_file, write to stdout
const usage =
    \\Usage: ./hash_files <template_file> <input_file>...
;

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    var template_bytes: []u8 = &.{};
    const Sha256 = std.crypto.hash.sha2.Sha256;
    var sha = Sha256.init(.{});

    for (args, 0..) |arg, i| {
        if (i == 0) continue;

        var file = try std.fs.cwd().openFile(arg, .{});
        const contents = try file.reader().readAllAlloc(arena, 100 * 1024 * 1024);
        if (i == 1) {
            template_bytes = contents;
        } else {
            sha.update(contents);
        }
    }

    var hash: [Sha256.digest_length]u8 = undefined;
    sha.final(&hash);

    const needle = "TEMPLATE_HASH";
    const index = std.mem.indexOf(u8, template_bytes, needle);
    if (index) |idx| {
        try std.io.getStdOut().writer().writeAll(template_bytes[0..idx]);
        try std.io.getStdOut().writer().print("{s}", .{std.fmt.fmtSliceHexLower(&hash)});
        try std.io.getStdOut().writer().writeAll(template_bytes[idx + needle.len ..]);
    }
}
