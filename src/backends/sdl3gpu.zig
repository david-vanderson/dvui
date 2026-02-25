const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const sdl_options = @import("sdl_options");
pub const sdl3 = sdl_options.version.major == 3;

// Index buffer configuration based on build option
pub const IndexElementSize = if (dvui.Vertex.Index == u32) c.SDL_GPU_INDEXELEMENTSIZE_32BIT else c.SDL_GPU_INDEXELEMENTSIZE_16BIT;

pub const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");

    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

extern "SDL_config" fn MACOS_enable_scroll_momentum() callconv(.c) void;

pub const kind: dvui.enums.Backend = .sdl3gpu;

pub const SDLBackend = @This();
pub const Context = *SDLBackend;

const log = std.log.scoped(.SDL3GPUBackend);

// Embedded shaders organized by format
const spv_shaders = struct {
    const vertex align(8) = @embedFile("sdl3gpu/compiled/spv/default.vertex.spv").*;
    const fragment align(8) = @embedFile("sdl3gpu/compiled/spv/default.fragment.spv").*;
};

const msl_shaders = struct {
    const vertex align(8) = @embedFile("sdl3gpu/compiled/msl/default.vertex.msl").*;
    const fragment align(8) = @embedFile("sdl3gpu/compiled/msl/default.fragment.msl").*;
};

const dxil_shaders = struct {
    const vertex align(8) = @embedFile("sdl3gpu/compiled/dxil/default.vertex.dxil").*;
    const fragment align(8) = @embedFile("sdl3gpu/compiled/dxil/default.fragment.dxil").*;
};

// Backend texture that references one of the shared samplers
const BackendTexture = struct {
    texture: *c.SDL_GPUTexture,
    sampler: *c.SDL_GPUSampler, // points to either linear_sampler or nearest_sampler
};

// Draw call information
const RectDraw = struct {
    index_start: u32,
    index_count: u32,
    texture: *BackendTexture,
    scissor: ?c.SDL_Rect,
};

fn UploadBuffer(comptime T: type) type {
    return struct {
        device: *c.SDL_GPUDevice,
        usage: c.SDL_GPUBufferUsageFlags,
        transfer: *c.SDL_GPUTransferBuffer,
        buffer: *c.SDL_GPUBuffer,
        mapped: ?[*]T,
        cap: u32,
        len: u32 = 0,

        pub const element_size = @sizeOf(T);

        pub fn init(device: *c.SDL_GPUDevice, capacity: u32, usage: c.SDL_GPUBufferUsageFlags) !@This() {
            const buffer_size = capacity * element_size;

            // Create vertex transfer buffer
            const transfer = c.SDL_CreateGPUTransferBuffer(
                device,
                &c.SDL_GPUTransferBufferCreateInfo{
                    .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                    .size = buffer_size,
                    .props = 0,
                },
            ) orelse return error.BufferCreationFailed;
            errdefer c.SDL_ReleaseGPUTransferBuffer(device, transfer);

            // Create vertex GPU buffer
            const buffer = c.SDL_CreateGPUBuffer(
                device,
                &c.SDL_GPUBufferCreateInfo{
                    .usage = usage,
                    .size = buffer_size,
                    .props = 0,
                },
            ) orelse return error.BufferCreationFailed;
            errdefer c.SDL_ReleaseGPUBuffer(device, buffer);

            return .{
                .device = device,
                .buffer = buffer,
                .usage = usage,
                .transfer = transfer,
                .mapped = @ptrCast(@alignCast(c.SDL_MapGPUTransferBuffer(device, transfer, false))),
                .cap = capacity,
            };
        }

        pub fn unmap(self: *@This()) void {
            c.SDL_UnmapGPUTransferBuffer(self.device, self.transfer);
            self.mapped = null;
        }

        pub fn reset(self: *@This()) void {
            self.len = 0;
        }

        pub fn ensureCapacityPushCount(self: *@This(), push_count: usize) !void {
            if (self.len + push_count >= self.cap) {
                var new_size = self.cap;

                while (new_size < self.len + push_count) {
                    if (new_size > 10000) {
                        new_size *= 2;
                    } else {
                        new_size += 2000;
                    }
                }

                try self.resize(new_size);
            }
        }

        pub fn maybeMap(self: *@This()) void {
            if (self.mapped == null) {
                self.mapped = @ptrCast(@alignCast(c.SDL_MapGPUTransferBuffer(self.device, self.transfer, true)));
            }
        }

        pub fn pushAssumeCap(self: *@This(), new: T) void {
            self.mapped.?[self.len] = new;
            self.len += 1;
        }

        pub fn addUploads(self: *@This(), copy_pass: *c.SDL_GPUCopyPass) void {
            self.unmap();
            c.SDL_UploadToGPUBuffer(
                copy_pass,
                &c.SDL_GPUTransferBufferLocation{
                    .transfer_buffer = self.transfer,
                    .offset = 0,
                },
                &c.SDL_GPUBufferRegion{
                    .buffer = self.buffer,
                    .offset = 0,
                    .size = @intCast(self.len * element_size),
                },
                true,
            );
            self.reset();
        }

        pub fn deinit(self: *@This()) void {
            self.unmap();
            c.SDL_ReleaseGPUTransferBuffer(self.device, self.transfer);
            c.SDL_ReleaseGPUBuffer(self.device, self.buffer);
        }

        pub fn resize(self: *@This(), new_cap: u32) !void {
            const new_size = new_cap * element_size;

            self.unmap();

            const device = self.device;
            const transfer = c.SDL_CreateGPUTransferBuffer(
                device,
                &c.SDL_GPUTransferBufferCreateInfo{
                    .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                    .size = new_size,
                    .props = 0,
                },
            ) orelse return error.BufferCreationFailed;
            errdefer c.SDL_ReleaseGPUTransferBuffer(device, transfer);

            // Create vertex GPU buffer
            const buffer = c.SDL_CreateGPUBuffer(
                device,
                &c.SDL_GPUBufferCreateInfo{
                    .usage = self.usage,
                    .size = new_size,
                    .props = 0,
                },
            ) orelse return error.BufferCreationFailed;
            errdefer c.SDL_ReleaseGPUBuffer(device, buffer);

            // gpu copy pass, from old gpu buffer to new buffer

            const cmd_buffer = c.SDL_AcquireGPUCommandBuffer(self.device) orelse {
                log.err("Failed to acquire command buffer for resize: {s}", .{c.SDL_GetError()});
                return error.ResizeFailed;
            };

            const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buffer) orelse {
                log.err("Failed to begin copyPass for resize: {s}", .{c.SDL_GetError()});
                return error.ResizeFailed;
            };

            c.SDL_CopyGPUBufferToBuffer(
                copy_pass,
                &c.SDL_GPUBufferLocation{
                    .buffer = self.buffer,
                    .offset = 0,
                },
                &c.SDL_GPUBufferLocation{
                    .buffer = buffer,
                    .offset = 0,
                },
                self.cap * element_size,
                false,
            );

            c.SDL_EndGPUCopyPass(copy_pass);

            if (!c.SDL_SubmitGPUCommandBuffer(cmd_buffer)) {
                log.err("Failed to submit command buffer for resize: {s}", .{c.SDL_GetError()});
                return error.TextureCreate;
            }

            c.SDL_ReleaseGPUBuffer(self.device, self.buffer);
            c.SDL_ReleaseGPUTransferBuffer(self.device, self.transfer);

            self.buffer = buffer;
            self.transfer = transfer;
            self.cap = new_cap;
            self.mapped = @ptrCast(@alignCast(c.SDL_MapGPUTransferBuffer(device, transfer, false)));
        }
    };
}

// Upload buffers for batching vertex/index data before rendering
const FrameUploads = struct {
    vertex: UploadBuffer(Vertex),
    index: UploadBuffer(dvui.Vertex.Index),

    // Draw calls tracking
    draws: std.ArrayList(RectDraw) = .{},
    allocator: std.mem.Allocator,

    // Copy pass for uploading data each frame
    copy_pass: ?*c.SDL_GPUCopyPass = null,

    fn init(device: *c.SDL_GPUDevice, allocator: std.mem.Allocator) !FrameUploads {
        return .{
            .vertex = try UploadBuffer(Vertex).init(device, 1000, c.SDL_GPU_BUFFERUSAGE_VERTEX),
            .index = try UploadBuffer(dvui.Vertex.Index).init(device, 2000, c.SDL_GPU_BUFFERUSAGE_INDEX),
            .allocator = allocator,
        };
    }

    fn deinit(self: *FrameUploads, device: *c.SDL_GPUDevice) void {
        _ = device;
        self.draws.deinit(self.allocator);
        self.vertex.deinit();
        self.index.deinit();
    }

    fn reset(self: *FrameUploads) void {
        self.index.reset();
        self.vertex.reset();

        self.draws.clearRetainingCapacity();
    }

    pub fn addUploads(self: *FrameUploads) void {
        const copy_pass = self.copy_pass.?;

        self.vertex.addUploads(copy_pass);
        self.index.addUploads(copy_pass);

        self.vertex.maybeMap();
        self.index.maybeMap();
    }

    fn push(self: *FrameUploads, back: *SDLBackend, backendTexture: ?*BackendTexture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, scissor: ?c.SDL_Rect) !void {
        // Record draw call
        try self.draws.append(self.allocator, .{
            .index_start = self.index.len,
            .index_count = @intCast(idx.len),
            .texture = backendTexture orelse back.white_texture,
            .scissor = scissor,
        });

        const vertex_start: dvui.Vertex.Index = @intCast(self.vertex.len);

        try self.vertex.ensureCapacityPushCount(vtx.len);
        try self.index.ensureCapacityPushCount(idx.len);

        const size = if (back.current_render_target_size) |s| s else back.last_pixel_size;

        for (vtx) |v| {
            self.vertex.pushAssumeCap(Vertex.fromDvui(v, size));
        }

        for (idx) |id| {
            self.index.pushAssumeCap(@as(dvui.Vertex.Index, id) + vertex_start);
        }
    }
};

const Vector4f = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

const Vector2f = extern struct {
    x: f32,
    y: f32,
};

