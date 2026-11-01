-- Hunger und Durst im Client: Anzeige neben der Minimap und Schaden bei 0.
-- Die Werte kommen nur vom Server. Andere Resources lesen sie mit exports.core:GetNeeds()
-- oder hoeren auf das lokale Ereignis core:needsChanged ({ hunger, thirst }).

NeedsHud = {}

local CFG = Config.Needs
local VISIBILITY_CHECK_MS = 500
local HUD_GAP_PX = 6

local current = nil   -- { hunger, thirst } oder nil ohne Charakter
local shown = false
local visible = false
local lastRect = nil
local damageRunning = false

local function starving()
    return current ~= nil and (current.hunger <= 0 or current.thirst <= 0)
end

-- Bei 0 regelmaessig Gesundheit abziehen, bis der Wert wieder steigt
local function startDamage()
    if damageRunning then
        return
    end
    damageRunning = true
    Platform.Async(function()
        while starving() do
            Platform.Wait(CFG.DamageIntervalSeconds * 1000)
            if starving() and not Platform.IsOwnPedDead() then
                local empty = (current.hunger <= 0 and 1 or 0) + (current.thirst <= 0 and 1 or 0)
                Platform.AddHealth(-CFG.DamagePerNeed * empty)
            end
        end
        damageRunning = false
    end)
end

local function sendLayout()
    local rect = Platform.GetMinimapRect()
    if lastRect and lastRect.left == rect.left and lastRect.right == rect.right
        and lastRect.top == rect.top and lastRect.bottom == rect.bottom then
        return
    end
    lastRect = rect
    Platform.UiSend('needs_layout', { minimap = rect, gap = HUD_GAP_PX })
end

local function apply(values)
    current = { hunger = tonumber(values.hunger) or 100, thirst = tonumber(values.thirst) or 100 }
    Platform.Emit('core:needsChanged', current)
    if shown then
        Platform.UiSend('needs_update', current)
    end
    if starving() then
        startDamage()
    end
end

function NeedsHud.Show(values)
    if not CFG.Enabled or type(values) ~= 'table' then
        return
    end
    if CFG.Hud then
        shown = true
        visible = true
        lastRect = Platform.GetMinimapRect()
        -- Alles in einer Nachricht, falls die UI noch laedt (uiOpen haelt sie bis ui_ready zurueck)
        Client.uiOpen('needs', 'needs_open', {
            colors = Config.UI.Colors,
            lowAt = CFG.LowAt,
            minimap = lastRect,
            gap = HUD_GAP_PX,
            hunger = tonumber(values.hunger) or 100,
            thirst = tonumber(values.thirst) or 100,
        }, false)
    end
    apply(values)
end

function NeedsHud.Hide()
    current = nil
    Platform.Emit('core:needsChanged', nil)
    if not shown then
        return
    end
    shown = false
    visible = false
    Client.uiClose('needs', 'needs_close')
end

Network.On('core:needs:update', function(data)
    if current and type(data) == 'table' then
        apply(data)
    end
end)

-- Nur zeigen, wenn die Minimap sichtbar ist, und bei neuer Aufloesung neu andocken
Platform.Async(function()
    while true do
        Platform.Wait(VISIBILITY_CHECK_MS)
        if shown then
            local now
            if CFG.HideWithMinimap then
                now = Platform.IsMinimapVisible()
            else
                now = not Platform.IsPauseMenuOpen()
            end
            if now ~= visible then
                visible = now
                Platform.UiSend('needs_visible', { visible = now })
            end
            if now then
                sendLayout()
            end
        end
    end
end)

-- Fehlersuche: /hungerdurst schreibt den Stand in die F8-Konsole
Platform.RegisterClientCommand('hungerdurst', function()
    local rect = Platform.GetMinimapRect()
    Platform.Print('info', ('Werte: %s | Leisten an: %s | sichtbar: %s | UI geladen: %s | Hud in Config: %s'):format(
        current and ('Hunger %d, Durst %d'):format(current.hunger, current.thirst) or 'keine (kein Charakter?)',
        tostring(shown), tostring(visible), tostring(Client.state.uiReady.needs == true), tostring(CFG.Hud)))
    Platform.Print('info', ('Minimap: links %.3f rechts %.3f oben %.3f unten %.3f | Pausemenue: %s | Radar sichtbar: %s'):format(
        rect.left, rect.right, rect.top, rect.bottom, tostring(Platform.IsPauseMenuOpen()), tostring(Platform.IsMinimapVisible())))
end)

Platform.Export('GetNeeds', function()
    return current and { hunger = current.hunger, thirst = current.thirst } or nil
end)
