//! This is a file with common implementiations that are used by
//! multiple backends.

const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("../dvui.zig");

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

/// Gets the preferred color scheme from the Windows registry
pub fn windowsGetPreferredColorScheme() ?dvui.enums.ColorScheme {
    var out: [4]u8 = undefined;
    var len: u32 = 4;
    const res = std.os.windows.advapi32.RegGetValueW(
        std.os.windows.HKEY_CURRENT_USER,
        std.unicode.utf8ToUtf16LeStringLiteral("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
        std.unicode.utf8ToUtf16LeStringLiteral("AppsUseLightTheme"),
        std.os.windows.advapi32.RRF.RT_REG_DWORD,
        null,
        &out,
        &len,
    );
    if (res != 0) return null;

    const val = std.mem.littleToNative(i32, @bitCast(out));
    return if (val > 0) .light else .dark;
}
