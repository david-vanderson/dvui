//! Vulkan 1.2 renderer and presentation bridge for the wio platform backend.
//!
//! This backend owns the Vulkan instance, device, surface, and swapchain. It
//! intentionally uses classic render passes and synchronization so Vulkan 1.3
//! features are not required.

const std = @import("std");
const dvui = @import("dvui");
const vk = @import("vk");
const wio = @import("wio");
const Renderer = @import("vulkan/renderer.zig");
const log = std.log.scoped(.dvui_vulkan);

pub const kind: dvui.enums.RenderBackend = .vulkan;
pub const api_version = vk.API_VERSION_1_2;
/// Vulkan declarations used by applications which record their own rendering
/// before DVUI in the same frame.
pub const vulkan = vk;
pub const RenderStats = Renderer.StatsSnapshot;

const frames_in_flight = 2;

/// Information passed to an optional physical-device selector. The backend has
/// already checked its Vulkan version, extension, surface, and queue needs.
pub const DeviceCandidate = struct {
    instance: vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    features: vk.PhysicalDeviceFeatures,
    graphics_queue_family: u32,
    present_queue_family: u32,
};

pub const DeviceSelector = struct {
    userdata: ?*anyopaque = null,
    /// Return null to reject a device. The highest score is selected.
    score: *const fn (userdata: ?*anyopaque, candidate: DeviceCandidate) ?i32,
};

pub const InitOptions = struct {
    size_physical: dvui.Size.Physical = .{ .w = 640, .h = 480 },
    vsync: bool = true,
    vk_alloc: ?*vk.AllocationCallbacks = null,
    color_formats: []const vk.Format = &.{
        .a2b10g10r10_unorm_pack32,
        .a2r10g10b10_unorm_pack32,
        .b8g8r8a8_unorm,
    },
    instance_extensions: []const [*:0]const u8 = &.{},
    device_extensions: []const [*:0]const u8 = &.{},
    device_features: vk.PhysicalDeviceFeatures = .{},
    /// Optional Vulkan feature structs chained to VkDeviceCreateInfo. The
    /// pointed-to structs only need to remain alive for the duration of init.
    device_features_p_next: ?*const anyopaque = null,
    select_device: ?DeviceSelector = null,
    /// color_attachment_bit is added automatically and all requested usages
    /// are validated against the selected surface.
    swapchain_image_usage: vk.ImageUsageFlags = .{},
    /// When set, the backend creates and clears one depth attachment per
    /// swapchain image and includes it in the application/DVUI render pass.
    depth_format: ?vk.Format = null,
};

const QueueFamilies = struct {
    graphics: u32,
    present: u32,
};

const SelectedDevice = struct {
    device: vk.PhysicalDevice,
    families: QueueFamilies,
    portability_subset: bool,
};

const DeviceExtensionSupport = struct {
    swapchain: bool = false,
    portability_subset: bool = false,
};

const Slot = struct {
    command_buffer: vk.CommandBuffer = .null_handle,
    image_available: vk.Semaphore = .null_handle,
    fence: vk.Fence = .null_handle,
};

const VulkanResources = struct {
    instance_wrapper: *vk.InstanceWrapper,
    instance: vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
    device_wrapper: *vk.DeviceWrapper,
    device: vk.DeviceProxy,
    graphics_queue: vk.QueueProxy,
    present_queue: vk.QueueProxy,
    queue_families: QueueFamilies,
    command_pool: vk.CommandPool,
    surface: vk.SurfaceKHR,

    fn deinit(self: *@This(), allocator: std.mem.Allocator, vk_alloc: ?*vk.AllocationCallbacks) void {
        self.device.destroyCommandPool(self.command_pool, vk_alloc);
        self.device.destroyDevice(vk_alloc);
        allocator.destroy(self.device_wrapper);
        self.instance.destroySurfaceKHR(self.surface, vk_alloc);
        self.instance.destroyInstance(vk_alloc);
        allocator.destroy(self.instance_wrapper);
    }
};

allocator: std.mem.Allocator,
vk_alloc: ?*vk.AllocationCallbacks,
instance_wrapper: *vk.InstanceWrapper,
instance: vk.InstanceProxy,
physical_device: vk.PhysicalDevice,
device_wrapper: *vk.DeviceWrapper,
device: vk.DeviceProxy,
graphics_queue: vk.QueueProxy,
present_queue: vk.QueueProxy,
queue_families: QueueFamilies,
command_pool: vk.CommandPool,
surface: vk.SurfaceKHR,
swapchain: vk.SwapchainKHR = .null_handle,
color_format: vk.Format = .undefined,
color_space: vk.ColorSpaceKHR = .srgb_nonlinear_khr,
extent: vk.Extent2D = .{ .width = 1, .height = 1 },
images: []vk.Image = &.{},
image_views: []vk.ImageView = &.{},
depth_images: []vk.Image = &.{},
depth_image_views: []vk.ImageView = &.{},
depth_memories: []vk.DeviceMemory = &.{},
framebuffers: []vk.Framebuffer = &.{},
image_fences: []vk.Fence = &.{},
render_finished: []vk.Semaphore = &.{},
slots: []Slot = &.{},
slot_index: usize = 0,
render_pass: vk.RenderPass,
renderer: Renderer,
preferred_formats: []vk.Format,
swapchain_image_usage: vk.ImageUsageFlags,
depth_format: ?vk.Format,
swapchain_generation: u64 = 0,
vsync: bool,
needs_recreate: bool = false,
frame_active: bool = false,
dvui_frame_active: bool = false,
previous_stats: RenderStats = .{},
pending_present: bool = false,
current_image: u32 = 0,
current_slot: usize = 0,

