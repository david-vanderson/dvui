//! Cached, downsampled "blurred backdrop" for content behind modals, floating
//! windows, or transparent bars (e.g. a nav bar over scrolling content).
//! Approximates CSS `backdrop-filter: blur(radius_px)` using a dual-Kawase
//! blur (the cheap wide-blur trick browsers/game engines use): repeated
//! halving down, then repeated doubling back up, with a multi-tap offset
//! blend at every pass.
//!
//! Unlike a live per-frame blur, this only re-captures the background when
//! it actually changed - every other frame it just redraws a small cached
//! texture (one cheap textured quad). This matters because dvui's renderer
//! is deferred: replaying a subwindow's `RenderCommand`s re-runs real glyph
//! shaping / path triangulation, not just a GPU blit, so doing it every
//! frame is a real (avoidable) CPU cost.
//!
//! Usage (bracket the background content you want blurred):
//! ```
//! const blur = dvui.BlurBackdrop.get(@src());
//! blur.init(rect, .{scroll_offset, window_w}); // witness: anything that should invalidate the cache when it changes
//! // ... draw background widgets (scroll area, page content, etc) ...
//! blur.deinit();
//! blur.draw(); // draws cached blurred texture over `rect`
//! // ... draw modal / nav bar contents on top ...
//! ```
//!
//! Cache invalidation is automatic for anything captured in `rect` and
//! `witness` (hashed and compared to the previous frame's). Call
//! `markDirty()` yourself only for changes that hash can't see, e.g. the
//! background content itself changed shape/content without `rect` or
//! `witness` changing.

const std = @import("std");
const dvui = @import("dvui.zig");

const Rect = dvui.Rect;
const Size = dvui.Size;
const Texture = dvui.Texture;

const BlurBackdrop = @This();

/// Physical-pixel rect this backdrop covers. Set by `init`.
rect: Rect.Physical = .{},
/// CSS `backdrop-filter: blur(radius_px)`-equivalent blur strength.
radius_px: f32 = 16,
/// Cached small texture, redrawn as-is on non-dirty frames.
small: ?Texture = null,
/// True until the next `deinit` runs a real capture.
dirty: bool = true,
/// Hash of the last `init`'s `rect` + `witness`, for auto-dirty.
last_hash: u64 = 0,

cmd_start: usize = undefined,
prev_rendering: bool = undefined,

/// Get the persistent `BlurBackdrop` for this call site, creating it on
/// first call. Registers its GPU-texture teardown with dvui's data store so
/// the cached texture is freed automatically once this storage key stops
/// being touched (e.g. the tab/panel it lives in closes) - unlike a bare
/// `dataGetPtrDefault`, which would otherwise silently leak `self.small`.
///
/// Safe to call every frame, any time before `init`/`deinit` - in
/// particular, before other same-frame code needs to mutate fields on the
/// returned pointer (e.g. a slider bound to `&backdrop.radius_px`).
pub fn get(src: std.builtin.SourceLocation) *BlurBackdrop {
    const id = dvui.parentGet().extendId(src, 0);
    const self = dvui.dataGetPtrDefault(null, id, "blur_backdrop", BlurBackdrop, .{});
    dvui.dataSetDeinitFunction(null, id, "blur_backdrop", &releaseTexture);
    return self;
}

/// Force a re-capture on the next `init`/`deinit` bracket, for invalidation
/// that `init`'s rect/witness hash can't see (e.g. modal reopened,
/// background content changed shape without `rect` moving).
pub fn markDirty(self: *BlurBackdrop) void {
    self.dirty = true;
}

