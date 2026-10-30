//! Spawn a new OS Window
//!
//! If not supported by the backend, a `dvui.FloatingWindowWidget` will be used as fallback.
//!
//! This is not technically a widget (it doesn't conform to the interface) but is
//! essentially a wrapping container around a heap allocated backend/dvui.Window, or around a FloatingWindowWidget in the fallback case.
//!
//! See `dvui.osWindow` and `dvui.popWindow`

const OsWindowWidget = @This();

inner: union(BackingImpl) { os: *ChildOsWindow, floating: *FloatingWindowWidget },

pub const BackingImpl = enum { os, floating };

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
        os_window_count -= 1;
    }
};

/// Wrapper of TrackingAutoHashMap that is zero bytes if backend doesn't support child windows
pub const ChildTrackMap = if (Backend.support_child_os_wins)
    dvui.TrackingAutoHashMap(dvui.Id, dvui.OsWindowWidget.ChildOsWindow, .get_and_put, void)
else
    VoidTrackMap;

pub const VoidTrackMap = struct {
    pub const empty: VoidTrackMap = .{};
    pub fn reset(_: VoidTrackMap) void {}
    pub const VoidIterator = struct {
        pub fn next_resetting(_: VoidIterator) @TypeOf(null) {
            return null;
        }
        pub fn next(_: VoidIterator) @TypeOf(null) {
            return null;
        }
    };
    pub fn iterator(_: VoidTrackMap) VoidIterator {
        return .{};
    }
    pub fn deinit(_: VoidTrackMap, _: anytype) void {}
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
    // FIXME : this doesn't seem to work as expected
    // Because it does not override the remembered geometry...
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
    switch (self.inner) {
        .os => |os| {
            os.end_micros = os.dvui_win.end(.{}) catch unreachable;
        },
        .floating => |float| float.deinit(),
    }
}

/// Access the inner's WidgetData
pub fn data(self: OsWindowWidget) *dvui.WidgetData {
    switch (self.inner) {
        .os => |os| return os.dvui_win.data(),
        .floating => |float| return float.data(),
    }
}

