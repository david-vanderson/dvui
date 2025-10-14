//! Adds accessibility support to widgets via the AccessKit library
const builtin = @import("builtin");
pub const c = @cImport({
    if (dvui.accesskit_enabled) {
        @cInclude("accesskit.h");
    }
});

// When linking to accesskit for non-msvc builds, the _fltuser symbol is undefined. Zig only defines this symbol
// for abi = .mscv and abi = .none, which makes gnu and musl builds break.
// Until we can build and link the accesskit c library with zig, we need this work-around as
// both the msvc and mingw builds of accesskit reference this symbol.
comptime {
    if (builtin.os.tag == .windows and builtin.cpu.arch.isX86() and dvui.accesskit_enabled) {
        @export(&_fltused, .{ .name = "_fltused", .linkage = .weak });
    }
}
var _fltused: c_int = 1;

pub const AccessKit = @This();
const std = @import("std");
const dvui = @import("dvui.zig");

adapter: ?AdapterType() = null,
// The ak_node id for the widget which last had focus this frame.
focused_id: usize = 0,
// Note: Any access to `nodes` must be protected by `mutex`.
nodes: std.AutoArrayHashMapUnmanaged(dvui.Id, *Node) = .empty,
// Note: Any access to `action_requests` must be protected by `mutex`.
action_requests: std.ArrayList(ActionRequest) = .empty,
status: enum {
    off,
    starting,
    on,
} = .off,
mutex: std.Thread.Mutex = .{},

fn AdapterType() type {
    if (dvui.accesskit_enabled and builtin.os.tag == .windows) {
        return *c.accesskit_windows_subclassing_adapter;
    } else if (dvui.accesskit_enabled and builtin.os.tag.isDarwin()) {
        return *c.accesskit_macos_subclassing_adapter;
    } else {
        return void;
    }
}

/// Perform SDL3-specific initialization
pub fn initialize(self: *AccessKit) void {
    if (dvui.backend.kind != .sdl3) @compileError("AccessKit currently only implemented for SDL3 backend");

    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));
    const SDLBackend = dvui.backend;

    if (builtin.os.tag == .windows) {
        const properties: SDLBackend.c.SDL_PropertiesID = SDLBackend.c.SDL_GetWindowProperties(window.backend.instance().window);
        const hwnd = SDLBackend.c.SDL_GetPointerProperty(
            properties,
            SDLBackend.c.SDL_PROP_WINDOW_WIN32_HWND_POINTER,
            null,
        ) orelse @panic("No HWND");

        self.adapter = c.accesskit_windows_subclassing_adapter_new(
            @intFromPtr(hwnd),
            initialTreeUpdate,
            self,
            doAction,
            self,
        ) orelse @panic("null");
    } else if (builtin.os.tag.isDarwin()) {
        const properties: SDLBackend.c.SDL_PropertiesID = SDLBackend.c.SDL_GetWindowProperties(window.backend.instance().window);
        const hwnd = SDLBackend.c.SDL_GetPointerProperty(
            properties,
            SDLBackend.c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,
            null,
        ) orelse @panic("No HWND");

        // TODO: This results in a null pointer unwrap. I assume the window class is wrong?
        //ak.accesskit_macos_add_focus_forwarder_to_window_class("SDLWindow");
        self.adapter = c.accesskit_macos_subclassing_adapter_for_window(@ptrCast(hwnd), initialTreeUpdate, self, doAction, self) orelse @panic("null");
    }
}

pub const nodeCreate = if (dvui.accesskit_enabled) nodeCreateReal else nodeCreateFake;

inline fn nodeCreateFake(_: *AccessKit, _: *dvui.WidgetData, _: Role) ?*Node {
    return null;
}

/// Create a new Node for AccessKit
/// Returns null if no accessibility information is required for this widget.
pub fn nodeCreateReal(self: *AccessKit, wd: *dvui.WidgetData, role: Role) ?*Node {
    if (self.adapter == null) {
        self.initialize();
    }

    if (!wd.visible()) return null;
    if (wd.options.role == .none) return null;

    const is_root = (wd.id == wd.parent.data().id);
    const focused_current_id: dvui.Id = dvui.focusedWidgetId() orelse dvui.focusedSubwindowId();

    {
        self.mutex.lock();
        defer self.mutex.unlock();

        switch (self.status) {
            .off => return null,
            .starting => {
                if (is_root) {
                    self.status = .on;
                } else {
                    return null;
                }
            },
            .on => {},
        }
    }

    //std.debug.print("Creating Node for {x} with role {?t} at {s}:{d}\n", .{ wd.id, wd.options.role, wd.src.file, wd.src.line });

    const ak_node = nodeNew(role.asU8()) orelse return null;
    wd.ak_node = ak_node;
    const border_rect = dvui.clipGet().intersect(wd.borderRectScale().r);
    nodeSetBounds(ak_node, .{ .x0 = border_rect.x, .y0 = border_rect.y, .x1 = border_rect.bottomRight().x, .y1 = border_rect.bottomRight().y });

    if (!is_root) {
        const parent_node: *Node, const parent_id: dvui.Id = nodeParent(wd);
        nodePushChild(parent_node, wd.id.asU64());
        if (wd.id == focused_current_id) {
            self.focused_id = (if (wd.id == focused_current_id) wd.id else parent_id).asU64();
        }
    }

    if (wd.options.label) |label| {
        switch (label) {
            .by => |id| {
                nodePushLabelledBy(ak_node, id.asU64());
            },
            .text => |txt| {
                const str = dvui.currentWindow().arena().dupeZ(u8, txt) catch "";
                defer dvui.currentWindow().arena().free(str);
                nodeSetLabel(ak_node, str);
            },
        }
    }

    std.debug.assert(!self.nodes.contains(wd.id));
    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));
    self.nodes.put(window.gpa, wd.id, ak_node) catch @panic("TODO");

    return ak_node;
}

pub inline fn nodeLabelFor(label_id: dvui.Id, target_id: dvui.Id) void {
    if (!dvui.accesskit_enabled) return;

    if (dvui.currentWindow().accesskit.nodes.get(target_id)) |node| {
        nodePushLabelledBy(node, label_id.asU64());
    }
}

/// Return the node of the nearest parent widget that has a non-null accesskit node.
pub fn nodeParent(wd_in: *dvui.WidgetData) struct { *Node, dvui.Id } {
    var wd = wd_in.parent.data();
    while (true) : (wd = wd.parent.data()) {
        if (wd.accesskit_node()) |ak_node| {
            //std.debug.print("parent node is {x} at {s}:{d}\n", .{ wd.id, wd.src.file, wd.src.line });
            return .{ ak_node, wd.id };
        }
    }

    unreachable;
}

/// Convert any actions during the frame into events to be processed next frame
/// Note: Assumes `mutex` is already held.
fn processActions(self: *AccessKit) void {
    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));
    for (self.action_requests.items) |request| {
        switch (request.action) {
            //Action.CLICK => {
            //    const ak_node = self.nodes.get(@enumFromInt(request.target)) orelse {
            //        dvui.log.debug("AccessKit: Action {d} received for a target {x} without a node.", .{ request.action, request.target });
            //        return;
            //    };
            //    const bounds = _: {
            //        const bounds_maybe = nodeBounds(ak_node);
            //        if (bounds_maybe.has_value) break :_ bounds_maybe.value;
            //        dvui.log.debug("AccessKit: Action {d} received for a target {x} without node bounds.", .{ request.action, request.target });
            //        return;
            //    };
            //    const click_point: dvui.Point.Physical = .{ .x = @floatCast((bounds.x0 + bounds.x1) / 2), .y = @floatCast((bounds.y0 + bounds.y1) / 2) };
            //    const floating_win = window.subwindows.windowFor(click_point);

            //    const motion_evt: dvui.Event = .{ .target_widgetId = @enumFromInt(request.target), .evt = .{ .mouse = .{
            //        .action = .{ .motion = .{ .x = 0, .y = 0 } },
            //        .button = .none,
            //        .mod = .none,
            //        .p = click_point,
            //        .floating_win = floating_win,
            //    } } };
            //    window.events.append(window.gpa, motion_evt) catch @panic("TODO");

            //    const focus_evt: dvui.Event = .{
            //        .target_widgetId = @enumFromInt(request.target),
            //        .evt = .{
            //            .mouse = .{
            //                .action = .focus,
            //                .button = .left,
            //                .mod = .none,
            //                .p = click_point,
            //                .floating_win = floating_win,
            //            },
            //        },
            //    };
            //    window.events.append(window.gpa, focus_evt) catch @panic("TODO");

            //    const click_evt: dvui.Event = .{ .target_widgetId = @enumFromInt(request.target), .evt = .{ .mouse = .{
            //        .action = .press,
            //        .button = .left,
            //        .mod = .none,
            //        .p = click_point,
            //        .floating_win = floating_win,
            //    } } };
            //    window.events.append(window.gpa, click_evt) catch @panic("TODO");

            //    const release_evt: dvui.Event = .{ .target_widgetId = @enumFromInt(request.target), .evt = .{ .mouse = .{
            //        .action = .release,
            //        .button = .left,
            //        .mod = .none,
            //        .p = click_point,
            //        .floating_win = floating_win,
            //    } } };
            //    window.events.append(window.gpa, release_evt) catch @panic("TODO");
            //},
            Action.set_value => {
                const ak_node = self.nodes.get(@enumFromInt(request.target)) orelse {
                    dvui.log.debug("AccessKit: Action {d} received for a target {x} without a node.", .{ request.action, request.target });
                    return;
                };
                if (request.data.has_value) {
                    const bounds = _: {
                        const bounds_maybe = nodeBounds(ak_node);
                        if (bounds_maybe.has_value) break :_ bounds_maybe.value;
                        dvui.log.debug("AccessKit: Action {d} received for a target {x} without node bounds.", .{ request.action, request.target });
                        return;
                    };
                    const mid_point: dvui.Point.Physical = .{ .x = @floatCast((bounds.x0 + bounds.x1) / 2), .y = @floatCast((bounds.y0 + bounds.y1) / 2) };
                    _ = window.addEventFocus(.{ .pt = mid_point, .target_id = @enumFromInt(request.target) }) catch @panic("TODO");

                    const text_value: []const u8 = value: {
                        switch (request.data.value.tag) {
                            ActionData.value => break :value std.mem.span(request.data.value.unnamed_0.unnamed_1.value),
                            ActionData.numeric_value => {
                                var writer: std.io.Writer.Allocating = .init(window.arena());
                                writer.writer.print("{d:.6}", .{request.data.value.unnamed_0.unnamed_2.numeric_value}) catch @panic("TODO");
                                break :value writer.toOwnedSlice() catch @panic("TODO");
                            },
                            else => {
                                break :value "";
                            },
                        }
                    };

                    _ = window.addEventText(.{ .text = text_value, .target_id = @enumFromInt(request.target) }) catch @panic("TODO");
                }
            },
            else => {},
        }
    }
    if (self.action_requests.items.len > 0) {
        self.action_requests.clearAndFree(window.gpa);
        dvui.refresh(window, @src(), null);
    }
}