/// Call immediately before drawing the background content that should show
/// through the blur. `witness` is anything (a value or tuple) that should
/// invalidate the cache when it changes - e.g. scroll offset, window width.
/// Cheap and safe to call every frame even when not dirty. Per-frame
/// bracket-open; does not allocate or own any resources itself (see `get`
/// for the one-time setup and `releaseTexture` for GPU teardown).
pub fn init(self: *BlurBackdrop, rect: Rect, witness: anytype) void {
    self.rect = dvui.windowRectScale().rectToPhysical(rect);

    var hasher = dvui.fnv.init();
    hasher.update(std.mem.asBytes(&rect));
    hasher.update(std.mem.asBytes(&witness));
    const h = hasher.final();
    if (h != self.last_hash) self.dirty = true;
    self.last_hash = h;

    if (!self.dirty) return;

    const cw = dvui.currentWindow();
    const sw = cw.subwindows.current() orelse &cw.subwindows.stack.items[0];
    self.cmd_start = sw.render_cmds.items.len;

    // Rendering defaults to immediate (draws straight to the current
    // target as each widget call happens), so without this the bracketed
    // draws below never get queued into `sw.render_cmds` and there's
    // nothing to replay into the offscreen texture. Force deferred mode
    // so we can replay the same commands twice below: once onscreen
    // (so the background stays visible) and once into the capture target.
    self.prev_rendering = dvui.renderingSet(false);
}

