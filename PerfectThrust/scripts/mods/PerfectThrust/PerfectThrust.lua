--- DMF entry script of Perfect Thrust; settings cache, windup hooks and HUD registration.
-- DMF runs this file as the `mod_script` named in `PerfectThrust.mod`; `PerfectThrust_data.lua`
-- and `PerfectThrust_localization.lua` are loaded by DMF from the same declaration.
--
-- Caches the settings in `mod._settings` and bumps `mod._settings_version` on every change, so
-- the HUD element re-applies them only when needed. Loads the tracker
-- (`PerfectThrust_tracker.lua`) as `mod._tracker` and feeds it from `hook_safe` hooks on the
-- melee windup actions, which only observe the game: no input, timing or buff is changed.
-- Registers the ring HUD element (`ui/PerfectThrust_hud_element.lua`).
-- module: PerfectThrust
-- author: LucLeto
local mod = get_mod("PerfectThrust")

mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

-- ----------------------------------------------------------------------------
-- Settings
-- ----------------------------------------------------------------------------

--- Cached setting values by setting id, initialised with the defaults from `PerfectThrust_data.lua`.
local settings = {
    display_mode = "progress",
    timing_mode = "predicted",
    ring_radius = 32,
    ring_thickness = 3,
    offset_x = 0,
    offset_y = 0,
    ring_opacity = 100,
    ready_pulse = true,
    debug_logging = false
}

--- Every cached setting id, in the order `refresh_settings` reads them.
local SETTING_IDS = {
    "display_mode",
    "timing_mode",
    "ring_radius",
    "ring_thickness",
    "offset_x",
    "offset_y",
    "ring_opacity",
    "ready_pulse",
    "debug_logging"
}

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
-- refreshes every setting.
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
-- Windup hooks
-- ----------------------------------------------------------------------------

--- Charge state and effect detection, shared with the HUD element.
mod._tracker = mod:io_dofile("PerfectThrust/scripts/mods/PerfectThrust/PerfectThrust_tracker")

local Tracker = mod._tracker

--- Forwards the start of a windup action to the tracker.
-- tab: self windup action instance
-- tab: action_settings action settings
-- number: t fixed-step time the action started at
local function on_windup_start(self, action_settings, t)
    Tracker.on_windup_start(self, t)
end

--- Forwards a fixed-step update of a windup action to the tracker.
-- tab: self windup action instance
-- number: dt fixed time step
-- number: t fixed-step time
-- number: time_in_action time since the action started
local function on_windup_fixed_update(self, dt, t, time_in_action)
    Tracker.on_windup_update(self, time_in_action)
end

-- Melee windups: the charge before a light or heavy attack is released.
mod:hook_safe(CLASS.ActionWindup, "start", on_windup_start)
mod:hook_safe(CLASS.ActionWindup, "fixed_update", on_windup_fixed_update)
mod:hook_safe(CLASS.ActionWindup, "finish", function (self, reason)
    Tracker.on_windup_finish(self, reason)
end)

-- Shield block-windups: heavy attacks charged from a block. ActionBlockWindup inherits finish from
-- ActionBlock; instead of hooking that shared base method, its end is caught by the tracker's
-- per-frame weapon_action check.
mod:hook_safe(CLASS.ActionBlockWindup, "start", on_windup_start)
mod:hook_safe(CLASS.ActionBlockWindup, "fixed_update", on_windup_fixed_update)

-- ----------------------------------------------------------------------------
-- DMF callbacks
-- ----------------------------------------------------------------------------

--- DMF callback for game state changes; entering or leaving gameplay stops any tracked windup.
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

--- DMF callback run when the mod is disabled; stops tracking, which hides the ring.
-- DMF disables the hooks of a disabled mod, so nothing starts tracking again until it is enabled.
mod.on_disabled = function ()
    Tracker.reset()
end

-- ----------------------------------------------------------------------------
-- HUD element
-- ----------------------------------------------------------------------------

-- The ring HUD element, with the crosshair's visibility groups. Like the crosshair it ignores the
-- HUD scale option, so it always fits around the crosshair.
mod:register_hud_element({
    class_name = "HudElementPerfectThrust",
    filename = "PerfectThrust/scripts/mods/PerfectThrust/ui/PerfectThrust_hud_element",
    use_hud_scale = false,
    visibility_groups = {
        "alive",
        "player_in_danger_zone"
    }
})

return mod
