-- Admin-Fahrzeuge: spawnen, loeschen, boosten.
-- Der Client fuehrt aus, der Server erlaubt, prueft und loggt. Spawnen und Boosten nur im Admin-Dienst,
-- Loeschen (/dv, Recht vehicle.delete) auch ausserhalb.

local MODEL_PATTERN = '^[%w_]+$'
local MODEL_MAX_LENGTH = 32
local DELETE_DISTANCE_MARGIN = 4.0 -- Spielraum fuer Verzoegerung, das Fahrzeug kann sich gerade bewegen

local function deny(source, permission)
    if Core.HasPermission(source, permission) then
        return nil
    end
    local player = Core.GetPlayer(source)
    Core.Log({
        actor_account_id = player and player.accountId or nil,
        category = 'security',
        action = 'admin_denied',
        data = { permission = permission },
    })
    return { ok = false, error = 'no_permission' }
end

-- Gemeinsame Pruefung: Recht, Charakter, Dienst. Gibt den Spieler oder nil und eine Antwort zurueck.
-- noDuty = true: geht auch ausserhalb des Admin-Diensts
local function check(source, permission, noDuty)
    local denied = deny(source, permission)
    if denied then
        return nil, denied
    end
    local player = Core.GetPlayer(source)
    if not player.character then
        return nil, { ok = false, error = 'no_character' }
    end
    if not noDuty and Config.Admin.RequireDutyForActions and not player.adminDuty then
        return nil, { ok = false, error = 'duty_required' }
    end
    if player.jail then
        return nil, { ok = false, error = 'jailed' }
    end
    return player
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function validModel(model)
    return type(model) == 'string' and #model <= MODEL_MAX_LENGTH and model:match(MODEL_PATTERN) ~= nil
end

local function log(player, action, data)
    data.position = Platform.GetPlayerPosition(player.source)
    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = player.characterId,
        category = 'admin',
        action = action,
        data = data,
    })
end

-- /car <modell>: der Client hat das Modell schon geprueft, hier wird erlaubt und geloggt
Core.RegisterCallback('admin_vehicle_spawn', function(source, data)
    local player, response = check(source, 'vehicle.spawn')
    if not player then return response end
    if not validModel(data.model) then
        return { ok = false, error = 'invalid_model' }
    end
    log(player, 'vehicle_spawn', { model = data.model:lower() })
    return { ok = true, data = { plate = Config.Vehicles.Plate } }
end)

-- /dv: Fahrzeug loeschen (das eigene oder das naechste). Auch ausserhalb des Admin-Diensts.
-- Position und Kennzeichen kommen vom Server, damit niemand ein Fahrzeug am anderen Ende der Karte loescht.
Core.RegisterCallback('admin_vehicle_delete', function(source, data)
    local player, response = check(source, 'vehicle.delete', true)
    if not player then return response end
    local netId = tonumber(data.netId)
    local vehicle = netId and Platform.GetVehicleInfo(netId) or nil
    if not vehicle then
        return { ok = false, error = 'no_vehicle' }
    end
    local position = Platform.GetPlayerPosition(source)
    local maxDistance = Config.Vehicles.DeleteRadius + DELETE_DISTANCE_MARGIN
    if not position or distance(position, vehicle.position) > maxDistance then
        return { ok = false, error = 'too_far' }
    end
    if not Platform.DeleteNetworkedVehicle(netId) then
        return { ok = false, error = 'no_vehicle' }
    end
    log(player, 'vehicle_delete', {
        model = validModel(data.model) and data.model or nil,
        plate = vehicle.plate,
        duty = player.adminDuty ~= nil,
    })
    return { ok = true }
end)

-- /boost <prozent>: Fahrzeug, in dem der Admin am Steuer sitzt. 0 schaltet ab.
Core.RegisterCallback('admin_vehicle_boost', function(source, data)
    local player, response = check(source, 'vehicle.boost')
    if not player then return response end
    local percent = tonumber(data.percent)
    if not percent or percent ~= math.floor(percent) or percent < 0 or percent > Config.Vehicles.MaxBoostPercent then
        return { ok = false, error = 'invalid_percent' }
    end
    log(player, percent > 0 and 'vehicle_boost' or 'vehicle_boost_off', {
        percent = percent > 0 and percent or nil,
        model = validModel(data.model) and data.model or nil,
        plate = type(data.plate) == 'string' and data.plate:sub(1, 8) or nil,
    })
    return { ok = true, data = { percent = percent } }
end)
