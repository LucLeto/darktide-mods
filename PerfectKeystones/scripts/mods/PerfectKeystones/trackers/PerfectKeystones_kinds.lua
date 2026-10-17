--- Presentation kinds of Perfect Keystones; turn observed buff state into what a ring shows.
-- Each kind reads its keystone's buffs through `trackers/PerfectKeystones_sources.lua` and writes
-- the keystone's normalized presentation state, which the HUD element draws without knowing any
-- game mechanics. The state is derived from the game's current values on every call: no kind keeps
-- a timer of its own, so nothing pauses while a ring is hidden or disabled, and a ring that appears
-- again shows the latest actual state at once.
--
-- Presentation state fields (one preallocated table per keystone, see `Kinds.new_state`):
-- `visible` whether the ring should be drawn;
-- `phase` `PHASE_ACTIVE` (timed active effect), `PHASE_BUILDING` (resource before an activation),
-- `PHASE_HELD` (held stacks), `PHASE_COOLDOWN` or `PHASE_REPLENISHING`, nil while hidden;
-- `fill` lit fraction of the ring from 0 to 1;
-- `base` `BASE_ACTIVE` or `BASE_COOLDOWN`, the colour of the lit segments;
-- `countdown` whether the fill is a timed active effect's remaining time, which the near-expiry
-- threshold applies to;
-- `highlight` `HIGHLIGHT_NONE`, `HIGHLIGHT_NEXT` (only the next expiring stack's share changes
-- colour) or `HIGHLIGHT_SHARED` (every lit segment changes colour);
-- `highlight_from` fill fraction from which the highlight starts;
-- `expiry` elapsed fraction from 0 to 1 of the timer behind the highlight, nil without valid timing;
-- `stacks`, `max_stacks` held count and effective maximum, nil in timed phases, so a label can never
-- show a resource the presentation hides;
-- `remaining`, `duration` seconds of the timer shown or behind the highlight, nil without one;
-- `pulse` whether the tracker noted a transition worth a pulse on this frame; the tracker sets it
-- after every call, so it holds for exactly the frame of the transition.
--
-- Loaded by `PerfectKeystones_tracker.lua` through `mod:io_dofile`; each kind is called with the
-- keystone's compiled tracking entry, its state and the frame context, and returns nothing.
-- module: PerfectKeystones_kinds
-- author: LucLeto
local mod = get_mod("PerfectKeystones")
local Sources = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/trackers/PerfectKeystones_sources")
local Registry = mod._registry

local count_of = Sources.count
local cap_of = Sources.cap
local timer_of = Sources.timer

--- Wielded slot of the Blitz, for Empowered Psionics' gate.
local SLOT_GRENADE_ABILITY = "slot_grenade_ability"

--- Seconds a running Lone Wolf countdown may lose its timer while charges are still missing,
-- shown empty, before the ring hides. The game clears the timer on the fixed frame that restores
-- a charge and sets the next interval on the following one.
local REPLENISH_GAP_HOLD = 0.1

local GATE_BLITZ_WIELDED = Registry.GATE_BLITZ_WIELDED
local VISIBILITY_ALWAYS = Registry.VISIBILITY_ALWAYS
local DECAY_PROGRESSIVE = Registry.DECAY_PROGRESSIVE

--- The kinds module table; kinds are stored by their registry kind id.
local Kinds = {}

--- Phases, colours and highlight modes of the presentation state.
local PHASE_ACTIVE = "active"
local PHASE_BUILDING = "building"
local PHASE_HELD = "held"
local PHASE_COOLDOWN = "cooldown"
local PHASE_REPLENISHING = "replenishing"
local BASE_ACTIVE = "active"
local BASE_COOLDOWN = "cooldown"
local HIGHLIGHT_NONE = "none"
local HIGHLIGHT_NEXT = "next"
local HIGHLIGHT_SHARED = "shared"