/// Must be called at the end of each frame.
/// Pushes any nodes created during the frame to the accesskit tree.
pub fn pushUpdates(self: *AccessKit) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.status != .on) {
        return;
    }

    // Take any actions from this frame and create events for them.
    // Created events will not be processed until the start of the next frame.
    self.processActions();

    if (builtin.os.tag == .windows) {
        const queued_events = c.accesskit_windows_subclassing_adapter_update_if_active(self.adapter.?, frameTreeUpdate, self);
        if (queued_events) |events| {
            c.accesskit_windows_queued_events_raise(events);
        }
    } else if (builtin.os.tag.isDarwin()) {
        const queued_events = c.accesskit_macos_subclassing_adapter_update_if_active(self.adapter.?, frameTreeUpdate, self);
        if (queued_events) |events| {
            c.accesskit_macos_queued_events_raise(events);
        }
    }

    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));
    self.nodes.clearAndFree(window.gpa);
    self.focused_id = 0;
}

pub fn deinit(self: *AccessKit) void {
    if (!dvui.accesskit_enabled) return;

    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.adapter == null) return;

    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));

    self.action_requests.clearAndFree(window.gpa);
    self.nodes.clearAndFree(window.gpa);
    if (builtin.os.tag == .windows)
        c.accesskit_windows_subclassing_adapter_free(self.adapter.?)
    else if (builtin.os.tag.isDarwin())
        c.accesskit_macos_subclassing_adapter_free(self.adapter.?);
}

/// Pushes all the nodes created during the current frame to AccessKit
/// Called once per frame (if accessibility is initialized)
/// Note: This callback is only during the dynamic extent of pushUpdates on the same thread. TODO: verify this.
fn frameTreeUpdate(instance: ?*anyopaque) callconv(.c) ?*TreeUpdate {
    var self: *AccessKit = @ptrCast(@alignCast(instance));
    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));

    const tree = treeNew(window.wd.id.asU64()) orelse @panic("null");
    if (self.focused_id == 0) self.focused_id = window.data().id.asU64();
    const result = treeUpdateWithCapacityAndFocus(self.nodes.count(), self.focused_id);
    treeUpdateSetTree(result, tree);
    var itr = self.nodes.iterator();
    while (itr.next()) |item| {
        treeUpdatePushNode(result, item.key_ptr.asU64(), item.value_ptr.*);
    }
    return result;
}

/// Creates the initial tree update when accessibility information is first requested by the OS
/// The initial tree only contains basic window details. These are updated when frameTreeUpdate runs.
/// Note: This callback can occur on a non-gui thread.
fn initialTreeUpdate(instance: ?*anyopaque) callconv(.c) ?*TreeUpdate {
    var self: *AccessKit = @ptrCast(@alignCast(instance));
    self.mutex.lock();
    defer self.mutex.unlock();

    const root = nodeNew(Role.window.asU8()) orelse @panic("null");
    const tree = treeNew(0) orelse @panic("null");
    const result = treeUpdateWithCapacityAndFocus(1, 0);
    treeUpdateSetTree(result, tree);
    treeUpdatePushNode(result, 0, root);
    self.status = .starting;

    // Refresh so that the full tree is sent next frame.
    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));
    dvui.refresh(window, @src(), null);
    return result;
}

/// Processing incoming actions, mouse clicks etc.
/// Any action requests which occur are processed at the end of the frame, during pushUpdates()
/// Note: This callback can occur on a non-gui thread.
fn doAction(request: [*c]c.accesskit_action_request, userdata: ?*anyopaque) callconv(.c) void {
    defer actionRequestFree(request);

    var self: *AccessKit = @ptrCast(@alignCast(userdata));

    self.mutex.lock();
    defer self.mutex.unlock();

    const window: *dvui.Window = @alignCast(@fieldParentPtr("accesskit", self));
    self.action_requests.append(window.gpa, request.?.*) catch @panic("TODO");
    dvui.refresh(window, @src(), null);
}

/// Backends should call this to add any events raised by responding to actions.
/// Accessibility events should be added before any other backend events.
pub fn addAllEvents(self: *AccessKit) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    for (self.events.items) |*evt| {
        switch (evt.evt) {
            .text => |*te| {
                self.window.positionMouseEventRemove();
                self.window.event_num += 1;
                evt.num = self.window.event_num;
                // Move text from gpa to arena
                const old_text = te.txt;
                te.txt = self.window.arena().dupe(u8, old_text) catch @panic("TODO");
                self.window.gpa.free(old_text);
                self.window.events.append(self.window.arena(), evt.*) catch @panic("TODO");
                self.window.positionMouseEventAdd() catch @panic("TODO");
            },
            .mouse => |me| {
                switch (me.action) {
                    .motion => |motion| {
                        if (true) {
                            self.window.positionMouseEventRemove();
                            self.window.event_num += 1;
                            evt.num = self.window.event_num;
                            self.window.events.append(self.window.arena(), evt.*) catch @panic("TODO");
                            self.window.positionMouseEventAdd() catch @panic("TODO");
                        } else {
                            _ = self.window.addEventMouseMotion(motion) catch @panic("TODO");
                        }
                        dvui.refresh(self.window, @src(), null);
                    },
                    .press => {
                        self.window.positionMouseEventRemove();

                        self.window.event_num += 1;
                        evt.num = self.window.event_num;
                        self.window.events.append(self.window.arena(), evt.*) catch @panic("TODO");
                        self.window.positionMouseEventAdd() catch @panic("TODO");
                        dvui.refresh(self.window, @src(), null);
                    },
                    .release => {
                        self.window.positionMouseEventRemove();
                        self.window.event_num += 1;
                        evt.num = self.window.event_num;
                        self.window.events.append(self.window.arena(), evt.*) catch @panic("TODO");
                        self.window.positionMouseEventAdd() catch @panic("TODO");
                        dvui.refresh(self.window, @src(), null);
                    },
                    .focus => {
                        self.window.positionMouseEventRemove();
                        self.window.event_num += 1;
                        evt.num = self.window.event_num;
                        self.window.events.append(self.window.arena(), evt.*) catch @panic("TODO");
                        self.window.positionMouseEventAdd() catch @panic("TODO");
                        self.window.focusSubwindow(me.floating_win, self.window.event_num); // TODO: Required.
                    },
                    else => {},
                }
            },
            else => {
                dvui.log.debug("Recevied unhandled AccessKit action event: {f}\n", .{evt});
            },
        }
    }
    dvui.accesskit.events.clearAndFree(self.window.gpa);
}

// While we could build this at comptime, it is nicer for ZLS etc to just
// write it out long form. This list is inlikely to change often.
pub const Role = if (dvui.accesskit_enabled) RoleAccessKit else RoleNoAccessKit;

