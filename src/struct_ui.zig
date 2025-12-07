//! A group of functions for displaying and editing values in structs
//!
//! The main structs and functions are:
//! fn displayStruct() which can be used to recursively display and/or edit all values in a struct.
//! union FieldOptions are used to control how each field is displayed or edited.
//! fn StructOptions(T) generates a set of FieldOptions for a struct.
//!
//! string_map holds any heap-allocated memory created when strings are modified.
//! These are automatically cleaned up during Window.deinit().

// By default struct_ui will use the gpa passed to the dvui window.
// If you want to use a different allocator, you can set it here.
pub var string_allocator: ?std.mem.Allocator = null;

/// Field options control whether and how fields are displayed.
///
/// Use TextFieldOptions for any array or slice of u8 you want ot display as a string.
/// Use NumberFieldOptions for any numbers, allowing setting of min and max ranges and other options
/// Use StandardFieldOptions (.default) for all other fields.
///
/// All FieldOptions types must provide:
/// - display: DisplayMode
/// - label: ?[]const u8
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

    pub fn labelSet(self: *FieldOptions, field_label: []const u8) void {
        switch (self.*) {
            inline else => |*fo| fo.label = field_label,
        }
    }
};

/// Standard field options allow control of the display mode and
/// option to provide an alternative label.
/// All FieldOption types must support the display and label fields.
pub const StandardFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,

    label: ?[]const u8 = null,
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
        pub const StructOptionsT = std.EnumMap(std.meta.FieldEnum(StructT), FieldOptions);
        const Self = @This();
        // Type of struct or union these options belong to
        pub const StructT = Struct;
        // display options for each field to be displayed
        field_options: StructOptionsT,
        // A default value to be used whenever an instance of this type is created
        default_value: ?StructT = null,

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

        /// Return a default value for a field if not default field has been supplied through
        /// StructOptions.
        pub fn defaultFieldOption(FieldType: type) FieldOptions {
            return switch (@typeInfo(FieldType)) {
                .int, .float => .{ .number = .{} },
                // For arrays, pointers and optionals, field_options are set for the child type.
                .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
                    .{
                        .text = .{ .display = if (ptr.is_const or ptr.sentinel_ptr != null) .read_only else .read_write },
                    }
                else
                    defaultFieldOption(ptr.child),
                .optional => |opt| defaultFieldOption(opt.child),
                .array => |arr| defaultFieldOption(arr.child),
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
            .float => switch (@typeInfo(@TypeOf(value))) {
                .int => @intFromError(value),
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
    comptime src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: NumberFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(null, &.{ .float, .int }, "numberFieldWidget", @TypeOf(field_value_ptr));
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
                    .show_min_max = opt.min != null and opt.max != null,
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
            dvui.label(@src(), "{d}", .{field_value_ptr.*}, .{});
        },
    }
}

pub fn enumFieldWidget(
    comptime src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: StandardFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(null, &.{.@"enum"}, "enumFieldWidget", @TypeOf(field_value_ptr));
    if (opt.display == .none) return;

    const T = @TypeOf(field_value_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or opt.display == .read_only;

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
    comptime src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opt: StandardFieldOptions,
    alignment: *dvui.Alignment,
) void {
    validateFieldPtrType(null, &.{.bool}, "boolFieldWidget", @TypeOf(field_value_ptr));
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

/// Options for displaying a text field.
pub const TextFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    label: ?[]const u8 = null,

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
    comptime src: std.builtin.SourceLocation,
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

    var read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or
        opt.display == .read_only or
        sentinel_terminated;

    if (opt.display == .read_write and read_only) {
        // Note all string arrays are currently treated as read-only, even if they are var.
        // It would be possible to support in-place editing, preferably by implementing a new display option.
        dvui.log.debug("struct_ui: field {s} display option is set to read_write for read_only string or an array. Displaying as read_only.", .{field_name});
        read_only = true;
    } else if (opt.display == .read_write and sentinel_terminated) {
        // Sentinel terminated strings cannot be edited.
        // Would require keeping 2 string maps, for sentinel vs non-sentinel strings.
        dvui.log.debug("struct_ui: field {s} display option is set to read_write for sentinel terminated string or an array. Displaying as read_only.", .{field_name});
        read_only = true;
    }

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
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

        const text_box = dvui.textEntry(@src(), if (backing == .buffer) .{ .text = .{ .buffer = backing.buffer } } else .{}, .{});
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

        dvui.label(@src(), "{s}", .{field_value_ptr.*}, .{});
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
    comptime src: std.builtin.SourceLocation,
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
            dvui.labelNoFmt(@src(), @tagName(active_tag), .{}, .{});
        } else {
            if (dvui.dropdown(@src(), choice_names, &active_choice_num, .{})) {
                active_tag = std.meta.stringToEnum(@TypeOf(active_tag), choice_names[active_choice_num]).?; // This should never fail.
            }
        }
    }
    return active_tag;
}