const Vertex = extern struct {
    position: Vector4f,
    color: Vector4f,
    texcoord: Vector2f,

    pub fn fromDvui(v: dvui.Vertex, s: anytype) @This() {
        return @This(){
            .position = .{
                .x = v.pos.x / s.w * 2 - 1.0,
                .y = -(v.pos.y / s.h * 2 - 1.0),
                .z = 0.0,
                .w = 1.0,
            },
            .color = .{
                .x = @as(f32, @floatFromInt(v.col.r)) / 255.0,
                .y = @as(f32, @floatFromInt(v.col.g)) / 255.0,
                .z = @as(f32, @floatFromInt(v.col.b)) / 255.0,
                .w = @as(f32, @floatFromInt(v.col.a)) / 255.0,
            },
            .texcoord = .{
                .x = v.uv[0],
                .y = v.uv[1],
            },
        };
    }
};

window: *c.SDL_Window,
device: *c.SDL_GPUDevice,

destroyDeviceOnExit: bool = false,

// Pipeline and rendering resources
swapchain_pipeline: *c.SDL_GPUGraphicsPipeline = undefined,
rendertarget_pipeline: *c.SDL_GPUGraphicsPipeline = undefined,
external_cmdbuffer: bool = false,
cmd: ?*c.SDL_GPUCommandBuffer = null,
swapchain_texture: ?*c.SDL_GPUTexture = null,
current_render_target: ?*BackendTextureTarget = null,
current_render_target_size: ?dvui.Size.Physical = null,
current_render_pass: ?*c.SDL_GPURenderPass = null,

// White texture for non-textured draws
white_texture: *BackendTexture = undefined,

// Shared samplers for all textures
linear_sampler: *c.SDL_GPUSampler = undefined,
nearest_sampler: *c.SDL_GPUSampler = undefined,

// list of linearly allocated buffers for transfers
texture_transfer_buffer: *c.SDL_GPUTransferBuffer = undefined,
texture_transfer_buffer_size: u32 = 0,

// Rect uploads for batching geometry
frame_uploads: FrameUploads = undefined,

// Shader-related fields
shaderformat: c.SDL_GPUShaderFormat = 0,
shader_entrypoint: []const u8 = "main",

ak_should_initialized: bool = dvui.accesskit_enabled,
we_own_window: bool = false,
touch_mouse_events: bool = false,
log_events: bool = false,
initial_scale: f32 = 1.0,
last_pixel_size: dvui.Size.Physical = .{ .w = 800, .h = 600 },
last_window_size: dvui.Size.Natural = .{ .w = 800, .h = 600 },
cursor_last: dvui.enums.Cursor = .arrow,
cursor_backing: [@typeInfo(dvui.enums.Cursor).@"enum".fields.len]?*c.SDL_Cursor = [_]?*c.SDL_Cursor{null} ** @typeInfo(dvui.enums.Cursor).@"enum".fields.len,
cursor_backing_tried: [@typeInfo(dvui.enums.Cursor).@"enum".fields.len]bool = [_]bool{false} ** @typeInfo(dvui.enums.Cursor).@"enum".fields.len,
arena: std.mem.Allocator = undefined,
textures_arena: std.heap.ArenaAllocator = undefined,

const max_texture_size = 2048 * 2048 * 4;
pub const TexTransferBuf = struct {
    transfer: *c.SDL_GPUTransferBuffer,
    slice: []const u8,
    fba: std.heap.FixedBufferAllocator,

    pub fn init(device: *c.SDL_GPUDevice) @This() {
        const buf = c.SDL_CreateGPUTransferBuffer(device, &c.SDL_GPUTransferBufferCreateInfo{
            .size = max_texture_size,
            .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .props = 0,
        });

        const p: [*]u8 = @ptrCast(@alignCast(c.SDL_MapGPUTransferBuffer(device, buf, false)));
        const s = p[0..max_texture_size];

        return @This(){
            .transfer = buf.?,
            .slice = s,
            .fba = std.heap.FixedBufferAllocator.init(s),
        };
    }

    pub fn reset(self: *@This()) void {
        self.fba.reset();
    }

    pub fn deinit(self: *@This(), device: *c.SDL_GPUDevice) void {
        c.SDL_UnmapGPUTransferBuffer(device, self.transfer);
        c.SDL_ReleaseGPUTransferBuffer(device, self.transfer);
    }
};

pub const InitOptions = struct {
    /// The allocator used for temporary allocations used during init()
    allocator: std.mem.Allocator,
    /// The initial size of the application window
    size: dvui.Size,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    vsync: bool,
    /// The application title to display
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
    /// use when running tests
    hidden: bool = false,
    fullscreen: bool = false,
};

pub fn initWindow(options: InitOptions) !SDLBackend {
    // use the string version instead of the #define so we compile with SDL < 2.24
    _ = c.SDL_SetHint("SDL_HINT_WINDOWS_DPI_SCALING", "1");
    _ = c.SDL_SetHint(c.SDL_HINT_MAC_SCROLL_MOMENTUM, "1");

    try toErr(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS), "SDL_Init in initWindow");

    var hidden = options.hidden;
    var show_window_in_begin = false;
    if (dvui.accesskit_enabled and !hidden) {
        // hide the window until we can initialize accesskit in Window.begin
        hidden = true;
        show_window_in_begin = true;
    }

    const hidden_flag = if (hidden) c.SDL_WINDOW_HIDDEN else 0;
    const fullscreen_flag = if (options.fullscreen) c.SDL_WINDOW_FULLSCREEN else 0;
    const window: *c.SDL_Window = c.SDL_CreateWindow(
        options.title,
        @as(c_int, @intFromFloat(options.size.w)),
        @as(c_int, @intFromFloat(options.size.h)),
        @intCast(c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE | hidden_flag | fullscreen_flag),
    ) orelse return logErr("SDL_CreateWindow in initWindow");

    errdefer c.SDL_DestroyWindow(window);

    // do premultiplied alpha blending:
    // * rendering to a texture and then rendering the texture works the same
    // * any filtering happening across pixels won't bleed in transparent rgb values
    // const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    // try toErr(c.SDL_SetRenderDrawBlendMode(renderer, pma_blend), "SDL_SetRenderDrawBlendMode in initWindow");

    const device = c.SDL_CreateGPUDevice(c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL, true, null) orelse {
        std.debug.print("Failed to create device: {s}\n", .{c.SDL_GetError()});
        return error.BackendError;
    };

    // Claim window for GPU device
    if (!c.SDL_ClaimWindowForGPUDevice(device, window)) {
        std.debug.print("Failed to claim window for GPU device: {s}\n", .{c.SDL_GetError()});
        c.SDL_DestroyGPUDevice(device);
        return error.BackendError;
    }

    var back = init(window, device, options.allocator);
    back.ak_should_initialized = show_window_in_begin;
    back.we_own_window = true;

    // TODO: May want to factor this out into shared code with the sdl3 backend

    back.initial_scale = c.SDL_GetDisplayContentScale(c.SDL_GetDisplayForWindow(window));
    if (back.initial_scale == 0) return logErr("SDL_GetDisplayContentScale in initWindow");
    log.info("SDL3 backend scale {d}", .{back.initial_scale});

    if (back.initial_scale != 1.0) {
        _ = c.SDL_SetWindowSize(
            window,
            @as(c_int, @intFromFloat(back.initial_scale * options.size.w)),
            @as(c_int, @intFromFloat(back.initial_scale * options.size.h)),
        );
    }

    if (options.icon) |bytes| {
        try back.setIconFromFileContent(bytes);
    }

    if (options.min_size) |size| {
        const ret = c.SDL_SetWindowMinimumSize(
            window,
            @as(c_int, @intFromFloat(back.initial_scale * size.w)),
            @as(c_int, @intFromFloat(back.initial_scale * size.h)),
        );
        try toErr(ret, "SDL_SetWindowMinimumSize in initWindow");
    }

    if (options.max_size) |size| {
        const ret = c.SDL_SetWindowMaximumSize(
            window,
            @as(c_int, @intFromFloat(back.initial_scale * size.w)),
            @as(c_int, @intFromFloat(back.initial_scale * size.h)),
        );
        try toErr(ret, "SDL_SetWindowMaximumSize in initWindow");
    }

    if (!options.vsync) {
        if (!c.SDL_SetGPUSwapchainParameters(
            device,
            window,
            c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
            c.SDL_GPU_PRESENTMODE_IMMEDIATE, // present mode VSYNC is the default
        )) {
            std.debug.print("Failed to set IMMEDIATE present mode: {s}", .{c.SDL_GetError()});
        }
    }

    return back;
}

pub fn init(window: *c.SDL_Window, device: *c.SDL_GPUDevice, allocator: std.mem.Allocator) SDLBackend {
    var back = SDLBackend{
        .window = window,
        .device = device,
        .textures_arena = std.heap.ArenaAllocator.init(allocator),
    };
    back.detectShaderFormat();
    back.createPipeline() catch |err| {
        log.err("Failed to create pipeline: {any}", .{err});
        @panic("Pipeline creation failed");
    };
    back.createSamplers() catch |err| {
        log.err("Failed to create samplers: {any}", .{err});
        @panic("Sampler creation failed");
    };

    back.createTextureTransferBuffer() catch |err| {
        log.err("Failed to create transfer buffer: {any}", .{err});
        @panic("Transfer buffer creation failed");
    };

    back.createWhiteTexture() catch |err|
        {
            log.err("Unable to create white texture: {any}", .{err});
            @panic("White Texture Creation failed");
        };

    back.frame_uploads = FrameUploads.init(device, allocator) catch |err| {
        log.err("Failed to create rect uploads: {any}", .{err});
        @panic("FrameUploads creation failed");
    };
    return back;
}

fn createWhiteTexture(self: *SDLBackend) !void {
    self.white_texture = @ptrCast(@alignCast((self.textureCreate(&.{ 255, 255, 255, 255 }, 1, 1, .linear, .rgba_32) catch return error.BackendError).ptr));
}

