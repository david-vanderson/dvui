open: bool = false,
options_editor_open: bool = false,
options_override_list_open: bool = false,

/// 0 means no widget is selected
widget_id: dvui.WidgetId = .zero,
target: DebugTarget = .none,

/// All functions using the parent are invalid
target_wd: ?dvui.WidgetData = null,

/// Uses `gpa` allocator
///
/// The name slice is also duplicated by the `gpa` allocator
under_mouse_stack: std.ArrayListUnmanaged(struct { id: dvui.WidgetId, name: []const u8 }) = .empty,

/// Uses `gpa` allocator
options_override: std.AutoHashMapUnmanaged(dvui.WidgetId, struct { Options, std.builtin.SourceLocation }) = .empty,

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
    quitting,

    pub fn mouse(self: DebugTarget) bool {
        return self == .mouse_until_click or self == .mouse_until_esc;
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
    if (!self.open) return;

    if (self.target == .quitting) {
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
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();

        dvui.labelNoFmt(@src(), "Hex id of widget to highlight:", .{}, .{ .gravity_y = 0.5 });

        var buf = [_]u8{0} ** 20;
        if (self.widget_id != .zero) {
            _ = std.fmt.bufPrint(&buf, "{x}", .{self.widget_id}) catch unreachable;
        }
        var te = dvui.textEntry(@src(), .{
            .text = .{ .buffer = &buf },
        }, .{});
        te.deinit();

        self.widget_id = @enumFromInt(std.fmt.parseInt(u64, std.mem.sliceTo(&buf, 0), 16) catch 0);
    }

    var tl = dvui.TextLayoutWidget.init(@src(), .{}, .{ .expand = .horizontal, .min_size_content = .{ .h = 250 } });
    tl.install(.{});

    {
        var corner_box = dvui.box(@src(), .vertical, .{ .gravity_x = 1, .margin = .all(8) });
        defer corner_box.deinit();

        var color: ?Options.ColorOrName = null;
        if (self.widget_id == .zero) {
            // blend text and control colors
            color = .{ .color = .average(dvui.themeGet().color_text, dvui.themeGet().color_fill_control) };
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
            \\{x} {s}
            \\
            \\{}
            \\min {}
            \\{}
            \\scale {d}
            \\padding {}
            \\border {}
            \\margin {}
            \\
            \\{s}:{d}
            \\id_extra {?d}
        , .{
            wd.id,
            wd.options.name orelse "???",
            rs.r,
            wd.min_size,
            wd.options.expandGet(),
            rs.s,
            wd.options.paddingGet().scale(rs.s, Rect.Physical),
            wd.options.borderGet().scale(rs.s, Rect.Physical),
            wd.options.marginGet().scale(rs.s, Rect.Physical),
            wd.src.file,
            wd.src.line,
            wd.options.id_extra,
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

    if (dvui.button(@src(), if (debug_target == .focused) "Stop Debugging Focus" else "Debug Focus", .{}, .{})) {
        debug_target = if (debug_target == .focused) .none else .focused;
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
        var i: usize = 0;
        var remove_override_id: ?dvui.WidgetId = null;
        while (it.next()) |entry| : (i += 1) {
            const id = entry.key_ptr.*;
            const options, const src = entry.value_ptr.*;

            const row = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
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
                var button = dvui.ButtonWidget.init(@src(), .{}, .{ .id_extra = i, .expand = .horizontal });
                button.install();
                defer button.deinit();
                button.processEvents();
                button.drawBackground();

                if (button.clicked()) self.widget_id = id;

                const stack = dvui.box(@src(), .vertical, .{
                    .expand = .both,
                    .color_fill = if (button.pressed()) .fill_press else null,
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

    var log_refresh = self.logRefresh(null);
    if (dvui.checkbox(@src(), &log_refresh, "Refresh Logging", .{})) {
        _ = self.logRefresh(log_refresh);
    }

    var log_events = self.logEvents(null);
    if (dvui.checkbox(@src(), &log_events, "Event Logging", .{})) {
        _ = self.logEvents(log_events);
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .background = false, .min_size_content = .height(200) });
    defer scroll.deinit();

    for (self.under_mouse_stack.items, 0..) |item, i| {
        var hbox = dvui.box(@src(), .horizontal, .{ .id_extra = i });
        defer hbox.deinit();

        if (dvui.buttonIcon(@src(), "find", dvui.entypo.magnifying_glass, .{}, .{}, .{})) {
            self.widget_id = item.id;
        }

        dvui.label(@src(), "{x} {s}", .{ item.id, item.name }, .{ .gravity_y = 0.5 });
    }
}

const OptionsEditorTab = enum { layout, style };

/// Returns true if the options was modified
pub fn optionsEditor(self: *Options, wd: *const dvui.WidgetData) bool {
    var changed = false;

    var vbox = dvui.box(@src(), .vertical, .{ .name = "Editor Box", .expand = .both });
    defer vbox.deinit();

    const active_tab = dvui.dataGetPtrDefault(null, vbox.data().id, "Tab", OptionsEditorTab, .layout);
    {
        var overlay = dvui.overlay(@src(), .{ .expand = .horizontal });
        defer overlay.deinit();

        var button_wd: dvui.WidgetData = undefined;
        if (dvui.buttonIcon(@src(), "Copy Options", dvui.entypo.copy, .{}, .{}, .{ .gravity_x = 1, .data_out = &button_wd })) {
            copyOptionsToClipboard(wd.src, wd.id, self.*);
        }
        dvui.tooltip(@src(), .{
            .active_rect = button_wd.borderRectScale().r,
            .position = .vertical,
        }, "Copy Options struct to clipboard", .{}, .{});

        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        tabs.install();
        defer tabs.deinit();

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

fn copyOptionsToClipboard(src: std.builtin.SourceLocation, id: dvui.WidgetId, options: Options) void {
    dvui.log.debug("Copied Options struct for {s}:{d}", .{ src.file, src.line });
    dvui.toast(@src(), .{ .message = "Options copied to clipboard" });

    var out = std.ArrayList(u8).init(dvui.currentWindow().lifo());
    defer out.deinit();
    var writer = out.writer();
    writeTypeAsCode(writer.any(), options) catch |err| {
        dvui.logError(@src(), err, "Could not write Options struct for {x} {s}", .{ id, options.name orelse "???" });
    };
    dvui.clipboardTextSet(out.items);
}

fn layoutPage(self: *Options, id: dvui.WidgetId) bool {
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
    const gravity_y = &self.gravity_y.?;

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
        var row = dvui.box(@src(), .horizontal, .{});
        defer row.deinit();

        {
            dvui.labelNoFmt(@src(), "expand", .{}, .{ .gravity_y = 0.5 });
            const expands = std.meta.tags(Options.Expand);
            var dd = dvui.DropdownWidget.init(@src(), .{
                .label = @tagName(self.expandGet()),
                .selected_index = std.mem.indexOfScalar(Options.Expand, expands, self.expandGet()).?,
            }, .{
                .expand = .horizontal,
                .min_size_content = .{ .w = 110 },
                .gravity_y = 0.5,
            });
            dd.install();
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
        var row = dvui.box(@src(), .horizontal, .{});
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
        var row = dvui.box(@src(), .horizontal, .{});
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
        var row = dvui.boxEqual(@src(), .horizontal, .{});
        defer row.deinit();
        { // Top Left
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "radius: {d:0}", .{ .value = &corner_radius.x, .min = 0, .max = 200, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
                if (link_radius.*) {
                    corner_radius.* = .all(corner_radius.x);
                }
            }
        }
        { // Top Center
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1) });
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
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1), .expand = .vertical });
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
        var row = dvui.boxEqual(@src(), .horizontal, .{});
        defer row.deinit();
        { // Middle Left
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1) });
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
            var col = dvui.box(@src(), .horizontal, .{ .border = .all(1), .expand = .both });
            defer col.deinit();

            if (dvui.slider(@src(), .vertical, gravity_y, .{ .expand = .vertical })) {
                changed = true;
            }

            var side = dvui.box(@src(), .vertical, .{ .expand = .both });
            defer side.deinit();

            dvui.labelNoFmt(@src(), "gravity", .{}, .{ .gravity_y = 0.5 });

            if (dvui.slider(@src(), .horizontal, gravity_x, .{ .expand = .horizontal, .gravity_y = 1 })) {
                changed = true;
            }
        }
        { // Middle Right
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1) });
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
        var row = dvui.boxEqual(@src(), .horizontal, .{});
        defer row.deinit();
        { // Bottom Left
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1), .expand = .vertical });
            defer col.deinit();

            if (dvui.sliderEntry(@src(), "radius: {d:0}", .{ .value = &corner_radius.h, .min = 0, .max = 200, .interval = 1 }, .{ .gravity_y = 0.5 })) {
                changed = true;
                if (link_radius.*) {
                    corner_radius.* = .all(corner_radius.h);
                }
            }
        }
        { // Bottom Center
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1) });
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
            var col = dvui.box(@src(), .vertical, .{ .border = .all(1), .expand = .vertical });
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
        var row = dvui.box(@src(), .horizontal, .{});
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

