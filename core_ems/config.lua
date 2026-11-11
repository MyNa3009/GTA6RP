-- Einstellungen von core_ems (Rettungsdienst). Die Organisation selbst (Raenge, Rechte, Dienst, Kasse) kommt aus
-- core_factions, Organisation 'ems'. Alles Geld aus Verkauf, Behandlung und Versicherung geht in deren Kasse.
-- Animationen, Kamera-Effekte und Gangarten der Symptome stehen in data/symptoms_gta5.lua.

Config.Ems = {
    Faction = 'ems',

    -- Farben der Medizinischen Datenbank. Leer lassen: dann gelten die Farben der Organisation (theme in
    -- core_factions/config.lua) und fuer alles, was dort fehlt, Config.UI.Colors der Core.
    -- Nur eintragen, was bewusst anders sein soll, als 'R G B': base, ink, accent, signal.
    Colors = {},

    -- Rechte, die core_ems bei core_factions anmeldet. minRank: ab diesem Rang, bis die Leitung es im Menue aendert.
    Permissions = {
        { key = 'ems.revive',       group = 'Rettungsdienst', label = 'Hochholen',                                minRank = 1 },
        { key = 'ems.heal',         group = 'Rettungsdienst', label = 'Versorgen (heilen)',                       minRank = 1 },
        { key = 'ems.sell',         group = 'Rettungsdienst', label = 'Verbände, Kästen und Tabletten verkaufen', minRank = 2 },
        { key = 'ems.treat',        group = 'Rettungsdienst', label = 'Untersuchen und behandeln',                minRank = 3 },
        { key = 'ems.insurance',    group = 'Rettungsdienst', label = 'Krankenversicherung verkaufen',            minRank = 5 },
        { key = 'ems.records',      group = 'Rettungsdienst', label = 'Medizinische Datenbank, Ausweis verlangen', minRank = 1 },
        { key = 'ems.records.note', group = 'Rettungsdienst', label = 'Einträge in die Akte schreiben',           minRank = 3 },
        { key = 'ems.records.manage', group = 'Rettungsdienst', label = 'Akte korrigieren (Einträge, Versicherung, Krankheiten)', minRank = 29 },
    },

    -- Abstand zur Person, den der Server prueft (Meter)
    TargetDistance = 3.0,

    -- Hochholen durch Mediziner: schneller Skillcheck mit Taste Z (QWERTZ), braucht keinen Verbandskasten.
    -- Mehrere Runden = mehrere Eintraege.
    Revive = {
        Difficulty = { 'medium', 'medium', 'hard' },
        Keys = { 'Z' },
        Price = 0,                  -- kostet nichts, die Person ist bewusstlos und kann nicht zustimmen
    },

    -- Versorgen durch Mediziner (G-Menue): Minigame, dann heilen. Braucht keinen Verbandskasten.
    Heal = {
        Difficulty = { 'medium', 'medium' },
        Keys = { 'E' },
        Amount = 100,               -- Gesundheit (GTA: 100 = von leer bis voll)
    },

    -- Verbandskasten fuer alle, die keine Mediziner sind: Damit kann man eine bewusstlose Person hochholen
    -- (G-Menue, Person, Hochholen). Kaufen kann man ihn beim Rettungsdienst. Verbraucht wird er erst, wenn das
    -- Minigame klappt. Selbst benutzt (Inventar) heilt er HealSelf.
    Medkit = {
        Difficulty = { 'medium', 'hard' },
        Keys = { 'Z' },
        HealSelf = 50,
    },

    -- Verkauf ueber das G-Menue zu festen Preisen. Die Person stimmt zu und zahlt bar, sonst vom Konto.
    -- Mit Krankenversicherung zahlt sie nur InsuredFactor davon.
    Sell = {
        { item = 'bandage',       price = 60 },
        { item = 'medkit',        price = 250 },
        { item = 'pill_cold',     price = 80 },
        { item = 'pill_headache', price = 60 },
        { item = 'pill_stomach',  price = 80 },
    },
    SellMaxCount = 10,
    PayFrom = { 'cash', 'bank' },

    -- Krankenversicherung: gilt Days Tage (Echtzeit), danach neu kaufen. Behandlungen und alles, was der
    -- Rettungsdienst verkauft, kosten dann nur InsuredFactor vom Preis (0.5 = halber Preis).
    Insurance = {
        Price = 2000,
        Days = 30,
        InsuredFactor = 0.5,
    },

    -- Behandeln: so lange laeuft der Fortschrittsbalken beim Mediziner. Der Server prueft, dass die Zeit vergangen ist.
    TreatDurationMs = 8000,

    -- Medizinische Datenbank
    Records = {
        SearchLimit = 30,
        HistoryLimit = 100,
        NoteMaxLength = 255,
        Command = 'medizin',        -- oeffnet die Datenbank (Mediziner im Dienst mit Recht, Admins mit factions.view)
        -- Akte korrigieren (Eintraege aendern und loeschen, Versicherung setzen, Krankheiten setzen oder heilen):
        -- Mediziner mit dem Recht ems.records.manage und Admins mit diesem Core-Recht (auch ohne Dienst)
        AdminPermission = 'factions.manage',
        InsuranceMaxDays = 365,     -- so weit in die Zukunft darf man die Versicherung von Hand setzen
    },

    -- Krankheiten. Die Uhr laeuft nur, solange man online ist.
    --   cure = 'pill': Tablette senkt um ein Stadium (Stadium 1 = geheilt), Mediziner heilt sofort. Nie toedlich.
    --   cure = 'treatment': nur der Mediziner. treatments: so viele Behandlungen pro Stadium ({ 3, 4, 5 } = Stadium 1
    --   braucht 3, Stadium 2 braucht 4, Stadium 3 braucht 5), alle innerhalb von windowMinutes, mit mindestens gapMinutes
    --   Abstand. Ohne Behandlung wird es alle worsenMinutes schlimmer. Im letzten Stadium bricht man zusammen
    --   (bewusstlos). Hochholen vor Ort geht dann nicht mehr, nur das Krankenhaus (Admins mit /revive schon).
    --   Danach steht die Krankheit wieder auf afterCollapseStage und muss weiter behandelt werden.
    -- chance: pro Minute online (base), zusaetzlich pro Minute nass (wet), pro Minute Stress (stress: rennen,
    --   zielen, schiessen), pro gegessenem Essen (food). 0.001 pro Minute sind rund 6 Prozent pro Stunde.
    -- contagious: steckt andere an. chance pro Minute, die jemand naeher als distance Meter steht, mal Stadium.
    --   0.01 im Stadium 1 sind rund 45 Prozent, wenn man eine Stunde direkt daneben steht (Stadium 3: 84 Prozent).
    -- symptoms[stadium]: Liste von Symptomen, every = ungefaehr alle so viele Sekunden (mit Zufall).
    --   cough, headache, nausea, vomit, sneeze: Animation oder Meldung
    --   blur (seconds), shake (seconds, intensity), blackout (ms), stumble (ms), minimap (seconds), forget
    --   nosprint, walk (style): gelten durchgehend, solange das Stadium besteht
    -- needs[stadium]: zusaetzlich Hunger und Durst pro Minute (Magen-Darm)
    Diseases = {
        cold = {
            label = 'Erkältung', cure = 'pill', pill = 'pill_cold', stages = 3, worsenMinutes = 90, price = 150,
            chance = { base = 0.0003, wet = 0.004 },
            contagious = { chance = 0.01, distance = 3.0 },
            symptoms = {
                { { kind = 'cough', every = 300 } },
                { { kind = 'cough', every = 150 }, { kind = 'sneeze', every = 360 }, { kind = 'blur', every = 420, seconds = 6 } },
                { { kind = 'cough', every = 90 }, { kind = 'blur', every = 240, seconds = 8 }, { kind = 'nosprint' } },
            },
        },
        headache = {
            label = 'Kopfschmerzen', cure = 'pill', pill = 'pill_headache', stages = 3, worsenMinutes = 60, price = 120,
            chance = { base = 0.0004, stress = 0.002 },
            symptoms = {
                { { kind = 'headache', every = 360 }, { kind = 'blur', every = 360, seconds = 5 } },
                { { kind = 'headache', every = 240 }, { kind = 'shake', every = 240, seconds = 8, intensity = 0.3 } },
                { { kind = 'headache', every = 150 }, { kind = 'shake', every = 180, seconds = 10, intensity = 0.5 }, { kind = 'blackout', every = 300, ms = 1000 } },
            },
        },
        stomach = {
            label = 'Magen-Darm', cure = 'pill', pill = 'pill_stomach', stages = 3, worsenMinutes = 90, price = 150,
            chance = { base = 0.0002, food = 0.02 },
            contagious = { chance = 0.006, distance = 2.0 },
            symptoms = {
                { { kind = 'nausea', every = 300 } },
                { { kind = 'nausea', every = 240 }, { kind = 'vomit', every = 360 } },
                { { kind = 'vomit', every = 180 }, { kind = 'stumble', every = 300, ms = 2500 }, { kind = 'walk', style = 'sick' } },
            },
            needs = { nil, { hunger = -0.5, thirst = -1 }, { hunger = -1, thirst = -2 } },
        },
        hypertension = {
            label = 'Bluthochdruck', cure = 'treatment', stages = 4, treatments = { 3, 4, 5 }, windowMinutes = 60, gapMinutes = 10,
            worsenMinutes = 60, afterCollapseStage = 2, price = 400,
            chance = { base = 0.0001, stress = 0.0006 },
            symptoms = {
                { { kind = 'shake', every = 360, seconds = 6, intensity = 0.2 } },
                { { kind = 'shake', every = 240, seconds = 8, intensity = 0.35 }, { kind = 'blackout', every = 360, ms = 1500 }, { kind = 'nosprint' } },
                { { kind = 'blackout', every = 180, ms = 2500 }, { kind = 'stumble', every = 300, ms = 3000 }, { kind = 'nosprint' }, { kind = 'walk', style = 'sick' } },
            },
        },
        dementia = {
            label = 'Demenz', cure = 'treatment', stages = 4, treatments = { 3, 4, 5 }, windowMinutes = 60, gapMinutes = 10,
            worsenMinutes = 60, afterCollapseStage = 2, price = 500,
            chance = { base = 0.00003 },
            symptoms = {
                { { kind = 'forget', every = 480 } },
                { { kind = 'forget', every = 300 }, { kind = 'minimap', every = 360, seconds = 20 } },
                { { kind = 'forget', every = 180 }, { kind = 'minimap', every = 240, seconds = 45 }, { kind = 'blackout', every = 300, ms = 2000 }, { kind = 'walk', style = 'confused' } },
            },
        },
    },
    DiseaseOrder = { 'cold', 'headache', 'stomach', 'hypertension', 'dementia' },

    MaxActiveDiseases = 2,          -- mehr bekommt man nicht gleichzeitig
    ImmuneAfterCureMinutes = 60,    -- nach einer Heilung bekommt man dieselbe Krankheit so lange nicht wieder
    TickSeconds = 60,               -- so oft rechnet der Server (Krankheiten, Ansteckung)
    SaveEveryTicks = 5,             -- so oft wird der Stand gespeichert (Stadienwechsel sofort)
    ExposureReportSeconds = 60,     -- so oft meldet der Client, ob man nass war oder Stress hatte
    PillCooldownMinutes = 5,        -- so lange wirkt eine Tablette, eine zweite davor bringt nichts
    FoodItems = { 'bread', 'sandwich' },

    -- Admins: Krankheit setzen oder heilen (zum Testen und fuer RP-Szenen)
    AdminPermission = 'player.heal',
}
