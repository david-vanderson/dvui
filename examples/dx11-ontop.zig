const std = @import("std");
const dvui = @import("dvui");
const Backend = @import("dx11-backend");

const win32 = @import("win32").everything;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const log = std.log.scoped(.Dx11Ontop);

// pub const panic = win32.messageBoxThenPanic(.{ .title = "Dx11 Ontop Panic!" });

var backend_attached = false;

pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    defer _ = gpa_instance.deinit();
    const wnd = createWindow();

    const options = createDeviceD3D(wnd) orelse return error.CreateDeviceFailed;

    log.info("Successfully created device.", .{});
    var window_state: Backend.WindowState = undefined;
    const backend = Backend.attach(wnd, &window_state, gpa, options, .{ .vsync = false }) catch |e| @panic(@errorName(e));
    defer backend.deinit();
    backend_attached = true;

    _ = win32.ShowWindow(wnd, .{ .SHOWNORMAL = 1 });
    _ = win32.UpdateWindow(wnd);

    const win: *dvui.Window = backend.getWindow();
    log.info("dvui window also init.", .{});

    main_loop: while (true) switch (Backend.serviceMessageQueue()) {
        .queue_empty => {
            // beginWait coordinates with waitTime below to run frames only when needed
            const nstime = win.beginWait(backend.hasEvent());

            // marks the beginning of a frame for dvui, can call dvui functions after this
            try win.begin(nstime);

            // draw some fancy dvui stuff
            dvui_floating_stuff();

            // check for quitting
            for (dvui.events()) |*e| {
                // assume we only have a single window
                if (e.evt == .window and e.evt.window.action == .close) break :main_loop;
                if (e.evt == .app and e.evt.app.action == .quit) break :main_loop;
            }

            // marks end of dvui frame, don't call dvui functions after this
            // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
            _ = try win.end(.{});
        },
        .quit => break :main_loop,
    };
}

fn windowProc(
    hwnd: win32.HWND,
    umsg: u32,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    switch (umsg) {
        win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN => {
            switch (wparam) {
                @intFromEnum(win32.VK_ESCAPE) => { //SHIFT+ESC = EXIT
                    if (win32.GetAsyncKeyState(@intFromEnum(win32.VK_LSHIFT)) & 0x01 == 1) {
                        win32.PostQuitMessage(0);
                        return 0;
                    }
                },
                else => {},
            }
        },
        else => {},
    }

    if (backend_attached)
        // Call the wndProc from the Dx11 Backend directly, it handles all sorts of mouse events!
        return Backend.wndProc(hwnd, umsg, wparam, lparam);
    return win32.DefWindowProcW(hwnd, umsg, wparam, lparam);
}

// boilerplate, no need to look at this ugly mess...
fn createWindow() win32.HWND {
    const class_name = win32.L("Dx11OntopMain");

    {
        const opt: win32.WNDCLASSEXW = .{
            .cbSize = @sizeOf(win32.WNDCLASSEXW),
            .style = .{ .DBLCLKS = 1, .OWNDC = 1 },
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = @sizeOf(usize),
            .hInstance = win32.GetModuleHandleW(null),
            .hIcon = null,
            .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = class_name,
            .hIconSm = null,
        };
        if (0 == win32.RegisterClassExW(&opt)) win32.panicWin32("RegisterClass", win32.GetLastError());
    }
    const style = win32.WS_OVERLAPPEDWINDOW;
    const style_ex: win32.WINDOW_EX_STYLE = .{ .APPWINDOW = 1, .WINDOWEDGE = 1 };
    const wnd = win32.CreateWindowExW(
        style_ex,
        class_name,
        win32.L("DVUI Dx11 Test"),
        style,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        0,
        0,
        null,
        null,
        win32.GetModuleHandleW(null),
        null,
    ) orelse win32.panicWin32("CreateWindow", win32.GetLastError());

    const dpi = win32.dpiFromHwnd(wnd);

    const screen_width = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CXSCREEN), dpi);
    const screen_height = win32.GetSystemMetricsForDpi(@intFromEnum(win32.SM_CYSCREEN), dpi);
    var wnd_size: win32.RECT = .{
        .left = 0,
        .top = 0,
        .right = @min(screen_width, win32.scaleDpi(i32, 1280, dpi)),
        .bottom = @min(screen_height, win32.scaleDpi(i32, 720, dpi)),
    };
    _ = win32.AdjustWindowRectEx(&wnd_size, style, 0, style_ex);

    const wnd_width = wnd_size.right - wnd_size.left;
    const wnd_height = wnd_size.bottom - wnd_size.top;
    _ = win32.SetWindowPos(
        wnd,
        null,
        @divFloor(screen_width - wnd_width, 2),
        @divFloor(screen_height - wnd_height, 2),
        wnd_width,
        wnd_height,
        win32.SWP_NOCOPYBITS,
    );
    return wnd;
}

fn createDeviceD3D(hwnd: win32.HWND) ?Backend.Directx11Options {
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

    var res: win32.HRESULT = win32.D3D11CreateDeviceAndSwapChain(
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
    );

    if (res == win32.DXGI_ERROR_UNSUPPORTED) {
        res = win32.D3D11CreateDeviceAndSwapChain(
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
        );
    }
    if (res != win32.S_OK)
        return null;

    return Backend.Directx11Options{
        .device = device,
        .device_context = device_context,
        .swap_chain = swap_chain,
    };
}

fn dvui_floating_stuff() void {
    var float = dvui.floatingWindow(@src(), .{}, .{ .min_size_content = .{ .w = 400, .h = 400 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("Floating Window", "", null));

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui for floating windows on top of an existing application.";
    tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText("The dvui is painting only floating windows and dialogs.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is managed by the application (in this demo capped at vsync).", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is only being set by dvui for floating windows.", .{});
    tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{})) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    dvui.Examples.demo();
}
