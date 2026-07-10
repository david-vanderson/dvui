const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const sdl_options = @import("sdl_options");
pub const sdl3 = sdl_options.version.major == 3;

pub const c = if (sdl3) @import("sdl3-c") else @import("sdl2-c");

/// Only available in sdl2
extern "SDL_config" fn MACOS_enable_scroll_momentum() callconv(.c) void;

pub const kind: dvui.enums.Backend = if (sdl3) .sdl3 else .sdl2;

pub const SDLBackend = @This();
pub const Context = *SDLBackend;

const log = std.log.scoped(.SDLBackend);

var sdl2_scale: f32 = 1.0;

// Global io instance assigned to `dvui.io`
io: std.Io,
// allocator that is reset each frame. Passed in via `SDL_Backend.begin`
arena: std.mem.Allocator = undefined,

window: *c.SDL_Window,
renderer: *c.SDL_Renderer,

/// Optional hook invoked during `Window.begin` just before pixel/window sizes are queried.
/// Useful to sync AppKit window state into SDL (e.g. during Space / zoom animations).
begin_hook: ?*const fn (*SDLBackend) void = null,

touch_mouse_events: bool = false,
log_events: bool = false,
last_pixel_size: dvui.Size.Physical = .{ .w = 800, .h = 600 },
last_window_size: dvui.Size.Natural = .{ .w = 800, .h = 600 },
cursor_last: dvui.enums.Cursor = .arrow,
cursor_backing: [cursor_enum_count]?*c.SDL_Cursor = @splat(null),
cursor_backing_tried: [cursor_enum_count]bool = @splat(false),

manage_backend_tracking: dvui.Backend.Common.TrackManageBackend = .{},

ak_should_initialized: bool = dvui.accesskit_enabled,
/// If set to true, the backend owns the window and should free ressources on deinit
we_own_window: bool = false,
/// For multi os windows, allow to destroy window/renderer without quitting SDL
/// Has no effect if `we_own_window == false`
sdl_quit: bool = true,
/// If set to true, the window will be cleared when begin() is called
clear_window_on_begin: bool = false,
/// Last known window rect while not maximized/fullscreen/minimized, tracked
/// from move/resize events
window_geometry: WindowGeometry = .{},
// Set by `initWindow` and `initWindowSecondary` for use by eventual child window.
init_opts_save: ?InitOptions = null,

const cursor_enum_count = @typeInfo(dvui.enums.Cursor).@"enum".fields.len;

pub const InitOptions = struct {
    /// Io backend and dvui should use, will be assigned to dvui.io.
    io: std.Io,
    /// SDL2 uses this to query for environment variables for scale:
    /// - QT_AUTO_SCREEN_SCALE_FACTOR
    /// - QT_SCALE_FACTOR
    /// - GDK_SCALE
    environ_map: ?*std.process.Environ.Map = null,
    /// The initial size of the application window
    size: dvui.Size,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    vsync: bool,
    /// The application title to display
    title: [:0]const u8,
    /// Organization name for SDL preference paths when `pref_path` is null
    /// (`SDL_GetPrefPath(org, title)`). Defaults to `"dvui"`.
    org: [:0]const u8 = "dvui",
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
    /// use when running tests
    hidden: bool = false,
    fullscreen: bool = false,
    transparent: bool = false,
    /// Whether SDL should be initialized. Set this to false for secondary os windows
    sdl_init: bool = true,
    /// Automatically restore the window position and size from the previous
    /// run, and save them when the backend deinits (SDL3 only, ignored when
    /// `hidden` is set).  Writes `window_geometry.zon` into `pref_path` when
    /// set, otherwise under `SDL_GetPrefPath(org, title)`.
    persist_window_geometry: bool = true,
    /// Optional folder for app preferences, including `window_geometry.zon`
    /// when `persist_window_geometry` is true.  When null, uses
    /// `SDL_GetPrefPath(org, title)`.
    pref_path: ?[:0]const u8 = null,
};

/// SDL initialization for the all SDL app, i.e. common for all OS Windows
/// This is expected to be called only once.
pub fn initSDL() !void {
    if (!sdl3) _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear");
    // needed according to https://discourse.libsdl.org/t/possible-to-run-sdl2-headless/25665/2
    // but getting error "offscreen not available"
    // if (options.hidden) _ = c.SDL_SetHint(c.SDL_HINT_VIDEODRIVER, "offscreen");

    // use the string version instead of the #define so we compile with SDL < 2.24
    _ = c.SDL_SetHint("SDL_HINT_WINDOWS_DPI_SCALING", "1");

    // makes mac scrolling better
    if (sdl3) _ = c.SDL_SetHint(c.SDL_HINT_MAC_SCROLL_MOMENTUM, "1");

    // prevents some bad performance in certain wayland compositors (sway) under some conditions
    if (sdl3) {
        if (c.SDL_SetHint(c.SDL_HINT_VIDEO_WAYLAND_PREFER_LIBDECOR, "1") != SDL_SUCCESS) {
            log.err("failed to set libdecor hint", .{});
        }
    }

    try toErr(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS), "SDL_Init in initWindow");

    if (!sdl3 and builtin.os.tag == .macos) {
        MACOS_enable_scroll_momentum();
    }

    // FIXME : as per SDL docs :
    // Consider reporting some basic metadata about your application before calling SDL_Init, using either SDL_SetAppMetadata() or SDL_SetAppMetadataProperty().
    // This would be nice here probably ...
}

pub fn initWindow(init_options: InitOptions) !SDLBackend {
    try initSDL();
    const new = try createWindowRenderer(init_options);

    var back = init(init_options.io, new.win, new.renderer);
    back.init_opts_save = init_options;
    back.window_geometry = new.saved_geometry orelse .{};

    try configureBackend(&back, init_options);

    return back;
}

pub fn initWindowSecondary(parent: *SDLBackend, child_win_opts: dvui.OsWindowWidget.InitOptions) !SDLBackend {
    const parent_opts = parent.init_opts_save orelse {
        log.err("initWindowSecondary expects parent instance with `init_opts_save` field set (typically by `initWindow`)", .{});
        return dvui.Backend.GenericError.BackendError;
    };
    const new_init_opts: SDLBackend.InitOptions = .{
        .io = parent.io,
        .environ_map = parent_opts.environ_map,

        .size = child_win_opts.size orelse parent_opts.size,
        .min_size = child_win_opts.min_size orelse parent_opts.min_size,
        .max_size = child_win_opts.max_size orelse parent_opts.max_size,
        .vsync = parent_opts.vsync,
        .title = child_win_opts.title orelse parent_opts.title,
        .org = parent_opts.org,
        .icon = child_win_opts.icon orelse parent_opts.icon,
        .hidden = child_win_opts.hidden,
        .fullscreen = child_win_opts.fullscreen,
        .transparent = parent_opts.transparent,
        .sdl_init = false,
        // only the primary window persists its geometry
        .persist_window_geometry = false,
    };
    const new = try createWindowRenderer(new_init_opts);
    preventWindowForkBomb();

    var back = init(dvui.io, new.win, new.renderer);
    back.init_opts_save = new_init_opts;
    back.window_geometry = new.saved_geometry orelse .{};
    back.sdl_quit = false;
    back.log_events = parent.log_events;

    try configureBackend(&back, new_init_opts);

    return back;
}

fn createWindowRenderer(options: InitOptions) !struct {
    win: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    saved_geometry: ?WindowGeometry,
} {
    var hidden = options.hidden;
    var show_window_in_begin = false;
    if (dvui.accesskit_enabled and !hidden) {
        // hide the window until we can initialize accesskit in Window.begin
        hidden = true;
        show_window_in_begin = true;
    }

    const saved_geometry: ?WindowGeometry = if (sdl3) WindowGeometry.load(options) else null;

    const hidden_flag = if (hidden) c.SDL_WINDOW_HIDDEN else 0;
    const fullscreen_flag = if (options.fullscreen) c.SDL_WINDOW_FULLSCREEN else 0;
    const transparent_flag = if (options.transparent and sdl3) c.SDL_WINDOW_TRANSPARENT else 0;
    const window: *c.SDL_Window = if (sdl3) blk: {
        // Window properties let us apply restored geometry at creation time,
        // so the window appears directly at its previous position/size.
        const props = c.SDL_CreateProperties();
        defer c.SDL_DestroyProperties(props);

        const flags: c.SDL_WindowFlags = @intCast(c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE | transparent_flag | hidden_flag | fullscreen_flag);
        var w: c_int = @as(c_int, @trunc(options.size.w));
        var h: c_int = @as(c_int, @trunc(options.size.h));

        if (saved_geometry) |g| {
            w = g.w;
            h = g.h;
            if (g.posOnADisplay()) {
                try toErr(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_X_NUMBER, g.x), "SDL_SetNumberProperty in initWindow");
                try toErr(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_Y_NUMBER, g.y), "SDL_SetNumberProperty in initWindow");
            }
        }

        try toErr(c.SDL_SetStringProperty(props, c.SDL_PROP_WINDOW_CREATE_TITLE_STRING, options.title), "SDL_SetStringProperty in initWindow");
        try toErr(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, w), "SDL_SetNumberProperty in initWindow");
        try toErr(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, h), "SDL_SetNumberProperty in initWindow");
        try toErr(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, @intCast(flags)), "SDL_SetNumberProperty in initWindow");

        break :blk c.SDL_CreateWindowWithProperties(props) orelse return logErr("SDL_CreateWindowWithProperties in initWindow");
    } else c.SDL_CreateWindow(
        options.title,
        c.SDL_WINDOWPOS_UNDEFINED,
        c.SDL_WINDOWPOS_UNDEFINED,
        @as(c_int, @trunc(options.size.w)),
        @as(c_int, @trunc(options.size.h)),
        @intCast(c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE | hidden_flag),
    ) orelse return logErr("SDL_CreateWindow in initWindow");

    errdefer c.SDL_DestroyWindow(window);

    // get initial content scale
    var scale: f32 = 1.0;
    if (sdl3) {
        scale = c.SDL_GetDisplayContentScale(c.SDL_GetDisplayForWindow(window));
        if (scale == 0) {
            log.err("SDL_GetDisplayContentScale returned 0", .{});
            scale = 1.0;
        }
        log.info("SDL3 backend scale {d}", .{scale});
    } else {
        scale = SDL2GuessScale(options.environ_map, options.io, window);
        sdl2_scale = scale;
    }

    // adjust window size for content scale
    if (scale != 1.0 and saved_geometry == null) {
        if (builtin.abi.isAndroid()) {
            // log.error fails on Android but SDL_Log will show up in LogCat
            c.SDL_Log("[ERROR] Android doesn't support SDL_SetWindowSize");
        } else {
            _ = c.SDL_SetWindowSize(
                window,
                @as(c_int, @trunc(scale * options.size.w)),
                @as(c_int, @trunc(scale * options.size.h)),
            );
        }
    }

    if (options.min_size) |size| {
        if (builtin.abi.isAndroid()) {
            // log.error fails on Android but SDL_Log will show up in LogCat
            c.SDL_Log("[ERROR] Android doesn't support SDL_SetWindowMinimumSize");
        } else {
            const ret = c.SDL_SetWindowMinimumSize(
                window,
                @as(c_int, @trunc(scale * size.w)),
                @as(c_int, @trunc(scale * size.h)),
            );
            if (sdl3) try toErr(ret, "SDL_SetWindowMinimumSize in initWindow");
        }
    }

    if (options.max_size) |size| {
        if (builtin.abi.isAndroid()) {
            // log.error fails on Android but SDL_Log will show up in LogCat
            c.SDL_Log("[ERROR] Android doesn't support SDL_SetWindowMaximumSize");
        } else {
            const ret = c.SDL_SetWindowMaximumSize(
                window,
                @as(c_int, @trunc(scale * size.w)),
                @as(c_int, @trunc(scale * size.h)),
            );
            if (sdl3) try toErr(ret, "SDL_SetWindowMaximumSize in initWindow");
        }
    }

    const renderer: *c.SDL_Renderer = if (!sdl3)
        c.SDL_CreateRenderer(window, -1, @intCast(
            c.SDL_RENDERER_TARGETTEXTURE | (if (options.vsync) c.SDL_RENDERER_PRESENTVSYNC else 0),
        )) orelse return logErr("SDL_CreateRenderer in initWindow")
    else blk: {
        const props = c.SDL_CreateProperties();
        defer c.SDL_DestroyProperties(props);

        try toErr(
            c.SDL_SetPointerProperty(props, c.SDL_PROP_RENDERER_CREATE_WINDOW_POINTER, window),
            "SDL_SetPointerProperty in initWindow",
        );

        if (options.vsync) {
            try toErr(
                c.SDL_SetNumberProperty(props, c.SDL_PROP_RENDERER_CREATE_PRESENT_VSYNC_NUMBER, 1),
                "SDL_SetNumberProperty in initWindow",
            );
        }

        break :blk c.SDL_CreateRendererWithProperties(props) orelse return logErr("SDL_CreateRendererWithProperties in initWindow");
    };
    errdefer c.SDL_DestroyRenderer(renderer);

    // do premultiplied alpha blending:
    // * rendering to a texture and then rendering the texture works the same
    // * any filtering happening across pixels won't bleed in transparent rgb values
    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    try toErr(c.SDL_SetRenderDrawBlendMode(renderer, pma_blend), "SDL_SetRenderDrawBlendMode in initWindow");

    // do fullscreen/maximize after window creation so the original geometry is saved:
    // position window -> fullscreen -> quit -> restart -> unfullscreen should restore original position
    if (!options.hidden) {
        if (saved_geometry) |g| {
            switch (g.state) {
                .normal => {},
                .maximized => {
                    _ = c.SDL_MaximizeWindow(window);
                },
                .fullscreen => {
                    if (sdl3) _ = c.SDL_SetHint(c.SDL_HINT_VIDEO_MAC_FULLSCREEN_MENU_VISIBILITY, "1");
                    _ = c.SDL_SetWindowFullscreen(window, true);
                },
            }
        }
    }

    return .{
        .win = window,
        .renderer = renderer,
        .saved_geometry = saved_geometry,
    };
}

