-- Einstellungen der core_lib. Farben kommen aus Config.UI.Colors der Core, das Menue hat eigene (Config.Lib.Menu.Colors).

Config.Lib = {
    ------------------------------------------------------------------------
    -- G-Menue (Interaktionsmenue)
    ------------------------------------------------------------------------
    Interact = {
        -- Standardtaste auf einer deutschen Tastatur. Jeder kann sie im Spiel aendern:
        -- Einstellungen > Tastenbelegung > FiveM > "Interaktionsmenü öffnen"
        Key = 'G',
        Command = 'interaktion',
        -- Ziel ist die Person, die man anschaut, hoechstens so weit weg (Meter)
        PlayerDistance = 3.0,
        -- Zu Fuss: das Fahrzeug, auf das man schaut, hoechstens so weit weg (Meter bis zur Karosserie)
        VehicleDistance = 3.5,
        -- Blickziel: Kreis am Boden unter der Person, leuchtende Umrandung um das Fahrzeug.
        -- Schaut man auf eine Person, gilt die Person. Wer in einem Fahrzeug sitzt, ist kein Personen-Ziel.
        -- Aussehen von Kreis und Umrandung in data/target_gta5.lua.
        Target = {
            MaxAngle = 12,          -- so viele Grad neben der Bildmitte zaehlt noch als "angeschaut"
            IntervalMs = 150,       -- so oft wird das Blickziel gesucht (nur bei geschlossenem Menue)
            KeepTolerance = 1.0,    -- bei offenem Menue darf sich die Person so viele Meter weiter entfernen
            Color = '232 64 190',   -- Farbe des Kreises als 'R G B' (Magenta aus dem Logo)
            Alpha = 200,            -- Deckkraft 0 bis 255
            VehicleColor = '232 64 190',  -- Farbe der Umrandung um das Fahrzeug
            VehicleAlpha = 255,
            -- Bei offenem Menue bleibt das Fahrzeug Ziel bis zu diesem Abstand zur Fahrzeugmitte.
            -- Gilt auch fuer Tueren und Einsteigen von aussen.
            VehicleKeepDistance = 6.0,
        },
        -- Sitz wechseln nur bis zu dieser Geschwindigkeit
        SeatChangeMaxKmh = 5,
        -- Nach einer Aktion mit keepOpen wird das Menue so viel spaeter neu aufgebaut
        RefreshDelayMs = 150,
        -- Grenzen fuer Eintraege anderer Scripts
        MaxEntries = 500,
        MaxDepth = 4,

        -- Feste Kategorien im Kreis, im Uhrzeigersinn ab oben. Andere Scripts koennen weitere anlegen.
        -- Platz ist fuer bis zu 8 Kategorien.
        Categories = {
            { name = 'Person',       icon = 'user',     order = 10 },
            { name = 'Fahrzeug',     icon = 'car',      order = 20 },
            { name = 'Organisation', icon = 'building', order = 30 },
        },

        -- Dokumente unter Person > Ausweis zeigen (Typen aus dem Inventar)
        Documents = {
            { type = 'id',      label = 'Personalausweis' },
            { type = 'driver',  label = 'Führerschein' },
            { type = 'weapon',  label = 'Waffenschein' },
            { type = 'service', label = 'Dienstausweis' },
            { type = 'pilot',   label = 'Flugschein' },
            { type = 'boat',    label = 'Bootsschein' },
            { type = 'fishing', label = 'Angelschein' },
        },

        -- Geld geben: Grenzen nur fuer das Eingabefeld, pruefen tut das Inventar
        GiveCash = { Min = 1, Max = 1000000 },
    },

    ------------------------------------------------------------------------
    -- Aussehen des Menues (G-Menue und Kontextmenues). Werte als 'R G B', Farben aus dem Logo.
    -- base oder ink weglassen: dann gelten Hintergrund und Schrift aus Config.UI.Colors der Core.
    ------------------------------------------------------------------------
    Menu = {
        Colors = {
            base   = '24 15 36',     -- Hintergrund, das dunkle Aubergine aus dem Logo
            ink    = '253 241 233',  -- Text, das Creme aus dem Logo
            accent = '232 64 190',   -- gewaehlte Kategorie im Kreis (Magenta)
            mark   = '244 152 105',  -- Ueberschrift der Liste, Icons, Hinweise (Pfirsich)
        },
    },

    ------------------------------------------------------------------------
    -- Fortschrittsbalken
    ------------------------------------------------------------------------
    Progress = {
        MinDurationMs = 250,
        MaxDurationMs = 10 * 60 * 1000,
        MaxLabelLength = 60,
    },

    ------------------------------------------------------------------------
    -- Minigames
    ------------------------------------------------------------------------
    Minigames = {
        SkillCheck = {
            -- area: Breite der Zielzone in Grad, speed: Umdrehungen pro Sekunde
            Difficulties = {
                easy   = { area = 64, speed = 0.55 },
                medium = { area = 44, speed = 0.75 },
                hard   = { area = 28, speed = 1.00 },
            },
            Keys = { 'E' },          -- Standardtaste, wenn das Script keine eigenen vorgibt
            MaxStages = 10,
        },
        Lockpick = {
            Pins = 5,
            Attempts = 3,             -- so viele Fehlversuche, dann bricht der Dietrich
            ZoneSize = 0.18,          -- Anteil der Bahn, in dem der Stift einrastet
            Speed = 0.9,              -- Bahnlaengen pro Sekunde
            TimeLimitMs = 45000,
        },
        Hack = {
            GridSize = 4,             -- 4 x 4 Felder
            StartLength = 3,          -- Laenge der ersten Folge
            Rounds = 3,               -- jede Runde ist ein Feld laenger
            StepMs = 520,             -- so lange leuchtet ein Feld beim Zeigen
            TimeLimitMs = 20000,      -- Zeit pro Runde zum Nachgeben
        },
        Wires = {
            Count = 4,
            TimeLimitMs = 15000,
        },
        -- Vom Server gestartete Minigames (exports.core_lib:StartMinigame)
        Server = {
            RequestTimeoutMs = 3 * 60 * 1000,
            -- Schneller als das kann niemand fertig sein. Kuerzere Ergebnisse gelten als nicht geschafft und werden geloggt.
            MinDurationMs = { skillcheck = 250, lockpick = 1500, hack = 2500, wires = 1200 },
            CleanupIntervalMs = 30000,
        },
    },

    ------------------------------------------------------------------------
    -- Dialoge, Kontextmenues, TextUI
    ------------------------------------------------------------------------
    Dialog = {
        MaxFields = 12,
        MaxTextLength = 500,
        MaxOptions = 50,
    },
    Context = {
        MaxOptions = 60,
        MaxDepth = 6,
    },
    TextUi = {
        MaxLength = 80,
    },

    -- Wartezeit beim Pruefen auf Ergebnisse (init.lua in anderen Resources)
    ResultPollMs = 50,
}
