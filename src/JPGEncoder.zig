output: *std.Io.Writer,
density: u16,

/// Bytes remaining to fill the buffer with the header
///
/// Set to 0 to skip custom density header
bytes_remaining_of_jfif_app0_segment: u32 = start_of_jfif_file,

pub const JPGEncoder = @This();

pub const min_buffer_size = start_of_jfif_file;
// https://en.wikipedia.org/wiki/JPEG_File_Interchange_Format#JFIF_APP0_marker_segment
// Assumes stbi jpg will always return image files starting with SOI (FF D8) followed by JFIF-APP0 (FF E0 ...)
/// The number of bytes from the start of a JFIF file to the end of the density values
const start_of_jfif_file = 2 // SOI marker
    + 2 // APP0 marker
    + 2 // length
    + 5 // "JFIF\0" identified
    + 2 // version
    + (1 + 2 + 2); // density unit and x/y values

/// dvui will set the density of 72 dpi (2834.64 px/m) times `windowNaturalScale`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn init(output: *std.Io.Writer) JPGEncoder {
    return JPGEncoder.initDensity(output, @intFromFloat(@round(dvui.windowNaturalScale() * 72.0)));
}

/// `density` is in pixels per inch (2.54 cm).
/// `density == 0` => don't write custom density
pub fn initDensity(output: *std.Io.Writer, density: u16) JPGEncoder {
    std.debug.assert(output.buffer.len >= min_buffer_size);
    var self = JPGEncoder{
        .output = output,
        .density = density,
    };
    if (density == 0) {
        // We have no density to write
        self.bytes_remaining_of_jfif_app0_segment = 0;
    }
    return self;
}

/// Writes a JPG with a quality of 90%
/// dvui will set the density of 72 dpi (2834.64 px/m) times `windowNaturalScale`
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn write(output: *std.Io.Writer, pixels: []u8, width: u32, height: u32) !void {
    var self = JPGEncoder.init(output);
    return self.writeWithQuality(pixels, width, height, 90);
}

/// Writes a JPG with a any quality between 0-100 and the density provided.
///
/// `quality == 0` uses the stb_image default
/// `density` is in pixels per inch (2.54 cm).
/// `density == 0` => don't write custom density
pub fn writeWithQuality(self: *JPGEncoder, pixels: []u8, width: u32, height: u32, quality: u7) !void {
    const res = dvui.c.stbi_write_jpg_to_func(
        &stbi_write_jpg_callback,
        self,
        @intCast(width),
        @intCast(height),
        dvui.c.STBI_rgb_alpha,
        pixels.ptr,
        @intCast(quality),
    );
    if (res == 0) return dvui.StbImageError.stbImageError;
}

fn callback(self: *JPGEncoder, data_in: []const u8) !void {
    if (self.bytes_remaining_of_jfif_app0_segment == 0) {
        try self.output.writeAll(data_in);
    } else if (data_in.len < self.bytes_remaining_of_jfif_app0_segment) {
        self.bytes_remaining_of_jfif_app0_segment -= @intCast(data_in.len);
        try self.output.writeAll(data_in);
    } else {
        // Write header up until density into the buffer
        try self.output.writeAll(data_in[0..self.bytes_remaining_of_jfif_app0_segment]);

        // Replace density
        self.output.undo(@sizeOf(u8) + 2 * @sizeOf(u16));
        try self.output.writeByte(0x01); // 0x01 => Pixels per inch density unit
        try self.output.writeInt(u16, self.density, .big); // Xdensity
        try self.output.writeInt(u16, self.density, .big); // Ydensity

        // Write the rest of the data
        try self.output.writeAll(data_in[self.bytes_remaining_of_jfif_app0_segment..]);
        self.bytes_remaining_of_jfif_app0_segment = 0;
    }
}

fn stbi_write_jpg_callback(ctx: ?*anyopaque, data_ptr: ?*anyopaque, len: c_int) callconv(.c) void {
    const self: *JPGEncoder = @ptrCast(@alignCast(ctx.?));
    const data: []const u8 = @as([*]const u8, @ptrCast(@alignCast(data_ptr.?)))[0..@intCast(len)];
    // TODO: Maybe propagate writer error by storing it as a field?
    self.callback(data) catch |err| dvui.logError(@src(), err, "Failed to write png data to output", .{});
}

const std = @import("std");
const dvui = @import("dvui.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
