--- The HUD element that draws Perfect Keystones' rings around the crosshair.
-- Two concentric rings of square segments centred on the screen, like the game's crosshair and
-- Perfect Thrust's ring: the inner ring shows the main keystone, the thin outer ring Until Death or
-- Lone Wolf. Each frame it asks the tracker for the presentation state of each ring and draws it;
-- it contains no keystone mechanics.
--
-- Segments light clockwise from the top, so a full ring that empties loses its segments
-- counter-clockwise back toward 12 o'clock. Lit segments use the active colour, or the cooldown
-- colour for a cooldown or recharge; the share of the next expiring stack, or the whole filled area
-- for stacks with a shared timer, blends toward the expiring colour as its timer runs down, and a
-- timed active effect turns the expiring colour for the last part of its duration set by the
-- near-expiry threshold. Unlit segments use the unfilled colour. Each ring pulses briefly when the
-- tracker reports a transition, and can show its stack count and remaining seconds next to the
-- rings. Both rings keep their geometry when the other one hides, and follow the crosshair together.
--
-- Colours, geometry and labels are only rewritten when the lit count, the highlight, the colour
-- step, the pulse, the shown value or the settings change; nothing is allocated per frame except a
-- label string when its shown value changes.
--
-- Loaded by DMF from the `register_hud_element` call in `PerfectKeystones.lua` and returned as the
-- `HudElementPerfectKeystones` class, with the crosshair's visibility groups and without the HUD
-- scale. Reads its settings from `mod._settings`, their defaults from `mod._ring_settings` and the
-- ring states from `mod._tracker`.
-- classmod: HudElementPerfectKeystones
-- author: LucLeto
local mod = get_mod("PerfectKeystones")
local Crosshair = require("scripts/ui/utilities/crosshair")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local Tracker = mod._tracker
local RingSettings = mod._ring_settings

local math_clamp = math.clamp
local math_cos = math.cos
local math_floor = math.floor
local math_pi = math.pi
local math_sin = math.sin
local string_format = string.format
local table_clone = table.clone
local type = type

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Presentation state values, as `trackers/PerfectKeystones_kinds.lua` defines them.
local BASE_COOLDOWN = "cooldown"
local HIGHLIGHT_NONE = "none"
local HIGHLIGHT_SHARED = "shared"

--- Number of segments in each ring, the first one at the top and the rest clockwise.
-- Fixed so the widget passes can be built once; the angle of segment `i` is
-- `RING_START_DEG + (i - 1) * 360 / SEGMENT_COUNT` degrees, in screen space with y pointing down.
local SEGMENT_COUNT = 48
local RING_START_DEG = -90
local DEG_TO_RAD = math_pi / 180

--- Pulse length in seconds, and the extra segment size at its peak, as Perfect Thrust's READY pulse.
-- The segment size follows a half sine from 1 to `1 + PULSE_EXTRA_SCALE` and back.
local PULSE_DURATION = 0.25
local PULSE_EXTRA_SCALE = 0.6

--- Frame time passed to `Crosshair.position` on the first frame the rings follow the crosshair.
-- The crosshair eases toward its aim point by `min(35 * dt, 1)` per frame, so this lands on it at
-- once instead of sliding in from the screen centre.
local CROSSHAIR_SNAP_DT = 1

--- Steps of the blend from the active to the expiring colour; the colours are rewritten once per step.
local COLOR_STEPS = 32

--- Label box size, font size and distance from the outer ring's outer edge, at 1080p.
local LABEL_WIDTH = 80
local LABEL_HEIGHT = 20
local LABEL_FONT_SIZE = 16
local LABEL_MARGIN = 6

--- Remaining seconds below which a label shows tenths.
local LABEL_TENTHS_BELOW = 10

--- Default colours `{ a, r, g, b }`, the colour settings' defaults; used when a colour setting is
-- invalid, never written.
local ACTIVE_COLOR = RingSettings.default_value("active_color")
local UNFILLED_COLOR = RingSettings.default_value("unfilled_color")
local EXPIRING_COLOR = RingSettings.default_value("expiring_color")
local COOLDOWN_COLOR = RingSettings.default_value("cooldown_color")

