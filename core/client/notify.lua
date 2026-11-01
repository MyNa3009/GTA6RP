-- Benachrichtigungen oben rechts (eigene UI statt Chat).
-- Notify.Show(text, typ, dauerMs) im Client, Platform.Notify(source, text, typ) auf dem Server.
-- Typen: info, success, error, warning, message (Teamnachricht, mit title als erster Zeile)

Notify = {}

local TYPES = { info = true, success = true, error = true, warning = true, message = true }
local TITLE_MAX_LENGTH = 80

local opened = false
local waiting = {} -- Meldungen, bevor die UI geladen ist

local function durationFor(text, kind, duration)
    if tonumber(duration) then
        return math.min(tonumber(duration), Config.Notify.MaxDurationMs * 2)
    end
    local base = Config.Notify.DurationMs[kind] or Config.Notify.DurationMs.info
    return math.min(base + #text * Config.Notify.PerCharacterMs, Config.Notify.MaxDurationMs)
end

function Notify.Show(text, kind, duration, title)
    if type(text) ~= 'string' or text == '' then
        return
    end
    kind = TYPES[kind] and kind or 'info'
    local item = { text = text, type = kind, duration = durationFor(text, kind, duration) }
    if type(title) == 'string' and title ~= '' then
        local cut = utf8.len(title) and utf8.len(title) > TITLE_MAX_LENGTH and utf8.offset(title, TITLE_MAX_LENGTH + 1)
        item.title = cut and title:sub(1, cut - 1) or title
    end

    if opened and Client.state.uiReady.notify then
        Platform.UiSend('notify_push', item)
        return
    end
    -- Noch nicht bereit: sammeln und beim Oeffnen alle auf einmal schicken
    waiting[#waiting + 1] = item
    opened = true
    Client.uiOpen('notify', 'notify_open', {
        colors = Config.UI.Colors,
        maxVisible = Config.Notify.MaxVisible,
        items = waiting,
    }, false)
end

-- Sobald die UI bereit ist, ist die Warteliste verschickt
Platform.UiOn('notify_flushed', function()
    waiting = {}
    return { ok = true }
end)

-- Vom Server (Platform.Notify)
Network.On('core:notify', function(data)
    if type(data) == 'table' then
        Notify.Show(data.text, data.type, data.duration, data.title)
    end
end)
