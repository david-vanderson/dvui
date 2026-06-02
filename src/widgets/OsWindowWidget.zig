//! Spawn a new OS Window
//!
//! If not supported by the backend, a `dvui.FloatingWindowWidget` will be used as fallback.
//!
//! This is not technically a widget (it doesn't conform to the interface) but is
//! essentially a wrapping container around a heap allocated backend/dvui.Window, or around a FloatingWindowWidget in the fallback case.
//!
//! See `dvui.osWindow`

const OsWindowWidget = @This();

inner: if (Backend.support_child_os_wins)
    *ChildOsWindow
else
    *FloatingWindowWidget,

/// Thin wrapper allowing to heap allocate a new os window.
pub const ChildOsWindow = struct {
    backend: *dvui.backend,
    dvui_win: *dvui.Window,
    end_micros: ?u32 = null,

    // debug : allows to detect duplicate window
    has_begin: bool = false,

    pub fn deinit(self: ChildOsWindow, alloc: std.mem.Allocator) void {
        self.backend.deinit();
        self.dvui_win.deinit();
        alloc.destroy(self.backend);
        alloc.destroy(self.dvui_win);
    }
};

/// User options for a new os window. See `dvui.osWindow`
///
/// Note that each backend is free to maintain some global state and
/// is responsible to interpret these options and the resulting effect may vary.
///
/// Fields that are left to `null` will be grab from parent window where possible.
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

    fullscreen: bool = false,
    hidden: bool = false,
};

/// Close the child Os Window context, effectively rendering it.
pub fn deinit(self: OsWindowWidget) void {
    if (Backend.support_child_os_wins)
        self.inner.end_micros = self.inner.dvui_win.end(.{}) catch unreachable
    else
        self.inner.deinit();
}

pub fn osWindowImpl(src: std.builtin.SourceLocation, child_win_opts: OsWindowWidget.InitOptions, win_opts: Window.InitOptions) OsWindowWidget {
    const cw = dvui.currentWindow();
    const hashval = cw.data().id.extendId(src, win_opts.id_extra);
    const win_maybe = cw.child_os_wins.getOrPut(cw.gpa, hashval) catch @panic("OOM");
    const os_win: *ChildOsWindow = if (win_maybe.found_existing)
        win_maybe.value_ptr
    else blk: {
        const new_backend = cw.gpa.create(dvui.backend) catch @panic("OOM");
        new_backend.* = cw.backend.impl.initWindowSecondary(child_win_opts) catch @panic("Failed to initialize new backend");

        // this is just for easy debug but would be nice to have a nudge strategy where possible.
        // But this as a whole other can of worms. Don't even know if this is possible on wayland for instance.
        _ = dvui.backend.c.SDL_SetWindowPosition(new_backend.window, 850, 150);

        const new_dvui_win = cw.gpa.create(dvui.Window) catch @panic("OOM");
        new_dvui_win.* = dvui.Window.init(src, cw.gpa, new_backend.backend(), .{
            .id_extra = win_opts.id_extra,
            .theme = win_opts.theme orelse cw.theme,
            .button_order = win_opts.button_order orelse cw.button_order,
            // Do not grab the parent's one, because closing a child window is not the same as
            // quitting the application. User should explicitly use the same open_flag for this behavior.
            .open_flag = win_opts.open_flag,
        }) catch
            @panic("Failed to initialize new dvui.Window");
        new_dvui_win.is_primary = false;
        win_maybe.value_ptr.* = .{ .backend = new_backend, .dvui_win = new_dvui_win };
        break :blk win_maybe.value_ptr;
    };
    std.debug.assert(os_win.dvui_win.data().id == hashval);
    os_win.dvui_win.begin(cw.frame_time_ns) catch |err| {
        dvui.logError(@src(), err, "Something wrong in child's dvui.Window.begin()", .{});
    };
    if (os_win.has_begin) {
        dvui.log.err("duplicate os Window. id {f} (highlighted in red); you may need to pass .{{.id_extra=<loop index>}} as widget options (see https://github.com/david-vanderson/dvui/blob/master/readme-implementation.md#widget-ids )", .{hashval});
        dvui.Debug.errorOutline(os_win.dvui_win.rectScale().r);
    }
    os_win.has_begin = true;
    return .{ .inner = os_win };
}

pub fn osWindowFallback(src: std.builtin.SourceLocation, child_win_opts: OsWindowWidget.InitOptions) OsWindowWidget {
    const float = dvui.floatingWindow(src, .{}, .{
        // TODO : review which os_win_opts make sense to "forward"
    });
    // TODO : deal with close flag somehow. osWindowFallback should have a close button, because an OS window do
    float.dragAreaSet(dvui.windowHeader(child_win_opts.title orelse "Dvui child window", "", null));
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