/// Actual Os Window implementation.
///
/// Gives back an empty os window you can draw normally on until calling `deinit`.
///
/// Retuns OsWindowFailed on error paths where floating window fallback might still work.
pub fn osWindowImpl(
    src: std.builtin.SourceLocation,
    os_win_opts: OsWindowWidget.InitOptions,
    dvui_win_opts: Window.InitOptions,
) error{OsWindowFailed}!OsWindowWidget {
    if (!Backend.support_child_os_wins) return error.OsWindowFailed;
    const cw = dvui.currentWindow();
    // FIXME : I have a discrepency here, WidgetData compute hash with
    // const parent = dvui.parentGet();
    // const id = parent.extendId(src, opts.idExtra()); <-
    // Not sure yet if this has any negative consequencies.
    const hashval = cw.data().id.extendId(src, dvui_win_opts.id_extra);
    const win_maybe = cw.child_os_wins.getOrPut(cw.gpa, hashval) catch @panic("OOM");
    // Don't leave the entry on error path or we gonna call illegal stuff in window.end()
    errdefer _ = cw.child_os_wins.remove(hashval);

    const os_win: *ChildOsWindow = if (win_maybe.found_existing)
        win_maybe.value_ptr
    else new_os_win: {
        if (tooManyWindows()) {
            return error.OsWindowFailed;
        }
        errdefer os_window_count -= 1;
        const new_backend = cw.gpa.create(dvui.backend) catch @panic("OOM");
        errdefer cw.gpa.destroy(new_backend);
        new_backend.* = cw.backend.impl.initWindowSecondary(hashval, os_win_opts) catch |err| {
            dvui.log.warn("osWindow : initWindowSecondary failed : {}", .{err});
            return error.OsWindowFailed;
        };

        const new_dvui_win = cw.gpa.create(dvui.Window) catch @panic("OOM");
        errdefer cw.gpa.destroy(new_dvui_win);
        new_dvui_win.* = dvui.Window.init(src, cw.gpa, new_backend.backend(), .{
            .id_extra = dvui_win_opts.id_extra,
            .theme = dvui_win_opts.theme orelse cw.theme,
            .button_order = dvui_win_opts.button_order orelse cw.button_order,
            // Do not grab the parent's one, because closing a child window is not the same as
            // quitting the application. User should explicitly use the same open_flag for this behavior.
            .open_flag = dvui_win_opts.open_flag,
        }) catch |err| {
            dvui.log.warn("osWindow : dvui.Window.init failed : {}", .{err});
            return error.OsWindowFailed;
        };
        new_dvui_win.is_primary = false;
        win_maybe.value_ptr.* = .{ .backend = new_backend, .dvui_win = new_dvui_win };
        break :new_os_win win_maybe.value_ptr;
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
    return .{ .inner = .{ .os = os_win } };
}

/// Floating window fallback.
///
/// Just a floatingWindow wrapped inside an `OsWindowWidget`.
pub fn osWindowFloatImpl(
    src: std.builtin.SourceLocation,
    float_opts: dvui.FloatingWindowWidget.InitOptions,
    opts: dvui.Options,
) OsWindowWidget {

    // FIXME : deal with size / rect
    // FIXME : should os_win_opts.hidden be mapped to something in float ?

    const float = dvui.floatingWindow(src, float_opts, opts);

    return .{ .inner = .{ .floating = float } };
}

/// Quasi copy of `dvui.windowHeader` but with an extra popup button next to the optional "right_srt".
/// `popflag` is set to `true` when the button is clicked.
pub fn popWindowHeader(str: []const u8, right_str: []const u8, popflag: *bool, openflag: ?*bool) Rect.Physical {
    if (!Backend.support_child_os_wins)
        return dvui.windowHeader(str, right_str, openflag);

    var over = dvui.overlay(@src(), .{ .expand = .horizontal, .name = "WindowHeader" });
    const bo = dvui.currentWindow().button_order;

    const align_x: f32 = if (bo == .ok_cancel) 0.0 else 0.5;
    dvui.labelNoFmt(@src(), str, .{ .align_x = align_x }, .{
        .expand = .horizontal,
        .font = .theme(.heading),
        .padding = .{ .x = 6, .y = 6, .w = 6, .h = 4 },
        .label = .{ .for_id = dvui.subwindowCurrentId() },
    });

    var hbox: ?*BoxWidget = null;
    if (bo == .ok_cancel) hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 1.0 });

    if (openflag) |of| {
        const opts: Options = .{
            .font = .theme(.heading),
            .corners = .all(1000),
            .padding = Rect.all(2),
            .margin = Rect.all(2),
            .gravity_y = 0.5,
            .expand = .ratio,
            .gravity_x = if (bo == .ok_cancel) 1.0 else 0.0,
        };
        if (dvui.buttonIcon(@src(), "close", entypo.cross, .{}, .{}, opts)) {
            of.* = false;
        }
    }

    const right_bo = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = if (bo == .ok_cancel) 0.0 else 1.0 });
    dvui.labelNoFmt(@src(), right_str, .{}, .{});
    if (dvui.buttonIcon(@src(), "pop window out", entypo.popup, .{}, .{}, .{})) {
        popflag.* = true;
    }

    right_bo.deinit();

    if (hbox) |hb| hb.deinit();

    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = over.data().id, .r = over.data().contentRectScale().r }))
            continue;

        if (e.evt == .mouse and e.evt.mouse.action == .press and e.evt.mouse.button.pointer()) {
            // raise this subwindow but let the press continue so the window
            // will do the drag-move
            dvui.raiseSubwindow(dvui.subwindowCurrentId());
        } else if (e.evt == .mouse and e.evt.mouse.action == .focus) {
            // our window will already be focused, but this prevents the window
            // from clearing the focused widget
            e.handle(@src(), over.data());
        }
    }

    var ret = over.data().rectScale().r;

    over.deinit();

    const swd = dvui.separator(@src(), .{ .expand = .horizontal });
    ret.h += swd.rectScale().r.h;

    return ret;
}

/// Allow maximum that much OS windows.
///
/// This prevent a small code error to turn into a Window Fork Bomb as it happend to
///  me a few times while developping the feature.
///
/// If you have a legit use case for more windows, you can change this.
///  See https://github.com/david-vanderson/dvui/issues/883
pub var max_os_windows: u32 = 5;
var os_window_count: u32 = 0;

// See `max_os_windows`
fn tooManyWindows() bool {
    if (os_window_count < max_os_windows) {
        os_window_count += 1;
        return false;
    }
    if (builtin.mode == .debug) {
        dvui.log.warn(
            \\Won't open more than {} OS window. Falling back to FloatingWindow.
            \\  This safety prevents windows fork bombs while hacking on multi os windows. 
            \\  You can change the allowed max with `dvui.OsWindowWidget.max_os_windows = X`;
        , .{max_os_windows});
    } else {
        dvui.log.info("Cannot spawn more than {} OS windows. Falling back to floating window", .{max_os_windows});
    }
    return true;
}

const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("../dvui.zig");

const Rect = dvui.Rect;
const BoxWidget = dvui.BoxWidget;
const Options = dvui.Options;
const entypo = dvui.entypo;

const Backend = dvui.Backend;
const Window = dvui.Window;
const FloatingWindowWidget = dvui.FloatingWindowWidget;
