Config = {}

------------------------------------------------------------------------
-- Aussehen der Core-UIs (Login usw.)
-- Farben als RGB-Kanaele mit Leerzeichen, z. B. '214 164 72'
------------------------------------------------------------------------
-- Tastatur der Spieler. Alle Standardtasten in dieser Datei sind so geschrieben, wie sie auf DIESER Tastatur stehen.
-- 'de' = deutsche Tastatur (QWERTZ), 'us' = englische Tastatur (QWERTY). FiveM selbst rechnet immer mit QWERTY,
-- die Core tauscht darum Y und Z automatisch.
Config.Keyboard = {
    Layout = 'de',
}

Config.UI = {
    ServerName = 'Testserver',
    Colors = {
        base   = '14 15 18',    -- Hintergrund
        ink    = '232 234 237', -- Text und neutrale Flaechen
        accent = '214 164 72',  -- Hauptaktion, Auswahl
        signal = '220 82 72',   -- Fehler und Warnungen
        info   = '84 140 220',  -- Hinweise ohne Gefahr, z. B. Twink-Interaktionen im Admin-Menue
    },
    -- So lange bleibt die Erfolgsmeldung nach dem Login sichtbar
    SuccessDelayMs = 900,
    -- Waehrung fuer Geldanzeigen (ISO-Code, z. B. 'USD' oder 'EUR')
    Currency = 'USD',
}

------------------------------------------------------------------------
-- Charaktere
------------------------------------------------------------------------
Config.Characters = {
    MaxPerAccount = 3,
    NameMinLength = 2,
    NameMaxLength = 20,
    MinAge = 18,
    MaxAge = 90,
    UniqueNames = true,        -- Vor- und Nachname zusammen duerfen nur einmal vorkommen
    StartCash = 500,
    StartBank = 2500,
    SavePositionIntervalMs = 60000, -- Position regelmaessig speichern (zusaetzlich beim Verlassen)
}

------------------------------------------------------------------------
-- Teamraenge und Rechte
-- Jeder Rang hat automatisch alle Rechte der Raenge mit kleinerem level.
-- id: kurz, ohne Leerzeichen, wird im Befehl /setrank benutzt
-- '*' heisst: alle Rechte
--
-- Rechte:
--   admin.menu       Admin-Menue oeffnen
--   admin.duty       Admin-Dienst (/aduty)
--   player.view      Spieler, Charaktere und deren komplette Historie ansehen
--   player.revive    wiederbeleben
--   player.teleport  zu Spielern teleportieren, Spieler holen
--   admin.noclip     Noclip (/nc), nur im Admin-Dienst
--   vehicle.spawn    Fahrzeuge spawnen (/car)
--   vehicle.delete   Fahrzeuge loeschen (/dv), auch ausserhalb des Admin-Diensts
--   vehicle.boost    Fahrzeug, in dem man am Steuer sitzt, schneller machen (/boost)
--   player.ajail     Admin-Jail geben und entlassen
--   player.kick      kicken
--   player.rename    Namen eines Charakters aendern (/namechange)
--   player.warn      verwarnen
--   player.ban       bannen (ganzer Account oder einzelner Charakter)
--   player.unban     entbannen
--   accounts.links   Multi-Account-Warnungen ausblenden und wieder anzeigen
--   money.manage     Geld geben und nehmen
--   ranks.manage     Raenge vergeben (nur unterhalb des eigenen Rangs)
--   admin.keys       Admin-Keys erstellen und loeschen (nur fuer Raenge unterhalb des eigenen)
--   data.private     echte Personendaten sehen (E-Mail, IP)
------------------------------------------------------------------------
Config.Ranks = {
    { id = 'player',      level = 0, label = 'Spieler',                    permissions = {} },
    { id = 'assistant',   level = 1, label = 'Administrator Assistant',    permissions = { 'admin.menu', 'admin.duty', 'player.view', 'admin.message', 'admin.esp', 'tickets.manage' } },
    { id = 'junior',      level = 2, label = 'Junior Administrator',       permissions = { 'player.revive', 'player.teleport', 'player.ajail', 'admin.noclip', 'player.freeze', 'player.heal', 'vehicle.fix', 'vehicle.delete', 'admin.dimension', 'player.spectate' } },
    { id = 'admin',       level = 3, label = 'Administrator',              permissions = { 'player.kick', 'accounts.links', 'player.dimension', 'player.kill', 'player.rename' } },
    { id = 'serveradmin', level = 4, label = 'Server Administrator',       permissions = { 'player.warn', 'player.ban', 'vehicle.spawn', 'player.silentkick', 'weapon.give', 'admin.mass' } },
    { id = 'senior',      level = 5, label = 'Senior Administrator',       permissions = { 'player.unban', 'money.manage', 'vehicle.boost', 'items.manage', 'admin.keys' } },
    { id = 'deputy',      level = 6, label = 'Deputy Chief Administrator', permissions = { 'ranks.manage', 'data.private' } },
    { id = 'chief',       level = 7, label = 'Chief Administrator',        permissions = { '*' } },
}
Config.DefaultRank = 'player'

