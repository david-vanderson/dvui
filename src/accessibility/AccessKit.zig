//! An `accessibility.Instance` that adds accessibility support to widgets via the AccessKit library

pub const Node = struct {
    pub const Id = dvui.Id;
    comptime {
        // NOTE: AccessKit id's are `u64`s, if dvui.Id ever changes backing integer from `u64` this will need to be changed!
        std.debug.assert(@sizeOf(Id) == @sizeOf(u64)); 
    }

    ak: *c.accesskit_node,

    pub fn init(ak: *c.accesskit_node) Node {
        return .{ .ak = ak };
    }

    pub fn deinit(node: Node) void {
        c.accesskit_node_free(node.ak); 
    }

    pub fn create(role: a11y.Role) error{OutOfNodes}!Node {
        return .init(c.accesskit_node_new(fromDvuiRole(role)) orelse return error.OutOfNodes);
    }

    pub fn addChild(node: Node, id: dvui.Id) void {
        c.accesskit_node_push_child(node.ak, @intFromEnum(id)); 
    }

    pub fn setLabelId(node: Node, id: dvui.Id) void {
        c.accesskit_node_push_labelled_by(node.ak, @intFromEnum(id));
    }

    pub fn setBounds(node: Node, bounds: dvui.Rect.Physical) void {
        c.accesskit_node_set_bounds(node.ak, .{ .x0 = bounds.x, .y0 = bounds.y, .x1 = bounds.bottomRight().x, .y1 = bounds.bottomRight().y });
    }

    pub fn setLabel(node: Node, label: [:0]const u8) void {
        c.accesskit_node_set_label(node.ak, label.ptr);
    }

    pub fn setInvalid(node: Node, invalid: a11y.Invalid) void {
        c.accesskit_node_set_invalid(node.ak, fromDvuiInvalid(invalid)); 
    }

    pub fn clearInvalid(node: Node) void {
        c.accesskit_node_clear_invalid(node.ak);
    }

    pub fn setModal(node: Node) void {
        c.accesskit_node_set_modal(node.ak);
    }

    pub fn clearModal(node: Node) void {
        c.accesskit_node_clear_modal(node.ak);
    }

    pub fn setReadOnly(node: Node) void {
        c.accesskit_node_set_read_only(node.ak);
    }

    pub fn setSelected(node: Node, selected: bool) void {
        c.accesskit_node_set_selected(node.ak, selected);
    }

    pub fn setRole(node: Node, role: a11y.Role) void {
        c.accesskit_node_set_role(node.ak, fromDvuiRole(role)); 
    }

    pub fn setLive(node: Node, live: a11y.Live) void {
        c.accesskit_node_set_live(node.ak, fromDvuiLive(live));
    }

    pub fn setOrientation(node: Node, orientation: a11y.Orientation) void {
        c.accesskit_node_set_orientation(node.ak, fromDvuiOrientation(orientation));
    }

    pub fn setSortDirection(node: Node, direction: a11y.SortDirection) void {
        c.accesskit_node_set_sort_direction(node.ak, fromDvuiSortDirection(direction));
    }

    pub fn value(node: Node) ?[*:0]u8 {
        return c.accesskit_node_value(node.ak);
    }

    pub fn freeValue(_: Node, str: [*:0]u8) void {
        c.accesskit_string_free(@ptrCast(str));
    }

    pub fn clearValue(node: Node) void {
        c.accesskit_node_clear_value(node.ak);
    }

    pub fn setValue(node: Node, str: [:0]const u8) void {
        c.accesskit_node_set_value(node.ak, str.ptr); 
    }

    pub fn setMinNumericValue(node: Node, min: f64) void {
        c.accesskit_node_set_min_numeric_value(node.ak, min);
    }

    pub fn setMaxNumericValue(node: Node, max: f64) void {
        c.accesskit_node_set_max_numeric_value(node.ak, max);
    }

    pub fn setNumericValue(node: Node, num: f64) void {
        c.accesskit_node_set_numeric_value(node.ak, num);
    }

    pub fn setNumericValueStep(node: Node, step: f64) void {
        c.accesskit_node_set_numeric_value_step(node.ak, step);
    }

    pub fn setNumericValueJump(node: Node, jump: f64) void {
        c.accesskit_node_set_numeric_value_jump(node.ak, jump);
    }

    pub fn setToggled(node: Node, toggled: a11y.Toggled) void {
        c.accesskit_node_set_toggled(node.ak, fromDvuiToggled(toggled)); 
    }

    pub fn setRowCount(node: Node, rows: usize) void {
        c.accesskit_node_set_row_count(node.ak, rows);
    }

    pub fn setColumnCount(node: Node, columns: usize) void {
        c.accesskit_node_set_column_count(node.ak, columns);
    }

    pub fn setRowIndex(node: Node, row: usize) void {
        c.accesskit_node_set_row_index(node.ak, row);
    }

    pub fn setColumnIndex(node: Node, column: usize) void {
        c.accesskit_node_set_column_index(node.ak, column);
    }

    pub fn addAction(node: Node, action: a11y.Action) void {
        c.accesskit_node_add_action(node.ak, fromDvuiAction(action));
    }
};

const Tree = struct {
    pub const Update = struct {
        ak: *c.accesskit_tree_update,

        pub fn init(ak: *c.accesskit_tree_update) Update {
            return .{ .ak = ak };
        }

        pub fn createCapacityFocus(capacity: usize, focus: dvui.Id) error{OutOfUpdates}!Update {
            return .init(c.accesskit_tree_update_with_capacity_and_focus(capacity, @intFromEnum(focus)) orelse return error.OutOfUpdates);
        }

        pub fn setTree(update: Update, tree: Tree) void {
            c.accesskit_tree_update_set_tree(update.ak, tree.ak); 
        }

        pub fn pushNode(update: Update, id: dvui.Id, node: Node) void {
            c.accesskit_tree_update_push_node(update.ak, @intFromEnum(id), node.ak);
        }
    };

    ak: *c.accesskit_tree,


    pub fn init(ak: *c.accesskit_tree) Tree {
        return .{ .ak = ak };
    }

    pub fn create(root: dvui.Id) error{OutOfTrees}!Tree {
        return .init(c.accesskit_tree_new(@intFromEnum(root)) orelse return error.OutOfTrees);
    }
};