pub fn init(allocator: std.mem.Allocator, window: *wio.Window, options: InitOptions) !@This() {
    const owned = blk: {
        var resources = try initVulkanResources(allocator, window, options);
        errdefer resources.deinit(allocator, options.vk_alloc);
        const preferred_formats = try allocator.dupe(vk.Format, options.color_formats);
        break :blk .{ .resources = resources, .preferred_formats = preferred_formats };
    };
    const resources = owned.resources;

    var self: @This() = .{
        .allocator = allocator,
        .vk_alloc = options.vk_alloc,
        .instance_wrapper = resources.instance_wrapper,
        .instance = resources.instance,
        .physical_device = resources.physical_device,
        .device_wrapper = resources.device_wrapper,
        .device = resources.device,
        .graphics_queue = resources.graphics_queue,
        .present_queue = resources.present_queue,
        .queue_families = resources.queue_families,
        .command_pool = resources.command_pool,
        .surface = resources.surface,
        .render_pass = .null_handle,
        .renderer = undefined,
        .preferred_formats = owned.preferred_formats,
        .swapchain_image_usage = options.swapchain_image_usage.merge(.{ .color_attachment_bit = true }),
        .depth_format = options.depth_format,
        .vsync = options.vsync,
    };
    errdefer self.deinitBeforeRenderer();

    try self.createSwapchain(sizeToExtent(options.size_physical));
    if (options.depth_format) |format| try validateDepthFormat(resources.instance, resources.physical_device, format);
    self.render_pass = try createRenderPass(resources.device, self.color_format, options.depth_format, options.vk_alloc);
    try self.createFramebuffers();

    const properties = resources.instance.getPhysicalDeviceProperties(resources.physical_device);
    self.renderer = try Renderer.init(allocator, .{
        .dev = resources.device,
        .graphics_queue_family_index = resources.queue_families.graphics,
        .gpu_allocator = .{ .builtin = Renderer.VkMemory.init(
            resources.instance.getPhysicalDeviceMemoryProperties(resources.physical_device),
            properties.limits.non_coherent_atom_size,
        ) orelse return error.NoCompatibleMemoryType },
        .render_pass = .{ .static = .{ .render_pass = self.render_pass } },
        .max_frames_in_flight = frames_in_flight,
        .vk_alloc = options.vk_alloc,
    });
    return self;
}

pub fn deinit(self: *@This()) void {
    self.device.deviceWaitIdle() catch {};
    self.renderer.deinit();
    self.deinitBeforeRenderer();
    self.* = undefined;
}

fn deinitBeforeRenderer(self: *@This()) void {
    self.destroyFramebuffers();
    if (self.render_pass != .null_handle) self.device.destroyRenderPass(self.render_pass, self.vk_alloc);
    self.destroySwapchain();
    if (self.preferred_formats.len != 0) self.allocator.free(self.preferred_formats);
    if (self.command_pool != .null_handle) self.device.destroyCommandPool(self.command_pool, self.vk_alloc);
    self.device.destroyDevice(self.vk_alloc);
    self.allocator.destroy(self.device_wrapper);
    self.instance.destroySurfaceKHR(self.surface, self.vk_alloc);
    self.instance.destroyInstance(self.vk_alloc);
    self.allocator.destroy(self.instance_wrapper);
}

pub fn beginWithSize(self: *@This(), arena: std.mem.Allocator, physical_size: dvui.Size.Physical) dvui.Backend.GenericError!void {
    return self.beginInternal(arena, physical_size) catch |err| return mapGenericError(err);
}

fn beginInternal(self: *@This(), arena: std.mem.Allocator, physical_size: dvui.Size.Physical) !void {
    if (!self.frame_active) _ = try self.beginApplicationFrame(physical_size);
    if (!self.frame_active) return;
    if (self.dvui_frame_active) return error.FrameAlreadyActive;

    try self.renderer.beginFrame(self.slots[self.current_slot].command_buffer, self.extent);
    self.renderer.begin(arena, physical_size);
    self.dvui_frame_active = true;
}

/// Borrowed Vulkan handles for creating application-owned resources.
pub const VulkanContext = struct {
    instance: vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
    device: vk.DeviceProxy,
    graphics_queue: vk.QueueProxy,
    present_queue: vk.QueueProxy,
    graphics_queue_family: u32,
    present_queue_family: u32,
    render_pass: vk.RenderPass,
    color_format: vk.Format,
    depth_format: ?vk.Format,
};

/// Handles exposed for application rendering at the start of a Vulkan frame.
/// Commands recorded here execute before DVUI commands recorded by `Window.begin`.
pub const ApplicationFrame = struct {
    device: vk.DeviceProxy,
    command_buffer: vk.CommandBuffer,
    render_pass: vk.RenderPass,
    extent: vk.Extent2D,
    image: vk.Image,
    image_view: vk.ImageView,
    image_index: u32,
    swapchain_generation: u64,
};

