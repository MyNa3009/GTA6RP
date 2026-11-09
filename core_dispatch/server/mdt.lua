-- MDT der Einheiten: Einsaetze, Einheiten mit Funkstatus, Disponieren, Archiv und Statistik.
-- Einheiten im Dienst mit dispatch.view arbeiten im eigenen Dienst. dispatch.manage disponiert (zuweisen, abziehen,
-- jeden Einsatz abschliessen), dispatch.archive sieht Archiv und Statistik. Admins: /mdt <dienst>, mit
-- AdminManagePermission auch bearbeiten.

if DispatchDisabled then
    return
end

local CFG = Config.Dispatch
local STATS_DAYS = 7

local function actorOf(access)
    return { characterId = access.characterId, name = access.name, admin = access.admin or nil }
end

-- Einsatz des eigenen Dienstes
local function callOf(access, id)
    local call = Calls.Get(id)
    if not call or call.service ~= access.service then
        return nil
    end
    return call
end

local function isAssigned(access, call)
    if not access.unit then
        return false
    end
    for _, id in ipairs(call.unitIds) do
        if id == access.unit.characterId then
            return true
        end
    end
    return false
end

-- Darf am Einsatz arbeiten: zugewiesen oder Leitstelle
local function canWork(access, call)
    return access.manage or isAssigned(access, call)
end

------------------------------------------------------------------------
-- Statistik: heute und die letzten Tage
------------------------------------------------------------------------

