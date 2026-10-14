local Protocol = {}

local floor = math.floor
local string_byte = string.byte
local string_char = string.char
local string_sub = string.sub
local table_concat = table.concat

local MECHANICUS_GLYPH = "\238\128\169"
local PACKET_MAGIC = 0x53
local PACKET_VERSION = 0x01
local FLAG_NONE = 0x00
local HEADER_SIZE = 9
local PAYLOAD_BYTES_PER_PACKET = 120
local MAX_VISIBLE_PACKET_LENGTH = 190
local MAX_PROTOCOL_CHUNKS = 10

local BASE64URL_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local BASE64URL_DECODE = {}

for i = 1, #BASE64URL_ALPHABET do
	BASE64URL_DECODE[string_byte(BASE64URL_ALPHABET, i)] = i - 1
end

local global_bit = rawget(_G, "bit")
local bit_bxor = global_bit and global_bit.bxor

local function xor_byte(a, b)
	if bit_bxor then
		return bit_bxor(a, b)
	end

	local result = 0
	local place = 1

	for _ = 1, 8 do
		local a_bit = a % 2
		local b_bit = b % 2

		if a_bit ~= b_bit then
			result = result + place
		end

		a = (a - a_bit) / 2
		b = (b - b_bit) / 2
		place = place * 2
	end

	return result
end

local function base64url_encode(data)
	local encoded = {}
	local encoded_count = 0
	local data_length = #data

	for i = 1, data_length, 3 do
		local first = string_byte(data, i)
		local second = string_byte(data, i + 1)
		local third = string_byte(data, i + 2)
		local value = first * 65536 + (second or 0) * 256 + (third or 0)

		encoded_count = encoded_count + 1
		encoded[encoded_count] = string_sub(BASE64URL_ALPHABET, floor(value / 262144) % 64 + 1, floor(value / 262144) % 64 + 1)
		encoded_count = encoded_count + 1
		encoded[encoded_count] = string_sub(BASE64URL_ALPHABET, floor(value / 4096) % 64 + 1, floor(value / 4096) % 64 + 1)

		if second then
			encoded_count = encoded_count + 1
			encoded[encoded_count] = string_sub(BASE64URL_ALPHABET, floor(value / 64) % 64 + 1, floor(value / 64) % 64 + 1)
		end

		if third then
			encoded_count = encoded_count + 1
			encoded[encoded_count] = string_sub(BASE64URL_ALPHABET, value % 64 + 1, value % 64 + 1)
		end
	end

	return table_concat(encoded)
end

local function base64url_decode(data)
	local data_length = #data
	local remainder = data_length % 4

	if data_length == 0 or remainder == 1 then
		return nil
	end

	local decoded = {}
	local decoded_count = 0

	for i = 1, data_length, 4 do
		local first = BASE64URL_DECODE[string_byte(data, i)]
		local second = BASE64URL_DECODE[string_byte(data, i + 1)]
		local third_byte = string_byte(data, i + 2)
		local fourth_byte = string_byte(data, i + 3)
		local third = third_byte and BASE64URL_DECODE[third_byte]
		local fourth = fourth_byte and BASE64URL_DECODE[fourth_byte]

		if first == nil or second == nil or third_byte and third == nil or fourth_byte and fourth == nil then
			return nil
		end

		local value = first * 262144 + second * 4096 + (third or 0) * 64 + (fourth or 0)

		decoded_count = decoded_count + 1
		decoded[decoded_count] = string_char(floor(value / 65536) % 256)

		if third_byte then
			decoded_count = decoded_count + 1
			decoded[decoded_count] = string_char(floor(value / 256) % 256)
		end

		if fourth_byte then
			decoded_count = decoded_count + 1
			decoded[decoded_count] = string_char(value % 256)
		end
	end

	return table_concat(decoded)
end

local function calculate_checksum(id_hi, id_lo, part, total, payload)
	local checksum = PACKET_MAGIC + PACKET_VERSION + FLAG_NONE + id_hi + id_lo + part + total

	for i = 1, #payload do
		checksum = checksum + string_byte(payload, i)
	end

	return checksum % 256
end

