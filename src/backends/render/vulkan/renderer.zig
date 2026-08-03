//! Vulkan dvui renderer, adapted from https://github.com/Deins/dvui_vk.
//! * Follows the `max_frames_in_flight` convention specified during init.
//!     Before the Nth subsequent `beginFrame`, all GPU work recorded during the
//!     original call must have completed. Automatic frame rotation assumes prompt,
//!     FIFO submission to the same graphics queue. The limit is global when a
//!     renderer is shared by multiple windows.
//!     Violating this contract can overwrite buffers or destroy textures still in
//!     use by the GPU.
//! * Memory: all space for vertex & index buffers is preallocated at start requiring setting appropriate limits in options.
//!     Requests to render over limit is safe but will lead to draw commands being ignored. Note that these settings are per frame and total memory allocated will depend on max frames in flight.
//!     Texture bookkeeping is similarly preallocated. The built-in GPU allocator
//!     uses one allocation per image; applications with many small images can use
//!     the optional resource-level allocator hooks instead.
//! * Command buffers: screen draws are recorded into the caller's command buffer.
//!     Texture uploads and render-target draws are recorded into an optional
//!     renderer-owned prepass command buffer, which must execute first. The caller
//!     can either submit it through `SubmitPrepass` or obtain it from `endFrame`.
//!
//! Minimal frame integration (without a submission callback):
//! ```zig
//! try renderer.beginFrame(main_cmd, extent);
//! // Run the DVUI frame; its backend calls record into `renderer`.
//! const recorded = try renderer.endFrame();
//! // End command-buffer recording, then submit `recorded.prepass` (if present)
//! // before `recorded.main` on the same ordered graphics queue.
//! ```
const std = @import("std");
const slog = std.log.scoped(.dvui_vulkan);
const dvui = @import("dvui");
const vk = @import("vk");
const Size = dvui.Size;

const vs_spv align(64) = @embedFile("dvui.vert.spv").*;
const fs_spv align(64) = @embedFile("dvui.frag.spv").*;

const Self = @This();

/// Vulkan declarations used by this renderer. Custom backends should use this
/// re-export so their handles have the same generated Zig types.
pub const vulkan = vk;
pub const DeviceProxy = vk.DeviceProxy;
pub const Vertex = dvui.Vertex;
pub const Index = dvui.Vertex.Index;
pub const invalid_texture: *anyopaque = @ptrFromInt(0xBAD0BAD0); //@ptrFromInt(0xFFFF_FFFF);
/// following image applications, dvui does math in srgb color space, so interpret all textures as unorm so no gamma correction occurs
pub const img_format = vk.Format.r8g8b8a8_unorm; // dvui works in srgb color space, so we don't linearize srgb -> linear colorspace
pub const TextureIdx = u16;

pub const MainTarget = union(enum) {
    dynamic: struct {
        /// Borrowed, including its `p_next` chain and format array, for the
        /// duration of `init` only.
        info: vk.PipelineRenderingCreateInfo,
        samples: vk.SampleCountFlags = .{ .@"1_bit" = true },
    },
    static: struct {
        render_pass: vk.RenderPass,
        subpass: u32 = 0,
        samples: vk.SampleCountFlags = .{ .@"1_bit" = true },
    },
};

pub const PipelineHandles = struct {
    pipeline: vk.Pipeline,
    pipeline_layout: vk.PipelineLayout,
};

pub const PipelineSource = union(enum) {
    builtin,
    borrowed: PipelineHandles,
    transferred: PipelineHandles,
};

/// Public pieces of the shader/pipeline ABI used by external pipeline sources.
pub const texture_descriptor_binding = vk.DescriptorSetLayoutBinding{
    .binding = 1,
    .descriptor_count = 1,
    .descriptor_type = .combined_image_sampler,
    .stage_flags = .{ .fragment_bit = true },
};

pub const push_constant_range = vk.PushConstantRange{
    .stage_flags = .{ .vertex_bit = true },
    .offset = 0,
    .size = @sizeOf(PushConstants),
};

pub const premultiplied_alpha_blend = vk.PipelineColorBlendAttachmentState{
    .blend_enable = .true,
    .src_color_blend_factor = .one,
    .dst_color_blend_factor = .one_minus_src_alpha,
    .color_blend_op = .add,
    .src_alpha_blend_factor = .one,
    .dst_alpha_blend_factor = .one_minus_src_alpha,
    .alpha_blend_op = .add,
    .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
};

pub const CommandSubmission = struct {
    userdata: ?*anyopaque = null,
    submit: *const fn (userdata: ?*anyopaque, command_buffer: vk.CommandBuffer) anyerror!void,
};

/// Compatibility name for the original prepass submission callback type.
pub const SubmitPrepass = CommandSubmission;

pub const ResourceUsage = enum {
    streaming,
    upload,
    readback,
    device_local,
};

pub const MappedBufferMemory = union(enum) {
    coherent: [*]u8,
    non_coherent: struct {
        ptr: [*]u8,
        /// Must flush the requested allocation-relative range. The callback is
        /// responsible for `nonCoherentAtomSize` alignment.
        flush: *const fn (
            userdata: ?*anyopaque,
            dev: DeviceProxy,
            buffer: vk.Buffer,
            allocation: ?*anyopaque,
            offset: vk.DeviceSize,
            size: vk.DeviceSize,
        ) anyerror!void,
        /// Must invalidate the requested allocation-relative range after GPU
        /// writes have completed. The callback is responsible for
        /// `nonCoherentAtomSize` alignment. Required for `.readback` buffers.
        invalidate: ?*const fn (
            userdata: ?*anyopaque,
            dev: DeviceProxy,
            buffer: vk.Buffer,
            allocation: ?*anyopaque,
            offset: vk.DeviceSize,
            size: vk.DeviceSize,
        ) anyerror!void = null,
    },

    pub fn mappedPtr(self: @This()) [*]u8 {
        return switch (self) {
            .coherent => |ptr| ptr,
            .non_coherent => |memory| memory.ptr,
        };
    }
};

pub const BufferAllocation = struct {
    handle: vk.Buffer,
    /// Opaque value returned unchanged to the allocator callbacks.
    allocation: ?*anyopaque = null,
    /// Renderer buffers are always persistently mapped.
    mapped: MappedBufferMemory,
    /// Bound allocation range available from `mapped`, not merely requested size.
    size: vk.DeviceSize,
};

pub const ImageAllocation = struct {
    handle: vk.Image,
    /// Opaque value returned unchanged to `destroy_image`.
    allocation: ?*anyopaque = null,
    /// Used only for renderer statistics; zero is allowed when unavailable.
    size: vk.DeviceSize = 0,
};

/// Resource-level hook for integrating VMA or an application's own GPU
/// allocator. Returned buffers/images must already be bound to memory. Streaming,
/// upload, and readback buffers must remain mapped for their lifetime.
pub const ResourceAllocator = struct {
    /// Must remain valid until renderer `deinit` returns.
    userdata: ?*anyopaque = null,
    create_buffer: *const fn (?*anyopaque, DeviceProxy, *const vk.BufferCreateInfo, ResourceUsage) anyerror!BufferAllocation,
    destroy_buffer: *const fn (?*anyopaque, DeviceProxy, BufferAllocation) void,
    create_image: *const fn (?*anyopaque, DeviceProxy, *const vk.ImageCreateInfo, ResourceUsage) anyerror!ImageAllocation,
    destroy_image: *const fn (?*anyopaque, DeviceProxy, ImageAllocation) void,
};

pub const GpuAllocator = union(enum) {
    builtin: VkMemory,
    custom: ResourceAllocator,
};

// debug flags
const enable_breakpoints = false;
const texture_tracing = false; // tace leaks and usage

/// Initialization options. Callback userdata, borrowed pipeline handles, and the
/// device must remain valid until `deinit`; the dynamic-rendering pointer chain is
/// needed only for the duration of `init`.
pub const InitOptions = struct {
    dev: vk.DeviceProxy,
    /// Select exactly one GPU resource allocation strategy.
    gpu_allocator: GpuAllocator,
    /// render pass from which renderer will be used
    /// or in case of vulkan >= 1.3 specify use dynamic rendering instead
    render_pass: MainTarget,
    /// optional vulkan host side allocator
    vk_alloc: ?*vk.AllocationCallbacks = null,

    /// Graphics-capable queue family used by renderer-owned prepass command pools.
    graphics_queue_family_index: u32,
    /// Optional submission hook used by texture-target readback. It must submit
    /// the command buffer to its graphics queue and return only after all
    /// commands have completed. Once invoked, the renderer treats the command
    /// buffer as delivered even when the callback returns an error. When null,
    /// `textureReadTarget` returns `error.NotImplemented`.
    submit_readback: ?CommandSubmission = null,
    /// Optional convenience submission hook. When null, `endFrame` returns the
    /// prepass command buffer for the application to submit before the main one.
    /// Queue synchronization remains owned by the application.
    submit_prepass: ?CommandSubmission = null,

    /// How many frames can be in flight in worst case (usually equals swapchain image count)
    max_frames_in_flight: u32,

    /// Maximum number of indices that can be submitted in a single frame.
    /// Draw requests above this limit will get discarded
    max_indices_per_frame: u32 = 1024 * 128,
    max_vertices_per_frame: u32 = 1024 * 64,

    /// Maximum number of alive textures supported including render targets. global - across all frames in flight
    /// Overflow should be safe but will lead to heavy visual artifacts as font etc. textures can get evicted
    /// Note: as this is only book keeping limit it can be set quite high. Real texture memory usage could be more concerning, as well as large allocation count.
    max_textures: TextureIdx = 256,

    /// error and invalid texture handle color
    /// if by any chance renderer runs out of textures or due to other reason fails to create a texture then this color will be used as texture
    error_texture_color: [4]u8 = [4]u8{ 255, 0, 255, 255 }, // default bright pink so its noticeable for debug, can be set to alpha 0 for invisible etc.

    /// Wrap mode used by the low-level `createAndUploadTexture` helper. Textures
    /// created through DVUI honor their own `wrap_u` and `wrap_v` options.
    texture_wrap: vk.SamplerAddressMode = .repeat,

    /// Built-in pipeline by default. Borrowed/transferred pipelines must implement
    /// the descriptor, vertex, blend, and push-constant interface exported below.
    pipeline: PipelineSource = .builtin,
};

