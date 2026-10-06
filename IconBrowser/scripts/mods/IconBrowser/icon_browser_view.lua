local mod = get_mod("IconBrowser")

local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWidgetGrid = require("scripts/ui/widget_logic/ui_widget_grid")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local ScrollbarPassTemplates = require("scripts/ui/pass_templates/scrollbar_pass_templates")
local ViewElementInputLegend = require("scripts/ui/view_elements/view_element_input_legend/view_element_input_legend")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local clone = table.clone
local max = math.max
local floor = math.floor
local COPY_STATUS_DURATION = 2
local COPY_STATUS_FADE_DURATION = 0.25
local COPY_STATUS_SUCCESS_COLOR = { 255, 120, 220, 140 }
local COPY_STATUS_ERROR_COLOR = { 255, 255, 120, 120 }

local function _clone(style)
    return clone(style)
end

local function _scaled(value, scale)
    return max(1, floor(value * scale + 0.5))
end

local function _scaled_font_size(base_font_size, scale, min_value)
    return max(min_value, floor(base_font_size * scale + 0.5))
end

local function _make_left_aligned_text_style(base_style)
    local style = _clone(base_style)
    style.text_horizontal_alignment = "left"
    style.horizontal_alignment = "left"
    style.vertical_alignment = "center"
    style.text_vertical_alignment = "center"

    return style
end

local function _make_header_text_style(base_style, offset_x)
    local style = _clone(base_style)
    style.offset = { offset_x, 0, 3 }

    return style
end

local VIEW_NAME = "icon_browser_view"

local BASE_LAYOUT = {
    background = {
        size = { 1500, 920 },
        position = { 0, 0, 1 },
    },
    title_text = {
        size = { 1420, 50 },
        position = { 40, 10, 2 },
    },
    copy_status_text = {
        size = { 1420, 50 },
        position = { 40, 10, 2 },
    },
    table_header = {
        size = { 1410, 40 },
        position = { 40, 70, 2 },
    },
    grid_area = {
        size = { 1410, 780 },
        position = { 40, 118, 1 },
    },
    scrollbar = {
        size = { 10, 780 },
        position = { 22, 0, 2 },
    },
    columns = {
        id_x = 90,
        path_x = 170,
    },
    row_height = 64,
    icon_size = 48,
}

local IconBrowserView = class("IconBrowserView", "BaseView")

