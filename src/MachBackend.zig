const std = @import("std");
const gui = @import("gui.zig");
const mach = @import("mach");
const gpu = @import("gpu");
const zm = @import("zmath");

const MachBackend = @This();

gpa: std.mem.Allocator,
core: *mach.Core,
pipeline: *gpu.RenderPipeline,

uniform_buffer: *gpu.Buffer,
uniform_buffer_size: u32,
uniform_buffer_len: u32,
sampler: *gpu.Sampler,

texture: ?*anyopaque,
clipr: gui.Rect,
vtx: std.ArrayList(gui.Vertex),
idx: std.ArrayList(u32),

encoder: *gpu.CommandEncoder,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
vertex_buffer_len: u32,
index_buffer_len: u32,
vertex_buffer_size: u32,
index_buffer_size: u32,

cursor_last: gui.CursorKind = .arrow,

pub fn init(gpa: std.mem.Allocator, core: *mach.Core) !MachBackend {
    var back: MachBackend = undefined;

    back.gpa = gpa;
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
    back.clipr = gui.Rect{};
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

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x4, .offset = @offsetOf(Vertex, "col"), .shader_location = 1 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 2 },
    };
    const vertex_buffer_layout = gpu.VertexBufferLayout{
        .array_stride = @sizeOf(Vertex),
        .step_mode = .vertex,
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    };

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
        .entry_point = "main",
        .targets = &[_]gpu.ColorTargetState{color_target},
        .target_count = 1,
        .constants = null,
    };
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffers = &[_]gpu.VertexBufferLayout{vertex_buffer_layout},
        },
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

fn toMachCursor(cursor: gui.CursorKind) mach.MouseCursor {
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
        .small_wait => .not_allowed,
    };
}

