const std = @import("std");
const dvui = @import("dvui.zig");

// TODO: Log an error, or disable checkbox if optional doesn't have a default.
// Can't currently control display order or omit options. Maybe the normal init shouldn't do a default init first
// and then need to check which fields are set with values, which I beleive is possible with the EnumArray.

// Look at decreasing depth for unions as well. Currently it can show the union slector, but not fields beneath,
// which I assume is depth related.
// END OF TODO

/// Field options control whether and how fields are displayed.
/// Field can be hidden in two ways:
/// 1) Setting display = .none,
/// 2) Omitting the FieldOption from the StructOptions passed to displayStruct.
///
pub const FieldOptions = union(enum) {
    /// Control if the field should be displayed and if it is editable.
    const DisplayMode = enum { none, read_only, read_write };
    standard: StandardFieldOptions,
    number: NumberFieldOptions,
    text: TextFieldOptions,

    pub const default: FieldOptions = .{ .standard = .{} };

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
pub fn StructOptions(Struct: type) type {
    switch (@typeInfo(Struct)) {
        .@"struct", .@"union" => {},
        else => @compileError(std.fmt.comptimePrint("StructOptions(T) requires Struct or Union, but received a {s}.", .{@typeName(Struct)})),
    }
    return struct {
        pub const StructOptionsT = std.EnumMap(std.meta.FieldEnum(StructT), FieldOptions);
        const Self = @This();
        pub const StructT = Struct;
        options: StructOptionsT, // use .init() or .defaultDefaults()
        default_value: ?StructT = null,

        /// Optionally provide overrides for some fields.
        /// Used as .init(&. { . { .a = . { .min_value = 10}}})
        pub fn init(
            options: std.enums.EnumFieldStruct(
                StructOptionsT.Key,
                ?StructOptionsT.Value,
                @as(?StructOptionsT.Value, null),
            ),
            comptime default_value: ?StructT,
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

        /// Inititialize struct options with default options.
        /// Use `default_value` as the initializer if an struct needs to be created.
        /// e.g. If the struct is a Union member, or is an Optional.
        pub fn initDefaults(comptime default_value: ?StructT) Self {
            comptime var defaults: StructOptionsT = .{};
            comptime {
                for (0..defaults.values.len) |i| {
                    const key = StructOptionsT.Indexer.keyForIndex(i);
                    const field_name = @tagName(key);
                    defaults.put(key, defaultFieldOption(@FieldType(StructT, field_name)));
                }
            }
            return .{
                .options = defaults,
                .default_value = default_value,
            };
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
                // For arrays, pointers and optionals, options are set for the child type.
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
    field_value_ptr: anytype,
    opt: NumberFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(&.{ .float, .int }, "numberFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    const T = @TypeOf(field_value_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display == .read_only;

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
                    .value = field_value_ptr,
                }, .{});
                if (maybe_num.value == .Valid) {
                    field_value_ptr.* = maybe_num.value.Valid;
                }
            }
            dvui.label(@src(), "{d}", .{field_value_ptr.*}, .{});
        },
        .slider => {
            var box = dvui.box(src, .{ .dir = .horizontal }, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{field_name}, .{});
            if (!read_only) {
                var percent = opt.toNormalizedPercent(T, field_value_ptr.*);
                _ = dvui.slider(@src(), .horizontal, &percent, .{
                    .expand = .horizontal,
                    .min_size_content = .{ .w = 100, .h = 20 },
                });
                field_value_ptr.* = opt.normalizedPercentToNum(T, percent);
            }
            dvui.label(@src(), "{d}", .{field_value_ptr.*}, .{});
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
    validateFieldPtrType(&.{.@"enum"}, "enumFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    const T = @TypeOf(field_value_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display == .read_only;

    // TODO: Look into if this box is realyl needed? Can we not use the parrent widget instead?
    var box = dvui.box(src, .{ .dir = .horizontal }, .{ .expand = .horizontal });
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        dvui.label(@src(), "{s}", .{@tagName(field_value_ptr.*)}, .{});
    } else {
        const choices = std.meta.FieldEnum(T);
        const entries = std.meta.fieldNames(choices);
        var choice: usize = @intFromEnum(std.meta.stringToEnum(std.meta.FieldEnum(T), @tagName(field_value_ptr.*)).?);
        _ = dvui.dropdown(@src(), entries, &choice, .{});

        field_value_ptr.* = std.meta.stringToEnum(T, @tagName(@as(std.meta.FieldEnum(T), @enumFromInt(choice)))).?;
    }
}

pub fn boolFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: StandardFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(&.{.bool}, "boolFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display == .read_only;

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
    var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        dvui.label(@src(), "{}", .{field_value_ptr.*}, .{});
    } else {
        const entries = .{ "false", "true" };
        var choice: usize = if (field_value_ptr.* == false) 0 else 1;
        _ = dvui.dropdown(@src(), &entries, &choice, .{});
        field_value_ptr.* = if (choice == 0) false else true;
    }
}

/// Ooptions for displaying a text field.
pub const TextFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,

    label: ?[]const u8 = null,
};

