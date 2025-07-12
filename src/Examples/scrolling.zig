/// ![image](Examples-scrolling.png)
pub fn scrolling() void {
    const Data1 = struct {
        msg_start: usize = 1_000,
        msg_end: usize = 1_100,
        scroll_info: ScrollInfo = .{},
    };

    {
        var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
        defer hbox.deinit();
        const Data = dvui.dataGetPtrDefault(null, hbox.data().id, "data", Data1, .{});

        var scroll_to_msg: ?usize = null;
        var scroll_to_bottom_after = false;
        var scroll_lock_visible = false;

        {
            var vbox = dvui.box(@src(), .vertical, .{ .expand = .vertical });
            defer vbox.deinit();

            dvui.label(@src(), "{d} total widgets", .{2 * (Data.msg_end - Data.msg_start)}, .{});

            if (dvui.button(@src(), "Scroll to Top", .{}, .{})) {
                Data.scroll_info.scrollToOffset(.vertical, 0);
            }

            {
                var h2 = dvui.box(@src(), .horizontal, .{});
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
            const result = dvui.textEntryNumber(@src(), usize, .{ .min = Data.msg_start, .max = Data.msg_end }, .{ .min_size_content = dvui.Options.sizeM(8, 1) });
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
                var h2 = dvui.box(@src(), .horizontal, .{});
                defer h2.deinit();
                if (dvui.button(@src(), "Add Below", .{}, .{})) {
                    Data.msg_end += 10;
                }

                if (dvui.button(@src(), "Del Below", .{}, .{})) {
                    Data.msg_end = @max(Data.msg_start, Data.msg_end - 10);
                }
            }

            if (dvui.button(@src(), "Add Below + Scroll", .{}, .{})) {
                Data.msg_end += 10;
                scroll_to_bottom_after = true;
            }

            if (dvui.button(@src(), "Scroll to Bottom", .{}, .{})) {
                Data.scroll_info.scrollToOffset(.vertical, std.math.maxInt(usize));
            }
        }
        {
            var vbox = dvui.box(@src(), .vertical, .{ .expand = .horizontal, .max_size_content = .height(300) });
            defer vbox.deinit();

            dvui.label(@src(), "{d:0>4.2}% visible, offset {d} frac {d:0>4.2}", .{ Data.scroll_info.visibleFraction(.vertical) * 100.0, Data.scroll_info.viewport.y, Data.scroll_info.offsetFraction(.vertical) }, .{});

            var scroll = dvui.scrollArea(@src(), .{ .scroll_info = &Data.scroll_info, .lock_visible = scroll_lock_visible }, .{ .expand = .horizontal, .min_size_content = .{ .h = 250 } });
            defer scroll.deinit();

            for (Data.msg_start..Data.msg_end + 1) |i| {
                {
                    var tl = dvui.textLayout(@src(), .{}, .{ .id_extra = i, .color_fill = .fill_window });
                    defer tl.deinit();

                    tl.format("Message {d}", .{i}, .{});

                    if (scroll_to_msg != null and scroll_to_msg.? == i) {
                        Data.scroll_info.scrollToOffset(.vertical, tl.data().rect.y);
                    }
                }

                var tl2 = dvui.textLayout(@src(), .{}, .{ .id_extra = i, .gravity_x = 1.0, .color_fill = .fill_window });
                tl2.format("Reply {d}", .{i}, .{});
                tl2.deinit();
            }
        }

        if (scroll_to_bottom_after) {
            // do this after scrollArea has given scroll_info the new size
            Data.scroll_info.scrollToOffset(.vertical, std.math.maxInt(usize));
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .all(12) });
    _ = dvui.separator(@src(), .{ .expand = .horizontal });
    _ = dvui.spacer(@src(), .{ .min_size_content = .all(12) });

    var box2 = dvui.box(@src(), .vertical, .{ .expand = .horizontal });
    defer box2.deinit();

    const siTop = dvui.dataGetPtrDefault(null, box2.data().id, "siTop", ScrollInfo, .{ .horizontal = .auto });
    const siLeft = dvui.dataGetPtrDefault(null, box2.data().id, "siLeft", ScrollInfo, .{ .horizontal = .auto });
    const siMain = dvui.dataGetPtrDefault(null, box2.data().id, "siMain", ScrollInfo, .{ .horizontal = .auto });

    // save the viewport so everything is synced this frame
    const fv = siMain.viewport.topLeft();
    const left_side_width = 80;
    {
        var main_area = dvui.ScrollAreaWidget.init(@src(), .{ .scroll_info = siMain, .frame_viewport = fv }, .{ .expand = .both, .max_size_content = .height(300), .background = false });
        defer main_area.deinit();
        main_area.installScrollBars();

        {
            var hboxTop = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hboxTop.deinit();

            var lbox = dvui.box(@src(), .vertical, .{ .min_size_content = .width(left_side_width) });
            dvui.label(@src(), "Linked\nScrolling", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
            lbox.deinit();

            _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

            {
                var top_area = dvui.scrollArea(@src(), .{ .scroll_info = siTop, .frame_viewport = .{ .x = fv.x }, .horizontal_bar = .hide, .process_events_after = false }, .{ .expand = .both });
                defer top_area.deinit();
                {
                    // inside top area
                    var topbox = dvui.box(@src(), .horizontal, .{});
                    defer topbox.deinit();

                    for (0..20) |i| {
                        dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
                    }
                }
            }
        }

        _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

        {
            var hbox3 = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
            defer hbox3.deinit();

            var side_area = dvui.scrollArea(@src(), .{ .scroll_info = siLeft, .frame_viewport = .{ .y = fv.y }, .vertical_bar = .hide, .process_events_after = false }, .{ .min_size_content = .{ .w = left_side_width, .h = 200 }, .expand = .vertical });
            {
                // inside side area
                var sidebox = dvui.box(@src(), .vertical, .{});
                defer sidebox.deinit();

                for (0..20) |i| {
                    dvui.label(@src(), "label {d}", .{i}, .{ .id_extra = i });
                }
            }
            side_area.deinit();

            _ = dvui.spacer(@src(), .{ .min_size_content = .all(10) });

            {
                var scontainer = dvui.ScrollContainerWidget.init(@src(), siMain, .{ .scroll_area = &main_area, .frame_viewport = fv, .event_rect = main_area.data().borderRectScale().r }, .{ .expand = .both });
                scontainer.install();
                defer scontainer.deinit();
                scontainer.processEvents();
                scontainer.processVelocity();

                {
                    // inside main area
                    var mainbox = dvui.box(@src(), .vertical, .{});
                    defer mainbox.deinit();
                    {
                        var mainbox2 = dvui.box(@src(), .horizontal, .{});
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

const std = @import("std");
const dvui = @import("../dvui.zig");
const ScrollInfo = dvui.ScrollInfo;
