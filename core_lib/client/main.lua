-- Grundlage der core_lib im Client: Versionspruefung, UI-Verwaltung (Fokus, Laden) und Ergebnisse.
-- Alles, was spaeter ein Ergebnis hat (Fortschritt, Minigame, Dialog), bekommt eine Nummer. Das Ergebnis geht als
-- lokales Ereignis 'core_lib:done' an alle Resources, init.lua in der aufrufenden Resource wartet darauf.

-- Braucht Core 1.9.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.9.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'AttachPropToOwnPed', 'ClearOwnTasks', 'CloseAllVehicleDoors', 'DeleteLocalProp',
    'DisableActionsThisFrame', 'Emit', 'EnterVehicleSeat', 'Export', 'GetActionLabel', 'GetCallingResource', 'GetNearbyPlayers',
    'DrawPlayerRing', 'GetOwnServerId', 'GetOwnVehicleState', 'GetPlayerInSight', 'GetTime', 'GetVehicleInSightOnFoot', 'GetVehicleOutsideState', 'HasVehicleDoor', 'HasVehicleWindow',
    'GetResourceName', 'IsActionPressed', 'IsOwnPedDead', 'IsPauseMenuOpen', 'IsOwnVehicle', 'IsResourceStarted', 'IsVehicleDoorOpen', 'IsVehicleWindowDown',
    'MoveToSeat', 'OnEvent', 'OnResourceStop', 'PlayOwnAnim', 'PlayOwnScenario', 'Print', 'CallExport',
    'RegisterKeyCommand', 'SetEntityOutline', 'SetVehicleDoor', 'SetVehicleDoorFromOutside', 'SetVehicleEngine', 'SetVehicleLights', 'SetVehicleWindow', 'StopOwnAnim',
    'UiFocus', 'UiOn', 'UiSend', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_lib: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Client-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    LibDisabled = true
    return
end

Lib = {}
Ui = {}

local DONE_EVENT = 'core_lib:done'

------------------------------------------------------------------------
-- Ergebnisse
------------------------------------------------------------------------

local nextId = 0
local results = {}   -- [id] = { done = bool, value = any }

-- Neue Nummer fuer etwas, das spaeter ein Ergebnis hat
function Lib.NewRequest()
    nextId = nextId + 1
    results[nextId] = { done = false }
    return nextId
end

function Lib.Finish(id, value)
    local entry = results[id]
    if not entry or entry.done then
        return
    end
    entry.done = true
    entry.value = value
    Platform.Emit(DONE_EVENT, id, value)
end

-- Wartet auf das Ergebnis (nur innerhalb der core_lib, andere Resources nutzen init.lua)
function Lib.Await(id)
    local entry = results[id]
    if not entry then
        return nil
    end
    while not entry.done do
        Platform.Wait(Config.Lib.ResultPollMs)
    end
    results[id] = nil
    return entry.value
end

-- Ergebnisse, auf die niemand innerhalb der core_lib wartet, nicht ewig aufheben
local RESULT_KEEP_MS = 10000
Platform.OnEvent(DONE_EVENT, function(id)
    Platform.Async(function()
        Platform.Wait(RESULT_KEEP_MS)
        local entry = results[id]
        if entry and entry.done then
            results[id] = nil
        end
    end)
end)

------------------------------------------------------------------------
-- Texte kuerzen und pruefen (Eingaben anderer Scripts)
------------------------------------------------------------------------

-- Kuerzt einen Text auf maxLength Zeichen (UTF-8). Gibt nil zurueck, wenn es kein Text ist.
function Lib.Text(value, maxLength)
    if type(value) == 'number' then
        value = tostring(value)
    end
    if type(value) ~= 'string' or value == '' then
        return nil
    end
    local length = utf8.len(value)
    if not length then
        return nil
    end
    if maxLength and length > maxLength then
        value = value:sub(1, utf8.offset(value, maxLength + 1) - 1)
    end
    return value
end

function Lib.Notify(text, kind, duration)
    Platform.Emit('core:notify', { text = text, type = kind or 'info', duration = duration })
end

------------------------------------------------------------------------
-- UI-Verwaltung
------------------------------------------------------------------------

local ready = {}          -- [ui] = true, sobald die Datei geladen ist
local waiting = {}        -- [ui] = { { action, data }, ... } bis die UI bereit ist
local focusOwners = {}    -- [ui] = { cursor = bool }
local focusState = { on = false, cursor = true }

function Ui.Send(ui, action, data)
    if ready[ui] then
        Platform.UiSend(action, data)
        return
    end
    waiting[ui] = waiting[ui] or {}
    waiting[ui][#waiting[ui] + 1] = { action = action, data = data }
end

local function applyFocus()
    local on, cursor = false, false
    for _, owner in pairs(focusOwners) do
        on = true
        cursor = cursor or owner.cursor
    end
    if on == focusState.on and (not on or cursor == focusState.cursor) then
        return
    end
    focusState.on, focusState.cursor = on, cursor
    Platform.UiFocus(on, cursor)
end

-- Fokus fuer eine UI an oder aus. Mehrere UIs koennen gleichzeitig Fokus wollen (Menue und Dialog).
function Ui.Focus(ui, on, cursor)
    if on then
        focusOwners[ui] = { cursor = cursor ~= false }
    else
        focusOwners[ui] = nil
    end
    applyFocus()
end

Platform.UiOn('ui_ready', function(data)
    local ui = type(data.ui) == 'string' and data.ui or nil
    if not ui then
        return { ok = false, error = 'invalid_input' }
    end
    ready[ui] = true
    local list = waiting[ui]
    waiting[ui] = nil
    if list then
        Platform.Async(function()
            for _, message in ipairs(list) do
                Platform.UiSend(message.action, message.data)
            end
        end)
    end
    -- Farben aus dem Logo: das Menue hat eigene (mark statt signal), alle anderen Fenster Config.Lib.Colors.
    -- Fehlt ein Wert, gilt der aus Config.UI.Colors der Core.
    local core = Config.UI.Colors
    local own = ui == 'menu' and Config.Lib.Menu.Colors or Config.Lib.Colors
    local colors = { base = own.base or core.base, ink = own.ink or core.ink, accent = own.accent or core.accent }
    if ui == 'menu' then
        colors.mark = own.mark
    else
        colors.signal = own.signal or core.signal
    end
    return { ok = true, data = { colors = colors } }
end)

------------------------------------------------------------------------
-- Exports, die nichts mit einer bestimmten UI zu tun haben
------------------------------------------------------------------------

Platform.Export('Notify', function(text, kind, duration)
    Lib.Notify(text, kind, duration)
end)

-- Ist ein Ergebnis schon da? (fuer init.lua, falls das Ereignis verpasst wurde)
Platform.Export('GetResult', function(id)
    local entry = results[tonumber(id)]
    if entry and entry.done then
        return true, entry.value
    end
    return false
end)

Platform.Export('GetVersion', function()
    return '1.4.2'
end)
