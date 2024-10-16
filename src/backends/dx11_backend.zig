const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const win = @import("zigwin32");

const w = std.os.windows;
const UINT = w.UINT;
const INT = w.INT;

const graphics = win.graphics;
const ui = win.ui.windows_and_messaging;
const key = win.ui.input.keyboard_and_mouse;
const hi_dpi = win.ui.hi_dpi;

const RECT = win.foundation.RECT;
const HINSTANCE = win.foundation.HINSTANCE;
const HWND = win.foundation.HWND;
const BOOL = win.foundation.BOOL;

const WNDCLASSEX = ui.WNDCLASSEXW;

const dxgic = dxgi.common;

const dxgi = graphics.dxgi;
const dx = graphics.direct3d11;
const d3d = graphics.direct3d;
const gdi = graphics.gdi;

const HDC = gdi.HDC;

const Dx11Backend = @This();
pub const Context = *Dx11Backend;

var inst: ?*Dx11Backend = null;
var wind: ?*dvui.Window = null;

const log = std.log.scoped(.Dx11Backend);

/// The directx device
device: *dx.ID3D11Device,
/// The device context
device_context: *dx.ID3D11DeviceContext,
/// The swap chain
swap_chain: *dxgi.IDXGISwapChain,

/// All the options that are windows window specific
window: ?WindowOptions = null,
/// The render target
render_target: ?*dx.ID3D11RenderTargetView = null,
/// The directx options. used internally.
dx_options: DirectxOptions = .{},
// TODO: Implement touch events
//   might require help with that,
//   since i have no touch input device that runs windows.
/// Whether there are touch events
touch_mouse_events: bool = false,
/// Whether to log events
log_events: bool = false,
/// The scaling of DVUI
initial_scale: f32 = 1.0,
/// All the initialization options
///   See: InitOptions
options: InitOptions,

/// The cursor that has been set
cursor_last: dvui.enums.Cursor = .arrow,

/// The arena allocator (usually)
arena: std.mem.Allocator = undefined,

const DvuiKey = union(enum) {
    /// A keyboard button press
    keyboard_key: dvui.enums.Key,
    /// A mouse button press
    mouse_key: dvui.enums.Button,
    /// Mouse move event
    mouse_event: struct { x: i16, y: i16 },
    /// Mouse wheel scroll event
    wheel_event: i16,
    /// No action
    none: void,
};

const KeyEvent = struct {
    /// The type of event emitted
    target: DvuiKey,
    /// What kind of action the event emitted
    action: enum { down, up, none },
};

const WindowOptions = struct {
    /// The general allocator used for the window initialization code
    alloc: std.mem.Allocator,
    /// The instance of the program
    instance: HINSTANCE,
    /// The instance of the Window
    hwnd: win.foundation.HWND,
    /// The window DC (= Device Context)
    hwnd_dc: gdi.HDC,

    /// The title as *allocated* utf16 string.
    /// Thank you windows for doing this... still.
    /// Long live UTF-8 !!!!!
    utf16_wnd_title: [:0]u16,

    pub fn deinit(self: WindowOptions) void {
        _ = gdi.ReleaseDC(self.hwnd, self.hwnd_dc);
        _ = ui.UnregisterClassW(self.utf16_wnd_title, self.instance);
        _ = ui.DestroyWindow(self.hwnd);
        self.alloc.free(self.utf16_wnd_title);
    }
};

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
    blend_state: ?*dx.ID3D11BlendState = null,

    pub fn deinit(self: DirectxOptions) void {
        // is there really no way to express this better?
        if (self.vertex_shader) |vs| {
            _ = vs.IUnknown.Release();
        }
        if (self.vertex_bytes) |vb| {
            _ = vb.IUnknown.Release();
        }
        if (self.pixel_shader) |ps| {
            _ = ps.IUnknown.Release();
        }
        if (self.pixel_bytes) |pb| {
            _ = pb.IUnknown.Release();
        }
        if (self.vertex_layout) |vl| {
            _ = vl.IUnknown.Release();
        }
        if (self.vertex_buffer) |vb| {
            _ = vb.IUnknown.Release();
        }
        if (self.index_buffer) |ib| {
            _ = ib.IUnknown.Release();
        }
        if (self.texture_view) |tv| {
            _ = tv.IUnknown.Release();
        }
        if (self.sampler) |s| {
            _ = s.IUnknown.Release();
        }
        if (self.rasterizer) |r| {
            _ = r.IUnknown.Release();
        }
        if (self.blend_state) |bs| {
            _ = bs.IUnknown.Release();
        }
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
};

pub const Directx11Options = struct {
    /// The device
    device: *dx.ID3D11Device,
    /// The Context
    device_context: *dx.ID3D11DeviceContext,
    /// The Swap chain
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
    \\    if(input.texcoord.x < 0 || input.texcoord.x > 1 || input.texcoord.y < 0 || input.texcoord.y > 1) return input.color;
    \\    float4 sampled = myTexture.Sample(samplerState, input.texcoord);
    \\    return sampled * input.color;
    \\}
