-- Automatisch erzeugt von tools/kleidung.py aus tools/kleidung_auswahl.json. Nicht von Hand aendern.
-- Nummern und Bilder: FiveM-ClothingData (Colbss), Game Build 3407.

ClothingItems = {
    mask_balaclava = { label = 'Sturmhaube', weight = 100, stack = 1, equip = 'mask', description = 'Schwarze Sturmhaube.' },
    hat_beanie = { label = 'Mütze', weight = 120, stack = 1, equip = 'hat', description = 'Schwarze Strickmütze.' },
    glasses_sun = { label = 'Pilotenbrille', weight = 50, stack = 1, equip = 'glasses', description = 'Getönte Gläser.' },
    ears_studs = { label = 'Ohrringe gold', weight = 10, stack = 1, equip = 'ears', description = 'Goldener Ohrschmuck.' },
    jacket_bomber = { label = 'Bomberjacke schwarz', weight = 900, stack = 1, equip = 'jacket', description = 'Kurze Jacke mit Bündchen.' },
    shirt_white = { label = 'Weißes T-Shirt', weight = 200, stack = 1, equip = 'shirt', description = 'Schlichtes T-Shirt.' },
    watch_gold = { label = 'Goldene Armbanduhr', weight = 80, stack = 1, equip = 'watch', description = 'Schwer und glänzend.' },
    gloves_leather = { label = 'Handschuhe schwarz', weight = 150, stack = 1, equip = 'gloves', description = 'Schwarze Handschuhe.' },
    pants_jeans = { label = 'Jeans blau', weight = 600, stack = 1, equip = 'pants', description = 'Blaue Jeans.' },
    pants_cargo = { label = 'Cargohose oliv', weight = 650, stack = 1, equip = 'pants', description = 'Mit vielen Taschen.' },
    shoes_sneaker = { label = 'Sneaker weiß', weight = 700, stack = 1, equip = 'shoes', description = 'Bequeme Turnschuhe.' },
}

-- { globale drawable-Nummer, Farbe, Arme } pro Modell, under = so unter einer Jacke
ClothingLooks = {
    mask_balaclava = { male = { 56, 1 }, female = { 56, 1 } },
    hat_beanie = { male = { 5, 0 }, female = { 5, 0 } },
    glasses_sun = { male = { 5, 0 }, female = { 11, 0 } },
    ears_studs = { male = { 3, 0 }, female = { 12, 1 } },
    jacket_bomber = { male = { 74, 1, 4 } },
    shirt_white = { male = { 1, 0, 0, under = { 15, 0 } }, female = { 2, 0, 0, under = { 14, 0 } } },
    watch_gold = { male = { 4, 0 }, female = { 2, 0 } },
    gloves_leather = { male = { 17, 0 }, female = { 16, 1 } },
    pants_jeans = { male = { 0, 0 }, female = { 0, 0 } },
    pants_cargo = { male = { 9, 0 }, female = { 11, 0 } },
    shoes_sneaker = { male = { 7, 0 }, female = { 1, 0 } },
}

for name, def in pairs(ClothingItems) do
    Items[name] = def
end
