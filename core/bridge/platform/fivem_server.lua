-- Plattform-Bridge (Server) fuer FiveM.
-- Nur hier duerfen FiveM-Natives stehen. Fuer eine neue Plattform wird diese
-- Datei ersetzt, alle Funktionen behalten Namen und Verhalten.

Platform = {}

local RESOURCE_NAME = GetCurrentResourceName()

local LEVEL_COLORS = {
    info  = '^5',
    ok    = '^2',
    warn  = '^3',
    error = '^1',
}

function Platform.Print(level, message)
    print(('%s[%s] %s^7'):format(LEVEL_COLORS[level] or '^7', RESOURCE_NAME, message))
end

function Platform.GetConvar(name, default)
    return GetConvar(name, default)
end

-- Welches Script hat die Core gerade aufgerufen (fuer das Log)
function Platform.GetCallingResource()
    return GetInvokingResource() or RESOURCE_NAME
end

function Platform.Async(fn)
    CreateThread(fn)
end

function Platform.Wait(ms)
    Wait(ms)
end

function Platform.DropPlayer(source, reason)
    DropPlayer(tostring(source), reason)
end

function Platform.SetInterval(intervalMs, fn)
    CreateThread(function()
        while true do
            Wait(intervalMs)
            fn()
        end
    end)
end

function Platform.OnResourceStop(fn)
    AddEventHandler('onResourceStop', function(name)
        if name == RESOURCE_NAME then
            fn()
        end
    end)
end