IconBrowserView.init = function(self, settings)
    local scenegraph_definition = {
        screen = UIWorkspaceSettings.screen,

        background = {
            parent = "screen",
            horizontal_alignment = "center",
            vertical_alignment = "center",
            size = clone(BASE_LAYOUT.background.size),
            position = clone(BASE_LAYOUT.background.position),
        },

        title_text = {
            parent = "background",
            horizontal_alignment = "left",
            vertical_alignment = "top",
            size = clone(BASE_LAYOUT.title_text.size),
            position = clone(BASE_LAYOUT.title_text.position),
        },

        copy_status_text = {
            parent = "background",
            horizontal_alignment = "left",
            vertical_alignment = "top",
            size = clone(BASE_LAYOUT.copy_status_text.size),
            position = clone(BASE_LAYOUT.copy_status_text.position),
        },

        table_header = {
            parent = "background",
            horizontal_alignment = "left",
            vertical_alignment = "top",
            size = clone(BASE_LAYOUT.table_header.size),
            position = clone(BASE_LAYOUT.table_header.position),
        },

        grid_area = {
            parent = "background",
            horizontal_alignment = "left",
            vertical_alignment = "top",
            size = clone(BASE_LAYOUT.grid_area.size),
            position = clone(BASE_LAYOUT.grid_area.position),
        },

        grid_content_pivot = {
            parent = "grid_area",
            horizontal_alignment = "left",
            vertical_alignment = "top",
            size = { 0, 0 },
            position = { 0, 0, 1 },
        },

        scrollbar = {
            parent = "grid_area",
            horizontal_alignment = "right",
            vertical_alignment = "top",
            size = clone(BASE_LAYOUT.scrollbar.size),
            position = clone(BASE_LAYOUT.scrollbar.position),
        },
    }

    local header_style = _make_left_aligned_text_style(UIFontSettings.header_2)
    local title_style = _clone(UIFontSettings.header_1)
    title_style.text_horizontal_alignment = "left"
    title_style.horizontal_alignment = "left"
    local copy_status_style = _clone(UIFontSettings.body_small or UIFontSettings.body)
    copy_status_style.text_horizontal_alignment = "right"
    copy_status_style.horizontal_alignment = "right"
    copy_status_style.vertical_alignment = "center"
    copy_status_style.text_vertical_alignment = "center"
    copy_status_style.text_color = { 0, COPY_STATUS_SUCCESS_COLOR[2], COPY_STATUS_SUCCESS_COLOR[3],
        COPY_STATUS_SUCCESS_COLOR[4] }

    local widget_definitions = {
        background = UIWidget.create_definition({
            { pass_type = "rect", style = { color = { 185, 0, 0, 0 } } },
        }, "background"),

        title_text = UIWidget.create_definition({
            { value_id = "text", pass_type = "text", value = mod:localize("mod_name"), style = title_style },
        }, "title_text"),

        copy_status_text = UIWidget.create_definition({
            { value_id = "text", pass_type = "text", value = "", style = copy_status_style },
        }, "copy_status_text"),

        table_header = UIWidget.create_definition({
            { pass_type = "rect", style = { color = { 180, 25, 25, 25 } } },
            {
                value_id = "icon_header",
                pass_type = "text",
                value = mod:localize("column_icon"),
                style = _make_header_text_style(header_style, 12),
            },
            {
                value_id = "id_header",
                pass_type = "text",
                value = mod:localize("column_id"),
                style = _make_header_text_style(header_style, BASE_LAYOUT.columns.id_x),
            },
            {
                value_id = "path_header",
                pass_type = "text",
                value = mod:localize("column_path"),
                style = _make_header_text_style(header_style, BASE_LAYOUT.columns.path_x),
            },
        }, "table_header"),

        scrollbar = UIWidget.create_definition(ScrollbarPassTemplates.default_scrollbar, "scrollbar", {
            scroll_speed = 10,
            scroll_amount = 0.15,
        }),
    }

    local definitions = {
        scenegraph_definition = scenegraph_definition,
        widget_definitions = widget_definitions,
        legend_inputs = {
            {
                input_action = "back",
                on_pressed_callback = "cb_on_back_pressed",
                display_name = "loc_settings_menu_close_menu",
                alignment = "left_alignment",
            },
        },
    }

    IconBrowserView.super.init(self, definitions, settings)

    self._rows = {}
    self._row_align = {}
    self._grid = nil

    self._base_title_font_size = (title_style and title_style.font_size) or 32
    self._base_header_font_size = (header_style and header_style.font_size) or 24
    self._base_copy_status_font_size = (copy_status_style and copy_status_style.font_size) or 18
    self._row_height = BASE_LAYOUT.row_height
    self._icon_size = BASE_LAYOUT.icon_size
    self._id_column_x = BASE_LAYOUT.columns.id_x
    self._path_column_x = BASE_LAYOUT.columns.path_x
    self._grid_width = BASE_LAYOUT.grid_area.size[1]
    self._current_scale = nil
    self._current_offset_x = nil
    self._current_offset_y = nil
    self._copy_status_message = ""
    self._copy_status_is_error = false
    self._copy_status_timer = 0
end

function IconBrowserView.on_enter(self)
    IconBrowserView.super.on_enter(self)
    mod._icon_browser_view_open = true
    self:_setup_input_legend()
    self:apply_layout_settings(true)
    self._copy_status_message = ""
    self._copy_status_is_error = false
    self._copy_status_timer = 0
    self:_update_copy_status_widget()
