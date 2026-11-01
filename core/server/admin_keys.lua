-- Admin-Keys: Jedes Teammitglied hat einen eigenen Key. Ohne eingegebenen Key hat es keine Rechte, wie ein Spieler.
-- Eingabe einmal pro Sitzung (bis Relog, Charakterwechsel oder Disconnect), beim ersten /aduty oder F10.
-- Erstellen und Loeschen im Admin-Menue (Recht admin.keys), nur fuer Raenge unter dem eigenen und nie fuer eigene Charaktere.
-- Den ersten Key (z. B. fuer den Chief) gibt die Server-Konsole: adminkey <permanente ID>
-- Gespeichert wird nur der Hash. Der Key selbst steht nirgends, auch nicht im Log.

AdminKeys = {}

local CONSOLE = 0
local KEY_GROUPS = 4
local KEY_GROUP_LENGTH = 4
local KEY_INPUT_MAX = 64
local SECONDS_PER_MINUTE = 60
local PROMPT_EVENT = 'core:admin:key_prompt'
local LOCKED_EVENT = 'core:admin:key_locked'

local failures = {} -- [characterId] = { count, lockedUntil }

local CREATE_TABLE = [[
    CREATE TABLE IF NOT EXISTS admin_keys (
        character_id INT UNSIGNED NOT NULL PRIMARY KEY,
        key_hash VARCHAR(255) NOT NULL,
        created_by_character INT UNSIGNED NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_used_at DATETIME NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

DB.Ready(function()
    if DB.Query(CREATE_TABLE) == nil then
        Platform.Print('error', 'Tabelle admin_keys konnte nicht angelegt werden. Ohne sie kann sich kein Teammitglied freischalten.')
    end
end)

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function enabled()
    return Config.AdminKeys.Enabled == true
end

-- Gross, ohne Leerzeichen und Bindestriche: "abcd-efgh" und "ABCDEFGH" sind derselbe Key
local function normalize(key)
    if type(key) ~= 'string' or #key > KEY_INPUT_MAX then
        return nil
    end
    local clean = key:upper():gsub('[%s%-]', '')
    if #clean ~= KEY_GROUPS * KEY_GROUP_LENGTH or not clean:match('^[%w]+$') then
        return nil
    end
    return clean
end

local function format(clean)
    local groups = {}
    for i = 1, KEY_GROUPS do
        groups[i] = clean:sub((i - 1) * KEY_GROUP_LENGTH + 1, i * KEY_GROUP_LENGTH)
    end
    return table.concat(groups, '-')
end

local function isTeamRank(rank)
    return rank ~= nil and rank.level > Permissions.Get(Permissions.DefaultId()).level
end

local function rankOf(player)
    return Permissions.Get(player.rank) or Permissions.Get(Permissions.DefaultId())
end

local function lockState(characterId)
    local entry = failures[characterId]
    if entry and entry.lockedUntil then
        local left = entry.lockedUntil - os.time()
        if left > 0 then
            return math.ceil(left / SECONDS_PER_MINUTE)
        end
        failures[characterId] = nil
    end
    return nil
end

local function hasKey(characterId)
    return DB.Scalar('SELECT 1 FROM admin_keys WHERE character_id = ?', { characterId }) ~= nil
end

------------------------------------------------------------------------
-- Abfragen fuer andere Teile der Core
------------------------------------------------------------------------

-- Hat dieser Spieler seine Rechte freigeschaltet? Spieler ohne Teamrang brauchen keinen Key.
function AdminKeys.IsUnlocked(player)
    if not enabled() or not isTeamRank(rankOf(player)) then
        return true
    end
    return player.character ~= nil and player.character.adminUnlocked == true
end

-- Wuerde der Rang dieses Recht geben, fehlt aber noch der Key?
function AdminKeys.NeedsUnlock(source, permission)
    if source == CONSOLE or not enabled() then
        return false
    end
    local player = Core.GetPlayer(source)
    if not player or not player.loggedIn or not player.character then
        return false
    end
    return not AdminKeys.IsUnlocked(player) and Permissions.RankAllows(player.rank, permission)
end

-- Eingabe-Fenster beim Client oeffnen. options: { duty = true } startet danach den Admin-Dienst, { menu = true } oeffnet das Menue.
-- Ohne Key oder waehrend der Sperre gibt es nur eine Meldung.
function AdminKeys.Prompt(source, options)
    local player = Core.GetPlayer(source)
    if not player or not player.character then
        return
    end
    local minutes = lockState(player.characterId)
    if minutes then
        Platform.Notify(source, ('Zu viele falsche Admin-Keys. Wieder möglich in %d Minuten.'):format(minutes), 'error')
        return
    end
    if not hasKey(player.characterId) then
        Platform.Notify(source, 'Du hast noch keinen Admin-Key. Ein Senior Administrator erstellt ihn dir im Admin-Menü.', 'error')
        return
    end
    Network.SendToClient(source, PROMPT_EVENT, {
        duty = options and options.duty == true or nil,
        menu = options and options.menu == true or nil,
    })
end

-- Freischaltung aufheben (neuer Key, Key geloescht). Laufender Admin-Dienst endet.
local function lockOnline(characterId, reason)
    local player = Core.GetPlayerByCharacter(characterId)
    if not player or not player.character or not player.character.adminUnlocked then
        return
    end
    player.character.adminUnlocked = nil
    if player.adminDuty then
        AdminDuty.Set(player.source, false)
    end
    AdminHelp.SendHidden(player.source)
    Network.SendToClient(player.source, LOCKED_EVENT, {})
    Platform.Notify(player.source, reason, 'warning')
end

------------------------------------------------------------------------
-- Akte im Admin-Menue
------------------------------------------------------------------------

-- Darf source fuer diesen Charakter Keys erstellen und loeschen? Gibt true oder false und einen Fehlercode zurueck.
local function canManage(source, characterId)
    if source ~= CONSOLE and not Core.HasPermission(source, 'admin.keys') then
        return false, 'no_permission'
    end
    local target = DB.Single('SELECT account_id, admin_rank, deleted_at FROM characters WHERE id = ?', { characterId })
    if not target then
        return false, 'not_found'
    end
    if target.deleted_at then
        return false, 'character_deleted'
    end
    local targetRank = Permissions.Get(target.admin_rank)
    if not isTeamRank(targetRank) then
        return false, 'no_team_rank'
    end
    if source == CONSOLE then
        return true
    end
    local actor = Core.GetPlayer(source)
    if actor.accountId == target.account_id then
        return false, 'own_key'
    end
    if targetRank.level >= rankOf(actor).level then
        return false, 'target_too_high'
    end
    return true
end

-- Fuer die Akte: Zustand des Keys oder nil, wenn der Betrachter keine Keys verwalten darf
function AdminKeys.InfoFor(source, characterId)
    if not characterId or not Core.HasPermission(source, 'admin.keys') then
        return nil
    end
    local allowed, reason = canManage(source, characterId)
    if reason == 'no_team_rank' or reason == 'not_found' then
        return nil
    end
    local row = DB.Single([[
        SELECT created_by_character, UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(last_used_at) AS last_used_at
        FROM admin_keys WHERE character_id = ?
    ]], { characterId })
    return {
        characterId = characterId,
        exists = row ~= nil,
        createdBy = row and row.created_by_character or nil,
        createdAt = row and tonumber(row.created_at) and math.floor(tonumber(row.created_at) * 1000) or nil,
        lastUsedAt = row and tonumber(row.last_used_at) and math.floor(tonumber(row.last_used_at) * 1000) or nil,
        canManage = allowed,
        reason = not allowed and reason or nil,
        locked = lockState(characterId) ~= nil or nil,
    }
end

-- Neuen Key erstellen. Ein alter Key wird sofort ungueltig. Gibt den Key (nur dieses eine Mal) oder nil und einen Fehlercode zurueck.
function AdminKeys.Create(source, characterId)
    local allowed, err = canManage(source, characterId)
    if not allowed then
        return nil, err
    end
    local clean = Platform.RandomToken(KEY_GROUPS * KEY_GROUP_LENGTH)
    local actor = source ~= CONSOLE and Core.GetPlayer(source) or nil
    local replaced = hasKey(characterId)
    local saved = DB.Query([[
        REPLACE INTO admin_keys (character_id, key_hash, created_by_character, created_at, last_used_at)
        VALUES (?, ?, ?, NOW(), NULL)
    ]], DB.Args(characterId, Platform.HashPassword(clean), actor and actor.characterId or nil))
    if saved == nil then
        return nil, 'db_error'
    end
    failures[characterId] = nil
    Core.Log({
        actor_account_id = actor and actor.accountId or nil,
        account_id = DB.Scalar('SELECT account_id FROM characters WHERE id = ?', { characterId }),
        character_id = characterId,
        category = 'admin',
        action = 'admin_key_create',
        data = { replaced = replaced or nil, console = source == CONSOLE or nil },
    })
    lockOnline(characterId, 'Dein Admin-Key wurde neu erstellt. Gib den neuen Key mit /aduty ein.')
    return format(clean)
end

function AdminKeys.Delete(source, characterId)
    local allowed, err = canManage(source, characterId)
    if not allowed then
        return nil, err
    end
    local removed = DB.Update('DELETE FROM admin_keys WHERE character_id = ?', { characterId })
    if not removed or removed == 0 then
        return nil, 'no_key'
    end
    local actor = source ~= CONSOLE and Core.GetPlayer(source) or nil
    Core.Log({
        actor_account_id = actor and actor.accountId or nil,
        account_id = DB.Scalar('SELECT account_id FROM characters WHERE id = ?', { characterId }),
        character_id = characterId,
        category = 'admin',
        action = 'admin_key_delete',
    })
    lockOnline(characterId, 'Dein Admin-Key wurde gelöscht. Deine Admin-Rechte sind gesperrt.')
    return true
end

-- Rang auf Spieler gesetzt: Key wird nicht mehr gebraucht
function AdminKeys.OnRankChanged(characterId, rank)
    if not isTeamRank(rank) then
        DB.Update('DELETE FROM admin_keys WHERE character_id = ?', { characterId })
        failures[characterId] = nil
    end
end

------------------------------------------------------------------------
-- Freischalten
------------------------------------------------------------------------

local function alertTeam(player)
    local text = ('Admin-Key: %d falsche Versuche für ID %d. Für %d Minuten gesperrt.'):format(
        Config.AdminKeys.MaxAttempts, player.characterId, Config.AdminKeys.LockMinutes)
    for _, other in pairs(Core.Players) do
        if other.source ~= player.source and Core.HasPermission(other.source, 'admin.keys') then
            Platform.Notify(other.source, text, 'warning')
        end
    end
end

Core.RegisterCallback('admin_key_unlock', function(source, data)
    local player = Core.GetPlayer(source)
    if not player.character then
        return { ok = false, error = 'no_character' }
    end
    if not enabled() or not isTeamRank(rankOf(player)) then
        return { ok = false, error = 'no_team_rank' }
    end
    if AdminKeys.IsUnlocked(player) then
        return { ok = true, data = { already = true } }
    end
    local characterId = player.characterId
    local minutes = lockState(characterId)
    if minutes then
        return { ok = false, error = 'locked', data = { minutes = minutes } }
    end
    local row = DB.Single('SELECT key_hash FROM admin_keys WHERE character_id = ?', { characterId })
    if not row then
        return { ok = false, error = 'no_key' }
    end

    local clean = normalize(data.key)
    if not clean or not Platform.VerifyPassword(clean, row.key_hash) then
        local entry = failures[characterId] or { count = 0 }
        entry.count = entry.count + 1
        failures[characterId] = entry
        local lockedNow = entry.count >= Config.AdminKeys.MaxAttempts
        if lockedNow then
            entry.lockedUntil = os.time() + Config.AdminKeys.LockMinutes * SECONDS_PER_MINUTE
        end
        Core.Log({
            actor_account_id = player.accountId,
            account_id = player.accountId,
            character_id = characterId,
            category = 'security',
            action = lockedNow and 'admin_key_locked' or 'admin_key_failed',
            data = { attempt = entry.count },
        })
        if lockedNow then
            alertTeam(player)
            return { ok = false, error = 'locked', data = { minutes = Config.AdminKeys.LockMinutes } }
        end
        return { ok = false, error = 'wrong_key', data = { left = Config.AdminKeys.MaxAttempts - entry.count } }
    end

    failures[characterId] = nil
    player.character.adminUnlocked = true
    DB.Update('UPDATE admin_keys SET last_used_at = NOW() WHERE character_id = ?', { characterId })
    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = characterId,
        category = 'admin',
        action = 'admin_key_unlock',
        data = { rank = player.rank },
    })
    AdminHelp.SendHidden(source)

    local duty = false
    if data.duty == true and not player.adminDuty and Core.HasPermission(source, 'admin.duty') then
        duty = AdminDuty.Set(source, true) == true
    end
    return { ok = true, data = { duty = duty } }
end)

-- Aus dem Admin-Menue
Core.RegisterCallback('admin_key_create', function(source, data)
    local characterId = tonumber(data.characterId)
    if not characterId then
        return { ok = false, error = 'not_found' }
    end
    local key, err = AdminKeys.Create(source, characterId)
    if not key then
        return { ok = false, error = err }
    end
    return { ok = true, data = { key = key, info = AdminKeys.InfoFor(source, characterId) } }
end)

Core.RegisterCallback('admin_key_delete', function(source, data)
    local characterId = tonumber(data.characterId)
    if not characterId then
        return { ok = false, error = 'not_found' }
    end
    local ok, err = AdminKeys.Delete(source, characterId)
    if not ok then
        return { ok = false, error = err }
    end
    return { ok = true, data = { info = AdminKeys.InfoFor(source, characterId) } }
end)

-- Nach der Charakterwahl: Teammitglieder erinnern, dass ihre Rechte noch gesperrt sind
Platform.OnEvent('core:characterLoaded', function(source)
    local player = Core.GetPlayer(source)
    if player and enabled() and isTeamRank(rankOf(player)) and not AdminKeys.IsUnlocked(player) then
        Platform.Notify(source, 'Deine Admin-Rechte sind gesperrt, bis du deinen Admin-Key eingibst: /aduty', 'info')
    end
end)

------------------------------------------------------------------------
-- Konsole: adminkey <permanente ID>
-- Nur in der Server-Konsole (txAdmin), damit der Key nie im Chat steht. Fuer den ersten Key oder den Chief.
------------------------------------------------------------------------

local CONSOLE_ERRORS = {
    not_found = 'Keinen Charakter mit dieser permanenten ID gefunden.',
    character_deleted = 'Dieser Charakter ist gelöscht.',
    no_team_rank = 'Dieser Charakter hat keinen Teamrang. Zuerst /setrank.',
    db_error = 'Datenbankfehler, siehe oben.',
}

Platform.RegisterCommand('adminkey', function(source, args)
    if source ~= CONSOLE then
        Platform.Notify(source, 'Admin-Keys erstellst du im Admin-Menü in der Akte der Person.', 'info')
        return
    end
    local characterId = tonumber(args[1])
    if not characterId then
        Platform.Print('info', 'Benutzung: adminkey <permanente ID>')
        return
    end
    local key, err = AdminKeys.Create(CONSOLE, characterId)
    if not key then
        Platform.Print('error', CONSOLE_ERRORS[err] or tostring(err))
        return
    end
    Platform.Print('ok', ('Admin-Key fuer ID %d: %s (nur jetzt sichtbar, privat weitergeben)'):format(characterId, key))
end)
