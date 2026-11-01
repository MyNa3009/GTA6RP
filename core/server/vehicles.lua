-- Admin-Fahrzeuge: spawnen, loeschen, boosten.
-- Der Client fuehrt aus, der Server erlaubt, prueft und loggt. Alles nur im Admin-Dienst.

local MODEL_PATTERN = '^[%w_]+$'
local MODEL_MAX_LENGTH = 32

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
local function check(source, permission)
    local denied = deny(source, permission)
    if denied then
        return nil, denied
    end
    local player = Core.GetPlayer(source)
    if not player.character then
        return nil, { ok = false, error = 'no_character' }
    end
    if Config.Admin.RequireDutyForActions and not player.adminDuty then
        return nil, { ok = false, error = 'duty_required' }
    end
    if player.jail then
        return nil, { ok = false, error = 'jailed' }
    end
    return player
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

-- /dv: Fahrzeug loeschen (das eigene oder das naechste)
Core.RegisterCallback('admin_vehicle_delete', function(source, data)
    local player, response = check(source, 'vehicle.spawn')
    if not player then return response end
    local netId = tonumber(data.netId)
    if not netId or not Platform.DeleteNetworkedVehicle(netId) then
        return { ok = false, error = 'no_vehicle' }
    end
    log(player, 'vehicle_delete', {
        model = validModel(data.model) and data.model or nil,
        plate = type(data.plate) == 'string' and data.plate:sub(1, 8) or nil,
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