end

function IconBrowserView.on_exit(self)
    mod._icon_browser_view_open = false

    if self._input_legend_element then
        self:_remove_element("input_legend")
        self._input_legend_element = nil
    end

    IconBrowserView.super.on_exit(self)
end

function IconBrowserView.cb_on_back_pressed(self)
    Managers.ui:close_view(VIEW_NAME)
end

function IconBrowserView._set_copy_status(self, message, is_error)
    self._copy_status_message = message or ""
    self._copy_status_is_error = is_error == true
    self._copy_status_timer = (message and message ~= "") and COPY_STATUS_DURATION or 0
    self:_update_copy_status_widget()
end

function IconBrowserView._update_copy_status_widget(self)
    local widget = self._widgets_by_name.copy_status_text

    if not widget or not widget.content or not widget.style or not widget.style.text then
        return
    end

    local style = widget.style.text
    local message = self._copy_status_message or ""
    local timer = self._copy_status_timer or 0
    local color = self._copy_status_is_error and COPY_STATUS_ERROR_COLOR or COPY_STATUS_SUCCESS_COLOR
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

function IconBrowserView._setup_input_legend(self)
    local input_legend_element = self:_add_element(ViewElementInputLegend, "input_legend", 10)
    local legend_inputs = self._definitions.legend_inputs

    self._input_legend_element = input_legend_element
    input_legend_element:set_display_name(mod:localize("mod_name"))

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

local function _row_definition(row_height, icon_size, id_column_x, path_column_x, grid_width, scale)
    local id_style = _make_left_aligned_text_style(UIFontSettings.list_button)
    id_style.offset = { id_column_x, 0, 3 }

    local path_style = _make_left_aligned_text_style(UIFontSettings.list_button)
    path_style.offset = { path_column_x, 0, 3 }

    local icon_style = {
        vertical_alignment = "center",
        horizontal_alignment = "left",
        size = { icon_size, icon_size },
        offset = { _scaled(12, scale), 0, 2 },
        color = { 255, 255, 255, 255 },
    }

    if id_style.font_size then
        id_style.font_size = _scaled_font_size(id_style.font_size, scale, 10)
    end

    if path_style.font_size then
        path_style.font_size = _scaled_font_size(path_style.font_size, scale, 10)
    end

    return UIWidget.create_definition({
        { pass_type = "hotspot", content_id = "hotspot" },
        { pass_type = "rect",    style_id = "bg",       style = { color = { 120, 0, 0, 0 } } },
        {
            value_id = "icon",
            pass_type = "texture",
            style_id = "icon",
            value = "",
            style = icon_style,
            visibility_function = function(content)
                return content.icon_available and content.icon ~= nil and content.icon ~= ""
            end,
        },
        { value_id = "icon_id", pass_type = "text", style_id = "icon_id", value = "", style = id_style },
        { value_id = "path",    pass_type = "text", style_id = "path",    value = "", style = path_style },
        {
            pass_type = "rect",
            style_id = "hover",
            style = { color = { 0, 255, 255, 255 }, offset = { 0, 0, 10 } },
            change_function = function(content, style)
                local hotspot = content.hotspot
                style.color[1] = (hotspot and (hotspot.is_hover or hotspot.is_focused)) and 35 or 0
            end,
        },
    }, "grid_content_pivot", nil, { grid_width, row_height })
end

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
end

function IconBrowserView._build_rows(self)
    local icons = mod.get_icon_paths()
    local widgets = {}
    local align = {}
    local row_def = _row_definition(self._row_height, self._icon_size, self._id_column_x, self._path_column_x,
        self._grid_width, self._current_scale or 1)

    for i, path in ipairs(icons) do
        local widget = self:_create_widget("icon_row_" .. i, row_def)
        local content = widget.content
        local style = widget.style
        local icon_available = mod.can_render_icon_path(path)

        content.icon_source = path
        content.icon_available = icon_available
        content.icon = icon_available and path or ""
        content.icon_id = "#" .. i
        content.path = path

        if style and style.bg and style.bg.color then
            style.bg.color[1] = (i % 2 == 1) and 105 or 125
        end

        content.hotspot.pressed_callback = function()
            local copied, status_message = mod.copy_icon_path_to_clipboard(i, path)

            self:_set_copy_status(status_message, not copied)
        end

        widgets[i] = widget
        align[i] = widget
    end

    self._rows = widgets
    self._row_align = align
