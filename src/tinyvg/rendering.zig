//!
//! This module implements means to render the output of the parsing module.
//!

const std = @import("std");
const builtin = @import("builtin");
const tvg = @import("tinyvg.zig");
const parsing = tvg.parsing;

/// Renders a TinyVG graphic and returns the rendered image.
/// - `temporary_allocator` is used for temporary allocations.
/// - `image_allocator` is used to allocate the final image.
/// - `size_hint` determines the way how the final graphic is specified
/// - `anti_alias` determines the level of anti-aliasing if not `null`
/// - `data` is a slice providing the TinyVG graphic
pub fn renderBuffer(
    temporary_allocator: std.mem.Allocator,
    image_allocator: std.mem.Allocator,
    size_hint: SizeHint,
    anti_alias: ?AntiAliasing,
    data: []const u8,
) !Image {
    var stream = std.io.fixedBufferStream(data);
    return try renderStream(
        temporary_allocator,
        image_allocator,
        size_hint,
        anti_alias,
        stream.reader(),
    );
}

/// Renders a TinyVG graphic and returns the rendered image.
/// - `temporary_allocator` is used for temporary allocations.
/// - `image_allocator` is used to allocate the final image.
/// - `size_hint` determines the way how the final graphic is specified
/// - `anti_alias` determines the level of anti-aliasing if not `null`
/// - `reader` is a stream providing the TinyVG graphic
pub fn renderStream(
    temporary_allocator: std.mem.Allocator,
    image_allocator: std.mem.Allocator,
    size_hint: SizeHint,
    anti_alias: ?AntiAliasing,
    reader: anytype,
) !Image {
    var parser = try tvg.parse(temporary_allocator, reader);
    defer parser.deinit();

    const target_size: Size = switch (size_hint) {
        .inherit => Size{ .width = parser.header.width, .height = parser.header.height },
        .size => |size| size,
        .width => |width| Size{
            .width = width,
            .height = (width * parser.header.height) / parser.header.width,
        },
        .height => |height| Size{
            .width = (height * parser.header.width) / parser.header.height,
            .height = height,
        },
        .bounded => |bounds| calcBoundedSize(
            bounds, parser.header.width, parser.header.height
        ),
    };

    const super_scale: u32 = if (anti_alias) |factor|
        @intFromEnum(factor)
    else
        1;

    const render_size = Size{
        .width = target_size.width * super_scale,
        .height = target_size.height * super_scale,
    };

    const target_pixel_count = @as(usize, target_size.width) * @as(usize, target_size.height);
    const render_pixel_count = @as(usize, render_size.width) * @as(usize, render_size.height);

    const framebuffer = Framebuffer{
        .slice = try temporary_allocator.alloc(Color, render_pixel_count),
        .stride = render_size.width,
        .width = render_size.width,
        .height = render_size.height,
    };
    defer temporary_allocator.free(framebuffer.slice);

    // Fill the destination buffer with magic magenta. None if this will be visible
    // in the end, but it will show users where they do wrong alpha interpolation
    // by bleeding in magenta
    @memset(framebuffer.slice, Color{ .r = 1, .g = 0, .b = 1, .a = 0 });

    while (try parser.next()) |cmd| {
        try renderCommand(&framebuffer, parser.header, parser.color_table, cmd, temporary_allocator);
    }

    const image = Image{
        .pixels = try image_allocator.alloc(Color8, target_pixel_count),
        .width = target_size.width,
        .height = target_size.height,
    };
    errdefer image_allocator.free(image.pixels);

    // resolve anti-aliasing
    for (image.pixels, 0..) |*pixel, i| {
        const x = i % image.width;
        const y = i / image.width;

        // stores premultiplied rgb + linear alpha
        // premultiplication is necessary as
        // (1,1,1,50%) over (0,0,0,0%) must result in (1,1,1,25%) and not (0.5,0.5,0.5,25%).
        // This will only happen if we fully ignore the fraction of transparent colors in the final result.
        // The average must also be computed in linear space, as we would get invalid color blending otherwise.
        var color = std.mem.zeroes([4]f32);

        for (0..super_scale) |dy| {
            for (0..super_scale) |dx| {
                const sx = x * super_scale + dx;
                const sy = y * super_scale + dy;

                const src_color = framebuffer.slice[sy * framebuffer.stride + sx];

                const a = src_color.a;

                // Create premultiplied linear colors
                color[0] += a * mapToLinear(src_color.r);
                color[1] += a * mapToLinear(src_color.g);
                color[2] += a * mapToLinear(src_color.b);
                color[3] += a;
            }
        }

        // Compute average
        for (&color) |*chan| {
            chan.* = chan.* / @as(f32, @floatFromInt(super_scale * super_scale));
        }

        const final_a = color[3];

        if (final_a > 0.0) {
            pixel.* = Color8{
                // unmultiply the alpha and apply the gamma
                .r = mapToGamma8(color[0] / final_a),
                .g = mapToGamma8(color[1] / final_a),
                .b = mapToGamma8(color[2] / final_a),
                .a = @intFromFloat(255.0 * color[3]),
            };
        } else {
            pixel.* = Color8{ .r = 0xFF, .g = 0x00, .b = 0xFF, .a = 0x00 };
        }
    }

    return image;
}

const gamma = 2.2;

fn mapToLinear(val: f32) f32 {
    return std.math.pow(f32, val, gamma);
}

fn mapToGamma(val: f32) f32 {
    return std.math.pow(f32, val, 1.0 / gamma);
}

