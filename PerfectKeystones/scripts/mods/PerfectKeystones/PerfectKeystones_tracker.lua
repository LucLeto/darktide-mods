--- Keystone tracking of Perfect Keystones; decides what the inner and the outer ring show.
-- Binds to the local player's unit, keeps the instances of the buff templates its archetype's
-- keystones need, runs each selected and enabled keystone's presentation kind
-- (`trackers/PerfectKeystones_kinds.lua`) and hands the HUD element the presentation state of the
-- keystone that owns each ring.
--
-- The buff instances are found by one scan of the unit's buffs when the tracker binds to it, on
-- joining a mission or respawning. After that, while the HUD element forwards the game's
-- `event_player_buff_added` and `event_player_buff_removed` events (`set_event_driven`), they keep
-- the found instances current without scanning: the game fires them for every buff instance it
-- creates or removes, server corrections and unit teardown included, while stacks gained or lost
-- on an existing instance need no update. Only removing the found instance of a template that can
-- have several instances (one without `max_stacks`) scans again, once. These are game events the
-- vanilla buff HUD listens to as well, not hooks; without them the buffs are scanned every frame.
--
-- A keystone counts as selected while one of its `detect` buffs (the controller or passive buff
-- its talent installs) is present, so the build is read from what the game actually applied:
-- talents disabled by a game mode, forced base talents and talent changes are followed without
-- parsing the profile. Talent variants and upgrades are read from the observed buff instances.
--
-- Each ring has a fixed owner: the inner ring the first selected and enabled main keystone, the
-- thin outer ring Until Death (Zealot) or Lone Wolf (Arbitrator), in registry order; a second
-- keystone whose ring position setting is the inner ring swaps places with the main keystone. The
-- talent trees allow only one main keystone per character, so ownership never alternates between
-- frames, and one ring hiding never moves or takes over the other. Go Get 'Em! and Unleashed
-- Brutality have no ring; their buffs are only watched for the debug output.
--
-- Every keystone's state is derived from the game's current values each frame, with no timers of
-- its own, so tracking never pauses or restarts while a ring is hidden, disabled or off screen.
-- The tracker also notes each keystone's transitions: activation, a refreshed countdown, the switch
-- from active to cooldown, reaching the maximum and, with the `pulse_on_stack_change` setting, any
-- stack change set its `pulse` flag for that frame; with `debug_logging` on, phase
-- changes are written to the log.
--
-- Loaded by `PerfectKeystones.lua` through `mod:io_dofile` and stored as `mod._tracker`; the HUD
-- element calls `refresh` once per frame. Only game state is read, and all state lives in module
-- locals with preallocated tables, so nothing is allocated per frame.
-- module: PerfectKeystones_tracker
-- author: LucLeto
local mod = get_mod("PerfectKeystones")
local FixedFrame = require("scripts/utilities/fixed_frame")
local Registry = mod._registry
local Kinds = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/trackers/PerfectKeystones_kinds")

local pairs = pairs
local string_format = string.format
local tostring = tostring

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Seconds a countdown's remaining time must grow between frames to count as a refresh; its own
-- countdown only shrinks, by one fixed step at most.
local REFRESH_EPSILON = 0.25

--- Seconds without a refresh after which the next one notes no transitions, as when the HUD hid the
-- element: whatever changed meanwhile is shown as it is, without pulses.
local REFRESH_GAP = 0.5

--- Prefix of every debug line. Debug lines go through `mod:info`, which DMF writes to the game's
-- console log only, unless the player changed DMF's logging settings.
local DEBUG_PREFIX = "[Perfect Keystones] "

--- Game modes in which nothing is tracked: the Mourningstar and the prologue's hub, where talents
-- are active but nothing is fought. Missions, the Psykhanium and the training grounds are tracked.
local UNTRACKED_GAME_MODES = {
    hub = true,
    prologue_hub = true
}

local SLOT_INNER = Registry.SLOT_INNER
local SLOT_OUTER = Registry.SLOT_OUTER
local KIND_NONE = Registry.KIND_NONE
local PHASE_ACTIVE = Kinds.PHASE_ACTIVE
local PHASE_COOLDOWN = Kinds.PHASE_COOLDOWN
local hide_state = Kinds.hide

--- The tracker module table returned to `PerfectKeystones.lua`.
local Tracker = {}

-- ----------------------------------------------------------------------------
-- Compiled archetypes
-- ----------------------------------------------------------------------------

