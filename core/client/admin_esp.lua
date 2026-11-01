-- Admin-Erkennungsmodus: Tab im Admin-Dienst. Ueber jedem Spieler stehen Name, permanente ID, Login, Server-ID,
-- Rang, Gesundheit, Weste, Entfernung und alles, was ein Admin wissen muss (offene Warnung, Verwarnungen, A-Jail ...).
-- Die Daten kommen vom Server (Recht admin.esp), Gesundheit und Entfernung misst der Client selbst.

AdminEsp = {}

local ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    duty_required = 'Der Erkennungsmodus geht nur im Admin-Dienst. Starte ihn mit /aduty.',
    no_character = 'Das geht nur mit einem Charakter.',
    timeout = 'Der Server antwortet nicht.',
}

local SCAN_MS = 250       -- so oft werden Spieler in der Naehe gesucht und die Texte neu gebaut

local active = false
local busy = false
local byServerId = {}     -- [serverId] = Daten vom Server
local warnBanAt = 3
local labels = {}         -- { ped, label }

local style = {
    Scale = Config.AdminEsp.Scale,
    HeightOffset = Config.AdminEsp.HeightOffset,
    Color = Config.AdminEsp.Color,
}

------------------------------------------------------------------------
-- Text pro Spieler: Zeilen aus Teilen { text, tone }. Wie das im Spiel aussieht, entscheidet die Bridge.
------------------------------------------------------------------------

local SEPARATOR = { text = ' | ', tone = 'muted' }

local function part(text, tone)
    return { text = text, tone = tone or 'normal' }
end

-- Teile mit Trennstrich dazwischen zu einer Zeile verbinden
local function joined(parts)
    local line = {}
    for i, entry in ipairs(parts) do
        if i > 1 then
            line[#line + 1] = SEPARATOR
        end
        line[#line + 1] = entry
    end
    return line
end

local function flagsFor(info, status)
    local flags = {}
    if info.warning then flags[#flags + 1] = part('Offene Warnung', 'danger') end
    if info.warns then flags[#flags + 1] = part(('Verwarnungen %d von %d'):format(info.warns, warnBanAt), 'warning') end
    if info.jailed then flags[#flags + 1] = part('A-Jail', 'danger') end
    if info.frozen then flags[#flags + 1] = part('Eingefroren', 'info') end
    if info.dead or (status and status.dead) then flags[#flags + 1] = part('Bewusstlos', 'warning') end
    if info.duty then flags[#flags + 1] = part('Im Admin-Dienst', 'danger') end
    if info.dimension then flags[#flags + 1] = part(('Dimension %d'):format(info.dimension), 'muted') end
    return flags
end

local function linesFor(info, status, distance)
    local lines = {}
    if info.characterId then
        lines[1] = { part(('ID %d'):format(info.characterId), 'accent'), part('  ' .. (info.name or '')) }
    else
        lines[1] = { part('Kein Charakter', 'muted') }
    end

    local second = {}
    if info.accountId then second[#second + 1] = part(('Login %d'):format(info.accountId), 'muted') end
    second[#second + 1] = part(('Server %d'):format(info.serverId), 'muted')
    if info.rank then second[#second + 1] = part(info.rank, 'info') end
    lines[2] = joined(second)

    if status then
        lines[3] = joined({
            part(('HP %d'):format(status.health)),
            part(('Weste %d'):format(status.armor)),
            part(('%d m'):format(math.floor(distance + 0.5))),
        })
    end

    local flags = flagsFor(info, status)
    if #flags > 0 then
        lines[#lines + 1] = joined(flags)
    end
    return lines
end

------------------------------------------------------------------------
-- Schleifen, laufen nur solange der Modus an ist
------------------------------------------------------------------------

local function applyData(data)
    local map = {}
    for _, info in ipairs(data.players or {}) do
        map[info.serverId] = info
    end
    byServerId = map
    warnBanAt = tonumber(data.warnBanAt) or warnBanAt
end

local function stop(notify)
    if not active then
        return
    end
    active = false
    labels = {}
    byServerId = {}
    if notify then
        Notify.Show('Erkennungsmodus aus.', 'info')
    end
end

local function dataLoop()
    while active do
        Platform.Wait(Config.AdminEsp.RefreshMs)
        if not active then
            break
        end
        local result = Network.Call('admin_esp', {})
        if result and result.ok then
            applyData(result.data)
        elseif result and result.error ~= 'rate_limited' then
            -- Kein Dienst oder keine Rechte mehr
            stop(true)
        end
    end
end

local function scanLoop()
    while active do
        local list = {}
        for _, entry in ipairs(Platform.GetNearbyPlayers(Config.AdminEsp.Distance, false)) do
            local info = byServerId[entry.serverId]
            if info then
                local lines = linesFor(info, Platform.GetPedStatus(entry.ped), entry.distance)
                list[#list + 1] = { ped = entry.ped, label = Platform.PrepareWorldText(lines) }
            end
        end
        labels = list
        Platform.Wait(SCAN_MS)
    end
end

local function drawLoop()
    while active do
        for _, entry in ipairs(labels) do
            Platform.DrawTextAbovePed(entry.ped, entry.label, style)
        end
        Platform.Wait(0)
    end
end

------------------------------------------------------------------------
-- An und aus
------------------------------------------------------------------------

local function toggle()
    if busy then
        return
    end
    if not Client.state.character then
        Notify.Show(ERROR_TEXT.no_character, 'error')
        return
    end
    busy = true
    local wanted = not active
    if not wanted then
        stop(true)
    end
    local result = Network.Call('admin_esp', { on = wanted })
    busy = false
    if not wanted then
        return
    end
    if not result or not result.ok then
        local code = result and result.error or 'timeout'
        Notify.Show(ERROR_TEXT[code] or ('Erkennungsmodus nicht möglich: ' .. tostring(code)), 'error')
        return
    end
    applyData(result.data)
    active = true
    Platform.Async(dataLoop)
    Platform.Async(scanLoop)
    Platform.Async(drawLoop)
    Notify.Show('Erkennungsmodus an. Name, IDs und Warnungen stehen über jedem Spieler.', 'success')
end

Platform.RegisterKeyCommand('aesp', 'Admin-Erkennungsmodus an oder aus', Config.AdminEsp.Key, toggle)

-- Dienstende schaltet den Modus aus
Network.On('core:admin:duty', function(data)
    if type(data) == 'table' and data.on == false then
        stop(true)
    end
end)

function AdminEsp.IsActive()
    return active
end

-- Beim Ausloggen oder Charakterwechsel
function AdminEsp.Reset()
    stop(false)
end