fn stylePage(self: *Options, id: dvui.WidgetId) bool {
    var changed = false;

    var row = dvui.box(@src(), .horizontal, .{ .expand = .horizontal });
    {
        dvui.label(@src(), "Font Style", .{}, .{ .gravity_y = 0.5 });
        const font_styles = std.meta.tags(Options.FontStyle);
        var dd = dvui.DropdownWidget.init(@src(), .{
            .label = if (self.font_style) |style| @tagName(style) else "null",
        }, .{
            .min_size_content = .{ .w = 150 },
            .gravity_y = 0.5,
        });
        dd.install();
        defer dd.deinit();
        if (dd.dropped()) {
            if (dd.addChoiceLabel("Set to null")) {
                self.font_style = null;
                changed = true;
            }
            for (font_styles) |style| {
                if (dd.addChoiceLabel(@tagName(style))) {
                    self.font_style = style;
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
    row = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .margin = .{ .y = 5 } });
    defer row.deinit();

    const active_color = dvui.dataGetPtrDefault(null, id, "Color", Options.ColorAsk, .accent);

    {
        var tabs = dvui.TabsWidget.init(@src(), .{ .dir = .vertical }, .{ .expand = .vertical });
        tabs.install();
        defer tabs.deinit();

        const colors = comptime std.meta.tags(Options.ColorAsk);
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
                label_opts.color_text = .{ .name = .text_press };
            }

            const field = "color_" ++ @tagName(color_ask);
            const color: Options.ColorOrName = if (@field(self, field)) |color| color else switch (color_ask) {
                .accent => .{ .name = .accent },
                .text => .{ .name = .text },
                .text_press => .{ .name = .text_press },
                .fill => .{ .name = .fill },
                .fill_hover => .{ .name = .fill_hover },
                .fill_press => .{ .name = .fill_press },
                .border => .{ .name = .border },
            };

            const color_indicator = dvui.overlay(@src(), .{
                .expand = .ratio,
                .min_size_content = .all(10),
                .corner_radius = .all(100),
                .border = .all(1),
                .background = true,
                .color_fill = .fromColor(color.resolve()),
            });
            // Used to o
            const color_width = color_indicator.data().rectScale().r.w;
            color_indicator.deinit();
            dvui.labelNoFmt(@src(), @tagName(color_ask), .{}, .{ .margin = .{ .x = color_width } });
        }
    }

    {
        var col = dvui.box(@src(), .vertical, .{ .expand = .both, .margin = .all(5) });
        defer col.deinit();

        const field: ?*Options.ColorOrName = switch (active_color.*) {
            inline else => |c| if (@field(self, "color_" ++ @tagName(c))) |*ptr| ptr else null,
        };
        const rgba_color: Options.ColorOrName = if (field) |ptr| ptr.* else switch (active_color.*) {
            .accent => .{ .name = .accent },
            .text => .{ .name = .text },
            .text_press => .{ .name = .text_press },
            .fill => .{ .name = .fill },
            .fill_hover => .{ .name = .fill_hover },
            .fill_press => .{ .name = .fill_press },
            .border => .{ .name = .border },
        };

        var hsv = dvui.Color.HSV.fromColor(rgba_color.resolve());
        if (dvui.colorPicker(@src(), .{ .hsv = &hsv, .dir = .horizontal }, .{})) {
            changed = true;
            if (field) |ptr| {
                ptr.* = .fromColor(hsv.toColor());
            } else switch (active_color.*) {
                inline else => |c| @field(self, "color_" ++ @tagName(c)) = .fromColor(hsv.toColor()),
            }
        }

        {
            const colors = std.meta.tags(Options.ColorsFromTheme);
            const current_color: ?Options.ColorsFromTheme = if (field) |ptr| switch (ptr.*) {
                .name => |n| n,
                .color => null,
            } else null;
            var dd = dvui.DropdownWidget.init(@src(), .{
                .label = if (current_color) |c| @tagName(c) else "custom",
                .selected_index = if (current_color) |c| std.mem.indexOfScalar(Options.ColorsFromTheme, colors, c) else null,
            }, .{
                .min_size_content = .{ .w = 110 },
            });
            dd.install();
            defer dd.deinit();
            if (dd.dropped()) {
                for (colors) |color| {
                    if (dd.addChoiceLabel(@tagName(color))) {
                        changed = true;
                        if (field) |ptr| {
                            ptr.* = .{ .name = color };
                        } else switch (active_color.*) {
                            inline else => |c| @field(self, "color_" ++ @tagName(c)) = .{ .name = color },
                        }
                    }
                }
            }
        }
    }

    return changed;
}