pub const VkMemory = struct {
    properties: vk.PhysicalDeviceMemoryProperties,
    non_coherent_atom_size: vk.DeviceSize,
    /// vulkan memory directly read/writeable by host. Usually ram that is streamed on demand by gpu. Very limited amount
    host_vis: u32,
    /// gpu dedicated memory, or if gpu has none same as host_vis
    device_local: u32,
    /// Returns true for integrated GPUs etc. where gpu shares memory with main memory and it basically doesn't have its own  dedicated local mem
    pub inline fn sharedMem(self: @This()) bool {
        return self.host_vis == self.device_local;
    }

    pub fn init(mem_props: vk.PhysicalDeviceMemoryProperties, non_coherent_atom_size: vk.DeviceSize) ?VkMemory {
        const all_types = std.math.maxInt(u32);
        const host_vis_mem_type_index = findMemoryTypeIn(mem_props, all_types, .{ .host_visible_bit = true }, .{ .device_local_bit = true, .host_coherent_bit = true }) orelse
            findMemoryTypeIn(mem_props, all_types, .{ .host_visible_bit = true }, .{ .host_coherent_bit = true }) orelse return null;
        const device_local_mem_idx = findMemoryTypeIn(mem_props, all_types, .{ .device_local_bit = true }, .{}) orelse host_vis_mem_type_index;

        return .{
            .properties = mem_props,
            .non_coherent_atom_size = non_coherent_atom_size,
            .host_vis = host_vis_mem_type_index,
            .device_local = device_local_mem_idx,
        };
    }

    pub fn findMemoryType(self: VkMemory, type_bits: u32, required: vk.MemoryPropertyFlags, preferred: vk.MemoryPropertyFlags) ?u32 {
        return findMemoryTypeIn(self.properties, type_bits, required, preferred) orelse
            findMemoryTypeIn(self.properties, type_bits, required, .{});
    }

    fn findMemoryTypeIn(mem_props: vk.PhysicalDeviceMemoryProperties, type_bits: u32, required: vk.MemoryPropertyFlags, preferred: vk.MemoryPropertyFlags) ?u32 {
        for (mem_props.memory_types[0..mem_props.memory_type_count], 0..) |mem_type, i| {
            const bit = @as(u32, 1) << @intCast(i);
            if (type_bits & bit == 0) continue;
            if (!mem_type.property_flags.contains(required)) continue;
            if (!mem_type.property_flags.contains(preferred)) continue;
            return @intCast(i);
        }
        return null;
    }
};

/// just simple debug and informative metrics
pub const Stats = struct {
    // per frame
    draw_calls: u32 = 0,
    verts: u32 = 0,
    indices: u32 = 0,
    // global
    textures_alive: u16 = 0, // including render targets
    textures_mem: u64 = 0,
};

/// Read-only renderer metrics suitable for application debug UIs.
pub const StatsSnapshot = struct {
    draw_calls: u32 = 0,
    vertices: u32 = 0,
    vertex_capacity: usize = 0,
    indices: u32 = 0,
    index_capacity: usize = 0,
    textures_alive: u16 = 0,
    texture_memory: u64 = 0,
    stream_memory_used: usize = 0,
    stream_memory_per_frame: usize = 0,
    stream_memory_total: usize = 0,
};

// not owned by us:
dev: DeviceProxy,
vk_alloc: ?*vk.AllocationCallbacks,
cmdbuf: vk.CommandBuffer = .null_handle,
frame_active: bool = false,
dpool: vk.DescriptorPool,
submit_prepass: ?CommandSubmission,
submit_readback: ?CommandSubmission,

// owned by us
allocator: std.mem.Allocator,
samplers: [10]vk.Sampler,
frames: []FrameData,
textures: []Texture,
destroy_textures_offset: TextureIdx = 0,
destroy_textures: []TextureIdx,
pending_uploads: std.ArrayListUnmanaged(PendingUpload) = .empty,
pipeline: vk.Pipeline,
pipeline_layout: vk.PipelineLayout,
owns_pipeline_resources: bool,
dset_layout: vk.DescriptorSetLayout,
current_frame: *FrameData, // points somewhere in frames

/// if set render to render texture instead of default cmdbuf
active_render_target: ?ActiveRenderTarget = null,
offscreen_rendering: OffscreenRendering,
render_target_pipeline: vk.Pipeline,

dummy_texture: Texture = .{}, // dummy/null white texture
error_texture: Texture = .{},

host_vis_mem_idx: u32,
host_vis_mem: vk.DeviceMemory,
host_vis_coherent: bool,
host_vis_data: []u8, // mapped host_vis_mem
device_local_mem_idx: u32,
gpu_allocator: GpuAllocator,

framebuffer_size: vk.Extent2D = .{ .width = 0, .height = 0 },
vtx_overflow_logged: bool = false,
idx_overflow_logged: bool = false,
// just for info / dbg
stats: Stats = .{},

const ActiveRenderTarget = struct {
    command_buffer: vk.CommandBuffer,
    texture: *Texture,
    extent: vk.Extent2D,
};

const OffscreenRendering = union(enum) {
    dynamic,
    render_passes: struct {
        clear: vk.RenderPass,
        load: vk.RenderPass,
    },
};

pub inline fn dynamicRendering(s: Self) bool {
    return s.offscreen_rendering == .dynamic;
}

const FrameData = struct {
    // buffers to host_vis memory
    vtx_buff: vk.Buffer = .null_handle,
    vtx_resource: ?BufferAllocation = null,
    vtx_data: []u8 = &.{},
    vtx_offset: u32 = 0,
    idx_buff: vk.Buffer = .null_handle,
    idx_resource: ?BufferAllocation = null,
    idx_data: []u8 = &.{},
    idx_offset: u32 = 0,
    vtx_mem_offset: vk.DeviceSize = 0,
    idx_mem_offset: vk.DeviceSize = 0,
    vtx_dirty_start: vk.DeviceSize = std.math.maxInt(vk.DeviceSize),
    vtx_dirty_end: vk.DeviceSize = 0,
    idx_dirty_start: vk.DeviceSize = std.math.maxInt(vk.DeviceSize),
    idx_dirty_end: vk.DeviceSize = 0,
    prepass_pool: vk.CommandPool = .null_handle,
    prepass_cmd: vk.CommandBuffer = .null_handle,
    prepass_used: bool = false,
    prepass_finalized: bool = false,
    prepass_delivered: bool = false,
    staging: std.ArrayListUnmanaged(AllocatedBuffer) = .empty,
    /// textures to be destroyed after frames cycle through
    /// offset & len points to backend.destroy_textures[]
    destroy_textures_offset: u16 = 0,
    destroy_textures_len: u16 = 0,

    fn deinit(f: *@This(), b: *Backend) void {
        f.freeTextures(b);
        f.freeStaging(b);
        f.staging.deinit(b.allocator);
        b.destroyStreamBuffer(f.vtx_buff, f.vtx_resource);
        b.destroyStreamBuffer(f.idx_buff, f.idx_resource);
        b.dev.destroyCommandPool(f.prepass_pool, b.vk_alloc);
    }

    fn reset(f: *@This(), b: *Backend) !void {
        f.freeStaging(b);
        f.vtx_offset = 0;
        f.idx_offset = 0;
        f.vtx_dirty_start = std.math.maxInt(vk.DeviceSize);
        f.vtx_dirty_end = 0;
        f.idx_dirty_start = std.math.maxInt(vk.DeviceSize);
        f.idx_dirty_end = 0;
        f.destroy_textures_offset = b.destroy_textures_offset;
        f.destroy_textures_len = 0;
        f.prepass_used = false;
        f.prepass_finalized = false;
        f.prepass_delivered = false;
        try b.dev.resetCommandPool(f.prepass_pool, .{});
        try b.dev.beginCommandBuffer(f.prepass_cmd, &.{ .flags = .{ .one_time_submit_bit = true } });
    }

    fn freeStaging(f: *@This(), b: *Backend) void {
        for (f.staging.items) |staging| {
            b.destroyAllocatedBuffer(staging);
        }
        f.staging.clearRetainingCapacity();
    }

    fn freeTextures(f: *@This(), b: *Backend) void {
        // free textures
        const first: usize = f.destroy_textures_offset;
        const last: usize = first + @as(usize, f.destroy_textures_len);
        for (first..last) |i| {
            const tidx = b.destroy_textures[i % b.destroy_textures.len]; // wrap around on overflow
            // just for debug and monitoring
            b.stats.textures_alive -= 1;
            b.stats.textures_mem -= b.textures[@intCast(tidx)].allocation_size;

            //slog.debug("destroy texture {}({x}) | {}", .{ tidx, @intFromPtr(&b.textures[tidx]), b.stats.textures_alive });
            b.textures[tidx].deinit(b);
            b.textures[tidx].img = .null_handle;
            b.textures[tidx].dset = .null_handle;
            b.textures[tidx].img_view = .null_handle;
            b.textures[tidx].mem = .null_handle;
            b.textures[tidx].trace.addAddr(@returnAddress(), "destroy"); // keep tracing
        }
        f.destroy_textures_len = 0;
    }
};

fn samplerSlot(interpolation: dvui.enums.TextureInterpolation, wrap_u: dvui.enums.TextureWrap, wrap_v: dvui.enums.TextureWrap) usize {
    const interpolation_index: usize = switch (interpolation) {
        .nearest => 0,
        .linear => 1,
    };
    const wrap_u_index: usize = switch (wrap_u) {
        .clamp => 0,
        .repeat => 1,
    };
    const wrap_v_index: usize = switch (wrap_v) {
        .clamp => 0,
        .repeat => 1,
    };
    return interpolation_index * 4 + wrap_u_index * 2 + wrap_v_index;
}

fn samplerCreateInfo(interpolation: dvui.enums.TextureInterpolation, wrap_u: vk.SamplerAddressMode, wrap_v: vk.SamplerAddressMode) vk.SamplerCreateInfo {
    const filter: vk.Filter = if (interpolation == .nearest) .nearest else .linear;
    const mipmap_mode: vk.SamplerMipmapMode = if (interpolation == .nearest) .nearest else .linear;
    return .{
        .mag_filter = filter,
        .min_filter = filter,
        .mipmap_mode = mipmap_mode,
        .address_mode_u = wrap_u,
        .address_mode_v = wrap_v,
        .address_mode_w = .clamp_to_edge,
        .mip_lod_bias = 0,
        .anisotropy_enable = .false,
        .max_anisotropy = 0,
        .compare_enable = .false,
        .compare_op = .always,
        .min_lod = 0,
        .max_lod = vk.LOD_CLAMP_NONE,
        .border_color = .int_opaque_white,
        .unnormalized_coordinates = .false,
    };
}

