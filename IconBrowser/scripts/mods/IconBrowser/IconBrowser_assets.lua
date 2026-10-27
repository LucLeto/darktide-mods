--- Asset model of Icon Browser; one canonical record per indexed material path.
-- Built once from the sorted icon index: the browser ID stays the index position, the full path stays
-- the canonical identifier, and every derived field (readable name, category, search text) is computed
-- here so the grid, the list and the inspector all read the same record.
--
-- Localized names are resolved later, on the first open of the view, from game definition tables that
-- pair a UI material with a localization key; only keys the localization manager reports as existing
-- are used, so no name is guessed.
--
-- Asset fields:
-- `id` browser ID, the position in the sorted index; `id_text` the same as `#id`;
-- `path` full material path, the canonical identifier; `filename` its last path segment;
-- `directory` the path between `content/ui/materials/` and the filename; `folder` the same with a
-- trailing `/`, as the `in:` search filter matches it;
-- `family` the directory and the filename without its variant suffixes (`icons/currencies/credits` for
-- `credits_big` and `credits_small`); `family_size` the number of assets in the family;
-- `filename_count` the number of assets with the same filename;
-- `readable_name` the humanized filename, prefixed with the parent folder when several indexed paths
-- share the filename;
-- `display_name` the shown name: the localized name, else the humanized definition key, else
-- `readable_name`; `sort_name` its lower-case form for sorting;
-- `name_source` one of the `NAME_SOURCE_*` values; `name_key` the localization key of a localized
-- name, else false; `name_origin` the definition the name came from as `source.key`, else false;
-- `name_uses` how many further definitions use the same material;
-- `category` category id of `CATEGORIES`; `category_label` its localized label;
-- `source_refs` the script lines naming the path (`scripts/...lua:line`), else false; `item_refs`
-- the items using it as `hud_icon` (`{ item name, display name key }`), else false; `ref_count`
-- both counted together; `ref_files` the lower-case script files of `source_refs` without line
-- numbers, each once, else false; `usage_sizes` the sizes the game draws it at (`WxH`, most frequent
-- first), else false; `usage_width`, `usage_height` the first of them, else 0; all from
-- `attach_sources`;
-- `search_extra` the lower-case script files and item names it is found under, else "";
-- `search_blob` lower-case path, the path with `_`, `-` and `/` read as spaces, the names, `#id` and
-- `search_extra`, separated by `|`;
-- `lua_string`, `ui_snippet` the copy formats, built on first use, else false. Several selected
-- assets are copied with `field_lines`, `lua_array` and `lua_table`.
--
-- Loaded through `mod:io_dofile` by `IconBrowser.lua` and stored as `mod._assets_module`; the
-- model built by `build` is stored as `mod._assets`.
-- module: IconBrowser_assets
-- author: LucLeto
local concat = table.concat
local find = string.find
local format = string.format
local gsub = string.gsub
local lower = string.lower
local match = string.match
local sub = string.sub
local upper = string.upper
local pairs = pairs
local pcall = pcall
local sort = table.sort
local tonumber = tonumber
local tostring = tostring
local type = type

--- The assets module table.
local Assets = {}

-- ----------------------------------------------------------------------------
-- Constants
-- ----------------------------------------------------------------------------

--- Prefix shared by every UI material path; categories match the path below it.
local MATERIAL_ROOT = "content/ui/materials/"
local MATERIAL_ROOT_LENGTH = #MATERIAL_ROOT

--- Sources of an asset's display name: a localized definition name, a humanized definition key, or
-- the humanized filename.
Assets.NAME_SOURCE_LOCALIZED = "localized"
Assets.NAME_SOURCE_DEFINITION = "definition"
Assets.NAME_SOURCE_FILENAME = "filename"

