-- Kicks und Verwarnungen.
-- Verwarnungen gehoeren zum Charakter (permanente ID) und werden pro Charakter gezaehlt.
-- Eine Verwarnung kann ein A-Jail mitbringen. Ab Config.Warns.AutoBanAt aktiven Verwarnungen gibt es
-- automatisch einen Charakter-Ban. Wer offline verwarnt wird, sieht es beim naechsten Spielen.

Moderation = {}

local CONSOLE = 0
local MS_PER_SECOND = 1000
local WARN_NOTIFY_MS = 20000      -- so lange bleibt eine Verwarnung beim Spieler stehen
local WARN_DELIVER_DELAY_MS = 4000 -- nach dem Spawn kurz warten, damit man sie auch sieht

local CREATE_WARNS = [[
    CREATE TABLE IF NOT EXISTS warns (
        id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        account_id    INT UNSIGNED NOT NULL,
        character_id  INT UNSIGNED NOT NULL,
        reason        VARCHAR(255) NOT NULL,
        warned_by     INT UNSIGNED NULL,           -- NULL = Konsole
        created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        seen_at       TIMESTAMP NULL DEFAULT NULL, -- wann der Spieler sie gesehen hat
        revoked_at    TIMESTAMP NULL DEFAULT NULL,
        revoked_by    INT UNSIGNED NULL,
        revoke_reason VARCHAR(255) NULL,
        INDEX idx_warns_account (account_id, revoked_at),
        INDEX idx_warns_unseen (character_id, seen_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

Moderation.Ready = false

-- Ban, der durch diese Verwarnung ausgeloest wurde (seit 0.9.6)
local WARN_BAN_COLUMN = 'ALTER TABLE warns ADD COLUMN IF NOT EXISTS ban_id INT UNSIGNED NULL DEFAULT NULL'

DB.Ready(function()
    if DB.Query(CREATE_WARNS) == nil or DB.Query(WARN_BAN_COLUMN) == nil then
        Platform.Print('error', 'Tabelle warns konnte nicht angelegt werden. Bitte 006_warns.sql und 007_character_ranks.sql ausfuehren.')
        return
    end
    Moderation.Ready = true
end)

-- Bedingung fuer aktive Verwarnungen (nicht zurueckgenommen, nicht abgelaufen)
local function activeCondition()
    if Config.Warns.ExpireDays and Config.Warns.ExpireDays > 0 then
        return ('revoked_at IS NULL AND created_at > DATE_SUB(CURRENT_TIMESTAMP, INTERVAL %d DAY)'):format(math.floor(Config.Warns.ExpireDays))
    end
    return 'revoked_at IS NULL'
end

local function notifyAdmins(message)
    for _, player in pairs(Core.Players) do
        if player.loggedIn and Core.HasPermission(player.source, 'admin.menu') then
            Platform.Notify(player.source, message, 'warning')
        end
    end
end

local function warnText(row)
    return ('Verwarnung von der Administration: %s'):format(row.reason)
end

------------------------------------------------------------------------
-- Kick
------------------------------------------------------------------------

-- target: { characterId } oder { accountId } (z. B. jemand im Login ohne Charakter)
-- Gibt true zurueck oder false und einen Fehlercode
function Moderation.Kick(actorSource, target, reason)
    reason = Punish.CleanReason(reason)
    if not reason then
        return false, 'invalid_reason'
    end

    local player
    if target.characterId then
        player = Core.GetPlayerByCharacter(target.characterId)
    elseif target.accountId then
        player = Core.GetPlayerByAccount(target.accountId)
    end
    if not player then
        return false, 'target_offline'
    end

    local allowed, err = Punish.CheckTarget(actorSource, player.accountId, player.characterId)
    if not allowed then
        return false, err
    end

    local actorAccountId = Punish.ActorAccountId(actorSource)
    local rankLabel = actorSource == CONSOLE and 'Konsole' or Core.GetRank(actorSource).label
    Core.Log({
        actor_account_id = actorAccountId,
        account_id = player.accountId,
        character_id = player.characterId,
        category = 'punishment',
        action = 'kick',
        reason = reason,
        data = { console = actorSource == CONSOLE or nil },
    })
    Platform.DropPlayer(player.source, ('Du wurdest vom Server gekickt.\nGrund: %s\nVon: %s'):format(reason, rankLabel))
    return true
end

------------------------------------------------------------------------
-- Verwarnungen
------------------------------------------------------------------------

-- Aktive Verwarnungen eines Charakters, die noch zu keinem Ban gefuehrt haben
function Moderation.CountActive(characterId)
    if not Moderation.Ready then return 0 end
    return tonumber(DB.Scalar(
        'SELECT COUNT(*) FROM warns WHERE character_id = ? AND ban_id IS NULL AND ' .. activeCondition(),
        { characterId }
    )) or 0
end

-- Dasselbe fuer viele Charaktere in einer Abfrage. Gibt { [characterId] = anzahl } zurueck (nur > 0).
function Moderation.CountActiveMany(characterIds)
    local result = {}
    if not Moderation.Ready or #characterIds == 0 then
        return result
    end
    local rows = DB.Query(
        ('SELECT character_id, COUNT(*) AS n FROM warns WHERE character_id IN (%s) AND ban_id IS NULL AND %s GROUP BY character_id')
            :format(string.rep('?', #characterIds, ', '), activeCondition()),
        characterIds
    ) or {}
    for _, row in ipairs(rows) do
        result[tonumber(row.character_id)] = tonumber(row.n)
    end
    return result
end

local SECONDS_PER_DAY = 86400

-- Genug Verwarnungen: automatischer Charakter-Ban, die Verwarnungen zaehlen danach nicht mehr
local function autoBan(actorSource, characterId, characterName, active, lastReason)
    local reason = ('Automatisch: %d Verwarnungen (zuletzt: %s)'):format(active, lastReason)
    if utf8.len(reason) > Config.Punish.ReasonMaxLength then
        reason = ('Automatisch: %d Verwarnungen'):format(active)
    end
    local info, result = Bans.Create(actorSource, {
        characterId = characterId,
        seconds = Config.Warns.AutoBanDays * SECONDS_PER_DAY,
        reason = reason,
    })
    if not info then
        -- z. B. schon gebannt: die Verwarnungen bleiben dann offen
        return nil, result
    end
    DB.Update(
        'UPDATE warns SET ban_id = ? WHERE character_id = ? AND ban_id IS NULL AND ' .. activeCondition(),
        { info.id, characterId }
    )
    notifyAdmins(('ID %d (%s) wurde nach %d Verwarnungen automatisch %d Tage gebannt (Ban-ID %d).'):format(
        characterId, characterName, active, Config.Warns.AutoBanDays, info.id))
    return info
end

-- Gibt die Warn-ID und ein Ergebnis { seen, jailed, jailError, banId, active } zurueck oder nil und einen Fehlercode.
-- jailMinutes (optional): zusaetzlich ins A-Jail
function Moderation.Warn(actorSource, characterId, reason, jailMinutes)
    if not Moderation.Ready then return nil, 'not_ready' end
    reason = Punish.CleanReason(reason)
    if not reason then
        return nil, 'invalid_reason'
    end
    characterId = tonumber(characterId)
    local characterName, accountId = Punish.CharacterName(characterId)
    if not accountId then
        return nil, 'character_not_found'
    end
    local allowed, err = Punish.CheckTarget(actorSource, accountId, characterId)
    if not allowed then
        return nil, err
    end

    local actorAccountId = Punish.ActorAccountId(actorSource)
    local target = Core.GetPlayerByCharacter(characterId)
    local warnId
    if target then
        warnId = DB.Insert(
            'INSERT INTO warns (account_id, character_id, reason, warned_by, seen_at) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)',
            DB.Args(accountId, characterId, reason, actorAccountId)
        )
    else
        warnId = DB.Insert(
            'INSERT INTO warns (account_id, character_id, reason, warned_by) VALUES (?, ?, ?, ?)',
            DB.Args(accountId, characterId, reason, actorAccountId)
        )
    end
    if not warnId then
        return nil, 'db_error'
    end

    local active = Moderation.CountActive(characterId)
    Core.Log({
        actor_account_id = actorAccountId,
        account_id = accountId,
        character_id = characterId,
        category = 'punishment',
        action = 'warn',
        reason = reason,
        data = {
            warnId = warnId, characterName = characterName, activeWarns = active,
            jailMinutes = tonumber(jailMinutes), console = actorSource == CONSOLE or nil,
        },
    })

    if target then
        Network.SendToClient(target.source, 'core:notify', {
            text = warnText({ reason = reason }) .. (' (%d von %d)'):format(active, Config.Warns.AutoBanAt),
            type = 'warning', duration = WARN_NOTIFY_MS,
        })
    end

    local result = { seen = target ~= nil, active = active }

    -- Verwarnung mit A-Jail
    if tonumber(jailMinutes) and tonumber(jailMinutes) > 0 then
        local jailId, jailInfo = Jail.Start(actorSource, characterId, tonumber(jailMinutes), reason)
        result.jailed = jailId ~= nil
        if not jailId then
            result.jailError = jailInfo
        end
    end

    if Config.Warns.AutoBanAt and Config.Warns.AutoBanAt > 0 and active >= Config.Warns.AutoBanAt then
        local ban = autoBan(actorSource, characterId, characterName, active, reason)
        result.banId = ban and ban.id or nil
    end
    return warnId, result
end

-- Verwarnung zuruecknehmen. expectedAccountId schuetzt im Menue vor der falschen Akte.
function Moderation.Unwarn(actorSource, warnId, reason, expectedAccountId)
    if not Moderation.Ready then return false, 'not_ready' end
    local row = DB.Single('SELECT id, account_id, character_id, reason FROM warns WHERE id = ? AND revoked_at IS NULL', { tonumber(warnId) })
    if not row or (expectedAccountId and row.account_id ~= expectedAccountId) then
        return false, 'warn_not_found'
    end
    local allowed, err = Punish.CheckTarget(actorSource, row.account_id, row.character_id)
    if not allowed then
        return false, err
    end
    local actorAccountId = Punish.ActorAccountId(actorSource)
    local changed = DB.Update(
        'UPDATE warns SET revoked_at = CURRENT_TIMESTAMP, revoked_by = ?, revoke_reason = ? WHERE id = ? AND revoked_at IS NULL',
        DB.Args(actorAccountId, reason, row.id)
    )
    if not changed or changed == 0 then
        return false, 'warn_not_found'
    end
    Core.Log({
        actor_account_id = actorAccountId,
        account_id = row.account_id,
        character_id = row.character_id,
        category = 'punishment',
        action = 'unwarn',
        reason = reason,
        data = { warnId = row.id, warnReason = row.reason },
    })
    return true
end

-- Beim Spielen eines Charakters: noch nicht gesehene Verwarnungen anzeigen
function Moderation.DeliverWarns(player)
    if not Moderation.Ready or not player or not player.characterId then
        return
    end
    local rows = DB.Query(
        'SELECT id, reason FROM warns WHERE character_id = ? AND seen_at IS NULL AND revoked_at IS NULL ORDER BY id',
        { player.characterId }
    ) or {}
    if #rows == 0 then
        return
    end
    for _, row in ipairs(rows) do
        Network.SendToClient(player.source, 'core:notify', { text = warnText(row), type = 'warning', duration = WARN_NOTIFY_MS })
    end
    DB.Update('UPDATE warns SET seen_at = CURRENT_TIMESTAMP WHERE character_id = ? AND seen_at IS NULL', { player.characterId })
end

function Moderation.DeliverWarnsLater(player)
    Platform.Async(function()
        Platform.Wait(WARN_DELIVER_DELAY_MS)
        Moderation.DeliverWarns(player)
    end)
end

-- Fuer die Akte: alle Verwarnungen eines Logins, neueste zuerst
function Moderation.ListForAccount(accountId)
    if not Moderation.Ready then return {}, 0 end
    local rows = DB.Query(([[
        SELECT id, character_id, reason, warned_by, revoked_by, revoke_reason, ban_id,
               UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(seen_at) AS seen_at,
               UNIX_TIMESTAMP(revoked_at) AS revoked_at, (%s) AS active
        FROM warns WHERE account_id = ? ORDER BY id DESC
    ]]):format(activeCondition()), { accountId }) or {}
    local list, activeByCharacter = {}, {}
    for i, row in ipairs(rows) do
        local isActive = row.active == 1 or row.active == true
        if isActive and not row.ban_id then
            local key = tostring(row.character_id)
            activeByCharacter[key] = (activeByCharacter[key] or 0) + 1
        end
        list[i] = {
            id = row.id,
            characterId = row.character_id,
            reason = row.reason,
            warnedBy = row.warned_by,
            revokedBy = row.revoked_by,
            revokeReason = row.revoke_reason,
            createdAt = tonumber(row.created_at) * MS_PER_SECOND,
            seenAt = row.seen_at and tonumber(row.seen_at) * MS_PER_SECOND or nil,
            revokedAt = row.revoked_at and tonumber(row.revoked_at) * MS_PER_SECOND or nil,
            banId = row.ban_id,
            active = isActive,
        }
    end
    return list, activeByCharacter
end

------------------------------------------------------------------------
-- Spam-Schutz der Netzwerk-Bridge ins Log
------------------------------------------------------------------------

local lastRateLog = {}
local RATE_LOG_COOLDOWN_SECONDS = 60

Network.OnRateLimited(function(source, callbackName)
    local now = os.time()
    if lastRateLog[source] and now - lastRateLog[source] < RATE_LOG_COOLDOWN_SECONDS then
        return
    end
    lastRateLog[source] = now
    local player = Core.GetPlayer(source)
    Core.Log({
        account_id = player and (player.accountId or player.knownAccountId) or nil,
        character_id = player and player.characterId or nil,
        category = 'security',
        action = 'rate_limited',
        data = { callback = callbackName, name = Platform.GetPlayerName(source), limit = Config.Network.MaxRequestsPerSecond },
    })
end)

Identity.OnDropped(function(source)
    lastRateLog[source] = nil
end)

------------------------------------------------------------------------
-- Befehle
------------------------------------------------------------------------

Punish.ERRORS.target_offline = 'Niemand mit dieser permanenten ID ist gerade im Spiel.'
Punish.ERRORS.warn_not_found = 'Diese Verwarnung gibt es nicht oder sie wurde schon zurückgenommen.'

-- /kick <permanente ID> <grund>
Core.RegisterAdminCommand('kick', 'player.kick', function(source, args)
    local characterId = tonumber(args[1])
    local reason = table.concat(args, ' ', 2)
    if not characterId or reason == '' then
        Platform.Notify(source, 'Benutzung: /kick <permanente ID> <grund>', 'info')
        return
    end
    local ok, err = Moderation.Kick(source, { characterId = characterId }, reason)
    if not ok then
        Platform.Notify(source, Punish.ErrorText(err), 'error')
        return
    end
    Platform.Notify(source, ('ID %d wurde gekickt.'):format(characterId), 'success')
end, { requireDuty = true })

-- /warn <permanente ID> <grund>              nur Verwarnung
-- /warn <permanente ID> <minuten> <grund>    Verwarnung mit A-Jail
Core.RegisterAdminCommand('warn', 'player.warn', function(source, args)
    local characterId = tonumber(args[1])
    local jailMinutes = args[2] and args[2]:match('^%d+$') and tonumber(args[2]) or nil
    local reason = table.concat(args, ' ', jailMinutes and 3 or 2)
    if not characterId or reason == '' then
        Platform.Notify(source, 'Benutzung: /warn <permanente ID> [A-Jail-Minuten] <grund>, z. B. /warn 17 30 RDM', 'info')
        return
    end
    local warnId, result = Moderation.Warn(source, characterId, reason, jailMinutes)
    if not warnId then
        Platform.Notify(source, Punish.ErrorText(result), 'error')
        return
    end
    local parts = { ('ID %d verwarnt (%d von %d, Warn-ID %d).'):format(characterId, result.active, Config.Warns.AutoBanAt, warnId) }
    if result.jailed then parts[#parts + 1] = ('Dazu %d Minuten A-Jail.'):format(jailMinutes) end
    if result.jailError then parts[#parts + 1] = 'A-Jail nicht möglich: ' .. Punish.ErrorText(result.jailError) end
    if result.banId then parts[#parts + 1] = ('Automatisch %d Tage gebannt.'):format(Config.Warns.AutoBanDays) end
    if not result.seen then parts[#parts + 1] = 'Die Person sieht es beim nächsten Spielen.' end
    Platform.Notify(source, table.concat(parts, ' '), result.jailError and 'warning' or 'success')
end, { requireDuty = true })

-- /unwarn <warn-ID> [grund]
Core.RegisterAdminCommand('unwarn', 'player.warn', function(source, args)
    local warnId = tonumber(args[1])
    if not warnId then
        Platform.Notify(source, 'Benutzung: /unwarn <warn-ID> [grund]. Die Warn-ID steht in der Akte unter Strafen.', 'info')
        return
    end
    local reason, valid = Punish.OptionalReason(table.concat(args, ' ', 2))
    if not valid then
        Platform.Notify(source, Punish.ErrorText('invalid_reason'), 'error')
        return
    end
    local ok, err = Moderation.Unwarn(source, warnId, reason)
    if not ok then
        Platform.Notify(source, Punish.ErrorText(err), 'error')
        return
    end
    Platform.Notify(source, ('Verwarnung %d zurückgenommen.'):format(warnId), 'success')
end, { requireDuty = true })
