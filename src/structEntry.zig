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
            return switch (@typeInfo(FieldType)) {
                .int, .float => .{ .number = .{} },
                .pointer => |ptr| if (ptr.size == .slice and ptr.child == u8)
                    .{
                        .text = .{ .display = if (ptr.is_const) .read_only else .read_write },
                    }
                else
                    defaultFieldOption(ptr.child),
                .optional => |opt| defaultFieldOption(opt.child),
                else => .{ .standard = .{} },
            };
        }
    };
}

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

    //fn toNormalizedPercent(self: *const NumberFieldOptions, input_num: anytype, min: @TypeOf(input_num), max: @TypeOf(input_num)) f32 {
    //    const input: f64 = cast(f64, input_num);
    //    const range: f64 = cast(f64, max - min);
    //
    //    const progress = input - self.minValue(@TypeOf(input_num));
    //    return @as(f32, @floatCast(progress / range));
    //}

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

pub fn textFieldWidgetBuf(
    src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
    field_ptr: anytype,
    opt: StandardFieldOptions,
    buffer: []u8,
    alignment: *dvui.Alignment,
) []u8 {
    if (opt.display == .none) return;
    var return_buf = buffer;
    //TODO respect alloc setting
    var box = dvui.box(src, .horizontal, .{});
    defer box.deinit();

    dvui.label(@src(), "{s}", .{opt.label orelse field_name}, .{});

    const ProvidedPointerTreatment = enum {
        mutate_value_and_realloc,
        mutate_value_in_place_only,
        display_only,
        copy_value_and_alloc_new,
    };

    comptime var treatment: ProvidedPointerTreatment = .display_only;
    if (@typeInfo(@TypeOf(field_ptr.*)).pointer.is_const) {
        treatment = .mutate_value_and_realloc;
    } else {
        treatment = .mutate_value_and_realloc;
    }

    switch (treatment) {
        .mutate_value_and_realloc => {
            var hbox_aligned = dvui.box(@src(), .horizontal, .{ .margin = alignment.margin(box.data().id) });
            defer hbox_aligned.deinit();
            alignment.record(box.data().id, hbox_aligned.data());

            const text_box = dvui.textEntry(@src(), .{}, .{});
            defer text_box.deinit();
            //            if (text_box.text.len == 0 or !std.mem.eql(u8, text_box.text[0..field_ptr.*.len], field_ptr.*)) {
            if (text_box.text.len == 0) {
                std.debug.print("Set text\n", .{});
                text_box.textSet(field_ptr.*, false);
            }
            if (text_box.text_changed) {
                @memcpy(buffer, text_box.text[0..buffer.len]);
                std.debug.print("text = {s}\n", .{text_box.text});
                std.debug.print("buffer = {s}\n", .{buffer});
                return_buf = @constCast(field_ptr.*);
                field_ptr.* = buffer;
                std.debug.print("field_ptr = {s}\n", .{field_ptr.*});
            }
        },
        .copy_value_and_alloc_new => {
            //TODO
            dvui.label(@src(), " : TODO {s}", .{field_ptr.*}, .{});
            //var memory_handle = dvui.dataGet(null, box.widget().data().id, "memory_handle", []u8);
            //if (memory_handle == null) {
            //    const len = @max(64, result.*.len * 2);
            //    const memory = try allocator.?.alloc(u8, len);
            //    @memset(memory, 0);
            //    std.mem.copyForwards(u8, memory, result.*);
            //    dvui.dataSet(null, box.widget().data().id, "memory_handle", memory);
            //    memory_handle = memory;
            //}

            ////WARNING: this could leak memory if result has been dynamically allocated
            //result.* = memory_handle.?;
            //const text_box = try dvui.textEntry(@src(), .{ .text = .{ .buffer = memory_handle.? } }, opt.dvui_opts);
            //text_box.deinit();
        },
        else => @compileError("Nope"),
    }
    return return_buf;
}

//===============================================
//=========CONTAINER FIELD WIDGETS===============
//===============================================

// The field widgets in this section create widgets
// which contain other widgets (such as optional fields
// or unions)