--- Widget of each ring, inner first.
local SLOT_WIDGET_NAMES = {
    "inner_ring",
    "outer_ring"
}

local SLOT_INNER = 1
local SLOT_OUTER = 2

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

--- Copies a colour setting into a colour array.
-- DMF stores a colour setting as `{ a, r, g, b }`, the layout of a widget style colour. Each
-- channel is clamped to 0-255 and rounded. Anything but a table with four number channels copies
-- the fallback colour instead. Only `color` is written.
-- tab: color `{ a, r, g, b }` array to fill
-- ?tab: argb colour setting value
-- tab: fallback `{ a, r, g, b }` colour copied when the setting is invalid
local function _copy_setting_color(color, argb, fallback)
    if type(argb) == "table" then
        local a, r, g, b = argb[1], argb[2], argb[3], argb[4]

        if type(a) == "number" and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            color[1] = math_floor(math_clamp(a, 0, 255) + 0.5)
            color[2] = math_floor(math_clamp(r, 0, 255) + 0.5)
            color[3] = math_floor(math_clamp(g, 0, 255) + 0.5)
            color[4] = math_floor(math_clamp(b, 0, 255) + 0.5)

            return
        end
    end

    color[1] = fallback[1]
    color[2] = fallback[2]
    color[3] = fallback[3]
    color[4] = fallback[4]
end

--- Copies a colour array into another.
-- tab: target `{ a, r, g, b }` array to fill
-- tab: source `{ a, r, g, b }` colour
local function _set_color(target, source)
    target[1] = source[1]
    target[2] = source[2]
    target[3] = source[3]
    target[4] = source[4]
end

--- Returns a numeric setting, or its default when the setting is not a number.
-- tab: settings `mod._settings`
-- string: id setting id
-- treturn: number
local function _number_setting(settings, id)
    local value = settings[id]

    if type(value) ~= "number" then
        return RingSettings.default_value(id)
    end

    return value
end

--- Builds the widget definition of one ring: a `rect` pass per segment and a text pass for its
-- label. Segment offsets are relative to the ring node, so the ring centre is the node position.
-- int: slot `SLOT_INNER` or `SLOT_OUTER`
-- treturn: tab widget definition
local function _ring_definition(slot)
    local passes = {}

    for i = 1, SEGMENT_COUNT do
        passes[i] = {
            pass_type = "rect",
            style_id = SEGMENT_STYLE_IDS[i],
            style = {
                offset = { 0, 0, 1 },
                size = { 3, 3 },
                color = { UNFILLED_COLOR[1], UNFILLED_COLOR[2], UNFILLED_COLOR[3], UNFILLED_COLOR[4] }
            }
        }
    end

    local label_style = table_clone(UIFontSettings.body_small)

    label_style.font_size = LABEL_FONT_SIZE
    label_style.drop_shadow = true
    label_style.horizontal_alignment = "left"
    label_style.vertical_alignment = "top"
    label_style.text_horizontal_alignment = "left"
    -- The inner ring's label sits just below the horizontal axis, the outer ring's just above it.
    label_style.text_vertical_alignment = slot == SLOT_INNER and "top" or "bottom"
    label_style.offset = { 0, 0, 2 }
    label_style.size = { LABEL_WIDTH, LABEL_HEIGHT }
    label_style.text_color = { ACTIVE_COLOR[1], ACTIVE_COLOR[2], ACTIVE_COLOR[3], ACTIVE_COLOR[4] }

    passes[SEGMENT_COUNT + 1] = {
        pass_type = "text",
        value_id = "label",
        style_id = "label",
        value = "",
        style = label_style
    }

    return UIWidget.create_definition(passes, "perfect_keystones_ring")
end

