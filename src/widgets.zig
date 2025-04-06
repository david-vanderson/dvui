//! You can find below a list of available widgets.
//!
//! Note that most of the time, you will **not** instanciate them directly but instead rely on higher level functions available in `dvui` top module.
//!
//! The corresponding function is usually indicated in the doc of each Widget.

pub const AnimateWidget = @import("widgets/AnimateWidget.zig");
pub const BoxWidget = @import("widgets/BoxWidget.zig");
pub const ButtonWidget = @import("widgets/ButtonWidget.zig");
pub const CacheWidget = @import("widgets/CacheWidget.zig");
pub const ContextWidget = @import("widgets/ContextWidget.zig");
pub const FlexBoxWidget = @import("widgets/FlexBoxWidget.zig");
pub const FloatingMenuWidget = @import("widgets/FloatingMenuWidget.zig");
pub const FloatingTooltipWidget = @import("widgets/FloatingTooltipWidget.zig");
pub const FloatingWidget = @import("widgets/FloatingWidget.zig");
pub const FloatingWindowWidget = @import("widgets/FloatingWindowWidget.zig");
pub const IconWidget = @import("widgets/IconWidget.zig");
pub const LabelWidget = @import("widgets/LabelWidget.zig");
pub const MenuItemWidget = @import("widgets/MenuItemWidget.zig");
pub const MenuWidget = @import("widgets/MenuWidget.zig");
pub const OverlayWidget = @import("widgets/OverlayWidget.zig");
pub const PanedWidget = @import("widgets/PanedWidget.zig");
pub const ReorderWidget = @import("widgets/ReorderWidget.zig");
pub const ScaleWidget = @import("widgets/ScaleWidget.zig");
pub const ScrollAreaWidget = @import("widgets/ScrollAreaWidget.zig");
pub const ScrollBarWidget = @import("widgets/ScrollBarWidget.zig");
pub const ScrollContainerWidget = @import("widgets/ScrollContainerWidget.zig");
pub const TextEntryWidget = @import("widgets/TextEntryWidget.zig");
pub const TextLayoutWidget = @import("widgets/TextLayoutWidget.zig");
pub const VirtualParentWidget = @import("widgets/VirtualParentWidget.zig");

// Needed for autodocs "backlink" to work
const dvui = @import("dvui");
