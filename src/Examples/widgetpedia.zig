//! The Widgetpedia is a place to showcase all of the dvui widgets.
//! It serves the dual purpose of allowing users to interact with widgets to understand how they how
//! and to provide a place for widget developers to test changes to widgets.
//!
//! To add new widgets refer to the documentation for widgetDisplayTemplate()
const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = dvui.Examples;

var reset_widget: bool = true;
const test_options_label = "Controls";

// Common struct_ui StructOptions.
const struct_options = struct {
    const color: StructOptions(dvui.Color) = .initWithDisplayFn(structColorPicker, .white);
    const color_hsva: StructOptions(dvui.Color.HSV) = .init(.{
        .h = .{ .number = .{ .min = 0, .max = 359.99 } },
        .s = .{ .number = .{ .min = 0, .max = 1 } },
        .v = .{ .number = .{ .min = 0, .max = 1 } },
        .a = .{ .number = .{ .min = 0, .max = 1 } },
    }, .fromColor(.white));

    const color_hsv: StructOptions(dvui.Color.HSV) = .init(.{
        .h = .{ .number = .{ .min = 0, .max = 359.99 } },
        .s = .{ .number = .{ .min = 0, .max = 1 } },
        .v = .{ .number = .{ .min = 0, .max = 1 } },
        .a = .{ .number = .{ .min = 0, .max = 1, .display = .read_only } },
    }, .fromColor(.white));

    const text_entry = struct {
        const init_opts: StructOptions(dvui.TextEntryWidget.InitOptions) = .initWithDefaults(.{
            .placeholder = .defaultTextRW,
            .password_char = .defaultTextRW,
            .tree_sitter = .defaultHidden,
            .text = .defaultReadOnly,
            .break_lines = .{ .boolean = .{ .widget_type = .checkbox } },
            .cache_layout = .{ .boolean = .{ .widget_type = .checkbox } },
            .multiline = .{ .boolean = .{ .widget_type = .checkbox } },
        }, .{
            .placeholder = "Placeholder",
            .password_char = "*",
        });
    };
};

pub fn widgetpedia() void {
    if (!Examples.show_widgetpedia_window) {
        return;
    }
    const prev_defaults = struct_ui.defaults;
    struct_ui.defaults.display_expanded = true;
    struct_ui.defaults.narrow = true;
    defer struct_ui.defaults.display_expanded = prev_defaults.display_expanded;
    defer struct_ui.defaults.narrow = prev_defaults.narrow;

    const width = 775;
    const height = 575;

    var floating_win = dvui.floatingWindow(@src(), .{
        .open_flag = &Examples.show_widgetpedia_window,
    }, .{
        .min_size_content = .{ .w = width, .h = 400 },
        .max_size_content = .{ .w = width, .h = height },
    });
    defer floating_win.deinit();

    floating_win.dragAreaSet(dvui.windowHeader("Widgetpedia", "", &Examples.show_widgetpedia_window));

    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .background = false });
    defer hbox.deinit();
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{});
        defer scroll.deinit();
        var tree = dvui.TreeWidget.tree(@src(), .{ .enable_reordering = false }, .{});
        defer tree.deinit();
        for (widget_hierarchy, 0..) |widget, i| {
            const color_fill: ?dvui.Color = blk: {
                if (widget.children) |children|
                    for (children) |child| {
                        if (child.displayFn != displayEmpty) break :blk null;
                    };
                break :blk if (widget.displayFn == displayEmpty) .gray else null;
            };
            const branch = tree.branch(@src(), .{ .expanded = false }, .{ .id_extra = i, .expand = .horizontal, .color_fill = color_fill });
            defer branch.deinit();
            dvui.label(@src(), "{s}", .{widget.name}, .{ .expand = .horizontal });

            if (widget.children != null) {
                _ = dvui.icon(
                    @src(),
                    "DropIcon",
                    if (branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
                    .{},
                    .{
                        .gravity_y = 0.5,
                        .gravity_x = 1.0,
                    },
                );
            } else if (branch.button.clicked()) {
                if (widget.children == null) {
                    current_widget = widget;
                    reset_widget = true;
                }
            }

            if (branch.expander(@src(), .{ .indent = 10 }, .{ .expand = .horizontal })) {
                if (widget.children) |children| {
                    for (children, 0..) |child, j| {
                        const branch_child = tree.branch(@src(), .{ .expanded = true }, .{ .id_extra = j, .expand = .horizontal, .color_fill = if (child.displayFn == displayEmpty) .gray else null });
                        defer branch_child.deinit();
                        dvui.labelNoFmt(@src(), child.name, .{}, .{ .expand = .horizontal });
                        if (branch_child.button.clicked()) {
                            setCurrentWidget(child);
                        }
                    }
                }
            }
        }
    }
    {
        var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .padding = .all(6), .corner_radius = .all(5), .border = .all(1) });
        defer vbox.deinit();
        current_widget.displayFn(reset_widget);
        reset_widget = false;
    }
}

fn setCurrentWidget(widget: WidgetHierarchy) void {
    current_widget = widget;
    reset_widget = true;
}

// Only supports 2 levels, parent and children.
const WidgetHierarchy = struct {
    name: []const u8,
    children: ?[]const WidgetHierarchy = null,
    displayFn: *const fn (reset_widget: bool) void,
};

var current_widget: WidgetHierarchy = widget_hierarchy[0];

fn displayEmpty(_: bool) void {
    var label_str = std.Io.Writer.Allocating.initCapacity(dvui.currentWindow().arena(), current_widget.name.len + 2) catch return;
    label_str.writer.print("{s}()", .{current_widget.name}) catch unreachable;
    var gbox = dvui.groupBox(@src(), label_str.written(), .{ .expand = .both });
    defer gbox.deinit();
    var vbox = dvui.box(@src(), .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
    defer vbox.deinit();
    dvui.icon(@src(), "under construction", dvui.entypo.hour_glass, .{}, .{ .gravity_x = 0.5, .min_size_content = .{ .h = 50, .w = 50 } });
    dvui.labelNoFmt(@src(), "Under construction", .{ .align_x = 0.5 }, .{});
}

/// To create a widget display compatible with this template, the struct must contain:
/// 1) const/var name: []const u8
/// 2) var wd: dvui.WidgetData
/// 3) var options: dvui.Options
/// 4) fn layoutWidget() void
/// 5) fn layoutResults() void - This is optional
/// 6) fn layoutWidgetControls() void - This is also optional
pub fn displayWidgetTemplate(widget_display: type) void {
    const default_options_editor_height = 300;
    const min_widget_display_height = 200;
    const state = struct {
        // Guess at initial split
        var split_ratio: f32 = 0.9;
        var split_ratio_inner: f32 = 0.5;
        var split_ratio_open: f32 = 0.5;
        var split_ratio_closed: f32 = 0.9;
        var options_editor_open: bool = false;
        var paned_content_height: f32 = 0;

        var paned_init_opts: dvui.PanedWidget.InitOptions = .{
            .direction = .vertical,
            .split_ratio = &split_ratio,
            .collapsed_size = 0,
        };
    };

    var paned = dvui.paned(@src(), state.paned_init_opts, .{ .expand = .both, .min_size_content = .{ .h = min_widget_display_height / state.split_ratio_closed } });
    defer paned.deinit();

    state.split_ratio = std.math.clamp(state.split_ratio, @min(min_widget_display_height / state.paned_content_height, state.split_ratio_closed), state.split_ratio_closed);

    if (paned.showFirst()) {
        {
            var inner_paned = dvui.paned(@src(), .{ .direction = .horizontal, .collapsed_size = 0, .split_ratio = &state.split_ratio_inner }, .{ .expand = .both });
            defer inner_paned.deinit();
            // Don't let the first pane completely close as it will stop the widget being displayed.
            // Important for floating widgets.
            if (state.split_ratio_inner < 0.01) state.split_ratio_inner = 0.01;

            if (inner_paned.showFirst()) {
                var vbox = dvui.box(@src(), .{}, .{ .expand = .both });
                defer vbox.deinit();
                {
                    var gbox = dvui.groupBox(@src(), widget_display.name, .{ .expand = .both });
                    defer gbox.deinit();
                    widget_display.layoutWidget();
                }
                if (std.meta.hasFn(widget_display, "layoutResults")) {
                    var gbox = dvui.groupBox(@src(), "Results", .{ .expand = .horizontal });
                    defer gbox.deinit();
                    widget_display.layoutResults();
                }
            }
            if (std.meta.hasFn(widget_display, "layoutWidgetControls")) {
                if (inner_paned.showSecond()) {
                    var scroll = dvui.scrollArea(@src(), .{}, .{
                        .corner_radius = .all(3),
                        .border = .all(1),
                        .padding = .all(6),
                        .expand = .both,
                        .margin = .{ .x = 6, .y = 6 + dvui.themeGet().font_body.lineHeight() / 2 - 1, .w = 6, .h = 6 },
                        .background = false,
                        .min_size_content = .{ .w = 350 },
                    });
                    defer scroll.deinit();
                    widget_display.layoutWidgetControls();
                }
            }
        }
    }

    if (paned.showSecond()) {
        var outer_vbox = dvui.box(@src(), .{}, .{
            .margin = .{ .x = 0, .y = 6, .h = 0, .w = 0 },
            .expand = .horizontal,
            .border = .all(1),
            .corner_radius = .all(3),
            .min_size_content = .{ .h = state.paned_content_height },
        });
        defer outer_vbox.deinit();
        var expander_wd: dvui.WidgetData = undefined;
        if (dvui.expander(@src(), "Options editor", .{ .default_expanded = false }, .{ .expand = .horizontal, .data_out = &expander_wd })) {
            var scroll = dvui.scrollArea(@src(), .{}, .{
                .corner_radius = .all(3),
                .padding = .all(6),
                .expand = .both,
                .background = false,
                .min_size_content = .{ .h = 40 },
            });
            defer scroll.deinit();

            var vbox = dvui.box(@src(), .{}, .{ .expand = .both });
            defer vbox.deinit();
            _ = widget_display.wd.validate();
            _ = dvui.Debug.optionsEditor(&widget_display.options, &widget_display.wd);
            if (state.split_ratio >= state.split_ratio_closed) {
                paned.animateSplit(state.split_ratio_open);
            }
            state.options_editor_open = true;
        } else if (state.options_editor_open and state.split_ratio < state.split_ratio_closed) {
            paned.animateSplit(state.split_ratio_closed);
            state.options_editor_open = false;
        }
        widgetShowSetOptionsTooltip(@src(), expander_wd.borderRectScale().r, widget_display.options);

        if (!dvui.firstFrame(paned.data().id) and state.paned_content_height != @max(paned.data().contentRect().h, 0.01)) {
            state.paned_content_height = @max(paned.data().contentRect().h, 0.01);
            state.split_ratio_open = 1 - default_options_editor_height / state.paned_content_height;
            // Using height of outer_vbox doesn't work when resizing the window. The vbox gets bigger.
            state.split_ratio_closed = (state.paned_content_height - expander_wd.rect.h - outer_vbox.data().options.marginGet().y - paned.handleGap()) / state.paned_content_height;
            if (!state.options_editor_open) {
                state.split_ratio = state.split_ratio_closed;
            }
        }
    }
}

pub fn widgetShowSetOptionsTooltip(src: std.builtin.SourceLocation, rect: Rect.Physical, opts: dvui.Options) void {
    var tt: dvui.FloatingTooltipWidget = undefined;
    tt.init(src, .{ .active_rect = rect, .interactive = false, .position = .vertical }, .{ .role = .tooltip });
    defer tt.deinit();
    if (tt.shown()) {
        var tl = dvui.textLayout(@src(), .{}, .{});
        defer tl.deinit();
        tl.addText("Configured options:", .{});
        var has_options: bool = false;
        inline for (std.meta.fields(@TypeOf(opts))) |field| {
            if (@typeInfo(@FieldType(dvui.Options, field.name)) == .optional and @field(opts, field.name) != null) {
                tl.addText("\n  • ", .{ .color_text = .green });
                tl.addText(field.name, .{});
                has_options = true;
            }
        }
        if (!has_options) {
            tl.addText("\n  • none", .{});
        }
    }
}

// Same as std.meta.DeclEnum, but allows decls to be skipped.
pub fn DeclEnumWithSkip(comptime T: type, start_at_decl: usize) type {
    const fieldInfos = std.meta.declarations(T)[start_at_decl..];
    const tt = std.math.IntFittingRange(0, if (fieldInfos.len == 0) 0 else fieldInfos.len - 1);
    var field_names: [fieldInfos.len][]const u8 = undefined;
    var field_values: [fieldInfos.len]tt = undefined;
    inline for (fieldInfos, 0..) |field, i| {
        field_names[i] = field.name;
        field_values[i] = @intCast(i);
    }
    return @Enum(tt, .exhaustive, &field_names, &field_values);
}

const DisplayAnimate = struct {
    const name = "animate()";
    var init_opts: dvui.AnimateWidget.InitOptions = undefined;
    var options: dvui.Options = undefined;
    var wd: dvui.WidgetData = undefined;

    const Easing = DeclEnumWithSkip(dvui.easing, 1);

    var animate_easing: ?Easing = null;

    const test_options = struct {
        var restart_animation: bool = undefined;
    };

    const default_init_opts: dvui.AnimateWidget.InitOptions = .{
        .duration = 5_000_000,
        .kind = .alpha,
        .easing = &dvui.easing.linear,
    };

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{ .kind = .alpha, .duration = 5_000_000 };
        options = .{ .expand = .both, .background = true, .color_fill = .navy };
        test_options.restart_animation = false;
    }

    pub fn layoutWidget() void {
        var animate = dvui.animate(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer animate.deinit();
        if (test_options.restart_animation) {
            animate.start();
            test_options.restart_animation = false;
        }
        dvui.labelNoFmt(@src(), "Some text", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
    }

    pub fn layoutWidgetControls() void {
        {
            var box = dvui.box(@src(), .{}, .{ .expand = .horizontal });
            defer box.deinit();
            if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
                defer container.deinit();
                container.data().options.expand = .horizontal;
                if (dvui.button(@src(), "Restart animation", .{}, .{})) {
                    test_options.restart_animation = true;
                }
            }
        }
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{
            StructOptions(dvui.AnimateWidget.InitOptions).initWithDefaults(.{
                .easing = .{ .standard = .{ .customDisplayFn = selectEasing } },
            }, default_init_opts),
        }, .{});
    }

    fn selectEasing(field_name: []const u8, ptr: *anyopaque, read_only: bool, alignment: *dvui.Alignment) void {
        if (read_only) return;

        const field_value_ptr: *?*const dvui.easing.EasingFn = @ptrCast(@alignCast(ptr));
        var box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer box.deinit();

        dvui.labelNoFmt(@src(), field_name, .{}, .{});

        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());
        if (dvui.dropdownEnum(@src(), Easing, .{ .choice_nullable = &animate_easing }, .{}, .{})) {
            if (animate_easing) |easing| {
                switch (easing) {
                    inline else => |e| field_value_ptr.* = @field(dvui.easing, @tagName(e)),
                }
            } else {
                field_value_ptr.* = null;
            }
        }
    }
};

