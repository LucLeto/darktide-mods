--- Perfect Keystones' DMF mod data; the mod description and the settings menu.
-- The returned table names the mod, makes it togglable and declares ten groups. `Ring`: crosshair
-- following, the inner ring's size and thickness, the outer ring's gap and thickness, horizontal
-- and vertical offset, pulses and the stack and time labels. `Appearance`: the active, unfilled,
-- expiring and cooldown colours and the near-expiry threshold. One group per archetype (Veteran,
-- Zealot, Ogryn, Psyker, Arbitrator, Hive Scum, Skitarius) with an enable checkbox for each of its
-- keystones that draws a ring, 23 in all. Until Death's cooldown display, Feel No Pain's and
-- Flensing Protocols' visibility and Empowered Psionics' Blitz-only visibility are nested under
-- their keystone's checkbox, so DMF indents them there and hides them while it is off.
-- `Miscellaneous`: debug output. Go Get 'Em! and Unleashed Brutality draw no ring and have no
-- checkbox. Every option has a tooltip. Colours are DMF colour pickers with alpha, stored as
-- `{ a, r, g, b }`.
--
-- The ring and appearance groups are built from `PerfectKeystones_ring_settings.lua` and the
-- archetype groups from `PerfectKeystones_registry.lua`, which also hold their defaults; the debug
-- setting's default here must match the `settings` table in `PerfectKeystones.lua`, which caches
-- the values at runtime. Loaded by DMF as `mod_data`, as declared in `PerfectKeystones.mod`.
-- module: PerfectKeystones_data
-- author: LucLeto
local mod = get_mod("PerfectKeystones")
local RingSettings = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones_ring_settings")
local Registry = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones_registry")

--- The `Ring` group.
local ring_widgets = {}

RingSettings.append_widgets(ring_widgets, RingSettings.RING_IDS)

--- The `Appearance` group.
local appearance_widgets = {}

RingSettings.append_widgets(appearance_widgets, RingSettings.APPEARANCE_IDS)

--- Every group, in menu order: ring, appearance, one per archetype, miscellaneous.
local groups = {
    {
        setting_id = "ring_group",
        type = "group",
        tooltip = "ring_group_tooltip",
        sub_widgets = ring_widgets
    },
    {
        setting_id = "appearance_group",
        type = "group",
        tooltip = "appearance_group_tooltip",
        sub_widgets = appearance_widgets
    }
}

for i = 1, #Registry.ARCHETYPES do
    local archetype = Registry.ARCHETYPES[i]
    local sub_widgets = {}

    Registry.append_widgets(sub_widgets, archetype.name)

    groups[#groups + 1] = {
        setting_id = archetype.group,
        type = "group",
        tooltip = archetype.group .. "_tooltip",
        sub_widgets = sub_widgets
    }
end

groups[#groups + 1] = {
    setting_id = "misc_group",
    type = "group",
    tooltip = "misc_group_tooltip",
    sub_widgets = {
        {
            setting_id = "debug_logging",
            type = "checkbox",
            default_value = false,
            tooltip = "debug_logging_tooltip"
        }
    }
}

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = groups
    }
}
