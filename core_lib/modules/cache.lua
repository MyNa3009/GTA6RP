-- Haeufig gebrauchte Werte des eigenen Spielers, einmal pro Intervall gelesen statt in jedem Script einzeln.
-- Im fxmanifest nach der Bridge der Core und init.lua in die client_scripts: '@core_lib/modules/cache.lua'
--
--   lib.cache.vehicle      Fahrzeug, in dem man sitzt, oder nil
--   lib.cache.seat         Sitz im Fahrzeug oder nil
--   lib.cache.isDriver     true am Steuer
--   lib.cache.coords       { x, y, z }
--   lib.cache.serverId, lib.cache.characterId (permanente ID, nil ohne Charakter), lib.cache.dead
--   lib.onCache('vehicle', function(neu, alt) end)   wird bei jeder Aenderung aufgerufen

lib = lib or {}
if lib.cache then
    return
end

local INTERVAL_MS = 250
local WATCHED = { 'vehicle', 'seat', 'isDriver', 'characterId', 'dead' }

lib.cache = {}
local listeners = {}   -- [schluessel] = { fn, ... }

function lib.onCache(key, fn)
    if type(key) ~= 'string' or type(fn) ~= 'function' then
        return false
    end
    listeners[key] = listeners[key] or {}
    listeners[key][#listeners[key] + 1] = fn
    return true
end

local function set(key, value)
    local old = lib.cache[key]
    if old == value then
        return
    end
    lib.cache[key] = value
    for _, fn in ipairs(listeners[key] or {}) do
        local ok, err = pcall(fn, value, old)
        if not ok then
            Platform.Print('error', ('lib.onCache(%s): %s'):format(key, tostring(err)))
        end
    end
end

local function update()
    lib.cache.coords = Platform.GetOwnPosition()
    local serverId = Platform.GetOwnServerId()
    lib.cache.serverId = serverId
    set('characterId', Network.GetPlayerPublic(serverId, 'coreId'))
    set('dead', Platform.IsOwnPedDead())
    local state = Platform.GetOwnVehicleState()
    set('vehicle', state and state.vehicle or nil)
    set('seat', state and state.seat or nil)
    set('isDriver', state and state.isDriver or false)
end

update()
Platform.Async(function()
    while true do
        Platform.Wait(INTERVAL_MS)
        update()
    end
end)

-- Fuer die README: diese Schluessel loesen lib.onCache aus
lib.cacheKeys = WATCHED
