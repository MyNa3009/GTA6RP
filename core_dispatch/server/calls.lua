-- Notrufe und Einsaetze: anlegen (Notruf, Einheit in Not), uebernehmen, zuweisen, freigeben, Nachricht an den
-- Anrufer, abschliessen. Offene Einsaetze liegen im Speicher, alles steht zusaetzlich in der Datenbank.
-- Fuer Anrufer: /dispatch Text, eigene Notrufe ansehen und zurueckziehen.

if DispatchDisabled then
    return
end

Calls = {}

local CFG = Config.Dispatch
local calls = {}          -- [id] = Einsatz (offen oder aktiv)
local lastSent = {}       -- [permanente ID] = Zeit des letzten Notrufs

local PRIORITY = {}
for _, entry in ipairs(CFG.Priorities) do
    PRIORITY[entry.level] = entry.label
end
local MAX_PRIORITY = #CFG.Priorities
local RESULTS = {}
for _, entry in ipairs(CFG.Results) do
    RESULTS[entry.key] = entry
end
local CANCELLED = { key = 'cancelled', label = 'Vom Anrufer zurückgezogen' }
RESULTS.cancelled = CANCELLED

Calls.Priority = PRIORITY
Calls.Results = RESULTS

function Calls.Get(id)
    return calls[tonumber(id)]
end

function Calls.Open(service)
    local list = {}
    for _, call in pairs(calls) do
        if call.service == service then
            list[#list + 1] = call
        end
    end
    -- Wichtigstes zuerst: Prioritaet, dann aelteste
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.id < b.id
    end)
    return list
end

------------------------------------------------------------------------
-- Darstellung und Senden
------------------------------------------------------------------------

