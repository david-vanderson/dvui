const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const ScrollInfo = dvui.ScrollInfo;
const Size = dvui.Size;
const Widget = dvui.Widget;
const WidgetData = dvui.WidgetData;
const ScrollAreaWidget = dvui.ScrollAreaWidget;
const TextEntryWidget = dvui.TextEntryWidget;

pub fn NumberEntryWidget(comptime T: type) type {
    return struct {
        wd: WidgetData = undefined,
        text_box: dvui.TextEntryWidget = undefined,
        init_opts: InitOptions,
        src: std.builtin.SourceLocation,

        pub const InitOptions =
            struct {
            buffer: []u8,
            min: ?T = null,
            max: ?T = null,
        };

        const base_filter = "abcdfghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ`~!@#$%^&*()_=[{]}\\|;:'\",<>/?] ";
        const filter = switch (@typeInfo(T)) {
            .Int => |int| switch (int.signedness) {
                .signed => base_filter ++ ".e",
                .unsigned => base_filter ++ "+-.e",
            },
            .Float => base_filter,
            else => unreachable,
        };

        pub fn drawBackground(self: *@This()) !void {
            try self.wd.borderAndBackground(.{});
        }

        pub fn widget(self: *@This()) Widget {
            return Widget.init(self, data, rectFor, screenRectScale, minSizeForChild, processEvent);
        }

        pub fn data(self: *@This()) *WidgetData {
            return &self.wd;
        }

        pub fn rectFor(self: *@This(), id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
            return dvui.placeIn(self.wd.contentRect().justSize(), dvui.minSize(id, min_size), e, g);
        }

        pub fn screenRectScale(self: *@This(), rect: Rect) RectScale {
            return self.wd.contentRectScale().rectToRectScale(rect);
        }

        pub fn minSizeForChild(self: *@This(), s: Size) void {
            self.wd.minSizeMax(self.wd.padSize(s));
        }

        pub fn processEvent(self: *@This(), e: *Event, bubbling: bool) void {
            _ = bubbling;
            if (e.bubbleable()) {
                self.wd.parent.processEvent(e, true);
            }
        }

        pub fn install(self: *@This()) !void {
            try self.wd.register();

            if (self.wd.visible()) {
                try dvui.tabIndexSet(self.wd.id, self.wd.options.tab_index);
            }

            dvui.parentSet(self.widget());

            try self.wd.borderAndBackground(.{});

            self.text_box = TextEntryWidget.init(self.src, .{ .text = self.init_opts.buffer }, .{ .id_extra = 1 });
            try self.text_box.install();

            var buffer_backup: [256]u8 = .{0} ** 256;
            std.mem.copyForwards(u8, &buffer_backup, self.getText());

            self.text_box.processEvents();

            for (std.mem.sliceTo(filter, 0), 0..) |_, i| {
                self.text_box.filterOut(filter[i..][0..1]);
            }

            const text = self.getText();
            if (text.len >= 2) {
                _ = self.getValue() catch {
                    std.mem.copyForwards(u8, text, buffer_backup[0..text.len]);
                };
            }

            try self.text_box.draw();

            const borderClip = dvui.clipGet();
            dvui.clipSet(borderClip);
        }

        pub fn getText(self: *const @This()) []u8 {
            return std.mem.sliceTo(self.text_box.init_opts.text, 0);
        }

        pub fn getValue(self: *const @This()) !T {
            return switch (@typeInfo(T)) {
                .Int => try std.fmt.parseInt(T, self.getText(), 10),
                .Float => try std.fmt.parseFloat(T, self.getText()),
                else => unreachable,
            };
        }

        pub fn init(
            src: std.builtin.SourceLocation,
            init_opts: InitOptions,
            options: Options,
        ) !@This() {
            var self = @This(){ .init_opts = init_opts, .src = src };
            self.wd = WidgetData.init(src, .{}, options);

            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.text_box.deinit();
            self.wd.minSizeSetAndRefresh();
            self.wd.minSizeReportToParent();
            dvui.parentReset(self.wd.id, self.wd.parent);
        }
    };
}
