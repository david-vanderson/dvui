// TODO:
// [ ] MENU vs MENU ITEMS.. There isn't really a distinction in DVUI? Maybe the use of floating menu widget could sort this out for us?
// [ ] Create structs/enums for common values like ORIENTATION
pub const c = @cImport({
    @cInclude("accesskit.h");
});
const builtin = @import("builtin");

pub const AccessKit = @This();
const dvui = @import("dvui.zig");
const SDLBackend = @import("backend");

backend: *SDLBackend,
window: *dvui.Window,
adapter: AdapterType(),
root: *Node = undefined,
// Note: Any access to `nodes` must be protected by `mutex`.
nodes: std.AutoArrayHashMapUnmanaged(dvui.Id, *Node),
// Note: Any access to `events` must be protected by `mutex`.
events: std.ArrayList(dvui.Event),
// Note: Any access to `action_requests` must be protected by `mutex`.
action_requests: std.ArrayList(ActionRequest),
active: bool = false,
mutex: std.Thread.Mutex,

fn AdapterType() type {
    if (builtin.os.tag == .windows) {
        return *c.accesskit_windows_subclassing_adapter;
    } else if (builtin.os.tag.isDarwin()) {
        return *c.accesskit_macos_subclassing_adapter;
    } else {
        return void;
    }
}
/// Perform SDL3-specific initialization
pub fn initSDL3(self: *AccessKit, backend: *SDLBackend, window: *dvui.Window) void {
    // TODO: This is windows OS-specific right now
    self.* = .{
        .backend = backend,
        .window = window,
        .adapter = undefined,
        .nodes = .empty,
        .action_requests = .empty,
        .events = .empty,
        .mutex = .{},
    };

    if (builtin.os.tag == .windows) {
        const properties: SDLBackend.c.SDL_PropertiesID = SDLBackend.c.SDL_GetWindowProperties(backend.window);
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
        const properties: SDLBackend.c.SDL_PropertiesID = SDLBackend.c.SDL_GetWindowProperties(backend.window);
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

    if (!self.active) return null;
    if (!wd.visible()) return null;

    //std.debug.print("Creating Node for {x} at {s}:{d}\n", .{ wd.id, wd.src.file, wd.src.line });

    const ak_node = nodeNew(role.asU8()) orelse @panic("TODO");
    wd.ak_node = ak_node;
    const border_rect = dvui.clipGet().intersect(wd.borderRectScale().r);
    nodeSetBounds(ak_node, .{ .x0 = border_rect.x, .y0 = border_rect.y, .x1 = border_rect.bottomRight().x, .y1 = border_rect.bottomRight().y });

    const parent_node = self.nodeParent(wd);
    nodePushChild(parent_node, wd.id.asU64());

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

    if (self.nodes.contains(wd.id)) @panic("Dupe!!"); // TODO:
    self.nodes.put(self.window.gpa, wd.id, ak_node) catch @panic("TODO");

    return ak_node;
}

pub inline fn nodeLabelFor(self: *AccessKit, label_id: dvui.Id, target_id: dvui.Id) void {
    if (!dvui.accesskit_enabled) return;

    if (self.nodes.get(target_id)) |node| {
        nodePushLabelledBy(node, label_id.asU64());
    }
}

/// Return the node of the nearest parent widget that has a non-null accesskit node.
pub fn nodeParent(self: *const AccessKit, wd_in: *dvui.WidgetData) *Node {
    if (wd_in.id == wd_in.parent.data().id) {
        //std.debug.print("parent ak node at root\n", .{});
        return self.root;
    }

    var wd = wd_in.parent.data();
    while (true) : (wd = wd.parent.data()) {
        if (wd.accesskit_node()) |ak_node| {
            //std.debug.print("parent ak node at {x} at {s}:{d}\n", .{ wd.id, wd.src.file, wd.src.line});
            return ak_node;
        }
    }

    unreachable;
}

/// Convert any actions during the frame into events to be processed next frame
/// Note: Assumes `mutex` is already held.
fn processActions(self: *AccessKit) void {
    for (self.action_requests.items) |request| {
        switch (request.action) {
            Action.CLICK => {
                const ak_node = self.nodes.get(@enumFromInt(request.target)) orelse {
                    dvui.log.debug("AccessKit: Action {d} received for a target {x} without a node.", .{ request.action, request.target });
                    return;
                };
                const bounds = _: {
                    const bounds_maybe = nodeBounds(ak_node);
                    if (bounds_maybe.has_value) break :_ bounds_maybe.value;
                    dvui.log.debug("AccessKit: Action {d} received for a target {x} without node bounds.", .{ request.action, request.target });
                    return;
                };
                const click_point: dvui.Point.Physical = .{ .x = @floatCast((bounds.x0 + bounds.x1) / 2), .y = @floatCast((bounds.y0 + bounds.y1) / 2) };
                const floating_win = self.window.subwindows.windowFor(click_point);
                const motion_evt: dvui.Event = .{ .target_widgetId = @enumFromInt(request.target), .evt = .{ .mouse = .{
                    .action = .{ .motion = .{ .x = 0, .y = 0 } },
                    .button = .none,
                    .mod = .none,
                    .p = click_point,
                    .floating_win = floating_win,
                } } };
                self.events.append(self.window.gpa, motion_evt) catch @panic("TODO");

                const focus_evt: dvui.Event = .{
                    .target_widgetId = @enumFromInt(request.target),
                    .evt = .{
                        .mouse = .{
                            .action = .focus,
                            .button = .left,
                            .mod = .none,
                            .p = click_point,
                            .floating_win = floating_win,
                        },
                    },
                };
                self.events.append(self.window.gpa, focus_evt) catch @panic("TODO");

                const click_evt: dvui.Event = .{ .target_widgetId = @enumFromInt(request.target), .evt = .{ .mouse = .{
                    .action = .press,
                    .button = .left,
                    .mod = .none,
                    .p = click_point,
                    .floating_win = floating_win,
                } } };
                self.events.append(self.window.gpa, click_evt) catch @panic("TODO");

                const release_evt: dvui.Event = .{ .target_widgetId = @enumFromInt(request.target), .evt = .{ .mouse = .{
                    .action = .release,
                    .button = .left,
                    .mod = .none,
                    .p = click_point,
                    .floating_win = floating_win,
                } } };
                self.events.append(self.window.gpa, release_evt) catch @panic("TODO");
            },
            Action.SET_VALUE => {
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
                    const floating_win = self.window.subwindows.windowFor(mid_point);

                    self.events.append(self.window.gpa, dvui.Event{
                        .target_widgetId = @enumFromInt(request.target),
                        .evt = .{
                            .mouse = .{
                                .action = .focus,
                                .button = .none,
                                .mod = .none,
                                .p = mid_point,
                                .floating_win = floating_win,
                            },
                        },
                    }) catch @panic("TODO");

                    const text_value = value: {
                        switch (request.data.value.tag) {
                            // Note this has to be done on gpa, rather than arena as we need it available for the start of the next frame.
                            c.ACCESSKIT_ACTION_DATA_VALUE => break :value self.window.gpa.dupe(u8, std.mem.span(request.data.value.unnamed_0.unnamed_1.value)) catch @panic("TODO"),
                            c.ACCESSKIT_ACTION_DATA_NUMERIC_VALUE => {
                                var writer: std.io.Writer.Allocating = .init(self.window.gpa);
                                writer.writer.print("{d:.6}", .{request.data.value.unnamed_0.unnamed_2.numeric_value}) catch @panic("TODO");
                                break :value writer.toOwnedSlice() catch @panic("TODO");
                            },
                            else => {
                                break :value "";
                            },
                        }
                    };
                    const text_evt: dvui.Event = .{
                        .target_widgetId = @enumFromInt(request.target),
                        .target_windowId = self.window.subwindows.windowFor(mid_point),
                        .evt = .{
                            .text = .{
                                .txt = @constCast(text_value), // TODO: Not sure proper way to do this?
                                .selected = false,
                            },
                        },
                    };
                    self.events.append(self.window.gpa, text_evt) catch @panic("TODO");
                }
            },
            else => {},
        }
    }
    if (self.action_requests.items.len > 0) {
        self.action_requests.clearAndFree(self.window.gpa);
        dvui.refresh(self.window, @src(), null);
    }
}