fn mapToGamma8(val: f32) u8 {
    return @intFromFloat(255.0 * mapToGamma(val));
}

const Framebuffer = struct {
    const Self = @This();

    // private API

    slice: []Color,
    stride: usize,

    // public API
    width: usize,
    height: usize,

    pub fn setPixel(self: *const Self, x: isize, y: isize, src_color: tvg.Color) void {
        if (x < 0 or y < 0)
            return;
        if (x >= self.width or y >= self.height)
            return;
        const offset = (std.math.cast(usize, y) orelse return) * self.stride + (std.math.cast(usize, x) orelse return);

        const destination_pixel = &self.slice[offset];

        const dst_color = destination_pixel.*;

        if (src_color.a == 0) {
            return;
        }
        if (src_color.a == 255) {
            destination_pixel.* = src_color;
            return;
        }

        // src over dst
        //   a over b

        const src_alpha = src_color.a;
        const dst_alpha = dst_color.a;

        const fin_alpha = src_alpha + (1.0 - src_alpha) * dst_alpha;

        destination_pixel.* = Color{
            .r = lerpColor(src_color.r, dst_color.r, src_alpha, dst_alpha, fin_alpha),
            .g = lerpColor(src_color.g, dst_color.g, src_alpha, dst_alpha, fin_alpha),
            .b = lerpColor(src_color.b, dst_color.b, src_alpha, dst_alpha, fin_alpha),
            .a = fin_alpha,
        };
    }

    fn lerpColor(src: f32, dst: f32, src_alpha: f32, dst_alpha: f32, fin_alpha: f32) f32 {
        const src_val = mapToLinear(src);
        const dst_val = mapToLinear(dst);

        const value = (1.0 / fin_alpha) * (src_alpha * src_val + (1.0 - src_alpha) * dst_alpha * dst_val);

        return mapToGamma(value);
    }
};

pub const Color8 = extern struct { r: u8, g: u8, b: u8, a: u8 };

pub const SizeHint = union(enum) {
    inherit,
    width: u32,
    height: u32,
    size: Size,
    /// The maximum size that maintains the aspect ratio and fits within the given bounds
    bounded: Size,
};

fn calcBoundedSize(bounds: Size, width: u32, height: u32) Size {
    const width_f32: f32 = @floatFromInt(width);
    const height_f32: f32 = @floatFromInt(height);
    const width_mult = @as(f32, @floatFromInt(bounds.width)) / width_f32;
    const height_mult = @as(f32, @floatFromInt(bounds.height)) / height_f32;
    if (width_mult >= height_mult) return .{
        .width = @intFromFloat(@trunc(width_f32 * height_mult)),
        .height = bounds.height,
    };
    return .{
        .width = bounds.width,
        .height = @intFromFloat(@trunc(height_f32 * width_mult)),
    };
}

pub const Size = struct {
    width: u32,
    height: u32,
};

pub const AntiAliasing = enum(u32) {
    x1 = 1,
    x4 = 2,
    x9 = 3,
    x16 = 4,
    x25 = 6,
    x49 = 7,
    x64 = 8,
    _,
};

pub const Image = struct {
    width: u32,
    height: u32,
    pixels: []Color8,

    pub fn deinit(self: *Image, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.* = undefined;
    }
};

pub fn isFramebuffer(comptime T: type) bool {
    const FbType = if (@typeInfo(T) == .pointer)
        std.meta.Child(T)
    else
        T;
    return std.meta.hasFn(FbType, "setPixel") and
        @hasField(FbType, "width") and
        @hasField(FbType, "height");
}

const Point = tvg.Point;
const Rectangle = tvg.Rectangle;
const Color = tvg.Color;
const Style = tvg.Style;

// TODO: Make these configurable
const circle_divs = 100;
const bezier_divs = 16;

const max_path_len = 512;

const IndexSlice = struct { offset: usize, len: usize };

// this is the allocation threshold for images.
// when we go over this, we require `allocator` to be set.
const temp_buffer_size = 256;

