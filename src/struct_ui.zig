const std = @import("std");
const dvui = @import("dvui.zig");

const border = dvui.Rect.all(1);

// TODO: Log an error, or disable checkbox if optional doesn't have a default.

// TODO: For pointers and arrays, work out whether FieldOptions are applying to the pointer or the
// children.
// e.g. b: []u16, This should get a NumberFieldOption rather than a standard one, so we know how to display the values.
// Check this is actually happening as expected.
// Can't currently control display order or omit options. Maybe the normal init shouldn't do a default init first
// and then need to check which fields are set with values, which I beleive is possible with the EnumArray.

// Gives types as part of error messages.
// Issue with field option buffer being applied to types and not fields as the
// buffer could be shared between different types and there is no way around that?

/// Field options control whether and how fields are displayed.
/// Field can be hidden in two ways:
/// 1) Setting display = .none,
/// 2) Omitting the FieldOption from the StructOptions passed to displayStruct.
///
/// For slices of u8, use TextFieldOptions to display as text or NUmberFieldOptions to display as number.
/// See the specific FieldOptions type for further details.
pub const FieldOptions = union(enum) {
    /// Control if the field should be displayed and if it is editable.
    const DisplayMode = enum { none, read_only, read_write };
    standard: StandardFieldOptions,
    number: NumberFieldOptions,
    text: TextFieldOptions,

    pub const standard_options: FieldOptions = .{ .standard = .{} };
};

/// Standard field options control the display mode and
/// provide an alternative label.
pub const StandardFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,

    label: ?[]const u8 = null,
};

/// Creates a default set of field options for a struct.
/// An optional default value can be provided, which is used whenever
/// the struct must be created. e.g. from setting an optional.
// TODO: The initialization with overrides doesn't work. pls fix.
pub fn StructOptions(T: type) type {
    switch (@typeInfo(T)) {
        .@"struct", .@"union" => {},
        else => @compileError(std.fmt.comptimePrint("StructUI: StructOptions(T) requires Struct or Union, but received a {s}.", .{@typeName(T)})),
    }
    return struct {
        pub const StructOptionsT = std.EnumMap(std.meta.FieldEnum(T), FieldOptions);
        const Self = @This();
        pub const StructT = T;
        options: StructOptionsT, // use .init() or .defaultDefaults()
        default_value: ?T = null,

        /// Optionally provide overrides for some fields.
        /// Used as .init(&. { . { .a = . { .min_vslue = 10}}})
        pub fn init(
            options: std.enums.EnumFieldStruct(
                StructOptionsT.Key,
                ?StructOptionsT.Value,
                @as(?StructOptionsT.Value, null),
            ),
            comptime default_value: ?T,
        ) Self {
            var self = initDefaults(default_value);
            inline for (0..self.options.values.len) |i| {
                const key = comptime StructOptionsT.Indexer.keyForIndex(i);
                if (@field(options, @tagName(key))) |*v| {
                    self.options.values[i] = v.*;
                }
            }
            return self;
        }

        pub fn initDefaults(comptime default_value: ?T) Self {
            comptime var defaults: StructOptionsT = .{};
            comptime {
                for (0..defaults.values.len) |i| {
                    const key = StructOptionsT.Indexer.keyForIndex(i);
                    const field_name = @tagName(key);
                    defaults.put(key, defaultFieldOption(@FieldType(T, field_name)));
                }
            }
            return .{ .options = defaults, .default_value = default_value };
        }

        // override default options
        pub fn override(self: *Self, options: std.enums.EnumFieldStruct(
            StructOptionsT.Key,
            ?StructOptionsT.Value,
            @as(?StructOptionsT.Value, null),
        )) void {
            inline for (0..self.options.values.len) |i| {
                const key = comptime StructOptionsT.Indexer.keyForIndex(i);
                if (@field(options, @tagName(key))) |*v| {
                    self.options.values[i] = v.*;
                }
            }
        }

        /// Return a default value for a field if not default field has been supplied through
        /// StructOptions.
        pub fn defaultFieldOption(FieldType: type) FieldOptions {
            const result: FieldOptions = switch (@typeInfo(FieldType)) {
                .int, .float => .{ .number = .{} },
                .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
                    .{
                        .text = .{ .display = if (ptr.is_const) .read_only else .read_write },
                    }
                else
                    defaultFieldOption(ptr.child),
                .optional => |opt| defaultFieldOption(opt.child),
                .array => |arr| defaultFieldOption(arr.child),
                else => .{ .standard = .{} },
            };
            return result;
        }
    };
}

