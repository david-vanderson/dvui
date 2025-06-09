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
    .padding = Rect.all(6),
};

wd: WidgetData = undefined,
label_str: []const u8,
/// An allocator to free `label_str` on `deinit`
allocator: ?std.mem.Allocator,

pub fn init(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, opts: Options) LabelWidget {
    comptime if (!std.unicode.utf8ValidateSlice(fmt)) @compileError("Format strings must be valid utf-8");

    const cw = dvui.currentWindow();
    // Validate utf8 formatting
    const str, const alloc = blk: {
        const str = std.fmt.allocPrint(cw.arena(), fmt, args) catch |err| {
            logAndHighlight(src, opts, err);
            break :blk .{ fmt, null };
        };
        // We need to use `long_term_arena` because otherwise we
        // will not be able to free the memory of the allocPrint
        const utf8 = dvui.toUtf8(cw.long_term_arena(), str) catch |err| {
            logAndHighlight(src, opts, err);
            // We contained invalid utf8, so textSize will fail later
            break :blk .{ str, cw.arena() };
        };
        if (str.ptr == utf8.ptr) break :blk .{ str, cw.arena() };
        cw.arena().free(str);
        dvui.log.debug("{s}:{d}: LabelWidget format output was invalid utf8 for '{s}'.", .{ src.file, src.line, str });
        break :blk .{ utf8, null };
    };
    return initNoFmtAllocator(src, str, alloc, opts);
}

pub fn initNoFmt(src: std.builtin.SourceLocation, label_str: []const u8, opts: Options) LabelWidget {
    const arena = dvui.currentWindow().arena();
    // If the allocation fails, the textSize will be incorrect
    // later because of invalid utf8
    const str = dvui.toUtf8(arena, label_str) catch |err| blk: {
        logAndHighlight(src, opts, err);
        break :blk label_str;
    };
    return initNoFmtAllocator(src, str, if (str.ptr != label_str.ptr) arena else null, opts);
}

/// The `allocator` argument will be used to deallocator `label_str` on
/// when `deinit` is called.
///
/// Assumes the label_str is valid utf8
pub fn initNoFmtAllocator(src: std.builtin.SourceLocation, label_str: []const u8, allocator: ?std.mem.Allocator, opts: Options) LabelWidget {
    const options = defaults.override(opts);
    var size = options.fontGet().textSize(label_str);
    size = Size.max(size, options.min_size_contentGet());
    return .{
        .wd = .init(src, .{}, options.override(.{ .min_size_content = size })),
        .label_str = label_str,
        .allocator = allocator,
    };
}

fn logAndHighlight(src: std.builtin.SourceLocation, opts: Options, err: anyerror) void {
    const newid = dvui.parentGet().extendId(src, opts.idExtra());
    dvui.currentWindow().debug_widget_id = newid;
    dvui.log.err("{s}:{d} LabelWidget id {x} (highlighted in red) init() got {!}", .{ src.file, src.line, newid, err });
}

pub fn data(self: *LabelWidget) *WidgetData {
    return &self.wd;
}

pub fn install(self: *LabelWidget) !void {
    self.wd.register();
    try self.wd.borderAndBackground(.{});
}

pub fn draw(self: *LabelWidget) !void {
    const rect = dvui.placeIn(self.wd.contentRect(), self.wd.options.min_size_contentGet(), .none, self.wd.options.gravityGet());
    var rs = self.wd.parent.screenRectScale(rect);
    const oldclip = dvui.clip(rs.r);
    var iter = std.mem.splitScalar(u8, self.label_str, '\n');
    var line_height_adj: f32 = undefined;
    var first: bool = true;
    while (iter.next()) |line| {
        if (first) {
            line_height_adj = self.wd.options.fontGet().textHeight() * (self.wd.options.fontGet().line_height_factor - 1.0);
            first = false;
        } else {
            rs.r.y += rs.s * line_height_adj;
        }

        const tsize = self.wd.options.fontGet().textSize(line);
        const lineRect = dvui.placeIn(self.wd.contentRect(), tsize, .none, self.wd.options.gravityGet());
        const liners = self.wd.parent.screenRectScale(lineRect);

        rs.r.x = liners.r.x;
        try dvui.renderText(.{
            .font = self.wd.options.fontGet(),
            .text = line,
            .rs = rs,
            .color = self.wd.options.color(.text),
            .debug = self.wd.options.debugGet(),
        });
        rs.r.y += rs.s * tsize.h;
    }
    dvui.clipSet(oldclip);
}

pub fn matchEvent(self: *LabelWidget, e: *Event) bool {
    return dvui.eventMatchSimple(e, self.data());
}

pub fn processEvents(self: *LabelWidget) void {
    const evts = dvui.events();
    for (evts) |*e| {
        if (!self.matchEvent(e))
            continue;

        self.processEvent(e, false);
    }
}

pub fn processEvent(self: *LabelWidget, e: *Event, bubbling: bool) void {
    _ = bubbling;

    if (e.bubbleable()) {
        self.wd.parent.processEvent(e, true);
    }
}

pub fn deinit(self: *LabelWidget) void {
    defer dvui.widgetFree(self);
    if (self.allocator) |alloc| alloc.free(self.label_str);
    self.wd.minSizeSetAndRefresh();
    self.wd.minSizeReportToParent();
    self.* = undefined;
}

test {
    @import("std").testing.refAllDecls(@This());
}
