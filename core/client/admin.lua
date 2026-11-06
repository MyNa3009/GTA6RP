-- Admin-Menue: oeffnen, Anfragen an den Server weiterreichen, Teleport ausfuehren.
-- Ob jemand etwas darf, entscheidet immer der Server.

local ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    not_logged_in = 'Du bist nicht eingeloggt.',
    timeout = 'Der Server antwortet nicht.',
}

local isOpen = false

local LOOK_ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    duty_required = 'Das geht nur im Admin-Dienst. Starte ihn mit /aduty.',
    invalid_input = 'Ungültiger Wert.',
    not_logged_in = 'Du bist nicht eingeloggt.',
    timeout = 'Der Server antwortet nicht.',
}

local LOOK_USAGE = 'Benutzung: /admin tarnung | /admin tag an|aus | /admin alpha 0-255 | /admin reset'

-- /admin <tarnung|tag|alpha|reset>: Aussehen im Admin-Dienst. Ohne Argument oeffnet sich das Menue.
-- Gibt true zurueck, wenn die Eingabe eine Optik-Einstellung war.
local function changeLook(args)
    local what = tostring(args[1] or ''):lower()
    local request
    if what == 'tarnung' or what == 'tarn' then
        -- Wie ein normaler Spieler: kein roter Admin-Tag, nicht durchsichtig
        request = { tag = false, alpha = 255 }
    elseif what == 'tag' then
        local value = tostring(args[2] or ''):lower()
        if value == 'an' or value == 'on' then
            request = { tag = true }
        elseif value == 'aus' or value == 'off' then
            request = { tag = false }
        else
            Notify.Show(LOOK_USAGE, 'info')
            return true
        end
    elseif what == 'alpha' then
        local alpha = tonumber(args[2])
        if not alpha or alpha < 0 or alpha > 255 then
            Notify.Show('Alpha ist eine Zahl von 0 (unsichtbar) bis 255 (normal). ' .. LOOK_USAGE, 'info')
            return true
        end
        request = { alpha = math.floor(alpha) }
    elseif what == 'reset' then
        request = { reset = true }
    else
        return false
    end

    local result = Network.Call('admin_look', request)
    if not result or not result.ok then
        local code = result and result.error or 'timeout'
        Notify.Show(LOOK_ERROR_TEXT[code] or ('Nicht möglich: ' .. tostring(code)), 'error')
        return true
    end
    local look = result.data
    Notify.Show(('Dienst-Optik: Admin-Tag %s, Durchsichtigkeit %d (255 = normal).'):format(look.tag and 'an' or 'aus', look.alpha), 'success')
    return true
end

local function open()
    if isOpen then
        return
    end
    local result = Network.Call('admin_overview', {})
    if not result or not result.ok then
        local code = result and result.error or 'timeout'
        -- Der Server hat schon nach dem Admin-Key gefragt oder gemeldet, warum es nicht geht
        if code == 'key_required' then
            return
        end
        Notify.Show(ERROR_TEXT[code] or ('Admin-Menü nicht verfügbar: ' .. tostring(code)), 'error')
        return
    end

    isOpen = true
    Client.uiOpen('admin', 'admin_open', {
        colors = Config.UI.Colors,
        currency = Config.UI.Currency,
        serverName = Config.UI.ServerName,
        self = result.data.self,
        players = result.data.players,
        warningCount = result.data.warningCount,
        commands = result.data.commands,
        ticketsOpen = result.data.ticketsOpen,
    })
end

local function close()
    isOpen = false
    Client.uiClose('admin', 'admin_close')
    Platform.UiFocus(false)
end

Platform.RegisterKeyCommand('adminmenu', 'Admin-Menü öffnen', Config.Admin.OpenKey, open)
Platform.RegisterKeyCommand('admin', 'Admin-Menü öffnen oder Dienst-Optik ändern', nil, function(args)
    if type(args) == 'table' and #args > 0 and changeLook(args) then
        return
    end
    open()
end)

Platform.UiOn('admin_close', function()
    close()
    return { ok = true }
end)

-- Knopf "Tickets" im Menue: Menue zu, Ticket-UI auf
Platform.UiOn('admin_open_tickets', function()
    close()
    Platform.Async(function()
        TicketsClient.OpenAdmin(nil)
    end)
    return { ok = true }
end)

Platform.UiOn('admin_refresh', function()
    return Network.Call('admin_overview', {})
end)

-- Diese Anfragen gehen unveraendert an den Server
for _, name in ipairs({ 'admin_search', 'admin_profile', 'admin_logs', 'admin_action', 'admin_duty', 'admin_link', 'admin_warnings', 'admin_accounts', 'admin_punish', 'admin_device_alert', 'admin_inventory', 'admin_key_create', 'admin_key_delete' }) do
    Platform.UiOn(name, function(data)
        return Network.Call(name, data)
    end)
end

-- Vom Server: zu einem Spieler teleportieren oder geholt werden
Network.On('core:admin:teleport', function(position)
    if type(position) ~= 'table' or not tonumber(position.x) then
        return
    end
    Platform.Async(function()
        Platform.TeleportTo(position)
    end)
end)

-- Beim Ausloggen das Menue schliessen
AdminMenu = {
    Open = open,
    Close = function()
        if isOpen then
            close()
        end
    end,
}
