var text_entry_buf = std.mem.zeroes([50]u8);
var text_entry_password_buf = std.mem.zeroes([30]u8);
var text_entry_password_buf_obf_enable: bool = true;
var text_entry_multiline_allocator_buf: [1000]u8 = undefined;
var text_entry_multiline_fba = std.heap.FixedBufferAllocator.init(&text_entry_multiline_allocator_buf);
var text_entry_multiline_buf: []u8 = &.{};
var text_entry_multiline_break = false;

/// ![image](Examples-text_entry.png)
pub fn textEntryWidgets(demo_win_id: dvui.WidgetId) void {
    var left_alignment = dvui.Alignment.init(@src(), 0);
    defer left_alignment.deinit();

    var enter_pressed = false;
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Singleline", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        var te = dvui.textEntry(@src(), .{ .text = .{ .buffer = &text_entry_buf } }, .{ .max_size_content = .size(dvui.Options.sizeM(20, 1)) });
        enter_pressed = te.enter_pressed;
        te.deinit();

        dvui.label(@src(), "(limit {d})", .{text_entry_buf.len}, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        left_alignment.spacer(@src(), 0);

        dvui.label(@src(), "press enter", .{}, .{ .gravity_y = 0.5 });

        if (enter_pressed) {
            dvui.animation(hbox.data().id, "enter_pressed", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 500_000 });
        }

        if (dvui.animationGet(hbox.data().id, "enter_pressed")) |a| {
            const prev_alpha = dvui.themeGet().alpha;
            dvui.themeGet().alpha *= a.value();
            dvui.label(@src(), "Enter!", .{}, .{ .gravity_y = 0.5 });
            dvui.themeGet().alpha = prev_alpha;
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Password", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        var te = dvui.textEntry(@src(), .{
            .text = .{ .buffer = &text_entry_password_buf },
            .password_char = if (text_entry_password_buf_obf_enable) "*" else null,
            .placeholder = "enter a password",
        }, .{});

        te.deinit();

        if (dvui.buttonIcon(
            @src(),
            "toggle",
            if (text_entry_password_buf_obf_enable) entypo.eye_with_line else entypo.eye,
            .{},
            .{},
            .{ .expand = .ratio },
        )) {
            text_entry_password_buf_obf_enable = !text_entry_password_buf_obf_enable;
        }

        dvui.label(@src(), "(limit {d})", .{text_entry_password_buf.len}, .{ .gravity_y = 0.5 });
    }

    const Sfont = struct {
        var dropdown: usize = 0;

        const FontNameId = struct { []const u8, ?dvui.Font.FontId };

        pub fn compare(_: void, lhs: FontNameId, rhs: FontNameId) bool {
            return std.mem.order(u8, lhs.@"0", rhs.@"0").compare(std.math.CompareOperator.lt);
        }
    };

    var font_entries: []Sfont.FontNameId = dvui.currentWindow().lifo().alloc(Sfont.FontNameId, dvui.currentWindow().font_bytes.count() + 1) catch &.{};
    defer dvui.currentWindow().lifo().free(font_entries);
    if (font_entries.len > 0) {
        font_entries[0] = .{ "Theme Body", null };
        var it = dvui.currentWindow().font_bytes.iterator();
        var i: usize = 0;
        while (it.next()) |entry| {
            i += 1;
            font_entries[i] = .{ entry.value_ptr.name, entry.key_ptr.* };
        }

        std.mem.sort(Sfont.FontNameId, font_entries[1..], {}, Sfont.compare);

        Sfont.dropdown = @min(Sfont.dropdown, font_entries.len - 1);
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        {
            var vbox = dvui.box(@src(), .{}, .{ .gravity_y = 0.5 });
            defer vbox.deinit();

            dvui.label(@src(), "Multiline", .{}, .{});

            _ = dvui.checkbox(@src(), &text_entry_multiline_break, "Break Lines", .{});
        }

        left_alignment.spacer(@src(), 0);

        var font = dvui.themeGet().font_body;
        if (Sfont.dropdown > 0) {
            if (font_entries[Sfont.dropdown].@"1") |id| {
                font.id = id;
            }
        }

        var te_opts: dvui.TextEntryWidget.InitOptions = .{ .multiline = true, .text = .{ .buffer_dynamic = .{
            .backing = &text_entry_multiline_buf,
            .allocator = text_entry_multiline_fba.allocator(),
            .limit = text_entry_multiline_allocator_buf.len,
        } } };
        if (text_entry_multiline_break) {
            te_opts.break_lines = true;
            te_opts.scroll_horizontal = false;
        }

        var te = dvui.textEntry(
            @src(),
            te_opts,
            .{
                .min_size_content = .{ .w = 160, .h = 80 },
                .max_size_content = .{ .w = 160, .h = 80 },
                .font = font,
            },
        );

        if (dvui.firstFrame(te.data().id)) {
            te.textSet("This multiline text\nentry can scroll\nin both directions.", false);
        }

        const bytes = te.len;
        te.deinit();

        dvui.label(@src(), "bytes {d}\nallocated {d}\nlimit {d}\nscroll horizontal: {s}", .{ bytes, text_entry_multiline_buf.len, text_entry_multiline_allocator_buf.len, if (text_entry_multiline_break) "no" else "yes" }, .{ .gravity_y = 0.5 });
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Multiline Font", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        var dd = dvui.DropdownWidget.init(@src(), .{ .selected_index = Sfont.dropdown, .label = font_entries[Sfont.dropdown].@"0" }, .{ .min_size_content = .{ .w = 100 }, .gravity_y = 0.5 });
        dd.install();
        defer dd.deinit();
        if (dd.dropped()) {
            for (font_entries, 0..) |e, i| {
                if (dd.addChoiceLabel(e.@"0")) {
                    Sfont.dropdown = i;
                }
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        left_alignment.spacer(@src(), 0);

        var vbox = dvui.box(@src(), .{}, .{});
        defer vbox.deinit();

        var la2 = dvui.Alignment.init(@src(), 0);
        defer la2.deinit();

        if (dvui.wasm) {
            if (dvui.button(@src(), "Add Noto Font", .{}, .{})) {
                dvui.backend.wasm.wasm_add_noto_font();
            }
        } else {
            var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            dvui.label(@src(), "Name", .{}, .{ .gravity_y = 0.5 });

            la2.spacer(@src(), 0);

            const normalOptions: dvui.Options = .{ .margin = dvui.TextEntryWidget.defaults.marginGet().plus(.all(1)) };
            const errOptions: dvui.Options = .{ .color_border = .err, .border = dvui.Rect.all(2) };

            const name_error = dvui.dataGetPtrDefault(null, hbox2.data().id, "_name_error", bool, false);
            var te_name = dvui.textEntry(@src(), .{}, if (name_error.*) errOptions else normalOptions);
            const name = te_name.getText();
            if (te_name.text_changed) {
                name_error.* = false;
            }
            te_name.deinit();
            hbox2.deinit();

            var hbox3 = dvui.box(@src(), .{ .dir = .horizontal }, .{});

            var new_filename: ?[]const u8 = null;

            if (dvui.buttonIcon(
                @src(),
                "select font",
                entypo.folder,
                .{},
                .{},
                .{ .expand = .ratio, .gravity_x = 1.0 },
            )) {
                new_filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{ .title = "Pick Font File" }) catch null;
            }

            dvui.label(@src(), "File", .{}, .{ .gravity_y = 0.5 });

            la2.spacer(@src(), 0);

            const file_error = dvui.dataGetPtrDefault(null, hbox3.data().id, "_file_error", bool, false);
            var te_file = dvui.textEntry(@src(), .{}, if (file_error.*) errOptions else normalOptions);
            if (new_filename) |f| {
                te_file.textLayout.selection.selectAll();
                te_file.textTyped(f, false);
            }
            if (te_file.text_changed) {
                file_error.* = false;
            }
            const filename = te_file.getText();
            te_file.deinit();
            hbox3.deinit();

            if (dvui.button(@src(), "Add Font", .{}, .{})) {
                if (name.len == 0) {
                    dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = "Add a Name" });
                    name_error.* = true;
                } else if (dvui.currentWindow().font_bytes.contains(.fromName(name))) {
                    const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Already have font named \"{s}\"", .{name}) catch name;
                    defer dvui.currentWindow().lifo().free(msg);
                    dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = msg });
                    name_error.* = true;
                } else {
                    var bytes: ?[]u8 = null;
                    if (!std.fs.path.isAbsolute(filename)) {
                        file_error.* = true;
                        const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Could not open \"{s}\"", .{filename}) catch filename;
                        defer dvui.currentWindow().lifo().free(msg);
                        dvui.dialog(@src(), .{}, .{ .title = "File Error", .message = msg });
                    } else {
                        const file = std.fs.openFileAbsolute(filename, .{}) catch blk: {
                            file_error.* = true;
                            const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Could not open \"{s}\"", .{filename}) catch filename;
                            defer dvui.currentWindow().lifo().free(msg);
                            dvui.dialog(@src(), .{}, .{ .title = "File Error", .message = msg });
                            break :blk null;
                        };
                        if (file) |f| {
                            bytes = f.reader().readAllAlloc(dvui.currentWindow().gpa, 30_000_000) catch null;
                        }
                    }

                    if (bytes) |b| blk: {
                        dvui.addFont(name, b, dvui.currentWindow().gpa) catch |err| switch (err) {
                            error.OutOfMemory => @panic("OOM"),
                            error.fontError => {
                                dvui.currentWindow().gpa.free(b);
                                const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "\"{s}\" is not a valid font", .{filename}) catch filename;
                                defer dvui.currentWindow().lifo().free(msg);
                                dvui.dialog(@src(), .{}, .{ .title = "Bad Font", .message = msg });
                                break :blk;
                            },
                        };

                        const msg = std.fmt.allocPrint(dvui.currentWindow().lifo(), "Added font named \"{s}\"", .{name}) catch name;
                        defer dvui.currentWindow().lifo().free(msg);
                        dvui.toast(@src(), .{ .subwindow_id = demo_win_id, .message = msg });
                    }
                }
            }
        }
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    // Combobox
    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "ComboBox", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        const entries: []const []const u8 = &.{
            "one", "two", "three", "four", "five", "six",
        };

        const combo = dvui.comboBox(@src(), .{}, .{});
        defer combo.deinit();
        // filter suggestions to match the start of the entry
        if (combo.te.text_changed) blk: {
            const arena = dvui.currentWindow().lifo();
            var filtered = std.ArrayListUnmanaged([]const u8).initCapacity(arena, entries.len) catch {
                dvui.dataRemove(null, combo.te.data().id, "suggestions");
                break :blk;
            };
            defer filtered.deinit(arena);
            const filter_text = combo.te.getText();
            for (entries) |entry| {
                if (std.mem.startsWith(u8, entry, filter_text)) {
                    filtered.appendAssumeCapacity(entry);
                }
            }
            dvui.dataSetSlice(null, combo.te.data().id, "suggestions", filtered.items);
        }

        if (combo.entries(dvui.dataGetSlice(null, combo.te.data().id, "suggestions", [][]const u8) orelse entries)) |index| {
            dvui.log.debug("Combo entry index picked: {d}", .{index});
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Suggest", .{}, .{ .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        var te = dvui.TextEntryWidget.init(@src(), .{}, .{ .max_size_content = .size(dvui.Options.sizeM(20, 1)) });
        te.install();

        const entries: []const []const u8 = &.{
            "one", "two", "three", "four", "five", "six",
        };

        var sug = dvui.suggestion(&te, .{ .open_on_text_change = true });

        // dvui.suggestion processes events so text entry should be updated
        if (te.text_changed) blk: {
            const arena = dvui.currentWindow().lifo();
            var filtered = std.ArrayListUnmanaged([]const u8).initCapacity(arena, entries.len) catch {
                dvui.dataRemove(null, te.data().id, "suggestions");
                break :blk;
            };
            defer filtered.deinit(arena);
            const filter_text = te.getText();
            for (entries) |entry| {
                if (std.mem.startsWith(u8, entry, filter_text)) {
                    filtered.appendAssumeCapacity(entry);
                }
            }
            dvui.dataSetSlice(null, te.data().id, "suggestions", filtered.items);
        }

        const filtered = dvui.dataGetSlice(null, te.data().id, "suggestions", [][]const u8) orelse entries;
        if (sug.dropped()) {
            for (filtered) |entry| {
                if (sug.addChoiceLabel(entry)) {
                    te.textSet(entry, false);
                    sug.close();
                }
            }

            if (sug.addChoiceLabel("Set to \"hello\" [always shown]")) {
                te.textSet("hello", false);
            }
            _ = sug.addChoiceLabel("close [always shown]");
        }

        sug.deinit();

        // suggestion forwards events to textEntry, so don't call te.processEvents()
        te.draw();
        te.deinit();
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(10) });

    const parse_types = [_]type{ u8, i8, u16, i16, u32, i32, f32, f64 };
    const parse_typenames: [parse_types.len][]const u8 = blk: {
        var temp: [parse_types.len][]const u8 = undefined;
        inline for (parse_types, 0..) |T, i| {
            temp[i] = @typeName(T);
        }
        break :blk temp;
    };

    const S = struct {
        var type_dropdown_val: usize = 0;
        var min: bool = false;
        var max: bool = false;
        var value: f64 = 0;
    };

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        dvui.label(@src(), "Parse", .{}, .{ .gravity_y = 0.5 });

        _ = dvui.dropdown(@src(), &parse_typenames, &S.type_dropdown_val, .{ .min_size_content = .{ .w = 20 }, .gravity_y = 0.5 });

        left_alignment.spacer(@src(), 0);

        inline for (parse_types, 0..) |T, i| {
            if (i == S.type_dropdown_val) {
                var value: T = undefined;
                if (@typeInfo(T) == .int) {
                    S.value = std.math.clamp(S.value, std.math.minInt(T), std.math.maxInt(T));
                    value = @intFromFloat(S.value);
                    S.value = @floatFromInt(value);
                } else {
                    value = @floatCast(S.value);
                }
                const result = dvui.textEntryNumber(@src(), T, .{ .value = &value, .min = if (S.min) 0 else null, .max = if (S.max) 100 else null, .show_min_max = true }, .{ .id_extra = i });
                displayTextEntryNumberResult(result);

                if (result.changed) {
                    if (@typeInfo(T) == .int) {
                        S.value = @floatFromInt(value);
                    } else {
                        S.value = @floatCast(value);
                    }
                    dvui.animation(hbox.data().id, "value_changed", .{ .start_val = 1.0, .end_val = 0, .start_time = 0, .end_time = 500_000 });
                }

                if (dvui.animationGet(hbox.data().id, "value_changed")) |a| {
                    const prev_alpha = dvui.themeGet().alpha;
                    dvui.themeGet().alpha *= a.value();
                    dvui.label(@src(), "Changed!", .{}, .{ .gravity_y = 0.5 });
                    dvui.themeGet().alpha = prev_alpha;
                }
            }
        }
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();

        left_alignment.spacer(@src(), 0);

        _ = dvui.checkbox(@src(), &S.min, "Min", .{});
        _ = dvui.checkbox(@src(), &S.max, "Max", .{});
        _ = dvui.label(@src(), "Stored {d}", .{S.value}, .{});
    }

    _ = dvui.spacer(@src(), .{ .min_size_content = .height(20) });

    dvui.label(@src(), "The text entries in this section are left-aligned", .{}, .{});
}

pub fn displayTextEntryNumberResult(result: anytype) void {
    switch (result.value) {
        .TooBig => {
            dvui.label(@src(), "Too Big", .{}, .{ .gravity_y = 0.5 });
        },
        .TooSmall => {
            dvui.label(@src(), "Too Small", .{}, .{ .gravity_y = 0.5 });
        },
        .Empty => {
            dvui.label(@src(), "Empty", .{}, .{ .gravity_y = 0.5 });
        },
        .Invalid => {
            dvui.label(@src(), "Invalid", .{}, .{ .gravity_y = 0.5 });
        },
        .Valid => |num| {
            dvui.label(@src(), "Parsed {d}", .{num}, .{ .gravity_y = 0.5 });
        },
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}

test "DOCIMG text_entry" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 500, .h = 500 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();
            textEntryWidgets(box.data().id);
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "Examples-text_entry.png");
}

const dvui = @import("../dvui.zig");
const std = @import("std");
const entypo = dvui.entypo;