fn detectShaderFormat(self: *SDLBackend) void {
    const formats = c.SDL_GetGPUShaderFormats(self.device);

    if (formats & c.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        self.shaderformat = c.SDL_GPU_SHADERFORMAT_SPIRV;
        self.shader_entrypoint = "main";
        log.info("Using SPIR-V shaders", .{});
    } else if (formats & c.SDL_GPU_SHADERFORMAT_MSL != 0) {
        self.shaderformat = c.SDL_GPU_SHADERFORMAT_MSL;
        self.shader_entrypoint = "main0";
        log.info("Using MSL shaders", .{});
    } else if (formats & c.SDL_GPU_SHADERFORMAT_DXIL != 0) {
        self.shaderformat = c.SDL_GPU_SHADERFORMAT_DXIL;
        self.shader_entrypoint = "main";
        log.info("Using DXIL shaders", .{});
    } else {
        log.err("No supported shader format found!", .{});
    }
}

fn getShaderExtension(self: *SDLBackend) []const u8 {
    return switch (self.shaderformat) {
        c.SDL_GPU_SHADERFORMAT_SPIRV => "spv",
        c.SDL_GPU_SHADERFORMAT_MSL => "msl",
        c.SDL_GPU_SHADERFORMAT_DXIL => "dxil",
        else => "unknown",
    };
}

pub fn loadShader(
    self: *SDLBackend,
    shader_code: []const u8,
    stage: c.SDL_GPUShaderStage,
    num_samplers: u32,
    num_storage_textures: u32,
    num_storage_buffers: u32,
    num_uniform_buffers: u32,
) !*c.SDL_GPUShader {
    const stage_name: []const u8 = if (stage == c.SDL_GPU_SHADERSTAGE_VERTEX) "vertex" else "fragment";
    log.info("Loading {s} {s} shader ({d} bytes)", .{ self.getShaderExtension(), stage_name, shader_code.len });

    // Create shader
    const shader_info = c.SDL_GPUShaderCreateInfo{
        .code_size = shader_code.len,
        .code = shader_code.ptr,
        .entrypoint = self.shader_entrypoint.ptr,
        .format = self.shaderformat,
        .stage = stage,
        .num_samplers = num_samplers,
        .num_storage_textures = num_storage_textures,
        .num_storage_buffers = num_storage_buffers,
        .num_uniform_buffers = num_uniform_buffers,
        .props = 0,
    };

    const shader = c.SDL_CreateGPUShader(self.device, &shader_info);
    if (shader == null) {
        log.err("Failed to create shader: {s}", .{c.SDL_GetError()});
        return error.ShaderCreationFailed;
    }

    return shader.?;
}

pub fn loadShaders(
    self: *SDLBackend,
) !struct { vertex: *c.SDL_GPUShader, fragment: *c.SDL_GPUShader } {
    // Select embedded shader data based on detected format
    const vertex_data: []const u8, const fragment_data: []const u8 = switch (self.shaderformat) {
        c.SDL_GPU_SHADERFORMAT_SPIRV => .{ &spv_shaders.vertex, &spv_shaders.fragment },
        c.SDL_GPU_SHADERFORMAT_MSL => .{ &msl_shaders.vertex, &msl_shaders.fragment },
        c.SDL_GPU_SHADERFORMAT_DXIL => .{ &dxil_shaders.vertex, &dxil_shaders.fragment },
        else => return error.UnsupportedShaderFormat,
    };

    // Vertex shader: 0 samplers, 0 storage textures, 0 storage buffers, 0 uniform buffers
    const vertex_shader = try self.loadShader(
        vertex_data,
        c.SDL_GPU_SHADERSTAGE_VERTEX,
        0,
        0,
        0,
        0,
    );

    // Fragment shader: 1 sampler, 0 storage textures, 0 storage buffers, 0 uniform buffers
    const fragment_shader = try self.loadShader(
        fragment_data,
        c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        1,
        0,
        0,
        0,
    );

    return .{ .vertex = vertex_shader, .fragment = fragment_shader };
}

pub fn createPipeline(self: *SDLBackend) !void {
    // Load shaders
    const shaders = try self.loadShaders();
    defer c.SDL_ReleaseGPUShader(self.device, shaders.vertex);
    defer c.SDL_ReleaseGPUShader(self.device, shaders.fragment);

    // Get swapchain texture format
    const swapchain_format = c.SDL_GetGPUSwapchainTextureFormat(self.device, self.window);
    log.err("swapchain format: {d}", .{swapchain_format});

    // Create color target description
    var color_target = std.mem.zeroes(c.SDL_GPUColorTargetDescription);
    color_target.format = swapchain_format;
    //color_target.blend_state = std.mem.zeroes(c.SDL_GPUColorTargetBlendState);
    color_target.blend_state = .{
        .enable_blend = true,
        .alpha_blend_op = c.SDL_GPU_BLENDOP_ADD,
        .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
        .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
        .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    };

    // Create pipeline info
    var pipeline_info = std.mem.zeroes(c.SDL_GPUGraphicsPipelineCreateInfo);
    pipeline_info.vertex_shader = shaders.vertex;
    pipeline_info.fragment_shader = shaders.fragment;
    pipeline_info.target_info.num_color_targets = 1;
    pipeline_info.target_info.color_target_descriptions = &color_target;
    pipeline_info.rasterizer_state.fill_mode = c.SDL_GPU_FILLMODE_FILL;
    pipeline_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;

    pipeline_info.vertex_input_state = .{
        .num_vertex_attributes = 3,
        .num_vertex_buffers = 1,
        .vertex_buffer_descriptions = &c.SDL_GPUVertexBufferDescription{
            .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .slot = 0,
            .instance_step_rate = 0,
            .pitch = @sizeOf(Vertex),
        },
        .vertex_attributes = &[_]c.SDL_GPUVertexAttribute{
            c.SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 0, .offset = 0 },
            c.SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4, .location = 1, .offset = @sizeOf(f32) * 4 },
            c.SDL_GPUVertexAttribute{ .buffer_slot = 0, .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .location = 2, .offset = @sizeOf(f32) * 4 * 2 },
        },
    };

    // Create the pipeline
    self.swapchain_pipeline = c.SDL_CreateGPUGraphicsPipeline(self.device, &pipeline_info) orelse {
        log.err("Failed to create graphics pipeline: {s}", .{c.SDL_GetError()});
        return error.PipelineCreationFailed;
    };

    color_target.format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
    self.rendertarget_pipeline = c.SDL_CreateGPUGraphicsPipeline(self.device, &pipeline_info) orelse {
        log.err("Failed to create graphics pipeline: {s}", .{c.SDL_GetError()});
        return error.PipelineCreationFailed;
    };

    log.info("Graphics pipeline created successfully", .{});
}

pub fn createSamplers(self: *SDLBackend) !void {
    // Create linear sampler
    const linear_sampler_info = c.SDL_GPUSamplerCreateInfo{
        .min_filter = c.SDL_GPU_FILTER_LINEAR,
        .mag_filter = c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .mip_lod_bias = 0.0,
        .max_anisotropy = 1.0,
        .compare_op = c.SDL_GPU_COMPAREOP_NEVER,
        .min_lod = 0.0,
        .max_lod = 1000.0,
        .enable_anisotropy = false,
        .enable_compare = false,
        .props = 0,
    };

    self.linear_sampler = c.SDL_CreateGPUSampler(self.device, &linear_sampler_info) orelse {
        log.err("Failed to create linear sampler: {s}", .{c.SDL_GetError()});
        return error.SamplerCreationFailed;
    };

    // Create nearest sampler
    const nearest_sampler_info = c.SDL_GPUSamplerCreateInfo{
        .min_filter = c.SDL_GPU_FILTER_NEAREST,
        .mag_filter = c.SDL_GPU_FILTER_NEAREST,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .mip_lod_bias = 0.0,
        .max_anisotropy = 1.0,
        .compare_op = c.SDL_GPU_COMPAREOP_NEVER,
        .min_lod = 0.0,
        .max_lod = 1000.0,
        .enable_anisotropy = false,
        .enable_compare = false,
        .props = 0,
    };

    self.nearest_sampler = c.SDL_CreateGPUSampler(self.device, &nearest_sampler_info) orelse {
        log.err("Failed to create nearest sampler: {s}", .{c.SDL_GetError()});
        return error.SamplerCreationFailed;
    };

    log.info("Samplers created successfully", .{});
}

const SDL_ERROR = bool;
const SDL_SUCCESS: SDL_ERROR = true;
inline fn toErr(res: SDL_ERROR, what: []const u8) !void {
    if (res == SDL_SUCCESS) return;
    return logErr(what);
}

inline fn logErr(what: []const u8) dvui.Backend.GenericError {
    log.err("{s} failed, error={s}", .{ what, c.SDL_GetError() });
    return dvui.Backend.GenericError.BackendError;
}

pub fn setIconFromFileContent(self: *SDLBackend, file_content: []const u8) !void {
    var icon_w: c_int = undefined;
    var icon_h: c_int = undefined;
    var channels_in_file: c_int = undefined;
    const data = dvui.c.stbi_load_from_memory(file_content.ptr, @as(c_int, @intCast(file_content.len)), &icon_w, &icon_h, &channels_in_file, 4);
    if (data == null) {
        log.warn("when setting icon, stbi_load error: {s}", .{dvui.c.stbi_failure_reason()});
        return dvui.StbImageError.stbImageError;
    }
    defer dvui.c.stbi_image_free(data);
    try self.setIconFromABGR8888(data, icon_w, icon_h);
}

pub fn setIconFromABGR8888(self: *SDLBackend, data: [*]const u8, icon_w: c_int, icon_h: c_int) !void {
    const surface =
        c.SDL_CreateSurfaceFrom(
            icon_w,
            icon_h,
            c.SDL_PIXELFORMAT_ABGR8888,
            @ptrCast(@constCast(data)),
            4 * icon_w,
        ) orelse return logErr("SDL_CreateSurfaceFrom in setIconFromABGR8888");
    defer c.SDL_DestroySurface(surface);

    // `toErr` logs the error for us
    toErr(c.SDL_SetWindowIcon(self.window, surface), "SDL_SetWindowIcon in setIconFromABGR8888") catch {};
}

