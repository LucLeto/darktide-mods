local mod = get_mod("OverflowMeter")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "overflow_meter_group",
                type = "group",
                tooltip = "overflow_meter_group_tooltip",
                sub_widgets = {
                    {
                        setting_id = "meter_style",
                        type = "dropdown",
                        default_value = "both",
                        tooltip = "meter_style_tooltip",
                        options = {
                            { text = "meter_style_gauge", value = "gauge" },
                            { text = "meter_style_text", value = "text" },
                            { text = "meter_style_both", value = "both" },
                            { text = "meter_style_none", value = "none" }
                        }
                    },
                    {
                        setting_id = "show_title",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "show_title_tooltip"
                    },
                    {
                        setting_id = "show_rate",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "show_rate_tooltip"
                    },
                    {
                        setting_id = "rate_mode",
                        type = "dropdown",
                        default_value = "total",
                        tooltip = "rate_mode_tooltip",
                        options = {
                            { text = "rate_mode_total", value = "total" },
                            { text = "rate_mode_per_ally", value = "per_ally" }
                        }
                    },
                    {
                        setting_id = "show_allies_count",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "show_allies_count_tooltip"
                    },
                    {
                        setting_id = "show_allies_missing",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "show_allies_missing_tooltip"
                    },
                    {
                        setting_id = "show_inactive_state",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "show_inactive_state_tooltip"
                    },
                    {
                        setting_id = "show_tier_labels",
                        type = "checkbox",
                        default_value = false,
                        tooltip = "show_tier_labels_tooltip"
                    },
                    {
                        setting_id = "rate_window",
                        type = "numeric",
                        default_value = 2,
                        range = { 1, 3 },
                        decimals_number = 1,
                        step_size_value = 0.5,
                        tooltip = "rate_window_tooltip"
                    },
                    {
                        setting_id = "widget_x",
                        type = "numeric",
                        default_value = 30,
                        range = { 0, 1820 },
                        decimals_number = 0,
                        step_size_value = 10,
                        tooltip = "widget_x_tooltip"
                    },
                    {
                        setting_id = "widget_y",
                        type = "numeric",
                        default_value = 420,
                        range = { 0, 1020 },
                        decimals_number = 0,
                        step_size_value = 10,
                        tooltip = "widget_y_tooltip"
                    },
                    {
                        setting_id = "widget_scale",
                        type = "numeric",
                        default_value = 100,
                        range = { 25, 300 },
                        decimals_number = 0,
                        step_size_value = 5,
                        tooltip = "widget_scale_tooltip"
                    },
                    {
                        setting_id = "widget_opacity",
                        type = "numeric",
                        default_value = 100,
                        range = { 20, 100 },
                        decimals_number = 0,
                        step_size_value = 5,
                        tooltip = "widget_opacity_tooltip"
                    }
                }
            },
            {
                setting_id = "mission_summary_group",
                type = "group",
                tooltip = "mission_summary_group_tooltip",
                sub_widgets = {
                    {
                        setting_id = "summary_keybind",
                        type = "keybind",
                        default_value = {},
                        keybind_trigger = "held",
                        keybind_type = "function_call",
                        function_name = "hold_mission_summary",
                        tooltip = "summary_keybind_tooltip"
                    },
                    {
                        setting_id = "show_summary",
                        type = "checkbox",
                        default_value = false,
                        tooltip = "show_summary_tooltip"
                    },
                    {
                        setting_id = "summary_chat_on_end",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "summary_chat_on_end_tooltip"
                    },
                    {
                        setting_id = "scoreboard_row_generated",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "scoreboard_row_generated_tooltip"
                    },
                    {
                        setting_id = "scoreboard_row_replenished",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "scoreboard_row_replenished_tooltip"
                    },
                    {
                        setting_id = "scoreboard_row_overflowed",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "scoreboard_row_overflowed_tooltip"
                    },
                    {
                        setting_id = "scoreboard_row_shared",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "scoreboard_row_shared_tooltip"
                    },
                    {
                        setting_id = "scoreboard_row_efficiency",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "scoreboard_row_efficiency_tooltip"
                    },
                    {
                        setting_id = "share_mission_summary",
                        type = "checkbox",
                        default_value = true,
                        tooltip = "share_mission_summary_tooltip"
                    },
                    {
                        setting_id = "summary_x",
                        type = "numeric",
                        default_value = 1630,
                        range = { 0, 1820 },
                        decimals_number = 0,
                        step_size_value = 10,
                        tooltip = "summary_x_tooltip"
                    },
                    {
                        setting_id = "summary_y",
                        type = "numeric",
                        default_value = 850,
                        range = { 0, 1020 },
                        decimals_number = 0,
                        step_size_value = 10,
                        tooltip = "summary_y_tooltip"
                    }
                }
            }
        }
    }
}
