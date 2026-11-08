-- Mitglieder: einstellen, Rang aendern, entlassen (mit Eintrag im Archiv) und die Felder der Leitstelle.
-- Hier wird nur ausgefuehrt. Ob jemand das darf, pruefen menu.lua und commands.lua vorher.
-- actor: { source, characterId, name, accountId } oder fuer Admins zusaetzlich admin = true.

if FactionsDisabled then
    return
end

Members = {}

local CFG = Config.Factions
local INVENTORY = 'core_inventory'
local DN_TRIES = 50

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function leaderName(faction)
    local org = Orgs[faction]
    local row = DB.Single('SELECT name FROM faction_members WHERE faction = ? AND `rank` >= ? ORDER BY `rank` DESC, hired_at LIMIT 1',
        { faction, org.leaderRank })
    return row and row.name or nil
end
Members.LeaderName = leaderName

local function history(faction, characterId, action, rankFrom, rankTo, actor)
    DB.Insert('INSERT INTO faction_history (faction, character_id, action, rank_from, rank_to, rank_name, leader_name, actor_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        DB.Args(faction, characterId, action, rankFrom, rankTo, rankTo and Factions.RankName(faction, rankTo) or nil,
            leaderName(faction), actor and actor.name or nil))
end

local function log(actor, action, characterId, data)
    Factions.Log({
        actor_account_id = actor and actor.accountId or nil,
        character_id = characterId,
        action = action,
        data = data,
    })
end

-- Naechste freie Dienstnummer, z. B. EMS-007
local function nextDn(faction)
    local org = Orgs[faction]
    for _ = 1, DN_TRIES do
        local number = tonumber(DB.Scalar('SELECT next_dn FROM faction_settings WHERE faction = ?', { faction })) or 1
        if DB.Update('UPDATE faction_settings SET next_dn = ? WHERE faction = ? AND next_dn = ?', { number + 1, faction, number }) == 1 then
            local dn = ('%s%03d'):format(org.dnPrefix, number)
            if not DB.Scalar('SELECT 1 FROM faction_members WHERE faction = ? AND dn = ?', { faction, dn }) then
                return dn
            end
        end
    end
    return nil
end

-- Dienstausweis im Inventar ausstellen oder aendern (Orga, Dienstgrad, Dienstnummer)
local function issueCard(faction, characterId, rank, dn, actor)
    if not Platform.IsResourceStarted(INVENTORY) then
        return
    end
    local org = Orgs[faction]
    Platform.CallExport(INVENTORY, 'IssueServiceCard', characterId,
        { org = org.short, label = org.label, rank = Factions.RankName(faction, rank), number = dn }, actor and actor.accountId or nil)
end

local function revokeCard(characterId, reason, actor)
    if Platform.IsResourceStarted(INVENTORY) then
        Platform.CallExport(INVENTORY, 'RevokeServiceCard', characterId, reason, actor and actor.accountId or nil)
    end
end

local function nameOf(characterId)
    local source = Factions.SourceOf(characterId)
    if source then
        return Factions.NameOf(source)
    end
    local record = Factions.Core('GetCharacterRecord', characterId)
    return type(record) == 'table' and ('%s %s'):format(record.firstname, record.lastname) or nil
end

------------------------------------------------------------------------
-- Abteilungen und Pruefungen
------------------------------------------------------------------------

