--- Aiming blessing detection for Perfect Thrust; decides what the ring shows while aiming down sights.
-- Tracks the local player's ranged aim (the game's alternate fire) for blessings that gain a step
-- per interval while aiming and start over on every shot: Surgical, built on the
-- `chance_based_on_aim_time` buff template (a `stepped_stat_buff`), and Pinpointing Target, built on
-- `power_level_on_aim_time` (a `proc_buff` with a lerped stat) and, on the Grenadier Gauntlet, on a
-- clone of `chance_based_on_aim_time` with its own step functions. Every weapon's blessing is a
-- clone of one of these two base templates and shares its `start_func`, so the blessings are
-- recognised by that function rather than by a per-weapon list, and their interval and step count
-- are resolved per buff from the blessing tier's override data.
--
-- Both base templates compute their steps from the same inputs: whether alternate fire is active,
-- the later of its start and the last shot, and the latest fixed-step time. No stack count is
-- replicated that could confirm them - a stepped buff computes its steps on demand, and the proc
-- events of a non-predicted buff run on the server only - but the local player predicts these
-- components on the same fixed frames the server simulates. This module evaluates the game's
-- formula on them, so the `timing_mode` setting does not apply to aiming.
--
-- Loaded by `PerfectThrust.lua` through `mod:io_dofile` and stored as `mod._aim_tracker`. The HUD
-- element calls `refresh` with the local player's extensions once per frame while no melee windup
-- is tracked and the `show_ads_blessings` setting is on. The active buffs are scanned once per aim,
-- when alternate fire starts or the wielded slot changes. Only game state is read, and all state
-- lives in module locals with preallocated tables, so nothing is allocated per frame.
-- module: PerfectThrust_aim_tracker
-- author: LucLeto
local mod = get_mod("PerfectThrust")
local BaseWeaponTraitBuffTemplates = require("scripts/settings/buff/weapon_traits_buff_templates/base_weapon_trait_buff_templates")
local FixedFrame = require("scripts/utilities/fixed_frame")

local math_floor = math.floor
local math_huge = math.huge
local pcall = pcall
local string_format = string.format
local table_concat = table.concat
local table_clear = table.clear
    or function (t)
        for k in pairs(t) do
            t[k] = nil
        end
    end
local type = type

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Base templates of the aiming blessings, if the game still defines them.
local STEPPED_AIM_TEMPLATE = BaseWeaponTraitBuffTemplates.chance_based_on_aim_time
local LERPED_AIM_TEMPLATE = BaseWeaponTraitBuffTemplates.power_level_on_aim_time

