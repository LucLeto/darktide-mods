
local mod = get_mod("OverflowMeter")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local Sources = mod._sources_veteran

local ScriptUnit = ScriptUnit
local Managers = Managers
local math_min = math.min

local ATTACK_RESULT_DIED = AttackSettings.attack_results.died
local ATTACK_TYPE_MELEE = AttackSettings.attack_types.melee
local ATTACK_TYPE_RANGED = AttackSettings.attack_types.ranged

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
}

local function _has_talent_buff(talent_extension, buff_template_name)
    if not talent_extension or not talent_extension.buff_template_tier then
        return false
    end

    local tier = talent_extension:buff_template_tier(buff_template_name)

    return tier ~= nil and tier ~= 0
end

local function _has_special_rule(talent_extension, rule_name)
    if not talent_extension or not talent_extension.has_special_rule then
        return false
    end

    return talent_extension:has_special_rule(rule_name) and true or false
end

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
end

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
end

Pulses.consume = function()
    local pending_excess = Pulses.pending_excess

    Pulses.pending_excess = 0

    return pending_excess
end

Pulses.consume_burst = function()
    local pending_burst_share = Pulses.pending_burst_share

    Pulses.pending_burst_share = 0

    return pending_burst_share
end

Pulses.consume_burst_overflow = function()
    local pending_burst_overflow = Pulses.pending_burst_overflow

    Pulses.pending_burst_overflow = 0

    return pending_burst_overflow
end

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

local function _now()
    local time_manager = Managers.time

    if time_manager and time_manager.has_timer and time_manager:has_timer("gameplay") then
        return time_manager:time("gameplay")
    end

    return 0
end

local function _is_disabled()
    local component = Pulses.disabled_component

    return component and component.is_disabled or false
end

local function _stance_duration()
    return Pulses.has_increased_stance_duration and Sources.stance_duration_increased or Sources.stance_duration
end

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

local function _weapon_switch_stacks()
    local unit_data_extension = Pulses.unit_data_extension

    if not unit_data_extension or not unit_data_extension.read_component then
        return 0
    end

    local component = unit_data_extension:read_component("talent_resource")

    return component and component.current_resource or 0
end

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

local function _tagged_by_local_player(attacked_unit)
    local state_managers = Managers.state
    local extension_manager = state_managers and state_managers.extension
    local smart_tag_system = extension_manager and extension_manager.system and extension_manager:system("smart_tag_system")

    if not smart_tag_system or not smart_tag_system.unit_tag then
        return false
    end

    local tag = smart_tag_system:unit_tag(attacked_unit)

    return tag ~= nil and tag.tagger_unit ~= nil and tag:tagger_unit() == Pulses.unit
end

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
        local stacks = _focus_target_stacks()

        if stacks > 0 then
            _add_pulse(Sources.target_down_fraction_per_stack * stacks, false)
        end
    end
end

mod:hook_safe(CLASS.ActionVeteranCombatAbility, "start", function(self, action_settings, t, time_scale, action_start_params)
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
end)

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

mod:hook_safe(CLASS.ActionUnwield, "start", function(self, action_settings, t, time_scale, action_start_params)
    if not Pulses.enabled or not Pulses.has_on_your_toes or self._player_unit ~= Pulses.unit then
        return
    end

    local is_ranged, is_melee = _wield_is_ranged_melee(self)

    if not is_ranged and not is_melee then
        return
    end

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
end)

return Pulses
