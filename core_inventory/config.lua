-- Einstellungen des Inventars. Die Farben, die Tastatur und das Netzwerk kommen aus der Config der Core.
-- Gewichte in Gramm (1000 = 1 kg), damit es keine Rundungsfehler gibt.

Config.Inventory = {
    Slots = 10,             -- Taschen-Plaetze ohne Rucksack: 1 bis 5 Schnellzugriff, 6 bis 10 eine Reihe Taschen
    MaxWeight = 15000,      -- 15 kg
    HotbarSlots = 5,        -- Plaetze 1 bis 5 sind der Schnellzugriff (Tasten 1 bis 5)

    -- Rucksack-Level: Level 1 bis 3 geben je eine Reihe (5 Plaetze) frei, Level 4 zwei Reihen auf einmal. Welches Item welches Level ist,
    -- steht in data/items.lua (bagLevel). Das hoechste Level bestimmt, wie viele Plaetze das Fenster zeigt.
    Backpacks = {
        [1] = { slots = 5,  maxWeight = 10000 },  -- 10 kg
        [2] = { slots = 10, maxWeight = 15000 },  -- 15 kg
        [3] = { slots = 15, maxWeight = 20000 },  -- 20 kg
        [4] = { slots = 25, maxWeight = 30000 },  -- 30 kg, zwei Reihen mehr als Level 3
    },

    -- Ausruestung. Kleidung zaehlt nicht zum Gewicht, solange man sie traegt.
    EquipSlots = {
        { id = 'mask',     label = 'Maske',          clothing = true },
        { id = 'hat',      label = 'Kopfbedeckung',  clothing = true },
        { id = 'glasses',  label = 'Brille',         clothing = true },
        { id = 'ears',     label = 'Ohrringe',       clothing = true },
        { id = 'jacket',   label = 'Jacke',          clothing = true },
        { id = 'shirt',    label = 'T-Shirt',        clothing = true },
        { id = 'watch',    label = 'Uhr',            clothing = true },
        { id = 'gloves',   label = 'Handschuhe',     clothing = true },
        { id = 'pants',    label = 'Hose',           clothing = true },
        { id = 'shoes',    label = 'Schuhe',         clothing = true },
        { id = 'weapon',   label = 'Waffe' },
        { id = 'backpack', label = 'Rucksack' },
    },

    -- Bekommt jeder neue Charakter einmal (Kleidung kommt in einer spaeteren Version dazu)
    StartItems = {
        { name = 'water', count = 2 },
        { name = 'bread', count = 2 },
    },
    -- Den Personalausweis bekommt jeder Charakter automatisch (auch bestehende), er steht nicht hier.

    -- Startoutfit: bekommt jeder Charakter einmal angezogen (auch bestehende, die noch keine Kleidung haben).
    -- Item-Namen aus data/items.lua, sie kommen in ihren Platz.
    StartOutfit = {
        male   = { 'shirt_white', 'pants_jeans', 'shoes_sneaker' },
        female = { 'shirt_white', 'pants_jeans', 'shoes_sneaker' },
    },

    -- Dokumente: eigene Reihe im Inventar, an den Charakter gebunden (nicht ablegen, geben oder wegnehmen).
    -- Lizenzen laufen nach LicenseDays ab (echte Tage), der Personalausweis und der Dienstausweis nie.
    -- Den Dienstausweis stellt das Orga-Script beim Beitritt aus (exports.core_inventory:IssueServiceCard) und entzieht ihn beim Austritt.
    Documents = {
        Slots = {
            { id = 'doc_id',      item = 'id_card',         label = 'Ausweis' },
            { id = 'doc_driver',  item = 'license_driver',  label = 'Führerschein' },
            { id = 'doc_weapon',  item = 'license_weapon',  label = 'Waffenschein' },
            { id = 'doc_pilot',   item = 'license_pilot',   label = 'Flugschein' },
            { id = 'doc_boat',    item = 'license_boat',    label = 'Bootsschein' },
            { id = 'doc_fishing', item = 'license_fishing', label = 'Angelschein' },
            { id = 'doc_service', item = 'service_card',    label = 'Dienstausweis' },
        },
        Issuer = 'State of San Andreas',  -- steht oben auf Ausweis und Lizenzen
        -- Volle Namen bekannter Orgas fuer den Dienstausweis (Kuerzel -> Name). Das Orga-Script kann auch selbst einen Namen schicken.
        ServiceOrgs = {
            LSPD = 'Los Santos Police Department',
            LSSD = 'Los Santos County Sheriff',
            SAHP = 'San Andreas Highway Patrol',
            LSMD = 'Los Santos Medical Department',
            DOJ  = 'Department of Justice',
        },
        LicenseDays = 30,
        DriverClasses = {           -- Klassen des Fuehrerscheins; requires = braucht vorher diese Klasse
            B = { label = 'PKW' },
            C = { label = 'LKW und Transporter', requires = 'B' },
        },
        ShowSeconds = 10,           -- so lange sieht die andere Person die Karte
        ShowDistance = 3.0,         -- so nah muss man stehen
    },

    -- Durchsuchen: nur wenn die Person die Haende oben hat oder gefesselt ist
    Search = {
        Distance = 2.0,
        HandsUpKey = 'X',           -- Haende hoch, im Spiel aenderbar
    },

    -- Kofferraum: Groesse nach Fahrzeugklasse in data/trunks_gta5.lua, Inhalt am Kennzeichen gespeichert
    Trunk = {
        Distance = 4.0,             -- so nah am Fahrzeug (Mitte) muss man stehen, der Client prueft das Heck genauer
        HeckDistance = 1.8,         -- Abstand zum Heck auf dem Client
    },

    -- Lager aus anderen Scripts (exports.core_inventory:OpenStash). Groesse gibt das Script vor.
    Stash = {
        Distance = 3.0,             -- Standard, wenn das Script eine Position mitgibt
        MaxSlots = 100,
    },

    OpenKey = 'F2',             -- Standardtaste, im Spiel aenderbar

    -- GTA-Waffenrad (Tab, Mausrad, Zifferntasten) sperren. Die Tasten 1 bis 5 gehoeren dem Schnellzugriff.
    BlockWeaponWheel = true,

    GiveDistance = 3.0,         -- so nah muss man am anderen Spieler stehen (Meter)

    -- Auf dem Boden abgelegte Items
    Drops = {
        Slots = 30,
        PickupDistance = 2.5,   -- so nah muss man dran sein, um etwas aufzuheben
        MergeDistance = 1.5,    -- wer naeher als das an einem Haufen ablegt, legt dazu
        LifetimeMinutes = 30,   -- danach verschwindet der Haufen (steht im Log)
        ShowDistance = 40.0,    -- bis hierhin sieht man den Haufen
    },
    SaveIntervalMs = 5000,      -- geaenderte Inventare werden so oft gespeichert
    MaxCountPerCommand = 10000, -- /giveitem und /removeitem
}
