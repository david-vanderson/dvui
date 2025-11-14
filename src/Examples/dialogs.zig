var progress_mutex = std.Thread.Mutex{};
var progress_val: f32 = 0.0;

/// ![image](Examples-dialogs.png)
pub fn dialogs(demo_win_id: dvui.Id) void {
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        if (dvui.button(@src(), "Direct Dialog", .{}, .{})) {
            Examples.show_dialog = true;
        }

        if (dvui.button(@src(), "Giant", .{}, .{})) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "So Much Text", .ok_label = "Too Much", .max_size = .{ .w = 300, .h = 300 }, .message = "This is a non modal dialog with no callafter which happens to have just way too much text in it.\n\nLuckily there is a max_size on here and if the text is too big it will be scrolled.\n\nI mean come on there is just way too much text here.\n\nCan you imagine this much text being created for a dialog?\n\nMaybe like a giant error message with a stack trace or dumping the contents of a large struct?\n\nOr a dialog asking way too many questions, or dumping a whole log into the dialog, or just a very long rant.\n\nMore lines.\n\nAnd more lines.\n\nFinally the last line." });
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Non modal", .{}, .{})) {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Ok Dialog", .ok_label = "Ok", .message = "This is a non modal dialog with no callafter\n\nThe ok button is focused by default" });
        }

        const dialogsFollowup = struct {
            fn callafter(id: dvui.Id, response: enums.DialogResponse) !void {
                _ = id;
                var buf: [100]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "You clicked \"{s}\" in the previous dialog", .{@tagName(response)}) catch unreachable;
                dvui.dialog(@src(), .{}, .{ .title = "Ok Followup Response", .message = text });
            }
        };

        if (dvui.button(@src(), "Modal with followup", .{}, .{})) {
            dvui.dialog(@src(), .{}, .{ .title = "Followup", .message = "This is a modal dialog with modal followup\n\nHere the cancel button is focused", .callafterFn = dialogsFollowup.callafter, .cancel_label = "Cancel", .default = .cancel });
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Toast 1", .{}, .{})) {
            dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 1 to demo window" });
        }

        if (dvui.button(@src(), "Toast 2", .{}, .{})) {
            dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 2 to demo window" });
        }

        if (dvui.button(@src(), "Toast 3", .{}, .{})) {
            dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Toast 3 to demo window" });
        }

        if (dvui.button(@src(), "Toast Main Window", .{}, .{})) {
            dvui.toast(@src(), .{ .message = "Toast to main window" });
        }
    }

    {
        var vbox = dvui.box(@src(), .{}, .{ .min_size_content = .{ .w = 250, .h = 80 }, .border = .all(1) });
        defer vbox.deinit();

        if (dvui.button(@src(), "Toast In Box", .{}, .{})) {
            dvui.toast(@src(), .{ .subwindow_id = vbox.data().id, .message = "Toast to this box" });
        }

        dvui.toastsShow(vbox.data().id, vbox.data().contentRectScale().r.toNatural());
    }

    dvui.label(@src(), "\nDialogs and toasts from other threads", .{}, .{});
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Dialog after 1 second", .{}, .{})) {
            if (!builtin.single_threaded) blk: {
                const bg_thread = std.Thread.spawn(.{}, background_dialog, .{ dvui.currentWindow(), 1_000_000_000 }) catch |err| {
                    dvui.log.debug("Failed to spawn background thread for delayed action, got {any}", .{err});
                    break :blk;
                };
                bg_thread.detach();
            } else {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not available in single-threaded" });
            }
        }

        if (dvui.button(@src(), "Toast after 1 second", .{}, .{})) {
            if (!builtin.single_threaded) blk: {
                const bg_thread = std.Thread.spawn(.{}, background_toast, .{ dvui.currentWindow(), 1_000_000_000, demo_win_id }) catch |err| {
                    dvui.log.debug("Failed to spawn background thread for delayed action, got {any}", .{err});
                    break :blk;
                };
                bg_thread.detach();
            } else {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not available in single-threaded" });
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer hbox.deinit();

        if (dvui.button(@src(), "Show Progress from another Thread", .{}, .{})) {
            progress_mutex.lock();
            progress_val = 0;
            progress_mutex.unlock();
            if (!builtin.single_threaded) blk: {
                const bg_thread = std.Thread.spawn(.{}, background_progress, .{ dvui.currentWindow(), 2_000_000_000 }) catch |err| {
                    dvui.log.debug("Failed to spawn background thread for delayed action, got {any}", .{err});
                    break :blk;
                };
                bg_thread.detach();
            } else {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not available in single-threaded" });
            }
        }

        dvui.progress(@src(), .{ .percent = progress_val }, .{ .expand = .horizontal, .gravity_y = 0.5, .corner_radius = dvui.Rect.all(100) });
    }

    dvui.label(@src(), "\nNative Dialogs", .{}, .{});
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        const single_file_id = hbox.widget().extendId(@src(), 0);

        if (dvui.button(@src(), "Open File", .{}, .{})) {
            if (dvui.wasm) {
                dvui.dialogWasmFileOpen(single_file_id, .{ .accept = ".png, .jpg" });
            } else if (!dvui.useTinyFileDialogs) {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Tiny File Dilaogs disabled" });
            } else {
                const filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{
                    .title = "dvui native file open",
                    .filters = &.{ "*.png", "*.jpg" },
                    .filter_description = "images",
                }) catch |err| blk: {
                    dvui.log.debug("Could not open file dialog, got {any}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Result", .ok_label = "Done", .message = f });
                }
            }
        }

        if (dvui.wasmFileUploaded(single_file_id)) |file| {
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Result", .ok_label = "Done", .message = file.name });
        }

        const multi_file_id = hbox.widget().extendId(@src(), 0);

        if (dvui.button(@src(), "Open Multiple Files", .{}, .{})) {
            if (dvui.wasm) {
                dvui.dialogWasmFileOpenMultiple(multi_file_id, .{ .accept = ".png, .jpg" });
            } else if (!dvui.useTinyFileDialogs) {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Tiny File Dilaogs disabled" });
            } else {
                const filenames = dvui.dialogNativeFileOpenMultiple(dvui.currentWindow().arena(), .{
                    .title = "dvui native file open multiple",
                    .filter_description = "images",
                }) catch |err| blk: {
                    dvui.log.debug("Could not open multi file dialog, got {any}", .{err});
                    break :blk null;
                };
                if (filenames) |files| {
                    const msg = std.mem.join(dvui.currentWindow().lifo(), "\n", files) catch "";
                    defer dvui.currentWindow().lifo().free(msg);
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Multiple Result", .ok_label = "Done", .message = msg });
                }
            }
        }

        if (dvui.wasmFileUploadedMultiple(multi_file_id)) |files| blk: {
            const lifo = dvui.currentWindow().lifo();
            const names = lifo.alloc([:0]const u8, files.len) catch break :blk;
            defer dvui.currentWindow().lifo().free(names);
            for (files, names) |f, *name| name.* = f.name;

            const msg = std.mem.join(dvui.currentWindow().lifo(), "\n", names) catch "";
            defer dvui.currentWindow().lifo().free(msg);
            dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Open Multiple Result", .ok_label = "Done", .message = msg });
        }
    }
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        if (dvui.button(@src(), "Open Folder", .{}, .{})) {
            if (dvui.wasm) {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Not implemented for web" });
            } else if (!dvui.useTinyFileDialogs) {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Tiny File Dilaogs disabled" });
            } else {
                const filename = dvui.dialogNativeFolderSelect(dvui.currentWindow().arena(), .{ .title = "dvui native folder select" }) catch |err| blk: {
                    dvui.log.debug("Could not open folder select dialog, got {any}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Folder Select Result", .ok_label = "Done", .message = f });
                }
            }
        }

        if (dvui.button(@src(), "Save File", .{}, .{})) {
            if (dvui.wasm) {
                dvui.dialog(@src(), .{}, .{ .modal = false, .title = "Save File", .ok_label = "Ok", .message = "Not available on the web.  For file download, see \"Save Plot\" in the plots example." });
            } else if (!dvui.useTinyFileDialogs) {
                dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Tiny File Dilaogs disabled" });
            } else {
                const filename = dvui.dialogNativeFileSave(dvui.currentWindow().arena(), .{ .title = "dvui native file save" }) catch |err| blk: {
                    dvui.log.debug("Could not open file save dialog, got {any}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    dvui.dialog(@src(), .{}, .{ .modal = false, .title = "File Save Result", .ok_label = "Done", .message = f });
                }
            }
        }
    }
}