;

/// Sets the directx viewport to the internally used dvui.Size
/// Call this *after* setDimensions
pub fn setViewport(self: *Dx11Backend) void {
    var vp = dx.D3D11_VIEWPORT{
        .TopLeftX = 0.0,
        .TopLeftY = 0.0,
        .Width = self.options.size.w,
        .Height = self.options.size.h,
        .MinDepth = 0.0,
        .MaxDepth = 1.0,
    };

    self.device_context.RSSetViewports(1, @ptrCast(&vp));
}

/// Sets the dimensions of a window and maps it to a dvui.Size
/// Call this *before* setViewport
pub fn setDimensions(self: *Dx11Backend, rect: RECT) void {
    self.options.size.w = @floatFromInt(rect.right - rect.left);
    self.options.size.h = @floatFromInt(rect.bottom - rect.top);
}

/// Sets the global dvui.Window instance
/// Call this after you created the dvui.Window
/// ```zig
/// const window = ...;
/// Backend.setWindow(&window);
/// ```
pub fn setWindow(window: ?*dvui.Window) void {
    wind = window;
}

/// Sets the global Dx11Backend
/// Call this on the Backend (not the instance!) after the Backend has been created
/// Example:
/// ```zig
/// const backend = ...;
/// Backend.setBackend(&backend);
/// ```
pub fn setBackend(ins: ?*Dx11Backend) void {
    inst = ins;
}

/// Inits a new instance of the Dx11Backend
/// The caller has to manage their DirectX device, swapchain and device context.
pub fn init(options: InitOptions, dx_options: Directx11Options) !Dx11Backend {
    return Dx11Backend{
        .device = dx_options.device,
        .swap_chain = dx_options.swap_chain,
        .device_context = dx_options.device_context,
        .options = options,
    };
}

/// Creates a new DirectX window for you, as well as initializes all the
/// DirectX options for you
/// The caller just needs to clean up everything by calling `deinit` on the Dx11Backend
pub fn initWindow(instance: HINSTANCE, cmd_show: INT, options: InitOptions) !Dx11Backend {
    const window_options = try createWindow(instance, options);
    const dx_options = createDeviceD3D(window_options.hwnd, options) orelse return error.D3dDeviceInitFailed;

    _ = ui.ShowWindow(window_options.hwnd, @bitCast(cmd_show));
    _ = gdi.UpdateWindow(window_options.hwnd);

    var rc: RECT = undefined;
    _ = ui.GetClientRect(window_options.hwnd, &rc);
    //std.debug.print("GetClientRect -> {}\n", .{rc});

    var res = Dx11Backend{
        .device = dx_options.device,
        .device_context = dx_options.device_context,
        .swap_chain = dx_options.swap_chain,
        .window = window_options,
        .options = options,
    };

    res.setDimensions(rc);
    res.setViewport();

    res.handleSwapChainResizing(@intCast(rc.right - rc.left), @intCast(rc.bottom - rc.top)) catch {
        log.err("Failed to handle swap chain resizing...", .{});
    };

    return res;
}

/// Cleanup routine
pub fn deinit(self: Dx11Backend) void {
    if (self.window) |instance| {
        instance.deinit();
        _ = self.device.IUnknown.Release();
        _ = self.device_context.IUnknown.Release();
        _ = self.swap_chain.IUnknown.Release();
    }

    if (self.render_target) |rt| {
        _ = rt.IUnknown.Release();
    }

    self.dx_options.deinit();

    setWindow(null);
    setBackend(null);
}

/// Resizes the SwapChain based on the new window size
/// This is only useful if you have your own directx stuff to manage
pub fn handleSwapChainResizing(self: *Dx11Backend, width: c_uint, height: c_uint) !void {
    self.cleanupRenderTarget();
    _ = self.swap_chain.ResizeBuffers(0, width, height, dxgic.DXGI_FORMAT_UNKNOWN, 0);
    return self.createRenderTarget();
}

/// Call this first in your main event loop.
/// This is NON-OPTIONAL!
/// Your window will freeze otherwise.
/// Time spent figuring this out: ~4 hours
pub fn isExitRequested() bool {
    var msg: ui.MSG = std.mem.zeroes(ui.MSG);

    while (ui.PeekMessageA(&msg, null, 0, 0, ui.PM_REMOVE) != 0) {
        _ = ui.TranslateMessage(&msg);
        _ = ui.DispatchMessageW(&msg);
        if (msg.message == ui.WM_QUIT) {
            return true;
        }
    }

    return false;
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
            log.err("hresult of error message was skewed: {x}", .{compile_shader});
            return error.VertexShaderInitFailed;
        }

        defer _ = error_message.?.IUnknown.Release();
        const as_str: [*:0]const u8 = @ptrCast(error_message.?.vtable.GetBufferPointer(error_message.?));
        log.err("vertex shader compilation failed with:\n{s}", .{as_str});
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
            log.err("hresult of error message was skewed: {x}", .{compile_shader});
            return error.PixelShaderInitFailed;
        }

        defer _ = error_message.?.IUnknown.Release();
        const as_str: [*:0]const u8 = @ptrCast(error_message.?.vtable.GetBufferPointer(error_message.?));
        log.err("pixel shader compilation failed with: {s}", .{as_str});
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