/// Call immediately after drawing the background content bracketed by
/// `init`. Re-captures + re-blurs only when dirty. Per-frame bracket-close -
/// call every frame, cheap when not dirty. Does not free the cached
/// texture; see `releaseTexture` for that.
pub fn deinit(self: *BlurBackdrop) void {
    if (!self.dirty) return;
    defer self.dirty = false;

    const cw = dvui.currentWindow();
    _ = dvui.renderingSet(self.prev_rendering);

    const sw = cw.subwindows.current() orelse &cw.subwindows.stack.items[0];
    // Left in the subwindow's normal queue (not stripped, not replayed here)
    // so they draw exactly once, in their natural queue order, via the
    // normal `Window.endRendering` deferred replay - same as any other
    // widget's deferred draws. Replaying them immediately here (as an
    // earlier version did) drew them "now" during build, which is fine at
    // top level but wrong when this widget is nested inside another
    // floating window: an enclosing background fill queued *earlier* in the
    // same subwindow only actually draws *later*, at `endRendering`, and
    // painted right over content already drawn early by an immediate
    // replay - the bracketed content (e.g. a checkerboard background)
    // vanishing behind the enclosing window every dirty frame.
    const cmds = sw.render_cmds.items[self.cmd_start..];

    var r = self.rect;
    if (r.empty()) return;
    // enlarge to pixel boundaries, same as Picture.start
    const x_start = @floor(r.x);
    const x_end = @ceil(r.x + r.w);
    r.x = x_start;
    r.w = @round(x_end - x_start);
    const y_start = @floor(r.y);
    const y_end = @ceil(r.y + r.h);
    r.y = y_start;
    r.h = @round(y_end - y_start);
    if (r.w < 1 or r.h < 1) return;

    // The rest of this function renders into offscreen targets (the full-res
    // capture, then each downsample/upsample pass) and must happen
    // immediately, not be deferred - `renderTexture` silently queues a
    // `RenderCommand` instead of drawing when `rendering` is false, which is
    // the ambient state whenever this whole widget is itself nested inside
    // another deferred floating window. Left alone, every blur pass would be
    // queued instead of drawn, its offscreen target would stay blank, and
    // `self.small` would end up fully transparent.
    const blur_prev_rendering = dvui.renderingSet(true);
    defer _ = dvui.renderingSet(blur_prev_rendering);

    // capture the bracketed commands at full res into an offscreen target.
    // Stays bound to offscreen targets for the whole downsample/upsample
    // pipeline below - restored to `prev1` (the real onscreen/window
    // target) exactly once at the end. Restoring it between passes (as a
    // naive save/restore per pass would) touches the live window target
    // once per blur pass for no reason, and on backends that clear-on-bind
    // that flashes away whatever was already drawn there - a visible
    // flicker every dirty frame (e.g. every tick while dragging the radius
    // slider).
    const full_target = dvui.textureCreateTarget(.{ .width = @intFromFloat(r.w), .height = @intFromFloat(r.h) }) catch return;
    const prev1 = dvui.renderTarget(.{ .texture = full_target, .offset = r.topLeft() });
    defer _ = dvui.renderTarget(prev1);
    cw.renderCommands(cmds) catch {};

    var cur = dvui.textureFromTarget(full_target) catch return; // destroys full_target

    // Each halving pass roughly doubles the effective blur radius in source
    // pixels, so after n halvings the total radius is ~2^n. Inverting that
    // gives the downscale factor to hit a given radius: 1/radius_px.
    // Approximate (not a real Gaussian-equivalent radius), but tracks CSS
    // intuition well enough: bigger radius looks blurrier, and doubling it
    // looks like about one more halving pass, same as the browser.
    const downscale = 1.0 / @max(1.0, self.radius_px);
    const target_w: u32 = @max(1, @as(u32, @intFromFloat(@round(r.w * downscale))));
    const target_h: u32 = @max(1, @as(u32, @intFromFloat(@round(r.h * downscale))));

    while (cur.width > target_w or cur.height > target_h) {
        const next_w = @max(target_w, cur.width / 2);
        const next_h = @max(target_h, cur.height / 2);
        const step_target = dvui.textureCreateTarget(.{ .width = next_w, .height = next_h }) catch break;
        // Switches straight from `cur`'s target to `step_target` - no need
        // to save/restore per pass, see comment above the outer `defer`.
        _ = dvui.renderTarget(.{ .texture = step_target, .offset = .{} });
        // The ambient clip rect is in window coordinates (wherever this
        // widget happens to be laid out) and is meaningless once rendering
        // targets `step_target`, whose content is addressed from (0,0) - a
        // clip that doesn't happen to cover the origin (e.g. a widget
        // scrolled/nested away from the top-left) would silently clip away
        // every tap draw below and leave `step_target` blank.
        const prev_clip = dvui.clipGet();
        dvui.clipSet(.{ .w = @floatFromInt(next_w), .h = @floatFromInt(next_h) });
        defer dvui.clipSet(prev_clip);

        // 4-tap diagonal-offset downsample, sampled further out (1.5 source
        // texels) than the ~0.5-texel implicit box a plain halving pass
        // would land on - that wider kernel is what keeps the blur
        // spreading pass over pass instead of just antialiasing. Scaled by
        // passStrength so a partial (non-halving) pass spreads less.
        const kawase_offset_texels: f32 = 1.5;
        const half_u = kawase_offset_texels * passStrength(next_w, cur.width) / @as(f32, @floatFromInt(cur.width));
        const half_v = kawase_offset_texels * passStrength(next_h, cur.height) / @as(f32, @floatFromInt(cur.height));
        const taps = [4]dvui.Point{
            .{ .x = -half_u, .y = -half_v },
            .{ .x = half_u, .y = -half_v },
            .{ .x = -half_u, .y = half_v },
            .{ .x = half_u, .y = half_v },
        };
        for (taps, 0..) |tap, i| {
            const a: f32 = 1.0 / @as(f32, @floatFromInt(i + 1));
            dvui.renderTexture(cur, .{ .r = .{ .w = @floatFromInt(next_w), .h = @floatFromInt(next_h) } }, .{
                .uv = .{ .x = tap.x, .y = tap.y, .w = 1, .h = 1 },
                .colormod = dvui.Color.white.opacity(a),
            }) catch {};
        }

        dvui.textureDestroyLater(cur);
        cur = dvui.textureFromTarget(step_target) catch break; // destroys step_target
    }

    // Upsample back to full size with progressive doubling + a wide
    // multi-tap kernel each step (real "dual Kawase" blur), instead of one
    // big bilinear stretch, which would just show the downsampled blocks.
    const final_w: u32 = @intFromFloat(r.w);
    const final_h: u32 = @intFromFloat(r.h);
    while (cur.width < final_w or cur.height < final_h) {
        const next_w = @min(final_w, cur.width * 2);
        const next_h = @min(final_h, cur.height * 2);
        const step_target = dvui.textureCreateTarget(.{ .width = next_w, .height = next_h }) catch break;
        _ = dvui.renderTarget(.{ .texture = step_target, .offset = .{} });
        // See matching comment in the downsample loop above.
        const prev_clip = dvui.clipGet();
        dvui.clipSet(.{ .w = @floatFromInt(next_w), .h = @floatFromInt(next_h) });
        defer dvui.clipSet(prev_clip);

        // 8-tap "dual filter" upsample kernel: 4 cardinal taps (weight 1)
        // plus 4 diagonal taps (weight 2), offset in units of the smaller
        // *source* texture's texel size. Composited with the same running-
        // weighted-average alpha trick as the downsample taps above
        // (alpha_i = w_i / cumulative_weight_i). Scaled by passStrength so
        // a partial (non-doubling) pass spreads less, matching the
        // downsample side.
        const ou_x = passStrength(cur.width, next_w) / @as(f32, @floatFromInt(cur.width));
        const ou_y = passStrength(cur.height, next_h) / @as(f32, @floatFromInt(cur.height));
        const Tap = struct { x: f32, y: f32, w: f32 };
        const taps = [8]Tap{
            .{ .x = 0, .y = 2 * ou_y, .w = 1 },
            .{ .x = ou_x, .y = ou_y, .w = 2 },
            .{ .x = 2 * ou_x, .y = 0, .w = 1 },
            .{ .x = ou_x, .y = -ou_y, .w = 2 },
            .{ .x = 0, .y = -2 * ou_y, .w = 1 },
            .{ .x = -ou_x, .y = -ou_y, .w = 2 },
            .{ .x = -2 * ou_x, .y = 0, .w = 1 },
            .{ .x = -ou_x, .y = ou_y, .w = 2 },
        };
        var cum_w: f32 = 0;
        for (taps) |tap| {
            cum_w += tap.w;
            const a = tap.w / cum_w;
            dvui.renderTexture(cur, .{ .r = .{ .w = @floatFromInt(next_w), .h = @floatFromInt(next_h) } }, .{
                .uv = .{ .x = tap.x, .y = tap.y, .w = 1, .h = 1 },
                .colormod = dvui.Color.white.opacity(a),
            }) catch {};
        }

        dvui.textureDestroyLater(cur);
        cur = dvui.textureFromTarget(step_target) catch break; // destroys step_target
    }

    if (self.small) |old| dvui.textureDestroyLater(old);
    self.small = cur;
}

