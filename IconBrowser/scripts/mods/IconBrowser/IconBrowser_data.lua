local mod = get_mod("IconBrowser")

return {
    mod_name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "open_icon_browser",
                type = "keybind",
                default_value = { "keyboard_f8" },
                keybind_global = true,
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "toggle_icon_browser",
                tooltip = mod:localize("open_tooltip"),
            },
            {
                setting_id = "icon_browser_scale",
                type = "numeric",
                default_value = 100,
                range = { 50, 200 },
                decimals_number = 0,
                step_size_value = 5,
                change = function(new_value)
                    mod:set_icon_browser_scale(new_value)
                end,
                get = function()
                    return mod:get_icon_browser_scale()
                end,
                tooltip = mod:localize("size_tooltip"),
            },
            {
                setting_id = "icon_browser_pos_x",
                type = "numeric",
                default_value = 0,
                range = { -12000, 12000 },
                decimals_number = 0,
                step_size_value = 5,
                change = function(new_value)
                    mod:set_icon_browser_position(new_value, nil)
                end,
                get = function()
                    return mod:get_icon_browser_offset_x()
                end,
                tooltip = mod:localize("position_x_tooltip"),
            },
            {
                setting_id = "icon_browser_pos_y",
                type = "numeric",
                default_value = 0,
                range = { -12000, 12000 },
                decimals_number = 0,
                step_size_value = 5,
                change = function(new_value)
                    mod:set_icon_browser_position(nil, new_value)
                end,
                get = function()
                    return mod:get_icon_browser_offset_y()
                end,
                tooltip = mod:localize("position_y_tooltip"),
            },
            {
                setting_id = "icon_browser_move_step",
                type = "numeric",
                default_value = 10,
                range = { 1, 200 },
                decimals_number = 0,
                step_size_value = 1,
                change = function(new_value)
                    mod:set_icon_browser_move_step(new_value)
                end,
                get = function()
                    return mod:get_icon_browser_move_step()
                end,
                tooltip = mod:localize("move_step_tooltip"),
            },
            {
                setting_id = "move_icon_browser_left_key",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "move_icon_browser_left",
                tooltip = mod:localize("move_left_tooltip"),
            },
            {
                setting_id = "move_icon_browser_right_key",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "move_icon_browser_right",
                tooltip = mod:localize("move_right_tooltip"),
            },
            {
                setting_id = "move_icon_browser_up_key",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "move_icon_browser_up",
                tooltip = mod:localize("move_up_tooltip"),
            },
            {
                setting_id = "move_icon_browser_down_key",
                type = "keybind",
                default_value = {},
                keybind_trigger = "pressed",
                keybind_type = "function_call",
                function_name = "move_icon_browser_down",
                tooltip = mod:localize("move_down_tooltip"),
            },
        },
    },
}
