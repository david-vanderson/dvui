//! A group of functions for displaying and editing values in structs
//!
//! The main structs and functions are:
//! fn displayStruct() which can be used to recursively display and/or edit all values in a struct.
//! union FieldOptions are used to control how each field is displayed or edited.
//! fn StructOptions(T) generates a set of FieldOptions for a struct.
//!
//! string_map holds any heap-allocated memory created when strings are modified.
//! These are automatically cleaned up during Window.deinit().

pub const defaults = struct {
    /// display structs and sub-structs expanded
    pub var display_expanded: bool = true;
    /// Make display more compatible with narrow layouts
    pub var narrow: bool = false;
    /// By default struct_ui will use the gpa passed to the dvui window.
    /// If you want to use a different allocator, you can set it here.
    pub var string_allocator: ?std.mem.Allocator = null;
};

const log = std.log.scoped(.struct_ui);

/// Field options control whether and how fields are displayed.
///
/// Use TextFieldOptions for any array or slice of u8 you want ot display as a string.
/// Use NumberFieldOptions for any numbers, allowing setting of min and max ranges and other options
/// Use BooleanFieldOptions for any bools.
/// Use StandardFieldOptions can be used for any field to give a default layout.
/// Use OptionalFieldOptions to use different field options for the optional vs the optional's value.
/// If a custom display function is supplied, they will be used to display the struct instead of
/// the struct_ui default functions.
///
/// All FieldOptions types must provide:
/// - display: DisplayMode
/// - label: ?[]const u8
/// - customDisplayFn: ?*const fn(field_name: []const u8, field_value_ptr: *anyopaque, read_only: bool, al: *dvui.Alignment)
/// - default_expanded: ?bool
pub const FieldOptions = union(enum) {
    /// Control if the field should be displayed and if it is editable.
    const DisplayMode = enum {
        /// do not display
        none,
        /// display only
        read_only,
        /// editable
        read_write,
        /// read-only for this field and all children
        /// treats the field as if it is const
        constant,
    };
    standard: StandardFieldOptions,
    number: NumberFieldOptions,
    text: TextFieldOptions,
    boolean: BoolFieldOptions,
    optional: OptionalFieldOptions,

    // Types without a FieldOptions field
    // Prevent FieldOptions becoming a recursive type.
    pub const ChildFieldOptions = union(enum) {
        none: void,
        standard: StandardFieldOptions,
        number: NumberFieldOptions,
        text: TextFieldOptions,
        boolean: BoolFieldOptions,
        // optional excluded as it contains child FieldOptions field.

        pub fn asFieldOption(self: ChildFieldOptions) ?FieldOptions {
            switch (self) {
                .none => return null,
                .standard => |fo| return @unionInit(FieldOptions, "standard", fo),
                .number => |fo| return @unionInit(FieldOptions, "number", fo),
                .text => |fo| return @unionInit(FieldOptions, "text", fo),
                .boolean => |fo| return @unionInit(FieldOptions, "boolean", fo),
            }
        }
    };

    /// All field can use `default` standard field option, however using the correct field
    /// option will ensure the field is displayed correctly.
    /// e.g. a slice of u8 will only be displayed as a "string" when using TextFieldOptions
    pub const default: FieldOptions = .{ .standard = .{} };
    pub const defaultNumber: FieldOptions = .{ .number = .{} };
    pub const defaultText: FieldOptions = .{ .text = .{} };
    pub const defaultTextRW: FieldOptions = .{ .text = .{ .display = .read_write } };
    pub const defaultBool: FieldOptions = .{ .boolean = .{} };
    pub const defaultHidden: FieldOptions = .{ .standard = .{ .display = .none } };
    pub const defaultReadOnly: FieldOptions = .{ .standard = .{ .display = .read_only } };
    pub const defaultConst: FieldOptions = .{ .standard = .{ .display = .constant } };
    pub fn optionStandard(self: FieldOptions, field_name: []const u8) StandardFieldOptions {
        return switch (self) {
            .standard => |fo| fo,
            else => {
                log.debug(msg_invalid_opt_type, .{ self, field_name });
                return .{};
            },
        };
    }

    pub fn optionNumber(self: FieldOptions, field_name: []const u8) NumberFieldOptions {
        return switch (self) {
            .number => |fo| fo,
            .standard => |fo| .{
                .label = fo.label,
                .display = fo.display,
                .customDisplayFn = fo.customDisplayFn,
            },
            else => {
                log.debug(msg_invalid_opt_type, .{ self, field_name });
                return .{};
            },
        };
    }

    pub fn optionText(self: FieldOptions, field_name: []const u8) TextFieldOptions {
        return switch (self) {
            .text => |fo| fo,
            .standard => |fo| .{
                .label = fo.label,
                .display = fo.display,
                .customDisplayFn = fo.customDisplayFn,
            },
            else => {
                log.debug(msg_invalid_opt_type, .{ self, field_name });
                return .{};
            },
        };
    }

    pub fn optionBool(self: FieldOptions, field_name: []const u8) BoolFieldOptions {
        return switch (self) {
            .boolean => |fo| fo,
            .standard => |fo| .{
                .label = fo.label,
                .display = fo.display,
                .customDisplayFn = fo.customDisplayFn,
            },
            else => {
                log.debug(msg_invalid_opt_type, .{ self, field_name });
                return .{};
            },
        };
    }

    pub fn optionOptional(self: FieldOptions, _: []const u8) OptionalFieldOptions {
        return switch (self) {
            .optional => |fo| fo,
            inline else => |fo| .{
                .label = fo.label,
                .display = fo.display,
                .customDisplayFn = fo.customDisplayFn,
            },
        };
    }

    /// If this FieldOption supports child options,
    /// return the child options, otherwise return self.
    pub fn childOption(self: FieldOptions) FieldOptions {
        switch (self) {
            inline else => |fo| {
                if (@hasField(@TypeOf(fo), "child")) {
                    return fo.child.asFieldOption() orelse .{ .standard = .{
                        .display = fo.display,
                        .label = fo.label,
                        .customDisplayFn = fo.customDisplayFn,
                    } };
                }
                return self;
            },
        }
    }

    pub fn displayMode(self: FieldOptions) DisplayMode {
        return switch (self) {
            inline else => |fo| fo.display,
        };
    }

    pub fn displayLabel(self: FieldOptions, field_name: []const u8) []const u8 {
        return switch (self) {
            inline else => |fo| fo.label orelse field_name,
        };
    }

    pub fn labelSet(self: *FieldOptions, field_label: []const u8) void {
        switch (self.*) {
            inline else => |*fo| fo.label = field_label,
        }
    }

    /// For container fields, controls whether the field is displayed expanded or collapsed.
    pub fn defaultExpanded(self: FieldOptions) bool {
        return switch (self) {
            inline else => |fo| fo.default_expanded orelse defaults.display_expanded,
        };
    }

    pub fn hasCustomDisplayFn(self: FieldOptions) bool {
        switch (self) {
            inline else => |fo| return fo.customDisplayFn != null,
        }
    }

    pub fn customDisplayFn(self: FieldOptions, field_name: []const u8, field_value_ptr: *anyopaque, read_only: bool, alignment: *dvui.Alignment) void {
        switch (self) {
            inline else => |fo| if (fo.customDisplayFn) |displayFn| displayFn(field_name, field_value_ptr, read_only, alignment),
        }
    }

    pub fn markConst(self: *FieldOptions) void {
        switch (self.*) {
            inline else => |*fo| fo.display = .constant,
        }
    }
};

/// Standard field options allow control of the display mode and
/// option to provide an alternative label.
/// All FieldOption types must support the display and label fields.
pub const StandardFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    // Display the field using this function, instead of the default struct_ui function.
    customDisplayFn: ?*const fn ([]const u8, *anyopaque, bool, *dvui.Alignment) void = null,

    label: ?[]const u8 = null,
    // For container fields, controls if the container displayed expanded or collapsed.
    // If not set uses defaults.display_expanded.
    default_expanded: ?bool = null,
};

