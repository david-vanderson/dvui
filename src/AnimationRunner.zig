//! `AnimationRunner` is a high-level helper that ties dvui's low-level animation
//! system to widget events (hover, click, or on-start), handling forward/backward
//! playback, interruption, and frame callbacks automatically.
//!
//! ## Usage
//! ```zig
//! // In your widget's draw function, every frame:
//! var anim = AnimationRunner.init(@src(), &my_widget.wd, .{
//!     .ptr  = &my_state,
//!     .kind = .hover,
//!     .duration = 200,
//!     .Fn   = myFrameCallback,
//!     .name = "my_anim",
//! });
//! anim.next();
//! ```
//! The callback receives a value in [0, 1] every frame the animation is running.
//! 0 = start / fully reversed, 1 = fully forward.

const std = @import("std");
const dvui = @import("dvui.zig");

const AnimationRunner = @This();

// ── Configuration (set once at init, never changed) ──────────────────────────

/// Passed as the first argument to `frameFn` every animated frame.
/// May be null if your callback does not need context.
ptr: ?*anyopaque,

/// What event drives the animation.
kind: Kind,

/// Called every frame the animation is running (forward or backward),
/// and once more with `0.0` when a backward animation finishes.
/// Signature: `fn (ctx: ?*anyopaque, value: f32) void`
frameFn: ?Frame = null,

/// Key string used to store the animation in dvui's window-level map.
/// Must be unique per widget if a widget runs multiple animations.
animation: []const u8,

/// The widget whose rect and events are used to drive the animation.
owner: *const dvui.WidgetData,

/// Source location used to derive a stable dvui ID for this animation.
src: std.builtin.SourceLocation,

/// How long the full forward (or backward) pass takes, in microseconds.
duration: i32 = 200,

/// Easing function applied to the raw linear time progress.
easing: *const dvui.easing.EasingFn = dvui.easing.linear,

/// Current playback status.
status: Status = .off,

/// Status from the previous frame, used to detect transitions.
status_prev: Status = .off,

/// Current animation value in [0, 1].
/// 0 = start / fully reversed, 1 = fully forward.
current_value: f32 = 0.0,

/// How many milliseconds into the animation we currently are.
/// Stored so that interrupted animations can reverse from their
/// current position rather than snapping to an end.
elapsed: i32 = 0,

/// Incremented whenever an in-progress animation is interrupted,
/// so a fresh dvui animation ID is used and the old one is discarded.
id_extra: usize,

/// The computed dvui ID for the current animation run.
id: dvui.Id,

// Per-frame event scratch (reset each call to next())

hovered: bool = false,
clicked: bool = false,

/// Callback type. `value` is in [0, 1].
pub const Frame = *const fn (ctx: ?*anyopaque, value: f32) void;

/// What event triggers the animation.
pub const Kind = enum {
    /// Animates forward while the mouse is over `owner`, backward when it leaves.
    hover,
    /// Animates forward while `owner` is captured (held), backward on release.
    click,
    /// Animates forward once on the first call to `next()`, never reverses.
    start,
    /// Infinately looping animations
    looping,
};

pub const Status = enum {
    /// Playing forward toward 1.0.
    forward,
    /// Fully forward (value == 1.0), waiting for the trigger to go away
    /// before starting the backward pass. No animation frames are generated.
    backward_ready,
    /// Playing backward toward 0.0.
    backward,
    /// Idle at 0.0. No animation frames are generated.
    off,
};

pub const InitOptions = struct {
    ptr: ?*anyopaque,
    kind: Kind,
    /// Full one-way duration in seconds.
    duration: f32,
    Fn: ?Frame = null,
    /// Extra integer mixed into the dvui ID. Use when the same `@src()`
    /// creates multiple `AnimationRunner`s (e.g. inside a loop).
    id_extra: usize = 0,
    /// Key for dvui's animation store. Must be unique per widget per animation.
    name: []const u8,
    easing: *const dvui.easing.EasingFn = dvui.easing.linear,
};