/// Acquire a swapchain image and begin its render pass so the application can
/// render before DVUI. Call `Window.begin` afterwards to append the DVUI draw.
/// Returns null while the drawable has no usable extent or is being recreated.
pub fn beginApplicationFrame(self: *@This(), physical_size: dvui.Size.Physical) !?ApplicationFrame {
    if (self.frame_active) return error.FrameAlreadyActive;
    if (self.pending_present) self.present() catch |err| log.err("presenting delayed Vulkan frame failed: {}", .{err});
    if (physical_size.w < 1 or physical_size.h < 1) return null;

    const requested = sizeToExtent(physical_size);
    if (self.needs_recreate or requested.width != self.extent.width or requested.height != self.extent.height) {
        try self.recreate(requested);
    }

    const slot = &self.slots[self.slot_index];
    _ = try self.device.waitForFences(&.{slot.fence}, .true, std.math.maxInt(u64));
    const acquired = self.device.acquireNextImageKHR(self.swapchain, std.math.maxInt(u64), slot.image_available, .null_handle) catch |err| switch (err) {
        error.OutOfDateKHR => {
            self.needs_recreate = true;
            return null;
        },
        else => return err,
    };
    if (acquired.result == .suboptimal_khr) self.needs_recreate = true;
    if (self.image_fences[acquired.image_index] != .null_handle) {
        _ = try self.device.waitForFences(&.{self.image_fences[acquired.image_index]}, .true, std.math.maxInt(u64));
    }

    try self.device.resetCommandBuffer(slot.command_buffer, .{});
    try self.device.beginCommandBuffer(slot.command_buffer, &.{ .flags = .{ .one_time_submit_bit = true } });
    const clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
        .{ .depth_stencil = .{ .depth = 1, .stencil = 0 } },
    };
    self.device.cmdBeginRenderPass(slot.command_buffer, &.{
        .render_pass = self.render_pass,
        .framebuffer = self.framebuffers[acquired.image_index],
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.extent },
        .clear_value_count = if (self.depth_format == null) 1 else 2,
        .p_clear_values = &clear_values,
    }, .@"inline");

    self.current_image = acquired.image_index;
    self.current_slot = self.slot_index;
    self.frame_active = true;
    return .{
        .device = self.device,
        .command_buffer = slot.command_buffer,
        .render_pass = self.render_pass,
        .extent = self.extent,
        .image = self.images[acquired.image_index],
        .image_view = self.image_views[acquired.image_index],
        .image_index = acquired.image_index,
        .swapchain_generation = self.swapchain_generation,
    };
}

/// Borrowed Vulkan handles for creating application-owned resources. They are
/// valid until this renderer is deinitialized.
pub fn vulkanContext(self: *const @This()) VulkanContext {
    return .{
        .instance = self.instance,
        .physical_device = self.physical_device,
        .device = self.device,
        .graphics_queue = self.graphics_queue,
        .present_queue = self.present_queue,
        .graphics_queue_family = self.queue_families.graphics,
        .present_queue_family = self.queue_families.present,
        .render_pass = self.render_pass,
        .color_format = self.color_format,
        .depth_format = self.depth_format,
    };
}

pub fn swapchainGeneration(self: *const @This()) u64 {
    return self.swapchain_generation;
}

pub fn vulkanDevice(self: *const @This()) vk.DeviceProxy {
    return self.device;
}

pub fn vulkanRenderPass(self: *const @This()) vk.RenderPass {
    return self.render_pass;
}

pub fn vulkanAllocationCallbacks(self: *const @This()) ?*vk.AllocationCallbacks {
    return self.vk_alloc;
}

pub fn end(self: *@This()) dvui.Backend.GenericError!void {
    return self.endInternal() catch |err| return mapGenericError(err);
}

fn endInternal(self: *@This()) !void {
    if (!self.frame_active) return;
    const slot = &self.slots[self.current_slot];
    const recorded = if (self.dvui_frame_active) blk: {
        const frame = try self.renderer.endFrame();
        self.previous_stats = self.renderer.statsSnapshot();
        break :blk frame;
    } else Renderer.RecordedFrame{ .prepass = null, .main = slot.command_buffer };
    self.device.cmdEndRenderPass(slot.command_buffer);
    try self.device.endCommandBuffer(slot.command_buffer);
    try self.device.resetFences(&.{slot.fence});

    var command_buffers: [2]vk.CommandBuffer = undefined;
    var command_count: u32 = 1;
    command_buffers[0] = slot.command_buffer;
    if (recorded.prepass) |prepass| {
        command_buffers[0] = prepass;
        command_buffers[1] = slot.command_buffer;
        command_count = 2;
    }
    try self.device.queueSubmit(self.graphics_queue.handle, &.{.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{slot.image_available},
        .p_wait_dst_stage_mask = &.{.{ .color_attachment_output_bit = true }},
        .command_buffer_count = command_count,
        .p_command_buffers = &command_buffers,
        .signal_semaphore_count = 1,
        .p_signal_semaphores = &.{self.render_finished[self.current_image]},
    }}, slot.fence);
    self.image_fences[self.current_image] = slot.fence;
    self.pending_present = true;
    self.frame_active = false;
    self.dvui_frame_active = false;
}

pub fn stats(self: *const @This()) RenderStats {
    return self.previous_stats;
}

/// Request vsync on or off. The swapchain is recreated safely at the start of
/// the next frame; disabling vsync may still fall back to FIFO when necessary.
pub fn setVsync(self: *@This(), enabled: bool) void {
    if (self.vsync == enabled) return;
    self.vsync = enabled;
    self.needs_recreate = true;
}

pub fn vsyncEnabled(self: *const @This()) bool {
    return self.vsync;
}

/// Draw renderer statistics into the current DVUI container.
pub fn drawStats(self: *@This()) void {
    const snapshot = self.stats();
    const h2 = dvui.Font.theme(.body).larger(-2).withWeight(.bold).withLineHeight(1.1);

    var vsync = self.vsyncEnabled();
    if (dvui.checkbox(@src(), &vsync, "VSync", .{})) self.setVsync(vsync);
    dvui.label(@src(), "draw calls: {}", .{snapshot.draw_calls}, .{ .expand = .horizontal });
    drawStatsUsageRow("indices", snapshot.indices, snapshot.index_capacity, 0);
    drawStatsUsageRow("vertices", snapshot.vertices, snapshot.vertex_capacity, 1);

    dvui.labelNoFmt(@src(), "Textures", .{}, .{ .font = h2, .expand = .horizontal });
    dvui.label(@src(), "count: {}", .{snapshot.textures_alive}, .{ .expand = .horizontal });
    dvui.label(@src(), "GPU memory: {Bi:.1}", .{snapshot.texture_memory}, .{ .expand = .horizontal });

    dvui.labelNoFmt(@src(), "Preallocated streaming memory", .{}, .{ .font = h2, .expand = .horizontal });
    dvui.label(@src(), "total: {Bi:.1}", .{snapshot.stream_memory_total}, .{ .expand = .horizontal });
    dvui.label(@src(), "frame: {Bi:.1} / {Bi:.1}", .{ snapshot.stream_memory_used, snapshot.stream_memory_per_frame }, .{ .expand = .horizontal });
    drawStatsUsageBar(snapshot.stream_memory_used, snapshot.stream_memory_per_frame, 2);
}

