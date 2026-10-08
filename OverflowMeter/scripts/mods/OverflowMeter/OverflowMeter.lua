--- DMF entry script that caches the settings, loads the modules and owns the shared hooks.
-- DMF runs this file as the `mod_script` named in `OverflowMeter.mod`; `OverflowMeter_data.lua`
-- and `OverflowMeter_localization.lua` are loaded by DMF from the same declaration.
--
-- Every setting is cached in `mod._settings` and refreshed per changed id. The modules are
-- loaded in dependency order through `mod:io_dofile` and stored on `mod`: the mission
-- statistics, the Skitarii and Veteran sources and pulses, the scoreboard snapshot with its
-- optional adapters, mission summary sharing and the Session Stats rows. The HUD element
-- (`ui/OverflowMeter_hud_element.lua`) is registered last and reaches everything through these
-- `mod` fields.
--
-- DMF keeps only one hook per mod and method, so the two hooks both pulse modules need
-- (`PlayerUnitBuffExtension._set_proc_active_start_time` and
-- `AttackReportManager.add_attack_result`) are registered here once and dispatched to whichever
-- pulse module is enabled.
-- module: OverflowMeter
-- author: LucLeto
local mod = get_mod("OverflowMeter")

--- Mod version from DMF's `info.json` metadata, or `unknown` on DMF releases without it.
mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

local math_floor = math.floor

-- ----------------------------------------------------------------------------
-- Settings cache
-- ----------------------------------------------------------------------------

--- Cached setting values by setting id, seeded with the defaults from `OverflowMeter_data.lua`.
-- Exposed as `mod._settings`, so per-frame code reads a table field instead of calling `mod:get`.
local settings = {
    meter_style = "gauge",
    show_title = true,
    show_rate = true,
    rate_mode = "total",
    show_allies_count = true,
    show_allies_missing = true,
    show_inactive_state = true,
    show_tier_labels = false,
    rate_window = 2,
    widget_x = 30,
    widget_y = 420,
    widget_scale = 100,
    widget_opacity = 100,
    show_summary = false,
    summary_x = 1630,
    summary_y = 850,
    scoreboard_row_generated = true,
    scoreboard_row_replenished = true,
    scoreboard_row_overflowed = true,
    scoreboard_row_shared = true,
    scoreboard_row_efficiency = true,
    summary_chat_on_end = true,
    share_mission_summary = true,
    session_stats_rows = true,
    session_stats_row_1 = "generated",
    session_stats_row_2 = "shared",
    session_stats_row_3 = "efficiency"
}

--- Every setting id mirrored into the cache.
local SETTING_IDS = {
    "meter_style",
    "show_title",
    "show_rate",
    "rate_mode",
    "show_allies_count",
    "show_allies_missing",
    "show_inactive_state",
    "show_tier_labels",
    "rate_window",
    "widget_x",
    "widget_y",
    "widget_scale",
    "widget_opacity",
    "show_summary",
    "summary_x",
    "summary_y",
    "scoreboard_row_generated",
    "scoreboard_row_replenished",
    "scoreboard_row_overflowed",
    "scoreboard_row_shared",
    "scoreboard_row_efficiency",
    "summary_chat_on_end",
    "share_mission_summary",
    "session_stats_rows",
    "session_stats_row_1",
    "session_stats_row_2",
    "session_stats_row_3"
}

--- Lookup set of `SETTING_IDS`, so a change to an uncached setting (the keybind) is ignored.
local CACHED_SETTING_IDS = {}

for i = 1, #SETTING_IDS do
    CACHED_SETTING_IDS[SETTING_IDS[i]] = true
end

--- Settings whose change refreshes mission summary sharing.
local SHARE_SETTING_IDS = {
    share_mission_summary = true
}

