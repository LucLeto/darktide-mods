--- Icon Browser's DMF mod data; the mod description and the settings menu.
-- The returned table names the mod, makes it togglable and declares two groups, which DMF shows as
-- native tabs. `Browser`: the Open Icon Browser keybind (F8 by default, a global `function_call`
-- keybind of `toggle_icon_browser`), Thumbnail Density, Inspector Width, Double-Click Copies Path,
-- C Key Copies Path, two buttons that clear the recent history and, held to confirm, the favorites,
-- and a button that copies the paths of the icons whose material is not loaded. `Window`: the
-- frame's Window Size, X and Y position, a button that centres it again,
-- the move step and four optional move keybinds.
--
-- Titles come from each `setting_id`, tooltips and button texts are localization ids that DMF
-- resolves. The settings are read through the getters in `IconBrowser.lua`, which clamp or validate
-- them and fall back to the defaults declared here; buttons call the `mod` function named by their
-- `function_name`. The view stores further state with `mod:set` under ids that have no widget here:
-- view mode, category, sort, preview background, favorites and the recent history.
--
-- Uses the group tabs and button widgets of DMF 26.10.22 and newer. Loaded by DMF as `mod_data`, as
-- declared in `IconBrowser.mod`.
-- module: IconBrowser_data
-- author: LucLeto
local mod = get_mod("IconBrowser")

--- The `Browser` tab: opening the browser, its layout, copy shortcuts, its saved lists and the list of
-- icons that are not loaded.
local browser_widgets = {
    {
        setting_id = "open_icon_browser",
        type = "keybind",
        default_value = { "keyboard_f8" },
        keybind_global = true,
        keybind_trigger = "pressed",
        keybind_type = "function_call",
        function_name = "toggle_icon_browser",
        tooltip = "open_tooltip",
    },
    {
        setting_id = "icon_browser_density",
        type = "dropdown",
        default_value = "normal",
        options = {
            { text = "density_option_compact", value = "compact" },
            { text = "density_option_normal", value = "normal" },
            { text = "density_option_large", value = "large" },
        },
        tooltip = "density_tooltip",
    },
    {
        setting_id = "icon_browser_inspector_width",
        type = "numeric",
        default_value = 28,
        range = { 25, 40 },
        decimals_number = 0,
        step_size_value = 1,
        tooltip = "inspector_width_tooltip",
    },
    {
        setting_id = "icon_browser_double_click_copy",
        type = "checkbox",
        default_value = true,
        tooltip = "double_click_copy_tooltip",
    },
    {
        setting_id = "icon_browser_copy_hotkey",
        type = "checkbox",
        default_value = true,
        tooltip = "copy_hotkey_tooltip",
    },
    {
        setting_id = "clear_icon_browser_recent",
        type = "button",
        button_text = "clear_recent_button",
        function_name = "clear_icon_browser_recent",
        tooltip = "clear_recent_tooltip",
    },
    {
        setting_id = "clear_icon_browser_favorites",
        type = "button",
        button_text = "clear_favorites_button",
        button_trigger = "held",
        button_hold_duration = 2,
        function_name = "clear_icon_browser_favorites",
        tooltip = "clear_favorites_tooltip",
    },
    {
        setting_id = "copy_unloaded_icon_paths",
        type = "button",
        button_text = "copy_unloaded_button",
        function_name = "copy_unloaded_icon_paths",
        tooltip = "copy_unloaded_tooltip",
    },
}

--- The `Window` tab: the frame's size and position and the keybinds that move it.
local window_widgets = {
    {
        setting_id = "icon_browser_scale",
        type = "numeric",
        default_value = 100,
        range = { 50, 100 },
        decimals_number = 0,
        step_size_value = 5,
        tooltip = "size_tooltip",
    },
    {
        setting_id = "icon_browser_pos_x",
        type = "numeric",
        default_value = 0,
        range = { -12000, 12000 },
        decimals_number = 0,
        step_size_value = 5,
        tooltip = "position_x_tooltip",
    },
    {
        setting_id = "icon_browser_pos_y",
        type = "numeric",
        default_value = 0,
        range = { -12000, 12000 },
        decimals_number = 0,
        step_size_value = 5,
        tooltip = "position_y_tooltip",
    },
    {
        setting_id = "reset_icon_browser_position",
        type = "button",
        button_text = "reset_position_button",
        function_name = "reset_icon_browser_position",
        tooltip = "reset_position_tooltip",
    },
    {
        setting_id = "icon_browser_move_step",
        type = "numeric",
        default_value = 10,
        range = { 1, 200 },
        decimals_number = 0,
        step_size_value = 1,
        tooltip = "move_step_tooltip",
    },
    {
        setting_id = "move_icon_browser_left_key",
        type = "keybind",
        default_value = {},
        keybind_trigger = "pressed",
        keybind_type = "function_call",
        function_name = "move_icon_browser_left",
        tooltip = "move_left_tooltip",
    },
    {
        setting_id = "move_icon_browser_right_key",
        type = "keybind",
        default_value = {},
        keybind_trigger = "pressed",
        keybind_type = "function_call",
        function_name = "move_icon_browser_right",
        tooltip = "move_right_tooltip",
    },
    {
        setting_id = "move_icon_browser_up_key",
        type = "keybind",
        default_value = {},
        keybind_trigger = "pressed",
        keybind_type = "function_call",
        function_name = "move_icon_browser_up",
        tooltip = "move_up_tooltip",
    },
    {
        setting_id = "move_icon_browser_down_key",
        type = "keybind",
        default_value = {},
        keybind_trigger = "pressed",
        keybind_type = "function_call",
        function_name = "move_icon_browser_down",
        tooltip = "move_down_tooltip",
    },
}

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "icon_browser_group",
                type = "group",
                sub_widgets = browser_widgets,
            },
            {
                setting_id = "icon_browser_window_group",
                type = "group",
                sub_widgets = window_widgets,
            },
        },
    },
}