/// Draw renderer statistics in a floating window. `rect`, when provided, must
/// remain valid across frames so the window can retain its position and size.
pub fn drawStatsWindow(self: *@This(), rect: ?*dvui.Rect) void {
    var float = dvui.floatingWindow(@src(), .{ .rect = rect }, .{ .min_size_content = .{ .w = 300, .h = 0 }, .id_extra = @intFromPtr(self) });
    defer float.deinit();
    float.dragAreaSet(dvui.windowHeader("Vulkan Renderer Stats", "", null));
    self.drawStats();
}

fn drawStatsUsageRow(comptime label: []const u8, used: anytype, capacity: usize, id_extra: usize) void {
    dvui.label(@src(), label ++ ": {} / {}", .{ used, capacity }, .{ .expand = .horizontal, .id_extra = id_extra });
    drawStatsUsageBar(used, capacity, id_extra);
}

fn drawStatsUsageBar(used: anytype, capacity: usize, id_extra: usize) void {
    const percent = if (capacity == 0) 0 else @as(f32, @floatFromInt(used)) / @as(f32, @floatFromInt(capacity));
    const original = dvui.themeGet().highlight.fill;
    defer dvui.currentWindow().theme.highlight.fill = original;
    dvui.currentWindow().theme.highlight.fill = dvui.Color.fromHSLuv(@max(12, (1 - percent * percent) * 155), 99, 50, 100);
    dvui.progress(@src(), .{ .percent = percent }, .{ .expand = .horizontal, .id_extra = id_extra });
}

pub fn renderPresent(self: *@This()) void {
    self.present() catch |err| switch (err) {
        error.OutOfDateKHR => self.needs_recreate = true,
        else => log.err("Vulkan present failed: {}", .{err}),
    };
}

fn present(self: *@This()) !void {
    if (!self.pending_present) return;
    defer self.pending_present = false;
    const result = try self.device.queuePresentKHR(self.present_queue.handle, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{self.render_finished[self.current_image]},
        .swapchain_count = 1,
        .p_swapchains = &.{self.swapchain},
        .p_image_indices = &.{self.current_image},
    });
    self.slot_index = (self.current_slot + 1) % self.slots.len;
    if (result == .suboptimal_khr) self.needs_recreate = true;
}

pub fn clear(_: *@This()) void {}

pub fn drawClippedTriangles(self: *@This(), _: dvui.Size.Physical, texture: ?dvui.Texture, vertices: []const dvui.Vertex, indices: []const dvui.Vertex.Index, clip: ?dvui.Rect.Physical) dvui.Backend.GenericError!void {
    if (self.frame_active) self.renderer.drawClippedTriangles(texture, vertices, indices, clip);
}

pub fn textureCreate(self: *@This(), pixels: [*]const u8, options: dvui.Texture.CreateOptions) dvui.Backend.TextureError!dvui.Texture {
    return self.renderer.textureCreate(pixels, options);
}

pub fn textureDestroy(self: *@This(), texture: dvui.Texture) void {
    self.renderer.textureDestroy(texture);
}

pub fn textureCreateTarget(self: *@This(), options: dvui.Texture.CreateOptions) dvui.Backend.TextureError!dvui.TextureTarget {
    return self.renderer.textureCreateTarget(options);
}

pub fn textureReadTarget(self: *@This(), texture: dvui.TextureTarget, pixels: [*]u8) dvui.Backend.TextureError!void {
    return self.renderer.textureReadTarget(texture, pixels);
}

pub fn textureClearTarget(self: *@This(), texture: dvui.Texture.Target) void {
    self.renderer.textureClearTarget(texture) catch |err| log.err("clearing Vulkan texture target failed: {}", .{err});
}

pub fn textureDestroyTarget(self: *@This(), texture: dvui.Texture.Target) void {
    self.renderer.textureDestroy(dvui.Texture.cast(texture));
}

pub fn textureFromTarget(self: *@This(), texture: dvui.TextureTarget) dvui.Backend.TextureError!dvui.Texture {
    return self.renderer.textureFromTarget(texture);
}

pub fn textureFromTargetTemp(_: *@This(), texture: dvui.TextureTarget) dvui.Backend.TextureError!dvui.Texture {
    return dvui.Texture.cast(texture);
}

pub fn renderTarget(self: *@This(), texture: ?dvui.TextureTarget) dvui.Backend.GenericError!void {
    return self.renderer.renderTarget(texture) catch |err| return mapGenericError(err);
}

fn recreate(self: *@This(), requested: vk.Extent2D) !void {
    if (requested.width == 0 or requested.height == 0) return;
    try self.device.deviceWaitIdle();
    self.destroyFramebuffers();
    self.destroySwapchain();
    try self.createSwapchain(requested);
    try self.createFramebuffers();
    self.needs_recreate = false;
}

