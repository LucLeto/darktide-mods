--- DMF entry script of Boss Health Fix; removes stale targets from the vanilla boss health HUD.
-- DMF runs this file as the `mod_script` named in `BossHealthFix.mod`; `BossHealthFix_data.lua`
-- and `BossHealthFix_localization.lua` are loaded by DMF from the same declaration.
--
-- Vanilla `HudElementBossHealth.update` only checks `ALIVE[unit]` before it reads
-- `target.health_extension`. A dead boss stays alive as a ragdoll unit after its extensions have
-- been removed, so a target that is still listed after its health extension was destroyed crashes
-- the update with "Cannot access property current_health_percent on destroyed object of type
-- HuskHealthExtension". Reported on non-host clients with more bosses than visible health bars.
--
-- A `hook` on `update` drops such targets from `_active_targets_array`, `_active_targets_by_unit`
-- and `_queued_targets` before vanilla runs, then calls the original update unchanged. Promoting
-- queued bosses stays with vanilla `event_boss_encounter_end`. This is a defensive workaround:
-- remove the mod once Fatshark fixes the boss HUD.
-- module: BossHealthFix
-- author: LucLeto
local mod = get_mod("BossHealthFix")

local HEALTH_ALIVE = HEALTH_ALIVE
local ScriptUnit_has_extension = ScriptUnit.has_extension
local table_remove = table.remove

-- ----------------------------------------------------------------------------
-- Stale targets
-- ----------------------------------------------------------------------------

--- Returns whether a boss HUD entry for `unit` can no longer be read safely.
-- `HEALTH_ALIVE` is the cheap check that passes for every living boss. Vanilla also clears it at
-- the killing blow, while the boss plays its death animation with a valid health extension, so a
-- dead unit only counts as stale once its health extension is gone. Dying bosses keep their bar.
-- ?unit: unit boss unit of the HUD entry
-- return: bool
local function is_stale(unit)
    return not unit or not HEALTH_ALIVE[unit] and not ScriptUnit_has_extension(unit, "health_system")
end

--- Removes stale entries from the active and queued boss HUD targets.
-- Active targets are removed in place, keeping the order of the remaining health bars, with the
-- same bookkeeping as vanilla `event_boss_encounter_end`. No queued boss is promoted here.
-- tab: self HudElementBossHealth instance
local function prune_stale_targets(self)
    local active_targets = self._active_targets_array

    if active_targets then
        local active_targets_by_unit = self._active_targets_by_unit
        local removed_target = false

        for i = #active_targets, 1, -1 do
            local target = active_targets[i]
            local unit = target and target.unit

            if is_stale(unit) then
                local breed = target and target.breed

                mod:warning("Removing stale active boss HUD target at index %d, unit=%s, breed=%s", i, tostring(unit), tostring(breed and breed.name))

                if unit and active_targets_by_unit then
                    active_targets_by_unit[unit] = nil
                end

                table_remove(active_targets, i)

                removed_target = true
            end
        end

        if removed_target then
            if #active_targets == 0 then
                self:_set_active(false)
            else
                self._force_update = true
            end
        end
    end

    local queued_targets = self._queued_targets

    if queued_targets then
        for i = #queued_targets, 1, -1 do
            local target = queued_targets[i]
            local unit = target and target.unit

            if is_stale(unit) then
                mod:warning("Removing stale queued boss HUD target at index %d, unit=%s", i, tostring(unit))

                table_remove(queued_targets, i)
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Boss health HUD hook
-- ----------------------------------------------------------------------------

-- A plain hook so the pruning runs before the original update and before every `hook_safe` on it.
mod:hook(CLASS.HudElementBossHealth, "update", function (func, self, ...)
    prune_stale_targets(self)

    return func(self, ...)
end)
