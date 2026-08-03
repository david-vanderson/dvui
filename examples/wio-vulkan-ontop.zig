const std = @import("std");
const dvui = @import("dvui");
const WioBackend = @import("wio-backend");
const wio = WioBackend.wio;
const vk = dvui.render_backend.vulkan;

const vsync = true;
const show_demo = false;
var stats_rect: dvui.Rect = .{ .x = 440, .y = 20, .w = 340, .h = 430 };
var transfer_queue_family: ?u32 = null;
var transfer_queue_index: u32 = 0;

/// The application owns this pipeline and records the spinning cube before
/// DVUI appends its floating-window draw commands to the same rendering scope.
const Scene = struct {
    const PushConstants = extern struct {
        angle: f32,
        aspect: f32,
    };

    device: vk.DeviceProxy,
    vk_alloc: ?*vk.AllocationCallbacks,
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,

    fn init(renderer: *dvui.render_backend) !Scene {
        const context = renderer.vulkanContext();
        std.debug.assert(context.depth_format != null);
        const device = context.device;
        const vk_alloc = renderer.vulkanAllocationCallbacks();

        const push_range = vk.PushConstantRange{
            .stage_flags = .{ .vertex_bit = true },
            .offset = 0,
            .size = @sizeOf(PushConstants),
        };
        const pipeline_layout = try device.createPipelineLayout(&.{
            .push_constant_range_count = 1,
            .p_push_constant_ranges = @ptrCast(&push_range),
        }, vk_alloc);
        errdefer device.destroyPipelineLayout(pipeline_layout, vk_alloc);

        const vertex_spv align(@alignOf(u32)) = @embedFile("shaders/wio-ontop.vert.spv").*;
        const fragment_spv align(@alignOf(u32)) = @embedFile("shaders/wio-ontop.frag.spv").*;
        const vertex_module = try device.createShaderModule(&.{
            .code_size = vertex_spv.len,
            .p_code = @ptrCast(&vertex_spv),
        }, vk_alloc);
        defer device.destroyShaderModule(vertex_module, vk_alloc);
        const fragment_module = try device.createShaderModule(&.{
            .code_size = fragment_spv.len,
            .p_code = @ptrCast(&fragment_spv),
        }, vk_alloc);
        defer device.destroyShaderModule(fragment_module, vk_alloc);

        const stages = [_]vk.PipelineShaderStageCreateInfo{
            .{ .stage = .{ .vertex_bit = true }, .module = vertex_module, .p_name = "main" },
            .{ .stage = .{ .fragment_bit = true }, .module = fragment_module, .p_name = "main" },
        };
        const vertex_input = vk.PipelineVertexInputStateCreateInfo{};
        const input_assembly = vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };
        var viewport: vk.Viewport = undefined;
        var scissor: vk.Rect2D = undefined;
        const viewport_state = vk.PipelineViewportStateCreateInfo{
            .viewport_count = 1,
            .p_viewports = @ptrCast(&viewport),
            .scissor_count = 1,
            .p_scissors = @ptrCast(&scissor),
        };
        const rasterization = vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .cull_mode = .{},
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        };
        const multisample = vk.PipelineMultisampleStateCreateInfo{
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = .false,
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };
        const stencil = vk.StencilOpState{
            .fail_op = .keep,
            .pass_op = .keep,
            .depth_fail_op = .keep,
            .compare_op = .always,
            .compare_mask = 0,
            .write_mask = 0,
            .reference = 0,
        };
        const depth_stencil = vk.PipelineDepthStencilStateCreateInfo{
            .depth_test_enable = .true,
            .depth_write_enable = .true,
            .depth_compare_op = .less,
            .depth_bounds_test_enable = .false,
            .stencil_test_enable = .false,
            .front = stencil,
            .back = stencil,
            .min_depth_bounds = 0,
            .max_depth_bounds = 1,
        };
        const color_attachment = vk.PipelineColorBlendAttachmentState{
            .blend_enable = .false,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        };
        const color_blend = vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_attachment),
            .blend_constants = .{ 0, 0, 0, 0 },
        };
        const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
        const dynamic_state = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = &dynamic_states,
        };
        const color_formats = [_]vk.Format{context.color_format};
        var pipeline_rendering: vk.PipelineRenderingCreateInfo = undefined;
        var pipeline_p_next: ?*const anyopaque = null;
        const render_pass = switch (context.rendering_target) {
            .render_pass => |render_pass| render_pass,
            .dynamic => |target| dynamic: {
                pipeline_rendering = .{
                    .view_mask = 0,
                    .color_attachment_count = 1,
                    .p_color_attachment_formats = &color_formats,
                    .depth_attachment_format = target.depth_format,
                    .stencil_attachment_format = target.stencil_format,
                };
                pipeline_p_next = &pipeline_rendering;
                break :dynamic .null_handle;
            },
        };
        const pipeline_info = [_]vk.GraphicsPipelineCreateInfo{.{
            .p_next = pipeline_p_next,
            .stage_count = stages.len,
            .p_stages = &stages,
            .p_vertex_input_state = &vertex_input,
            .p_input_assembly_state = &input_assembly,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &rasterization,
            .p_multisample_state = &multisample,
            .p_depth_stencil_state = &depth_stencil,
            .p_color_blend_state = &color_blend,
            .p_dynamic_state = &dynamic_state,
            .layout = pipeline_layout,
            .render_pass = render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        }};
        var pipelines: [1]vk.Pipeline = undefined;
        _ = try device.createGraphicsPipelines(.null_handle, &pipeline_info, vk_alloc, &pipelines);

        return .{
            .device = device,
            .vk_alloc = vk_alloc,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipelines[0],
        };
    }

    fn deinit(self: *Scene) void {
        self.device.deviceWaitIdle() catch {};
        self.device.destroyPipeline(self.pipeline, self.vk_alloc);
        self.device.destroyPipelineLayout(self.pipeline_layout, self.vk_alloc);
    }

    fn draw(self: *Scene, frame: dvui.render_backend.ApplicationFrame, angle: f32) void {
        const viewport = vk.Viewport{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(frame.extent.width),
            .height = @floatFromInt(frame.extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };
        const scissor = vk.Rect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = frame.extent };
        frame.device.cmdSetViewport(frame.command_buffer, 0, &.{viewport});
        frame.device.cmdSetScissor(frame.command_buffer, 0, &.{scissor});
        frame.device.cmdBindPipeline(frame.command_buffer, .graphics, self.pipeline);
        const push = PushConstants{
            .angle = angle,
            .aspect = @as(f32, @floatFromInt(frame.extent.width)) / @as(f32, @floatFromInt(frame.extent.height)),
        };
        frame.device.cmdPushConstants(frame.command_buffer, self.pipeline_layout, .{ .vertex_bit = true }, 0, @sizeOf(PushConstants), &push);
        frame.device.cmdDraw(frame.command_buffer, 36, 1, 0, 0);
    }
};