const DisplayBox = struct {
    const name = "box()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.BoxWidget.InitOptions = undefined;

    var test_options: struct {
        nr_boxes: usize,
        expand: dvui.Options.Expand,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        test_options.nr_boxes = 5;
        test_options.expand = .none;
        init_opts = .{};
        options = .{ .expand = .both, .border = .all(1) };
    }

    pub fn layoutWidget() void {
        var box = dvui.box(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer box.deinit();
        for (0..test_options.nr_boxes) |i| {
            var b = dvui.box(@src(), .{}, .{
                .min_size_content = .{ .h = 30, .w = 30 },
                .border = .all(1),
                .id_extra = i,
                .expand = test_options.expand,
            });
            b.deinit();
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{}, .{});
    }
};

const DisplayButton = struct {
    const name = "button()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;

    var init_opts: dvui.ButtonWidget.InitOptions = undefined;
    var result: bool = undefined;
    var test_options: struct {
        label_str: []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{};
        options = .{};
        test_options = .{
            .label_str = "Button",
        };
    }

    pub fn layoutWidget() void {
        result = dvui.button(@src(), test_options.label_str, init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .widget_type = .{ .trigger_on = true } } }, &al);
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(
            @src(),
            test_options_label,
            &test_options,
            1,
            .{StructOptions(@TypeOf(test_options)).initWithDefaults(.{
                .label_str = .defaultTextRW,
            }, null)},
            .{},
        );
        dvui.structUI(@src(), "init_opts", &init_opts, 0, .{}, .{});
    }
};

const DisplayButtonIcon = struct {
    const EntypoIcons = std.meta.DeclEnum(dvui.entypo);
    const name = "buttonIcon()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.ButtonWidget.InitOptions = undefined;

    var result: bool = undefined;

    var icon_opts: dvui.IconRenderOptions = undefined;

    var icon_bytes: []const u8 = undefined;
    var icon: EntypoIcons = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{};
        icon_opts = .{};
        options = .{ .min_size_content = .all(50) };
        icon = .aircraft;
        icon_bytes = dvui.entypo.aircraft;
    }

    pub fn layoutWidget() void {
        result = dvui.buttonIcon(@src(), "icon", icon_bytes, init_opts, icon_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .widget_type = .{ .trigger_on = true } } }, &al);
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
            defer container.deinit();
            if (dvui.dropdownEnum(@src(), EntypoIcons, .{ .choice = &icon }, .{}, .{ .expand = .horizontal })) {
                switch (icon) {
                    inline else => |ch| icon_bytes = @field(dvui.entypo, @tagName(ch)),
                }
            }
        }
        dvui.structUI(@src(), "icon_opts", &icon_opts, 1, .{struct_options.color}, .{});
    }
};

const DisplayButtonLabelAndIcon = struct {
    const name = "buttonLabelAndIcon()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var combined_opts: dvui.ButtonLabelAndIconOptions = undefined;
    var result: bool = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .expand = .horizontal };
        combined_opts = .{
            .label = "Button",
            .tvg_bytes = dvui.entypo.aircraft,
            .button_opts = .{},
        };
    }

    pub fn layoutWidget() void {
        result = dvui.buttonLabelAndIcon(@src(), combined_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .widget_type = .{ .trigger_on = true } } }, &al);
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(
            @src(),
            "combined_opts",
            &combined_opts,
            1,
            .{ StructOptions(dvui.ButtonLabelAndIconOptions).initWithDefaults(.{
                .label = .defaultTextRW,
                .tvg_bytes = .defaultHidden,
            }, null), struct_options.color },
            .{},
        );
    }
};

const DisplayCheckbox = struct {
    const name = "checkbox()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;

    var result: bool = undefined;

    var test_options: struct {
        checked: bool,
        label_str: []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        test_options = .{
            .label_str = "checkbox label",
            .checked = false,
        };
    }

    pub fn layoutWidget() void {
        result = dvui.checkbox(@src(), &test_options.checked, test_options.label_str, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .widget_type = .{ .trigger_on = true } } }, &al);
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(
            @src(),
            test_options_label,
            &test_options,
            1,
            .{StructOptions(@TypeOf(test_options)).initWithDefaults(.{
                .label_str = .defaultTextRW,
            }, null)},
            .{},
        );
    }
};

const DisplayColorPicker = struct {
    const name = "colorPicker()";
    var init_opts: dvui.ColorPickerInitOptions = undefined;
    var options: dvui.Options = undefined;
    var wd: dvui.WidgetData = undefined;
    var hsv: dvui.Color.HSV = undefined;

    var result: struct {
        return_value: bool,
        color: dvui.Color,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{ .hsv = &hsv };
        options = .{};
        hsv = .fromColor(.white);
        result = .{
            .return_value = false,
            .color = .white,
        };
    }

    pub fn layoutWidget() void {
        if (dvui.colorPicker(@src(), init_opts, options.override(.{ .data_out = &wd }))) {
            result.return_value = true;
            result.color = init_opts.hsv.toColor();
        } else {
            result.return_value = false;
        }
    }

    pub fn layoutResults() void {
        dvui.structUI(
            @src(),
            null,
            &result,
            1,
            .{
                StructOptions(@TypeOf(result)).init(.{
                    .return_value = .{ .boolean = .{ .widget_type = .{ .trigger_on = true }, .display = .read_only } },
                    .color = .{ .standard = .{ .display = .read_only, .customDisplayFn = structColorPicker } },
                }, null),
            },
            .{},
        );
    }

    pub fn layoutWidgetControls() void {
        if (init_opts.alpha) {
            dvui.structUI(@src(), "init_opts", &init_opts, 2, .{struct_options.color_hsva}, .{});
        } else {
            dvui.structUI(@src(), "init_opts", &init_opts, 2, .{struct_options.color_hsv}, .{});
        }
    }
};

const DisplayComboBox = struct {
    const name = "comboBox()";
    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.TextEntryWidget.InitOptions = undefined;
    var options: dvui.Options = undefined;
    var test_options: struct {
        choice: usize,
        entries: []const []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{};
        options = .{};
        test_options = .{
            .choice = 0,
            .entries = &.{ "one", "two", "three", "four", "five" },
        };
    }

    pub fn layoutWidget() void {
        var combo = dvui.comboBox(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer combo.deinit();
        if (combo.entries(test_options.entries)) |index| {
            test_options.choice = index;
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(
            @src(),
            test_options_label,
            &test_options,
            1,
            .{},
            .{},
        );
        dvui.structUI(@src(), "init_opts", &init_opts, 2, .{struct_options.text_entry.init_opts}, .{});
    }
};

const DisplayContext = struct {
    const name = "context()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
    }

    pub fn layoutWidget() void {
        var label_wd: dvui.WidgetData = undefined;
        dvui.labelNoFmt(@src(), "Right click me...", .{}, .{ .data_out = &label_wd });

        const ctext = dvui.context(@src(), .{ .rect = label_wd.borderRectScale().r }, .{ .data_out = &wd });
        defer ctext.deinit();

        if (ctext.activePoint()) |cp| {
            var fw = dvui.floatingMenu(@src(), .{ .from = .fromPoint(cp) }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Menu Item 1", .{}, .{ .expand = .horizontal })) |_| {
                fw.close();
            }
            if (dvui.menuItemLabel(@src(), "Menu Item 2", .{}, .{ .expand = .horizontal })) |_| {
                fw.close();
            }
            if ((dvui.menuItemLabel(@src(), "Menu Item 3", .{}, .{ .expand = .horizontal }))) |_| {
                fw.close();
            }
        }
    }
};

const DisplayDropDown = struct {
    const name = "dropdown()";
    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.DropdownInitOptions = undefined;
    var options: dvui.Options = undefined;
    var results: struct {
        return_value: bool,
        choice_nullable: ?usize,
        choice: usize,
    } = undefined;
    // Enum values to display
    var expand: dvui.Options.Expand = undefined;
    var expand_maybe: ?dvui.Options.Expand = undefined;

    // Defaults for when fields are set to non-null
    const default_init_opts: dvui.DropdownInitOptions = .{
        .null_selectable = false,
        .placeholder = "Select ...",
    };

    var test_options: struct {
        nullable: bool,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .gravity_y = 0.5 };
        init_opts = .{};
        test_options.nullable = false;
        expand_maybe = null;
        results = .{
            .return_value = false,
            .choice_nullable = null,
            .choice = 0,
        };
    }

    pub fn layoutWidget() void {
        const entries = [_][]const u8{ "First", "Second", "Third is a really long one that doesn't fit" };

        results.return_value = dvui.dropdown(
            @src(),
            &entries,
            if (test_options.nullable) .{ .choice_nullable = &results.choice_nullable } else .{ .choice = &results.choice },
            init_opts,
            options.override(.{ .data_out = &wd }),
        );
    }

    pub fn layoutResults() void {
        const display_results = results;
        if (test_options.nullable) {
            dvui.structUI(@src(), null, &display_results, 3, .{StructOptions(@TypeOf(results)).init(.{
                .return_value = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
                .choice_nullable = .default,
            }, null)}, .{});
        } else {
            dvui.structUI(@src(), null, &display_results, 3, .{StructOptions(@TypeOf(results)).init(.{
                .return_value = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
                .choice = .default,
            }, null)}, .{});
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{StructOptions(dvui.DropdownInitOptions).initWithDefaults(.{
            .placeholder = .defaultText,
        }, default_init_opts)}, .{});
    }
};

