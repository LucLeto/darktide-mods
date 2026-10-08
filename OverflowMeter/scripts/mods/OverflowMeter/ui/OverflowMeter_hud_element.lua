--- The HUD element that samples Toughness sharing and draws the meter and the summary panel.
-- Once a second it checks whether the local player is in a mission as a supported class with its
-- sharing talent (a Skitarius with Power Overflow or a Veteran with Born Leader) and wires up that
-- archetype's sources and pulse module. Four times a second it samples: it measures what the
-- replicated Toughness bar gained, sums the active continuous sources (Skitarii) or the modelled
-- at-full regeneration (Veteran), drains the pulse queues, counts the allies in Coherency and those
-- missing Toughness, feeds the estimator and adds the sample to the mission statistics. The meter
-- (gauge, readout, state and context lines) is only redrawn when a displayed value changes.
--
-- The mission summary panel is a second widget of the same element, shown while the hold key is
-- down or permanently. The element also pushes the local totals to the scoreboard snapshot once a
-- second, and follows Custom HUD: a box moved or resized there keeps that position and size.
--
-- Loaded by DMF from the `register_hud_element` call in `OverflowMeter.lua` and returned as the
-- `HudElementOverflowMeter` class. The rate maths come from `OverflowMeter_estimator.lua`, the
-- gauge layout from `OverflowMeter_gauge_geometry.lua`, and the archetype modules through `mod`.
-- classmod: HudElementOverflowMeter
-- author: LucLeto
local mod = get_mod("OverflowMeter")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local Estimator = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_estimator")
local Geometry = mod:io_dofile("OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_gauge_geometry")
local Stats = mod._stats
local Snapshot = mod._snapshot

local Color = Color
local ScriptUnit = ScriptUnit
local math_abs = math.abs
local math_floor = math.floor
local pairs = pairs
local string_format = string.format
local table_clear = table.clear
    or function (t)
        for k in pairs(t) do
            t[k] = nil
        end
    end

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Timing and thresholds. Support is checked every second and sharing sampled every 0.25 s;
-- full means 99.9 % Toughness, and an ally misses Toughness above half a point of damage.
local GUARD_INTERVAL = 1
local SAMPLE_INTERVAL = 0.25
local FULL_TOUGHNESS_EPSILON = 0.999
local MISSING_TOUGHNESS_EPSILON = 0.5
local ARCHETYPE_VETERAN = "veteran"

--- Supported archetypes: the sharing talent's buff template, its id in the profile's talents, the
-- meter title and the burst flash text.
local ARCHETYPES = {
    cryptic = {
        talent_buff = "cryptic_shared_toughness",
        talent_id = "cryptic_shared_toughness",
        title_key = "hud_title",
        burst_key = "ctx_burst_discharge"
    },
    veteran = {
        talent_buff = "veteran_share_toughness_gained",
        talent_id = "veteran_allies_in_coherency_share_toughness_gain",
        title_key = "hud_title_veteran",
        burst_key = "ctx_burst_share"
    },
}

--- Samples the context line shows a burst flash for (1.25 s).
local BURST_FLASH_SAMPLES = 5

--- Estimator states. The generic sharing state stands in for Useful sharing and No demand while
-- the allies-missing display is off.
local STATE_INACTIVE = Estimator.STATE_INACTIVE
local STATE_READY = Estimator.STATE_READY
local STATE_SHARING_USEFUL = Estimator.STATE_SHARING_USEFUL
local STATE_SHARING_NO_DEMAND = Estimator.STATE_SHARING_NO_DEMAND
local DISPLAY_STATE_SHARING_GENERIC = "sharing_generic"
--- Localization keys of the output tier badges.
local TIER_LOC_KEYS = {
    [Estimator.TIER_LOW] = "tier_low",
    [Estimator.TIER_MID] = "tier_mid",
    [Estimator.TIER_HIGH] = "tier_high"
}

--- Values of the `Meter style` setting.
local METER_STYLE_GAUGE = "gauge"
local METER_STYLE_TEXT = "text"
local METER_STYLE_BOTH = "both"
local METER_STYLE_NONE = "none"

--- Custom HUD: its mod id, the saved-settings keys of our two boxes, and the clamp applied to
-- the effective scale.
local CUSTOM_HUD_MOD_NAME = "custom_hud"
local CUSTOM_HUD_NODE_KEY = "HudElementOverflowMeter|overflow_meter"
local CUSTOM_HUD_SUMMARY_NODE_KEY = "HudElementOverflowMeter|overflow_summary"
local MIN_EFFECTIVE_SCALE = 0.25
local MAX_EFFECTIVE_SCALE = 3

--- Meter layout in unscaled pixels: the box, the gauge centre, radius and arc (240° opening at
-- the bottom), and the segment count and size.
local NODE_W = 280
local NODE_H = 172
local GAUGE_CENTER_X = 140
local GAUGE_CENTER_Y = 84
local GAUGE_RADIUS = 62
local GAUGE_START_DEG = 150
local GAUGE_SWEEP_DEG = 240
local SEGMENT_COUNT = 24
local SEG_W = 9
local SEG_H = 13

--- Segment centres along the gauge arc.
local SEGMENTS = Geometry.build_segments({
    count = SEGMENT_COUNT,
    radius = GAUGE_RADIUS,
    center_x = GAUGE_CENTER_X,
    center_y = GAUGE_CENTER_Y,
    start_deg = GAUGE_START_DEG,
    sweep_deg = GAUGE_SWEEP_DEG
})

--- Meter font sizes, and vertical text offsets for each layout (gauge only, text only, both).
local TITLE_FONT_SIZE = 18
local READOUT_FONT_SIZE = 27
local UNIT_FONT_SIZE = 12
local TEXT_FONT_SIZE = 16
local CONTEXT_FONT_SIZE = 14

local TITLE_OFFSET_Y = 0
local READOUT_OFFSET_Y = 56
local UNIT_OFFSET_Y = 92
local GAUGE_CONTEXT_OFFSET_Y = 138
local TEXT_STATE_OFFSET_Y = 26
local TEXT_CONTEXT_OFFSET_Y = 48
local BOTH_STATE_OFFSET_Y = 138
local BOTH_CONTEXT_OFFSET_Y = 158

--- Base alpha of each meter part, multiplied by the opacity setting.
local TITLE_ALPHA = 255
local READOUT_ALPHA = 255
local UNIT_ALPHA = 190
local TEXT_ALPHA = 255
local CONTEXT_ALPHA = 200
local SEG_LIT_ALPHA = 235
local SEG_DIM_ALPHA = 80
local SEG_PEAK_ALPHA = 255

--- Gauge colours: the lit gradient from cool teal through amber to hot red, unlit segments and
-- the peak marker.
local GRAD_COLD = { 90, 205, 180 }
local GRAD_MID = { 240, 190, 90 }
local GRAD_HOT = { 235, 92, 70 }
local SEG_DIM_RGB = { 70, 82, 86 }
local SEG_PEAK_RGB = { 245, 248, 240 }

