const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const win = @import("zigwin32");
const RECT = win.foundation.RECT;
const graphics = win.graphics;

const dxgic = dxgi.common;

const dxgi = graphics.dxgi;
const dx = graphics.direct3d11;
const d3d = graphics.direct3d;

const L = win.zig.L;

const ui = win.ui.windows_and_messaging;

const Dx11Backend = @This();
pub const Context = *Dx11Backend;

device: *dx.ID3D11Device,
device_context: *dx.ID3D11DeviceContext,
swap_chain: *dxgi.IDXGISwapChain,

hwnd: ?win.foundation.HWND = null,
render_target: ?*dx.ID3D11RenderTargetView = null,
dx_options: DirectxOptions = .{},
we_own_window: bool = false,
touch_mouse_events: bool = false,
log_events: bool = false,
initial_scale: f32 = 1.0,

width: f32 = 1280.0,
height: f32 = 760.0,

// TODO: Figure out cursor situation
// cursor_last: dvui.enums.Cursor = .arrow,
// something dx cursor

arena: std.mem.Allocator = undefined,

const DirectxOptions = struct {
    vertex_shader: ?*dx.ID3D11VertexShader = null,
    vertex_bytes: ?*d3d.ID3DBlob = null,
    pixel_shader: ?*dx.ID3D11PixelShader = null,
    pixel_bytes: ?*d3d.ID3DBlob = null,
    vertex_layout: ?*dx.ID3D11InputLayout = null,
    vertex_buffer: ?*dx.ID3D11Buffer = null,
    index_buffer: ?*dx.ID3D11Buffer = null,
    texture_view: ?*dx.ID3D11ShaderResourceView = null,
    sampler: ?*dx.ID3D11SamplerState = null,
    rasterizer: ?*dx.ID3D11RasterizerState = null,
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
};

pub const Directx11Options = struct {
    /// The device
    device: *dx.ID3D11Device,
    device_context: *dx.ID3D11DeviceContext,
    swap_chain: *dxgi.IDXGISwapChain,
};

const XMFLOAT2 = extern struct { x: f32, y: f32 };
const XMFLOAT3 = extern struct { x: f32, y: f32, z: f32 };
const XMFLOAT4 = extern struct { r: f32, g: f32, b: f32, a: f32 };
const SimpleVertex = extern struct { position: XMFLOAT3, color: XMFLOAT4, texcoord: XMFLOAT2 };

const shader =
    \\struct PSInput
    \\{
    \\    float4 position : SV_POSITION;
    \\    float4 color : COLOR;
    \\    float2 texcoord : TEXCOORD0;
    \\};
    \\
    \\PSInput VSMain(float4 position : POSITION, float4 color : COLOR, float2 texcoord : TEXCOORD0)
    \\{
    \\    PSInput result;
    \\
    \\    result.position = position;
    \\    result.color = color;
    \\    result.texcoord = texcoord;
    \\
    \\    return result;
    \\}
    \\
    \\Texture2D myTexture : register(t0);
    \\SamplerState samplerState : register(s0);
    \\
    \\float4 PSMain(PSInput input) : SV_TARGET
    \\{
    \\    float4 sampled = myTexture.Sample(samplerState, input.texcoord);
    \\    return sampled * input.color;
    \\    
    \\}
;

fn convertSpaceToNDC(self: *Dx11Backend, x: f32, y: f32) XMFLOAT3 {
    return XMFLOAT3{
        .x = (2.0 * x / self.width) - 1.0,
        .y = 1.0 - (2.0 * y / self.height),
        .z = 0.0,
    };
}

fn convertVertices(self: *Dx11Backend, vtx: []const dvui.Vertex, zero_uvs: bool) ![]SimpleVertex {
    const simple_vertex = try self.arena.alloc(SimpleVertex, vtx.len);
    for (vtx, simple_vertex) |v, *s| {
        const r: f32 = @floatFromInt(v.col.r);
        const g: f32 = @floatFromInt(v.col.g);
        const b: f32 = @floatFromInt(v.col.b);
        const a: f32 = @floatFromInt(v.col.a);

        s.* = .{
            .position = self.convertSpaceToNDC(v.pos.x, v.pos.y),
            .color = .{ .r = r / 255.0, .g = g / 255.0, .b = b / 255.0, .a = a / 255.0 },
            .texcoord = if (zero_uvs) .{ .x = 0, .y = 0 } else .{ .x = v.uv[0], .y = v.uv[1] },
        };
    }

    return simple_vertex;
}

