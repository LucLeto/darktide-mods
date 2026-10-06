--- Charge state and effect detection for Perfect Thrust; decides what the ring shows.
-- Tracks the local player's melee windups (`ActionWindup` and `ActionBlockWindup`). When one
-- starts, the active buffs are scanned once for effects that gain stacks from the game's
-- `on_windup_trigger` proc event (blessings such as Thrust and Slow and Steady, the Ogryn talent
-- Crunch!, the built-in windup bonus of some weapons), and their stack caps are resolved from
-- the buff templates rather than from a per-weapon list.
--
-- Every stack is granted by the server and reaches a multiplayer client one round trip later.
-- The windup action itself runs on the client too and advances the same trigger timer the
-- server uses, so this module reads that timer (`_proc_trigger_time`) to predict the stack count
-- without the network delay, while the replicated stacks decide which effects count at all. The
-- `confirmed` timing mode uses only the replicated stacks.
--
-- Loaded by `PerfectThrust.lua` through `mod:io_dofile` and stored as `mod._tracker`. The windup
-- hooks there feed `on_windup_start`, `on_windup_update` and `on_windup_finish`, and the HUD
-- element calls `refresh` once per frame while a windup is tracked. All state lives in module
-- locals with preallocated tables, so nothing is allocated per frame.
-- module: PerfectThrust_tracker
-- author: LucLeto
local mod = get_mod("PerfectThrust")
local BuffSettings = require("scripts/settings/buff/buff_settings")
local BuffTemplates = require("scripts/settings/buff/buff_templates")

local math_abs = math.abs
local math_ceil = math.ceil
local math_floor = math.floor
local math_huge = math.huge
local string_format = string.format
local string_gsub = string.gsub
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

--- Proc event fired by the windup action once the heavy attack is available and then once per interval.
local ON_WINDUP_TRIGGER = BuffSettings.proc_events.on_windup_trigger

--- Trigger interval in seconds of an action that sets no `proc_time_interval`.
-- Same fallback `ActionWindup` and `ActionBlockWindup` use.
local PROC_INTERVAL_DEFAULT = 0.25

--- Most charge-dependent effects tracked during one windup; further matches are ignored.
local MAX_EFFECTS = 4

--- Highest fill a predicted effect reaches before the game has fired its last needed trigger.
-- Keeps a time-based fill from showing a full ring ahead of the trigger counter.
local NEARLY_FULL = 0.999

--- `timing_mode` setting value that takes READY from the replicated stacks only.
local TIMING_MODE_CONFIRMED = "confirmed"

--- Prefix of every debug chat line.
local DEBUG_PREFIX = "[Perfect Thrust] "

--- The tracker module table returned to `PerfectThrust.lua`.
local Tracker = {}

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

--- Effect descriptors by buff template name, or false for a template that does not stack while charging.
-- Templates never change at runtime, so each one is resolved at most once.
local descriptor_cache = {}

--- Preallocated pool of the effects tracked during the current windup.
-- Only the first `state.effect_count` entries are in use. Fields:
-- `child_name` buff template whose stacks are counted;
-- `offset` baseline stacks a parent buff keeps on its child, subtracted from the stack count;
-- `cap` stacks at which the effect is at its maximum;
-- `needed` windup triggers needed to reach `cap`;
-- `predictable` whether every trigger is known to grant a stack (no proc chance, no cooldown);
-- `observed` replicated stack count after the offset;
-- `start_observed` `observed` when the windup started;
-- `armed` whether the stack count has been seen at zero during this windup;
-- `confirmed` whether the effect has started stacking during this windup.
local effects = {}

--- Scratch list of the per-effect parts of a debug line.
local debug_parts = {}

for i = 1, MAX_EFFECTS do
    effects[i] = {
        child_name = nil,
        offset = 0,
        cap = 1,
        needed = 1,
        predictable = false,
        observed = 0,
        start_observed = 0,
        armed = false,
        confirmed = false
    }
end

--- The windup being tracked.
-- `active` is set only while a local windup with at least one charge-dependent effect runs.
-- `action`, `action_name` and `start_t` identify that windup and are checked against the
-- weapon_action component every frame. `first_trigger_t` is the time in action of the first
-- trigger, `interval` the time between triggers, `triggers` how many the game has fired so far
-- and `time_in_action` the latest fixed-step time in action. `fill` and `ready` are the last
-- values returned by `Tracker.refresh`; `ready` stays set for the rest of the windup.
local state = {
    active = false,
    action = nil,
    unit = nil,
    action_name = nil,
    start_t = 0,
    first_trigger_t = 0,
    interval = PROC_INTERVAL_DEFAULT,
    triggers = 0,
    time_in_action = 0,
    buff_extension = nil,
    weapon_action_component = nil,
    effect_count = 0,
    fill = 0,
    ready = false
}

