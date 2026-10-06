local mod = get_mod("OverflowMeter")
local Snapshot = mod._snapshot

local Managers = Managers
local get_mod = get_mod
local pairs = pairs
local pcall = pcall
local tostring = tostring
local type = type

local POWER_DI_MOD_NAME = "Power_DI"

local DATASOURCE_NAME = "OverflowMeter_Summary"
local DATASET_NAME = "Overflow Meter mission summary"
local REPORT_NAME = "Overflow Meter"

local Adapter = {
    name = POWER_DI_MOD_NAME,
    active = false
}

local registered = false
local datasource_getter = nil
local session_rows = nil
local session_table = nil
local row_index = {}

local function _dataset_function(data)
    data:append_dataset("OverflowMeter_Summary"):next(function ()
        data:complete_dataset()
    end)
end

local function _resolve_identity(entry)
    local player_manager = Managers.player
    local players = player_manager and player_manager.players and player_manager:players()

    if not players then
        return
    end

    local account_id = entry.account_id

    for _, player in pairs(players) do
        if player.account_id and player:account_id() == account_id then
            if player.name then
                entry.player_name = player:name()
            end

            local profile = player.profile and player:profile()

            entry.character_id = profile and profile.character_id

            return
        end
    end
end

local function _register(pdi)
    local ok, getter = pcall(pdi.datasources.register_datasource, {
        name = DATASOURCE_NAME,
        hook_templates = {}
    })

    if not ok or not getter then
        mod:info("Power_DI datasource registration failed: %s", tostring(getter))

        return false
    end

    datasource_getter = getter

    local dataset_ok, dataset_error = pcall(pdi.datasets.register_dataset, {
        name = DATASET_NAME,
        required_datasources = {
            DATASOURCE_NAME
        },
        dataset_function = _dataset_function,
        legend = {
            player = "player",
            player_name = "string",
            archetype = "string",
            source = "string",
            generated = "number",
            replenished = "number",
            overflowed = "number",
            shared_per_ally = "number",
            shared_all_allies = "number",
            efficiency = "number"
        }
    })

    if not dataset_ok then
        mod:info("Power_DI dataset registration failed: %s", tostring(dataset_error))

        return false
    end

    local report_ok, report_error = pcall(pdi.reports.register_report, {
        name = REPORT_NAME,
        dataset_name = DATASET_NAME,
        report_type = "pivot_table",
        columns = {
            "player"
        },
        rows = {
            "archetype"
        },
        values = {
            { field_name = "generated", type = "sum", label = "Generated (~)", visible = true, format = "number" },
            { field_name = "replenished", type = "sum", label = "Replenished", visible = true, format = "number" },
            { field_name = "overflowed", type = "sum", label = "Overflowed (~)", visible = true, format = "number" },
            { field_name = "shared_per_ally", type = "sum", label = "Shared per ally (~)", visible = true, format = "number" },
            { field_name = "shared_all_allies", type = "sum", label = "Shared, all allies (~)", visible = true, format = "number" },
            { field_name = "efficiency", type = "sum", label = "Efficiency % (~)", visible = true, format = "number" }
        },
        filters = {}
    })

    if not report_ok then
        mod:info("Power_DI report registration failed: %s", tostring(report_error))
    end

    return true
end

Adapter.setup = function ()
    if registered then
        Adapter.active = datasource_getter ~= nil

        return
    end

    local pdi = get_mod(POWER_DI_MOD_NAME)

    if not pdi or not pdi.datasources or not pdi.datasets or not pdi.reports then
        Adapter.active = false

        return
    end

    registered = true

    Adapter.active = _register(pdi)
end

Adapter.prepare = function ()
    session_rows = nil

    local getter = datasource_getter

    if not getter then
        return
    end

    local ok, rows = pcall(getter)

    if not ok or type(rows) ~= "table" then
        return
    end

    if rows ~= session_table then
        session_table = rows

        for account_id in pairs(row_index) do
            row_index[account_id] = nil
        end
    end

    session_rows = rows
end

Adapter.publish = function (entry)
    local rows = session_rows

    if not rows or not entry.archetype then
        return
    end

    local account_id = entry.account_id
    local index = row_index[account_id]
    local row = index and rows[index]

    if not row then
        index = #rows + 1
        row = {}
        rows[index] = row
        row_index[account_id] = index
    end

    if not entry.character_id then
        _resolve_identity(entry)
    end

    row.player = entry.character_id or account_id
    row.player_name = entry.player_name or account_id
    row.archetype = entry.archetype or "unknown"
    row.source = entry.remote and "remote" or "local"
    row.generated = entry.generated
    row.replenished = entry.replenished
    row.overflowed = entry.overflowed
    row.shared_per_ally = entry.shared
    row.shared_all_allies = entry.shared_total
    row.efficiency = entry.efficiency
end

Adapter.reset = function ()
    session_rows = nil
    session_table = nil

    for account_id in pairs(row_index) do
        row_index[account_id] = nil
    end
end

Snapshot.register_adapter(Adapter)

return Adapter
