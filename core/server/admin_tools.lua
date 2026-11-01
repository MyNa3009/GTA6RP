-- Admin-Werkzeuge: /freeze, /unfreeze, /kill, /heal, /armor, /fixcars, /cartp, /dim, /setdim, /dm, /silentk, /gun, /regun.
-- Ziele bei den meisten Befehlen:
--   (leer)      man selbst, wo es Sinn ergibt (/heal, /armor, /gun, /regun)
--   17          permanente ID
--   r 20        alle im Umkreis von 20 Metern (auch r20), nur in der eigenen Dimension
--   all         alle im Spiel, braucht zusaetzlich das Recht admin.mass
-- Jede Aktion wird pro betroffener Person geloggt, damit sie in deren Akte steht.

AdminTools = {}
Dimensions = {}

local CONSOLE = 0
local DEBUG = Platform.GetConvar('core_debug', 'false') == 'true'
local MASS_PERMISSION = 'admin.mass'

local FREEZE_EVENT = 'core:admin:freeze'
local HEAL_EVENT = 'core:admin:heal'
local WEAPON_EVENT = 'core:admin:weapon'
local FIX_EVENT = 'core:admin:fixvehicle'
local KILL_EVENT = 'core:admin:kill'
local MAX_ARMOR = 100

local TEXT = {
    offline = 'Niemand mit dieser permanenten ID ist gerade im Spiel.',
    self = 'Das geht nicht mit dir selbst.',
    console = 'Aus der Konsole bitte eine permanente ID angeben.',
    consoleRadius = 'Der Umkreis geht nur ingame.',
    noCharacter = 'Das geht nur mit einem Charakter.',
    noMass = 'Für "all" fehlen dir die Rechte.',
    radius = ('Gib einen Umkreis von 1 bis %d Metern an, z. B. r 20.'):format(math.floor(Config.AdminTools.MaxRadius)),
    nobody = 'Im Umkreis ist niemand.',
    nobodyOnline = 'Gerade ist niemand im Spiel.',
}

