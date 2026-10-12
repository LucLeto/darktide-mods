--- DMF entry script of Perfect Thrust; settings cache, windup hooks and HUD registration.
-- DMF runs this file as the `mod_script` named in `PerfectThrust.mod`; `PerfectThrust_data.lua`
-- and `PerfectThrust_localization.lua` are loaded by DMF from the same declaration.
--
-- Caches the settings in `mod._settings` and bumps `mod._settings_version` on every change, so
-- the HUD element re-applies them only when needed; the ring settings of the melee and the aiming
-- ring come from `PerfectThrust_ring_settings.lua`, stored as `mod._ring_settings`. On load it
-- first folds the removed opacity setting of earlier versions into the melee ring's colour
-- settings' alpha, once. Loads the tracker
-- (`PerfectThrust_tracker.lua`) as `mod._tracker` and feeds it from `hook_safe` hooks on the
-- melee windup actions, which only observe the game: no input, timing or buff is changed. Loads
-- the aim tracker (`PerfectThrust_aim_tracker.lua`) as `mod._aim_tracker`, which needs no hooks:
-- the HUD element polls it while aiming down sights. Registers the ring HUD element
-- (`ui/PerfectThrust_hud_element.lua`).
-- module: PerfectThrust
-- author: LucLeto
local mod = get_mod("PerfectThrust")

mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

-- ----------------------------------------------------------------------------
-- Settings
-- ----------------------------------------------------------------------------

--- Ring setting definitions of the melee and the aiming ring, shared with the data file and the HUD element.
mod._ring_settings = mod:io_dofile("PerfectThrust/scripts/mods/PerfectThrust/PerfectThrust_ring_settings")

--- Cached setting values by setting id, initialised with the defaults from `PerfectThrust_data.lua`;
-- both rings' settings are added from `PerfectThrust_ring_settings.lua` below.
-- Colour settings hold DMF's `{ a, r, g, b }` tables; they are only read, never written.
local settings = {
    timing_mode = "predicted",
    show_heavy_threshold = true,
    show_ads_blessings = true,
    debug_logging = false
}

--- Every cached setting id, in the order `refresh_settings` reads them; the ring settings follow.
local SETTING_IDS = {
    "timing_mode",
    "show_heavy_threshold",
    "show_ads_blessings",
    "debug_logging"
}

mod._ring_settings.add_settings(settings, SETTING_IDS)

--- Lookup of `SETTING_IDS`, so unrelated setting changes are ignored.
local CACHED_SETTING_IDS = {}

for i = 1, #SETTING_IDS do
    CACHED_SETTING_IDS[SETTING_IDS[i]] = true
end

--- Shared settings cache, and a counter bumped on every change that the HUD element compares against.
mod._settings = settings
mod._settings_version = 0

--- The melee ring's colour setting ids, whose alpha took over from the removed `ring_opacity`
-- setting; the aiming ring's colours came later and never had it.
local COLOR_SETTING_IDS = {
    "unfilled_color",
    "charging_color",
    "heavy_available_color",
    "ready_color",
    "ready_pulse_color"
}

--- Folds the removed `ring_opacity` setting into the alpha of every colour setting, once.
-- Earlier versions multiplied each state's alpha by `ring_opacity`; the colour settings now hold
-- that alpha themselves. DMF stores the colour defaults, which carry the old state alphas, before
-- this script runs, so an updating player's ring keeps exactly its previous look. The old key is
-- deleted afterwards, so later starts do not migrate again; new installs never have it.
local function migrate_ring_opacity()
    local ring_opacity = mod:get("ring_opacity")

    if ring_opacity == nil then
        return
    end

    if type(ring_opacity) == "number" and ring_opacity ~= 100 then
        local opacity = ring_opacity / 100

        for i = 1, #COLOR_SETTING_IDS do
            local setting_id = COLOR_SETTING_IDS[i]
            local color = mod:get(setting_id)

            if type(color) ~= "table" or type(color[1]) ~= "number" then
                color = settings[setting_id]
            end

            mod:set(setting_id, { math.floor(color[1] * opacity), color[2], color[3], color[4] })
        end
    end

    mod:set("ring_opacity", nil)
end

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

migrate_ring_opacity()
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

--- Aim state and aiming blessing detection, polled by the HUD element.
mod._aim_tracker = mod:io_dofile("PerfectThrust/scripts/mods/PerfectThrust/PerfectThrust_aim_tracker")

local AimTracker = mod._aim_tracker

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

--- DMF callback for game state changes; entering or leaving gameplay stops any tracked windup or aim.
-- string: status `enter` or `exit`
-- string: state_name game state class name
mod.on_game_state_changed = function (status, state_name)
    if state_name == "StateGameplay" then
        Tracker.reset()
        AimTracker.reset()
    end
end

--- DMF callback run when the mod is enabled; re-reads the settings and starts from a clean state.
mod.on_enabled = function ()
    refresh_settings()

    Tracker.reset()
    AimTracker.reset()
end

--- DMF callback run when the mod is disabled; stops tracking, which hides the ring.
-- DMF disables the hooks of a disabled mod, so nothing starts tracking again until it is enabled;
-- the aim tracker is only polled by the HUD element, which DMF removes along with the mod.
mod.on_disabled = function ()
    Tracker.reset()
    AimTracker.reset()
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
