const std = @import("std");
const dvui = @import("../dvui.zig");
const Examples = dvui.Examples;

var reset_widget: bool = false;

pub fn widgetpedia() void {
    if (!Examples.show_widgetpedia_window) {
        return;
    }
    dvui.struct_ui.defaults.display_expanded = true;

    const width = 750;

    var float = dvui.floatingWindow(@src(), .{ .open_flag = &Examples.show_widgetpedia_window }, .{ .min_size_content = .{ .w = width, .h = 400 }, .max_size_content = .width(width) });
    defer float.deinit();
    float.dragAreaSet(dvui.windowHeader("Widgetpedia", "", &Examples.show_widgetpedia_window));

    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .background = true });
    defer hbox.deinit();
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .vertical });
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

            if (branch.expander(@src(), .{ .indent = 30 }, .{ .expand = .horizontal })) {
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
    dvui.struct_ui.defaults.display_expanded = false;
}

const WidgetHeirachy = struct {
    name: []const u8,
    children: ?[]const WidgetHeirachy = null,
    displayFn: *const fn () void,
};

var current_widget: WidgetHeirachy = widget_hierarchy[0];
//var currentDisplayFn: *const fn () void = displayDropDownEnum;

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

    const defaults = struct {
        const init_opts: dvui.AnimateWidget.InitOptions = .{ .kind = .alpha, .duration = 5_000_000 };
        const options: dvui.Options = .{ .expand = .both, .background = true, .color_fill = .navy };
    };
    const state = struct {
        var init_opts: dvui.AnimateWidget.InitOptions = defaults.init_opts;
        var options: dvui.Options = defaults.options;

        const test_options = struct {
            var restart_animation: bool = false;
        };
    };
    const default_init_opts: dvui.AnimateWidget.InitOptions = .{
        .duration = defaults.init_opts.duration,
        .kind = defaults.init_opts.kind,
        .easing = &dvui.easing.linear,
    };

    if (reset_widget) {
        state.init_opts = defaults.init_opts;
        state.options = defaults.options;
    }
    const size_content: dvui.Size = .{ .w = 250, .h = 250 };
    var gbox = dvui.groupBox(@src(), "animate()", .{ .expand = .both });
    defer gbox.deinit();
    var wd: dvui.WidgetData = undefined;
    {
        if (animate_easing) |easing| {
            state.init_opts.easing = easing_functions.get(easing);
        } else {
            state.init_opts.easing = null;
        }

        var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .min_size_content = .cast(size_content),
            .max_size_content = .cast(size_content),
            .border = dvui.Rect.all(1),
            .corner_radius = dvui.Rect.all(3),
        });
        defer outer_hbox.deinit();
        var animate = dvui.animate(@src(), state.init_opts, state.options);
        defer animate.deinit();
        if (state.test_options.restart_animation) {
            animate.start();
            state.test_options.restart_animation = false;
        }
        dvui.labelNoFmt(@src(), "Some text", .{}, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{});
    defer scroll.deinit();
    {
        var box = dvui.box(@src(), .{}, .{ .expand = .horizontal });
        defer box.deinit();
        if (dvui.struct_ui.displayContainer(@src(), "test_options")) |container| {
            defer container.deinit();
            if (dvui.button(@src(), "Restart animation", .{}, .{})) {
                state.test_options.restart_animation = true;
            }
        }
    }
    dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{
        dvui.struct_ui.StructOptions(dvui.AnimateWidget.InitOptions).initWithDefaults(.{
            .easing = .{ .standard = .{ .customDisplayFn = selectEasing } },
        }, default_init_opts),
    }, .{});
    if (dvui.expander(@src(), "Options editor", .{}, .{ .expand = .horizontal })) {
        _ = dvui.Debug.optionsEditor(&state.options, &wd);
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
    const defaults = struct {
        const nr_boxes = 5;
        const expand: dvui.Options.Expand = .none;
        const init_opts: dvui.BoxWidget.InitOptions = .{};
        const options: dvui.Options = .{ .expand = .both };
    };
    const state = struct {
        var test_options: struct {
            nr_boxes: usize = defaults.nr_boxes,
            expand: dvui.Options.Expand = defaults.expand,
        } = .{};
        var init_opts: dvui.BoxWidget.InitOptions = defaults.init_opts;
        var options: dvui.Options = defaults.options;
    };

    if (reset_widget) {
        state.test_options.nr_boxes = defaults.nr_boxes;
        state.test_options.expand = defaults.expand;
        state.init_opts = defaults.init_opts;
        state.options = defaults.options;
    }
    const size_content: dvui.Size = .{ .w = 250, .h = 250 };
    var gbox = dvui.groupBox(@src(), "box()", .{ .expand = .both });
    defer gbox.deinit();
    var wd: dvui.WidgetData = undefined;
    {
        var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .min_size_content = .cast(size_content),
            .max_size_content = .cast(size_content),
            .border = dvui.Rect.all(1),
            .corner_radius = dvui.Rect.all(3),
        });
        defer outer_hbox.deinit();
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
    var scroll = dvui.scrollArea(@src(), .{}, .{});
    defer scroll.deinit();
    dvui.structUI(@src(), "test options", &state.test_options, 1, .{}, .{});
    dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{}, .{});
    if (dvui.expander(@src(), "Options editor", .{}, .{ .expand = .horizontal })) {
        _ = dvui.Debug.optionsEditor(&state.options, &wd);
    }
}

