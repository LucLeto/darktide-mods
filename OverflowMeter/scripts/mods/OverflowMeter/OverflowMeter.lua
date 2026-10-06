local mod = get_mod("OverflowMeter")

mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

local math_floor = math.floor

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
    share_mission_summary = true
}

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
    "share_mission_summary"
}

local CACHED_SETTING_IDS = {}

for i = 1, #SETTING_IDS do
    CACHED_SETTING_IDS[SETTING_IDS[i]] = true
end

local SHARE_SETTING_IDS = {
    share_mission_summary = true
}

local SNAPSHOT_SETTING_IDS = {
    rate_mode = true,
    scoreboard_row_generated = true,
    scoreboard_row_replenished = true,
    scoreboard_row_overflowed = true,
    scoreboard_row_shared = true,
    scoreboard_row_efficiency = true
}

mod._settings = settings
mod._settings_version = 0
mod._snapshot_settings_version = 0
mod._reset_requested = false
mod._summary_held = false
mod._summary_echoed = false

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

mod._stats = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_stats")
mod._sources = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_sources")
mod._pulses = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_pulses")
mod._sources_veteran = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_sources_veteran")
mod._pulses_veteran = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_pulses_veteran")

mod._sources_by_archetype = {
    cryptic = mod._sources,
    veteran = mod._sources_veteran
}

mod._pulses_by_archetype = {
    cryptic = mod._pulses,
    veteran = mod._pulses_veteran
}

mod._snapshot = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_snapshot")

mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_scoreboard")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_vt2_scoreboard")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_scores")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_power_di")
mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/integrations/OverflowMeter_another_scoreboard")

mod._share = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_share")

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

local function disable_all_pulses()
    local pulses_by_archetype = mod._pulses_by_archetype

    for _, pulses in pairs(pulses_by_archetype) do
        if pulses then
            pulses.disable()
        end
    end
end

mod._disable_all_pulses = disable_all_pulses

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

mod:hook_safe("EndView", "on_enter", function ()
    echo_mission_summary()

    mod._share.push_peers()
    mod._snapshot.flush()
end)

mod.on_all_mods_loaded = function ()
    mod._share.setup()
    mod._snapshot.setup()
end

mod.update = function (dt)
    mod._share.update(dt)
end

mod.on_enabled = function ()
    refresh_settings()

    mod._reset_requested = true

    mod._stats.reset()
    mod._share.refresh()
    mod._snapshot.reset()
end

mod.on_disabled = function ()
    mod._reset_requested = true
    mod._summary_held = false

    mod._stats.reset()
    mod._share.teardown()
    mod._snapshot.reset()
    mod._snapshot.teardown()

    disable_all_pulses()
end

mod.on_unload = function ()
    mod._share.teardown()
    mod._snapshot.teardown()
end

mod.hold_mission_summary = function (is_pressed)
    mod._summary_held = is_pressed and true or false
end

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

mod:register_hud_element({
    class_name = "HudElementOverflowMeter",
    filename = "OverflowMeter/scripts/mods/OverflowMeter/ui/OverflowMeter_hud_element",
    use_hud_scale = true,
    visibility_groups = {
        "alive"
    }
})

return mod