/// Creates a default set of field options for a struct or union.
///
/// An optional default value can be provided to init, and used whenever
/// the struct or union must be created. e.g. from setting an optional to Not Null.
///
/// Field options can be overridden after creation directly through the
/// field_options member. Use .remove() and/or .put().
pub fn StructOptions(Struct: type) type {
    switch (@typeInfo(Struct)) {
        .@"struct", .@"union" => {},
        else => @compileError(std.fmt.comptimePrint("StructOptions(T) requires Struct or Union, but received a {s}.", .{@typeName(Struct)})),
    }
    return struct {
        const Self = @This();

        pub const StructOptionsT = std.EnumMap(std.meta.FieldEnum(StructT), FieldOptions);
        // Type of struct or union these options belong to
        pub const StructT = Struct;

        // display options for each field to be displayed
        field_options: StructOptionsT,
        // A default value to be used whenever an instance of this type is created
        default_value: ?StructT = null,
        // Display the struct using this function, instead of the default struct_ui function.
        customDisplayFn: ?*const fn ([]const u8, *anyopaque, bool, *dvui.Alignment) void = null,
        // If set, this struct_option will only apply to fields with this name
        for_field_name: ?[]const u8 = null,

        /// Initialize and display only the fields provided.
        /// options: field options for all the fields to be displayed.
        /// default_value: An optional default value to be used whenever an instance
        /// of this type needs ot be created.
        ///
        /// Example Usage - Do not display the .a field and display all other fields as sliders.
        /// ```
        /// const color_options: dvui.struct_ui.StructOptions(dvui.Color) = .init(.{
        /// .r = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        /// .g = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        /// .b = .{ .number = .{ .min = 0, .max = 255, .widget_type = .slider } },
        /// }, .{ .r = 127, .g = 127, .b = 127, .a = 255 });
        /// ```
        pub fn init(
            options: std.enums.EnumFieldStruct(
                StructOptionsT.Key,
                ?StructOptionsT.Value,
                @as(?StructOptionsT.Value, null),
            ),
            comptime default_value: ?StructT,
        ) Self {
            return .{
                .field_options = .init(options),
                .default_value = default_value,
            };
        }

        /// Initialize struct options with default options for all fields.
        /// Overrides for these defaults are specified in options.
        ///
        /// options: field options for all the fields to be displayed.
        /// default_value: An optional default value to be used whenever an instance
        /// of this type needs ot be created.
        /// Used with the same syntax as .init, with the only difference being that this initializer
        /// creates default field options for any fields not provided in options.
        ///
        /// Example Usage - Display .r, .g, .b, .a as default text entry boxes.
        /// `const color_options: dvui.struct_ui.StructOptions(dvui.Color) = .init(.{}, null);`
        pub fn initWithDefaults(comptime options: std.enums.EnumFieldStruct(
            StructOptionsT.Key,
            ?StructOptionsT.Value,
            @as(?StructOptionsT.Value, null),
        ), comptime default_value: ?StructT) Self {
            comptime var field_options: StructOptionsT = .{};
            comptime {
                for (0..field_options.values.len) |i| {
                    const key = StructOptionsT.Indexer.keyForIndex(i);
                    const field_name = @tagName(key);
                    if (@field(options, field_name)) |*v| {
                        field_options.put(key, v.*);
                    } else {
                        const type_info = @typeInfo(@FieldType(StructT, field_name));
                        // Skip creating default field options for any pointer fields that can't be displayed.
                        if (type_info == .pointer and !canDisplayPtr(type_info.pointer)) continue;
                        field_options.put(key, defaultFieldOption(@FieldType(StructT, field_name)));
                    }
                }
            }
            return .{
                .field_options = field_options,
                .default_value = default_value,
            };
        }

        /// Use a custom display function to display this struct.
        pub fn initWithDisplayFn(
            // Display the struct using this function, instead of the default struct_ui function.
            customDisplayFn: *const fn (field_name: []const u8, field_value_ptr: *anyopaque, read_only: bool, *dvui.Alignment) void,
            comptime default_value: ?StructT,
        ) Self {
            return .{
                .field_options = .init(.{}),
                .customDisplayFn = customDisplayFn,
                .default_value = default_value,
            };
        }

        /// Helper for setting `for_field_name` after construction.
        /// If `for_field_name` is set, these options will only apply to fields
        /// field with that field name.
        ///
        /// Useful for dealing with common struct such as dvui.Point where you want
        /// to display different fields of the same type using different widgets.
        ///
        /// NOTE: Ordering is important. If there are multiple options for the same struct type
        /// order the field_name variants before the generic struct options.
        pub fn forFieldName(self: Self, field_name: []const u8) Self {
            // This should be rarely used, so this is fine. But if we add more of these
            // options, move to using an init_opts struct, rather than this builder pattern.
            var result = self;
            result.for_field_name = field_name;
            return result;
        }

        /// Return a default value for a field if no default for that field has been supplied through
        /// StructOptions.
        pub fn defaultFieldOption(FieldType: type) FieldOptions {
            return switch (@typeInfo(FieldType)) {
                .int, .float => .{ .number = .{} },
                .bool => .{ .boolean = .{} },
                // For arrays, pointers and optionals, field_options are set for the child type.
                .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
                    .{
                        .text = .{ .display = if (ptr.is_const or ptr.sentinel_ptr != null) .read_only else .read_write },
                    }
                else
                    defaultFieldOption(ptr.child),
                .optional => |opt| defaultFieldOption(opt.child),
                .array => |arr| if (arr.child == u8) .{ .text = .{ .display = .read_only } } else defaultFieldOption(arr.child),
                else => .{ .standard = .{} },
            };
        }
    };
}

/// Controls how numeric fields are displayed.
/// Note that min and max are stored as f64, which can represent
/// all integer values up to an i53/u53.
pub const NumberFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    label: ?[]const u8 = null,
    customDisplayFn: ?*const fn ([]const u8, *anyopaque, bool, *dvui.Alignment) void = null,
    default_expanded: ?bool = null,

    /// For .read_write, display as either a text entry box or as a slider.
    widget_type: enum {
        number_entry,
        slider,
        slider_entry,
        // Apply a number only when the user presses enter.
        // Display the value as a placeholder if no value is being entered.
        entry_on_enter,
    } = .number_entry,
    /// Minimum value - required if widget_type is slider.
    min: ?f64 = null,
    /// Maximum value - required if widget_type is slider.
    max: ?f64 = null,

    /// Display as a slider.
    pub fn initAsSlider(min_val: f64, max_val: f64) NumberFieldOptions {
        return .{
            .widget_type = .slider,
            .min = min_val,
            .max = max_val,
        };
    }

    /// Return a typed copy of the min value
    pub fn minValue(self: *const NumberFieldOptions, T: type) T {
        return switch (@typeInfo(T)) {
            .int => @intFromFloat(self.min orelse @max(std.math.minInt(T), std.math.minInt(i52))),
            .float => @floatCast(self.min orelse -std.math.floatMax(T)),
            else => unreachable,
        };
    }

    /// Return a typed copy of the max value
    pub fn maxValue(self: *const NumberFieldOptions, T: type) T {
        return switch (@typeInfo(T)) {
            .int => @intFromFloat(self.max orelse @min(std.math.maxInt(T), std.math.maxInt(u53))),
            .float => @floatCast(self.max orelse std.math.floatMax(T)),
            else => unreachable,
        };
    }

    /// Cast between different numeric types.
    pub fn cast(T: type, value: anytype) T {
        return switch (@typeInfo(@TypeOf(value))) {
            .int => switch (@typeInfo(T)) {
                .int => @intCast(value),
                .float => @floatFromInt(value),
                else => unreachable,
            },
            .float => switch (@typeInfo(T)) {
                .int => @intFromFloat(value),
                .float => @floatCast(value),
                else => unreachable,
            },
            else => unreachable,
        };
    }

    /// For slider, convert slider percentage into a number between min and max.
    pub fn normalizedPercentToNum(self: *const NumberFieldOptions, comptime T: type, normalized_percent: f32) T {
        if (@typeInfo(T) != .int and @typeInfo(T) != .float) @compileError("T is not a number type");
        std.debug.assert(normalized_percent >= 0 and normalized_percent <= 1);

        const min = self.minValue(T);
        const max = self.maxValue(T);
        const range = max - min;

        const result: T = switch (@typeInfo(T)) {
            .int => @intFromFloat(@as(f32, @floatFromInt(min)) + @as(f32, @floatFromInt(range)) * normalized_percent),
            .float => @as(T, min + range * @as(T, @floatCast(normalized_percent))),
            else => unreachable,
        };
        return result;
    }

    /// For slider, convert number to a slider percentage
    pub fn toNormalizedPercent(self: *const NumberFieldOptions, T: type, input_num: anytype) f32 {
        if (@typeInfo(T) != .int and @typeInfo(T) != .float) @compileError("T is not a number type");

        const min = self.minValue(T);
        const max = self.maxValue(T);
        const input, const range, const min_f = switch (@typeInfo(@TypeOf(input_num))) {
            .int => .{
                std.math.clamp(@as(f32, @floatFromInt(input_num)), @as(f32, @floatFromInt(min)), @as(f32, @floatFromInt(max))),
                @as(f32, @floatFromInt(max - min)),
                @as(f32, @floatFromInt(min)),
            },
            .float => .{
                input_num,
                max - min,
                min,
            },
            else => unreachable,
        };
        const progress = input - min_f;
        return @as(f32, @floatCast(progress / range));
    }
};

