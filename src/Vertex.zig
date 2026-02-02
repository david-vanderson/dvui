const dvui = @import("dvui.zig");

pub const Index = switch (@import("build_options").vertex_index) {
    .u16 => u16,
    .u32 => u32,
};

pos: dvui.Point.Physical,
col: dvui.Color.PMA = .{},
uv: @Vector(2, f32) = @splat(0),

test {
    @import("std").testing.refAllDecls(@This());
}
