--- Skitarii (Power Overflow) source model: what feeds the talent and how much.
-- Power Overflow shares 25 % of every replenish that lands while the Skitarius is at full
-- Toughness. This module describes every such source the meter tracks, in two forms.
--
-- 1. Continuous regeneration is modelled by adapters: Restoration Protocol (the precision
--    stance), Auto-Repair Doctrines, Superior Defence Engrams and the temporary regeneration
--    talents. Each adapter reports whether it is active, its current rate, whether the build
--    has it and its highest rate. Rates are fractions of maximum Toughness per second.
-- 2. Discrete restores (melee and weakspot kills, Flensing Protocols, Voltaic Overcharge and
--    weapon blessing procs) are exported as fractions, buff names and template sets for
--    `OverflowMeter_pulses.lua`.
--
-- Explicit module loaded by `OverflowMeter.lua` and stored as `mod._sources` (and as `cryptic`
-- in `mod._sources_by_archetype`). Adapters receive the HUD element's sample context:
-- `buffs_by_name` (the relevant buffs found this sample), `talent_extension`,
-- `ability_extension` and `buff_extension`.
-- module: OverflowMeter_sources
-- author: LucLeto
local ArchetypeToughnessTemplates = require("scripts/settings/toughness/archetype_toughness_templates")
local TalentSettings = require("scripts/settings/talent/talent_settings")
local SpecialRulesSettings = require("scripts/settings/ability/special_rules_settings")

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

local special_rules = SpecialRulesSettings.special_rules
local cryptic_settings = TalentSettings.cryptic or {}

--- Talent tuning read from the game's talent and toughness settings.
-- Every value falls back to its 1.13 number when a settings path is missing.
local shared_toughness_settings = cryptic_settings.cryptic_shared_toughness
local share_fraction = shared_toughness_settings and shared_toughness_settings.toughness_replenish_percent or 0.25

local precision_stance_settings = cryptic_settings.precision_stance
local precision_stance_toughness_settings = precision_stance_settings and precision_stance_settings.cryptic_precision_stance_toughness_suppression
local precision_stance_fallback_rate = precision_stance_toughness_settings and precision_stance_toughness_settings.toughness_regen_per_second or 0.1

local per_charge_settings = cryptic_settings.cryptic_toughness_per_charge
local per_charge_fallback_base_rate = per_charge_settings and per_charge_settings.toughness_regen_per_second or 0.03
local per_charge_fallback_bonus_rate = per_charge_settings and per_charge_settings.increased_toughness_regen_per_charge or 0.005

local ranged_stacking_settings = cryptic_settings.cryptic_ranged_stacking_toughness
local ranged_stacking_fallback_rate_per_stack = ranged_stacking_settings and ranged_stacking_settings.toughness_regen_per_second_per_stack or 0.01
local ranged_stacking_max_stacks = ranged_stacking_settings and ranged_stacking_settings.max_stacks or 5

local DEFAULT_MAX_COMBAT_ABILITY_CHARGES = 3

local cryptic_toughness_template = ArchetypeToughnessTemplates.cryptic
local cryptic_recovery_percentages = cryptic_toughness_template and cryptic_toughness_template.recovery_percentages
local melee_kill_base_fraction = cryptic_recovery_percentages and cryptic_recovery_percentages.melee_kill or 0.05

local weakspot_kill_settings = cryptic_settings.cryptic_weakspot_kills_restore_toughness
local weakspot_kill_fraction = weakspot_kill_settings and weakspot_kill_settings.toughness_restored or 0.05

local dissector_settings = cryptic_settings.dissector
local dissector_kill_fraction = dissector_settings and dissector_settings.toughness_regen_percent_per_elite_or_special_kill or 0.15

local discharge_ability_settings = cryptic_settings.discharge_ability
local discharge_max_charges = discharge_ability_settings and discharge_ability_settings.max_charges or 3
local discharge_toughness_settings = discharge_ability_settings and discharge_ability_settings.cryptic_discharge_toughness
local discharge_use_fraction = discharge_toughness_settings and discharge_toughness_settings.toughness_percent_on_use or 0.25
local discharge_hit_fraction = discharge_toughness_settings and discharge_toughness_settings.toughness_percent_per_hit or 0.01