-- ----------------------------------------------------------------------------
-- Effect discovery
-- ----------------------------------------------------------------------------

--- Works out whether a buff template stacks while a heavy attack is charged, and how.
-- A template qualifies when it procs on `on_windup_trigger` and adds stacks of a child buff that
-- has a `max_stacks` limit. Parent proc buffs (blessings, weapon windup bonuses) name the child in
-- `child_buff_template` and the stacks per trigger in `add_child_proc_events`. Proc buffs that add
-- their child from a proc function (the Ogryn talent Crunch!) are matched by the `*_parent` /
-- `*_child` naming convention, at one stack per trigger.
-- tab: template buff template
-- treturn: tab|bool descriptor with `child_name`, `offset`, `cap`, `per_trigger`, `uses_parent_override` and `predictable`, or false
local function _resolve_descriptor(template)
    local proc_events = template.proc_events
    local proc_chance = proc_events and proc_events[ON_WINDUP_TRIGGER]

    if not proc_chance then
        return false
    end

    local child_name = template.child_buff_template
    local per_trigger
    local uses_parent_override = false

    if child_name then
        local add_child_proc_events = template.add_child_proc_events

        per_trigger = add_child_proc_events and add_child_proc_events[ON_WINDUP_TRIGGER]
        uses_parent_override = true
    else
        local name = template.name
        local candidate = name and (string_gsub(name, "_parent$", "_child"))

        if candidate and candidate ~= name and BuffTemplates[candidate] then
            child_name = candidate
            per_trigger = 1
        end
    end

    local child_template = child_name and BuffTemplates[child_name]
    local cap = child_template and child_template.max_stacks

    if type(per_trigger) ~= "number" or per_trigger < 1 or type(cap) ~= "number" or cap < 1 then
        return false
    end

    return {
        child_name = child_name,
        offset = math_abs(child_template.stack_offset or 0),
        cap = cap,
        per_trigger = per_trigger,
        uses_parent_override = uses_parent_override,
        predictable = type(proc_chance) == "number" and proc_chance >= 1 and not template.cooldown_duration
    }
end

--- Returns the cached descriptor of a buff template, resolving it on first use.
-- tab: template buff template
-- treturn: tab|bool descriptor, or false when the template is not a charge-dependent effect
local function _descriptor(template)
    local name = template.name

    if not name then
        return false
    end

    local descriptor = descriptor_cache[name]

    if descriptor == nil then
        descriptor = _resolve_descriptor(template)
        descriptor_cache[name] = descriptor
    end

    return descriptor
end

--- Returns whether one of the first `count` tracked effects already counts the given child buff.
-- int: count effects filled in so far
-- string: child_name child buff template name
-- treturn: bool
local function _has_effect(count, child_name)
    for i = 1, count do
        if effects[i].child_name == child_name then
            return true
        end
    end

    return false
end

--- Returns an effect's replicated stack count without the parent's baseline stacks.
-- tab: buff_extension local player's buff extension
-- tab: effect entry of `effects`
-- treturn: int stacks, never below zero
local function _observed_stacks(buff_extension, effect)
    local observed = buff_extension:current_stacks(effect.child_name) - effect.offset

    return observed > 0 and observed or 0
end

--- Stops tracking and clears the windup state.
local function _reset_state()
    state.active = false
    state.action = nil
    state.unit = nil
    state.action_name = nil
    state.buff_extension = nil
    state.weapon_action_component = nil
    state.effect_count = 0
    state.triggers = 0
    state.time_in_action = 0
    state.fill = 0
    state.ready = false
end

-- ----------------------------------------------------------------------------
-- Debug output
-- ----------------------------------------------------------------------------

--- Formats the tracked effects as `child observed/cap` pairs for a debug line.
-- treturn: string
local function _debug_effects()
    table_clear(debug_parts)

    for i = 1, state.effect_count do
        local effect = effects[i]

        debug_parts[i] = string_format("%s %d/%d", effect.child_name, effect.observed, effect.cap)
    end

    return table_concat(debug_parts, ", ")
end

--- Writes the end of a tracked windup to chat when debug output is enabled.
-- param: reason why tracking ended, such as the action's finish reason
local function _debug_finish(reason)
    if not mod._settings.debug_logging then
        return
    end

    mod:echo(DEBUG_PREFIX .. "end (%s) after %.2fs, %d triggers, ready=%s: %s", tostring(reason), state.time_in_action, state.triggers, tostring(state.ready), _debug_effects())
end

-- ----------------------------------------------------------------------------
-- Windup hooks
-- ----------------------------------------------------------------------------

