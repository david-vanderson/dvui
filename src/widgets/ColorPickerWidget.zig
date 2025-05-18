pub const ColorPickerWidget = @This();

id: u32,
opts: dvui.Options,
init_opts: InitOptions,
color_changed: bool = false,

pub const InitOptions = struct {
    hsv: *Color.HSV,
};

pub fn init(src: std.builtin.SourceLocation, init_opts: InitOptions, opts: Options) ColorPickerWidget {
    const defaults = Options{
        .name = "ColorPicker",
    };
    const self = ColorPickerWidget{
        .id = dvui.parentGet().extendId(src, opts.idExtra()),
        .opts = defaults.override(opts),
        .init_opts = init_opts,
    };
    return self;
}

pub fn install(self: *ColorPickerWidget) !void {
    var box = try dvui.box(@src(), .horizontal, self.opts);
    defer box.deinit();

    if (try valueSaturationBox(@src(), self.init_opts.hsv, .{})) {
        self.color_changed = true;
    }
}

pub fn deinit(_: *ColorPickerWidget) void {}

/// Returns true if the color was changed
pub fn valueSaturationBox(src: std.builtin.SourceLocation, hsv: *Color.HSV, opts: Options) !bool {
    const defaults = Options{
        .name = "ValueSaturationBox",
        .expand = .ratio,
        .min_size_content = .all(100),
        .border = .all(1),
        .padding = .all(5),
    };

    var box = try dvui.box(src, .horizontal, defaults.override(opts));
    defer box.deinit();

    const rs = box.data().contentRectScale();
    const size = rs.r.size();

    var vertexes = [_]dvui.Vertex{
        .{ .pos = rs.r.topLeft(), .col = .white, .uv = .{ 0.25, 0.25 } },
        .{ .pos = rs.r.bottomLeft(), .col = .white, .uv = .{ 0.25, 0.75 } },
        .{ .pos = rs.r.bottomRight(), .col = .white, .uv = .{ 0.75, 0.75 } },
        .{ .pos = rs.r.topRight(), .col = .white, .uv = .{ 0.75, 0.25 } },
    };
    var indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

    const triangles = dvui.Triangles{
        .vertexes = vertexes[0..],
        .indices = indices[0..],
        .bounds = rs.r,
    };

    var pixels = Color.white.toRGBA() ** 2 ++ Color.black.toRGBA() ** 2;
    comptime std.debug.assert(pixels.len == 2 * 2 * 4);
    // set top right corner to the max value of that hue
    @memcpy(pixels[4..8], &Color.HSV.toColor(.{ .h = hsv.h }).toRGBA());

    const tex = dvui.textureCreate(&pixels, 2, 2, .linear);
    // FIXME: Cache texture until hue changes, potentially modify existing texture
    dvui.textureDestroyLater(tex);

    try dvui.renderTriangles(triangles, tex);

    var changed = false;
    for (dvui.events()) |*e| {
        if (!dvui.eventMatchSimple(e, box.data())) {
            continue;
        }

        if (e.evt == .mouse) {
            switch (e.evt.mouse.action) {
                .press => {
                    e.handle(@src(), box.data());
                    const relative = e.evt.mouse.p.diff(rs.r.topLeft());
                    hsv.s = std.math.clamp(relative.x / size.w, 0, 1);
                    hsv.v = std.math.clamp(1 - relative.y / size.h, 0, 1);
                    changed = true;
                },
                else => {},
            }
        }
    }

    const current_point: dvui.Point = .{ .x = size.w * hsv.s, .y = size.h * (1 - hsv.v) };

    var indicator = dvui.BoxWidget.init(@src(), .horizontal, false, .{
        .rect = dvui.Rect.fromPoint(current_point).toSize(.all(10)).offsetNeg(.all(5)),
        .padding = .{},
        .margin = .{},
        .background = true,
        .border = .all(1),
        .corner_radius = .all(100),
        .color_fill = .fromColor(hsv.toColor()),
    });
    try indicator.install();
    try indicator.drawBackground();
    indicator.deinit();

    return changed;
}

const Options = dvui.Options;
const Color = dvui.Color;

const std = @import("std");
const dvui = @import("../dvui.zig");
