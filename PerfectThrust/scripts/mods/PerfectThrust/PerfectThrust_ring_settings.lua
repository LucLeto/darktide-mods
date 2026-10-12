--- Shared definitions of Perfect Thrust's ring settings; one set for each ring.
-- The melee charge ring and the aiming ring each have their own display mode, size, thickness,
-- offsets, READY pulse and colours. The melee ring's settings use the plain setting ids, the
-- aiming ring's the same ids with `ADS_PREFIX`; the aiming ring has no heavy attack available
-- colour, as it never shows that state. This module is the single source of their DMF widget
-- definitions and defaults: `PerfectThrust_data.lua` builds both settings groups from it,
-- `PerfectThrust.lua` the settings cache, and the HUD element looks up the setting ids of the ring
-- it shows. The aiming ring reuses the melee ring's titles and tooltips, except for the few texts
-- in `AIM_TEXT_IDS` that have their own `ads_` localization.
--
-- DMF loads the data file before the mod script, so both load this module through
-- `mod:io_dofile`; `PerfectThrust.lua` stores it as `mod._ring_settings` for the HUD element.
-- module: PerfectThrust_ring_settings
-- author: LucLeto
local pairs = pairs
local type = type

--- The ring settings module table.
local RingSettings = {}

--- Prefix of the aiming ring's setting ids; the melee ring's have none.
local ADS_PREFIX = "ads_"

RingSettings.ADS_PREFIX = ADS_PREFIX

--- The ring settings after the display mode, in menu order.
local APPEARANCE_IDS = {
    "ring_radius",
    "ring_thickness",
    "offset_x",
    "offset_y",
    "ready_pulse",
    "unfilled_color",
    "charging_color",
    "heavy_available_color",
    "ready_color",
    "ready_pulse_color"
}

RingSettings.APPEARANCE_IDS = APPEARANCE_IDS

--- Every ring setting by its melee id: the display mode, then `APPEARANCE_IDS`.
local SETTING_IDS = { "display_mode" }

for i = 1, #APPEARANCE_IDS do
    SETTING_IDS[i + 1] = APPEARANCE_IDS[i]
end

--- Ring settings only the melee ring has.
local WINDUP_ONLY = {
    heavy_available_color = true
}

--- Localization ids the aiming ring has its own `ads_` text for; its other titles and tooltips
-- are the melee ring's.
local AIM_TEXT_IDS = {
    charging_color = true,
    charging_color_tooltip = true,
    unfilled_color_tooltip = true,
    ready_pulse_tooltip = true
}

--- DMF widget definitions of the ring settings, by melee id, without `setting_id`, `title` and
-- `tooltip`. Colours are DMF colour pickers with alpha, stored as `{ a, r, g, b }`.
local DEFINITIONS = {
    display_mode = {
        type = "dropdown",
        default_value = "progress",
        options = {
            { text = "display_mode_progress", value = "progress" },
            { text = "display_mode_ready_only", value = "ready_only" }
        }
    },
    ring_radius = {
        type = "numeric",
        default_value = 32,
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
    ready_pulse = {
        type = "checkbox",
        default_value = true
    },
    unfilled_color = {
        type = "color",
        default_value = { 80, 70, 82, 86 },
        has_alpha = true
    },
    charging_color = {
        type = "color",
        default_value = { 235, 240, 190, 90 },
        has_alpha = true
    },
    heavy_available_color = {
        type = "color",
        default_value = { 229, 233, 255, 90 },
        has_alpha = true
    },
    ready_color = {
        type = "color",
        default_value = { 255, 120, 225, 140 },
        has_alpha = true
    },
    ready_pulse_color = {
        type = "color",
        -- The READY colour.
        default_value = { 255, 120, 225, 140 },
        has_alpha = true
    }
}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

--- Returns a deep copy of a value; other values than tables are returned as they are.
-- DMF localizes dropdown option texts in place and stores default values, so no two widgets may
-- share a table.
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

--- Returns whether a ring has a setting.
-- string: prefix `""` for the melee ring or `ADS_PREFIX` for the aiming ring
-- string: id melee setting id
-- treturn: bool
local function _has_setting(prefix, id)
    return prefix == "" or not WINDUP_ONLY[id]
end

--- Returns the localization id of a ring setting's title or tooltip.
-- string: prefix ring prefix
-- string: text_id the melee ring's localization id
-- treturn: string the ring's own localization id, or the melee ring's
local function _text_id(prefix, text_id)
    if prefix ~= "" and AIM_TEXT_IDS[text_id] then
        return prefix .. text_id
    end

    return text_id
end

-- ----------------------------------------------------------------------------
-- Settings menu
-- ----------------------------------------------------------------------------

--- Returns the DMF widget of one ring setting, as a new table.
-- The melee ring's widget is titled by its setting id, as before; the aiming ring's names its
-- title explicitly.
-- string: prefix `""` for the melee ring or `ADS_PREFIX` for the aiming ring
-- string: id melee setting id
-- treturn: tab DMF widget definition
RingSettings.widget = function (prefix, id)
    local widget = _copy(DEFINITIONS[id])

    widget.setting_id = prefix .. id
    widget.tooltip = _text_id(prefix, id .. "_tooltip")

    if prefix ~= "" then
        widget.title = _text_id(prefix, id)
    end

    return widget
end

--- Appends a ring's widgets for the given setting ids, skipping settings the ring does not have.
-- tab: sub_widgets DMF widget list to append to
-- string: prefix `""` for the melee ring or `ADS_PREFIX` for the aiming ring
-- tab: ids melee setting ids in menu order
RingSettings.append_widgets = function (sub_widgets, prefix, ids)
    for i = 1, #ids do
        local id = ids[i]

        if _has_setting(prefix, id) then
            sub_widgets[#sub_widgets + 1] = RingSettings.widget(prefix, id)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Runtime
-- ----------------------------------------------------------------------------

--- Returns the default value of a ring setting. Colour tables are shared and must not be written.
-- string: id melee setting id
-- treturn: param default value
RingSettings.default_value = function (id)
    return DEFINITIONS[id].default_value
end

--- Adds both rings' settings to a settings cache: each default to `settings` by setting id, and
-- each setting id to `setting_ids`, the melee ring's first.
-- tab: settings settings cache by setting id
-- tab: setting_ids list of cached setting ids
RingSettings.add_settings = function (settings, setting_ids)
    for ring = 1, 2 do
        local prefix = ring == 1 and "" or ADS_PREFIX

        for i = 1, #SETTING_IDS do
            local id = SETTING_IDS[i]

            if _has_setting(prefix, id) then
                local setting_id = prefix .. id

                settings[setting_id] = DEFINITIONS[id].default_value
                setting_ids[#setting_ids + 1] = setting_id
            end
        end
    end
end

--- Returns the setting id one ring reads for each ring setting, by melee id. A setting the ring
-- does not have maps to the melee ring's, so every lookup finds a value.
-- string: prefix `""` for the melee ring or `ADS_PREFIX` for the aiming ring
-- treturn: tab setting ids by melee id
RingSettings.keys = function (prefix)
    local keys = {}

    for i = 1, #SETTING_IDS do
        local id = SETTING_IDS[i]

        keys[id] = _has_setting(prefix, id) and prefix .. id or id
    end

    return keys
end

return RingSettings
