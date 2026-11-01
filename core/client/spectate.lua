-- Beobachten auf dem Client. Der Server entscheidet, wer wen beobachten darf, und schickt Start und Ende.
-- Damit der Spieler geladen bleibt, wird der eigene (versteckte) Ped immer in seiner Naehe gehalten.

SpectateClient = {}

local CHECK_MS = 500
local KEEP_CLOSE_DISTANCE = 60.0  -- weiter weg: eigenen Ped nachziehen
local BELOW_TARGET = 8.0          -- versteckter Ped etwas unter dem Spieler, damit er niemandem im Weg ist
local LOST_TIMEOUT_MS = 10000     -- so lange wird gewartet, bis der Spieler geladen ist

local current = nil -- { serverId, characterId, name }

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function below(position)
    return { x = position.x, y = position.y, z = position.z - BELOW_TARGET }
end

local function watch(session)
    local attachedPed = nil
    local lostSince = Platform.GetTime()
    while current == session do
        local ped = Platform.GetPlayerPedByServerId(session.serverId)
        if ped then
            lostSince = nil
            if ped ~= attachedPed then
                Platform.SetSpectating(ped)
                attachedPed = ped
            end
            local target = Platform.GetEntityPosition(ped)
            if distance(Platform.GetEntityPosition(Platform.GetOwnPed()), target) > KEEP_CLOSE_DISTANCE then
                Platform.MoveOwnPedTo(below(target))
            end
        else
            lostSince = lostSince or Platform.GetTime()
            if Platform.GetTime() - lostSince > LOST_TIMEOUT_MS then
                Notify.Show('Der Spieler ist nicht in Reichweite geladen. Beobachten beendet.', 'error')
                Network.Call('admin_spectate_stop', {})
                return
            end
        end
        Platform.Wait(CHECK_MS)
    end
end

local function start(data)
    if Noclip then
        Noclip.Stop(true)
    end
    local switching = current ~= nil
    current = { serverId = data.serverId, characterId = data.characterId, name = data.name }
    if not switching then
        Platform.SetSpectatorHidden(true)
    end
    if type(data.position) == 'table' and tonumber(data.position.x) then
        Platform.MoveOwnPedTo(below(data.position))
    end
    local session = current
    Platform.Async(function()
        watch(session)
    end)
end

local function stop(position)
    if not current then
        return
    end
    current = nil
    Platform.SetSpectating(nil)
    Platform.SetSpectatorHidden(false)
    if type(position) == 'table' and tonumber(position.x) then
        Platform.TeleportTo(position)
    end
end

Network.On('core:admin:spectate', function(data)
    if type(data) ~= 'table' then
        return
    end
    Platform.Async(function()
        if data.on then
            start(data)
        else
            stop(data.position)
        end
    end)
end)

function SpectateClient.IsActive()
    return current ~= nil
end

-- Beim Ausloggen oder Charakterwechsel: nur lokal aufraeumen, der Server weiss Bescheid
function SpectateClient.Reset()
    stop(nil)
end
