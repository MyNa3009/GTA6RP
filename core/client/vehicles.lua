-- Admin-Fahrzeuge: /car <modell>, /dv, /boost <prozent>.
-- Der Server prueft Recht und Admin-Dienst und loggt jede Aktion.

AdminVehicles = {}

local ERROR_TEXT = {
    no_permission = 'Dafür hast du keine Rechte.',
    duty_required = 'Das geht nur im Admin-Dienst. Starte ihn mit /aduty.',
    no_character = 'Das geht nur mit einem Charakter.',
    jailed = 'Im A-Jail geht das nicht.',
    invalid_model = 'Dieses Fahrzeugmodell gibt es nicht. Beispiel: /car adder',
    model_timeout = 'Das Modell lädt nicht. Versuch es noch einmal.',
    spawn_failed = 'Das Fahrzeug konnte nicht gespawnt werden.',
    no_vehicle = 'Kein Fahrzeug in der Nähe.',
    invalid_percent = ('Gib einen Boost von 0 bis %d Prozent an, z. B. /boost 200.'):format(Config.Vehicles.MaxBoostPercent),
    not_driver = 'Setz dich ans Steuer eines Fahrzeugs.',
    timeout = 'Der Server antwortet nicht.',
}

local function notifyError(code)
    Notify.Show(ERROR_TEXT[code] or ('Nicht möglich: ' .. tostring(code)), 'error')
end

local function call(name, data)
    local result = Network.Call(name, data)
    if not result or not result.ok then
        notifyError(result and result.error or 'timeout')
        return nil
    end
    return result.data or {}
end

------------------------------------------------------------------------
-- /car <modell>
------------------------------------------------------------------------

Platform.RegisterClientCommand('car', function(args)
    local model = args[1] and args[1]:lower() or nil
    if not model then
        Notify.Show('Benutzung: /car <modell>, z. B. /car adder', 'info')
        return
    end
    if not Platform.IsVehicleModel(model) then
        notifyError('invalid_model')
        return
    end
    local data = call('admin_vehicle_spawn', { model = model })
    if not data then
        return
    end
    local vehicle, err = Platform.SpawnVehicle(model, data.plate or Config.Vehicles.Plate, Config.Vehicles.ModelLoadTimeoutMs)
    if not vehicle then
        notifyError(err)
        return
    end
    Notify.Show(('Fahrzeug %s gespawnt.'):format(model), 'success')
end)

------------------------------------------------------------------------
-- /dv
------------------------------------------------------------------------

Platform.RegisterClientCommand('dv', function()
    local info = Platform.GetVehicleInfo(Platform.GetVehicleNearby(Config.Vehicles.DeleteRadius))
    if not info or not info.netId then
        notifyError('no_vehicle')
        return
    end
    if call('admin_vehicle_delete', { netId = info.netId, model = info.model, plate = info.plate }) then
        Notify.Show(('Fahrzeug %s gelöscht.'):format(info.model), 'success')
    end
end)

------------------------------------------------------------------------
-- /boost <prozent>
------------------------------------------------------------------------

local boost = nil -- { vehicle, percent }

local IDLE_CHECK_MS = 500 -- nicht am Steuer: nur zweimal pro Sekunde nachsehen

local function boostLoop(current)
    while boost == current and Platform.VehicleExists(current.vehicle) do
        if Platform.GetDrivenVehicle() == current.vehicle then
            Platform.ApplyVehicleBoostThisFrame(current.vehicle, current.percent)
            Platform.Wait(0)
        else
            Platform.Wait(IDLE_CHECK_MS)
        end
    end
    if boost == current then
        boost = nil
    end
end

local function clearBoost()
    if boost then
        Platform.SetVehicleBoost(boost.vehicle, 0, 0)
        boost = nil
    end
end

Platform.RegisterClientCommand('boost', function(args)
    local percent = tonumber(args[1])
    if not percent then
        Notify.Show(('Benutzung: /boost <prozent>, z. B. /boost 200. Höchstens %d, 0 schaltet ab.'):format(Config.Vehicles.MaxBoostPercent), 'info')
        return
    end
    local vehicle = Platform.GetDrivenVehicle()
    if not vehicle then
        notifyError('not_driver')
        return
    end
    local info = Platform.GetVehicleInfo(vehicle)
    local data = call('admin_vehicle_boost', { percent = percent, model = info.model, plate = info.plate })
    if not data then
        return
    end

    clearBoost()
    if data.percent == 0 then
        Notify.Show('Boost aus.', 'info')
        return
    end
    Platform.SetVehicleBoost(vehicle, data.percent, Config.Vehicles.BoostTopSpeedKmh)
    boost = { vehicle = vehicle, percent = data.percent }
    Platform.Async(function()
        boostLoop(boost)
    end)
    Notify.Show(('Boost %d %% aktiv. Höchstens %d km/h. /boost 0 schaltet ab.'):format(data.percent, Config.Vehicles.BoostTopSpeedKmh), 'success')
end)

-- Beim Ausloggen oder Charakterwechsel
function AdminVehicles.Reset()
    clearBoost()
end
