local ArchetypeToughnessTemplates = require("scripts/settings/toughness/archetype_toughness_templates")
local TalentSettings = require("scripts/settings/talent/talent_settings")

local veteran_settings_2 = TalentSettings.veteran_2 or {}
local veteran_settings_3 = TalentSettings.veteran_3 or {}

local born_leader_settings = veteran_settings_3.coop_3
local share_fraction = born_leader_settings and born_leader_settings.percent or 0.2

local veteran_toughness_template = ArchetypeToughnessTemplates.veteran
local veteran_recovery_percentages = veteran_toughness_template and veteran_toughness_template.recovery_percentages
local melee_kill_base_fraction = veteran_recovery_percentages and veteran_recovery_percentages.melee_kill or 0.05

local out_for_blood_settings = veteran_settings_3.toughness_3
local out_for_blood_fraction = out_for_blood_settings and out_for_blood_settings.toughness or 0.05

local confirmed_kill_settings = veteran_settings_2.toughness_1
local confirmed_kill_instant_fraction = confirmed_kill_settings and confirmed_kill_settings.instant_toughness or 0.1
local confirmed_kill_regen_per_second = confirmed_kill_settings and confirmed_kill_settings.toughness or 0.02

local exhilarating_settings = veteran_settings_2.toughness_2
local exhilarating_fraction = exhilarating_settings and exhilarating_settings.toughness or 0.15

local catch_a_breath_settings = veteran_settings_2.toughness_3
local catch_a_breath_rate = catch_a_breath_settings and catch_a_breath_settings.toughness or 0.05
local catch_a_breath_cooldown = catch_a_breath_settings and catch_a_breath_settings.cooldown or 5
local confirmed_kill_regen_duration = confirmed_kill_settings and confirmed_kill_settings.duration or 10

local stance_settings = veteran_settings_2.combat_ability or {}
local stance_regen_rate = stance_settings.toughness or 0.1
local stance_duration = stance_settings.duration or 6
local stance_duration_increased = stance_settings.duration_increased or stance_duration

local focus_target_settings = TalentSettings.veteran_tag or {}
local target_down_max_stacks = focus_target_settings.max_stacks_talent or focus_target_settings.max_stacks or 6

local OUT_FOR_BLOOD_BUFF_NAME = "veteran_all_kills_replenish_bonus_toughness"
local CONFIRMED_KILL_BUFF_NAME = "veteran_toughness_on_elite_kill"
local EXHILARATING_BUFF_NAME = "veteran_ranged_weakspot_toughness_recovery"
local CATCH_A_BREATH_BUFF_NAME = "veteran_toughness_regen_out_of_melee"

local STANCE_AUGMENT_BUFF_NAME = "veteran_combat_ability_increased_ranged_and_weakspot_damage_outlines"
local STANCE_INCREASED_DURATION_RULE = "veteran_combat_ability_ogryn_outlines"
local STANCE_REFRESH_RULE = "veteran_combat_ability_outlined_kills_extends_duration"

local ON_YOUR_TOES_RULE = "veteran_weapon_switch_replenish_toughness"
local TARGET_DOWN_RULE = "veteran_improved_tag_dead_bonus"

local WEAPON_TOUGHNESS_PROC_TEMPLATES = {
    -- Continuous fire
    weapon_trait_bespoke_arc_rifle_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autogun_p2_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autopistol_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_dual_autopistols_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_bolter_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_shotgun_p4_toughness_on_continuous_fire = true,
    -- Elite / crit / close-range kills
    weapon_trait_bespoke_bolter_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_boltpistol_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_galvanic_rifle_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_phosphor_pistol_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_plasmagun_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_stubrevolver_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_shotpistol_shield_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_needlepistol_p1_toughness_on_elite_kills = true,
    weapon_trait_bespoke_laspistol_p1_toughness_on_crit_kills = true,
    weapon_trait_bespoke_needlepistol_p1_toughness_on_crit_kills = true,
    weapon_trait_bespoke_dual_stubpistols_p1_toughness_on_close_range_kills = true,
    weapon_trait_bespoke_shotgun_p4_toughness_on_close_range_kills = true,
    -- Melee specials / chained hits
    weapon_trait_bespoke_chainsword_2h_p1_toughness_recovery_on_multiple_hits = true,
    weapon_trait_bespoke_forcesword_2h_p1_toughness_recovery_on_multiple_hits = true,
    weapon_trait_bespoke_thunderhammer_2h_p1_toughness_recovery_on_multiple_hits = true,
    weapon_trait_bespoke_bespoke_powersword_p2_regain_toughness_on_multiple_hits_by_weapon_special = true,
    weapon_trait_bespoke_bespoke_powersword_2h_p1_regain_toughness_on_multiple_hits_by_weapon_special = true,
    weapon_trait_bespoke_powermaul_p2_toughness_recovery_on_chained_attacks = true,
    weapon_trait_bespoke_powermaul_p3_toughness_recovery_on_chained_attacks = true,
    weapon_trait_bespoke_powermaul_shield_p1_toughness_recovery_on_chained_attacks = true,
}

