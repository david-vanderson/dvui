pub const Self = @This();

window: *dvui.Window,
frameFn: *const fn () anyerror!void,

time_ns: i128 = 0,

named_widgets: std.AutoHashMap(u32, WidgetInfo),

pub const WidgetInfo = struct {
    /// The Widget data is guaranteed to have the rect_scale_cache populated.
    ///
    /// IMPORTANT: All functions that interact with the window and parent widget are invalid to call!
    // we store WidgetData directly to use its logic for rect sizing
    wd: dvui.WidgetData,
    visible: bool,
};

pub fn init(window: *dvui.Window, frameFn: *const fn () anyerror!void) Self {
    return .{
        .window = window,
        .frameFn = frameFn,
        .named_widgets = .init(window.gpa),
    };
}

pub fn deinit(self: *Self) void {
    self.named_widgets.deinit();
}

pub fn registerWidgetData(self: *Self, wd: *const dvui.WidgetData) !void {
    if (wd.options.test_id) |test_id| {
        const hashed_id = dvui.hashIdKey(@intCast(wd.options.idExtra()), test_id);
        try self.named_widgets.put(hashed_id, .{
            .wd = wd.*,
            .visible = wd.visible(),
        });
    }
}

pub fn run(
    self: *Self,
) !void {
    defer self.time_ns += 1000 * std.time.ns_per_ms; // Move time really fast to finish animations quicker

    self.window.runner = self;
    defer self.window.runner = null;

    var i: usize = 0;
    // 0 indicates that dvui want to render as fast as possible
    var wait_time: ?u32 = 0;
    while (wait_time == 0 and i < 100) : (i += 1) {
        self.named_widgets.clearRetainingCapacity();
        try self.window.begin(self.time_ns);
        try self.frameFn();
        wait_time = try self.window.end(.{});
    }
    std.debug.print("Run exited with i {d}\n", .{i});
}

// Adds a position event to move the mouse over the widget
fn moveToWidget(self: *Self, info: *const WidgetInfo) !void {
    if (!info.visible) return error.WidgetNotVisible;
    const center = info.wd.rect.topLeft().plus(.{ .x = info.wd.rect.w / 2, .y = info.wd.rect.h / 2 });
    const movement = center.diff(self.window.mouse_pt);
    if (movement.nonZero()) {
        _ = try self.window.addEventMouseMotion(movement.x, movement.y);
    }
}

pub fn click(self: *Self, test_id: []const u8, id_extra: u32) !void {
    const hashed_id = dvui.hashIdKey(id_extra, test_id);
    const info = self.named_widgets.getPtr(hashed_id) orelse return error.NamedWidgetDidNotExist;
    try self.moveToWidget(info);

    _ = try self.window.addEventMouseButton(.left, .press);
    _ = try self.window.addEventMouseButton(.left, .release);
}

const std = @import("std");
const dvui = @import("dvui.zig");
