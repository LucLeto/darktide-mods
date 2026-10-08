--- Shares mission totals between Overflow Meter users through the party presence.
-- Each client publishes its own totals as a small JSON payload under one presence key,
-- `overflow_meter_summary`, which a hook on `PresenceEntryMyself.create_key_values` adds to the
-- local presence. It reads the same key from every party member's presence, and a teammate's
-- totals reach the snapshot as a remote entry, so the scoreboards can fill that teammate's column.
--
-- `mod.update` drives it at most every 2 s while in a mission: the payload is republished when
-- the totals change and once more when the mission ends, and the party is read on the same
-- interval and again when the end-of-round screen opens. Payloads are size-capped (250 bytes out,
-- 1 KiB in) and decoded defensively.
--
-- Explicit module loaded by `OverflowMeter.lua` and stored as `mod._share`. Turning off
-- `share_mission_summary` withdraws the published payload; teammates' payloads are still read.
-- module: OverflowMeter_share
-- alias: Share
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local Stats = mod._stats
local Snapshot = mod._snapshot

local Managers = Managers
local cjson = cjson
local math_floor = math.floor
local pairs = pairs
local pcall = pcall
local tostring = tostring
local type = type

-- ----------------------------------------------------------------------------
-- Constants and state
-- ----------------------------------------------------------------------------

--- Presence key and payload format version.
local KEY = "overflow_meter_summary"
local PAYLOAD_VERSION = 1

--- Size caps for the published payload and for a payload read from a teammate.
local MAX_PUBLISH_BYTES = 250
local MAX_INBOUND_BYTES = 1024

--- Seconds between publishing and reading rounds.
local PUBLISH_INTERVAL = 2

--- Logs the party members and whether each one publishes a summary, for debugging only.
local DEBUG_MEMBERS = false

local Share = {}

--- Publishing state: whether the presence hook is installed, the payload currently published
-- (`""` for none), the time to the next round, the statistics version last published, whether
-- the mission-end payload went out, and the raw payload last seen per teammate account id.
local hook_installed = false
local my_encoded = nil
local publish_timer = 0
local published_version = nil
local end_published = false
local debug_logged = false
local peer_raw = {}

--- Reused payload table. The short keys keep the encoded summary small: `a` archetype,
-- `g` generated, `r` replenished, `o` overflowed, `s` shared per ally, `st` shared with all
-- allies and `e` efficiency in percent.
local payload = {
    pv = PAYLOAD_VERSION,
    a = "",
    g = 0,
    r = 0,
    o = 0,
    s = 0,
    st = 0,
    e = 0
}

-- ----------------------------------------------------------------------------
-- Encoding and presence
-- ----------------------------------------------------------------------------

--- Encodes the local totals as the payload.
-- treturn: ?string JSON payload, or nil when sharing is off, nothing was generated yet, or the
-- payload would exceed the size cap
local function _encode_summary()
    if not cjson or not mod._settings.share_mission_summary then
        return nil
    end

    local archetype = Stats.archetype

    if not archetype or Stats.generated <= 0 then
        return nil
    end

    payload.a = archetype
    payload.g = math_floor(Stats.generated + 0.5)
    payload.r = math_floor(Stats.replenished + 0.5)
    payload.o = math_floor(Stats.overflowed + 0.5)
    payload.s = math_floor(Stats.shared + 0.5)
    payload.st = math_floor(Stats.shared_total + 0.5)
    payload.e = math_floor(Stats.efficiency() * 100 + 0.5)

    local ok, encoded = pcall(cjson.encode, payload)

    if not ok or type(encoded) ~= "string" or #encoded > MAX_PUBLISH_BYTES then
        return nil
    end

    return encoded
end

--- Decodes a teammate's payload.
-- ?string: raw raw presence value
-- treturn: ?tab decoded payload, or nil for anything empty, oversized or malformed
local function _decode_summary(raw)
    if type(raw) ~= "string" or raw == "" or #raw > MAX_INBOUND_BYTES or not cjson then
        return nil
    end

    local ok, decoded = pcall(cjson.decode, raw)

    if not ok or type(decoded) ~= "table" then
        return nil
    end

    return decoded
