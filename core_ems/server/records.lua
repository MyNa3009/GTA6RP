-- Medizinische Datenbank: jede Person suchen (Name oder permanente ID), Krankenakte, Versicherung, Eintraege schreiben.
-- Zugriff: Mediziner im Dienst mit Recht ems.records (Schreiben mit ems.records.note) oder Admins mit factions.view.
-- Korrigieren (Eintraege aendern oder als geloescht markieren, Versicherung setzen, Krankheiten setzen oder heilen):
-- Mediziner im Dienst mit ems.records.manage oder Admins mit Records.AdminPermission (factions.manage).
-- Jeder Blick in eine Akte und jede Aenderung wird geloggt und steht im Protokoll des Rettungsdiensts.

if EmsDisabled then
    return
end

local CFG = Config.Ems
local DEFS = CFG.Diseases
local VIEW_PERMISSION = 'factions.view'
local MANAGE_PERMISSION = CFG.Records.AdminPermission

-- Gibt { medic, admin, canNote, canManage, name } zurueck oder nil und einen Fehlercode
local function access(source)
    local medic = Ems.CanMedic(source, 'ems.records')
    if medic then
        -- Ein Admin, der selbst Mediziner ist, behaelt im Dienst seine Admin-Korrektur
        local manage = Ems.CanMedic(source, 'ems.records.manage') == true or Ems.Core('HasPermission', source, MANAGE_PERMISSION) == true
        return { medic = true, canNote = manage or Ems.CanMedic(source, 'ems.records.note') == true, canManage = manage, name = Ems.NameOf(source) }
    end
    if Ems.Core('HasPermission', source, MANAGE_PERMISSION) == true then
        return { admin = true, canNote = true, canManage = true, name = ('Admin %s'):format(Ems.NameOf(source) or '') }
    end
    if Ems.Core('HasPermission', source, VIEW_PERMISSION) == true then
        return { admin = true, canNote = false, canManage = false, name = ('Admin %s'):format(Ems.NameOf(source) or '') }
    end
    local _, err = Ems.CanMedic(source, 'ems.records')
    return nil, err
end

-- Eintrag im Protokoll (Bereich Datenbank)
local function protocol(source, rights, action, text, characterId)
    Ems.Protocol('datenbank', { action = action, text = text, actorSource = source, actorName = rights.name,
        admin = rights.admin or nil, target = characterId })
end

local function register(name, handler)
    Network.RegisterCallback(name, function(source, data)
        if not Ems.Ready or not Ems.CharacterOf(source) then
            return { ok = false, error = 'no_character' }
        end
        local rights, err = access(source)
        if not rights then
            return { ok = false, error = err }
        end
        local ok, result = pcall(handler, source, type(data) == 'table' and data or {}, rights)
        if not ok then
            Platform.Print('error', ('core_ems: Fehler in %s: %s'):format(name, tostring(result)))
            return { ok = false, error = 'server_error' }
        end
        return result
    end)
end

