//! Stupid script to insert the DVUI logo in autodocs.
//!
//! Replace a string tag by base64 encoding version of the logos, and is
//! called by the build system, so this is easy to change the logo.

const std = @import("std");
const Encoder = std.base64.standard.Encoder;
const Decoder = std.base64.standard.Decoder;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // Get files via arguments (passed by build system)
    const args = try init.minimal.args.toSlice(allocator);

    // Open and read the files
    const cwd = std.Io.Dir.cwd();
    const html = try cwd.readFileAlloc(init.io, args[1], allocator, .unlimited);
    const favico = try cwd.readFileAlloc(init.io, args[2], allocator, .unlimited);
    const logo = try cwd.readFileAlloc(init.io, args[3], allocator, .unlimited);

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
    var stdout = std.Io.File.stdout().writer(init.io, &buf);
    try stdout.interface.print("{s}", .{html_out});
    try stdout.interface.flush();
}
