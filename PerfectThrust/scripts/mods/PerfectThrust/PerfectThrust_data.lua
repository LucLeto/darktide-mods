--- Perfect Thrust's DMF mod data; the mod description and the settings menu.
-- The returned table names the mod, makes it togglable and declares one `Charge indicator`
-- group: display mode, READY timing, ring size, thickness, horizontal and vertical offset,
-- READY pulse, the unfilled, charging, READY and READY pulse colours and debug output. Every
-- option has a `<setting_id>_tooltip`. Colours are DMF colour pickers with alpha, stored as
-- `{ a, r, g, b }`; their alpha replaces the opacity setting of earlier versions, which
-- `PerfectThrust.lua` migrates once.
--
-- Loaded by DMF as `mod_data`, as declared in `PerfectThrust.mod`. The defaults here must match
-- the `settings` table in `PerfectThrust.lua`, which caches the values at runtime.
-- module: PerfectThrust_data
-- author: LucLeto
local mod = get_mod("PerfectThrust")

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
                sub_widgets = {
                    {
                        setting_id = "display_mode",
                        type = "dropdown",
                        default_value = "progress",
                        tooltip = "display_mode_tooltip",
                        options = {
                            { text = "display_mode_progress", value = "progress" },
                            { text = "display_mode_ready_only", value = "ready_only" }
                        }
                    },
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
                        setting_id = "ring_radius",
                        type = "numeric",
                        default_value = 32,
                        range = { 12, 150 },
                        decimals_number = 0,
                        step_size_value = 1,
                        tooltip = "ring_radius_tooltip"
                    },
                    {
                        setting_id = "ring_thickness",
                        type = "numeric",
                        default_value = 3,
                        range = { 1, 10 },
                        decimals_number = 0,
                        step_size_value = 1,
                        tooltip = "ring_thickness_tooltip"
                    },
                    {
                        setting_id = "offset_x",
                        type = "numeric",
                        default_value = 0,
                        range = { -960, 960 },
                        decimals_number = 0,
                        step_size_value = 1,
                        tooltip = "offset_x_tooltip"
                    },
                    {
                        setting_id = "offset_y",
                        type = "numeric",
                        default_value = 0,
                        range = { -540, 540 },
                        decimals_number = 0,
                        step_size_value = 1,
                        tooltip = "offset_y_tooltip"
                    },
                    {
                        setting_id = "ready_pulse",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "ready_pulse_tooltip"
                    },
                    {
                        setting_id = "unfilled_color",
                        type = "color",
                        default_value = { 80, 70, 82, 86 }, -- ARGB
                        has_alpha = true,
                        tooltip = "unfilled_color_tooltip"
                    },
                    {
                        setting_id = "charging_color",
                        type = "color",
                        default_value = { 235, 240, 190, 90 }, -- ARGB
                        has_alpha = true,
                        tooltip = "charging_color_tooltip"
                    },
                    {
                        setting_id = "ready_color",
                        type = "color",
                        default_value = { 255, 120, 225, 140 }, -- ARGB
                        has_alpha = true,
                        tooltip = "ready_color_tooltip"
                    },
                    {
                        setting_id = "ready_pulse_color",
                        type = "color",
                        default_value = { 255, 120, 225, 140 }, -- ARGB, the READY colour
                        has_alpha = true,
                        tooltip = "ready_pulse_color_tooltip"
                    },
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
