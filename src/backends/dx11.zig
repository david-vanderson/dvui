const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
pub const win32 = @import("win32").everything;

pub const kind: dvui.enums.Backend = .dx11;

pub const Dx11Backend = @This();
pub const Context = *align(1) Dx11Backend;

const log = std.log.scoped(.Dx11Backend);

pub const WindowState = struct {
    vsync: bool,

    dvui_window: dvui.Window,

    last_pixel_size: dvui.Size.Physical = .{ .w = 800, .h = 600 },
    last_window_size: dvui.Size.Natural = .{ .w = 800, .h = 600 },
    cursor_last: dvui.enums.Cursor = .arrow,

    texture_interpolation: std.AutoHashMapUnmanaged(*anyopaque, dvui.enums.TextureInterpolation) = .empty,

    device: *win32.ID3D11Device,
    device_context: *win32.ID3D11DeviceContext,
    swap_chain: *win32.IDXGISwapChain,

    render_target: ?*win32.ID3D11RenderTargetView = null,
    dx_options: DirectxOptions = .{},

    // TODO: Implement touch events
    //   might require help with that,
    //   since i have no touch input device that runs windows.
    /// Whether there are touch events
    touch_mouse_events: bool = false,
    /// Whether to log events
    log_events: bool = false,

    /// The arena allocator (usually)
    arena: std.mem.Allocator = undefined,

    pub fn deinit(state: *WindowState) void {
        const gpa = state.dvui_window.gpa;
        state.dvui_window.deinit();
        state.texture_interpolation.deinit(gpa);
        if (state.render_target) |rt| {
            _ = rt.IUnknown.Release();
        }
        _ = state.device.IUnknown.Release();
        _ = state.device_context.IUnknown.Release();
        _ = state.swap_chain.IUnknown.Release();
        state.dx_options.deinit();
        state.* = undefined;
    }
};

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

const DirectxOptions = struct {
    vertex_shader: ?*win32.ID3D11VertexShader = null,
    vertex_bytes: ?*win32.ID3DBlob = null,
    pixel_shader: ?*win32.ID3D11PixelShader = null,
    pixel_bytes: ?*win32.ID3DBlob = null,
    vertex_layout: ?*win32.ID3D11InputLayout = null,
    vertex_buffer: ?*win32.ID3D11Buffer = null,
    index_buffer: ?*win32.ID3D11Buffer = null,
    texture_view: ?*win32.ID3D11ShaderResourceView = null,
    sampler_linear: ?*win32.ID3D11SamplerState = null,
    sampler_nearest: ?*win32.ID3D11SamplerState = null,
    rasterizer: ?*win32.ID3D11RasterizerState = null,
    blend_state: ?*win32.ID3D11BlendState = null,

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
        if (self.sampler_linear) |s| {
            _ = s.IUnknown.Release();
        }
        if (self.sampler_nearest) |s| {
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
    dvui_gpa: std.mem.Allocator,
    /// Passed to `dvui.Window.init`
    dvui_window_init_options: dvui.Window.InitOptions = .{},
    /// The allocator used for temporary allocations used during init()
    allocator: std.mem.Allocator,
    /// The initial size of the application window
    size: ?dvui.Size = null,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,

    vsync: bool,

    /// A windows class that has previously been registered via RegisterClass.
    registered_class: [*:0]const u16,

    /// The application title to display
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
};

pub const Directx11Options = struct {
    /// The device
    device: *win32.ID3D11Device,
    /// The Context
    device_context: *win32.ID3D11DeviceContext,
    /// The Swap chain
    swap_chain: *win32.IDXGISwapChain,
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
fn setViewport(state: *WindowState, width: f32, height: f32) void {
    var vp = win32.D3D11_VIEWPORT{
        .TopLeftX = 0.0,
        .TopLeftY = 0.0,
        .Width = width,
        .Height = height,
        .MinDepth = 0.0,
        .MaxDepth = 1.0,
    };
    state.device_context.RSSetViewports(1, @ptrCast(&vp));
}

pub fn getWindow(context: Context) *dvui.Window {
    return &stateFromHwnd(hwndFromContext(context)).dvui_window;
}

pub const RegisterClassOptions = struct {
    /// styles in addition to DBLCLICKS
    style: win32.WNDCLASS_STYLES = .{},
    // NOTE: we could allow the user to provide their own wndproc which we could
    //       call before or after ours
    //wndproc: ...,
    class_extra: c_int = 0,
    // NOTE: the dx11 backend uses the first @sizeOf(*anyopaque) bytes, any length
    //       added here will be offset by that many bytes
    window_extra_after_sizeof_ptr: c_int = 0,
    instance: union(enum) { this_module, custom: ?win32.HINSTANCE } = .this_module,
    cursor: union(enum) { arrow, custom: ?win32.HICON } = .arrow,
    icon: ?win32.HICON = null,
    icon_small: ?win32.HICON = null,
    bg_brush: ?win32.HBRUSH = null,
    menu_name: ?[*:0]const u16 = null,
};

/// A wrapper for win32.RegisterClass that registers a window class compatible
/// with initWindow. Returns error.Win32 on failure, call win32.GetLastError()
/// for the error code.
///
/// RegisterClass can only be called once for a given name (unless it's been unregistered
/// via UnregisterClass). Typically there's no reason to unregister a window class.
pub fn RegisterClass(name: [*:0]const u16, opt: RegisterClassOptions) error{Win32}!void {
    const wc: win32.WNDCLASSEXW = .{
        .cbSize = @sizeOf(win32.WNDCLASSEXW),
        .style = @bitCast(@as(u32, @bitCast(win32.WNDCLASS_STYLES{ .DBLCLKS = 1 })) | @as(u32, @bitCast(opt.style))),
        .lpfnWndProc = wndProc,
        .cbClsExtra = opt.class_extra,
        .cbWndExtra = @sizeOf(usize) + opt.window_extra_after_sizeof_ptr,
        .hInstance = switch (opt.instance) {
            .this_module => win32.GetModuleHandleW(null),
            .custom => |i| i,
        },
        .hIcon = opt.icon,
        .hIconSm = opt.icon_small,
        .hCursor = switch (opt.cursor) {
            .arrow => win32.LoadCursorW(null, win32.IDC_ARROW),
            .custom => |c| c,
        },
        .hbrBackground = opt.bg_brush,
        .lpszMenuName = opt.menu_name,
        .lpszClassName = name,
    };
    if (0 == win32.RegisterClassExW(&wc)) return error.Win32;
}

/// Creates a new DirectX window for you, as well as initializes all the
/// DirectX options for you
/// The caller just needs to clean up everything by calling `deinit` on the Dx11Backend
pub fn initWindow(window_state: *WindowState, options: InitOptions) !Context {
    const style = win32.WS_OVERLAPPEDWINDOW;
    const style_ex: win32.WINDOW_EX_STYLE = .{ .APPWINDOW = 1, .WINDOWEDGE = 1 };

    const create_args: CreateWindowArgs = .{
        .window_state = window_state,
        .vsync = options.vsync,
        .dvui_gpa = options.dvui_gpa,
        .dvui_window_init_options = options.dvui_window_init_options,
    };
    const hwnd = blk: {
        const wnd_title = try std.unicode.utf8ToUtf16LeAllocZ(options.allocator, options.title);
        defer options.allocator.free(wnd_title);
        break :blk win32.CreateWindowExW(
            style_ex,
            options.registered_class,
            wnd_title,
            style,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            win32.GetModuleHandleW(null),
            @ptrCast(@constCast(&create_args)),
        ) orelse switch (win32.GetLastError()) {
            win32.ERROR_CANNOT_FIND_WND_CLASS => switch (builtin.mode) {
                .Debug => std.debug.panic(
                    "did you forget to call RegisterClass? (class_name='{f}')",
                    .{std.unicode.fmtUtf16Le(std.mem.span(options.registered_class))},
                ),
                else => unreachable,
            },
            else => |win32Err| {
                if (create_args.err) |err| return err;
                win32.panicWin32("CreateWindow", win32Err);
            },
        };
    };

    switch (preferredColorScheme(@ptrCast(hwnd)) orelse .light) {
        .dark => resToErr(
            win32.DwmSetWindowAttribute(hwnd, win32.DWMWA_USE_IMMERSIVE_DARK_MODE, &win32.TRUE, @sizeOf(win32.BOOL)),
            "DwmSetWindowAttribute dark window in initWindow",
        ) catch {},
        .light => {},
    }
    if (dvui.accesskit_enabled) {
        window_state.dvui_window.accesskit.initialize();
    }

    if (options.size) |size| {
        const dpi = win32.GetDpiForWindow(hwnd);
        try boolToErr(@intCast(dpi), "GetDpiForWindow in initWindow");
        const screen_width = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CXSCREEN), dpi);
        const screen_height = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CYSCREEN), dpi);
        var wnd_size: win32.RECT = .{
            .left = 0,
            .top = 0,
            .right = @min(screen_width, @as(i32, @intFromFloat(@round(win32.scaleDpi(f32, size.w, dpi))))),
            .bottom = @min(screen_height, @as(i32, @intFromFloat(@round(win32.scaleDpi(f32, size.h, dpi))))),
        };
        try boolToErr(
            win32.AdjustWindowRectEx(&wnd_size, style, 0, style_ex),
            "AdjustWindowRectEx in initWindow",
        );

        const wnd_width = wnd_size.right - wnd_size.left;
        const wnd_height = wnd_size.bottom - wnd_size.top;
        try boolToErr(win32.SetWindowPos(
            hwnd,
            null,
            @divFloor(screen_width - wnd_width, 2),
            @divFloor(screen_height - wnd_height, 2),
            wnd_width,
            wnd_height,
            win32.SWP_NOCOPYBITS,
        ), "SetWindowPos in initWindow");
    }
    // Returns 0 if the window was previously hidden
    _ = win32.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
    try boolToErr(win32.UpdateWindow(hwnd), "UpdateWindow in initWindow");
    return contextFromHwnd(hwnd);
}

