pub const Gradient = union(enum) {
    /// NOTE: stops only need to live as long as the call that hands it to dvui
    /// all defered rendering should dupe
    linear: struct {
        /// Sorted ascending by `offset`. Must have at least 1 stop.
        /// Positions before the first stop or after the last just take that
        /// stop's color (matches CSS/SVG gradients) — no need for stops at
        /// exactly 0 and 1.
        stops: []const Stop,
        /// 0 = left-to-right, 90 = top-to-bottom, clockwise.
        angle_degrees: f32 = 90,
        /// Overrides the bounding box the gradient is computed against
        /// (physical pixels), instead of the shape's own bounds. Lets
        /// separate widgets share one continuous gradient sweep — pass
        /// e.g. a parent's rect. CSS gradients are always local to their
        /// own box and can't do this.
        anchor: ?Rect.Physical = null,
        /// Multiplies every stop's alpha (see `Gradient.opacity`).
        alpha: f32 = 1.0,
    },
    radial: struct {
        /// See `linear.stops`.
        stops: []const Stop,
        shape: Shape = .{ .ellipse = .{} },
        extent: Extent = .farthest_corner,
        /// Gradient center, as a fraction of the bounding box (0,0 = top-left
        /// corner, 1,1 = bottom-right corner). Defaults to the box center.
        position: struct { x: f32 = 0.5, y: f32 = 0.5 } = .{},
        /// SVG-style focal point (as a fraction of the bounding box, same
        /// convention as `position`): where the 0%-offset point sits.
        /// Defaults to `position` (the ending shape's own center) when
        /// null, matching CSS. Offsetting it from `position` gives a
        /// sphere/light-source highlight CSS radial-gradient() can't do.
        focal: ?struct { x: f32, y: f32 } = null,
        /// See `linear.anchor`.
        anchor: ?Rect.Physical = null,
        /// See `linear.alpha`.
        alpha: f32 = 1.0,
    },
    /// Arbitrary 2D-positioned color stops, blended by inverse-distance²
    /// weighting: `weight_i = 1/distance^2`, snapping to a stop's exact
    /// color if `pos` lands on it, else
    /// `color = sum(weight_i*color_i) / sum(weight_i)`.
    scattered: struct {
        stops: []const ScatterStop,
        /// See `linear.anchor`.
        anchor: ?Rect.Physical = null,
        /// See `linear.alpha`.
        alpha: f32 = 1.0,
    },

    pub const Shape = union(enum) {
        /// radius in natural pixels (like `Options.border` etc.,
        /// scaled to physical by the widget before rendering), overriding
        /// `extent`'s keyword sizing.
        circle: struct { radius: ?f32 = null },
        ellipse: struct {
            /// Explicit x/y radii in natural pixels (see `circle.radius`),
            /// overriding `extent`'s keyword sizing (CSS
            /// `radial-gradient(50px 30px at ...)`).
            size: ?struct { x: f32, y: f32 } = null,
            /// Rotates the ending ellipse clockwise by this many degrees.
            /// CSS radial-gradient() can't rotate its ellipse at all.
            rotation_degrees: f32 = 0,
        },
    };

    /// How far the gradient's ending shape extends before reaching the last
    /// stop. Mirrors CSS `radial-gradient()`'s `<size>` keywords.
    pub const Extent = enum { closest_side, farthest_side, closest_corner, farthest_corner };

    pub const Stop = struct { color: Color, offset: f32 };

    /// A `scattered`-gradient stop: `x`/`y` are a fraction [0,1] of the
    /// bounding box (same convention as `radial.position`).
    pub const ScatterStop = struct { color: Color, x: f32, y: f32 };

    /// `firstColor`, without the `alpha` multiplier applied. Used
    /// internally as the placeholder color for antialiasing fade vertexes
    /// before `apply` resamples them -- `apply`/`sample` apply `alpha`
    /// themselves, so baking it in here too would double it up.
    fn firstColorRaw(gradient: Gradient) Color {
        return switch (gradient) {
            inline else => |g| g.stops[0].color,
        };
    }

    /// The gradient's own first stop (with `alpha` applied), used as a flat
    /// representative color where a full gradient can't be expressed (see
    /// `ColorOrGradient.toColor`).
    pub fn firstColor(gradient: Gradient) Color {
        return switch (gradient) {
            inline else => |g| g.stops[0].color.opacity(g.alpha),
        };
    }

    /// Multiply the gradient's overall opacity by `mult` (see
    /// `Color.opacity`), applied on top of every stop's own alpha at sample
    /// time. Just flips the `alpha` multiplier field -- doesn't touch
    /// `stops`, which is a caller-owned/shared const slice.
    pub fn opacity(gradient: Gradient, mult: f32) Gradient {
        var g = gradient;
        switch (g) {
            inline else => |*v| v.alpha *= mult,
        }
        return g;
    }

    /// Scales natural-pixel fields (`radial.shape`'s `circle.radius` /
    /// `ellipse.size`) by `s`, the same way `Options.cornersGet()` and
    /// border thickness get scaled before rendering. `anchor` is left
    /// alone
    pub fn scale(gradient: Gradient, s: f32) Gradient {
        var g = gradient;
        switch (g) {
            .radial => |*r| switch (r.shape) {
                .circle => |*c| if (c.radius) |*radius| {
                    radius.* *= s;
                },
                .ellipse => |*e| if (e.size) |*sz| {
                    sz.x *= s;
                    sz.y *= s;
                },
            },
            .linear, .scattered => {},
        }
        return g;
    }

    /// Copies `stops` into memory owned by `allocator`, returning a
    /// `Gradient` that no longer depends on the caller's slice. See the
    pub fn dupe(gradient: Gradient, allocator: std.mem.Allocator) std.mem.Allocator.Error!Gradient {
        var g = gradient;
        switch (g) {
            .linear => |*l| l.stops = try allocator.dupe(Stop, l.stops),
            .radial => |*r| r.stops = try allocator.dupe(Stop, r.stops),
            .scattered => |*s| s.stops = try allocator.dupe(ScatterStop, s.stops),
        }
        return g;
    }

    /// Interpolates through `stops` at position `t`. Positions before the
    /// first stop or after the last clamp to that stop's color.
    fn interpolate(stops: []const Stop, t: f32) Color {
        if (t <= stops[0].offset) return stops[0].color;
        var prev = stops[0];
        for (stops[1..]) |s| {
            if (t <= s.offset) {
                const span = s.offset - prev.offset;
                const local_t = if (span <= 0) 0 else (t - prev.offset) / span;
                return prev.color.lerp(s.color, std.math.clamp(local_t, 0, 1));
            }
            prev = s;
        }
        return prev.color;
    }

    /// The analytic gradient position `t` (0-1) for `linear` at `pos`, or
    /// `null` if the bounds are degenerate (caller should use `firstColor`).
    /// Factored out of `sample` so `apply` can assign it directly to a
    /// vertex's UV instead of baking a color from it.
    fn linearT(g: anytype, bounds: Rect.Physical, pos: Point.Physical) ?f32 {
        const cx = bounds.x + bounds.w / 2;
        const cy = bounds.y + bounds.h / 2;
        const rad = std.math.degreesToRadians(g.angle_degrees);
        const dir: Point.Physical = .{ .x = @cos(rad), .y = @sin(rad) };
        const hx = bounds.w / 2;
        const hy = bounds.h / 2;

        // Half-extent of the bounding box projected onto dir (distance from
        // center to the corner furthest along the gradient axis).
        const half_extent = @abs(dir.x) * hx + @abs(dir.y) * hy;
        if (half_extent <= 0) return null;

        const proj = (pos.x - cx) * dir.x + (pos.y - cy) * dir.y;
        return std.math.clamp((proj / half_extent + 1) / 2, 0, 1);
    }

    /// The ending shape's center, radii, and rotation (sin/cos, identity
    /// when unrotated) for `radial`, resolved from `shape`/`extent`/
    /// `position` against `bounds`. Shared by the focal-point solve, the
    /// non-focal `t = length(nx,ny)` path, and the non-focal ramp-texture UV
    /// path (`radialUV`) below. `null` if the ending shape is degenerate
    /// (zero radius).
    const RadialGeometry = struct { px: f32, py: f32, rx: f32, ry: f32, cs: f32, sn: f32 };
    fn radialGeometry(g: anytype, bounds: Rect.Physical) ?RadialGeometry {
        const px = bounds.x + g.position.x * bounds.w;
        const py = bounds.y + g.position.y * bounds.h;

        // Distances from the gradient center to each side of the box;
        // can be asymmetric when `position` is off-center.
        const left = px - bounds.x;
        const right = (bounds.x + bounds.w) - px;
        const top = py - bounds.y;
        const bottom = (bounds.y + bounds.h) - py;

        var rx: f32 = 0;
        var ry: f32 = 0;
        switch (g.shape) {
            .circle => |c| if (c.radius) |r| {
                rx = r;
                ry = r;
            } else {
                rx = switch (g.extent) {
                    .closest_side => @min(@min(left, right), @min(top, bottom)),
                    .farthest_side => @max(@max(left, right), @max(top, bottom)),
                    .closest_corner, .farthest_corner => blk: {
                        const closest = g.extent == .closest_corner;
                        const sx = if (closest) @min(left, right) else @max(left, right);
                        const sy = if (closest) @min(top, bottom) else @max(top, bottom);
                        break :blk @sqrt(sx * sx + sy * sy);
                    },
                };
                ry = rx;
            },
            .ellipse => |e| if (e.size) |sz| {
                rx = sz.x;
                ry = sz.y;
            } else switch (g.extent) {
                .closest_side => {
                    rx = @min(left, right);
                    ry = @min(top, bottom);
                },
                .farthest_side => {
                    rx = @max(left, right);
                    ry = @max(top, bottom);
                },
                .closest_corner, .farthest_corner => {
                    // Ellipse sized to pass exactly through the closest/farthest
                    // corner while keeping the aspect ratio of the corresponding
                    // *_side extents (matches CSS radial-gradient() sizing).
                    const closest = g.extent == .closest_corner;
                    const sx = if (closest) @min(left, right) else @max(left, right);
                    const sy = if (closest) @min(top, bottom) else @max(top, bottom);
                    rx = sx * std.math.sqrt2;
                    ry = sy * std.math.sqrt2;
                },
            },
        }
        if (rx <= 0 or ry <= 0) return null;

        const rotation_degrees: f32 = if (g.shape == .ellipse) g.shape.ellipse.rotation_degrees else 0;
        const rot = rotation_degrees != 0;
        const cs = if (rot) @cos(std.math.degreesToRadians(-rotation_degrees)) else 1;
        const sn = if (rot) @sin(std.math.degreesToRadians(-rotation_degrees)) else 0;
        return .{ .px = px, .py = py, .rx = rx, .ry = ry, .cs = cs, .sn = sn };
    }

    /// Radial `(nx,ny)`: `pos` in the ending shape's local, axis-aligned,
    /// unit-circle space. For non-focal radial, `length(nx,ny)` is the
    /// gradient's `t` (clamped to [0,1] by the caller); for focal radial,
    /// `focalRadialT` turns it (plus the focal point's own `(nx,ny)`) into
    /// `t`. Either way, unlike `t` itself, `(nx,ny)` is an *affine* function
    /// of `pos` (rotation/translation/scale, no `sqrt`), so it can be
    /// assigned directly to a vertex's UV and interpolated exactly by the
    /// GPU across a plain (non-subdivided) quad - see `apply`'s `radial`
    /// branch.
    fn radialUV(geo: RadialGeometry, pos: Point.Physical) [2]f32 {
        const dx = pos.x - geo.px;
        const dy = pos.y - geo.py;
        const rdx = dx * geo.cs - dy * geo.sn;
        const rdy = dx * geo.sn + dy * geo.cs;
        return .{ rdx / geo.rx, rdy / geo.ry };
    }

    /// Focal-point radial gradient's `t` as a function of the *affine* `(u,v)`
    /// (from `radialUV(geo, pos)`) and the focal point's own affine
    /// coordinates `(fu,fv)` (from `radialUV(geo, focalPos)`, constant for a
    /// given draw).
    ///
    /// SVG-style focal point: `t` is the fraction of the way from the focal
    /// point to the ellipse boundary along the ray toward `pos`. Substituting
    /// `d = (u,v) - (fu,fv)` into the boundary-crossing quadratic
    /// (`|F + s*d| = 1` for the unit circle `(u,v)` lives in) makes it solely
    /// a function of `(u,v)` and the constant `(fu,fv)` - despite `t` itself
    /// not being affine in `pos`, `(u,v)` is, so this can be baked into a 2D
    /// ramp texture sampled via UV instead of resampled per subdivided
    /// vertex (mirrors `rampTexture2D`'s trick for non-focal radial).
    fn focalRadialT(u: f32, v: f32, fu: f32, fv: f32) f32 {
        const dx = u - fu;
        const dy = v - fv;
        const a = dx * dx + dy * dy;
        if (a <= 0) return 0;
        const b = 2 * (fu * dx + fv * dy);
        const c = fu * fu + fv * fv - 1;
        const disc = b * b - 4 * a * c;
        if (disc < 0) return 1;
        const sq = @sqrt(disc);
        const s = @max((-b + sq) / (2 * a), (-b - sq) / (2 * a));
        return if (s <= 0) 1 else std.math.clamp(1.0 / s, 0, 1);
    }

    /// `scattered`'s `(u,v)`: `pos` as a fraction of `bounds` (same
    /// convention as a stop's `x`/`y`), affine in `pos` like `radialUV`.
    /// Guards against a degenerate (zero-width/height) axis rather than
    /// dividing by zero - the numerator is 0 in that case anyway since
    /// `pos` can't extend along a zero-size axis.
    fn scatteredUV(bounds: Rect.Physical, pos: Point.Physical) [2]f32 {
        const bw = if (bounds.w > 0) bounds.w else 1;
        const bh = if (bounds.h > 0) bounds.h else 1;
        return .{ (pos.x - bounds.x) / bw, (pos.y - bounds.y) / bh };
    }

    /// `scattered`'s inverse-distance-squared blend (see the `scattered`
    /// field doc comment), evaluated at the affine `(u,v)` from
    /// `scatteredUV` against stops' own `(x,y)` (already bounds fractions).
    /// Since it's a fixed function of that affine `(u,v)`, it can be baked
    /// into a 2D ramp texture sampled via UV instead of resampled per
    /// subdivided vertex, same as `focalRadialT`/`rampTexture2D`. Returns
    /// `null` if there are no stops (caller should use `firstColor`).
    fn scatteredColorAt(stops: []const ScatterStop, u: f32, v: f32) ?Color {
        if (stops.len == 0) return null;
        var wsum: f32 = 0;
        var r: f32 = 0;
        var gg: f32 = 0;
        var bb: f32 = 0;
        var aa: f32 = 0;
        for (stops) |s| {
            const dx = u - s.x;
            const dy = v - s.y;
            const dist2 = dx * dx + dy * dy;
            if (dist2 == 0) return s.color;
            const w = 1.0 / dist2;
            wsum += w;
            r += w * @as(f32, @floatFromInt(s.color.r));
            gg += w * @as(f32, @floatFromInt(s.color.g));
            bb += w * @as(f32, @floatFromInt(s.color.b));
            aa += w * @as(f32, @floatFromInt(s.color.a));
        }
        if (wsum <= 0) return null;
        return .{
            .r = @intFromFloat(std.math.clamp(r / wsum, 0, 255)),
            .g = @intFromFloat(std.math.clamp(gg / wsum, 0, 255)),
            .b = @intFromFloat(std.math.clamp(bb / wsum, 0, 255)),
            .a = @intFromFloat(std.math.clamp(aa / wsum, 0, 255)),
        };
    }

    /// Samples the gradient's raw color (per-stop alpha, no `alpha`
    /// multiplier) at `pos`. `sample` wraps this with the `alpha`
    /// multiplier applied once, uniformly, regardless of which branch below
    /// produced the color.
    fn sampleRaw(gradient: Gradient, bounds_in: Rect.Physical, pos: Point.Physical) Color {
        const bounds = switch (gradient) {
            inline else => |g| g.anchor orelse bounds_in,
        };
        const base = gradient.firstColorRaw();
        if (bounds.w <= 0 and bounds.h <= 0) return base;
        switch (gradient) {
            .linear => |g| {
                const t = linearT(g, bounds, pos) orelse return base;
                return interpolate(g.stops, t);
            },
            .radial => |g| {
                const geo = radialGeometry(g, bounds) orelse return base;

                const uv = radialUV(geo, pos);
                if (g.focal) |f| {
                    const fuv = radialUV(geo, .{ .x = bounds.x + f.x * bounds.w, .y = bounds.y + f.y * bounds.h });
                    const t = focalRadialT(uv[0], uv[1], fuv[0], fuv[1]);
                    return interpolate(g.stops, t);
                }

                const t = std.math.clamp(@sqrt(uv[0] * uv[0] + uv[1] * uv[1]), 0, 1);
                return interpolate(g.stops, t);
            },
            .scattered => |g| {
                if (g.stops.len == 0) return base;
                const uv = scatteredUV(bounds, pos);
                return scatteredColorAt(g.stops, uv[0], uv[1]) orelse base;
            },
        }
    }

    /// Like `sampleRaw`, with the gradient's `alpha` multiplier applied.
    /// Public so text rendering can Gouraud-sample it per glyph-quad vertex
    /// instead of going through `apply`'s ramp-texture trick (see
    /// `render.renderText`).
    pub fn sample(gradient: Gradient, bounds_in: Rect.Physical, pos: Point.Physical) Color {
        const alpha = switch (gradient) {
            inline else => |g| g.alpha,
        };
        return gradient.sampleRaw(bounds_in, pos).opacity(alpha);
    }

    /// Width of the 1D ramp texture generated for `linear` gradients by
    /// `rampTexture`.
    const ramp_width = 256;

    /// Builds (or fetches from the texture cache) a `ramp_width`x1 texture
    /// holding `interpolate(stops, t)` across its width, keyed by the
    /// stops' contents. Used so `linear` gradients can be drawn via UV +
    /// texture sampling instead of baking colors at vertexes: `t` is affine
    /// in `(x,y)` for a linear gradient, but `interpolate` is only
    /// piecewise-affine once there are 3+ stops, so composing it with
    /// Gouraud (vertex-color) interpolation produces visibly wrong results
    /// off the gradient axis. UV interpolation reproduces the affine `t`
    /// exactly, and the texture reproduces `interpolate` exactly.
    fn linearKey(stops: []const Stop, alpha: f32) dvui.Texture.Cache.Key {
        var hasher = dvui.fnv.init();
        for (stops) |s| {
            hasher.update(std.mem.asBytes(&s.offset));
            hasher.update(std.mem.asBytes(&s.color));
        }
        hasher.update(std.mem.asBytes(&alpha));
        return hasher.final();
    }

    fn rampTexture(stops: []const Stop, alpha: f32) (std.mem.Allocator.Error || dvui.Backend.TextureError)!dvui.Texture {
        const key = linearKey(stops, alpha);
        if (dvui.textureGetCached(key)) |cached| return cached;

        var pixels: [ramp_width]Color.PMA = undefined;
        for (&pixels, 0..) |*px, i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ramp_width - 1));
            px.* = .fromColor(interpolate(stops, t).opacity(alpha));
        }
        const tex = try dvui.Texture.fromPixelsPMA(&pixels, ramp_width, 1, .linear);
        dvui.textureAddToCache(key, tex);
        return tex;
    }

    /// Side length of the square 2D ramp texture generated for non-focal
    /// `radial` gradients by `rampTexture2D`.
    const ramp2d_width = 64;

    /// Builds (or fetches from the texture cache) a `ramp2d_width`^2 texture
    /// holding `interpolate(stops, clamp(length(u,v), 0, 1))` for `(u,v)`
    /// covering `[-1,1]^2`, keyed by the stops' contents. Mirrors
    /// `rampTexture`, but 2D: a non-focal radial gradient's `(nx,ny)` (see
    /// `radialUV`) is affine in position, but the final `t = length(nx,ny)`
    /// isn't, so unlike `linear` the nonlinear step has to live in the
    /// texture rather than the UV itself. Texture sampling clamps to the
    /// edge texel (`Texture.CreateOptions.wrap_*` defaults to `.clamp`), and
    /// clamping `(u,v)` per-axis to the last texel still yields
    /// `length >= 1` on that axis, so any `(u,v)` outside `[-1,1]^2` reads
    /// back the same saturated last-stop color `t=1` would - no separate
    /// clamp of `(u,v)` is needed before mapping to texture space.
    fn radialKey(stops: []const Stop, alpha: f32) dvui.Texture.Cache.Key {
        var hasher = dvui.fnv.init();
        hasher.update("radial2d"); // distinguish from `rampTexture`'s 1D cache key
        for (stops) |s| {
            hasher.update(std.mem.asBytes(&s.offset));
            hasher.update(std.mem.asBytes(&s.color));
        }
        hasher.update(std.mem.asBytes(&alpha));
        return hasher.final();
    }

    fn rampTexture2D(stops: []const Stop, alpha: f32) (std.mem.Allocator.Error || dvui.Backend.TextureError)!dvui.Texture {
        const key = radialKey(stops, alpha);
        if (dvui.textureGetCached(key)) |cached| return cached;

        var pixels: [ramp2d_width * ramp2d_width]Color.PMA = undefined;
        for (0..ramp2d_width) |row| {
            const v = 2 * (@as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(ramp2d_width - 1))) - 1;
            for (0..ramp2d_width) |col| {
                const u = 2 * (@as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(ramp2d_width - 1))) - 1;
                const t = std.math.clamp(@sqrt(u * u + v * v), 0, 1);
                pixels[row * ramp2d_width + col] = .fromColor(interpolate(stops, t).opacity(alpha));
            }
        }
        const tex = try dvui.Texture.fromPixelsPMA(&pixels, ramp2d_width, ramp2d_width, .linear);
        dvui.textureAddToCache(key, tex);
        return tex;
    }

    /// Like `rampTexture2D`, but for focal radial: holds
    /// `interpolate(stops, focalRadialT(u, v, fu, fv))` for `(u,v)` covering
    /// `[-1,1]^2`. `(fu,fv)` (the focal point's own `radialUV`) is constant
    /// for a given draw but varies across gradients, so it joins the cache
    /// key alongside the stops.
    fn radialFocalKey(stops: []const Stop, alpha: f32, fu: f32, fv: f32) dvui.Texture.Cache.Key {
        var hasher = dvui.fnv.init();
        hasher.update("radial2dfocal");
        for (stops) |s| {
            hasher.update(std.mem.asBytes(&s.offset));
            hasher.update(std.mem.asBytes(&s.color));
        }
        hasher.update(std.mem.asBytes(&alpha));
        hasher.update(std.mem.asBytes(&fu));
        hasher.update(std.mem.asBytes(&fv));
        return hasher.final();
    }

    fn rampTextureFocal2D(stops: []const Stop, alpha: f32, fu: f32, fv: f32) (std.mem.Allocator.Error || dvui.Backend.TextureError)!dvui.Texture {
        const key = radialFocalKey(stops, alpha, fu, fv);
        if (dvui.textureGetCached(key)) |cached| return cached;

        var pixels: [ramp2d_width * ramp2d_width]Color.PMA = undefined;
        for (0..ramp2d_width) |row| {
            const v = 2 * (@as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(ramp2d_width - 1))) - 1;
            for (0..ramp2d_width) |col| {
                const u = 2 * (@as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(ramp2d_width - 1))) - 1;
                const t = focalRadialT(u, v, fu, fv);
                pixels[row * ramp2d_width + col] = .fromColor(interpolate(stops, t).opacity(alpha));
            }
        }
        const tex = try dvui.Texture.fromPixelsPMA(&pixels, ramp2d_width, ramp2d_width, .linear);
        dvui.textureAddToCache(key, tex);
        return tex;
    }

    /// Like `rampTexture2D`, but for `scattered`: holds
    /// `scatteredColorAt(stops, u, v)` for `(u,v)` covering `[0,1]^2`
    /// (bounds fractions, same convention as a stop's own `x`/`y` - no
    /// `*2-1` remap needed since `scatteredUV` is already `[0,1]`-based).
    /// Keyed by the whole stop set (position and color), since - unlike the
    /// single-scalar-`t` gradients - there's no separate 1D interpolation to
    /// key on. Note this makes the underlying blend distance-metric
    /// bounds-aspect-relative rather than physical-pixel: a non-square
    /// shape now gets elliptical (not circular) falloff around each stop,
    /// trading that for cacheability (see `scatteredColorAt`).
    fn scatteredKey(stops: []const ScatterStop, alpha: f32) dvui.Texture.Cache.Key {
        var hasher = dvui.fnv.init();
        hasher.update("scattered2d");
        for (stops) |s| {
            hasher.update(std.mem.asBytes(&s.x));
            hasher.update(std.mem.asBytes(&s.y));
            hasher.update(std.mem.asBytes(&s.color));
        }
        hasher.update(std.mem.asBytes(&alpha));
        return hasher.final();
    }

    fn rampTextureScattered2D(stops: []const ScatterStop, alpha: f32) (std.mem.Allocator.Error || dvui.Backend.TextureError)!dvui.Texture {
        const key = scatteredKey(stops, alpha);
        if (dvui.textureGetCached(key)) |cached| return cached;

        var pixels: [ramp2d_width * ramp2d_width]Color.PMA = undefined;
        for (0..ramp2d_width) |row| {
            const v = @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(ramp2d_width - 1));
            for (0..ramp2d_width) |col| {
                const u = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(ramp2d_width - 1));
                const color = scatteredColorAt(stops, u, v) orelse stops[0].color;
                pixels[row * ramp2d_width + col] = .fromColor(color.opacity(alpha));
            }
        }
        const tex = try dvui.Texture.fromPixelsPMA(&pixels, ramp2d_width, ramp2d_width, .linear);
        dvui.textureAddToCache(key, tex);
        return tex;
    }

    /// The `dvui.textureGetCached`/`textureRetain` key `apply` will use for
    /// this gradient's ramp texture, computed without touching the texture
    /// cache. `apply` normally keeps its ramp texture alive by being called
    /// (and so implicitly re-touching the cache) every frame; a caller that
    /// instead caches geometry referencing the texture across frames (e.g.
    /// icon rendering's mesh cache) needs this key to `dvui.textureRetain`/
    /// `textureRelease` it explicitly so it isn't evicted out from under
    /// the cached geometry after one unrendered frame.
    pub fn textureCacheKey(gradient: Gradient, bounds_in: Rect.Physical) dvui.Texture.Cache.Key {
        return switch (gradient) {
            .linear => |g| linearKey(g.stops, g.alpha),
            .radial => |g| blk: {
                const b = g.anchor orelse bounds_in;
                if (g.focal) |f| {
                    const geo = radialGeometry(g, b);
                    const fuv = if (geo) |gm| radialUV(gm, .{ .x = b.x + f.x * b.w, .y = b.y + f.y * b.h }) else [2]f32{ 0, 0 };
                    break :blk radialFocalKey(g.stops, g.alpha, fuv[0], fuv[1]);
                }
                break :blk radialKey(g.stops, g.alpha);
            },
            .scattered => |g| scatteredKey(g.stops, g.alpha),
        };
    }

    /// Post-process pass over already-built triangles.
    ///
    /// Sets each vertex's UV to the gradient's exact analytic (affine)
    /// coordinate and returns a ramp texture holding the (possibly
    /// nonlinear) color function of that coordinate, for the caller to draw
    /// the triangles with. GPU UV interpolation reproduces the affine
    /// coordinate exactly everywhere, which baked-vertex-color Gouraud
    /// interpolation can't do for a nonlinear or multi-stop color function
    /// (see `rampTexture`'s doc comment) - so vertex color is left alone
    /// (aside from being turned into a texture-modulation white, preserving
    /// existing alpha for opacity/antialiasing fade).
    ///
    /// `bounds` should be the shape's bounding box, e.g. `Triangles.bounds`.
    pub fn apply(gradient: Gradient, triangles: *Triangles, bounds: Rect.Physical) (std.mem.Allocator.Error || dvui.Backend.TextureError)!?dvui.Texture {
        switch (gradient) {
            .linear => |g| {
                const tex = try rampTexture(g.stops, g.alpha);
                const b = g.anchor orelse bounds;
                for (triangles.vertexes) |*v| {
                    const t = linearT(g, b, v.pos) orelse 0;
                    v.uv = .{ t, 0.5 };
                    // White, premultiplied by the vertex's existing alpha, so the
                    // ramp texture shows through unmodified while still respecting
                    // opacity/antialiasing fade already baked into that alpha.
                    v.col = .{ .r = v.col.a, .g = v.col.a, .b = v.col.a, .a = v.col.a };
                }
                return tex;
            },
            .radial => |g| {
                // `(nx,ny)` (`radialUV`) is affine in position for both
                // focal and non-focal radial, so both can go straight into
                // the UV and be reproduced exactly by GPU interpolation, no
                // subdivision needed. The nonlinearity (`length()` for
                // non-focal, `focalRadialT`'s quadratic solve for focal)
                // lives in the 2D ramp texture instead.
                const b = g.anchor orelse bounds;
                const geo = radialGeometry(g, b);
                const tex = if (g.focal) |f| blk: {
                    const fuv = if (geo) |gm| radialUV(gm, .{ .x = b.x + f.x * b.w, .y = b.y + f.y * b.h }) else [2]f32{ 0, 0 };
                    break :blk try rampTextureFocal2D(g.stops, g.alpha, fuv[0], fuv[1]);
                } else try rampTexture2D(g.stops, g.alpha);
                for (triangles.vertexes) |*v| {
                    const uv = if (geo) |gm| radialUV(gm, v.pos) else [2]f32{ 0, 0 };
                    v.uv = .{ (uv[0] + 1) / 2, (uv[1] + 1) / 2 };
                    // White, premultiplied by the vertex's existing alpha - see `linear` above.
                    v.col = .{ .r = v.col.a, .g = v.col.a, .b = v.col.a, .a = v.col.a };
                }
                return tex;
            },
            .scattered => |g| {
                const tex = try rampTextureScattered2D(g.stops, g.alpha);
                const b = g.anchor orelse bounds;
                for (triangles.vertexes) |*v| {
                    const uv = scatteredUV(b, v.pos);
                    v.uv = .{ uv[0], uv[1] };
                    v.col = .{ .r = v.col.a, .g = v.col.a, .b = v.col.a, .a = v.col.a };
                }
                return tex;
            },
        }
    }
};

