--- The scoreboard snapshot: one entry of rounded totals per player, published to every adapter.
-- Holds the local player's totals (from `OverflowMeter_stats.lua`) and each teammate's shared
-- totals (from `OverflowMeter_share.lua`) as integer entries keyed by account id. Entries are
-- marked dirty when they change, and publishing hands the dirty ones to every active scoreboard
-- adapter. `METRICS` defines the five rows every adapter builds from.
--
-- An adapter is a table with a `name`, an `active` flag and `publish(entry)`, plus the optional
-- callbacks `setup` (all mods loaded), `prepare` (once before each publish), `reset` (new
-- mission or toggle), `refresh` (settings changed) and `teardown` (mod disabled or unloaded).
--
-- Explicit module loaded by `OverflowMeter.lua` and stored as `mod._snapshot`; each adapter in
-- `integrations/` registers itself when loaded. The HUD element updates the local entry once a
-- second while the totals change, sharing updates teammates' entries, and the end-of-round
-- screen flushes everything.
-- module: OverflowMeter_snapshot
-- alias: Snapshot
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local Stats = mod._stats

local math_floor = math.floor
local pairs = pairs
local tonumber = tonumber
local type = type

--- Upper bound for a published total.
local MAX_STAT = 1000000000

local RATE_MODE_PER_ALLY = "per_ally"

local Snapshot = {}

--- Version of the entry layout.
Snapshot.SCHEMA_VERSION = 1

--- The five scoreboard rows, in display order.
-- Each names its entry `field`, scoreboard `row`, label key `loc` (and `loc_short` where a
-- scoreboard needs a shorter label), the `setting` that enables it, and whether the value is
-- `observed` (read from the bar) rather than estimated. Shared reads `shared_display`, which
-- follows the `Rate display` setting.
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

--- Entries by account id, the same entries in insertion order, and a change counter.
Snapshot.entries = {}
Snapshot.order = {}
Snapshot.version = 0

local entries = Snapshot.entries
local order = Snapshot.order

--- Registered adapters, the number of dirty entries and the local player's account id.
local adapters = {}
local adapter_count = 0

local dirty_count = 0
local local_account_id = nil

-- ----------------------------------------------------------------------------
-- Entries
-- ----------------------------------------------------------------------------

--- Sanitises a total: a whole number from 0 to `MAX_STAT`, 0 for anything invalid.
-- param: value number or numeric string
-- treturn: int
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

--- Sanitises a percentage: a whole number from 0 to 100, 0 for anything invalid.
-- param: value number or numeric string
-- treturn: int
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

--- Marks an entry for the next publish and bumps the version.
-- tab: entry snapshot entry
local function _mark_dirty(entry)
    if not entry.dirty then
        entry.dirty = true
        dirty_count = dirty_count + 1
    end

    Snapshot.version = Snapshot.version + 1
end

--- Returns the entry for an account id, creating an empty one on first use.
-- string: account_id backend account id
-- treturn: tab entry
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

--- Returns the entry for an account id, if any.
-- string: account_id backend account id
-- treturn: ?tab entry
Snapshot.get = function (account_id)
    return entries[account_id]
end

--- Returns whether an entry's value for a metric was observed rather than estimated.
-- Only the local player's Replenished is observed; a teammate's values are always their estimate.
-- tab: entry snapshot entry
-- tab: metric entry of `METRICS`
-- treturn: bool
Snapshot.is_observed = function (entry, metric)
    return metric.observed and not entry.remote
end

--- Copies the local totals into the local player's entry, rounded to whole numbers.
-- ?string: account_id local player's account id; nothing happens without one
-- ?string: archetype archetype name, defaulting to the statistics' archetype
-- treturn: ?tab entry
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

--- Copies a teammate's decoded payload into their entry, sanitising every value.
-- ?string: account_id teammate's account id
-- ?tab: peer decoded payload from `OverflowMeter_share.lua`
-- treturn: ?tab entry
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

--- Recomputes every entry's displayed Shared value after the `Rate display` setting changed.
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

-- ----------------------------------------------------------------------------
-- Adapters
-- ----------------------------------------------------------------------------

--- Registers a scoreboard adapter, once per adapter name.
-- tab: adapter adapter table
Snapshot.register_adapter = function (adapter)
    for i = 1, adapter_count do
        if adapters[i].name == adapter.name then
            return
        end
    end

    adapter_count = adapter_count + 1
    adapters[adapter_count] = adapter
end

--- Publishes the dirty entries, or every entry when forced, to every active adapter.
-- ?bool: force publish every entry even if nothing changed
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

--- Refreshes the local entry from the current totals and publishes every entry.
-- Used whenever a scoreboard is about to show its values, so it never shows stale totals.
Snapshot.flush = function ()
    if local_account_id then
        Snapshot.update_local(local_account_id)
    end

    Snapshot.publish(true)
end

--- Runs every adapter's `setup`, from `mod.on_all_mods_loaded`.
Snapshot.setup = function ()
    for i = 1, adapter_count do
        local adapter = adapters[i]

        if adapter.setup then
            adapter.setup()
        end
    end
end

--- Clears every entry and runs every adapter's `reset`, for a new mission or a mod toggle.
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

--- Applies a settings change: runs every adapter's `refresh`, recomputes the displayed Shared
-- values and republishes every entry.
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

--- Runs every adapter's `teardown`, when the mod is disabled or unloaded.
Snapshot.teardown = function ()
    for i = 1, adapter_count do
        local adapter = adapters[i]

        if adapter.teardown then
            adapter.teardown()
        end
    end
end

return Snapshot