fn nodesReset(self: *AccessKit) void {
    self.nodes.clearAndFree(self.window.gpa);

    // add generic root node
    self.root = nodeNew(Role.GENERIC_CONTAINER.asU8()) orelse @panic("null");
    self.nodes.put(self.window.gpa, .zero, self.root) catch @panic("TODO");
}

/// Must be called at the end of each frame.
/// Pushes any nodes created during the frame to the accesskit tree.
pub fn pushUpdates(self: *AccessKit) void {
    if (!self.active) {
        return;
    }
    self.mutex.lock();
    defer self.mutex.unlock();

    // Take any actions from this frame and create events for them.
    // Created events will not be processed until the start of the next frame.
    self.processActions();

    // TODO: Windows-specific
    if (builtin.os.tag == .windows) {
        const queued_events = c.accesskit_windows_subclassing_adapter_update_if_active(self.adapter, frameTreeUpdate, self);
        if (queued_events) |events| {
            c.accesskit_windows_queued_events_raise(events);
        }
    } else if (builtin.os.tag.isDarwin()) {
        const queued_events = c.accesskit_macos_subclassing_adapter_update_if_active(self.adapter, frameTreeUpdate, self);
        if (queued_events) |events| {
            c.accesskit_macos_queued_events_raise(events);
        }
    }

    self.nodesReset();
}

