-- core_dispatch im Client: /dispatch (Notruf oder Formular), /mdt, /status, Tasten, G-Menue, Notruf im Bewusstlos-Bildschirm, Alarm am Bildschirmrand,
-- Blips und Route zu Einsaetzen. Werte hier sind nur Anzeige (Entfernung, Ortsname). Der Server entscheidet alles.

-- Braucht Core 1.15.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.15.0'
local missingBridge = {}
for _, name in ipairs({ 'AddBlip', 'Async', 'CallExport', 'Emit', 'GetLocationName', 'GetOwnPosition', 'IsPauseMenuOpen', 'OnEvent',
    'PlayUiSound', 'Print', 'RegisterClientCommand', 'RegisterKeyCommand', 'RemoveBlip', 'SetBlipRoute', 'SetWaypoint',
    'UiFocus', 'UiOn', 'UiSend', 'Wait', 'GetResourceName' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_dispatch: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Client-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    return
end

local CFG = Config.Dispatch
local ALERT_MS = CFG.AlertSeconds * 1000

-- Erlaubte Server-Anfragen aus der UI
local MDT_CALLS = {
    dispatch_call_get = true, dispatch_accept = true, dispatch_release = true, dispatch_assign = true,
    dispatch_priority = true, dispatch_note = true, dispatch_message = true, dispatch_close = true,
    dispatch_status = true, dispatch_callsign = true, dispatch_archive = true,
}
local FORM_CALLS = { dispatch_mine = true, dispatch_cancel = true }

local ERROR_TEXT = {
    text_too_short = ('Beschreib kurz, was passiert ist (mindestens %d Zeichen).'):format(CFG.TextMin),
    cooldown = 'Du hast gerade erst einen Notruf abgesetzt. Warte einen Moment.',
    too_many_open = 'Du hast schon offene Notrufe. Warte, bis sie bearbeitet sind, oder zieh einen zurück.',
    blocked = 'Du kannst gerade keinen Notruf absetzen (Missbrauch).',
    not_member = 'Das MDT gibt es nur für Organisationen mit Leitstelle.',
    not_on_duty = 'Dafür musst du im Dienst sein. Geh zur Umkleide.',
    no_permission = 'Dafür hast du keine Rechte.',
    invalid_service = 'Diesen Dienst gibt es nicht.',
    not_found = 'Den Einsatz gibt es nicht mehr.',
    already_assigned = 'Du bist schon an diesem Einsatz.',
    not_unit = 'Nur Einheiten im Dienst können das.',
    timeout = 'Der Server antwortet nicht.',
}

local me = { service = nil, status = nil, callId = nil, callsign = nil }
local calls = {}          -- [id] = Einsatz (offen oder aktiv), fuer Blips und Alarm
local blips = {}          -- [id] = Blip
local lastAlert = nil     -- Einsatz des letzten Alarms (Taste zum Uebernehmen)
local view = nil          -- 'mdt' | 'form' | nil
local viewAdmin = false   -- MDT als Admin offen (bleibt offen ohne eigene Einheit)
local uiReady, pending = false, {}

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function notify(text, kind)
    Platform.Emit('core:notify', { text = text, type = kind or 'info' })
end

local function errorText(result)
    local code = result and result.error
    if code == 'cooldown' and result.data and result.data.seconds then
        return ('Warte noch %d Sekunden bis zum nächsten Notruf.'):format(result.data.seconds)
    end
    if code == 'blocked' and result.data and result.data['until'] then
        return ('Du kannst bis %s Uhr keinen Notruf absetzen (Missbrauch).'):format(result.data['until'])
    end
    return ERROR_TEXT[code] or 'Das hat nicht geklappt.'
end

local function call(name, data)
    local result = Network.Call(name, data or {})
    if not result or not result.ok then
        notify(errorText(result), 'error')
        return nil
    end
    return result.data or {}
end

local function send(action, data)
    if uiReady then
        Platform.UiSend(action, data)
    else
        pending[#pending + 1] = { action = action, data = data }
    end
end

local function ownLocation()
    local pos = Platform.GetOwnPosition()
    return pos and Platform.GetLocationName(pos) or nil
end

-- Ortsname und Entfernung fuer die Anzeige (vom eigenen Standort aus)
local function enrich(entry)
    if type(entry) ~= 'table' or type(entry.pos) ~= 'table' then
        return entry
    end
    if not entry.location or entry.location == '' then
        entry.location = Platform.GetLocationName(entry.pos)
    end
    local own = Platform.GetOwnPosition()
    if own then
        local dx, dy = own.x - entry.pos.x, own.y - entry.pos.y
        entry.distance = math.floor(math.sqrt(dx * dx + dy * dy))
    end
    return entry
end

local function colors(org)
    local core = Config.UI.Colors
    local theme = type(org) == 'table' and org.theme or {}
    return { base = theme.base or core.base, ink = theme.ink or core.ink, accent = theme.accent or core.accent, signal = theme.signal or core.signal }
end

------------------------------------------------------------------------
-- Blips und Route
------------------------------------------------------------------------

local function blipStyle(entry)
    if entry.id == me.callId then
        return DispatchBlips.assigned
    end
    if entry.kind == 'unit' or entry.priority >= #CFG.Priorities then
        return DispatchBlips.urgent
    end
    return DispatchBlips.call
end

local function updateBlip(entry)
    Platform.RemoveBlip(blips[entry.id])
    blips[entry.id] = nil
    if not me.service or entry.status == 'closed' then
        return
    end
    local style = blipStyle(entry)
    local blip = Platform.AddBlip({ coords = entry.pos, sprite = style.sprite, color = style.color, scale = style.scale,
        label = ('Einsatz %s'):format(entry.number), shortRange = false })
    blips[entry.id] = blip
    if entry.id == me.callId then
        Platform.SetBlipRoute(blip, true, entry.priority >= #CFG.Priorities)
    end
end

local function clearAll()
    for id, blip in pairs(blips) do
        Platform.RemoveBlip(blip)
        blips[id] = nil
    end
    calls = {}
    lastAlert = nil
end

------------------------------------------------------------------------
-- Vom Server
------------------------------------------------------------------------

Network.On('core_dispatch:self', function(data)
    local oldCall = me.callId
    me.service, me.status, me.callId, me.callsign = data.service, data.status, data.callId, data.callsign
    if not me.service then
        clearAll()
        send('mdt_self', { service = nil })
        if view == 'mdt' and not viewAdmin then
            view = nil
            Platform.UiFocus(false)
        end
        return
    end
    -- Neuer eigener Einsatz: Route dahin
    if me.callId ~= oldCall then
        for _, id in ipairs({ oldCall, me.callId }) do
            if id and calls[id] then
                updateBlip(calls[id])
            end
        end
        if me.callId and calls[me.callId] then
            Platform.SetWaypoint(calls[me.callId].pos)
        end
    end
    send('mdt_self', data)
end)

Network.On('core_dispatch:call', function(data)
    local entry = enrich(data.call)
    if type(entry) ~= 'table' then
        return
    end
    if entry.status == 'closed' then
        calls[entry.id] = nil
        if lastAlert == entry.id then
            lastAlert = nil
        end
    else
        calls[entry.id] = entry
    end
    updateBlip(entry)
    if view == 'mdt' then
        send('mdt_call', { call = entry, now = data.now, alert = data.alert })
    end
    if data.alert and me.service then
        lastAlert = entry.id
        Platform.PlayUiSound(data.alert == 'urgent' and 'urgent' or 'alert')
        if view ~= 'mdt' then
            send('alert_show', { call = entry, now = data.now, kind = data.alert, ms = ALERT_MS,
                keys = { accept = CFG.Keys.Accept, mdt = CFG.Keys.Mdt }, priorities = CFG.Priorities })
        end
    end
end)

Network.On('core_dispatch:units', function(data)
    if view == 'mdt' then
        send('mdt_units', data)
    end
end)

Network.On('core_dispatch:talk', function(data)
    notify(('Sprechwunsch (Status 5): %s%s'):format(data.callsign and (data.callsign .. ', ') or '', data.name or ''), 'warning')
    Platform.PlayUiSound('click')
end)

Network.On('core_dispatch:mine', function()
    if view == 'form' then
        local data = Network.Call('dispatch_mine', {})
        if data and data.ok then
            send('form_mine', data.data)
        end
    end
end)

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------

Platform.UiOn('ui_ready', function()
    uiReady = true
    for _, entry in ipairs(pending) do
        Platform.UiSend(entry.action, entry.data)
    end
    pending = {}
    return { ok = true, data = { colors = colors() } }
end)

local function closeView()
    if view == 'mdt' then
        Network.Call('dispatch_mdt_close', {})
    end
    view = nil
    Platform.UiFocus(false)
    send('ui_hide', {})
end

Platform.UiOn('ui_close', function()
    closeView()
    return { ok = true }
end)

-- Anfragen aus der UI an den Server (nur erlaubte). Einsaetze bekommen Ortsname und Entfernung.
Platform.UiOn('mdt_call', function(data)
    local name = type(data) == 'table' and data.name
    if not ((view == 'mdt' and MDT_CALLS[name]) or (view == 'form' and FORM_CALLS[name])) then
        return { ok = false, error = 'invalid_input' }
    end
    local payload = type(data.data) == 'table' and data.data or {}
    if name == 'dispatch_status' then
        payload.location = ownLocation()
    end
    local result = Network.Call(name, payload)
    if result and result.ok and type(result.data) == 'table' then
        enrich(result.data.call)
        for _, entry in ipairs(result.data.entries or {}) do
            enrich(entry)
        end
    end
    return result or { ok = false, error = 'timeout' }
end)

-- Route zum Einsatz (nur im Spiel, kein Server noetig)
Platform.UiOn('mdt_route', function(data)
    local entry = calls[tonumber(data.id)]
    if type(data.pos) == 'table' then
        Platform.SetWaypoint(data.pos)
    elseif entry then
        Platform.SetWaypoint(entry.pos)
    else
        return { ok = false, error = 'not_found' }
    end
    return { ok = true }
end)

-- Notruf aus dem Formular: Standort und Ortsname kommen von hier, die Position prueft der Server selbst
Platform.UiOn('form_send', function(data)
    local result = Network.Call('dispatch_send', { text = data.text, service = data.service, anonymous = data.anonymous == true, location = ownLocation() })
    return result or { ok = false, error = 'timeout' }
end)

local function openMdt(service)
    if view or Platform.IsPauseMenuOpen() then
        return
    end
    local data = call('dispatch_mdt_open', { service = service })
    if not data then
        return
    end
    for _, entry in ipairs(data.calls or {}) do
        enrich(entry)
    end
    data.colors = colors(data.org)
    view, viewAdmin = 'mdt', data.admin == true
    Platform.UiFocus(true, true)
    send('mdt_open', data)
end

local function openForm()
    if view or Platform.IsPauseMenuOpen() then
        return
    end
    local data = call('dispatch_mine', {})
    if not data then
        return
    end
    data.location = ownLocation()
    view = 'form'
    Platform.UiFocus(true, true)
    send('form_open', data)
end

local function sendCall(text)
    local result = Network.Call('dispatch_send', { text = text, location = ownLocation() })
    if not result or not result.ok then
        notify(errorText(result), 'error')
        return
    end
    local data = result.data
    if data.units > 0 then
        notify(('Notruf %s an %s gesendet. %d %s im Dienst.'):format(data.number, data.service, data.units, data.units == 1 and 'Einheit' or 'Einheiten'), 'success')
    else
        notify(('Notruf %s gesendet. Gerade ist niemand vom %s im Dienst, der Notruf bleibt offen.'):format(data.number, data.service), 'warning')
    end
end

------------------------------------------------------------------------
-- Befehle und Tasten
------------------------------------------------------------------------

-- /dispatch Text: Notruf. Ohne Text: im Dienst das MDT, sonst das Formular.
Platform.RegisterClientCommand(CFG.Commands.Dispatch, function(args)
    local text = table.concat(args or {}, ' ')
    if text ~= '' then
        sendCall(text)
    elseif me.service then
        openMdt()
    else
        openForm()
    end
end)

Platform.RegisterKeyCommand(CFG.Commands.Mdt, 'MDT öffnen (Leitstelle)', CFG.Keys.Mdt, function(args)
    openMdt(args and args[1])
end)

-- Bewusstlos-Bildschirm der Core: zweite Taste "Notruf absenden". Die Core meldet den Druck mit 'core:death:action'
-- und sperrt die Taste, bis hier das Ergebnis steht. Ob bewusstlos und welche Prioritaet, prueft der Server selbst.
local DOWN_CALL_TEXT = type(CFG.DownCallText) == 'string' and CFG.DownCallText or ''
if DOWN_CALL_TEXT ~= '' then
    local registered = Platform.CallExport('core', 'SetDeathAction', {
        label = 'Notruf absenden',
        pendingNote = 'Notruf wird gesendet…',
        hideWhenHospitalOnly = true,
    })
    if registered ~= true then
        Platform.Print('warn', ('core_dispatch: Die Notruf-Taste im Bewusstlos-Bildschirm braucht Core %s. Ohne sie geht der Notruf weiter mit /dispatch.'):format(REQUIRED_CORE))
    end
    Platform.OnEvent('core:death:action', function()
        Platform.Async(function()
            local result = Network.Call('dispatch_send', { text = DOWN_CALL_TEXT, location = ownLocation() })
            if result and result.ok and result.data then
                local data = result.data
                local note = data.units > 0
                    and ('Notruf %s ist beim %s. %d %s im Dienst.'):format(data.number, data.service, data.units, data.units == 1 and 'Einheit' or 'Einheiten')
                    or ('Notruf %s bleibt offen. Gerade ist niemand vom %s im Dienst.'):format(data.number, data.service)
                Platform.CallExport('core', 'UpdateDeathAction', { label = 'Notruf gesendet', note = note, enabled = false })
                return
            end
            -- Schon ein offener Notruf: nicht noch einmal anbieten. Sonst darf man es wieder versuchen.
            local open = result and result.error == 'too_many_open'
            Platform.CallExport('core', 'UpdateDeathAction', { note = errorText(result), enabled = not open })
        end)
    end)
end

-- G-Menue: Organisation/MDT. Nur Einheiten im Dienst sehen den Eintrag, alle anderen gar nicht.
-- Ob man das MDT wirklich oeffnen darf, prueft wie immer der Server (dispatch_mdt_open).
if type(lib) == 'table' and type(lib.addInteraction) == 'function' then
    lib.addInteraction({
        id = 'mdt',
        path = 'Organisation',
        label = 'MDT',
        description = 'Einsätze, Funkstatus, Leitstelle',
        icon = 'phone',
        order = 15,
        canShow = function()
            return me.service ~= nil
        end,
        onSelect = function()
            openMdt()
        end,
    })
else
    Platform.Print('warn', 'core_dispatch: core_lib fehlt, das MDT steht nicht im G-Menü. /mdt und die Taste gehen weiter.')
end

Platform.RegisterClientCommand(CFG.Commands.Status, function(args)
    local status = tonumber(args and args[1])
    if not status then
        notify('Funkstatus: /status 0 bis 8, z. B. /status 2 (einsatzbereit auf Wache).', 'info')
        return
    end
    local data = call('dispatch_status', { status = status, location = ownLocation() })
    if data then
        notify(('Status %d: %s'):format(data.status, CFG.Statuses[data.status] or ''), data.status == 0 and 'warning' or 'success')
    end
end)

Platform.RegisterKeyCommand('dispatch_accept', 'Letzten Alarm übernehmen', CFG.Keys.Accept, function()
    if not me.service or not lastAlert or not calls[lastAlert] then
        return
    end
    local entry = calls[lastAlert]
    local data = call('dispatch_accept', { id = entry.id })
    if data then
        notify(('Einsatz %s übernommen. Route ist gesetzt.'):format(entry.number), 'success')
        send('alert_hide', { id = entry.id })
        Platform.SetWaypoint(entry.pos)
    end
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == Platform.GetResourceName() then
        if view then
            Platform.UiFocus(false)
        end
        clearAll()
    end
end)