pub fn init(alloc: std.mem.Allocator, opt: InitOptions) !Self {
    if (opt.max_frames_in_flight == 0 or opt.max_textures == 0 or opt.max_vertices_per_frame == 0 or opt.max_indices_per_frame == 0)
        return error.InvalidOptions;
    const dev = opt.dev;
    const dynamic_rendering = std.meta.activeTag(opt.render_pass) == .dynamic;
    const builtin_memory: ?VkMemory = switch (opt.gpu_allocator) {
        .builtin => |memory| memory,
        .custom => null,
    };
    // Create the streaming buffers first so allocation size, alignment, and the
    // compatible memory-type intersection come from Vulkan rather than guesses.
    const frames = try alloc.alloc(FrameData, opt.max_frames_in_flight);
    @memset(frames, FrameData{});
    var host_visible_mem: vk.DeviceMemory = .null_handle;
    var host_vis_data: []u8 = &.{};
    var host_vis_mem_idx: u32 = if (builtin_memory) |memory| memory.host_vis else std.math.maxInt(u32);
    var host_vis_coherent = true;
    var host_memory_mapped = false;
    errdefer {
        for (frames) |f| {
            switch (opt.gpu_allocator) {
                .builtin => {
                    if (f.vtx_buff != .null_handle) dev.destroyBuffer(f.vtx_buff, opt.vk_alloc);
                    if (f.idx_buff != .null_handle) dev.destroyBuffer(f.idx_buff, opt.vk_alloc);
                },
                .custom => |custom| {
                    if (f.vtx_resource) |resource| custom.destroy_buffer(custom.userdata, dev, resource);
                    if (f.idx_resource) |resource| custom.destroy_buffer(custom.userdata, dev, resource);
                },
            }
            if (f.prepass_pool != .null_handle) dev.destroyCommandPool(f.prepass_pool, opt.vk_alloc);
        }
        if (host_memory_mapped) dev.unmapMemory(host_visible_mem);
        if (host_visible_mem != .null_handle) dev.freeMemory(host_visible_mem, opt.vk_alloc);
        alloc.free(frames);
    }
    var host_memory_type_bits: u32 = std.math.maxInt(u32);
    var host_visible_size: vk.DeviceSize = 0;
    for (frames) |*f| {
        const vtx_info = vk.BufferCreateInfo{
            .size = try std.math.mul(vk.DeviceSize, @sizeOf(Vertex), opt.max_vertices_per_frame),
            .usage = .{ .vertex_buffer_bit = true },
            .sharing_mode = .exclusive,
        };
        const idx_info = vk.BufferCreateInfo{
            .size = try std.math.mul(vk.DeviceSize, @sizeOf(Index), opt.max_indices_per_frame),
            .usage = .{ .index_buffer_bit = true },
            .sharing_mode = .exclusive,
        };
        switch (opt.gpu_allocator) {
            .builtin => {
                f.vtx_buff = try dev.createBuffer(&vtx_info, opt.vk_alloc);
                const vtx_req = dev.getBufferMemoryRequirements(f.vtx_buff);
                host_memory_type_bits &= vtx_req.memory_type_bits;
                host_visible_size = std.mem.alignForward(vk.DeviceSize, host_visible_size, vtx_req.alignment);
                f.vtx_mem_offset = host_visible_size;
                host_visible_size = try std.math.add(vk.DeviceSize, host_visible_size, vtx_req.size);

                f.idx_buff = try dev.createBuffer(&idx_info, opt.vk_alloc);
                const idx_req = dev.getBufferMemoryRequirements(f.idx_buff);
                host_memory_type_bits &= idx_req.memory_type_bits;
                host_visible_size = std.mem.alignForward(vk.DeviceSize, host_visible_size, idx_req.alignment);
                f.idx_mem_offset = host_visible_size;
                host_visible_size = try std.math.add(vk.DeviceSize, host_visible_size, idx_req.size);
            },
            .custom => |custom| {
                const vtx = try custom.create_buffer(custom.userdata, dev, &vtx_info, .streaming);
                if (vtx.handle == .null_handle or vtx.size < vtx_info.size) {
                    custom.destroy_buffer(custom.userdata, dev, vtx);
                    return error.InvalidResourceAllocation;
                }
                f.vtx_resource = vtx;
                f.vtx_buff = vtx.handle;
                f.vtx_data = vtx.mapped.mappedPtr()[0..@intCast(vtx_info.size)];

                const idx = try custom.create_buffer(custom.userdata, dev, &idx_info, .streaming);
                if (idx.handle == .null_handle or idx.size < idx_info.size) {
                    custom.destroy_buffer(custom.userdata, dev, idx);
                    return error.InvalidResourceAllocation;
                }
                f.idx_resource = idx;
                f.idx_buff = idx.handle;
                f.idx_data = idx.mapped.mappedPtr()[0..@intCast(idx_info.size)];
            },
        }

        f.prepass_pool = try dev.createCommandPool(&.{
            .flags = .{ .reset_command_buffer_bit = true, .transient_bit = true },
            .queue_family_index = opt.graphics_queue_family_index,
        }, opt.vk_alloc);
        try dev.allocateCommandBuffers(&.{
            .command_pool = f.prepass_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&f.prepass_cmd));
    }

    if (std.meta.activeTag(opt.gpu_allocator) == .builtin) {
        const memory = builtin_memory.?;
        host_vis_mem_idx = memory.findMemoryType(
            host_memory_type_bits,
            .{ .host_visible_bit = true },
            .{ .device_local_bit = true, .host_coherent_bit = true },
        ) orelse memory.findMemoryType(host_memory_type_bits, .{ .host_visible_bit = true }, .{ .host_coherent_bit = true }) orelse
            return error.NoCompatibleMemoryType;
        host_vis_coherent = memory.properties.memory_types[host_vis_mem_idx].property_flags.host_coherent_bit;
        slog.debug("host visible allocation size: {Bi}, memory type: {}", .{ host_visible_size, host_vis_mem_idx });
        host_visible_mem = try dev.allocateMemory(&.{
            .allocation_size = host_visible_size,
            .memory_type_index = host_vis_mem_idx,
        }, opt.vk_alloc);
        const mapped = (try dev.mapMemory(host_visible_mem, 0, vk.WHOLE_SIZE, .{})) orelse return error.MapMemoryFailed;
        host_memory_mapped = true;
        host_vis_data = @as([*]u8, @ptrCast(mapped))[0..@intCast(host_visible_size)];

        for (frames) |*f| {
            const vtx_req = dev.getBufferMemoryRequirements(f.vtx_buff);
            try dev.bindBufferMemory(f.vtx_buff, host_visible_mem, f.vtx_mem_offset);
            f.vtx_data = host_vis_data[@intCast(f.vtx_mem_offset)..][0..@intCast(vtx_req.size)];

            const idx_req = dev.getBufferMemoryRequirements(f.idx_buff);
            try dev.bindBufferMemory(f.idx_buff, host_visible_mem, f.idx_mem_offset);
            f.idx_data = host_vis_data[@intCast(f.idx_mem_offset)..][0..@intCast(idx_req.size)];
        }
    }

    // Descriptors
    const extra: u32 = 8; // idk, exact pool sizes returns OutOfPoolMemory slightly too soon, add extra margin
    const dpool_sizes = [_]vk.DescriptorPoolSize{
        .{ .type = .combined_image_sampler, .descriptor_count = opt.max_textures + extra },
        //.{ .type = .uniform_buffer, .descriptor_count = opt.max_frames_in_flight },
    };
    const dpool = try dev.createDescriptorPool(&.{
        .max_sets = opt.max_textures + extra,
        .pool_size_count = dpool_sizes.len,
        .p_pool_sizes = &dpool_sizes,
        .flags = .{ .free_descriptor_set_bit = true },
    }, opt.vk_alloc);
    errdefer dev.destroyDescriptorPool(dpool, opt.vk_alloc);
    const dsl = try dev.createDescriptorSetLayout(
        &vk.DescriptorSetLayoutCreateInfo{
            .binding_count = 1,
            .p_bindings = &.{
                // vk.DescriptorSetLayoutBinding{
                //     .binding = ubo_binding,
                //     .descriptor_count = 1,
                //     .descriptor_type = .uniform_buffer,
                //     .stage_flags = .{ .vertex_bit = true },
                // },
                texture_descriptor_binding,
            },
        },
        opt.vk_alloc,
    );
    errdefer dev.destroyDescriptorSetLayout(dsl, opt.vk_alloc);
    const pipeline_layout = switch (opt.pipeline) {
        .builtin => try dev.createPipelineLayout(&.{
            .flags = .{},
            .set_layout_count = 1,
            .p_set_layouts = @ptrCast(&dsl),
            .push_constant_range_count = 1,
            .p_push_constant_ranges = &.{push_constant_range},
        }, opt.vk_alloc),
        .borrowed, .transferred => |handles| handles.pipeline_layout,
    };
    const owns_pipeline_resources = switch (opt.pipeline) {
        .builtin => true,
        .borrowed => false,
        .transferred => true,
    };
    errdefer if (owns_pipeline_resources) dev.destroyPipelineLayout(pipeline_layout, opt.vk_alloc);

    const render_target_pass = if (dynamic_rendering) .null_handle else try createOffscreenRenderPass(dev, img_format, .clear, opt.vk_alloc);
    errdefer if (render_target_pass != .null_handle) dev.destroyRenderPass(render_target_pass, opt.vk_alloc);
    const render_target_load_pass = if (dynamic_rendering) .null_handle else try createOffscreenRenderPass(dev, img_format, .load, opt.vk_alloc);
    errdefer if (render_target_load_pass != .null_handle) dev.destroyRenderPass(render_target_load_pass, opt.vk_alloc);
    const offscreen_rendering: OffscreenRendering = if (dynamic_rendering)
        .dynamic
    else
        .{ .render_passes = .{ .clear = render_target_pass, .load = render_target_load_pass } };

    const pipeline = switch (opt.pipeline) {
        .builtin => try createPipeline(dev, pipeline_layout, switch (opt.render_pass) {
            .static => |target| target.render_pass,
            .dynamic => .null_handle,
        }, switch (opt.render_pass) {
            .static => null,
            .dynamic => |target| target.info,
        }, switch (opt.render_pass) {
            .static => |target| target.subpass,
            .dynamic => 0,
        }, switch (opt.render_pass) {
            .static => |target| target.samples,
            .dynamic => |target| target.samples,
        }, opt.vk_alloc),
        .borrowed, .transferred => |handles| handles.pipeline,
    };
    errdefer if (owns_pipeline_resources) dev.destroyPipeline(pipeline, opt.vk_alloc);

    const render_target_pipeline = try createPipeline(dev, pipeline_layout, render_target_pass, if (render_target_pass == .null_handle) vk.PipelineRenderingCreateInfo{
        .color_attachment_count = 1,
        .view_mask = 0,
        .p_color_attachment_formats = &[_]vk.Format{img_format},
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
    } else null, 0, .{ .@"1_bit" = true }, opt.vk_alloc);
    errdefer dev.destroyPipeline(render_target_pipeline, opt.vk_alloc);

    var samplers: [10]vk.Sampler = @splat(.null_handle);
    var sampler_count: usize = 0;
    errdefer for (samplers[0..sampler_count]) |sampler| dev.destroySampler(sampler, opt.vk_alloc);
    for (0..8) |i| {
        const interpolation: dvui.enums.TextureInterpolation = if (i / 4 == 0) .nearest else .linear;
        const wrap_u: vk.SamplerAddressMode = if ((i / 2) % 2 == 0) .clamp_to_edge else .repeat;
        const wrap_v: vk.SamplerAddressMode = if (i % 2 == 0) .clamp_to_edge else .repeat;
        samplers[i] = try dev.createSampler(&samplerCreateInfo(interpolation, wrap_u, wrap_v), opt.vk_alloc);
        sampler_count += 1;
    }
    for (samplers[8..], 0..) |*sampler, i| {
        const interpolation: dvui.enums.TextureInterpolation = if (i == 0) .nearest else .linear;
        sampler.* = try dev.createSampler(&samplerCreateInfo(interpolation, opt.texture_wrap, opt.texture_wrap), opt.vk_alloc);
        sampler_count += 1;
    }

    const textures = try alloc.alloc(Texture, opt.max_textures);
    errdefer alloc.free(textures);
    @memset(textures, Texture{});
    const destroy_textures = try alloc.alloc(u16, opt.max_textures);
    errdefer alloc.free(destroy_textures);

    var res: Self = .{
        .allocator = alloc,
        .dev = dev,
        .dpool = dpool,
        .vk_alloc = opt.vk_alloc,

        .dset_layout = dsl,
        .samplers = samplers,
        .textures = textures,
        .destroy_textures = destroy_textures,
        .offscreen_rendering = offscreen_rendering,
        .render_target_pipeline = render_target_pipeline,
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
        .owns_pipeline_resources = owns_pipeline_resources,
        .host_vis_mem_idx = host_vis_mem_idx,
        .host_vis_mem = host_visible_mem,
        .host_vis_data = host_vis_data,
        .host_vis_coherent = host_vis_coherent,
        .device_local_mem_idx = if (builtin_memory) |memory| memory.device_local else std.math.maxInt(u32),
        .gpu_allocator = opt.gpu_allocator,
        .submit_prepass = opt.submit_prepass,
        .submit_readback = opt.submit_readback,
        .frames = frames,
        .current_frame = &frames[0],
    };
    res.dummy_texture = try res.createAndUploadTexture(&[4]u8{ 255, 255, 255, 255 }, 1, 1, .nearest);
    res.error_texture = res.createAndUploadTexture(&opt.error_texture_color, 1, 1, .nearest) catch |err| {
        for (res.pending_uploads.items) |upload| res.destroyAllocatedBuffer(upload.staging);
        res.pending_uploads.deinit(alloc);
        res.dummy_texture.deinit(&res);
        return err;
    };
    return res;
}

