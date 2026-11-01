-- Admin-Dienst und Admin-Menue.
-- Alles, was ein Admin sieht oder tut, wird geloggt. Jede Anfrage prueft das passende Recht auf dem Server.

AdminDuty = {}

local DUTY_KEY = 'adminDuty'
local DUTY_EVENT = 'core:admin:duty'
local TELEPORT_EVENT = 'core:admin:teleport'
local TELEPORT_OFFSET = 1.0 -- Meter neben dem Ziel, damit niemand ineinander steht
local SECONDS_PER_MINUTE = 60
local SEARCH_MIN_LENGTH = 1
local SEARCH_MAX_LENGTH = 50

local LOG_CATEGORIES = {
    money = true, death = true, connection = true, account = true,
    character = true, admin = true, security = true, test = true, punishment = true, twink = true, ticket = true, item = true,
}
local NOCLIP_EVENT = 'core:admin:noclip'
local INVENTORY_RESOURCE = 'core_inventory'

------------------------------------------------------------------------
-- Admin-Dienst
------------------------------------------------------------------------

function Core.IsOnDuty(source)
    local player = Core.GetPlayer(source)
    return player ~= nil and player.adminDuty ~= nil
end

local function characterName(player)
    local character = player.character
    if not character then
        return nil
    end
    return ('%s %s'):format(character.firstname, character.lastname)
end

-- Noclip beenden (Dienstende, A-Jail, Ausloggen). Der Client bekommt Bescheid.
function Core.StopNoclip(player, reason)
    if not player or not player.noclip then
        return
    end
    local seconds = os.time() - player.noclip.since
    player.noclip = nil
    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = player.characterId,
        category = 'admin',
        action = 'noclip_off',
        reason = reason,
        data = { seconds = seconds, position = Platform.GetPlayerPosition(player.source) },
    })
    Network.SendToClient(player.source, NOCLIP_EVENT, { on = false })
end

-- Gibt true/false (neuer Zustand) zurueck oder nil und einen Fehlercode
function AdminDuty.Set(source, on)
    local player = Core.GetPlayer(source)
    if not player or not player.loggedIn then
        return nil, 'not_logged_in'
    end
    if on and not player.character then
        return nil, 'no_character'
    end
    if on and not Core.HasPermission(source, 'admin.duty') then
        return nil, 'no_permission'
    end
    if on and player.jail then
        return nil, 'jailed'
    end
    if (player.adminDuty ~= nil) == on then
        return on
    end

    if on then
        local rank = Core.GetRank(source)
        player.adminDuty = { since = os.time() }
        Network.SetPlayerPublic(source, DUTY_KEY, { rank = rank.label, name = characterName(player) })
        Core.Log({
            actor_account_id = player.accountId,
            account_id = player.accountId,
            character_id = player.characterId,
            category = 'admin',
            action = 'duty_on',
            data = { rank = rank.id },
        })
    else
        Core.StopNoclip(player, 'Admin-Dienst beendet')
        AdminTools.StopEsp(player)
        Spectate.Stop(player, 'Admin-Dienst beendet')
        local minutes = math.floor((os.time() - player.adminDuty.since) / SECONDS_PER_MINUTE)
        player.adminDuty = nil
        Network.SetPlayerPublic(source, DUTY_KEY, nil)
        Core.Log({
            actor_account_id = player.accountId,
            account_id = player.accountId,
            character_id = player.characterId,
            category = 'admin',
            action = 'duty_off',
            data = { minutes = minutes },
        })
    end

    Network.SendToClient(source, DUTY_EVENT, { on = on })
    return on
end

-- Beim Ausloggen, Relog oder Disconnect
function AdminDuty.Clear(player, reason)
    if not player or not player.adminDuty then
        return
    end
    Core.StopNoclip(player, reason)
    AdminTools.StopEsp(player)
    Spectate.Stop(player, reason)
    local minutes = math.floor((os.time() - player.adminDuty.since) / SECONDS_PER_MINUTE)
    player.adminDuty = nil
    Network.SetPlayerPublic(player.source, DUTY_KEY, nil)
    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = player.characterId,
        category = 'admin',
        action = 'duty_off',
        reason = reason,
        data = { minutes = minutes },
    })
end

local DUTY_ERRORS = {
    no_character = 'Der Admin-Dienst geht nur mit einem Charakter.',
    jailed = 'Im A-Jail gibt es keinen Admin-Dienst.',
    no_permission = 'Dafür hast du keine Rechte.',
    not_logged_in = 'Du bist nicht eingeloggt.',
}

-- /aduty
Core.RegisterAdminCommand('aduty', 'admin.duty', function(source)
    if source == 0 then
        Platform.Print('warn', 'Der Admin-Dienst geht nur ingame.')
        return
    end
    local on, err = AdminDuty.Set(source, not Core.IsOnDuty(source))
    if on == nil then
        Platform.Notify(source, DUTY_ERRORS[err] or tostring(err), 'error')
        return
    end
    Platform.Notify(source, on and 'Admin-Dienst gestartet.' or 'Admin-Dienst beendet.', 'success')
end)

------------------------------------------------------------------------
-- Hilfen fuer das Menue
------------------------------------------------------------------------

local function deny(source, permission)
    if Core.HasPermission(source, permission) then
        return nil
    end
    local player = Core.GetPlayer(source)
    Core.Log({
        actor_account_id = player and player.accountId or nil,
        category = 'security',
        action = 'admin_denied',
        data = { permission = permission },
    })
    return { ok = false, error = 'no_permission' }
end

local function rankLabel(rankId)
    local rank = Permissions.Get(rankId)
    return rank and rank.label or rankId
end

local function findOnlineByAccount(accountId)
    return Core.GetPlayerByAccount(accountId)
end

local function onlineEntry(player)
    return {
        serverId = player.source,
        accountId = player.accountId,
        characterId = player.characterId,
        characterName = characterName(player),
        playerName = Platform.GetPlayerName(player.source),
        rank = player.loggedIn and rankLabel(player.rank) or nil,
        loggedIn = player.loggedIn == true,
        duty = player.adminDuty ~= nil,
        jailed = player.jail ~= nil,
        frozen = player.frozen ~= nil,
        dimension = player.dimension,
        warning = false,
    }
end

