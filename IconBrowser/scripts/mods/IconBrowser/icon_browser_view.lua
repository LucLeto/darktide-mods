--- The Icon Browser view; a full-screen, terminal-style browser of the indexed UI materials.
-- A `BaseView` laid out from the screen size in UI units: the frame takes about 95 % of the width
-- and ends just above the game's input legend, shrunk by the Window Size setting and moved by the
-- offsets, which are clamped so it stays on screen. It holds a header with the title, status, asset
-- count and toolbar (search field, category and sort menus, favorites and recent filters, grid/list
-- and density toggles), the asset browser and a persistent inspector with preview, metadata, the
-- asset's source references (the script lines and items that use it, and the size the game draws
-- it at, which the preview's `auto` aspect follows) and copy actions. Its Related menu lists the
-- asset's family, folder, filename twins and the scripts naming it, with counts, and applies the chosen
-- one as an `in:`, `family:`, `filename:` or `file:` filter in the search field.
--
-- The browser is virtualized: a pool of slot widgets covering the visible cells is rebuilt only when
-- the slot geometry changes and rebound to the window of query results the scrollbar shows, with
-- row-snapped scrolling. A click selects an asset, which fills the inspector; copying is explicit
-- (inspector buttons, double-click, Ctrl+C or C). Ctrl+click, Shift+click and Ctrl+A select several
-- assets; the inspector then previews the one clicked last, lists the selection and copies all of
-- them at once (paths, filenames, a Lua array or a Lua table keyed by filename). Arrow keys move a
-- keyboard focus that Enter selects, Ctrl+F focuses the search field, F toggles the favorite, and
-- Esc leaves the search field, then an open menu, then a multi-selection, then the view; no
-- shortcut fires while the search field has focus.
--
-- Every widget that draws an indexed material (tiles, list rows, the inspector preview) is drawn
-- inside `pcall`; a failing material is reported once through `mod.mark_icon_render_failed`, shown
-- with a fallback and stays selectable and copyable. A material the engine has not loaded raises no
-- error but would draw as a white square, so it is not drawn and its fallback says so in red; while
-- a global game package requested in the main menu still loads, the fallback says "loading" instead,
-- and every state is checked again once it has loaded.
-- Chrome widgets are drawn inside `pcall` as well, so a missing shared material only hides that
-- widget.
--
-- Loaded through the `package.preload` loader that `IconBrowser.lua` registers for the view's
-- module path, and returned as the `IconBrowserView` class. Reads the asset model from
-- `mod._assets`, the query module from `mod._query_module`, its look from
-- `icon_browser_view_definitions.lua`, and its settings, favorites, history and session state
-- through the functions and fields on `mod`.
-- classmod: IconBrowserView
-- author: LucLeto
local mod = get_mod("IconBrowser")

local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")

--- The view's look and structure, and the asset and query modules loaded by `IconBrowser.lua`.
local Definitions = mod:io_dofile("IconBrowser/scripts/mods/IconBrowser/icon_browser_view_definitions")
local Assets = mod._assets_module
local Query = mod._query_module

local concat = table.concat
local floor = math.floor
local format = string.format
local gmatch = string.gmatch
local gsub = string.gsub
local match = string.match
local max = math.max
local min = math.min
local pcall = pcall
local pairs = pairs
local table_clear = table.clear
local tostring = tostring
local type = type

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Definition tables and helpers shared with `icon_browser_view_definitions.lua`, and the
-- upper-case function for titles.
local LAYOUT = Definitions.LAYOUT
local DENSITIES = Definitions.DENSITIES
local PALETTE = Definitions.PALETTE
local ASPECTS = Definitions.ASPECTS
local ZOOM_LEVELS = Definitions.ZOOM_LEVELS
local PREVIEW_BACKGROUNDS = Definitions.PREVIEW_BACKGROUNDS
local TOOLBAR_NODES = Definitions.TOOLBAR_NODES
local copy_color = Definitions.copy_color
local upper = Utf8 and Utf8.upper or string.upper

--- Name of the view, as `IconBrowser.lua` registers it.
local VIEW_NAME = "icon_browser_view"
--- Seconds a status message stays in the header, and the last part of it in which it fades out.
local COPY_STATUS_DURATION = 2
local COPY_STATUS_FADE_DURATION = 0.25
--- Seconds an asset must stay hovered before its tooltip shows.
local TOOLTIP_DELAY = 0.4
--- Ctrl+F focuses the search field this many updates later, so the "f" keystroke of the shortcut
-- is consumed before the text field starts reading keystrokes.
local SEARCH_FOCUS_DELAY = 2
--- Rows scrolled per mouse wheel notch in the grid and in the list.
local GRID_ROWS_PER_SCROLL = 1
local LIST_ROWS_PER_SCROLL = 3
--- One wheel notch moves `scroll_amount * 0.8 / 1.5` of the range in the terminal scrollbar.
local SCROLL_NOTCH_FACTOR = 1.875
--- Ellipsis appended to cropped text.
local CROP_SUFFIX = "..."
--- Slack in UI units between the measured text and its box, so measuring and drawing can never
-- disagree about a line fitting.
local CROP_MARGIN = 4
--- Usage sizes listed in the inspector's size line; the copied references hold every source.
local MAX_METADATA_SIZES = 3

--- Widths of the toolbar controls, in the order of `TOOLBAR_NODES`.
local TOOLBAR_WIDTHS = {
    LAYOUT.toolbar.category,
    LAYOUT.toolbar.sort,
    LAYOUT.toolbar.favorites,
    LAYOUT.toolbar.recent,
    LAYOUT.toolbar.recent_clear,
    LAYOUT.toolbar.view,
    LAYOUT.toolbar.view,
    LAYOUT.toolbar.density,
    LAYOUT.toolbar.density,
    LAYOUT.toolbar.density,
}

--- Inspector widgets shown only while an asset is selected.
local INSPECTOR_CONTENT_WIDGETS = {
    "inspector_title",
    "inspector_subtitle",
    "inspector_metadata",
    "preview_frame",
    "preview_background_button",
    "preview_zoom_button",
    "preview_aspect_button",
}

--- Inspector buttons disabled while no asset is selected.
local INSPECTOR_ACTION_WIDGETS = {
    "copy_path_button",
    "copy_filename_button",
    "copy_lua_button",
    "copy_snippet_button",
    "copy_sources_button",
    "favorite_button",
    "related_button",
}

--- Script files listed in the Related menu at most, and the menu's width range in UI units.
local MAX_RELATED_FILES = 6
local RELATED_MIN_WIDTH = 320
local RELATED_MAX_WIDTH = 640
--- Empty favorites and recent lookups for counting relations without those filters.
local EMPTY_LOOKUP = {}

--- Widgets of the list column header, shown only in the list view.
local LIST_HEADER_WIDGETS = {
    "list_header_background",
    "list_header_preview",
    "list_header_name",
    "list_header_id",
    "list_header_category",
    "list_header_path",
}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

--- Text markup that colours the text after it, up to `RESET_TAG`.
-- tab: color `{ a, r, g, b }` colour
-- treturn: string
local function _color_tag(color)
    return format("{#color(%d,%d,%d)}", color[2], color[3], color[4])
end

--- Colour markup of the inspector metadata: field labels, values, warnings, and the reset.
local LABEL_TAG = _color_tag(PALETTE.text_sub_header)
local VALUE_TAG = _color_tag(PALETTE.text_header)
local WARNING_TAG = _color_tag(PALETTE.status_error)
local RESET_TAG = "{#reset()}"

--- Clamps a value into a range.
-- number: value value to clamp
-- number: min_value lower bound
-- number: max_value upper bound
-- treturn: number
local function _clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    elseif value > max_value then
        return max_value
    end

    return value
end

--- Sets a slot's or the preview's fallback text: the regular "no preview" text for a loaded material,
-- "loading" while a game package that may carry it still loads, both in the default colour, and
-- "not available" in red for a material that is not loaded.
-- tab: content widget content
-- string: text_id content field of the fallback text
-- tab: style fallback text style
-- tab: texts `default`, `loading` and `not_loaded` texts
-- bool: loaded whether the material is loaded
-- bool: loading whether a game package that may carry it is still loading
local function _set_fallback(content, text_id, style, texts, loaded, loading)
    if loaded then
        content[text_id] = texts.default
        copy_color(style.default_color, style.text_color)
    elseif loading then
        content[text_id] = texts.loading
        copy_color(style.default_color, style.text_color)
    else
        content[text_id] = texts.not_loaded
        copy_color(PALETTE.status_error, style.text_color)
    end
end

--- Keyboard indices cached by `_keyboard_keys_lookup`; nil until its first call.
local _keyboard_keys

--- Returns a keyboard index, or false when the engine does not know the key.
-- func: button_index `Keyboard.button_index`
-- string: name key name
-- treturn: int|bool
local function _optional_key(button_index, name)
    local ok, index = pcall(button_index, name)

    return ok and index or false
end

--- Raw keyboard indices for Ctrl+F / Ctrl+C / Ctrl+A and the Ctrl and Shift modifiers of a click,
-- resolved once; `false` when the engine API is missing. A missing right Ctrl or Shift key only
-- disables that key, a missing A key only Ctrl+A.
-- treturn: tab|bool `left_ctrl`, `right_ctrl`, `left_shift`, `right_shift`, `f`, `c` and `a`
-- indices, or false
local function _keyboard_keys_lookup()
    if _keyboard_keys == nil then
        _keyboard_keys = false

        local keyboard = Keyboard
        local button_index = keyboard and keyboard.button_index

        if button_index then
            local ok, left_ctrl, key_f, key_c = pcall(function()
                return button_index("left ctrl"), button_index("f"), button_index("c")
            end)

            if ok and left_ctrl and key_f and key_c then
                _keyboard_keys = {
                    left_ctrl = left_ctrl,
                    right_ctrl = _optional_key(button_index, "right ctrl"),
                    left_shift = _optional_key(button_index, "left shift"),
                    right_shift = _optional_key(button_index, "right shift"),
                    f = key_f,
                    c = key_c,
                    a = _optional_key(button_index, "a"),
                }
            end
        end
    end

    return _keyboard_keys
end

--- Returns whether either of two keys is held.
-- int|bool: left_key keyboard index, or false
-- int|bool: right_key keyboard index, or false
-- treturn: bool
local function _either_down(left_key, right_key)
    local keyboard = Keyboard

    return left_key and keyboard.button(left_key) > 0.5 or right_key and keyboard.button(right_key) > 0.5 or false
end

--- Returns whether either Ctrl key is held.
-- tab: keys indices from `_keyboard_keys_lookup`
-- treturn: bool
local function _ctrl_down(keys)
    return _either_down(keys.left_ctrl, keys.right_ctrl)
end

--- Returns whether either Shift key is held.
-- tab: keys indices from `_keyboard_keys_lookup`
-- treturn: bool
local function _shift_down(keys)
    return _either_down(keys.left_shift, keys.right_shift)
end

--- The view class.
local IconBrowserView = class("IconBrowserView", "BaseView")

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------

