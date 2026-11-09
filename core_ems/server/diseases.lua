-- Krankheiten: Ansteckung (Zufall und andere Kranke), Stadien, Tabletten, Behandlungsserien, Zusammenbruch.
-- Alles rechnet der Server, nur mit Online-Zeit. Der Client bekommt die Liste (Krankheit, Stadium) fuer die Symptome.
-- Was der Client meldet (nass, Stress), erhoeht nur die Chance, krank zu werden. Ein Cheater kann sich so hoechstens
-- vor Krankheiten druecken, nie etwas gewinnen.

if EmsDisabled then
    return
end

Diseases = {}

local CFG = Config.Ems
local DEFS = CFG.Diseases
local STATE_EVENT = 'core_ems:diseases'
local SECONDS_PER_MINUTE = 60
local EXPOSURE_MIN_GAP_MS = 45000

local cache = {}        -- [permanente ID] = { list = { Krankheit }, ticks, cured = { [krankheit] = os.time() } }
local exposure = {}     -- [source] = { wet, stress, at }

------------------------------------------------------------------------
-- Laden, Speichern, an den Client schicken
------------------------------------------------------------------------

local COLUMNS = 'id, disease, stage, worsen_in, series, series_left, gap_left'

local function fromRow(row)
    return { id = row.id, disease = row.disease, stage = row.stage, worsenIn = row.worsen_in, series = row.series,
        seriesLeft = row.series_left, gapLeft = row.gap_left }
end

