const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = dvui.Examples;

var reset_widget: bool = true;
const test_options_label = "Widget display options";

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
    struct_ui.defaults.display_expanded = true;

    const width = 775;

    var float = dvui.floatingWindow(@src(), .{ .open_flag = &Examples.show_widgetpedia_window }, .{ .min_size_content = .{ .w = width, .h = 400 }, .max_size_content = .width(width) });
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
        var vbox = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .padding = dvui.Rect.all(6) });
        defer vbox.deinit();
        current_widget.displayFn();
        reset_widget = false;
    }
    struct_ui.defaults.display_expanded = false;
}

const WidgetHeirachy = struct {
    name: []const u8,
    children: ?[]const WidgetHeirachy = null,
    displayFn: *const fn () void,
};

var current_widget: WidgetHeirachy = widget_hierarchy[0];

const WidgetGroupBox = struct {
    hbox: ?*dvui.BoxWidget = null,
    gbox: ?*dvui.BoxWidget = null,

    pub fn deinit(self: *WidgetGroupBox) void {
        if (self.gbox) |gbox| gbox.deinit();
        if (self.hbox) |hbox| hbox.deinit();
        self.* = undefined;
    }

    pub fn testOptionsScrollArea(self: *WidgetGroupBox, src: std.builtin.SourceLocation, opts: dvui.Options) *dvui.ScrollAreaWidget {
        if (self.gbox) |gbox| {
            gbox.deinit();
            self.gbox = null;
        }

        const defaults: dvui.Options = .{
            .corner_radius = dvui.Rect.all(3),
            .border = dvui.Rect.all(1),
            .padding = dvui.Rect.all(6),
            .expand = .both,
            .margin = .{ .x = 6, .y = 6 + opts.fontGet().lineHeight() / 2 - 1, .w = 6, .h = 6 },
            .background = false,
            .min_size_content = .{ .w = 350 },
            // TODO:
            //.max_size_content = .height(300),
        };
        return dvui.scrollArea(src, .{}, defaults.override(opts));
    }

    const WidgetTestBox = struct {
        vbox: ?*dvui.BoxWidget,
        widget_box: ?*dvui.BoxWidget,

        pub fn deinit(self: *WidgetTestBox) void {
            if (self.widget_box) |widget_box| widget_box.deinit();
            if (self.vbox) |vbox| vbox.deinit();
            self.* = undefined;
        }

        pub fn resultsBox(self: *WidgetTestBox, src: std.builtin.SourceLocation, opts: dvui.Options) *dvui.BoxWidget {
            if (self.widget_box) |widget_box| {
                widget_box.deinit();
                self.widget_box = null;
            }

            const defaults: dvui.Options = .{
                .expand = .both,
                .padding = dvui.Rect.all(6),
                .border = dvui.Rect.all(1),
                .corner_radius = dvui.Rect.all(3),
                .margin = dvui.Rect.all(6),
            };

            return dvui.box(src, .{}, defaults.override(opts));
        }
    };

    pub fn widgetTestingBox(_: WidgetGroupBox, src: std.builtin.SourceLocation, size_content_opt: ?dvui.Size, opts: dvui.Options) WidgetTestBox {
        const vbox = dvui.box(src, .{ .dir = .vertical }, .{ .expand = .horizontal });

        const size_content: dvui.Size = size_content_opt orelse .{ .w = 250, .h = 250 };
        const border_defaults: dvui.Options = if (dvui.parentGet().data().options.border == null) .{
            .border = dvui.Rect.all(1),
            .corner_radius = dvui.Rect.all(3),
        } else .{};
        const defaults: dvui.Options = .{
            .margin = dvui.Rect.all(6),
            .min_size_content = .cast(size_content),
            .expand = .horizontal,
            // TODO:
            //.max_size_content = .cast(size_content),
        };
        const widget_box = dvui.box(src, .{}, defaults.override(border_defaults.override(opts)));
        return .{
            .vbox = vbox,
            .widget_box = widget_box,
        };
    }
};

pub fn widgetGroupBox(src: std.builtin.SourceLocation, label_str: []const u8, opts: dvui.Options) WidgetGroupBox {
    const defaults: dvui.Options = .{ .expand = .both };
    const hbox = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{ .expand = .both });
    const gbox = dvui.groupBox(src, label_str, defaults.override(opts));
    return .{
        .hbox = hbox,
        .gbox = gbox,
    };
}