fn background_dialog(win: *dvui.Window, delay_ns: u64) void {
    std.Thread.sleep(delay_ns);
    dvui.dialog(@src(), .{}, .{ .window = win, .modal = false, .title = "Background Dialog", .message = "This non modal dialog was added from a non-GUI thread." });
}

fn background_toast(win: *dvui.Window, delay_ns: u64, subwindow_id: ?dvui.Id) void {
    std.Thread.sleep(delay_ns);
    dvui.refresh(win, @src(), null);
    dvui.toast(@src(), .{ .window = win, .subwindow_id = subwindow_id, .message = "Toast came from a non-GUI thread" });
}

fn background_progress(win: *dvui.Window, delay_ns: u64) void {
    const interval: u64 = 10_000_000;
    var total_sleep: u64 = 0;
    while (total_sleep < delay_ns) : (total_sleep += interval) {
        std.Thread.sleep(interval);
        progress_mutex.lock();
        progress_val = @as(f32, @floatFromInt(total_sleep)) / @as(f32, @floatFromInt(delay_ns));
        progress_mutex.unlock();
        dvui.refresh(win, @src(), null);
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG dialogs" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 400, .h = 300 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            dialogs(box.data().id);
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);

    // Tab to the main window toast button
    for (0..8) |_| {
        try dvui.testing.pressKey(.tab, .none);
        _ = try dvui.testing.step(frame);
    }
    try dvui.testing.pressKey(.enter, .none);

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-dialogs.png");
}

const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("../dvui.zig");
const enums = dvui.enums;
const Examples = @import("../Examples.zig");