fn createRasterizerState(self: *Dx11Backend) !void {
    var raster_desc = std.mem.zeroes(dx.D3D11_RASTERIZER_DESC);
    raster_desc.FillMode = dx.D3D11_FILL_MODE.SOLID;
    raster_desc.CullMode = dx.D3D11_CULL_BACK;
    raster_desc.FrontCounterClockwise = 1;
    raster_desc.DepthClipEnable = 0;

    const rasterizer_res = self.device.CreateRasterizerState(&raster_desc, &self.dx_options.rasterizer);
    if (!isOk(rasterizer_res)) {
        return error.RasterizerInitFailed;
    }

    self.device_context.RSSetState(self.dx_options.rasterizer);
}

fn createRenderTarget(self: *Dx11Backend) !void {
    var back_buffer: ?*dx.ID3D11Texture2D = null;

    _ = self.swap_chain.GetBuffer(0, dx.IID_ID3D11Texture2D, @ptrCast(&back_buffer));
    defer _ = back_buffer.?.IUnknown.Release();

    _ = self.device.CreateRenderTargetView(
        @ptrCast(back_buffer),
        null,
        &self.render_target,
    );
}

fn cleanupRenderTarget(self: *Dx11Backend) void {
    if (self.render_target) |mrtv| {
        _ = mrtv.IUnknown.Release();
        self.render_target = null;
    }
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

    if (self.dx_options.texture_view) |tv| {
        _ = tv.IUnknown.Release();
    }

    const rv_result = self.device.CreateShaderResourceView(
        &tex.ID3D11Resource,
        &rvd,
        &self.dx_options.texture_view,
    );

    if (!isOk(rv_result)) {
        log.err("Texture View creation failed", .{});
        @panic("couldn't create texture view");
    }
}

fn createSampler(self: *Dx11Backend) !void {
    var samp_desc = std.mem.zeroes(dx.D3D11_SAMPLER_DESC);
    samp_desc.Filter = dx.D3D11_FILTER.MIN_MAG_POINT_MIP_LINEAR;
    samp_desc.AddressU = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressV = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressW = dx.D3D11_TEXTURE_ADDRESS_MODE.WRAP;

    var blend_desc = std.mem.zeroes(dx.D3D11_BLEND_DESC);
    blend_desc.RenderTarget[0].BlendEnable = 1;
    blend_desc.RenderTarget[0].SrcBlend = dx.D3D11_BLEND_SRC_ALPHA;
    blend_desc.RenderTarget[0].DestBlend = dx.D3D11_BLEND_INV_SRC_ALPHA;
    blend_desc.RenderTarget[0].BlendOp = dx.D3D11_BLEND_OP_ADD;
    blend_desc.RenderTarget[0].SrcBlendAlpha = dx.D3D11_BLEND_ONE;
    blend_desc.RenderTarget[0].DestBlendAlpha = dx.D3D11_BLEND_ZERO;
    blend_desc.RenderTarget[0].BlendOpAlpha = dx.D3D11_BLEND_OP_ADD;
    blend_desc.RenderTarget[0].RenderTargetWriteMask = @intFromEnum(dx.D3D11_COLOR_WRITE_ENABLE_ALL);

    // TODO: Handle errors better
    _ = self.device.CreateBlendState(&blend_desc, &self.dx_options.blend_state);
    _ = self.device_context.OMSetBlendState(self.dx_options.blend_state, null, 0xffffffff);

    const sampler = self.device.CreateSamplerState(&samp_desc, &self.dx_options.sampler);

    if (!isOk(sampler)) {
        log.err("sampler state could not be iniitialized", .{});
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

// ############ Satisfy DVUI interfaces ############
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
        log.err("Texture creation failed.", .{});
        @panic("couldn't create texture");
    }

    return texture.?;
}

pub fn textureDestroy(self: *Dx11Backend, texture: *anyopaque) void {
    _ = self;
    const tex: *dx.ID3D11Texture2D = @ptrCast(@alignCast(texture));
    _ = tex.IUnknown.Release();
}