pub fn widgetOptionsScrollArea(src: std.builtin.SourceLocation, opts: dvui.Options) *dvui.ScrollAreaWidget {
    const defaults: dvui.Options = .{
        .corner_radius = dvui.Rect.all(3),
        .border = dvui.Rect.all(1),
        .padding = dvui.Rect.all(6),
        .expand = .both,
        .margin = dvui.Rect.all(6),
        .background = false,
        .min_size_content = .{ .h = 40 },
    };
    return dvui.scrollArea(src, .{ .horizontal = .auto }, defaults.override(opts));
}

pub fn widgetShowSetOptionsTooltip(src: std.builtin.SourceLocation, rect: dvui.Rect.Physical, opts: dvui.Options) void {
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

pub fn widgetOptionsEditor(src: std.builtin.SourceLocation, edit_opts: *dvui.Options, wd: *dvui.WidgetData, expanded: bool) void {
    var expander_wd: dvui.WidgetData = undefined;

    if (dvui.expander(@src(), "Options editor", .{ .default_expanded = expanded }, .{ .expand = .horizontal, .data_out = &expander_wd })) {
        var vbox = dvui.box(src, .{}, .{ .expand = .both });
        defer vbox.deinit();
        _ = dvui.Debug.optionsEditor(edit_opts, wd);
    }
    widgetShowSetOptionsTooltip(@src(), expander_wd.borderRectScale().r, edit_opts.*);
}

fn displayEmpty() void {
    var label_str = std.Io.Writer.Allocating.initCapacity(dvui.currentWindow().arena(), current_widget.name.len + 2) catch return;
    label_str.writer.print("{s}()", .{current_widget.name}) catch unreachable;
    var gbox = dvui.groupBox(@src(), label_str.written(), .{ .expand = .both });
    defer gbox.deinit();
    var vbox = dvui.box(@src(), .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
    defer vbox.deinit();
    dvui.icon(@src(), "under construction", dvui.entypo.hour_glass, .{}, .{ .gravity_x = 0.5, .min_size_content = .{ .h = 50, .w = 50 } });
    dvui.labelNoFmt(@src(), "Under construction", .{ .align_x = 0.5 }, .{});
}

const Easing = enum {
    linear,
    inQuad,
    outQuad,
    inOutQuad,
    inCubic,
    outCubic,
    inOutCubic,
    inQuart,
    outQuart,
    inOutQuart,
    inQuint,
    outQuint,
    inOutQuint,
    inSine,
    outSine,
    inOutSine,
    inExpo,
    outExpo,
    inOutExpo,
    inCirc,
    outCirc,
    inOutCirc,
    inElastic,
    outElastic,
    inOutElastic,
    inBack,
    outBack,
    inOutBack,
    inBounce,
    outBounce,
    inOutBounce,
};

var animate_easing: ?Easing = null;

pub fn displayAnimate() void {
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

    const state = struct {
        var init_opts: dvui.AnimateWidget.InitOptions = undefined;
        var options: dvui.Options = undefined;

        const test_options = struct {
            var restart_animation: bool = undefined;
        };
    };
    const default_init_opts: dvui.AnimateWidget.InitOptions = .{
        .duration = 5_000_000,
        .kind = .alpha,
        .easing = &dvui.easing.linear,
    };

    if (reset_widget) {
        state.init_opts = .{ .kind = .alpha, .duration = 5_000_000 };
        state.options = .{ .expand = .both, .background = true, .color_fill = .navy };
        state.test_options.restart_animation = false;
    }

    var paned = dvui.paned(@src(), .{ .direction = .vertical, .collapsed_size = 0, .autofit_first = .{ .min_size = 300 } }, .{ .expand = .both });
    defer paned.deinit();

    var wd: dvui.WidgetData = undefined;
    {
        if (paned.showFirst()) {
            var gbox = widgetGroupBox(@src(), "animate()", .{ .expand = .both });
            defer gbox.deinit();

            if (animate_easing) |easing| {
                state.init_opts.easing = easing_functions.get(easing);
            } else {
                state.init_opts.easing = null;
            }
            {
                var widget_box = gbox.widgetTestingBox(@src(), null, .{ .expand = .horizontal });
                defer widget_box.deinit();
                var animate = dvui.animate(@src(), state.init_opts, state.options);
                defer animate.deinit();
                if (state.test_options.restart_animation) {
                    animate.start();
                    state.test_options.restart_animation = false;
                }
                dvui.labelNoFmt(@src(), "Some text", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
            }
            //gbox.optionsEditor(@src(), &state.options, &wd);
            var scroll = gbox.testOptionsScrollArea(@src(), .{});
            defer scroll.deinit();
            {
                var box = dvui.box(@src(), .{}, .{ .expand = .horizontal });
                defer box.deinit();
                if (struct_ui.displayContainer(@src(), test_options_label)) |container| {
                    defer container.deinit();
                    container.data().options.expand = .horizontal;
                    if (dvui.button(@src(), "Restart animation", .{}, .{})) {
                        state.test_options.restart_animation = true;
                    }
                }
            }
            dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{
                StructOptions(dvui.AnimateWidget.InitOptions).initWithDefaults(.{
                    .easing = .{ .standard = .{ .customDisplayFn = selectEasing } },
                }, default_init_opts),
            }, .{});
        }
    }
    if (paned.showSecond()) {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

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

pub fn displayBox() void {
    const state = struct {
        var test_options: struct {
            nr_boxes: usize,
            expand: dvui.Options.Expand,
        } = undefined;
        var init_opts: dvui.BoxWidget.InitOptions = undefined;
        var options: dvui.Options = undefined;
    };

    if (reset_widget) {
        state.test_options.nr_boxes = 5;
        state.test_options.expand = .none;
        state.init_opts = .{};
        state.options = .{ .expand = .both, .border = dvui.Rect.all(1) };
    }
    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "box()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{ .expand = .horizontal });
            defer widget_box.deinit();
            var box = dvui.box(@src(), state.init_opts, state.options.override(.{ .data_out = &wd }));
            defer box.deinit();
            for (0..state.test_options.nr_boxes) |i| {
                var b = dvui.box(@src(), .{}, .{
                    .min_size_content = .{ .h = 30, .w = 30 },
                    .border = dvui.Rect.all(1),
                    .id_extra = i,
                    .expand = state.test_options.expand,
                });
                b.deinit();
            }
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), test_options_label, &state.test_options, 1, .{}, .{});
        dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{}, .{});
    }
    var scroll = widgetOptionsScrollArea(@src(), .{});
    defer scroll.deinit();
    widgetOptionsEditor(@src(), &state.options, &wd, true);
}