const DisplayDropDownEnum = struct {
    const name = "dropdownEnum()";
    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.DropdownInitOptions = undefined;
    var options: dvui.Options = undefined;
    var results: struct {
        return_value: bool,
        choice: dvui.DropdownChoice(dvui.Options.Expand),
    } = undefined;
    // Enum values to display
    var expand: dvui.Options.Expand = undefined;
    var expand_maybe: ?dvui.Options.Expand = undefined;

    // Defaults for when fields are set to non-null
    const default_init_opts: dvui.DropdownInitOptions = .{
        .null_selectable = false,
        .placeholder = "Select something",
    };

    var test_options: struct {
        nullable: bool,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .gravity_y = 0.5 };
        init_opts = .{};
        test_options.nullable = false;
        expand = .none;
        expand_maybe = null;
        results = .{
            .return_value = false,
            .choice = .{ .choice = &expand },
        };
    }

    pub fn layoutWidget() void {
        results.return_value = dvui.dropdownEnum(@src(), dvui.Options.Expand, results.choice, init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        // const to force read-only display.
        const display_results = results;
        dvui.structUI(@src(), null, &display_results, 3, .{StructOptions(@TypeOf(results)).init(.{
            .return_value = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
            .choice = .default,
        }, null)}, .{});
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
        if (test_options.nullable) {
            if (results.choice != .choice_nullable) {
                results.choice = .{ .choice_nullable = &expand_maybe };
            }
        } else if (results.choice != .choice) {
            results.choice = .{ .choice = &expand };
        }

        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{StructOptions(dvui.DropdownInitOptions).initWithDefaults(.{
            .placeholder = .defaultText,
        }, default_init_opts)}, .{});
    }
};

const DisplayExpander = struct {
    const name = "expander()";
    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.ExpanderOptions = .{};
    var options: dvui.Options = undefined;
    var result: bool = undefined;
    var test_options: struct {
        label: []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{};
        options = .{};
        test_options = .{ .label = "Expander" };
    }

    pub fn layoutWidget() void {
        result = dvui.expander(@src(), test_options.label, init_opts, options.override(.{ .data_out = &wd }));
        if (result) {
            dvui.labelNoFmt(@src(), "Widget 1 ", .{}, .{});
            dvui.labelNoFmt(@src(), "Widget 2 ", .{}, .{});
            dvui.labelNoFmt(@src(), "Widget 3 ", .{}, .{});
        }
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .display = .read_only } }, &al);
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 2, .{
            StructOptions(@TypeOf(test_options)).initWithDefaults(.{
                .label = .defaultTextRW,
            }, null),
        }, .{});
        dvui.structUI(@src(), "init_opts", &init_opts, 2, .{}, .{});
    }
};

const DisplayFlexBox = struct {
    const name = "flexBox()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.FlexBoxWidget.InitOptions = undefined;

    var test_options: struct {
        nr_boxes: usize,
        expand: dvui.Options.Expand,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        test_options.nr_boxes = 25;
        test_options.expand = .none;
        init_opts = .{};
        options = .{ .border = .all(1) };
    }

    pub fn layoutWidget() void {
        var box = dvui.flexbox(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer box.deinit();
        for (0..test_options.nr_boxes) |i| {
            var b = dvui.box(@src(), .{}, .{
                .min_size_content = .{ .h = 30, .w = 30 },
                .border = .all(1),
                .id_extra = i,
                .expand = test_options.expand,
                .color_border = options.themeGet().focus,
            });
            b.deinit();
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{}, .{});
    }
};

const DisplayFloatingWindow = struct {
    const name = "floatingWindow()";
    var wd: dvui.WidgetData = undefined;
    var floating_opts: dvui.FloatingWindowWidget.InitOptions = .{};
    var options: dvui.Options = undefined;
    var open_flag = false;
    var rect: Rect = undefined;
    // Used to "relaunch" as a new window.
    var id_extra: usize = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        open_flag = true;
        rect = .all(0);
        id_extra = 0;
        floating_opts = .{ .open_flag = &open_flag };
        options = .{ .min_size_content = .all(350) };
    }

    pub fn layoutWidget() void {
        if (!open_flag) return;

        var fw = dvui.floatingWindow(@src(), floating_opts, options.override(.{ .data_out = &wd, .id_extra = id_extra }));
        defer fw.deinit();
        dvui.icon(@src(), "rocket", dvui.entypo.rocket, .{}, .{ .expand = .both });
        if (floating_opts.modal) {
            if (dvui.button(@src(), "End Modal", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 })) {
                floating_opts.modal = false;
            }
        }
        if (floating_opts.rect == null) {
            rect = fw.data().rect;
        }
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
            defer container.deinit();
            if (dvui.button(@src(), "Relaunch window", .{}, .{})) {
                open_flag = true;
                id_extra += 1;
            }
        }
        const display_opts: StructOptions(dvui.FloatingWindowWidget.InitOptions) = .initWithDefaults(
            .{},
            .{ .rect = &rect, .open_flag = &open_flag },
        );
        dvui.structUI(@src(), "floating_opts", &floating_opts, 2, .{display_opts}, .{});
    }
};

const DisplayWindowHeader = struct {
    const name = "windowHeader()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;

    var test_options: struct {
        str: []const u8,
        right_str: []const u8,
        open_flag: bool,
    } = undefined;

    var result: Rect.Physical = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        test_options = .{
            .str = "Window heading",
            .right_str = "right text",
            .open_flag = true,
        };
    }

    pub fn layoutWidget() void {
        {
            var tl = dvui.textLayout(@src(), .{}, .{ .gravity_y = 1.0, .gravity_x = 0.5 });
            defer tl.deinit();
            tl.addText("This widget has no configurable DVUI options.", .{});
        }
        if (!test_options.open_flag) return;

        var fw = dvui.floatingWindow(@src(), .{ .open_flag = &test_options.open_flag }, .{ .min_size_content = .all(350), .data_out = &wd });
        defer fw.deinit();
        result = dvui.windowHeader(test_options.str, test_options.right_str, &test_options.open_flag);
        fw.dragAreaSet(result);

        dvui.icon(@src(), "rocket", dvui.entypo.rocket, .{}, .{ .expand = .both });
    }

    pub fn layoutResults() void {
        const result_c = result;
        dvui.structUI(@src(), null, &result_c, 1, .{}, .{});
    }

    pub fn layoutWidgetControls() void {
        const display_opts: StructOptions(@TypeOf(test_options)) = .initWithDefaults(.{
            .str = .defaultTextRW,
            .right_str = .defaultTextRW,
        }, null);
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{display_opts}, .{});
    }
};

const DisplayFocusGroup = struct {
    const name = "focusGroup()";
    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.FocusGroupWidget.InitOptions = .{};
    var options: dvui.Options = undefined;
    var first_frame: bool = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{};
        options = .{};
        first_frame = true;
    }

    pub fn layoutWidget() void {
        var fg = dvui.focusGroup(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer fg.deinit();
        var button_wd: dvui.WidgetData = undefined;
        {
            var box = dvui.box(@src(), .{ .dir = init_opts.nav_key_dir orelse .vertical }, .{ .expand = .both });
            defer box.deinit();
            _ = dvui.button(@src(), "Button 1", .{}, .{ .data_out = &button_wd });
            _ = dvui.button(@src(), "Button 2", .{}, .{});
            _ = dvui.button(@src(), "Button 3", .{}, .{});
        }
        var tl = dvui.textLayout(@src(), .{ .break_lines = true }, .{ .expand = .horizontal });
        tl.addText("Widgets in a focus group are navigated using arrow keys.", .{ .gravity_x = 0.5, .expand = .horizontal });
        tl.deinit();
        if (first_frame) {
            first_frame = false;
            dvui.focusWidget(button_wd.id, null, null);
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 2, .{}, .{});
    }
};

const DisplayGroupBox = struct {
    const name = "groupBox()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var test_options: struct {
        long_label: bool,
        big_font: bool,
        background: bool,
    } = undefined;

    const label_short = "Shipping:";
    const label_long = "This is a really long label that will get truncated if it is long enough to span the width of the groupbox.";

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .expand = .both };
        test_options = .{
            .background = false,
            .big_font = false,
            .long_label = false,
        };
    }

    pub fn layoutWidget() void {
        if (test_options.big_font) {
            options.font = options.fontGet().withSize(18);
        } else {
            options.font = null;
        }
        if (test_options.background) {
            options.background = true;
            if (options.color_fill == null) {
                options.color_fill = .red;
            }
        } else {
            options.background = false;
        }

        var test_gbox = dvui.groupBox(@src(), if (test_options.long_label) label_long else label_short, options.override(.{ .data_out = &wd }));
        defer test_gbox.deinit();
        dvui.labelNoFmt(@src(), "Name:", .{}, .{});
        var te = dvui.textEntry(@src(), .{}, .{});
        te.deinit();
        dvui.labelNoFmt(@src(), "Address:", .{}, .{});
        te = dvui.textEntry(@src(), .{}, .{});
        te.deinit();
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
    }
};

const DisplayIcon = struct {
    const EntypoIcons = std.meta.DeclEnum(dvui.entypo);
    const name = "icon()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var icon_opts: dvui.IconRenderOptions = undefined;
    var icon_bytes: []const u8 = undefined;
    var icon_name: []const u8 = undefined;
    var choice: EntypoIcons = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .expand = .both };
        icon_opts = .{};
        icon_bytes = dvui.entypo.battery;
        choice = .battery;
        icon_name = @tagName(choice);
    }

    pub fn layoutWidget() void {
        dvui.icon(@src(), icon_name, icon_bytes, icon_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
            defer container.deinit();
            var al: dvui.Alignment = .init(@src(), 0);
            defer al.deinit();
            struct_ui.displayString(@src(), "name", &icon_name, .defaultTextRW, &al);
            {
                var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
                defer hbox.deinit();
                dvui.labelNoFmt(@src(), "icon_bytes", .{}, .{});
                al.spacer(@src(), 0);
                if (dvui.dropdownEnum(@src(), EntypoIcons, .{ .choice = &choice }, .{}, .{ .expand = .horizontal })) {
                    switch (choice) {
                        inline else => |ch| icon_bytes = @field(dvui.entypo, @tagName(ch)),
                    }
                    icon_name = @tagName(choice);
                }
            }
        }
    }
};

const DisplayLabelEx = struct {
    var name: []const u8 = undefined;

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.LabelWidget.InitOptions = undefined;
    var test_opts: struct {
        label: []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        name = std.fmt.allocPrint(dvui.currentWindow().arena(), "{s}()", .{current_widget.name}) catch current_widget.name;
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{};
        test_opts = .{
            .label = "Label text",
        };
    }

    pub fn layoutWidget() void {
        dvui.labelEx(@src(), "{s}", .{test_opts.label}, init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutWidgetControls() void {
        if (std.mem.eql(u8, current_widget.name, "labelNoFmt")) {
            dvui.structUI(@src(), test_options_label, &test_opts, 0, .{}, .{});
        } else {
            dvui.structUI(@src(), test_options_label, &test_opts, 0, .{StructOptions(@TypeOf(test_opts)).initWithDefaults(.{ .label = .defaultTextRW }, null)}, .{});
        }
        if (!std.mem.eql(u8, current_widget.name, "label")) {
            dvui.structUI(@src(), "init_opts", &init_opts, 1, .{}, .{});
        }
    }
};

const DisplayLabelClick = struct {
    const name: []const u8 = "labelClick()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.LabelClickOptions = undefined;
    var test_opts: struct {
        label: []const u8,
    } = undefined;
    var result: bool = false;
    var click_event: dvui.Event.EventTypes = undefined;
    var click_event_valid: ?dvui.Event.EventTypes = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{ .click_event = &click_event };
        test_opts = .{
            .label = "Label text",
        };
        click_event_valid = null;
    }

    pub fn layoutWidget() void {
        result = dvui.labelClick(@src(), "{s}", .{test_opts.label}, init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .widget_type = .{ .trigger_on = true } } }, &al);
        if (result) {
            click_event_valid = click_event;
        }
        if (click_event_valid) |cev| {
            struct_ui.displayUnion(@src(), "last click_event", &cev, 1, .{ .standard = .{ .display = .read_only, .default_expanded = false } }, .{});
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_opts, 1, .{StructOptions(@TypeOf(test_opts)).init(.{
            .label = .defaultTextRW,
        }, null)}, .{});
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{StructOptions(dvui.LabelClickOptions).initWithDefaults(.{
            .click_event = .defaultHidden,
        }, null)}, .{});
    }
};

const DisplayLink = struct {
    const name: []const u8 = "link()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.LinkOptions = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{ .url = "https://david-vanderson.github.io/", .label = null };
    }

    pub fn layoutWidget() void {
        dvui.link(@src(), init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutWidgetControls() void {
        const opts = StructOptions(dvui.LinkOptions).initWithDefaults(.{
            .url = .defaultTextRW,
            .label = .defaultTextRW,
        }, null);
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{opts}, .{});
    }
};

