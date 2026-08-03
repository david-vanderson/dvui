# DVUI Vulkan

DVUI's Vulkan support has two layers:

- `vulkan.zig` is the native wio integration. It owns device selection,
  the surface, swapchain, frame synchronization, submission, and presentation.
- `renderer.zig` is the platform-independent renderer for custom
  backends. The application owns all Vulkan platform and frame lifecycle work.

## Native wio backend

Select wio and Vulkan in the DVUI dependency:

```zig
const dvui_dep = b.dependency("dvui", .{
    .target = target,
    .optimize = optimize,
    .backend = .wio,
    .renderer = .vulkan,
});
exe.root_module.addImport("dvui", dvui_dep.module("dvui_wio"));
```

Initialize the renderer with a wio window:

```zig
var renderer = try dvui.render_backend.init(gpa, &window, .{
    .size_physical = .{ .w = 800, .h = 600 },
    .vsync = true,
});
defer renderer.deinit();

var backend = try WioBackend.init(.{ .io = io, .window = window });
var win = try dvui.Window.init(@src(), gpa, backend.backend(&renderer), .{});
```

Applications can add Vulkan requirements while leaving device, swapchain, and
submission ownership with the backend:

```zig
var renderer = try dvui.render_backend.init(gpa, &window, .{
    .instance_extensions = &.{my_instance_extension_name},
    .device_extensions = &.{my_extension_name},
    .device_features = .{ .sampler_anisotropy = .true },
    .device_features_p_next = feature_chain,
    .select_device = .{ .userdata = app, .select = selectDevice },
    .depth_format = .d32_sfloat,
});
```

The optional selector receives all devices which passed DVUI's Vulkan version,
swapchain, surface, requested-extension, feature, attachment, and base queue
requirements. It returns the desired candidate index; a missing selector uses
the first candidate.

Feature structs in `device_features_p_next` are borrowed only during `init`; the
application is responsible for querying support for those extended features.

### Vulkan version and dynamic rendering

The native backend can own a Vulkan 1.3 dynamic-rendering scope instead of a
classic render pass:

```zig
var renderer = try dvui.render_backend.init(gpa, &window, .{
    .api_version = vk.API_VERSION_1_3,
    .rendering = .dynamic,
    .depth_format = .d32_sfloat,
});
```

Dynamic rendering requires Vulkan 1.3. The backend queries and enables the core
`dynamicRendering` feature automatically. Do not also put
`VkPhysicalDeviceDynamicRenderingFeatures` in `device_features_p_next`.

`VulkanContext.rendering_target` describes either the classic render pass or
the color/depth/stencil formats required in `VkPipelineRenderingCreateInfo`.
The legacy `render_pass` field is null in dynamic mode.

### Device and queue selection

Applications which need additional transfer, compute, sparse, or video queues
can increase the selected device's per-family queue counts before device
creation:

```zig
const QueueState = struct {
    transfer_family: u32 = undefined,
    transfer_index: u32 = undefined,
};

fn configureQueues(
    userdata: ?*anyopaque,
    candidate: dvui.render_backend.DeviceCandidate,
    queue_counts: []u32,
) !void {
    const state: *QueueState = @ptrCast(@alignCast(userdata.?));
    const family = findTransferFamily(candidate, queue_counts) orelse return;
    state.transfer_family = family;
    state.transfer_index = queue_counts[family];
    queue_counts[family] += 1;
}

var queue_state: QueueState = .{};
var renderer = try dvui.render_backend.init(gpa, &window, .{
    .select_device = .{
        .userdata = &queue_state,
        .configure_queues = configureQueues,
    },
});
```

The counts already reserve index zero in DVUI's graphics and presentation
families. They may only be increased and must not exceed the advertised family
capacity. DVUI creates exactly those dense queue ranges; it does not retain or
return application queue handles. Retrieve a reserved queue after initialization:

```zig
const context = renderer.vulkanContext();
const transfer_queue = context.device.getDeviceQueue(
    queue_state.transfer_family,
    queue_state.transfer_index,
);
```

DVUI owns submissions to its graphics and presentation queues. Application
queues, command pools, submission synchronization, and queue-family ownership
transfers remain application-owned. Queue selection does not enable related
features or extensions: request sparse features through `device_features`,
video extensions through `device_extensions`, and extended features through
`device_features_p_next`. The callbacks may use the candidate's instance,
physical device, and queue-family properties for video profile or other
extension-specific queries.

The backend always adds `color_attachment_bit` to `swapchain_image_usage` and
rejects unsupported requested usage flags. An optional `depth_format` must
support optimal-tiled depth/stencil attachments; DVUI creates one attachment per
swapchain image and clears it at the beginning of the shared rendering scope.

`Window.begin()` acquires and begins the Vulkan frame. `Window.end()` finishes
DVUI recording, submits, and presents it.

Application Vulkan commands can be recorded before DVUI in the same rendering scope:

```zig
if (try renderer.beginApplicationFrame(backend.pixelSize())) |frame| {
    // Record application commands into frame.command_buffer.
}
try win.begin(backend.nanoTime()); // binds DVUI's pipeline after application work
```

Do not end or submit `frame.command_buffer`; the backend owns it. See
[wio-vulkan-ontop.zig](../../../../examples/wio-vulkan-ontop.zig) for a complete
application-owned pipeline example.

