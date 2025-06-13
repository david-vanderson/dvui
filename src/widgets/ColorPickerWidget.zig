//! ![color-picker](ColorPickerWidget.png)
//!
//! A widget that handles the basic color picker square and acompanying hue slider.
//!
//! This widget does not include any sliders or input fields for
//! the individual color values.

pub const ColorPickerWidget = @This();

src: std.builtin.SourceLocation,
opts: dvui.Options,
init_opts: InitOptions,
color_changed: bool = false,
box: *dvui.BoxWidget = undefined,

pub const InitOptions = struct {
    hsv: *Color.HSV,
    dir: dvui.enums.Direction = .horizontal,
};

pub var defaults = Options{
    .name = "ColorPicker",
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) ColorPickerWidget {
    const self = ColorPickerWidget{
        .src = src,
        .opts = defaults.override(opts),
        .init_opts = init_opts,
    };
    return self;
}

pub fn install(self: *ColorPickerWidget) void {
    self.box = dvui.box(self.src, self.init_opts.dir, self.opts);

    if (valueSaturationBox(@src(), self.init_opts.hsv, .{})) {
        self.color_changed = true;
    }

    if (hueSlider(@src(), self.init_opts.dir.invert(), &self.init_opts.hsv.h, .{ .expand = .fromDirection(self.init_opts.dir.invert()) })) {
        self.color_changed = true;
    }
}

pub fn deinit(self: *ColorPickerWidget) void {
    defer dvui.widgetFree(self);
    self.box.deinit();
    self.* = undefined;
}

pub const value_saturation_box_defaults = Options{
    .name = "ValueSaturationBox",
    .expand = .ratio,
    .min_size_content = .all(100),
    .margin = .all(2),
};

/// Returns true if the color was changed
pub fn valueSaturationBox(src: std.builtin.SourceLocation, hsv: *Color.HSV, opts: Options) bool {
    const options = value_saturation_box_defaults.override(opts);

    var b = dvui.box(src, .horizontal, options);
    defer b.deinit();

    if (b.data().visible()) {
        dvui.tabIndexSet(b.data().id, options.tab_index);
    }

    const rs = b.data().contentRectScale();

    const texture = getValueSaturationTexture(hsv.h) catch |err| blk: {
        dvui.logError(@src(), err, "Could not get value saturation texture", .{});
        break :blk null;
    };
    if (texture) |tex| {
        dvui.renderTexture(tex, rs, .{
            .corner_radius = options.corner_radiusGet(),
            .uv = .{ .x = 0.25, .y = 0.25, .w = 0.75, .h = 0.75 },
        }) catch |err| {
            dvui.logError(@src(), err, "Could not render value saturation texture", .{});
        };
    }

    const mouse_rect = b.data().contentRect().justSize().outsetAll(5);
    const mouse_rs = b.widget().screenRectScale(mouse_rect);

    var changed = false;
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = b.data().id, .r = mouse_rs.r }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                var p: ?dvui.Point.Physical = null;
                if (me.action == .focus) {
                    e.handle(@src(), b.data());
                    dvui.focusWidget(b.data().id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    // capture
                    dvui.captureMouse(b.data());
                    e.handle(@src(), b.data());
                    p = me.p;
                } else if (me.action == .release and me.button.pointer()) {
                    // stop capture
                    dvui.captureMouse(null);
                    dvui.dragEnd();
                    e.handle(@src(), b.data());
                } else if (me.action == .motion and dvui.captured(b.data().id)) {
                    // handle only if we have capture
                    e.handle(@src(), b.data());
                    p = me.p;
                } else if (me.action == .position) {
                    dvui.cursorSet(.arrow);
                }

                if (p) |pp| {
                    hsv.s = std.math.clamp((pp.x - rs.r.x) / rs.r.w, 0, 1);
                    hsv.v = std.math.clamp(1 - (pp.y - rs.r.y) / rs.r.h, 0, 1);
                    changed = true;
                }
            },
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .left => {
                            e.handle(@src(), b.data());
                            hsv.s = std.math.clamp(hsv.s - 0.05, 0, 1);
                            changed = true;
                        },
                        .right => {
                            e.handle(@src(), b.data());
                            hsv.s = std.math.clamp(hsv.s + 0.05, 0, 1);
                            changed = true;
                        },
                        .up => {
                            e.handle(@src(), b.data());
                            // hsv.v is inverted, up is positive
                            hsv.v = std.math.clamp(hsv.v + 0.05, 0, 1);
                            changed = true;
                        },
                        .down => {
                            e.handle(@src(), b.data());
                            // hsv.v is inverted, down is negative
                            hsv.v = std.math.clamp(hsv.v - 0.05, 0, 1);
                            changed = true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    const br = b.data().contentRect();
    const current_point: dvui.Point = .{ .x = br.w * hsv.s, .y = br.h * (1 - hsv.v) };

    var indicator = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal }, .{
        .rect = dvui.Rect.fromPoint(current_point).toSize(.all(10)).offsetNeg(.all(5)),
        .padding = .{},
        .margin = .{},
        .background = true,
        .border = .all(1),
        .corner_radius = .all(100),
        .color_fill = .fromColor(hsv.toColor()),
    });
    indicator.install();
    indicator.drawBackground();
    if (b.data().id == dvui.focusedWidgetId()) {
        indicator.wd.focusBorder();
    }
    indicator.deinit();

    return changed;
}