--- Special rule and buff names the adapters look for.
local PRECISION_STANCE_RESTORE_RULE = special_rules.cryptic_precision_stance_restores_toughness or "cryptic_precision_stance_restores_toughness"
local COMBAT_ABILITY_TYPE = "combat_ability"
local TOUGHNESS_PER_CHARGE_BUFF_NAME = "cryptic_toughness_per_charge"
local RANGED_STACKING_BUFF_NAME = "cryptic_ranged_stacking_toughness_stack"

--- Buffs Advanced Combat Doctrines applies while the stance is up; 1.13 only uses the one-charge buff.
local PRECISION_STANCE_BUFF_NAMES = {
    "cryptic_precision_stance_one_charge"
}

--- Talents that regenerate Toughness for a while after a trigger: Omnissian Recharge Litany,
-- Power Redistribution Uplink, Binary Ballistics Protocol, Entropic Transfer, Kinetic Energy
-- Distributors and Surge-Extension.
local TEMPORARY_REGEN_BUFF_NAMES = {
    "cryptic_multi_hits_restore_toughness",
    "cryptic_crits_grant_tdr",
    "cryptic_elite_kills_toughness",
    "cryptic_electrocution_toughness",
    "cryptic_toughness_on_damage_taken",
    "cryptic_redline_toughness"
}

--- Lookup set of every buff the adapters read; the HUD element collects only these into `buffs_by_name`.
local relevant_buff_names = {}

for i = 1, #PRECISION_STANCE_BUFF_NAMES do
    relevant_buff_names[PRECISION_STANCE_BUFF_NAMES[i]] = true
end

relevant_buff_names[TOUGHNESS_PER_CHARGE_BUFF_NAME] = true
relevant_buff_names[RANGED_STACKING_BUFF_NAME] = true

for i = 1, #TEMPORARY_REGEN_BUFF_NAMES do
    relevant_buff_names[TEMPORARY_REGEN_BUFF_NAMES[i]] = true
end

--- Weapon blessing proc buffs that restore a fixed percentage of Toughness: Confident Strike,
-- Inspiring Barrage, Reassuringly Accurate, Gloryhunter and Syphon. The set may include weapons
-- a Skitarius cannot equip; their templates simply never proc.
local WEAPON_TOUGHNESS_PROC_TEMPLATES = {
    weapon_trait_bespoke_powermaul_p3_toughness_recovery_on_chained_attacks = true,
    weapon_trait_bespoke_arc_rifle_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autogun_p2_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autopistol_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_laspistol_p1_toughness_on_crit_kills = true,
    weapon_trait_bespoke_galvanic_rifle_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_phosphor_pistol_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_plasmagun_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_stubrevolver_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_bespoke_powersword_p2_regain_toughness_on_multiple_hits_by_weapon_special = true
}

--- Continuous-fire blessings, whose restore is multiplied by the current fire step (up to 5).
local CONTINUOUS_FIRE_TEMPLATES = {
    weapon_trait_bespoke_arc_rifle_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autogun_p2_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autopistol_p1_toughness_on_continuous_fire = true
}

-- ----------------------------------------------------------------------------
-- Continuous source adapters
-- ----------------------------------------------------------------------------

--- Returns the active precision stance buff instance, if any.
-- tab: buffs_by_name relevant buffs by template name
-- treturn: ?tab buff instance
local function _find_precision_stance_buff(buffs_by_name)
    for i = 1, #PRECISION_STANCE_BUFF_NAMES do
        local instance = buffs_by_name[PRECISION_STANCE_BUFF_NAMES[i]]

        if instance then
            return instance
        end
    end

    return nil
end

--- Restoration Protocol: Advanced Combat Doctrines regenerates 10 % per second while the stance is up.
-- Needs the stance buff and the restore special rule. The rate comes from the buff template.
local precision_stance = {
    name = "precision_stance",
    is_active = function (ctx)
        if not _find_precision_stance_buff(ctx.buffs_by_name) then
            return false
        end

        local talent_extension = ctx.talent_extension

        if not talent_extension or not talent_extension.has_special_rule then
            return false
        end

        return talent_extension:has_special_rule(PRECISION_STANCE_RESTORE_RULE) and true or false
    end,
    estimate_per_second = function (ctx)
        local instance = _find_precision_stance_buff(ctx.buffs_by_name)
        local template = instance and instance:template()

        return template and template.toughness_regen_per_second or precision_stance_fallback_rate
    end,
    is_available = function (ctx)
        local talent_extension = ctx.talent_extension

        if not talent_extension or not talent_extension.has_special_rule then
            return false
        end

        return talent_extension:has_special_rule(PRECISION_STANCE_RESTORE_RULE) and true or false
    end,
    max_rate = function ()
        return precision_stance_fallback_rate
    end
}

