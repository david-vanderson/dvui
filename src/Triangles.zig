vertexes: []Vertex,
indices: []u16,
bounds: Rect.Physical,

pub const Triangles = @This();

pub const empty = Triangles{
    .vertexes = &.{},
    .indices = &.{},
    .bounds = .{},
};

/// A builder for Triangles that assumes the exact number of
/// vertexes and indices is known
pub const Builder = struct {
    vertexes: std.ArrayListUnmanaged(Vertex),
    indices: std.ArrayListUnmanaged(u16),
    /// w and h is max_x and max_y
    bounds: Rect.Physical = .{
        .x = math.floatMax(f32),
        .y = math.floatMax(f32),
        .w = -math.floatMax(f32),
        .h = -math.floatMax(f32),
    },

    pub fn init(allocator: std.mem.Allocator, vtx_count: usize, idx_count: usize) std.mem.Allocator.Error!Builder {
        std.debug.assert(vtx_count >= 3);
        std.debug.assert(idx_count % 3 == 0);
        var vtx: @FieldType(Builder, "vertexes") = try .initCapacity(allocator, vtx_count);
        errdefer vtx.deinit(allocator);
        return .{
            .vertexes = vtx,
            .indices = try .initCapacity(allocator, idx_count),
        };
    }

    pub fn deinit(self: *Builder, allocator: std.mem.Allocator) void {
        defer self.* = undefined;
        // NOTE: Should be in the opposite order to `init`
        self.indices.deinit(allocator);
        self.vertexes.deinit(allocator);
    }

    /// Appends a vertex and updates the bounds
    pub fn appendVertex(self: *Builder, v: Vertex) void {
        self.vertexes.appendAssumeCapacity(v);
        self.bounds.x = @min(self.bounds.x, v.pos.x);
        self.bounds.y = @min(self.bounds.y, v.pos.y);
        self.bounds.w = @max(self.bounds.w, v.pos.x);
        self.bounds.h = @max(self.bounds.h, v.pos.y);
    }

    /// Triangles must be counter-clockwise (y going down) to avoid backface culling
    ///
    /// Asserts that points is a multiple of 3
    pub fn appendTriangles(self: *Builder, points: []const u16) void {
        std.debug.assert(points.len % 3 == 0);
        self.indices.appendSliceAssumeCapacity(points);
    }

    /// Asserts that the entire array has been filled
    ///
    /// The memory ownership is transferred to `Triangles`.
    /// making `Builder.deinit` unnecessary, but safe, to call
    pub fn build(self: *Builder) Triangles {
        defer self.* = .{ .vertexes = .empty, .indices = .empty };
        // Ownership is transferred as the the full allocated slices are returned
        return self.build_unowned();
    }

    /// Creates `Triangles`, ignoring any extra capacity.
    ///
    /// Calling `Triangles.deinit` is invalid and `Builder.deinit`
    /// should always be called instead
    pub fn build_unowned(self: *Builder) Triangles {
        return .{
            .vertexes = self.vertexes.items,
            .indices = self.indices.items,
            // convert bounds w/h back to width/height
            .bounds = self.bounds.toPoint(.{
                .x = self.bounds.w,
                .y = self.bounds.h,
            }),
        };
    }
};

pub fn dupe(self: *const Triangles, allocator: std.mem.Allocator) std.mem.Allocator.Error!Triangles {
    const vtx = try allocator.dupe(Vertex, self.vertexes);
    errdefer allocator.free(vtx);
    return .{
        .vertexes = vtx,
        .indices = try allocator.dupe(u16, self.indices),
        .bounds = self.bounds,
    };
}

pub fn deinit(self: *Triangles, allocator: std.mem.Allocator) void {
    defer self.* = undefined;
    allocator.free(self.indices);
    allocator.free(self.vertexes);
}

/// Multiply `col` into vertex colors.
pub fn color(self: *Triangles, col: Color) void {
    if (col.r == 0xff and col.g == 0xff and col.b == 0xff and col.a == 0xff)
        return;

    const pma_col: Color.PMA = .fromColor(col);
    for (self.vertexes) |*v| {
        v.col = v.col.multiply(pma_col);
    }
}

/// Set uv coords of vertexes according to position in r (with r_uv coords
/// at corners), clamped to 0-1.
pub fn uvFromRectuv(self: *Triangles, r: Rect.Physical, r_uv: Rect) void {
    for (self.vertexes) |*v| {
        const xfrac = (v.pos.x - r.x) / r.w;
        v.uv[0] = std.math.clamp(r_uv.x + xfrac * r_uv.w, 0, 1);

        const yfrac = (v.pos.y - r.y) / r.h;
        v.uv[1] = std.math.clamp(r_uv.y + yfrac * r_uv.h, 0, 1);
    }
}

/// Rotate vertexes around origin by radians (positive clockwise).
pub fn rotate(self: *Triangles, origin: Point.Physical, radians: f32) void {
    if (radians == 0) return;

    const cos = @cos(radians);
    const sin = @sin(radians);

    for (self.vertexes) |*v| {
        // get vector from origin to point
        const d = v.pos.diff(origin);

        // rotate vector
        const rotated: Point.Physical = .{
            .x = d.x * cos - d.y * sin,
            .y = d.x * sin + d.y * cos,
        };

        v.pos = origin.plus(rotated);
    }

    // recalc bounds
    var points: [4]Point.Physical = .{
        self.bounds.topLeft(),
        self.bounds.topRight(),
        self.bounds.bottomRight(),
        self.bounds.bottomLeft(),
    };

    for (&points) |*p| {
        // get vector from origin to point
        const d = p.diff(origin);

        // rotate vector
        const rotated: Point.Physical = .{
            .x = d.x * cos - d.y * sin,
            .y = d.x * sin + d.y * cos,
        };

        p.* = origin.plus(rotated);
    }

    self.bounds.x = @min(points[0].x, points[1].x, points[2].x, points[3].x);
    self.bounds.y = @min(points[0].y, points[1].y, points[2].y, points[3].y);
    self.bounds.w = @max(points[0].x, points[1].x, points[2].x, points[3].x);
    self.bounds.w -= self.bounds.x;
    self.bounds.h = @max(points[0].y, points[1].y, points[2].y, points[3].y);
    self.bounds.h -= self.bounds.y;
}

const std = @import("std");
const dvui = @import("dvui.zig");

const math = dvui.math;
const Vertex = dvui.Vertex;
const Color = dvui.Color;
const Point = dvui.Point;
const Rect = dvui.Rect;

test {
    @import("std").testing.refAllDecls(@This());
}
