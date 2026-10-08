return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`Boss Health Fix` encountered an error loading the Darktide Mod Framework.")

        new_mod("BossHealthFix", {
            mod_script       = "BossHealthFix/scripts/mods/BossHealthFix/BossHealthFix",
            mod_data         = "BossHealthFix/scripts/mods/BossHealthFix/BossHealthFix_data",
            mod_localization = "BossHealthFix/scripts/mods/BossHealthFix/BossHealthFix_localization",
        })
    end,
    packages = {},
}
