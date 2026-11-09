-- Einstellungen von core_factions: Organisationen, Raenge, Rechte, Grenzen und Farben.
-- Orte (Umkleide, Garage) und Blips stehen in data/places_gta5.lua, weil sie GTA-5-spezifisch sind.
-- Alles, was die Leitung im Organisationsmenue aendert (Rangnamen, Rechte, Fahrzeuge ab Rang, Abteilungen,
-- Pruefungen), liegt in der Datenbank. Die Werte hier sind nur der Anfang.

Config.Factions = {
    -- Grundfarben des Organisationsmenues als 'R G B'. Jede Organisation kann sie mit eigenen Farben (theme)
    -- ueberschreiben, siehe unten. Fehlt ein Wert, gilt Config.UI.Colors der Core.
    Colors = {
        base   = '24 15 36',     -- Hintergrund (Aubergine)
        ink    = '253 241 233',  -- Text (Creme)
        accent = '232 64 190',   -- Auswahl, Hauptaktion (Magenta)
        signal = '240 84 96',    -- Fehler, Entlassen, Strikes (Korallrot)
    },

    -- Organisationsmenue auch per Befehl (sonst G-Menue, Organisation)
    MenuCommand = 'orga',

    -- Gehalt: Leader und Vice Leader legen es pro Rang fest (Organisationsmenue, Anpassung). Ausgezahlt wird
    -- nach je IntervalMinutes im Dienst, aus der Kasse der Organisation aufs Konto. Ist die Kasse leer, gibt es nichts.
    Salary = {
        Max = 1000,
        IntervalMinutes = 60,
    },

    -- Bonus: Leader und Vice Leader zahlen einer Person aus der Kasse etwas extra aufs Konto (Leitstelle),
    -- hoechstens Max pro Zahlung und einmal pro Kalendertag je Person.
    Bonus = {
        Max = 1000,
    },

    -- Grenzen
    MaxDivisions = 5,            -- Divisionen pro Organisation (Ranggruppen wie Command, Supervisor)
    MaxInfoSections = 30,        -- Abschnitte unter Erklaerungen
    MaxDepartments = 12,         -- Abteilungen pro Organisation
    MaxDepartmentRanks = 5,      -- interne Raenge pro Abteilung
    MaxExams = 30,               -- Pruefungen pro Organisation
    MaxStrikes = 10,
    MaxVacationDays = 365,
    ArchivePageSize = 40,
    MaxVehiclesPerMember = 1,    -- gleichzeitig ausgeparkte Dienstfahrzeuge pro Person
    TextMax = { rankName = 32, department = 32, exam = 40, message = 600, reason = 120, dn = 12,
        division = 32, infoTitle = 60, infoBody = 3000, examDescription = 1500, rankTasks = 300 },

    -- Bereiche unter Erklaerungen (Reihenfolge wie hier). Pruefungen und Raenge mit Rechten kommen automatisch dazu.
    InfoCategories = {
        { key = 'rules',   label = 'Regeln' },
        { key = 'process', label = 'Abläufe' },
        { key = 'info',    label = 'Wichtig' },
    },

    -- Protokolle (Organisationsmenue, Tab Protokolle): jede Aenderung mit wer, an wem, was. Lesen mit Recht logs.view.
    -- Eintraege werden nie geaendert oder geloescht. Bereiche in dieser Reihenfolge als Filter.
    Protocol = {
        PageSize = 50,
        Areas = {
            { key = 'leitstelle', label = 'Leitstelle' },
            { key = 'einsatz',    label = 'Einsatz' },      -- z. B. Hochholen, Behandeln, Verkaufen (core_ems)
            { key = 'datenbank',  label = 'Datenbank' },    -- z. B. Akte angesehen, Eintrag geschrieben (core_ems)
            { key = 'kasse',      label = 'Kasse' },
            { key = 'dienst',     label = 'Dienst' },       -- Dienst an und aus, Dienstfahrzeuge
            { key = 'anpassung',  label = 'Anpassung' },    -- Raenge, Rechte, Abteilungen, Pruefungen, Divisionen, Erklaerungen
        },
    },

    -- Abstand zur Umkleide und Garage, den der Server prueft (Meter)
    PlaceDistance = 3.0,
    GarageDistance = 6.0,

    -- Rechte, die jede Organisation hat. minRank: ab diesem Rang, solange die Leitung nichts aendert.
    -- Der Leader (hoechster Rang) hat immer alles. Rechte einzelner Organisationen (z. B. ems.revive) melden
    -- deren Scripts ueber exports.core_factions:RegisterPermissions an.
    Permissions = {
        { key = 'leitstelle.view',     group = 'Leitstelle', label = 'Leitstelle ansehen',             minRank = 1 },
        { key = 'members.hire',        group = 'Leitstelle', label = 'Einstellen',                     minRank = 24 },
        { key = 'members.fire',        group = 'Leitstelle', label = 'Entlassen',                      minRank = 26 },
        { key = 'members.rank',        group = 'Leitstelle', label = 'Befördern und degradieren',      minRank = 24 },
        { key = 'members.dn',          group = 'Leitstelle', label = 'Dienstnummer ändern',            minRank = 24 },
        { key = 'members.strikes',     group = 'Leitstelle', label = 'Strikes vergeben',               minRank = 22 },
        { key = 'members.vacation',    group = 'Leitstelle', label = 'Urlaubstage ändern',             minRank = 22 },
        { key = 'members.departments', group = 'Leitstelle', label = 'Abteilungen zuweisen',           minRank = 20 },
        { key = 'members.exams',       group = 'Leitstelle', label = 'Prüfungen eintragen',            minRank = 15 },
        { key = 'archive.view',        group = 'Verwaltung', label = 'Mitarbeiter-Archiv ansehen',     minRank = 20 },
        { key = 'message.edit',        group = 'Verwaltung', label = 'Nachricht vom Leader ändern',    minRank = 29 },
        { key = 'cash.view',           group = 'Verwaltung', label = 'Kasse ansehen',                  minRank = 25 },
        { key = 'cash.manage',         group = 'Verwaltung', label = 'Kasse ein- und auszahlen',       minRank = 28 },
        { key = 'logs.view',           group = 'Verwaltung', label = 'Protokolle ansehen',             minRank = 27 },
    },

    Organizations = {
        ems = {
            label = 'Emergency Medical Service',
            short = 'EMS',               -- auch Kuerzel auf dem Dienstausweis
            -- Logo im Organisationsmenue (Datei in html/logos/) und Farben der Organisation als 'R G B'.
            -- accent: Auswahl, Hauptaktion, Kopf. mark: zweite Farbe (Hervorhebungen, Entlassen, Strikes).
            -- base: Hintergrund (dunkel, leicht in Richtung der Organisation getoent). ink: Schrift.
            logo = 'logos/ems.png',
            theme = {
                base   = '9 14 28',
                ink    = '240 244 250',
                accent = '37 94 190',    -- Blau aus dem Stern
                mark   = '237 28 36',    -- Rot aus dem Ring
            },
            ranks = 30,
            leaderRank = 30,             -- Leader: hat immer alle Rechte, setzt nur ein Admin (/setorga)
            viceRank = 29,               -- Vice Leader: Raenge, Rechte, Fahrzeuge, Abteilungen wie der Leader
            dnPrefix = 'EMS-',           -- Dienstnummer bei der Einstellung: EMS-001, EMS-002 ...
            platePrefix = 'EMS',         -- Kennzeichen der Dienstfahrzeuge: EMS 4821
            rankNames = {
                'Praktikant', 'Rettungssanitäter-Anwärter', 'Rettungssanitäter', 'Rettungssanitäter II',
                'Rettungssanitäter III', 'Notfallsanitäter-Anwärter', 'Notfallsanitäter', 'Notfallsanitäter II',
                'Notfallsanitäter III', 'Praxisanleiter', 'Assistenzarzt', 'Assistenzarzt II', 'Assistenzarzt III',
                'Arzt', 'Arzt II', 'Facharzt', 'Facharzt II', 'Notarzt', 'Notarzt II', 'Oberarzt', 'Oberarzt II',
                'Leitender Oberarzt', 'Stationsleitung', 'Wachleitung', 'Bereichsleitung', 'Ärztlicher Leiter',
                'Stellv. Direktor', 'Direktor', 'Vice Leader', 'Leader',
            },
            -- Dienstfahrzeuge. minRank kann die Leitung im Menue aendern (Tab Fahrzeuge).
            vehicles = {
                { model = 'ambulance', label = 'Rettungswagen',      minRank = 1 },
                { model = 'lguard',    label = 'Einsatzfahrzeug',    minRank = 7 },
                { model = 'firetruk',  label = 'Großraum-Rettung',   minRank = 18 },
            },
        },
    },
}