/// Cleanup routine
pub fn deinit(self: Context) void {
    if (0 == win32.DestroyWindow(hwndFromContext(self))) win32.panicWin32("DestroyWindow", win32.GetLastError());
}

/// Resizes the SwapChain based on the new window size
/// This is only useful if you have your own directx stuff to manage
pub fn handleSwapChainResizing(self: Context, width: c_uint, height: c_uint) !void {
    const state = stateFromHwnd(hwndFromContext(self));
    cleanupRenderTarget(state);
    try resToErr(
        state.swap_chain.ResizeBuffers(0, width, height, win32.DXGI_FORMAT_UNKNOWN, 0),
        "ResizeBuffers in handleSwapChainResizing",
    );
    try createRenderTarget(state);
}

pub const ServiceResult = union(enum) {
    queue_empty,
    quit,
};
/// Dispatches messages to any/all native OS windows until either the
/// queue is empty or WM_QUIT/WM_CLOSE are encountered.
pub fn serviceMessageQueue() ServiceResult {
    var msg: win32.MSG = undefined;
    // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-peekmessagea#return-value
    while (win32.PeekMessageA(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
        _ = win32.TranslateMessage(&msg);
        // ignore return value, https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-dispatchmessagew#return-value
        _ = win32.DispatchMessageW(&msg);
        if (msg.message == win32.WM_QUIT) {
            @branchHint(.unlikely);
            return .quit;
        }
    }
    return .queue_empty;
}

fn resToErr(res: win32.HRESULT, what: []const u8) !void {
    if (win32.SUCCEEDED(res)) return;
    std.log.err("{s} failed, hresult=0x{x}", .{ what, res });
    return dvui.Backend.GenericError.BackendError;
}

/// Check the return value and prints `win32.GetLastError()` on failure
fn boolToErr(res: win32.BOOL, what: []const u8) !void {
    if (res != win32.FALSE) return;
    return lastErr(what);
}

/// prints `win32.GetLastError()`
fn lastErr(what: []const u8) !void {
    const err = win32.GetLastError();
    return win32ToErr(err, what);
}

fn win32ToErr(err: win32.WIN32_ERROR, what: []const u8) !void {
    if (err == win32.NO_ERROR) return;
    std.log.err("{s} failed, error={f}", .{ what, err });
    return dvui.Backend.GenericError.BackendError;
}

fn initShader(state: *WindowState) !void {
    var error_message: ?*win32.ID3DBlob = null;

    var vs_blob: ?*win32.ID3DBlob = null;
    const compile_shader = win32.D3DCompile(
        shader.ptr,
        shader.len,
        null,
        null,
        null,
        "VSMain",
        "vs_4_0",
        win32.D3DCOMPILE_ENABLE_STRICTNESS,
        0,
        &vs_blob,
        &error_message,
    );
    if (win32.FAILED(compile_shader)) {
        if (error_message) |msg| {
            defer _ = msg.IUnknown.Release();
            const as_str: [*:0]const u8 = @ptrCast(msg.vtable.GetBufferPointer(error_message.?));
            log.err("vertex shader compilation failed with:\n{s}", .{as_str});
        }
        try resToErr(compile_shader, "vertex shader compilation");
        unreachable;
    }
    state.dx_options.vertex_bytes = vs_blob.?;
    errdefer {
        // TODO: Can this always be freed?
        _ = vs_blob.?.IUnknown.Release();
        state.dx_options.vertex_bytes = null;
    }

    var ps_blob: ?*win32.ID3DBlob = null;
    const ps_res = win32.D3DCompile(
        shader.ptr,
        shader.len,
        null,
        null,
        null,
        "PSMain",
        "ps_4_0",
        win32.D3DCOMPILE_ENABLE_STRICTNESS,
        0,
        &ps_blob,
        &error_message,
    );
    if (win32.FAILED(ps_res)) {
        if (error_message) |msg| {
            defer _ = msg.IUnknown.Release();
            const as_str: [*:0]const u8 = @ptrCast(msg.vtable.GetBufferPointer(error_message.?));
            log.err("pixel shader compilation failed with:\n{s}", .{as_str});
        }
        try resToErr(ps_res, "pixel shader compile");
        unreachable;
    }
    state.dx_options.pixel_bytes = ps_blob.?;
    errdefer {
        // TODO: Can this always be freed?
        _ = ps_blob.?.IUnknown.Release();
        state.dx_options.pixel_bytes = null;
    }

    var vertex_shader_result: @TypeOf(state.dx_options.vertex_shader.?) = undefined;
    try resToErr(state.device.CreateVertexShader(
        @ptrCast(state.dx_options.vertex_bytes.?.GetBufferPointer()),
        state.dx_options.vertex_bytes.?.GetBufferSize(),
        null,
        &vertex_shader_result,
    ), "CreateVertexShader");
    state.dx_options.vertex_shader = vertex_shader_result;

    var pixel_shader_result: @TypeOf(state.dx_options.pixel_shader.?) = undefined;
    try resToErr(state.device.CreatePixelShader(
        @ptrCast(state.dx_options.pixel_bytes.?.GetBufferPointer()),
        state.dx_options.pixel_bytes.?.GetBufferSize(),
        null,
        &pixel_shader_result,
    ), "CreatePixelShader");
    state.dx_options.pixel_shader = pixel_shader_result;
}

fn createRasterizerState(state: *WindowState) !void {
    var raster_desc = std.mem.zeroes(win32.D3D11_RASTERIZER_DESC);
    raster_desc.FillMode = win32.D3D11_FILL_MODE.SOLID;
    raster_desc.CullMode = win32.D3D11_CULL_BACK;
    raster_desc.FrontCounterClockwise = 1;
    raster_desc.DepthClipEnable = 0;
    raster_desc.ScissorEnable = 1;

    // TODO: is this variable needed?
    var rasterizer_result: @TypeOf(state.dx_options.rasterizer.?) = undefined;
    try resToErr(
        state.device.CreateRasterizerState(&raster_desc, &rasterizer_result),
        "CreateRasterizerState in createRasterizerState",
    );
    state.dx_options.rasterizer = rasterizer_result;

    state.device_context.RSSetState(state.dx_options.rasterizer);
}

fn createRenderTarget(state: *WindowState) !void {
    var back_buffer: ?*win32.ID3D11Texture2D = null;

    try resToErr(
        state.swap_chain.GetBuffer(0, win32.IID_ID3D11Texture2D, @ptrCast(&back_buffer)),
        "GetBuffer in createRenderTarget",
    );
    defer _ = back_buffer.?.IUnknown.Release();

    var render_target_result: @TypeOf(state.render_target.?) = undefined;
    try resToErr(state.device.CreateRenderTargetView(
        @ptrCast(back_buffer),
        null,
        &render_target_result,
    ), "CreateRenderTargetView in createRenderTarget");
    state.render_target = render_target_result;
}

fn cleanupRenderTarget(state: *WindowState) void {
    if (state.render_target) |mrtv| {
        _ = mrtv.IUnknown.Release();
        state.render_target = null;
    }
}

fn createInputLayout(state: *WindowState) !void {
    const input_layout_desc = &[_]win32.D3D11_INPUT_ELEMENT_DESC{
        .{ .SemanticName = "POSITION", .SemanticIndex = 0, .Format = win32.DXGI_FORMAT_R32G32B32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 0, .InputSlotClass = win32.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "COLOR", .SemanticIndex = 0, .Format = win32.DXGI_FORMAT_R32G32B32A32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 12, .InputSlotClass = win32.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
        .{ .SemanticName = "TEXCOORD", .SemanticIndex = 0, .Format = win32.DXGI_FORMAT_R32G32_FLOAT, .InputSlot = 0, .AlignedByteOffset = 28, .InputSlotClass = win32.D3D11_INPUT_PER_VERTEX_DATA, .InstanceDataStepRate = 0 },
    };

    const num_elements = input_layout_desc.len;

    var vertex_layout_result: @TypeOf(state.dx_options.vertex_layout.?) = undefined;
    try resToErr(state.device.CreateInputLayout(
        input_layout_desc,
        num_elements,
        @ptrCast(state.dx_options.vertex_bytes.?.GetBufferPointer()),
        state.dx_options.vertex_bytes.?.GetBufferSize(),
        &vertex_layout_result,
    ), "CreateInputLayout in createInputLayout");
    state.dx_options.vertex_layout = vertex_layout_result;

    state.device_context.IASetInputLayout(state.dx_options.vertex_layout);
}

fn recreateShaderView(state: *WindowState, texture: *anyopaque) !void {
    const tex: *win32.ID3D11Texture2D = @ptrCast(@alignCast(texture));

    const rvd = win32.D3D11_SHADER_RESOURCE_VIEW_DESC{
        .Format = win32.DXGI_FORMAT.R8G8B8A8_UNORM,
        .ViewDimension = win32.D3D_SRV_DIMENSION_TEXTURE2D,
        .Anonymous = .{
            .Texture2D = .{
                .MostDetailedMip = 0,
                .MipLevels = 1,
            },
        },
    };

    if (state.dx_options.texture_view) |tv| {
        _ = tv.IUnknown.Release();
    }

    var texture_view_result: @TypeOf(state.dx_options.texture_view.?) = undefined;
    try resToErr(state.device.CreateShaderResourceView(
        &tex.ID3D11Resource,
        &rvd,
        &texture_view_result,
    ), "CreateShaderResourceView in recreateShaderView");
    state.dx_options.texture_view = texture_view_result;
}

fn createSampler(state: *WindowState, interpolation: dvui.enums.TextureInterpolation) !void {
    var samp_desc = std.mem.zeroes(win32.D3D11_SAMPLER_DESC);
    samp_desc.Filter = switch (interpolation) {
        .linear => win32.D3D11_FILTER.MIN_MAG_MIP_LINEAR,
        .nearest => win32.D3D11_FILTER.MIN_MAG_MIP_POINT,
    };
    samp_desc.AddressU = win32.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressV = win32.D3D11_TEXTURE_ADDRESS_MODE.WRAP;
    samp_desc.AddressW = win32.D3D11_TEXTURE_ADDRESS_MODE.WRAP;

    var blend_desc = std.mem.zeroes(win32.D3D11_BLEND_DESC);
    blend_desc.RenderTarget[0].BlendEnable = 1;
    blend_desc.RenderTarget[0].SrcBlend = win32.D3D11_BLEND_ONE;
    blend_desc.RenderTarget[0].DestBlend = win32.D3D11_BLEND_INV_SRC_ALPHA;
    blend_desc.RenderTarget[0].BlendOp = win32.D3D11_BLEND_OP_ADD;
    blend_desc.RenderTarget[0].SrcBlendAlpha = win32.D3D11_BLEND_ONE;
    blend_desc.RenderTarget[0].DestBlendAlpha = win32.D3D11_BLEND_INV_SRC_ALPHA;
    blend_desc.RenderTarget[0].BlendOpAlpha = win32.D3D11_BLEND_OP_ADD;
    blend_desc.RenderTarget[0].RenderTargetWriteMask = @intFromEnum(win32.D3D11_COLOR_WRITE_ENABLE_ALL);

    // TODO: Handle errors better
    var blend_state_result: @TypeOf(state.dx_options.blend_state.?) = undefined;
    try resToErr(state.device.CreateBlendState(&blend_desc, &blend_state_result), "CreateBlendState in createSampler");
    state.dx_options.blend_state = blend_state_result;
    state.device_context.OMSetBlendState(state.dx_options.blend_state, null, 0xffffffff);

    var sampler_result: *win32.ID3D11SamplerState = undefined;
    try resToErr(state.device.CreateSamplerState(&samp_desc, &sampler_result), "CreateSamplerState in createSampler");
    switch (interpolation) {
        .linear => state.dx_options.sampler_linear = sampler_result,
        .nearest => state.dx_options.sampler_nearest = sampler_result,
    }
}

// If you don't know what they are used for... just don't use them, alright?
fn createBuffer(state: *WindowState, bind_type: anytype, comptime InitialType: type, initial_data: []const InitialType) !*win32.ID3D11Buffer {
    var bd = std.mem.zeroes(win32.D3D11_BUFFER_DESC);
    bd.Usage = win32.D3D11_USAGE_DEFAULT;
    bd.ByteWidth = @intCast(@sizeOf(InitialType) * initial_data.len);
    bd.BindFlags = bind_type;
    bd.CPUAccessFlags = .{};

    var data: win32.D3D11_SUBRESOURCE_DATA = undefined;
    data.pSysMem = @ptrCast(initial_data.ptr);

    var buffer: *win32.ID3D11Buffer = undefined;
    try resToErr(state.device.CreateBuffer(&bd, &data, &buffer), "CreateBuffer in createBuffer");

    // argument no longer pointer-to-optional since zigwin32 update - 2025-01-10
    //if (buffer) |buf| {
    return buffer;
    //} else {
    //    return error.BufferFailedToCreate;
    //}
}

// ############ Satisfy DVUI interfaces ############
pub fn textureCreate(self: Context, pixels: [*]const u8, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.Texture {
    const state = stateFromHwnd(hwndFromContext(self));

    var texture: *win32.ID3D11Texture2D = undefined;
    var tex_desc = win32.D3D11_TEXTURE2D_DESC{
        .Width = width,
        .Height = height,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = win32.DXGI_FORMAT.R8G8B8A8_UNORM,
        .SampleDesc = .{
            .Count = 1,
            .Quality = 0,
        },
        .Usage = win32.D3D11_USAGE_DEFAULT,
        .BindFlags = win32.D3D11_BIND_SHADER_RESOURCE,
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
    };

    var resource_data = std.mem.zeroes(win32.D3D11_SUBRESOURCE_DATA);
    resource_data.pSysMem = pixels;
    resource_data.SysMemPitch = width * 4; // 4 byte per pixel (RGBA)

    resToErr(
        state.device.CreateTexture2D(&tex_desc, &resource_data, &texture),
        "CreateTexture2D in textureCreate",
    ) catch return dvui.Backend.TextureError.TextureCreate;
    errdefer _ = texture.IUnknown.Release();

    try state.texture_interpolation.put(state.dvui_window.gpa, texture, interpolation);

    return dvui.Texture{ .ptr = texture, .width = width, .height = height };
}

pub fn textureCreateTarget(self: Context, width: u32, height: u32, interpolation: dvui.enums.TextureInterpolation) !dvui.TextureTarget {
    const state = stateFromHwnd(hwndFromContext(self));

    const texture_desc = win32.D3D11_TEXTURE2D_DESC{
        .Height = height,
        .Width = width,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = win32.DXGI_FORMAT.R8G8B8A8_UNORM,
        .SampleDesc = .{
            .Count = 1,
            .Quality = 0,
        },
        .Usage = win32.D3D11_USAGE.DEFAULT,
        .BindFlags = .{ .RENDER_TARGET = 1 },
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
    };
    var texture: *win32.ID3D11Texture2D = undefined;
    resToErr(
        state.device.CreateTexture2D(&texture_desc, null, &texture),
        "CreateTexture2D target",
    ) catch return dvui.Backend.TextureError.TextureCreate;
    errdefer _ = texture.IUnknown.Release();

    try state.texture_interpolation.put(state.dvui_window.gpa, texture, interpolation);
    return .{ .ptr = @ptrCast(texture), .width = width, .height = height };
}

pub fn textureReadTarget(self: Context, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    const state = stateFromHwnd(hwndFromContext(self));
    const tex: *win32.ID3D11Texture2D = @ptrCast(@alignCast(texture.ptr));

    const texture_desc = win32.D3D11_TEXTURE2D_DESC{
        .Height = texture.height,
        .Width = texture.width,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = win32.DXGI_FORMAT.R8G8B8A8_UNORM,
        .SampleDesc = .{
            .Count = 1,
            .Quality = 0,
        },
        .Usage = win32.D3D11_USAGE.STAGING,
        .BindFlags = .{},
        .CPUAccessFlags = .{ .READ = 1 },
        .MiscFlags = .{},
    };
    var staging: *win32.ID3D11Texture2D = undefined;
    resToErr(
        state.device.CreateTexture2D(&texture_desc, null, &staging),
        "CreateTexture2D in textureReadTarget",
    ) catch return dvui.Backend.TextureError.TextureCreate;
    defer _ = staging.IUnknown.Release();

    state.device_context.CopyResource(&staging.ID3D11Resource, &tex.ID3D11Resource);
    defer state.device_context.Unmap(&staging.ID3D11Resource, 0);

    var mapped: win32.D3D11_MAPPED_SUBRESOURCE = undefined;
    resToErr(
        state.device_context.Map(&staging.ID3D11Resource, 0, win32.D3D11_MAP.READ, 0, &mapped),
        "Map in textureReadTarget",
    ) catch return dvui.Backend.TextureError.TextureRead;

    if (mapped.pData) |data_ptr| {
        const data: [*]const u8 = @ptrCast(data_ptr);
        const row_len = texture.width * 4;
        for (0..texture.height) |i| {
            const offset = (i * row_len);
            // copy row by row as mapping may not store the rows contiguously
            @memcpy(pixels_out[offset..(offset + row_len)], data + (i * mapped.RowPitch));
        }
    }
}

pub fn textureDestroy(self: Context, texture: dvui.Texture) void {
    const state = stateFromHwnd(hwndFromContext(self));
    const tex: *win32.ID3D11Texture2D = @ptrCast(@alignCast(texture.ptr));
    if (!state.texture_interpolation.remove(texture.ptr)) {
        log.err("Destroyed texture that did not have a stored interpolation", .{});
    }
    _ = tex.IUnknown.Release();
}

pub fn textureFromTarget(self: Context, texture: dvui.TextureTarget) !dvui.Texture {
    const state = stateFromHwnd(hwndFromContext(self));

    // DX11 can't draw target textures, so read all the pixels and make a new texture

    const pixels = try state.arena.alloc(u8, texture.width * texture.height * 4);
    defer state.arena.free(pixels);
    try self.textureReadTarget(texture, pixels.ptr);

    const tex: *win32.ID3D11Texture2D = @ptrCast(@alignCast(texture.ptr));
    const interpolation = if (state.texture_interpolation.fetchRemove(texture.ptr)) |kv| kv.value else blk: {
        log.err("Target texture destroyed that did not have a stored interpolation", .{});
        break :blk .linear;
    };
    _ = tex.IUnknown.Release();

    return self.textureCreate(pixels.ptr, texture.width, texture.height, interpolation);
}

pub fn renderTarget(self: Context, texture: ?dvui.TextureTarget) !void {
    const state = stateFromHwnd(hwndFromContext(self));
    cleanupRenderTarget(state);
    if (texture) |tex| {
        const target: *win32.ID3D11Texture2D = @ptrCast(@alignCast(tex.ptr));
        var render_target: @TypeOf(state.render_target.?) = undefined;
        errdefer state.render_target = null;
        try resToErr(state.device.CreateRenderTargetView(
            @ptrCast(&target.ID3D11Resource),
            null,
            &render_target,
        ), "CreateRenderTargetView in renderTarget");
        state.device_context.ClearRenderTargetView(render_target, @ptrCast(&[4]f32{ 0, 0, 0, 0 }));
        state.render_target = render_target;
    } else {
        state.render_target = null;
    }
}

pub fn drawClippedTriangles(
    self: Context,
    texture: ?dvui.Texture,
    vtx: []const dvui.Vertex,
    idx: []const u16,
    clipr: ?dvui.Rect.Physical,
) !void {
    const state = stateFromHwnd(hwndFromContext(self));
    const client_size = win32.getClientSize(hwndFromContext(self));
    setViewport(state, @floatFromInt(client_size.cx), @floatFromInt(client_size.cy));

    if (state.render_target == null) try createRenderTarget(state);
    if (state.dx_options.vertex_shader == null or state.dx_options.pixel_shader == null) try initShader(state);
    if (state.dx_options.vertex_layout == null) try createInputLayout(state);
    if (state.dx_options.sampler_linear == null) try createSampler(state, .linear);
    if (state.dx_options.sampler_nearest == null) try createSampler(state, .nearest);
    if (state.dx_options.rasterizer == null) try createRasterizerState(state);

    var stride: usize = @sizeOf(SimpleVertex);
    var offset: usize = 0;
    const converted_vtx = try convertVertices(state.arena, .{
        .w = @floatFromInt(client_size.cx),
        .h = @floatFromInt(client_size.cy),
    }, vtx, texture == null);
    defer state.arena.free(converted_vtx);

    // Do yourself a favour and don't touch it.
    // End() isn't being called all the time, so it's kind of futile.
    if (state.dx_options.vertex_buffer) |vb| {
        _ = vb.IUnknown.Release();
    }
    state.dx_options.vertex_buffer = try createBuffer(state, win32.D3D11_BIND_VERTEX_BUFFER, SimpleVertex, converted_vtx);

    // Do yourself a favour and don't touch it.
    // End() isn't being called all the time, so it's kind of futile.
    if (state.dx_options.index_buffer) |ib| {
        _ = ib.IUnknown.Release();
    }
    state.dx_options.index_buffer = try createBuffer(state, win32.D3D11_BIND_INDEX_BUFFER, u16, idx);

    setViewport(state, @floatFromInt(client_size.cx), @floatFromInt(client_size.cy));

    if (texture) |tex| try recreateShaderView(state, tex.ptr);
    const interpolation = if (texture) |tex| state.texture_interpolation.get(tex.ptr) orelse .linear else .linear;

    var scissor_rect: ?win32.RECT = std.mem.zeroes(win32.RECT);
    var nums: u32 = 1;
    state.device_context.RSGetScissorRects(&nums, @ptrCast(&scissor_rect));

    if (clipr) |cr| {
        const new_clip: win32.RECT = .{
            .left = @intFromFloat(cr.x),
            .top = @intFromFloat(cr.y),
            .right = @intFromFloat(cr.x + cr.w),
            .bottom = @intFromFloat(cr.y + cr.h),
        };
        state.device_context.RSSetScissorRects(nums, @ptrCast(&new_clip));
    } else {
        scissor_rect = null;
    }

    state.device_context.IASetVertexBuffers(0, 1, @ptrCast(&state.dx_options.vertex_buffer), @ptrCast(&stride), @ptrCast(&offset));
    state.device_context.IASetIndexBuffer(state.dx_options.index_buffer, win32.DXGI_FORMAT.R16_UINT, 0);
    state.device_context.IASetPrimitiveTopology(win32.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

    state.device_context.OMSetRenderTargets(1, @ptrCast(&state.render_target), null);
    state.device_context.VSSetShader(state.dx_options.vertex_shader, null, 0);
    state.device_context.PSSetShader(state.dx_options.pixel_shader, null, 0);

    state.device_context.PSSetShaderResources(0, 1, @ptrCast(&state.dx_options.texture_view));
    state.device_context.PSSetSamplers(0, 1, switch (interpolation) {
        .linear => @ptrCast(&state.dx_options.sampler_linear),
        .nearest => @ptrCast(&state.dx_options.sampler_nearest),
    });
    state.device_context.DrawIndexed(@intCast(idx.len), 0, 0);
    if (scissor_rect) |srect| state.device_context.RSSetScissorRects(nums, @ptrCast(&srect));
}

pub fn begin(self: Context, arena: std.mem.Allocator) !void {
    const state = stateFromHwnd(hwndFromContext(self));
    state.arena = arena;

    const pixel_size = self.pixelSize();
    var scissor_rect: win32.RECT = .{
        .left = 0,
        .top = 0,
        .right = @intFromFloat(@round(pixel_size.w)),
        .bottom = @intFromFloat(@round(pixel_size.h)),
    };
    state.device_context.RSSetScissorRects(1, @ptrCast(&scissor_rect));

    var clear_color = [_]f32{ 1.0, 1.0, 1.0, 0.0 };
    state.device_context.ClearRenderTargetView(state.render_target orelse return, @ptrCast((&clear_color).ptr));
}

pub fn end(self: Context) !void {
    const state = stateFromHwnd(hwndFromContext(self));
    try resToErr(state.swap_chain.Present(if (state.vsync) 1 else 0, 0), "Present in end");
}

pub fn pixelSize(self: Context) dvui.Size.Physical {
    const hwnd = hwndFromContext(self);
    const state = stateFromHwnd(hwnd);
    var rect: win32.RECT = undefined;
    resToErr(win32.GetClientRect(hwnd, &rect), "GetClientRect in pixelSize") catch return state.last_pixel_size;
    std.debug.assert(rect.left == 0);
    std.debug.assert(rect.top == 0);
    state.last_pixel_size = .{
        .w = @floatFromInt(rect.right),
        .h = @floatFromInt(rect.bottom),
    };
    return state.last_pixel_size;
}

pub fn windowSize(self: Context) dvui.Size.Natural {
    const hwnd = hwndFromContext(self);
    const state = stateFromHwnd(hwnd);
    const size = self.pixelSize();
    // apply dpi scaling manually as there is no convenient api to get the window
    // size of the client size. `win32.GetWindowRect` includes window decorations
    const dpi = win32.GetDpiForWindow(hwnd);
    boolToErr(@intCast(dpi), "GetDpiForWindow in windowSize") catch return state.last_window_size;
    state.last_window_size = .{
        .w = size.w / win32.scaleFromDpi(f32, dpi),
        .h = size.h / win32.scaleFromDpi(f32, dpi),
    };
    return state.last_window_size;
}

pub fn contentScale(_: Context) f32 {
    return 1.0;
    //return @as(f32, @floatFromInt(win32.dpiFromHwnd(hwndFromContext(self)))) / 96.0;
}

pub fn hasEvent(_: Context) bool {
    return false;
}

pub fn backend(self: Context) dvui.Backend {
    return dvui.Backend.init(self);
}

pub fn nanoTime(_: Context) i128 {
    return std.time.nanoTimestamp();
}

pub fn sleep(_: Context, ns: u64) void {
    std.Thread.sleep(ns);
}

pub fn clipboardText(self: Context) ![]const u8 {
    const state = stateFromHwnd(hwndFromContext(self));
    boolToErr(win32.OpenClipboard(hwndFromContext(self)), "OpenClipboard in clipboardText") catch return "";
    defer boolToErr(win32.CloseClipboard(), "CloseClipboard in clipboardText") catch {};

    // istg, windows. why. why utf16.
    const data_handle = win32.GetClipboardData(@intFromEnum(win32.CF_UNICODETEXT)) orelse {
        lastErr("GetClipboardData in clipboardText") catch {};
        return "";
    };

    var res: []u8 = undefined;
    {
        const handle: isize = @intCast(@intFromPtr(data_handle));
        const data: [*:0]u16 = @ptrCast(@alignCast(win32.GlobalLock(handle) orelse return ""));
        defer boolToErr(win32.GlobalUnlock(handle), "GlobalUnlock in clipboardText") catch {};

        // we want this to be a sane format.
        res = std.unicode.utf16LeToUtf8Alloc(state.arena, std.mem.span(data)) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            else => return dvui.Backend.GenericError.BackendError,
        };
    }

    return res;
}

pub fn clipboardTextSet(self: Context, text: []const u8) !void {
    const state = stateFromHwnd(hwndFromContext(self));
    boolToErr(win32.OpenClipboard(hwndFromContext(self)), "OpenClipboard in clipboardTextSet") catch return;
    defer boolToErr(win32.CloseClipboard(), "CloseClipboard in clipboardTextSet") catch {};

    const handle = win32.GlobalAlloc(win32.GMEM_MOVEABLE, text.len * @sizeOf(u16) + 1); // don't forget the nullbyte
    if (handle == 0) return std.mem.Allocator.Error.OutOfMemory;

    const as_utf16 = std.unicode.utf8ToUtf16LeAlloc(state.arena, text) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => return dvui.Backend.GenericError.BackendError,
    };
    defer state.arena.free(as_utf16);

    const data: [*:0]u16 = @ptrCast(@alignCast(win32.GlobalLock(handle) orelse return));
    defer boolToErr(win32.GlobalUnlock(handle), "GlobalUnlock in clipboardTextSet") catch {};

    for (as_utf16, 0..) |wide, i| {
        data[i] = wide;
    }

    try boolToErr(win32.EmptyClipboard(), "EmptyClipboard in clipboardTextSet");
    const handle_usize: usize = @intCast(handle);
    _ = win32.SetClipboardData(@intFromEnum(win32.CF_UNICODETEXT), @ptrFromInt(handle_usize)) orelse try lastErr("SetClipboardData in clipboardTextSet");
}

pub fn openURL(self: Context, url: []const u8, _: bool) !void {
    const hwnd = hwndFromContext(self);
    const arena = stateFromHwnd(hwnd).arena;

    const win_url = std.unicode.utf8ToUtf16LeAllocZ(arena, url) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => return dvui.Backend.GenericError.BackendError,
    };
    defer arena.free(win_url);

    _ = win32.ShellExecuteW(
        hwnd,
        win32.L("open"),
        win_url,
        null,
        null,
        win32.SW_SHOW.SHOWNORMAL,
    );
}

pub fn preferredColorScheme(_: Context) ?dvui.enums.ColorScheme {
    return dvui.Backend.Common.windowsGetPreferredColorScheme();
}
pub fn cursorShow(_: Context, value: ?bool) !bool {
    var info: win32.CURSORINFO = undefined;
    info.cbSize = @sizeOf(win32.CURSORINFO);
    try boolToErr(win32.GetCursorInfo(&info), "GetCursorInfo in cursorShow");
    const prev = info.flags == win32.CURSOR_SHOWING;
    if (value) |val| {
        // Count == 0 will hide cursor. Any value greater than 0 will show it
        // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showcursor#remarks
        const count = win32.ShowCursor(if (val) win32.TRUE else win32.FALSE);
        if (!val and count > 0) {
            // Keep hiding cursor until it's hidden
            for (0..@intCast(count)) |_| {
                if (win32.ShowCursor(win32.FALSE) == 0) break;
            }
        }
    }
    return prev;
}

pub fn refresh(_: Context) void {}

pub fn setCursor(ctx: Context, cursor: dvui.enums.Cursor) !void {
    const self = stateFromHwnd(hwndFromContext(ctx));
    if (cursor == self.cursor_last) return;
    defer self.cursor_last = cursor;
    const new_shown_state = if (cursor == .hidden) false else if (self.cursor_last == .hidden) true else null;
    if (new_shown_state) |new_state| {
        if (try ctx.cursorShow(new_state) == new_state) {
            log.err("Cursor shown state was out of sync", .{});
        }
        // Return early if we are hiding
        if (new_state == false) return;
    }

    const converted_cursor = switch (cursor) {
        .arrow => win32.IDC_ARROW,
        .ibeam => win32.IDC_IBEAM,
        .wait, .wait_arrow => win32.IDC_WAIT,
        .crosshair => win32.IDC_CROSS,
        .arrow_nw_se => win32.IDC_SIZENWSE,
        .arrow_ne_sw => win32.IDC_SIZENESW,
        .arrow_w_e => win32.IDC_SIZEWE,
        .arrow_n_s => win32.IDC_SIZENS,
        .arrow_all => win32.IDC_SIZEALL,
        .bad => win32.IDC_NO,
        .hand => win32.IDC_HAND,
        .hidden => unreachable,
    };

    if (win32.LoadCursorW(null, converted_cursor)) |hcursor| {
        // NOTE: We set the class cursor because using win32.setCursor requires handling win32.WN_SETCURSOR
        // and messes with the default resize cursors of the window.
        _ = win32.SetClassLongPtrW(
            hwndFromContext(ctx),
            win32.GCLP_HCURSOR, // change cursor
            @intCast(@intFromPtr(hcursor)),
        );
    }
}

pub fn hwndFromContext(ctx: Context) win32.HWND {
    return @ptrCast(ctx);
}
pub fn contextFromHwnd(hwnd: win32.HWND) Context {
    return @ptrCast(hwnd);
}
fn stateFromHwnd(hwnd: win32.HWND) *WindowState {
    const addr: usize = @bitCast(win32.GetWindowLongPtrW(hwnd, win32.WINDOW_LONG_PTR_INDEX._USERDATA));
    if (addr == 0) @panic("window is missing it's state!");
    return @ptrFromInt(addr);
}

pub fn attach(
    hwnd: win32.HWND,
    window_state: *WindowState,
    gpa: std.mem.Allocator,
    dx_options: Directx11Options,
    opt: struct {
        vsync: bool,
        window_init_opts: dvui.Window.InitOptions = .{},
    },
) !Context {
    const existing = win32.SetWindowLongPtrW(
        hwnd,
        win32.WINDOW_LONG_PTR_INDEX._USERDATA,
        @bitCast(@intFromPtr(window_state)),
    );
    if (existing != 0) std.debug.panic("hwnd is already using slot 0 for something? (0x{x})", .{existing});

    const addr: usize = @bitCast(win32.GetWindowLongPtrW(hwnd, win32.WINDOW_LONG_PTR_INDEX._USERDATA));
    if (addr == 0) @panic("unable to attach window state pointer to HWND, did you set cbWndExtra to be >= to @sizeof(usize)?");

    const ctx = contextFromHwnd(hwnd).backend();

    var dvui_window = try dvui.Window.init(@src(), gpa, ctx, opt.window_init_opts);
    errdefer dvui_window.deinit();
    window_state.* = .{
        .vsync = opt.vsync,
        .dvui_window = dvui_window,
        .device = dx_options.device,
        .device_context = dx_options.device_context,
        .swap_chain = dx_options.swap_chain,
    };

    std.debug.assert(stateFromHwnd(hwnd) == window_state);
    return contextFromHwnd(hwnd);
}

// ############ Event Handling via wnd proc ############
pub fn wndProc(
    hwnd: win32.HWND,
    umsg: u32,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    switch (umsg) {
        win32.WM_CREATE => {
            const create_struct: *win32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const args: *CreateWindowArgs = @ptrCast(@alignCast(create_struct.lpCreateParams));
            const dx_options = createDeviceD3D(hwnd) orelse {
                args.err = error.D3dDeviceInitFailed;
                return -1;
            };
            errdefer dx_options.deinit();
            _ = attach(hwnd, args.window_state, args.dvui_gpa, dx_options, .{
                .vsync = args.vsync,
                .window_init_opts = args.dvui_window_init_options,
            }) catch |e| {
                args.err = e;
                return -1;
            };
            return 0;
        },
        win32.WM_DESTROY => {
            const state = stateFromHwnd(hwnd);
            state.deinit();
            return 0;
        },
        win32.WM_CLOSE => {
            // important not call DefWindowProc here because that will destroy the window
            // without notifying the app
            const state = stateFromHwnd(hwnd);
            state.dvui_window.addEventWindow(.{ .action = .close }) catch {};
            return 0;
        },
        win32.WM_PAINT => {
            var ps: win32.PAINTSTRUCT = undefined;
            if (win32.BeginPaint(hwnd, &ps) == null) lastErr("BeginPaint") catch return -1;
            boolToErr(win32.EndPaint(hwnd, &ps), "EndPaint") catch return -1;
            return 0;
        },
        win32.WM_SIZE => {
            const size = win32.getClientSize(hwnd);
            //const resize: packed struct { width: i16, height: i16, _upper: i32 } = @bitCast(lparam);
            // instance.options.size.w = @floatFromInt(resize.width);
            // instance.options.size.h = @floatFromInt(resize.height);
            contextFromHwnd(hwnd).handleSwapChainResizing(@intCast(size.cx), @intCast(size.cy)) catch {
                log.err("Failed to handle swap chain resizing...", .{});
            };
            return 0;
        },
        // All mouse events
        win32.WM_LBUTTONDOWN,
        win32.WM_LBUTTONDBLCLK,
        win32.WM_RBUTTONDOWN,
        win32.WM_MBUTTONDOWN,
        win32.WM_XBUTTONDOWN,
        win32.WM_LBUTTONUP,
        win32.WM_RBUTTONUP,
        win32.WM_MBUTTONUP,
        win32.WM_XBUTTONUP,
        => |msg| {
            const button: dvui.enums.Button = switch (msg) {
                win32.WM_LBUTTONDOWN, win32.WM_LBUTTONDBLCLK, win32.WM_LBUTTONUP => .left,
                win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP => .right,
                win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP => .middle,
                win32.WM_XBUTTONDOWN, win32.WM_XBUTTONUP => switch (win32.hiword(wparam)) {
                    0x0001 => .four,
                    0x0002 => .five,
                    else => unreachable,
                },
                else => unreachable,
            };
            _ = stateFromHwnd(hwnd).dvui_window.addEventMouseButton(
                button,
                switch (msg) {
                    win32.WM_LBUTTONDOWN, win32.WM_LBUTTONDBLCLK, win32.WM_RBUTTONDOWN, win32.WM_MBUTTONDOWN, win32.WM_XBUTTONDOWN => .press,
                    win32.WM_LBUTTONUP, win32.WM_RBUTTONUP, win32.WM_MBUTTONUP, win32.WM_XBUTTONUP => .release,
                    else => unreachable,
                },
            ) catch {};
            return 0;
        },
        win32.WM_MOUSEMOVE => {
            const x = win32.xFromLparam(lparam);
            const y = win32.yFromLparam(lparam);
            _ = stateFromHwnd(hwnd).dvui_window.addEventMouseMotion(
                .{
                    .pt = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) },
                },
            ) catch {};
            return 0;
        },
        win32.WM_MOUSEWHEEL,
        win32.WM_MOUSEHWHEEL,
        => |msg| {
            const delta: i16 = @bitCast(win32.hiword(wparam));
            const float_delta: f32 = @floatFromInt(delta);
            const wheel_delta: f32 = @floatFromInt(win32.WHEEL_DELTA);
            _ = stateFromHwnd(hwnd).dvui_window.addEventMouseWheel(
                float_delta / wheel_delta * dvui.scroll_speed,
                switch (msg) {
                    win32.WM_MOUSEWHEEL => .vertical,
                    win32.WM_MOUSEHWHEEL => .horizontal,
                    else => unreachable,
                },
            ) catch {};
            return 0;
        },
        // All key events
        win32.WM_KEYUP,
        win32.WM_SYSKEYUP,
        win32.WM_KEYDOWN,
        win32.WM_SYSKEYDOWN,
        => |msg| {
            // https://learn.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input#keystroke-message-flags
            const KeystrokeMessageFlags = packed struct(u32) {
                /// The repeat count for the current message. The value is the number of times
                /// the keystroke is autorepeated as a result of the user holding down the key.
                /// The repeat count is always 1 for a WM_KEYUP message.
                repeat_count: u16,
                /// The scan code. The value depends on the OEM.
                scan_code: u8,
                /// Indicates whether the key is an extended key, such as the right-hand ALT
                /// and CTRL keys that appear on an enhanced 101- or 102-key keyboard. The value
                /// is 1 if it is an extended key; otherwise, it is 0.
                is_extended_key: bool,
                _reserved: u4,
                /// The context code. The value is always 0 for a WM_KEYUP message.
                has_alt_down: bool,
                /// The previous key state. The value is always 1 for a WM_KEYUP message.
                was_key_down: bool,
                /// The transition state. The value is always 1 for a WM_KEYUP message.
                is_key_released: bool,
            };
            const info: KeystrokeMessageFlags = @bitCast(@as(i32, @truncate(lparam)));

            if (std.meta.intToEnum(win32.VIRTUAL_KEY, wparam)) |as_vkey| {
                // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getasynckeystate
                // NOTE: If the key is pressed, the most significant bit is set.
                //       For a signed integer that means it's a negative number
                //       if the key is currently down.
                var mods = dvui.enums.Mod.none;
                if (win32.GetAsyncKeyState(@intFromEnum(win32.VK_LSHIFT)) < 0) mods.combine(.lshift);
                if (win32.GetAsyncKeyState(@intFromEnum(win32.VK_RSHIFT)) < 0) mods.combine(.rshift);
                if (win32.GetAsyncKeyState(@intFromEnum(win32.VK_LCONTROL)) < 0) mods.combine(.lcontrol);
                if (win32.GetAsyncKeyState(@intFromEnum(win32.VK_RCONTROL)) < 0) mods.combine(.rcontrol);
                if (win32.GetAsyncKeyState(@intFromEnum(win32.VK_LMENU)) < 0) mods.combine(.lalt);
                if (win32.GetAsyncKeyState(@intFromEnum(win32.VK_RMENU)) < 0) mods.combine(.ralt);
                // Command mods would be the windows key, which we do not handle

                const code = convertVKeyToDvuiKey(as_vkey);

                const state = stateFromHwnd(hwnd);
                _ = state.dvui_window.addEventKey(.{
                    .code = code,
                    .action = switch (msg) {
                        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN => if (info.was_key_down) .repeat else .down,
                        win32.WM_KEYUP, win32.WM_SYSKEYUP => .up,
                        else => unreachable,
                    },
                    .mod = mods,
                }) catch {};
                // Repeats are counted, so we produce an event for each additional repeat
                for (1..info.repeat_count) |_| {
                    _ = state.dvui_window.addEventKey(.{
                        .code = code,
                        .action = .repeat,
                        .mod = mods,
                    }) catch {};
                }
            } else |err| {
                log.err("invalid key found: {t}", .{err});
            }
            return switch (msg) {
                win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP => win32.DefWindowProcW(hwnd, umsg, wparam, lparam),
                else => 0,
            };
        },
        win32.WM_CHAR => {
            const state = stateFromHwnd(hwnd);
            const ascii_char: u8 = @truncate(wparam);
            if (std.ascii.isPrint(ascii_char)) {
                const string: []const u8 = &.{ascii_char};
                _ = state.dvui_window.addEventText(.{ .text = string }) catch {};
            }
            return 0;
        },
        win32.WM_SETFOCUS, win32.WM_EXITSIZEMOVE, win32.WM_EXITMENULOOP => {
            if (dvui.accesskit_enabled and stateFromHwnd(hwnd).dvui_window.accesskit.status != .off) {
                const events = dvui.AccessKit.c.accesskit_windows_adapter_update_window_focus_state(stateFromHwnd(hwnd).dvui_window.accesskit.adapter, true);
                if (events) |_| {
                    dvui.AccessKit.c.accesskit_windows_queued_events_raise(events);
                }
            }
            return 0;
        },
        win32.WM_KILLFOCUS, win32.WM_ENTERSIZEMOVE, win32.WM_ENTERMENULOOP => {
            if (dvui.accesskit_enabled and stateFromHwnd(hwnd).dvui_window.accesskit.status != .off) {
                const events = dvui.AccessKit.c.accesskit_windows_adapter_update_window_focus_state(stateFromHwnd(hwnd).dvui_window.accesskit.adapter, false);
                if (events) |_| {
                    dvui.AccessKit.c.accesskit_windows_queued_events_raise(events);
                }
            }
            return 0;
        },
        win32.WM_GETOBJECT => {
            if (dvui.accesskit_enabled) {
                const state = stateFromHwnd(hwnd);
                const ak = state.dvui_window.accesskit;
                const result = dvui.AccessKit.c.accesskit_windows_adapter_handle_wm_getobject(
                    ak.adapter,
                    wparam,
                    lparam,
                    if (ak.status != .on) dvui.AccessKit.initialTreeUpdate else dvui.AccessKit.frameTreeUpdate,
                    &stateFromHwnd(hwnd).dvui_window.accesskit,
                );
                if (result.has_value) {
                    return result.value;
                }
            }
            return win32.DefWindowProcW(hwnd, umsg, wparam, lparam);
        },
        else => return win32.DefWindowProcW(hwnd, umsg, wparam, lparam),
    }
}