/// Used to copy the code for any runtime type, used to copy
/// modified `Options`.
pub fn writeTypeAsCode(writer: std.io.AnyWriter, val: anytype) !void {
    const T = @TypeOf(val);
    switch (@typeInfo(T)) {
        .optional => if (val) |v|
            try writeTypeAsCode(writer, v)
        else
            try writer.writeAll("null"),
        .null => try writer.writeAll("null"),
        .@"enum", .enum_literal => try writer.print(".{s}", .{@tagName(val)}),
        .float, .int, .comptime_float, .comptime_int => try writer.print("{d}", .{val}),
        .bool => try writer.print("{any}", .{val}),
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => switch (@typeInfo(ptr.child)) {
                    .array => try writeTypeAsCode(writer, val.*),
                    else => @compileError("Cannot write single item pointer"),
                },
                .c, .many, .slice => if (ptr.child == u8)
                    try writer.print("\"{s}\"", .{val})
                else
                    @compileError("Cannot write non string many item pointer"),
            }
        },
        .array => |array| if (array.child == u8) {
            try writer.print("\"{s}\"", .{val});
        } else {
            try writer.writeAll(".{ ");
            for (val) |v| {
                try writeTypeAsCode(writer, v);
                try writer.writeAll(", ");
            }
            try writer.writeAll("}");
        },
        .@"struct" => {
            try writer.writeAll(".{ ");
            inline for (std.meta.fields(T)) |field| blk: {
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
                if (field.defaultValue() != null and ti == .optional and @field(val, field.name) == null) {
                    break :blk;
                }
                try writer.print(".{s} = ", .{field.name});
                try writeTypeAsCode(writer, @field(val, field.name));
                try writer.writeAll(", ");
            }
            try writer.writeAll("}");
        },
        .@"union" => switch (std.meta.activeTag(val)) {
            inline else => |tag| if (@FieldType(T, @tagName(tag)) == void) {
                try writer.print(".{s}", .{@tagName(tag)});
            } else {
                try writer.print(".{{ .{s} = ", .{@tagName(tag)});
                try writeTypeAsCode(writer, @field(val, @tagName(tag)));
                try writer.writeAll(" }");
            },
        },
        else => @compileError("Unhandled field type: " ++ @typeName(T)),
    }
}

