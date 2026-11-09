-- Orte der Organisationen: Umkleide (Dienst antreten und beenden) und Garage (Dienstfahrzeuge aus- und einparken).
-- Der Server prueft den Abstand mit seiner eigenen Position, den Rang und den Dienst. Der Client spawnt nur.

if FactionsDisabled then
    return
end

local CFG = Config.Factions
local PLATE_DIGITS = 4
local PLATE_TRIES = 20
local PENDING_MS = 15000           -- so lange darf das Ausparken dauern
local STORE_MARGIN = 4.0           -- Spielraum, das Fahrzeug steht neben dem Punkt

local pending = {}                 -- [source] = { plate, model, faction, characterId, at }
local spawned = {}                 -- [netId] = { plate, faction, characterId }

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Naechster Ort dieser Art in Reichweite oder nil
local function nearPlace(source, faction, kind, maxDistance)
    local places = FactionPlaces[faction]
    local position = Platform.GetPlayerPosition(source)
    if not places or not position then
        return nil
    end
    for index, place in ipairs(places[kind] or {}) do
        local point = place.point or place
        if distance(position, point) <= maxDistance then
            return place, index
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Umkleide: Dienst
------------------------------------------------------------------------

Network.RegisterCallback('faction_duty', function(source)
    local member = Factions.MemberOf(source)
    if not member then
        return { ok = false, error = 'not_member' }
    end
    if not nearPlace(source, member.faction, 'lockers', CFG.PlaceDistance) then
        return { ok = false, error = 'too_far' }
    end
    local on = not Factions.IsOnDuty(source, member.faction)
    local ok, err = Factions.SetDuty(source, on, 'locker')
    if not ok then
        return { ok = false, error = err }
    end
    return { ok = true, data = { onDuty = on } }
end)

------------------------------------------------------------------------
-- Garage
------------------------------------------------------------------------

local function outCount(characterId)
    local count = 0
    for _, vehicle in pairs(spawned) do
        if vehicle.characterId == characterId then
            count = count + 1
        end
    end
    return count
end

local function makePlate(org)
    for _ = 1, PLATE_TRIES do
        local plate = ('%s %0' .. PLATE_DIGITS .. 'd'):format(org.platePrefix, math.random(0, 10 ^ PLATE_DIGITS - 1))
        local taken = false
        for _, vehicle in pairs(spawned) do
            if vehicle.plate == plate then
                taken = true
            end
        end
        if not taken then
            return plate
        end
    end
    return nil
end

local function trimPlate(plate)
    return type(plate) == 'string' and plate:match('^%s*(.-)%s*$') or nil
end

-- Was darf ich hier ausparken?
Network.RegisterCallback('faction_garage_list', function(source)
    local member = Factions.MemberOf(source)
    if not member then
        return { ok = false, error = 'not_member' }
    end
    if not Factions.IsOnDuty(source, member.faction) then
        return { ok = false, error = 'not_on_duty' }
    end
    if not nearPlace(source, member.faction, 'garages', CFG.GarageDistance) then
        return { ok = false, error = 'too_far' }
    end
    local list = {}
    for _, vehicle in ipairs(FactionMenu.Vehicles(member.faction)) do
        list[#list + 1] = {
            model = vehicle.model, label = vehicle.label, minRank = vehicle.minRank,
            rankName = Factions.RankName(member.faction, vehicle.minRank),
            allowed = member.rank >= vehicle.minRank or nil,
        }
    end
    return { ok = true, data = { vehicles = list, out = outCount(member.characterId), max = CFG.MaxVehiclesPerMember } }
end)

Network.RegisterCallback('faction_garage_take', function(source, data)
    local member = Factions.MemberOf(source)
    if not member then
        return { ok = false, error = 'not_member' }
    end
    if not Factions.IsOnDuty(source, member.faction) then
        return { ok = false, error = 'not_on_duty' }
    end
    local garage = nearPlace(source, member.faction, 'garages', CFG.GarageDistance)
    if not garage then
        return { ok = false, error = 'too_far' }
    end
    local chosen
    for _, vehicle in ipairs(FactionMenu.Vehicles(member.faction)) do
        if type(data) == 'table' and vehicle.model == data.model then
            chosen = vehicle
        end
    end
    if not chosen then
        return { ok = false, error = 'invalid_model' }
    end
    if member.rank < chosen.minRank then
        return { ok = false, error = 'rank_too_low' }
    end
    if outCount(member.characterId) >= CFG.MaxVehiclesPerMember then
        return { ok = false, error = 'vehicle_limit' }
    end
    local plate = makePlate(Orgs[member.faction])
    if not plate then
        return { ok = false, error = 'server_error' }
    end
    pending[source] = { plate = plate, model = chosen.model, faction = member.faction, characterId = member.characterId, at = Platform.GetTime() }
    return { ok = true, data = { model = chosen.model, plate = plate, spawn = garage.spawn } }
end)

