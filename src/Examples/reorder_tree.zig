const reorderLayout = enum {
    vertical,
    horizontal,
    flex,
};

pub fn reorderLists() void {
    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    const layo = dvui.dataGetPtrDefault(null, uniqueId, "reorderLayout", reorderLayout, .horizontal);

    if (dvui.expander(@src(), "Simple", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .{}, .{ .margin = .{ .x = 10 } });
        defer vbox.deinit();

        {
            var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox2.deinit();

            const entries = [_][]const u8{ "Vertical", "Horizontal", "Flex" };
            for (0..3) |i| {
                if (dvui.radio(@src(), @intFromEnum(layo.*) == i, entries[i], .{ .id_extra = i })) {
                    layo.* = @enumFromInt(i);
                }
            }
        }

        {
            var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer hbox2.deinit();
            dvui.label(@src(), "Drag", .{}, .{});
            dvui.icon(@src(), "drag_icon", dvui.entypo.menu, .{}, .{ .min_size_content = .{ .h = 22 } });
            dvui.label(@src(), "to reorder.", .{}, .{});
        }

        reorderListsSimple(layo.*);
    }

    if (dvui.expander(@src(), "Advanced", .{}, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .{}, .{ .margin = .{ .x = 10 } });
        defer vbox.deinit();

        dvui.label(@src(), "Drag off list to remove.", .{}, .{});
        reorderListsAdvanced();
    }

    if (dvui.expander(@src(), "Tree", .{ .default_expanded = true }, .{ .expand = .horizontal })) {
        var vbox = dvui.box(@src(), .{}, .{ .margin = .{ .x = 10 }, .expand = .both });
        defer vbox.deinit();

        reorderTree();
    }
}

pub fn reorderListsSimple(lay: reorderLayout) void {
    const g = struct {
        var dir_entry: usize = 0;
        var strings = [6][]const u8{ "zero", "one", "two", "three", "four", "five" };
    };

    var removed_idx: ?usize = null;
    var insert_before_idx: ?usize = null;

    var scroll: ?*dvui.ScrollAreaWidget = null;
    if (lay == .horizontal) {
        scroll = dvui.scrollArea(@src(), .{ .horizontal = .auto }, .{});
    }
    defer {
        if (scroll) |sc| sc.deinit();
    }

    // reorder widget must wrap entire list
    var reorder = dvui.reorder(@src(), .{ .min_size_content = .{ .w = 120 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });
    defer reorder.deinit();

    // this box determines layout of list - could be any layout widget
    var vbox: ?*dvui.BoxWidget = null;
    var fbox: ?*dvui.FlexBoxWidget = null;
    switch (lay) {
        .vertical => vbox = dvui.box(@src(), .{}, .{ .expand = .both }),
        .horizontal => vbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both }),
        .flex => fbox = dvui.flexbox(@src(), .{}, .{ .expand = .both }),
    }
    defer {
        if (vbox) |vb| vb.deinit();
        if (fbox) |fb| fb.deinit();
    }

    for (g.strings[0..g.strings.len], 0..) |s, i| {

        // make a reorderable for each entry in the list
        var reorderable = reorder.reorderable(@src(), .{}, .{ .id_extra = i, .expand = .horizontal, .min_size_content = dvui.Options.sizeM(8, 1) });
        defer reorderable.deinit();

        if (reorderable.removed()) {
            removed_idx = i; // this entry is being dragged
        } else if (reorderable.insertBefore()) {
            insert_before_idx = i; // this entry was dropped onto
        }

        // actual content of the list entry
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .style = .window });
        defer hbox.deinit();

        dvui.label(@src(), "{s}", .{s}, .{});

        // this helper shows the triple-line icon, detects the start of a drag,
        // and hands off the drag to the ReorderWidget
        _ = dvui.ReorderWidget.draggable(@src(), .{ .reorderable = reorderable }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 });
    }

    // show a final slot that allows dropping an entry at the end of the list
    if (reorder.finalSlot()) {
        insert_before_idx = g.strings.len; // entry was dropped into the final slot
    }

    // returns true if the slice was reordered
    _ = dvui.ReorderWidget.reorderSlice([]const u8, &g.strings, removed_idx, insert_before_idx);
}