/// The caller must ensure all GPU work using this renderer has completed.
pub fn deinit(self: *Self) void {
    const alloc = self.allocator;
    for (self.frames) |*f| f.deinit(self);
    alloc.free(self.frames);
    for (self.textures, 0..) |tex, i| if (!tex.isNull()) {
        slog.debug("TEXTURE LEAKED {}:\n", .{i});
        tex.trace.dump();
        tex.deinit(self);
    };
    alloc.free(self.textures);
    alloc.free(self.destroy_textures);
    for (self.pending_uploads.items) |upload| {
        self.destroyAllocatedBuffer(upload.staging);
    }
    self.pending_uploads.deinit(alloc);

    self.dummy_texture.deinit(self);
    self.error_texture.deinit(self);
    for (self.samplers) |s| self.dev.destroySampler(s, self.vk_alloc);

    self.dev.destroyPipeline(self.render_target_pipeline, self.vk_alloc);
    if (self.owns_pipeline_resources) {
        self.dev.destroyPipeline(self.pipeline, self.vk_alloc);
        self.dev.destroyPipelineLayout(self.pipeline_layout, self.vk_alloc);
    }
    self.dev.destroyDescriptorPool(self.dpool, self.vk_alloc);
    self.dev.destroyDescriptorSetLayout(self.dset_layout, self.vk_alloc);
    switch (self.offscreen_rendering) {
        .dynamic => {},
        .render_passes => |passes| {
            self.dev.destroyRenderPass(passes.load, self.vk_alloc);
            self.dev.destroyRenderPass(passes.clear, self.vk_alloc);
        },
    }
    if (self.host_vis_mem != .null_handle) {
        self.dev.unmapMemory(self.host_vis_mem);
        self.dev.freeMemory(self.host_vis_mem, self.vk_alloc);
    }
    // self.dev.destroyRenderPass(self.render_pass_texture_target, self.vk_alloc);
}

pub const RenderPassInfo = struct {
    framebuffer: vk.Framebuffer,
    render_area: vk.Rect2D,
};

/// Begins a new frame. `cmdbuf` must be inside a compatible render pass or dynamic
/// rendering instance when DVUI records screen draws.
///
/// Before the Nth subsequent call (where N is `max_frames_in_flight`), the caller
/// must ensure that GPU work recorded by this call has completed.
pub fn beginFrame(self: *Self, cmdbuf: vk.CommandBuffer, framebuffer_size: vk.Extent2D) !void {
    if (self.frame_active) return error.FrameAlreadyActive;
    self.cmdbuf = cmdbuf;
    self.framebuffer_size = framebuffer_size;

    // advance frame pointer,
    const current_frame_idx = (@intFromPtr(self.current_frame) - @intFromPtr(self.frames.ptr) + @sizeOf(FrameData)) / @sizeOf(FrameData) % self.frames.len;
    const cf = &self.frames[current_frame_idx];
    self.current_frame = cf;

    // clean up old frame data
    cf.freeTextures(self);

    // reset frame data
    try self.current_frame.reset(self);
    self.frame_active = true;
    errdefer self.frame_active = false;
    try self.recordPendingUploads();
    self.stats.draw_calls = 0;
    self.stats.indices = 0;
    self.stats.verts = 0;
    self.vtx_overflow_logged = false;
    self.idx_overflow_logged = false;
}

pub const RecordedFrame = struct {
    /// Submit before `main`. Null when no prepass was needed or `submit_prepass`
    /// already submitted it.
    prepass: ?vk.CommandBuffer,
    /// The same application-owned command buffer passed to `beginFrame`.
    main: vk.CommandBuffer,
};

pub fn statsSnapshot(self: *const Self) StatsSnapshot {
    const frame = self.current_frame;
    var stream_memory_total: usize = 0;
    for (self.frames) |item| stream_memory_total += item.vtx_data.len + item.idx_data.len;
    return .{
        .draw_calls = self.stats.draw_calls,
        .vertices = self.stats.verts,
        .vertex_capacity = frame.vtx_data.len / @sizeOf(Vertex),
        .indices = self.stats.indices,
        .index_capacity = frame.idx_data.len / @sizeOf(Index),
        .textures_alive = self.stats.textures_alive,
        .texture_memory = self.stats.textures_mem,
        .stream_memory_used = self.stats.verts * @sizeOf(Vertex) + self.stats.indices * @sizeOf(Index),
        .stream_memory_per_frame = frame.vtx_data.len + frame.idx_data.len,
        .stream_memory_total = stream_memory_total,
    };
}

/// Finalizes renderer recording for the current frame. Applications which do
/// not configure `submit_prepass` must submit the returned prepass, when non-null,
/// before the main command buffer and include both in the same frame-completion
/// synchronization scope.
pub fn endFrame(self: *Self) !RecordedFrame {
    const prepass = try self.finishPrepass();
    if (prepass != null and self.submit_prepass != null) try self.submitConfiguredPrepass(prepass.?);

    const result: RecordedFrame = .{
        .prepass = if (prepass != null and !self.current_frame.prepass_delivered) prepass else null,
        .main = self.cmdbuf,
    };
    if (result.prepass != null) self.current_frame.prepass_delivered = true;
    self.frame_active = false;
    self.cmdbuf = .null_handle;
    return result;
}

//
// Dvui backend interface matching functions
//  see: dvui/Backend.zig
//
const Backend = Self;

pub fn begin(self: *Self, arena: std.mem.Allocator, framebuffer_size: dvui.Size.Physical) void {
    _ = arena; // autofix
    self.active_render_target = null;
    if (self.cmdbuf == .null_handle) @panic("dvui_vulkan_renderer: Command bufer not set! (missing beginFrame()?)");

    const dev = self.dev;
    const cmdbuf = self.cmdbuf;
    dev.cmdBindPipeline(cmdbuf, .graphics, self.pipeline);

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = framebuffer_size.w,
        .height = framebuffer_size.h,
        .min_depth = 0,
        .max_depth = 1,
    };
    dev.cmdSetViewport(cmdbuf, 0, &.{viewport});

    const push_constants = PushConstants{
        .view_scale = .{ 2.0 / framebuffer_size.w, 2.0 / framebuffer_size.h },
        .view_translate = .{ -1.0, -1.0 },
    };
    dev.cmdPushConstants(cmdbuf, self.pipeline_layout, .{ .vertex_bit = true }, 0, @sizeOf(PushConstants), &push_constants);
}

pub fn end(self: *Backend) void {
    defer self.frame_active = false;
    const prepass = self.finishPrepass() catch |err| {
        slog.err("failed to finalize renderer prepass: {}", .{err});
        return;
    };
    if (prepass) |cmdbuf| self.submitConfiguredPrepass(cmdbuf) catch |err| {
        slog.err("failed to submit renderer prepass: {}", .{err});
    };
}

fn finishPrepass(self: *Self) !?vk.CommandBuffer {
    self.finishOffscreenTarget(true);
    self.flushFrameWrites();

    const frame = self.current_frame;
    if (!frame.prepass_finalized) {
        try self.dev.endCommandBuffer(frame.prepass_cmd);
        frame.prepass_finalized = true;
    }
    return if (frame.prepass_used) frame.prepass_cmd else null;
}

/// Starts a fresh prepass segment after the current segment was submitted and
/// completed synchronously. Unlike `FrameData.reset`, this preserves draw
/// offsets and deferred texture destruction belonging to the active frame.
fn restartCompletedPrepass(self: *Self) !void {
    const frame = self.current_frame;
    frame.freeStaging(self);
    try self.dev.resetCommandPool(frame.prepass_pool, .{});
    try self.dev.beginCommandBuffer(frame.prepass_cmd, &.{ .flags = .{ .one_time_submit_bit = true } });
    frame.prepass_used = false;
    frame.prepass_finalized = false;
    frame.prepass_delivered = false;
}

fn submitConfiguredPrepass(self: *Self, cmdbuf: vk.CommandBuffer) !void {
    const frame = self.current_frame;
    if (frame.prepass_delivered) return;
    const submit = self.submit_prepass orelse return;
    try submit.submit(submit.userdata, cmdbuf);
    frame.prepass_delivered = true;
}

fn flushFrameWrites(self: *Self) void {
    const frame = self.current_frame;
    switch (self.gpu_allocator) {
        .builtin => {
            if (!self.host_vis_coherent) {
                self.flushBuiltinRange(frame.vtx_mem_offset, frame.vtx_dirty_start, frame.vtx_dirty_end);
                self.flushBuiltinRange(frame.idx_mem_offset, frame.idx_dirty_start, frame.idx_dirty_end);
            }
        },
        .custom => |custom| {
            self.flushCustomRange(custom, frame.vtx_resource.?, frame.vtx_dirty_start, frame.vtx_dirty_end);
            self.flushCustomRange(custom, frame.idx_resource.?, frame.idx_dirty_start, frame.idx_dirty_end);
        },
    }
    frame.vtx_dirty_start = std.math.maxInt(vk.DeviceSize);
    frame.vtx_dirty_end = 0;
    frame.idx_dirty_start = std.math.maxInt(vk.DeviceSize);
    frame.idx_dirty_end = 0;
}

fn flushBuiltinRange(self: *Self, base: vk.DeviceSize, dirty_start: vk.DeviceSize, dirty_end: vk.DeviceSize) void {
    if (dirty_start == std.math.maxInt(vk.DeviceSize)) return;
    const atom = self.gpu_allocator.builtin.non_coherent_atom_size;
    const allocation_size: vk.DeviceSize = @intCast(self.host_vis_data.len);
    const flush_start = std.mem.alignBackward(vk.DeviceSize, base + dirty_start, atom);
    const flush_end = @min(std.mem.alignForward(vk.DeviceSize, base + dirty_end, atom), allocation_size);
    self.dev.flushMappedMemoryRanges(&.{.{
        .memory = self.host_vis_mem,
        .offset = flush_start,
        .size = flush_end - flush_start,
    }}) catch |err| slog.err("flushMappedMemoryRanges: {}", .{err});
}