--- Starts tracking a windup of the local player when a charge-dependent effect is active.
-- Called after `ActionWindup.start` or `ActionBlockWindup.start`. Ignores bots and other players,
-- and windups without a trigger time. Scans the active buffs once, keeps the effects that belong
-- to the wielded weapon or to no weapon, and stays idle when none is found. An instance override
-- of `max_stacks` on a parent buff caps its children, as in `WeaponTraitParentProcBuff`.
-- tab: action windup action instance
-- number: t fixed-step time the action started at
Tracker.on_windup_start = function (action, t)
    if not action._is_local_unit or not action._is_human_controlled then
        return
    end

    if state.active then
        _debug_finish("restarted")
        _reset_state()
    end

    local first_trigger_t = action._proc_trigger_time

    if not first_trigger_t or first_trigger_t == math_huge then
        return
    end

    local buff_extension = action._buff_extension
    local weapon_action_component = action._weapon_action_component
    local inventory_component = action._inventory_component
    local buffs = buff_extension and buff_extension.buffs and buff_extension:buffs()

    if not buffs or not weapon_action_component or not inventory_component then
        return
    end

    local wielded_slot = inventory_component.wielded_slot
    local count = 0

    for i = 1, #buffs do
        local buff_instance = buffs[i]
        local template = buff_instance:template()
        local descriptor = template and _descriptor(template)

        if descriptor then
            local item_slot_name = buff_instance:item_slot_name()
            local child_name = descriptor.child_name

            if (item_slot_name == nil or item_slot_name == wielded_slot) and not _has_effect(count, child_name) then
                local cap = descriptor.cap

                if descriptor.uses_parent_override then
                    local override_data = buff_instance._template_override_data
                    local override_max_stacks = type(override_data) == "table" and override_data.max_stacks

                    if type(override_max_stacks) == "number" and override_max_stacks >= 1 then
                        cap = override_max_stacks
                    end
                end

                count = count + 1

                local effect = effects[count]

                effect.child_name = child_name
                effect.offset = descriptor.offset
                effect.cap = cap
                effect.needed = math_ceil(cap / descriptor.per_trigger)
                effect.predictable = descriptor.predictable
                effect.observed = _observed_stacks(buff_extension, effect)
                effect.start_observed = effect.observed
                -- Stacks left over from the previous attack are ignored until they are seen cleared
                -- or rising again, so a late-replicated old stack count can never confirm an effect.
                effect.armed = effect.observed == 0
                effect.confirmed = false

                if count == MAX_EFFECTS then
                    break
                end
            end
        end
    end

    local action_settings = action._action_settings
    local action_name = weapon_action_component.current_action_name

    if count == 0 then
        if mod._settings.debug_logging then
            mod:echo(DEBUG_PREFIX .. "windup %s: no charge-dependent effect", tostring(action_name))
        end

        return
    end

    state.active = true
    state.action = action
    state.unit = action._player_unit
    state.action_name = action_name
    state.start_t = t
    state.first_trigger_t = first_trigger_t
    state.interval = action_settings and action_settings.proc_time_interval or PROC_INTERVAL_DEFAULT
    state.triggers = 0
    state.time_in_action = 0
    state.buff_extension = buff_extension
    state.weapon_action_component = weapon_action_component
    state.effect_count = count
    state.fill = 0
    state.ready = false

    if mod._settings.debug_logging then
        mod:echo(DEBUG_PREFIX .. "windup %s: first trigger %.2fs, step %.2fs, effects: %s", tostring(action_name), first_trigger_t, state.interval, _debug_effects())
    end
end

--- Records the trigger count and time in action of the tracked windup.
-- Called after every fixed-step update of a windup action; other actions return immediately.
-- The action advances `_proc_trigger_time` by one interval each time it fires
-- `on_windup_trigger`, so this reads the game's own trigger count, and follows a server
-- correction that resets the timer.
-- tab: action windup action instance
-- number: time_in_action fixed-step time since the action started
Tracker.on_windup_update = function (action, time_in_action)
    if action ~= state.action then
        return
    end

    state.time_in_action = time_in_action

    local proc_trigger_time = action._proc_trigger_time

    if proc_trigger_time then
        local triggers = math_floor((proc_trigger_time - state.first_trigger_t) / state.interval + 0.5)

        state.triggers = triggers > 0 and triggers or 0
    end
end

--- Stops tracking when the tracked windup finishes.
-- Called after `ActionWindup.finish`. `ActionBlockWindup` inherits its finish from `ActionBlock`
-- and is not hooked; its end is caught by the weapon_action check in `Tracker.refresh`.
-- tab: action windup action instance
-- string: reason finish reason passed by the action handler
Tracker.on_windup_finish = function (action, reason)
    if action ~= state.action then
        return
    end

    _debug_finish(reason)
    _reset_state()
