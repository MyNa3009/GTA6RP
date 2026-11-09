-- Protokolle: jede Aenderung in einer Organisation mit wer, an wem und was, lesbar pro permanenter ID
-- (Organisationsmenue, Tab Protokolle, Recht logs.view). Leitstelle, Anpassung, Kasse, Dienst und Garage schreiben
-- hier rein, andere Scripts ueber exports.core_factions:AddProtocol (z. B. core_ems: Hochholen, Datenbank).
-- Eintraege werden nie geaendert oder geloescht. Das zentrale Log der Core bekommt alles zusaetzlich.

if FactionsDisabled then
    return
end

Protocol = {}

local CFG = Config.Factions.Protocol
local TEXT_MAX = 500
local NAME_MAX = 101
local ACTION_MAX = 32

local AREAS = {}
for _, area in ipairs(CFG.Areas) do
    AREAS[area.key] = area.label
end
Protocol.Areas = AREAS

-- Name zu einer permanenten ID: online aus dem Speicher, sonst aus der Akte der Core
function Protocol.NameOf(characterId)
    characterId = tonumber(characterId)
    if not characterId then
        return nil
    end
    local source = Factions.SourceOf(characterId)
    local member = source and Factions.MemberOf(source)
    if member then
        return member.name
    end
    if source then
        local name = Factions.NameOf(source)
        if name then
            return name
        end
    end
    local record = Factions.Core('GetCharacterRecord', characterId)
    return type(record) == 'table' and ('%s %s'):format(record.firstname, record.lastname) or nil
end

-- Eintrag schreiben. entry:
--   area      'leitstelle' | 'einsatz' | 'datenbank' | 'kasse' | 'dienst' | 'anpassung'
--   action    kurzer Code (z. B. 'rank', 'revive')
--   text      was passiert ist, auf Deutsch (max. 500 Zeichen)
--   actor     { source, characterId, name, admin } aus menu.lua oder nur actorSource / actorId
--   target    permanente ID der Person, die es betrifft (optional), targetName optional
-- Gibt true oder false und einen Fehlercode zurueck.
function Factions.Protocol(faction, entry)
    if not Orgs[faction] or type(entry) ~= 'table' or not AREAS[entry.area] then
        return false, 'invalid_input'
    end
    local text = Factions.Text(entry.text, TEXT_MAX)
    local action = Factions.Text(entry.action, ACTION_MAX)
    if not text or not action then
        return false, 'invalid_input'
    end
    local actor = type(entry.actor) == 'table' and entry.actor or {}
    local actorSource = tonumber(entry.actorSource or actor.source)
    local actorId = tonumber(entry.actorId or actor.characterId) or (actorSource and Factions.CharacterOf(actorSource))
    local actorName = Factions.Text(entry.actorName or actor.name, NAME_MAX)
    if not actorName and actorSource then
        local member = Factions.MemberOf(actorSource)
        actorName = member and member.name or Factions.NameOf(actorSource)
    end
    if not actorName and actorId then
        actorName = Protocol.NameOf(actorId)
    end
    local targetId = tonumber(entry.target)
    local targetName = Factions.Text(entry.targetName, NAME_MAX) or (targetId and Protocol.NameOf(targetId)) or nil
    local admin = (entry.admin or actor.admin) and 1 or 0
    local area = entry.area
    -- In einem eigenen Thread, damit der Aufrufer nicht auf die Datenbank wartet (auch beim Ausloggen)
    Platform.Async(function()
        DB.Insert('INSERT INTO faction_logs (faction, area, action, actor_id, actor_name, actor_admin, target_id, target_name, text) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            DB.Args(faction, area, action, actorId, actorName, admin, targetId, targetName, text))
    end)
    return true
end

-- Eine Seite Eintraege, neueste zuerst. filter: { characterId, role = 'all' | 'target' | 'actor', area, before }
-- Mit ID: Eintraege, die die Person betreffen und die sie selbst gemacht hat (zwei Abfragen ueber je einen Index).
function Protocol.Page(faction, filter)
    local limit = CFG.PageSize + 1
    local before = tonumber(filter.before)
    local area = AREAS[filter.area] and filter.area or nil
    local columns = "id, area, action, actor_id, actor_name, actor_admin, target_id, target_name, text, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at"

    local function part(where, params)
        local sql = ('SELECT %s FROM faction_logs WHERE faction = ?%s'):format(columns, where)
        local args = { faction }
        for _, value in ipairs(params) do
            args[#args + 1] = value
        end
        if area then
            sql = sql .. ' AND area = ?'
            args[#args + 1] = area
        end
        if before then
            sql = sql .. ' AND id < ?'
            args[#args + 1] = before
        end
        return sql .. ' ORDER BY id DESC LIMIT ' .. limit, args
    end

    local rows
    local characterId = tonumber(filter.characterId)
    if characterId then
        local role = filter.role
        local seen, merged = {}, {}
        local function collect(where)
            local sql, args = part(where, { characterId })
            for _, row in ipairs(DB.Query(sql, args) or {}) do
                if not seen[row.id] then
                    seen[row.id] = true
                    merged[#merged + 1] = row
                end
            end
        end
        if role ~= 'actor' then
            collect(' AND target_id = ?')
        end
        if role ~= 'target' then
            collect(' AND actor_id = ?')
        end
        table.sort(merged, function(a, b) return a.id > b.id end)
        rows = merged
    else
        local sql, args = part('', {})
        rows = DB.Query(sql, args) or {}
    end

    local list = {}
    for index = 1, math.min(#rows, CFG.PageSize) do
        local row = rows[index]
        list[#list + 1] = {
            id = row.id, area = row.area, action = row.action, text = row.text, at = row.at,
            actor = row.actor_id and { id = row.actor_id, name = row.actor_name } or (row.actor_name and { name = row.actor_name }) or nil,
            target = row.target_id and { id = row.target_id, name = row.target_name } or nil,
            admin = (row.actor_admin == 1 or row.actor_admin == true) or nil,
        }
    end
    return { entries = list, more = #rows > CFG.PageSize, next = #list > 0 and list[#list].id or nil }
end

-- Fuer andere Scripts: exports.core_factions:AddProtocol('ems', { area = 'einsatz', action = 'revive', text = 'Hochgeholt',
--   actorSource = source, target = permanenteId })
Platform.Export('AddProtocol', function(faction, entry)
    return (Factions.Protocol(faction, entry))
end)