pub fn accessKitShouldInitialize(self: *SDLBackend) bool {
    return self.ak_should_initialized;
}
pub fn accessKitInitInBegin(self: *SDLBackend) !void {
    std.debug.assert(self.ak_should_initialized);
    try toErr(c.SDL_ShowWindow(self.window), "SDL_ShowWindow in accessKitInitInBegin");
    self.ak_should_initialized = false;
}

/// Return true if interrupted by event
pub fn waitEventTimeout(_: *SDLBackend, timeout_micros: u32) !bool {
    if (timeout_micros == std.math.maxInt(u32)) {
        // wait no timeout
        _ = c.SDL_WaitEvent(null);
        return false;
    }

    if (timeout_micros > 0) {
        // wait with a timeout
        const timeout = @min((timeout_micros + 999) / 1000, std.math.maxInt(c_int));
        var ret: bool = undefined;
        ret = c.SDL_WaitEventTimeout(null, @as(c_int, @intCast(timeout)));

        // TODO: this call to SDL_PollEvent can be removed after resolution of
        // https://github.com/libsdl-org/SDL/issues/6539
        // maintaining this a little longer for people with older SDL versions
        _ = c.SDL_PollEvent(null);

        return ret;
    }

    // don't wait at all
    return false;
}

pub fn cursorShow(_: *SDLBackend, value: ?bool) !bool {
    const prev = c.SDL_CursorVisible();
    if (value) |val| {
        if (val) {
            if (!c.SDL_ShowCursor()) {
                return logErr("SDL_ShowCursor in cursorShow");
            }
        } else {
            if (!c.SDL_HideCursor()) {
                return logErr("SDL_HideCursor in cursorShow");
            }
        }
    }
    return prev;
}

pub fn native(self: *SDLBackend, _: *dvui.Window) dvui.Window.Native {
    const props: c.SDL_PropertiesID = c.SDL_GetWindowProperties(self.window);
    switch (builtin.os.tag) {
        .windows => return .{ .hwnd = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_WIN32_HWND_POINTER, null) },
        .macos => return .{ .cocoa_window = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null) },
        else => return {},
    }
}

pub fn refresh(_: *SDLBackend) void {
    var ue = std.mem.zeroes(c.SDL_Event);
    ue.type = c.SDL_EVENT_USER;
    toErr(c.SDL_PushEvent(&ue), "SDL_PushEvent in refresh") catch {};
}

pub fn addAllEvents(self: *SDLBackend, win: *dvui.Window) !bool {
    //const flags = c.SDL_GetWindowFlags(self.window);
    //if (flags & c.SDL_WINDOW_MOUSE_FOCUS == 0 and flags & c.SDL_WINDOW_INPUT_FOCUS == 0) {
    //std.debug.print("bailing\n", .{});
    //}
    var event: c.SDL_Event = undefined;
    const poll_got_event = true;
    while (c.SDL_PollEvent(&event) == poll_got_event) {
        _ = try self.addEvent(win, event);
        switch (event.type) {
            c.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            c.SDL_EVENT_QUIT,
            => return true,
            // TODO: revisit with sdl3
            //c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED => {
            //std.debug.print("sdl window scale changed event\n", .{});
            //},
            //c.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED => {
            //std.debug.print("sdl display scale changed event\n", .{});
            //},
            else => {},
        }
    }

    return false;
}

pub fn setCursor(self: *SDLBackend, cursor: dvui.enums.Cursor) !void {
    if (cursor == self.cursor_last) return;
    defer self.cursor_last = cursor;
    const new_shown_state = if (cursor == .hidden) false else if (self.cursor_last == .hidden) true else null;
    if (new_shown_state) |new_state| {
        if (try self.cursorShow(new_state) == new_state) {
            log.err("Cursor shown state was out of sync", .{});
        }
        // Return early if we are hiding
        if (new_state == false) return;
    }

    const enum_int = @intFromEnum(cursor);
    const tried = self.cursor_backing_tried[enum_int];
    if (!tried) {
        self.cursor_backing_tried[enum_int] = true;
        self.cursor_backing[enum_int] = switch (cursor) {
            .arrow => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_DEFAULT),
            .ibeam => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_TEXT),
            .wait => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT),
            .wait_arrow => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_PROGRESS),
            .crosshair => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR),
            .arrow_nw_se => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NWSE_RESIZE),
            .arrow_ne_sw => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NESW_RESIZE),
            .arrow_w_e => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_EW_RESIZE),
            .arrow_n_s => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NS_RESIZE),
            .arrow_all => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_MOVE),
            .bad => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_NOT_ALLOWED),
            .hand => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_POINTER),
            .hidden => unreachable,
        };
    }

    if (self.cursor_backing[enum_int]) |cur| {
        try toErr(c.SDL_SetCursor(cur), "SDL_SetCursor in setCursor");
    } else {
        log.err("setCursor \"{s}\" failed", .{@tagName(cursor)});
        return logErr("SDL_CreateSystemCursor in setCursor");
    }
}

pub fn textInputRect(self: *SDLBackend, rect: ?dvui.Rect.Natural) !void {
    if (rect) |r| {
        // This is the offset from r.x in window coords, supposed to be the
        // location of the cursor I think so that the IME window can be put
        // at the cursor location.  We will use 0 for now, might need to
        // change it (or how we determine rect) if people are using huge
        // text entries).
        const cursor = 0;

        try toErr(c.SDL_SetTextInputArea(
            self.window,
            &c.SDL_Rect{
                .x = @intFromFloat(r.x),
                .y = @intFromFloat(r.y),
                .w = @intFromFloat(r.w),
                .h = @intFromFloat(r.h),
            },
            cursor,
        ), "SDL_SetTextInputArea in textInputRect");
        try toErr(c.SDL_StartTextInput(self.window), "SDL_StartTextInput in textInputRect");
    } else {
        try toErr(c.SDL_StopTextInput(self.window), "SDL_StopTextInput in textInputRect");
    }
}

pub fn deinit(self: *SDLBackend) void {
    for (self.cursor_backing) |cursor| {
        if (cursor) |cur| {
            c.SDL_DestroyCursor(cur);
        }
    }

    // Clean up rect uploads (always needed)
    self.frame_uploads.deinit(self.device);

    c.SDL_ReleaseGPUTexture(self.device, self.white_texture.texture);
    c.SDL_ReleaseGPUSampler(self.device, self.linear_sampler);
    c.SDL_ReleaseGPUSampler(self.device, self.nearest_sampler);

    c.SDL_ReleaseGPUTransferBuffer(self.device, self.texture_transfer_buffer);

    if (self.we_own_window) {
        // Release GPU resources
        c.SDL_ReleaseGPUGraphicsPipeline(self.device, self.swapchain_pipeline);
        c.SDL_ReleaseGPUGraphicsPipeline(self.device, self.rendertarget_pipeline);

        c.SDL_DestroyGPUDevice(self.device);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    } else if (self.destroyDeviceOnExit) {
        c.SDL_DestroyGPUDevice(self.device);
    }

    // Clean up textures arena (always needed)
    self.textures_arena.deinit();
    log.info("sdl3gpu backend deinitialized", .{});
    self.* = undefined;
}

pub fn backend(self: *SDLBackend) dvui.Backend {
    return dvui.Backend.init(self);
}

pub fn nanoTime(_: *SDLBackend) i128 {
    return std.time.nanoTimestamp();
}

pub fn sleep(_: *SDLBackend, ns: u64) void {
    std.Thread.sleep(ns);
}

pub fn clipboardText(self: *SDLBackend) ![]const u8 {
    const p = c.SDL_GetClipboardText();
    defer c.SDL_free(p); // must free even on error

    const str = std.mem.span(p);
    // Log error, but don't fail the application
    if (str.len == 0) logErr("SDL_GetClipboardText in clipboardText") catch {};

    return try self.arena.dupe(u8, str);
}

pub fn clipboardTextSet(self: *SDLBackend, text: []const u8) !void {
    if (text.len == 0) return;
    const c_text = try self.arena.dupeZ(u8, text);
    defer self.arena.free(c_text);
    try toErr(c.SDL_SetClipboardText(c_text.ptr), "SDL_SetClipboardText in clipboardTextSet");
}

pub fn openURL(self: *SDLBackend, url: []const u8, _: bool) !void {
    const c_url = try self.arena.dupeZ(u8, url);
    defer self.arena.free(c_url);
    try toErr(c.SDL_OpenURL(c_url.ptr), "SDL_OpenURL in openURL");
}

pub fn preferredColorScheme(_: *SDLBackend) ?dvui.enums.ColorScheme {
    return switch (c.SDL_GetSystemTheme()) {
        c.SDL_SYSTEM_THEME_DARK => .dark,
        c.SDL_SYSTEM_THEME_LIGHT => .light,
        else => null,
    };
}

pub fn begin(self: *SDLBackend, arena: std.mem.Allocator) !void {
    self.arena = arena;
    self.frame_uploads.reset();
    if (self.cmd != null) {
        self.external_cmdbuffer = true;
        return;
    }

    self.external_cmdbuffer = false;

    // Acquire command buffer for this frame
    self.cmd = c.SDL_AcquireGPUCommandBuffer(self.device);
    if (self.cmd == null) {
        log.err("Failed to acquire GPU command buffer: {s}", .{c.SDL_GetError()});
        return error.BackendError;
    }

    // Acquire swapchain texture for this frame
    var swapchain_w: u32 = 0;
    var swapchain_h: u32 = 0;
    if (!c.SDL_WaitAndAcquireGPUSwapchainTexture(self.cmd.?, self.window, &self.swapchain_texture, &swapchain_w, &swapchain_h)) {
        log.err("Failed to acquire swapchain texture: {s}", .{c.SDL_GetError()});
        _ = c.SDL_SubmitGPUCommandBuffer(self.cmd);
        self.cmd = null;
        self.swapchain_texture = null;
        return;
    }
}

