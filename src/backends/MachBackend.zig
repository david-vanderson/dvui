const std = @import("std");
const dvui = @import("dvui");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");

const MachBackend = @This();

core: *mach.Core,
pipeline: *gpu.RenderPipeline,

uniform_buffer: *gpu.Buffer,
uniform_buffer_size: u32,
uniform_buffer_len: u32,
sampler: *gpu.Sampler,

texture: ?*anyopaque,
clipr: dvui.Rect,
vtx: std.ArrayList(dvui.Vertex),
idx: std.ArrayList(u32),

encoder: *gpu.CommandEncoder,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
vertex_buffer_len: u32,
index_buffer_len: u32,
vertex_buffer_size: u32,
index_buffer_size: u32,

cursor_last: dvui.Cursor = .arrow,

pub fn init(core: *mach.Core) !MachBackend {
    var back: MachBackend = undefined;

    //try core.setOptions(.{ .vsync = .none });

    back.core = core;
    back.uniform_buffer_size = 1;
    back.uniform_buffer_len = 0;
    back.uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .copy_dst = true, .uniform = true },
        .size = UniformBufferObject.Size * back.uniform_buffer_size,
        .mapped_at_creation = false,
    });

    back.sampler = core.device.createSampler(&.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });

    back.texture = null;
    back.clipr = dvui.Rect{};
    back.vertex_buffer_size = 1000;
    back.index_buffer_size = 1000;
    back.vertex_buffer_len = 0;
    back.index_buffer_len = 0;
    back.vertex_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true, .copy_dst = true },
        .size = @sizeOf(Vertex) * back.vertex_buffer_size,
        .mapped_at_creation = false,
    });
    back.index_buffer = core.device.createBuffer(&.{
        .usage = .{ .index = true, .copy_dst = true },
        .size = @sizeOf(u32) * back.index_buffer_size,
        .mapped_at_creation = false,
    });

    const vs_module = core.device.createShaderModuleWGSL("my vertex shader", vert_wgsl);

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        // .attribute_count = vertex_attributes.len,
        .attributes = &[_]gpu.VertexAttribute{
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
            .{ .format = .float32x4, .offset = @offsetOf(Vertex, "col"), .shader_location = 1 },
            .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
        },
    });

    const fs_module = core.device.createShaderModuleWGSL("my fragment shader", frag_wgsl);

    // Fragment state
    const blend = gpu.BlendState{
        .color = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
        .alpha = .{
            .operation = .add,
            .src_factor = .src_alpha,
            .dst_factor = .one_minus_src_alpha,
        },
    };
    const color_target = gpu.ColorTargetState{
        .format = core.swap_chain_format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState{
        .module = fs_module,
        .entry_point = "fragment_main",
        .targets = &[_]gpu.ColorTargetState{color_target},
        .target_count = 1,
        .constants = null,
    };
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = gpu.VertexState.init(.{
            .module = vs_module,
            .entry_point = "vertex_main",
            .buffers = &[_]gpu.VertexBufferLayout{vertex_buffer_layout},
        }),
        .primitive = .{
            .cull_mode = .none,
            .topology = .triangle_list,
        },
    };

    back.pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    vs_module.release();
    fs_module.release();

    return back;
}

fn toMachCursor(cursor: dvui.Cursor) mach.MouseCursor {
    return switch (cursor) {
        .arrow => .arrow,
        .ibeam => .ibeam,
        .crosshair => .crosshair,
        .arrow_w_e => .resize_ew,
        .arrow_n_s => .resize_ns,
        .arrow_nw_se => .resize_nwse,
        .arrow_ne_sw => .resize_nesw,
        .arrow_all => .resize_all,
        .bad => .not_allowed,
        .hand => .pointing_hand,

        // not supported in mach glfw backend
        .wait => .not_allowed,
        .wait_arrow => .not_allowed,
    };
}

pub fn setCursor(self: *MachBackend, cursor: dvui.Cursor) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;
        self.core.setMouseCursor(toMachCursor(cursor)) catch unreachable;
    }
}

pub fn deinit(self: *MachBackend) void {
    self.uniform_buffer.release();
    self.sampler.release();
    self.vertex_buffer.release();
    self.index_buffer.release();
    self.pipeline.release();
}

pub const UniformBufferObject = struct {
    // dawn gives me an error when trying to align uniforms to less than this
    const Size = 256;
    mat: zm.Mat,
    use_tex: i32,
};

pub const Vertex = struct {
    pos: dvui.Point,
    col: @Vector(4, f32),
    uv: @Vector(2, f32),
};

fn toDVUIKey(key: mach.Key) dvui.enums.Key {
    return switch (key) {
        .a => .a,
        else => blk: {
            std.debug.print("todvUIKey unknown key {d}\n", .{key});
            break :blk .unknown;
        },
    };
}

