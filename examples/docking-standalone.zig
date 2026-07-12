//! Standalone IDE-mock demonstrating `dvui.dockspace` with full layout
//! persistence: the layout is loaded from `docking-example-layout.json` (next
//! to the executable's cwd) on startup and saved back on quit, showing
//! reviewers the complete save/load story `DockLayout.writeJson`/`parseJson`
//! enable.
const std = @import("std");
const dvui = @import("dvui");
const SDLBackend = @import("sdl-backend");

comptime {
    std.debug.assert(@hasDecl(SDLBackend, "SDLBackend"));
}

const Layout = dvui.DockingWidget.Layout;

const layout_file = "docking-example-layout.json";

fn buildDefaultLayout(allocator: std.mem.Allocator) !Layout.DockLayout {
    var l = try Layout.DockLayout.initSingleLeaf(allocator, "viewport");
    try l.splitLeaf(l.root, .left, "hierarchy");
    const viewport_leaf = l.findPanel("viewport").?;
    try l.splitLeaf(viewport_leaf, .right, "inspector");
    const inspector_leaf = l.findPanel("inspector").?;
    try l.splitLeaf(inspector_leaf, .bottom, "console");
    return l;
}

fn loadLayout(allocator: std.mem.Allocator, io: std.Io) Layout.DockLayout {
    const contents = std.Io.Dir.cwd().readFileAlloc(io, layout_file, allocator, .limited(1024 * 1024)) catch |err| {
        std.log.info("docking-standalone: no saved layout ({t}), starting from default", .{err});
        return buildDefaultLayout(allocator) catch @panic("OOM building default layout");
    };
    defer allocator.free(contents);

    return Layout.DockLayout.parseJson(allocator, contents) catch |err| {
        std.log.warn("docking-standalone: {s} failed to parse ({t}), starting from default", .{ layout_file, err });
        return buildDefaultLayout(allocator) catch @panic("OOM building default layout");
    };
}

fn saveLayout(layout: *const Layout.DockLayout, gpa: std.mem.Allocator, io: std.Io) void {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    layout.writeJson(&out.writer) catch |err| {
        std.log.warn("docking-standalone: failed to serialize layout: {t}", .{err});
        return;
    };
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = layout_file, .data = out.written() }) catch |err| {
        std.log.warn("docking-standalone: failed to write {s}: {t}", .{ layout_file, err });
    };
}

fn panelInfo(id: Layout.PanelId) dvui.DockingWidget.PanelInfo {
    return .{ .title = id, .closable = true };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var layout = loadLayout(gpa, init.io);
    defer {
        saveLayout(&layout, gpa, init.io);
        layout.deinit();
    }

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
            }
            if (dvui.button(@src(), "Save Now", .{}, .{})) {
                saveLayout(&layout, gpa, init.io);
            }
        }

        {
            var dock = dvui.dockspace(@src(), .{ .layout = &layout, .panelInfo = panelInfo }, .{ .expand = .both });
            defer dock.deinit();
            while (dock.panel()) |p| {
                defer p.end();
                dvui.label(@src(), "{s} panel content", .{p.id}, .{});
            }
            if (dock.changed) saveLayout(&layout, gpa, init.io);
        }

        const end_micros = try win.end(.{});
        const wait_event_micros = win.waitTime(end_micros);
        interrupted = try backend.waitEventTimeout(wait_event_micros);
    }
}
