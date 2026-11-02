-- Noclip (/nc): frei fliegen, durch Waende, mit Kamera-Richtung.
-- Der Server erlaubt es nur mit Recht admin.noclip und im Admin-Dienst und loggt An und Aus.

Noclip = {}

local active = false
local busy = false

local ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    duty_required = 'Noclip geht nur im Admin-Dienst. Starte ihn mit /aduty.',
    jailed = 'Im A-Jail gibt es kein Noclip.',
    frozen = 'Eingefroren gibt es kein Noclip.',
    no_character = 'Noclip geht nur mit einem Charakter.',
    not_logged_in = 'Du bist nicht eingeloggt.',
    timeout = 'Der Server antwortet nicht.',
}

local function axis(positive, negative)
    local value = 0
    if Platform.IsActionPressed(positive) then value = value + 1 end
    if Platform.IsActionPressed(negative) then value = value - 1 end
    return value
end

local function speed()
    if Platform.IsActionPressed('noclipFast') then
        return Config.Noclip.FastSpeed
    end
    if Platform.IsActionPressed('noclipSlow') then
        return Config.Noclip.SlowSpeed
    end
    return Config.Noclip.Speed
end

local function run()
    Platform.SetNoclip(true, Config.Noclip.Invisible)
    while active do
        Platform.Wait(0)
        Platform.DisableNoclipControlsThisFrame()
        if Config.Noclip.Invisible and Config.Noclip.VisibleForSelf then
            Platform.ShowNoclipLocallyThisFrame()
        end
        local forward = axis('noclipForward', 'noclipBack')
        local right = axis('noclipRight', 'noclipLeft')
        local up = axis('noclipUp', 'noclipDown')
        if forward ~= 0 or right ~= 0 or up ~= 0 then
            Platform.NoclipMove(forward, right, up, speed() * Platform.GetFrameTime(), Config.Noclip.FollowCameraPitch)
        end
    end
    Platform.SetNoclip(false, Config.Noclip.Invisible, Config.Noclip.GroundOnExit)
end

function Noclip.IsActive()
    return active
end

function Noclip.Start()
    if active then
        return
    end
    active = true
    Platform.Async(run)
    local start = Config.Noclip.Invisible and 'Noclip an, du bist unsichtbar.' or 'Noclip an.'
    local move = Config.Noclip.FollowCameraPitch and 'W fliegt, wohin du schaust.' or 'W A S D fliegen waagerecht.'
    Notify.Show(('%s %s Leertaste hoch, Strg runter, Shift schnell, Alt langsam.'):format(start, move), 'success')
end

-- Lokal beenden, z. B. beim Ausloggen oder wenn der Server es beendet hat
function Noclip.Stop(silent)
    if not active then
        return
    end
    active = false
    if not silent then
        Notify.Show('Noclip aus.', 'info')
    end
end

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
    -- Ausschalten geht immer sofort, der Server bekommt es danach fuer das Log
    if not wanted then
        Noclip.Stop()
    end
    local result = Network.Call('admin_noclip', { on = wanted })
    busy = false

    if not result or not result.ok then
        local code = result and result.error or 'timeout'
        if wanted then
            Notify.Show(ERROR_TEXT[code] or ('Noclip nicht möglich: ' .. tostring(code)), 'error')
        end
        return
    end
    if wanted then
        Noclip.Start()
    end
end

Platform.RegisterKeyCommand('nc', 'Noclip an oder aus', Config.Noclip.Key, toggle)

-- Vom Server: Dienstende, A-Jail usw.
Network.On('core:admin:noclip', function(data)
    if type(data) == 'table' and data.on == false then
        Noclip.Stop()
    end
end)
