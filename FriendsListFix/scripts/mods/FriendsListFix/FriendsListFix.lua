--- DMF entry script of Friends List Fix; shows each friend once in the Social menu's Friends tab.
-- DMF runs this file as the `mod_script` named in `FriendsListFix.mod`; `FriendsListFix_data.lua`
-- and `FriendsListFix_localization.lua` are loaded by DMF from the same declaration.
--
-- Since Darktide 1.13.0, `SocialService.fetch_friends` merges the Fatshark friends list with the
-- platform (Steam/Xbox/PSN) friends list but only skips an entry that is the same PlayerInfo
-- object. A player who is both an in-game friend and a platform friend can be two PlayerInfo
-- objects, one found by account id and one by platform user id, so the Friends tab lists them
-- twice. Up to 1.12.5 the merge also matched account ids and platform user ids, and kept the
-- Fatshark entry.
--
-- A `hook` on `SocialMenuRosterView._prepare_list` picks one entry per person for the Friends tab
-- only, before vanilla copies, sorts and groups the list. The social service's friends list is
-- never changed. This is a defensive workaround: remove the mod once Fatshark fixes the merge.
-- module: FriendsListFix
-- author: LucLeto
local mod = get_mod("FriendsListFix")
local SocialConstants = require("scripts/managers/data_service/services/social/social_constants")

local FRIENDS_LIST = 1

local table_clear = table.clear

-- ----------------------------------------------------------------------------
-- Work tables
-- ----------------------------------------------------------------------------

-- Built once at load and reused by every refresh, so deduplicating allocates no tables. The row
-- arrays are only read up to the current row count, so they are overwritten instead of cleared.
local _rows = {}
local _row_accounts = {}
local _row_platforms = {}
local _row_platform_ids = {}
local _selected_rows = {}
local _slots_by_account = {}
local _accounts_by_platform_id = {}
local _slots_by_platform_id = {}
local _platform_names = {}
local _num_platforms = 0
local _result = {}
local _num_result = 0

-- One lookup per known platform replaces a "platform:id" key string per row. A platform without
-- an entry here (e.g. "Unknown") gives its rows no platform id.
for platform in pairs(SocialConstants.Platforms) do
    _num_platforms = _num_platforms + 1
    _platform_names[_num_platforms] = platform
    _accounts_by_platform_id[platform] = {}
    _slots_by_platform_id[platform] = {}
end

--- Empties the lookups filled by the previous call.
local function clear_lookups()
    table_clear(_slots_by_account)

    for i = 1, _num_platforms do
        local platform = _platform_names[i]

        table_clear(_accounts_by_platform_id[platform])
        table_clear(_slots_by_platform_id[platform])
    end
end

-- ----------------------------------------------------------------------------
-- Deduplication
-- ----------------------------------------------------------------------------

--- Returns whether `id` is a usable account id or platform user id.
-- ?string: id account id or platform user id, may be false or nil
-- return: bool
local function has_id(id)
    return type(id) == "string" and id ~= ""
end

--- Returns whether row `row` should replace row `current` as the entry shown for one person.
-- A row with its own account id (the Fatshark entry) beats a platform-only row, as vanilla did up
-- to 1.12.5, because the roster's popup actions need the account id. Then the better Friends
-- group wins, then a row with a platform id, then the earlier row.
-- int: row candidate row index
-- int: current row index that holds the slot
-- func: group_for roster group selection function, a lower group is listed first
-- return: bool
local function prefer_row(row, current, group_for)
    local row_has_account = _row_accounts[row] ~= false

    if row_has_account ~= (_row_accounts[current] ~= false) then
        return row_has_account
    end

    local row_group = group_for(_rows[row])
    local current_group = group_for(_rows[current])

    if row_group ~= current_group then
        return row_group < current_group
    end

    return _row_platform_ids[row] ~= false and _row_platform_ids[current] == false
end

