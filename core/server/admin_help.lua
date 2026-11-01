-- Befehlsliste fuer das Admin-Menue. Pro Eintrag: Schreibweise, kurze Erklaerung und das noetige Recht.
-- Ab welchem Rang etwas geht, wird aus Config.Ranks berechnet, damit die Liste nach einer Rang-Aenderung stimmt.
-- Neuer Befehl: hier eintragen. Der Test prueft, dass jeder Admin-Befehl in dieser Liste steht.

AdminHelp = {}

local GROUPS = {
    {
        title = 'Allgemein',
        entries = {
            { usage = '/meineid', text = 'Zeigt deine permanente ID und deine Login-Nummer.' },
            { usage = '/report', text = 'Ticket an das Team schreiben. Für alle Spieler.' },
            { usage = '/rang, /raenge', text = 'Eigenen Rang und alle Ränge anzeigen.' },
            { usage = '/geld, /ueberweisen, /geben', text = 'Kontostand, Überweisung, Bargeld geben. Für alle Spieler.' },
            { usage = '/relog', text = 'Zurück zum Login.' },
            { usage = '/admin oder F10', text = 'Admin-Menü öffnen.', permission = 'admin.menu' },
            { usage = '/aduty', text = 'Admin-Dienst an oder aus. Die meisten Befehle gehen nur im Dienst.', permission = 'admin.duty', command = 'aduty' },
            { usage = 'Tab', text = 'Erkennungsmodus: Name, IDs, Gesundheit und Warnungen über jedem Spieler.', permission = 'admin.esp' },
        },
    },
    {
        title = 'Tickets',
        entries = {
            { usage = '/tickets', text = 'Alle offenen Tickets, eigene und geschlossene ansehen.', permission = 'tickets.manage' },
            { usage = '/claim 12', text = 'Ticket 12 übernehmen. Danach kannst du antworten und es schließen.', permission = 'tickets.manage', command = 'claim' },
        },
    },
    {
        title = 'Bewegen',
        entries = {
            { usage = 'Z oder /nc', text = 'Noclip. W A S D, Leertaste hoch, Strg runter, Shift sehr schnell, Alt langsam.', permission = 'admin.noclip' },
            { usage = '/tp', text = 'Zu einem zufälligen anderen Spieler.', permission = 'player.teleport', command = 'tp' },
            { usage = '/tp 17, /goto 17', text = 'Zu ID 17 teleportieren.', permission = 'player.teleport', command = 'goto' },
            { usage = '/tp x y [z]', text = 'Zu Koordinaten. Ohne Höhe auf den Boden.', permission = 'player.teleport' },
            { usage = '/bring 17', text = 'ID 17 zu dir holen. Nicht aus dem A-Jail.', permission = 'player.teleport', command = 'bring' },
            { usage = '/cartp 17, /cartp x y', text = 'Am Steuer mit Fahrzeug und Insassen teleportieren.', permission = 'player.teleport' },
            { usage = '/spec 17', text = 'ID 17 unsichtbar beobachten. Nochmal /spec beendet und bringt dich zurück.', permission = 'player.spectate', command = 'spec' },
            { usage = '/dim, /dim 5', text = 'Eigene Dimension anzeigen oder wechseln. 0 ist die normale Welt.', permission = 'admin.dimension', command = 'dim' },
            { usage = '/setdim 17 5', text = 'ID 17 in Dimension 5 setzen.', permission = 'player.dimension', command = 'setdim' },
        },
    },
    {
        title = 'Spieler',
        hint = 'Ziel: permanente ID, "r 20" für alle im Umkreis von 20 m oder "all" für alle (ab Server Administrator).',
        entries = {
            { usage = '/revive [17]', text = 'Wiederbeleben. Ohne ID dich selbst.', permission = 'player.revive', command = 'revive' },
            { usage = '/heal [ziel]', text = 'Volle Gesundheit, Hunger und Durst. Ohne Ziel dich selbst.', permission = 'player.heal', command = 'heal' },
            { usage = '/armor [ziel] [wert]', text = 'Weste geben, ohne Wert 100.', permission = 'player.heal', command = 'armor' },
            { usage = '/freeze ziel, /unfreeze ziel', text = 'Einfrieren und wieder frei lassen.', permission = 'player.freeze', command = 'freeze' },
            { usage = '/kill [ziel]', text = 'Bewusstlos machen. Admins im Dienst werden übersprungen.', permission = 'player.kill', command = 'kill' },
            { usage = '/dm ziel Text', text = 'Teamnachricht in der Bildschirmmitte.', permission = 'admin.message', command = 'dm' },
            { usage = '/gun [ziel] [waffe] [munition]', text = 'Waffe geben, ohne Angabe Pistole mit 250 Schuss.', permission = 'weapon.give', command = 'gun' },
            { usage = '/regun [ziel] [waffe]', text = 'Waffen wieder wegnehmen, die ein Admin gegeben hat.', permission = 'weapon.give', command = 'regun' },
        },
    },
    {
        title = 'Fahrzeuge',
        entries = {
            { usage = '/car adder', text = 'Fahrzeug spawnen, du sitzt am Steuer.', permission = 'vehicle.spawn' },
            { usage = '/dv', text = 'Fahrzeug löschen, in dem du sitzt oder das nächste bis 6 m.', permission = 'vehicle.spawn' },
            { usage = '/fixcars, /fixcars r 30', text = 'Fahrzeug reparieren, auf das du schaust, oder alle im Umkreis.', permission = 'vehicle.fix' },
            { usage = '/boost 300', text = 'Fahrzeug bis zu 300 % schneller. /boost 0 schaltet ab.', permission = 'vehicle.boost' },
        },
    },
    {
        title = 'Strafen',
        entries = {
            { usage = '/ajail 17 30 Grund', text = '30 Minuten A-Jail für Charakter 17.', permission = 'player.ajail', command = 'ajail' },
            { usage = '/unjail 17', text = 'Aus dem A-Jail entlassen.', permission = 'player.ajail', command = 'unjail' },
            { usage = '/kick 17 Grund', text = 'Vom Server werfen, mit Grund.', permission = 'player.kick', command = 'kick' },
            { usage = '/warn 17 [min] Grund', text = 'Verwarnen, optional mit A-Jail. Die dritte gibt 7 Tage Charakter-Ban.', permission = 'player.warn', command = 'warn' },
            { usage = '/unwarn 15', text = 'Verwarnung 15 zurücknehmen.', permission = 'player.warn', command = 'unwarn' },
            { usage = '/silentk 17 [grund]', text = 'Kick, der wie ein Verbindungsabbruch aussieht. Der Grund steht nur in der Akte.', permission = 'player.silentkick', command = 'silentk' },
            { usage = '/ban 17 3d Grund', text = 'Nur Charakter 17 bannen. Dauer 30m, 12h, 7d, 2w oder perm.', permission = 'player.ban', command = 'ban' },
            { usage = '/loginban 17 7d Grund', text = 'Den ganzen Login mit allen Charakteren bannen.', permission = 'player.ban', command = 'loginban' },
            { usage = '/unban 17, /loginunban 17', text = 'Ban aufheben.', permission = 'player.unban', command = 'unban' },
        },
    },
    {
        title = 'Geld und Team',
        entries = {
            { usage = '/givemoney cash 17 500', text = 'Geld geben, cash oder bank. Geht auch offline.', permission = 'money.manage', command = 'givemoney' },
            { usage = '/removemoney bank 17 500', text = 'Geld abziehen.', permission = 'money.manage', command = 'removemoney' },
            { usage = '/namechange 17 Lena Brandt', text = 'Vor- und Nachnamen eines Charakters ändern. Geht auch offline.', permission = 'player.rename', command = 'namechange' },
            { usage = '/setrank 17 junior', text = 'Teamrang eines Charakters setzen. Nicht für eigene Charaktere.', permission = 'ranks.manage', command = 'setrank' },
        },
    },
}

