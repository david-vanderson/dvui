const Role = AccessKit.Role;

role: ?Role = null,
labeled_by: ?dvui.Id = null,
label_for: ?dvui.Id = null,
label: ?[]const u8 = null,

const AccessibilityOptions = @This();

pub fn defaultRoleTo(opts: dvui.Options, default_role: AccessKit.Role) dvui.Options {
    if (opts.a11y) |a11y| {
        if (a11y.role == null) {
            var result = opts;
            result.a11y.?.role = default_role;
            return result;
        } else {
            return opts;
        }
    } else {
        var result = opts;
        result.a11y = .{ .role = default_role };
        return result;
    }
}

const AccessKit = dvui.AccessKit;
const dvui = @import("dvui.zig");