pub fn reorderListsAdvanced() void {
    const g = struct {
        var strings_template = [6][]const u8{ "zero", "one", "two", "three", "four", "five" };
        var strings = [6][]const u8{ "zero", "one", "two", "three", "", "" };
        var strings_len: usize = 4;

        pub fn reorder(removed_idx: ?usize, insert_before_idx: ?usize) void {
            if (removed_idx) |ri| {
                if (insert_before_idx) |ibi| {
                    // save this index
                    const removed = strings[ri];
                    if (ri < ibi) {
                        // moving down, shift others up
                        for (ri..ibi - 1) |i| {
                            strings[i] = strings[i + 1];
                        }
                        strings[ibi - 1] = removed;
                    } else {
                        // moving up, shift others down
                        for (ibi..ri, 0..) |_, i| {
                            strings[ri - i] = strings[ri - i - 1];
                        }
                        strings[ibi] = removed;
                    }
                } else {
                    // just removing, shift others up
                    for (ri..strings_len - 1) |i| {
                        strings[i] = strings[i + 1];
                    }
                    strings_len -= 1;
                }
            }
        }
    };

    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
    defer hbox.deinit();

    // template you can drag to add to list
    var added_idx: ?usize = null;
    var added_idx_p: ?dvui.Point.Physical = null;

    if (g.strings_len == g.strings.len) {
        dvui.label(@src(), "List Full", .{}, .{ .gravity_x = 1.0 });
    } else {
        var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .gravity_x = 1.0, .border = dvui.Rect.all(1), .margin = dvui.Rect.all(4), .background = true, .style = .window });
        defer hbox2.deinit();

        dvui.label(@src(), "Drag to add : {d}", .{g.strings_len}, .{});

        if (dvui.ReorderWidget.draggable(@src(), .{ .top_left = hbox2.data().rectScale().r.topLeft() }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 })) |p| {
            // add to list, but will be removed if not dropped onto a list slot
            g.strings[g.strings_len] = g.strings_template[g.strings_len];
            added_idx = g.strings_len;
            added_idx_p = p;
            g.strings_len += 1;
        }
    }

    var removed_idx: ?usize = null;
    var insert_before_idx: ?usize = null;

    // reorder widget must wrap entire list
    var reorder = dvui.reorder(@src(), .{ .min_size_content = .{ .w = 120 }, .background = true, .border = dvui.Rect.all(1), .padding = dvui.Rect.all(4) });
    defer reorder.deinit();

    // determines layout of list
    var vbox = dvui.box(@src(), .{}, .{ .expand = .both });
    defer vbox.deinit();

    if (added_idx) |ai| {
        // marking all events for capture, this will only be a problem if some
        // mouse events (in the same frame) came before this drag, and would
        // have interacted with a widget that hasn't run yet
        reorder.dragStart(ai, added_idx_p.?, 0); // reorder grabs capture
    }

    var seen_non_floating = false;
    for (g.strings[0..g.strings_len], 0..) |s, i| {
        // overriding the reorder id used so that it doesn't use the widget ids
        // (this allows adding a list element above without making a widget)
        var reorderable = dvui.Reorderable.init(@src(), reorder, .{ .reorder_id = i, .draw_target = false, .reinstall = false }, .{ .id_extra = i, .expand = .horizontal });
        defer reorderable.deinit();

        if (!reorderable.floating()) {
            if (seen_non_floating) {
                // we've had a non floating one already, and we are non floating, so add a separator
                _ = dvui.separator(@src(), .{ .id_extra = i, .expand = .horizontal, .margin = dvui.Rect.all(6) });
            } else {
                seen_non_floating = true;
            }
        }

        reorderable.install();

        if (reorderable.removed()) {
            removed_idx = i;
        } else if (reorderable.insertBefore()) {
            insert_before_idx = i;
        }

        if (reorderable.targetRectScale()) |rs| {
            // user is dragging a reorderable over this rect, could draw anything here
            rs.r.fill(.{}, .{ .color = .green, .fade = 1.0 });

            // reset to use next space, need a separator
            reorderable.reinstall1();
            _ = dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(6) });
            reorderable.reinstall2();
        }

        // actual content of the list entry
        var hbox2 = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .border = dvui.Rect.all(1), .background = true, .style = .window });
        defer hbox2.deinit();

        dvui.label(@src(), "{s}", .{s}, .{});

        if (dvui.ReorderWidget.draggable(@src(), .{ .top_left = reorderable.data().rectScale().r.topLeft() }, .{ .expand = .vertical, .gravity_x = 1.0, .min_size_content = dvui.Size.all(22), .gravity_y = 0.5 })) |p| {
            // marking all events for capture, this will only be a problem if some
            // mouse events (in the same frame) came before this drag, and would
            // have interacted with a widget that hasn't run yet
            reorder.dragStart(i, p, 0); // reorder grabs capture
        }
    }

    if (reorder.needFinalSlot()) {
        if (seen_non_floating) {
            _ = dvui.separator(@src(), .{ .expand = .horizontal, .margin = dvui.Rect.all(6) });
        }
        var reorderable = reorder.reorderable(@src(), .{ .last_slot = true, .draw_target = false }, .{});
        defer reorderable.deinit();

        if (reorderable.insertBefore()) {
            insert_before_idx = g.strings_len;
        }

        if (reorderable.targetRectScale()) |rs| {
            // user is dragging a reorderable over this rect
            rs.r.fill(.{}, .{ .color = .green, .fade = 1.0 });
        }
    }

    g.reorder(removed_idx, insert_before_idx);
}