fn flushCustomRange(self: *Self, custom: ResourceAllocator, buffer: BufferAllocation, dirty_start: vk.DeviceSize, dirty_end: vk.DeviceSize) void {
    if (dirty_start == std.math.maxInt(vk.DeviceSize)) return;
    switch (buffer.mapped) {
        .coherent => {},
        .non_coherent => |memory| memory.flush(
            custom.userdata,
            self.dev,
            buffer.handle,
            buffer.allocation,
            dirty_start,
            dirty_end - dirty_start,
        ) catch |err| slog.err("custom GPU allocator failed to flush streaming buffer: {}", .{err}),
    }
}

pub fn pixelSize(self: *Backend) Size {
    return .{ .w = @floatFromInt(self.framebuffer_size.width), .h = @floatFromInt(self.framebuffer_size.height) };
}

pub fn drawClippedTriangles(self: *Backend, texture_: ?dvui.Texture, vtx: []const Vertex, idx: []const Index, clipr: ?dvui.Rect.Physical) void {
    const texture: ?*anyopaque = if (texture_) |t| @as(*anyopaque, @ptrCast(@alignCast(t.ptr))) else null;
    if (texture != null and texture.? != invalid_texture) {
        const tex: *Texture = @ptrCast(@alignCast(texture.?));
        self.ensureTargetInitialized(tex);
    }
    const dev = self.dev;
    const cmdbuf = if (self.active_render_target) |target| target.command_buffer else self.cmdbuf;
    const cf = self.current_frame;
    const vtx_bytes = vtx.len * @sizeOf(Vertex);
    const idx_bytes = idx.len * @sizeOf(Index);

    { // updates stats even if draw is skipped due to overflow
        self.stats.draw_calls += 1;
        self.stats.verts += @intCast(vtx.len);
        self.stats.indices += @intCast(idx.len);
    }

    if (cf.vtx_data[cf.vtx_offset..].len < vtx_bytes) {
        if (!self.vtx_overflow_logged) slog.warn("vertex buffer out of space", .{});
        self.vtx_overflow_logged = true;
        if (enable_breakpoints) @breakpoint();
        return;
    }
    if (cf.idx_data[cf.idx_offset..].len < idx_bytes) {
        // if only index buffer alone is out of bounds, we could just shrinking it... but meh
        if (!self.idx_overflow_logged) slog.warn("index buffer out of space", .{});
        self.idx_overflow_logged = true;
        if (enable_breakpoints) @breakpoint();
        return;
    }

    { // clip / scissor
        const active_extent = if (self.active_render_target) |target| target.extent else self.framebuffer_size;
        const scissor = if (clipr) |c| blk: {
            const max_x: f32 = @floatFromInt(active_extent.width);
            const max_y: f32 = @floatFromInt(active_extent.height);
            const x0 = std.math.clamp(c.x, 0, max_x);
            const y0 = std.math.clamp(c.y, 0, max_y);
            const x1 = std.math.clamp(c.x + @max(0, c.w), x0, max_x);
            const y1 = std.math.clamp(c.y + @max(0, c.h), y0, max_y);
            break :blk vk.Rect2D{
                .offset = .{ .x = @intFromFloat(x0), .y = @intFromFloat(y0) },
                .extent = .{ .width = @intFromFloat(x1 - x0), .height = @intFromFloat(y1 - y0) },
            };
        } else vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = active_extent,
        };
        dev.cmdSetScissor(cmdbuf, 0, &.{scissor});
    }

    const idx_offset: u32 = cf.idx_offset;
    const vtx_offset: u32 = cf.vtx_offset;
    { // upload indices & vertices
        { // indices
            const dirty_start = cf.idx_offset;
            const dst = cf.idx_data[cf.idx_offset..][0..idx_bytes];
            cf.idx_offset += @intCast(dst.len);
            cf.idx_dirty_start = @min(cf.idx_dirty_start, dirty_start);
            cf.idx_dirty_end = @max(cf.idx_dirty_end, cf.idx_offset);
            @memcpy(dst, std.mem.sliceAsBytes(idx));
        }
        { // vertices
            const dirty_start = cf.vtx_offset;
            const dst = cf.vtx_data[cf.vtx_offset..][0..vtx_bytes];
            cf.vtx_offset += @intCast(dst.len);
            cf.vtx_dirty_start = @min(cf.vtx_dirty_start, dirty_start);
            cf.vtx_dirty_end = @max(cf.vtx_dirty_end, cf.vtx_offset);
            @memcpy(dst, std.mem.sliceAsBytes(vtx));
        }
    }

    dev.cmdBindIndexBuffer(cmdbuf, cf.idx_buff, idx_offset, switch (Index) {
        u16 => .uint16,
        u32 => .uint32,
        else => @compileError("invalid vertex index type"),
    });
    dev.cmdBindVertexBuffers(cmdbuf, 0, &.{cf.vtx_buff}, &.{vtx_offset});
    const dset: vk.DescriptorSet = if (texture == null) self.dummy_texture.dset else blk: {
        if (texture.? == invalid_texture) break :blk self.error_texture.dset;
        const tex = @as(*Texture, @ptrCast(@alignCast(texture)));
        if (tex.trace.index < tex.trace.addrs.len / 2 + 1) tex.trace.addAddr(@returnAddress(), "render"); // if trace has some free room, trace this
        break :blk tex.dset;
    };
    dev.cmdBindDescriptorSets(
        cmdbuf,
        .graphics,
        self.pipeline_layout,
        0,
        &.{dset},
        null,
    );
    dev.cmdDrawIndexed(cmdbuf, @intCast(idx.len), 1, 0, 0, 0);
}

fn findEmptyTextureSlot(self: *Backend) ?TextureIdx {
    for (self.textures, 0..) |*out_tex, s| {
        if (out_tex.isNull()) return @intCast(s);
    }
    slog.err("textureCreate: Out of texture slots!", .{});
    return null;
}

pub fn textureCreate(self: *Backend, pixels: [*]const u8, options: dvui.Texture.CreateOptions) TextureError!dvui.Texture {
    if (options.format != .rgba_32) return error.TextureCreate;

    const slot = self.findEmptyTextureSlot() orelse return .{
        .ptr = invalid_texture,
        .width = 1,
        .height = 1,
        .format = .rgba_32,
        .interpolation = options.interpolation,
        .wrap_u = options.wrap_u,
        .wrap_v = options.wrap_v,
    };
    const out_tex: *Texture = &self.textures[slot];
    const tex = self.createAndUploadTextureWithSampler(pixels, options.width, options.height, samplerSlot(options.interpolation, options.wrap_u, options.wrap_v)) catch |err| {
        if (enable_breakpoints) @breakpoint();
        slog.err("Can't create texture: {}", .{err});
        return error.TextureCreate;
    };
    out_tex.* = tex;
    out_tex.trace.addAddr(@returnAddress(), "create");

    self.stats.textures_alive += 1;
    self.stats.textures_mem += out_tex.allocation_size;
    //slog.debug("textureCreate {} ({x}) | {}", .{ slot, @intFromPtr(out_tex), self.stats.textures_alive });
    return .{
        .ptr = @ptrCast(out_tex),
        .width = options.width,
        .height = options.height,
        .format = options.format,
        .interpolation = options.interpolation,
        .wrap_u = options.wrap_u,
        .wrap_v = options.wrap_v,
    };
}