Kinds.PHASE_ACTIVE = PHASE_ACTIVE
Kinds.PHASE_BUILDING = PHASE_BUILDING
Kinds.PHASE_HELD = PHASE_HELD
Kinds.PHASE_COOLDOWN = PHASE_COOLDOWN
Kinds.PHASE_REPLENISHING = PHASE_REPLENISHING
Kinds.BASE_ACTIVE = BASE_ACTIVE
Kinds.BASE_COOLDOWN = BASE_COOLDOWN
Kinds.HIGHLIGHT_NONE = HIGHLIGHT_NONE
Kinds.HIGHLIGHT_NEXT = HIGHLIGHT_NEXT
Kinds.HIGHLIGHT_SHARED = HIGHLIGHT_SHARED

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

--- Returns a new, hidden presentation state.
-- treturn: tab presentation state
Kinds.new_state = function ()
    return {
        visible = false,
        phase = nil,
        fill = 0,
        base = BASE_ACTIVE,
        countdown = false,
        highlight = HIGHLIGHT_NONE,
        highlight_from = 0,
        expiry = nil,
        stacks = nil,
        max_stacks = nil,
        remaining = nil,
        duration = nil,
        pulse = false
    }
end

--- Hides a presentation state and clears its values; `pulse` is left to the tracker.
-- tab: state presentation state
local function _hide(state)
    state.visible = false
    state.phase = nil
    state.fill = 0
    state.base = BASE_ACTIVE
    state.countdown = false
    state.highlight = HIGHLIGHT_NONE
    state.highlight_from = 0
    state.expiry = nil
    state.stacks = nil
    state.max_stacks = nil
    state.remaining = nil
    state.duration = nil
end

Kinds.hide = _hide

--- Shows a timer whose fill is its remaining fraction: a full ring that empties as time runs out.
-- tab: state presentation state
-- string: phase `PHASE_ACTIVE`, `PHASE_COOLDOWN` or `PHASE_REPLENISHING`
-- string: base `BASE_ACTIVE` or `BASE_COOLDOWN`
-- number: remaining remaining seconds from 0 to the duration
-- number: duration positive duration in seconds
local function _show_timer(state, phase, base, remaining, duration)
    state.visible = true
    state.phase = phase
    state.fill = remaining / duration
    state.base = base
    state.countdown = phase == PHASE_ACTIVE
    state.highlight = HIGHLIGHT_NONE
    state.highlight_from = 0
    state.expiry = nil
    state.stacks = nil
    state.max_stacks = nil
    state.remaining = remaining
    state.duration = duration
end

--- Shows held stacks as their share of the maximum, without a timer.
-- tab: state presentation state
-- string: phase `PHASE_HELD` or `PHASE_BUILDING`
-- int: count held stacks from 0 to `cap`
-- int: cap effective maximum from 1
local function _show_stacks(state, phase, count, cap)
    state.visible = true
    state.phase = phase
    state.fill = count / cap
    state.base = BASE_ACTIVE
    state.countdown = false
    state.highlight = HIGHLIGHT_NONE
    state.highlight_from = 0
    state.expiry = nil
    state.stacks = count
    state.max_stacks = cap
    state.remaining = nil
    state.duration = nil
end

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

--- Returns the first found buff of a list of watch indices.
-- tab: found buff instances by watch index
-- ?tab: indices watch indices in priority order
-- treturn: ?tab buff instance
local function _first(found, indices)
    if not indices then
        return nil
    end

    for i = 1, #indices do
        local buff = found[indices[i]]

        if buff then
            return buff
        end
    end

    return nil
end

--- Returns the timer with the most time left among a list of active buffs.
-- tab: found buff instances by watch index
-- ?tab: indices watch indices of the active buffs
-- number: t latest fixed-step time
-- treturn: ?number remaining seconds
-- treturn: ?number duration in seconds
local function _active_timer(found, indices, t)
    if not indices then
        return nil, nil
    end

    local best_remaining, best_duration

    for i = 1, #indices do
        local buff = found[indices[i]]

        if buff then
            local remaining, duration = timer_of(buff, t)

            if remaining and (best_remaining == nil or remaining > best_remaining) then
                best_remaining = remaining
                best_duration = duration
            end
        end
    end

    return best_remaining, best_duration
