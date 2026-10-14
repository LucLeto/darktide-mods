local mod = get_mod("ForDaEmprah")

local CLOCK_SLOTS = {
    "12",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "10",
    "11"
}

local COMMAND = {
    NONE = 0,
    FOR_THE_EMPEROR = 1,
    VACUUM_CAPSULE = 2,
    YES = 3,
    NO = 4,
    CRYONIC_ROD = 5,
    POWER_CELL = 6,
    SCRIPTURE = 7,
    GRIMOIRE = 8,
    RELIC = 9,
    HEALTH_BOOSTER = 10,
    MINE = 11,
    AMMO = 12,
    GRENADE = 13,
    PLASTEEL = 14,
    DIAMANTINE = 15,
    FOLLOWING = 16,
    MEDICAE_STATION = 17,
    UNCHARGED_MEDICAE = 18,
    MEDIPACK = 19,
    MEDIPACK_DOWN = 20,
    AMMO_CRATE = 21,
    NEED_AMMO = 22,
    NEED_HEALING = 23,
    LOOK_THERE = 24,
    GO_THERE = 25,
    ENEMY = 26,
    THANKS = 27,
    SORRY = 28
}

local DROPDOWN_OPTIONS = {
    { text = "option_nil",               value = COMMAND.NONE },
    { text = "option_ammo",              value = COMMAND.AMMO },
    { text = "option_ammo_crate",        value = COMMAND.AMMO_CRATE },
    { text = "option_cryonic_rod",       value = COMMAND.CRYONIC_ROD },
    { text = "option_diamantine",        value = COMMAND.DIAMANTINE },
    { text = "option_enemy",             value = COMMAND.ENEMY,            vanilla = true },
    { text = "option_following",         value = COMMAND.FOLLOWING },
    { text = "option_for_the_emperor",   value = COMMAND.FOR_THE_EMPEROR,  vanilla = true },
    { text = "option_go_there",          value = COMMAND.GO_THERE,         vanilla = true },
    { text = "option_grenade",           value = COMMAND.GRENADE },
    { text = "option_grimoire",          value = COMMAND.GRIMOIRE },
    { text = "option_health_booster",    value = COMMAND.HEALTH_BOOSTER },
    { text = "option_look_there",        value = COMMAND.LOOK_THERE,       vanilla = true },
    { text = "option_medicae_station",   value = COMMAND.MEDICAE_STATION },
    { text = "option_medipack",          value = COMMAND.MEDIPACK },
    { text = "option_medipack_down",     value = COMMAND.MEDIPACK_DOWN },
    { text = "option_mine",              value = COMMAND.MINE },
    { text = "option_need_ammo",         value = COMMAND.NEED_AMMO,        vanilla = true, stock_chat = true },
    { text = "option_need_healing",      value = COMMAND.NEED_HEALING,     vanilla = true, stock_chat = true },
    { text = "option_no",                value = COMMAND.NO },
    { text = "option_plasteel",          value = COMMAND.PLASTEEL },
    { text = "option_power_cell",        value = COMMAND.POWER_CELL },
    { text = "option_relic",             value = COMMAND.RELIC },
    { text = "option_scripture",         value = COMMAND.SCRIPTURE },
    { text = "option_sorry",             value = COMMAND.SORRY },
    { text = "option_thanks",            value = COMMAND.THANKS,           vanilla = true, stock_chat = true },
    { text = "option_uncharged_medicae", value = COMMAND.UNCHARGED_MEDICAE },
    { text = "option_vacuum_capsule",    value = COMMAND.VACUUM_CAPSULE },
    { text = "option_yes",               value = COMMAND.YES },
}

local DEFAULT_WHEEL_VALUES = {
    plugin_wheel_12 = COMMAND.GO_THERE,
    plugin_wheel_1 = COMMAND.ENEMY,
    plugin_wheel_2 = COMMAND.NONE,
    plugin_wheel_3 = COMMAND.NONE,
    plugin_wheel_4 = COMMAND.NEED_AMMO,
    plugin_wheel_5 = COMMAND.THANKS,
    plugin_wheel_6 = COMMAND.NEED_HEALING,
    plugin_wheel_7 = COMMAND.FOR_THE_EMPEROR,
    plugin_wheel_8 = COMMAND.NONE,
    plugin_wheel_9 = COMMAND.NONE,
    plugin_wheel_10 = COMMAND.NONE,
    plugin_wheel_11 = COMMAND.LOOK_THERE
}

