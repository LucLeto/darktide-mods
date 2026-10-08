--- Veteran (Born Leader) pulse tracking: discrete restores and the at-full regeneration model.
-- Born Leader shares 20 % of the wanted amount of every replenish. The HUD element measures what
-- fills the replicated bar, which misses the part clamped at the cap and everything at full.
-- This module infers that part from client-side events: kills in local attack reports (melee,
-- Out for Blood, Exhilarating Takedown, Confirmed Kill and Target Down!), weapon blessing procs,
-- Voice of Command and Infiltrate, and On Your Toes weapon swaps. It also models when the
-- continuous at-full sources run (Executioner's Stance, Catch a Breath and Confirmed Kill's
-- regeneration), because their server-side buffs are not reliably visible to the client.
--
-- The HUD element drains three queues every sample: `pending_excess`, the clamped excess of
-- discrete restores; `pending_burst_share`, the share each ally gets from a shout; and
-- `pending_burst_overflow`, the shout's clamped excess. All are in Toughness points.
--
-- Explicit module loaded by `OverflowMeter.lua` and stored as `mod._pulses_veteran`.
-- `on_proc_active` and `on_attack_result` are called from the shared hooks in
-- `OverflowMeter.lua`; the combat ability, weapon swap and smart tag hooks are registered here.
-- `set_context` enables it for the local player's unit, and it ignores every event while
-- disabled.
-- module: OverflowMeter_pulses_veteran
-- alias: Pulses
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local Sources = mod._sources_veteran

local ScriptUnit = ScriptUnit
local Managers = Managers
local math_min = math.min

local ATTACK_RESULT_DIED = AttackSettings.attack_results.died
local ATTACK_TYPE_MELEE = AttackSettings.attack_types.melee
local ATTACK_TYPE_RANGED = AttackSettings.attack_types.ranged

--- Pulse state.
-- Besides the queues and the local Veteran's unit, extensions and talent flags, it holds the
-- modelled timers: when the stance ends, the last melee hit taken (Catch a Breath), when
-- Confirmed Kill's regeneration ends, the last On Your Toes restore per side, and the enemy last
-- tagged for Focus Target with the end of its 25 s window.
local Pulses = {
    enabled = false,
    pending_excess = 0,
    pending_burst_share = 0,
    pending_burst_overflow = 0,
    unit = nil,
    buff_extension = nil,
    toughness_extension = nil,
    unit_data_extension = nil,
    disabled_component = nil,
    has_out_for_blood = false,
    has_confirmed_kill = false,
    has_exhilarating = false,
    has_catch_a_breath = false,
    has_executioners_stance = false,
    has_increased_stance_duration = false,
    has_stance_refresh = false,
    has_on_your_toes = false,
    has_target_down = false,
    stance_active_until = 0,
    catch_a_breath_last_hit_t = 0,
    confirmed_kill_regen_until = 0,
    last_ranged_wield_t = 0,
    last_melee_wield_t = 0,
    focus_target_unit = nil,
    focus_target_until = 0,
}

-- ----------------------------------------------------------------------------
-- Context and queues
-- ----------------------------------------------------------------------------

--- Returns whether the build has the talent that grants a buff template.
-- ?tab: talent_extension local player's talent extension
-- string: buff_template_name buff template the talent grants
-- treturn: bool
local function _has_talent_buff(talent_extension, buff_template_name)
    if not talent_extension or not talent_extension.buff_template_tier then
        return false
    end

    local tier = talent_extension:buff_template_tier(buff_template_name)

    return tier ~= nil and tier ~= 0
end

--- Returns whether the build has a talent special rule.
-- ?tab: talent_extension local player's talent extension
-- string: rule_name special rule name
-- treturn: bool
local function _has_special_rule(talent_extension, rule_name)
    if not talent_extension or not talent_extension.has_special_rule then
        return false
    end

    return talent_extension:has_special_rule(rule_name) and true or false
end

