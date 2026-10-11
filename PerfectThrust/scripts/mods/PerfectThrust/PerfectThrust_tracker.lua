--- Charge state and effect detection for Perfect Thrust; decides what the ring shows.
-- Tracks the local player's melee windups (`ActionWindup` and `ActionBlockWindup`). When one
-- starts, the active buffs are scanned once for effects that gain stacks from the game's
-- `on_windup_trigger` proc event (blessings such as Thrust and Slow and Steady, the Ogryn talent
-- Crunch!, the built-in windup bonus of some weapons), and their stack caps are resolved from
-- the buff templates rather than from a per-weapon list. Each effect's own proc conditions are
-- checked as well, so a conditional bonus is left out of windups in which it cannot stack.
--
-- Every stack is granted by the server and reaches a multiplayer client one round trip later.
-- The windup action itself runs on the client too and advances the same trigger timer the
-- server uses, so this module reads that timer (`_proc_trigger_time`) to predict the stack count
-- without the network delay, while the replicated stacks decide which effects count at all. The
-- `confirmed` timing mode uses only the replicated stacks.
--
-- With the `show_heavy_threshold` setting on, the heavy attack threshold is tracked too: the
-- earliest moment a release still gives the heavy attack, resolved from the weapon's heavy attack
-- input, the hold timer the game's input parser started at the press (read-only, with a fallback
-- to the windup start) and the action's own heavy attack chain time. A windup without any such effect then fills
-- up to that threshold and is READY there. A windup with effects shows one ring from its start
-- over the expected charge: charging, then heavy attack available once the threshold is reached,
-- then READY once the effects are at their maximum. The tracking mode is chosen once when the
-- windup starts, and READY always follows the effects when there are any.
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

--- Tracking modes of a windup: its charge-dependent effects, or the regular heavy attack
-- threshold when no such effect is active.
local MODE_EFFECTS = "effects"
local MODE_HEAVY_READINESS = "heavy_readiness"

--- Action inputs that chain a windup into its heavy attack, in lookup order: the melee heavy
-- attack, the melee heavy attack while the weapon special is active, and the heavy bash or stab of
-- a ranged weapon's special attack. Each one names both the entry in the windup's
-- `allowed_chain_actions` and the input in the weapon template's `action_inputs`.
local HEAVY_CHAIN_INPUTS = {
    "heavy_attack",
    "heavy_attack_special",
    "special_action_heavy"
}

--- Action input parser of the weapon actions in `PlayerUnitActionInputExtension._action_input_parsers`.
local WEAPON_ACTION_PARSER = "weapon_action"

--- Indices of the running flag, current element and element start time tables in a frame of
-- `ActionInputParser._sequences`, as the parser defines them.
local SEQUENCE_IS_RUNNING = 1
local SEQUENCE_CURRENT_ELEMENT_INDEX = 2
local SEQUENCE_ELEMENT_START_T = 3

--- Prefix of every debug line. Debug lines go through `mod:info`, which DMF writes to the game's
-- console log only, unless the player changed DMF's logging settings.
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
-- `ready_t` time in action of the trigger that is expected to reach `cap`;
-- `predictable` whether every trigger is known to grant a stack (no proc chance, no cooldown);
-- `observed` replicated stack count after the offset;
-- `start_observed` `observed` when the windup started;
-- `armed` whether the stack count has been seen at zero during this windup;
-- `confirmed` whether the effect has started stacking during this windup.
local effects = {}

--- Scratch list of the per-effect parts of a debug line.
local debug_parts = {}

--- Scratch proc event parameters for checking a buff's windup trigger conditions; like the
-- parameters of the game's own `on_windup_trigger` event, only `action_settings` is set.
local windup_trigger_params = {}

for i = 1, MAX_EFFECTS do
    effects[i] = {
        child_name = nil,
        offset = 0,
        cap = 1,
        needed = 1,
        ready_t = 0,
        predictable = false,
        observed = 0,
        start_observed = 0,
        armed = false,
        confirmed = false
    }
end

