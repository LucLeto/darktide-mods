--- DMF entry script of Perfect Keystones; settings cache, tracking and HUD registration.
-- DMF runs this file as the `mod_script` named in `PerfectKeystones.mod`; `PerfectKeystones_data.lua`
-- and `PerfectKeystones_localization.lua` are loaded by DMF from the same declaration.
--
-- Caches the settings in `mod._settings` and bumps `mod._settings_version` on every change, so the
-- HUD element re-applies them only when needed; the ring and appearance settings come from
-- `PerfectKeystones_ring_settings.lua`, stored as `mod._ring_settings`, and each keystone's settings
-- from `PerfectKeystones_registry.lua`, stored as `mod._registry`. Loads the tracker
-- (`PerfectKeystones_tracker.lua`) as `mod._tracker`, which the HUD element polls once per frame.
-- No game function is hooked: the mod only reads the local player's buffs, components and ability
-- charges, and never changes buffs, cooldowns, inputs or any other gameplay state. Registers the
-- ring HUD element (`ui/PerfectKeystones_hud_element.lua`).
-- module: PerfectKeystones
-- author: LucLeto
local mod = get_mod("PerfectKeystones")

mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

-- ----------------------------------------------------------------------------
-- Settings
-- ----------------------------------------------------------------------------

--- Ring and appearance setting definitions, shared with the data file and the HUD element.
mod._ring_settings = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones_ring_settings")

--- Keystone registry, shared with the data file and the tracker.
mod._registry = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones_registry")

--- Cached setting values by setting id, initialised with the defaults from `PerfectKeystones_data.lua`;
-- the ring settings are added from `PerfectKeystones_ring_settings.lua` and every keystone's settings
-- from `PerfectKeystones_registry.lua` below. Colour settings hold DMF's `{ a, r, g, b }` tables;
-- they are only read, never written.
local settings = {
    debug_logging = false
}

--- Every cached setting id, in the order `refresh_settings` reads them; the ring and keystone
-- settings follow.
local SETTING_IDS = {
    "debug_logging"
}

mod._ring_settings.add_settings(settings, SETTING_IDS)
mod._registry.add_settings(settings, SETTING_IDS)

--- Lookup of `SETTING_IDS`, so unrelated setting changes are ignored.
local CACHED_SETTING_IDS = {}

for i = 1, #SETTING_IDS do
    CACHED_SETTING_IDS[SETTING_IDS[i]] = true
end

--- Shared settings cache, and a counter bumped on every change that the HUD element compares against.
mod._settings = settings
mod._settings_version = 0

--- Reads every cached setting from DMF and bumps the settings version.
-- A setting DMF returns nil for keeps its current value.
local function refresh_settings()
    for i = 1, #SETTING_IDS do
        local setting_id = SETTING_IDS[i]
        local value = mod:get(setting_id)

        if value ~= nil then
            settings[setting_id] = value
        end
    end

    mod._settings_version = mod._settings_version + 1
end

refresh_settings()

--- DMF callback for a changed setting.
-- Updates the cached value of a known setting and bumps the settings version; a nil setting id
-- refreshes every setting. Changing a keystone's settings only changes what is shown: the tracker
-- reads the game's state afresh every frame, so nothing is reset, paused or consumed.
-- ?string: setting_id changed setting
mod.on_setting_changed = function (setting_id)
    if setting_id == nil then
        refresh_settings()

        return
    end

    if not CACHED_SETTING_IDS[setting_id] then
        return
    end

    local value = mod:get(setting_id)

    if value ~= nil then
        settings[setting_id] = value
    end

    mod._settings_version = mod._settings_version + 1
end

-- ----------------------------------------------------------------------------
-- Tracking
-- ----------------------------------------------------------------------------

--- Keystone detection and presentation state, polled by the HUD element.
mod._tracker = mod:io_dofile("PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones_tracker")

local Tracker = mod._tracker

-- ----------------------------------------------------------------------------
-- DMF callbacks
-- ----------------------------------------------------------------------------

--- DMF callback for game state changes; entering or leaving gameplay forgets the bound player.
-- string: status `enter` or `exit`
-- string: state_name game state class name
mod.on_game_state_changed = function (status, state_name)
    if state_name == "StateGameplay" then
        Tracker.reset()
    end
end

--- DMF callback run when the mod is enabled; re-reads the settings and starts from a clean state.
mod.on_enabled = function ()
    refresh_settings()

    Tracker.reset()
end

--- DMF callback run when the mod is disabled; stops tracking.
-- DMF removes the HUD element along with the mod, which hides the rings; the tracker is only
-- polled by that element.
mod.on_disabled = function ()
    Tracker.reset()
end

-- ----------------------------------------------------------------------------
-- HUD element
-- ----------------------------------------------------------------------------

-- The ring HUD element, with the crosshair's visibility groups. Like the crosshair it ignores the
-- HUD scale option, so it always fits around the crosshair.
mod:register_hud_element({
    class_name = "HudElementPerfectKeystones",
    filename = "PerfectKeystones/scripts/mods/PerfectKeystones/ui/PerfectKeystones_hud_element",
    use_hud_scale = false,
    visibility_groups = {
        "alive",
        "player_in_danger_zone"
    }
})

return mod
