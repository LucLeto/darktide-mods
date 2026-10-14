local mod = get_mod("SkitariiChat")
local protocol = mod:io_dofile("SkitariiChat/scripts/mods/SkitariiChat/SkitariiChat_protocol")

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local string_format = string.format
local string_find = string.find
local string_lower = string.lower
local string_sub = string.sub
local table_concat = table.concat
local tostring = tostring
local tonumber = tonumber

local CHUNK_TIMEOUT_SECONDS = 10
local CLEANUP_INTERVAL_SECONDS = 1
local REMOTE_CHECK_TIMEOUT_SECONDS = 10
local REMOTE_MARKER_URL = "https://raw.githubusercontent.com/LucLeto/darktide-mods-skitarii-chat/main/SKCE"
local INSTANCE_SAFE_WORD = "skitussy"
local ENCODE_MODE_OFF = "off"
local ENCODE_MODE_ALWAYS = "always"
local ENCODE_MODE_COMMAND = "command"
local VALID_ENCODE_MODES = {
	[ENCODE_MODE_OFF] = true,
	[ENCODE_MODE_ALWAYS] = true,
	[ENCODE_MODE_COMMAND] = true,
}

local encode_mode
local decode_incoming_messages
local show_decoded_marker
local max_chunks
local debug_logging

local pending_messages = {}
local pending_count = 0
local next_cleanup_at = 0
local selected_channel_handle
local queued_command_message
local remote_check_generation = 0
local remote_functionality_enabled = true
local mod_is_enabled = true
local instance_encoding_disabled = false

local function reset_dmf_command_gui()
	local dmf = get_mod("DMF")

	if dmf and type(dmf.destroy_command_gui) == "function" then
		dmf.destroy_command_gui()
	end
end

local function is_stale_dmf_command_gui_error(error_message)
	local message = tostring(error_message)

	return string_find(message, "slug_text_extents", 1, true) ~= nil
		and string_find(message, "Gui expected", 1, true) ~= nil
end

local function refresh_settings()
	local configured_mode = mod:get("encode_mode")

	encode_mode = VALID_ENCODE_MODES[configured_mode] and configured_mode or ENCODE_MODE_COMMAND
	decode_incoming_messages = mod:get("decode_incoming_messages") ~= false
	show_decoded_marker = mod:get("show_decoded_marker")
	max_chunks = math_min(protocol.MAX_PROTOCOL_CHUNKS, math_max(1, math_floor(tonumber(mod:get("max_chunks")) or 3)))
	debug_logging = mod:get("debug_logging")
end

local function debug_log(message, ...)
	if debug_logging then
		mod:info("[SKC1] " .. string_format(message, ...))
	end
end

local function current_time()
	local time_manager = Managers.time

	if time_manager then
		local t = time_manager:time("main")

		if t then
			return t
		end
	end

	return 0
end

local function clear_pending_messages()
	pending_messages = {}
	pending_count = 0
	next_cleanup_at = 0
end

local function is_instance_safe_word(message)
	if type(message) ~= "string" then
		return false
	end

	return string_find(string_lower(message), INSTANCE_SAFE_WORD, 1, true) ~= nil
end

local function disable_instance_encoding()
	if instance_encoding_disabled then
		return
	end

	instance_encoding_disabled = true
	queued_command_message = nil
	mod:echo(mod:localize("safe_word_triggered"))
end

local function remote_http_status(value)
	if type(value) ~= "table" then
		return nil
	end

	local status = tonumber(value.status or value.status_code or value.code)

	if status then
		return status
	end

	if type(value.error) == "table" then
		return tonumber(value.error.status or value.error.status_code or value.error.code)
	end

	return nil
end

local function remote_marker_is_missing(value)
	local status = remote_http_status(value)

	if status then
		return status == 404 or status == 410
	end

	local message = tostring(value)

	return string_find(message, "404", 1, true) ~= nil
		or string_find(message, "410", 1, true) ~= nil
end

local function sync_command_availability()
	if mod_is_enabled and remote_functionality_enabled then
		mod:command_enable("skc")
	else
		mod:command_disable("skc")
	end
end

local function set_remote_functionality_enabled(enabled)
	if remote_functionality_enabled == enabled then
		return
	end

	remote_functionality_enabled = enabled
	clear_pending_messages()
	queued_command_message = nil
	selected_channel_handle = nil
	sync_command_availability()

	if mod_is_enabled then
		local message_key = enabled and "remote_enabled" or "remote_disabled"

		mod:echo(mod:localize(message_key))
	end
end

