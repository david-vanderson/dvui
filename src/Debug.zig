open: bool = false,
options_editor_open: bool = false,
options_override_list_open: bool = false,
show_frame_times: bool = false,

/// 0 means no widget is selected
widget_id: dvui.Id = .zero,
target: DebugTarget = .none,

/// All functions using the parent are invalid
target_wd: ?dvui.WidgetData = null,

/// Uses `gpa` allocator
///
/// The name slice is also duplicated by the `gpa` allocator
under_mouse_stack: std.ArrayListUnmanaged(struct { id: dvui.Id, name: []const u8 }) = .empty,

/// Uses `gpa` allocator
options_override: std.AutoHashMapUnmanaged(dvui.Id, struct { Options, std.builtin.SourceLocation }) = .empty,

toggle_mutex: std.Thread.Mutex = .{},
log_refresh: bool = false,
log_events: bool = false,

/// A panic will be called from within the targeted widget
widget_panic: bool = false,

/// when true, left mouse button works like a finger
touch_simulate_events: bool = false,
touch_simulate_down: bool = false,

const Debug = @This();

pub const DebugTarget = enum {
    none,
    focused,
    mouse_until_esc,
    mouse_until_click,
    mouse_quitting,

    pub fn mouse(self: DebugTarget) bool {
        return self == .mouse_until_click or self == .mouse_until_esc or self == .mouse_quitting;
    }
};

pub fn reset(self: *Debug, gpa: std.mem.Allocator) void {
    if (self.target.mouse()) {
        for (self.under_mouse_stack.items) |item| {
            gpa.free(item.name);
        }
        self.under_mouse_stack.clearRetainingCapacity();
    }
    self.target_wd = null;
}

pub fn deinit(self: *Debug, gpa: std.mem.Allocator) void {
    for (self.under_mouse_stack.items) |item| {
        gpa.free(item.name);
    }
    self.under_mouse_stack.clearAndFree(gpa);
    self.options_override.deinit(gpa);
}

/// Returns the previous value
///
/// called from any thread
pub fn logEvents(self: *Debug, val: ?bool) bool {
    self.toggle_mutex.lock();
    defer self.toggle_mutex.unlock();

    const previous = self.log_events;
    if (val) |v| {
        self.log_events = v;
    }

    return previous;
}

/// Returns the previous value
///
/// called from any thread
pub fn logRefresh(self: *Debug, val: ?bool) bool {
    self.toggle_mutex.lock();
    defer self.toggle_mutex.unlock();

    const previous = self.log_refresh;
    if (val) |v| {
        self.log_refresh = v;
    }

    return previous;
}