pub fn reorderTree() void {
    exampleFileTree(
        @src(),
        .{
            .enable_reordering = true,
        },
        .{
            .background = true,
            .border = dvui.Rect.all(1),
            .padding = dvui.Rect.all(4),
        },
        .{
            .padding = dvui.Rect.all(1),
        },
        .{
            .border = .{ .x = 1 },
            .corner_radius = dvui.Rect.all(4),
            .box_shadow = .{
                .color = .black,
                .offset = .{ .x = -5, .y = 5 },
                .shrink = 5,
                .fade = 10,
                .alpha = 0.15,
            },
        },
    ) catch std.debug.panic("Failed to recurse files", .{});
}

const TreeEntryKind = enum {
    file,
    directory,
};

const ConstTreeEntry = struct {
    name: []const u8,
    children: []const ConstTreeEntry = &[_]ConstTreeEntry{},
    kind: TreeEntryKind = .file,
};

const MutableTreeEntry = struct {
    name: []const u8,
    children: Children = .empty,
    kind: TreeEntryKind = .file,

    const Children = std.ArrayListUnmanaged(MutableTreeEntry);
};

const tree_palette = &[_]dvui.Color{
    .{ .r = 0x5e, .g = 0x31, .b = 0x5b, .a = 0xff },
    .{ .r = 0x8c, .g = 0x3f, .b = 0x5d, .a = 0xff },
    .{ .r = 0xba, .g = 0x61, .b = 0x56, .a = 0xff },
    .{ .r = 0xf2, .g = 0xa6, .b = 0x5e, .a = 0xff },
    .{ .r = 0xff, .g = 0xe4, .b = 0x78, .a = 0xff },
    .{ .r = 0xcf, .g = 0xff, .b = 0x70, .a = 0xff },
    .{ .r = 0x8f, .g = 0xde, .b = 0x5d, .a = 0xff },
    .{ .r = 0x3c, .g = 0xa3, .b = 0x70, .a = 0xff },
    .{ .r = 0x3d, .g = 0x6e, .b = 0x70, .a = 0xff },
    .{ .r = 0x32, .g = 0x3e, .b = 0x4f, .a = 0xff },
    .{ .r = 0x32, .g = 0x29, .b = 0x47, .a = 0xff },
    .{ .r = 0x47, .g = 0x3b, .b = 0x78, .a = 0xff },
    .{ .r = 0x4b, .g = 0x5b, .b = 0xab, .a = 0xff },
};

fn exampleRemoveTreeEntry(directory: []const u8, entries: *MutableTreeEntry.Children, old_directory: []const u8, uniqueId: dvui.WidgetId) void {
    for (entries.items, 0..) |*e, i| {
        const alloc = dvui.currentWindow().lifo();
        const abs_path = std.fs.path.join(alloc, &.{ directory, e.name }) catch "";
        defer alloc.free(abs_path);

        if (std.mem.eql(u8, old_directory, abs_path)) {
            dvui.dataSet(null, uniqueId, "removed_entry", entries.swapRemove(i));
        }

        if (e.children.items.len > 0) {
            exampleRemoveTreeEntry(abs_path, &e.children, old_directory, uniqueId);
        }
    }
}

