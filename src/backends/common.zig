//! This is a file with common implementiations that are used by
//! multiple backends.

const std = @import("std");

/// On Windows graphical apps have no console, so output goes to nowhere.
/// This functions attached the console manually.
///
/// Related: https://github.com/ziglang/zig/issues/4196
pub fn windowsAttachConsole() !void {
    const winapi = struct {
        extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
    };

    const ATTACH_PARENT_PROCESS: std.os.windows.DWORD = 0xFFFFFFFF; //DWORD(-1)
    const res = winapi.AttachConsole(ATTACH_PARENT_PROCESS);
    if (res == std.os.windows.FALSE) return error.CouldNotAttachConsole;
}