local function stats(service)
    local today = DB.Single([[SELECT COUNT(*) AS calls,
            AVG(TIMESTAMPDIFF(SECOND, created_at, accepted_at)) AS accept,
            AVG(TIMESTAMPDIFF(SECOND, created_at, arrived_at)) AS arrive,
            SUM(result = 'abuse') AS abuse
        FROM dispatch_calls WHERE service = ? AND created_at >= CURDATE()]], { service }) or {}
    -- Tage nach der Uhr der Datenbank: ago = 0 ist heute
    local days = {}
    local rows = DB.Query([[SELECT DATEDIFF(CURDATE(), created_at) AS ago, COUNT(*) AS calls FROM dispatch_calls
        WHERE service = ? AND created_at >= CURDATE() - INTERVAL ? DAY GROUP BY ago]], { service, STATS_DAYS - 1 }) or {}
    local byAgo = {}
    for _, row in ipairs(rows) do
        byAgo[tonumber(row.ago)] = tonumber(row.calls) or 0
    end
    for ago = STATS_DAYS - 1, 0, -1 do
        days[#days + 1] = { ago = ago, calls = byAgo[ago] or 0 }
    end
    local open = #Calls.Open(service)
    return {
        today = tonumber(today.calls) or 0, open = open,
        avgAccept = today.accept and math.floor(tonumber(today.accept)) or nil,
        avgArrive = today.arrive and math.floor(tonumber(today.arrive)) or nil,
        abuse = tonumber(today.abuse) or 0, days = days, date = DB.Scalar("SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d')"),
    }
end

------------------------------------------------------------------------
-- Oeffnen
------------------------------------------------------------------------

local function list(map)
    local out = {}
    for code = 0, 9 do
        if map[code] then
            out[#out + 1] = { code = code, label = map[code] }
        end
    end
    return out
end

Disp.RegisterMdt('dispatch_mdt_open', function(source, data, access)
    if access.admin then
        Disp.SetViewer(source, access.service)
    end
    local service = Disp.Service(access.service)
    local calls = {}
    for _, call in ipairs(Calls.Open(access.service)) do
        calls[#calls + 1] = Calls.Public(call, access.admin)
    end
    local units = {}
    for _, unit in ipairs(Disp.UnitsOf(access.service)) do
        units[#units + 1] = Disp.PublicUnit(unit)
    end
    local results = {}
    for _, entry in ipairs(CFG.Results) do
        results[#results + 1] = { key = entry.key, label = entry.label, block = entry.block or nil }
    end
    return { ok = true, data = {
        now = Disp.Now(), me = access.unit and Disp.PublicUnit(access.unit) or nil,
        admin = access.admin or nil, manage = access.manage, archive = access.archive,
        service = { key = service.key, label = service.label, prefix = service.prefix },
        org = Disp.Factions('GetOrg', service.faction),
        calls = calls, units = units, statuses = list(CFG.Statuses), priorities = CFG.Priorities, results = results,
        free = CFG.FreeStatuses, stats = access.archive and stats(access.service) or nil,
        limits = { note = CFG.NoteMax, message = CFG.MessageMax, report = CFG.ReportMax, callsign = CFG.CallsignMax },
        blockMinutes = CFG.AbuseBlockMinutes,
    } }
end)

Disp.Register('dispatch_mdt_close', function(source)
    Disp.SetViewer(source, nil)
    return { ok = true }
end)

------------------------------------------------------------------------
-- Einsatz im Detail (offen oder aus dem Archiv)
------------------------------------------------------------------------

local function events(callId)
    local out = {}
    for _, row in ipairs(DB.Query('SELECT kind, actor_name, text, UNIX_TIMESTAMP(created_at) AS at FROM dispatch_events WHERE call_id = ? ORDER BY id', { callId }) or {}) do
        out[#out + 1] = { kind = row.kind, by = row.actor_name, text = row.text, at = tonumber(row.at) }
    end
    return out
end

local function archived(row, admin)
    local units = row.units and Platform.JsonDecode(row.units) or {}
    local result = Calls.Results[row.result]
    return {
        id = row.id, number = row.number, kind = row.kind, priority = row.priority, status = row.status,
        text = row.text, location = row.location, pos = { x = row.x, y = row.y, z = row.z },
        caller = ((admin or not (row.anonymous == 1 or row.anonymous == true)) and row.caller_id) and { id = row.caller_id, name = row.caller_name } or nil,
        anonymous = (row.anonymous == 1 or row.anonymous == true) or nil, callerDown = (row.caller_down == 1 or row.caller_down == true) or nil,
        createdAt = tonumber(row.created), acceptedAt = tonumber(row.accepted), arrivedAt = tonumber(row.arrived), closedAt = tonumber(row.closed),
        closedBy = row.closed_by, result = result and result.label or row.result, resultKey = row.result, report = row.report,
        units = type(units) == 'table' and units or {},
    }
end

local ARCHIVE_COLUMNS = [[id, number, kind, priority, status, caller_id, caller_name, anonymous, caller_down, text, location, x, y, z, units,
    UNIX_TIMESTAMP(created_at) AS created, UNIX_TIMESTAMP(accepted_at) AS accepted, UNIX_TIMESTAMP(arrived_at) AS arrived,
    UNIX_TIMESTAMP(closed_at) AS closed, closed_by, result, report]]

Disp.RegisterMdt('dispatch_call_get', function(source, data, access)
    local id = tonumber(data.id)
    local call = id and callOf(access, id)
    local public
    if call then
        public = Calls.Public(call, access.admin)
    else
        if not access.archive then
            return { ok = false, error = 'not_found' }
        end
        local row = id and DB.Single('SELECT ' .. ARCHIVE_COLUMNS .. ' FROM dispatch_calls WHERE id = ? AND service = ?', { id, access.service })
        if not row then
            return { ok = false, error = 'not_found' }
        end
        public = archived(row, access.admin)
    end
    -- Naechste Einheiten fuer die Leitstelle (Entfernung vom Server)
    local nearest
    if call and access.manage then
        nearest = {}
        for _, unit in ipairs(Disp.UnitsOf(access.service)) do
            local entry = Disp.PublicUnit(unit, call.pos)
            entry.free = CFG.FreeStatuses[unit.status] == true and unit.callId == nil
            nearest[#nearest + 1] = entry
        end
        table.sort(nearest, function(a, b)
            if a.free ~= b.free then
                return a.free
            end
            return (a.distance or math.huge) < (b.distance or math.huge)
        end)
    end
    return { ok = true, data = { now = Disp.Now(), call = public, events = events(id), nearest = nearest,
        assigned = call and isAssigned(access, call) or nil, canWork = call and canWork(access, call) or nil } }
end)

------------------------------------------------------------------------
-- Uebernehmen, freigeben, zuweisen
------------------------------------------------------------------------

Disp.RegisterMdt('dispatch_accept', function(source, data, access)
    if not access.unit then
        return { ok = false, error = 'not_unit' }
    end
    local call = callOf(access, data.id)
    if not call then
        return { ok = false, error = 'not_found' }
    end
    local ok, err = Calls.Assign(call, access.unit, actorOf(access))
    if not ok then
        return { ok = false, error = err }
    end
    return { ok = true, data = { call = Calls.Public(call, access.admin) } }
end)

Disp.RegisterMdt('dispatch_release', function(source, data, access)
    local call = callOf(access, data.id)
    if not call or not access.unit then
        return { ok = false, error = 'not_found' }
    end
    local ok, err = Calls.Release(call, access.unit, actorOf(access))
    if not ok then
        return { ok = false, error = err }
    end
    return { ok = true }
end)

local function unitOf(access, characterId)
    local unit = Disp.UnitByCharacter(tonumber(characterId))
    if not unit or unit.service ~= access.service then
        return nil
    end
    return unit
end

Disp.RegisterMdt('dispatch_assign', function(source, data, access)
    if not access.manage then
        return { ok = false, error = 'no_permission' }
    end
    local call = callOf(access, data.id)
    local unit = unitOf(access, data.characterId)
    if not call or not unit then
        return { ok = false, error = 'not_found' }
    end
    local ok, err
    if data.remove == true then
        ok, err = Calls.Release(call, unit, actorOf(access))
    else
        ok, err = Calls.Assign(call, unit, actorOf(access))
    end
    if not ok then
        return { ok = false, error = err }
    end
    return { ok = true }
end)

------------------------------------------------------------------------
-- Am Einsatz arbeiten: Prioritaet, Notiz, Nachricht an den Anrufer, Abschluss
------------------------------------------------------------------------

Disp.RegisterMdt('dispatch_priority', function(source, data, access)
    local call = callOf(access, data.id)
    if not call then
        return { ok = false, error = 'not_found' }
    end
    if not canWork(access, call) then
        return { ok = false, error = 'no_permission' }
    end
    local ok, err = Calls.SetPriority(call, math.floor(tonumber(data.level) or 0), actorOf(access))
    return ok and { ok = true } or { ok = false, error = err }
end)

Disp.RegisterMdt('dispatch_note', function(source, data, access)
    local call = callOf(access, data.id)
    local text = Disp.Text(data.text, CFG.NoteMax)
    if not call then
        return { ok = false, error = 'not_found' }
    end
    if not text then
        return { ok = false, error = 'invalid_input' }
    end
    Calls.Note(call, text, actorOf(access))
    return { ok = true }
end)

Disp.RegisterMdt('dispatch_message', function(source, data, access)
    local call = callOf(access, data.id)
    local text = Disp.Text(data.text, CFG.MessageMax)
    if not call then
        return { ok = false, error = 'not_found' }
    end
    if not canWork(access, call) then
        return { ok = false, error = 'no_permission' }
    end
    if not text then
        return { ok = false, error = 'invalid_input' }
    end
    local ok, err = Calls.Message(call, text, actorOf(access))
    return ok and { ok = true } or { ok = false, error = err }
end)

Disp.RegisterMdt('dispatch_close', function(source, data, access)
    local call = callOf(access, data.id)
    if not call then
        return { ok = false, error = 'not_found' }
    end
    if not canWork(access, call) then
        return { ok = false, error = 'no_permission' }
    end
    if data.result == 'cancelled' or not Calls.Results[data.result] then
        return { ok = false, error = 'invalid_result' }
    end
    local ok, err = Calls.Close(call, data.result, Disp.Text(data.report, CFG.ReportMax), actorOf(access))
    return ok and { ok = true } or { ok = false, error = err }
end)

------------------------------------------------------------------------
-- Eigene Einheit: Funkstatus, Funkrufname
------------------------------------------------------------------------

-- { status, location? }. Status 0: Notruf der Einheit an alle, Status 5: Sprechwunsch an die Leitstelle.
Disp.RegisterMdt('dispatch_status', function(source, data, access)
    local unit = access.unit
    if not unit then
        return { ok = false, error = 'not_unit' }
    end
    local status = tonumber(data.status)
    if not status or status ~= math.floor(status) or not CFG.Statuses[status] then
        return { ok = false, error = 'invalid_status' }
    end
    local old = Disp.SetStatus(unit, status)
    if status == 0 and old ~= 0 then
        local pos = Platform.GetPlayerPosition(source)
        local service = Disp.Service(unit.service)
        if pos then
            Calls.Create(service, {
                kind = 'unit', priority = #CFG.Priorities, callerId = unit.characterId, callerName = unit.name,
                text = ('%s braucht sofort Hilfe'):format(unit.callsign and (unit.callsign .. ', ' .. unit.name) or unit.name),
                location = Disp.Text(data.location, CFG.LocationMax), pos = pos,
                actor = { characterId = unit.characterId, name = unit.name },
            })
        end
    elseif status == 5 then
        for _, receiver in ipairs(Disp.Receivers(unit.service)) do
            Network.SendToClient(receiver.source, 'core_dispatch:talk', { name = unit.name, callsign = unit.callsign, id = unit.characterId })
        end
    end
    if old ~= status then
        Disp.Protocol(unit.faction, { area = 'dienst', action = 'status', actorId = unit.characterId, actorName = unit.name,
            target = unit.characterId, text = ('Funkstatus %d: %s'):format(status, CFG.Statuses[status]) })
    end
    return { ok = true, data = { status = status } }
end)

Disp.RegisterMdt('dispatch_callsign', function(source, data, access)
    local unit = access.unit
    if not unit then
        return { ok = false, error = 'not_unit' }
    end
    local callsign = Disp.Text(data.callsign, CFG.CallsignMax)
    unit.callsign = callsign
    DB.Update('INSERT INTO dispatch_units (character_id, callsign) VALUES (?, ?) ON DUPLICATE KEY UPDATE callsign = VALUES(callsign)',
        DB.Args(unit.characterId, callsign))
    Disp.PushSelf(unit)
    Disp.PushUnits(unit.service)
    return { ok = true, data = { callsign = callsign } }
end)

------------------------------------------------------------------------
-- Archiv und Statistik
------------------------------------------------------------------------

-- { page, search?, result? }. search: Einsatznummer, permanente ID des Anrufers oder Text
Disp.RegisterMdt('dispatch_archive', function(source, data, access)
    if not access.archive then
        return { ok = false, error = 'no_permission' }
    end
    local size = CFG.HistoryPageSize
    local page = math.max(1, math.floor(tonumber(data.page) or 1))
    local search = Disp.Text(data.search, 40)
    local where, args = "service = ? AND status = 'closed'", { access.service }
    if Calls.Results[data.result] then
        where = where .. ' AND result = ?'
        args[#args + 1] = data.result
    end
    if search and tonumber(search) then
        where = where .. ' AND caller_id = ?'
        args[#args + 1] = tonumber(search)
    elseif search and search:match('%d+/%d+') then
        where = where .. ' AND number LIKE ?'
        args[#args + 1] = '%' .. search:match('%d+/%d+') .. '%'
    elseif search then
        where = where .. ' AND text LIKE ?'
        args[#args + 1] = '%' .. search:gsub('[%%_\\]', '\\%0') .. '%'
    end
    args[#args + 1] = size + 1
    args[#args + 1] = (page - 1) * size
    local rows = DB.Query('SELECT ' .. ARCHIVE_COLUMNS .. ' FROM dispatch_calls WHERE ' .. where .. ' ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?', args) or {}
    local list = {}
    for index = 1, math.min(#rows, size) do
        list[#list + 1] = archived(rows[index], access.admin)
    end
    return { ok = true, data = { entries = list, page = page, more = #rows > size, stats = stats(access.service) } }
end)