--- Readout colours: grey when not sharing, teal while sharing, gold while an ally needs Toughness.
local READOUT_RGB_DIM = { 150, 160, 164 }
local READOUT_RGB_SHARING = { 120, 205, 185 }
local READOUT_RGB_USEFUL = { 245, 205, 120 }

--- Summary panel layout, fonts and alphas, in unscaled pixels.
local SUM_NODE_W = 260
local SUM_NODE_H = 152
local SUM_ROW_COUNT = 5
local SUM_TITLE_FONT_SIZE = 15
local SUM_ROW_FONT_SIZE = 14
local SUM_TITLE_OFFSET_Y = 0
local SUM_ROW_OFFSET_Y = 26
local SUM_ROW_STEP_Y = 22
local SUM_TITLE_ALPHA = 255
local SUM_LABEL_ALPHA = 200
local SUM_VALUE_ALPHA = 255

--- Summary rows: label localization keys and the widget content ids of labels and values.
local SUM_LABEL_KEYS = {
    "summary_generated",
    "summary_replenished",
    "summary_overflowed",
    "summary_shared",
    "summary_efficiency"
}

local SUM_LABEL_IDS = {}
local SUM_VALUE_IDS = {}

for i = 1, SUM_ROW_COUNT do
    SUM_LABEL_IDS[i] = "sum_label_" .. i
    SUM_VALUE_IDS[i] = "sum_value_" .. i
end

--- Prefix that marks an estimated value.
local ESTIMATE_PREFIX = "~"

--- Linear interpolation between two numbers.
local function _lerp(a, b, t)
    return a + (b - a) * t
end

--- Returns the gauge gradient colour at a position along the arc.
-- number: t position from 0 (first segment) to 1 (last segment)
-- treturn: tab `{ r, g, b }`
local function _gradient_rgb(t)
    local c0, c1, local_t

    if t < 0.5 then
        c0, c1, local_t = GRAD_COLD, GRAD_MID, t / 0.5
    else
        c0, c1, local_t = GRAD_MID, GRAD_HOT, (t - 0.5) / 0.5
    end

    return { math_floor(_lerp(c0[1], c1[1], local_t) + 0.5), math_floor(_lerp(c0[2], c1[2], local_t) + 0.5), math_floor(_lerp(c0[3], c1[3], local_t) + 0.5) }
end

--- Precomputed lit colour of each segment.
local SEGMENT_RGB = {}

for i = 1, SEGMENT_COUNT do
    SEGMENT_RGB[i] = _gradient_rgb(SEGMENTS[i].t)
end

-- ----------------------------------------------------------------------------
-- Widget definitions
-- ----------------------------------------------------------------------------

--- Builds the scenegraph and the two widgets.
-- The meter has the title, one rect per gauge segment, the readout and its unit, and the state
-- and context lines; the summary panel has its title and a label and value per row. Sizes and
-- offsets here are unscaled; `_apply_display_settings` scales them.
-- treturn: tab definitions with `scenegraph_definition` and `widget_definitions`
local function _build_definitions()
    local passes = {
        {
            pass_type = "text",
            value_id = "title",
            style_id = "title",
            value = "",
            style = {
                font_type = "machine_medium",
                font_size = TITLE_FONT_SIZE,
                text_horizontal_alignment = "center",
                text_vertical_alignment = "top",
                size = { NODE_W, 24 },
                offset = { 0, TITLE_OFFSET_Y, 3 },
                text_color = Color.terminal_text_header(TITLE_ALPHA, true)
            }
        }
    }

    for i = 1, SEGMENT_COUNT do
        local segment = SEGMENTS[i]

        passes[#passes + 1] = {
            pass_type = "rect",
            style_id = "seg_" .. i,
            style = {
                offset = { segment.x - SEG_W * 0.5, segment.y - SEG_H * 0.5, 2 },
                size = { SEG_W, SEG_H },
                color = { SEG_DIM_ALPHA, SEG_DIM_RGB[1], SEG_DIM_RGB[2], SEG_DIM_RGB[3] }
            }
        }
    end

    passes[#passes + 1] = {
        pass_type = "text",
        value_id = "gauge_value",
        style_id = "gauge_value",
        value = "",
        style = {
            font_type = "machine_medium",
            font_size = READOUT_FONT_SIZE,
            text_horizontal_alignment = "center",
            text_vertical_alignment = "top",
            size = { NODE_W, 36 },
            offset = { 0, READOUT_OFFSET_Y, 4 },
            text_color = { READOUT_ALPHA, READOUT_RGB_SHARING[1], READOUT_RGB_SHARING[2], READOUT_RGB_SHARING[3] }
        }
    }
    passes[#passes + 1] = {
        pass_type = "text",
        value_id = "gauge_unit",
        style_id = "gauge_unit",
        value = "",
        style = {
            font_type = "proxima_nova_bold",
            font_size = UNIT_FONT_SIZE,
            text_horizontal_alignment = "center",
            text_vertical_alignment = "top",
            size = { NODE_W, 16 },
            offset = { 0, UNIT_OFFSET_Y, 4 },
            text_color = Color.terminal_text_body(UNIT_ALPHA, true)
        }
    }

    passes[#passes + 1] = {
        pass_type = "text",
        value_id = "state_text",
        style_id = "state_text",
        value = "",
        style = {
            font_type = "proxima_nova_bold",
            font_size = TEXT_FONT_SIZE,
            text_horizontal_alignment = "center",
            text_vertical_alignment = "top",
            size = { NODE_W, 22 },
            offset = { 0, TEXT_STATE_OFFSET_Y, 3 },
            text_color = Color.terminal_text_body(TEXT_ALPHA, true)
        }
    }

    passes[#passes + 1] = {
        pass_type = "text",
        value_id = "context_text",
        style_id = "context_text",
        value = "",
        style = {
            font_type = "proxima_nova_bold",
            font_size = CONTEXT_FONT_SIZE,
            text_horizontal_alignment = "center",
            text_vertical_alignment = "top",
            size = { NODE_W, 20 },
            offset = { 0, TEXT_CONTEXT_OFFSET_Y, 3 },
            text_color = Color.terminal_text_body(CONTEXT_ALPHA, true)
        }
    }

    local summary_passes = {
        {
            pass_type = "text",
            value_id = "sum_title",
            style_id = "sum_title",
            value = "",
            style = {
                font_type = "machine_medium",
                font_size = SUM_TITLE_FONT_SIZE,
                text_horizontal_alignment = "left",
                text_vertical_alignment = "top",
                size = { SUM_NODE_W, 20 },
                offset = { 0, SUM_TITLE_OFFSET_Y, 3 },
                text_color = Color.terminal_text_header(SUM_TITLE_ALPHA, true)
            }
        }
    }

    for i = 1, SUM_ROW_COUNT do
        local row_offset_y = SUM_ROW_OFFSET_Y + (i - 1) * SUM_ROW_STEP_Y

        summary_passes[#summary_passes + 1] = {
            pass_type = "text",
            value_id = SUM_LABEL_IDS[i],
            style_id = SUM_LABEL_IDS[i],
            value = "",
            style = {
                font_type = "proxima_nova_bold",
                font_size = SUM_ROW_FONT_SIZE,
                text_horizontal_alignment = "left",
                text_vertical_alignment = "top",
                size = { SUM_NODE_W, 20 },
                offset = { 0, row_offset_y, 3 },
                text_color = Color.terminal_text_body(SUM_LABEL_ALPHA, true)
            }
        }
        summary_passes[#summary_passes + 1] = {
            pass_type = "text",
            value_id = SUM_VALUE_IDS[i],
            style_id = SUM_VALUE_IDS[i],
            value = "",
            style = {
                font_type = "proxima_nova_bold",
                font_size = SUM_ROW_FONT_SIZE,
                text_horizontal_alignment = "right",
                text_vertical_alignment = "top",
                size = { SUM_NODE_W, 20 },
                offset = { 0, row_offset_y, 3 },
                text_color = Color.terminal_text_body(SUM_VALUE_ALPHA, true)
            }
        }
    end

    return {
        scenegraph_definition = {
            screen = UIWorkspaceSettings.screen,
            overflow_meter = {
                parent = "screen",
                horizontal_alignment = "left",
                vertical_alignment = "top",
                size = { NODE_W, NODE_H },
                position = { 30, 420, 55 }
            },
            overflow_summary = {
                parent = "screen",
                horizontal_alignment = "left",
                vertical_alignment = "top",
                size = { SUM_NODE_W, SUM_NODE_H },
                position = { 1630, 850, 55 }
            }
        },
        widget_definitions = {
            meter = UIWidget.create_definition(passes, "overflow_meter"),
            summary = UIWidget.create_definition(summary_passes, "overflow_summary")
        }
    }
