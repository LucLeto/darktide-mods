--- Optional rows in the game's own Session Stats panel on the end-of-round screen.
-- Darktide 1.13 added a collapsible Session Stats panel to the end-of-round screen. Its rows come
-- from `SessionStatsDisplay`, whose values the server sends by row index, so the list itself is
-- not extended. Instead, after the panel has built its own rows, up to three Overflow Meter rows
-- are appended with the panel's own row template. The padding rows (the last one holds the
-- collapse prompt) move down below them, and the panel's height grows to match. A fourth row
-- would overlap the Continue button, so there are three slots.
--
-- The player picks the metric of each slot (`session_stats_row_1` to `_3`) and can turn the
-- feature off (`session_stats_rows`). Slots set to Off are skipped without a gap, and a metric
-- already shown is not repeated. Values are the local player's totals, marked `~` when estimated;
-- the team column stays empty because only players running the mod have these values. Nothing is
-- added unless something was generated this mission, the same rule as the chat line.
--
-- Explicit module loaded by `OverflowMeter.lua`. The panel class is only loaded with the end-of-
-- round screen, so it is hooked by name; DMF applies the hook before the panel's first `init`.
-- Every precondition is checked before the panel is changed, so a game patch that renames its
-- internals leaves the panel as it is.
-- module: OverflowMeter_session_stats
-- alias: SessionStats
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local Stats = mod._stats

local math_floor = math.floor
local pcall = pcall
local require = require
local string_format = string.format
local type = type

--- Game files that define the panel's row template and its layout settings.
local DEFINITIONS_PATH = "scripts/ui/view_elements/view_element_session_stats/view_element_session_stats_definitions"
local SETTINGS_PATH = "scripts/ui/view_elements/view_element_session_stats/view_element_session_stats_settings"

--- Widget names of the game's rows, of its padding rows and of ours.
local GAME_ROW_PREFIX = "session_stat_row_"
local PADDING_ROW_PREFIX = "session_stat_padding_"
local ROW_PREFIX = "overflow_meter_session_stat_"

--- Setting ids of the row slots, in display order.
local SLOT_SETTING_IDS = {
    "session_stats_row_1",
    "session_stats_row_2",
    "session_stats_row_3"
}

local RATE_MODE_PER_ALLY = "per_ally"
local ESTIMATE_PREFIX = "~"

--- The metrics a slot can show, by setting value.
-- Each has its label key, whether it is an estimate, an optional suffix and a function returning
-- the current total. Shared follows the `Rate display` setting like the chat line.
local METRICS = {
    generated = {
        loc = "session_stats_metric_generated",
        estimated = true,
        value = function ()
            return Stats.generated
        end
    },
    replenished = {
        loc = "session_stats_metric_replenished",
        estimated = false,
        value = function ()
            return Stats.replenished
        end
    },
    overflowed = {
        loc = "session_stats_metric_overflowed",
        estimated = true,
        value = function ()
            return Stats.overflowed
        end
    },
    shared = {
        loc = "session_stats_metric_shared",
        estimated = true,
        value = function ()
            return mod._settings.rate_mode ~= RATE_MODE_PER_ALLY and Stats.shared_total or Stats.shared
        end
    },
    efficiency = {
        loc = "session_stats_metric_efficiency",
        estimated = true,
        suffix = "%",
        value = function ()
            return Stats.efficiency() * 100
        end
    }
}

local SessionStats = {}

--- Metrics chosen for the current panel, reused between end-of-round screens.
local chosen = {}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

--- Fills `chosen` with the metrics of the slots in order, skipping Off and repeated metrics.
-- tab: settings cached settings
-- treturn: int number of chosen metrics
local function _choose_metrics(settings)
    local count = 0

    for i = 1, #SLOT_SETTING_IDS do
        local metric = METRICS[settings[SLOT_SETTING_IDS[i]]]
        local repeated = false

        for j = 1, count do
            if chosen[j] == metric then
                repeated = true
            end
        end

        if metric and not repeated then
            count = count + 1
            chosen[count] = metric
        end
    end

    for i = count + 1, #chosen do
        chosen[i] = nil
    end

    return count
end

--- Formats a metric's current total, rounded like the chat line.
-- tab: metric entry of `METRICS`
-- treturn: string
local function _format_value(metric)
    local prefix = metric.estimated and ESTIMATE_PREFIX or ""

    return string_format("%s%d%s", prefix, math_floor(metric.value() + 0.5), metric.suffix or "")