/// Either a flat color or a gradient. Used by `Options.color_fill` and
/// friends so gradients don't need sibling `_gradient` fields.
pub const ColorOrGradient = union(enum) {
    color: Color,
    gradient: Gradient,

    /// A representative flat color: `.color` as-is, or a gradient's own
    /// first stop. Used where a full gradient can't be expressed (e.g.
    /// blending into another flat color for a "grayed out" effect).
    pub fn toColor(self: ColorOrGradient) Color {
        return switch (self) {
            .color => |c| c,
            .gradient => |g| g.firstColor(),
        };
    }

    pub fn opacity(self: ColorOrGradient, mult: f32) ColorOrGradient {
        return switch (self) {
            .color => |c| .{ .color = c.opacity(mult) },
            .gradient => |g| .{ .gradient = g.opacity(mult) },
        };
    }

    pub fn scale(self: ColorOrGradient, s: f32) ColorOrGradient {
        return switch (self) {
            .color => self,
            .gradient => |g| .{ .gradient = g.scale(s) },
        };
    }

    pub fn dupe(self: ColorOrGradient, allocator: std.mem.Allocator) std.mem.Allocator.Error!ColorOrGradient {
        return switch (self) {
            .color => self,
            .gradient => |g| .{ .gradient = try g.dupe(allocator) },
        };
    }

    /// Blends `a` toward `b` by `t` (0-1). If both are flat colors, this is
    /// a normal color lerp. Otherwise it snaps to `a` (t<0.5) or `b`
    /// (t>=0.5) rather than blending —
    /// gradients don't get an automatic hover/press adjustment.
    pub fn lerp(a: ColorOrGradient, b: ColorOrGradient, t: f32) ColorOrGradient {
        if (a == .color and b == .color) return .{ .color = a.color.lerp(b.color, t) };
        return if (t < 0.5) a else b;
    }

    /// Wrap a flat `Color`. Convenience for call sites that only ever pass
    /// a flat color into a `ColorOrGradient` field.
    pub fn fromColor(c: Color) ColorOrGradient {
        return .{ .color = c };
    }

    /// Forwards to `Color.fromHex`, wrapped as a flat color.
    pub fn fromHex(hex_color: []const u8) ColorOrGradient {
        return .{ .color = Color.fromHex(hex_color) };
    }

    /// Splits into the `color`/`gradient` pair that `FillConvexOptions`,
    /// `FillOptions`, and `StrokeOptions` take.
    pub fn split(self: ColorOrGradient) struct { color: Color, gradient: ?Gradient } {
        return switch (self) {
            .color => |c| .{ .color = c, .gradient = null },
            // Raw (no `alpha` applied) -- this feeds the pre-`apply`
            // placeholder vertex color; `apply`/`sample` apply `alpha`.
            .gradient => |g| .{ .color = g.firstColorRaw(), .gradient = g },
        };
    }
    // const aliases (future TODO: should be sync to those in Color, if those change)
    pub const white: ColorOrGradient = .{ .color = Color.white };
    pub const silver: ColorOrGradient = .{ .color = Color.silver };
    pub const gray: ColorOrGradient = .{ .color = Color.gray };
    pub const black: ColorOrGradient = .{ .color = Color.black };
    pub const red: ColorOrGradient = .{ .color = Color.red };
    pub const maroon: ColorOrGradient = .{ .color = Color.maroon };
    pub const yellow: ColorOrGradient = .{ .color = Color.yellow };
    pub const olive: ColorOrGradient = .{ .color = Color.olive };
    pub const lime: ColorOrGradient = .{ .color = Color.lime };
    pub const green: ColorOrGradient = .{ .color = Color.green };
    pub const aqua: ColorOrGradient = .{ .color = Color.aqua };
    pub const teal: ColorOrGradient = .{ .color = Color.teal };
    pub const blue: ColorOrGradient = .{ .color = Color.blue };
    pub const navy: ColorOrGradient = .{ .color = Color.navy };
    pub const fuchsia: ColorOrGradient = .{ .color = Color.fuchsia };
    pub const purple: ColorOrGradient = .{ .color = Color.purple };
    pub const transparent: ColorOrGradient = .{ .color = Color.transparent };
    // Aliases for basic colors that are already defined
    // https://en.wikipedia.org/wiki/Web_colors#Extended_colors
    pub const cyan = aqua;
    pub const magenta = fuchsia;
    pub const dark_cyan = teal;
    pub const dark_magenta = purple;
};