end

--- Asks the presence manager to republish the local presence with the summary key.
local function _push_presence()
    local presence_manager = Managers.presence

    if not presence_manager or type(presence_manager._update_my_presence) ~= "function" then
        return
    end

    pcall(presence_manager._update_my_presence, presence_manager, { [KEY] = true })
end

--- Publishes a payload, pushing the presence only when it changed.
-- string: encoded payload, or `""` to withdraw it
local function _set_published(encoded)
    if encoded == my_encoded then
        return
    end

    my_encoded = encoded

    _push_presence()
end

-- ----------------------------------------------------------------------------
-- Party members
-- ----------------------------------------------------------------------------

--- Returns a party member's presence entry.
-- ?tab: member party member
-- treturn: ?tab presence entry
local function _member_presence(member)
    if not member or type(member.presence) ~= "function" then
        return nil
    end

    local ok, presence = pcall(member.presence, member)

    if not ok or not presence then
        return nil
    end

    return presence
end

--- Returns whether a presence entry is the local player's own.
-- tab: presence presence entry
-- treturn: bool
local function _is_myself(presence)
    if type(presence.is_myself) ~= "function" then
        return false
    end

    local ok, myself = pcall(presence.is_myself, presence)

    return ok and myself == true
end

--- Returns the raw summary value from a presence entry.
-- tab: presence presence entry
-- treturn: ?string raw payload
local function _raw_member(presence)
    if type(presence._key_value_string) ~= "function" then
        return nil
    end

    local ok, raw = pcall(presence._key_value_string, presence, KEY)

    if not ok then
        return nil
    end

    return raw
end

--- Returns the decoded summary from a presence entry.
-- tab: presence presence entry
-- treturn: ?tab decoded payload
local function _read_member(presence)
    return _decode_summary(_raw_member(presence))
end

--- Returns every member of the local player's Immaterium party, the local player included.
-- treturn: ?tab array of party members
local function _members()
    local party_manager = Managers.party_immaterium

    if not party_manager or type(party_manager.all_members) ~= "function" then
        return nil
    end

    local ok, members = pcall(party_manager.all_members, party_manager)

    if not ok or type(members) ~= "table" then
        return nil
    end

    return members
end

--- Returns the game mode manager while in a mission, nil in the hub or without a game mode.
-- treturn: ?tab game mode manager
local function _in_mission()
    local state_managers = Managers.state
    local game_mode_manager = state_managers and state_managers.game_mode

    if not game_mode_manager then
        return nil
    end

    local game_mode_name = game_mode_manager:game_mode_name()

    if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
        return nil
    end

    return game_mode_manager
end

--- Returns whether the mission has ended (outro, done, or end conditions met).
-- tab: game_mode_manager game mode manager
-- treturn: bool
local function _mission_ended(game_mode_manager)
    if game_mode_manager.game_mode_state then
        local game_mode_state = game_mode_manager:game_mode_state()

        if game_mode_state == "outro_cinematic" or game_mode_state == "done" then
            return true
        end
    end

    if game_mode_manager.end_conditions_met and game_mode_manager:end_conditions_met() then
        return true
    end

    return false
end