/// Returns early if `Debug.open` is `false`
pub fn show(self: *Debug) void {
    if (self.show_frame_times) {
        self.showFrameTimes();
    }

    if (!self.open) return;

    if (self.target == .mouse_quitting) {
        self.target = .none;
    }

    // disable so the widgets we are about to use to display this data
    // don't modify the data, otherwise our iterator will get corrupted and
    // even if you search for a widget here, the data won't be available
    var debug_target = self.target;
    self.target = .none;
    defer self.target = debug_target;

    var float = dvui.floatingWindow(@src(), .{ .open_flag = &self.open }, .{ .min_size_content = .{ .w = 300, .h = 600 } });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("DVUI Debug", "", &self.open));

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        var log_refresh = self.logRefresh(null);
        if (dvui.checkbox(@src(), &log_refresh, "Refresh Logging", .{ .gravity_y = 0.5 })) {
            _ = self.logRefresh(log_refresh);
        }

        var custom_label: ?[]const u8 = null;
        var max_fps: f32 = 60;
        if (dvui.currentWindow().max_fps) |mfps| {
            max_fps = mfps;
        } else {
            custom_label = "max fps: unlimited";
        }

        if (dvui.sliderEntry(@src(), "max fps: {d:0.0}", .{ .value = &max_fps, .min = 1, .max = 60, .interval = 1, .label = custom_label }, .{ .min_size_content = .width(200), .gravity_y = 0.5 })) {
            if (max_fps >= 60) {
                dvui.currentWindow().max_fps = null;
            } else {
                dvui.currentWindow().max_fps = max_fps;
            }
        }

        if (dvui.button(@src(), "Frame Times", .{}, .{})) {
            self.show_frame_times = !self.show_frame_times;
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        var log_events = self.logEvents(null);
        if (dvui.checkbox(@src(), &log_events, "Event Logging", .{})) {
            _ = self.logEvents(log_events);
        }

        var wd: dvui.WidgetData = undefined;
        _ = dvui.checkbox(@src(), &dvui.currentWindow().debug.touch_simulate_events, "Simulate Touch With Mouse", .{ .data_out = &wd });

        dvui.tooltip(@src(), .{ .active_rect = wd.borderRectScale().r }, "mouse drag will scroll\ntext layout/entry have draggables and menu", .{}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .all(4) });

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.labelNoFmt(@src(), "Widget Id:", .{}, .{ .gravity_y = 0.5 });

        var buf = [_]u8{0} ** 20;
        if (self.widget_id != .zero) {
            _ = std.fmt.bufPrint(&buf, "{x}", .{self.widget_id}) catch unreachable;
        }
        var te = dvui.textEntry(@src(), .{
            .text = .{ .buffer = &buf },
        }, .{});
        te.deinit();

        self.widget_id = @enumFromInt(std.fmt.parseInt(u64, std.mem.sliceTo(&buf, 0), 16) catch 0);

        var temp = (debug_target == .focused);
        if (dvui.checkbox(@src(), &temp, "Follow Focus", .{ .gravity_y = 0.5 })) {
            debug_target = if (debug_target == .focused) .none else .focused;
        }
    }

    var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal });
    tl.install(.{});

    {
        var corner_box = dvui.box(@src(), .{}, .{ .gravity_x = 1, .margin = .all(8) });
        defer corner_box.deinit();

        var color: ?dvui.Color = null;
        if (self.widget_id == .zero) {
            // blend text and control colors
            const opts: Options = .{};
            color = .average(opts.color(.text), opts.color(.fill));
        }

        if (dvui.button(@src(), "Edit Options", .{}, .{ .gravity_x = 1, .color_text = color })) {
            if (self.widget_id != .zero) {
                self.options_editor_open = true;
            } else {
                dvui.dialog(@src(), .{}, .{ .title = "Disabled", .message = "Need valid widget Id to edit options" });
            }
        }

        self.widget_panic = false;
        if (dvui.button(@src(), "Panic", .{}, .{ .gravity_x = 1, .color_text = color })) {
            if (self.widget_id != .zero) {
                self.widget_panic = true;
            } else {
                dvui.dialog(@src(), .{}, .{ .title = "Disabled", .message = "Need valid widget Id to panic" });
            }
        }
    }

    if (tl.touchEditing()) |floating_widget| {
        defer floating_widget.deinit();
        tl.touchEditingMenu();
    }
    tl.processEvents();

    if (self.target_wd) |wd| {
        const rs = wd.rectScale();
        tl.format(
            \\{s}
            \\role {?t}
            \\{s}:{d}
            \\min {f}
            \\expand {any}
            \\gravity x {d:0>.2} y {d:0>.2}
            \\margin {f}
            \\border {f}
            \\padding {f}
            \\rs.s {d}
            \\rs.r {f}
        , .{
            wd.options.name orelse "???",
            wd.options.role,
            wd.src.file,
            wd.src.line,
            wd.min_size,
            wd.options.expandGet(),
            wd.options.gravityGet().x,
            wd.options.gravityGet().y,
            wd.options.marginGet(),
            wd.options.borderGet(),
            wd.options.paddingGet(),
            rs.s,
            rs.r,
        }, .{});
    }
    tl.deinit();

    if (self.target_wd) |wd| {
        if (self.options_editor_open) {
            var options, _ = self.options_override.get(wd.id) orelse .{ wd.options, undefined };

            var editor_float = dvui.floatingWindow(@src(), .{
                .open_flag = &self.options_editor_open,
                .stay_above_parent_window = true,
            }, .{});
            defer editor_float.deinit();

            const title = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{x} {s} (+{d})", .{
                wd.id,
                wd.options.name orelse "???",
                wd.options.idExtra(),
            }) catch wd.options.name orelse "???";
            defer dvui.currentWindow().lifo().free(title);

            editor_float.dragAreaSet(dvui.windowHeader(title, "", &self.options_editor_open));

            if (optionsEditor(&options, &wd)) {
                self.options_override.put(dvui.currentWindow().gpa, wd.id, .{ options, wd.src }) catch |err| {
                    dvui.logError(@src(), err, "Could not add the override options for {x} {s}", .{ wd.id, wd.options.name orelse "???" });
                };
            }
        }
    } else {
        self.options_editor_open = false;
    }

    if (dvui.button(@src(), if (debug_target == .mouse_until_click) "Stop (Or Left Click)" else "Debug Under Mouse (until click)", .{}, .{})) {
        debug_target = if (debug_target == .mouse_until_click) .none else .mouse_until_click;
    }

    if (dvui.button(@src(), if (debug_target == .mouse_until_esc) "Stop (Or Press Esc)" else "Debug Under Mouse (until esc)", .{}, .{})) {
        debug_target = if (debug_target == .mouse_until_esc) .none else .mouse_until_esc;
    }

    if (dvui.button(@src(), "Show all option overrides", .{}, .{})) {
        self.options_override_list_open = true;
    }

    if (self.options_override_list_open) {
        var list_float = dvui.floatingWindow(@src(), .{
            .open_flag = &self.options_override_list_open,
            .stay_above_parent_window = true,
        }, .{ .min_size_content = .{ .w = 300, .h = 200 } });
        defer list_float.deinit();

        list_float.dragAreaSet(dvui.windowHeader("Options overrides", "", &self.options_override_list_open));

        var scroll = dvui.scrollArea(@src(), .{}, .{ .min_size_content = .{ .h = 200 }, .expand = .both });
        defer scroll.deinit();

        var menu = dvui.menu(@src(), .vertical, .{ .expand = .horizontal });
        defer menu.deinit();

        var it = self.options_override.iterator();
        var remove_override_id: ?dvui.Id = null;
        while (it.next()) |entry| {
            const id = entry.key_ptr.*;
            const options, const src = entry.value_ptr.*;

            const row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = id.asUsize() });
            defer row.deinit();

            var reset_wd: dvui.WidgetData = undefined;
            if (dvui.buttonIcon(@src(), "Reset Option Override", dvui.entypo.back, .{}, .{}, .{
                .gravity_y = 0.5,
                .data_out = &reset_wd,
            })) {
                remove_override_id = id;
            }
            dvui.tooltip(@src(), .{
                .active_rect = reset_wd.borderRectScale().r,
                .position = .vertical,
            }, "Remove the override", .{}, .{});

            var copy_wd: dvui.WidgetData = undefined;
            if (dvui.buttonIcon(@src(), "Copy Option Override", dvui.entypo.copy, .{}, .{}, .{
                .gravity_y = 0.5,
                .data_out = &copy_wd,
            })) {
                copyOptionsToClipboard(src, id, options);
            }
            dvui.tooltip(@src(), .{
                .active_rect = copy_wd.borderRectScale().r,
                .position = .vertical,
            }, "Copy Options struct to clipboard", .{}, .{});

            {
                var button: dvui.ButtonWidget = undefined;
                button.init(@src(), .{}, .{ .expand = .horizontal });
                defer button.deinit();
                button.processEvents();
                button.drawBackground();

                if (button.clicked()) self.widget_id = id;

                const opts: Options = .{};
                const stack = dvui.box(@src(), .{}, .{
                    .expand = .both,
                    .color_fill = if (button.pressed()) opts.color(.fill_press) else null,
                });
                defer stack.deinit();

                dvui.label(@src(), "{x} {s} (+{d})", .{ id, options.name orelse "???", options.idExtra() }, .{ .padding = .all(1) });
                dvui.label(@src(), "{s}:{d}", .{ src.file, src.line }, .{ .font_style = .caption, .padding = .all(1) });
            }
        }
        if (remove_override_id) |id| {
            _ = self.options_override.remove(id);
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false, .min_size_content = .height(200) });
    defer scroll.deinit();

    for (self.under_mouse_stack.items, 0..) |item, i| {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = i });
        defer hbox.deinit();

        if (dvui.buttonIcon(@src(), "find", dvui.entypo.magnifying_glass, .{}, .{}, .{})) {
            self.widget_id = item.id;
        }

        dvui.label(@src(), "{x} {s}", .{ item.id, item.name }, .{ .gravity_y = 0.5 });
    }
}

