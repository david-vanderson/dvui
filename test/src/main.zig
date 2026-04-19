const std = @import("std");
const dvui = @import("dvui");

pub const dvui_app = dvui.App{ .config = .{ .options = .{
    .title = "foo",
    .size = .all(100),
    .vsync = true,
} }, .frameFn = frame, .initFn = init };
pub const main = dvui.App.main;

fn init(window: *dvui.Window) !void {
    _ = window;
    dvui.styleSchemeSet(.button, .{ .corner_radius = .all(20), .padding = .all(10) });
    dvui.themeSet(dvui.Theme.builtin.adwaita_dark);
}

fn frame() !dvui.App.Result {
    _ = dvui.button(@src(), "hello", .{}, .{});
    return .ok;
}