-- Admin-Keys: Jedes Teammitglied braucht einen eigenen Key. Bis er eingegeben ist, hat es keine Rechte, wie ein Spieler.
-- Eingabe einmal pro Sitzung beim ersten /aduty oder F10, gilt bis Relog oder Disconnect.
-- Erstellen im Admin-Menue in der Akte (Recht admin.keys), nur fuer Raenge unter dem eigenen.
-- Den ersten Key gibt die Server-Konsole: adminkey <permanente ID>
Config.AdminKeys = {
    Enabled = true,
    MaxAttempts = 5,   -- so viele falsche Versuche, dann gesperrt
    LockMinutes = 15,  -- so lange gesperrt, das Team bekommt eine Meldung
}

------------------------------------------------------------------------
-- Admin-Menue und Admin-Dienst
------------------------------------------------------------------------
Config.Admin = {
    OpenKey = 'F10',              -- Standardtaste, jeder Spieler kann sie in den GTA-Einstellungen aendern
    RequireDutyForActions = true, -- Wiederbeleben, Teleport, Geld usw. nur im Admin-Dienst
    LogPageSize = 50,             -- Eintraege pro Seite in der Akte
    SearchLimit = 25,
}

-- Tickets (/report fuer Spieler, /tickets und /claim fuer das Team mit Recht tickets.manage)
Config.Tickets = {
    PlayerCooldownSeconds = 25, -- so lange muss ein Spieler zwischen zwei Nachrichten warten, das Team nicht
    MessageMinLength = 3,
    MessageMaxLength = 500,
    NotifyOffDuty = false,      -- true: auch Teammitglieder ausserhalb des Admin-Diensts bekommen neue Tickets gemeldet
    HistoryLimit = 20,          -- so viele alte Tickets sieht ein Spieler
    ListLimit = 50,             -- so viele Tickets pro Liste im Team
    MessageLimit = 200,         -- so viele Nachrichten werden pro Ticket geladen
    Categories = {
        { id = 'question', label = 'Frage' },
        { id = 'bug',      label = 'Bug oder Fehler' },
        { id = 'report',   label = 'Regelverstoß melden' },
        { id = 'other',    label = 'Sonstiges' },
    },
}

-- Admin-Erkennungsmodus (Tab im Admin-Dienst): ueber jedem Spieler Name, IDs, Rang, Gesundheit und offene Warnungen
Config.AdminEsp = {
    Key = 'TAB',            -- Standardtaste, im Spiel aenderbar unter "Admin-Erkennungsmodus an oder aus"
    Distance = 150.0,       -- so weit, auch durch Waende
    RefreshMs = 3000,       -- so oft fragt der Client den Server nach Warnungen, Rang usw.
    Scale = 0.3,
    HeightOffset = 1.0,     -- Abstand ueber dem Kopf in Metern (vier Zeilen brauchen Platz)
    Color = { 255, 255, 255, 235 },
}

