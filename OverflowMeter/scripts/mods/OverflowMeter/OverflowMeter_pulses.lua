--- Skitarii (Power Overflow) pulse tracking: discrete restores the bar cannot show while full.
-- Power Overflow only shares replenishes that land at full Toughness, where the replicated bar
-- cannot move, so discrete restores are inferred from client-side events: local attack reports
-- (melee kills, Servo-Core Recharge Engine weakspot kills, Flensing Protocols Elite and
-- Specialist kills, Voltaic Overcharge hits), weapon blessing procs and the Voltaic Emitter
-- ability. Each restore becomes a fraction of maximum Toughness and is queued for the HUD
-- element, which drains the queues every sample. `pending_fraction` holds restores that landed
-- at full and is shared as a one-sample pulse; `pending_burst_fraction` holds Voltaic
-- Overcharge's on-use restore at full and is shown as a flash; `pending_overflow` holds the
-- Toughness lost against the cap, at full or not, in Toughness points.
--
-- Explicit module loaded by `OverflowMeter.lua` and stored as `mod._pulses`. `on_proc_active`
-- and `on_attack_result` are called from the shared hooks in `OverflowMeter.lua`; the Voltaic
-- Emitter hook is registered here. `set_context` enables it for the local player's unit, and it
-- ignores every event while disabled.
-- module: OverflowMeter_pulses
-- alias: Pulses
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local AttackSettings = require("scripts/settings/damage/attack_settings")
local Sources = mod._sources

local ScriptUnit = ScriptUnit
local math_min = math.min

local ATTACK_RESULT_DIED = AttackSettings.attack_results.died
local ATTACK_TYPE_MELEE = AttackSettings.attack_types.melee
--- Toughness fraction treated as full, matching the HUD element.
local FULL_TOUGHNESS_EPSILON = 0.999
local COMBAT_ABILITY_TYPE = "combat_ability"