--- Builds the scenegraph and widget definitions.
-- One 0x0 node centred on the screen, like the crosshair's pivot, carries both rings; the offset
-- settings move it. A second 0x0 centred node is never moved: the pivot the crosshair position is
-- measured from, so it leaves out the offset settings.
-- treturn: tab definitions for `HudElementBase.init`
local function _build_definitions()
    return {
        scenegraph_definition = {
            screen = UIWorkspaceSettings.screen,
            perfect_keystones_ring = {
                parent = "screen",
                horizontal_alignment = "center",
                vertical_alignment = "center",
                size = { 0, 0 },
                position = { 0, 0, 10 }
            },
            perfect_keystones_pivot = {
                parent = "screen",
                horizontal_alignment = "center",
                vertical_alignment = "center",
                size = { 0, 0 },
                position = { 0, 0, 0 }
            }
        },
        widget_definitions = {
            [SLOT_WIDGET_NAMES[SLOT_INNER]] = _ring_definition(SLOT_INNER),
            [SLOT_WIDGET_NAMES[SLOT_OUTER]] = _ring_definition(SLOT_OUTER)
        }
    }
end

--- Scenegraph and widget definitions shared by every instance of the element.
local Definitions = _build_definitions()

--- The HUD element class, derived from the game's `HudElementBase`.
local HudElementPerfectKeystones = class("HudElementPerfectKeystones", "HudElementBase")

-- ----------------------------------------------------------------------------
-- HudElementPerfectKeystones
-- ----------------------------------------------------------------------------

--- Initialises the element, both rings hidden, and applies the current settings.
-- tab: parent HUD that owns the element
-- int: draw_layer element draw layer
-- number: start_scale initial UI scale
HudElementPerfectKeystones.init = function (self, parent, draw_layer, start_scale)
    HudElementPerfectKeystones.super.init(self, parent, draw_layer, start_scale, Definitions)

    self._active_color = { 0, 0, 0, 0 }
    self._unfilled_color = { 0, 0, 0, 0 }
    self._expiring_color = { 0, 0, 0, 0 }
    self._cooldown_color = { 0, 0, 0, 0 }
    self._near_threshold = 0
    self._following_crosshair = false
    self._crosshair_x = 0
    self._crosshair_y = 0
    self._crosshair_pivot = { 0, 0 }

    --- Per-ring display state: geometry, pulse, the blended highlight colour and the render and
    -- label caches.
    self._slots = {}

    for slot = 1, #SLOT_WIDGET_NAMES do
        local widget = self._widgets_by_name[SLOT_WIDGET_NAMES[slot]]

        widget.content.visible = false

        self._slots[slot] = {
            widget = widget,
            radius = 0,
            thickness = 0,
            shown = false,
            pulse_remaining = 0,
            blend_color = { 0, 0, 0, 0 },
            last_lit = nil,
            last_highlight_start = nil,
            last_base = nil,
            last_step = nil,
            last_near = nil,
            last_label_stacks = nil,
            last_label_key = nil,
            last_label_base = nil
        }
    end

    self:_apply_display_settings(mod._settings)
end

--- Forgets a ring's last drawn colours and label, so the next refresh rewrites them.
-- tab: slot per-ring display state
local function _clear_render_cache(slot)
    slot.last_lit = nil
    slot.last_highlight_start = nil
    slot.last_base = nil
    slot.last_step = nil
    slot.last_near = nil
    slot.last_label_stacks = nil
    slot.last_label_key = nil
    slot.last_label_base = nil
end

--- Updates both rings from the tracker once per frame.
-- Applies the settings after a change, asks the tracker for each ring's presentation state, hides
-- a ring without one, starts a ring's pulse on a frame its state reports a transition and the
-- `pulse` setting is on, redraws what changed and advances the pulses.
-- number: dt frame delta time
-- number: t time
-- tab: ui_renderer active UI renderer
-- ?tab: render_settings render settings
-- param: input_service input service
HudElementPerfectKeystones.update = function (self, dt, t, ui_renderer, render_settings, input_service)
    HudElementPerfectKeystones.super.update(self, dt, t, ui_renderer, render_settings, input_service)

    local settings = mod._settings

    if mod._settings_version ~= self._applied_settings_version then
        self:_apply_display_settings(settings)
    end

    local parent = self._parent
    local inner_state, outer_state = Tracker.refresh(parent:player_extensions(), parent:player())
    local slots = self._slots

    self:_update_slot(slots[SLOT_INNER], inner_state, settings, dt)
    self:_update_slot(slots[SLOT_OUTER], outer_state, settings, dt)
