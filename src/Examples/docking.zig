//! Docking demo: a small IDE mock (hierarchy/viewport/inspector/console)
//! showing `dvui.dockspace` — drag tabs between panels, split, float, and
//! reset back to the default layout.
//!
//! The "..." button after each tab strip shows `drawHeaderExtra`: dvui draws
//! nothing in that trailing space, so the menu there is entirely this demo's.
//! `panel_background` shows a panel frame is themeable like any other widget —
//! `corners` rounds it, omitting them leaves sharp 90° corners.
const std = @import("std");
const dvui = @import("../dvui.zig");

const DockingWidget = dvui.DockingWidget;
const Layout = DockingWidget.Layout;

var docking_buffer: [8192]u8 = undefined;
var docking_fba = std.heap.FixedBufferAllocator.init(&docking_buffer);

var docking_layout: ?Layout.DockLayout = null;

/// Queued by the header menu, applied after the dockspace walk: `dockspace`
/// treats the layout tree as immutable while it is open.
var pending: ?struct { panel: Layout.PanelId, action: enum { float, close } } = null;

fn buildDefaultLayout(allocator: std.mem.Allocator) Layout.DockLayout {
    var l = Layout.DockLayout.initSingleLeaf(allocator, "viewport") catch unreachable;
    l.splitLeaf(l.root, .left, "hierarchy") catch unreachable;
    const viewport_leaf = l.findPanel("viewport").?;
    l.splitLeaf(viewport_leaf, .right, "inspector") catch unreachable;
    const inspector_leaf = l.findPanel("inspector").?;
    l.splitLeaf(inspector_leaf, .bottom, "console") catch unreachable;
    return l;
}

fn panelInfo(id: Layout.PanelId) DockingWidget.PanelInfo {
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

pub fn docking() void {
    if (docking_layout == null) docking_layout = buildDefaultLayout(docking_fba.allocator());

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        if (dvui.button(@src(), "Reset Layout", .{}, .{})) {
            docking_fba.reset();
            docking_layout = buildDefaultLayout(docking_fba.allocator());
            pending = null;
        }
    }

    {
        var dock = dvui.dockspace(@src(), .{
            .layout = &docking_layout.?,
            .panelInfo = panelInfo,
            .drawHeaderExtra = drawHeaderExtra,
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
        const l = &docking_layout.?;
        switch (p.action) {
            .float => l.floatPanel(p.panel, .{ .x = 60, .y = 60, .w = 260, .h = 180 }) catch {},
            .close => l.removePanel(p.panel),
        }
    }
}

test {
    std.testing.refAllDecls(@This());
}
