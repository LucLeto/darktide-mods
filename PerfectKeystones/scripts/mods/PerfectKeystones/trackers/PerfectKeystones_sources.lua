--- Game-state readers of Perfect Keystones; read counts, caps and timers from the local player's buffs.
-- Every value is read from the observed buff instance or its template as the game resolves it, so
-- talent variants and upgrades are followed without values hard-coded here:
--
-- * Counts come from `buff:visual_stack_count()`, the count the game's own buff HUD shows. It
--   already accounts for `talent_resource` buffs (`use_talent_resource`), parent buffs (child stacks
--   without the baseline child), the Zealot passive's derived stacks, stepped buffs with a
--   `stack_offset` and custom visual counts such as Empowered Psionics' stored charges.
-- * Timers come from `buff:start_time()` and `buff:duration()`, which includes any extra duration
--   a talent added to the instance, measured against the fixed-step time the buffs use.
-- * Proc timing comes from the proc buff's active start time and its active and cooldown durations.
--
-- Values that are missing, not numbers, infinite, NaN or out of range are reported as missing, so
-- the kinds never divide by an unvalidated value and hide instead of inventing state. Nothing here
-- writes to the game.
--
-- Loaded by `trackers/PerfectKeystones_kinds.lua` through `mod:io_dofile`.
-- module: PerfectKeystones_sources
-- author: LucLeto
local BuffTemplates = require("scripts/settings/buff/buff_templates")

local math_floor = math.floor
local math_huge = math.huge
local type = type

--- Ability type of the Blitz in the ability extension.
local GRENADE_ABILITY_TYPE = "grenade_ability"

--- Cap source ids, as in `PerfectKeystones_registry.lua`.
local CAP_MAX_STACKS = "max_stacks"
local CAP_MAX_STACKS_CAP = "max_stacks_cap"
local CAP_TEMPLATE_DATA = "template_data"
local CAP_CHILD_TEMPLATE = "child_template"
local CAP_TALENT_RESOURCE = "talent_resource"

--- The sources module table.
local Sources = {}

-- ----------------------------------------------------------------------------
-- Validation
-- ----------------------------------------------------------------------------

--- Returns whether a value is a finite number; the comparisons also reject NaN.
-- param: value value to check
-- treturn: bool
local function _is_finite(value)
    return type(value) == "number" and value > -math_huge and value < math_huge
end

--- Returns whether a value is a finite number above zero.
-- param: value value to check
-- treturn: bool
local function _is_positive(value)
    return type(value) == "number" and value > 0 and value < math_huge
end

Sources.is_finite = _is_finite
Sources.is_positive = _is_positive

-- ----------------------------------------------------------------------------
-- Readers
-- ----------------------------------------------------------------------------

--- Returns a buff's remaining time and effective duration.
-- The remaining time is `start_time + duration - t`, clamped to the duration, as the game's own
-- `_duration_progress` computes it; `t` is the latest fixed-step time, the clock the buff's start
-- time is measured on.
-- tab: buff buff instance
-- number: t latest fixed-step time
-- treturn: ?number remaining seconds from 0 to the duration
-- treturn: ?number effective duration in seconds
Sources.timer = function (buff, t)
    local duration = buff.duration and buff:duration()
    local start_time = buff.start_time and buff:start_time()

    if not _is_positive(duration) or not _is_finite(start_time) then
        return nil, nil
    end

    local remaining = start_time + duration - t

    if remaining > duration then
        remaining = duration
    elseif remaining < 0 then
        remaining = 0
    end

    return remaining, duration
end

--- Returns a buff's displayed stack count.
-- A negative count, such as a parent buff whose baseline child has not reached the client yet, is
-- reported as missing rather than as zero.
-- tab: buff buff instance
-- treturn: ?int stack count from 0
Sources.count = function (buff)
    local count = buff.visual_stack_count and buff:visual_stack_count()

    if not _is_finite(count) or count < 0 then
        return nil
    end

    return math_floor(count + 0.5)
end

--- Returns a buff's effective stack maximum from the given source.
-- tab: buff buff instance
-- string: source one of the registry's `CAP_*` values
-- ?tab: talent_resource_component the local player's `talent_resource` component
-- treturn: ?int maximum from 1
Sources.cap = function (buff, source, talent_resource_component)
    local cap

    if source == CAP_MAX_STACKS then
        cap = buff.max_stacks and buff:max_stacks()
    elseif source == CAP_MAX_STACKS_CAP then
        cap = buff.max_stacks_cap and buff:max_stacks_cap()
    elseif source == CAP_TEMPLATE_DATA then
        local template_data = buff.template_data and buff:template_data()

        cap = type(template_data) == "table" and template_data.max_stacks
    elseif source == CAP_CHILD_TEMPLATE then
        local template = buff.template and buff:template()
        local child_name = template and template.child_buff_template
        local child_template = child_name and BuffTemplates[child_name]

        cap = child_template and child_template.max_stacks
    elseif source == CAP_TALENT_RESOURCE then
        cap = talent_resource_component and talent_resource_component.max_resource
    end

    if not _is_positive(cap) then
        return nil
    end

    cap = math_floor(cap + 0.5)

    return cap >= 1 and cap or nil
end

--- Returns a proc buff's active start time and its active and cooldown durations.
-- The durations are resolved by the buff itself (`_active_duration`, `_cooldown_duration`), which
-- applies talent and trait overrides, with the template fields as fallback. The active start time
-- reaches a client through the game's proc activation RPC.
-- tab: buff proc buff instance
-- treturn: ?number active start time on the fixed-step clock
-- treturn: ?number active duration in seconds
-- treturn: ?number cooldown in seconds, or nil without one
Sources.proc_timing = function (buff)
    local active_start_time = buff.active_start_time and buff:active_start_time()
    local template = buff.template and buff:template()
    local active_duration, cooldown

    if buff._active_duration then
        active_duration = buff:_active_duration()
    elseif template then
        active_duration = template.active_duration
    end

    if buff._cooldown_duration then
        cooldown = buff:_cooldown_duration()
    elseif template then
        cooldown = template.cooldown_duration
    end

    if not _is_finite(active_start_time) or not _is_positive(active_duration) then
        return nil, nil, nil
    end

    return active_start_time, active_duration, _is_positive(cooldown) and cooldown or nil
end

--- Returns the running replenishment timer of a Lone Wolf replenishment buff.
-- The buff keeps the time the next charge is restored in its template data, and the interval of
-- the selected Blitz; there is no timer while no charge is missing or between a restored charge
-- and the next interval.
-- tab: buff `adamant_grenade_replenishment` instance
-- treturn: ?number fixed-step time of the next restored charge
-- treturn: ?number replenishment interval in seconds
Sources.replenishment = function (buff)
    local template_data = buff.template_data and buff:template_data()

    if type(template_data) ~= "table" then
        return nil, nil
    end

    local next_t = template_data.next_grenade_t
    local interval = template_data.cooldown

    if not _is_finite(next_t) or not _is_positive(interval) then
        return nil, nil
    end

    return next_t, interval
end

--- Returns how many Blitz charges are missing, through the ability extension's read-only accessor.
-- An unequipped or disabled Blitz reports none.
-- ?tab: ability_extension the local player's ability extension
-- treturn: ?int missing charges
Sources.missing_blitz_charges = function (ability_extension)
    local missing = ability_extension and ability_extension.missing_ability_charges and ability_extension:missing_ability_charges(GRENADE_ABILITY_TYPE)

    if not _is_finite(missing) then
        return nil
    end

    return missing
end

return Sources