/// Controls how numeric fields are displayed.
/// Note that min and max are stored as f64, which can represent
/// all integer values up to an i53/u53.
pub const NumberFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    label: ?[]const u8 = null,

    /// For .read_write, display as either a text entry box or as a slider.
    widget_type: enum { number_entry, slider } = .number_entry,
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
            .int => @intFromFloat(self.min orelse 0),
            .float => @floatCast(self.min orelse 0),
            else => unreachable,
        };
    }

    /// Return a typed copy of the max value
    pub fn maxValue(self: *const NumberFieldOptions, T: type) T {
        return switch (@typeInfo(T)) {
            .int => @intFromFloat(self.max orelse std.math.maxInt(T)),
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
            .float => switch (@typeInfo(@TypeOf(value))) {
                .int => @intFromError(value),
                .float => @floatCast(value),
                else => unreachable,
            },
            else => unreachable,
        };
    }

    /// For slider, convert slider percentage into a number betwen min and max.
    pub fn normalizedPercentToNum(_: *const NumberFieldOptions, normalized_percent: f32, comptime T: type, min: T, max: T) T {
        if (@typeInfo(T) != .int and @typeInfo(T) != .float) @compileError("T is not a number type");
        std.debug.assert(normalized_percent >= 0);
        std.debug.assert(normalized_percent <= 1);
        const range = max - min;

        const result: T = switch (@typeInfo(T)) {
            .int => @intFromFloat(@as(f32, @floatFromInt(min)) + @as(f32, @floatFromInt(range)) * normalized_percent),
            .float => @as(T, min + range * @as(T, @floatCast(normalized_percent))),
            else => unreachable,
        };
        return result;
    }

    /// For slider, convert number to a slider percentage
    pub fn toNormalizedPercent(_: *const NumberFieldOptions, input_num: anytype, min: @TypeOf(input_num), max: @TypeOf(input_num)) f32 {
        const input, const range, const min_f = switch (@typeInfo(@TypeOf(input_num))) {
            .int => .{
                @as(f32, @floatFromInt(if (input_num < min) min else input_num)),
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
    field_ptr: anytype,
    opt: NumberFieldOptions,
    alignment: *dvui.Alignment,
) void {
    if (opt.display == .none) return;
    if (opt.widget_type == .slider) {
        // TODO: Consider making this an error instead of an assert? minValue(T) and maxValue(T) already return 0 if min/max are null.
        std.debug.assert(opt.min != null and opt.max != null); // min and max are required for sliders
    }

    const T = @TypeOf(field_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_ptr)).pointer.is_const;

    switch (@typeInfo(T)) {
        .int => {},
        .float => {},
        else => @compileError(std.fmt.comptimePrint("{s} must be a number type, but is a {s}", .{ field_name, @typeName(T) })),
    }

    switch (opt.widget_type) {
        .number_entry => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});

            var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            if (!read_only) {
                const maybe_num = dvui.textEntryNumber(@src(), T, .{
                    .min = opt.minValue(T),
                    .max = opt.maxValue(T),
                    .value = field_ptr,
                }, .{});
                if (maybe_num.value == .Valid) {
                    field_ptr.* = maybe_num.value.Valid;
                }
            }
            dvui.label(@src(), "{}", .{field_ptr.*}, .{});
        },
        .slider => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{field_name}, .{});

            if (!read_only) {
                var percent = opt.toNormalizedPercent(field_ptr.*, opt.minValue(T), opt.maxValue(T));
                _ = dvui.slider(@src(), .horizontal, &percent, .{
                    .expand = .horizontal,
                    .min_size_content = .{ .w = 100, .h = 20 },
                });
                field_ptr.* = opt.normalizedPercentToNum(percent, T, opt.minValue(T), opt.maxValue(T));
            }
            dvui.label(@src(), "{}", .{field_ptr.*}, .{});
        },
    }
}