/// Display a numeric field
pub fn numberFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: NumberFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(null, &.{ .float, .int }, "numberFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    const T = @TypeOf(field_value_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display != .read_write;

    switch (opt.widget_type) {
        .number_entry => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });

            var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            if (!read_only) {
                const maybe_num = dvui.textEntryNumber(@src(), T, .{
                    .min = opt.minValue(T),
                    .max = opt.maxValue(T),
                    .value = field_value_ptr,
                    .show_min_max = opt.min != null and opt.max != null,
                }, .{});
                if (maybe_num.value == .Valid) {
                    field_value_ptr.* = maybe_num.value.Valid;
                }
            }
            if (!defaults.narrow or read_only)
                dvui.label(@src(), "{d}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
        },
        .entry_on_enter => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });

            var enter_pressed = dvui.dataGetDefault(null, box.data().id, "_enter_pressed", bool, false);
            defer dvui.dataSet(null, box.data().id, "_enter_pressed", enter_pressed);

            var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            if (!read_only) {
                const value_str = std.fmt.allocPrint(dvui.currentWindow().lifo(), "{d}", .{field_value_ptr.*}) catch "";
                defer dvui.currentWindow().lifo().free(value_str);
                var te_wd: dvui.WidgetData = undefined;
                const maybe_num = dvui.textEntryNumber(@src(), T, .{
                    .text = if (enter_pressed) "" else null,
                    .placeholder = value_str,
                }, .{ .data_out = &te_wd });
                if (maybe_num.value == .Valid and maybe_num.enter_pressed) {
                    field_value_ptr.* = std.math.clamp(
                        maybe_num.value.Valid,
                        opt.minValue(T),
                        opt.maxValue(T),
                    );
                    enter_pressed = true;
                } else if (maybe_num.value == .Valid and !maybe_num.enter_pressed) {
                    dvui.tooltip(@src(), .{
                        .active_rect = te_wd.borderRectScale().r,
                        .position = .vertical,
                    }, "Press Enter to set value", .{}, .{});
                } else {
                    enter_pressed = false;
                }
            }
            if (!defaults.narrow or read_only)
                dvui.label(@src(), "{d}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
        },
        .slider => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });
            var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            if (!read_only) {
                var percent = opt.toNormalizedPercent(T, field_value_ptr.*);
                _ = dvui.slider(@src(), .{ .fraction = &percent }, .{
                    .expand = .horizontal,
                    .min_size_content = .{ .w = 100, .h = 20 },
                });
                field_value_ptr.* = opt.normalizedPercentToNum(T, percent);
            }
            dvui.label(@src(), "{d}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
        },
        .slider_entry => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();
            dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });
            var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id), .expand = .vertical });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            if (!read_only) {
                var se_wd: dvui.WidgetData = undefined;
                var value: f32 = NumberFieldOptions.cast(f32, field_value_ptr.*);
                if (dvui.sliderEntry(@src(), "{d:0.2}", .{
                    .value = &value,
                    .min = opt.minValue(f32),
                    .max = opt.maxValue(f32),
                }, .{ .data_out = &se_wd, .gravity_y = 0.5 })) {
                    field_value_ptr.* = NumberFieldOptions.cast(T, value);
                }
                if (dvui.focusedWidgetId() == se_wd.id) {
                    dvui.tooltip(@src(), .{
                        .active_rect = se_wd.borderRectScale().r,
                        .delay = 1_000_000,
                        .position = .vertical,
                    }, "Press Enter to type a value", .{}, .{});
                }
            } else {
                dvui.label(@src(), "{d}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
            }
        },
    }
}

/// Display a numeric field
pub fn numberFieldWidgetOptional(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_optional_ptr: anytype,
    opt: NumberFieldOptions,
    alignment: *dvui.Alignment,
) void {
    const type_info = @typeInfo(@TypeOf(field_value_optional_ptr));
    if (type_info != .pointer or @typeInfo(type_info.pointer.child) != .optional) {
        @compileError(std.fmt.comptimePrint("{s} requires a pointer to an optional, but received a {s}", .{ "numberFieldWidgetOptional", @typeName(field_value_optional_ptr.*) }));
    }
    validateFieldPtrType(null, &.{ .float, .int }, "numberFieldWidgetOptional", @TypeOf(&field_value_optional_ptr.*.?));
    if (opt.display == .none) return;

    const T = @TypeOf(field_value_optional_ptr.*.?);
    const read_only = @typeInfo(@TypeOf(field_value_optional_ptr)).pointer.is_const or opt.display != .read_write;

    switch (opt.widget_type) {
        .number_entry => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}?", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });

            var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            if (!read_only) {
                const maybe_num = dvui.textEntryNumber(@src(), T, .{
                    .min = opt.minValue(T),
                    .max = opt.maxValue(T),
                    .value = if (field_value_optional_ptr.*) |*opt_ptr| opt_ptr else null,
                    .show_min_max = opt.min != null and opt.max != null,
                    .placeholder = "null",
                }, .{});
                if (maybe_num.value == .Valid) {
                    field_value_optional_ptr.* = maybe_num.value.Valid;
                } else {
                    field_value_optional_ptr.* = null;
                }
            }
            if (!defaults.narrow or read_only)
                dvui.label(@src(), "{?d}", .{field_value_optional_ptr.*}, .{ .margin = .{ .y = 4 } });
        },
        .slider, .slider_entry, .entry_on_enter => {
            unreachable;
        },
    }
}

pub fn enumFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: StandardFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(null, &.{.@"enum"}, "enumFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    const T = @TypeOf(field_value_ptr.*);
    const exhaustive = @typeInfo(T).@"enum".is_exhaustive;
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display != .read_write;
    if (!read_only and !exhaustive) {
        // TODO: Display these as numbers and do the enum<->int conversion.
        log.debug("non-exhaustive enum {s}.{s} can only be displayed read-only", .{ @typeName(T), field_name });
    }

    var box = dvui.box(src, .{ .dir = .horizontal }, .{ .expand = .horizontal });
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only and exhaustive) {
        dvui.label(@src(), "{s}", .{@tagName(field_value_ptr.*)}, .{ .margin = .{ .y = 4 } });
    } else if (!exhaustive) {
        dvui.label(@src(), "{d}", .{@intFromEnum(field_value_ptr.*)}, .{ .margin = .{ .y = 4 } });
    } else {
        const choices = std.meta.FieldEnum(T);
        const entries = std.meta.fieldNames(choices);
        var choice: usize = @intFromEnum(std.meta.stringToEnum(std.meta.FieldEnum(T), @tagName(field_value_ptr.*)).?);
        _ = dvui.dropdown(@src(), entries, .{ .choice = &choice }, .{}, .{});

        field_value_ptr.* = std.meta.stringToEnum(T, @tagName(@as(std.meta.FieldEnum(T), @enumFromInt(choice)))).?;
    }
}

