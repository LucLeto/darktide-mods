--- Pure layout maths for the meter's segmented arc gauge.
-- Places the gauge segments along an arc and maps the estimator's fill and peak fractions to
-- segment counts. It has no game dependencies, so offline harnesses can load it directly.
--
-- Explicit module loaded through `mod:io_dofile` by `ui/OverflowMeter_hud_element.lua`; the
-- chunk returns `Geometry`.
-- module: OverflowMeter_gauge_geometry
-- alias: Geometry
-- author: LucLeto
local math_cos = math.cos
local math_sin = math.sin
local math_pi = math.pi

local Geometry = {}

local DEG_TO_RAD = math_pi / 180

--- Returns the centre point of every segment, evenly spaced along an arc.
-- Angles are in degrees, measured clockwise from the positive x axis in screen space.
-- tab: config `count`, `radius`, `center_x`, `center_y`, `start_deg` and `sweep_deg`
-- treturn: tab array of `{ x, y, t }`, where `t` runs from 0 at the first segment to 1 at the last
Geometry.build_segments = function(config)
    local count = config.count
    local radius = config.radius
    local center_x = config.center_x
    local center_y = config.center_y
    local start_deg = config.start_deg
    local sweep_deg = config.sweep_deg
    local segments = {}
    local denom = count > 1 and count - 1 or 1

    for i = 1, count do
        local t = (i - 1) / denom
        local angle_rad = (start_deg + t * sweep_deg) * DEG_TO_RAD

        segments[i] = {
            x = center_x + radius * math_cos(angle_rad),
            y = center_y + radius * math_sin(angle_rad),
            t = t,
        }
    end

    return segments
end

--- Returns how many segments to light for a fill fraction.
-- Any positive fill lights at least one segment, so a small rate is still visible.
-- number: fill_fraction fill from 0 to 1
-- int: count number of segments
-- treturn: int lit segments, 0 to `count`
Geometry.lit_count = function(fill_fraction, count)
    if fill_fraction <= 0 then
        return 0
    end

    local lit = math.floor(fill_fraction * count + 0.5)

    if lit < 1 then
        lit = 1
    elseif lit > count then
        lit = count
    end

    return lit
end

--- Returns the segment that marks a fraction, used for the peak marker.
-- number: fraction position from 0 to 1
-- int: count number of segments
-- treturn: int segment index, or 0 for no marker
Geometry.marker_index = function(fraction, count)
    if fraction <= 0 then
        return 0
    end

    local index = math.floor(fraction * count + 0.5)

    if index < 1 then
        index = 1
    elseif index > count then
        index = count
    end

    return index
end

return Geometry
