const std = @import("std");
const dvui = @import("dvui");
comptime {
    std.debug.assert(dvui.backend_kind == .dx11);
}
const Dx11Backend = dvui.backend;

const zwin = @import("zigwin32");
const ui = zwin.ui.windows_and_messaging;

const dxgi = zwin.graphics.dxgi;
const dx = zwin.graphics.direct3d11;
const d3d = zwin.graphics.direct3d;

const L = zwin.zig.L;

const w = std.os.windows;
const HINSTANCE = w.HINSTANCE;
const LPWSTR = w.LPWSTR;
const INT = w.INT;
const UINT = w.UINT;
const WNDCLASSEX = ui.WNDCLASSEXW;
const RECT = w.RECT;
const BOOL = w.BOOL;
const HDC = w.HDC;
const HWND = zwin.foundation.HWND;

const dxgic = dxgi.common;

const WINAPI = w.WINAPI;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const log = std.log.scoped(.Dx11Ontop);

var wnd: HWND = undefined;
const wnd_title = L("DVUI Dx11 Test");
var width: INT = 1280;
var height: INT = 720;
var resize_width: UINT = 0;
var resize_height: UINT = 0;
var wnd_size: RECT = .{ .left = 0, .top = 0, .right = 1280, .bottom = 720 };
var wnd_dc: HDC = undefined;
var wnd_dpi: w.UINT = 0;
var wnd_hRC: w.HGLRC = undefined;

pub export fn main(
    instance: HINSTANCE,
    _: ?HINSTANCE,
    _: ?LPWSTR,
    cmd_show: INT,
) callconv(WINAPI) INT {
    defer _ = gpa_instance.deinit();
    createWindow(instance);
    defer _ = ReleaseDC(wnd, wnd_dc);
    defer _ = UnregisterClassW(wnd_title, instance);
    defer _ = DestroyWindow(wnd);

    const init_options = Dx11Backend.InitOptions{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = false,
        .title = "DX11 Test",
        .icon = null,
    };

    if (createDeviceD3D(wnd)) |options| {
        log.info("Successfully created device.", .{});
        var backend = Dx11Backend.init(init_options, options) catch return 1;
        defer backend.deinit();
        log.info("Dx11 backend also init.", .{});

        _ = ShowWindow(wnd, cmd_show);
        _ = UpdateWindow(wnd);

        var rect = std.mem.zeroes(zwin.foundation.RECT);
        _ = ui.GetWindowRect(wnd, &rect);

        backend.setDimensions(rect);
        backend.setViewport(); // for now: fixed values :)

        var win = dvui.Window.init(@src(), gpa, backend.backend(), .{}) catch return 1;
        log.info("dvui window also init.", .{});
        defer win.deinit();

        var msg: ui.MSG = std.mem.zeroes(ui.MSG);
        const PM_REMOVE = 0x0001;
        main_loop: while (true) {
            while (PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0) {
                _ = TranslateMessage(&msg);
                _ = DispatchMessageW(&msg);
                if (msg.message == ui.WM_QUIT) {
                    break :main_loop;
                }
            }

            if (resize_width != 0 and resize_height != 0) {
                backend.handleSwapChainResizing(&resize_width, &resize_height) catch {
                    log.err("Failed to handle swap chain resizing...", .{});
                    continue;
                };
            }

            rect = std.mem.zeroes(zwin.foundation.RECT);
            _ = ui.GetWindowRect(wnd, &rect);

            backend.setDimensions(rect);

            win.begin(std.time.nanoTimestamp()) catch {
                log.err("win.begin() failed.", .{});
                return 1;
            };

            // log.info("post begin", .{});

            // dvui_floating_stuff() catch {
            //     log.err("Oh no something went horribly wrong!", .{});
            // };
            var pixel_data = [_]u8{ 0xff, 0xff, 0x00, 0xff, 0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0xff, 0xff, 0x00, 0xff, 0xff };
            const tex = dvui.textureCreate((&pixel_data).ptr, 2, 2, .nearest);
            dvui.textureDestroyLater(tex);

            var frame_box = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 50, .h = 50 } }) catch continue;
            dvui.renderTexture(tex, frame_box.data().contentRectScale(), 0, .{}) catch {
                continue;
            };
            frame_box.deinit();

            // _ = dvui.button(@src(), "button", .{}, .{}) catch {};

            //  {
            // const vtx = [_]dvui.Vertex{
            //     .{ .pos = .{ .x = 100, .y = 100 }, .col = dvui.Color.white, .uv = .{ 0, 0 } },
            //     .{ .pos = .{ .x = 200, .y = 100 }, .col = dvui.Color.white, .uv = .{ 0, 0 } },
            //     .{ .pos = .{ .x = 200, .y = 200 }, .col = dvui.Color.white, .uv = .{ 0, 0 } },
            // };
            // const idx = [_]u16{ 0, 2, 1 };
            // backend.drawClippedTriangles(null, &vtx, &idx, .{ .x = 0, .y = 0, .w = 400, .h = 400 });
            //  }

            //  {
            // const vtx = [_]dvui.Vertex{
            //     .{ .pos = .{ .x = 300, .y = 300 }, .col = dvui.Color.white, .uv = .{ 0, 0 } },
            //     .{ .pos = .{ .x = 400, .y = 300 }, .col = dvui.Color.white, .uv = .{ 0, 0 } },
            //     .{ .pos = .{ .x = 400, .y = 400 }, .col = dvui.Color.white, .uv = .{ 0, 0 } },
            // };
            // const idx = [_]u16{ 0, 1, 2 };
            // backend.drawClippedTriangles(null, &vtx, &idx, .{ .x = 0, .y = 0, .w = 400, .h = 400 });
            //  }

            // log.info("post dvui_floating_stuff", .{});

            _ = win.end(.{}) catch {
                log.err("win.end() failed.", .{});
                return 1;
            };
        }
    } else {
        log.err("createDevice rip", .{});
        return 1;
    }

    return 0;
}

