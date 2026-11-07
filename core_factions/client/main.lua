-- core_factions im Client: eigener Stand (Organisation, Rang, Dienst, Rechte), Organisationsmenue, Exports.
-- Der Stand ist nur Anzeige. Jede Aktion prueft der Server selbst.

-- Braucht Core 1.10.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.10.0'
local missingBridge = {}
for _, name in ipairs({ 'AddBlip', 'Async', 'DrawMarkerAt', 'Emit', 'Export', 'GetActionLabel', 'GetDrivenVehicle', 'GetOwnPosition',
    'GetVehicleInfo', 'IsActionPressed', 'IsOwnPedDead', 'IsPauseMenuOpen', 'OnEvent', 'Print', 'RegisterClientCommand', 'RemoveBlip',
    'SpawnVehicleAt', 'UiFocus', 'UiOn', 'UiSend', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_factions: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Client-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    FactionsDisabled = true
    return
end

FactionClient = { state = { member = false } }

local CFG = Config.Factions
local STATE_CHANGED = 'core_factions:stateChanged'

-- Erlaubte Server-Anfragen aus dem Menue (die UI kann nur diese ausloesen)
local MENU_CALLS = {
    faction_menu_open = true, faction_message_save = true, faction_cash = true,
    faction_ranks = true, faction_rank_save = true, faction_department_save = true, faction_department_delete = true,
    faction_exam_save = true, faction_exam_delete = true,
    faction_vehicles = true, faction_vehicle_save = true,
    faction_members = true, faction_member_update = true, faction_member_rank = true, faction_member_fire = true, faction_hire = true,
    faction_archive = true,
}

local ERROR_TEXT = {
    not_member = 'Du bist in keiner Organisation.',
    no_permission = 'Dafür hast du keine Rechte.',
    not_on_duty = 'Dafür musst du im Dienst sein. Geh zur Umkleide.',
    too_far = 'Du bist zu weit weg.',
    target_offline = 'Die Person ist nicht mehr da.',
    already_member = 'Die Person ist schon in einer Organisation.',
    consent_declined = 'Die Person hat abgelehnt.',
    consent_timeout = 'Die Person hat nicht geantwortet.',
    target_busy = 'Die Person entscheidet gerade etwas anderes.',
    leader_cannot_leave = 'Als Leader kannst du nicht kündigen. Ein Admin muss die Leitung übergeben.',
    rank_too_low = 'Dein Rang reicht für dieses Fahrzeug nicht.',
    vehicle_limit = 'Du hast schon ein Dienstfahrzeug draußen. Park es zuerst ein.',
    not_faction_vehicle = 'Das ist kein Dienstfahrzeug deiner Organisation.',
    timeout = 'Der Server antwortet nicht.',
}

function FactionClient.Notify(text, kind)
    Platform.Emit('core:notify', { text = text, type = kind or 'info' })
end

function FactionClient.Error(code)
    FactionClient.Notify(ERROR_TEXT[code] or 'Das hat nicht geklappt.', 'error')
end

function FactionClient.Can(key)
    local state = FactionClient.state
    if not state.member then
        return false
    end
    for _, permission in ipairs(state.permissions or {}) do
        if permission == key then
            return true
        end
    end
    return false
end

Network.On('core_factions:state', function(state)
    if type(state) ~= 'table' then
        return
    end
    FactionClient.state = state
    Platform.Emit(STATE_CHANGED, state)
end)

------------------------------------------------------------------------
-- Organisationsmenue
------------------------------------------------------------------------

local uiReady = false
local pendingOpen = nil
local menuOpen = false

local function colors()
    local core = Config.UI.Colors
    local own = CFG.Colors or {}
    return { base = own.base or core.base, ink = own.ink or core.ink, accent = own.accent or core.accent, signal = own.signal or core.signal }
end

local function send(action, data)
    if uiReady then
        Platform.UiSend(action, data)
    else
        pendingOpen = { action = action, data = data }
    end
end

Platform.UiOn('ui_ready', function()
    uiReady = true
    if pendingOpen then
        Platform.UiSend(pendingOpen.action, pendingOpen.data)
        pendingOpen = nil
    end
    return { ok = true, data = { colors = colors() } }
end)

function FactionClient.OpenMenu(admin)
    if menuOpen or Platform.IsPauseMenuOpen() then
        return
    end
    local result = Network.Call('faction_menu_open', { admin = admin == true })
    if not result or not result.ok then
        FactionClient.Error(result and result.error)
        return
    end
    menuOpen = true
    Platform.UiFocus(true, true)
    send('orgmenu_open', { colors = colors(), overview = result.data })
end

local function closeMenu()
    if not menuOpen then
        return
    end
    menuOpen = false
    Platform.UiFocus(false)
    Platform.UiSend('orgmenu_close', {})
    Network.Call('faction_menu_close', {})
end
FactionClient.CloseMenu = closeMenu

Platform.UiOn('orgmenu_close', function()
    closeMenu()
    return { ok = true }
end)

-- Jede Anfrage der UI geht unveraendert an den Server, aber nur aus der Liste oben
Platform.UiOn('orgmenu_call', function(data)
    local name = type(data.name) == 'string' and data.name or nil
    if not name or not MENU_CALLS[name] or not menuOpen then
        return { ok = false, error = 'invalid_input' }
    end
    return Network.Call(name, type(data.data) == 'table' and data.data or {})
end)

Network.On('core_factions:open_admin', function()
    Platform.Async(function()
        FactionClient.OpenMenu(true)
    end)
end)

Platform.RegisterClientCommand(CFG.MenuCommand, function()
    FactionClient.OpenMenu(false)
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == Platform.GetResourceName() and menuOpen then
        Platform.UiFocus(false)
    end
end)

------------------------------------------------------------------------
-- Exports fuer andere Scripts im Client
------------------------------------------------------------------------

-- { member, faction, label, short, rank, rankName, isLeader, isVice, onDuty, permissions }
Platform.Export('GetState', function()
    return FactionClient.state
end)
Platform.Export('HasPermission', function(key, needsDuty)
    if needsDuty and not FactionClient.state.onDuty then
        return false
    end
    return FactionClient.Can(key)
end)
Platform.Export('IsOnDuty', function(faction)
    local state = FactionClient.state
    return state.member == true and state.onDuty == true and (faction == nil or state.faction == faction)
end)
Platform.Export('OpenMenu', function()
    Platform.Async(function()
        FactionClient.OpenMenu(false)
    end)
end)
