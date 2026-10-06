return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`Perfect Thrust` encountered an error loading the Darktide Mod Framework.")

        new_mod("PerfectThrust", {
            mod_script       = "PerfectThrust/scripts/mods/PerfectThrust/PerfectThrust",
            mod_data         = "PerfectThrust/scripts/mods/PerfectThrust/PerfectThrust_data",
            mod_localization = "PerfectThrust/scripts/mods/PerfectThrust/PerfectThrust_localization",
        })
    end,
    packages = {},
}
