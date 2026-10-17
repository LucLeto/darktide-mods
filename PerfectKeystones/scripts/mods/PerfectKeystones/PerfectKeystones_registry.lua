--- Keystone registry of Perfect Keystones; every tracked keystone as plain data.
-- Lists all 25 keystones of the seven archetypes as the talent trees of game version 1.13.2 define
-- them (nodes with `type = "keystone"`): 23 that draw a ring and two Arbitrator companion
-- specialisations, Go Get 'Em! and Unleashed Brutality, that are recognised but deliberately draw
-- nothing (`kind = KIND_NONE`). Each entry names the buff templates it reads, how they are read and
-- where its ring is drawn; the game mechanics behind those readings live in
-- `trackers/PerfectKeystones_sources.lua` and `trackers/PerfectKeystones_kinds.lua`, and the HUD
-- element only ever sees the resulting presentation state.
--
-- Entry fields:
-- `id` setting id of the entry's enable checkbox and its localization id;
-- `archetype` archetype name, as `player:archetype_name()` returns it;
-- `talent` the keystone's talent id (documentation and debug output);
-- `kind` presentation kind, one of the `KIND_*` values;
-- `slot` `SLOT_INNER` for the main keystone, `SLOT_OUTER` for the thin outer ring;
-- `detect` buff templates of which any present means the keystone is selected: the controller or
-- passive buff the talent installs, so disabled talents and talent changes are followed as the game
-- applies them (documentation only for entries without a ring, which the tracker never watches);
-- `buffs` buff templates whose stacks are read, the first one present wins (stack kinds, and the
-- resource phase of a hybrid);
-- `by_slot` for a hybrid whose resource depends on the wielded slot: template by slot name;
-- `cap` where the effective maximum is read, one of the `CAP_*` values;
-- `active` buff templates of a timed active phase (duration kind, and the active phase of a hybrid);
-- `cooldown_setting`, `visibility_setting`, `gate_setting` ids of the entry's extra settings;
-- `gate` condition the gate setting adds, one of the `GATE_*` values;
-- `settle` seconds a below-maximum deficit is held back after the stack buff first appears, as the
-- starting stacks reach a client over the network;
-- `decay_style` `DECAY_STABLE` (stable fill, next stack changes colour) or `DECAY_PROGRESSIVE`
-- (next stack drains); every current stack-decay keystone has the confirmed stable style.
--
-- Loaded through `mod:io_dofile` by `PerfectKeystones_data.lua`, which builds the archetype groups
-- from it, and by `PerfectKeystones.lua`, which caches its settings and stores it as
-- `mod._registry` for the tracker. It requires no game module, so the data file can load it too.
-- module: PerfectKeystones_registry
-- author: LucLeto
local pairs = pairs
local type = type

--- The registry module table.
local Registry = {}

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Presentation kinds.
Registry.KIND_DURATION = "duration"
Registry.KIND_STACK_DECAY = "stack_decay"
Registry.KIND_STACK_SHARED = "stack_shared"
Registry.KIND_STACK_DISCRETE = "stack_discrete"
Registry.KIND_HYBRID = "hybrid"
Registry.KIND_PROC_COOLDOWN = "proc_cooldown"
Registry.KIND_REPLENISHMENT = "replenishment"
Registry.KIND_NONE = "none"

--- Ring slots: the main keystone inside, Until Death or Lone Wolf in the thin outer ring.
Registry.SLOT_INNER = "inner"
Registry.SLOT_OUTER = "outer"

--- Sources of an effective stack maximum, read from the observed buff instance.
-- `CAP_MAX_STACKS` `buff:max_stacks()`, the template or override maximum plus extra stacks (only
-- for templates without a stack offset, which it would add);
-- `CAP_MAX_STACKS_CAP` `buff:max_stacks_cap()`, the cap plus extra cap, without the offset;
-- `CAP_TEMPLATE_DATA` `buff:template_data().max_stacks`, set by the buff's own `start_func`;
-- `CAP_CHILD_TEMPLATE` `max_stacks` of a parent buff's child template, without the baseline stack;
-- `CAP_TALENT_RESOURCE` the `talent_resource` component's `max_resource`.
Registry.CAP_MAX_STACKS = "max_stacks"
Registry.CAP_MAX_STACKS_CAP = "max_stacks_cap"
Registry.CAP_TEMPLATE_DATA = "template_data"
Registry.CAP_CHILD_TEMPLATE = "child_template"
Registry.CAP_TALENT_RESOURCE = "talent_resource"

--- Gate conditions: the selected Blitz is wielded.
Registry.GATE_BLITZ_WIELDED = "blitz_wielded"