--- Path categories, matched in order against the path below `content/ui/materials/`; the first match
-- wins and anything unmatched falls into `other`, so no asset is ever hidden by categorisation.
-- `all` is the pseudo category of the filter and owns no prefixes.
Assets.CATEGORIES = {
    { id = "all" },
    { id = "abilities", prefixes = { "icons/abilities/" } },
    { id = "talents", prefixes = { "icons/talents/", "icons/traits/", "icons/perks/" } },
    {
        id = "weapons",
        prefixes = { "icons/weapons/", "icons/throwables/", "icons/pocketables/", "icons/pickups/" },
    },
    { id = "hud", prefixes = { "hud/", "icons/hud/", "icons/player_states/" } },
    { id = "buffs", prefixes = { "icons/buffs/" } },
    {
        id = "classes",
        prefixes = {
            "icons/classes/", "icons/class_badges/", "icons/portraits/", "icons/npc_portraits/",
            "icons/character_creator/", "icons/appearances/",
        },
    },
    {
        id = "inventory",
        prefixes = {
            "icons/items/", "icons/item_types/", "icons/crafting/", "icons/currencies/", "icons/cosmetics/",
            "icons/engrams/", "icons/presets/", "icons/offer_cards/", "icons/categories/", "icons/list_buttons/",
        },
    },
    {
        id = "missions",
        prefixes = {
            "icons/mission_types/", "icons/mission_types_pj/", "icons/mission_type/", "icons/objectives/",
            "icons/difficulty/", "icons/mission_difficulty_complete/", "icons/circumstances/", "icons/contracts/",
        },
    },
    { id = "backgrounds", prefixes = { "backgrounds/" } },
    { id = "other" },
}

--- Ids of the pseudo category and of the fallback category.
local CATEGORY_ALL = "all"
local CATEGORY_OTHER = "other"

--- Filename suffixes that mark a size variant of the same icon. Numbered (`_01`, `_2b`) and lettered
-- (`_a`) variants are recognised by pattern.
local VARIANT_SUFFIXES = {
    tiny = true,
    small = true,
    medium = true,
    big = true,
    large = true,
    huge = true,
    xs = true,
    xl = true,
}

--- Lua UI snippet copied for an asset: a texture pass for `UIWidget.create_definition`, with the
-- material path as `%s`.
local UI_SNIPPET_FORMAT = [[{
    pass_type = "texture",
    style_id = "icon",
    value = "%s",
    style = {
        horizontal_alignment = "center",
        vertical_alignment = "center",
        size = { 64, 64 },
        color = { 255, 255, 255, 255 },
    },
},]]

-- ----------------------------------------------------------------------------
-- Derived fields
-- ----------------------------------------------------------------------------

--- `gsub` replacement that upper-cases the first letter of a word.
-- string: first first letter
-- string: rest rest of the word
-- treturn: string
local function _capitalize(first, rest)
    return upper(first) .. rest
end

--- Turns an identifier such as `credits_big` into a readable name such as `Credits Big`.
-- string: text identifier with underscores or hyphens
-- treturn: string
local function _humanize(text)
    text = gsub(text, "[_%-]+", " ")
    text = gsub(text, "^%s+", "")
    text = gsub(text, "%s+$", "")

    return (gsub(text, "(%a)(%w*)", _capitalize))
end

--- Returns a material path without its `content/ui/materials/` prefix.
-- string: path full material path
-- treturn: string
local function _relative_path(path)
    if sub(path, 1, MATERIAL_ROOT_LENGTH) == MATERIAL_ROOT then
        return sub(path, MATERIAL_ROOT_LENGTH + 1)
    end

    return path
end

--- Returns a filename without its variant suffixes, e.g. `credits` for `credits_big` and
-- `mission_type` for `mission_type_01`; several suffixes are removed one after another.
-- string: filename last path segment
-- treturn: string
local function _family_stem(filename)
    while true do
        local base, suffix = match(filename, "^(.+)_(%w+)$")

        if not base or not (VARIANT_SUFFIXES[suffix] or find(suffix, "^%d+%a?$") or find(suffix, "^%a$")) then
            return filename
        end

        filename = base
    end
end

--- Returns the id of the first category with a prefix matching the path, else `other`.
-- string: relative_path path below `content/ui/materials/`
-- treturn: string category id
local function _category_of(relative_path)
    local categories = Assets.CATEGORIES

    for i = 1, #categories do
        local prefixes = categories[i].prefixes

        if prefixes then
            for j = 1, #prefixes do
                if find(relative_path, prefixes[j], 1, true) == 1 then
                    return categories[i].id
                end
            end
        end
    end

    return CATEGORY_OTHER
end

--- Builds the lower-case text an asset is searched in.
-- tab: asset asset record with `path`, `readable_name` and `id_text`
-- ?string: localized_name verified localized name
-- ?string: definition_name humanized definition key
-- treturn: string
local function _search_blob(asset, localized_name, definition_name)
    local lower_path = lower(asset.path)

    return lower_path
        .. "|" .. gsub(lower_path, "[_%-/]", " ")
        .. "|" .. lower(asset.readable_name)
        .. "|" .. lower(localized_name or "")
        .. "|" .. lower(definition_name or "")
        .. "|" .. asset.id_text
        .. "|" .. asset.search_extra
        .. "|"