pub fn unionFieldWidget(
    src: std.builtin.SourceLocation,
    comptime field_name: []const u8,
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
    comptime field_name: []const u8,
    field_ptr: anytype,
    comptime opts: OptionalFieldOptions,
    alignment: *dvui.Alignment,
) bool { // TODO: Return bool?
    _ = alignment;
    const box = dvui.box(src, .vertical, .{});
    defer box.deinit();
    var checkbox_state: bool = field_ptr.* != null;
    {
        var hbox = dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        dvui.label(@src(), "{s}?", .{opts.label_override orelse field_name}, .{});
        _ = dvui.checkbox(@src(), &checkbox_state, null, .{});
    }

    return checkbox_state;
}

// TODO: This needs to change somehow.
//pub fn pointerFieldWidget2(src: std.builtin.SourceLocation, container: anytype, comptime field_name: []const u8, comptime opts: FloatFieldOptions(@TypeOf(@field(container, field_name))), alignment: *dvui.Alignment) void {
//    var box = dvui.box(src, .vertical, .{});
//    defer box.deinit();
//    pointerFieldWidget(field_name, @TypeOf(@field(container, field_name)), &@field(container, field_name), opts, false, null, alignment);
//}
//
//pub fn pointerFieldWidget(
//    comptime name: []const u8,
//    comptime T: type,
//    comptime exclude: anytype,
//    result: *T,
//    opt: PointerFieldOptions(T, exclude),
//    comptime alloc: bool,
//    allocator: ?std.mem.Allocator,
//    alignment: *dvui.Alignment,
//) void {
//    const info = @typeInfo(T).pointer;
//
//    if (info.size == .slice and info.child == u8) {
//        textFieldWidget(name, T, result, opt, alloc, allocator, alignment);
//    } else if (info.size == .slice) {
//        sliceFieldWidget(name, T, exclude, result, opt, alloc, allocator, alignment);
//    } else if (info.size == .one) {
//        singlePointerFieldWidget(name, T, exclude, result, opt, alloc, allocator, alignment);
//    } else if (info.size == .c or info.size == .many) {
//        @compileError("structEntry does not support *C or Many pointers");
//    }
//}

//=======Single Item pointer and options=======
//pub fn SinglePointerFieldOptions(comptime T: type, exclude: anytype) type {
//    return struct {
//        child: FieldOptions(@typeInfo(T).pointer.child, exclude) = .{},
//        disabled: bool = false,
//        //label_override: ?[]const u8 = null,
//    };
//}
//
//pub fn singlePointerFieldWidget2(src: std.builtin.SourceLocation, container: anytype, comptime field_name: []const u8, comptime opts: FloatFieldOptions(@TypeOf(@field(container, field_name))), alignment: *dvui.Alignment) void {
//    var box = dvui.box(src, .vertical, .{});
//    defer box.deinit();
//    singlePointerFieldWidget(field_name, @TypeOf(@field(container, field_name)), &@field(container, field_name), opts, false, null, alignment);
//}
//
//pub fn singlePointerFieldWidget(
//    comptime name: []const u8,
//    comptime T: type,
//    comptime exclude: anytype,
//    result: *T,
//    opt: SinglePointerFieldOptions(T, exclude),
//    comptime alloc: bool,
//    allocator: ?std.mem.Allocator,
//    alignment: *dvui.Alignment,
//) void {
//    if (opt.disabled) return;
//    var box = dvui.box(@src(), .horizontal, .{});
//    defer box.deinit();
//
//    const Child = @typeInfo(T).pointer.child;
//
//    const ProvidedPointerTreatment = enum {
//        mutate_value_in_place,
//        display_only,
//        copy_value_and_alloc_new,
//    };
//
//    comptime var treatment: ProvidedPointerTreatment = .display_only;
//    comptime if (alloc == false) {
//        if (@typeInfo(T).pointer.is_const) {
//            treatment = .display_only;
//        } else {
//            treatment = .mutate_value_in_place;
//        }
//    } else if (alloc == true) {
//        if (@typeInfo(T).pointer.is_const) {
//            treatment = .copy_value_and_alloc_new;
//        } else {
//            treatment = .mutate_value_in_place;
//        }
//    };
//
//    //dvui.label(@src(), "{s}", .{opt.label_override orelse name}, .{});
//    switch (treatment) {
//        .display_only => {
//            dvui.label(@src(), ": {any}", .{result.*.*}, .{});
//        },
//        .mutate_value_in_place => {
//            fieldWidget(name, Child, exclude, result.*, opt.child, alloc, allocator, alignment);
//        },
//        .copy_value_and_alloc_new => {
//            //TODO
//            dvui.label(@src(), ": TODO {any}", .{result.*.*}, .{});
//        },
//    }
//}
//
////=========Array Field Widget and Options==========

