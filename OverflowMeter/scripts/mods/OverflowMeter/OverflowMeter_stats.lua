local Stats = {}

local share_fraction = 0

Stats.generated = 0
Stats.replenished = 0
Stats.overflowed = 0
Stats.shared = 0
Stats.shared_total = 0
Stats.archetype = nil

Stats.shareable = 0

Stats.version = 0

Stats.reset = function ()
    Stats.generated = 0
    Stats.replenished = 0
    Stats.overflowed = 0
    Stats.shared = 0
    Stats.shared_total = 0
    Stats.shareable = 0
    Stats.version = Stats.version + 1
end

Stats.set_context = function (archetype, talent_share_fraction)
    share_fraction = talent_share_fraction or 0

    if archetype ~= Stats.archetype then
        Stats.archetype = archetype

        Stats.reset()
    end
end

Stats.add_event = function (recovered, overflowed, shareable, allies)
    local changed = false

    if recovered > 0 then
        Stats.replenished = Stats.replenished + recovered
        Stats.generated = Stats.generated + recovered

        changed = true
    end

    if overflowed > 0 then
        Stats.overflowed = Stats.overflowed + overflowed
        Stats.generated = Stats.generated + overflowed

        changed = true
    end

    if shareable > 0 then
        Stats.shareable = Stats.shareable + shareable

        changed = true

        if allies > 0 then
            local shared = share_fraction * shareable

            Stats.shared = Stats.shared + shared
            Stats.shared_total = Stats.shared_total + shared * allies
        end
    end

    if changed then
        Stats.version = Stats.version + 1
    end
end

Stats.efficiency = function ()
    local shareable = Stats.shareable

    if shareable <= 0 or share_fraction <= 0 then
        return 0
    end

    return Stats.shared / (share_fraction * shareable)
end

return Stats
