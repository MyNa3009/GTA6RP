-- GTA-5-spezifisch: Kreis am Boden unter der Person und Umrandung um das Fahrzeug, das man anschaut (G-Menue).
-- Beim Umzug wird nur diese Datei ersetzt.
-- type ist der GTA-Markertyp: 27 = Kreis aus zwei Boegen mit Pfeilen, dreht sich mit rotate. 25 = schlichter duenner Kreis.

LibTargetData = {
    Ring = {
        type = 27,
        size = 1.1,        -- Durchmesser in Metern
        zOffset = -0.98,   -- vom Mittelpunkt des Peds bis zum Boden
        rotate = true,     -- dreht sich langsam, damit man ihn sofort sieht
    },
    -- Umrandung um das Fahrzeug. shader: 0 = weicher Schein (leuchtet), 1 = harte Linie 2 px breit.
    Outline = {
        shader = 0,
    },
}