--- Creates the view's definitions and state; its widgets only exist from `on_enter` on.
-- tab: settings view settings from `Views`
IconBrowserView.init = function(self, settings)
    local definitions = Definitions.create(upper)

    IconBrowserView.super.init(self, definitions, settings)

    self._assets = mod.get_icon_assets()
    self._query_state = Query.new_state()
    self._query_cache = Query.new_cache()
    self._results = {}
    self._result_count = 0
    self._results_dirty = true
    self._reset_scroll = true
    self._keep_selection_visible = false

    self._slots = {}
    self._slot_count = 0
    self._slot_kind = false
    self._slot_width = 0
    self._slot_height = 0
    self._slot_density = false
    self._columns = 1
    self._visible_rows = 1
    self._row_pitch = 1
    self._column_pitch = 1
    self._max_first_row = 0
    self._first_row = -1
    self._bind_dirty = true
    self._label_cache = {}
    self._name_cache = {}
    self._category_cache = {}
    self._path_cache = {}
    self._material_loaded = {}
    self._global_packages_loading = false
    self._fallback_texts = {
        short = {
            default = mod:localize("preview_unavailable_short"),
            loading = mod:localize("preview_loading_short"),
            not_loaded = mod:localize("preview_not_loaded_short"),
        },
        long = {
            default = mod:localize("preview_unavailable"),
            loading = mod:localize("preview_loading"),
            not_loaded = mod:localize("preview_not_loaded"),
        },
    }
    self._list_columns = {
        preview_x = 0,
        preview_width = 0,
        name_x = 0,
        name_width = 0,
        id_x = 0,
        id_width = 0,
        category_x = 0,
        category_width = 0,
        path_x = 0,
        path_width = 0,
    }
    self._layout = {
        frame_width = 0,
        frame_height = 0,
        browser_x = 0,
        browser_y = 0,
        area_x = 0,
        area_y = 0,
        area_width = 0,
        area_height = 0,
        status_y = 0,
        preview_width = 0,
        preview_height = 0,
        metadata_width = 0,
    }
    self._applied_layout_revision = -1
    self._view_mode = "grid"
    self._density = "normal"
    self._double_click_copy = true
    self._copy_hotkey_enabled = true
    self._widget_count = 0
    self._entered_browser = false

    self._selected_asset = nil
    self._selection = {}
    self._selection_list = {}
    self._selection_count = 0
    self._selection_anchor = nil
    self._selection_ordered = {}
    self._focus_asset = nil
    self._focus_index = nil
    self._icon_lists_revision = -1

    self._open_popup = nil
    self._swallow_input = false
    self._popup_options = { category = {}, sort = {}, related = {} }
    self._popup_option_counts = { category = 0, sort = 0, related = 0 }
    self._popup_widths = { category = 0, sort = 0, related = 0 }
    self._related_tokens = {}
    self._related_state = Query.new_state()
    self._related_results = {}
    self._related_result_count = 0

    self._preview_widgets = {}
    self._preview_background = "dark"
    self._preview_zoom_index = 1
    self._preview_aspect_index = 1
    self._inspector_dirty = true
    self._metadata_lines = {}

    self._hovered_asset = nil
    self._hovered_slot = nil
    self._tooltip_asset = nil
    self._tooltip_timer = 0
    self._tooltip_shown = false

    self._search_content = nil
    self._pending_search_focus = 0
    self._was_writing = false

    self._copy_status_message = ""
    self._copy_status_is_error = false
    self._copy_status_timer = 0
    self._status_text = {
        path = mod:localize("status_copied_path"),
        filename = mod:localize("status_copied_filename"),
        lua_string = mod:localize("status_copied_lua_string"),
        ui_snippet = mod:localize("status_copied_ui_snippet"),
        sources = mod:localize("status_copied_sources"),
        failed = mod:localize("status_copy_failed"),
        favorite_added = mod:localize("status_favorite_added"),
        favorite_removed = mod:localize("status_favorite_removed"),
        recent_cleared = mod:localize("status_recent_cleared"),
    }
    -- labels of the copy and favorite buttons for one selected asset and for several
    self._action_texts = {
        filename = upper(mod:localize("action_copy_filename")),
        lua_string = upper(mod:localize("action_copy_lua_string")),
        ui_snippet = upper(mod:localize("action_copy_ui_snippet")),
        filenames = upper(mod:localize("action_copy_filenames")),
        lua_array = upper(mod:localize("action_copy_lua_array")),
        lua_table = upper(mod:localize("action_copy_lua_table")),
        favorite_add = upper(mod:localize("action_favorite_add")),
        favorite_remove = upper(mod:localize("action_favorite_remove")),
        favorite_add_all = upper(mod:localize("action_favorite_add_all")),
        favorite_remove_all = upper(mod:localize("action_favorite_remove_all")),
    }
    self._field_labels = {
        path = LABEL_TAG .. upper(mod:localize("field_path")) .. RESET_TAG,
        filename = LABEL_TAG .. mod:localize("field_filename") .. RESET_TAG .. "  ",
        id = LABEL_TAG .. mod:localize("field_id") .. RESET_TAG .. "  ",
        category = LABEL_TAG .. mod:localize("field_category") .. RESET_TAG .. "  ",
        name = LABEL_TAG .. mod:localize("field_name_source") .. RESET_TAG .. "  ",
        preview = LABEL_TAG .. mod:localize("field_preview") .. RESET_TAG .. "  ",
        size = LABEL_TAG .. mod:localize("field_size") .. RESET_TAG .. "  ",
        used_in = LABEL_TAG .. mod:localize("field_used_in") .. RESET_TAG .. "  ",
        items = LABEL_TAG .. mod:localize("field_items") .. RESET_TAG .. "  ",
    }
    self._field_label_texts = {
        size = mod:localize("field_size") .. "  ",
        used_in = mod:localize("field_used_in") .. "  ",
        items = mod:localize("field_items") .. "  ",
    }
end

--- Sets up the legend, the preview widgets and the callbacks, resolves the localized names on the
-- first opening, restores the saved filters, search text and selection, and applies the layout.
function IconBrowserView.on_enter(self)
    IconBrowserView.super.on_enter(self)
    mod._icon_browser_view_open = true

    local widgets_by_name = self._widgets_by_name

    self._widget_count = #self._widgets
    self._search_content = widgets_by_name.search_input.content
    widgets_by_name.scrollbar.style.mouse_scroll.scenegraph_id = "browser_area"
    widgets_by_name.popup_background.visible = false
    widgets_by_name.tooltip.visible = false

    self:_setup_input_legend()
    self:_create_preview_widgets()
    self:_setup_callbacks()
    self._global_packages_loading = mod.are_global_icon_packages_loading()
    Assets.attach_sources(self._assets, mod.get_icon_sources())
    Assets.resolve_names(self._assets)
    self:_restore_state()
    self._entered_browser = true
    self:_apply_layout(true)

    self._copy_status_message = ""
    self._copy_status_is_error = false
    self._copy_status_timer = 0
    self:_update_copy_status_widget()
end

--- Saves the session state, destroys the slot, menu and preview widgets, writes changed favorites
-- and history to disk, and removes the input legend.
function IconBrowserView.on_exit(self)
    mod._icon_browser_view_open = false

    if self._entered_browser then
        local session = mod._icon_browser_session
        local state = self._query_state
        local selected_asset = self._selected_asset

        session.query = state.text
        session.selected_path = selected_asset and selected_asset.path or false
        session.favorites_only = state.favorites_only
        session.recent_only = state.recent_only

        if self._was_writing then
            self:_set_ime_enabled(false)
        end
    end

    self:_destroy_slots()
    self:_destroy_popup_options()
    self:_destroy_preview_widgets()
    mod.save_icon_lists_if_dirty()

    if self._input_legend_element then
        self:_remove_element("input_legend")
        self._input_legend_element = nil
    end

    IconBrowserView.super.on_exit(self)
end

--- Re-applies the layout after the resolution or the UI scale changed.
-- number: scale new render scale
function IconBrowserView.on_resolution_modified(self, scale)
    IconBrowserView.super.on_resolution_modified(self, scale)

    if self._entered_browser then
        self:_apply_layout(true)
    end
end

-- ----------------------------------------------------------------------------
-- Setup
-- ----------------------------------------------------------------------------

--- Adds the input legend with the entries from the definitions; an entry with a visibility function
-- is hidden, and its hotkey ignored, while that function returns false.
function IconBrowserView._setup_input_legend(self)
    local input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)
    local legend_inputs = self._definitions.legend_inputs

    self._input_legend_element = input_legend_element

    for i = 1, #legend_inputs do
        local entry = legend_inputs[i]
        input_legend_element:add_entry(
            entry.display_name,
            entry.input_action,
            entry.visibility_function,
            entry.on_pressed_callback and callback(self, entry.on_pressed_callback),
            entry.alignment
        )
    end
end

--- Creates the inspector preview widgets, which `draw` renders itself inside `pcall`.
function IconBrowserView._create_preview_widgets(self)
    local preview_widgets = self._preview_widgets

    for name, definition in pairs(self._definitions.preview_widget_definitions) do
        preview_widgets[name] = UIWidget.init(name, definition)
    end

    local preview_content = preview_widgets.preview_icon.content
    local fallback_content = preview_widgets.preview_fallback.content

    preview_content.icon_available = false
    preview_content.has_asset = false
    fallback_content.icon_available = false
    fallback_content.has_asset = false
end

--- Destroys the inspector preview widgets.
function IconBrowserView._destroy_preview_widgets(self)
    local ui_renderer = self._ui_renderer
    local preview_widgets = self._preview_widgets

    for name, widget in pairs(preview_widgets) do
        UIWidget.destroy(ui_renderer, widget)
        preview_widgets[name] = nil
    end
end

--- Sets a button's pressed callback to a method of the view.
-- string: widget_name name of the button widget
-- string: callback_name method name
-- ?param: argument value bound as the method's first argument
function IconBrowserView._bind_button(self, widget_name, callback_name, argument)
    local hotspot = self._widgets_by_name[widget_name].content.hotspot

    if argument ~= nil then
        hotspot.pressed_callback = callback(self, callback_name, argument)
    else
        hotspot.pressed_callback = callback(self, callback_name)
    end
end

--- Binds the toolbar, list header, preview control and inspector buttons to their callbacks.
function IconBrowserView._setup_callbacks(self)
    self:_bind_button("search_clear", "cb_on_clear_search_pressed")
    self:_bind_button("category_button", "cb_on_dropdown_pressed", "category")
    self:_bind_button("sort_button", "cb_on_dropdown_pressed", "sort")
    self:_bind_button("favorites_button", "cb_on_favorites_filter_pressed")
    self:_bind_button("recent_button", "cb_on_recent_filter_pressed")
    self:_bind_button("recent_clear_button", "cb_on_clear_recent_pressed")
    self:_bind_button("view_grid_button", "cb_on_view_mode_pressed", "grid")
    self:_bind_button("view_list_button", "cb_on_view_mode_pressed", "list")
    self:_bind_button("density_compact_button", "cb_on_density_pressed", "compact")
    self:_bind_button("density_normal_button", "cb_on_density_pressed", "normal")
    self:_bind_button("density_large_button", "cb_on_density_pressed", "large")
    self:_bind_button("list_header_name", "cb_on_column_pressed", "name")
    self:_bind_button("list_header_id", "cb_on_column_pressed", "index")
    self:_bind_button("list_header_category", "cb_on_column_pressed", "category")
    self:_bind_button("list_header_path", "cb_on_column_pressed", "path")
    self:_bind_button("preview_background_button", "cb_on_preview_background_pressed")
    self:_bind_button("preview_zoom_button", "cb_on_preview_zoom_pressed")
    self:_bind_button("preview_aspect_button", "cb_on_preview_aspect_pressed")
    self:_bind_button("copy_path_button", "cb_on_copy_pressed", "path")
    self:_bind_button("copy_filename_button", "cb_on_copy_pressed", "filename")
    self:_bind_button("copy_lua_button", "cb_on_copy_pressed", "lua_string")
    self:_bind_button("copy_snippet_button", "cb_on_copy_pressed", "ui_snippet")
    self:_bind_button("copy_sources_button", "cb_on_copy_pressed", "sources")
    self:_bind_button("favorite_button", "cb_on_favorite_pressed")
    self:_bind_button("related_button", "cb_on_related_pressed")
end

--- Restores the persisted filter preferences and the session's search text and selection.
-- The favorites and recent filters exclude each other; a saved selection that is no longer indexed
-- is dropped.
function IconBrowserView._restore_state(self)
    local state = self._query_state
    local session = mod._icon_browser_session
    local search_content = self._search_content
    local query = session.query or ""

    state.category = mod.get_icon_browser_category()
    state.sort = mod.get_icon_browser_sort()
    state.favorites_only = session.favorites_only == true
    state.recent_only = session.recent_only == true and not state.favorites_only
    self._preview_background = mod.get_icon_browser_preview_background()

    search_content.input_text = query
    search_content.caret_position = Utf8.string_length(query) + 1
    Query.set_text(state, query)

    local selected_asset = session.selected_path and self._assets.by_path[session.selected_path] or nil

    self:_select_asset(selected_asset, nil, false)
    self._results_dirty = true
    self._reset_scroll = true
    self._keep_selection_visible = selected_asset ~= nil
    self._inspector_dirty = true
end

-- ----------------------------------------------------------------------------
-- Layout
-- ----------------------------------------------------------------------------

--- Sets a scenegraph node's position and size; callers update the scenegraph afterwards.
-- string: scenegraph_id node id
-- number: x horizontal position relative to the parent
-- number: y vertical position relative to the parent
-- number: width node width
-- number: height node height
function IconBrowserView._place(self, scenegraph_id, x, y, width, height)
    local node = self._ui_scenegraph[scenegraph_id]
    local position = node.position
    local size = node.size

    position[1] = x
    position[2] = y
    size[1] = width
    size[2] = height
end

--- Screen-relative layout: frame, header, browser, inspector and slot pool. Runs on open, on
-- resolution changes and when a layout setting changed (`mod._layout_revision`), never per frame.
-- The frame's minimum height is what the inspector needs, so its controls are never clipped.
-- ?bool: force apply even when the layout revision did not change
function IconBrowserView._apply_layout(self, force)
    local revision = mod._layout_revision

    if not force and revision == self._applied_layout_revision then
        return
    end

    self._applied_layout_revision = revision
    self._view_mode = mod.get_icon_browser_view_mode()
    self._density = mod.get_icon_browser_density()
    self._double_click_copy = mod.is_icon_browser_double_click_copy_enabled()
    self._copy_hotkey_enabled = mod.is_icon_browser_copy_hotkey_enabled()

    local resolution = RESOLUTION_LOOKUP
    local inverse_scale = resolution.inverse_scale or 1
    local screen_width = floor(resolution.width * inverse_scale)
    local screen_height = floor(resolution.height * inverse_scale)
    local size_factor = mod.get_icon_browser_scale() / 100
    local available_height = screen_height - LAYOUT.top_margin - LAYOUT.legend_height - LAYOUT.bottom_gap
    local frame_width = min(screen_width - 16,
        max(LAYOUT.min_frame_width, floor(screen_width * LAYOUT.frame_width_fraction * size_factor)))
    local header_height = self:_layout_header(frame_width)
    local min_frame_height = header_height + LAYOUT.inspector.min_content_height + LAYOUT.status_height + 30
    local frame_height = min(available_height, max(min_frame_height, floor(available_height * size_factor)))
    local max_offset_x = floor((screen_width - frame_width) / 2)
    local offset_x = _clamp(mod.get_icon_browser_offset_x(), -max_offset_x, max_offset_x)
    local min_y = 8
    local max_y = max(min_y, screen_height - LAYOUT.legend_height - frame_height)
    local frame_y = _clamp(LAYOUT.top_margin + floor((available_height - frame_height) / 2) +
        mod.get_icon_browser_offset_y(), min_y, max_y)
    local layout = self._layout
    local padding = LAYOUT.padding
    local inner_width = frame_width - padding * 2

    self:_place("frame", offset_x, frame_y, frame_width, frame_height)
    layout.frame_width = frame_width
    layout.frame_height = frame_height

    local status_y = frame_height - LAYOUT.status_height - 8
    local content_y = header_height + 6
    local content_height = status_y - content_y - 8
    local inspector_width = floor((inner_width - LAYOUT.gap) * mod.get_icon_browser_inspector_width() / 100)

    inspector_width = min(max(inspector_width, LAYOUT.inspector_min_width),
        floor(inner_width * LAYOUT.inspector_max_fraction))

    local browser_width = inner_width - LAYOUT.gap - inspector_width

    local hint_widget = self._widgets_by_name.hint_text

    self:_place("status_bar", padding, status_y, inner_width, LAYOUT.status_height)
    self:_place("hint_text", 0, 0, inner_width, LAYOUT.status_height)
    hint_widget.content.text = self:_fit_text(mod:localize("shortcut_hint"), hint_widget.style.text, inner_width, false)
    self:_place("browser_panel", padding, content_y, browser_width, content_height)
    self:_place("inspector_panel", padding + browser_width + LAYOUT.gap, content_y, inspector_width, content_height)
    layout.browser_x = padding
    layout.browser_y = content_y
    layout.status_y = status_y

    self:_layout_browser(browser_width, content_height)
    self:_layout_inspector(inspector_width, content_height)
    self:_force_update_scenegraph()
    self:_build_popup_options()
    self:_close_popup()
    self:_hide_tooltip()
    self:_refresh_toolbar()

    self._results_dirty = true
    self._keep_selection_visible = true
    self._inspector_dirty = true