fn createSwapchain(self: *@This(), requested: vk.Extent2D) !void {
    const capabilities = try self.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface);
    if (!capabilities.supported_usage_flags.contains(self.swapchain_image_usage)) return error.UnsupportedSwapchainImageUsage;
    self.extent = if (capabilities.current_extent.width != std.math.maxInt(u32)) capabilities.current_extent else .{
        .width = std.math.clamp(requested.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
        .height = std.math.clamp(requested.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
    };
    const formats = try self.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(self.physical_device, self.surface, self.allocator);
    defer self.allocator.free(formats);
    const selected_format = chooseColorFormat(formats, if (self.color_format == .undefined) self.preferred_formats else &.{self.color_format});
    if (self.color_format != .undefined and selected_format.format != self.color_format) return error.SurfaceFormatChanged;
    self.color_format = selected_format.format;
    self.color_space = selected_format.color_space;

    const modes = try self.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(self.physical_device, self.surface, self.allocator);
    defer self.allocator.free(modes);
    const image_count = if (capabilities.max_image_count == 0)
        capabilities.min_image_count + 1
    else
        @min(capabilities.min_image_count + 1, capabilities.max_image_count);
    const family_indices = [_]u32{ self.queue_families.graphics, self.queue_families.present };
    self.swapchain = try self.device.createSwapchainKHR(&.{
        .surface = self.surface,
        .min_image_count = image_count,
        .image_format = self.color_format,
        .image_color_space = self.color_space,
        .image_extent = self.extent,
        .image_array_layers = 1,
        .image_usage = self.swapchain_image_usage,
        .image_sharing_mode = if (self.queue_families.graphics == self.queue_families.present) .exclusive else .concurrent,
        .queue_family_index_count = if (self.queue_families.graphics == self.queue_families.present) 0 else 2,
        .p_queue_family_indices = if (self.queue_families.graphics == self.queue_families.present) null else &family_indices,
        .pre_transform = capabilities.current_transform,
        .composite_alpha = chooseCompositeAlpha(capabilities.supported_composite_alpha),
        .present_mode = choosePresentMode(modes, self.vsync),
        .clipped = .true,
    }, self.vk_alloc);
    errdefer self.destroySwapchain();

    self.images = try self.device.getSwapchainImagesAllocKHR(self.swapchain, self.allocator);
    self.image_views = try self.allocator.alloc(vk.ImageView, self.images.len);
    @memset(self.image_views, .null_handle);
    for (self.images, self.image_views) |image, *view| {
        view.* = try self.device.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = self.color_format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = colorRange(),
        }, self.vk_alloc);
    }
    self.image_fences = try self.allocator.alloc(vk.Fence, self.images.len);
    @memset(self.image_fences, .null_handle);
    self.render_finished = try self.allocator.alloc(vk.Semaphore, self.images.len);
    @memset(self.render_finished, .null_handle);
    for (self.render_finished) |*semaphore| semaphore.* = try self.device.createSemaphore(&.{}, self.vk_alloc);

    self.slots = try self.allocator.alloc(Slot, frames_in_flight);
    @memset(self.slots, Slot{});
    for (self.slots) |*slot| {
        slot.image_available = try self.device.createSemaphore(&.{}, self.vk_alloc);
        slot.fence = try self.device.createFence(&.{ .flags = .{ .signaled_bit = true } }, self.vk_alloc);
        try self.device.allocateCommandBuffers(&.{
            .command_pool = self.command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&slot.command_buffer));
    }
    self.swapchain_generation += 1;
}

fn destroySwapchain(self: *@This()) void {
    for (self.slots) |slot| {
        if (slot.image_available != .null_handle) self.device.destroySemaphore(slot.image_available, self.vk_alloc);
        if (slot.fence != .null_handle) self.device.destroyFence(slot.fence, self.vk_alloc);
        if (slot.command_buffer != .null_handle) self.device.freeCommandBuffers(self.command_pool, &.{slot.command_buffer});
    }
    for (self.render_finished) |semaphore| if (semaphore != .null_handle) self.device.destroySemaphore(semaphore, self.vk_alloc);
    for (self.image_views) |view| if (view != .null_handle) self.device.destroyImageView(view, self.vk_alloc);
    if (self.slots.len != 0) self.allocator.free(self.slots);
    if (self.render_finished.len != 0) self.allocator.free(self.render_finished);
    if (self.image_fences.len != 0) self.allocator.free(self.image_fences);
    if (self.image_views.len != 0) self.allocator.free(self.image_views);
    if (self.images.len != 0) self.allocator.free(self.images);
    if (self.swapchain != .null_handle) self.device.destroySwapchainKHR(self.swapchain, self.vk_alloc);
    self.slots = &.{};
    self.render_finished = &.{};
    self.image_fences = &.{};
    self.image_views = &.{};
    self.images = &.{};
    self.swapchain = .null_handle;
    self.slot_index = 0;
}

fn createFramebuffers(self: *@This()) !void {
    if (self.depth_format != null) try self.createDepthResources();
    errdefer self.destroyFramebuffers();
    self.framebuffers = try self.allocator.alloc(vk.Framebuffer, self.image_views.len);
    @memset(self.framebuffers, .null_handle);
    for (self.image_views, self.framebuffers, 0..) |view, *framebuffer, i| {
        const attachments = [_]vk.ImageView{ view, if (self.depth_format == null) .null_handle else self.depth_image_views[i] };
        framebuffer.* = try self.device.createFramebuffer(&.{
            .render_pass = self.render_pass,
            .attachment_count = if (self.depth_format == null) 1 else 2,
            .p_attachments = &attachments,
            .width = self.extent.width,
            .height = self.extent.height,
            .layers = 1,
        }, self.vk_alloc);
    }
}

fn destroyFramebuffers(self: *@This()) void {
    for (self.framebuffers) |framebuffer| if (framebuffer != .null_handle) self.device.destroyFramebuffer(framebuffer, self.vk_alloc);
    if (self.framebuffers.len != 0) self.allocator.free(self.framebuffers);
    self.framebuffers = &.{};
    self.destroyDepthResources();
}

