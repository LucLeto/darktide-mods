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
-- colour), `HIGHLIGHT_SHARED` (the lit segments turn to the expiring colour one after another,
-- so the whole filled area has turned as the shared timer ends) or `HIGHLIGHT_REFILL` (the lit
-- segments from `highlight_from` on are a stack still being restored or sweeping in, drawn in the
-- cooldown colour);
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
local PlayerUnitStatus = require("scripts/utilities/attack/player_unit_status")
local Sources = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/trackers/PerfectKeystones_sources")
local Registry = mod._registry

local count_of = Sources.count
local cap_of = Sources.cap
local is_positive = Sources.is_positive
local timer_of = Sources.timer

--- Wielded slot of the Blitz, for Empowered Psionics' gate.
local SLOT_GRENADE_ABILITY = "slot_grenade_ability"

--- Seconds a running Lone Wolf countdown may lose its timer while charges are still missing,
-- shown empty, before the ring hides. The game clears the timer on the fixed frame that restores
-- a charge and sets the next interval on the following one.
local REPLENISH_GAP_HOLD = 0.1

--- Seconds newly gained stacks of an `animate_gains` entry take to sweep in.
local GAIN_SWEEP_DURATION = 0.3

--- Seconds the full ring of an `animate_gains` entry stays visible after its last stack returned,
-- before the below-maximum visibility hides it.
local FULL_HOLD_DURATION = 1

local GATE_BLITZ_WIELDED = Registry.GATE_BLITZ_WIELDED
local VISIBILITY_ALWAYS = Registry.VISIBILITY_ALWAYS
local DECAY_PROGRESSIVE = Registry.DECAY_PROGRESSIVE
local RESTORE_CHILD_TEMPLATE = Registry.RESTORE_CHILD_TEMPLATE

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
local HIGHLIGHT_REFILL = "refill"

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
Kinds.HIGHLIGHT_REFILL = HIGHLIGHT_REFILL

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

--- Forgets an `animate_gains` entry's observed count history, as for a new stack buff instance.
-- tab: tracked compiled tracking entry
local function _forget_refill(tracked)
    tracked.observed_count = nil
    tracked.gain_t = nil
    tracked.loss_t = nil
    tracked.sweep_from = nil
    tracked.shown_held = nil
    tracked.full_t = nil
end

--- Notes an `animate_gains` entry's observed count changes: a gain starts a sweep from the stacks
-- shown so far, and reaching the maximum from below starts the full hold; a loss ends both. Called
-- every frame the count can be read, shown or not; the first count after an instance change is
-- only recorded.
-- tab: tracked compiled tracking entry
-- int: count held stacks
-- int: cap effective maximum
-- number: t latest fixed-step time
local function _observe_count(tracked, count, cap, t)
    local observed = tracked.observed_count

    if observed and count ~= observed then
        if count > observed then
            local from = tracked.shown_held

            if not from or from > observed then
                from = observed
            end

            tracked.gain_t = t
            tracked.sweep_from = from

            if count >= cap and observed < cap then
                tracked.full_t = t
            end
        else
            tracked.loss_t = t
            tracked.sweep_from = nil
            tracked.shown_held = nil
            tracked.full_t = nil
        end
    end

    tracked.observed_count = count
end

--- Returns an entry's restore interval: the parent buff template's `restore_child_duration`, or
-- the talent setting named by `restore_setting`, resolved once.
-- tab: tracked compiled tracking entry
-- tab: buff stack buff instance
-- treturn: ?number interval in seconds
local function _restore_interval(tracked, buff)
    if tracked.restore_progress == RESTORE_CHILD_TEMPLATE then
        local template = buff.template and buff:template()

        return template and template.restore_child_duration
    end

    local interval = tracked.restore_interval

    if interval == nil then
        interval = tracked.restore_setting and Sources.talent_setting(tracked.restore_setting) or false
        tracked.restore_interval = interval
    end

    return interval or nil
end