/// Window position/size persisted across runs (see `InitOptions.persist_window_geometry`).
/// Stored as `window_geometry.zon` in `InitOptions.pref_path` or, when that is
/// null, under `SDL_GetPrefPath(org, title)`.
/// x/y/w/h are always the normal (windowed) rect — a window that quit while
/// maximized or fullscreen is restored at its last windowed size/position.
/// SDL3 only.
pub const WindowGeometry = struct {
    x: c_int = 0,
    y: c_int = 0,
    w: c_int = 100,
    h: c_int = 100,
    state: State = .normal,

    const State = enum { normal, maximized, fullscreen };

    const Saved = struct {
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        state: State = .normal,
    };

    const zon_file_name = "window_geometry.zon";

    fn filePath(buf: []u8, options: InitOptions) ?[:0]const u8 {
        if (options.pref_path) |dir| {
            if (std.mem.endsWith(u8, dir, std.fs.path.sep_str)) {
                return std.fmt.bufPrintZ(buf, "{s}{s}", .{ dir, zon_file_name }) catch null;
            }
            return std.fmt.bufPrintZ(buf, "{s}{c}{s}", .{ dir, std.fs.path.sep, zon_file_name }) catch null;
        }
        const pref = c.SDL_GetPrefPath(options.org.ptr, options.title.ptr) orelse {
            logErr("SDL_GetPrefPath in WindowGeometry") catch {};
            return null;
        };
        defer c.SDL_free(pref);
        return std.fmt.bufPrintZ(buf, "{s}" ++ zon_file_name, .{std.mem.span(@as([*:0]const u8, @ptrCast(pref)))}) catch null;
    }

    fn fromSaved(saved: Saved) ?WindowGeometry {
        if (saved.w < 1 or saved.h < 1) return null;
        return .{
            .x = std.math.cast(c_int, saved.x) orelse return null,
            .y = std.math.cast(c_int, saved.y) orelse return null,
            .w = std.math.cast(c_int, saved.w) orelse return null,
            .h = std.math.cast(c_int, saved.h) orelse return null,
            .state = saved.state,
        };
    }

    fn toSaved(self: WindowGeometry) Saved {
        return .{
            .x = @intCast(self.x),
            .y = @intCast(self.y),
            .w = @intCast(self.w),
            .h = @intCast(self.h),
            .state = self.state,
        };
    }

    pub fn load(options: InitOptions) ?WindowGeometry {
        if (!options.persist_window_geometry) return null;
        var path_buf: [1024]u8 = undefined;
        const path = filePath(&path_buf, options) orelse return null;
        return loadZon(options.io, path);
    }

    fn loadZon(io: std.Io, path: [:0]const u8) ?WindowGeometry {
        const data = std.Io.Dir.cwd().readFileAlloc(io, path, std.heap.page_allocator, .limited(4096)) catch return null;
        defer std.heap.page_allocator.free(data);
        var nul_buf: [4097]u8 = undefined;
        if (data.len >= nul_buf.len) return null;
        @memcpy(nul_buf[0..data.len], data);
        nul_buf[data.len] = 0;
        const saved = std.zon.parse.fromSlice(
            Saved,
            std.heap.page_allocator,
            nul_buf[0..data.len :0],
            null,
            .{ .ignore_unknown_fields = true },
        ) catch return null;
        return fromSaved(saved);
    }

    fn writeFile(io: std.Io, path: [:0]const u8, g: WindowGeometry) void {
        var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
        defer aw.deinit();
        std.zon.stringify.serialize(g.toSaved(), .{}, &aw.writer) catch return;
        const parent = std.fs.path.dirname(path) orelse return;
        std.Io.Dir.createDirAbsolute(io, parent, .default_dir) catch {};
        std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = aw.written() }) catch {
            log.err("failed to write window_geometry.zon", .{});
        };
    }

    fn save(back: *SDLBackend) void {
        const opts = back.init_opts_save orelse return;
        var path_buf: [1024]u8 = undefined;
        const path = filePath(&path_buf, opts) orelse return;

        //std.debug.print("saving window geometry: {any}\n", .{back.window_geometry});
        WindowGeometry.writeFile(opts.io, path, back.window_geometry);
    }

    /// True if the window's title bar area would land on a connected display.
    /// Guards against restoring onto a monitor that is no longer attached.
    fn posOnADisplay(self: WindowGeometry) bool {
        var count: c_int = 0;
        const displays = c.SDL_GetDisplays(&count) orelse return false;
        defer c.SDL_free(displays);
        const cx = self.x + @divTrunc(self.w, 2);
        const cy = self.y + 10;
        for (displays[0..@intCast(count)]) |id| {
            var bounds: c.SDL_Rect = undefined;
            if (!c.SDL_GetDisplayUsableBounds(id, &bounds)) continue;
            if (cx >= bounds.x and cx < bounds.x + bounds.w and cy >= bounds.y and cy < bounds.y + bounds.h) return true;
        }
        return false;
    }
};

// Common configuration part for both `initWindow` and `initWindowSecondary`
fn configureBackend(back: *SDLBackend, options: InitOptions) !void {
    var hidden = options.hidden;
    var show_window_in_begin = false;
    if (dvui.accesskit_enabled and !hidden) {
        // hide the window until we can initialize accesskit in Window.begin
        hidden = true;
        show_window_in_begin = true;
    }
    back.ak_should_initialized = show_window_in_begin;
    back.we_own_window = true;
    back.clear_window_on_begin = true;

    if (options.icon) |bytes| {
        if (builtin.abi.isAndroid()) {
            // log.error fails on Android but SDL_Log will show up in LogCat
            c.SDL_Log("[ERROR] Android doesn't support setting a custom icon at runtime");
        } else {
            try back.setIconFromFileContent(bytes);
        }
    }
}

fn preventWindowForkBomb() void {
    // This happend to me a few time while working on multi os window.
    // FIXME / TODO : find out if this should remain in one form or another.
    // If it's an option, how to make sure people are aware of it ?
    const too_many_win_msg = "Too many SDL window open. This is preventing fork bombs while hacking on multi os windows, and this limitation will be lifted once stuff are more stable";
    if (sdl3) {
        var count: c_int = 0;
        _ = c.SDL_GetWindows(&count);
        if (count > 5) {
            log.err(too_many_win_msg, .{});
            std.process.exit(1);
        }
    } else {
        // SDL2 doesn't maintain list of windows, just check if we have a window with ID 5 (ID are incremental)
        if (c.SDL_GetWindowFromID(5)) |_| {
            log.err(too_many_win_msg, .{});
            std.process.exit(1);
        }
    }
}

pub fn init(io: std.Io, window: *c.SDL_Window, renderer: *c.SDL_Renderer) SDLBackend {
    dvui.io = io;
    if (sdl3 and builtin.os.tag.isDarwin()) {
        dvui_macos_monitor_install();
    }
    return SDLBackend{ .io = io, .window = window, .renderer = renderer };
}

extern "c" fn dvui_macos_monitor_install() void;
extern "c" fn dvui_macos_monitor_last_scroll_precise() c_int;

const SDL_ERROR = if (sdl3) bool else c_int;
const SDL_SUCCESS: SDL_ERROR = if (sdl3) true else 0;
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
    const surface = if (sdl3)
        c.SDL_CreateSurfaceFrom(
            icon_w,
            icon_h,
            c.SDL_PIXELFORMAT_ABGR8888,
            @ptrCast(@constCast(data)),
            4 * icon_w,
        ) orelse return logErr("SDL_CreateSurfaceFrom in setIconFromABGR8888")
    else
        c.SDL_CreateRGBSurfaceWithFormatFrom(
            @ptrCast(@constCast(data)),
            icon_w,
            icon_h,
            32,
            4 * icon_w,
            c.SDL_PIXELFORMAT_ABGR8888,
        ) orelse return logErr("SDL_CreateRGBSurfaceWithFormatFrom in setIconFromABGR8888");

    defer if (sdl3) c.SDL_DestroySurface(surface) else c.SDL_FreeSurface(surface);

    if (sdl3) {
        // `toErr` logs the error for us
        toErr(c.SDL_SetWindowIcon(self.window, surface), "SDL_SetWindowIcon in setIconFromABGR8888") catch {};
    } else {
        c.SDL_SetWindowIcon(self.window, surface);
    }
}