// Enums
pub const RoleAccessKit = enum(u8) {
    pub fn asU8(self: RoleAccessKit) u8 {
        return @intFromEnum(self);
    }

    none = 255,
    unknown = c.ACCESSKIT_ROLE_UNKNOWN,
    text_run = c.ACCESSKIT_ROLE_TEXT_RUN,
    cell = c.ACCESSKIT_ROLE_CELL,
    label = c.ACCESSKIT_ROLE_LABEL,
    image = c.ACCESSKIT_ROLE_IMAGE,
    link = c.ACCESSKIT_ROLE_LINK,
    row = c.ACCESSKIT_ROLE_ROW,
    list_item = c.ACCESSKIT_ROLE_LIST_ITEM,
    list_marker = c.ACCESSKIT_ROLE_LIST_MARKER,
    tree_item = c.ACCESSKIT_ROLE_TREE_ITEM,
    list_box_option = c.ACCESSKIT_ROLE_LIST_BOX_OPTION,
    menu_item = c.ACCESSKIT_ROLE_MENU_ITEM,
    menu_list_option = c.ACCESSKIT_ROLE_MENU_LIST_OPTION,
    paragraph = c.ACCESSKIT_ROLE_PARAGRAPH,
    generic_container = c.ACCESSKIT_ROLE_GENERIC_CONTAINER,
    check_box = c.ACCESSKIT_ROLE_CHECK_BOX,
    radio_button = c.ACCESSKIT_ROLE_RADIO_BUTTON,
    text_input = c.ACCESSKIT_ROLE_TEXT_INPUT,
    button = c.ACCESSKIT_ROLE_BUTTON,
    default_button = c.ACCESSKIT_ROLE_DEFAULT_BUTTON,
    pane = c.ACCESSKIT_ROLE_PANE,
    row_header = c.ACCESSKIT_ROLE_ROW_HEADER,
    column_header = c.ACCESSKIT_ROLE_COLUMN_HEADER,
    row_group = c.ACCESSKIT_ROLE_ROW_GROUP,
    list = c.ACCESSKIT_ROLE_LIST,
    table = c.ACCESSKIT_ROLE_TABLE,
    layout_table_cell = c.ACCESSKIT_ROLE_LAYOUT_TABLE_CELL,
    layout_table_row = c.ACCESSKIT_ROLE_LAYOUT_TABLE_ROW,
    layout_table = c.ACCESSKIT_ROLE_LAYOUT_TABLE,
    ak_switch = c.ACCESSKIT_ROLE_SWITCH,
    menu = c.ACCESSKIT_ROLE_MENU,
    multiline_text_input = c.ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT,
    search_input = c.ACCESSKIT_ROLE_SEARCH_INPUT,
    date_input = c.ACCESSKIT_ROLE_DATE_INPUT,
    date_time_input = c.ACCESSKIT_ROLE_DATE_TIME_INPUT,
    week_input = c.ACCESSKIT_ROLE_WEEK_INPUT,
    month_input = c.ACCESSKIT_ROLE_MONTH_INPUT,
    time_input = c.ACCESSKIT_ROLE_TIME_INPUT,
    email_input = c.ACCESSKIT_ROLE_EMAIL_INPUT,
    number_input = c.ACCESSKIT_ROLE_NUMBER_INPUT,
    password_input = c.ACCESSKIT_ROLE_PASSWORD_INPUT,
    phone_number_input = c.ACCESSKIT_ROLE_PHONE_NUMBER_INPUT,
    url_input = c.ACCESSKIT_ROLE_URL_INPUT,
    abbr = c.ACCESSKIT_ROLE_ABBR,
    alert = c.ACCESSKIT_ROLE_ALERT,
    alert_dialog = c.ACCESSKIT_ROLE_ALERT_DIALOG,
    application = c.ACCESSKIT_ROLE_APPLICATION,
    article = c.ACCESSKIT_ROLE_ARTICLE,
    audio = c.ACCESSKIT_ROLE_AUDIO,
    banner = c.ACCESSKIT_ROLE_BANNER,
    blockquote = c.ACCESSKIT_ROLE_BLOCKQUOTE,
    canvas = c.ACCESSKIT_ROLE_CANVAS,
    caption = c.ACCESSKIT_ROLE_CAPTION,
    caret = c.ACCESSKIT_ROLE_CARET,
    code = c.ACCESSKIT_ROLE_CODE,
    color_well = c.ACCESSKIT_ROLE_COLOR_WELL,
    combo_box = c.ACCESSKIT_ROLE_COMBO_BOX,
    editable_combo_box = c.ACCESSKIT_ROLE_EDITABLE_COMBO_BOX,
    complementary = c.ACCESSKIT_ROLE_COMPLEMENTARY,
    comment = c.ACCESSKIT_ROLE_COMMENT,
    content_deletion = c.ACCESSKIT_ROLE_CONTENT_DELETION,
    content_insertion = c.ACCESSKIT_ROLE_CONTENT_INSERTION,
    content_info = c.ACCESSKIT_ROLE_CONTENT_INFO,
    definition = c.ACCESSKIT_ROLE_DEFINITION,
    description_list = c.ACCESSKIT_ROLE_DESCRIPTION_LIST,
    description_list_detail = c.ACCESSKIT_ROLE_DESCRIPTION_LIST_DETAIL,
    description_list_term = c.ACCESSKIT_ROLE_DESCRIPTION_LIST_TERM,
    details = c.ACCESSKIT_ROLE_DETAILS,
    dialog = c.ACCESSKIT_ROLE_DIALOG,
    directory = c.ACCESSKIT_ROLE_DIRECTORY,
    disclosure_triangle = c.ACCESSKIT_ROLE_DISCLOSURE_TRIANGLE,
    document = c.ACCESSKIT_ROLE_DOCUMENT,
    embedded_object = c.ACCESSKIT_ROLE_EMBEDDED_OBJECT,
    emphasis = c.ACCESSKIT_ROLE_EMPHASIS,
    feed = c.ACCESSKIT_ROLE_FEED,
    figure_caption = c.ACCESSKIT_ROLE_FIGURE_CAPTION,
    figure = c.ACCESSKIT_ROLE_FIGURE,
    footer = c.ACCESSKIT_ROLE_FOOTER,
    footer_as_non_landmark = c.ACCESSKIT_ROLE_FOOTER_AS_NON_LANDMARK,
    form = c.ACCESSKIT_ROLE_FORM,
    grid = c.ACCESSKIT_ROLE_GRID,
    group = c.ACCESSKIT_ROLE_GROUP,
    header = c.ACCESSKIT_ROLE_HEADER,
    header_as_non_landmark = c.ACCESSKIT_ROLE_HEADER_AS_NON_LANDMARK,
    heading = c.ACCESSKIT_ROLE_HEADING,
    iframe = c.ACCESSKIT_ROLE_IFRAME,
    iframe_presentational = c.ACCESSKIT_ROLE_IFRAME_PRESENTATIONAL,
    ime_candidate = c.ACCESSKIT_ROLE_IME_CANDIDATE,
    keyboard = c.ACCESSKIT_ROLE_KEYBOARD,
    legend = c.ACCESSKIT_ROLE_LEGEND,
    line_break = c.ACCESSKIT_ROLE_LINE_BREAK,
    list_box = c.ACCESSKIT_ROLE_LIST_BOX,
    log = c.ACCESSKIT_ROLE_LOG,
    main = c.ACCESSKIT_ROLE_MAIN,
    mark = c.ACCESSKIT_ROLE_MARK,
    marquee = c.ACCESSKIT_ROLE_MARQUEE,
    math = c.ACCESSKIT_ROLE_MATH,
    menu_bar = c.ACCESSKIT_ROLE_MENU_BAR,
    menu_item_check_box = c.ACCESSKIT_ROLE_MENU_ITEM_CHECK_BOX,
    menu_item_radio = c.ACCESSKIT_ROLE_MENU_ITEM_RADIO,
    menu_list_popup = c.ACCESSKIT_ROLE_MENU_LIST_POPUP,
    meter = c.ACCESSKIT_ROLE_METER,
    navigation = c.ACCESSKIT_ROLE_NAVIGATION,
    note = c.ACCESSKIT_ROLE_NOTE,
    plugin_object = c.ACCESSKIT_ROLE_PLUGIN_OBJECT,
    portal = c.ACCESSKIT_ROLE_PORTAL,
    pre = c.ACCESSKIT_ROLE_PRE,
    progress_indicator = c.ACCESSKIT_ROLE_PROGRESS_INDICATOR,
    radio_group = c.ACCESSKIT_ROLE_RADIO_GROUP,
    region = c.ACCESSKIT_ROLE_REGION,
    root_web_area = c.ACCESSKIT_ROLE_ROOT_WEB_AREA,
    ruby = c.ACCESSKIT_ROLE_RUBY,
    ruby_annotation = c.ACCESSKIT_ROLE_RUBY_ANNOTATION,
    scroll_bar = c.ACCESSKIT_ROLE_SCROLL_BAR,
    scroll_view = c.ACCESSKIT_ROLE_SCROLL_VIEW,
    search = c.ACCESSKIT_ROLE_SEARCH,
    section = c.ACCESSKIT_ROLE_SECTION,
    slider = c.ACCESSKIT_ROLE_SLIDER,
    spin_button = c.ACCESSKIT_ROLE_SPIN_BUTTON,
    splitter = c.ACCESSKIT_ROLE_SPLITTER,
    status = c.ACCESSKIT_ROLE_STATUS,
    strong = c.ACCESSKIT_ROLE_STRONG,
    suggestion = c.ACCESSKIT_ROLE_SUGGESTION,
    svg_root = c.ACCESSKIT_ROLE_SVG_ROOT,
    tab = c.ACCESSKIT_ROLE_TAB,
    tab_list = c.ACCESSKIT_ROLE_TAB_LIST,
    tab_panel = c.ACCESSKIT_ROLE_TAB_PANEL,
    term = c.ACCESSKIT_ROLE_TERM,
    time = c.ACCESSKIT_ROLE_TIME,
    timer = c.ACCESSKIT_ROLE_TIMER,
    title_bar = c.ACCESSKIT_ROLE_TITLE_BAR,
    toolbar = c.ACCESSKIT_ROLE_TOOLBAR,
    tooltip = c.ACCESSKIT_ROLE_TOOLTIP,
    tree = c.ACCESSKIT_ROLE_TREE,
    tree_grid = c.ACCESSKIT_ROLE_TREE_GRID,
    video = c.ACCESSKIT_ROLE_VIDEO,
    web_view = c.ACCESSKIT_ROLE_WEB_VIEW,
    window = c.ACCESSKIT_ROLE_WINDOW,
    pdf_actionable_highlight = c.ACCESSKIT_ROLE_PDF_ACTIONABLE_HIGHLIGHT,
    pdf_root = c.ACCESSKIT_ROLE_PDF_ROOT,
    graphics_document = c.ACCESSKIT_ROLE_GRAPHICS_DOCUMENT,
    graphics_object = c.ACCESSKIT_ROLE_GRAPHICS_OBJECT,
    graphics_symbol = c.ACCESSKIT_ROLE_GRAPHICS_SYMBOL,
    doc_abstract = c.ACCESSKIT_ROLE_DOC_ABSTRACT,
    doc_acknowledgements = c.ACCESSKIT_ROLE_DOC_ACKNOWLEDGEMENTS,
    doc_afterword = c.ACCESSKIT_ROLE_DOC_AFTERWORD,
    doc_appendix = c.ACCESSKIT_ROLE_DOC_APPENDIX,
    doc_back_link = c.ACCESSKIT_ROLE_DOC_BACK_LINK,
    doc_biblio_entry = c.ACCESSKIT_ROLE_DOC_BIBLIO_ENTRY,
    doc_bibliography = c.ACCESSKIT_ROLE_DOC_BIBLIOGRAPHY,
    doc_biblio_ref = c.ACCESSKIT_ROLE_DOC_BIBLIO_REF,
    doc_chapter = c.ACCESSKIT_ROLE_DOC_CHAPTER,
    doc_colophon = c.ACCESSKIT_ROLE_DOC_COLOPHON,
    doc_conclusion = c.ACCESSKIT_ROLE_DOC_CONCLUSION,
    doc_cover = c.ACCESSKIT_ROLE_DOC_COVER,
    doc_credit = c.ACCESSKIT_ROLE_DOC_CREDIT,
    doc_credits = c.ACCESSKIT_ROLE_DOC_CREDITS,
    doc_dedication = c.ACCESSKIT_ROLE_DOC_DEDICATION,
    doc_endnote = c.ACCESSKIT_ROLE_DOC_ENDNOTE,
    doc_endnotes = c.ACCESSKIT_ROLE_DOC_ENDNOTES,
    doc_epigraph = c.ACCESSKIT_ROLE_DOC_EPIGRAPH,
    doc_epilogue = c.ACCESSKIT_ROLE_DOC_EPILOGUE,
    doc_errata = c.ACCESSKIT_ROLE_DOC_ERRATA,
    doc_example = c.ACCESSKIT_ROLE_DOC_EXAMPLE,
    doc_footnote = c.ACCESSKIT_ROLE_DOC_FOOTNOTE,
    doc_foreword = c.ACCESSKIT_ROLE_DOC_FOREWORD,
    doc_glossary = c.ACCESSKIT_ROLE_DOC_GLOSSARY,
    doc_gloss_ref = c.ACCESSKIT_ROLE_DOC_GLOSS_REF,
    doc_index = c.ACCESSKIT_ROLE_DOC_INDEX,
    doc_introduction = c.ACCESSKIT_ROLE_DOC_INTRODUCTION,
    doc_note_ref = c.ACCESSKIT_ROLE_DOC_NOTE_REF,
    doc_notice = c.ACCESSKIT_ROLE_DOC_NOTICE,
    doc_page_break = c.ACCESSKIT_ROLE_DOC_PAGE_BREAK,
    doc_page_footer = c.ACCESSKIT_ROLE_DOC_PAGE_FOOTER,
    doc_page_header = c.ACCESSKIT_ROLE_DOC_PAGE_HEADER,
    doc_page_list = c.ACCESSKIT_ROLE_DOC_PAGE_LIST,
    doc_part = c.ACCESSKIT_ROLE_DOC_PART,
    doc_preface = c.ACCESSKIT_ROLE_DOC_PREFACE,
    doc_prologue = c.ACCESSKIT_ROLE_DOC_PROLOGUE,
    doc_pullquote = c.ACCESSKIT_ROLE_DOC_PULLQUOTE,
    doc_qna = c.ACCESSKIT_ROLE_DOC_QNA,
    doc_subtitle = c.ACCESSKIT_ROLE_DOC_SUBTITLE,
    doc_tip = c.ACCESSKIT_ROLE_DOC_TIP,
    doc_toc = c.ACCESSKIT_ROLE_DOC_TOC,
    list_grid = c.ACCESSKIT_ROLE_LIST_GRID,
    terminal = c.ACCESSKIT_ROLE_TERMINAL,
};