pub fn widgetGroupBox(src: std.builtin.SourceLocation, label_str: []const u8, opts: dvui.Options) *dvui.BoxWidget {
    const defaults: dvui.Options = .{ .expand = .horizontal };
    return dvui.groupBox(src, label_str, defaults.override(opts));
}

pub fn widgetTestingBox(src: std.builtin.SourceLocation, size_content_opt: ?dvui.Size, opts: dvui.Options) *dvui.BoxWidget {
    const size_content: dvui.Size = size_content_opt orelse .{ .w = 250, .h = 250 };
    const border_defaults: dvui.Options = if (dvui.parentGet().data().options.border == null) .{
        .border = dvui.Rect.all(1),
        .corner_radius = dvui.Rect.all(3),
    } else .{};
    const defaults: dvui.Options = .{
        .margin = dvui.Rect.all(6),
        .min_size_content = .cast(size_content),
        .max_size_content = .cast(size_content),
    };
    return dvui.box(src, .{}, defaults.override(border_defaults.override(opts)));
}

pub fn widgetTextingBoxWithResults(src: std.builtin.SourceLocation, opts: dvui.Options) *dvui.BoxWidget {
    const defaults: dvui.Options = .{ .expand = .horizontal };
    return dvui.box(src, .{ .dir = .horizontal }, defaults.override(opts));
}

pub fn widgetResultsBox(src: std.builtin.SourceLocation, opts: dvui.Options) *dvui.BoxWidget {
    const defaults: dvui.Options = .{
        .expand = .both,
        .padding = dvui.Rect.all(6),
    };
    return dvui.box(src, .{}, defaults.override(opts));
}

pub fn widgetOptionsScrollArea(src: std.builtin.SourceLocation, opts: dvui.Options) *dvui.ScrollAreaWidget {
    const defaults: dvui.Options = .{
        .corner_radius = dvui.Rect.all(3),
        .border = dvui.Rect.all(1),
        .padding = dvui.Rect.all(6),
        .expand = .both,
        .margin = dvui.Rect.all(6),
        .background = false,
    };
    return dvui.scrollArea(src, .{}, defaults.override(opts));
}

pub fn widgetOptionsEditor(src: std.builtin.SourceLocation, edit_opts: *dvui.Options, wd: *dvui.WidgetData) void {
    if (dvui.expander(src, "Options editor", .{}, .{ .expand = .horizontal })) {
        _ = dvui.Debug.optionsEditor(edit_opts, wd);
    }
}