--- Returns the friends list with one entry per person.
-- Rows with the same account id are one person. A row without an account id joins the account
-- that uses its platform user id, unless two accounts use that platform user id. Rows that the
-- roster would hide because of cross-play settings are left out. Returns `friends` itself when
-- nothing was merged, else a reused array that is valid until the next call. `friends` is not
-- changed.
-- tab: friends array of PlayerInfo
-- int: num_friends number of entries in `friends`
-- tab: presence_myself own presence entry
-- func: group_for roster group selection function
-- return: tab
local function deduplicate_friends(friends, num_friends, presence_myself, group_for)
    local my_platform = presence_myself:platform()
    local my_cross_play_disabled = presence_myself:cross_play_disabled()
    local rows = _rows
    local row_accounts = _row_accounts
    local row_platforms = _row_platforms
    local row_platform_ids = _row_platform_ids
    local accounts_by_platform_id = _accounts_by_platform_id
    local num_rows = 0

    clear_lookups()

    for i = 1, num_friends do
        local player_info = friends[i]
        local platform = player_info:platform()

        -- Match the roster's eligibility check before choosing a representative.
        if my_platform == platform or not (my_cross_play_disabled or player_info:cross_play_disabled()) then
            local account_id = player_info:account_id()
            local platform_id = player_info:platform_user_id()
            local accounts_by_id = accounts_by_platform_id[platform]

            if not has_id(account_id) then
                account_id = false
            end

            if not (accounts_by_id and has_id(platform_id)) then
                platform_id = false
            end

            num_rows = num_rows + 1
            rows[num_rows] = player_info
            row_accounts[num_rows] = account_id
            row_platforms[num_rows] = platform_id and platform
            row_platform_ids[num_rows] = platform_id

            if account_id and platform_id then
                local mapped_account = accounts_by_id[platform_id]

                -- A platform id shared by different accounts cannot identify an account-less row.
                if mapped_account == nil then
                    accounts_by_id[platform_id] = account_id
                elseif mapped_account ~= account_id then
                    accounts_by_id[platform_id] = false
                end
            end
        end
    end

    local selected_rows = _selected_rows
    local slots_by_account = _slots_by_account
    local slots_by_platform_id = _slots_by_platform_id
    local num_selected = 0

    for row = 1, num_rows do
        local platform_id = row_platform_ids[row]
        local platform = row_platforms[row]
        local mapped_account = platform_id and accounts_by_platform_id[platform][platform_id]
        local account_id = row_accounts[row] or mapped_account
        local slots, key

        if account_id then
            slots = slots_by_account
            key = account_id
        elseif platform_id and mapped_account ~= false then
            slots = slots_by_platform_id[platform]
            key = platform_id
        end

        -- A row with neither key is its own person; vanilla never lists one PlayerInfo twice.
        local slot = slots and slots[key]

        if not slot then
            num_selected = num_selected + 1
            selected_rows[num_selected] = row

            if slots then
                slots[key] = num_selected
            end
        elseif prefer_row(row, selected_rows[slot], group_for) then
            selected_rows[slot] = row
        end
    end

    if num_selected == num_rows then
        return friends
    end

    local result = _result

    for i = 1, num_selected do
        result[i] = rows[selected_rows[i]]
    end

    for i = num_selected + 1, _num_result do
        result[i] = nil
    end

    _num_result = num_selected

    return result
end

-- ----------------------------------------------------------------------------
-- Hooks
-- ----------------------------------------------------------------------------

-- Vanilla only reads `new_list_items` while copying it into `roster_list`, so the reused result
-- array of `deduplicate_friends` is safe to pass on.
mod:hook("SocialMenuRosterView", "_prepare_list", function(func, self, roster_list_data, roster_list, new_list_items, list_index, ...)
    if list_index == FRIENDS_LIST and type(new_list_items) == "table" then
        local num_items = #new_list_items

        if num_items > 1 then
            new_list_items = deduplicate_friends(new_list_items, num_items, Managers.presence:presence_entry_myself(), roster_list_data.group_select_function)
        end
    end

    return func(self, roster_list_data, roster_list, new_list_items, list_index, ...)
end)