/// Display slices and/or arrays of u8 and const u8.
/// If a slice, the slice will be assigned to point to the internal heap allocated
/// string of the text widget. If the struct has a lifetime greater than the text entry widget's window
/// then the struct's strings should be duplicated before the windows is disposed.
pub fn textFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: TextFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrTypeString("textFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    var box = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer box.deinit();

    var read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display == .read_only;
    if (opt.display == .read_write and read_only) {
        // Note all string arrays are currently treated as read-only, even if they are var.
        // It would be possible to support in-place editing, preferrably by implementing a new display option.
        dvui.log.debug("struct_ui: field {s} display option is set to read_write for read_only string or an array. Displaying as read_only.", .{field_name});
        read_only = true;
    }

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
    if (!read_only) {
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());

        const text_box = dvui.textEntry(@src(), .{}, .{});
        defer text_box.deinit();
        if (!text_box.text_changed and !std.mem.eql(u8, text_box.getText(), field_value_ptr.*)) {
            text_box.textSet(field_value_ptr.*, false);
        }
        if (!@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) {
            if (text_box.text_changed and !std.mem.eql(u8, text_box.getText(), field_value_ptr.*)) {
                field_value_ptr.* = text_box.getText();
            }
        }
    } else {
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(box.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(box.data().id, hbox_aligned.data());

        dvui.label(@src(), "{s}", .{field_value_ptr.*}, .{});
    }
}

/// Returns the enum type associated with a tagged union
/// validates that FieldPtrType points to a tagged union.
pub fn UnionTagType(FieldPtrType: type) type {
    validateFieldPtrType(&.{.@"union"}, "unionFieldWidget", FieldPtrType);
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
    _ = field_name;
    const T = @TypeOf(field_value_ptr.*);
    if (@typeInfo(T).@"union".tag_type == null) {}

    if (opt.displayMode() == .none) {
        return field_value_ptr.*;
    }
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.displayMode() == .read_only;

    var box = dvui.box(src, .{ .dir = .vertical }, .{});
    defer box.deinit();

    const entries = std.meta.fields(T);
    var choice = std.meta.activeTag(field_value_ptr.*);
    {
        var hbox = dvui.box(@src(), .{}, .{});
        defer hbox.deinit();
        if (read_only) {
            _ = dvui.radio(@src(), true, @tagName(choice), .{});
        } else {
            inline for (entries, 0..) |entry, i| {
                if (dvui.radio(@src(), choice == std.meta.stringToEnum(@TypeOf(choice), entry.name), entry.name, .{ .id_extra = i })) {
                    if (!read_only) {
                        choice = std.meta.stringToEnum(@TypeOf(choice), entry.name).?; // This should never fail.
                    }
                }
            }
        }
    }
    return choice;
}

pub fn optionalFieldWidget(
    comptime src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opts: FieldOptions,
    alignment: *dvui.Alignment,
) bool {
    validateFieldPtrType(&.{.optional}, "optionalFieldWidget", @TypeOf(field_value_ptr));

    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opts.displayMode() == .read_only;

    var choice: usize = if (field_value_ptr.* == null) 0 else 1; // 0 = Null, 1 = Not Null

    var hbox = dvui.box(src, .{ .dir = .horizontal }, .{});
    defer hbox.deinit();
    dvui.label(@src(), "{s}?", .{opts.displayLabel(field_name)}, .{});
    {
        var hbox_aligned = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = alignment.margin(hbox.data().id) });
        defer hbox_aligned.deinit();
        alignment.record(hbox.data().id, hbox_aligned.data());

        if (!read_only) {
            _ = dvui.dropdown(@src(), &.{ "Null", "Not Null" }, &choice, .{});
        } else {
            dvui.labelNoFmt(@src(), if (choice == 0) "Null" else "Not Null", .{}, .{});
        }
    }
    return choice == 1; // Not null
}

