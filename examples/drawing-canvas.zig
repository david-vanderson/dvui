const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");

pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI App Example",
            .window_init_options = .{
                .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = AppFrame,
    .initFn = AppInit,
    .deinitFn = AppDeinit,
};

pub const main = dvui.App.main;
pub const panic = dvui.App.panic;

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var path = dvui.Path.Builder.init(gpa);
var drawings: std.ArrayList([]dvui.Point.Physical) = undefined;

pub fn AppInit(win: *dvui.Window) !void {
    var orig_content_scale: f32 = 1.0;
    orig_content_scale = win.content_scale;
    drawings = try std.ArrayList([]dvui.Point.Physical).initCapacity(gpa, 10);

    if (false) {
        const theme = switch (win.backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        };

        win.themeSet(theme);
    }
}

pub fn AppDeinit() void {
    path.deinit();

    for (drawings.items) |stroke| {
        gpa.free(stroke);
    }

    drawings.deinit(gpa);

    if (gpa_instance.detectLeaks()) {
        @panic("Leaks");
    }
}

pub fn AppFrame() !dvui.App.Result {
    return frame();
}

pub fn findPointCollision(points: []const dvui.Point.Physical, mouse_pos: dvui.Point.Physical, radius: f32) ?usize {
    for (points, 0..) |point, i| {
        const dx = mouse_pos.x - point.x;
        const dy = mouse_pos.y - point.y;
        const distance_squared = dx * dx + dy * dy;
        const radius_squared = radius * radius;

        if (distance_squared <= radius_squared) {
            return i;
        }
    }
    return null;
}

const Tools = enum {
    Pencil,
    Eraser,
    None,
};

var active_tool: Tools = .None;

pub fn frame() !dvui.App.Result {
    // Container
    var hbox = dvui.box(@src(), .{ .dir = .vertical }, .{
        .expand = .both,
    });

    defer hbox.deinit();

    // Canvas area
    {
        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
        defer scroll.deinit();

        const events = dvui.events();
        for (events) |*ev| {
            if (!dvui.eventMatch(ev, .{ .id = scroll.data().id, .r = scroll.data().contentRectScale().r })) {
                continue;
            }

            switch (ev.evt) {
                else => continue,
                .mouse => |ms| {
                    switch (ms.action) {
                        .press => {
                            if (ms.button == .left) {
                                ev.handle(@src(), scroll.data());
                                dvui.captureMouse(scroll.data(), ev.num);
                                if (active_tool == .Pencil) {
                                    path.addPoint(ms.p);
                                }
                            }
                        },
                        .motion => {
                            if (dvui.captured(scroll.data().id)) {
                                ev.handle(@src(), scroll.data());

                                if (active_tool == .Pencil) {
                                    path.addPoint(ms.p);
                                    dvui.refresh(null, @src(), scroll.data().id);
                                }

                                if (active_tool == .Eraser) {
                                    var i: usize = drawings.items.len;
                                    while (i > 0) {
                                        i -= 1;
                                        const drawing = drawings.items[i];
                                        if (findPointCollision(drawing, ms.p, 15.0) != null) {
                                            gpa.free(drawing);
                                            _ = drawings.orderedRemove(i);
                                            dvui.refresh(null, @src(), scroll.data().id);
                                            std.debug.print("removed drawing {}\n", .{i});
                                        }
                                    }
                                }
                            }
                        },
                        .release => {
                            dvui.captureMouse(null, ev.num);
                            if (active_tool == .Pencil) {
                                const copy = try gpa.dupe(dvui.Point.Physical, path.points.items);
                                try drawings.append(gpa, copy);
                                path.points.clearRetainingCapacity();
                            }
                        },

                        else => continue,
                    }
                },
            }
        }

        for (drawings.items) |drawing| {
            dvui.Path.stroke(dvui.Path{ .points = drawing }, .{
                .color = dvui.Color{ .a = 255, .b = 120, .g = 12, .r = 212 },
                .thickness = 12.12,
            });
        }

        dvui.Path.stroke(dvui.Path{ .points = path.points.items }, .{
            .color = dvui.Color{ .a = 255, .b = 120, .g = 12, .r = 212 },
            .thickness = 12.12,
        });
    }

    // dock
    {
        var dock = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .expand = .horizontal,
            .border = dvui.Rect.all(1),
            .corner_radius = .{ .x = 0, .y = 0 },
            .padding = .{ .x = 8, .y = 8 },
            .margin = .{ .x = 0, .y = 0 },
            .background = true,
            .color_fill = dvui.themeGet().color(.control, .fill),
        });
        defer dock.deinit();

        if (dvui.button(@src(), "Pencil", .{}, .{})) {
            active_tool = .Pencil;
            std.debug.print("Pencil selected\n", .{});
        }

        if (dvui.button(@src(), "Eraser", .{}, .{})) {
            active_tool = .Eraser;
            std.debug.print("Eraser selected\n", .{});
        }
    }

    return .ok;
}
