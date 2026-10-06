local mod = get_mod("OverflowMeter")
local Snapshot = mod._snapshot

local get_mod = get_mod
local table_insert = table.insert
local table_remove = table.remove

local SCOREBOARD_MOD_NAME = "scoreboard"

local OVENPROOF_MOD_NAME = "ovenproof_scoreboard_plugin"
local OVENPROOF_ANCHOR_ROW = "blank_3"

local METRICS = Snapshot.METRICS
local METRIC_COUNT = Snapshot.METRIC_COUNT

local SCOREBOARD_ROW_NAMES = {}
local FIELDS = {}

local REPLACES_VALUE = {}

for i = 1, METRIC_COUNT do
    local metric = METRICS[i]

    SCOREBOARD_ROW_NAMES[i] = metric.row
    FIELDS[i] = metric.field
    REPLACES_VALUE[i] = metric.id == "efficiency"
end

local Adapter = {
    name = SCOREBOARD_MOD_NAME,
    active = true
}

local target = nil

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

local function _scoreboard_row_index(rows, name)
    for i = 1, #rows do
        if rows[i].name == name then
            return i
        end
    end
end

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

local function _any_row_wanted(settings)
    for i = 1, METRIC_COUNT do
        if settings[METRICS[i].setting] then
            return true
        end
    end

    return false
end

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

Adapter.reset = function ()
    target = nil
end

Snapshot.register_adapter(Adapter)

return Adapter