--- Pulse state: the pending queues, the local Skitarius' unit and extensions, and whether the
-- build has the talent behind each kill or hit pulse.
local Pulses = {
    enabled = false,
    pending_fraction = 0,
    pending_burst_fraction = 0,
    pending_overflow = 0,
    unit = nil,
    buff_extension = nil,
    toughness_extension = nil,
    has_weakspot_talent = false,
    has_dissector_talent = false,
    has_discharge_toughness_talent = false,
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

--- Enables the module for the local player's unit and caches its extensions and talent flags.
-- param: unit local player unit
-- tab: buff_extension its buff extension
-- tab: toughness_extension its toughness extension
-- ?tab: talent_extension its talent extension
Pulses.set_context = function(unit, buff_extension, toughness_extension, talent_extension)
    Pulses.enabled = true
    Pulses.unit = unit
    Pulses.buff_extension = buff_extension
    Pulses.toughness_extension = toughness_extension
    Pulses.has_weakspot_talent = _has_talent_buff(talent_extension, Sources.weakspot_talent_buff_name)
    Pulses.has_dissector_talent = _has_talent_buff(talent_extension, Sources.dissector_talent_buff_name)
    Pulses.has_discharge_toughness_talent = _has_talent_buff(talent_extension, Sources.discharge_toughness_talent_buff_name)
end

--- Disables the module and clears every queue, cached extension and talent flag.
Pulses.disable = function()
    Pulses.enabled = false
    Pulses.pending_fraction = 0
    Pulses.pending_burst_fraction = 0
    Pulses.pending_overflow = 0
    Pulses.unit = nil
    Pulses.buff_extension = nil
    Pulses.toughness_extension = nil
    Pulses.has_weakspot_talent = false
    Pulses.has_dissector_talent = false
    Pulses.has_discharge_toughness_talent = false
end

--- Returns and clears the restores that landed at full Toughness.
-- treturn: number fraction of maximum Toughness
Pulses.consume = function()
    local pending_fraction = Pulses.pending_fraction

    Pulses.pending_fraction = 0

    return pending_fraction
end

--- Returns and clears Voltaic Overcharge's on-use restores that landed at full Toughness.
-- treturn: number fraction of maximum Toughness
Pulses.consume_burst_fraction = function()
    local pending_burst_fraction = Pulses.pending_burst_fraction

    Pulses.pending_burst_fraction = 0

    return pending_burst_fraction
end

--- Returns and clears the Toughness lost against the cap.
-- treturn: number Toughness points
Pulses.consume_overflow = function()
    local pending_overflow = Pulses.pending_overflow

    Pulses.pending_overflow = 0

    return pending_overflow
end

-- ----------------------------------------------------------------------------
-- Pulse recording
-- ----------------------------------------------------------------------------

--- Returns whether the local player is at full Toughness.
-- treturn: bool
local function _is_full()
    local toughness_extension = Pulses.toughness_extension

    return toughness_extension ~= nil and toughness_extension:current_toughness_percent() >= FULL_TOUGHNESS_EPSILON
end

--- Adds the part of a restore that exceeds the missing Toughness to the overflow.
-- number: fraction restore as a fraction of maximum Toughness
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

--- Records a restore: its overflow always, and the restore itself when it lands at full.
-- ?number: fraction restore as a fraction of maximum Toughness; ignored unless positive
-- ?bool: apply_replenish_stat_buffs scale by `toughness_replenish_modifier` and
-- `toughness_replenish_multiplier`, as the game does for restores that use stat buffs
-- ?bool: as_burst queue a restore at full as a burst instead of a pulse
local function _add_pulse(fraction, apply_replenish_stat_buffs, as_burst)
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
        if as_burst then
            Pulses.pending_burst_fraction = Pulses.pending_burst_fraction + fraction
        else
            Pulses.pending_fraction = Pulses.pending_fraction + fraction
        end
    end
end

--- Records the base melee-kill restore, scaled the way the game's toughness template does.
-- The melee replenish bonus (Slaughter Protocol) adds to the replenish modifier, and the
-- replenish multiplier applies on top.
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

--- Records the restores triggered by one of the local player's attack reports.
-- Any Voltaic Overcharge explosion hit restores 1 %. A kill adds the base melee restore for melee
-- kills, Servo-Core Recharge Engine for weakspot kills and Flensing Protocols for Elite and
-- Specialist kills. The arguments are those of `AttackReportManager.add_attack_result`.
-- ?tab: damage_profile damage profile of the attack
-- param: attacked_unit unit that was hit
-- param: attacking_unit unit that attacked; only the local player's attacks count
-- bool: hit_weakspot whether a weakspot was hit
-- string: attack_result `died` for a kill
-- string: attack_type such as `melee` or `ranged`
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

--- Returns how many combat ability charges a Voltaic Emitter use counts as, the way the game does.
-- The Mortis Trials full-charge keyword makes every use count as the maximum. Otherwise it is the
-- cost `ActionAbilityBase.start` consumed, falling back to the ability extension's last count and
-- then 1, capped at the maximum.
-- tab: action the `ActionCrypticDischarge` instance
-- treturn: number charges, 1 to the maximum
local function _discharge_charges(action)
    local max_charges = Sources.discharge_max_charges
    local buff_extension = action._buff_extension

    if buff_extension and buff_extension.has_keyword and buff_extension:has_keyword(Sources.discharge_full_charges_keyword) then
        return max_charges
    end

    local charges = action._ability_cost_at_start

    if type(charges) ~= "number" or charges < 1 then
        local ability_extension = action._ability_extension

        charges = ability_extension and ability_extension.ability_charges_used_on_activation and ability_extension:ability_charges_used_on_activation(COMBAT_ABILITY_TYPE)
    end

    if type(charges) ~= "number" or charges < 1 then
        return 1
    end

    return math_min(charges, max_charges)
end

-- Voltaic Emitter use. With Voltaic Overcharge it restores 25 % per charge spent, queued as a
-- burst. The hook runs after `ActionAbilityBase.start` has consumed the charges.
mod:hook_safe(CLASS.ActionCrypticDischarge, "start", function(self, action_settings, t, time_scale, action_start_params)
    if not Pulses.enabled or self._player_unit ~= Pulses.unit then
        return
    end

    local talent_extension = self._talent_extension

    if talent_extension and talent_extension.has_special_rule and talent_extension:has_special_rule(Sources.discharge_restore_special_rule) then
        _add_pulse(Sources.discharge_use_fraction * _discharge_charges(self), true, true)
    end
end)

return Pulses