--- Tracking data by archetype name, compiled once from the registry. Fields:
-- `watch` watch index by buff template name;
-- `count` number of watch indices;
-- `tracked` compiled entries of the keystones with a ring, in registry order;
-- `static` compiled entries of the keystones without a ring (debug output only).
-- A compiled entry holds the registry fields the kinds read, its buff templates as watch indices
-- (`detect`, `buffs`, `active`, `by_slot`), its presentation `state` and its transition and debug
-- bookkeeping (`selected`, `last_visible`, `last_phase`, `last_stacks`, `last_remaining`), plus
-- `seen_buff`, `seen_t`, `valid_t` and the refill bookkeeping (`observed_count`, `gain_t`,
-- `loss_t`, `sweep_from`, `shown_held`, `full_t`, and `restore_interval`, resolved once) for the
-- kinds.
local ARCHETYPE_DATA = {}

--- Largest watch index of any archetype; the size of the `found` table.
local max_watch_count = 0

--- Returns a template list as watch indices, adding new templates to an archetype's watch map.
-- tab: data archetype tracking data
-- ?tab: names buff template names
-- treturn: ?tab watch indices in the same order
local function _watch_indices(data, names)
    if not names then
        return nil
    end

    local indices = {}

    for i = 1, #names do
        local name = names[i]
        local index = data.watch[name]

        if not index then
            index = data.count + 1
            data.count = index
            data.watch[name] = index
        end

        indices[i] = index
    end

    return indices
end

--- Compiles one registry entry for its archetype.
-- tab: data archetype tracking data
-- tab: entry registry entry
-- treturn: tab compiled entry
local function _compile_entry(data, entry)
    local compiled = {
        id = entry.id,
        talent = entry.talent,
        kind = Kinds[entry.kind],
        slot = entry.slot,
        cap = entry.cap,
        decay_style = entry.decay_style,
        cooldown_setting = entry.cooldown_setting,
        ring_setting = entry.ring_setting,
        visibility_setting = entry.visibility_setting,
        gate = entry.gate,
        gate_setting = entry.gate_setting,
        settle = entry.settle or 0,
        hide_at_zero = entry.hide_at_zero or false,
        animate_gains = entry.animate_gains or false,
        restore_progress = entry.restore_progress or false,
        restore_setting = entry.restore_setting,
        restore_interval = nil,
        detect = _watch_indices(data, entry.detect),
        buffs = _watch_indices(data, entry.buffs),
        active = _watch_indices(data, entry.active),
        by_slot = nil,
        state = Kinds.new_state(),
        selected = false,
        last_visible = false,
        last_phase = nil,
        last_stacks = nil,
        last_remaining = nil,
        seen_buff = nil,
        seen_t = 0,
        valid_t = nil,
        observed_count = nil,
        gain_t = nil,
        loss_t = nil,
        sweep_from = nil,
        shown_held = nil,
        full_t = nil
    }

    if entry.by_slot then
        compiled.by_slot = {}

        for slot_name, template_name in pairs(entry.by_slot) do
            compiled.by_slot[slot_name] = _watch_indices(data, { template_name })[1]
        end
    end

    return compiled
end