const AdapterKind = enum { windows, unix, macos };
const Adapter = switch (builtin.target.os.tag) {
    .windows => struct {
        pub const kind: AdapterKind = .windows;
        ak: *c.accesskit_windows_subclassing_adapter,

        pub fn init(state: *State, window: *anyopaque) WindowsAdapter {
            return .{ .ak = c.accesskit_windows_subclassing_adapter_new(@intFromPtr(window), initialTreeUpdate, state, doAction, state) orelse @panic("null") };
        }

        pub fn deinit(adapter: WindowsAdapter) void {
            c.accesskit_windows_subclassing_adapter_free(adapter.ak);
        }

        pub fn end(adapter: WindowsAdapter, state: *State) void {
            const queued_events = c.accesskit_windows_subclassing_adapter_update_if_active(adapter.ak, frameTreeUpdate, state);

            if (queued_events) |events| {
                c.accesskit_windows_queued_events_raise(events);
            }
        }

        pub inline fn focusGained(_: WindowsAdapter) void {}
        pub inline fn focusLost(_: WindowsAdapter) void {}
        pub inline fn setBounds(_: WindowsAdapter, _: dvui.Rect.Physical, _: dvui.Rect.Physical) void {}

        const WindowsAdapter = @This();
    },
    // XXX: This is *nix, could maybe apply to BSDs also?
    .linux => struct {
        pub const kind: AdapterKind = .unix;
        ak: *c.accesskit_unix_adapter,

        pub fn init(state: *State, _: *anyopaque) UnixAdapter {
            return .{ .ak = c.accesskit_unix_adapter_new(initialTreeUpdate, state, doAction, state, deactivateAccessibility, state) orelse @panic("null") };
        }

        pub fn deinit(adapter: UnixAdapter) void {
            c.accesskit_unix_adapter_free(adapter.ak);
        }

        pub fn end(adapter: UnixAdapter, state: *State) void {
            c.accesskit_unix_adapter_update_if_active(adapter.ak, frameTreeUpdate, state);
        }

        pub fn focusGained(adapter: UnixAdapter) void {
            c.accesskit_unix_adapter_update_window_focus_state(adapter.ak, true);
        }

        pub fn focusLost(adapter: UnixAdapter) void {
            c.accesskit_unix_adapter_update_window_focus_state(adapter.ak, false);
        }

        pub fn setBounds(adapter: UnixAdapter, outer: dvui.Rect.Physical, inner: dvui.Rect.Physical) void {
            c.accesskit_unix_adapter_set_root_window_bounds(
                adapter.ak,
                .{ .x0 = outer.x, .y0 = outer.y, .x1 = outer.bottomRight().x, .y1 = outer.bottomRight().y },
                .{ .x0 = inner.x, .y0 = inner.y, .x1 = inner.bottomRight().x, .y1 = inner.bottomRight().y },
            ); 
        }

        const UnixAdapter = @This();
    },
    .macos => struct {
        pub const kind: AdapterKind = .macos;
        ak: *c.accesskit_macos_subclassing_adapter,

        pub fn init(state: *State, window: *anyopaque) MacosAdapter {
            // TODO: This results in a null pointer unwrap. I assume the window class is wrong?
            //ak.accesskit_macos_add_focus_forwarder_to_window_class("SDLWindow");
            return .{ .ak = c.accesskit_macos_subclassing_adapter_for_window(window, initialTreeUpdate, state, doAction, state) orelse @panic("null") };
        }

        pub fn deinit(adapter: MacosAdapter) void {
            c.accesskit_macos_subclassing_adapter_free(adapter.ak);
        }

        pub fn end(adapter: MacosAdapter, state: *State) void {
            const queued_events = c.accesskit_macos_subclassing_adapter_update_if_active(adapter.ak, frameTreeUpdate, state);

            if (queued_events) |events| {
                c.accesskit_macos_queued_events_raise(events);
            }
        }

        pub fn focusGained(adapter: MacosAdapter) void {
            const events = c.accesskit_macos_subclassing_adapter_update_view_focus_state(adapter.ak, true);

            if (events) |evts| {
                c.accesskit_macos_queued_events_raise(evts);
            }
        }

        pub fn focusLost(adapter: MacosAdapter) void {
            const events = c.accesskit_macos_subclassing_adapter_update_view_focus_state(adapter.ak, false);

            if (events) |evts| {
                c.accesskit_macos_queued_events_raise(evts);
            }
        }

        pub inline fn setBounds(_: MacosAdapter, _: dvui.Rect.Physical, _: dvui.Rect.Physical) void {}

        const MacosAdapter = @This();
    },
    else => |t| @compileError("AccessKit not supported on '" ++ @tagName(t) ++ "'"),
};

const State = struct {
    const Status = enum { off, starting, on };

    gpa: std.mem.Allocator,
    adapter: Adapter,
    root_id: dvui.Id = .zero,
    // The node id for the widget which last had focus this frame.
    focused_id: dvui.Id = .zero,
    // Note: Access to `nodes` must be protected by `mutex`.
    // Safe for read-only access from gui-thread, without mutex.
    nodes: std.AutoArrayHashMapUnmanaged(dvui.Id, Node) = .empty,
    // Note: Any access to `action_requests` must be protected by `mutex`.
    action_requests: std.ArrayList(c.accesskit_action_request) = .empty,

    // The last seen node with `role = .label`
    prev_label_id: dvui.Id = .zero,

    // `node_to_label` contains the node that will be labeled with the next
    // created label node.
    node_waiting_label: bool = false,
    node_to_label: dvui.Id = .zero,

    status: Status = .off,
    mutex: std.Thread.Mutex = .{},

    pub fn deinit(state: *State) void {
        state.adapter.deinit();
        state.action_requests.clearAndFree(state.gpa);
        state.nodes.clearAndFree(state.gpa);
        state.* = undefined;
    }
};

state: *State,

const debug_node_tree = false;