--- Settings whose change republishes the scoreboard snapshot (row choice and the shared value's unit).
local SNAPSHOT_SETTING_IDS = {
    rate_mode = true,
    scoreboard_row_generated = true,
    scoreboard_row_replenished = true,
    scoreboard_row_overflowed = true,
    scoreboard_row_shared = true,
    scoreboard_row_efficiency = true
}

--- Shared runtime state read by the HUD element and the integrations.
-- `_settings_version` changes with every cached setting and makes the HUD element reapply its
-- display settings; `_snapshot_settings_version` changes only for `SNAPSHOT_SETTING_IDS` and
-- makes it republish the scoreboard snapshot. `_reset_requested` asks the HUD element to reset
-- its estimator, `_summary_held` mirrors the hold keybind and `_summary_echoed` limits the
-- end-of-mission chat line to once per mission.
mod._settings = settings
mod._settings_version = 0
mod._snapshot_settings_version = 0
mod._reset_requested = false
mod._summary_held = false
mod._summary_echoed = false

--- Rereads every cached setting from DMF and bumps both settings versions.
local function refresh_settings()
    for i = 1, #SETTING_IDS do
        local setting_id = SETTING_IDS[i]
        local value = mod:get(setting_id)

        if value ~= nil then
            settings[setting_id] = value
        end
    end

    mod._settings_version = mod._settings_version + 1
    mod._snapshot_settings_version = mod._snapshot_settings_version + 1
end

refresh_settings()

--- DMF callback; updates the changed setting's cached value.
-- Numeric sliders call it for every drag step, so only the changed value is copied, and sharing
-- and the snapshot are refreshed only for the settings that affect them. A nil id rereads every
-- setting and refreshes both.
-- ?string: setting_id changed setting
mod.on_setting_changed = function (setting_id)
    if setting_id == nil then
        refresh_settings()

        mod._share.refresh()
        mod._snapshot.refresh()

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

    if SHARE_SETTING_IDS[setting_id] then
        mod._share.refresh()
    end

    if SNAPSHOT_SETTING_IDS[setting_id] then
        mod._snapshot_settings_version = mod._snapshot_settings_version + 1

        mod._snapshot.refresh()
    end
end

-- ----------------------------------------------------------------------------
-- Modules
-- ----------------------------------------------------------------------------

-- Loaded in dependency order: the pulse modules read their sources from `mod`, and the
-- snapshot reads the statistics.
mod._stats = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_stats")
mod._sources = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_sources")
mod._pulses = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_pulses")
mod._sources_veteran = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_sources_veteran")
mod._pulses_veteran = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_pulses_veteran")

--- Source models by archetype name, as returned by `player:archetype_name()` (Skitarii is `cryptic`).
mod._sources_by_archetype = {
    cryptic = mod._sources,
    veteran = mod._sources_veteran
}

--- Pulse modules by archetype name; the HUD element enables the one for the local player.
mod._pulses_by_archetype = {
    cryptic = mod._pulses,
    veteran = mod._pulses_veteran
}

mod._snapshot = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_snapshot")

-- Optional scoreboard adapters. Each registers itself with the snapshot and stays inactive
-- while its host mod is missing.
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_scoreboard")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_vt2_scoreboard")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_scores")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_power_di")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_another_scoreboard")

mod._share = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_share")

-- Optional rows in the game's own Session Stats panel on the end-of-round screen.
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_session_stats")

-- ----------------------------------------------------------------------------
-- Shared hooks
-- ----------------------------------------------------------------------------

-- A proc buff became active (weapon blessing procs). Dispatched to the enabled pulse module,
-- which checks the buff extension and template itself.
mod:hook_safe(CLASS.PlayerUnitBuffExtension, "_set_proc_active_start_time", function (self, index, activation_time, skip_send_active_time_rpc)
    local pulses = mod._pulses

    if not pulses.enabled then
        pulses = mod._pulses_veteran

        if not pulses.enabled then
            return
        end
    end

    pulses.on_proc_active(self, index)
end)

-- A local attack report (a hit, a kill, or the local player being hit). Dispatched to the
-- enabled pulse module.
mod:hook_safe(CLASS.AttackReportManager, "add_attack_result", function (self, damage_profile, attacked_unit, attacking_unit, attack_direction, hit_world_position, hit_weakspot, damage, attack_result, attack_type, damage_efficiency, is_critical_strike)
    local pulses = mod._pulses

    if not pulses.enabled then
        pulses = mod._pulses_veteran

        if not pulses.enabled then
            return
        end
    end

    pulses.on_attack_result(damage_profile, attacked_unit, attacking_unit, attack_direction, hit_world_position, hit_weakspot, damage, attack_result, attack_type, damage_efficiency, is_critical_strike)
end)

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------

--- Disables every pulse module, clearing their pending amounts and cached extensions.
-- Exposed as `mod._disable_all_pulses` for the HUD element.
local function disable_all_pulses()
    local pulses_by_archetype = mod._pulses_by_archetype

    for _, pulses in pairs(pulses_by_archetype) do
        if pulses then
            pulses.disable()
        end
    end
end

mod._disable_all_pulses = disable_all_pulses

--- DMF callback for game state changes.
-- Entering or leaving `StateGameplay` disables the pulses and asks the HUD element to reset.
-- Entering it also resets the statistics, sharing and the snapshot, so every mission starts from
-- zero; leaving keeps the totals for the end-of-round screen.
-- string: status `enter` or `exit`
-- string: state_name game state class name
mod.on_game_state_changed = function (status, state_name)
    if state_name == "StateGameplay" then
        mod._reset_requested = true

        if status == "enter" then
            mod._summary_echoed = false

            mod._stats.reset()
            mod._share.reset()
            mod._snapshot.reset()
        end

        disable_all_pulses()
    end
