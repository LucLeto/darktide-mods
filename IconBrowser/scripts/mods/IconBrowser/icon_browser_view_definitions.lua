--- Look and structure of the Icon Browser view.
-- Palette and fonts follow the game's terminal screens (Psykhanium and Mortis Trials terminals): dark
-- desaturated greens, olive frames, sage text and amber/gold for selection, built once from the
-- `Color.terminal_*` set. Every scenegraph node is sized and placed at runtime by the view's layout,
-- so the definitions only declare the hierarchy and the passes.
--
-- Chrome widgets use only shared UI materials (backgrounds, gradients, 2px frames and corners); the
-- indexed icon materials are drawn only by the slot and preview widgets, which the view renders inside
-- `pcall` so a failing material never takes the frame down with it.
--
-- Loaded through `mod:io_dofile` by `icon_browser_view.lua`.
-- module: icon_browser_view_definitions
-- author: LucLeto
local mod = get_mod("IconBrowser")

local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")
local ScrollbarPassTemplates = require("scripts/ui/pass_templates/scrollbar_pass_templates")
local TextInputPassTemplates = require("scripts/ui/pass_templates/text_input_pass_templates")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UISoundEvents = require("scripts/settings/ui/ui_sound_events")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local clone = table.clone
local floor = math.floor
local min = math.min
local terminal_button_change_function = ButtonPassTemplates.terminal_button_change_function
local terminal_button_hover_change_function = ButtonPassTemplates.terminal_button_hover_change_function

--- The view definitions module table.
local Definitions = {}

--- Shared UI materials of the terminal look: a plain square, a vertical gradient, the 2 px frame and
-- its corner pieces, and the textured panel background.
local MATERIAL_SQUARE = "content/ui/materials/backgrounds/default_square"
local MATERIAL_GRADIENT = "content/ui/materials/gradients/gradient_vertical"
local MATERIAL_FRAME = "content/ui/materials/frames/frame_tile_2px"
local MATERIAL_CORNER = "content/ui/materials/frames/frame_corner_2px"
local MATERIAL_PANEL = "content/ui/materials/backgrounds/terminal_basic"

--- Font sizes of the inspector's secondary buttons and preview controls; smaller than the template's
-- 22 so the half- and third-width buttons fit their labels.
local SECONDARY_BUTTON_FONT_SIZE = 18
local PREVIEW_BUTTON_FONT_SIZE = 16

--- Colours of the browser as `{ a, r, g, b }`, built once from the game's `Color.terminal_*` set
-- where one fits: dark desaturated greens for surfaces, olive frames, sage text, and amber and gold
-- for selection. Change functions copy from these tables and never write them.
local PALETTE = {
    backdrop = { 170, 3, 7, 5 },
    frame_background = { 228, 9, 14, 11 },
    panel = Color.terminal_grid_background(110, true),
    panel_fill = { 170, 10, 16, 12 },
    header_fill = { 120, 20, 28, 21 },
    divider = Color.terminal_frame(255, true),
    frame = Color.terminal_frame(255, true),
    frame_hover = Color.terminal_frame_hover(255, true),
    frame_focus = Color.terminal_frame_hover(255, true),
    frame_selected = Color.terminal_corner_selected(200, true),
    corner = Color.terminal_corner(255, true),
    corner_hover = Color.terminal_corner_hover(255, true),
    corner_focus = Color.terminal_corner_hover_bright(255, true),
    corner_selected = Color.terminal_corner_selected(255, true),
    tile_background = { 210, 14, 20, 15 },
    tile_background_hover = { 220, 30, 40, 30 },
    tile_background_focus = { 220, 26, 36, 27 },
    tile_background_selected = Color.terminal_background_selected(150, true),
    gradient = Color.terminal_background_gradient(40, true),
    gradient_hover = Color.terminal_background_gradient(90, true),
    gradient_selected = Color.terminal_frame_selected(120, true),
    preview_backing = { 170, 5, 8, 6 },
    text_header = Color.terminal_text_header(255, true),
    text_header_selected = Color.terminal_text_header_selected(255, true),
    text_body = Color.terminal_text_body(255, true),
    text_body_dark = Color.terminal_text_body_dark(255, true),
    text_sub_header = Color.terminal_text_body_sub_header(255, true),
    text_key_value = Color.terminal_text_key_value(255, true),
    favorite = Color.terminal_corner_selected(255, true),
    status_success = Color.terminal_text_key_value(255, true),
    status_error = { 255, 214, 96, 72 },
    row_even = { 110, 16, 22, 17 },
    row_odd = { 110, 23, 31, 24 },
    row_hover = { 170, 44, 56, 42 },
    row_focus = { 170, 36, 48, 36 },
    row_selected = Color.terminal_background_selected(110, true),
    option_hover = Color.terminal_frame_hover(110, true),
    option_selected = Color.terminal_background_selected(150, true),
    header_hover = Color.terminal_frame_hover(60, true),
    preview_dark = { 255, 8, 10, 8 },
    preview_light = { 255, 196, 200, 190 },
    checker_light = { 255, 170, 170, 170 },
    checker_dark = { 255, 110, 110, 110 },
    tooltip_background = { 245, 8, 12, 9 },
    transparent = { 0, 0, 0, 0 },
}

--- The palette, shared with the view.
Definitions.PALETTE = PALETTE