fn showFrameTimes(self: *Debug) void {
    var float = dvui.floatingWindow(@src(), .{ .open_flag = &self.show_frame_times }, .{ .min_size_content = .width(600) });
    defer float.deinit();

    float.dragAreaSet(dvui.windowHeader("Frame Times", "", &self.show_frame_times));

    {
        var b = dvui.box(@src(), .{}, .{ .expand = .horizontal, .gravity_y = 1.0 });
        defer b.deinit();

        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .both });
        defer tl.deinit();

        tl.addText("Shows time (ms) between Window.begin/end for last 400 frames.", .{});
    }

    const uniqueId = dvui.parentGet().extendId(@src(), 0);

    var data = dvui.dataGetSlice(null, uniqueId, "data", []f64) orelse blk: {
        dvui.dataSetSliceCopies(null, uniqueId, "data", &[1]f64{0}, 400);
        break :blk dvui.dataGetSlice(null, uniqueId, "data", []f64) orelse unreachable;
    };

    const cw = dvui.currentWindow();
    const so_far_nanos = @max(cw.frame_time_ns, cw.backend.nanoTime()) - cw.frame_time_ns;
    const so_far_micros = @as(u32, @intCast(@divFloor(so_far_nanos, 1000)));
    const new_data: f64 = @as(f64, @floatFromInt(so_far_micros)) / 1000.0;

    for (0..data.len - 1) |i| {
        data[i] = data[i + 1];
    }
    data[data.len - 1] = new_data;

    var xs = dvui.currentWindow().arena().alloc(f64, data.len) catch @panic("OOM");
    defer dvui.currentWindow().arena().free(xs);

    for (0..data.len) |i| {
        xs[i] = @floatFromInt(i);
    }

    var yaxis: dvui.PlotWidget.Axis = .{
        .name = "ms",
        .min = 0,
        .max = 50,
    };

    dvui.plotXY(@src(), .{ .xs = xs, .ys = data, .plot_opts = .{ .y_axis = &yaxis } }, .{ .expand = .both, .min_size_content = .height(50), .padding = .{ .y = 10, .h = 10 } });
}