/// Floating DVUI windows over an application-owned Vulkan draw.
pub fn main(init: std.process.Init) !void {
    if (@import("builtin").os.tag == .windows) {
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    dvui.Examples.show_demo_window = show_demo;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next(); // exe name
    var use_dynamic_rendering = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--dynamic-rendering")) {
            use_dynamic_rendering = true;
        } else {
            std.log.err("unknown argument: {s}", .{arg});
            return error.UnknownArgument;
        }
    }

    try wio.init(.{ .allocator = init.gpa, .io = init.io, .eventFn = wio.EventQueue.eventFn });
    defer wio.deinit();

    var events: wio.EventQueue = .empty;
    defer events.deinit();

    var window = try wio.Window.create(.{
        .event_fn_data = &events,
        .title = if (use_dynamic_rendering)
            "DVUI wio Vulkan Ontop Example (dynamic rendering)"
        else
            "DVUI wio Vulkan Ontop Example (render pass)",
        .size = .{ .width = 800, .height = 600 },
        .scale = 1,
    });
    defer window.destroy();
    window.enableDrawAvailableEvents();

    var renderer = try dvui.render_backend.init(init.gpa, &window, .{
        .size_physical = .{ .w = 800, .h = 600 },
        .vsync = vsync,
        .api_version = if (use_dynamic_rendering) vk.API_VERSION_1_3 else vk.API_VERSION_1_2,
        .rendering = if (use_dynamic_rendering) .dynamic else .render_pass,
        .depth_format = .d32_sfloat,
    });
    defer renderer.deinit();

    var scene = try Scene.init(&renderer);
    defer scene.deinit();

    var backend = try WioBackend.init(.{
        .io = init.io,
        .window = window,
        .size_logical = .{ .width = 800, .height = 600 },
        .size_physical = .{ .width = 800, .height = 600 },
    });
    defer backend.deinit();

    var win = try dvui.Window.init(@src(), init.gpa, backend.backend(&renderer), .{});
    defer win.deinit();

    const start_ns = backend.nanoTime();
    main_loop: while (true) {
        wio.update();
        var draw_available = false;
        while (events.pop()) |event| {
            switch (event) {
                .draw => draw_available = true,
                .close => break :main_loop,
                else => {},
            }
            _ = try backend.addEvent(&win, event);
        }
        if (!draw_available and renderer.vsyncEnabled()) { // for smooth resize
            backend.waitEventTimeout(std.time.ns_per_ms * 100);
            continue;
        }

        // Application rendering comes first.
        if (try renderer.beginApplicationFrame(backend.pixelSize())) |frame| {
            const elapsed_ns = backend.nanoTime() - start_ns;
            const angle: f32 = @floatCast(@as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s);
            scene.draw(frame, angle);
        }

        // Window.begin binds DVUI's pipeline after the application pipeline.
        try win.begin(backend.nanoTime());
        dvuiStuff(&renderer, use_dynamic_rendering);
        _ = try win.end(.{ .manage_backend = false });

        if (win.cursorRequestedFloating()) |cursor| {
            backend.setCursor(cursor);
        } else {
            backend.setCursor(.bad);
        }
        backend.textInputRect(win.textInputRequested());
        renderer.renderPresent();
    }
}

fn dvuiStuff(renderer: *dvui.render_backend, use_dynamic_rendering: bool) void {
    var float = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .w = 400, .h = 400 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("Floating Window", "", null));

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both });
    defer scroll.deinit();

    var title = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font = .theme(.title) });
    title.addText("DVUI over application-owned Vulkan rendering", .{});
    title.deinit();

    var text = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    text.addText(if (use_dynamic_rendering)
        "The depth-tested spinning cube is recorded by the application first. DVUI then records this floating window into the same Vulkan dynamic-rendering scope."
    else
        "The depth-tested spinning cube is recorded by the application first. DVUI then records this floating window into the same Vulkan render pass.", .{});
    text.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }
    if (dvui.button(@src(), "Debug Window", .{}, .{})) dvui.toggleDebugWindow();
    dvui.Examples.demo(.full);

    renderer.drawStatsWindow(&stats_rect);
}