local function check_remote_marker()
	remote_check_generation = remote_check_generation + 1

	local generation = remote_check_generation
	local backend = Managers.backend

	if not backend or type(backend.url_request) ~= "function" then
		mod:warning("[SKC1] Remote enable marker check unavailable; keeping the cached state.")

		return
	end

	local request_url = string_format("%s?check=%d-%d", REMOTE_MARKER_URL, os.time(), generation)
	local request_succeeded, promise = pcall(backend.url_request, backend, request_url, {
		method = "GET",
		require_auth = false,
		response_timeout_seconds = REMOTE_CHECK_TIMEOUT_SECONDS,
		headers = {
			["Cache-Control"] = "no-cache",
			Pragma = "no-cache",
		},
	})

	if not request_succeeded or not promise or type(promise.next) ~= "function" then
		mod:warning("[SKC1] Remote enable marker request could not start; keeping the cached state.")

		return
	end

	promise:next(function(response)
		if generation ~= remote_check_generation then
			return
		end

		if remote_marker_is_missing(response) then
			set_remote_functionality_enabled(false)
		else
			set_remote_functionality_enabled(true)
		end
	end, function(request_error)
		if generation ~= remote_check_generation then
			return
		end

		if remote_marker_is_missing(request_error) then
			set_remote_functionality_enabled(false)
		else
			mod:warning(string_format(
				"[SKC1] Remote enable marker check failed; keeping the cached state: %s",
				tostring(request_error)
			))
		end
	end)
end

local function cleanup_expired(now)
	if pending_count == 0 then
		next_cleanup_at = now + CLEANUP_INTERVAL_SECONDS

		return
	end

	for key, state in pairs(pending_messages) do
		if now - state.created_at >= CHUNK_TIMEOUT_SECONDS then
			pending_messages[key] = nil
			pending_count = pending_count - 1

			debug_log("expired message %d (%d/%d chunks)", state.message_id, state.received, state.total)
		end
	end

	next_cleanup_at = now + CLEANUP_INTERVAL_SECONDS
end

local function new_pending_message(sender_key, channel_key, packet, now)
	return {
		sender = sender_key,
		channel = channel_key,
		message_id = packet.message_id,
		total = packet.total,
		created_at = now,
		received = 0,
		chunks = {},
	}
end

local function collect_packet(sender, channel, packet)
	local sender_key = tostring(sender or "")
	local channel_key = tostring(channel.tag or channel.channel_name or channel)
	local key = sender_key .. "\0" .. channel_key .. "\0" .. packet.message_id
	local now = current_time()

	if now >= next_cleanup_at then
		cleanup_expired(now)
	end

	local state = pending_messages[key]

	if state and state.total ~= packet.total then
		pending_messages[key] = nil
		pending_count = pending_count - 1
		state = nil

		debug_log("reset conflicting message %d", packet.message_id)
	end

	if not state then
		state = new_pending_message(sender_key, channel_key, packet, now)
		pending_messages[key] = state
		pending_count = pending_count + 1
	end

	local existing_payload = state.chunks[packet.part]

	if existing_payload and existing_payload ~= packet.payload then
		state = new_pending_message(sender_key, channel_key, packet, now)
		pending_messages[key] = state
		existing_payload = nil

		debug_log("reset conflicting chunk %d for message %d", packet.part, packet.message_id)
	end

	if not existing_payload then
		state.chunks[packet.part] = packet.payload
		state.received = state.received + 1

		debug_log("collected message %d chunk %d/%d", packet.message_id, packet.part, packet.total)
	end

	if state.received ~= state.total then
		return nil
	end

	pending_messages[key] = nil
	pending_count = pending_count - 1

	return table_concat(state.chunks, "", 1, state.total)
end