pub var hue_slider_defaults: Options = .{
    .margin = .all(2),
    .min_size_content = .{ .w = 20, .h = 20 },
    .name = "HueSlider",
};

/// Returns true if the hue was changed
///
/// `hue` >= 0 and `hue` < 360
pub fn hueSlider(src: std.builtin.SourceLocation, dir: dvui.enums.Direction, hue: *f32, opts: Options) bool {
    var fraction = std.math.clamp(hue.* / 360, 0, 1);
    std.debug.assert(fraction >= 0);
    std.debug.assert(fraction <= 1);

    const options = hue_slider_defaults.override(opts);

    var b = dvui.box(src, dir, options);
    defer b.deinit();

    if (b.data().visible()) {
        dvui.tabIndexSet(b.data().id, options.tab_index);
    }

    const br = b.data().contentRect();
    const knobsize: dvui.Size = switch (dir) {
        .horizontal => .{ .w = 10, .h = br.h },
        .vertical => .{ .w = br.w, .h = 10 },
    };
    const track_thickness = 10;
    const track: dvui.Rect = switch (dir) {
        .horizontal => .{ .x = 0, .y = br.h / 2 - track_thickness / 2, .w = br.w, .h = track_thickness },
        .vertical => .{ .x = br.w / 2 - track_thickness / 2, .y = 0, .w = track_thickness, .h = br.h },
    };

    const trackrs = b.widget().screenRectScale(track);

    var ret = false;
    const rect = b.data().contentRect().justSize().outset(if (dir == .vertical) .{ .y = 5, .h = 5 } else .{ .x = 5, .w = 5 });
    const rs = b.widget().screenRectScale(rect);
    const evts = dvui.events();
    for (evts) |*e| {
        if (!dvui.eventMatch(e, .{ .id = b.data().id, .r = rs.r }))
            continue;

        switch (e.evt) {
            .mouse => |me| {
                var p: ?dvui.Point.Physical = null;
                if (me.action == .focus) {
                    e.handle(@src(), b.data());
                    dvui.focusWidget(b.data().id, null, e.num);
                } else if (me.action == .press and me.button.pointer()) {
                    // capture
                    dvui.captureMouse(b.data());
                    e.handle(@src(), b.data());
                    p = me.p;
                } else if (me.action == .release and me.button.pointer()) {
                    // stop capture
                    dvui.captureMouse(null);
                    dvui.dragEnd();
                    e.handle(@src(), b.data());
                } else if (me.action == .motion and dvui.captured(b.data().id)) {
                    // handle only if we have capture
                    e.handle(@src(), b.data());
                    p = me.p;
                } else if (me.action == .position) {
                    dvui.cursorSet(.arrow);
                }

                if (p) |pp| {
                    const val = switch (dir) {
                        .horizontal => (pp.x - trackrs.r.x) / trackrs.r.w,
                        .vertical => (pp.y - trackrs.r.y) / trackrs.r.h,
                    };
                    fraction = std.math.clamp(val, 0, 1);
                    ret = true;
                }
            },
            .key => |ke| {
                if (ke.action == .down or ke.action == .repeat) {
                    switch (ke.code) {
                        .left, .up => {
                            e.handle(@src(), b.data());
                            fraction = std.math.clamp(fraction - 0.05, 0, 1);
                            ret = true;
                        },
                        .right, .down => {
                            e.handle(@src(), b.data());
                            fraction = std.math.clamp(fraction + 0.05, 0, 1);
                            ret = true;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    if (ret) {
        hue.* = fraction * 359.99;
        dvui.refresh(null, @src(), b.data().id);
    }

    const uv_offset = comptime 0.5 / @as(f32, @floatFromInt(hue_selector_colors.len));
    const texture = getHueSelectorTexture(dir) catch |err| blk: {
        dvui.logError(@src(), err, "Could not get hue selector texture", .{});
        break :blk null;
    };
    if (texture) |tex| {
        dvui.renderTexture(tex, trackrs, .{
            .corner_radius = options.corner_radiusGet(),
            .uv = .{
                .x = uv_offset,
                .y = if (dir == .vertical) uv_offset else 1 - uv_offset,
                .w = 1 - uv_offset,
                .h = if (dir == .horizontal) uv_offset else 1 - uv_offset,
            },
        }) catch |err| {
            dvui.logError(@src(), err, "Could not render hue selector texture", .{});
        };
    }

    const knobRect = dvui.Rect.fromPoint(switch (dir) {
        .horizontal => .{ .x = (br.w * fraction) - knobsize.w / 2 },
        .vertical => .{ .y = (br.h * fraction) - knobsize.h / 2 },
    }).toSize(knobsize);

    var knob = dvui.BoxWidget.init(@src(), .{ .dir = .horizontal }, .{
        .rect = knobRect,
        .padding = .{},
        .margin = .{},
        .background = true,
        .border = .all(1),
        .corner_radius = .all(100),
        .color_fill = .fromColor((Color.HSV{ .h = hue.* }).toColor()),
    });
    knob.install();
    knob.drawBackground();
    if (b.data().id == dvui.focusedWidgetId()) {
        knob.wd.focusBorder();
    }
    knob.deinit();

    return ret;
}

pub fn getHueSelectorTexture(dir: dvui.enums.Direction) dvui.Backend.TextureError!dvui.Texture {
    const hue_texture_id = dvui.hashIdKey(@enumFromInt(@as(u64, @intFromEnum(dir))), "hue_selector_texture");
    const cw = dvui.currentWindow();
    const res = try cw.texture_cache.getOrPut(cw.gpa, hue_texture_id);
    if (!res.found_existing) {
        const width: u32, const height: u32 = switch (dir) {
            .horizontal => .{ hue_selector_colors.len, 1 },
            .vertical => .{ 1, hue_selector_colors.len },
        };
        // FIXME: textureCreate should not need a non const pointer to pixels
        res.value_ptr.texture = try dvui.textureCreate(.cast(@constCast(&hue_selector_pixels)), width, height, .linear);
    }
    return res.value_ptr.texture;
}

pub fn getValueSaturationTexture(hue: f32) dvui.Backend.TextureError!dvui.Texture {
    const hue_texture_id = dvui.hashIdKey(@enumFromInt(@as(u64, @intFromFloat(hue * 10000))), "value_saturation_texture");
    const cw = dvui.currentWindow();
    const res = try cw.texture_cache.getOrPut(cw.gpa, hue_texture_id);
    if (!res.found_existing) {
        var pixels = Color.white.toRGBA() ** 2 ++ Color.black.toRGBA() ** 2;
        comptime std.debug.assert(pixels.len == 2 * 2 * 4);
        // set top right corner to the max value of that hue
        @memcpy(pixels[4..8], &Color.HSV.toColor(.{ .h = hue }).toRGBA());
        res.value_ptr.texture = try dvui.textureCreate(.cast(&pixels), 2, 2, .linear);
    }
    return res.value_ptr.texture;
}

const hue_selector_colors: [7]Color = .{ .red, .yellow, .lime, .cyan, .blue, .magenta, .red };
const hue_selector_pixels: [hue_selector_colors.len * 4]u8 = blk: {
    var pixels: [hue_selector_colors.len * 4]u8 = undefined;
    for (0.., hue_selector_colors) |i, c| {
        pixels[i * 4 + 0] = c.r;
        pixels[i * 4 + 1] = c.g;
        pixels[i * 4 + 2] = c.b;
        pixels[i * 4 + 3] = c.a;
    }
    break :blk pixels;
};

const Options = dvui.Options;
const Color = dvui.Color;

const std = @import("std");
const dvui = @import("../dvui.zig");

test {
    std.testing.refAllDecls(@This());
}

test "DOCIMG ColorPickerWidget" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 300, .h = 130 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .vertical, .{ .expand = .both, .background = true, .color_fill = .fill_window });
            defer box.deinit();

            var hsv: dvui.Color.HSV = .{ .h = 120, .s = 0.8, .v = 0.9 };
            _ = dvui.colorPicker(@src(), .{ .hsv = &hsv }, .{ .gravity_x = 0.5, .gravity_y = 0.5 });
            return .ok;
        }
    }.frame;

    try dvui.testing.settle(frame);
    try t.saveImage(frame, null, "ColorPickerWidget.png");
}
