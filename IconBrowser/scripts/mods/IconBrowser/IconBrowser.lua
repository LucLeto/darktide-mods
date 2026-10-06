local mod = get_mod("IconBrowser")
local Views = require("scripts/ui/views/views")

local floor = math.floor
local sort = table.sort
local format = string.format

local VIEW_NAME = "icon_browser_view"
local VIEW_PACKAGE = "packages/ui/views/system_view/system_view"
local PACKAGE_REF = "IconBrowser"
local VIEW_MODULE = "IconBrowser/scripts/mods/IconBrowser/icon_browser_view"
local ALT_VIEW_MODULE = "scripts/mods/IconBrowser/icon_browser_view"
local ICON_INDEX_MODULE = "IconBrowser/scripts/mods/IconBrowser/IconIndex"
local _requested_icon_packages = {}

local DEFAULT_WINDOW_SCALE = 100
local DEFAULT_WINDOW_OFFSET_X = 0
local DEFAULT_WINDOW_OFFSET_Y = 0
local DEFAULT_MOVE_STEP = 10

local MIN_WINDOW_SCALE = 50
local MAX_WINDOW_SCALE = 200
local MIN_WINDOW_POSITION = -12000
local MAX_WINDOW_POSITION = 12000
local MIN_MOVE_STEP = 1
local MAX_MOVE_STEP = 200

