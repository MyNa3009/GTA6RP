-- Anzeige ueber dem Kopf und Admin-Dienst-Darstellung.
--   Normal:      "ID: 12" ueber anderen Spielern in der Naehe, nicht durch Waende
--   Admin-Dienst: Rang, Name und ID in Rot mit Leuchten, weiter sichtbar, Admin ist durchsichtig
-- Alle Werte kommen vom Server (oeffentliche Werte 'coreId' und 'adminDuty').

local labels = {}       -- { ped, label, style }
local transparent = {}  -- [serverId] = ped, bei denen wir die Durchsichtigkeit gesetzt haben

local normalStyle = Config.Overhead
local dutyStyle = Config.AdminDuty
local searchDistance = math.max(Config.Overhead.Distance, Config.AdminDuty.TagDistance)

-- Sichtlinie (Raycast) pro Spieler nur so oft neu pruefen. Bei vielen Spielern auf einem Fleck spart das
-- den Grossteil der Raycasts, die Anzeige reagiert trotzdem innerhalb einer Sekunde.
local LOS_CACHE_MS = 1000
local losCache = {} -- [serverId] = { ped, visible, checkedAt }

local function hasLineOfSight(serverId, ped, now)
    local cached = losCache[serverId]
    if cached and cached.ped == ped and now - cached.checkedAt < LOS_CACHE_MS then
        return cached.visible
    end
    local visible = Platform.HasLineOfSight(ped)
    losCache[serverId] = { ped = ped, visible = visible, checkedAt = now }
    return visible
end

-- "{name} | ID: {id}" mit Werten fuellen
local function fill(template, values)
    return (template:gsub('{(%w+)}', values))
end

local function dutyLines(duty, id)
    local values = { rank = duty.rank or '', name = duty.name or '', id = tostring(id) }
    local lines = {}
    for i, template in ipairs(dutyStyle.TagLines) do
        lines[i] = fill(template, values)
    end
    return lines
end

local function updateTransparency(seen)
    for serverId, ped in pairs(transparent) do
        if not seen[serverId] then
            Platform.ResetPedAlpha(ped)
            transparent[serverId] = nil
        end
    end
end

local invinciblePed = nil -- Ped, den dieses Script unverwundbar gemacht hat, sonst nil

-- Nur zuruecksetzen, was der Admin-Dienst gesetzt hat, damit andere Scripts (z. B. Safezones) nicht ueberschrieben werden.
-- Neuer Ped im Dienst (z. B. nach dem Wiederbeleben): wird erneut gesetzt.
local function setOwnInvincible(on)
    local ped = on and Platform.GetOwnPed() or nil
    if invinciblePed == ped then
        return
    end
    invinciblePed = ped
    Platform.SetInvincible(on)
end

local function refresh()
    local ownId = Platform.GetOwnServerId()
    local playing = Network.GetPlayerPublic(ownId, 'coreId') ~= nil

    local list = {}
    local seenDuty = {}
    local now = Platform.GetTime()
    local nearby = {}

    -- Eigener Ped: im Dienst durchsichtig und auf Wunsch unverwundbar
    local ownDuty = Network.GetPlayerPublic(ownId, 'adminDuty')
    if ownDuty then
        local ped = Platform.GetOwnPed()
        Platform.SetPedAlpha(ped, dutyStyle.Alpha)
        transparent[ownId] = ped
        seenDuty[ownId] = true
        if dutyStyle.Invincible then
            setOwnInvincible(true)
        end
    elseif invinciblePed then
        -- Dienst ist vorbei, auch wenn das Ereignis dazu nicht ankam (Relog, Verbindungsproblem)
        setOwnInvincible(false)
    end

    for _, entry in ipairs(Platform.GetNearbyPlayers(searchDistance, Config.Overhead.ShowOwn)) do
        nearby[entry.serverId] = true
        local id = Network.GetPlayerPublic(entry.serverId, 'coreId')
        local duty = Network.GetPlayerPublic(entry.serverId, 'adminDuty')

        if duty and entry.serverId ~= ownId then
            Platform.SetPedAlpha(entry.ped, dutyStyle.Alpha)
            transparent[entry.serverId] = entry.ped
            seenDuty[entry.serverId] = true
        end

        -- Im Admin-Erkennungsmodus stehen die IDs schon im ausfuehrlichen Text
        local espActive = AdminEsp and AdminEsp.IsActive()
        if playing and id and not espActive and Platform.IsPedVisible(entry.ped) then
            if duty and Config.Overhead.Enabled and entry.distance <= dutyStyle.TagDistance then
                list[#list + 1] = {
                    ped = entry.ped,
                    label = Platform.PrepareWorldText(dutyLines(duty, id)),
                    style = dutyStyle,
                }
            elseif Config.Overhead.Enabled and entry.distance <= normalStyle.Distance
                and (not normalStyle.RequireLineOfSight or hasLineOfSight(entry.serverId, entry.ped, now)) then
                list[#list + 1] = {
                    ped = entry.ped,
                    label = Platform.PrepareWorldText(fill(normalStyle.Label, { id = tostring(id) })),
                    style = normalStyle,
                }
            end
        end
    end

    updateTransparency(seenDuty)
    labels = list
    -- Wer weg ist, fliegt aus dem Zwischenspeicher
    for serverId in pairs(losCache) do
        if not nearby[serverId] then
            losCache[serverId] = nil
        end
    end
end

-- Dienst beendet: eigene Durchsichtigkeit und Unverwundbarkeit sofort zuruecksetzen
Network.On('core:admin:duty', function(data)
    if data and data.on then
        return
    end
    local ownId = Platform.GetOwnServerId()
    Platform.ResetPedAlpha(Platform.GetOwnPed())
    transparent[ownId] = nil
    setOwnInvincible(false)
end)

-- Suchen: ein paar Mal pro Sekunde
Platform.Async(function()
    while true do
        refresh()
        Platform.Wait(Config.Overhead.RefreshMs)
    end
end)

-- Zeichnen: jeden Frame, aber nur wenn jemand in der Naehe ist
Platform.Async(function()
    while true do
        if #labels == 0 then
            Platform.Wait(Config.Overhead.RefreshMs)
        else
            for _, entry in ipairs(labels) do
                Platform.DrawTextAbovePed(entry.ped, entry.label, entry.style)
            end
            Platform.Wait(0)
        end
    end
end)
