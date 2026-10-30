//! Hash keys, and the snapshot digest.
//!
//! Two jobs that used to be mixed by hand, kept apart here:
//! - laying a value out as bytes is `s2s`'s job: field order, no padding, no
//!   pointer bytes, and a type id ahead of the value so a layout change is
//!   detected instead of silently colliding;
//! - hashing those bytes is `std.hash.Wyhash`'s job.
//!
//! Wyhash is not DoS resistant and does not need to be: every value hashed
//! here is produced by the program itself, never by an untrusted peer.
const std = @import("std");
const s2s = @import("s2s");

pub const Hasher = std.hash.Wyhash;

/// A `std.Io.Writer` that feeds everything written to a `Hasher`.
///
/// Unbuffered, so every write reaches the hasher directly and `flush` (which
/// `s2s.serialize` ends with) has nothing left to do.
pub const HasherWriter = struct {
    hasher: *Hasher,
    writer: std.Io.Writer,

    pub fn init(hasher: *Hasher) HasherWriter {
        return .{
            .hasher = hasher,
            .writer = .{ .vtable = &vtable, .buffer = &empty_buffer },
        };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *HasherWriter = @alignCast(@fieldParentPtr("writer", w));
        if (w.end > 0) {
            self.hasher.update(w.buffer[0..w.end]);
            w.end = 0;
        }

        const slices = data[0 .. data.len - 1];
        const pattern = data[slices.len];
        var written: usize = pattern.len * splat;
        for (slices) |bytes| {
            self.hasher.update(bytes);
            written += bytes.len;
        }
        for (0..splat) |_| self.hasher.update(pattern);
        return written;
    }

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
    };
};

/// The writer is unbuffered, so this slice is never written to; it only needs
/// to exist because `std.Io.Writer` holds a `[]u8`.
var empty_buffer: [0]u8 = .{};

/// Serialize `value` into `hasher`.
pub fn serialize(hasher: *Hasher, value: anytype) void {
    var hw = HasherWriter.init(hasher);
    s2s.serialize(&hw.writer, @TypeOf(value), value) catch unreachable;
}

/// Hash `value`: `s2s` lays it out as bytes, Wyhash hashes them.
pub fn hashOf(value: anytype) u64 {
    var hasher = Hasher.init(0);
    serialize(&hasher, value);
    return hasher.final();
}

test {
    std.testing.refAllDecls(@This());
}