end

function IconBrowserView._setup_grid(self)
    local grid = UIWidgetGrid:new(self._rows, self._row_align, self._ui_scenegraph, "grid_area", "down", { 0, 2 }, nil,
        true)
    local scrollbar = self._widgets_by_name.scrollbar
    grid:assign_scrollbar(scrollbar, "grid_content_pivot", "grid_area", true)
    grid:set_scrollbar_progress(0)
    self._grid = grid
end

function IconBrowserView._apply_scenegraph_layout(self, scale, offset_x, offset_y)
    local ui_scenegraph = self._ui_scenegraph
    local background = ui_scenegraph.background
    local title_text = ui_scenegraph.title_text
    local copy_status_text = ui_scenegraph.copy_status_text
    local table_header = ui_scenegraph.table_header
    local grid_area = ui_scenegraph.grid_area
    local scrollbar = ui_scenegraph.scrollbar

    background.size[1] = _scaled(BASE_LAYOUT.background.size[1], scale)
    background.size[2] = _scaled(BASE_LAYOUT.background.size[2], scale)
    background.position[1] = offset_x
    background.position[2] = offset_y

    title_text.size[1] = _scaled(BASE_LAYOUT.title_text.size[1], scale)
    title_text.size[2] = _scaled(BASE_LAYOUT.title_text.size[2], scale)
    title_text.position[1] = _scaled(BASE_LAYOUT.title_text.position[1], scale)
    title_text.position[2] = _scaled(BASE_LAYOUT.title_text.position[2], scale)

    copy_status_text.size[1] = _scaled(BASE_LAYOUT.copy_status_text.size[1], scale)
    copy_status_text.size[2] = _scaled(BASE_LAYOUT.copy_status_text.size[2], scale)
    copy_status_text.position[1] = _scaled(BASE_LAYOUT.copy_status_text.position[1], scale)
    copy_status_text.position[2] = _scaled(BASE_LAYOUT.copy_status_text.position[2], scale)

    table_header.size[1] = _scaled(BASE_LAYOUT.table_header.size[1], scale)
    table_header.size[2] = _scaled(BASE_LAYOUT.table_header.size[2], scale)
    table_header.position[1] = _scaled(BASE_LAYOUT.table_header.position[1], scale)
    table_header.position[2] = _scaled(BASE_LAYOUT.table_header.position[2], scale)

    grid_area.size[1] = _scaled(BASE_LAYOUT.grid_area.size[1], scale)
    grid_area.size[2] = _scaled(BASE_LAYOUT.grid_area.size[2], scale)
    grid_area.position[1] = _scaled(BASE_LAYOUT.grid_area.position[1], scale)
    grid_area.position[2] = _scaled(BASE_LAYOUT.grid_area.position[2], scale)

    scrollbar.size[1] = _scaled(BASE_LAYOUT.scrollbar.size[1], scale)
    scrollbar.size[2] = _scaled(BASE_LAYOUT.scrollbar.size[2], scale)
    scrollbar.position[1] = _scaled(BASE_LAYOUT.scrollbar.position[1], scale)
    scrollbar.position[2] = _scaled(BASE_LAYOUT.scrollbar.position[2], scale)
end