test "fill gradient" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };

    const left_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const right_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try square.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .linear = .{ .stops = &.{ .{ .color = left_color, .offset = 0 }, .{ .color = right_color, .offset = 1 } }, .angle_degrees = 0 } } },
    });
    defer triangles.deinit(std.testing.allocator);

    try std.testing.expect(triangles.texture != null);
    for (triangles.vertexes) |v| {
        if (v.pos.x < 1) {
            try std.testing.expect(v.uv[0] < 0.5);
        } else if (v.pos.x > 99) {
            try std.testing.expect(v.uv[0] > 0.5);
        }
    }
}

test "fill gradient radial" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try square.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .radial = .{ .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } } } } },
        .center = .{ .x = 50, .y = 50 },
    });
    defer triangles.deinit(std.testing.allocator);

    for (triangles.vertexes) |v| {
        const d = @sqrt((v.uv[0] - 0.5) * (v.uv[0] - 0.5) + (v.uv[1] - 0.5) * (v.uv[1] - 0.5));
        if (v.pos.x == 50 and v.pos.y == 50) {
            try std.testing.expect(d < 0.1);
        } else if ((v.pos.x == 0 or v.pos.x == 100) and (v.pos.y == 0 or v.pos.y == 100)) {
            try std.testing.expect(d > 0.4);
        }
    }
}

