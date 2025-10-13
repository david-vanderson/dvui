const std = @import("std");
const dvui = @import("../dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;

const LabelWidget = @This();

pub var defaults: Options = .{
    .name = "Label",
    .role = .label,
    .padding = Rect.all(6),
};

pub const InitOptions = struct {
    align_x: f32 = 0,
    align_y: f32 = 0,
    ellipsize: bool = true,

    pub fn gravityGet(self: InitOptions) Options.Gravity {
        return .{ .x = self.align_x, .y = self.align_y };
    }
};

wd: WidgetData,
label_str: []const u8,
/// An allocator to free `label_str` on `deinit`
allocator: ?std.mem.Allocator,
init_options: InitOptions,

pub fn init(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, init_opts: InitOptions, opts: Options) LabelWidget {
    comptime if (!std.unicode.utf8ValidateSlice(fmt)) @compileError("Format strings must be valid utf-8");

    const cw = dvui.currentWindow();
    // Validate utf8 formatting
    const str, const alloc = blk: {
        const str = std.fmt.allocPrint(cw.lifo(), fmt, args) catch |err| {
            const newid = dvui.parentGet().extendId(src, opts.idExtra());
            dvui.logError(@src(), err, "id {x} (highlighted in red) could not print its content", .{newid});
            dvui.currentWindow().debug.widget_id = newid;
            break :blk .{ fmt, null };
        };
        // We need to use `long_term_arena` because otherwise we
        // will not be able to free the memory of the allocPrint
        const utf8 = dvui.toUtf8(cw.arena(), str) catch |err| {
            const newid = dvui.parentGet().extendId(src, opts.idExtra());
            dvui.logError(@src(), err, "id {x} (highlighted in red) could not allocate valid utf8 slice", .{newid});
            dvui.currentWindow().debug.widget_id = newid;
            // We contained invalid utf8, so textSize will fail later
            break :blk .{ str, cw.lifo() };
        };
        if (str.ptr == utf8.ptr) break :blk .{ str, cw.lifo() };
        cw.lifo().free(str);
        dvui.log.debug("LabelWidget format output was invalid utf8 for {s} with '{any}'.", .{ fmt, args });
        break :blk .{ utf8, null };
    };
    return initNoFmtAllocator(src, str, alloc, init_opts, opts);
}

pub fn initNoFmt(src: std.builtin.SourceLocation, label_str: []const u8, init_opts: InitOptions, opts: Options) LabelWidget {
    const arena = dvui.currentWindow().lifo();
    // If the allocation fails, the textSize will be incorrect
    // later because of invalid utf8
    const str = dvui.toUtf8(arena, label_str) catch |err| blk: {
        logAndHighlight(src, opts, err);
        break :blk label_str;
    };
    return initNoFmtAllocator(src, str, if (str.ptr != label_str.ptr) arena else null, init_opts, opts);
}

/// The `allocator` argument will be used to deallocator `label_str` on
/// when `deinit` is called.
///
/// Assumes the label_str is valid utf8
pub fn initNoFmtAllocator(src: std.builtin.SourceLocation, label_str: []const u8, allocator: ?std.mem.Allocator, init_opts: InitOptions, opts: Options) LabelWidget {
    const options = defaults.override(opts);
    var size = options.fontGet().textSize(label_str);
    size = Size.max(size, options.min_size_contentGet());
    return .{
        .wd = .init(src, .{}, options.override(.{ .min_size_content = size })),
        .init_options = init_opts,
        .label_str = label_str,
        .allocator = allocator,
    };
}

fn logAndHighlight(src: std.builtin.SourceLocation, opts: Options, err: anyerror) void {
    const newid = dvui.parentGet().extendId(src, opts.idExtra());
    dvui.currentWindow().debug.widget_id = newid;
    dvui.log.err("{s}:{d} LabelWidget id {x} (highlighted in red) init() got {any}", .{ src.file, src.line, newid, err });
}

pub fn data(self: *LabelWidget) *WidgetData {
    return self.wd.validate();
}

pub fn install(self: *LabelWidget) void {
    self.data().register();
    self.data().borderAndBackground(.{});

    if (self.data().accesskit_node()) |ak_node| {
        const str = dvui.currentWindow().arena().dupeZ(u8, self.label_str) catch "";
        defer dvui.currentWindow().arena().free(str);
        dvui.AccessKit.nodeSetValue(ak_node, str);
        if (self.data().options.label == null) {
            dvui.AccessKit.nodeSetLabel(ak_node, str);
        }
    }
}

pub fn draw(self: *LabelWidget) void {
    const label_gravity = self.init_options.gravityGet();
    const rect = dvui.placeIn(self.data().contentRect(), self.data().options.min_size_contentGet(), .none, label_gravity);
    var rs = self.data().parent.screenRectScale(rect);
    const oldclip = dvui.clip(rs.r);
    var iter = std.mem.splitScalar(u8, self.label_str, '\n');
    var line_height_adj: f32 = undefined;
    var first: bool = true;
    while (iter.next()) |line_slice| {
        if (first) {
            line_height_adj = self.data().options.fontGet().textHeight() * (self.data().options.fontGet().line_height_factor - 1.0);
            first = false;
        } else {
            rs.r.y += rs.s * line_height_adj;
        }

        var line = line_slice;
        var tsize = self.data().options.fontGet().textSize(line);

        // this is only about horizontal direction
        var lineRect = dvui.placeIn(self.data().contentRect(), tsize, .none, label_gravity);

        const ellip = "...";
        var ellipsize = false;
        // give ourselves a fraction of a pixel extra for floating point innacurracies:
        // - a lot of times the content Rect is sized based on the text width
        if (self.init_options.ellipsize and tsize.w > (self.data().contentRect().w + 0.001)) {
            ellipsize = true;
            const esize = self.data().options.fontGet().textSize(ellip);
            var endi: usize = 0;
            tsize = self.data().options.fontGet().textSizeEx(line, .{ .max_width = self.data().contentRect().w - esize.w, .end_idx = &endi });
            line = line[0..endi];
            lineRect = dvui.placeIn(self.data().contentRect(), tsize, .none, .{ .x = 0, .y = 0 });
        }

        const liners = self.data().parent.screenRectScale(lineRect);

        rs.r.x = liners.r.x;
        dvui.renderText(.{
            .font = self.data().options.fontGet(),
            .text = line,
            .rs = rs,
            .color = self.data().options.color(.text),
        }) catch |err| {
            dvui.logError(@src(), err, "Failed to render text: {s}", .{line});
        };

        if (ellipsize) {
            rs.r.x += liners.r.w;
            dvui.renderText(.{
                .font = self.data().options.fontGet(),
                .text = ellip,
                .rs = rs,
                .color = self.data().options.color(.text),
            }) catch |err| {
                dvui.logError(@src(), err, "Failed to render ellipses after text: {s}", .{line});
            };
        }

        rs.r.y += rs.s * tsize.h;
    }
    dvui.clipSet(oldclip);
}

pub fn matchEvent(self: *LabelWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn deinit(self: *LabelWidget) void {
    const should_free = self.data().was_allocated_on_widget_stack;
    defer if (should_free) dvui.widgetFree(self);
    defer self.* = undefined;
    if (self.allocator) |alloc| alloc.free(self.label_str);
    self.data().minSizeSetAndRefresh();
    self.data().minSizeReportToParent();
}

test {
    @import("std").testing.refAllDecls(@This());
}
