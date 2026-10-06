
local mod = get_mod("OverflowMeter")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local Sources = mod._sources

local ScriptUnit = ScriptUnit
local math_min = math.min

local ATTACK_RESULT_DIED = AttackSettings.attack_results.died
local ATTACK_TYPE_MELEE = AttackSettings.attack_types.melee
local FULL_TOUGHNESS_EPSILON = 0.999

local Pulses = {
    enabled = false,
    pending_fraction = 0,
    pending_overflow = 0,
    unit = nil,
    buff_extension = nil,
    toughness_extension = nil,
    has_weakspot_talent = false,
    has_dissector_talent = false,
    has_discharge_toughness_talent = false,
}

local function _has_talent_buff(talent_extension, buff_template_name)
    if not talent_extension or not talent_extension.buff_template_tier then
        return false
    end

    local tier = talent_extension:buff_template_tier(buff_template_name)

    return tier ~= nil and tier ~= 0
end

Pulses.set_context = function(unit, buff_extension, toughness_extension, talent_extension)
    Pulses.enabled = true
    Pulses.unit = unit
    Pulses.buff_extension = buff_extension
    Pulses.toughness_extension = toughness_extension
    Pulses.has_weakspot_talent = _has_talent_buff(talent_extension, Sources.weakspot_talent_buff_name)
    Pulses.has_dissector_talent = _has_talent_buff(talent_extension, Sources.dissector_talent_buff_name)
    Pulses.has_discharge_toughness_talent = _has_talent_buff(talent_extension, Sources.discharge_toughness_talent_buff_name)
end

Pulses.disable = function()
    Pulses.enabled = false
    Pulses.pending_fraction = 0
    Pulses.pending_overflow = 0
    Pulses.unit = nil
    Pulses.buff_extension = nil
    Pulses.toughness_extension = nil
    Pulses.has_weakspot_talent = false
    Pulses.has_dissector_talent = false
    Pulses.has_discharge_toughness_talent = false
end

Pulses.consume = function()
    local pending_fraction = Pulses.pending_fraction

    Pulses.pending_fraction = 0

    return pending_fraction
end

Pulses.consume_overflow = function()
    local pending_overflow = Pulses.pending_overflow

    Pulses.pending_overflow = 0

    return pending_overflow
end

local function _is_full()
    local toughness_extension = Pulses.toughness_extension

    return toughness_extension ~= nil and toughness_extension:current_toughness_percent() >= FULL_TOUGHNESS_EPSILON
end

local function _accumulate_overflow(fraction)
    local toughness_extension = Pulses.toughness_extension

    if not toughness_extension then
        return
    end

    local excess = fraction * toughness_extension:max_toughness() - toughness_extension:toughness_damage()

    if excess > 0 then
        Pulses.pending_overflow = Pulses.pending_overflow + excess
    end
end

local function _add_pulse(fraction, apply_replenish_stat_buffs)
    if not fraction or fraction <= 0 then
        return
    end

    if apply_replenish_stat_buffs then
        local buff_extension = Pulses.buff_extension
        local stat_buffs = buff_extension and buff_extension.stat_buffs and buff_extension:stat_buffs()

        if stat_buffs then
            fraction = fraction * (stat_buffs.toughness_replenish_modifier or 1) * (stat_buffs.toughness_replenish_multiplier or 1)
        end
    end

    _accumulate_overflow(fraction)

    if _is_full() then
        Pulses.pending_fraction = Pulses.pending_fraction + fraction
    end
end

local function _add_melee_kill_pulse()
    local fraction = Sources.melee_kill_base_fraction
    local buff_extension = Pulses.buff_extension
    local stat_buffs = buff_extension and buff_extension.stat_buffs and buff_extension:stat_buffs()

    if stat_buffs then
        fraction = fraction * ((stat_buffs.toughness_melee_replenish or 1) + (stat_buffs.toughness_replenish_modifier or 1) - 1) * (stat_buffs.toughness_replenish_multiplier or 1)
    end

    if fraction > 0 then
        _accumulate_overflow(fraction)

        if _is_full() then
            Pulses.pending_fraction = Pulses.pending_fraction + fraction
        end
    end
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
    if not Pulses.enabled or attacking_unit ~= Pulses.unit then
        return
    end

    if Pulses.has_discharge_toughness_talent and damage_profile and damage_profile.name == Sources.discharge_damage_profile_name then
        _add_pulse(Sources.discharge_hit_fraction, true)
    end

    if attack_result ~= ATTACK_RESULT_DIED then
        return
    end

    if attack_type == ATTACK_TYPE_MELEE then
        _add_melee_kill_pulse()
    end

    if hit_weakspot and Pulses.has_weakspot_talent then
        _add_pulse(Sources.weakspot_kill_fraction, true)
    end

    if Pulses.has_dissector_talent and attacked_unit then
        local unit_data_extension = ScriptUnit.has_extension(attacked_unit, "unit_data_system")
        local breed = unit_data_extension and unit_data_extension.breed and unit_data_extension:breed()
        local tags = breed and breed.tags

        if tags and (tags.elite or tags.special) then
            _add_pulse(Sources.dissector_kill_fraction, true)
        end
    end
end

mod:hook_safe(CLASS.ActionCrypticDischarge, "start", function(self, action_settings, t, time_scale, action_start_params)
    if not Pulses.enabled or self._player_unit ~= Pulses.unit then
        return
    end

    local talent_extension = self._talent_extension

    if talent_extension and talent_extension.has_special_rule and talent_extension:has_special_rule(Sources.discharge_restore_special_rule) then
        _add_pulse(Sources.discharge_use_fraction, true)
    end
end)

return Pulses
