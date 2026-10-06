return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`Overflow Meter` encountered an error loading the Darktide Mod Framework.")

        new_mod("OverflowMeter", {
            mod_script       = "OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter",
            mod_data         = "OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_data",
            mod_localization = "OverflowMeter/scripts/mods/OverflowMeter/OverflowMeter_localization",
        })
    end,
    packages = {},
    load_after = {
        "dmf",
    },
    version = "1.5.0",
    mod_id = "1095",
}
