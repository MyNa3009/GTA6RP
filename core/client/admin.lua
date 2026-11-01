-- Admin-Menue: oeffnen, Anfragen an den Server weiterreichen, Teleport ausfuehren.
-- Ob jemand etwas darf, entscheidet immer der Server.

local ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    not_logged_in = 'Du bist nicht eingeloggt.',
    timeout = 'Der Server antwortet nicht.',
}

local isOpen = false

local function open()
    if isOpen then
        return
    end
    local result = Network.Call('admin_overview', {})
    if not result or not result.ok then
        local code = result and result.error or 'timeout'
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
Platform.RegisterKeyCommand('admin', 'Admin-Menü öffnen', nil, open)

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
for _, name in ipairs({ 'admin_search', 'admin_profile', 'admin_logs', 'admin_action', 'admin_duty', 'admin_link', 'admin_warnings', 'admin_accounts', 'admin_punish', 'admin_device_alert', 'admin_inventory' }) do
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
    Close = function()
        if isOpen then
            close()
        end
    end,
}
