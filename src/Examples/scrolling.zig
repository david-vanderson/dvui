/// ![image](Examples-scrolling.png)
pub fn scrolling() void {
    const Data1 = struct {
        msg_start: usize = 100,
        msg_end: usize = 100,

        dynamic: bool = true,
        remove_top: ?usize = null,

        auto_add: bool = false,
        scroll_info: ScrollInfo = .{},
    };

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer hbox.deinit();
        const Data = dvui.dataGetPtrDefault(null, hbox.data().id, "data", Data1, .{});

        var scroll_to_msg: ?usize = null;
        var scroll_lock_visible = false;

        // scroll to the bottom if we started there and new stuff was added
        const stick_to_bottom = Data.scroll_info.offsetFromMax(.vertical) <= 0;
        var new_bottom_stuff = false;

        var show_loading_top = false;

        if (Data.remove_top) |rt| {
            Data.remove_top = null;

            Data.msg_start = rt + 1;
            scroll_lock_visible = true;
        }

        // are we close enough to the top to load new messages?
        if (Data.dynamic and Data.scroll_info.offset(.vertical) <= 100) {
            // want to load more messages at top
            if (Data.msg_start > 0) {
                // we think we can get more messages
                if (dvui.animationGet(hbox.data().id, "load_top") == null) {
                    // this animation represents the time it takes to fetch new messages
                    dvui.animation(hbox.data().id, "load_top", .{ .start_time = 1_000_000, .end_time = 1_000_000 });
                }
            }
        }

        if (dvui.animationGet(hbox.data().id, "load_top")) |a| {
            // this represents fetching new messages
            if (a.done()) {
                // loaded more messages at the top
                Data.msg_start -|= 10;
                scroll_lock_visible = true;
            } else {
                show_loading_top = true;
            }
        }

        {
            var vbox = dvui.box(@src(), .{}, .{ .expand = .vertical });
            defer vbox.deinit();

            dvui.label(@src(), "{d} total widgets", .{2 * (Data.msg_end - Data.msg_start)}, .{});

            _ = dvui.checkbox(@src(), &Data.dynamic, "Dynamic Loading", .{});

            if (dvui.button(@src(), "Scroll to Top", .{}, .{})) {
                Data.scroll_info.scrollToOffset(.vertical, 0);
            }

            {
                var h2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                defer h2.deinit();
                if (dvui.button(@src(), "Add Above", .{}, .{})) {
                    Data.msg_start -|= 10;
                }

                if (dvui.button(@src(), "Del Above", .{}, .{})) {
                    Data.msg_start = @min(Data.msg_end, Data.msg_start + 10);
                }
            }

            if (dvui.button(@src(), "Add Above No Scroll", .{}, .{})) {
                Data.msg_start -|= 10;
                scroll_lock_visible = true;
            }

            if (dvui.button(@src(), "Del Above No Scroll", .{}, .{})) {
                Data.msg_start = @min(Data.msg_end, Data.msg_start + 10);
                scroll_lock_visible = true;
            }

            _ = dvui.spacer(@src(), .{ .expand = .vertical });

            dvui.label(@src(), "Scroll to msg:", .{}, .{});
            const result = dvui.textEntryNumber(@src(), usize, .{ .min = Data.msg_start, .max = Data.msg_end }, .{ .min_size_content = .sizeM(8, 1) });
            const label = switch (result.value) {
                .TooBig => "Too Big",
                .TooSmall => "Too Small",
                .Invalid => "Invalid",
                .Valid, .Empty => " ",
            };
            dvui.labelNoFmt(@src(), label, .{}, .{});
            if (result.value == .Valid and result.enter_pressed) {
                scroll_to_msg = result.value.Valid;
            }

            _ = dvui.spacer(@src(), .{ .expand = .vertical });

            {
                var h2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                defer h2.deinit();
                if (dvui.button(@src(), "Add Below", .{}, .{})) {
                    Data.msg_end += 10;
                    new_bottom_stuff = true;
                }

                if (dvui.button(@src(), "Del Below", .{}, .{})) {
                    Data.msg_end = @max(Data.msg_start, Data.msg_end - 10);
                }
            }

            if (dvui.button(@src(), "Scroll to Bottom", .{}, .{})) {
                Data.scroll_info.scrollToOffset(.vertical, std.math.floatMax(f32));
            }

            if (Data.auto_add) {
                const uniqId = dvui.parentGet().extendId(@src(), 0);
                if (dvui.timerGet(uniqId) == null) {
                    dvui.timer(uniqId, 1_000_000);
                }

                if (dvui.timerDone(uniqId)) {
                    Data.msg_end += 1;
                    new_bottom_stuff = true;
                    dvui.timer(uniqId, 1_000_000);
                }
            }
        }
        {
            var vbox = dvui.box(@src(), .{}, .{ .expand = .horizontal });
            defer vbox.deinit();

            dvui.label(@src(), "{d:0>4.2}% visible, offset {d:0>.1} frac {d:0>4.2} sticky-bot {any}", .{ Data.scroll_info.visibleFraction(.vertical) * 100.0, Data.scroll_info.viewport.y, Data.scroll_info.offsetFraction(.vertical), stick_to_bottom }, .{});

            var scrollData: dvui.WidgetData = undefined;
            var scroll = dvui.scrollArea(@src(), .{ .scroll_info = &Data.scroll_info, .lock_visible = scroll_lock_visible }, .{ .expand = .horizontal, .min_size_content = .{ .h = 250 }, .max_size_content = .height(250), .style = .content, .data_out = &scrollData });

            for (Data.msg_start..Data.msg_end) |i| {
                {
                    var tl = dvui.textLayout(@src(), .{}, .{ .id_extra = i, .style = .window });
                    defer tl.deinit();

                    tl.format("Message {d}", .{i}, .{});

                    if (scroll_to_msg != null and scroll_to_msg.? == i) {
                        Data.scroll_info.scrollToOffset(.vertical, tl.data().rect.y);
                    } else if (Data.dynamic and tl.data().rect.y < Data.scroll_info.offset(.vertical) - 1000) {
                        // record farthest message we want to remove
                        Data.remove_top = i;
                        dvui.refresh(null, @src(), null);
                    }
                }

                var tl2 = dvui.textLayout(@src(), .{}, .{ .id_extra = i, .gravity_x = 1.0, .style = .window });
                tl2.format("Reply {d}", .{i}, .{});
                tl2.deinit();
            }

            scroll.deinit();

            if (show_loading_top) {
                const r = scrollData.rectScale().r;
                const pt: dvui.Point.Physical = .{ .x = r.x + r.w / 2, .y = r.y };
                var fw: dvui.FloatingWidget = undefined;
                fw.init(@src(), .{ .from = pt, .from_gravity_y = 1.0 }, .{ .background = true, .style = .window, .corner_radius = .all(1000), .padding = .all(4), .margin = .all(4) });
                dvui.label(@src(), "Loading Top...", .{}, .{});
                fw.deinit();
            }

            _ = dvui.checkbox(@src(), &Data.auto_add, "Add Msg 1/s", .{});
        }

        if (new_bottom_stuff and stick_to_bottom) {
            // do this after scrollArea has given scroll_info the new size
            Data.scroll_info.scrollToOffset(.vertical, std.math.floatMax(f32));
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .all(12) });
    _ = dvui.separator(@src(), .{ .expand = .horizontal });
    _ = dvui.spacer(@src(), .{ .min_size_content = .all(12) });

    var box2 = dvui.box(@src(), .{}, .{ .expand = .horizontal });
    defer box2.deinit();

    const siTop = dvui.dataGetPtrDefault(null, box2.data().id, "siTop", ScrollInfo, .{ .horizontal = .auto });
    const siLeft = dvui.dataGetPtrDefault(null, box2.data().id, "siLeft", ScrollInfo, .{ .horizontal = .auto });
    const siMain = dvui.dataGetPtrDefault(null, box2.data().id, "siMain", ScrollInfo, .{ .horizontal = .auto });

    // save the viewport so everything is synced this frame
    const fv = siMain.viewport.topLeft();
    const left_side_width = 80;
    {
        var main_area: dvui.ScrollAreaWidget = undefined;
        main_area.init(@src(), .{ .scroll_info = siMain, .frame_viewport = fv, .container = false }, .{ .expand = .both, .max_size_content = .height(300), .background = false });
        defer main_area.deinit();

        {
            var hboxTop = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hboxTop.deinit();

            var lbox = dvui.box(@src(), .{}, .{ .min_size_content = .width(left_side_width) });
            dvui.label(@src(), "Linked\nScrolling", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
            lbox.deinit();

            _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

            {
                var top_area = dvui.scrollArea(@src(), .{ .scroll_info = siTop, .frame_viewport = .{ .x = fv.x }, .horizontal_bar = .hide, .process_events_after = false }, .{ .expand = .both, .style = .content });
                defer top_area.deinit();
                {
                    // inside top area
                    var topbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                    defer topbox.deinit();

                    for (0..20) |i| {
                        dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
                    }
                }
            }
        }

        _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

        {
            var hbox3 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox3.deinit();

            var side_area = dvui.scrollArea(@src(), .{ .scroll_info = siLeft, .frame_viewport = .{ .y = fv.y }, .vertical_bar = .hide, .process_events_after = false }, .{ .style = .content, .min_size_content = .{ .w = left_side_width, .h = 200 }, .expand = .vertical });
            {
                // inside side area
                var sidebox = dvui.box(@src(), .{}, .{});
                defer sidebox.deinit();

                for (0..20) |i| {
                    dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
                }
            }
            side_area.deinit();

            _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

            {
                var scontainer: dvui.ScrollContainerWidget = undefined;
                scontainer.init(@src(), siMain, .{ .scroll_area = &main_area, .frame_viewport = fv, .event_rect = main_area.data().borderRectScale().r }, .{ .style = .content, .expand = .both });
                defer scontainer.deinit();
                scontainer.processEvents();
                scontainer.processVelocity();

                {
                    // inside main area
                    var mainbox = dvui.box(@src(), .{}, .{});
                    defer mainbox.deinit();
                    {
                        var mainbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                        defer mainbox2.deinit();
                        for (0..20) |i| {
                            dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
                        }
                    }
                    for (1..20) |i| {
                        dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
                    }
                } // mainbox
            } // scontainer
        } // hbox3
    } // main_area

    // sync siTop and siMain horizontal
    if (siTop.viewport.x != fv.x) siMain.viewport.x = siTop.viewport.x;
    if (siMain.viewport.x != fv.x) siTop.viewport.x = siMain.viewport.x;

    // sync siLeft and siMain vertical
    if (siLeft.viewport.y != fv.y) siMain.viewport.y = siLeft.viewport.y;
    if (siMain.viewport.y != fv.y) siLeft.viewport.y = siMain.viewport.y;

    // TODO: what happens if sizes are different?
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG scrolling" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 400 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            scrolling();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-scrolling.png");
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const ScrollInfo = dvui.ScrollInfo;
