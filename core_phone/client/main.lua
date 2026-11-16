-- core_phone im Client: oeffnet das Handy (Taste, Befehl, Item), reicht Anfragen der UI an den Server weiter,
-- schaltet die Sprache im Telefonat und zeigt Anrufe und Nachrichten an, auch wenn das Handy zu ist.
-- Alle Daten kommen vom Server, hier wird nichts entschieden.

-- Braucht Core 1.20.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.20.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Emit', 'GetResourceName', 'IsOwnPedDead', 'IsOwnPedInVehicle', 'IsPauseMenuOpen',
    'IsResourceStarted', 'OnEvent', 'PlayOwnScenario', 'Print', 'RegisterKeyCommand', 'SetCallPartner', 'SetWaypoint',
    'StopOwnScenario', 'UiFocus', 'UiOn', 'UiSend', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_phone: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Client-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    return
end

local CFG = Config.Phone
local INVENTORY = 'core_inventory'
local WATCH_MS = 500

local ERROR_TEXT = {
    no_character = 'Du spielst gerade keinen Charakter.',
    no_phone = 'Du hast kein Handy dabei.',
    is_dead = 'Bewusstlos kannst du dein Handy nicht benutzen.',
    no_permission = 'Dafür hast du keine Rechte.',
    not_found = 'Diese Person hat noch keine eSIM.',
    timeout = 'Der Server antwortet nicht.',
}

local isOpen = false      -- Handy ist offen und hat den Fokus
local adminView = false   -- offen ist das Handy einer anderen Person (Admin, nur lesen)
local opening = false
local uiReady = false
local queue = {}          -- Nachrichten an die UI, bevor sie geladen ist
local call = nil          -- laufendes Gespraech: { id, state, partner?, channel? }
local scenario = false

local function notify(text, kind)
    Platform.Emit('core:notify', { text = text, type = kind or 'info' })
end

-- Farben des Servers, einzelne Werte aus Config.Phone.Colors gehen vor
local function colors()
    local core = Config.UI.Colors
    local own = CFG.Colors or {}
    return {
        base = own.base or core.base, ink = own.ink or core.ink, accent = own.accent or core.accent,
        mark = own.mark or core.mark, signal = own.signal or core.signal,
    }
end