const DisplayMenu = struct {
    const name: []const u8 = "menu()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var test_options: struct {
        direction: dvui.enums.Direction,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        test_options = .{ .direction = .horizontal };
    }

    pub fn layoutWidget() void {
        var menu = dvui.menu(@src(), test_options.direction, options.override(.{ .data_out = &wd }));
        defer menu.deinit();
        {
            if (dvui.menuItemLabel(@src(), "Item", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                var mi = dvui.menuItem(@src(), .{}, .{ .expand = .horizontal });
                defer mi.deinit();
                {
                    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
                    defer hbox.deinit();
                    dvui.icon(@src(), "bell", dvui.entypo.bell, .{}, .{ .expand = .ratio });
                    dvui.labelNoFmt(@src(), "MenuItemWidget with icon and text", .{}, .{});
                }
                if (mi.activeRect()) |_| {
                    menu.close();
                }
            }
            if (dvui.menuItemLabel(@src(), "ItemIcon", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                if (dvui.menuItemIcon(@src(), "brush", dvui.entypo.brush, .{}, .{ .expand = .ratio })) |_| {
                    menu.close();
                }
            }
            if (dvui.menuItemLabel(@src(), "ItemLabel", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                if (dvui.menuItemLabel(@src(), "Menu label", .{}, .{ .expand = .horizontal })) |_| {
                    menu.close();
                }
            }
            if (dvui.menuItemLabel(@src(), "SubMenus", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                submenu();
                if (dvui.menuItemLabel(@src(), "Close", .{ .submenu = false }, .{ .expand = .horizontal })) |_| {
                    menu.close();
                }
            }
        }
    }

    pub fn submenu() void {
        if (dvui.menuItemLabel(@src(), "Sub...", .{ .submenu = true }, .{ .expand = .horizontal })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();
            submenu();
            if (dvui.menuItemLabel(@src(), "Close", .{ .submenu = false }, .{ .expand = .horizontal })) |_| {
                fw.close();
            }
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
    }
};

const DisplayMenuItem = struct {
    const name: []const u8 = "menuItem()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.MenuItemWidget.InitOptions = undefined;
    var checked: bool = false;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .min_size_content = .all(30) };
        init_opts = .{};
        checked = false;
    }

    pub fn layoutWidget() void {
        {
            var menu = dvui.menu(@src(), .horizontal, .{});
            defer menu.deinit();
            if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                {
                    var mi = dvui.menuItem(@src(), init_opts, options.override(.{ .data_out = &wd }));
                    defer mi.deinit();
                    var vbox = dvui.box(@src(), .{}, .{});
                    defer vbox.deinit();
                    dvui.labelNoFmt(@src(), "Menu items can contain other widgets", .{}, .{});
                    dvui.spinner(@src(), .{ .color_text = .green });
                    if (mi.activeRect()) |_| {
                        menu.close();
                    }
                }
                _ = dvui.checkbox(@src(), &checked, "Checkbox outside menu item", .{});
                if (dvui.menuItemLabel(@src(), "Standard item", .{}, .{ .expand = .horizontal })) |_| {
                    menu.close();
                }
            }
        }
    }

    pub fn layoutWidgetControls() void {
        const display_opts = StructOptions(dvui.MenuItemWidget.InitOptions).initWithDefaults(.{
            .submenu = .defaultReadOnly,
        }, null);
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{display_opts}, .{});
    }
};

const DisplayMenuItemIcon = struct {
    const name: []const u8 = "menuItemIcon()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.MenuItemWidget.InitOptions = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .min_size_content = .all(30) };
        init_opts = .{};
    }

    pub fn layoutWidget() void {
        {
            var menu = dvui.menu(@src(), .horizontal, .{});
            defer menu.deinit();
            if (dvui.menuItemIcon(@src(), "chevron_thin_down", dvui.entypo.chevron_thin_down, init_opts, options.override(.{ .data_out = &wd }))) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
                defer fw.deinit();
                _ = dvui.menuItemIcon(@src(), "aircraft", dvui.entypo.aircraft, init_opts, options.override(.{ .data_out = &wd }));
                _ = dvui.menuItemIcon(@src(), "aircraft_landing", dvui.entypo.aircraft_landing, init_opts, options.override(.{ .data_out = &wd }));
                _ = dvui.menuItemIcon(@src(), "aircraft_take_off", dvui.entypo.aircraft_take_off, init_opts, options.override(.{ .data_out = &wd }));
            }
            _ = dvui.menuItemIcon(@src(), "aircraft", dvui.entypo.aircraft, init_opts, options.override(.{ .data_out = &wd }));
            _ = dvui.menuItemIcon(@src(), "aircraft_landing", dvui.entypo.aircraft_landing, init_opts, options.override(.{ .data_out = &wd }));
            _ = dvui.menuItemIcon(@src(), "aircraft_take_off", dvui.entypo.aircraft_take_off, init_opts, options.override(.{ .data_out = &wd }));
        }
        var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .gravity_y = 1.0, .gravity_x = 0.5 });
        defer tl.deinit();
        tl.addText("The first icon will show a submenu when submenus are enabled", .{ .expand = .horizontal, .gravity_x = 0.5 });
    }

    pub fn layoutWidgetControls() void {
        const display_opts = StructOptions(dvui.MenuItemWidget.InitOptions).initWithDefaults(.{}, null);
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{display_opts}, .{});
    }
};

const DisplayMenuItemLabel = struct {
    const name: []const u8 = "menuItemLabel()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.MenuItemWidget.InitOptions = undefined;

    // Since FixedBufferAllocator only frees the last allocation, there is little point in performing
    // deallocations. If the FBA returns OOM, call resetWidget(.oom).
    var allocator_buffer: [10 * 1024]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = undefined;
    const allocator = fba.allocator();
    var menu_id: usize = 0;

    const MenuItem = struct {
        label: []const u8,
        id: usize,
        sub_items: std.ArrayList(MenuItem) = .empty,
    };

    var menu_items: std.ArrayList(MenuItem) = .empty;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget(.reset);
        displayWidgetTemplate(@This());
    }

    fn menuId() usize {
        defer menu_id += 1;
        return menu_id;
    }

    pub fn resetWidget(reason: enum { reset, oom }) void {
        fba = .init(&allocator_buffer);
        menu_items = .empty;

        options = .{};
        init_opts = .{
            .submenu = true,
        };
        menu_items.append(allocator, .{
            .label = "File",
            .id = menuId(),
            .sub_items = populateSubItems(&.{
                .{
                    .id = menuId(),
                    .label = "Export...",
                    .sub_items = populateSubItems(&.{
                        .{ .id = menuId(), .label = "png" },
                        .{ .id = menuId(), .label = "jpg" },
                    }),
                },
                .{ .id = menuId(), .label = "Close" },
            }),
        }) catch unreachable;
        menu_items.append(allocator, .{
            .label = "Help",
            .id = menuId(),
            .sub_items = populateSubItems(&.{
                .{ .id = menuId(), .label = "About" },
            }),
        }) catch unreachable;

        if (reason == .oom) {
            dvui.toast(@src(), .{ .subwindow_id = dvui.currentWindow().subwindows.current_id, .message = "Menu builder exceeded memory limit and has been reset " });
        }
    }

    fn populateSubItems(sub_items: []const MenuItem) std.ArrayList(MenuItem) {
        var result: std.ArrayList(MenuItem) = .empty;
        for (sub_items) |menu_item| {
            result.append(allocator, menu_item) catch resetWidget(.oom);
        }
        return result;
    }

    pub fn layoutWidget() void {
        var menu = dvui.menu(@src(), .horizontal, .{});
        defer menu.deinit();
        displayMenuItems(menu, menu_items);
    }

    fn displayMenuItems(menu: *dvui.MenuWidget, items: std.ArrayList(MenuItem)) void {
        for (items.items, 0..) |menu_item, i| {
            var init_opts_submenu = init_opts;
            init_opts_submenu.submenu = init_opts.submenu and menu_item.sub_items.items.len > 0;
            if (dvui.menuItemLabel(@src(), menu_item.label, init_opts_submenu, options.override(.{ .id_extra = i, .data_out = &wd }))) |r| {
                var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{ .id_extra = i });
                defer fw.deinit();
                // If there are no sub menus to display close on click.
                if (menu_item.sub_items.items.len == 0) {
                    menu.close();
                } else {
                    displayMenuItems(menu, menu_item.sub_items);
                }
            }
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{}, .{});
        var al: dvui.Alignment = .init(@src(), 0);
        defer al.deinit();
        if (struct_ui.displayContainer(@src(), "Menu builder", true)) |container| {
            defer container.deinit();
            displayMenuControls(&menu_items);
            al.spacer(@src(), 0);
            if (dvui.buttonIcon(@src(), "add", dvui.entypo.circle_with_plus, .{}, .{}, .{})) {
                const label = std.fmt.allocPrint(allocator, "Main {}", .{menu_items.items.len + 1}) catch return resetWidget(.oom);
                menu_items.append(allocator, .{ .label = label, .id = menuId() }) catch return resetWidget(.oom);
                dvui.refresh(null, @src(), null);
            }
        }
    }

    fn displayMenuControls(items: *std.ArrayList(MenuItem)) void {
        var indent = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .horizontal,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .x = 12 },
        });
        defer indent.deinit();

        var to_remove: ?usize = null;
        for (items.items, 0..) |*menu_item, i| {
            var vbox = dvui.box(@src(), .{}, .{ .id_extra = menu_item.id });
            defer vbox.deinit();
            {
                var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                defer hbox.deinit();
                {
                    const size = dvui.themeGet().font_body.sizeM(10, 1);
                    var te = dvui.textEntry(@src(), .{}, .{ .min_size_content = size, .max_size_content = .cast(size) });
                    defer te.deinit();
                    if (dvui.firstFrame(te.data().id)) {
                        te.textSet(menu_item.label, false);
                    }
                    menu_item.label = te.textGet();
                }
                if (dvui.buttonIcon(@src(), "delete", dvui.entypo.circle_with_minus, .{}, .{}, .{ .expand = .both })) {
                    to_remove = i;
                    continue;
                }
                if (dvui.buttonIcon(@src(), "add", dvui.entypo.circle_with_plus, .{}, .{}, .{ .expand = .both })) {
                    const label = std.fmt.allocPrint(allocator, "Sub {d}...", .{menu_item.sub_items.items.len + 1}) catch return resetWidget(.oom);
                    menu_item.sub_items.append(allocator, .{ .label = label, .id = menuId() }) catch return resetWidget(.oom);
                }
            }
            displayMenuControls(&menu_item.sub_items);
        }
        if (to_remove) |index| {
            _ = items.orderedRemove(index);
            to_remove = null;
        }
    }
};

const DisplayPaned = struct {
    const name: []const u8 = "paned()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.PanedWidget.InitOptions = undefined;
    var split_ratio: f32 = undefined;
    var auto_fit: bool = false;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .expand = .both };
        init_opts = .{ .direction = .horizontal, .collapsed_size = 0 };
        split_ratio = 0.5;
        auto_fit = false;
    }

    pub fn layoutWidget() void {
        var paned = dvui.paned(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer paned.deinit();
        if (auto_fit) {
            paned.autoFit();
            auto_fit = false;
        }

        if (paned.showFirst()) {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .border = .all(1), .corner_radius = .all(5) });
            defer hbox.deinit();
            if (paned.collapsed() and !paned.collapsing) {
                if (dvui.buttonIcon(
                    @src(),
                    "chevron",
                    if (init_opts.direction == .horizontal) dvui.entypo.chevron_thin_left else dvui.entypo.chevron_thin_up,
                    .{},
                    .{},
                    .{ .min_size_content = .all(25), .gravity_x = 1.0 },
                )) {
                    paned.animateSplit(0.0);
                }
            }

            dvui.icon(@src(), "lock", if (paned.collapsed()) dvui.entypo.lock else dvui.entypo.lock_open, .{}, .{ .expand = .both });
        }
        if (paned.showSecond()) {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .border = .all(1), .corner_radius = .all(5) });
            defer hbox.deinit();
            if (paned.collapsed() and !paned.collapsing) {
                if (dvui.buttonIcon(
                    @src(),
                    "chevron",
                    if (init_opts.direction == .horizontal) dvui.entypo.chevron_thin_right else dvui.entypo.chevron_thin_down,

                    .{},
                    .{},
                    .{
                        .min_size_content = .all(25),
                        .gravity_x = if (init_opts.direction == .vertical) 1.0 else null,
                    },
                )) {
                    paned.animateSplit(1.0);
                }
            }

            dvui.icon(@src(), "key", dvui.entypo.key, .{}, .{ .expand = .both });
        }
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
            defer container.deinit();
            auto_fit = dvui.button(@src(), "Auto fit", .{}, .{});
            dvui.labelNoFmt(@src(), "*requires autofit_first to be set", .{}, .{});
        }
        const display_opts: StructOptions(dvui.PanedWidget.InitOptions) = .initWithDefaults(.{}, .{
            .direction = .horizontal,
            .split_ratio = &split_ratio,
            .collapsed_size = 0,
        });
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{display_opts}, .{});
    }
};

