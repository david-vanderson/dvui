const RadioChoice = enum(u8) {
    one = 1,
    two,
    _,
};

var checkbox_bool: bool = false;
var radio_choice: RadioChoice = @enumFromInt(0);

/// ![image](Examples-menus.png)
pub fn menus() void {
    var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .margin = .{ .x = 4 } });
    defer vbox.deinit();

    {
        const ctext = dvui.context(@src(), .{ .rect = vbox.data().borderRectScale().r }, .{});
        defer ctext.deinit();

        if (ctext.activePoint()) |cp| {
            var fw2 = dvui.floatingMenu(@src(), .{ .from = Rect.Natural.fromPoint(cp) }, .{});
            defer fw2.deinit();

            submenus();
            _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            if ((dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal })) != null) {
                fw2.close();
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer hbox.deinit();
        {
            var m = dvui.menu(@src(), .horizontal, .{});
            defer m.deinit();

            if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();

                submenus();

                _ = dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});

                if (dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
                    fw.close();
                    Examples.show_dialog = true;
                }

                if (dvui.menuItemLabel(@src(), "Focus Tab 3", .{}, .{ .expand = .horizontal }) != null) {
                    fw.close();
                    if (dvui.dataGet(null, vbox.data().id, "tab3_id", dvui.Id)) |wid| {
                        const subwindowId = dvui.dataGet(null, vbox.data().id, "tab3_subwindow_id", dvui.Id) orelse unreachable;
                        dvui.focusWidget(wid, subwindowId, null);
                    }
                }

                if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                    fw.close();
                }
            }

            if (dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                _ = dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
                _ = dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
                _ = dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
            }

            if (dvui.menuItemLabel(@src(), "Log", .{}, .{ .margin = .{ .x = 10, .w = 10 } })) |_| {}
        }

        dvui.labelNoFmt(@src(), "Right click for a context menu", .{}, .{ .gravity_x = 1.0 });
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(12) });

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .border = dvui.Rect.all(1), .min_size_content = .{ .h = 50 }, .max_size_content = .width(300) });
        defer hbox.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("This box has a simple tooltip.", .{});
        tl.deinit();

        dvui.tooltip(@src(), .{ .active_rect = hbox.data().borderRectScale().r }, "{s}", .{"Simple Tooltip"}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(4) });

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .border = dvui.Rect.all(1), .min_size_content = .{ .h = 50 }, .max_size_content = .width(300) });
        defer hbox.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("This box has a complex tooltip with a fade in and nested tooltip.", .{});
        tl.deinit();

        {
            var tt: dvui.FloatingTooltipWidget = .init(@src(), .{
                .active_rect = hbox.data().borderRectScale().r,
                .interactive = true,
            }, .{ .background = false, .border = .{} });
            defer tt.deinit();
            if (tt.shown()) {
                var animator = dvui.animate(@src(), .{ .kind = .alpha, .duration = 250_000 }, .{ .expand = .both });
                defer animator.deinit();

                var vbox2 = dvui.box(@src(), .{}, dvui.FloatingTooltipWidget.defaults.override(.{ .expand = .both }));
                defer vbox2.deinit();

                var tl2 = dvui.textLayout(@src(), .{}, .{ .background = false });
                tl2.addText("This is the tooltip text", .{});
                tl2.deinit();

                _ = dvui.checkbox(@src(), &checkbox_bool, "Checkbox", .{});
                {
                    var tt2: dvui.FloatingTooltipWidget = .init(@src(), .{
                        .active_rect = tt.data().borderRectScale().r,
                    }, .{ .max_size_content = .width(200), .box_shadow = .{} });
                    defer tt2.deinit();
                    if (tt2.shown()) {
                        var tl3 = dvui.textLayout(@src(), .{}, .{ .background = false });
                        tl3.addText("Text in a nested tooltip with box shadow", .{});
                        tl3.deinit();
                    }
                }
            }
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(12) });

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        const layout_dir = dvui.dataGetPtrDefault(null, hbox.data().id, "layout_dir", dvui.enums.Direction, .horizontal);
        const active_tab = dvui.dataGetPtrDefault(null, hbox.data().id, "active_tab", usize, 0);
        {
            defer hbox.deinit();
            var group = dvui.radioGroup(@src(), .{}, .{ .label = .{ .text = "Layout" } });
            defer group.deinit();
            const entries = [_][]const u8{ "Horizontal", "Vertical" };
            for (0..2) |i| {
                if (dvui.radio(@src(), @intFromEnum(layout_dir.*) == i, entries[i], .{ .id_extra = i })) {
                    layout_dir.* = @enumFromInt(i);
                }
            }
        }
        // reverse orientation because horizontal tabs go above content
        var tbox = dvui.box(@src(), .{ .dir = if (layout_dir.* == .vertical) .horizontal else .vertical }, .{ .max_size_content = .{ .w = 400, .h = 200 } });
        defer tbox.deinit();

        {
            var tabs = dvui.tabs(@src(), .{ .dir = layout_dir.* }, .{ .expand = if (layout_dir.* == .horizontal) .horizontal else .vertical });
            defer tabs.deinit();

            inline for (0..8) |i| {
                const tabname = std.fmt.comptimePrint("Tab {d}", .{i});
                if (i != 3) {
                    // easy label only
                    if (tabs.addTabLabel(active_tab.* == i, tabname)) {
                        active_tab.* = i;
                    }
                } else {
                    // directly put whatever in the tab
                    var tab = tabs.addTab(active_tab.* == i, .{});
                    defer tab.deinit();

                    // store widget id and subwindow id for later focusing
                    dvui.dataSet(null, vbox.data().id, "tab3_id", tab.data().id);
                    dvui.dataSet(null, vbox.data().id, "tab3_subwindow_id", dvui.subwindowCurrentId());

                    var tab_box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                    defer tab_box.deinit();

                    dvui.icon(@src(), "cycle", entypo.cycle, .{}, .{});

                    _ = dvui.spacer(@src(), .{ .min_size_content = .width(4) });

                    var label_opts = tab.data().options.strip();
                    if (dvui.captured(tab.data().id)) {
                        label_opts.color_text = (dvui.Options{}).color(.text_press);
                    }

                    dvui.labelNoFmt(@src(), tabname, .{}, label_opts);

                    if (tab.clicked()) {
                        active_tab.* = i;
                    }
                }
            }
        }

        {
            var border = dvui.Rect.all(1);
            switch (layout_dir.*) {
                .horizontal => border.y = 0,
                .vertical => border.x = 0,
            }
            var vbox3 = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window, .border = border, .role = .tab_panel });
            defer vbox3.deinit();

            dvui.label(@src(), "This is tab {d}", .{active_tab.*}, .{ .expand = .both, .gravity_x = 0.5, .gravity_y = 0.5 });
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(12) });

    focus();
}