--- Layout constants in UI units (1080 high); the view derives every node from these and the screen.
Definitions.LAYOUT = {
    top_margin = 24,
    legend_height = 60,
    bottom_gap = 6,
    frame_width_fraction = 0.95,
    min_frame_width = 1280,
    padding = 20,
    gap = 14,
    title_height = 44,
    toolbar_height = 44,
    row_spacing = 10,
    status_height = 30,
    list_header_height = 34,
    area_padding = 10,
    scrollbar_width = 8,
    scrollbar_gap = 8,
    inspector_min_width = 380,
    inspector_max_fraction = 0.45,
    popup_option_height = 38,
    tooltip_max_width = 640,
    tooltip_padding = 10,
    toolbar = {
        spacing = 8,
        search_min = 320,
        clear = 44,
        category = 240,
        sort = 210,
        favorites = 140,
        recent = 120,
        recent_clear = 90,
        view = 90,
        density = 46,
    },
    inspector = {
        padding = 18,
        title_height = 56,
        subtitle_height = 22,
        spacing = 10,
        controls_height = 34,
        metadata_min_height = 250,
        primary_height = 50,
        secondary_height = 34,
        secondary_rows = 3,
        preview_min_height = 120,
    },
}

do
    local inspector = Definitions.LAYOUT.inspector

    --- Height the inspector needs with the smallest preview; the frame never gets shorter than this,
    -- so the copy actions and the metadata are never clipped. The spacings are the one below the
    -- divider, the three around the preview controls and the metadata, the one above the secondary
    -- buttons and the ones between their rows.
    inspector.min_content_height = inspector.padding * 2 + inspector.title_height + inspector.subtitle_height + 8
        + inspector.spacing * (4 + inspector.secondary_rows) + inspector.preview_min_height
        + inspector.controls_height + inspector.metadata_min_height + inspector.primary_height
        + inspector.secondary_height * inspector.secondary_rows
end

--- Thumbnail densities: grid tile target width, label font/height, list row height and font.
Definitions.DENSITIES = {
    compact = { tile = 104, gap = 8, padding = 6, font = 15, label = 22, row = 40, row_font = 16 },
    normal = { tile = 136, gap = 10, padding = 7, font = 17, label = 26, row = 52, row_font = 18 },
    large = { tile = 184, gap = 12, padding = 8, font = 19, label = 30, row = 72, row_font = 20 },
}

--- Densities in toolbar order, the cycle of preview backgrounds, and the preview zoom factors.
Definitions.DENSITY_ORDER = { "compact", "normal", "large" }
Definitions.PREVIEW_BACKGROUNDS = { "dark", "light", "checker" }
Definitions.ZOOM_LEVELS = { 1, 2, 4 }

--- Display aspects of the inspector preview. The engine exposes no native texture size, so the
-- aspect is the user's choice. The first entry, `auto`, uses the size the game draws the asset at
-- where the source references know one, and 1:1 otherwise.
Definitions.ASPECTS = {
    { label = "auto", auto = true, width = 1, height = 1 },
    { label = "1:1", width = 1, height = 1 },
    { label = "4:3", width = 4, height = 3 },
    { label = "16:9", width = 16, height = 9 },
    { label = "2:1", width = 2, height = 1 },
    { label = "3:4", width = 3, height = 4 },
    { label = "1:2", width = 1, height = 2 },
}

--- Cells per side of the checkerboard preview background.
Definitions.CHECKER_CELLS = 8

-- ----------------------------------------------------------------------------
-- Styles
-- ----------------------------------------------------------------------------

--- Copies the four channels of a colour into an existing colour table, without allocating.
-- tab: source `{ a, r, g, b }` colour
-- tab: target colour table that is overwritten
local function _copy_color(source, target)
    target[1] = source[1]
    target[2] = source[2]
    target[3] = source[3]
    target[4] = source[4]
end

--- `_copy_color`, shared with the view.
Definitions.copy_color = _copy_color

--- Clones a font style and sets its size, colour and alignment for a text pass.
-- The colour is also stored as `default_color` for the change functions; the pass is aligned to the
-- top left of its node with a z offset of 1.
-- tab: base_style `UIFontSettings` entry
-- ?number: font_size font size, else the base style's
-- tab: text_color `{ a, r, g, b }` colour
-- ?string: horizontal_alignment text alignment, `left` by default
-- ?string: vertical_alignment text alignment, `center` by default
-- treturn: tab
local function _text_style(base_style, font_size, text_color, horizontal_alignment, vertical_alignment)
    local style = clone(base_style)

    style.font_size = font_size or style.font_size
    style.text_color = clone(text_color)
    style.default_color = clone(text_color)
    style.text_horizontal_alignment = horizontal_alignment or "left"
    style.text_vertical_alignment = vertical_alignment or "center"
    style.horizontal_alignment = "left"
    style.vertical_alignment = "top"
    style.offset = { 0, 0, 1 }

    return style
end

--- Base font styles: body text, the browser title and the inspector title.
local FONT_BODY = UIFontSettings.body_small or UIFontSettings.body
local FONT_HEADER = UIFontSettings.header_2 or UIFontSettings.header_1
local FONT_SUB_HEADER = UIFontSettings.header_3 or FONT_HEADER

--- Hotspot content with the game's default hover and click sounds; cloned into every clickable pass.
local HOTSPOT_CONTENT = {
    on_hover_sound = UISoundEvents.default_mouse_hover,
    on_pressed_sound = UISoundEvents.default_click,
}

--- Selected > keyboard focus > hover > default, read from content flags the view sets on bind, so the
-- hotspot's own `is_selected` (which also routes gamepad confirm presses) is never touched.
-- tab: content widget content with `hotspot`, `is_selected` and `is_focused`
-- tab: style pass style with `default_color`, `hover_color`, `focus_color` and `selected_color`
local function _slot_state_change_function(content, style)
    local color

    if content.is_selected then
        color = style.selected_color
    elseif content.is_focused then
        color = style.focus_color
    elseif content.hotspot.is_hover then
        color = style.hover_color
    end

    _copy_color(color or style.default_color, style.text_color or style.color)