fn examplePlaceTreeEntry(directory: []const u8, entries: *MutableTreeEntry.Children, new_directory: []const u8, uniqueId: dvui.WidgetId) void {
    if (std.mem.containsAtLeast(u8, new_directory, 1, directory)) {
        if (dvui.dataGetPtr(null, uniqueId, "removed_entry", MutableTreeEntry)) |removed_entry| {
            const alloc = dvui.currentWindow().lifo();
            {
                const new_path = std.fs.path.join(alloc, &.{ directory, std.fs.path.basename(new_directory) }) catch "";
                defer alloc.free(new_path);

                if (std.mem.eql(u8, new_path, new_directory)) {
                    entries.appendAssumeCapacity(removed_entry.*);
                    return;
                }
            }

            for (entries.items) |*current_entry| {
                const abs_path = std.fs.path.join(alloc, &.{ directory, current_entry.name }) catch "";
                defer alloc.free(abs_path);

                if (current_entry.kind == .directory) {
                    const new_path = std.fs.path.join(alloc, &.{ abs_path, std.fs.path.basename(new_directory) }) catch "";
                    defer alloc.free(new_path);

                    if (std.mem.eql(u8, new_path, new_directory)) {
                        current_entry.children.appendAssumeCapacity(removed_entry.*);
                        return;
                    }
                    examplePlaceTreeEntry(abs_path, &current_entry.children, new_directory, uniqueId);
                }
            }

            dvui.dataRemove(null, uniqueId, "removed_entry");
        }
    }
}

// Should be able to fit all entries (including nested) in `example_file_structure`
// This could be calculated at comptime but it's a lot of code to traverse the tree for little gain
const example_file_structure_max_children = 36;
const example_file_structure: []const ConstTreeEntry = &[_]ConstTreeEntry{
    .{
        .name = "src",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "main.zig", .kind = .file },
            .{ .name = "utils.zig", .kind = .file },
            .{ .name = "config.zig", .kind = .file },
            .{
                .name = "components",
                .kind = .directory,
                .children = &[_]ConstTreeEntry{
                    .{ .name = "button.zig", .kind = .file },
                    .{ .name = "input.zig", .kind = .file },
                    .{ .name = "modal.zig", .kind = .file },
                },
            },
            .{
                .name = "styles",
                .kind = .directory,
                .children = &[_]ConstTreeEntry{
                    .{ .name = "theme.zig", .kind = .file },
                    .{ .name = "colors.zig", .kind = .file },
                },
            },
        },
    },
    .{
        .name = "assets",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "images", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "logo.png", .kind = .file },
                .{ .name = "icon.svg", .kind = .file },
                .{ .name = "background.jpg", .kind = .file },
            } },
            .{ .name = "fonts", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "main.ttf", .kind = .file },
                .{ .name = "bold.ttf", .kind = .file },
            } },
        },
    },
    .{
        .name = "docs",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "README.md", .kind = .file },
            .{ .name = "API.md", .kind = .file },
            .{ .name = "CHANGELOG.md", .kind = .file },
            .{ .name = "examples", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "basic.zig", .kind = .file },
                .{ .name = "advanced.zig", .kind = .file },
            } },
        },
    },
    .{ .name = "build.zig", .kind = .file },
    .{ .name = "build.zig.zon", .kind = .file },
    .{ .name = ".gitignore", .kind = .file },
    .{ .name = "LICENSE", .kind = .file },
    .{
        .name = "tests",
        .kind = .directory,
        .children = &[_]ConstTreeEntry{
            .{ .name = "unit.zig", .kind = .file },
            .{ .name = "integration.zig", .kind = .file },
            .{ .name = "fixtures", .kind = .directory, .children = &[_]ConstTreeEntry{
                .{ .name = "test_data.json", .kind = .file },
                .{ .name = "sample.txt", .kind = .file },
            } },
        },
    },
};