pub fn ArrayFieldOptions(comptime T: type, exclude: anytype) type {
    return struct {
        child: StandardFieldOptions(@typeInfo(T).array.child, exclude) = .{},
        label_override: ?[]const u8 = null,
        disabled: bool = false,
    };
}

// TODO: Fix
//pub fn arrayFieldWidget2(src: std.builtin.SourceLocation, container: anytype, comptime field_name: []const u8, comptime opts: StandardFieldOptions, alignment: *dvui.Alignment) void {
//    _ = opts; // TODO
//    var box = dvui.box(src, .vertical, .{});
//    defer box.deinit();
//    arrayFieldWidget(field_name, @TypeOf(@field(container, field_name)), &@field(container, field_name), .{}, false, null, alignment);
//}

//pub fn arrayFieldWidget(
//    comptime name: []const u8,
//    comptime T: type,
//    comptime exclude: anytype,
//    result: *T,
//    opt: ArrayFieldOptions(T, exclude),
//    comptime alloc: bool,
//    allocator: ?std.mem.Allocator,
//    alignment: *dvui.Alignment,
//) void {
//    const SliceType = []@typeInfo(T).array.child;
//    var slice_result: SliceType = &(result.*);
//    const slice_opts = SliceFieldOptions(SliceType, exclude){
//        .child = opt.child,
//        .label_override = opt.label,
//        .disabled = opt.disabled,
//    };
//    sliceFieldWidget(name, SliceType, exclude, &slice_result, slice_opts, alloc, allocator, alignment);
//}