local function encode_packet(payload, message_id, part, total, nonce)
	local id_hi = floor(message_id / 256)
	local id_lo = message_id % 256
	local checksum = calculate_checksum(id_hi, id_lo, part, total, payload)
	local packet = {
		string_char(nonce),
		string_char(xor_byte(PACKET_MAGIC, nonce)),
		string_char(xor_byte(PACKET_VERSION, nonce)),
		string_char(xor_byte(FLAG_NONE, nonce)),
		string_char(xor_byte(id_hi, nonce)),
		string_char(xor_byte(id_lo, nonce)),
		string_char(xor_byte(part, nonce)),
		string_char(xor_byte(total, nonce)),
		string_char(xor_byte(checksum, nonce)),
	}

	for i = 1, #payload do
		packet[#packet + 1] = string_char(xor_byte(string_byte(payload, i), nonce))
	end

	return MECHANICUS_GLYPH .. base64url_encode(table_concat(packet))
end

local function default_random_byte()
	return math.random(0, 255)
end

function Protocol.encode_message(message, max_chunks, random_byte)
	if type(message) ~= "string" or message == "" then
		return nil, "empty"
	end

	max_chunks = floor(tonumber(max_chunks) or 0)

	if max_chunks < 1 or max_chunks > MAX_PROTOCOL_CHUNKS then
		return nil, "invalid_max_chunks"
	end

	local total = floor((#message + PAYLOAD_BYTES_PER_PACKET - 1) / PAYLOAD_BYTES_PER_PACKET)

	if total > max_chunks then
		return nil, "too_long"
	end

	random_byte = random_byte or default_random_byte

	local message_id = random_byte() * 256 + random_byte()
	local packets = {}

	for part = 1, total do
		local first_byte = (part - 1) * PAYLOAD_BYTES_PER_PACKET + 1
		local payload = string_sub(message, first_byte, first_byte + PAYLOAD_BYTES_PER_PACKET - 1)
		local nonce = random_byte()

		packets[part] = encode_packet(payload, message_id, part, total, nonce)
	end

	return packets
end

function Protocol.decode_visible(message)
	if type(message) ~= "string" or string_sub(message, 1, #MECHANICUS_GLYPH) ~= MECHANICUS_GLYPH then
		return nil
	end

	if #message > MAX_VISIBLE_PACKET_LENGTH then
		return nil
	end

	local packet = base64url_decode(string_sub(message, #MECHANICUS_GLYPH + 1))

	if not packet or #packet <= HEADER_SIZE then
		return nil
	end

	if base64url_encode(packet) ~= string_sub(message, #MECHANICUS_GLYPH + 1) then
		return nil
	end

	local nonce = string_byte(packet, 1)
	local magic = xor_byte(string_byte(packet, 2), nonce)
	local version = xor_byte(string_byte(packet, 3), nonce)
	local flags = xor_byte(string_byte(packet, 4), nonce)
	local id_hi = xor_byte(string_byte(packet, 5), nonce)
	local id_lo = xor_byte(string_byte(packet, 6), nonce)
	local part = xor_byte(string_byte(packet, 7), nonce)
	local total = xor_byte(string_byte(packet, 8), nonce)
	local checksum = xor_byte(string_byte(packet, 9), nonce)

	if magic ~= PACKET_MAGIC or version ~= PACKET_VERSION or flags ~= FLAG_NONE then
		return nil
	end

	if total < 1 or total > MAX_PROTOCOL_CHUNKS or part < 1 or part > total then
		return nil
	end

	local payload = {}

	for i = HEADER_SIZE + 1, #packet do
		payload[#payload + 1] = string_char(xor_byte(string_byte(packet, i), nonce))
	end

	payload = table_concat(payload)

	if checksum ~= calculate_checksum(id_hi, id_lo, part, total, payload) then
		return nil
	end

	return {
		message_id = id_hi * 256 + id_lo,
		part = part,
		total = total,
		payload = payload,
	}
end

Protocol.MECHANICUS_GLYPH = MECHANICUS_GLYPH
Protocol.PAYLOAD_BYTES_PER_PACKET = PAYLOAD_BYTES_PER_PACKET
Protocol.MAX_VISIBLE_PACKET_LENGTH = MAX_VISIBLE_PACKET_LENGTH
Protocol.MAX_PROTOCOL_CHUNKS = MAX_PROTOCOL_CHUNKS

return Protocol
