return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`ForDaEmprah` encountered an error loading the Darktide Mod Framework.")

		new_mod("ForDaEmprah", {
			mod_script       = "ForDaEmprah/scripts/mods/ForDaEmprah/ForDaEmprah",
			mod_data         = "ForDaEmprah/scripts/mods/ForDaEmprah/ForDaEmprah_data",
			mod_localization = "ForDaEmprah/scripts/mods/ForDaEmprah/ForDaEmprah_localization",
		})
	end,
	packages = {},
}