pub fn optionalFieldWidget(
    comptime src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_value_ptr: anytype,
    opts: FieldOptions,
    alignment: *dvui.Alignment,
) bool {
    validateFieldPtrType(null, &.{.optional}, "optionalFieldWidget", @TypeOf(field_value_ptr));

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
/// displayField can be used when iterating through a list of fields of varying types.
/// it will call the correct display function based on the type of the field.
pub fn displayField(
    comptime src: std.builtin.SourceLocation,
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
    switch (@typeInfo(@TypeOf(field_value_ptr))) {
        .pointer => |top_ptr| {
            switch (@typeInfo(top_ptr.child)) {
                .int, .float => displayNumber(src, field_name, field_value_ptr, field_option, al),
                .bool => displayBool(src, field_name, field_value_ptr, field_option, al),
                .@"enum" => displayEnum(src, field_name, field_value_ptr, field_option, al),
                .array => |arr| {
                    // Array of u8 is only displayed as text if it has a text field option.
                    if (arr.child == u8 and field_option == .text) {
                        const slice: []const u8 = &field_value_ptr.*; // Arrays can only currently be shown as const strings.
                        displayString(src, field_name, &slice, field_option, al);
                    } else {
                        displayArray(src, field_name, field_value_ptr, depth, field_option, options);
                    }
                },
                .pointer => |ptr| {
                    if (ptr.size == .slice and ptr.child == u8 and field_option == .text) {
                        displayString(src, field_name, field_value_ptr, field_option, al);
                    } else {
                        displayPointer(src, field_name, field_value_ptr, depth, field_option, options, al);
                    }
                },
                .optional => {
                    displayOptional(src, field_name, field_value_ptr, depth, field_option, options, al, null);
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

/// Display numeric fields, ints and floats.
pub fn displayNumber(comptime src: std.builtin.SourceLocation, comptime field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(field_name, &.{ .int, .float }, "displayEnum", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .number)) return;
    numberFieldWidget(src, field_name, field_value_ptr, field_option.number, al);
}

pub fn displayEnum(comptime src: std.builtin.SourceLocation, comptime field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(field_name, &.{.@"enum"}, "displayEnum", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    enumFieldWidget(src, field_name, field_value_ptr, field_option.standard, al);
}

/// Display []u8, []const u8 and arrays of u8 and const u8.
/// Arrays are always treated as read-only. In future this could be enhanced to support in-place editing.
/// When strings are modified, they are assigned to a duplicated version of the text widget's buffer.
pub fn displayString(comptime src: std.builtin.SourceLocation, comptime field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrTypeString(field_name, "displayString", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .text)) return;
    textFieldWidget(src, field_name, field_value_ptr, field_option.text, al, stringBackingAllocator());
}

/// Same as displayString, but uses a user-supplied buffer, rather than a dynamically allocated buffer.
pub fn displayStringBuf(comptime src: std.builtin.SourceLocation, comptime field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment, buffer: []u8) void {
    validateFieldPtrTypeString(field_name, "displayString", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .text)) return;
    textFieldWidget(src, field_name, field_value_ptr, field_option.text, al, .{ .buffer = buffer });
}

pub fn displayBool(comptime src: std.builtin.SourceLocation, comptime field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    validateFieldPtrType(field_name, &.{.bool}, "displayBool", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    boolFieldWidget(src, field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayArray(
    comptime src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrType(field_name, &.{.array}, "displayArray", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (displayContainer(src, field_option.displayLabel(field_name))) |vbox| {
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

            displayField(@src(), field_name, val, depth, element_field_option, options, &alignment);
        }
    }
}

pub fn displaySlice(
    comptime src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
) void {
    validateFieldPtrTypeSlice(field_name, "displaySlice", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    if (displayContainer(src, field_option.displayLabel(field_name))) |vbox| {
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
            displayField(@src(), field_name, val, depth, element_field_option, options, &alignment);
        }
    }
}

/// Display a union.
///
/// If the union has Struct or Union members, then StructOptions(T) should be provided
/// for those members with an appropriate default_value.
/// These default values will be used to populate the active union value when the user changes selections.
pub fn displayUnion(
    comptime src: std.builtin.SourceLocation,
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
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() == .read_only;

    if (displayContainer(src, field_option.displayLabel(field_name))) |vbox| {
        defer vbox.deinit();

        const new_choice = unionFieldWidget(@src(), field_name, field_value_ptr, field_option);
        const UnionT = @TypeOf(field_value_ptr.*);
        if (current_choice != new_choice) {
            switch (new_choice) {
                inline else => |choice| {
                    const default_value = defaultValue(
                        @FieldType(UnionT, @tagName(choice)),
                        options,
                    );
                    if (!read_only) {
                        if (default_value) |default| {
                            field_value_ptr.* = @unionInit(UnionT, @tagName(choice), default);
                        } else {
                            dvui.log.debug(
                                "struct_ui: Union field {s}.{s} cannot be selected as no default value is provided. Use struct_ui.StructOptions({s}) to provide a default.",
                                .{ field_name, @tagName(choice), @typeName(@FieldType(UnionT, @tagName(choice))) },
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
                const struct_options: StructOptions(UnionT) = findMatchingStructOption(UnionT, options) orelse .initWithDefaults(.{}, null);
                var alignment: dvui.Alignment = .init(@src(), depth);
                defer alignment.deinit();

                // Will only display if an option exists for this field.
                if (struct_options.field_options.get(active_tag)) |union_field_option| {
                    displayField(@src(), @tagName(active_tag), active, depth, union_field_option, options, &alignment);
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
    comptime src: std.builtin.SourceLocation,
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
    const read_only = @typeInfo(@TypeOf(field_value_ptr)).pointer.is_const or field_option.displayMode() == .read_only;

    if (optionalFieldWidget(src, field_name, field_value_ptr, field_option, al)) {
        if (!read_only) {
            if (field_value_ptr.* == null) {
                field_value_ptr.* = default_value orelse
                    defaultValue(optional.child, options); // If there is no default value, it will remain null.
            }
        }
        if (field_value_ptr.*) |*val| {
            displayField(@src(), field_name, val, depth, field_option, options, al);
        } else {
            dvui.log.debug("struct_ui: Optional field {s} cannot be selected as no default value is provided. Use struct_ui.StructOptions({s}) to provide a default.", .{
                field_name,
                @typeName(optional.child),
            });
        }
    } else if (!read_only) {
        field_value_ptr.* = null;
    }
}

pub fn displayPointer(
    comptime src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    validateFieldPtrType(field_name, &.{.pointer}, "displayPointer", @TypeOf(field_value_ptr));
    if (field_option.displayMode() == .none) return;

    const ptr = @typeInfo(@TypeOf(field_value_ptr.*)).pointer;
    if (ptr.size == .one) {
        if (canDisplayPtr(ptr))
            displayField(src, field_name, field_value_ptr.*, depth, field_option, options, al);
    } else if (ptr.size == .slice) {
        if (canDisplayPtr(ptr))
            displaySlice(src, field_name, &field_value_ptr.*, depth, field_option, options);
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
    comptime src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: ?*dvui.Alignment,
) ?*dvui.BoxWidget {
    validateFieldPtrType(field_name, &.{.@"struct"}, "displayStruct", @TypeOf(field_value_ptr));
    if (!validFieldOptionsType(field_name, field_option, .standard)) return null;
    if (field_option.standard.display == .none) return null;

    const StructT = @TypeOf(field_value_ptr.*);
    const struct_options: StructOptions(StructT) = findMatchingStructOption(StructT, options) orelse .initWithDefaults(.{}, null);

    if (field_option.displayMode() == .none) return null;
    const vbox: ?*dvui.BoxWidget = displayContainer(src, field_option.displayLabel(field_name));
    if (vbox != null) {
        var struct_alignment: dvui.Alignment = .init(@src(), depth);
        defer struct_alignment.deinit();
        const alignment = al orelse &struct_alignment;

        inline for (0..struct_options.field_options.values.len) |field_num| {
            const field = comptime @TypeOf(struct_options.field_options).Indexer.keyForIndex(field_num);
            if (struct_options.field_options.contains(field)) {
                var box = dvui.box(@src(), .{ .dir = .vertical }, .{ .id_extra = field_num });
                defer box.deinit();
                displayField(
                    @src(),
                    @tagName(field),
                    &@field(field_value_ptr, @tagName(field)),
                    depth,
                    struct_options.field_options.getAssertContains(field),
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
pub fn displayContainer(comptime src: std.builtin.SourceLocation, field_name: []const u8) ?*dvui.BoxWidget {
    var vbox: ?*dvui.BoxWidget = null;
    if (dvui.expander(
        src,
        field_name,
        .{ .default_expanded = true },
        .{ .expand = .horizontal },
    )) {
        vbox = dvui.box(src, .{ .dir = .vertical }, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
            .id_extra = 1,
        });
    }
    return vbox;
}

/// Create a default value for a field from either default field initialization values or from struct_options
pub fn defaultValue(T: type, struct_options: anytype) ?T {
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
        inline else => return null,
    }
}

/// Return true if the field_option is valiud for this type of field.
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

/// Validate if the @typeInfo() of the passed in field_value_ptr
/// is in the set of `required_types`
pub fn validateFieldPtrType(
    comptime field_name: ?[]const u8,
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
pub fn validateFieldPtrTypeSlice(comptime field_name: []const u8, comptime caller: []const u8, comptime ptr_type: type) void {
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
pub fn validateFieldPtrTypeString(comptime field_name: ?[]const u8, comptime caller: []const u8, comptime ptr_type: type) void {
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
pub fn findMatchingStructOption(T: type, struct_options: anytype) ?StructOptions(T) {
    inline for (struct_options) |struct_option| {
        if (@TypeOf(struct_option).StructT == T) {
            return struct_option;
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
    return .{ .gpa = string_allocator orelse dvui.currentWindow().gpa };
}

/// Free any strings allocated by struct_ui.
///
/// `gpa` must be the same allocator as passed to dvui.Window.init().
pub fn deinit(gpa: std.mem.Allocator) void {
    var itr = string_map.iterator();
    while (itr.next()) |entry| {
        if (string_allocator) |string_alloc| {
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