end

-- ----------------------------------------------------------------------------
-- Per-frame refresh
-- ----------------------------------------------------------------------------

--- Updates the tracked effects and returns what the ring should show.
-- Called by the HUD element every frame while a windup is tracked. Stops tracking first when the
-- weapon_action component no longer runs the tracked windup or the player unit is gone, which
-- covers a missed finish, a cancel, a weapon switch, death and rollbacks.
--
-- An effect is confirmed once it has started stacking during this windup, and only confirmed
-- effects count. Each one contributes a fill fraction; the ring shows the lowest, so READY waits
-- for the slowest effect. In `predicted` mode a predictable effect is full once the game has fired
-- its needed triggers and fills smoothly with the time in action before that, reaching
-- `k / needed` exactly at trigger `k`. In `confirmed` mode, and for effects that are not
-- predictable, the fraction is the replicated stack count over the cap. Once READY, the ring
-- stays full for the rest of the windup.
-- string: timing_mode `predicted` or `confirmed`
-- treturn: bool whether the ring should be visible
-- treturn: number fill fraction from 0 to 1
-- treturn: bool whether every confirmed effect is at its maximum
Tracker.refresh = function (timing_mode)
    if not state.active then
        return false, 0, false
    end

    local weapon_action_component = state.weapon_action_component
    local alive_units = ALIVE

    if weapon_action_component.current_action_name ~= state.action_name or weapon_action_component.start_t ~= state.start_t or not alive_units or not alive_units[state.unit] then
        _debug_finish("action ended")
        _reset_state()

        return false, 0, false
    end

    local buff_extension = state.buff_extension
    local predicted = timing_mode ~= TIMING_MODE_CONFIRMED
    local triggers = state.triggers
    local interval = state.interval
    local fill_start_t = state.first_trigger_t - interval
    local time_since_fill_start = state.time_in_action - fill_start_t
    local fill = 1
    local confirmed_count = 0

    for i = 1, state.effect_count do
        local effect = effects[i]
        local observed = _observed_stacks(buff_extension, effect)

        effect.observed = observed

        if not effect.confirmed then
            if observed == 0 then
                effect.armed = true
            elseif effect.armed or observed > effect.start_observed then
                effect.confirmed = true

                if mod._settings.debug_logging then
                    mod:echo(DEBUG_PREFIX .. "%s confirmed at %d/%d after %.2fs (%d triggers)", effect.child_name, observed, effect.cap, state.time_in_action, triggers)
                end
            end
        end

        if effect.confirmed then
            confirmed_count = confirmed_count + 1

            local cap = effect.cap
            local fraction

            if observed >= cap then
                fraction = 1
            elseif predicted and effect.predictable then
                if triggers >= effect.needed then
                    fraction = 1
                else
                    fraction = time_since_fill_start / (effect.needed * interval)

                    if fraction > NEARLY_FULL then
                        fraction = NEARLY_FULL
                    end
                end
            else
                fraction = observed / cap
            end

            if fraction < fill then
                fill = fraction
            end
        end
    end

    if confirmed_count == 0 then
        state.fill = 0

        return false, 0, false
    end

    if state.ready then
        fill = 1
    elseif fill >= 1 then
        fill = 1
        state.ready = true

        if mod._settings.debug_logging then
            mod:echo(DEBUG_PREFIX .. "READY after %.2fs (%d triggers, %s): %s", state.time_in_action, triggers, predicted and "predicted" or "confirmed", _debug_effects())
        end
    elseif fill < 0 then
        fill = 0
    end

    state.fill = fill

    return true, fill, state.ready
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

--- Returns whether a windup with at least one charge-dependent effect is being tracked.
-- treturn: bool
Tracker.is_charging_heavy_attack = function ()
    return state.active
end

--- Returns the effects tracked during the current windup.
-- The table is the preallocated pool; only its first `count` entries are in use, and it must not
-- be modified.
-- treturn: tab effect pool (see `effects`)
-- treturn: int count of entries in use
Tracker.get_relevant_charge_buffs = function ()
    return effects, state.effect_count
end

--- Returns whether every confirmed effect of the current windup has reached its maximum.
-- treturn: bool
Tracker.are_charge_buffs_maxed = function ()
    return state.ready
end

--- Returns the fill fraction last computed by `Tracker.refresh`.
-- treturn: number fill fraction from 0 to 1
Tracker.fill = function ()
    return state.fill
end

--- Stops tracking; used on game state changes and when the mod is enabled or disabled.
Tracker.reset = function ()
    _reset_state()
end

return Tracker
