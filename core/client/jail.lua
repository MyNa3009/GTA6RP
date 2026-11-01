-- A-Jail auf dem Client: Anzeige mit Restzeit, Kampfsperre, Teleports vom Server.
-- Ob jemand drin ist und wann er raus darf, entscheidet nur der Server.

JailHud = {}

local jailed = false

local function open(info)
    Client.uiOpen('jail', 'jail_open', {
        colors = Config.UI.Colors,
        remaining = info and info.remaining or 0,
        total = info and info.total or 0,
        reason = info and info.reason or nil,
        by = info and info.by or nil,
    }, false)
end

-- Laeuft nur, solange man im A-Jail ist
local function combatLoop()
    while jailed do
        Platform.Wait(0)
        Platform.DisableCombatThisFrame()
    end
end

local function start(info)
    if Noclip then
        Noclip.Stop(true)
    end
    open(info)
    if jailed then
        return
    end
    jailed = true
    if Config.Jail.DisableCombat then
        Platform.Async(combatLoop)
    end
end

-- Beim Spawn eines Charakters, der im A-Jail sitzt
function JailHud.OnSpawn(info)
    if info then
        start(info)
    end
end

-- Beim Ausloggen oder Zurueck in die Charakterauswahl
function JailHud.Reset()
    if not jailed then
        return
    end
    jailed = false
    Client.uiClose('jail', 'jail_close')
end

function JailHud.IsJailed()
    return jailed
end

-- Vom Server: ab ins A-Jail (wer bewusstlos war, wacht dort auf)
Network.On('core:jail:start', function(data)
    if type(data) ~= 'table' or type(data.position) ~= 'table' then
        return
    end
    Platform.Async(function()
        if data.revive or Client.state.dead then
            Platform.RespawnAt(data.position)
            Death.Reset()
        else
            Platform.TeleportTo(data.position)
        end
        start(data.jail)
    end)
end)

Network.On('core:jail:sync', function(data)
    if jailed and type(data) == 'table' then
        Platform.UiSend('jail_update', { remaining = data.remaining })
    end
end)

-- Vom Server: zu weit weg, zurueck
Network.On('core:jail:return', function(data)
    if not jailed or type(data) ~= 'table' or type(data.position) ~= 'table' then
        return
    end
    Platform.Async(function()
        if Noclip then
            Noclip.Stop(true)
        end
        Platform.TeleportTo(data.position)
        Notify.Show('Du kannst das A-Jail nicht verlassen.', 'error')
    end)
end)

-- Vom Server: Zeit vorbei oder entlassen. Wer gerade bewusstlos ist, bleibt liegen
-- und wacht danach ganz normal im Krankenhaus auf.
Network.On('core:jail:end', function(data)
    JailHud.Reset()
    if Client.state.dead or type(data) ~= 'table' or type(data.position) ~= 'table' then
        return
    end
    Platform.Async(function()
        Platform.TeleportTo(data.position)
    end)
end)