pub fn init(gpa: std.mem.Allocator, root: dvui.Id, window: ?*anyopaque) !AccessKit {
    const state = try gpa.create(State);

    state.* = .{
        .root_id = root,
        .gpa = gpa,
        .adapter = .init(state, window orelse @panic("Cannot initialize AccessKit without a native Handle!")),
    };

    log.info("initialized successfully", .{});
    return .{ .state = state };
}

pub fn deinit(ak: *AccessKit, gpa: std.mem.Allocator) void {
    const state = ak.state;
    // No mutex lock and unlock, we're freeing.
    // Calling this and having other thread using this means we have other problems to solve...
    state.deinit();
    gpa.destroy(state);
}

pub fn needsNode(ak: *AccessKit, ctx: a11y.NodeContext) bool {
    const state = ak.state;
    return needs: switch (state.status) {
        .off => false,
        .starting => if(ctx.root) {
            state.status = .on;
            continue :needs .on;
        } else false,
        .on => (ctx.visible or ctx.focused) and ctx.role != .none,
    };
}

pub fn createNode(ak: *AccessKit, gpa: std.mem.Allocator, full: a11y.NodeContext.Full) !Node {
    std.debug.assert(full.ctx.visible or full.ctx.focused);
    std.debug.assert(full.ctx.role != .none);

    const state = ak.state;

    state.mutex.lock();
    defer state.mutex.unlock();

    if(debug_node_tree)
        log.debug("Creating AccessKit Node for {x} with role '{t}'", .{ full.ctx.id, full.ctx.role });

    const node: Node = try .create(full.ctx.role);
    errdefer node.deinit();

    node.setBounds(full.bounds); 

    if (!full.ctx.root) {
        full.parent.?.addChild(full.ctx.id);
        if (full.ctx.focused) state.focused_id = full.ctx.id;
    }

    switch (full.ctx.label) {
        .none => {},
        .by_id => |id| {
            node.setLabelId(id);
        },
        .for_id => |id| blk: {
            const for_node = state.nodes.get(id) orelse {
                log.debug("label.for_id {x} is not a valid AccessKit Node", .{id});
                break :blk;
            };
            for_node.setLabelId(full.ctx.id);
        },
        .label_widget => |direction| switch (direction) {
            .next => {
                state.node_to_label = full.ctx.id;
                state.node_waiting_label = true;
            },
            .prev => {
                std.debug.assert(state.nodes.contains(state.prev_label_id));
                node.setLabelId(state.prev_label_id);
            },
        },
        .text => |txt| {
            const str = gpa.dupeZ(u8, txt) catch "";
            defer gpa.free(str);
            node.setLabel(str);
        },
    }

    if (full.ctx.role == .label) {
        if (state.node_waiting_label) {
            if (state.node_to_label == .zero) {
                state.node_waiting_label = false;
            } else {
                // If the labelled node is no longer visible, it will not be found.
                if (state.nodes.get(state.node_to_label)) |for_node| {
                    for_node.setLabelId(full.ctx.id);
                    state.node_waiting_label = false;
                    state.node_to_label = .zero;
                }
            }
        }

        state.prev_label_id = full.ctx.id;
    }

    try state.nodes.putNoClobber(gpa, full.ctx.id, node);
    return node;
}

pub fn focusGained(ak: *AccessKit) void {
    ak.state.adapter.focusGained();
}

pub fn focusLost(ak: *AccessKit) void {
    ak.state.adapter.focusLost();
}

pub fn setBounds(ak: AccessKit, outer: dvui.Rect.Physical, inner: dvui.Rect.Physical) void {
    ak.state.adapter.setBounds(outer, inner);
}

pub fn name(_: AccessKit) []const u8 {
    return "accesskit";
}

/// Convert any actions during the frame into events to be processed next frame
/// Note: Assumes `mutex` is already held.
fn processActions(ak: *AccessKit, window: *dvui.Window) void {
    const state = ak.state;
    for (state.action_requests.items) |request| {
        switch (request.action) {
            fromDvuiAction(.click) => {
                const node = state.nodes.get(@enumFromInt(request.target)) orelse {
                    log.debug("Action {d} received for a target {x} without a node.", .{ request.action, request.target });
                    return;
                };
                const bounds = blk: {
                    const bounds_maybe = c.accesskit_node_bounds(node.ak);
                    if (bounds_maybe.has_value) break :blk bounds_maybe.value;
                    log.debug("Action {d} received for a target {x} without node bounds.", .{ request.action, request.target });
                    return;
                };
                const click_point: dvui.Point.Physical = .{ .x = @floatCast((bounds.x0 + bounds.x1) / 2), .y = @floatCast((bounds.y0 + bounds.y1) / 2) };

                _ = window.addEventMouseMotion(.{ .pt = click_point, .target_id = @enumFromInt(request.target) }) catch |err| logEventAddError(@src(), err);

                // sending a left press also sends a focus event
                _ = window.addEventPointer(.{ .button = .left, .action = .press, .target_id = @enumFromInt(request.target) }) catch |err| logEventAddError(@src(), err);
                _ = window.addEventPointer(.{ .button = .left, .action = .release, .target_id = @enumFromInt(request.target) }) catch |err| logEventAddError(@src(), err);
            },
            fromDvuiAction(.set_value) => {
                const node = state.nodes.get(@enumFromInt(request.target)) orelse {
                    log.debug("Action {d} received for a target {x} without a node.", .{ request.action, request.target });
                    return;
                };
                if (request.data.has_value) {
                    const bounds = _: {
                        const bounds_maybe = c.accesskit_node_bounds(node.ak);
                        if (bounds_maybe.has_value) break :_ bounds_maybe.value;
                        log.debug("Action {d} received for a target {x} without node bounds.", .{ request.action, request.target });
                        return;
                    };
                    const mid_point: dvui.Point.Physical = .{ .x = @floatCast((bounds.x0 + bounds.x1) / 2), .y = @floatCast((bounds.y0 + bounds.y1) / 2) };
                    _ = window.addEventFocus(.{ .pt = mid_point, .target_id = @enumFromInt(request.target) }) catch |err| logEventAddError(@src(), err);

                    const text_value: []const u8 = value: {
                        switch (request.data.value.tag) {
                            ActionData.value => break :value std.mem.span(request.data.value.unnamed_0.unnamed_1.value),
                            ActionData.numeric_value => {
                                var writer: std.io.Writer.Allocating = .init(window.arena());
                                writer.writer.print("{d}", .{request.data.value.unnamed_0.unnamed_2.numeric_value}) catch break :value "";
                                break :value writer.toOwnedSlice() catch break :value "";
                            },
                            else => {
                                break :value "";
                            },
                        }
                    };

                    _ = window.addEventText(.{ .text = text_value, .target_id = @enumFromInt(request.target), .replace = true }) catch |err| logEventAddError(@src(), err);
                }
            },
            else => {},
        }
    }
    if (state.action_requests.items.len > 0) {
        state.action_requests.clearAndFree(window.gpa);
        dvui.refresh(window, @src(), null);
    }
}