end

--- Updates one ring from its presentation state.
-- tab: slot per-ring display state
-- ?tab: ring_state presentation state, nil when the ring is hidden
-- tab: settings `mod._settings`
-- number: dt frame delta time
HudElementPerfectKeystones._update_slot = function (self, slot, ring_state, settings, dt)
    if not ring_state then
        if slot.shown then
            self:_hide_slot(slot)
        end

        return
    end

    local widget = slot.widget

    if not slot.shown then
        slot.shown = true
        widget.content.visible = true
        widget.dirty = true
    end

    if ring_state.pulse and settings.pulse then
        slot.pulse_remaining = PULSE_DURATION
    end

    self:_refresh_ring(slot, ring_state)
    self:_refresh_label(slot, ring_state, settings)

    if slot.pulse_remaining > 0 then
        local remaining = slot.pulse_remaining - dt

        if remaining > 0 then
            slot.pulse_remaining = remaining

            self:_apply_geometry(slot, 1 + PULSE_EXTRA_SCALE * math_sin(math_pi * (1 - remaining / PULSE_DURATION)))
        else
            slot.pulse_remaining = 0

            self:_apply_geometry(slot, 1)
        end
    end
end

--- Moves the shown rings with the crosshair, then draws them.
-- While a ring is shown and the `follow_crosshair` setting is on, both ring widgets' offset is the
-- game's crosshair position, from `Crosshair.position` as the crosshair element uses it, on top of
-- the scenegraph position the offset settings set. On the first such frame it starts at the
-- crosshair's aim point. Otherwise the offset is back at zero. Done here rather than in `update`,
-- like the crosshair, so both read the same frame's camera.
-- number: dt frame delta time
-- number: t time
-- param: input_service input service
-- tab: ui_renderer active UI renderer
-- ?tab: render_settings render settings
HudElementPerfectKeystones._draw_widgets = function (self, dt, t, input_service, ui_renderer, render_settings)
    local slots = self._slots
    local inner_widget = slots[SLOT_INNER].widget
    local outer_widget = slots[SLOT_OUTER].widget

    if (slots[SLOT_INNER].shown or slots[SLOT_OUTER].shown) and mod._settings.follow_crosshair then
        -- The unscaled world position is the node's own table; scaling it here allocates nothing.
        local world_position = self:scenegraph_world_position("perfect_keystones_pivot")
        local pivot = self._crosshair_pivot
        local scale = ui_renderer.scale

        pivot[1] = world_position[1] * scale
        pivot[2] = world_position[2] * scale

        local x, y = Crosshair.position(self._following_crosshair and dt or CROSSHAIR_SNAP_DT, t, self._parent, ui_renderer, self._crosshair_x, self._crosshair_y, pivot)

        self._following_crosshair = true
        self._crosshair_x = x
        self._crosshair_y = y

        self:_set_widget_offsets(inner_widget, outer_widget, x, y)
    elseif self._following_crosshair then
        self._following_crosshair = false
        self._crosshair_x = 0
        self._crosshair_y = 0

        self:_set_widget_offsets(inner_widget, outer_widget, 0, 0)
    end

    HudElementPerfectKeystones.super._draw_widgets(self, dt, t, input_service, ui_renderer, render_settings)
end