test "fill gradient radial defaults center to bounding box" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try square.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .radial = .{ .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } } } } },
    });
    defer triangles.deinit(std.testing.allocator);

    var found_center = false;
    for (triangles.vertexes) |v| {
        if (v.pos.x == 50 and v.pos.y == 50) {
            found_center = true;
            const d = @sqrt((v.uv[0] - 0.5) * (v.uv[0] - 0.5) + (v.uv[1] - 0.5) * (v.uv[1] - 0.5));
            try std.testing.expect(d < 0.1);
        }
    }
    try std.testing.expect(found_center);
}

test "fill gradient radial ellipse reaches all edges of a non-square box" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const wide: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 400, .y = 100 },
        .{ .x = 400, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try wide.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .radial = .{ .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } }, .extent = .closest_side } } },
    });
    defer triangles.deinit(std.testing.allocator);

    for (triangles.vertexes) |v| {
        if (v.pos.x < 1 or v.pos.x > 399) {
            const d = @sqrt((v.uv[0] - 0.5) * (v.uv[0] - 0.5) + (v.uv[1] - 0.5) * (v.uv[1] - 0.5));
            try std.testing.expect(d > 0.4);
        }
    }
}

test "fill gradient radial circle shape stays circular on a non-square box" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const wide: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 400, .y = 100 },
        .{ .x = 400, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try wide.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .radial = .{ .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } }, .shape = .{ .circle = .{} }, .extent = .closest_side } } },
        .center = .{ .x = 210, .y = 50 },
    });
    defer triangles.deinit(std.testing.allocator);

    var found = false;
    for (triangles.vertexes) |v| {
        if (v.pos.x == 210 and v.pos.y == 50) {
            found = true;
            const d = @sqrt((v.uv[0] - 0.5) * (v.uv[0] - 0.5) + (v.uv[1] - 0.5) * (v.uv[1] - 0.5));
            try std.testing.expect(d < 0.15);
        }
    }
    try std.testing.expect(found);
}

