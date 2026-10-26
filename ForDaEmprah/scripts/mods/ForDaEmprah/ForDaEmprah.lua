local ChatManagerConstants = require("scripts/foundation/managers/chat/chat_manager_constants")
local HudElementSmartTaggingDefinitions = require("scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging_definitions")
local HudElementSmartTaggingSettings = require("scripts/ui/hud/elements/smart_tagging/hud_element_smart_tagging_settings")
local InputDevice = require("scripts/managers/input/input_device")
local VOQueryConstants = require("scripts/settings/dialogue/vo_query_constants")
local Vo = require("scripts/utilities/vo")

local mod = get_mod("ForDaEmprah")

local ChannelTags = ChatManagerConstants.ChannelTag
local HudElementSmartTagging_instance
local vanilla_wheel_options

local ipairs = ipairs
local pairs = pairs
local type = type
local math_abs = math.abs
local math_angle = math.angle
local math_cos = math.cos
local math_distance_2d = math.distance_2d
local math_max = math.max
local math_min = math.min
local math_rad = math.rad
local math_sin = math.sin
local math_smoothstep = math.smoothstep
local math_tan = math.tan
local string_find = string.find
local string_format = string.format
local string_match = string.match
local table_sort = table.sort
local unit_world_position = Unit.world_position
local vector3_distance_squared = Vector3.distance_squared
local vector3_length = Vector3.length
local vector3box_unbox = Vector3Box.unbox
local wheel_setting_id = mod.wheel_setting_id
local command_enabled_setting_id = mod.command_enabled_setting_id
local command_chat_setting_id = mod.command_chat_setting_id
local command_customize_setting_id = mod.command_customize_setting_id
local command_message_setting_id = mod.command_message_setting_id
local label_loc_keys = mod.label_loc_keys
local labels = mod.labels
local CLOCK_SLOTS = mod.clock_slots
local CLOCK_WHEEL_SLOT_COUNT = #CLOCK_SLOTS
local VANILLA_WHEEL_SLOT_COUNT = HudElementSmartTaggingSettings.wheel_slots
local PI = math.pi
local TWO_PI = PI * 2
local HALF_PI = PI * 0.5
local MOUSE_MIN_HOVER_ANGLE = math_rad(8)
local MOUSE_HOVER_ANGLE_PADDING = math_rad(1)
local HOVER_DISTANCE_THRESHOLD = 130
-- Mirrors the file-local constant in hud_element_smart_tagging.lua, which is not reachable from here.
local INSTANT_WHEEL_THRESHOLD = 8
local VANILLA_MAX_RADIUS = HudElementSmartTaggingSettings.max_radius
-- The slice_eighth textures each cover 1/8 of the circle, whatever the configured slot count.
local SLICE_TEXTURE_HALF_ANGLE_TAN = math_tan(PI / 8)
-- Below this many slots, widened slices distort too much, so they stop growing.
local MIN_SLICE_SLOT_COUNT = 4
local BACKGROUND_BASE_SIZE = HudElementSmartTaggingDefinitions.scenegraph_definition.background.size
local MARK_BASE_STYLE = HudElementSmartTaggingDefinitions.widget_definitions.wheel_background.style.mark
local slice_style_ids = {}
local slice_base_sizes = {}
local wheel_settings = {}

local function _sort_teammates_by_distance(a, b)
    return a.distance < b.distance
end

for i, clock_slot in ipairs(CLOCK_SLOTS) do
    wheel_settings[i] = wheel_setting_id(clock_slot)
end

HudElementSmartTaggingSettings.wheel_slots = CLOCK_WHEEL_SLOT_COUNT

local function _item_tag(value, fallback)
    if type(value) ~= "string" then
        return fallback
    end

    if string_find(value, "pup_", 1, true) == 1 or string_find(value, "station_", 1, true) == 1 then
        return value
    end

    return fallback
end

local function _clone_command(command)
    if not command then
        return nil
    end

    local cloned_command = {}

    for key, value in pairs(command) do
        cloned_command[key] = value
    end

    return cloned_command
end