--- Values of the below-maximum visibility settings.
Registry.VISIBILITY_BELOW_MAX = "below_max"
Registry.VISIBILITY_ALWAYS = "always"

--- Stack decay styles.
Registry.DECAY_STABLE = "stable"
Registry.DECAY_PROGRESSIVE = "progressive"

local KIND_DURATION = Registry.KIND_DURATION
local KIND_STACK_DECAY = Registry.KIND_STACK_DECAY
local KIND_STACK_SHARED = Registry.KIND_STACK_SHARED
local KIND_STACK_DISCRETE = Registry.KIND_STACK_DISCRETE
local KIND_HYBRID = Registry.KIND_HYBRID
local KIND_PROC_COOLDOWN = Registry.KIND_PROC_COOLDOWN
local KIND_REPLENISHMENT = Registry.KIND_REPLENISHMENT
local KIND_NONE = Registry.KIND_NONE
local SLOT_INNER = Registry.SLOT_INNER
local SLOT_OUTER = Registry.SLOT_OUTER
local CAP_MAX_STACKS = Registry.CAP_MAX_STACKS
local CAP_MAX_STACKS_CAP = Registry.CAP_MAX_STACKS_CAP
local CAP_TEMPLATE_DATA = Registry.CAP_TEMPLATE_DATA
local CAP_CHILD_TEMPLATE = Registry.CAP_CHILD_TEMPLATE
local CAP_TALENT_RESOURCE = Registry.CAP_TALENT_RESOURCE
local DECAY_STABLE = Registry.DECAY_STABLE

--- Settings group of each archetype, in menu order.
Registry.ARCHETYPES = {
    { name = "veteran", group = "veteran_group" },
    { name = "zealot", group = "zealot_group" },
    { name = "ogryn", group = "ogryn_group" },
    { name = "psyker", group = "psyker_group" },
    { name = "adamant", group = "adamant_group" },
    { name = "broker", group = "broker_group" },
    { name = "cryptic", group = "cryptic_group" }
}

--- Dropdown options of the below-maximum visibility settings.
local VISIBILITY_OPTIONS = {
    { text = "visibility_below_max", value = Registry.VISIBILITY_BELOW_MAX },
    { text = "visibility_always", value = Registry.VISIBILITY_ALWAYS }
}

-- ----------------------------------------------------------------------------
-- Entries
-- ----------------------------------------------------------------------------

