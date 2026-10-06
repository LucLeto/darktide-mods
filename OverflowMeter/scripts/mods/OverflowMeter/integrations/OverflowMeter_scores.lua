local mod = get_mod("OverflowMeter")
local Snapshot = mod._snapshot

local get_mod = get_mod
local pairs = pairs
local table_insert = table.insert
local table_remove = table.remove
local tostring = tostring

-- Scoreboard II was renamed to Scores (same Nexus mod, id 872) and its version numbering restarted
-- at 1.0. Both mod ids are looked up so either release works; the first one installed wins.
local HOST_MOD_NAMES = {
    "scores",
    "scoreboard-ii"
}

local KNOWN_GOOD_VERSIONS = {
    scores = {
        ["1.0"] = true
    },
    ["scoreboard-ii"] = {
        ["18.3"] = true
    }
}

local ANCHOR_ROWS = {
    "coherency_efficiency",
    "ammo_collected",
    "resources_collected"
}

local METRICS = Snapshot.METRICS
local METRIC_COUNT = Snapshot.METRIC_COUNT

local FIELDS = {}

local OUR_ROW_ORDER = {}

for i = 1, METRIC_COUNT do
    FIELDS[i] = METRICS[i].field
    OUR_ROW_ORDER[METRICS[i].row] = i
end

local Adapter = {
    name = "scores",
    active = false
}

local row_data = {}
local templates = {}

for i = 1, METRIC_COUNT do
    local metric = METRICS[i]

    row_data[metric.row] = {}

    templates[i] = {
        name = metric.row,
        text = metric.loc_short or metric.loc,
        validation = "ASC",
        iteration = "DIFF",
        data = row_data[metric.row]
    }
end

local sb_mod = nil
local hooks_installed = false
local ready = false
local promoted = {}

local function _template_index(list, name)
    for i = 1, #list do
        if list[i].name == name then
            return i
        end
    end
end

local function _ensure_rows(sb)
    local row_templates = sb.scoreboard_rows
    local registered = sb.registered_scoreboard_rows
    local index = sb.scoreboard_row_index

    if not row_templates or not registered or not index then
        return
    end

    local settings = mod._settings

    for i = 1, METRIC_COUNT do
        local metric = METRICS[i]
        local row_name = metric.row
        local template_index = _template_index(row_templates, row_name)
        local entry = index[row_name]

        if settings[metric.setting] then
            if not template_index then
                row_templates[#row_templates + 1] = templates[i]
            end

            if entry then
                entry.mod = mod
            else
                entry = sb:register_scoreboard_row(mod, templates[i])
                registered[#registered + 1] = entry
                index[row_name] = entry
            end
        else
            if template_index then
                table_remove(row_templates, template_index)
            end

            if entry then
                index[row_name] = nil

                for j = #registered, 1, -1 do
                    if registered[j].name == row_name then
                        table_remove(registered, j)

                        break
                    end
                end
            end
        end
    end
end

local function _row_position(rows, name)
    for i = 1, #rows do
        if rows[i].name == name then
            return i
        end
    end
end

local function _promote_rows(sorted)
    local rows = sorted and sorted[1]

    if not rows then
        return
    end

    local count = 0

    for i = #rows, 1, -1 do
        local row = rows[i]
        local position = OUR_ROW_ORDER[row.name]

        if position and row.visible == false then
            row.visible = nil
            count = count + 1
            promoted[position] = table_remove(rows, i)
        end
    end

    if count == 0 then
        return
    end

    local anchor = #rows

    for i = 1, #ANCHOR_ROWS do
        local position = _row_position(rows, ANCHOR_ROWS[i])

        if position then
            anchor = position

            break
        end
    end

    for i = 1, METRIC_COUNT do
        local row = promoted[i]

        if row then
            anchor = anchor + 1

            table_insert(rows, anchor, row)

            promoted[i] = nil
        end
    end
end

local function _find_host()
    for i = 1, #HOST_MOD_NAMES do
        local name = HOST_MOD_NAMES[i]
        local candidate = get_mod(name)

        if candidate and candidate.register_scoreboard_row and candidate.set_row_value and candidate.scoreboard_row_index then
            return candidate, name
        end
    end
end

Adapter.setup = function ()
    local sb, host_name = _find_host()

    if not sb then
        sb_mod = nil
        Adapter.active = false

        return
    end

    sb_mod = sb
    Adapter.active = true

    _ensure_rows(sb)

    if hooks_installed then
        return
    end

    hooks_installed = true

    mod:hook(sb, "collect_scoreboard_rows", function (func, self, loaded_rows)
        local entries = func(self, loaded_rows)

        if not loaded_rows then
            _ensure_rows(self)

            return entries
        end

        if entries then
            for i = 1, #entries do
                local entry = entries[i]

                if OUR_ROW_ORDER[entry.name] then
                    entry.mod = mod
                end
            end
        end

        return entries
    end)

    local version = tostring(sb.version)
    local known_versions = KNOWN_GOOD_VERSIONS[host_name]

    if not (known_versions and known_versions[version]) then
        mod:info("%s %s has not been verified; the rows are registered but stay hidden.", host_name, version)

        return
    end

    mod:hook(sb, "get_rows_in_groups", function (func, self, loaded_rows)
        Snapshot.flush()

        local sorted = func(self, loaded_rows)

        _promote_rows(sorted)

        return sorted
    end)
end

Adapter.refresh = function ()
    local sb = sb_mod

    if not sb then
        return
    end

    _ensure_rows(sb)
end

Adapter.prepare = function ()
    ready = sb_mod ~= nil
end

Adapter.publish = function (entry)
    local sb = sb_mod

    if not ready then
        return
    end

    local settings = mod._settings
    local account_id = entry.account_id

    for i = 1, METRIC_COUNT do
        local metric = METRICS[i]

        if settings[metric.setting] then
            sb:set_row_value(metric.row, account_id, entry[FIELDS[i]])
        end
    end
end

Adapter.reset = function ()
    ready = false

    for _, data in pairs(row_data) do
        for account_id in pairs(data) do
            data[account_id] = nil
        end
    end
end

Snapshot.register_adapter(Adapter)

return Adapter