pub fn accessKitShouldInitialize(self: *SDLBackend) bool {
    return self.ak_should_initialized;
}
pub fn accessKitInitInBegin(self: *SDLBackend) !void {
    std.debug.assert(self.ak_should_initialized);
    if (sdl3) {
        try toErr(c.SDL_ShowWindow(self.window), "SDL_ShowWindow in accessKitInitInBegin");
    } else {
        c.SDL_ShowWindow(self.window);
    }
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
        if (sdl3) {
            ret = c.SDL_WaitEventTimeout(null, @as(c_int, @intCast(timeout)));
        } else {
            ret = c.SDL_WaitEventTimeout(null, @as(c_int, @intCast(timeout))) != 0;
        }

        // TODO: this call to SDL_PollEvent can be removed after resolution of
        // https://github.com/libsdl-org/SDL/issues/6539
        // maintaining this a little longer for people with older SDL versions
        _ = c.SDL_PollEvent(null);

        return ret;
    }

    // don't wait at all
    return false;
}

pub fn cursorShow(_: *SDLBackend, value: ?bool) bool {
    if (sdl3) {
        const prev = c.SDL_CursorVisible();
        if (value) |val| {
            if (val) {
                if (!c.SDL_ShowCursor()) {
                    logErr("SDL_ShowCursor in cursorShow") catch return false;
                }
            } else {
                if (!c.SDL_HideCursor()) {
                    logErr("SDL_HideCursor in cursorShow") catch return false;
                }
            }
        }
        return prev;
    } else {
        const prev = switch (c.SDL_ShowCursor(c.SDL_QUERY)) {
            c.SDL_ENABLE => true,
            c.SDL_DISABLE => false,
            else => logErr("SDL_ShowCursor QUERY in cursorShow") catch return false,
        };
        if (value) |val| {
            if (c.SDL_ShowCursor(if (val) c.SDL_ENABLE else c.SDL_DISABLE) < 0) {
                logErr("SDL_ShowCursor set in cursorShow") catch return false;
            }
        }
        return prev;
    }
}

pub fn native(self: *SDLBackend, _: *dvui.Window) dvui.Window.Native {
    if (sdl3) {
        const props = c.SDL_GetWindowProperties(self.window);
        switch (builtin.os.tag) {
            .windows => return .{ .hwnd = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_WIN32_HWND_POINTER, null) },
            .macos => return .{ .cocoa_window = c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null) },
            else => return {},
        }
    } else {
        switch (builtin.os.tag) {
            .windows => return .{ .hwnd = null },
            .macos => return .{ .cocoa_window = null },
            else => return {},
        }
    }
}

pub fn title(self: *SDLBackend, _: *dvui.Window, new_title: []const u8) void {
    var buf: [300]u8 = @splat(0);
    const c_text: []const u8 = std.fmt.bufPrintSentinel(&buf, "{s}", .{new_title}, 0) catch "title: Error";
    _ = c.SDL_SetWindowTitle(self.window, c_text.ptr);
}

pub fn windowStateSet(self: *SDLBackend, _: *dvui.Window, state: dvui.enums.WindowState) void {
    switch (state) {
        .fullscreen => {
            if (sdl3) _ = c.SDL_SetHint(c.SDL_HINT_VIDEO_MAC_FULLSCREEN_MENU_VISIBILITY, "1");
            _ = c.SDL_SetWindowFullscreen(self.window, if (sdl3) true else 1);
        },
        .maximize => {
            _ = c.SDL_SetWindowFullscreen(self.window, if (sdl3) false else 0);
            _ = c.SDL_MaximizeWindow(self.window);
        },
        .normal => {
            _ = c.SDL_SetWindowFullscreen(self.window, if (sdl3) false else 0);
            _ = c.SDL_RestoreWindow(self.window);
        },
    }
}

pub fn refresh(_: *SDLBackend) void {
    var ue = std.mem.zeroes(c.SDL_Event);
    ue.type = if (sdl3) c.SDL_EVENT_USER else c.SDL_USEREVENT;
    if (sdl3) {
        toErr(c.SDL_PushEvent(&ue), "SDL_PushEvent in refresh") catch {};
    } else {
        // Returns 1 on success, 0 if the event was filtered, or a negative error code on failure
        const ret = c.SDL_PushEvent(&ue);
        if (ret == 0) {
            log.debug("Refresh event was filtered", .{});
        }
        toErr(if (ret < 0) ret else SDL_SUCCESS, "SDL_PushEvent in refresh") catch {};
    }
}

pub fn addAllEvents(self: *SDLBackend, win: *dvui.Window) !void {
    //const flags = c.SDL_GetWindowFlags(self.window);
    //if (flags & c.SDL_WINDOW_MOUSE_FOCUS == 0 and flags & c.SDL_WINDOW_INPUT_FOCUS == 0) {
    //std.debug.print("bailing\n", .{});
    //}
    var event: c.SDL_Event = undefined;
    const poll_got_event = if (sdl3) true else 1;
    while (c.SDL_PollEvent(&event) == poll_got_event) {
        const target_sdl_window = getWindowFromEvent(&event);
        if (target_sdl_window) |target_win| {
            _ = try self.addEventWinRecursive(&event, win, target_win);
        } else {
            // "global" event are managed by "primary" window
            _ = try self.addEvent(win, event);
        }
        //switch (event.type) {
        //    // TODO: revisit with sdl3
        //    //c.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED => {
        //    //std.debug.print("sdl window scale changed event\n", .{});
        //    //},
        //    //c.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED => {
        //    //std.debug.print("sdl display scale changed event\n", .{});
        //    //},
        //    else => {},
        //}
    }
}

/// Recursively Iterate `child_os_wins` and try to deliver the event.
///
/// Note that contrary to `addEvent`, this function return true if the event is sent based on the
///  SDL_Window handle (i.e. OS Window dispatch) and doesn't care about subwindows.
fn addEventWinRecursive(self: *SDLBackend, event: *c.SDL_Event, win: *dvui.Window, target_win: *c.SDL_Window) !bool {
    if (self.window == target_win) {
        _ = try self.addEvent(win, event.*);
        return true;
    }
    var child_win_it = win.child_os_wins.iterator();
    // Use next_peek because the fact we had events since last frame
    // doesn't mean the child Os Window will still be used in the upcoming frame, we don't know that yet.
    while (child_win_it.next_peek()) |alive_win| {
        if (try addEventWinRecursive(
            alive_win.value.backend,
            event,
            alive_win.value.dvui_win,
            target_win,
        )) return true;
    }
    return false;
}

pub fn setCursor(self: *SDLBackend, cursor: dvui.enums.Cursor) void {
    if (cursor == self.cursor_last) return;
    defer self.cursor_last = cursor;
    const new_shown_state = if (cursor == .hidden) false else if (self.cursor_last == .hidden) true else null;
    if (new_shown_state) |new_state| {
        if (self.cursorShow(new_state) == new_state) {
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
            .arrow => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_DEFAULT else c.SDL_SYSTEM_CURSOR_ARROW),
            .ibeam => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_TEXT else c.SDL_SYSTEM_CURSOR_IBEAM),
            .wait => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_WAIT),
            .wait_arrow => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_PROGRESS else c.SDL_SYSTEM_CURSOR_WAITARROW),
            .crosshair => c.SDL_CreateSystemCursor(c.SDL_SYSTEM_CURSOR_CROSSHAIR),
            .arrow_nw_se => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NWSE_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENWSE),
            .arrow_ne_sw => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NESW_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENESW),
            .arrow_w_e => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_EW_RESIZE else c.SDL_SYSTEM_CURSOR_SIZEWE),
            .arrow_n_s => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NS_RESIZE else c.SDL_SYSTEM_CURSOR_SIZENS),
            .arrow_all => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_MOVE else c.SDL_SYSTEM_CURSOR_SIZEALL),
            .bad => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_NOT_ALLOWED else c.SDL_SYSTEM_CURSOR_NO),
            .hand => c.SDL_CreateSystemCursor(if (sdl3) c.SDL_SYSTEM_CURSOR_POINTER else c.SDL_SYSTEM_CURSOR_HAND),
            .hidden => unreachable,
        };
    }

    if (self.cursor_backing[enum_int]) |cur| {
        if (sdl3) {
            toErr(c.SDL_SetCursor(cur), "SDL_SetCursor in setCursor") catch return;
        } else {
            c.SDL_SetCursor(cur);
        }
    } else {
        log.err("setCursor \"{s}\" failed", .{@tagName(cursor)});
        logErr("SDL_CreateSystemCursor in setCursor") catch return;
    }
    self.manage_backend_tracking.check(.setCursor);
}

pub fn textInputRect(self: *SDLBackend, rect: ?dvui.Rect.Natural) void {
    if (rect) |r| {
        if (sdl3) {
            // This is the offset from r.x in window coords, supposed to be the
            // location of the cursor I think so that the IME window can be put
            // at the cursor location.  We will use 0 for now, might need to
            // change it (or how we determine rect) if people are using huge
            // text entries).
            const cursor = 0;

            toErr(c.SDL_SetTextInputArea(
                self.window,
                &c.SDL_Rect{
                    .x = @trunc(r.x),
                    .y = @trunc(r.y),
                    .w = @trunc(r.w),
                    .h = @trunc(r.h),
                },
                cursor,
            ), "SDL_SetTextInputArea in textInputRect") catch return;
        } else c.SDL_SetTextInputRect(&c.SDL_Rect{
            .x = @trunc(r.x),
            .y = @trunc(r.y),
            .w = @trunc(r.w),
            .h = @trunc(r.h),
        });
        if (sdl3) {
            toErr(c.SDL_StartTextInput(self.window), "SDL_StartTextInput in textInputRect") catch return;
        } else {
            c.SDL_StartTextInput();
        }
    } else {
        if (sdl3) {
            toErr(c.SDL_StopTextInput(self.window), "SDL_StopTextInput in textInputRect") catch return;
        } else {
            c.SDL_StopTextInput();
        }
    }
    self.manage_backend_tracking.check(.textInputRect);
}

pub fn deinit(self: *SDLBackend) void {
    for (self.cursor_backing) |cursor| {
        if (cursor) |cur| {
            if (sdl3) {
                c.SDL_DestroyCursor(cur);
            } else {
                c.SDL_FreeCursor(cur);
            }
        }
    }

    if (self.we_own_window) {
        if (comptime sdl3) {
            if (self.init_opts_save != null and self.init_opts_save.?.persist_window_geometry) {
                self.trackGeometry();
                WindowGeometry.save(self);
            }
        }
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        if (self.sdl_quit) {
            c.SDL_Quit();
        }
    }
    self.* = undefined;
}

pub fn renderPresent(self: *SDLBackend) void {
    if (sdl3) {
        toErr(c.SDL_RenderPresent(self.renderer), "SDL_RenderPresent in renderPresent") catch {};
    } else {
        c.SDL_RenderPresent(self.renderer);
    }
    self.manage_backend_tracking.check(.renderPresent);
}

pub fn backend(self: *SDLBackend) dvui.Backend {
    return dvui.Backend.init(self);
}

pub fn nanoTime(self: *SDLBackend) i128 {
    const ret = std.Io.Clock.awake.now(self.io);
    return ret.nanoseconds;
}

pub fn sleep(self: *SDLBackend, ns: u64) void {
    std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromNanoseconds(ns) }, self.io) catch {};
}

