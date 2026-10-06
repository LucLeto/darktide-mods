local mod = get_mod("OverflowMeter")
local Snapshot = mod._snapshot

local get_mod = get_mod
local math_max = math.max
local pairs = pairs
local table_insert = table.insert
local table_remove = table.remove

local VT2_MOD_NAME = "vt2_scoreboard"

local METRICS = Snapshot.METRICS
local METRIC_COUNT = Snapshot.METRIC_COUNT

local FIELDS = {}

local OUR_ROW_ORDER = {}

for i = 1, METRIC_COUNT do
    FIELDS[i] = METRICS[i].field
    OUR_ROW_ORDER[METRICS[i].row] = i
end

local Adapter = {
    name = VT2_MOD_NAME,
    active = false
}

local ITERATION_DIFF = {
    value = function (new_value, old_value)
        return new_value, math_max(new_value - old_value, 0)
    end
}

local labels = {}

local row_data = {}
local rows_cache = {}

local vt2_mod = nil
local hooks_installed = false
local ready = false

local function _row_index(rows, name)
    for i = 1, #rows do
        if rows[i].name == name then
            return i
        end
    end
end

local function _insert_position(rows, metric_position)
    local after = #rows

    for i = 1, #rows do
        local position = OUR_ROW_ORDER[rows[i].name]

        if position and position < metric_position then
            after = i
        end
    end

    return after + 1
end

local function _sync_rows(vt2)
    local rows = vt2.registered_rows

    if not rows then
        return
    end

    local settings = mod._settings
    local validation_types = vt2.validation_types
    local validation = validation_types and validation_types.ASC

    for i = 1, METRIC_COUNT do
        local metric = METRICS[i]
        local row_name = metric.row
        local index = _row_index(rows, row_name)

        if settings[metric.setting] then
            if not index then
                table_insert(rows, _insert_position(rows, i), {
                    name = row_name,
                    text = labels[i],
                    iteration = ITERATION_DIFF,
                    validation = validation,
                    validation_type = "ASC",
                    data = row_data[row_name]
                })
            end
        elseif index then
            table_remove(rows, index)
        end
    end
end

Adapter.setup = function ()
    local vt2 = get_mod(VT2_MOD_NAME)

    if not vt2 or not vt2.registered_rows or not vt2.get_row or not vt2.validation_types then
        vt2_mod = nil
        Adapter.active = false

        return
    end

    for i = 1, METRIC_COUNT do
        local metric = METRICS[i]

        labels[i] = mod:localize(metric.loc)
        row_data[metric.row] = row_data[metric.row] or {}
    end

    vt2_mod = vt2
    Adapter.active = true

    _sync_rows(vt2)

    if hooks_installed then
        return
    end

    hooks_installed = true

    mod:hook_safe(vt2, "collect_rows", function (self)
        _sync_rows(self)
    end)

    if vt2.show_vt2_scoreboard_view then
        mod:hook(vt2, "show_vt2_scoreboard_view", function (func, ...)
            Snapshot.flush()

            return func(...)
        end)
    end
end

Adapter.refresh = function ()
    local vt2 = vt2_mod

    if not vt2 then
        return
    end

    _sync_rows(vt2)
end

Adapter.prepare = function ()
    ready = false

    local vt2 = vt2_mod

    if not vt2 or not vt2.is_enabled or not vt2:is_enabled() then
        return
    end

    local settings = mod._settings
    local any = false

    for i = 1, METRIC_COUNT do
        local row = settings[METRICS[i].setting] and vt2:get_row(METRICS[i].row) or nil

        rows_cache[i] = row
        any = any or row ~= nil
    end

    ready = any
end

Adapter.publish = function (entry)
    if not ready then
        return
    end

    local account_id = entry.account_id

    for i = 1, METRIC_COUNT do
        local row = rows_cache[i]

        if row then
            local data = row.data

            if not data then
                data = {}
                row.data = data
            end

            local cell = data[account_id]

            if not cell then
                cell = {}
                data[account_id] = cell
            end

            local value = entry[FIELDS[i]]

            cell.value = value
            cell.score = value
        end
    end
end

Adapter.reset = function ()
    ready = false

    for i = 1, METRIC_COUNT do
        rows_cache[i] = nil
    end

    for _, data in pairs(row_data) do
        for account_id in pairs(data) do
            data[account_id] = nil
        end
    end
end

Snapshot.register_adapter(Adapter)

return Adapter