local ICON_BROWSER_PACKAGES = {
    -- Core menu and profile surfaces, broad UI atlas coverage
    "packages/ui/views/main_menu_view/main_menu_view",
    "packages/ui/views/main_menu_background_view/main_menu_background_view",
    "packages/ui/views/character_appearance_view/character_appearance_view",
    "packages/ui/views/class_selection_view/class_selection_view",
    "packages/ui/views/options_view/options_view",
    "packages/ui/views/news_view/news_view",
    "packages/ui/views/system_view/system_view",
    "packages/ui/views/loading_view/loading_screen_background",
    "packages/ui/views/loading_view/loading_view",
    "packages/ui/views/player_character_options_view/player_character_options_view",
    "packages/ui/views/social_menu_view/social_menu_view",
    "packages/ui/views/social_menu_roster_view/social_menu_roster_view",
    "packages/ui/views/group_finder_view/group_finder_view",
    "packages/ui/views/lobby_view/lobby_view",
    "packages/ui/views/report_player_view/report_player_view",
    "packages/ui/views/video_view/video_view",
    "packages/ui/views/splash_view/splash_view",
    "packages/ui/ui_signin_assets",

    -- Inventory, weapon, and generic item icon sources
    "packages/ui/views/inventory_view/inventory_view",
    "packages/ui/views/inventory_background_view/inventory_background_view",
    "packages/ui/views/inventory_weapons_view/inventory_weapons_view",
    "packages/ui/views/inventory_weapon_details_view/inventory_weapon_details_view",
    "packages/ui/views/inventory_weapon_marks_view/inventory_weapon_marks_view",
    "packages/ui/views/inventory_weapon_cosmetics_view/inventory_weapon_cosmetics_view",
    "packages/ui/views/inventory_cosmetics_view/inventory_cosmetics_view",
    "packages/ui/views/cosmetics_inspect_view/cosmetics_inspect_view",
    "packages/ui/views/store_item_detail_view/store_item_detail_view",
    "packages/ui/hud/player_weapon/player_weapon",
    "packages/ui/hud/wield_info/wield_info",
    "packages/ui/hud/weapon_counter/weapon_counter",

    -- Mastery, talent, crafting, and generic item-type placeholders
    "packages/ui/views/masteries_overview_view/masteries_overview_view",
    "packages/ui/views/mastery_view/mastery_view",
    "packages/ui/views/talent_builder_view/talent_builder_view",
    "packages/ui/views/crafting_view/crafting_view",
    "packages/ui/views/crafting_mechanicus_upgrade_expertise_view/crafting_mechanicus_upgrade_expertise_view",
    "packages/ui/views/crafting_mechanicus_replace_trait_view/crafting_mechanicus_replace_trait_view",
    "packages/ui/views/crafting_mechanicus_replace_perk_view/crafting_mechanicus_replace_perk_view",
    "packages/ui/views/crafting_mechanicus_upgrade_item_view/crafting_mechanicus_upgrade_item_view",
    "packages/ui/views/crafting_mechanicus_barter_items_view/crafting_mechanicus_barter_items_view",
    "packages/ui/views/crafting_mechanicus_modify_view/crafting_mechanicus_modify_view",

    -- Vendors, store, currencies, cosmetics, and appearance-related icons
    "packages/ui/views/credits_goods_vendor_view/credits_goods_vendor_view",
    "packages/ui/views/credits_vendor_view/credits_vendor_view",
    "packages/ui/views/credits_vendor_background_view/credits_vendor_background_view",
    "packages/ui/views/marks_goods_vendor_view/marks_goods_vendor_view",
    "packages/ui/views/marks_vendor_view/marks_vendor_view",
    "packages/ui/views/store_view/store_view",
    "packages/ui/views/cosmetics_vendor_view/cosmetics_vendor_view",
    "packages/ui/views/cosmetics_vendor_background_view/cosmetics_vendor_background_view",
    "packages/ui/views/barber_vendor_background_view/barber_vendor_background_view",
    "packages/ui/views/broker_stimm_builder_view/broker_stimm_builder_view",
    "packages/ui/views/live_events_view/live_events_view",
    "packages/ui/views/penance_overview_view/penance_overview_view",
    "packages/ui/material_sets/circumstances",

    -- Mission, contracts, havoc, and player-journey icon families
    "packages/ui/views/mission_intro_view/mission_intro_view",
    "packages/ui/views/mission_board_view/mission_board_view",
    "packages/ui/views/mission_voting_view/mission_voting_view",
    "packages/ui/views/contracts_view/contracts_view",
    "packages/ui/views/contracts_background_view/contracts_background_view",
    "packages/ui/views/scanner_display_view/scanner_display_view",
    "packages/ui/views/havoc_reward_presentation_view/havoc_reward_presentation_view",
    "packages/ui/views/havoc_play_view/havoc_play_view",
    "packages/ui/views/havoc_background_view/havoc_background_view",
    "packages/ui/views/expedition_play_view/expedition_play_view",
    "packages/ui/views/expedition_background_view/expedition_background_view",
    "packages/ui/views/expedition_view/expedition_view",
    "packages/ui/views/horde_play_view/horde_play_view",
    "packages/ui/views/training_grounds_options_view/training_grounds_options_view",
    "packages/ui/views/training_grounds_view/training_grounds_view",
    "packages/ui/views/end_player_view/end_player_view",

    -- HUD packages that commonly carry ability, buff, frame, and flat icon materials
    "packages/ui/hud/team_player_panel/team_player_panel",
    "packages/ui/hud/crosshair/crosshair",
    "packages/ui/hud/tactical_overlay/tactical_overlay",
    "packages/ui/hud/mission_objective_feed/mission_objective_feed",
    "packages/ui/hud/mission_objective_popup/mission_objective_popup",
    "packages/ui/hud/objective_progress_bar/objective_progress_bar",
    "packages/ui/hud/onboarding_popup/onboarding_popup",
    "packages/ui/hud/area_notification_popup/area_notification_popup",
    "packages/ui/hud/mission_speaker_popup/mission_speaker_popup",
    "packages/ui/hud/world_markers/world_markers",
    "packages/ui/hud/interaction/interaction",
    "packages/ui/hud/emote_wheel/emote_wheel",
    "packages/ui/hud/boss_health/boss_health",
    "packages/ui/hud/player_ability/player_ability",
    "packages/ui/hud/damage_indicator/damage_indicator",
    "packages/ui/hud/blocking/blocking",
    "packages/ui/hud/dodge_counter/dodge_counter",
    "packages/ui/hud/overcharge/overcharge",
    "packages/ui/hud/smart_tagging/smart_tagging",
    "packages/ui/hud/prologue_tutorial_step_tracker/prologue_tutorial_step_tracker",
    "packages/ui/hud/prologue_tutorial_info_box/prologue_tutorial_info_box",
    "packages/ui/hud/player_buffs/player_buffs",
}