/// Renders a single TinyVG command. Performs no aliasing, super sampling or blending.
/// - `framebuffer` implements the backing storage for rendering, must provide function `setPixel(x:usize,y:usize,TvgColor)` and fields `width` and `height`.
/// - `header` is the TinyVG header
/// - `color_table` is the color table that is used for rendering.
/// - `cmd` is the draw command that should be rendered.
pub fn renderCommand(
    /// A struct that exports a single function `setPixel(x: isize, y: isize, color: [4]u8) void` as well as two fields width and height
    framebuffer: anytype,
    /// The parsed header of a TVG
    header: parsing.Header,
    /// The color lookup table
    color_table: []const tvg.Color,
    /// The command that should be executed.
    cmd: parsing.DrawCommand,
    /// When given, the `renderCommand` is able to render complexer graphics
    allocator: ?std.mem.Allocator,
) !void {
    if (!comptime isFramebuffer(@TypeOf(framebuffer)))
        @compileError("framebuffer needs fields width, height and function setPixel!");
    const fb_width: f32 = @floatFromInt(framebuffer.width);
    const fb_height: f32 = @floatFromInt(framebuffer.height);
    // std.debug.print("render {}\n", .{cmd});#

    var painter = Painter{
        .scale_x = fb_width / @as(f32, @floatFromInt(header.width)),
        .scale_y = fb_height / @as(f32, @floatFromInt(header.height)),
    };

    switch (cmd) {
        .fill_polygon => |data| {
            painter.fillPolygonList(framebuffer, color_table, data.style, &[_][]const Point{data.vertices}, .even_odd);
        },
        .fill_rectangles => |data| {
            for (data.rectangles) |rect| {
                painter.fillRectangle(framebuffer, rect.x, rect.y, rect.width, rect.height, color_table, data.style);
            }
        },
        .fill_path => |data| {
            var point_store = FixedBufferList(Point, temp_buffer_size).init(allocator);
            defer point_store.deinit();
            var slice_store = FixedBufferList(IndexSlice, temp_buffer_size).init(allocator);
            defer slice_store.deinit();

            try renderPath(&point_store, null, &slice_store, data.path, 0.0);

            var slices: [max_path_len][]const Point = undefined;
            for (slice_store.items(), 0..) |src, i| {
                slices[i] = point_store.items()[src.offset..][0..src.len];
            }

            painter.fillPolygonList(
                framebuffer,
                color_table,
                data.style,
                slices[0..slice_store.items().len],
                .even_odd,
            );
        },
        .draw_lines => |data| {
            for (data.lines) |line| {
                painter.drawLine(framebuffer, color_table, data.style, data.line_width, data.line_width, line);
            }
        },
        .draw_line_strip => |data| {
            for (data.vertices[1..], 0..) |end, i| {
                const start = data.vertices[i]; // is actually [i-1], but we access the slice off-by-one!
                painter.drawLine(framebuffer, color_table, data.style, data.line_width, data.line_width, .{
                    .start = start,
                    .end = end,
                });
            }
        },
        .draw_line_loop => |data| {
            var start_index: usize = data.vertices.len - 1;
            for (data.vertices, 0..) |end, end_index| {
                const start = data.vertices[start_index];

                painter.drawLine(framebuffer, color_table, data.style, data.line_width, data.line_width, .{
                    .start = start,
                    .end = end,
                });
                start_index = end_index;
            }
        },
        .draw_line_path => |data| {
            var point_store = FixedBufferList(Point, temp_buffer_size).init(allocator);
            defer point_store.deinit();
            var width_store = FixedBufferList(f32, temp_buffer_size).init(allocator);
            defer width_store.deinit();
            var slice_store = FixedBufferList(IndexSlice, temp_buffer_size).init(allocator);
            defer slice_store.deinit();

            try renderPath(&point_store, &width_store, &slice_store, data.path, data.line_width);

            const slice_size = slice_store.buffer.len;
            var slices: [slice_size][]const Point = undefined;
            for (slice_store.items(), 0..) |src, i| {
                slices[i] = point_store.items()[src.offset..][0..src.len];
            }

            const line_widths = width_store.items();

            for (slices[0..slice_store.items().len]) |vertices| {
                for (vertices[1..], 0..) |end, i| {
                    const start = vertices[i]; // is actually [i-1], but we access the slice off-by-one!
                    painter.drawLine(framebuffer, color_table, data.style, line_widths[i], line_widths[i + 1], .{
                        .start = start,
                        .end = end,
                    });
                }
            }
        },
        .outline_fill_polygon => |data| {
            painter.fillPolygonList(framebuffer, color_table, data.fill_style, &[_][]const Point{data.vertices}, .even_odd);

            var start_index: usize = data.vertices.len - 1;
            for (data.vertices, 0..) |end, end_index| {
                const start = data.vertices[start_index];

                painter.drawLine(framebuffer, color_table, data.line_style, data.line_width, data.line_width, .{
                    .start = start,
                    .end = end,
                });
                start_index = end_index;
            }
        },

        .outline_fill_rectangles => |data| {
            for (data.rectangles) |rect| {
                painter.fillRectangle(framebuffer, rect.x, rect.y, rect.width, rect.height, color_table, data.fill_style);
                const tl = Point{ .x = rect.x, .y = rect.y };
                const tr = Point{ .x = rect.x + rect.width, .y = rect.y };
                const bl = Point{ .x = rect.x, .y = rect.y + rect.height };
                const br = Point{ .x = rect.x + rect.width, .y = rect.y + rect.height };
                painter.drawLine(framebuffer, color_table, data.line_style, data.line_width, data.line_width, .{ .start = tl, .end = tr });
                painter.drawLine(framebuffer, color_table, data.line_style, data.line_width, data.line_width, .{ .start = tr, .end = br });
                painter.drawLine(framebuffer, color_table, data.line_style, data.line_width, data.line_width, .{ .start = br, .end = bl });
                painter.drawLine(framebuffer, color_table, data.line_style, data.line_width, data.line_width, .{ .start = bl, .end = tl });
            }
        },
        .outline_fill_path => |data| {
            var point_store = FixedBufferList(Point, temp_buffer_size).init(allocator);
            defer point_store.deinit();
            var width_store = FixedBufferList(f32, temp_buffer_size).init(allocator);
            defer width_store.deinit();
            var slice_store = FixedBufferList(IndexSlice, temp_buffer_size).init(allocator);
            defer slice_store.deinit();

            try renderPath(&point_store, &width_store, &slice_store, data.path, data.line_width);

            var slices: [max_path_len][]const Point = undefined;
            for (slice_store.items(), 0..) |src, i| {
                slices[i] = point_store.items()[src.offset..][0..src.len];
            }

            painter.fillPolygonList(framebuffer, color_table, data.fill_style, slices[0..slice_store.items().len], .even_odd);

            const line_widths = width_store.items();

            for (slices[0..slice_store.items().len]) |vertices| {
                for (vertices[1..], 0..) |end, i| {
                    const start = vertices[i]; // is actually [i-1], but we access the slice off-by-one!
                    painter.drawLine(framebuffer, color_table, data.line_style, line_widths[i], line_widths[i + 1], .{
                        .start = start,
                        .end = end,
                    });
                }
            }
        },
    }
}

