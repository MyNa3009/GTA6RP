-- Bewusstlosigkeit: liegen bleiben, Countdown, Taste halten fuers Krankenhaus.
-- Die Zeit prueft der Server, der Client zeigt nur an.

Death = {}

local dying = {
    active = false,
    readyAt = 0,       -- Spielzeit in ms, ab der das Krankenhaus erlaubt ist
    holdStart = nil,   -- Spielzeit in ms, seit der die Taste gehalten wird
    requesting = false,
}

local MS_PER_SECOND = 1000

local function setReadyIn(seconds)
    dying.readyAt = Platform.GetTime() + seconds * MS_PER_SECOND
end

function Death.Reset()
    dying.active = false
    dying.holdStart = nil
    dying.requesting = false
    Client.state.dead = false
    Client.uiClose('death', 'death_close')
end

local function requestHospital()
    dying.requesting = true
    local result = Network.Call('death_respawn', {})

    if result and result.ok and result.data and result.data.position then
        Platform.RespawnAt(result.data.position)
        Death.Reset()
        return
    end

    dying.requesting = false
    if result and result.error == 'too_early' and result.data then
        setReadyIn(result.data.retryIn)
        Platform.UiSend('death_update', { secondsLeft = result.data.retryIn, holding = false })
        return
    end
    Platform.UiSend('death_update', { holding = false, error = (result and result.error) or 'server_error' })
end

-- Laeuft nur, solange man bewusstlos ist
local function holdLoop()
    while dying.active do
        Platform.Wait(0)
        local now = Platform.GetTime()

        if not dying.requesting and now >= dying.readyAt then
            if Platform.IsActionPressed('respawn') then
                if not dying.holdStart then
                    dying.holdStart = now
                    Platform.UiSend('death_update', { holding = true })
                elseif now - dying.holdStart >= Config.Death.HoldToRespawnMs then
                    dying.holdStart = nil
                    requestHospital()
                end
            elseif dying.holdStart then
                dying.holdStart = nil
                Platform.UiSend('death_update', { holding = false })
            end
        end
    end
end

Platform.OnDeath(function(info)
    if not Client.state.character or dying.active then
        return
    end

    dying.active = true
    Client.state.dead = true

    local result = Network.Call('death_report', {
        killer = info.killerServerId,
        weapon = info.weapon,
    })
    local seconds = (result and result.ok and result.data and result.data.respawnInSeconds)
        or Config.Death.HospitalAfterSeconds
    setReadyIn(seconds)

    Client.uiOpen('death', 'death_open', {
        colors = Config.UI.Colors,
        secondsLeft = seconds,
        holdMs = Config.Death.HoldToRespawnMs,
        keyLabel = Platform.GetActionLabel('respawn'),
    }, false)

    holdLoop()
end)

-- Vom Server: Rettungsdienst, Admin oder /revive
Network.On('core:death:revive', function()
    Platform.ReviveInPlace()
    Death.Reset()
end)