local ICON_BROWSER_LEVEL_PACKAGES = {
    -- Inventory and itemization levels, often pull extra material dependencies
    "content/levels/ui/inventory/inventory",
    "content/levels/ui/inventory_weapon_view/inventory_weapon_view",
    "content/levels/ui/crafting_view_itemization/crafting_view_itemization",
    "content/levels/ui/crafting_view_sacrifice/world",
    "content/levels/ui/store/store",
    "content/levels/ui/credits_vendor/credits_vendor",
    "content/levels/ui/vendor_cosmetics_preview_gear/vendor_cosmetics_preview_gear",
    "content/levels/ui/vendor_cosmetics_preview_weapon/vendor_cosmetics_preview_weapon",
    "content/levels/ui/credits_cosmetics_vendor/credits_cosmetics_vendor",

    -- Mission and event levels, useful for mission-type and event currency icons
    "content/levels/ui/mission_intro/mission_intro",
    "content/levels/ui/mission_board_player_journey/mission_board_player_journey",
    "content/levels/ui/contracts_view/contracts_view",
    "content/levels/ui/havoc/havoc",
    "content/levels/ui/penances/world",
    "content/levels/ui/training_grounds/training_grounds",

    -- Barber and appearance levels, useful for hair/appearance icon families
    "content/levels/ui/barber/barber",
    "content/levels/ui/barber_character_appearance/barber_character_appearance",
    "content/levels/ui/barber_character_mindwipe/barber_character_mindwipe",
    "content/levels/ui/character_create/character_create",
    "content/levels/ui/cartel_selection/cartel_selection",

    -- Expedition player-journey level, used by mission_types_pj icon families
    "content/levels/ui/expedition/world",
}

local function _clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    elseif value > max_value then
        return max_value
    end

    return value
end

local function _normalize_int(value, default_value, min_value, max_value)
    local numeric_value = floor(tonumber(value) or default_value)

    return _clamp(numeric_value, min_value, max_value)
end

local function _emit_user_message(message, prefer_notification)
    mod:echo(message)

    if not Mods or not Mods.message then
        return
    end

    if prefer_notification and Mods.message.notify then
        Mods.message.notify(message)
    elseif Mods.message.echo then
        Mods.message.echo(message)
    end
end

local function _register_view_module_preload()
    local package_preload = package and package.preload

    if not package_preload then
        return
    end

    local loader = function()
        if mod and mod.io_dofile then
            return mod:io_dofile(VIEW_MODULE)
        end

        return dofile("./../mods/" .. VIEW_MODULE .. ".lua")
    end

    if not package_preload[VIEW_MODULE] then
        package_preload[VIEW_MODULE] = loader
    end

    if not package_preload[ALT_VIEW_MODULE] then
        package_preload[ALT_VIEW_MODULE] = loader
    end
end

local function _register_view()
    _register_view_module_preload()

    if Views[VIEW_NAME] then
        return
    end

    Views[VIEW_NAME] = {
        name = VIEW_NAME,
        class = "IconBrowserView",
        display_name = "mod_name",
        path = VIEW_MODULE,
        package = VIEW_PACKAGE,
        state_bound = true,
        allow_hud = false,
        disable_game_world = false,
        game_world_blur = 0.8,
        use_transition_ui = false,
        close_on_hotkey_pressed = true,
    }
end

local function _load_icon_index()
    local ok, icons = pcall(function()
        if mod and mod.io_dofile then
            return mod:io_dofile(ICON_INDEX_MODULE)
        end

        return require(ICON_INDEX_MODULE)
    end)

    if ok and type(icons) == "table" then
        sort(icons)
        return icons
    end

    return {}
end

local function _package_is_available(package_name)
    local application = Application

    if not application or not application.can_get_resource then
        return false
    end

    local ok, exists = pcall(function()
        return application.can_get_resource("package", package_name)
    end)

    return ok and exists or false
end

