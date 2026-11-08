-- Medizinische Datenbank: jede Person suchen (Name oder permanente ID), Krankenakte, Versicherung, Eintraege schreiben.
-- Zugriff: Mediziner im Dienst mit Recht ems.records (Schreiben mit ems.records.note) oder Admins mit factions.view.
-- Jeder Blick in eine Akte wird geloggt, weil es um Gesundheitsdaten geht.

if EmsDisabled then
    return
end

local CFG = Config.Ems
local DEFS = CFG.Diseases
local ADMIN_PERMISSION = 'factions.view'

-- Gibt { medic, admin, canNote } zurueck oder nil und einen Fehlercode
local function access(source)
    local medic = Ems.CanMedic(source, 'ems.records')
    if medic then
        return { medic = true, canNote = Ems.CanMedic(source, 'ems.records.note') == true }
    end
    if Ems.Core('HasPermission', source, ADMIN_PERMISSION) == true then
        return { admin = true, canNote = false }
    end
    local _, err = Ems.CanMedic(source, 'ems.records')
    return nil, err
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
    return { ok = true, data = { canNote = rights.canNote, admin = rights.admin or nil, noteMax = CFG.Records.NoteMaxLength } }
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

local function recordOf(characterId)
    local person = Ems.Core('GetCharacterRecord', characterId)
    if type(person) ~= 'table' then
        return nil
    end
    local insurance = DB.Single("SELECT DATE_FORMAT(valid_until, '%Y-%m-%d') AS valid_until, valid_until > NOW() AS valid, sold_by FROM ems_insurance WHERE character_id = ?", { characterId })
    local diseases = {}
    for _, entry in ipairs(Diseases.Active(characterId)) do
        local def = DEFS[entry.disease]
        diseases[#diseases + 1] = {
            label = def.label,
            stage = entry.stage,
            stages = def.cure == 'treatment' and def.stages - 1 or def.stages,
            cure = def.cure,
            series = entry.series,
            needed = Diseases.Needed(def, entry.stage),
        }
    end
    local history = {}
    for _, row in ipairs(DB.Query("SELECT kind, text, actor_name, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at FROM ems_records WHERE character_id = ? ORDER BY id DESC LIMIT ?",
        { characterId, CFG.Records.HistoryLimit }) or {}) do
        history[#history + 1] = { kind = row.kind, text = row.text, by = row.actor_name, at = row.at }
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
    local record = characterId and recordOf(math.floor(characterId))
    if not record then
        return { ok = false, error = 'not_found' }
    end
    Ems.Log({ actor_account_id = Ems.Core('GetAccountId', source), character_id = record.characterId, action = 'records_view',
        data = { admin = rights.admin or nil } })
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
    Ems.Record(record.characterId, 'note', text, Ems.NameOf(source))
    Ems.Log({ actor_account_id = Ems.Core('GetAccountId', source), character_id = record.characterId, action = 'records_note', data = { text = text } })
    return { ok = true, data = recordOf(record.characterId) }
end)