pub fn clipboardText(self: *SDLBackend) ![]const u8 {
    if (c.SDL_HasClipboardText() == (if (sdl3) false else 0)) return &.{};

    const p = c.SDL_GetClipboardText();
    defer c.SDL_free(p); // must free even on error

    const str = std.mem.span(p);
    // Log error, but don't fail the application
    if (str.len == 0) logErr("SDL_GetClipboardText in clipboardText") catch {};

    return try self.arena.dupe(u8, str);
}

pub fn clipboardTextSet(self: *SDLBackend, text: []const u8) !void {
    if (text.len == 0) return;
    const c_text = try self.arena.dupeSentinel(u8, text, 0);
    defer self.arena.free(c_text);
    try toErr(c.SDL_SetClipboardText(c_text.ptr), "SDL_SetClipboardText in clipboardTextSet");
}

pub fn openURL(self: *SDLBackend, url: []const u8, _: bool) !void {
    const c_url = try self.arena.dupeSentinel(u8, url, 0);
    defer self.arena.free(c_url);
    try toErr(c.SDL_OpenURL(c_url.ptr), "SDL_OpenURL in openURL");
}

pub fn preferredColorScheme(_: *SDLBackend) ?dvui.enums.ColorScheme {
    if (sdl3) {
        return switch (c.SDL_GetSystemTheme()) {
            c.SDL_SYSTEM_THEME_DARK => .dark,
            c.SDL_SYSTEM_THEME_LIGHT => .light,
            else => null,
        };
    } else if (builtin.target.os.tag == .windows) {
        return dvui.Backend.Common.windowsGetPreferredColorScheme();
    }
    return null;
}

pub fn prefersReducedMotion(_: *@This()) bool {
    return false;
}

pub fn begin(self: *SDLBackend, arena: std.mem.Allocator) !void {
    self.arena = arena;
    if (self.begin_hook) |hook| hook(self);
    if (self.clear_window_on_begin) try self.clearWindow();
    const size = self.pixelSize();
    if (sdl3) {
        try toErr(c.SDL_SetRenderClipRect(self.renderer, &c.SDL_Rect{
            .x = 0,
            .y = 0,
            .w = @trunc(size.w),
            .h = @trunc(size.h),
        }), "SDL_SetRenderClipRect in begin");
    } else {
        try toErr(c.SDL_RenderSetClipRect(self.renderer, &c.SDL_Rect{
            .x = 0,
            .y = 0,
            .w = @trunc(size.w),
            .h = @trunc(size.h),
        }), "SDL_SetRenderClipRect in begin");
    }
    self.manage_backend_tracking.reset_begin();
}

pub fn clearWindow(self: *SDLBackend) !void {
    try toErr(SDLBackend.c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0), "SDL_SetRenderDrawColor in clearScreen");
    try toErr(SDLBackend.c.SDL_RenderClear(self.renderer), "SDL_RenderClear in clearScreen");
}

pub fn end(_: *SDLBackend) !void {}

pub fn pixelSize(self: *SDLBackend) dvui.Size.Physical {
    var w: i32 = undefined;
    var h: i32 = undefined;
    if (sdl3) {
        toErr(
            c.SDL_GetCurrentRenderOutputSize(self.renderer, &w, &h),
            "SDL_GetCurrentRenderOutputSize in pixelSize",
        ) catch return self.last_pixel_size;
    } else {
        toErr(
            c.SDL_GetRendererOutputSize(self.renderer, &w, &h),
            "SDL_GetRendererOutputSize in pixelSize",
        ) catch return self.last_pixel_size;
    }
    self.last_pixel_size = .{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
    return self.last_pixel_size;
}

pub fn windowSize(self: *SDLBackend) dvui.Size.Natural {
    var w: i32 = undefined;
    var h: i32 = undefined;
    if (sdl3) {
        toErr(c.SDL_GetWindowSize(self.window, &w, &h), "SDL_GetWindowSize in windowSize") catch return self.last_window_size;
    } else {
        c.SDL_GetWindowSize(self.window, &w, &h);
    }
    self.last_window_size = .{ .w = @as(f32, @floatFromInt(w)), .h = @as(f32, @floatFromInt(h)) };
    return self.last_window_size;
}

pub fn contentScale(self: *SDLBackend) f32 {
    if (sdl3) {
        const display_id = c.SDL_GetDisplayForWindow(self.window);
        const scale = c.SDL_GetDisplayContentScale(display_id);
        if (scale == 0.0) {
            log.err("SDL_GetDisplayContentScale returned 0", .{});
            return 1.0;
        }
        return scale;
    } else {
        return sdl2_scale;
    }
}

pub fn drawClippedTriangles(self: *SDLBackend, texture: ?dvui.Texture, vtx: []const dvui.Vertex, idx: []const dvui.Vertex.Index, maybe_clipr: ?dvui.Rect.Physical) !void {
    //std.debug.print("drawClippedTriangles:\n", .{});
    //for (vtx) |v, i| {
    //  std.debug.print("  {d} vertex {}\n", .{i, v});
    //}
    //for (idx) |id, i| {
    //  std.debug.print("  {d} index {d}\n", .{i, id});
    //}

    var oldclip: c.SDL_Rect = undefined;

    if (maybe_clipr) |clipr| {
        if (sdl3) {
            try toErr(
                c.SDL_GetRenderClipRect(self.renderer, &oldclip),
                "SDL_GetRenderClipRect in drawClippedTriangles",
            );
        } else {
            c.SDL_RenderGetClipRect(self.renderer, &oldclip);
        }

        const clip = c.SDL_Rect{
            .x = @trunc(clipr.x),
            .y = @trunc(clipr.y),
            .w = @trunc(clipr.w),
            .h = @trunc(clipr.h),
        };
        if (sdl3) {
            try toErr(
                c.SDL_SetRenderClipRect(self.renderer, &clip),
                "SDL_SetRenderClipRect in drawClippedTriangles",
            );
        } else {
            try toErr(
                c.SDL_RenderSetClipRect(self.renderer, &clip),
                "SDL_RenderSetClipRect in drawClippedTriangles",
            );
        }
    }

    var tex: ?*c.SDL_Texture = null;
    if (texture) |t| {
        tex = @ptrCast(@alignCast(t.ptr));
        if (sdl3) {
            _ = c.SDL_SetRenderTextureAddressMode(
                self.renderer,
                if (t.wrap_u == .clamp) c.SDL_TEXTURE_ADDRESS_CLAMP else c.SDL_TEXTURE_ADDRESS_WRAP,
                if (t.wrap_v == .clamp) c.SDL_TEXTURE_ADDRESS_CLAMP else c.SDL_TEXTURE_ADDRESS_WRAP,
            );
        }
    }

    if (sdl3) {
        // not great, but seems sdl3 strictly accepts color only in floats
        // TODO: review if better solution is possible
        const vcols = try self.arena.alloc(c.SDL_FColor, vtx.len);
        defer self.arena.free(vcols);
        for (vcols, 0..) |*col, i| {
            col.r = @as(f32, @floatFromInt(vtx[i].col.r)) / 255.0;
            col.g = @as(f32, @floatFromInt(vtx[i].col.g)) / 255.0;
            col.b = @as(f32, @floatFromInt(vtx[i].col.b)) / 255.0;
            col.a = @as(f32, @floatFromInt(vtx[i].col.a)) / 255.0;
        }

        try toErr(c.SDL_RenderGeometryRaw(
            self.renderer,
            tex,
            @as(*const f32, @ptrCast(&vtx[0].pos)),
            @sizeOf(dvui.Vertex),
            vcols.ptr,
            @sizeOf(c.SDL_FColor),
            @as(*const f32, @ptrCast(&vtx[0].uv)),
            @sizeOf(dvui.Vertex),
            @as(c_int, @intCast(vtx.len)),
            idx.ptr,
            @as(c_int, @intCast(idx.len)),
            @sizeOf(dvui.Vertex.Index),
        ), "SDL_RenderGeometryRaw, in drawClippedTriangles");
    } else {
        var clamped: ?[]f32 = null;
        defer if (clamped) |cld| self.arena.free(cld);

        if (texture) |t| {
            var out_of_bounds = false;
            clamped = try self.arena.alloc(f32, vtx.len * 2);
            for (vtx, 0..) |v, i| {
                if (v.uv[0] < 0 or v.uv[0] > 1 or v.uv[1] < 0 or v.uv[1] > 1) out_of_bounds = true;
                clamped.?[i * 2] = std.math.clamp(v.uv[0], 0, 1);
                clamped.?[i * 2 + 1] = std.math.clamp(v.uv[1], 0, 1);
            }

            if (out_of_bounds and (t.wrap_u != .clamp or t.wrap_v != .clamp)) {
                log.err("sdl2: uv coords clamped, .repeat not supported", .{});
            }
        }

        try toErr(c.SDL_RenderGeometryRaw(
            self.renderer,
            tex,
            @as(*const f32, @ptrCast(&vtx[0].pos)),
            @sizeOf(dvui.Vertex),
            @as(*const c.SDL_Color, @ptrCast(@alignCast(&vtx[0].col))),
            @sizeOf(dvui.Vertex),
            if (clamped) |cld| cld.ptr else @ptrCast(&vtx[0].uv),
            if (clamped) |_| 2 * @sizeOf(f32) else @sizeOf(dvui.Vertex),
            @as(c_int, @intCast(vtx.len)),
            idx.ptr,
            @as(c_int, @intCast(idx.len)),
            @sizeOf(dvui.Vertex.Index),
        ), "SDL_RenderGeometryRaw in drawClippedTriangles");
    }

    if (maybe_clipr) |_| {
        if (sdl3) {
            try toErr(
                c.SDL_SetRenderClipRect(self.renderer, &oldclip),
                "SDL_SetRenderClipRect in drawClippedTriangles reset clip",
            );
        } else {
            try toErr(
                c.SDL_RenderSetClipRect(self.renderer, &oldclip),
                "SDL_RenderSetClipRect in drawClippedTriangles reset clip",
            );
        }
    }
}

pub fn pixelFormatToSdl(format: dvui.enums.TexturePixelFormat) ?u32 {
    return switch (format) {
        .rgba_32 => c.SDL_PIXELFORMAT_RGBA32,
        .argb_32 => c.SDL_PIXELFORMAT_ARGB32,
        .bgra_32 => c.SDL_PIXELFORMAT_BGRA32,
        .abgr_32 => c.SDL_PIXELFORMAT_ABGR32,

        .rgbx_32 => c.SDL_PIXELFORMAT_RGBX32,
        .xrgb_32 => c.SDL_PIXELFORMAT_XRGB32,
        .bgrx_32 => c.SDL_PIXELFORMAT_BGRX32,
        .xbgr_32 => c.SDL_PIXELFORMAT_XBGR32,

        .rgba_8_8_8_8 => c.SDL_PIXELFORMAT_RGBA8888,
        .argb_8_8_8_8 => c.SDL_PIXELFORMAT_ARGB8888,
        .bgra_8_8_8_8 => c.SDL_PIXELFORMAT_BGRA8888,
        .abgr_8_8_8_8 => c.SDL_PIXELFORMAT_ABGR8888,

        .rgbx_8_8_8_8 => c.SDL_PIXELFORMAT_RGBX8888,
        .xrgb_8_8_8_8 => c.SDL_PIXELFORMAT_XRGB8888,
        .bgrx_8_8_8_8 => c.SDL_PIXELFORMAT_BGRX8888,
        .xbgr_8_8_8_8 => c.SDL_PIXELFORMAT_XBGR8888,

        .fourcc_yv12 => c.SDL_PIXELFORMAT_YV12,
        .fourcc_iyuv => c.SDL_PIXELFORMAT_IYUV,
        .fourcc_yuy2 => c.SDL_PIXELFORMAT_YUY2,
        .fourcc_uyvy => c.SDL_PIXELFORMAT_UYVY,
        .fourcc_yvyu => c.SDL_PIXELFORMAT_YVYU,
    };
}

pub fn textureCreate(self: *SDLBackend, pixels: [*]const u8, options: dvui.Texture.CreateOptions) !dvui.Texture {
    if (!sdl3) switch (options.interpolation) {
        .nearest => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "nearest"),
        .linear => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear"),
    };

    const sdl_format = pixelFormatToSdl(options.format) orelse {
        log.err("pixel format {} not supported", .{options.format});
        return dvui.Backend.TextureError.NotImplemented;
    };

    const surface = if (sdl3)
        c.SDL_CreateSurfaceFrom(
            @as(c_int, @intCast(options.width)),
            @as(c_int, @intCast(options.height)),
            @as(c.SDL_PixelFormat, @intCast(sdl_format)),
            @constCast(pixels),
            @as(c_int, @intCast(options.width * options.format.pitchFactor())),
        ) orelse return logErr("SDL_CreateSurfaceFrom in textureCreate")
    else
        c.SDL_CreateRGBSurfaceWithFormatFrom(
            @constCast(pixels),
            @as(c_int, @intCast(options.width)),
            @as(c_int, @intCast(options.height)),
            32,
            @as(c_int, @intCast(options.width * options.format.pitchFactor())),
            sdl_format,
        ) orelse return logErr("SDL_CreateRGBSurfaceWithFormatFrom in textureCreate");

    defer if (sdl3) c.SDL_DestroySurface(surface) else c.SDL_FreeSurface(surface);

    const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return logErr("SDL_CreateTextureFromSurface in textureCreate");
    errdefer c.SDL_DestroyTexture(texture);

    if (sdl3) try toErr(switch (options.interpolation) {
        .nearest => c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST),
        .linear => c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_LINEAR),
    }, "SDL_SetTextureScaleMode in textureCreates");

    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    try toErr(c.SDL_SetTextureBlendMode(texture, pma_blend), "SDL_SetTextureBlendMode in textureCreate");
    return dvui.Texture{ .ptr = texture, .width = options.width, .height = options.height, .format = options.format, .interpolation = options.interpolation, .wrap_u = options.wrap_u, .wrap_v = options.wrap_v };
}

