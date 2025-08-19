const std = @import("std");
const dvui = @import("dvui.zig");

const border = dvui.Rect.all(1);

pub const FieldOptions = union(enum) {
    const DisplayMode = enum { none, read_only, read_write, read_create };
    standard: StandardFieldOptions,
    number: NumberFieldOptions,
    text: TextFieldOptions,
};

pub const StandardFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,

    label: ?[]const u8 = null,
};

pub fn StructOptions(T: type) type {
    return struct {
        pub const StructOptionsT = std.EnumMap(std.meta.FieldEnum(T), FieldOptions);
        const Self = @This();
        pub const StructT = T;
        options: StructOptionsT, // use .init or .default
        default_value: ?T = null,

        /// Optionally provide overrides for some fields.
        /// Used as .init(&. { . { .a = . { .min_vslue = 10}}})
        pub fn init(options: std.enums.EnumFieldStruct(
            StructOptionsT.Key,
            ?StructOptionsT.Value,
            @as(?StructOptionsT.Value, null),
        )) Self {
            var self = initDefaults(null);
            inline for (0..self.options.values.len) |i| {
                const key = comptime StructOptionsT.Indexer.keyForIndex(i);
                if (@field(options, @tagName(key))) |*v| {
                    self.options.values[i] = v.*;
                }
            }
            return self;
        }

        // TODO: So maybe the union is passing the field options for 'a', when it should be passing for 'b'??
        // ???
        pub fn initDefaults(comptime default_value: ?T) Self {
            comptime var defaults: StructOptionsT = .{};
            comptime {
                for (0..defaults.values.len) |i| {
                    const key = StructOptionsT.Indexer.keyForIndex(i);
                    const field_name = @tagName(key);
                    defaults.put(key, defaultFieldOption(@FieldType(T, field_name)));
                    //@compileLog(T, field_name, defaults.values[i]);
                }
            }
            return .{ .options = defaults, .default_value = default_value };
        }

        //pub fn override(self: *Self, options: std.enums.EnumFieldStruct(
        //    StructOptionsT.Key,
        //    ?StructOptionsT.Value,
        //    @as(?StructOptionsT.Value, null),
        //)) void {
        //    self.doOverride(StructOptionsT.Key, options);
        //}
        //
        //fn doOverride(self: *Self, comptime KeyType: type, options: anytype) void {
        //    inline for (std.enums.values(KeyType)) |key| {
        //        if (@field(options, @tagName(key))) {
        //            self.options.put(key, @field(options, @tagName(key)));
        //        }
        //    }
        //}

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
            //@compileLog(FieldType, result);
            return result;
        }
    };
}

/// Controls how number field are displayed.
/// Note that min and max are stored as f64, which can represent
/// all integer values up to an i53/u53.
pub const NumberFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,
    label: ?[]const u8 = null,

    widget_type: enum { number_entry, slider } = .number_entry,
    min: ?f64 = null,
    max: ?f64 = null,

    pub fn minValue(self: *const NumberFieldOptions, T: type) T {
        return switch (@typeInfo(T)) {
            .int => @intFromFloat(self.min orelse 0),
            .float => @floatCast(self.min orelse 0),
            else => unreachable,
        };
    }

    pub fn maxValue(self: *const NumberFieldOptions, T: type) T {
        return switch (@typeInfo(T)) {
            .int => @intFromFloat(self.max orelse std.math.maxInt(T)),
            .float => @floatCast(self.max orelse std.math.floatMax(T)),
            else => unreachable,
        };
    }

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

