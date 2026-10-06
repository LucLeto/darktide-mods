local mod = get_mod("OverflowMeter")
local Stats = mod._stats

local math_floor = math.floor
local pairs = pairs
local tonumber = tonumber
local type = type

local MAX_STAT = 1000000000

local RATE_MODE_PER_ALLY = "per_ally"

local Snapshot = {}

Snapshot.SCHEMA_VERSION = 1

Snapshot.METRICS = {
    {
        id = "generated",
        field = "generated",
        row = "overflow_meter_generated",
        loc = "scoreboard_generated",
        setting = "scoreboard_row_generated",
        observed = false
    },
    {
        id = "replenished",
        field = "replenished",
        row = "overflow_meter_replenished",
        loc = "scoreboard_replenished",
        setting = "scoreboard_row_replenished",
        observed = true
    },
    {
        id = "overflowed",
        field = "overflowed",
        row = "overflow_meter_overflowed",
        loc = "scoreboard_overflowed",
        setting = "scoreboard_row_overflowed",
        observed = false
    },
    {
        id = "shared",
        field = "shared_display",
        row = "overflow_meter_shared",
        loc = "scoreboard_shared",
        setting = "scoreboard_row_shared",
        observed = false
    },
    {
        id = "efficiency",
        field = "efficiency",
        row = "overflow_meter_efficiency",
        loc = "scoreboard_efficiency",
        loc_short = "scoreboard_efficiency_short",
        setting = "scoreboard_row_efficiency",
        observed = false
    }
}

local METRICS = Snapshot.METRICS
local METRIC_COUNT = #METRICS

Snapshot.METRIC_COUNT = METRIC_COUNT

Snapshot.entries = {}
Snapshot.order = {}
Snapshot.version = 0

local entries = Snapshot.entries
local order = Snapshot.order

local adapters = {}
local adapter_count = 0

local dirty_count = 0
local local_account_id = nil

local function _stat(value)
    value = tonumber(value)

    if not value or not (value >= 0) then
        return 0
    end

    if value > MAX_STAT then
        return MAX_STAT
    end

    return math_floor(value)
end

local function _percent(value)
    value = tonumber(value)

    if not value or not (value >= 0) then
        return 0
    end

    if value > 100 then
        return 100
    end

    return math_floor(value)
end

Snapshot.stat = _stat
Snapshot.percent = _percent

local function _mark_dirty(entry)
    if not entry.dirty then
        entry.dirty = true
        dirty_count = dirty_count + 1
    end

    Snapshot.version = Snapshot.version + 1
end

local function _entry(account_id)
    local entry = entries[account_id]

    if entry then
        return entry
    end

    entry = {
        schema = Snapshot.SCHEMA_VERSION,
        account_id = account_id,
        archetype = nil,
        player_name = nil,
        character_id = nil,
        generated = 0,
        replenished = 0,
        overflowed = 0,
        shared = 0,
        shared_total = 0,
        shared_display = 0,
        efficiency = 0,
        remote = false,
        dirty = false
    }

    entries[account_id] = entry
    order[#order + 1] = entry

    return entry
end

Snapshot.get = function (account_id)
    return entries[account_id]
end

Snapshot.is_observed = function (entry, metric)
    return metric.observed and not entry.remote
end

Snapshot.update_local = function (account_id, archetype)
    if not account_id then
        return nil
    end

    local_account_id = account_id

    local entry = _entry(account_id)
    local shared = math_floor(Stats.shared + 0.5)
    local shared_total = math_floor(Stats.shared_total + 0.5)

    entry.archetype = archetype or Stats.archetype
    entry.remote = false
    entry.generated = math_floor(Stats.generated + 0.5)
    entry.replenished = math_floor(Stats.replenished + 0.5)
    entry.overflowed = math_floor(Stats.overflowed + 0.5)
    entry.shared = shared
    entry.shared_total = shared_total
    entry.shared_display = mod._settings.rate_mode ~= RATE_MODE_PER_ALLY and shared_total or shared
    entry.efficiency = math_floor(Stats.efficiency() * 100 + 0.5)

    _mark_dirty(entry)

    return entry
end

Snapshot.update_peer = function (account_id, peer)
    if not account_id or type(peer) ~= "table" then
        return nil
    end

    local entry = _entry(account_id)
    local shared = _stat(peer.s)
    local shared_total = _stat(peer.st)

    entry.archetype = type(peer.a) == "string" and peer.a or nil
    entry.remote = true
    entry.generated = _stat(peer.g)
    entry.replenished = _stat(peer.r)
    entry.overflowed = _stat(peer.o)
    entry.shared = shared
    entry.shared_total = shared_total
    entry.shared_display = mod._settings.rate_mode ~= RATE_MODE_PER_ALLY and shared_total or shared
    entry.efficiency = _percent(peer.e)

    _mark_dirty(entry)

    return entry
end

Snapshot.refresh_values = function ()
    local rate_mode_total = mod._settings.rate_mode ~= RATE_MODE_PER_ALLY

    for i = 1, #order do
        local entry = order[i]
        local shared_display = rate_mode_total and entry.shared_total or entry.shared

        if shared_display ~= entry.shared_display then
            entry.shared_display = shared_display

            _mark_dirty(entry)
        end
    end
end

Snapshot.register_adapter = function (adapter)
    for i = 1, adapter_count do
        if adapters[i].name == adapter.name then
            return
        end
    end

    adapter_count = adapter_count + 1
    adapters[adapter_count] = adapter
end

Snapshot.publish = function (force)
    if adapter_count == 0 or (not force and dirty_count == 0) then
        return
    end

    for i = 1, adapter_count do
        local adapter = adapters[i]

        if adapter.active and adapter.prepare then
            adapter.prepare()
        end
    end

    for i = 1, #order do
        local entry = order[i]

        if force or entry.dirty then
            for j = 1, adapter_count do
                local adapter = adapters[j]

                if adapter.active then
                    adapter.publish(entry)
                end
            end

            if entry.dirty then
                entry.dirty = false
                dirty_count = dirty_count - 1
            end
        end
    end
end

Snapshot.flush = function ()
    if local_account_id then
        Snapshot.update_local(local_account_id)
    end

    Snapshot.publish(true)
end

Snapshot.setup = function ()
    for i = 1, adapter_count do
        local adapter = adapters[i]

        if adapter.setup then
            adapter.setup()
        end
    end
end

Snapshot.reset = function ()
    for account_id in pairs(entries) do
        entries[account_id] = nil
    end

    for i = #order, 1, -1 do
        order[i] = nil
    end

    dirty_count = 0
    local_account_id = nil
    Snapshot.version = Snapshot.version + 1

    for i = 1, adapter_count do
        local adapter = adapters[i]

        if adapter.reset then
            adapter.reset()
        end
    end
end

Snapshot.refresh = function ()
    for i = 1, adapter_count do
        local adapter = adapters[i]

        if adapter.refresh then
            adapter.refresh()
        end
    end

    Snapshot.refresh_values()

    Snapshot.publish(true)
end

Snapshot.teardown = function ()
    for i = 1, adapter_count do
        local adapter = adapters[i]

        if adapter.teardown then
            adapter.teardown()
        end
    end
end

return Snapshot
