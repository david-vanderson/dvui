//! Stupid script to insert the DVUI logo in autodocs.
//!
//! Replace a string tag by base64 encoding version of the logos, and is
//! called by the build system, so this is easy to change the logo.

const std = @import("std");
const Encoder = std.base64.standard.Encoder;
const Decoder = std.base64.standard.Decoder;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get files via arguments (passed by build system)
    const args = try std.process.argsAlloc(allocator);

    // Open and read the files
    var html_file = try std.fs.openFileAbsolute(args[1], .{});
    defer html_file.close();
    const html = try html_file.readToEndAlloc(allocator, std.math.maxInt(usize));

    var favico_file = try std.fs.openFileAbsolute(args[2], .{});
    defer favico_file.close();
    const favico = try favico_file.readToEndAlloc(allocator, std.math.maxInt(usize));

    var logo_file = try std.fs.openFileAbsolute(args[3], .{});
    defer logo_file.close();
    const logo = try logo_file.readToEndAlloc(allocator, std.math.maxInt(usize));

    // Encode images
    const fav_len = Encoder.calcSize(favico.len);
    const b64_favico = try allocator.alloc(u8, fav_len);
    _ = Encoder.encode(b64_favico, favico);
    const logo_len = Encoder.calcSize(logo.len);
    const b64_logo = try allocator.alloc(u8, logo_len);
    _ = Encoder.encode(b64_logo, logo);

    // Replace needles
    var html_out = try std.mem.replaceOwned(u8, allocator, html, "B64_FAVICON_DATA_TO_INSERT_HERE", b64_favico);
    html_out = try std.mem.replaceOwned(u8, allocator, html_out, "B64_LOGO_DATA_TO_INSERT_HERE", b64_logo);

    // Output resulting html file for the build system to do it's magic.
    var buf: [1000]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&buf);
    try stdout.interface.print("{s}", .{html_out});
    try stdout.interface.flush();
}
