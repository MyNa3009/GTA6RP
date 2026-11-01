-- A-Jail (Admin-Jail): ein Ort, aus dem man nicht rauskommt.
-- Gilt fuer einen Charakter (permanente ID). Mit anderen Charakteren kann man normal spielen.
-- Die Zeit laeuft nur, solange der Spieler mit einem Charakter online ist.
-- Der Server prueft die Position selbst und setzt jeden zurueck, der draussen ist.

Jail = {}

local CONSOLE = 0
local SECONDS_PER_MINUTE = 60
local MS_PER_SECOND = 1000
-- So lange nach dem Spawn oder Teleport keine Positionspruefung, weil der Ped erst ankommen muss
local GRACE_SECONDS = 10
local RETURN_GRACE_SECONDS = 2

local START_EVENT = 'core:jail:start'
local SYNC_EVENT = 'core:jail:sync'
local RETURN_EVENT = 'core:jail:return'
local END_EVENT = 'core:jail:end'

local ACTIVE_SQL = [[
    SELECT id, account_id, character_id, reason, minutes, remaining_seconds, jailed_by
    FROM admin_jails WHERE character_id = ? AND released_at IS NULL
    ORDER BY id DESC LIMIT 1
]]

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Liegt die Position im A-Jail? (z. B. gespeicherte Position nach dem Entlassen)
function Jail.IsInside(position)
    if type(position) ~= 'table' or not tonumber(position.x) then
        return false
    end
    return distance(position, JailData.cell) <= JailData.radius
end

local function jailerName(accountId)
    if not accountId then
        return nil
    end
    return DB.Scalar([[
        SELECT CONCAT(firstname, ' ', lastname) FROM characters
        WHERE account_id = ? AND deleted_at IS NULL
        ORDER BY last_played IS NULL, last_played DESC LIMIT 1
    ]], { accountId })
end

-- Was der Client fuer die Anzeige braucht
function Jail.ClientInfo(jail)
    if not jail then
        return nil
    end
    return {
        remaining = math.max(0, jail.remaining),
        total = jail.minutes * SECONDS_PER_MINUTE,
        reason = jail.reason,
        by = jail.jailedByName,
    }
end

local function fromRow(row)
    return {
        id = row.id,
        accountId = row.account_id,
        characterId = row.character_id,
        reason = row.reason,
        minutes = tonumber(row.minutes) or 0,
        remaining = tonumber(row.remaining_seconds) or 0,
        jailedBy = row.jailed_by,
        jailedByName = jailerName(row.jailed_by),
        lastTick = os.time(),
        savedAt = os.time(),
        escapes = 0,
        lastEscapeLog = 0,
        graceUntil = os.time() + GRACE_SECONDS,
    }
end

local function save(jail)
    jail.savedAt = os.time()
    DB.Update(
        'UPDATE admin_jails SET remaining_seconds = ? WHERE id = ? AND released_at IS NULL',
        { math.max(0, jail.remaining), jail.id }
    )
end

------------------------------------------------------------------------
-- Laden und Entladen (mit dem Charakter)
------------------------------------------------------------------------

-- Beim Auswaehlen eines Charakters. Gibt das aktive A-Jail zurueck oder nil.
function Jail.Load(player)
    player.jail = nil
    if not Punish.Ready then
        return nil
    end
    local row = DB.Single(ACTIVE_SQL, { player.characterId })
    if not row then
        return nil
    end
    player.jail = fromRow(row)
    return player.jail
end

-- Beim Verlassen des Charakters: Restzeit speichern
function Jail.Unload(player)
    local jail = player and player.jail
    if not jail then
        return
    end
    jail.remaining = jail.remaining - (os.time() - jail.lastTick)
    save(jail)
    player.jail = nil
end

-- Nach dem Tod im A-Jail wacht man wieder im A-Jail auf
function Jail.RespawnPosition(player)
    if player and player.jail then
        return JailData.cell
    end
    return nil
end

------------------------------------------------------------------------
-- Rein und raus
------------------------------------------------------------------------

-- Spieler sofort ins A-Jail setzen (er ist online und spielt einen Charakter)
local function putIn(player)
    local character = player.character
    local wasDead = character.diedAt ~= nil
    character.diedAt = nil
    if wasDead then
        Needs.AfterRespawn(player.source)
    end
    player.jail.graceUntil = os.time() + GRACE_SECONDS
    -- Im A-Jail kein Admin-Dienst (beendet auch Noclip)
    if player.adminDuty then
        AdminDuty.Set(player.source, false)
    end
    Core.StopNoclip(player, 'A-Jail')
    -- Das A-Jail liegt in der normalen Welt
    Dimensions.Set(player, 0, nil, 'A-Jail')
    Network.SendToClient(player.source, START_EVENT, {
        position = JailData.cell,
        revive = wasDead,
        jail = Jail.ClientInfo(player.jail),
    })