pub fn renderPath(
    point_list: *FixedBufferList(Point, temp_buffer_size),
    width_list: ?*FixedBufferList(f32, temp_buffer_size),
    slice_list: *FixedBufferList(IndexSlice, temp_buffer_size),
    path: tvg.Path,
    line_width: f32,
) !void {
    const Helper = struct {
        list: @TypeOf(point_list),
        last: Point,
        count: usize,

        width_list: ?*FixedBufferList(f32, temp_buffer_size),

        // Discard when point is in the vicinity of the last point (same pixel)
        const pixel_delta = 0.25;

        fn approxEqual(p0: Point, p1: Point, delta: f32) bool {
            return std.math.approxEqAbs(f32, p0.x, p1.x, delta) and std.math.approxEqAbs(f32, p0.y, p1.y, delta);
        }

        fn append(self: *@This(), pt: Point, lw: f32) !void {
            std.debug.assert(!std.math.isNan(pt.x));
            std.debug.assert(!std.math.isNan(pt.y));

            // This breaks back-to-back line segments share end and start
            //if (approxEqual(self.last, pt, pixel_delta))
            //    return;

            try self.list.append(pt);
            if (self.width_list) |wl| {
                errdefer _ = self.list.popBack();
                try wl.append(lw);
            }
            self.last = pt;
            self.count += 1;
        }

        fn back(self: @This()) Point {
            return self.last;
        }
    };

    var point_store = Helper{
        .list = point_list,
        .last = undefined,
        .count = 0,
        .width_list = width_list,
    };

    for (path.segments) |segment| {
        const start_index = point_store.count;
        var last_width = line_width;

        try point_store.append(segment.start, last_width);

        for (segment.commands) |node| {
            const new_width = switch (node) {
                .line => |val| val.line_width,
                .horiz => |val| val.line_width,
                .vert => |val| val.line_width,
                .bezier => |val| val.line_width,
                .arc_circle => |val| val.line_width,
                .arc_ellipse => |val| val.line_width,
                .close => |val| val.line_width,
                .quadratic_bezier => |val| val.line_width,
            } orelse last_width;
            defer last_width = new_width;

            switch (node) {
                .line => |pt| try point_store.append(pt.data, pt.line_width orelse last_width),
                .horiz => |x| try point_store.append(Point{ .x = x.data, .y = point_store.back().y }, x.line_width orelse last_width),
                .vert => |y| try point_store.append(Point{ .x = point_store.back().x, .y = y.data }, y.line_width orelse last_width),
                .bezier => |bezier| {
                    const previous = point_store.back();

                    const oct0_x = [4]f32{ previous.x, bezier.data.c0.x, bezier.data.c1.x, bezier.data.p1.x };
                    const oct0_y = [4]f32{ previous.y, bezier.data.c0.y, bezier.data.c1.y, bezier.data.p1.y };

                    for (1..bezier_divs) |i| {
                        const f = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bezier_divs));

                        const x = lerpAndReduceToOne(4, oct0_x, f);
                        const y = lerpAndReduceToOne(4, oct0_y, f);

                        try point_store.append(Point{ .x = x, .y = y }, lerp(last_width, new_width, f));
                    }

                    try point_store.append(bezier.data.p1, new_width);
                },
                .quadratic_bezier => |bezier| {
                    const previous = point_store.back();

                    const oct0_x = [3]f32{ previous.x, bezier.data.c.x, bezier.data.p1.x };
                    const oct0_y = [3]f32{ previous.y, bezier.data.c.y, bezier.data.p1.y };

                    for (1..bezier_divs) |i| {
                        const f = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(bezier_divs));

                        const x = lerpAndReduceToOne(3, oct0_x, f);
                        const y = lerpAndReduceToOne(3, oct0_y, f);

                        try point_store.append(Point{ .x = x, .y = y }, lerp(last_width, new_width, f));
                    }

                    try point_store.append(bezier.data.p1, new_width);
                },
                // /home/felix/projects/forks/svg-curve-lib/src/js/svg-curve-lib.js
                .arc_circle => |circle| {
                    // Filter out too-tiny ellipses so we don't go into NaN land
                    if (Helper.approxEqual(point_store.back(), circle.data.target, 1e-5))
                        continue;
                    try renderCircle(
                        &point_store,
                        point_store.back(),
                        circle.data.target,
                        circle.data.radius,
                        circle.data.large_arc,
                        circle.data.sweep,
                        last_width,
                        new_width,
                    );
                },
                .arc_ellipse => |ellipse| {
                    // Filter out too-tiny ellipses so we don't go into NaN land
                    if (Helper.approxEqual(point_store.back(), ellipse.data.target, 1e-5))
                        continue;
                    try renderEllipse(
                        &point_store,
                        point_store.back(),
                        ellipse.data.target,
                        ellipse.data.radius_x,
                        ellipse.data.radius_y,
                        ellipse.data.rotation,
                        ellipse.data.large_arc,
                        ellipse.data.sweep,
                        last_width,
                        new_width,
                    );
                },
                .close => |close| {
                    // if (node_index != (nodes.len - 1)) {
                    //     // .close must be last!
                    //     return error.InvalidData;
                    // }
                    try point_store.append(segment.start, close.line_width orelse last_width);
                },
            }
        }
        const end_index = point_store.count;

        if (end_index > start_index) {
            try slice_list.append(IndexSlice{
                .offset = start_index,
                .len = end_index - start_index,
            });
        }
    }
}