--- Logs every party member and mission player, for `DEBUG_MEMBERS` only.
-- string: tag label for the log lines
local function _log_members(tag)
    local members = _members()

    if not members then
        mod:info("[share][%s] no party members available", tag)

        return
    end

    mod:info("[share][%s] members=%d published=%d bytes", tag, #members, my_encoded and #my_encoded or 0)

    for i = 1, #members do
        local member = members[i]
        local presence = _member_presence(member)

        mod:info(
            "[share][%s] member %d is_myself=%s account_id=%s has_summary=%s",
            tag,
            i,
            tostring(presence and _is_myself(presence)),
            tostring(member.account_id and member:account_id()),
            tostring(presence and _read_member(presence) ~= nil)
        )
    end

    local player_manager = Managers.player
    local players = player_manager and player_manager.players and player_manager:players()

    if not players then
        return
    end

    for _, player in pairs(players) do
        if player.account_id then
            mod:info("[share][%s] mission player account_id=%s", tag, tostring(player:account_id()))
        end
    end
end

--- Reads every teammate's payload into the snapshot and publishes it to the scoreboards.
-- A payload is only decoded when its raw value changed, unless forced.
-- bool: force reread every payload and republish even without changes
local function _push_peers(force)
    local members = _members()

    if not members then
        return
    end

    local changed = false

    for i = 1, #members do
        local member = members[i]
        local presence = _member_presence(member)

        if presence and not _is_myself(presence) then
            local account_id = member.account_id and member:account_id()
            local raw = account_id and _raw_member(presence)

            if raw and (force or raw ~= peer_raw[account_id]) then
                local peer = _decode_summary(raw)

                peer_raw[account_id] = raw

                if peer then
                    Snapshot.update_peer(account_id, peer)

                    changed = true
                end
            end
        end
    end

    if changed or force then
        Snapshot.publish(force)
    end
end

-- ----------------------------------------------------------------------------
-- Interface
-- ----------------------------------------------------------------------------

--- Installs the presence hook that adds the payload to the local presence, once.
-- Called from `mod.on_all_mods_loaded`; without `PresenceEntryMyself` sharing stays off.
Share.setup = function ()
    if hook_installed then
        return
    end

    local presence_class = CLASS and CLASS.PresenceEntryMyself

    if not presence_class or type(presence_class.create_key_values) ~= "function" then
        mod:error("PresenceEntryMyself.create_key_values is missing; the mission summary cannot be shared.")

        return
    end

    hook_installed = true

    -- Adds the payload to the local presence's key values whenever the key is requested.
    mod:hook(presence_class, "create_key_values", function (func, self, white_list)
        local key_values = func(self, white_list)

        if my_encoded and (not white_list or white_list[KEY]) then
            key_values[KEY] = my_encoded
        end

        return key_values
    end)
end

--- Applies the sharing setting: republishes on the next round when sharing is on, withdraws the
-- payload when it is off or the mod is disabled.
Share.refresh = function ()
    if mod:is_enabled() and mod._settings.share_mission_summary then
        published_version = nil

        return
    end

    _set_published("")
end

--- Starts a new mission: withdraws the payload and forgets every teammate's payload.
Share.reset = function ()
    publish_timer = 0
    published_version = nil
    end_published = false
    debug_logged = false

    for account_id in pairs(peer_raw) do
        peer_raw[account_id] = nil
    end

    _set_published("")
end

--- Withdraws the payload and resets, when the mod is disabled or unloaded.
Share.teardown = function ()
    _set_published("")

    Share.reset()
end

--- Runs one publishing and reading round every `PUBLISH_INTERVAL` seconds while in a mission.
-- Republishes when the totals changed, publishes the final totals and flushes the snapshot once
-- the mission ends, and reads the teammates' payloads.
-- number: dt frame delta time
Share.update = function (dt)
    if not hook_installed then
        return
    end

    publish_timer = publish_timer - dt

    if publish_timer > 0 then
        return
    end

    publish_timer = PUBLISH_INTERVAL

    local game_mode_manager = _in_mission()

    if not game_mode_manager then
        return
    end

    if Stats.version ~= published_version then
        published_version = Stats.version

        _set_published(_encode_summary() or "")
    end

    if not end_published and _mission_ended(game_mode_manager) then
        end_published = true

        _set_published(_encode_summary() or "")

        Snapshot.flush()
    end

    _push_peers(false)

    if DEBUG_MEMBERS and not debug_logged then
        debug_logged = true

        _log_members("mission")
    end
end


--- Rereads every teammate's payload and republishes the snapshot, from the end-of-round screen
-- and when a scoreboard collects its values.
Share.push_peers = function ()
    if DEBUG_MEMBERS then
        _log_members("end_view")
    end

    _push_peers(true)
end

return Share
