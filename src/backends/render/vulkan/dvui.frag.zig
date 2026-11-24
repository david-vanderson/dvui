const std = @import("std");
const Image = @SpirvType(.{ .image = .{ .usage = .{ .sampled = f32 }, .format = .unknown, .dim = .@"2d", .depth = .unknown, .arrayed = false, .multisampled = false, .access = .unknown } });
const SampledImage = @SpirvType(.{ .sampled_image = Image });
const texture = @extern(*addrspace(.constant) const SampledImage, .{ .name = "texture_sampler", .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } } });
const in_col = @extern(*addrspace(.input) const @Vector(4, f32), .{ .name = "in_col", .decoration = .{ .location = 0 } });
const in_uv = @extern(*addrspace(.input) const @Vector(2, f32), .{ .name = "in_uv", .decoration = .{ .location = 1 } });
const out_color = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "out_color", .decoration = .{ .location = 0 } });
export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    out_color.* = std.spirv.imageSampleImplicitLod(texture, in_uv.*) * in_col.*;
}