pub fn enumFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opt: StandardFieldOptions,
    alignment: *dvui.Alignment,
) void {
    if (opt.display == .none) return;

    const T = @TypeOf(field_ptr.*);
    if (@typeInfo(T) != .@"enum") {
        @compileError(std.fmt.comptimePrint("Field {s} must be an enum, but is a {s}\n", .{ field_name, @typeName(T) }));
    }

    const read_only = @typeInfo(@TypeOf(field_ptr)).pointer.is_const;

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        dvui.label(@src(), "{s}", .{@tagName(field_ptr.*)}, .{});
    } else {
        const choices = std.meta.FieldEnum(T);
        const entries = std.meta.fieldNames(choices);
        var choice: usize = @intFromEnum(std.meta.stringToEnum(std.meta.FieldEnum(T), @tagName(field_ptr.*)).?);
        _ = dvui.dropdown(@src(), entries, &choice, .{});

        field_ptr.* = std.meta.stringToEnum(T, @tagName(@as(std.meta.FieldEnum(T), @enumFromInt(choice)))).?;
    }
}

pub fn boolFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opt: StandardFieldOptions,
    alignment: *dvui.Alignment,
) void {
    const T = @TypeOf(field_ptr.*);
    if (T != bool)
        @compileError(std.fmt.comptimePrint("{s} must be of type bool, but is {s}.", .{ field_name, @typeName(T) }));
    if (opt.display == .none) return;

    const read_only = @typeInfo(@TypeOf(field_ptr)).pointer.is_const;

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        dvui.label(@src(), "{}", .{field_ptr.*}, .{});
    } else {
        const entries = .{ "false", "true" };
        var choice: usize = if (field_ptr.* == false) 0 else 1;
        _ = dvui.dropdown(@src(), &entries, &choice, .{});
        field_ptr.* = if (choice == 0) false else true;
    }
}

/// Display a text field.
/// The optional buffer should be supplied to enable editing on read-only strings, or
/// any time the original struct field should not be used to store new data.
pub const TextFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,

    label: ?[]const u8 = null,
    // TODO: So is this where the user provides their edit buffer?
    buffer: ?[]u8 = null,
};

/// Display slices and/or arrays of u8 and const u8.
pub fn textFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opt: TextFieldOptions,
    alignment: *dvui.Alignment,
) void {
    if (opt.display == .none) return;
    const T = @TypeOf(field_ptr.*);
    if (@TypeOf(field_ptr.*[0]) != u8) {
        @compileError(std.fmt.comptimePrint("{s} must be an array or slice of u8 or const u8, but is a {s}\n", .{ field_name, @typeName(T) }));
    }

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});

    if (opt.buffer) |buf| {
        // If not using the struct field directly to store a value, copy the field value into the buffer
        // in case the struct value has been updated by the user between frames.
        if (buf.ptr != field_ptr.*.ptr) {
            @memcpy(buf[0..field_ptr.*.len], field_ptr.*);
        }
    }
    switch (opt.display) {
        .read_write => {
            const buffer: []u8 = buffer: {
                if (opt.buffer) |buf| {
                    break :buffer buf;
                } else if (@typeInfo(@TypeOf(field_ptr.*)).pointer.is_const) {
                    dvui.log.debug("Must supply a buffer to TextFieldOptions to allow editing of const fields. Field name is {s}", .{field_name});
                    return;
                } else {
                    break :buffer field_ptr.*;
                }
            };

            var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            const text_box = dvui.textEntry(@src(), .{ .text = .{ .buffer = buffer } }, .{});
            defer text_box.deinit();
            if (!@typeInfo(@TypeOf(field_ptr)).pointer.is_const) {
                if (text_box.text_changed and opt.buffer != null) {
                    field_ptr.* = buffer;
                }
            }
        },
        .read_only => {
            dvui.label(@src(), " : {s}", .{field_ptr.*}, .{});
        },
        .none => unreachable, // Handled above.
    }
}

