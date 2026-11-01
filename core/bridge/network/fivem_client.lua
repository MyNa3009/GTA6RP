-- Netzwerk-Bridge (Client) fuer FiveM.
-- Network.Call wartet auf die Antwort des Servers und gibt { ok, data, error } zurueck.

Network = {}

-- Pro Resource eigene Events, passend zur Server-Bridge
local RESOURCE = GetCurrentResourceName()
local REQUEST_EVENT = RESOURCE .. ':cb:request'
local RESPONSE_EVENT = RESOURCE .. ':cb:response'

local pending = {}
local nextRequestId = 0

RegisterNetEvent(RESPONSE_EVENT, function(requestId, result)
    local request = pending[requestId]
    if request then
        pending[requestId] = nil
        request:resolve(result)
    end
end)

function Network.Call(name, data)
    nextRequestId = nextRequestId + 1
    local requestId = nextRequestId
    local request = promise.new()
    pending[requestId] = request

    TriggerServerEvent(REQUEST_EVENT, name, requestId, data or {})

    SetTimeout(Config.Network.CallbackTimeoutMs, function()
        if pending[requestId] then
            pending[requestId] = nil
            request:resolve({ ok = false, error = 'timeout' })
        end
    end)

    return Citizen.Await(request)
end

function Network.On(event, handler)
    RegisterNetEvent(event, handler)
end

-- Liest einen oeffentlichen Wert eines Spielers (vom Server gesetzt)
function Network.GetPlayerPublic(serverId, key)
    local player = Player(serverId)
    return player and player.state and player.state[key] or nil
end