fn createDepthResources(self: *@This()) !void {
    const format = self.depth_format orelse return;
    const memory_properties = self.instance.getPhysicalDeviceMemoryProperties(self.physical_device);
    self.depth_images = try self.allocator.alloc(vk.Image, self.image_views.len);
    @memset(self.depth_images, .null_handle);
    errdefer self.destroyDepthResources();
    self.depth_image_views = try self.allocator.alloc(vk.ImageView, self.image_views.len);
    @memset(self.depth_image_views, .null_handle);
    self.depth_memories = try self.allocator.alloc(vk.DeviceMemory, self.image_views.len);
    @memset(self.depth_memories, .null_handle);

    for (self.depth_images, self.depth_image_views, self.depth_memories) |*image, *view, *memory| {
        image.* = try self.device.createImage(&.{
            .image_type = .@"2d",
            .format = format,
            .extent = .{ .width = self.extent.width, .height = self.extent.height, .depth = 1 },
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = .optimal,
            .usage = .{ .depth_stencil_attachment_bit = true },
            .sharing_mode = .exclusive,
            .initial_layout = .undefined,
        }, self.vk_alloc);
        const requirements = self.device.getImageMemoryRequirements(image.*);
        const memory_type_index = findMemoryType(memory_properties, requirements.memory_type_bits, .{ .device_local_bit = true }) orelse
            findMemoryType(memory_properties, requirements.memory_type_bits, .{}) orelse
            return error.NoCompatibleMemoryType;
        memory.* = try self.device.allocateMemory(&.{
            .allocation_size = requirements.size,
            .memory_type_index = memory_type_index,
        }, self.vk_alloc);
        try self.device.bindImageMemory(image.*, memory.*, 0);
        view.* = try self.device.createImageView(&.{
            .image = image.*,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = depthRange(format),
        }, self.vk_alloc);
    }
}

fn destroyDepthResources(self: *@This()) void {
    for (self.depth_image_views) |view| if (view != .null_handle) self.device.destroyImageView(view, self.vk_alloc);
    for (self.depth_images) |image| if (image != .null_handle) self.device.destroyImage(image, self.vk_alloc);
    for (self.depth_memories) |memory| if (memory != .null_handle) self.device.freeMemory(memory, self.vk_alloc);
    if (self.depth_image_views.len != 0) self.allocator.free(self.depth_image_views);
    if (self.depth_images.len != 0) self.allocator.free(self.depth_images);
    if (self.depth_memories.len != 0) self.allocator.free(self.depth_memories);
    self.depth_image_views = &.{};
    self.depth_images = &.{};
    self.depth_memories = &.{};
}

fn initVulkanResources(allocator: std.mem.Allocator, window: *wio.Window, options: InitOptions) !VulkanResources {
    const vk_alloc = options.vk_alloc;
    const base = vk.BaseWrapper.load(getInstanceProcAddr);
    const instance_wrapper = try allocator.create(vk.InstanceWrapper);
    errdefer allocator.destroy(instance_wrapper);

    const wio_extensions = wio.getRequiredVulkanInstanceExtensions();
    const available_extensions = try base.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    defer allocator.free(available_extensions);
    const portability_enumeration = hasExtension(available_extensions, vk.extensions.khr_portability_enumeration.name);
    const extension_storage = try allocator.alloc(
        [*:0]const u8,
        wio_extensions.len + options.instance_extensions.len + @intFromBool(portability_enumeration),
    );
    defer allocator.free(extension_storage);
    var extension_count: usize = 0;
    appendUniqueExtensions(extension_storage, &extension_count, wio_extensions);
    appendUniqueExtensions(extension_storage, &extension_count, options.instance_extensions);
    if (portability_enumeration) appendUniqueExtensions(
        extension_storage,
        &extension_count,
        &.{vk.extensions.khr_portability_enumeration.name.ptr},
    );
    const extensions = extension_storage[0..extension_count];
    for (extensions) |extension| {
        if (!hasExtension(available_extensions, std.mem.span(extension))) return error.MissingRequiredInstanceExtension;
    }

    const instance_handle = try base.createInstance(&.{
        .flags = .{ .enumerate_portability_bit_khr = portability_enumeration },
        .p_application_info = &.{
            .p_application_name = "dvui",
            .application_version = 0,
            .p_engine_name = "dvui",
            .engine_version = 0,
            .api_version = @bitCast(api_version),
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
    }, vk_alloc);
    instance_wrapper.* = vk.InstanceWrapper.load(instance_handle, getInstanceProcAddr);
    const instance = vk.InstanceProxy.init(instance_handle, instance_wrapper);
    errdefer instance.destroyInstance(vk_alloc);

    var surface_value: u64 = 0;
    if (window.vkCreateSurface(@intFromEnum(instance_handle), vk_alloc, &surface_value) != 0) return error.SurfaceCreateFailed;
    const surface: vk.SurfaceKHR = @enumFromInt(surface_value);
    errdefer instance.destroySurfaceKHR(surface, vk_alloc);

    const selected = try selectPhysicalDevice(
        allocator,
        instance,
        surface,
        options.device_extensions,
        options.device_features,
        options.swapchain_image_usage.merge(.{ .color_attachment_bit = true }),
        options.depth_format,
        options.select_device,
    );
    const priorities = [_]f32{1};
    var queue_infos: [2]vk.DeviceQueueCreateInfo = undefined;
    queue_infos[0] = .{
        .queue_family_index = selected.families.graphics,
        .queue_count = 1,
        .p_queue_priorities = &priorities,
    };
    var queue_info_count: u32 = 1;
    if (selected.families.present != selected.families.graphics) {
        queue_infos[1] = .{
            .queue_family_index = selected.families.present,
            .queue_count = 1,
            .p_queue_priorities = &priorities,
        };
        queue_info_count = 2;
    }

    const device_wrapper = try allocator.create(vk.DeviceWrapper);
    errdefer allocator.destroy(device_wrapper);
    const device_extension_storage = try allocator.alloc([*:0]const u8, options.device_extensions.len + 2);
    defer allocator.free(device_extension_storage);
    var device_extension_count: usize = 0;
    appendUniqueExtensions(device_extension_storage, &device_extension_count, &.{vk.extensions.khr_swapchain.name.ptr});
    appendUniqueExtensions(device_extension_storage, &device_extension_count, options.device_extensions);
    if (selected.portability_subset) appendUniqueExtensions(
        device_extension_storage,
        &device_extension_count,
        &.{vk.extensions.khr_portability_subset.name.ptr},
    );
    const device_extensions = device_extension_storage[0..device_extension_count];
    const device_handle = try instance.createDevice(selected.device, &.{
        .p_next = options.device_features_p_next,
        .queue_create_info_count = queue_info_count,
        .p_queue_create_infos = &queue_infos,
        .enabled_extension_count = @intCast(device_extensions.len),
        .pp_enabled_extension_names = device_extensions.ptr,
        .p_enabled_features = &options.device_features,
    }, vk_alloc);
    device_wrapper.* = vk.DeviceWrapper.load(device_handle, instance_wrapper.dispatch.vkGetDeviceProcAddr.?);
    const device = vk.DeviceProxy.init(device_handle, device_wrapper);
    errdefer device.destroyDevice(vk_alloc);

    const command_pool = try device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = selected.families.graphics,
    }, vk_alloc);
    errdefer device.destroyCommandPool(command_pool, vk_alloc);

    return .{
        .instance_wrapper = instance_wrapper,
        .instance = instance,
        .physical_device = selected.device,
        .device_wrapper = device_wrapper,
        .device = device,
        .graphics_queue = vk.QueueProxy.init(device.getDeviceQueue(selected.families.graphics, 0), device_wrapper),
        .present_queue = vk.QueueProxy.init(device.getDeviceQueue(selected.families.present, 0), device_wrapper),
        .queue_families = selected.families,
        .command_pool = command_pool,
        .surface = surface,
    };
}

