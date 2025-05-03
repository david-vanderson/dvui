const dvui = @import("dvui.zig");

pos: dvui.Point.Physical,
col: dvui.Color,
uv: @Vector(2, f32),

test {
    @import("std").testing.refAllDecls(@This());
}