--- Every keystone, in menu order within its archetype. Within one slot, the first selected and
-- enabled entry owns the ring; the talent trees allow only one main keystone per character.
Registry.ENTRIES = {
    -- Veteran ----------------------------------------------------------------
    {
        -- Stacks decay one at a time on a renewable timer.
        id = "marksmans_focus",
        archetype = "veteran",
        talent = "veteran_snipers_focus",
        kind = KIND_STACK_DECAY,
        slot = SLOT_INNER,
        detect = { "veteran_snipers_focus" },
        buffs = { "veteran_snipers_focus_stat_buff", "veteran_snipers_focus_stat_buff_increased_stacks" },
        cap = CAP_MAX_STACKS,
        decay_style = DECAY_STABLE
    },
    {
        -- Held tagging resource in the talent_resource component; the cap is set by the controller.
        id = "focus_target",
        archetype = "veteran",
        talent = "veteran_improved_tag",
        kind = KIND_STACK_DISCRETE,
        slot = SLOT_INNER,
        detect = { "veteran_improved_tag" },
        buffs = { "veteran_improved_tag" },
        cap = CAP_TEMPLATE_DATA
    },
    {
        -- The active buff of the wielded weapon first, otherwise the resource for the next switch.
        id = "weapons_specialist",
        archetype = "veteran",
        talent = "veteran_weapon_switch_passive",
        kind = KIND_HYBRID,
        slot = SLOT_INNER,
        detect = { "veteran_weapon_switch_passive_buff" },
        active = { "veteran_weapon_switch_ranged_buff", "veteran_weapon_switch_melee_buff" },
        by_slot = {
            slot_primary = "veteran_weapon_switch_ranged_visual",
            slot_secondary = "veteran_weapon_switch_melee_visual"
        },
        cap = CAP_MAX_STACKS
    },
    -- Zealot -----------------------------------------------------------------
    {
        -- The rescue proc's protection, then its cooldown; hidden while ready.
        id = "until_death",
        archetype = "zealot",
        talent = "zealot_resist_death",
        kind = KIND_PROC_COOLDOWN,
        slot = SLOT_OUTER,
        detect = { "zealot_resist_death" },
        buffs = { "zealot_resist_death" },
        cooldown_setting = "until_death_show_cooldown"
    },
    {
        -- The personal buff at full Fury first, otherwise the held Fury.
        id = "blazing_piety",
        archetype = "zealot",
        talent = "zealot_fanatic_rage",
        kind = KIND_HYBRID,
        slot = SLOT_INNER,
        detect = { "zealot_fanatic_rage" },
        active = { "zealot_fanatic_rage_buff" },
        buffs = { "zealot_fanatic_rage" },
        cap = CAP_TALENT_RESOURCE
    },
    {
        -- Stacks derived from missing health segments, against the keystone's strength cap.
        id = "martyrdom",
        archetype = "zealot",
        talent = "zealot_martyrdom",
        kind = KIND_STACK_DISCRETE,
        slot = SLOT_INNER,
        detect = { "zealot_martyrdom_base" },
        buffs = { "zealot_martyrdom_base" },
        cap = CAP_TEMPLATE_DATA
    },
    {
        -- The active buff first, otherwise the held Momentum (child stacks without the baseline).
        id = "inexorable_judgement",
        archetype = "zealot",
        talent = "zealot_quickness_passive",
        kind = KIND_HYBRID,
        slot = SLOT_INNER,
        detect = { "zealot_quickness_passive" },
        active = { "zealot_quickness_active", "zealot_quickness_active_increased_duration" },
        buffs = { "zealot_quickness_passive" },
        cap = CAP_CHILD_TEMPLATE
    },
    -- Ogryn ------------------------------------------------------------------
    {
        -- All stacks share one refreshable timer.
        id = "heavy_hitter",
        archetype = "ogryn",
        talent = "ogryn_passive_heavy_hitter",
        kind = KIND_STACK_SHARED,
        slot = SLOT_INNER,
        detect = { "ogryn_passive_heavy_hitter" },
        buffs = { "ogryn_heavy_hitter_damage_effect" },
        cap = CAP_MAX_STACKS
    },
    {
        -- All stacks share one refreshable timer.
        id = "burst_limiter_override",
        archetype = "ogryn",
        talent = "ogryn_leadbelcher_no_ammo_chance",
        kind = KIND_STACK_SHARED,
        slot = SLOT_INNER,
        detect = { "ogryn_blo_new_passive" },
        buffs = { "ogryn_blo_stacking_buff" },
        cap = CAP_MAX_STACKS
    },
    {
        -- Strength stacks (child stacks without the baseline); shown below the maximum by default.
        id = "feel_no_pain",
        archetype = "ogryn",
        talent = "ogryn_carapace_armor",
        kind = KIND_STACK_DISCRETE,
        slot = SLOT_INNER,
        detect = { "ogryn_carapace_armor_parent" },
        buffs = { "ogryn_carapace_armor_parent" },
        cap = CAP_CHILD_TEMPLATE,
        visibility_setting = "feel_no_pain_visibility",
        settle = 0.5
    },
    -- Psyker -----------------------------------------------------------------
    {
        -- Warp Charges decay one at a time on a renewable timer.
        id = "warp_siphon",
        archetype = "psyker",
        talent = "psyker_passive_souls_from_elite_kills",
        kind = KIND_STACK_DECAY,
        slot = SLOT_INNER,
        detect = { "psyker_passive_souls_from_elite_kills" },
        buffs = { "psyker_souls", "psyker_souls_increased_max_stacks" },
        cap = CAP_MAX_STACKS,
        decay_style = DECAY_STABLE
    },
    {
        -- Stacks decay one at a time on a renewable timer; the variant sets cap and duration.
        id = "disrupt_destiny",
        archetype = "psyker",
        talent = "psyker_new_mark_passive",
        kind = KIND_STACK_DECAY,
        slot = SLOT_INNER,
        detect = { "psyker_marked_enemies_passive" },
        buffs = {
            "psyker_marked_enemies_passive_bonus_stacking",
            "psyker_marked_enemies_passive_bonus_stacking_increased_stacks",
            "psyker_marked_enemies_passive_bonus_stacking_increased_duration"
        },
        cap = CAP_MAX_STACKS,
        decay_style = DECAY_STABLE
    },
    {
        -- Stored charges; the capacity is set by the visual buff, overflow stacks are excluded.
        id = "empowered_psionics",
        archetype = "psyker",
        talent = "psyker_empowered_ability",
        kind = KIND_STACK_DISCRETE,
        slot = SLOT_INNER,
        detect = { "psyker_empowered_grenades_passive", "psyker_empowered_grenades_passive_improved" },
        buffs = { "psyker_empowered_grenades_passive_visual_buff", "psyker_empowered_grenades_passive_visual_buff_increased" },
        cap = CAP_TEMPLATE_DATA,
        gate = Registry.GATE_BLITZ_WIELDED,
        gate_setting = "empowered_psionics_blitz_only"
    },
    -- Arbitrator -------------------------------------------------------------
    {
        -- The personal buff's remaining time.
        id = "execution_order",
        archetype = "adamant",
        talent = "adamant_execution_order",
        kind = KIND_DURATION,
        slot = SLOT_INNER,
        detect = { "adamant_execution_order" },
        active = { "adamant_execution_order_buff" }
    },
    {
        -- The active main effect first, otherwise the pool for the next weapon switch.
        id = "terminus_warrant",
        archetype = "adamant",
        talent = "adamant_terminus_warrant",
        kind = KIND_HYBRID,
        slot = SLOT_INNER,
        detect = { "adamant_terminus_warrant" },
        active = {
            "adamant_terminus_warrant_melee_stat_buff",
            "adamant_terminus_warrant_ranged_stat_buff",
            "adamant_terminus_warrant_melee_stat_buff_improved",
            "adamant_terminus_warrant_ranged_stat_buff_improved"
        },
        by_slot = {
            slot_primary = "adamant_terminus_warrant_ranged",
            slot_secondary = "adamant_terminus_warrant_melee"
        },
        cap = CAP_MAX_STACKS
    },
    {
        -- Core stacks decay one at a time on a renewable timer.
        id = "forceful",
        archetype = "adamant",
        talent = "adamant_forceful",
        kind = KIND_STACK_DECAY,
        slot = SLOT_INNER,
        detect = { "adamant_forceful" },
        buffs = { "adamant_forceful_stacks" },
        cap = CAP_MAX_STACKS,
        decay_style = DECAY_STABLE
    },
    {
        -- Time until the next automatic Blitz charge, only while charges are missing.
        id = "lone_wolf",
        archetype = "adamant",
        talent = "adamant_disable_companion",
        kind = KIND_REPLENISHMENT,
        slot = SLOT_OUTER,
        detect = { "adamant_grenade_replenishment" },
        buffs = { "adamant_grenade_replenishment" }
    },
    {
        -- Permanent companion specialisation: recognised, never drawn.
        id = "go_get_em",
        archetype = "adamant",
        talent = "adamant_companion_focus_ranged",
        kind = KIND_NONE,
        detect = { "adamant_companion_focus_ranged" }
    },
    {
        -- Permanent companion specialisation: recognised, never drawn.
        id = "unleashed_brutality",
        archetype = "adamant",
        talent = "adamant_companion_focus_elite",
        kind = KIND_NONE,
        detect = { "adamant_companion_focus_elite" }
    },
    -- Hive Scum --------------------------------------------------------------
    {
        -- All stacks share one refreshable timer; the upgrade extends the instance's duration.
        id = "vultures_mark",
        archetype = "broker",
        talent = "broker_keystone_vultures_mark_on_kill",
        kind = KIND_STACK_SHARED,
        slot = SLOT_INNER,
        detect = { "broker_keystone_vultures_mark_on_kill" },
        buffs = { "vultures_mark" },
        cap = CAP_MAX_STACKS
    },
    {
        -- Frenzy's remaining time first, otherwise the build-up stacks.
        id = "adrenaline_frenzy",
        archetype = "broker",
        talent = "broker_keystone_adrenaline_junkie",
        kind = KIND_HYBRID,
        slot = SLOT_INNER,
        detect = { "broker_keystone_adrenaline_junkie" },
        active = { "broker_keystone_adrenaline_junkie_proc" },
        buffs = { "broker_keystone_adrenaline_junkie_stack" },
        cap = CAP_MAX_STACKS
    },
    {
        -- Stacks decay one at a time on a renewable timer; the upgrade changes cap and duration.
        id = "chemical_dependency",
        archetype = "broker",
        talent = "broker_keystone_chemical_dependency",
        kind = KIND_STACK_DECAY,
        slot = SLOT_INNER,
        detect = { "broker_keystone_chemical_dependency" },
        buffs = { "broker_keystone_chemical_dependency_stack" },
        cap = CAP_MAX_STACKS_CAP,
        decay_style = DECAY_STABLE
    },
    -- Skitarius --------------------------------------------------------------
    {
        -- Core stacks decay one at a time on a renewable timer; the talent adds an extra stack.
        id = "redline_capacitors",
        archetype = "cryptic",
        talent = "cryptic_redline",
        kind = KIND_STACK_DECAY,
        slot = SLOT_INNER,
        detect = { "cryptic_redline" },
        buffs = { "cryptic_redline_stack" },
        cap = CAP_MAX_STACKS_CAP,
        decay_style = DECAY_STABLE
    },
    {
        -- The received Power Overload buff first, otherwise the charge toward the threshold.
        id = "power_overload",
        archetype = "cryptic",
        talent = "cryptic_overload_keystone",
        kind = KIND_HYBRID,
        slot = SLOT_INNER,
        detect = { "cryptic_overload_keystone" },
        active = { "cryptic_overload_keystone_allies_buff" },
        buffs = { "cryptic_overload_keystone_stack" },
        cap = CAP_MAX_STACKS_CAP
    },
    {
        -- Strength stacks without the baseline; shown below the maximum by default.
        id = "flensing_protocols",
        archetype = "cryptic",
        talent = "cryptic_dissector",
        kind = KIND_STACK_DISCRETE,
        slot = SLOT_INNER,
        detect = { "cryptic_dissector" },
        buffs = { "cryptic_dissector_stack" },
        cap = CAP_MAX_STACKS_CAP,
        visibility_setting = "flensing_protocols_visibility",
        settle = 0.5
    }
}