const DisplayPlot = struct {
    const name: []const u8 = "plot()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.PlotWidget.InitOptions = undefined;
    var x_axis: dvui.PlotWidget.Axis = undefined;
    var y_axis: dvui.PlotWidget.Axis = undefined;

    var test_options: struct {
        plot_type: enum { bar, line },
        nr_points: u8,
        seed: u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .expand = .both };
        init_opts = .{};
        test_options = .{
            .plot_type = .bar,
            .nr_points = 5,
            .seed = 1,
        };
        x_axis = .{
            .name = "X",
        };
        y_axis = .{
            .name = "Y",
        };
    }

    pub fn layoutWidget() void {
        var rng: std.Random.DefaultPrng = .init(test_options.seed);
        var plot = dvui.plot(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer plot.deinit();
        switch (test_options.plot_type) {
            .bar => {
                for (0..test_options.nr_points) |i| {
                    const point_nr: f64 = @floatFromInt(i);
                    plot.bar(.{ .x = point_nr * 15, .y = 0, .w = 10, .h = @floatFromInt(rng.next() % 100) });
                }
            },
            .line => {
                var line = plot.line();
                defer line.deinit();
                for (0..test_options.nr_points) |i| {
                    const point_nr: f64 = @floatFromInt(i);

                    line.point(10 * point_nr, @floatFromInt(rng.next() % 100));
                }
                line.stroke(2, .blue);
            },
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
        const axis_opts: StructOptions(dvui.PlotWidget.Axis) = .initWithDefaults(.{
            .name = .defaultTextRW,
        }, null);
        const tick_opts: StructOptions(dvui.PlotWidget.Axis.TickFormating) = .initWithDefaults(.{
            .custom = .defaultHidden,
        }, .{ .normal = .{} });
        //const location_opts: StructOptions(@TypeOf(init_opts.x_axis.?.ticks.locations)) = .initWithDefaults(.{}, .{.{}});
        const display_opts: StructOptions(dvui.PlotWidget.InitOptions) = .initWithDefaults(.{
            .title = .defaultTextRW,
        }, .{
            .x_axis = &x_axis,
            .y_axis = &y_axis,
        });
        dvui.structUI(@src(), "init_opts", &init_opts, 3, .{ display_opts, axis_opts, struct_options.color, tick_opts }, .{});
    }
};

const DisplayPlotXY = struct {
    const name: []const u8 = "plotXY()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.PlotXYOptions = undefined;
    var x_axis: dvui.PlotWidget.Axis = undefined;
    var y_axis: dvui.PlotWidget.Axis = undefined;
    var xs: [20]f64 = undefined;
    var ys: [20]f64 = undefined;

    var test_options: struct {
        plot_type: enum { bar, line },
        seed: u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .expand = .both };
        init_opts = .{ .xs = &xs, .ys = &ys };
        test_options = .{
            .plot_type = .bar,
            .seed = 1,
        };
        x_axis = .{
            .name = "X",
        };
        y_axis = .{
            .name = "Y",
        };
    }

    pub fn layoutWidget() void {
        var rng: std.Random.DefaultPrng = .init(test_options.seed);
        for (0..xs.len) |i| {
            xs[i] = @floatFromInt(rng.next() % 50);
            ys[i] = @floatFromInt(rng.next() % 50);
        }

        dvui.plotXY(@src(), init_opts, options.override(.{ .data_out = &wd }));
    }

    // TODO: make these options shared if possible.
    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{}, .{});
        const axis_opts: StructOptions(dvui.PlotWidget.Axis) = .initWithDefaults(.{
            .name = .defaultTextRW,
        }, null);
        const tick_opts: StructOptions(dvui.PlotWidget.Axis.TickFormating) = .initWithDefaults(.{
            .custom = .defaultHidden,
        }, .{ .normal = .{} });
        const plot_opts: StructOptions(dvui.PlotWidget.InitOptions) = .initWithDefaults(.{
            .title = .defaultTextRW,
        }, .{
            .x_axis = &x_axis,
            .y_axis = &y_axis,
        });
        const display_opts: StructOptions(dvui.PlotXYOptions) = .initWithDefaults(.{
            .xs = .{ .standard = .{ .default_expanded = false } },
            .ys = .{ .standard = .{ .default_expanded = false } },
        }, null);
        dvui.structUI(@src(), "init_opts", &init_opts, 3, .{ display_opts, plot_opts, axis_opts, struct_options.color, tick_opts }, .{});
    }
};

const DisplayProgress = struct {
    const name: []const u8 = "progress()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.Progress_InitOptions = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .expand = .horizontal };
        init_opts = .{ .percent = 0.5 };
    }

    pub fn layoutWidget() void {
        dvui.progress(@src(), init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutWidgetControls() void {
        const prev_dir = init_opts.dir;
        const display_opts: StructOptions(dvui.Progress_InitOptions) = .initWithDefaults(.{
            .percent = .{ .number = .{ .widget_type = .slider_entry, .min = 0, .max = 1 } },
        }, null);
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{ display_opts, struct_options.color }, .{});
        if (prev_dir != init_opts.dir) {
            options.expand = if (init_opts.dir == .horizontal) .horizontal else .vertical;
        }
    }
};

const DisplayRadio = struct {
    const name: []const u8 = "radio()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var result: bool = false;
    var test_options: struct {
        active: bool,
        label_str: []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        test_options = .{
            .active = false,
            .label_str = "radio button",
        };
    }

    pub fn layoutWidget() void {
        result = dvui.radio(@src(), test_options.active, test_options.label_str, options.override(.{ .data_out = &wd }));
        if (result) {
            test_options.active = true;
        }
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .widget_type = .{ .trigger_on = true }, .display = .read_only } }, &al);
    }

    pub fn layoutWidgetControls() void {
        const display_opts: StructOptions(@TypeOf(test_options)) = .initWithDefaults(.{
            .active = .{ .boolean = .{ .widget_type = .checkbox } },
            .label_str = .defaultTextRW,
        }, null);
        dvui.structUI(@src(), test_options_label, &test_options, 1, .{display_opts}, .{});
    }
};

const DisplayRadioGroup = struct {
    const name: []const u8 = "radioGroup()";
    const nr_radio_buttons = 3;

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.FocusGroupWidget.InitOptions = undefined;
    var result: bool = false;
    var test_options: struct {
        active: [nr_radio_buttons]bool,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{};
        test_options = .{
            .active = @splat(false),
        };
    }

    pub fn layoutWidget() void {
        {
            var rgroup = dvui.radioGroup(@src(), init_opts, options.override(.{ .data_out = &wd }));
            defer rgroup.deinit();

            inline for (0..nr_radio_buttons) |i| {
                if (dvui.radio(@src(), test_options.active[i], std.fmt.comptimePrint("radio {}", .{i}), .{ .id_extra = i })) {
                    test_options.active = @splat(false);
                    test_options.active[i] = true;
                }
            }
        }
        var tl = dvui.textLayout(@src(), .{ .break_lines = true }, .{ .expand = .horizontal });
        defer tl.deinit();
        tl.addText("Radio buttons in a radio group can be navigated using the arrow keys", .{ .gravity_y = 1.0, .gravity_x = 0.5 });
    }

    pub fn layoutResults() void {
        const test_options_c = test_options;
        dvui.structUI(@src(), null, &test_options_c, 1, .{}, .{});
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{}, .{});
    }
};

const DisplayScale = struct {
    const name: []const u8 = "scale()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.ScaleWidget.InitOptions = undefined;
    var scale: f32 = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{ .scale = &scale };
        scale = 1.0;
    }

    pub fn layoutWidget() void {
        var scalew = dvui.scale(@src(), init_opts, options.override(.{ .data_out = &wd, .expand = .both }));
        defer scalew.deinit();
        dvui.labelNoFmt(@src(), "Scalable", .{}, .{ .border = .all(1), .color_border = dvui.themeGet().focus, .gravity_x = 0.5, .gravity_y = 0.5 });
    }

    pub fn layoutWidgetControls() void {
        const display_opts = StructOptions(dvui.ScaleWidget.InitOptions).initWithDefaults(.{
            .scale = .{ .number = .{ .widget_type = .slider_entry, .min = 0, .max = 10 } },
        }, .{ .scale = &scale });
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{display_opts}, .{});
    }
};