test "fill gradient radial position moves the gradient center off the box center" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try square.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .radial = .{ .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } }, .position = .{ .x = 0, .y = 0 } } } },
        .center = .{ .x = 0, .y = 0 },
    });
    defer triangles.deinit(std.testing.allocator);

    for (triangles.vertexes) |v| {
        const d = @sqrt((v.uv[0] - 0.5) * (v.uv[0] - 0.5) + (v.uv[1] - 0.5) * (v.uv[1] - 0.5));
        if (v.pos.x == 0 and v.pos.y == 0) {
            try std.testing.expect(d < 0.1);
        } else if (v.pos.x == 100 and v.pos.y == 100) {
            try std.testing.expect(d > 0.4);
        }
    }
}

test "fill gradient radial size gives an explicit pixel radius, ignoring extent" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const big: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 200 },
        .{ .x = 200, .y = 200 },
        .{ .x = 200, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try big.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .radial = .{ .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } }, .shape = .{ .ellipse = .{ .size = .{ .x = 20, .y = 10 } } } } } },
        .center = .{ .x = 100, .y = 100 },
    });
    defer triangles.deinit(std.testing.allocator);

    for (triangles.vertexes) |v| {
        if (v.pos.x == 100 and v.pos.y == 100) {
            const d = @sqrt((v.uv[0] - 0.5) * (v.uv[0] - 0.5) + (v.uv[1] - 0.5) * (v.uv[1] - 0.5));
            try std.testing.expect(d < 0.1);
        } else if (v.pos.x == 0 and v.pos.y == 0) {
            const d = @sqrt((v.uv[0] - 0.5) * (v.uv[0] - 0.5) + (v.uv[1] - 0.5) * (v.uv[1] - 0.5));
            try std.testing.expect(d > 1.0);
        }
    }
}

