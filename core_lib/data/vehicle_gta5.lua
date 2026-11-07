-- GTA-5-spezifisch: Tueren, Fenster und Sitze eines Fahrzeugs fuer das G-Menue. Beim Umzug wird nur diese Datei ersetzt.
-- key ist der stabile Name fuer die Logik, index der GTA-Index fuer die Bridge.

LibVehicleData = {
    Doors = {
        { key = 'front_left',  index = 0, label = 'Fahrertür' },
        { key = 'front_right', index = 1, label = 'Beifahrertür' },
        { key = 'rear_left',   index = 2, label = 'Tür hinten links' },
        { key = 'rear_right',  index = 3, label = 'Tür hinten rechts' },
        { key = 'hood',        index = 4, label = 'Motorhaube' },
        { key = 'trunk',       index = 5, label = 'Kofferraum' },
    },

    -- seat: Sitz, von dem aus man dieses Fenster auch als Mitfahrer bedienen darf
    Windows = {
        { key = 'front_left',  index = 0, seat = -1, label = 'Fenster vorne links' },
        { key = 'front_right', index = 1, seat = 0,  label = 'Fenster vorne rechts' },
        { key = 'rear_left',   index = 2, seat = 1,  label = 'Fenster hinten links' },
        { key = 'rear_right',  index = 3, seat = 2,  label = 'Fenster hinten rechts' },
    },

    DriverSeat = -1,
    Seats = {
        [-1] = 'Fahrersitz',
        [0]  = 'Beifahrersitz',
        [1]  = 'Hinten links',
        [2]  = 'Hinten rechts',
    },
    -- Weitere Sitze (Busse, Transporter): Nummer ab 1 fuer den ersten Sitz hinter Reihe 2
    SeatFallback = 'Sitz %d',
    SeatFallbackOffset = -2,
}
