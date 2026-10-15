--- Perfect Thrust's DMF mod data; the mod description and the settings menu.
-- The returned table names the mod, makes it togglable and declares three groups. `Charge
-- indicator`: display mode, READY timing, heavy attack threshold, crosshair following, ring size,
-- thickness, horizontal and vertical offset, READY pulse and the unfilled, charging, heavy attack
-- available, READY and READY pulse colours. `Aiming indicator`: the aiming blessings switch and
-- the aiming ring's own display mode, crosshair following, size, thickness, offsets, READY pulse
-- and colours, without the heavy attack available colour. `Miscellaneous`: debug output, which
-- covers both rings. Every option has a tooltip. Colours are DMF colour pickers with alpha,
-- stored as `{ a, r, g, b }`; the melee ring's alpha replaces the opacity setting of earlier
-- versions, which `PerfectThrust.lua` migrates once.
--
-- The ring settings of both groups are built from `PerfectThrust_ring_settings.lua`, which also
-- holds their defaults; the other settings' defaults here must match the `settings` table in
-- `PerfectThrust.lua`, which caches the values at runtime. Loaded by DMF as `mod_data`, as declared
-- in `PerfectThrust.mod`.
-- module: PerfectThrust_data
-- author: LucLeto
local mod = get_mod("PerfectThrust")
local RingSettings = mod:io_dofile("PerfectThrust/scripts/mods/PerfectThrust/PerfectThrust_ring_settings")

local ADS_PREFIX = RingSettings.ADS_PREFIX
local APPEARANCE_IDS = RingSettings.APPEARANCE_IDS

--- The `Charge indicator` group: the melee ring.
local charge_widgets = {
    RingSettings.widget("", "display_mode"),
    {
        setting_id = "timing_mode",
        type = "dropdown",
        default_value = "predicted",
        tooltip = "timing_mode_tooltip",
        options = {
            { text = "timing_mode_predicted", value = "predicted" },
            { text = "timing_mode_confirmed", value = "confirmed" }
        }
    },
    {
        setting_id = "show_heavy_threshold",
        type = "checkbox",
        default_value = true,
        tooltip = "show_heavy_threshold_tooltip"
    }
}

RingSettings.append_widgets(charge_widgets, "", APPEARANCE_IDS)

--- The `Aiming indicator` group: the aiming ring.
local aim_widgets = {
    {
        setting_id = "show_ads_blessings",
        type = "checkbox",
        default_value = true,
        tooltip = "show_ads_blessings_tooltip"
    },
    RingSettings.widget(ADS_PREFIX, "display_mode")
}

RingSettings.append_widgets(aim_widgets, ADS_PREFIX, APPEARANCE_IDS)

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "indicator_group",
                type = "group",
                tooltip = "indicator_group_tooltip",
                sub_widgets = charge_widgets
            },
            {
                setting_id = "aim_indicator_group",
                type = "group",
                tooltip = "aim_indicator_group_tooltip",
                sub_widgets = aim_widgets
            },
            {
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
        }
    }
}