--- `start_func` shared by every clone of the stepped base template (Surgical, and the Grenadier
-- Gauntlet's Pinpointing Target, which replaces only the step functions), and by every clone of
-- the lerped one (Pinpointing Target). Both read the alternate_fire and action_shoot components.
local STEPPED_AIM_START_FUNC = STEPPED_AIM_TEMPLATE and STEPPED_AIM_TEMPLATE.start_func
local LERPED_AIM_START_FUNC = LERPED_AIM_TEMPLATE and LERPED_AIM_TEMPLATE.start_func

--- Kinds of aiming blessing, by the base template they are cloned from.
local KIND_STEPPED = "stepped"
local KIND_LERPED = "lerped"

--- Most aiming blessings tracked during one aim; further matches are ignored.
local MAX_EFFECTS = 4

--- Highest fill before every blessing has reached its last step.
-- Keeps the time-based fill from showing a full ring ahead of the game's own step count.
local NEARLY_FULL = 0.999

--- Prefix of every debug line, as in `PerfectThrust_tracker.lua`.
local DEBUG_PREFIX = "[Perfect Thrust] "

--- Stands in for a buff's missing override data; never written.
local EMPTY_TABLE = {}

--- The aim tracker module table returned to `PerfectThrust.lua`.
local AimTracker = {}

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

--- Blessing kind by buff template name, or false for a template that is no aiming blessing.
-- Templates never change at runtime, so each one is resolved at most once.
local kind_cache = {}

--- Preallocated pool of the blessings tracked during the current aim.
-- Only the first `state.effect_count` entries are in use. Fields:
-- `name` buff template name;
-- `kind` `KIND_STEPPED` or `KIND_LERPED`;
-- `duration` seconds per step;
-- `max_steps` steps at which the blessing is at its maximum;
-- `steps` steps the game grants at the latest refresh, from 0 to `max_steps`.
local effects = {}

--- Scratch list of the per-blessing parts of a debug line.
local debug_parts = {}

for i = 1, MAX_EFFECTS do
    effects[i] = {
        name = nil,
        kind = nil,
        duration = 1,
        max_steps = 1,
        steps = 0
    }
end

--- The aim being tracked.
-- `unit_data_extension` is the local player's unit data extension the three cached components
-- were read from; they are read again only when it changes. `active` is set while an aim is open,
-- with or without blessings: `start_t` is alternate fire's start time and `wielded_slot` the slot
-- it was scanned for, `effect_count` the blessings found and `span` the seconds the slowest of them
-- needs to reach its maximum. `check_t` is the later of `start_t` and the last shot, from which the
-- game counts the steps, `shots` the shots fired during the aim and `elapsed` the fixed-step time
-- since `check_t` at the latest refresh. `fill` and `ready` are the last values returned by
-- `AimTracker.refresh`; `ready` stays set until the next shot.
local state = {
    unit_data_extension = nil,
    alternate_fire_component = nil,
    action_shoot_component = nil,
    inventory_component = nil,
    active = false,
    start_t = 0,
    wielded_slot = nil,
    effect_count = 0,
    span = 0,
    check_t = 0,
    shots = 0,
    elapsed = 0,
    fill = 0,
    ready = false
}

-- ----------------------------------------------------------------------------
-- Blessing discovery
-- ----------------------------------------------------------------------------

--- Returns the cached kind of a buff template, resolving it on first use.
-- tab: template buff template
-- treturn: string|bool `KIND_STEPPED`, `KIND_LERPED`, or false when it is no aiming blessing
local function _kind(template)
    local name = template.name

    if not name then
        return false
    end

    local kind = kind_cache[name]

    if kind == nil then
        local start_func = template.start_func

        if start_func == nil then
            kind = false
        elseif start_func == STEPPED_AIM_START_FUNC then
            kind = KIND_STEPPED
        elseif start_func == LERPED_AIM_START_FUNC then
            kind = KIND_LERPED
        else
            kind = false
        end

        kind_cache[name] = kind
    end

    return kind
end

--- Returns whether one of the first `count` tracked blessings already uses the given template.
-- int: count blessings filled in so far
-- string: name buff template name
-- treturn: bool
local function _has_effect(count, name)
    for i = 1, count do
        if effects[i].name == name then
            return true
        end
    end

    return false
end

--- Returns the interval and step count of an aiming blessing, as its buff resolves them.
-- A stepped buff takes `duration_per_stack` from the tier's override data or the template, and its
-- maximum from `min_max_step_func`, called with the buff's own template data and context as
-- `SteppedStatBuff` does; its single stack adds nothing, as `stack_offset` takes it back to zero. A
-- lerped buff takes `duration_per_step` and `num_steps_for_max_stat` from the override data or the
-- template. Nothing is returned when a value is missing or not a positive finite number.
-- tab: buff_instance active buff
-- tab: template its buff template
-- string: kind `KIND_STEPPED` or `KIND_LERPED`
-- treturn: ?number seconds per step
-- treturn: ?number steps at the maximum
local function _resolve_steps(buff_instance, template, kind)
    local override_data = buff_instance._template_override_data

    if type(override_data) ~= "table" then
        override_data = EMPTY_TABLE
    end

    local duration, max_steps

    if kind == KIND_STEPPED then
        duration = override_data.duration_per_stack or template.duration_per_stack

        local min_max_step_func = template.min_max_step_func

        if min_max_step_func then
            local ok, _, max = pcall(min_max_step_func, buff_instance._template_data, buff_instance._template_context)

            if ok then
                max_steps = max
            end
        end
    else
        duration = override_data.duration_per_step or template.duration_per_step
        max_steps = override_data.num_steps_for_max_stat or template.num_steps_for_max_stat
    end

    -- The comparisons also reject NaN, which fails every one of them.
    if type(duration) ~= "number" or not (duration > 0 and duration < math_huge) or type(max_steps) ~= "number" or not (max_steps >= 1 and max_steps < math_huge) then
        return nil
    end

    return duration, max_steps
end

--- Ends the tracked aim and clears its state; the cached components are kept.
local function _reset_session()
    state.active = false
    state.start_t = 0
    state.wielded_slot = nil
    state.effect_count = 0
    state.span = 0
    state.check_t = 0
    state.shots = 0
    state.elapsed = 0
    state.fill = 0
    state.ready = false
end

--- Ends the tracked aim and forgets the cached components.
local function _reset_state()
    _reset_session()

    state.unit_data_extension = nil
    state.alternate_fire_component = nil
    state.action_shoot_component = nil
    state.inventory_component = nil
end

--- Caches the components of a new local player unit.
-- The components stay nil when one of them cannot be read; `AimTracker.refresh` then shows nothing.
-- tab: unit_data_extension the local player's unit data extension
local function _bind_unit(unit_data_extension)
    state.unit_data_extension = unit_data_extension

    local read_component = unit_data_extension.read_component

    if not read_component then
        return
    end

    local alternate_fire_component = read_component(unit_data_extension, "alternate_fire")
    local action_shoot_component = read_component(unit_data_extension, "action_shoot")
    local inventory_component = read_component(unit_data_extension, "inventory")

    if alternate_fire_component and action_shoot_component and inventory_component then
        state.alternate_fire_component = alternate_fire_component
        state.action_shoot_component = action_shoot_component
        state.inventory_component = inventory_component
    end
end

-- ----------------------------------------------------------------------------
-- Debug output
-- ----------------------------------------------------------------------------

--- Formats the tracked blessings as `name steps/max` pairs, or with `with_interval` as
-- `name max x interval` pairs, for a debug line.
-- ?bool: with_interval whether to show the interval instead of the current steps
-- treturn: string
local function _debug_effects(with_interval)
    table_clear(debug_parts)

    for i = 1, state.effect_count do
        local effect = effects[i]

        if with_interval then
            debug_parts[i] = string_format("%s %d x %gs", effect.name, effect.max_steps, effect.duration)
        else
            debug_parts[i] = string_format("%s %d/%d", effect.name, effect.steps, effect.max_steps)
        end
    end

    return table_concat(debug_parts, ", ")
end

--- Writes the end of a tracked aim with blessings to the log when debug output is enabled.
-- param: reason why tracking ended
local function _debug_finish(reason)
    if not state.active or state.effect_count == 0 or not mod._settings.debug_logging then
        return
    end

    mod:info(DEBUG_PREFIX .. "ADS end (%s) after %.2fs, %d shots, ready=%s: %s", tostring(reason), state.elapsed, state.shots, tostring(state.ready), _debug_effects())
end

-- ----------------------------------------------------------------------------
-- Aim tracking
-- ----------------------------------------------------------------------------

--- Starts tracking an aim and finds its blessings.
-- Scans the active buffs once and keeps the aiming blessings of the wielded slot; like the game's
-- own stat check, blessings of a weapon that is not wielded do not count.
-- ?tab: buff_extension the local player's buff extension
-- number: start_t alternate fire's start time
-- string: wielded_slot the wielded inventory slot
local function _start_session(buff_extension, start_t, wielded_slot)
    local buffs = buff_extension and buff_extension.buffs and buff_extension:buffs()
    local debug_logging = mod._settings.debug_logging
    local count = 0
    local span = 0
    local buff_count = buffs and #buffs or 0

    for i = 1, buff_count do
        local buff_instance = buffs[i]
        local template = buff_instance:template()
        local kind = template and _kind(template)

        if kind and buff_instance:item_slot_name() == wielded_slot and not _has_effect(count, template.name) then
            local duration, max_steps = _resolve_steps(buff_instance, template, kind)

            if duration then
                count = count + 1

                local effect = effects[count]

                effect.name = template.name
                effect.kind = kind
                effect.duration = duration
                effect.max_steps = max_steps
                effect.steps = 0

                local effect_span = max_steps * duration

                if effect_span > span then
                    span = effect_span
                end

                if count == MAX_EFFECTS then
                    break
                end
            elseif debug_logging then
                mod:info(DEBUG_PREFIX .. "%s skipped: its interval or step count could not be resolved", tostring(template.name))
            end
        end
    end

    local fire_last_t = state.action_shoot_component.fire_last_t

    state.active = true
    state.start_t = start_t
    state.wielded_slot = wielded_slot
    state.effect_count = count
    state.span = span
    state.check_t = fire_last_t > start_t and fire_last_t or start_t
    state.shots = 0
    state.elapsed = 0
    state.fill = 0
    state.ready = false

    if debug_logging then
        if count == 0 then
            mod:info(DEBUG_PREFIX .. "ADS %s: no aiming blessing", tostring(wielded_slot))
        else
            mod:info(DEBUG_PREFIX .. "ADS %s: expected READY %.2fs, blessings: %s", tostring(wielded_slot), span, _debug_effects(true))
        end
    end
end

--- Updates the tracked aim and returns what the ring should show.
-- Called by the HUD element every frame while no melee windup is tracked and the
-- `show_ads_blessings` setting is on. The aim ends when alternate fire is no longer active, which
-- covers leaving ADS, reloads, weapon switches, staggers and the Shotpistol & Shield push; a new
-- alternate fire start time or wielded slot starts a new aim and scans the buffs again.
--
-- Each blessing's steps follow the game's formula, `floor(elapsed / interval)` capped at its
-- maximum, with `elapsed` the latest fixed-step time minus the later of the aim start and the last
-- shot. A shot therefore restarts every blessing, and READY waits until every one of them has
-- reached its maximum, so with two blessings it follows the slower one. Before READY the ring
-- fills with `elapsed` over the slowest blessing's time to its maximum; once READY, it stays full
-- until the next shot.
-- ?tab: player_extensions the HUD's player extensions, with `unit_data` and `buff`
-- treturn: bool whether the ring should be visible
-- treturn: number fill fraction from 0 to 1
-- treturn: bool whether every tracked blessing is at its maximum
AimTracker.refresh = function (player_extensions)
    local unit_data_extension = player_extensions and player_extensions.unit_data

    if unit_data_extension ~= state.unit_data_extension then
        _debug_finish("player unit changed")
        _reset_state()

        if unit_data_extension then
            _bind_unit(unit_data_extension)
        end
    end

    local alternate_fire_component = state.alternate_fire_component

    if not alternate_fire_component then
        return false, 0, false
    end

    if not alternate_fire_component.is_active then
        if state.active then
            _debug_finish("left ADS")
            _reset_session()
        end

        return false, 0, false
    end

    local start_t = alternate_fire_component.start_t
    local wielded_slot = state.inventory_component.wielded_slot

    if not state.active or start_t ~= state.start_t or wielded_slot ~= state.wielded_slot then
        if state.active then
            _debug_finish(wielded_slot ~= state.wielded_slot and "weapon switched" or "ADS restarted")
            _reset_session()
        end

        _start_session(player_extensions.buff, start_t, wielded_slot)
    end

    local count = state.effect_count

    if count == 0 then
        return false, 0, false
    end

    local fire_last_t = state.action_shoot_component.fire_last_t
    local check_t = fire_last_t > start_t and fire_last_t or start_t

    if check_t ~= state.check_t then
        if mod._settings.debug_logging then
            mod:info(DEBUG_PREFIX .. "ADS shot after %.2fs, ready=%s: %s", state.elapsed, tostring(state.ready), _debug_effects())
        end

        state.check_t = check_t
        state.shots = state.shots + 1
        state.ready = false
    end

    local elapsed = FixedFrame.get_latest_fixed_time() - check_t
    local maxed = true

    for i = 1, count do
        local effect = effects[i]
        local max_steps = effect.max_steps
        local steps = math_floor(elapsed / effect.duration)

        if steps >= max_steps then
            steps = max_steps
        else
            maxed = false

            if steps < 0 then
                steps = 0
            end
        end

        effect.steps = steps
    end

    state.elapsed = elapsed

    local fill = 1

    if not state.ready then
        if maxed then
            state.ready = true

            if mod._settings.debug_logging then
                mod:info(DEBUG_PREFIX .. "READY after %.2fs (ADS): %s", elapsed, _debug_effects())
            end
        else
            fill = elapsed / state.span

            if fill > NEARLY_FULL then
                fill = NEARLY_FULL
            elseif fill < 0 then
                fill = 0
            end
        end
    end

    state.fill = fill

    return true, fill, state.ready
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

--- Returns whether an aim is being tracked, with or without blessings.
-- treturn: bool
AimTracker.is_tracking = function ()
    return state.active
end

--- Stops tracking and forgets the cached components; used on game state changes, when the mod is
-- enabled or disabled and when the `show_ads_blessings` setting is turned off.
AimTracker.reset = function ()
    _reset_state()
end

return AimTracker