pub fn displayDropDownEnum() void {
    const defaults = struct {
        const init_opts: dvui.DropdownInitOptions = .{};
        const options: dvui.Options = .{ .gravity_y = 0.5 };
        const nullable = false;
    };
    const state = struct {
        var init_opts: dvui.DropdownInitOptions = defaults.init_opts;
        var options: dvui.Options = defaults.options;
        var results: struct {
            return_value: bool = false,
            choice: dvui.DropdownChoice(dvui.Options.Expand) = .{ .choice = &expand },
        } = .{};
        // Enum values to display
        var expand: dvui.Options.Expand = .none;
        var expand_maybe: ?dvui.Options.Expand = null;

        // Defaults for when fields are set to non-null
        const default_init_opts: dvui.DropdownInitOptions = .{
            .null_selectable = false,
            .placeholder = "Select something",
        };

        var test_options: struct {
            nullable: bool = defaults.nullable,
        } = .{};
    };

    if (reset_widget) {
        state.options = defaults.options;
        state.init_opts = defaults.init_opts;
        state.test_options.nullable = defaults.nullable;
    }

    var wd: dvui.WidgetData = undefined;

    {
        var gbox = widgetGroupBox(@src(), "dropDownEnum()", .{});
        defer gbox.deinit();
        var outer_box = widgetTextingBoxWithResults(@src(), .{});
        defer outer_box.deinit();

        var widget_box = widgetTestingBox(@src(), null, .{});
        state.results.return_value = dvui.dropdownEnum(@src(), dvui.Options.Expand, state.results.choice, state.init_opts, state.options.override(.{ .data_out = &wd }));
        widget_box.deinit();
        var results_box = widgetResultsBox(@src(), .{});
        defer results_box.deinit();
        // Display a read-only version of results.
        const display_results = state.results;
        dvui.structUI(@src(), "results", &display_results, 3, .{dvui.struct_ui.StructOptions(@TypeOf(state.results)).init(.{
            .return_value = .{ .boolean = .{ .manual_reset = true } },
            .choice = .default,
        }, null)}, .{ .gravity_x = 1.0, .border = dvui.Rect.all(1), .corner_radius = dvui.Rect.all(3), .expand = .both, .margin = .{ .x = 6 } });
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), "Widget Display Options", &state.test_options, 1, .{}, .{});
        if (state.test_options.nullable) {
            if (state.results.choice != .choice_nullable) {
                state.results.choice = .{ .choice_nullable = &state.expand_maybe };
            }
        } else if (state.results.choice != .choice) {
            state.results.choice = .{ .choice = &state.expand };
        }

        dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{dvui.struct_ui.StructOptions(dvui.DropdownInitOptions).initWithDefaults(.{
            .placeholder = .defaultText,
        }, state.default_init_opts)}, .{});

        widgetOptionsEditor(@src(), &state.options, &wd);
    }
}

pub fn displayGroupBox() void {
    const defaults = struct {
        const options: dvui.Options = .{ .expand = .both };
        const label_short = "Shipping:";
        const label_long = "This is a really long label that will get truncated if it is long enough to span the width of the groupbox.";
    };
    const state = struct {
        var options: dvui.Options = defaults.options;
        var label = defaults.label_short;
        var test_options: struct {
            long_label: bool = false,
            big_font: bool = false,
            background: bool = false,
        } = .{};
    };

    if (reset_widget) {
        state.options = defaults.options;
        state.test_options.long_label = false;
        state.test_options.big_font = false;
        state.test_options.background = false;
    }

    if (state.test_options.big_font) {
        state.options.font = state.options.fontGet().withSize(18);
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
        var widget_box = widgetGroupBox(@src(), "groupBox()", .{});
        defer widget_box.deinit();
        {
            var test_box = widgetTestingBox(@src(), null, .{ .expand = .horizontal });
            defer test_box.deinit();

            var gbox = dvui.groupBox(@src(), if (state.test_options.long_label) defaults.label_long else defaults.label_short, state.options.override(.{ .data_out = &wd }));
            defer gbox.deinit();
            dvui.labelNoFmt(@src(), "Name:", .{}, .{});
            var te = dvui.textEntry(@src(), .{}, .{});
            te.deinit();
            dvui.labelNoFmt(@src(), "Address:", .{}, .{});
            te = dvui.textEntry(@src(), .{}, .{});
            te.deinit();
        }
    }
    {
        var scroll = widgetOptionsScrollArea(@src(), .{});
        defer scroll.deinit();
        dvui.structUI(@src(), "Widget Display Options", &state.test_options, 1, .{}, .{});
        widgetOptionsEditor(@src(), &state.options, &wd);
    }
}

