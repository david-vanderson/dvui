# Accessibility in DVUI

## What is accessibility?

Most modern operating system provide an accessibility API to assist users who cannot use standard computer I/O devices to interact with applications.  See the "Accessibility" section of [README](README.md) for additional accessibility concerns.

These users often interact via 'screen reader' that can read text and other accessibility labels from the application. Some readers will also provide the user with a way to perform actions on an application, such as clicking a button, or setting the text in a text box. Others will rely on the keyboard navigation features provided by the application.

DVUI implements this part of accessibility through the [AccessKit](https://github.com/AccessKit/accesskit) toolkit, which provides a common interface to the operating system-specific accessibility APIs.

While DVUI tries to make this easy to integrate, some effort at the application level is required:
* adding accessibility labels to images and icons
* adding accessiblity labels to entry widgets such as textboxes and groups of widgets. See [Labeling](#labeling) for more details.
* ensuring visible labels are read for the correct content
* testing tab ordering and keyboard navigation
* general testing with screen readers (see below)

## Benefits and Downsides

The primary benefit is making your appliation useable by a wider array of users.

Incorporating accessibility makes your UI application scriptable. Each widget that has a node in the accessibility tree publishes its current value along with the set of actions it can perform. By using your platform's accessibility API, you can write automated tests as well as allowing your users to script common tasks.

Outside of the additional executable size from including the AccessKit library, there is very little performance impact from supporting AccessKit. (Essentially, two additional if statements per widget) 

The overhead of creating AccessKit nodes is only incurred when the operating system's accessibility API is activated by a screen reader or similar application.

## Enabling AccessKit in DVUI

AccessKit can be included as either a static or dynamic link library. Use `-Daccesskit=static` or `-Daccesskit=shared` to enable AccessKit support. 

Not all combinations of backends and operating systems are currently supported. 
- Linux - Coming soon.
- Windows - Support for all backends, except raylib static due to symbol clashes.
- MacOS - Support for SDL2, SDL3 and Raylib.
- Web - Not currently supported by AccessKit but it is planned. 

When you compile you application with AccessKit enabled, most of the accessibility work is taken care of for you and your users will gain most of the benefits of accessibility support. However, DVUI doesn't know your application's intent or any semantic details about the UX, so it is not possible to automate everything. 

As an example, you may have a set of radio buttons, but DVUI has no way to know if those radio buttons all belong to the same radio group.

For the radio button example, you can give DVUI and AccessKit some additional information by setting the 
role option on the box surrounding the radio buttons to `.role = .radio_group`.  This will let AccessKit know that all child radio buttons within the box all belong to the same radio group. You might also choose to supply a `.label` to give the user more information about the meaning of the radio group.

There are other AccessKit APIs that let you provide more details to the accessibility API. See [Widget users](#widget-users) for more details on how to use the AccessKit API.

```
{
    var hbox = dvui.box(@src(), 
        .{ .dir = .horizontal }, 
        .role = .radio_group, 
        .label = . { .text = "Make a choice"} },
    );
    defer hbox.deinit();
    
    if (dvui.radio(@src(), radio_choice == choice1), "Choice 1", .{ .id_extra = i })) {
        radio_choice = choice1;
    }
    if (dvui.radio(@src(), radio_choice == choice2), "Choice 2", .{ .id_extra = i })) {
        radio_choice = choice2;
    }
}
```

## Testing for accessibility

As all accessibility APIs are operating system specific, different tools are required to test on each platform.

### Testing accessibility on Windows

The basic test you should do is to open the Narrator using `ctrl-win-enter` (The same keyboard shortcut closes it). Perform the following steps:
1) Make sure the reader highlights a widget when you first click on the window. 
    - If no widget is focused and the whole window stays highlighted, you need to default the focus to a widget whenever the window is first opened using `dvui.focusWidget()` or similar.
2) Press `caps-r` to read the screen. The reader should read all controls and their displayed content.
    - If the reader is reading from controls that should be skipped (e.g. the down triangle in a custom dropdown), set .role = .none in the widget creation options for the image.
    - If the reader is skipping a widget that should be added, set .role to an appropriate value for that widget. 
    - Check that fields are labelled correctly (e.g. associating a label for a text box). DVUI has some heuristics for this but use the .label = .for or .by in the widget options to properly associate labels if needed.
3) Tab through each widget. 
    - Make sure each focusable widget has an appropriate `.tab_index` (either manually assigned or generated) and has a sensible position in the tab order.
    - Make sure the reader highlights each widget and reads out the correct value.
