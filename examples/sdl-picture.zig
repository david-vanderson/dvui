const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

const vsync = true;
const show_demo = true;
var scale_val: f32 = 1.0;

var g_backend: ?Backend = null;

/// This example shows how to use the dvui for a normal application:
/// - dvui renders the whole application
/// - render frames only when needed
///
pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        _ = winapi.AttachConsole(0xFFFFFFFF);
    }
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    dvui.Examples.show_demo_window = show_demo;

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Picture Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    g_backend = backend;
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    main_loop: while (true) {
        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(backend.hasEvent());

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        // The demos we pass in here show up under "Platform-specific demos"
        try gui_frame();

        _ = try win.end(.{});

        // cursor management
        backend.setCursor(win.cursorRequested());
        backend.textInputRect(win.textInputRequested());

        backend.renderPresent();

        if (win.extra_frames_needed == 0) {
            const width: usize = @intFromFloat(win.clipRect.w);
            const height: usize = @intFromFloat(win.clipRect.h);
            // For some reason currentWindow().arena() crashes on this allocation
            const pixel_buf = try std.heap.page_allocator.alloc(u8, width * height * 4);

            try readWindowPixels(&backend, width, height, pixel_buf.ptr);

            var len: c_int = undefined;
            const png_bytes = dvui.c.stbi_write_png_to_mem(pixel_buf.ptr, @intCast(width * 4), @intCast(width), @intCast(height), 4, &len);

            try std.fs.cwd().writeFile(.{
                .sub_path = "pic.png",
                .data = png_bytes[0..@intCast(len)],
            });
            return;
        }
    }
}

fn readWindowPixels(self: *Backend, width: usize, height: usize, pixels_out: [*]u8) !void {
    const c = Backend.c;

    if (Backend.sdl3) {
        var surface: *c.SDL_Surface = c.SDL_RenderReadPixels(self.renderer, null) orelse return error.TextureRead;
        defer c.SDL_DestroySurface(surface);
        if (width * height != surface.*.w * surface.*.h) return error.TextureRead;
        // TODO: most common format is RGBA8888, doing conversion during copy to pixels_out should be faster
        if (surface.*.format != c.SDL_PIXELFORMAT_ABGR8888) {
            surface = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_ABGR8888) orelse return error.TextureRead;
        }
        @memcpy(pixels_out[0 .. width * height * 4], @as(?[*]u8, @ptrCast(surface.*.pixels)).?[0 .. width * height * 4]);
        return;
    }

    // If SDL picks directX11 as a rendering backend, it could not support
    // SDL_PIXELFORMAT_ABGR8888 so this works around that.  For some reason sdl
    // crashes if we ask it to do the conversion for us.
    var swap_rb = true;
    var info: c.SDL_RendererInfo = undefined;
    _ = c.SDL_GetRendererInfo(self.renderer, &info);
    //std.debug.print("renderer name {s} formats:\n", .{info.name});
    for (0..info.num_texture_formats) |i| {
        //std.debug.print("  {s}\n", .{c.SDL_GetPixelFormatName(info.texture_formats[i])});
        if (info.texture_formats[i] == c.SDL_PIXELFORMAT_ABGR8888) {
            swap_rb = false;
        }
    }

    _ = c.SDL_RenderReadPixels(self.renderer, null, if (swap_rb) c.SDL_PIXELFORMAT_ARGB8888 else c.SDL_PIXELFORMAT_ABGR8888, pixels_out, @intCast(width * 4));

    if (swap_rb) {
        for (0..width * height) |i| {
            const r = pixels_out[i * 4 + 0];
            const b = pixels_out[i * 4 + 2];
            pixels_out[i * 4 + 0] = b;
            pixels_out[i * 4 + 2] = r;
        }
    }
}

// both dvui and SDL drawing
fn gui_frame() !void {
    const backend = g_backend orelse return;

    {
        var m = try dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                m.close();
            }
        }

        if (try dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            _ = try dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }

    var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .name = .fill_window } });
    defer scroll.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This example shows how to use dvui in a normal application.";
    try tl.addText(lorem, .{});
    tl.deinit();

    var tl2 = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    try tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- example menu at the top of the window
        \\- rest of the window is a scroll area
    , .{});
    try tl2.addText("\n\n", .{});
    try tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    try tl2.addText("\n\n", .{});
    if (vsync) {
        try tl2.addText("Framerate is capped by vsync.", .{});
    } else {
        try tl2.addText("Framerate is uncapped.", .{});
    }
    try tl2.addText("\n\n", .{});
    try tl2.addText("Cursor is always being set by dvui.", .{});
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

    {
        var scaler = try dvui.scale(@src(), scale_val, .{ .expand = .horizontal });
        defer scaler.deinit();

        {
            var hbox = try dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            if (try dvui.button(@src(), "Zoom In", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val + 1.0) / dvui.themeGet().font_body.size;
            }

            if (try dvui.button(@src(), "Zoom Out", .{}, .{})) {
                scale_val = @round(dvui.themeGet().font_body.size * scale_val - 1.0) / dvui.themeGet().font_body.size;
            }
        }

        try dvui.labelNoFmt(@src(), "Below is drawn directly by the backend, not going through DVUI.", .{ .margin = .{ .x = 4 } });

        var box = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .min_size_content = .{ .h = 40 }, .background = true, .margin = .{ .x = 8, .w = 8 } });
        defer box.deinit();

        // Here is some arbitrary drawing that doesn't have to go through DVUI.
        // It can be interleaved with DVUI drawing.
        // NOTE: This only works in the main window (not floating subwindows
        // like dialogs).

        // get the screen rectangle for the box
        const rs = box.data().contentRectScale();

        // rs.r is the pixel rectangle, rs.s is the scale factor (like for
        // hidpi screens or display scaling)
        var rect: if (Backend.sdl3) Backend.c.SDL_FRect else Backend.c.SDL_Rect = undefined;
        if (Backend.sdl3) rect = .{
            .x = (rs.r.x + 4 * rs.s),
            .y = (rs.r.y + 4 * rs.s),
            .w = (20 * rs.s),
            .h = (20 * rs.s),
        } else rect = .{
            .x = @intFromFloat(rs.r.x + 4 * rs.s),
            .y = @intFromFloat(rs.r.y + 4 * rs.s),
            .w = @intFromFloat(20 * rs.s),
            .h = @intFromFloat(20 * rs.s),
        };
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 255, 0, 0, 255);
        _ = Backend.c.SDL_RenderFillRect(backend.renderer, &rect);

        rect.x += if (Backend.sdl3) 24 * rs.s else @intFromFloat(24 * rs.s);
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 255, 0, 255);
        _ = Backend.c.SDL_RenderFillRect(backend.renderer, &rect);

        rect.x += if (Backend.sdl3) 24 * rs.s else @intFromFloat(24 * rs.s);
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 255, 255);
        _ = Backend.c.SDL_RenderFillRect(backend.renderer, &rect);

        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 255, 0, 255, 255);

        if (Backend.sdl3)
            _ = Backend.c.SDL_RenderLine(backend.renderer, (rs.r.x + 4 * rs.s), (rs.r.y + 30 * rs.s), (rs.r.x + rs.r.w - 8 * rs.s), (rs.r.y + 30 * rs.s))
        else
            _ = Backend.c.SDL_RenderDrawLine(backend.renderer, @intFromFloat(rs.r.x + 4 * rs.s), @intFromFloat(rs.r.y + 30 * rs.s), @intFromFloat(rs.r.x + rs.r.w - 8 * rs.s), @intFromFloat(rs.r.y + 30 * rs.s));
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
