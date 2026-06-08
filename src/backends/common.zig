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
    if (res == std.os.windows.BOOL.FALSE) return error.CouldNotAttachConsole;
}

/// Gets the preferred color scheme from the Windows registry
pub fn windowsGetPreferredColorScheme() ?dvui.enums.ColorScheme {
    const winapi = struct {
        pub extern "advapi32" fn RegGetValueW(
            hkey: std.os.windows.HKEY,
            lpSubKey: std.os.windows.LPCWSTR,
            lpValue: std.os.windows.LPCWSTR,
            dwFlags: std.os.windows.DWORD,
            pdwType: ?*std.os.windows.DWORD,
            pvData: ?*anyopaque,
            pcbData: ?*std.os.windows.DWORD,
        ) callconv(.winapi) std.os.windows.LSTATUS;
    };

    var out: [4]u8 = undefined;
    var len: u32 = 4;
    const res = winapi.RegGetValueW(
        std.os.windows.HKEY_CURRENT_USER,
        std.unicode.utf8ToUtf16LeStringLiteral("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
        std.unicode.utf8ToUtf16LeStringLiteral("AppsUseLightTheme"),
        0x10, //advapi32.RRF.RT_REG_DWORD,
        null,
        &out,
        &len,
    );
    if (res != 0) return null;

    const val = std.mem.littleToNative(i32, @bitCast(out));
    return if (val > 0) .light else .dark;
}

/// Helper for backends to warn user in case the "manage_backends" functions get
/// called multiple time. Useful now that `dvui.Window.end()` does it by default.
pub const TrackManageBackend = struct {
    has_renderPresent: bool = false,
    has_setCursor: bool = false,
    has_textInputRect: bool = false,
    pub const Which = enum { renderPresent, setCursor, textInputRect };
    pub fn reset_begin(self: *@This()) void {
        self.* = .{}; // everybody to false
    }
    pub fn check(self: *@This(), which: Which) void {
        switch (which) {
            .renderPresent => {
                if (self.has_renderPresent) warnDoubleCall(which);
                self.has_renderPresent = true;
            },
            .setCursor => {
                if (self.has_setCursor) warnDoubleCall(which);
                self.has_setCursor = true;
            },
            .textInputRect => {
                if (self.has_textInputRect) warnDoubleCall(which);
                self.has_textInputRect = true;
            },
        }
    }
    fn warnDoubleCall(which: Which) void {
        dvui.log.warn("backend.{t} has already been called once in this frame. `dvui.Window.end(.{{}})` is now doing it by default, pass `.manage_backend = false` if needed.", .{which});
    }
};
