-- Teamraenge und Rechte.
-- Raenge stehen in der Config, jeder Rang erbt die Rechte aller niedrigeren Raenge.
-- Der Rang gehoert zum Charakter (permanente ID), nicht zum Login. Twinks eines Admins sind normale Spieler.
-- In der Charakterauswahl hat jeder den Standardrang.
-- Scripts fragen nie nach dem Rang, sondern immer nach einem Recht: Core.HasPermission(source, 'player.ban')

Permissions = {}

local ALL = '*'
local CONSOLE = 0

local ranksById = {}
local defaultRank = nil

------------------------------------------------------------------------
-- Raenge aus der Config aufbauen
------------------------------------------------------------------------

local function build()
    local sorted = {}
    local seenLevels = {}
    for _, rank in ipairs(Config.Ranks) do
        if ranksById[rank.id] then
            Platform.Print('warn', ('Rang-ID %s ist doppelt in Config.Ranks.'):format(rank.id))
        end
        if seenLevels[rank.level] then
            Platform.Print('warn', ('Level %d ist doppelt in Config.Ranks (%s und %s).'):format(rank.level, seenLevels[rank.level], rank.id))
        end
        seenLevels[rank.level] = rank.id
        sorted[#sorted + 1] = rank
        ranksById[rank.id] = true
    end
    table.sort(sorted, function(a, b) return a.level < b.level end)

    ranksById = {}
    local inherited = {}
    for _, rank in ipairs(sorted) do
        local set = {}
        for permission in pairs(inherited) do
            set[permission] = true
        end
        for _, permission in ipairs(rank.permissions or {}) do
            set[permission] = true
        end
        inherited = set
        ranksById[rank.id] = { id = rank.id, label = rank.label, level = rank.level, permissions = set }
    end

    defaultRank = ranksById[Config.DefaultRank] or ranksById[sorted[1].id]
end

build()

function Permissions.Get(rankId)
    return ranksById[rankId]
end

-- Niedrigster Rang, der dieses Recht hat (fuer die Befehlsliste im Admin-Menue), oder nil
function Permissions.MinRankFor(permission)
    local best
    for _, rank in pairs(ranksById) do
        if rank.permissions[permission] or rank.permissions['*'] then
            if not best or rank.level < best.level then
                best = rank
            end
        end
    end
    return best
end

function Permissions.List()
    local list = {}
    for _, rank in pairs(ranksById) do
        list[#list + 1] = rank
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

-- Alle bekannten Rechte, z. B. fuer das Admin-Menue
Permissions.Known = {
    'admin.menu', 'admin.duty', 'admin.noclip', 'vehicle.spawn', 'vehicle.boost', 'player.view', 'player.revive', 'player.teleport', 'player.ajail',
    'player.kick', 'player.warn', 'player.ban', 'player.unban', 'accounts.links', 'money.manage', 'ranks.manage', 'data.private',
    'admin.message', 'player.freeze', 'player.heal', 'vehicle.fix', 'admin.dimension', 'player.dimension', 'player.silentkick',
    'weapon.give', 'admin.mass', 'admin.esp', 'player.kill', 'tickets.manage', 'player.spectate', 'items.manage',
}

-- Liste der Rechte, die ein Spieler hat
function Permissions.ListFor(source)
    local list = {}
    for _, permission in ipairs(Permissions.Known) do
        if Core.HasPermission(source, permission) then
            list[#list + 1] = permission
        end
    end
    return list
end

function Permissions.DefaultId()
    return defaultRank.id
end

-- Rang eines Charakters (beim Spawnen geladen)
function Permissions.LoadCharacterRank(characterId)
    local rankId = DB.Scalar('SELECT admin_rank FROM characters WHERE id = ?', { characterId })
    if rankId and not ranksById[rankId] then
        Platform.Print('warn', ('Charakter %d hat den unbekannten Rang "%s", behandle ihn als %s.'):format(characterId, rankId, defaultRank.id))
        return defaultRank.id
    end
    return rankId or defaultRank.id
end

-- Hoechster Rang aller Charaktere eines Logins (fuer Strafen gegen den ganzen Login)
function Permissions.HighestOfAccount(accountId)
    local best = defaultRank
    for _, row in ipairs(DB.Query('SELECT admin_rank FROM characters WHERE account_id = ?', { accountId }) or {}) do
        local rank = ranksById[row.admin_rank]
        if rank and rank.level > best.level then
            best = rank
        end
    end
    return best
end

function Permissions.OfCharacter(characterId)
    local rankId = DB.Scalar('SELECT admin_rank FROM characters WHERE id = ?', { characterId })
    return ranksById[rankId] or defaultRank
end

-- Umstellung von Rang pro Login auf Rang pro Charakter (bis 0.9.5):
-- Der alte Rang des Logins geht an seinen zuletzt gespielten Charakter, die Twinks bleiben Spieler.
local CHARACTER_RANK_COLUMN = [[
    ALTER TABLE characters ADD COLUMN IF NOT EXISTS admin_rank VARCHAR(32) NOT NULL DEFAULT 'player' AFTER account_id
]]

DB.Ready(function()
    if DB.Query(CHARACTER_RANK_COLUMN) == nil then
        Platform.Print('error', 'Spalte characters.admin_rank fehlt. Bitte 007_character_ranks.sql ausfuehren.')
        return
    end
    local rows = DB.Query([[
        SELECT a.id AS account_id, a.admin_rank,
               (SELECT c.id FROM characters c WHERE c.account_id = a.id AND c.deleted_at IS NULL
                 ORDER BY c.last_played IS NULL, c.last_played DESC, c.id LIMIT 1) AS character_id
        FROM accounts a WHERE a.admin_rank <> ?
    ]], { defaultRank.id }) or {}
    for _, row in ipairs(rows) do
        -- Ohne Charakter bleibt der Rang am Login, bis es einen gibt (naechster Start)
        if row.character_id then
            DB.Update('UPDATE characters SET admin_rank = ? WHERE id = ?', { row.admin_rank, row.character_id })
            DB.Update('UPDATE accounts SET admin_rank = ? WHERE id = ?', { defaultRank.id, row.account_id })
            Platform.Print('ok', ('Rang %s von Login %d an Charakter %d uebertragen.'):format(row.admin_rank, row.account_id, row.character_id))
        end
    end
end)

------------------------------------------------------------------------
-- Oeffentliche API
------------------------------------------------------------------------

-- Rang des Spielers als { id, label, level }. Nicht eingeloggt: Standardrang.
function Core.GetRank(source)
    local player = Core.GetPlayer(source)
    local rank = player and player.loggedIn and ranksById[player.rank] or defaultRank
    return { id = rank.id, label = rank.label, level = rank.level }
end

-- Die Server-Konsole darf alles
function Core.HasPermission(source, permission)
    if source == CONSOLE then
        return true
    end
    local player = Core.GetPlayer(source)
    if not player or not player.loggedIn then
        return false
    end
    local rank = ranksById[player.rank] or defaultRank
    return rank.permissions[ALL] == true or rank.permissions[permission] == true
end

Platform.Export('GetRank', Core.GetRank)
Platform.Export('HasPermission', Core.HasPermission)

-- Befehl, der ein Recht braucht. Erlaubte und verweigerte Versuche landen im Log.
-- options.requireDuty: nur im Admin-Dienst (wenn Config.Admin.RequireDutyForActions an ist)
-- Alle Admin-Befehle (fuer den Test der Befehlsliste im Admin-Menue)
Core.AdminCommandNames = {}

-- Darf source diesen Admin-Befehl ausfuehren? Meldet und loggt selbst. Gibt true und die Login-ID zurueck.
-- Auch fuer andere Resources (Export AuthorizeCommand), damit ihre Befehle genauso geprueft und geloggt werden.
function Core.AuthorizeCommand(source, name, permission, args, requireDuty)
    local player = source ~= CONSOLE and Core.GetPlayer(source) or nil
    local actorAccountId = player and player.accountId or nil

    if not Core.HasPermission(source, permission) then
        Core.Log({
            actor_account_id = actorAccountId,
            category = 'security',
            action = 'command_denied',
            data = { command = name, permission = permission, args = args },
        })
        Platform.Notify(source, 'Dafür hast du keine Rechte.', 'error')
        return false
    end

    if requireDuty and source ~= CONSOLE and Config.Admin.RequireDutyForActions and not Core.IsOnDuty(source) then
        Platform.Notify(source, 'Das geht nur im Admin-Dienst. Starte ihn mit /aduty.', 'error')
        return false
    end

    Core.Log({
        actor_account_id = actorAccountId,
        category = 'admin',
        action = 'command',
        data = { command = name, args = args, console = source == CONSOLE },
    })
    return true, actorAccountId
end

function Core.RegisterAdminCommand(name, permission, handler, options)
    Core.AdminCommandNames[name] = permission
    local requireDuty = options and options.requireDuty == true
    Platform.RegisterCommand(name, function(source, args)
        local allowed, actorAccountId = Core.AuthorizeCommand(source, name, permission, args, requireDuty)
        if allowed then
            handler(source, args, actorAccountId)
        end
    end)
end

------------------------------------------------------------------------
-- Raenge vergeben
------------------------------------------------------------------------

-- Rang eines Charakters setzen. actorSource 0 = Konsole. Gibt den neuen Rang zurueck oder nil und einen Fehlercode.
function Permissions.SetRank(actorSource, targetCharacterId, rankId)
    local rank = ranksById[rankId]
    if not rank then
        return nil, 'unknown_rank'
    end

    local target = DB.Single('SELECT account_id, admin_rank FROM characters WHERE id = ?', { targetCharacterId })
    if not target then
        return nil, 'account_not_found'
    end
    local targetAccountId = target.account_id
    local current = ranksById[target.admin_rank] or defaultRank

    local actorAccountId = nil
    if actorSource ~= CONSOLE then
        local actor = Core.GetPlayer(actorSource)
        local actorRank = Core.GetRank(actorSource)
        actorAccountId = actor and actor.accountId or nil

        if not Core.HasPermission(actorSource, 'ranks.manage') then
            return nil, 'no_permission'
        end
        -- Auch keinen eigenen Twink befoerdern
        if actorAccountId == targetAccountId then
            return nil, 'own_rank'
        end
        if current.level >= actorRank.level then
            return nil, 'target_too_high'
        end
        if rank.level >= actorRank.level then
            return nil, 'rank_too_high'
        end
    end

    if current.id == rank.id then
        return nil, 'unchanged'
    end

    local changed = DB.Update('UPDATE characters SET admin_rank = ? WHERE id = ?', { rank.id, targetCharacterId })
    if not changed or changed == 0 then
        return nil, 'db_error'
    end

    local player = Core.GetPlayerByCharacter(targetCharacterId)
    if player then
        player.rank = rank.id
        Platform.Notify(player.source, ('Dein Teamrang ist jetzt: %s'):format(rank.label), 'info')
        -- Ohne Recht fuer den Admin-Dienst endet er sofort
        if player.adminDuty and not Core.HasPermission(player.source, 'admin.duty') then
            AdminDuty.Set(player.source, false)
        end
    end

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = targetAccountId,
        character_id = targetCharacterId,
        category = 'admin',
        action = 'set_rank',
        data = { from = current.id, to = rank.id, console = actorSource == CONSOLE },
    })

    return rank
end

------------------------------------------------------------------------
-- Befehle
------------------------------------------------------------------------

local SET_RANK_ERRORS = {
    unknown_rank = 'Diesen Rang gibt es nicht. Alle Raenge: /raenge',
    account_not_found = 'Keinen Login zu dieser ID gefunden.',
    no_permission = 'Dafür hast du keine Rechte.',
    own_rank = 'Den Rang deiner eigenen Charaktere kannst du nicht ändern.',
    target_too_high = 'Diese Person hat denselben oder einen höheren Rang als du.',
    rank_too_high = 'Du kannst nur Ränge unterhalb deines eigenen vergeben.',
    unchanged = 'Die Person hat diesen Rang schon.',
    db_error = 'Datenbankfehler, siehe Serverkonsole.',
}

-- /setrank <permanente ID> <rang>     z. B. /setrank 1 chief  (auch in der txAdmin-Konsole)
-- Der Rang gilt nur fuer diesen Charakter. Twinks derselben Person bleiben Spieler.
Core.RegisterAdminCommand('setrank', 'ranks.manage', function(source, args)
    local characterId = tonumber(args[1])
    local rankId = (args[2] or ''):lower()
    if not characterId or rankId == '' then
        Platform.Notify(source, 'Benutzung: /setrank <permanente ID> <rang>. Alle Ränge: /raenge', 'info')
        return
    end
    local accountId = DB.Scalar('SELECT account_id FROM characters WHERE id = ?', { characterId })
    if not accountId then
        Platform.Notify(source, 'Keinen Charakter mit dieser permanenten ID gefunden.', 'error')
        return
    end

    local rank, err = Permissions.SetRank(source, characterId, rankId)
    if not rank then
        Platform.Notify(source, SET_RANK_ERRORS[err] or tostring(err), 'error')
        return
    end
    Platform.Notify(source, ('ID %d (Login %d) ist jetzt %s.'):format(characterId, accountId, rank.label), 'success')
end)

-- /rang
Platform.RegisterCommand('rang', function(source)
    if source == CONSOLE then
        Platform.Print('info', 'Die Konsole hat alle Rechte.')
        return
    end
    Platform.Notify(source, ('Dein Teamrang: %s'):format(Core.GetRank(source).label), 'info')
end)

-- /raenge
Platform.RegisterCommand('raenge', function(source)
    local parts = {}
    for _, rank in ipairs(Permissions.List()) do
        parts[#parts + 1] = ('%s (%s)'):format(rank.id, rank.label)
    end
    Platform.Notify(source, table.concat(parts, ', '), 'info')
end)