const OptionsEditorTab = enum { layout, style };

/// Returns true if the options was modified
pub fn optionsEditor(self: *Options, wd: *const dvui.WidgetData) bool {
    var changed = false;

    var vbox = dvui.box(@src(), .{}, .{ .name = "Editor Box", .expand = .both });
    defer vbox.deinit();

    const active_tab = dvui.dataGetPtrDefault(null, vbox.data().id, "Tab", OptionsEditorTab, .layout);
    {
        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        tabs.install();
        defer tabs.deinit();

        var button_wd: dvui.WidgetData = undefined;
        if (dvui.buttonIcon(@src(), "Copy Options", dvui.entypo.copy, .{}, .{}, .{ .gravity_x = 1, .data_out = &button_wd })) {
            copyOptionsToClipboard(wd.src, wd.id, self.*);
        }
        dvui.tooltip(@src(), .{
            .active_rect = button_wd.borderRectScale().r,
            .position = .vertical,
        }, "Copy Options struct to clipboard", .{}, .{});

        if (tabs.addTabLabel(active_tab.* == .layout, "Layout")) {
            active_tab.* = .layout;
        }
        if (tabs.addTabLabel(active_tab.* == .style, "Style")) {
            active_tab.* = .style;
        }
    }

    switch (active_tab.*) {
        .layout => {
            if (layoutPage(self, vbox.data().id)) changed = true;
        },
        .style => {
            if (stylePage(self, vbox.data().id)) changed = true;
        },
        // NOTE: name and tag editing have been intentionally skipped as the memory
        //       ownership would be unnecessarily complicated
    }

    return changed;
}

fn copyOptionsToClipboard(src: std.builtin.SourceLocation, id: dvui.Id, options: Options) void {
    dvui.log.debug("Copied Options struct for {s}:{d}", .{ src.file, src.line });
    dvui.toast(@src(), .{ .message = "Options copied to clipboard" });

    var aw = std.Io.Writer.Allocating.init(dvui.currentWindow().lifo());
    defer aw.deinit();
    aw.writer.print("{f}", .{asZigCode(options)}) catch |err| {
        dvui.logError(@src(), err, "Could not write Options struct for {x} {s}", .{ id, options.name orelse "???" });
    };
    dvui.clipboardTextSet(aw.written());
}