fn createWindow(hInstance: HINSTANCE) void {
    const wnd_class: WNDCLASSEX = .{
        .cbSize = @sizeOf(WNDCLASSEX),
        .style = .{ .DBLCLKS = 1, .OWNDC = 1 },
        .lpfnWndProc = windowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null,
        .hCursor = ui.LoadCursorW(null, ui.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = @ptrCast(wnd_title),
        .hIconSm = null,
    };
    std.debug.print("register class: {x}\n", .{ui.RegisterClassExW(&wnd_class)});
    var overlap = ui.WS_OVERLAPPEDWINDOW;
    std.debug.print("adjust window rect: {x}\n", .{ui.AdjustWindowRectEx(@ptrCast(&wnd_size), overlap, w.FALSE, .{ .APPWINDOW = 1, .WINDOWEDGE = 1 })});
    overlap.VISIBLE = 1;
    wnd = ui.CreateWindowExW(.{ .APPWINDOW = 1, .WINDOWEDGE = 1 }, wnd_title, wnd_title, overlap, ui.CW_USEDEFAULT, ui.CW_USEDEFAULT, 0, 0, null, null, hInstance, null) orelse {
        std.debug.print("This didn't do anything\n", .{});
        std.process.exit(1);
    };

    wnd_dc = GetDC(wnd).?;
    const dpi = GetDpiForWindow(wnd);
    const xcenter = @divFloor(GetSystemMetricsForDpi(@intFromEnum(ui.SM_CXSCREEN), dpi), 2);
    const ycenter = @divFloor(GetSystemMetricsForDpi(@intFromEnum(ui.SM_CYSCREEN), dpi), 2);
    wnd_size.left = xcenter - @divFloor(width, 2);
    wnd_size.top = ycenter - @divFloor(height, 2);
    wnd_size.right = wnd_size.left + @divFloor(width, 2);
    wnd_size.bottom = wnd_size.top + @divFloor(height, 2);
    _ = ui.SetWindowPos(wnd, null, wnd_size.left, wnd_size.top, wnd_size.right, wnd_size.bottom, ui.SWP_NOCOPYBITS);
}

fn createDeviceD3D(hWnd: HWND) ?Dx11Backend.Directx11Options {
    var rc: RECT = undefined;
    _ = GetClientRect(hWnd, &rc);

    var sd = std.mem.zeroes(dxgi.DXGI_SWAP_CHAIN_DESC);
    sd.BufferCount = 6;
    sd.BufferDesc.Width = @intCast(width);
    sd.BufferDesc.Height = @intCast(height);
    sd.BufferDesc.Format = dxgic.DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = @intFromEnum(dxgi.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH);
    sd.BufferUsage = dxgi.DXGI_USAGE_RENDER_TARGET_OUTPUT;
    @setRuntimeSafety(false);
    sd.OutputWindow = @as(HWND, @alignCast(@ptrCast(hWnd)));
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

    var res: zwin.foundation.HRESULT = dx.D3D11CreateDeviceAndSwapChain(
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
    if (res != zwin.foundation.S_OK)
        return null;

    return Dx11Backend.Directx11Options{
        .device = device.?,
        .device_context = device_context.?,
        .swap_chain = swap_chain.?,
    };
}

fn windowProc(hwnd: HWND, umsg: UINT, wparam: w.WPARAM, lparam: w.LPARAM) callconv(WINAPI) w.LRESULT {
    switch (umsg) {
        ui.WM_DESTROY => {
            ui.PostQuitMessage(0);
            return 0;
        },
        ui.WM_PAINT => {
            var ps: zwin.graphics.gdi.PAINTSTRUCT = undefined;
            const hdc: HDC = BeginPaint(hwnd, &ps) orelse undefined;
            _ = FillRect(hdc, @ptrCast(&ps.rcPaint), @ptrFromInt(@intFromEnum(ui.COLOR_WINDOW) + 1));
            _ = EndPaint(hwnd, &ps);
        },
        ui.WM_SIZE => {
            resize_width = loword(lparam);
            resize_height = hiword(lparam);
        },
        ui.WM_KEYDOWN, ui.WM_SYSKEYDOWN => {
            switch (wparam) {
                @intFromEnum(zwin.ui.input.keyboard_and_mouse.VK_ESCAPE) => { //SHIFT+ESC = EXIT
                    if (GetAsyncKeyState(@intFromEnum(zwin.ui.input.keyboard_and_mouse.VK_LSHIFT)) & 0x01 == 1) {
                        ui.PostQuitMessage(0);
                        return 0;
                    }
                },
                else => {},
            }
        },
        else => _ = .{},
    }

    return ui.DefWindowProcW(hwnd, umsg, wparam, lparam);
}

fn dvui_floating_stuff() !void {
    var float = try dvui.floatingWindow(@src(), .{}, .{ .min_size_content = .{ .w = 400, .h = 400 } });
    defer float.deinit();

    try dvui.windowHeader("Floating Window", "", null);

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    defer scroll.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui for floating windows on top of an existing application.";
    try tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    try tl2.addText("The dvui is painting only floating windows and dialogs.", .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Framerate is managed by the application (in this demo capped at vsync).", .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Cursor is only being set by dvui for floating windows.", .{});
    try tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        try tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        try tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (try dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}

fn loword(l: w.LONG_PTR) UINT {
    return @as(u32, @intCast(l)) & 0xFFFF;
}
fn hiword(l: w.LONG_PTR) UINT {
    return (@as(u32, @intCast(l)) >> 16) & 0xFFFF;
}

// externs
pub extern "user32" fn BeginPaint(hWnd: ?HWND, lpPaint: ?*zwin.graphics.gdi.PAINTSTRUCT) callconv(WINAPI) ?HDC;
pub extern "user32" fn FillRect(hDC: ?HDC, lprc: ?*const RECT, hbr: ?zwin.graphics.gdi.HBRUSH) callconv(WINAPI) INT;
pub extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const zwin.graphics.gdi.PAINTSTRUCT) callconv(WINAPI) BOOL;
pub extern "user32" fn GetDC(hWnd: ?HWND) callconv(WINAPI) ?w.HDC;
pub extern "user32" fn GetAsyncKeyState(nKey: c_int) callconv(WINAPI) w.INT;
pub extern "user32" fn GetDpiForWindow(hWnd: HWND) callconv(WINAPI) w.UINT;
pub extern "user32" fn GetSystemMetricsForDpi(nIndex: w.INT, dpi: w.UINT) callconv(WINAPI) w.INT;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(WINAPI) BOOL;
pub extern "user32" fn UnregisterClassW(lpClassName: [*:0]const u16, hInstance: w.HINSTANCE) callconv(WINAPI) BOOL;
pub extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: w.HDC) callconv(WINAPI) i32;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(WINAPI) w.UINT;
pub extern "user32" fn PeekMessageA(lpMsg: *ui.MSG, hWnd: ?HWND, wMsgFilterMin: w.UINT, wMsgFilterMax: w.UINT, wRemoveMsg: w.UINT) callconv(WINAPI) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const ui.MSG) callconv(WINAPI) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const ui.MSG) callconv(WINAPI) w.LRESULT;
pub extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: i32) callconv(WINAPI) BOOL;
pub extern "user32" fn UpdateWindow(hWnd: HWND) callconv(WINAPI) BOOL;