4) Pay special attention to images and icons. Make sure to add a `.label` option to give descriptive labels to these widgets.

The above steps only test reading from the screen. Actions can also be tested.
1) Download, install and run [Accessibility Insights](https://accessibilityinsights.io/)
2) Click on each widget
3) Look in the bottom right pane for a list of values and actions applicable to each widget.
    - If you don't see an action for an actionable widget and it is a DVUI widget, please file an issue.
    - If it is your widget, use `AccessKit.nodeAddAction()` and other relevant API to add the appropriate actions.
    - The best way to understand what actions are available for which roles is to look at the AccessKit source code.

See [AccessKit - Tips for application developers](https://github.com/AccessKit/accesskit/blob/main/README-APPLICATION-DEVELOPERS.md)

### Testing accessibility on MacOS

See [AccessKit - Tips for application developers](https://github.com/AccessKit/accesskit/blob/main/README-APPLICATION-DEVELOPERS.md)

### Testing accessibility on Linux

See [AccessKit - Tips for application developers](https://github.com/AccessKit/accesskit/blob/main/README-APPLICATION-DEVELOPERS.md)

## DVUI and AccessKit Details

AccessKit is an accessibility library written in Rust that provides a unified API to the underlying operating system specific accessibility APIs.

AccessKit requires:
1) A tree of "node ids" representing the parent / child relationships and the roles of each node.
2) A set of updates to those nodes, which contain any data that was changed since the previous update.

As DVUI does not keep state for all widget values, a full set of node id's and a full set of updates is sent at the end of each frame.

The DVUI WidgetId is used as the AccessKit node id. When a widget is created, if 1) Accessibility is active, 2) The Widget has a role and it is not .none, 3) The widget is at least partially visible or the widget is the focused widget, then a new AccessKit node will be created via `dvui.accesskit.nodeCreate()`.  Widgets will then set any values or actions against the created node.

The visibility check should be removed in future and the nodeSetClipsChildren API should be used for anything that clips contained child widgets. The focused node is always added to the tree, even if it is not visible, meaning it can have the wrong parent. But this stops the screen reader's focus from shifting to the main window when the focused widget scrolls off the screen.

Note: AccessKit is still a relatively new and evolving library. Not all platform accessibility features are supported and support for some features may be partially implemented.  Please file any issues!

### Multithreading requirements

There is the potential for any callback from AccessKit to be called on the non-gui thread. This includes the initialTreeUpdate, the frameTreeUpdate and the actionHandler. Which thread these are called on varies by operating system, so you should assume they will be called on a separate thread.

Any direct access to the `currentWindow().accesskit` variables should be protected by `currentWindow().accesskit.mutex`. 
`accesskit.nodes` is safe for `.get` access if used from the gui thread.

### Actions

Actions are input events from the OS accessibility API to perform some function in the GUI, such as focusing a widget, clicking a button or setting a value for a widget. See `AccessKit.Actions` for a full list.

Actions are collected for the current frame in the `action_requests` ArrayList. 
At the start of the next frame, these action requests are converted to the relevant DVUI events for the requested widget.
Values are set via the 'text' event with the `replace` field set to true to indicate that the value should replace any existing value held by that widget.

Currently supported Actions are:
* click
* set_value (text and numeric types are supported)
* focus