pub fn displayButton() void {
    const state = struct {
        var init_opts: dvui.ButtonWidget.InitOptions = undefined;
        var options: dvui.Options = undefined;

        var test_options: struct {
            label_str: []const u8,
        } = undefined;
    };

    if (reset_widget) {
        state.init_opts = .{};
        state.options = .{};
        state.test_options = .{
            .label_str = "Button",
        };
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "button()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();
            const result = dvui.button(@src(), state.test_options.label_str, state.init_opts, state.options);
            var result_box = widget_box.resultsBox(@src(), .{});
            defer result_box.deinit();
            var al = dvui.Alignment.init(@src(), 0);
            defer al.deinit();
            struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .manual_reset = true } }, &al);
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(
            @src(),
            test_options_label,
            &state.test_options,
            1,
            .{StructOptions(@TypeOf(state.test_options)).initWithDefaults(.{
                .label_str = .defaultTextRW,
            }, null)},
            .{},
        );
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayButtonIcon() void {
    const state = struct {
        var init_opts: dvui.ButtonWidget.InitOptions = undefined;
        var options: dvui.Options = undefined;
        var icon_opts: dvui.IconRenderOptions = undefined;

        var test_options: struct {
            icon: []const u8,
        } = undefined;
    };

    if (reset_widget) {
        state.init_opts = .{};
        state.icon_opts = .{};
        state.options = .{};
        state.test_options = .{
            .icon = dvui.entypo.aircraft,
        };
    }
    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "buttonIcon()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();

            const result = dvui.buttonIcon(@src(), "icon", state.test_options.icon, state.init_opts, state.icon_opts, state.options);
            var result_box = widget_box.resultsBox(@src(), .{});
            defer result_box.deinit();
            var al = dvui.Alignment.init(@src(), 0);
            defer al.deinit();
            struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .manual_reset = true } }, &al);
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(
            @src(),
            test_options_label,
            &state.test_options,
            1,
            .{StructOptions(@TypeOf(state.test_options)).initWithDefaults(.{
                .icon = .{ .standard = .{ .display = .none } },
            }, null)},
            .{},
        );
        dvui.structUI(@src(), "icon_opts", &state.icon_opts, 1, .{struct_options.color}, .{});
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayButtonLabelAndIcon() void {
    const state = struct {
        var options: dvui.Options = undefined;
        var icon_opts: dvui.IconRenderOptions = undefined;
        var combined_opts: dvui.ButtonLabelAndIconOptions = undefined;
    };

    if (reset_widget) {
        state.options = .{};
        state.combined_opts = .{
            .label = "Button",
            .tvg_bytes = dvui.entypo.aircraft,
            .button_opts = .{},
        };
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "buttonLabelAndIcon()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();
            const result = dvui.buttonLabelAndIcon(@src(), state.combined_opts, state.options);
            var result_box = widget_box.resultsBox(@src(), .{});
            defer result_box.deinit();
            var al = dvui.Alignment.init(@src(), 0);
            defer al.deinit();
            struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .manual_reset = true } }, &al);
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(
            @src(),
            "combined_opts",
            &state.combined_opts,
            1,
            .{ StructOptions(dvui.ButtonLabelAndIconOptions).initWithDefaults(.{
                .label = .{ .text = .{ .display = .read_write } },
                .tvg_bytes = .{ .standard = .{ .display = .none } },
            }, null), struct_options.color },
            .{},
        );
        dvui.structUI(@src(), "icon_opts", &state.icon_opts, 1, .{struct_options.color}, .{});
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayCheckbox() void {
    const state = struct {
        var init_opts: dvui.ButtonWidget.InitOptions = undefined;
        var options: dvui.Options = undefined;
        var test_options: struct {
            checked: bool,
            label_str: []const u8,
        } = undefined;
    };

    if (reset_widget) {
        state.init_opts = .{};
        state.options = .{};
        state.test_options.checked = false;
        state.test_options = .{
            .label_str = "checkbox label",
            .checked = false,
        };
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "checkbox()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();

            const result = dvui.checkbox(@src(), &state.test_options.checked, state.test_options.label_str, .{});
            var result_box = widget_box.resultsBox(@src(), .{});
            defer result_box.deinit();
            var al = dvui.Alignment.init(@src(), 0);
            defer al.deinit();
            struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .manual_reset = true } }, &al);
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(
            @src(),
            test_options_label,
            &state.test_options,
            1,
            .{StructOptions(@TypeOf(state.test_options)).initWithDefaults(.{
                .label_str = .{ .text = .{ .display = .read_write } },
            }, null)},
            .{},
        );
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayColorPicker() void {
    const state = struct {
        var init_opts: dvui.ColorPickerInitOptions = undefined;
        var options: dvui.Options = undefined;
        var hsv: dvui.Color.HSV = undefined;

        var result: struct {
            return_value: bool,
            color: dvui.Color,
        } = undefined;
    };

    if (reset_widget) {
        state.init_opts = .{ .hsv = &state.hsv };
        state.options = .{};
        state.hsv = .fromColor(.white);
        state.result = .{
            .return_value = false,
            .color = .white,
        };
    }
    var paned = dvui.paned(@src(), .{ .direction = .vertical, .collapsed_size = 0, .autofit_first = .{ .min_size = 300 } }, .{ .expand = .both });
    defer paned.deinit();

    var wd: dvui.WidgetData = undefined;
    if (paned.showFirst()) {
        var gbox = widgetGroupBox(@src(), "colorPicker()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();
            if (dvui.colorPicker(@src(), state.init_opts, state.options)) {
                state.result.return_value = true;
                state.result.color = state.init_opts.hsv.toColor();
            } else {
                state.result.return_value = false;
            }
            var result_box = widget_box.resultsBox(@src(), .{});
            defer result_box.deinit();
            dvui.structUI(
                @src(),
                "results",
                &state.result,
                1,
                .{
                    StructOptions(@TypeOf(state.result)).init(.{
                        .return_value = .{ .boolean = .{ .manual_reset = true, .display = .read_only } },
                        .color = .{ .standard = .{ .display = .read_only, .customDisplayFn = structColorPicker } },
                    }, null),
                },
                .{},
            );
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        if (state.init_opts.alpha) {
            dvui.structUI(@src(), "init_opts", &state.init_opts, 2, .{struct_options.color_hsva}, .{});
        } else {
            dvui.structUI(@src(), "init_opts", &state.init_opts, 2, .{struct_options.color_hsv}, .{});
        }
    }
    if (paned.showSecond()) {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayCombobox() void {
    const state = struct {
        var init_opts: dvui.TextEntryWidget.InitOptions = undefined;
        var options: dvui.Options = undefined;
        var test_options: struct {
            choice: usize,
            entries: []const []const u8,
        } = undefined;
    };

    if (reset_widget) {
        state.init_opts = .{};
        state.options = .{};
        state.test_options = .{
            .choice = 0,
            .entries = &.{ "one", "two", "three", "four", "five" },
        };
    }

    var paned = dvui.paned(@src(), .{ .direction = .vertical, .collapsed_size = 400, .autofit_first = .{ .min_size = 300 }, .uncollapse_ratio = 0.8 }, .{ .expand = .both });
    defer paned.deinit();

    // TODO: If not showfirst then this will be undefined. So need to sort that.
    var wd: dvui.WidgetData = undefined;
    if (paned.showFirst()) {
        var gbox = widgetGroupBox(@src(), "comboBox()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();
            var combo = dvui.comboBox(@src(), state.init_opts, state.options);
            defer combo.deinit();
            if (combo.entries(state.test_options.entries)) |index| {
                state.test_options.choice = index;
            }
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(
            @src(),
            test_options_label,
            &state.test_options,
            1,
            .{},
            .{},
        );
        dvui.structUI(@src(), "init_opts", &state.init_opts, 2, .{struct_options.text_entry.init_opts}, .{});
    }
    if (paned.showSecond()) {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        // TODO: Try and get collapsed working.
        //        if (paned.collapsed()) {
        //            dvui.label(@src(), "Right Side", .{}, .{});
        //            widgetOptionsEditor(@src(), &state.options, &wd, false);
        //            paned.animateSplit(1.0);
        //        } else {
        //            widgetOptionsEditor(@src(), &state.options, &wd, true);
        //        }
        widgetOptionsEditor(@src(), &state.options, &wd, true);
        if (paned.collapsed()) {
            std.debug.print("here!\n", .{});
            paned.animateSplit(0.8);
        }
    }
}

pub fn displayContext() void {
    const state = struct {
        var init_opts: dvui.ContextWidget.InitOptions = undefined;
        var options: dvui.Options = undefined;
    };

    if (reset_widget) {
        state.options = .{};
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "context()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();

            var label_wd: dvui.WidgetData = undefined;
            dvui.labelNoFmt(@src(), "Right click me...", .{}, .{ .data_out = &label_wd });

            const ctext = dvui.context(@src(), .{ .rect = label_wd.borderRectScale().r }, .{ .data_out = &wd });
            defer ctext.deinit();

            if (ctext.activePoint()) |cp| {
                var fw2 = dvui.floatingMenu(@src(), .{ .from = dvui.Rect.Natural.fromPoint(cp) }, .{});
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
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayDropdown() void {
    const state = struct {
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
    };

    if (reset_widget) {
        state.options = .{ .gravity_y = 0.5 };
        state.init_opts = .{};
        state.test_options.nullable = false;
        state.expand_maybe = null;
        state.results = .{
            .return_value = false,
            .choice_nullable = null,
            .choice = 0,
        };
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "dropDownEnum()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();

            const entries = [_][]const u8{ "First", "Second", "Third is a really long one that doesn't fit" };

            state.results.return_value = dvui.dropdown(
                @src(),
                &entries,
                if (state.test_options.nullable) .{ .choice_nullable = &state.results.choice_nullable } else .{ .choice = &state.results.choice },
                state.init_opts,
                state.options.override(.{ .data_out = &wd }),
            );

            var results_box = widget_box.resultsBox(@src(), .{});
            defer results_box.deinit();
            // const to force read-only display.
            const display_results = state.results;
            if (state.test_options.nullable) {
                dvui.structUI(@src(), "results", &display_results, 3, .{StructOptions(@TypeOf(state.results)).init(.{
                    .return_value = .{ .boolean = .{ .manual_reset = true } },
                    .choice_nullable = .default,
                }, null)}, .{});
            } else {
                dvui.structUI(@src(), "results", &display_results, 3, .{StructOptions(@TypeOf(state.results)).init(.{
                    .return_value = .{ .boolean = .{ .manual_reset = true } },
                    .choice = .default,
                }, null)}, .{});
            }
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), test_options_label, &state.test_options, 1, .{}, .{});
        dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{StructOptions(dvui.DropdownInitOptions).initWithDefaults(.{
            .placeholder = .defaultText,
        }, state.default_init_opts)}, .{});
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayDropDownEnum() void {
    const state = struct {
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
    };

    if (reset_widget) {
        state.options = .{ .gravity_y = 0.5 };
        state.init_opts = .{};
        state.test_options.nullable = false;
        state.expand = .none;
        state.expand_maybe = null;
        state.results = .{
            .return_value = false,
            .choice = .{ .choice = &state.expand },
        };
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "dropDownEnum()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();

            state.results.return_value = dvui.dropdownEnum(@src(), dvui.Options.Expand, state.results.choice, state.init_opts, state.options.override(.{ .data_out = &wd }));
            var results_box = widget_box.resultsBox(@src(), .{});
            defer results_box.deinit();
            // const to force read-only display.
            const display_results = state.results;
            dvui.structUI(@src(), "results", &display_results, 3, .{StructOptions(@TypeOf(state.results)).init(.{
                .return_value = .{ .boolean = .{ .manual_reset = true } },
                .choice = .default,
            }, null)}, .{});
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), test_options_label, &state.test_options, 1, .{}, .{});
        if (state.test_options.nullable) {
            if (state.results.choice != .choice_nullable) {
                state.results.choice = .{ .choice_nullable = &state.expand_maybe };
            }
        } else if (state.results.choice != .choice) {
            state.results.choice = .{ .choice = &state.expand };
        }

        dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{StructOptions(dvui.DropdownInitOptions).initWithDefaults(.{
            .placeholder = .defaultText,
        }, state.default_init_opts)}, .{});
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayExpander() void {
    const state = struct {
        var init_opts: dvui.ExpanderOptions = .{};
        var options: dvui.Options = undefined;
        var test_options: struct {
            label: []const u8,
        } = undefined;
    };

    if (reset_widget) {
        state.init_opts = .{};
        state.options = .{};
        state.test_options = .{ .label = "Expander" };
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "expander()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();
            const result = dvui.expander(@src(), state.test_options.label, state.init_opts, state.options.override(.{ .data_out = &wd }));
            if (result) {
                dvui.labelNoFmt(@src(), "Widget 1 ", .{}, .{});
                dvui.labelNoFmt(@src(), "Widget 2 ", .{}, .{});
                dvui.labelNoFmt(@src(), "Widget 3 ", .{}, .{});
            }
            var result_box = widget_box.resultsBox(@src(), .{});

            defer result_box.deinit();
            var al = dvui.Alignment.init(@src(), 0);
            defer al.deinit();
            struct_ui.displayBool(@src(), "result", &result, .{ .boolean = .{ .display = .read_only } }, &al);
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), test_options_label, &state.test_options, 2, .{
            StructOptions(@TypeOf(state.test_options)).initWithDefaults(.{
                .label = .defaultTextRW,
            }, null),
        }, .{});
        dvui.structUI(@src(), "init_opts", &state.init_opts, 2, .{}, .{});
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayFocusGroup() void {
    const state = struct {
        var init_opts: dvui.FocusGroupWidget.InitOptions = .{};
        var options: dvui.Options = undefined;
        var test_options: struct {
            label: []const u8,
        } = undefined;
    };

    if (reset_widget) {
        state.init_opts = .{};
        state.options = .{};
        state.test_options = .{ .label = "Expander" };
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "focusGroup()", .{ .border = dvui.Rect.all(0) });
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();
            var fg = dvui.focusGroup(@src(), state.init_opts, state.options.override(.{ .data_out = &wd }));
            defer fg.deinit();
            var button_wd: dvui.WidgetData = undefined;
            _ = dvui.button(@src(), "Button 1", .{}, .{ .data_out = &button_wd });
            if (dvui.firstFrame(button_wd.id)) {
                dvui.focusWidget(button_wd.id, null, null);
            }
            _ = dvui.button(@src(), "Button 2", .{}, .{});
            _ = dvui.button(@src(), "Button 3", .{}, .{});
            _ = dvui.spacer(@src(), .{ .margin = .{ .y = 6, .x = 0, .w = 0, .h = 0 } });
            var tl = dvui.textLayout(@src(), .{ .break_lines = true }, .{});
            tl.addText("Widgets in a focus group are navigated using arrow keys.", .{});
            tl.deinit();
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), "init_opts", &state.init_opts, 2, .{}, .{});
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayGroupBox() void {
    const label_short = "Shipping:";
    const label_long = "This is a really long label that will get truncated if it is long enough to span the width of the groupbox.";
    const state = struct {
        var options: dvui.Options = undefined;
        var label = undefined;
        var test_options: struct {
            long_label: bool,
            big_font: bool,
            background: bool,
        } = undefined;
    };

    if (reset_widget) {
        state.options = .{ .expand = .both };
        state.test_options = .{
            .background = false,
            .big_font = false,
            .long_label = false,
        };
    }

    if (state.test_options.big_font) {
        state.options.font = state.options.fontGet().withSize(18);
    } else {
        state.options.font = null;
    }
    if (state.test_options.background) {
        state.options.background = true;
        if (state.options.color_fill == null) {
            state.options.color_fill = .red;
        }
    } else {
        state.options.background = false;
    }
    var wd: dvui.WidgetData = undefined;

    {
        var gbox = widgetGroupBox(@src(), "groupBox()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{ .expand = .horizontal, .border = dvui.Rect.all(0) });
            defer widget_box.deinit();

            var test_gbox = dvui.groupBox(@src(), if (state.test_options.long_label) label_long else label_short, state.options.override(.{ .data_out = &wd }));
            defer test_gbox.deinit();
            dvui.labelNoFmt(@src(), "Name:", .{}, .{});
            var te = dvui.textEntry(@src(), .{}, .{});
            te.deinit();
            dvui.labelNoFmt(@src(), "Address:", .{}, .{});
            te = dvui.textEntry(@src(), .{}, .{});
            te.deinit();
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), test_options_label, &state.test_options, 1, .{}, .{});
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        widgetOptionsEditor(@src(), &state.options, &wd, true);
    }
}

pub fn displayTextEntryNumber() void {
    const NumberType = i64;

    const state = struct {
        var init_opts: dvui.TextEntryNumberInitOptions(NumberType) = undefined;
        var options: dvui.Options = undefined;
        var value: NumberType = undefined;
    };
    const init_opts_defaults: dvui.TextEntryNumberInitOptions(NumberType) = .{ .value = &state.value, .placeholder = "Enter a number", .text = "", .min = -100, .max = 100 };

    if (reset_widget) {
        state.init_opts = .{};
        state.options = .{ .gravity_y = 0.5 };
        state.value = -789;
    }

    var wd: dvui.WidgetData = undefined;
    {
        var gbox = widgetGroupBox(@src(), "textEntryNumber()", .{});
        defer gbox.deinit();
        {
            var widget_box = gbox.widgetTestingBox(@src(), null, .{});
            defer widget_box.deinit();
            const result = dvui.textEntryNumber(@src(), NumberType, state.init_opts, state.options.override(.{ .data_out = &wd }));
            var results_box = widget_box.resultsBox(@src(), .{});
            defer results_box.deinit();
            dvui.structUI(@src(), "result", &result, 99, .{
                StructOptions(dvui.TextEntryNumberResult(NumberType)).initWithDefaults(.{
                    .changed = .{ .boolean = .{ .manual_reset = true } },
                    .enter_pressed = .{ .boolean = .{ .manual_reset = true } },
                }, null),
            }, .{ .gravity_x = 1.0 });
        }
        var scroll = gbox.testOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{
            StructOptions(dvui.TextEntryNumberInitOptions(NumberType)).initWithDefaults(.{
                .text = .{ .text = .{ .display = .read_write } },
                .placeholder = .{ .text = .{ .display = .read_write } },
            }, init_opts_defaults),
        }, .{});
    }
    var scroll = widgetOptionsScrollArea(@src(), .{});
    defer scroll.deinit();
    widgetOptionsEditor(@src(), &state.options, &wd, true);
}

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
            .margin = dvui.Rect.all(6),
        });
        color_box.deinit();
    } else {
        var hsv_color: dvui.Color.HSV = .fromColor(field_value_ptr.*);
        _ = dvui.colorPicker(@src(), .{ .hsv = &hsv_color, .hex_text_entry = false, .dir = .vertical }, .{});
        field_value_ptr.* = hsv_color.toColor();
    }
}