const DisplayScrollArea = struct {
    const name: []const u8 = "scrollArea()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.ScrollAreaWidget.InitOpts = undefined;
    var scroll_info: dvui.ScrollInfo = undefined;

    var top_left_wd: dvui.WidgetData = undefined;
    var bottom_right_wd: dvui.WidgetData = undefined;
    var check_top_left: bool = false;
    var check_bottom_right = false;
    var user_scroll: dvui.Point = undefined;

    var focus_id: enum { null, top_left, bottom_right } = undefined;

    var nr_boxes: struct {
        w: usize,
        h: usize,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{};
        scroll_info = .{};
        nr_boxes = .{ .w = 20, .h = 20 };
        focus_id = .null;
        check_bottom_right = false;
        check_top_left = false;
        user_scroll = .{ .x = 0, .y = 0 };
    }

    pub fn layoutWidget() void {
        const box_size = 26;
        const color_fill = options.color(.border).opacity(0.25);

        options.min_size_content = if (init_opts.scroll_info == null) null else .{ .w = @floatFromInt(nr_boxes.w * (box_size + 2)), .h = @floatFromInt(nr_boxes.h * (box_size + 2)) };
        init_opts.focus_id = switch (focus_id) {
            .null => null,
            .top_left => top_left_wd.id,
            .bottom_right => bottom_right_wd.id,
        };

        var scroll = dvui.scrollArea(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer scroll.deinit();
        var vbox = dvui.box(@src(), .{}, .{ .expand = .both });
        defer vbox.deinit();
        for (0..nr_boxes.h) |i| {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = i });
            defer hbox.deinit();
            for (0..nr_boxes.w) |j| {
                var box = dvui.box(@src(), .{}, .{ .min_size_content = .all(box_size), .color_border = color_fill, .color_fill = if ((i + j) % 2 == 0) color_fill else null, .id_extra = i * 1_000_000 + j, .border = .all(1), .background = true });
                defer box.deinit();
                if (i == 0 and j == 0) {
                    _ = dvui.buttonIcon(@src(), "top_left", dvui.entypo.hair_cross, .{}, .{}, .{ .data_out = &top_left_wd, .expand = .both, .padding = .all(0) });
                } else if (i == nr_boxes.h - 1 and j == nr_boxes.w - 1) {
                    _ = dvui.buttonIcon(@src(), "bottom_right", dvui.entypo.hair_cross, .{}, .{}, .{ .data_out = &bottom_right_wd, .expand = .both, .padding = .all(0) });
                }
            }
        }
        if (init_opts.scroll_info) |si| {
            if (si.horizontal == .given) {
                si.virtual_size.w = options.min_size_content.?.w;
            }
            if (si.vertical == .given) {
                si.virtual_size.h = options.min_size_content.?.h;
            }
        }
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
            defer container.deinit();
            const display_opts: StructOptions(@TypeOf(nr_boxes)) = .init(.{
                .w = .{ .number = .{ .min = 2, .max = 200 } },
                .h = .{ .number = .{ .min = 2, .max = 200 } },
            }, null);
            var al: dvui.Alignment = .init(@src(), 0);
            defer al.deinit();
            if (struct_ui.displayStruct(@src(), "Boxes", &nr_boxes, 1, .default, .{display_opts}, &al)) |container_inner| {
                defer container_inner.deinit();
            }
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();
            dvui.icon(@src(), "box", dvui.entypo.hair_cross, .{}, .{ .max_size_content = .all(25), .gravity_y = 0.5, .padding = .{ .x = 6 } });
            al.spacer(@src(), 0);
            dvui.labelNoFmt(@src(), "Focus with focus_id\nthen click scrollbar", .{}, .{});
        }
        const display_opts: StructOptions(dvui.ScrollAreaWidget.InitOpts) = .initWithDefaults(.{
            .focus_id = .{ .standard = .{ .customDisplayFn = displayFocusId } },
            .user_scroll = .defaultConst,
        }, .{ .scroll_info = &scroll_info, .frame_viewport = .{ .x = 100, .y = 100 }, .user_scroll = &user_scroll });
        const si_opts: StructOptions(dvui.ScrollInfo) = .initWithDefaults(.{
            .viewport = .{ .number = .{ .customDisplayFn = displayViewport } },
            .virtual_size = .defaultConst,
        }, null);
        // Only override the Point type display widget type for fields named "velocity"
        const velocity_opts = StructOptions(dvui.Point).init(.{
            .x = .{ .number = .{ .widget_type = .entry_on_enter } },
            .y = .{ .number = .{ .widget_type = .entry_on_enter } },
        }, null).forFieldName("velocity");

        dvui.structUI(@src(), "init_opts", &init_opts, 2, .{ display_opts, velocity_opts, si_opts }, .{});
    }

    /// Show sliders for the viewport x if init_opts.scroll_info.horizontal.horizontal == .given
    /// Show sliders for the viewport y if init_opts.scroll_info.horizontal.vertical == .given
    fn displayViewport(field_name: []const u8, ptr: *anyopaque, _: bool, _: *dvui.Alignment) void {
        const field_value_ptr: *Rect = @ptrCast(@alignCast(ptr));

        if (struct_ui.displayContainer(@src(), field_name, true)) |container| {
            defer container.deinit();
            var al: dvui.Alignment = .init(@src(), 0);
            defer al.deinit();
            if (init_opts.scroll_info) |si| {
                struct_ui.displayNumber(@src(), "x", &field_value_ptr.x, .{
                    .number = .{
                        .widget_type = if (si.horizontal == .given) .slider_entry else .number_entry,
                        .min = 0,
                        .max = scroll_info.virtual_size.w - scroll_info.viewport.w,
                        .display = if (si.horizontal == .given) .read_write else .read_only,
                    },
                }, &al);
                struct_ui.displayNumber(@src(), "y", &field_value_ptr.y, .{
                    .number = .{
                        .widget_type = if (si.vertical == .given) .slider_entry else .number_entry,
                        .min = 0,
                        .max = scroll_info.virtual_size.h - scroll_info.viewport.h,
                        .display = if (si.vertical == .given) .read_write else .read_only,
                    },
                }, &al);
            } else {
                struct_ui.displayNumber(@src(), "x", &field_value_ptr.x, .defaultReadOnly, &al);
                struct_ui.displayNumber(@src(), "y", &field_value_ptr.y, .defaultReadOnly, &al);
            }
            struct_ui.displayNumber(@src(), "w", &field_value_ptr.w, .defaultReadOnly, &al);
            struct_ui.displayNumber(@src(), "h", &field_value_ptr.h, .defaultReadOnly, &al);
        }
    }

    fn displayFocusId(field_name: []const u8, _: *anyopaque, _: bool, alignment: *dvui.Alignment) void {
        var box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer box.deinit();

        dvui.label(@src(), "{s}", .{field_name}, .{});
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());

        const selected_index: usize = @intFromEnum(focus_id);

        var dd: dvui.DropdownWidget = undefined;
        dd.init(@src(), .{ .selected_index = selected_index, .label = if (selected_index == 0) "null" else if (selected_index == 1) "top left" else "bottom right" }, .{});
        defer dd.deinit();

        if (dd.dropped()) {
            {
                var mi = dd.addChoice();
                defer mi.deinit();
                dvui.labelNoFmt(@src(), "null", .{}, .{});
                if (mi.activeRect()) |_| {
                    dd.close();
                    init_opts.focus_id = null;
                }
            }
            {
                var mi = dd.addChoice();
                defer mi.deinit();
                dvui.label(@src(), "top left\n{f}", .{top_left_wd.id}, .{});
                if (mi.activeRect()) |_| {
                    dd.close();
                    focus_id = .top_left;
                }
            }
            {
                var mi = dd.addChoice();
                defer mi.deinit();
                dvui.label(@src(), "bottom right\n{f}", .{bottom_right_wd.id}, .{});
                if (mi.activeRect()) |_| {
                    dd.close();
                    focus_id = .bottom_right;
                }
            }
        }
    }
};

const DisplaySeparator = struct {
    const name: []const u8 = "separator()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var result: dvui.WidgetData = undefined;
    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{
            .expand = .horizontal,
            .gravity_y = 0.5,
        };
    }

    pub fn layoutWidget() void {
        result = dvui.separator(@src(), options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        const result_c = result;
        dvui.structUI(@src(), "rect", &result_c.rect, 1, .{}, .{});
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
            defer container.deinit();
            var al: dvui.Alignment = .init(@src(), 0);
            defer al.deinit();
            struct_ui.displayOptional(@src(), dvui.Options, "expand", &options.expand, 1, .default, .{}, &al, .horizontal);
            struct_ui.displayOptional(@src(), dvui.Options, "min_size_content", &options.min_size_content, 1, .default, .{}, &al, .all(1));
        }
    }
};

const DisplaySlider = struct {
    const name: []const u8 = "slider()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.SliderInitOptions = undefined;
    var result: bool = undefined;
    var fraction: f32 = undefined;
    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        fraction = 0;
        options = .{
            .expand = .horizontal,
            .gravity_y = 0.5,
        };
        init_opts = .{
            .fraction = &fraction,
        };
    }

    pub fn layoutWidget() void {
        result = dvui.slider(@src(), init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .display = .read_only } }, &al);
    }

    pub fn layoutWidgetControls() void {
        const prev_dir = init_opts.dir;
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_options.color}, .{});
        if (prev_dir != init_opts.dir) {
            options.expand = if (init_opts.dir == .horizontal) .horizontal else .vertical;
        }
    }
};

const DisplaySliderEntry = struct {
    const name: []const u8 = "sliderEntry()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.SliderEntryInitOptions = undefined;
    var result: bool = undefined;

    var test_options: struct {
        value: f32,
        label_fmt: ?[]const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{
            .expand = .horizontal,
            .gravity_y = 0.5,
        };
        init_opts = .{
            .value = &test_options.value,
            .min = 0,
            .max = 100,
            .interval = 1,
        };
        test_options = .{
            .value = 0,
            .label_fmt = "{d:0.1}",
        };
    }

    pub fn layoutWidget() void {
        if (test_options.label_fmt) |_|
            result = dvui.sliderEntry(@src(), "{d:0.1}", init_opts, options.override(.{ .data_out = &wd }))
        else
            result = dvui.sliderEntry(@src(), null, init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .display = .read_only } }, &al);
    }

    pub fn layoutWidgetControls() void {
        {
            const display_options: StructOptions(@TypeOf(test_options)) = .initWithDefaults(.{
                .label_fmt = .{ .optional = .{ .child = .{ .text = .{ .display = .read_only } } } },
            }, .{ .label_fmt = "{d:0.1}", .value = 0 });
            dvui.structUI(@src(), test_options_label, &test_options, 1, .{display_options}, .{});
        }
        {
            const display_options = StructOptions(dvui.SliderEntryInitOptions).initWithDefaults(.{
                .label = .defaultTextRW,
            }, .{ .label = "slider entry", .value = &test_options.value });
            dvui.structUI(@src(), "init_opts", &init_opts, 1, .{display_options}, .{});
        }
    }
};

const DisplaySliderVector = struct {
    const name: []const u8 = "sliderVector()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.SliderVectorInitOptions = undefined;
    var result: bool = undefined;

    const pi = std.math.pi;
    var slider_values = [_]f32{ -2 * pi, -pi, 0, pi, 2 * pi };

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{ .min = -2 * pi, .max = 2 * pi, .interval = 0.01 };
    }

    pub fn layoutWidget() void {
        result = dvui.sliderVector(@src(), "{d:0.2}", 5, &slider_values, init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        var al = dvui.Alignment.init(@src(), 0);
        defer al.deinit();
        struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .display = .read_only } }, &al);
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_options.color}, .{});
    }
};

const DisplaySpacer = struct {
    const name: []const u8 = "spacer()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var result_wd: dvui.WidgetData = undefined;
    var border: bool = false;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .min_size_content = .{ .h = 50, .w = 50 }, .expand = .horizontal };
        border = false;
    }

    pub fn layoutWidget() void {
        dvui.labelNoFmt(@src(), "Before Spacer", .{}, .{});
        result_wd = dvui.spacer(@src(), options.override(.{ .data_out = &wd }));
        dvui.labelNoFmt(@src(), "After Spacer", .{}, .{});
    }

    pub fn layoutResults() void {
        const result_c = result_wd;
        dvui.structUI(@src(), "rect", &result_c.rect, 1, .{}, .{});
    }

    pub fn layoutWidgetControls() void {
        const display_opts = StructOptions(dvui.Options).init(.{
            .min_size_content = .default,
            .expand = .default,
        }, .{ .min_size_content = .{ .h = 50, .w = 50 } });

        var al: dvui.Alignment = .init(@src(), 0);
        defer al.deinit();

        if (struct_ui.displayStruct(@src(), test_options_label, &options, 1, .default, .{display_opts}, &al)) |container| {
            defer container.deinit();
            border = options.border != null;
            const prev_border = border;
            struct_ui.displayBool(@src(), "border", &border, .{ .boolean = .{ .widget_type = .checkbox } }, &al);
            if (prev_border != border) {
                if (border) {
                    options.border = .all(1);
                } else {
                    options.border = null;
                }
            }
        }
    }
};

const DisplaySpinner = struct {
    const name: []const u8 = "spinner()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{ .color_text = .green };
    }

    pub fn layoutWidget() void {
        dvui.spinner(@src(), options.override(.{ .data_out = &wd }));
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label, true)) |container| {
            defer container.deinit();
            var al: dvui.Alignment = .init(@src(), 0);
            defer al.deinit();
            struct_ui.displayOptional(@src(), dvui.Options, "color_text", &options.color_text, 1, .default, .{struct_options.color}, &al, .green);
        }
    }
};

const DisplayTabs = struct {
    const name: []const u8 = "tabs()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.TabsWidget.InitOptions = undefined;

    var active_tab: usize = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{};
        active_tab = 0;
    }

    pub fn layoutWidget() void {
        // reverse orientation because horizontal tabs go above content
        var tbox = dvui.box(@src(), .{ .dir = if (init_opts.dir == .vertical) .horizontal else .vertical }, .{ .expand = .both });
        defer tbox.deinit();

        {
            var tabs = dvui.tabs(@src(), init_opts, options.override(.{ .data_out = &wd }));
            defer tabs.deinit();

            inline for (0..8) |i| {
                const tabname = std.fmt.comptimePrint("Tab {d}", .{i});
                if (i != 3) {
                    // easy label only
                    if (tabs.addTabLabel(active_tab == i, tabname, .{})) {
                        active_tab = i;
                    }
                } else {
                    // directly put whatever in the tab
                    var tab = tabs.addTab(active_tab == i, .{});
                    defer tab.deinit();

                    var tab_box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
                    defer tab_box.deinit();

                    dvui.icon(@src(), "cycle", dvui.entypo.cycle, .{}, .{});

                    _ = dvui.spacer(@src(), .{ .min_size_content = .width(4) });

                    var label_opts = tab.data().options.strip();
                    if (dvui.captured(tab.data().id)) {
                        label_opts.color_text = (dvui.Options{}).color(.text_press);
                    }

                    dvui.labelNoFmt(@src(), tabname, .{}, label_opts);

                    if (tab.clicked()) {
                        active_tab = i;
                    }
                }
            }
        }

        {
            var border: dvui.Rect = .all(1);
            switch (init_opts.dir) {
                .horizontal => border.y = 0,
                .vertical => border.x = 0,
            }
            var vbox3 = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .style = .window, .border = border, .role = .tab_panel });
            defer vbox3.deinit();

            dvui.labelEx(@src(), "This is tab {d}", .{active_tab}, .{ .align_x = 0.5, .align_y = 0.5 }, .{ .expand = .horizontal });
            if (active_tab == 3) {
                dvui.icon(@src(), "icon", dvui.entypo.aircraft, .{}, .{ .min_size_content = .all(30), .gravity_x = 0.5 });
            }
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{}, .{});
    }
};