fn logEventAddError(src: std.builtin.SourceLocation, err: anyerror) void {
    dvui.logError(src, err, "Accesskit: Event for action has not been added", .{});
}

/// Must be called at the end of each frame.
/// Pushes any nodes created during the frame to the accesskit tree.
pub fn end(ak: *AccessKit, gpa: std.mem.Allocator, window: *dvui.Window) void {
    // The gpa is asserted to be the same as the `init` one.
    const state = ak.state;

    state.mutex.lock();
    defer state.mutex.unlock();

    if(Adapter.kind == .unix) state.adapter.focusGained();

    if (state.status != .on) return;

    // Take any actions from this frame and create events for them.
    // Created events will not be processed until the start of the next frame.
    ak.processActions(window);
    state.adapter.end(state);
    state.nodes.clearAndFree(gpa);
    state.focused_id = .zero;
}

/// Pushes all the nodes created during the current frame to AccessKit
/// Called once per frame (if accessibility is initialized)
/// Note: This callback is only during the dynamic extent of pushUpdates on the same thread. TODO: verify this.
pub fn frameTreeUpdate(userdata: ?*anyopaque) callconv(.c) ?*c.accesskit_tree_update {
    const state: *State = @ptrCast(@alignCast(userdata.?));

    // XXX: Shouldn't this handle it gracefully? panicking is too much
    const tree = Tree.create(state.root_id) catch @panic("Out of AccessKit trees");
    if (state.focused_id == .zero) state.focused_id = state.root_id;
    const update = Tree.Update.createCapacityFocus(state.nodes.count(), state.focused_id) catch @panic("Out of AccessKit tree updates");

    if(debug_node_tree)
        log.debug("AccessKit Tree Update with focused {x}", .{ @intFromEnum(state.focused_id) });

    update.setTree(tree);
    var itr = state.nodes.iterator();
    while (itr.next()) |item| {
        update.pushNode(item.key_ptr.*, item.value_ptr.*);
    }
    return update.ak;
}

/// Creates the initial tree update when accessibility information is first requested by the OS
/// The initial tree only contains basic window details. These are updated when frameTreeUpdate runs.
/// Note: This callback can occur on a non-gui thread.
pub fn initialTreeUpdate(instance: ?*anyopaque) callconv(.c) ?*c.accesskit_tree_update {
    const state: *State = @ptrCast(@alignCast(instance.?));
 
    state.mutex.lock();
    defer state.mutex.unlock();

    // XXX: Shouldn't this handle it gracefully? panicking is too much
    const root = Node.create(.window) catch @panic("Out of AccessKit nodes"); 
    const tree = Tree.create(.zero) catch @panic("Out of AccessKit trees");
    const update = Tree.Update.createCapacityFocus(1, .zero) catch @panic("Out of AccessKit tree updates");
    update.setTree(tree);
    update.pushNode(.zero, root);
    state.status = .starting;

    if(debug_node_tree)
        log.debug("AccessKit Initial Tree Update", .{});

    // XXX: accessibility shouldn't depend on the entire window state...

    // Refresh so that the full tree is sent next frame.
    // XXX: dvui.refresh(window, @src(), null);
    return update.ak;
}

/// Processing incoming actions, mouse clicks etc.
/// Any action requests which occur are processed at the end of the frame, during pushUpdates()
/// Note: This callback can occur on a non-gui thread.
fn doAction(request: [*c]c.accesskit_action_request, userdata: ?*anyopaque) callconv(.c) void {
    defer c.accesskit_action_request_free(request);

    const state: *State = @ptrCast(@alignCast(userdata.?));

    state.mutex.lock();
    defer state.mutex.unlock();

    state.action_requests.append(state.gpa, request.?.*) catch |err| {
        dvui.logError(@src(), err, "AccessKit: Unable to add action request", .{});
    };
    // XXX: dvui.refresh(window, @src(), null);
}

fn deactivateAccessibility(userdata: ?*anyopaque) callconv(.c) void {
    const state: *AccessKit = @ptrCast(@alignCast(userdata));

    state.mutex.lock();
    defer state.mutex.unlock();

    state.status = .off;
}