local function vehicleLabel(faction, model)
    for _, vehicle in ipairs(Orgs[faction].vehicles) do
        if vehicle.model == model then
            return vehicle.label or model
        end
    end
    return model
end

-- Der Client meldet das gespawnte Fahrzeug. Nur mit dem Kennzeichen, das der Server vergeben hat.
Network.RegisterCallback('faction_garage_spawned', function(source, data)
    local wait = pending[source]
    pending[source] = nil
    local netId = type(data) == 'table' and tonumber(data.netId)
    if not wait or not netId or Platform.GetTime() - wait.at > PENDING_MS then
        return { ok = false, error = 'no_vehicle' }
    end
    local info = Platform.GetVehicleInfo(netId)
    if not info or trimPlate(info.plate) ~= wait.plate then
        return { ok = false, error = 'no_vehicle' }
    end
    spawned[netId] = { plate = wait.plate, faction = wait.faction, characterId = wait.characterId, model = wait.model }
    Factions.Log({
        actor_account_id = Factions.AccountOf(source),
        character_id = wait.characterId,
        action = 'vehicle_out',
        data = { faction = wait.faction, model = wait.model, plate = wait.plate },
    })
    Factions.Protocol(wait.faction, { area = 'dienst', action = 'vehicle_out', actorSource = source, target = wait.characterId,
        text = ('Dienstfahrzeug %s ausgeparkt, Kennzeichen %s'):format(vehicleLabel(wait.faction, wait.model), wait.plate) })
    return { ok = true }
end)

-- Einparken: jedes Dienstfahrzeug der eigenen Organisation, das neben der Garage steht
Network.RegisterCallback('faction_garage_store', function(source, data)
    local member = Factions.MemberOf(source)
    if not member then
        return { ok = false, error = 'not_member' }
    end
    local netId = type(data) == 'table' and tonumber(data.netId)
    local vehicle = netId and spawned[netId]
    if not vehicle or vehicle.faction ~= member.faction then
        return { ok = false, error = 'not_faction_vehicle' }
    end
    local info = Platform.GetVehicleInfo(netId)
    if not info then
        spawned[netId] = nil
        return { ok = false, error = 'no_vehicle' }
    end
    local garage = nearPlace(source, member.faction, 'garages', CFG.GarageDistance + STORE_MARGIN)
    if not garage or distance(info.position, garage.point) > CFG.GarageDistance + STORE_MARGIN then
        return { ok = false, error = 'too_far' }
    end
    Platform.DeleteNetworkedVehicle(netId)
    spawned[netId] = nil
    Factions.Log({
        actor_account_id = Factions.AccountOf(source),
        character_id = member.characterId,
        action = 'vehicle_in',
        data = { faction = member.faction, plate = vehicle.plate, model = vehicle.model },
    })
    Factions.Protocol(member.faction, { area = 'dienst', action = 'vehicle_in', actorSource = source, target = member.characterId,
        text = ('Dienstfahrzeug %s eingeparkt, Kennzeichen %s'):format(vehicleLabel(member.faction, vehicle.model), vehicle.plate) })
    return { ok = true }
end)

-- Ausgeparkte Fahrzeuge, die es nicht mehr gibt (zerstoert, von einem Admin geloescht), vergessen
local CLEANUP_MS = 60000
Platform.SetInterval(CLEANUP_MS, function()
    for netId in pairs(spawned) do
        if not Platform.GetVehicleInfo(netId) then
            spawned[netId] = nil
        end
    end
end)

local previousUnloaded = Factions.OnUnloaded
function Factions.OnUnloaded(source)
    previousUnloaded(source)
    if source then
        pending[source] = nil
    end
end
