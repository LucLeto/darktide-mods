return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`ShowCnJaKoGlyphsPlus` encountered an error loading the Darktide Mod Framework.")

        new_mod("ShowCnJaKoGlyphsPlus", {
            mod_script       = "ShowCnJaKoGlyphsPlus/scripts/mods/ShowCnJaKoGlyphsPlus/ShowCnJaKoGlyphsPlus",
            mod_data         = "ShowCnJaKoGlyphsPlus/scripts/mods/ShowCnJaKoGlyphsPlus/ShowCnJaKoGlyphsPlus_data",
            mod_localization = "ShowCnJaKoGlyphsPlus/scripts/mods/ShowCnJaKoGlyphsPlus/ShowCnJaKoGlyphsPlus_localization",
        })
    end,
    packages = {},
    version = "2.1.1",
    mod_id = "1113",
}