end

--- Builds the asset model from the sorted path list; `mod` localizes the category labels.
-- The model holds `list` (assets by browser ID), `count`, `by_path` (assets by full path),
-- `category_counts` and `category_labels` (by category id, `all` included), and `names_revision`
-- and `names_resolved`, which `resolve_names` updates.
-- tab: paths sorted array of material paths
-- tab: mod the DMF mod, for `mod:localize`
-- treturn: tab asset model
function Assets.build(paths, mod)
    local count = #paths
    local list = {}
    local by_path = {}
    local filename_counts = {}
    local family_counts = {}
    local category_counts = {}
    local category_labels = {}
    local categories = Assets.CATEGORIES

    for i = 1, #categories do
        local id = categories[i].id

        category_counts[id] = 0
        category_labels[id] = mod:localize("category_" .. id)
    end

    for i = 1, count do
        local filename = match(paths[i], "([^/]+)$") or paths[i]

        filename_counts[filename] = (filename_counts[filename] or 0) + 1
    end

    for i = 1, count do
        local path = paths[i]
        local relative_path = _relative_path(path)
        local directory = match(relative_path, "^(.*)/[^/]+$") or ""
        local filename = match(path, "([^/]+)$") or path
        local readable_name = _humanize(filename)

        if filename_counts[filename] > 1 then
            local parent = match(directory, "([^/]+)$")

            if parent then
                readable_name = _humanize(parent) .. " " .. readable_name
            end
        end

        if readable_name == "" then
            readable_name = filename
        end

        local category = _category_of(relative_path)
        local stem = _family_stem(filename)
        local family = directory ~= "" and directory .. "/" .. stem or stem
        local asset = {
            id = i,
            id_text = "#" .. i,
            path = path,
            filename = filename,
            directory = directory,
            folder = directory .. "/",
            family = family,
            family_size = 0,
            filename_count = filename_counts[filename],
            readable_name = readable_name,
            display_name = readable_name,
            sort_name = lower(readable_name),
            name_source = Assets.NAME_SOURCE_FILENAME,
            name_key = false,
            name_origin = false,
            name_uses = 0,
            category = category,
            category_label = category_labels[category],
            source_refs = false,
            item_refs = false,
            ref_count = 0,
            ref_files = false,
            usage_sizes = false,
            usage_width = 0,
            usage_height = 0,
            search_extra = "",
            search_blob = "",
            lua_string = false,
            ui_snippet = false,
        }

        asset.search_blob = _search_blob(asset, nil, nil)
        list[i] = asset
        by_path[path] = asset
        category_counts[category] = category_counts[category] + 1
        family_counts[family] = (family_counts[family] or 0) + 1
    end

    for i = 1, count do
        local asset = list[i]

        asset.family_size = family_counts[asset.family]
    end

    category_counts[CATEGORY_ALL] = count

    return {
        list = list,
        count = count,
        by_path = by_path,
        category_counts = category_counts,
        category_labels = category_labels,
        names_revision = 0,
        names_resolved = false,
        sources_attached = false,
        sources_game_version = false,
        sources_items_version = false,
    }
end

-- ----------------------------------------------------------------------------
-- Source references
-- ----------------------------------------------------------------------------

