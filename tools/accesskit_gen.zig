//! Creates Zig API mappings from "accesskit.h"
//! These should be pasted at the end of AccessKit.zig
//! Copy the latest accesskit.h file into the directory
//! (or specify the include directory with -I below)
//! Build with `zig build-exe accesskit_gen.zig -I. -lc`
const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cDefine("__APPLE__", {});
    @cDefine("__linux__", {});
    if (builtin.os.tag == .windows)
        @cDefine("_WIN32", {});
    @cInclude("accesskit.h");
});

// Replaces any clashes with zig keywords.
var replacements: std.StaticStringMap([]const u8) = .initComptime(&.{
    .{ "true", "ak_true" },
    .{ "false", "ak_false" },
    .{ "inline", "ak_inline" },
    .{ "switch", "ak_switch" },
});

// Any structs that are conditional on whether accesskit is enabled.
var conditional_on_enabled: std.StaticStringMap(void) = .initComptime(&.{
    .{ "accesskit_node", {} },
    .{ "accesskit_action_request", {} },
});

// Any type decls that are mistakenly picked up as functions and are displayed in wrong case
// We can only automatically pick up struct types as their decl starts with struct_
var type_decls: std.StaticStringMap(void) = .initComptime(&.{
    .{ "accesskit_node_id", {} },
    .{ "accesskit_action_data_Tag", {} },
    .{ "accesskit_tree_update_factory_userdata", {} },
    .{ "accesskit_tree_update_factory", {} },
    .{ "accesskit_action_handler_callback", {} },
    .{ "accesskit_activation_handler_callback", {} },
    .{ "accesskit_deactivation_handler_callback", {} },
});

const DeclGroup = enum {
    // Enums that are converted to Zig enums
    enums,
    // Enums that are converted to Zig structs
    enums_as_structs,
    // All other decls
    others,
    // Decls that will not be imported
    ignore,
};

const DeclPattern = struct {
    patterns: []const []const u8,
    matches: std.ArrayList(struct { pattern: []const u8, decl: []const u8 }),

    pub fn init(patterns: []const []const u8) DeclPattern {
        return .{
            .patterns = patterns,
            .matches = .empty,
        };
    }
};

// string patterns to match and associated matches
var decl_patterns: std.AutoArrayHashMapUnmanaged(DeclGroup, DeclPattern) = .empty;

// The order in which groups are matched.
const pattern_order: [4]DeclGroup = .{
    .ignore,
    .enums,
    .enums_as_structs,
    .others,
};

// Exclude aliases for decls that are already processed. (e.g. a struct and the typedef for the struct)
var exclude_decl: std.StringHashMapUnmanaged(void) = .empty;