test "fill gradient radial focal point shifts the 0%-offset point off center" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    const gradient: Gradient = .{ .radial = .{ .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } }, .focal = .{ .x = 0, .y = 0 } } };
    var triangles = try square.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = gradient },
        .center = .{ .x = 0, .y = 0 },
    });
    defer triangles.deinit(std.testing.allocator);

    try std.testing.expect(triangles.texture != null);
    const c = gradient.sample(triangles.bounds, .{ .x = 0, .y = 0 });
    try std.testing.expect(c.r > c.b);
}

test "fill gradient radial rotation tilts an off-center ellipse" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const square: Path = .{ .points = &.{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    } };

    const center_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const edge_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try square.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .radial = .{
            .stops = &.{ .{ .color = center_color, .offset = 0 }, .{ .color = edge_color, .offset = 1 } },
            .shape = .{ .ellipse = .{ .size = .{ .x = 200, .y = 10 }, .rotation_degrees = 90 } },
        } } },
        .center = .{ .x = 50, .y = 50 },
    });
    defer triangles.deinit(std.testing.allocator);

    for (triangles.vertexes) |v| {
        if (v.pos.x == 50 and v.pos.y == 0) {
            try std.testing.expect(v.col.r > v.col.b);
        } else if (v.pos.x == 0 and v.pos.y == 50) {
            try std.testing.expectEqual(edge_color, v.col.toColor());
        }
    }
}