--- Auto-Repair Doctrines: a base rate plus a bonus per held combat ability charge.
-- The highest rate assumes every charge is held.
local toughness_per_charge = {
    name = "toughness_per_charge",
    is_active = function (ctx)
        return ctx.buffs_by_name[TOUGHNESS_PER_CHARGE_BUFF_NAME] ~= nil
    end,
    estimate_per_second = function (ctx)
        local instance = ctx.buffs_by_name[TOUGHNESS_PER_CHARGE_BUFF_NAME]
        local template = instance and instance:template()
        local base_rate = template and template.toughness_regen_per_second or per_charge_fallback_base_rate
        local bonus_rate = template and template.increased_toughness_regen_per_charge or per_charge_fallback_bonus_rate
        local ability_extension = ctx.ability_extension
        local num_charges = 0

        if ability_extension and ability_extension.remaining_ability_charges then
            num_charges = ability_extension:remaining_ability_charges(COMBAT_ABILITY_TYPE) or 0
        end

        return base_rate + bonus_rate * num_charges
    end,

    is_available = function (ctx)
        return ctx.buffs_by_name[TOUGHNESS_PER_CHARGE_BUFF_NAME] ~= nil
    end,
    max_rate = function (ctx)
        local instance = ctx.buffs_by_name[TOUGHNESS_PER_CHARGE_BUFF_NAME]
        local template = instance and instance:template()
        local base_rate = template and template.toughness_regen_per_second or per_charge_fallback_base_rate
        local bonus_rate = template and template.increased_toughness_regen_per_charge or per_charge_fallback_bonus_rate
        local ability_extension = ctx.ability_extension
        local max_charges = DEFAULT_MAX_COMBAT_ABILITY_CHARGES

        if ability_extension and ability_extension.max_ability_charges then
            max_charges = ability_extension:max_ability_charges(COMBAT_ABILITY_TYPE) or DEFAULT_MAX_COMBAT_ABILITY_CHARGES
        end

        return base_rate + bonus_rate * max_charges
    end
}

--- Superior Defence Engrams: ranged kills grant stacks, each regenerating 1 % per second.
local ranged_kill_regeneration = {
    name = "ranged_kill_regeneration",
    is_active = function (ctx)
        return ctx.buffs_by_name[RANGED_STACKING_BUFF_NAME] ~= nil
    end,
    estimate_per_second = function (ctx)
        local instance = ctx.buffs_by_name[RANGED_STACKING_BUFF_NAME]

        if not instance then
            return 0
        end

        local template = instance:template()
        local rate_per_stack = template and template.toughness_regen_per_second_per_stack or ranged_stacking_fallback_rate_per_stack
        local stack_count = 0

        if instance.stack_count then
            stack_count = instance:stack_count() or 0
        else
            local buff_extension = ctx.buff_extension

            if buff_extension and buff_extension.current_stacks then
                stack_count = buff_extension:current_stacks(RANGED_STACKING_BUFF_NAME) or 0
            end
        end

        return rate_per_stack * stack_count
    end,

    is_available = function (ctx)
        return ctx.buffs_by_name[RANGED_STACKING_BUFF_NAME] ~= nil
    end,
    max_rate = function (ctx)
        local instance = ctx.buffs_by_name[RANGED_STACKING_BUFF_NAME]
        local template = instance and instance:template()
        local rate_per_stack = template and template.toughness_regen_per_second_per_stack or ranged_stacking_fallback_rate_per_stack
        local max_stacks = template and template.max_stacks or ranged_stacking_max_stacks

        return rate_per_stack * max_stacks
    end
}

--- Sums the highest rates of every adapter the build has, the gauge's nominal ceiling.
-- tab: adapters adapter list
-- tab: ctx sample context
-- treturn: number fraction of maximum Toughness per second
local function _available_max_fraction(adapters, ctx)
    local total = 0

    for i = 1, #adapters do
        local adapter = adapters[i]

        if adapter.is_available and adapter.is_available(ctx) then
            total = total + adapter.max_rate(ctx)
        end
    end

    return total