// Roles need to be output twice. Save their decls here.
var role_decls: std.ArrayList([]const u8) = .empty;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_allocator.allocator();
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writerStreaming(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {}; // Don't forget to flush!
    var stderr_writer = std.fs.File.stderr().writerStreaming(&.{});
    const stderr = &stderr_writer.interface;

    if (builtin.os.tag != .windows) {
        try stderr.print("WARNING: Windows-specific declarations cannot be generated on non-Windows platforms. Please add them by hand.\n", .{});
    }

    // Accesskit role is imported as an enum rather than a struct.
    try decl_patterns.put(gpa, .enums, .init(&.{"ACCESSKIT_ROLE"}));

    // Put all other enums here.
    try decl_patterns.put(gpa, .enums_as_structs, .init(&.{
        "ACCESSKIT_ACTION_DATA", // ACTION_DATA must be before ACTION
        "ACCESSKIT_ACTION",
        "ACCESSKIT_ARIA_CURRENT",
        "ACCESSKIT_AUTO_COMPLETE",
        "ACCESSKIT_HAS_POPUP",
        "ACCESSKIT_INVALID",
        "ACCESSKIT_LIST_STYLE",
        "ACCESSKIT_LIVE",
        "ACCESSKIT_ORIENTATION",
        "ACCESSKIT_SCROLL_HINT",
        "ACCESSKIT_SCROLL_UNIT",
        "ACCESSKIT_SORT_DIRECTION",
        "ACCESSKIT_TEXT_ALIGN",
        "ACCESSKIT_TEXT_DECORATION",
        "ACCESSKIT_TEXT_DIRECTION",
        "ACCESSKIT_TOGGLED",
        "ACCESSKIT_VERTICAL_OFFSET",
    }));

    try decl_patterns.put(gpa, .others, .init(&.{"accesskit_"}));
    try decl_patterns.put(gpa, .ignore, .init(&.{"enum_accesskit_"}));

    // Go through each pattern in order and collect any decls that match
    for (std.meta.declarations(c)) |decl| {
        if (std.mem.containsAtLeast(u8, decl.name, 1, "accesskit") or
            std.mem.containsAtLeast(u8, decl.name, 1, "ACCESSKIT"))
        {
            searching: {
                for (&pattern_order) |group_type| {
                    const entry = decl_patterns.getEntry(group_type) orelse unreachable;

                    for (entry.value_ptr.patterns) |pattern| {
                        if (std.mem.containsAtLeast(u8, decl.name, 1, pattern)) {
                            try entry.value_ptr.matches.append(gpa, .{ .pattern = pattern, .decl = decl.name });
                            break :searching; // Only matches first pattern. Put more specific patterns first.
                        }
                    }
                }
            }
        }
    }

    // Output each match
    {
        try stdout.print("// Enums \n", .{});

        var current_enum: []const u8 = "";
        var print_closing_brace = false;
        for (decl_patterns.getPtr(.enums).?.matches.items) |match| {
            const idents = splitIdentifier(match.pattern, match.decl);
            if (!std.mem.eql(u8, current_enum, idents.first)) {
                if (print_closing_brace) {
                    try stdout.print("}};\n\n", .{});
                } else {
                    print_closing_brace = true;
                }
                current_enum = idents.first;
                const pascalled_identifier = if (std.mem.eql(u8, current_enum, "ROLE"))
                    "RoleAccessKit"
                else
                    snakeToPascalCase(gpa, current_enum);

                try stdout.print("pub const {s} = enum(u8) {{\n", .{pascalled_identifier});
                try stdout.print(
                    \\    pub fn asU8(self: {s}) u8 {{
                    \\        return @intFromEnum(self);
                    \\    }}
                    \\
                    \\    none = 255,
                    \\
                , .{pascalled_identifier});
                try role_decls.append(gpa, "none");
                var str_builder: std.Io.Writer.Allocating = .init(gpa);
                try str_builder.writer.print("accesskit_{s}", .{lowerCase(gpa, idents.first)});
                try exclude_decl.put(gpa, try str_builder.toOwnedSlice(), {});
            }
            const zig_identifier = doReplace(lowerCase(gpa, idents.remaining));
            try stdout.print("    {s} = c.{s},\n", .{ zig_identifier, match.decl });

            // A non-libc version of Role also needs to be created.
            if (std.mem.eql(u8, current_enum, "ROLE")) {
                try role_decls.append(gpa, zig_identifier);
            }
        }
        try stdout.print("}};\n\n", .{});
    }

    {
        try stdout.print("// Enum Structs \n", .{});

        var current_enum: []const u8 = "";
        var print_closing_brace = false;
        for (decl_patterns.getPtr(.enums_as_structs).?.matches.items) |match| {
            const idents = splitIdentifier(match.pattern, match.decl);
            if (!std.mem.eql(u8, current_enum, idents.first)) {
                if (print_closing_brace) {
                    try stdout.print("}};\n\n", .{});
                } else {
                    print_closing_brace = true;
                }
                current_enum = idents.first;
                try stdout.print("pub const {s} = struct {{\n", .{snakeToPascalCase(gpa, current_enum)});

                var str_builder: std.Io.Writer.Allocating = .init(gpa);
                try str_builder.writer.print("accesskit_{s}", .{lowerCase(gpa, idents.first)});
                try exclude_decl.put(gpa, try str_builder.toOwnedSlice(), {});

                str_builder = .init(gpa);
                try str_builder.writer.print("struct_accesskit_{s}", .{lowerCase(gpa, idents.first)});
                try exclude_decl.put(gpa, try str_builder.toOwnedSlice(), {});
            }
            try stdout.print("    pub const {s} = c.{s};\n", .{ doReplace(lowerCase(gpa, idents.remaining)), match.decl });
        }
        try stdout.print("}};\n\n", .{});
    }

    {
        try stdout.print("// Mappings \n", .{});
        for (decl_patterns.getPtr(.others).?.matches.items) |match| {
            if (!exclude_decl.contains(match.decl)) {
                const starts_with_struct = std.mem.startsWith(u8, match.decl, "struct_");
                if (starts_with_struct or type_decls.has(match.decl)) {
                    const decl_str = if (starts_with_struct) match.decl[7..] else match.decl;
                    if (conditional_on_enabled.has(decl_str)) {
                        try stdout.print("pub const {s} = if (dvui.accesskit_enabled) c.{s} else struct {{}};\n", .{ snakeToPascalCase(gpa, stripAccesskitPrefix(decl_str)), decl_str });
                    } else {
                        try stdout.print("pub const {s} = c.{s};\n", .{ snakeToPascalCase(gpa, stripAccesskitPrefix(decl_str)), decl_str });
                    }
                    try exclude_decl.put(gpa, decl_str, {}); // Stop the typedef version of the decl being created as well.
                } else {
                    try stdout.print("pub const {s} = c.{s};\n", .{ snakeToCamelCase(gpa, stripAccesskitPrefix(match.decl)), match.decl });
                }
            }
        }
    }
    {
        try stdout.print("// Non libc Mappings \n", .{});
        try stdout.print("pub const RoleNoAccessKit = enum {{\n", .{});
        for (role_decls.items) |decl| {
            try stdout.print("    {s},\n", .{decl});
        }
        try stdout.print("}};\n", .{});
    }
}