fn layoutPage(self: *Options, id: dvui.Id) bool {
    var changed = false;

    const corner_radius_was_null = self.corner_radius == null;
    self.corner_radius = self.corner_radiusGet();
    defer if (corner_radius_was_null and !changed) {
        self.corner_radius = null;
    };
    const corner_radius = &self.corner_radius.?;

    const margin_was_null = self.margin == null;
    self.margin = self.marginGet();
    defer if (margin_was_null and !changed) {
        self.margin = null;
    };
    const margin = &self.margin.?;

    const border_was_null = self.border == null;
    self.border = self.borderGet();
    defer if (border_was_null and !changed) {
        self.border = null;
    };
    const border = &self.border.?;

    const padding_was_null = self.padding == null;
    self.padding = self.paddingGet();
    defer if (padding_was_null and !changed) {
        self.padding = null;
    };
    const padding = &self.padding.?;

    const gravity_y_was_null = self.gravity_y == null;
    self.gravity_y = self.gravityGet().y;
    defer if (gravity_y_was_null and !changed) {
        self.gravity_y = null;
    };
    var grav_y_inv = 1.0 - self.gravity_y.?;
    const gravity_y = &grav_y_inv;

    const gravity_x_was_null = self.gravity_x == null;
    self.gravity_x = self.gravityGet().x;
    defer if (gravity_x_was_null and !changed) {
        self.gravity_x = null;
    };
    const gravity_x = &self.gravity_x.?;

    const rotation_was_null = self.rotation == null;
    self.rotation = self.rotationGet();
    defer if (rotation_was_null and !changed) {
        self.rotation = null;
    };
    const rotation = &self.rotation.?;

    const link_margin = dvui.dataGetPtrDefault(null, id, "link_margin", bool, true);
    const link_border = dvui.dataGetPtrDefault(null, id, "link_border", bool, true);
    const link_padding = dvui.dataGetPtrDefault(null, id, "link_padding", bool, true);
    const link_radius = dvui.dataGetPtrDefault(null, id, "link_radius", bool, true);

    { // First bar
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();

        {
            dvui.labelNoFmt(@src(), "expand", .{}, .{ .gravity_y = 0.5 });
            const expands = std.meta.tags(Options.Expand);
            var dd: dvui.DropdownWidget = undefined;
            dd.init(@src(), .{
                .label = @tagName(self.expandGet()),
                .selected_index = std.mem.indexOfScalar(Options.Expand, expands, self.expandGet()).?,
            }, .{
                .expand = .horizontal,
                .min_size_content = .{ .w = 110 },
                .gravity_y = 0.5,
            });
            defer dd.deinit();
            if (dd.dropped()) {
                for (expands) |new| {
                    if (dd.addChoiceLabel(@tagName(new))) {
                        self.expand = new;
                        changed = true;
                    }
                }
            }
        }

        if (dvui.sliderEntry(@src(), "rotation: {d:0.2}", .{
            .min = std.math.pi * -2,
            .max = std.math.pi * 2,
            .interval = @as(f32, std.math.pi) / 100,
            .value = rotation,
        }, .{ .gravity_y = 0.5 })) {
            changed = true;
        }
    }

    { // Min size
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();

        var has_min_size = self.min_size_content != null;
        if (dvui.checkbox(@src(), &has_min_size, "min size", .{ .gravity_y = 0.5, .min_size_content = .{ .w = 90 } })) {
            if (self.min_size_content) |_| {
                self.min_size_content = null;
            } else {
                self.min_size_content = .all(100);
            }
            changed = true;
        }

        if (self.min_size_content) |*size| {
            if (dvui.sliderEntry(@src(), "width: {d:0.0}", .{ .value = &size.w, .min = 0, .max = 400.0, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
            }
            if (dvui.sliderEntry(@src(), "height: {d:0.0}", .{ .value = &size.h, .min = 0, .max = 400.0, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
            }
        }
    }

    { // Max size
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();

        var has_max_size = self.max_size_content != null;
        if (dvui.checkbox(@src(), &has_max_size, "max size", .{ .gravity_y = 0.5, .min_size_content = .{ .w = 90 } })) {
            if (self.max_size_content) |_| {
                self.max_size_content = null;
            } else {
                self.max_size_content = .size(.all(400));
            }
            changed = true;
        }

        if (self.max_size_content) |*size| {
            if (dvui.sliderEntry(@src(), "width: {d:0.0}", .{ .value = &size.w, .min = 0, .max = 400.0, .interval = 1 }, .{})) {
                changed = true;
            }
            if (dvui.sliderEntry(@src(), "height: {d:0.0}", .{ .value = &size.h, .min = 0, .max = 400.0, .interval = 1 }, .{})) {
                changed = true;
            }
        }
    }

    { // Top Row
        var row = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{});
        defer row.deinit();
        { // Top Left
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "radius: {d:0}", .{ .value = &corner_radius.x, .min = 0, .max = 200, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
                if (link_radius.*) {
                    corner_radius.* = .all(corner_radius.x);
                }
            }
        }
        { // Top Center
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "margin: {d:0.0}", .{ .value = &margin.y, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_margin.*) {
                    margin.* = .all(margin.y);
                }
            }
            if (dvui.sliderEntry(@src(), "border: {d:0.0}", .{ .value = &border.y, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_border.*) {
                    border.* = .all(border.y);
                }
            }
            if (dvui.sliderEntry(@src(), "padding: {d:0.0}", .{ .value = &padding.y, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_padding.*) {
                    padding.* = .all(padding.y);
                }
            }
        }
        { // Top Right
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "radius: {d:0}", .{ .value = &corner_radius.y, .min = 0, .max = 200, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
                if (link_radius.*) {
                    corner_radius.* = .all(corner_radius.y);
                }
            }
        }
    }

    { // Middle Row
        var row = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{});
        defer row.deinit();
        { // Middle Left
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "margin: {d:0.0}", .{ .value = &margin.x, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_margin.*) {
                    margin.* = .all(margin.x);
                }
            }
            if (dvui.sliderEntry(@src(), "border: {d:0.0}", .{ .value = &border.x, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_border.*) {
                    border.* = .all(border.x);
                }
            }
            if (dvui.sliderEntry(@src(), "padding: {d:0.0}", .{ .value = &padding.x, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_padding.*) {
                    padding.* = .all(padding.x);
                }
            }
        }
        { // Middle Center
            var col = dvui.box(@src(), .{ .dir = .horizontal }, .{ .border = .all(1), .expand = .both });
            defer col.deinit();

            if (dvui.slider(@src(), .{ .dir = .vertical, .fraction = gravity_y }, .{ .expand = .vertical })) {
                self.gravity_y.? = 1.0 - gravity_y.*;
                changed = true;
            }

            var side = dvui.box(@src(), .{}, .{ .expand = .both });
            defer side.deinit();

            dvui.labelNoFmt(@src(), "gravity", .{}, .{ .gravity_y = 0.5 });

            if (dvui.slider(@src(), .{ .fraction = gravity_x }, .{ .expand = .horizontal, .gravity_y = 1 })) {
                changed = true;
            }
        }
        { // Middle Right
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "margin: {d:0.0}", .{ .value = &margin.w, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_margin.*) {
                    margin.* = .all(margin.w);
                }
            }
            if (dvui.sliderEntry(@src(), "border: {d:0.0}", .{ .value = &border.w, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_border.*) {
                    border.* = .all(border.w);
                }
            }
            if (dvui.sliderEntry(@src(), "padding: {d:0.0}", .{ .value = &padding.w, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_padding.*) {
                    padding.* = .all(padding.w);
                }
            }
        }
    }

    { // Bottom Row
        var row = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{});
        defer row.deinit();
        { // Bottom Left
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "radius: {d:0}", .{ .value = &corner_radius.h, .min = 0, .max = 200, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
                if (link_radius.*) {
                    corner_radius.* = .all(corner_radius.h);
                }
            }
        }
        { // Bottom Center
            var col = dvui.box(@src(), .{}, .{ .border = .all(1) });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "margin: {d:0.0}", .{ .value = &margin.h, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_margin.*) {
                    margin.* = .all(margin.h);
                }
            }
            if (dvui.sliderEntry(@src(), "border: {d:0.0}", .{ .value = &border.h, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_border.*) {
                    border.* = .all(border.h);
                }
            }
            if (dvui.sliderEntry(@src(), "padding: {d:0.0}", .{ .value = &padding.h, .min = 0, .max = 20.0, .interval = 1 }, .{})) {
                changed = true;
                if (link_padding.*) {
                    padding.* = .all(padding.h);
                }
            }
        }
        { // Bottom Right
            var col = dvui.box(@src(), .{}, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "radius: {d:0}", .{ .value = &corner_radius.w, .min = 0, .max = 200, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
                if (link_radius.*) {
                    corner_radius.* = .all(corner_radius.w);
                }
            }
        }
    }

    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer row.deinit();

        dvui.labelNoFmt(@src(), "Link: ", .{}, .{});

        if (dvui.checkbox(@src(), link_margin, "margin", .{})) {
            margin.* = .all(margin.x);
            changed = true;
        }
        if (dvui.checkbox(@src(), link_border, "border", .{})) {
            border.* = .all(border.x);
            changed = true;
        }
        if (dvui.checkbox(@src(), link_padding, "padding", .{})) {
            padding.* = .all(padding.x);
            changed = true;
        }
        if (dvui.checkbox(@src(), link_radius, "radius", .{})) {
            corner_radius.* = .all(corner_radius.x);
            changed = true;
        }
    }

    return changed;
}

fn stylePage(self: *Options, id: dvui.Id) bool {
    var changed = false;

    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
    {
        dvui.label(@src(), "Font Style", .{}, .{ .gravity_y = 0.5 });
        const styles = std.meta.tags(dvui.Theme.Style.Name);
        var dd: dvui.DropdownWidget = undefined;
        dd.init(@src(), .{
            .label = if (self.style) |style| @tagName(style) else "null",
        }, .{
            .min_size_content = .{ .w = 150 },
            .gravity_y = 0.5,
        });
        defer dd.deinit();
        if (dd.dropped()) {
            if (dd.addChoiceLabel("Set to null")) {
                self.font_style = null;
                changed = true;
            }
            for (styles) |style| {
                if (dd.addChoiceLabel(@tagName(style))) {
                    self.style = style;
                    changed = true;
                }
            }
        }
    }

    var background = self.backgroundGet();
    if (dvui.checkbox(@src(), &background, "background", .{ .gravity_y = 0.5 })) {
        changed = true;
        self.background = background;
    }

    row.deinit();
    row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .margin = .{ .y = 5 } });
    defer row.deinit();

    const OptionsColors = enum { fill, fill_hover, fill_press, text, text_hover, text_press, border };
    const active_color = dvui.dataGetPtrDefault(null, id, "Color", OptionsColors, .fill);

    {
        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .vertical }, .{ .expand = .vertical });
        tabs.install();
        defer tabs.deinit();

        const colors = comptime std.meta.tags(OptionsColors);
        inline for (colors, 0..) |color_ask, i| {
            const tab = tabs.addTab(active_color.* == color_ask, .{
                .expand = .horizontal,
                .padding = .all(2),
                .id_extra = i,
            });
            defer tab.deinit();

            if (tab.clicked()) {
                active_color.* = color_ask;
            }

            var label_opts = tab.data().options.strip();
            if (dvui.captured(tab.data().id)) {
                label_opts.color_text = label_opts.color(.text_press);
            }

            const field = "color_" ++ @tagName(color_ask);
            const color = @field(self, field);

            const color_indicator = dvui.overlay(@src(), .{
                .expand = .ratio,
                .min_size_content = .all(10),
                .corner_radius = .all(100),
                .border = .all(1),
                .background = true,
                .color_fill = color,
            });
            const color_width = color_indicator.data().rectScale().r.w;
            if (color == null) {
                dvui.labelNoFmt(@src(), "?", .{}, .{ .expand = .ratio, .gravity_x = 0.5, .gravity_y = 0.5 });
            }
            color_indicator.deinit();
            dvui.labelNoFmt(@src(), @tagName(color_ask), .{}, .{ .margin = .{ .x = color_width } });
        }
    }

    {
        var vbox = dvui.box(@src(), .{}, .{});
        defer vbox.deinit();

        const field: *?dvui.Color = switch (active_color.*) {
            inline else => |c| &@field(self, "color_" ++ @tagName(c)),
        };
        var hsv = dvui.Color.HSV.fromColor(field.* orelse .white);
        if (dvui.colorPicker(@src(), .{ .hsv = &hsv, .dir = .horizontal }, .{})) {
            changed = true;
            field.* = hsv.toColor();
        }

        if (field.* != null and dvui.button(@src(), "Set to null", .{}, .{})) {
            changed = true;
            field.* = null;
        }
    }

    return changed;
}

