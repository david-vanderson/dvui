//! Represents an `accessibility.Instance` that does nothing, unlike `AccessKit`.
//! Gives a brief overview of the needed APIs for an `accessibility` backend.
//! If an API is not here, it is NOT public and shouldn't be relied upon!

pub const Node = enum {
    // NOTE: Don't add any field, empty enums are zero-sized and `?enum{}` WILL be optimized as its always null.

    pub inline fn setBounds(_: Node, _: dvui.Rect.Physical) void {
        unreachable;
    }
    pub inline fn setLabel(_: Node, _: [:0]const u8) void {
        unreachable;
    }
    pub fn setInvalid(_: Node, _: a11y.Invalid) void {
        unreachable;
    }
    pub fn clearInvalid(_: Node) void {
        unreachable;
    }
    pub inline fn setModal(_: Node) void {
        unreachable;
    }
    pub inline fn clearModal(_: Node) void {
        unreachable;
    }
    pub inline fn setReadOnly(_: Node) void {
        unreachable;
    }
    pub inline fn setSelected(_: Node, _: bool) void {
        unreachable;
    }
    pub inline fn setRole(_: Node, _: a11y.Role) void {
        unreachable;
    }
    pub inline fn setLive(_: Node, _: a11y.Live) void {
        unreachable;
    }
    pub inline fn setOrientation(_: Node, _: a11y.Orientation) void {
        unreachable;
    }
    pub fn setSortDirection(_: Node, _: a11y.SortDirection) void {
        unreachable;
    }
    pub inline fn value(_: Node) ?[*:0]const u8 {
        unreachable;
    }
    pub inline fn clearValue(_: Node) void {
        unreachable;
    }
    pub inline fn setValue(_: Node, _: [:0]const u8) void {
        unreachable;
    }
    pub inline fn setMinNumericValue(_: Node, _: f64) void {
        unreachable;
    }
    pub inline fn setMaxNumericValue(_: Node, _: f64) void {
        unreachable;
    }
    pub inline fn setNumericValue(_: Node, _: f64) void {
        unreachable;
    }
    pub inline fn setNumericValueStep(_: Node, _: f64) void {
        unreachable;
    }
    pub inline fn setNumericValueJump(_: Node, _: f64) void {
        unreachable;
    }
    pub inline fn setToggled(_: Node, _: a11y.Toggled) void {
        unreachable;
    }
    pub inline fn setRowCount(_: Node, _: usize) void {
        unreachable;
    }
    pub inline fn setColumnCount(_: Node, _: usize) void {
        unreachable;
    }
    pub inline fn setRowIndex(_: Node, _: usize) void {
        unreachable;
    }
    pub inline fn setColumnIndex(_: Node, _: usize) void {
        unreachable;
    }
    pub inline fn addAction(_: Node, _: a11y.Action) void {
        unreachable;
    }
};

pub inline fn init(_: std.mem.Allocator, _: dvui.Id) error{}!Null {
    return .{};
}

pub inline fn deinit(_: Null, _: std.mem.Allocator) void {}

/// Checks whether a full context and node should be made.
/// If `false`, `Node.none` is used instead of creating a new node.
pub inline fn needsNode(_: Null, _: a11y.NodeContext) bool {
    return false;
}

/// Asserts that `needsNode` returned `true`
pub inline fn createNode(_: Null, _: std.mem.Allocator, _: a11y.NodeContext.Full) a11y.NodeCreationError!Node {
    unreachable;
}

/// The window this instance controls has gained focus.
pub inline fn focusGained(_: Null) void {}

/// The window this instance controls has lost focus.
pub inline fn focusLost(_: Null) void {}

/// The window this instance controls has changed bounds (minimization, maximization, resized, etc...).
pub inline fn setBounds(_: Null, outer: dvui.Rect.Physical, inner: dvui.Rect.Physical) void {
    _ = outer;
    _ = inner;
}

/// Must be called at the end of each frame.
/// Updates nodes created during the frame.
pub inline fn end(_: Null, _: std.mem.Allocator, _: *dvui.Window) void {}

pub inline fn name(_: Null) []const u8 {
    return "null";
}

const Null = @This();

const std = @import("std");
const dvui = @import("dvui");

const a11y = dvui.accessibility;