end

--- Returns a buff's held count and effective maximum, with the count clamped to the maximum.
-- tab: tracked compiled tracking entry, for its cap source
-- tab: buff buff instance
-- tab: ctx frame context
-- treturn: ?int count, nil when it or the maximum is missing
-- treturn: ?int maximum
local function _count_and_cap(tracked, buff, ctx)
    local count = count_of(buff)
    local cap = count and cap_of(buff, tracked.cap, ctx.talent_resource_component)

    if not cap then
        return nil, nil
    end

    if count > cap then
        count = cap
    end

    return count, cap
end

--- Shows held stacks whose next or shared expiry is announced by colour.
-- With `HIGHLIGHT_NEXT`, a progressive decay style drains the next stack's share instead.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
-- string: highlight `HIGHLIGHT_NEXT` or `HIGHLIGHT_SHARED`
local function _timed_stacks(tracked, state, ctx, highlight)
    local buff = _first(ctx.found, tracked.buffs)
    local count, cap

    if buff then
        count, cap = _count_and_cap(tracked, buff, ctx)
    end

    if not count or count <= 0 then
        _hide(state)

        return
    end

    _show_stacks(state, PHASE_HELD, count, cap)

    local remaining, duration = timer_of(buff, ctx.t)

    if not remaining then
        -- No valid timing: keep the observed fill without an expiry animation.
        return
    end

    local expiry = 1 - remaining / duration

    state.remaining = remaining
    state.duration = duration
    state.expiry = expiry

    if highlight == HIGHLIGHT_NEXT and tracked.decay_style == DECAY_PROGRESSIVE then
        state.fill = (count - expiry) / cap

        return
    end

    state.highlight = highlight
    state.highlight_from = highlight == HIGHLIGHT_NEXT and (count - 1) / cap or 0
end

-- ----------------------------------------------------------------------------
-- Kinds
-- ----------------------------------------------------------------------------

--- `duration`: a timed buff's remaining time, a full ring that empties counter-clockwise.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.duration = function (tracked, state, ctx)
    local remaining, duration = _active_timer(ctx.found, tracked.active, ctx.t)

    if remaining then
        _show_timer(state, PHASE_ACTIVE, BASE_ACTIVE, remaining, duration)
    else
        _hide(state)
    end
end

--- `stack_decay`: stacks that expire one at a time on a renewable timer. The held stacks stay
-- filled; only the next stack's share turns toward the expiring colour as its timer runs down.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.stack_decay = function (tracked, state, ctx)
    _timed_stacks(tracked, state, ctx, HIGHLIGHT_NEXT)
end

--- `stack_shared`: stacks that share one refreshable timer. The held stacks stay filled; the whole
-- filled area turns toward the expiring colour together.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.stack_shared = function (tracked, state, ctx)
    _timed_stacks(tracked, state, ctx, HIGHLIGHT_SHARED)
end

--- `stack_discrete`: held stacks in whole steps, without a timer.
-- Shown while above zero, or, for an entry with a visibility setting, below its maximum (zero
-- included) or always; a deficit is held back for the entry's settle time after its stack buff
-- appears. An entry with a gate setting additionally needs its gate condition when that setting is
-- on. A missing buff or maximum is not a zero count and hides the ring.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.stack_discrete = function (tracked, state, ctx)
    local buff = _first(ctx.found, tracked.buffs)

    if buff ~= tracked.seen_buff then
        tracked.seen_buff = buff
        tracked.seen_t = ctx.t
    end

    local count, cap

    if buff then
        count, cap = _count_and_cap(tracked, buff, ctx)
    end

    if not count then
        _hide(state)

        return
    end

    local settings = ctx.settings
    local visible
    local visibility_setting = tracked.visibility_setting

    if visibility_setting then
        if settings[visibility_setting] == VISIBILITY_ALWAYS then
            visible = true
        else
            visible = count < cap and ctx.t - tracked.seen_t >= tracked.settle
        end
    else
        visible = count > 0
    end

    if visible and tracked.gate == GATE_BLITZ_WIELDED and settings[tracked.gate_setting] then
        local inventory_component = ctx.inventory_component

        visible = inventory_component ~= nil and inventory_component.wielded_slot == SLOT_GRENADE_ABILITY
    end

    if visible then
        _show_stacks(state, PHASE_HELD, count, cap)
    else
        _hide(state)
    end
