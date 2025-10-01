//! A collection of points that make up a shape that can later be rendered to the screen.
//!
//! This is the basic tool to create rectangles and more complex polygons to later be
//! turned into `Triangles` and rendered to the screen.

points: []const Point.Physical,

pub const Path = @This();

/// A builder with an ArrayList to add points to.
///
/// If a OutOfMemory error occurs, the builder with log it and ignore it,
/// meaning that you would get an incomplete path in that case. For rendering,
/// this will produce an incorrect output but will largely tend to work.
///
/// `Builder.deinit` should always be called as `Builder.build` does not give ownership
/// of the memory
pub const Builder = struct {
    points: std.array_list.Managed(Point.Physical),
    oom_error_occurred: bool = false,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .points = .init(allocator) };
    }

    pub fn deinit(path: *Builder) void {
        path.points.deinit();
    }

    /// Returns a non-owned `Path`. Calling `deinit` on the `Builder` is still required to free memory
    pub fn build(path: *Builder) Path {
        if (path.oom_error_occurred) {
            // This does not allow for error return traces, but
            // reduces spam caused by logs on every call to `addPoint`
            dvui.logError(@src(), std.mem.Allocator.Error.OutOfMemory, "Path encountered error and is likely incomplete", .{});
        }
        return .{ .points = path.points.items };
    }

    /// Add a point to the path
    pub fn addPoint(path: *Builder, p: Point.Physical) void {
        path.points.append(p) catch {
            path.oom_error_occurred = true;
        };
    }

    /// Add rounded rect to path.  Starts from top left, and ends at top right
    /// unclosed.  See `Rect.fill`.
    ///
    /// radius values:
    /// - x is top-left corner
    /// - y is top-right corner
    /// - w is bottom-right corner
    /// - h is bottom-left corner
    pub fn addRect(path: *Builder, r: Rect.Physical, radius: Rect.Physical) void {
        var rad = radius;
        const maxrad = @min(r.w, r.h) / 2;
        rad.x = @min(rad.x, maxrad);
        rad.y = @min(rad.y, maxrad);
        rad.w = @min(rad.w, maxrad);
        rad.h = @min(rad.h, maxrad);
        const tl = Point.Physical{ .x = r.x + rad.x, .y = r.y + rad.x };
        const bl = Point.Physical{ .x = r.x + rad.h, .y = r.y + r.h - rad.h };
        const br = Point.Physical{ .x = r.x + r.w - rad.w, .y = r.y + r.h - rad.w };
        const tr = Point.Physical{ .x = r.x + r.w - rad.y, .y = r.y + rad.y };
        path.addArc(tl, rad.x, math.pi * 1.5, math.pi, @abs(tl.y - bl.y) < 0.5);
        path.addArc(bl, rad.h, math.pi, math.pi * 0.5, @abs(bl.x - br.x) < 0.5);
        path.addArc(br, rad.w, math.pi * 0.5, 0, @abs(br.y - tr.y) < 0.5);
        path.addArc(tr, rad.y, math.pi * 2.0, math.pi * 1.5, @abs(tr.x - tl.x) < 0.5);
    }

    /// Add line segments creating an arc to path.
    ///
    /// `start` >= `end`, both are radians that go clockwise from the positive x axis.
    ///
    /// If `skip_end`, the final point will not be added.  Useful if the next
    /// addition to path would duplicate the end of the arc.
    pub fn addArc(path: *Builder, center: Point.Physical, radius: f32, start: f32, end: f32, skip_end: bool) void {
        if (radius == 0) {
            path.addPoint(center);
            return;
        }

        // how close our points will be to the perfect circle
        const err = 0.5;

        // angle that has err error between circle and segments
        const theta = math.acos(radius / (radius + err));

        var a: f32 = start;
        path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });

        while (a - end > theta) {
            // move to next fixed theta, this prevents shimmering on things like a spinner
            a = @floor((a - 0.001) / theta) * theta;
            path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
        }

        if (!skip_end) {
            a = end;
            path.addPoint(.{ .x = center.x + radius * @cos(a), .y = center.y + radius * @sin(a) });
        }
    }
};

test Builder {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    var builder = Path.Builder.init(std.testing.allocator);
    // deinit should always be called on the builder
    defer builder.deinit();

    builder.addRect(.{ .x = 10, .y = 20, .w = 30, .h = 40 }, .all(0));
    const path = builder.build();
    // path does not have to be freed as the memory is still
    // owned by and will be freed by the Path.Builder
    try std.testing.expectEqual(4, path.points.len);

    var triangles = try path.fillConvexTriangles(std.testing.allocator, .{ .color = Color.white });
    defer triangles.deinit(std.testing.allocator);
    try std.testing.expectApproxEqRel(10, triangles.bounds.x, 0.05);
    try std.testing.expectApproxEqRel(20, triangles.bounds.y, 0.05);
    try std.testing.expectApproxEqRel(30, triangles.bounds.w, 0.05);
    try std.testing.expectApproxEqRel(40, triangles.bounds.h, 0.05);
}