const DisplayTabGroup = struct {
    const name: []const u8 = "tabIndexGroup()";

    // TODO: Both of these stay undefined, because there are no
    // options. Next widgetpedia PR will have ability to hanlde widgets without options.
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;

    var active_tab: usize = undefined;
    var tab_group_index: struct {
        @".tab_index (red)": u16,
        @".tab_index (green)": u16,
        @".tab_index (blue)": u16,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        active_tab = 0;
        tab_group_index = .{
            .@".tab_index (red)" = 1,
            .@".tab_index (green)" = 2,
            .@".tab_index (blue)" = 3,
        };
    }

    pub fn layoutWidget() void {
        var tig_outer = dvui.tabIndexGroup(@src(), .{});
        defer tig_outer.deinit();
        {
            var tig = dvui.tabIndexGroup(@src(), .{ .tab_index = tab_group_index.@".tab_index (red)" });
            defer tig.deinit();
            var box = dvui.box(@src(), .{}, .{ .border = .all(2), .margin = .all(1), .color_border = .red, .expand = .horizontal });
            defer box.deinit();
            _ = dvui.button(@src(), "One", .{}, .{ .expand = .horizontal, .color_text = .red });
            _ = dvui.button(@src(), "Two", .{}, .{ .expand = .horizontal, .color_text = .red });
        }
        defer tig_outer.deinit();
        {
            var tig = dvui.tabIndexGroup(@src(), .{ .tab_index = tab_group_index.@".tab_index (green)" });
            defer tig.deinit();
            var box = dvui.box(@src(), .{}, .{ .border = .all(2), .margin = .all(1), .color_border = .green, .expand = .horizontal });
            defer box.deinit();
            var fg = dvui.focusGroup(@src(), .{ .nav_key_dir = .vertical, .wrap = true }, .{});
            defer fg.deinit();
            var gbox = dvui.groupBox(@src(), "in focus group", .{ .expand = .horizontal });
            defer gbox.deinit();
            _ = dvui.button(@src(), "One", .{}, .{ .expand = .horizontal, .color_text = .green });
            _ = dvui.button(@src(), "Two", .{}, .{ .expand = .horizontal, .color_text = .green });
        }
        defer tig_outer.deinit();
        {
            var tig = dvui.tabIndexGroup(@src(), .{ .tab_index = tab_group_index.@".tab_index (blue)" });
            defer tig.deinit();
            var box = dvui.box(@src(), .{}, .{ .border = .all(2), .margin = .all(1), .color_border = .blue, .expand = .horizontal });
            defer box.deinit();
            _ = dvui.button(@src(), "Two", .{}, .{ .expand = .horizontal, .color_text = .blue, .tab_index = 2 });
            _ = dvui.button(@src(), "One", .{}, .{ .expand = .horizontal, .color_text = .blue, .tab_index = 1 });
        }
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), test_options_label, &tab_group_index, 1, .{}, .{});
    }
};

const DisplayTextEntry = struct {
    const name: []const u8 = "textEntry()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.TextEntryWidget.InitOptions = undefined;

    const Configuration = enum {
        single_line,
        password,
        multiline,
        large,
        all,
        // TODO: Syntax highlighting
    };
    var configuration: Configuration = undefined;
    var configuration_changed: bool = false;
    var num_done: usize = undefined;

    var large_opts: struct {
        // cache_ok: bool,
        copies: usize,
        refresh: bool,
    } = undefined;

    var filter_opts: struct {
        filter_in: ?[]const u8 = null,
        filter_out: ?[]const u8 = null,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{};
        filter_opts = .{};
        configuration = .single_line;
        configuration_changed = true;
        large_opts = .{
            //            .cache_ok = false,
            .copies = 100,
            .refresh = false,
        };
        num_done = 0;
    }

    pub fn layoutWidget() void {
        defer configuration_changed = false;

        if (configuration_changed) {
            switch (configuration) {
                .single_line, .all => {
                    init_opts = .{};
                    options = .{ .expand = .horizontal };
                },
                .password => {
                    init_opts = .{ .password_char = "*" };
                    options = .{ .expand = .horizontal };
                },
                .multiline => {
                    init_opts = .{
                        .multiline = true,
                        .break_lines = true,
                        .scroll_horizontal = false,
                    };
                    options = .{ .expand = .both };
                },
                .large => {
                    init_opts = .{
                        .multiline = true,
                        .cache_layout = true,
                        .scroll_horizontal = false,
                        .break_lines = true,
                        .text = .{ .internal = .{ .limit = 2_000_000 } },
                    };
                    options = .{ .expand = .both };
                },
            }
        }

        if (configuration == .large) {
            return layoutWidgetLarge();
        } else {
            var te = dvui.textEntry(@src(), init_opts, options.override(.{ .data_out = &wd }));
            defer te.deinit();
            if (configuration_changed) {
                te.textSet("", false);
            }
            switch (configuration) {
                .single_line, .all => {
                    if (filter_opts.filter_in) |in| te.filterIn(in);
                    if (filter_opts.filter_out) |out| te.filterOut(out);
                },
                .password => {},
                .multiline => {
                    if (configuration_changed) {
                        for (lorem) |text| {
                            te.textTyped(text, false);
                        }
                        te.textLayout.selection.moveCursor(0, false);
                    }
                },
                .large => unreachable,
            }
        }
    }

    fn layoutWidgetLarge() void {
        if (large_opts.refresh) {
            dvui.refresh(null, @src(), null);
        }

        var tl: dvui.TextEntryWidget = undefined;
        tl.init(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer tl.deinit();
        tl.processEvents();

        if (configuration_changed) {
            num_done = 0;
            tl.textSet("", false);
        }

        if (num_done < large_opts.copies) {
            const lorem1 = "Header line with 9 indented\n";
            const lorem2 = "    an indented line\n";

            for (num_done..@min(num_done + 10, large_opts.copies)) |i| {
                num_done += 1;
                var buf2: [10]u8 = undefined;
                const written = std.fmt.bufPrint(&buf2, "{d} ", .{i}) catch unreachable;
                tl.textTyped(written, false);
                tl.textTyped(lorem1, false);
                for (0..9) |_| {
                    tl.textTyped(lorem2, false);
                }
            }
        }

        tl.draw();
    }

    pub fn layoutWidgetControls() void {
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "Configuration:", .{ .align_y = 0.5 }, .{ .expand = .vertical });
            if (dvui.dropdownEnum(@src(), Configuration, .{ .choice = &configuration }, .{}, .{ .expand = .horizontal })) {
                configuration_changed = true;
            }
        }
        switch (configuration) {
            .single_line => {
                dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_ui.StructOptions(dvui.TextEntryWidget.InitOptions).init(.{
                    .placeholder = .defaultTextRW,
                }, null)}, .{});
                dvui.structUI(@src(), "Filter options", &filter_opts, 1, .{StructOptions(@TypeOf(filter_opts)).init(.{
                    .filter_in = .defaultTextRW,
                    .filter_out = .defaultTextRW,
                }, null)}, .{});
            },
            .password => dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_ui.StructOptions(dvui.TextEntryWidget.InitOptions).init(.{
                .placeholder = .defaultTextRW,
                .password_char = .defaultTextRW,
            }, .{ .password_char = "*" })}, .{}),
            .multiline => structDisplayMultiLineInitOpts(&init_opts),
            .large => {
                const old_copies = large_opts.copies;
                dvui.structUI(@src(), test_options_label, &large_opts, 1, .{StructOptions(@TypeOf(large_opts)).initWithDefaults(.{
                    .refresh = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
                    .copies = .{ .number = .{ .widget_type = .slider_entry, .min = 0, .max = 1000 } },
                }, null)}, .{});
                if (large_opts.copies != old_copies)
                    configuration_changed = true;
                structDisplayMultiLineInitOpts(&init_opts);
            },
            .all => {
                dvui.structUI(@src(), "Filter options", &filter_opts, 1, .{StructOptions(@TypeOf(filter_opts)).init(.{
                    .filter_in = .defaultTextRW,
                    .filter_out = .defaultTextRW,
                }, null)}, .{});
                dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_options.text_entry.init_opts}, .{});
            },
        }
    }

    fn structDisplayMultiLineInitOpts(field_value_ptr: *dvui.TextEntryWidget.InitOptions) void {
        const T = dvui.TextEntryWidget.InitOptions;

        if (struct_ui.displayContainer(@src(), "init_opts", true)) |container| {
            defer container.deinit();
            var al: dvui.Alignment = .init(@src(), 0);
            defer al.deinit();

            switch (configuration) {
                .multiline => {
                    struct_ui.displayBool(@src(), "multiline", &field_value_ptr.multiline, .{ .boolean = .{ .widget_type = .checkbox } }, &al);
                    struct_ui.displayBool(@src(), "break_lines", &field_value_ptr.break_lines, .{ .boolean = .{ .widget_type = .checkbox } }, &al);
                    struct_ui.displayOptional(@src(), T, "scroll_vertical", &field_value_ptr.scroll_vertical, 0, .defaultBool, .{}, &al, false);
                    struct_ui.displayOptional(@src(), T, "scroll_vertical_bar", &field_value_ptr.scroll_vertical_bar, 0, .default, .{}, &al, .auto);
                    struct_ui.displayOptional(@src(), T, "scroll_horizontal", &field_value_ptr.scroll_horizontal, 0, .defaultBool, .{}, &al, false);
                    struct_ui.displayOptional(@src(), T, "scroll_horizontal_bar", &field_value_ptr.scroll_horizontal_bar, 0, .default, .{}, &al, .auto);
                },
                .large => {
                    struct_ui.displayBool(@src(), "break_lines", &field_value_ptr.break_lines, .{ .boolean = .{ .widget_type = .checkbox } }, &al);
                    struct_ui.displayOptional(@src(), T, "kerning", &field_value_ptr.kerning, 0, .{ .boolean = .{ .widget_type = .checkbox } }, .{}, &al, null);
                    struct_ui.displayBool(@src(), "cache_layout", &field_value_ptr.cache_layout, .{ .boolean = .{ .widget_type = .checkbox } }, &al);
                },
                else => unreachable,
            }
        }
    }
};

const DisplayTextEntryColor = struct {
    const name = "textEntryColor()";

    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.TextEntryColorInitOptions = undefined;
    var options: dvui.Options = undefined;
    var value: dvui.Color = undefined;
    var result: dvui.TextEntryColorResult = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{};
        options = .{};
        value = .white;
    }

    pub fn layoutWidget() void {
        result = dvui.textEntryColor(@src(), init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        const result_opts: StructOptions(dvui.TextEntryColorResult) = .initWithDefaults(.{
            .changed = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
            .enter_pressed = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
        }, null);
        const r = result;
        dvui.structUI(@src(), null, &r, 2, .{ struct_options.color, result_opts }, .{});
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{
            StructOptions(dvui.TextEntryColorInitOptions).initWithDefaults(.{
                .placeholder = .defaultTextRW,
            }, .{ .value = &value }),
        }, .{});
    }
};

const DisplayTextEntryNumber = struct {
    const NumberType = i32;
    const name = "textEntryNumber()";

    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.TextEntryNumberInitOptions(NumberType) = undefined;
    var options: dvui.Options = undefined;
    var value: NumberType = undefined;
    var result: dvui.TextEntryNumberResult(NumberType) = undefined;
    const init_opts_defaults: dvui.TextEntryNumberInitOptions(NumberType) = .{ .value = &value, .placeholder = "Enter a number", .text = "", .min = -100, .max = 100 };

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        init_opts = .{};
        options = .{ .gravity_y = 0.5 };
        value = -789;
    }

    pub fn layoutWidget() void {
        result = dvui.textEntryNumber(@src(), NumberType, init_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutResults() void {
        const r = result;
        dvui.structUI(@src(), null, &r, 99, .{
            StructOptions(dvui.TextEntryNumberResult(NumberType)).initWithDefaults(.{
                .changed = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
                .enter_pressed = .{ .boolean = .{ .widget_type = .{ .trigger_on = true } } },
            }, null),
        }, .{ .gravity_x = 1.0 });
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{
            StructOptions(dvui.TextEntryNumberInitOptions(NumberType)).initWithDefaults(.{
                .text = .defaultTextRW,
                .placeholder = .defaultTextRW,
            }, init_opts_defaults),
        }, .{});
    }
};

