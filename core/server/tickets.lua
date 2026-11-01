-- Tickets: Spieler schreiben dem Team ueber /report, das Team uebernimmt mit /claim oder in der UI.
-- Spieler: ein offenes Ticket pro Charakter, 25 Sekunden Pause zwischen Nachrichten, geschlossene Tickets nur noch lesen.
-- Team (Recht tickets.manage): alle Tickets sehen, uebernehmen, antworten, schliessen, wieder oeffnen.
-- Jede Nachricht steht in ticket_messages, Erstellen, Uebernehmen, Schliessen und Oeffnen zusaetzlich im Log.

Tickets = { Ready = false }

local CONSOLE = 0
local MANAGE = 'tickets.manage'
local MESSAGE_EVENT = 'core:ticket:message'
local CHANGED_EVENT = 'core:ticket:changed'
local NAME_MAX = 64
local SUBJECT_MAX = 120

local CREATE_TICKETS = [[
    CREATE TABLE IF NOT EXISTS tickets (
        id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        account_id           INT UNSIGNED NOT NULL,
        character_id         INT UNSIGNED NOT NULL,
        character_name       VARCHAR(64) NOT NULL,
        category             VARCHAR(16) NOT NULL,
        subject              VARCHAR(120) NOT NULL,
        status               ENUM('open', 'claimed', 'closed') NOT NULL DEFAULT 'open',
        claimed_by           INT UNSIGNED NULL,     -- Login des Admins
        claimed_by_character INT UNSIGNED NULL,     -- permanente ID des Admins
        claimed_by_name      VARCHAR(64) NULL,
        claimed_at           TIMESTAMP NULL DEFAULT NULL,
        closed_by            INT UNSIGNED NULL,
        closed_at            TIMESTAMP NULL DEFAULT NULL,
        created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_tickets_status (status, updated_at),
        INDEX idx_tickets_character (character_id, created_at),
        INDEX idx_tickets_claimer (claimed_by_character, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local CREATE_MESSAGES = [[
    CREATE TABLE IF NOT EXISTS ticket_messages (
        id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        ticket_id           INT UNSIGNED NOT NULL,
        author_account_id   INT UNSIGNED NULL,
        author_character_id INT UNSIGNED NULL,
        author_name         VARCHAR(64) NOT NULL,
        role                ENUM('player', 'admin', 'system') NOT NULL,
        body                VARCHAR(600) NOT NULL,
        created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_ticket_messages (ticket_id, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

DB.Ready(function()
    if DB.Query(CREATE_TICKETS) == nil or DB.Query(CREATE_MESSAGES) == nil then
        Platform.Print('error', 'Tabellen fuer Tickets konnten nicht angelegt werden. Bitte 008_tickets.sql ausfuehren.')
        return
    end
    Tickets.Ready = true
end)

local CATEGORY_LABELS = {}
for _, category in ipairs(Config.Tickets.Categories) do
    CATEGORY_LABELS[category.id] = category.label
end

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local SUMMARY_FIELDS = [[
    id, account_id, character_id, character_name, category, subject, status,
    claimed_by, claimed_by_character, claimed_by_name, closed_by,
    UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(updated_at) AS updated_at,
    UNIX_TIMESTAMP(claimed_at) AS claimed_at, UNIX_TIMESTAMP(closed_at) AS closed_at
]]

local function nameOf(player)
    local character = player and player.character
    if not character then
        return nil
    end
    return ('%s %s'):format(character.firstname, character.lastname):sub(1, NAME_MAX)
end

local function onlineByCharacter()
    local map = {}
    for _, player in pairs(Core.Players) do
        if player.characterId then
            map[player.characterId] = player
        end
    end
    return map
end

local function summary(row, online)
    local owner = online[tonumber(row.character_id)]
    local claimer = row.claimed_by_character and online[tonumber(row.claimed_by_character)] or nil
    return {
        id = tonumber(row.id),
        accountId = tonumber(row.account_id),
        characterId = tonumber(row.character_id),
        characterName = row.character_name,
        category = row.category,
        categoryLabel = CATEGORY_LABELS[row.category] or row.category,
        subject = row.subject,
        status = row.status,
        claimedById = tonumber(row.claimed_by_character),
        claimedByName = row.claimed_by_name,
        claimedByOnline = claimer ~= nil or nil,
        createdAt = tonumber(row.created_at),
        updatedAt = tonumber(row.updated_at),
        claimedAt = tonumber(row.claimed_at),
        closedAt = tonumber(row.closed_at),
        serverId = owner and owner.source or nil,
    }
end

local function fetch(id)
    id = tonumber(id)
    if not id then
        return nil
    end
    return DB.Single('SELECT ' .. SUMMARY_FIELDS .. ' FROM tickets WHERE id = ?', { math.floor(id) })
end

local function canManage(source)
    return Core.HasPermission(source, MANAGE)
end

local function isOwner(player, row)
    return player and player.characterId ~= nil and player.characterId == tonumber(row.character_id)
end

local function dutyMissing(player)
    return Config.Admin.RequireDutyForActions and not player.adminDuty
end

-- Text pruefen: Leerzeichen am Rand weg, Zeilenumbrueche bleiben, Laenge in Zeichen
local function cleanText(text)
    if type(text) ~= 'string' then
        return nil
    end
    text = text:gsub('\r', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('\n\n\n+', '\n\n')
    local length = utf8.len(text)
    if not length or length < Config.Tickets.MessageMinLength or length > Config.Tickets.MessageMaxLength then
        return nil
    end
    return text
end

local function subjectOf(text)
    local line = text:gsub('%s+', ' ')
    if utf8.len(line) > SUBJECT_MAX then
        line = line:sub(1, utf8.offset(line, SUBJECT_MAX - 1) - 1) .. '…'
    end
    return line
end

local function log(actorAccountId, row, action, data)
    Core.Log({
        actor_account_id = actorAccountId,
        account_id = tonumber(row.account_id),
        character_id = tonumber(row.character_id),
        category = 'ticket',
        action = action,
        data = data,
    })
end

local function cooldownLeft(player)
    return math.max(0, (player.ticketCooldownUntil or 0) - os.time())
end

------------------------------------------------------------------------
-- Nachrichten und Live-Updates
------------------------------------------------------------------------

local function messageFromRow(row)
    return {
        id = tonumber(row.id),
        authorId = tonumber(row.author_character_id),
        authorName = row.author_name,
        role = row.role,
        body = row.body,
        createdAt = tonumber(row.created_at),
    }
end

-- Wer die UI offen hat und dieses Ticket sehen darf, bekommt die Aenderung sofort
local function pushChanged(row)
    local online = onlineByCharacter()
    local data = summary(row, online)
    for _, player in pairs(Core.Players) do
        if player.ticketUi and (isOwner(player, row) or (player.ticketUi == 'admin' and canManage(player.source))) then
            Network.SendToClient(player.source, CHANGED_EVENT, data)
        end
    end
end

local function addMessage(row, author, role, body)
    local id = DB.Insert(
        'INSERT INTO ticket_messages (ticket_id, author_account_id, author_character_id, author_name, role, body) VALUES (?, ?, ?, ?, ?, ?)',
        DB.Args(tonumber(row.id), author and author.accountId, author and author.characterId, author and nameOf(author) or 'System', role, body)
    )
    if not id then
        return nil
    end
    DB.Fire('UPDATE tickets SET updated_at = CURRENT_TIMESTAMP WHERE id = ?', { tonumber(row.id) })
    local message = {
        id = id,
        authorId = author and author.characterId or nil,
        authorName = author and nameOf(author) or 'System',
        role = role,
        body = body,
        createdAt = os.time(),
    }
    for _, player in pairs(Core.Players) do
        if player.viewingTicket == tonumber(row.id) then
            Network.SendToClient(player.source, MESSAGE_EVENT, { ticketId = tonumber(row.id), message = message })
        end
    end
    return message
end

local function systemMessage(row, text)
    return addMessage(row, nil, 'system', text)
end

-- Team benachrichtigen (im Dienst, ausser es ist anders eingestellt). Wer das Ticket gerade offen hat, sieht es schon.
local function notifyTeam(text, row, onlyCharacterId)
    for _, player in pairs(Core.Players) do
        if player.character and canManage(player.source) and player.viewingTicket ~= tonumber(row.id)
            and (player.adminDuty or Config.Tickets.NotifyOffDuty)
            and (not onlyCharacterId or player.characterId == onlyCharacterId)
            and not isOwner(player, row) then
            Platform.Notify(player.source, text, 'info')
        end
    end
end

local function notifyOwner(row, text)
    local owner = Core.GetPlayerByCharacter(row.character_id)
    if owner and owner.viewingTicket ~= tonumber(row.id) then
        Platform.Notify(owner.source, text, 'info')
    end
end

local function label(player)
    return ('%s (ID %d)'):format(nameOf(player) or '?', player.characterId or 0)
end

------------------------------------------------------------------------
-- Spieler
------------------------------------------------------------------------

local function notReady()
    return { ok = false, error = 'not_ready' }
end

-- Eigene Tickets dieses Charakters, aktuelles zuerst
Core.RegisterCallback('ticket_mine', function(source)
    if not Tickets.Ready then return notReady() end
    local player = Core.GetPlayer(source)
    if not player.character then
        return { ok = false, error = 'no_character' }
    end
    player.ticketUi = 'player'
    local rows = DB.Query(
        ('SELECT %s FROM tickets WHERE character_id = ? ORDER BY (status <> \'closed\') DESC, id DESC LIMIT %d')
            :format(SUMMARY_FIELDS, Config.Tickets.HistoryLimit),
        { player.characterId }
    ) or {}
    local online, list = onlineByCharacter(), {}
    for _, row in ipairs(rows) do
        list[#list + 1] = summary(row, online)
    end
    return { ok = true, data = { tickets = list, cooldown = cooldownLeft(player) } }
end)

Core.RegisterCallback('ticket_create', function(source, data)
    if not Tickets.Ready then return notReady() end
    local player = Core.GetPlayer(source)
    if not player.character then
        return { ok = false, error = 'no_character' }
    end
    if not CATEGORY_LABELS[data.category] then
        return { ok = false, error = 'invalid_category' }
    end
    local text = cleanText(data.text)
    if not text then
        return { ok = false, error = 'invalid_text' }
    end
    local wait = cooldownLeft(player)
    if wait > 0 then
        return { ok = false, error = 'cooldown', data = { cooldown = wait } }
    end
    local active = DB.Scalar("SELECT id FROM tickets WHERE character_id = ? AND status <> 'closed' LIMIT 1", { player.characterId })
    if active then
        return { ok = false, error = 'already_open', data = { id = tonumber(active) } }
    end

    local id = DB.Insert(
        'INSERT INTO tickets (account_id, character_id, character_name, category, subject) VALUES (?, ?, ?, ?, ?)',
        { player.accountId, player.characterId, nameOf(player), data.category, subjectOf(text) }
    )
    if not id then
        return { ok = false, error = 'db_error' }
    end
    local row = fetch(id)
    addMessage(row, player, 'player', text)
    player.ticketCooldownUntil = os.time() + Config.Tickets.PlayerCooldownSeconds
    log(player.accountId, row, 'ticket_create', { ticketId = id, category = data.category })

    notifyTeam(('Neues Ticket #%d von %s: %s. Übernehmen mit /claim %d'):format(id, label(player), CATEGORY_LABELS[data.category], id), row)
    pushChanged(row)
    return { ok = true, data = { ticket = summary(row, onlineByCharacter()), cooldown = Config.Tickets.PlayerCooldownSeconds } }
end)

------------------------------------------------------------------------
-- Ticket ansehen und schreiben (Spieler und Team)
------------------------------------------------------------------------

local function canSee(player, row)
    return isOwner(player, row) or canManage(player.source)
end

-- Darf dieser Spieler gerade schreiben? Gibt die Rolle oder nil und einen Fehlercode zurueck.
local function writeRole(player, row)
    if row.status == 'closed' then
        return nil, 'closed'
    end
    if isOwner(player, row) then
        return 'player'
    end
    if not canManage(player.source) then
        return nil, 'no_permission'
    end
    if tonumber(row.claimed_by_character) ~= player.characterId then
        return nil, 'not_claimed'
    end
    if dutyMissing(player) then
        return nil, 'duty_required'
    end
    return 'admin'
end

Core.RegisterCallback('ticket_get', function(source, data)
    if not Tickets.Ready then return notReady() end
    local player = Core.GetPlayer(source)
    local row = fetch(data.id)
    if not row or not canSee(player, row) then
        return { ok = false, error = 'not_found' }
    end
    player.viewingTicket = tonumber(row.id)
    local rows = DB.Query(
        ('SELECT id, author_character_id, author_name, role, body, UNIX_TIMESTAMP(created_at) AS created_at FROM ticket_messages WHERE ticket_id = ? ORDER BY id DESC LIMIT %d')
            :format(Config.Tickets.MessageLimit),
        { tonumber(row.id) }
    ) or {}
    local messages = {}
    for i = #rows, 1, -1 do
        messages[#messages + 1] = messageFromRow(rows[i])
    end
    if not isOwner(player, row) then
        Core.Log({
            actor_account_id = player.accountId,
            account_id = tonumber(row.account_id),
            character_id = tonumber(row.character_id),
            category = 'ticket',
            action = 'ticket_view',
            data = { ticketId = tonumber(row.id) },
        })
    end
    local role = writeRole(player, row)
    return {
        ok = true,
        data = {
            ticket = summary(row, onlineByCharacter()),
            messages = messages,
            canWrite = role ~= nil,
            cooldown = isOwner(player, row) and cooldownLeft(player) or 0,
        },
    }
end)

Core.RegisterCallback('ticket_send', function(source, data)
    if not Tickets.Ready then return notReady() end
    local player = Core.GetPlayer(source)
    local row = fetch(data.id)
    if not row or not canSee(player, row) then
        return { ok = false, error = 'not_found' }
    end
    local role, err = writeRole(player, row)
    if not role then
        return { ok = false, error = err }
    end
    local text = cleanText(data.text)
    if not text then
        return { ok = false, error = 'invalid_text' }
    end
    if role == 'player' then
        local wait = cooldownLeft(player)
        if wait > 0 then
            return { ok = false, error = 'cooldown', data = { cooldown = wait } }
        end
    end

    local message = addMessage(row, player, role, text)
    if not message then
        return { ok = false, error = 'db_error' }
    end
    if role == 'player' then
        player.ticketCooldownUntil = os.time() + Config.Tickets.PlayerCooldownSeconds
        local text = ('Neue Nachricht in Ticket #%d von %s.'):format(tonumber(row.id), label(player))
        notifyTeam(text, row, row.status == 'claimed' and tonumber(row.claimed_by_character) or nil)
    else
        notifyOwner(row, ('Das Team hat in deinem Ticket #%d geantwortet. Öffnen mit /report'):format(tonumber(row.id)))
    end
    pushChanged(fetch(row.id))
    return { ok = true, data = { message = message, cooldown = role == 'player' and Config.Tickets.PlayerCooldownSeconds or 0 } }
end)

Core.RegisterCallback('ticket_ui_close', function(source)
    local player = Core.GetPlayer(source)
    if player then
        player.ticketUi = nil
        player.viewingTicket = nil
    end
    return { ok = true }
end, { public = true })

------------------------------------------------------------------------
-- Team: Liste, Uebernehmen, Freigeben, Schliessen, Oeffnen
------------------------------------------------------------------------

local LIST_FILTERS = {
    open = "status <> 'closed'",
    mine = "status = 'claimed' AND claimed_by_character = ?",
    closed = "status = 'closed'",
    player = 'character_id = ?',
}
local LIST_ORDER = {
    open = "(status = 'open') DESC, created_at ASC",  -- wer am laengsten wartet, steht oben
    mine = 'updated_at DESC',
    closed = 'closed_at DESC',
    player = 'id DESC',
}

local function counts(player)
    local row = DB.Single([[
        SELECT SUM(status = 'open') AS open, SUM(status = 'claimed') AS claimed,
               SUM(status = 'claimed' AND claimed_by_character = ?) AS mine
        FROM tickets WHERE status <> 'closed'
    ]], { player.characterId or 0 }) or {}
    return { open = tonumber(row.open) or 0, claimed = tonumber(row.claimed) or 0, mine = tonumber(row.mine) or 0 }
end

function Tickets.OpenCount()
    if not Tickets.Ready then
        return 0
    end
    return tonumber(DB.Scalar("SELECT COUNT(*) FROM tickets WHERE status = 'open'")) or 0
end

Core.RegisterCallback('ticket_list', function(source, data)
    if not Tickets.Ready then return notReady() end
    if not canManage(source) then
        return { ok = false, error = 'no_permission' }
    end
    local player = Core.GetPlayer(source)
    local filter = LIST_FILTERS[data.filter] and data.filter or 'open'
    local params = {}
    if filter == 'mine' then
        params[1] = player.characterId or 0
    elseif filter == 'player' then
        local characterId = tonumber(data.characterId)
        if not characterId then
            return { ok = false, error = 'invalid_query' }
        end
        params[1] = math.floor(characterId)
    end
    player.ticketUi = 'admin'
    local rows = DB.Query(
        ('SELECT %s FROM tickets WHERE %s ORDER BY %s LIMIT %d'):format(SUMMARY_FIELDS, LIST_FILTERS[filter], LIST_ORDER[filter], Config.Tickets.ListLimit),
        params
    ) or {}
    local online, list = onlineByCharacter(), {}
    for _, row in ipairs(rows) do
        list[#list + 1] = summary(row, online)
    end
    return {
        ok = true,
        data = {
            tickets = list,
            filter = filter,
            counts = counts(player),
            permissions = {
                teleport = Core.HasPermission(source, 'player.teleport'),
                spectate = Core.HasPermission(source, 'player.spectate'),
            },
            duty = player.adminDuty ~= nil,
            dutyRequired = Config.Admin.RequireDutyForActions,
            selfId = player.characterId,
        },
    }
end)

-- Gemeinsame Pruefung fuer alle Team-Aktionen an einem Ticket
local function teamAction(source, id)
    if not Tickets.Ready then return nil, nil, 'not_ready' end
    if not canManage(source) then return nil, nil, 'no_permission' end
    local player = Core.GetPlayer(source)
    if not player or not player.character then return nil, nil, 'no_character' end
    if dutyMissing(player) then return nil, nil, 'duty_required' end
    local row = fetch(id)
    if not row then return nil, nil, 'not_found' end
    return player, row
end

-- Uebernehmen. Gibt true oder nil, einen Fehlercode und Zusatzdaten zurueck. Auch fuer /claim.
function Tickets.Claim(source, id)
    local player, row, err = teamAction(source, id)
    if not player then return nil, err end
    if isOwner(player, row) then return nil, 'own_ticket' end
    if row.status == 'closed' then return nil, 'closed' end
    local claimerId = tonumber(row.claimed_by_character)
    if claimerId == player.characterId then return nil, 'already_yours' end
    -- Wer offline ist, haelt kein Ticket fest
    if row.status == 'claimed' and Core.GetPlayerByCharacter(claimerId) then
        return nil, 'claimed_by_other', { name = row.claimed_by_name }
    end
    local changed = DB.Update(
        "UPDATE tickets SET status = 'claimed', claimed_by = ?, claimed_by_character = ?, claimed_by_name = ?, claimed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND status <> 'closed' AND (claimed_by_character IS NULL OR claimed_by_character = ?)",
        DB.Args(player.accountId, player.characterId, nameOf(player), tonumber(row.id), claimerId)
    )
    if not changed or changed < 1 then
        return nil, 'claimed_by_other', { name = row.claimed_by_name }
    end
    row = fetch(row.id)
    systemMessage(row, ('%s hat das Ticket übernommen.'):format(label(player)))
    log(player.accountId, row, 'ticket_claim', { ticketId = tonumber(row.id), from = claimerId })
    notifyOwner(row, ('%s kümmert sich um dein Ticket #%d. Öffnen mit /report'):format(nameOf(player), tonumber(row.id)))
    pushChanged(row)
    return true
end

function Tickets.Unclaim(source, id)
    local player, row, err = teamAction(source, id)
    if not player then return nil, err end
    if row.status ~= 'claimed' or tonumber(row.claimed_by_character) ~= player.characterId then
        return nil, 'not_claimed'
    end
    DB.Update("UPDATE tickets SET status = 'open', claimed_by = NULL, claimed_by_character = NULL, claimed_by_name = NULL, claimed_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ?", { tonumber(row.id) })
    row = fetch(row.id)
    systemMessage(row, ('%s hat das Ticket wieder freigegeben.'):format(label(player)))
    log(player.accountId, row, 'ticket_unclaim', { ticketId = tonumber(row.id) })
    pushChanged(row)
    return true
end

-- Schliessen darf, wer es uebernommen hat. Ist niemand dran (oder offline), darf jeder mit dem Recht.
function Tickets.Close(source, id)
    local player, row, err = teamAction(source, id)
    if not player then return nil, err end
    if row.status == 'closed' then return nil, 'closed' end
    local claimerId = tonumber(row.claimed_by_character)
    if row.status == 'claimed' and claimerId ~= player.characterId and Core.GetPlayerByCharacter(claimerId) then
        return nil, 'claimed_by_other', { name = row.claimed_by_name }
    end
    DB.Update("UPDATE tickets SET status = 'closed', closed_by = ?, closed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?", { player.accountId, tonumber(row.id) })
    row = fetch(row.id)
    systemMessage(row, ('%s hat das Ticket geschlossen. Für ein neues Anliegen bitte ein neues Ticket erstellen.'):format(label(player)))
    log(player.accountId, row, 'ticket_close', { ticketId = tonumber(row.id) })
    notifyOwner(row, ('Dein Ticket #%d wurde geschlossen.'):format(tonumber(row.id)))
    pushChanged(row)
    return true
end

-- Wieder oeffnen geht nur ueber das Team, der Oeffnende uebernimmt es direkt
function Tickets.Reopen(source, id)
    local player, row, err = teamAction(source, id)
    if not player then return nil, err end
    if row.status ~= 'closed' then return nil, 'not_closed' end
    if isOwner(player, row) then return nil, 'own_ticket' end
    DB.Update(
        "UPDATE tickets SET status = 'claimed', claimed_by = ?, claimed_by_character = ?, claimed_by_name = ?, claimed_at = CURRENT_TIMESTAMP, closed_by = NULL, closed_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        { player.accountId, player.characterId, nameOf(player), tonumber(row.id) }
    )
    row = fetch(row.id)
    systemMessage(row, ('%s hat das Ticket wieder geöffnet.'):format(label(player)))
    log(player.accountId, row, 'ticket_reopen', { ticketId = tonumber(row.id) })
    notifyOwner(row, ('Dein Ticket #%d wurde wieder geöffnet. Öffnen mit /report'):format(tonumber(row.id)))
    pushChanged(row)
    return true
end

local ACTIONS = {
    claim = Tickets.Claim,
    unclaim = Tickets.Unclaim,
    close = Tickets.Close,
    reopen = Tickets.Reopen,
}

Core.RegisterCallback('ticket_action', function(source, data)
    local fn = ACTIONS[data.action]
    if not fn then
        return { ok = false, error = 'unknown_action' }
    end
    local ok, err, extra = fn(source, data.id)
    if not ok then
        return { ok = false, error = err, data = extra }
    end
    return { ok = true, data = { ticket = summary(fetch(data.id), onlineByCharacter()) } }
end)

-- Aus dem Ticket heraus: zum Spieler teleportieren oder ihn beobachten
Core.RegisterCallback('ticket_goto', function(source, data)
    local player, row, err = teamAction(source, data.id)
    if not player then return { ok = false, error = err } end
    if not Core.HasPermission(source, 'player.teleport') then return { ok = false, error = 'no_permission' } end
    local owner = Core.GetPlayerByCharacter(row.character_id)
    if not owner then return { ok = false, error = 'target_offline' } end
    if owner.source == source then return { ok = false, error = 'self' } end
    local destination, text = AdminTeleport.Resolve(source, { tostring(owner.characterId) })
    if not destination then return { ok = false, error = 'no_position', data = { text = text } } end
    AdminTeleport.Apply(player, destination)
    Network.SendToClient(source, 'core:admin:teleport', destination.position)
    return { ok = true }
end)

Core.RegisterCallback('ticket_spectate', function(source, data)
    local player, row, err = teamAction(source, data.id)
    if not player then return { ok = false, error = err } end
    local owner = Core.GetPlayerByCharacter(row.character_id)
    if not owner then return { ok = false, error = 'target_offline' } end
    local ok, spectateErr = Spectate.Start(source, owner)
    if not ok then return { ok = false, error = spectateErr } end
    return { ok = true }
end)

------------------------------------------------------------------------
-- /claim <ticket-ID>
------------------------------------------------------------------------

local CLAIM_ERRORS = {
    not_ready = 'Tickets sind noch nicht bereit.',
    no_permission = 'Dafür hast du keine Rechte.',
    no_character = 'Das geht nur mit einem Charakter.',
    duty_required = 'Das geht nur im Admin-Dienst. Starte ihn mit /aduty.',
    not_found = 'Dieses Ticket gibt es nicht.',
    own_ticket = 'Dein eigenes Ticket kannst du nicht übernehmen.',
    closed = 'Dieses Ticket ist geschlossen.',
    already_yours = 'Das Ticket hast du schon übernommen.',
}

Core.RegisterAdminCommand('claim', MANAGE, function(source, args)
    if source == CONSOLE then
        Platform.Print('warn', 'Tickets übernehmen geht nur ingame.')
        return
    end
    local id = tonumber(args[1] and args[1]:gsub('^#', '') or nil)
    if not id then
        Platform.Notify(source, 'Benutzung: /claim <ticket-ID>, z. B. /claim 12', 'info')
        return
    end
    local ok, err, extra = Tickets.Claim(source, id)
    if not ok then
        local text = err == 'claimed_by_other' and ('%s bearbeitet das Ticket schon.'):format(extra and extra.name or 'Jemand anderes')
            or CLAIM_ERRORS[err] or tostring(err)
        Platform.Notify(source, text, 'error')
        return
    end
    Platform.Notify(source, ('Ticket #%d übernommen. Öffnen mit /tickets'):format(id), 'success')
    Network.SendToClient(source, 'core:ticket:open', { id = id })
end, { requireDuty = true })
