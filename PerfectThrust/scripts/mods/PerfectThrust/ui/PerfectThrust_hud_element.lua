--- The HUD element that draws Perfect Thrust's charge ring around the crosshair.
-- A ring of square segments centred on the screen, like the game's crosshair. While a tracked
-- windup runs, it asks the tracker each frame what to show: segments light up amber clockwise
-- from the top as the charge-dependent effects build, the whole ring turns green at READY with
-- an optional short pulse, and it hides as soon as the tracker stops. Colours and geometry are
-- only rewritten when the lit count, the READY state or the settings change.
--
-- Loaded by DMF from the `register_hud_element` call in `PerfectThrust.lua` and returned as the
-- `HudElementPerfectThrust` class, with the crosshair's visibility groups and without the HUD
-- scale. Reads its settings from `mod._settings` and its state from `mod._tracker`.
-- classmod: HudElementPerfectThrust
-- author: LucLeto
local mod = get_mod("PerfectThrust")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local Tracker = mod._tracker

local math_cos = math.cos
local math_floor = math.floor
local math_pi = math.pi
local math_sin = math.sin

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- `display_mode` setting value that shows the ring only at READY.
local DISPLAY_MODE_READY_ONLY = "ready_only"

--- Number of segments in the ring, the first one at the top and the rest clockwise.
-- Fixed so the widget passes can be built once; the angle of segment `i` is
-- `RING_START_DEG + (i - 1) * 360 / SEGMENT_COUNT` degrees, in screen space with y pointing down.
local SEGMENT_COUNT = 48
local RING_START_DEG = -90
local DEG_TO_RAD = math_pi / 180

--- READY pulse length in seconds, and the extra segment size at its peak.
-- The segment size follows a half sine from 1 to `1 + PULSE_EXTRA_SCALE` and back.
local PULSE_DURATION = 0.25
local PULSE_EXTRA_SCALE = 0.6

--- Segment alpha of the unlit, charging and READY states, before the opacity setting is applied.
local SEG_DIM_ALPHA = 80
local SEG_LIT_ALPHA = 235
local SEG_READY_ALPHA = 255

--- Segment colours of the unlit, charging and READY states.
local SEG_DIM_RGB = { 70, 82, 86 }
local SEG_LIT_RGB = { 240, 190, 90 }
local SEG_READY_RGB = { 120, 225, 140 }

--- Style id and unit circle position of each segment, precomputed so the per-frame loops build no strings.
local SEGMENT_STYLE_IDS = {}
local SEGMENT_COS = {}
local SEGMENT_SIN = {}

for i = 1, SEGMENT_COUNT do
    local angle_rad = (RING_START_DEG + (i - 1) * 360 / SEGMENT_COUNT) * DEG_TO_RAD

    SEGMENT_STYLE_IDS[i] = "seg_" .. i
    SEGMENT_COS[i] = math_cos(angle_rad)
    SEGMENT_SIN[i] = math_sin(angle_rad)
end

-- ----------------------------------------------------------------------------
-- Helpers and definitions
-- ----------------------------------------------------------------------------

--- Returns how many segments a fill fraction lights.
-- Any fill above zero lights at least one segment.
-- number: fill_fraction fill from 0 to 1
-- treturn: int lit segments from 0 to `SEGMENT_COUNT`
local function _lit_count(fill_fraction)
    if fill_fraction <= 0 then
        return 0
    end

    local lit = math_floor(fill_fraction * SEGMENT_COUNT + 0.5)

    if lit < 1 then
        lit = 1
    elseif lit > SEGMENT_COUNT then
        lit = SEGMENT_COUNT
    end

    return lit
end

--- Builds the scenegraph and widget definitions.
-- One 0x0 node centred on the screen, like the crosshair's pivot, and one widget with a `rect`
-- pass per segment. Segment offsets are relative to the node, so the ring centre is the node
-- position and the offset settings move it.
-- treturn: tab definitions for `HudElementBase.init`
local function _build_definitions()
    local passes = {}

    for i = 1, SEGMENT_COUNT do
        passes[i] = {
            pass_type = "rect",
            style_id = SEGMENT_STYLE_IDS[i],
            style = {
                offset = { 0, 0, 1 },
                size = { 3, 3 },
                color = { SEG_DIM_ALPHA, SEG_DIM_RGB[1], SEG_DIM_RGB[2], SEG_DIM_RGB[3] }
            }
        }
    end

    return {
        scenegraph_definition = {
            screen = UIWorkspaceSettings.screen,
            perfect_thrust_ring = {
                parent = "screen",
                horizontal_alignment = "center",
                vertical_alignment = "center",
                size = { 0, 0 },
                position = { 0, 0, 10 }
            }
        },
        widget_definitions = {
            ring = UIWidget.create_definition(passes, "perfect_thrust_ring")
        }
    }
end

--- Scenegraph and widget definitions shared by every instance of the element.
local Definitions = _build_definitions()

--- The HUD element class, derived from the game's `HudElementBase`.
local HudElementPerfectThrust = class("HudElementPerfectThrust", "HudElementBase")

-- ----------------------------------------------------------------------------
-- HudElementPerfectThrust
-- ----------------------------------------------------------------------------

--- Initialises the element, hidden, and applies the current settings.
-- tab: parent HUD that owns the element
-- int: draw_layer element draw layer
-- number: start_scale initial UI scale
HudElementPerfectThrust.init = function (self, parent, draw_layer, start_scale)
    HudElementPerfectThrust.super.init(self, parent, draw_layer, start_scale, Definitions)

    self._opacity = 1
    self._radius = 32
    self._thickness = 3
    self._shown = false
    self._ready_seen = false
    self._pulse_remaining = 0

    self:_clear_render_cache()

    self._widgets_by_name.ring.content.visible = false

    self:_apply_display_settings(mod._settings)