fn selectPhysicalDevice(
    allocator: std.mem.Allocator,
    instance: vk.InstanceProxy,
    surface: vk.SurfaceKHR,
    required_extensions: []const [*:0]const u8,
    required_features: vk.PhysicalDeviceFeatures,
    required_swapchain_usage: vk.ImageUsageFlags,
    depth_format: ?vk.Format,
    selector: ?DeviceSelector,
) !SelectedDevice {
    const devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(devices);
    var selected: ?SelectedDevice = null;
    var selected_score: i32 = std.math.minInt(i32);
    for (devices) |device| {
        const properties = instance.getPhysicalDeviceProperties(device);
        if (properties.api_version < @as(u32, @bitCast(api_version))) continue;
        const available_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(device, null, allocator);
        defer allocator.free(available_extensions);
        const extension_support = getDeviceExtensionSupport(available_extensions);
        if (!extension_support.swapchain) continue;
        var extensions_available = true;
        for (required_extensions) |extension| {
            if (!hasExtension(available_extensions, std.mem.span(extension))) extensions_available = false;
        }
        if (!extensions_available) continue;

        const features = instance.getPhysicalDeviceFeatures(device);
        if (!supportsFeatures(features, required_features)) continue;

        const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, allocator);
        defer allocator.free(families);
        var graphics: ?u32 = null;
        var present_family: ?u32 = null;
        for (families, 0..) |family, i| {
            const index: u32 = @intCast(i);
            if (graphics == null and family.queue_flags.graphics_bit) graphics = index;
            if (present_family == null and try instance.getPhysicalDeviceSurfaceSupportKHR(device, index, surface) == .true) present_family = index;
        }
        if (graphics == null or present_family == null) continue;
        const surface_capabilities = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(device, surface);
        if (!surface_capabilities.supported_usage_flags.contains(required_swapchain_usage)) continue;
        if (depth_format) |format| {
            const format_properties = instance.getPhysicalDeviceFormatProperties(device, format);
            if (!format_properties.optimal_tiling_features.depth_stencil_attachment_bit) continue;
        }
        const candidate = DeviceCandidate{
            .instance = instance,
            .physical_device = device,
            .properties = properties,
            .features = features,
            .graphics_queue_family = graphics.?,
            .present_queue_family = present_family.?,
        };
        const score = if (selector) |selection|
            selection.score(selection.userdata, candidate) orelse continue
        else
            0;
        if (selected == null or score > selected_score) {
            selected_score = score;
            selected = .{
                .device = device,
                .families = .{ .graphics = graphics.?, .present = present_family.? },
                .portability_subset = extension_support.portability_subset,
            };
            if (selector == null) break;
        }
    }
    return selected orelse error.NoSuitableDevice;
}

fn getDeviceExtensionSupport(extensions: []const vk.ExtensionProperties) DeviceExtensionSupport {
    var support: DeviceExtensionSupport = .{};
    for (extensions) |extension| {
        const name = std.mem.sliceTo(&extension.extension_name, 0);
        if (std.mem.eql(u8, name, vk.extensions.khr_swapchain.name)) support.swapchain = true;
        if (std.mem.eql(u8, name, vk.extensions.khr_portability_subset.name)) support.portability_subset = true;
    }
    return support;
}

fn supportsFeatures(available: vk.PhysicalDeviceFeatures, required: vk.PhysicalDeviceFeatures) bool {
    inline for (@typeInfo(vk.PhysicalDeviceFeatures).@"struct".fields) |field| {
        if (@field(required, field.name) == .true and @field(available, field.name) != .true) return false;
    }
    return true;
}