end

--- `hybrid`: an actual timed active buff takes priority and shows its remaining time; otherwise
-- the held resource is shown in whole steps while above zero. The resource keeps being read while
-- the active phase hides it, and is shown directly once that phase ends. An entry with `by_slot`
-- shows the resource of the wielded slot, and none in other slots.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.hybrid = function (tracked, state, ctx)
    local found = ctx.found
    local remaining, duration = _active_timer(found, tracked.active, ctx.t)

    if remaining then
        _show_timer(state, PHASE_ACTIVE, BASE_ACTIVE, remaining, duration)

        return
    end

    local buff
    local by_slot = tracked.by_slot

    if by_slot then
        local inventory_component = ctx.inventory_component
        local index = inventory_component and by_slot[inventory_component.wielded_slot]

        buff = index and found[index]
    else
        buff = _first(found, tracked.buffs)
    end

    local count, cap

    if buff then
        count, cap = _count_and_cap(tracked, buff, ctx)
    end

    if count and count > 0 then
        _show_stacks(state, PHASE_BUILDING, count, cap)
    else
        _hide(state)
    end
end

--- `proc_cooldown`: a proc's active protection as a countdown, then, with the entry's cooldown
-- setting on, its cooldown as a countdown in the cooldown colour; hidden while ready.
-- The phase follows the proc's actual active start time, which the game sets when it procs; the
-- cooldown starts where the active time ends, as `ProcBuff` places it.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.proc_cooldown = function (tracked, state, ctx)
    local buff = _first(ctx.found, tracked.buffs)
    local active_start_time, active_duration, cooldown

    if buff then
        active_start_time, active_duration, cooldown = Sources.proc_timing(buff)
    end

    if not active_start_time then
        _hide(state)

        return
    end

    local t = ctx.t
    local active_end_t = active_start_time + active_duration

    if t < active_end_t then
        local remaining = active_end_t - t

        _show_timer(state, PHASE_ACTIVE, BASE_ACTIVE, remaining < active_duration and remaining or active_duration, active_duration)

        return
    end

    if cooldown and ctx.settings[tracked.cooldown_setting] and t < active_end_t + cooldown then
        local remaining = active_end_t + cooldown - t

        _show_timer(state, PHASE_COOLDOWN, BASE_COOLDOWN, remaining < cooldown and remaining or cooldown, cooldown)

        return
    end

    _hide(state)
end

--- `replenishment`: the remaining time until the next automatic Blitz charge, as a countdown in
-- the cooldown colour, while charges are missing and the game runs a timer; hidden at full
-- inventory. A running countdown whose timer is cleared while charges are still missing (the frame
-- between a restored charge and the next interval) stays shown empty for `REPLENISH_GAP_HOLD`.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.replenishment = function (tracked, state, ctx)
    local buff = _first(ctx.found, tracked.buffs)
    local missing = buff and Sources.missing_blitz_charges(ctx.ability_extension)

    if not missing or missing <= 0 then
        tracked.valid_t = nil

        _hide(state)

        return
    end

    local t = ctx.t
    local next_t, interval = Sources.replenishment(buff)

    if next_t then
        local remaining = next_t - t

        if remaining > interval then
            remaining = interval
        elseif remaining < 0 then
            remaining = 0
        end

        tracked.valid_t = t

        _show_timer(state, PHASE_REPLENISHING, BASE_COOLDOWN, remaining, interval)

        return
    end

    local valid_t = tracked.valid_t

    if state.visible and valid_t and t - valid_t <= REPLENISH_GAP_HOLD then
        state.fill = 0
        state.remaining = 0

        return
    end

    tracked.valid_t = nil

    _hide(state)
end

return Kinds