end

--- The temporary regeneration talents together; active while any of their proc buffs is active.
local temporary_regeneration = {
    name = "temporary_regeneration",
    is_active = function (ctx)
        local buffs_by_name = ctx.buffs_by_name

        for i = 1, #TEMPORARY_REGEN_BUFF_NAMES do
            local instance = buffs_by_name[TEMPORARY_REGEN_BUFF_NAMES[i]]

            if instance and instance.is_proc_active and instance:is_proc_active() then
                local template = instance:template()

                if template and template.toughness_regen_per_second then
                    return true
                end
            end
        end

        return false
    end,
    estimate_per_second = function (ctx)
        local buffs_by_name = ctx.buffs_by_name
        local total_rate = 0

        for i = 1, #TEMPORARY_REGEN_BUFF_NAMES do
            local instance = buffs_by_name[TEMPORARY_REGEN_BUFF_NAMES[i]]

            if instance and instance.is_proc_active and instance:is_proc_active() then
                local template = instance:template()
                local rate = template and template.toughness_regen_per_second

                if rate then
                    total_rate = total_rate + rate
                end
            end
        end

        return total_rate
    end,

    is_available = function (ctx)
        local buffs_by_name = ctx.buffs_by_name

        for i = 1, #TEMPORARY_REGEN_BUFF_NAMES do
            local instance = buffs_by_name[TEMPORARY_REGEN_BUFF_NAMES[i]]

            if instance then
                local template = instance:template()

                if template and template.toughness_regen_per_second then
                    return true
                end
            end
        end

        return false
    end,
    max_rate = function (ctx)
        local buffs_by_name = ctx.buffs_by_name
        local total_rate = 0

        for i = 1, #TEMPORARY_REGEN_BUFF_NAMES do
            local instance = buffs_by_name[TEMPORARY_REGEN_BUFF_NAMES[i]]

            if instance then
                local template = instance:template()
                local rate = template and template.toughness_regen_per_second

                if rate then
                    total_rate = total_rate + rate
                end
            end
        end

        return total_rate
    end
}

--- Every continuous adapter, summed by the HUD element each sample.
local adapters = {
    precision_stance,
    toughness_per_charge,
    ranged_kill_regeneration,
    temporary_regeneration
}

-- ----------------------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------------------

--- The Skitarii source model.
-- `continuous_when_full` and `has_inactive_state` select the estimator mode, `share_fraction`
-- is the 25 % Power Overflow offers each ally, `relevant_buff_names` and `adapters` drive the
-- continuous estimate, and `available_max_fraction(ctx)` returns the nominal ceiling. The
-- remaining fields are pulse inputs for `OverflowMeter_pulses.lua`: the blessing template sets,
-- restore fractions, Voltaic Overcharge's charge cap and full-charge keyword, the Discharge
-- damage profile and special rule, and the talent buffs that gate the kill and hit pulses.
return {
    continuous_when_full = true,
    has_inactive_state = true,

    share_fraction = share_fraction,
    relevant_buff_names = relevant_buff_names,
    adapters = adapters,

    available_max_fraction = function (ctx)
        return _available_max_fraction(adapters, ctx)
    end,

    weapon_toughness_proc_templates = WEAPON_TOUGHNESS_PROC_TEMPLATES,
    continuous_fire_templates = CONTINUOUS_FIRE_TEMPLATES,
    max_continuous_fire_steps = 5,
    melee_kill_base_fraction = melee_kill_base_fraction,
    weakspot_kill_fraction = weakspot_kill_fraction,
    dissector_kill_fraction = dissector_kill_fraction,
    discharge_use_fraction = discharge_use_fraction,
    discharge_hit_fraction = discharge_hit_fraction,
    discharge_max_charges = discharge_max_charges,
    discharge_full_charges_keyword = "cryptic_discharge_ability_always_full_charges_bonus",
    discharge_damage_profile_name = "cryptic_discharge_explosion",
    discharge_restore_special_rule = special_rules.cryptic_discharge_restores_toughness_on_use or "cryptic_discharge_restores_toughness_on_use",
    weakspot_talent_buff_name = "cryptic_weakspot_kills_restore_toughness",
    dissector_talent_buff_name = "cryptic_dissector",
    discharge_toughness_talent_buff_name = "cryptic_discharge_toughness"
}
