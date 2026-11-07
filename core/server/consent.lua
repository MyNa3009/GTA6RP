-- Zustimmung einer anderen Person, bevor ihr etwas gegeben oder gezeigt wird (Items, Geld, Ausweise).
-- Der Server fragt, die Person drueckt Ja (Y) oder Nein (N), erst dann wird gegeben. Ein Cheater kann das nicht
-- ueberspringen, weil der Server die Antwort selbst abwartet.
--
-- In der Core:      local accepted, err = Core.AskConsent(source, target, { title = '...', text = '...' })
-- In Addons:        local id = exports.core:StartConsent(source, target, { title, text })
--                   dann exports.core:GetConsentResult(id) abfragen, bis es nicht mehr nil ist (true oder false, grund)
-- Fehler und Gruende: 'declined', 'timeout', 'target_busy', 'target_offline', 'no_character'

Consent = {}

local CFG = Config.Consent
local TITLE_LENGTH = 80
local TEXT_LENGTH = 160
local POLL_MS = 50

local nextId = 0
local requests = {}   -- [id] = { from, target, expiresAt, done, accepted, reason }
local byTarget = {}   -- [target] = id, hoechstens eine offene Frage pro Person

local function cut(value, length)
    if type(value) ~= 'string' or value == '' then
        return nil
    end
    local count = utf8.len(value)
    if count and count > length then
        return value:sub(1, utf8.offset(value, length + 1) - 1)
    end
    return value
end

local function finish(id, accepted, reason)
    local request = requests[id]
    if not request or request.done then
        return
    end
    request.done = true
    request.accepted = accepted == true
    request.reason = reason
    if byTarget[request.target] == id then
        byTarget[request.target] = nil
    end
    Network.SendToClient(request.target, 'core:consent:close', { id = id, accepted = request.accepted, reason = reason })
end

-- Fragt target, ob es annimmt. Gibt sofort eine Nummer zurueck oder nil und einen Fehlercode.
function Consent.Start(source, target, options)
    source, target = tonumber(source), tonumber(target)
    options = type(options) == 'table' and options or {}
    if not source or not Core.GetPlayer(source) or not Core.GetPlayer(source).characterId then
        return nil, 'no_character'
    end
    local targetPlayer = target and Core.GetPlayer(target)
    if not targetPlayer or not targetPlayer.characterId or target == source then
        return nil, 'target_offline'
    end
    if byTarget[target] then
        return nil, 'target_busy'
    end
    local title = cut(options.title, TITLE_LENGTH)
    if not title then
        return nil, 'invalid_input'
    end
    nextId = nextId + 1
    local id = nextId
    requests[id] = {
        from = source,
        target = target,
        expiresAt = Platform.GetTime() + CFG.TimeoutMs,
        done = false,
    }
    byTarget[target] = id
    Network.SendToClient(target, 'core:consent', {
        id = id,
        title = title,
        text = cut(options.text, TEXT_LENGTH),
        timeoutMs = CFG.TimeoutMs,
    })
    return id
end

-- nil, solange offen. Danach einmal true oder false und der Grund, dann vergessen.
function Consent.Result(id)
    id = tonumber(id)
    local request = id and requests[id]
    if not request then
        return false, 'timeout'
    end
    if not request.done then
        if Platform.GetTime() >= request.expiresAt then
            finish(id, false, 'timeout')
        else
            return nil
        end
    end
    requests[id] = nil
    return request.accepted, request.reason
end

-- Wartet auf die Antwort (nur aus einem Thread, z. B. in einem Callback). Gibt true oder false und den Grund zurueck.
function Core.AskConsent(source, target, options)
    local id, err = Consent.Start(source, target, options)
    if not id then
        return false, err
    end
    Platform.Notify(source, CFG.WaitingText, 'info')
    while true do
        local accepted, reason = Consent.Result(id)
        if accepted ~= nil then
            if not accepted then
                Platform.Notify(source, CFG.DeclinedText[reason] or CFG.DeclinedText.declined, 'error')
            end
            return accepted, reason
        end
        Platform.Wait(POLL_MS)
    end
end

-- Antwort der gefragten Person
Core.RegisterCallback('consent_answer', function(source, data)
    local id = tonumber(data.id)
    local request = id and requests[id]
    if not request or request.done or request.target ~= source then
        return { ok = false, error = 'not_active' }
    end
    local accepted = data.accept == true
    finish(id, accepted, not accepted and 'declined' or nil)
    return { ok = true }
end)

-- Wer geht, kann nicht mehr antworten und nichts mehr geben
Platform.OnEvent('core:characterUnloaded', function(source)
    for id, request in pairs(requests) do
        if not request.done and (request.target == source or request.from == source) then
            finish(id, false, request.target == source and 'target_offline' or 'cancelled')
        end
    end
end)

Platform.Export('StartConsent', Consent.Start)
Platform.Export('GetConsentResult', Consent.Result)

-- Abgelaufene Fragen schliessen (auch wenn niemand mehr nach dem Ergebnis fragt)
local CLEANUP_MS = 5000
Platform.SetInterval(CLEANUP_MS, function()
    local now = Platform.GetTime()
    for id, request in pairs(requests) do
        if not request.done and now >= request.expiresAt then
            finish(id, false, 'timeout')
        elseif request.done and now >= request.expiresAt + CLEANUP_MS * 2 then
            requests[id] = nil
        end
    end
end)
