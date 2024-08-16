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

            pub fn audit(self: InitOptions) void {
                if (self.max != null and self.min != null) {
                    std.debug.assert(self.max.? > self.min.?);
                }
            }
        };

        const base_filter = "1234567890";
        const filter = switch (@typeInfo(T)) {
            .Int => |int| switch (int.signedness) {
                .signed => base_filter ++ "+-",
                .unsigned => base_filter,
            },
            .Float => base_filter ++ "+-.",
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

            try self.wd.borderAndBackground(.{});

            self.text_box = TextEntryWidget.init(self.src, .{ .text = self.init_opts.buffer }, .{ .id_extra = 1 });
            try self.text_box.install();

            var buffer_backup: [256]u8 = .{0} ** 256;
            @memcpy(&buffer_backup, self.init_opts.buffer);

            self.text_box.processEvents();

            self.text_box.filterIn(filter);

            var valid: bool = true;
            const text = self.text_box.getText();
            const value = self.getValue();
            if (@typeInfo(T) == .Int) {
                if (value) |num| {
                    if (self.init_opts.min) |min| {
                        if (num < min) {
                            @memcpy(self.init_opts.buffer, &buffer_backup);
                            self.text_box.filterIn(filter);
                        }
                    }
                    if (self.init_opts.max) |max| {
                        if (num > max) {
                            @memcpy(self.init_opts.buffer, &buffer_backup);
                            self.text_box.filterIn(filter);
                        }
                    }
                } else if (text.len >= 2) {
                    @memcpy(self.init_opts.buffer, &buffer_backup);

                    self.text_box.filterIn(filter);
                }
            } else if (@typeInfo(T) == .Float) {
                if (value) |num| {
                    if (self.init_opts.min) |min| {
                        if (num < min) {
                            valid = false;
                        }
                    }
                    if (self.init_opts.max) |max| {
                        if (num > max) {
                            valid = false;
                        }
                    }
                } else if (text.len >= 2) {
                    valid = false;
                }
            }

            try self.text_box.draw();

            const borderClip = dvui.clipGet();
            dvui.clipSet(borderClip);

            if (!valid) {
                const rs = self.text_box.data().borderRectScale();
                try dvui.pathAddRect(rs.r, self.text_box.data().options.corner_radiusGet());
                const color = dvui.themeGet().color_err;
                try dvui.pathStrokeAfter(true, true, 1 * rs.s, .none, color);
            }
        }

        pub fn getValue(self: *const @This()) ?T {
            return switch (@typeInfo(T)) {
                .Int => std.fmt.parseInt(T, self.text_box.getText(), 10) catch null,
                .Float => std.fmt.parseFloat(T, self.text_box.getText()) catch null,
                else => unreachable,
            };
        }

        pub fn init(
            src: std.builtin.SourceLocation,
            init_opts: InitOptions,
            options: Options,
        ) !@This() {
            init_opts.audit();
            var self = @This(){ .init_opts = init_opts, .src = src };
            self.wd = WidgetData.init(src, .{}, options);

            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.text_box.deinit();
            self.wd.minSizeSetAndRefresh();
            self.wd.minSizeReportToParent();
        }
    };
}
