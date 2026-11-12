-- Grundlage von core_dispatch auf dem Server: Dienste, Einheiten im Dienst mit Funkstatus, Rechte ueber core_factions,
-- Senden an die Clients, Protokoll und Log. Notrufe stehen in calls.lua, das MDT in mdt.lua.
-- Der Server entscheidet alles: Position, Zeiten, Rechte. Ortsnamen vom Client sind nur Anzeige.

-- Braucht Core 1.15.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.15.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Export', 'GetPlayerPosition', 'GetPlayerDimension', 'IsResourceStarted',
    'Notify', 'OnEvent', 'Print', 'SetInterval', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_dispatch: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    DispatchDisabled = true
    return
end

Disp = { Ready = false }

local CFG = Config.Dispatch
local CORE = 'core'
local FACTIONS = 'core_factions'

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

function Disp.Core(name, ...)
    return Platform.CallExport(CORE, name, ...)
end

function Disp.Factions(name, ...)
    return Platform.CallExport(FACTIONS, name, ...)
end

-- Nutzertext: Steuerzeichen raus, Leerraum aussen weg, auf maxLength Zeichen kuerzen. Leer: nil
function Disp.Text(value, maxLength)
    if type(value) ~= 'string' then
        return nil
    end
    value = value:gsub('[%c]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if value == '' or not utf8.len(value) then
        return nil
    end
    if utf8.len(value) > maxLength then
        value = value:sub(1, utf8.offset(value, maxLength + 1) - 1)
    end
    return value
end

function Disp.Now()
    return os.time()
end

function Disp.NameOf(source)
    local info = Disp.Core('GetCharacterInfo', source)
    if type(info) ~= 'table' then
        return nil
    end
    return ('%s %s'):format(info.firstname, info.lastname)
end

function Disp.CharacterOf(source)
    return tonumber(Disp.Core('GetCharacterId', source))
end

function Disp.Log(entry)
    entry.category = 'dispatch'
    Disp.Core('Log', entry)
end

-- Eintrag im Protokoll der Organisation (Bereich Einsatz), siehe core_factions
function Disp.Protocol(faction, entry)
    entry.area = entry.area or 'einsatz'
    Disp.Factions('AddProtocol', faction, entry)
end

function Disp.Distance(a, b)
    if not a or not b then
        return nil
    end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

------------------------------------------------------------------------
-- Dienste
------------------------------------------------------------------------

local services, byFaction, byWord = {}, {}, {}
for _, service in ipairs(CFG.Services) do
    services[service.key] = service
    byFaction[service.faction] = service
    for _, word in ipairs(service.words or { service.key }) do
        byWord[word:lower()] = service
    end
end

function Disp.Service(key)
    return type(key) == 'string' and services[key] or nil
end

function Disp.ServiceOfFaction(faction)
    return byFaction[faction]
end

function Disp.ServiceByWord(word)
    return type(word) == 'string' and byWord[word:lower()] or nil
end

function Disp.Services()
    return CFG.Services
end

------------------------------------------------------------------------
-- Einheiten: wer im Dienst ist und das MDT nutzen darf, mit Funkstatus
------------------------------------------------------------------------

local units = {}        -- [source] = { source, characterId, name, dn, callsign, service, faction, status, since, callId }
local viewers = {}      -- [source] = service: Admins mit offenem MDT

function Disp.Unit(source)
    return units[tonumber(source)]
end

function Disp.UnitByCharacter(characterId)
    for _, unit in pairs(units) do
        if unit.characterId == characterId then
            return unit
        end
    end
    return nil
end

function Disp.UnitsOf(service)
    local list = {}
    for _, unit in pairs(units) do
        if unit.service == service then
            list[#list + 1] = unit
        end
    end
    table.sort(list, function(a, b) return a.characterId < b.characterId end)
    return list
end

function Disp.SetViewer(source, service)
    viewers[tonumber(source)] = service
end

-- Darf diese Person das MDT ihres Dienstes nutzen? (im Dienst, Recht dispatch.view)
local function canUse(source, member)
    return member.onDuty == true and Disp.Factions('HasPermission', source, 'dispatch.view', true) == true
end

function Disp.PublicUnit(unit, from)
    return {
        id = unit.characterId, name = unit.name, dn = unit.dn, callsign = unit.callsign, status = unit.status,
        since = unit.since, callId = unit.callId,
        distance = from and math.floor(Disp.Distance(Platform.GetPlayerPosition(unit.source), from) or -1) or nil,
    }
end

-- Alle Empfaenger eines Dienstes: Einheiten im Dienst und Admins mit offenem MDT
function Disp.Receivers(service)
    local list = {}
    for source, unit in pairs(units) do
        if unit.service == service then
            list[#list + 1] = { source = source, admin = false }
        end
    end
    for source, viewing in pairs(viewers) do
        if viewing == service and not units[source] then
            list[#list + 1] = { source = source, admin = true }
        end
    end
    return list
end

function Disp.PushUnits(service)
    local list = {}
    for _, unit in ipairs(Disp.UnitsOf(service)) do
        list[#list + 1] = Disp.PublicUnit(unit)
    end
    for _, receiver in ipairs(Disp.Receivers(service)) do
        Network.SendToClient(receiver.source, 'core_dispatch:units', { service = service, units = list })
    end
end

function Disp.PushSelf(unit)
    Network.SendToClient(unit.source, 'core_dispatch:self', {
        service = unit.service, status = unit.status, callId = unit.callId, callsign = unit.callsign,
    })
end

-- Status setzen (ohne Pruefung, die macht der Aufrufer). Gibt den alten Status zurueck.
function Disp.SetStatus(unit, status)
    local old = unit.status
    if old ~= status then
        unit.status, unit.since = status, Disp.Now()
        Disp.PushSelf(unit)
        Disp.PushUnits(unit.service)
    end
    return old
end

-- Wird von calls.lua ueberschrieben: Einheit aus ihrem Einsatz nehmen (Dienstende)
function Disp.OnUnitGone(unit) end

local function addUnit(source)
    source = tonumber(source)
    local member = Disp.Factions('GetMember', source)
    if type(member) ~= 'table' then
        return
    end
    local service = Disp.ServiceOfFaction(member.faction)
    if not service or not canUse(source, member) then
        return
    end
    local characterId = tonumber(member.characterId) or Disp.CharacterOf(source)
    local unit = {
        source = source, characterId = characterId, name = Disp.NameOf(source) or ('ID ' .. tostring(characterId)),
        dn = member.dn, service = service.key, faction = member.faction, status = CFG.StatusOnDuty, since = Disp.Now(),
        callsign = DB.Scalar('SELECT callsign FROM dispatch_units WHERE character_id = ?', { characterId }),
    }
    units[source] = unit
    viewers[source] = nil
    Disp.PushSelf(unit)
    Disp.PushUnits(service.key)
    Disp.SendOpenCalls(unit)
end

local function removeUnit(source)
    source = tonumber(source)
    local unit = units[source]
    if not unit then
        return
    end
    Disp.OnUnitGone(unit)
    units[source] = nil
    Network.SendToClient(source, 'core_dispatch:self', { service = nil })
    Disp.PushUnits(unit.service)
end

Disp.AddUnit, Disp.RemoveUnit = addUnit, removeUnit

-- Wird von calls.lua ueberschrieben: offene Einsaetze an eine neue Einheit schicken
function Disp.SendOpenCalls(unit) end

Platform.OnEvent('core_factions:duty', function(source, faction, onDuty)
    Platform.Async(function()
        while not Disp.Ready do
            Platform.Wait(100)
        end
        if onDuty then
            addUnit(source)
        else
            removeUnit(source)
        end
    end)
end)

Platform.OnEvent('core:characterUnloaded', function(source)
    removeUnit(source)
    viewers[tonumber(source)] = nil
end)

-- Rechte in core_factions anmelden (erscheinen im Organisationsmenue)
local function registerPermissions()
    if not Platform.IsResourceStarted(FACTIONS) then
        return
    end
    for _, service in ipairs(CFG.Services) do
        Disp.Factions('RegisterPermissions', service.faction, CFG.Permissions)
    end
end

-- Alle, die schon im Dienst sind (Neustart von core_dispatch)
local function collectUnits()
    for _, service in ipairs(CFG.Services) do
        for _, source in ipairs(Disp.Factions('GetOnDuty', service.faction) or {}) do
            addUnit(source)
        end
    end
end

Platform.OnEvent('onResourceStart', function(resource)
    if resource == FACTIONS then
        Platform.Async(function()
            Platform.Wait(500)
            registerPermissions()
            collectUnits()
        end)
    end
end)

------------------------------------------------------------------------
-- Zugriff aufs MDT
------------------------------------------------------------------------

-- Gibt { unit, service, faction, manage, archive, admin } zurueck oder nil und einen Fehlercode.
-- wanted: Dienst, den ein Admin ansehen will (Einheiten sehen immer ihren eigenen).
function Disp.Access(source, wanted)
    local unit = units[tonumber(source)]
    if unit then
        local adminManage = Disp.Core('HasPermission', source, CFG.AdminManagePermission) == true
        return {
            unit = unit, service = unit.service, faction = unit.faction,
            manage = adminManage or Disp.Factions('HasPermission', source, 'dispatch.manage', true) == true,
            archive = adminManage or Disp.Factions('HasPermission', source, 'dispatch.archive', true) == true,
            name = unit.name, characterId = unit.characterId,
        }
    end
    local service = Disp.Service(wanted) or Disp.Service(viewers[tonumber(source)])
    if Disp.Core('HasPermission', source, CFG.AdminViewPermission) == true then
        if not service then
            return nil, 'invalid_service'
        end
        local manage = Disp.Core('HasPermission', source, CFG.AdminManagePermission) == true
        return {
            admin = true, service = service.key, faction = service.faction, manage = manage, archive = true,
            name = ('Admin %s'):format(Disp.NameOf(source) or ''), characterId = Disp.CharacterOf(source),
        }
    end
    local member = Disp.Factions('GetMember', source)
    if type(member) ~= 'table' or not Disp.ServiceOfFaction(member.faction) then
        return nil, 'not_member'
    end
    if not member.onDuty then
        return nil, 'not_on_duty'
    end
    return nil, 'no_permission'
end

-- Callback mit Pruefung, ob ein Charakter spielt, und Fehlerschutz
function Disp.Register(name, handler)
    Network.RegisterCallback(name, function(source, data)
        if not Disp.Ready then
            return { ok = false, error = 'not_ready' }
        end
        if not Disp.CharacterOf(source) then
            return { ok = false, error = 'no_character' }
        end
        local ok, result = pcall(handler, source, type(data) == 'table' and data or {})
        if not ok then
            Platform.Print('error', ('core_dispatch: Fehler in %s: %s'):format(name, tostring(result)))
            return { ok = false, error = 'server_error' }
        end
        return result
    end)
end

-- Wie Register, aber nur mit Zugriff aufs MDT. handler(source, data, access)
function Disp.RegisterMdt(name, handler)
    Disp.Register(name, function(source, data)
        local access, err = Disp.Access(source, data.service)
        if not access then
            return { ok = false, error = err }
        end
        return handler(source, data, access)
    end)
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------

-- Wird von calls.lua ueberschrieben: offene Einsaetze aus der Datenbank laden
function Disp.LoadCalls() end

DB.Ready(function()
    for _, statement in ipairs(DispatchSchema) do
        if DB.Query(statement) == nil then
            Platform.Print('error', 'core_dispatch: Tabellen konnten nicht angelegt werden. Bitte database/dispatch.sql ausfuehren.')
            return
        end
    end
    Disp.LoadCalls()
    Disp.Ready = true
    registerPermissions()
    collectUnits()
end)
