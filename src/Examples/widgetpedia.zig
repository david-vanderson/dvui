const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = dvui.Examples;

var reset_widget: bool = true;
const test_options_label = "Controls";

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
            .break_lines = .{ .boolean = .{ .checkbox = true } },
            .cache_layout = .{ .boolean = .{ .checkbox = true } },
            .multiline = .{ .boolean = .{ .checkbox = true } },
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
    const prev_expanded = struct_ui.defaults.display_expanded;
    struct_ui.defaults.display_expanded = true;
    defer struct_ui.defaults.display_expanded = prev_expanded;

    const width = 775;
    const height = 575;

    var float = dvui.floatingWindow(@src(), .{
        .open_flag = &Examples.show_widgetpedia_window,
    }, .{ .min_size_content = .{ .w = width, .h = 400 }, .max_size_content = .{ .w = width, .h = height } });
    defer float.deinit();
    float.dragAreaSet(dvui.windowHeader("Widgetpedia", "", &Examples.show_widgetpedia_window));

    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .background = true });
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
                            current_widget = child;
                            reset_widget = true;
                        }
                    }
                }
            }
        }
    }
    {
        var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .padding = Rect.all(6) });
        defer vbox.deinit();
        current_widget.displayFn(reset_widget);
        reset_widget = false;
    }
}

const WidgetHeirachy = struct {
    name: []const u8,
    children: ?[]const WidgetHeirachy = null,
    displayFn: *const fn (reset_widget: bool) void,
};

var current_widget: WidgetHeirachy = widget_hierarchy[0];

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

pub fn displayWidgetTemplate(widget_display: type) void {
    const default_options_editor_height = 300;
    const min_widget_display_height = 200;
    const state = struct {
        // Guess at initial split
        var split_ratio: f32 = 0.9;
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
            var hbox = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{ .expand = .both });
            defer hbox.deinit();
            {
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
                var scroll = dvui.scrollArea(@src(), .{}, .{
                    .corner_radius = Rect.all(3),
                    .border = Rect.all(1),
                    .padding = Rect.all(6),
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

    if (paned.showSecond()) {
        var outer_vbox = dvui.box(@src(), .{}, .{
            .margin = .{ .x = 0, .y = 6, .h = 0, .w = 0 },
            .expand = .horizontal,
            .border = Rect.all(1),
            .corner_radius = Rect.all(3),
            .min_size_content = .{ .h = state.paned_content_height },
        });
        defer outer_vbox.deinit();
        var expander_wd: dvui.WidgetData = undefined;
        if (dvui.expander(@src(), "Options editor", .{ .default_expanded = false }, .{ .expand = .horizontal, .data_out = &expander_wd })) {
            var scroll = dvui.scrollArea(@src(), .{}, .{
                .corner_radius = Rect.all(3),
                .padding = Rect.all(6),
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

const Easing = DeclEnumWithSkip(dvui.easing, 1);

pub fn DeclEnumWithSkip(comptime T: type, start: usize) type {
    const fieldInfos = std.meta.declarations(T);
    var enumDecls: [fieldInfos.len]std.builtin.Type.EnumField = undefined;
    var decls = [_]std.builtin.Type.Declaration{};
    inline for (fieldInfos, 0..) |field, i| {
        enumDecls[i] = .{ .name = field.name, .value = i };
    }
    return @Type(.{
        .@"enum" = .{
            .tag_type = std.math.IntFittingRange(0, if (fieldInfos.len == 0) 0 else fieldInfos.len - 1),
            .fields = enumDecls[start..],
            .decls = &decls,
            .is_exhaustive = true,
        },
    });
}

var animate_easing: ?Easing = null;

const DisplayAnimate = struct {
    const name = "animate()";
    const easing_functions: std.EnumArray(Easing, *const dvui.easing.EasingFn) = .init(.{
        .linear = dvui.easing.linear,
        .inQuad = dvui.easing.inQuad,
        .outQuad = dvui.easing.outQuad,
        .inOutQuad = dvui.easing.inOutQuad,
        .inCubic = dvui.easing.inCubic,
        .outCubic = dvui.easing.outCubic,
        .inOutCubic = dvui.easing.inOutCubic,
        .inQuart = dvui.easing.inQuart,
        .outQuart = dvui.easing.outQuart,
        .inOutQuart = dvui.easing.inOutQuart,
        .inQuint = dvui.easing.inQuint,
        .outQuint = dvui.easing.outQuint,
        .inOutQuint = dvui.easing.inOutQuint,
        .inSine = dvui.easing.inSine,
        .outSine = dvui.easing.outSine,
        .inOutSine = dvui.easing.inOutSine,
        .inExpo = dvui.easing.inExpo,
        .outExpo = dvui.easing.outExpo,
        .inOutExpo = dvui.easing.inOutExpo,
        .inCirc = dvui.easing.inCirc,
        .outCirc = dvui.easing.outCirc,
        .inOutCirc = dvui.easing.inOutCirc,
        .inElastic = dvui.easing.inElastic,
        .outElastic = dvui.easing.outElastic,
        .inOutElastic = dvui.easing.inOutElastic,
        .inBack = dvui.easing.inBack,
        .outBack = dvui.easing.outBack,
        .inOutBack = dvui.easing.inOutBack,
        .inBounce = dvui.easing.inBounce,
        .outBounce = dvui.easing.outBounce,
        .inOutBounce = dvui.easing.inOutBounce,
    });
    var init_opts: dvui.AnimateWidget.InitOptions = undefined;
    var options: dvui.Options = undefined;
    var wd: dvui.WidgetData = undefined;

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
            if (struct_ui.displayContainer(@src(), test_options_label)) |container| {
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
        if (animate_easing) |easing| {
            switch (easing) {
                inline else => |e| init_opts.easing = @field(dvui.easing, @tagName(e)),
            }
        } else {
            init_opts.easing = null;
        }
    }
};

fn selectEasing(field_name: []const u8, _: *anyopaque, read_only: bool, alignment: *dvui.Alignment) void {
    if (read_only) return;
    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.labelNoFmt(@src(), field_name, .{}, .{});

    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());
    _ = dvui.dropdownEnum(@src(), Easing, .{ .choice_nullable = &animate_easing }, .{}, .{});
}

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
        options = .{ .expand = .both, .border = Rect.all(1) };
    }

    pub fn layoutWidget() void {
        var box = dvui.box(@src(), init_opts, options.override(.{ .data_out = &wd }));
        defer box.deinit();
        for (0..test_options.nr_boxes) |i| {
            var b = dvui.box(@src(), .{}, .{
                .min_size_content = .{ .h = 30, .w = 30 },
                .border = Rect.all(1),
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
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .trigger_on = true } }, &al);
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
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .trigger_on = true } }, &al);
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label)) |container| {
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
    const name = "buttonIcon()";
    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.ButtonWidget.InitOptions = undefined;
    var icon_opts: dvui.IconRenderOptions = undefined;
    var combined_opts: dvui.ButtonLabelAndIconOptions = undefined;
    var result: bool = undefined;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
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
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .trigger_on = true } }, &al);
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(
            @src(),
            "combined_opts",
            &combined_opts,
            1,
            .{ StructOptions(dvui.ButtonLabelAndIconOptions).initWithDefaults(.{
                .label = .{ .text = .{ .display = .read_write } },
                .tvg_bytes = .{ .standard = .{ .display = .none } },
            }, null), struct_options.color },
            .{},
        );
        dvui.structUI(@src(), "icon_opts", &icon_opts, 1, .{struct_options.color}, .{});
    }
};