test "fill gradient anchor lets the gradient span a rect outside the shape's own bounds" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const small: Path = .{ .points = &.{
        .{ .x = 190, .y = 0 },
        .{ .x = 190, .y = 20 },
        .{ .x = 200, .y = 20 },
        .{ .x = 200, .y = 0 },
    } };

    const left_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const right_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    var triangles = try small.fillConvexTriangles(std.testing.allocator, .{
        .color = .{ .gradient = .{ .linear = .{
            .stops = &.{ .{ .color = left_color, .offset = 0 }, .{ .color = right_color, .offset = 1 } },
            .angle_degrees = 0,
            .anchor = .{ .x = 0, .y = 0, .w = 200, .h = 20 },
        } } },
        .center = .{ .x = 195, .y = 10 },
    });
    defer triangles.deinit(std.testing.allocator);

    try std.testing.expect(triangles.texture != null);
    for (triangles.vertexes) |v| {
        try std.testing.expect(v.uv[0] > 0.5);
    }
}

test "fill gradient multi-stop" {
    const start: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const mid: Color = .{ .r = 0, .g = 255, .b = 0, .a = 255 };
    const end: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    const gradient: Gradient = .{ .linear = .{
        .angle_degrees = 0,
        .stops = &.{
            .{ .color = start, .offset = 0 },
            .{ .color = mid, .offset = 0.5 },
            .{ .color = end, .offset = 1 },
        },
    } };
    const bounds: Rect.Physical = .{ .x = 0, .y = 0, .w = 100, .h = 10 };

    try std.testing.expect(gradient.sample(bounds, .{ .x = 0, .y = 5 }).r > 200);
    const midc = gradient.sample(bounds, .{ .x = 50, .y = 5 });
    try std.testing.expect(midc.g > midc.r and midc.g > midc.b);
    try std.testing.expect(gradient.sample(bounds, .{ .x = 100, .y = 5 }).b > 200);
}

