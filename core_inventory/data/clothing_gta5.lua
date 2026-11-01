-- GTA-5-Kleidung. Plattformabhaengig, fuer GTA 6 kommt hier spaeter eine eigene Datei hin.
-- Server und Client laden sie: der Client zieht damit an.

-- Welcher Platz welche Komponente (Kleidung) oder welches Prop (Zubehoer) ist
ClothingSlots = {
    mask    = { component = 1 },
    jacket  = { component = 11 },   -- Oberteil
    shirt   = { component = 8 },    -- T-Shirt: ohne Jacke als Oberteil, unter einer Jacke als Unterhemd
    gloves  = { component = 3 },    -- Arme mit Handschuhen
    pants   = { component = 4 },
    shoes   = { component = 6 },
    hat     = { prop = 0 },
    glasses = { prop = 1 },
    ears    = { prop = 2 },
    watch   = { prop = 6 },
}
ClothingTopComponent = 11
ClothingArmsComponent = 3

-- Das Aussehen jedes Kleidungs-Items (ClothingLooks) steht in data/clothing_catalog_gta5.lua.

-- Was bei leerem Platz gilt: { drawable, texture }. Props ohne Eintrag werden abgenommen.
ClothingNaked = {
    male = {
        mask   = { 0, 0 },
        jacket = { 15, 0 },
        shirt  = { 15, 0 },
        gloves = { 15, 0 },   -- Arme ohne Oberteil
        pants  = { 61, 0 },
        shoes  = { 34, 0 },
    },
    female = {
        mask   = { 0, 0 },
        jacket = { 15, 0 },
        shirt  = { 14, 0 },
        gloves = { 15, 0 },
        pants  = { 17, 0 },
        shoes  = { 35, 0 },
    },
}