end

local Definitions = _build_definitions()

local HudElementOverflowMeter = class("HudElementOverflowMeter", "HudElementBase")

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------

--- Initialises the element with both widgets hidden and applies the display settings.
-- tab: parent HUD that owns the element
-- int: draw_layer element draw layer
-- number: start_scale initial UI scale
HudElementOverflowMeter.init = function (self, parent, draw_layer, start_scale)
    HudElementOverflowMeter.super.init(self, parent, draw_layer, start_scale, Definitions)

    self._estimator = Estimator.new()
    self._ctx = { buffs_by_name = {} }
    self._loc = {}
    self._supported = false
    self._archetype = nil
    self._sources = nil
    self._pulses = nil
    self._last_toughness_damage = nil
    self._last_max_toughness = nil
    self._burst_flash_remaining = 0
    self._burst_flash_amount = 0
    self._guard_timer = 0
    self._sample_timer = 0
    self._opacity = 1
    self._force_refresh = true
    self._summary_shown = false
    self._sum_value_cache = {}
    self._last_scoreboard_version = nil
    self._last_scoreboard_settings_version = nil

    self:_clear_render_cache()

    self._widgets_by_name.meter.content.visible = false
    self._widgets_by_name.summary.content.visible = false

    self:_apply_display_settings(mod._settings)
end

--- Forgets every last-drawn value, so the next refresh rewrites everything.
HudElementOverflowMeter._clear_render_cache = function (self)
    self._last_display_state = nil
    self._last_rate_str = nil
    self._last_allies = nil
    self._last_allies_missing = nil
    self._last_tier = nil
    self._last_burst_active = nil
    self._last_burst_amount = nil
    self._last_state_text = nil
    self._last_context_text = nil
    self._last_lit = nil
    self._last_peak_index = nil
    self._last_gauge_value = nil
    self._last_summary_version = nil

    local sum_value_cache = self._sum_value_cache

    for i = 1, SUM_ROW_COUNT do
        sum_value_cache[i] = nil
    end
end

--- Per-frame update.
-- Reapplies the display settings after a change and resets after a reset request. Once a second
-- it follows Custom HUD changes, rechecks support and pushes the scoreboard snapshot. The summary
-- panel refreshes every frame when its data changed; while supported and the player unit is
-- alive, sharing is sampled and the meter refreshed every `SAMPLE_INTERVAL`.
-- number: dt frame delta time
-- number: t time
-- tab: ui_renderer UI renderer
-- tab: render_settings render settings
-- tab: input_service input service
HudElementOverflowMeter.update = function (self, dt, t, ui_renderer, render_settings, input_service)
    HudElementOverflowMeter.super.update(self, dt, t, ui_renderer, render_settings, input_service)

    local settings = mod._settings

    if mod._settings_version ~= self._applied_settings_version then
        self:_apply_display_settings(settings)

        self._guard_timer = 0
        self._force_refresh = true
    end

    if mod._reset_requested then
        mod._reset_requested = false

        self._estimator:reset()

        self._last_toughness_damage = nil
        self._burst_flash_remaining = 0

        self._guard_timer = 0
        self._force_refresh = true
    end

    self._guard_timer = self._guard_timer - dt

    if self._guard_timer <= 0 then
        self._guard_timer = GUARD_INTERVAL

        local ch_managed, ch_factor = self:_custom_hud_layout()
        local sum_managed, sum_factor = self:_custom_hud_node(CUSTOM_HUD_SUMMARY_NODE_KEY, SUM_NODE_W)

        if ch_managed ~= self._applied_ch_managed or ch_factor ~= self._applied_ch_factor or sum_managed ~= self._applied_sum_managed or sum_factor ~= self._applied_sum_factor then
            self:_apply_display_settings(settings)

            self._force_refresh = true
        end

        local supported = self:_check_supported(settings)

        if supported ~= self._supported then
            self._supported = supported

            if supported then
                self._sample_timer = 0
                self._force_refresh = true
            else
                self:_reset_display()
            end
        end

        self:_push_scoreboard(settings)
    end

    self:_refresh_summary(settings)

    if not self._supported then
        return
    end

    local alive_units = ALIVE

    if not alive_units or not alive_units[self._ctx.unit] then
        self._supported = false
        self._guard_timer = 0

        self:_reset_display()

        return
    end

    self._sample_timer = self._sample_timer - dt

    if self._sample_timer <= 0 then
        self._sample_timer = SAMPLE_INTERVAL

        self:_sample()
        self:_refresh_display(settings)
    end
end

-- ----------------------------------------------------------------------------
-- Custom HUD and support
-- ----------------------------------------------------------------------------

