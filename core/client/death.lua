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
local function screenEffect(on)
    if Config.Death.ScreenEffect then
        Platform.SetScreenEffect(ScreenEffects.Unconscious, on)
    end
end

local function setReadyIn(seconds)
    dying.readyAt = Platform.GetTime() + seconds * MS_PER_SECOND
end

function Death.Reset()
    if dying.active then
        screenEffect(false)
    end
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
    local data = result and result.ok and result.data or {}
    local seconds = data.respawnInSeconds or Config.Death.HospitalAfterSeconds
    setReadyIn(seconds)

    screenEffect(true)
    Client.uiOpen('death', 'death_open', {
        colors = Config.UI.Colors,
        secondsLeft = seconds,
        totalSeconds = Config.Death.HospitalAfterSeconds,
        holdMs = Config.Death.HoldToRespawnMs,
        keyLabel = Platform.GetActionLabel('respawn'),
        cause = data.collapseReason or WeaponLabel(info.weapon),
        killerId = tonumber(data.killerId),
        hospitalOnly = data.hospitalOnly == true,
    }, false)

    holdLoop()
end)

-- Vom Server: Rettungsdienst, Admin oder /revive
Network.On('core:death:revive', function()
    Platform.ReviveInPlace()
    Death.Reset()
    local anim = DeathAnims and DeathAnims.getUp
    if anim then
        Platform.Async(function()
            Platform.PlayOwnAnim(anim.dict, anim.clip, { loop = false, durationMs = anim.ms })
        end)
    end
end)

-- Vom Server: Zusammenbruch (z. B. Krankheit). Die normale Todesmeldung folgt von selbst.
Network.On('core:death:collapse', function()
    if Client.state.character and not dying.active then
        Platform.KillSelf()
    end
end)

-- Vom Server: Gesundheit geben (Verbandskasten vom Rettungsdienst)
Network.On('core:heal', function(data)
    local amount = type(data) == 'table' and tonumber(data.amount)
    if amount and amount > 0 then
        Platform.AddHealth(amount)
    end
end)
