/// ![image](Examples-icon_browser.png)
pub fn iconBrowser(src: std.builtin.SourceLocation, show_flag: *bool, comptime icon_decl_name: []const u8, comptime icon_decl: type) void {
    const num_icons = @typeInfo(icon_decl).@"struct".decls.len;
    const Settings = struct {
        icon_size: f32 = 20,
        icon_rgb: dvui.Color = .black,
        row_height: f32 = 0,
        num_rows: u32 = num_icons,
        search: [64:0]u8 = @splat(0),
    };

    const icon_names: [num_icons][]const u8 = blk: {
        var blah: [num_icons][]const u8 = undefined;
        inline for (@typeInfo(icon_decl).@"struct".decls, 0..) |d, i| {
            blah[i] = d.name;
        }
        break :blk blah;
    };

    const icon_fields: [num_icons][]const u8 = blk: {
        var blah: [num_icons][]const u8 = undefined;
        inline for (@typeInfo(icon_decl).@"struct".decls, 0..) |d, i| {
            blah[i] = @field(icon_decl, d.name);
        }
        break :blk blah;
    };

    var vp = dvui.virtualParent(src, .{});
    defer vp.deinit();

    var fwin = dvui.floatingWindow(@src(), .{ .open_flag = show_flag }, .{ .min_size_content = .{ .w = 300, .h = 400 } });
    defer fwin.deinit();
    fwin.dragAreaSet(dvui.windowHeader("Icon Browser " ++ icon_decl_name, "", show_flag));

    var settings: *Settings = dvui.dataGetPtrDefault(null, fwin.data().id, "settings", Settings, .{});

    _ = dvui.sliderEntry(@src(), "size: {d:0.0}", .{ .value = &settings.icon_size, .min = 1, .max = 100, .interval = 1 }, .{ .expand = .horizontal });
    _ = styling.rgbSliders(@src(), &settings.icon_rgb, .{});

    const search = dvui.textEntry(@src(), .{ .text = .{ .buffer = &settings.search }, .placeholder = "Search..." }, .{ .expand = .horizontal });
    const filter = search.getText();
    search.deinit();

    const height = @as(f32, @floatFromInt(settings.num_rows)) * settings.row_height;

    // we won't have the height the first frame, so always set it
    var scroll_info: ScrollInfo = .{ .vertical = .given };
    if (dvui.dataGet(null, fwin.data().id, "scroll_info", ScrollInfo)) |si| {
        scroll_info = si;
        scroll_info.virtual_size.h = height;
    }
    defer dvui.dataSet(null, fwin.data().id, "scroll_info", scroll_info);

    var scroll = dvui.scrollArea(@src(), .{ .scroll_info = &scroll_info }, .{ .expand = .both });
    defer scroll.deinit();

    const visibleRect = scroll.si.viewport;
    var cursor: f32 = 0;
    settings.num_rows = 0;

    for (icon_names, icon_fields, 0..) |name, field, i| {
        if (std.ascii.indexOfIgnoreCase(name, filter) == null) {
            continue;
        }
        settings.num_rows += 1;

        if (cursor <= (visibleRect.y + visibleRect.h) and (cursor + settings.row_height) >= visibleRect.y) {
            const r = Rect{ .x = 0, .y = cursor, .w = 0, .h = settings.row_height };
            var iconbox = dvui.box(@src(), .horizontal, .{ .id_extra = i, .expand = .horizontal, .rect = r });

            var buf: [100]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, icon_decl_name ++ ".{s}", .{name}) catch "<Too much text>";
            if (dvui.buttonIcon(
                @src(),
                text,
                field,
                .{},
                .{},
                .{
                    .min_size_content = .{ .h = settings.icon_size },
                    .color_text = .{ .color = settings.icon_rgb },
                },
            )) {
                dvui.clipboardTextSet(text);
                var buf2: [100]u8 = undefined;
                const toast_text = std.fmt.bufPrint(&buf2, "Copied \"{s}\"", .{text}) catch "Copied <Too much text>";
                dvui.toast(@src(), .{ .message = toast_text });
            }
            dvui.labelNoFmt(@src(), text, .{}, .{ .gravity_y = 0.5 });

            const iconboxId = iconbox.data().id;

            iconbox.deinit(); // this calculates iconbox min size

            settings.row_height = dvui.minSizeGet(iconboxId).?.h;
        }

        cursor += settings.row_height;
    }
}

const std = @import("std");
const dvui = @import("../dvui.zig");
const Rect = dvui.Rect;
const ScrollInfo = dvui.ScrollInfo;
const styling = @import("styling.zig");
