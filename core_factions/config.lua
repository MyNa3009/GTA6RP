-- Einstellungen von core_factions: Organisationen, Raenge, Rechte, Grenzen und Farben.
-- Orte (Umkleide, Garage) und Blips stehen in data/places_gta5.lua, weil sie GTA-5-spezifisch sind.
-- Alles, was die Leitung im Organisationsmenue aendert (Rangnamen, Rechte, Fahrzeuge ab Rang, Abteilungen,
-- Pruefungen), liegt in der Datenbank. Die Werte hier sind nur der Anfang.

Config.Factions = {
    -- Farben des Organisationsmenues als 'R G B' (aus dem Server-Logo). Fehlt ein Wert, gilt Config.UI.Colors der Core.
    Colors = {
        base   = '24 15 36',     -- Hintergrund (Aubergine)
        ink    = '253 241 233',  -- Text (Creme)
        accent = '232 64 190',   -- Auswahl, Hauptaktion (Magenta)
        signal = '240 84 96',    -- Fehler, Entlassen, Strikes (Korallrot)
    },

    -- Organisationsmenue auch per Befehl (sonst G-Menue, Organisation)
    MenuCommand = 'orga',

    -- Grenzen
    MaxDepartments = 12,         -- Abteilungen pro Organisation
    MaxDepartmentRanks = 5,      -- interne Raenge pro Abteilung
    MaxExams = 30,               -- Pruefungen pro Organisation
    MaxStrikes = 10,
    MaxVacationDays = 365,
    ArchivePageSize = 40,
    MaxVehiclesPerMember = 1,    -- gleichzeitig ausgeparkte Dienstfahrzeuge pro Person
    TextMax = { rankName = 32, department = 32, exam = 40, message = 600, reason = 120, dn = 12 },

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
    },

    Organizations = {
        ems = {
            label = 'Emergency Medical Service',
            short = 'EMS',               -- auch Kuerzel auf dem Dienstausweis
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
