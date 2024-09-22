const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const win = @import("zigwin32");
const graphics = win.graphics;

const dxgic = dxgi.common;

const dxgi = graphics.dxgi;
const dx = graphics.direct3d11;
const d3d = graphics.direct3d;

const L = win.zig.L;

const ui = win.ui.windows_and_messaging;

const Dx11Backend = @This();

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
// TODO: Figure out cursor situation
// cursor_last: dvui.enums.Cursor = .arrow,
// something dx cursor
arena: std.mem.Allocator = undefined,

const vertex_shader = @embedFile("vertex_shader.hlsl");
const pixel_shader = @embedFile("pixel_shader.hlsl");

const DirectxOptions = struct {
    vertex_shader: ?*dx.ID3D11VertexShader = null,
    pixel_shader: ?*dx.ID3D11PixelShader = null,
    vertex_layout: ?*dx.ID3D11InputLayout = null,
    vertex_buffer: ?*dx.ID3D11Buffer = null,
    index_buffer: ?*dx.ID3D11Buffer = null,
    texture_view: ?*dx.ID3D11ShaderResourceView = null,
    sampler: ?*dx.ID3D11SamplerState = null,
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

pub fn init(options: InitOptions, dx_options: Directx11Options) !Dx11Backend {
    return Dx11Backend{
        .device = dx_options.device,
        .swap_chain = dx_options.swap_chain,
        .device_context = dx_options.device_context,
        .arena = options.allocator,
    };
}

pub fn deinit(self: Dx11Backend) void {
    if (self.we_own_window) {
        _ = self.device.vtable.base.Release(self.device);
        _ = self.device_context.vtable.base.Release(self.device_context);
        _ = self.swap_chain.vtable.base.base.base.Release(self.swap_chain);
    }

    if (self.render_target) |rt| {
        _ = rt.vtable.base.base.base.Release(rt);
    }

    if (self.dx_options.vertex_shader) |vs| {
        _ = vs.vtable.base.Release(@ptrCast(vs));
    }

    if (self.dx_options.pixel_shader) |ps| {
        _ = ps.vtable.base.Release(@ptrCast(ps));
    }

    if (self.dx_options.vertex_layout) |vl| {
        _ = vl.vtable.base.base.base.Release(@ptrCast(vl));
    }
}

fn isOk(res: win.foundation.HRESULT) bool {
    return res == win.foundation.S_OK;
}

fn initShader(self: *Dx11Backend) !void {
    var error_message: ?*d3d.ID3DBlob = null;

    var vs_blob: ?*d3d.ID3DBlob = null;
    defer if (vs_blob) |blob| blob.vtable.base.Release(@ptrCast(blob));
    const compile_shader = d3d.fxc.D3DCompileFromFile(
        L("shaders.hlsl"),
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
        defer error_message.?.base.Release(error_message.?);
        const as_str: [*:0]const u8 = @ptrCast(error_message.?.vtable.GetBufferPointer(error_message.?));
        std.debug.print("vertex shader compilation failed with:\n{s}\n", .{as_str});
        return error.VertexShaderInitFailed;
    }

    var ps_blob: ?*d3d.ID3DBlob = null;
    defer if (ps_blob) |blob| blob.vtable.base.Release(@ptrCast(blob));
    const ps_res = d3d.fxc.D3DCompileFromFile(
        L("shaders.hlsl"),
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
        defer error_message.?.base.Release(error_message.?);
        const as_str: [*:0]const u8 = @ptrCast(error_message.?.vtable.GetBufferPointer(error_message.?));
        std.debug.print("pixel shader compilation failed with: {s}\n", .{as_str});
        return error.PixelShaderInitFailed;
    }

    const create_vs = self.device.vtable.CreateVertexShader(
        self.device,
        @ptrCast(vs_blob.?.vtable.GetBufferPointer(vs_blob.?)),
        vs_blob.?.vtable.GetBufferSize(vs_blob.?),
        null,
        &self.dx_options.vertex_shader,
    );

    if (!isOk(create_vs)) {
        return error.CreateVertexShaderFailed;
    }

    const create_ps = self.device.vtable.CreatePixelShader(
        self.device,
        @ptrCast(ps_blob.?.vtable.GetBufferPointer(ps_blob.?)),
        ps_blob.?.vtable.GetBufferSize(ps_blob.?),
        null,
        &self.dx_options.pixel_shader,
    );

    if (!isOk(create_ps)) {
        return error.CreatePixelShaderFailed;
    }
}

fn createRenderTarget(self: *Dx11Backend) !void {
    var back_buffer: ?*dx.ID3D11Texture2D = null;

    _ = self.swap_chain.vtable.GetBuffer(self.swap_chain, 0, dx.IID_ID3D11Texture2D, @as([*]?*anyopaque, @ptrCast(&back_buffer)));
    defer _ = back_buffer.?.vtable.base.base.base.Release(@ptrCast(back_buffer));

    _ = self.device.vtable.CreateRenderTargetView(
        self.device,
        @as([*]dx.ID3D11Resource, @ptrCast(back_buffer)),
        null,
        &self.render_target,
    );
}

fn createInputLayout(self: *Dx11Backend) !void {
    const input_layout_desc = &[_]dx.D3D11_INPUT_ELEMENT_DESC{
        .{ .SemanticName = "POSITION", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32B32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 0, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "COLOR", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32B32A32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 12, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "TEXCOORD", .SemanticIndex = 0, .Format = dxgic.DXGI_FORMAT_R32G32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 28, .InputSlotClass = dx.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
    };

    const num_elements = input_layout_desc.len;

    const res = self.device.vtable.CreateInputLayout(
        self.device,
        input_layout_desc,
        num_elements,
        @ptrCast(self.dx_options.vertex_shader.vtable.GetBufferPointer(self.dx_options.vertex_shader)),
        self.dx_options.vertex_shader.vtable.GetBufferSize(self.dx_options.vertex_shader),
        &self.dx_options.vertex_layout,
    );

    if (!isOk(res)) {
        return error.VertexLayoutCreationFailed;
    }

    self.device_context.vtable.IASetInputLayout(self.device_context, self.dx_options.vertex_layout);
}

pub fn textureCreate(self: *Dx11Backend, pixels: []const u8, width: u32, height: u32) !*anyopaque {
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

    var resource_data: dx.D3D11_SUBRESOURCE_DATA = std.mem.zeroes(dx.D3D11_SUBRESOURCE_DATA);
    resource_data.pSysMem = pixels.ptr;
    resource_data.SysMemPitch = pixels.len;

    const tex_creation = self.device.vtable.CreateTexture2D(
        self.device,
        &tex_desc,
        &resource_data,
        &texture,
    );

    if (!isOk(tex_creation)) {
        std.debug.print("Texture creation failed.\n", .{});
        return error.TextureCreationFailed;
    }

    var rvd: dx.D3D11_SHADER_RESOURCE_VIEW_DESC = std.mem.zeroes(dx.D3D11_SHADER_RESOURCE_VIEW_DESC);
    rvd = .{
        .Format = dxgic.DXGI_FORMAT.R8G8B8A8_UNORM,
        .ViewDimension = @enumFromInt(4), // DIMENSION_TEXTURE2D
        .Anonymous = .{ .Texture2D = .{
            .MostDetailedMip = 0,
            .MipLevels = 1,
        } },
    };

    const rv_result = self.device.vtable.CreateShaderResourceView(
        self.device,
        &self.dx_options.texture.ID3D11Resource,
        &rvd,
        &self.dx_options.texture_view,
    );

    if (!isOk(rv_result)) {
        std.debug.print("Texture View creation failed\n", .{});
        return error.TextureViewCreationFailed;
    }

    return texture.?;
}

pub fn textureDestroy(self: *Dx11Backend, texture: *anyopaque) void {
    _ = self;
    const tex: *dx.ID3D11Texture2D = @ptrCast(texture);
    tex.vtable.base.base.base.Release(tex);
}

pub fn drawClippedTriangles(
    self: *Dx11Backend,
    texture: ?*anyopaque,
    vtx: []const dvui.Vertex,
    idx: []const u16,
    clipr: dvui.Rect,
) void {
    _ = texture; // autofix
    _ = vtx; // autofix
    _ = idx; // autofix
    _ = clipr; // autofix
    if (self.dx_options.vertex_shader == null or self.dx_options.pixel_shader == null) {
        self.initShader() catch |err| {
            std.debug.print("shaders could not be initialized: {any}\n", .{err});
            return;
        };
    }

    if (self.dx_options.vertex_shader == null) {
        self.createInputLayout() catch |err| {
            std.debug.print("Failed to create vertex layout: {any}\n", .{err});
            return;
        };
    }

    if (self.render_target == null) {
        self.createRenderTarget() catch |err| {
            std.debug.print("render target could not be initialized: {any}\n", .{err});
            return;
        };
    }

    if (self.dx_options.sampler == null) {
        self.createSampler() catch |err| {
            std.debug.print("sampler could not be initialized: {any}\n", .{err});
            return;
        };
    }

    var clear_color = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    self.device_context.vtable.OMSetRenderTargets(self.device_context, 1, @ptrCast(self.render_target), null);
    self.device_context.vtable.ClearRenderTargetView(self.device_context, self.render_target, @ptrCast((&clear_color).ptr));
    self.device_context.vtable.VSSetShader(self.device_context, self.dx_options.vertex_shader, null, 0);
    self.device_context.vtable.PSSetShader(self.device_context, self.dx_options.pixel_shader, null, 0);
    self.device_context.vtable.PSSetShaderResources(self.device_context, 0, 1, @ptrCast(self.dx_options.sampler));
    self.device_context.vtable.DrawIndexed(self.device_context, idx.len, 0, 0);

    self.swap_chain.vtable.Present(self.swap_chain, 0, 0);
}