--- Extra DMF settings, by entry id, shown right after the entry's checkbox; without `setting_id`,
-- `title` and `tooltip`, which `_extra_widget` adds.
local EXTRA_SETTINGS = {
    until_death = {
        { id = "until_death_show_cooldown", type = "checkbox", default_value = true }
    },
    feel_no_pain = {
        { id = "feel_no_pain_visibility", type = "dropdown", default_value = Registry.VISIBILITY_BELOW_MAX, options = VISIBILITY_OPTIONS }
    },
    empowered_psionics = {
        { id = "empowered_psionics_blitz_only", type = "checkbox", default_value = false }
    },
    flensing_protocols = {
        { id = "flensing_protocols_visibility", type = "dropdown", default_value = Registry.VISIBILITY_BELOW_MAX, options = VISIBILITY_OPTIONS }
    }
}

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

--- Returns a deep copy of a value; other values than tables are returned as they are.
-- DMF localizes dropdown option texts in place and stores default values, so no two widgets may
-- share a table.
-- param: value value to copy
-- treturn: param the copy
local function _copy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, item in pairs(value) do
        copy[key] = _copy(item)
    end

    return copy
end

--- Returns whether an entry draws a ring and so has an enable checkbox.
-- tab: entry registry entry
-- treturn: bool
Registry.is_renderable = function (entry)
    return entry.kind ~= KIND_NONE
