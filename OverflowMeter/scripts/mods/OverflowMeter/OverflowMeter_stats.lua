--- Per-mission Toughness totals shown by the summary panel, the chat line and the scoreboards.
-- The HUD element feeds one event per sample: Toughness that filled the bar, Toughness lost
-- against the cap, the shareable part and the allies in Coherency. From these it keeps the
-- generated, replenished, overflowed and shared totals and the share efficiency. Values are in
-- Toughness points; `version` changes with every update so consumers can skip unchanged data.
--
-- Explicit module loaded first by `OverflowMeter.lua` and stored as `mod._stats`. The totals
-- are module-level, so they outlive the HUD element and are still readable on the end-of-round
-- screen. They reset when a mission starts, when the archetype changes and when the mod is
-- toggled.
-- module: OverflowMeter_stats
-- alias: Stats
-- author: LucLeto
local Stats = {}

--- Fraction of each shareable amount the active talent offers to one ally (0.25 or 0.2).
local share_fraction = 0

--- Mission totals.
-- `generated` = `replenished` + `overflowed`; `shared` is offered to one ally and `shared_total`
-- to all allies in Coherency together; `shareable` is what the talent could have shared, the
-- base of the efficiency. `archetype` is the archetype the totals were collected on.
Stats.generated = 0
Stats.replenished = 0
Stats.overflowed = 0
Stats.shared = 0
Stats.shared_total = 0
Stats.archetype = nil

Stats.shareable = 0

--- Change counter, bumped by every reset and by every event that changed a total.
Stats.version = 0

--- Clears every total and bumps the version.
Stats.reset = function ()
    Stats.generated = 0
    Stats.replenished = 0
    Stats.overflowed = 0
    Stats.shared = 0
    Stats.shared_total = 0
    Stats.shareable = 0
    Stats.version = Stats.version + 1
end

--- Sets the talent's share fraction and resets the totals when the archetype changes.
-- ?string: archetype archetype name, such as `cryptic` or `veteran`
-- ?number: talent_share_fraction fraction offered to each ally
Stats.set_context = function (archetype, talent_share_fraction)
    share_fraction = talent_share_fraction or 0

    if archetype ~= Stats.archetype then
        Stats.archetype = archetype

        Stats.reset()
    end
end

--- Adds one sample's amounts to the totals.
-- Shared Toughness is only counted while at least one ally is in Coherency; without one the
-- shareable amount still counts, which lowers the efficiency.
-- number: recovered Toughness that filled the bar
-- number: overflowed Toughness lost against the cap
-- number: shareable Toughness the talent could share
-- int: allies allies in Coherency
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

--- Returns the share efficiency: the part of the shareable Toughness offered with an ally in Coherency.
-- The ally count does not matter, because both talents give every ally the full share.
-- treturn: number from 0 to 1
Stats.efficiency = function ()
    local shareable = Stats.shareable

    if shareable <= 0 or share_fraction <= 0 then
        return 0
    end

    return Stats.shared / (share_fraction * shareable)
end

return Stats
