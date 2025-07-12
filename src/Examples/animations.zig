var animating_window_show: bool = false;
var animating_window_closing: bool = false;
var animating_window_rect = Rect{ .x = 100, .y = 100, .w = 300, .h = 200 };

/// ![image](Examples-animations.png)
pub fn animations() void {
    const global = struct {
        var animation_choice: usize = 0;
        var round_corners: bool = false;
        var center: bool = false;
        var easing_choice: usize = 0;
        var easing: *const dvui.easing.EasingFn = dvui.easing.linear;
        var duration: i32 = 500_000;
        var xs: [100]f64 = @splat(0);
        var ys: [100]f64 = @splat(0);
    };
    const easing_fns, const easing_names = comptime blk: {
        const decls = std.meta.declarations(dvui.easing);
        var easing_names_arr = [_][]const u8{undefined} ** decls.len;
        var easing_fns_arr = [_]*const dvui.easing.EasingFn{undefined} ** decls.len;
        var i = 0;
        for (decls) |decl| {
            const decl_field = @field(dvui.easing, decl.name);
            if (@TypeOf(decl_field) == dvui.easing.EasingFn) {
                easing_names_arr[i] = decl.name;
                easing_fns_arr[i] = decl_field;
                i += 1;
            }
        }
        var out_names = [_][]const u8{undefined} ** i;
        var out_fns = [_]*const dvui.easing.EasingFn{undefined} ** i;
        @memcpy(&out_names, easing_names_arr[0..i]);
        @memcpy(&out_fns, easing_fns_arr[0..i]);
        break :blk .{ out_fns, out_names };
    };

    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        {
            var hbox2 = dvui.box(@src(), .vertical, .{ .min_size_content = .{ .w = 200 } });
            defer hbox2.deinit();

            var button_wiggle = ButtonWidget.init(@src(), .{}, .{ .gravity_x = 0.5 });
            defer button_wiggle.deinit();

            if (dvui.animationGet(button_wiggle.data().id, "xoffset")) |a| {
                button_wiggle.data().rect.x += 20 * (1.0 - a.value()) * (1.0 - a.value()) * @sin(a.value() * std.math.pi * 50);
            }

            button_wiggle.install();
            button_wiggle.processEvents();
            button_wiggle.drawBackground();
            dvui.labelNoFmt(@src(), "Wiggle", .{}, button_wiggle.data().options.strip().override(.{ .gravity_x = 0.5, .gravity_y = 0.5 }));
            button_wiggle.drawFocus();

            if (button_wiggle.clicked()) {
                dvui.animation(button_wiggle.data().id, "xoffset", .{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 500_000 });
            }
        }

        if (dvui.button(@src(), "Animating Window (Rect)", .{}, .{})) {
            if (animating_window_show) {
                animating_window_closing = true;
            } else {
                animating_window_show = true;
                animating_window_closing = false;
            }
        }

        if (animating_window_show) {
            var win = animatingWindowRect(@src(), &animating_window_rect, &animating_window_show, &animating_window_closing, .{});
            win.install();
            win.processEventsBefore();
            win.drawBackground();
            defer win.deinit();

            var keep_open = true;
            win.dragAreaSet(dvui.windowHeader("Animating Window (center)", "", &keep_open));
            if (!keep_open) {
                animating_window_closing = true;
            }

            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
            tl.addText("This shows how to animate dialogs and other floating windows by changing the rect.\n\nThis dialog also remembers its position on screen.", .{});
            tl.deinit();
        }
    }

    if (dvui.expander(@src(), "Easings", .{}, .{ .expand = .horizontal })) {
        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();

            dvui.labelNoFmt(@src(), "Animate", .{}, .{ .gravity_y = 0.5 });

            _ = dvui.dropdown(@src(), &.{ "alpha", "horizontal", "vertical" }, &global.animation_choice, .{});

            dvui.labelNoFmt(@src(), "easing", .{}, .{ .gravity_y = 0.5 });

            var recalc = false;
            if (dvui.firstFrame(hbox.data().id)) {
                recalc = true;
            }

            if (dvui.dropdown(@src(), &easing_names, &global.easing_choice, .{})) {
                global.easing = easing_fns[global.easing_choice];
                recalc = true;
            }

            var duration_float: f32 = @floatFromInt(@divTrunc(global.duration, std.time.us_per_ms));
            if (dvui.sliderEntry(
                @src(),
                "Duration {d}ms",
                .{ .value = &duration_float, .min = 50, .interval = 10, .max = 2_000 },
                .{ .min_size_content = .{ .w = 180 }, .gravity_y = 0.5 },
            )) {
                global.duration = @as(i32, @intFromFloat(duration_float)) * std.time.us_per_ms;
            }

            if (recalc) {
                for (0..global.xs.len) |i| {
                    global.xs[i] = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(global.xs.len));
                    global.ys[i] = global.easing(@floatCast(global.xs[i]));
                }
            }
        }

        {
            var start = false;
            var end = false;
            {
                var hbox = dvui.box(@src(), .horizontal, .{});
                defer hbox.deinit();

                if (dvui.button(@src(), "start", .{}, .{})) {
                    start = true;
                }

                if (dvui.button(@src(), "end", .{}, .{})) {
                    end = true;
                }

                if (global.animation_choice > 0) {
                    _ = dvui.checkbox(@src(), &global.center, "Center", .{ .gravity_y = 0.5 });
                }
            }

            // overlay is just here for padding and sizing
            var o = dvui.overlay(@src(), .{ .padding = dvui.Rect.all(6), .min_size_content = .{ .w = 100, .h = 80 } });
            defer o.deinit();

            const kind: dvui.AnimateWidget.Kind = switch (global.animation_choice) {
                0 => .alpha,
                1 => .horizontal,
                2 => .vertical,
                else => unreachable,
            };
            var animator = dvui.animate(@src(), .{ .kind = kind, .duration = global.duration, .easing = global.easing }, .{ .expand = .both, .gravity_x = if (global.center) 0.5 else 0.0, .gravity_y = if (global.center) 0.5 else 0.0 });
            defer animator.deinit();

            if (start) animator.start();
            if (end) animator.startEnd();

            dvui.plotXY(@src(), .{}, 1, &global.xs, &global.ys, .{ .expand = .both });
        }

        if (dvui.button(@src(), "Animating Dialog (drop)", .{}, .{})) {
            dvui.dialog(@src(), .{ .duration = global.duration, .easing = global.easing }, .{ .modal = false, .title = "Animating Dialog (drop)", .message = "This shows how to animate dialogs and other floating windows.", .displayFn = AnimatingDialog.dialogDisplay, .callafterFn = AnimatingDialog.after });
        }
    }

    if (dvui.expander(@src(), "Spinner", .{}, .{ .expand = .horizontal })) {
        dvui.labelNoFmt(@src(), "Spinner maxes out frame rate", .{}, .{});
        dvui.spinner(@src(), .{ .color_text = .{ .color = .{ .r = 100, .g = 200, .b = 100 } } });
    }

    if (dvui.expander(@src(), "Clock", .{}, .{ .expand = .horizontal })) {
        dvui.labelNoFmt(@src(), "Schedules a frame at the beginning of each second", .{}, .{});

        const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
        const left = @as(i32, @intCast(@rem(millis, 1000)));

        {
            var mslabel = dvui.LabelWidget.init(@src(), "{d:0>3} ms into second", .{@as(u32, @intCast(left))}, .{}, .{});
            defer mslabel.deinit();

            mslabel.install();
            mslabel.draw();

            if (dvui.timerDoneOrNone(mslabel.data().id)) {
                const wait = 1000 * (1000 - left);
                dvui.timer(mslabel.data().id, wait);
            }
        }
        dvui.label(@src(), "Estimate of frame overhead {d:6} us", .{dvui.currentWindow().loop_target_slop}, .{});
        switch (dvui.backend.kind) {
            .sdl2, .sdl3 => dvui.label(@src(), "sdl: updated when not interrupted by event", .{}, .{}),
            .web => dvui.label(@src(), "web: updated when not interrupted by event", .{}, .{}),
            .raylib => dvui.label(@src(), "raylib: only updated if non-null passed to waitTime", .{}, .{}),
            .dx11 => dvui.label(@src(), "dx11: only updated if non-null passed to waitTime", .{}, .{}),
            .sdl, .custom, .testing => {},
        }
    }

    if (dvui.expander(@src(), "Texture Frames", .{}, .{ .expand = .horizontal })) {
        var box = dvui.box(@src(), .vertical, .{ .margin = .{ .x = 10 } });
        defer box.deinit();

        const pixels = dvui.dataGetPtrDefault(null, box.data().id, "pixels", [4]dvui.Color.PMA, .{ .yellow, .cyan, .red, .magenta });
        const image_source: dvui.ImageSource = .{ .pixelsPMA = .{ .rgba = pixels, .width = 2, .height = 2, .interpolation = .nearest } };

        // example of how to run frames at a certain fps
        const millis_per_frame = 500;
        if (dvui.timerDoneOrNone(box.data().id)) {
            std.mem.rotate(dvui.Color.PMA, pixels, 1);
            dvui.textureInvalidateCache(image_source.hash());

            const millis = @divFloor(dvui.frameTimeNS(), 1_000_000);
            const left = @as(i32, @intCast(@rem(millis, millis_per_frame)));
            const wait = 1000 * (millis_per_frame - left);
            dvui.timer(box.data().id, wait);
        }

        const num_frames = 4;
        const frame: std.math.IntFittingRange(0, num_frames) = blk: {
            const millis = @divFloor(dvui.frameTimeNS(), std.time.ns_per_ms);
            const left = @as(i32, @intCast(@rem(millis, num_frames * millis_per_frame)));
            break :blk @intCast(@divTrunc(left, millis_per_frame));
        };

        {
            var hbox = dvui.box(@src(), .horizontal, .{});
            defer hbox.deinit();
            dvui.label(@src(), "frame: {d}", .{frame}, .{});
            _ = dvui.checkbox(@src(), &global.round_corners, "Round Corners", .{});
            //dvui.label(@src(), "num textures: {d}", .{dvui.backend.num_textures}, .{});
        }

        var frame_box = dvui.box(@src(), .horizontal, .{ .min_size_content = .{ .w = 50, .h = 50 } });
        defer frame_box.deinit();

        _ = dvui.image(@src(), .{ .source = image_source }, .{ .expand = .both, .corner_radius = if (global.round_corners) dvui.Rect.all(10) else .{} });
    }
}

