-- Noclip (/nc): frei fliegen wie bei txAdmin (freie Kamera, der Ped fliegt unsichtbar mit).
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

-- Texte der Tastenhinweise unten rechts (wie bei txAdmin)
local KEY_LABELS = {
    slower = 'Langsamer',
    faster = 'Schneller',
    down = 'Runter',
    up = 'Hoch',
    leftRight = 'Links/Rechts',
    forwardBack = 'Vor/Zurück',
}

function Noclip.IsActive()
    return active
end

-- Fliegen macht die Bridge (freie Kamera wie bei txAdmin). An und Aus wirken sofort.
function Noclip.Start()
    if active then
        return
    end
    active = true
    Platform.SetNoclip(true, Config.Noclip, KEY_LABELS)
    Notify.Show('Noclip an, du bist unsichtbar. W A S D fliegen, Q hoch, E runter, Shift schneller, Alt langsamer.', 'success')
end

-- Lokal beenden. silent = true: von A-Jail, Beobachten, Einfrieren, /kill oder Ausloggen,
-- dann ohne Meldung und ohne Fallschutz, weil gleich danach versetzt wird.
function Noclip.Stop(silent)
    if not active then
        return
    end
    active = false
    Platform.SetNoclip(false, { protectFall = not silent })
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