pub fn textureUpdate(_: *SDLBackend, texture: dvui.Texture, pixels: [*]const u8) !void {
    if (comptime sdl3) {
        const tx: [*c]c.SDL_Texture = @ptrCast(@alignCast(texture.ptr));
        if (!c.SDL_UpdateTexture(tx, null, pixels, @intCast(texture.width * texture.format.pitchFactor()))) return error.TextureUpdate;
    } else {
        return dvui.Backend.TextureError.NotImplemented;
    }
}

pub fn textureUpdateSubRect(_: *SDLBackend, texture: dvui.Texture, pixels: [*]const u8, x: u32, y: u32, w: u32, h: u32) !void {
    if (comptime sdl3) {
        const tx: [*c]c.SDL_Texture = @ptrCast(@alignCast(texture.ptr));
        const pitch_factor: usize = texture.format.pitchFactor();
        const row_pitch: usize = @as(usize, texture.width) * pitch_factor;
        const offset: usize = @as(usize, y) * row_pitch + @as(usize, x) * pitch_factor;
        const rect: c.SDL_Rect = .{ .x = @intCast(x), .y = @intCast(y), .w = @intCast(w), .h = @intCast(h) };
        if (!c.SDL_UpdateTexture(tx, &rect, pixels + offset, @intCast(row_pitch))) return error.TextureUpdate;
    } else {
        return dvui.Backend.TextureError.NotImplemented;
    }
}

pub fn textureCreateTarget(self: *SDLBackend, options: dvui.Texture.CreateOptions) !dvui.TextureTarget {
    if (!sdl3) switch (options.interpolation) {
        .nearest => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "nearest"),
        .linear => _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "linear"),
    };

    const sdl_format = pixelFormatToSdl(options.format) orelse {
        log.err("pixel format {} not supported", .{options.format});
        return dvui.Backend.TextureError.NotImplemented;
    };

    const texture = c.SDL_CreateTexture(
        self.renderer,
        if (comptime sdl3) @as(c.SDL_PixelFormat, @intCast(sdl_format)) else sdl_format,
        c.SDL_TEXTUREACCESS_TARGET,
        @intCast(options.width),
        @intCast(options.height),
    ) orelse return logErr("SDL_CreateTexture in textureCreateTarget");
    errdefer c.SDL_DestroyTexture(texture);

    if (sdl3) try toErr(switch (options.interpolation) {
        .nearest => c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_NEAREST),
        .linear => c.SDL_SetTextureScaleMode(texture, c.SDL_SCALEMODE_LINEAR),
    }, "SDL_SetTextureScaleMode in textureCreates");

    const pma_blend = c.SDL_ComposeCustomBlendMode(c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD, c.SDL_BLENDFACTOR_ONE, c.SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA, c.SDL_BLENDOPERATION_ADD);
    try toErr(
        c.SDL_SetTextureBlendMode(texture, pma_blend),
        "SDL_SetTextureBlendMode in textureCreateTarget",
    );
    //try toErr(c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND), "SDL_SetTextureBlendMode in textureCreateTarget",);

    const tex = dvui.TextureTarget{ .ptr = texture, .width = options.width, .height = options.height, .format = options.format, .interpolation = options.interpolation, .wrap_u = .clamp, .wrap_v = .clamp };
    self.textureClearTarget(tex);
    return tex;
}

pub fn textureClearTarget(self: *SDLBackend, texture: dvui.TextureTarget) void {
    // null is the default render target
    const old = c.SDL_GetRenderTarget(self.renderer);
    defer _ = c.SDL_SetRenderTarget(self.renderer, old);

    var oldBlend: c_uint = undefined;
    _ = c.SDL_GetRenderDrawBlendMode(self.renderer, &oldBlend);
    defer _ = c.SDL_SetRenderDrawBlendMode(self.renderer, oldBlend);

    toErr(
        c.SDL_SetRenderTarget(self.renderer, @ptrCast(@alignCast(texture.ptr))),
        "SDL_SetRenderTarget in textureClearTarget",
    ) catch return;

    toErr(
        c.SDL_SetRenderDrawBlendMode(self.renderer, c.SDL_BLENDMODE_NONE),
        "SDL_SetRenderDrawBlendMode in textureClearTarget",
    ) catch return;

    toErr(
        c.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 0),
        "SDL_SetRenderDrawColor in textureClearTarget",
    ) catch return;

    toErr(
        c.SDL_RenderFillRect(self.renderer, null),
        "SDL_RenderFillRect in textureClearTarget",
    ) catch return;
}

pub fn textureReadTarget(self: *SDLBackend, texture: dvui.TextureTarget, pixels_out: [*]u8) !void {
    if (sdl3) {
        // null is the default target
        const orig_target = c.SDL_GetRenderTarget(self.renderer);
        try toErr(c.SDL_SetRenderTarget(self.renderer, @ptrCast(@alignCast(texture.ptr))), "SDL_SetRenderTarget in textureReadTarget");
        defer toErr(
            c.SDL_SetRenderTarget(self.renderer, orig_target),
            "SDL_SetRenderTarget in textureReadTarget",
        ) catch log.err("Could not reset render target", .{});

        var surface: *c.SDL_Surface = c.SDL_RenderReadPixels(self.renderer, null) orelse
            logErr("SDL_RenderReadPixels in textureReadTarget") catch
            return dvui.Backend.TextureError.TextureRead;
        defer c.SDL_DestroySurface(surface);

        if (texture.width * texture.height != surface.*.w * surface.*.h) {
            log.err(
                "texture and target surface sizes did not match: texture {d} {d} surface {d} {d}\n",
                .{ texture.width, texture.height, surface.*.w, surface.*.h },
            );
            return dvui.Backend.TextureError.TextureRead;
        }

        // TODO: most common format is RGBA8888, doing conversion during copy to pixels_out should be faster
        if (surface.*.format != c.SDL_PIXELFORMAT_ABGR8888) {
            surface = c.SDL_ConvertSurface(surface, c.SDL_PIXELFORMAT_ABGR8888) orelse
                logErr("SDL_ConvertSurface in textureReadTarget") catch
                return dvui.Backend.TextureError.TextureRead;
        }
        @memcpy(pixels_out[0 .. texture.width * texture.height * 4], @as(?[*]u8, @ptrCast(surface.*.pixels)).?[0 .. texture.width * texture.height * 4]);
        return;
    }

    // If SDL picks directX11 as a rendering backend, it could not support
    // SDL_PIXELFORMAT_ABGR8888 so this works around that.  For some reason sdl
    // crashes if we ask it to do the conversion for us.
    var swap_rb = true;
    var info: c.SDL_RendererInfo = undefined;
    try toErr(c.SDL_GetRendererInfo(self.renderer, &info), "SDL_GetRendererInfo in textureReadTarget");
    //std.debug.print("renderer name {s} formats:\n", .{info.name});
    for (0..info.num_texture_formats) |i| {
        //std.debug.print("  {s}\n", .{c.SDL_GetPixelFormatName(info.texture_formats[i])});
        if (info.texture_formats[i] == c.SDL_PIXELFORMAT_ABGR8888) {
            swap_rb = false;
        }
    }

    const orig_target = c.SDL_GetRenderTarget(self.renderer);
    try toErr(c.SDL_SetRenderTarget(self.renderer, @ptrCast(texture.ptr)), "SDL_SetRenderTarget in textureReadTarget");
    defer toErr(
        c.SDL_SetRenderTarget(self.renderer, orig_target),
        "SDL_SetRenderTarget in textureReadTarget",
    ) catch log.err("Could not reset render target", .{});

    toErr(
        c.SDL_RenderReadPixels(
            self.renderer,
            null,
            if (swap_rb) c.SDL_PIXELFORMAT_ARGB8888 else c.SDL_PIXELFORMAT_ABGR8888,
            pixels_out,
            @intCast(texture.width * 4),
        ),
        "SDL_RenderReadPixels in textureReadTarget",
    ) catch return dvui.Backend.TextureError.TextureRead;

    if (swap_rb) {
        for (0..texture.width * texture.height) |i| {
            const r = pixels_out[i * 4 + 0];
            const b = pixels_out[i * 4 + 2];
            pixels_out[i * 4 + 0] = b;
            pixels_out[i * 4 + 2] = r;
        }
    }
}

pub fn textureDestroy(_: *SDLBackend, texture: dvui.Texture) void {
    c.SDL_DestroyTexture(@as(*c.SDL_Texture, @ptrCast(@alignCast(texture.ptr))));
}