local function unitList(call)
    local list = {}
    for _, characterId in ipairs(call.unitIds) do
        local unit = Disp.UnitByCharacter(characterId)
        list[#list + 1] = unit and { id = characterId, name = unit.name, callsign = unit.callsign, status = unit.status }
            or { id = characterId, name = call.unitNames[characterId] }
    end
    return list
end

-- Einsatz fuer die UI. Anonyme Anrufer sehen nur Admins.
function Calls.Public(call, admin)
    local showCaller = admin or not call.anonymous
    return {
        id = call.id, number = call.number, kind = call.kind, priority = call.priority, status = call.status,
        text = call.text, location = call.location, pos = call.pos,
        createdAt = call.createdAt, acceptedAt = call.acceptedAt, arrivedAt = call.arrivedAt,
        caller = (showCaller and call.callerId) and { id = call.callerId, name = call.callerName } or nil,
        anonymous = call.anonymous or nil, callerDown = call.callerDown or nil,
        units = unitList(call), lastEvent = call.lastEvent,
    }
end

-- An alle Einheiten und Admins des Dienstes. alert: als neuer Alarm anzeigen ('new' | 'assigned' | 'urgent')
function Calls.Push(call, alert, onlyCharacter)
    for _, receiver in ipairs(Disp.Receivers(call.service)) do
        local unit = Disp.Unit(receiver.source)
        local showAlert = alert
        if onlyCharacter and (not unit or unit.characterId ~= onlyCharacter) then
            showAlert = nil
        end
        Network.SendToClient(receiver.source, 'core_dispatch:call', {
            service = call.service, now = Disp.Now(), alert = showAlert, call = Calls.Public(call, receiver.admin),
        })
    end
end

function Disp.SendOpenCalls(unit)
    for _, call in ipairs(Calls.Open(unit.service)) do
        Network.SendToClient(unit.source, 'core_dispatch:call', { service = call.service, now = Disp.Now(), call = Calls.Public(call, false) })
    end
end

-- Den Anrufer benachrichtigen, wenn er online ist
local function tellCaller(call, text, kind)
    if not call.callerId or call.kind ~= 'call' then
        return
    end
    local source = Disp.Core('GetSourceByCharacter', call.callerId)
    if source then
        Platform.Notify(source, text, kind or 'info')
        Network.SendToClient(source, 'core_dispatch:mine', { id = call.id })
    end
end

------------------------------------------------------------------------
-- Verlauf, Speichern
------------------------------------------------------------------------

-- Eintrag im Verlauf des Einsatzes. actor: { characterId, name } oder nil (System)
function Calls.Event(call, kind, text, actor)
    call.lastEvent = { kind = kind, text = text, at = Disp.Now(), by = actor and actor.name or nil }
    local callId = call.id
    local actorId, actorName = actor and actor.characterId or nil, actor and actor.name or nil
    Platform.Async(function()
        DB.Insert('INSERT INTO dispatch_events (call_id, kind, actor_id, actor_name, text) VALUES (?, ?, ?, ?, ?)',
            DB.Args(callId, kind, actorId, actorName, text))
    end)
end

local function saveUnits(call)
    local list = {}
    for _, characterId in ipairs(call.unitIds) do
        list[#list + 1] = { id = characterId, name = call.unitNames[characterId] }
    end
    DB.Update('UPDATE dispatch_calls SET units = ?, status = ? WHERE id = ?', { Platform.JsonEncode(list), call.status, call.id })
end

local function protocol(call, action, text, actor, target)
    Disp.Protocol(call.faction, {
        action = action, text = ('%s: %s'):format(call.number, text), target = target,
        actorId = actor and actor.characterId or nil, actorName = actor and actor.name or nil, admin = actor and actor.admin or nil,
    })
end

------------------------------------------------------------------------
-- Anlegen
------------------------------------------------------------------------

-- options: { kind, priority, callerId, callerName, anonymous, callerDown, text, location, pos, actor }
function Calls.Create(service, options)
    local pos = options.pos
    local id = DB.Insert([[INSERT INTO dispatch_calls (service, faction, number, kind, priority, caller_id, caller_name, anonymous, caller_down, text, location, x, y, z)
        VALUES (?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        DB.Args(service.key, service.faction, options.kind, options.priority, options.callerId, options.callerName,
            options.anonymous and 1 or 0, options.callerDown and 1 or 0, options.text, options.location, pos.x, pos.y, pos.z))
    if not id then
        return nil, 'db_error'
    end
    -- Einsatznummer "EMS 26/0042": Jahr nach der Uhr der Datenbank, laufende Nummer aus der ID
    DB.Update("UPDATE dispatch_calls SET number = CONCAT(?, ' ', DATE_FORMAT(created_at, '%y'), '/', LPAD(id MOD 10000, 4, '0')) WHERE id = ?", { service.prefix, id })
    local number = DB.Scalar('SELECT number FROM dispatch_calls WHERE id = ?', { id })
    local call = {
        id = id, service = service.key, faction = service.faction, number = number, kind = options.kind,
        priority = options.priority, status = 'open', callerId = options.callerId, callerName = options.callerName,
        anonymous = options.anonymous == true, callerDown = options.callerDown == true, text = options.text,
        location = options.location, pos = { x = pos.x, y = pos.y, z = pos.z }, createdAt = Disp.Now(),
        unitIds = {}, unitNames = {},
    }
    calls[id] = call
    local what = options.kind == 'unit' and 'Einheit in Not' or 'Notruf eingegangen'
    Calls.Event(call, 'created', ('%s: %s'):format(what, options.text), options.actor)
    protocol(call, 'call_' .. options.kind, ('%s (%s)'):format(what, PRIORITY[call.priority]), options.actor, options.callerId)
    Disp.Log({ character_id = options.callerId, action = 'call', data = { id = id, number = number, service = service.key,
        kind = options.kind, priority = call.priority, text = options.text, anonymous = options.anonymous or nil } })
    Calls.Push(call, (call.priority >= MAX_PRIORITY or options.kind == 'unit') and 'urgent' or 'new')
    return call
end

------------------------------------------------------------------------
-- Einheiten am Einsatz
------------------------------------------------------------------------

local function hasUnit(call, characterId)
    for index, id in ipairs(call.unitIds) do
        if id == characterId then
            return index
        end
    end
    return nil
end

-- Einheit aus ihrem Einsatz nehmen (ohne Status zu setzen)
local function detach(unit, actor, reason)
    local call = unit.callId and calls[unit.callId]
    unit.callId = nil
    if not call then
        return
    end
    local index = hasUnit(call, unit.characterId)
    if index then
        table.remove(call.unitIds, index)
        if #call.unitIds == 0 then
            call.status = 'open'
        end
        Calls.Event(call, 'release', reason or ('%s hat den Einsatz freigegeben'):format(unit.name), actor)
        saveUnits(call)
        Calls.Push(call)
    end
end

-- Einheit an einen Einsatz. by: wer es tut (die Einheit selbst oder die Leitstelle)
function Calls.Assign(call, unit, by)
    if hasUnit(call, unit.characterId) then
        return false, 'already_assigned'
    end
    if unit.callId and unit.callId ~= call.id then
        detach(unit, by, ('%s ist zu %s gewechselt'):format(unit.name, call.number))
    end
    call.unitIds[#call.unitIds + 1] = unit.characterId
    call.unitNames[unit.characterId] = unit.name
    unit.callId = call.id
    local first = call.acceptedAt == nil
    call.status = 'active'
    if first then
        call.acceptedAt = Disp.Now()
        DB.Update('UPDATE dispatch_calls SET accepted_at = CURRENT_TIMESTAMP WHERE id = ?', { call.id })
    end
    local self = by and by.characterId == unit.characterId
    Calls.Event(call, 'accept', self and ('%s hat übernommen'):format(unit.name) or ('%s zugewiesen von %s'):format(unit.name, by and by.name or 'System'), by)
    protocol(call, self and 'call_accept' or 'call_assign', self and 'Einsatz übernommen' or ('Einheit zugewiesen: %s'):format(unit.name), by, unit.characterId)
    saveUnits(call)
    Disp.SetStatus(unit, CFG.StatusOnAccept)
    Disp.PushSelf(unit)
    Calls.Push(call, not self and 'assigned' or nil, unit.characterId)
    if first then
        tellCaller(call, ('Dein Notruf %s wurde übernommen. Hilfe ist unterwegs.'):format(call.number), 'success')
    end
    return true
end

function Calls.Release(call, unit, by)
    if not hasUnit(call, unit.characterId) then
        return false, 'not_assigned'
    end
    local self = by and by.characterId == unit.characterId
    detach(unit, by, self and ('%s hat den Einsatz freigegeben'):format(unit.name) or ('%s abgezogen von %s'):format(unit.name, by and by.name or 'System'))
    protocol(call, 'call_release', self and 'Einsatz freigegeben' or ('Einheit abgezogen: %s'):format(unit.name), by, unit.characterId)
    Disp.SetStatus(unit, CFG.StatusOnClose)
    Disp.PushSelf(unit)
    return true
end

function Disp.OnUnitGone(unit)
    detach(unit, nil, ('%s ist nicht mehr im Dienst'):format(unit.name))
end

------------------------------------------------------------------------
-- Abschliessen, Prioritaet, Notiz, Nachricht
------------------------------------------------------------------------

function Calls.Close(call, resultKey, report, by)
    local result = RESULTS[resultKey]
    if not result then
        return false, 'invalid_result'
    end
    for _, characterId in ipairs(call.unitIds) do
        local unit = Disp.UnitByCharacter(characterId)
        if unit and unit.callId == call.id then
            unit.callId = nil
            Disp.SetStatus(unit, CFG.StatusOnClose)
            Disp.PushSelf(unit)
        end
    end
    call.status = 'closed'
    calls[call.id] = nil
    DB.Update('UPDATE dispatch_calls SET status = ?, closed_at = CURRENT_TIMESTAMP, closed_by = ?, result = ?, report = ? WHERE id = ?',
        DB.Args('closed', by and by.name or nil, result.key, report, call.id))
    Calls.Event(call, 'close', ('Abgeschlossen: %s%s'):format(result.label, report and (' · ' .. report) or ''), by)
    protocol(call, 'call_close', ('Abgeschlossen: %s'):format(result.label), by, call.callerId)
    Disp.Log({ character_id = call.callerId, action = 'close', reason = report,
        data = { id = call.id, number = call.number, result = result.key, by = by and by.characterId or nil, admin = by and by.admin or nil } })
    if result.block and call.callerId then
        DB.Update('INSERT INTO dispatch_blocks (character_id, until, reason, by_name) VALUES (?, DATE_ADD(NOW(), INTERVAL ? MINUTE), ?, ?) ON DUPLICATE KEY UPDATE until = VALUES(until), reason = VALUES(reason), by_name = VALUES(by_name)',
            DB.Args(call.callerId, CFG.AbuseBlockMinutes, ('%s: %s'):format(call.number, result.label), by and by.name or nil))
        tellCaller(call, ('Dein Notruf %s wurde als Missbrauch eingestuft. Du kannst %d Minuten lang keinen Notruf absetzen.'):format(call.number, CFG.AbuseBlockMinutes), 'error')
    elseif result.key ~= 'cancelled' then
        tellCaller(call, ('Dein Notruf %s ist abgeschlossen: %s.'):format(call.number, result.label), 'info')
    end
    Calls.Push(call)
    return true
end

function Calls.SetPriority(call, level, by)
    if not PRIORITY[level] then
        return false, 'invalid_priority'
    end
    if call.priority == level then
        return true
    end
    call.priority = level
    DB.Update('UPDATE dispatch_calls SET priority = ? WHERE id = ?', { level, call.id })
    Calls.Event(call, 'priority', ('Priorität: %s'):format(PRIORITY[level]), by)
    Calls.Push(call, level >= MAX_PRIORITY and 'urgent' or nil)
    return true
end

function Calls.Note(call, text, by)
    Calls.Event(call, 'note', text, by)
    Calls.Push(call)
    return true
end

function Calls.Message(call, text, by)
    if not call.callerId or call.kind ~= 'call' then
        return false, 'no_caller'
    end
    Calls.Event(call, 'message', text, by)
    protocol(call, 'call_message', ('Nachricht an den Anrufer: %s'):format(text), by, call.callerId)
    local service = Disp.Service(call.service)
    tellCaller(call, ('Leitstelle %s zu %s: %s'):format(service and service.label or '', call.number, text), 'info')
    Calls.Push(call)
    return true
end

------------------------------------------------------------------------
-- Automatisch "am Einsatzort"
------------------------------------------------------------------------

Platform.SetInterval(CFG.ArriveCheckMs, function()
    for _, call in pairs(calls) do
        for _, characterId in ipairs(call.unitIds) do
            local unit = Disp.UnitByCharacter(characterId)
            if unit and unit.callId == call.id and unit.status == CFG.StatusOnAccept then
                local distance = Disp.Distance(Platform.GetPlayerPosition(unit.source), call.pos)
                if distance and distance <= CFG.ArriveDistance then
                    Disp.SetStatus(unit, CFG.StatusOnArrive)
                    if not call.arrivedAt then
                        call.arrivedAt = Disp.Now()
                        DB.Update('UPDATE dispatch_calls SET arrived_at = CURRENT_TIMESTAMP WHERE id = ?', { call.id })
                    end
                    Calls.Event(call, 'arrive', ('%s ist am Einsatzort'):format(unit.name), unit)
                    Calls.Push(call)
                end
            end
        end
    end
end)

------------------------------------------------------------------------
-- Laden beim Start
------------------------------------------------------------------------

function Disp.LoadCalls()
    local rows = DB.Query("SELECT id, service, faction, number, kind, priority, status, caller_id, caller_name, anonymous, caller_down, text, location, x, y, z, UNIX_TIMESTAMP(created_at) AS created, UNIX_TIMESTAMP(accepted_at) AS accepted, UNIX_TIMESTAMP(arrived_at) AS arrived FROM dispatch_calls WHERE status IN ('open', 'active')") or {}
    for _, row in ipairs(rows) do
        if Disp.Service(row.service) then
            -- Nach einem Neustart ist niemand mehr zugewiesen
            calls[row.id] = {
                id = row.id, service = row.service, faction = row.faction, number = row.number, kind = row.kind,
                priority = row.priority, status = 'open', callerId = row.caller_id, callerName = row.caller_name,
                anonymous = row.anonymous == 1 or row.anonymous == true, callerDown = row.caller_down == 1 or row.caller_down == true,
                text = row.text, location = row.location, pos = { x = row.x, y = row.y, z = row.z },
                createdAt = tonumber(row.created), acceptedAt = tonumber(row.accepted), arrivedAt = tonumber(row.arrived),
                unitIds = {}, unitNames = {},
            }
        end
    end
    DB.Update("UPDATE dispatch_calls SET status = 'open', units = NULL WHERE status = 'active'")
end

------------------------------------------------------------------------
-- Anrufer: Notruf absetzen, eigene Notrufe
------------------------------------------------------------------------

local function blockedUntil(characterId)
    return DB.Scalar("SELECT DATE_FORMAT(until, '%H:%i') FROM dispatch_blocks WHERE character_id = ? AND until > NOW()", { characterId })
end

local function openCount(characterId)
    local count = 0
    for _, call in pairs(calls) do
        if call.callerId == characterId and call.kind == 'call' then
            count = count + 1
        end
    end
    return count
end

-- { text, service?, anonymous?, location? }. Ohne service: erstes Wort ("/dispatch ems ...") oder DefaultService.
Disp.Register('dispatch_send', function(source, data)
    local characterId = Disp.CharacterOf(source)
    local text = Disp.Text(data.text, CFG.TextMax)
    local service = Disp.Service(data.service)
    if not service and text then
        local first, rest = text:match('^(%S+)%s+(.+)$')
        local byWord = Disp.ServiceByWord(first)
        if byWord and rest then
            service, text = byWord, rest
        end
    end
    service = service or Disp.Service(CFG.DefaultService)
    if not service then
        return { ok = false, error = 'invalid_service' }
    end
    if not text or utf8.len(text) < CFG.TextMin then
        return { ok = false, error = 'text_too_short' }
    end
    local blocked = blockedUntil(characterId)
    if blocked then
        return { ok = false, error = 'blocked', data = { ['until'] = blocked } }
    end
    local now = Disp.Now()
    local wait = lastSent[characterId] and (lastSent[characterId] + CFG.CooldownSeconds - now) or 0
    if wait > 0 then
        return { ok = false, error = 'cooldown', data = { seconds = wait } }
    end
    if openCount(characterId) >= CFG.MaxOpenPerCaller then
        return { ok = false, error = 'too_many_open' }
    end
    local pos = Platform.GetPlayerPosition(source)
    if not pos then
        return { ok = false, error = 'no_position' }
    end
    local down = Disp.Core('IsDead', source) == true
    local priority = down and math.max(1, CFG.DownPriority) or 1
    local call, err = Calls.Create(service, {
        kind = 'call', priority = priority, callerId = characterId, callerName = Disp.NameOf(source),
        anonymous = data.anonymous == true, callerDown = down, text = text,
        location = Disp.Text(data.location, CFG.LocationMax), pos = pos,
        actor = { characterId = characterId, name = Disp.NameOf(source) },
    })
    if not call then
        return { ok = false, error = err }
    end
    lastSent[characterId] = now
    return { ok = true, data = { id = call.id, number = call.number, service = service.label, units = #Disp.UnitsOf(service.key) } }
end)

-- Fuer das Formular: Dienste, eigene letzte Notrufe mit Nachrichten der Leitstelle, Sperre, Wartezeit
Disp.Register('dispatch_mine', function(source)
    local characterId = Disp.CharacterOf(source)
    local rows = DB.Query("SELECT id, service, number, status, result, text, UNIX_TIMESTAMP(created_at) AS created FROM dispatch_calls WHERE caller_id = ? AND kind = 'call' ORDER BY created_at DESC LIMIT ?",
        { characterId, CFG.MyCallsShown }) or {}
    local list = {}
    for _, row in ipairs(rows) do
        local messages = {}
        for _, event in ipairs(DB.Query("SELECT text, UNIX_TIMESTAMP(created_at) AS at FROM dispatch_events WHERE call_id = ? AND kind = 'message' ORDER BY id", { row.id }) or {}) do
            messages[#messages + 1] = { text = event.text, at = tonumber(event.at) }
        end
        local live = calls[row.id]
        local service = Disp.Service(row.service)
        list[#list + 1] = {
            id = row.id, number = row.number, service = service and service.label or row.service, text = row.text,
            status = live and live.status or row.status, result = row.result and RESULTS[row.result] and RESULTS[row.result].label or nil,
            createdAt = tonumber(row.created), units = live and #live.unitIds or 0, messages = messages,
        }
    end
    local services = {}
    for _, service in ipairs(Disp.Services()) do
        services[#services + 1] = { key = service.key, label = service.label, units = #Disp.UnitsOf(service.key) }
    end
    local wait = lastSent[characterId] and (lastSent[characterId] + CFG.CooldownSeconds - Disp.Now()) or 0
    return { ok = true, data = {
        now = Disp.Now(), calls = list, services = services, default = CFG.DefaultService,
        blockedUntil = blockedUntil(characterId), cooldown = wait > 0 and wait or nil,
        textMin = CFG.TextMin, textMax = CFG.TextMax,
    } }
end)

-- Eigenen Notruf zurueckziehen (solange er offen oder aktiv ist)
Disp.Register('dispatch_cancel', function(source, data)
    local call = Calls.Get(data.id)
    local characterId = Disp.CharacterOf(source)
    if not call or call.callerId ~= characterId or call.kind ~= 'call' then
        return { ok = false, error = 'not_found' }
    end
    Calls.Close(call, 'cancelled', nil, { characterId = characterId, name = call.callerName })
    return { ok = true }
end)

-- Fuer andere Scripts (z. B. ein Handy, ein Alarmknopf): Notruf ohne Formular.
-- exports.core_dispatch:SendCall('ems', { text = 'Alarm in der Bank', pos = { x, y, z }, priority = 2, location = '...' })
Platform.Export('SendCall', function(serviceKey, options)
    local service = Disp.Service(serviceKey)
    if not service or type(options) ~= 'table' or type(options.pos) ~= 'table' then
        return nil, 'invalid_input'
    end
    local text = Disp.Text(options.text, CFG.TextMax)
    if not text then
        return nil, 'invalid_input'
    end
    local priority = math.floor(tonumber(options.priority) or 1)
    local call, err = Calls.Create(service, {
        kind = 'call', priority = PRIORITY[priority] and priority or 1, callerId = tonumber(options.callerId),
        callerName = Disp.Text(options.callerName, 101) or Platform.GetCallingResource(), text = text,
        location = Disp.Text(options.location, CFG.LocationMax),
        pos = { x = tonumber(options.pos.x) or 0, y = tonumber(options.pos.y) or 0, z = tonumber(options.pos.z) or 0 },
    })
    return call and call.number or nil, err
end)