-- Admin-Werkzeuge: /freeze, /kill, /heal, /armor, /fixcars, /cartp, /dim, /setdim, /dm, /silentk, /gun, /regun
-- Ziele: permanente ID (/heal 17), Umkreis in Metern (/heal r 20) oder alle im Spiel (/heal all, Recht admin.mass)
Config.AdminTools = {
    MaxRadius = 250.0,          -- groesster Umkreis fuer "r <meter>"
    ArmorValue = 100,           -- /armor ohne Wert
    DefaultWeapon = 'pistol',   -- /gun ohne Waffe
    DefaultAmmo = 250,
    MaxAmmo = 9999,
    MaxDimension = 9999,        -- 0 ist die normale Welt
    MessageMaxLength = 250,     -- /dm
    LookDistance = 30.0,        -- /fixcars ohne Umkreis: so weit wird nach dem Fahrzeug gesucht, auf das man schaut
    CarTeleportOffset = 4.0,    -- /cartp zu einem Spieler: so viele Meter daneben, damit niemand im Auto steckt
    -- /silentk: Das sieht der Spieler. Absichtlich wie ein Verbindungsabbruch, der echte Grund steht nur im Log.
    SilentKickReason = 'Server->client connection timed out. Last seen 3482 msec ago.',
}

Config.AdminDuty = {
    Alpha = 150,          -- Durchsichtigkeit fuer alle (0 unsichtbar, 255 normal)
    Invincible = true,    -- im Dienst unverwundbar
    TagDistance = 40.0,   -- so weit sehen Spieler den Admin-Namen, auch durch Waende
    -- Eine Zeile pro Eintrag. Platzhalter: {rank}, {name}, {id}
    TagLines = { '{rank}', '{name} | ID: {id}' },
    Scale = 0.4,
    HeightOffset = 0.5,
    Color = { 255, 70, 70, 255 },
    Glow = { 255, 0, 0, 170 },  -- Leuchten um die Schrift
}

-- Noclip (/nc). Geschwindigkeit in Metern pro Sekunde.
-- Steuerung: W A S D, Leertaste hoch, Strg runter, Shift schnell, Alt langsam
Config.Noclip = {
    -- Standardtaste (deutsche Tastatur, siehe Config.Keyboard). Jeder kann sie im Spiel aendern:
    -- Einstellungen > Tastenbelegung > FiveM > "Noclip an oder aus"
    Key = 'Z',
    Speed = 30.0,
    FastSpeed = 350.0,          -- mit Shift
    SlowSpeed = 6.0,            -- mit Alt
    -- true: W fliegt dahin, wohin die Kamera schaut. Maus nach unten = nach unten fliegen, nach oben = nach oben.
    -- false: W und S fliegen immer waagerecht, hoch und runter nur mit Leertaste und Strg.
    FollowCameraPitch = true,
    Invisible = true,        -- fuer alle anderen unsichtbar
    VisibleForSelf = false,  -- true: man sieht sich selbst trotzdem
    GroundOnExit = true,     -- beim Ausschalten auf den Boden darunter, auch aus der Luft
}

-- Admin-Fahrzeuge
Config.Vehicles = {
    Plate = 'ADMIN',            -- Kennzeichen gespawnter Fahrzeuge (hoechstens 8 Zeichen)
    ModelLoadTimeoutMs = 5000,  -- so lange wird auf das Modell gewartet
    DeleteRadius = 6.0,         -- /dv loescht das Fahrzeug, in dem man sitzt, sonst das naechste in diesem Umkreis
    MaxBoostPercent = 300,      -- /boost 300 = bis zu 300 % schneller
    BoostTopSpeedKmh = 500,     -- Hoechstgeschwindigkeit mit Boost
}

------------------------------------------------------------------------
-- Strafen: Bans und A-Jail
-- Der Ort des A-Jails steht in data/jail_gta5.lua
------------------------------------------------------------------------
Config.Punish = {
    ReasonMinLength = 3,
    ReasonMaxLength = 200,
}

Config.Bans = {
    MaxDays = 365,      -- laengste zeitliche Sperre, alles darueber nur mit "perm"
    -- Beim Verbinden abgelehnt, wenn einer dieser Identifier zu einem gebannten Account gehoert.
    -- Das faengt auch Zweit-Accounts auf derselben Rockstar-Lizenz ab.
    BlockIdentifiers = { 'license', 'license2', 'fivem', 'discord' },
    -- Auch abgelehnt, wenn der PC (Hardware-Token) zu einem gebannten Login gehoert
    BlockHardware = true,
    -- Steht unter der Ban-Meldung, leer lassen fuer nichts
    AppealText = 'Entbannungsantrag im Discord stellen.',
    -- Zusaetzliche Sicherheit: so oft wird geprueft, ob jemand Online gebannt ist (auch in Login und Charakterauswahl).
    -- Der Kick beim Bannen selbst passiert sofort, das hier faengt nur Sonderfaelle ab (z. B. Ban direkt in der Datenbank).
    CheckIntervalMs = 10000,
}