end

-- Gibt die Jail-ID zurueck (und true, wenn der Spieler sofort drin ist) oder nil und einen Fehlercode
function Jail.Start(actorSource, characterId, minutes, reason)
    if not Punish.Ready then return nil, 'not_ready' end

    minutes = tonumber(minutes)
    if not minutes or minutes ~= math.floor(minutes) or minutes < 1 or minutes > Config.Jail.MaxMinutes then
        return nil, 'invalid_minutes'
    end
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
    if DB.Single(ACTIVE_SQL, { characterId }) then
        return nil, 'already_jailed'
    end

    local target = Core.GetPlayerByCharacter(characterId)
    local actorAccountId = Punish.ActorAccountId(actorSource)
    local seconds = minutes * SECONDS_PER_MINUTE

    local jailId = DB.Insert(
        'INSERT INTO admin_jails (account_id, character_id, reason, minutes, remaining_seconds, jailed_by) VALUES (?, ?, ?, ?, ?, ?)',
        DB.Args(accountId, characterId, reason, minutes, seconds, actorAccountId)
    )
    if not jailId then
        return nil, 'db_error'
    end

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = accountId,
        character_id = characterId,
        category = 'punishment',
        action = 'jail',
        reason = reason,
        data = { jailId = jailId, minutes = minutes, characterName = characterName, online = target ~= nil, console = actorSource == CONSOLE or nil },
    })

    if target then
        target.jail = fromRow({
            id = jailId, account_id = accountId, character_id = characterId,
            reason = reason, minutes = minutes, remaining_seconds = seconds, jailed_by = actorAccountId,
        })
        putIn(target)
        Platform.Notify(target.source, ('Du bist für %d Minuten im A-Jail. Grund: %s'):format(minutes, reason), 'warning')
        return jailId, true
    end
    return jailId, false
end

-- releasedBy = nil heisst: Zeit abgesessen
local function finish(player, jail, actorAccountId, reason, served)
    local remaining = served and 0 or math.max(0, jail.remaining)
    local changed = DB.Update(
        'UPDATE admin_jails SET released_at = CURRENT_TIMESTAMP, released_by = ?, release_reason = ?, remaining_seconds = ? WHERE id = ? AND released_at IS NULL',
        DB.Args(actorAccountId, reason, remaining, jail.id)
    )
    if changed == nil then
        return false, 'db_error'
    end

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = jail.accountId,
        character_id = jail.characterId,
        category = 'punishment',
        action = served and 'jail_done' or 'unjail',
        reason = reason,
        data = { jailId = jail.id, minutes = jail.minutes, remaining = remaining, escapes = jail.escapes ~= 0 and jail.escapes or nil },
    })

    if player and player.jail and player.jail.id == jail.id then
        player.jail = nil
        Network.SendToClient(player.source, END_EVENT, { position = JailData.release })
        Platform.Notify(player.source, served and 'Deine Zeit im A-Jail ist vorbei.' or 'Du wurdest aus dem A-Jail entlassen.', 'success')
    end
    return true
end

-- Vorzeitig entlassen, egal ob online oder offline
function Jail.Release(actorSource, characterId, reason)
    if not Punish.Ready then return false, 'not_ready' end
    characterId = tonumber(characterId)
    local actorAccountId = Punish.ActorAccountId(actorSource)

    local player = characterId and Core.GetPlayerByCharacter(characterId)
    if player and player.jail then
        local jail = player.jail
        jail.remaining = jail.remaining - (os.time() - jail.lastTick)
        jail.lastTick = os.time()
        return finish(player, jail, actorAccountId, reason, false)
    end

    local row = characterId and DB.Single(ACTIVE_SQL, { characterId })
    if not row then
        return false, 'not_jailed'
    end
    return finish(nil, fromRow(row), actorAccountId, reason, false)
end

------------------------------------------------------------------------
-- Fuer das Admin-Menue
------------------------------------------------------------------------

-- Aktives A-Jail mit aktueller Restzeit, auch wenn der Spieler offline ist
function Jail.ActiveFor(characterId)
    local player = Core.GetPlayerByCharacter(characterId)
    if player and player.jail then
        local jail = player.jail
        return {
            id = jail.id, reason = jail.reason, minutes = jail.minutes, jailedBy = jail.jailedBy,
            remaining = math.max(0, jail.remaining - (os.time() - jail.lastTick)), running = true,
        }
    end
    if not Punish.Ready then return nil end
    local row = DB.Single(ACTIVE_SQL, { characterId })
    if not row then
        return nil
    end
    return {
        id = row.id, reason = row.reason, minutes = tonumber(row.minutes), jailedBy = row.jailed_by,
        remaining = tonumber(row.remaining_seconds) or 0, running = false,
    }
