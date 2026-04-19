/// This Struct is a helper to make animations in dvui.
/// This integrates Widget level events with animation system which used to be separate.
/// Individual widgets will have to call `AnimationRunner` and fetch it from the current window in the draw function.
/// See `animation` and `animationGet` for more information
const std = @import("std");
const dvui = @import("dvui.zig");

/// This is provided to the per frame function.
ptr: *anyopaque,
/// This field is not used in internal logic in the `AnimationRunner` and is used to provide context
/// to whatever function running this animation.
kind: Kind,
/// The duration of the animation, this value is duplicated with the one of the Animation
duration: f32,
/// The function that gets executed every animation frame
Fn: AnimationFrame,
/// The Id to get the animation every frame
id: dvui.Id,
/// The animation name to get the animation every frame
animation: []const u8,

const AnimationRunner = @This();

pub const AnimationFrame = *const fn (*anyopaque, f32) void;

pub const Kind = enum {
    hover,
    click,
    start,
    end,
};

pub const InitOptions = struct { ptr: *anyopaque, kind: Kind, duration: f32, Fn: AnimationFrame, id_extra: usize = 0, name: []const u8 };

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions) AnimationRunner {
    dvui.animation(dvui.Id.extendId(null, src, init_opts), init_opts.name, dvui.Animation{});
    return .{
        .ptr = init_opts.ptr,
        .kind = init_opts.kind,
        .duration = init_opts.duration,
        .Fn = init_opts.Fn,
        .animation = init_opts.name,
    };
}

pub fn next(self: *AnimationRunner) bool {
    const a = dvui.animationGet(self.id, self.animation) orelse unreachable;
    const done = a.value() < self.duration;
    if (done) return true;
    self.Fn(self.ptr, a);
    return done;
}

pub fn animationGet(self: *AnimationRunner) ?dvui.Animation {
    return dvui.animationGet(self.id, self.animation);
}