/// Used to copy the code for any runtime type, used to copy
/// modified `Options`.s
pub fn ZigCodeFormatter(comptime T: type) type {
    return struct {
        value: T,
        pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            switch (@typeInfo(T)) {
                .optional => if (self.value) |v|
                    try writer.print("{f}", .{asZigCode(v)})
                else
                    try writer.writeAll("null"),
                .null => try writer.writeAll("null"),
                .@"enum" => try writer.print(".{t}", .{self.value}),
                .float, .int, .comptime_float, .comptime_int => try writer.print("{d}", .{self.value}),
                .bool => try writer.print("{s}", .{if (self.value) "true" else "false"}),
                .pointer => |ptr| {
                    switch (ptr.size) {
                        .one => switch (@typeInfo(ptr.child)) {
                            .array => try writer.print("{f}", .{asZigCode(self.value.*)}),
                            else => @compileError("Cannot write single item pointer"),
                        },
                        .c, .many, .slice => if (ptr.child == u8)
                            try writer.print("\"{s}\"", .{self.value})
                        else
                            @compileError("Cannot write non string many item pointer"),
                    }
                },
                .array => |array| if (array.child == u8) {
                    try writer.print("\"{s}\"", .{self.value});
                } else {
                    try writer.writeAll(".{ ");
                    for (self.value) |v| {
                        try writer.print("{f}", .{asZigCode(v)});
                        try writer.writeAll(", ");
                    }
                    try writer.writeAll("}");
                },
                .@"struct" => |struct_info| {
                    try writer.writeAll(".{ ");
                    inline for (struct_info.fields) |field| blk: {
                        const ti = @typeInfo(field.type);
                        // Ignore single item pointers
                        const ptr_info: ?std.builtin.Type.Pointer = switch (ti) {
                            .pointer => |ptr| ptr,
                            .optional => |opt| if (@typeInfo(opt.child) == .pointer)
                                @typeInfo(opt.child).pointer
                            else
                                null,
                            else => null,
                        };
                        if (ptr_info != null and ptr_info.?.size == .one and @typeInfo(ptr_info.?.child) != .array) {
                            continue;
                        }
                        if (field.defaultValue() != null and ti == .optional and @field(self.value, field.name) == null) {
                            break :blk;
                        }
                        try writer.print(".{s} = ", .{field.name});
                        try writer.print("{f}", .{asZigCode(@field(self.value, field.name))});
                        try writer.writeAll(", ");
                    }
                    try writer.writeAll("}");
                },
                .@"union" => switch (std.meta.activeTag(self.value)) {
                    inline else => |tag| if (@FieldType(T, @tagName(tag)) == void) {
                        try writer.print(".{s}", .{@tagName(tag)});
                    } else {
                        try writer.print(".{{ .{s} = ", .{@tagName(tag)});
                        try writer.print("{f}", .{asZigCode(@field(self.value, @tagName(tag)))});
                        try writer.writeAll(" }");
                    },
                },
                else => @compileError("Unhandled field type: " ++ @typeName(T)),
            }
        }
    };
}

