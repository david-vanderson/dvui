//! Spawn a new OS Window
//!
//! If not supported by the backend, a `dvui.FloatingWindowWidget` will be used as fallback.
//!
//! This is not technically a widget (it doesn't conform to the interface) but is
//! essentially a wrapping container around a heap allocated backend/dvui.Window, or around a FloatingWindowWidget in the fallback case.
//!
//! See `dvui.osWindow`

const OsWindowWidget = @This();

inner: if (Backend.support_multi_os_wins)
    *ChildOsWindow
else
    *FloatingWindowWidget,

/// Thin wrapper allowing to heap allocate a new os window.
pub const ChildOsWindow = struct {
    backend: *dvui.backend,
    dvui_win: *dvui.Window,
    end_micros: ?u32 = null,
};

/// User options for a new os window. See `dvui.osWindow`
///
/// Very similar to `dvui.Backend.InitWindowOptions` but provides defaults for convenience,
/// and doesn't contains fields that dvui can reasonnably grab from previous instances, like gpa/io ...
///
/// Fields that are left to `null` will be grab from parent window where applicable.
pub const InitOptions = struct {
    /// Usually displayed on the top of the window.
    title: ?[:0]const u8 = null,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
    /// Initial size of the os window.
    size: ?dvui.Size = null,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    hidden: ?bool = null,
    transparent: ?bool = null,

    fullscreen: bool = false,
    vsync: bool = true,
};

/// Close the child Os Window context, effectively rendering it.
pub fn deinit(self: OsWindowWidget) void {
    if (Backend.support_multi_os_wins)
        self.inner.end_micros = self.inner.dvui_win.end(.{}) catch unreachable
    else
        self.inner.deinit();
}

pub fn osWindowImpl(src: std.builtin.SourceLocation, os_win_opts: OsWindowWidget.InitOptions, win_opts: Window.InitOptions) OsWindowWidget {
    const hashval = dvui.Id.extendId(null, src, win_opts.id_extra);
    const cw = dvui.currentWindow();
    const win_maybe = cw.child_os_wins.getOrPut(cw.gpa, hashval) catch @panic("OOM");
    const os_win: *ChildOsWindow = if (win_maybe.found_existing)
        win_maybe.value_ptr
    else blk: {
        const new_backend = cw.gpa.create(dvui.backend) catch @panic("OOM");
        const parent_win_opts: Backend.InitWindowOptions = cw.backend.impl.initwindow_opts orelse opts: {
            dvui.logError(src, error.BackendError, "Opening new OS window but the parent backend did not store `initwindow_opts`. `backend.initWindow` is supposed to do that.", .{});
            break :opts .{ .io = dvui.io, .allocator = cw.gpa, .size = .{ .w = 800, .h = 600 }, .title = "Dvui child window" };
        };
        new_backend.* = dvui.backend.initWindow(.{
            .global_init = false,
            .io = parent_win_opts.io,
            .allocator = parent_win_opts.allocator,
            .environ_map = parent_win_opts.environ_map,

            .title = os_win_opts.title orelse parent_win_opts.title,
            .size = os_win_opts.size orelse parent_win_opts.size,
            .icon = os_win_opts.icon orelse parent_win_opts.icon,
            .min_size = os_win_opts.min_size orelse parent_win_opts.min_size,
            .max_size = os_win_opts.max_size orelse parent_win_opts.max_size,
            .hidden = os_win_opts.hidden orelse parent_win_opts.hidden,
            .transparent = os_win_opts.transparent orelse parent_win_opts.transparent,
            .vsync = os_win_opts.vsync,
            .fullscreen = os_win_opts.fullscreen,
        }) catch @panic("Failed to initialize new backend");
        // this is just for easy debug but would be nice to have a nudge strategy where possible.
        // But this as a whole other can of worms. Don't even know if this is possible on wayland for instance.
        _ = dvui.backend.c.SDL_SetWindowPosition(new_backend.window, 850, 150);

        const new_dvui_win = cw.gpa.create(dvui.Window) catch @panic("OOM");
        new_dvui_win.* = dvui.Window.init(src, cw.gpa, new_backend.backend(), .{
            .theme = win_opts.theme orelse cw.theme,
            .button_order = win_opts.button_order orelse cw.button_order,
        }) catch
            @panic("Failed to initialize new dvui.Window");
        win_maybe.value_ptr.* = .{ .backend = new_backend, .dvui_win = new_dvui_win };
        break :blk win_maybe.value_ptr;
    };
    std.debug.assert(os_win.dvui_win.data().id == hashval);
    os_win.dvui_win.begin(cw.frame_time_ns) catch |err| {
        dvui.logError(@src(), err, "Something wrong in child's dvui.Window.begin()", .{});
    };
    return .{ .inner = os_win };
}

pub fn osWindowFallback(src: std.builtin.SourceLocation, os_win_opts: OsWindowWidget.InitOptions) OsWindowWidget {
    const float = dvui.floatingWindow(src, .{}, .{
        // TODO : review which os_win_opts make sense to "forward"
    });
    // TODO : deal with close flag somehow. osWindowFallback should have a close button, because an OS window do
    float.dragAreaSet(dvui.windowHeader(os_win_opts.title orelse "Dvui child window", "", null));
    // TODO : deal with Floating window inside the floating window.
    // something is wrong with rendering order, but maybe we want the floating win declared
    // inside an osWindow to not be able to exceed it's boundaries ? Or on the contrary it's nice
    // that they just become "sibling" floating window ?
    return .{ .inner = float };
}

const std = @import("std");
const dvui = @import("../dvui.zig");

const Backend = dvui.Backend;
const Window = dvui.Window;
const FloatingWindowWidget = dvui.FloatingWindowWidget;