--- Returns the restore progress of an entry's next stack.
-- The game restores one stack once the restore interval has passed since the last stack change:
-- Feel No Pain's parent buff counts from its last removed and its last added child stack and keeps
-- restarting while the player is knocked down; Focus Target! counts from its last gained stack
-- and from a tag or kill that set its stacks. The timer is not sent to clients, so it is rebuilt
-- here from the losses and gains this client observed, which arrive with the same delay as the
-- restored stack itself. Until a change has been observed, the timer is unknown and no progress is
-- reported; for a child template entry, the same holds without the character state.
-- tab: tracked compiled tracking entry
-- tab: buff stack buff instance
-- tab: ctx frame context
-- treturn: number progress from 0 to 1 toward the next restored stack
-- treturn: ?number seconds until that stack, nil without progress
-- treturn: ?number restore interval in seconds, nil without progress
local function _restore_progress(tracked, buff, ctx)
    local interval = _restore_interval(tracked, buff)

    if not is_positive(interval) then
        return 0, nil, nil
    end

    local t = ctx.t

    if tracked.restore_progress == RESTORE_CHILD_TEMPLATE then
        local character_state_component = ctx.character_state_component

        if not character_state_component then
            return 0, nil, nil
        end

        if PlayerUnitStatus.is_knocked_down(character_state_component) then
            tracked.loss_t = t

            return 0, nil, nil
        end
    end

    local since = tracked.loss_t
    local gain_t = tracked.gain_t

    if gain_t and (not since or gain_t > since) then
        since = gain_t
    end

    if not since then
        return 0, nil, nil
    end

    local elapsed = t - since

    if elapsed <= 0 then
        return 0, nil, nil
    end

    if elapsed >= interval then
        return 1, 0, interval
    end

    return elapsed / interval, interval - elapsed, interval
end

--- Applies an `animate_gains` entry's refill presentation to its shown stacks: newly gained stacks
-- sweep in over `GAIN_SWEEP_DURATION`. With `restore_progress`, the share of the next stack also
-- fills during its restore interval; that share, and a gained share the sweep has not reached
-- yet, are drawn with `HIGHLIGHT_REFILL`, and the time label counts down to the next stack.
-- Without it, the gained segments themselves appear one after another.
-- tab: tracked compiled tracking entry
-- tab: state presentation state, already showing `count` of `cap`
-- tab: ctx frame context
-- tab: buff stack buff instance
-- int: count held stacks
-- int: cap effective maximum
local function _show_refill(tracked, state, ctx, buff, count, cap)
    local held = count
    local sweep_from = tracked.sweep_from

    if sweep_from then
        local progress = (ctx.t - tracked.gain_t) / GAIN_SWEEP_DURATION

        if progress < 1 then
            held = sweep_from + (count - sweep_from) * progress
        else
            tracked.sweep_from = nil
        end
    end

    tracked.shown_held = held

    local held_fill = held / cap

    if not tracked.restore_progress then
        state.fill = held_fill

        return
    end

    local refill, remaining, interval = 0, nil, nil

    if count < cap then
        refill, remaining, interval = _restore_progress(tracked, buff, ctx)
    end

    local fill = (count + refill) / cap

    state.fill = fill

    if fill > held_fill then
        state.highlight = HIGHLIGHT_REFILL
        state.highlight_from = held_fill
    end

    if remaining then
        state.remaining = remaining
        state.duration = interval
    end
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

--- `stack_shared`: stacks that share one refreshable timer. The held stacks stay filled; the filled
-- segments turn to the expiring colour one after another as the timer runs down, so the whole
-- filled area has turned when the stacks expire, and a refresh turns them back.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.stack_shared = function (tracked, state, ctx)
    _timed_stacks(tracked, state, ctx, HIGHLIGHT_SHARED)
end

--- Notes the stack buff instance an entry reads this frame; a different instance, or none, restarts
-- its settle time and forgets its observed count history.
-- tab: tracked compiled tracking entry
-- ?tab: buff stack buff instance
-- number: t latest fixed-step time
local function _note_stack_buff(tracked, buff, t)
    if buff ~= tracked.seen_buff then
        tracked.seen_buff = buff
        tracked.seen_t = t

        _forget_refill(tracked)
    end
end