pub fn finishRenderingCurrentTarget(self: *SDLBackend, final: bool) !void {
    if (self.current_render_target == null) {
        if (!final) {
            self.frame_uploads.reset();
            return;
        }
    }

    // Begin copy pass for uploading vertex/index data
    self.frame_uploads.copy_pass = c.SDL_BeginGPUCopyPass(self.cmd.?) orelse {
        log.err("Failed to begin GPU copy pass: {s}", .{c.SDL_GetError()});
        return error.BackendError;
    };

    self.frame_uploads.addUploads();

    // End copy pass (all uploads must be done before rendering starts)
    if (self.frame_uploads.copy_pass) |copy_pass| {
        c.SDL_EndGPUCopyPass(copy_pass);
        self.frame_uploads.copy_pass = null;
    }

    var color_target = std.mem.zeroes(c.SDL_GPUColorTargetInfo);
    color_target.texture = if (self.current_render_target == null) self.swapchain_texture else self.current_render_target.?.texture;
    color_target.clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = if (self.current_render_target == null) 1.0 else 0.0 };
    color_target.load_op = if (self.current_render_target == null) c.SDL_GPU_LOADOP_LOAD else c.SDL_GPU_LOADOP_CLEAR;
    color_target.store_op = c.SDL_GPU_STOREOP_STORE;

    self.current_render_pass = c.SDL_BeginGPURenderPass(self.cmd.?, &color_target, 1, null);
    if (self.current_render_pass == null) {
        log.err("Failed to begin GPU render pass: {s}", .{c.SDL_GetError()});
        return error.BackendError;
    }

    // Iterate over frame_uploads and bind and render every draw call
    var vertexBuffer: c.SDL_GPUBufferBinding = .{ .buffer = self.frame_uploads.vertex.buffer, .offset = 0 };
    var indexBuffer: c.SDL_GPUBufferBinding = .{ .buffer = self.frame_uploads.index.buffer, .offset = 0 };

    if (self.current_render_target == null) {
        c.SDL_BindGPUGraphicsPipeline(self.current_render_pass, self.swapchain_pipeline);
    } else {
        c.SDL_BindGPUGraphicsPipeline(self.current_render_pass, self.rendertarget_pipeline);
    }
    c.SDL_BindGPUVertexBuffers(self.current_render_pass, 0, &vertexBuffer, 1);
    c.SDL_BindGPUIndexBuffer(self.current_render_pass, &indexBuffer, IndexElementSize);

    var screenScissor = c.SDL_Rect{
        .x = 0,
        .y = 0,
        .h = @intFromFloat(self.last_pixel_size.h),
        .w = @intFromFloat(self.last_pixel_size.w),
    };

    for (self.frame_uploads.draws.items, 0..) |draw, i| {
        var binding = c.SDL_GPUTextureSamplerBinding{
            .texture = draw.texture.texture,
            .sampler = draw.texture.sampler,
        };

        if (draw.scissor) |*scissor| {
            c.SDL_SetGPUScissor(self.current_render_pass, scissor);
        } else {
            c.SDL_SetGPUScissor(self.current_render_pass, &screenScissor);
        }

        c.SDL_BindGPUFragmentSamplers(self.current_render_pass, 0, &binding, 1);
        c.SDL_DrawGPUIndexedPrimitives(self.current_render_pass, draw.index_count, 1, draw.index_start, 0, @intCast(i));
    }

    // End the render pass
    if (self.current_render_pass) |pass| {
        c.SDL_EndGPURenderPass(pass);
        self.current_render_pass = null;
    }

    self.frame_uploads.reset();
}

pub fn end(self: *SDLBackend) !void {
    try self.finishRenderingCurrentTarget(true);
}

pub fn renderPresent(self: *SDLBackend) !void {
    if (self.cmd != null and self.external_cmdbuffer == false) {
        // Submit the command buffer
        const submitted = c.SDL_SubmitGPUCommandBuffer(self.cmd);
        if (!submitted) {
            log.err("Failed to submit GPU command buffer: {s}", .{c.SDL_GetError()});
            return error.CommandBufferSubmissionFailed;
        }
    }
    self.external_cmdbuffer = false;
    self.cmd = null;
    self.swapchain_texture = null;
}

pub fn pixelSize(self: *SDLBackend) dvui.Size.Physical {
    var w: i32 = undefined;
    var h: i32 = undefined;

    toErr(c.SDL_GetWindowSizeInPixels(self.window, &w, &h), "SDL_GetWindowSizeInPixels in pixelSize") catch return self.last_pixel_size;
    self.last_pixel_size = .{ .w = @floatFromInt(w), .h = @floatFromInt(h) };
    return self.last_pixel_size;
}

pub fn windowSize(self: *SDLBackend) dvui.Size.Natural {
    var w: i32 = undefined;
    var h: i32 = undefined;
    toErr(c.SDL_GetWindowSize(self.window, &w, &h), "SDL_GetWindowSize in windowSize") catch return self.last_window_size;
    self.last_window_size = .{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
    return self.last_window_size;
}

pub fn contentScale(self: *SDLBackend) f32 {
    return self.initial_scale;
}

pub fn drawClippedTriangles(self: *SDLBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, maybe_clipr: ?dvui.Rect.Physical) !void {
    const clip = if (maybe_clipr) |clipr| c.SDL_Rect{
        .x = @intFromFloat(clipr.x),
        .y = @intFromFloat(clipr.y),
        .w = @intFromFloat(clipr.w),
        .h = @intFromFloat(clipr.h),
    } else null;

    var backendTexture: ?*BackendTexture = null;

    if (texture) |t| {
        backendTexture = @ptrCast(@alignCast(t.ptr));
    }

    self.frame_uploads.push(self, backendTexture, vtx, idx, clip) catch {
        log.err("out of buffer size", .{});
        return error.BackendError;
    };
}

pub fn createTextureTransferBuffer(self: *SDLBackend) !void {
    self.texture_transfer_buffer_size = max_texture_size;

    self.texture_transfer_buffer = c.SDL_CreateGPUTransferBuffer(
        self.device,
        &c.SDL_GPUTransferBufferCreateInfo{
            .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = self.texture_transfer_buffer_size,
            .props = 0,
        },
    ) orelse {
        log.err("Failed to create transfer buffer: {s}", .{c.SDL_GetError()});
        return error.TransferBufferCreationFailed;
    };

    log.info("Transfer buffer created: {} bytes", .{self.texture_transfer_buffer_size});
}

pub fn textureCreate(self: *SDLBackend, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) !dvui.Texture {
    if (format != .rgba_32) {
        log.err("textureCreate currently only supports pixel format .rgba_32", .{});
        return dvui.Backend.TextureError.TextureCreate;
    }

    // 1. Create GPU texture
    const texture = c.SDL_CreateGPUTexture(
        self.device,
        &c.SDL_GPUTextureCreateInfo{
            .type = c.SDL_GPU_TEXTURETYPE_2D,
            .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
            .props = 0,
        },
    ) orelse {
        log.err("Failed to create GPU texture: {s}", .{c.SDL_GetError()});
        return error.TextureCreate;
    };
    errdefer c.SDL_ReleaseGPUTexture(self.device, texture);

    // 4. Upload to GP   // 3. Map and copy pixel data to shared transfer buffer
    const mapped = c.SDL_MapGPUTransferBuffer(
        self.device,
        self.texture_transfer_buffer,
        false,
    ) orelse {
        log.err("Failed to map transfer buffer: {s}", .{c.SDL_GetError()});
        return error.TextureCreate;
    };

    @memcpy(
        @as([*]u8, @ptrCast(mapped))[0 .. width * height * 4],
        pixels[0 .. width * height * 4],
    );
    c.SDL_UnmapGPUTransferBuffer(self.device, self.texture_transfer_buffer);

    // 4. Upload to GPU
    const cmd_buffer = c.SDL_AcquireGPUCommandBuffer(self.device) orelse {
        log.err("Failed to acquire command buffer for texture upload: {s}", .{c.SDL_GetError()});
        return error.TextureCreate;
    };

    const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buffer) orelse {
        log.err("Failed to begin copy pass: {s}", .{c.SDL_GetError()});
        return error.TextureCreate;
    };

    c.SDL_UploadToGPUTexture(
        copy_pass,
        &c.SDL_GPUTextureTransferInfo{
            .transfer_buffer = self.texture_transfer_buffer,
            .offset = 0,
            .pixels_per_row = width,
            .rows_per_layer = height,
        },
        &c.SDL_GPUTextureRegion{
            .texture = texture,
            .mip_level = 0,
            .layer = 0,
            .x = 0,
            .y = 0,
            .z = 0,
            .w = width,
            .h = height,
            .d = 1,
        },
        false,
    );

    c.SDL_EndGPUCopyPass(copy_pass);

    const fence = c.SDL_SubmitGPUCommandBufferAndAcquireFence(cmd_buffer);
    if (fence == null) {
        log.err("Failed to submit command buffer for texture upload: {s}", .{c.SDL_GetError()});
        return error.TextureCreate;
    }
    defer c.SDL_ReleaseGPUFence(self.device, fence);

    _ = c.SDL_WaitForGPUFences(self.device, true, &fence, 1);

    // 5. Allocate BackendTexture from arena and set sampler
    const backendTexture = try self.textures_arena.allocator().create(BackendTexture);

    backendTexture.* = .{
        .texture = texture,
        .sampler = switch (interpolation) {
            .linear => self.linear_sampler,
            .nearest => self.nearest_sampler,
        },
    };

    // log.info("texture created size {d}x{d} 0x{x}", .{ width, height, @intFromPtr(backendTexture.texture) });

    return dvui.Texture{
        .ptr = backendTexture,
        .width = width,
        .height = height,
        .format = format,
    };
}

// render target for textures
const BackendTextureTarget = struct {
    texture: *c.SDL_GPUTexture,
    sampler: *c.SDL_GPUSampler, // points to either linear_sampler or nearest_sampler
};