pub fn deinit(self: *AccessKit) void {
    if (!dvui.accesskit_enabled) return;

    self.mutex.lock();
    defer self.mutex.unlock();

    self.action_requests.clearAndFree(self.window.gpa);
    self.events.clearAndFree(self.window.gpa);
    self.nodes.clearAndFree(self.window.gpa);
    if (builtin.os.tag == .windows)
        c.accesskit_windows_subclassing_adapter_free(self.adapter)
    else if (builtin.os.tag.isDarwin())
        c.accesskit_macos_subclassing_adapter_free(self.adapter);
}

/// Pushes all the nodes created during the current frame to AccessKit
/// Called once per frame (if accessibility is initialized)
/// Note: This callback can occur on a non-gui thread.
fn frameTreeUpdate(instance: ?*anyopaque) callconv(.c) ?*TreeUpdate {
    var self: *AccessKit = @ptrCast(@alignCast(instance));

    const tree = treeNew(0) orelse @panic("null");
    const result = treeUpdateWithCapacityAndFocus(self.nodes.count(), 0);
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

    const root = nodeNew(Role.GENERIC_CONTAINER.asU8()) orelse @panic("null");
    const tree = treeNew(0) orelse @panic("null");
    const result = treeUpdateWithCapacityAndFocus(1, 0);
    treeUpdateSetTree(result, tree);
    treeUpdatePushNode(result, 0, root);
    self.active = true;

    self.nodesReset();

    // Refresh so that the full tree is sent next frame.
    dvui.refresh(self.window, @src(), null);
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

    self.action_requests.append(self.window.gpa, request.?.*) catch @panic("TODO");
    dvui.refresh(self.window, @src(), null);
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
pub const Role = enum(u8) {
    pub fn asU8(self: Role) u8 {
        return @intFromEnum(self);
    }

    CELL = c.ACCESSKIT_ROLE_CELL,
    LABEL = c.ACCESSKIT_ROLE_LABEL,
    IMAGE = c.ACCESSKIT_ROLE_IMAGE,
    LINK = c.ACCESSKIT_ROLE_LINK,
    ROW = c.ACCESSKIT_ROLE_ROW,
    LIST_ITEM = c.ACCESSKIT_ROLE_LIST_ITEM,
    LIST_MARKER = c.ACCESSKIT_ROLE_LIST_MARKER,
    TREE_ITEM = c.ACCESSKIT_ROLE_TREE_ITEM,
    LIST_BOX_OPTION = c.ACCESSKIT_ROLE_LIST_BOX_OPTION,
    MENU_ITEM = c.ACCESSKIT_ROLE_MENU_ITEM,
    MENU_LIST_OPTION = c.ACCESSKIT_ROLE_MENU_LIST_OPTION,
    PARAGRAPH = c.ACCESSKIT_ROLE_PARAGRAPH,
    GENERIC_CONTAINER = c.ACCESSKIT_ROLE_GENERIC_CONTAINER,
    CHECK_BOX = c.ACCESSKIT_ROLE_CHECK_BOX,
    RADIO_BUTTON = c.ACCESSKIT_ROLE_RADIO_BUTTON,
    TEXT_INPUT = c.ACCESSKIT_ROLE_TEXT_INPUT,
    BUTTON = c.ACCESSKIT_ROLE_BUTTON,
    DEFAULT_BUTTON = c.ACCESSKIT_ROLE_DEFAULT_BUTTON,
    PANE = c.ACCESSKIT_ROLE_PANE,
    ROW_HEADER = c.ACCESSKIT_ROLE_ROW_HEADER,
    COLUMN_HEADER = c.ACCESSKIT_ROLE_COLUMN_HEADER,
    ROW_GROUP = c.ACCESSKIT_ROLE_ROW_GROUP,
    LIST = c.ACCESSKIT_ROLE_LIST,
    TABLE = c.ACCESSKIT_ROLE_TABLE,
    LAYOUT_TABLE_CELL = c.ACCESSKIT_ROLE_LAYOUT_TABLE_CELL,
    LAYOUT_TABLE_ROW = c.ACCESSKIT_ROLE_LAYOUT_TABLE_ROW,
    LAYOUT_TABLE = c.ACCESSKIT_ROLE_LAYOUT_TABLE,
    SWITCH = c.ACCESSKIT_ROLE_SWITCH,
    MENU = c.ACCESSKIT_ROLE_MENU,
    MULTILINE_TEXT_INPUT = c.ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT,
    SEARCH_INPUT = c.ACCESSKIT_ROLE_SEARCH_INPUT,
    DATE_INPUT = c.ACCESSKIT_ROLE_DATE_INPUT,
    DATE_TIME_INPUT = c.ACCESSKIT_ROLE_DATE_TIME_INPUT,
    WEEK_INPUT = c.ACCESSKIT_ROLE_WEEK_INPUT,
    MONTH_INPUT = c.ACCESSKIT_ROLE_MONTH_INPUT,
    TIME_INPUT = c.ACCESSKIT_ROLE_TIME_INPUT,
    EMAIL_INPUT = c.ACCESSKIT_ROLE_EMAIL_INPUT,
    NUMBER_INPUT = c.ACCESSKIT_ROLE_NUMBER_INPUT,
    PASSWORD_INPUT = c.ACCESSKIT_ROLE_PASSWORD_INPUT,
    PHONE_NUMBER_INPUT = c.ACCESSKIT_ROLE_PHONE_NUMBER_INPUT,
    URL_INPUT = c.ACCESSKIT_ROLE_URL_INPUT,
    ABBR = c.ACCESSKIT_ROLE_ABBR,
    ALERT = c.ACCESSKIT_ROLE_ALERT,
    ALERT_DIALOG = c.ACCESSKIT_ROLE_ALERT_DIALOG,
    APPLICATION = c.ACCESSKIT_ROLE_APPLICATION,
    ARTICLE = c.ACCESSKIT_ROLE_ARTICLE,
    AUDIO = c.ACCESSKIT_ROLE_AUDIO,
    BANNER = c.ACCESSKIT_ROLE_BANNER,
    BLOCKQUOTE = c.ACCESSKIT_ROLE_BLOCKQUOTE,
    CANVAS = c.ACCESSKIT_ROLE_CANVAS,
    CAPTION = c.ACCESSKIT_ROLE_CAPTION,
    CARET = c.ACCESSKIT_ROLE_CARET,
    CODE = c.ACCESSKIT_ROLE_CODE,
    COLOR_WELL = c.ACCESSKIT_ROLE_COLOR_WELL,
    COMBO_BOX = c.ACCESSKIT_ROLE_COMBO_BOX,
    EDITABLE_COMBO_BOX = c.ACCESSKIT_ROLE_EDITABLE_COMBO_BOX,
    COMPLEMENTARY = c.ACCESSKIT_ROLE_COMPLEMENTARY,
    COMMENT = c.ACCESSKIT_ROLE_COMMENT,
    CONTENT_DELETION = c.ACCESSKIT_ROLE_CONTENT_DELETION,
    CONTENT_INSERTION = c.ACCESSKIT_ROLE_CONTENT_INSERTION,
    CONTENT_INFO = c.ACCESSKIT_ROLE_CONTENT_INFO,
    DEFINITION = c.ACCESSKIT_ROLE_DEFINITION,
    DESCRIPTION_LIST = c.ACCESSKIT_ROLE_DESCRIPTION_LIST,
    DESCRIPTION_LIST_DETAIL = c.ACCESSKIT_ROLE_DESCRIPTION_LIST_DETAIL,
    DESCRIPTION_LIST_TERM = c.ACCESSKIT_ROLE_DESCRIPTION_LIST_TERM,
    DETAILS = c.ACCESSKIT_ROLE_DETAILS,
    DIALOG = c.ACCESSKIT_ROLE_DIALOG,
    DIRECTORY = c.ACCESSKIT_ROLE_DIRECTORY,
    DISCLOSURE_TRIANGLE = c.ACCESSKIT_ROLE_DISCLOSURE_TRIANGLE,
    DOCUMENT = c.ACCESSKIT_ROLE_DOCUMENT,
    EMBEDDED_OBJECT = c.ACCESSKIT_ROLE_EMBEDDED_OBJECT,
    EMPHASIS = c.ACCESSKIT_ROLE_EMPHASIS,
    FEED = c.ACCESSKIT_ROLE_FEED,
    FIGURE_CAPTION = c.ACCESSKIT_ROLE_FIGURE_CAPTION,
    FIGURE = c.ACCESSKIT_ROLE_FIGURE,
    FOOTER = c.ACCESSKIT_ROLE_FOOTER,
    FOOTER_AS_NON_LANDMARK = c.ACCESSKIT_ROLE_FOOTER_AS_NON_LANDMARK,
    FORM = c.ACCESSKIT_ROLE_FORM,
    GRID = c.ACCESSKIT_ROLE_GRID,
    GROUP = c.ACCESSKIT_ROLE_GROUP,
    HEADER = c.ACCESSKIT_ROLE_HEADER,
    HEADER_AS_NON_LANDMARK = c.ACCESSKIT_ROLE_HEADER_AS_NON_LANDMARK,
    HEADING = c.ACCESSKIT_ROLE_HEADING,
    IFRAME = c.ACCESSKIT_ROLE_IFRAME,
    IFRAME_PRESENTATIONAL = c.ACCESSKIT_ROLE_IFRAME_PRESENTATIONAL,
    IME_CANDIDATE = c.ACCESSKIT_ROLE_IME_CANDIDATE,
    KEYBOARD = c.ACCESSKIT_ROLE_KEYBOARD,
    LEGEND = c.ACCESSKIT_ROLE_LEGEND,
    LINE_BREAK = c.ACCESSKIT_ROLE_LINE_BREAK,
    LIST_BOX = c.ACCESSKIT_ROLE_LIST_BOX,
    LOG = c.ACCESSKIT_ROLE_LOG,
    MAIN = c.ACCESSKIT_ROLE_MAIN,
    MARK = c.ACCESSKIT_ROLE_MARK,
    MARQUEE = c.ACCESSKIT_ROLE_MARQUEE,
    MATH = c.ACCESSKIT_ROLE_MATH,
    MENU_BAR = c.ACCESSKIT_ROLE_MENU_BAR,
    MENU_ITEM_CHECK_BOX = c.ACCESSKIT_ROLE_MENU_ITEM_CHECK_BOX,
    MENU_ITEM_RADIO = c.ACCESSKIT_ROLE_MENU_ITEM_RADIO,
    MENU_LIST_POPUP = c.ACCESSKIT_ROLE_MENU_LIST_POPUP,
    METER = c.ACCESSKIT_ROLE_METER,
    NAVIGATION = c.ACCESSKIT_ROLE_NAVIGATION,
    NOTE = c.ACCESSKIT_ROLE_NOTE,
    PLUGIN_OBJECT = c.ACCESSKIT_ROLE_PLUGIN_OBJECT,
    PORTAL = c.ACCESSKIT_ROLE_PORTAL,
    PRE = c.ACCESSKIT_ROLE_PRE,
    PROGRESS_INDICATOR = c.ACCESSKIT_ROLE_PROGRESS_INDICATOR,
    RADIO_GROUP = c.ACCESSKIT_ROLE_RADIO_GROUP,
    REGION = c.ACCESSKIT_ROLE_REGION,
    ROOT_WEB_AREA = c.ACCESSKIT_ROLE_ROOT_WEB_AREA,
    RUBY = c.ACCESSKIT_ROLE_RUBY,
    RUBY_ANNOTATION = c.ACCESSKIT_ROLE_RUBY_ANNOTATION,
    SCROLL_BAR = c.ACCESSKIT_ROLE_SCROLL_BAR,
    SCROLL_VIEW = c.ACCESSKIT_ROLE_SCROLL_VIEW,
    SEARCH = c.ACCESSKIT_ROLE_SEARCH,
    SECTION = c.ACCESSKIT_ROLE_SECTION,
    SLIDER = c.ACCESSKIT_ROLE_SLIDER,
    SPIN_BUTTON = c.ACCESSKIT_ROLE_SPIN_BUTTON,
    SPLITTER = c.ACCESSKIT_ROLE_SPLITTER,
    STATUS = c.ACCESSKIT_ROLE_STATUS,
    STRONG = c.ACCESSKIT_ROLE_STRONG,
    SUGGESTION = c.ACCESSKIT_ROLE_SUGGESTION,
    SVG_ROOT = c.ACCESSKIT_ROLE_SVG_ROOT,
    TAB = c.ACCESSKIT_ROLE_TAB,
    TAB_LIST = c.ACCESSKIT_ROLE_TAB_LIST,
    TAB_PANEL = c.ACCESSKIT_ROLE_TAB_PANEL,
    TERM = c.ACCESSKIT_ROLE_TERM,
    TIME = c.ACCESSKIT_ROLE_TIME,
    TIMER = c.ACCESSKIT_ROLE_TIMER,
    TITLE_BAR = c.ACCESSKIT_ROLE_TITLE_BAR,
    TOOLBAR = c.ACCESSKIT_ROLE_TOOLBAR,
    TOOLTIP = c.ACCESSKIT_ROLE_TOOLTIP,
    TREE = c.ACCESSKIT_ROLE_TREE,
    TREE_GRID = c.ACCESSKIT_ROLE_TREE_GRID,
    VIDEO = c.ACCESSKIT_ROLE_VIDEO,
    WEB_VIEW = c.ACCESSKIT_ROLE_WEB_VIEW,
    WINDOW = c.ACCESSKIT_ROLE_WINDOW,
    PDF_ACTIONABLE_HIGHLIGHT = c.ACCESSKIT_ROLE_PDF_ACTIONABLE_HIGHLIGHT,
    PDF_ROOT = c.ACCESSKIT_ROLE_PDF_ROOT,
    GRAPHICS_DOCUMENT = c.ACCESSKIT_ROLE_GRAPHICS_DOCUMENT,
    GRAPHICS_OBJECT = c.ACCESSKIT_ROLE_GRAPHICS_OBJECT,
    GRAPHICS_SYMBOL = c.ACCESSKIT_ROLE_GRAPHICS_SYMBOL,
    DOC_ABSTRACT = c.ACCESSKIT_ROLE_DOC_ABSTRACT,
    DOC_ACKNOWLEDGEMENTS = c.ACCESSKIT_ROLE_DOC_ACKNOWLEDGEMENTS,
    DOC_AFTERWORD = c.ACCESSKIT_ROLE_DOC_AFTERWORD,
    DOC_APPENDIX = c.ACCESSKIT_ROLE_DOC_APPENDIX,
    DOC_BACK_LINK = c.ACCESSKIT_ROLE_DOC_BACK_LINK,
    DOC_BIBLIO_ENTRY = c.ACCESSKIT_ROLE_DOC_BIBLIO_ENTRY,
    DOC_BIBLIOGRAPHY = c.ACCESSKIT_ROLE_DOC_BIBLIOGRAPHY,
    DOC_BIBLIO_REF = c.ACCESSKIT_ROLE_DOC_BIBLIO_REF,
    DOC_CHAPTER = c.ACCESSKIT_ROLE_DOC_CHAPTER,
    DOC_COLOPHON = c.ACCESSKIT_ROLE_DOC_COLOPHON,
    DOC_CONCLUSION = c.ACCESSKIT_ROLE_DOC_CONCLUSION,
    DOC_COVER = c.ACCESSKIT_ROLE_DOC_COVER,
    DOC_CREDIT = c.ACCESSKIT_ROLE_DOC_CREDIT,
    DOC_CREDITS = c.ACCESSKIT_ROLE_DOC_CREDITS,
    DOC_DEDICATION = c.ACCESSKIT_ROLE_DOC_DEDICATION,
    DOC_ENDNOTE = c.ACCESSKIT_ROLE_DOC_ENDNOTE,
    DOC_ENDNOTES = c.ACCESSKIT_ROLE_DOC_ENDNOTES,
    DOC_EPIGRAPH = c.ACCESSKIT_ROLE_DOC_EPIGRAPH,
    DOC_EPILOGUE = c.ACCESSKIT_ROLE_DOC_EPILOGUE,
    DOC_ERRATA = c.ACCESSKIT_ROLE_DOC_ERRATA,
    DOC_EXAMPLE = c.ACCESSKIT_ROLE_DOC_EXAMPLE,
    DOC_FOOTNOTE = c.ACCESSKIT_ROLE_DOC_FOOTNOTE,
    DOC_FOREWORD = c.ACCESSKIT_ROLE_DOC_FOREWORD,
    DOC_GLOSSARY = c.ACCESSKIT_ROLE_DOC_GLOSSARY,
    DOC_GLOSS_REF = c.ACCESSKIT_ROLE_DOC_GLOSS_REF,
    DOC_INDEX = c.ACCESSKIT_ROLE_DOC_INDEX,
    DOC_INTRODUCTION = c.ACCESSKIT_ROLE_DOC_INTRODUCTION,
    DOC_NOTE_REF = c.ACCESSKIT_ROLE_DOC_NOTE_REF,
    DOC_NOTICE = c.ACCESSKIT_ROLE_DOC_NOTICE,
    DOC_PAGE_BREAK = c.ACCESSKIT_ROLE_DOC_PAGE_BREAK,
    DOC_PAGE_FOOTER = c.ACCESSKIT_ROLE_DOC_PAGE_FOOTER,
    DOC_PAGE_HEADER = c.ACCESSKIT_ROLE_DOC_PAGE_HEADER,
    DOC_PAGE_LIST = c.ACCESSKIT_ROLE_DOC_PAGE_LIST,
    DOC_PART = c.ACCESSKIT_ROLE_DOC_PART,
    DOC_PREFACE = c.ACCESSKIT_ROLE_DOC_PREFACE,
    DOC_PROLOGUE = c.ACCESSKIT_ROLE_DOC_PROLOGUE,
    DOC_PULLQUOTE = c.ACCESSKIT_ROLE_DOC_PULLQUOTE,
    DOC_QNA = c.ACCESSKIT_ROLE_DOC_QNA,
    DOC_SUBTITLE = c.ACCESSKIT_ROLE_DOC_SUBTITLE,
    DOC_TIP = c.ACCESSKIT_ROLE_DOC_TIP,
    DOC_TOC = c.ACCESSKIT_ROLE_DOC_TOC,
    LIST_GRID = c.ACCESSKIT_ROLE_LIST_GRID,
    TERMINAL = c.ACCESSKIT_ROLE_TERMINAL,
};

pub const Action = struct {
    pub const CLICK = c.ACCESSKIT_ACTION_CLICK;
    pub const FOCUS = c.ACCESSKIT_ACTION_FOCUS;
    pub const BLUR = c.ACCESSKIT_ACTION_BLUR;
    pub const COLLAPSE = c.ACCESSKIT_ACTION_COLLAPSE;
    pub const EXPAND = c.ACCESSKIT_ACTION_EXPAND;
    pub const CUSTOM_ACTION = c.ACCESSKIT_ACTION_CUSTOM_ACTION;
    pub const DECREMENT = c.ACCESSKIT_ACTION_DECREMENT;
    pub const INCREMENT = c.ACCESSKIT_ACTION_INCREMENT;
    pub const HIDE_TOOLTIP = c.ACCESSKIT_ACTION_HIDE_TOOLTIP;
    pub const SHOW_TOOLTIP = c.ACCESSKIT_ACTION_SHOW_TOOLTIP;
    pub const REPLACE_SELECTED_TEXT = c.ACCESSKIT_ACTION_REPLACE_SELECTED_TEXT;
    pub const SCROLL_DOWN = c.ACCESSKIT_ACTION_SCROLL_DOWN;
    pub const SCROLL_LEFT = c.ACCESSKIT_ACTION_SCROLL_LEFT;
    pub const SCROLL_RIGHT = c.ACCESSKIT_ACTION_SCROLL_RIGHT;
    pub const SCROLL_UP = c.ACCESSKIT_ACTION_SCROLL_UP;
    pub const SCROLL_INTO_VIEW = c.ACCESSKIT_ACTION_SCROLL_INTO_VIEW;
    pub const SCROLL_TO_POINT = c.ACCESSKIT_ACTION_SCROLL_TO_POINT;
    pub const SET_SCROLL_OFFSET = c.ACCESSKIT_ACTION_SET_SCROLL_OFFSET;
    pub const SET_TEXT_SELECTION = c.ACCESSKIT_ACTION_SET_TEXT_SELECTION;
    pub const SET_SEQUENTIAL_FOCUS_NAVIGATION_STARTING_POINT = c.ACCESSKIT_ACTION_SET_SEQUENTIAL_FOCUS_NAVIGATION_STARTING_POINT;
    pub const SET_VALUE = c.ACCESSKIT_ACTION_SET_VALUE;
    pub const SHOW_CONTEXT_MENU = c.ACCESSKIT_ACTION_SHOW_CONTEXT_MENU;
    pub const DATA_CUSTOM_ACTION = c.ACCESSKIT_ACTION_DATA_CUSTOM_ACTION;
    pub const DATA_VALUE = c.ACCESSKIT_ACTION_DATA_VALUE;
    pub const DATA_NUMERIC_VALUE = c.ACCESSKIT_ACTION_DATA_NUMERIC_VALUE;
    pub const DATA_SCROLL_UNIT = c.ACCESSKIT_ACTION_DATA_SCROLL_UNIT;
    pub const DATA_SCROLL_HINT = c.ACCESSKIT_ACTION_DATA_SCROLL_HINT;
    pub const DATA_SCROLL_TO_POINT = c.ACCESSKIT_ACTION_DATA_SCROLL_TO_POINT;
    pub const DATA_SET_SCROLL_OFFSET = c.ACCESSKIT_ACTION_DATA_SET_SCROLL_OFFSET;
    pub const DATA_SET_TEXT_SELECTION = c.ACCESSKIT_ACTION_DATA_SET_TEXT_SELECTION;
};

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
// Use the nodeCreate method instead.
const nodeNew = c.accesskit_node_new;
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
pub const unixAdapterNew = c.accesskit_unix_adapter_new;
pub const unixAdapterFree = c.accesskit_unix_adapter_free;
pub const unixAdapterSetRootWindowBounds = c.accesskit_unix_adapter_set_root_window_bounds;
pub const unixAdapterUpdateIfActive = c.accesskit_unix_adapter_update_if_active;
pub const unixAdapterUpdateWindowFocusState = c.accesskit_unix_adapter_update_window_focus_state;

// Action is overridden above
//pub const Action = ak.accesskit_action;
pub const AriaCurrent = c.accesskit_aria_current;
pub const AutoComplete = c.accesskit_auto_complete;
pub const HasPopup = c.accesskit_has_popup;
pub const Invalid = c.accesskit_invalid;
pub const ListStyle = c.accesskit_list_style;
pub const Live = c.accesskit_live;
pub const Orientation = c.accesskit_orientation;
// Role is overridden above
//pub const Role = ak.accesskit_role;
pub const ScrollHint = c.accesskit_scroll_hint;
pub const ScrollUnit = c.accesskit_scroll_unit;
pub const SortDirection = c.accesskit_sort_direction;
pub const TextAlign = c.accesskit_text_align;
pub const TextDecoration = c.accesskit_text_decoration;
pub const TextDirection = c.accesskit_text_direction;
pub const Toggled = c.accesskit_toggled;
pub const VerticalOffset = c.accesskit_vertical_offset;
pub const MacosAdapter = c.accesskit_macos_adapter;
pub const MacosQueuedEvents = c.accesskit_macos_queued_events;
pub const MacosSubclassingAdapter = c.accesskit_macos_subclassing_adapter;
pub const Node = c.accesskit_node;
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
pub const ActionRequest = c.accesskit_action_request;
pub const Vec2 = c.accesskit_vec2;
pub const Size = c.accesskit_size;
pub const OptLresult = c.accesskit_opt_lresult;

const std = @import("std");