const DisplayCheckbox = struct {
    const name = "checkbox()";
    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.ButtonWidget.InitOptions = undefined;
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
        init_opts = .{};
        options = .{};
        test_options.checked = false;
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
        struct_ui.displayBool(@src(), "return_value", &result, .{ .boolean = .{ .display = .read_only, .trigger_on = true } }, &al);
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(
            @src(),
            test_options_label,
            &test_options,
            1,
            .{StructOptions(@TypeOf(test_options)).initWithDefaults(.{
                .label_str = .{ .text = .{ .display = .read_write } },
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
                    .return_value = .{ .boolean = .{ .trigger_on = true, .display = .read_only } },
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
            var fw2 = dvui.floatingMenu(@src(), .{ .from = Rect.Natural.fromPoint(cp) }, .{});
            defer fw2.deinit();

            if (dvui.menuItemLabel(@src(), "Menu Item 1", .{}, .{ .expand = .horizontal })) |_| {
                fw2.close();
            }
            if (dvui.menuItemLabel(@src(), "Menu Item 2", .{}, .{ .expand = .horizontal })) |_| {
                fw2.close();
            }
            if ((dvui.menuItemLabel(@src(), "Menu Item 3", .{}, .{ .expand = .horizontal }))) |_| {
                fw2.close();
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
                .return_value = .{ .boolean = .{ .trigger_on = true } },
                .choice_nullable = .default,
            }, null)}, .{});
        } else {
            dvui.structUI(@src(), null, &display_results, 3, .{StructOptions(@TypeOf(results)).init(.{
                .return_value = .{ .boolean = .{ .trigger_on = true } },
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
            .return_value = .{ .boolean = .{ .trigger_on = true } },
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

const DisplayFocusGroup = struct {
    const name = "focusGroup()";
    var wd: dvui.WidgetData = undefined;
    var init_opts: dvui.FocusGroupWidget.InitOptions = .{};
    var options: dvui.Options = undefined;
    var first_frame: bool = undefined;
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
        // TODO: Can't get this to centre.
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
    var label = undefined;
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
        dvui.structUI(@src(), null, &result, 99, .{
            StructOptions(dvui.TextEntryNumberResult(NumberType)).initWithDefaults(.{
                .changed = .{ .boolean = .{ .trigger_on = true } },
                .enter_pressed = .{ .boolean = .{ .trigger_on = true } },
            }, null),
        }, .{ .gravity_x = 1.0 });
    }

    pub fn layoutWidgetControls() void {
        dvui.structUI(@src(), "init_opts", &init_opts, 1, .{
            StructOptions(dvui.TextEntryNumberInitOptions(NumberType)).initWithDefaults(.{
                .text = .{ .text = .{ .display = .read_write } },
                .placeholder = .{ .text = .{ .display = .read_write } },
            }, init_opts_defaults),
        }, .{});
    }
};

const DisplayIcon = struct {
    const EntypoIcons = std.meta.DeclEnum(dvui.entypo);
    const name = "icon()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var icon_opts: dvui.IconRenderOptions = undefined;
    var icon_bytes: []const u8 = undefined;
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
    }

    pub fn layoutWidget() void {
        dvui.icon(@src(), "demo", icon_bytes, icon_opts, options.override(.{ .data_out = &wd }));
    }

    pub fn layoutWidgetControls() void {
        if (struct_ui.displayContainer(@src(), test_options_label)) |container| {
            defer container.deinit();
            if (dvui.dropdownEnum(@src(), EntypoIcons, .{ .choice = &choice }, .{}, .{ .expand = .horizontal })) {
                switch (choice) {
                    inline else => |ch| icon_bytes = @field(dvui.entypo, @tagName(ch)),
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
    var icon_opts: dvui.IconRenderOptions = undefined;
    var icon_bytes: []const u8 = undefined;
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

const DisplayTextEntry = struct {
    var name: []const u8 = "textEntry()";

    var wd: dvui.WidgetData = undefined;
    var options: dvui.Options = undefined;
    var init_opts: dvui.TextEntryWidget.InitOptions = undefined;

    const Configuration = enum {
        single_line,
        password,
        multiline,
        large,
        // TODO
        //        highlight,
    };
    var configuration: Configuration = undefined;
    var configuration_changed: bool = false;

    pub fn displayFn(reset: bool) void {
        if (reset) resetWidget();
        displayWidgetTemplate(@This());
    }

    pub fn resetWidget() void {
        options = .{};
        init_opts = .{};
        configuration = .single_line;
    }

    pub fn layoutWidget() void {
        if (configuration_changed) {
            switch (configuration) {
                .single_line => {
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
                    init_opts = .{ .multiline = true, .break_lines = true };
                    options = .{ .expand = .both };
                },
            }
        }
        {
            var te = dvui.textEntry(@src(), init_opts, options.override(.{ .data_out = &wd }));
            defer te.deinit();
            switch (configuration) {
                .single_line, .password => {},
                .multiline => {
                    if (configuration_changed) {
                        te.textSet("", false);
                        for (lorem) |text| {
                            te.textTyped(text, false);
                        }
                        te.textLayout.selection.moveCursor(0, false);
                    }
                },
                .large => {},
            }
        }
        configuration_changed = false;
    }

    pub fn layoutWidgetControls() void {
        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox.deinit();
            dvui.labelNoFmt(@src(), "Configuration:", .{}, .{});
            if (dvui.dropdownEnum(@src(), Configuration, .{ .choice = &configuration }, .{}, .{ .expand = .horizontal })) {
                configuration_changed = true;
            }
        }
        switch (configuration) {
            .single_line => dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_ui.StructOptions(dvui.TextEntryWidget.InitOptions).init(.{
                .placeholder = .defaultTextRW,
            }, null)}, .{}),
            .password => dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_ui.StructOptions(dvui.TextEntryWidget.InitOptions).init(.{
                .placeholder = .defaultTextRW,
                .password_char = .defaultTextRW,
            }, .{ .password_char = "*" })}, .{}),
            else => dvui.structUI(@src(), "init_opts", &init_opts, 1, .{struct_options.text_entry.init_opts}, .{}),
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
            .margin = Rect.all(6),
        });
        color_box.deinit();
    } else {
        var hsv_color: dvui.Color.HSV = .fromColor(field_value_ptr.*);
        _ = dvui.colorPicker(@src(), .{ .hsv = &hsv_color, .hex_text_entry = false, .dir = .vertical }, .{});
        field_value_ptr.* = hsv_color.toColor();
    }
}

const widget_hierarchy = [_]WidgetHeirachy{
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
    .{ .name = "flexbox", .displayFn = displayEmpty, .children = null },
    .{ .name = "floatingMenu", .displayFn = displayEmpty, .children = null },

    .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = &.{
        .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = null },
        .{ .name = "windowHeader", .displayFn = displayEmpty, .children = null },
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
        .{ .name = "labelClick", .displayFn = displayEmpty, .children = null },
        .{ .name = "labelEx", .displayFn = DisplayLabelEx.displayFn, .children = null },
        .{ .name = "labelNoFmt", .displayFn = DisplayLabelEx.displayFn, .children = null },
    } },

    .{ .name = "link", .displayFn = displayEmpty, .children = null },

    .{ .name = "menus", .displayFn = displayEmpty, .children = &.{
        .{ .name = "menu", .displayFn = displayEmpty, .children = null },
        .{ .name = "menuItem", .displayFn = displayEmpty, .children = null },
        .{ .name = "menuItemIcon", .displayFn = displayEmpty, .children = null },
        .{ .name = "menuItemLabel", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "paned", .displayFn = displayEmpty, .children = null },

    .{ .name = "plots", .displayFn = displayEmpty, .children = &.{
        .{ .name = "plot", .displayFn = displayEmpty, .children = null },
        .{ .name = "plotXY", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "progress", .displayFn = displayEmpty, .children = null },
    .{ .name = "radio", .displayFn = displayEmpty, .children = null },
    .{ .name = "radioGroup", .displayFn = displayEmpty, .children = null },
    .{ .name = "reorder", .displayFn = displayEmpty, .children = null },
    .{ .name = "scale", .displayFn = displayEmpty, .children = null },
    .{ .name = "scrollArea", .displayFn = displayEmpty, .children = null },
    .{ .name = "separator", .displayFn = displayEmpty, .children = null },

    .{ .name = "sliders", .displayFn = displayEmpty, .children = &.{
        .{ .name = "slider", .displayFn = displayEmpty, .children = null },
        .{ .name = "sliderEntry", .displayFn = displayEmpty, .children = null },
        .{ .name = "sliderVector", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "spacer", .displayFn = displayEmpty, .children = null },
    .{ .name = "spinner", .displayFn = displayEmpty, .children = null },
    .{ .name = "suggestion", .displayFn = displayEmpty, .children = null },
    .{ .name = "tabs", .displayFn = displayEmpty, .children = null },

    .{ .name = "textEntries", .displayFn = displayEmpty, .children = &.{
        .{ .name = "textEntry", .displayFn = DisplayTextEntry.displayFn, .children = null },
        .{ .name = "textEntryColor", .displayFn = displayEmpty, .children = null },
        .{ .name = "textEntryNumber", .displayFn = DisplayTextEntryNumber.displayFn, .children = null },
    } },

    .{ .name = "textLayout", .displayFn = displayEmpty, .children = null },
    .{ .name = "toast", .displayFn = displayEmpty, .children = null },
    .{ .name = "tooltip", .displayFn = displayEmpty, .children = null },
};

const lorem: []const []const u8 = &.{
    "It was the best of times, it was the worst of times, it was the age of wisdom, `it was the age of foolishness, it was the epoch of belief, it was the epoch of incredulity, it was the season of Light, it was the season of Darkness, it was the spring of hope, it was the winter of despair, we had everything before us, we had nothing before us, we were all going direct to Heaven, we were all going direct the other way—in short, the period was so far like the present period, that some of its noisiest authorities insisted on its being received, for good or for evil, in the superlative degree of comparison only.\n\n",
    "There were a king with a large jaw and a queen with a plain face, on the throne of England; there were a king with a large jaw and a queen with a fair face, on the throne of France. In both countries it was clearer than crystal to the lords of the State preserves of loaves and fishes, that things in general were settled for ever.\n\n",
    "It was the year of Our Lord one thousand seven hundred and seventy-five. Spiritual revelations were conceded to England at that favoured period, as at this. Mrs. Southcott had recently attained her five-and-twentieth blessed birthday, of whom a prophetic private in the Life Guards had heralded the sublime appearance by announcing that arrangements were made for the swallowing up of London and Westminster. Even the Cock-lane ghost had been laid only a round dozen of years, after rapping out its messages, as the spirits of this very year last past (supernaturally deficient in originality) rapped out theirs. Mere messages in the earthly order of events had lately come to the English Crown and People, from a congress of British subjects in America: which, strange to relate, have proved more important to the human race than any communications yet received through any of the chickens of the Cock-lane brood.\n\n",
};

const struct_ui = dvui.struct_ui;
const StructOptions = struct_ui.StructOptions;
const Rect = dvui.Rect;