--- Reads Custom HUD's saved settings for one of our boxes.
-- Custom HUD positions a box it manages itself but never resizes it, so a saved width that differs
-- from the box's default is applied here as a scale factor.
-- string: node_key saved-settings key of the box
-- number: node_width the box's unscaled width
-- treturn: bool whether Custom HUD manages the box
-- treturn: ?number scale factor when it was resized there
HudElementOverflowMeter._custom_hud_node = function (self, node_key, node_width)
    local custom_hud = get_mod(CUSTOM_HUD_MOD_NAME)

    if not custom_hud or not custom_hud.is_enabled or not custom_hud:is_enabled() then
        return false, nil
    end

    local saved = custom_hud.get and custom_hud:get("saved_node_settings")
    local entry = saved and saved[node_key]

    if not entry then
        return false, nil
    end

    local size = entry.size
    local default_settings = entry.default_settings
    local default_size = default_settings and default_settings.size
    local width = size and size[1]
    local default_width = default_size and default_size[1]

    if width and width > 0 and default_width and default_width > 0 and math_abs(width - default_width) > 0.5 then
        return true, width / node_width
    end

    return true, nil
end

--- Reads Custom HUD's saved settings for the meter box.
-- treturn: bool whether Custom HUD manages the box
-- treturn: ?number scale factor when it was resized there
HudElementOverflowMeter._custom_hud_layout = function (self)
    return self:_custom_hud_node(CUSTOM_HUD_NODE_KEY, NODE_W)
end

--- Returns whether the meter can run now, and wires the archetype's modules when it can.
-- Needs a mission (not the hub), a living local player unit of a supported archetype with its
-- sharing talent, and the buff and toughness extensions. The talent is read from the talent
-- extension, falling back to the profile's talents, whose entries are numbers before 1.13 and
-- `{ tier, ... }` tables since. On success it caches the extensions in the sample context and
-- enables the archetype's pulse module.
-- tab: settings cached settings
-- treturn: bool
HudElementOverflowMeter._check_supported = function (self, settings)
    local alive_units = ALIVE

    if not alive_units then
        return false
    end

    local state_managers = Managers.state
    local game_mode_manager = state_managers and state_managers.game_mode

    if not game_mode_manager then
        return false
    end

    local game_mode_name = game_mode_manager:game_mode_name()

    if game_mode_name == "hub" or game_mode_name == "prologue_hub" then
        return false
    end

    local player_manager = Managers.player
    local player = player_manager and player_manager.local_player_safe and player_manager:local_player_safe(1)

    if not player then
        return false
    end

    local player_unit = player.player_unit

    if not player_unit or not alive_units[player_unit] then
        return false
    end

    local archetype = player.archetype_name and player:archetype_name()
    local archetype_config = archetype and ARCHETYPES[archetype]

    if not archetype_config then
        return false
    end

    local talent_extension = ScriptUnit.has_extension(player_unit, "talent_system")
    local has_talent = false

    if talent_extension and talent_extension.buff_template_tier then
        local tier = talent_extension:buff_template_tier(archetype_config.talent_buff)

        has_talent = tier ~= nil and tier ~= 0
    end

    if not has_talent and player.profile then
        local profile = player:profile()
        local talents = profile and profile.talents
        local points = talents and talents[archetype_config.talent_id]

        if type(points) == "table" then
            points = points.tier
        end

        has_talent = points ~= nil and points ~= 0
    end

    if not has_talent then
        return false
    end

    local buff_extension = ScriptUnit.has_extension(player_unit, "buff_system")
    local toughness_extension = ScriptUnit.has_extension(player_unit, "toughness_system")

    if not buff_extension or not toughness_extension then
        return false
    end

    self:_set_archetype(archetype)

    local ctx = self._ctx

    ctx.unit = player_unit
    ctx.buff_extension = buff_extension
    ctx.toughness_extension = toughness_extension
    ctx.talent_extension = talent_extension
    ctx.ability_extension = ScriptUnit.has_extension(player_unit, "ability_system")
    ctx.coherency_extension = ScriptUnit.has_extension(player_unit, "coherency_system")

    self._pulses.set_context(player_unit, buff_extension, toughness_extension, talent_extension)

    return true
end

--- Switches to an archetype's sources, pulses, estimator mode, statistics context and texts.
-- Does nothing when the archetype is unchanged.
-- string: archetype archetype name
HudElementOverflowMeter._set_archetype = function (self, archetype)
    if self._archetype == archetype then
        return
    end

    mod._disable_all_pulses()

    self._archetype = archetype
    self._sources = mod._sources_by_archetype[archetype]
    self._pulses = mod._pulses_by_archetype[archetype]
    self._last_toughness_damage = nil
    self._burst_flash_remaining = 0

    local sources = self._sources

    self._estimator:set_mode(sources.continuous_when_full, sources.has_inactive_state)

    Stats.set_context(archetype, sources.share_fraction)

    self:_refresh_localization()
    self:_clear_render_cache()

    self._force_refresh = true
end

-- ----------------------------------------------------------------------------
-- Sampling
-- ----------------------------------------------------------------------------

--- Counts the living allies in Coherency and those of them missing Toughness.
-- treturn: int allies
-- treturn: int allies missing Toughness
HudElementOverflowMeter._count_allies = function (self)
    local allies = 0
    local allies_missing = 0
    local coherency_extension = self._ctx.coherency_extension

    if coherency_extension and coherency_extension.in_coherence_units then
        local units_in_coherency = coherency_extension:in_coherence_units()

        if units_in_coherency then
            local player_unit = self._ctx.unit
            local alive_units = ALIVE

            for coherency_unit in pairs(units_in_coherency) do
                if coherency_unit ~= player_unit and alive_units[coherency_unit] then
                    local ally_toughness_extension = ScriptUnit.has_extension(coherency_unit, "toughness_system")

                    if ally_toughness_extension then
                        allies = allies + 1

                        if ally_toughness_extension:toughness_damage() > MISSING_TOUGHNESS_EPSILON then
                            allies_missing = allies_missing + 1
                        end
                    end
                end
            end
        end
    end

    return allies, allies_missing
end