pub fn setCursor(self: *MachBackend, cursor: gui.CursorKind) void {
    if (cursor != self.cursor_last) {
        self.cursor_last = cursor;
        self.core.setMouseCursor(toMachCursor(cursor)) catch {};
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
    pos: gui.Point,
    col: @Vector(4, f32),
    uv: @Vector(2, f32),
};

fn toGUIKey(key: mach.Key) gui.keys.Key {
    return switch (key) {
        .a => .a,
        else => .z,
    };
}

pub fn addEvent(_: *MachBackend, win: *gui.Window, event: mach.Event) bool {
    switch (event) {
        .key_press => |ev| {
            return win.addEventKey(toGUIKey(ev.key), gui.keys.Mod.none, .down);
        },
        .key_release => |ev| {
            return win.addEventKey(toGUIKey(ev.key), gui.keys.Mod.none, .up);
        },
        .mouse_motion => |mm| {
            return win.addEventMouseMotion(@floatCast(f32, mm.pos.x), @floatCast(f32, mm.pos.y));
        },
        .mouse_press => |mb| {
            switch (mb.button) {
                .left => return win.addEventMouseButton(.leftdown),
                .right => return win.addEventMouseButton(.rightdown),
                else => {},
            }
        },
        .mouse_release => |mb| {
            switch (mb.button) {
                .left => return win.addEventMouseButton(.leftup),
                .right => return win.addEventMouseButton(.rightup),
                else => {},
            }
        },
        .mouse_scroll => |s| {
            return win.addEventMouseWheel(s.yoffset);
        },
        else => {},
    }

    return false;
}

pub fn waitEventTimeout(self: *MachBackend, timeout_micros: u32) void {
    if (timeout_micros == std.math.maxInt(u32)) {
        self.core.setWaitEvent(std.math.floatMax(f64));
    } else {
        self.core.setWaitEvent(@intToFloat(f64, timeout_micros) / 1_000_000);
    }
}

pub fn addAllEvents(self: *MachBackend, win: *gui.Window) bool {
    while (self.core.pollEvent()) |event| {
        _ = self.addEvent(win, event);
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

pub fn guiBackend(self: *MachBackend) gui.Backend {
    return gui.Backend.init(self, begin, end, pixelSize, windowSize, renderGeometry, textureCreate, textureDestroy);
}

pub fn begin(self: *MachBackend, arena: std.mem.Allocator) void {
    self.clipr = gui.Rect{};
    self.texture = null;
    self.vtx = std.ArrayList(gui.Vertex).init(arena);
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
    queue.submit(&.{command});
    command.release();
}

pub fn pixelSize(self: *MachBackend) gui.Size {
    const psize = self.core.getFramebufferSize();
    return gui.Size{ .w = @intToFloat(f32, psize.width), .h = @intToFloat(f32, psize.height) };
}

pub fn windowSize(self: *MachBackend) gui.Size {
    const size = self.core.getWindowSize();
    return gui.Size{ .w = @intToFloat(f32, size.width), .h = @intToFloat(f32, size.height) };
}

pub fn renderGeometry(self: *MachBackend, tex: ?*anyopaque, vtx: []gui.Vertex, idx: []u32) void {
    const clipr = gui.windowRectPixels().intersect(gui.clipGet());
    if (clipr.empty()) {
        return;
    }

    //std.debug.print("renderGeometry {} {x}\n", .{clipr, tex});

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
        self.idx.append(id + @intCast(u32, self.vtx.items.len)) catch unreachable;
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

            self.vertex_buffer_size = self.vertex_buffer_len + @intCast(u32, self.vtx.items.len);

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

            self.index_buffer_size = self.index_buffer_len + @intCast(u32, self.idx.items.len);

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

    const default_texture_ptr = gui.iconTexture("default_texture", gui.icons.papirus.actions.media_playback_start_symbolic, 1.0).texture;

    var texture: ?*gpu.Texture = null;
    if (self.texture) |t| {
        texture = @ptrCast(*gpu.Texture, t);
    }

    {
        const model = zm.translation(-gui.windowRectPixels().w / 2, gui.windowRectPixels().h / 2, 0);
        const view = zm.lookAtLh(
            zm.f32x4(0, 0, 1, 1),
            zm.f32x4(0, 0, 0, 1),
            zm.f32x4(0, -1, 0, 0),
        );
        const proj = zm.orthographicLh(gui.windowRectPixels().w, gui.windowRectPixels().h, 1, 0);
        const mvp = zm.mul(zm.mul(view, model), proj);
        const ubo = UniformBufferObject{
            .mat = mvp,
            .use_tex = if (texture != null) 1 else 0,
        };
        self.encoder.writeBuffer(self.uniform_buffer, UniformBufferObject.Size * self.uniform_buffer_len, &.{ubo});
    }

    const bind_group = self.core.device.createBindGroup(
        &gpu.BindGroup.Descriptor{
            .layout = self.pipeline.getBindGroupLayout(0),
            .entries = &.{
                gpu.BindGroup.Entry.buffer(0, self.uniform_buffer, UniformBufferObject.Size * self.uniform_buffer_len, @sizeOf(UniformBufferObject)),
                gpu.BindGroup.Entry.sampler(1, self.sampler),
                gpu.BindGroup.Entry.textureView(2, (texture orelse default_texture_ptr).createView(&gpu.TextureView.Descriptor{})),
            },
        },
    );

    self.uniform_buffer_len += 1;

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_allocator.allocator();
    defer arena_allocator.deinit();

    var vertices = arena.alloc(Vertex, self.vtx.items.len) catch unreachable;
    for (self.vtx.items) |vin, i| {
        vertices[i] = Vertex{ .pos = vin.pos, .col = .{ @intToFloat(f32, vin.col.r) / 255.0, @intToFloat(f32, vin.col.g) / 255.0, @intToFloat(f32, vin.col.b) / 255.0, @intToFloat(f32, vin.col.a) / 255.0 }, .uv = vin.uv };
    }
    //std.debug.print("vertexes {d} + {d} indexes {d} + {d}\n", .{self.vertex_buffer_len, self.vtx.items.len, self.index_buffer_len, self.idx.items.len});
    self.encoder.writeBuffer(self.vertex_buffer, self.vertex_buffer_len * @sizeOf(Vertex), Vertex, vertices);
    self.encoder.writeBuffer(self.index_buffer, self.index_buffer_len * @sizeOf(u32), u32, self.idx.items);

    const render_pass_info = gpu.RenderPassEncoder.Descriptor{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = null,
    };
    const pass = self.encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(self.pipeline);
    pass.setVertexBuffer(0, self.vertex_buffer, @sizeOf(Vertex) * self.vertex_buffer_len, @sizeOf(Vertex) * @intCast(u32, self.vtx.items.len));
    pass.setIndexBuffer(self.index_buffer, .uint32, @sizeOf(u32) * self.index_buffer_len, @sizeOf(u32) * @intCast(u32, self.idx.items.len));
    pass.setBindGroup(0, bind_group, &.{});

    pass.setScissorRect(@floatToInt(u32, self.clipr.x), @floatToInt(u32, self.clipr.y), @floatToInt(u32, @ceil(self.clipr.w)), @floatToInt(u32, @ceil(self.clipr.h)));

    pass.drawIndexed(@intCast(u32, self.idx.items.len), 1, 0, 0, 0);
    pass.end();
    pass.release();
    bind_group.release();

    self.vertex_buffer_len += @intCast(u32, self.vtx.items.len);
    self.index_buffer_len += @intCast(u32, self.idx.items.len);

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
        .bytes_per_row = @intCast(u32, width * 4),
        .rows_per_image = @intCast(u32, height),
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
    const tex = @ptrCast(*gpu.Texture, @alignCast(@alignOf(gpu.Texture), texture));
    tex.release();
    self.gpa.destroy(tex);
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
    \\@stage(vertex) fn main(
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
    \\@stage(fragment) fn main(
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
