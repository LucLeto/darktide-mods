return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Skitarii Chat` encountered an error loading the Darktide Mod Framework.")

		new_mod("SkitariiChat", {
			mod_script       = "SkitariiChat/scripts/mods/SkitariiChat/SkitariiChat",
			mod_data         = "SkitariiChat/scripts/mods/SkitariiChat/SkitariiChat_data",
			mod_localization = "SkitariiChat/scripts/mods/SkitariiChat/SkitariiChat_localization",
		})
	end,
	packages = {},
	version = "0.2.3",
	mod_id = "",
}