--- Returns how much Toughness the bar gained since the last sample.
-- A sample in which maximum Toughness changed is skipped, so a raised cap (such as Duty and
-- Honour's bonus Toughness) is not mistaken for a replenish.
-- number: toughness_damage current Toughness damage
-- number: max_toughness current maximum Toughness
-- treturn: number Toughness points recovered, 0 or more
HudElementOverflowMeter._consume_bar_gain = function (self, toughness_damage, max_toughness)
    local last_damage = self._last_toughness_damage
    local bar_gain = 0

    if last_damage and self._last_max_toughness == max_toughness then
        local recovered = last_damage - toughness_damage

        if recovered > 0 then
            bar_gain = recovered
        end
    end

    self._last_toughness_damage = toughness_damage
    self._last_max_toughness = max_toughness

    return bar_gain
end

--- Starts a burst flash for a new one-off share, or counts down the current one.
-- A new burst also raises the estimator's burst marker while an ally is in Coherency.
-- number: burst_share Toughness each ally gets from the burst, 0 for none
-- int: allies allies in Coherency
-- int: ally_multiplier allies counted by the rate display (all of them, or 1 per ally)
HudElementOverflowMeter._update_burst_flash = function (self, burst_share, allies, ally_multiplier)
    if burst_share > 0 then
        if allies > 0 then
            self._estimator:register_burst(burst_share * ally_multiplier / SAMPLE_INTERVAL)
        end

        self._burst_flash_amount = burst_share
        self._burst_flash_remaining = BURST_FLASH_SAMPLES
    elseif self._burst_flash_remaining > 0 then
        self._burst_flash_remaining = self._burst_flash_remaining - 1
    end
end

--- Takes one Power Overflow sample, or hands over to `_sample_veteran` for a Veteran.
-- Power Overflow shares 25 % of what is replenished at full. The continuous rate is the sum of the
-- active adapters, scaled by the replenish stat buffs; it counts only at full. Pulses that landed
-- at full add a one-sample spike and a Voltaic Overcharge restore a burst flash. The statistics
-- get the bar gain, the overflow (pulse overflow plus the continuous amount at full) and the
-- shareable amount.
HudElementOverflowMeter._sample = function (self)
    if self._archetype == ARCHETYPE_VETERAN then
        self:_sample_veteran()

        return
    end

    local ctx = self._ctx
    local sources = self._sources
    local pulses = self._pulses
    local buffs_by_name = ctx.buffs_by_name

    table_clear(buffs_by_name)

    local buff_extension = ctx.buff_extension
    local relevant_buff_names = sources.relevant_buff_names
    local buffs = buff_extension.buffs and buff_extension:buffs()

    if buffs then
        for i = 1, #buffs do
            local buff_instance = buffs[i]
            local template = buff_instance.template and buff_instance:template()
            local template_name = template and template.name

            if template_name and relevant_buff_names[template_name] then
                buffs_by_name[template_name] = buff_instance
            end
        end
    end

    local toughness_extension = ctx.toughness_extension
    local max_toughness = toughness_extension:max_toughness()
    local is_full = toughness_extension:current_toughness_percent() >= FULL_TOUGHNESS_EPSILON
    local bar_gain = self:_consume_bar_gain(toughness_extension:toughness_damage(), max_toughness)
    local adapters = sources.adapters
    local total_rate = 0

    for i = 1, #adapters do
        local adapter = adapters[i]

        if adapter.is_active(ctx) then
            total_rate = total_rate + adapter.estimate_per_second(ctx)
        end
    end

    local replenish_multiplier = 1
    local stat_buffs = buff_extension.stat_buffs and buff_extension:stat_buffs()

    if stat_buffs then
        replenish_multiplier = (stat_buffs.toughness_replenish_modifier or 1) * (stat_buffs.toughness_replenish_multiplier or 1)
    end

    local share_per_ally_per_second = total_rate > 0 and total_rate * max_toughness * replenish_multiplier * sources.share_fraction or 0

    local allies, allies_missing = self:_count_allies()
    local ally_multiplier

    if self._rate_mode_total then
        ally_multiplier = allies
    else
        ally_multiplier = allies > 0 and 1 or 0
    end

    local pending_pulse_fraction = pulses.consume()
    local pulse_offered_per_second = 0

    if pending_pulse_fraction > 0 and allies > 0 then
        pulse_offered_per_second = pending_pulse_fraction * max_toughness * sources.share_fraction * ally_multiplier / SAMPLE_INTERVAL
    end

    local pending_burst_fraction = pulses.consume_burst_fraction()

    self:_update_burst_flash(pending_burst_fraction * max_toughness * sources.share_fraction, allies, ally_multiplier)

    local nominal_ceiling = sources.available_max_fraction(ctx) * max_toughness * sources.share_fraction * ally_multiplier

    self._estimator:sample(is_full, total_rate > 0, share_per_ally_per_second * ally_multiplier, pulse_offered_per_second, nominal_ceiling, allies, allies_missing)

    local stats_overflow = pulses.consume_overflow()
    local stats_shareable = (pending_pulse_fraction + pending_burst_fraction) * max_toughness

    if is_full and total_rate > 0 then
        local continuous_amount = total_rate * max_toughness * replenish_multiplier * SAMPLE_INTERVAL

        stats_overflow = stats_overflow + continuous_amount
        stats_shareable = stats_shareable + continuous_amount
    end

    Stats.add_event(bar_gain, stats_overflow, stats_shareable, allies)
end

--- Takes one Born Leader sample.
-- Born Leader shares 20 % of every replenish. Below full the bar gain is the continuous rate,
-- which already covers every source; at full the modelled regeneration takes its place, scaled
-- by the replenish stat buffs. Pulses add their clamped excess, and Voice of Command or
-- Infiltrate a burst flash. Everything generated (bar gain plus overflow) is shareable.
HudElementOverflowMeter._sample_veteran = function (self)
    local ctx = self._ctx
    local sources = self._sources
    local pulses = self._pulses
    local toughness_extension = ctx.toughness_extension
    local buff_extension = ctx.buff_extension
    local max_toughness = toughness_extension:max_toughness()
    local toughness_damage = toughness_extension:toughness_damage()
    local is_full = toughness_extension:current_toughness_percent() >= FULL_TOUGHNESS_EPSILON
    local share_fraction = sources.share_fraction
    local bar_gain = self:_consume_bar_gain(toughness_damage, max_toughness)

    local allies, allies_missing = self:_count_allies()
    local ally_multiplier

    if self._rate_mode_total then
        ally_multiplier = allies
    else
        ally_multiplier = allies > 0 and 1 or 0
    end

    local continuous_offered_per_second = 0

    if bar_gain > 0 and allies > 0 then
        continuous_offered_per_second = share_fraction * bar_gain * ally_multiplier / SAMPLE_INTERVAL
    end

    local pending_excess = pulses.consume()
    local pulse_offered_per_second = 0

    if pending_excess > 0 and allies > 0 then
        pulse_offered_per_second = share_fraction * pending_excess * ally_multiplier / SAMPLE_INTERVAL
    end

    local continuous_overflow = 0

    if is_full then
        local continuous_fraction = pulses.active_continuous_fraction()

        if continuous_fraction > 0 then
            local replenish_multiplier = 1
            local stat_buffs = buff_extension.stat_buffs and buff_extension:stat_buffs()

            if stat_buffs then
                replenish_multiplier = (stat_buffs.toughness_replenish_modifier or 1) * (stat_buffs.toughness_replenish_multiplier or 1)
            end

            local continuous_per_second = continuous_fraction * max_toughness * replenish_multiplier

            continuous_overflow = continuous_per_second * SAMPLE_INTERVAL

            if allies > 0 then
                pulse_offered_per_second = pulse_offered_per_second + share_fraction * continuous_per_second * ally_multiplier
            end
        end
    end

    self:_update_burst_flash(pulses.consume_burst(), allies, ally_multiplier)

    local nominal_ceiling = sources.available_max_fraction(ctx) * max_toughness * share_fraction * ally_multiplier

    self._estimator:sample(is_full, bar_gain > 0, continuous_offered_per_second, pulse_offered_per_second, nominal_ceiling, allies, allies_missing)

    local stats_overflow = pending_excess + continuous_overflow + pulses.consume_burst_overflow()

    Stats.add_event(bar_gain, stats_overflow, bar_gain + stats_overflow, allies)
end

-- ----------------------------------------------------------------------------
-- Meter display
-- ----------------------------------------------------------------------------

--- Returns the state to display, merging Useful sharing and No demand while the allies-missing
-- display is off.
-- tab: settings cached settings
-- treturn: string
HudElementOverflowMeter._display_state = function (self, settings)
    local state = self._estimator.state

    if not settings.show_allies_missing and (state == STATE_SHARING_USEFUL or state == STATE_SHARING_NO_DEMAND) then
        return DISPLAY_STATE_SHARING_GENERIC
    end

    return state
end

--- Shows or hides the meter and refreshes the gauge and the texts after a sample.
-- The meter is hidden for the `None` style, and in the Inactive state unless that is shown.
-- tab: settings cached settings
HudElementOverflowMeter._refresh_display = function (self, settings)
    local estimator = self._estimator
    local widget = self._widgets_by_name.meter
    local content = widget.content

    if not self._show_meter or (estimator.state == STATE_INACTIVE and not settings.show_inactive_state) then
        if content.visible then
            content.visible = false
            widget.dirty = true
        end

        return
    end

    if not content.visible then
        content.visible = true
        widget.dirty = true
    end

    local display_state = self:_display_state(settings)
    local dirty = false

    if self._show_gauge then
        dirty = self:_refresh_gauge(settings, display_state) or dirty
    end

    dirty = self:_refresh_text(settings, display_state) or dirty

    if dirty or self._force_refresh then
        widget.dirty = true
    end

    self._force_refresh = false
end

--- Recolours the segments and updates the readout when the lit count, the peak or the rate changed.
-- tab: settings cached settings
-- string: display_state state from `_display_state`
-- treturn: bool whether anything changed
HudElementOverflowMeter._refresh_gauge = function (self, settings, display_state)
    local estimator = self._estimator
    local widget = self._widgets_by_name.meter
    local style = widget.style
    local content = widget.content
    local dirty = false

    local lit = Geometry.lit_count(estimator.fill_fraction, SEGMENT_COUNT)
    local peak_index = Geometry.marker_index(estimator.peak_fraction, SEGMENT_COUNT)
    local opacity = self._opacity

    if self._force_refresh or lit ~= self._last_lit or peak_index ~= self._last_peak_index then
        self._last_lit = lit
        self._last_peak_index = peak_index

        local lit_alpha = math_floor(SEG_LIT_ALPHA * opacity)
        local dim_alpha = math_floor(SEG_DIM_ALPHA * opacity)
        local peak_alpha = math_floor(SEG_PEAK_ALPHA * opacity)

        for i = 1, SEGMENT_COUNT do
            local color = style["seg_" .. i].color

            if i <= lit then
                local rgb = SEGMENT_RGB[i]

                color[1] = lit_alpha
                color[2] = rgb[1]
                color[3] = rgb[2]
                color[4] = rgb[3]
            elseif i == peak_index and peak_index > lit then
                color[1] = peak_alpha
                color[2] = SEG_PEAK_RGB[1]
                color[3] = SEG_PEAK_RGB[2]
                color[4] = SEG_PEAK_RGB[3]
            else
                color[1] = dim_alpha
                color[2] = SEG_DIM_RGB[1]
                color[3] = SEG_DIM_RGB[2]
                color[4] = SEG_DIM_RGB[3]
            end
        end

        dirty = true
    end

    local value_str = settings.show_rate and ("~" .. string_format("%.1f", estimator.display_rate)) or ""

    if self._force_refresh or value_str ~= self._last_gauge_value then
        self._last_gauge_value = value_str
        content.gauge_value = value_str
        content.gauge_unit = self._loc.unit_toughness_per_second

        local rgb = READOUT_RGB_DIM

        if display_state == STATE_SHARING_USEFUL then
            rgb = READOUT_RGB_USEFUL
        elseif display_state == STATE_SHARING_NO_DEMAND or display_state == DISPLAY_STATE_SHARING_GENERIC then
            rgb = READOUT_RGB_SHARING
        end

        local value_color = style.gauge_value.text_color

        value_color[1] = math_floor(READOUT_ALPHA * opacity)
        value_color[2] = rgb[1]
        value_color[3] = rgb[2]
        value_color[4] = rgb[3]

        dirty = true
    end

    return dirty
end

--- Rebuilds the state and context lines when any value they show changed.
-- The state line carries the rate and, when enabled, the tier badge; the context line shows the
-- allies, the allies in need or a hint, and is replaced by the burst flash while one runs.
-- tab: settings cached settings
-- string: display_state state from `_display_state`
-- treturn: bool whether anything changed
HudElementOverflowMeter._refresh_text = function (self, settings, display_state)
    local estimator = self._estimator
    local allies = estimator.allies
    local allies_missing = estimator.allies_missing
    local rate_str = settings.show_rate and string_format("%.1f", estimator.display_rate) or ""
    local tier = (settings.show_tier_labels and self._archetype ~= nil) and estimator.tier or 0
    local burst_active = (self._burst_flash_remaining or 0) > 0
    local burst_amount = burst_active and math_floor(self._burst_flash_amount + 0.5) or 0

    if not self._force_refresh and display_state == self._last_display_state and rate_str == self._last_rate_str and allies == self._last_allies and allies_missing == self._last_allies_missing and tier == self._last_tier and burst_active == self._last_burst_active and burst_amount == self._last_burst_amount then
        return false
    end

    self._last_display_state = display_state
    self._last_rate_str = rate_str
    self._last_allies = allies
    self._last_allies_missing = allies_missing
    self._last_tier = tier
    self._last_burst_active = burst_active
    self._last_burst_amount = burst_amount

    local loc = self._loc
    local content = self._widgets_by_name.meter.content
    local state_text, context_text
    local sharing = false

    local rate_key_suffix = self._rate_mode_total and "" or "_per_ally"

    if display_state == STATE_INACTIVE then
        state_text = loc.state_inactive
        context_text = loc.ctx_inactive
    elseif display_state == STATE_READY then
        state_text = loc.state_ready
        context_text = self:_allies_context_text(allies, settings)
    elseif display_state == STATE_SHARING_USEFUL then
        state_text = self:_rate_state_text(loc.state_useful, "state_useful_rate" .. rate_key_suffix, rate_str, settings)
        context_text = mod:localize(allies_missing == 1 and "ctx_needs_one" or "ctx_needs_many", allies_missing)
        sharing = true
    elseif display_state == STATE_SHARING_NO_DEMAND then
        state_text = self:_rate_state_text(loc.state_sharing, "state_sharing_rate" .. rate_key_suffix, rate_str, settings)
        context_text = loc.ctx_no_demand
        sharing = true
    else
        state_text = self:_rate_state_text(loc.state_sharing, "state_sharing_rate" .. rate_key_suffix, rate_str, settings)
        context_text = self:_allies_context_text(allies, settings)
        sharing = true
    end

    if tier ~= 0 and sharing then
        local tier_text = loc.tier[tier]

        if tier_text then
            state_text = state_text .. " · " .. tier_text
        end
    end

    if burst_active then
        local archetype_config = ARCHETYPES[self._archetype]

        context_text = mod:localize(archetype_config and archetype_config.burst_key or "ctx_burst_share", burst_amount)
    end

    local dirty = false

    if self._show_text and state_text ~= self._last_state_text then
        self._last_state_text = state_text
        content.state_text = state_text
        dirty = true
    end

    if context_text ~= self._last_context_text then
        self._last_context_text = context_text
        content.context_text = context_text
        dirty = true
    end

    return dirty
end

-- ----------------------------------------------------------------------------
-- Summary panel and scoreboard
-- ----------------------------------------------------------------------------

--- Sets a summary row's value text if it changed.
-- int: index row index
-- string: text value text
-- treturn: bool whether it changed
HudElementOverflowMeter._set_summary_value = function (self, index, text)
    local sum_value_cache = self._sum_value_cache

    if sum_value_cache[index] == text then
        return false
    end

    sum_value_cache[index] = text
    self._widgets_by_name.summary.content[SUM_VALUE_IDS[index]] = text

    return true
end

--- Shows the summary panel while the hold key is down or it is always shown, and while there is
-- something to show; rewrites its values when the statistics changed.
-- tab: settings cached settings
HudElementOverflowMeter._refresh_summary = function (self, settings)
    local widget = self._widgets_by_name.summary

    if not (settings.show_summary or mod._summary_held) or not (self._supported or Stats.generated > 0) then
        if self._summary_shown then
            self._summary_shown = false
            widget.content.visible = false
            widget.dirty = true
        end

        return
    end

    local version = Stats.version
    local became_visible = not self._summary_shown

    if not became_visible and version == self._last_summary_version then
        return
    end

    self._summary_shown = true
    self._last_summary_version = version

    local dirty = became_visible

    if became_visible then
        widget.content.visible = true
    end

    local shared = self._rate_mode_total and Stats.shared_total or Stats.shared

    dirty = self:_set_summary_value(1, ESTIMATE_PREFIX .. string_format("%d", math_floor(Stats.generated + 0.5))) or dirty
    dirty = self:_set_summary_value(2, string_format("%d", math_floor(Stats.replenished + 0.5))) or dirty
    dirty = self:_set_summary_value(3, ESTIMATE_PREFIX .. string_format("%d", math_floor(Stats.overflowed + 0.5))) or dirty
    dirty = self:_set_summary_value(4, ESTIMATE_PREFIX .. string_format("%d", math_floor(shared + 0.5))) or dirty
    dirty = self:_set_summary_value(5, ESTIMATE_PREFIX .. string_format("%d%%", math_floor(Stats.efficiency() * 100 + 0.5))) or dirty

    if dirty then
        widget.dirty = true
    end
end

--- Copies the local totals into the scoreboard snapshot and publishes the change.
-- Skipped while neither the statistics nor the snapshot settings changed.
-- tab: settings cached settings
HudElementOverflowMeter._push_scoreboard = function (self, settings)
    local stats_version = Stats.version
    local settings_version = mod._snapshot_settings_version

    if stats_version == self._last_scoreboard_version and settings_version == self._last_scoreboard_settings_version then
        return
    end

    local player_manager = Managers.player
    local player = player_manager and player_manager.local_player_safe and player_manager:local_player_safe(1)
    local account_id = player and player.account_id and player:account_id()

    if not account_id then
        return
    end

    self._last_scoreboard_version = stats_version
    self._last_scoreboard_settings_version = settings_version

    Snapshot.update_local(account_id, self._archetype)
    Snapshot.publish(false)
end

-- ----------------------------------------------------------------------------
-- Text helpers
-- ----------------------------------------------------------------------------

--- Returns a state text with the rate, or the plain text while the rate is hidden.
-- string: plain_text state text without the rate
-- string: rate_key localization key of the text with the rate
-- string: rate_str formatted rate
-- tab: settings cached settings
-- treturn: string
HudElementOverflowMeter._rate_state_text = function (self, plain_text, rate_key, rate_str, settings)
    if not settings.show_rate then
        return plain_text
    end

    return mod:localize(rate_key, rate_str)
end

--- Returns the allies-in-Coherency context text, or an empty string while it is hidden.
-- int: allies allies in Coherency
-- tab: settings cached settings
-- treturn: string
HudElementOverflowMeter._allies_context_text = function (self, allies, settings)
    if not settings.show_allies_count then
        return ""
    end

    return mod:localize(allies == 1 and "ctx_allies_one" or "ctx_allies_many", allies)
end

-- ----------------------------------------------------------------------------
-- Settings and localization
-- ----------------------------------------------------------------------------

--- Stops tracking and hides the meter, when the meter is no longer supported.
HudElementOverflowMeter._reset_display = function (self)
    self._estimator:reset()
    mod._disable_all_pulses()

    self._last_toughness_damage = nil
    self._burst_flash_remaining = 0

    self:_clear_render_cache()

    local widget = self._widgets_by_name.meter

    if widget.content.visible then
        widget.content.visible = false
        widget.dirty = true
    end
end

--- Applies the display settings to both widgets.
-- Positions each box unless Custom HUD manages it, scales it by the Custom HUD size or the
-- `Meter size` setting (clamped to 25 to 300 %), applies the opacity and the meter style's
-- layout, sets the averaging window, resets the estimator when the rate unit changed, and
-- refreshes every text.
-- tab: settings cached settings
HudElementOverflowMeter._apply_display_settings = function (self, settings)
    self._applied_settings_version = mod._settings_version

    local ch_managed, ch_factor = self:_custom_hud_layout()
    local sum_managed, sum_factor = self:_custom_hud_node(CUSTOM_HUD_SUMMARY_NODE_KEY, SUM_NODE_W)

    self._applied_ch_managed = ch_managed
    self._applied_ch_factor = ch_factor
    self._applied_sum_managed = sum_managed
    self._applied_sum_factor = sum_factor

    if not ch_managed then
        self:set_scenegraph_position("overflow_meter", settings.widget_x, settings.widget_y)
    end

    if not sum_managed then
        self:set_scenegraph_position("overflow_summary", settings.summary_x, settings.summary_y)
    end

    local widget_scale = (settings.widget_scale or 100) / 100
    local scale = ch_factor or widget_scale

    if scale < MIN_EFFECTIVE_SCALE then
        scale = MIN_EFFECTIVE_SCALE
    elseif scale > MAX_EFFECTIVE_SCALE then
        scale = MAX_EFFECTIVE_SCALE
    end

    local sum_scale = sum_factor or widget_scale

    if sum_scale < MIN_EFFECTIVE_SCALE then
        sum_scale = MIN_EFFECTIVE_SCALE
    elseif sum_scale > MAX_EFFECTIVE_SCALE then
        sum_scale = MAX_EFFECTIVE_SCALE
    end

    local opacity = (settings.widget_opacity or 100) / 100

    self._opacity = opacity

    local meter_style = settings.meter_style or METER_STYLE_GAUGE
    local show_gauge = meter_style == METER_STYLE_GAUGE or meter_style == METER_STYLE_BOTH
    local show_text = meter_style == METER_STYLE_TEXT or meter_style == METER_STYLE_BOTH

    self._show_meter = meter_style ~= METER_STYLE_NONE
    self._show_gauge = show_gauge
    self._show_text = show_text

    self:_set_scenegraph_size("overflow_meter", NODE_W * scale, NODE_H * scale)

    local widget = self._widgets_by_name.meter
    local style = widget.style
    local node_w = NODE_W * scale

    style.title.font_size = TITLE_FONT_SIZE * scale
    style.title.offset[2] = TITLE_OFFSET_Y * scale
    style.title.size[1] = node_w
    style.title.visible = settings.show_title ~= false
    style.title.text_color[1] = math_floor(TITLE_ALPHA * opacity)

    for i = 1, SEGMENT_COUNT do
        local segment = SEGMENTS[i]
        local seg_style = style["seg_" .. i]
        local seg_w = SEG_W * scale
        local seg_h = SEG_H * scale

        seg_style.size[1] = seg_w
        seg_style.size[2] = seg_h
        seg_style.offset[1] = segment.x * scale - seg_w * 0.5
        seg_style.offset[2] = segment.y * scale - seg_h * 0.5
        seg_style.visible = show_gauge
    end

    style.gauge_value.font_size = READOUT_FONT_SIZE * scale
    style.gauge_value.offset[2] = READOUT_OFFSET_Y * scale
    style.gauge_value.size[1] = node_w
    style.gauge_value.visible = show_gauge
    style.gauge_unit.font_size = UNIT_FONT_SIZE * scale
    style.gauge_unit.offset[2] = UNIT_OFFSET_Y * scale
    style.gauge_unit.size[1] = node_w
    style.gauge_unit.visible = show_gauge and settings.show_rate
    style.gauge_unit.text_color[1] = math_floor(UNIT_ALPHA * opacity)

    local state_offset_y = show_gauge and BOTH_STATE_OFFSET_Y or TEXT_STATE_OFFSET_Y

    style.state_text.font_size = TEXT_FONT_SIZE * scale
    style.state_text.offset[2] = state_offset_y * scale
    style.state_text.size[1] = node_w
    style.state_text.visible = show_text
    style.state_text.text_color[1] = math_floor(TEXT_ALPHA * opacity)

    local context_offset_y = TEXT_CONTEXT_OFFSET_Y

    if show_gauge and show_text then
        context_offset_y = BOTH_CONTEXT_OFFSET_Y
    elseif show_gauge then
        context_offset_y = GAUGE_CONTEXT_OFFSET_Y
    end

    style.context_text.font_size = CONTEXT_FONT_SIZE * scale
    style.context_text.offset[2] = context_offset_y * scale
    style.context_text.size[1] = node_w
    style.context_text.text_color[1] = math_floor(CONTEXT_ALPHA * opacity)

    local window_samples = math_floor((settings.rate_window or 2) / SAMPLE_INTERVAL + 0.5)

    self._estimator:set_window(window_samples)

    local rate_mode_total = settings.rate_mode ~= "per_ally"

    if rate_mode_total ~= self._rate_mode_total then
        self._rate_mode_total = rate_mode_total

        self._estimator:reset()
    end

    local summary_widget = self._widgets_by_name.summary
    local summary_style = summary_widget.style
    local sum_node_w = SUM_NODE_W * sum_scale

    self:_set_scenegraph_size("overflow_summary", sum_node_w, SUM_NODE_H * sum_scale)

    summary_style.sum_title.font_size = SUM_TITLE_FONT_SIZE * sum_scale
    summary_style.sum_title.offset[2] = SUM_TITLE_OFFSET_Y * sum_scale
    summary_style.sum_title.size[1] = sum_node_w
    summary_style.sum_title.text_color[1] = math_floor(SUM_TITLE_ALPHA * opacity)

    for i = 1, SUM_ROW_COUNT do
        local row_offset_y = (SUM_ROW_OFFSET_Y + (i - 1) * SUM_ROW_STEP_Y) * sum_scale
        local label_style = summary_style[SUM_LABEL_IDS[i]]
        local value_style = summary_style[SUM_VALUE_IDS[i]]

        label_style.font_size = SUM_ROW_FONT_SIZE * sum_scale
        label_style.offset[2] = row_offset_y
        label_style.size[1] = sum_node_w
        label_style.text_color[1] = math_floor(SUM_LABEL_ALPHA * opacity)

        value_style.font_size = SUM_ROW_FONT_SIZE * sum_scale
        value_style.offset[2] = row_offset_y
        value_style.size[1] = sum_node_w
        value_style.text_color[1] = math_floor(SUM_VALUE_ALPHA * opacity)
    end

    self:_refresh_localization()

    self._force_refresh = true
    self:_clear_render_cache()

    widget.dirty = true
    summary_widget.dirty = true
end

--- Caches the fixed texts and writes the titles and summary labels, for the current archetype.
HudElementOverflowMeter._refresh_localization = function (self)
    local loc = self._loc

    loc.state_inactive = mod:localize("state_inactive")
    loc.ctx_inactive = mod:localize("ctx_inactive")
    loc.state_ready = mod:localize("state_ready")
    loc.state_sharing = mod:localize("state_sharing")
    loc.state_useful = mod:localize("state_useful")
    loc.ctx_no_demand = mod:localize("ctx_no_demand")
    loc.unit_toughness_per_second = mod:localize("unit_toughness_per_second")

    loc.tier = loc.tier or {}
    loc.tier[Estimator.TIER_LOW] = mod:localize(TIER_LOC_KEYS[Estimator.TIER_LOW])
    loc.tier[Estimator.TIER_MID] = mod:localize(TIER_LOC_KEYS[Estimator.TIER_MID])
    loc.tier[Estimator.TIER_HIGH] = mod:localize(TIER_LOC_KEYS[Estimator.TIER_HIGH])

    local archetype_config = self._archetype and ARCHETYPES[self._archetype]
    local title_key = archetype_config and archetype_config.title_key or "hud_title"

    self._widgets_by_name.meter.content.title = mod:localize(title_key)

    local summary_content = self._widgets_by_name.summary.content

    summary_content.sum_title = mod:localize("summary_title")

    for i = 1, SUM_ROW_COUNT do
        summary_content[SUM_LABEL_IDS[i]] = mod:localize(SUM_LABEL_KEYS[i])
    end
end

return HudElementOverflowMeter
