-- Einstellungen von core_dispatch: Notrufe an Organisationen und das MDT ihrer Einheiten.
-- Tasten so, wie sie auf einer deutschen Tastatur stehen (die Core tauscht Y und Z selbst).

Config.Dispatch = {
    -- Wer Notrufe bekommt. faction: Organisation aus core_factions. Mit dem ersten Wort waehlt man den Dienst:
    -- "/dispatch ems Person bewusstlos". Ohne passendes Wort geht der Notruf an DefaultService.
    -- prefix: Einsatznummer, z. B. "EMS 26/0042" (Jahr/laufende Nummer)
    Services = {
        { key = 'ems', faction = 'ems', label = 'Rettungsdienst', prefix = 'EMS',
          words = { 'ems', 'rd', 'medic', 'rettung', 'rettungsdienst' } },
    },
    DefaultService = 'ems',

    Commands = {
        Dispatch = 'dispatch',     -- /dispatch Text: Notruf. Ohne Text: Formular (oder MDT, wenn man im Dienst ist)
        Mdt = 'mdt',               -- MDT oeffnen (im Dienst). Admins: /mdt ems
        Status = 'status',         -- /status 3: eigener Funkstatus
    },
    Keys = {
        Accept = 'J',              -- letzten Alarm uebernehmen
        Mdt = 'F6',                -- MDT oeffnen
    },

    -- Texte
    TextMin = 5,
    TextMax = 240,
    LocationMax = 80,
    MessageMax = 160,              -- Nachricht an den Anrufer
    NoteMax = 240,
    ReportMax = 600,               -- Abschlussbericht
    CallsignMax = 16,              -- Funkrufname, z. B. "RTW 1/83-1"

    -- Missbrauch und Spam
    CooldownSeconds = 60,          -- zwischen zwei Notrufen derselben Person
    MaxOpenPerCaller = 2,          -- offene Notrufe pro Person
    AbuseBlockMinutes = 30,        -- nach "Missbrauch" keine Notrufe mehr fuer so lange

    AlertSeconds = 15,             -- so lange steht ein neuer Alarm am Bildschirmrand
    ArriveDistance = 40,           -- so nah am Einsatzort: Status 4 (am Einsatzort) automatisch
    ArriveCheckMs = 5000,
    HistoryPageSize = 25,          -- Archiv
    MyCallsShown = 5,              -- eigene Notrufe im Formular

    Priorities = {
        { level = 1, label = 'Normal' },
        { level = 2, label = 'Dringend' },
        { level = 3, label = 'Lebensgefahr' },
    },
    -- Anrufer bewusstlos: mindestens diese Prioritaet
    DownPriority = 2,

    -- Funkstatus wie beim FMS der BOS. 0 und 5 gehen an die Leitstelle, 0 ist ein Notruf der Einheit selbst.
    Statuses = {
        [0] = 'Notruf: Einheit in Gefahr',
        [1] = 'Einsatzbereit über Funk',
        [2] = 'Einsatzbereit auf Wache',
        [3] = 'Einsatz übernommen',
        [4] = 'Am Einsatzort',
        [5] = 'Sprechwunsch',
        [6] = 'Nicht einsatzbereit',
        [7] = 'Patient aufgenommen',
        [8] = 'Am Krankenhaus',
    },
    StatusOnDuty = 2,              -- beim Dienstantritt
    StatusOnAccept = 3,
    StatusOnArrive = 4,
    StatusOnClose = 1,
    FreeStatuses = { [1] = true, [2] = true },   -- frei fuer neue Einsaetze (Vorschlag "naechste freie Einheit")

    -- Abschluss eines Einsatzes. block = true: Anrufer wird fuer AbuseBlockMinutes gesperrt.
    Results = {
        { key = 'done',        label = 'Erledigt vor Ort' },
        { key = 'transport',   label = 'Transport ins Krankenhaus' },
        { key = 'no_person',   label = 'Niemand vor Ort' },
        { key = 'false_alarm', label = 'Fehlalarm' },
        { key = 'duplicate',   label = 'Doppelt gemeldet' },
        { key = 'abuse',       label = 'Missbrauch', block = true },
    },

    -- Admins: MDT ansehen (/mdt ems) und mit Manage-Recht wie die Leitstelle arbeiten
    AdminViewPermission = 'factions.view',
    AdminManagePermission = 'factions.manage',

    -- Rechte pro Rang in core_factions (Organisationsmenue, Anpassung). Startwerte:
    Permissions = {
        { key = 'dispatch.view',   group = 'Leitstelle (MDT)', label = 'MDT nutzen, Alarme bekommen, Einsätze übernehmen', minRank = 1 },
        { key = 'dispatch.manage', group = 'Leitstelle (MDT)', label = 'Disponieren: zuweisen, Priorität, alle Einsätze abschließen', minRank = 18 },
        { key = 'dispatch.archive', group = 'Leitstelle (MDT)', label = 'Einsatzarchiv und Statistik', minRank = 6 },
    },
}