end

--- Writes the mission totals to the local chat, once per mission and only if anything was generated.
-- The message is passed as an argument because `mod:echo` formats its first argument and a
-- localized text can contain a literal `%`.
local function echo_mission_summary()
    if mod._summary_echoed or not settings.summary_chat_on_end then
        return
    end

    local stats = mod._stats

    if stats.generated <= 0 then
        return
    end

    mod._summary_echoed = true

    local shared = settings.rate_mode ~= "per_ally" and stats.shared_total or stats.shared
    local message = mod:localize(
        "summary_chat",
        math_floor(stats.generated + 0.5),
        math_floor(stats.replenished + 0.5),
        math_floor(stats.overflowed + 0.5),
        math_floor(shared + 0.5),
        math_floor(stats.efficiency() * 100 + 0.5)
    )

    mod:echo("%s", message)
end

-- The end-of-round screen opened. The HUD is already destroyed by then, but the module-level
-- totals survive: echo the chat line, read the teammates' published totals and push the final
-- snapshot to the scoreboards. The view is package-loaded, so the hook uses the class name and
-- DMF applies it once the class exists.
mod:hook_safe("EndView", "on_enter", function ()
    echo_mission_summary()

    mod._share.push_peers()
    mod._snapshot.flush()
end)

--- DMF callback; installs the presence hook for sharing and lets the scoreboard adapters find
-- their host mods, which only exist once every mod has loaded.
mod.on_all_mods_loaded = function ()
    mod._share.setup()
    mod._snapshot.setup()
end

--- DMF update callback; drives the periodic publishing and reading of mission summaries.
-- number: dt frame delta time
mod.update = function (dt)
    mod._share.update(dt)
end

--- DMF callback; rereads the settings and starts tracking from zero.
mod.on_enabled = function ()
    refresh_settings()

    mod._reset_requested = true

    mod._stats.reset()
    mod._share.refresh()
    mod._snapshot.reset()
end

--- DMF callback; stops tracking, clears the totals, withdraws the published summary and
-- detaches the scoreboard adapters.
mod.on_disabled = function ()
    mod._reset_requested = true
    mod._summary_held = false

    mod._stats.reset()
    mod._share.teardown()
    mod._snapshot.reset()
    mod._snapshot.teardown()

    disable_all_pulses()
end

--- DMF callback; withdraws the published summary and detaches the scoreboard adapters before unloading.
mod.on_unload = function ()
    mod._share.teardown()
    mod._snapshot.teardown()
end

--- Keybind callback of `Show summary (hold)`.
-- DMF calls it without `self` on press and again on release.
-- bool: is_pressed true while the key is held
mod.hold_mission_summary = function (is_pressed)
    mod._summary_held = is_pressed and true or false
end

-- ----------------------------------------------------------------------------
-- Scoreboard rows and HUD element
-- ----------------------------------------------------------------------------

--- Row declarations the Scoreboard mod collects from every mod's `scoreboard_rows` table.
-- `DIFF` rows add the difference between two published totals. Efficiency is a percentage
-- that must not add up, so its adapter writes the value straight into the row data.
mod.scoreboard_rows = {
    {
        name = "overflow_meter_generated",
        text = "scoreboard_generated",
        validation = "ASC",
        iteration = "DIFF",
        group = "defense",
        setting = "scoreboard_row_generated"
    },
    {
        name = "overflow_meter_replenished",
        text = "scoreboard_replenished",
        validation = "ASC",
        iteration = "DIFF",
        group = "defense",
        setting = "scoreboard_row_replenished"
    },
    {
        name = "overflow_meter_overflowed",
        text = "scoreboard_overflowed",
        validation = "ASC",
        iteration = "DIFF",
        group = "defense",
        setting = "scoreboard_row_overflowed"
    },
    {
        name = "overflow_meter_shared",
        text = "scoreboard_shared",
        validation = "ASC",
        iteration = "DIFF",
        group = "defense",
        setting = "scoreboard_row_shared"
    },
    {
        name = "overflow_meter_efficiency",
        text = "scoreboard_efficiency",
        validation = "ASC",
        iteration = "ADD",
        group = "defense",
        setting = "scoreboard_row_efficiency"
    }
}

-- The meter and the mission summary panel. The `alive` visibility group is also true in the
-- hub, so the element checks the game mode itself.
mod:register_hud_element({
    class_name = "HudElementOverflowMeter",
    filename = "OverflowMeter/scripts/mods/OverflowMeter/ui/OverflowMeter_hud_element",
    use_hud_scale = true,
    visibility_groups = {
        "alive"
    }
})

return mod
