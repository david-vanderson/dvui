//! For apps that want dvui to provide the mainloop which runs these callbacks.
//!
//! In your root file, have a declaration named "dvui_app" of this type:
//! ```
//! pub const dvui_app: dvui.App = .{ .initFn = AppInit, ...};
//! ```
//!
//! Also must use the App's main, panic and log functions:
//! ```
//! pub const main = dvui.App.main;
//! pub const panic = dvui.App.panic;
//! pub const std_options: std.Options = .{
//!     .logFn = dvui.App.logFn,
//! };
//! ```

pub const App = @This();

/// The configuration options for the app, either directly or a function that
/// is run at startup that returns the options.
config: AppConfig,
/// Runs before the first full frame, allowing for configuring the Window.
/// Window and Backend have run init() already.  Runs between `Window.begin`
/// and `Window.end`, so can access all of dvui functions.
initFn: ?fn (*dvui.Window) anyerror!void = null,
/// Runs when the app is exiting, before Window.deinit().
deinitFn: ?fn (*dvui.Window) void = null,
/// Runs once every frame between `Window.begin` and `Window.end`
///
/// Returns whether the app should continue running or close.
frameFn: frameFunction,

/// The init arg passed into main.  null if not available (like on web).
pub var main_init: ?std.process.Init = null;

pub const frameFunction = fn () anyerror!Result;

fn nop_main() !void {}
/// The root file needs to expose the App main function:
/// ```
/// pub const main = dvui.App.main;
/// ```
pub const main = if (@hasDecl(dvui.backend, "main")) dvui.backend.main else nop_main;

/// The root file needs to expose the App panic function:
/// ```
/// pub const panic = dvui.App.panic;
/// ```
pub const panic = if (@hasDecl(dvui.backend, "panic")) dvui.backend.panic else std.debug.FullPanic(std.debug.defaultPanic);

/// Some backends, like web, cannot use stdout and has a custom logFn to be used.
/// Dvui apps should always prefer to use std.log over stdout to work across all backends.
///
/// The root file needs to use the App logFn function:
/// ```
/// pub const std_options: std.Options = .{
///     .logFn = dvui.App.logFn,
/// };
/// ```
pub const logFn: @FieldType(std.Options, "logFn") = if (@hasDecl(dvui.backend, "logFn")) dvui.backend.logFn else std.log.defaultLog;

pub const AppConfig = union(enum) {
    options: StartOptions,
    /// Runs before anything else. Can be used to programmatically create the `StartOptions`
    startFn: *const fn () StartOptions,

    pub fn get(self: AppConfig) StartOptions {
        switch (self) {
            .options => |opts| return opts,
            .startFn => |startFn| return startFn(),
        }
    }
};

pub const StartOptions = struct {
    /// The initial size of the application window
    size: dvui.Size,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    vsync: bool = true,
    /// Organization name for the app.
    /// Used for things like SDL preference path. (when `pref_path` is null)
    /// Must be static for the application lifetime.
    org: [:0]const u8,
    /// Name of the app.
    /// Used for things like SDL preference path. (when `pref_path` is null)
    /// Must be static for the application lifetime.
    app: [:0]const u8,
    /// Title that identify the OS window (typically displayed on window bar)
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[]const u8 = null,
    /// use when running tests
    hidden: bool = false,
    /// Set the window to be transparent
    transparent: bool = false,
    /// Automatically restore the window position and size from the previous
    /// run and save them at exit (currently SDL only).
    /// The geometry is stored as `windows_geometry.zon` file.
    /// See `pref_path`.
    persist_window_geometry: bool = true,
    /// Optional folder for app preferences, including `windows_geometry.zon`
    /// See `persist_window_geometry`.
    /// When null, the SDL backend uses `SDL_GetPrefPath(org, app)`.
    pref_path: ?[:0]const u8 = null,
    /// Will be passed to `dvui.Window.init`
    ///
    /// Options like `keybinds` should be used with care as it will
    /// be used for all backends and platforms, meaning the platform
    /// defaults will be overrulled.
    window_init_options: dvui.Window.InitOptions = .{ .keybinds_zoom = true },
    /// General purpose allocator.  If null, dvui picks a reasonable default.
    /// Use dvui.App.config.startFn to initialize this non-statically
    gpa: ?std.mem.Allocator = null,
    /// Io implementation.  If null, dvui picks a reasonable default.
    /// Use dvui.App.config.startFn to initialize this non-statically
    io: ?std.Io = null,
};

pub const Result = enum {
    /// App should continue
    ok,
    /// App should close and exit
    close,
};

/// Used internally to get the dvui_app if it's defined
pub fn get() ?App {
    const root = @import("root");
    // return error instead of failing compile to allow for reference in tests without dvui_app defined
    if (!@hasDecl(root, "dvui_app")) return null;

    if (!@hasDecl(root, "main")) {
        @compileError(
            \\Using the App interface requires using the App main function
            \\
            \\Add the following line to your root file:
            \\pub const main = dvui.App.main;
        );
    }

    return root.dvui_app;
}

const std = @import("std");
const dvui = @import("dvui.zig");

test {
    std.testing.refAllDecls(@This());
}