pub fn dupe(path: Path, allocator: std.mem.Allocator) std.mem.Allocator.Error!Path {
    return .{ .points = try allocator.dupe(Point.Physical, path.points) };
}

pub const FillConvexOptions = struct {
    color: Color,

    /// Size (physical pixels) of fade to transparent centered on the edge.
    /// If >1, then starts a half-pixel inside and the rest outside.
    fade: f32 = 0.0,
    center: ?Point.Physical = null,
};

/// Fill path (must be convex) with `color` (or `Theme.color_fill`).  See `Rect.fill`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn fillConvex(path: Path, opts: FillConvexOptions) void {
    if (path.points.len < 3) {
        return;
    }

    if (dvui.clipGet().empty()) {
        return;
    }

    const cw = dvui.currentWindow();

    if (!cw.render_target.rendering) {
        const new_path = path.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathFillConvex = .{ .path = new_path, .opts = opts } }, false);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = path.fillConvexTriangles(cw.lifo(), options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, null) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{options});
        return;
    };
}

/// Generates triangles to fill path (must be convex).
///
/// Vertexes will have unset uv and color is alpha multiplied opts.color
/// fading to transparent at the edge if fade is > 0.
pub fn fillConvexTriangles(path: Path, allocator: std.mem.Allocator, opts: FillConvexOptions) std.mem.Allocator.Error!Triangles {
    if (path.points.len < 3) {
        return .empty;
    }

    var vtx_count = path.points.len;
    var idx_count = (path.points.len - 2) * 3;
    if (opts.fade > 0) {
        vtx_count *= 2;
        idx_count += path.points.len * 6;
    }
    if (opts.center) |_| {
        vtx_count += 1;
        idx_count += 6;
    }

    var builder = try Triangles.Builder.init(allocator, vtx_count, idx_count);
    errdefer comptime unreachable; // No errors from this point on

    const col: Color.PMA = .fromColor(opts.color);

    var i: usize = 0;
    while (i < path.points.len) : (i += 1) {
        const ai: u16 = @intCast((i + path.points.len - 1) % path.points.len);
        const bi: u16 = @intCast(i % path.points.len);
        const ci: u16 = @intCast((i + 1) % path.points.len);
        const aa = path.points[ai];
        const bb = path.points[bi];
        const cc = path.points[ci];

        const diffab = aa.diff(bb).normalize();
        const diffbc = bb.diff(cc).normalize();
        // average of normals on each side
        var norm: Point.Physical = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

        // inner vertex
        const inside_len = @min(0.5, opts.fade / 2);
        builder.appendVertex(.{
            .pos = .{
                .x = bb.x - norm.x * inside_len,
                .y = bb.y - norm.y * inside_len,
            },
            .col = col,
        });

        const idx_ai = if (opts.fade > 0) ai * 2 else ai;
        const idx_bi = if (opts.fade > 0) bi * 2 else bi;

        // indexes for fill
        // triangles must be counter-clockwise (y going down) to avoid backface culling
        if (opts.center) |_| {
            builder.appendTriangles(&.{ @intCast(vtx_count - 1), idx_ai, idx_bi });
        } else if (i > 1) {
            builder.appendTriangles(&.{ 0, idx_ai, idx_bi });
        }

        if (opts.fade > 0) {
            // scale averaged normal by angle between which happens to be the same as
            // dividing by the length^2
            const d2 = norm.x * norm.x + norm.y * norm.y;
            if (d2 > 0.000001) {
                norm = norm.scale(1.0 / d2, Point.Physical);
            }

            // limit distance our vertexes can be from the point to 2 so
            // very small angles don't produce huge geometries
            const l = norm.length();
            if (l > 2.0) {
                norm = norm.scale(2.0 / l, Point.Physical);
            }

            // outer vertex
            const outside_len = if (opts.fade <= 1) opts.fade / 2 else opts.fade - 0.5;
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x + norm.x * outside_len,
                    .y = bb.y + norm.y * outside_len,
                },
                .col = .transparent,
            });

            // indexes for aa fade from inner to outer
            // triangles must be counter-clockwise (y going down) to avoid backface culling
            builder.appendTriangles(&.{
                idx_ai,     idx_ai + 1, idx_bi,
                idx_ai + 1, idx_bi + 1, idx_bi,
            });
        }
    }

    if (opts.center) |center| {
        builder.appendVertex(.{
            .pos = center,
            .col = col,
        });
    }

    return builder.build();
}