function IconBrowserView._apply_widget_layout(self, scale)
    local title_widget = self._widgets_by_name.title_text
    local copy_status_widget = self._widgets_by_name.copy_status_text
    local header_widget = self._widgets_by_name.table_header

    if title_widget and title_widget.style and title_widget.style.text and title_widget.style.text.font_size then
        title_widget.style.text.font_size = _scaled_font_size(self._base_title_font_size, scale, 14)
    end

    if copy_status_widget and copy_status_widget.style and copy_status_widget.style.text and copy_status_widget.style.text.font_size then
        copy_status_widget.style.text.font_size = _scaled_font_size(self._base_copy_status_font_size, scale, 10)
    end

    if header_widget and header_widget.style then
        local header_style = header_widget.style
        local icon_header = header_style.icon_header
        local id_header = header_style.id_header
        local path_header = header_style.path_header

        if icon_header then
            icon_header.offset[1] = _scaled(12, scale)

            if icon_header.font_size then
                icon_header.font_size = _scaled_font_size(self._base_header_font_size, scale, 12)
            end
        end

        if id_header then
            id_header.offset[1] = self._id_column_x

            if id_header.font_size then
                id_header.font_size = _scaled_font_size(self._base_header_font_size, scale, 12)
            end
        end

        if path_header then
            path_header.offset[1] = self._path_column_x

            if path_header.font_size then
                path_header.font_size = _scaled_font_size(self._base_header_font_size, scale, 12)
            end
        end
    end
end

function IconBrowserView.apply_layout_settings(self, force)
    local scale = mod.get_icon_browser_scale() / 100
    local offset_x = mod.get_icon_browser_offset_x()
    local offset_y = mod.get_icon_browser_offset_y()
    local current_scale = self._current_scale
    local current_offset_x = self._current_offset_x
    local current_offset_y = self._current_offset_y
    local layout_changed = force
        or current_scale ~= scale
        or current_offset_x ~= offset_x
        or current_offset_y ~= offset_y

    if not layout_changed then
        return
    end

    local size_changed = force or current_scale ~= scale

    self._current_scale = scale
    self._current_offset_x = offset_x
    self._current_offset_y = offset_y
    self._row_height = _scaled(BASE_LAYOUT.row_height, scale)
    self._icon_size = _scaled(BASE_LAYOUT.icon_size, scale)
    self._id_column_x = _scaled(BASE_LAYOUT.columns.id_x, scale)
    self._path_column_x = _scaled(BASE_LAYOUT.columns.path_x, scale)
    self._grid_width = _scaled(BASE_LAYOUT.grid_area.size[1], scale)

    self:_apply_scenegraph_layout(scale, offset_x, offset_y)
    self:_apply_widget_layout(scale)

    if size_changed then
        self:_build_rows()
        self:_setup_grid()
    end
end

function IconBrowserView.update(self, dt, t, input_service)
    IconBrowserView.super.update(self, dt, t, input_service)
    self:apply_layout_settings(false)

    local grid = self._grid

    if grid then
        grid:update(dt, t, input_service)
    end

    if self._copy_status_timer and self._copy_status_timer > 0 then
        self._copy_status_timer = max(self._copy_status_timer - dt, 0)

        if self._copy_status_timer == 0 then
            self._copy_status_message = ""
        end

        self:_update_copy_status_widget()
    end
end

function IconBrowserView.draw(self, dt, t, input_service, layer)
    IconBrowserView.super.draw(self, dt, t, input_service, layer)

    local grid = self._grid

    if grid then
        local ui_renderer = self._ui_renderer
        local rows = self._rows

        UIRenderer.begin_pass(ui_renderer, self._ui_scenegraph, input_service, dt, self._render_settings)

        for i = 1, #rows do
            local widget = rows[i]

            if grid:is_widget_visible(widget) then
                local ok, error_message = pcall(UIWidget.draw, widget, ui_renderer)

                if not ok then
                    self:_disable_icon_preview(widget, error_message)
                    pcall(UIWidget.draw, widget, ui_renderer)
                end
            end
        end

        UIRenderer.end_pass(ui_renderer)
    end
end

return IconBrowserView
