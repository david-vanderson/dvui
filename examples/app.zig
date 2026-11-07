const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

const Io = std.Io;

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .org = "org.vn",
            .app = "target_finder",
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "Target Finder",
            .icon = null,
            .window_init_options = .{
                // Could set a default theme here
                // .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var gpa = std.heap.smp_allocator;

var orig_content_scale: f32 = 1.0;
// var warn_on_quit: bool = false;
// var warn_on_quit_closing: bool = false;
// var extra_os_win: bool = false;

// 关键词相关
var keyword_buffer = std.mem.zeroes([256]u8);
var keyword_box_id: dvui.Id = undefined;

// 目录路径相关
var directories = std.ArrayList([]const u8).empty;
var directory_list_id: dvui.Id = undefined;
var directory_inner_box_padding: dvui.Rect = dvui.Rect.all(0);
var btn_inner_box_padding: dvui.Rect = dvui.Rect.all(0);
var directory_scroll_info = dvui.ScrollInfo{ .horizontal = .auto };
var btn_scroll_info = dvui.ScrollInfo{ .horizontal = .none };

// 搜索结果相关
var result_map: std.StringArrayHashMapUnmanaged([]Matched) = undefined;
var result_inner_box_h: f32 = undefined;
var expander_collapsed_map: std.AutoArrayHashMapUnmanaged(usize, bool) = undefined;
var result_inner_box_padding: dvui.Rect = dvui.Rect.all(0);
var result_btn_inner_box_padding: dvui.Rect = dvui.Rect.all(0);
var result_scroll_info = dvui.ScrollInfo{ .horizontal = .auto };
var result_btn_scroll_info = dvui.ScrollInfo{ .horizontal = .none };

var searching = false;
var worker: ?std.Thread = null;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn appInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;

    // Add your own bundled font files...:
    // try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    // try dvui.addFont("NotoSansSC", @embedFile("../src/assets/fonts/NotoSansSC-Regular.ttf"), null);

    // Initialize search result maps
    result_map = .{};
    try result_map.ensureUnusedCapacity(gpa, 256);
    expander_collapsed_map = .{};
    try expander_collapsed_map.ensureUnusedCapacity(gpa, 256);

    // If you want a custom theme use something like this:
    // var theme = switch (win.backend.preferredColorScheme() orelse .light) {
    //     .light => dvui.Theme.builtin.adwaita_light,
    //     .dark => dvui.Theme.builtin.adwaita_dark,
    // };

    // theme.font_body = .find(.{ .family = "NotoSansSC" });

    // win.themeSet(theme);
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn appDeinit(win: *dvui.Window) void {
    _ = win;
    // good place to free anything you've allocated with win.gpa
    defer {
        // for (directories.items) |item| {
        //     gpa.free(item);
        // }
        defer directories.deinit(gpa);
    }
}

// Run each frame to do normal UI
pub fn appFrame() !dvui.App.Result {
    {
        var scaler = dvui.scale(@src(), .{
            .scale = &dvui.currentWindow().content_scale,
        }, .{ .rect = .cast(dvui.windowRect()) });
        scaler.deinit();

        if (menu()) |res| return res;

        var box = dvui.box(@src(), .{ .dir = .vertical }, .{
            .expand = .both,
            .max_size_content = .{ .w = 200, .h = dvui.currentWindow().rect_pixels.h },
            .min_size_content = .{ .h = 300 },
            .style = .content,
            .background = true,
        });
        defer box.deinit();

        if (try content()) |res| return res;
    }

    return .ok;
}

pub fn menu() ?dvui.App.Result {
    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
    defer hbox.deinit();

    var m = dvui.menu(@src(), .horizontal, .{});
    defer m.deinit();

    if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .tag = "first-focusable" })) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();

        if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
            m.close();
        }

        if (dvui.backend.kind != .web) {
            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                return .close;
            }
        }
    }

    return null;
}