inline fn toRadians(a: f32) f32 {
    return std.math.pi / 180.0 * a;
}

inline fn cos(val: anytype) @TypeOf(val) {
    return @cos(val);
}

inline fn sin(val: anytype) @TypeOf(val) {
    return @sin(val);
}
inline fn sqrt(val: anytype) @TypeOf(val) {
    return @sqrt(val);
}
inline fn abs(val: anytype) @TypeOf(val) {
    return @abs(val);
}

pub fn renderEllipse(
    point_list: anytype,
    p0: Point,
    p1: Point,
    radius_x: f32,
    radius_y: f32,
    rotation: f32,
    large_arc: bool,
    turn_left: bool,
    start_width: f32,
    end_width: f32,
) !void {
    // std.debug.print("renderEllipse(({d:.3} {d:.3}), ({d:.3} {d:.3}), {d:.2}, {d:.2}, {d:.4}, large={}, left={})\n", .{
    //     p0.x,
    //     p0.y,
    //     p1.x,
    //     p1.y,
    //     radius_x,
    //     radius_y,
    //     rotation,
    //     large_arc,
    //     turn_left,
    // });

    const radius_min = distance(p0, p1) / 2.0;
    const radius_lim = sqrt(radius_x * radius_x + radius_y * radius_y); // @min(std.math.fabs(radius_x), std.math.fabs(radius_y));

    const up_scale = if (radius_lim < radius_min)
        radius_min / radius_lim
    else
        1.0;

    // std.debug.print("radius_min={d} radius_lim={d} up_scale={d}\n", .{ radius_min, radius_lim, up_scale });

    // std.debug.print("{d} {d} {d}, {d} => {d}\n", .{ radius_x, radius_y, radius_lim, radius_min, up_scale });

    const ratio = radius_x / radius_y;
    const rot = rotationMat(toRadians(-rotation));
    const transform = [2][2]f32{
        .{ rot[0][0] / up_scale, rot[0][1] / up_scale },
        .{ rot[1][0] / up_scale * ratio, rot[1][1] / up_scale * ratio },
    };
    const transform_back = [2][2]f32{
        .{ rot[1][1] * up_scale, -rot[0][1] / ratio * up_scale },
        .{ -rot[1][0] * up_scale, rot[0][0] / ratio * up_scale },
    };

    const Helper = struct {
        point_list: FixedBufferList(Point, circle_divs),
        width_list: FixedBufferList(f32, circle_divs),

        fn append(self: *@This(), pt: Point, lw: f32) !void {
            try self.point_list.append(pt);
            try self.width_list.append(lw);
        }
    };

    var tmp = Helper{
        .point_list = FixedBufferList(Point, circle_divs).init(null),
        .width_list = FixedBufferList(f32, circle_divs).init(null),
    };
    renderCircle(
        &tmp,
        applyMat(transform, p0),
        applyMat(transform, p1),
        radius_x * up_scale,
        large_arc,
        turn_left,
        start_width,
        end_width,
    ) catch unreachable; // buffer is correctly sized

    for (tmp.point_list.items(), tmp.width_list.items()) |p, w| {
        try point_list.append(applyMat(transform_back, p), w);
    }
}

fn renderCircle(
    point_list: anytype,
    p0: Point,
    p1: Point,
    radius: f32,
    large_arc: bool,
    turn_left: bool,
    start_width: f32,
    end_width: f32,
) !void {
    var r = radius;

    // Whether the center should be to the left of the vector from p0 to p1
    const left_side = (turn_left and large_arc) or (!turn_left and !large_arc);

    const delta = scale(sub(p1, p0), 0.5);
    const midpoint = add(p0, delta);

    // Vector from midpoint to center, but incorrect length
    const radius_vec = if (left_side)
        Point{ .x = -delta.y, .y = delta.x }
    else
        Point{ .x = delta.y, .y = -delta.x };

    const len_squared = length2(radius_vec);
    if (len_squared - 0.03 > r * r or r < 0) {
        r = @sqrt(len_squared);
        // std.log.err("{d} > {d}", .{ std.math.sqrt(len_squared), std.math.sqrt(r * r) });
        // return error.InvalidRadius;
    }

    const to_center = scale(radius_vec, sqrt(@max(0, r * r / len_squared - 1)));
    const center = add(midpoint, to_center);

    const angle = std.math.asin(std.math.clamp(sqrt(len_squared) / r, -1.0, 1.0)) * 2;
    const arc = if (large_arc) (std.math.tau - angle) else angle;

    const pos = sub(p0, center);
    for (0..circle_divs - 1) |i| {
        const step_mat = rotationMat(@as(f32, @floatFromInt(i)) * (if (turn_left) -arc else arc) / circle_divs);
        const point = add(applyMat(step_mat, pos), center);

        try point_list.append(point, lerp(start_width, end_width, @as(f32, @floatFromInt(i)) / circle_divs));
    }

    try point_list.append(p1, end_width);
}

fn rotationMat(angle: f32) [2][2]f32 {
    const s = sin(angle);
    const c = cos(angle);
    return .{
        .{ c, -s },
        .{ s, c },
    };
}