--- Enables the module for the local player's unit, caches its extensions and talent flags and
-- restarts every timer.
-- param: unit local player unit
-- tab: buff_extension its buff extension
-- tab: toughness_extension its toughness extension
-- ?tab: talent_extension its talent extension
Pulses.set_context = function(unit, buff_extension, toughness_extension, talent_extension)
    Pulses.enabled = true
    Pulses.unit = unit
    Pulses.buff_extension = buff_extension
    Pulses.toughness_extension = toughness_extension

    local unit_data_extension = ScriptUnit.has_extension(unit, "unit_data_system")

    Pulses.unit_data_extension = unit_data_extension
    Pulses.disabled_component = unit_data_extension and unit_data_extension.read_component and unit_data_extension:read_component("disabled_character_state")
    Pulses.has_out_for_blood = _has_talent_buff(talent_extension, Sources.out_for_blood_talent_buff_name)
    Pulses.has_confirmed_kill = _has_talent_buff(talent_extension, Sources.confirmed_kill_talent_buff_name)
    Pulses.has_exhilarating = _has_talent_buff(talent_extension, Sources.exhilarating_talent_buff_name)
    Pulses.has_catch_a_breath = _has_talent_buff(talent_extension, Sources.catch_a_breath_talent_buff_name)
    Pulses.has_executioners_stance = _has_talent_buff(talent_extension, Sources.stance_augment_buff_name)
    Pulses.has_increased_stance_duration = _has_special_rule(talent_extension, Sources.stance_increased_duration_rule)
    Pulses.has_stance_refresh = _has_special_rule(talent_extension, Sources.stance_refresh_rule)
    Pulses.has_on_your_toes = _has_special_rule(talent_extension, Sources.on_your_toes_talent_rule)
    Pulses.has_target_down = _has_special_rule(talent_extension, Sources.target_down_talent_rule)
    Pulses.stance_active_until = 0
    Pulses.catch_a_breath_last_hit_t = 0
    Pulses.confirmed_kill_regen_until = 0
    Pulses.last_ranged_wield_t = 0
    Pulses.last_melee_wield_t = 0
    Pulses.focus_target_unit = nil
    Pulses.focus_target_until = 0
end

--- Disables the module and clears every queue, cached reference, talent flag and timer.
Pulses.disable = function()
    Pulses.enabled = false
    Pulses.pending_excess = 0
    Pulses.pending_burst_share = 0
    Pulses.pending_burst_overflow = 0
    Pulses.unit = nil
    Pulses.buff_extension = nil
    Pulses.toughness_extension = nil
    Pulses.unit_data_extension = nil
    Pulses.disabled_component = nil
    Pulses.has_out_for_blood = false
    Pulses.has_confirmed_kill = false
    Pulses.has_exhilarating = false
    Pulses.has_catch_a_breath = false
    Pulses.has_executioners_stance = false
    Pulses.has_increased_stance_duration = false
    Pulses.has_stance_refresh = false
    Pulses.has_on_your_toes = false
    Pulses.has_target_down = false
    Pulses.stance_active_until = 0
    Pulses.catch_a_breath_last_hit_t = 0
    Pulses.confirmed_kill_regen_until = 0
    Pulses.last_ranged_wield_t = 0
    Pulses.last_melee_wield_t = 0
    Pulses.focus_target_unit = nil
    Pulses.focus_target_until = 0
end

--- Returns and clears the clamped excess of discrete restores.
-- treturn: number Toughness points
Pulses.consume = function()
    local pending_excess = Pulses.pending_excess

    Pulses.pending_excess = 0

    return pending_excess
end

--- Returns and clears the share each ally gets from the shouts since the last sample.
-- treturn: number Toughness points per ally
Pulses.consume_burst = function()
    local pending_burst_share = Pulses.pending_burst_share

    Pulses.pending_burst_share = 0

    return pending_burst_share
end

--- Returns and clears the clamped excess of the shouts since the last sample.
-- treturn: number Toughness points
Pulses.consume_burst_overflow = function()
    local pending_burst_overflow = Pulses.pending_burst_overflow

    Pulses.pending_burst_overflow = 0

    return pending_burst_overflow
end