pub fn enumFieldWidgetOptional(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_optional_ptr: anytype,
    opt: StandardFieldOptions,
    alignment: *dvui.Alignment,
) void {
    const type_info = @typeInfo(@TypeOf(field_value_optional_ptr));
    if (type_info != .pointer or @typeInfo(type_info.pointer.child) != .optional) {
        @compileError(std.fmt.comptimePrint("{s} requires a pointer to an optional, but received a {s}", .{ "enumFieldWidgetOptional", @typeName(field_value_optional_ptr.*) }));
    }
    validateFieldPtrType(null, &.{.@"enum"}, "enumFieldWidget", @TypeOf(&field_value_optional_ptr.*.?));
    if (opt.display == .none) return;

    const T = @TypeOf(field_value_optional_ptr.*.?);
    const read_only = @typeInfo(@TypeOf(field_value_optional_ptr)).pointer.is_const or opt.display != .read_write;
    var box = dvui.box(src, .{ .dir = .horizontal }, .{ .expand = .horizontal });
    defer box.deinit();

    dvui.label(@src(), "{s}?", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        dvui.label(@src(), "{s}", .{if (field_value_optional_ptr.*) |field_value| @tagName(field_value) else "null"}, .{ .margin = .{ .y = 4 } });
    } else {
        const choices = std.meta.FieldEnum(T);
        const entries = std.meta.fieldNames(choices);
        var choice: ?usize = if (field_value_optional_ptr.*) |field_value|
            @intFromEnum(std.meta.stringToEnum(std.meta.FieldEnum(T), @tagName(field_value)).?)
        else
            null;
        _ = dvui.dropdown(@src(), entries, .{ .choice_nullable = &choice }, .{ .placeholder = "null" }, .{});

        if (choice) |ch| {
            @setEvalBranchQuota(5000);
            field_value_optional_ptr.* = std.meta.stringToEnum(T, @tagName(@as(std.meta.FieldEnum(T), @enumFromInt(ch)))).?;
        } else
            field_value_optional_ptr.* = null;
    }
}

/// Options for displaying a text field.
pub const BoolFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    label: ?[]const u8 = null,
    customDisplayFn: ?*const fn ([]const u8, *anyopaque, bool, *dvui.Alignment) void = null,
    default_expanded: ?bool = null,
    widget_type: union(enum) {
        // true/false/null dropdown.
        dropdown: void,
        // keep displaying true until manually reset (for read-only values)
        manual_reset: void,
        // show true then fade to false (for read-only value)
        trigger_on: bool,
        // show as checkbox
        checkbox: void,
    } = .dropdown,
};

pub fn boolFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: BoolFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(null, &.{.bool}, "boolFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display != .read_write;

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        if (opt.widget_type == .manual_reset) {
            const prev_state = dvui.dataGetDefault(null, box.data().id, "bool", bool, false);
            var state = prev_state or field_value_ptr.*;
            var data_out: dvui.WidgetData = undefined;
            _ = dvui.checkbox(@src(), &state, "", .{ .data_out = &data_out, .margin = .{ .y = 4 } });
            if (state)
                dvui.tooltip(@src(), .{ .active_rect = data_out.borderRectScale().r, .delay = 1_000_000 }, "Value was set to true since last manual reset.", .{}, .{})
            else
                dvui.tooltip(@src(), .{ .active_rect = data_out.borderRectScale().r, .delay = 1_000_000 }, "Value was not set to true since last manual reset", .{}, .{});

            dvui.dataSet(null, box.data().id, "bool", state);
        } else if (opt.widget_type == .trigger_on) {
            if (opt.widget_type.trigger_on == field_value_ptr.*) {
                dvui.animation(box.data().id, "trigger", .{ .start_val = 0, .end_val = 1.0, .start_time = 0, .end_time = 1_000_000, .easing = easing });
            }
            if (dvui.animationGet(box.data().id, "trigger")) |a| {
                const prev_alpha = dvui.alpha(a.value());
                defer dvui.alphaSet(prev_alpha);
                if (!a.done()) {
                    dvui.label(@src(), "{}", .{opt.widget_type.trigger_on}, .{ .margin = .{ .y = 4 } });
                } else {
                    dvui.label(@src(), "{}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
                    dvui.refresh(null, @src(), null);
                }
            } else {
                dvui.label(@src(), "{}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
            }
        } else {
            dvui.label(@src(), "{}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
        }
    } else {
        if (opt.widget_type == .checkbox) {
            _ = dvui.checkbox(@src(), field_value_ptr, "", .{});
        } else {
            const entries = .{ "false", "true" };
            var choice: usize = if (field_value_ptr.* == false) 0 else 1;
            _ = dvui.dropdown(@src(), &entries, .{ .choice = &choice }, .{}, .{});
            field_value_ptr.* = if (choice == 0) false else true;
        }
    }
}

// Bring in immediately, hold, then smoothstep fade.
// Return 1 if t < 0.4, then smoothstep to 0 for remainder
fn easing(t: f32) f32 {
    if (t < 0.4) return 1;
    const u = (t - 0.4) / 0.6;
    return 1 - u * u * (3 - 2 * u);
}

pub fn boolFieldWidgetOptional(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_optional_ptr: anytype,
    opt: BoolFieldOptions,
    alignment: *dvui.Alignment,
) void {
    const type_info = @typeInfo(@TypeOf(field_value_optional_ptr));
    if (type_info != .pointer or @typeInfo(type_info.pointer.child) != .optional) {
        @compileError(std.fmt.comptimePrint("{s} requires a pointer to an optional, but received a {s}", .{ "boolFieldWidgetOptional", @typeName(field_value_optional_ptr.*) }));
    }
    validateFieldPtrType(null, &.{.bool}, "boolFieldWidgetOptional", @TypeOf(&field_value_optional_ptr.*.?));
    if (opt.display == .none) return;

    const read_only = @typeInfo(@TypeOf(field_value_optional_ptr)).pointer.is_const or opt.display != .read_write;

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}?", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        dvui.label(@src(), "{?}", .{field_value_optional_ptr.*}, .{ .margin = .{ .y = 4 } });
    } else {
        const entries = .{ "null", "false", "true" };
        var choice: usize = if (field_value_optional_ptr.*) |field_value|
            if (field_value) 2 else 1
        else
            0;
        _ = dvui.dropdown(@src(), &entries, .{ .choice = &choice }, .{}, .{});
        field_value_optional_ptr.* = switch (choice) {
            0 => null,
            1 => false,
            2 => true,
            else => unreachable,
        };
    }
}

/// Options for displaying a text field.
pub const TextFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    label: ?[]const u8 = null,
    customDisplayFn: ?*const fn ([]const u8, *anyopaque, bool, *dvui.Alignment) void = null,
    default_expanded: ?bool = null,
    multiline: bool = false,

    /// Set to true if the string is heap allocated and should be
    /// freed before a new string is allocated.
    heap_allocated: bool = false,
};

/// Is the string backed by a buffer or dynamically allocated?
const StringBackingType = union(enum) {
    buffer: []u8,
    gpa: std.mem.Allocator,
};

