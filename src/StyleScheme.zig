//! CSS-like rule system for styling system for dvui widgets.
//!
//! Rules are matched by widget kind and/or class names, sorted by specificity
//! (lowest to highest: universal → element → class → element+class), then
//! merged in order so more-specific rules win.
//!
//! ## Example
//! ```zig
//! scheme.addStyle("button.danger", .{ .color_fill = dvui.Color.red });
//! scheme.addStyle("button",        .{ .corner_radius = .{ .x = 4 } });
//! ```

const std = @import("std");
const dvui = @import("dvui.zig");

const Options = dvui.Options;
const IconTheme = dvui.IconTheme;
const StyleScheme = @This();

/// Raw rules keyed by the selector string (e.g. "button", ".danger", "button.danger").
style_rules: std.StringHashMapUnmanaged(Options) = .empty,

/// Cache of already-computed merged Options per widget ID.
/// Invalidated externally via the TrackingAutoHashMap machinery.
styles_raw: dvui.TrackingAutoHashMap(dvui.Id, FatStyleData, .get_and_put, void) = .{},

/// Icon theme used by dvui widgets.
icon_theme: IconTheme = dvui.entypo,

/// Data attached to a widget that rules are matched against.
/// Each widget defines this by passing it to the `WidgetData.init` function
pub const WidgetIdData = struct {
    /// e.g. "button", "label"
    widget_kind: []const u8,
    /// e.g. &.{ "danger", "sm" }
    classes: [][]const u8 = &.{},
};

/// A parsed selector: optional element name + zero or more class names.
/// A Selector of no information is considered global.
/// Widget names and classes can have any
const Selector = struct {
    widget: ?[]const u8,
    classes: std.ArrayListUnmanaged([]const u8),

    pub fn parse(gpa: std.mem.Allocator, src: []const u8) !Selector {
        var self = Selector{ .widget = null, .classes = .empty };
        var seg_start: usize = 0;
        var first_seg = true;

        for (src, 0..) |c, i| {
            const at_end = i == src.len - 1;
            if (c == '.' or at_end) {
                const end = if (at_end and c != '.') i + 1 else i;
                const token = src[seg_start..end];
                if (token.len > 0) {
                    if (first_seg) {
                        self.widget = token;
                    } else {
                        try self.classes.append(gpa, token);
                    }
                }
                seg_start = i + 1;
                first_seg = false;
            }
        }
        return self;
    }

    pub fn deinit(self: *Selector, gpa: std.mem.Allocator) void {
        self.classes.deinit(gpa);
    }

    /// The returned type of this function is called the grade of appliance
    /// Returns:
    ///     - 0 if this selector doesn't apply
    ///     - 1 if this selector is global (applies, no widget name or classlist)
    ///     - 2 if this selector is a generic element selector with no classes that applies (widget name only)
    ///     - 3 if this selector is a non-element class selector that applies (classlist only)
    ///     - 4 if this selector is a specific class-element selector that applies (widget name + classlist)
    pub fn applies(self: *Selector, id: WidgetIdData) u3 {
        if (self.widget == null and self.classes.items.len == 0) return 1;
        if (self.widget != null and self.widget == id.widget_kind and self.classes.items.len == 0) return 2;
        if (self.widget == null and self.classes.items.len != 0) {
            for (self.classes.items) |i| {
                for (id.classes) |c| {
                    if (i != c) return 0;
                }
            }
            return 3;
        }
        if (self.widget != null and self.classes.items.len != 0 and std.mem.eql(u8, self.widget, id.widget_kind)) {
            for (self.classes.items) |i| {
                for (id.classes) |c| {
                    if (i != c) return 0;
                }
            }
            return 4;
        }
        return 0;
    }
};

/// This is used for when a new style is added
pub const FatStyleData = struct {
    id: WidgetIdData,
    style: Options,
};

/// Apply matching style rules to `data.options`, using the cache when possible.
pub fn applyStyles(self: *StyleScheme, data: *dvui.WidgetData, extra_opts: Options) void {
    if (self.styles_raw.get(data.id)) |d| data.options = d.style.override(extra_opts);
    const opts = self.genOpts(data.style_id);
    data.options = opts.override(extra_opts);
    self.styles_raw.put(data.id, FatStyleData{ .id = data.style_id, .style = opts });
}

pub fn genOpts(self: *StyleScheme, id: WidgetIdData) Options {
    var opts = Options{};
    var iter = self.styles_raw.iterator();
    while (iter.next()) |kv| {
        const sel = Selector.parse(kv.key_ptr.*) catch |e|
            @panic(std.fmt.allocPrint(dvui.currentWindow().gpa, "Failed to parse class \"{s}\": {s}", .{ kv.key_ptr.*, @errorName(e) }));
        for (1..4) |i| {
            if (sel.applies(id) != i) continue;
            opts.override(kv.value_ptr.*);
            break;
        }
    }
    return opts;
}

pub fn syncCache(self: *StyleScheme) void {
    var iter = self.styles_raw.iterator();
    while (iter.next()) |kv| {
        kv.value_ptr.style = genOpts(kv.value_ptr.id);
    }
}

/// Add or merge a style rule.
/// `selector` follows CSS-like syntax: "element", ".class", "element.class".
/// refreshes all internal cache
pub fn addStyle(self: *StyleScheme, selector: []const u8, opts: Options) void {
    const gpa = dvui.currentWindow().gpa;
    if (self.style_rules.getPtr(selector)) |existing| {
        existing.* = existing.override(opts);
        return;
    }
    self.style_rules.put(gpa, selector, opts) catch @panic("OOM");
    self.syncCache();
}

pub fn deinit(self: *StyleScheme) void {
    self.style_rules.deinit(dvui.currentWindow().gpa);
}