--- Adds the generated source references to the assets they name, once; safe to call repeatedly.
-- Sets each named asset's `source_refs`, `item_refs`, `ref_count`, `ref_files`, `usage_sizes`,
-- `usage_width` and `usage_height`, and adds the script files (without line numbers) and item names to its search
-- text, so an icon can be found by where the game uses it. Call it before `resolve_names`, which
-- turns the items' display names into name candidates.
-- tab: assets asset model built by `build`
-- ?tab: sources the `IconSources.lua` table, nil when it could not be loaded
-- treturn: int number of assets with references
function Assets.attach_sources(assets, sources)
    if assets.sources_attached or type(sources) ~= "table" or type(sources.materials) ~= "table" then
        return 0
    end

    assets.sources_attached = true
    assets.sources_game_version = sources.game_version or false
    assets.sources_items_version = sources.items_version or false

    local by_path = assets.by_path
    local attached = 0

    for path, entry in pairs(sources.materials) do
        local asset = by_path[path]

        if asset and type(entry) == "table" then
            local refs = type(entry.refs) == "table" and entry.refs or false
            local items = type(entry.items) == "table" and entry.items or false
            local sizes = type(entry.sizes) == "table" and entry.sizes or false
            local search_parts = {}
            local seen_files = {}
            local ref_files = false

            if refs then
                ref_files = {}

                for i = 1, #refs do
                    local file = lower(match(refs[i], "^(.-):%d+$") or refs[i])

                    if not seen_files[file] then
                        seen_files[file] = true
                        ref_files[#ref_files + 1] = file
                        search_parts[#search_parts + 1] = file
                    end
                end
            end

            if items then
                for i = 1, #items do
                    search_parts[#search_parts + 1] = lower(tostring(items[i][1]))
                end
            end

            if sizes and sizes[1] then
                local width, height = match(sizes[1], "^(%d+)x(%d+)$")

                asset.usage_width = tonumber(width) or 0
                asset.usage_height = tonumber(height) or 0
            end

            asset.source_refs = refs
            asset.item_refs = items
            asset.ref_count = (refs and #refs or 0) + (items and #items or 0)
            asset.ref_files = ref_files
            asset.usage_sizes = sizes
            asset.search_extra = concat(search_parts, " ")
            asset.search_blob = _search_blob(asset, nil, nil)
            attached = attached + 1
        end
    end

    return attached
end

--- Returns the asset's references as copyable text: one script line per line, then one
-- `item <item name>` line per item.
-- tab: asset asset record
-- treturn: string empty when nothing references the asset
function Assets.source_reference_text(asset)
    local lines = {}
    local refs = asset.source_refs
    local items = asset.item_refs

    if refs then
        for i = 1, #refs do
            lines[#lines + 1] = refs[i]
        end
    end

    if items then
        for i = 1, #items do
            lines[#lines + 1] = "item " .. tostring(items[i][1])
        end
    end

    return concat(lines, "\n")
end

-- ----------------------------------------------------------------------------
-- Localized names
-- ----------------------------------------------------------------------------

-- Every collector walks one game definition table and calls
-- `add(material, loc_key, source, key)` for each material it names; `add` ignores materials that
-- are not in the index.

--- Mission types: `icon` and `mission_board_icon` named by `name`.
-- tab: data `MissionTypes`
-- func: add candidate collector
local function _collect_mission_types(data, add)
    for key, entry in pairs(data) do
        if type(entry) == "table" then
            add(entry.icon, entry.name, "mission_types", key)
            add(entry.mission_board_icon, entry.name, "mission_types", key)
        end
    end
end

--- Circumstances: `ui.icon` and `ui.mission_board_icon` named by `ui.display_name`.
-- tab: data `CircumstanceTemplates`
-- func: add candidate collector
local function _collect_circumstances(data, add)
    for key, entry in pairs(data) do
        local ui = type(entry) == "table" and entry.ui

        if type(ui) == "table" then
            add(ui.icon, ui.display_name, "circumstance_templates", key)
            add(ui.mission_board_icon, ui.display_name, "circumstance_templates", key)
        end
    end
end

--- Currencies: `icon_texture_big` and `icon_texture_small` named by `display_name`.
-- tab: data `WalletSettings`
-- func: add candidate collector
local function _collect_wallets(data, add)
    for key, entry in pairs(data) do
        if type(entry) == "table" then
            add(entry.icon_texture_big, entry.display_name, "wallet_settings", key)
            add(entry.icon_texture_small, entry.display_name, "wallet_settings", key)
        end
    end
end

--- Difficulty levels: `icon` and `digital_icon` named by `display_name`, keyed by the level name.
-- tab: data `DangerSettings`
-- func: add candidate collector
local function _collect_danger_levels(data, add)
    local danger_levels = data.danger_levels

    if type(danger_levels) ~= "table" then
        return
    end

    for i = 1, #danger_levels do
        local entry = danger_levels[i]

        if type(entry) == "table" then
            add(entry.icon, entry.display_name, "danger_settings", entry.name or tostring(i))
            add(entry.digital_icon, entry.display_name, "danger_settings", entry.name or tostring(i))
        end
    end
end

--- Archetype fields that hold a class icon material, all named by the archetype's name.
local ARCHETYPE_ICON_FIELDS = {
    "archetype_icon_large",
    "archetype_icon_selection_large",
    "archetype_icon_selection_large_unselected",
    "archetype_background_large",
    "archetype_badge",
}

--- Classes: the `ARCHETYPE_ICON_FIELDS` materials named by `archetype_name`.
-- tab: data `Archetypes`
-- func: add candidate collector
local function _collect_archetypes(data, add)
    for key, entry in pairs(data) do
        if type(entry) == "table" then
            for i = 1, #ARCHETYPE_ICON_FIELDS do
                add(entry[ARCHETYPE_ICON_FIELDS[i]], entry.archetype_name, "archetypes", key)
            end
        end
    end
end

--- Item types and store categories: two pairs of `UISettings` lookups joined on their shared keys.
-- tab: data `UISettings`
-- func: add candidate collector
local function _collect_ui_settings(data, add)
    local materials = data.item_type_material_lookup
    local names = data.item_type_localization_lookup

    if type(materials) == "table" and type(names) == "table" then
        for key, material in pairs(materials) do
            add(material, names[key], "item_types", key)
        end
    end

    materials = data.texture_by_store_category
    names = data.display_name_by_store_category

    if type(materials) == "table" and type(names) == "table" then
        for key, material in pairs(materials) do
            add(material, names[key], "store_categories", key)
        end
    end
end

--- Crafting recipes: `icon` named by `display_name`.
-- tab: data `CraftingSettings` or the Mechanicus crafting settings
-- func: add candidate collector
local function _collect_recipes(data, add)
    local recipes = data.recipes

    if type(recipes) ~= "table" then
        return
    end

    for key, entry in pairs(recipes) do
        if type(entry) == "table" then
            add(entry.icon, entry.display_name, "crafting_recipes", key)
        end
    end
end

--- Game definitions that pair a UI material with a localization key. Talent, buff and weapon templates
-- are left out on purpose: their icons are textures or shared placeholders, so names would mislead.
local NAME_SOURCES = {
    { module = "scripts/settings/mission/mission_types", collect = _collect_mission_types },
    { module = "scripts/settings/circumstance/circumstance_templates", collect = _collect_circumstances },
    { module = "scripts/settings/wallet_settings", collect = _collect_wallets },
    { module = "scripts/settings/difficulty/danger_settings", collect = _collect_danger_levels },
    { module = "scripts/settings/archetype/archetypes", collect = _collect_archetypes },
    { module = "scripts/settings/ui/ui_settings", collect = _collect_ui_settings },
    { module = "scripts/settings/item/crafting_settings", collect = _collect_recipes },
    { module = "scripts/settings/item/crafting_mechanicus_settings", collect = _collect_recipes },
}

--- Localizes a key only when the localization manager reports it as existing.
-- param: key candidate localization key
-- treturn: ?string the localized text, nil for a missing, invalid or unlocalized key
local function _localize_key(key)
    if type(key) ~= "string" or sub(key, 1, 4) ~= "loc_" then
        return nil
    end

    local managers = Managers
    local localization_manager = managers and managers.localization

    if not localization_manager or not localization_manager.exists then
        return nil
    end

    local ok, exists = pcall(localization_manager.exists, localization_manager, key)

    if not ok or not exists then
        return nil
    end

    local localized_ok, text = pcall(Localize, key)

    if localized_ok and type(text) == "string" and text ~= "" and sub(text, 1, 1) ~= "<" then
        return text
    end

    return nil
end

--- `_localize_key`, shared with the view for the item names in the inspector.
Assets.localize_key = _localize_key

--- Orders name candidates by `source.key`, so the chosen name does not depend on table order.
-- tab: a candidate
-- tab: b candidate
-- treturn: bool
local function _compare_candidates(a, b)
    return a.origin < b.origin
end

--- Resolves verified names once; safe to call repeatedly.
-- Collects every definition naming an indexed material, and every item that uses one as `hud_icon`
-- (from `attach_sources`, as source `master_items`), takes the first candidate in `source.key`
-- order whose key localizes, else the first candidate's humanized key, and rebuilds the named
-- assets' sort and search fields. A failing game module or collector only loses its own names.
-- Bumps `names_revision`, which tells the query module to rebuild its name-based orders.
-- tab: assets asset model built by `build`
-- treturn: int number of named assets, 0 when the names were resolved before
function Assets.resolve_names(assets)
    if assets.names_resolved then
        return 0
    end

    assets.names_resolved = true

    local by_path = assets.by_path
    local candidates = {}
    local add = function(material, loc_key, source, key)
        if type(material) ~= "string" then
            return
        end

        local path = gsub(material, "%.material$", "")

        if not by_path[path] then
            return
        end

        local list = candidates[path]

        if not list then
            list = {}
            candidates[path] = list
        end

        list[#list + 1] = {
            loc_key = loc_key,
            key = tostring(key),
            origin = source .. "." .. tostring(key),
        }
    end

    for i = 1, #NAME_SOURCES do
        local source = NAME_SOURCES[i]
        local ok, data = pcall(require, source.module)

        if ok and type(data) == "table" then
            pcall(source.collect, data, add)
        end
    end

    for path, asset in pairs(by_path) do
        local items = asset.item_refs

        if items then
            for i = 1, #items do
                local item_name = tostring(items[i][1])

                add(path, items[i][2], "master_items", match(item_name, "([^/]+)$") or item_name)
            end
        end
    end

    local named = 0

    for path, list in pairs(candidates) do
        local asset = by_path[path]

        sort(list, _compare_candidates)

        local localized_name, definition_name
        local chosen = list[1]

        for i = 1, #list do
            localized_name = _localize_key(list[i].loc_key)

            if localized_name then
                chosen = list[i]
                break
            end
        end

        if localized_name then
            asset.display_name = localized_name
            asset.name_source = Assets.NAME_SOURCE_LOCALIZED
            asset.name_key = chosen.loc_key
        else
            definition_name = _humanize(chosen.key)

            if definition_name ~= "" then
                asset.display_name = definition_name
                asset.name_source = Assets.NAME_SOURCE_DEFINITION
            end
        end

        asset.name_origin = chosen.origin
        asset.name_uses = #list - 1
        asset.sort_name = lower(asset.display_name)
        asset.search_blob = _search_blob(asset, localized_name, definition_name or _humanize(chosen.key))
        named = named + 1
    end

    assets.names_revision = assets.names_revision + 1

    return named
end

-- ----------------------------------------------------------------------------
-- Copy formats
-- ----------------------------------------------------------------------------

--- Returns the asset's path as a quoted Lua string, cached on the asset.
-- tab: asset asset record
-- treturn: string
function Assets.lua_string(asset)
    local text = asset.lua_string

    if not text then
        text = '"' .. asset.path .. '"'
        asset.lua_string = text
    end

    return text
end

--- Returns a texture pass snippet for the asset's material (`UI_SNIPPET_FORMAT`), cached on the
-- asset.
-- tab: asset asset record
-- treturn: string
function Assets.ui_snippet(asset)
    local text = asset.ui_snippet

    if not text then
        text = format(UI_SNIPPET_FORMAT, asset.path)
        asset.ui_snippet = text
    end

    return text
end

--- Lua keywords, which cannot be bare table keys.
local LUA_KEYWORDS = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true,
    ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true, ["return"] = true,
    ["then"] = true, ["true"] = true, ["until"] = true, ["while"] = true,
}

--- Returns one field of several assets, one per line, in the given order.
-- tab: list array of asset records
-- int: count number of assets in `list`
-- string: field `path` or `filename`
-- treturn: string
function Assets.field_lines(list, count, field)
    local lines = {}

    for i = 1, count do
        lines[i] = list[i][field]
    end

    return concat(lines, "\n", 1, count)
end

--- Returns the paths of several assets as a Lua array, in the given order.
-- tab: list array of asset records
-- int: count number of assets in `list`
-- treturn: string
function Assets.lua_array(list, count)
    local lines = { "{" }

    for i = 1, count do
        lines[i + 1] = '    "' .. list[i].path .. '",'
    end

    lines[count + 2] = "}"

    return concat(lines, "\n", 1, count + 2)
end

--- Returns the paths of several assets as a Lua table keyed by filename, in the given order. A
-- filename that occurs more than once in the list is keyed by its path below `content/ui/materials/`
-- instead, and keys that are not plain identifiers are written as `["key"]`.
-- tab: list array of asset records
-- int: count number of assets in `list`
-- treturn: string
function Assets.lua_table(list, count)
    local filename_counts = {}
    local lines = { "{" }

    for i = 1, count do
        local filename = list[i].filename

        filename_counts[filename] = (filename_counts[filename] or 0) + 1
    end

    for i = 1, count do
        local asset = list[i]
        local key = asset.filename

        if filename_counts[key] > 1 then
            key = asset.directory ~= "" and asset.directory .. "/" .. key or key
        end

        if not find(key, "^[%a_][%w_]*$") or LUA_KEYWORDS[key] then
            key = '["' .. key .. '"]'
        end

        lines[i + 1] = "    " .. key .. ' = "' .. asset.path .. '",'
    end

    lines[count + 2] = "}"

    return concat(lines, "\n", 1, count + 2)
end

return Assets