/// Display slices and/or arrays of u8 and const u8.
/// If a slice, the slice will be assigned to a duplicated copy of the
/// text widget's buffer.
pub fn textFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: TextFieldOptions,
    alignment: *dvui.Alignment,
    backing: StringBackingType,
) void {
    validateFieldPtrTypeString(null, "textFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;
    const T = @TypeOf(field_value_ptr.*);

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    const sentinel_terminated = @typeInfo(T).pointer.sentinel_ptr != null;

    var read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display != .read_write;

    if (opt.display == .read_write and read_only) {
        // Note all string arrays are currently treated as read-only, even if they are var.
        // It would be possible to support in-place editing, preferably by implementing a new display option.
        log.debug("field {s} display option is set to read_write for read_only string or an array. Displaying as read_only.", .{field_name});
    } else if (opt.display == .read_write and sentinel_terminated) {
        // Sentinel terminated strings cannot be edited.
        // Would require keeping 2 string maps, for sentinel vs non-sentinel strings.
        log.debug("field {s} display option is set to read_write for sentinel terminated string or an array. Displaying as read_only.", .{field_name});
        read_only = true;
    }

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{ .margin = .{ .y = 4 } });
    if (!read_only) {
        // If the original string is heap allocated, then add it to the map so it will be freed before a new string
        // is allocated.
        if (backing == .gpa and opt.heap_allocated and !string_map.contains(field_value_ptr)) {
            string_map.put(dvui.currentWindow().gpa, field_value_ptr, field_value_ptr.*) catch |err| {
                dvui.logError(@src(), err, "Error adding to struct_ui.string_map. This will leak memory", .{});
            };
        }
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());

        const textbox_width = dvui.themeGet().font_body.sizeM(dvui.TextEntryWidget.defaultMWidth, 1).w;
        const text_box = dvui.textEntry(@src(), if (backing == .buffer) .{ .text = .{ .buffer = backing.buffer }, .multiline = opt.multiline } else .{ .multiline = opt.multiline }, .{
            .min_size_content = if (opt.multiline) .{ .h = dvui.themeGet().font_body.lineHeight() * 2, .w = textbox_width } else null,
            .max_size_content = if (opt.multiline) .{ .h = dvui.themeGet().font_body.lineHeight() * 4, .w = textbox_width } else null,
        });
        defer text_box.deinit();
        if (!text_box.text_changed and !std.mem.eql(u8, text_box.getText(), field_value_ptr.*)) {
            text_box.textSet(field_value_ptr.*, false);
        }
        if (!@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const and !sentinel_terminated) {
            if (text_box.text_changed and !std.mem.eql(u8, text_box.getText(), field_value_ptr.*)) {
                switch (backing) {
                    .gpa => {
                        if (string_map.getEntry(field_value_ptr)) |entry| {
                            backing.gpa.free(entry.value_ptr.*);
                        }
                        // Memory leaks from this line are caused by not calling struct_ui.deinit()
                        field_value_ptr.* = backing.gpa.dupe(u8, text_box.getText()) catch "";
                        string_map.put(dvui.currentWindow().gpa, field_value_ptr, field_value_ptr.*) catch |err| {
                            dvui.logError(@src(), err, "Error adding to struct_ui.string_map. This will leak memory", .{});
                        };
                    },
                    .buffer => {
                        field_value_ptr.* = text_box.getText();
                    },
                }
            }
        }
    } else {
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());

        dvui.label(@src(), "{s}", .{field_value_ptr.*}, .{ .margin = .{ .y = 4 } });
    }
}

/// Returns the enum type associated with a tagged union
/// validates that FieldPtrType points to a tagged union.
pub fn UnionTagType(FieldPtrType: type) type {
    validateFieldPtrType(null, &.{.@"union"}, "unionFieldWidget", FieldPtrType);
    const type_info = @typeInfo(@typeInfo(FieldPtrType).pointer.child);
    if (type_info.@"union".tag_type == null) {
        @compileError("Only tagged unions are supported.");
    }
    return type_info.@"union".tag_type.?;
}

/// Allow the selection of the active union member.
/// returns the tag of the active member.
pub fn unionFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: FieldOptions,
) UnionTagType(@TypeOf(field_value_ptr)) {
    const T = @TypeOf(field_value_ptr.*);
    if (@typeInfo(T).@"union".tag_type == null) {
        @compileError(std.fmt.comptimePrint("union field {s}: Only tagged unions are supported", .{field_name}));
    }

    if (opt.displayMode() == .none) {
        return field_value_ptr.*;
    }
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.displayMode() != .read_write;

    var box = dvui.box(src, .{ .dir = .vertical }, .{});
    defer box.deinit();

    const entries = std.meta.fields(T);
    var active_tag = std.meta.activeTag(field_value_ptr.*);

    // This loop is being used, rather than @intFromEnum etc as there is no guarantee that
    // the enum int values are the same as the field order. i.e. custom enums can be used as tags.
    // There should be a better way to do this than converting to string? But UnionField doesn't store the tag.
    const choice_names: []const []const u8, var active_choice_num: usize = blk: {
        var choice_names: [entries.len][]const u8 = undefined;
        var active_choice_num: usize = 0;
        inline for (0..entries.len) |i| {
            if (std.meta.stringToEnum(@TypeOf(active_tag), entries[i].name).? == std.meta.activeTag(field_value_ptr.*)) {
                active_choice_num = i;
            }
            choice_names[i] = entries[i].name;
        }
        break :blk .{ &choice_names, active_choice_num };
    };

    {
        var hbox = dvui.box(@src(), .{}, .{});
        defer hbox.deinit();
        if (read_only) {
            switch (active_tag) {
                // Don't display active tag, if it will be displayed as a field. i.e. it is not a void union member.
                // TODO: It is not strictly just void here. It is really any type that can't be displayed by
                // displayField(). Need to add a lookup for displayable types and use that here.
                inline else => |t| if (@FieldType(T, @tagName(t)) == void) {
                    dvui.labelNoFmt(@src(), @tagName(active_tag), .{}, .{ .margin = .{ .y = 4 } });
                },
            }
        } else {
            if (dvui.dropdown(@src(), choice_names, .{ .choice = &active_choice_num }, .{}, .{})) {
                active_tag = std.meta.stringToEnum(@TypeOf(active_tag), choice_names[active_choice_num]).?; // This should never fail.
            }
        }
    }
    return active_tag;
}

/// Optional field options can provide separate field options for both
/// the optional and the optional's value.
/// The value for the optional is set via the `child` field.
pub const OptionalFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    /// Display the field using this function, instead of the default struct_ui function.
    customDisplayFn: ?*const fn ([]const u8, *anyopaque, bool, *dvui.Alignment) void = null,

    label: ?[]const u8 = null,
    default_expanded: ?bool = null,
    /// the optional and the option's value can have different display modes.
    child: FieldOptions.ChildFieldOptions = .none,

    pub const default: OptionalFieldOptions = .{};
};

/// Display an optional
/// returns true if optional is not null
pub fn optionalFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opts: OptionalFieldOptions,
    alignment: *dvui.Alignment,
) bool {
    validateFieldPtrType(null, &.{.optional}, "optionalFieldWidget", @TypeOf(field_value_ptr));

    // Display mode is ignored. It controls whether the optional value is read_only, not the optional itself.
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opts.display != .read_write;

    var choice: usize = if (field_value_ptr.* == null) 0 else 1; // 0 = Null, 1 = Not Null

    var hbox = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer hbox.deinit();
    dvui.label(@src(), "{s}?", .{opts.label orelse field_name}, .{ .margin = .{ .y = 4 } });
    {
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(hbox.data().id, hbox_aligned.data());

        if (!read_only) {
            _ = dvui.dropdown(@src(), &.{ "null", "not null" }, .{ .choice = &choice }, .{}, .{});
        } else {
            dvui.labelNoFmt(@src(), if (choice == 0) "null" else "not null", .{}, .{ .margin = .{ .y = 4 } });
        }
    }
    return choice == 1; // Not null
}