local function _package_is_loaded(package_name)
    local managers = Managers
    local package_manager = managers and managers.package

    if not package_manager or not package_manager.has_loaded then
        return false
    end

    local ok, is_loaded = pcall(package_manager.has_loaded, package_manager, package_name)

    return ok and is_loaded or false
end

local function _load_package_list(package_list)
    local managers = Managers
    local package_manager = managers and managers.package

    if not package_manager then
        return
    end

    for _, pkg in ipairs(package_list) do
        if _package_is_available(pkg) and not _requested_icon_packages[pkg] then
            if _package_is_loaded(pkg) then
                _requested_icon_packages[pkg] = true
            else
                local ok = pcall(function()
                    package_manager:load(pkg, PACKAGE_REF, nil, true)
                end)

                if ok then
                    _requested_icon_packages[pkg] = true
                end
            end
        end
    end
end

local function _all_packages_loaded(package_list)
    for _, pkg in ipairs(package_list) do
        if _package_is_available(pkg) and not _package_is_loaded(pkg) then
            return false
        end
    end

    return true
end

local function _ensure_icon_packages_loaded()
    local managers = Managers
    local package_manager = managers and managers.package

    if not package_manager then
        return false
    end

    _load_package_list(ICON_BROWSER_PACKAGES)
    _load_package_list(ICON_BROWSER_LEVEL_PACKAGES)

    return _all_packages_loaded(ICON_BROWSER_PACKAGES) and _all_packages_loaded(ICON_BROWSER_LEVEL_PACKAGES)
end

local function _view_is_active()
    local managers = Managers
    local ui_manager = managers and managers.ui

    return ui_manager and ui_manager:view_active(VIEW_NAME)
end

function mod.get_icon_browser_scale()
    return _normalize_int(mod:get("icon_browser_scale"), DEFAULT_WINDOW_SCALE, MIN_WINDOW_SCALE, MAX_WINDOW_SCALE)
end

function mod.get_icon_browser_offset_x()
    return _normalize_int(mod:get("icon_browser_pos_x"), DEFAULT_WINDOW_OFFSET_X, MIN_WINDOW_POSITION,
        MAX_WINDOW_POSITION)
end

function mod.get_icon_browser_offset_y()
    return _normalize_int(mod:get("icon_browser_pos_y"), DEFAULT_WINDOW_OFFSET_Y, MIN_WINDOW_POSITION,
        MAX_WINDOW_POSITION)
end

function mod.get_icon_browser_move_step()
    return _normalize_int(mod:get("icon_browser_move_step"), DEFAULT_MOVE_STEP, MIN_MOVE_STEP, MAX_MOVE_STEP)
end

function mod.set_icon_browser_scale(new_value)
    mod:set("icon_browser_scale", _normalize_int(new_value, DEFAULT_WINDOW_SCALE, MIN_WINDOW_SCALE, MAX_WINDOW_SCALE))
end

function mod.set_icon_browser_position(new_x, new_y)
    if new_x ~= nil then
        mod:set("icon_browser_pos_x",
            _normalize_int(new_x, DEFAULT_WINDOW_OFFSET_X, MIN_WINDOW_POSITION, MAX_WINDOW_POSITION))
    end

    if new_y ~= nil then
        mod:set("icon_browser_pos_y",
            _normalize_int(new_y, DEFAULT_WINDOW_OFFSET_Y, MIN_WINDOW_POSITION, MAX_WINDOW_POSITION))
    end
end

function mod.set_icon_browser_move_step(new_value)
    mod:set("icon_browser_move_step", _normalize_int(new_value, DEFAULT_MOVE_STEP, MIN_MOVE_STEP, MAX_MOVE_STEP))
end

function mod.move_icon_browser_left(...)
    local move_step = mod.get_icon_browser_move_step()
    mod.set_icon_browser_position(mod.get_icon_browser_offset_x() - move_step, nil)
end

function mod.move_icon_browser_right(...)
    local move_step = mod.get_icon_browser_move_step()
    mod.set_icon_browser_position(mod.get_icon_browser_offset_x() + move_step, nil)
end

