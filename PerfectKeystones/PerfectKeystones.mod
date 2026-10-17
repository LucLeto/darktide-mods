return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`Perfect Keystones` encountered an error loading the Darktide Mod Framework.")

        new_mod("PerfectKeystones", {
            mod_script       = "PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones",
            mod_data         = "PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones_data",
            mod_localization = "PerfectKeystones/scripts/mods/PerfectKeystones/PerfectKeystones_localization",
        })
    end,
    packages = {},
}