fn fromDvuiRole(role: a11y.Role) u8 {
    return switch (role) {
        .none => 255,
        .unknown => c.ACCESSKIT_ROLE_UNKNOWN,
        .text_run => c.ACCESSKIT_ROLE_TEXT_RUN,
        .cell => c.ACCESSKIT_ROLE_CELL,
        .label => c.ACCESSKIT_ROLE_LABEL,
        .image => c.ACCESSKIT_ROLE_IMAGE,
        .link => c.ACCESSKIT_ROLE_LINK,
        .row => c.ACCESSKIT_ROLE_ROW,
        .list_item => c.ACCESSKIT_ROLE_LIST_ITEM,
        .list_marker => c.ACCESSKIT_ROLE_LIST_MARKER,
        .tree_item => c.ACCESSKIT_ROLE_TREE_ITEM,
        .list_box_option => c.ACCESSKIT_ROLE_LIST_BOX_OPTION,
        .menu_item => c.ACCESSKIT_ROLE_MENU_ITEM,
        .menu_list_option => c.ACCESSKIT_ROLE_MENU_LIST_OPTION,
        .paragraph => c.ACCESSKIT_ROLE_PARAGRAPH,
        .generic_container => c.ACCESSKIT_ROLE_GENERIC_CONTAINER,
        .check_box => c.ACCESSKIT_ROLE_CHECK_BOX,
        .radio_button => c.ACCESSKIT_ROLE_RADIO_BUTTON,
        .text_input => c.ACCESSKIT_ROLE_TEXT_INPUT,
        .button => c.ACCESSKIT_ROLE_BUTTON,
        .default_button => c.ACCESSKIT_ROLE_DEFAULT_BUTTON,
        .pane => c.ACCESSKIT_ROLE_PANE,
        .row_header => c.ACCESSKIT_ROLE_ROW_HEADER,
        .column_header => c.ACCESSKIT_ROLE_COLUMN_HEADER,
        .row_group => c.ACCESSKIT_ROLE_ROW_GROUP,
        .list => c.ACCESSKIT_ROLE_LIST,
        .table => c.ACCESSKIT_ROLE_TABLE,
        .layout_table_cell => c.ACCESSKIT_ROLE_LAYOUT_TABLE_CELL,
        .layout_table_row => c.ACCESSKIT_ROLE_LAYOUT_TABLE_ROW,
        .layout_table => c.ACCESSKIT_ROLE_LAYOUT_TABLE,
        .ak_switch => c.ACCESSKIT_ROLE_SWITCH,
        .menu => c.ACCESSKIT_ROLE_MENU,
        .multiline_text_input => c.ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT,
        .search_input => c.ACCESSKIT_ROLE_SEARCH_INPUT,
        .date_input => c.ACCESSKIT_ROLE_DATE_INPUT,
        .date_time_input => c.ACCESSKIT_ROLE_DATE_TIME_INPUT,
        .week_input => c.ACCESSKIT_ROLE_WEEK_INPUT,
        .month_input => c.ACCESSKIT_ROLE_MONTH_INPUT,
        .time_input => c.ACCESSKIT_ROLE_TIME_INPUT,
        .email_input => c.ACCESSKIT_ROLE_EMAIL_INPUT,
        .number_input => c.ACCESSKIT_ROLE_NUMBER_INPUT,
        .password_input => c.ACCESSKIT_ROLE_PASSWORD_INPUT,
        .phone_number_input => c.ACCESSKIT_ROLE_PHONE_NUMBER_INPUT,
        .url_input => c.ACCESSKIT_ROLE_URL_INPUT,
        .abbr => c.ACCESSKIT_ROLE_ABBR,
        .alert => c.ACCESSKIT_ROLE_ALERT,
        .alert_dialog => c.ACCESSKIT_ROLE_ALERT_DIALOG,
        .application => c.ACCESSKIT_ROLE_APPLICATION,
        .article => c.ACCESSKIT_ROLE_ARTICLE,
        .audio => c.ACCESSKIT_ROLE_AUDIO,
        .banner => c.ACCESSKIT_ROLE_BANNER,
        .blockquote => c.ACCESSKIT_ROLE_BLOCKQUOTE,
        .canvas => c.ACCESSKIT_ROLE_CANVAS,
        .caption => c.ACCESSKIT_ROLE_CAPTION,
        .caret => c.ACCESSKIT_ROLE_CARET,
        .code => c.ACCESSKIT_ROLE_CODE,
        .color_well => c.ACCESSKIT_ROLE_COLOR_WELL,
        .combo_box => c.ACCESSKIT_ROLE_COMBO_BOX,
        .editable_combo_box => c.ACCESSKIT_ROLE_EDITABLE_COMBO_BOX,
        .complementary => c.ACCESSKIT_ROLE_COMPLEMENTARY,
        .comment => c.ACCESSKIT_ROLE_COMMENT,
        .content_deletion => c.ACCESSKIT_ROLE_CONTENT_DELETION,
        .content_insertion => c.ACCESSKIT_ROLE_CONTENT_INSERTION,
        .content_info => c.ACCESSKIT_ROLE_CONTENT_INFO,
        .definition => c.ACCESSKIT_ROLE_DEFINITION,
        .description_list => c.ACCESSKIT_ROLE_DESCRIPTION_LIST,
        .description_list_detail => c.ACCESSKIT_ROLE_DESCRIPTION_LIST_DETAIL,
        .description_list_term => c.ACCESSKIT_ROLE_DESCRIPTION_LIST_TERM,
        .details => c.ACCESSKIT_ROLE_DETAILS,
        .dialog => c.ACCESSKIT_ROLE_DIALOG,
        .directory => c.ACCESSKIT_ROLE_DIRECTORY,
        .disclosure_triangle => c.ACCESSKIT_ROLE_DISCLOSURE_TRIANGLE,
        .document => c.ACCESSKIT_ROLE_DOCUMENT,
        .embedded_object => c.ACCESSKIT_ROLE_EMBEDDED_OBJECT,
        .emphasis => c.ACCESSKIT_ROLE_EMPHASIS,
        .feed => c.ACCESSKIT_ROLE_FEED,
        .figure_caption => c.ACCESSKIT_ROLE_FIGURE_CAPTION,
        .figure => c.ACCESSKIT_ROLE_FIGURE,
        .footer => c.ACCESSKIT_ROLE_FOOTER,
        .footer_as_non_landmark => c.ACCESSKIT_ROLE_FOOTER_AS_NON_LANDMARK,
        .form => c.ACCESSKIT_ROLE_FORM,
        .grid => c.ACCESSKIT_ROLE_GRID,
        .group => c.ACCESSKIT_ROLE_GROUP,
        .header => c.ACCESSKIT_ROLE_HEADER,
        .header_as_non_landmark => c.ACCESSKIT_ROLE_HEADER_AS_NON_LANDMARK,
        .heading => c.ACCESSKIT_ROLE_HEADING,
        .iframe => c.ACCESSKIT_ROLE_IFRAME,
        .iframe_presentational => c.ACCESSKIT_ROLE_IFRAME_PRESENTATIONAL,
        .ime_candidate => c.ACCESSKIT_ROLE_IME_CANDIDATE,
        .keyboard => c.ACCESSKIT_ROLE_KEYBOARD,
        .legend => c.ACCESSKIT_ROLE_LEGEND,
        .line_break => c.ACCESSKIT_ROLE_LINE_BREAK,
        .list_box => c.ACCESSKIT_ROLE_LIST_BOX,
        .log => c.ACCESSKIT_ROLE_LOG,
        .main => c.ACCESSKIT_ROLE_MAIN,
        .mark => c.ACCESSKIT_ROLE_MARK,
        .marquee => c.ACCESSKIT_ROLE_MARQUEE,
        .math => c.ACCESSKIT_ROLE_MATH,
        .menu_bar => c.ACCESSKIT_ROLE_MENU_BAR,
        .menu_item_check_box => c.ACCESSKIT_ROLE_MENU_ITEM_CHECK_BOX,
        .menu_item_radio => c.ACCESSKIT_ROLE_MENU_ITEM_RADIO,
        .menu_list_popup => c.ACCESSKIT_ROLE_MENU_LIST_POPUP,
        .meter => c.ACCESSKIT_ROLE_METER,
        .navigation => c.ACCESSKIT_ROLE_NAVIGATION,
        .note => c.ACCESSKIT_ROLE_NOTE,
        .plugin_object => c.ACCESSKIT_ROLE_PLUGIN_OBJECT,
        .portal => c.ACCESSKIT_ROLE_PORTAL,
        .pre => c.ACCESSKIT_ROLE_PRE,
        .progress_indicator => c.ACCESSKIT_ROLE_PROGRESS_INDICATOR,
        .radio_group => c.ACCESSKIT_ROLE_RADIO_GROUP,
        .region => c.ACCESSKIT_ROLE_REGION,
        .root_web_area => c.ACCESSKIT_ROLE_ROOT_WEB_AREA,
        .ruby => c.ACCESSKIT_ROLE_RUBY,
        .ruby_annotation => c.ACCESSKIT_ROLE_RUBY_ANNOTATION,
        .scroll_bar => c.ACCESSKIT_ROLE_SCROLL_BAR,
        .scroll_view => c.ACCESSKIT_ROLE_SCROLL_VIEW,
        .search => c.ACCESSKIT_ROLE_SEARCH,
        .section => c.ACCESSKIT_ROLE_SECTION,
        .slider => c.ACCESSKIT_ROLE_SLIDER,
        .spin_button => c.ACCESSKIT_ROLE_SPIN_BUTTON,
        .splitter => c.ACCESSKIT_ROLE_SPLITTER,
        .status => c.ACCESSKIT_ROLE_STATUS,
        .strong => c.ACCESSKIT_ROLE_STRONG,
        .suggestion => c.ACCESSKIT_ROLE_SUGGESTION,
        .svg_root => c.ACCESSKIT_ROLE_SVG_ROOT,
        .tab => c.ACCESSKIT_ROLE_TAB,
        .tab_list => c.ACCESSKIT_ROLE_TAB_LIST,
        .tab_panel => c.ACCESSKIT_ROLE_TAB_PANEL,
        .term => c.ACCESSKIT_ROLE_TERM,
        .time => c.ACCESSKIT_ROLE_TIME,
        .timer => c.ACCESSKIT_ROLE_TIMER,
        .title_bar => c.ACCESSKIT_ROLE_TITLE_BAR,
        .toolbar => c.ACCESSKIT_ROLE_TOOLBAR,
        .tooltip => c.ACCESSKIT_ROLE_TOOLTIP,
        .tree => c.ACCESSKIT_ROLE_TREE,
        .tree_grid => c.ACCESSKIT_ROLE_TREE_GRID,
        .video => c.ACCESSKIT_ROLE_VIDEO,
        .web_view => c.ACCESSKIT_ROLE_WEB_VIEW,
        .window => c.ACCESSKIT_ROLE_WINDOW,
        .pdf_actionable_highlight => c.ACCESSKIT_ROLE_PDF_ACTIONABLE_HIGHLIGHT,
        .pdf_root => c.ACCESSKIT_ROLE_PDF_ROOT,
        .graphics_document => c.ACCESSKIT_ROLE_GRAPHICS_DOCUMENT,
        .graphics_object => c.ACCESSKIT_ROLE_GRAPHICS_OBJECT,
        .graphics_symbol => c.ACCESSKIT_ROLE_GRAPHICS_SYMBOL,
        .doc_abstract => c.ACCESSKIT_ROLE_DOC_ABSTRACT,
        .doc_acknowledgements => c.ACCESSKIT_ROLE_DOC_ACKNOWLEDGEMENTS,
        .doc_afterword => c.ACCESSKIT_ROLE_DOC_AFTERWORD,
        .doc_appendix => c.ACCESSKIT_ROLE_DOC_APPENDIX,
        .doc_back_link => c.ACCESSKIT_ROLE_DOC_BACK_LINK,
        .doc_biblio_entry => c.ACCESSKIT_ROLE_DOC_BIBLIO_ENTRY,
        .doc_bibliography => c.ACCESSKIT_ROLE_DOC_BIBLIOGRAPHY,
        .doc_biblio_ref => c.ACCESSKIT_ROLE_DOC_BIBLIO_REF,
        .doc_chapter => c.ACCESSKIT_ROLE_DOC_CHAPTER,
        .doc_colophon => c.ACCESSKIT_ROLE_DOC_COLOPHON,
        .doc_conclusion => c.ACCESSKIT_ROLE_DOC_CONCLUSION,
        .doc_cover => c.ACCESSKIT_ROLE_DOC_COVER,
        .doc_credit => c.ACCESSKIT_ROLE_DOC_CREDIT,
        .doc_credits => c.ACCESSKIT_ROLE_DOC_CREDITS,
        .doc_dedication => c.ACCESSKIT_ROLE_DOC_DEDICATION,
        .doc_endnote => c.ACCESSKIT_ROLE_DOC_ENDNOTE,
        .doc_endnotes => c.ACCESSKIT_ROLE_DOC_ENDNOTES,
        .doc_epigraph => c.ACCESSKIT_ROLE_DOC_EPIGRAPH,
        .doc_epilogue => c.ACCESSKIT_ROLE_DOC_EPILOGUE,
        .doc_errata => c.ACCESSKIT_ROLE_DOC_ERRATA,
        .doc_example => c.ACCESSKIT_ROLE_DOC_EXAMPLE,
        .doc_footnote => c.ACCESSKIT_ROLE_DOC_FOOTNOTE,
        .doc_foreword => c.ACCESSKIT_ROLE_DOC_FOREWORD,
        .doc_glossary => c.ACCESSKIT_ROLE_DOC_GLOSSARY,
        .doc_gloss_ref => c.ACCESSKIT_ROLE_DOC_GLOSS_REF,
        .doc_index => c.ACCESSKIT_ROLE_DOC_INDEX,
        .doc_introduction => c.ACCESSKIT_ROLE_DOC_INTRODUCTION,
        .doc_note_ref => c.ACCESSKIT_ROLE_DOC_NOTE_REF,
        .doc_notice => c.ACCESSKIT_ROLE_DOC_NOTICE,
        .doc_page_break => c.ACCESSKIT_ROLE_DOC_PAGE_BREAK,
        .doc_page_footer => c.ACCESSKIT_ROLE_DOC_PAGE_FOOTER,
        .doc_page_header => c.ACCESSKIT_ROLE_DOC_PAGE_HEADER,
        .doc_page_list => c.ACCESSKIT_ROLE_DOC_PAGE_LIST,
        .doc_part => c.ACCESSKIT_ROLE_DOC_PART,
        .doc_preface => c.ACCESSKIT_ROLE_DOC_PREFACE,
        .doc_prologue => c.ACCESSKIT_ROLE_DOC_PROLOGUE,
        .doc_pullquote => c.ACCESSKIT_ROLE_DOC_PULLQUOTE,
        .doc_qna => c.ACCESSKIT_ROLE_DOC_QNA,
        .doc_subtitle => c.ACCESSKIT_ROLE_DOC_SUBTITLE,
        .doc_tip => c.ACCESSKIT_ROLE_DOC_TIP,
        .doc_toc => c.ACCESSKIT_ROLE_DOC_TOC,
        .list_grid => c.ACCESSKIT_ROLE_LIST_GRID,
        .terminal => c.ACCESSKIT_ROLE_TERMINAL,
    };
}