pub fn textureCreateTarget(self: *Backend, options: dvui.Texture.CreateOptions) TextureError!dvui.TextureTarget {
    if (!self.frame_active) return error.BackendError;
    if (options.format != .rgba_32) return error.TextureCreate;
    const tex_slot = self.findEmptyTextureSlot() orelse return error.OutOfMemory;

    const dev = self.dev;
    var tex = self.createTextureWithSampler(.{
        .image_type = .@"2d",
        .format = img_format,
        .extent = .{ .width = options.width, .height = options.height, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{
            .color_attachment_bit = true,
            .sampled_bit = true,
            .transfer_src_bit = true,
        },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, samplerSlot(options.interpolation, options.wrap_u, options.wrap_v)) catch |err| {
        if (enable_breakpoints) @breakpoint();
        slog.err("textureCreateTarget failed to create framebuffer: {}", .{err});
        return error.BackendError;
    };
    errdefer tex.deinit(self);

    tex.framebuffer = if (self.dynamicRendering()) .null_handle else dev.createFramebuffer(&.{
        .flags = .{},
        .render_pass = self.offscreen_rendering.render_passes.clear,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&tex.img_view),
        .width = options.width,
        .height = options.height,
        .layers = 1,
    }, self.vk_alloc) catch |err| {
        if (enable_breakpoints) @breakpoint();
        slog.err("textureCreateTarget failed to create framebuffer: {}", .{err});
        return error.BackendError;
    };
    errdefer dev.destroyFramebuffer(tex.framebuffer, self.vk_alloc);

    tex.target_extent = .{ .width = options.width, .height = options.height };
    self.textures[tex_slot] = tex;
    self.stats.textures_alive += 1;
    self.stats.textures_mem += tex.allocation_size;
    return .{
        .ptr = &self.textures[tex_slot],
        .width = options.width,
        .height = options.height,
        .format = options.format,
        .interpolation = options.interpolation,
        .wrap_u = options.wrap_u,
        .wrap_v = options.wrap_v,
    };
}
pub fn textureRead(self: *Backend, texture: dvui.Texture, pixels_out: [*]u8, width: u32, height: u32) !void {
    slog.debug("textureRead({}, {*}, {}x{}) Not implemented!", .{ texture, pixels_out, width, height });
    _ = self; // autofix
    return error.NotImplemented;
}
pub fn textureDestroy(self: *Backend, texture: dvui.Texture) void {
    if (texture.ptr == invalid_texture) return;
    const dslot = self.destroy_textures_offset;
    self.destroy_textures_offset = (dslot + 1) % @as(u16, @intCast(self.destroy_textures.len));
    self.destroy_textures[dslot] = @intCast((@intFromPtr(texture.ptr) - @intFromPtr(self.textures.ptr)) / @sizeOf(Texture));
    self.current_frame.destroy_textures_len += 1;
    // slog.debug("schedule destroy texture: {} ({x})", .{ self.destroy_textures[dslot], @intFromPtr(texture) });
}

/// Read pixel data (RGBA) from `texture` into `pixels_out`.
pub fn textureReadTarget(self: *Backend, texture: dvui.TextureTarget, pixels_out: [*]u8) TextureError!void {
    if (!self.frame_active) return error.BackendError;
    const submit_readback = self.submit_readback orelse return error.NotImplemented;
    if (texture.ptr == invalid_texture) return error.TextureRead;

    const pixel_count = std.math.mul(usize, @as(usize, texture.width), @as(usize, texture.height)) catch return error.TextureRead;
    const byte_len = std.math.mul(usize, pixel_count, 4) catch return error.TextureRead;
    if (byte_len == 0) return error.TextureRead;
    const copy_size: vk.DeviceSize = @intCast(byte_len);

    const target: *Texture = @ptrCast(@alignCast(texture.ptr));
    const target_extent = target.target_extent orelse return error.TextureRead;
    if (target_extent.width != texture.width or target_extent.height != texture.height) return error.TextureRead;

    const previous_target = self.active_render_target;
    self.finishOffscreenTarget(false);
    var restore_on_error = true;
    errdefer if (restore_on_error and !self.current_frame.prepass_finalized) {
        if (previous_target) |previous| self.beginOffscreenTarget(previous.texture, previous.extent, .load);
    };

    // Reading an untouched target has the same transparent contents that
    // sampling it would establish through `ensureTargetInitialized`.
    if (target.layout == .undefined) {
        self.beginOffscreenTarget(target, target_extent, .clear);
        self.finishOffscreenTarget(false);
    }

    const readback = self.createReadbackBuffer(copy_size) catch |err| {
        slog.err("textureReadTarget failed to create readback buffer: {}", .{err});
        return error.TextureRead;
    };
    var readback_owned = true;
    errdefer if (readback_owned) self.destroyAllocatedBuffer(readback.allocation);

    // Once commands reference the buffer, keep it in the frame's staging list
    // so an unsuccessful submit/wait cannot free an in-use Vulkan resource.
    self.current_frame.staging.ensureUnusedCapacity(self.allocator, 1) catch return error.OutOfMemory;
    self.current_frame.staging.appendAssumeCapacity(readback.allocation);
    readback_owned = false;

    const dev = self.dev;
    const cmdbuf = self.current_frame.prepass_cmd;
    self.current_frame.prepass_used = true;

    const to_transfer = vk.ImageMemoryBarrier{
        // This target may have been written and transitioned to its tracked
        // layout earlier in the same prepass. Use a conservative source scope
        // because synchronous readback is not a performance-sensitive path.
        .src_access_mask = .{ .memory_read_bit = true, .memory_write_bit = true },
        .dst_access_mask = .{ .transfer_read_bit = true },
        .old_layout = target.layout,
        .new_layout = .transfer_src_optimal,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = target.img,
        .subresource_range = colorSubresourceRange(),
    };
    dev.cmdPipelineBarrier(cmdbuf, .{ .all_commands_bit = true }, .{ .transfer_bit = true }, .{}, null, null, &.{to_transfer});
    target.layout = .transfer_src_optimal;

    const copy = vk.BufferImageCopy{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{ .width = texture.width, .height = texture.height, .depth = 1 },
    };
    dev.cmdCopyImageToBuffer(cmdbuf, target.img, .transfer_src_optimal, readback.allocation.buf, &.{copy});

    const to_host = vk.BufferMemoryBarrier{
        .src_access_mask = .{ .transfer_write_bit = true },
        .dst_access_mask = .{ .host_read_bit = true },
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .buffer = readback.allocation.buf,
        .offset = 0,
        .size = copy_size,
    };
    const resume_read_target = previous_target != null and previous_target.?.texture == target;
    const final_layout: vk.ImageLayout = if (resume_read_target) .color_attachment_optimal else .shader_read_only_optimal;
    const after_copy = vk.ImageMemoryBarrier{
        .src_access_mask = .{ .transfer_read_bit = true },
        .dst_access_mask = if (resume_read_target)
            .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true }
        else
            .{ .shader_read_bit = true },
        .old_layout = .transfer_src_optimal,
        .new_layout = final_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = target.img,
        .subresource_range = colorSubresourceRange(),
    };
    dev.cmdPipelineBarrier(
        cmdbuf,
        .{ .transfer_bit = true },
        if (resume_read_target)
            .{ .host_bit = true, .color_attachment_output_bit = true }
        else
            .{ .host_bit = true, .fragment_shader_bit = true },
        .{},
        null,
        &.{to_host},
        &.{after_copy},
    );
    target.layout = final_layout;

    const prepass = self.finishPrepass() catch |err| {
        slog.err("textureReadTarget failed to finalize prepass: {}", .{err});
        return error.TextureRead;
    } orelse unreachable;
    // Do not let `endFrame` resubmit this command buffer if the callback fails
    // after handing it to the queue.
    self.current_frame.prepass_delivered = true;
    submit_readback.submit(submit_readback.userdata, prepass) catch |err| {
        slog.err("textureReadTarget synchronous submission failed: {}", .{err});
        return error.TextureRead;
    };

    var invalidate_error: ?anyerror = null;
    self.invalidateReadbackBuffer(readback) catch |err| {
        invalidate_error = err;
    };
    if (invalidate_error == null) {
        @memcpy(pixels_out[0..byte_len], readback.ptr[0..byte_len]);
    }

    self.restartCompletedPrepass() catch |err| {
        slog.err("textureReadTarget failed to restart prepass: {}", .{err});
        return error.BackendError;
    };
    if (previous_target) |previous| self.beginOffscreenTarget(previous.texture, previous.extent, .load);
    restore_on_error = false;

    if (invalidate_error) |err| {
        slog.err("textureReadTarget failed to invalidate readback memory: {}", .{err});
        return error.TextureRead;
    }
}

pub fn textureClearTarget(self: *Backend, target: dvui.TextureTarget) GenericError!void {
    if (!self.frame_active) return error.BackendError;
    const texture: *Texture = @ptrCast(@alignCast(target.ptr));
    self.finishOffscreenTarget(true);
    self.beginOffscreenTarget(texture, .{ .width = target.width, .height = target.height }, .clear);
    self.finishOffscreenTarget(true);
}

/// Convert texture target made with `textureCreateTarget` into return texture
/// as if made by `textureCreate`.  After this call, texture target will not be
/// used by dvui.
pub fn textureFromTarget(self: *Backend, texture_target: dvui.TextureTarget) dvui.Texture {
    _ = self; // autofix
    return dvui.Texture.cast(texture_target);
}

pub fn renderTarget(self: *Backend, dvui_texture_target: ?dvui.TextureTarget) GenericError!void {
    if (!self.frame_active) return error.BackendError;
    const requested_texture: ?*Texture = if (dvui_texture_target) |t| @ptrCast(@alignCast(t.ptr)) else null;
    if (requested_texture != null and self.active_render_target != null and requested_texture == self.active_render_target.?.texture) return;

    self.finishOffscreenTarget(true);

    const texture = requested_texture orelse return;
    const target = dvui_texture_target.?;
    const load_op: vk.AttachmentLoadOp = if (texture.layout == .undefined) .clear else .load;
    self.beginOffscreenTarget(texture, .{ .width = target.width, .height = target.height }, load_op);
}

fn ensureTargetInitialized(self: *Self, texture: *Texture) void {
    const extent = texture.target_extent orelse return;
    if (texture.layout != .undefined) return;

    const previous_target = self.active_render_target;
    self.finishOffscreenTarget(true);
    self.beginOffscreenTarget(texture, extent, .clear);
    self.finishOffscreenTarget(true);
    if (previous_target) |target| self.beginOffscreenTarget(target.texture, target.extent, .load);
}

fn finishOffscreenTarget(self: *Self, make_sampled: bool) void {
    const target = self.active_render_target orelse return;

    if (self.dynamicRendering()) self.dev.cmdEndRendering(target.command_buffer) else self.dev.cmdEndRenderPass(target.command_buffer);
    self.active_render_target = null;

    if (!make_sampled) return;
    const barrier = vk.ImageMemoryBarrier{
        .src_access_mask = .{ .color_attachment_write_bit = true },
        .dst_access_mask = .{ .shader_read_bit = true },
        .old_layout = .color_attachment_optimal,
        .new_layout = .shader_read_only_optimal,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = target.texture.img,
        .subresource_range = colorSubresourceRange(),
    };
    self.dev.cmdPipelineBarrier(target.command_buffer, .{ .color_attachment_output_bit = true }, .{ .fragment_shader_bit = true }, .{}, null, null, &.{barrier});
    target.texture.layout = .shader_read_only_optimal;
}

fn beginOffscreenTarget(self: *Self, texture: *Texture, extent: vk.Extent2D, load_op: vk.AttachmentLoadOp) void {
    std.debug.assert(self.active_render_target == null);
    const dev = self.dev;
    const cmdbuf = self.current_frame.prepass_cmd;
    self.current_frame.prepass_used = true;

    if (texture.layout != .color_attachment_optimal or load_op == .load) {
        const img_barrier = vk.ImageMemoryBarrier{
            .old_layout = texture.layout,
            .src_access_mask = if (texture.layout == .shader_read_only_optimal)
                .{ .shader_read_bit = true }
            else if (texture.layout == .color_attachment_optimal)
                .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true }
            else
                .{},
            .dst_access_mask = if (load_op == .load)
                .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true }
            else
                .{ .color_attachment_write_bit = true },
            .new_layout = .color_attachment_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = texture.img,
            .subresource_range = colorSubresourceRange(),
        };
        const src_stage: vk.PipelineStageFlags = if (texture.layout == .shader_read_only_optimal)
            .{ .fragment_shader_bit = true }
        else if (texture.layout == .color_attachment_optimal)
            .{ .color_attachment_output_bit = true }
        else
            .{ .top_of_pipe_bit = true };
        dev.cmdPipelineBarrier(cmdbuf, src_stage, .{ .color_attachment_output_bit = true }, .{}, null, null, &.{img_barrier});
    }
    texture.layout = .color_attachment_optimal;

    const w: f32 = @floatFromInt(extent.width);
    const h: f32 = @floatFromInt(extent.height);
    { // begin render-pass & reset viewport
        dev.cmdBindPipeline(cmdbuf, .graphics, self.render_target_pipeline);
        const clear = vk.ClearValue{
            .color = .{ .float_32 = .{ 0, 0, 0, 0 } },
        };
        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = w,
            .height = h,
            .min_depth = 0,
            .max_depth = 1,
        };

        if (texture.img_view == .null_handle) unreachable;
        if (self.dynamicRendering()) dev.cmdBeginRendering(cmdbuf, &.{
            .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
            .view_mask = 0,
            .layer_count = 1,
            .color_attachment_count = 1,
            .p_color_attachments = &[_]vk.RenderingAttachmentInfo{.{
                .image_view = texture.img_view,
                .image_layout = .color_attachment_optimal,
                .resolve_mode = .{},
                .resolve_image_view = .null_handle,
                .resolve_image_layout = .color_attachment_optimal,
                .load_op = load_op,
                .store_op = .store,
                .clear_value = .{ .color = .{ .float_32 = .{ 0, 0, 0, 0 } } },
            }},
            .p_depth_attachment = null,
        }) else dev.cmdBeginRenderPass(cmdbuf, &.{
            .render_pass = if (load_op == .clear)
                self.offscreen_rendering.render_passes.clear
            else
                self.offscreen_rendering.render_passes.load,
            .framebuffer = texture.framebuffer,
            .render_area = vk.Rect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = extent,
            },
            .clear_value_count = if (load_op == .clear) 1 else 0,
            .p_clear_values = if (load_op == .clear) @ptrCast(&clear) else null,
        }, .@"inline");
        dev.cmdSetViewport(cmdbuf, 0, &.{viewport});
    }

    const push_constants = PushConstants{
        .view_scale = .{ 2.0 / w, 2.0 / h },
        .view_translate = .{ -1.0, -1.0 },
    };
    dev.cmdPushConstants(cmdbuf, self.pipeline_layout, .{ .vertex_bit = true }, 0, @sizeOf(PushConstants), &push_constants);

    self.active_render_target = .{
        .command_buffer = cmdbuf,
        .texture = texture,
        .extent = extent,
    };
}