pub fn setViewport(self: *Dx11Backend) void {
    var vp = dx.D3D11_VIEWPORT{
        .TopLeftX = 0.0,
        .TopLeftY = 0.0,
        .Width = self.width,
        .Height = self.height,
        .MinDepth = 0.0,
        .MaxDepth = 1.0,
    };

    self.device_context.RSSetViewports(1, @ptrCast(&vp));
}

pub fn setDimensions(self: *Dx11Backend, rect: RECT) void {
    self.width = @floatFromInt(rect.right - rect.left);
    self.height = @floatFromInt(rect.bottom - rect.top);
}

pub fn init(options: InitOptions, dx_options: Directx11Options) !Dx11Backend {
    _ = options;
    return Dx11Backend{
        .device = dx_options.device,
        .swap_chain = dx_options.swap_chain,
        .device_context = dx_options.device_context,
    };
}

pub fn deinit(self: Dx11Backend) void {
    if (self.we_own_window) {
        _ = self.device.IUnknown.Release();
        _ = self.device_context.IUnknown.Release();
        _ = self.swap_chain.IUnknown.Release();
    }

    if (self.render_target) |rt| {
        _ = rt.IUnknown.Release();
    }

    if (self.dx_options.vertex_shader) |vs| {
        _ = vs.IUnknown.Release();
    }

    if (self.dx_options.pixel_shader) |ps| {
        _ = ps.IUnknown.Release();
    }

    if (self.dx_options.vertex_layout) |vl| {
        _ = vl.IUnknown.Release();
    }
}

fn isOk(res: win.foundation.HRESULT) bool {
    return res == win.foundation.S_OK;
}

fn initShader(self: *Dx11Backend) !void {
    var error_message: ?*d3d.ID3DBlob = null;

    var vs_blob: ?*d3d.ID3DBlob = null;
    const compile_shader = d3d.fxc.D3DCompile(
        shader.ptr,
        shader.len,
        null,
        null,
        null,
        "VSMain",
        "vs_4_0",
        d3d.fxc.D3DCOMPILE_ENABLE_STRICTNESS,
        0,
        &vs_blob,
        &error_message,
    );
    if (!isOk(compile_shader)) {
        if (error_message == null) {
            std.debug.print("hresult of error message was skewed: {x}\n", .{compile_shader});
            return error.VertexShaderInitFailed;
        }

        defer _ = error_message.?.IUnknown.Release();
        const as_str: [*:0]const u8 = @ptrCast(error_message.?.vtable.GetBufferPointer(error_message.?));
        std.debug.print("vertex shader compilation failed with:\n{s}\n", .{as_str});
        return error.VertexShaderInitFailed;
    }

    var ps_blob: ?*d3d.ID3DBlob = null;
    const ps_res = d3d.fxc.D3DCompile(
        shader.ptr,
        shader.len,
        null,
        null,
        null,
        "PSMain",
        "ps_4_0",
        d3d.fxc.D3DCOMPILE_ENABLE_STRICTNESS,
        0,
        &ps_blob,
        &error_message,
    );
    if (!isOk(ps_res)) {
        if (error_message == null) {
            std.debug.print("hresult of error message was skewed: {x}\n", .{compile_shader});
            return error.PixelShaderInitFailed;
        }

        defer _ = error_message.?.IUnknown.Release();
        const as_str: [*:0]const u8 = @ptrCast(error_message.?.vtable.GetBufferPointer(error_message.?));
        std.debug.print("pixel shader compilation failed with: {s}\n", .{as_str});
        return error.PixelShaderInitFailed;
    }

    self.dx_options.vertex_bytes = vs_blob.?;
    const create_vs = self.device.CreateVertexShader(
        @ptrCast(self.dx_options.vertex_bytes.?.GetBufferPointer()),
        self.dx_options.vertex_bytes.?.GetBufferSize(),
        null,
        &self.dx_options.vertex_shader,
    );

    if (!isOk(create_vs)) {
        return error.CreateVertexShaderFailed;
    }

    self.dx_options.pixel_bytes = ps_blob.?;
    const create_ps = self.device.CreatePixelShader(
        @ptrCast(self.dx_options.pixel_bytes.?.GetBufferPointer()),
        self.dx_options.pixel_bytes.?.GetBufferSize(),
        null,
        &self.dx_options.pixel_shader,
    );

    if (!isOk(create_ps)) {
        return error.CreatePixelShaderFailed;
    }
}