pub fn addEvent(_: *MachBackend, win: *dvui.Window, event: mach.Event) !bool {
    switch (event) {
        .key_press => |ev| {
            return try win.addEventKey(.{ .down = toDVUIKey(ev.key) }, .none);
        },
        .key_release => |ev| {
            return try win.addEventKey(.{ .up = toDVUIKey(ev.key) }, .none);
        },
        .mouse_motion => |mm| {
            return try win.addEventMouseMotion(@as(f32, @floatCast(mm.pos.x)), @as(f32, @floatCast(mm.pos.y)));
        },
        .mouse_press => |mb| {
            switch (mb.button) {
                .left => return try win.addEventMouseButton(.{ .press = .left }),
                .right => return try win.addEventMouseButton(.{ .press = .right }),
                else => {},
            }
        },
        .mouse_release => |mb| {
            switch (mb.button) {
                .left => return try win.addEventMouseButton(.{ .release = .left }),
                .right => return try win.addEventMouseButton(.{ .release = .right }),
                else => {},
            }
        },
        .mouse_scroll => |s| {
            return try win.addEventMouseWheel(s.yoffset);
        },
        else => {},
    }

    return false;
}

pub fn waitEventTimeout(self: *MachBackend, timeout_micros: u32) void {
    self.core.setWaitEvent(@as(f64, @floatFromInt(timeout_micros)) / 1_000_000);
}

pub fn addAllEvents(self: *MachBackend, win: *dvui.Window) !bool {
    while (self.core.pollEvent()) |event| {
        _ = try self.addEvent(win, event);
        switch (event) {
            .key_press => |ev| {
                if (ev.key == .space)
                    return true;
            },
            else => {},
        }
    }

    return false;
}

pub fn backend(self: *MachBackend) dvui.Backend {
    return dvui.Backend.init(self, begin, end, pixelSize, windowSize, drawClippedTriangles, textureCreate, textureDestroy);
}

pub fn begin(self: *MachBackend, arena: std.mem.Allocator) void {
    self.clipr = dvui.Rect{};
    self.texture = null;
    self.vtx = std.ArrayList(dvui.Vertex).init(arena);
    self.idx = std.ArrayList(u32).init(arena);

    self.encoder = self.core.device.createCommandEncoder(null);
    self.uniform_buffer_len = 0;
    self.vertex_buffer_len = 0;
    self.index_buffer_len = 0;
}

pub fn end(self: *MachBackend) void {
    self.flushRender();
    var command = self.encoder.finish(null);
    //std.debug.print("  release encoder\n", .{});
    self.encoder.release();

    var queue = self.core.device.getQueue();
    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
}

pub fn pixelSize(self: *MachBackend) dvui.Size {
    const psize = self.core.getFramebufferSize();
    return dvui.Size{ .w = @as(f32, @floatFromInt(psize.width)), .h = @as(f32, @floatFromInt(psize.height)) };
}

pub fn windowSize(self: *MachBackend) dvui.Size {
    const size = self.core.getWindowSize();
    return dvui.Size{ .w = @as(f32, @floatFromInt(size.width)), .h = @as(f32, @floatFromInt(size.height)) };
}

pub fn drawClippedTriangles(self: *MachBackend, tex: ?*anyopaque, vtx: []const dvui.Vertex, idx: []const u32) void {
    const clipr = dvui.windowRectPixels().intersect(dvui.clipGet());
    if (clipr.empty()) {
        return;
    }

    //std.debug.print("drawClippedTriangles {} {x}\n", .{clipr, tex});

    if (clipr.x != self.clipr.x or
        clipr.y != self.clipr.y or
        clipr.w != self.clipr.w or
        clipr.h != self.clipr.h or
        (self.texture == null and tex != null) or
        (self.texture != null and tex == null) or
        (self.texture != null and tex != null and self.texture.? != tex.?))
    {
        // clip rect or texture changed, can't coalesce so flush
        self.flushRender();
    }

    self.clipr = clipr;
    self.texture = tex;

    for (idx) |id| {
        self.idx.append(id + @as(u32, @intCast(self.vtx.items.len))) catch unreachable;
    }

    for (vtx) |v| {
        self.vtx.append(v) catch unreachable;
    }
}