// All types below are generated from accesskit.h
// See accesskit_gen.zig in the tools directory for more details

// Enum Structs
fn fromDvuiAction(action: a11y.Action) u8 {
    return switch (action) {
        .click => c.ACCESSKIT_ACTION_CLICK,
        .focus => c.ACCESSKIT_ACTION_FOCUS,
        .blur => c.ACCESSKIT_ACTION_BLUR,
        .collapse => c.ACCESSKIT_ACTION_COLLAPSE,
        .expand => c.ACCESSKIT_ACTION_EXPAND,
        .custom_action => c.ACCESSKIT_ACTION_CUSTOM_ACTION,
        .decrement => c.ACCESSKIT_ACTION_DECREMENT,
        .increment => c.ACCESSKIT_ACTION_INCREMENT,
        .hide_tooltip => c.ACCESSKIT_ACTION_HIDE_TOOLTIP,
        .show_tooltip => c.ACCESSKIT_ACTION_SHOW_TOOLTIP,
        .replace_selected_text => c.ACCESSKIT_ACTION_REPLACE_SELECTED_TEXT,
        .scroll_down => c.ACCESSKIT_ACTION_SCROLL_DOWN,
        .scroll_left => c.ACCESSKIT_ACTION_SCROLL_LEFT,
        .scroll_right => c.ACCESSKIT_ACTION_SCROLL_RIGHT,
        .scroll_up => c.ACCESSKIT_ACTION_SCROLL_UP,
        .scroll_into_view => c.ACCESSKIT_ACTION_SCROLL_INTO_VIEW,
        .scroll_to_point => c.ACCESSKIT_ACTION_SCROLL_TO_POINT,
        .set_scroll_offset => c.ACCESSKIT_ACTION_SET_SCROLL_OFFSET,
        .set_text_selection => c.ACCESSKIT_ACTION_SET_TEXT_SELECTION,
        .set_sequential_focus_navigation_starting_point => c.ACCESSKIT_ACTION_SET_SEQUENTIAL_FOCUS_NAVIGATION_STARTING_POINT,
        .set_value => c.ACCESSKIT_ACTION_SET_VALUE,
        .show_context_menu => c.ACCESSKIT_ACTION_SHOW_CONTEXT_MENU,
    };
}