fn colorSubresourceRange() vk.ImageSubresourceRange {
    return .{
        .aspect_mask = .{ .color_bit = true },
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };
}

//
// Private functions
// Some can be pub just to allow using them as utils
//
const Texture = struct {
    img: vk.Image = .null_handle,
    img_view: vk.ImageView = .null_handle,
    mem: vk.DeviceMemory = .null_handle,
    custom_resource: ?ImageAllocation = null,
    allocation_size: vk.DeviceSize = 0,
    dset: vk.DescriptorSet = .null_handle,
    /// for render-textures only
    framebuffer: vk.Framebuffer = .null_handle,
    target_extent: ?vk.Extent2D = null,
    layout: vk.ImageLayout = .undefined,

    trace: Trace = Trace.init,
    const Trace = std.debug.ConfigurableTrace(6, 5, texture_tracing);

    pub fn isNull(self: @This()) bool {
        return self.dset == .null_handle;
    }

    pub fn deinit(tex: Texture, b: *Backend) void {
        if (tex.isNull()) return;
        const dev = b.dev;
        const vk_alloc = b.vk_alloc;
        dev.freeDescriptorSets(b.dpool, &.{tex.dset}) catch |err| slog.err("Failed to free descriptor set: {}", .{err});
        dev.destroyFramebuffer(tex.framebuffer, vk_alloc);
        dev.destroyImageView(tex.img_view, vk_alloc);
        if (tex.custom_resource) |resource| {
            const custom = b.gpu_allocator.custom;
            custom.destroy_image(custom.userdata, dev, resource);
        } else {
            dev.destroyImage(tex.img, vk_alloc);
            dev.freeMemory(tex.mem, vk_alloc);
        }
    }
};

fn createPipeline(
    dev: DeviceProxy,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
    dynamic_render_pass: ?vk.PipelineRenderingCreateInfo, // render_pass must be null
    subpass: u32,
    samples: vk.SampleCountFlags,
    vk_alloc: ?*vk.AllocationCallbacks,
) DeviceProxy.CreateGraphicsPipelinesError!vk.Pipeline {
    if (dynamic_render_pass != null and render_pass != .null_handle) unreachable;
    if (dynamic_render_pass == null and render_pass == .null_handle) unreachable;
    //  NOTE: VK_KHR_maintenance5 (which was promoted to vulkan 1.4) deprecates ShaderModules.
    // todo: check for extension and then enable
    const ext_m5 = false; // VK_KHR_maintenance5
    const vert_shdd = vk.ShaderModuleCreateInfo{
        .code_size = vs_spv.len,
        .p_code = @ptrCast(&vs_spv),
    };
    const frag_shdd = vk.ShaderModuleCreateInfo{
        .code_size = fs_spv.len,
        .p_code = @ptrCast(&fs_spv),
    };
    var pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .p_name = "main",
            .module = if (ext_m5) null else try dev.createShaderModule(&vert_shdd, vk_alloc),
            .p_next = if (ext_m5) &vert_shdd else null,
        },
        .{
            .stage = .{ .fragment_bit = true },
            //.module = frag,
            .p_name = "main",
            .module = if (ext_m5) null else try dev.createShaderModule(&frag_shdd, vk_alloc),
            .p_next = if (ext_m5) &frag_shdd else null,
        },
    };
    defer if (!ext_m5) for (pssci) |p| if (p.module != .null_handle) dev.destroyShaderModule(p.module, vk_alloc);

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = VertexBindings.binding_description.len,
        .p_vertex_binding_descriptions = &VertexBindings.binding_description,
        .vertex_attribute_description_count = VertexBindings.attribute_description.len,
        .p_vertex_attribute_descriptions = &VertexBindings.attribute_description,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
    };

    var viewport: vk.Viewport = undefined;
    var scissor: vk.Rect2D = undefined;
    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = @ptrCast(&viewport), // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = @ptrCast(&scissor), // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = false },
        .front_face = .clockwise,
        .depth_bias_enable = .false,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = samples,
        .sample_shading_enable = .false,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&premultiplied_alpha_blend),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = pssci.len,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = &.{
            .flags = .{},
            .depth_test_enable = .false,
            .depth_write_enable = .false,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = .false,
            .stencil_test_enable = .false,
            .front = std.mem.zeroes(vk.StencilOpState),
            .back = std.mem.zeroes(vk.StencilOpState),
            .min_depth_bounds = 0,
            .max_depth_bounds = 1,
        },
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = subpass,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
        .p_next = if (dynamic_render_pass) |s| &s else null,
    };

    const gpci_one = [_]vk.GraphicsPipelineCreateInfo{gpci};
    var pipeline_one: [1]vk.Pipeline = undefined;
    _ = try dev.createGraphicsPipelines(
        .null_handle,
        &gpci_one,
        vk_alloc,
        &pipeline_one,
    );
    return pipeline_one[0];
}

const AllocatedBuffer = struct {
    buf: vk.Buffer,
    mem: vk.DeviceMemory = .null_handle,
    custom_resource: ?BufferAllocation = null,
    builtin_mapped: bool = false,
};

const ReadbackBuffer = struct {
    allocation: AllocatedBuffer,
    ptr: [*]u8,
    size: vk.DeviceSize,
    builtin_coherent: bool = true,
};

const PendingUpload = struct {
    image: vk.Image,
    width: u32,
    height: u32,
    staging: AllocatedBuffer,
};

/// allocates space for staging, creates buffer, and copies content to it
fn stageToBuffer(
    self: *@This(),
    buf_info: vk.BufferCreateInfo,
    contents: []const u8,
) !AllocatedBuffer {
    if (std.meta.activeTag(self.gpu_allocator) == .custom) {
        const custom = self.gpu_allocator.custom;
        const resource = try custom.create_buffer(custom.userdata, self.dev, &buf_info, .upload);
        errdefer custom.destroy_buffer(custom.userdata, self.dev, resource);
        if (resource.handle == .null_handle or resource.size < buf_info.size)
            return error.InvalidResourceAllocation;
        @memcpy(resource.mapped.mappedPtr()[0..contents.len], contents);
        switch (resource.mapped) {
            .coherent => {},
            .non_coherent => |memory| try memory.flush(custom.userdata, self.dev, resource.handle, resource.allocation, 0, contents.len),
        }
        return .{ .buf = resource.handle, .custom_resource = resource };
    }

    const buf = self.dev.createBuffer(&buf_info, self.vk_alloc) catch |err| {
        slog.err("createBuffer: {}", .{err});
        return err;
    };
    errdefer self.dev.destroyBuffer(buf, self.vk_alloc);
    const mreq = self.dev.getBufferMemoryRequirements(buf);
    const memory = self.gpu_allocator.builtin;
    const memory_type_index = memory.findMemoryType(
        mreq.memory_type_bits,
        .{ .host_visible_bit = true },
        .{ .host_coherent_bit = true },
    ) orelse return error.NoCompatibleMemoryType;
    const mem = try self.dev.allocateMemory(&.{ .allocation_size = mreq.size, .memory_type_index = memory_type_index }, self.vk_alloc);
    errdefer self.dev.freeMemory(mem, self.vk_alloc);
    const mem_offset = 0;
    try self.dev.bindBufferMemory(buf, mem, mem_offset);
    const mapped = (try self.dev.mapMemory(mem, mem_offset, vk.WHOLE_SIZE, .{})) orelse return error.MapMemoryFailed;
    const data = @as([*]u8, @ptrCast(mapped))[0..@intCast(mreq.size)];
    @memcpy(data[0..contents.len], contents);
    defer self.dev.unmapMemory(mem);
    if (!memory.properties.memory_types[memory_type_index].property_flags.host_coherent_bit)
        try self.dev.flushMappedMemoryRanges(&.{.{ .memory = mem, .offset = mem_offset, .size = mreq.size }});
    return .{ .buf = buf, .mem = mem };
}

fn createReadbackBuffer(self: *Self, size: vk.DeviceSize) !ReadbackBuffer {
    const info = vk.BufferCreateInfo{
        .size = size,
        .usage = .{ .transfer_dst_bit = true },
        .sharing_mode = .exclusive,
    };

    if (std.meta.activeTag(self.gpu_allocator) == .custom) {
        const custom = self.gpu_allocator.custom;
        const resource = try custom.create_buffer(custom.userdata, self.dev, &info, .readback);
        errdefer custom.destroy_buffer(custom.userdata, self.dev, resource);
        if (resource.handle == .null_handle or resource.size < size)
            return error.InvalidResourceAllocation;
        return .{
            .allocation = .{ .buf = resource.handle, .custom_resource = resource },
            .ptr = resource.mapped.mappedPtr(),
            .size = size,
        };
    }

    const dev = self.dev;
    const buf = try dev.createBuffer(&info, self.vk_alloc);
    errdefer dev.destroyBuffer(buf, self.vk_alloc);
    const requirements = dev.getBufferMemoryRequirements(buf);
    const memory = self.gpu_allocator.builtin;
    const memory_type_index = VkMemory.findMemoryTypeIn(
        memory.properties,
        requirements.memory_type_bits,
        .{ .host_visible_bit = true },
        .{ .host_cached_bit = true, .host_coherent_bit = true },
    ) orelse VkMemory.findMemoryTypeIn(
        memory.properties,
        requirements.memory_type_bits,
        .{ .host_visible_bit = true },
        .{ .host_cached_bit = true },
    ) orelse memory.findMemoryType(
        requirements.memory_type_bits,
        .{ .host_visible_bit = true },
        .{ .host_coherent_bit = true },
    ) orelse return error.NoCompatibleMemoryType;
    const mem = try dev.allocateMemory(&.{
        .allocation_size = requirements.size,
        .memory_type_index = memory_type_index,
    }, self.vk_alloc);
    errdefer dev.freeMemory(mem, self.vk_alloc);
    try dev.bindBufferMemory(buf, mem, 0);
    const mapped = (try dev.mapMemory(mem, 0, vk.WHOLE_SIZE, .{})) orelse return error.MapMemoryFailed;
    const coherent = memory.properties.memory_types[memory_type_index].property_flags.host_coherent_bit;
    return .{
        .allocation = .{ .buf = buf, .mem = mem, .builtin_mapped = true },
        .ptr = @ptrCast(mapped),
        .size = size,
        .builtin_coherent = coherent,
    };
}

fn invalidateReadbackBuffer(self: *Self, readback: ReadbackBuffer) !void {
    if (readback.allocation.custom_resource) |resource| {
        switch (resource.mapped) {
            .coherent => {},
            .non_coherent => |mapped| {
                const invalidate = mapped.invalidate orelse return error.MissingInvalidateCallback;
                const custom = self.gpu_allocator.custom;
                try invalidate(custom.userdata, self.dev, resource.handle, resource.allocation, 0, readback.size);
            },
        }
    } else if (!readback.builtin_coherent) {
        try self.dev.invalidateMappedMemoryRanges(&.{.{
            .memory = readback.allocation.mem,
            .offset = 0,
            .size = vk.WHOLE_SIZE,
        }});
    }
}

