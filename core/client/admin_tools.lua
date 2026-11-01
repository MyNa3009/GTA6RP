-- Admin-Werkzeuge auf dem Client: einfrieren, heilen, Waffen, Fahrzeuge reparieren, /fixcars und /cartp.
-- Ob jemand etwas darf, entscheidet immer der Server. Der Client fuehrt nur aus.

AdminToolsClient = {}

local ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    duty_required = 'Das geht nur im Admin-Dienst. Starte ihn mit /aduty.',
    no_character = 'Das geht nur mit einem Charakter.',
    jailed = 'Im A-Jail geht das nicht.',
    no_vehicle = 'Kein Fahrzeug gefunden. Schau ein Fahrzeug an oder nutze /fixcars r <meter>.',
    invalid_radius = ('Gib einen Umkreis von 1 bis %d Metern an, z. B. /fixcars r 30.'):format(math.floor(Config.AdminTools.MaxRadius)),
    no_position = 'Deine Position konnte nicht gelesen werden.',
    not_driver = 'Setz dich ans Steuer eines Fahrzeugs.',
    usage_cartp = 'Benutzung: /cartp <permanente ID> oder /cartp <x> <y> [z]',
    timeout = 'Der Server antwortet nicht.',
}

local function notifyError(code, text)
    Notify.Show(text or ERROR_TEXT[code] or ('Nicht möglich: ' .. tostring(code)), 'error')
end

------------------------------------------------------------------------
-- Einfrieren (vom Server)
------------------------------------------------------------------------

local frozen = false

local function frozenLoop()
    while frozen do
        Platform.DisableControlsWhileFrozenThisFrame()
        Platform.Wait(0)
    end
end

local function setFrozen(on)
    Platform.SetFrozen(on)
    if on == frozen then
        return
    end
    frozen = on
    if on then
        if Noclip then
            Noclip.Stop(true)
        end
        Platform.Async(frozenLoop)
    end
end

Network.On('core:admin:freeze', function(data)
    setFrozen(type(data) == 'table' and data.on == true)
end)

------------------------------------------------------------------------
-- /kill (vom Server)
------------------------------------------------------------------------

Network.On('core:admin:kill', function()
    if Noclip then
        Noclip.Stop(true)
    end
    Platform.KillSelf()
end)

------------------------------------------------------------------------
-- Heilen und Weste (vom Server)
------------------------------------------------------------------------

Network.On('core:admin:heal', function(data)
    if type(data) ~= 'table' then
        return
    end
    if data.health then
        Platform.HealSelf()
    end
    local armor = tonumber(data.armor)
    if armor then
        Platform.SetArmor(math.floor(armor))
    end
end)

------------------------------------------------------------------------
-- Waffen von Admins (vom Server). Werden beim Charakterwechsel wieder abgenommen.
------------------------------------------------------------------------

local adminWeapons = {}

Network.On('core:admin:weapon', function(data)
    if type(data) ~= 'table' then
        return
    end
    if type(data.give) == 'string' then
        Platform.GiveWeapon(data.give, math.floor(tonumber(data.ammo) or 0))
        adminWeapons[data.give] = true
    end
    if type(data.remove) == 'table' then
        for _, name in ipairs(data.remove) do
            if type(name) == 'string' then
                Platform.RemoveWeapon(name)
                adminWeapons[name] = nil
            end
        end
    end
end)

------------------------------------------------------------------------
-- Fahrzeug reparieren: der Server schickt das an den, der das Fahrzeug gerade steuert
------------------------------------------------------------------------

Network.On('core:admin:fixvehicle', function(data)
    local vehicle = type(data) == 'table' and tonumber(data.netId) and Platform.VehicleFromNetId(math.floor(data.netId))
    if vehicle then
        Platform.RepairVehicle(vehicle)
    end
end)

local function parseRadius(args)
    local first = args[1] and args[1]:lower() or ''
    if first == 'r' or first == 'radius' then
        return tonumber(args[2]) or false
    end
    local inline = first:match('^r(%d+%.?%d*)$')
    if inline then
        return tonumber(inline)
    end
    return nil
end

-- /fixcars            das Fahrzeug, in dem man sitzt oder auf das man schaut
-- /fixcars r <meter>  alle im Umkreis
Platform.RegisterClientCommand('fixcars', function(args)
    local radius = parseRadius(args)
    if radius == false then
        notifyError('invalid_radius')
        return
    end

    local request, vehicle = {}, nil
    if radius then
        request.radius = radius
    else
        vehicle = Platform.GetVehicleInSight(Config.AdminTools.LookDistance)
        local info = Platform.GetVehicleInfo(vehicle)
        if not info then
            notifyError('no_vehicle')
            return
        end
        request.netId = info.netId
        request.localVehicle = info.netId == nil or nil
        request.model, request.plate = info.model, info.plate
    end

    local result = Network.Call('admin_fixcars', request)
    if not result or not result.ok then
        notifyError(result and result.error or 'timeout')
        return
    end
    if request.localVehicle then
        Platform.RepairVehicle(vehicle)
    end
    local fixed = result.data.fixed
    if radius then
        Notify.Show(('%d %s im Umkreis von %d m repariert.'):format(fixed, fixed == 1 and 'Fahrzeug' or 'Fahrzeuge', math.floor(radius)), 'success')
    else
        Notify.Show(('Fahrzeug %s repariert.'):format(request.model), 'success')
    end
end)

------------------------------------------------------------------------
-- /cartp <ID> oder /cartp <x> <y> [z]: mit dem Fahrzeug teleportieren
------------------------------------------------------------------------

Platform.RegisterClientCommand('cartp', function(args)
    if #args == 0 then
        notifyError('usage_cartp')
        return
    end
    local vehicle = Platform.GetDrivenVehicle()
    if not vehicle then
        notifyError('not_driver')
        return
    end
    local info = Platform.GetVehicleInfo(vehicle)
    local result = Network.Call('admin_cartp', { args = args, model = info.model, plate = info.plate })
    if not result or not result.ok then
        local code = result and result.error or 'timeout'
        notifyError(code == 'usage' and 'usage_cartp' or code, result and result.data and result.data.text)
        return
    end
    Platform.TeleportVehicleTo(vehicle, result.data.position)
    Notify.Show(('Mit dem Fahrzeug zu %s teleportiert.'):format(result.data.label), 'success')
end)

------------------------------------------------------------------------
-- Beim Ausloggen oder Charakterwechsel
------------------------------------------------------------------------

function AdminToolsClient.Reset()
    setFrozen(false)
    for name in pairs(adminWeapons) do
        Platform.RemoveWeapon(name)
    end
    adminWeapons = {}
end