pub const AriaCurrent = struct {
    pub const ak_false = c.ACCESSKIT_ARIA_CURRENT_FALSE;
    pub const ak_true = c.ACCESSKIT_ARIA_CURRENT_TRUE;
    pub const page = c.ACCESSKIT_ARIA_CURRENT_PAGE;
    pub const step = c.ACCESSKIT_ARIA_CURRENT_STEP;
    pub const location = c.ACCESSKIT_ARIA_CURRENT_LOCATION;
    pub const date = c.ACCESSKIT_ARIA_CURRENT_DATE;
    pub const time = c.ACCESSKIT_ARIA_CURRENT_TIME;
};

pub const AutoComplete = struct {
    pub const ak_inline = c.ACCESSKIT_AUTO_COMPLETE_INLINE;
    pub const list = c.ACCESSKIT_AUTO_COMPLETE_LIST;
    pub const both = c.ACCESSKIT_AUTO_COMPLETE_BOTH;
};

pub const HasPopup = struct {
    pub const menu = c.ACCESSKIT_HAS_POPUP_MENU;
    pub const listbox = c.ACCESSKIT_HAS_POPUP_LISTBOX;
    pub const tree = c.ACCESSKIT_HAS_POPUP_TREE;
    pub const grid = c.ACCESSKIT_HAS_POPUP_GRID;
    pub const dialog = c.ACCESSKIT_HAS_POPUP_DIALOG;
};

fn fromDvuiInvalid(inv: a11y.Invalid) u8 {
    return switch (inv) {
        .true => c.ACCESSKIT_INVALID_TRUE,
        .grammar => c.ACCESSKIT_INVALID_GRAMMAR,
        .spelling => c.ACCESSKIT_INVALID_SPELLING,
    };
}