fn destroyAllocatedBuffer(self: *Self, buffer: AllocatedBuffer) void {
    if (buffer.custom_resource) |resource| {
        const custom = self.gpu_allocator.custom;
        custom.destroy_buffer(custom.userdata, self.dev, resource);
    } else {
        if (buffer.builtin_mapped) self.dev.unmapMemory(buffer.mem);
        self.dev.destroyBuffer(buffer.buf, self.vk_alloc);
        self.dev.freeMemory(buffer.mem, self.vk_alloc);
    }
}

fn destroyStreamBuffer(self: *Self, buffer: vk.Buffer, resource: ?BufferAllocation) void {
    if (resource) |custom_resource| {
        const custom = self.gpu_allocator.custom;
        custom.destroy_buffer(custom.userdata, self.dev, custom_resource);
    } else {
        self.dev.destroyBuffer(buffer, self.vk_alloc);
    }
}

fn recordPendingUploads(self: *Self) !void {
    if (self.pending_uploads.items.len == 0) return;

    const previous_target = self.active_render_target;
    self.finishOffscreenTarget(false);

    const frame = self.current_frame;
    try frame.staging.ensureUnusedCapacity(self.allocator, self.pending_uploads.items.len);
    frame.prepass_used = true;
    const cmdbuf = frame.prepass_cmd;
    const dev = self.dev;

    for (self.pending_uploads.items) |upload| {
        const to_transfer = vk.ImageMemoryBarrier{
            .src_access_mask = .{},
            .dst_access_mask = .{ .transfer_write_bit = true },
            .old_layout = .undefined,
            .new_layout = .transfer_dst_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = upload.image,
            .subresource_range = colorSubresourceRange(),
        };
        dev.cmdPipelineBarrier(cmdbuf, .{ .top_of_pipe_bit = true }, .{ .transfer_bit = true }, .{}, null, null, &.{to_transfer});

        const copy = vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = .{ .width = upload.width, .height = upload.height, .depth = 1 },
        };
        dev.cmdCopyBufferToImage(cmdbuf, upload.staging.buf, upload.image, .transfer_dst_optimal, &.{copy});

        const to_sampled = vk.ImageMemoryBarrier{
            .src_access_mask = .{ .transfer_write_bit = true },
            .dst_access_mask = .{ .shader_read_bit = true },
            .old_layout = .transfer_dst_optimal,
            .new_layout = .shader_read_only_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = upload.image,
            .subresource_range = colorSubresourceRange(),
        };
        dev.cmdPipelineBarrier(cmdbuf, .{ .transfer_bit = true }, .{ .fragment_shader_bit = true }, .{}, null, null, &.{to_sampled});
        frame.staging.appendAssumeCapacity(upload.staging);
    }
    self.pending_uploads.clearRetainingCapacity();

    if (previous_target) |target| self.beginOffscreenTarget(target.texture, target.extent, .load);
}

pub fn createTextureWithMem(self: Backend, img_info: vk.ImageCreateInfo, interpolation: dvui.enums.TextureInterpolation) !Texture {
    return self.createTextureWithSampler(img_info, 8 + @as(usize, @intFromEnum(interpolation)));
}

fn createTextureWithSampler(self: Backend, img_info: vk.ImageCreateInfo, sampler_slot: usize) !Texture {
    const dev = self.dev;
    var img: vk.Image = .null_handle;
    var mem: vk.DeviceMemory = .null_handle;
    var custom_resource: ?ImageAllocation = null;
    var allocation_size: vk.DeviceSize = 0;
    switch (self.gpu_allocator) {
        .builtin => {
            img = try dev.createImage(&img_info, self.vk_alloc);
            errdefer dev.destroyImage(img, self.vk_alloc);
            const mreq = dev.getImageMemoryRequirements(img);
            allocation_size = mreq.size;
            const memory = self.gpu_allocator.builtin;
            const memory_type_index = memory.findMemoryType(
                mreq.memory_type_bits,
                .{ .device_local_bit = true },
                .{},
            ) orelse memory.findMemoryType(mreq.memory_type_bits, .{}, .{ .device_local_bit = true }) orelse
                return error.NoCompatibleMemoryType;

            mem = dev.allocateMemory(&.{
                .allocation_size = mreq.size,
                .memory_type_index = memory_type_index,
            }, self.vk_alloc) catch |err| {
                slog.err("Failed to alloc texture mem: {}", .{err});
                return err;
            };
            errdefer dev.freeMemory(mem, self.vk_alloc);
            try dev.bindImageMemory(img, mem, 0);
        },
        .custom => |custom| {
            const resource = try custom.create_image(custom.userdata, dev, &img_info, .device_local);
            if (resource.handle == .null_handle) {
                custom.destroy_image(custom.userdata, dev, resource);
                return error.InvalidResourceAllocation;
            }
            custom_resource = resource;
            img = resource.handle;
            allocation_size = resource.size;
            errdefer custom.destroy_image(custom.userdata, dev, resource);
        },
    }
    errdefer if (custom_resource) |resource| {
        const custom = self.gpu_allocator.custom;
        custom.destroy_image(custom.userdata, dev, resource);
    } else {
        dev.destroyImage(img, self.vk_alloc);
        dev.freeMemory(mem, self.vk_alloc);
    };

    const srr = vk.ImageSubresourceRange{
        .aspect_mask = .{ .color_bit = true },
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };
    const img_view = try dev.createImageView(&.{
        .flags = .{},
        .image = img,
        .view_type = .@"2d",
        .format = img_format,
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .subresource_range = srr,
    }, self.vk_alloc);
    errdefer dev.destroyImageView(img_view, self.vk_alloc);

    var dset: [1]vk.DescriptorSet = undefined;
    dev.allocateDescriptorSets(&.{
        .descriptor_pool = self.dpool,
        .descriptor_set_count = 1,
        .p_set_layouts = @ptrCast(&self.dset_layout),
    }, &dset) catch |err| {
        if (enable_breakpoints) @breakpoint();
        slog.err("Failed to allocate descriptor set: {}", .{err});
        return err;
    };
    const dii = [1]vk.DescriptorImageInfo{.{
        .sampler = self.samplers[sampler_slot],
        .image_view = img_view,
        .image_layout = .shader_read_only_optimal,
    }};
    const write_dss = [_]vk.WriteDescriptorSet{.{
        .dst_set = dset[0],
        .dst_binding = tex_binding,
        .dst_array_element = 0,
        .descriptor_count = 1,
        .descriptor_type = .combined_image_sampler,
        .p_image_info = &dii,
        .p_buffer_info = undefined,
        .p_texel_buffer_view = undefined,
    }};
    dev.updateDescriptorSets(&write_dss, null);

    return Texture{
        .img = img,
        .img_view = img_view,
        .mem = mem,
        .custom_resource = custom_resource,
        .allocation_size = allocation_size,
        .dset = dset[0],
    };
}

pub fn createAndUploadTexture(self: *Backend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !Texture {
    return self.createAndUploadTextureWithSampler(pixels, width, height, 8 + @as(usize, @intFromEnum(interpolation)));
}

fn createAndUploadTextureWithSampler(self: *Backend, pixels: [*]const u8, width: u32, height: u32, sampler_slot: usize) !Texture {
    var tex = try self.createTextureWithSampler(.{
        .image_type = .@"2d",
        .format = img_format,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{
            .transfer_dst_bit = true,
            .sampled_bit = true,
        },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    }, sampler_slot);
    errdefer tex.deinit(self);

    const pixel_count = try std.math.mul(usize, @as(usize, width), @as(usize, height));
    const upload_size = try std.math.mul(usize, pixel_count, 4);
    const img_staging = try self.stageToBuffer(.{
        .flags = .{},
        .size = upload_size,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, pixels[0..upload_size]);
    var staging_owned = true;
    errdefer if (staging_owned) self.destroyAllocatedBuffer(img_staging);

    // When a frame is active, reserve before transferring staging ownership so
    // recording the upload cannot fail halfway through this texture creation.
    if (self.frame_active)
        try self.current_frame.staging.ensureUnusedCapacity(self.allocator, self.pending_uploads.items.len + 1);
    try self.pending_uploads.append(self.allocator, .{
        .image = tex.img,
        .width = width,
        .height = height,
        .staging = img_staging,
    });
    staging_owned = false;
    tex.layout = .shader_read_only_optimal;
    if (self.frame_active) self.recordPendingUploads() catch unreachable;
    return tex;
}

/// Compatibility alias for the original misspelled public symbol.
pub fn createAndUplaodTexture(self: *Backend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !Texture {
    return self.createAndUploadTexture(pixels, width, height, interpolation);
}

pub fn createOffscreenRenderPass(dev: DeviceProxy, format: vk.Format, load_op: vk.AttachmentLoadOp, vk_alloc: ?*vk.AllocationCallbacks) !vk.RenderPass {
    var subpasses: [1]vk.SubpassDescription = undefined;
    var color_attachments: [1]vk.AttachmentDescription = undefined;

    { // Render to framebuffer
        color_attachments[0] = vk.AttachmentDescription{
            .format = format, // swapchain / framebuffer image format
            .samples = .{ .@"1_bit" = true },
            .load_op = load_op,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .color_attachment_optimal,
            .final_layout = .color_attachment_optimal,
        };
        const color_attachment_ref = vk.AttachmentReference{
            .attachment = 0,
            .layout = .color_attachment_optimal,
        };
        subpasses[0] = vk.SubpassDescription{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = @ptrCast(&color_attachment_ref),
        };
    }

    const deps = [2]vk.SubpassDependency{
        .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .fragment_shader_bit = true },
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_access_mask = .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true },
            .dependency_flags = .{ .by_region_bit = true },
        },
        .{
            .src_subpass = 0,
            .dst_subpass = vk.SUBPASS_EXTERNAL,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_stage_mask = .{ .fragment_shader_bit = true },
            .src_access_mask = .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true },
            .dst_access_mask = .{ .shader_read_bit = true },
            .dependency_flags = .{ .by_region_bit = true },
        },
    };

    return try dev.createRenderPass(&.{
        .attachment_count = @intCast(color_attachments.len),
        .p_attachments = &color_attachments,
        .subpass_count = @intCast(subpasses.len),
        .p_subpasses = &subpasses,
        .dependency_count = deps.len,
        .p_dependencies = @ptrCast(&deps),
    }, vk_alloc);
}

pub const VertexBindings = struct {
    pub const binding_description = [_]vk.VertexInputBindingDescription{.{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    }};

    pub const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r8g8b8a8_unorm,
            .offset = @offsetOf(Vertex, "col"),
        },
        .{
            .binding = 0,
            .location = 2,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "uv"),
        },
    };
};

pub const tex_binding = texture_descriptor_binding.binding; // shader binding slot must match shader

pub const PushConstants = extern struct {
    view_scale: [2]f32,
    view_translate: [2]f32,
};

pub const GenericError = std.mem.Allocator.Error || error{BackendError};
pub const TextureError = GenericError || error{ TextureCreate, TextureRead, TextureUpdate, NotImplemented };
