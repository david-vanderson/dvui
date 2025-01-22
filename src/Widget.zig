const std = @import("std");
const dvui = @import("dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;

const Widget = @This();

ptr: *anyopaque,
vtable: *const VTable,

const VTable = struct {
    data: *const fn (ptr: *anyopaque) *WidgetData,
    rectFor: *const fn (ptr: *anyopaque, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect,
    screenRectScale: *const fn (ptr: *anyopaque, r: Rect) RectScale,
    minSizeForChild: *const fn (ptr: *anyopaque, s: Size) void,
    processEvent: *const fn (ptr: *anyopaque, e: *Event, bubbling: bool) void,
};

pub fn init(
    pointer: anytype,
    comptime dataFn: fn (ptr: @TypeOf(pointer)) *WidgetData,
    comptime rectForFn: fn (ptr: @TypeOf(pointer), id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect,
    comptime screenRectScaleFn: fn (ptr: @TypeOf(pointer), r: Rect) RectScale,
    comptime minSizeForChildFn: fn (ptr: @TypeOf(pointer), s: Size) void,
    comptime processEventFn: fn (ptr: @TypeOf(pointer), e: *Event, bubbling: bool) void,
) Widget {
    const Ptr = @TypeOf(pointer);
    const ptr_info = @typeInfo(Ptr);
    std.debug.assert(ptr_info == .pointer); // Must be a pointer
    std.debug.assert(ptr_info.pointer.size == .One); // Must be a single-item pointer

    const gen = struct {
        fn dataImpl(ptr: *anyopaque) *WidgetData {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, dataFn, .{self});
        }

        fn rectForImpl(ptr: *anyopaque, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, rectForFn, .{ self, id, min_size, e, g });
        }

        fn screenRectScaleImpl(ptr: *anyopaque, r: Rect) RectScale {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, screenRectScaleFn, .{ self, r });
        }

        fn minSizeForChildImpl(ptr: *anyopaque, s: Size) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, minSizeForChildFn, .{ self, s });
        }

        fn processEventImpl(ptr: *anyopaque, e: *Event, bubbling: bool) void {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, processEventFn, .{ self, e, bubbling });
        }

        const vtable = VTable{
            .data = dataImpl,
            .rectFor = rectForImpl,
            .screenRectScale = screenRectScaleImpl,
            .minSizeForChild = minSizeForChildImpl,
            .processEvent = processEventImpl,
        };
    };

    return .{
        .ptr = pointer,
        .vtable = &gen.vtable,
    };
}

pub fn data(self: Widget) *WidgetData {
    return self.vtable.data(self.ptr);
}

pub fn extendId(self: Widget, src: std.builtin.SourceLocation, id_extra: usize) u32 {
    var hash = dvui.fnv.init();
    hash.value = self.data().id;
    hash.update(src.file);
    hash.update(std.mem.asBytes(&src.line));
    hash.update(std.mem.asBytes(&src.column));
    hash.update(std.mem.asBytes(&id_extra));
    return hash.final();
}

pub fn rectFor(self: Widget, id: u32, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return self.vtable.rectFor(self.ptr, id, min_size, e, g);
}

pub fn screenRectScale(self: Widget, r: Rect) RectScale {
    return self.vtable.screenRectScale(self.ptr, r);
}

pub fn minSizeForChild(self: Widget, s: Size) void {
    self.vtable.minSizeForChild(self.ptr, s);
}

pub fn processEvent(self: Widget, e: *Event, bubbling: bool) void {
    self.vtable.processEvent(self.ptr, e, bubbling);
}