fn exampleFileTreeSearch(directory: []const u8, base_entries: *MutableTreeEntry.Children, entries: *MutableTreeEntry.Children, tree: *dvui.TreeWidget, uniqueId: dvui.WidgetId, color_id: *usize, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    var id_extra: usize = 0;
    for (entries.items) |*entry| {
        id_extra += 1;
        const color = tree_palette[color_id.* % tree_palette.len];

        var branch_opts_override = dvui.Options{
            .id_extra = id_extra,
            .expand = .horizontal,
        };

        const branch = tree.branch(@src(), .{ .expanded = false }, branch_opts_override.override(branch_options));
        defer branch.deinit();

        const alloc = dvui.currentWindow().lifo();
        const abs_path = std.fs.path.join(alloc, &.{ directory, entry.name }) catch "";
        defer alloc.free(abs_path);

        if (branch.insertBefore()) {
            if (dvui.dataGetSlice(null, uniqueId, "removed_path", []u8)) |removed_path| {
                const old_sub_path = std.fs.path.basename(removed_path);

                const new_path = try std.fs.path.join(alloc, &.{ if (entry.kind == .directory) abs_path else directory, old_sub_path });
                defer alloc.free(new_path);

                if (!std.mem.eql(u8, removed_path, new_path)) {
                    exampleRemoveTreeEntry("~", base_entries, removed_path, uniqueId);
                    examplePlaceTreeEntry("~", base_entries, new_path, uniqueId);
                }

                dvui.dataRemove(null, uniqueId, "removed_path");
            }
        }

        if (branch.floating()) {
            if (dvui.dataGetSlice(null, uniqueId, "removed_path", []u8) == null)
                dvui.dataSetSlice(null, uniqueId, "removed_path", abs_path);
        }

        if (entry.kind == .directory) {
            dvui.icon(
                @src(),
                "FolderIcon",
                dvui.entypo.folder,
                .{ .fill_color = color },
                .{
                    .gravity_y = 0.5,
                },
            );

            _ = dvui.label(@src(), "{s}", .{entry.name}, .{});

            dvui.icon(
                @src(),
                "DropIcon",
                if (branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
                .{ .fill_color = color },
                .{
                    .gravity_y = 0.5,
                    .gravity_x = 1.0,
                },
            );

            var expander_opts_override = dvui.Options{
                .margin = .{ .x = 14 },
                .color_border = color,
                .background = if (expander_options.border != null) true else false,
                .expand = .horizontal,
            };

            if (branch.expander(@src(), .{ .indent = 14 }, expander_opts_override.override(expander_options))) {
                exampleFileTreeSearch(
                    abs_path,
                    base_entries,
                    &entry.children,
                    tree,
                    uniqueId,
                    color_id,
                    branch_options,
                    expander_options,
                ) catch std.debug.panic("Failed to recurse files", .{});
            }

            color_id.* = color_id.* + 1;
        } else {
            dvui.icon(@src(), "FileIcon", dvui.entypo.text_document, .{ .fill_color = color }, .{
                .gravity_y = 0.5,
            });

            _ = dvui.label(@src(), "{s}", .{entry.name}, .{});

            if (branch.button.clicked()) {
                std.log.debug("Clicked: {s}", .{abs_path});
            }
        }
    }
}

/// Used to keep the data slices for the children alive
///
/// This is needed because we want to automatically deallocate when we are done
fn keepExampleFileTreeDataAlive(const_file_tree: []const ConstTreeEntry) void {
    for (const_file_tree) |const_entry| {
        const id: dvui.WidgetId = @enumFromInt(dvui.hashIdKey(@enumFromInt(@intFromPtr(const_file_tree.ptr)), const_entry.name));
        const child_slice = dvui.dataGetSlice(null, id, "child_slice", []MutableTreeEntry) orelse @panic("File tree slice did not exist");
        std.mem.doNotOptimizeAway(child_slice);
        if (const_entry.children.len > 0) {
            keepExampleFileTreeDataAlive(const_entry.children);
        }
    }
}

fn exampleFileTreeSetup(const_file_tree: []const ConstTreeEntry, mutable_file_tree: *MutableTreeEntry.Children) void {
    for (const_file_tree) |const_entry| {
        const id: dvui.WidgetId = @enumFromInt(dvui.hashIdKey(@enumFromInt(@intFromPtr(const_file_tree.ptr)), const_entry.name));
        // Allocate a data slice with the max amount of children possible which will be kept alive later.
        dvui.dataSetSliceCopies(null, id, "child_slice", &[1]MutableTreeEntry{undefined}, example_file_structure_max_children);
        var mutable_entry = MutableTreeEntry{
            .name = const_entry.name,
            .kind = const_entry.kind,
            .children = MutableTreeEntry.Children.initBuffer(
                dvui.dataGetSlice(null, id, "child_slice", []MutableTreeEntry) orelse @panic("Could not set slice for file tree"),
            ),
        };

        if (const_entry.children.len > 0) {
            exampleFileTreeSetup(const_entry.children, &mutable_entry.children);
        }

        mutable_file_tree.appendAssumeCapacity(mutable_entry);
    }
}

pub fn exampleFileTree(src: std.builtin.SourceLocation, tree_init_options: dvui.TreeWidget.InitOptions, tree_options: dvui.Options, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    const uniqueId = dvui.parentGet().extendId(@src(), 0);

    var tree = dvui.TreeWidget.tree(src, tree_init_options, tree_options);
    defer tree.deinit();

    var color_index: usize = 0;

    if (dvui.dataGetPtr(null, uniqueId, "mutable_data", MutableTreeEntry.Children)) |mutable_file_tree| {
        // Keep the array list buffer alive
        const data_slice = dvui.dataGetSlice(null, uniqueId, "mutable_slice", []MutableTreeEntry);
        std.mem.doNotOptimizeAway(data_slice);

        if (mutable_file_tree.items.len == 0) {
            exampleFileTreeSetup(example_file_structure, mutable_file_tree);
        } else {
            keepExampleFileTreeDataAlive(example_file_structure);
        }

        exampleFileTreeSearch("~", mutable_file_tree, mutable_file_tree, tree, uniqueId, &color_index, branch_options, expander_options) catch std.debug.panic("Failed to recurse files", .{});
    } else {
        dvui.dataSetSliceCopies(null, uniqueId, "mutable_slice", &[1]MutableTreeEntry{undefined}, example_file_structure_max_children);
        dvui.dataSet(null, uniqueId, "mutable_data", MutableTreeEntry.Children.initBuffer(
            dvui.dataGetSlice(null, uniqueId, "mutable_slice", []MutableTreeEntry) orelse @panic("Could not set slice for file tree"),
        ));
    }
}

pub fn fileTree(src: std.builtin.SourceLocation, root_directory: []const u8, tree_init_options: dvui.TreeWidget.InitOptions, tree_options: dvui.Options, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    var tree = dvui.TreeWidget.tree(src, tree_init_options, tree_options);
    defer tree.deinit();

    const uniqueId = dvui.parentGet().extendId(@src(), 0);
    recurseFiles(root_directory, tree, uniqueId, branch_options, expander_options) catch std.debug.panic("Failed to recurse files", .{});
}

fn recurseFiles(root_directory: []const u8, outer_tree: *dvui.TreeWidget, uniqueId: dvui.WidgetId, branch_options: dvui.Options, expander_options: dvui.Options) !void {
    const recursor = struct {
        fn search(directory: []const u8, tree: *dvui.TreeWidget, uid: dvui.WidgetId, color_id: *usize, branch_opts: dvui.Options, expander_opts: dvui.Options) !void {
            var dir = std.fs.cwd().openDir(directory, .{ .access_sub_paths = true, .iterate = true }) catch return;
            defer dir.close();

            const padding = dvui.Rect.all(2);

            var iter = dir.iterate();

            var id_extra: usize = 0;
            while (try iter.next()) |entry| {
                id_extra += 1;

                var branch_opts_override = dvui.Options{
                    .id_extra = id_extra,
                    .expand = .horizontal,
                };

                const color = tree_palette[color_id.* % tree_palette.len];

                const branch = tree.branch(@src(), .{
                    .expanded = false,
                }, branch_opts_override.override(branch_opts));
                defer branch.deinit();

                const abs_path = try std.fs.path.join(
                    dvui.currentWindow().arena(),
                    &.{ directory, entry.name },
                );

                if (branch.insertBefore()) {
                    if (dvui.dataGetSlice(null, uid, "removed_path", []u8)) |removed_path| {
                        const old_sub_path = std.fs.path.basename(removed_path);

                        const new_path = try std.fs.path.join(dvui.currentWindow().arena(), &.{ if (entry.kind == .directory) abs_path else directory, old_sub_path });

                        if (!std.mem.eql(u8, removed_path, new_path)) {
                            std.log.debug("DVUI/TreeWidget: Moved {s} to {s}", .{ removed_path, new_path });

                            try std.fs.renameAbsolute(removed_path, new_path);
                        }

                        dvui.dataRemove(null, uid, "removed_path");
                    }
                }

                if (branch.floating()) {
                    if (dvui.dataGetSlice(null, uid, "removed_path", []u8) == null)
                        dvui.dataSetSlice(null, uid, "removed_path", abs_path);
                }

                switch (entry.kind) {
                    .file => {
                        const icon = dvui.entypo.text_document;
                        const icon_color = color;
                        const text_color = dvui.themeGet().color_text;

                        _ = dvui.icon(
                            @src(),
                            "FileIcon",
                            icon,
                            .{ .fill_color = icon_color },
                            .{
                                .gravity_y = 0.5,
                                .padding = padding,
                            },
                        );
                        dvui.label(
                            @src(),
                            "{s}",
                            .{entry.name},
                            .{
                                .color_text = .{ .color = text_color },
                                .padding = padding,
                            },
                        );

                        if (branch.button.clicked()) {
                            std.log.debug("Clicked: {s}", .{abs_path});
                        }
                    },
                    .directory => {
                        const folder_name = std.fs.path.basename(abs_path);
                        const icon_color = color;

                        _ = dvui.icon(
                            @src(),
                            "FolderIcon",
                            dvui.entypo.folder,
                            .{
                                .fill_color = icon_color,
                            },
                            .{
                                .gravity_y = 0.5,
                                .padding = padding,
                            },
                        );
                        dvui.label(@src(), "{s}", .{folder_name}, .{
                            .color_text = .{ .color = dvui.themeGet().color_text },
                            .padding = padding,
                        });
                        _ = dvui.icon(
                            @src(),
                            "DropIcon",
                            if (branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
                            .{ .fill_color = icon_color },
                            .{
                                .gravity_y = 0.5,
                                .gravity_x = 1.0,
                                .padding = padding,
                            },
                        );

                        var expander_opts_override = dvui.Options{
                            .margin = .{ .x = 14 },
                            .color_border = .{ .color = color },
                            .expand = .horizontal,
                        };

                        if (branch.expander(@src(), .{ .indent = 14 }, expander_opts_override.override(expander_opts))) {
                            try search(
                                abs_path,
                                tree,
                                uid,
                                color_id,
                                branch_opts,
                                expander_opts,
                            );
                        }
                        color_id.* = color_id.* + 1;
                    },
                    else => {},
                }
            }
        }
    }.search;

    var color_index: usize = 0;

    const root_branch = outer_tree.branch(@src(), .{
        .expanded = true,
    }, .{
        .id_extra = 0,
        .expand = .horizontal,
        //.color_fill_hover = .fill,
    });
    defer root_branch.deinit();

    dvui.icon(
        @src(),
        "FolderIcon",
        dvui.entypo.folder,
        .{
            .fill_color = tree_palette[0],
        },
        .{
            .gravity_y = 0.5,
            .padding = dvui.Rect.all(10),
        },
    );

    const folder_name = std.fs.path.basename(root_directory);
    dvui.label(@src(), "{s}", .{folder_name}, .{
        .color_text = .{ .color = dvui.themeGet().color_text },
        .padding = dvui.Rect.all(10),
    });
    dvui.icon(
        @src(),
        "DropIcon",
        if (root_branch.expanded) dvui.entypo.triangle_down else dvui.entypo.triangle_right,
        .{ .fill_color = tree_palette[0] },
        .{
            .gravity_y = 0.5,
            .gravity_x = 1.0,
            .padding = dvui.Rect.all(10),
        },
    );

    if (root_branch.expander(@src(), .{ .indent = 14.0 }, .{
        .color_fill = .fill_window,
        .color_border = .{ .color = tree_palette[0] },
        .expand = .horizontal,
        .corner_radius = root_branch.button.wd.options.corner_radius,
        .background = true,
        .border = .{ .x = 1 },
        .box_shadow = .{
            .color = .{ .color = .black },
            .offset = .{ .x = -5, .y = 5 },
            .shrink = 5,
            .fade = 10,
            .alpha = 0.15,
        },
    })) {
        try recursor(root_directory, outer_tree, uniqueId, &color_index, branch_options, expander_options);
    }

    return;
}

test {
    @import("std").testing.refAllDecls(@This());
}

const std = @import("std");
const dvui = @import("../dvui.zig");
