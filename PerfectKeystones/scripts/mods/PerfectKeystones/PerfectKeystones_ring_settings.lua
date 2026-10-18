--- Shared definitions of Perfect Keystones' ring settings.
-- The `Ring` group holds the geometry of both rings (the main keystone's inner ring and the thin
-- outer ring of Until Death and Lone Wolf, set as a gap and a thickness outside the inner ring),
-- crosshair following, offsets, pulses and the stack and time labels, each label with its own
-- offsets nested under its checkbox; the `Appearance` group the colours and the near-expiry
-- threshold. This module is the single source of their DMF widget definitions and
-- defaults: `PerfectKeystones_data.lua` builds both groups from it, `PerfectKeystones.lua` the
-- settings cache, and the HUD element reads the defaults as fallbacks.
--
-- DMF loads the data file before the mod script, so both load this module through
-- `mod:io_dofile`; `PerfectKeystones.lua` stores it as `mod._ring_settings` for the HUD element.
-- module: PerfectKeystones_ring_settings
-- author: LucLeto
local pairs = pairs
local type = type

--- The ring settings module table.
local RingSettings = {}

--- The `Ring` group's settings, in menu order.
local RING_IDS = {
    "follow_crosshair",
    "ring_radius",
    "ring_thickness",
    "outer_ring_gap",
    "outer_ring_thickness",
    "offset_x",
    "offset_y",
    "pulse",
    "pulse_on_stack_change",
    "show_stack_label",
    "show_time_label"
}

RingSettings.RING_IDS = RING_IDS

--- The `Appearance` group's settings, in menu order.
local APPEARANCE_IDS = {
    "active_color",
    "unfilled_color",
    "expiring_color",
    "cooldown_color",
    "near_expiry_threshold"
}

RingSettings.APPEARANCE_IDS = APPEARANCE_IDS

--- Settings nested under another one, by parent setting id, in menu order: each label's offsets
-- sit under its checkbox, so DMF indents them there and hides them while the label is off.
local SUB_IDS = {
    show_stack_label = { "stack_label_offset_x", "stack_label_offset_y" },
    show_time_label = { "time_label_offset_x", "time_label_offset_y" }
}

--- Localization ids of settings that share their title and tooltip with others, by setting id;
-- every other setting uses its own id and `<id>_tooltip`.
local TEXT_IDS = {
    stack_label_offset_x = "label_offset_x",
    stack_label_offset_y = "label_offset_y",
    time_label_offset_x = "label_offset_x",
    time_label_offset_y = "label_offset_y"
}

--- DMF widget definitions of the ring settings, by setting id, without `setting_id` and `tooltip`.
-- Colours are DMF colour pickers with alpha, stored as `{ a, r, g, b }`.
local DEFINITIONS = {
    follow_crosshair = {
        type = "checkbox",
        default_value = true
    },
    ring_radius = {
        type = "numeric",
        -- Slightly larger than Perfect Thrust's default of 32, so both rings fit around the crosshair.
        default_value = 40,
        range = { 12, 150 },
        decimals_number = 0,
        step_size_value = 1
    },
    ring_thickness = {
        type = "numeric",
        default_value = 3,
        range = { 1, 10 },
        decimals_number = 0,
        step_size_value = 1
    },
    outer_ring_gap = {
        type = "numeric",
        default_value = 5,
        range = { 1, 30 },
        decimals_number = 0,
        step_size_value = 1
    },
    outer_ring_thickness = {
        type = "numeric",
        default_value = 2,
        range = { 1, 10 },
        decimals_number = 0,
        step_size_value = 1
    },
    offset_x = {
        type = "numeric",
        default_value = 0,
        range = { -960, 960 },
        decimals_number = 0,
        step_size_value = 1
    },
    offset_y = {
        type = "numeric",
        default_value = 0,
        range = { -540, 540 },
        decimals_number = 0,
        step_size_value = 1
    },
    pulse = {
        type = "checkbox",
        default_value = true
    },
    pulse_on_stack_change = {
        type = "checkbox",
        default_value = false
    },
    show_stack_label = {
        type = "checkbox",
        default_value = false
    },
    show_time_label = {
        type = "checkbox",
        default_value = false
    },
    -- Label offsets from each label's default place, in pixels at 1080p.
    stack_label_offset_x = {
        type = "numeric",
        default_value = 0,
        range = { -200, 200 },
        decimals_number = 0,
        step_size_value = 1
    },
    stack_label_offset_y = {
        type = "numeric",
        default_value = 0,
        range = { -200, 200 },
        decimals_number = 0,
        step_size_value = 1
    },
    time_label_offset_x = {
        type = "numeric",
        default_value = 0,
        range = { -200, 200 },
        decimals_number = 0,
        step_size_value = 1
    },
    time_label_offset_y = {
        type = "numeric",
        default_value = 0,
        range = { -200, 200 },
        decimals_number = 0,
        step_size_value = 1
    },
    active_color = {
        type = "color",
        -- Purple.
        default_value = { 235, 170, 90, 255 },
        has_alpha = true
    },
    unfilled_color = {
        type = "color",
        -- Perfect Thrust's faint grey.
        default_value = { 80, 70, 82, 86 },
        has_alpha = true
    },
    expiring_color = {
        type = "color",
        -- Red-orange.
        default_value = { 235, 255, 90, 70 },
        has_alpha = true
    },
    cooldown_color = {
        type = "color",
        -- Light blue.
        default_value = { 220, 110, 175, 235 },
        has_alpha = true
    },
    near_expiry_threshold = {
        type = "numeric",
        default_value = 25,
        range = { 0, 100 },
        decimals_number = 0,
        step_size_value = 5
    }
}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

