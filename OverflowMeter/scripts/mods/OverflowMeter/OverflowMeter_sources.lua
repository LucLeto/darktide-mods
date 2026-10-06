local ArchetypeToughnessTemplates = require("scripts/settings/toughness/archetype_toughness_templates")
local TalentSettings = require("scripts/settings/talent/talent_settings")
local SpecialRulesSettings = require("scripts/settings/ability/special_rules_settings")

local special_rules = SpecialRulesSettings.special_rules
local cryptic_settings = TalentSettings.cryptic or {}

local shared_toughness_settings = cryptic_settings.cryptic_shared_toughness
local share_fraction = shared_toughness_settings and shared_toughness_settings.toughness_replenish_percent or 0.25

local precision_stance_settings = cryptic_settings.precision_stance
local precision_stance_toughness_settings = precision_stance_settings and precision_stance_settings.cryptic_precision_stance_toughness_suppression
local precision_stance_fallback_rate = precision_stance_toughness_settingste and precision_stance_toughness_settings.toughness_regen_per_second or 0.1

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
local discharge_toughness_settings = discharge_ability_settings and discharge_ability_settings.cryptic_discharge_toughness
local discharge_use_fraction = discharge_toughness_settings and discharge_toughness_settings.toughness_percent_on_use or 0.25
local discharge_hit_fraction = discharge_toughness_settings and discharge_toughness_settings.toughness_percent_per_hit or 0.01

local PRECISION_STANCE_RESTORE_RULE = special_rules.cryptic_precision_stance_restores_toughness or "cryptic_precision_stance_restores_toughness"
local COMBAT_ABILITY_TYPE = "combat_ability"
local TOUGHNESS_PER_CHARGE_BUFF_NAME = "cryptic_toughness_per_charge"
local RANGED_STACKING_BUFF_NAME = "cryptic_ranged_stacking_toughness_stack"

local PRECISION_STANCE_BUFF_NAMES = {
    "cryptic_precision_stance_one_charge",
    "cryptic_precision_stance_two_charges",
    "cryptic_precision_stance_three_charges"
}

local TEMPORARY_REGEN_BUFF_NAMES = {
    "cryptic_multi_hits_restore_toughness",
    "cryptic_crits_grant_tdr",
    "cryptic_elite_kills_toughness",
    "cryptic_electrocution_toughness",
    "cryptic_toughness_on_damage_taken",
    "cryptic_redline_toughness"
}

local relevant_buff_names = {}

for i = 1, #PRECISION_STANCE_BUFF_NAMES do
    relevant_buff_names[PRECISION_STANCE_BUFF_NAMES[i]] = true
end

relevant_buff_names[TOUGHNESS_PER_CHARGE_BUFF_NAME] = true
relevant_buff_names[RANGED_STACKING_BUFF_NAME] = true

for i = 1, #TEMPORARY_REGEN_BUFF_NAMES do
    relevant_buff_names[TEMPORARY_REGEN_BUFF_NAMES[i]] = true
end

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

local CONTINUOUS_FIRE_TEMPLATES = {
    weapon_trait_bespoke_arc_rifle_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autogun_p2_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autopistol_p1_toughness_on_continuous_fire = true
}

local function _find_precision_stance_buff(buffs_by_name)
    for i = 1, #PRECISION_STANCE_BUFF_NAMES do
        local instance = buffs_by_name[PRECISION_STANCE_BUFF_NAMES[i]]

        if instance then
            return instance
        end
    end

    return nil
end

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

local adapters = {
    precision_stance,
    toughness_per_charge,
    ranged_kill_regeneration,
    temporary_regeneration
}

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
    discharge_damage_profile_name = "cryptic_discharge_explosion",
    discharge_restore_special_rule = special_rules.cryptic_discharge_restores_toughness_on_use or "cryptic_discharge_restores_toughness_on_use",
    weakspot_talent_buff_name = "cryptic_weakspot_kills_restore_toughness",
    dissector_talent_buff_name = "cryptic_dissector",
    discharge_toughness_talent_buff_name = "cryptic_discharge_toughness"
}
