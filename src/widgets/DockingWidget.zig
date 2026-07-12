//! Docking widget: a layout tree of splits and tabbed leaves that panels can
//! be dragged between. See `Layout` for the pure-data tree; the widget itself
//! (rendering, drag-and-drop, floating leaves) is built up incrementally.
pub const Layout = @import("DockingWidget/Layout.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