pub fn drawClippedTriangles(
    self: *Dx11Backend,
    texture: ?*anyopaque,
    vtx: []const dvui.Vertex,
    idx: []const u16,
    clipr: ?dvui.Rect,
) void {
    self.setViewport();
    if (self.render_target == null) {
        self.createRenderTarget() catch |err| {
            log.err("render target could not be initialized: {}", .{err});
            return;
        };
    }

    if (self.dx_options.vertex_shader == null or self.dx_options.pixel_shader == null) {
        self.initShader() catch |err| {
            log.err("shaders could not be initialized: {}", .{err});
            return;
        };
    }

    if (self.dx_options.vertex_layout == null) {
        self.createInputLayout() catch |err| {
            log.err("Failed to create vertex layout: {}", .{err});
            return;
        };
    }

    if (self.dx_options.sampler == null) {
        self.createSampler() catch |err| {
            log.err("sampler could not be initialized: {}", .{err});
            return;
        };
    }

    if (self.dx_options.rasterizer == null) {
        self.createRasterizerState() catch |err| {
            log.err("Creating rasterizer failed: {}", .{err});
        };
    }

    var stride: usize = @sizeOf(SimpleVertex);
    var offset: usize = 0;
    const converted_vtx = self.convertVertices(vtx, texture == null) catch @panic("OOM");
    defer self.arena.free(converted_vtx);

    // Do yourself a favour and don't touch it.
    // End() isn't being called all the time, so it's kind of futile.
    if (self.dx_options.vertex_buffer) |vb| {
        _ = vb.IUnknown.Release();
    }
    self.dx_options.vertex_buffer = self.createBuffer(dx.D3D11_BIND_VERTEX_BUFFER, SimpleVertex, converted_vtx) catch {
        log.err("no vertex buffer created", .{});
        return;
    };

    // Do yourself a favour and don't touch it.
    // End() isn't being called all the time, so it's kind of futile.
    if (self.dx_options.index_buffer) |ib| {
        _ = ib.IUnknown.Release();
    }
    self.dx_options.index_buffer = self.createBuffer(dx.D3D11_BIND_INDEX_BUFFER, u16, idx) catch {
        log.err("no index buffer created", .{});
        return;
    };

    self.setViewport();

    if (texture) |tex| self.recreateShaderView(tex);

    var scissor_rect: ?RECT = std.mem.zeroes(RECT);
    var nums: u32 = 1;
    self.device_context.RSGetScissorRects(&nums, @ptrCast(&scissor_rect));

    if (clipr) |cr| {
        const new_clip: RECT = .{
            .left = @intFromFloat(@round(cr.x)),
            .top = @intFromFloat(@round(cr.y)),
            .right = @intFromFloat(@round(cr.w)),
            .bottom = @intFromFloat(@round(cr.h)),
        };
        self.device_context.RSSetScissorRects(nums, @ptrCast(&new_clip));
    } else {
        scissor_rect = null;
    }

    self.device_context.IASetVertexBuffers(0, 1, @ptrCast(&self.dx_options.vertex_buffer), @ptrCast(&stride), @ptrCast(&offset));
    self.device_context.IASetIndexBuffer(self.dx_options.index_buffer, dxgic.DXGI_FORMAT.R16_UINT, 0);
    self.device_context.IASetPrimitiveTopology(d3d.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    self.device_context.OMSetRenderTargets(1, @ptrCast(&self.render_target), null);
    self.device_context.VSSetShader(self.dx_options.vertex_shader, null, 0);
    self.device_context.PSSetShader(self.dx_options.pixel_shader, null, 0);

    self.device_context.PSSetShaderResources(0, 1, @ptrCast(&self.dx_options.texture_view));
    self.device_context.PSSetSamplers(0, 1, @ptrCast(&self.dx_options.sampler));
    self.device_context.DrawIndexed(@intCast(idx.len), 0, 0);
    if (scissor_rect) |srect| self.device_context.RSSetScissorRects(nums, @ptrCast(&srect));
}

pub fn begin(self: *Dx11Backend, arena: std.mem.Allocator) void {
    self.arena = arena;
    var clear_color = [_]f32{ 1.0, 1.0, 1.0, 0.0 };
    self.device_context.ClearRenderTargetView(self.render_target orelse return, @ptrCast((&clear_color).ptr));
}

pub fn end(self: *Dx11Backend) void {
    _ = self.swap_chain.Present(if (self.options.vsync) 1 else 0, 0);
}

pub fn pixelSize(self: *Dx11Backend) dvui.Size {
    const window_opt = self.window orelse return std.mem.zeroes(dvui.Size);
    const dpi_scale: f32 = @floatFromInt(hi_dpi.GetDpiForWindow(window_opt.hwnd) / 96);
    return dvui.Size{
        .w = self.options.size.w * dpi_scale,
        .h = self.options.size.h * dpi_scale,
    };
}

pub fn windowSize(self: *Dx11Backend) dvui.Size {
    return self.options.size;
}

pub fn contentScale(self: *Dx11Backend) f32 {
    return self.initial_scale;
}

pub fn hasEvent(_: *Dx11Backend) bool {
    return false;
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
    const data_x = win.system.data_exchange;
    const opened = data_x.OpenClipboard(self.window.?.hwnd) == win.zig.TRUE;
    defer _ = data_x.CloseClipboard();
    if (!opened) {
        return "";
    }

    // istg, windows. why. why utf16.
    const data_handle = data_x.GetClipboardData(@intFromEnum(win.system.system_services.CF_UNICODETEXT)) orelse return "";

    var res: []u8 = undefined;
    {
        const handle: isize = @intCast(@intFromPtr(data_handle));
        const data: [*:0]u16 = @ptrCast(@alignCast(win.system.memory.GlobalLock(handle) orelse return ""));
        defer _ = win.system.memory.GlobalUnlock(handle);

        // we want this to be a sane format.
        const len = std.mem.indexOfSentinel(u16, 0, data);
        res = std.unicode.utf16leToUtf8Alloc(self.arena, data[0..len]) catch return error.OutOfMemory;
    }

    return res;
}

pub fn clipboardTextSet(self: *Dx11Backend, text: []const u8) !void {
    const data_x = win.system.data_exchange;
    const memory = win.system.memory;
    const opened = data_x.OpenClipboard(self.window.?.hwnd) == win.zig.TRUE;
    defer _ = data_x.CloseClipboard();
    if (!opened) {
        return;
    }

    const handle = memory.GlobalAlloc(memory.GMEM_MOVEABLE, text.len * @sizeOf(u16) + 1); // don't forget the nullbyte
    if (handle != 0x0) {
        const as_utf16 = std.unicode.utf8ToUtf16LeAlloc(self.arena, text) catch return error.OutOfMemory;
        defer self.arena.free(as_utf16);

        const data: [*:0]u16 = @ptrCast(@alignCast(win.system.memory.GlobalLock(handle) orelse return));
        defer _ = win.system.memory.GlobalUnlock(handle);

        for (as_utf16, 0..) |wide, i| {
            data[i] = wide;
        }
    } else {
        return error.OutOfMemory;
    }

    _ = data_x.EmptyClipboard();
    const handle_usize: usize = @intCast(handle);
    _ = data_x.SetClipboardData(@intFromEnum(win.system.system_services.CF_UNICODETEXT), @ptrFromInt(handle_usize));
}

pub fn openURL(self: *Dx11Backend, url: []const u8) !void {
    _ = self;
    _ = url;
}

pub fn refresh(self: *Dx11Backend) void {
    _ = self;
}

pub fn addEvent(self: *Dx11Backend, window: *dvui.Window, key_event: KeyEvent) !bool {
    _ = self;
    const event = key_event.target;
    const action = key_event.action;
    switch (event) {
        .keyboard_key => |ev| {
            return window.addEventKey(.{
                .code = ev,
                .action = if (action == .up) .up else .down,
                .mod = dvui.enums.Mod.none,
            });
        },
        .mouse_key => |ev| {
            return window.addEventMouseButton(ev, if (action == .up) .release else .press);
        },
        .mouse_event => |ev| {
            return window.addEventMouseMotion(@floatFromInt(ev.x), @floatFromInt(ev.y));
        },
        .wheel_event => |ev| {
            return window.addEventMouseWheel(@floatFromInt(ev));
        },
        .none => return false,
    }
}

pub fn addAllEvents(self: *Dx11Backend, window: *dvui.Window) !bool {
    _ = self;
    _ = window;
    return false;
}

pub fn setCursor(self: *Dx11Backend, new_cursor: dvui.enums.Cursor) void {
    const converted_cursor = switch (new_cursor) {
        .arrow => ui.IDC_ARROW,
        .ibeam => ui.IDC_IBEAM,
        .wait, .wait_arrow => ui.IDC_WAIT,
        .crosshair => ui.IDC_CROSS,
        .arrow_nw_se => ui.IDC_ARROW,
        .arrow_ne_sw => ui.IDC_ARROW,
        .arrow_w_e => ui.IDC_ARROW,
        .arrow_n_s => ui.IDC_ARROW,
        .arrow_all => ui.IDC_ARROW,
        .bad => ui.IDC_NO,
        .hand => ui.IDC_HAND,
    };

    _ = ui.LoadCursorW(self.window.?.instance, converted_cursor);
}

// ############ Event Handling via wnd proc ############
pub fn wndProc(hwnd: HWND, umsg: UINT, wparam: w.WPARAM, lparam: w.LPARAM) callconv(w.WINAPI) w.LRESULT {
    const instance = inst orelse return ui.DefWindowProcW(hwnd, umsg, wparam, lparam);

    switch (umsg) {
        ui.WM_DESTROY => {
            ui.PostQuitMessage(0);
            return 0;
        },
        ui.WM_PAINT => {
            var ps: win.graphics.gdi.PAINTSTRUCT = undefined;
            const hdc: HDC = gdi.BeginPaint(hwnd, &ps) orelse undefined;
            _ = gdi.FillRect(hdc, @ptrCast(&ps.rcPaint), @ptrFromInt(@intFromEnum(ui.COLOR_WINDOW) + 1));
            _ = gdi.EndPaint(hwnd, &ps);
        },
        ui.WM_SIZE => {
            const resize: packed struct { width: i16, height: i16, _upper: i32 } = @bitCast(lparam);
            instance.options.size.w = @floatFromInt(resize.width);
            instance.options.size.h = @floatFromInt(resize.height);
            instance.handleSwapChainResizing(@intCast(resize.width), @intCast(resize.height)) catch {
                log.err("Failed to handle swap chain resizing...", .{});
            };
        },
        ui.WM_KEYDOWN, ui.WM_SYSKEYDOWN => {
            if (std.meta.intToEnum(key.VIRTUAL_KEY, wparam)) |as_vkey| {
                const conv_vkey = convertVKeyToDvuiKey(as_vkey);
                if (wind) |window| {
                    const dk = DvuiKey{ .keyboard_key = conv_vkey };
                    _ = instance.addEvent(
                        window,
                        KeyEvent{ .target = dk, .action = .down },
                    ) catch {};
                }
            } else |err| {
                log.err("invalid key found: {}", .{err});
            }
        },
        ui.WM_LBUTTONDOWN => {
            const lbutton = dvui.enums.Button.left;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = lbutton };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .down },
                ) catch {};
            }
        },
        ui.WM_RBUTTONDOWN => {
            const rbutton = dvui.enums.Button.right;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = rbutton };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .down },
                ) catch {};
            }
        },
        ui.WM_MBUTTONDOWN => {
            const mbutton = dvui.enums.Button.middle;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = mbutton };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .down },
                ) catch {};
            }
        },
        ui.WM_XBUTTONDOWN => {
            const xbutton: packed struct { _upper: u16, which: u16, _lower: u32 } = @bitCast(wparam);
            const variant = if (xbutton.which == 1) dvui.enums.Button.four else dvui.enums.Button.five;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = variant };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .down },
                ) catch {};
            }
        },
        ui.WM_MOUSEMOVE => {
            const lparam_low: i32 = @truncate(lparam);
            const bits: packed struct { x: i16, y: i16 } = @bitCast(lparam_low);
            if (wind) |window| {
                const mouse_x, const mouse_y = .{ bits.x, bits.y };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = DvuiKey{
                        .mouse_event = .{ .x = mouse_x, .y = mouse_y },
                    }, .action = .down },
                ) catch {};
            }
        },
        ui.WM_KEYUP, ui.WM_SYSKEYUP => {
            if (std.meta.intToEnum(key.VIRTUAL_KEY, wparam)) |as_vkey| {
                const conv_vkey = convertVKeyToDvuiKey(as_vkey);
                if (wind) |window| {
                    const dk = DvuiKey{ .keyboard_key = conv_vkey };
                    _ = instance.addEvent(
                        window,
                        KeyEvent{ .target = dk, .action = .up },
                    ) catch {};
                }
            } else |err| {
                log.err("invalid key found: {}", .{err});
            }
        },
        ui.WM_LBUTTONUP => {
            const lbutton = dvui.enums.Button.left;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = lbutton };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .up },
                ) catch {};
            }
        },
        ui.WM_RBUTTONUP => {
            const rbutton = dvui.enums.Button.right;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = rbutton };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .up },
                ) catch {};
            }
        },
        ui.WM_MBUTTONUP => {
            const mbutton = dvui.enums.Button.middle;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = mbutton };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .up },
                ) catch {};
            }
        },
        ui.WM_XBUTTONUP => {
            const xbutton: packed struct { _upper: u16, which: u16, _lower: u32 } = @bitCast(wparam);
            const variant = if (xbutton.which == 1) dvui.enums.Button.four else dvui.enums.Button.five;
            if (wind) |window| {
                const dk = DvuiKey{ .mouse_key = variant };
                _ = instance.addEvent(
                    window,
                    KeyEvent{ .target = dk, .action = .up },
                ) catch {};
            }
        },
        ui.WM_MOUSEWHEEL => {
            const higher: isize = @intCast(wparam >> 16);
            const wheel_info: i16 = @truncate(higher);
            if (wind) |window| {
                _ = instance.addEvent(window, KeyEvent{
                    .target = .{ .wheel_event = wheel_info },
                    .action = .none,
                }) catch {};
            }
        },
        else => {},
    }

    return ui.DefWindowProcW(hwnd, umsg, wparam, lparam);
}

