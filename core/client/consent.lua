-- Anfrage einer anderen Person annehmen oder ablehnen, z. B. "Willst du den Personalausweis nehmen?".
-- Anzeige oben oder unten (Config.Consent.Position), ohne Maus. Ja mit Y, Nein mit N (im Spiel aenderbar).
-- Entscheiden tut der Server: Er wartet auf die Antwort und gibt erst danach.

local CFG = Config.Consent

local current = nil   -- { id } der offenen Anfrage
local busy = false

-- Der Server hat die Texte schon gekuerzt
local function text(value)
    return type(value) == 'string' and value ~= '' and value or nil
end

Network.On('core:consent', function(data)
    if type(data) ~= 'table' or type(data.id) ~= 'number' or type(data.title) ~= 'string' then
        return
    end
    current = { id = data.id }
    busy = false
    Client.uiOpen('consent', 'consent_open', {
        colors = Config.UI.Colors,
        title = text(data.title),
        text = text(data.text),
        timeoutMs = tonumber(data.timeoutMs) or CFG.TimeoutMs,
        position = CFG.Position == 'bottom' and 'bottom' or 'top',
        yesKey = CFG.YesKey,
        noKey = CFG.NoKey,
    }, false)
end)

Network.On('core:consent:close', function(data)
    if type(data) ~= 'table' or not current or current.id ~= data.id then
        return
    end
    current = nil
    Platform.UiSend('consent_close', {})
end)

local function answer(accept)
    if not current or busy then
        return
    end
    busy = true
    local id = current.id
    Platform.UiSend('consent_answer', { accept = accept })
    local result = Network.Call('consent_answer', { id = id, accept = accept })
    busy = false
    -- Antwort kam nicht an (z. B. schon abgelaufen): Anzeige trotzdem schliessen
    if (not result or not result.ok) and current and current.id == id then
        current = nil
        Platform.UiSend('consent_close', {})
    end
end

Platform.RegisterKeyCommand('ja', 'Anfrage annehmen', CFG.YesKey, function()
    answer(true)
end)

Platform.RegisterKeyCommand('nein', 'Anfrage ablehnen', CFG.NoKey, function()
    answer(false)
end)
