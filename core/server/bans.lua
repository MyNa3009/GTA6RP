-- Bans: einzelner Charakter (permanente ID) oder ganzer Login, zeitlich oder permanent.
-- Login-Bans greifen schon beim Verbinden (auch fuer Zweit-Logins auf derselben Lizenz),
-- Charakter-Bans in der Charakterauswahl. Jede Aenderung landet im Log.

Bans = {}

local CONSOLE = 0
local MS_PER_SECOND = 1000
local RETURN_EVENT = 'core:char:return'

-- Aktiv = nicht aufgehoben und nicht abgelaufen
local ACTIVE = '(lifted_at IS NULL AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP))'

local SELECT_FIELDS = [[
    id, account_id, character_id, reason, banned_by, lift_reason, lifted_by,
    UNIX_TIMESTAMP(created_at) AS created_at,
    UNIX_TIMESTAMP(expires_at) AS expires_at,
    UNIX_TIMESTAMP(lifted_at) AS lifted_at,
]] .. ACTIVE .. ' AS active'

local function toInfo(row)
    if not row then
        return nil
    end
    return {
        id = row.id,
        accountId = row.account_id,
        characterId = row.character_id,
        reason = row.reason,
        bannedBy = row.banned_by,
        createdAt = tonumber(row.created_at),
        expiresAt = tonumber(row.expires_at), -- Sekunden, nil = permanent
        liftedAt = tonumber(row.lifted_at),
        liftedBy = row.lifted_by,
        liftReason = row.lift_reason,
        active = row.active == 1 or row.active == true,
    }
end

-- Fuer UIs: Zeiten in Millisekunden
function Bans.ToClient(info)
    if not info then
        return nil
    end
    return {
        id = info.id,
        characterId = info.characterId,
        reason = info.reason,
        createdAt = info.createdAt and info.createdAt * MS_PER_SECOND or nil,
        expiresAt = info.expiresAt and info.expiresAt * MS_PER_SECOND or nil,
        liftedAt = info.liftedAt and info.liftedAt * MS_PER_SECOND or nil,
        bannedBy = info.bannedBy,
        liftedBy = info.liftedBy,
        liftReason = info.liftReason,
        active = info.active,
    }
end

