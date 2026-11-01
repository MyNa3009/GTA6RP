-- Strafen: gemeinsame Hilfen fuer Bans und A-Jail, Tabellen anlegen.

Punish = {}

local DEBUG = Platform.GetConvar('core_debug', 'false') == 'true'
local CONSOLE = 0
local SECONDS_PER_DAY = 86400

local UNIT_SECONDS = { m = 60, h = 3600, d = SECONDS_PER_DAY, w = 7 * SECONDS_PER_DAY }
local PERMANENT_WORDS = { perm = true, permanent = true, ['0'] = true }

local CREATE_BANS = [[
    CREATE TABLE IF NOT EXISTS bans (
        id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        account_id   INT UNSIGNED NOT NULL,
        character_id INT UNSIGNED NULL,          -- NULL = ganzer Account, sonst nur dieser Charakter
        reason       VARCHAR(255) NOT NULL,
        banned_by    INT UNSIGNED NULL,          -- NULL = Konsole
        created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expires_at   TIMESTAMP NULL DEFAULT NULL, -- NULL = permanent
        lifted_at    TIMESTAMP NULL DEFAULT NULL,
        lifted_by    INT UNSIGNED NULL,
        lift_reason  VARCHAR(255) NULL,
        INDEX idx_bans_account (account_id),
        INDEX idx_bans_character (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local CREATE_JAILS = [[
    CREATE TABLE IF NOT EXISTS admin_jails (
        id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        account_id        INT UNSIGNED NOT NULL,
        character_id      INT UNSIGNED NULL,     -- Charakter, mit dem gespielt wurde (nur zur Info)
        reason            VARCHAR(255) NOT NULL,
        minutes           INT UNSIGNED NOT NULL,
        remaining_seconds INT UNSIGNED NOT NULL, -- laeuft nur, solange der Spieler online ist
        jailed_by         INT UNSIGNED NULL,
        created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        released_at       TIMESTAMP NULL DEFAULT NULL,
        released_by       INT UNSIGNED NULL,     -- NULL und released_at gesetzt = Zeit abgesessen
        release_reason    VARCHAR(255) NULL,
        INDEX idx_jails_account (account_id, released_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

Punish.Ready = false

DB.Ready(function()
    if DB.Query(CREATE_BANS) == nil or DB.Query(CREATE_JAILS) == nil then
        Platform.Print('error', 'Tabellen bans oder admin_jails konnten nicht angelegt werden. Bitte 004_punishments.sql ausfuehren.')
        return
    end
    -- Seit 0.9.1 gilt das A-Jail pro Charakter. Alte A-Jails ohne Charakter werden beendet.
    DB.Update([[
        UPDATE admin_jails SET released_at = CURRENT_TIMESTAMP, release_reason = 'Umstellung auf Charakter-IDs'
        WHERE character_id IS NULL AND released_at IS NULL
    ]])
    Punish.Ready = true
end)

------------------------------------------------------------------------
-- Eingaben pruefen
------------------------------------------------------------------------

-- '30m', '12h', '7d', '2w' -> Sekunden, 'perm' -> 0 (fuer immer), sonst nil
function Punish.ParseDuration(text)
    if type(text) ~= 'string' then
        return nil
    end
    text = text:lower():match('^%s*(.-)%s*$')
    if PERMANENT_WORDS[text] then
        return 0
    end
    local amount, unit = text:match('^(%d+)([mhdw])$')
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return nil
    end
    local seconds = amount * UNIT_SECONDS[unit]
    if seconds > Config.Bans.MaxDays * SECONDS_PER_DAY then
        return nil
    end
    return seconds
end

-- Bereinigter Grund oder nil
function Punish.CleanReason(text)
    if type(text) ~= 'string' then
        return nil
    end
    local reason = text:gsub('[%c]', ' '):match('^%s*(.-)%s*$')
    local length = utf8.len(reason)
    if not length or length < Config.Punish.ReasonMinLength or length > Config.Punish.ReasonMaxLength then
        return nil
    end
    return reason
end

-- Optionaler Grund (Entbannen, Entlassen): leer ist erlaubt
function Punish.OptionalReason(text)
    if type(text) ~= 'string' or text:match('^%s*$') then
        return nil, true
    end
    local reason = Punish.CleanReason(text)
    return reason, reason ~= nil
end

-- Darf actorSource das Ziel bestrafen? Nur Raenge unterhalb des eigenen, nie sich selbst oder eigene Twinks.
-- Mit characterId zaehlt der Rang dieses Charakters, sonst der hoechste Rang aller Charaktere des Logins.
-- Im Debug-Modus darf man sich selbst bestrafen, damit man allein testen kann.
function Punish.CheckTarget(actorSource, targetAccountId, targetCharacterId)
    if DB.Scalar('SELECT id FROM accounts WHERE id = ?', { targetAccountId }) == nil then
        return false, 'account_not_found'
    end
    if actorSource == CONSOLE then
        return true
    end

    local actor = Core.GetPlayer(actorSource)
    if actor and actor.accountId == targetAccountId then
        if DEBUG then
            return true
        end
        return false, 'self'
    end

    local targetRank
    if targetCharacterId then
        targetRank = Permissions.OfCharacter(targetCharacterId)
    else
        targetRank = Permissions.HighestOfAccount(targetAccountId)
    end
    if targetRank and targetRank.level >= Core.GetRank(actorSource).level then
        return false, 'target_too_high'
    end
    return true
end

function Punish.ActorAccountId(source)
    if source == CONSOLE then
        return nil
    end
    local player = Core.GetPlayer(source)
    return player and player.accountId or nil
end

------------------------------------------------------------------------
-- Anzeige
------------------------------------------------------------------------

function Punish.FormatTime(seconds)
    return os.date('%d.%m.%Y %H:%M', seconds)
end

function Punish.FormatDuration(seconds)
    if seconds == 0 then
        return 'permanent'
    end
    local days = seconds // SECONDS_PER_DAY
    local hours = (seconds % SECONDS_PER_DAY) // UNIT_SECONDS.h
    local minutes = (seconds % UNIT_SECONDS.h) // UNIT_SECONDS.m
    local parts = {}
    if days > 0 then parts[#parts + 1] = days .. (days == 1 and ' Tag' or ' Tage') end
    if hours > 0 then parts[#parts + 1] = hours .. ' Std.' end
    if minutes > 0 then parts[#parts + 1] = minutes .. ' Min.' end
    return table.concat(parts, ' ')
end

function Punish.CharacterName(characterId)
    local row = characterId and DB.Single('SELECT account_id, firstname, lastname FROM characters WHERE id = ?', { characterId })
    if not row then
        return nil, nil
    end
    return ('%s %s'):format(row.firstname, row.lastname), row.account_id
end

-- Fehlertexte fuer Befehle
Punish.ERRORS = {
    account_not_found = 'Diesen Login gibt es nicht.',
    character_not_found = 'Keinen Charakter mit dieser permanenten ID gefunden.',
    self = 'Das geht nicht mit dir selbst.',
    target_too_high = 'Diese Person hat denselben oder einen höheren Teamrang als du.',
    invalid_reason = ('Gib einen Grund mit %d bis %d Zeichen an.'):format(Config.Punish.ReasonMinLength, Config.Punish.ReasonMaxLength),
    invalid_duration = ('Ungültige Dauer. Beispiele: 30m, 12h, 7d, 2w oder perm. Höchstens %d Tage.'):format(Config.Bans.MaxDays),
    invalid_minutes = ('Gib die Minuten als Zahl von 1 bis %d an.'):format(Config.Jail.MaxMinutes),
    already_banned = 'Dafür gibt es schon einen aktiven Ban.',
    not_banned = 'Dafür gibt es keinen aktiven Ban.',
    already_jailed = 'Diese ID sitzt schon im A-Jail. Erst /unjail, dann neu vergeben.',
    not_jailed = 'Diese ID sitzt nicht im A-Jail.',
    not_ready = 'Die Strafen-Tabellen fehlen. Siehe Serverkonsole.',
    db_error = 'Datenbankfehler, siehe Serverkonsole.',
}

function Punish.ErrorText(code)
    return Punish.ERRORS[code] or tostring(code)
end