end

--- Visibility function of icon passes: shown while the bound material may be drawn.
-- tab: content widget content
-- treturn: bool
local function _icon_visibility_function(content)
    return content.icon_available
end

--- Visibility function of the fallback text: shown for a bound asset whose preview cannot be drawn.
-- tab: content widget content
-- treturn: bool
local function _fallback_visibility_function(content)
    return content.has_asset and not content.icon_available
end

--- Visibility function of the favorite marker.
-- tab: content widget content
-- treturn: bool
local function _favorite_visibility_function(content)
    return content.is_favorite
end

--- Gives a pass style one colour per state for `_slot_state_change_function`; the drawn colour starts
-- as a copy of the default.
-- tab: style pass style to extend
-- tab: default_color colour without any state
-- tab: hover_color colour while hovered
-- tab: focus_color colour while focused by the keyboard
-- tab: selected_color colour while selected
-- treturn: tab the style
local function _state_colors(style, default_color, hover_color, focus_color, selected_color)
    style.color = clone(default_color)
    style.default_color = default_color
    style.hover_color = hover_color
    style.focus_color = focus_color
    style.selected_color = selected_color

    return style
end

--- Passes of the thin terminal frame and its corner pieces.
-- number: frame_z z offset of the frame; the corners sit one above
-- treturn: tab array of passes
local function _terminal_frame_passes(frame_z)
    return {
        {
            pass_type = "texture",
            style_id = "frame",
            value = MATERIAL_FRAME,
            style = {
                color = clone(PALETTE.frame),
                offset = { 0, 0, frame_z },
            },
        },
        {
            pass_type = "texture",
            style_id = "corner",
            value = MATERIAL_CORNER,
            style = {
                color = clone(PALETTE.corner),
                offset = { 0, 0, frame_z + 1 },
            },
        },
    }
end