local vanilla_wheel_command_ids = {
    [1] = true,
    [22] = true,
    [23] = true,
    [24] = true,
    [25] = true,
    [26] = true,
    [27] = true,
}

-- A mod command's default chat message is its label: the subtitle of its own voice line (see ForDaEmprah_data.lua).
-- The game always loads its subtitles, so every player reads the line in their own language, mod or not.
local function _optional_chat_message_data(display_name)
    return {
        channel = ChannelTags.MISSION,
        text = label_loc_keys[display_name],
    }
end

local commands = {
    [1] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/for_the_emperor",
        display_name = "option_for_the_emperor",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_for_the_emperor,
        },
    },
    [2] = {
        icon = "content/ui/materials/icons/player_states/lugged",
        display_name = "option_vacuum_capsule",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_container,
        },
    },
    [3] = {
        icon = "content/ui/materials/icons/list_buttons/check",
        display_name = "option_yes",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_yes,
        },
    },
    [4] = {
        icon = "content/ui/materials/icons/list_buttons/cross",
        display_name = "option_no",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_no,
        },
    },
    [5] = {
        icon = "content/ui/materials/icons/player_states/lugged",
        display_name = "option_cryonic_rod",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_control_rod,
        },
    },
    [6] = {
        icon = "content/ui/materials/icons/player_states/lugged",
        display_name = "option_power_cell",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_battery,
        },
    },
    [7] = {
        icon = "content/ui/materials/icons/pocketables/hud/scripture",
        display_name = "option_scripture",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_side_mission_tome,
        },
    },
    [8] = {
        icon = "content/ui/materials/icons/pocketables/hud/grimoire",
        display_name = "option_grimoire",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_side_mission_grimoire,
        },
    },
    [9] = {
        icon = "content/ui/materials/hud/interactions/icons/objective_side",
        display_name = "option_relic",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_side_mission_consumable,
        },
    },
    [10] = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_syringe_corruption",
        display_name = "option_health_booster",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = _item_tag(VOQueryConstants.trigger_ids.smart_tag_vo_pickup_stimm_health, "pup_stimm_health"),
        },
    },
    [11] = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_default",
        display_name = "option_mine",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_need_that,
        },
    },
    [12] = {
        icon = "content/ui/materials/hud/interactions/icons/ammunition",
        display_name = "option_ammo",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_ammo,
        },
    },
    [13] = {
        icon = "content/ui/materials/hud/interactions/icons/grenade",
        display_name = "option_grenade",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_small_grenade,
        },
    },
    [14] = {
        icon = "content/ui/materials/hud/interactions/icons/environment_generic",
        display_name = "option_plasteel",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_forge_metal,
        },
    },
    [15] = {
        icon = "content/ui/materials/hud/interactions/icons/environment_generic",
        display_name = "option_diamantine",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_platinum,
        },
    },
    [16] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/location",
        display_name = "option_following",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_follow_you,
        },
    },
    [17] = {
        icon = "content/ui/materials/hud/interactions/icons/respawn",
        display_name = "option_medicae_station",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_station_health,
        },
    },
    [18] = {
        icon = "content/ui/materials/hud/interactions/icons/respawn",
        display_name = "option_uncharged_medicae",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_station_health_without_battery,
        },
    },
    [19] = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        display_name = "option_medipack",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = VOQueryConstants.trigger_ids.smart_tag_vo_pickup_medical_crate,
        },
    },
    [20] = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_medkit",
        display_name = "option_medipack_down",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = _item_tag(VOQueryConstants.trigger_ids.smart_tag_vo_pickup_deployed_medical_crate,
                "pup_deployed_medical_crate"),
        },
    },
    [21] = {
        icon = "content/ui/materials/hud/interactions/icons/pocketable_ammo",
        display_name = "option_ammo_crate",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_vo_tag_item,
            voice_tag_id = _item_tag(VOQueryConstants.trigger_ids.smart_tag_vo_pickup_deployed_ammo_crate,
                "pup_deployed_ammo_crate"),
        },
    },
    [22] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/ammo",
        display_name = "option_need_ammo",
        chat_message_data = {
            channel = ChannelTags.MISSION,
            text = "loc_communication_wheel_need_ammo",
        },
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_need_ammo,
        },
    },
    [23] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/health",
        display_name = "option_need_healing",
        chat_message_data = {
            channel = ChannelTags.MISSION,
            text = "loc_communication_wheel_need_health",
        },
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_need_health,
        },
    },
    [24] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/attention",
        display_name = "option_look_there",
        tag_type = "location_attention",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_over_here,
        },
    },
    [25] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/location",
        display_name = "option_go_there",
        tag_type = "location_ping",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_lets_go_this_way,
        },
    },
    [26] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/enemy",
        display_name = "option_enemy",
        tag_type = "location_threat",
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_enemy_over_here,
        },
    },
    [27] = {
        icon = "content/ui/materials/hud/communication_wheel/icons/thanks",
        display_name = "option_thanks",
        chat_message_data = {
            channel = ChannelTags.MISSION,
            text = "loc_communication_wheel_thanks",
        },
        voice_event_data = {
            voice_tag_concept = VOQueryConstants.concepts.on_demand_com_wheel,
            voice_tag_id = VOQueryConstants.trigger_ids.com_wheel_vo_thank_you,
        },
    },
    [28] = {
        icon = "content/ui/materials/hud/interactions/icons/speak",
        display_name = "option_sorry",
        -- Darktide does not expose a dedicated "sorry" bark in the current on-demand VO tables.
        use_apology_rule = true,
        use_custom_execution = true,
    },
}