pub fn submenus() void {
    if (dvui.menuItemLabel(@src(), "Submenu...", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
        var fw2 = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw2.deinit();

        submenus();

        if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
            fw2.close();
        }

        if (dvui.menuItemLabel(@src(), "Dialog", .{}, .{ .expand = .horizontal }) != null) {
            fw2.close();
            Examples.show_dialog = true;
        }
    }
}

pub fn focus() void {
    if (dvui.expander(@src(), "Changing Focus", .{}, .{ .expand = .horizontal })) {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .margin = .{ .x = 10 } });
        defer b.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("Each time this section is expanded, the first text entry will be focused", .{});
        tl.deinit();

        var te = dvui.textEntry(@src(), .{}, .{});
        const teId = te.data().id;
        {
            defer te.deinit();
            // firstFrame must be called before te.deinit()
            if (dvui.firstFrame(te.data().id)) {
                dvui.focusWidget(te.data().id, null, null);
            }
        }

        // Get a unique Id without making a widget
        const uniqueId = dvui.parentGet().extendId(@src(), 0);

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            if (dvui.button(@src(), "Focus Next textEntry", .{}, .{})) {
                // grab id from previous frame
                if (dvui.dataGet(null, uniqueId, "next_text_entry_id", dvui.Id)) |id| {
                    dvui.focusWidget(id, null, null);
                }
            }

            if (dvui.button(@src(), "Focus Prev textEntry", .{}, .{})) {
                dvui.focusWidget(teId, null, null);
            }
        }

        var te2 = dvui.textEntry(@src(), .{}, .{});

        // save id for next frame
        dvui.dataSet(null, uniqueId, "next_text_entry_id", te2.data().id);

        te2.deinit();
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    {
        var b = dvui.box(@src(), .{}, .{ .margin = .{ .x = 10, .y = 2 }, .border = dvui.Rect.all(1) });
        defer b.deinit();

        const last_focus_id = dvui.lastFocusedIdInFrame();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("This shows how to detect if any widgets in a dynamic extent have focus.", .{});
        tl.deinit();

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();

            for (0..6) |i| {
                const str = switch (i) {
                    0 => "0",
                    1 => "1",
                    2 => "2",
                    3 => "3",
                    4 => "4",
                    5 => "5",
                    else => unreachable,
                };
                _ = dvui.button(@src(), str, .{}, .{ .id_extra = i });
            }
        }

        const have_focus = dvui.lastFocusedIdInFrameSince(last_focus_id) != null;
        dvui.label(@src(), "Anything here with focus: {s}", .{if (have_focus) "Yes" else "No"}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal });
        defer b.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .background = false });
        tl.addText("Hover highlighting a box around widgets:", .{});
        tl.deinit();

        var hbox = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .padding = dvui.Rect.all(4) });
        hbox.install();
        defer hbox.deinit();
        const evts = dvui.events();
        for (evts) |*e| {
            if (!dvui.eventMatchSimple(e, hbox.data())) {
                continue;
            }

            if (e.evt == .mouse and e.evt.mouse.action == .position) {
                hbox.data().options.background = true;
                hbox.data().options.color_fill = dvui.themeGet().color(.content, .fill_hover);
            }
        }
        hbox.drawBackground();

        var group = dvui.radioGroup(@src(), .{}, .{ .label = .{ .text = "Radio buttons" } });
        defer group.deinit();
        inline for (@typeInfo(RadioChoice).@"enum".fields, 0..) |field, i| {
            if (dvui.radio(@src(), radio_choice == @as(RadioChoice, @enumFromInt(field.value)), "Radio " ++ field.name, .{ .id_extra = i })) {
                radio_choice = @enumFromInt(field.value);
            }
        }
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG menus" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 300, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            menus();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-menus.png");
}
const std = @import("std");
const dvui = @import("../dvui.zig");
const entypo = dvui.entypo;
const Rect = dvui.Rect;
const Examples = @import("../Examples.zig");