--- Appends the entries of one array to another.
-- tab: target array that is extended
-- tab: source array whose entries are appended
-- treturn: tab the target
local function _append(target, source)
    for i = 1, #source do
        target[#target + 1] = source[i]
    end

    return target
end

--- Passes of a terminal panel: a dark fill, the `terminal_basic` texture and a frame with corners.
-- treturn: tab array of passes
local function _panel_passes()
    return _append({
        {
            pass_type = "rect",
            style_id = "fill",
            style = {
                color = clone(PALETTE.panel_fill),
                offset = { 0, 0, 0 },
            },
        },
        {
            pass_type = "texture",
            style_id = "panel",
            value = MATERIAL_PANEL,
            style = {
                scale_to_material = true,
                color = clone(PALETTE.panel),
                offset = { 0, 0, 1 },
            },
        },
    }, _terminal_frame_passes(2))
end

--- A single text pass whose style id and value id are both `text`.
-- tab: style text style
-- treturn: tab array of passes
local function _text_passes(style)
    return {
        {
            pass_type = "text",
            style_id = "text",
            value_id = "text",
            value = "",
            style = style,
        },
    }
end

--- Terminal control with a small caption above its value; used for the category and sort menus.
-- The caption is `content.caption`, the value `content.text`; the selected state of the hotspot
-- marks the button whose menu is open.
-- treturn: tab array of passes
local function _dropdown_button_passes()
    local caption_style = _text_style(FONT_BODY, 13, PALETTE.text_sub_header, "left", "top")
    local value_style = _text_style(FONT_BODY, 19, PALETTE.text_header, "left", "bottom")

    caption_style.offset = { 12, 4, 6 }
    caption_style.size_addition = { -24, 0 }
    value_style.offset = { 12, -4, 6 }
    value_style.size_addition = { -24, 0 }
    value_style.hover_color = PALETTE.text_header_selected

    return {
        {
            pass_type = "hotspot",
            content_id = "hotspot",
            content = clone(HOTSPOT_CONTENT),
        },
        {
            pass_type = "texture",
            style_id = "background",
            value = MATERIAL_SQUARE,
            style = {
                color = Color.terminal_background(nil, true),
                default_color = Color.terminal_background(nil, true),
                selected_color = Color.terminal_background_selected(nil, true),
            },
            change_function = terminal_button_change_function,
        },
        {
            pass_type = "texture",
            style_id = "background_gradient",
            value = MATERIAL_GRADIENT,
            style = {
                color = Color.terminal_background_gradient(nil, true),
                offset = { 0, 0, 1 },
            },
            change_function = terminal_button_hover_change_function,
        },
        {
            pass_type = "texture",
            style_id = "frame",
            value = MATERIAL_FRAME,
            style = {
                color = Color.terminal_frame(nil, true),
                default_color = Color.terminal_frame(nil, true),
                hover_color = Color.terminal_frame_hover(nil, true),
                selected_color = Color.terminal_frame_selected(nil, true),
                offset = { 0, 0, 2 },
            },
            change_function = terminal_button_change_function,
        },
        {
            pass_type = "texture",
            style_id = "corner",
            value = MATERIAL_CORNER,
            style = {
                color = Color.terminal_corner(nil, true),
                default_color = Color.terminal_corner(nil, true),
                hover_color = Color.terminal_corner_hover(nil, true),
                selected_color = Color.terminal_corner_selected(nil, true),
                offset = { 0, 0, 3 },
            },
            change_function = terminal_button_change_function,
        },
        {
            pass_type = "text",
            style_id = "caption",
            value_id = "caption",
            value = "",
            style = caption_style,
        },
        {
            pass_type = "text",
            style_id = "text",
            value_id = "text",
            value = "",
            style = value_style,
            change_function = function(content, style)
                local hotspot = content.hotspot

                _copy_color((hotspot.is_hover or hotspot.is_selected) and style.hover_color or style.default_color,
                    style.text_color)
            end,
        },
    }
end

--- Clickable list column header; `content.is_active` marks the sorted column in gold.
-- treturn: tab array of passes
local function _list_header_button_passes()
    local text_style = _text_style(FONT_BODY, 16, PALETTE.text_sub_header, "left", "center")

    text_style.offset = { 10, 0, 3 }
    text_style.size_addition = { -20, 0 }
    text_style.active_color = PALETTE.corner_selected
    text_style.hover_color = PALETTE.text_header

    return {
        {
            pass_type = "hotspot",
            content_id = "hotspot",
            content = clone(HOTSPOT_CONTENT),
        },
        {
            pass_type = "rect",
            style_id = "hover",
            style = {
                color = clone(PALETTE.header_hover),
                offset = { 0, 0, 1 },
            },
            visibility_function = function(content)
                return content.hotspot.is_hover
            end,
        },
        {
            pass_type = "text",
            style_id = "text",
            value_id = "text",
            value = "",
            style = text_style,
            change_function = function(content, style)
                local color = style.default_color

                if content.is_active then
                    color = style.active_color
                elseif content.hotspot.is_hover then
                    color = style.hover_color
                end

                _copy_color(color, style.text_color)
            end,
        },
    }
end

-- ----------------------------------------------------------------------------
-- Static definitions
-- ----------------------------------------------------------------------------

--- Scenegraph node at the top left of its parent; the view sets its size and position at runtime.
-- string: parent parent node id
-- ?number: z z position relative to the parent, 1 by default
-- treturn: tab
local function _node(parent, z)
    return {
        parent = parent,
        horizontal_alignment = "left",
        vertical_alignment = "top",
        size = { 1, 1 },
        position = { 0, 0, z or 1 },
    }
end

--- Toolbar control nodes in layout order; the view places them left to right after the search field.
Definitions.TOOLBAR_NODES = {
    "category_button",
    "sort_button",
    "favorites_button",
    "recent_button",
    "recent_clear_button",
    "view_grid_button",
    "view_list_button",
    "density_compact_button",
    "density_normal_button",
    "density_large_button",
}

--- List view columns, left to right.
Definitions.LIST_COLUMNS = { "preview", "name", "id", "category", "path" }

--- Builds the view's definitions: scenegraph, static widgets, preview widgets and legend entries.
-- Called by the view's `init` on every opening, so the texts follow the current language. Legend
-- entries name callbacks and visibility methods of the view.
-- func: upper upper-case function for titles, `Utf8.upper` where available
-- treturn: tab with `scenegraph_definition`, `widget_definitions`, `preview_widget_definitions` and
-- `legend_inputs`
function Definitions.create(upper)
    local scenegraph_definition = {
        screen = UIWorkspaceSettings.screen,
        frame = {
            parent = "screen",
            horizontal_alignment = "center",
            vertical_alignment = "top",
            size = { 1280, 800 },
            position = { 0, 24, 10 },
        },
        header = _node("frame", 1),
        title_text = _node("header", 2),
        copy_status_text = _node("header", 2),
        count_text = _node("header", 2),
        header_divider = _node("header", 2),
        search_input = _node("frame", 3),
        search_clear = _node("frame", 3),
        browser_panel = _node("frame", 1),
        list_header = _node("browser_panel", 3),
        list_header_preview = _node("list_header", 1),
        list_header_name = _node("list_header", 1),
        list_header_id = _node("list_header", 1),
        list_header_category = _node("list_header", 1),
        list_header_path = _node("list_header", 1),
        browser_area = _node("browser_panel", 3),
        scrollbar = _node("browser_panel", 4),
        inspector_panel = _node("frame", 1),
        inspector_title = _node("inspector_panel", 3),
        inspector_subtitle = _node("inspector_panel", 3),
        inspector_divider = _node("inspector_panel", 3),
        preview_area = _node("inspector_panel", 3),
        preview_icon = {
            parent = "preview_area",
            horizontal_alignment = "center",
            vertical_alignment = "center",
            size = { 1, 1 },
            position = { 0, 0, 3 },
        },
        preview_background_button = _node("inspector_panel", 3),
        preview_zoom_button = _node("inspector_panel", 3),
        preview_aspect_button = _node("inspector_panel", 3),
        inspector_metadata = _node("inspector_panel", 3),
        inspector_empty = _node("inspector_panel", 3),
        copy_path_button = _node("inspector_panel", 3),
        copy_filename_button = _node("inspector_panel", 3),
        copy_lua_button = _node("inspector_panel", 3),
        copy_snippet_button = _node("inspector_panel", 3),
        copy_sources_button = _node("inspector_panel", 3),
        favorite_button = _node("inspector_panel", 3),
        status_bar = _node("frame", 2),
        hint_text = _node("status_bar", 1),
        popup = _node("frame", 100),
        tooltip = _node("frame", 120),
    }

    local toolbar_nodes = Definitions.TOOLBAR_NODES

    for i = 1, #toolbar_nodes do
        scenegraph_definition[toolbar_nodes[i]] = _node("frame", 3)
    end

    local title_style = _text_style(FONT_HEADER, 30, PALETTE.text_header, "left", "center")
    local status_style = _text_style(FONT_BODY, 18, PALETTE.status_success, "right", "center")
    local count_style = _text_style(FONT_BODY, 20, PALETTE.text_body, "right", "center")
    local empty_style = _text_style(FONT_BODY, 22, PALETTE.text_sub_header, "center", "center")
    local inspector_title_style = _text_style(FONT_SUB_HEADER, 24, PALETTE.text_header, "left", "bottom")
    local inspector_subtitle_style = _text_style(FONT_BODY, 18, PALETTE.text_sub_header, "left", "center")
    local metadata_style = _text_style(FONT_BODY, 16, PALETTE.text_body, "left", "top")
    local hint_style = _text_style(FONT_BODY, 16, PALETTE.text_body_dark, "left", "center")
    local preview_label_style = _text_style(FONT_BODY, 16, PALETTE.text_sub_header, "left", "center")
    local tooltip_style = _text_style(FONT_BODY, 18, PALETTE.text_header, "left", "top")

    metadata_style.line_spacing = 1.15
    tooltip_style.offset = { Definitions.LAYOUT.tooltip_padding, Definitions.LAYOUT.tooltip_padding, 3 }
    tooltip_style.size_addition = { -Definitions.LAYOUT.tooltip_padding * 2, -Definitions.LAYOUT.tooltip_padding * 2 }
    preview_label_style.offset = { 10, 0, 1 }

    local widget_definitions = {
        backdrop = UIWidget.create_definition({
            { pass_type = "rect", style = { color = clone(PALETTE.backdrop) } },
        }, "screen"),
        frame_background = UIWidget.create_definition(_append({
            { pass_type = "rect", style = { color = clone(PALETTE.frame_background), offset = { 0, 0, 0 } } },
        }, _terminal_frame_passes(1)), "frame"),
        header_background = UIWidget.create_definition({
            { pass_type = "rect", style = { color = clone(PALETTE.header_fill), offset = { 0, 0, 0 } } },
        }, "header"),
        header_divider = UIWidget.create_definition({
            { pass_type = "rect", style = { color = clone(PALETTE.divider) } },
        }, "header_divider"),
        title_text = UIWidget.create_definition({
            { pass_type = "text", value_id = "text", value = upper(mod:localize("mod_name")), style = title_style },
        }, "title_text"),
        copy_status_text = UIWidget.create_definition(_text_passes(status_style), "copy_status_text"),
        count_text = UIWidget.create_definition(_text_passes(count_style), "count_text"),
        search_input = UIWidget.create_definition(TextInputPassTemplates.terminal_input_field, "search_input", {
            placeholder_text = mod:localize("search_placeholder"),
        }),
        search_clear = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small, "search_clear", {
            text = "X",
        }),
        category_button = UIWidget.create_definition(_dropdown_button_passes(), "category_button", {
            caption = upper(mod:localize("toolbar_category")),
        }),
        sort_button = UIWidget.create_definition(_dropdown_button_passes(), "sort_button", {
            caption = upper(mod:localize("toolbar_sort")),
        }),
        favorites_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small, "favorites_button", {
            text = upper(mod:localize("toolbar_favorites")),
        }),
        recent_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small, "recent_button", {
            text = upper(mod:localize("toolbar_recent")),
        }),
        recent_clear_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "recent_clear_button", {
                text = upper(mod:localize("toolbar_clear_recent")),
            }),
        view_grid_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small, "view_grid_button", {
            text = upper(mod:localize("toolbar_view_grid")),
        }),
        view_list_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small, "view_list_button", {
            text = upper(mod:localize("toolbar_view_list")),
        }),
        density_compact_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "density_compact_button", {
                text = mod:localize("toolbar_density_compact"),
            }),
        density_normal_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "density_normal_button", {
                text = mod:localize("toolbar_density_normal"),
            }),
        density_large_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "density_large_button", {
                text = mod:localize("toolbar_density_large"),
            }),
        browser_panel = UIWidget.create_definition(_panel_passes(), "browser_panel"),
        list_header_background = UIWidget.create_definition({
            { pass_type = "rect", style = { color = clone(PALETTE.header_fill) } },
            {
                pass_type = "rect",
                style = {
                    vertical_alignment = "bottom",
                    color = clone(PALETTE.divider),
                    size = { nil, 2 },
                    offset = { 0, 0, 1 },
                },
            },
        }, "list_header"),
        list_header_preview = UIWidget.create_definition(_text_passes(preview_label_style), "list_header_preview", {
            text = upper(mod:localize("column_preview")),
        }),
        list_header_name = UIWidget.create_definition(_list_header_button_passes(), "list_header_name"),
        list_header_id = UIWidget.create_definition(_list_header_button_passes(), "list_header_id"),
        list_header_category = UIWidget.create_definition(_list_header_button_passes(), "list_header_category"),
        list_header_path = UIWidget.create_definition(_list_header_button_passes(), "list_header_path"),
        empty_text = UIWidget.create_definition({
            {
                pass_type = "text",
                value_id = "text",
                value = "",
                style = (function()
                    local style = clone(empty_style)

                    style.offset = { 0, 0, 20 }

                    return style
                end)(),
            },
        }, "browser_area"),
        scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.terminal_scrollbar, "scrollbar", {
            scroll_speed = 10,
            scroll_amount = 0.1,
        }),
        inspector_panel = UIWidget.create_definition(_panel_passes(), "inspector_panel"),
        inspector_title = UIWidget.create_definition(_text_passes(inspector_title_style), "inspector_title"),
        inspector_subtitle = UIWidget.create_definition(_text_passes(inspector_subtitle_style), "inspector_subtitle"),
        inspector_divider = UIWidget.create_definition({
            { pass_type = "rect", style = { color = clone(PALETTE.divider) } },
        }, "inspector_divider"),
        preview_frame = UIWidget.create_definition(_terminal_frame_passes(8), "preview_area"),
        preview_background_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "preview_background_button", { text = "" }, nil, { text = { font_size = PREVIEW_BUTTON_FONT_SIZE } }),
        preview_zoom_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "preview_zoom_button", { text = "" }, nil, { text = { font_size = PREVIEW_BUTTON_FONT_SIZE } }),
        preview_aspect_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "preview_aspect_button", { text = "" }, nil, { text = { font_size = PREVIEW_BUTTON_FONT_SIZE } }),
        inspector_metadata = UIWidget.create_definition(_text_passes(metadata_style), "inspector_metadata"),
        inspector_empty = UIWidget.create_definition(_text_passes(clone(empty_style)), "inspector_empty", {
            text = mod:localize("inspector_no_selection"),
        }),
        copy_path_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button, "copy_path_button", {
            original_text = upper(mod:localize("action_copy_path")),
        }),
        copy_filename_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "copy_filename_button", { text = upper(mod:localize("action_copy_filename")) }, nil,
            { text = { font_size = SECONDARY_BUTTON_FONT_SIZE } }),
        copy_lua_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small, "copy_lua_button", {
            text = upper(mod:localize("action_copy_lua_string")),
        }, nil, { text = { font_size = SECONDARY_BUTTON_FONT_SIZE } }),
        copy_snippet_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "copy_snippet_button", { text = upper(mod:localize("action_copy_ui_snippet")) }, nil,
            { text = { font_size = SECONDARY_BUTTON_FONT_SIZE } }),
        copy_sources_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small,
            "copy_sources_button", { text = upper(mod:localize("action_copy_sources")) }, nil,
            { text = { font_size = SECONDARY_BUTTON_FONT_SIZE } }),
        favorite_button = UIWidget.create_definition(ButtonPassTemplates.terminal_button_small, "favorite_button", {
            text = "",
        }, nil, { text = { font_size = SECONDARY_BUTTON_FONT_SIZE } }),
        status_divider = UIWidget.create_definition({
            {
                pass_type = "rect",
                style = { color = clone(PALETTE.divider), size = { nil, 1 }, offset = { 0, 0, 0 } },
            },
        }, "status_bar"),
        hint_text = UIWidget.create_definition(_text_passes(hint_style), "hint_text", {
            text = mod:localize("shortcut_hint"),
        }),
        popup_background = UIWidget.create_definition(_append({
            { pass_type = "rect", style = { color = clone(PALETTE.tooltip_background), offset = { 0, 0, 0 } } },
        }, _terminal_frame_passes(1)), "popup"),
        tooltip = UIWidget.create_definition(_append({
            { pass_type = "rect", style = { color = clone(PALETTE.tooltip_background), offset = { 0, 0, 0 } } },
            { pass_type = "text", style_id = "text", value_id = "text", value = "", style = tooltip_style },
        }, _terminal_frame_passes(1)), "tooltip"),
    }

    return {
        scenegraph_definition = scenegraph_definition,
        widget_definitions = widget_definitions,
        preview_widget_definitions = Definitions.preview_widget_definitions(),
        legend_inputs = {
            {
                input_action = "back",
                on_pressed_callback = "cb_on_back_pressed",
                display_name = "loc_settings_menu_close_menu",
                alignment = "left_alignment",
            },
            {
                input_action = "confirm_pressed",
                on_pressed_callback = "cb_on_select_pressed",
                display_name = "loc_icon_browser_legend_select",
                alignment = "right_alignment",
                visibility_function = function(parent)
                    return parent:legend_select_visible()
                end,
            },
            {
                input_action = "hotkey_item_customize",
                on_pressed_callback = "cb_on_copy_hotkey_pressed",
                display_name = "loc_icon_browser_legend_copy_path",
                alignment = "right_alignment",
                visibility_function = function(parent)
                    return parent:legend_copy_visible()
                end,
            },
            {
                input_action = "hotkey_item_favorite",
                on_pressed_callback = "cb_on_favorite_hotkey_pressed",
                display_name = "loc_icon_browser_legend_favorite",
                alignment = "right_alignment",
                visibility_function = function(parent)
                    return parent:legend_favorite_visible()
                end,
            },
        },
    }