pub fn content() !?dvui.App.Result {
    var left_alignment = dvui.Alignment.init(@src(), 0);
    defer left_alignment.deinit();

    // 输入区块
    {
        var top_box = dvui.groupBox(@src(), "Input", .{ .border = .all(1.0), .expand = .horizontal });
        defer top_box.deinit();

        // 关键词区块
        {
            var keyword_box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
            defer keyword_box.deinit();

            dvui.label(@src(), "Keyword: ", .{}, .{ .gravity_y = 0.5 });

            left_alignment.spacer(@src(), 0);

            var keyword_input = dvui.textEntry(@src(), .{ .text = .{ .buffer = &keyword_buffer } }, .{ .label = .{ .label_widget = .prev } });
            defer keyword_input.deinit();

            keyword_box_id = keyword_input.data().id;

            // std.debug.print("{s}\n", .{keyword_input.textGet()});
        }

        // 目录区块
        {
            var directory_box_wrapper = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both });
            defer directory_box_wrapper.deinit();

            dvui.label(@src(), "Directory: ", .{}, .{ .gravity_y = 0, .margin = .rect(0, 4, 0, 0) });

            left_alignment.spacer(@src(), 0);

            var directory_box = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
            defer directory_box.deinit();

            {
                var directory_list_box = dvui.box(@src(), .{
                    .dir = .horizontal,
                }, .{ .expand = .both, .border = if (directories.items.len > 0) .all(1) else .all(0), .margin = .rect(4, if (directories.items.len > 0) 4 else 0, 0, 0), .padding = if (directories.items.len > 0) .rect(2, 0, 2, 0) else .rect(0, 4, 0, 0), .corners = .all(3) });
                defer directory_list_box.deinit();

                directory_list_id = directory_list_box.data().id;
                dvui.dataSetSlice(dvui.currentWindow(), directory_list_id, "directories", directories.items);

                const directory_paths = dvui.dataGetSlice(dvui.currentWindow(), directory_list_id, "directories", [][]const u8) orelse @as([][]const u8, &.{});

                var grid = dvui.grid(@src(), .{}, .{ .expand = .both, .max_size_content = .height(60), .border = .all(0) });
                defer grid.deinit();

                for (directory_paths, 0..) |item, row| {
                    {
                        var cell = grid.cell(.{ .row = row, .col = 0 }, .{ .expand = .both });
                        defer cell.deinit();

                        var cache = dvui.cacheSize(@src(), .{}, .{ .id_extra = row, .expand = .both });
                        defer cache.deinit();

                        if (cache.uncached()) {
                            dvui.label(@src(), "{s}\n", .{item}, .{ .expand = .both, .max_size_content = .width(1000) });
                        }
                    }
                    {
                        var cell = grid.cell(.{ .row = row, .col = 1 }, .{
                            .expand = .none,
                            .min_size_content = .width(28),
                            .max_size_content = .width(28),
                        });
                        defer cell.deinit();

                        var cache = dvui.cacheSize(@src(), .{}, .{
                            .id_extra = row,
                        });
                        defer cache.deinit();

                        if (cache.uncached()) {
                            if (dvui.buttonIcon(@src(), "minus", dvui.entypo.minus, .{ .draw_focus = false }, .{}, .{ .id_extra = row, .min_size_content = .{ .w = 14, .h = 14 }, .max_size_content = .{ .w = 14, .h = 14 }, .corners = .round(14), .gravity_x = 0.5, .gravity_y = 0.5 })) {
                                std.debug.print("{s}\n", .{"点击了移除按钮"});
                                _ = directories.orderedRemove(row);

                                dvui.dataSetSlice(dvui.currentWindow(), directory_list_id, "directories", directories.items);
                            }
                        }
                    }
                }
            }

            // 新增目录按钮
            {
                if (dvui.buttonIcon(@src(), "plus", dvui.entypo.plus, .{ .draw_focus = false }, .{}, .{})) {
                    std.debug.print("{s}\n", .{"点击了新增按钮"});

                    const directory_path = try dvui.dialogNativeFolderSelect(gpa, .{}) orelse @as([]const u8, &.{});

                    const contains = for (directories.items) |item| {
                        if (std.mem.eql(u8, item, directory_path)) {
                            break true;
                        }
                    } else false;

                    if (contains == false) {
                        try directories.append(gpa, directory_path);
                    }

                    dvui.dataSetSlice(dvui.currentWindow(), directory_list_id, "directories", directories.items);
                }
            }
        }

        // 操作区块
        {
            var opt_box_wrapper = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .both, .margin = .rect(0, 4, 0, 0) });
            defer opt_box_wrapper.deinit();

            left_alignment.spacer(@src(), 0);

            var opt_box = dvui.box(@src(), .{ .dir = .horizontal }, .{});
            defer opt_box.deinit();

            if (dvui.button(@src(), "Search", .{ .draw_focus = false }, .{})) {
                const keyword: []const u8 = std.mem.sliceTo(&keyword_buffer, 0);

                if (keyword.len == 0) return null;

                const directory_paths = dvui.dataGetSlice(dvui.currentWindow(), directory_list_id, "directories", [][]const u8) orelse @as([][]const u8, &.{});

                if (searching == false) {
                    searching = true;
                    worker = try std.Thread.spawn(.{}, travers, .{ gpa, dvui.io, keyword, directory_paths, &result_map });
                } else {
                    // Already searching, ignore
                }
            }

            // Wait for background search to complete
            if (searching) {
                if (worker) |w| {
                    w.join();
                    worker = null;
                    searching = false;
                }
            }
        }
    }

    // 输出区块
    {
        var bottom_box = dvui.groupBox(@src(), "Output", .{ .expand = .both, .padding = .all(0) });
        defer bottom_box.deinit();

        var result_box_wrapper = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
        defer result_box_wrapper.deinit();

        var result_list = dvui.scrollArea(@src(), .{ .scroll_info = &result_scroll_info, .vertical_bar = .auto_overlay, .horizontal_bar = .auto_overlay }, .{
            .expand = .both,
            .style = .content,
            .max_size_content = .size(.{ .h = 200 }),
        });
        defer result_list.deinit();

        const len = result_map.entries.len;

        for (0..len) |index| {

            //             {
            //                 const cell = grid.colHeader(index, .{});
            //                 defer cell.deinit();
            //
            //                 dvui.label(@src(), "Path", .{}, .{ .gravity_x = 0.5 });
            //             }
            //
            //             {
            //                 const cell = grid.colHeader(index, .{});
            //                 defer cell.deinit();
            //
            //                 dvui.label(@src(), "Action", .{}, .{ .gravity_x = 0.5 });
            //             }

            const item = result_map.entries.slice().get(index);

            if (dvui.expander(@src(), item.key, .{ .default_expanded = true }, .{ .id_extra = index, .expand = .horizontal, .font = .{ .size = 12 } })) {
                var grid = dvui.grid(@src(), .{}, .{ .border = .all(0), .expand = .both, .id_extra = index });
                defer grid.deinit();

                for (0..item.value.len) |row| {
                    {
                        var cell = grid.cell(.{ .row = row, .col = 0 }, .{
                            .expand = .both,
                        });
                        defer cell.deinit();

                        var cache = dvui.cacheSize(@src(), .{}, .{
                            .id_extra = row,
                            .expand = .both,
                        });
                        defer cache.deinit();

                        if (cache.uncached()) {
                            dvui.label(@src(), "{d} - {s}\n", .{ row, item.value[row].path }, .{
                                .expand = .both,
                                .min_size_content = .{ .w = 100, .h = 18 },
                                .max_size_content = .height(18),
                                .gravity_y = 0.5,
                            });
                        }
                    }
                    {
                        var cell = grid.cell(.{ .row = row, .col = 1 }, .{ .expand = .none, .padding = .{ .x = 12, .w = 12 } });
                        defer cell.deinit();

                        var cache = dvui.cacheSize(@src(), .{}, .{ .id_extra = row, .expand = .both, .gravity_y = 0.5 });
                        defer cache.deinit();

                        const icon_type = switch (item.value[row].kind) {
                            .directory => .{ "folder", dvui.entypo.folder },
                            .file => .{ "documents", dvui.entypo.documents },
                            else => .{ "emoji_neutral", dvui.entypo.emoji_neutral },
                        };

                        if (cache.uncached()) {
                            dvui.icon(@src(), icon_type.@"0", icon_type.@"1", .{}, .{ .id_extra = row, .max_size_content = .size(.{ .w = 14, .h = 14 }), .min_size_content = .{ .w = 14, .h = 14 }, .corners = .round(14), .gravity_y = 0.5 });
                        }
                    }
                    {
                        var cell = grid.cell(.{ .row = row, .col = 2 }, .{ .expand = .none, .padding = .{ .x = 4, .w = 4 } });
                        defer cell.deinit();

                        var cache = dvui.cacheSize(@src(), .{}, .{ .id_extra = row, .expand = .both, .gravity_y = 0.5 });
                        defer cache.deinit();

                        if (cache.uncached()) { // 里面套一层box会导致内容在滚动的时候不显示，停止滚动的时候才显示
                            // var icon_box = dvui.box(@src(), .{ .dir = .horizontal, .equal_space = true }, .{ .gravity_y = 0.5 });
                            // defer icon_box.deinit();

                            if (dvui.buttonIcon(@src(), "copy", dvui.entypo.copy, .{}, .{}, .{
                                .id_extra = row,
                                .max_size_content = .size(.{ .w = 14, .h = 14 }),
                                .min_size_content = .{ .w = 14, .h = 14 },
                                .corners = .round(14),
                                .gravity_y = 0.5,
                            })) {
                                std.debug.print("点击了拷贝按钮\n", .{});
                                dvui.clipboardTextSet(item.value[row].path);
                            }
                        }
                    }
                    {
                        var cell = grid.cell(.{ .row = row, .col = 3 }, .{ .padding = .{ .x = 4, .w = 12 } });
                        defer cell.deinit();

                        var cache = dvui.cacheSize(@src(), .{}, .{ .id_extra = row, .expand = .both, .gravity_y = 0.5 });
                        defer cache.deinit();

                        if (cache.uncached()) {
                            if (dvui.buttonIcon(@src(), "arrow_right", dvui.entypo.arrow_right, .{}, .{}, .{
                                .id_extra = row,
                                .max_size_content = .size(.{ .w = 14, .h = 14 }),
                                .min_size_content = .{ .w = 14, .h = 14 },
                                .corners = .round(14),
                                .gravity_y = 0.5,
                            })) {
                                std.debug.print("点击了打开按钮\n", .{});

                                const current_target = try std.zig.system.resolveTargetQuery(dvui.io, try std.Target.Query.parse(.{}));

                                var cmd: []const u8 = undefined;

                                // 如果是文件则使用文件所在的目录路径
                                var directory_path = if (std.mem.cutScalarLast(u8, item.value[row].path, '/')) |v| v.@"0" else "";
                                var splat = "/";

                                if (current_target.os.tag.isDarwin()) {
                                    cmd = "/usr/bin/open";
                                } else if (current_target.os.tag.isBSD()) {
                                    cmd = "xdg-open";
                                } else if (std.mem.eql(u8, current_target.os.tag.exeFileExt(std.Target.Cpu.Arch.x86_64), ".exe")) {
                                    cmd = "C:\\Windows\\explorer.exe";
                                    directory_path = if (std.mem.cutScalarLast(u8, item.value[row].path, '\\')) |v| v.@"0" else "";
                                    splat = "\\";
                                } else {
                                    cmd = "";
                                }

                                const absolute_path = try gpa.alloc(u8, item.key.len + 1 + directory_path.len);

                                @memcpy(absolute_path[0..item.key.len], item.key);
                                @memcpy(absolute_path[item.key.len .. item.key.len + 1], splat);
                                @memcpy(absolute_path[item.key.len + 1 ..], directory_path);

                                std.debug.print("{s} ||| {s}\n--{s}\n", .{ item.value[row].path, directory_path, absolute_path });

                                var child = try std.process.spawn(dvui.io, .{ .argv = &.{ cmd, absolute_path } });
                                _ = try child.wait(dvui.io);
                            }
                        }
                    }
                }

                try expander_collapsed_map.put(gpa, index, false);
            } else {
                try expander_collapsed_map.put(gpa, index, true);
            }
        }
    }

    return null;
}

/// 匹配到搜索文本的自定义类型
pub const Matched = struct {
    /// 实体路径
    path: []const u8,
    /// 实体类型
    kind: std.Io.File.Kind,
};

/// 遍历指定的目录，返回路径匹配到搜索文本的自定义实体动态数组
pub fn travers(alloc: std.mem.Allocator, io: std.Io, text: []const u8, dir_paths: [][]const u8, data_map: *std.StringArrayHashMapUnmanaged([]Matched)) !void {
    for (dir_paths) |dir_path| {
        var matched_list = std.ArrayList(Matched).empty;
        const root_dir = try std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true });
        defer root_dir.close(io);

        var walker = try root_dir.walk(alloc);
        defer walker.deinit();

        while (true) {
            if (try walker.next(io)) |item| {
                const match = std.mem.find(u8, item.basename, text);

                if (match) |_| {
                    const item_path = try alloc.dupe(u8, item.path);
                    // const item_path = item.path;
                    const item_kind = item.kind;
                    try matched_list.append(alloc, Matched{ .path = item_path, .kind = item_kind });
                }
            } else {
                break;
            }
        }

        if (matched_list.items.len > 0) {
            try data_map.put(alloc, dir_path, matched_list.items);
        }
    }
}
