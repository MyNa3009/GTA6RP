-- Bewusstlosigkeit: liegen bleiben, Countdown, Taste halten fuers Krankenhaus.
-- Die Zeit prueft der Server, der Client zeigt nur an.
--
-- Zusatzaktion (seit Core 1.15.0): Eine andere Resource kann eine zweite Taste anmelden, z. B. core_dispatch den Notruf.
-- Die Core kennt nur Taste und Text. Was beim Druecken passiert, entscheidet die Resource:
--   exports.core:SetDeathAction({ label = 'Notruf absenden', pendingNote = 'Notruf wird gesendet…', hideWhenHospitalOnly = true })
--   lokales Ereignis 'core:death:action', wenn die Taste gedrueckt wurde (die Taste ist danach gesperrt)
--   exports.core:UpdateDeathAction({ label = ..., note = ..., enabled = true/false }) mit dem Ergebnis

Death = {}

local dying = {
    active = false,
    readyAt = 0,       -- Spielzeit in ms, ab der das Krankenhaus erlaubt ist
    holdStart = nil,   -- Spielzeit in ms, seit der die Taste gehalten wird
    requesting = false,
    extra = nil,       -- Zusatzaktion fuer diese Bewusstlosigkeit: { label, note, enabled }
    extraDown = false, -- Taste war im letzten Frame gedrueckt (nur der Druck zaehlt, nicht das Halten)
}

-- Angemeldete Zusatzaktion: { label, pendingNote, hideWhenHospitalOnly } oder nil
local extraAction = nil
local EXTRA_LABEL_MAX = 40
local EXTRA_NOTE_MAX = 120

local function extraText(value, max)
    if type(value) ~= 'string' or value == '' then
        return nil
    end
    return value:sub(1, max)
end

-- Fuer die UI: nil, wenn es gerade keine Zusatzaktion gibt
local function extraPayload()
    if not dying.extra then
        return nil
    end
    return { keyLabel = Platform.GetActionLabel('emergency'), label = dying.extra.label, note = dying.extra.note, enabled = dying.extra.enabled }
end

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
    dying.extra = nil
    dying.extraDown = false
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

        -- Zusatzaktion: ein Druck loest aus, danach ist die Taste gesperrt, bis die Resource das Ergebnis meldet
        if dying.extra then
            local pressed = Platform.IsActionPressed('emergency')
            if pressed and not dying.extraDown and dying.extra.enabled then
                dying.extra.enabled = false
                dying.extra.note = extraAction and extraAction.pendingNote or nil
                Platform.UiSend('death_update', { extra = extraPayload() })
                Platform.Emit('core:death:action')
            end
            dying.extraDown = pressed
        end

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

    dying.extra, dying.extraDown = nil, false
    if extraAction and not (extraAction.hideWhenHospitalOnly and data.hospitalOnly == true) then
        dying.extra = { label = extraAction.label, enabled = true }
    end

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
        extra = extraPayload(),
    }, false)

    holdLoop()
end)

-- Zusatzaktion anmelden oder mit nil wieder abmelden. Gilt ab der naechsten Bewusstlosigkeit.
Platform.Export('SetDeathAction', function(action)
    local label = type(action) == 'table' and extraText(action.label, EXTRA_LABEL_MAX)
    if not label then
        extraAction = nil
        return false
    end
    extraAction = { label = label, pendingNote = extraText(action.pendingNote, EXTRA_NOTE_MAX), hideWhenHospitalOnly = action.hideWhenHospitalOnly == true }
    return true
end)

-- Ergebnis der Zusatzaktion anzeigen: { label?, note?, enabled? }. Nur solange man bewusstlos ist.
Platform.Export('UpdateDeathAction', function(patch)
    if not dying.active or not dying.extra or type(patch) ~= 'table' then
        return false
    end
    dying.extra.label = extraText(patch.label, EXTRA_LABEL_MAX) or dying.extra.label
    if patch.note ~= nil then
        dying.extra.note = extraText(patch.note, EXTRA_NOTE_MAX)
    end
    if patch.enabled ~= nil then
        dying.extra.enabled = patch.enabled == true
    end
    Platform.UiSend('death_update', { extra = extraPayload() })
    return true
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