//=======Single Item pointer and options=======
//`pub const SliceFieldOptions = struct {
//    label_override: ?[]const u8 = null,
//    disabled: bool = false,
//};
//
//pub fn sliceFieldWidget2(
//    src: std.builtin.SourceLocation,
//    container: anytype,
//    comptime field_name: []const u8,
//    opts: StandardFieldOptions,
//    alignment: *dvui.Alignment,
//) void {
//    _ = opts; // TODO:
//    var box = dvui.box(src, .vertical, .{});
//    defer box.deinit();
//    sliceFieldWidget(field_name, @TypeOf(@field(container, field_name)), &@field(container, field_name), .{}, false, null, alignment);
//}
//
//pub fn sliceFieldWidget(
//    comptime name: []const u8,
//    comptime T: type,
//    comptime exclude: anytype,
//    result: *T,
//    opt: SliceFieldOptions(T, exclude),
//    comptime alloc: bool,
//    allocator: ?std.mem.Allocator,
//    alignment: *dvui.Alignment,
//) void {
//    if (@typeInfo(T).pointer.size != .slice) @compileError("must be called with slice");
//
//    const Child = @typeInfo(T).pointer.child;
//
//    const ProvidedPointerTreatment = enum {
//        mutate_value_and_realloc,
//        mutate_value_in_place_only,
//        display_only,
//        copy_value_and_alloc_new,
//    };
//
//    comptime var treatment: ProvidedPointerTreatment = .display_only;
//    comptime if (alloc == false) {
//        if (@typeInfo(T).pointer.is_const) {
//            treatment = .display_only;
//        } else {
//            treatment = .mutate_value_in_place_only;
//        }
//    } else if (alloc == true) {
//        if (@typeInfo(T).pointer.is_const) {
//            treatment = .copy_value_and_alloc_new;
//        } else {
//            treatment = .mutate_value_and_realloc;
//        }
//    };
//
//    var removed_idx: ?usize = null;
//    var insert_before_idx: ?usize = null;
//
//    var reorder = dvui.reorder(@src(), .{
//        .min_size_content = .{ .w = 120 },
//        .background = true,
//        .border = dvui.Rect.all(1),
//        .padding = dvui.Rect.all(4),
//    });
//
//    var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
//    dvui.label(@src(), "{s}", .{opt.label orelse name}, .{});
//
//    for (result.*, 0..) |_, i| {
//        var reorderable = reorder.reorderable(@src(), .{}, .{
//            .id_extra = i,
//            .expand = .horizontal,
//        });
//        defer reorderable.deinit();
//
//        if (reorderable.removed()) {
//            removed_idx = i; // this entry is being dragged
//        } else if (reorderable.insertBefore()) {
//            insert_before_idx = i; // this entry was dropped onto
//        }
//
//        var hbox = dvui.box(@src(), .horizontal, .{
//            .expand = .both,
//            .border = dvui.Rect.all(1),
//            .background = true,
//            .color_fill = .{ .name = .fill_window },
//        });
//        defer hbox.deinit();
//
//        switch (treatment) {
//            .mutate_value_in_place_only, .mutate_value_and_realloc => {
//                _ = dvui.ReorderWidget.draggable(@src(), .{ .reorderable = reorderable }, .{
//                    .expand = .vertical,
//                    .min_size_content = dvui.Size.all(22),
//                    .gravity_y = 0.5,
//                });
//            },
//            .display_only => {
//                //TODO
//            },
//            .copy_value_and_alloc_new => {
//                //TODO
//            },
//        }
//
//        fieldWidget("name", Child, exclude, @alignCast(@ptrCast(&(result.*[i]))), opt.child, alloc, allocator, alignment);
//    }
//
//    // show a final slot that allows dropping an entry at the end of the list
//    if (reorder.finalSlot()) {
//        insert_before_idx = result.*.len; // entry was dropped into the final slot
//    }
//
//    // returns true if the slice was reordered
//    _ = dvui.ReorderWidget.reorderSlice(Child, result.*, removed_idx, insert_before_idx);
//
//    //if (alloc) {
//    switch (treatment) {
//        .mutate_value_and_realloc => {
//            const new_item: *Child = dvui.dataGetPtrDefault(null, reorder.data().id, "new_item", Child, undefined);
//
//            _ = dvui.spacer(@src(), .{ .min_size_content = .height(4) });
//
//            var hbox = dvui.box(@src(), .horizontal, .{
//                .expand = .both,
//                .border = dvui.Rect.all(1),
//                .background = true,
//                .color_fill = .{ .name = .fill_window },
//            });
//            defer hbox.deinit();
//
//            if (dvui.button(@src(), "Add New", .{}, .{})) {
//                //TODO realloc here with allocator parameter
//            }
//
//            fieldWidget(@typeName(T), Child, exclude, @ptrCast(new_item), opt.child, alloc, allocator, alignment);
//        },
//        .copy_value_and_alloc_new => {
//            //TODO
//        },
//        .display_only => {
//            //TODO
//        },
//        .mutate_value_in_place_only => {
//            //TODO
//        },
//    }
//
//    vbox.deinit();
//
//    reorder.deinit();
//}
//==========Struct Field Widget and Options
//pub fn StructFieldOptions(comptime T: type, exclude: anytype) type {
//    return struct {
//        fields: NamespaceFieldOptions(T, exclude) = .{},
//        disabled: bool = false,
//        label_override: ?[]const u8 = null,
//        use_expander: bool = true,
//        align_fields: bool = true,
//    };
//}