test "gradient scattered blends by inverse-distance squared, snapping on exact stops" {
    const red: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    const gradient: Gradient = .{ .scattered = .{ .stops = &.{
        .{ .color = red, .x = 0, .y = 0.5 },
        .{ .color = blue, .x = 1, .y = 0.5 },
    } } };
    const bounds: Rect.Physical = .{ .x = 0, .y = 0, .w = 100, .h = 100 };

    try std.testing.expectEqual(red, gradient.sample(bounds, .{ .x = 0, .y = 50 }));
    try std.testing.expectEqual(blue, gradient.sample(bounds, .{ .x = 100, .y = 50 }));

    const midc = gradient.sample(bounds, .{ .x = 50, .y = 50 });
    try std.testing.expect(@abs(@as(i32, midc.r) - midc.b) < 10);

    const nearc = gradient.sample(bounds, .{ .x = 10, .y = 50 });
    try std.testing.expect(nearc.r > nearc.b);
}

test "ColorOrGradient.lerp snaps instead of blending when either side is a gradient" {
    const red: ColorOrGradient = .{ .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } };
    const blue: ColorOrGradient = .{ .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 } };

    const half = ColorOrGradient.lerp(red, blue, 0.5);
    try std.testing.expect(half.color.r > 0 and half.color.b > 0);

    const gradient: ColorOrGradient = .{ .gradient = .{ .linear = .{ .stops = &.{
        .{ .color = .{ .r = 0, .g = 255, .b = 0, .a = 255 }, .offset = 0 },
    } } } };
    try std.testing.expectEqual(red, ColorOrGradient.lerp(red, gradient, 0.25));
    try std.testing.expectEqual(.gradient, std.meta.activeTag(ColorOrGradient.lerp(red, gradient, 0.75)));
}

test "stroke gradient" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    const line: Path = .{ .points = &.{
        .{ .x = 0, .y = 50 },
        .{ .x = 100, .y = 50 },
    } };

    const left_color: Color = .{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const right_color: Color = .{ .r = 0, .g = 0, .b = 255, .a = 255 };

    const lifo = dvui.currentWindow().lifo();
    var triangles = try line.strokeTriangles(lifo, .{
        .thickness = 5,
        .color = .{ .gradient = .{ .linear = .{ .stops = &.{ .{ .color = left_color, .offset = 0 }, .{ .color = right_color, .offset = 1 } }, .angle_degrees = 0 } } },
    });
    defer triangles.deinit(lifo);

    try std.testing.expect(triangles.texture != null);
    var saw_left = false;
    var saw_right = false;
    for (triangles.vertexes) |v| {
        if (v.col.a != 255) continue; // skip aa-fade edge vertexes
        if (v.pos.x < 1) {
            try std.testing.expect(v.uv[0] < 0.5);
            saw_left = true;
        } else if (v.pos.x > 99) {
            try std.testing.expect(v.uv[0] > 0.5);
            saw_right = true;
        }
    }
    try std.testing.expect(saw_left and saw_right);
}

// Run with (from repo root): zig build test -Dtest-filter="DOCIMG gradient css" -Dimage-dir=/tmp/gradient-compare/dvui
test "DOCIMG gradient css comparison" {
    const size: dvui.Size = .{ .w = 300, .h = 200 };
    var t = try dvui.testing.init(.{ .window_size = size });
    defer t.deinit();

    const red: Color = .{ .r = 255, .g = 80, .b = 80, .a = 255 };
    const blue: Color = .{ .r = 80, .g = 120, .b = 255, .a = 255 };
    const yellow: Color = .{ .r = 255, .g = 220, .b = 80, .a = 255 };

    const Sample = struct {
        var gradient: Gradient = undefined;

        fn frame() !dvui.App.Result {
            var box = dvui.box(@src(), .{}, .{
                .expand = .both,
                .background = true,
                .color_fill = .{ .gradient = gradient },
            });
            defer box.deinit();
            return .ok;
        }
    };

    Sample.gradient = .{
        .linear = .{
            .angle_degrees = 0, // css: linear-gradient(90deg, ...)
            .stops = &.{ .{ .color = red, .offset = 0 }, .{ .color = blue, .offset = 1 } },
        },
    };
    try t.saveImage(Sample.frame, null, "linear-basic.png");

    Sample.gradient = .{
        .linear = .{
            .angle_degrees = 45, // css: linear-gradient(135deg, ...)
            .stops = &.{ .{ .color = red, .offset = 0 }, .{ .color = yellow, .offset = 0.5 }, .{ .color = blue, .offset = 1 } },
        },
    };
    try t.saveImage(Sample.frame, null, "linear-diagonal-3stop.png");

    Sample.gradient = .{
        .radial = .{
            .shape = .{ .circle = .{} },
            .extent = .farthest_corner,
            // css: radial-gradient(circle farthest-corner at 50% 50%, ...)
            .stops = &.{ .{ .color = red, .offset = 0 }, .{ .color = blue, .offset = 1 } },
        },
    };
    try t.saveImage(Sample.frame, null, "radial-circle-farthest-corner.png");

    Sample.gradient = .{
        .radial = .{
            .shape = .{ .ellipse = .{} },
            .extent = .closest_side,
            .position = .{ .x = 0.25, .y = 0.25 },
            // css: radial-gradient(ellipse closest-side at 25% 25%, ...)
            .stops = &.{ .{ .color = red, .offset = 0 }, .{ .color = blue, .offset = 1 } },
        },
    };
    try t.saveImage(Sample.frame, null, "radial-ellipse-closest-side-offcenter.png");

    Sample.gradient = .{
        .radial = .{
            .shape = .{ .ellipse = .{} },
            .extent = .farthest_corner,
            .position = .{ .x = 0.7, .y = 0.3 },
            // css: radial-gradient(ellipse farthest-corner at 70% 30%, ...)
            .stops = &.{ .{ .color = red, .offset = 0 }, .{ .color = yellow, .offset = 0.5 }, .{ .color = blue, .offset = 1 } },
        },
    };
    try t.saveImage(Sample.frame, null, "radial-ellipse-farthest-corner-3stop.png");

    Sample.gradient = .{
        .radial = .{
            .shape = .{ .ellipse = .{ .size = .{ .x = 60, .y = 40 } } },
            // css: radial-gradient(60px 40px at 50% 50%, ...)
            .stops = &.{ .{ .color = red, .offset = 0 }, .{ .color = blue, .offset = 1 } },
        },
    };
    try t.saveImage(Sample.frame, null, "radial-ellipse-fixed-size.png");
}

const std = @import("std");
const dvui = @import("dvui.zig");

const math = dvui.math;
const Color = dvui.Color;

const Rect = dvui.Rect;
const Path = dvui.Path;
const Point = dvui.Point;
const Triangles = dvui.Triangles;