end

--- Title row plus toolbar; the toolbar wraps below the search field when it would get too narrow.
-- number: frame_width frame width in UI units
-- treturn: number header height
function IconBrowserView._layout_header(self, frame_width)
    local padding = LAYOUT.padding
    local toolbar = LAYOUT.toolbar
    local spacing = toolbar.spacing
    local inner_width = frame_width - padding * 2
    local title_height = LAYOUT.title_height
    local toolbar_height = LAYOUT.toolbar_height
    local clear_width = toolbar.clear
    local controls_width = 0

    for i = 1, #TOOLBAR_NODES do
        controls_width = controls_width + TOOLBAR_WIDTHS[i] + spacing
    end

    local toolbar_y = padding + title_height + LAYOUT.row_spacing
    local search_width = inner_width - controls_width - clear_width - 4
    local controls_x, controls_y

    if search_width >= toolbar.search_min then
        controls_x = padding + search_width + 4 + clear_width + spacing
        controls_y = toolbar_y
    else
        search_width = inner_width - clear_width - 4
        controls_x = padding
        controls_y = toolbar_y + toolbar_height + LAYOUT.row_spacing
    end

    self:_place("search_input", padding, toolbar_y, search_width, toolbar_height)
    self:_place("search_clear", padding + search_width + 4, toolbar_y, clear_width, toolbar_height)

    local x = controls_x

    for i = 1, #TOOLBAR_NODES do
        self:_place(TOOLBAR_NODES[i], x, controls_y, TOOLBAR_WIDTHS[i], toolbar_height)
        x = x + TOOLBAR_WIDTHS[i] + spacing
    end

    local header_height = controls_y + toolbar_height + LAYOUT.row_spacing
    local title_width = floor(inner_width * 0.4)
    local count_width = 320

    self:_place("header", 0, 0, frame_width, header_height)
    self:_place("title_text", padding, padding, title_width, title_height)
    self:_place("count_text", padding + inner_width - count_width, padding, count_width, title_height)
    self:_place("copy_status_text", padding + title_width, padding, inner_width - title_width - count_width - 20,
        title_height)
    self:_place("header_divider", padding, header_height - 2, inner_width, 2)

    return header_height
end

--- Browser area and slot geometry: grid columns fill the width for the density's target tile size,
-- rows are rounded so whole rows fill the height; list rows likewise.
-- number: width browser panel width
-- number: height browser panel height
function IconBrowserView._layout_browser(self, width, height)
    local area_padding = LAYOUT.area_padding
    local scrollbar_width = LAYOUT.scrollbar_width
    local area_width = width - area_padding * 2 - scrollbar_width - LAYOUT.scrollbar_gap
    local is_list = self._view_mode == "list"
    local density = DENSITIES[self._density]
    local widgets_by_name = self._widgets_by_name
    local layout = self._layout
    local area_y = area_padding

    if is_list then
        self:_place("list_header", area_padding, area_padding, area_width, LAYOUT.list_header_height)
        area_y = area_padding + LAYOUT.list_header_height + 4
    end

    for i = 1, #LIST_HEADER_WIDGETS do
        widgets_by_name[LIST_HEADER_WIDGETS[i]].visible = is_list
    end

    local area_height = height - area_y - area_padding

    self:_place("browser_area", area_padding, area_y, area_width, area_height)
    self:_place("scrollbar", width - area_padding - scrollbar_width, area_y, scrollbar_width, area_height)
    layout.area_x = area_padding
    layout.area_y = area_y
    layout.area_width = area_width
    layout.area_height = area_height

    local columns, rows, slot_width, slot_height, column_pitch, row_pitch

    if is_list then
        rows = max(1, floor(area_height / density.row + 0.5))
        slot_height = floor(area_height / rows)
        slot_width = area_width
        columns = 1
        column_pitch = 0
        row_pitch = slot_height

        self:_layout_list_columns(area_width, slot_height)
    else
        local gap = density.gap

        columns = max(1, floor((area_width + gap) / (density.tile + gap)))
        slot_width = floor((area_width - (columns - 1) * gap) / columns)
        rows = max(1, floor((area_height + gap) / (slot_width + density.label + gap) + 0.5))
        slot_height = floor((area_height + gap) / rows) - gap

        while rows > 1 and slot_height < density.label + 48 do
            rows = rows - 1
            slot_height = floor((area_height + gap) / rows) - gap
        end

        column_pitch = slot_width + gap
        row_pitch = slot_height + gap
    end

    self._columns = columns
    self._visible_rows = rows
    self._column_pitch = column_pitch
    self._row_pitch = row_pitch

    self:_ensure_slots(is_list and "list" or "grid", columns, rows, slot_width, slot_height, density)
end

--- Lays out the list columns and their headers: the preview, shares of the width for the name and
-- the category, a fixed ID column and the rest for the path.
-- number: area_width width of the browser area
-- number: row_height list row height
function IconBrowserView._layout_list_columns(self, area_width, row_height)
    local columns = self._list_columns
    local spacing = 12
    local preview_x = 8
    local preview_width = max(row_height - 8, 72)
    local name_x = preview_x + preview_width + spacing
    local remaining = area_width - name_x - spacing
    local id_width = 72
    local name_width = floor(remaining * 0.28)
    local category_width = floor(remaining * 0.2)
    local path_width = remaining - name_width - id_width - category_width - spacing * 3
    local id_x = name_x + name_width + spacing
    local category_x = id_x + id_width + spacing
    local path_x = category_x + category_width + spacing
    local header_height = LAYOUT.list_header_height

    columns.preview_x = preview_x
    columns.preview_width = preview_width
    columns.name_x = name_x
    columns.name_width = name_width
    columns.id_x = id_x
    columns.id_width = id_width
    columns.category_x = category_x
    columns.category_width = category_width
    columns.path_x = path_x
    columns.path_width = path_width

    self:_place("list_header_preview", preview_x - 10, 0, preview_width + 10, header_height)
    self:_place("list_header_name", name_x - 10, 0, name_width + 10, header_height)
    self:_place("list_header_id", id_x - 10, 0, id_width + 10, header_height)
    self:_place("list_header_category", category_x - 10, 0, category_width + 10, header_height)
    self:_place("list_header_path", path_x - 10, 0, path_width + 10, header_height)
end

--- Rebuilds the slot pool only when the slot geometry changed; slots are placed once and rebound.
-- A rebuild also drops the cached cropped texts, which depend on the slot size.
-- string: kind `grid` or `list`
-- int: columns slots per row
-- int: rows visible rows
-- number: slot_width slot width
-- number: slot_height slot height
-- tab: density entry of `Definitions.DENSITIES`
function IconBrowserView._ensure_slots(self, kind, columns, rows, slot_width, slot_height, density)
    local count = columns * rows

    if kind == self._slot_kind and slot_width == self._slot_width and slot_height == self._slot_height
        and count == self._slot_count and density == self._slot_density then
        return
    end

    self:_destroy_slots()

    local definition

    if kind == "grid" then
        definition = Definitions.tile_definition(slot_width, slot_height, density)
    else
        definition = Definitions.list_row_definition(slot_width, slot_height, self._list_columns, density)
    end

    local slots = self._slots
    local column_pitch = self._column_pitch
    local row_pitch = self._row_pitch

    for k = 1, count do
        local widget = UIWidget.init("icon_slot_" .. k, definition)
        local content = widget.content
        local hotspot = content.hotspot
        local index = k - 1

        widget.offset[1] = (index % columns) * column_pitch
        widget.offset[2] = floor(index / columns) * row_pitch
        widget.visible = false
        content.asset = false
        content.result_index = 0
        content.has_asset = false
        content.icon_available = false
        content.icon_source = false
        content.is_selected = false
        content.is_focused = false
        content.is_favorite = false
        content.is_odd = false
        hotspot.pressed_callback = callback(self, "cb_on_slot_pressed", k)
        hotspot.double_click_callback = callback(self, "cb_on_slot_double_clicked", k)
        slots[k] = widget
    end

    self._slot_count = count
    self._slot_kind = kind
    self._slot_width = slot_width
    self._slot_height = slot_height
    self._slot_density = density
    self._first_row = -1
    self._bind_dirty = true

    table_clear(self._label_cache)
    table_clear(self._name_cache)
    table_clear(self._category_cache)
    table_clear(self._path_cache)
end

--- Destroys the slot pool and forgets the hovered slot.
function IconBrowserView._destroy_slots(self)
    local slots = self._slots
    local ui_renderer = self._ui_renderer

    for k = 1, self._slot_count do
        UIWidget.destroy(ui_renderer, slots[k])
        slots[k] = nil
    end

    self._slot_count = 0
    self._slot_kind = false
    self._hovered_asset = nil
    self._hovered_slot = nil
end

--- Inspector: buttons are anchored to the bottom, metadata above them, and the preview takes the
-- remaining height (at most square), so the actions are never pushed out of the panel.
-- number: width inspector panel width
-- number: height inspector panel height
function IconBrowserView._layout_inspector(self, width, height)
    local inspector = LAYOUT.inspector
    local padding = inspector.padding
    local spacing = inspector.spacing
    local inner_width = width - padding * 2
    local y = padding

    self:_place("inspector_title", padding, y, inner_width, inspector.title_height)
    y = y + inspector.title_height
    self:_place("inspector_subtitle", padding, y, inner_width, inspector.subtitle_height)
    y = y + inspector.subtitle_height + 6
    self:_place("inspector_divider", padding, y, inner_width, 2)
    y = y + 2 + spacing

    local secondary_height = inspector.secondary_height
    local third_row_y = height - padding - secondary_height
    local second_row_y = third_row_y - spacing - secondary_height
    local first_row_y = second_row_y - spacing - secondary_height
    local primary_y = first_row_y - spacing - inspector.primary_height
    local half_width = floor((inner_width - spacing) / 2)
    local right_x = padding + half_width + spacing
    local right_width = inner_width - half_width - spacing

    self:_place("copy_path_button", padding, primary_y, inner_width, inspector.primary_height)
    self:_place("copy_filename_button", padding, first_row_y, half_width, secondary_height)
    self:_place("copy_lua_button", right_x, first_row_y, right_width, secondary_height)
    self:_place("copy_snippet_button", padding, second_row_y, half_width, secondary_height)
    self:_place("copy_sources_button", right_x, second_row_y, right_width, secondary_height)
    self:_place("favorite_button", padding, third_row_y, half_width, secondary_height)
    self:_place("related_button", right_x, third_row_y, right_width, secondary_height)

    local preview_top = y
    local controls_height = inspector.controls_height
    local metadata_height = inspector.metadata_min_height
    local preview_height = primary_y - spacing - metadata_height - spacing - controls_height - spacing - preview_top

    if preview_height > inner_width then
        metadata_height = metadata_height + preview_height - inner_width
        preview_height = inner_width
    elseif preview_height < inspector.preview_min_height then
        local reduction = min(inspector.preview_min_height - preview_height, max(0, metadata_height - 150))

        metadata_height = metadata_height - reduction
        preview_height = preview_height + reduction
    end

    preview_height = max(preview_height, 40)

    local controls_y = preview_top + preview_height + spacing
    local third_width = floor((inner_width - spacing * 2) / 3)
    local metadata_y = controls_y + controls_height + spacing
    local layout = self._layout

    self:_place("preview_area", padding, preview_top, inner_width, preview_height)
    self:_place("preview_background_button", padding, controls_y, third_width, controls_height)
    self:_place("preview_zoom_button", padding + third_width + spacing, controls_y, third_width, controls_height)
    self:_place("preview_aspect_button", padding + (third_width + spacing) * 2, controls_y,
        inner_width - (third_width + spacing) * 2, controls_height)
    self:_place("inspector_metadata", padding, metadata_y, inner_width, max(20, primary_y - spacing - metadata_y))
    self:_place("inspector_empty", padding, preview_top, inner_width, primary_y - spacing - preview_top)
    layout.preview_width = inner_width
    layout.preview_height = preview_height
    layout.metadata_width = inner_width

    self:_layout_preview()
end

--- Fits the preview icon to the chosen display aspect and lays out the checkerboard cells.
-- With the `auto` aspect, the selected asset's usage size from the source references sets the
-- aspect, and 1:1 stands in when the game draws it at no known size.
function IconBrowserView._layout_preview(self)
    local layout = self._layout
    local width = layout.preview_width
    local height = layout.preview_height
    local aspect = ASPECTS[self._preview_aspect_index]
    local aspect_width, aspect_height = aspect.width, aspect.height
    local selected_asset = self._selected_asset

    if aspect.auto and selected_asset and selected_asset.usage_width > 0 and selected_asset.usage_height > 0 then
        aspect_width, aspect_height = selected_asset.usage_width, selected_asset.usage_height
    end

    local available_width = max(1, width - 24)
    local available_height = max(1, height - 24)
    local icon_width = available_width
    local icon_height = floor(icon_width * aspect_height / aspect_width)

    if icon_height > available_height then
        icon_height = available_height
        icon_width = floor(icon_height * aspect_width / aspect_height)
    end

    self:_place("preview_icon", 0, 0, max(1, icon_width), max(1, icon_height))

    local checker_styles = self._preview_widgets.preview_checker.style
    local cells = Definitions.CHECKER_CELLS
    local cell_width = width / cells
    local cell_height = height / cells
    local cell = 0

    for row = 0, cells - 1 do
        for column = 0, cells - 1 do
            if (row + column) % 2 == 1 then
                cell = cell + 1

                local style = checker_styles["cell_" .. cell]

                style.size[1] = cell_width
                style.size[2] = cell_height
                style.offset[1] = column * cell_width
                style.offset[2] = row * cell_height
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Popup menus
-- ----------------------------------------------------------------------------

