const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const graphics = @import("zigwin32").graphics;
const dxgi = graphics.dxgi;
const dx = graphics.direct3d11;
const d3d = graphics.direct3d;

const Dx11Backend = @This();

device: *dx.ID3D11Device,
device_context: *dx.ID3D11DeviceContext,
swap_chain: *dxgi.IDXGISwapChain,
render_target: *dx.ID3D11RenderTargetView,
dx_options: DirectxOptions = .{},
we_own_window: bool = false,
touch_mouse_events: bool = false,
log_events: bool = false,
initial_scale: f32 = 1.0,
// TODO: Figure out cursor situation
// cursor_last: dvui.enums.Cursor = .arrow,
// something dx cursor
arena: std.mem.Allocator = undefined,

const DirectxOptions = struct {
    vertex_shader: ?*dx.ID3D11VertexShader = null,
    pixel_shader: ?*dx.ID3D11PixelShader = null,
    vertex_layout: ?*dx.ID3D11InputLayout = null,
    vertex_buffer: ?*dx.ID3D11Buffer = null,
    index_buffer: ?*dx.ID3D11Buffer = null,
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
}