pub fn animatingWindowRect(src: std.builtin.SourceLocation, rect: *Rect, show_flag: *bool, closing: *bool, opts: Options) FloatingWindowWidget {
    const fwin_id = dvui.parentGet().extendId(src, opts.idExtra());

    if (dvui.firstFrame(fwin_id)) {
        dvui.animation(fwin_id, "rect_percent", .{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 300_000 });
        dvui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    if (closing.*) {
        closing.* = false;
        dvui.animation(fwin_id, "rect_percent", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 300_000 });
        dvui.dataSet(null, fwin_id, "size", rect.*.size());
    }

    var fwin: FloatingWindowWidget = undefined;

    if (dvui.animationGet(fwin_id, "rect_percent")) |a| {
        if (dvui.dataGet(null, fwin_id, "size", Size)) |ss| {
            var r = rect.*;
            const dw = ss.w * a.value();
            const dh = ss.h * a.value();
            r.x = r.x + (r.w / 2) - (dw / 2);
            r.w = dw;
            r.y = r.y + (r.h / 2) - (dh / 2);
            r.h = dh;

            // don't pass rect so our animating rect doesn't get saved back
            fwin = FloatingWindowWidget.init(src, .{ .open_flag = show_flag }, opts.override(.{ .rect = r }));

            if (a.done() and r.empty()) {
                // done with closing animation
                fwin.close();
            }
        }
    } else {
        fwin = FloatingWindowWidget.init(src, .{ .rect = rect, .open_flag = show_flag }, opts);
    }

    return fwin;
}