fn stripAccesskitPrefix(str: []const u8) []const u8 {
    var idx = std.mem.indexOf(
        u8,
        str,
        "accesskit_",
    ) orelse std.mem.indexOf(
        u8,
        str,
        "ACCESSKIT_",
    ) orelse unreachable;
    idx += "accesskit_".len;
    std.debug.assert(str.len >= idx);
    return str[idx..];
}

fn splitIdentifier(pattern: []const u8, str: []const u8) struct { first: []const u8, remaining: []const u8 } {
    var idx = std.mem.indexOf(u8, str, pattern) orelse unreachable;
    idx += pattern.len;
    std.debug.assert(str.len > idx + 1);
    return .{ .first = stripAccesskitPrefix(str[0..idx]), .remaining = str[idx + 1 ..] };
}

fn snakeToMixedCase(gpa: std.mem.Allocator, str: []const u8, capitalize_first: bool) []const u8 {
    const out = gpa.alloc(u8, str.len) catch @panic("OOM");
    var out_idx: usize = 0;

    var capitalize: bool = capitalize_first;
    for (str) |ch| {
        switch (ch) {
            'A'...'Z' => |char| {
                out[out_idx] = if (capitalize) char else std.ascii.toLower(char);
                capitalize = false;
                out_idx += 1;
            },
            '0'...'9', 'a'...'z' => |char| {
                out[out_idx] = if (capitalize) std.ascii.toUpper(char) else char;
                capitalize = char >= '0' and char <= '9';
                out_idx += 1;
            },
            '_' => {
                capitalize = true;
                continue;
            },
            else => |char| {
                std.debug.print("\nunhandled identifier character: {c}\n", .{char});
                unreachable;
            },
        }
    }
    return out[0..out_idx];
}

fn snakeToCamelCase(gpa: std.mem.Allocator, str: []const u8) []const u8 {
    return snakeToMixedCase(gpa, str, false);
}

fn snakeToPascalCase(gpa: std.mem.Allocator, str: []const u8) []const u8 {
    return snakeToMixedCase(gpa, str, true);
}

fn upperCase(gpa: std.mem.Allocator, str: []const u8) []const u8 {
    const out = gpa.alloc(u8, str.len) catch @panic("OOM");
    return std.ascii.upperString(out, str);
}

fn lowerCase(gpa: std.mem.Allocator, str: []const u8) []const u8 {
    const out = gpa.alloc(u8, str.len) catch @panic("OOM");
    return std.ascii.lowerString(out, str);
}

fn doReplace(str: []const u8) []const u8 {
    return replacements.get(str) orelse str;
}