local function load(characterId)
    local list = {}
    for _, row in ipairs(DB.Query('SELECT ' .. COLUMNS .. ' FROM ems_diseases WHERE character_id = ? AND cured_at IS NULL', { characterId }) or {}) do
        if DEFS[row.disease] then
            list[#list + 1] = fromRow(row)
        end
    end
    return list
end

local function save(entry)
    DB.Update('UPDATE ems_diseases SET stage = ?, worsen_in = ?, series = ?, series_left = ?, gap_left = ? WHERE id = ?',
        { entry.stage, math.floor(entry.worsenIn), entry.series, math.floor(entry.seriesLeft), math.floor(entry.gapLeft), entry.id })
end

local function saveAll(characterId)
    local data = cache[characterId]
    if data then
        for _, entry in ipairs(data.list) do
            save(entry)
        end
    end
end

-- Liste fuer den Client: nur, was die Symptome brauchen
function Diseases.Push(characterId)
    local source = Ems.SourceOf(characterId)
    local data = cache[characterId]
    if not source or not data then
        return
    end
    local list = {}
    for _, entry in ipairs(data.list) do
        list[#list + 1] = { disease = entry.disease, stage = entry.stage }
    end
    Network.SendToClient(source, STATE_EVENT, list)
end

-- Krankheiten eines Charakters (online aus dem Speicher, sonst aus der Datenbank)
function Diseases.Active(characterId)
    local data = cache[characterId]
    if data then
        return data.list
    end
    return load(characterId)
end

local function find(characterId, disease)
    for index, entry in ipairs(Diseases.Active(characterId)) do
        if entry.disease == disease then
            return entry, index
        end
    end
    return nil
end
Diseases.Find = find

function Ems.OnLoaded(source, characterId)
    cache[characterId] = { list = load(characterId), ticks = 0, cured = {} }
    Diseases.Push(characterId)
end

function Ems.OnUnloaded(source, characterId)
    exposure[source] = nil
    if characterId and cache[characterId] then
        saveAll(characterId)
        cache[characterId] = nil
    end
end

------------------------------------------------------------------------
-- Aendern
------------------------------------------------------------------------

local function stageText(def, stage)
    return ('%s, Stadium %d von %d'):format(def.label, stage, def.cure == 'treatment' and def.stages - 1 or def.stages)
end
Diseases.StageText = stageText

-- Neue Krankheit (Zufall, Ansteckung, Admin, Event). cause steht in Klammern in der Akte (z. B. 'angesteckt').
-- Gibt den Eintrag zurueck oder nil und einen Fehlercode.
function Diseases.Add(characterId, disease, stage, actorName, cause)
    local def = DEFS[disease]
    if not def then
        return nil, 'unknown_disease'
    end
    if find(characterId, disease) then
        return nil, 'already_sick'
    end
    stage = math.max(1, math.min(def.cure == 'treatment' and def.stages - 1 or def.stages, math.floor(tonumber(stage) or 1)))
    local worsenIn = def.worsenMinutes * SECONDS_PER_MINUTE
    local id = DB.Insert('INSERT INTO ems_diseases (character_id, disease, stage, worsen_in) VALUES (?, ?, ?, ?)',
        { characterId, disease, stage, worsenIn })
    if not id then
        return nil, 'db_error'
    end
    local entry = { id = id, disease = disease, stage = stage, worsenIn = worsenIn, series = 0, seriesLeft = 0, gapLeft = 0 }
    local data = cache[characterId]
    if data then
        data.list[#data.list + 1] = entry
    end
    Ems.Record(characterId, 'onset', ('%s begonnen%s'):format(stageText(def, stage), cause and (' (%s)'):format(cause) or ''), actorName)
    Ems.Log({ character_id = characterId, action = 'disease_onset', data = { disease = disease, stage = stage, by = actorName, cause = cause } })
    local source = Ems.SourceOf(characterId)
    if source then
        Platform.Notify(source, 'Du fühlst dich nicht gut.', 'warning')
    end
    Diseases.Push(characterId)
    return entry
end

-- Stadium von Hand setzen (Akte korrigieren). Fehlt die Krankheit, kommt sie dazu. Nie ins Endstadium, damit
-- niemand durch eine Korrektur zusammenbricht. Gibt den Eintrag zurueck oder nil und einen Fehlercode.
function Diseases.SetStage(characterId, disease, stage, actorName)
    local def = DEFS[disease]
    if not def then
        return nil, 'unknown_disease'
    end
    local top = def.cure == 'treatment' and def.stages - 1 or def.stages
    stage = math.floor(tonumber(stage) or 0)
    if stage < 1 or stage > top then
        return nil, 'invalid_input'
    end
    local entry = find(characterId, disease)
    if not entry then
        return Diseases.Add(characterId, disease, stage, actorName, 'Korrektur')
    end
    if entry.stage == stage then
        return entry
    end
    entry.stage = stage
    entry.worsenIn = def.worsenMinutes * SECONDS_PER_MINUTE
    entry.series, entry.seriesLeft = 0, 0
    save(entry)
    Ems.Record(characterId, 'correction', ('%s gesetzt (Korrektur)'):format(stageText(def, stage)), actorName)
    Diseases.Push(characterId)
    return entry
end

-- Geheilt (Tablette, Mediziner, Admin)
function Diseases.Cure(characterId, disease, actorName, how)
    local entry, index = find(characterId, disease)
    if not entry then
        return false, 'not_sick'
    end
    DB.Update('UPDATE ems_diseases SET cured_at = CURRENT_TIMESTAMP, cured_by = ?, stage = ? WHERE id = ?', DB.Args(actorName, entry.stage, entry.id))
    local data = cache[characterId]
    if data then
        table.remove(data.list, index)
        data.cured[disease] = os.time()
    end
    Ems.Record(characterId, 'cured', ('%s geheilt%s'):format(DEFS[disease].label, how and (' (%s)'):format(how) or ''), actorName)
    Ems.Log({ character_id = characterId, action = 'disease_cured', data = { disease = disease, by = actorName, how = how } })
    local source = Ems.SourceOf(characterId)
    if source then
        Platform.Notify(source, ('Deine %s ist weg.'):format(DEFS[disease].label), 'success')
    end
    Diseases.Push(characterId)
    return true
end

-- Ein Stadium hoeher. Im letzten Stadium einer Krankheit mit Behandlung: Zusammenbruch, hochholen vor Ort geht nicht,
-- nur das Krankenhaus (oder ein Admin mit /revive).
local function worsen(characterId, entry)
    local def = DEFS[entry.disease]
    if entry.stage >= def.stages then
        return
    end
    entry.stage = entry.stage + 1
    entry.worsenIn = def.worsenMinutes * SECONDS_PER_MINUTE
    entry.series, entry.seriesLeft = 0, 0
    save(entry)
    local source = Ems.SourceOf(characterId)
    if def.cure == 'treatment' and entry.stage >= def.stages then
        Ems.Record(characterId, 'collapse', ('Zusammenbruch durch %s'):format(def.label))
        Ems.Log({ character_id = characterId, action = 'disease_collapse', data = { disease = entry.disease } })
        if source then
            Ems.Core('Collapse', source, def.label, true)
        end
    else
        Ems.Record(characterId, 'worse', ('%s schlimmer geworden'):format(stageText(def, entry.stage)))
        if source then
            local hint = def.cure == 'pill' and 'Nimm eine passende Tablette oder geh zum Rettungsdienst.' or 'Lass dich vom Rettungsdienst behandeln.'
            Platform.Notify(source, ('Deine %s wird schlimmer. %s'):format(def.label, hint), 'warning')
        end
    end
    Diseases.Push(characterId)
end

-- Ein Stadium runter (Tablette). Aus Stadium 1 wird geheilt.
local function better(characterId, entry, actorName, how)
    if entry.stage <= 1 then
        return Diseases.Cure(characterId, entry.disease, actorName, how)
    end
    local def = DEFS[entry.disease]
    entry.stage = entry.stage - 1
    entry.worsenIn = def.worsenMinutes * SECONDS_PER_MINUTE
    save(entry)
    Ems.Record(characterId, 'better', ('%s besser (%s)'):format(stageText(def, entry.stage), how or 'Tablette'), actorName)
    Diseases.Push(characterId)
    return true
end

-- Tablette genommen (aus dem Inventar)
function Diseases.Pill(characterId, item)
    local source = Ems.SourceOf(characterId)
    local disease
    for name, def in pairs(DEFS) do
        if def.pill == item then
            disease = name
        end
    end
    local entry = disease and find(characterId, disease)
    if not entry then
        if source then
            Platform.Notify(source, 'Du merkst keinen Unterschied.', 'info')
        end
        return false, 'not_sick'
    end
    if entry.gapLeft > 0 then
        if source then
            Platform.Notify(source, 'Die letzte Tablette wirkt noch. Die zweite bringt nichts.', 'info')
        end
        return false, 'too_soon'
    end
    entry.gapLeft = CFG.PillCooldownMinutes * SECONDS_PER_MINUTE
    Ems.Record(characterId, 'pill', ('Tablette gegen %s genommen'):format(DEFS[disease].label))
    return better(characterId, entry, nil, 'Tablette')
end

-- Wie viele Behandlungen braucht dieses Stadium? treatments ist eine Zahl oder eine Liste pro Stadium.
function Diseases.Needed(def, stage)
    local value = def.treatments
    if type(value) == 'table' then
        return value[math.min(stage, #value)] or value[#value] or 1
    end
    return tonumber(value) or 1
end

-- Behandlung durch einen Mediziner. Gibt true und { cured, series, needed } oder false und einen Fehlercode zurueck.
function Diseases.Treat(characterId, disease, medicName)
    local entry = find(characterId, disease)
    local def = DEFS[disease]
    if not entry or not def then
        return false, 'not_sick'
    end
    if def.cure == 'pill' then
        Ems.Record(characterId, 'treatment', ('%s behandelt'):format(def.label), medicName)
        Diseases.Cure(characterId, disease, medicName, 'Behandlung')
        return true, { cured = true }
    end
    if entry.gapLeft > 0 then
        return false, 'too_soon', { minutes = math.ceil(entry.gapLeft / SECONDS_PER_MINUTE) }
    end
    if entry.series == 0 then
        entry.seriesLeft = def.windowMinutes * SECONDS_PER_MINUTE
    end
    entry.series = entry.series + 1
    entry.gapLeft = def.gapMinutes * SECONDS_PER_MINUTE
    -- Jede Behandlung haelt die Krankheit auf, bis zur naechsten Verschlechterung ist wieder volle Zeit
    entry.worsenIn = def.worsenMinutes * SECONDS_PER_MINUTE
    local needed = Diseases.Needed(def, entry.stage)
    Ems.Record(characterId, 'treatment', ('%s behandelt, %d von %d'):format(def.label, entry.series, needed), medicName)
    if entry.series >= needed then
        Diseases.Cure(characterId, disease, medicName, ('%d Behandlungen'):format(needed))
        return true, { cured = true }
    end
    save(entry)
    Diseases.Push(characterId)
    return true, { cured = false, series = entry.series, needed = needed }
end

------------------------------------------------------------------------
-- Jede Minute: Uhr weiterdrehen, Ansteckung
------------------------------------------------------------------------

local function activeCount(data)
    return #data.list
end

-- Kann der Charakter diese Krankheit gerade bekommen? (nicht schon krank, nicht frisch geheilt, nicht zu viele)
local function canGet(characterId, data, name)
    if activeCount(data) >= CFG.MaxActiveDiseases or find(characterId, name) then
        return false
    end
    local curedAt = data.cured[name]
    return not (curedAt and os.time() - curedAt < CFG.ImmuneAfterCureMinutes * SECONDS_PER_MINUTE)
end

local function tryInfect(characterId, data, reasons)
    for _, name in ipairs(CFG.DiseaseOrder) do
        local def = DEFS[name]
        local chance = 0
        for key, value in pairs(def.chance or {}) do
            chance = chance + value * (reasons[key] or 0)
        end
        if chance > 0 and canGet(characterId, data, name) and math.random() < chance then
            Diseases.Add(characterId, name, 1)
            return
        end
    end
end

-- Ansteckende Krankheiten springen auf Leute in der Naehe ueber. Positionen kommen vom Server, nicht vom Client.
local CONTAGIOUS = {}
for _, name in ipairs(CFG.DiseaseOrder) do
    if DEFS[name].contagious then
        CONTAGIOUS[name] = DEFS[name].contagious
    end
end

local function spread(active, seconds)
    if next(CONTAGIOUS) == nil then
        return
    end
    local carriers = {}
    for source, characterId in pairs(active) do
        local data = cache[characterId]
        for _, entry in ipairs(data and data.list or {}) do
            if CONTAGIOUS[entry.disease] then
                carriers[#carriers + 1] = { source = source, disease = entry.disease, stage = entry.stage }
            end
        end
    end
    local minutes = seconds / SECONDS_PER_MINUTE
    for _, carrier in ipairs(carriers) do
        local rule = CONTAGIOUS[carrier.disease]
        for other, otherId in pairs(active) do
            local data = cache[otherId]
            if other ~= carrier.source and data and not Ems.Core('IsDead', other)
                and canGet(otherId, data, carrier.disease) and Ems.Near(carrier.source, other, rule.distance)
                and math.random() < rule.chance * carrier.stage * minutes then
                Diseases.Add(otherId, carrier.disease, 1, nil, 'angesteckt')
            end
        end
    end
end
Diseases.Spread = spread

local function tickCharacter(source, characterId, seconds)
    local data = cache[characterId]
    if not data then
        return
    end
    local dead = Ems.Core('IsDead', source)
    -- Bewusstlos laeuft die Uhr nicht weiter (sonst bricht man im Liegen gleich wieder zusammen)
    if not dead then
        for _, entry in ipairs({ table.unpack(data.list) }) do
            local def = DEFS[entry.disease]
            entry.gapLeft = math.max(0, entry.gapLeft - seconds)
            if entry.series > 0 then
                entry.seriesLeft = entry.seriesLeft - seconds
                if entry.seriesLeft <= 0 then
                    -- Behandlungsfenster abgelaufen: Serie verfaellt
                    entry.series, entry.seriesLeft = 0, 0
                    Ems.Record(characterId, 'series', ('Behandlung von %s abgebrochen, nicht rechtzeitig fortgesetzt'):format(def.label))
                end
            end
            if entry.stage < def.stages then
                entry.worsenIn = entry.worsenIn - seconds
                if entry.worsenIn <= 0 then
                    worsen(characterId, entry)
                end
            end
            -- Hunger und Durst (Magen-Darm)
            local needs = def.needs and def.needs[entry.stage]
            if needs then
                Ems.Core('AddNeeds', source, { hunger = (needs.hunger or 0) * seconds / SECONDS_PER_MINUTE, thirst = (needs.thirst or 0) * seconds / SECONDS_PER_MINUTE })
            end
        end
        -- Ansteckung: pro Minute online, dazu was der Client gemeldet hat
        local report = exposure[source]
        exposure[source] = nil
        local minutes = seconds / SECONDS_PER_MINUTE
        tryInfect(characterId, data, {
            base = minutes,
            wet = report and report.wet / SECONDS_PER_MINUTE or 0,
            stress = report and report.stress / SECONDS_PER_MINUTE or 0,
        })
    end
    data.ticks = data.ticks + 1
    if data.ticks % CFG.SaveEveryTicks == 0 then
        saveAll(characterId)
    end
end

Platform.SetInterval(CFG.TickSeconds * 1000, function()
    local active = Ems.Active()
    for source, characterId in pairs(active) do
        tickCharacter(source, characterId, CFG.TickSeconds)
    end
    spread(active, CFG.TickSeconds)
end)
Diseases.Tick = tickCharacter

-- Der Client meldet: so viele Sekunden nass und unter Stress seit der letzten Meldung
Network.RegisterCallback('ems_exposure', function(source, data)
    if not Ems.CharacterOf(source) or type(data) ~= 'table' then
        return { ok = false }
    end
    local now = Platform.GetTime()
    local last = exposure[source]
    if last and now - last.at < EXPOSURE_MIN_GAP_MS then
        return { ok = false, error = 'too_often' }
    end
    local limit = CFG.ExposureReportSeconds
    local function clamp(value)
        value = tonumber(value) or 0
        return math.max(0, math.min(limit, value))
    end
    exposure[source] = { wet = clamp(data.wet), stress = clamp(data.stress), at = now }
    return { ok = true }
end)

------------------------------------------------------------------------
-- Essen (Magen-Darm) und Tabletten aus dem Inventar
------------------------------------------------------------------------

local FOOD = {}
for _, item in ipairs(CFG.FoodItems) do
    FOOD[item] = true
end
local PILLS = {}
for _, def in pairs(DEFS) do
    if def.pill then
        PILLS[def.pill] = true
    end
end

Platform.OnEvent('core_inventory:itemUsed', function(source, characterId, item)
    characterId = tonumber(characterId)
    if not characterId or not cache[characterId] then
        return
    end
    if PILLS[item] then
        Diseases.Pill(characterId, item)
    elseif FOOD[item] then
        tryInfect(characterId, cache[characterId], { food = 1 })
    end
end)

------------------------------------------------------------------------
-- Nach dem Zusammenbruch: Krankenhaus (oder Admin-Revive), die Krankheit geht zurueck auf afterCollapseStage
------------------------------------------------------------------------

local function stabilize(source, characterId, where)
    characterId = tonumber(characterId)
    local data = characterId and cache[characterId]
    if not data then
        return
    end
    for _, entry in ipairs(data.list) do
        local def = DEFS[entry.disease]
        if def.cure == 'treatment' and entry.stage >= def.stages then
            entry.stage = def.afterCollapseStage
            entry.worsenIn = def.worsenMinutes * SECONDS_PER_MINUTE
            entry.series, entry.seriesLeft, entry.gapLeft = 0, 0, 0
            save(entry)
            Ems.Record(characterId, 'stabilized', ('%s stabilisiert, %s'):format(where, stageText(def, entry.stage)))
            Platform.Notify(source, ('Du bist wieder bei dir. Deine %s ist nicht geheilt, lass dich weiter behandeln.'):format(def.label), 'warning')
        end
    end
    Diseases.Push(characterId)
end

Platform.OnEvent('core:characterRespawned', function(source, characterId)
    stabilize(source, characterId, 'Im Krankenhaus')
end)
Platform.OnEvent('core:characterRevived', function(source, characterId)
    stabilize(source, characterId, 'Vor Ort')
end)

Platform.OnResourceStop(function()
    for characterId in pairs(cache) do
        saveAll(characterId)
    end
end)

------------------------------------------------------------------------
-- Schnittstellen und Admin-Befehle
------------------------------------------------------------------------

-- { { disease, label, stage } } eines Charakters
Platform.Export('GetDiseases', function(characterId)
    local list = {}
    for _, entry in ipairs(Diseases.Active(tonumber(characterId)) or {}) do
        list[#list + 1] = { disease = entry.disease, label = DEFS[entry.disease].label, stage = entry.stage }
    end
    return list
end)
Platform.Export('AddDisease', function(characterId, disease, stage)
    return Diseases.Add(tonumber(characterId), disease, stage, 'Script') ~= nil
end)
Platform.Export('CureDisease', function(characterId, disease)
    return (Diseases.Cure(tonumber(characterId), disease, 'Script', 'Script'))
end)

local function diseaseList()
    return table.concat(CFG.DiseaseOrder, ', ')
end

-- /krankheit <ID> <krankheit> [stadium]   /heilen <ID> [krankheit]
Platform.RegisterCommand('krankheit', function(source, args)
    local allowed, accountId = Ems.Core('AuthorizeCommand', source, 'krankheit', CFG.AdminPermission, args, true)
    if not allowed then
        return
    end
    local characterId, disease = tonumber(args[1]), args[2]
    if not characterId or not DEFS[disease] then
        Platform.Notify(source, ('Benutzung: /krankheit <ID> <krankheit> [stadium]. Krankheiten: %s'):format(diseaseList()), 'error')
        return
    end
    local entry, err = Diseases.Add(characterId, disease, args[3], 'Admin')
    if not entry then
        Platform.Notify(source, err == 'already_sick' and 'Die Person hat diese Krankheit schon.' or ('Das hat nicht geklappt (%s).'):format(err), 'error')
        return
    end
    Ems.Log({ actor_account_id = accountId, character_id = characterId, action = 'admin_disease', data = { disease = disease, stage = entry.stage } })
    Ems.Protocol('datenbank', { action = 'admin_disease', admin = true, actorSource = source, actorName = ('Admin %s'):format(Ems.NameOf(source) or ''),
        target = characterId, text = ('%s gegeben (/krankheit)'):format(stageText(DEFS[disease], entry.stage)) })
    Platform.Notify(source, ('ID %d hat jetzt %s.'):format(characterId, stageText(DEFS[disease], entry.stage)), 'success')
end)

Platform.RegisterCommand('heilen', function(source, args)
    local allowed, accountId = Ems.Core('AuthorizeCommand', source, 'heilen', CFG.AdminPermission, args, true)
    if not allowed then
        return
    end
    local characterId, disease = tonumber(args[1]), args[2]
    if not characterId then
        Platform.Notify(source, 'Benutzung: /heilen <ID> [krankheit]. Ohne Krankheit werden alle geheilt.', 'error')
        return
    end
    local count = 0
    for _, entry in ipairs({ table.unpack(Diseases.Active(characterId)) }) do
        if not disease or entry.disease == disease then
            if Diseases.Cure(characterId, entry.disease, 'Admin', 'Admin') then
                count = count + 1
            end
        end
    end
    Ems.Log({ actor_account_id = accountId, character_id = characterId, action = 'admin_cure', data = { disease = disease, count = count } })
    if count > 0 then
        Ems.Protocol('datenbank', { action = 'admin_cure', admin = true, actorSource = source, actorName = ('Admin %s'):format(Ems.NameOf(source) or ''),
            target = characterId, text = ('%d Krankheit(en) geheilt (/heilen)'):format(count) })
    end
    Platform.Notify(source, ('%d Krankheit(en) bei ID %d geheilt.'):format(count, characterId), count > 0 and 'success' or 'info')
end)

-- In der Befehlsliste des Admin-Menues zeigen
DB.Ready(function()
    Ems.Core('AddCommandHelp', {
        title = 'Rettungsdienst',
        entries = {
            { usage = '/krankheit 17 cold 2', text = ('Krankheit geben (zum Testen und für RP-Szenen). Krankheiten: %s.'):format(diseaseList()), permission = CFG.AdminPermission },
            { usage = '/heilen 17', text = 'Alle Krankheiten heilen. Mit Name nur eine, z. B. /heilen 17 cold.', permission = CFG.AdminPermission },
        },
    })
end)