Config.Jail = {
    MaxMinutes = 1440,          -- laengstes A-Jail (24 Stunden)
    CheckIntervalMs = 1000,     -- so oft prueft der Server, ob jemand ausserhalb ist
    SaveIntervalSeconds = 30,   -- Restzeit regelmaessig speichern
    EscapeLogCooldownSeconds = 60, -- Fluchtversuche hoechstens so oft ins Log, gezaehlt werden alle
    DisableCombat = true,       -- im A-Jail nicht schiessen und nicht schlagen
}

------------------------------------------------------------------------
-- Geld
------------------------------------------------------------------------
Config.Money = {
    -- Hoechster Betrag pro Buchung, faengt Tippfehler und Script-Fehler ab
    MaxAmount = 100000000,
    -- Geldanzeige oben rechts
    Hud = true,
    -- Bargeld liegt als Item "cash" im Inventar dieser Resource (die Bank bleibt in der Core).
    -- nil = Bargeld wie frueher in der Spalte characters.cash.
    CashInventory = 'core_inventory',
    -- So lange bleibt "+500 $" neben dem Kontostand stehen
    DeltaVisibleMs = 3000,
}

------------------------------------------------------------------------
-- Tod und Bewusstlosigkeit
------------------------------------------------------------------------
Config.Death = {
    -- Ab wann man sich selbst ins Krankenhaus bringen darf (auf dem Live-Server eher 300 oder mehr)
    HospitalAfterSeconds = 60,
    -- So lange muss die Taste gehalten werden
    HoldToRespawnMs = 1500,
}

------------------------------------------------------------------------
-- Hunger und Durst (0 bis 100). Der Server rechnet, der Client zeigt nur an.
------------------------------------------------------------------------
Config.Needs = {
    Enabled = true,
    -- So viele Minuten echte Spielzeit von voll bis leer
    HungerMinutes = 120,
    ThirstMinutes = 90,
    -- Alle so viele Sekunden rechnet der Server neu
    TickSeconds = 10,
    -- Bei 0: alle DamageIntervalSeconds so viel Gesundheit weg (GTA: 100 Punkte von voll bis bewusstlos)
    DamageIntervalSeconds = 10,
    DamagePerNeed = 2,
    -- Nach Krankenhaus oder Wiederbeleben mindestens so viel, sonst geht es sofort weiter abwaerts
    AfterRespawn = 40,
    -- Ab hier wird die Leiste rot
    LowAt = 20,
    -- Kein Abfall waehrend Admin-Dienst und im A-Jail
    PauseOnAdminDuty = true,
    PauseInJail = true,
    -- true: Leisten nur, wenn die Minimap zu sehen ist. false: immer (ausser im Pausemenue),
    -- auch wenn ein anderes Script die Minimap zu Fuss ausblendet.
    HideWithMinimap = false,
    -- Eingebaute Leisten neben der Minimap. Ein eigenes HUD-Script kann sie abschalten und
    -- die Werte ueber exports.core:GetNeeds() oder das Ereignis core:needsChanged lesen.
    Hud = true,
}

------------------------------------------------------------------------
-- ID ueber dem Kopf
------------------------------------------------------------------------
Config.Overhead = {
    Enabled = true,
    Label = 'ID: {id}',         -- Platzhalter: {id}
    Distance = 12.0,            -- in Metern
    RequireLineOfSight = true,  -- keine IDs durch Waende
    ShowOwn = false,            -- zum Testen allein auf true setzen
    RefreshMs = 250,            -- wie oft die Spieler in der Naehe neu gesucht werden
    Scale = 0.35,
    HeightOffset = 0.35,        -- Abstand ueber dem Kopf in Metern
    Color = { 255, 255, 255, 220 },
}

------------------------------------------------------------------------
-- Accounts und Login
------------------------------------------------------------------------
Config.Accounts = {
    PasswordMinLength = 8,
    PasswordMaxLength = 72,   -- Grenze des Passwort-Hashings
    EmailMaxLength = 255,
    OneAccountPerDevice = true, -- pro Spiel-Lizenz nur ein Account
    RememberEmail = true,       -- E-Mail des Accounts auf diesem Geraet im Login schon eintragen
    -- Warnung im Admin-Menue, wenn sich mehrere Accounts diese Identifier teilen.
    -- license und license2 sind die Rockstar- bzw. Social-Club-Lizenz.
    MultiAccountIdentifiers = { 'license', 'license2' },
}