pub const ListStyle = struct {
    pub const circle = c.ACCESSKIT_LIST_STYLE_CIRCLE;
    pub const disc = c.ACCESSKIT_LIST_STYLE_DISC;
    pub const image = c.ACCESSKIT_LIST_STYLE_IMAGE;
    pub const numeric = c.ACCESSKIT_LIST_STYLE_NUMERIC;
    pub const square = c.ACCESSKIT_LIST_STYLE_SQUARE;
    pub const other = c.ACCESSKIT_LIST_STYLE_OTHER;
};

fn fromDvuiLive(live: a11y.Live) u8 {
    return switch (live) {
        .off => c.ACCESSKIT_LIVE_OFF,
        .polite => c.ACCESSKIT_LIVE_POLITE,
        .assertive => c.ACCESSKIT_LIVE_ASSERTIVE,
    };
}

fn fromDvuiOrientation(orientation: a11y.Orientation) u8 {
    return switch (orientation) {
        .horizontal => c.ACCESSKIT_ORIENTATION_HORIZONTAL,
        .vertical => c.ACCESSKIT_ORIENTATION_VERTICAL,
    };
}

pub const ScrollHint = struct {
    pub const top_left = c.ACCESSKIT_SCROLL_HINT_TOP_LEFT;
    pub const bottom_right = c.ACCESSKIT_SCROLL_HINT_BOTTOM_RIGHT;
    pub const top_edge = c.ACCESSKIT_SCROLL_HINT_TOP_EDGE;
    pub const bottom_edge = c.ACCESSKIT_SCROLL_HINT_BOTTOM_EDGE;
    pub const left_edge = c.ACCESSKIT_SCROLL_HINT_LEFT_EDGE;
    pub const right_edge = c.ACCESSKIT_SCROLL_HINT_RIGHT_EDGE;
};

pub const ScrollUnit = struct {
    pub const item = c.ACCESSKIT_SCROLL_UNIT_ITEM;
    pub const page = c.ACCESSKIT_SCROLL_UNIT_PAGE;
};

fn fromDvuiSortDirection(dir: a11y.SortDirection) u8 {
    return switch (dir) {
        .ascending => c.ACCESSKIT_SORT_DIRECTION_ASCENDING,
        .descending => c.ACCESSKIT_SORT_DIRECTION_DESCENDING,
        .other => c.ACCESSKIT_SORT_DIRECTION_OTHER,
    };
}

pub const TextAlign = struct {
    pub const left = c.ACCESSKIT_TEXT_ALIGN_LEFT;
    pub const right = c.ACCESSKIT_TEXT_ALIGN_RIGHT;
    pub const center = c.ACCESSKIT_TEXT_ALIGN_CENTER;
    pub const justify = c.ACCESSKIT_TEXT_ALIGN_JUSTIFY;
};

pub const TextDecoration = struct {
    pub const solid = c.ACCESSKIT_TEXT_DECORATION_SOLID;
    pub const dotted = c.ACCESSKIT_TEXT_DECORATION_DOTTED;
    pub const dashed = c.ACCESSKIT_TEXT_DECORATION_DASHED;
    pub const double = c.ACCESSKIT_TEXT_DECORATION_DOUBLE;
    pub const wavy = c.ACCESSKIT_TEXT_DECORATION_WAVY;
};

pub const TextDirection = struct {
    pub const left_to_right = c.ACCESSKIT_TEXT_DIRECTION_LEFT_TO_RIGHT;
    pub const right_to_left = c.ACCESSKIT_TEXT_DIRECTION_RIGHT_TO_LEFT;
    pub const top_to_bottom = c.ACCESSKIT_TEXT_DIRECTION_TOP_TO_BOTTOM;
    pub const bottom_to_top = c.ACCESSKIT_TEXT_DIRECTION_BOTTOM_TO_TOP;
};

fn fromDvuiToggled(toggled: a11y.Toggled) u8 {
    return switch (toggled) {
        .false => c.ACCESSKIT_TOGGLED_FALSE,
        .true => c.ACCESSKIT_TOGGLED_TRUE,
        .mixed => c.ACCESSKIT_TOGGLED_MIXED,
    };
}

pub const VerticalOffset = struct {
    pub const subscript = c.ACCESSKIT_VERTICAL_OFFSET_SUBSCRIPT;
    pub const superscript = c.ACCESSKIT_VERTICAL_OFFSET_SUPERSCRIPT;
};

pub const ActionData = struct {
    pub const custom_action = c.ACCESSKIT_ACTION_DATA_CUSTOM_ACTION;
    pub const value = c.ACCESSKIT_ACTION_DATA_VALUE;
    pub const numeric_value = c.ACCESSKIT_ACTION_DATA_NUMERIC_VALUE;
    pub const scroll_unit = c.ACCESSKIT_ACTION_DATA_SCROLL_UNIT;
    pub const scroll_hint = c.ACCESSKIT_ACTION_DATA_SCROLL_HINT;
    pub const scroll_to_point = c.ACCESSKIT_ACTION_DATA_SCROLL_TO_POINT;
    pub const set_scroll_offset = c.ACCESSKIT_ACTION_DATA_SET_SCROLL_OFFSET;
    pub const set_text_selection = c.ACCESSKIT_ACTION_DATA_SET_TEXT_SELECTION;
};

const AccessKit = @This();

const log = std.log.scoped(.AccessKit);

const builtin = @import("builtin");
const std = @import("std");
const dvui = @import("dvui");

const a11y = dvui.accessibility;

const c = @cImport({
    // Workaround for a linker symbol clash on aarch64-windows
    @cDefine("__mingw_current_teb", "___mingw_current_teb");
    @cInclude("accesskit.h");
});

// When linking to accesskit for non-msvc builds, the _fltuser symbol is
// undefined. Zig only defines this symbol for abi = .mscv and abi = .none,
// which makes gnu and musl builds break.  Until we can build and link the
// accesskit c library with zig, we need this work-around as both the msvc and
// mingw builds of accesskit reference this symbol.
comptime {
    if (builtin.os.tag == .windows and builtin.cpu.arch.isX86()) {
        @export(&_fltused, .{ .name = "_fltused", .linkage = .weak });
    }
}

var _fltused: c_int = 1;
