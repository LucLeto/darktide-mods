--- Veteran (Born Leader) source model: talent tuning, blessing procs and the at-full regeneration.
-- Born Leader shares 20 % of the wanted amount of every replenish the Veteran makes with each
-- ally in Coherency, at any Toughness level. Below full the HUD element measures that from the
-- Toughness bar itself, so this module mainly serves the at-full model: restore fractions, buff
-- names, special rules and timings of every discrete feeder and continuous source for
-- `OverflowMeter_pulses_veteran.lua`, and adapters for the build's highest continuous rates
-- (Catch a Breath, Confirmed Kill and Executioner's Stance), which form the nominal ceiling.
--
-- Explicit module loaded by `OverflowMeter.lua` and stored as `mod._sources_veteran` (and as
-- `veteran` in `mod._sources_by_archetype`).
-- module: OverflowMeter_sources_veteran
-- author: LucLeto
local ArchetypeToughnessTemplates = require("scripts/settings/toughness/archetype_toughness_templates")
local TalentSettings = require("scripts/settings/talent/talent_settings")

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

local veteran_settings_2 = TalentSettings.veteran_2 or {}
local veteran_settings_3 = TalentSettings.veteran_3 or {}

--- Talent tuning read from the game's talent and toughness settings.
-- Born Leader is `coop_3`, Out for Blood `veteran_3.toughness_3`, Confirmed Kill
-- `veteran_2.toughness_1`, Exhilarating Takedown `toughness_2`, Catch a Breath
-- `veteran_2.toughness_3` and Executioner's Stance `combat_ability`. Every value falls back to
-- its 1.13 number when a settings path is missing.
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

--- Talent buff templates; a buff template tier above 0 means the build has the talent.
local OUT_FOR_BLOOD_BUFF_NAME = "veteran_all_kills_replenish_bonus_toughness"
local CONFIRMED_KILL_BUFF_NAME = "veteran_toughness_on_elite_kill"
local EXHILARATING_BUFF_NAME = "veteran_ranged_weakspot_toughness_recovery"
local CATCH_A_BREATH_BUFF_NAME = "veteran_toughness_regen_out_of_melee"

--- Executioner's Stance: the passive buff that carries its regeneration, the special rule that
-- lengthens the stance and the one that refreshes it on highlighted Elite and Specialist kills.
local STANCE_AUGMENT_BUFF_NAME = "veteran_combat_ability_increased_ranged_and_weakspot_damage_outlines"
local STANCE_INCREASED_DURATION_RULE = "veteran_combat_ability_ogryn_outlines"
local STANCE_REFRESH_RULE = "veteran_combat_ability_outlined_kills_extends_duration"

--- Keystone upgrade rules (On Your Toes, Target Down!) and the tag Focus Target follows.
local ON_YOUR_TOES_RULE = "veteran_weapon_switch_replenish_toughness"
local TARGET_DOWN_RULE = "veteran_improved_tag_dead_bonus"
local TARGET_DOWN_TAG_NAME = "enemy_over_here_veteran"

--- Weapon blessing proc buffs that restore a fixed percentage of Toughness, grouped by trigger.
-- A deliberate superset: a template for a weapon the Veteran cannot equip simply never procs.
local WEAPON_TOUGHNESS_PROC_TEMPLATES = {
    -- Continuous fire
    weapon_trait_bespoke_arc_rifle_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autogun_p2_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autopistol_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_dual_autopistols_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_bolter_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_shotgun_p4_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_shotgun_p3_toughness_on_continuous_fire = true,
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
    weapon_trait_bespoke_shotgun_p3_toughness_on_close_range_kills = true,
    weapon_trait_bespoke_shotgun_p3_toughness_on_elite_kills = true,
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

--- Continuous-fire blessings, whose restore is multiplied by the current fire step (up to 5).
local CONTINUOUS_FIRE_TEMPLATES = {
    weapon_trait_bespoke_arc_rifle_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autogun_p2_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_autopistol_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_dual_autopistols_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_bolter_p1_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_shotgun_p4_toughness_on_continuous_fire = true,
    weapon_trait_bespoke_shotgun_p3_toughness_on_continuous_fire = true,
}

-- ----------------------------------------------------------------------------
-- Continuous source adapters
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

--- Catch a Breath: 5 % per second once you have not been attacked in melee for 5 s.
-- The Veteran adapters only report availability and their highest rate; when each source is
-- active is modelled by `OverflowMeter_pulses_veteran.lua`.
local catch_a_breath = {
    name = "catch_a_breath",
    is_available = function (ctx)
        return _has_talent_buff(ctx.talent_extension, CATCH_A_BREATH_BUFF_NAME)
    end,
    max_rate = function ()
        return catch_a_breath_rate
    end
}

--- Confirmed Kill: 2 % per second for 10 s after an Elite or Specialist kill.
local confirmed_kill_regeneration = {
    name = "confirmed_kill_regeneration",
    is_available = function (ctx)
        return _has_talent_buff(ctx.talent_extension, CONFIRMED_KILL_BUFF_NAME)
    end,
    max_rate = function ()
        return confirmed_kill_regen_per_second
    end
}

--- Executioner's Stance: 10 % per second while the ranged stance is up.
local executioners_stance = {
    name = "executioners_stance",
    is_available = function (ctx)
        return _has_talent_buff(ctx.talent_extension, STANCE_AUGMENT_BUFF_NAME)
    end,
    max_rate = function ()
        return stance_regen_rate
    end
}

--- Every continuous adapter, for the nominal ceiling.
local adapters = {
    catch_a_breath,
    confirmed_kill_regeneration,
    executioners_stance
}

--- Sums the highest rates of every adapter the build has.
-- tab: adapters adapter list
-- tab: ctx sample context with the `talent_extension`
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

-- ----------------------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------------------

--- The Veteran source model.
-- `continuous_when_full` and `has_inactive_state` select Born Leader's estimator mode,
-- `share_fraction` is the 20 % it offers each ally and `available_max_fraction(ctx)` returns
-- the nominal ceiling. The remaining fields are inputs for `OverflowMeter_pulses_veteran.lua`.
-- On Your Toes, Target Down! and the Focus Target duration are hard-coded in the game's buff
-- templates, so they are hard-coded here as well.
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
    target_down_tag_name = TARGET_DOWN_TAG_NAME,
    target_down_tag_duration = 25,
}