/// Draw the cached blurred texture over `rect` (set by the last
/// `init`). Cheap: just queues one textured-quad render command.
/// Must be the first thing drawn wherever content on top of the blur goes,
/// so that content paints over it.
pub fn draw(self: *BlurBackdrop) void {
    const tex = self.small orelse return;
    dvui.renderTexture(tex, .{ .r = self.rect }, .{}) catch {};
}

/// Release the cached GPU texture. Never called directly by user code -
/// registered by `get` as the data store's deinit function for this key, so
/// dvui calls it exactly once, whenever the storage key is finally
/// reclaimed (e.g. the widget that owns it stops being touched).
fn releaseTexture(ptr: *anyopaque) void {
    const self: *BlurBackdrop = @ptrCast(@alignCast(ptr));
    if (self.small) |tex| dvui.textureDestroyLater(tex);
    self.* = undefined;
}

/// How much of a full kawase pass's blur spread a size change from `a` to
/// `b` (in either order) is "worth": 1.0 for a full halving/doubling, down
/// to 0.0 for no size change at all. Used to scale tap offsets so a partial
/// leftover pass (whenever radius_px doesn't land on a clean power-of-two
/// fraction of the source size) contributes proportionally less blur,
/// instead of every pass - full or barely-there - applying the same fixed
/// offset. That fixed-offset behavior is what made `radius_px` feel like it
/// jumped in big steps: crossing the threshold where an extra pass kicks in
/// used to snap in a whole pass's worth of blur at once.
fn passStrength(a: u32, b: u32) f32 {
    const af: f32 = @floatFromInt(a);
    const bf: f32 = @floatFromInt(b);
    const ratio = @min(af, bf) / @max(af, bf);
    return @min(1.0, 2 * (1 - ratio));
}