function Platform.GetPlayers()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        list[#list + 1] = tonumber(id)
    end
    return list
end

function Platform.GetPlayerCount()
    return #GetPlayers()
end

function Platform.GetMaxPlayers()
    return GetConvarInt('sv_maxclients', 32)
end

function Platform.GetPlayerName(source)
    return GetPlayerName(source) or ('Spieler ' .. tostring(source))
end

function Platform.HashPassword(password)
    return GetPasswordHash(password)
end

function Platform.VerifyPassword(password, hash)
    return VerifyPasswordHash(password, hash)
end

-- Zufaelliger Text aus TOKEN_ALPHABET (z. B. fuer Admin-Keys). Ohne 0, O, 1 und I, damit man nichts verwechselt.
-- Zufall aus zwei Quellen: dem zufaelligen Salt von bcrypt (GetPasswordHash) und math.random.
local TOKEN_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' -- genau 32 Zeichen
local BCRYPT_CHARS = './ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
local BCRYPT_PREFIX_LENGTH = 7 -- "$2a$10$"
local INT_MAX = 2147483647

function Platform.RandomToken(length)
    local size = #TOKEN_ALPHABET
    local out = {}
    while #out < length do
        local hash = GetPasswordHash(('%d:%.6f:%d'):format(os.time(), os.clock(), math.random(1, INT_MAX)))
        for i = BCRYPT_PREFIX_LENGTH + 1, #hash do
            if #out >= length then
                break
            end
            local index = BCRYPT_CHARS:find(hash:sub(i, i), 1, true)
            if index then
                local value = ((index - 1) + math.random(0, size - 1)) % size
                out[#out + 1] = TOKEN_ALPHABET:sub(value + 1, value + 1)
            end
        end
    end
    return table.concat(out)
end

function Platform.JsonEncode(value)
    return json.encode(value)
end

-- Gibt nil zurueck, wenn der Text kein gueltiges JSON ist
function Platform.JsonDecode(text)
    if type(text) ~= 'string' or text == '' then
        return nil
    end
    local ok, value = pcall(json.decode, text)
    if ok then
        return value
    end
    return nil
end

local function round(value, factor)
    return math.floor(value * factor + 0.5) / factor
end

-- Position des Spielers oder nil, wenn es gerade keine gueltige gibt (braucht OneSync)
function Platform.GetPlayerPosition(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)
    if not coords or (coords.x == 0.0 and coords.y == 0.0) then
        return nil
    end

    return {
        x = round(coords.x, 100),
        y = round(coords.y, 100),
        z = round(coords.z, 100),
        heading = round(GetEntityHeading(ped), 10),
    }
end

-- Loescht ein vernetztes Fahrzeug (braucht OneSync). Gibt true zurueck, wenn es eins war.
local ENTITY_TYPE_VEHICLE = 2

function Platform.DeleteNetworkedVehicle(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= ENTITY_TYPE_VEHICLE then
        return false
    end
    DeleteEntity(entity)
    return true
end

-- Fahrzeuge im Umkreis (braucht OneSync). Nur aus derselben Dimension. Gibt eine Liste von Netz-IDs zurueck.
function Platform.GetVehiclesNear(position, radius, dimension)
    local list = {}
    local radiusSq = radius * radius
    for _, vehicle in ipairs(GetAllVehicles()) do
        if GetEntityRoutingBucket(vehicle) == (dimension or 0) then
            local coords = GetEntityCoords(vehicle)
            local dx, dy, dz = coords.x - position.x, coords.y - position.y, coords.z - position.z
            if dx * dx + dy * dy + dz * dz <= radiusSq then
                list[#list + 1] = NetworkGetNetworkIdFromEntity(vehicle)
            end
        end
    end
    return list
end

-- Wer ein vernetztes Fahrzeug gerade steuert (nur dessen Client kann es reparieren). Gibt die Server-ID oder nil zurueck.
function Platform.GetVehicleOwner(netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= ENTITY_TYPE_VEHICLE then
        return nil
    end
    local owner = NetworkGetEntityOwner(entity)
    if not owner or owner <= 0 then
        return nil
    end
    return owner
end

-- Fahrzeug ueber die Netzwerk-ID: Kennzeichen, abgeschlossen, Position. nil, wenn es das Fahrzeug nicht gibt.
local VEHICLE_LOCKED_FROM = 2 -- GTA: 0/1 offen, ab 2 abgeschlossen

function Platform.GetVehicleInfo(netId)
    if not netId then
        return nil
    end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= ENTITY_TYPE_VEHICLE then
        return nil
    end
    local coords = GetEntityCoords(entity)
    return {
        plate = GetVehicleNumberPlateText(entity),
        locked = GetVehicleDoorLockStatus(entity) >= VEHICLE_LOCKED_FROM,
        position = { x = coords.x, y = coords.y, z = coords.z },
    }
end

-- Dimension (Routing Bucket) eines Spielers, 0 ist die normale Welt
function Platform.GetPlayerDimension(source)
    local ok, bucket = pcall(GetPlayerRoutingBucket, source)
    return ok and tonumber(bucket) or 0
end

-- Dimension (Routing Bucket) setzen. 0 ist die normale Welt. Wer am Steuer sitzt, nimmt sein Fahrzeug mit.
local DRIVER_SEAT = -1

function Platform.SetPlayerDimension(source, dimension)
    local ok, err = pcall(function()
        local ped = GetPlayerPed(source)
        local vehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
        SetPlayerRoutingBucket(source, dimension)
        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, DRIVER_SEAT) == ped then
            SetEntityRoutingBucket(vehicle, dimension)
        end
    end)
    if not ok then
        Platform.Print('warn', ('Dimension fuer %s nicht gesetzt: %s'):format(tostring(source), tostring(err)))
    end
end

local NOTIFY_EVENT = 'core:notify'
local CONSOLE_LEVELS = { error = 'error', warning = 'warn', success = 'ok', info = 'info' }

-- Meldung im Notify-UI des Spielers. tone: 'info' (Standard), 'success', 'error', 'warning' oder 'message'
-- title: optionale erste Zeile, z. B. "Teamnachricht von Fabian Nandes"
function Platform.Notify(source, message, tone, title)
    if source == 0 then
        Platform.Print(CONSOLE_LEVELS[tone] or 'info', title and (title .. ': ' .. message) or message)
        return
    end
    TriggerClientEvent(NOTIFY_EVENT, source, { text = message, type = tone or 'info', title = title })
end

-- Befehle laufen in einem eigenen Thread, damit Datenbank-Abfragen darin warten koennen
function Platform.RegisterCommand(name, handler)
    RegisterCommand(name, function(source, args)
        CreateThread(function()
            handler(source, args)
        end)
    end, false)
end

function Platform.Export(name, fn)
    exports(name, fn)
end

-- Ereignis an andere Resources auf dem Server (z. B. core:characterLoaded)
function Platform.Emit(event, ...)
    TriggerEvent(event, ...)
end

function Platform.OnEvent(event, handler)
    AddEventHandler(event, handler)
end

-- Versionsnummer aus dem fxmanifest einer Resource, ohne Angabe die eigene
function Platform.GetResourceVersion(name)
    local ok, version = pcall(GetResourceMetadata, name or RESOURCE_NAME, 'version', 0)
    return ok and version or nil
end

-- Laeuft eine andere Resource gerade?
function Platform.IsResourceStarted(name)
    return GetResourceState(name) == 'started'
end

-- Export einer anderen Resource aufrufen. Gibt nil zurueck, wenn sie nicht laeuft oder einen Fehler wirft.
function Platform.CallExport(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then
        return nil
    end
    local args = table.pack(...)
    local results = table.pack(pcall(function()
        local target = exports[resource]
        return target[name](target, table.unpack(args, 1, args.n))
    end))
    if not results[1] then
        Platform.Print('error', ('Export %s:%s fehlgeschlagen: %s'):format(resource, name, tostring(results[2])))
        return nil
    end
    return table.unpack(results, 2, results.n)
end