// ############ Utilities ############
fn convertSpaceToNDC(self: *Dx11Backend, x: f32, y: f32) XMFLOAT3 {
    return XMFLOAT3{
        .x = (2.0 * x / self.options.size.w) - 1.0,
        .y = 1.0 - (2.0 * y / self.options.size.h),
        .z = 0.0,
    };
}

fn convertVertices(self: *Dx11Backend, vtx: []const dvui.Vertex, signal_invalid_uv: bool) ![]SimpleVertex {
    const simple_vertex = try self.arena.alloc(SimpleVertex, vtx.len);
    for (vtx, simple_vertex) |v, *s| {
        const r: f32 = @floatFromInt(v.col.r);
        const g: f32 = @floatFromInt(v.col.g);
        const b: f32 = @floatFromInt(v.col.b);
        const a: f32 = @floatFromInt(v.col.a);

        s.* = .{
            .position = self.convertSpaceToNDC(v.pos.x, v.pos.y),
            .color = .{ .r = r / 255.0, .g = g / 255.0, .b = b / 255.0, .a = a / 255.0 },
            .texcoord = if (signal_invalid_uv) .{ .x = -1.0, .y = -1.0 } else .{ .x = v.uv[0], .y = v.uv[1] },
        };
    }

    return simple_vertex;
}

