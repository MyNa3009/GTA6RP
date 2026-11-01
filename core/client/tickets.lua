-- Tickets auf dem Client: /report (Spieler) und /tickets (Team) oeffnen dieselbe UI in zwei Ansichten.
-- Ob jemand etwas darf, entscheidet immer der Server.

TicketsClient = {}

local ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    no_character = 'Tickets gehen nur mit einem Charakter.',
    not_ready = 'Tickets sind gerade nicht verfügbar. Versuch es gleich noch einmal.',
    timeout = 'Der Server antwortet nicht.',
}

local isOpen = false

local function failed(result)
    local code = result and result.error or 'timeout'
    Notify.Show(ERROR_TEXT[code] or ('Tickets nicht verfügbar: ' .. tostring(code)), 'error')
end

local function limits()
    return {
        cooldown = Config.Tickets.PlayerCooldownSeconds,
        minLength = Config.Tickets.MessageMinLength,
        maxLength = Config.Tickets.MessageMaxLength,
    }
end

-- Spieler-Ansicht
local function openPlayer()
    if not Client.state.character then
        Notify.Show(ERROR_TEXT.no_character, 'error')
        return
    end
    local result = Network.Call('ticket_mine', {})
    if not result or not result.ok then
        failed(result)
        return
    end
    isOpen = true
    Client.uiOpen('ticket', 'ticket_open', {
        mode = 'player',
        colors = Config.UI.Colors,
        categories = Config.Tickets.Categories,
        limits = limits(),
        tickets = result.data.tickets,
        cooldown = result.data.cooldown,
    })
end

-- Team-Ansicht, optional direkt mit einem Ticket
local function openAdmin(selectId)
    if not Client.state.character then
        Notify.Show(ERROR_TEXT.no_character, 'error')
        return
    end
    local result = Network.Call('ticket_list', { filter = 'open' })
    if not result or not result.ok then
        failed(result)
        return
    end
    isOpen = true
    Client.uiOpen('ticket', 'ticket_open', {
        mode = 'admin',
        colors = Config.UI.Colors,
        categories = Config.Tickets.Categories,
        limits = limits(),
        list = result.data,
        selectId = selectId,
    })
end

function TicketsClient.Close()
    if not isOpen then
        return
    end
    isOpen = false
    Client.uiClose('ticket', 'ticket_close')
    Platform.UiFocus(false)
    Platform.Async(function()
        Network.Call('ticket_ui_close', {})
    end)
end

Platform.RegisterClientCommand('report', function()
    openPlayer()
end)

Platform.RegisterClientCommand('tickets', function()
    openAdmin(nil)
end)

-- AdminMenu-Knopf "Tickets"
function TicketsClient.OpenAdmin(selectId)
    openAdmin(selectId)
end

-- Nach /claim direkt das Ticket zeigen
Network.On('core:ticket:open', function(data)
    Platform.Async(function()
        openAdmin(type(data) == 'table' and tonumber(data.id) or nil)
    end)
end)

-- Live: neue Nachricht oder geaenderter Status
Network.On('core:ticket:message', function(data)
    if isOpen then
        Platform.UiSend('ticket_message', data)
    end
end)

Network.On('core:ticket:changed', function(data)
    if isOpen then
        Platform.UiSend('ticket_changed', data)
    end
end)

Platform.UiOn('ticket_close', function()
    TicketsClient.Close()
    return { ok = true }
end)

-- Diese Anfragen gehen unveraendert an den Server
for _, name in ipairs({ 'ticket_mine', 'ticket_list', 'ticket_get', 'ticket_create', 'ticket_send', 'ticket_action' }) do
    Platform.UiOn(name, function(data)
        return Network.Call(name, data)
    end)
end

-- Hingehen und Beobachten: bei Erfolg schliesst die UI, damit man das Spiel sieht
for _, name in ipairs({ 'ticket_goto', 'ticket_spectate' }) do
    Platform.UiOn(name, function(data)
        local result = Network.Call(name, data)
        if result and result.ok then
            TicketsClient.Close()
        end
        return result
    end)
end