pub fn textureCreateTarget(self: *SDLBackend, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation, format: dvui.enums.TexturePixelFormat) !dvui.TextureTarget {
    if (format != .rgba_32) {
        log.err("textureCreateTarget currently only supports pixel format .rgba_32", .{});
        return dvui.Backend.TextureError.TextureCreate;
    }

    // 1. Create GPU texture
    const texture = c.SDL_CreateGPUTexture(
        self.device,
        &c.SDL_GPUTextureCreateInfo{
            .type = c.SDL_GPU_TEXTURETYPE_2D,
            .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER | c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
            .props = 0,
        },
    ) orelse {
        log.err("Failed to create GPU texture: {s}", .{c.SDL_GetError()});
        return error.TextureCreate;
    };
    errdefer c.SDL_ReleaseGPUTexture(self.device, texture);

    // 5. Allocate BackendTexture from arena and set sampler
    const backendTexture = try self.textures_arena.allocator().create(BackendTextureTarget);

    backendTexture.* = .{
        .texture = texture,
        .sampler = switch (interpolation) {
            .linear => self.linear_sampler,
            .nearest => self.nearest_sampler,
        },
    };

    return dvui.TextureTarget{
        .ptr = backendTexture,
        .width = width,
        .height = height,
        .format = format,
    };
}

pub fn renderTarget(self: *SDLBackend, dvuiTarget: ?dvui.TextureTarget) !void {
    try self.finishRenderingCurrentTarget(false);

    if (dvuiTarget) |dt| {
        const target: *BackendTextureTarget = @ptrCast(@alignCast(dt.ptr));
        self.current_render_target = target;
        self.current_render_target_size = .{ .h = @floatFromInt(dt.height), .w = @floatFromInt(dt.width) };
    } else {
        self.current_render_target = null;
        self.current_render_target_size = null;
    }
}

pub fn textureReadTarget(self: *SDLBackend, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    _ = self;
    _ = pixels_out;
    log.info("trying to read 0x{x} not implemented", .{@intFromPtr(texture.ptr)});

    return error.BackendError;
}

pub fn textureDestroy(self: *SDLBackend, texture: dvui.Texture) void {
    const backendTexture: *BackendTexture = @ptrCast(@alignCast(texture.ptr));
    // log.info("texture destroyed {d}x{d} 0x{x}", .{
    //     texture.width,
    //     texture.height,
    //     @intFromPtr(backendTexture.texture),
    // });
    c.SDL_ReleaseGPUTexture(self.device, backendTexture.texture);
    // Note: backendTexture itself is allocated from textures_arena and will be freed when arena is reset/deinit
    // Samplers are shared and will be released in deinit()
}

pub fn textureFromTarget(_: *SDLBackend, texture: dvui.TextureTarget) !dvui.Texture {
    return .{ .ptr = texture.ptr, .width = texture.width, .height = texture.height, .format = texture.format };
}