function mod.move_icon_browser_up(...)
    local move_step = mod.get_icon_browser_move_step()
    mod.set_icon_browser_position(nil, mod.get_icon_browser_offset_y() - move_step)
end

function mod.move_icon_browser_down(...)
    local move_step = mod.get_icon_browser_move_step()
    mod.set_icon_browser_position(nil, mod.get_icon_browser_offset_y() + move_step)
end

_register_view()
mod._icon_paths = mod._icon_paths or _load_icon_index()
mod._icon_browser_view_open = mod._icon_browser_view_open or false
mod._icon_render_failures = mod._icon_render_failures or {}

function mod.get_icon_paths()
    return mod._icon_paths or {}
end

function mod.can_render_icon_path(path)
    return type(path) == "string" and path ~= "" and not mod._icon_render_failures[path]
end

function mod.mark_icon_render_failed(path, error_message)
    if type(path) ~= "string" or path == "" then
        return
    end

    local failures = mod._icon_render_failures

    if failures[path] then
        return
    end

    failures[path] = true

    local message = format("[IconBrowser] Failed to render icon preview: %s", path)

    if error_message and error_message ~= "" then
        message = format("%s (%s)", message, tostring(error_message))
    end

    _emit_user_message(message, false)
end

function mod.copy_icon_path_to_clipboard(icon_id, path)
    if type(path) ~= "string" or path == "" then
        local message = "[IconBrowser] Unable to copy icon path."

        _emit_user_message(message, true)

        return false, "Copy failed"
    end

    local clipboard = Clipboard
    local clipboard_put = clipboard and clipboard.put

    if type(clipboard_put) ~= "function" then
        local message = format("[IconBrowser] Clipboard unavailable for #%d %s", icon_id or 0, path)

        _emit_user_message(message, true)

        return false, "Clipboard unavailable"
    end

    local ok, copied = pcall(clipboard_put, path)

    if ok and copied ~= false then
        local message = format("[IconBrowser] Copied #%d %s", icon_id or 0, path)

        _emit_user_message(message, true)

        return true, "Copied path to clipboard"
    end

    local message = format("[IconBrowser] Failed to copy #%d %s", icon_id or 0, path)

    _emit_user_message(message, true)

    return false, "Copy failed"
end

local function _open_icon_browser_view()
    local managers = Managers
    local ui_manager = managers and managers.ui

    if not ui_manager then
        return false
    end

    if ui_manager:view_active(VIEW_NAME) then
        mod._icon_browser_view_open = true
        return true
    end

    ui_manager:open_view(VIEW_NAME)
    mod._icon_browser_view_open = true

    return true
end

function mod.on_all_mods_loaded()
    _ensure_icon_packages_loaded()
end

function mod.update(dt)
    if mod._pending_icon_browser_open and _ensure_icon_packages_loaded() then
        mod._pending_icon_browser_open = false
        mod._icon_browser_loading_notified = false
        _open_icon_browser_view()
    end
end

function mod.open_icon_browser(...)
    _register_view()

    if not _ensure_icon_packages_loaded() then
        mod._pending_icon_browser_open = true

        if not mod._icon_browser_loading_notified then
            local message = "[IconBrowser] Loading icon packages..."
            _emit_user_message(message, false)

            mod._icon_browser_loading_notified = true
        end

        return
    end

    mod._pending_icon_browser_open = false
    mod._icon_browser_loading_notified = false
    _open_icon_browser_view()
end

function mod.close_icon_browser(...)
    local managers = Managers
    local ui_manager = managers and managers.ui

    mod._pending_icon_browser_open = false
    mod._icon_browser_loading_notified = false

    if not ui_manager then
        return
    end

    if ui_manager:view_active(VIEW_NAME) then
        ui_manager:close_view(VIEW_NAME)
    end

    mod._icon_browser_view_open = false
end

function mod.toggle_icon_browser(...)
    if _view_is_active() or mod._icon_browser_view_open or mod._pending_icon_browser_open then
        mod.close_icon_browser()
    else
        mod.open_icon_browser()
    end
end

function mod.on_setting_changed(_setting_id)
end

return mod
