local mod = get_mod("OverflowMeter")
local Snapshot = mod._snapshot

local get_mod = get_mod
local tostring = tostring

local ANOTHER_SCOREBOARD_MOD_NAME = "AnotherScoreboard"
local EXTERNAL_STATS_API_VERSION = 1

local GROUP_ID = "overflow_meter"
local GROUP_PLACEMENT = "own"

local METRICS = Snapshot.METRICS
local METRIC_COUNT = Snapshot.METRIC_COUNT

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

local Adapter = {
    name = ANOTHER_SCOREBOARD_MOD_NAME,
    active = false
}

local api = nil
local registered_mask = 0
local stat_keys = {}
local stat_count = 0
local target = nil

local function _find_scoreboard()
    local scoreboard = get_mod(ANOTHER_SCOREBOARD_MOD_NAME)

    if scoreboard and scoreboard.external_stats_api_version == EXTERNAL_STATS_API_VERSION then
        return scoreboard
    end
end

local function _wanted_mask(settings)
    local mask = 0

    for i = 1, METRIC_COUNT do
        if settings[METRICS[i].setting] then
            mask = mask + MASK_BITS[i]
        end
    end

    return mask
end

local function _collect()
    mod._share.push_peers()

    Snapshot.flush()
end

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

local function _register_with(scoreboard)
    if api then
        _unregister()
    end

    _register(scoreboard)
end

Adapter.setup = function ()
    local scoreboard = _find_scoreboard()

    Adapter.active = scoreboard ~= nil

    if scoreboard and scoreboard ~= api and mod:is_enabled() then
        _register_with(scoreboard)
    end
end

Adapter.reset = function ()
    target = nil

    if Adapter.active and not api and mod:is_enabled() then
        local scoreboard = _find_scoreboard()

        if scoreboard then
            _register(scoreboard)
        end
    end
end

Adapter.refresh = function ()
    local scoreboard = api

    if not scoreboard or not mod:is_enabled() or _wanted_mask(mod._settings) == registered_mask then
        return
    end

    _register_with(scoreboard)
end

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

Adapter.teardown = function ()
    _unregister()
end

Snapshot.register_adapter(Adapter)

return Adapter