-- Same limit as the game's chat input box.
local CHAT_MESSAGE_MAX_LENGTH = 200

local function wheel_setting_id(clock_slot)
    return "plugin_wheel_" .. clock_slot
end

-- Per-command settings are keyed by the command's display name, e.g. "option_sorry". The keybind keeps
-- the bare name and the chat toggle its "chat_" prefix, the ids earlier builds saved them under.
local function command_enabled_setting_id(display_name)
    return display_name .. "_enabled"
end

local function command_chat_setting_id(display_name)
    return "chat_" .. display_name
end

local function command_customize_setting_id(display_name)
    return display_name .. "_customize"
end

local function command_message_setting_id(display_name)
    return display_name .. "_message"
end

mod.clock_slots = CLOCK_SLOTS
mod.wheel_setting_id = wheel_setting_id
mod.command_enabled_setting_id = command_enabled_setting_id
mod.command_chat_setting_id = command_chat_setting_id
mod.command_customize_setting_id = command_customize_setting_id
mod.command_message_setting_id = command_message_setting_id

local pairs = pairs
local ipairs = ipairs

local function shallow_copy(source)
    local copy = {}

    for key, value in pairs(source) do
        copy[key] = value
    end

    return copy
end

local function build_dropdown_options()
    local options = {}

    for i, option in ipairs(DROPDOWN_OPTIONS) do
        options[i] = shallow_copy(option)
    end

    return options
end

local function get_wheel_widgets()
    local widgets = {}

    for i, clock_slot in ipairs(CLOCK_SLOTS) do
        local setting_id = wheel_setting_id(clock_slot)
        local command_value = DEFAULT_WHEEL_VALUES[setting_id] or COMMAND.NONE

        widgets[i] = {
            setting_id = setting_id,
            type = "dropdown",
            default_value = command_value,
            options = build_dropdown_options(),
        }
    end

    return widgets
end

-- Vanilla commands with a stock chat line keep posting it unless it is switched off. The message field only
-- applies while "Customize Text" is on; the script fills it with the default message, which needs the game's
-- localization, so its default here stays empty.
local function get_command_chat_widget(option)
    return {
        setting_id = command_chat_setting_id(option.text),
        type = "checkbox",
        title = "command_chat",
        tooltip = "command_chat_tooltip",
        default_value = option.stock_chat == true,
        sub_widgets = {
            {
                setting_id = command_customize_setting_id(option.text),
                type = "checkbox",
                title = "command_customize",
                tooltip = "command_customize_tooltip",
                default_value = false,
                sub_widgets = {
                    {
                        setting_id = command_message_setting_id(option.text),
                        type = "text",
                        title = "command_message",
                        tooltip = "command_message_tooltip",
                        placeholder_text = "command_message_placeholder",
                        max_length = CHAT_MESSAGE_MAX_LENGTH,
                        default_value = "",
                    },
                },
            },
        },
    }
end

-- One toggle per command; DMF only shows its settings while it is on, and they only apply while it is on.
local function get_command_widget(option)
    local sub_widgets = {
        {
            setting_id = option.text,
            type = "keybind",
            title = "command_keybind",
            keybind_trigger = "pressed",
            keybind_type = "function_call",
            function_name = "keybind_" .. option.value,
            default_value = {},
        },
    }

    if option.vanilla ~= true or option.stock_chat then
        sub_widgets[#sub_widgets + 1] = get_command_chat_widget(option)
    end

    return {
        setting_id = command_enabled_setting_id(option.text),
        type = "checkbox",
        title = option.text,
        tooltip = "command_toggle_tooltip",
        default_value = false,
        sub_widgets = sub_widgets,
    }
end

local function get_command_widgets()
    local widgets = {}

    for _, option in ipairs(DROPDOWN_OPTIONS) do
        if option.value > COMMAND.NONE then
            widgets[#widgets + 1] = get_command_widget(option)
        end
    end

    return widgets
end

local function get_widgets()
    return {
        {
            setting_id = "plugin_wheel_slots",
            type = "group",
            sub_widgets = get_wheel_widgets(),
        },
        {
            setting_id = "plugin_commands",
            type = "group",
            sub_widgets = get_command_widgets(),
        },
    }
end

return {
    name = mod:localize("mod_title"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = get_widgets(),
    }
}