end

--- Inspector preview widgets, drawn by the view inside `pcall` because the icon is an indexed material.
-- The checkerboard has one light base rect and a dark rect per dark cell, which the view sizes when
-- the preview area changes; the icon is a `texture_uv` pass whose `uvs` the zoom control sets.
-- treturn: tab widget definitions by name: `preview_background`, `preview_checker`, `preview_icon`
-- and `preview_fallback`
function Definitions.preview_widget_definitions()
    local fallback_style = _text_style(FONT_BODY, 18, PALETTE.text_sub_header, "center", "center")
    local checker_passes = {
        {
            pass_type = "rect",
            style_id = "base",
            style = { color = clone(PALETTE.checker_light), offset = { 0, 0, 0 } },
        },
    }
    local cells = Definitions.CHECKER_CELLS

    fallback_style.offset = { 0, 0, 6 }

    for i = 1, cells * cells / 2 do
        checker_passes[#checker_passes + 1] = {
            pass_type = "rect",
            style_id = "cell_" .. i,
            style = { color = clone(PALETTE.checker_dark), size = { 1, 1 }, offset = { 0, 0, 1 } },
        }
    end

    return {
        preview_background = UIWidget.create_definition({
            { pass_type = "rect", style_id = "background", style = { color = clone(PALETTE.preview_dark) } },
        }, "preview_area"),
        preview_checker = UIWidget.create_definition(checker_passes, "preview_area"),
        preview_icon = UIWidget.create_definition({
            {
                pass_type = "texture_uv",
                style_id = "icon",
                value_id = "icon",
                value = "",
                style = {
                    color = { 255, 255, 255, 255 },
                    uvs = { { 0, 0 }, { 1, 1 } },
                    offset = { 0, 0, 1 },
                },
                visibility_function = _icon_visibility_function,
            },
        }, "preview_icon"),
        preview_fallback = UIWidget.create_definition({
            {
                pass_type = "text",
                style_id = "text",
                value_id = "text",
                value = mod:localize("preview_unavailable"),
                style = fallback_style,
                visibility_function = _fallback_visibility_function,
            },
        }, "preview_area"),
    }