const DisplayToast = struct {
    const name: []const u8 = "toast()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.ToastOptions = undefined;
    var selection: ?enum { @"widgetpedia window" } = null;

    var test_options: struct {
        message: []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{ .message = "Toast Text" };
    }

    pub fn layoutWidget() void {
        init_opts.subwindow_id = if (selection == .@"widgetpedia window") dvui.subwindowCurrentId() else null;
        if (dvui.button(@src(), "Display toast", .{}, .{})) {
            dvui.toast(@src(), init_opts);
        }
    }

    pub fn layoutWidgetControls() void {
        const display_opts: StructOptions(dvui.ToastOptions) = .initWithDefaults(.{
            .window = .defaultHidden,
            .message = .{ .text = .{ .multiline = true, .display = .read_write } },
            .subwindow_id = .{ .standard = .{ .customDisplayFn = displaySubWindowId } },
        }, null);
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{display_opts}, .{});
    }

    fn displaySubWindowId(field_name: []const u8, _: *anyopaque, read_only: bool, alignment: *dvui.Alignment) void {
        if (read_only) return;

        var box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer box.deinit();

        dvui.label(@src(), "{s}", .{field_name}, .{});
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());

        _ = dvui.dropdownEnum(@src(), @TypeOf(selection.?), .{ .choice_nullable = &selection }, .{}, .{});
    }
};

const DisplayToolTip = struct {
    const name: []const u8 = "tooltip()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.FloatingTooltipWidget.InitOptions = undefined;

    var test_options: struct {
        scenario: enum { @"text only", @"with icon" },
        text: []const u8,
    } = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{ .active_rect = .all(0) };
        test_options = .{
            .text = "This is tooltip text",
            .scenario = .@"text only",
        };
    }

    pub fn layoutWidget() void {
        var label_wd: dvui.WidgetData = undefined;
        dvui.labelNoFmt(@src(), "Mouse over me", .{}, .{ .border = .all(1), .data_out = &label_wd, .gravity_x = 0.5, .gravity_y = 0.5 });
        init_opts.active_rect = label_wd.borderRectScale().r;
        switch (test_options.scenario) {
            .@"text only" => dvui.tooltip(@src(), init_opts, "{s}", .{test_options.text}, options.override(.{ .data_out = &wd })),
            .@"with icon" => {
                var tt: dvui.FloatingTooltipWidget = undefined;
                tt.init(@src(), init_opts, options.override(.{ .data_out = &wd }));
                defer tt.deinit();
                if (tt.shown()) {
                    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });
                    defer hbox.deinit();
                    dvui.icon(@src(), "warning", dvui.entypo.warning, .{}, .{ .min_size_content = .all(30), .margin = .all(6) });
                    var tl = dvui.textLayout(@src(), .{}, .{ .background = false, .gravity_y = 0.5 });
                    tl.addText(test_options.text, .{});
                    tl.deinit();
                }
            },
        }
    }

    pub fn layoutWidgetControls() void {
        {
            const display_opts: StructOptions(@TypeOf(test_options)) = .initWithDefaults(.{
                .text = .{ .text = .{ .multiline = true, .display = .read_write } },
            }, null);
            dvui.structUI(@src(), test_options_label, &test_options, 1, .{display_opts}, .{});
        }
        {
            const display_opts = StructOptions(dvui.FloatingTooltipWidget.InitOptions).initWithDefaults(.{
                .delay = .{ .number = .{ .label = "delay (µs)" } },
                .active_rect = .defaultConst,
            }, null);
            dvui.structUI(@src(), "init_opts", &init_opts, 1, .{display_opts}, .{});
        }

        if (init_opts.position == .absolute) {
            if (options.rect == null) {
                options.rect = .{ .x = 100, .y = 100 };
            }

            dvui.structUI(@src(), "options.rect", &options.rect.?, 1, .{}, .{});
        } else {
            options.rect = null;
        }
    }
};

fn structColorPicker(field_name: []const u8, ptr: *anyopaque, read_only: bool, alignment: *dvui.Alignment) void {
    const field_value_ptr: *dvui.Color = @ptrCast(@alignCast(ptr));

    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{field_name}, .{});
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        const text_height = dvui.themeGet().font_body.lineHeight();
        var color_box = dvui.box(@src(), .{}, .{
            .expand = .both,
            .min_size_content = .{ .h = text_height, .w = text_height },
            .color_fill = field_value_ptr.*,
            .background = true,
            .gravity_y = 0.5,
            .margin = .all(6),
        });
        color_box.deinit();
    } else {
        var hsv_color: dvui.Color.HSV = .fromColor(field_value_ptr.*);
        _ = dvui.colorPicker(@src(), .{ .hsv = &hsv_color, .hex_text_entry = false, .dir = .vertical }, .{});
        field_value_ptr.* = hsv_color.toColor();
    }
}

const widget_hierarchy = [_]WidgetHierarchy{
    .{ .name = "animate", .displayFn = DisplayAnimate.displayFn, .children = null },
    .{ .name = "box", .displayFn = DisplayBox.displayFn, .children = null },

    .{ .name = "buttons", .displayFn = displayEmpty, .children = &.{
        .{ .name = "button", .displayFn = DisplayButton.displayFn, .children = null },
        .{ .name = "buttonIcon", .displayFn = DisplayButtonIcon.displayFn, .children = null },
        .{ .name = "buttonLabelAndIcon", .displayFn = DisplayButtonLabelAndIcon.displayFn, .children = null },
    } },

    .{ .name = "checkbox", .displayFn = DisplayCheckbox.displayFn, .children = null },
    .{ .name = "colorPicker", .displayFn = DisplayColorPicker.displayFn, .children = null },
    .{ .name = "comboBox", .displayFn = DisplayComboBox.displayFn, .children = null },
    .{ .name = "context", .displayFn = DisplayContext.displayFn, .children = null },
    .{ .name = "dialog", .displayFn = displayEmpty, .children = null },
    .{ .name = "dropdowns", .displayFn = displayEmpty, .children = &.{
        .{ .name = "dropdown", .displayFn = DisplayDropDown.displayFn, .children = null },
        .{ .name = "dropdownEnum", .displayFn = DisplayDropDownEnum.displayFn, .children = null },
    } },
    .{ .name = "expander", .displayFn = DisplayExpander.displayFn, .children = null },
    .{ .name = "flexbox", .displayFn = DisplayFlexBox.displayFn, .children = null },
    // FloatingMenuWidget is typically combined with other widgets, and not used standalone.
    //    .{ .name = "floatingMenu", .displayFn = displayEmpty, .children = null },

    .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = &.{
        .{ .name = "floatingWindow", .displayFn = DisplayFloatingWindow.displayFn, .children = null },
        .{ .name = "windowHeader", .displayFn = DisplayWindowHeader.displayFn, .children = null },
    } },

    .{ .name = "focusGroup", .displayFn = DisplayFocusGroup.displayFn, .children = null },

    .{ .name = "grid", .displayFn = displayEmpty, .children = &.{
        .{ .name = "grid", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeading", .displayFn = displayEmpty, .children = null },
        .{ .name = "columnLayoutProportional", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingCheckbox", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingSeparator", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingSortable", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "groupBox", .displayFn = DisplayGroupBox.displayFn, .children = null },
    .{ .name = "icon", .displayFn = DisplayIcon.displayFn, .children = null },
    .{ .name = "image", .displayFn = displayEmpty, .children = null },

    .{ .name = "labels", .displayFn = displayEmpty, .children = &.{
        .{ .name = "label", .displayFn = DisplayLabelEx.displayFn, .children = null },
        .{ .name = "labelClick", .displayFn = DisplayLabelClick.displayFn, .children = null },
        .{ .name = "labelEx", .displayFn = DisplayLabelEx.displayFn, .children = null },
        .{ .name = "labelNoFmt", .displayFn = DisplayLabelEx.displayFn, .children = null },
    } },

    .{ .name = "link", .displayFn = DisplayLink.displayFn, .children = null },

    .{ .name = "menus", .displayFn = displayEmpty, .children = &.{
        .{ .name = "menu", .displayFn = DisplayMenu.displayFn, .children = null },
        .{ .name = "menuItem", .displayFn = DisplayMenuItem.displayFn, .children = null },
        .{ .name = "menuItemIcon", .displayFn = DisplayMenuItemIcon.displayFn, .children = null },
        .{ .name = "menuItemLabel", .displayFn = DisplayMenuItemLabel.displayFn, .children = null },
    } },

    .{ .name = "paned", .displayFn = DisplayPaned.displayFn, .children = null },

    .{ .name = "plots", .displayFn = displayEmpty, .children = &.{
        .{ .name = "plot", .displayFn = DisplayPlot.displayFn, .children = null },
        .{ .name = "plotXY", .displayFn = DisplayPlotXY.displayFn, .children = null },
    } },

    .{ .name = "progress", .displayFn = DisplayProgress.displayFn, .children = null },
    .{ .name = "radio", .displayFn = DisplayRadio.displayFn, .children = null },
    .{ .name = "radioGroup", .displayFn = DisplayRadioGroup.displayFn, .children = null },
    .{ .name = "reorder", .displayFn = displayEmpty, .children = null },
    .{ .name = "scale", .displayFn = DisplayScale.displayFn, .children = null },
    .{ .name = "scrollArea", .displayFn = DisplayScrollArea.displayFn, .children = null },
    .{ .name = "separator", .displayFn = DisplaySeparator.displayFn, .children = null },

    .{ .name = "sliders", .displayFn = displayEmpty, .children = &.{
        .{ .name = "slider", .displayFn = DisplaySlider.displayFn, .children = null },
        .{ .name = "sliderEntry", .displayFn = DisplaySliderEntry.displayFn, .children = null },
        .{ .name = "sliderVector", .displayFn = DisplaySliderVector.displayFn, .children = null },
    } },

    .{ .name = "spacer", .displayFn = DisplaySpacer.displayFn, .children = null },
    .{ .name = "spinner", .displayFn = DisplaySpinner.displayFn, .children = null },
    .{ .name = "suggestion", .displayFn = displayEmpty, .children = null },
    .{ .name = "tabs", .displayFn = DisplayTabs.displayFn, .children = null },
    .{ .name = "tabGroup", .displayFn = DisplayTabGroup.displayFn, .children = null },

    .{ .name = "textEntries", .displayFn = displayEmpty, .children = &.{
        .{ .name = "textEntry", .displayFn = DisplayTextEntry.displayFn, .children = null },
        .{ .name = "textEntryColor", .displayFn = DisplayTextEntryColor.displayFn, .children = null },
        .{ .name = "textEntryNumber", .displayFn = DisplayTextEntryNumber.displayFn, .children = null },
    } },

    .{ .name = "textLayout", .displayFn = displayEmpty, .children = null },
    .{ .name = "toast", .displayFn = DisplayToast.displayFn, .children = null },
    .{ .name = "tooltip", .displayFn = DisplayToolTip.displayFn, .children = null },
};

const lorem: []const []const u8 = &.{
    "It was the best of times, it was the worst of times, it was the age of wisdom, `it was the age of foolishness, it was the epoch of belief, it was the epoch of incredulity, it was the season of Light, it was the season of Darkness, it was the spring of hope, it was the winter of despair, we had everything before us, we had nothing before us, we were all going direct to Heaven, we were all going direct the other way—in short, the period was so far like the present period, that some of its noisiest authorities insisted on its being received, for good or for evil, in the superlative degree of comparison only.\n\n",
    "There were a king with a large jaw and a queen with a plain face, on the throne of England; there were a king with a large jaw and a queen with a fair face, on the throne of France. In both countries it was clearer than crystal to the lords of the State preserves of loaves and fishes, that things in general were settled for ever.\n\n",
    "It was the year of Our Lord one thousand seven hundred and seventy-five. Spiritual revelations were conceded to England at that favoured period, as at this. Mrs. Southcott had recently attained her five-and-twentieth blessed birthday, of whom a prophetic private in the Life Guards had heralded the sublime appearance by announcing that arrangements were made for the swallowing up of London and Westminster. Even the Cock-lane ghost had been laid only a round dozen of years, after rapping out its messages, as the spirits of this very year last past (supernaturally deficient in originality) rapped out theirs. Mere messages in the earthly order of events had lately come to the English Crown and People, from a congress of British subjects in America: which, strange to relate, have proved more important to the human race than any communications yet received through any of the chickens of the Cock-lane brood.\n\n",
};

const struct_ui = dvui.struct_ui;
const StructOptions = struct_ui.StructOptions;
const StructOptionsForField = struct_ui.StructOptionsForField;
const Rect = dvui.Rect;