pub fn unionFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opt: FieldOptions,
    alignment: *dvui.Alignment,
) @typeInfo(@TypeOf(field_ptr.*)).@"union".tag_type.? {
    _ = alignment;
    switch (opt) {
        inline else => |field_option| if (field_option.display == .none) {
            return field_ptr.*;
        },
    }
    const T = @TypeOf(field_ptr.*);
    const valid_type: bool = valid: switch (@typeInfo(T)) {
        .@"union" => |u| {
            if (u.tag_type != null) {
                break :valid true;
            }
        },
        else => break :valid false,
    };
    if (!valid_type) {
        @compileError(std.fmt.comptimePrint("{s} must be a tagged union field, but is a {s}\n", .{ field_name, @typeName(T) }));
    }

    var box = dvui.box(src, .{ .dir = .vertical }, .{});
    defer box.deinit();

    const entries = std.meta.fields(T);
    var choice = std.meta.activeTag(field_ptr.*);
    {
        var hbox = dvui.box(@src(), .{}, .{});
        defer hbox.deinit();
        //const label = opt.label_override orelse field_name; // TODO:
        const label = field_name;
        if (label.len != 0) {
            dvui.label(@src(), "{s}", .{label}, .{});
        }
        inline for (entries, 0..) |entry, i| {
            if (dvui.radio(@src(), choice == std.meta.stringToEnum(@TypeOf(choice), entry.name), entry.name, .{ .id_extra = i })) {
                choice = std.meta.stringToEnum(@TypeOf(choice), entry.name).?; // This should never fail.
            }
        }
    }
    return choice;
}

pub fn optionalFieldWidget(
    comptime src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opts: FieldOptions,
    alignment: *dvui.Alignment,
) bool {
    _ = alignment; // TODO ?
    const T = @TypeOf(field_ptr.*);
    if (@typeInfo(T) != .optional) {
        @compileError(std.fmt.comptimePrint("{s} must be an optional field, but is a {s}\n", .{ field_name, @typeName(T) }));
    }

    const box = dvui.box(src, .{ .dir = .vertical }, .{});
    defer box.deinit();
    var checkbox_state: bool = field_ptr.* != null;
    {
        const display_name = switch (opts) {
            inline else => |opt| opt.label orelse field_name,
        };
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        dvui.label(@src(), "{s}?", .{display_name}, .{});
        _ = dvui.checkbox(@src(), &checkbox_state, null, .{});
    }

    return checkbox_state;
}

