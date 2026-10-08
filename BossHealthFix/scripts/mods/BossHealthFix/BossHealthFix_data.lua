--- Boss Health Fix's DMF mod data; the mod description, without a settings menu.
-- The returned table names the mod and makes it togglable. There are no options: disabling the mod
-- in the mod options disables its hook and restores vanilla behaviour, e.g. for a control test.
--
-- Loaded by DMF as `mod_data`, as declared in `BossHealthFix.mod`.
-- module: BossHealthFix_data
-- author: LucLeto
local mod = get_mod("BossHealthFix")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
}