fn createRasterizerState(self: *Dx11Backend) void {
    var raster_desc = std.mem.zeroes(dx.D3D11_RASTERIZER_DESC);
    raster_desc.FillMode = dx.D3D11_FILL_MODE.SOLID;
    raster_desc.CullMode = dx.D3D11_CULL_BACK;
    raster_desc.FrontCounterClockwise = 1;
    raster_desc.DepthClipEnable = 1;

    // TODO: Create better error handling
    _ = self.device.CreateRasterizerState(&raster_desc, &self.dx_options.rasterizer);
    _ = self.device_context.RSSetState(self.dx_options.rasterizer);
}

pub fn createRenderTarget(self: *Dx11Backend) !void {
    var back_buffer: ?*dx.ID3D11Texture2D = null;

    _ = self.swap_chain.GetBuffer(0, dx.IID_ID3D11Texture2D, @ptrCast(&back_buffer));
    // defer _ = back_buffer.?.IUnknown.Release();

    _ = self.device.CreateRenderTargetView(
        @ptrCast(back_buffer),
        null,
        &self.render_target,
    );
}

pub fn cleanupRenderTarget(self: *Dx11Backend) void {
    if (self.render_target) |mrtv| {
        _ = mrtv.IUnknown.Release();
        self.render_target = null;
    }
}

pub fn handleSwapChainResizing(self: *Dx11Backend, width: *c_uint, height: *c_uint) !void {
    self.cleanupRenderTarget();
    _ = self.swap_chain.vtable.ResizeBuffers(self.swap_chain, 0, width.*, height.*, dxgic.DXGI_FORMAT_UNKNOWN, 0);
    width.* = 0;
    height.* = 0;
    try self.createRenderTarget();
}