fn hasExtension(extensions: []const vk.ExtensionProperties, wanted: []const u8) bool {
    for (extensions) |extension| {
        if (std.mem.eql(u8, std.mem.sliceTo(&extension.extension_name, 0), wanted)) return true;
    }
    return false;
}

fn hasExtensionName(extensions: []const [*:0]const u8, wanted: []const u8) bool {
    for (extensions) |extension| {
        if (std.mem.eql(u8, std.mem.span(extension), wanted)) return true;
    }
    return false;
}

fn appendUniqueExtensions(
    destination: [][*:0]const u8,
    count: *usize,
    extensions: []const [*:0]const u8,
) void {
    for (extensions) |extension| {
        if (hasExtensionName(destination[0..count.*], std.mem.span(extension))) continue;
        destination[count.*] = extension;
        count.* += 1;
    }
}

fn createRenderPass(
    device: vk.DeviceProxy,
    color_format: vk.Format,
    depth_format: ?vk.Format,
    vk_alloc: ?*vk.AllocationCallbacks,
) !vk.RenderPass {
    const attachments = [_]vk.AttachmentDescription{
        .{
            .format = color_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        },
        .{
            .format = depth_format orelse .undefined,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .dont_care,
            .stencil_load_op = .clear,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .depth_stencil_attachment_optimal,
        },
    };
    const color_reference = vk.AttachmentReference{ .attachment = 0, .layout = .color_attachment_optimal };
    const depth_reference = vk.AttachmentReference{ .attachment = 1, .layout = .depth_stencil_attachment_optimal };
    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_reference),
        .p_depth_stencil_attachment = if (depth_format == null) null else &depth_reference,
    };
    const dependency = vk.SubpassDependency{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = depth_format != null,
        },
        .dst_stage_mask = .{
            .color_attachment_output_bit = true,
            .early_fragment_tests_bit = depth_format != null,
        },
        .dst_access_mask = .{
            .color_attachment_read_bit = true,
            .color_attachment_write_bit = true,
            .depth_stencil_attachment_read_bit = depth_format != null,
            .depth_stencil_attachment_write_bit = depth_format != null,
        },
    };
    return device.createRenderPass(&.{
        .attachment_count = if (depth_format == null) 1 else 2,
        .p_attachments = &attachments,
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
        .dependency_count = 1,
        .p_dependencies = @ptrCast(&dependency),
    }, vk_alloc);
}

fn validateDepthFormat(instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice, format: vk.Format) !void {
    const properties = instance.getPhysicalDeviceFormatProperties(physical_device, format);
    if (!properties.optimal_tiling_features.depth_stencil_attachment_bit) return error.UnsupportedDepthFormat;
}

fn findMemoryType(
    properties: vk.PhysicalDeviceMemoryProperties,
    type_bits: u32,
    required: vk.MemoryPropertyFlags,
) ?u32 {
    for (properties.memory_types[0..properties.memory_type_count], 0..) |memory_type, i| {
        const bit = @as(u32, 1) << @intCast(i);
        if (type_bits & bit != 0 and memory_type.property_flags.contains(required)) return @intCast(i);
    }
    return null;
}

fn chooseColorFormat(available: []const vk.SurfaceFormatKHR, preferred: []const vk.Format) vk.SurfaceFormatKHR {
    if (available.len == 1 and available[0].format == .undefined and preferred.len != 0) {
        return .{ .format = preferred[0], .color_space = available[0].color_space };
    }
    for (preferred) |format| for (available) |item| if (item.format == format) return item;
    return available[0];
}

fn choosePresentMode(available: []const vk.PresentModeKHR, vsync: bool) vk.PresentModeKHR {
    if (!vsync) for (available) |mode| if (mode == .mailbox_khr) return mode;
    if (!vsync) for (available) |mode| if (mode == .immediate_khr) return mode;
    return .fifo_khr;
}

fn chooseCompositeAlpha(supported: vk.CompositeAlphaFlagsKHR) vk.CompositeAlphaFlagsKHR {
    if (supported.opaque_bit_khr) return .{ .opaque_bit_khr = true };
    if (supported.pre_multiplied_bit_khr) return .{ .pre_multiplied_bit_khr = true };
    if (supported.post_multiplied_bit_khr) return .{ .post_multiplied_bit_khr = true };
    return .{ .inherit_bit_khr = true };
}

fn colorRange() vk.ImageSubresourceRange {
    return .{
        .aspect_mask = .{ .color_bit = true },
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };
}

fn depthRange(format: vk.Format) vk.ImageSubresourceRange {
    return .{
        .aspect_mask = .{
            .depth_bit = format != .s8_uint,
            .stencil_bit = switch (format) {
                .s8_uint, .d16_unorm_s8_uint, .d24_unorm_s8_uint, .d32_sfloat_s8_uint => true,
                else => false,
            },
        },
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };
}

fn sizeToExtent(size: dvui.Size.Physical) vk.Extent2D {
    return .{
        .width = @max(1, @as(u32, @intFromFloat(@round(size.w)))),
        .height = @max(1, @as(u32, @intFromFloat(@round(size.h)))),
    };
}

fn getInstanceProcAddr(instance: vk.Instance, name: [*:0]const u8) callconv(vk.vulkan_call_conv) vk.PfnVoidFunction {
    return @ptrCast(wio.vkGetInstanceProcAddr(@intFromEnum(instance), name));
}

fn mapGenericError(err: anyerror) dvui.Backend.GenericError {
    log.err("Vulkan backend operation failed: {}", .{err});
    return if (err == error.OutOfMemory) error.OutOfMemory else error.BackendError;
}

test {
    std.testing.refAllDecls(@This());
}