/// Display a field within a container.
/// displayField can be used when iterating throgh a list of fields of varying types.
/// it will call the correct display fucntion based on the type of the field.
pub fn displayField(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    if (field_option.displayMode() == .none) return;

    switch (@typeInfo(@TypeOf(field_value_ptr.*))) {
        .int, .float => displayNumber(field_name, field_value_ptr, field_option, al),
        .bool => displayBool(field_name, field_value_ptr, field_option, al),
        .@"enum" => displayEnum(field_name, field_value_ptr, field_option, al),
        .array => |arr| {
            // Array of u8 is only displayed as text if it has a text field option.
            if (arr.child == u8 and field_option == .text) {
                const slice: []const u8 = &field_value_ptr.*; // Arrays can only be shown as const strings.
                displayString(field_name, &slice, field_option, al);
            } else {
                displayArray(field_name, field_value_ptr, depth, field_option, options);
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
        .@"union" => displayUnion(field_name, field_value_ptr, depth, field_option, options),
        .@"struct" => {
            if (depth > 0)
                displayStruct(field_name, field_value_ptr, depth - 1, field_option, options);
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

/// Display numberic fields, ints and floats.
pub fn displayNumber(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(&.{ .int, .float }, "displayEnum", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .number)) return;
    numberFieldWidget(@src(), field_name, field_value_ptr, field_option.number, al);
}

pub fn displayEnum(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(&.{.@"enum"}, "displayEnum", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    enumFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

/// display []u8, []const u8 and arrays of u8 and const u8.
/// Arrays are currently always displayed as read only.
pub fn displayString(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrTypeString("displayString", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .text)) return;
    textFieldWidget(@src(), field_name, field_value_ptr, field_option.text, al);
}

// TODO: Reinstate this to give the user a way to display string fields and supply their own buffer.
//pub fn displayStringBuffer(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) bool {
//    if (!validFieldOptionsType(field_name, field_option, .text)) return;
//    textFieldWidget(@src(), field_name, field_value_ptr, field_option.text, al);
//}

pub fn displayBool(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(&.{.bool}, "displayBool", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    boolFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayArray(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrType(&.{.array}, "displayArray", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (dvui.expander(
        @src(),
        field_option.displayLabel(field_name),
        .{ .default_expanded = true },
        .{ .expand = .horizontal },
    )) {
        var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();
        var alignment: dvui.Alignment = .init(@src(), depth);
        defer alignment.deinit();
        for (field_value_ptr, 0..) |*val, i| {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal, .id_extra = i });
            defer hbox.deinit();

            var field_name_buf: [21]u8 = undefined; // 20 chars = u64 + ':'
            const field_name_str = std.fmt.bufPrint(&field_name_buf, "{d}:", .{i}) catch "#";
            displayField(field_name_str, val, depth, field_option, options, &alignment);
        }
    }
}

pub fn displaySlice(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrTypeSlice("displaySlice", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (dvui.expander(
        @src(),
        field_option.displayLabel(field_name),
        .{ .default_expanded = true },
        .{ .expand = .horizontal },
    )) {
        var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();
        var alignment: dvui.Alignment = .init(@src(), depth);
        defer alignment.deinit();

        for (field_value_ptr.*, 0..) |*val, i| {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
                .id_extra = i,
            });
            defer hbox.deinit();

            var field_name_buf: [21]u8 = undefined; // 20 chars = u64 + ':'
            const field_name_str = std.fmt.bufPrint(&field_name_buf, "{d}:", .{i}) catch "#";
            displayField(field_name_str, val, depth, field_option, options, &alignment);
        }
    }
}

/// Display a union.
/// If the union has Struct or Union members, then StructOptions should be provided
/// for those members with default values. These default values will be ussed to populate
/// the active union value when the user changes selections.
pub fn displayUnion(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrType(&.{.@"union"}, "displayUnion", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (@typeInfo(@TypeOf(field_value_ptr.*)).@"union".tag_type == null) {
        @compileError("Only tagged unions are supported.");
    }
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    const current_choice = std.meta.activeTag(field_value_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() == .read_only;
    if (dvui.expander(
        @src(),
        field_option.displayLabel(field_name),
        .{ .default_expanded = true },
        .{ .expand = .horizontal },
    )) {
        var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();

        const new_choice = unionFieldWidget(@src(), field_name, field_value_ptr, field_option);
        const UnionT = @TypeOf(field_value_ptr.*);
        if (current_choice != new_choice) {
            switch (new_choice) {
                inline else => |choice| {
                    const default_value = defaultValue(
                        @FieldType(UnionT, @tagName(choice)),
                        field_option,
                        options,
                    );
                    if (!read_only) {
                        if (default_value) |default| {
                            field_value_ptr.* = @unionInit(UnionT, @tagName(choice), default);
                        } else {
                            dvui.log.debug(
                                "struct_ui: Union field {s}.{s} cannot be selected as no default value is provided. Field will not be selected.",
                                .{ field_name, @tagName(choice) },
                            );
                            return;
                        }
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
                var alignment: dvui.Alignment = .init(@src(), depth);
                defer alignment.deinit();

                // Will only display if an option exists for this field.
                if (struct_options.options.get(active_tag)) |union_field_option| {
                    displayField(@tagName(active_tag), active, depth, union_field_option, options, &alignment);
                }
            },
        }
    }
}

/// Display an optional
///
/// If the optional is a union or struct, StructOptions should be provided for those
/// types. They will be used as default values for when the user creates a new optional value.
/// Basic types are assigned default value sdepending on their type.
/// It is recommended that users handle optional pointers manually using optionalFieldWidget directly,
/// rather than using this function.
/// Otherwise all pointers for a type will point to a single default value.
pub fn displayOptional(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    validateFieldPtrType(&.{.optional}, "displayOptional", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    const optional = @typeInfo(@TypeOf(field_value_ptr.*)).optional;
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() == .read_only;

    if (optionalFieldWidget(@src(), field_name, field_value_ptr, field_option, al)) {
        if (!read_only) {
            if (field_value_ptr.* == null) {
                field_value_ptr.* = defaultValue(optional.child, field_option, options); // If there is no default value, it will remain null.
            }
        }
        if (field_value_ptr.*) |*val| {
            displayField(field_name, val, depth, field_option, options, al);
        } else {
            dvui.log.debug("struct_ui: Optional field {s} cannot be selected as no default value is provided.", .{field_name});
        }
    } else if (!read_only) {
        field_value_ptr.* = null;
    }
}

pub fn displayPointer(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    validateFieldPtrType(&.{.pointer}, "displayPointer", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    const ptr = @typeInfo(@TypeOf(field_value_ptr.*)).pointer;
    if (ptr.size == .one) {
        displayField(field_name, field_value_ptr.*, depth, field_option, options, al);
    } else if (ptr.size == .slice) {
        displaySlice(field_name, &field_value_ptr.*, depth, field_option, options);
    } else {
        @compileError(std.fmt.comptimePrint("C-style and many item pointers not supported for {s}.{s}\n", .{ @typeName(@TypeOf(field_value_ptr.*)), field_name }));
    }
}

pub fn displayStruct(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrType(&.{.@"struct"}, "displayStruct", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    if (field_option.standard.display == .none) return;

    const StructT = @TypeOf(field_value_ptr.*);
    const struct_options: StructOptions(StructT) = findMatchingStructOption(StructT, options) orelse .initDefaults(null);

    if (field_option.displayMode() == .none) return;

    if (dvui.expander(
        @src(),
        field_option.displayLabel(field_name),
        .{ .default_expanded = true },
        .{ .expand = .horizontal },
    )) {
        var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();
        var alignment: dvui.Alignment = .init(@src(), depth);
        defer alignment.deinit();

        inline for (struct_options.options.values, 0..) |sub_field_option, field_num| {
            var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .id_extra = field_num });
            defer box.deinit();
            const field = comptime @TypeOf(struct_options.options).Indexer.keyForIndex(field_num);

            displayField(
                @tagName(field),
                &@field(field_value_ptr, @tagName(field)),
                depth,
                sub_field_option,
                options,
                &alignment,
            );
        }
    }
}

/// Create a default value for a field from either default field initialization values or from struct_options
pub fn defaultValue(T: type, field_option: FieldOptions, struct_options: anytype) ?T {
    _ = field_option; // TODO: Remove
    // default string values
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
                        @compileError(std.fmt.comptimePrint("field {s} for struct {s} does not support default initialization", .{ field.name, @typeName(T) }));
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
        inline else => return null,
    }
}

pub fn validFieldOptionsType(field_name: []const u8, field_option: FieldOptions, required_tag: @typeInfo(FieldOptions).@"union".tag_type.?) bool {
    if (field_option != required_tag) {
        dvui.log.debug("struct_ui: Field {s} has FieldOption type {s} but needs {s}. Field will not be displayed\n", .{
            field_name,
            @tagName(field_option),
            @tagName(required_tag),
        });
        return false;
    }
    return true;
}

pub fn validateFieldPtrType(comptime required_types: []const std.builtin.TypeId, comptime caller: []const u8, comptime ptr_type: type) void {
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
    @compileError(std.fmt.comptimePrint(
        "{s} requires a pointer to a {s}, but received a {s} to a {s}.",
        .{ caller, requiredTypesToString(required_types), @tagName(type_info), @typeName(ptr_type) },
    ));
}

pub fn requiredTypesToString(comptime required_types: []const std.builtin.TypeId) []const u8 {
    var result: [:0]const u8 = "";
    inline for (required_types, 0..) |required_type, i| {
        result = result ++ @tagName(required_type) ++ if (i < required_types.len - 1) " or " else "";
    }
    return result;
}

pub fn validateFieldPtrTypeSlice(comptime caller: []const u8, comptime ptr_type: type) void {
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
        "{s} requires a pointer to a slice, but received a {s}.",
        .{ caller, @typeName(ptr_type) },
    ));
}

pub fn validateFieldPtrTypeString(comptime caller: []const u8, comptime ptr_type: type) void {
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
        "{s} requires a pointer to a []u8 or []const u8, but received a {s}.",
        .{ caller, @typeName(ptr_type) },
    ));
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

test {
    @import("std").testing.refAllDecls(@This());
}