// Enum Structs
pub const Action = struct {
    pub const click = c.ACCESSKIT_ACTION_CLICK;
    pub const focus = c.ACCESSKIT_ACTION_FOCUS;
    pub const blur = c.ACCESSKIT_ACTION_BLUR;
    pub const collapse = c.ACCESSKIT_ACTION_COLLAPSE;
    pub const expand = c.ACCESSKIT_ACTION_EXPAND;
    pub const custom_action = c.ACCESSKIT_ACTION_CUSTOM_ACTION;
    pub const decrement = c.ACCESSKIT_ACTION_DECREMENT;
    pub const increment = c.ACCESSKIT_ACTION_INCREMENT;
    pub const hide_tooltip = c.ACCESSKIT_ACTION_HIDE_TOOLTIP;
    pub const show_tooltip = c.ACCESSKIT_ACTION_SHOW_TOOLTIP;
    pub const replace_selected_text = c.ACCESSKIT_ACTION_REPLACE_SELECTED_TEXT;
    pub const scroll_down = c.ACCESSKIT_ACTION_SCROLL_DOWN;
    pub const scroll_left = c.ACCESSKIT_ACTION_SCROLL_LEFT;
    pub const scroll_right = c.ACCESSKIT_ACTION_SCROLL_RIGHT;
    pub const scroll_up = c.ACCESSKIT_ACTION_SCROLL_UP;
    pub const scroll_into_view = c.ACCESSKIT_ACTION_SCROLL_INTO_VIEW;
    pub const scroll_to_point = c.ACCESSKIT_ACTION_SCROLL_TO_POINT;
    pub const set_scroll_offset = c.ACCESSKIT_ACTION_SET_SCROLL_OFFSET;
    pub const set_text_selection = c.ACCESSKIT_ACTION_SET_TEXT_SELECTION;
    pub const set_sequential_focus_navigation_starting_point = c.ACCESSKIT_ACTION_SET_SEQUENTIAL_FOCUS_NAVIGATION_STARTING_POINT;
    pub const set_value = c.ACCESSKIT_ACTION_SET_VALUE;
    pub const show_context_menu = c.ACCESSKIT_ACTION_SHOW_CONTEXT_MENU;
};

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

pub const Invalid = struct {
    pub const ak_true = c.ACCESSKIT_INVALID_TRUE;
    pub const grammar = c.ACCESSKIT_INVALID_GRAMMAR;
    pub const spelling = c.ACCESSKIT_INVALID_SPELLING;
};

pub const ListStyle = struct {
    pub const circle = c.ACCESSKIT_LIST_STYLE_CIRCLE;
    pub const disc = c.ACCESSKIT_LIST_STYLE_DISC;
    pub const image = c.ACCESSKIT_LIST_STYLE_IMAGE;
    pub const numeric = c.ACCESSKIT_LIST_STYLE_NUMERIC;
    pub const square = c.ACCESSKIT_LIST_STYLE_SQUARE;
    pub const other = c.ACCESSKIT_LIST_STYLE_OTHER;
};

pub const Live = struct {
    pub const off = c.ACCESSKIT_LIVE_OFF;
    pub const polite = c.ACCESSKIT_LIVE_POLITE;
    pub const assertive = c.ACCESSKIT_LIVE_ASSERTIVE;
};

pub const Orientation = struct {
    pub const horizontal = c.ACCESSKIT_ORIENTATION_HORIZONTAL;
    pub const vertical = c.ACCESSKIT_ORIENTATION_VERTICAL;
};

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

pub const SortDirection = struct {
    pub const ascending = c.ACCESSKIT_SORT_DIRECTION_ASCENDING;
    pub const descending = c.ACCESSKIT_SORT_DIRECTION_DESCENDING;
    pub const other = c.ACCESSKIT_SORT_DIRECTION_OTHER;
};

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

pub const Toggled = struct {
    pub const ak_false = c.ACCESSKIT_TOGGLED_FALSE;
    pub const ak_true = c.ACCESSKIT_TOGGLED_TRUE;
    pub const mixed = c.ACCESSKIT_TOGGLED_MIXED;
};

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

