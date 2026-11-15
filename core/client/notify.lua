-- Benachrichtigungen unten mittig ohne Kasten, mit kleinem Ton (eigene UI statt Chat).
-- Notify.Show(text, typ, dauerMs) im Client, Platform.Notify(source, text, typ) auf dem Server.
-- Typen: info, success, error, warning, message (Teamnachricht, mit title als erster Zeile)

Notify = {}

local TYPES = { info = true, success = true, error = true, warning = true, message = true }
local TITLE_MAX_LENGTH = 80

local SOUND_GAP_MS = 250   -- viele Meldungen auf einmal: nur ein Ton

local opened = false
local lastSound = 0

-- Kleiner Ton pro Art (Toene in der Bridge). Abschaltbar ueber Config.Notify.Sound.
local function playSound(kind)
    local sounds = Config.Notify.Sound
    if not sounds then
        return
    end
    local now = Platform.GetTime()
    if now - lastSound < SOUND_GAP_MS then
        return
    end
    lastSound = now
    local name = type(sounds) == 'table' and sounds[kind] or ('notify_' .. kind)
    if name then
        Platform.PlayUiSound(name)
    end
end
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
    playSound(kind)
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