/// Display a field within a container.
/// displayField can be used when iterating through a list of fields of varying types.
/// it will call the correct display function based on the type of the field.
pub fn displayField(
    src: std.builtin.SourceLocation,
    comptime ContainerT: type,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    if (field_option.displayMode() == .none) return;
    const PtrT = @TypeOf(field_value_ptr);
    if (@typeInfo(PtrT) != .pointer) {
        @compileError(std.fmt.comptimePrint("field_value_ptr for field {s} must be a pointer to a field. It is a {s}", .{ field_name, @typeName(PtrT) }));
    }

    // 1. Display using the field's custom display function if set.
    // 2. Display using the type's custom display function if set. (For Structs and Unions)
    // 3. Display using the default display functions.

    if (field_option.hasCustomDisplayFn()) {
        const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() != .read_write;
        field_option.customDisplayFn(field_name, @ptrCast(@constCast(field_value_ptr)), read_only, al);
        return;
    }

    switch (@typeInfo(@typeInfo(PtrT).pointer.child)) {
        .@"struct", .@"union" => {
            const struct_options = findMatchingStructOption(@TypeOf(field_value_ptr.*), field_name, options);
            if (struct_options) |so| {
                if (so.customDisplayFn) |displayFn| {
                    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() != .read_write;
                    displayFn(field_name, @ptrCast(@constCast(field_value_ptr)), read_only, al);
                    return;
                }
            }
        },
        else => {},
    }

    switch (@typeInfo(@TypeOf(field_value_ptr))) {
        .pointer => |top_ptr| {
            switch (@typeInfo(top_ptr.child)) {
                .int, .float => displayNumber(src, field_name, field_value_ptr, field_option, al),
                .bool => displayBool(src, field_name, field_value_ptr, field_option, al),
                .@"enum" => displayEnum(src, field_name, field_value_ptr, field_option, al),
                .array => |arr| {
                    // Array of u8 is only displayed as text if it has a text field option.
                    if (arr.child == u8 and field_option == .text) {
                        // Arrays can only currently be shown as const strings. (Don't know why std.mem.span won't work here?)
                        const slice: []const u8 = if (arr.sentinel() != null) field_value_ptr[0..std.mem.indexOfSentinel(u8, arr.sentinel().?, &field_value_ptr.*)] else &field_value_ptr.*;
                        displayString(src, field_name, &slice, field_option, al);
                    } else {
                        displayArray(src, ContainerT, field_name, field_value_ptr, depth, field_option, options);
                    }
                },
                .pointer => |ptr| {
                    if (ptr.size == .slice and ptr.child == u8 and field_option == .text) {
                        displayString(src, field_name, field_value_ptr, field_option, al);
                    } else {
                        displayPointer(src, ContainerT, field_name, field_value_ptr, depth, field_option, options, al);
                    }
                },
                .optional => {
                    displayOptional(src, ContainerT, field_name, field_value_ptr, depth, field_option, options, al, null);
                },
                .@"union" => displayUnion(src, field_name, field_value_ptr, depth, field_option, options),
                .@"struct" => {
                    if (depth > 0) {
                        if (displayStruct(src, field_name, field_value_ptr, depth - 1, field_option, options, null)) |box| {
                            box.deinit();
                        }
                    }
                },
                .type,
                .void,
                .noreturn,
                .comptime_int,
                .comptime_float,
                .undefined,
                .null,
                .error_union,
                .error_set,
                .@"fn",
                .@"opaque",
                .frame,
                .@"anyframe",
                .vector,
                .enum_literal,
                => {}, // These types are not displayed
            }
        },
        else => {
            validateFieldPtrType(field_name, &.{ .int, .float, .bool, .@"enum", .array, .pointer, .optional, .@"union", .@"struct" }, "displayField", @TypeOf(field_value_ptr));
        },
    }
}

const msg_invalid_opt_type = "invalid field option type {t} used for field {s}. Using default options.";

/// Display numeric fields, ints and floats.
pub fn displayNumber(src: std.builtin.SourceLocation, field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(field_name, &.{ .int, .float }, "displayNumber", @TypeOf(field_value_ptr));
    numberFieldWidget(src, field_name, field_value_ptr, field_option.optionNumber(field_name), al);
}

pub fn displayEnum(src: std.builtin.SourceLocation, field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(field_name, &.{.@"enum"}, "displayEnum", @TypeOf(field_value_ptr));
    enumFieldWidget(src, field_name, field_value_ptr, field_option.optionStandard(field_name), al);
}

/// Display []u8, []const u8 and arrays of u8 and const u8.
/// Arrays are always treated as read-only. In future this could be enhanced to support in-place editing.
/// When strings are modified, they are assigned to a duplicated version of the text widget's buffer.
pub fn displayString(src: std.builtin.SourceLocation, field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrTypeString(field_name, "displayString", @TypeOf(field_value_ptr));
    textFieldWidget(src, field_name, field_value_ptr, field_option.optionText(field_name), al, stringBackingAllocator());
}

/// Same as displayString, but uses a user-supplied buffer, rather than a dynamically allocated buffer.
pub fn displayStringBuf(src: std.builtin.SourceLocation, field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment, buffer: []u8) void {
    validateFieldPtrTypeString(field_name, "displayString", @TypeOf(field_value_ptr));
    textFieldWidget(src, field_name, field_value_ptr, field_option.optionText(field_name), al, .{ .buffer = buffer });
}

pub fn displayBool(src: std.builtin.SourceLocation, field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(field_name, &.{.bool}, "displayBool", @TypeOf(field_value_ptr));
    boolFieldWidget(src, field_name, field_value_ptr, field_option.optionBool(field_name), al);
}

pub fn displayArray(
    src: std.builtin.SourceLocation,
    comptime ContainerT: type,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrType(field_name, &.{.array}, "displayArray", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (displayContainer(src, field_option.displayLabel(field_name), field_option.defaultExpanded())) |vbox| {
        defer vbox.deinit();
        var alignment: dvui.Alignment = .init(@src(), depth);
        defer alignment.deinit();
        var element_field_option = field_option;
        for (field_value_ptr, 0..) |*val, i| {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = i });
            defer hbox.deinit();

            var field_name_buf: [21]u8 = undefined; // 20 chars = u64 + ':'
            const field_name_str = std.fmt.bufPrint(&field_name_buf, "{d}:", .{i}) catch "#";
            element_field_option.labelSet(field_name_str);

            displayField(@src(), ContainerT, field_name, val, depth, element_field_option, options, &alignment);
        }
    }
}

pub fn displaySlice(
    src: std.builtin.SourceLocation,
    comptime ContainerT: type,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrTypeSlice(field_name, "displaySlice", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (displayContainer(src, field_option.displayLabel(field_name), field_option.defaultExpanded())) |vbox| {
        defer vbox.deinit();
        var alignment: dvui.Alignment = .init(@src(), depth);
        defer alignment.deinit();

        var element_field_option = field_option;
        for (field_value_ptr.*, 0..) |*val, i| {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .id_extra = i,
            });
            defer hbox.deinit();

            var field_name_buf: [21]u8 = undefined; // 20 chars = u64 + ':'
            const field_name_str = std.fmt.bufPrint(&field_name_buf, "{d}:", .{i}) catch "#";
            element_field_option.labelSet(field_name_str);
            displayField(@src(), ContainerT, field_name, val, depth, element_field_option, options, &alignment);
        }
    }
}

/// Display a union.
///
/// If the union has Struct or Union members, then StructOptions(T) should be provided
/// for those members with an appropriate default_value.
/// These default values will be used to populate the active union value when the user changes selections.
pub fn displayUnion(
    src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrType(field_name, &.{.@"union"}, "displayUnion", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (@typeInfo(@TypeOf(field_value_ptr.*)).@"union".tag_type == null) {
        @compileError(std.fmt.comptimePrint("Field {s} cannot be displayed. Only tagged unions are supported.", .{field_name}));
    }
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    const current_choice = std.meta.activeTag(field_value_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() != .read_write;

    if (displayContainer(src, field_option.displayLabel(field_name), field_option.defaultExpanded())) |vbox| {
        defer vbox.deinit();

        const UnionT = @TypeOf(field_value_ptr.*);
        const new_choice = unionFieldWidget(@src(), field_name, field_value_ptr, field_option);
        if (current_choice != new_choice) {
            switch (new_choice) {
                inline else => |choice| {
                    const default_value = defaultValue(
                        @FieldType(UnionT, @tagName(choice)),
                        UnionT,
                        field_name,
                        options,
                    );
                    if (!read_only) {
                        if (default_value) |default| {
                            field_value_ptr.* = @unionInit(UnionT, @tagName(choice), default);
                        } else {
                            log.debug(
                                "Union field {s}.{s} cannot be selected as no default value is provided. Use struct_ui.StructOptions({s}) to provide a default.",
                                .{
                                    field_name, @tagName(choice),
                                    switch (@typeInfo(@FieldType(UnionT, @tagName(choice)))) {
                                        .@"union", .@"struct" => @typeName(@FieldType(UnionT, @tagName(choice))),
                                        else => @typeName(UnionT),
                                    },
                                },
                            );
                            return;
                        }
                    }
                },
            }
        }
        switch (field_value_ptr.*) {
            inline else => |*active, active_tag| {
                var inner_vbox = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal, .id_extra = @intFromEnum(active_tag) });
                defer inner_vbox.deinit();
                const struct_options: StructOptions(UnionT) = findMatchingStructOption(UnionT, field_name, options) orelse .initWithDefaults(.{}, null);
                var alignment: dvui.Alignment = .init(@src(), depth);
                defer alignment.deinit();

                // Will only display if an option exists for this field.
                if (struct_options.field_options.get(active_tag)) |union_field_option_| {
                    var union_field_option = union_field_option_;
                    if (field_option.displayMode() == .constant and union_field_option.displayMode() != .none) {
                        union_field_option.markConst();
                    }
                    displayField(@src(), UnionT, @tagName(active_tag), active, depth, union_field_option, options, &alignment);
                }
            },
        }
    }
}