pub fn textureDestroyTarget(_: *SDLBackend, texture: dvui.Texture.Target) void {
    c.SDL_DestroyTexture(@as(*c.SDL_Texture, @ptrCast(@alignCast(texture.ptr))));
}

// as if we are destroying target and creating a new texture
pub fn textureFromTarget(_: *SDLBackend, target: dvui.TextureTarget) !dvui.Texture {
    // SDL can't read from non-target textures, but we are enforcing that through zig types
    return .cast(target);
}

// return is temporary, will not be destroyed
pub fn textureFromTargetTemp(_: *SDLBackend, target: dvui.TextureTarget) !dvui.Texture {
    return .cast(target);
}

pub fn renderTarget(self: *SDLBackend, texture: ?dvui.TextureTarget) !void {
    const ptr: ?*anyopaque = if (texture) |tex| tex.ptr else null;
    try toErr(c.SDL_SetRenderTarget(self.renderer, @ptrCast(@alignCast(ptr))), "SDL_SetRenderTarget in renderTarget");

    // by default sdl sets an empty clip, let's ensure it is the full texture/screen
    if (sdl3) {
        // sdl3 crashes if w/h are too big, this seems to work
        try toErr(
            c.SDL_SetRenderClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = 65536, .h = 65536 }),
            "SDL_SetRenderClipRect in renderTarget",
        );
    } else {
        try toErr(
            c.SDL_RenderSetClipRect(self.renderer, &c.SDL_Rect{ .x = 0, .y = 0, .w = std.math.maxInt(c_int), .h = std.math.maxInt(c_int) }),
            "SDL_RenderSetClipRect in renderTarget",
        );
    }
}

/// Record the window rect on move/resize while the window is in its normal
/// (non-fullscreen/maximized/minimized) state.  Marks the geometry dirty rather
/// than writing it; the write is deferred to `flushGeometryIfDirty`.  SDL3 only.
fn trackGeometry(self: *SDLBackend) void {
    if (self.init_opts_save) |opts| if (!opts.persist_window_geometry) return;

    const flags = c.SDL_GetWindowFlags(self.window);
    if (flags & c.SDL_WINDOW_MINIMIZED != 0) {
        // don't track
        //std.debug.print("track: minimized\n", .{});
        return;
    }

    if (flags & c.SDL_WINDOW_FULLSCREEN != 0) {
        // only track state
        self.window_geometry.state = .fullscreen;
        //std.debug.print("track: fullscreen\n", .{});
        return;
    }

    if (flags & c.SDL_WINDOW_MAXIMIZED != 0) {
        // only track state
        self.window_geometry.state = .maximized;
        //std.debug.print("track: maximized\n", .{});
        return;
    }

    var x: c_int = 0;
    var y: c_int = 0;
    var w: c_int = 0;
    var h: c_int = 0;
    if (!c.SDL_GetWindowPosition(self.window, &x, &y)) return;
    if (!c.SDL_GetWindowSize(self.window, &w, &h)) return;
    if (w < 1 or h < 1) return;
    self.window_geometry = .{ .x = x, .y = y, .w = w, .h = h };
    //std.debug.print("track: normal {any}\n", .{self.window_geometry});
}