end

function Jail.ListForAccount(accountId)
    if not Punish.Ready then return {} end
    local rows = DB.Query([[
        SELECT id, character_id, reason, minutes, remaining_seconds, jailed_by, released_by, release_reason,
               UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(released_at) AS released_at
        FROM admin_jails WHERE account_id = ? ORDER BY id DESC
    ]], { accountId }) or {}

    local list = {}
    for i, row in ipairs(rows) do
        local active = row.released_at == nil
        local live = active and row.character_id and Jail.ActiveFor(row.character_id) or nil
        list[i] = {
            id = row.id,
            characterId = row.character_id,
            reason = row.reason,
            minutes = tonumber(row.minutes),
            remaining = (active and live and live.id == row.id) and live.remaining or tonumber(row.remaining_seconds),
            jailedBy = row.jailed_by,
            releasedBy = row.released_by,
            releaseReason = row.release_reason,
            createdAt = row.created_at and tonumber(row.created_at) * MS_PER_SECOND or nil,
            releasedAt = row.released_at and tonumber(row.released_at) * MS_PER_SECOND or nil,
            active = active,
        }
    end
    return list
end

------------------------------------------------------------------------
-- Waechter: Zeit zaehlen, Flucht verhindern, Restzeit speichern
------------------------------------------------------------------------

local function logEscape(player, jail, position, now)
    jail.escapes = jail.escapes + 1
    if now - jail.lastEscapeLog < Config.Jail.EscapeLogCooldownSeconds then
        return
    end
    jail.lastEscapeLog = now
    Core.Log({
        account_id = player.accountId,
        character_id = player.characterId,
        category = 'punishment',
        action = 'jail_escape',
        data = { jailId = jail.id, position = position, attempts = jail.escapes },
    })
end

Platform.SetInterval(Config.Jail.CheckIntervalMs, function()
    local now = os.time()
    for _, player in pairs(Core.Players) do
        local jail = player.jail
        if jail and player.character then
            jail.remaining = jail.remaining - (now - jail.lastTick)
            jail.lastTick = now

            if jail.remaining <= 0 then
                finish(player, jail, nil, 'Zeit abgesessen', true)
            else
                local position = now >= jail.graceUntil and Platform.GetPlayerPosition(player.source)
                if position and distance(position, JailData.cell) > JailData.radius then
                    Network.SendToClient(player.source, RETURN_EVENT, { position = JailData.cell })
                    jail.graceUntil = now + RETURN_GRACE_SECONDS
                    logEscape(player, jail, position, now)
                end
                if now - jail.savedAt >= Config.Jail.SaveIntervalSeconds then
                    save(jail)
                    Network.SendToClient(player.source, SYNC_EVENT, { remaining = jail.remaining })
                end
            end
        end
    end
end)

------------------------------------------------------------------------
-- Befehle (Recht player.ajail)
------------------------------------------------------------------------

-- /ajail <permanente ID> <minuten> <grund>
Core.RegisterAdminCommand('ajail', 'player.ajail', function(source, args)
    local characterId = tonumber(args[1])
    local reason = table.concat(args, ' ', 3)
    if not characterId or not args[2] or reason == '' then
        Platform.Notify(source, 'Benutzung: /ajail <permanente ID> <minuten> <grund>', 'info')
        return
    end
    local jailId, online = Jail.Start(source, characterId, tonumber(args[2]), reason)
    if not jailId then
        Platform.Notify(source, Punish.ErrorText(online), 'error')
        return
    end
    Platform.Notify(source, online
        and ('ID %d sitzt jetzt %d Minuten im A-Jail.'):format(characterId, tonumber(args[2]))
        or ('ID %d ist gerade nicht im Spiel und landet beim nächsten Spielen im A-Jail.'):format(characterId), 'success')
end, { requireDuty = true })

-- /unjail <permanente ID> [grund]
Core.RegisterAdminCommand('unjail', 'player.ajail', function(source, args)
    local characterId = tonumber(args[1])
    if not characterId then
        Platform.Notify(source, 'Benutzung: /unjail <permanente ID> [grund]', 'info')
        return
    end
    local reason, valid = Punish.OptionalReason(table.concat(args, ' ', 2))
    if not valid then
        Platform.Notify(source, Punish.ErrorText('invalid_reason'), 'error')
        return
    end
    local ok, err = Jail.Release(source, characterId, reason)
    if not ok then
        Platform.Notify(source, Punish.ErrorText(err), 'error')
        return
    end
    Platform.Notify(source, ('ID %d aus dem A-Jail entlassen.'):format(characterId), 'success')
end, { requireDuty = true })