--- Sets both ring widgets' offset.
-- tab: inner_widget inner ring widget
-- tab: outer_widget outer ring widget
-- number: x horizontal offset
-- number: y vertical offset
HudElementPerfectKeystones._set_widget_offsets = function (self, inner_widget, outer_widget, x, y)
    local inner_offset = inner_widget.offset
    local outer_offset = outer_widget.offset

    inner_offset[1] = x
    inner_offset[2] = y
    outer_offset[1] = x
    outer_offset[2] = y
    inner_widget.dirty = true
    outer_widget.dirty = true
end

--- Colours a ring's segments for its presentation state, when anything drawn changed since the
-- last call.
-- Lit segments before the highlight use the base colour (the expiring colour in a timed active
-- effect's near-expiry part); highlighted lit segments use the active colour blended toward the
-- expiring colour by the state's elapsed timer fraction, in `COLOR_STEPS` steps; unlit segments use
-- the unfilled colour.
-- tab: slot per-ring display state
-- tab: ring_state presentation state
HudElementPerfectKeystones._refresh_ring = function (self, slot, ring_state)
    local lit = _lit_count(ring_state.fill)
    local base = ring_state.base
    local highlight_start = lit + 1
    local step = 0
    local near = false
    local expiry = ring_state.expiry

    if ring_state.highlight ~= HIGHLIGHT_NONE and expiry and lit > 0 then
        step = math_floor(math_clamp(expiry, 0, 1) * COLOR_STEPS + 0.5)

        if ring_state.highlight == HIGHLIGHT_SHARED then
            highlight_start = 1
        else
            highlight_start = _lit_count(ring_state.highlight_from) + 1

            if highlight_start > lit then
                highlight_start = lit
            end
        end
    elseif ring_state.countdown and ring_state.fill < self._near_threshold then
        near = true
    end

    if lit == slot.last_lit and highlight_start == slot.last_highlight_start and base == slot.last_base and step == slot.last_step and near == slot.last_near then
        return
    end

    slot.last_lit = lit
    slot.last_highlight_start = highlight_start
    slot.last_base = base
    slot.last_step = step
    slot.last_near = near

    local base_color

    if near then
        base_color = self._expiring_color
    elseif base == BASE_COOLDOWN then
        base_color = self._cooldown_color
    else
        base_color = self._active_color
    end

    local blend_color = slot.blend_color

    if highlight_start <= lit then
        local active_color = self._active_color
        local expiring_color = self._expiring_color
        local blend = step / COLOR_STEPS

        for channel = 1, 4 do
            local from = active_color[channel]

            blend_color[channel] = math_floor(from + (expiring_color[channel] - from) * blend + 0.5)
        end
    end

    local unfilled_color = self._unfilled_color
    local widget = slot.widget
    local style = widget.style

    for i = 1, SEGMENT_COUNT do
        local source

        if i > lit then
            source = unfilled_color
        elseif i >= highlight_start then
            source = blend_color
        else
            source = base_color
        end

        _set_color(style[SEGMENT_STYLE_IDS[i]].color, source)
    end

    widget.dirty = true
end

--- Writes a ring's label, when its shown value changed since the last call.
-- With `show_stack_label` on, it shows the held stacks of a state that has them; with
-- `show_time_label` on, the seconds of the timer shown or behind the highlight, with tenths below
-- `LABEL_TENTHS_BELOW` seconds. Timed phases carry no stack count, so a resource the ring hides is
-- never shown either. The label takes the ring's base colour.
-- tab: slot per-ring display state
-- tab: ring_state presentation state
-- tab: settings `mod._settings`
HudElementPerfectKeystones._refresh_label = function (self, slot, ring_state, settings)
    local stacks = settings.show_stack_label and ring_state.stacks or nil
    local remaining = settings.show_time_label and ring_state.remaining or nil
    local key

    if remaining then
        if remaining < LABEL_TENTHS_BELOW then
            key = math_floor(remaining * 10)
        else
            -- Whole seconds, kept apart from the tenths keys.
            key = -1 - math_floor(remaining)
        end
    end

    local base = ring_state.base

    if stacks == slot.last_label_stacks and key == slot.last_label_key and base == slot.last_label_base then
        return
    end

    slot.last_label_stacks = stacks
    slot.last_label_key = key
    slot.last_label_base = base

    local seconds_text

    if key then
        seconds_text = key >= 0 and string_format("%.1f", key / 10) or string_format("%d", -1 - key)
    end

    local text

    if stacks and seconds_text then
        text = string_format("%d  %s", stacks, seconds_text)
    elseif stacks then
        text = string_format("%d", stacks)
    else
        text = seconds_text or ""
    end

    local widget = slot.widget

    widget.content.label = text

    _set_color(widget.style.label.text_color, base == BASE_COOLDOWN and self._cooldown_color or self._active_color)

    widget.dirty = true
end

--- Positions and sizes every segment of a ring on its radius.
-- Each segment is a square of the ring's thickness, centred on the ring's radius.
-- tab: slot per-ring display state
-- number: thickness_scale multiplier of the segment size, above 1 during a pulse
HudElementPerfectKeystones._apply_geometry = function (self, slot, thickness_scale)
    local radius = slot.radius
    local segment_size = slot.thickness * thickness_scale
    local half_size = segment_size * 0.5
    local widget = slot.widget
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

--- Hides a ring, ends its pulse and forgets what it drew.
-- tab: slot per-ring display state
HudElementPerfectKeystones._hide_slot = function (self, slot)
    slot.shown = false

    if slot.pulse_remaining > 0 then
        slot.pulse_remaining = 0

        self:_apply_geometry(slot, 1)
    end

    _clear_render_cache(slot)

    local widget = slot.widget

    widget.content.visible = false
    widget.content.label = ""
    widget.dirty = true
end

--- Applies the position, geometry, colour and threshold settings.
-- The inner ring takes the ring radius and thickness; the outer ring lies the outer ring gap
-- outside it, measured between the segments' edges, with its own thickness. Both labels sit the
-- same distance right of the outer ring's outer edge, whether or not that ring is shown. Records
-- the settings version, so `update` only calls it again after a change.
-- tab: settings `mod._settings`
HudElementPerfectKeystones._apply_display_settings = function (self, settings)
    self._applied_settings_version = mod._settings_version

    self:set_scenegraph_position("perfect_keystones_ring", _number_setting(settings, "offset_x"), _number_setting(settings, "offset_y"))

    local inner_radius = _number_setting(settings, "ring_radius")
    local inner_thickness = _number_setting(settings, "ring_thickness")
    local outer_thickness = _number_setting(settings, "outer_ring_thickness")
    local outer_radius = inner_radius + inner_thickness * 0.5 + _number_setting(settings, "outer_ring_gap") + outer_thickness * 0.5
    local label_x = outer_radius + outer_thickness * 0.5 + LABEL_MARGIN
    local slots = self._slots

    slots[SLOT_INNER].radius = inner_radius
    slots[SLOT_INNER].thickness = inner_thickness
    slots[SLOT_OUTER].radius = outer_radius
    slots[SLOT_OUTER].thickness = outer_thickness

    _copy_setting_color(self._active_color, settings.active_color, ACTIVE_COLOR)
    _copy_setting_color(self._unfilled_color, settings.unfilled_color, UNFILLED_COLOR)
    _copy_setting_color(self._expiring_color, settings.expiring_color, EXPIRING_COLOR)
    _copy_setting_color(self._cooldown_color, settings.cooldown_color, COOLDOWN_COLOR)

    self._near_threshold = math_clamp(_number_setting(settings, "near_expiry_threshold"), 0, 100) / 100

    for slot_index = 1, #slots do
        local slot = slots[slot_index]
        local label_offset = slot.widget.style.label.offset

        label_offset[1] = label_x
        label_offset[2] = slot_index == SLOT_INNER and 1 or -1 - LABEL_HEIGHT
        slot.pulse_remaining = 0

        self:_apply_geometry(slot, 1)
        _clear_render_cache(slot)
    end
end

return HudElementPerfectKeystones