local function send(action, data)
    if uiReady then
        Platform.UiSend(action, data)
    else
        queue[#queue + 1] = { action = action, data = data }
    end
end

Platform.UiOn('ui_ready', function()
    uiReady = true
    local waiting = queue
    queue = {}
    Platform.Async(function()
        for _, item in ipairs(waiting) do
            Platform.UiSend(item.action, item.data)
        end
    end)
    return { ok = true, data = { colors = colors(), key = CFG.Key, volume = CFG.Volume } }
end)

------------------------------------------------------------------------
-- Sprache im Telefonat
------------------------------------------------------------------------

-- Laeuft nur waehrend eines Gespraechs: Wer bewusstlos wird, legt auf (das Handy selbst geht dann nicht mehr auf)
local function watchCall()
    Platform.Async(function()
        while call do
            if not CFG.AllowWhenDead and Platform.IsOwnPedDead() then
                Network.Call('phone_call_end', {})
                return
            end
            Platform.Wait(WATCH_MS)
        end
    end)
end

-- Stand vom Server uebernehmen: aktiv = Partner hoeren, sonst Sprache zuruecksetzen
local function setCall(state)
    local wasActive = call and call.state == 'active'
    local hadCall = call ~= nil
    call = state
    if state and not hadCall then
        watchCall()
    end
    if state and state.state == 'active' and state.partner then
        Platform.SetCallPartner(state.partner, state.channel)
    elseif wasActive then
        Platform.SetCallPartner(nil)
    end
end

------------------------------------------------------------------------
-- Oeffnen und schliessen
------------------------------------------------------------------------

local function stopScenario()
    if scenario then
        scenario = false
        Platform.StopOwnScenario()
    end
end

local function close(tellUi)
    if not isOpen then
        return
    end
    isOpen = false
    adminView = false
    Platform.UiFocus(false)
    if tellUi then
        send('phone_close', {})
    end
    stopScenario()
    Platform.Async(function()
        Network.Call('phone_close', {})
    end)
end

-- Schliesst von selbst, wenn man bewusstlos wird oder das Pausemenue aufgeht. Bewusstlos endet auch das Gespraech.
local function watch()
    Platform.Async(function()
        while isOpen do
            if Platform.IsPauseMenuOpen() or (not adminView and not CFG.AllowWhenDead and Platform.IsOwnPedDead()) then
                close(true)
                return
            end
            Platform.Wait(WATCH_MS)
        end
    end)
end

-- characterId: Admin-Ansicht eines anderen Handys. Ob man das darf, prueft der Server.
local function open(characterId)
    if isOpen or opening or Platform.IsPauseMenuOpen() then
        return
    end
    opening = true
    local result = Network.Call('phone_open', { characterId = characterId })
    opening = false
    if not result or not result.ok then
        notify(ERROR_TEXT[result and result.error] or 'Das Handy lässt sich gerade nicht öffnen.', 'error')
        return
    end
    -- Kam der Anstoss aus dem Inventar (Item benutzt), geht das Inventar zu
    if Platform.IsResourceStarted(INVENTORY) then
        Platform.CallExport(INVENTORY, 'Close')
    end
    local data = result.data or {}
    data.colors = colors()
    data.key = CFG.Key
    isOpen = true
    adminView = data.admin == true
    if not adminView then
        setCall(data.call)
    end
    Platform.UiFocus(true, true)
    send('phone_open', data)
    if not adminView and PhoneScenario and not Platform.IsOwnPedInVehicle() then
        scenario = Platform.PlayOwnScenario(PhoneScenario) == true
    end
    watch()
end

-- /handy und die Taste: auf und zu. Admins: /handy <ID>
Platform.RegisterKeyCommand(CFG.Command, 'Handy öffnen oder schließen', CFG.Key, function(args)
    local characterId = type(args) == 'table' and tonumber(args[1]) or nil
    if isOpen then
        close(true)
    else
        open(characterId)
    end
end)

Platform.UiOn('phone_close', function()
    close(false)
    return { ok = true }
end)

------------------------------------------------------------------------
-- Anfragen der UI an den Server
------------------------------------------------------------------------

local CALLS = { phone_home = true, phone_settings = true, phone_contact_save = true, phone_contact_delete = true,
    phone_thread = true, phone_message_send = true, phone_thread_delete = true,
    phone_call_start = true, phone_call_answer = true, phone_call_end = true, phone_calls = true, phone_calls_seen = true,
    phone_bank = true, phone_bank_lookup = true, phone_bank_transfer = true, phone_bank_debts = true, phone_bank_pay = true,
    phone_dispatch = true, phone_dispatch_send = true }
-- Antworten, die den Stand des Gespraechs mitbringen
local CALL_RESULTS = { phone_call_start = true, phone_call_answer = true }
-- Bei diesen Fehlern geht das Handy zu
local PHONE_GONE = { no_phone = true, is_dead = true, no_character = true }

Platform.UiOn('phone_call', function(data)
    if type(data.name) ~= 'string' or not CALLS[data.name] then
        return { ok = false, error = 'invalid_input' }
    end
    local result = Network.Call(data.name, type(data.data) == 'table' and data.data or {})
    if not result then
        return { ok = false, error = 'timeout' }
    end
    if result.ok and CALL_RESULTS[data.name] and result.data then
        setCall(result.data.call)
    elseif result.ok and data.name == 'phone_call_end' then
        setCall(nil)
    elseif not result.ok and PHONE_GONE[result.error] and isOpen then
        notify(ERROR_TEXT[result.error], 'error')
        close(true)
    end
    return result
end)

-- Standort aus einer Nachricht als Wegpunkt setzen
Platform.UiOn('phone_waypoint', function(data)
    local x, y = tonumber(data.x), tonumber(data.y)
    if not x or not y then
        return { ok = false, error = 'invalid_input' }
    end
    Platform.SetWaypoint({ x = x, y = y })
    return { ok = true }
end)

------------------------------------------------------------------------
-- Vom Server: Nachricht, Anruf, verpasster Anruf, Handy oeffnen
------------------------------------------------------------------------

Network.On('core_phone:event', function(data)
    if type(data) ~= 'table' then
        return
    end
    if data.type == 'open' then
        Platform.Async(function()
            open(nil)
        end)
        return
    end
    if data.type == 'call' then
        setCall(data.call)
    end
    -- Die UI zeigt alles selbst an, auch bei geschlossenem Handy (Anrufleiste, Hinweis, Ton)
    send('phone_push', data)
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource ~= Platform.GetResourceName() then
        return
    end
    Platform.SetCallPartner(nil)
    if isOpen then
        Platform.UiFocus(false)
        stopScenario()
    end
end)