/// Display a field within a container.
pub fn displayField(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    switch (@typeInfo(@TypeOf(field_value_ptr.*))) {
        .int, .float => displayNumber(field_name, field_value_ptr, field_option, al),
        .bool => displayBool(field_name, field_value_ptr, field_option, al),
        .@"enum" => displayEnum(field_name, field_value_ptr, field_option, al),
        .array => |arr| {
            // Array of u8 is only displayed as text if it has a text field option.
            if (arr.child == u8 and field_option == .text) {
                const slice: []u8 = &field_value_ptr.*;
                displayString(field_name, &slice, field_option, al);
            } else {
                displayArray(field_name, field_value_ptr, depth, field_option, options, al);
            }
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8 and field_option == .text) {
                displayString(field_name, field_value_ptr, field_option, al);
            } else {
                displayPointer(field_name, field_value_ptr, depth, field_option, options, al);
            }
        },
        .optional => {
            displayOptional(field_name, field_value_ptr, depth, field_option, options, al);
        },
        .@"union" => displayUnion(field_name, field_value_ptr, depth, field_option, options, al),
        .@"struct" => {
            if (depth > 0)
                displayStruct(field_name, field_value_ptr, depth - 1, field_option, options, al);
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
}

pub fn displayNumber(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    if (!validFieldOptionsType(field_name, field_option, .number)) return;
    numberFieldWidget(@src(), field_name, field_value_ptr, field_option.number, al);
}

pub fn displayEnum(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(.@"enum:", "displayEnum", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    enumFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayString(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    if (!validFieldOptionsType(field_name, field_option, .text)) return;
    textFieldWidget(@src(), field_name, field_value_ptr, field_option.text, al);
}

pub fn displayBool(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(.bool, "displayBool", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    boolFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayArray(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    if (dvui.expander(@src(), field_name, .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();

        for (field_value_ptr, 0..) |*val, i| {
            // TODO: Aligmmnent
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = i });
            defer hbox.deinit();

            var field_name_buf: [20]u8 = undefined; // 20 chars = u64
            const field_name_str = std.fmt.bufPrint(&field_name_buf, "{d}", .{i}) catch "#";
            displayField(field_name_str, val, depth, field_option, options, al);
        }
    }
}

pub fn displaySlice(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    if (dvui.expander(@src(), field_name, .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();

        for (field_value_ptr.*, 0..) |*val, i| {
            // TODO: Aligmmnent

            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = i });
            defer hbox.deinit();

            var field_name_buf: [20]u8 = undefined; // 20 chars = u64
            const field_name_str = std.fmt.bufPrint(&field_name_buf, "{d}", .{i}) catch "#";
            displayField(field_name_str, val, depth, field_option, options, al);
        }
    }
}

pub fn displayUnion(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    validateFieldPtrType(.@"union", "displayUnion", @TypeOf(field_value_ptr));
    const current_choice = std.meta.activeTag(field_value_ptr.*);
    var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .vertical,
        .border = .{ .x = 1 },
        .background = true,
        .margin = .{ .w = 12, .x = 12 },
    });
    defer vbox.deinit();

    const new_choice = unionFieldWidget(@src(), field_name, field_value_ptr, field_option, al);
    const UnionT = @TypeOf(field_value_ptr.*);
    if (current_choice != new_choice) {
        switch (new_choice) {
            inline else => |choice| {
                const default_value = defaultValue(
                    @FieldType(UnionT, @tagName(choice)),
                    field_option,
                    options,
                );
                if (default_value) |default| {
                    field_value_ptr.* = @unionInit(UnionT, @tagName(choice), default);
                } else {
                    dvui.log.debug(
                        "StructUI: Union field {s}.{s} cannot be selected as no default value is provided. Field will not be selected.",
                        .{ field_name, @tagName(choice) },
                    );
                    return;
                }
            },
        }
    }
    switch (field_value_ptr.*) {
        inline else => |*active, active_tag| {
            // Create the hbox so each tag gets a unique @src() to prevent accidentally sharing widgets between tags.
            const hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = @intFromEnum(active_tag) });
            defer hbox.deinit();
            const struct_options: StructOptions(UnionT) = findMatchingStructOption(UnionT, options) orelse .initDefaults(null);
            // Will only display if an option exists for this field.
            if (struct_options.options.get(active_tag)) |union_field_option| {
                displayField(@tagName(active_tag), active, depth, union_field_option, options, al);
            }
        },
    }
}

pub fn displayOptional(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    validateFieldPtrType(.optional, "displayOptional", @TypeOf(field_value_ptr));
    const optional = @typeInfo(@TypeOf(field_value_ptr.*)).optional;

    if (optionalFieldWidget(@src(), field_name, field_value_ptr, field_option, al)) {
        if (field_value_ptr.* == null) {
            field_value_ptr.* = defaultValue(optional.child, field_option, options); // If there is no default value, it will remain null.
        }
        if (field_value_ptr.*) |*val| {
            displayField(field_name, val, depth, field_option, options, al);
        }
    } else {
        field_value_ptr.* = null;
    }

    if (field_value_ptr.* == null) {
        dvui.label(@src(), "{s} is null", .{field_name}, .{});
    }
}