--- Returns a deep copy of a value; other values than tables are returned as they are.
-- DMF stores default values, so no two widgets may share a table.
-- param: value value to copy
-- treturn: param the copy
local function _copy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, item in pairs(value) do
        copy[key] = _copy(item)
    end

    return copy
end

-- ----------------------------------------------------------------------------
-- Settings menu
-- ----------------------------------------------------------------------------

--- Returns the DMF widget of one ring setting, as a new table, with its nested settings as
-- sub-widgets. It is titled by its setting id, or by its shared text id from `TEXT_IDS`.
-- string: id setting id
-- treturn: tab DMF widget definition
RingSettings.widget = function (id)
    local widget = _copy(DEFINITIONS[id])
    local text_id = TEXT_IDS[id]

    widget.setting_id = id
    widget.tooltip = (text_id or id) .. "_tooltip"

    if text_id then
        widget.title = text_id
    end

    local sub_ids = SUB_IDS[id]

    if sub_ids then
        widget.sub_widgets = {}

        for i = 1, #sub_ids do
            widget.sub_widgets[i] = RingSettings.widget(sub_ids[i])
        end
    end

    return widget
end

--- Appends the widgets of the given setting ids.
-- tab: sub_widgets DMF widget list to append to
-- tab: ids setting ids in menu order
RingSettings.append_widgets = function (sub_widgets, ids)
    for i = 1, #ids do
        sub_widgets[#sub_widgets + 1] = RingSettings.widget(ids[i])
    end
end

-- ----------------------------------------------------------------------------
-- Runtime
-- ----------------------------------------------------------------------------

--- Returns the default value of a ring setting. Colour tables are shared and must not be written.
-- string: id setting id
-- treturn: param default value
RingSettings.default_value = function (id)
    return DEFINITIONS[id].default_value
end

--- Adds a setting and its nested settings to a settings cache.
-- tab: settings settings cache by setting id
-- tab: setting_ids list of cached setting ids
-- string: id setting id
local function _add_setting(settings, setting_ids, id)
    settings[id] = DEFINITIONS[id].default_value
    setting_ids[#setting_ids + 1] = id

    local sub_ids = SUB_IDS[id]

    if sub_ids then
        for i = 1, #sub_ids do
            _add_setting(settings, setting_ids, sub_ids[i])
        end
    end
end

--- Adds both groups' settings, nested ones included, to a settings cache: each default to
-- `settings` by setting id, and each setting id to `setting_ids`, the `Ring` group's first.
-- tab: settings settings cache by setting id
-- tab: setting_ids list of cached setting ids
RingSettings.add_settings = function (settings, setting_ids)
    for group = 1, 2 do
        local ids = group == 1 and RING_IDS or APPEARANCE_IDS

        for i = 1, #ids do
            _add_setting(settings, setting_ids, ids[i])
        end
    end
end

return RingSettings