pub const StrokeOptions = struct {
    /// true => Render this after normal drawing on that subwindow.  Useful for
    /// debugging on cross-gui drawing.
    after: bool = false,

    thickness: f32,
    color: Color,

    /// true => Stroke includes from path end to path start.
    closed: bool = false,
    endcap_style: EndCapStyle = .none,

    pub const EndCapStyle = enum {
        none,
        square,
    };
};

/// Stroke path as a series of line segments.  See `Rect.stroke`.
///
/// Only valid between `Window.begin`and `Window.end`.
pub fn stroke(path: Path, opts: StrokeOptions) void {
    if (path.points.len == 0) {
        return;
    }

    const cw = dvui.currentWindow();

    if (opts.after or !cw.render_target.rendering) {
        const new_path = path.dupe(cw.arena()) catch |err| {
            dvui.logError(@src(), err, "Could not reallocate path for render command", .{});
            return;
        };
        cw.addRenderCommand(.{ .pathStroke = .{ .path = new_path, .opts = opts } }, opts.after);
        return;
    }

    var options = opts;
    options.color = options.color.opacity(cw.alpha);

    var triangles = path.strokeTriangles(cw.lifo(), options) catch |err| {
        dvui.logError(@src(), err, "Could not get triangles for path", .{});
        return;
    };
    defer triangles.deinit(cw.lifo());
    dvui.renderTriangles(triangles, null) catch |err| {
        dvui.logError(@src(), err, "Could not draw path, opts: {any}", .{opts});
        return;
    };
}

