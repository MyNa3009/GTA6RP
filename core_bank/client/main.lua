-- core_bank im Client: oeffnet die UIs fuer Filiale, Bankautomat und Admin-Ansicht und reicht ihre Anfragen
-- an den Server weiter. Alle Zahlen kommen vom Server, hier wird nichts gerechnet oder entschieden.

-- Braucht Core 1.16.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.16.0'
local missingBridge = {}
for _, name in ipairs({ 'AddBlip', 'Async', 'CallExport', 'ClearOwnTasks', 'DrawMarkerAt', 'Emit', 'FindNearbyObject', 'GetActionLabel',
    'GetResourceName', 'IsActionPressed', 'IsOwnPedDead', 'IsOwnPedInVehicle', 'IsPauseMenuOpen', 'IsResourceStarted', 'OnEvent',
    'PlayOwnScenario', 'Print', 'RegisterClientCommand', 'RemoveBlip', 'UiFocus', 'UiOn', 'UiSend', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_bank: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Client-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    BankDisabled = true
    return
end

BankClient = { open = nil }   -- open: 'bank' oder 'atm', solange eine UI offen ist

local CFG = Config.Bank
local WATCH_MS = 500

local ERROR_TEXT = {
    no_character = 'Du spielst gerade keinen Charakter.',
    too_far = 'Du bist zu weit weg.',
    is_dead = 'Bewusstlos kannst du nicht an dein Konto.',
    no_permission = 'Dafür hast du keine Rechte.',
    not_found = 'Keinen Charakter mit dieser permanenten ID gefunden.',
    not_on_duty = 'Dafür musst du im Dienst sein.',
    target_offline = 'Die Person ist nicht mehr da.',
    target_busy = 'Die Person wird gerade schon etwas gefragt.',
    consent_declined = 'Die Person hat abgelehnt.',
    consent_timeout = 'Die Person hat nicht geantwortet.',
    invalid_amount = 'Der Betrag passt nicht.',
    invalid_input = 'Die Eingabe passt nicht.',
    busy = 'Einen Moment, die letzte Buchung läuft noch.',
    timeout = 'Der Server antwortet nicht.',
}

function BankClient.Notify(text, kind)
    Platform.Emit('core:notify', { text = text, type = kind or 'info' })
end

function BankClient.Error(code)
    BankClient.Notify(ERROR_TEXT[code] or 'Das hat nicht geklappt.', 'error')
end

-- Farben des Servers, einzelne Werte aus Config.Bank.Colors gehen vor
function BankClient.Colors()
    local core = Config.UI.Colors
    local own = CFG.Colors or {}
    return {
        base = own.base or core.base, ink = own.ink or core.ink, accent = own.accent or core.accent,
        mark = own.mark or core.mark, signal = own.signal or core.signal,
    }
end

------------------------------------------------------------------------
-- UI: zwei Dateien in einer Shell (bank.html und atm.html). Ereignisse beginnen mit dem Namen der UI.
------------------------------------------------------------------------

local ready = {}     -- [ui] = true, sobald die Datei geladen ist
local pending = {}   -- [ui] = { action, data } bis die UI bereit ist
local opening = false
local inCall = 0     -- laufende Anfragen der UI (dann kommt der neue Stand mit der Antwort)

local function send(ui, action, data)
    if ready[ui] then
        Platform.UiSend(action, data)
    else
        pending[ui] = { action = action, data = data }
    end
end

Platform.UiOn('ui_ready', function(data)
    local ui = type(data.ui) == 'string' and data.ui or nil
    if ui ~= 'bank' and ui ~= 'atm' then
        return { ok = false, error = 'invalid_input' }
    end
    ready[ui] = true
    local waiting = pending[ui]
    pending[ui] = nil
    if waiting then
        Platform.Async(function()
            Platform.UiSend(waiting.action, waiting.data)
        end)
    end
    return { ok = true, data = { colors = BankClient.Colors() } }
end)

local function close(tellUi)
    local ui = BankClient.open
    if not ui then
        return
    end
    BankClient.open = nil
    Platform.UiFocus(false)
    if tellUi then
        Platform.UiSend(ui .. '_close', {})
    end
    if ui == 'atm' and BankAtmScenario then
        Platform.ClearOwnTasks()
    end
    Platform.Async(function()
        Network.Call('bank_close', {})
    end)
end

-- Schliesst von selbst, wenn man bewusstlos wird oder das Pausemenue aufgeht
local function watch()
    Platform.Async(function()
        while BankClient.open do
            if Platform.IsOwnPedDead() or Platform.IsPauseMenuOpen() then
                close(true)
                return
            end
            Platform.Wait(WATCH_MS)
        end
    end)
end

-- request: { channel = 'bank', branch } | { channel = 'atm', atm = { x, y, z } } | { channel = 'admin', characterId }
function BankClient.Open(request)
    if BankClient.open or opening or Platform.IsPauseMenuOpen() or Platform.IsOwnPedDead() then
        return false
    end
    opening = true
    local result = Network.Call('bank_open', request)
    opening = false
    if not result or not result.ok then
        BankClient.Error(result and result.error)
        return false
    end
    local data = result.data or {}
    local ui = data.channel == 'atm' and 'atm' or 'bank'
    data.colors = BankClient.Colors()
    BankClient.open = ui
    Platform.UiFocus(true, true)
    send(ui, ui .. '_open', data)
    if ui == 'atm' and BankAtmScenario then
        Platform.PlayOwnScenario(BankAtmScenario)
    end
    watch()
    return true
end

Platform.UiOn('bank_close', function()
    close(false)
    return { ok = true }
end)

Platform.UiOn('atm_close', function()
    close(false)
    return { ok = true }
end)

-- Erlaubte Server-Anfragen aus den UIs
local CALLS = { bank_overview = true, bank_statement = true, bank_deposit = true, bank_withdraw = true, bank_lookup = true,
    bank_transfer = true, bank_debts = true, bank_debt_pay = true, bank_debt_add = true, bank_debt_cancel = true }
-- Bei diesen Fehlern ist die Sitzung auf dem Server zu Ende
local SESSION_OVER = { too_far = true, no_session = true, is_dead = true, no_character = true }

Platform.UiOn('bank_call', function(data)
    if not BankClient.open or type(data.name) ~= 'string' or not CALLS[data.name] then
        return { ok = false, error = 'invalid_input' }
    end
    inCall = inCall + 1
    local result = Network.Call(data.name, type(data.data) == 'table' and data.data or {})
    inCall = inCall - 1
    if result and not result.ok and SESSION_OVER[result.error] then
        BankClient.Error(result.error)
        close(true)
    end
    return result or { ok = false, error = 'timeout' }
end)

-- Auf dem Konto hat sich etwas getan (Geldeingang, neue Forderung): offene UI laedt neu
Network.On('core_bank:changed', function(data)
    if BankClient.open and inCall == 0 then
        Platform.UiSend(BankClient.open .. '_refresh', { what = type(data) == 'table' and data.what or nil })
    end
end)

-- Admins: /konto <ID>. Ob man das darf, prueft der Server.
Platform.RegisterClientCommand(CFG.Admin.Command, function(args)
    local characterId = tonumber(args[1])
    if not characterId then
        BankClient.Notify(('Benutzung: /%s <ID>'):format(CFG.Admin.Command), 'info')
        return
    end
    BankClient.Open({ channel = 'admin', characterId = characterId })
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == Platform.GetResourceName() and BankClient.open then
        Platform.UiFocus(false)
        if BankClient.open == 'atm' and BankAtmScenario then
            Platform.ClearOwnTasks()
        end
    end
end)
