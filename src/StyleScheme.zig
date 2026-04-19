/// A big struct to define how to style elements by default.
/// This is a quality of life feature to prevent repetition.
const std = @import("std");
const dvui = @import("dvui.zig");

const Options = dvui.Options;
const ButtonWidget = dvui.ButtonWidget;
const LabelWidget = dvui.LabelWidget;
const TextEntryWidget = dvui.TextEntryWidget;
const IconWidget = dvui.IconWidget;
const ScrollBarWidget = dvui.ScrollBarWidget;
const ContextWidget = dvui.ContextWidget;
const DropdownWidget = dvui.DropdownWidget;
const Window = dvui.Window;
const IconTheme = dvui.IconTheme;
const AnimationRunner = dvui.AnimationRunner;

button: Options = ButtonWidget.defaults,
text_entry: Options = TextEntryWidget.defaults,
label: Options = LabelWidget.defaults,
icon: Options = IconWidget.defaults,
scrollbar: Options = ScrollBarWidget.defaults,
context: Options = ContextWidget.defaults,
dropdown: Options = DropdownWidget.defaults,
animations: std.ArrayList(AnimationRunner) = .empty,
icon_theme: IconTheme = dvui.entypo,

const StyleScheme = @This();

/// An enum used to determine the kind of element to override when using `StyleScheme.set`.
pub const StyleSchemeElement = enum {
    button,
    text_entry,
    label,
    icon,
    scrollbar,
    context,
    dropdown,
};

/// Modify an element's default options.
pub fn set(self: *StyleScheme, element: StyleSchemeElement, opts: Options) void {
    switch (element) {
        .button => self.button = self.button.override(opts),
        .text_entry => self.text_entry = self.text_entry.override(opts),
        .label => self.label = self.label.override(opts),
        .icon => self.icon = self.icon.override(opts),
        .scrollbar => self.scrollbar = self.scrollbar.override(opts),
        .context => self.context = self.context.override(opts),
        .dropdown => self.dropdown = self.dropdown.override(opts),
    }
}