pub fn displayPointer(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    validateFieldPtrType(.pointer, "displayPointer", @TypeOf(field_value_ptr));

    const ptr = @typeInfo(@TypeOf(field_value_ptr.*)).pointer;
    if (ptr.size == .one) {
        displayField(field_name, field_value_ptr.*, depth, field_option, options, al);
    } else if (ptr.size == .slice) {
        displaySlice(field_name, &field_value_ptr.*, depth, field_option, options, al);
    } else {
        @compileError(std.fmt.comptimePrint("C-style and many item pointers not supported for {s}.{s}\n", .{ @typeName(@TypeOf(field_value_ptr.*)), field_name }));
    }
}

pub fn displayStruct(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    validateFieldPtrType(.@"struct", "displayStruct", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    if (field_option.standard.display == .none) return;

    const StructT = @TypeOf(field_value_ptr.*);
    const struct_options: StructOptions(StructT) = findMatchingStructOption(StructT, options) orelse .initDefaults(null);

    if (dvui.expander(@src(), field_name, .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();

        inline for (struct_options.options.values, 0..) |sub_field_option, field_num| {
            var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .id_extra = field_num });
            defer box.deinit();

            const field = comptime @TypeOf(struct_options.options).Indexer.keyForIndex(field_num);
            displayField(@tagName(field), &@field(field_value_ptr, @tagName(field)), depth, sub_field_option, options, al);
        }
    }
}

/// Supply a default value for a field from supplied from either default field initialization values or from struct_options
pub fn defaultValue(T: type, field_option: FieldOptions, struct_options: anytype) ?T { // TODO: Field is not anytype
    if (T == []u8 or T == []const u8) {
        if (field_option.text.buffer) |buf| {
            return buf;
        }
    }
    switch (@typeInfo(T)) {
        inline .bool => return false,
        inline .int => return 0,
        inline .float => return 0.0,
        inline .@"struct" => |si| {
            comptime var default_found = false;
            inline for (struct_options) |opt| {
                if (@TypeOf(opt).StructT == T) { //} and opt.default_value != null) {
                    default_found = true;
                    return opt.default_value;
                }
            }
            if (!default_found) {
                // TODO: This will just return null now and do a runtime debug message.
                inline for (si.fields) |field| {
                    if (field.defaultValue() == null) {
                        @compileError(std.fmt.comptimePrint("field {s} for struct {s} does not support default initialization", .{ field.name, @typeName(T) }));
                    }
                }
            }
            return .{};
        },
        inline .@"union" => |_| {
            inline for (struct_options) |opt| {
                if (@TypeOf(opt).StructT == T) {
                    return opt.default_value;
                }
            }
            return null;
        },

        inline .@"enum" => |e| return @enumFromInt(e.fields[0].value),
        inline else => return null,
    }
}

pub fn validFieldOptionsType(field_name: []const u8, field_option: FieldOptions, required_tag: @typeInfo(FieldOptions).@"union".tag_type.?) bool {
    if (field_option != required_tag) {
        dvui.log.debug("StructUI: Field {s} has FieldOption type {s} but needs {s}. Field will not be displayed\n", .{
            field_name,
            @tagName(field_option),
            @tagName(required_tag),
        });
        return false;
    }
    return true;
}

pub fn validateFieldPtrType(comptime required_type: std.builtin.TypeId, comptime caller: []const u8, comptime ptr_type: type) void {
    const type_info = @typeInfo(ptr_type);
    switch (type_info) {
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    if (@typeInfo(ptr.child) == required_type) {
                        return;
                    }
                },
                else => {}, // Fallthrough
            }
        },
        else => {}, // Fallthrough
    }
    @compileError(std.fmt.comptimePrint(
        "{s} requires a pointer to a {s}, but received a {s} for {s}.",
        .{ caller, @tagName(required_type), @tagName(type_info), @typeName(ptr_type) },
    ));
}

test {
    @import("std").testing.refAllDecls(@This());
}

/// Returns the option from the passed in options tuple for type T.
pub fn findMatchingStructOption(T: type, struct_options: anytype) ?StructOptions(T) {
    inline for (struct_options) |struct_option| {
        if (@TypeOf(struct_option).StructT == T) {
            return struct_option;
        }
    }
    return null;
}