------------------------------------------------------------------------
-- Geraete: Accountsharing und Multi-Accounts ueber den PC erkennen
-- FiveM liefert pro PC mehrere Hardware-Tokens. Ein Login an einem PC ohne einen
-- bekannten Token gibt eine rote Warnung in der Akte und im Chat aller Admins.
------------------------------------------------------------------------
Config.Devices = {
    Enabled = true,
    -- Mehrere Logins auf demselben PC auch als Multi-Account melden
    HardwareMultiAccount = true,
    -- IP-Adressen nur als Zusatzinfo (nur mit Recht data.private sichtbar), nie als Ausloeser
    StoreIp = true,
    IpRetentionDays = 30,       -- danach werden IPs geloescht (Datenschutz)
}

------------------------------------------------------------------------
-- Twinks: Charaktere derselben Person (gleicher Login oder verknuepfte Logins)
-- 'warn'  = erlaubt, landet blau in der Akte
-- 'block' = wird verhindert und landet in der Akte
------------------------------------------------------------------------
Config.Twinks = {
    -- Verknuepfte Logins (Multi-Account, gleicher PC) zaehlen auch, solange die Warnung nicht ausgeblendet ist
    IncludeLinkedLogins = true,
    Interactions = {
        money_transfer = 'warn',
        item_give = 'warn',       -- Inventar: Items an eigenen Charakter geben
    },
    -- Unbekannte Interaktionen aus anderen Scripts
    Default = 'warn',
}

Config.Login = {
    MaxAttempts = 5,  -- Fehlversuche bis zur Sperre
    LockSeconds = 60, -- Dauer der Sperre
}

------------------------------------------------------------------------
-- Technik
------------------------------------------------------------------------
Config.Network = {
    CallbackTimeoutMs = 10000,
    -- Anfragen pro Spieler und Sekunde, darueber wird abgelehnt und geloggt (Schutz vor Spam und Cheats)
    MaxRequestsPerSecond = 20,
}

------------------------------------------------------------------------
-- Benachrichtigungen (oben rechts unter der Geldanzeige)
------------------------------------------------------------------------
Config.Notify = {
    MaxVisible = 4,                 -- aeltere verschwinden, wenn mehr kommen
    DurationMs = { info = 5000, success = 4000, error = 6000, warning = 9000, message = 12000 }, -- message: /dm vom Team
    PerCharacterMs = 35,            -- lange Texte bleiben laenger stehen
    MaxDurationMs = 15000,
}

------------------------------------------------------------------------
-- Verwarnungen und Kicks
------------------------------------------------------------------------
Config.Warns = {
    ExpireDays = 90,    -- Verwarnungen zaehlen so lange als aktiv, 0 = fuer immer
    -- Ab so vielen aktiven Verwarnungen eines Charakters gibt es automatisch einen Charakter-Ban.
    -- Die Verwarnungen, die dazu gefuehrt haben, zaehlen danach nicht mehr fuer den naechsten Ban.
    AutoBanAt = 3,
    AutoBanDays = 7,
}

Config.Log = {
    -- Wie oft gesammelte Log-Eintraege in die Datenbank geschrieben werden
    FlushIntervalMs = 5000,
    -- Ab so vielen Eintraegen wird sofort geschrieben, ohne auf das Intervall zu warten
    MaxBatchSize = 200,
    -- So viele Eintraege werden bei Datenbankfehlern hoechstens zwischengespeichert
    MaxQueueSize = 5000,
    -- Archiv: aeltere Eintraege wandern nachts nach audit_log_archive (0 schaltet ab). Die Akte kann das Archiv durchsuchen.
    ArchiveAfterDays = 90,
    ArchiveHour = 5,          -- Stunde in Serverzeit (5 = zwischen 5 und 6 Uhr morgens)
    ArchiveBatchSize = 5000,  -- so viele Eintraege pro Portion
    ArchivePauseMs = 300,     -- Pause zwischen zwei Portionen
}
