local mod = get_mod("ShowCnJaKoGlyphsPlus")

local FontDefinitions = require("scripts/managers/ui/ui_fonts_definitions")
local UIFontManager = require("scripts/managers/ui/ui_font_manager")

local FONT_TYPES = FontDefinitions.FontTypes
local SANS_SERIF = FONT_TYPES.sans_serif
local SERIF = FONT_TYPES.serif

local font_packages = {
    "packages/ui/fonts/slug_zh_cn",
    "packages/ui/fonts/slug_zh_tw",
    "packages/ui/fonts/slug_ja",
    "packages/ui/fonts/slug_ko",
}

local FONT_PACKAGE_REFERENCE = "ShowCnJaKoGlyphsPlus"

local font_packages_loading = false
local font_extension_enabled = false

local function get_fallback_order()
    local q = {
        mod:get("q_zh_hans"),
        mod:get("q_zh_hant"),
        mod:get("q_ja"),
        mod:get("q_ko"),
    }
    local lang = {
        "sc",
        "tc",
        "jp",
        "kr",
    }
    for i = 1, 3 do
        for j = 1, 4 - i do
            if q[j] < q[j + 1] then
                q[j], q[j + 1] = q[j + 1], q[j]
                lang[j], lang[j + 1] = lang[j + 1], lang[j]
            end
        end
    end
    return lang
end

local function get_active_locale_fonts()
    local localization_manager = Managers.localization
    local current_locale = localization_manager and localization_manager:language()

    return current_locale and FontDefinitions.locale_specific_fonts[current_locale]
end

local function append_unique_font(fonts, seen_fonts, font)
    if font and not seen_fonts[font] then
        fonts[#fonts + 1] = font
        seen_fonts[font] = true
    end
end

local function append_fallback_fonts(fonts, seen_fonts, fallback_fonts)
    if type(fallback_fonts) == "table" then
        for i = 1, #fallback_fonts do
            append_unique_font(fonts, seen_fonts, fallback_fonts[i])
        end
    else
        append_unique_font(fonts, seen_fonts, fallback_fonts)
    end
end

local function build_cjk_combo_font(locale_fonts)
    local font = {}
    local sans_serif = {}
    local serif = {}
    local seen_sans_serif = {}
    local seen_serif = {}

    if locale_fonts then
        for font_name in pairs(FontDefinitions.fonts) do
            local exact_override = locale_fonts[font_name]

            if exact_override then
                font[font_name] = exact_override
            end
        end

        append_fallback_fonts(sans_serif, seen_sans_serif, locale_fonts[SANS_SERIF])
        append_fallback_fonts(serif, seen_serif, locale_fonts[SERIF])
    end

    local fallback_order = get_fallback_order()

    for i = 1, #fallback_order do
        local lang = fallback_order[i]

        append_unique_font(sans_serif, seen_sans_serif, "noto_sans_" .. lang .. "_bold")
        append_unique_font(serif, seen_serif, "noto_sans_" .. lang .. "_black")
    end

    font[SANS_SERIF] = sans_serif
    font[SERIF] = serif

    return font
end

local function update_font()
    local font_manager = Managers.font

    if font_manager then
        font_manager:_setup_font_definitions(get_active_locale_fonts())
    end
end

mod:hook(UIFontManager, "_setup_font_definitions", function(func, self, locale_fonts, ...)
    if font_extension_enabled then
        locale_fonts = build_cjk_combo_font(locale_fonts or get_active_locale_fonts())
    end

    return func(self, locale_fonts, ...)
end)

local function update_font_packages_loading()
    if not font_packages_loading then
        return
    end

    local package_manager = Managers.package

    if not package_manager then
        return
    end

    for i = 1, #font_packages do
        if not package_manager:has_loaded(font_packages[i]) then
            return
        end
    end

    font_packages_loading = false
    font_extension_enabled = true
    mod.update = nil

    update_font()
end

local function load_font_packages()
    if font_packages_loading or font_extension_enabled then
        return
    end

    local package_manager = Managers.package

    if not package_manager then
        return
    end

    font_packages_loading = true
    mod.update = update_font_packages_loading

    for i = 1, #font_packages do
        local package_name = font_packages[i]

        if package_manager:reference_count(package_name, FONT_PACKAGE_REFERENCE) == 0 then
            package_manager:load(package_name, FONT_PACKAGE_REFERENCE, nil, true)
        end
    end

    update_font_packages_loading()
end

local function unload_font_packages()
    font_extension_enabled = false
    font_packages_loading = false
    mod.update = nil

    update_font()
end

mod.on_all_mods_loaded = function()
    if mod:is_enabled() then
        load_font_packages()
    end
end

mod.on_enabled = function(initial_call)
    if not initial_call then
        load_font_packages()
    end
end

mod.on_disabled = function()
    unload_font_packages()
end

mod.on_unload = function()
    unload_font_packages()
end

mod.on_setting_changed = function()
    if mod:is_enabled() and font_extension_enabled then
        update_font()
    end
end