-- Befehle, die zwar registriert sind, aber in einem anderen Eintrag mit erklaert werden
local COVERED_ELSEWHERE = { unfreeze = true, loginunban = true }

-- Gruppen anderer Resources (exports.core:AddCommandHelp), nur sichtbar, solange die Resource laeuft
local external = {} -- [resource] = group

Platform.Export('AddCommandHelp', function(group)
    local resource = Platform.GetCallingResource()
    if type(group) == 'table' and type(group.title) == 'string' and type(group.entries) == 'table' then
        external[resource] = group
    end
end)

local function allGroups()
    local list = {}
    for _, group in ipairs(GROUPS) do
        list[#list + 1] = group
    end
    for resource, group in pairs(external) do
        if Platform.IsResourceStarted(resource) then
            list[#list + 1] = group
        end
    end
    return list
end

function AdminHelp.ListFor(source)
    local groups = {}
    for _, group in ipairs(allGroups()) do
        local entries = {}
        for _, entry in ipairs(group.entries) do
            local rank = entry.permission and Permissions.MinRankFor(entry.permission) or nil
            entries[#entries + 1] = {
                usage = entry.usage,
                text = entry.text,
                rank = rank and rank.label or nil,
                level = rank and rank.level or 0,
                allowed = entry.permission == nil or Core.HasPermission(source, entry.permission),
            }
        end
        groups[#groups + 1] = { title = group.title, hint = group.hint, entries = entries }
    end
    return groups
end

-- Fuer den Test: welche Admin-Befehle stehen in der Liste
function AdminHelp.CoveredCommands()
    local set = {}
    for name in pairs(COVERED_ELSEWHERE) do
        set[name] = true
    end
    for _, group in ipairs(GROUPS) do
        for _, entry in ipairs(group.entries) do
            if entry.command then
                set[entry.command] = true
            end
        end
    end
    return set
end