const AnimatingDialog = struct {
    pub fn dialogDisplay(id: dvui.WidgetId) !void {
        const modal = dvui.dataGet(null, id, "_modal", bool) orelse unreachable;
        const title = dvui.dataGetSlice(null, id, "_title", []u8) orelse unreachable;
        const message = dvui.dataGetSlice(null, id, "_message", []u8) orelse unreachable;
        const callafter = dvui.dataGet(null, id, "_callafter", DialogCallAfterFn);
        const duration = dvui.dataGet(null, id, "duration", i32) orelse unreachable;
        const easing = dvui.dataGet(null, id, "easing", *const dvui.easing.EasingFn) orelse unreachable;

        // once we record a response, refresh it until we close
        _ = dvui.dataGet(null, id, "response", enums.DialogResponse);

        var win = FloatingWindowWidget.init(@src(), .{ .modal = modal }, .{ .id_extra = id.asUsize(), .max_size_content = .width(300) });

        if (dvui.firstFrame(win.data().id)) {
            dvui.animation(win.data().id, "rect_percent", .{ .start_val = 0.0, .end_val = 1.0, .end_time = duration, .easing = easing });
        }

        const winHeight = win.data().rect.h;
        var winHeight_changed = false;

        if (dvui.animationGet(win.data().id, "rect_percent")) |a| {
            win.data().rect.h *= a.value();
            winHeight_changed = true;

            // mucking with the window size can screw up the windows auto sizing, so force it
            win.autoSize();

            if (a.done() and a.end_val == 0) {
                dvui.dialogRemove(id);

                if (callafter) |ca| {
                    const response = dvui.dataGet(null, id, "response", enums.DialogResponse) orelse {
                        std.log.debug("Error: no response for dialog {x}\n", .{id});
                        return;
                    };
                    ca(id, response) catch |err| {
                        std.log.debug("AnimationDialogs callafter got {!}", .{err});
                    };
                }

                return;
            }
        }

        win.install();
        defer win.deinit();
        win.processEventsBefore();
        win.drawBackground();

        var closing: bool = false;

        var header_openflag = true;
        win.dragAreaSet(dvui.windowHeader(title, "", &header_openflag));
        if (!header_openflag) {
            closing = true;
            dvui.dataSet(null, id, "response", enums.DialogResponse.cancel);
        }

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        tl.addText(message, .{});
        tl.deinit();

        if (dvui.button(@src(), "Ok", .{}, .{ .gravity_x = 0.5, .gravity_y = 1.0, .tab_index = 1 })) {
            closing = true;
            dvui.dataSet(null, id, "response", enums.DialogResponse.ok);
        }

        // restore saved win rect so our change is not persisted to next frame
        if (winHeight_changed) {
            win.data().rect.h = winHeight;
        }

        if (closing) {
            dvui.animation(win.data().id, "rect_percent", .{ .start_val = 1.0, .end_val = 0.0, .end_time = duration, .easing = easing });
        }
    }

    pub fn after(id: dvui.WidgetId, response: enums.DialogResponse) !void {
        _ = id;
        std.log.debug("You clicked \"{s}\"", .{@tagName(response)});
    }
};

const std = @import("std");
const dvui = @import("../dvui.zig");
const enums = dvui.enums;
const Size = dvui.Size;
const Rect = dvui.Rect;
const Options = dvui.Options;
const ButtonWidget = dvui.ButtonWidget;
const FloatingWindowWidget = dvui.FloatingWindowWidget;
const DialogCallAfterFn = dvui.DialogCallAfterFn;