fn applyMat(mat: [2][2]f32, p: Point) Point {
    return .{
        .x = p.x * mat[0][0] + p.y * mat[0][1],
        .y = p.x * mat[1][0] + p.y * mat[1][1],
    };
}

fn pointFromInts(x: i16, y: i16) Point {
    return Point{ .x = @as(f32, @floatFromInt(x)) + 0.5, .y = @as(f32, @floatFromInt(y)) + 0.5 };
}

const IntPoint = struct { x: i16, y: i16 };
fn pointToInts(point: Point) IntPoint {
    return IntPoint{
        .x = floatToIntClamped(i16, @round(point.x)),
        .y = floatToIntClamped(i16, @round(point.y)),
    };
}

fn xy(x: f32, y: f32) Point {
    return Point{ .x = x, .y = y };
}

test "point conversion" {
    const TestData = struct { point: Point, x: i16, y: i16 };

    const pt2int = [_]TestData{
        .{ .point = xy(0, 0), .x = 0, .y = 0 },
        .{ .point = xy(1, 0), .x = 1, .y = 0 },
        .{ .point = xy(2, 0), .x = 2, .y = 0 },
        .{ .point = xy(0, 1), .x = 0, .y = 1 },
        .{ .point = xy(0, 2), .x = 0, .y = 2 },
        .{ .point = xy(1, 3), .x = 1, .y = 3 },
        .{ .point = xy(2, 4), .x = 2, .y = 4 },
    };
    const int2pt = [_]TestData{
        .{ .point = xy(0, 0), .x = 0, .y = 0 },
        .{ .point = xy(1, 0), .x = 1, .y = 0 },
        .{ .point = xy(2, 0), .x = 2, .y = 0 },
        .{ .point = xy(0, 1), .x = 0, .y = 1 },
        .{ .point = xy(0, 2), .x = 0, .y = 2 },
        .{ .point = xy(1, 3), .x = 1, .y = 3 },
        .{ .point = xy(2, 4), .x = 2, .y = 4 },
    };
    for (pt2int) |data| {
        const ints = pointToInts(data.point);
        //std.debug.print("{d} {d} => {d} {d}\n", .{
        //    data.point.x, data.point.y,
        //    ints.x,       ints.y,
        //});
        try std.testing.expectEqual(data.x, ints.x);
        try std.testing.expectEqual(data.y, ints.y);
    }
    for (int2pt) |data| {
        const pt = pointFromInts(data.x, data.y);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), distance(pt, data.point), sqrt(2.0) / 2.0);
    }
}

