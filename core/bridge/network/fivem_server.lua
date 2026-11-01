-- Netzwerk-Bridge (Server) fuer FiveM.
-- Callbacks: Der Client fragt etwas an, der Server antwortet genau einmal.
-- Die Bridge prueft nichts inhaltlich, das macht die Core (Core.RegisterCallback).

Network = {}

-- Pro Resource eigene Events (core:cb:request, core_inventory:cb:request ...), damit mehrere Resources diese Bridge nutzen koennen
local RESOURCE = GetCurrentResourceName()
local REQUEST_EVENT = RESOURCE .. ':cb:request'
local RESPONSE_EVENT = RESOURCE .. ':cb:response'

local callbacks = {}

-- Schutz vor Spam: hoechstens so viele Anfragen pro Spieler und Sekunde
local RATE_WINDOW_MS = 1000
local buckets = {}       -- [source] = { start, count }
local rateHandler = nil  -- function(source, callbackName), von der Core gesetzt

-- Die Core meldet sich hier fuer das Log an
function Network.OnRateLimited(handler)
    rateHandler = handler
end

local function allowed(src, name)
    local limit = Config.Network.MaxRequestsPerSecond
    if not limit or limit <= 0 then
        return true
    end
    local now = GetGameTimer()
    local bucket = buckets[src]
    if not bucket or now - bucket.start >= RATE_WINDOW_MS then
        buckets[src] = { start = now, count = 1 }
        return true
    end
    bucket.count = bucket.count + 1
    if bucket.count > limit then
        if bucket.count == limit + 1 and rateHandler then
            rateHandler(src, name)
        end
        return false
    end
    return true
end

AddEventHandler('playerDropped', function()
    buckets[tonumber(source) or source] = nil
end)

function Network.RegisterCallback(name, handler)
    callbacks[name] = handler
end

function Network.SendToClient(source, event, data)
    TriggerClientEvent(event, source, data)
end

-- Oeffentlicher Wert am Spieler, den alle Clients lesen koennen (z. B. die ID ueber dem Kopf)
function Network.SetPlayerPublic(source, key, value)
    local ok, err = pcall(function()
        Player(source).state:set(key, value, true)
    end)
    if not ok then
        Platform.Print('warn', ('Statebag %s fuer %s nicht gesetzt: %s'):format(key, tostring(source), tostring(err)))
    end
end

RegisterNetEvent(REQUEST_EVENT, function(name, requestId, data)
    local src = source

    if type(name) ~= 'string' or type(requestId) ~= 'number' then
        return
    end
    if type(data) ~= 'table' then
        data = {}
    end

    local function reply(result)
        TriggerClientEvent(RESPONSE_EVENT, src, requestId, result)
    end

    if not allowed(src, name) then
        reply({ ok = false, error = 'rate_limited' })
        return
    end

    local handler = callbacks[name]
    if not handler then
        reply({ ok = false, error = 'unknown_callback' })
        return
    end

    CreateThread(function()
        local ok, result = pcall(handler, src, data)
        if not ok then
            Platform.Print('error', ('Fehler im Callback %s: %s'):format(name, tostring(result)))
            result = { ok = false, error = 'server_error' }
        end
        reply(result or { ok = true })
    end)
end)
