const std = @import("std");

// hash all input files, replace string "TEMPLATE_HASH" in template_file, write to stdout
const usage =
    \\Usage: ./hash_files <template_file> <input_file>...
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    var template_bytes: []u8 = &.{};
    const Sha256 = std.crypto.hash.sha2.Sha256;
    var sha = Sha256.init(.{});

    for (args, 0..) |arg, i| {
        if (i == 0) continue;

        const contents = try std.Io.Dir.cwd().readFileAlloc(init.io, arg, arena, .unlimited);
        if (i == 1) {
            template_bytes = contents;
        } else {
            sha.update(contents);
        }
    }

    var hash: [Sha256.digest_length]u8 = undefined;
    sha.final(&hash);

    const needle = "TEMPLATE_HASH_WITH_PADDING__ITS_64_BYTES_LONG_THE_SAME_AS_SHA256";
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, template_bytes, pos, needle)) |idx| {
        pos = idx + needle.len;
        _ = try std.fmt.bufPrint(template_bytes[idx..][0..needle.len], "{x}", .{&hash});
    }

    var buf: [1000]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buf);
    try stdout.interface.print("{s}", .{template_bytes});
    try stdout.interface.flush();
}
