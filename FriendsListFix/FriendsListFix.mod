return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Friends List Fix requires the Darktide Mod Framework.")

        new_mod("FriendsListFix", {
            mod_script = "FriendsListFix/scripts/mods/FriendsListFix/FriendsListFix",
            mod_data = "FriendsListFix/scripts/mods/FriendsListFix/FriendsListFix_data",
            mod_localization = "FriendsListFix/scripts/mods/FriendsListFix/FriendsListFix_localization",
        })
    end,
    packages = {},
}