-- ----------------------------------------------------------------------------
-- Pulse recording
-- ----------------------------------------------------------------------------

--- Adds the part of a wanted restore that exceeds the missing Toughness to the excess queue.
-- ?number: wanted wanted restore in Toughness points; ignored unless positive
local function _accumulate_wanted(wanted)
    if not wanted or wanted <= 0 then
        return
    end

    local toughness_extension = Pulses.toughness_extension

    if not toughness_extension then
        return
    end

    local headroom = toughness_extension:toughness_damage()
    local excess = wanted - headroom

    if excess > 0 then
        Pulses.pending_excess = Pulses.pending_excess + excess
    end
end

--- Records a restore given as a fraction of maximum Toughness.
-- ?number: fraction restore fraction; ignored unless positive
-- ?bool: apply_replenish_stat_buffs scale by `toughness_replenish_modifier` and
-- `toughness_replenish_multiplier`, as the game does for restores that use stat buffs
local function _add_pulse(fraction, apply_replenish_stat_buffs)
    if not fraction or fraction <= 0 then
        return
    end

    local toughness_extension = Pulses.toughness_extension

    if not toughness_extension then
        return
    end

    local wanted = fraction * toughness_extension:max_toughness()

    if apply_replenish_stat_buffs then
        local buff_extension = Pulses.buff_extension
        local stat_buffs = buff_extension and buff_extension.stat_buffs and buff_extension:stat_buffs()

        if stat_buffs then
            wanted = wanted * (stat_buffs.toughness_replenish_modifier or 1) * (stat_buffs.toughness_replenish_multiplier or 1)
        end
    end

    _accumulate_wanted(wanted)
end

--- Records the base melee-kill restore, scaled the way the game's toughness template does.
-- The melee replenish bonus adds to the replenish modifier, and the replenish multiplier applies
-- on top.
local function _add_melee_kill_pulse()
    local toughness_extension = Pulses.toughness_extension

    if not toughness_extension then
        return
    end

    local fraction = Sources.melee_kill_base_fraction
    local buff_extension = Pulses.buff_extension
    local stat_buffs = buff_extension and buff_extension.stat_buffs and buff_extension:stat_buffs()

    if stat_buffs then
        fraction = fraction * ((stat_buffs.toughness_melee_replenish or 1) + (stat_buffs.toughness_replenish_modifier or 1) - 1) * (stat_buffs.toughness_replenish_multiplier or 1)
    end

    if fraction > 0 then
        _accumulate_wanted(fraction * toughness_extension:max_toughness())
    end
end

--- Records a Voice of Command or Infiltrate use.
-- Both restore the Veteran's whole maximum Toughness on the server, so Born Leader shares 20 % of
-- maximum Toughness with each ally even at full; whatever the bar could not take is overflow.
local function _add_burst()
    local toughness_extension = Pulses.toughness_extension

    if not toughness_extension then
        return
    end

    local max_toughness = toughness_extension:max_toughness()

    if max_toughness > 0 then
        Pulses.pending_burst_share = Pulses.pending_burst_share + Sources.share_fraction * max_toughness

        local excess = max_toughness - toughness_extension:toughness_damage()

        if excess > 0 then
            Pulses.pending_burst_overflow = Pulses.pending_burst_overflow + excess
        end
    end
end

-- ----------------------------------------------------------------------------
-- Continuous source model
-- ----------------------------------------------------------------------------

--- Returns the current gameplay time, or 0 before the gameplay timer exists.
-- treturn: number
local function _now()
    local time_manager = Managers.time

    if time_manager and time_manager.has_timer and time_manager:has_timer("gameplay") then
        return time_manager:time("gameplay")
    end

    return 0
end

--- Returns whether the Veteran is disabled (for example netted or pounced), which pauses the
-- modelled regeneration as it does in game.
-- treturn: bool
local function _is_disabled()
    local component = Pulses.disabled_component

    return component and component.is_disabled or false
end

--- Returns the stance duration in seconds, longer with the special rule that extends it.
-- treturn: number
local function _stance_duration()
    return Pulses.has_increased_stance_duration and Sources.stance_duration_increased or Sources.stance_duration