fn add(a: Point, b: Point) Point {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

fn sub(p1: Point, p2: Point) Point {
    return Point{ .x = p1.x - p2.x, .y = p1.y - p2.y };
}

fn dot(p1: Point, p2: Point) f32 {
    return p1.x * p2.x + p1.y * p2.y;
}

fn cross(a: Point, b: Point) f32 {
    return a.x * b.y - a.y * b.x;
}

fn scale(a: Point, s: f32) Point {
    return .{ .x = a.x * s, .y = a.y * s };
}

fn length2(p: Point) f32 {
    return dot(p, p);
}

fn length(p: Point) f32 {
    return sqrt(length2(p));
}

fn distance(p1: Point, p2: Point) f32 {
    return length(sub(p1, p2));
}

fn getProjectedPointOnLine(v1: Point, v2: Point, p: Point) Point {
    const l1 = sub(v2, v1);
    const l2 = sub(p, v1);
    const proj = dot(l1, l2) / length2(l1);

    return add(v1, scale(l1, proj));
}

const Painter = struct {
    scale_x: f32,
    scale_y: f32,

    // fn fillPolygon(self: Painter, framebuffer: anytype, color_table: []const Color, style: Style, points: []const Point) void {
    //     fillPolygonList(self, framebuffer, color_table, style, &[_][]const Point{points}, .nonzero);
    // }

    const FillRule = enum { even_odd, nonzero };
    fn fillPolygonList(self: Painter, framebuffer: anytype, color_table: []const Color, style: Style, points_lists: []const []const Point, rule: FillRule) void {
        std.debug.assert(points_lists.len > 0);

        var min_x: i16 = std.math.maxInt(i16);
        var min_y: i16 = std.math.maxInt(i16);
        var max_x: i16 = std.math.minInt(i16);
        var max_y: i16 = std.math.minInt(i16);

        for (points_lists) |points| {
            // std.debug.assert(points.len >= 3);
            for (points) |pt| {
                min_x = @min(min_x, floatToIntClamped(i16, @floor(self.scale_x * pt.x)));
                min_y = @min(min_y, floatToIntClamped(i16, @floor(self.scale_y * pt.y)));
                max_x = @max(max_x, floatToIntClamped(i16, @ceil(self.scale_x * pt.x)));
                max_y = @max(max_y, floatToIntClamped(i16, @ceil(self.scale_y * pt.y)));
            }
        }

        // limit to valid screen area
        min_x = @max(min_x, 0);
        min_y = @max(min_y, 0);

        max_x = @min(max_x, @as(i16, @intCast(framebuffer.width - 1)));
        max_y = @min(max_y, @as(i16, @intCast(framebuffer.height - 1)));

        var y: i16 = min_y;
        while (y <= max_y) : (y += 1) {
            var x: i16 = min_x;
            while (x <= max_x) : (x += 1) {

                // compute "center" of the pixel
                const p = self.mapPointToImage(pointFromInts(x, y));

                var inside_count: usize = 0;
                for (points_lists) |points| {
                    if (points.len < 2) continue;
                    var inside = false;

                    // free after https://stackoverflow.com/a/17490923

                    var j = points.len - 1;
                    for (points, 0..) |p0, i| {
                        defer j = i;
                        const p1 = points[j];

                        if ((p0.y > p.y) != (p1.y > p.y) and p.x < (p1.x - p0.x) * (p.y - p0.y) / (p1.y - p0.y) + p0.x) {
                            inside = !inside;
                        }
                    }
                    if (inside) {
                        inside_count += 1;
                    }
                }
                const set = switch (rule) {
                    .nonzero => (inside_count > 0),
                    .even_odd => (inside_count % 2) == 1,
                };
                if (set) {
                    framebuffer.setPixel(x, y, self.sampleStlye(color_table, style, x, y));
                }
            }
        }
    }

    fn fillRectangle(self: Painter, framebuffer: anytype, x: f32, y: f32, width: f32, height: f32, color_table: []const Color, style: Style) void {
        const xlimit: i16 = @intFromFloat(@ceil(self.scale_x * (x + width)));
        const ylimit: i16 = @intFromFloat(@ceil(self.scale_y * (y + height)));

        var py: i16 = @intFromFloat(@floor(self.scale_y * y));
        while (py < ylimit) : (py += 1) {
            var px: i16 = @intFromFloat(@floor(self.scale_x * x));
            while (px < xlimit) : (px += 1) {
                framebuffer.setPixel(px, py, self.sampleStlye(color_table, style, px, py));
            }
        }
    }

    fn sdUnevenCapsule(_p: Point, pa: Point, _pb: Point, ra: f32, rb: f32) f32 {
        const p = sub(_p, pa);
        const pb = sub(_pb, pa);
        const h = dot(pb, pb);
        var q = scale(tvg.point(dot(p, tvg.point(pb.y, -pb.x)), dot(p, pb)), 1.0 / h);

        //-----------

        q.x = @abs(q.x);

        const b = ra - rb;
        const c = tvg.point(@sqrt(h - b * b), b);

        const k = cross(c, q);
        const m = dot(c, q);
        const n = dot(q, q);

        if (k < 0.0) {
            return @sqrt(h * (n)) - ra;
        } else if (k > c.x) {
            return @sqrt(h * (n + 1.0 - 2.0 * q.y)) - rb;
        } else {
            return m - ra;
        }
    }

    /// render round-capped line via SDF: https://iquilezles.org/www/articles/distfunctions2d/distfunctions2d.htm (Uneven Capsule - exact )
    /// ```
    /// float sdUnevenCapsule( in vec2 p, in vec2 pa, in vec2 pb, in float ra, in float rb )
    /// {
    ///     p  -= pa;
    ///     pb -= pa;
    ///     float h = dot(pb,pb);
    ///     vec2  q = vec2( dot(p,vec2(pb.y,-pb.x)), dot(p,pb) )/h;
    ///
    ///     //-----------
    ///
    ///     q.x = abs(q.x);
    ///
    ///     float b = ra-rb;
    ///     vec2  c = vec2(sqrt(h-b*b),b);
    ///
    ///     float k = cro(c,q);
    ///     float m = dot(c,q);
    ///     float n = dot(q,q);
    ///
    ///          if( k < 0.0 ) return sqrt(h*(n            )) - ra;
    ///     else if( k > c.x ) return sqrt(h*(n+1.0-2.0*q.y)) - rb;
    ///                        return m                       - ra;
    /// }
    /// ```
    fn drawLine(self: Painter, framebuffer: anytype, color_table: []const Color, style: Style, width_start: f32, width_end: f32, line: tvg.Line) void {
        var min_x: i16 = std.math.maxInt(i16);
        var min_y: i16 = std.math.maxInt(i16);
        var max_x: i16 = std.math.minInt(i16);
        var max_y: i16 = std.math.minInt(i16);

        const max_width = @max(width_start, width_end);

        const points = [_]tvg.Point{ line.start, line.end };
        for (points) |pt| {
            min_x = @min(min_x, @as(i16, @intFromFloat(@floor(self.scale_x * (pt.x - max_width)))));
            min_y = @min(min_y, @as(i16, @intFromFloat(@floor(self.scale_y * (pt.y - max_width)))));
            max_x = @max(max_x, @as(i16, @intFromFloat(@ceil(self.scale_x * (pt.x + max_width)))));
            max_y = @max(max_y, @as(i16, @intFromFloat(@ceil(self.scale_y * (pt.y + max_width)))));
        }

        // limit to valid screen area
        min_x = @max(min_x, 0);
        min_y = @max(min_y, 0);

        max_x = @min(max_x, @as(i16, @intCast(framebuffer.width - 1)));
        max_y = @min(max_y, @as(i16, @intCast(framebuffer.height - 1)));

        var y: i16 = min_y;
        while (y <= max_y) : (y += 1) {
            var x: i16 = min_x;
            while (x <= max_x) : (x += 1) {

                // compute "center" of the pixel
                const p = self.mapPointToImage(pointFromInts(x, y));

                const dist = sdUnevenCapsule(
                    p,
                    line.start,
                    line.end,
                    @max(0.35, width_start / 2),
                    @max(0.35, width_end / 2),
                );

                if (dist <= 0.0) {
                    framebuffer.setPixel(x, y, self.sampleStlye(color_table, style, x, y));
                }
            }
        }
    }

    fn mapPointToImage(self: Painter, pt: Point) Point {
        return Point{
            .x = pt.x / self.scale_x,
            .y = pt.y / self.scale_y,
        };
    }

    fn sampleStlye(self: Painter, color_table: []const Color, style: Style, x: i16, y: i16) Color {
        return switch (style) {
            .flat => |index| color_table[index],
            .linear => |grad| blk: {
                const c0 = color_table[grad.color_0];
                const c1 = color_table[grad.color_1];

                const p0 = grad.point_0;
                const p1 = grad.point_1;
                const pt = self.mapPointToImage(pointFromInts(x, y));

                const direction = sub(p1, p0);
                const delta_pt = sub(pt, p0);

                const dot_0 = dot(direction, delta_pt);
                if (dot_0 <= 0.0)
                    break :blk c0;

                const dot_1 = dot(direction, sub(pt, p1));
                if (dot_1 >= 0.0)
                    break :blk c1;

                const len_grad = length(direction);

                const pos_grad = length(getProjectedPointOnLine(
                    Point{ .x = 0, .y = 0 },
                    direction,
                    delta_pt,
                ));

                break :blk lerp_sRGB(c0, c1, pos_grad / len_grad);
            },
            .radial => |grad| blk: {
                const dist_max = distance(grad.point_0, grad.point_1);
                const dist_is = distance(grad.point_0, self.mapPointToImage(pointFromInts(x, y)));

                const c0 = color_table[grad.color_0];
                const c1 = color_table[grad.color_1];

                break :blk lerp_sRGB(c0, c1, dist_is / dist_max);
            },
        };
    }
};

const sRGB_gamma = 2.2;

fn gamma2linear(v: f32) f32 {
    std.debug.assert(v >= 0 and v <= 1);
    return 255.0 * std.math.pow(f32, v, 1.0 / sRGB_gamma);
}

fn linear2gamma(v: f32) f32 {
    return std.math.pow(f32, v / 255.0, sRGB_gamma);
}

fn lerp_sRGB(c0: Color, c1: Color, f_unchecked: f32) Color {
    const f = std.math.clamp(f_unchecked, 0, 1);
    return Color{
        .r = gamma2linear(lerp(linear2gamma(c0.r), linear2gamma(c1.r), f)),
        .g = gamma2linear(lerp(linear2gamma(c0.g), linear2gamma(c1.g), f)),
        .b = gamma2linear(lerp(linear2gamma(c0.b), linear2gamma(c1.b), f)),
        .a = lerp(c0.a, c0.a, f),
    };
}

fn lerp(a: f32, b: f32, x: f32) f32 {
    return a + (b - a) * x;
}

fn lerpAndReduce(comptime n: comptime_int, vals: [n]f32, f: f32) [n - 1]f32 {
    var result: [n - 1]f32 = undefined;
    for (&result, 0..) |*r, i| {
        r.* = lerp(vals[i + 0], vals[i + 1], f);
    }
    return result;
}

fn lerpAndReduceToOne(comptime n: comptime_int, vals: [n]f32, f: f32) f32 {
    if (n == 1) {
        return vals[0];
    } else {
        return lerpAndReduceToOne(n - 1, lerpAndReduce(n, vals, f), f);
    }
}

pub fn FixedBufferList(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();

        buffer: [N]T = undefined,
        count: usize = 0,
        large: ?std.ArrayList(T),

        pub fn init(allocator: ?std.mem.Allocator) Self {
            return Self{
                .large = if (allocator) |allo|
                    std.ArrayList(T).init(allo)
                else
                    null,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.large) |*large| {
                large.deinit();
            }
        }

        pub fn append(self: *Self, value: T) !void {
            if (self.large) |*large| {
                try large.append(value);
                return;
            }
            if (self.count == N)
                return error.OutOfMemory;
            self.buffer[self.count] = value;
            self.count += 1;
        }

        pub fn popBack(self: *Self) ?T {
            if (self.large) |*large| {
                return large.pop();
            }

            if (self.count == 0)
                return null;
            self.count -= 1;
            return self.buffer[self.count];
        }

        pub fn itemsMut(self: *Self) []T {
            if (self.large) |*large| {
                return large.items;
            }
            return self.buffer[0..self.count];
        }

        pub fn items(self: *const Self) []const T {
            if (self.large) |*large| {
                return large.items;
            }
            return self.buffer[0..self.count];
        }

        pub fn front(self: *const Self) ?T {
            if (self.large) |*large| {
                if (large.items.len > 0) {
                    return large.items[0];
                } else {
                    return null;
                }
            }
            if (self.count == 0)
                return null;
            return self.buffer[0];
        }

        pub fn back(self: *const Self) ?T {
            if (self.large) |*large| {
                if (large.items.len > 0) {
                    return large.items[large.items.len - 1];
                } else {
                    return null;
                }
            }
            if (self.count == 0)
                return null;
            return self.buffer[self.count - 1];
        }
    };
}

fn floatToInt(comptime I: type, f: anytype) error{Overflow}!I {
    if (f < std.math.minInt(I))
        return error.Overflow;
    if (f > std.math.maxInt(I))
        return error.Overflow;
    return @intFromFloat(f);
}

fn floatToIntClamped(comptime I: type, f: anytype) I {
    if (std.math.isNan(f))
        @panic("NaN passed to floatToIntClamped!");
    if (f < std.math.minInt(I))
        return std.math.minInt(I);
    if (f > std.math.maxInt(I))
        return std.math.maxInt(I);
    return @intFromFloat(f);
}
