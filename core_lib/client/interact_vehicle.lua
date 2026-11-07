-- G-Menue, Kategorie Fahrzeug: Motor, Licht, Tueren, Fenster, Sitz wechseln, Kofferraum.
-- Tueren und Fenster aendert nur, wer drin sitzt (Fahrer alle, Mitfahrer nur das eigene Fenster).
-- Abschliessen gehoert spaeter zum Schluessel-Script, darum nichts von aussen ausser dem Kofferraum.
if LibDisabled then return end

local CFG = Config.Lib.Interact
local DATA = LibVehicleData
local INVENTORY = 'core_inventory'
local OWNER = 'core_lib'
local MAX_SEAT_INDEX = 14     -- Busse haben bis zu 16 Sitze

local function vehicleOf(ctx)
    return ctx.vehicle and ctx.vehicle.handle
end

local function onOff(on)
    return on and 'an' or 'aus'
end

Interact.SetCategory('Fahrzeug/Türen', { icon = 'door', order = 30 })
Interact.SetCategory('Fahrzeug/Fenster', { icon = 'window', order = 40 })
Interact.SetCategory('Fahrzeug/Sitz wechseln', { icon = 'seat', order = 50 })

Interact.Add({
    id = 'vehicle_engine',
    path = 'Fahrzeug',
    label = 'Motor',
    icon = 'power',
    order = 10,
    vehicle = 'driver',
    keepOpen = true,
    state = function(ctx) return onOff(ctx.vehicle.engine) end,
    onSelect = function(ctx)
        Platform.SetVehicleEngine(vehicleOf(ctx), not ctx.vehicle.engine)
    end,
}, OWNER)

Interact.Add({
    id = 'vehicle_lights',
    path = 'Fahrzeug',
    label = 'Licht',
    icon = 'light',
    order = 20,
    vehicle = 'driver',
    keepOpen = true,
    state = function(ctx) return onOff(ctx.vehicle.lights) end,
    onSelect = function(ctx)
        Platform.SetVehicleLights(vehicleOf(ctx), not ctx.vehicle.lights)
    end,
}, OWNER)

for index, door in ipairs(DATA.Doors) do
    Interact.Add({
        id = 'vehicle_door_' .. door.key,
        path = 'Fahrzeug/Türen',
        label = door.label,
        icon = 'door',
        order = index,
        vehicle = 'driver',
        keepOpen = true,
        canShow = function(ctx) return Platform.HasVehicleDoor(vehicleOf(ctx), door.index) end,
        state = function(ctx) return Platform.IsVehicleDoorOpen(vehicleOf(ctx), door.index) and 'offen' or 'zu' end,
        onSelect = function(ctx)
            local vehicle = vehicleOf(ctx)
            Platform.SetVehicleDoor(vehicle, door.index, not Platform.IsVehicleDoorOpen(vehicle, door.index))
        end,
    }, OWNER)
end

Interact.Add({
    id = 'vehicle_doors_close',
    path = 'Fahrzeug/Türen',
    label = 'Alle schließen',
    icon = 'close',
    order = #DATA.Doors + 1,
    vehicle = 'driver',
    keepOpen = true,
    canShow = function(ctx)
        for _, door in ipairs(DATA.Doors) do
            if Platform.IsVehicleDoorOpen(vehicleOf(ctx), door.index) then
                return true
            end
        end
        return false
    end,
    onSelect = function(ctx)
        Platform.CloseAllVehicleDoors(vehicleOf(ctx))
    end,
}, OWNER)

for index, window in ipairs(DATA.Windows) do
    Interact.Add({
        id = 'vehicle_window_' .. window.key,
        path = 'Fahrzeug/Fenster',
        label = window.label,
        icon = 'window',
        order = index,
        vehicle = 'inside',
        keepOpen = true,
        canShow = function(ctx)
            return (ctx.vehicle.isDriver or ctx.vehicle.seat == window.seat) and Platform.HasVehicleWindow(vehicleOf(ctx), window.index)
        end,
        state = function(ctx) return Platform.IsVehicleWindowDown(vehicleOf(ctx), window.index) and 'unten' or 'oben' end,
        onSelect = function(ctx)
            local vehicle = vehicleOf(ctx)
            Platform.SetVehicleWindow(vehicle, window.index, not Platform.IsVehicleWindowDown(vehicle, window.index))
        end,
    }, OWNER)
end

local function seatLabel(seat)
    return DATA.Seats[seat] or DATA.SeatFallback:format(seat + DATA.SeatFallbackOffset)
end

local function isSeatFree(ctx, seat)
    for _, free in ipairs(ctx.vehicle.freeSeats or {}) do
        if free == seat then
            return true
        end
    end
    return false
end

for seat = DATA.DriverSeat, MAX_SEAT_INDEX do
    Interact.Add({
        id = 'vehicle_seat_' .. tostring(seat),
        path = 'Fahrzeug/Sitz wechseln',
        label = seatLabel(seat),
        icon = 'seat',
        order = seat,
        vehicle = 'inside',
        canShow = function(ctx)
            return ctx.vehicle.speedKmh <= CFG.SeatChangeMaxKmh and isSeatFree(ctx, seat)
        end,
        onSelect = function(ctx)
            local state = Platform.GetOwnVehicleState()
            if not state or state.speedKmh > CFG.SeatChangeMaxKmh then
                Lib.Notify('Erst anhalten, dann den Sitz wechseln.', 'error')
                return
            end
            if not Platform.MoveToSeat(state.vehicle, seat) then
                Lib.Notify('Der Sitz ist nicht mehr frei.', 'error')
            end
        end,
    }, OWNER)
end

Interact.Add({
    id = 'vehicle_trunk',
    path = 'Fahrzeug',
    label = 'Kofferraum öffnen',
    description = 'Stell dich direkt ans Heck.',
    icon = 'package',
    order = 60,
    vehicle = 'outside',
    canShow = function() return Platform.IsResourceStarted(INVENTORY) end,
    onSelect = function()
        Platform.CallExport(INVENTORY, 'OpenNearestTrunk')
    end,
}, OWNER)