pub fn asZigCode(value: anytype) ZigCodeFormatter(@TypeOf(value)) {
    return .{ .value = value };
}

test asZigCode {
    var writeBuffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writeBuffer);

    try writer.print("{f}", .{asZigCode(@as(f32, 12.34))});
    try std.testing.expectEqualStrings("12.34", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(f32, 12))});
    try std.testing.expectEqualStrings("12", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(u8, 43))});
    try std.testing.expectEqualStrings("43", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(i32, -5423))});
    try std.testing.expectEqualStrings("-5423", writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(true)});
    try std.testing.expectEqualStrings("true", writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(false)});
    try std.testing.expectEqualStrings("false", writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as(?f32, null))});
    try std.testing.expectEqualStrings("null", writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as([]const u8, "testing"))});
    try std.testing.expectEqualStrings(
        \\"testing"
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(@as(*const [7]u8, "testing"))});
    try std.testing.expectEqualStrings(
        \\"testing"
    , writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as([3]u32, .{ 12, 34, 56 }))});
    try std.testing.expectEqualStrings(
        \\.{ 12, 34, 56, }
    , writer.buffered());
    _ = writer.consumeAll();

    try writer.print("{f}", .{asZigCode(@as(enum { a, b }, .a))});
    try std.testing.expectEqualStrings(".a", writer.buffered());
    _ = writer.consumeAll();

    const A = struct {
        a: bool,
        b: u32 = 123,
        c: ?[]const u8 = null,
    };

    try writer.print("{f}", .{asZigCode(A{ .a = true })});
    try std.testing.expectEqualStrings(
        // Expect that `c` is not included as it defaults to `null`
        \\.{ .a = true, .b = 123, }
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(A{ .a = false, .c = "testing text" })});
    try std.testing.expectEqualStrings(
        \\.{ .a = false, .b = 123, .c = "testing text", }
    , writer.buffered());
    _ = writer.consumeAll();

    const B = union(enum) {
        a: u32,
        b: struct { a: ?[]const u8 = null, b: f32 },
        c,
    };

    try writer.print("{f}", .{asZigCode(B{ .a = 123 })});
    try std.testing.expectEqualStrings(
        \\.{ .a = 123 }
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(B{ .b = .{ .b = 0.001 } })});
    try std.testing.expectEqualStrings(
        \\.{ .b = .{ .b = 0.001, } }
    , writer.buffered());
    _ = writer.consumeAll();
    try writer.print("{f}", .{asZigCode(B.c)});
    try std.testing.expectEqualStrings(
        // the value type here is void, so it should use the shorthand
        \\.c
    , writer.buffered());
    _ = writer.consumeAll();
}

const Options = dvui.Options;
const Rect = dvui.Rect;

const std = @import("std");
const dvui = @import("dvui.zig");