local function _setup_optional_chat_messages()
    for command_id, command in pairs(commands) do
        if not vanilla_wheel_command_ids[command_id] and command.display_name then
            command.chat_message_data = _optional_chat_message_data(command.display_name)
            command.chat_message_data.optional = true
        end
    end
end

_setup_optional_chat_messages()

-- Setting ids of each command's toggle, chat toggle and custom message (see ForDaEmprah_data.lua).
local command_settings = {}

for command_id, command in pairs(commands) do
    local display_name = command.display_name

    command_settings[command_id] = {
        enabled = command_enabled_setting_id(display_name),
        chat = command_chat_setting_id(display_name),
        customize = command_customize_setting_id(display_name),
        message = command_message_setting_id(display_name),
    }
end

local function _custom_chat_message(setting_ids)
    if not mod:get(setting_ids.customize) then
        return nil
    end

    local message = mod:get(setting_ids.message)

    if type(message) ~= "string" then
        return nil
    end

    message = string_match(message, "^%s*(.-)%s*$")

    return message ~= "" and message or nil
end

-- The default message as the local player reads it. Its loc key needs the game's localization, which returns ""
-- until its strings are loaded.
local function _default_chat_text(chat_message_data)
    return type(Localize) == "function" and Localize(chat_message_data.text) or ""
end

-- Fills the message fields with their default message, so customizing starts from it. Only empty fields of
-- commands that aren't customized are filled, so text the player wrote is never replaced. Returns false while
-- the game's localization isn't loaded yet.
local function _fill_default_messages()
    for command_id, command in pairs(commands) do
        local chat_message_data = command.chat_message_data
        local setting_ids = command_settings[command_id]

        if chat_message_data and not mod:get(setting_ids.customize) then
            local message = mod:get(setting_ids.message)

            if message == nil or message == "" then
                local default_text = _default_chat_text(chat_message_data)

                if default_text == "" then
                    return false
                end

                mod:set(setting_ids.message, default_text)
            end
        end
    end

    return true
end

local default_messages_filled = _fill_default_messages()