pub fn init(
    src: std.builtin.SourceLocation,
    owner: *const dvui.WidgetData,
    init_opts: InitOptions,
) AnimationRunner {
    return .{
        .ptr = init_opts.ptr,
        .kind = init_opts.kind,
        .frameFn = init_opts.Fn,
        .animation = init_opts.name,
        .owner = owner,
        .duration = @intFromFloat(init_opts.duration * std.time.ms_per_s * 1000),
        .src = src,
        .id_extra = init_opts.id_extra,
        .id = dvui.Id.extendId(null, src, init_opts.id_extra),
        .easing = init_opts.easing,
    };
}

/// Advance the animation by one frame. Call this every frame inside your
/// widget's draw function, after the widget has been laid out so that
/// `owner.rectScale()` returns a valid rect.
pub fn next(self: *AnimationRunner) void {
    if (self.frameFn == null) @panic("frameFn is null");
    self.value();
    self.frameFn.?(self.ptr, self.current_value);
}

pub fn value(self: *AnimationRunner) f32 {
    defer self.status_prev = self.status;

    if (self.kind != .start) self.sampleEvents();

    self.status = self.nextStatus();

    self.supplyAnimation();

    const a = dvui.animationGet(self.id, self.animation) orelse return self.current_value;

    self.current_value = a.value();
    // Convert normalised value back to milliseconds so we know how far
    // through the animation we are. This is used to start a reverse pass
    // from the current position when the animation is interrupted.
    self.elapsed = self.duration - @min(a.end_time, 0);

    if (self.kind == .start) return self.current_value; // .start never reverses, nothing left to do.

    if ((self.status == .backward or self.kind == .looping) and a.done())
        self.reset()
    else if (self.status == .forward and a.done()) {
        // Sit in backward_ready until the trigger goes away.
        self.status = .backward_ready;
    }

    dvui.refresh(null, @src(), self.owner.id);
    return self.current_value;
}

/// Read mouse events and update `hovered` / `clicked` for this frame.
fn sampleEvents(self: *AnimationRunner) void {
    // Find the first mouse event this frame to get the current pointer position.
    const mouse_pos = for (dvui.events()) |e| {
        if (e.evt == .mouse) break e.evt.mouse.p;
    } else {
        self.hovered = false;
        self.clicked = false;
        return;
    };

    self.hovered = self.owner.rectScale().r.contains(mouse_pos);
    self.clicked = dvui.captured(self.owner.id);
}

/// Pure function: given current state + inputs, return the next status.
fn nextStatus(self: *const AnimationRunner) Status {
    const triggered = switch (self.kind) {
        .hover => self.hovered,
        .click => self.clicked,
        .start, .looping => true,
    };

    return switch (self.kind) {
        .start, .looping => .forward,
        .hover, .click => if (triggered) switch (self.status) {
            // Stay in backward_ready while triggered don't restart
            // the forward animation if we never left.
            .backward_ready => .backward_ready,
            else => .forward,
        } else switch (self.status) {
            // Trigger just released: begin reversing.
            .forward, .backward_ready => .backward,
            // Already reversing or idle: keep current state.
            else => self.status,
        },
    };
}

/// If the status just transitioned to `.forward` or `.backward`, register
/// a new dvui animation starting from the current value/position.
fn supplyAnimation(self: *AnimationRunner) void {
    const starting_forward = self.status == .forward and self.status_prev != .forward;
    const starting_backward = self.status == .backward and self.status_prev != .backward;
    if (!starting_forward and !starting_backward) return;

    // If we are interrupting an animation that was already playing in the
    // opposite direction, mint a fresh ID so dvui treats this as a new
    // animation rather than continuing the old one.
    const was_playing = self.status_prev == .forward or self.status_prev == .backward;
    if (was_playing) {
        self.id_extra += 1;
        self.id = dvui.Id.extendId(null, self.src, self.id_extra);
    }

    // When reversing, play only for as long as we have already played
    // forward, so the speed feels symmetrical.
    const end_time_ms: i32 = if (starting_backward) self.elapsed else self.duration;

    dvui.animation(self.id, self.animation, .{
        .start_val = self.current_value,
        .end_val = if (starting_backward) 0.0 else 1.0,
        .start_time = 0,
        .end_time = end_time_ms,
        .easing = self.easing,
    });
}

/// Reset all runtime state to idle. Does not touch configuration fields.
pub fn reset(self: *AnimationRunner) void {
    self.status = .off;
    self.status_prev = .off;
    self.hovered = false;
    self.clicked = false;
    self.current_value = 0.0;
    self.elapsed = 0.0;
}