test writeTypeAsCode {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    const writer = out.writer().any();

    try writeTypeAsCode(writer, @as(f32, 12.34));
    try std.testing.expectEqualStrings("12.34", out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, @as(f32, 12));
    try std.testing.expectEqualStrings("12", out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, @as(u8, 43));
    try std.testing.expectEqualStrings("43", out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, @as(i32, -5423));
    try std.testing.expectEqualStrings("-5423", out.items);
    out.clearRetainingCapacity();

    try writeTypeAsCode(writer, true);
    try std.testing.expectEqualStrings("true", out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, false);
    try std.testing.expectEqualStrings("false", out.items);
    out.clearRetainingCapacity();

    try writeTypeAsCode(writer, @as(?f32, null));
    try std.testing.expectEqualStrings("null", out.items);
    out.clearRetainingCapacity();

    try writeTypeAsCode(writer, @as([]const u8, "testing"));
    try std.testing.expectEqualStrings(
        \\"testing"
    , out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, @as(*const [7]u8, "testing"));
    try std.testing.expectEqualStrings(
        \\"testing"
    , out.items);
    out.clearRetainingCapacity();

    try writeTypeAsCode(writer, @as([3]u32, .{ 12, 34, 56 }));
    try std.testing.expectEqualStrings(
        \\.{ 12, 34, 56, }
    , out.items);
    out.clearRetainingCapacity();

    try writeTypeAsCode(writer, @as(enum { a, b }, .a));
    try std.testing.expectEqualStrings(".a", out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, .literal);
    try std.testing.expectEqualStrings(".literal", out.items);
    out.clearRetainingCapacity();

    const A = struct {
        a: bool,
        b: u32 = 123,
        c: ?[]const u8 = null,
    };

    try writeTypeAsCode(writer, A{ .a = true });
    try std.testing.expectEqualStrings(
        // Expect that `c` is not included as it defaults to `null`
        \\.{ .a = true, .b = 123, }
    , out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, A{ .a = false, .c = "testing text" });
    try std.testing.expectEqualStrings(
        \\.{ .a = false, .b = 123, .c = "testing text", }
    , out.items);
    out.clearRetainingCapacity();

    const B = union(enum) {
        a: u32,
        b: struct { a: ?[]const u8 = null, b: f32 },
        c,
    };

    try writeTypeAsCode(writer, B{ .a = 123 });
    try std.testing.expectEqualStrings(
        \\.{ .a = 123 }
    , out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, B{ .b = .{ .b = 0.001 } });
    try std.testing.expectEqualStrings(
        \\.{ .b = .{ .b = 0.001, } }
    , out.items);
    out.clearRetainingCapacity();
    try writeTypeAsCode(writer, B.c);
    try std.testing.expectEqualStrings(
        // the value type here is void, so it should use the shorthand
        \\.c
    , out.items);
    out.clearRetainingCapacity();
}

const Options = dvui.Options;
const Rect = dvui.Rect;

const std = @import("std");
const dvui = @import("dvui.zig");