end

-- ----------------------------------------------------------------------------
-- Slot builders (called on layout changes only)
-- ----------------------------------------------------------------------------

--- Grid tile: centred preview box, short label, gold favorite marker, terminal frame and corners.
-- The view binds `content.icon`, `content.label`, the fallback text and its colour (red while the
-- material is not loaded) and the state flags `has_asset`, `icon_available`,
-- `is_selected`, `is_focused` and `is_favorite`.
-- number: width tile width in UI units
-- number: height tile height in UI units
-- tab: density entry of `DENSITIES`
-- treturn: tab widget definition
function Definitions.tile_definition(width, height, density)
    local padding = density.padding
    local label_height = density.label
    local preview_width = width - padding * 2
    local preview_height = height - label_height - padding * 2
    local icon_size = min(preview_width, preview_height) - 8
    local icon_x = padding + floor((preview_width - icon_size) / 2)
    local icon_y = padding + floor((preview_height - icon_size) / 2)
    local label_style = _text_style(FONT_BODY, density.font, PALETTE.text_body, "center", "center")
    local fallback_style = _text_style(FONT_BODY, density.font - 2, PALETTE.text_body_dark, "center", "center")

    label_style.size = { width - padding * 2, label_height }
    label_style.offset = { padding, height - label_height - floor(padding / 2), 5 }
    label_style.hover_color = PALETTE.text_header
    label_style.focus_color = PALETTE.text_header
    label_style.selected_color = PALETTE.text_header_selected
    fallback_style.size = { preview_width, preview_height }
    fallback_style.offset = { padding, padding, 4 }

    return UIWidget.create_definition({
        {
            pass_type = "hotspot",
            content_id = "hotspot",
            content = clone(HOTSPOT_CONTENT),
        },
        {
            pass_type = "texture",
            style_id = "background",
            value = MATERIAL_SQUARE,
            style = _state_colors({ offset = { 0, 0, 0 } }, PALETTE.tile_background, PALETTE.tile_background_hover,
                PALETTE.tile_background_focus, PALETTE.tile_background_selected),
            change_function = _slot_state_change_function,
        },
        {
            pass_type = "texture",
            style_id = "gradient",
            value = MATERIAL_GRADIENT,
            style = _state_colors({ offset = { 0, 0, 1 } }, PALETTE.gradient, PALETTE.gradient_hover,
                PALETTE.gradient_hover, PALETTE.gradient_selected),
            change_function = _slot_state_change_function,
        },
        {
            pass_type = "rect",
            style_id = "preview_backing",
            style = {
                size = { preview_width, preview_height },
                offset = { padding, padding, 2 },
                color = clone(PALETTE.preview_backing),
            },
        },
        {
            pass_type = "texture",
            style_id = "icon",
            value_id = "icon",
            value = "",
            style = {
                size = { icon_size, icon_size },
                offset = { icon_x, icon_y, 3 },
                color = { 255, 255, 255, 255 },
            },
            visibility_function = _icon_visibility_function,
        },
        {
            pass_type = "text",
            style_id = "fallback",
            value_id = "fallback_text",
            value = mod:localize("preview_unavailable_short"),
            style = fallback_style,
            visibility_function = _fallback_visibility_function,
        },
        {
            pass_type = "text",
            style_id = "label",
            value_id = "label",
            value = "",
            style = label_style,
            change_function = _slot_state_change_function,
        },
        {
            pass_type = "rect",
            style_id = "favorite",
            style = {
                size = { 10, 10 },
                offset = { width - 15, 5, 6 },
                color = clone(PALETTE.favorite),
            },
            visibility_function = _favorite_visibility_function,
        },
        {
            pass_type = "texture",
            style_id = "frame",
            value = MATERIAL_FRAME,
            style = _state_colors({ offset = { 0, 0, 7 } }, PALETTE.frame, PALETTE.frame_hover, PALETTE.frame_focus,
                PALETTE.frame_selected),
            change_function = _slot_state_change_function,
        },
        {
            pass_type = "texture",
            style_id = "corner",
            value = MATERIAL_CORNER,
            style = _state_colors({ offset = { 0, 0, 8 } }, PALETTE.corner, PALETTE.corner_hover, PALETTE.corner_focus,
                PALETTE.corner_selected),
            change_function = _slot_state_change_function,
        },
    }, "browser_area", nil, { width, height })