pub fn flushRender(self: *MachBackend) void {
    if (self.vtx.items.len == 0) {
        return;
    }

    //std.debug.print("  flush {d} {d}\n", .{self.uniform_buffer_size, self.uniform_buffer_len});

    if (self.uniform_buffer_size < self.uniform_buffer_len + 1 or
        self.vertex_buffer_size < self.vertex_buffer_len + self.vtx.items.len or
        self.index_buffer_size < self.index_buffer_len + self.idx.items.len)
    {
        if (self.uniform_buffer_size < self.uniform_buffer_len + 1) {
            self.uniform_buffer.release();

            self.uniform_buffer_size = self.uniform_buffer_len + 1;

            //std.debug.print("creating uniform buffer {d}\n", .{self.uniform_buffer_size});
            self.uniform_buffer = self.core.device.createBuffer(&.{
                .usage = .{ .copy_dst = true, .uniform = true },
                .size = UniformBufferObject.Size * self.uniform_buffer_size,
                .mapped_at_creation = false,
            });

            self.uniform_buffer_len = 0;
        }

        if (self.vertex_buffer_size < self.vertex_buffer_len + self.vtx.items.len) {
            self.vertex_buffer.release();

            self.vertex_buffer_size = self.vertex_buffer_len + @as(u32, @intCast(self.vtx.items.len));

            //std.debug.print("creating vertex buffer {d}\n", .{self.vertex_buffer_size});
            self.vertex_buffer = self.core.device.createBuffer(&.{
                .usage = .{ .vertex = true, .copy_dst = true },
                .size = @sizeOf(Vertex) * self.vertex_buffer_size,
                .mapped_at_creation = false,
            });

            self.vertex_buffer_len = 0;
        }

        if (self.index_buffer_size < self.index_buffer_len + self.idx.items.len) {
            self.index_buffer.release();

            self.index_buffer_size = self.index_buffer_len + @as(u32, @intCast(self.idx.items.len));

            //std.debug.print("creating index buffer {d}\n", .{self.index_buffer_size});
            self.index_buffer = self.core.device.createBuffer(&.{
                .usage = .{ .index = true, .copy_dst = true },
                .size = @sizeOf(u32) * self.index_buffer_size,
                .mapped_at_creation = false,
            });

            self.index_buffer_len = 0;
        }
    }

    const back_buffer_view = self.core.swap_chain.?.getCurrentTextureView();
    defer back_buffer_view.release();

    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .load,
        .store_op = .store,
    };

    const default_tex = dvui.iconTexture("default_texture", dvui.icons.papirus.actions.media_playback_start_symbolic, 1.0) catch |err| {
        std.debug.print("MachBackend:flushRender: got {!} when doing iconTexture for default texture\n", .{err});
        return;
    };
    const default_texture_ptr = @as(*gpu.Texture, @ptrCast(default_tex.texture));

    var texture: ?*gpu.Texture = null;
    if (self.texture) |t| {
        texture = @as(*gpu.Texture, @ptrCast(t));
    }

    {
        const model = zm.translation(-dvui.windowRectPixels().w / 2, dvui.windowRectPixels().h / 2, 0);
        const view = zm.lookAtLh(
            zm.f32x4(0, 0, 1, 1),
            zm.f32x4(0, 0, 0, 1),
            zm.f32x4(0, -1, 0, 0),
        );
        const proj = zm.orthographicLh(dvui.windowRectPixels().w, dvui.windowRectPixels().h, 1, 0);
        const mvp = zm.mul(zm.mul(view, model), proj);
        const ubo = UniformBufferObject{
            .mat = mvp,
            .use_tex = if (texture != null) 1 else 0,
        };
        self.encoder.writeBuffer(self.uniform_buffer, UniformBufferObject.Size * self.uniform_buffer_len, &[_]UniformBufferObject{ubo});
    }

    const bind_group = self.core.device.createBindGroup(
        &gpu.BindGroup.Descriptor.init(.{
            .layout = self.pipeline.getBindGroupLayout(0),
            .entries = &[_]gpu.BindGroup.Entry{
                gpu.BindGroup.Entry.buffer(0, self.uniform_buffer, UniformBufferObject.Size * self.uniform_buffer_len, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.sampler(1, self.sampler),
                gpu.BindGroup.Entry.textureView(2, (texture orelse default_texture_ptr).createView(&gpu.TextureView.Descriptor{})),
            },
        }),
    );

    self.uniform_buffer_len += 1;

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    var vertices = arena.alloc(Vertex, self.vtx.items.len) catch unreachable;
    for (self.vtx.items, 0..) |vin, i| {
        vertices[i] = Vertex{ .pos = vin.pos, .col = .{ @as(f32, @floatFromInt(vin.col.r)) / 255.0, @as(f32, @floatFromInt(vin.col.g)) / 255.0, @as(f32, @floatFromInt(vin.col.b)) / 255.0, @as(f32, @floatFromInt(vin.col.a)) / 255.0 }, .uv = vin.uv };
    }
    //std.debug.print("vertexes {d} + {d} indexes {d} + {d}\n", .{self.vertex_buffer_len, self.vtx.items.len, self.index_buffer_len, self.idx.items.len});
    self.encoder.writeBuffer(self.vertex_buffer, self.vertex_buffer_len * @sizeOf(Vertex), vertices);
    self.encoder.writeBuffer(self.index_buffer, self.index_buffer_len * @sizeOf(u32), self.idx.items);

    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = null,
    });
    const pass = self.encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(self.pipeline);
    pass.setVertexBuffer(0, self.vertex_buffer, @sizeOf(Vertex) * self.vertex_buffer_len, @sizeOf(Vertex) * @as(u32, @intCast(self.vtx.items.len)));
    pass.setIndexBuffer(self.index_buffer, .uint32, @sizeOf(u32) * self.index_buffer_len, @sizeOf(u32) * @as(u32, @intCast(self.idx.items.len)));
    pass.setBindGroup(0, bind_group, &.{});

    // figure out how much we are losing by truncating x and y, need to add that back to w and h
    pass.setScissorRect(@as(u32, @intFromFloat(self.clipr.x)), @as(u32, @intFromFloat(self.clipr.y)), @as(u32, @intFromFloat(@ceil(self.clipr.w + self.clipr.x - @floor(self.clipr.x)))), @as(u32, @intFromFloat(@ceil(self.clipr.h + self.clipr.y - @floor(self.clipr.y)))));

    pass.drawIndexed(@as(u32, @intCast(self.idx.items.len)), 1, 0, 0, 0);
    pass.end();
    pass.release();
    bind_group.release();

    self.vertex_buffer_len += @as(u32, @intCast(self.vtx.items.len));
    self.index_buffer_len += @as(u32, @intCast(self.idx.items.len));

    self.vtx.clearRetainingCapacity();
    self.idx.clearRetainingCapacity();
}

