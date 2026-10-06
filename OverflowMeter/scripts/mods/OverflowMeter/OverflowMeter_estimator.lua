local math_max = math.max
local math_min = math.min

local RING_CAPACITY = 12
local MIN_SCALE = 2
local PEAK_DECAY_PER_SAMPLE = 0.97
local BURST_DECAY_PER_SAMPLE = 0.85
local TIER_LOW_THRESHOLD = 1 / 3
local TIER_MID_THRESHOLD = 2 / 3

local Estimator = {}

Estimator.__index = Estimator
Estimator.RING_CAPACITY = RING_CAPACITY
Estimator.MIN_SCALE = MIN_SCALE
Estimator.STATE_INACTIVE = "inactive"
Estimator.STATE_READY = "ready"
Estimator.STATE_SHARING_USEFUL = "sharing_useful"
Estimator.STATE_SHARING_NO_DEMAND = "sharing_no_demand"
Estimator.TIER_NONE = 0
Estimator.TIER_LOW = 1
Estimator.TIER_MID = 2
Estimator.TIER_HIGH = 3

Estimator.new = function ()
    local self = setmetatable({}, Estimator)

    self._ring = {}
    self._window_size = RING_CAPACITY
    self._continuous_when_full = true
    self._allow_inactive = true

    self:reset()

    return self
end

Estimator.set_mode = function (self, continuous_when_full, allow_inactive)
    continuous_when_full = continuous_when_full ~= false
    allow_inactive = allow_inactive ~= false

    if continuous_when_full ~= self._continuous_when_full or allow_inactive ~= self._allow_inactive then
        self._continuous_when_full = continuous_when_full
        self._allow_inactive = allow_inactive

        self:reset()
    end
end

Estimator.reset = function (self)
    local ring = self._ring

    for i = 1, RING_CAPACITY do
        ring[i] = 0
    end

    self._ring_index = 0
    self._ring_count = 0
    self._ring_sum = 0
    self._peak_rate = 0
    self._burst_rate = 0
    self.state = self._allow_inactive and Estimator.STATE_INACTIVE or Estimator.STATE_READY
    self.display_rate = 0
    self.allies = 0
    self.allies_missing = 0
    self.scale_max = MIN_SCALE
    self.fill_fraction = 0
    self.peak_fraction = 0
    self.tier = Estimator.TIER_NONE
end

Estimator.set_window = function (self, num_samples)
    num_samples = math_max(1, math_min(num_samples, RING_CAPACITY))

    if num_samples ~= self._window_size then
        self._window_size = num_samples

        self:reset()
    end
end

Estimator.register_burst = function (self, offered_per_second)
    if offered_per_second and offered_per_second > self._burst_rate then
        self._burst_rate = offered_per_second
    end
end

Estimator.sample = function (self, is_full, has_continuous_source, continuous_offered_per_second, pulse_offered_per_second, nominal_ceiling, allies, allies_missing)
    local push_value = pulse_offered_per_second or 0
    local count_continuous

    if self._continuous_when_full then
        count_continuous = is_full and has_continuous_source
    else
        count_continuous = not is_full and has_continuous_source
    end

    if count_continuous then
        push_value = push_value + continuous_offered_per_second
    end

    local window_size = self._window_size
    local index = self._ring_index % window_size + 1
    local ring = self._ring
    local ring_sum = self._ring_sum - ring[index] + push_value

    if ring_sum < 1e-09 then
        ring_sum = 0
    end

    ring[index] = push_value
    self._ring_sum = ring_sum
    self._ring_index = index

    local ring_count = self._ring_count

    if ring_count < window_size then
        ring_count = ring_count + 1
        self._ring_count = ring_count
    end

    local display_rate = ring_count > 0 and ring_sum / ring_count or 0

    self.display_rate = display_rate

    local peak_rate = math_max(display_rate, self._peak_rate * PEAK_DECAY_PER_SAMPLE)

    self._peak_rate = peak_rate

    local burst_rate = self._burst_rate * BURST_DECAY_PER_SAMPLE

    if burst_rate < 1e-06 then
        burst_rate = 0
    end

    self._burst_rate = burst_rate

    local scale_max = math_max(MIN_SCALE, nominal_ceiling or 0, peak_rate)

    self.scale_max = scale_max
    self.fill_fraction = math_min(display_rate / scale_max, 1)

    local marker_rate = math_max(peak_rate, burst_rate)

    self.peak_fraction = math_min(marker_rate / scale_max, 1)

    local ceiling = nominal_ceiling or 0
    local tier = Estimator.TIER_NONE

    if ceiling > 0 and display_rate > 0 then
        local ceiling_fraction = display_rate / ceiling

        if ceiling_fraction < TIER_LOW_THRESHOLD then
            tier = Estimator.TIER_LOW
        elseif ceiling_fraction < TIER_MID_THRESHOLD then
            tier = Estimator.TIER_MID
        else
            tier = Estimator.TIER_HIGH
        end
    end

    self.tier = tier

    local has_recent_activity = has_continuous_source or ring_sum > 0
    local state

    if self._allow_inactive and not is_full then
        state = Estimator.STATE_INACTIVE
    elseif not has_recent_activity or allies <= 0 then
        state = Estimator.STATE_READY
    elseif allies_missing > 0 then
        state = Estimator.STATE_SHARING_USEFUL
    else
        state = Estimator.STATE_SHARING_NO_DEMAND
    end

    self.state = state
    self.allies = allies
    self.allies_missing = allies_missing

    return state
end

return Estimator
