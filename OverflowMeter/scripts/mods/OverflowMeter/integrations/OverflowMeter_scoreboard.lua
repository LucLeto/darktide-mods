--- Optional integration with the Scoreboard mod.
-- The rows are declared in `mod.scoreboard_rows` (`OverflowMeter.lua`), which the Scoreboard
-- collects from every mod; this adapter fills them with each player's totals through
-- `update_stat`. Efficiency is a percentage, so its value is written straight into the row data
-- instead of going through the row's accumulation. With the Ovenproof scoreboard plugin enabled,
-- the rows are moved directly above its `blank_3` spacer row and into that row's group, so they
-- sit with the plugin's defense rows.
--
-- Explicit module loaded by `OverflowMeter.lua`; it registers itself with the snapshot. It stays
-- active and does nothing while the Scoreboard is missing or disabled or every row is turned off.
-- module: OverflowMeter_scoreboard
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local Snapshot = mod._snapshot

local get_mod = get_mod
local table_insert = table.insert
local table_remove = table.remove

local SCOREBOARD_MOD_NAME = "scoreboard"

--- The Ovenproof plugin and the spacer row our rows are placed above.
local OVENPROOF_MOD_NAME = "ovenproof_scoreboard_plugin"
local OVENPROOF_ANCHOR_ROW = "blank_3"

local METRICS = Snapshot.METRICS
local METRIC_COUNT = Snapshot.METRIC_COUNT

--- Per-metric row names, entry fields, and whether the value replaces the row data.
local SCOREBOARD_ROW_NAMES = {}
local FIELDS = {}

local REPLACES_VALUE = {}

for i = 1, METRIC_COUNT do
    local metric = METRICS[i]

    SCOREBOARD_ROW_NAMES[i] = metric.row
    FIELDS[i] = metric.field
    REPLACES_VALUE[i] = metric.id == "efficiency"
end

--- The snapshot adapter.
local Adapter = {
    name = SCOREBOARD_MOD_NAME,
    active = true
}

--- The Scoreboard mod while it can receive values, set by `prepare`.
local target = nil

--- Writes a value straight into a row's data, replacing it instead of accumulating it.
-- tab: scoreboard Scoreboard mod
-- string: row_name row name
-- string: account_id player's account id
-- number: value value to show
local function _replace_scoreboard_stat(scoreboard, row_name, account_id, value)
    local row = scoreboard.get_scoreboard_row and scoreboard:get_scoreboard_row(row_name)

    if not row then
        return
    end

    local row_data = row.data

    if not row_data then
        row_data = {}
        row.data = row_data
    end

    local entry = row_data[account_id]

    if not entry then
        entry = {}
        row_data[account_id] = entry
    end

    entry.value = value
    entry.score = value
    entry.text = nil
end

--- Returns the index of a row by name.
-- tab: rows row list
-- string: name row name
-- treturn: ?int
local function _scoreboard_row_index(rows, name)
    for i = 1, #rows do
        if rows[i].name == name then
            return i
        end
    end
end

--- Moves our rows directly above the Ovenproof plugin's spacer row, in the spacer's group.
-- Does nothing without the plugin or when the rows are already in place.
-- tab: scoreboard Scoreboard mod
local function _arrange_scoreboard_rows(scoreboard)
    local rows = scoreboard.registered_scoreboard_rows

    if not rows then
        return
    end

    local ovenproof = get_mod(OVENPROOF_MOD_NAME)

    if not ovenproof or not ovenproof.is_enabled or not ovenproof:is_enabled() then
        return
    end

    local anchor_index = _scoreboard_row_index(rows, OVENPROOF_ANCHOR_ROW)

    if not anchor_index then
        return
    end

    local count = #SCOREBOARD_ROW_NAMES
    local first_index = _scoreboard_row_index(rows, SCOREBOARD_ROW_NAMES[1])

    if not first_index or anchor_index - first_index == count then
        return
    end

    local group = rows[anchor_index].group
    local moved = {}

    for i = 1, count do
        local index = _scoreboard_row_index(rows, SCOREBOARD_ROW_NAMES[i])

        if index then
            local entry = table_remove(rows, index)

            entry.group = group
            moved[#moved + 1] = entry
        end
    end

    anchor_index = _scoreboard_row_index(rows, OVENPROOF_ANCHOR_ROW)

    for i = #moved, 1, -1 do
        table_insert(rows, anchor_index, moved[i])
    end
end

--- Returns whether any scoreboard row is turned on.
-- tab: settings cached settings
-- treturn: bool
local function _any_row_wanted(settings)
    for i = 1, METRIC_COUNT do
        if settings[METRICS[i].setting] then
            return true
        end
    end

    return false
end

--- Finds the enabled Scoreboard mod and arranges our rows before a publish.
Adapter.prepare = function ()
    target = nil

    if not _any_row_wanted(mod._settings) then
        return
    end

    local scoreboard = get_mod(SCOREBOARD_MOD_NAME)

    if not scoreboard or not scoreboard.update_stat or not scoreboard.is_enabled or not scoreboard:is_enabled() then
        return
    end

    _arrange_scoreboard_rows(scoreboard)

    target = scoreboard
end

--- Writes an entry's enabled metrics into the Scoreboard rows.
-- tab: entry snapshot entry
Adapter.publish = function (entry)
    local scoreboard = target

    if not scoreboard then
        return
    end

    local settings = mod._settings
    local account_id = entry.account_id

    for i = 1, METRIC_COUNT do
        local metric = METRICS[i]

        if settings[metric.setting] then
            local value = entry[FIELDS[i]]

            if REPLACES_VALUE[i] then
                _replace_scoreboard_stat(scoreboard, metric.row, account_id, value)
            else
                scoreboard:update_stat(metric.row, account_id, value)
            end
        end
    end
end

--- Forgets the Scoreboard mod until the next publish.
Adapter.reset = function ()
    target = nil
end

Snapshot.register_adapter(Adapter)

return Adapter
