return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`IconBrowser` encountered an error loading the Darktide Mod Framework.")

		new_mod("IconBrowser", {
			mod_script       = "IconBrowser/scripts/mods/IconBrowser/IconBrowser",
			mod_data         = "IconBrowser/scripts/mods/IconBrowser/IconBrowser_data",
			mod_localization = "IconBrowser/scripts/mods/IconBrowser/IconBrowser_localization",
		})
	end,
	packages = {},
}
