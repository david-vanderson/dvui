const dvui = @import("dvui.zig");

pos: dvui.Point.Physical,
col: dvui.Color.PMA,
uv: @Vector(2, f32),

test {
    @import("std").testing.refAllDecls(@This());
}