function Members.Departments(faction, includeDeleted)
    local rows = DB.Query('SELECT id, name, ranks, deleted_at IS NOT NULL AS deleted FROM faction_departments WHERE faction = ? ORDER BY id', { faction }) or {}
    local list = {}
    for _, row in ipairs(rows) do
        if includeDeleted or row.deleted == 0 or row.deleted == false then
            list[#list + 1] = { id = row.id, name = row.name, ranks = Factions.Decode(row.ranks, {}) }
        end
    end
    return list
end

function Members.Exams(faction, includeDeleted)
    local rows = DB.Query('SELECT id, name, description, deleted_at IS NOT NULL AS deleted FROM faction_exams WHERE faction = ? ORDER BY id', { faction }) or {}
    local list = {}
    for _, row in ipairs(rows) do
        if includeDeleted or row.deleted == 0 or row.deleted == false then
            list[#list + 1] = { id = row.id, name = row.name, description = row.description }
        end
    end
    return list
end

-- Divisionen (Ranggruppen), hoechste zuerst: { id, name, minRank, maxRank }
function Members.Divisions(faction)
    local list = {}
    for _, row in ipairs(DB.Query('SELECT id, name, min_rank, max_rank FROM faction_divisions WHERE faction = ? ORDER BY max_rank DESC, id', { faction }) or {}) do
        list[#list + 1] = { id = row.id, name = row.name, minRank = row.min_rank, maxRank = row.max_rank }
    end
    return list
end

-- Division eines Rangs oder nil
function Members.DivisionOf(divisions, rank)
    for _, division in ipairs(divisions) do
        if rank >= division.minRank and rank <= division.maxRank then
            return division
        end
    end
    return nil
end

-- Mitglieder pro Rang: { [rang] = anzahl } und die Gesamtzahl
function Members.CountByRank(faction)
    local counts, total = {}, 0
    for _, row in ipairs(DB.Query('SELECT `rank`, COUNT(*) AS n FROM faction_members WHERE faction = ? GROUP BY `rank`', { faction }) or {}) do
        counts[row.rank] = tonumber(row.n) or 0
        total = total + (tonumber(row.n) or 0)
    end
    return counts, total
end

-- Letzter Uprank je Mitglied: { [permanente ID] = 'JJJJ-MM-TT' }
function Members.LastPromotions(faction)
    local map = {}
    for _, row in ipairs(DB.Query("SELECT character_id, DATE_FORMAT(MAX(created_at), '%Y-%m-%d') AS at FROM faction_history WHERE faction = ? AND action = 'rank' AND rank_to > rank_from GROUP BY character_id", { faction }) or {}) do
        map[row.character_id] = row.at
    end
    return map
end

-- Nur Upranks seit der aktuellen Einstellung zaehlen (nicht aus einer frueheren Mitgliedschaft)
function Members.PromotedSinceHire(promotedAt, hiredAt)
    if not promotedAt or (hiredAt and promotedAt < hiredAt) then
        return nil
    end
    return promotedAt
end

-- Erklaerungen: Abschnitte der Leitung { id, category, title, body, sort, updatedBy, updatedAt }
function Members.Info(faction)
    local list = {}
    for _, row in ipairs(DB.Query("SELECT id, category, title, body, sort, updated_by, DATE_FORMAT(updated_at, '%Y-%m-%d') AS updated_at FROM faction_info WHERE faction = ? ORDER BY category, sort, id", { faction }) or {}) do
        list[#list + 1] = { id = row.id, category = row.category, title = row.title, body = row.body, sort = row.sort,
            updatedBy = row.updated_by, updatedAt = row.updated_at }
    end
    return list
end

local function byId(list)
    local map = {}
    for _, entry in ipairs(list) do
        map[entry.id] = entry
    end
    return map
end
Members.ById = byId

------------------------------------------------------------------------
-- Einstellen, Rang, Entlassen
------------------------------------------------------------------------

function Members.Hire(faction, characterId, rank, actor)
    local org = Orgs[faction]
    characterId = tonumber(characterId)
    if not org or not characterId then
        return false, 'invalid_input'
    end
    rank = Factions.Int(rank or 1, 1, org.ranks)
    if not rank then
        return false, 'invalid_rank'
    end
    if Factions.GetMember(characterId) then
        return false, 'already_member'
    end
    local name = nameOf(characterId)
    if not name then
        return false, 'unknown_character'
    end
    local dn = nextDn(faction)
    local inserted = DB.Update('INSERT IGNORE INTO faction_members (character_id, faction, `rank`, name, dn, departments, exams, hired_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        DB.Args(characterId, faction, rank, name, dn, '[]', '[]', actor and actor.characterId or nil))
    if inserted ~= 1 then
        return false, 'already_member'
    end
    history(faction, characterId, 'hire', nil, rank, actor)
    log(actor, 'hire', characterId, { faction = faction, rank = rank, dn = dn, admin = actor and actor.admin or nil })
    issueCard(faction, characterId, rank, dn, actor)
    Factions.Refresh(characterId)
    return true
end

function Members.SetRank(faction, characterId, rank, actor)
    local org = Orgs[faction]
    local member = Factions.GetMember(characterId)
    if not org or not member or member.faction ~= faction then
        return false, 'not_member'
    end
    rank = Factions.Int(rank, 1, org.ranks)
    if not rank then
        return false, 'invalid_rank'
    end
    if rank == member.rank then
        return true
    end
    DB.Update('UPDATE faction_members SET `rank` = ? WHERE character_id = ?', { rank, member.characterId })
    history(faction, member.characterId, 'rank', member.rank, rank, actor)
    log(actor, 'rank', member.characterId, { faction = faction, from = member.rank, to = rank, admin = actor and actor.admin or nil })
    issueCard(faction, member.characterId, rank, member.dn, actor)
    Factions.Refresh(member.characterId)
    return true
end

-- Raenge seit der letzten Einstellung, mit dem Leader zu der Zeit (fuer das Archiv)
local function rankHistory(faction, characterId)
    local rows = DB.Query("SELECT action, rank_to, rank_name, leader_name, DATE_FORMAT(created_at, '%Y-%m-%d') AS at FROM faction_history WHERE faction = ? AND character_id = ? ORDER BY id",
        { faction, characterId }) or {}
    local list = {}
    for _, row in ipairs(rows) do
        if row.action == 'hire' then
            list = {}
        end
        if (row.action == 'hire' or row.action == 'rank') and row.rank_to then
            list[#list + 1] = { rank = row.rank_to, name = row.rank_name, at = row.at, leader = row.leader_name }
        end
    end
    return list
end

-- kind: 'fire' (entlassen), 'leave' (selbst gekuendigt), 'admin' (vom Admin entfernt)
function Members.Remove(faction, characterId, kind, reason, actor)
    local member = Factions.GetMember(characterId)
    if not member or member.faction ~= faction then
        return false, 'not_member'
    end
    reason = Factions.Text(reason, CFG.TextMax.reason)
    local exams = {}
    local examNames = byId(Members.Exams(faction, true))
    for _, entry in ipairs(member.exams) do
        local exam = examNames[entry.id]
        exams[#exams + 1] = { name = exam and exam.name or ('Prüfung %s'):format(tostring(entry.id)), at = entry.at, by = entry.by }
    end
    local archived = DB.Insert('INSERT INTO faction_archive (faction, character_id, name, dn, last_rank, ranks, exams, hired_at, left_reason, left_by, kind) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        DB.Args(faction, member.characterId, member.name, member.dn, Factions.RankName(faction, member.rank),
            Factions.Encode(rankHistory(faction, member.characterId)), Factions.Encode(exams), member.hiredAt,
            reason, actor and actor.name or nil, kind))
    if not archived then
        return false, 'db_error'
    end
    DB.Update('DELETE FROM faction_members WHERE character_id = ?', { member.characterId })
    history(faction, member.characterId, kind == 'leave' and 'leave' or 'fire', member.rank, nil, actor)
    log(actor, kind == 'leave' and 'leave' or 'fire', member.characterId, { faction = faction, rank = member.rank, reason = reason, kind = kind })
    revokeCard(member.characterId, kind == 'leave' and 'Gekündigt' or (reason or 'Entlassen'), actor)
    local source = Factions.SourceOf(member.characterId)
    if source and Factions.IsOnDuty(source) then
        Factions.SetDuty(source, false, 'removed')
    end
    Factions.Refresh(member.characterId)
    return true
end

------------------------------------------------------------------------
-- Felder der Leitstelle
------------------------------------------------------------------------

-- field: 'dn' | 'strikes' | 'vacation' | 'departments' | 'exams'. value ist schon geprueft.
function Members.SetField(faction, characterId, field, value, actor)
    local member = Factions.GetMember(characterId)
    if not member or member.faction ~= faction then
        return false, 'not_member'
    end
    local column, stored
    if field == 'dn' then
        if value and DB.Scalar('SELECT 1 FROM faction_members WHERE faction = ? AND dn = ? AND character_id <> ?', { faction, value, member.characterId }) then
            return false, 'dn_taken'
        end
        column, stored = 'dn', value
    elseif field == 'strikes' then
        column, stored = 'strikes', value
    elseif field == 'vacation' then
        column, stored = 'vacation_days', value
    elseif field == 'departments' then
        column, stored = 'departments', Factions.Encode(value)
    elseif field == 'exams' then
        column, stored = 'exams', Factions.Encode(value)
    else
        return false, 'invalid_field'
    end
    if DB.Update(('UPDATE faction_members SET %s = ? WHERE character_id = ?'):format(column), DB.Args(stored, member.characterId)) == nil then
        return false, 'db_error'
    end
    log(actor, 'member_' .. field, member.characterId, { faction = faction, value = value })
    if field == 'dn' then
        issueCard(faction, member.characterId, member.rank, value, actor)
    end
    Factions.Refresh(member.characterId)
    return true
end

-- Leitstelle: alle Mitglieder einer Organisation, hoechster Rang zuerst
function Members.List(faction)
    local rows = DB.Query('SELECT ' .. Factions.MemberColumns .. ' FROM faction_members WHERE faction = ? ORDER BY `rank` DESC, name', { faction }) or {}
    local list = {}
    for _, row in ipairs(rows) do
        list[#list + 1] = Factions.DecodeMember(row)
    end
    return list
end