-- Warum jemand uebersprungen wurde
local SKIP_TEXT = {
    rank = 'gleicher oder höherer Rang',
    dead = 'bewusstlos, dafür /revive',
    jailed = 'im A-Jail',
    already_frozen = 'schon eingefroren',
    not_frozen = 'nicht eingefroren',
    no_weapon = 'keine Admin-Waffe',
    duty = 'im Admin-Dienst',
    already_dead = 'schon bewusstlos',
}
local SKIP_SINGLE = {
    rank = 'Die Person hat den gleichen oder einen höheren Rang als du.',
    dead = 'Die Person ist bewusstlos. Nutze /revive.',
    jailed = 'Die Person sitzt im A-Jail.',
    already_frozen = 'Die Person ist schon eingefroren.',
    not_frozen = 'Die Person ist nicht eingefroren.',
    no_weapon = 'Die Person hat keine Waffe von einem Admin.',
    duty = 'Die Person ist im Admin-Dienst.',
    already_dead = 'Die Person ist schon bewusstlos.',
}

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function slice(list, from)
    local result = {}
    for i = from, #list do
        result[#result + 1] = list[i]
    end
    return result
end

local function characterName(player)
    local character = player and player.character
    if not character then
        return nil
    end
    return ('%s %s'):format(character.firstname, character.lastname)
end

local function actorAccountId(source)
    return Punish.ActorAccountId(source)
end

-- Darf der Admin etwas Negatives (einfrieren, Dimension, stiller Kick) mit dieser Person machen?
-- Nur bei niedrigerem Rang, nie bei eigenen Charakteren (ausser im Debug-Modus). Ohne Datenbank-Abfrage.
local function outranks(source, target)
    if source == CONSOLE then
        return true
    end
    local actor = Core.GetPlayer(source)
    if actor and actor.accountId == target.accountId then
        return DEBUG
    end
    local rank = Permissions.Get(target.rank)
    return not rank or rank.level < Core.GetRank(source).level
end

local function distanceSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function parseRadius(args)
    local first = args[1] and args[1]:lower() or ''
    if first == 'r' or first == 'radius' then
        return tonumber(args[2]), 2
    end
    local inline = first:match('^r(%d+%.?%d*)$')
    if inline then
        return tonumber(inline), 1
    end
    return nil, 0
end

-- Ziel aus den Argumenten lesen.
-- opts.selfDefault: ohne Ziel ist man selbst gemeint. opts.includeSelf: im Umkreis und bei "all" auch man selbst.
-- Gibt { mode, players, radius? } und die restlichen Argumente zurueck, oder nil und einen Text.
function AdminTools.ParseTarget(source, args, opts)
    opts = opts or {}
    local first = args[1] and args[1]:lower() or nil

    if first == 'all' or first == 'alle' then
        if not Core.HasPermission(source, MASS_PERMISSION) then
            return nil, TEXT.noMass
        end
        local list = {}
        for _, player in pairs(Core.Players) do
            if player.character and (player.source ~= source or opts.includeSelf) then
                list[#list + 1] = player
            end
        end
        if #list == 0 then
            return nil, TEXT.nobodyOnline
        end
        return { mode = 'all', players = list }, slice(args, 2)
    end

    local radius, used = parseRadius(args)
    if used > 0 then
        if source == CONSOLE then
            return nil, TEXT.consoleRadius
        end
        if not radius or radius <= 0 or radius > Config.AdminTools.MaxRadius then
            return nil, TEXT.radius
        end
        local admin = Core.GetPlayer(source)
        local center = Platform.GetPlayerPosition(source)
        if not admin or not admin.character or not center then
            return nil, TEXT.noCharacter
        end
        local dimension = Dimensions.Get(admin)
        local radiusSq = radius * radius
        local list = {}
        for _, player in pairs(Core.Players) do
            if player.character and (player.source ~= source or opts.includeSelf) and Dimensions.Get(player) == dimension then
                local position = Platform.GetPlayerPosition(player.source)
                if position and distanceSq(position, center) <= radiusSq then
                    list[#list + 1] = player
                end
            end
        end
        if #list == 0 then
            return nil, TEXT.nobody
        end
        return { mode = 'radius', radius = radius, players = list }, slice(args, used + 1)
    end

    if first and first:match('^%d+$') then
        local player = Core.GetPlayerByCharacter(first)
        if not player or not player.character then
            return nil, TEXT.offline
        end
        if player.source == source and not opts.selfDefault then
            return nil, TEXT.self
        end
        return { mode = player.source == source and 'self' or 'id', players = { player } }, slice(args, 2)
    end

    if opts.selfDefault then
        if source == CONSOLE then
            return nil, TEXT.console
        end
        local me = Core.GetPlayer(source)
        if not me or not me.character then
            return nil, TEXT.noCharacter
        end
        return { mode = 'self', players = { me } }, args
    end
    return nil, nil
end

-- Fuer jede Person fn(player) aufrufen. fn gibt nil (erledigt) oder einen Grund zum Ueberspringen zurueck.
-- Danach eine Meldung an den Admin: einzeln mit genauem Grund, sonst mit Anzahl.
local function forEach(source, target, fn, texts)
    local done, skipped = 0, {}
    local lastSkip
    for _, player in ipairs(target.players) do
        local skip = fn(player)
        if skip then
            skipped[skip] = (skipped[skip] or 0) + 1
            lastSkip = skip
        else
            done = done + 1
        end
    end

    if target.mode == 'self' or target.mode == 'id' then
        if done == 0 then
            Platform.Notify(source, SKIP_SINGLE[lastSkip] or tostring(lastSkip), 'error')
        elseif target.mode == 'self' then
            Platform.Notify(source, texts.self, 'success')
        else
            Platform.Notify(source, texts.one:format(target.players[1].characterId), 'success')
        end
        return done
    end

    local parts = {}
    for reason, count in pairs(skipped) do
        parts[#parts + 1] = ('%d %s'):format(count, SKIP_TEXT[reason] or reason)
    end
    table.sort(parts)
    local where = target.mode == 'radius' and ('Im Umkreis von %d m: '):format(math.floor(target.radius)) or ''
    local text = where .. texts.many:format(done, done == 1 and 'Person' or 'Personen') .. '.'
    if #parts > 0 then
        text = text .. ' Übersprungen: ' .. table.concat(parts, ', ') .. '.'
    end
    Platform.Notify(source, text, done > 0 and 'success' or 'error')
    return done
end

local function log(source, player, action, data, category, reason)
    Core.Log({
        actor_account_id = actorAccountId(source),
        account_id = player.accountId,
        character_id = player.characterId,
        category = category or 'admin',
        action = action,
        reason = reason,
        data = data,
    })
end

local function targetData(target, extra)
    local data = extra or {}
    data.mode = target.mode
    data.radius = target.radius
    return data
end

-- Fehlertext als Fehler, sonst die Benutzung als Hinweis
local function fail(source, err, usageText)
    if err then
        Platform.Notify(source, err, 'error')
    else
        Platform.Notify(source, usageText, 'info')
    end
end

local function usage(source, text)
    Platform.Notify(source, text, 'info')
end

------------------------------------------------------------------------
-- Dimensionen (0 ist die normale Welt)
------------------------------------------------------------------------

function Dimensions.Get(player)
    return player and player.dimension or 0
end

-- Setzt die Dimension und loggt. Gibt true zurueck, wenn sich etwas geaendert hat.
function Dimensions.Set(player, dimension, actorSource, reason)
    local old = Dimensions.Get(player)
    if old == dimension then
        return false
    end
    player.dimension = dimension ~= 0 and dimension or nil
    Platform.SetPlayerDimension(player.source, dimension)
    Core.Log({
        actor_account_id = actorSource and actorAccountId(actorSource) or player.accountId,
        account_id = player.accountId,
        character_id = player.characterId,
        category = 'admin',
        action = 'dimension',
        reason = reason,
        data = { from = old, to = dimension },
    })
    return true
end

local function dimensionText(dimension)
    return dimension == 0 and 'in der normalen Welt (Dimension 0)' or ('in Dimension %d'):format(dimension)
end

local function parseDimension(value)
    local dimension = tonumber(value)
    if not dimension or dimension ~= math.floor(dimension) or dimension < 0 or dimension > Config.AdminTools.MaxDimension then
        return nil
    end
    return dimension
end

local DIM_RANGE = ('Gib eine Dimension von 0 bis %d an. 0 ist die normale Welt.'):format(Config.AdminTools.MaxDimension)

-- /dim          eigene Dimension anzeigen
-- /dim <zahl>   selbst in diese Dimension wechseln
Core.RegisterAdminCommand('dim', 'admin.dimension', function(source, args)
    local admin = source ~= CONSOLE and Core.GetPlayer(source) or nil
    if not admin or not admin.character then
        Platform.Notify(source, TEXT.noCharacter, 'error')
        return
    end
    if not args[1] then
        Platform.Notify(source, ('Du bist %s.'):format(dimensionText(Dimensions.Get(admin))), 'info')
        return
    end
    local dimension = parseDimension(args[1])
    if not dimension then
        Platform.Notify(source, DIM_RANGE, 'error')
        return
    end
    if not Dimensions.Set(admin, dimension, source, 'Befehl /dim') then
        Platform.Notify(source, ('Du bist schon %s.'):format(dimensionText(dimension)), 'info')
        return
    end
    Platform.Notify(source, ('Du bist jetzt %s.'):format(dimensionText(dimension)), 'success')
end, { requireDuty = true })

-- /setdim <permanente ID> <zahl>
Core.RegisterAdminCommand('setdim', 'player.dimension', function(source, args)
    local dimension = parseDimension(args[2])
    if not args[1] or not args[1]:match('^%d+$') or not args[2] then
        usage(source, 'Benutzung: /setdim <permanente ID> <dimension>, z. B. /setdim 17 5. 0 ist die normale Welt.')
        return
    end
    if not dimension then
        Platform.Notify(source, DIM_RANGE, 'error')
        return
    end
    local player = Core.GetPlayerByCharacter(args[1])
    if not player or not player.character then
        Platform.Notify(source, TEXT.offline, 'error')
        return
    end
    if player.source ~= source and not outranks(source, player) then
        Platform.Notify(source, SKIP_SINGLE.rank, 'error')
        return
    end
    if player.jail and dimension ~= 0 then
        Platform.Notify(source, SKIP_SINGLE.jailed, 'error')
        return
    end
    if not Dimensions.Set(player, dimension, source, 'Befehl /setdim') then
        Platform.Notify(source, ('ID %d ist schon %s.'):format(player.characterId, dimensionText(dimension)), 'info')
        return
    end
    if player.source ~= source then
        Platform.Notify(player.source, ('Ein Teammitglied hat dich verschoben. Du bist jetzt %s.'):format(dimensionText(dimension)), 'info')
    end
    Platform.Notify(source, ('ID %d ist jetzt %s.'):format(player.characterId, dimensionText(dimension)), 'success')
end, { requireDuty = true })

------------------------------------------------------------------------
-- Einfrieren
------------------------------------------------------------------------

local function setFrozen(source, player, on, target)
    if on then
        player.frozen = { since = os.time(), by = actorAccountId(source) }
        Core.StopNoclip(player, 'Eingefroren')
        Spectate.Stop(player, 'Eingefroren')
    else
        player.frozen = nil
    end
    Network.SendToClient(player.source, FREEZE_EVENT, { on = on })
    log(source, player, on and 'freeze' or 'unfreeze', targetData(target, { position = Platform.GetPlayerPosition(player.source) }))
end

-- /freeze <ID | r meter | all>
Core.RegisterAdminCommand('freeze', 'player.freeze', function(source, args)
    local target, err = AdminTools.ParseTarget(source, args)
    if not target then
        fail(source, err, 'Benutzung: /freeze <permanente ID>, /freeze r <meter> oder /freeze all')
        return
    end
    forEach(source, target, function(player)
        if not outranks(source, player) then return 'rank' end
        if player.frozen then return 'already_frozen' end
        setFrozen(source, player, true, target)
        Platform.Notify(player.source, 'Ein Teammitglied hat dich eingefroren.', 'warning')
    end, { one = 'ID %d eingefroren.', many = '%d %s eingefroren' })
end, { requireDuty = true })

-- /unfreeze <ID | r meter | all>
Core.RegisterAdminCommand('unfreeze', 'player.freeze', function(source, args)
    local target, err = AdminTools.ParseTarget(source, args)
    if not target then
        fail(source, err, 'Benutzung: /unfreeze <permanente ID>, /unfreeze r <meter> oder /unfreeze all')
        return
    end
    forEach(source, target, function(player)
        if not player.frozen then return 'not_frozen' end
        setFrozen(source, player, false, target)
        Platform.Notify(player.source, 'Du kannst dich wieder bewegen.', 'info')
    end, { one = 'ID %d aufgetaut.', many = '%d %s aufgetaut' })
end, { requireDuty = true })

------------------------------------------------------------------------
-- Toeten (danach greift das normale Todes-System)
------------------------------------------------------------------------

-- /kill [ID | r meter | all]   ohne Ziel: man selbst
Core.RegisterAdminCommand('kill', 'player.kill', function(source, args)
    local KILL_USAGE = 'Benutzung: /kill, /kill <permanente ID>, /kill r <meter> oder /kill all'
    local target, rest = AdminTools.ParseTarget(source, args, { selfDefault = true })
    if not target then
        fail(source, rest, KILL_USAGE)
        return
    end
    if #rest > 0 then
        usage(source, KILL_USAGE)
        return
    end
    forEach(source, target, function(player)
        local isSelf = player.source == source
        if not isSelf and not outranks(source, player) then return 'rank' end
        if not isSelf and player.adminDuty then return 'duty' end
        if player.character.diedAt then return 'already_dead' end
        Core.StopNoclip(player, 'Getötet')
        Network.SendToClient(player.source, KILL_EVENT, {})
        log(source, player, 'kill', targetData(target, { position = Platform.GetPlayerPosition(player.source) }))
        if not isSelf then
            Platform.Notify(player.source, 'Ein Teammitglied hat dich bewusstlos gemacht.', 'info')
        end
    end, { self = 'Du bist jetzt bewusstlos.', one = 'ID %d bewusstlos gemacht.', many = '%d %s bewusstlos gemacht' })
end, { requireDuty = true })

------------------------------------------------------------------------
-- Heilen und Weste
------------------------------------------------------------------------

-- /heal [ID | r meter | all]
Core.RegisterAdminCommand('heal', 'player.heal', function(source, args)
    local HEAL_USAGE = 'Benutzung: /heal, /heal <permanente ID>, /heal r <meter> oder /heal all'
    local target, rest = AdminTools.ParseTarget(source, args, { selfDefault = true, includeSelf = true })
    if not target then
        fail(source, rest, HEAL_USAGE)
        return
    end
    if #rest > 0 then
        usage(source, HEAL_USAGE)
        return
    end
    forEach(source, target, function(player)
        if player.character.diedAt then return 'dead' end
        Network.SendToClient(player.source, HEAL_EVENT, { health = true })
        Needs.Fill(player.source)
        log(source, player, 'heal', targetData(target))
        if player.source ~= source then
            Platform.Notify(player.source, 'Du wurdest von einem Teammitglied geheilt.', 'success')
        end
    end, { self = 'Du wurdest geheilt.', one = 'ID %d geheilt.', many = '%d %s geheilt' })
end, { requireDuty = true })

-- /armor [ID | r meter | all] [wert]
Core.RegisterAdminCommand('armor', 'player.heal', function(source, args)
    local ARMOR_USAGE = ('Benutzung: /armor [ziel] [0 bis %d], z. B. /armor 17 oder /armor r 20 50'):format(MAX_ARMOR)
    local target, rest = AdminTools.ParseTarget(source, args, { selfDefault = true, includeSelf = true })
    if not target then
        fail(source, rest, ARMOR_USAGE)
        return
    end
    local value = tonumber(rest[1])
    if #rest > 1 or (rest[1] and not value) then
        usage(source, ARMOR_USAGE)
        return
    end
    value = math.floor(math.max(0, math.min(MAX_ARMOR, value or Config.AdminTools.ArmorValue)))
    forEach(source, target, function(player)
        if player.character.diedAt then return 'dead' end
        Network.SendToClient(player.source, HEAL_EVENT, { armor = value })
        log(source, player, 'armor', targetData(target, { armor = value }))
        if player.source ~= source then
            Platform.Notify(player.source, ('Ein Teammitglied hat dir eine Weste gegeben (%d).'):format(value), 'success')
        end
    end, {
        self = ('Weste auf %d gesetzt.'):format(value),
        one = 'ID %d hat jetzt Weste ' .. value .. '.',
        many = '%d %s mit Weste ' .. value,
    })
end, { requireDuty = true })

------------------------------------------------------------------------
-- Waffen geben und wieder wegnehmen
------------------------------------------------------------------------

local function giveWeapon(source, player, weapon, ammo, target)
    player.adminWeapons = player.adminWeapons or {}
    player.adminWeapons[weapon.id] = true
    Network.SendToClient(player.source, WEAPON_EVENT, { give = weapon.id, ammo = ammo })
    log(source, player, 'give_weapon', targetData(target, { weapon = weapon.id, ammo = ammo }))
end

-- /gun [ID | r meter | all] [waffe] [munition]
Core.RegisterAdminCommand('gun', 'weapon.give', function(source, args)
    local target, rest = AdminTools.ParseTarget(source, args, { selfDefault = true, includeSelf = true })
    if not target then
        fail(source, rest, 'Benutzung: /gun [ziel] [waffe] [munition], z. B. /gun 17 carbinerifle 120')
        return
    end
    local weaponName, ammo = rest[1], tonumber(rest[2])
    if tonumber(weaponName) then
        weaponName, ammo = nil, tonumber(weaponName)
    end
    local weapon = WeaponByName(weaponName or Config.AdminTools.DefaultWeapon)
    if not weapon then
        Platform.Notify(source, ('Die Waffe "%s" gibt es nicht. Beispiele: pistol, combatpistol, carbinerifle, pumpshotgun.'):format(tostring(weaponName)), 'error')
        return
    end
    ammo = math.floor(math.max(0, math.min(Config.AdminTools.MaxAmmo, ammo or Config.AdminTools.DefaultAmmo)))

    forEach(source, target, function(player)
        if player.jail then return 'jailed' end
        giveWeapon(source, player, weapon, ammo, target)
        if player.source ~= source then
            Platform.Notify(player.source, ('Ein Teammitglied hat dir eine Waffe gegeben: %s.'):format(weapon.label), 'info')
        end
    end, {
        self = ('Du hast jetzt: %s (%d Schuss).'):format(weapon.label, ammo),
        one = 'ID %d hat jetzt: ' .. weapon.label .. '.',
        many = '%d %s mit ' .. weapon.label,
    })
end, { requireDuty = true })

-- /regun [ID | r meter | all] [waffe]   nimmt Waffen weg, die ein Admin mit /gun gegeben hat
Core.RegisterAdminCommand('regun', 'weapon.give', function(source, args)
    local REGUN_USAGE = 'Benutzung: /regun [ziel] [waffe], z. B. /regun 17 oder /regun r 30'
    local target, rest = AdminTools.ParseTarget(source, args, { selfDefault = true, includeSelf = true })
    if not target then
        fail(source, rest, REGUN_USAGE)
        return
    end
    if #rest > 1 then
        usage(source, REGUN_USAGE)
        return
    end
    local only = nil
    if rest[1] then
        only = WeaponByName(rest[1])
        if not only then
            Platform.Notify(source, ('Die Waffe "%s" gibt es nicht.'):format(rest[1]), 'error')
            return
        end
    end

    forEach(source, target, function(player)
        local given = player.adminWeapons
        if not given or (only and not given[only.id]) or next(given) == nil then
            return 'no_weapon'
        end
        local removed = {}
        for id in pairs(given) do
            if not only or id == only.id then
                removed[#removed + 1] = id
            end
        end
        for _, id in ipairs(removed) do
            given[id] = nil
        end
        if next(given) == nil then
            player.adminWeapons = nil
        end
        table.sort(removed)
        Network.SendToClient(player.source, WEAPON_EVENT, { remove = removed })
        log(source, player, 'remove_weapon', targetData(target, { weapons = removed }))
        if player.source ~= source then
            Platform.Notify(player.source, 'Ein Teammitglied hat dir die Admin-Waffen wieder abgenommen.', 'info')
        end
    end, { self = 'Admin-Waffen abgelegt.', one = 'ID %d hat die Admin-Waffen nicht mehr.', many = '%d %s ohne Admin-Waffen' })
end, { requireDuty = true })

------------------------------------------------------------------------
-- Teamnachricht und stiller Kick
------------------------------------------------------------------------

-- /dm <permanente ID | r meter | all> <nachricht>
-- Steht beim Empfaenger gross in der Bildschirmmitte. "all" braucht wie ueberall admin.mass.
Core.RegisterAdminCommand('dm', 'admin.message', function(source, args)
    local DM_USAGE = 'Benutzung: /dm <permanente ID> <nachricht>, /dm r <meter> <nachricht> oder /dm all <nachricht>'
    local target, rest = AdminTools.ParseTarget(source, args)
    if not target then
        fail(source, rest, DM_USAGE)
        return
    end
    if #rest == 0 then
        usage(source, DM_USAGE)
        return
    end
    local message = table.concat(rest, ' '):gsub('%s+', ' ')
    if utf8.len(message) == nil or utf8.len(message) > Config.AdminTools.MessageMaxLength then
        Platform.Notify(source, ('Die Nachricht darf höchstens %d Zeichen lang sein.'):format(Config.AdminTools.MessageMaxLength), 'error')
        return
    end
    local sender = source == CONSOLE and 'Teamnachricht vom Server'
        or ('Teamnachricht von %s'):format(characterName(Core.GetPlayer(source)) or Core.GetRank(source).label)
    forEach(source, target, function(player)
        Platform.Notify(player.source, message, 'message', sender)
        log(source, player, 'message', targetData(target, { text = message }))
    end, { one = 'Nachricht an ID %d gesendet.', many = 'Nachricht an %d %s gesendet' })
end, { requireDuty = true })

-- /silentk <permanente ID> [grund]
-- Der Spieler sieht nur einen Verbindungsabbruch. Der echte Grund und wer es war steht in der Akte.
Core.RegisterAdminCommand('silentk', 'player.silentkick', function(source, args)
    if not args[1] or not args[1]:match('^%d+$') then
        usage(source, 'Benutzung: /silentk <permanente ID> [grund]')
        return
    end
    local reason, valid = Punish.OptionalReason(table.concat(slice(args, 2), ' '))
    if not valid then
        Platform.Notify(source, ('Der Grund muss %d bis %d Zeichen lang sein.'):format(Config.Punish.ReasonMinLength, Config.Punish.ReasonMaxLength), 'error')
        return
    end
    local player = Core.GetPlayerByCharacter(args[1])
    if not player or not player.character then
        Platform.Notify(source, TEXT.offline, 'error')
        return
    end
    if player.source == source and not DEBUG then
        Platform.Notify(source, TEXT.self, 'error')
        return
    end
    if not outranks(source, player) then
        Platform.Notify(source, SKIP_SINGLE.rank, 'error')
        return
    end
    log(source, player, 'silent_kick', { shown = Config.AdminTools.SilentKickReason, console = source == CONSOLE or nil }, 'punishment', reason)
    local characterId = player.characterId
    Platform.DropPlayer(player.source, Config.AdminTools.SilentKickReason)
    Platform.Notify(source, ('ID %d still gekickt. Für die Person sieht es wie ein Verbindungsabbruch aus.'):format(characterId), 'success')
end, { requireDuty = true })

------------------------------------------------------------------------
-- Fahrzeuge: reparieren und mit dem Fahrzeug teleportieren (Befehle laufen im Client)
------------------------------------------------------------------------

local function denyTool(source, permission)
    if not Core.HasPermission(source, permission) then
        Core.Log({ actor_account_id = actorAccountId(source), category = 'security', action = 'admin_denied', data = { permission = permission } })
        return { ok = false, error = 'no_permission' }
    end
    local player = Core.GetPlayer(source)
    if not player or not player.character then
        return { ok = false, error = 'no_character' }
    end
    if Config.Admin.RequireDutyForActions and not player.adminDuty then
        return { ok = false, error = 'duty_required' }
    end
    return nil, player
end

-- data.netId: das Fahrzeug, auf das man schaut. data.radius: alle im Umkreis. data.localVehicle: nicht vernetzt, repariert der Client selbst.
Core.RegisterCallback('admin_fixcars', function(source, data)
    local denied, admin = denyTool(source, 'vehicle.fix')
    if denied then return denied end

    local position = Platform.GetPlayerPosition(source)
    local netIds
    local radius = tonumber(data.radius)
    if radius then
        if radius <= 0 or radius > Config.AdminTools.MaxRadius then
            return { ok = false, error = 'invalid_radius' }
        end
        if not position then
            return { ok = false, error = 'no_position' }
        end
        netIds = Platform.GetVehiclesNear(position, radius, Dimensions.Get(admin))
    elseif tonumber(data.netId) then
        netIds = { math.floor(tonumber(data.netId)) }
    elseif data.localVehicle == true then
        netIds = {}
    else
        return { ok = false, error = 'no_vehicle' }
    end

    local fixed, missing = 0, 0
    for _, netId in ipairs(netIds) do
        local owner = Platform.GetVehicleOwner(netId)
        if owner then
            Network.SendToClient(owner, FIX_EVENT, { netId = netId })
            fixed = fixed + 1
        else
            missing = missing + 1
        end
    end
    if data.localVehicle == true then
        fixed = fixed + 1
    end
    if fixed == 0 then
        return { ok = false, error = 'no_vehicle' }
    end

    Core.Log({
        actor_account_id = admin.accountId,
        account_id = admin.accountId,
        character_id = admin.characterId,
        category = 'admin',
        action = 'fix_vehicles',
        data = {
            count = fixed,
            radius = radius,
            model = type(data.model) == 'string' and data.model:sub(1, 32) or nil,
            plate = type(data.plate) == 'string' and data.plate:sub(1, 12) or nil,
            position = position,
        },
    })
    return { ok = true, data = { fixed = fixed, missing = missing } }
end)

-- data.args: Argumente von /cartp. Gibt die Zielposition zurueck, der Client setzt das Fahrzeug dorthin.
Core.RegisterCallback('admin_cartp', function(source, data)
    local denied, admin = denyTool(source, 'player.teleport')
    if denied then return denied end
    if admin.jail then
        return { ok = false, error = 'jailed' }
    end
    local args = {}
    if type(data.args) == 'table' then
        for i = 1, math.min(#data.args, 4) do
            args[i] = tostring(data.args[i])
        end
    end
    if #args == 0 then
        return { ok = false, error = 'usage' }
    end
    local destination, err = AdminTeleport.Resolve(source, args, Config.AdminTools.CarTeleportOffset)
    if not destination then
        return { ok = false, error = err and 'target' or 'usage', data = { text = err } }
    end
    destination.data.model = type(data.model) == 'string' and data.model:sub(1, 32) or nil
    destination.data.plate = type(data.plate) == 'string' and data.plate:sub(1, 12) or nil
    AdminTeleport.Apply(admin, destination, 'car_teleport')
    return { ok = true, data = { position = destination.position, label = destination.label } }
end)

------------------------------------------------------------------------
-- Admin-Erkennungsmodus (Tab): Daten zu allen Spielern, der Client zeichnet sie ueber die Koepfe
------------------------------------------------------------------------

-- data.on: true beim Einschalten (wird geloggt), false beim Ausschalten, nil beim Nachladen
Core.RegisterCallback('admin_esp', function(source, data)
    local denied, admin = denyTool(source, 'admin.esp')
    if denied then return denied end

    if data.on == true or data.on == false then
        if (admin.esp ~= nil) ~= data.on then
            admin.esp = data.on and { since = os.time() } or nil
            Core.Log({
                actor_account_id = admin.accountId,
                account_id = admin.accountId,
                character_id = admin.characterId,
                category = 'admin',
                action = data.on and 'esp_on' or 'esp_off',
            })
        end
        if not data.on then
            return { ok = true, data = { on = false } }
        end
    elseif not admin.esp then
        return { ok = false, error = 'esp_off' }
    end

    local players, accountIds, characterIds = {}, {}, {}
    for _, player in pairs(Core.Players) do
        if player.accountId then
            accountIds[#accountIds + 1] = player.accountId
        end
        if player.characterId then
            characterIds[#characterIds + 1] = player.characterId
        end
    end
    -- Zwei Abfragen fuer alle Spieler zusammen, nicht eine pro Spieler
    local warned = AdminWarnedAccounts(accountIds)
    local warns = Moderation.CountActiveMany(characterIds)

    for _, player in pairs(Core.Players) do
        local rank = player.character and Permissions.Get(player.rank) or nil
        players[#players + 1] = {
            serverId = player.source,
            characterId = player.characterId,
            accountId = player.accountId,
            name = characterName(player),
            rank = rank and rank.level > 0 and rank.label or nil,
            duty = player.adminDuty ~= nil or nil,
            jailed = player.jail ~= nil or nil,
            frozen = player.frozen ~= nil or nil,
            dead = player.character and player.character.diedAt ~= nil or nil,
            dimension = player.dimension,
            warning = player.accountId and warned[player.accountId] or nil,
            warns = player.characterId and warns[player.characterId] or nil,
        }
    end
    return { ok = true, data = { on = true, players = players, warnBanAt = Config.Warns.AutoBanAt } }
end)

-- Dienstende schaltet den Erkennungsmodus mit aus (der Client bekommt das ueber core:admin:duty)
function AdminTools.StopEsp(player)
    if player and player.esp then
        player.esp = nil
        Core.Log({
            actor_account_id = player.accountId,
            account_id = player.accountId,
            character_id = player.characterId,
            category = 'admin',
            action = 'esp_off',
        })
    end
end

------------------------------------------------------------------------
-- Beim Charakterwechsel oder Ausloggen alles zuruecksetzen
------------------------------------------------------------------------

function AdminTools.OnUnload(player)
    AdminTools.StopEsp(player)
    Spectate.Stop(player, 'Ausgeloggt', true)
    Spectate.OnTargetGone(player)
    player.ticketUi = nil
    player.viewingTicket = nil
    player.frozen = nil
    player.adminWeapons = nil
    if player.dimension then
        player.dimension = nil
        Platform.SetPlayerDimension(player.source, 0)
    end
end

------------------------------------------------------------------------
-- /namechange ID Vorname Nachname (geht auch, wenn der Charakter offline ist)
------------------------------------------------------------------------

local NAMECHANGE_USAGE = 'Benutzung: /namechange <permanente ID> <Vorname> <Nachname>, z. B. /namechange 17 Lena Brandt'

Core.RegisterAdminCommand('namechange', 'player.rename', function(source, args)
    local characterId = tonumber(args[1])
    if not characterId or #args ~= 3 then
        usage(source, NAMECHANGE_USAGE)
        return
    end
    local firstname = Characters.NormalizeName(args[2])
    local lastname = Characters.NormalizeName(args[3])
    if not firstname or not lastname then
        Platform.Notify(source, ('Ungültiger Name. Nur Buchstaben, Bindestrich und Apostroph, %d bis %d Zeichen.'):format(
            Config.Characters.NameMinLength, Config.Characters.NameMaxLength), 'error')
        return
    end
    local row = DB.Single('SELECT id, account_id, admin_rank, firstname, lastname FROM characters WHERE id = ? AND deleted_at IS NULL', { characterId })
    if not row then
        Platform.Notify(source, 'Diesen Charakter gibt es nicht.', 'error')
        return
    end
    local online = Core.GetPlayerByCharacter(characterId)
    if not outranks(source, online or { accountId = row.account_id, rank = row.admin_rank }) then
        Platform.Notify(source, SKIP_SINGLE.rank, 'error')
        return
    end
    if row.firstname == firstname and row.lastname == lastname then
        Platform.Notify(source, ('ID %d heißt schon %s %s.'):format(characterId, firstname, lastname), 'info')
        return
    end
    if Config.Characters.UniqueNames then
        local taken = DB.Scalar(
            'SELECT id FROM characters WHERE firstname = ? AND lastname = ? AND id <> ? AND deleted_at IS NULL LIMIT 1',
            { firstname, lastname, characterId }
        )
        if taken then
            Platform.Notify(source, ('Den Namen %s %s hat schon ID %d.'):format(firstname, lastname, taken), 'error')
            return
        end
    end
    if not DB.Update('UPDATE characters SET firstname = ?, lastname = ? WHERE id = ?', { firstname, lastname, characterId }) then
        Platform.Notify(source, 'Datenbankfehler, siehe Serverkonsole.', 'error')
        return
    end
    local old = ('%s %s'):format(row.firstname, row.lastname)
    local new = ('%s %s'):format(firstname, lastname)
    if online and online.character then
        online.character.firstname, online.character.lastname = firstname, lastname
        Platform.Notify(online.source, ('Ein Teammitglied hat deinen Namen geändert: Du heißt jetzt %s.'):format(new), 'info')
    end
    Core.Log({
        actor_account_id = actorAccountId(source),
        account_id = row.account_id,
        character_id = characterId,
        category = 'character',
        action = 'namechange',
        data = { old = old, new = new, online = online ~= nil },
    })
    Platform.Notify(source, ('ID %d heißt jetzt %s (vorher %s).'):format(characterId, new, old), 'success')
end, { requireDuty = true })
