local MECHANICUS_GLYPH = "\238\128\169"

return {
	mod_name = {
		en = "Skitarii Chat",
	},
	mod_description = {
		en = "Encodes Mechanicus-themed chat messages that other Skitarii Chat users decode locally.",
	},
	encode_mode = {
		en = "Outgoing encoding mode",
	},
	encode_mode_tooltip = {
		en = "Choose whether outgoing messages are never encoded, always encoded, or encoded only with /skc.",
	},
	encode_mode_off = {
		en = "Off",
	},
	encode_mode_always = {
		en = "Always",
	},
	encode_mode_command = {
		en = "Command only",
	},
	toggle_skitarii_chat = {
		en = "Toggle Skitarii Chat",
	},
	toggle_skitarii_chat_tooltip = {
		en = "Assign a key to enable or disable the entire mod. This only affects future messages.",
	},
	decode_incoming_messages = {
		en = "Decode incoming SKC1 messages",
	},
	decode_incoming_messages_tooltip = {
		en = "Decode valid incoming SKC1 messages into readable text. When disabled, encoded messages are shown unchanged, as players without Skitarii Chat see them.",
	},
	show_decoded_marker = {
		en = "Show decoded Mechanicus marker " .. MECHANICUS_GLYPH,
	},
	show_decoded_marker_tooltip = {
		en = "Prefixes decoded messages with " .. MECHANICUS_GLYPH .. ", the Mechanicus glyph.",
	},
	max_chunks = {
		en = "Maximum outgoing chunks",
	},
	max_chunks_tooltip = {
		en = "Limits how many chat packets one encoded message may send. Each chunk carries up to 120 bytes.",
	},
	debug_logging = {
		en = "Enable debug logging",
	},
	debug_logging_tooltip = {
		en = "Writes packet and chunk diagnostics to the Darktide mod log.",
	},
	message_too_long = {
		en = "Skitarii Chat message is too long.",
	},
	command_usage = {
		en = "Usage: /skc <message>",
	},
	encoding_disabled = {
		en = "Skitarii Chat outgoing encoding is off.",
	},
	safe_word_triggered = {
		en = "Skitarii Chat encoding disabled for this location.",
	},
	safe_word_encoding_disabled = {
		en = "Skitarii Chat encoding was stopped for this location.",
	},
	chat_channel_unavailable = {
		en = "Skitarii Chat could not find an active chat channel.",
	},
	mod_enabled = {
		en = "Skitarii Chat enabled.",
	},
	mod_disabled = {
		en = "Skitarii Chat disabled.",
	},
	remote_disabled = {
		en = "Skitarii Chat has been remotely disabled by its maintainer.",
	},
	remote_enabled = {
		en = "Skitarii Chat remote access restored.",
	},
	command_description = {
		en = "Send an encoded Skitarii Chat message. Usage: /skc <message>",
	},
}