/// Send an SDL_Event to a dvui.Window
///
/// Return true if the event is to be handled by a subwindow.
///
/// This allows "ontop" application main loop to ignore such events since they
/// are meant for something visually floating on top of the main application.
pub fn addEvent(self: *SDLBackend, win: *dvui.Window, event: c.SDL_Event) !bool {
    switch (event.type) {
        if (sdl3) c.SDL_EVENT_KEY_DOWN else c.SDL_KEYDOWN => {
            const sdl_key: i32 = if (sdl3) @intCast(event.key.key) else event.key.keysym.sym;
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(if (sdl3) @intCast(event.key.mod) else event.key.keysym.mod);
            if (self.log_events) {
                log.debug("event KEYDOWN {any} {s} {any} {any}\n", .{ sdl_key, @tagName(code), mod, event.key.repeat });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = if (if (sdl3) event.key.repeat else event.key.repeat != 0) .repeat else .down,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_KEY_UP else c.SDL_KEYUP => {
            const sdl_key: i32 = if (sdl3) @intCast(event.key.key) else event.key.keysym.sym;
            const code = SDL_keysym_to_dvui(@intCast(sdl_key));
            const mod = SDL_keymod_to_dvui(if (sdl3) @intCast(event.key.mod) else event.key.keysym.mod);
            if (self.log_events) {
                log.debug("event KEYUP {any} {s} {any}\n", .{ sdl_key, @tagName(code), mod });
            }

            return try win.addEventKey(.{
                .code = code,
                .action = .up,
                .mod = mod,
            });
        },
        if (sdl3) c.SDL_EVENT_TEXT_INPUT else c.SDL_TEXTINPUT => {
            const txt = std.mem.sliceTo(if (sdl3) event.text.text else &event.text.text, 0);
            if (self.log_events) {
                log.debug("event TEXTINPUT {s}\n", .{txt});
            }

            return try win.addEventText(.{ .text = txt });
        },
        if (sdl3) c.SDL_EVENT_TEXT_EDITING else c.SDL_TEXTEDITING => {
            const strlen: u8 = @intCast(c.SDL_strlen(if (sdl3) event.edit.text else &event.edit.text));
            if (self.log_events) {
                log.debug("event TEXTEDITING {s} start {d} len {d} strlen {d}\n", .{ event.edit.text, event.edit.start, event.edit.length, strlen });
            }
            return try win.addEventText(.{ .text = event.edit.text[0..strlen], .selected = true });
        },
        if (sdl3) c.SDL_EVENT_MOUSE_MOTION else c.SDL_MOUSEMOTION => {
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
            const windowW = self.windowSize().w;
            const scale = if (windowW == 0) 1.0 else (self.pixelSize().w / windowW);

            if (sdl3) {
                return try win.addEventMouseMotion(.{
                    .pt = .{
                        .x = event.motion.x * scale,
                        .y = event.motion.y * scale,
                    },
                });
            } else {
                return try win.addEventMouseMotion(.{
                    .pt = .{
                        .x = @as(f32, @floatFromInt(event.motion.x)) * scale,
                        .y = @as(f32, @floatFromInt(event.motion.y)) * scale,
                    },
                });
            }
        },
        if (sdl3) c.SDL_EVENT_MOUSE_BUTTON_DOWN else c.SDL_MOUSEBUTTONDOWN => {
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
        if (sdl3) c.SDL_EVENT_MOUSE_BUTTON_UP else c.SDL_MOUSEBUTTONUP => {
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
        if (sdl3) c.SDL_EVENT_MOUSE_WHEEL else c.SDL_MOUSEWHEEL => {
            // .precise added in 2.0.18
            const ticks_x = if (sdl3) event.wheel.x else event.wheel.preciseX;
            const ticks_y = if (sdl3) event.wheel.y else event.wheel.preciseY;

            if (self.log_events) {
                log.debug("event MOUSEWHEEL {d} {d} {d} {s}\n", .{ ticks_x, ticks_y, event.wheel.which, if (event.wheel.direction == c.SDL_MOUSEWHEEL_FLIPPED) "flipped" else "normal" });
            }

            // macOS dispatches continuous wheel events at the display refresh rate
            // (AppKit syncs scrollWheel: to CVDisplayLink). SDL3's Cocoa_HandleMouseWheel forwards
            // [event scrollingDeltaY] verbatim, so a 120Hz ProMotion display delivers 2× the wheel
            // events per second of a 60Hz display
            //
            // Normalize by 60/refresh_hz on macOS
            const mac_wheel_scale: f32 = if (sdl3 and builtin.os.tag.isDarwin()) blk: {
                const display = c.SDL_GetDisplayForWindow(self.window);
                if (display == 0) break :blk 1.0;
                const mode = c.SDL_GetCurrentDisplayMode(display) orelse break :blk 1.0;
                const hz = mode.*.refresh_rate;
                if (hz <= 0) break :blk 1.0;
                break :blk 60.0 / hz;
            } else 1.0;

            // On macOS we override the magnitude heuristic with the OS-side flag from
            // the NSEvent monitor (see init / macos_monitor.m). Updates per scroll
            // event so users switching between a trackpad and a mouse mid-session get
            // the right classification immediately.
            var mouse_type: dvui.enums.MouseType = .unknown;

            if (sdl3 and builtin.os.tag.isDarwin()) {
                const v = dvui_macos_monitor_last_scroll_precise();
                if (v >= 0) {
                    mouse_type = if (v != 0) .trackpad else .mouse;
                }
            }

            var ret = false;
            // sdl says x positive means to the right, where as y positive
            // means up, so we negate x so that down and right match
            if (ticks_x != 0) {
                if (mouse_type == .unknown) {
                    const min = win.mouseWheelBatch(.horizontal, ticks_x);
                    mouse_type = if (min == 1.0) .mouse else .trackpad;
                }
                ret = try win.addEventMouseWheel(-ticks_x * dvui.scroll_speed * mac_wheel_scale, .horizontal, mouse_type);
            }
            if (ticks_y != 0) {
                if (mouse_type == .unknown) {
                    const min = win.mouseWheelBatch(.vertical, ticks_y);
                    mouse_type = if (min == 1.0) .mouse else .trackpad;
                }
                ret = try win.addEventMouseWheel(ticks_y * dvui.scroll_speed * mac_wheel_scale, .vertical, mouse_type);
            }
            return ret;
        },
        if (sdl3) c.SDL_EVENT_FINGER_DOWN else c.SDL_FINGERDOWN => {
            if (self.log_events) {
                log.debug("event FINGERDOWN {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.{ .button = .touch0, .action = .press, .xynorm = .{ .x = event.tfinger.x, .y = event.tfinger.y } });
        },
        if (sdl3) c.SDL_EVENT_FINGER_UP else c.SDL_FINGERUP => {
            if (self.log_events) {
                log.debug("event FINGERUP {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y });
            }

            return try win.addEventPointer(.{ .button = .touch0, .action = .release, .xynorm = .{ .x = event.tfinger.x, .y = event.tfinger.y } });
        },
        if (sdl3) c.SDL_EVENT_FINGER_MOTION else c.SDL_FINGERMOTION => {
            if (self.log_events) {
                log.debug("event FINGERMOTION {d} {d} {d} {d} {d}\n", .{ if (sdl3) event.tfinger.fingerID else event.tfinger.fingerId, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy });
            }

            return try win.addEventTouchMotion(.touch0, event.tfinger.x, event.tfinger.y, event.tfinger.dx, event.tfinger.dy);
        },
        if (sdl3) c.SDL_EVENT_WINDOW_FOCUS_GAINED else c.SDL_WINDOWEVENT_FOCUS_GAINED => {
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
        if (sdl3) c.SDL_EVENT_WINDOW_FOCUS_LOST else c.SDL_WINDOWEVENT_FOCUS_LOST => {
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
        if (sdl3) c.SDL_EVENT_WINDOW_SHOWN else c.SDL_WINDOWEVENT_SHOWN => {
            if (self.log_events) {
                log.debug("event WINDOW_SHOWN\n", .{});
            }
            if (comptime sdl3) {
                self.trackGeometry();
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
        if (sdl3) c.SDL_EVENT_WINDOW_MOVED else c.SDL_WINDOWEVENT_MOVED, if (sdl3) c.SDL_EVENT_WINDOW_RESIZED else c.SDL_WINDOWEVENT_RESIZED => {
            if (comptime sdl3) {
                self.trackGeometry();
            }
            return false;
        },
        if (sdl3) c.SDL_EVENT_WINDOW_CLOSE_REQUESTED else c.SDL_WINDOWEVENT_CLOSE => {
            if (self.log_events) {
                log.debug("SDL event window close\n", .{});
            }
            try win.addEventWindow(.{ .action = .close });
            return false;
        },
        if (sdl3) c.SDL_EVENT_QUIT else c.SDL_QUIT => {
            if (self.log_events) {
                log.debug("SDL event quit\n", .{});
            }
            try win.addEventApp(.{ .action = .quit });
            return false;
        },
        if (sdl3) c.SDL_EVENT_DROP_FILE else c.SDL_DROPFILE => {
            if (self.log_events) {
                log.debug("SDL event drop file: {s}\n", .{if (sdl3) event.drop.data else event.drop.file});
            }
            return false;
        },
        if (sdl3) c.SDL_EVENT_WINDOW_MOUSE_LEAVE else c.SDL_WINDOWEVENT_LEAVE => {
            if (self.log_events) {
                log.debug("SDL mouse leave window {}\n", .{event.window.windowID});
            }
            try win.addEventWindow(.{ .action = .leave });
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
    if (keymod == if (sdl3) c.SDL_KMOD_NONE else c.KMOD_NONE) return dvui.enums.Mod.none;

    var m: u16 = 0;
    if (keymod & (if (sdl3) c.SDL_KMOD_LSHIFT else c.KMOD_LSHIFT) > 0) m |= @intFromEnum(dvui.enums.Mod.lshift);
    if (keymod & (if (sdl3) c.SDL_KMOD_RSHIFT else c.KMOD_RSHIFT) > 0) m |= @intFromEnum(dvui.enums.Mod.rshift);
    if (keymod & (if (sdl3) c.SDL_KMOD_LCTRL else c.KMOD_LCTRL) > 0) m |= @intFromEnum(dvui.enums.Mod.lcontrol);
    if (keymod & (if (sdl3) c.SDL_KMOD_RCTRL else c.KMOD_RCTRL) > 0) m |= @intFromEnum(dvui.enums.Mod.rcontrol);
    if (keymod & (if (sdl3) c.SDL_KMOD_LALT else c.KMOD_LALT) > 0) m |= @intFromEnum(dvui.enums.Mod.lalt);
    if (keymod & (if (sdl3) c.SDL_KMOD_RALT else c.KMOD_RALT) > 0) m |= @intFromEnum(dvui.enums.Mod.ralt);
    if (keymod & (if (sdl3) c.SDL_KMOD_LGUI else c.KMOD_LGUI) > 0) m |= @intFromEnum(dvui.enums.Mod.lcommand);
    if (keymod & (if (sdl3) c.SDL_KMOD_RGUI else c.KMOD_RGUI) > 0) m |= @intFromEnum(dvui.enums.Mod.rcommand);

    return @as(dvui.enums.Mod, @enumFromInt(m));
}

pub fn SDL_keysym_to_dvui(keysym: i32) dvui.enums.Key {
    return switch (keysym) {
        if (sdl3) c.SDLK_A else c.SDLK_a => .a,
        if (sdl3) c.SDLK_B else c.SDLK_b => .b,
        if (sdl3) c.SDLK_C else c.SDLK_c => .c,
        if (sdl3) c.SDLK_D else c.SDLK_d => .d,
        if (sdl3) c.SDLK_E else c.SDLK_e => .e,
        if (sdl3) c.SDLK_F else c.SDLK_f => .f,
        if (sdl3) c.SDLK_G else c.SDLK_g => .g,
        if (sdl3) c.SDLK_H else c.SDLK_h => .h,
        if (sdl3) c.SDLK_I else c.SDLK_i => .i,
        if (sdl3) c.SDLK_J else c.SDLK_j => .j,
        if (sdl3) c.SDLK_K else c.SDLK_k => .k,
        if (sdl3) c.SDLK_L else c.SDLK_l => .l,
        if (sdl3) c.SDLK_M else c.SDLK_m => .m,
        if (sdl3) c.SDLK_N else c.SDLK_n => .n,
        if (sdl3) c.SDLK_O else c.SDLK_o => .o,
        if (sdl3) c.SDLK_P else c.SDLK_p => .p,
        if (sdl3) c.SDLK_Q else c.SDLK_q => .q,
        if (sdl3) c.SDLK_R else c.SDLK_r => .r,
        if (sdl3) c.SDLK_S else c.SDLK_s => .s,
        if (sdl3) c.SDLK_T else c.SDLK_t => .t,
        if (sdl3) c.SDLK_U else c.SDLK_u => .u,
        if (sdl3) c.SDLK_V else c.SDLK_v => .v,
        if (sdl3) c.SDLK_W else c.SDLK_w => .w,
        if (sdl3) c.SDLK_X else c.SDLK_x => .x,
        if (sdl3) c.SDLK_Y else c.SDLK_y => .y,
        if (sdl3) c.SDLK_Z else c.SDLK_z => .z,

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
        if (sdl3) c.SDLK_APOSTROPHE else c.SDLK_QUOTE => .apostrophe,
        c.SDLK_COMMA => .comma,
        c.SDLK_PERIOD => .period,
        c.SDLK_SLASH => .slash,
        if (sdl3) c.SDLK_GRAVE else c.SDLK_BACKQUOTE => .grave,

        else => blk: {
            log.debug("SDL_keysym_to_dvui unknown keysym {d}", .{keysym});
            break :blk .unknown;
        },
    };
}

fn SDL2GuessScale(environ_map: ?*std.process.Environ.Map, io: std.Io, win: *c.SDL_Window) f32 {
    // first try to inspect environment variables
    if (environ_map) |map| {
        const qt_str: ?[]const u8 = map.get("QT_SCALE_FACTOR");
        if (qt_str) |str| {
            const qt_scale = std.fmt.parseFloat(f32, str) catch 1.0;
            log.info("QT_SCALE_FACTOR is {d}, using that for initial content scale", .{qt_scale});
            return qt_scale;
        }

        const gdk_str: ?[]const u8 = map.get("GDK_SCALE");
        if (gdk_str) |str| {
            const gdk_scale = std.fmt.parseFloat(f32, str) catch 1.0;
            log.info("GDK_SCALE is {d}, using that for initial content scale", .{gdk_scale});
            return gdk_scale;
        }

        const qt_auto_str: ?[]const u8 = map.get("QT_AUTO_SCREEN_SCALE_FACTOR");
        if (qt_auto_str != null and std.mem.eql(u8, qt_auto_str.?, "0")) {
            log.info("QT_AUTO_SCREEN_SCALE_FACTOR is 0, disabling content scale guessing", .{});
            return 1.0;
        }
    }
    // env variables where not conclusive, guesssing from dpi
    var mdpi: ?f32 = null;

    // for X11, try to grab the output of xrdb -query
    //*customization: -color
    //Xft.dpi: 96
    //Xft.antialias: 1
    if (mdpi == null and builtin.os.tag == .linux) {
        var buff: [512]u8 = undefined;
        var fballoc = std.heap.FixedBufferAllocator.init(&buff);
        const result: ?std.process.RunResult = std.process.run(fballoc.allocator(), io, .{
            .argv = &.{ "xrdb", "-get", "Xft.dpi" },
        }) catch null;
        if (result) |r| {
            const end_digits = std.mem.findNone(u8, r.stdout, &.{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }) orelse r.stdout.len;
            const xrdb_dpi = std.fmt.parseInt(u32, r.stdout[0..end_digits], 10) catch null;
            if (xrdb_dpi) |dpi| {
                mdpi = @floatFromInt(dpi);
            }

            if (mdpi) |dpi| {
                log.info("dpi {d} from xrdb -get Xft.dpi", .{dpi});
            }
        } else log.warn("failed to run `xrdb` for dpi guessing", .{});
    }

    // This doesn't seem to be helping anybody and sometimes hurts,
    // so we'll try disabling it outside of windows for now.
    if (mdpi == null and builtin.os.tag == .windows) {
        // see if we can guess correctly based on the dpi from SDL2
        const display_num = c.SDL_GetWindowDisplayIndex(win);
        if (display_num < 0) logErr("SDL_GetWindowDisplayIndex in SDL2GuessScale") catch return 1.0;
        var hdpi: f32 = undefined;
        var vdpi: f32 = undefined;
        toErr(c.SDL_GetDisplayDPI(display_num, null, &hdpi, &vdpi), "SDL_GetDisplayDPI in SDL2GuessScale") catch return 1.0;
        mdpi = @max(hdpi, vdpi);
        log.info("dpi {d} from SDL_GetDisplayDPI\n", .{mdpi.?});
    }

    if (mdpi) |dpi| {
        const scale_computed: f32 = blk: {
            if (builtin.os.tag == .windows) {
                // Windows DPIs come in 25% increments, and sometimes SDL2
                // reports something slightly off, which feels a bit blurry.
                break :blk @round((dpi / 100.0) / 0.25) * 0.25;
            } else {
                // Other platforms get integer scaling until someone
                // figures out how to make it better
                if (dpi > 200) {
                    break :blk 4.0;
                } else if (dpi > 100) {
                    break :blk 2.0;
                }
                break :blk 1.0;
            }
        };
        log.info("guessing initial backend scale {d} from dpi {d}", .{ scale_computed, dpi });
        return scale_computed;
    }
    return 1.0;
}

fn getWindowFromEvent(event: *c.SDL_Event) ?*c.SDL_Window {
    if (sdl3) return c.SDL_GetWindowFromEvent(event) else return c.SDL_GetWindowFromID(
        switch (event.type) {
            c.SDL_KEYDOWN, c.SDL_KEYUP, c.SDL_TEXTEDITING, c.SDL_TEXTINPUT, c.SDL_KEYMAPCHANGED => event.key.windowID,
            c.SDL_MOUSEMOTION => event.wheel.windowID,
            c.SDL_MOUSEBUTTONDOWN, c.SDL_MOUSEBUTTONUP => event.button.windowID,
            c.SDL_MOUSEWHEEL => event.wheel.windowID,
            c.SDL_WINDOWEVENT => event.window.windowID,
            // Not windowID field, we just return null so it's handled by "primary" window
            c.SDL_QUIT, c.SDL_DISPLAYEVENT => 0,
            else => blk: {
                log.info("SDL2 event type {any} unknown, will deliver to primary window", .{event.type});
                break :blk 0;
            },
        },
    );
}

pub fn getSDLVersion() std.SemanticVersion {
    if (sdl3) {
        const v: u32 = @bitCast(c.SDL_GetVersion());
        return .{
            .major = @divTrunc(v, 1000000),
            .minor = @mod(@divTrunc(v, 1000), 1000),
            .patch = @mod(v, 1000),
        };
    } else {
        var v: c.SDL_version = .{};
        c.SDL_GetVersion(&v);
        return .{
            .major = @intCast(v.major),
            .minor = @intCast(v.minor),
            .patch = @intCast(v.patch),
        };
    }
}

fn sdlLogCallbackCommon(category: c_int, priority: c_int, message: [*c]const u8) void {
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
        c.SDL_LOG_CATEGORY_TEST + 1...c.SDL_LOG_CATEGORY_CUSTOM - 1 => if (sdl3 and category == c.SDL_LOG_CATEGORY_GPU)
            sdlLog(.SDL_GPU, priority, message)
        else
            sdlLog(.SDL_RESERVED, priority, message),
        // starting from c.SDL_LOG_CATEGORY_CUSTOM any greater values are all custom categories
        else => sdlLog(.SDL_CUSTOM, priority, message),
    }
}

// `SDL_LogOutputFunction`'s priority parameter is `c_int` in some translate-c outputs and `c_uint`
// in others — varies by SDL major version and platform (e.g. SDL2 on Linux is `c_uint`, SDL3 on
// windows-msvc is `c_int`). Derive the parameter type from the actual cimport type so the callback
// signature matches whatever translate-c emitted for this target/version.
const SdlLogPriorityType = blk: {
    const Opt = @typeInfo(c.SDL_LogOutputFunction);
    const FnPtr = if (Opt == .optional) @typeInfo(Opt.optional.child) else Opt;
    const FnT = @typeInfo(FnPtr.pointer.child).@"fn";
    break :blk FnT.params[2].type.?;
};

fn sdlLogCallback(userdata: ?*anyopaque, category: c_int, priority: SdlLogPriorityType, message: [*c]const u8) callconv(.c) void {
    _ = userdata;
    sdlLogCallbackCommon(category, @intCast(priority), message);
}

fn sdlLog(comptime category: @EnumLiteral(), priority: c_int, message: [*c]const u8) void {
    const logger = std.log.scoped(category);
    switch (priority) {
        c.SDL_LOG_PRIORITY_VERBOSE => logger.debug("VERBOSE: {s}", .{message}),
        c.SDL_LOG_PRIORITY_DEBUG => logger.debug("{s}", .{message}),
        c.SDL_LOG_PRIORITY_INFO => logger.info("{s}", .{message}),
        c.SDL_LOG_PRIORITY_WARN => logger.warn("{s}", .{message}),
        c.SDL_LOG_PRIORITY_ERROR => logger.err("{s}", .{message}),
        c.SDL_LOG_PRIORITY_CRITICAL => logger.err("CRITICAL: {s}", .{message}),
        else => if (sdl3 and priority == c.SDL_LOG_PRIORITY_TRACE)
            logger.debug("TRACE: {s}", .{message})
        else
            logger.err("UNKNOWN: {s}", .{message}),
    }
}

/// This set enables the internal logging of SDL based on the level of std.log (and the SDL_... scopes)
pub fn enableSDLLogging() void {
    if (sdl3) {
        c.SDL_SetLogOutputFunction(&sdlLogCallback, null);
    } else {
        c.SDL_LogSetOutputFunction(&sdlLogCallback, null);
    }
    // Set default log level
    const default_log_level: c.SDL_LogPriority = if (std.log.logEnabled(.debug, .SDLBackend))
        c.SDL_LOG_PRIORITY_VERBOSE
    else if (std.log.logEnabled(.info, .SDLBackend))
        c.SDL_LOG_PRIORITY_INFO
    else if (std.log.logEnabled(.warn, .SDLBackend))
        c.SDL_LOG_PRIORITY_WARN
    else
        c.SDL_LOG_PRIORITY_ERROR;
    if (sdl3) c.SDL_SetLogPriorities(default_log_level) else c.SDL_LogSetAllPriority(default_log_level);

    const categories = [_]struct { c_uint, @EnumLiteral() }{
        .{ c.SDL_LOG_CATEGORY_APPLICATION, .SDL_APPLICATION },
        .{ c.SDL_LOG_CATEGORY_ERROR, .SDL_ERROR },
        .{ c.SDL_LOG_CATEGORY_ASSERT, .SDL_ASSERT },
        .{ c.SDL_LOG_CATEGORY_SYSTEM, .SDL_SYSTEM },
        .{ c.SDL_LOG_CATEGORY_AUDIO, .SDL_AUDIO },
        .{ c.SDL_LOG_CATEGORY_VIDEO, .SDL_VIDEO },
        .{ c.SDL_LOG_CATEGORY_RENDER, .SDL_RENDER },
        .{ c.SDL_LOG_CATEGORY_INPUT, .SDL_INPUT },
        .{ c.SDL_LOG_CATEGORY_TEST, .SDL_TEST },
    } ++ (if (!sdl3) .{} else .{
        .{ c.SDL_LOG_CATEGORY_GPU, .SDL_GPU },
    });
    inline for (categories) |category_data| {
        const category, const scope = category_data;
        inline for (std.options.log_scope_levels) |scope_level| {
            if (scope_level.scope == scope) {
                const log_level: c.SDL_LogPriority = switch (scope_level.level) {
                    .debug => c.SDL_LOG_PRIORITY_VERBOSE,
                    .info => c.SDL_LOG_PRIORITY_INFO,
                    .warn => c.SDL_LOG_PRIORITY_WARN,
                    .err => c.SDL_LOG_PRIORITY_ERROR,
                };
                if (sdl3) c.SDL_SetLogPriority(category, log_level) else c.SDL_LogSetPriority(category, log_level);
                break;
            }
        }
    }
}

/// This is what is run if you are using `dvui.App` with this backend.
pub fn main(main_init: std.process.Init) !u8 {
    dvui.App.main_init = main_init;
    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;

    // You can override these by calling this function with your arguments in dvui.App.config.startFn
    if (sdl3)
        _ = c.SDL_SetAppMetadata("DVUI App Example", "0.1", "com.example.dvui.app");

    if (builtin.os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }
    enableSDLLogging();

    if (sdl3 and (sdl_options.callbacks orelse true) and (builtin.target.os.tag == .macos or builtin.target.os.tag == .windows)) {
        // We are using sdl's callbacks to support rendering during OS resizing

        const init_opts = app.config.get();

        appState.gpa = init_opts.gpa orelse main_init.gpa;
        appState.io = init_opts.io orelse main_init.io;

        // For programs that provide their own entry points instead of relying on SDL's main function
        // macro magic, 'SDL_SetMainReady()' should be called before calling 'SDL_Init()'.
        c.SDL_SetMainReady();

        // This is more or less what 'SDL_main.h' does behind the curtains.
        const status = c.SDL_EnterAppMainCallbacks(0, null, appInit, appIterate, appEvent, appQuit);

        return @bitCast(@as(i8, @truncate(status)));
    }

    log.info("version: {f} no callbacks", .{getSDLVersion()});

    const init_opts = app.config.get();

    // init SDL backend (creates and owns OS window)
    var back = try initWindow(.{
        .io = init_opts.io orelse main_init.io,
        .environ_map = main_init.environ_map,
        .size = init_opts.size,
        .min_size = init_opts.min_size,
        .max_size = init_opts.max_size,
        .vsync = init_opts.vsync,
        .title = init_opts.title,
        .org = init_opts.org,
        .icon = init_opts.icon,
        .hidden = init_opts.hidden,
        .transparent = init_opts.transparent,
        .persist_window_geometry = init_opts.persist_window_geometry,
        .pref_path = init_opts.pref_path,
    });
    defer back.deinit();

    if (sdl3) {
        toErr(c.SDL_EnableScreenSaver(), "SDL_EnableScreenSaver in sdl main") catch {};
    } else {
        c.SDL_EnableScreenSaver();
    }

    //// init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), main_init.gpa, back.backend(), init_opts.window_init_options);
    defer win.deinit();

    if (init_opts.window_init_options.open_flag != null)
        dvui.log.warn("`open_flag` option has no effect in dvui App. It is managed internally in that case.", .{});
    var window_open = true;
    win.open_flag = &window_open;

    if (app.initFn) |initFn| {
        try win.begin(win.frame_time_ns);
        try initFn(&win);
        _ = try win.end(.{});
    }
    defer if (app.deinitFn) |deinitFn| deinitFn();

    var interrupted = false;

    main_loop: while (window_open) {
        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(interrupted);

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        try back.addAllEvents(&win);

        const res = try app.frameFn();

        const end_micros = try win.end(.{});

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
    gpa: std.mem.Allocator,
    io: std.Io,
    window_open: bool = true,
    interrupted: bool = false,
    have_resize: bool = false,
    no_wait: bool = false,
};

/// used when doing sdl callbacks
var appState: CallbackState = .{ .win = undefined, .back = undefined, .gpa = undefined, .io = undefined };

// sdl3 callback
fn appInit(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    _ = appstate;
    _ = argc;
    _ = argv;
    //_ = c.SDL_SetAppMetadata("dvui-demo", "0.1", "com.example.dvui-demo");

    const app = dvui.App.get() orelse return error.DvuiAppNotDefined;

    log.info("version: {f} callbacks", .{getSDLVersion()});

    const init_opts = app.config.get();

    // init SDL backend (creates and owns OS window)
    appState.back = initWindow(.{
        .io = appState.io,
        .size = init_opts.size,
        .min_size = init_opts.min_size,
        .max_size = init_opts.max_size,
        .vsync = init_opts.vsync,
        .title = init_opts.title,
        .org = init_opts.org,
        .icon = init_opts.icon,
        .hidden = init_opts.hidden,
        .transparent = init_opts.transparent,
        .persist_window_geometry = init_opts.persist_window_geometry,
        .pref_path = init_opts.pref_path,
    }) catch |err| {
        log.err("initWindow failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    if (sdl3) {
        toErr(c.SDL_EnableScreenSaver(), "SDL_EnableScreenSaver in sdl main") catch {};
    } else {
        c.SDL_EnableScreenSaver();
    }

    //// init dvui Window (maps onto a single OS window)
    appState.win = dvui.Window.init(@src(), appState.gpa, appState.back.backend(), init_opts.window_init_options) catch |err| {
        log.err("dvui.Window.init failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };
    appState.window_open = true;
    if (init_opts.window_init_options.open_flag != null)
        dvui.log.warn("`open_flag` option has no effect in dvui App. It is managed internally in that case.", .{});
    appState.win.open_flag = &appState.window_open;

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

    const e = &event.?.*;
    const target_sdl_window = getWindowFromEvent(e);
    if (target_sdl_window) |target_win| {
        _ = appState.back.addEventWinRecursive(e, &appState.win, target_win) catch |err| {
            log.err("dvui.Window.addEvent failed: {any}", .{err});
            return c.SDL_APP_FAILURE;
        };
    } else {
        _ = appState.back.addEvent(&appState.win, e.*) catch |err| {
            log.err("dvui.Window.addEvent failed: {any}", .{err});
            return c.SDL_APP_FAILURE;
        };
    }

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

    const app = dvui.App.get() orelse unreachable;
    var res = app.frameFn() catch |err| {
        log.err("dvui.App.frameFn failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    const end_micros = appState.win.end(.{ .manage_backend = false }) catch |err| {
        log.err("dvui.Window.end failed: {any}", .{err});
        return c.SDL_APP_FAILURE;
    };

    // check if window got quit/close event
    if (!appState.window_open) res = .close;

    appState.back.setCursor(appState.win.cursorRequested());
    appState.back.textInputRect(appState.win.textInputRequested());
    appState.back.renderPresent();

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

test {
    //std.debug.print("{s} backend test\n", .{if (sdl3) "SDL3" else "SDL2"});
    std.testing.refAllDecls(@This());
}
