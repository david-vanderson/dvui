//! For apps that want dvui to provide the mainloop which runs these callbacks.
//!
//! In your root file, have a declaration named "dvui_app" of this type:
//! ```
//! pub const dvui_app: dvui.App = .{ .initFn = AppInit, ...};
//! ```
//!
//! Also must use the App's main and log functions:
//! ```
//! pub const main = dvui.App.main;
//! pub const std_options: std.Options = .{
//!     .logFn = dvui.App.logFn,
//! };
//! ```

/// Runs before anything else, returning the configuration options for the app
startFn: fn () StartOptions,
/// Runs before the first frame, allowing for configuring the Window
initFn: ?fn (*dvui.Window) void = null,
/// Runs when the app is exiting
deinitFn: ?fn () void = null,
/// Runs once every frame
///
/// Always runs between `Window.begin` and `Window.end`
frameFn: fn () Result,

fn nop_main() !void {}
/// The root file needs to expose the App main function:
/// ```
/// pub const main = dvui.App.main;
/// ```
pub const main: fn () anyerror!void = if (@hasDecl(dvui.backend, "main")) dvui.backend.main else nop_main;
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

pub const StartOptions = struct {
    /// The initial size of the application window
    size: dvui.Size,
    /// Set the minimum size of the window
    min_size: ?dvui.Size = null,
    /// Set the maximum size of the window
    max_size: ?dvui.Size = null,
    vsync: bool = true,
    /// The application title to display
    title: [:0]const u8,
    /// content of a PNG image (or any other format stb_image can load)
    /// tip: use @embedFile
    icon: ?[:0]const u8 = null,
};

pub const Result = enum {
    /// App should continue
    ok,
    /// App should close and exit
    close,
};

const std = @import("std");
const dvui = @import("dvui.zig");