local CONTINUOUS_FIRE_TEMPLATES = {
    weapon_trait_bespoke_arc_rifle_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autogun_p2_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autopistol_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_dual_autopistols_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_bolter_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_shotgun_p4_toughness_on_continuous_fire = true,
}

local function _has_talent_buff(talent_extension, buff_template_name)
    if not talent_extension or not talent_extension.buff_template_tier then
        return false
    end

    local tier = talent_extension:buff_template_tier(buff_template_name)

    return tier ~= nil and tier ~= 0
end

local catch_a_breath = {
    name = "catch_a_breath",
    is_available = function (ctx)
        return _has_talent_buff(ctx.talent_extension, CATCH_A_BREATH_BUFF_NAME)
    end,
    max_rate = function ()
        return catch_a_breath_rate
    end
}

local confirmed_kill_regeneration = {
    name = "confirmed_kill_regeneration",
    is_available = function (ctx)
        return _has_talent_buff(ctx.talent_extension, CONFIRMED_KILL_BUFF_NAME)
    end,
    max_rate = function ()
        return confirmed_kill_regen_per_second
    end
}

local executioners_stance = {
    name = "executioners_stance",
    is_available = function (ctx)
        return _has_talent_buff(ctx.talent_extension, STANCE_AUGMENT_BUFF_NAME)
    end,
    max_rate = function ()
        return stance_regen_rate
    end
}

local adapters = {
    catch_a_breath,
    confirmed_kill_regeneration,
    executioners_stance
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

return {
    continuous_when_full = false,
    has_inactive_state = false,

    share_fraction = share_fraction,
    adapters = adapters,

    available_max_fraction = function (ctx)
        return _available_max_fraction(adapters, ctx)
    end,

    weapon_toughness_proc_templates = WEAPON_TOUGHNESS_PROC_TEMPLATES,
    continuous_fire_templates = CONTINUOUS_FIRE_TEMPLATES,
    max_continuous_fire_steps = 5,

    melee_kill_base_fraction = melee_kill_base_fraction,
    out_for_blood_fraction = out_for_blood_fraction,
    confirmed_kill_instant_fraction = confirmed_kill_instant_fraction,
    exhilarating_fraction = exhilarating_fraction,

    out_for_blood_talent_buff_name = OUT_FOR_BLOOD_BUFF_NAME,
    confirmed_kill_talent_buff_name = CONFIRMED_KILL_BUFF_NAME,
    exhilarating_talent_buff_name = EXHILARATING_BUFF_NAME,
    catch_a_breath_talent_buff_name = CATCH_A_BREATH_BUFF_NAME,

    stance_regen_rate = stance_regen_rate,
    stance_duration = stance_duration,
    stance_duration_increased = stance_duration_increased,
    stance_augment_buff_name = STANCE_AUGMENT_BUFF_NAME,
    stance_increased_duration_rule = STANCE_INCREASED_DURATION_RULE,
    stance_refresh_rule = STANCE_REFRESH_RULE,
    catch_a_breath_rate = catch_a_breath_rate,
    catch_a_breath_cooldown = catch_a_breath_cooldown,
    confirmed_kill_regen_rate = confirmed_kill_regen_per_second,
    confirmed_kill_regen_duration = confirmed_kill_regen_duration,

    on_your_toes_fraction = 0.2,
    on_your_toes_cooldown = 3,
    on_your_toes_talent_rule = ON_YOUR_TOES_RULE,

    target_down_fraction_per_stack = 0.05,
    target_down_max_stacks = target_down_max_stacks,
    target_down_talent_rule = TARGET_DOWN_RULE,
}