register('ems_records_open', function(source, data, rights)
    local diseases = {}
    for _, key in ipairs(CFG.DiseaseOrder) do
        local def = DEFS[key]
        diseases[#diseases + 1] = { disease = key, label = def.label, stages = def.cure == 'treatment' and def.stages - 1 or def.stages }
    end
    return { ok = true, data = { canNote = rights.canNote, canManage = rights.canManage, admin = rights.admin or nil,
        noteMax = CFG.Records.NoteMaxLength, insuranceMaxDays = CFG.Records.InsuranceMaxDays, diseases = diseases } }
end)

register('ems_records_search', function(source, data)
    local text = Ems.Text(data.text, 50) or ''
    local rows = Ems.Core('SearchCharacters', text, CFG.Records.SearchLimit) or {}
    local ids, list = {}, {}
    for _, row in ipairs(rows) do
        ids[#ids + 1] = row.characterId
    end
    local insured, sick = {}, {}
    if #ids > 0 then
        local marks = ('?,'):rep(#ids):sub(1, -2)
        for _, row in ipairs(DB.Query(("SELECT character_id, DATE_FORMAT(valid_until, '%%Y-%%m-%%d') AS valid_until FROM ems_insurance WHERE character_id IN (%s) AND valid_until > NOW()"):format(marks), ids) or {}) do
            insured[row.character_id] = row.valid_until
        end
        for _, row in ipairs(DB.Query(('SELECT character_id, COUNT(*) AS n FROM ems_diseases WHERE character_id IN (%s) AND cured_at IS NULL GROUP BY character_id'):format(marks), ids) or {}) do
            sick[row.character_id] = tonumber(row.n)
        end
    end
    for _, row in ipairs(rows) do
        list[#list + 1] = {
            characterId = row.characterId,
            name = ('%s %s'):format(row.firstname, row.lastname),
            dateOfBirth = row.dateOfBirth,
            insuredUntil = insured[row.characterId],
            diseases = sick[row.characterId] or 0,
        }
    end
    return { ok = true, data = { results = list } }
end)

-- withDeleted: als geloescht markierte Eintraege mitschicken (nur wer korrigieren darf)
local function recordOf(characterId, withDeleted)
    local person = Ems.Core('GetCharacterRecord', characterId)
    if type(person) ~= 'table' then
        return nil
    end
    local insurance = DB.Single("SELECT DATE_FORMAT(valid_until, '%Y-%m-%d') AS valid_until, valid_until > NOW() AS valid, sold_by FROM ems_insurance WHERE character_id = ?", { characterId })
    local diseases = {}
    for _, entry in ipairs(Diseases.Active(characterId)) do
        local def = DEFS[entry.disease]
        diseases[#diseases + 1] = {
            disease = entry.disease,
            label = def.label,
            stage = entry.stage,
            stages = def.cure == 'treatment' and def.stages - 1 or def.stages,
            cure = def.cure,
            series = entry.series,
            needed = Diseases.Needed(def, entry.stage),
        }
    end
    local history = {}
    local sql = "SELECT id, kind, text, actor_name, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at, edited_by, DATE_FORMAT(edited_at, '%Y-%m-%d %H:%i') AS edited_at, deleted_by FROM ems_records WHERE character_id = ?"
        .. (withDeleted and '' or ' AND deleted_at IS NULL') .. ' ORDER BY id DESC LIMIT ?'
    for _, row in ipairs(DB.Query(sql, { characterId, CFG.Records.HistoryLimit }) or {}) do
        history[#history + 1] = { id = row.id, kind = row.kind, text = row.text, by = row.actor_name, at = row.at,
            editedBy = row.edited_by, editedAt = row.edited_at, deletedBy = row.deleted_by }
    end
    return {
        characterId = characterId,
        name = ('%s %s'):format(person.firstname, person.lastname),
        dateOfBirth = person.dateOfBirth,
        gender = person.gender,
        insurance = insurance and { validUntil = insurance.valid_until, valid = insurance.valid == 1 or insurance.valid == true, soldBy = insurance.sold_by } or nil,
        diseases = diseases,
        history = history,
    }
end

register('ems_records_get', function(source, data, rights)
    local characterId = tonumber(data.characterId)
    local record = characterId and recordOf(math.floor(characterId), rights.canManage)
    if not record then
        return { ok = false, error = 'not_found' }
    end
    Ems.Log({ actor_account_id = Ems.Core('GetAccountId', source), character_id = record.characterId, action = 'records_view',
        data = { admin = rights.admin or nil } })
    protocol(source, rights, 'records_view', 'Akte angesehen', record.characterId)
    return { ok = true, data = record }
end)

register('ems_records_note', function(source, data, rights)
    if not rights.canNote then
        return { ok = false, error = 'no_permission' }
    end
    local characterId = tonumber(data.characterId)
    local text = Ems.Text(data.text, CFG.Records.NoteMaxLength)
    if not characterId or not text then
        return { ok = false, error = 'invalid_input' }
    end
    local record = recordOf(math.floor(characterId))
    if not record then
        return { ok = false, error = 'not_found' }
    end
    Ems.Record(record.characterId, 'note', text, rights.name)
    Ems.Log({ actor_account_id = Ems.Core('GetAccountId', source), character_id = record.characterId, action = 'records_note', data = { text = text } })
    protocol(source, rights, 'records_note', ('Eintrag geschrieben: %s'):format(text), record.characterId)
    return { ok = true, data = recordOf(record.characterId, rights.canManage) }
end)

------------------------------------------------------------------------
-- Korrigieren (ems.records.manage oder Admin)
------------------------------------------------------------------------

local function manage(name, handler)
    register(name, function(source, data, rights)
        if not rights.canManage then
            return { ok = false, error = 'no_permission' }
        end
        return handler(source, data, rights)
    end)
end

local function shorten(text, length)
    return utf8.len(text) > length and (text:sub(1, utf8.offset(text, length + 1) - 1) .. '…') or text
end

local PROTOCOL_QUOTE = 80

-- Eintrag aendern { id, text } oder als geloescht markieren { id, delete = true } oder wiederherstellen { id, restore = true }
manage('ems_records_entry', function(source, data, rights)
    local id = tonumber(data.id)
    local row = id and DB.Single('SELECT id, character_id, kind, text, deleted_at IS NOT NULL AS deleted FROM ems_records WHERE id = ?', { math.floor(id) })
    if not row then
        return { ok = false, error = 'not_found' }
    end
    local deleted = row.deleted == 1 or row.deleted == true
    local action, text
    if data.delete == true then
        if deleted then
            return { ok = false, error = 'not_found' }
        end
        DB.Update('UPDATE ems_records SET deleted_at = CURRENT_TIMESTAMP, deleted_by = ? WHERE id = ?', { rights.name, row.id })
        action, text = 'records_delete', ('Eintrag gelöscht: %s'):format(shorten(row.text, PROTOCOL_QUOTE))
    elseif data.restore == true then
        if not deleted then
            return { ok = false, error = 'not_found' }
        end
        DB.Update('UPDATE ems_records SET deleted_at = NULL, deleted_by = NULL WHERE id = ?', { row.id })
        action, text = 'records_restore', ('Eintrag wiederhergestellt: %s'):format(shorten(row.text, PROTOCOL_QUOTE))
    else
        local newText = Ems.Text(data.text, CFG.Records.NoteMaxLength)
        if not newText or deleted then
            return { ok = false, error = 'invalid_input' }
        end
        if newText == row.text then
            return { ok = true, data = recordOf(row.character_id, true) }
        end
        DB.Update('UPDATE ems_records SET text = ?, edited_at = CURRENT_TIMESTAMP, edited_by = ? WHERE id = ?', { newText, rights.name, row.id })
        action, text = 'records_edit', ('Eintrag geändert: %s (vorher: %s)'):format(shorten(newText, PROTOCOL_QUOTE), shorten(row.text, PROTOCOL_QUOTE))
    end
    Ems.Log({ actor_account_id = Ems.Core('GetAccountId', source), character_id = row.character_id, action = action,
        data = { id = row.id, before = row.text, after = data.text, admin = rights.admin or nil } })
    protocol(source, rights, action, text, row.character_id)
    return { ok = true, data = recordOf(row.character_id, true) }
end)

-- Versicherung setzen { characterId, days } (ab heute) oder beenden { characterId, days = 0 }
manage('ems_records_insurance', function(source, data, rights)
    local characterId = tonumber(data.characterId)
    local days = tonumber(data.days)
    local record = characterId and recordOf(math.floor(characterId))
    if not record then
        return { ok = false, error = 'not_found' }
    end
    if not days or days ~= math.floor(days) or days < 0 or days > CFG.Records.InsuranceMaxDays then
        return { ok = false, error = 'invalid_input' }
    end
    local text
    if days == 0 then
        if DB.Update('UPDATE ems_insurance SET valid_until = NOW() WHERE character_id = ? AND valid_until > NOW()', { record.characterId }) ~= 1 then
            return { ok = false, error = 'not_insured' }
        end
        text = 'Krankenversicherung beendet (Korrektur)'
    else
        DB.Update('INSERT INTO ems_insurance (character_id, valid_until, sold_by) VALUES (?, DATE_ADD(NOW(), INTERVAL ? DAY), ?) ON DUPLICATE KEY UPDATE valid_until = VALUES(valid_until), sold_by = VALUES(sold_by), sold_at = CURRENT_TIMESTAMP',
            { record.characterId, days, rights.name })
        text = ('Krankenversicherung bis %s gesetzt (Korrektur)'):format(Ems.InsuredUntil(record.characterId) or '?')
    end
    Ems.Record(record.characterId, 'insurance', text, rights.name)
    Ems.Log({ actor_account_id = Ems.Core('GetAccountId', source), character_id = record.characterId, action = 'records_insurance',
        data = { days = days, admin = rights.admin or nil } })
    protocol(source, rights, 'records_insurance', text, record.characterId)
    return { ok = true, data = recordOf(record.characterId, true) }
end)

-- Krankheit setzen { characterId, disease, stage } oder heilen { characterId, disease, stage = 0 }
manage('ems_records_disease', function(source, data, rights)
    local characterId = tonumber(data.characterId)
    local record = characterId and recordOf(math.floor(characterId))
    local def = DEFS[data.disease]
    if not record then
        return { ok = false, error = 'not_found' }
    end
    local stage = tonumber(data.stage)
    if not def or not stage then
        return { ok = false, error = 'invalid_input' }
    end
    local text
    if stage == 0 then
        local ok, err = Diseases.Cure(record.characterId, data.disease, rights.name, 'Korrektur')
        if not ok then
            return { ok = false, error = err }
        end
        text = ('%s geheilt (Korrektur)'):format(def.label)
    else
        local entry, err = Diseases.SetStage(record.characterId, data.disease, stage, rights.name)
        if not entry then
            return { ok = false, error = err }
        end
        text = ('%s auf Stadium %d gesetzt (Korrektur)'):format(def.label, entry.stage)
    end
    Ems.Log({ actor_account_id = Ems.Core('GetAccountId', source), character_id = record.characterId, action = 'records_disease',
        data = { disease = data.disease, stage = stage, admin = rights.admin or nil } })
    protocol(source, rights, 'records_disease', text, record.characterId)
    return { ok = true, data = recordOf(record.characterId, true) }
end)
