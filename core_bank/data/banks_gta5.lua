-- GTA-5-spezifisch: Filialen der Bank (Schalter), Blip und Markierung. Beim Umzug wird nur diese Datei ersetzt.
-- Die Koordinaten sind die Schalter der normalen Banken ohne MLO. Mit einem MLO hier anpassen.

BankBranches = {
    { label = 'Fleeca Bank, Legion Square',    x = 149.9,    y = -1040.5, z = 29.4 },
    { label = 'Fleeca Bank, Alta',             x = 314.2,    y = -278.8,  z = 54.2 },
    { label = 'Fleeca Bank, Burton',           x = -350.9,   y = -49.6,   z = 49.0 },
    { label = 'Fleeca Bank, Rockford Hills',   x = -1213.0,  y = -330.6,  z = 37.8 },
    { label = 'Fleeca Bank, Great Ocean Hwy',  x = -2962.6,  y = 482.6,   z = 15.7 },
    { label = 'Fleeca Bank, Route 68',         x = 1175.0,   y = 2706.6,  z = 38.1 },
    { label = 'Pacific Standard, Vinewood',    x = 247.0,    y = 223.1,   z = 106.3 },
    { label = 'Blaine County Savings, Paleto', x = -112.2,   y = 6469.3,  z = 31.6 },
}

-- Blip auf der Karte (GTA-Sprite 108 = Dollar, Farbe 2 = Gruen)
BankBlip = { sprite = 108, color = 2, scale = 0.75, label = 'Bank' }

-- Markierung am Boden am Schalter (GTA-Markertyp 27 = flacher Kreis)
BankMarker = { type = 27, size = 0.9, height = 0.9, zOffset = -0.95, alpha = 150, rotate = true }