It is planned to support scrolling actions once the read-only issue with AccessKit scrollbars is resolved.

### Widget creators

Each widget's `install()` should check if an accessibility node was created by using `self.data().accesskit_node()` or equivalent. If this returns non-null, AccessKit functions can be used on the returned node to set any values and events for that widget. Common functions are:
- `nodeSetValue` / `nodeSetNumericValue` - Used to set the value to be read out by the reader. See AccessKit source code for details on what values can be set for each role.
- `nodesetToggled` - For checkboxes, radio buttons etc.
- `nodeAddAction` - Common actions are .click, .focus, .toggle. See AccessKit source code for the actions available for each role.

If your widget can have a value set, then make sure to handle the `text` event to allow that value to be set via a set_value action.

It is safe to use the `accesskit_node()` for a widget that has been deinitialized. e.g. the following code will work. 
```
var label_wd: WidgetData = undefined;
dvui.labelNoFmt(@src(), message, .{}, .{ .background = true, .corner_radius = dvui.Rect.all(1000), .padding = .{ .x = 16, .y = 8, .w = 16, .h = 8 }, .data_out = &label_wd });
if (label_wd.accesskit_node()) |ak_node| {     
    AccessKit.nodeSetLive(ak_node, AccessKit.Live.polite);
}
```

For cases where you only have access to the widget id. the AccessKit node can be obtained from the `nodes` collection of the `AccessKit` struct. e.g.
```
var label_id: Id = ...;
{
    if (currentWindow().accesskit.nodes.get(label_id)) |ak_node| {
        AccessKit.nodeSetLive(ak_node, AccessKit.Live.polite);
    }
}
```

### Widget users

The AccessKit APIs are also available for widget users to customize accessibility information. As above, the AccessKit node can be accessed either from `accesskit_node()` on widget data, or via the `nodes` collection through `currentWindow().accesskit`

An example of using a text box as a number entry box and adding minimum and maximum values. (Note that dvui.textEntryNumber already does this for you)

```
const te = dvui.textEntry(@src(), .{}, .{ .role = .number_input});
if (te.data().accesskit_node()) | ak_node | {
    // Remove the text value already set by textEntry
    AccessKit.nodeClearValue(ak_node);  
    AccessKit.nodeSetMinNumericValue(ak_node, 0);
    AccessKit.nodeSetMaxNumericValue(ak_node, 128);
    // Set the numeric value.
    AccessKit.nodeSetNumericValue(ak_node, std.fmt.parseInt(te.getText()) catch 0);
}
```

#### Labeling
Labellng is one of the most important things you can do to make your appliction more accessible. Widgets can be labelled by setting the `.label` option for any widget. Labels should give the screen reader enough context for a widget so the user csn know what that widget is for. 

For example, if a user moves focus to a text entry, the text box should be labeeled with it's purpose. Typically, this will the contents of the label widget preceding the text entry.

DVUI offers the following labeling options:
   * text - set label directly
   * by_id - Pass the id of the label widget containing the label
   * for_id - This label widget labels another widget.
   * label_widget = .prev - This widget is labeled by the last created label widget.
   * label_widget  = .next - This widget is labeled by the next created label widget.

Alternatively, you can also use the `AccessKit.nodeSetLabel` and `AccessKit.nodeSetLabeledBy` functions.

## Current State of Accessibility in DVUI

* A role of `null` means the widget will not be added to the accessibility tree, unless the user passes a `role` for that widget via Options.