end

--- Forgets the last drawn lit count and READY state, so the next refresh rewrites every segment colour.
HudElementPerfectThrust._clear_render_cache = function (self)
    self._last_lit = nil
    self._last_ready = nil
end

--- Updates the ring from the tracker once per frame.
-- Applies changed settings first. While no windup is tracked this costs one check; otherwise it
-- refreshes the tracker, hides the ring when there is nothing to show (or, in `ready_only` mode,
-- until READY), starts the pulse the first time READY is reached and advances it.
-- number: dt frame delta time
-- number: t time
-- tab: ui_renderer active UI renderer
-- ?tab: render_settings render settings
-- param: input_service input service
HudElementPerfectThrust.update = function (self, dt, t, ui_renderer, render_settings, input_service)
    HudElementPerfectThrust.super.update(self, dt, t, ui_renderer, render_settings, input_service)

    local settings = mod._settings

    if mod._settings_version ~= self._applied_settings_version then
        self:_apply_display_settings(settings)
    end

    if not Tracker.is_charging_heavy_attack() then
        if self._shown then
            self:_hide()
        end

        return
    end

    local visible, fill, ready = Tracker.refresh(settings.timing_mode)

    if visible and not ready and settings.display_mode == DISPLAY_MODE_READY_ONLY then
        visible = false
    end

    if not visible then
        if self._shown then
            self:_hide()
        end

        return
    end

    local widget = self._widgets_by_name.ring

    if not self._shown then
        self._shown = true
        widget.content.visible = true
        widget.dirty = true
    end

    if ready and not self._ready_seen then
        self._ready_seen = true

        if settings.ready_pulse then
            self._pulse_remaining = PULSE_DURATION
        end
    end

    self:_refresh_ring(fill, ready)

    if self._pulse_remaining > 0 then
        local remaining = self._pulse_remaining - dt

        if remaining > 0 then
            self._pulse_remaining = remaining

            self:_apply_geometry(1 + PULSE_EXTRA_SCALE * math_sin(math_pi * (1 - remaining / PULSE_DURATION)))
        else
            self._pulse_remaining = 0

            self:_apply_geometry(1)
        end
    end
end

--- Colours the segments for a fill and READY state, when either changed since the last call.
-- At READY every segment is lit in the READY colour.
-- number: fill fill fraction from 0 to 1
-- bool: ready whether every tracked effect is at its maximum
HudElementPerfectThrust._refresh_ring = function (self, fill, ready)
    local lit = ready and SEGMENT_COUNT or _lit_count(fill)

    if lit == self._last_lit and ready == self._last_ready then
        return
    end

    self._last_lit = lit
    self._last_ready = ready

    local opacity = self._opacity
    local lit_alpha, lit_rgb

    if ready then
        lit_alpha = math_floor(SEG_READY_ALPHA * opacity)
        lit_rgb = SEG_READY_RGB
    else
        lit_alpha = math_floor(SEG_LIT_ALPHA * opacity)
        lit_rgb = SEG_LIT_RGB
    end

    local dim_alpha = math_floor(SEG_DIM_ALPHA * opacity)
    local widget = self._widgets_by_name.ring
    local style = widget.style

    for i = 1, SEGMENT_COUNT do
        local color = style[SEGMENT_STYLE_IDS[i]].color

        if i <= lit then
            color[1] = lit_alpha
            color[2] = lit_rgb[1]
            color[3] = lit_rgb[2]
            color[4] = lit_rgb[3]
        else
            color[1] = dim_alpha
            color[2] = SEG_DIM_RGB[1]
            color[3] = SEG_DIM_RGB[2]
            color[4] = SEG_DIM_RGB[3]
        end
    end

    widget.dirty = true
end

--- Positions and sizes every segment on the ring.
-- Each segment is a square of the thickness setting, centred on the ring's radius.
-- number: thickness_scale multiplier of the segment size, above 1 during the READY pulse
HudElementPerfectThrust._apply_geometry = function (self, thickness_scale)
    local radius = self._radius
    local segment_size = self._thickness * thickness_scale
    local half_size = segment_size * 0.5
    local widget = self._widgets_by_name.ring
    local style = widget.style

    for i = 1, SEGMENT_COUNT do
        local seg_style = style[SEGMENT_STYLE_IDS[i]]
        local size = seg_style.size
        local offset = seg_style.offset

        size[1] = segment_size
        size[2] = segment_size
        offset[1] = radius * SEGMENT_COS[i] - half_size
        offset[2] = radius * SEGMENT_SIN[i] - half_size
    end

    widget.dirty = true
end

--- Hides the ring, ends a running pulse and resets the per-windup display state.
HudElementPerfectThrust._hide = function (self)
    self._shown = false
    self._ready_seen = false

    if self._pulse_remaining > 0 then
        self._pulse_remaining = 0

        self:_apply_geometry(1)
    end

    self:_clear_render_cache()

    local widget = self._widgets_by_name.ring

    widget.content.visible = false
    widget.dirty = true
end

--- Applies the position, opacity, radius and thickness settings.
-- Records the settings version it applied, so `update` only calls it again after a change.
-- tab: settings `mod._settings`
HudElementPerfectThrust._apply_display_settings = function (self, settings)
    self._applied_settings_version = mod._settings_version

    self:set_scenegraph_position("perfect_thrust_ring", settings.offset_x or 0, settings.offset_y or 0)

    self._opacity = (settings.ring_opacity or 100) / 100
    self._radius = settings.ring_radius or 32
    self._thickness = settings.ring_thickness or 3
    self._pulse_remaining = 0

    self:_apply_geometry(1)
    self:_clear_render_cache()
end

return HudElementPerfectThrust