pub fn textureCreate(self: *MachBackend, pixels: []const u8, width: u32, height: u32) *anyopaque {
    const img_size = gpu.Extent3D{ .width = width, .height = height };
    var texture = self.core.device.createTexture(&.{
        .size = img_size,
        .format = .rgba8_unorm,
        .usage = .{
            .texture_binding = true,
            .copy_dst = true,
            .render_attachment = true,
        },
    });

    const data_layout = gpu.Texture.DataLayout{
        .bytes_per_row = @as(u32, @intCast(width * 4)),
        .rows_per_image = @as(u32, @intCast(height)),
    };

    var queue = self.core.device.getQueue();
    queue.writeTexture(&.{ .texture = texture }, &data_layout, &img_size, pixels);

    return texture;
}

pub fn textureDestroy(self: *MachBackend, texture: *anyopaque) void {
    if (self.texture != null and self.texture.? == texture) {
        // flush so we don't accidentally release this texture before we use it
        self.flushRender();
    }

    const tex = @as(*gpu.Texture, @ptrCast(texture));
    tex.release();
}

const vert_wgsl =
    \\struct Uniforms {
    \\  matrix: mat4x4<f32>,
    \\  use_tex: i32,
    \\};
    \\
    \\@group(0) @binding(0) var<uniform> uniforms : Uniforms;
    \\
    \\struct VertexOutput {
    \\  @builtin(position) position : vec4<f32>,
    \\  @location(0) color : vec4<f32>,
    \\  @location(1) uv: vec2<f32>,
    \\};
    \\
    \\@stage(vertex) fn vertex_main(
    \\  @location(0) position : vec2<f32>,
    \\  @location(1) color : vec4<f32>,
    \\  @location(2) uv: vec2<f32>,
    \\) -> VertexOutput {
    \\  var output : VertexOutput;
    \\
    \\  var pos = vec4<f32>(position, 0.0, 1.0);
    \\  output.position = uniforms.matrix * pos;
    \\
    \\  output.color = color;
    \\  output.uv = uv;
    \\
    \\  return output;
    \\}
;

const frag_wgsl =
    \\struct Uniforms {
    \\  matrix: mat4x4<f32>,
    \\  use_tex: i32,
    \\};
    \\
    \\@group(0) @binding(0) var<uniform> uniforms : Uniforms;
    \\@group(0) @binding(1) var mySampler : sampler;
    \\@group(0) @binding(2) var myTexture : texture_2d<f32>;
    \\
    \\@stage(fragment) fn fragment_main(
    \\  @location(0) color : vec4<f32>,
    \\  @location(1) uv : vec2<f32>,
    \\) -> @location(0) vec4<f32> {
    \\    if (uniforms.use_tex == 1) {
    \\      return textureSample(myTexture, mySampler, uv) * color;
    \\    }
    \\    else {
    \\      return color;
    \\    }
    \\}
;