fn createInputLayout(self: *Dx11Backend) !void {
    const input_layout_desc = &[_]dx.D3D11_INPUT_ELEMENT_DESC{
        .{ .SemanticName = "POSITION", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32B32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 0, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "COLOR", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32B32A32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 12, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "TEXCOORD", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 28, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
    };

    const num_elements = input_layout_desc.len;

    const res = self.device.CreateInputLayout(
        input_layout_desc,
        num_elements,
        @ptrCast(self.dx_options.vertex_bytes.?.GetBufferPointer()),
        self.dx_options.vertex_bytes.?.GetBufferSize(),
        &self.dx_options.vertex_layout,
    );

    if (!isOk(res)) {
        return error.VertexLayoutCreationFailed;
    }

    self.device_context.IASetInputLayout(self.dx_options.vertex_layout);
}

pub fn textureCreate(self: *Dx11Backend, pixels: [*]u8, width: u32, height: u32, ti: dvui.enums.TextureInterpolation) *anyopaque {
    _ = ti; // autofix

    var texture: ?*dx.ID3D11Texture2D = null;
    var tex_desc = dx.D3D11_TEXTURE2D_DESC{
        .Width = width,
        .Height = height,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = dxgic.DXGI_FORMAT.R8G8B8A8_UNORM,
        .SampleDesc = .{
            .Count = 1,
            .Quality = 0,
        },
        .Usage = dx.D3D11_USAGE_DEFAULT,
        .BindFlags = dx.D3D11_BIND_SHADER_RESOURCE,
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
    };

    var resource_data = std.mem.zeroes(dx.D3D11_SUBRESOURCE_DATA);
    resource_data.pSysMem = pixels;
    resource_data.SysMemPitch = width * 4; // 4 byte per pixel (RGBA)

    const tex_creation = self.device.CreateTexture2D(
        &tex_desc,
        &resource_data,
        &texture,
    );

    if (!isOk(tex_creation)) {
        std.debug.print("Texture creation failed.\n", .{});
        @panic("couldn't create texture");
    }

    return texture.?;
}

pub fn textureDestroy(self: *Dx11Backend, texture: *anyopaque) void {
    // if (true) return;
    _ = self;
    const tex: *dx.ID3D11Texture2D = @ptrCast(@alignCast(texture));
    _ = tex.IUnknown.Release();
}

fn recreateShaderView(self: *Dx11Backend, texture: *anyopaque) void {
    const tex: *dx.ID3D11Texture2D = @ptrCast(@alignCast(texture));

    const rvd = dx.D3D11_SHADER_RESOURCE_VIEW_DESC{
        .Format = dxgic.DXGI_FORMAT.R8G8B8A8_UNORM,
        .ViewDimension = d3d.D3D_SRV_DIMENSION_TEXTURE2D,
        .Anonymous = .{
            .Texture2D = .{
                .MostDetailedMip = 0,
                .MipLevels = 1,
            },
        },
    };

    const rv_result = self.device.CreateShaderResourceView(
        &tex.ID3D11Resource,
        &rvd,
        &self.dx_options.texture_view,
    );

    if (!isOk(rv_result)) {
        std.debug.print("Texture View creation failed\n", .{});
        @panic("couldn't create texture view");
    }
}

fn createSampler(self: *Dx11Backend) !void {
    var samp_desc = std.mem.zeroes(dx.D3D11_SAMPLER_DESC);

    samp_desc.Filter = dx.D3D11_FILTER.MIN_MAG_POINT_MIP_LINEAR;
    samp_desc.AddressU = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressV = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressW = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;

    const sampler = self.device.CreateSamplerState(&samp_desc, &self.dx_options.sampler);

    if (!isOk(sampler)) {
        std.debug.print("sampler state could not be iniitialized\n", .{});
        return error.SamplerStateUninitialized;
    }
}

// If you don't know what they are used for... just don't use them, alright?
fn createBuffer(self: *Dx11Backend, bind_type: anytype, comptime InitialType: type, initial_data: []const InitialType) !*dx.ID3D11Buffer {
    var bd = std.mem.zeroes(dx.D3D11_BUFFER_DESC);
    bd.Usage = dx.D3D11_USAGE_DEFAULT;
    bd.ByteWidth = @intCast(@sizeOf(InitialType) * initial_data.len);
    bd.BindFlags = bind_type;
    bd.CPUAccessFlags = .{};

    var data: dx.D3D11_SUBRESOURCE_DATA = undefined;
    data.pSysMem = @ptrCast(initial_data.ptr);

    var buffer: ?*dx.ID3D11Buffer = null;
    _ = self.device.CreateBuffer(&bd, &data, &buffer);

    if (buffer) |buf| {
        return buf;
    } else {
        return error.BufferFailedToCreate;
    }
}

pub fn drawClippedTriangles(
    self: *Dx11Backend,
    texture: ?*anyopaque,
    vtx: []const dvui.Vertex,
    idx: []const u16,
    clipr: dvui.Rect,
) void {
    self.setViewport();
    if (self.render_target == null) {
        self.createRenderTarget() catch |err| {
            std.debug.print("render target could not be initialized: {any}\n", .{err});
            return;
        };
    }

    if (self.dx_options.vertex_shader == null or self.dx_options.pixel_shader == null) {
        self.initShader() catch |err| {
            std.debug.print("shaders could not be initialized: {any}\n", .{err});
            return;
        };
    }

    if (self.dx_options.vertex_layout == null) {
        self.createInputLayout() catch |err| {
            std.debug.print("Failed to create vertex layout: {any}\n", .{err});
            return;
        };
    }

    if (self.dx_options.sampler == null) {
        self.createSampler() catch |err| {
            std.debug.print("sampler could not be initialized: {any}\n", .{err});
            return;
        };
    }

    if (self.dx_options.rasterizer == null) {
        self.createRasterizerState();
    }

    var stride: usize = @sizeOf(SimpleVertex);
    var offset: usize = 0;
    const converted_vtx = self.convertVertices(vtx, false) catch @panic("OOM");
    defer self.arena.free(converted_vtx);

    self.dx_options.vertex_buffer = self.createBuffer(dx.D3D11_BIND_VERTEX_BUFFER, SimpleVertex, converted_vtx) catch {
        std.debug.print("no vertex buffer created\n", .{});
        return;
    };
    self.dx_options.index_buffer = self.createBuffer(dx.D3D11_BIND_INDEX_BUFFER, u16, idx) catch {
        std.debug.print("no index buffer created\n", .{});
        return;
    };

    //self.width = clipr.w;
    //self.height = clipr.h;
    self.setViewport();

    if (texture) |tex| self.recreateShaderView(tex);

    var scissor_rect = std.mem.zeroes(RECT);
    var nums: u32 = 1;
    self.device_context.RSGetScissorRects(&nums, @ptrCast(&scissor_rect));

    const new_clip: RECT = .{
        .left = @intFromFloat(@round(clipr.x)),
        .top = @intFromFloat(@round(clipr.y)),
        .right = @intFromFloat(@round(clipr.w)),
        .bottom = @intFromFloat(@round(clipr.h)),
    };
    self.device_context.RSSetScissorRects(nums, @ptrCast(&new_clip));

    self.device_context.IASetVertexBuffers(0, 1, @ptrCast(&self.dx_options.vertex_buffer), @ptrCast(&stride), @ptrCast(&offset));
    self.device_context.IASetIndexBuffer(self.dx_options.index_buffer, dxgic.DXGI_FORMAT.R16_UINT, 0);
    self.device_context.IASetPrimitiveTopology(d3d.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    self.device_context.OMSetRenderTargets(1, @ptrCast(&self.render_target), null);
    self.device_context.VSSetShader(self.dx_options.vertex_shader, null, 0);
    self.device_context.PSSetShader(self.dx_options.pixel_shader, null, 0);

    self.device_context.PSSetShaderResources(0, 1, @ptrCast(&self.dx_options.texture_view));
    self.device_context.PSSetSamplers(0, 1, @ptrCast(&self.dx_options.sampler));
    self.device_context.DrawIndexed(@intCast(idx.len), 0, 0);
    self.device_context.RSSetScissorRects(nums, @ptrCast(&scissor_rect));
}

pub fn begin(self: *Dx11Backend, arena: std.mem.Allocator) void {
    self.arena = arena;

    var clear_color = [_]f32{ 0.10, 0.10, 0.10, 0.0 };
    self.device_context.ClearRenderTargetView(self.render_target, @ptrCast((&clear_color).ptr));
}

pub fn end(self: *Dx11Backend) void {
    _ = self.swap_chain.Present(0, 0);

    if (self.dx_options.vertex_buffer) |vb| {
        _ = vb.IUnknown.Release();
    }
    self.dx_options.vertex_buffer = null;

    if (self.dx_options.index_buffer) |ib| {
        _ = ib.IUnknown.Release();
    }
    self.dx_options.index_buffer = null;
}

pub fn pixelSize(self: *Dx11Backend) dvui.Size {
    _ = self;
    return dvui.Size{ .w = 1280.0, .h = 720.0 };
}

pub fn windowSize(self: *Dx11Backend) dvui.Size {
    _ = self;
    return dvui.Size{ .w = 1280.0, .h = 720.0 };
}

pub fn contentScale(self: *Dx11Backend) f32 {
    return self.initial_scale;
}

pub fn backend(self: *Dx11Backend) dvui.Backend {
    return dvui.Backend.init(self, @This());
}

pub fn nanoTime(self: *Dx11Backend) i128 {
    _ = self;
    return std.time.nanoTimestamp();
}

pub fn sleep(self: *Dx11Backend, ns: u64) void {
    _ = self;
    std.time.sleep(ns);
}

pub fn clipboardText(self: *Dx11Backend) ![]const u8 {
    _ = self;
    return "";
}

pub fn clipboardTextSet(self: *Dx11Backend, text: []const u8) !void {
    _ = self;
    _ = text;
}

pub fn openURL(self: *Dx11Backend, url: []const u8) !void {
    _ = self;
    _ = url;
}

pub fn refresh(self: *Dx11Backend) void {
    _ = self;
}
