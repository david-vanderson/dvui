/// This will just be something that waits simulating a long operation
const std = @import("std");
const dvui = @import("../dvui.zig");

/// So zig doesn't give the types different IDs
const UpdateType = dvui.update.UpdateThread(Message);

const Message = enum {
    load_item,
    unload_item,
};

const AppState = struct {
    text: []const u8 = "no-content",
    update: UpdateType = undefined,
    window: *dvui.Window = undefined,
};

var state = AppState{ .update = .{ .self = undefined, .update_fn = update } };

pub fn updateThreads() !void {
    if (!state.update.queue_initialized) {
        state.window = dvui.currentWindow();
        state.update.self = &state;
        try state.update.run();
    }

    if (dvui.button(@src(), "load", .{}, .{})) try state.update.send(dvui.currentWindow().arena(), .load_item);

    dvui.label(@src(), "{s}", .{state.text}, .{});
}

fn update(self_: *anyopaque, message: Message) !void {
    const self: *AppState = @ptrCast(@alignCast(self_));
    switch (message) {
        .load_item => {
            if (std.mem.eql(u8, "loaded", self.text)) {
                self.text = "no-content";
                return;
            }
            self.text = "loading";
            const time = try std.time.Instant.now();
            // wait 0.5s while clugging the thread (on purpose)
            while ((try std.time.Instant.now()).since(time) < 1500000000) {}
            self.text = "loaded";
            self.window.refreshWindow(@src(), null); // Show the new information
        },
        .unload_item => unreachable,
    }
}
