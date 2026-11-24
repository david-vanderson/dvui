const std = @import("std");
const ScreenTransform = extern struct { scale: @Vector(2, f32), translate: @Vector(2, f32) };
const transform = @extern(*addrspace(.push_constant) const ScreenTransform, .{ .name = "screen_transform" });
const in_pos = @extern(*addrspace(.input) const @Vector(2, f32), .{ .name = "in_pos", .decoration = .{ .location = 0 } });
const in_col = @extern(*addrspace(.input) const @Vector(4, f32), .{ .name = "in_col", .decoration = .{ .location = 1 } });
const in_uv = @extern(*addrspace(.input) const @Vector(2, f32), .{ .name = "in_uv", .decoration = .{ .location = 2 } });
const out_col = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "out_col", .decoration = .{ .location = 0 } });
const out_uv = @extern(*addrspace(.output) @Vector(2, f32), .{ .name = "out_uv", .decoration = .{ .location = 1 } });
export fn main() callconv(.spirv_vertex) void {
    const p = in_pos.* * transform.scale + transform.translate;
    std.spirv.position_out.* = .{ p[0], p[1], 0, 1 };
    out_col.* = in_col.*;
    out_uv.* = in_uv.*;
}