end

--- List row; `columns` holds x and width per column, as the view computed them for this layout.
-- The view binds `content.icon`, `content.name`, `content.id_text`, `content.category`,
-- `content.path` and the same state flags as a tile, plus `is_odd` for the alternating background.
-- number: width row width in UI units
-- number: height row height in UI units
-- tab: columns column layout with `*_x` and `*_width` per column of `LIST_COLUMNS`
-- tab: density entry of `DENSITIES`
-- treturn: tab widget definition
function Definitions.list_row_definition(width, height, columns, density)
    local font_size = density.row_font
    local preview_size = height - 8
    local icon_size = preview_size - 6
    local name_style = _text_style(FONT_BODY, font_size, PALETTE.text_header, "left", "center")
    local id_style = _text_style(FONT_BODY, font_size - 1, PALETTE.text_key_value, "left", "center")
    local category_style = _text_style(FONT_BODY, font_size - 2, PALETTE.text_sub_header, "left", "center")
    local path_style = _text_style(FONT_BODY, font_size - 2, PALETTE.text_body, "left", "center")
    local fallback_style = _text_style(FONT_BODY, 12, PALETTE.text_body_dark, "center", "center")

    name_style.size = { columns.name_width, height }
    name_style.offset = { columns.name_x, 0, 4 }
    name_style.hover_color = PALETTE.text_header_selected
    name_style.focus_color = PALETTE.text_header_selected
    name_style.selected_color = PALETTE.text_header_selected
    id_style.size = { columns.id_width, height }
    id_style.offset = { columns.id_x, 0, 4 }
    category_style.size = { columns.category_width, height }
    category_style.offset = { columns.category_x, 0, 4 }
    path_style.size = { columns.path_width, height }
    path_style.offset = { columns.path_x, 0, 4 }
    fallback_style.size = { preview_size, preview_size }
    fallback_style.offset = { columns.preview_x, 4, 4 }

    return UIWidget.create_definition({
        {
            pass_type = "hotspot",
            content_id = "hotspot",
            content = clone(HOTSPOT_CONTENT),
        },
        {
            pass_type = "rect",
            style_id = "background",
            style = _state_colors({ offset = { 0, 0, 0 } }, PALETTE.row_even, PALETTE.row_hover, PALETTE.row_focus,
                PALETTE.row_selected),
            change_function = function(content, style)
                local color

                if content.is_selected then
                    color = style.selected_color
                elseif content.is_focused then
                    color = style.focus_color
                elseif content.hotspot.is_hover then
                    color = style.hover_color
                elseif content.is_odd then
                    color = PALETTE.row_odd
                end

                _copy_color(color or style.default_color, style.color)
            end,
        },
        {
            pass_type = "rect",
            style_id = "selected_bar",
            style = {
                size = { 4, height },
                offset = { 0, 0, 2 },
                color = clone(PALETTE.corner_selected),
            },
            visibility_function = function(content)
                return content.is_selected
            end,
        },
        {
            pass_type = "rect",
            style_id = "focus_bar",
            style = {
                size = { 4, height },
                offset = { 0, 0, 2 },
                color = clone(PALETTE.corner_focus),
            },
            visibility_function = function(content)
                return content.is_focused and not content.is_selected
            end,
        },
        {
            pass_type = "rect",
            style_id = "preview_backing",
            style = {
                size = { preview_size, preview_size },
                offset = { columns.preview_x, 4, 2 },
                color = clone(PALETTE.preview_backing),
            },
        },
        {
            pass_type = "texture",
            style_id = "icon",
            value_id = "icon",
            value = "",
            style = {
                size = { icon_size, icon_size },
                offset = { columns.preview_x + 3, 7, 3 },
                color = { 255, 255, 255, 255 },
            },
            visibility_function = _icon_visibility_function,
        },
        {
            pass_type = "text",
            style_id = "fallback",
            value_id = "fallback_text",
            value = mod:localize("preview_unavailable_short"),
            style = fallback_style,
            visibility_function = _fallback_visibility_function,
        },
        {
            pass_type = "text",
            style_id = "name",
            value_id = "name",
            value = "",
            style = name_style,
            change_function = _slot_state_change_function,
        },
        {
            pass_type = "text",
            style_id = "id",
            value_id = "id_text",
            value = "",
            style = id_style,
        },
        {
            pass_type = "text",
            style_id = "category",
            value_id = "category",
            value = "",
            style = category_style,
        },
        {
            pass_type = "text",
            style_id = "path",
            value_id = "path",
            value = "",
            style = path_style,
        },
        {
            pass_type = "rect",
            style_id = "favorite",
            style = {
                size = { 8, 8 },
                offset = { columns.preview_x + preview_size - 10, 6, 5 },
                color = clone(PALETTE.favorite),
            },
            visibility_function = _favorite_visibility_function,
        },
    }, "browser_area", nil, { width, height })