end

--- Returns the summed rate of the continuous sources currently modelled as running.
-- Executioner's Stance runs until its window ends, Catch a Breath once no melee hit was taken for
-- its cooldown, and Confirmed Kill's regeneration until its window ends. The HUD element uses it
-- only at full Toughness, where the bar cannot show these sources.
-- treturn: number fraction of maximum Toughness per second, before stat buffs
Pulses.active_continuous_fraction = function()
    if not Pulses.enabled or _is_disabled() then
        return 0
    end

    local now = _now()
    local total = 0

    if Pulses.has_executioners_stance and now < Pulses.stance_active_until then
        total = total + Sources.stance_regen_rate
    end

    if Pulses.has_catch_a_breath and now > Pulses.catch_a_breath_last_hit_t + Sources.catch_a_breath_cooldown then
        total = total + Sources.catch_a_breath_rate
    end

    if Pulses.has_confirmed_kill and now < Pulses.confirmed_kill_regen_until then
        total = total + Sources.confirmed_kill_regen_rate
    end

    return total
end

-- ----------------------------------------------------------------------------
-- Keystone helpers
-- ----------------------------------------------------------------------------

--- Returns the Weapons Specialist stacks from the replicated talent resource.
-- treturn: number
local function _weapon_switch_stacks()
    local unit_data_extension = Pulses.unit_data_extension

    if not unit_data_extension or not unit_data_extension.read_component then
        return 0
    end

    local component = unit_data_extension:read_component("talent_resource")

    return component and component.current_resource or 0
end

--- Returns the Focus Target stacks from the replicated talent resource, capped at the talent maximum.
-- treturn: number
local function _focus_target_stacks()
    local unit_data_extension = Pulses.unit_data_extension

    if not unit_data_extension or not unit_data_extension.read_component then
        return 0
    end

    local component = unit_data_extension:read_component("talent_resource")
    local stacks = component and component.current_resource or 0

    if stacks > Sources.target_down_max_stacks then
        stacks = Sources.target_down_max_stacks
    end

    return stacks
end

--- Returns whether an enemy is the local player's Focus Target.
-- True for the enemy the player last tagged within its 25 s window, even after a teammate
-- replaced the tag (the server keeps following it), and otherwise for any enemy whose current tag
-- the local player owns.
-- param: attacked_unit enemy unit
-- treturn: bool
local function _tagged_by_local_player(attacked_unit)
    if attacked_unit == Pulses.focus_target_unit and _now() < Pulses.focus_target_until then
        return true
    end

    local state_managers = Managers.state
    local extension_manager = state_managers and state_managers.extension
    local smart_tag_system = extension_manager and extension_manager.system and extension_manager:system("smart_tag_system")

    if not smart_tag_system or not smart_tag_system.unit_tag then
        return false
    end

    local tag = smart_tag_system:unit_tag(attacked_unit)

    return tag ~= nil and tag.tagger_unit ~= nil and tag:tagger_unit() == Pulses.unit
end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

--- Records a weapon blessing proc of the local player.
-- The fixed percentage comes from the blessing tier's override data, or else the template.
-- Continuous fire multiplies it by the fire step, at most 5. Blessing restores ignore Toughness
-- stat buffs.
-- tab: buff_extension buff extension whose proc became active
-- ?int: index index of the buff instance
Pulses.on_proc_active = function(buff_extension, index)
    if not Pulses.enabled or buff_extension ~= Pulses.buff_extension then
        return
    end

    local buff_instance = index and buff_extension._buffs_by_index[index]

    if not buff_instance or not buff_instance.template_name then
        return
    end

    local template_name = buff_instance:template_name()

    if not Sources.weapon_toughness_proc_templates[template_name] then
        return
    end

    local template_context = buff_instance.template_context and buff_instance:template_context()
    local override_data = template_context and template_context.template_override_data
    local template = buff_instance.template and buff_instance:template()
    local fixed_percentage = override_data and override_data.toughness_fixed_percentage or template and template.toughness_fixed_percentage

    if not fixed_percentage then
        return
    end

    if Sources.continuous_fire_templates[template_name] then
        local fire_step = buff_instance.visual_stack_count and buff_instance:visual_stack_count() or 1

        if fire_step < 1 then
            fire_step = 1
        end

        fixed_percentage = fixed_percentage * math_min(fire_step, Sources.max_continuous_fire_steps)
    end

    _add_pulse(fixed_percentage, false)
