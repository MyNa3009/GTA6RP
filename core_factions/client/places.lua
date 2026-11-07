-- Orte im Client: Blip auf der Karte, Markierung am Boden, Hinweis mit E.
-- Umkleide: Dienst antreten oder beenden. Garage: Dienstfahrzeug ausparken (nur im Dienst) oder einparken.
-- Markierung und Hinweis sieht nur, wer in dieser Organisation ist. Den Blip sehen alle (z. B. Krankenhaus).

if FactionsDisabled then
    return
end

local CFG = Config.Factions
local MARKER_DISTANCE = 15.0       -- ab hier wird die Markierung gezeichnet
local SPAWN_TIMEOUT_MS = 5000
local KEY = 'interact'

local blips = {}
local busy = false
local keyWasDown = false

local function color()
    local own = CFG.Colors and CFG.Colors.accent or Config.UI.Colors.accent
    local r, g, b = own:match('^(%d+) (%d+) (%d+)$')
    return { r = tonumber(r), g = tonumber(g), b = tonumber(b) }
end

local MARKER_COLOR = color()

local function styled(style)
    local copy = {}
    for k, v in pairs(style) do
        copy[k] = v
    end
    copy.color = MARKER_COLOR
    return copy
end

local LOCKER_STYLE = styled(FactionMarkers.locker)
local GARAGE_STYLE = styled(FactionMarkers.garage)

-- Taste nur einmal pro Druck (nicht jedes Frame, solange sie gehalten wird)
local function pressedOnce()
    local down = Platform.IsActionPressed(KEY)
    local pressed = down and not keyWasDown
    keyWasDown = down
    return pressed
end

local function mine(faction)
    local state = FactionClient.state
    return state.member == true and state.faction == faction
end

------------------------------------------------------------------------
-- Umkleide
------------------------------------------------------------------------

local function toggleDuty()
    busy = true
    local result = Network.Call('faction_duty', {})
    busy = false
    if not result or not result.ok then
        FactionClient.Error(result and result.error)
        return
    end
    FactionClient.Notify(result.data.onDuty and 'Du bist jetzt im Dienst.' or 'Du hast den Dienst beendet.', 'success')
end

------------------------------------------------------------------------
-- Garage
------------------------------------------------------------------------

local function takeVehicle(model)
    local result = Network.Call('faction_garage_take', { model = model })
    if not result or not result.ok then
        FactionClient.Error(result and result.error)
        return
    end
    local vehicle, netId = Platform.SpawnVehicleAt(result.data.model, result.data.plate, result.data.spawn, SPAWN_TIMEOUT_MS)
    if not vehicle then
        FactionClient.Notify('Das Fahrzeug konnte nicht geladen werden.', 'error')
        return
    end
    local reported = Network.Call('faction_garage_spawned', { netId = netId })
    if not reported or not reported.ok then
        FactionClient.Error(reported and reported.error)
    end
end

local function openGarage(faction)
    busy = true
    local result = Network.Call('faction_garage_list', {})
    busy = false
    if not result or not result.ok then
        FactionClient.Error(result and result.error)
        return
    end
    local options = {}
    for _, vehicle in ipairs(result.data.vehicles) do
        options[#options + 1] = {
            title = vehicle.label,
            description = vehicle.allowed and 'Ausparken' or ('Ab %s'):format(vehicle.rankName),
            icon = 'car',
            disabled = not vehicle.allowed or result.data.out >= result.data.max,
            onSelect = function(model)
                Platform.Async(function()
                    takeVehicle(model)
                end)
            end,
            args = vehicle.model,
        }
    end
    if result.data.out >= result.data.max then
        table.insert(options, 1, { title = 'Du hast schon ein Fahrzeug draußen', description = 'Erst einparken, dann ein neues holen.', readOnly = true })
    end
    lib.registerContext({ id = 'core_factions_garage_' .. faction, title = 'Dienstfahrzeuge', options = options })
    lib.showContext('core_factions_garage_' .. faction)
end

local function storeVehicle()
    local vehicle = Platform.GetDrivenVehicle()
    local info = vehicle and Platform.GetVehicleInfo(vehicle)
    if not info or not info.netId then
        FactionClient.Error('not_faction_vehicle')
        return
    end
    busy = true
    local result = Network.Call('faction_garage_store', { netId = info.netId })
    busy = false
    if not result or not result.ok then
        FactionClient.Error(result and result.error)
        return
    end
    FactionClient.Notify('Fahrzeug eingeparkt.', 'success')
end

------------------------------------------------------------------------
-- Punkte anlegen
------------------------------------------------------------------------

local function hint(text)
    lib.showTextUI(text, { key = Platform.GetActionLabel(KEY), position = 'left' })
end

for faction, places in pairs(FactionPlaces) do
    if places.blip then
        blips[#blips + 1] = Platform.AddBlip(places.blip)
    end

    for _, locker in ipairs(places.lockers or {}) do
        lib.points.new({
            coords = locker,
            distance = MARKER_DISTANCE,
            nearby = function(self)
                if not mine(faction) then
                    return
                end
                Platform.DrawMarkerAt(locker, LOCKER_STYLE)
                if self.currentDistance and self.currentDistance <= CFG.PlaceDistance then
                    hint(FactionClient.state.onDuty and 'Dienst beenden' or 'Dienst antreten')
                    if pressedOnce() and not busy then
                        Platform.Async(toggleDuty)
                    end
                    self.hinted = true
                elseif self.hinted then
                    self.hinted = false
                    lib.hideTextUI()
                end
            end,
            onExit = function(self)
                if self.hinted then
                    self.hinted = false
                    lib.hideTextUI()
                end
            end,
        })
    end

    for _, garage in ipairs(places.garages or {}) do
        lib.points.new({
            coords = garage.point,
            distance = MARKER_DISTANCE,
            nearby = function(self)
                if not mine(faction) or not FactionClient.state.onDuty then
                    if self.hinted then
                        self.hinted = false
                        lib.hideTextUI()
                    end
                    return
                end
                Platform.DrawMarkerAt(garage.point, GARAGE_STYLE)
                if self.currentDistance and self.currentDistance <= CFG.GarageDistance then
                    local driving = Platform.GetDrivenVehicle() ~= nil
                    hint(driving and 'Fahrzeug einparken' or 'Dienstfahrzeug ausparken')
                    if pressedOnce() and not busy then
                        Platform.Async(function()
                            if driving then
                                storeVehicle()
                            else
                                openGarage(faction)
                            end
                        end)
                    end
                    self.hinted = true
                elseif self.hinted then
                    self.hinted = false
                    lib.hideTextUI()
                end
            end,
            onExit = function(self)
                if self.hinted then
                    self.hinted = false
                    lib.hideTextUI()
                end
            end,
        })
    end
end

Platform.OnEvent('onResourceStop', function(resource)
    if resource == Platform.GetResourceName() then
        for _, blip in ipairs(blips) do
            Platform.RemoveBlip(blip)
        end
    end
end)