pub fn displayTextEntryNumber() void {
    const NumberType = i64;

    const state = struct {
        var init_opts: dvui.TextEntryNumberInitOptions(NumberType) = .{};
        var options: dvui.Options = .{ .gravity_y = 0.5 };
        var value: NumberType = -789;
    };
    const init_opts_defaults: dvui.TextEntryNumberInitOptions(NumberType) = .{ .value = &state.value, .placeholder = "Enter a number", .text = "", .min = -100, .max = 100 };

    const size_content: dvui.Size = .{ .w = 250, .h = 250 };
    var gbox = dvui.groupBox(@src(), "textEntryNumber()", .{ .expand = .both });
    defer gbox.deinit();
    var text_entry_wd: dvui.WidgetData = undefined;
    {
        var outer_hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .margin = dvui.Rect.all(6),
            .border = dvui.Rect.all(1),
            .color_border = .red,
        });
        defer outer_hbox.deinit();
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .min_size_content = .cast(size_content), .max_size_content = .cast(size_content), .border = dvui.Rect.all(1), .color_border = .blue });
        const result = dvui.textEntryNumber(@src(), NumberType, state.init_opts, state.options.override(.{ .data_out = &text_entry_wd }));
        hbox.deinit();
        dvui.structUI(@src(), "result", &result, 99, .{
            dvui.struct_ui.StructOptions(dvui.TextEntryNumberResult(NumberType)).initWithDefaults(.{
                .changed = .{ .boolean = .{ .manual_reset = true } },
                .enter_pressed = .{ .boolean = .{ .manual_reset = true } },
            }, null),
        }, .{ .gravity_x = 1.0 });
    }
    var scroll = dvui.scrollArea(@src(), .{}, .{ .corner_radius = dvui.Rect.all(3), .border = dvui.Rect.all(1), .padding = dvui.Rect.all(6), .expand = .horizontal, .margin = dvui.Rect.all(6), .background = false });
    defer scroll.deinit();
    dvui.structUI(@src(), "init_opts", &state.init_opts, 1, .{
        dvui.struct_ui.StructOptions(dvui.TextEntryNumberInitOptions(NumberType)).initWithDefaults(.{
            .text = .{ .text = .{ .display = .read_write } },
            .placeholder = .{ .text = .{ .display = .read_write } },
        }, init_opts_defaults),
    }, .{});
    if (dvui.expander(@src(), "Options editor", .{}, .{ .expand = .horizontal })) {
        _ = dvui.Debug.optionsEditor(&state.options, &text_entry_wd);
    }
}

const widget_hierarchy = [_]WidgetHeirachy{
    .{ .name = "animate", .displayFn = displayAnimate, .children = null },
    .{ .name = "box", .displayFn = displayBox, .children = null },

    .{ .name = "buttons", .displayFn = displayEmpty, .children = &.{
        .{ .name = "button", .displayFn = displayEmpty, .children = null },
        .{ .name = "buttonIcon", .displayFn = displayEmpty, .children = null },
        .{ .name = "buttonLabelAndIcon", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "checkbox", .displayFn = displayEmpty, .children = null },
    .{ .name = "colorPicker", .displayFn = displayEmpty, .children = null },
    .{ .name = "comboBox", .displayFn = displayEmpty, .children = null },
    .{ .name = "context", .displayFn = displayEmpty, .children = null },
    .{ .name = "dialog", .displayFn = displayEmpty, .children = null },
    .{ .name = "dropdowns", .displayFn = displayEmpty, .children = &.{
        .{ .name = "dropdown", .displayFn = displayEmpty, .children = null },
        .{ .name = "dropdownEnum", .displayFn = displayDropDownEnum, .children = null },
    } },
    .{ .name = "expander", .displayFn = displayEmpty, .children = null },
    .{ .name = "flexbox", .displayFn = displayEmpty, .children = null },
    .{ .name = "floatingMenu", .displayFn = displayEmpty, .children = null },

    .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = &.{
        .{ .name = "floatingWindow", .displayFn = displayEmpty, .children = null },
        .{ .name = "windowHeader", .displayFn = displayEmpty, .children = null },
    } },

    .{ .name = "focusGroup", .displayFn = displayEmpty, .children = null },

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