--- Shows a held count by the entry's visibility rules, or hides the ring.
-- Without a visibility setting, the count is shown while above zero. With one, it is shown below
-- the maximum (zero included) or always; a `hide_at_zero` entry hides at zero in both modes. A
-- deficit is held back for the entry's settle time after its stack buff appears. An
-- `animate_gains` entry sweeps gained stacks in and, below the maximum, keeps its full ring for
-- `FULL_HOLD_DURATION` after the last stack returned; with `restore_progress` it also fills the
-- next stack's share over its restore interval (see `_show_refill`). An entry with a gate setting
-- additionally needs its gate condition when that setting is on.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
-- tab: buff stack buff instance
-- int: count held stacks
-- int: cap effective maximum
-- string: phase `PHASE_HELD` or `PHASE_BUILDING`
local function _show_held(tracked, state, ctx, buff, count, cap, phase)
    local t = ctx.t
    local animate_gains = tracked.animate_gains

    if animate_gains then
        _observe_count(tracked, count, cap, t)
    end

    local settings = ctx.settings
    local visibility_setting = tracked.visibility_setting
    local visible

    if count <= 0 and (tracked.hide_at_zero or not visibility_setting) then
        visible = false
    elseif not visibility_setting or settings[visibility_setting] == VISIBILITY_ALWAYS then
        visible = true
    elseif count < cap then
        visible = t - tracked.seen_t >= tracked.settle
    else
        -- Starting stacks arriving during the settle time get no full hold either.
        local full_t = tracked.full_t

        visible = full_t ~= nil and t - full_t < FULL_HOLD_DURATION and full_t - tracked.seen_t >= tracked.settle
    end

    if visible and tracked.gate == GATE_BLITZ_WIELDED and settings[tracked.gate_setting] then
        local inventory_component = ctx.inventory_component

        visible = inventory_component ~= nil and inventory_component.wielded_slot == SLOT_GRENADE_ABILITY
    end

    if not visible then
        _hide(state)

        return
    end

    _show_stacks(state, phase, count, cap)

    if animate_gains then
        _show_refill(tracked, state, ctx, buff, count, cap)
    end
end

--- `stack_discrete`: held stacks in whole steps, without a timer, shown by the entry's visibility
-- rules (see `_show_held`). A missing buff or maximum is not a zero count and hides the ring.
-- tab: tracked compiled tracking entry
-- tab: state presentation state
-- tab: ctx frame context
Kinds.stack_discrete = function (tracked, state, ctx)
    local buff = _first(ctx.found, tracked.buffs)

    _note_stack_buff(tracked, buff, ctx.t)

    local count, cap

    if buff then
        count, cap = _count_and_cap(tracked, buff, ctx)
    end

    if not count then
        _hide(state)

        return
    end

    _show_held(tracked, state, ctx, buff, count, cap, PHASE_HELD)
end

--- `hybrid`: an actual timed active buff takes priority and shows its remaining time; otherwise
-- the held resource is shown in whole steps by the entry's visibility rules (see `_show_held`),
-- above zero without a visibility setting. The resource keeps being read while the active phase
-- hides it, and is shown directly once that phase ends. An entry with `by_slot` shows the resource
-- of the wielded slot, and none in other slots.
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

        buff = index and found[index] or nil
    else
        buff = _first(found, tracked.buffs)
    end

    _note_stack_buff(tracked, buff, ctx.t)

    local count, cap

    if buff then
        count, cap = _count_and_cap(tracked, buff, ctx)
    end

    if not count then
        _hide(state)

        return
    end

    _show_held(tracked, state, ctx, buff, count, cap, PHASE_BUILDING)
end

--- `proc_cooldown`: a proc's active protection as a countdown, then, with the entry's cooldown
-- setting on, its cooldown as a countdown in the cooldown colour; hidden while ready.
-- The phase follows the proc's actual active start time, which the game sets when it procs; the
-- cooldown starts where the active time ends, as `ProcBuff` places it. The entry's `active` buffs
-- are further timed protections, such as the shorter one Until Death's Zealous Pilgrim modifier
-- grants on combat ability use without starting the proc's cooldown: while any protection runs,
-- the one with the most time left is shown, ahead of the cooldown, which resumes afterwards.
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
    local remaining, duration = _active_timer(ctx.found, tracked.active, t)

    -- An expired protection lingers on a client until the server removes it; it no longer counts.
    if remaining and remaining <= 0 then
        remaining = nil
    end

    if t < active_end_t then
        local proc_remaining = active_end_t - t

        if proc_remaining > active_duration then
            proc_remaining = active_duration
        end

        if not remaining or proc_remaining >= remaining then
            remaining = proc_remaining
            duration = active_duration
        end
    end

    if remaining then
        _show_timer(state, PHASE_ACTIVE, BASE_ACTIVE, remaining, duration)

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