--- The windup being tracked.
-- `active` is set only while a local windup with at least one charge-dependent effect, or with a
-- resolved regular heavy attack threshold, runs; `mode` is `MODE_EFFECTS` or `MODE_HEAVY_READINESS`
-- accordingly. `tracks_heavy` is set when the heavy attack threshold is tracked, and
-- `heavy_threshold` is then the time in action from which it can be released, possibly 0 when the
-- hold was already done before the windup started. With effects and a heavy threshold, `ready_t` is the expected time
-- of READY, `heavy_fraction` the share of the ring filled at the heavy threshold and
-- `heavy_available` whether that threshold has been reached; it stays set for the rest of the windup.
-- `action`, `action_name` and `start_t` identify that windup and are checked against the
-- weapon_action component every frame. `first_trigger_t` is the time in action of the first
-- trigger, `interval` the time between triggers, `triggers` how many the game has fired so far
-- and `time_in_action` the latest fixed-step time in action. `fill` and `ready` are the last
-- values returned by `Tracker.refresh`; `ready` stays set for the rest of the windup.
local state = {
    active = false,
    mode = nil,
    tracks_heavy = false,
    heavy_threshold = 0,
    ready_t = 0,
    heavy_fraction = 0,
    heavy_available = false,
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

--- Returns whether a buff's own conditions let it proc on the trigger of the windup that starts.
-- Mirrors `ProcBuff.update_proc_events`: the template's `conditional_proc_func`, then its
-- `specific_check_proc_funcs` entry for `on_windup_trigger` or else its `check_proc_func`, called
-- with the buff instance's template data and context and the windup's action settings as event
-- parameters. This leaves out conditional weapon mechanics in windups where they cannot stack,
-- such as the Relic Blades' sprint-only bonus on a standing heavy attack or the Mechanicus Power
-- Sword's bonus with its special off. Proc chance and cooldown are not checked. A check that
-- cannot run keeps the effect, as before.
-- tab: buff_instance active buff
-- tab: template its buff template
-- ?tab: action_settings settings of the windup action
-- number: t fixed-step time the windup started at
-- string: child_name child buff template name, for debug output
-- treturn: bool
local function _can_proc_on_windup(buff_instance, template, action_settings, t, child_name)
    local conditional_proc_func = template.conditional_proc_func
    local specific_check_proc_funcs = template.specific_check_proc_funcs
    local check_proc_func = specific_check_proc_funcs and specific_check_proc_funcs[ON_WINDUP_TRIGGER] or template.check_proc_func

    if not conditional_proc_func and not check_proc_func then
        return true
    end

    local template_data = buff_instance._template_data
    local template_context = buff_instance._template_context

    if type(template_data) ~= "table" or type(template_context) ~= "table" then
        return true
    end

    local ok, allowed = true, true

    if conditional_proc_func then
        ok, allowed = pcall(conditional_proc_func, template_data, template_context, t)
    end

    if check_proc_func and not (ok and not allowed) then
        windup_trigger_params.action_settings = action_settings
        ok, allowed = pcall(check_proc_func, windup_trigger_params, template_data, template_context, t)

        table_clear(windup_trigger_params)
    end

    if ok and not allowed then
        if mod._settings.debug_logging then
            mod:info(DEBUG_PREFIX .. "%s skipped: its condition is not met in this windup", tostring(child_name))
        end

        return false
    end

    return true
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
    state.mode = nil
    state.tracks_heavy = false
    state.heavy_threshold = 0
    state.ready_t = 0
    state.heavy_fraction = 0
    state.heavy_available = false
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
-- Regular heavy attack threshold
-- ----------------------------------------------------------------------------

--- Returns the chain time of one heavy attack transition, or nil when it cannot be resolved.
-- An input-dependent `chain_time` table is resolved like the windup action's own
-- `_latest_chain_time`, by the input that started the windup or its `default`. A transition gated
-- by a running action state is skipped, because that state is not known here.
-- tab: chain_action entry of `allowed_chain_actions`, or one of its alternatives
-- ?string: used_input input that started the windup
-- treturn: ?number chain time in seconds of unscaled action time
local function _transition_chain_time(chain_action, used_input)
    if type(chain_action) ~= "table" or chain_action.running_action_state_requirement then
        return nil
    end

    local chain_time = chain_action.chain_time

    if type(chain_time) == "table" then
        chain_time = chain_time[used_input] or chain_time.default
    end

    if type(chain_time) ~= "number" or chain_time < 0 then
        return nil
    end

    return chain_time
end

--- Returns how much of the heavy attack input's hold was already done when the windup started.
-- The game's input parser starts the hold timer of the heavy attack input when the attack press is
-- registered. In an attack chain that press often comes while the previous attack still runs, so
-- the hold is partly or fully done before the windup starts. This reads the timer from the parser's
-- latest frame: the heavy attack sequence must be running, either still on its first (hold)
-- element, whose start time is the press, or past it, when the hold is complete. A sequence that
-- is no longer running was already decided by a release, typically a quick tap during the previous
-- attack that turns this windup into a light attack. These are internals of `ActionInputParser`;
-- when the hold cannot be read, the caller counts it from the windup start, which is never early.
-- tab: action windup action instance
-- string: chain_input action input of the heavy attack transition
-- number: t fixed-step time the windup started at
-- number: hold_duration hold duration of the heavy attack input's first element
-- treturn: ?number seconds of the hold done at the windup start, from 0 to `hold_duration`
-- treturn: ?bool true when the parser was read but the heavy attack input had already been released
local function _heavy_hold_elapsed(action, chain_input, t, hold_duration)
    local script_unit = ScriptUnit
    local has_extension = type(script_unit) == "table" and script_unit.has_extension
    local unit = action._player_unit

    if not has_extension or not unit then
        return nil
    end

    local ok, action_input_extension = pcall(has_extension, unit, "action_input_system")
    local parsers = ok and type(action_input_extension) == "table" and action_input_extension._action_input_parsers
    local parser = type(parsers) == "table" and parsers[WEAPON_ACTION_PARSER]

    if type(parser) ~= "table" then
        return nil
    end

    local ring_buffer = parser._sequences
    local sequences = type(ring_buffer) == "table" and ring_buffer[parser._ring_buffer_index]
    local network_lookups = parser._ACTION_INPUT_NETWORK_LOOKUP
    local action_component = parser._action_component
    local network_lookup = type(network_lookups) == "table" and action_component and network_lookups[action_component.template_name]
    local sequence_i = type(network_lookup) == "table" and network_lookup[chain_input]

    if type(sequences) ~= "table" or type(sequence_i) ~= "number" then
        return nil
    end

    local is_running = sequences[SEQUENCE_IS_RUNNING]
    local element_indices = sequences[SEQUENCE_CURRENT_ELEMENT_INDEX]
    local element_start_ts = sequences[SEQUENCE_ELEMENT_START_T]

    if type(is_running) ~= "table" or type(element_indices) ~= "table" or type(element_start_ts) ~= "table" then
        return nil
    end

    local running = is_running[sequence_i]

    if running == false then
        return nil, true
    elseif running ~= true then
        return nil
    end

    local element_index = element_indices[sequence_i]
    local start_t = element_start_ts[sequence_i]

    -- An unset start time is -math.huge; a start after the windup cannot belong to its press.
    if type(element_index) ~= "number" or type(start_t) ~= "number" or not (start_t > -math_huge and start_t <= t) then
        return nil
    end

    if element_index > 1 then
        return hold_duration
    elseif element_index == 1 then
        local elapsed = t - start_t

        return elapsed < hold_duration and elapsed or hold_duration
    end

    return nil
end

--- Works out the earliest time in action at which releasing a windup still gives its heavy attack.
-- Called once when a windup starts. The input layer decides light or heavy on release: once the
-- weapon's heavy attack input has been held for its first step's `duration`, a release queues the
-- heavy attack, and the queued input waits up to its `buffer_time` for the windup to allow the
-- heavy attack at its chain time. So the threshold is the rest of that hold, unless the chain time
-- comes more than one buffer time later, which a release must then wait for. The hold timer starts
-- with the press, which in an attack chain can be before the windup; the part of the hold already
-- done is read from the input parser, and when it cannot be read the hold is counted from the
-- windup start, which is never early. A release made in reaction to READY lands at least one fixed
-- step later, which keeps it past the light attack's inclusive time window and the queued input
-- alive at the chain time, so no extra margin is needed. The threshold is 0 when the hold is
-- complete and the chain time is within one buffer time of the windup start.
--
-- Takes the first heavy attack transition of `HEAVY_CHAIN_INPUTS` in the windup's
-- `allowed_chain_actions`; of several alternatives the latest chain time is used, since the
-- conditions that pick one are not known here. Like the action handler's chain check, the chain
-- time is divided by the action's time scale. A `chain_until` only opens an earlier window and is
-- ignored. Nothing is returned when the hold duration is unknown or no finite threshold can be
-- resolved.
-- tab: action windup action instance
-- ?tab: action_settings settings of the windup action
-- tab: weapon_action_component the local player's weapon_action component
-- number: t fixed-step time the windup started at
-- treturn: ?number threshold in seconds of time in action
-- treturn: ?string action input of the heavy attack transition
-- treturn: ?number hold duration of the heavy attack input
-- treturn: ?number unscaled chain time
-- treturn: ?number action time scale
-- treturn: ?number buffer time of the heavy attack input, 0 when it has none
-- treturn: ?number hold already done at the windup start, or nil when it could not be read
-- treturn: ?bool true when the heavy attack input had already been released at the windup start
local function _resolve_heavy_threshold(action, action_settings, weapon_action_component, t)
    local allowed_chain_actions = action_settings and action_settings.allowed_chain_actions

    if type(allowed_chain_actions) ~= "table" then
        return nil
    end

    local chain_input, chain_action

    for i = 1, #HEAVY_CHAIN_INPUTS do
        local input = HEAVY_CHAIN_INPUTS[i]
        local candidate = allowed_chain_actions[input]

        if type(candidate) == "table" then
            chain_input = input
            chain_action = candidate

            break
        end
    end

    if not chain_action then
        return nil
    end

    local used_input = action._used_input
    local alternatives = #chain_action
    local chain_time

    if alternatives == 0 then
        chain_time = _transition_chain_time(chain_action, used_input)
    else
        for i = 1, alternatives do
            local alternative_chain_time = _transition_chain_time(chain_action[i], used_input)

            if alternative_chain_time and (not chain_time or alternative_chain_time > chain_time) then
                chain_time = alternative_chain_time
            end
        end
    end

    local time_scale = weapon_action_component.time_scale
    local weapon_template = action._weapon_template
    local action_inputs = weapon_template and weapon_template.action_inputs
    local action_input = action_inputs and action_inputs[chain_input]
    local input_sequence = action_input and action_input.input_sequence
    local hold_element = input_sequence and input_sequence[1]
    local hold_duration = hold_element and hold_element.duration

    -- `not (x >= 0)` also rejects NaN, which fails every comparison.
    if not chain_time or type(time_scale) ~= "number" or time_scale <= 0 or type(hold_duration) ~= "number" or not (hold_duration >= 0) then
        return nil
    end

    local buffer_time = action_input.buffer_time

    if type(buffer_time) ~= "number" or not (buffer_time >= 0) then
        buffer_time = 0
    end

    local hold_elapsed, hold_released = _heavy_hold_elapsed(action, chain_input, t, hold_duration)
    local hold_remaining = hold_duration - (hold_elapsed or 0)
    -- Windup kinds never use the action handler's inverted time scale.
    local threshold = chain_time / time_scale - buffer_time

    if threshold < hold_remaining then
        threshold = hold_remaining
    end

    if threshold < 0 then
        threshold = 0
    end

    if not (threshold >= 0 and threshold < math_huge) then
        return nil
    end

    return threshold, chain_input, hold_duration, chain_time, time_scale, buffer_time, hold_elapsed, hold_released
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

--- Writes the end of a tracked windup to the log when debug output is enabled.
-- param: reason why tracking ended, such as the action's finish reason
local function _debug_finish(reason)
    if not mod._settings.debug_logging then
        return
    end

    if state.mode == MODE_HEAVY_READINESS then
        mod:info(DEBUG_PREFIX .. "end (%s) after %.2fs, ready=%s (regular heavy)", tostring(reason), state.time_in_action, tostring(state.ready))

        return
    end

    mod:info(DEBUG_PREFIX .. "end (%s) after %.2fs, %d triggers, ready=%s: %s", tostring(reason), state.time_in_action, state.triggers, tostring(state.ready), _debug_effects())
end

-- ----------------------------------------------------------------------------
-- Windup hooks
-- ----------------------------------------------------------------------------

--- Starts tracking a windup of the local player when a charge-dependent effect is active.
-- Called after `ActionWindup.start` or `ActionBlockWindup.start`. Ignores bots and other players.
-- Scans the active buffs once and keeps the effects that belong to the wielded weapon or to no
-- weapon and whose own conditions let them stack in this windup; a windup without a trigger time
-- can have none. An instance override of `max_stacks` on a parent buff caps its children, as in
-- `WeaponTraitParentProcBuff`. With the `show_heavy_threshold` setting on, it also resolves the
-- heavy attack threshold: a windup with effects then gets the expected READY time and the heavy
-- threshold's share of the ring, and a windup without effects tracks that threshold alone. Without
-- effects and without a resolvable threshold it stays idle.
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
    -- Every charge-dependent effect stacks from the windup trigger. A windup without a trigger time
    -- (the game ignores alternative chain lists when computing it) can still have a heavy attack.
    local has_trigger_time = first_trigger_t and first_trigger_t ~= math_huge
    local show_heavy_threshold = mod._settings.show_heavy_threshold

    if not has_trigger_time and not show_heavy_threshold then
        return
    end

    local buff_extension = action._buff_extension
    local weapon_action_component = action._weapon_action_component
    local inventory_component = action._inventory_component
    local buffs = buff_extension and buff_extension.buffs and buff_extension:buffs()

    if not buffs or not weapon_action_component or not inventory_component then
        return
    end

    local action_settings = action._action_settings
    local interval = action_settings and action_settings.proc_time_interval or PROC_INTERVAL_DEFAULT
    local wielded_slot = inventory_component.wielded_slot
    local count = 0
    local buff_count = has_trigger_time and #buffs or 0

    for i = 1, buff_count do
        local buff_instance = buffs[i]
        local template = buff_instance:template()
        local descriptor = template and _descriptor(template)

        if descriptor then
            local item_slot_name = buff_instance:item_slot_name()
            local child_name = descriptor.child_name

            if (item_slot_name == nil or item_slot_name == wielded_slot) and not _has_effect(count, child_name) and _can_proc_on_windup(buff_instance, template, action_settings, t, child_name) then
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
                effect.ready_t = first_trigger_t + (effect.needed - 1) * interval
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

    local action_name = weapon_action_component.current_action_name
    local heavy_threshold, chain_input, hold_duration, chain_time, time_scale, buffer_time, hold_elapsed, hold_released

    if show_heavy_threshold then
        heavy_threshold, chain_input, hold_duration, chain_time, time_scale, buffer_time, hold_elapsed, hold_released = _resolve_heavy_threshold(action, action_settings, weapon_action_component, t)
    end

    if count == 0 and not heavy_threshold then
        -- Windups without a trigger time stay silent, as they always have.
        if has_trigger_time and mod._settings.debug_logging then
            mod:info(DEBUG_PREFIX .. (show_heavy_threshold and "windup %s: no charge-dependent effect, no heavy attack threshold" or "windup %s: no charge-dependent effect"), tostring(action_name))
        end

        return
    end

    -- The ring of a windup with effects spans the expected charge up to the slowest effect's cap.
    local ready_t = heavy_threshold or 0

    if heavy_threshold then
        for i = 1, count do
            local effect_ready_t = effects[i].ready_t

            if effect_ready_t > ready_t then
                ready_t = effect_ready_t
            end
        end
    end

    state.active = true
    state.mode = count > 0 and MODE_EFFECTS or MODE_HEAVY_READINESS
    state.tracks_heavy = heavy_threshold ~= nil
    state.heavy_threshold = heavy_threshold or 0
    state.ready_t = ready_t
    state.heavy_fraction = heavy_threshold and ready_t > 0 and heavy_threshold / ready_t or 0
    state.heavy_available = false
    state.action = action
    state.unit = action._player_unit
    state.action_name = action_name
    state.start_t = t
    state.first_trigger_t = has_trigger_time and first_trigger_t or math_huge
    state.interval = interval
    state.triggers = 0
    state.time_in_action = 0
    state.buff_extension = buff_extension
    state.weapon_action_component = weapon_action_component
    state.effect_count = count
    state.fill = 0
    state.ready = false

    if mod._settings.debug_logging then
        -- How much of the hold was done before the windup, `released` when the heavy attack input had
        -- already been released, or `?` when the input parser could not be read.
        local held = hold_elapsed and string_format("%.2fs", hold_elapsed) or hold_released and "released" or "?"

        if count == 0 then
            mod:info(DEBUG_PREFIX .. "windup %s: regular heavy, threshold %.2fs (%s hold %.2fs, held %s, chain %.2fs, time scale %.2f, buffer %.2fs)", tostring(action_name), heavy_threshold, chain_input, hold_duration, held, chain_time, time_scale, buffer_time)
        else
            mod:info(DEBUG_PREFIX .. "windup %s: first trigger %.2fs, step %.2fs, effects: %s", tostring(action_name), first_trigger_t, state.interval, _debug_effects())

            if heavy_threshold then
                mod:info(DEBUG_PREFIX .. "heavy threshold %.2fs (%s hold %.2fs, held %s, chain %.2fs, time scale %.2f, buffer %.2fs), expected READY %.2fs", heavy_threshold, chain_input, hold_duration, held, chain_time, time_scale, buffer_time, ready_t)
            end
        end
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
--
-- A windup tracked for regular heavy attack readiness is visible from its start and fills with
-- the fixed-step time in action up to the heavy threshold, where it is READY. This runs entirely
-- on the local windup timing, so `timing_mode` does not apply to it.
--
-- A windup with effects and a heavy threshold is visible from its start too, and its ring spans
-- the expected charge: it fills with the time in action up to the heavy threshold's share of the
-- ring, then reports the heavy attack as available and fills the rest by the slowest effect, by
-- time up to its expected cap in `predicted` mode for predictable effects and by the replicated
-- stacks otherwise. Effects that are not confirmed yet hold the fill below full. READY follows the
-- same rule as above and additionally waits for the heavy threshold.
-- string: timing_mode `predicted` or `confirmed`
-- treturn: bool whether the ring should be visible
-- treturn: number fill fraction from 0 to 1
-- treturn: bool whether every confirmed effect is at its maximum, or the heavy threshold is reached
-- treturn: bool whether the heavy attack is available while the effects still build
Tracker.refresh = function (timing_mode)
    if not state.active then
        return false, 0, false, false
    end

    local weapon_action_component = state.weapon_action_component
    local alive_units = ALIVE

    if weapon_action_component.current_action_name ~= state.action_name or weapon_action_component.start_t ~= state.start_t or not alive_units or not alive_units[state.unit] then
        _debug_finish("action ended")
        _reset_state()

        return false, 0, false, false
    end

    if state.mode == MODE_HEAVY_READINESS then
        local fill = 1

        if not state.ready then
            local time_in_action = state.time_in_action
            local heavy_threshold = state.heavy_threshold

            if time_in_action >= heavy_threshold then
                state.ready = true

                if mod._settings.debug_logging then
                    mod:info(DEBUG_PREFIX .. "READY after %.2fs (regular heavy)", time_in_action)
                end
            elseif time_in_action > 0 then
                fill = time_in_action / heavy_threshold
            else
                fill = 0
            end
        end

        state.fill = fill

        return true, fill, state.ready, false
    end

    local buff_extension = state.buff_extension
    local predicted = timing_mode ~= TIMING_MODE_CONFIRMED
    local triggers = state.triggers
    local interval = state.interval
    local time_in_action = state.time_in_action
    local fill_start_t = state.first_trigger_t - interval
    local time_since_fill_start = time_in_action - fill_start_t
    local fill = 1
    local confirmed_count = 0
    local heavy_threshold = state.heavy_threshold
    local shows_heavy = state.tracks_heavy
    local heavy_available = shows_heavy and (state.heavy_available or time_in_action >= heavy_threshold)
    local heavy_fraction = state.heavy_fraction
    local ring_fill = 1

    for i = 1, state.effect_count do
        local effect = effects[i]
        local observed = _observed_stacks(buff_extension, effect)
        local fraction

        effect.observed = observed

        if not effect.confirmed then
            if observed == 0 then
                effect.armed = true
            elseif effect.armed or observed > effect.start_observed then
                effect.confirmed = true

                if mod._settings.debug_logging then
                    mod:info(DEBUG_PREFIX .. "%s confirmed at %d/%d after %.2fs (%d triggers)", effect.child_name, observed, effect.cap, time_in_action, triggers)
                end
            end
        end

        if effect.confirmed then
            confirmed_count = confirmed_count + 1

            local cap = effect.cap

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

        -- Past the heavy threshold the ring covers the rest of the expected charge; an effect that
        -- has not been confirmed yet is expected to stack on time but never fills the ring.
        if heavy_available then
            local progress

            if fraction == 1 then
                progress = 1
            elseif predicted and effect.predictable then
                local span = effect.ready_t - heavy_threshold

                progress = span > 0 and (time_in_action - heavy_threshold) / span or NEARLY_FULL

                if progress > NEARLY_FULL then
                    progress = NEARLY_FULL
                end
            else
                progress = fraction or 0
            end

            progress = heavy_fraction + (1 - heavy_fraction) * progress

            if progress < ring_fill then
                ring_fill = progress
            end
        end
    end

    if not shows_heavy then
        if confirmed_count == 0 then
            state.fill = 0

            return false, 0, false, false
        end

        if state.ready then
            fill = 1
        elseif fill >= 1 then
            fill = 1
            state.ready = true

            if mod._settings.debug_logging then
                mod:info(DEBUG_PREFIX .. "READY after %.2fs (%d triggers, %s): %s", time_in_action, triggers, predicted and "predicted" or "confirmed", _debug_effects())
            end
        elseif fill < 0 then
            fill = 0
        end

        state.fill = fill

        return true, fill, state.ready, false
    end

    if heavy_available and not state.heavy_available then
        state.heavy_available = true

        if mod._settings.debug_logging then
            mod:info(DEBUG_PREFIX .. "heavy attack available after %.2fs", time_in_action)
        end
    end

    if state.ready then
        fill = 1
    elseif heavy_available and confirmed_count > 0 and fill >= 1 then
        fill = 1
        state.ready = true

        if mod._settings.debug_logging then
            mod:info(DEBUG_PREFIX .. "READY after %.2fs (%d triggers, %s): %s", time_in_action, triggers, predicted and "predicted" or "confirmed", _debug_effects())
        end
    else
        fill = heavy_available and ring_fill or time_in_action / state.ready_t

        if fill > NEARLY_FULL then
            fill = NEARLY_FULL
        elseif fill < 0 then
            fill = 0
        end
    end

    state.fill = fill

    return true, fill, state.ready, heavy_available
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

--- Returns whether a windup is being tracked, for its charge-dependent effects or for regular
-- heavy attack readiness.
-- treturn: bool
Tracker.is_charging_heavy_attack = function ()
    return state.active
end

--- Returns the effects tracked during the current windup.
-- The table is the preallocated pool; only its first `count` entries are in use, and it must not
-- be modified. `count` is 0 while regular heavy attack readiness is tracked.
-- treturn: tab effect pool (see `effects`)
-- treturn: int count of entries in use
Tracker.get_relevant_charge_buffs = function ()
    return effects, state.effect_count
end

--- Returns whether every confirmed effect of the current windup has reached its maximum, or,
-- while regular heavy attack readiness is tracked, whether the heavy threshold has been reached.
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
