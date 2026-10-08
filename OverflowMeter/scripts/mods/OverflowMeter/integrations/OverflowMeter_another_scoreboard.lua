--- Optional integration with Another Scoreboard through its external stats API (version 1).
-- Registers an `Overflow Meter` group with one stat per enabled row and a collector, which
-- Another Scoreboard calls before it shows its values: the collector rereads the teammates'
-- shared totals and flushes the snapshot. Stats use `set` accumulation, so every publish replaces
-- the value. When the enabled rows change, the registration is rebuilt with the new set.
--
-- Explicit module loaded by `OverflowMeter.lua`; it registers itself with the snapshot and
-- becomes active in `setup` once Another Scoreboard with a matching API version is found.
-- Registration is withdrawn in `teardown` and redone after a new mission when needed.
-- module: OverflowMeter_another_scoreboard
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local Snapshot = mod._snapshot

local get_mod = get_mod
local tostring = tostring

--- Another Scoreboard's mod id and the external stats API version this adapter speaks.
local ANOTHER_SCOREBOARD_MOD_NAME = "AnotherScoreboard"
local EXTERNAL_STATS_API_VERSION = 1

--- Our stat group's id and its placement in Another Scoreboard's layout.
local GROUP_ID = "overflow_meter"
local GROUP_PLACEMENT = "own"

local METRICS = Snapshot.METRICS
local METRIC_COUNT = Snapshot.METRIC_COUNT

--- Per-metric entry fields, stat ids, value suffixes and bits for the enabled-rows mask.
local FIELDS = {}
local STAT_IDS = {}
local SUFFIXES = {}
local MASK_BITS = {}

for i = 1, METRIC_COUNT do
    local metric = METRICS[i]

    FIELDS[i] = metric.field
    -- Another Scoreboard sorts a group's rows by stat key; the index prefix keeps the metric order.
    STAT_IDS[i] = i .. "_" .. metric.id
    SUFFIXES[i] = metric.id == "efficiency" and "%" or nil
    MASK_BITS[i] = 2 ^ (i - 1)
end

--- The snapshot adapter.
local Adapter = {
    name = ANOTHER_SCOREBOARD_MOD_NAME,
    active = false
}

--- Registration state: the Another Scoreboard instance registered with, the mask of rows
-- registered, the stat key per metric and their count, and the instance a publish writes to.
local api = nil
local registered_mask = 0
local stat_keys = {}
local stat_count = 0
local target = nil

--- Returns Another Scoreboard when it speaks our API version.
-- treturn: ?tab Another Scoreboard mod
local function _find_scoreboard()
    local scoreboard = get_mod(ANOTHER_SCOREBOARD_MOD_NAME)

    if scoreboard and scoreboard.external_stats_api_version == EXTERNAL_STATS_API_VERSION then
        return scoreboard
    end
end

--- Returns the bit mask of the rows that are turned on.
-- tab: settings cached settings
-- treturn: number
local function _wanted_mask(settings)
    local mask = 0

    for i = 1, METRIC_COUNT do
        if settings[METRICS[i].setting] then
            mask = mask + MASK_BITS[i]
        end
    end

    return mask
end

--- Stat collector Another Scoreboard calls before showing its values.
local function _collect()
    mod._share.push_peers()

    Snapshot.flush()
end

--- Registers our group, one stat per enabled row and the collector.
-- Registers nothing while every row is turned off.
-- tab: scoreboard Another Scoreboard mod
local function _register(scoreboard)
    local settings = mod._settings

    api = scoreboard
    registered_mask = _wanted_mask(settings)
    stat_count = 0

    if registered_mask == 0 then
        return
    end

    local group_key, group_error = scoreboard:register_external_group(mod, {
        id = GROUP_ID,
        label = mod:localize("mod_name"),
        placement = GROUP_PLACEMENT,
        collapsible = true,
        collapsed_by_default = false
    })

    if not group_key then
        mod:info("Another Scoreboard group registration failed: %s", tostring(group_error))

        return
    end

    for i = 1, METRIC_COUNT do
        local metric = METRICS[i]

        if settings[metric.setting] then
            local stat_key, stat_error = scoreboard:register_external_stat(mod, {
                id = STAT_IDS[i],
                label = mod:localize(metric.loc),
                group = group_key,
                value_type = "number",
                accumulation = "set",
                ranking = "higher_better",
                decimals = 0,
                suffix = SUFFIXES[i]
            })

            if stat_key then
                stat_keys[i] = stat_key
                stat_count = stat_count + 1
            else
                mod:info("Another Scoreboard stat registration failed for %s: %s", metric.id, tostring(stat_error))
            end
        end
    end

    if stat_count > 0 then
        scoreboard:set_external_stat_collector(mod, _collect)
    end
end

--- Withdraws everything registered and forgets the instance.
local function _unregister()
    local scoreboard = api

    api = nil
    registered_mask = 0
    stat_count = 0
    target = nil

    for i = 1, METRIC_COUNT do
        stat_keys[i] = nil
    end

    if scoreboard then
        scoreboard:unregister_external_provider(mod)
    end
end

--- Re-registers with an instance, withdrawing any earlier registration first.
-- tab: scoreboard Another Scoreboard mod
local function _register_with(scoreboard)
    if api then
        _unregister()
    end

    _register(scoreboard)
end

--- Finds Another Scoreboard and registers with it while the mod is enabled.
Adapter.setup = function ()
    local scoreboard = _find_scoreboard()

    Adapter.active = scoreboard ~= nil

    if scoreboard and scoreboard ~= api and mod:is_enabled() then
        _register_with(scoreboard)
    end
end

--- Registers again for a new mission or after the mod was re-enabled, if not registered.
Adapter.reset = function ()
    target = nil

    if Adapter.active and not api and mod:is_enabled() then
        local scoreboard = _find_scoreboard()

        if scoreboard then
            _register(scoreboard)
        end
    end
end

--- Rebuilds the registration when the set of enabled rows changed.
Adapter.refresh = function ()
    local scoreboard = api

    if not scoreboard or not mod:is_enabled() or _wanted_mask(mod._settings) == registered_mask then
        return
    end

    _register_with(scoreboard)
end

--- Picks the instance to write to before a publish, re-registering if Another Scoreboard was reloaded.
Adapter.prepare = function ()
    target = nil

    if not mod:is_enabled() then
        return
    end

    local scoreboard = _find_scoreboard()

    if not scoreboard then
        return
    end

    if scoreboard ~= api then
        _register_with(scoreboard)
    end

    if stat_count > 0 and scoreboard:is_enabled() then
        target = scoreboard
    end
end

--- Writes an entry's values into our registered stats.
-- tab: entry snapshot entry
Adapter.publish = function (entry)
    local scoreboard = target

    if not scoreboard then
        return
    end

    local account_id = entry.account_id

    for i = 1, METRIC_COUNT do
        local stat_key = stat_keys[i]

        if stat_key then
            scoreboard:update_external_stat(stat_key, account_id, entry[FIELDS[i]])
        end
    end
end

--- Withdraws the registration when the mod is disabled or unloaded.
Adapter.teardown = function ()
    _unregister()
end

Snapshot.register_adapter(Adapter)

return Adapter