const widget_hierarchy = [_]WidgetHeirachy{
    .{ .name = "animate", .displayFn = displayAnimate, .children = null },
    .{ .name = "box", .displayFn = displayBox, .children = null },

    .{ .name = "buttons", .displayFn = displayEmpty, .children = &.{
        .{ .name = "button", .displayFn = displayButton, .children = null },
        .{ .name = "buttonIcon", .displayFn = displayButtonIcon, .children = null },
        .{ .name = "buttonLabelAndIcon", .displayFn = displayButtonLabelAndIcon, .children = null },
    } },

    .{ .name = "checkbox", .displayFn = displayCheckbox, .children = null },
    .{ .name = "colorPicker", .displayFn = displayColorPicker, .children = null },
    .{ .name = "comboBox", .displayFn = displayCombobox, .children = null },
    .{ .name = "context", .displayFn = displayContext, .children = null },
    .{ .name = "dialog", .displayFn = displayEmpty, .children = null },
    .{ .name = "dropdowns", .displayFn = displayEmpty, .children = &.{
        .{ .name = "dropdown", .displayFn = displayDropdown, .children = null },
        .{ .name = "dropdownEnum", .displayFn = displayDropDownEnum, .children = null },
    } },
    .{ .name = "expander", .displayFn = displayExpander, .children = null },
    .{ .name = "flexbox", .displayFn = displayEmpty, .children = null },
    .{ .name = "floatingMenu", .displayFn = displayEmpty, .children = null },

    .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = &.{
        .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = null },
        .{ .name = "windowHeader", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "focusGroup", .displayFn = displayFocusGroup, .children = null },

    .{ .name = "grid", .displayFn = displayEmpty, .children = &.{
        .{ .name = "grid", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeading", .displayFn = displayEmpty, .children = null },
        .{ .name = "columnLayoutProportional", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingCheckbox", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingSeparator", .displayFn = displayEmpty, .children = null },
        .{ .name = "gridHeadingSortable", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "groupBox", .displayFn = displayGroupBox, .children = null },
    .{ .name = "icon", .displayFn = displayEmpty, .children = null },
    .{ .name = "image", .displayFn = displayEmpty, .children = null },

    .{ .name = "labels", .displayFn = displayEmpty, .children = &.{
        .{ .name = "label", .displayFn = displayEmpty, .children = null },
        .{ .name = "labelClick", .displayFn = displayEmpty, .children = null },
        .{ .name = "labelEx", .displayFn = displayEmpty, .children = null },
        .{ .name = "labelNoFmt", .displayFn = displayEmpty, .children = null },
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
        .{ .name = "textEntry", .displayFn = displayEmpty, .children = null },
        .{ .name = "textEntryColor", .displayFn = displayEmpty, .children = null },
        .{ .name = "textEntryNumber", .displayFn = displayTextEntryNumber, .children = null },
    } },

    .{ .name = "textLayout", .displayFn = displayEmpty, .children = null },
    .{ .name = "toast", .displayFn = displayEmpty, .children = null },
    .{ .name = "tooltip", .displayFn = displayEmpty, .children = null },
};

const struct_ui = dvui.struct_ui;
const StructOptions = struct_ui.StructOptions;