//fn structFieldWidget(
//    comptime name: []const u8,
//    comptime T: type,
//    comptime exclude: anytype,
//    result: *T,
//    opt: StructFieldOptions(T, exclude),
//    comptime alloc: bool,
//    allocator: ?std.mem.Allocator,
//) void {
//    if (@typeInfo(T) != .@"struct") @compileError("Input Type Must Be A Struct");
//    if (opt.disabled) return;
//    const fields = @typeInfo(T).@"struct".fields;
//
//    var box = dvui.box(@src(), .vertical, .{ .expand = .both });
//    defer box.deinit();
//
//    const label = opt.label_override orelse name;
//
//    var expand = false; //use expander
//    var separate = false; //use separator to inset field
//
//    if (label.len == 0) {
//        expand = true;
//        separate = false;
//    } else if (opt.use_expander) {
//        expand = dvui.expander(@src(), label, .{}, .{});
//        separate = expand;
//    } else {
//        dvui.label(@src(), "{s}", .{label}, .{});
//        expand = true;
//        separate = false;
//    }
//
//    var hbox = dvui.box(@src(), .horizontal, .{ .expand = .both });
//    defer hbox.deinit();
//
//    if (separate) {
//        _ = dvui.separator(@src(), .{
//            .expand = .vertical,
//            .min_size_content = .{ .w = 2 },
//            .margin = dvui.Rect.all(4),
//        });
//    }
//
//    if (expand) {
//        var vbox = dvui.box(@src(), .vertical, .{ .expand = .both });
//        defer vbox.deinit();
//
//        var left_alignment = dvui.Alignment.init();
//        defer left_alignment.deinit();
//
//        inline for (fields, 0..) |field, i| {
//            if (comptime isExcluded(field.name, exclude)) continue;
//            const options = @field(opt.fields, field.name);
//            if (!options.disabled) {
//                const result_ptr = &@field(result.*, field.name);
//
//                var widgetbox = dvui.box(@src(), .vertical, .{
//                    .expand = .both,
//                    .id_extra = i,
//                    //.margin = left_alignment.margin(hbox.data().id)
//                });
//                defer widgetbox.deinit();
//
//                //var hbox_aligned = dvui.box(@src(), .horizontal, .{ .margin = left_alignment.margin(hbox.data().id) });
//                //defer hbox_aligned.deinit();
//                //left_alignment.record(hbox.data().id, hbox_aligned.data());
//
//                fieldWidget(field.name, field.type, exclude, result_ptr, options, alloc, allocator, &left_alignment);
//            }
//        }
//    }
//}
//
//=========Generic Field Widget and Options Implementations===========
//pub fn FieldOptions(comptime T: type, exclude: anytype) type {
//    return switch (@typeInfo(T)) {
//        .int => IntFieldOptions(T),
//        .float => FloatFieldOptions(T),
//        .@"enum" => EnumFieldOptions,
//        .bool => BoolFieldOptions,
//        //        .@"struct" => StructFieldOptions(T, exclude),
//        //        .@"union" => UnionFieldOptions(T, exclude),
//        .optional => OptionalFieldOptions(T, exclude),
//        //.pointer => PointerFieldOptions(T, exclude),
//        .array => ArrayFieldOptions(T, exclude),
//        else => @compileError("Invalid Type: " ++ @typeName(T)),
//    };
//}
//
//pub fn NamespaceFieldOptions(comptime T: type, exclude: anytype) type {
//    var fields: [std.meta.fields(T).len]std.builtin.Type.StructField = undefined;
//    var field_count = 0;
//    inline for (std.meta.fields(T)) |field| {
//        if (isExcluded(field.name, exclude)) continue;
//        const FieldType = FieldOptions(field.type, exclude);
//        fields[field_count] = .{
//            .alignment = 1,
//            .default_value_ptr = &(@as(FieldType, FieldType{})),
//            .is_comptime = false,
//            .name = field.name,
//            .type = FieldType,
//        };
//        field_count += 1;
//    }
//
//    return @Type(.{ .@"struct" = .{
//        .decls = &.{},
//        .fields = fields[0..field_count],
//        .is_tuple = false,
//        .layout = .auto,
//    } });
//}

//pub fn fieldWidget(
//    comptime name: []const u8,
//    comptime T: type,
//    comptime exclude: anytype,
//    result: *T,
//    options: StandardFieldOptions(T, exclude),
//    comptime alloc: bool,
//    allocator: ?std.mem.Allocator,
//    alignment: *dvui.Alignment,
//) void {
//    switch (@typeInfo(T)) {
//        //.int => intFieldWidget(name, T, result, options, alignment),
//        //.float => floatFieldWidget(name, T, result, options, alignment),
//        //.bool => boolFieldWidget(name, result, options, alignment),
//        //        .@"enum" => enumFieldWidget(name, T, result, options, alignment),
//        // .pointer => pointerFieldWidget(name, T, exclude, result, options, alloc, allocator, alignment),
//        .optional => optionalFieldWidget(name, T, result, options, alloc, allocator, alignment),
//        //        .@"union" => unionFieldWidget(name, T, exclude, result, options, alloc, allocator, alignment),
//        //        .@"struct" => structFieldWidget(name, T, exclude, result, options, alloc, allocator),
//        .array => arrayFieldWidget(name, T, exclude, result, options, alloc, allocator, alignment),
//        else => @compileError("Invalid type: " ++ @typeName(T)),
//    }
//}

//===============================================
//============PUBLIC API FUNCTIONS===============
//===============================================