pub fn numberFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opt: NumberFieldOptions,
    alignment: *dvui.Alignment,
) void {
    if (opt.display == .none) return;

    const T = @TypeOf(field_ptr.*);
    const read_only = @typeInfo(@TypeOf(field_ptr)).pointer.is_const;

    switch (@typeInfo(T)) {
        .int => {},
        .float => {},
        else => @compileError(std.fmt.comptimePrint("{s} must be a number type, but is a {s}", .{ field_name, @typeName(T) })),
    }

    switch (opt.widget_type) {
        .number_entry => {
            var box = dvui.box(src, .horizontal, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});

            var hbox_aligned = dvui.box(@src(), .horizontal, .{ .margin = alignment.margin(box.data().id) });
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
            var box = dvui.box(src, .horizontal, .{});
            defer box.deinit();

            dvui.label(@src(), "{s}", .{field_name}, .{});

            if (!read_only) {
                var percent = opt.toNormalizedPercent(field_ptr.*, opt.minValue(T), opt.maxValue(T));
                _ = dvui.slider(@src(), .horizontal, &percent, .{
                    .expand = .horizontal,
                    .min_size_content = .{ .w = 100, .h = 20 },
                });
                // TODO: min and max can now be null. they need to get better defaults earlier.
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
    const read_only = @typeInfo(@TypeOf(field_ptr)).pointer.is_const;
    // TODO: Type check that it is actually an enum

    var box = dvui.box(src, .horizontal, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
    var hbox_aligned = dvui.box(@src(), .horizontal, .{ .margin = alignment.margin(box.data().id) });
    defer hbox_aligned.deinit();
    alignment.record(box.data().id, hbox_aligned.data());

    if (read_only) {
        dvui.label(@src(), "{s}", .{@tagName(field_ptr.*)}, .{});
    } else {
        const entries = std.meta.fieldNames(T);
        var choice: usize = @intFromEnum(field_ptr.*);
        _ = dvui.dropdown(@src(), entries, &choice, .{});
        field_ptr.* = @enumFromInt(choice);
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

    var box = dvui.box(src, .horizontal, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});
    var hbox_aligned = dvui.box(@src(), .horizontal, .{ .margin = alignment.margin(box.data().id) });
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

// TODO: Handle allocations if required.
pub const TextFieldOptions = struct {
    display: FieldOptions.DisplayMode = .read_write,

    label: ?[]const u8 = null,
    // TODO: So is this where the user provides their edit buffer?
    buffer: ?[]u8 = null,
};

/// Supports display and editing of []u8 slices and arrays.
/// Hmm. this needs to just handle slices I think. The array thingo can pass a slice to the array if needed.
pub fn textFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opt: TextFieldOptions,
    alignment: *dvui.Alignment,
) void {
    if (opt.display == .none) return;

    // TODO: Type checking! Split out read-only vs read-write.
    var box = dvui.box(src, .horizontal, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});

    // TODO: This needs to be 2-way
    if (opt.buffer) |buf| {
        if (buf.ptr != field_ptr.*.ptr) { // If it is a const pointer, this will alias, so need to check. sigh.
            @memcpy(buf[0..field_ptr.*.len], field_ptr.*);
        }
    }
    // TODO: Read-only needs to check 1) If the pointer is read-only and 2) if the buffer is read-only.
    switch (opt.display) {
        .read_write => {
            const buffer: []u8 = buffer: {
                if (opt.buffer) |buf| {
                    break :buffer buf;
                } else if (@typeInfo(@TypeOf(field_ptr.*)).pointer.is_const) {
                    dvui.log.debug("Must supply a buffer to TextOptions to allow editing of const fields. Field name is {s}", .{field_name});
                    return;
                } else {
                    break :buffer field_ptr.*;
                }
            };

            var hbox_aligned = dvui.box(@src(), .horizontal, .{ .margin = alignment.margin(box.data().id) });
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
        .none => {}, // TODO: ???
        .read_create => {}, // TODO: ??
        //else => @compileError("Nope"),
    }
}

//===============================================
//=========CONTAINER FIELD WIDGETS===============
//===============================================

// The field widgets in this section create widgets
// which contain other widgets (such as optional fields
// or unions)

pub fn unionFieldWidget(
    src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opt: FieldOptions,
    alignment: *dvui.Alignment,
) @typeInfo(@TypeOf(field_ptr.*)).@"union".tag_type.? {
    _ = alignment;
    _ = opt;
    const T = @TypeOf(field_ptr.*);
    //if (opt.display == .none) return; // TODO: Do we need union field options?

    var box = dvui.box(src, .vertical, .{});
    defer box.deinit();

    const entries = std.meta.fields(T);
    var choice = std.meta.activeTag(field_ptr.*);
    {
        var hbox = dvui.box(@src(), .vertical, .{});
        defer hbox.deinit();
        //const label = opt.label_override orelse field_name; // TODO:
        const label = field_name;
        if (label.len != 0) {
            dvui.label(@src(), "{s}", .{label}, .{
                .border = border,
                .background = true,
            });
        }
        inline for (entries, 0..) |entry, i| {
            // TODO: Make this select the real choice
            if (dvui.radio(@src(), choice == std.meta.stringToEnum(@TypeOf(choice), entry.name), entry.name, .{ .id_extra = i })) {
                choice = std.meta.stringToEnum(@TypeOf(choice), entry.name).?;
            }
        }
    }
    return choice;
}

//=======Optional Field Widget and Options=======
pub const OptionalFieldOptions = struct {
    disabled: bool = false,
    label_override: ?[]const u8 = null,
};

pub fn optionalFieldWidget(
    comptime src: std.builtin.SourceLocation,
    field_name: []const u8,
    field_ptr: anytype,
    opts: FieldOptions,
    alignment: *dvui.Alignment,
) bool { // TODO: Return bool?
    _ = alignment;
    const box = dvui.box(src, .vertical, .{});
    defer box.deinit();
    var checkbox_state: bool = field_ptr.* != null;
    {
        const display_name = switch (opts) {
            inline else => |opt| opt.label orelse field_name,
        };
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        dvui.label(@src(), "{s}?", .{display_name}, .{});
        _ = dvui.checkbox(@src(), &checkbox_state, null, .{});
    }

    return checkbox_state;
}

//===============================================
//============PUBLIC API FUNCTIONS===============
//===============================================

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

pub fn displayNumber(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    if (!validFieldOptionsType(field_name, field_option, .number)) return;
    numberFieldWidget(@src(), field_name, field_value_ptr, field_option.number, al);
}

pub fn displayEnum(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    enumFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayString(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    if (!validFieldOptionsType(field_name, field_option, .text)) return;
    textFieldWidget(@src(), field_name, field_value_ptr, field_option.text, al);
}

pub fn displayBool(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    boolFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayArray(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    if (dvui.expander(@src(), field_name, .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .vertical, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();

        for (field_value_ptr, 0..) |*val, i| {
            // TODO: Aligmmnent
            var hbox = dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .id_extra = i });
            defer hbox.deinit();

            var field_name_buf: [20]u8 = undefined; // 20 chars = u64
            const field_name_str = std.fmt.bufPrint(&field_name_buf, "{d}", .{i}) catch "#";
            displayField(field_name_str, val, depth, field_option, options, al);
        }
    }
}

/// Returns the option from the passed in options tuple for type T.
pub fn findMatchingStructOption(T: type, struct_options: anytype) ?dvui.se.StructOptions(T) {
    inline for (struct_options) |struct_option| {
        if (@TypeOf(struct_option).StructT == T) {
            return struct_option;
        }
    }
    return null;
}

pub fn displayStruct(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    if (!validFieldOptionsType(field_name, field_option, .standard)) return;
    if (field_option.standard.display == .none) return;

    const StructT = @TypeOf(field_value_ptr.*);
    const struct_options: StructOptions(StructT) = findMatchingStructOption(StructT, options) orelse .initDefaults(null);

    if (dvui.expander(@src(), field_name, .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .vertical, .{
            .expand = .vertical,
            .border = .{ .x = 1 },
            .background = true,
            .margin = .{ .w = 12, .x = 12 },
        });
        defer vbox.deinit();

        inline for (struct_options.options.values, 0..) |sub_field_option, field_num| {
            var box = dvui.box(@src(), .vertical, .{ .id_extra = field_num });
            defer box.deinit();

            const field = comptime @TypeOf(struct_options.options).Indexer.keyForIndex(field_num);
            displayField(@tagName(field), &@field(field_value_ptr, @tagName(field)), depth, sub_field_option, options, al);
        }
    }
}

/// Display a field in a container.
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

pub fn displayUnion(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    const current_choice = std.meta.activeTag(field_value_ptr.*);
    const new_choice = dvui.se.unionFieldWidget(@src(), field_name, field_value_ptr, field_option, al);
    const UnionT = @TypeOf(field_value_ptr.*);
    if (current_choice != new_choice) {
        switch (new_choice) {
            inline else => |choice| {
                field_value_ptr.* = @unionInit(
                    UnionT,
                    @tagName(choice),
                    defaultValue(
                        @FieldType(UnionT, @tagName(choice)),
                        field_option,
                        options,
                    ) orelse undefined,
                );
            },
        }
    }
    switch (field_value_ptr.*) {
        inline else => |*active, active_tag| {
            const struct_options: StructOptions(UnionT) = findMatchingStructOption(UnionT, options) orelse .initDefaults(null);
            // Will only display if an option exists for this field.
            if (struct_options.options.get(active_tag)) |union_field_option| {
                displayField(@tagName(active_tag), active, depth, union_field_option, options, al);
            }
        },
    }
}

pub fn displayOptional(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    const optional = @typeInfo(@TypeOf(field_value_ptr.*)).optional;

    if (dvui.se.optionalFieldWidget(@src(), field_name, field_value_ptr, field_option, al)) {
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
        dvui.label(@src(), "{s} is null", .{field_name}, .{}); // .{ .id_extra = i }); // TODO: Make this nicer formatting.
    }
}

pub fn displayPointer(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    const ptr = @typeInfo(@TypeOf(field_value_ptr.*)).pointer;
    if (ptr.size == .one) {
        displayField(field_name, field_value_ptr.*, depth, field_option, options, al);
    } else if (ptr.size == .slice) {
        displayField(field_name, &field_value_ptr.*, depth, field_option, options, al);
    } else {
        @compileError(std.fmt.comptimePrint("C-style and many item pointers not supported for {s}.{s}\n", .{ @typeName(@TypeOf(field_value_ptr.*)), field_name }));
    }
}

/// Supply a default value for a field
pub fn defaultValue(T: type, field_option: dvui.se.FieldOptions, struct_options: anytype) ?T { // TODO: Field is not anytype
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
                //@compileLog(@TypeOf(opt).StructT, T);
                if (@TypeOf(opt).StructT == T) { //} and opt.default_value != null) {
                    //@compileLog("found");
                    //                    std.debug.print("returning: {?any}\n", .{opt.default_value});
                    return opt.default_value;
                }
            }
            return null;
        },

        inline .@"enum" => |e| return @enumFromInt(e.fields[0].value),
        inline else => return null,
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