pub fn addEvent(self: *SDLBackend, win: *dvui.Window, event: c.SDL_Event) !bool {
    switch (event.type) {
        c.SDL_EVENT_KEY_DOWN => {
            const sdl_key: i32 = @intCast(event.key.key);
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(@intCast(event.key.mod));
            if (self.log_events) {
                log.debug("event KEYDOWN {any} {s} {any} {any}\n", .{ sdl_key, @tagName(code), mod, event.key.repeat });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = if (event.key.repeat) .repeat else .down,
                .mod = mod,
            });
        },

        c.SDL_EVENT_KEY_UP => {
            const sdl_key: i32 = @intCast(event.key.key);
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(@intCast(event.key.mod));
            if (self.log_events) {
                log.debug("event KEYUP {any} {s} {any}\n", .{ sdl_key, @tagName(code), mod });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = .up,
                .mod = mod,
            });
        },
        c.SDL_EVENT_TEXT_INPUT => {
            const txt = std.mem.sliceTo(event.text.text, 0);
            if (self.log_events) {
                log.debug("event TEXTINPUT {s}\n", .{txt});
            }

            return try win.addEventText(.{ .text = txt });
        },
        c.SDL_EVENT_TEXT_EDITING => {
            const strlen: u8 = @intCast(c.SDL_strlen(event.edit.text));
            if (self.log_events) {
                log.debug("event TEXTEDITING {s} start {d} len {d} strlen {d}\n", .{ event.edit.text, event.edit.start, event.edit.length, strlen });
            }
            return try win.addEventText(.{ .text = event.edit.text[0..strlen], .selected = true });
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEMOTION {d} {d}\n", .{ touch_str, event.motion.x, event.motion.y });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            // sdl gives us mouse coords in "window coords" which is kind of
            // like natural coords but ignores content scaling
            const scale = self.pixelSize().w / self.windowSize().w;

            return try win.addEventMouseMotion(.{
                .pt = .{
                    .x = event.motion.x * scale,
                    .y = event.motion.y * scale,
                },
            });
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEBUTTONDOWN {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDL_mouse_button_to_dvui(event.button.button), .press);
        },
        c.SDL_EVENT_MOUSE_BUTTON_UP => {
            const touch = event.motion.which == c.SDL_TOUCH_MOUSEID;
            if (self.log_events) {
                var touch_str: []const u8 = " ";
                if (touch) touch_str = " touch ";
                if (touch and !self.touch_mouse_events) touch_str = " touch ignored ";
                log.debug("event{s}MOUSEBUTTONUP {d}\n", .{ touch_str, event.button.button });
            }

            if (touch and !self.touch_mouse_events) {
                return false;
            }

            return try win.addEventMouseButton(SDL_mouse_button_to_dvui(event.button.button), .release);
        },
        c.SDL_EVENT_MOUSE_WHEEL => {
            // .precise added in 2.0.18
            const ticks_x = event.wheel.x;
            const ticks_y = event.wheel.y;

            if (self.log_events) {
                log.debug("event MOUSEWHEEL {d} {d} {d}\n", .{ ticks_x, ticks_y, event.wheel.which });
            }

            var ret = false;
            if (ticks_x != 0) ret = try win.addEventMouseWheel(ticks_x * dvui.scroll_speed, .horizontal);
            if (ticks_y != 0) ret = try win.addEventMouseWheel(ticks_y * dvui.scroll_speed, .vertical);
            return ret;
        },
        c.SDL_EVENT_FINGER_DOWN => {
            if (self.log_events) {
                log.debug("event FINGERDOWN {d} {d} {d}\n", .{ event.tfinger.fingerID, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.{ .button = .touch0, .action = .press, .xynorm = .{ .x = event.tfinger.x, .y = event.tfinger.y } });
        },
        c.SDL_EVENT_FINGER_UP => {
            if (self.log_events) {
                log.debug("event FINGERUP {d} {d} {d}\n", .{ event.tfinger.fingerID, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.{ .button = .touch0, .action = .release, .xynorm = .{ .x = event.tfinger.x, .y = event.tfinger.y } });
        },
        c.SDL_EVENT_FINGER_MOTION => {
            if (self.log_events) {
                log.debug("event FINGERMOTION {d} {d} {d} {d} {d}\n", .{ event.tfinger.fingerID, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy });
            }

            return try win.addEventTouchMotion(.touch0, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy);
        },
        c.SDL_EVENT_WINDOW_FOCUS_GAINED => {
            if (self.log_events) {
                log.debug("event FOCUS_GAINED\n", .{});
            }
            if (dvui.accesskit_enabled and builtin.os.tag == .linux) {
                dvui.AccessKit.c.accesskit_unix_adapter_update_window_focus_state(win.accesskit.adapter, true);
            } else if (dvui.accesskit_enabled and builtin.os.tag == .macos) {
                const events = dvui.AccessKit.c.accesskit_macos_subclassing_adapter_update_view_focus_state(win.accesskit.adapter, true);
                if (events) |evts| {
                    dvui.AccessKit.c.accesskit_macos_queued_events_raise(evts);
                }
            }
            return false;
        },
        c.SDL_EVENT_WINDOW_FOCUS_LOST => {
            if (self.log_events) {
                log.debug("event FOCUS_LOST\n", .{});
            }
            if (dvui.accesskit_enabled and builtin.os.tag == .linux) {
                dvui.AccessKit.c.accesskit_unix_adapter_update_window_focus_state(win.accesskit.adapter, false);
            } else if (dvui.accesskit_enabled and builtin.os.tag == .macos) {
                const events = dvui.AccessKit.c.accesskit_macos_subclassing_adapter_update_view_focus_state(win.accesskit.adapter, false);
                if (events) |evts| {
                    dvui.AccessKit.c.accesskit_macos_queued_events_raise(evts);
                }
            }
            return false;
        },
        c.SDL_EVENT_WINDOW_SHOWN => {
            if (self.log_events) {
                log.debug("event WINDOW_SHOWN\n", .{});
            }
            if (dvui.accesskit_enabled and builtin.os.tag == .linux) {
                var x: i32, var y: i32 = .{ undefined, undefined };
                _ = c.SDL_GetWindowPosition(win.backend.impl.window, &x, &y);
                var w: i32, var h: i32 = .{ undefined, undefined };
                _ = c.SDL_GetWindowSize(win.backend.impl.window, &w, &h);
                var top: i32, var bot: i32, var left: i32, var right: i32 = .{ undefined, undefined, undefined, undefined };
                _ = c.SDL_GetWindowBordersSize(win.backend.impl.window, &top, &left, &bot, &right);
                const outer_bounds: dvui.AccessKit.Rect = .{ .x0 = @floatFromInt(x - left), .y0 = @floatFromInt(y - top), .x1 = @floatFromInt(x + w + right), .y1 = @floatFromInt(y + h + bot) };
                const inner_bounds: dvui.AccessKit.Rect = .{ .x0 = @floatFromInt(x), .y0 = @floatFromInt(y), .x1 = @floatFromInt(x + w), .y1 = @floatFromInt(y + h) };
                dvui.AccessKit.c.accesskit_unix_adapter_set_root_window_bounds(win.accesskit.adapter.?, outer_bounds, inner_bounds);
            }
            return false;
        },
        c.SDL_EVENT_QUIT => {
            try win.addEventApp(.{ .action = .quit });
            return false;
        },
        else => {
            if (self.log_events) {
                log.debug("unhandled SDL event type {any}\n", .{event.type});
            }
            return false;
        },
    }
}

pub fn SDL_mouse_button_to_dvui(button: u8) dvui.enums.Button {
    return switch (button) {
        c.SDL_BUTTON_LEFT => .left,
        c.SDL_BUTTON_MIDDLE => .middle,
        c.SDL_BUTTON_RIGHT => .right,
        c.SDL_BUTTON_X1 => .four,
        c.SDL_BUTTON_X2 => .five,
        else => blk: {
            log.debug("SDL_mouse_button_to_dvui.unknown button {d}", .{button});
            break :blk .six;
        },
    };
}

pub fn SDL_keymod_to_dvui(keymod: u16) dvui.enums.Mod {
    if (keymod == c.SDL_KMOD_NONE) return dvui.enums.Mod.none;

    var m: u16 = 0;
    if (keymod & (c.SDL_KMOD_LSHIFT) > 0) m |= @intFromEnum(dvui.enums.Mod.lshift);
    if (keymod & (c.SDL_KMOD_RSHIFT) > 0) m |= @intFromEnum(dvui.enums.Mod.rshift);
    if (keymod & (c.SDL_KMOD_LCTRL) > 0) m |= @intFromEnum(dvui.enums.Mod.lcontrol);
    if (keymod & (c.SDL_KMOD_RCTRL) > 0) m |= @intFromEnum(dvui.enums.Mod.rcontrol);
    if (keymod & (c.SDL_KMOD_LALT) > 0) m |= @intFromEnum(dvui.enums.Mod.lalt);
    if (keymod & (c.SDL_KMOD_RALT) > 0) m |= @intFromEnum(dvui.enums.Mod.ralt);
    if (keymod & (c.SDL_KMOD_LGUI) > 0) m |= @intFromEnum(dvui.enums.Mod.lcommand);
    if (keymod & (c.SDL_KMOD_RGUI) > 0) m |= @intFromEnum(dvui.enums.Mod.rcommand);

    return @as(dvui.enums.Mod, @enumFromInt(m));
}

pub fn SDL_keysym_to_dvui(keysym: i32) dvui.enums.Key {
    return switch (keysym) {
        c.SDLK_A => .a,
        c.SDLK_B => .b,
        c.SDLK_C => .c,
        c.SDLK_D => .d,
        c.SDLK_E => .e,
        c.SDLK_F => .f,
        c.SDLK_G => .g,
        c.SDLK_H => .h,
        c.SDLK_I => .i,
        c.SDLK_J => .j,
        c.SDLK_K => .k,
        c.SDLK_L => .l,
        c.SDLK_M => .m,
        c.SDLK_N => .n,
        c.SDLK_O => .o,
        c.SDLK_P => .p,
        c.SDLK_Q => .q,
        c.SDLK_R => .r,
        c.SDLK_S => .s,
        c.SDLK_T => .t,
        c.SDLK_U => .u,
        c.SDLK_V => .v,
        c.SDLK_W => .w,
        c.SDLK_X => .x,
        c.SDLK_Y => .y,
        c.SDLK_Z => .z,

        c.SDLK_0 => .zero,
        c.SDLK_1 => .one,
        c.SDLK_2 => .two,
        c.SDLK_3 => .three,
        c.SDLK_4 => .four,
        c.SDLK_5 => .five,
        c.SDLK_6 => .six,
        c.SDLK_7 => .seven,
        c.SDLK_8 => .eight,
        c.SDLK_9 => .nine,

        c.SDLK_F1 => .f1,
        c.SDLK_F2 => .f2,
        c.SDLK_F3 => .f3,
        c.SDLK_F4 => .f4,
        c.SDLK_F5 => .f5,
        c.SDLK_F6 => .f6,
        c.SDLK_F7 => .f7,
        c.SDLK_F8 => .f8,
        c.SDLK_F9 => .f9,
        c.SDLK_F10 => .f10,
        c.SDLK_F11 => .f11,
        c.SDLK_F12 => .f12,

        c.SDLK_KP_DIVIDE => .kp_divide,
        c.SDLK_KP_MULTIPLY => .kp_multiply,
        c.SDLK_KP_MINUS => .kp_subtract,
        c.SDLK_KP_PLUS => .kp_add,
        c.SDLK_KP_ENTER => .kp_enter,
        c.SDLK_KP_0 => .kp_0,
        c.SDLK_KP_1 => .kp_1,
        c.SDLK_KP_2 => .kp_2,
        c.SDLK_KP_3 => .kp_3,
        c.SDLK_KP_4 => .kp_4,
        c.SDLK_KP_5 => .kp_5,
        c.SDLK_KP_6 => .kp_6,
        c.SDLK_KP_7 => .kp_7,
        c.SDLK_KP_8 => .kp_8,
        c.SDLK_KP_9 => .kp_9,
        c.SDLK_KP_PERIOD => .kp_decimal,

        c.SDLK_RETURN => .enter,
        c.SDLK_ESCAPE => .escape,
        c.SDLK_TAB => .tab,
        c.SDLK_LSHIFT => .left_shift,
        c.SDLK_RSHIFT => .right_shift,
        c.SDLK_LCTRL => .left_control,
        c.SDLK_RCTRL => .right_control,
        c.SDLK_LALT => .left_alt,
        c.SDLK_RALT => .right_alt,
        c.SDLK_LGUI => .left_command,
        c.SDLK_RGUI => .right_command,
        c.SDLK_MENU => .menu,
        c.SDLK_NUMLOCKCLEAR => .num_lock,
        c.SDLK_CAPSLOCK => .caps_lock,
        c.SDLK_PRINTSCREEN => .print,
        c.SDLK_SCROLLLOCK => .scroll_lock,
        c.SDLK_PAUSE => .pause,
        c.SDLK_DELETE => .delete,
        c.SDLK_HOME => .home,
        c.SDLK_END => .end,
        c.SDLK_PAGEUP => .page_up,
        c.SDLK_PAGEDOWN => .page_down,
        c.SDLK_INSERT => .insert,
        c.SDLK_LEFT => .left,
        c.SDLK_RIGHT => .right,
        c.SDLK_UP => .up,
        c.SDLK_DOWN => .down,
        c.SDLK_BACKSPACE => .backspace,
        c.SDLK_SPACE => .space,
        c.SDLK_MINUS => .minus,
        c.SDLK_EQUALS => .equal,
        c.SDLK_LEFTBRACKET => .left_bracket,
        c.SDLK_RIGHTBRACKET => .right_bracket,
        c.SDLK_BACKSLASH => .backslash,
        c.SDLK_SEMICOLON => .semicolon,
        c.SDLK_APOSTROPHE => .apostrophe,
        c.SDLK_COMMA => .comma,
        c.SDLK_PERIOD => .period,
        c.SDLK_SLASH => .slash,
        c.SDLK_GRAVE => .grave,

        else => blk: {
            log.debug("SDL_keysym_to_dvui unknown keysym {d}", .{keysym});
            break :blk .unknown;
        },
    };
}

pub fn getSDLVersion() std.SemanticVersion {
    const v: u32 = @bitCast(c.SDL_GetVersion());
    return .{
        .major = @divTrunc(v, 1000000),
        .minor = @mod(@divTrunc(v, 1000), 1000),
        .patch = @mod(v, 1000),
    };
}

fn sdlLogCallback(userdata: ?*anyopaque, category: c_int, priority: c_uint, message: [*c]const u8) callconv(.c) void {
    _ = userdata;
    switch (category) {
        c.SDL_LOG_CATEGORY_APPLICATION => sdlLog(.SDL_APPLICATION, priority, message),
        c.SDL_LOG_CATEGORY_ERROR => sdlLog(.SDL_ERROR, priority, message),
        c.SDL_LOG_CATEGORY_ASSERT => sdlLog(.SDL_ASSERT, priority, message),
        c.SDL_LOG_CATEGORY_SYSTEM => sdlLog(.SDL_SYSTEM, priority, message),
        c.SDL_LOG_CATEGORY_AUDIO => sdlLog(.SDL_AUDIO, priority, message),
        c.SDL_LOG_CATEGORY_VIDEO => sdlLog(.SDL_VIDEO, priority, message),
        c.SDL_LOG_CATEGORY_RENDER => sdlLog(.SDL_RENDER, priority, message),
        c.SDL_LOG_CATEGORY_INPUT => sdlLog(.SDL_INPUT, priority, message),
        c.SDL_LOG_CATEGORY_TEST => sdlLog(.SDL_TEST, priority, message),

        // These are the set of reserved categories that don't have fixed names between sdl2 and sdl3.
        // It's simpler to deal with them as a group because there is no easy way to remove a switch case at comptime
        c.SDL_LOG_CATEGORY_TEST + 1...c.SDL_LOG_CATEGORY_CUSTOM - 1 => if (category == c.SDL_LOG_CATEGORY_GPU)
            sdlLog(.SDL_GPU, priority, message)
        else
            sdlLog(.SDL_RESERVED, priority, message),

        // starting from c.SDL_LOG_CATEGORY_CUSTOM any greater values are all custom categories
        else => sdlLog(.SDL_CUSTOM, priority, message),
    }
}

fn sdlLog(comptime category: @Type(.enum_literal), priority: c_uint, message: [*c]const u8) void {
    const logger = std.log.scoped(category);
    switch (priority) {
        c.SDL_LOG_PRIORITY_VERBOSE => logger.debug("VERBOSE: {s}", .{message}),
        c.SDL_LOG_PRIORITY_DEBUG => logger.debug("{s}", .{message}),
        c.SDL_LOG_PRIORITY_INFO => logger.info("{s}", .{message}),
        c.SDL_LOG_PRIORITY_WARN => logger.warn("{s}", .{message}),
        c.SDL_LOG_PRIORITY_ERROR => logger.err("{s}", .{message}),
        c.SDL_LOG_PRIORITY_CRITICAL => logger.err("CRITICAL: {s}", .{message}),
        else => if (priority == c.SDL_LOG_PRIORITY_TRACE)
            logger.debug("TRACE: {s}", .{message})
        else
            logger.err("UNKNOWN: {s}", .{message}),
    }
}

/// This set enables the internal logging of SDL based on the level of std.log (and the SDL_... scopes)
pub fn enableSDLLogging() void {
    c.SDL_SetLogOutputFunction(&sdlLogCallback, null);

    // Set default log level
    const default_log_level: c.SDL_LogPriority = if (std.log.logEnabled(.debug, .SDLBackend))
        c.SDL_LOG_PRIORITY_VERBOSE
    else if (std.log.logEnabled(.info, .SDLBackend))
        c.SDL_LOG_PRIORITY_INFO
    else if (std.log.logEnabled(.warn, .SDLBackend))
        c.SDL_LOG_PRIORITY_WARN
    else
        c.SDL_LOG_PRIORITY_ERROR;

    c.SDL_SetLogPriorities(default_log_level);

    const categories = [_]struct { c_uint, @Type(.enum_literal) }{
        .{ c.SDL_LOG_CATEGORY_APPLICATION, .SDL_APPLICATION },
        .{ c.SDL_LOG_CATEGORY_ERROR, .SDL_ERROR },
        .{ c.SDL_LOG_CATEGORY_ASSERT, .SDL_ASSERT },
        .{ c.SDL_LOG_CATEGORY_SYSTEM, .SDL_SYSTEM },
        .{ c.SDL_LOG_CATEGORY_AUDIO, .SDL_AUDIO },
        .{ c.SDL_LOG_CATEGORY_VIDEO, .SDL_VIDEO },
        .{ c.SDL_LOG_CATEGORY_RENDER, .SDL_RENDER },
        .{ c.SDL_LOG_CATEGORY_INPUT, .SDL_INPUT },
        .{ c.SDL_LOG_CATEGORY_TEST, .SDL_TEST },
        .{ c.SDL_LOG_CATEGORY_GPU, .SDL_GPU },
    };

    inline for (categories) |category_data| {
        const category, const scope = category_data;
        for (std.options.log_scope_levels) |scope_level| {
            if (scope_level.scope == scope) {
                const log_level: c.SDL_LogPriority = switch (scope_level.level) {
                    .debug => c.SDL_LOG_PRIORITY_VERBOSE,
                    .info => c.SDL_LOG_PRIORITY_INFO,
                    .warn => c.SDL_LOG_PRIORITY_WARN,
                    .err => c.SDL_LOG_PRIORITY_ERROR,
                };
                c.SDL_SetLogPriority(category, log_level);
                break;
            }
        }
    }
}

/// This is what is run if you are using `dvui.App` with this backend.
pub fn main() !u8 {
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;

    if (builtin.os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    enableSDLLogging();

    if ((sdl_options.callbacks orelse true) and (builtin.target.os.tag == .macos or builtin.target.os.tag == .windows)) {
        // We are using sdl's callbacks to support rendering during OS resizing

        // For programs that provide their own entry points instead of relying on SDL's main function
        // macro magic, 'SDL_SetMainReady()' should be called before calling 'SDL_Init()'.
        c.SDL_SetMainReady();

        // This is more or less what 'SDL_main.h' does behind the curtains.
        const status = c.SDL_EnterAppMainCallbacks(0, null, appInit, appIterate, appEvent, appQuit);

        return @bitCast(@as(i8, @truncate(status)));
    }

    log.info("version: {f} no callbacks", .{getSDLVersion()});

    const init_opts = app.config.get();

    var gpa_instance: std.heap.DebugAllocator(.{}) = .init;
    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");
    const gpa = gpa_instance.allocator();

    // init SDL backend (creates and owns OS window)
    var back = try initWindow(.{
        .allocator = gpa,
        .size = init_opts.size,
        .min_size = init_opts.min_size,
        .max_size = init_opts.max_size,
        .vsync = init_opts.vsync,
        .title = init_opts.title,
        .icon = init_opts.icon,
        .hidden = init_opts.hidden,
    });
    defer back.deinit();

    toErr(c.SDL_EnableScreenSaver(), "SDL_EnableScreenSaver in sdl main") catch {};

    //// init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, back.backend(), init_opts.window_init_options);
    defer win.deinit();

    if (app.initFn) |initFn| {
        try win.begin(win.frame_time_ns);
        try initFn(&win);
        _ = try win.end(.{});
    }
    defer if (app.deinitFn) |deinitFn| deinitFn();

    var interrupted = false;

    main_loop: while (true) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try back.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        try toErr(c.SDL_SetRenderDrawColor(back.renderer, 0, 0, 0, 255), "SDL_SetRenderDrawColor in sdl main");
        try toErr(c.SDL_RenderClear(back.renderer), "SDL_RenderClear in sdl main");

        const res = try app.frameFn();

        const end_micros = try win.end(.{});

        try back.setCursor(win.cursorRequested());
        try back.textInputRect(win.textInputRequested());

        try back.renderPresent();

        if (res != .ok) break :main_loop;

        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try back.waitEventTimeout(wait_event_micros);
    }

    return 0;
}

/// used when doing sdl callbacks
const CallbackState = struct {
    win: dvui.Window,
    back: SDLBackend,
    gpa: std.heap.GeneralPurposeAllocator(.{}) = .init,
    interrupted: bool = false,
    have_resize: bool = false,
    no_wait: bool = false,
};

/// used when doing sdl callbacks
var appState: CallbackState = .{ .win = undefined, .back = undefined };

// sdl3 callback
fn appInit(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    _ = appstate;
    _ = argc;
    _ = argv;
    //_ = c.SDL_SetAppMetadata("dvui-demo", "0.1", "com.example.dvui-demo");

    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;

    log.info("version: {f} callbacks", .{getSDLVersion()});

    const init_opts = app.config.get();

    const gpa = appState.gpa.allocator();

    // init SDL backend (creates and owns OS window)
    appState.back = initWindow(.{
        .allocator = gpa,
        .size = init_opts.size,
        .min_size = init_opts.min_size,
        .max_size = init_opts.max_size,
        .vsync = init_opts.vsync,
        .title = init_opts.title,
        .icon = init_opts.icon,
        .hidden = init_opts.hidden,
    }) catch |err| {
        log.err("initWindow failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    toErr(c.SDL_EnableScreenSaver(), "SDL_EnableScreenSaver in sdl main") catch {};

    //// init dvui Window (maps onto a single OS window)
    appState.win = dvui.Window.init(@src(), gpa, appState.back.backend(), app.config.options.window_init_options) catch |err| {
        log.err("dvui.Window.init failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    if (app.initFn) |initFn| {
        appState.win.begin(appState.win.frame_time_ns) catch |err| {
            log.err("dvui.Window.begin failed: {any}", .{err});
            return c.SDL_APP_FAILURE;
        };

        initFn(&appState.win) catch |err| {
            log.err("dvui.App.initFn failed: {any}", .{err});
            return c.SDL_APP_FAILURE;
        };

        _ = appState.win.end(.{}) catch |err| {
            log.err("dvui.Window.end failed: {any}", .{err});
            return c.SDL_APP_FAILURE;
        };
    }

    return c.SDL_APP_CONTINUE;
}

// sdl3 callback
// This function runs once at shutdown.
fn appQuit(_: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    _ = result;

    const app = dvui.App.get() orelse unreachable;
    if (app.deinitFn) |deinitFn| deinitFn();
    appState.win.deinit();
    appState.back.deinit();
    if (appState.gpa.deinit() != .ok) @panic("Memory leak on exit!");

    // SDL will clean up the window/renderer for us.
}

// sdl3 callback
// This function runs when a new event (mouse input, keypresses, etc) occurs.
fn appEvent(_: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    if (event.?.type == c.SDL_EVENT_USER) {
        // SDL3 says this function might be called on whatever thread pushed
        // the event.  Events from SDL itself are always on the main thread.
        // EVENT_USER is what we use from other threads to wake dvui up, so to
        // prevent concurrent access return early.
        return c.SDL_APP_CONTINUE;
    }

    const e = event.?.*;
    _ = appState.back.addEvent(&appState.win, e) catch |err| {
        log.err("dvui.Window.addEvent failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    switch (event.?.type) {
        c.SDL_EVENT_WINDOW_RESIZED => {
            //std.debug.print("resize {d}x{d}\n", .{e.window.data1, e.window.data2});
            // getting a resize event means we are likely in a callback, so don't call any wait functions
            appState.have_resize = true;
        },
        else => {},
    }

    return c.SDL_APP_CONTINUE;
}

// sdl3 callback
// This function runs once per frame, and is the heart of the program.
fn appIterate(_: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    // beginWait coordinates with waitTime below to run frames only when needed
    const nstime = appState.win.beginWait(appState.interrupted or appState.no_wait);

    // marks the beginning of a frame for dvui, can call dvui functions after this
    appState.win.begin(nstime) catch |err| {
        log.err("dvui.Window.begin failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    // if dvui widgets might not cover the whole window, then need to clear
    // the previous frame's render
    toErr(c.SDL_SetRenderDrawColor(appState.back.renderer, 0, 0, 0, 255), "SDL_SetRenderDrawColor in sdl main") catch return c.SDL_APP_FAILURE;
    toErr(c.SDL_RenderClear(appState.back.renderer), "SDL_RenderClear in sdl main") catch return c.SDL_APP_FAILURE;

    const app = dvui.App.get() orelse unreachable;
    const res = app.frameFn() catch |err| {
        log.err("dvui.App.frameFn failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    const end_micros = appState.win.end(.{}) catch |err| {
        log.err("dvui.Window.end failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    appState.back.setCursor(appState.win.cursorRequested()) catch return c.SDL_APP_FAILURE;
    appState.back.textInputRect(appState.win.textInputRequested()) catch return c.SDL_APP_FAILURE;

    appState.back.renderPresent() catch return c.SDL_APP_FAILURE;

    if (res != .ok) return c.SDL_APP_SUCCESS;

    const wait_event_micros = appState.win.waitTime(end_micros);

    //std.debug.print("waitEventTimeout {d} {} resize {}\n", .{wait_event_micros, gno_wait, ghave_resize});

    // If a resize event happens we are likely in a callback.  If for any
    // reason we are called nested while waiting in the below waitEventTimeout
    // we are in a callback.
    //
    // During a callback we don't want to call SDL_WaitEvent or
    // SDL_WaitEventTimeout.  Otherwise all event handling gets screwed up and
    // either never recovers or recovers after many seconds.
    if (appState.no_wait or appState.have_resize) {
        appState.have_resize = false;
        return c.SDL_APP_CONTINUE;
    }

    appState.no_wait = true;
    appState.interrupted = appState.back.waitEventTimeout(wait_event_micros) catch return c.SDL_APP_FAILURE;
    appState.no_wait = false;

    return c.SDL_APP_CONTINUE;
}