do
    local archetypes = Registry.ARCHETYPES
    local entries = Registry.ENTRIES

    for i = 1, #archetypes do
        local archetype = archetypes[i].name
        local data = {
            watch = {},
            count = 0,
            tracked = {},
            static = {}
        }

        for j = 1, #entries do
            local entry = entries[j]

            if entry.archetype == archetype then
                local list = entry.kind == KIND_NONE and data.static or data.tracked

                list[#list + 1] = _compile_entry(data, entry)
            end
        end

        if data.count > max_watch_count then
            max_watch_count = data.count
        end

        ARCHETYPE_DATA[archetype] = data
    end
end

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

--- Watched buff instances by watch index, the first instance of each template; refilled by every
-- scan and kept current by the buff events in between.
local found = {}

for i = 1, max_watch_count do
    found[i] = false
end

--- The bound player. `extensions` is the HUD's player extensions table it was bound to, which the
-- HUD replaces for every new player unit and clears while there is none; `unit` is that player
-- unit, whose buffs alone the events update; `data` is the archetype's tracking data, nil while
-- nothing can be tracked; `fresh` is set until the first refresh after a bind, which notes no
-- transitions; `last_t` is the fixed-step time of the latest refresh. `event_driven` is set while
-- the HUD element forwards the buff events, and `dirty` while `found` needs a scan: after a bind,
-- after the events were off, and after the found instance of a template that can have several
-- instances was removed.
local state = {
    extensions = nil,
    unit = nil,
    archetype = nil,
    data = nil,
    buff_extension = nil,
    fresh = true,
    last_t = nil,
    event_driven = false,
    dirty = true
}

--- Frame context passed to the kinds.
local ctx = {
    found = found,
    t = 0,
    settings = nil,
    inventory_component = nil,
    talent_resource_component = nil,
    character_state_component = nil,
    ability_extension = nil
}

--- Forgets the presentation state and bookkeeping of every compiled entry of an archetype.
-- ?tab: data archetype tracking data
local function _reset_entries(data)
    if not data then
        return
    end

    for list = 1, 2 do
        local compiled_entries = list == 1 and data.tracked or data.static

        for i = 1, #compiled_entries do
            local compiled = compiled_entries[i]

            hide_state(compiled.state)

            compiled.selected = false
            compiled.last_visible = false
            compiled.last_phase = nil
            compiled.last_stacks = nil
            compiled.last_remaining = nil
            compiled.seen_buff = nil
            compiled.seen_t = 0
            compiled.valid_t = nil
            compiled.observed_count = nil
            compiled.gain_t = nil
            compiled.loss_t = nil
            compiled.sweep_from = nil
            compiled.shown_held = nil
            compiled.full_t = nil
        end
    end
end

--- Stops tracking and forgets the bound player.
local function _reset_state()
    _reset_entries(state.data)

    state.extensions = nil
    state.unit = nil
    state.archetype = nil
    state.data = nil
    state.buff_extension = nil
    state.fresh = true
    state.last_t = nil
    state.dirty = true
    ctx.inventory_component = nil
    ctx.talent_resource_component = nil
    ctx.character_state_component = nil
    ctx.ability_extension = nil

    for i = 1, max_watch_count do
        found[i] = false
    end
end

--- Returns whether the current game mode is one of `UNTRACKED_GAME_MODES`.
-- treturn: bool
local function _in_untracked_game_mode()
    local state_managers = Managers.state
    local game_mode_manager = state_managers and state_managers.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager.game_mode_name and game_mode_manager:game_mode_name()

    return game_mode_name ~= nil and UNTRACKED_GAME_MODES[game_mode_name] == true
end

--- Binds to the HUD's player extensions of a new player unit.
-- Nothing is tracked when there is no unit, in a hub (`UNTRACKED_GAME_MODES`), when the archetype
-- has no keystone in the registry or when the buff extension cannot be read. The game mode only
-- changes along with the player unit, so it is checked here once. The inventory, talent resource
-- and character state components are optional; the keystones that need them hide without them,
-- and without the character state Feel No Pain shows no refill progress.
-- ?tab: player_extensions the HUD's player extensions, with `unit_data`, `buff` and `ability`
-- ?tab: player the HUD's player
local function _bind(player_extensions, player)
    _reset_state()

    state.extensions = player_extensions

    if not player_extensions then
        return
    end

    if _in_untracked_game_mode() then
        if mod._settings.debug_logging then
            mod:info(DEBUG_PREFIX .. "not tracking in the hub")
        end

        return
    end

    local archetype = player and player.archetype_name and player:archetype_name()
    local data = archetype and ARCHETYPE_DATA[archetype]
    local buff_extension = player_extensions.buff

    if not data or not buff_extension or not buff_extension.buffs then
        return
    end

    local unit_data_extension = player_extensions.unit_data
    local read_component = unit_data_extension and unit_data_extension.read_component

    if read_component then
        ctx.inventory_component = read_component(unit_data_extension, "inventory")
        ctx.talent_resource_component = read_component(unit_data_extension, "talent_resource")
        ctx.character_state_component = read_component(unit_data_extension, "character_state")
    end

    ctx.ability_extension = player_extensions.ability
    state.unit = player_extensions.unit
    state.archetype = archetype
    state.data = data
    state.buff_extension = buff_extension

    if mod._settings.debug_logging then
        mod:info(DEBUG_PREFIX .. "bound to a %s, watching %d buff templates (%s)", archetype, data.count, state.event_driven and "buff events" or "scanning every frame")
    end
end

-- ----------------------------------------------------------------------------
-- Frame update
-- ----------------------------------------------------------------------------

--- Collects the watched buffs into `found`, the first instance of each template.
-- tab: data archetype tracking data
local function _scan(data)
    local count = data.count

    for i = 1, count do
        found[i] = false
    end

    local buffs = state.buff_extension:buffs()
    local watch = data.watch

    for i = 1, #buffs do
        local buff = buffs[i]
        local index = watch[buff:template_name()]

        if index and not found[index] then
            found[index] = buff
        end
    end
end

--- Returns whether any of the given watch indices has a buff this frame.
-- ?tab: indices watch indices
-- treturn: bool
local function _any_found(indices)
    if indices then
        for i = 1, #indices do
            if found[indices[i]] then
                return true
            end
        end
    end

    return false
end

--- Writes a keystone's selection change to the log when debug output is enabled.
-- tab: compiled compiled entry
-- bool: selected whether the keystone is now selected
-- ?string: note extra text
local function _debug_selection(compiled, selected, note)
    mod:info(DEBUG_PREFIX .. "%s (%s) %s%s", compiled.id, tostring(compiled.talent), selected and "selected" or "no longer selected", note or "")
end

--- Writes a keystone's phase change to the log when debug output is enabled.
-- tab: compiled compiled entry
local function _debug_phase(compiled)
    local entry_state = compiled.state

    if not entry_state.visible then
        mod:info(DEBUG_PREFIX .. "%s: %s -> hidden", compiled.id, compiled.last_phase or "hidden")

        return
    end

    local detail

    if entry_state.stacks then
        detail = string_format("%d/%d", entry_state.stacks, entry_state.max_stacks)

        if entry_state.remaining then
            detail = string_format("%s, timer %.2f/%.2fs", detail, entry_state.remaining, entry_state.duration)
        end
    elseif entry_state.remaining then
        detail = string_format("%.2f/%.2fs", entry_state.remaining, entry_state.duration)
    else
        detail = "-"
    end

    mod:info(DEBUG_PREFIX .. "%s: %s -> %s (%s)", compiled.id, compiled.last_phase or "hidden", entry_state.phase, detail)
end

--- Notes a keystone's transitions after its kind ran: sets its `pulse` flag on activation, a
-- refreshed countdown, the switch from active to cooldown, reaching its maximum and, with the
-- `pulse_on_stack_change` setting, any stack change, and logs phase changes. The first refresh
-- after a bind notes nothing.
-- tab: compiled compiled entry
-- tab: settings `mod._settings`
local function _note_transitions(compiled, settings)
    local entry_state = compiled.state
    local phase = entry_state.phase
    local last_phase = compiled.last_phase
    local stacks = entry_state.stacks
    local last_stacks = compiled.last_stacks
    local pulse = false

    if entry_state.visible and not state.fresh then
        if phase ~= last_phase then
            pulse = phase == PHASE_ACTIVE or phase == PHASE_COOLDOWN and last_phase == PHASE_ACTIVE
        elseif phase == PHASE_ACTIVE and compiled.last_remaining and entry_state.remaining > compiled.last_remaining + REFRESH_EPSILON then
            pulse = true
        end

        if stacks and last_stacks ~= stacks then
            if stacks >= entry_state.max_stacks and (last_stacks or 0) < stacks then
                pulse = true
            elseif last_stacks and settings.pulse_on_stack_change then
                pulse = true
            end
        end
    end

    entry_state.pulse = pulse

    if settings.debug_logging and (entry_state.visible ~= compiled.last_visible or phase ~= last_phase) then
        _debug_phase(compiled)
    end

    compiled.last_visible = entry_state.visible
    compiled.last_phase = phase
    compiled.last_stacks = stacks
    compiled.last_remaining = entry_state.remaining
end

--- Updates every keystone of the bound player and returns the presentation state of each ring.
-- Called by the HUD element once per frame. A new player extensions table binds to the new unit
-- first. The buffs are scanned when `found` is dirty, or every frame without the buff events; with
-- every keystone of the archetype disabled, no buff is scanned.
-- ?tab: player_extensions the HUD's player extensions, nil while there is no player unit
-- ?tab: player the HUD's player
-- treturn: ?tab presentation state of the inner ring, nil when it is hidden
-- treturn: ?tab presentation state of the outer ring, nil when it is hidden
Tracker.refresh = function (player_extensions, player)
    if player_extensions ~= state.extensions then
        _bind(player_extensions, player)
    end

    local data = state.data

    if not data then
        return nil, nil
    end

    local settings = mod._settings
    local tracked = data.tracked
    local any_enabled = false

    for i = 1, #tracked do
        if settings[tracked[i].id] then
            any_enabled = true

            break
        end
    end

    if not any_enabled then
        if not state.fresh then
            _reset_entries(data)

            state.fresh = true
        end

        return nil, nil
    end

    local t = FixedFrame.get_latest_fixed_time()
    local last_t = state.last_t

    if last_t and (t < last_t or t - last_t > REFRESH_GAP) then
        state.fresh = true
    end

    state.last_t = t
    ctx.t = t
    ctx.settings = settings

    if state.dirty or not state.event_driven then
        state.dirty = false

        _scan(data)
    end

    local debug_logging = settings.debug_logging
    local inner, outer

    for i = 1, #tracked do
        local compiled = tracked[i]
        local selected = _any_found(compiled.detect)
        local applicable = selected and settings[compiled.id]

        if debug_logging and selected ~= compiled.selected then
            _debug_selection(compiled, selected)
        end

        compiled.selected = selected

        if applicable then
            compiled.kind(compiled, compiled.state, ctx)
        else
            hide_state(compiled.state)
        end

        _note_transitions(compiled, settings)

        if applicable then
            if compiled.slot == SLOT_INNER then
                inner = inner or compiled
            elseif compiled.slot == SLOT_OUTER then
                outer = outer or compiled
            end
        end
    end

    if debug_logging then
        local static = data.static

        for i = 1, #static do
            local compiled = static[i]
            local selected = _any_found(compiled.detect)

            if selected ~= compiled.selected then
                compiled.selected = selected

                _debug_selection(compiled, selected, ", no ring by design")
            end
        end
    end

    state.fresh = false

    -- A second keystone set to the inner ring swaps places with the main keystone.
    local ring_setting = outer and outer.ring_setting

    if ring_setting and settings[ring_setting] == SLOT_INNER then
        inner, outer = outer, inner
    end

    local inner_state = inner and inner.state
    local outer_state = outer and outer.state

    return inner_state and inner_state.visible and inner_state or nil, outer_state and outer_state.visible and outer_state or nil
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

--- Stops tracking and forgets the bound player; used on game state changes and when the mod is
-- enabled or disabled. The next refresh binds again.
Tracker.reset = function ()
    _reset_state()
end

--- Sets whether the HUD element forwards the buff events. Either way the next refresh scans once:
-- when the events start, any missed while they were off are caught up; when they stop, refresh
-- scans every frame again.
-- bool: event_driven whether `on_buff_added` and `on_buff_removed` are called for every buff event
Tracker.set_event_driven = function (event_driven)
    state.event_driven = event_driven and true or false
    state.dirty = true
end

--- Returns whether a buff instance belongs to the bound player unit and has a watched template.
-- tab: buff_instance buff instance from a buff event
-- treturn: ?int its watch index
local function _watch_index(buff_instance)
    local data = state.data

    if not data or not buff_instance.template_context or not buff_instance.template_name then
        return nil
    end

    local template_context = buff_instance:template_context()

    if not template_context or template_context.unit ~= state.unit then
        return nil
    end

    return data.watch[buff_instance:template_name()]
end

--- Handles the game's `event_player_buff_added` for a new buff instance of any player unit; the
-- HUD element forwards it. A watched template's instance of the bound unit is kept when its
-- template has no found instance yet, as a scan keeps the first one.
-- tab: buff_instance the new buff instance
Tracker.on_buff_added = function (buff_instance)
    local index = _watch_index(buff_instance)

    if index and not found[index] then
        found[index] = buff_instance
    end
end

--- Handles the game's `event_player_buff_removed` for a buff instance of any player unit that is
-- about to be removed; the HUD element forwards it. The found instance of a watched template is
-- forgotten; when its template can have several instances, the next refresh scans for another one.
-- tab: buff_instance the removed buff instance
Tracker.on_buff_removed = function (buff_instance)
    local index = _watch_index(buff_instance)

    if index and found[index] == buff_instance then
        found[index] = false

        local template = buff_instance.template and buff_instance:template()

        if not template or not template.max_stacks then
            state.dirty = true
        end
    end
end

return Tracker