end

--- Records what one attack report means for the Veteran's restores and timers.
-- A melee attack on the Veteran restarts Catch a Breath's cooldown. On the Veteran's own kills it
-- records the base melee restore, Out for Blood (any kill), Exhilarating Takedown (ranged
-- weakspot kills), Confirmed Kill (Elite and Specialist kills, which also open its regeneration
-- window), the stance refresh on highlighted kills, and Target Down! for the Focus Target, 5 %
-- per Focus Target stack without stat buffs. The arguments are those of
-- `AttackReportManager.add_attack_result`.
-- ?tab: damage_profile damage profile of the attack
-- param: attacked_unit unit that was hit
-- param: attacking_unit unit that attacked
-- bool: hit_weakspot whether a weakspot was hit
-- string: attack_result `died` for a kill
-- string: attack_type such as `melee` or `ranged`
Pulses.on_attack_result = function(damage_profile, attacked_unit, attacking_unit, attack_direction, hit_world_position, hit_weakspot, damage, attack_result, attack_type, damage_efficiency, is_critical_strike)
    if not Pulses.enabled then
        return
    end

    local unit = Pulses.unit

    if Pulses.has_catch_a_breath and attacked_unit == unit and attack_type == ATTACK_TYPE_MELEE then
        Pulses.catch_a_breath_last_hit_t = _now()
    end

    if attacking_unit ~= unit or attack_result ~= ATTACK_RESULT_DIED then
        return
    end

    if attack_type == ATTACK_TYPE_MELEE then
        _add_melee_kill_pulse()
    end

    if Pulses.has_out_for_blood then
        _add_pulse(Sources.out_for_blood_fraction, true)
    end

    if Pulses.has_exhilarating and hit_weakspot and attack_type == ATTACK_TYPE_RANGED then
        _add_pulse(Sources.exhilarating_fraction, true)
    end

    local is_elite_or_special = false

    if attacked_unit then
        local unit_data_extension = ScriptUnit.has_extension(attacked_unit, "unit_data_system")
        local breed = unit_data_extension and unit_data_extension.breed and unit_data_extension:breed()
        local tags = breed and breed.tags

        is_elite_or_special = tags and (tags.elite or tags.special) and true or false
    end

    if Pulses.has_confirmed_kill and is_elite_or_special then
        _add_pulse(Sources.confirmed_kill_instant_fraction, true)

        Pulses.confirmed_kill_regen_until = _now() + Sources.confirmed_kill_regen_duration
    end

    if Pulses.has_executioners_stance and Pulses.has_stance_refresh and is_elite_or_special then
        local now = _now()

        if now < Pulses.stance_active_until then
            Pulses.stance_active_until = now + _stance_duration()
        end
    end

    if Pulses.has_target_down and attacked_unit and _tagged_by_local_player(attacked_unit) then
        if attacked_unit == Pulses.focus_target_unit then
            Pulses.focus_target_unit = nil
        end

        local stacks = _focus_target_stacks()

        if stacks > 0 then
            _add_pulse(Sources.target_down_fraction_per_stack * stacks, false)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Hooks
-- ----------------------------------------------------------------------------