--- Destroys the option widgets of one popup menu.
-- string: popup_id `category`, `sort` or `related`
function IconBrowserView._destroy_popup_menu_options(self, popup_id)
    local ui_renderer = self._ui_renderer
    local options = self._popup_options[popup_id]

    for i = 1, self._popup_option_counts[popup_id] do
        UIWidget.destroy(ui_renderer, options[i])
        options[i] = nil
    end

    self._popup_option_counts[popup_id] = 0
end

--- Destroys the option widgets of every popup menu.
function IconBrowserView._destroy_popup_options(self)
    for popup_id in pairs(self._popup_options) do
        self:_destroy_popup_menu_options(popup_id)
    end
end

--- Builds the options of the category menu, each labelled with its asset count, and of the sort
-- menu, at least as wide as their toolbar buttons. The Related menu is built when it opens.
function IconBrowserView._build_popup_options(self)
    self:_destroy_popup_menu_options("category")
    self:_destroy_popup_menu_options("sort")

    local option_height = LAYOUT.popup_option_height
    local assets = self._assets
    local ui_scenegraph = self._ui_scenegraph
    local categories = Assets.CATEGORIES
    local category_width = max(ui_scenegraph.category_button.size[1], 340)
    local category_definition = Definitions.option_definition(category_width, option_height)
    local category_options = self._popup_options.category

    for i = 1, #categories do
        local category_id = categories[i].id
        local widget = UIWidget.init("category_option_" .. i, category_definition)
        local content = widget.content

        widget.offset[2] = 6 + (i - 1) * option_height
        content.text = format("%s  (%d)", assets.category_labels[category_id], assets.category_counts[category_id])
        content.option_id = category_id
        content.is_selected = false
        content.hotspot.pressed_callback = callback(self, "cb_on_category_option_pressed", category_id)
        category_options[i] = widget
    end

    self._popup_option_counts.category = #categories
    self._popup_widths.category = category_width

    local sorts = Query.SORTS
    local sort_width = max(ui_scenegraph.sort_button.size[1], 260)
    local sort_definition = Definitions.option_definition(sort_width, option_height)
    local sort_options = self._popup_options.sort

    for i = 1, #sorts do
        local sort_id = sorts[i].id
        local widget = UIWidget.init("sort_option_" .. i, sort_definition)
        local content = widget.content

        widget.offset[2] = 6 + (i - 1) * option_height
        content.text = mod:localize("sort_" .. sort_id)
        content.option_id = sort_id
        content.is_selected = false
        content.hotspot.pressed_callback = callback(self, "cb_on_sort_option_pressed", sort_id)
        sort_options[i] = widget
    end

    self._popup_option_counts.sort = #sorts
    self._popup_widths.sort = sort_width
end

--- Returns how many assets a search filter shows, counted without the category, favorites and recent
-- filters, as applying it from the Related menu switches those off.
-- string: token `kind:value` filter from `Query.filter_token`
-- treturn: int
function IconBrowserView._relation_size(self, token)
    local state = self._related_state

    Query.set_text(state, token)

    local count = Query.run(state, self._assets, self._query_cache, EMPTY_LOOKUP, EMPTY_LOOKUP, self._related_results,
        self._related_result_count)

    self._related_result_count = count

    return count
end

--- Adds an entry to the Related menu when its filter shows more than the asset itself.
-- tab: labels array the entry's label is added to
-- int: count entries so far
-- string: token `kind:value` filter the entry applies
-- string: text_id localization id of the label, formatted with `value`
-- string: value shown value
-- treturn: int entries afterwards
function IconBrowserView._add_relation(self, labels, count, token, text_id, value)
    local size = self:_relation_size(token)

    if size < 2 then
        return count
    end

    count = count + 1
    self._related_tokens[count] = token
    labels[count] = format("%s  (%d)", mod:localize(text_id, value), size)

    return count
end

