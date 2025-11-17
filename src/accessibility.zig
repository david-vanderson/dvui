const Null = @import("accessibility/Null.zig");
const AccessKit = @import("accessibility/AccessKit.zig");

pub const Instance = if (accesskit_enabled)
    AccessKit
else
    Null;

/// Alias of `Instance.Node`
pub const Node = Instance.Node;

pub const NodeCreationError = std.mem.Allocator.Error || error{OutOfNodes};

pub const NodeContext = struct {
    pub const Full = struct {
        ctx: NodeContext,

        parent: ?Node,
        bounds: dvui.Rect.Physical,
    };

    id: dvui.Id,
    role: Role,
    label: Label,

    root: bool,
    visible: bool,
    focused: bool,
};

pub const Label = union(enum) {
    pub const Direction = enum { prev, next };

    /// Use no label.
    none,
    /// Use the label from a different widget. This is preferred if there is a
    /// visible widget that labels this one.
    by_id: dvui.Id,

    /// Use this label for a different widget.
    for_id: dvui.Id,

    /// Use the previous or next label widget to label this widget.
    label_widget: Direction,

    /// Use this text as the label.  Prefer using .by if possible - .text is
    /// for cases where there is no visible label (like an icon or image).
    text: []const u8,
};

pub const Live = enum {
    off,
    polite,
    assertive,
};

pub const Orientation = enum {
    horizontal,
    vertical,

    pub fn ofDirection(dir: dvui.enums.Direction) Orientation {
        return switch (dir) {
            .horizontal => .horizontal,
            .vertical => .vertical,
        };
    }
};

pub const SortDirection = enum {
    ascending,
    descending,
    other,
};

pub const Toggled = enum {
    false,
    true,
    mixed,

    pub fn ofBool(value: bool) Toggled {
        return if (value) .true else .false;
    }
};

pub const Invalid = enum {
    true,
    grammar,
    spelling,
};

pub const Action = enum {
    click,
    focus,
    blur,
    collapse,
    expand,
    custom_action,
    decrement,
    increment,
    hide_tooltip,
    show_tooltip,
    replace_selected_text,
    scroll_down,
    scroll_left,
    scroll_right,
    scroll_up,
    scroll_into_view,
    scroll_to_point,
    set_scroll_offset,
    set_text_selection,
    set_sequential_focus_navigation_starting_point,
    set_value,
    show_context_menu,
};

pub const Role = enum {
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

const std = @import("std");
const dvui = @import("dvui");

const build_opts = @import("build_options");
const accesskit_enabled = build_opts.accesskit != .off and dvui.backend.kind != .testing and dvui.backend.kind != .web;
