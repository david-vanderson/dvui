const std = @import("std");
const dvui = @import("dvui.zig");

const Event = dvui.Event;
const Options = dvui.Options;
const Rect = dvui.Rect;
const RectScale = dvui.RectScale;
const Size = dvui.Size;
const WidgetData = dvui.WidgetData;
const Id = dvui.Id;

const Widget = @This();

ptr: *anyopaque,
vtable: *const VTable,

const VTable = struct {
    data: *const fn (ptr: *anyopaque) *WidgetData,
    rectFor: *const fn (ptr: *anyopaque, id: Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect,
    screenRectScale: *const fn (ptr: *anyopaque, r: Rect) RectScale,
    minSizeForChild: *const fn (ptr: *anyopaque, s: Size) void,
};

pub fn init(
    pointer: anytype,
    comptime dataFn: fn (ptr: @TypeOf(pointer)) *WidgetData,
    comptime rectForFn: fn (ptr: @TypeOf(pointer), id: Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect,
    comptime screenRectScaleFn: fn (ptr: @TypeOf(pointer), r: Rect) RectScale,
    comptime minSizeForChildFn: fn (ptr: @TypeOf(pointer), s: Size) void,
) Widget {
    const Ptr = @TypeOf(pointer);
    const ptr_info = @typeInfo(Ptr);
    std.debug.assert(ptr_info == .pointer); // Must be a pointer
    std.debug.assert(ptr_info.pointer.size == .one); // Must be a single-item pointer

    const gen = struct {
        fn dataImpl(ptr: *anyopaque) *WidgetData {
            const self = @as(Ptr, @ptrCast(@alignCast(ptr)));
            return @call(.always_inline, dataFn, .{self});
        }

        fn rectForImpl(ptr: *anyopaque, id: Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
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

        const vtable = VTable{
            .data = dataImpl,
            .rectFor = rectForImpl,
            .screenRectScale = screenRectScaleImpl,
            .minSizeForChild = minSizeForChildImpl,
        };
    };

    return .{
        .ptr = pointer,
        .vtable = &gen.vtable,
    };
}

pub fn data(self: Widget) *WidgetData {
    return self.vtable.data(self.ptr).validate();
}

/// Calls `dvui.Id.extendId` on the this widgets id
pub fn extendId(self: Widget, src: std.builtin.SourceLocation, id_extra: usize) dvui.Id {
    return self.data().id.extendId(src, id_extra);
}

pub fn rectFor(self: Widget, id: Id, min_size: Size, e: Options.Expand, g: Options.Gravity) Rect {
    return self.vtable.rectFor(self.ptr, id, min_size, e, g);
}

pub fn screenRectScale(self: Widget, r: Rect) RectScale {
    return self.vtable.screenRectScale(self.ptr, r);
}

pub fn minSizeForChild(self: Widget, s: Size) void {
    self.vtable.minSizeForChild(self.ptr, s);
}

test {
    @import("std").testing.refAllDecls(@This());
}