--- Builds the Related menu of an asset: its family, its folder (with subfolders), the same filename
-- in other folders, and each game script that names it, each with its asset count. An asset without
-- relatives gets a single entry that says so and does nothing.
-- tab: asset selected asset
function IconBrowserView._build_related_options(self, asset)
    self:_destroy_popup_menu_options("related")

    local tokens = self._related_tokens
    local labels = {}
    local count = 0

    table_clear(tokens)

    if asset.family_size > 1 then
        count = self:_add_relation(labels, count, Query.filter_token("family", asset.family), "related_family",
            match(asset.family, "([^/]+)$") or asset.family)
    end

    if asset.directory ~= "" then
        count = self:_add_relation(labels, count, Query.filter_token("in", asset.directory), "related_folder",
            asset.directory)
    end

    if asset.filename_count > 1 then
        count = self:_add_relation(labels, count, Query.filter_token("filename", asset.filename), "related_filename",
            asset.filename)
    end

    local files = asset.ref_files

    if files then
        for i = 1, min(#files, MAX_RELATED_FILES) do
            local file_name = match(files[i], "([^/]+)$") or files[i]

            count = self:_add_relation(labels, count, Query.filter_token("file", file_name), "related_file", file_name)
        end
    end

    if count == 0 then
        count = 1
        labels[1] = mod:localize("related_none")
    end

    local option_height = LAYOUT.popup_option_height
    local text_style = Definitions.option_definition(RELATED_MAX_WIDTH, option_height).style.text
    local width = RELATED_MIN_WIDTH

    for i = 1, count do
        width = max(width, (self:_text_width(labels[i], text_style) or 0) + 32 + CROP_MARGIN * 2)
    end

    width = min(floor(width), RELATED_MAX_WIDTH, self._layout.frame_width - LAYOUT.padding * 2)

    local definition = Definitions.option_definition(width, option_height)
    local options = self._popup_options.related

    for i = 1, count do
        local widget = UIWidget.init("related_option_" .. i, definition)
        local content = widget.content

        widget.offset[2] = 6 + (i - 1) * option_height
        content.text = self:_fit_text(labels[i], widget.style.text, width - 32, false)
        content.option_id = i
        content.is_selected = false
        content.hotspot.pressed_callback = callback(self, "cb_on_related_option_pressed", i)
        options[i] = widget
    end

    self._popup_option_counts.related = count
    self._popup_widths.related = width
end

--- Opens a popup menu below its toolbar button, or the Related menu above the inspector's Related
-- button; leaves the search field and closes any other menu and the tooltip first.
-- string: popup_id `category`, `sort` or `related`
function IconBrowserView._open_popup_menu(self, popup_id)
    self:_stop_search_input()
    self:_close_popup()

    local ui_scenegraph = self._ui_scenegraph
    local button_node = ui_scenegraph[popup_id .. "_button"]
    local width = self._popup_widths[popup_id]
    local height = self._popup_option_counts[popup_id] * LAYOUT.popup_option_height + 12
    local x, y

    if popup_id == "related" then
        local panel_position = ui_scenegraph.inspector_panel.position

        x = panel_position[1] + button_node.position[1] + button_node.size[1] - width
        y = max(LAYOUT.padding, panel_position[2] + button_node.position[2] - height - 4)
    else
        x = button_node.position[1]
        y = button_node.position[2] + button_node.size[2] + 4
    end

    x = min(x, self._layout.frame_width - LAYOUT.padding - width)

    self:_place("popup", max(LAYOUT.padding, x), y, width, height)
    self:_force_update_scenegraph()

    self._open_popup = popup_id
    self._widgets_by_name.popup_background.visible = true
    self._widgets_by_name[popup_id .. "_button"].content.hotspot.is_selected = true
    self:_refresh_popup_selection()
    self:_hide_tooltip()
end

--- Closes the open popup menu, if any.
function IconBrowserView._close_popup(self)
    local popup_id = self._open_popup

    if not popup_id then
        return
    end

    self._open_popup = nil
    self._widgets_by_name.popup_background.visible = false
    self._widgets_by_name[popup_id .. "_button"].content.hotspot.is_selected = false
end

--- Marks the option of the open menu that matches the active category or sort; the Related menu
-- has no active option.
function IconBrowserView._refresh_popup_selection(self)
    local popup_id = self._open_popup

    if not popup_id then
        return
    end

    local state = self._query_state
    local active_id = popup_id == "category" and state.category or popup_id == "sort" and state.sort or nil
    local options = self._popup_options[popup_id]

    for i = 1, self._popup_option_counts[popup_id] do
        local content = options[i].content

        content.is_selected = content.option_id == active_id
    end
end

--- Returns whether the cursor is over an option of the open menu.
-- treturn: bool
function IconBrowserView._popup_hovered(self)
    local popup_id = self._open_popup
    local options = self._popup_options[popup_id]

    for i = 1, self._popup_option_counts[popup_id] do
        if options[i].content.hotspot.is_hover then
            return true
        end
    end

    return false
end

-- ----------------------------------------------------------------------------
-- Search field
-- ----------------------------------------------------------------------------

--- Returns whether the search field has focus.
-- treturn: bool
function IconBrowserView._is_typing(self)
    local search_content = self._search_content

    return search_content ~= nil and search_content.is_writing == true
end

--- Returns whether shortcuts are blocked, because the search field has focus or a menu is open.
-- treturn: bool
function IconBrowserView._input_blocked(self)
    return self._open_popup ~= nil or self:_is_typing()
end

--- Leaves the search field like `CharacterAppearanceView._stop_name_input`, keeping a pending
-- select-all selection as the text so nothing typed is lost.
function IconBrowserView._stop_search_input(self)
    local search_content = self._search_content

    if not search_content or not search_content.is_writing then
        return
    end

    local selected_text = search_content.selected_text
    local input_text = search_content.input_text

    if (input_text == nil or input_text == "") and selected_text and selected_text ~= "" then
        search_content.input_text = selected_text
    end

    search_content.selected_text = nil
    search_content._selection_start = nil
    search_content._selection_end = nil
    search_content.is_writing = false
end

--- Switches the input method editor used to type languages such as Chinese or Japanese.
-- bool: enabled whether the IME is enabled
function IconBrowserView._set_ime_enabled(self, enabled)
    local window = Window

    if window and window.set_ime_enabled then
        pcall(window.set_ime_enabled, enabled)
    end
end

--- Applies a pending Ctrl+F focus once its delay ran out, shows the focused field's gold outline,
-- and closes the open menu and switches the IME when the focus changes.
function IconBrowserView._update_search_focus(self)
    local search_content = self._search_content
    local pending = self._pending_search_focus

    if pending > 0 then
        pending = pending - 1
        self._pending_search_focus = pending

        if pending == 0 and not search_content.is_writing then
            local text = search_content.input_text or ""

            search_content.is_writing = true
            search_content.caret_position = Utf8.string_length(text) + 1
            search_content.force_caret_update = true
        end
    end

    local writing = search_content.is_writing == true

    search_content.hotspot.is_selected = writing

    if writing ~= self._was_writing then
        self._was_writing = writing

        if writing then
            self:_close_popup()
        end

        self:_set_ime_enabled(writing)
    end
end

--- Polls the search text (one string comparison per frame) and re-runs the query on change.
-- While the field shows a pending select-all, the selected text counts as the search text.
function IconBrowserView._sync_search_text(self)
    local search_content = self._search_content
    local text = search_content.input_text or ""

    if text == "" and search_content.is_writing then
        local selected_text = search_content.selected_text

        if selected_text and selected_text ~= "" then
            text = selected_text
        end
    end

    if Query.set_text(self._query_state, text) then
        self._results_dirty = true
        self._reset_scroll = true
        mod._icon_browser_session.query = text
        self._widgets_by_name.search_clear.visible = text ~= ""
    end
end

-- ----------------------------------------------------------------------------
-- Query, scroll and binding
-- ----------------------------------------------------------------------------

--- Returns the position of an asset in the current results.
-- ?tab: asset asset record
-- treturn: ?int
function IconBrowserView._index_of(self, asset)
    if not asset then
        return nil
    end

    local results = self._results

    for i = 1, self._result_count do
        if results[i] == asset then
            return i
        end
    end

    return nil
end

--- Runs the query and refreshes what depends on the results: the focus position, the scrollbar, the
-- scroll position, the slot binding, the asset count and the empty-results message.
function IconBrowserView._run_query(self)
    self._results_dirty = false

    local count = Query.run(self._query_state, self._assets, self._query_cache, mod._favorite_lookup,
        mod._recent_lookup, self._results, self._result_count)

    self._result_count = count
    self._focus_index = self:_index_of(self._focus_asset)

    if not self._focus_index then
        self._focus_asset = nil
    end

    self:_update_scrollbar_metrics()

    if self._reset_scroll then
        self._reset_scroll = false
        self:_set_scroll_row(0)
    end

    if self._keep_selection_visible then
        self._keep_selection_visible = false

        local index = self._focus_index or self:_index_of(self._selected_asset)

        if index then
            self:_scroll_to_index(index)
        end
    end

    self._first_row = -1
    self._bind_dirty = true

    local widgets_by_name = self._widgets_by_name
    local state = self._query_state
    local empty_widget = widgets_by_name.empty_text

    widgets_by_name.count_text.content.text = mod:localize("count_format", count, self._assets.count)
    empty_widget.visible = count == 0

    if count == 0 then
        local message_id = "empty_results"

        local unfiltered = state.term_count == 0 and state.filter_count == 0

        if unfiltered and state.favorites_only then
            message_id = "empty_favorites"
        elseif unfiltered and state.recent_only then
            message_id = "empty_recent"
        end

        empty_widget.content.text = mod:localize(message_id)
    end
end

--- Sizes the scrollbar for the result rows and sets the wheel step: one row per notch in the grid,
-- three in the list.
function IconBrowserView._update_scrollbar_metrics(self)
    local columns = self._columns
    local visible_rows = self._visible_rows
    local row_pitch = self._row_pitch
    local total_rows = floor((self._result_count + columns - 1) / columns)
    local max_first_row = max(0, total_rows - visible_rows)
    local content = self._widgets_by_name.scrollbar.content
    local rows_per_notch = self._slot_kind == "list" and LIST_ROWS_PER_SCROLL or GRID_ROWS_PER_SCROLL

    self._max_first_row = max_first_row
    content.scroll_length = max_first_row * row_pitch
    content.area_length = visible_rows * row_pitch
    content.scroll_amount = max_first_row > 0 and min(1, rows_per_notch * SCROLL_NOTCH_FACTOR / max_first_row) or 0

    if max_first_row == 0 then
        content.value = 0
        content.scroll_value = nil
        content.scroll_add = nil
    end
end

--- Returns the first visible row for the scrollbar position, snapped to whole rows.
-- treturn: int zero-based row
function IconBrowserView._current_first_row(self)
    local max_first_row = self._max_first_row

    if max_first_row <= 0 then
        return 0
    end

    local value = self._widgets_by_name.scrollbar.content.value or 0

    return _clamp(floor(value * max_first_row + 0.5), 0, max_first_row)
end

--- Scrolls so that a row is the first visible one.
-- int: row zero-based row
function IconBrowserView._set_scroll_row(self, row)
    local max_first_row = self._max_first_row
    local content = self._widgets_by_name.scrollbar.content

    content.value = max_first_row > 0 and _clamp(row / max_first_row, 0, 1) or 0
    content.scroll_value = nil
    content.scroll_add = nil
end

--- Scrolls just far enough to show a result.
-- int: index position in the results
function IconBrowserView._scroll_to_index(self, index)
    local row = floor((index - 1) / self._columns)
    local first_row = self:_current_first_row()

    if row < first_row then
        self:_set_scroll_row(row)
    elseif row >= first_row + self._visible_rows then
        self:_set_scroll_row(row - self._visible_rows + 1)
    end
end

--- Rebinds the slots when the first visible row changed or a rebind is pending; hides the tooltip
-- while scrolling.
function IconBrowserView._update_scroll(self)
    local first_row = self:_current_first_row()

    if first_row ~= self._first_row then
        self._first_row = first_row
        self._bind_dirty = true

        if self._tooltip_shown then
            self:_hide_tooltip()
        end
    end

    if self._bind_dirty then
        self:_bind_slots()
    end
end

--- Single-line width of `text` in UI units (fonts scale linearly with the render scale), or nil.
-- string: text text to measure
-- tab: style text style with `font_type` and `font_size`
-- treturn: ?number
function IconBrowserView._text_width(self, text, style)
    local ok, width = pcall(UIRenderer.text_size, self._ui_renderer, text, style.font_type, style.font_size, nil, nil,
        true)

    return ok and width or nil
end

--- Crops `text` so it stays on one line inside `max_width`, ellipsis included. The game's
-- `crop_text_width` checks the width before appending its "...", so its result can overflow the box
-- and the engine then wraps it at the last space; this binary search measures with the suffix, keeps
-- a small margin, and drops spaces next to the ellipsis so it can never end up alone on a line.
-- string: text text to fit
-- tab: style text style it is drawn with
-- number: max_width box width in UI units
-- ?bool: crop_from_left keep the end of the text instead of its start, for paths
-- treturn: string
function IconBrowserView._fit_text(self, text, style, max_width, crop_from_left)
    local limit = max_width - CROP_MARGIN
    local width = self:_text_width(text, style)

    if not width or width <= limit then
        return text
    end

    limit = limit - (self:_text_width(CROP_SUFFIX, style) or 0)

    local length = Utf8.string_length(text)
    local low, high = 0, length - 1

    while low < high do
        local middle = floor((low + high + 1) / 2)
        local candidate

        if crop_from_left then
            candidate = Utf8.sub_string(text, length - middle + 1, length)
        else
            candidate = Utf8.sub_string(text, 1, middle)
        end

        local candidate_width = self:_text_width(candidate, style)

        if candidate_width and candidate_width <= limit then
            low = middle
        else
            high = middle - 1
        end
    end

    if crop_from_left then
        return CROP_SUFFIX .. gsub(Utf8.sub_string(text, length - low + 1, length), "^%s+", "")
    end

    return gsub(Utf8.sub_string(text, 1, low), "%s+$", "") .. CROP_SUFFIX
end

--- Cropped display text per asset, measured once per slot layout and then reused while scrolling.
-- tab: cache cropped texts by browser ID
-- tab: asset asset the text belongs to
-- string: text text to fit
-- tab: style text style it is drawn with
-- number: max_width box width in UI units
-- ?bool: crop_from_left keep the end of the text, for paths
-- treturn: string
function IconBrowserView._cropped_text(self, cache, asset, text, style, max_width, crop_from_left)
    local cropped = cache[asset.id]

    if cropped then
        return cropped
    end

    cropped = self:_fit_text(text, style, max_width, crop_from_left)
    cache[asset.id] = cropped

    return cropped
end

--- Returns whether an asset's material is loaded, asking the engine once per path while the view is
-- open. A material that is not loaded draws as a white square, so it gets a red fallback instead.
-- string: path material path
-- treturn: bool
function IconBrowserView._is_material_loaded(self, path)
    local material_loaded = self._material_loaded
    local loaded = material_loaded[path]

    if loaded == nil then
        loaded = mod.is_icon_material_loaded(path)
        material_loaded[path] = loaded
    end

    return loaded
end

--- Forgets the cached material states and rebinds the slots and the inspector, once the global game
-- packages requested in the main menu have loaded.
function IconBrowserView._refresh_material_states(self)
    local slots = self._slots

    table_clear(self._material_loaded)

    for k = 1, self._slot_count do
        slots[k].content.asset = false
    end

    self._bind_dirty = true
    self._inspector_dirty = true
end

--- Binds the visible window of the results to the slot pool. Strings are only written when a slot
-- shows a different asset; state flags are refreshed for every visible slot. A material that is not
-- loaded is not drawn, since it would show as a white square; its slot shows a red fallback.
function IconBrowserView._bind_slots(self)
    self._bind_dirty = false

    local slots = self._slots
    local slot_count = self._slot_count

    if slot_count == 0 then
        return
    end

    local results = self._results
    local result_count = self._result_count
    local base_index = max(self._first_row, 0) * self._columns
    local selection = self._selection
    local focus_asset = self._focus_asset
    local favorites = mod._favorite_lookup
    local is_grid = self._slot_kind == "grid"
    local first_style = slots[1].style
    local columns = self._list_columns
    local fallback_texts = self._fallback_texts.short
    local packages_loading = self._global_packages_loading

    for k = 1, slot_count do
        local widget = slots[k]
        local content = widget.content
        local index = base_index + k
        local asset = index <= result_count and results[index] or nil

        if asset then
            if content.asset ~= asset then
                local path = asset.path
                local loaded = self:_is_material_loaded(path)
                local available = loaded and mod.can_render_icon_path(path)

                content.asset = asset
                content.icon_source = path
                content.icon_available = available
                content.icon = available and path or ""
                content.hotspot.double_click_timer = 0
                _set_fallback(content, "fallback_text", widget.style.fallback, fallback_texts, loaded,
                    packages_loading)

                if is_grid then
                    local label_style = first_style.label

                    content.label = self:_cropped_text(self._label_cache, asset, asset.display_name, label_style,
                        label_style.size[1], false)
                else
                    content.name = self:_cropped_text(self._name_cache, asset, asset.display_name, first_style.name,
                        columns.name_width, false)
                    content.id_text = asset.id_text
                    content.category = self:_cropped_text(self._category_cache, asset, asset.category_label,
                        first_style.category, columns.category_width, false)
                    content.path = self:_cropped_text(self._path_cache, asset, asset.path, first_style.path,
                        columns.path_width, true)
                end
            end

            content.result_index = index
            content.has_asset = true
            content.is_selected = selection[asset] == true
            content.is_focused = asset == focus_asset
            content.is_favorite = favorites[asset.path] == true
            content.is_odd = index % 2 == 1
            widget.visible = true
        else
            if content.asset then
                content.asset = false
                content.icon = ""
                content.icon_available = false
                content.icon_source = false
            end

            content.has_asset = false
            widget.visible = false
        end
    end
end

-- ----------------------------------------------------------------------------
-- Selection, focus and actions
-- ----------------------------------------------------------------------------

--- Sets the primary selection, the asset the inspector previews and single actions use, moves the
-- keyboard focus to it and refreshes the slots and the inspector.
-- ?tab: asset asset record
-- ?int: index its position in the results
function IconBrowserView._set_primary(self, asset, index)
    self._selected_asset = asset
    self._focus_asset = asset
    self._focus_index = index
    self._bind_dirty = true
    self._inspector_dirty = true
    mod._icon_browser_session.selected_path = asset and asset.path or false
end

--- Adds an asset to the selection, after the assets selected before it.
-- tab: asset asset record
function IconBrowserView._add_to_selection(self, asset)
    local selection = self._selection

    if selection[asset] then
        return
    end

    local count = self._selection_count + 1

    selection[asset] = true
    self._selection_list[count] = asset
    self._selection_count = count
end

--- Removes an asset from the selection.
-- tab: asset asset record
function IconBrowserView._remove_from_selection(self, asset)
    local selection = self._selection

    if not selection[asset] then
        return
    end

    local list = self._selection_list
    local count = self._selection_count

    selection[asset] = nil

    for i = 1, count do
        if list[i] == asset then
            table.remove(list, i)

            break
        end
    end

    self._selection_count = count - 1
end

--- Empties the selection.
function IconBrowserView._clear_selection(self)
    table_clear(self._selection)
    table_clear(self._selection_list)
    self._selection_count = 0
end

--- Selects only this asset, which also becomes the anchor of a Shift range, and refreshes the slots
-- and the inspector; the clipboard is never touched.
-- ?tab: asset asset record, nil to clear the selection
-- ?int: index its position in the results
-- ?bool: record_recent add it to the recent history
function IconBrowserView._select_asset(self, asset, index, record_recent)
    self:_clear_selection()

    if asset then
        self:_add_to_selection(asset)
    end

    self._selection_anchor = asset
    self:_set_primary(asset, index)

    if asset and record_recent then
        mod.record_recent_icon(asset.path)
    end
end

--- Ctrl+click: adds the asset to the selection or removes it. An added asset becomes the primary
-- selection and the anchor; removing the primary hands it to the asset selected last.
-- tab: asset asset record
-- ?int: index its position in the results
function IconBrowserView._toggle_in_selection(self, asset, index)
    if self._selection[asset] then
        self:_remove_from_selection(asset)

        local count = self._selection_count
        local primary = self._selected_asset

        if primary == asset then
            primary = count > 0 and self._selection_list[count] or nil
            self:_set_primary(primary, self:_index_of(primary))
        else
            self._bind_dirty = true
            self._inspector_dirty = true
        end

        self._selection_anchor = primary
    else
        self:_add_to_selection(asset)
        self._selection_anchor = asset
        self:_set_primary(asset, index)
    end
end

--- Shift+click: selects the results from the anchor to the asset; with `additive` (Ctrl+Shift) the
-- range is added to the selection instead of replacing it. Without an anchor among the results it
-- selects the asset alone. The anchor stays, so further Shift+clicks resize the range.
-- tab: asset asset record
-- int: index its position in the results
-- bool: additive keep the current selection
function IconBrowserView._select_range(self, asset, index, additive)
    local anchor = self._selection_anchor
    local anchor_index = self:_index_of(anchor)

    if not anchor_index then
        self:_select_asset(asset, index, false)

        return
    end

    if not additive then
        self:_clear_selection()
    end

    local results = self._results
    local step = anchor_index <= index and 1 or -1

    for i = anchor_index, index, step do
        self:_add_to_selection(results[i])
    end

    self._selection_anchor = anchor
    self:_set_primary(asset, index)
end

--- Ctrl+A: selects every listed result; the primary selection stays when it is listed, else the
-- focused or first result takes its place.
function IconBrowserView._select_all_results(self)
    local count = self._result_count

    if count == 0 then
        return
    end

    local results = self._results

    self:_clear_selection()

    for i = 1, count do
        self:_add_to_selection(results[i])
    end

    local primary = self._selected_asset
    local index = self:_index_of(primary)

    if not index then
        index = self._focus_index or 1
        primary = results[index]
    end

    self._selection_anchor = primary
    self:_set_primary(primary, index)
end

--- Fills `_selection_ordered` with the selected assets in the active sort order, filtered out ones
-- included, which is the order bulk copies use.
-- treturn: tab array of assets
-- treturn: int number of assets
function IconBrowserView._ordered_selection(self)
    local ordered = self._selection_ordered
    local selection = self._selection
    local order = Query.order(self._query_cache, self._assets, self._query_state.sort)
    local count = 0

    table_clear(ordered)

    for i = 1, self._assets.count do
        local asset = order[i]

        if selection[asset] then
            count = count + 1
            ordered[count] = asset
        end
    end

    return ordered, count
end

--- Moves the keyboard focus through the results and scrolls it into view; without a focus it
-- starts at the first visible result.
-- int: delta_x step within a row, -1, 0 or 1
-- int: delta_y step in rows, -1, 0 or 1
function IconBrowserView._move_focus(self, delta_x, delta_y)
    local count = self._result_count

    if count == 0 then
        return
    end

    local index = self._focus_index

    if not index then
        index = self:_current_first_row() * self._columns + 1

        if index > count then
            index = 1
        end
    else
        index = _clamp(index + delta_x + delta_y * self._columns, 1, count)
    end

    self._focus_index = index
    self._focus_asset = self._results[index]
    self._bind_dirty = true
    self:_scroll_to_index(index)
end

--- Bulk format each button copies while several assets are selected, its chat label and the status
-- shown in the header.
local BULK_COPY_FORMATS = {
    path = { label = "paths", status = "status_copied_paths" },
    filename = { label = "filenames", status = "status_copied_filenames" },
    lua_string = { label = "Lua array", status = "status_copied_lua_array" },
    ui_snippet = { label = "Lua table", status = "status_copied_lua_table" },
}

--- Copies the selected assets in a bulk format, in the active sort order, and shows the status; bulk
-- copies are not added to the recent history.
-- string: copy_format button format: `path`, `filename`, `lua_string` or `ui_snippet`
function IconBrowserView._copy_selection(self, copy_format)
    local bulk = BULK_COPY_FORMATS[copy_format]

    if not bulk then
        return
    end

    local list, count = self:_ordered_selection()
    local text

    if copy_format == "path" or copy_format == "filename" then
        text = Assets.field_lines(list, count, copy_format)
    elseif copy_format == "lua_string" then
        text = Assets.lua_array(list, count)
    else
        text = Assets.lua_table(list, count)
    end

    local copied = mod.copy_icon_list_to_clipboard(text, bulk.label, count)

    self:_set_copy_status(copied and mod:localize(bulk.status, count) or self._status_text.failed, not copied)
end

--- Copies a format of the selected asset, records it in the recent history and shows the status.
-- With several assets selected, the bulk format of `BULK_COPY_FORMATS` is copied instead.
-- string: copy_format `path`, `filename`, `lua_string`, `ui_snippet` or `sources`
function IconBrowserView._copy_selected(self, copy_format)
    local asset = self._selected_asset

    if not asset then
        return
    end

    if self._selection_count > 1 then
        return self:_copy_selection(copy_format)
    end

    local copied

    if copy_format == "path" then
        copied = mod.copy_icon_path_to_clipboard(asset.id, asset.path)
    elseif copy_format == "filename" then
        copied = mod.copy_icon_text_to_clipboard(asset.id, asset.filename, "filename", asset.path)
    elseif copy_format == "lua_string" then
        copied = mod.copy_icon_text_to_clipboard(asset.id, Assets.lua_string(asset), "Lua string", asset.path)
    elseif copy_format == "sources" then
        copied = mod.copy_icon_text_to_clipboard(asset.id, Assets.source_reference_text(asset), "source references",
            asset.path)
    else
        copied = mod.copy_icon_text_to_clipboard(asset.id, Assets.ui_snippet(asset), "Lua UI snippet", asset.path)
    end

    if copied then
        mod.record_recent_icon(asset.path)
    end

    local status_text = self._status_text

    self:_set_copy_status(copied and status_text[copy_format] or status_text.failed, not copied)
end

--- Returns whether every selected asset is a favorite.
-- treturn: bool
function IconBrowserView._selection_all_favorites(self)
    local list = self._selection_list
    local favorites = mod._favorite_lookup

    for i = 1, self._selection_count do
        if not favorites[list[i].path] then
            return false
        end
    end

    return true
end

--- Toggles the selected asset's favorite and shows the status. With several assets selected, all of
-- them become favorites, or all are removed when every one of them already is.
function IconBrowserView._toggle_selected_favorite(self)
    local asset = self._selected_asset

    if not asset then
        return
    end

    local count = self._selection_count

    if count > 1 then
        local is_favorite = not self:_selection_all_favorites()
        local paths = {}
        local list = self._selection_list

        for i = 1, count do
            paths[i] = list[i].path
        end

        local changed = mod.set_icon_favorites(paths, count, is_favorite)

        self:_set_copy_status(mod:localize(is_favorite and "status_favorites_added" or "status_favorites_removed",
            changed), false)

        return
    end

    local is_favorite = mod.toggle_icon_favorite(asset.path)

    self:_set_copy_status(self._status_text[is_favorite and "favorite_added" or "favorite_removed"], false)
end

--- Pressed callback of a slot; leaves the search field and selects the slot's asset: alone on a
-- plain click, toggled with Ctrl, as a range from the anchor with Shift, added as a range with
-- Ctrl+Shift.
-- int: slot_index slot in the pool
function IconBrowserView.cb_on_slot_pressed(self, slot_index)
    local widget = self._slots[slot_index]
    local asset = widget and widget.content.asset

    if not asset then
        return
    end

    local index = widget.content.result_index
    local keys = _keyboard_keys_lookup()
    local ctrl = keys and _ctrl_down(keys)

    self:_stop_search_input()

    if keys and _shift_down(keys) then
        self:_select_range(asset, index, ctrl)
    elseif ctrl then
        self:_toggle_in_selection(asset, index)
    else
        self:_select_asset(asset, index, true)
    end
end

--- The hotspot calls this instead of `pressed_callback` for the second click of a double click.
-- Selects the slot's asset and copies its path when the Double-Click Copies Path setting is on.
-- With Ctrl or Shift held it counts as a second click instead, so quick Ctrl+clicks toggle twice.
-- int: slot_index slot in the pool
function IconBrowserView.cb_on_slot_double_clicked(self, slot_index)
    local widget = self._slots[slot_index]
    local asset = widget and widget.content.asset

    if not asset then
        return
    end

    local keys = _keyboard_keys_lookup()

    if keys and (_ctrl_down(keys) or _shift_down(keys)) then
        return self:cb_on_slot_pressed(slot_index)
    end

    if asset ~= self._selected_asset then
        self:_select_asset(asset, widget.content.result_index, true)
    end

    if self._double_click_copy then
        self:_copy_selected("path")
    end
end

-- ----------------------------------------------------------------------------
-- Legend and toolbar callbacks
-- ----------------------------------------------------------------------------

--- Legend visibility of Enter: shown while the keyboard focus is on an asset that is not selected.
-- treturn: bool
function IconBrowserView.legend_select_visible(self)
    local focus_asset = self._focus_asset

    return not self:_input_blocked() and focus_asset ~= nil and focus_asset ~= self._selected_asset
end

--- Legend visibility of C: shown for a selection while the C key copies.
-- treturn: bool
function IconBrowserView.legend_copy_visible(self)
    return self._copy_hotkey_enabled and self._selected_asset ~= nil and not self:_input_blocked()
end

--- Legend visibility of F: shown for a selection.
-- treturn: bool
function IconBrowserView.legend_favorite_visible(self)
    return self._selected_asset ~= nil and not self:_input_blocked()
end

--- Esc leaves the search field first, then an open menu, then reduces a multi-selection to its
-- primary asset, and only then closes the browser.
function IconBrowserView.cb_on_back_pressed(self)
    if self:_is_typing() then
        self:_stop_search_input()
    elseif self._open_popup then
        self:_close_popup()
    elseif self._selection_count > 1 then
        self:_select_asset(self._selected_asset, self._focus_index, false)
    else
        Managers.ui:close_view(VIEW_NAME)
    end
end

--- Legend callback of Enter; selects the focused asset.
function IconBrowserView.cb_on_select_pressed(self)
    local focus_asset = self._focus_asset

    if self:_input_blocked() or not focus_asset then
        return
    end

    self:_select_asset(focus_asset, self._focus_index, true)
end

--- Legend callback of C; copies the selected path. Ignored with Ctrl held, as Ctrl+C is handled in
-- `_handle_input`, and while shortcuts are blocked or the C key setting is off.
function IconBrowserView.cb_on_copy_hotkey_pressed(self)
    local keys = _keyboard_keys_lookup()

    if self:_input_blocked() or not self._copy_hotkey_enabled or keys and _ctrl_down(keys) then
        return
    end

    self:_copy_selected("path")
end

--- Legend callback of F; toggles the selected asset's favorite. Ignored with Ctrl held, so Ctrl+F
-- does not toggle it, and while shortcuts are blocked.
function IconBrowserView.cb_on_favorite_hotkey_pressed(self)
    local keys = _keyboard_keys_lookup()

    if self:_input_blocked() or keys and _ctrl_down(keys) then
        return
    end

    self:_toggle_selected_favorite()
end

--- Clears the search field and keeps its focus.
function IconBrowserView.cb_on_clear_search_pressed(self)
    local search_content = self._search_content

    search_content.input_text = ""
    search_content.selected_text = nil
    search_content._selection_start = nil
    search_content._selection_end = nil
    search_content.caret_position = 1
    search_content.force_caret_update = true
end

--- Opens or closes the category or sort menu.
-- string: popup_id `category` or `sort`
function IconBrowserView.cb_on_dropdown_pressed(self, popup_id)
    if self._open_popup == popup_id then
        self:_close_popup()
    else
        self:_open_popup_menu(popup_id)
    end
end

--- Applies and saves a category chosen in the menu.
-- string: category_id category id of `Assets.CATEGORIES`
function IconBrowserView.cb_on_category_option_pressed(self, category_id)
    local state = self._query_state

    self:_close_popup()

    if state.category ~= category_id then
        state.category = category_id
        mod.set_icon_browser_category(category_id)
        self._results_dirty = true
        self._reset_scroll = true
    end

    self:_refresh_toolbar()
end

--- Applies and saves a sort and keeps the selection in view.
-- string: sort_id sort id of `Query.SORTS`
function IconBrowserView._apply_sort(self, sort_id)
    local state = self._query_state

    if state.sort ~= sort_id and Query.is_valid_sort(sort_id) then
        state.sort = sort_id
        mod.set_icon_browser_sort(sort_id)
        self._results_dirty = true
        self._reset_scroll = true
        self._keep_selection_visible = true
    end

    self:_refresh_toolbar()
end

--- Applies a sort chosen in the menu.
-- string: sort_id sort id of `Query.SORTS`
function IconBrowserView.cb_on_sort_option_pressed(self, sort_id)
    self:_close_popup()
    self:_apply_sort(sort_id)
end

--- Sorts by a list column, ascending first and descending on a second click.
-- string: sort_key `name`, `index`, `category` or `path`
function IconBrowserView.cb_on_column_pressed(self, sort_key)
    self:_stop_search_input()
    self:_apply_sort(Query.toggle_sort(self._query_state.sort, sort_key))
end

--- Opens or closes the Related menu of the selected asset.
function IconBrowserView.cb_on_related_pressed(self)
    local asset = self._selected_asset

    if self._open_popup == "related" or not asset then
        self:_close_popup()

        return
    end

    self:_build_related_options(asset)
    self:_open_popup_menu("related")
end

--- Shows the relatives chosen in the Related menu: writes the entry's filter into the search field
-- and switches the category, favorites and recent filters off, so the count shown in the menu is
-- what the browser lists; the selection stays and is scrolled into view.
-- int: index entry of the Related menu
function IconBrowserView.cb_on_related_option_pressed(self, index)
    local token = self._related_tokens[index]

    self:_close_popup()

    if not token then
        return
    end

    local search_content = self._search_content
    local state = self._query_state

    search_content.input_text = token
    search_content.selected_text = nil
    search_content.caret_position = Utf8.string_length(token) + 1
    search_content.force_caret_update = true

    if state.category ~= Query.CATEGORY_ALL then
        state.category = Query.CATEGORY_ALL
        mod.set_icon_browser_category(Query.CATEGORY_ALL)
    end

    state.favorites_only = false
    state.recent_only = false
    self._results_dirty = true
    self._keep_selection_visible = true
    self:_refresh_toolbar()
end

--- Toggles the favorites filter; switching it on switches the recent filter off.
function IconBrowserView.cb_on_favorites_filter_pressed(self)
    local state = self._query_state

    self:_stop_search_input()
    state.favorites_only = not state.favorites_only

    if state.favorites_only then
        state.recent_only = false
    end

    self._results_dirty = true
    self._reset_scroll = true
    self:_refresh_toolbar()
end

--- Toggles the recent filter; switching it on switches the favorites filter off.
function IconBrowserView.cb_on_recent_filter_pressed(self)
    local state = self._query_state

    self:_stop_search_input()
    state.recent_only = not state.recent_only

    if state.recent_only then
        state.favorites_only = false
    end

    self._results_dirty = true
    self._reset_scroll = true
    self:_refresh_toolbar()
end

--- Empties the recent history.
function IconBrowserView.cb_on_clear_recent_pressed(self)
    mod.clear_recent_icons()
    self:_set_copy_status(self._status_text.recent_cleared, false)
end

--- Switches between grid and list; the layout follows on the next update.
-- string: view_mode `grid` or `list`
function IconBrowserView.cb_on_view_mode_pressed(self, view_mode)
    self:_stop_search_input()

    if view_mode ~= self._view_mode then
        mod.set_icon_browser_view_mode(view_mode)
    end
end

--- Switches the thumbnail density; the layout follows on the next update.
-- string: density `compact`, `normal` or `large`
function IconBrowserView.cb_on_density_pressed(self, density)
    self:_stop_search_input()

    if density ~= self._density then
        mod.set_icon_browser_density(density)
    end
end

--- Cycles and saves the preview background: dark, light, checkerboard.
function IconBrowserView.cb_on_preview_background_pressed(self)
    local current = self._preview_background
    local next_index = 1

    for i = 1, #PREVIEW_BACKGROUNDS do
        if PREVIEW_BACKGROUNDS[i] == current then
            next_index = i % #PREVIEW_BACKGROUNDS + 1
            break
        end
    end

    self._preview_background = PREVIEW_BACKGROUNDS[next_index]
    mod.set_icon_browser_preview_background(self._preview_background)
    self:_refresh_preview_controls()
end

--- Cycles the preview zoom: fit, 2x, 4x.
function IconBrowserView.cb_on_preview_zoom_pressed(self)
    self._preview_zoom_index = self._preview_zoom_index % #ZOOM_LEVELS + 1
    self:_refresh_preview_controls()
end

--- Cycles the preview's display aspect and fits the icon to it.
function IconBrowserView.cb_on_preview_aspect_pressed(self)
    self._preview_aspect_index = self._preview_aspect_index % #ASPECTS + 1
    self:_layout_preview()
    self:_force_update_scenegraph()
    self:_refresh_preview_controls()
end

--- Pressed callback of the inspector's copy buttons.
-- string: copy_format `path`, `filename`, `lua_string`, `ui_snippet` or `sources`
function IconBrowserView.cb_on_copy_pressed(self, copy_format)
    self:_copy_selected(copy_format)
end

--- Pressed callback of the inspector's favorite button.
function IconBrowserView.cb_on_favorite_pressed(self)
    self:_toggle_selected_favorite()
end

-- ----------------------------------------------------------------------------
-- Toolbar and inspector presentation
-- ----------------------------------------------------------------------------

--- Labels a list column header, with the sort direction when it is the sorted column.
-- string: widget_name header widget
-- string: label_id localization id of the column name
-- string: key sort key of the column
-- ?string: sort_key sort key of the active sort
-- bool: descending whether the active sort descends
function IconBrowserView._set_column_header(self, widget_name, label_id, key, sort_key, descending)
    local content = self._widgets_by_name[widget_name].content
    local label = upper(mod:localize(label_id))
    local is_active = key == sort_key

    if is_active then
        local marker_id

        if key == "index" then
            marker_id = descending and "sort_marker_numeric_descending" or "sort_marker_numeric_ascending"
        else
            marker_id = descending and "sort_marker_descending" or "sort_marker_ascending"
        end

        label = label .. " " .. mod:localize(marker_id)
    end

    content.text = label
    content.is_active = is_active
end

--- Dropdown values are cropped once when they change instead of fitting the font every frame.
-- string: widget_name dropdown button widget
-- string: text value to show
function IconBrowserView._set_dropdown_text(self, widget_name, text)
    local widget = self._widgets_by_name[widget_name]
    local max_width = self._ui_scenegraph[widget_name].size[1] - 24

    widget.content.text = self:_fit_text(text, widget.style.text, max_width, false)
end

--- Updates the toolbar's values and toggle states, the clear buttons and the list column headers.
function IconBrowserView._refresh_toolbar(self)
    local widgets_by_name = self._widgets_by_name
    local state = self._query_state
    local is_list = self._view_mode == "list"
    local density = self._density
    local sort_key = Query.sort_key(state.sort)
    local descending = Query.is_descending(state.sort)

    self:_set_dropdown_text("category_button", upper(self._assets.category_labels[state.category] or ""))
    self:_set_dropdown_text("sort_button", upper(mod:localize("sort_short_" .. state.sort)))
    widgets_by_name.favorites_button.content.hotspot.is_selected = state.favorites_only
    widgets_by_name.recent_button.content.hotspot.is_selected = state.recent_only
    widgets_by_name.recent_clear_button.visible = state.recent_only
    widgets_by_name.view_grid_button.content.hotspot.is_selected = not is_list
    widgets_by_name.view_list_button.content.hotspot.is_selected = is_list
    widgets_by_name.density_compact_button.content.hotspot.is_selected = density == "compact"
    widgets_by_name.density_normal_button.content.hotspot.is_selected = density == "normal"
    widgets_by_name.density_large_button.content.hotspot.is_selected = density == "large"
    widgets_by_name.search_clear.visible = state.text ~= ""

    self:_set_column_header("list_header_name", "column_name", "name", sort_key, descending)
    self:_set_column_header("list_header_id", "column_id", "index", sort_key, descending)
    self:_set_column_header("list_header_category", "column_category", "category", sort_key, descending)
    self:_set_column_header("list_header_path", "column_path", "path", sort_key, descending)
end

--- Labels the preview controls and applies the background colour and the zoom's texture coordinates.
function IconBrowserView._refresh_preview_controls(self)
    local widgets_by_name = self._widgets_by_name
    local background = self._preview_background
    local zoom = ZOOM_LEVELS[self._preview_zoom_index]
    local aspect = ASPECTS[self._preview_aspect_index]
    local zoom_text, aspect_text

    if zoom == 1 then
        zoom_text = mod:localize("preview_zoom_fit")
    else
        zoom_text = mod:localize("preview_zoom_format", zoom)
    end

    if aspect.auto then
        aspect_text = mod:localize("preview_aspect_auto")
    else
        aspect_text = mod:localize("preview_aspect_format", aspect.label)
    end

    widgets_by_name.preview_background_button.content.text = upper(mod:localize("preview_background_" .. background))
    widgets_by_name.preview_zoom_button.content.text = upper(zoom_text)
    widgets_by_name.preview_aspect_button.content.text = upper(aspect_text)

    local preview_widgets = self._preview_widgets
    local half = 0.5 / zoom
    local uvs = preview_widgets.preview_icon.style.icon.uvs

    copy_color(background == "light" and PALETTE.preview_light or PALETTE.preview_dark,
        preview_widgets.preview_background.style.background.color)
    uvs[1][1] = 0.5 - half
    uvs[1][2] = 0.5 - half
    uvs[2][1] = 0.5 + half
    uvs[2][2] = 0.5 + half
end

--- Path split into lines at "/" so it wraps inside the inspector; copying always uses the full path.
-- string: path material path
-- tab: style metadata text style
-- number: max_width line width in UI units
-- tab: lines array the coloured lines are written into
-- int: count lines already written
-- treturn: int lines written afterwards
function IconBrowserView._append_path_lines(self, path, style, max_width, lines, count)
    local line = ""
    local limit = max_width - CROP_MARGIN

    for segment in gmatch(path, "[^/]+/?") do
        local candidate = line .. segment
        local too_wide = false

        if line ~= "" then
            local width = self:_text_width(candidate, style)

            too_wide = width ~= nil and width > limit
        end

        if too_wide then
            count = count + 1
            lines[count] = VALUE_TAG .. line .. RESET_TAG
            line = segment
        else
            line = candidate
        end
    end

    if line ~= "" then
        count = count + 1
        lines[count] = VALUE_TAG .. line .. RESET_TAG
    end

    return count
end

--- Builds the inspector's metadata text: the wrapped path, filename, browser ID, category, name
-- source, preview status, size and source references, with coloured labels. The preview status is
-- red when the preview failed or the material is not loaded, and says "not loaded yet" while a global
-- game package still loads.
-- tab: asset selected asset
-- bool: preview_available whether its preview may be drawn
-- bool: material_loaded whether the engine has its material loaded
-- treturn: string
function IconBrowserView._build_metadata(self, asset, preview_available, material_loaded)
    local labels = self._field_labels
    local lines = self._metadata_lines
    local style = self._widgets_by_name.inspector_metadata.style.text
    local count = 1
    local name_text, preview_text

    lines[1] = labels.path
    count = self:_append_path_lines(asset.path, style, self._layout.metadata_width, lines, count)

    if asset.name_source == Assets.NAME_SOURCE_LOCALIZED then
        name_text = mod:localize("name_source_localized", asset.name_key)
    elseif asset.name_source == Assets.NAME_SOURCE_DEFINITION then
        name_text = mod:localize("name_source_definition", asset.name_origin)
    else
        name_text = mod:localize("name_source_filename")
    end

    if asset.name_uses > 0 then
        name_text = name_text .. " " .. mod:localize("name_source_more_uses", asset.name_uses)
    end

    if preview_available then
        preview_text = mod:localize("preview_status_available")
    elseif not material_loaded and self._global_packages_loading then
        preview_text = mod:localize("preview_status_loading")
    elseif not material_loaded then
        preview_text = WARNING_TAG .. mod:localize("preview_status_not_loaded") .. RESET_TAG
    else
        preview_text = WARNING_TAG .. mod:localize("preview_status_failed") .. RESET_TAG
    end

    lines[count + 1] = labels.filename .. asset.filename
    lines[count + 2] = labels.id .. asset.id_text
    lines[count + 3] = labels.category .. asset.category_label
    lines[count + 4] = labels.name .. name_text
    lines[count + 5] = labels.preview .. preview_text
    lines[count + 6] = labels.size .. self:_fit_field("size", self:_size_text(asset), style)
    lines[count + 7] = labels.used_in .. self:_fit_field("used_in", self:_used_in_text(asset), style)
    count = count + 7

    if asset.item_refs then
        count = count + 1
        lines[count] = labels.items .. self:_fit_field("items", self:_items_text(asset), style)
    end

    return concat(lines, "\n", 1, count)
end

--- Crops a metadata value so that it and its label fit on one line of the metadata block.
-- string: field key of the label in `_field_label_texts`
-- string: value value text
-- tab: style metadata text style
-- treturn: string
function IconBrowserView._fit_field(self, field, value, style)
    local label_width = self:_text_width(self._field_label_texts[field], style) or 0

    return self:_fit_text(value, style, self._layout.metadata_width - label_width, false)
end

--- Size line of the metadata: the sizes the game draws the asset at, or that none is known.
-- tab: asset selected asset
-- treturn: string
function IconBrowserView._size_text(self, asset)
    local sizes = asset.usage_sizes

    if not sizes then
        return mod:localize("size_unknown")
    end

    return mod:localize("size_drawn_at", concat(sizes, ", ", 1, min(#sizes, MAX_METADATA_SIZES)))
end

--- Used-in line of the metadata: the first script line naming the asset, with the count of the rest.
-- tab: asset selected asset
-- treturn: string
function IconBrowserView._used_in_text(self, asset)
    local refs = asset.source_refs

    if not refs then
        return mod:localize("used_in_none")
    end

    local text = match(refs[1], "([^/]+)$") or refs[1]
    local more = #refs - 1

    if more > 0 then
        text = text .. " " .. mod:localize("more_format", more)
    end

    return text
end

--- Items line of the metadata: the first item using the asset as its HUD icon, by its localized name
-- where the game has one, with the count of the others.
-- tab: asset selected asset with `item_refs`
-- treturn: string
function IconBrowserView._items_text(self, asset)
    local items = asset.item_refs
    local item = items[1]
    local text = Assets.localize_key(item[2]) or match(tostring(item[1]), "([^/]+)$") or tostring(item[1])
    local more = #items - 1

    if more > 0 then
        text = text .. " " .. mod:localize("more_format", more)
    end

    return text
end

--- Subtitle of a multi-selection: the shared category, else how many categories it spans.
-- treturn: string
function IconBrowserView._selection_subtitle(self)
    local list = self._selection_list
    local category = list[1].category
    local seen = { [category] = true }
    local category_count = 1

    for i = 2, self._selection_count do
        local other = list[i].category

        if not seen[other] then
            seen[other] = true
            category_count = category_count + 1
        end
    end

    if category_count == 1 then
        return upper(list[1].category_label)
    end

    return upper(mod:localize("selection_categories", category_count))
end

--- Metadata of a multi-selection: one line per selected asset (browser ID and filename) in the
-- active sort order, as many as fit the metadata block, and how many more there are.
-- treturn: string
function IconBrowserView._build_selection_summary(self)
    local lines = self._metadata_lines
    local style = self._widgets_by_name.inspector_metadata.style.text
    local width = self._layout.metadata_width
    local list, count = self:_ordered_selection()
    local line_height = style.font_size * (style.line_spacing or 1)
    local capacity = max(2, floor(self._ui_scenegraph.inspector_metadata.size[2] / line_height) - 1)
    local shown = count <= capacity and count or capacity - 1

    lines[1] = LABEL_TAG .. upper(mod:localize("selection_header")) .. RESET_TAG

    for i = 1, shown do
        local asset = list[i]
        local text = self:_fit_text(asset.id_text .. "  " .. asset.filename, style, width, false)

        lines[i + 1] = VALUE_TAG .. text .. RESET_TAG
    end

    local line_count = shown + 1

    if shown < count then
        line_count = line_count + 1
        lines[line_count] = mod:localize("more_format", count - shown)
    end

    return concat(lines, "\n", 1, line_count)
end

--- Labels the copy and favorite buttons for one selected asset or for several, and enables the
-- actions that exist in that mode: Copy Sources and Show Related need a single asset.
-- tab: asset primary selection
-- bool: multi whether several assets are selected
function IconBrowserView._refresh_action_labels(self, asset, multi)
    local widgets_by_name = self._widgets_by_name
    local texts = self._action_texts
    local favorite_text

    if multi then
        widgets_by_name.copy_path_button.content.original_text = upper(mod:localize("action_copy_paths",
            self._selection_count))
        favorite_text = self:_selection_all_favorites() and texts.favorite_remove_all or texts.favorite_add_all
    else
        widgets_by_name.copy_path_button.content.original_text = upper(mod:localize("action_copy_path"))
        favorite_text = asset and mod.is_icon_favorite(asset.path) and texts.favorite_remove or texts.favorite_add
    end

    widgets_by_name.copy_filename_button.content.text = multi and texts.filenames or texts.filename
    widgets_by_name.copy_lua_button.content.text = multi and texts.lua_array or texts.lua_string
    widgets_by_name.copy_snippet_button.content.text = multi and texts.lua_table or texts.ui_snippet
    widgets_by_name.favorite_button.content.text = favorite_text

    if asset then
        widgets_by_name.copy_sources_button.content.hotspot.disabled = multi or asset.ref_count == 0
        widgets_by_name.related_button.content.hotspot.disabled = multi
    end
end

--- Fills the inspector from the selection; without one it shows the empty state and disables the
-- actions. With several assets selected it previews the primary one and lists the selection.
function IconBrowserView._refresh_inspector(self)
    self._inspector_dirty = false

    local widgets_by_name = self._widgets_by_name
    local asset = self._selected_asset
    local has_asset = asset ~= nil
    local preview_widgets = self._preview_widgets
    local icon_content = preview_widgets.preview_icon.content
    local fallback_content = preview_widgets.preview_fallback.content

    for i = 1, #INSPECTOR_CONTENT_WIDGETS do
        widgets_by_name[INSPECTOR_CONTENT_WIDGETS[i]].visible = has_asset
    end

    for i = 1, #INSPECTOR_ACTION_WIDGETS do
        widgets_by_name[INSPECTOR_ACTION_WIDGETS[i]].content.hotspot.disabled = not has_asset
    end

    widgets_by_name.inspector_empty.visible = not has_asset
    icon_content.has_asset = has_asset
    fallback_content.has_asset = has_asset

    if not has_asset then
        icon_content.icon = ""
        icon_content.icon_available = false
        icon_content.icon_source = false
        fallback_content.icon_available = false
        self:_refresh_action_labels(nil, false)

        return
    end

    local path = asset.path
    local loaded = self:_is_material_loaded(path)
    local available = loaded and mod.can_render_icon_path(path)
    local multi = self._selection_count > 1

    icon_content.icon_source = path
    icon_content.icon = available and path or ""
    icon_content.icon_available = available
    fallback_content.icon_available = available
    _set_fallback(fallback_content, "text", preview_widgets.preview_fallback.style.text, self._fallback_texts.long,
        loaded, self._global_packages_loading)

    if multi then
        widgets_by_name.inspector_title.content.text = mod:localize("selection_title", self._selection_count)
        widgets_by_name.inspector_subtitle.content.text = self:_selection_subtitle()
        widgets_by_name.inspector_metadata.content.text = self:_build_selection_summary()
    else
        widgets_by_name.inspector_title.content.text = asset.display_name
        widgets_by_name.inspector_subtitle.content.text = upper(asset.category_label)
        widgets_by_name.inspector_metadata.content.text = self:_build_metadata(asset, available, loaded)
    end

    self:_refresh_action_labels(asset, multi)

    if ASPECTS[self._preview_aspect_index].auto then
        self:_layout_preview()
        self:_force_update_scenegraph()
    end

    self:_refresh_preview_controls()
end

-- ----------------------------------------------------------------------------
-- Tooltip and status
-- ----------------------------------------------------------------------------

--- Hides the hover tooltip.
function IconBrowserView._hide_tooltip(self)
    local widget = self._widgets_by_name.tooltip

    if widget then
        widget.visible = false
    end

    self._tooltip_shown = false
end

--- Shows the full path of a hovered asset below its slot, or above it near the bottom of the
-- browser; a path too long for the browser is cropped from the left.
-- tab: asset hovered asset
-- ?int: slot_index slot it is shown in
function IconBrowserView._show_tooltip(self, asset, slot_index)
    local slot = slot_index and self._slots[slot_index]

    if not slot then
        return
    end

    local widget = self._widgets_by_name.tooltip
    local text_style = widget.style.text
    local layout = self._layout
    local padding = LAYOUT.tooltip_padding
    local max_width = min(layout.frame_width - LAYOUT.padding * 2, layout.area_width + LAYOUT.area_padding * 2)
    local text = asset.path
    local text_width = self:_text_width(text, text_style)

    text_width = text_width and floor(text_width) + CROP_MARGIN or LAYOUT.tooltip_max_width

    if text_width > max_width - padding * 2 then
        text = self:_fit_text(text, text_style, max_width - padding * 2, true)
        text_width = max_width - padding * 2
    end

    local width = text_width + padding * 2 + 8
    local height = floor(text_style.font_size * 1.4) + padding * 2
    local slot_x = layout.browser_x + layout.area_x + slot.offset[1]
    local slot_y = layout.browser_y + layout.area_y + slot.offset[2]
    local x = _clamp(slot_x, LAYOUT.padding, layout.frame_width - LAYOUT.padding - width)
    local y = slot_y + self._slot_height + 6

    if y + height > layout.status_y then
        y = slot_y - height - 6
    end

    widget.content.text = text
    self:_place("tooltip", x, y, width, height)
    self:_force_update_scenegraph()
    widget.visible = true
    self._tooltip_shown = true
end

--- Shows the tooltip once the same asset stayed hovered for `TOOLTIP_DELAY` seconds, and hides it
-- when the hover moves.
-- number: dt frame delta time
function IconBrowserView._update_tooltip(self, dt)
    local asset = self._hovered_asset

    if asset ~= self._tooltip_asset then
        self._tooltip_asset = asset
        self._tooltip_timer = 0

        if self._tooltip_shown then
            self:_hide_tooltip()
        end

        return
    end

    if asset and not self._tooltip_shown and not self._open_popup then
        local timer = self._tooltip_timer + dt

        self._tooltip_timer = timer

        if timer >= TOOLTIP_DELAY then
            self:_show_tooltip(asset, self._hovered_slot)
        end
    end
end

--- Shows a status message in the header, which fades out after `COPY_STATUS_DURATION` seconds.
-- ?string: message status text
-- ?bool: is_error show it in the error colour
function IconBrowserView._set_copy_status(self, message, is_error)
    self._copy_status_message = message or ""
    self._copy_status_is_error = is_error == true
    self._copy_status_timer = (message and message ~= "") and COPY_STATUS_DURATION or 0
    self:_update_copy_status_widget()
end

--- Writes the status text, its colour and its fading alpha into the header widget.
function IconBrowserView._update_copy_status_widget(self)
    local widget = self._widgets_by_name.copy_status_text

    if not widget or not widget.content or not widget.style or not widget.style.text then
        return
    end

    local style = widget.style.text
    local message = self._copy_status_message or ""
    local timer = self._copy_status_timer or 0
    local color = self._copy_status_is_error and PALETTE.status_error or PALETTE.status_success
    local alpha = 0

    if message ~= "" and timer > 0 then
        alpha = 255

        if timer < COPY_STATUS_FADE_DURATION then
            alpha = floor(255 * (timer / COPY_STATUS_FADE_DURATION) + 0.5)
        end
    else
        message = ""
    end

    widget.content.text = message
    style.text_color[1] = alpha
    style.text_color[2] = color[2]
    style.text_color[3] = color[3]
    style.text_color[4] = color[4]
end

-- ----------------------------------------------------------------------------
-- Input, update and draw
-- ----------------------------------------------------------------------------

--- Handles keyboard and mouse input each frame. While the search field has focus, only Enter is
-- handled, leaving the field. Otherwise Ctrl+F focuses the field, Ctrl+C copies the path (the
-- paths of a multi-selection), Ctrl+A selects every listed result, a click outside an open menu
-- closes it without reaching the widgets below, and the arrow keys move the focus.
-- tab: input_service view input service
-- number: dt frame delta time
-- number: t time
function IconBrowserView._handle_input(self, input_service, dt, t)
    if self:_is_typing() then
        if input_service:get("confirm_pressed") then
            self:_stop_search_input()
        end

        return
    end

    local keys = _keyboard_keys_lookup()

    if keys and _ctrl_down(keys) then
        local keyboard = Keyboard

        if keyboard.pressed(keys.f) then
            self:_close_popup()
            self._pending_search_focus = SEARCH_FOCUS_DELAY

            return
        elseif keyboard.pressed(keys.c) then
            self:_copy_selected("path")

            return
        elseif keys.a and not self._open_popup and keyboard.pressed(keys.a) then
            self:_select_all_results()

            return
        end
    end

    if self._open_popup then
        if input_service:get("left_pressed") and not self:_popup_hovered() then
            self:_close_popup()
            self._swallow_input = true
        end

        return
    end

    if input_service:get("navigate_up_continuous") then
        self:_move_focus(0, -1)
    elseif input_service:get("navigate_down_continuous") then
        self:_move_focus(0, 1)
    elseif input_service:get("navigate_left_continuous") then
        self:_move_focus(-1, 0)
    elseif input_service:get("navigate_right_continuous") then
        self:_move_focus(1, 0)
    end
end

--- Stops drawing a widget's icon after a draw error and records the failure for its path.
-- tab: widget slot or preview widget
-- ?param: error_message error raised by the draw
function IconBrowserView._disable_icon_preview(self, widget, error_message)
    local content = widget and widget.content

    if not content or content.icon_available == false then
        return
    end

    local icon_path = content.icon_source or content.path or content.icon

    content.icon_available = false
    content.icon = ""

    if icon_path then
        mod.mark_icon_render_failed(icon_path, error_message)
    end

    local selected_asset = self._selected_asset

    if selected_asset and selected_asset.path == icon_path then
        self._inspector_dirty = true
    end
end

--- Updates the view each frame: layout revision, search focus and text, favorites and history
-- changes, the query, scrolling and binding, the inspector, the tooltip and the status fade.
-- number: dt frame delta time
-- number: t time
-- tab: input_service view input service
function IconBrowserView.update(self, dt, t, input_service)
    IconBrowserView.super.update(self, dt, t, input_service)

    if not self._entered_browser then
        return
    end

    self:_apply_layout(false)
    self:_update_search_focus()
    self:_sync_search_text()

    if self._global_packages_loading and not mod.are_global_icon_packages_loading() then
        self._global_packages_loading = false
        self:_refresh_material_states()
    end

    local lists_revision = mod._icon_lists_revision

    if lists_revision ~= self._icon_lists_revision then
        local state = self._query_state

        self._icon_lists_revision = lists_revision
        self._bind_dirty = true
        self._inspector_dirty = true

        if state.favorites_only or state.recent_only then
            self._results_dirty = true
        end
    end

    if self._results_dirty then
        self:_run_query()
    end

    self:_update_scroll()

    if self._inspector_dirty then
        self:_refresh_inspector()
    end

    self:_update_tooltip(dt)

    if self._copy_status_timer and self._copy_status_timer > 0 then
        self._copy_status_timer = max(self._copy_status_timer - dt, 0)

        if self._copy_status_timer == 0 then
            self._copy_status_message = ""
        end

        self:_update_copy_status_widget()
    end
end

--- Chrome widgets are drawn inside `pcall` as well, so a missing shared material hides one widget
-- instead of breaking the whole view.
-- number: dt frame delta time
-- number: t time
-- tab: input_service input service of this draw
-- tab: ui_renderer active UI renderer
-- tab: render_settings render settings
function IconBrowserView._draw_widgets(self, dt, t, input_service, ui_renderer, render_settings)
    local widgets = self._widgets

    for i = 1, self._widget_count do
        local widget = widgets[i]

        if widget.visible then
            local ok, error_message = pcall(UIWidget.draw, widget, ui_renderer)

            if not ok then
                widget.visible = false
                mod:echo(format("[IconBrowser] Hid widget %s after a draw error (%s)", tostring(widget.name),
                    tostring(error_message)))
            end
        end
    end
end

--- Draws the visible slots inside `pcall`, disabling the icon of a slot whose material fails, and
-- records the hovered slot and asset.
-- tab: ui_renderer active UI renderer
function IconBrowserView._draw_slots(self, ui_renderer)
    local slots = self._slots
    local hovered_asset, hovered_slot

    for k = 1, self._slot_count do
        local widget = slots[k]

        if widget.visible then
            local ok, error_message = pcall(UIWidget.draw, widget, ui_renderer)

            if not ok then
                self:_disable_icon_preview(widget, error_message)
                pcall(UIWidget.draw, widget, ui_renderer)
            end

            local content = widget.content

            if content.hotspot.is_hover then
                hovered_asset = content.asset
                hovered_slot = k
            end
        end
    end

    self._hovered_asset = hovered_asset or nil
    self._hovered_slot = hovered_slot
end

--- Draws the inspector preview: background or checkerboard, the icon inside `pcall` and the
-- fallback text.
-- tab: ui_renderer active UI renderer
function IconBrowserView._draw_preview(self, ui_renderer)
    local preview_widgets = self._preview_widgets

    if self._preview_background == "checker" then
        UIWidget.draw(preview_widgets.preview_checker, ui_renderer)
    else
        UIWidget.draw(preview_widgets.preview_background, ui_renderer)
    end

    local icon_widget = preview_widgets.preview_icon

    if icon_widget.content.icon_available then
        local ok, error_message = pcall(UIWidget.draw, icon_widget, ui_renderer)

        if not ok then
            self:_disable_icon_preview(icon_widget, error_message)
            preview_widgets.preview_fallback.content.icon_available = false
            self._bind_dirty = true
        end
    end

    UIWidget.draw(preview_widgets.preview_fallback, ui_renderer)
end

--- Draws the chrome and the legend, then the slots and the preview, then an open menu. While a menu
-- is open, or in the frame a click closed it, everything below the menu is drawn with the null input
-- service, so clicks never reach it.
-- number: dt frame delta time
-- number: t time
-- tab: input_service view input service
-- int: layer start layer
function IconBrowserView.draw(self, dt, t, input_service, layer)
    local blocked = self._open_popup ~= nil or self._swallow_input
    local base_input_service = blocked and input_service:null_service() or input_service

    IconBrowserView.super.draw(self, dt, t, base_input_service, layer)

    if not self._entered_browser then
        return
    end

    local ui_renderer = self._ui_renderer
    local ui_scenegraph = self._ui_scenegraph
    local render_settings = self._render_settings

    UIRenderer.begin_pass(ui_renderer, ui_scenegraph, base_input_service, dt, render_settings)
    self:_draw_slots(ui_renderer)

    if self._selected_asset then
        self:_draw_preview(ui_renderer)
    end

    UIRenderer.end_pass(ui_renderer)

    local popup_id = self._open_popup

    if popup_id then
        local options = self._popup_options[popup_id]

        UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt, render_settings)

        for i = 1, self._popup_option_counts[popup_id] do
            UIWidget.draw(options[i], ui_renderer)
        end

        UIRenderer.end_pass(ui_renderer)
    end

    self._swallow_input = false
end

return IconBrowserView