pub fn displayNumber(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    std.debug.print("{s} = {d} ({s})\n", .{ field_name, field_value_ptr.*, writeable });
    numberFieldWidget(@src(), field_name, field_value_ptr, field_option.number, al);
}

pub fn displayEnum(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    std.debug.print("{s} = {s} ({s})\n", .{ field_name, @tagName(field_value_ptr.*), writeable });
    enumFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayString(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    std.debug.print("{s} = {s} ({s})\n", .{ field_name, field_value_ptr.*, writeable });
    if (field_option != .text) {
        dvui.log.debug("StructUI: Field {s} has FieldOption type {s} but needs {s}. Field will not be displayed\n", .{ field_name, @tagName(field_option), @tagName(FieldOptions.text) });
        return;
    }
    textFieldWidget(@src(), field_name, field_value_ptr, field_option.text, al);
}

pub fn displayBool(field_name: []const u8, field_value_ptr: anytype, field_option: FieldOptions, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    std.debug.print("{s} = {} ({s})\n", .{ field_name, field_value_ptr.*, writeable });
    boolFieldWidget(@src(), field_name, field_value_ptr, field_option.standard, al);
}

pub fn displayArray(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    const indent = " " ** 4;
    // TODO: Create the indenting box here.
    std.debug.print("{s} = ({s})\n", .{ field_name, writeable });

    for (field_value_ptr, 0..) |*val, i| {
        displayField(field_name, field_value_ptr, depth, field_option, options, al);
        std.debug.print("{s}{d} = {any}\n", .{ indent, i, val });
    }
}

pub fn findMatchingStructOption(T: type, struct_options: anytype) ?dvui.se.StructOptions(T) {
    inline for (struct_options) |struct_option| {
        if (@TypeOf(struct_option).StructT == T) {
            return struct_option;
        }
    }
    return null;
}

pub fn displayStruct(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    // TODO: assert the field option must be standard? But then why not just require a standard field option??
    if (field_option.standard.display == .none) return;

    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    const indent = " " ** (4 * depth);
    std.debug.print("{s}{s} = ({s})\n", .{ indent, field_name, writeable });
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

pub fn displayField(
    field_name: []const u8,
    field_value_ptr: anytype,
    comptime depth: usize,
    field_option: FieldOptions,
    options: anytype,
    al: *dvui.Alignment,
) void {
    const indent = " " ** (4 * depth);
    std.debug.print("{s}", .{indent});
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
            if (ptr.size == .slice and ptr.child == u8) {
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
        => {}, // These types are currently not displayed
    }
}

pub fn displayUnion(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    switch (field_value_ptr.*) {
        inline else => |*active, active_tag| {
            std.debug.print("{s} = {s} ({s})\n", .{ field_name, @tagName(active_tag), writeable });
            displayField(@tagName(active_tag), active, depth, field_option, options, al);
        },
    }
}

pub fn displayOptional(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    const is_null = if (field_value_ptr.* == null) "null" else "not null";
    std.debug.print("{s} is {s} ({s})\n", .{ field_name, is_null, writeable });
    if (field_value_ptr.*) |*val| {
        displayField(field_name, val, depth, field_option, options, al);
    }
}

pub fn displayPointer(field_name: []const u8, field_value_ptr: anytype, comptime depth: usize, field_option: FieldOptions, options: anytype, al: *dvui.Alignment) void {
    const writeable = if (@typeInfo(@TypeOf(field_value_ptr)).pointer.is_const) "RO" else "RW";
    std.debug.print("{s} ptr ({s})\n", .{ field_name, writeable });
    const ptr = @typeInfo(@TypeOf(field_value_ptr.*)).pointer;
    if (ptr.size == .one) {
        switch (@typeInfo(ptr.child)) {
            .@"fn" => {}, // TODO: There are more things here as well? Or does display field take care of this now?
            else => displayField(field_name, field_value_ptr.*, depth, field_option, options, al),
        }
    } else if (ptr.size == .slice) {
        // TODO: Thjis will need to take depth righty? It could be an array of structs?
        displayArray(field_name, field_value_ptr, field_option, options, al);
    } else {
        @compileError(std.fmt.comptimePrint("C-style and many item pointers not supported for {s}\n", .{@typeName(@TypeOf(field_value_ptr.*))}));
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