/// Display an optional
///
/// - If the optional is a union or struct, StructOptions should be provided for those
///   types in the options tuple containing default_value's.
/// - These default values are used when the user creates a new optional value or activates a new the union member.
/// - Basic types are assigned a default value depending on their type. e.g. 0 for numbers, "" for strings.
/// - It is recommended that users handle optional pointers manually using optionalFieldWidget directly,
///   rather than using this function. Otherwise all instances of the type will point to a single default value as defaults
///   are per-type, not per field.
pub fn displayOptional(
    src: std.builtin.SourceLocation,
    comptime ContainerT: type,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
    default_value: ?@TypeOf(field_value_ptr.*),
) void {
    validateFieldPtrType(field_name, &.{.optional}, "displayOptional", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    const optional = @typeInfo(@TypeOf(field_value_ptr.*)).optional;
    const child_field_option = field_option.childOption();
    // Shortcut some common optionals
    switch (@typeInfo(optional.child)) {
        .bool => {
            boolFieldWidgetOptional(src, field_name, field_value_ptr, child_field_option.optionBool(field_name), al);
            return;
        },
        .@"enum" => {
            enumFieldWidgetOptional(src, field_name, field_value_ptr, child_field_option.optionStandard(field_name), al);
            return;
        },
        .int, .float => {
            const fo = child_field_option.optionNumber(field_name);
            if (fo.widget_type == .number_entry) {
                numberFieldWidgetOptional(@src(), field_name, field_value_ptr, fo, al);
                return;
            }
        },
        else => {},
    }

    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() != .read_write;
    if (optionalFieldWidget(src, field_name, field_value_ptr, field_option.optionOptional(field_name), al)) {
        if (!read_only) {
            if (field_value_ptr.* == null) {
                field_value_ptr.* = default_value orelse
                    defaultValue(optional.child, ContainerT, field_name, options); // If there is no default value, it will remain null.
            }
        }
        if (field_value_ptr.*) |*val| {
            displayField(@src(), ContainerT, field_name, val, depth, child_field_option, options, al);
        } else {
            log.debug("Optional field {s} cannot be selected as no default value is provided. Use struct_ui.StructOptions({s}) with a default or StructOptions({s}) with a default, setting a value for {s}.", .{
                field_name,
                @typeName(optional.child),
                @typeName(ContainerT),
                field_name,
            });
        }
    } else if (!read_only) {
        field_value_ptr.* = null;
    }
}

pub fn displayPointer(
    src: std.builtin.SourceLocation,
    comptime ContainerT: type,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option_: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    validateFieldPtrType(field_name, &.{.pointer}, "displayPointer", @TypeOf(field_value_ptr));

    const field_option = blk: {
        const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const;
        if (field_option_.displayMode() == .constant or (read_only and field_option_.displayMode() != .none)) {
            // Everything pointed to by a pointer to const must be const.
            var field_option = field_option_;
            field_option.markConst();
            break :blk field_option;
        } else {
            break :blk field_option_;
        }
    };
    if (field_option.displayMode() == .none) return;

    const ptr = @typeInfo(@TypeOf(field_value_ptr.*)).pointer;
    if (ptr.size == .one) {
        if (canDisplayPtr(ptr))
            displayField(src, ContainerT, field_name, field_value_ptr.*, depth, field_option, options, al);
    } else if (ptr.size == .slice) {
        if (canDisplayPtr(ptr))
            displaySlice(src, ContainerT, field_name, &field_value_ptr.*, depth, field_option, options);
    } else {
        @compileError(std.fmt.comptimePrint("C-style and many item pointers not supported for {s}.{s}\n", .{ @typeName(@TypeOf(field_value_ptr.*)), field_name }));
    }
}

/// Is this a pointer type that struct_ui can display?
fn canDisplayPtr(ptr: std.builtin.Type.Pointer) bool {
    return switch (@typeInfo(ptr.child)) {
        .bool, .int, .float, .pointer, .array, .@"struct", .optional, .@"enum", .@"union" => true,
        else => false,
    };
}

/// Display a struct and allow the user to view and/or edit the fields.
///
/// If the struct is being displayed, returns a pointer to a BoxWidget
/// (which must be deinit()-ed), otherwise returns null.
//
/// field_name: The name of the field holding the struct.
/// field_value_ptr: A pointer to the struct
/// depth: How many nested levels of structs to display. A depth of 0 will only display this struct's fields.
/// options: A tuple of StructOptions(T) of .{} to use default options.
/// al: If adding your own, pass in an alignment to be shared between the struct display and your own widgets,
///     otherwise pass null.
///
/// The returned BoxWidget be used to add custom display fields or additional widgets to the struct's display.
///
/// NOTE:
/// Any modified text fields are dynamically allocated. These are cleaned up during Window.deinit()
/// If a string should not be automatically cleaned up (i.e will be cleaned up by a struct's deinit() method),
/// remove the string from struct_ui.string map prior to the Window.deinit() being called.
///
/// The displayStringBuf() function can be used as an alternative to display strings with a user-supplied buffer.
pub fn displayStruct(
    src: std.builtin.SourceLocation,
    field_name: ?[]const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: ?*dvui.Alignment,
) ?*dvui.BoxWidget {
    validateFieldPtrType(field_name, &.{.@"struct"}, "displayStruct", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name orelse "null", field_option, .standard)) return null;
    {
        const typeinfo = @typeInfo(@TypeOf(options));
        if (typeinfo != .@"struct" or !typeinfo.@"struct".is_tuple) {
            @compileError("The struct_ui.displayStruct() options parameter must be passed as a tuple of StructOptions");
        }
    }
    if (field_option.displayMode() == .none) return null;

    const StructT = @TypeOf(field_value_ptr.*);
    const struct_options: StructOptions(StructT) = findMatchingStructOption(StructT, field_name orelse "", options) orelse .initWithDefaults(.{}, null);

    const vbox: ?*dvui.BoxWidget = displayContainer(src, if (field_name) |name| field_option.displayLabel(name) else null, field_option.defaultExpanded());
    if (vbox != null) {
        var struct_alignment: dvui.Alignment = .init(@src(), depth);
        defer struct_alignment.deinit();
        const alignment = al orelse &struct_alignment;

        inline for (0..struct_options.field_options.values.len) |field_num| {
            const field = comptime @TypeOf(struct_options.field_options).Indexer.keyForIndex(field_num);
            if (struct_options.field_options.get(field)) |child_option_| {
                var child_option = child_option_;
                if (field_option.displayMode() == .constant and child_option.displayMode() != .none) {
                    child_option.markConst();
                }
                var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .id_extra = field_num });
                defer box.deinit();
                displayField(
                    @src(),
                    StructT,
                    @tagName(field),
                    &@field(field_value_ptr, @tagName(field)),
                    depth,
                    child_option,
                    options,
                    alignment,
                );
            }
        }
    }
    return vbox;
}

/// Create and expander to display a container field and indent the container's fields.
/// can be used for the custom display of structs and unions.
pub fn displayContainer(src: std.builtin.SourceLocation, field_name: ?[]const u8, default_expanded: bool) ?*dvui.BoxWidget {
    var vbox: ?*dvui.BoxWidget = null;
    if (field_name == null or dvui.expander(
        src,
        field_name.?,
        .{ .default_expanded = default_expanded },
        .{ .expand = .horizontal },
    )) {
        // Use src again in case exoander is not created.
        vbox = dvui.box(src, .{ .dir = .vertical }, .{
            .expand = .horizontal,
            .border = if (field_name != null) .{ .x = 1 } else null,
            .background = true,
            .margin = if (field_name != null) .{ .x = 12 } else null,
            .id_extra = 1,
        });
    }
    return vbox;
}