// ############ Utilities ############
fn convertSpaceToNDC(size: dvui.Size, x: f32, y: f32) XMFLOAT3 {
    return XMFLOAT3{
        .x = (2.0 * x / size.w) - 1.0,
        .y = 1.0 - (2.0 * y / size.h),
        .z = 0.0,
    };
}

fn convertVertices(
    arena: std.mem.Allocator,
    size: dvui.Size,
    vtx: []const dvui.Vertex,
    signal_invalid_uv: bool,
) ![]SimpleVertex {
    const simple_vertex = try arena.alloc(SimpleVertex, vtx.len);
    for (vtx, simple_vertex) |v, *s| {
        const r: f32 = @floatFromInt(v.col.r);
        const g: f32 = @floatFromInt(v.col.g);
        const b: f32 = @floatFromInt(v.col.b);
        const a: f32 = @floatFromInt(v.col.a);

        s.* = .{
            .position = convertSpaceToNDC(size, v.pos.x, v.pos.y),
            .color = .{ .r = r / 255.0, .g = g / 255.0, .b = b / 255.0, .a = a / 255.0 },
            .texcoord = if (signal_invalid_uv) .{ .x = -1.0, .y = -1.0 } else .{ .x = v.uv[0], .y = v.uv[1] },
        };
    }

    return simple_vertex;
}