-- Text fuer die Verbindungs-Ablehnung und den Kick
function Bans.Message(info)
    local lines = {
        'Du bist auf diesem Server gebannt.',
        'Grund: ' .. info.reason,
        info.expiresAt and ('Bis: ' .. Punish.FormatTime(info.expiresAt)) or 'Dauer: permanent',
        ('Ban-ID: %d'):format(info.id),
    }
    if Config.Bans.AppealText and Config.Bans.AppealText ~= '' then
        lines[#lines + 1] = Config.Bans.AppealText
    end
    return table.concat(lines, '\n')
end

------------------------------------------------------------------------
-- Abfragen
------------------------------------------------------------------------

function Bans.ActiveForAccount(accountId)
    if not Punish.Ready then return nil end
    return toInfo(DB.Single(
        'SELECT ' .. SELECT_FIELDS .. ' FROM bans WHERE account_id = ? AND character_id IS NULL AND ' .. ACTIVE
            .. ' ORDER BY expires_at IS NULL DESC, expires_at DESC LIMIT 1',
        { accountId }
    ))
end

function Bans.ActiveForCharacter(characterId)
    if not Punish.Ready then return nil end
    return toInfo(DB.Single(
        'SELECT ' .. SELECT_FIELDS .. ' FROM bans WHERE character_id = ? AND ' .. ACTIVE
            .. ' ORDER BY expires_at IS NULL DESC, expires_at DESC LIMIT 1',
        { characterId }
    ))
end

-- [characterId] = info fuer alle gesperrten Charaktere eines Accounts
function Bans.ActiveCharacterBans(accountId)
    local result = {}
    if not Punish.Ready then return result end
    local rows = DB.Query(
        'SELECT ' .. SELECT_FIELDS .. ' FROM bans WHERE account_id = ? AND character_id IS NOT NULL AND ' .. ACTIVE,
        { accountId }
    ) or {}
    for _, row in ipairs(rows) do
        local info = toInfo(row)
        local current = result[info.characterId]
        -- Bei mehreren Bans zaehlt der laengste
        if not current or (current.expiresAt and (not info.expiresAt or info.expiresAt > current.expiresAt)) then
            result[info.characterId] = info
        end
    end
    return result
end

-- Account-Ban, der zu einem dieser Identifier passt (auch ueber einen anderen Account derselben Person)
-- Login-Ban ueber Hardware-Tokens (gleicher PC, anderer Login)
function Bans.ActiveForTokens(tokens)
    if not Punish.Ready or not Config.Bans.BlockHardware or type(tokens) ~= 'table' or #tokens == 0 or not Devices.Ready then
        return nil
    end
    local row = DB.Single(([[
        SELECT b.id, b.account_id, b.character_id, b.reason, b.banned_by, b.lift_reason, b.lifted_by,
               UNIX_TIMESTAMP(b.created_at) AS created_at, UNIX_TIMESTAMP(b.expires_at) AS expires_at,
               UNIX_TIMESTAMP(b.lifted_at) AS lifted_at, 1 AS active
        FROM bans b
        JOIN account_devices d ON d.account_id = b.account_id
        WHERE b.character_id IS NULL
          AND b.lifted_at IS NULL AND (b.expires_at IS NULL OR b.expires_at > CURRENT_TIMESTAMP)
          AND d.token IN (%s)
        ORDER BY b.expires_at IS NULL DESC, b.expires_at DESC
        LIMIT 1
    ]]):format(string.rep('?', #tokens, ', ')), tokens)
    return toInfo(row)
end

function Bans.ActiveForIdentifiers(identifiers)
    if not Punish.Ready then return nil end
    local clauses, params = {}, {}
    for _, idType in ipairs(Config.Bans.BlockIdentifiers) do
        local value = identifiers[idType]
        if value then
            clauses[#clauses + 1] = '(i.type = ? AND i.value = ?)'
            params[#params + 1] = idType
            params[#params + 1] = value
        end
    end
    if #clauses == 0 then
        return nil
    end

    local row = DB.Single(([[
        SELECT b.id, b.account_id, b.character_id, b.reason, b.banned_by, b.lift_reason, b.lifted_by,
               UNIX_TIMESTAMP(b.created_at) AS created_at, UNIX_TIMESTAMP(b.expires_at) AS expires_at,
               UNIX_TIMESTAMP(b.lifted_at) AS lifted_at, 1 AS active
        FROM bans b
        JOIN account_identifiers i ON i.account_id = b.account_id
        WHERE b.character_id IS NULL
          AND b.lifted_at IS NULL AND (b.expires_at IS NULL OR b.expires_at > CURRENT_TIMESTAMP)
          AND (%s)
        ORDER BY b.expires_at IS NULL DESC, b.expires_at DESC
        LIMIT 1
    ]]):format(table.concat(clauses, ' OR ')), params)
    return toInfo(row)
end

-- Alle Bans eines Accounts (auch Charakter-Bans, aufgehobene und abgelaufene), neueste zuerst
function Bans.ListForAccount(accountId)
    if not Punish.Ready then return {} end
    local rows = DB.Query('SELECT ' .. SELECT_FIELDS .. ' FROM bans WHERE account_id = ? ORDER BY id DESC', { accountId }) or {}
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = toInfo(row)
    end
    return list
end

------------------------------------------------------------------------
-- Durchsetzen
------------------------------------------------------------------------

-- Spieler zurueck in die Charakterauswahl, z. B. nach einem Charakter-Ban
function Bans.ReturnToSelection(player, reason, notice)
    AdminDuty.Clear(player, reason)
    Characters.Unload(player, reason)
    Network.SendToClient(player.source, RETURN_EVENT, { notice = notice })
end

local function enforce(info)
    if not info.characterId then
        -- Auch wer gerade im Login-Screen steht und zu diesem Account gehoert
        local dropped = false
        for source, player in pairs(Core.Players) do
            if player.accountId == info.accountId or (not player.loggedIn and player.knownAccountId == info.accountId) then
                Platform.DropPlayer(source, Bans.Message(info))
                dropped = true
            end
        end
        return dropped
    end
    local player = Core.GetPlayerByAccount(info.accountId)
    if not player then
        return false
    end
    if player.characterId == info.characterId then
        Bans.ReturnToSelection(player, 'Charakter gebannt', 'character_banned')
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Bannen und Entbannen
------------------------------------------------------------------------

-- options: { accountId?, characterId?, seconds (0 = permanent), reason }
-- Mit characterId wird nur dieser Charakter gesperrt, sonst der ganze Login (alle Charaktere).
-- Gibt info und online (true, wenn sofort gekickt) zurueck oder nil und einen Fehlercode.
function Bans.Create(actorSource, options)
    if not Punish.Ready then return nil, 'not_ready' end

    local reason = Punish.CleanReason(options.reason)
    if not reason then
        return nil, 'invalid_reason'
    end
    local seconds = tonumber(options.seconds)
    if not seconds or seconds < 0 then
        return nil, 'invalid_duration'
    end

    local accountId = tonumber(options.accountId)
    local characterId = tonumber(options.characterId)
    local characterName
    if characterId then
        local ownerId
        characterName, ownerId = Punish.CharacterName(characterId)
        if not ownerId or (accountId and ownerId ~= accountId) then
            return nil, 'character_not_found'
        end
        accountId = ownerId
    end
    if not accountId then
        return nil, 'account_not_found'
    end

    local allowed, err = Punish.CheckTarget(actorSource, accountId, characterId)
    if not allowed then
        return nil, err
    end

    local existing
    if characterId then
        existing = Bans.ActiveForCharacter(characterId)
    else
        existing = Bans.ActiveForAccount(accountId)
    end
    if existing then
        return nil, 'already_banned'
    end

    local actorAccountId = Punish.ActorAccountId(actorSource)
    local banId
    if seconds == 0 then
        banId = DB.Insert(
            'INSERT INTO bans (account_id, character_id, reason, banned_by) VALUES (?, ?, ?, ?)',
            DB.Args(accountId, characterId, reason, actorAccountId)
        )
    else
        banId = DB.Insert(
            'INSERT INTO bans (account_id, character_id, reason, banned_by, expires_at) VALUES (?, ?, ?, ?, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND))',
            DB.Args(accountId, characterId, reason, actorAccountId, seconds)
        )
    end
    if not banId then
        return nil, 'db_error'
    end

    local info = toInfo(DB.Single('SELECT ' .. SELECT_FIELDS .. ' FROM bans WHERE id = ?', { banId }))
    if not info then
        return nil, 'db_error'
    end

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = accountId,
        character_id = characterId,
        category = 'punishment',
        action = characterId and 'character_ban' or 'ban',
        reason = reason,
        data = {
            banId = banId,
            characterName = characterName,
            duration = Punish.FormatDuration(seconds),
            ['until'] = info.expiresAt and Punish.FormatTime(info.expiresAt) or nil,
            permanent = seconds == 0,
            console = actorSource == CONSOLE or nil,
        },
    })

    local online = enforce(info)
    return info, online
end

local function lift(actorSource, info, reason)
    local actorAccountId = Punish.ActorAccountId(actorSource)
    local changed = DB.Update(
        'UPDATE bans SET lifted_at = CURRENT_TIMESTAMP, lifted_by = ?, lift_reason = ? WHERE id = ? AND ' .. ACTIVE,
        DB.Args(actorAccountId, reason, info.id)
    )
    if changed == nil then
        return false, 'db_error'
    end
    if changed == 0 then
        return false, 'not_banned'
    end

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = info.accountId,
        character_id = info.characterId,
        category = 'punishment',
        action = 'unban',
        reason = reason,
        data = {
            banId = info.id,
            banReason = info.reason,
            characterName = info.characterId and (Punish.CharacterName(info.characterId)) or nil,
            console = actorSource == CONSOLE or nil,
        },
    })
    return true
end

-- Einen bestimmten Ban aufheben. expectedAccountId schuetzt davor, im Menue den falschen Ban zu erwischen.
function Bans.Lift(actorSource, banId, reason, expectedAccountId)
    if not Punish.Ready then return false, 'not_ready' end
    local info = banId and toInfo(DB.Single('SELECT ' .. SELECT_FIELDS .. ' FROM bans WHERE id = ?', { banId }))
    if not info or not info.active or (expectedAccountId and info.accountId ~= expectedAccountId) then
        return false, 'not_banned'
    end
    return lift(actorSource, info, reason)
end

function Bans.LiftAccount(actorSource, accountId, reason)
    local info = Bans.ActiveForAccount(accountId)
    if not info then
        return false, 'not_banned'
    end
    return lift(actorSource, info, reason)
end

function Bans.LiftCharacter(actorSource, characterId, reason)
    local info = Bans.ActiveForCharacter(characterId)
    if not info then
        return false, 'not_banned'
    end
    return lift(actorSource, info, reason)
end

------------------------------------------------------------------------
-- Waechter: wer online ist und einen aktiven Account-Ban hat, fliegt
-- (egal ob im Spiel, in der Charakterauswahl oder im Login)
------------------------------------------------------------------------

Platform.SetInterval(Config.Bans.CheckIntervalMs, function()
    if not Punish.Ready then
        return
    end
    local ids, sourcesByAccount = {}, {}
    for source, player in pairs(Core.Players) do
        local accountId = player.accountId or player.knownAccountId
        if accountId then
            if not sourcesByAccount[accountId] then
                ids[#ids + 1] = accountId
                sourcesByAccount[accountId] = {}
            end
            table.insert(sourcesByAccount[accountId], source)
        end
    end
    if #ids == 0 then
        return
    end

    local rows = DB.Query(('SELECT ' .. SELECT_FIELDS .. ' FROM bans WHERE character_id IS NULL AND ' .. ACTIVE
        .. ' AND account_id IN (%s)'):format(string.rep('?', #ids, ', ')), ids) or {}
    for _, row in ipairs(rows) do
        local info = toInfo(row)
        for _, source in ipairs(sourcesByAccount[info.accountId] or {}) do
            if Core.Players[source] then
                Platform.DropPlayer(source, Bans.Message(info))
            end
        end
    end
end)

------------------------------------------------------------------------
-- Beim Verbinden pruefen
------------------------------------------------------------------------

Identity.OnConnecting(function(source, identifiers, tokens)
    local info = Bans.ActiveForIdentifiers(identifiers) or Bans.ActiveForTokens(tokens)
    if not info then
        return nil
    end
    Core.Log({
        account_id = info.accountId,
        category = 'security',
        action = 'ban_blocked',
        data = { banId = info.id, name = Platform.GetPlayerName(source) },
    })
    return Bans.Message(info)
end)

------------------------------------------------------------------------
-- Befehle
------------------------------------------------------------------------

local function notifyBan(source, info, online, characterId)
    local target = info.characterId
        and ('ID %d'):format(info.characterId)
        or ('Login %d (über ID %d, alle Charaktere)'):format(info.accountId, characterId)
    local untilText = info.expiresAt and ('bis ' .. Punish.FormatTime(info.expiresAt)) or 'permanent'
    Platform.Notify(source, ('%s gebannt, %s. Ban-ID %d.%s'):format(target, untilText, info.id, online and ' Spieler wurde gekickt.' or ''), 'success')
end

-- scope 'character': nur dieser Charakter, 'login': alle Charaktere dieser Person
local USAGE = {
    character = 'Benutzung: /ban <permanente ID> <dauer> <grund>. Dauer z. B. 30m, 12h, 7d, 2w oder perm.',
    login = 'Benutzung: /loginban <permanente ID> <dauer> <grund>. Sperrt alle Charaktere dieser Person.',
}

local function banCommand(scope)
    return function(source, args)
        local characterId = tonumber(args[1])
        local seconds = Punish.ParseDuration(args[2])
        local reason = table.concat(args, ' ', 3)
        if not characterId or not args[2] or reason == '' then
            Platform.Notify(source, USAGE[scope], 'info')
            return
        end
        if not seconds then
            Platform.Notify(source, Punish.ErrorText('invalid_duration'), 'error')
            return
        end

        local options = { seconds = seconds, reason = reason }
        if scope == 'character' then
            options.characterId = characterId
        else
            local _, accountId = Punish.CharacterName(characterId)
            if not accountId then
                Platform.Notify(source, Punish.ErrorText('character_not_found'), 'error')
                return
            end
            options.accountId = accountId
        end

        local info, result = Bans.Create(source, options)
        if not info then
            Platform.Notify(source, Punish.ErrorText(result), 'error')
            return
        end
        notifyBan(source, info, result, characterId)
    end
end

local function unbanCommand(scope)
    return function(source, args)
        local characterId = tonumber(args[1])
        if not characterId then
            Platform.Notify(source, scope == 'character'
                and 'Benutzung: /unban <permanente ID> [grund]'
                or 'Benutzung: /loginunban <permanente ID> [grund]', 'info')
            return
        end
        local reason, valid = Punish.OptionalReason(table.concat(args, ' ', 2))
        if not valid then
            Platform.Notify(source, Punish.ErrorText('invalid_reason'), 'error')
            return
        end
        local ok, err
        if scope == 'character' then
            ok, err = Bans.LiftCharacter(source, characterId, reason)
        else
            local _, accountId = Punish.CharacterName(characterId)
            if not accountId then
                Platform.Notify(source, Punish.ErrorText('character_not_found'), 'error')
                return
            end
            ok, err = Bans.LiftAccount(source, accountId, reason)
        end
        if not ok then
            Platform.Notify(source, Punish.ErrorText(err), 'error')
            return
        end
        Platform.Notify(source, scope == 'character'
            and ('ID %d entbannt.'):format(characterId)
            or ('Login von ID %d entbannt.'):format(characterId), 'success')
    end
end

Core.RegisterAdminCommand('ban', 'player.ban', banCommand('character'), { requireDuty = true })
Core.RegisterAdminCommand('loginban', 'player.ban', banCommand('login'), { requireDuty = true })
Core.RegisterAdminCommand('unban', 'player.unban', unbanCommand('character'), { requireDuty = true })
Core.RegisterAdminCommand('loginunban', 'player.unban', unbanCommand('login'), { requireDuty = true })