/// Create a default value for a field from either default field initialization values or from struct_options
pub fn defaultValue(T: type, ContainerT: type, comptime field_name: []const u8, struct_options: anytype) ?T {
    // If the containing struct has a default value, get the field's default value from
    // the corresponding field within the struct's default value.
    inline for (struct_options) |option| {
        if (@TypeOf(option).StructT == ContainerT and @typeInfo(ContainerT) == .@"struct") {
            if (option.default_value) |default_value| {
                if (@typeInfo(@FieldType(ContainerT, field_name)) == .optional) {
                    if (@field(default_value, field_name) != null) {
                        return @field(default_value, field_name);
                    }
                } else {
                    return @field(default_value, field_name);
                }
            }
        }
    }

    if (T == []u8 or T == []const u8) {
        return "";
    }

    switch (@typeInfo(T)) {
        inline .bool => return false,
        inline .int => return 0,
        inline .float => return 0.0,
        inline .@"struct" => |si| {
            comptime var default_found = false;
            inline for (struct_options) |opt| {
                if (@TypeOf(opt).StructT == T) {
                    default_found = true;
                    return opt.default_value;
                }
            }

            if (!default_found) {
                inline for (si.fields) |field| {
                    if (field.defaultValue() == null) {
                        // The struct can't be default initialized and no struct_options were supplied for this type.
                        return null;
                    }
                }
            }
            return .{};
        },
        inline .@"union" => {
            inline for (struct_options) |opt| {
                if (@TypeOf(opt).StructT == T) {
                    return opt.default_value;
                }
            }
            return null;
        },

        inline .@"enum" => |e| return @enumFromInt(e.fields[0].value),
        inline .void => return {},
        inline else => return null,
    }
}
/// Return true if the field_option is valid for this type of field.
pub fn validFieldOptionsType(field_name: []const u8, field_option: FieldOptions, required_tag: @typeInfo(FieldOptions).@"union".tag_type.?) bool {
    if (field_option != required_tag) {
        log.debug("Field {s} has FieldOption type {s} but needs {s}. Field will not be displayed\n", .{
            field_name,
            @tagName(field_option),
            @tagName(required_tag),
        });
        return false;
    }
    return true;
}

/// Validate if the @typeInfo() of the passed in field_value_ptr
/// is in the set of `required_types`
pub fn validateFieldPtrType(
    field_name: ?[]const u8,
    comptime required_types: []const std.builtin.TypeId,
    comptime caller: []const u8,
    comptime ptr_type: type,
) void {
    const type_info = @typeInfo(ptr_type);
    switch (type_info) {
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    inline for (required_types) |required_t| {
                        if (@typeInfo(ptr.child) == required_t) {
                            return;
                        }
                    }
                },
                else => {},
            }
        },
        else => {},
    }
    if (field_name) |field_name_| {
        @compileError(std.fmt.comptimePrint(
            "Cannot display field {s}. {s} requires a pointer to a {s}, but received a {s} to a {s}.",
            .{ field_name_, caller, requiredTypesToString(required_types), @tagName(type_info), @typeName(ptr_type) },
        ));
    } else {
        @compileError(std.fmt.comptimePrint(
            "{s} requires a pointer to a {s}, but received a {s} to a {s}.",
            .{ caller, requiredTypesToString(required_types), @tagName(type_info), @typeName(ptr_type) },
        ));
    }
}

pub fn requiredTypesToString(comptime required_types: []const std.builtin.TypeId) []const u8 {
    var result: [:0]const u8 = "";
    inline for (required_types, 0..) |required_type, i| {
        result = result ++ @tagName(required_type) ++ if (i < required_types.len - 1) ", " else "";
    }
    return result;
}

/// Validate is a pointer to a slice
pub fn validateFieldPtrTypeSlice(field_name: []const u8, comptime caller: []const u8, comptime ptr_type: type) void {
    switch (@typeInfo(ptr_type)) {
        .pointer => |p1| {
            switch (@typeInfo(p1.child)) {
                .pointer => |ptr| {
                    if (ptr.size == .slice)
                        return;
                },
                else => {},
            }
        },
        else => {},
    }
    @compileError(std.fmt.comptimePrint(
        "Field {s} cannot be displayed. {s} requires a pointer to a slice, but received a {s}.",
        .{ field_name, caller, @typeName(ptr_type) },
    ));
}

/// Validate is a pointer to a u8 slice.
pub fn validateFieldPtrTypeString(field_name: ?[]const u8, comptime caller: []const u8, comptime ptr_type: type) void {
    switch (@typeInfo(ptr_type)) {
        .pointer => |p| {
            switch (@typeInfo(p.child)) {
                .pointer => |ptr| {
                    if (ptr.size == .slice and ptr.child == u8)
                        return;
                },
                else => {},
            }
        },
        else => {},
    }
    @compileError(std.fmt.comptimePrint(
        "Field {s} cannot be displayed. {s} requires a pointer to a []u8 or []const u8, but received a {s}.",
        .{ field_name orelse "", caller, @typeName(ptr_type) },
    ));
}

/// Returns the option from the passed in options tuple for type T.
pub fn findMatchingStructOption(T: type, field_name: []const u8, struct_options: anytype) ?StructOptions(T) {
    inline for (struct_options) |struct_option| {
        if (@TypeOf(struct_option).StructT == T) {
            // Check if these options are for a specific field.
            if (struct_option.for_field_name) |for_name| {
                if (std.mem.eql(u8, field_name, for_name)) {
                    return struct_option;
                }
            } else {
                return struct_option;
            }
        }
    }
    return null;
}

/// Stores all strings currently allocated by struct_ui.
/// K: a pointer to the string field.
/// V: The string slice.
pub var string_map: std.AutoHashMapUnmanaged(*const []const u8, []const u8) = .empty;

/// Returns a 'gpa' backing type with required allocator.
pub fn stringBackingAllocator() StringBackingType {
    return .{ .gpa = defaults.string_allocator orelse dvui.currentWindow().gpa };
}

/// Free any strings allocated by struct_ui.
///
/// `gpa` must be the same allocator as passed to dvui.Window.init().
pub fn deinit(gpa: std.mem.Allocator) void {
    var itr = string_map.iterator();
    while (itr.next()) |entry| {
        if (defaults.string_allocator) |string_alloc| {
            string_alloc.free(entry.value_ptr.*);
        } else {
            gpa.free(entry.value_ptr.*);
        }
    }
    string_map.clearAndFree(gpa);
}

/// This used to test the various comptime error messages.
/// There is currently no good way to test these messages, except to uncomment as required.
pub fn testCompileErrors() void {
    //const sui = dvui.struct_ui;
    //var al: dvui.Alignment = .init(@src(), 0);
    //defer al.deinit();
    //var test_enum: enum { one } = .one;
    //sui.numberFieldWidget(@src(), "enum", &test_enum, .{}, &al);
    //sui.displayNumber("enum", &test_enum, .{ .number = .{} }, &al);
    //sui.textFieldWidget(@src(), "enum", &test_enum, .{}, &al);
    //sui.displayString("enum", &test_enum, .{ .text = .{} }, &al);
    //sui.unionFieldWidget(@src(), "enum", &test_enum, .{ .standard = .{} });
    //sui.displayUnion("enum", &test_enum, 1, .{ .standard = .{} }, .{});

    //const UN = union {
    //    a: i32,
    //    b: u32,
    //};
    //    const un: UN = .{ .a = 2 };
    //sui.unionFieldWidget(@src(), "non-tagged", &un, .{ .standard = .{} });
    //sui.displayUnion("non-tagged", &un, 1, .{ .standard = .{} }, .{});

    //sui.boolFieldWidget(@src(), "union", &un, .{}, &al);
    //sui.displayBool("union", &un, .{ .standard = .{} }, &al);

    //_ = sui.optionalFieldWidget(@src(), "union", &un, .{ .standard = .{} }, &al);
    //sui.displayOptional("union", &un, 1, .{ .standard = .{} }, .{}, &al, null);

    //sui.displayArray("union", &un, 1, .{ .standard = .{} }, .{});
    //sui.displaySlice("union", &un, 1, .{ .standard = .{} }, .{});
    //if (sui.displayStruct("union", &un, 1, .default, .{}, null)) |box| box.deinit();
    //sui.displayUnion("struct", &test_enum, 1, .default, .{});
    // const ptr: *anyopaque = undefined;
    //sui.displayField("struct", test_enum, 1, .default, .{}, &al);
    // sui.displayField("struct", ptr, 1, .default, .{}, &al); // Should not error
    // sui.displayField("struct", &ptr, 1, .default, .{}, &al); // Should not error
}

test {
    @import("std").testing.refAllDecls(@This());
}
const std = @import("std");
const dvui = @import("dvui.zig");