local function selfInfo(source)
    local player = Core.GetPlayer(source)
    return {
        accountId = player and player.accountId or nil,
        rank = Core.GetRank(source),
        duty = Core.IsOnDuty(source),
        dutyRequired = Config.Admin.RequireDutyForActions,
        permissions = Permissions.ListFor(source),
        limits = {
            jailMaxMinutes = Config.Jail.MaxMinutes,
            banMaxDays = Config.Bans.MaxDays,
            reasonMin = Config.Punish.ReasonMinLength,
            reasonMax = Config.Punish.ReasonMaxLength,
        },
    }
end

local function toMs(seconds)
    seconds = tonumber(seconds)
    return seconds and math.floor(seconds * 1000) or nil
end

-- Entfernt E-Mail-Adressen aus Log-Daten, wenn das Recht data.private fehlt
local function cleanData(raw, private)
    if private or type(raw) ~= 'string' then
        return raw
    end
    local data = Platform.JsonDecode(raw)
    if type(data) ~= 'table' or data.email == nil then
        return raw
    end
    data.email = nil
    return Platform.JsonEncode(data)
end

local function placeholders(count)
    return string.rep('?', count, ', ')
end

local function keysOf(set)
    local list = {}
    for id in pairs(set) do
        list[#list + 1] = id
    end
    return list
end

-- Namen fuer Account- und Charakter-IDs. Schluessel als Text, damit JSON ein Objekt daraus macht.
-- Account-Name = zuletzt gespielter, nicht geloeschter Charakter
local function resolveNames(accountSet, characterSet)
    local names = { accounts = {}, characters = {} }

    local characterIds = keysOf(characterSet)
    if #characterIds > 0 then
        local rows = DB.Query(
            ('SELECT id, firstname, lastname FROM characters WHERE id IN (%s)'):format(placeholders(#characterIds)),
            characterIds
        ) or {}
        for _, row in ipairs(rows) do
            names.characters[tostring(row.id)] = ('%s %s'):format(row.firstname, row.lastname)
        end
    end

    local accountIds = keysOf(accountSet)
    if #accountIds > 0 then
        local rows = DB.Query(([[
            SELECT account_id, firstname, lastname FROM characters
            WHERE account_id IN (%s) AND deleted_at IS NULL
            ORDER BY last_played IS NULL, last_played DESC
        ]]):format(placeholders(#accountIds)), accountIds) or {}
        for _, row in ipairs(rows) do
            local key = tostring(row.account_id)
            if not names.accounts[key] then
                names.accounts[key] = ('%s %s'):format(row.firstname, row.lastname)
            end
        end
    end

    return names
end

-- Bans und A-Jails eines Accounts fuer die Akte, mit Namen aller Beteiligten
local function punishmentData(accountId)
    local bans = Bans.ListForAccount(accountId)
    local jails = Jail.ListForAccount(accountId)

    local accountSet, characterSet = {}, {}
    for _, ban in ipairs(bans) do
        if ban.bannedBy then accountSet[ban.bannedBy] = true end
        if ban.liftedBy then accountSet[ban.liftedBy] = true end
        if ban.characterId then characterSet[ban.characterId] = true end
    end
    for _, jail in ipairs(jails) do
        if jail.jailedBy then accountSet[jail.jailedBy] = true end
        if jail.releasedBy then accountSet[jail.releasedBy] = true end
        if jail.characterId then characterSet[jail.characterId] = true end
    end
    local names = resolveNames(accountSet, characterSet)
    local function accountName(id) return id and names.accounts[tostring(id)] or nil end

    local banList, activeBan = {}, nil
    for i, ban in ipairs(bans) do
        local entry = Bans.ToClient(ban)
        entry.characterName = ban.characterId and names.characters[tostring(ban.characterId)] or nil
        entry.bannedByName = accountName(ban.bannedBy)
        entry.liftedByName = accountName(ban.liftedBy)
        banList[i] = entry
        if ban.active and not ban.characterId and not activeBan then
            activeBan = entry
        end
    end

    local activeJails = {}
    for _, jail in ipairs(jails) do
        jail.characterName = jail.characterId and names.characters[tostring(jail.characterId)] or nil
        jail.jailedByName = accountName(jail.jailedBy)
        jail.releasedByName = accountName(jail.releasedBy)
        if jail.active and jail.characterId then
            activeJails[#activeJails + 1] = jail
        end
    end

    local warns, activeWarns = Moderation.ListForAccount(accountId)
    local warnAccounts, warnCharacters = {}, {}
    for _, warn in ipairs(warns) do
        if warn.warnedBy then warnAccounts[warn.warnedBy] = true end
        if warn.revokedBy then warnAccounts[warn.revokedBy] = true end
        warnCharacters[warn.characterId] = true
    end
    local warnNames = resolveNames(warnAccounts, warnCharacters)
    for _, warn in ipairs(warns) do
        warn.characterName = warnNames.characters[tostring(warn.characterId)]
        warn.warnedByName = warn.warnedBy and warnNames.accounts[tostring(warn.warnedBy)] or nil
        warn.revokedByName = warn.revokedBy and warnNames.accounts[tostring(warn.revokedBy)] or nil
    end

    return {
        bans = banList, jails = jails, activeBan = activeBan, activeJails = activeJails,
        -- activeWarns: { [characterId als Text] = Anzahl }, zaehlt bis zum automatischen Ban
        warns = warns, activeWarns = activeWarns, warnExpireDays = Config.Warns.ExpireDays,
        warnBanAt = Config.Warns.AutoBanAt, warnBanDays = Config.Warns.AutoBanDays,
    }
end

-- Offene Warnungen (Multi-Account oder neues Geraet) fuer mehrere Logins
local function warnedAccounts(accountIds)
    local warned = MultiAccount.ActiveFor(accountIds)
    for accountId in pairs(Devices.ActiveFor(accountIds)) do
        warned[accountId] = true
    end
    return warned
end

-- Fuer den Erkennungsmodus: welche dieser Logins haben eine offene Warnung
AdminWarnedAccounts = warnedAccounts

local function warningCount()
    return MultiAccount.CountActive() + Devices.CountActive()
end

local TWINK_RECENT = 5

-- Letzte Twink-Interaktionen eines Logins fuer den blauen Kasten in der Akte
local function twinkSummary(accountId)
    local twinkIds = [[
        (SELECT id FROM audit_log WHERE account_id = ? AND category = 'twink'
         UNION SELECT id FROM audit_log WHERE target_account_id = ? AND category = 'twink')
    ]]
    local total = tonumber(DB.Scalar(('SELECT COUNT(*) FROM %s AS ids'):format(twinkIds), { accountId, accountId })) or 0
    local recent = {}
    if total > 0 then
        local rows = DB.Query(([[
            SELECT STRAIGHT_JOIN l.action, l.amount, l.data, UNIX_TIMESTAMP(l.created_at) AS created_at
            FROM %s AS ids JOIN audit_log l ON l.id = ids.id
            ORDER BY l.id DESC LIMIT ?
        ]]):format(twinkIds), { accountId, accountId, TWINK_RECENT }) or {}
        for i, row in ipairs(rows) do
            recent[i] = { action = row.action, amount = row.amount, time = toMs(row.created_at), data = row.data }
        end
    end
    return { total = total, recent = recent }
end

-- IDs aller Log-Eintraege einer Person. Drei getrennte Abfragen nutzen je einen Index,
-- ein OR ueber drei Spalten wuerde bei grossem audit_log die ganze Tabelle lesen.
-- STRAIGHT_JOIN erzwingt: erst diese IDs, dann pro ID ueber den Primaerschluessel nachschlagen.
local PERSON_LOG_IDS_TEMPLATE = [[
    (SELECT id FROM {log} WHERE account_id = ?
     UNION SELECT id FROM {log} WHERE actor_account_id = ?
     UNION SELECT id FROM {log} WHERE target_account_id = ?)
]]
local PERSON_LOG_IDS = PERSON_LOG_IDS_TEMPLATE:gsub('{log}', 'audit_log')

local function escapeLike(text)
    return (text:gsub('[\\%%_]', '\\%0'))
end

------------------------------------------------------------------------
-- Callbacks
------------------------------------------------------------------------

Core.RegisterCallback('admin_overview', function(source)
    local denied = deny(source, 'admin.menu')
    if denied then return denied end

    local players, accountIds = {}, {}
    for _, player in pairs(Core.Players) do
        players[#players + 1] = onlineEntry(player)
        if player.accountId then
            accountIds[#accountIds + 1] = player.accountId
        end
    end
    table.sort(players, function(a, b) return a.serverId < b.serverId end)

    local warned = warnedAccounts(accountIds)
    for _, entry in ipairs(players) do
        entry.warning = entry.accountId ~= nil and warned[entry.accountId] == true
    end

    return {
        ok = true,
        data = {
            self = selfInfo(source),
            players = players,
            warningCount = warningCount(),
            commands = AdminHelp.ListFor(source),
            ticketsOpen = Core.HasPermission(source, 'tickets.manage') and Tickets.OpenCount() or nil,
        },
    }
end)

Core.RegisterCallback('admin_duty', function(source)
    local denied = deny(source, 'admin.duty')
    if denied then return denied end

    local on, err = AdminDuty.Set(source, not Core.IsOnDuty(source))
    if on == nil then
        return { ok = false, error = err }
    end
    return { ok = true, data = { self = selfInfo(source) } }
end)

Core.RegisterCallback('admin_search', function(source, data)
    local denied = deny(source, 'player.view')
    if denied then return denied end

    local query = type(data.query) == 'string' and data.query:match('^%s*(.-)%s*$') or ''
    if #query < SEARCH_MIN_LENGTH or #query > SEARCH_MAX_LENGTH then
        return { ok = false, error = 'invalid_query' }
    end

    local rows
    local accountId = tonumber(query)
    if accountId then
        -- Zahl: permanente ID (Charakter) oder Login-Nummer
        rows = DB.Query([[
            SELECT a.id AS account_id, COALESCE(c.admin_rank, a.admin_rank) AS admin_rank, c.id AS character_id, c.firstname, c.lastname,
                   c.deleted_at IS NOT NULL AS deleted
            FROM accounts a
            LEFT JOIN characters c ON c.account_id = a.id
            WHERE c.id = ? OR a.id = ?
            ORDER BY c.id = ? DESC, c.last_played DESC
            LIMIT ?
        ]], { accountId, accountId, accountId, Config.Admin.SearchLimit })
    else
        rows = DB.Query([[
            SELECT a.id AS account_id, COALESCE(c.admin_rank, a.admin_rank) AS admin_rank, c.id AS character_id, c.firstname, c.lastname,
                   c.deleted_at IS NOT NULL AS deleted
            FROM characters c
            JOIN accounts a ON a.id = c.account_id
            WHERE CONCAT(c.firstname, ' ', c.lastname) LIKE ?
            ORDER BY c.last_played DESC
            LIMIT ?
        ]], { '%' .. escapeLike(query) .. '%', Config.Admin.SearchLimit })
    end
    if not rows then
        return { ok = false, error = 'db_error' }
    end

    local results = {}
    for _, row in ipairs(rows) do
        local online = row.character_id and Core.GetPlayerByCharacter(row.character_id) or nil
        results[#results + 1] = {
            accountId = row.account_id,
            characterId = row.character_id,
            characterName = row.firstname and ('%s %s'):format(row.firstname, row.lastname) or nil,
            deleted = row.deleted == 1 or row.deleted == true,
            rank = rankLabel(row.admin_rank),
            serverId = online and online.source or nil,
        }
    end
    return { ok = true, data = { results = results } }
end)

Core.RegisterCallback('admin_profile', function(source, data)
    local denied = deny(source, 'player.view')
    if denied then return denied end

    -- Akte einer Person (Login). characterId legt fest, welcher Charakter im Mittelpunkt steht.
    local accountId = tonumber(data.accountId)
    local focusCharacterId = tonumber(data.characterId)
    if focusCharacterId then
        local ownerId = DB.Scalar('SELECT account_id FROM characters WHERE id = ?', { focusCharacterId })
        if not ownerId or (accountId and ownerId ~= accountId) then
            return { ok = false, error = 'not_found' }
        end
        accountId = ownerId
    end
    local account = accountId and DB.Single([[
        SELECT id, email, admin_rank,
               UNIX_TIMESTAMP(created_at) AS created_at,
               UNIX_TIMESTAMP(last_login_at) AS last_login_at
        FROM accounts WHERE id = ?
    ]], { accountId })
    if not account then
        return { ok = false, error = 'not_found' }
    end

    local private = Core.HasPermission(source, 'data.private')

    local characters = DB.Query([[
        SELECT id, firstname, lastname, DATE_FORMAT(date_of_birth, '%Y-%m-%d') AS date_of_birth,
               gender, job, job_grade, cash, bank, admin_rank,
               UNIX_TIMESTAMP(created_at) AS created_at,
               UNIX_TIMESTAMP(last_played) AS last_played,
               UNIX_TIMESTAMP(deleted_at) AS deleted_at
        FROM characters WHERE account_id = ? ORDER BY id ASC
    ]], { accountId }) or {}

    local identifierRows = DB.Query(
        'SELECT type, value, UNIX_TIMESTAMP(last_seen) AS last_seen FROM account_identifiers WHERE account_id = ? ORDER BY type',
        { accountId }
    ) or {}

    local countRows = DB.Query(([[
        SELECT STRAIGHT_JOIN l.category, COUNT(*) AS total
        FROM %s AS ids JOIN audit_log l ON l.id = ids.id
        WHERE NOT (l.category = 'money' AND l.action IN ('transfer_in', 'transfer_out') AND l.account_id <> ?)
        GROUP BY l.category
    ]]):format(PERSON_LOG_IDS), { accountId, accountId, accountId, accountId }) or {}

    -- Ohne Vorgabe: der Charakter, der gerade spielt, sonst der zuletzt gespielte
    if not focusCharacterId then
        local onlinePlayer = findOnlineByAccount(accountId)
        focusCharacterId = onlinePlayer and onlinePlayer.characterId or nil
        if not focusCharacterId then
            local best
            for _, row in ipairs(characters) do
                if not row.deleted_at and (not best or (tonumber(row.last_played) or 0) > (tonumber(best.last_played) or 0)) then
                    best = row
                end
            end
            focusCharacterId = best and best.id or (characters[1] and characters[1].id) or nil
        end
    end

    local focusRank = Permissions.DefaultId()
    for _, row in ipairs(characters) do
        if row.id == focusCharacterId then
            focusRank = row.admin_rank
        end
    end

    local characterList = {}
    for i, row in ipairs(characters) do
        characterList[i] = {
            id = row.id,
            rank = rankLabel(row.admin_rank),
            firstname = row.firstname,
            lastname = row.lastname,
            dateOfBirth = row.date_of_birth,
            gender = row.gender,
            job = row.job,
            jobGrade = row.job_grade,
            cash = Money.CashOnSelect(row.id, row.cash), -- Bargeld liegt im Inventar, wenn core_inventory laeuft
            bank = row.bank,
            createdAt = toMs(row.created_at),
            lastPlayed = toMs(row.last_played),
            deletedAt = toMs(row.deleted_at),
        }
    end

    local identifiers = {}
    for i, row in ipairs(identifierRows) do
        identifiers[i] = { type = row.type, value = private and row.value or nil, lastSeen = toMs(row.last_seen) }
    end

    local counts = {}
    for _, row in ipairs(countRows) do
        counts[row.category] = row.total
    end

    local links = MultiAccount.ForAccount(accountId)
    local linkAccounts = {}
    for _, link in ipairs(links) do
        linkAccounts[link.otherAccountId] = true
        if link.dismissedBy then linkAccounts[link.dismissedBy] = true end
    end
    local linkNames = resolveNames(linkAccounts, {})
    for _, link in ipairs(links) do
        link.otherName = linkNames.accounts[tostring(link.otherAccountId)]
        link.dismissedByName = link.dismissedBy and linkNames.accounts[tostring(link.dismissedBy)] or nil
        link.firstSeen = toMs(link.firstSeen)
        link.lastSeen = toMs(link.lastSeen)
        link.dismissedAt = toMs(link.dismissedAt)
    end

    local online = findOnlineByAccount(accountId)
    local viewer = Core.GetPlayer(source)
    Core.Log({
        actor_account_id = viewer and viewer.accountId or nil,
        account_id = accountId,
        character_id = focusCharacterId,
        category = 'admin',
        action = 'view_profile',
    })

    return {
        ok = true,
        data = {
            account = {
                id = account.id,
                -- Rang gehoert zum Charakter: hier der Rang des angezeigten Charakters
                rank = rankLabel(focusRank),
                email = private and account.email or nil,
                createdAt = toMs(account.created_at),
                lastLogin = toMs(account.last_login_at),
            },
            online = online and onlineEntry(online) or nil,
            characters = characterList,
            identifiers = identifiers,
            counts = counts,
            links = links,
            punishments = punishmentData(accountId),
            devices = Devices.ForAccount(accountId, private),
            twinks = twinkSummary(accountId),
            focusCharacterId = focusCharacterId,
            inventory = Platform.IsResourceStarted(INVENTORY_RESOURCE),
        },
    }
end)

-- Inventar eines Charakters fuer die Akte (kommt aus core_inventory, geht auch offline)
Core.RegisterCallback('admin_inventory', function(source, data)
    local denied = deny(source, 'player.view')
    if denied then return denied end
    local characterId = tonumber(data.characterId)
    if not characterId then
        return { ok = false, error = 'character_not_found' }
    end
    if not Platform.IsResourceStarted(INVENTORY_RESOURCE) then
        return { ok = false, error = 'no_inventory' }
    end
    local accountId = DB.Scalar('SELECT account_id FROM characters WHERE id = ?', { characterId })
    if not accountId then
        return { ok = false, error = 'character_not_found' }
    end
    local state = Platform.CallExport(INVENTORY_RESOURCE, 'GetInventory', characterId)
    if type(state) ~= 'table' then
        return { ok = false, error = 'no_inventory' }
    end
    local admin = Core.GetPlayer(source)
    Core.Log({
        actor_account_id = admin and admin.accountId or nil,
        account_id = accountId,
        character_id = characterId,
        category = 'admin',
        action = 'view_inventory',
    })
    return {
        ok = true,
        data = {
            characterId = characterId,
            state = state,
            items = Platform.CallExport(INVENTORY_RESOURCE, 'GetItemDefs') or {},
            layout = Platform.CallExport(INVENTORY_RESOURCE, 'GetLayout') or {},
        },
    }
end)

-- Alle Charaktere (jeder mit eigener permanenter ID), auch offline, zuletzt gespielte zuerst.
-- Logins ohne Charakter stehen als eigene Zeile dabei.
local ACTIVE_BAN = 'b.lifted_at IS NULL AND (b.expires_at IS NULL OR b.expires_at > CURRENT_TIMESTAMP)'

Core.RegisterCallback('admin_accounts', function(source, data)
    local denied = deny(source, 'player.view')
    if denied then return denied end

    local page = math.max(0, math.floor(tonumber(data.page) or 0))
    local pageSize = Config.Admin.LogPageSize

    local rows = DB.Query(([[
        SELECT p.*,
               EXISTS(SELECT 1 FROM bans b WHERE b.account_id = p.account_id AND b.character_id IS NULL AND %s) AS banned,
               EXISTS(SELECT 1 FROM bans b WHERE b.character_id = p.character_id AND %s) AS character_banned,
               EXISTS(SELECT 1 FROM admin_jails j WHERE j.character_id = p.character_id AND j.released_at IS NULL) AS jailed
        FROM (
            SELECT a.id AS account_id, COALESCE(c.admin_rank, a.admin_rank) AS admin_rank, c.id AS character_id,
                   CONCAT(c.firstname, ' ', c.lastname) AS name,
                   UNIX_TIMESTAMP(COALESCE(c.last_played, a.last_login_at)) AS last_seen
            FROM accounts a
            LEFT JOIN characters c ON c.account_id = a.id AND c.deleted_at IS NULL
            ORDER BY last_seen IS NULL, last_seen DESC, a.id DESC, c.id DESC
            LIMIT ? OFFSET ?
        ) AS p
        ORDER BY p.last_seen IS NULL, p.last_seen DESC, p.account_id DESC, p.character_id DESC
    ]]):format(ACTIVE_BAN, ACTIVE_BAN), { pageSize + 1, page * pageSize })
    if not rows then
        return { ok = false, error = 'db_error' }
    end

    local ids = {}
    for i = 1, math.min(#rows, pageSize) do
        ids[#ids + 1] = rows[i].account_id
    end
    local warned = warnedAccounts(ids)

    local function flag(value)
        return value == 1 or value == true
    end

    local accounts = {}
    for i = 1, math.min(#rows, pageSize) do
        local row = rows[i]
        local online
        if row.character_id then
            online = Core.GetPlayerByCharacter(row.character_id)
        else
            online = findOnlineByAccount(row.account_id)
        end
        accounts[i] = {
            accountId = row.account_id,
            characterId = row.character_id,
            name = row.name,
            rank = rankLabel(row.admin_rank),
            lastSeen = toMs(row.last_seen),
            serverId = online and online.source or nil,
            warning = warned[row.account_id] == true,
            banned = flag(row.banned) or flag(row.character_banned),
            jailed = flag(row.jailed),
        }
    end
    return { ok = true, data = { accounts = accounts, page = page, hasMore = #rows > pageSize } }
end)

-- Alle offenen Multi-Account-Warnungen, auch wenn beide offline sind
Core.RegisterCallback('admin_warnings', function(source)
    local denied = deny(source, 'player.view')
    if denied then return denied end

    local rows = MultiAccount.ListActive(Config.Admin.SearchLimit * 4)
    local accountSet = {}
    for _, row in ipairs(rows) do
        accountSet[row.account_a] = true
        accountSet[row.account_b] = true
    end
    local names = resolveNames(accountSet, {})

    local function side(accountId)
        local online = findOnlineByAccount(accountId)
        return {
            accountId = accountId,
            name = names.accounts[tostring(accountId)],
            serverId = online and online.source or nil,
        }
    end

    local warnings = {}
    for i, row in ipairs(rows) do
        local types = {}
        for idType in tostring(row.types or ''):gmatch('[^,]+') do
            types[#types + 1] = idType
        end
        warnings[i] = {
            a = side(row.account_a),
            b = side(row.account_b),
            types = types,
            timesSeen = tonumber(row.times_seen) or 0,
            firstSeen = toMs(row.first_seen),
            lastSeen = toMs(row.last_seen),
        }
    end
    local private = Core.HasPermission(source, 'data.private')
    local devices = Devices.ListActive(Config.Admin.SearchLimit * 4, private)
    local deviceAccounts = {}
    for _, alert in ipairs(devices) do
        deviceAccounts[alert.accountId] = true
    end
    local deviceNames = resolveNames(deviceAccounts, {})
    for _, alert in ipairs(devices) do
        alert.name = deviceNames.accounts[tostring(alert.accountId)]
        local online = findOnlineByAccount(alert.accountId)
        alert.serverId = online and online.source or nil
    end
    return { ok = true, data = { warnings = warnings, devices = devices } }
end)

-- Multi-Account-Warnung aus- oder wieder einblenden
Core.RegisterCallback('admin_link', function(source, data)
    local denied = deny(source, 'accounts.links')
    if denied then return denied end

    local accountId, otherAccountId = tonumber(data.accountId), tonumber(data.otherAccountId)
    if not accountId or not otherAccountId then
        return { ok = false, error = 'not_found' }
    end
    local admin = Core.GetPlayer(source)
    local ok, err = MultiAccount.SetDismissed(accountId, otherAccountId, data.dismissed == true, admin and admin.accountId)
    if not ok then
        return { ok = false, error = err }
    end

    local links = MultiAccount.ForAccount(accountId)
    local linkAccounts = {}
    for _, link in ipairs(links) do
        linkAccounts[link.otherAccountId] = true
        if link.dismissedBy then linkAccounts[link.dismissedBy] = true end
    end
    local names = resolveNames(linkAccounts, {})
    for _, link in ipairs(links) do
        link.otherName = names.accounts[tostring(link.otherAccountId)]
        link.dismissedByName = link.dismissedBy and names.accounts[tostring(link.dismissedBy)] or nil
        link.firstSeen = toMs(link.firstSeen)
        link.lastSeen = toMs(link.lastSeen)
        link.dismissedAt = toMs(link.dismissedAt)
    end
    return { ok = true, data = { links = links } }
end)

Core.RegisterCallback('admin_logs', function(source, data)
    local denied = deny(source, 'player.view')
    if denied then return denied end

    local accountId = tonumber(data.accountId)
    if not accountId then
        return { ok = false, error = 'not_found' }
    end
    local category = data.category
    if category ~= nil and category ~= 'all' and not LOG_CATEGORIES[category] then
        return { ok = false, error = 'invalid_category' }
    end
    local page = math.max(0, math.floor(tonumber(data.page) or 0))
    local pageSize = Config.Admin.LogPageSize

    -- archive = true: dieselbe Abfrage im Log-Archiv (Eintraege aelter als Config.Log.ArchiveAfterDays)
    local archive = data.archive == true
    if archive and not LogArchive.Ready then
        return { ok = false, error = 'not_ready' }
    end
    local logTable = archive and LogArchive.Table or 'audit_log'
    local sql = ([[
        SELECT STRAIGHT_JOIN l.id, UNIX_TIMESTAMP(l.created_at) AS created_at, l.actor_account_id, l.account_id, l.character_id,
               l.category, l.action, l.amount, l.balance_before, l.balance_after, l.target_account_id, l.resource, l.reason, l.data
        FROM %s AS ids JOIN %s l ON l.id = ids.id
        WHERE NOT (l.category = 'money' AND l.action IN ('transfer_in', 'transfer_out') AND l.account_id <> ?)
    ]]):format((PERSON_LOG_IDS_TEMPLATE:gsub('{log}', logTable)), logTable)
    local params = { accountId, accountId, accountId, accountId }
    if category and category ~= 'all' then
        sql = sql .. ' AND l.category = ?'
        params[#params + 1] = category
    end
    sql = sql .. ' ORDER BY l.id DESC LIMIT ? OFFSET ?'
    params[#params + 1] = pageSize + 1
    params[#params + 1] = page * pageSize

    local rows = DB.Query(sql, params)
    if not rows then
        return { ok = false, error = 'db_error' }
    end

    local private = Core.HasPermission(source, 'data.private')
    local entries = {}
    for i = 1, math.min(#rows, pageSize) do
        local row = rows[i]
        entries[i] = {
            id = row.id,
            time = toMs(row.created_at),
            actorAccountId = row.actor_account_id,
            accountId = row.account_id,
            characterId = row.character_id,
            targetAccountId = row.target_account_id,
            category = row.category,
            action = row.action,
            amount = row.amount,
            balanceBefore = row.balance_before,
            balanceAfter = row.balance_after,
            resource = row.resource,
            reason = row.reason,
            data = cleanData(row.data, private),
        }
    end

    -- Namen aller beteiligten Accounts und Charaktere, damit die Akte "Name (ID 9)" statt nur "ID 9" zeigt
    local accountSet, characterSet = {}, {}
    for _, entry in ipairs(entries) do
        if entry.actorAccountId then accountSet[entry.actorAccountId] = true end
        if entry.accountId then accountSet[entry.accountId] = true end
        if entry.targetAccountId then accountSet[entry.targetAccountId] = true end
        if entry.characterId then characterSet[entry.characterId] = true end
        local extra = Platform.JsonDecode(entry.data)
        if type(extra) == 'table' then
            for _, key in ipairs({ 'killerCharacterId', 'toCharacterId', 'fromCharacterId' }) do
                local id = tonumber(extra[key])
                if id then characterSet[id] = true end
            end
            local killerAccount = tonumber(extra.killerAccountId)
            if killerAccount then accountSet[killerAccount] = true end
        end
    end

    return {
        ok = true,
        data = {
            entries = entries,
            page = page,
            hasMore = #rows > pageSize,
            archive = archive,
            archiveDays = Config.Log.ArchiveAfterDays,
            names = resolveNames(accountSet, characterSet),
        },
    }
end)

------------------------------------------------------------------------
-- Aktionen
------------------------------------------------------------------------

local ACTIONS = {
    ['revive'] = 'player.revive',
    ['goto'] = 'player.teleport', -- goto ist in Lua ein Schluesselwort, darum in Klammern
    ['bring'] = 'player.teleport',
}

local followDimension -- weiter unten bei den Teleport-Befehlen

local function offset(position)
    return { x = position.x + TELEPORT_OFFSET, y = position.y, z = position.z, heading = position.heading }
end

Core.RegisterCallback('admin_action', function(source, data)
    local permission = ACTIONS[data.action]
    if not permission then
        return { ok = false, error = 'unknown_action' }
    end
    local denied = deny(source, permission)
    if denied then return denied end

    if Config.Admin.RequireDutyForActions and not Core.IsOnDuty(source) then
        return { ok = false, error = 'duty_required' }
    end

    local target = Core.GetPlayer(tonumber(data.serverId))
    if not target or not target.character then
        return { ok = false, error = 'target_offline' }
    end
    local admin = Core.GetPlayer(source)

    if data.action == 'revive' then
        Core.Revive(target.source, admin.accountId, 'Admin-Menü')
        return { ok = true }
    end

    if target.source == source then
        return { ok = false, error = 'self' }
    end
    if data.action == 'bring' and target.jail then
        return { ok = false, error = 'target_jailed' }
    end

    local from, to
    if data.action == 'goto' then
        from, to = source, target.source
    else
        from, to = target.source, source
    end

    local position = Platform.GetPlayerPosition(to)
    if not position then
        return { ok = false, error = 'no_position' }
    end
    followDimension(Core.GetPlayer(from), Core.GetPlayer(to), source)
    Network.SendToClient(from, TELEPORT_EVENT, offset(position))

    Core.Log({
        actor_account_id = admin.accountId,
        account_id = target.accountId,
        character_id = target.characterId,
        category = 'admin',
        action = data.action == 'goto' and 'teleport_to' or 'bring',
        data = { position = position },
    })
    return { ok = true }
end)

------------------------------------------------------------------------
-- Strafen aus dem Menue: A-Jail, Entlassen, Bannen, Entbannen
------------------------------------------------------------------------

local PUNISH_PERMISSIONS = {
    jail = 'player.ajail',
    unjail = 'player.ajail',
    ban = 'player.ban',
    unban = 'player.unban',
    warn = 'player.warn',
    unwarn = 'player.warn',
    kick = 'player.kick',
}

Core.RegisterCallback('admin_punish', function(source, data)
    local permission = PUNISH_PERMISSIONS[data.type]
    if not permission then
        return { ok = false, error = 'unknown_action' }
    end
    local denied = deny(source, permission)
    if denied then return denied end

    if Config.Admin.RequireDutyForActions and not Core.IsOnDuty(source) then
        return { ok = false, error = 'duty_required' }
    end

    local accountId = tonumber(data.accountId)
    local characterId = tonumber(data.characterId)
    if not accountId then
        return { ok = false, error = 'not_found' }
    end
    -- Der Charakter muss zu dieser Akte gehoeren
    if characterId and DB.Scalar('SELECT account_id FROM characters WHERE id = ?', { characterId }) ~= accountId then
        return { ok = false, error = 'character_not_found' }
    end

    local ok, err
    if data.type == 'jail' then
        if not characterId then return { ok = false, error = 'character_not_found' } end
        ok, err = Jail.Start(source, characterId, tonumber(data.minutes), data.reason)
        if not ok then return { ok = false, error = err } end
    elseif data.type == 'unjail' then
        if not characterId then return { ok = false, error = 'character_not_found' } end
        local reason, valid = Punish.OptionalReason(data.reason)
        if not valid then return { ok = false, error = 'invalid_reason' } end
        ok, err = Jail.Release(source, characterId, reason)
        if not ok then return { ok = false, error = err } end
    elseif data.type == 'warn' then
        if not characterId then return { ok = false, error = 'character_not_found' } end
        local minutes = tonumber(data.minutes)
        ok, err = Moderation.Warn(source, characterId, data.reason, minutes and minutes > 0 and minutes or nil)
        if not ok then return { ok = false, error = err } end
    elseif data.type == 'unwarn' then
        local reason, valid = Punish.OptionalReason(data.reason)
        if not valid then return { ok = false, error = 'invalid_reason' } end
        ok, err = Moderation.Unwarn(source, tonumber(data.warnId), reason, accountId)
        if not ok then return { ok = false, error = err } end
    elseif data.type == 'kick' then
        -- Mit Charakter: nur wenn genau der gespielt wird. Ohne: wer mit diesem Login verbunden ist (z. B. im Login-Screen)
        ok, err = Moderation.Kick(source, characterId and { characterId = characterId } or { accountId = accountId }, data.reason)
        if not ok then return { ok = false, error = err } end
    elseif data.type == 'ban' then
        local seconds = Punish.ParseDuration(type(data.duration) == 'string' and data.duration or '')
        if not seconds then
            return { ok = false, error = 'invalid_duration' }
        end
        -- scope 'login': alle Charaktere dieser Person, sonst nur der Charakter
        local loginBan = data.scope == 'login'
        if not loginBan and not characterId then
            return { ok = false, error = 'character_not_found' }
        end
        ok, err = Bans.Create(source, {
            accountId = accountId,
            characterId = not loginBan and characterId or nil,
            seconds = seconds,
            reason = data.reason,
        })
        if not ok then return { ok = false, error = err } end
    else
        local reason, valid = Punish.OptionalReason(data.reason)
        if not valid then return { ok = false, error = 'invalid_reason' } end
        ok, err = Bans.Lift(source, tonumber(data.banId), reason, accountId)
        if not ok then return { ok = false, error = err } end
    end

    return { ok = true, data = { punishments = punishmentData(accountId) } }
end)

------------------------------------------------------------------------
-- Noclip (/nc). Der Client fliegt, der Server erlaubt und loggt.
------------------------------------------------------------------------

Core.RegisterCallback('admin_noclip', function(source, data)
    local denied = deny(source, 'admin.noclip')
    if denied then return denied end

    local player = Core.GetPlayer(source)
    if data.on ~= true then
        Core.StopNoclip(player, nil)
        return { ok = true, data = { on = false } }
    end

    if not player.character then
        return { ok = false, error = 'no_character' }
    end
    if Config.Admin.RequireDutyForActions and not player.adminDuty then
        return { ok = false, error = 'duty_required' }
    end
    if player.jail then
        return { ok = false, error = 'jailed' }
    end
    if player.frozen then
        return { ok = false, error = 'frozen' }
    end

    if not player.noclip then
        player.noclip = { since = os.time() }
        Core.Log({
            actor_account_id = player.accountId,
            account_id = player.accountId,
            character_id = player.characterId,
            category = 'admin',
            action = 'noclip_on',
            data = { position = Platform.GetPlayerPosition(source) },
        })
    end
    return { ok = true, data = { on = true } }
end)

-- Geraete-Warnung (neuer PC) aus- oder wieder einblenden
Core.RegisterCallback('admin_device_alert', function(source, data)
    local denied = deny(source, 'accounts.links')
    if denied then return denied end

    local accountId, alertId = tonumber(data.accountId), tonumber(data.alertId)
    if not accountId or not alertId then
        return { ok = false, error = 'not_found' }
    end
    local admin = Core.GetPlayer(source)
    local ok, err = Devices.SetDismissed(accountId, alertId, data.dismissed == true, admin and admin.accountId)
    if not ok then
        return { ok = false, error = err }
    end
    return { ok = true, data = { devices = Devices.ForAccount(accountId, Core.HasPermission(source, 'data.private')) } }
end)

------------------------------------------------------------------------
-- Teleport-Befehle (Recht player.teleport, nur im Dienst)
------------------------------------------------------------------------

local COORD_LIMIT = 10000   -- Karte liegt sicher innerhalb von +-10000
local HEIGHT_MIN, HEIGHT_MAX = -500, 3000

local function logTeleport(admin, action, target, data)
    Core.Log({
        actor_account_id = admin.accountId,
        account_id = target and target.accountId or admin.accountId,
        character_id = target and target.characterId or admin.characterId,
        category = 'admin',
        action = action,
        data = data,
    })
end

local function requireIngame(source)
    if source == 0 then
        Platform.Print('warn', 'Teleport-Befehle gehen nur ingame.')
        return nil
    end
    local admin = Core.GetPlayer(source)
    if not admin or not admin.character then
        Platform.Notify(source, 'Das geht nur mit einem Charakter.', 'error')
        return nil
    end
    return admin
end

-- Wer teleportiert wird, landet in der Dimension des Ziels (sonst sieht man sich nicht)
function followDimension(mover, anchor, actorSource)
    if Dimensions and anchor and Dimensions.Get(mover) ~= Dimensions.Get(anchor) then
        Dimensions.Set(mover, Dimensions.Get(anchor), actorSource, 'Teleport')
    end
end

-- /bring <permanente ID>: Spieler zum Admin holen
Core.RegisterAdminCommand('bring', 'player.teleport', function(source, args)
    local admin = requireIngame(source)
    if not admin then return end
    if not args[1] then
        Platform.Notify(source, 'Benutzung: /bring <permanente ID>', 'info')
        return
    end
    local target, err = Core.ResolveTarget(source, args[1])
    if not target then
        Platform.Notify(source, err, 'error')
        return
    end
    if target == source then
        Platform.Notify(source, 'Das geht nicht mit dir selbst.', 'error')
        return
    end
    local player = Core.GetPlayer(target)
    if player.jail then
        Platform.Notify(source, 'Die Person sitzt im A-Jail und kann nicht geholt werden.', 'error')
        return
    end
    local position = Platform.GetPlayerPosition(source)
    if not position then
        Platform.Notify(source, 'Deine Position konnte nicht gelesen werden.', 'error')
        return
    end
    followDimension(player, admin, source)
    Network.SendToClient(target, TELEPORT_EVENT, offset(position))
    logTeleport(admin, 'bring', player, { position = position })
    Platform.Notify(source, ('ID %d geholt.'):format(player.characterId), 'success')
end, { requireDuty = true })

-- Zahlen aus "/tp 215.3, -810.2, 30" oder "/tp 215 -810"
local function parseNumbers(args)
    local numbers = {}
    for value in table.concat(args, ' '):gmatch('-?%d+%.?%d*') do
        numbers[#numbers + 1] = tonumber(value)
    end
    return numbers
end

AdminTeleport = {}

-- Zufaelliger anderer Spieler mit Charakter oder nil
local function randomPlayer(source)
    local list = {}
    for _, player in pairs(Core.Players) do
        if player.character and player.source ~= source then
            list[#list + 1] = player
        end
    end
    if #list == 0 then
        return nil
    end
    return list[math.random(#list)]
end

-- Ziel aus den Argumenten: leer = zufaelliger Spieler, eine Zahl = permanente ID, zwei oder drei = Koordinaten.
-- spacing: Abstand zum Spieler in Metern. Gibt { position, target?, label, action, data } oder nil und einen Text zurueck.
function AdminTeleport.Resolve(source, args, spacing)
    local numbers = parseNumbers(args)

    if #numbers == 0 or #numbers == 1 then
        local player
        if #numbers == 0 then
            if args[1] then
                return nil, nil
            end
            player = randomPlayer(source)
            if not player then
                return nil, 'Gerade ist niemand anderes im Spiel.'
            end
        else
            local target, err = Core.ResolveTarget(source, tostring(math.floor(numbers[1])))
            if not target then
                return nil, err
            end
            if target == source then
                return nil, 'Das geht nicht mit dir selbst.'
            end
            player = Core.GetPlayer(target)
        end
        local position = Platform.GetPlayerPosition(player.source)
        if not position then
            return nil, 'Die Position konnte nicht gelesen werden.'
        end
        return {
            position = { x = position.x + (spacing or TELEPORT_OFFSET), y = position.y, z = position.z, heading = position.heading },
            target = player,
            label = ('ID %d'):format(player.characterId),
            action = 'teleport_to',
            data = { position = position, random = #numbers == 0 or nil },
        }
    end

    if #numbers == 2 or #numbers == 3 then
        local x, y, z = numbers[1], numbers[2], numbers[3]
        if math.abs(x) > COORD_LIMIT or math.abs(y) > COORD_LIMIT or (z and (z < HEIGHT_MIN or z > HEIGHT_MAX)) then
            return nil, 'Diese Koordinaten liegen außerhalb der Karte.'
        end
        return {
            -- Ohne Hoehe von oben auf den Boden setzen
            position = { x = x, y = y, z = z or HEIGHT_MAX / 3, ground = z == nil },
            label = ('%.1f, %.1f%s'):format(x, y, z and (', %.1f'):format(z) or ''),
            action = 'teleport_coords',
            data = { position = { x = x, y = y, z = z } },
        }
    end
    return nil, nil
end

-- Teleport ausfuehren, der ziel-Spieler bestimmt die Dimension. Gibt den Text fuer den Admin zurueck.
function AdminTeleport.Apply(admin, destination, logAction)
    Spectate.Stop(admin, 'Teleport', true)
    followDimension(admin, destination.target, admin.source)
    logTeleport(admin, logAction or destination.action, destination.target, destination.data)
end

local TP_USAGE = 'Benutzung: /tp (zufälliger Spieler), /tp <permanente ID> oder /tp <x> <y> [z], z. B. /tp 215.3 -810.2 30.7'

local function teleportCommand(usage)
    return function(source, args)
        local admin = requireIngame(source)
        if not admin then return end
        local destination, err = AdminTeleport.Resolve(source, args)
        if not destination then
            Platform.Notify(source, err or usage, err and 'error' or 'info')
            return
        end
        AdminTeleport.Apply(admin, destination)
        Network.SendToClient(source, TELEPORT_EVENT, destination.position)
        local text = destination.data.random and 'Zufällig zu %s teleportiert.' or 'Zu %s teleportiert.'
        Platform.Notify(source, text:format(destination.label), 'success')
    end
end

-- /tp                    zu einem zufaelligen Spieler
-- /tp <permanente ID>    zum Spieler
-- /tp <x> <y> [z]        zu Koordinaten (ohne z auf den Boden)
Core.RegisterAdminCommand('tp', 'player.teleport', teleportCommand(TP_USAGE), { requireDuty = true })

-- /goto <permanente ID>  wie /tp mit ID
Core.RegisterAdminCommand('goto', 'player.teleport', function(source, args)
    if not args[1] or not args[1]:match('^%d+$') then
        Platform.Notify(source, 'Benutzung: /goto <permanente ID>', 'info')
        return
    end
    teleportCommand('Benutzung: /goto <permanente ID>')(source, args)
end, { requireDuty = true })