/// Generates triangles to stroke path.
///
/// Vertexes will have unset uv and color is alpha multiplied opts.color
/// fading to transparent at the edge.
pub fn strokeTriangles(path: Path, allocator: std.mem.Allocator, opts: StrokeOptions) std.mem.Allocator.Error!Triangles {
    if (dvui.clipGet().empty()) {
        return .empty;
    }

    if (path.points.len == 1) {
        // draw a circle with radius thickness at that point
        const center = path.points[0];

        const other_allocator = if (dvui.current_window) |cw|
            if (cw.lifo().ptr != allocator.ptr) cw.lifo() else cw.arena()
        else
            // Using the same allocator will "leak" the tempPath on
            // arena allocators because it can only free the last allocation
            allocator;

        var tempPath: Path.Builder = .init(other_allocator);
        defer tempPath.deinit();

        tempPath.addArc(center, opts.thickness, math.pi * 2.0, 0, true);
        return tempPath.build().fillConvexTriangles(allocator, .{ .color = opts.color, .fade = 1.0 });
    }

    const Side = enum {
        none,
        left,
        right,
    };

    // a single segment can't be closed
    const closed: bool = if (path.points.len == 2) false else opts.closed;

    var vtx_count = path.points.len * 8;
    if (!closed) {
        vtx_count += 4;
    }
    // max is 18 per leg (2 tri fill plus 4 tri fade)
    // plus (if miter is too long) 18 for fill and fade at each corner
    var idx_count = (path.points.len - 1) * 18 + (path.points.len - 2) * 18;
    if (closed) {
        idx_count += 18 + 2 * 18;
    } else {
        idx_count += 8 * 3;
    }

    var builder = try Triangles.Builder.init(allocator, vtx_count, idx_count);

    const col: Color.PMA = .fromColor(opts.color);

    const aa_size = 1.0;
    var vtx_left: u16 = 0;
    var vtx_right: u16 = 0;
    var i: usize = 0;
    const last_i: usize = if (closed) path.points.len + 1 else path.points.len;
    while (i < last_i) : (i += 1) {
        const ai: u16 = @intCast((i + path.points.len - 1) % path.points.len);
        const bi: u16 = @intCast(i % path.points.len);
        const ci: u16 = @intCast((i + 1) % path.points.len);
        const aa = path.points[ai];
        var bb = path.points[bi];
        const cc = path.points[ci];
        var miter_break: Side = .none;

        // the amount to move from bb to the edge of the line
        var halfnorm: Point.Physical = undefined;
        var halfnorm_miter: Point.Physical = undefined;
        var diffab: Point.Physical = undefined;

        if (!closed and ((i == 0) or ((i + 1) == path.points.len))) {
            if (i == 0) {
                const diffbc = bb.diff(cc).normalize();
                // rotate by 90 to get normal
                halfnorm = .{ .x = diffbc.y / 2, .y = (-diffbc.x) / 2 };

                if (opts.endcap_style == .square) {
                    // square endcaps move bb out by thickness
                    bb.x += diffbc.x * opts.thickness;
                    bb.y += diffbc.y * opts.thickness;
                }

                // add 2 extra vertexes for endcap fringe
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x - halfnorm.x * (opts.thickness + aa_size) + diffbc.x * aa_size,
                        .y = bb.y - halfnorm.y * (opts.thickness + aa_size) + diffbc.y * aa_size,
                    },
                    .col = .transparent,
                });

                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + halfnorm.x * (opts.thickness + aa_size) + diffbc.x * aa_size,
                        .y = bb.y + halfnorm.y * (opts.thickness + aa_size) + diffbc.y * aa_size,
                    },
                    .col = .transparent,
                });

                // add indexes for endcap fringe
                builder.appendTriangles(&.{
                    0, 2, 3,
                    0, 1, 2,
                    1, 4, 2,
                    1, 5, 4,
                });
            } else if ((i + 1) == path.points.len) {
                diffab = aa.diff(bb).normalize();
                // rotate by 90 to get normal
                halfnorm = .{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                if (opts.endcap_style == .square) {
                    // square endcaps move bb out by thickness
                    bb.x -= diffab.x * opts.thickness;
                    bb.y -= diffab.y * opts.thickness;
                }
            }
        } else {
            diffab = aa.diff(bb).normalize();
            const diffbc = bb.diff(cc).normalize();
            // average of normals on each side
            halfnorm = .{ .x = (diffab.y + diffbc.y) / 2, .y = (-diffab.x - diffbc.x) / 2 };

            // scale averaged normal by angle between which happens to be the same as
            // dividing by the length^2
            const d2 = halfnorm.x * halfnorm.x + halfnorm.y * halfnorm.y;
            if (d2 > 0.000001) {
                halfnorm = halfnorm.scale(0.5 / d2, Point.Physical);
            } else {
                // degenerate case - ab and bc are on top of each other
                halfnorm = aa.diff(bb);
            }

            // limit distance our vertexes can be from the point to 2 * thickness so
            // very small angles don't produce huge geometries
            const l = halfnorm.length();
            if (l > 2.0) {
                halfnorm_miter = halfnorm.scale(2.0 / l, Point.Physical);

                const hn_len = halfnorm.length() * (opts.thickness + aa_size);
                const ab_len = aa.diff(bb).length();
                const bc_len = bb.diff(cc).length();
                const max_len = @min(hn_len, ab_len, bc_len);
                if (max_len < hn_len) {
                    halfnorm = halfnorm.scale(max_len / hn_len, Point.Physical);
                }

                const dot = diffab.x * halfnorm.x + diffab.y * halfnorm.y;
                if (dot > 0) {
                    miter_break = .left;
                } else {
                    miter_break = .right;
                }
            }
        }

        const vtx_base: u16 = if (i == path.points.len) 0 else @intCast(builder.vertexes.items.len);
        var vtx_left_in = vtx_base;
        var vtx_right_in = vtx_left_in + 2;

        var vtx_left_out = vtx_left_in;
        var vtx_right_out = vtx_right_in;

        switch (miter_break) {
            .none => {},
            .left => {
                vtx_left_in += 4;
                vtx_left_out += 6;
            },
            .right => {
                vtx_right_in += 2;
                vtx_right_out += 4;
            },
        }

        if (i < path.points.len) {
            {
                const hn = if (miter_break == .left) halfnorm_miter else halfnorm;
                // left inner vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x - hn.x * opts.thickness,
                        .y = bb.y - hn.y * opts.thickness,
                    },
                    .col = col,
                });

                // left AA vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x - hn.x * (opts.thickness + aa_size),
                        .y = bb.y - hn.y * (opts.thickness + aa_size),
                    },
                    .col = .transparent,
                });
            }

            {
                const hn = if (miter_break == .right) halfnorm_miter else halfnorm;
                // right inner vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + hn.x * opts.thickness,
                        .y = bb.y + hn.y * opts.thickness,
                    },
                    .col = col,
                });

                // right AA vertex
                builder.appendVertex(.{
                    .pos = .{
                        .x = bb.x + hn.x * (opts.thickness + aa_size),
                        .y = bb.y + hn.y * (opts.thickness + aa_size),
                    },
                    .col = .transparent,
                });
            }

            switch (miter_break) {
                .none => {},
                .left => {
                    const hn = .{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                    // left bump start inner (vtx_left_in)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * opts.thickness,
                            .y = bb.y - hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // left bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * (opts.thickness + aa_size),
                            .y = bb.y - hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // right bump start inner (vtx_left_out)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * opts.thickness,
                            .y = bb.y + hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // right bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * (opts.thickness + aa_size),
                            .y = bb.y + hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // add triangles to fill the miter (counter clockwise y going down)
                    builder.appendTriangles(&.{
                        // indexes for fill
                        vtx_left_in, vtx_base + 2,     vtx_base,
                        vtx_base,    vtx_base + 2,     vtx_left_out,

                        // aa fade
                        vtx_left_in, vtx_base,         vtx_left_in + 1,
                        vtx_base,    vtx_base + 1,     vtx_left_in + 1,

                        vtx_base,    vtx_left_out,     vtx_left_out + 1,
                        vtx_base,    vtx_left_out + 1, vtx_base + 1,
                    });
                },
                .right => {
                    const hn = .{ .x = diffab.y / 2, .y = (-diffab.x) / 2 };

                    // right bump start inner (vtx_right_in)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * opts.thickness,
                            .y = bb.y + hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // right bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x + hn.x * (opts.thickness + aa_size),
                            .y = bb.y + hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // left bump start inner (vtx_right_out)
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * opts.thickness,
                            .y = bb.y - hn.y * opts.thickness,
                        },
                        .col = col,
                    });

                    // left bump start AA vertex
                    builder.appendVertex(.{
                        .pos = .{
                            .x = bb.x - hn.x * (opts.thickness + aa_size),
                            .y = bb.y - hn.y * (opts.thickness + aa_size),
                        },
                        .col = .transparent,
                    });

                    // add triangles to fill the miter (counter clockwise y going down)
                    builder.appendTriangles(&.{
                        // indexes for fill
                        vtx_right_in,     vtx_base + 2,      vtx_base,
                        vtx_base,         vtx_base + 2,      vtx_right_out,

                        // aa fade
                        vtx_right_in,     vtx_right_in + 1,  vtx_base + 2,
                        vtx_right_in + 1, vtx_base + 3,      vtx_base + 2,

                        vtx_base + 2,     vtx_base + 3,      vtx_right_out,
                        vtx_base + 3,     vtx_right_out + 1, vtx_right_out,
                    });
                },
            }
        }

        // triangles must be counter-clockwise (y going down) to avoid backface culling
        if ((i > 0) and (closed or (i < path.points.len))) {
            // vtx1 wraps when closed
            builder.appendTriangles(&.{
                // indexes for fill
                vtx_left,  vtx_right,        vtx_left_in,
                vtx_right, vtx_right_in,     vtx_left_in,

                // indexes for aa fade from inner to outer left side
                vtx_left,  vtx_left_in + 1,  vtx_left + 1,
                vtx_left,  vtx_left_in,      vtx_left_in + 1,

                // indexes for aa fade from inner to outer right side
                vtx_right, vtx_right + 1,    vtx_right_in + 1,
                vtx_right, vtx_right_in + 1, vtx_right_in,
            });
        }

        if (!closed and (i + 1) == path.points.len) {
            // add 2 extra vertexes for endcap fringe

            const vtx: u16 = @intCast(builder.vertexes.items.len);
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x - halfnorm.x * (opts.thickness + aa_size) - diffab.x * aa_size,
                    .y = bb.y - halfnorm.y * (opts.thickness + aa_size) - diffab.y * aa_size,
                },
                .col = .transparent,
            });
            builder.appendVertex(.{
                .pos = .{
                    .x = bb.x + halfnorm.x * (opts.thickness + aa_size) - diffab.x * aa_size,
                    .y = bb.y + halfnorm.y * (opts.thickness + aa_size) - diffab.y * aa_size,
                },
                .col = .transparent,
            });

            builder.appendTriangles(&.{
                // add indexes for endcap fringe
                vtx_left_in,  vtx,              vtx_left_in + 1,
                vtx,          vtx_left_in,      vtx_right_in,
                vtx,          vtx_right_in,     vtx + 1,
                vtx_right_in, vtx_right_in + 1, vtx + 1,
            });
        }

        vtx_left = vtx_left_out;
        vtx_right = vtx_right_out;
    }

    return builder.build();
}

const std = @import("std");
const dvui = @import("dvui.zig");

const math = dvui.math;
const Rect = dvui.Rect;
const Point = dvui.Point;
const Color = dvui.Color;
const Triangles = dvui.Triangles;

test {
    @import("std").testing.refAllDecls(@This());
}