end

--- Returns the DMF widget of an extra setting, as a new table.
-- tab: extra extra setting definition
-- treturn: tab DMF widget definition
local function _extra_widget(extra)
    local widget = {
        setting_id = extra.id,
        type = extra.type,
        default_value = extra.default_value,
        tooltip = extra.id .. "_tooltip"
    }

    if extra.options then
        widget.options = _copy(extra.options)
    end

    return widget
end

-- ----------------------------------------------------------------------------
-- Settings menu
-- ----------------------------------------------------------------------------

--- Appends one archetype's widgets: each renderable entry's enable checkbox, titled by its id,
-- followed by its extra settings. Entries without a ring get no widget.
-- tab: sub_widgets DMF widget list to append to
-- string: archetype archetype name
Registry.append_widgets = function (sub_widgets, archetype)
    local entries = Registry.ENTRIES

    for i = 1, #entries do
        local entry = entries[i]

        if entry.archetype == archetype and Registry.is_renderable(entry) then
            sub_widgets[#sub_widgets + 1] = {
                setting_id = entry.id,
                type = "checkbox",
                default_value = true,
                tooltip = entry.id .. "_tooltip"
            }

            local extras = EXTRA_SETTINGS[entry.id]

            if extras then
                for j = 1, #extras do
                    sub_widgets[#sub_widgets + 1] = _extra_widget(extras[j])
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Runtime
-- ----------------------------------------------------------------------------

--- Adds every entry setting to a settings cache: each default to `settings` by setting id, and each
-- setting id to `setting_ids`, in menu order.
-- tab: settings settings cache by setting id
-- tab: setting_ids list of cached setting ids
Registry.add_settings = function (settings, setting_ids)
    local entries = Registry.ENTRIES

    for i = 1, #entries do
        local entry = entries[i]

        if Registry.is_renderable(entry) then
            settings[entry.id] = true
            setting_ids[#setting_ids + 1] = entry.id

            local extras = EXTRA_SETTINGS[entry.id]

            if extras then
                for j = 1, #extras do
                    local extra = extras[j]

                    settings[extra.id] = extra.default_value
                    setting_ids[#setting_ids + 1] = extra.id
                end
            end
        end
    end
end

return Registry