const CreateWindowArgs = struct {
    window_state: *WindowState,
    vsync: bool,
    dvui_window_init_options: dvui.Window.InitOptions,
    dvui_gpa: std.mem.Allocator,
    err: ?anyerror = null,
};

fn createDeviceD3D(hwnd: win32.HWND) ?Directx11Options {
    const client_size = win32.getClientSize(hwnd);

    var sd = std.mem.zeroes(win32.DXGI_SWAP_CHAIN_DESC);
    sd.BufferCount = 6;
    sd.BufferDesc.Width = @intCast(client_size.cx);
    sd.BufferDesc.Height = @intCast(client_size.cy);
    sd.BufferDesc.Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = @intFromEnum(win32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH);
    sd.BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT;
    @setRuntimeSafety(false);
    sd.OutputWindow = hwnd;
    @setRuntimeSafety(true);
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = 1;
    sd.SwapEffect = win32.DXGI_SWAP_EFFECT_DISCARD;

    const createDeviceFlags: win32.D3D11_CREATE_DEVICE_FLAG = .{
        .DEBUG = 0,
    };
    //createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
    var featureLevel: win32.D3D_FEATURE_LEVEL = undefined;
    const featureLevelArray = &[_]win32.D3D_FEATURE_LEVEL{ win32.D3D_FEATURE_LEVEL_11_0, win32.D3D_FEATURE_LEVEL_10_0 };

    var device: *win32.ID3D11Device = undefined;
    var device_context: *win32.ID3D11DeviceContext = undefined;
    var swap_chain: *win32.IDXGISwapChain = undefined;

    resToErr(switch (win32.D3D11CreateDeviceAndSwapChain(
        null,
        win32.D3D_DRIVER_TYPE_HARDWARE,
        null,
        createDeviceFlags,
        featureLevelArray,
        2,
        win32.D3D11_SDK_VERSION,
        &sd,
        &swap_chain,
        &device,
        &featureLevel,
        &device_context,
    )) {
        win32.DXGI_ERROR_UNSUPPORTED => win32.D3D11CreateDeviceAndSwapChain(
            null,
            win32.D3D_DRIVER_TYPE_WARP,
            null,
            createDeviceFlags,
            featureLevelArray,
            2,
            win32.D3D11_SDK_VERSION,
            &sd,
            &swap_chain,
            &device,
            &featureLevel,
            &device_context,
        ),
        else => |res| res,
    }, "D3D11CreateDeviceAndSwapChain in createDeviceD3D") catch return null;

    return Directx11Options{
        .device = device,
        .device_context = device_context,
        .swap_chain = swap_chain,
    };
}

