-- Admin-Key eingeben: kleines Fenster, wenn der Server danach fragt (/aduty oder F10 ohne Key).
-- Ob der Key stimmt, prueft nur der Server. Hier wird nur weitergereicht und angezeigt.

local UI = 'adminkey'
local pending = nil -- { duty, menu } solange das Fenster offen ist

local function close()
    if not pending then
        return
    end
    pending = nil
    Client.uiClose(UI, 'adminkey_close')
    Platform.UiFocus(false)
end

local function open(options)
    if not Client.state.character then
        return
    end
    pending = { duty = options.duty == true, menu = options.menu == true }
    Client.uiOpen(UI, 'adminkey_open', {
        colors = Config.UI.Colors,
        maxAttempts = Config.AdminKeys.MaxAttempts,
    })
end

-- Vom Server: Key wird gebraucht
Network.On('core:admin:key_prompt', function(data)
    open(type(data) == 'table' and data or {})
end)

-- Vom Server: Key neu erstellt oder geloescht, Fenster nicht mehr noetig
Network.On('core:admin:key_locked', function()
    close()
end)

-- Vom Server: diese Befehle darf man nicht, also auch nicht im Chat vorschlagen
Network.On('core:admin:commands', function(data)
    if type(data) == 'table' then
        Platform.SetHiddenCommands(data.hidden)
    end
end)

Platform.UiOn('adminkey_submit', function(data)
    if not pending then
        return { ok = false, error = 'closed' }
    end
    local key = type(data) == 'table' and data.key or nil
    local result = Network.Call('admin_key_unlock', { key = key, duty = pending.duty })
    if not result then
        return { ok = false, error = 'timeout' }
    end
    if result.ok then
        local wanted = pending
        close()
        local duty = result.data and result.data.duty
        Notify.Show(duty and 'Admin-Rechte freigeschaltet. Admin-Dienst gestartet.' or 'Admin-Rechte freigeschaltet.', 'success')
        if wanted.menu then
            Platform.Async(AdminMenu.Open)
        end
    end
    return result
end)

Platform.UiOn('adminkey_close', function()
    close()
    return { ok = true }
end)

-- Beim Ausloggen
AdminKeyPrompt = {
    Close = close,
}
