-- GTA-5-spezifisch: Umkleide (Dienst antreten) und Garage jeder Organisation, Blips und Markierungen.
-- Koordinaten fuer das normale Pillbox-Krankenhaus. Mit einem MLO hier anpassen. Beim Umzug wird nur diese Datei ersetzt.

FactionPlaces = {
    ems = {
        blip = { coords = { x = 298.6, y = -584.5, z = 43.3 }, sprite = 61, color = 1, scale = 0.85, label = 'Krankenhaus' },
        -- Umkleide: hier mit E den Dienst antreten oder beenden
        lockers = {
            { x = 298.6, y = -598.3, z = 43.3 },
        },
        -- Garage: hier ausparken und einparken. spawn = Stelle, an der das Fahrzeug erscheint
        garages = {
            { point = { x = 294.6, y = -574.6, z = 43.2 }, spawn = { x = 291.2, y = -567.4, z = 43.2, heading = 68.0 } },
        },
    },
}

-- Markierung am Boden fuer Umkleide und Garage (GTA-Markertyp 27 = flacher Kreis)
FactionMarkers = {
    locker = { type = 27, size = 1.0, height = 1.0, zOffset = -0.95, alpha = 160, rotate = true },
    garage = { type = 36, size = 1.2, height = 1.2, zOffset = 0.2,  alpha = 160, rotate = true },   -- 36 = Auto-Symbol
}