| Widget | Role | Read Support | Action Support | TODO? | Details |
|--------|------|--------------|----------------|-------|---------|
| AnimateWidget| null | Basic | N/A | N | User can pass .role and .label via options |
| BoxWidget | null | Basic | N/A | N | User can pass .role and .label via options |
| ButtonWidget | button | Yes | Yes | N | Focus and Click actions supported |
| ColorPickerWidget | slider x 4 | Partial | Partial | Y | AccessKit does not currently support 2d-sliders. Other sliders are supported. |
| DropDownWidget | combo_box / list_item | N | Y | Y | more testing required |
| FlexBoxWidget | null | Basic | N/A | N | User can pass .role and .label via options |
| FloatingMenuWidget | none | N/A | N/A | N | Accessibility Handled by Menu / MenuItem|
| FloatingToolTipWidget | tooltip | Y* | N | N | Tooltips are added only when shown. No support for showing / hiding tooltips |
| FloatingWidget | N/A | N/A | N/A | N | |
| FloatingWindowWidget | window | Y | Y | N | Can close via close button. |
| GridWidget | grid, header, cell | Y? | N/A | Y | Needs more real-world testing. Setting row and col numbers doesn't appear to do anything |
| IconWidget | image |  Y | N/A | N | |
| LabelWidget | label |  Y | N/A | N | | 
| MenuItemWidget | menu_item | Y | Y | Y | Add keyboard shortcuts when supported by dvui | 
| MenuWidget | menu |  Y | Y | N | |
| OverlayWidget | null | Basic | N/A | N | User can pass .role and .label via options |
| PanedWidget | pane |Y | N* | Y | Accesskit currently sets the control as read-only. If this is fixed, implement .text event to set the splitter position. |
| PlotWidget | .group, .image | N | N/A? | N | Labels image with title of plot. Labels plot widget as a plot. |
| ReorderWidget | null | N | N | Y | Not currently supported. Unlikely that interaction will work? | 
| ScaleWidget | null | N/A | N/A | N | Not required |
| ScrollAreaWidget | scroll_view | Y | N | N | Appears as a pane |
| ScrollBarWidget | scroll_bar | Y *| N* | Y | Due to bug in AccessKit, is set to read-only and cannot interact. Actual values displayed may not be accurate | 
| SuggestionsWidget | suggestion, list_item | Y | Y | N | 
| TabsWidget | .tab_panel, .tab | Y | Y | N | Sets active tabs and allows tab selection |
| TextEntryWidget | text_input, multiline_text_input | Y* | N* | Y | Text entry should work for "reasonable" amounts of text. SetValue will replace all text. Needs to implement the .text_run role to properly allow users to fully perform text entry and editing. |
| TextLayoutWidget | label | Y* | N/A | Y | Currently displays only visible text (TBC). Works OK for "reasonable" amounts of text. Does not support sending of formatting information | 
| TreeWidget | tree, tree_item | Y* | Y | Y | Adds tree and nodes. Implement expand / collapse when supported by AccessKit | 
| windowHeader | label, button | Y | Y | N | |
| dialogs | window | Y | Y | Y | All dialogs are displayed as windows, rather than dialogs and modal state is not displayed in accessibility insights. AccessKit currently has limted support for dialogs, so leaving as window until the situation changes and can revisit. |
| toasts | label | Y? | N/A | ? | These are set as polite annoucements via node_set_live but have not seen this cause anything to be read from the reader. |
| comboBox | combo_box | Y | Y | N | Displays as combo box and shows list items when dropped |
| expander | group | Y* | Y* | Y | AccessKit does not currently support expand / collapse |
| context | ? | ? | ? | ? | Will need to implement "show context menu" action. Which will be mapped to right-click. |
| gridHeadingSortable | button | Y* | Y | Y | Sets sort state of asc/desc if sorted, but does not come through in accessibility insights. further investigation required |
| gridHeadingCheckbox | button | Y | Y | N| Labels checkbox as select all / select none. |
| image | image | Y* | N/A | N | Requires user to label the image with .label |
| slider | slider | Y | Y | N | Fully supported |
| progress | progress_indicator | Y | N/A  | N | Fully supported |
| checkbox | check_box | Y | Y | N | Fully supported |
| radio | radio_button | Y* | Y | N | Best practice: Create a radio group with a surrounding box|
| textEntryNumber | number_input | Y | Y | N | Fully supported. Supports min, max and valid/invalid. |

