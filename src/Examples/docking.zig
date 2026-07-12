//! Docking demo: a small IDE mock (hierarchy/viewport/inspector/console)
//! showing `dvui.dockspace` — drag tabs between panels, split, float, and
//! reset back to the default layout.
const std = @import("std");
const dvui = @import("../dvui.zig");

const DockingWidget = dvui.DockingWidget;
const Layout = DockingWidget.Layout;

var docking_buffer: [8192]u8 = undefined;
var docking_fba = std.heap.FixedBufferAllocator.init(&docking_buffer);

var docking_layout: ?Layout.DockLayout = null;

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

pub fn docking() void {
    if (docking_layout == null) docking_layout = buildDefaultLayout(docking_fba.allocator());

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        if (dvui.button(@src(), "Reset Layout", .{}, .{})) {
            docking_fba.reset();
            docking_layout = buildDefaultLayout(docking_fba.allocator());
        }
    }

    var dock = dvui.dockspace(@src(), .{ .layout = &docking_layout.?, .panelInfo = panelInfo }, .{ .expand = .both });
    defer dock.deinit();
    while (dock.panel()) |p| {
        defer p.end();
        dvui.label(@src(), "{s} panel content", .{p.id}, .{});
    }
}

test {
    std.testing.refAllDecls(@This());
}