fn convertVKeyToDvuiKey(vkey: win32.VIRTUAL_KEY) dvui.enums.Key {
    const K = dvui.enums.Key;
    return switch (vkey) {
        .@"0" => .zero,
        .@"1" => .one,
        .@"2" => .two,
        .@"3" => .three,
        .@"4" => .four,
        .@"5" => .five,
        .@"6" => .six,
        .@"7" => .seven,
        .@"8" => .eight,
        .@"9" => .nine,
        .NUMPAD0 => K.kp_0,
        .NUMPAD1 => K.kp_1,
        .NUMPAD2 => K.kp_2,
        .NUMPAD3 => K.kp_3,
        .NUMPAD4 => K.kp_4,
        .NUMPAD5 => K.kp_5,
        .NUMPAD6 => K.kp_6,
        .NUMPAD7 => K.kp_7,
        .NUMPAD8 => K.kp_8,
        .NUMPAD9 => K.kp_9,
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
        .RETURN => K.enter,
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

pub fn main() !void {
    dvui.Backend.Common.windowsAttachConsole() catch {};

    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;

    const window_class = win32.L("DvuiWindow");

    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();
    defer _ = gpa_instance.deinit();

    RegisterClass(window_class, .{}) catch win32.panicWin32(
        "RegisterClass",
        win32.GetLastError(),
    );

    const init_opts = app.config.get();

    var window_state: WindowState = undefined;

    // init dx11 backend (creates and owns OS window)
    const b = try initWindow(&window_state, .{
        .registered_class = window_class,
        .dvui_gpa = gpa,
        .dvui_window_init_options = init_opts.window_init_options,
        .allocator = gpa,
        .size = init_opts.size,
        .min_size = init_opts.min_size,
        .max_size = init_opts.max_size,
        .vsync = init_opts.vsync,
        .title = init_opts.title,
        .icon = init_opts.icon,
    });
    defer b.deinit();

    const win = b.getWindow();

    if (app.initFn) |initFn| {
        try win.begin(win.frame_time_ns);
        try initFn(win);
        _ = try win.end(.{});
    }
    defer if (app.deinitFn) |deinitFn| deinitFn();

    while (true) switch (serviceMessageQueue()) {
        .queue_empty => {
            // beginWait coordinates with waitTime below to run frames only when needed
            const nstime = win.beginWait(b.hasEvent());

            // marks the beginning of a frame for dvui, can call dvui functions after this
            try win.begin(nstime);

            // both dvui and dx11 drawing
            var res = try app.frameFn();

            // check for unhandled quit/close
            for (dvui.events()) |*e| {
                if (e.handled) continue;
                // assuming we only have a single window
                if (e.evt == .window and e.evt.window.action == .close) res = .close;
                if (e.evt == .app and e.evt.app.action == .quit) res = .close;
            }

            // marks end of dvui frame, don't call dvui functions after this
            // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
            _ = try win.end(.{});

            if (res != .ok) break;

            // cursor management
            try b.setCursor(win.cursorRequested());
        },
        .quit => break,
    };
}

test {
    //std.debug.print("dx11 backend test\n", .{});
    std.testing.refAllDecls(@This());
}