local function send_encoded_message(channel_handle, message, send_packet)
	if channel_handle == nil then
		mod:echo(mod:localize("chat_channel_unavailable"))

		return false
	end

	local packets, error_code = protocol.encode_message(message, max_chunks)

	if not packets then
		if error_code == "too_long" then
			mod:echo(mod:localize("message_too_long"))
		else
			mod:echo(mod:localize("command_usage"))
		end

		return false
	end

	if send_packet then
		for i = 1, #packets do
			send_packet(channel_handle, packets[i])
		end
	else
		local chat_manager = Managers.chat

		for i = 1, #packets do
			chat_manager:send_channel_message(channel_handle, packets[i])
		end
	end

	debug_log("sent %d chunk(s), %d payload bytes", #packets, #message)

	return true
end

local function command_message_from_text(message)
	if type(message) ~= "string" then
		return nil
	end

	local lowered_message = string_lower(message)

	if lowered_message == "/skc" then
		return ""
	end

	if string_sub(lowered_message, 1, 5) == "/skc " then
		return string_sub(message, 6)
	end

	return nil
end

local function is_encoded_packet(message)
	return string_sub(message, 1, #protocol.MECHANICUS_GLYPH) == protocol.MECHANICUS_GLYPH
		and protocol.decode_visible(message) ~= nil
end

refresh_settings()

mod:command("skc", mod:localize("command_description"), function(...)
	local message = queued_command_message
	queued_command_message = nil

	if not remote_functionality_enabled then
		mod:echo(mod:localize("remote_disabled"))

		return
	end

	if instance_encoding_disabled then
		mod:echo(mod:localize("safe_word_encoding_disabled"))

		return
	end

	if message == nil then
		message = table_concat({ ... }, " ")
	end

	if encode_mode == ENCODE_MODE_OFF then
		mod:echo(mod:localize("encoding_disabled"))

		return
	end

	send_encoded_message(selected_channel_handle, message)
end)

mod:hook("ConstantElementChat", "_handle_active_chat_input", function(func, self, input_service, ui_renderer, ...)
	selected_channel_handle = self._selected_channel_handle

	if remote_functionality_enabled
		and not instance_encoding_disabled
		and encode_mode ~= ENCODE_MODE_OFF
		and input_service:get("send_chat_message") then
		local input_widget = self._input_field_widget
		local input_text = input_widget and input_widget.content.input_text

		if type(input_text) == "string" then
			local command_prefix = string_lower(string_sub(input_text, 1, 5))

			if command_prefix == "/skc " then
				queued_command_message = self:_scrub(string_sub(input_text, 6))
			elseif string_lower(input_text) == "/skc" then
				queued_command_message = ""
			end
		end
	end

	local succeeded, result = pcall(func, self, input_service, ui_renderer, ...)

	if succeeded then
		return result
	end

	if is_stale_dmf_command_gui_error(result) then
		reset_dmf_command_gui()
		mod:warning("[SKC1] Recovered from a stale DMF command autocomplete GUI.")

		return
	end

	error(result, 0)
end)

mod:hook("ChatManager", "send_channel_message", function(func, self, channel_handle, message_body)
	if type(message_body) ~= "string" then
		return func(self, channel_handle, message_body)
	end

	if is_instance_safe_word(message_body) then
		disable_instance_encoding()

		return func(self, channel_handle, message_body)
	end

	local command_message = command_message_from_text(message_body)

	if command_message ~= nil then
		if not remote_functionality_enabled then
			mod:echo(mod:localize("remote_disabled"))

			return
		end

		if instance_encoding_disabled then
			mod:echo(mod:localize("safe_word_encoding_disabled"))

			return
		end

		if encode_mode == ENCODE_MODE_OFF then
			mod:echo(mod:localize("encoding_disabled"))

			return
		end

		send_encoded_message(channel_handle, command_message, function(handle, packet)
			func(self, handle, packet)
		end)

		return
	end

	if remote_functionality_enabled
		and not instance_encoding_disabled
		and encode_mode == ENCODE_MODE_ALWAYS
		and message_body ~= ""
		and string_sub(message_body, 1, 1) ~= "/"
		and not is_encoded_packet(message_body) then
		send_encoded_message(channel_handle, message_body, function(handle, packet)
			func(self, handle, packet)
		end)

		return
	end

	return func(self, channel_handle, message_body)
end)

mod:hook("ConstantElementChat", "_add_message", function(func, self, message, sender, channel)
	if is_instance_safe_word(message) then
		disable_instance_encoding()

		return func(self, message, sender, channel)
	end

	if not remote_functionality_enabled
		or not decode_incoming_messages
		or type(message) ~= "string"
		or string_sub(message, 1, #protocol.MECHANICUS_GLYPH) ~= protocol.MECHANICUS_GLYPH then
		return func(self, message, sender, channel)
	end

	local packet = protocol.decode_visible(message)

	if not packet then
		return func(self, message, sender, channel)
	end

	local decoded_message = collect_packet(sender, channel, packet)

	if not decoded_message then
		return
	end

	decoded_message = self:_scrub(decoded_message)

	if show_decoded_marker then
		decoded_message = protocol.MECHANICUS_GLYPH .. " " .. decoded_message
	end

	return func(self, decoded_message, sender, channel)
end)

mod.update = function()
	if pending_count > 0 then
		local now = current_time()

		if now >= next_cleanup_at then
			cleanup_expired(now)
		end
	end
end

mod.on_game_state_changed = function(status, state_name)
	if status == "enter" and state_name == "StateGameplay" then
		instance_encoding_disabled = false

		if mod_is_enabled then
			check_remote_marker()
		end
	end
end

mod.on_setting_changed = function()
	refresh_settings()

	if encode_mode == ENCODE_MODE_OFF then
		queued_command_message = nil
	end

	if not decode_incoming_messages then
		clear_pending_messages()
	end
end

mod.on_enabled = function(initial_call)
	mod_is_enabled = true
	refresh_settings()
	sync_command_availability()

	if not initial_call then
		local message_key = remote_functionality_enabled and "mod_enabled" or "remote_disabled"

		mod:echo(mod:localize(message_key))
	end
end

mod.on_disabled = function(initial_call)
	mod_is_enabled = false
	mod:command_disable("skc")
	clear_pending_messages()
	queued_command_message = nil
	selected_channel_handle = nil

	if not initial_call then
		mod:echo(mod:localize("mod_disabled"))
	end
end