fn createWindow(instance: HINSTANCE, options: InitOptions) !WindowOptions {
    const wnd_title = try std.unicode.utf8ToUtf16LeAllocZ(options.allocator, options.title);
    const wnd_class: WNDCLASSEX = .{
        .cbSize = @sizeOf(WNDCLASSEX),
        .style = .{ .DBLCLKS = 1, .OWNDC = 1 },
        .lpfnWndProc = wndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = ui.LoadCursorW(null, ui.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = @ptrCast(wnd_title.ptr),
        .hIconSm = null,
    };
    var wnd_size: RECT = .{
        .left = 0,
        .top = 0,
        .right = @intFromFloat(options.size.w),
        .bottom = @intFromFloat(options.size.h),
    };

    _ = ui.RegisterClassExW(&wnd_class);
    var overlap = ui.WS_OVERLAPPEDWINDOW;
    _ = ui.AdjustWindowRectEx(
        @ptrCast(&wnd_size),
        overlap,
        w.FALSE,
        .{ .APPWINDOW = 1, .WINDOWEDGE = 1 },
    );
    overlap.VISIBLE = 1;

    const min_size = options.min_size orelse dvui.Size{
        .w = @floatFromInt(wnd_size.right - wnd_size.left),
        .h = @floatFromInt(wnd_size.bottom - wnd_size.top),
    };
    const wnd = ui.CreateWindowExW(
        .{ .APPWINDOW = 1, .WINDOWEDGE = 1 },
        wnd_title,
        wnd_title,
        overlap,
        ui.CW_USEDEFAULT,
        ui.CW_USEDEFAULT,
        @intFromFloat(min_size.w),
        @intFromFloat(min_size.h),
        null,
        null,
        instance,
        null,
    ) orelse {
        log.err("Failed to create window: {}\nQuitting...", .{win.foundation.GetLastError()});
        std.process.exit(1);
    };

    const wnd_dc = gdi.GetDC(wnd).?;
    const dpi = hi_dpi.GetDpiForWindow(wnd);
    const xcenter = @divFloor(hi_dpi.GetSystemMetricsForDpi(@intFromEnum(ui.SM_CXSCREEN), dpi), 2);
    const ycenter = @divFloor(hi_dpi.GetSystemMetricsForDpi(@intFromEnum(ui.SM_CYSCREEN), dpi), 2);

    const width_floor: i32 = @intFromFloat(@divFloor(options.size.w, 2));
    const height_floor: i32 = @intFromFloat(@divFloor(options.size.h, 2));

    wnd_size.left = xcenter - width_floor;
    wnd_size.top = ycenter - height_floor;
    wnd_size.right = wnd_size.left + width_floor;
    wnd_size.bottom = wnd_size.top + height_floor;

    _ = ui.SetWindowPos(wnd, null, wnd_size.left, wnd_size.top, wnd_size.right, wnd_size.bottom, ui.SWP_NOCOPYBITS);

    return WindowOptions{
        .alloc = options.allocator,
        .instance = instance,
        .hwnd = wnd,
        .hwnd_dc = wnd_dc,
        .utf16_wnd_title = wnd_title,
    };
}

fn createDeviceD3D(hwnd: HWND, opt: InitOptions) ?Dx11Backend.Directx11Options {
    var rc: RECT = undefined;
    _ = ui.GetClientRect(hwnd, &rc);

    var sd = std.mem.zeroes(dxgi.DXGI_SWAP_CHAIN_DESC);
    sd.BufferCount = 6;
    sd.BufferDesc.Width = @intFromFloat(opt.size.w);
    sd.BufferDesc.Height = @intFromFloat(opt.size.h);
    sd.BufferDesc.Format = dxgic.DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = @intFromEnum(dxgi.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH);
    sd.BufferUsage = dxgi.DXGI_USAGE_RENDER_TARGET_OUTPUT;
    @setRuntimeSafety(false);
    sd.OutputWindow = hwnd;
    @setRuntimeSafety(true);
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = w.TRUE;
    sd.SwapEffect = dxgi.DXGI_SWAP_EFFECT_DISCARD;

    const createDeviceFlags: dx.D3D11_CREATE_DEVICE_FLAG = .{
        .DEBUG = 1,
    };
    //createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
    var featureLevel: d3d.D3D_FEATURE_LEVEL = undefined;
    const featureLevelArray = &[_]d3d.D3D_FEATURE_LEVEL{ d3d.D3D_FEATURE_LEVEL_11_0, d3d.D3D_FEATURE_LEVEL_10_0 };

    var device: ?*dx.ID3D11Device = null;
    var device_context: ?*dx.ID3D11DeviceContext = null;
    var swap_chain: ?*dxgi.IDXGISwapChain = null;

    var res: win.foundation.HRESULT = dx.D3D11CreateDeviceAndSwapChain(
        null,
        d3d.D3D_DRIVER_TYPE_HARDWARE,
        null,
        createDeviceFlags,
        featureLevelArray,
        2,
        dx.D3D11_SDK_VERSION,
        &sd,
        &swap_chain,
        &device,
        &featureLevel,
        &device_context,
    );

    if (res == dxgi.DXGI_ERROR_UNSUPPORTED) {
        res = dx.D3D11CreateDeviceAndSwapChain(
            null,
            d3d.D3D_DRIVER_TYPE_WARP,
            null,
            createDeviceFlags,
            featureLevelArray,
            2,
            dx.D3D11_SDK_VERSION,
            &sd,
            &swap_chain,
            &device,
            &featureLevel,
            &device_context,
        );
    }
    if (!isOk(res))
        return null;

    return Dx11Backend.Directx11Options{
        .device = device.?,
        .device_context = device_context.?,
        .swap_chain = swap_chain.?,
    };
}

fn convertVKeyToDvuiKey(vkey: key.VIRTUAL_KEY) dvui.enums.Key {
    const K = dvui.enums.Key;
    return switch (vkey) {
        .@"0", .NUMPAD0 => K.kp_0,
        .@"1", .NUMPAD1 => K.kp_1,
        .@"2", .NUMPAD2 => K.kp_2,
        .@"3", .NUMPAD3 => K.kp_3,
        .@"4", .NUMPAD4 => K.kp_4,
        .@"5", .NUMPAD5 => K.kp_5,
        .@"6", .NUMPAD6 => K.kp_6,
        .@"7", .NUMPAD7 => K.kp_7,
        .@"8", .NUMPAD8 => K.kp_8,
        .@"9", .NUMPAD9 => K.kp_9,
        .A => K.a,
        .B => K.b,
        .C => K.c,
        .D => K.d,
        .E => K.e,
        .F => K.f,
        .G => K.g,
        .H => K.h,
        .I => K.i,
        .J => K.j,
        .K => K.k,
        .L => K.l,
        .M => K.m,
        .N => K.n,
        .O => K.o,
        .P => K.p,
        .Q => K.q,
        .R => K.r,
        .S => K.s,
        .T => K.t,
        .U => K.u,
        .V => K.v,
        .W => K.w,
        .X => K.x,
        .Y => K.y,
        .Z => K.z,
        .BACK => K.backspace,
        .TAB => K.tab,
        .RETURN => K.kp_enter,
        .F1 => K.f1,
        .F2 => K.f2,
        .F3 => K.f3,
        .F4 => K.f4,
        .F5 => K.f5,
        .F6 => K.f6,
        .F7 => K.f7,
        .F8 => K.f8,
        .F9 => K.f9,
        .F10 => K.f10,
        .F11 => K.f11,
        .F12 => K.f12,
        .F13 => K.f13,
        .F14 => K.f14,
        .F15 => K.f15,
        .F16 => K.f16,
        .F17 => K.f17,
        .F18 => K.f18,
        .F19 => K.f19,
        .F20 => K.f20,
        .F21 => K.f21,
        .F22 => K.f22,
        .F23 => K.f23,
        .F24 => K.f24,
        .SHIFT, .LSHIFT => K.left_shift,
        .RSHIFT => K.right_shift,
        .CONTROL, .LCONTROL => K.left_control,
        .RCONTROL => K.right_control,
        .MENU => K.menu,
        .PAUSE => K.pause,
        .ESCAPE => K.escape,
        .SPACE => K.space,
        .END => K.end,
        .HOME => K.home,
        .LEFT => K.left,
        .RIGHT => K.right,
        .UP => K.up,
        .DOWN => K.down,
        .PRINT => K.print,
        .INSERT => K.insert,
        .DELETE => K.delete,
        .LWIN => K.left_command,
        .RWIN => K.right_command,
        .PRIOR => K.page_up,
        .NEXT => K.page_down,
        .MULTIPLY => K.kp_multiply,
        .ADD => K.kp_add,
        .SUBTRACT => K.kp_subtract,
        .DIVIDE => K.kp_divide,
        .NUMLOCK => K.num_lock,
        .OEM_1 => K.semicolon,
        .OEM_2 => K.slash,
        .OEM_3 => K.grave,
        .OEM_4 => K.left_bracket,
        .OEM_5 => K.backslash,
        .OEM_6 => K.right_bracket,
        .OEM_7 => K.apostrophe,
        .CAPITAL => K.caps_lock,
        .OEM_PLUS => K.kp_equal,
        .OEM_MINUS => K.minus,
        else => |e| {
            log.warn("Key {s} not supported.", .{@tagName(e)});
            return K.unknown;
        },
    };
}