-- A smart tag was created on this machine (for clients, when the server's tag arrives). The
-- server's Focus Target follows the owner's own `enemy_over_here_veteran` tags for 25 s and
-- ignores later replacements by teammates, so the enemy is remembered the same way.
mod:hook_safe(CLASS.SmartTagSystem, "_create_tag_locally", function(self, tag_id, template_name, tagger_unit, target_unit)
    if not Pulses.enabled or not Pulses.has_target_down or tagger_unit ~= Pulses.unit or not target_unit or template_name ~= Sources.target_down_tag_name then
        return
    end

    Pulses.focus_target_unit = target_unit
    Pulses.focus_target_until = _now() + Sources.target_down_tag_duration
end)

--- Records an On Your Toes restore for drawing a weapon, as the game's Weapons Specialist does.
-- Needs Specialist stacks and honours the independent 3 s cooldown per side.
-- number: t gameplay time of the swap
-- bool: is_ranged the drawn weapon is a ranged weapon
-- bool: is_melee the drawn weapon is a melee weapon
local function _on_your_toes(t, is_ranged, is_melee)
    local stacks = _weapon_switch_stacks()

    if stacks <= 0 then
        return
    end

    local cooldown = Sources.on_your_toes_cooldown

    if is_ranged and t > Pulses.last_ranged_wield_t + cooldown then
        Pulses.last_ranged_wield_t = t

        _add_pulse(Sources.on_your_toes_fraction, true)
    elseif is_melee and t > Pulses.last_melee_wield_t + cooldown then
        Pulses.last_melee_wield_t = t

        _add_pulse(Sources.on_your_toes_fraction, true)
    end
end

-- The Veteran used a combat ability. Voice of Command and Infiltrate record a shout burst, and
-- the ranged stance opens the Executioner's Stance window. The stance draws the ranged weapon
-- itself without an unwield action, so the wielded slot is read before the original runs to
-- count that draw for On Your Toes.
mod:hook(CLASS.ActionVeteranCombatAbility, "start", function(func, self, action_settings, t, time_scale, action_start_params)
    local inventory_component = self._inventory_component
    local wielded_slot_before = inventory_component and inventory_component.wielded_slot

    func(self, action_settings, t, time_scale, action_start_params)

    if not Pulses.enabled or self._player_unit ~= Pulses.unit then
        return
    end

    local tweak_data = self._ability_template_tweak_data
    local class_tag = tweak_data and tweak_data.class_tag

    if class_tag == "squad_leader" or class_tag == "shock_trooper" then
        _add_burst()
    elseif (class_tag == "ranger" or class_tag == "base") and Pulses.has_executioners_stance then
        Pulses.stance_active_until = t + _stance_duration()
    end

    if Pulses.has_on_your_toes and tweak_data and tweak_data.wield_secondary_slot and wielded_slot_before and wielded_slot_before ~= "slot_secondary" then
        _on_your_toes(t, true, false)
    end
end)

--- Returns whether an unwield action is drawing a ranged and/or a melee weapon.
-- tab: action the `ActionUnwield` instance
-- treturn: bool ranged
-- treturn: bool melee
local function _wield_is_ranged_melee(action)
    local component = action._action_unwield_component
    local slot = component and component.slot_to_wield
    local visual_loadout_extension = action._visual_loadout_extension

    if not slot or not visual_loadout_extension or not visual_loadout_extension.weapon_template_from_slot then
        return false, false
    end

    local weapon_template = visual_loadout_extension:weapon_template_from_slot(slot)
    local keywords = weapon_template and weapon_template.keywords

    if not keywords then
        return false, false
    end

    local is_ranged, is_melee = false, false

    for i = 1, #keywords do
        local keyword = keywords[i]

        if keyword == "ranged" then
            is_ranged = true
        elseif keyword == "melee" then
            is_melee = true
        end
    end

    return is_ranged, is_melee
end

-- A weapon swap started (also covers `ActionUnwieldToPrevious`); records On Your Toes for the
-- weapon being drawn.
mod:hook_safe(CLASS.ActionUnwield, "start", function(self, action_settings, t, time_scale, action_start_params)
    if not Pulses.enabled or not Pulses.has_on_your_toes or self._player_unit ~= Pulses.unit then
        return
    end

    local is_ranged, is_melee = _wield_is_ranged_melee(self)

    if not is_ranged and not is_melee then
        return
    end

    _on_your_toes(t, is_ranged, is_melee)
end)

return Pulses
