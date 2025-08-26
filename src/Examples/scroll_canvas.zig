/// ![image](Examples-scrollCanvas.png)
pub fn scrollCanvas() void {
    var vbox = dvui.box(@src(), .{}, .{ .expand = .both });
    defer vbox.deinit();

    const scroll_info = dvui.dataGetPtrDefault(null, vbox.data().id, "scroll_info", ScrollInfo, .{ .vertical = .given, .horizontal = .given });
    const origin = dvui.dataGetPtrDefault(null, vbox.data().id, "origin", Point, .{});
    const scale = dvui.dataGetPtrDefault(null, vbox.data().id, "scale", f32, 1.0);
    const boxes = dvui.dataGetSliceDefault(null, vbox.data().id, "boxes", []Point, &.{ .{ .x = 50, .y = 10 }, .{ .x = 80, .y = 150 } });
    const box_contents = dvui.dataGetSliceDefault(null, vbox.data().id, "box_contents", []u8, &.{ 1, 3 });

    const drag_box_window = dvui.dataGetPtrDefault(null, vbox.data().id, "drag_box_window", usize, 0);
    const drag_box_content = dvui.dataGetPtrDefault(null, vbox.data().id, "drag_box_content", usize, 0);

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .style = .window });
    tl.addText("Click-drag to pan\n", .{});
    tl.addText("Ctrl-wheel to zoom\n", .{});
    tl.addText("Drag blue cubes from box to box\n\n", .{});
    tl.format("Virtual size {d}x{d}\n", .{ scroll_info.virtual_size.w, scroll_info.virtual_size.h }, .{});
    tl.format("Scroll Offset {d}x{d}\n", .{ scroll_info.viewport.x, scroll_info.viewport.y }, .{});
    tl.format("Origin {d}x{d}\n", .{ origin.x, origin.y }, .{});
    tl.format("Scale {d}", .{scale.*}, .{});
    tl.deinit();

    var scrollArea = dvui.scrollArea(@src(), .{ .scroll_info = scroll_info }, .{ .style = .content, .min_size_content = .{ .w = 300, .h = 300 } });
    var scrollContainer = &scrollArea.scroll.?;

    // can use this to convert between viewport/virtual_size and screen coords
    const scrollRectScale = scrollContainer.screenRectScale(.{});

    var scaler = dvui.scale(@src(), .{ .scale = scale }, .{ .rect = .{ .x = -origin.x, .y = -origin.y } });

    // can use this to convert between data and screen coords
    const dataRectScale = scaler.screenRectScale(.{});

    // get current mouse position
    var mousePosPhysical: dvui.Point.Physical = .{};
    var mousePosData: dvui.Point = .{};
    for (dvui.events()) |*e| {
        // using eventMatch means we will only get the mouse position if it is
        // inside scrollContainer, and not in a floating subwindow above or
        // captured by another widget
        if (!dvui.eventMatchSimple(e, scrollContainer.data())) {
            continue;
        }

        if (e.evt == .mouse and e.evt.mouse.action == .position) {
            mousePosPhysical = e.evt.mouse.p;
            mousePosData = dataRectScale.pointFromPhysical(mousePosPhysical);
        }
    }

    dvui.Path.stroke(.{ .points = &.{
        dataRectScale.pointToPhysical(.{ .x = -10 }),
        dataRectScale.pointToPhysical(.{ .x = 10 }),
    } }, .{ .thickness = 1, .color = dvui.themeGet().color(.control, .text) });

    dvui.Path.stroke(.{ .points = &.{
        dataRectScale.pointToPhysical(.{ .y = -10 }),
        dataRectScale.pointToPhysical(.{ .y = 10 }),
    } }, .{ .thickness = 1, .color = dvui.themeGet().color(.control, .text) });

    // keep record of bounding box
    var mbbox: ?Rect.Physical = null;

    const evts = dvui.events();

    const dragging_box = dvui.dragName("box_transfer");
    if (dragging_box) {
        // draw a half-opaque box to show we are dragging
        // put it in a floating widget so it draws above stuff we do later
        // turn off mouse events so mouse release goes to what is under it

        var fwd: dvui.WidgetData = undefined;

        const mouse_point = dvui.currentWindow().mouse_pt.toNatural().diff(.{ .x = 10, .y = 10 });
        var fw = dvui.FloatingWidget.init(@src(), .{ .mouse_events = false }, .{ .rect = Rect.fromPoint(.cast(mouse_point)), .min_size_content = .all(20), .background = true, .color_fill = dvui.themeGet().focus.opacity(0.5), .data_out = &fwd });
        fw.install();
        fw.deinit();

        // We want to get mouse motion events during the drag as if we had
        // capture.  So don't call eventMatch, we are only going to passively
        // observe mouse motion.
        for (evts) |*e| {
            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .motion) {
                        dvui.scrollDrag(.{
                            .mouse_pt = me.p,
                            .screen_rect = fwd.borderRectScale().r,
                        });
                    }
                },
                else => {},
            }
        }
    }

    for (boxes, 0..) |*b, i| {
        var dragBox = dvui.box(@src(), .{}, .{
            .id_extra = i,
            .rect = dvui.Rect{ .x = b.x, .y = b.y },
            .padding = .{ .h = 5, .w = 5, .x = 5, .y = 5 },
            .background = true,
            .style = .window,
            .border = .{ .h = 1, .w = 1, .x = 1, .y = 1 },
            .corner_radius = .{ .h = 5, .w = 5, .x = 5, .y = 5 },
            .color_border = if (dragging_box) dvui.themeGet().focus else null,
            .box_shadow = .{},
        });

        const boxRect = dragBox.data().rectScale().r;
        if (mbbox) |bb| {
            mbbox = bb.unionWith(boxRect);
        } else {
            mbbox = boxRect;
        }

        dvui.label(@src(), "Box {d} {d:0>3.0}x{d:0>3.0}", .{ i, b.x, b.y }, .{});

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();
            if (dvui.buttonIcon(
                @src(),
                "left",
                entypo.arrow_left,
                .{},
                .{},
                .{ .min_size_content = .{ .h = 20 } },
            )) {
                b.x -= 10;
            }

            if (dvui.buttonIcon(
                @src(),
                "right",
                entypo.arrow_right,
                .{},
                .{},
                .{ .min_size_content = .{ .h = 20 } },
            )) {
                b.x += 10;
            }
        }

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = dvui.Rect.all(4), .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4), .background = true, .style = .window });
            defer hbox.deinit();

            for (evts) |*e| {
                if (!dvui.eventMatchSimple(e, hbox.data())) {
                    continue;
                }
            }

            for (0..box_contents[i]) |k| {
                const dragging_this = dragging_box and i == drag_box_window.* and k == drag_box_content.*;

                if (k > 0) {
                    _ = dvui.spacer(@src(), .{ .min_size_content = .width(5), .id_extra = k });
                }
                const col = if (dragging_this) dvui.Color.lime.opacity(0.5) else dvui.Color.blue;
                var dbox = dvui.box(@src(), .{}, .{ .id_extra = k, .min_size_content = .{ .w = 20, .h = 20 }, .background = true, .color_fill = col });
                defer dbox.deinit();

                for (evts) |*e| {
                    if (!dvui.eventMatchSimple(e, dbox.data())) {
                        continue;
                    }

                    switch (e.evt) {
                        .mouse => |me| {
                            if (me.action == .press and me.button.pointer()) {
                                e.handle(@src(), dbox.data());
                                dvui.captureMouse(dbox.data(), e.num);
                                dvui.dragPreStart(me.p, .{ .name = "box_transfer" });
                            } else if (me.action == .release and me.button.pointer()) {
                                if (dvui.captured(dbox.data().id)) {
                                    // mouse up before drag started
                                    e.handle(@src(), dbox.data());
                                    dvui.captureMouse(null, e.num);
                                    dvui.dragEnd();
                                }
                            } else if (me.action == .motion) {
                                if (dvui.captured(dbox.data().id)) {
                                    e.handle(@src(), dbox.data());
                                    if (dvui.dragging(me.p, null)) |_| {
                                        // started the drag
                                        drag_box_window.* = i;
                                        drag_box_content.* = k;
                                        // give up capture so target can get mouse events, but don't end drag
                                        dvui.captureMouse(null, e.num);
                                    }
                                }
                            } else if (me.action == .position) {
                                dvui.cursorSet(.hand);
                            }
                        },
                        else => {},
                    }
                }
            }
        }

        // process events to drag the box around
        for (evts) |*e| {
            if (!dragBox.matchEvent(e)) continue;

            switch (e.evt) {
                .mouse => |me| {
                    if (me.action == .press and me.button.pointer()) {
                        e.handle(@src(), dragBox.data());
                        dvui.captureMouse(dragBox.data(), e.num);
                        const offset = me.p.diff(dragBox.data().rectScale().r.topLeft()); // pixel offset from dragBox corner
                        dvui.dragPreStart(me.p, .{ .offset = offset });
                    } else if (me.action == .release and me.button.pointer()) {
                        if (dvui.captured(dragBox.data().id)) {
                            e.handle(@src(), dragBox.data());
                            dvui.captureMouse(null, e.num);
                            dvui.dragEnd();
                        }
                    } else if (me.action == .motion) {
                        if (dvui.captured(dragBox.data().id)) {
                            if (dvui.dragging(me.p, null)) |_| {
                                const p = me.p.diff(dvui.dragOffset()); // pixel corner we want
                                b.* = dataRectScale.pointFromPhysical(p);
                                dvui.refresh(null, @src(), scrollContainer.data().id);

                                dvui.scrollDrag(.{
                                    .mouse_pt = e.evt.mouse.p,
                                    .screen_rect = dragBox.data().rectScale().r,
                                });
                            }
                        }
                    }
                },
                else => {},
            }
        }

        // Check if a drag is over or dropped on this box
        if (dragging_box) {
            for (evts) |*e| {
                if (!dvui.eventMatch(e, .{ .id = dragBox.data().id, .r = dragBox.data().borderRectScale().r, .drag_name = "box_transfer" })) {
                    continue;
                }

                switch (e.evt) {
                    .mouse => |me| {
                        if (me.action == .release and me.button.pointer()) {
                            e.handle(@src(), dragBox.data());
                            dvui.dragEnd();
                            dvui.refresh(null, @src(), dragBox.data().id);

                            if (drag_box_window.* != i) {
                                // move box to new home
                                box_contents[drag_box_window.*] -= 1;
                                box_contents[1 - drag_box_window.*] += 1;
                            }
                        } else if (me.action == .position) {
                            dvui.cursorSet(.crosshair);
                            // the drag is hovered above us, draw to indicate that
                            const rs = dragBox.data().contentRectScale();
                            rs.r.fill(dragBox.data().options.corner_radiusGet().scale(rs.s, Rect.Physical), .{ .color = dvui.themeGet().focus.opacity(0.2) });
                        }
                    },
                    else => {},
                }
            }
        }

        dragBox.deinit();
    }

    var zoom: f32 = 1;
    var zoomP: Point.Physical = .{};

    // process scroll area events after boxes so the boxes get first pick (so
    // the button works)
    for (evts) |*e| {
        if (!scrollContainer.matchEvent(e))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                if (me.action == .press and me.button.pointer()) {
                    e.handle(@src(), scrollContainer.data());
                    dvui.captureMouse(scrollContainer.data(), e.num);
                    dvui.dragPreStart(me.p, .{});
                } else if (me.action == .release and me.button.pointer()) {
                    if (dvui.captured(scrollContainer.data().id)) {
                        e.handle(@src(), scrollContainer.data());
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                    }
                } else if (me.action == .motion) {
                    if (me.button.touch()) {
                        // eat touch motion events so they don't scroll
                        e.handle(@src(), scrollContainer.data());
                    }
                    if (dvui.captured(scrollContainer.data().id)) {
                        if (dvui.dragging(me.p, null)) |dps| {
                            e.handle(@src(), scrollContainer.data());
                            const rs = scrollRectScale;
                            scroll_info.viewport.x -= dps.x / rs.s;
                            scroll_info.viewport.y -= dps.y / rs.s;
                            dvui.refresh(null, @src(), scrollContainer.data().id);
                        }
                    }
                } else if (me.action == .wheel_y and me.mod.matchBind("ctrl/cmd")) {
                    e.handle(@src(), scrollContainer.data());
                    const base: f32 = 1.01;
                    const zs = @exp(@log(base) * me.action.wheel_y);
                    if (zs != 1.0) {
                        zoom *= zs;
                        zoomP = me.p;
                    }
                }
            },
            else => {},
        }
    }

    if (zoom != 1.0) {
        // scale around mouse point
        // first get data point of mouse
        const prevP = dataRectScale.pointFromPhysical(zoomP);

        // scale
        var pp = prevP.scale(1 / scale.*, Point);
        scale.* *= zoom;
        pp = pp.scale(scale.*, Point);

        // get where the mouse would be now
        const newP = dataRectScale.pointToPhysical(pp);

        // convert both to viewport
        const diff = scrollRectScale.pointFromPhysical(newP).diff(scrollRectScale.pointFromPhysical(zoomP));
        scroll_info.viewport.x += diff.x;
        scroll_info.viewport.y += diff.y;

        dvui.refresh(null, @src(), scrollContainer.data().id);
    }

    scaler.deinit();

    const scrollContainerId = scrollContainer.data().id;

    // deinit is where scroll processes events
    scrollArea.deinit();

    // don't mess with scrolling if we aren't being shown (prevents weirdness
    // when starting out)
    if (!scroll_info.viewport.empty()) {
        // add current viewport plus padding
        const pad = 10;
        var bbox = scroll_info.viewport.outsetAll(pad);
        if (mbbox) |bb| {
            // convert bb from screen space to viewport space
            const scrollbbox = scrollRectScale.rectFromPhysical(bb);
            bbox = bbox.unionWith(scrollbbox);
        }

        // adjust top if needed
        if (bbox.y != 0) {
            const adj = -bbox.y;
            scroll_info.virtual_size.h += adj;
            scroll_info.viewport.y += adj;
            origin.y -= adj;
            dvui.refresh(null, @src(), scrollContainerId);
        }

        // adjust left if needed
        if (bbox.x != 0) {
            const adj = -bbox.x;
            scroll_info.virtual_size.w += adj;
            scroll_info.viewport.x += adj;
            origin.x -= adj;
            dvui.refresh(null, @src(), scrollContainerId);
        }

        // adjust bottom if needed
        if (bbox.h != scroll_info.virtual_size.h) {
            scroll_info.virtual_size.h = bbox.h;
            dvui.refresh(null, @src(), scrollContainerId);
        }

        // adjust right if needed
        if (bbox.w != scroll_info.virtual_size.w) {
            scroll_info.virtual_size.w = bbox.w;
            dvui.refresh(null, @src(), scrollContainerId);
        }
    }

    dvui.label(@src(), "Mouse Data Coords {d:0.2}x{d:0.2}", .{ mousePosData.x, mousePosData.y }, .{});
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG scrollCanvas" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 300, .h = 400 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window });
            defer box.deinit();
            scrollCanvas();
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-scrollCanvas.png");
}

const dvui = @import("../dvui.zig");
const entypo = dvui.entypo;
const Point = dvui.Point;
const Rect = dvui.Rect;
const ScrollInfo = dvui.ScrollInfo;
