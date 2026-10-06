
local math_cos = math.cos
local math_sin = math.sin
local math_pi = math.pi

local Geometry = {}

local DEG_TO_RAD = math_pi / 180

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