// Mappings
pub const MacosAdapter = c.accesskit_macos_adapter;
pub const MacosQueuedEvents = c.accesskit_macos_queued_events;
pub const MacosSubclassingAdapter = c.accesskit_macos_subclassing_adapter;
pub const Node = if (dvui.accesskit_enabled) c.accesskit_node else struct {};
pub const Tree = c.accesskit_tree;
pub const TreeUpdate = c.accesskit_tree_update;
pub const UnixAdapter = c.accesskit_unix_adapter;
pub const WindowsAdapter = c.accesskit_windows_adapter;
pub const WindowsQueuedEvents = c.accesskit_windows_queued_events;
pub const WindowsSubclassingAdapter = c.accesskit_windows_subclassing_adapter;
pub const NodeId = c.accesskit_node_id;
pub const NodeIds = c.accesskit_node_ids;
pub const OptNodeId = c.accesskit_opt_node_id;
pub const OptDouble = c.accesskit_opt_double;
pub const OptIndex = c.accesskit_opt_index;
pub const OptColor = c.accesskit_opt_color;
pub const OptTextDecoration = c.accesskit_opt_text_decoration;
pub const Lengths = c.accesskit_lengths;
pub const OptCoords = c.accesskit_opt_coords;
pub const OptBool = c.accesskit_opt_bool;
pub const OptInvalid = c.accesskit_opt_invalid;
pub const OptToggled = c.accesskit_opt_toggled;
pub const OptLive = c.accesskit_opt_live;
pub const OptTextDirection = c.accesskit_opt_text_direction;
pub const OptOrientation = c.accesskit_opt_orientation;
pub const OptSortDirection = c.accesskit_opt_sort_direction;
pub const OptAriaCurrent = c.accesskit_opt_aria_current;
pub const OptAutoComplete = c.accesskit_opt_auto_complete;
pub const OptHasPopup = c.accesskit_opt_has_popup;
pub const OptListStyle = c.accesskit_opt_list_style;
pub const OptTextAlign = c.accesskit_opt_text_align;
pub const OptVerticalOffset = c.accesskit_opt_vertical_offset;
pub const Affine = c.accesskit_affine;
pub const Rect = c.accesskit_rect;
pub const OptRect = c.accesskit_opt_rect;
pub const TextPosition = c.accesskit_text_position;
pub const TextSelection = c.accesskit_text_selection;
pub const OptTextSelection = c.accesskit_opt_text_selection;
pub const CustomAction = c.accesskit_custom_action;
pub const CustomActions = c.accesskit_custom_actions;
pub const Point = c.accesskit_point;
pub const ActionDataTag = c.accesskit_action_data_Tag;
pub const OptActionData = c.accesskit_opt_action_data;
pub const ActionRequest = if (dvui.accesskit_enabled) c.accesskit_action_request else struct {};
pub const Vec2 = c.accesskit_vec2;
pub const Size = c.accesskit_size;
pub const actionHandlerCallback = c.accesskit_action_handler_callback;
pub const TreeUpdateFactoryUserdata = c.accesskit_tree_update_factory_userdata;
pub const TreeUpdateFactory = c.accesskit_tree_update_factory;
pub const ActivationHandlerCallback = c.accesskit_activation_handler_callback;
pub const DeactivationHandlerCallback = c.accesskit_deactivation_handler_callback;
pub const OptLresult = c.accesskit_opt_lresult;
pub const nodeRole = c.accesskit_node_role;
pub const nodeSetRole = c.accesskit_node_set_role;
pub const nodeSupportsAction = c.accesskit_node_supports_action;
pub const nodeAddAction = c.accesskit_node_add_action;
pub const nodeRemoveAction = c.accesskit_node_remove_action;
pub const nodeClearActions = c.accesskit_node_clear_actions;
pub const nodeChildSupportsAction = c.accesskit_node_child_supports_action;
pub const nodeAddChildAction = c.accesskit_node_add_child_action;
pub const nodeRemoveChildAction = c.accesskit_node_remove_child_action;
pub const nodeClearChildActions = c.accesskit_node_clear_child_actions;
pub const nodeIsHidden = c.accesskit_node_is_hidden;
pub const nodeSetHidden = c.accesskit_node_set_hidden;
pub const nodeClearHidden = c.accesskit_node_clear_hidden;
pub const nodeIsMultiselectable = c.accesskit_node_is_multiselectable;
pub const nodeSetMultiselectable = c.accesskit_node_set_multiselectable;
pub const nodeClearMultiselectable = c.accesskit_node_clear_multiselectable;
pub const nodeIsRequired = c.accesskit_node_is_required;
pub const nodeSetRequired = c.accesskit_node_set_required;
pub const nodeClearRequired = c.accesskit_node_clear_required;
pub const nodeIsVisited = c.accesskit_node_is_visited;
pub const nodeSetVisited = c.accesskit_node_set_visited;
pub const nodeClearVisited = c.accesskit_node_clear_visited;
pub const nodeIsBusy = c.accesskit_node_is_busy;
pub const nodeSetBusy = c.accesskit_node_set_busy;
pub const nodeClearBusy = c.accesskit_node_clear_busy;
pub const nodeIsLiveAtomic = c.accesskit_node_is_live_atomic;
pub const nodeSetLiveAtomic = c.accesskit_node_set_live_atomic;
pub const nodeClearLiveAtomic = c.accesskit_node_clear_live_atomic;
pub const nodeIsModal = c.accesskit_node_is_modal;
pub const nodeSetModal = c.accesskit_node_set_modal;
pub const nodeClearModal = c.accesskit_node_clear_modal;
pub const nodeIsTouchTransparent = c.accesskit_node_is_touch_transparent;
pub const nodeSetTouchTransparent = c.accesskit_node_set_touch_transparent;
pub const nodeClearTouchTransparent = c.accesskit_node_clear_touch_transparent;
pub const nodeIsReadOnly = c.accesskit_node_is_read_only;
pub const nodeSetReadOnly = c.accesskit_node_set_read_only;
pub const nodeClearReadOnly = c.accesskit_node_clear_read_only;
pub const nodeIsDisabled = c.accesskit_node_is_disabled;
pub const nodeSetDisabled = c.accesskit_node_set_disabled;
pub const nodeClearDisabled = c.accesskit_node_clear_disabled;
pub const nodeIsBold = c.accesskit_node_is_bold;
pub const nodeSetBold = c.accesskit_node_set_bold;
pub const nodeClearBold = c.accesskit_node_clear_bold;
pub const nodeIsItalic = c.accesskit_node_is_italic;
pub const nodeSetItalic = c.accesskit_node_set_italic;
pub const nodeClearItalic = c.accesskit_node_clear_italic;
pub const nodeClipsChildren = c.accesskit_node_clips_children;
pub const nodeSetClipsChildren = c.accesskit_node_set_clips_children;
pub const nodeClearClipsChildren = c.accesskit_node_clear_clips_children;
pub const nodeIsLineBreakingObject = c.accesskit_node_is_line_breaking_object;
pub const nodeSetIsLineBreakingObject = c.accesskit_node_set_is_line_breaking_object;
pub const nodeClearIsLineBreakingObject = c.accesskit_node_clear_is_line_breaking_object;
pub const nodeIsPageBreakingObject = c.accesskit_node_is_page_breaking_object;
pub const nodeSetIsPageBreakingObject = c.accesskit_node_set_is_page_breaking_object;
pub const nodeClearIsPageBreakingObject = c.accesskit_node_clear_is_page_breaking_object;
pub const nodeIsSpellingError = c.accesskit_node_is_spelling_error;
pub const nodeSetIsSpellingError = c.accesskit_node_set_is_spelling_error;
pub const nodeClearIsSpellingError = c.accesskit_node_clear_is_spelling_error;
pub const nodeIsGrammarError = c.accesskit_node_is_grammar_error;
pub const nodeSetIsGrammarError = c.accesskit_node_set_is_grammar_error;
pub const nodeClearIsGrammarError = c.accesskit_node_clear_is_grammar_error;
pub const nodeIsSearchMatch = c.accesskit_node_is_search_match;
pub const nodeSetIsSearchMatch = c.accesskit_node_set_is_search_match;
pub const nodeClearIsSearchMatch = c.accesskit_node_clear_is_search_match;
pub const nodeIsSuggestion = c.accesskit_node_is_suggestion;
pub const nodeSetIsSuggestion = c.accesskit_node_set_is_suggestion;
pub const nodeClearIsSuggestion = c.accesskit_node_clear_is_suggestion;
pub const nodeChildren = c.accesskit_node_children;
pub const nodeSetChildren = c.accesskit_node_set_children;
pub const nodePushChild = c.accesskit_node_push_child;
pub const nodeClearChildren = c.accesskit_node_clear_children;
pub const nodeControls = c.accesskit_node_controls;
pub const nodeSetControls = c.accesskit_node_set_controls;
pub const nodePushControlled = c.accesskit_node_push_controlled;
pub const nodeClearControls = c.accesskit_node_clear_controls;
pub const nodeDetails = c.accesskit_node_details;
pub const nodeSetDetails = c.accesskit_node_set_details;
pub const nodePushDetail = c.accesskit_node_push_detail;
pub const nodeClearDetails = c.accesskit_node_clear_details;
pub const nodeDescribedBy = c.accesskit_node_described_by;
pub const nodeSetDescribedBy = c.accesskit_node_set_described_by;
pub const nodePushDescribedBy = c.accesskit_node_push_described_by;
pub const nodeClearDescribedBy = c.accesskit_node_clear_described_by;
pub const nodeFlowTo = c.accesskit_node_flow_to;
pub const nodeSetFlowTo = c.accesskit_node_set_flow_to;
pub const nodePushFlowTo = c.accesskit_node_push_flow_to;
pub const nodeClearFlowTo = c.accesskit_node_clear_flow_to;
pub const nodeLabelledBy = c.accesskit_node_labelled_by;
pub const nodeSetLabelledBy = c.accesskit_node_set_labelled_by;
pub const nodePushLabelledBy = c.accesskit_node_push_labelled_by;
pub const nodeClearLabelledBy = c.accesskit_node_clear_labelled_by;
pub const nodeOwns = c.accesskit_node_owns;
pub const nodeSetOwns = c.accesskit_node_set_owns;
pub const nodePushOwned = c.accesskit_node_push_owned;
pub const nodeClearOwns = c.accesskit_node_clear_owns;
pub const nodeRadioGroup = c.accesskit_node_radio_group;
pub const nodeSetRadioGroup = c.accesskit_node_set_radio_group;
pub const nodePushToRadioGroup = c.accesskit_node_push_to_radio_group;
pub const nodeClearRadioGroup = c.accesskit_node_clear_radio_group;
pub const nodeActiveDescendant = c.accesskit_node_active_descendant;
pub const nodeSetActiveDescendant = c.accesskit_node_set_active_descendant;
pub const nodeClearActiveDescendant = c.accesskit_node_clear_active_descendant;
pub const nodeErrorMessage = c.accesskit_node_error_message;
pub const nodeSetErrorMessage = c.accesskit_node_set_error_message;
pub const nodeClearErrorMessage = c.accesskit_node_clear_error_message;
pub const nodeInPageLinkTarget = c.accesskit_node_in_page_link_target;
pub const nodeSetInPageLinkTarget = c.accesskit_node_set_in_page_link_target;
pub const nodeClearInPageLinkTarget = c.accesskit_node_clear_in_page_link_target;
pub const nodeMemberOf = c.accesskit_node_member_of;
pub const nodeSetMemberOf = c.accesskit_node_set_member_of;
pub const nodeClearMemberOf = c.accesskit_node_clear_member_of;
pub const nodeNextOnLine = c.accesskit_node_next_on_line;
pub const nodeSetNextOnLine = c.accesskit_node_set_next_on_line;
pub const nodeClearNextOnLine = c.accesskit_node_clear_next_on_line;
pub const nodePreviousOnLine = c.accesskit_node_previous_on_line;
pub const nodeSetPreviousOnLine = c.accesskit_node_set_previous_on_line;
pub const nodeClearPreviousOnLine = c.accesskit_node_clear_previous_on_line;
pub const nodePopupFor = c.accesskit_node_popup_for;
pub const nodeSetPopupFor = c.accesskit_node_set_popup_for;
pub const nodeClearPopupFor = c.accesskit_node_clear_popup_for;
pub const stringFree = c.accesskit_string_free;
pub const nodeLabel = c.accesskit_node_label;
pub const nodeSetLabel = c.accesskit_node_set_label;
pub const nodeClearLabel = c.accesskit_node_clear_label;
pub const nodeDescription = c.accesskit_node_description;
pub const nodeSetDescription = c.accesskit_node_set_description;
pub const nodeClearDescription = c.accesskit_node_clear_description;
pub const nodeValue = c.accesskit_node_value;
pub const nodeSetValue = c.accesskit_node_set_value;
pub const nodeClearValue = c.accesskit_node_clear_value;
pub const nodeAccessKey = c.accesskit_node_access_key;
pub const nodeSetAccessKey = c.accesskit_node_set_access_key;
pub const nodeClearAccessKey = c.accesskit_node_clear_access_key;
pub const nodeAuthorId = c.accesskit_node_author_id;
pub const nodeSetAuthorId = c.accesskit_node_set_author_id;
pub const nodeClearAuthorId = c.accesskit_node_clear_author_id;
pub const nodeClassName = c.accesskit_node_class_name;
pub const nodeSetClassName = c.accesskit_node_set_class_name;
pub const nodeClearClassName = c.accesskit_node_clear_class_name;
pub const nodeFontFamily = c.accesskit_node_font_family;
pub const nodeSetFontFamily = c.accesskit_node_set_font_family;
pub const nodeClearFontFamily = c.accesskit_node_clear_font_family;
pub const nodeHtmlTag = c.accesskit_node_html_tag;
pub const nodeSetHtmlTag = c.accesskit_node_set_html_tag;
pub const nodeClearHtmlTag = c.accesskit_node_clear_html_tag;
pub const nodeInnerHtml = c.accesskit_node_inner_html;
pub const nodeSetInnerHtml = c.accesskit_node_set_inner_html;
pub const nodeClearInnerHtml = c.accesskit_node_clear_inner_html;
pub const nodeKeyboardShortcut = c.accesskit_node_keyboard_shortcut;
pub const nodeSetKeyboardShortcut = c.accesskit_node_set_keyboard_shortcut;
pub const nodeClearKeyboardShortcut = c.accesskit_node_clear_keyboard_shortcut;
pub const nodeLanguage = c.accesskit_node_language;
pub const nodeSetLanguage = c.accesskit_node_set_language;
pub const nodeClearLanguage = c.accesskit_node_clear_language;
pub const nodePlaceholder = c.accesskit_node_placeholder;
pub const nodeSetPlaceholder = c.accesskit_node_set_placeholder;
pub const nodeClearPlaceholder = c.accesskit_node_clear_placeholder;
pub const nodeRoleDescription = c.accesskit_node_role_description;
pub const nodeSetRoleDescription = c.accesskit_node_set_role_description;
pub const nodeClearRoleDescription = c.accesskit_node_clear_role_description;
pub const nodeStateDescription = c.accesskit_node_state_description;
pub const nodeSetStateDescription = c.accesskit_node_set_state_description;
pub const nodeClearStateDescription = c.accesskit_node_clear_state_description;
pub const nodeTooltip = c.accesskit_node_tooltip;
pub const nodeSetTooltip = c.accesskit_node_set_tooltip;
pub const nodeClearTooltip = c.accesskit_node_clear_tooltip;
pub const nodeUrl = c.accesskit_node_url;
pub const nodeSetUrl = c.accesskit_node_set_url;
pub const nodeClearUrl = c.accesskit_node_clear_url;
pub const nodeRowIndexText = c.accesskit_node_row_index_text;
pub const nodeSetRowIndexText = c.accesskit_node_set_row_index_text;
pub const nodeClearRowIndexText = c.accesskit_node_clear_row_index_text;
pub const nodeColumnIndexText = c.accesskit_node_column_index_text;
pub const nodeSetColumnIndexText = c.accesskit_node_set_column_index_text;
pub const nodeClearColumnIndexText = c.accesskit_node_clear_column_index_text;
pub const nodeScrollX = c.accesskit_node_scroll_x;
pub const nodeSetScrollX = c.accesskit_node_set_scroll_x;
pub const nodeClearScrollX = c.accesskit_node_clear_scroll_x;
pub const nodeScrollXMin = c.accesskit_node_scroll_x_min;
pub const nodeSetScrollXMin = c.accesskit_node_set_scroll_x_min;
pub const nodeClearScrollXMin = c.accesskit_node_clear_scroll_x_min;
pub const nodeScrollXMax = c.accesskit_node_scroll_x_max;
pub const nodeSetScrollXMax = c.accesskit_node_set_scroll_x_max;
pub const nodeClearScrollXMax = c.accesskit_node_clear_scroll_x_max;
pub const nodeScrollY = c.accesskit_node_scroll_y;
pub const nodeSetScrollY = c.accesskit_node_set_scroll_y;
pub const nodeClearScrollY = c.accesskit_node_clear_scroll_y;
pub const nodeScrollYMin = c.accesskit_node_scroll_y_min;
pub const nodeSetScrollYMin = c.accesskit_node_set_scroll_y_min;
pub const nodeClearScrollYMin = c.accesskit_node_clear_scroll_y_min;
pub const nodeScrollYMax = c.accesskit_node_scroll_y_max;
pub const nodeSetScrollYMax = c.accesskit_node_set_scroll_y_max;
pub const nodeClearScrollYMax = c.accesskit_node_clear_scroll_y_max;
pub const nodeNumericValue = c.accesskit_node_numeric_value;
pub const nodeSetNumericValue = c.accesskit_node_set_numeric_value;
pub const nodeClearNumericValue = c.accesskit_node_clear_numeric_value;
pub const nodeMinNumericValue = c.accesskit_node_min_numeric_value;
pub const nodeSetMinNumericValue = c.accesskit_node_set_min_numeric_value;
pub const nodeClearMinNumericValue = c.accesskit_node_clear_min_numeric_value;
pub const nodeMaxNumericValue = c.accesskit_node_max_numeric_value;
pub const nodeSetMaxNumericValue = c.accesskit_node_set_max_numeric_value;
pub const nodeClearMaxNumericValue = c.accesskit_node_clear_max_numeric_value;
pub const nodeNumericValueStep = c.accesskit_node_numeric_value_step;
pub const nodeSetNumericValueStep = c.accesskit_node_set_numeric_value_step;
pub const nodeClearNumericValueStep = c.accesskit_node_clear_numeric_value_step;
pub const nodeNumericValueJump = c.accesskit_node_numeric_value_jump;
pub const nodeSetNumericValueJump = c.accesskit_node_set_numeric_value_jump;
pub const nodeClearNumericValueJump = c.accesskit_node_clear_numeric_value_jump;
pub const nodeFontSize = c.accesskit_node_font_size;
pub const nodeSetFontSize = c.accesskit_node_set_font_size;
pub const nodeClearFontSize = c.accesskit_node_clear_font_size;
pub const nodeFontWeight = c.accesskit_node_font_weight;
pub const nodeSetFontWeight = c.accesskit_node_set_font_weight;
pub const nodeClearFontWeight = c.accesskit_node_clear_font_weight;
pub const nodeRowCount = c.accesskit_node_row_count;
pub const nodeSetRowCount = c.accesskit_node_set_row_count;
pub const nodeClearRowCount = c.accesskit_node_clear_row_count;
pub const nodeColumnCount = c.accesskit_node_column_count;
pub const nodeSetColumnCount = c.accesskit_node_set_column_count;
pub const nodeClearColumnCount = c.accesskit_node_clear_column_count;
pub const nodeRowIndex = c.accesskit_node_row_index;
pub const nodeSetRowIndex = c.accesskit_node_set_row_index;
pub const nodeClearRowIndex = c.accesskit_node_clear_row_index;
pub const nodeColumnIndex = c.accesskit_node_column_index;
pub const nodeSetColumnIndex = c.accesskit_node_set_column_index;
pub const nodeClearColumnIndex = c.accesskit_node_clear_column_index;
pub const nodeRowSpan = c.accesskit_node_row_span;
pub const nodeSetRowSpan = c.accesskit_node_set_row_span;
pub const nodeClearRowSpan = c.accesskit_node_clear_row_span;
pub const nodeColumnSpan = c.accesskit_node_column_span;
pub const nodeSetColumnSpan = c.accesskit_node_set_column_span;
pub const nodeClearColumnSpan = c.accesskit_node_clear_column_span;
pub const nodeLevel = c.accesskit_node_level;
pub const nodeSetLevel = c.accesskit_node_set_level;
pub const nodeClearLevel = c.accesskit_node_clear_level;
pub const nodeSizeOfSet = c.accesskit_node_size_of_set;
pub const nodeSetSizeOfSet = c.accesskit_node_set_size_of_set;
pub const nodeClearSizeOfSet = c.accesskit_node_clear_size_of_set;
pub const nodePositionInSet = c.accesskit_node_position_in_set;
pub const nodeSetPositionInSet = c.accesskit_node_set_position_in_set;
pub const nodeClearPositionInSet = c.accesskit_node_clear_position_in_set;
pub const nodeColorValue = c.accesskit_node_color_value;
pub const nodeSetColorValue = c.accesskit_node_set_color_value;
pub const nodeClearColorValue = c.accesskit_node_clear_color_value;
pub const nodeBackgroundColor = c.accesskit_node_background_color;
pub const nodeSetBackgroundColor = c.accesskit_node_set_background_color;
pub const nodeClearBackgroundColor = c.accesskit_node_clear_background_color;
pub const nodeForegroundColor = c.accesskit_node_foreground_color;
pub const nodeSetForegroundColor = c.accesskit_node_set_foreground_color;
pub const nodeClearForegroundColor = c.accesskit_node_clear_foreground_color;
pub const nodeOverline = c.accesskit_node_overline;
pub const nodeSetOverline = c.accesskit_node_set_overline;
pub const nodeClearOverline = c.accesskit_node_clear_overline;
pub const nodeStrikethrough = c.accesskit_node_strikethrough;
pub const nodeSetStrikethrough = c.accesskit_node_set_strikethrough;
pub const nodeClearStrikethrough = c.accesskit_node_clear_strikethrough;
pub const nodeUnderline = c.accesskit_node_underline;
pub const nodeSetUnderline = c.accesskit_node_set_underline;
pub const nodeClearUnderline = c.accesskit_node_clear_underline;
pub const nodeCharacterLengths = c.accesskit_node_character_lengths;
pub const nodeSetCharacterLengths = c.accesskit_node_set_character_lengths;
pub const nodeClearCharacterLengths = c.accesskit_node_clear_character_lengths;
pub const nodeWordLengths = c.accesskit_node_word_lengths;
pub const nodeSetWordLengths = c.accesskit_node_set_word_lengths;
pub const nodeClearWordLengths = c.accesskit_node_clear_word_lengths;
pub const nodeCharacterPositions = c.accesskit_node_character_positions;
pub const nodeSetCharacterPositions = c.accesskit_node_set_character_positions;
pub const nodeClearCharacterPositions = c.accesskit_node_clear_character_positions;
pub const nodeCharacterWidths = c.accesskit_node_character_widths;
pub const nodeSetCharacterWidths = c.accesskit_node_set_character_widths;
pub const nodeClearCharacterWidths = c.accesskit_node_clear_character_widths;
pub const nodeIsExpanded = c.accesskit_node_is_expanded;
pub const nodeSetExpanded = c.accesskit_node_set_expanded;
pub const nodeClearExpanded = c.accesskit_node_clear_expanded;
pub const nodeIsSelected = c.accesskit_node_is_selected;
pub const nodeSetSelected = c.accesskit_node_set_selected;
pub const nodeClearSelected = c.accesskit_node_clear_selected;
pub const nodeInvalid = c.accesskit_node_invalid;
pub const nodeSetInvalid = c.accesskit_node_set_invalid;
pub const nodeClearInvalid = c.accesskit_node_clear_invalid;
pub const nodeToggled = c.accesskit_node_toggled;
pub const nodeSetToggled = c.accesskit_node_set_toggled;
pub const nodeClearToggled = c.accesskit_node_clear_toggled;
pub const nodeLive = c.accesskit_node_live;
pub const nodeSetLive = c.accesskit_node_set_live;
pub const nodeClearLive = c.accesskit_node_clear_live;
pub const nodeTextDirection = c.accesskit_node_text_direction;
pub const nodeSetTextDirection = c.accesskit_node_set_text_direction;
pub const nodeClearTextDirection = c.accesskit_node_clear_text_direction;
pub const nodeOrientation = c.accesskit_node_orientation;
pub const nodeSetOrientation = c.accesskit_node_set_orientation;
pub const nodeClearOrientation = c.accesskit_node_clear_orientation;
pub const nodeSortDirection = c.accesskit_node_sort_direction;
pub const nodeSetSortDirection = c.accesskit_node_set_sort_direction;
pub const nodeClearSortDirection = c.accesskit_node_clear_sort_direction;
pub const nodeAriaCurrent = c.accesskit_node_aria_current;
pub const nodeSetAriaCurrent = c.accesskit_node_set_aria_current;
pub const nodeClearAriaCurrent = c.accesskit_node_clear_aria_current;
pub const nodeAutoComplete = c.accesskit_node_auto_complete;
pub const nodeSetAutoComplete = c.accesskit_node_set_auto_complete;
pub const nodeClearAutoComplete = c.accesskit_node_clear_auto_complete;
pub const nodeHasPopup = c.accesskit_node_has_popup;
pub const nodeSetHasPopup = c.accesskit_node_set_has_popup;
pub const nodeClearHasPopup = c.accesskit_node_clear_has_popup;
pub const nodeListStyle = c.accesskit_node_list_style;
pub const nodeSetListStyle = c.accesskit_node_set_list_style;
pub const nodeClearListStyle = c.accesskit_node_clear_list_style;
pub const nodeTextAlign = c.accesskit_node_text_align;
pub const nodeSetTextAlign = c.accesskit_node_set_text_align;
pub const nodeClearTextAlign = c.accesskit_node_clear_text_align;
pub const nodeVerticalOffset = c.accesskit_node_vertical_offset;
pub const nodeSetVerticalOffset = c.accesskit_node_set_vertical_offset;
pub const nodeClearVerticalOffset = c.accesskit_node_clear_vertical_offset;
pub const nodeTransform = c.accesskit_node_transform;
pub const nodeSetTransform = c.accesskit_node_set_transform;
pub const nodeClearTransform = c.accesskit_node_clear_transform;
pub const nodeBounds = c.accesskit_node_bounds;
pub const nodeSetBounds = c.accesskit_node_set_bounds;
pub const nodeClearBounds = c.accesskit_node_clear_bounds;
pub const nodeTextSelection = c.accesskit_node_text_selection;
pub const nodeSetTextSelection = c.accesskit_node_set_text_selection;
pub const nodeClearTextSelection = c.accesskit_node_clear_text_selection;
pub const customActionNew = c.accesskit_custom_action_new;
pub const customActionsFree = c.accesskit_custom_actions_free;
pub const nodeCustomActions = c.accesskit_node_custom_actions;
pub const nodeSetCustomActions = c.accesskit_node_set_custom_actions;
pub const nodePushCustomAction = c.accesskit_node_push_custom_action;
pub const nodeClearCustomActions = c.accesskit_node_clear_custom_actions;
pub const nodeNew = c.accesskit_node_new;
pub const nodeFree = c.accesskit_node_free;
pub const treeNew = c.accesskit_tree_new;
pub const treeFree = c.accesskit_tree_free;
pub const treeGetToolkitName = c.accesskit_tree_get_toolkit_name;
pub const treeSetToolkitName = c.accesskit_tree_set_toolkit_name;
pub const treeClearToolkitName = c.accesskit_tree_clear_toolkit_name;
pub const treeGetToolkitVersion = c.accesskit_tree_get_toolkit_version;
pub const treeSetToolkitVersion = c.accesskit_tree_set_toolkit_version;
pub const treeClearToolkitVersion = c.accesskit_tree_clear_toolkit_version;
pub const treeUpdateWithFocus = c.accesskit_tree_update_with_focus;
pub const treeUpdateWithCapacityAndFocus = c.accesskit_tree_update_with_capacity_and_focus;
pub const treeUpdateFree = c.accesskit_tree_update_free;
pub const treeUpdatePushNode = c.accesskit_tree_update_push_node;
pub const treeUpdateSetTree = c.accesskit_tree_update_set_tree;
pub const treeUpdateClearTree = c.accesskit_tree_update_clear_tree;
pub const treeUpdateSetFocus = c.accesskit_tree_update_set_focus;
pub const actionRequestFree = c.accesskit_action_request_free;
pub const affineIdentity = c.accesskit_affine_identity;
pub const affineFlipY = c.accesskit_affine_flip_y;
pub const affineFlipX = c.accesskit_affine_flip_x;
pub const affineScale = c.accesskit_affine_scale;
pub const affineScaleNonUniform = c.accesskit_affine_scale_non_uniform;
pub const affineTranslate = c.accesskit_affine_translate;
pub const affineMapUnitSquare = c.accesskit_affine_map_unit_square;
pub const affineDeterminant = c.accesskit_affine_determinant;
pub const affineInverse = c.accesskit_affine_inverse;
pub const affineTransformRectBbox = c.accesskit_affine_transform_rect_bbox;
pub const affineIsFinite = c.accesskit_affine_is_finite;
pub const affineIsNan = c.accesskit_affine_is_nan;
pub const pointToVec2 = c.accesskit_point_to_vec2;
pub const rectFromPoints = c.accesskit_rect_from_points;
pub const rectFromOriginSize = c.accesskit_rect_from_origin_size;
pub const rectWithOrigin = c.accesskit_rect_with_origin;
pub const rectWithSize = c.accesskit_rect_with_size;
pub const rectWidth = c.accesskit_rect_width;
pub const rectHeight = c.accesskit_rect_height;
pub const rectMinX = c.accesskit_rect_min_x;
pub const rectMaxX = c.accesskit_rect_max_x;
pub const rectMinY = c.accesskit_rect_min_y;
pub const rectMaxY = c.accesskit_rect_max_y;
pub const rectOrigin = c.accesskit_rect_origin;
pub const rectSize = c.accesskit_rect_size;
pub const rectAbs = c.accesskit_rect_abs;
pub const rectArea = c.accesskit_rect_area;
pub const rectIsEmpty = c.accesskit_rect_is_empty;
pub const rectContains = c.accesskit_rect_contains;
pub const rectUnion = c.accesskit_rect_union;
pub const rectUnionPt = c.accesskit_rect_union_pt;
pub const rectIntersect = c.accesskit_rect_intersect;
pub const sizeToVec2 = c.accesskit_size_to_vec2;
pub const vec2ToPoint = c.accesskit_vec2_to_point;
pub const vec2ToSize = c.accesskit_vec2_to_size;
pub const macosQueuedEventsRaise = c.accesskit_macos_queued_events_raise;
pub const macosAdapterNew = c.accesskit_macos_adapter_new;
pub const macosAdapterFree = c.accesskit_macos_adapter_free;
pub const macosAdapterUpdateIfActive = c.accesskit_macos_adapter_update_if_active;
pub const macosAdapterUpdateViewFocusState = c.accesskit_macos_adapter_update_view_focus_state;
pub const macosAdapterViewChildren = c.accesskit_macos_adapter_view_children;
pub const macosAdapterFocus = c.accesskit_macos_adapter_focus;
pub const macosAdapterHitTest = c.accesskit_macos_adapter_hit_test;
pub const macosSubclassingAdapterNew = c.accesskit_macos_subclassing_adapter_new;
pub const macosSubclassingAdapterForWindow = c.accesskit_macos_subclassing_adapter_for_window;
pub const macosSubclassingAdapterFree = c.accesskit_macos_subclassing_adapter_free;
pub const macosSubclassingAdapterUpdateIfActive = c.accesskit_macos_subclassing_adapter_update_if_active;
pub const macosSubclassingAdapterUpdateViewFocusState = c.accesskit_macos_subclassing_adapter_update_view_focus_state;
pub const macosAddFocusForwarderToWindowClass = c.accesskit_macos_add_focus_forwarder_to_window_class;
pub const unixAdapterNew = c.accesskit_unix_adapter_new;
pub const unixAdapterFree = c.accesskit_unix_adapter_free;
pub const unixAdapterSetRootWindowBounds = c.accesskit_unix_adapter_set_root_window_bounds;
pub const unixAdapterUpdateIfActive = c.accesskit_unix_adapter_update_if_active;
pub const unixAdapterUpdateWindowFocusState = c.accesskit_unix_adapter_update_window_focus_state;
pub const windowsQueuedEventsRaise = c.accesskit_windows_queued_events_raise;
pub const windowsAdapterNew = c.accesskit_windows_adapter_new;
pub const windowsAdapterFree = c.accesskit_windows_adapter_free;
pub const windowsAdapterUpdateIfActive = c.accesskit_windows_adapter_update_if_active;
pub const windowsAdapterUpdateWindowFocusState = c.accesskit_windows_adapter_update_window_focus_state;
pub const windowsAdapterHandleWmGetobject = c.accesskit_windows_adapter_handle_wm_getobject;
pub const windowsSubclassingAdapterNew = c.accesskit_windows_subclassing_adapter_new;
pub const windowsSubclassingAdapterFree = c.accesskit_windows_subclassing_adapter_free;
pub const windowsSubclassingAdapterUpdateIfActive = c.accesskit_windows_subclassing_adapter_update_if_active;
// Non libc Mappings
pub const RoleNoAccessKit = enum {
    none,
    unknown,
    text_run,
    cell,
    label,
    image,
    link,
    row,
    list_item,
    list_marker,
    tree_item,
    list_box_option,
    menu_item,
    menu_list_option,
    paragraph,
    generic_container,
    check_box,
    radio_button,
    text_input,
    button,
    default_button,
    pane,
    row_header,
    column_header,
    row_group,
    list,
    table,
    layout_table_cell,
    layout_table_row,
    layout_table,
    ak_switch,
    menu,
    multiline_text_input,
    search_input,
    date_input,
    date_time_input,
    week_input,
    month_input,
    time_input,
    email_input,
    number_input,
    password_input,
    phone_number_input,
    url_input,
    abbr,
    alert,
    alert_dialog,
    application,
    article,
    audio,
    banner,
    blockquote,
    canvas,
    caption,
    caret,
    code,
    color_well,
    combo_box,
    editable_combo_box,
    complementary,
    comment,
    content_deletion,
    content_insertion,
    content_info,
    definition,
    description_list,
    description_list_detail,
    description_list_term,
    details,
    dialog,
    directory,
    disclosure_triangle,
    document,
    embedded_object,
    emphasis,
    feed,
    figure_caption,
    figure,
    footer,
    footer_as_non_landmark,
    form,
    grid,
    group,
    header,
    header_as_non_landmark,
    heading,
    iframe,
    iframe_presentational,
    ime_candidate,
    keyboard,
    legend,
    line_break,
    list_box,
    log,
    main,
    mark,
    marquee,
    math,
    menu_bar,
    menu_item_check_box,
    menu_item_radio,
    menu_list_popup,
    meter,
    navigation,
    note,
    plugin_object,
    portal,
    pre,
    progress_indicator,
    radio_group,
    region,
    root_web_area,
    ruby,
    ruby_annotation,
    scroll_bar,
    scroll_view,
    search,
    section,
    slider,
    spin_button,
    splitter,
    status,
    strong,
    suggestion,
    svg_root,
    tab,
    tab_list,
    tab_panel,
    term,
    time,
    timer,
    title_bar,
    toolbar,
    tooltip,
    tree,
    tree_grid,
    video,
    web_view,
    window,
    pdf_actionable_highlight,
    pdf_root,
    graphics_document,
    graphics_object,
    graphics_symbol,
    doc_abstract,
    doc_acknowledgements,
    doc_afterword,
    doc_appendix,
    doc_back_link,
    doc_biblio_entry,
    doc_bibliography,
    doc_biblio_ref,
    doc_chapter,
    doc_colophon,
    doc_conclusion,
    doc_cover,
    doc_credit,
    doc_credits,
    doc_dedication,
    doc_endnote,
    doc_endnotes,
    doc_epigraph,
    doc_epilogue,
    doc_errata,
    doc_example,
    doc_footnote,
    doc_foreword,
    doc_glossary,
    doc_gloss_ref,
    doc_index,
    doc_introduction,
    doc_note_ref,
    doc_notice,
    doc_page_break,
    doc_page_footer,
    doc_page_header,
    doc_page_list,
    doc_part,
    doc_preface,
    doc_prologue,
    doc_pullquote,
    doc_qna,
    doc_subtitle,
    doc_tip,
    doc_toc,
    list_grid,
    terminal,
};
