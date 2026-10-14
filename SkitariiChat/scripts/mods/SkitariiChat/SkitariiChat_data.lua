local mod = get_mod("SkitariiChat")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "encode_mode",
				type = "dropdown",
				default_value = "command",
				tooltip = "encode_mode_tooltip",
				options = {
					{ text = "encode_mode_off", value = "off" },
					{ text = "encode_mode_always", value = "always" },
					{ text = "encode_mode_command", value = "command" },
				},
			},
			{
				setting_id = "toggle_skitarii_chat",
				type = "keybind",
				default_value = {},
				keybind_trigger = "pressed",
				keybind_type = "mod_toggle",
				keybind_global = true,
				tooltip = "toggle_skitarii_chat_tooltip",
			},
			{
				setting_id = "decode_incoming_messages",
				type = "checkbox",
				default_value = true,
				tooltip = "decode_incoming_messages_tooltip",
			},
			{
				setting_id = "show_decoded_marker",
				type = "checkbox",
				default_value = true,
				tooltip = "show_decoded_marker_tooltip",
			},
			{
				setting_id = "max_chunks",
				type = "numeric",
				default_value = 3,
				range = { 1, 10 },
				tooltip = "max_chunks_tooltip",
			},
			{
				setting_id = "debug_logging",
				type = "checkbox",
				default_value = false,
				tooltip = "debug_logging_tooltip",
			},
		},
	},
}