end

--- Loads one of the panel's game files.
-- string: path require path
-- treturn: ?tab module, or nil when it cannot be loaded
local function _require_table(path)
    local ok, result = pcall(require, path)

    if ok and type(result) == "table" then
        return result
    end

    return nil
end

-- ----------------------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------------------

--- Appends the chosen Overflow Meter rows to a Session Stats panel that has built its own rows.
-- Does nothing while the feature is off, every slot is Off or nothing was generated, and leaves
-- the panel untouched when any of its internals is missing.
-- tab: element the `ViewElementSessionStats` instance
SessionStats.append_rows = function (element)
    local settings = mod._settings

    if not mod:is_enabled() or not settings.session_stats_rows or Stats.generated <= 0 then
        return
    end

    local count = _choose_metrics(settings)

    if count == 0 then
        return
    end

    local Definitions = _require_table(DEFINITIONS_PATH)
    local PanelSettings = _require_table(SETTINGS_PATH)
    local row_definition = Definitions and Definitions.row_definition
    local definition_style = row_definition and row_definition.style
    local definition_shade = definition_style and definition_style.shade
    local shade_alpha = Definitions and Definitions.row_shade_alpha
    local row_height = PanelSettings and PanelSettings.row_height
    local title_height = PanelSettings and PanelSettings.title_height
    local num_padding_rows = PanelSettings and PanelSettings.num_padding_rows
    local widgets_by_name = element._widgets_by_name
    local widgets = element._widgets
    local full_height = element._full_height

    if not definition_shade or not definition_shade.default_color or type(shade_alpha) ~= "number" or type(row_height) ~= "number" or type(title_height) ~= "number" or type(num_padding_rows) ~= "number" or type(widgets_by_name) ~= "table" or type(widgets) ~= "table" or type(full_height) ~= "number" or type(element._create_widget) ~= "function" then
        mod:info("The Session Stats panel has changed; no Overflow Meter rows were added.")

        return
    end

    local num_game_rows = 0

    while widgets_by_name[GAME_ROW_PREFIX .. (num_game_rows + 1)] do
        num_game_rows = num_game_rows + 1
    end

    local first_row = widgets_by_name[GAME_ROW_PREFIX .. 1]
    local first_shade = first_row and first_row.style and first_row.style.shade
    local base_alpha = first_shade and first_shade.default_color and first_shade.default_color[1]

    if type(base_alpha) ~= "number" then
        mod:info("The Session Stats panel has no rows to follow; no Overflow Meter rows were added.")

        return
    end

    for k = 1, num_padding_rows do
        local padding = widgets_by_name[PADDING_ROW_PREFIX .. k]
        local shade = padding and padding.style and padding.style.shade

        if not padding or not padding.offset or not padding.content or type(padding.content.reveal_bottom) ~= "number" or not shade or not shade.color or not shade.default_color then
            mod:info("The Session Stats panel's padding rows have changed; no Overflow Meter rows were added.")

            return
        end
    end

    local rows_y = title_height + row_height
    local added_height = count * row_height

    for j = 1, count do
        local metric = chosen[j]
        local row_index = num_game_rows + j
        local widget = element:_create_widget(ROW_PREFIX .. j, row_definition)
        local content = widget.content

        widget.offset[2] = (row_index - 1) * row_height
        content.label = mod:localize(metric.loc)
        content.own = _format_value(metric)
        content.team = ""
        content.reveal_bottom = rows_y + row_index * row_height

        if row_index % 2 == 0 then
            widget.style.shade.default_color[1] = shade_alpha
        end

        widgets[#widgets + 1] = widget
    end

    -- The padding rows continue the row shading, so their parity follows the new row count.
    local padding_alpha = (num_game_rows + count + 1) % 2 == 0 and shade_alpha or base_alpha

    for k = 1, num_padding_rows do
        local padding = widgets_by_name[PADDING_ROW_PREFIX .. k]
        local shade = padding.style.shade

        padding.offset[2] = padding.offset[2] + added_height
        padding.content.reveal_bottom = padding.content.reveal_bottom + added_height
        shade.color[1] = padding_alpha
        shade.default_color[1] = padding_alpha
    end

    element._full_height = full_height + added_height
end

-- The panel has built its own rows; `init` applies the height right after this returns.
mod:hook_safe("ViewElementSessionStats", "_populate_rows", function (self)
    SessionStats.append_rows(self)
end)

return SessionStats