end

--- Popup menu option; `content.is_selected` marks the active value.
-- number: width option width in UI units
-- number: height option height in UI units
-- treturn: tab widget definition
function Definitions.option_definition(width, height)
    local text_style = _text_style(FONT_BODY, 19, PALETTE.text_body, "left", "center")

    text_style.size = { width - 32, height }
    text_style.offset = { 18, 0, 3 }
    text_style.hover_color = PALETTE.text_header_selected
    text_style.focus_color = PALETTE.text_header_selected
    text_style.selected_color = PALETTE.text_header_selected

    return UIWidget.create_definition({
        {
            pass_type = "hotspot",
            content_id = "hotspot",
            content = clone(HOTSPOT_CONTENT),
        },
        {
            pass_type = "rect",
            style_id = "background",
            style = _state_colors({ offset = { 0, 0, 1 } }, PALETTE.transparent, PALETTE.option_hover,
                PALETTE.option_hover, PALETTE.option_selected),
            change_function = _slot_state_change_function,
        },
        {
            pass_type = "rect",
            style_id = "selected_bar",
            style = {
                size = { 4, height },
                offset = { 0, 0, 2 },
                color = clone(PALETTE.corner_selected),
            },
            visibility_function = function(content)
                return content.is_selected
            end,
        },
        {
            pass_type = "text",
            style_id = "text",
            value_id = "text",
            value = "",
            style = text_style,
            change_function = _slot_state_change_function,
        },
    }, "popup", nil, { width, height })
end

return Definitions