Use `renderer.vulkanContext()` to create application pipelines and resources.
It exposes borrowed instance, physical-device, device, queue, queue-family,
rendering-target, and attachment-format information. Each `ApplicationFrame` also
contains the acquired image, image view/index, extent, and
`swapchain_generation`. Rebuild application resources tied to swapchain images
or extent whenever that generation changes.

The context handles remain backend-owned: do not destroy them, present the
swapchain, or submit the frame command buffer yourself. Synchronize any separate
application queue submissions before DVUI uses the affected resources.

Application commands are recorded inside the render pass or dynamic-rendering
scope begun by `beginApplicationFrame()`. They must obey its attachment layouts
and execute before `Window.begin()`. Destroy application-owned Vulkan resources
before `renderer.deinit()`.

The native adapter also provides:

```zig
renderer.setVsync(false);              // recreates the swapchain next frame
const enabled = renderer.vsyncEnabled();
const stats = renderer.stats();
renderer.drawStats();                  // into the current DVUI container
renderer.drawStatsWindow(&stats_rect); // reusable floating window
```

## Custom backend renderer

Enable the public low-level module without enabling the wio adapter:

```zig
const dvui_dep = b.dependency("dvui", .{
    .target = target,
    .optimize = optimize,
    .backend = .custom,
    .renderer = .vulkan,
});

const dvui_mod = dvui_dep.module("dvui");
const vk_renderer_mod = dvui_dep.module("dvui_vulkan_renderer");

custom_backend_mod.addImport("dvui", dvui_mod);
custom_backend_mod.addImport("dvui_vulkan_renderer", vk_renderer_mod);
dvui_mod.addImport("backend", custom_backend_mod);
```

In the custom backend:

```zig
const dvui = @import("dvui");
const VkRenderer = @import("dvui_vulkan_renderer");
const vk = VkRenderer.vulkan;
```

Use the re-exported `VkRenderer.vulkan` declarations so handles have exactly the
same generated Zig types as the renderer.

### Ownership

| Application/custom backend owns | `VkRenderer` owns |
| --- | --- |
| Instance, physical-device selection, device and queues | DVUI graphics pipelines and descriptors |
| Surface, swapchain, images and framebuffers | Samplers and DVUI textures |
| Main render pass or dynamic-rendering setup | Streaming vertex/index buffers |
| Main command buffers, fences and semaphores | Texture prepass command pools and buffers |
| Submission, presentation and resize handling | Resources allocated through its selected GPU allocator |

The device, render target, callbacks, and borrowed pipeline handles passed to the
renderer must remain valid until `deinit()` returns.

### Initialization

After creating the device and compatible render pass, initialize the DVUI
renderer:

```zig
const properties = instance.getPhysicalDeviceProperties(physical_device);
const memory = VkRenderer.VkMemory.init(
    instance.getPhysicalDeviceMemoryProperties(physical_device),
    properties.limits.non_coherent_atom_size,
) orelse return error.NoCompatibleMemoryType;

var renderer = try VkRenderer.init(gpa, .{
    .dev = device,
    .gpu_allocator = .{ .builtin = memory },
    .render_pass = .{ .static = .{
        .render_pass = render_pass,
        .subpass = 0,
    } },
    .graphics_queue_family_index = graphics_queue_family_index,
    .submit_readback = readback_submission,
    .max_frames_in_flight = frames_in_flight,
});
```

`submit_readback` is optional unless `textureReadTarget` is used. Its callback
must submit the supplied command buffer to the graphics queue and return only
after that work completes. This keeps queue ownership and external
synchronization in the application.

`GpuAllocator.custom` can replace the built-in per-resource allocation strategy,
for example when using VMA. `PipelineSource` can similarly use an application
pipeline implementing the exported descriptor, vertex, blend, and push-constant
ABI. Custom allocators receive `.readback` for download buffers; non-coherent
mapped allocations must provide the corresponding invalidate callback.

### Frame lifecycle

Before `dvui.Window.begin()`, the custom backend must begin its main command
buffer and a compatible render pass, then start the renderer frame:

```zig
try renderer.beginFrame(main_command_buffer, extent);
renderer.begin(frame_arena, .{
    .w = @floatFromInt(extent.width),
    .h = @floatFromInt(extent.height),
});
```

The custom backend delegates DVUI's draw and texture operations to `renderer`.
See [Backend.zig](../../../Backend.zig) for the backend contract and
[vulkan.zig](../vulkan.zig) for concrete delegation examples.

At the end of the DVUI frame:

```zig
const recorded = try renderer.endFrame();

// End the application's render pass and main command buffer.
// Submit recorded.prepass first when it is non-null, followed by recorded.main.
```

Texture uploads and render-target work may produce `recorded.prepass`. It must be
submitted before `recorded.main` on the ordered graphics queue and covered by the
same frame-completion synchronization. Alternatively, configure `.submit_prepass`
at initialization and perform that submission in the callback.

Before the Nth subsequent `beginFrame()`, where N is
`max_frames_in_flight`, all GPU work from the original frame must have completed.
Wait for all renderer work before calling `deinit()`.

## Shaders

The checked-in SPIR-V 1.5 files are compatible with Vulkan 1.2. Regeneration
commands are at the top of [dvui.slang](dvui.slang) and require `slangc`; normal
builds do not require a Vulkan SDK or shader compiler.
