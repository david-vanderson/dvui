//! Standalone IDE-mock demonstrating `dvui.dockspace`: drag tabs between
//! panels, split, float, and reset back to the default layout.
//!
//! The "..." button after each tab strip shows `drawHeaderExtra` — dvui draws
//! nothing in that trailing space, so the menu there is entirely this example's.
//!
//! Persisting a layout is the app's job: `DockLayout.snapshot` hands back a
//! plain `Snapshot` value and `DockLayout.fromSnapshot` rebuilds one, so any
//! serializer (JSON, ZON, msgpack, ...) works. The widget itself picks none.
const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

const Layout = dvui.DockingWidget.Layout;

/// Queued by the header menu, applied after the dockspace walk: `dockspace`
/// treats the layout tree as immutable while it is open.
var pending: ?struct { panel: Layout.PanelId, action: enum { float, close } } = null;

fn buildDefaultLayout(allocator: std.mem.Allocator) !Layout.DockLayout {
    var l = try Layout.DockLayout.initSingleLeaf(allocator, "viewport");
    try l.splitLeaf(l.root, .left, "hierarchy");
    const viewport_leaf = l.findPanel("viewport").?;
    try l.splitLeaf(viewport_leaf, .right, "inspector");
    const inspector_leaf = l.findPanel("inspector").?;
    try l.splitLeaf(inspector_leaf, .bottom, "console");
    return l;
}

fn panelInfo(id: Layout.PanelId) dvui.DockingWidget.PanelInfo {
    return .{ .title = id, .closable = true };
}

/// Keeps each leaf's otherwise-identical menu widgets distinct.
fn panelIdExtra(id: Layout.PanelId) usize {
    return @truncate(std.hash.Wyhash.hash(0, id));
}

fn drawHeaderExtra(id: Layout.PanelId) void {
    var m = dvui.menu(@src(), .horizontal, .{ .id_extra = panelIdExtra(id), .gravity_x = 1.0, .gravity_y = 0.5 });
    defer m.deinit();

    if (dvui.menuItemLabel(@src(), "...", .{ .submenu = true }, .{ .id_extra = panelIdExtra(id) })) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();

        if (dvui.menuItemLabel(@src(), "Float Panel", .{}, .{ .expand = .horizontal }) != null) {
            fw.close();
            pending = .{ .panel = id, .action = .float };
        }
        if (dvui.menuItemLabel(@src(), "Close Panel", .{}, .{ .expand = .horizontal }) != null) {
            fw.close();
            pending = .{ .panel = id, .action = .close };
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var layout = try buildDefaultLayout(gpa);
    defer layout.deinit();

    var backend = try SDLBackend.initWindow(.{
        .io = init.io,
        .environ_map = init.environ_map,
        .size = .{ .w = 900.0, .h = 600.0 },
        .min_size = .{ .w = 400.0, .h = 300.0 },
        .vsync = true,
        .title = "DVUI Docking Standalone Example",
    });
    defer backend.deinit();

    var window_open = true;
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{
        .theme = switch (backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        },
        .open_flag = &window_open,
    });
    defer win.deinit();

    var interrupted = false;
    while (window_open) {
        const nstime = win.beginWait(interrupted);
        try win.begin(nstime);
        try backend.addAllEvents(&win);

        {
            var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
            defer hbox.deinit();
            if (dvui.button(@src(), "Reset Layout", .{}, .{})) {
                layout.deinit();
                layout = buildDefaultLayout(gpa) catch @panic("OOM building default layout");
                pending = null;
            }
        }

        {
            var dock = dvui.dockspace(@src(), .{
                .layout = &layout,
                .panelInfo = panelInfo,
                .drawHeaderExtra = drawHeaderExtra,
                // A panel's frame is themeable like any other widget: `corners`
                // rounds it, omitting them leaves sharp 90° corners.
                .panel_background = .{
                    .background = true,
                    .border = dvui.Rect.all(1),
                    .corners = dvui.CornerRect.all(5),
                    .margin = dvui.Rect.all(2),
                },
            }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "{s} panel content", .{p.id}, .{});
            }
        }

        if (pending) |p| {
            pending = null;
            switch (p.action) {
                .float => layout.floatPanel(p.panel, .{ .x = 60, .y = 60, .w = 260, .h = 180 }) catch {},
                .close => layout.removePanel(p.panel),
            }
        }

        const end_micros = try win.end(.{});
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);
    }
}