-- The command as the wheel and its keybind use it. While its toggle is off it keeps its defaults: no optional
-- chat message, and vanilla commands keep their stock one. While on, its chat toggle and custom message apply.
local function _configured_command(command_id)
    local command = commands[command_id]

    if not command then
        return nil
    end

    local configured_command = _clone_command(command)
    local chat_message_data = command.chat_message_data

    if not chat_message_data then
        return configured_command
    end

    local setting_ids = command_settings[command_id]

    if not mod:get(setting_ids.enabled) then
        if chat_message_data.optional then
            configured_command.chat_message_data = nil
        end
    elseif not mod:get(setting_ids.chat) then
        configured_command.chat_message_data = nil
    else
        local custom_message = _custom_chat_message(setting_ids)

        -- Text left as the default it was filled with still goes out as the default, so it stays localized per
        -- player. Anything else is sent as typed; localized = false also routes wheel picks through _execute_command.
        if custom_message and custom_message ~= _default_chat_text(chat_message_data) then
            configured_command.chat_message_data = {
                channel = chat_message_data.channel,
                text = custom_message,
                localized = false,
            }
        end
    end

    return configured_command
end

local function _active_wheel_options()
    local options = {}

    for i = 1, CLOCK_WHEEL_SLOT_COUNT do
        local command_id = mod:get(wheel_settings[i])

        if command_id and command_id > 0 then
            local command = _configured_command(command_id)

            if command then
                options[#options + 1] = command
            end
        end
    end

    return options
end

local function _wheel_entry_options(entries)
    local options = {}

    for i = 1, #entries do
        local option = entries[i].option

        if option then
            options[#options + 1] = option
        end
    end

    return options
end

local function _clock_angle(position, visible_count)
    if visible_count <= 0 then
        return PI
    end

    local radians_per_entry = TWO_PI / visible_count

    return PI - (position - 1) * radians_per_entry
end

local function _screen_angle(x1, y1, x2, y2)
    return (TWO_PI - math_angle(x1, y1, x2, y2) - HALF_PI) % TWO_PI
end

local function _angle_distance(a, b)
    return (a - b + PI) % TWO_PI - PI
end

local function _mouse_hover_angle(visible_count)
    if visible_count <= 0 then
        return 0
    end

    return math_max(MOUSE_MIN_HOVER_ANGLE, (TWO_PI / visible_count) - MOUSE_HOVER_ANGLE_PADDING)
end

local function _gamepad_hover_angle(visible_count)
    if visible_count <= 0 then
        return 0
    end

    return math_min(TWO_PI, (TWO_PI / visible_count) * 1.1)
end

local function _wheel_radius_bounds(visible_count)
    local extra_radius = math_max(visible_count - 8, 0) * 12

    return HudElementSmartTaggingSettings.min_radius + extra_radius,
        HudElementSmartTaggingSettings.max_radius + extra_radius
end

local function _collect_slice_styles()
    local entry_definition = HudElementSmartTaggingDefinitions.entry_widget_definition
    local definition_content = entry_definition.content
    local definition_style = entry_definition.style
    local passes = entry_definition.passes

    for i = 1, #passes do
        local pass = passes[i]
        local style_id = pass.style_id
        local value = pass.value_id and definition_content[pass.value_id]

        if style_id and type(value) == "string" and string_find(value, "/communication_wheel/slice_", 1, true) then
            local base_style = definition_style[style_id]
            local base_size = base_style and base_style.size

            if base_size then
                slice_style_ids[#slice_style_ids + 1] = style_id
                slice_base_sizes[#slice_base_sizes + 1] = { base_size[1], base_size[2] }
            end
        end
    end
end

_collect_slice_styles()

local function _wheel_scale(visible_count)
    local _, max_radius = _wheel_radius_bounds(visible_count)

    return max_radius / VANILLA_MAX_RADIUS
end

local function _slice_width_scale(visible_count)
    if visible_count <= 0 then
        return 1
    end

    -- Scaling a wedge horizontally keeps its edges pointing at the wheel centre and scales tan(half angle) linearly.
    return math_tan(PI / math_max(visible_count, MIN_SLICE_SLOT_COUNT)) / SLICE_TEXTURE_HALF_ANGLE_TAN
end

local function _apply_background_scale(instance, scale)
    instance:_set_scenegraph_size("background", BACKGROUND_BASE_SIZE[1] * scale, BACKGROUND_BASE_SIZE[2] * scale)

    local mark_style = instance._widgets_by_name.wheel_background.style.mark
    local base_size = MARK_BASE_STYLE.size
    local base_pivot = MARK_BASE_STYLE.pivot
    local base_offset = MARK_BASE_STYLE.offset

    mark_style.size[1] = base_size[1] * scale
    mark_style.size[2] = base_size[2] * scale
    mark_style.pivot[1] = base_pivot[1] * scale
    mark_style.pivot[2] = base_pivot[2] * scale
    mark_style.offset[1] = base_offset[1] * scale
    mark_style.offset[2] = base_offset[2] * scale
end

local function _apply_wheel_scale(instance, visible_count)
    local scale = _wheel_scale(visible_count)
    local slice_width_scale = scale * _slice_width_scale(visible_count)
    local entries = instance._entries

    for i = 1, #entries do
        local widget_style = entries[i].widget.style

        for j = 1, #slice_style_ids do
            local style = widget_style[slice_style_ids[j]]
            local base_size = slice_base_sizes[j]
            local size = style.size
            local pivot = style.pivot
            local width = base_size[1] * slice_width_scale
            local height = base_size[2] * scale

            size[1] = width
            size[2] = height
            -- rotated_texture caches its pivot from the first drawn size, so keep it centred on the new size.
            pivot[1] = width * 0.5
            pivot[2] = height * 0.5
        end
    end

    _apply_background_scale(instance, scale)

    instance._mod_wheel_scale = scale
end


local function _chat_channel(chat_manager, channel_tag)
    if not chat_manager then
        return nil
    end

    local channels = chat_manager:connected_chat_channels()

    if not channels then
        return nil
    end

    for channel_handle, channel in pairs(channels) do
        if channel.tag == channel_tag then
            return channel_handle
        end
    end

    return nil
end

local function _send_chat_message(chat_message_data)
    if not chat_message_data then
        return
    end

    local chat_manager = Managers.chat
    local channel_handle = _chat_channel(chat_manager, chat_message_data.channel)

    if not chat_manager or not channel_handle then
        return
    end

    if chat_message_data.localized == false then
        chat_manager:send_channel_message(channel_handle, chat_message_data.text)
    else
        chat_manager:send_loc_channel_message(channel_handle, chat_message_data.text, chat_message_data.context)
    end
end

local function _player_unit()
    local instance = HudElementSmartTagging_instance
    local parent = instance and instance._parent

    return parent and parent:player_unit() or nil
end

local function _dialogue_extension(unit)
    if not unit then
        return nil
    end

    return ScriptUnit.has_extension(unit, "dialogue_system")
end

local function _player_class(unit)
    local dialogue_extension = _dialogue_extension(unit)

    if not dialogue_extension then
        return nil
    end

    if dialogue_extension.vo_class_name then
        return dialogue_extension:vo_class_name()
    end

    local context = dialogue_extension.get_context and dialogue_extension:get_context()

    return context and context.class_name or nil
end

local function _append_unique_class(list, seen, class_name)
    if class_name and not seen[class_name] then
        seen[class_name] = true
        list[#list + 1] = class_name
    end
end

local function _ordered_teammate_classes(player_unit)
    local player_unit_spawn_manager = Managers.state.player_unit_spawn
    local alive_players = player_unit_spawn_manager and player_unit_spawn_manager:alive_players()
    local alive_lookup = ALIVE

    if not player_unit or not alive_players or not alive_lookup[player_unit] then
        return {}
    end

    local player_position = unit_world_position(player_unit, 1)
    local teammates = {}
    local ordered_classes = {}
    local seen_classes = {}

    for i = 1, #alive_players do
        local other_player = alive_players[i]
        local other_unit = other_player and other_player.player_unit

        if other_unit and other_unit ~= player_unit and alive_lookup[other_unit] then
            teammates[#teammates + 1] = {
                class_name = _player_class(other_unit),
                distance = vector3_distance_squared(player_position, unit_world_position(other_unit, 1)),
            }
        end
    end

    table_sort(teammates, _sort_teammates_by_distance)

    for i = 1, #teammates do
        _append_unique_class(ordered_classes, seen_classes, teammates[i].class_name)
    end

    return ordered_classes
end

local function _available_apology_target_classes(dialogue_extension, speaker_class)
    local voice_choices = dialogue_extension and dialogue_extension._vo_choice

    if not voice_choices or not speaker_class then
        return {}
    end

    local pattern = string_format("^response_for_friendly_fire_from_%s_to_(.+)$", speaker_class)
    local target_classes = {}
    local seen_classes = {}

    for rule_name in pairs(voice_choices) do
        local target_class = string_match(rule_name, pattern)

        _append_unique_class(target_classes, seen_classes, target_class)
    end

    table_sort(target_classes)

    return target_classes
end

local function _apology_rule_name(player_unit)
    local dialogue_extension = _dialogue_extension(player_unit)
    local speaker_class = _player_class(player_unit)

    if not dialogue_extension or not speaker_class then
        return nil
    end

    local target_classes = {}
    local seen_classes = {}
    local nearby_target_classes = _ordered_teammate_classes(player_unit)
    local available_target_classes = _available_apology_target_classes(dialogue_extension, speaker_class)

    for i = 1, #nearby_target_classes do
        _append_unique_class(target_classes, seen_classes, nearby_target_classes[i])
    end

    for i = 1, #available_target_classes do
        _append_unique_class(target_classes, seen_classes, available_target_classes[i])
    end

    local rule_name_prefix = "response_for_friendly_fire_from_" .. speaker_class .. "_to_"

    for i = 1, #target_classes do
        local rule_name = rule_name_prefix .. target_classes[i]

        if dialogue_extension:has_dialogue(rule_name) then
            return rule_name
        end
    end

    return nil
end

local function _trigger_apology_voice(player_unit)
    local rule_name = _apology_rule_name(player_unit)

    if not rule_name then
        return false
    end

    Vo.play_local_vo_event(player_unit, rule_name, 0)

    return true
end

local function _trigger_location_tag(command)
    local instance = HudElementSmartTagging_instance

    if not instance or not command.tag_type then
        return
    end

    local raycast_data = instance:_find_raycast_targets(true)
    local hit_position = raycast_data and raycast_data.static_hit_position

    if hit_position then
        instance:_trigger_smart_tag(command.tag_type, nil, vector3box_unbox(hit_position))
    end
end

local function _trigger_voice_event(command, player_unit)
    local voice_event_data = command.voice_event_data

    if voice_event_data and player_unit then
        Vo.on_demand_vo_event(player_unit, voice_event_data.voice_tag_concept, voice_event_data.voice_tag_id)
    end
end

local function _execute_command(command, player_unit)
    if not command then
        return
    end

    player_unit = player_unit or _player_unit()

    _trigger_location_tag(command)
    _send_chat_message(command.chat_message_data)

    if command.use_apology_rule then
        _trigger_apology_voice(player_unit)
    else
        _trigger_voice_event(command, player_unit)
    end
end

local function _uses_custom_execution(command)
    if command.use_custom_execution then
        return true
    end

    local chat_message_data = command.chat_message_data

    -- Vanilla wheel execution always sends chat as a stock loc key, so custom (typed) chat must go through _execute_command.
    return chat_message_data ~= nil and chat_message_data.localized == false
end

mod:hook("HudElementSmartTagging", "_populate_wheel", function(func, self, options)
    -- Only vanilla init passes options; keep them so on_disabled can restore the stock wheel.
    if options then
        vanilla_wheel_options = options
    end

    local active_options = _active_wheel_options()

    self._mod_active_wheel_option_count = #active_options

    func(self, active_options)
    _apply_wheel_scale(self, #active_options)
end)

mod:hook("HudElementSmartTagging", "_update_widget_locations", function(func, self)
    local entries = self._entries
    local visible_count = 0
    local active_progress = self._wheel_active_progress
    local anim_progress = math_smoothstep(active_progress, 0, 1)

    for i = 1, #entries do
        local entry = entries[i]

        if entry and entry.option then
            visible_count = visible_count + 1
        elseif entry then
            local widget = entry.widget
            local offset = widget.offset

            widget.content.angle = PI
            widget.content.hotspot.force_hover = false
            offset[1] = 0
            offset[2] = 0
        end
    end

    local min_radius, max_radius = _wheel_radius_bounds(visible_count)
    local radius = min_radius + anim_progress * (max_radius - min_radius)
    local visible_position = 0

    for i = 1, #entries do
        local entry = entries[i]

        if entry and entry.option then
            visible_position = visible_position + 1

            local widget = entry.widget
            local angle = _clock_angle(visible_position, visible_count)
            local offset = widget.offset

            widget.content.angle = angle
            offset[1] = math_sin(angle) * radius
            offset[2] = math_cos(angle) * radius
        end
    end
end)

mod:hook("HudElementSmartTagging", "_update_wheel_presentation",
    function(func, self, dt, t, ui_renderer, render_settings, input_service)
        local screen_width = RESOLUTION_LOOKUP.width
        local screen_height = RESOLUTION_LOOKUP.height
        local half_screen_height = screen_height * 0.5
        local half_screen_width = screen_width * 0.5
        local scale = render_settings.scale
        local cursor = input_service and input_service:get("cursor")

        if input_service and InputDevice.gamepad_active then
            cursor = input_service:get("navigate_controller_right")
            cursor[1] = half_screen_width + cursor[1] * half_screen_width
            cursor[2] = half_screen_height - cursor[2] * half_screen_height
        end

        if not cursor then
            return
        end

        local cursor_x = cursor[1]
        local cursor_y = cursor[2]
        local cursor_distance_from_center = math_distance_2d(half_screen_width, half_screen_height, cursor_x, cursor_y)
        local raw_cursor_angle = math_angle(half_screen_width, half_screen_height, cursor_x, cursor_y)
        local cursor_visual_angle = raw_cursor_angle - HALF_PI
        local cursor_selection_angle = (TWO_PI - raw_cursor_angle - HALF_PI) % TWO_PI
        local visible_count = self._mod_active_wheel_option_count or 0
        local entry_hover_degrees_half = _mouse_hover_angle(visible_count) * 0.5
        local any_hover = false
        local hovered_entry
        local entries = self._entries
        local hover_distance_threshold = HOVER_DISTANCE_THRESHOLD * scale * (self._mod_wheel_scale or 1)

        for i = 1, #entries do
            local entry = entries[i]
            local widget = entry.widget
            local is_hover = false

            if entry.option and cursor_distance_from_center > hover_distance_threshold then
                local widget_angle = _screen_angle(0, 0, widget.offset[1], widget.offset[2])
                local angle_diff = math_abs(_angle_distance(widget_angle, cursor_selection_angle))

                if angle_diff <= entry_hover_degrees_half then
                    is_hover = true
                    any_hover = true
                    hovered_entry = entry
                end
            end

            widget.content.hotspot.force_hover = is_hover
        end

        local wheel_background_widget = self._widgets_by_name.wheel_background
        local wheel_background_content = wheel_background_widget.content
        local wheel_background_mark_color = wheel_background_widget.style.mark.color

        wheel_background_content.angle = cursor_visual_angle
        wheel_background_content.force_hover = any_hover
        wheel_background_content.text = ""
        wheel_background_mark_color[1] = any_hover and 255 or 0

        if hovered_entry then
            wheel_background_content.text = labels[hovered_entry.option.display_name]
        end
    end)

mod:hook("HudElementSmartTagging", "_should_draw_wheel_gamepad", function(func, self, input_service)
    local look_delta = input_service:get("look_raw_controller") * INSTANT_WHEEL_THRESHOLD * 2
    local is_dragging = vector3_length(look_delta) > INSTANT_WHEEL_THRESHOLD
    local wheel_context = self._com_wheel_context

    if not wheel_context.camera_still_on_tag then
        return false
    end

    if not wheel_context.instant_drew and is_dragging then
        local entries = self._entries
        local look_angle = _screen_angle(0, 0, look_delta[1], look_delta[2])
        local half_entry_hover_angle = _gamepad_hover_angle(self._mod_active_wheel_option_count or 0) * 0.5

        for i = 1, #entries do
            local entry = entries[i]

            if entry.option then
                local widget = entry.widget
                local widget_angle = _screen_angle(0, 0, widget.offset[1], widget.offset[2])
                local angle_diff = math_abs(_angle_distance(widget_angle, look_angle))

                if angle_diff < half_entry_hover_angle then
                    wheel_context.instant_drew = true

                    break
                end
            end
        end
    end

    return is_dragging
end)

mod:hook("HudElementSmartTagging", "_on_com_wheel_stop_callback",
    function(func, self, t, ui_renderer, render_settings, input_service)
        local wheel_hovered_entry = self._wheel_active and self:_is_wheel_entry_hovered(t)
        local command = wheel_hovered_entry and wheel_hovered_entry.option

        if command and _uses_custom_execution(command) then
            local parent = self._parent
            local player_unit = parent and parent:player_unit() or nil
            local wheel_context = self._com_wheel_context

            _execute_command(command, player_unit)

            wheel_context.input_stop_time = t
            wheel_context.input_start_time = nil
            wheel_context.is_double_tap = nil
            wheel_context.instant_drew = nil
            wheel_context.camera_still_on_tag = nil
            wheel_context.simultaneous_press = nil

            Managers.event:trigger("event_set_communication_wheel_state", "inactive")

            return
        end

        func(self, t, ui_renderer, render_settings, input_service)
    end)

local function setup_keybind_functions()
    for key in ipairs(commands) do
        local enabled_setting_id = command_settings[key].enabled

        mod["keybind_" .. key] = function()
            if Managers.input:cursor_active() or Managers.ui:using_input() then
                return
            end

            -- A command's keybind only applies while its toggle is on.
            if not mod:get(enabled_setting_id) then
                return
            end

            _execute_command(_configured_command(key))
        end
    end
end

mod:hook_safe("HudElementSmartTagging", "update", function(self)
    if HudElementSmartTagging_instance ~= self then
        HudElementSmartTagging_instance = self
        setup_keybind_functions()
    end

    if #self._entries ~= CLOCK_WHEEL_SLOT_COUNT then
        -- A HUD created while the mod was disabled still holds the vanilla options here.
        vanilla_wheel_options = vanilla_wheel_options or _wheel_entry_options(self._entries)

        self:_setup_entries(CLOCK_WHEEL_SLOT_COUNT)
        self:_populate_wheel()
    end

    if mod.setting_dirty then
        self:_populate_wheel()
        mod.setting_dirty = false
    end
end)

mod:hook_safe("HudElementSmartTagging", "destroy", function(self)
    if HudElementSmartTagging_instance == self then
        HudElementSmartTagging_instance = nil
    end
end)

-- Every setting feeds into the wheel options: slot commands, command toggles, chat toggles and messages.
-- Refilling also restores the default text of a field left empty when "Customize Text" is switched off.
mod.on_setting_changed = function()
    mod.setting_dirty = true
    default_messages_filled = _fill_default_messages()
end

mod.update = function()
    if not default_messages_filled then
        default_messages_filled = _fill_default_messages()
    end
end

mod.on_enabled = function()
    HudElementSmartTaggingSettings.wheel_slots = CLOCK_WHEEL_SLOT_COUNT
end

mod.on_disabled = function()
    HudElementSmartTaggingSettings.wheel_slots = VANILLA_WHEEL_SLOT_COUNT

    local instance = HudElementSmartTagging_instance

    -- DMF deactivates all hooks before on_disabled, so these calls run the vanilla implementations.
    if instance and vanilla_wheel_options then
        instance:_setup_entries(VANILLA_WHEEL_SLOT_COUNT)
        instance:_populate_wheel(vanilla_wheel_options)
        _apply_background_scale(instance, 1)
    end

    -- The destroy hook is inactive while disabled, so drop the reference; update re-acquires it on enable.
    HudElementSmartTagging_instance = nil
end

local function init_keybind_functions()
    local noop = function()
        return
    end

    for key in ipairs(commands) do
        mod["keybind_" .. key] = noop
    end
end

init_keybind_functions()
