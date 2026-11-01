-- Mehrere Accounts mit derselben Rockstar-Lizenz (Social Club).
-- Wird erkannt, sobald ein Geraet, dessen Lizenz zu Account A gehoert, sich bei Account B einloggt oder registriert.
-- Der andere Account muss dafuer nicht online sein: Die Lizenz von A steht dauerhaft in der Datenbank.
-- Beim Serverstart werden ausserdem alte Treffer aus dem Log nachgetragen.
-- Die Warnung bleibt gespeichert, egal ob einer oder beide offline sind, bis ein Admin sie ausblendet.

MultiAccount = {}

local TYPES = {}
for _, idType in ipairs(Config.Accounts.MultiAccountIdentifiers or {}) do
    TYPES[idType] = true
end
TYPES.hardware = true -- gleicher PC, siehe server/devices.lua

local TYPE_TEXT = {
    license = 'dieselbe Rockstar-Lizenz',
    license2 = 'dieselbe Rockstar-Lizenz',
    hardware = 'denselben PC',
}

local INSERTED = 1 -- MariaDB meldet 1 bei neuer Zeile, 2 bei ON DUPLICATE KEY UPDATE

local function pair(a, b)
    return math.min(a, b), math.max(a, b)
end

local function notifyAdmins(message)
    for _, player in pairs(Core.Players) do
        if player.loggedIn and Core.HasPermission(player.source, 'admin.menu') then
            Platform.Notify(player.source, message, 'warning')
        end
    end
end
MultiAccount.NotifyAdmins = notifyAdmins

-- options.silent: keine Chat-Meldung (z. B. beim Nachtragen beim Serverstart)
function MultiAccount.Record(accountId, otherAccountId, identifierType, options)
    if not TYPES[identifierType] or not accountId or not otherAccountId or accountId == otherAccountId then
        return false
    end
    local silent = options and options.silent == true
    local a, b = pair(accountId, otherAccountId)
    local pairKnown = DB.Scalar('SELECT id FROM account_links WHERE account_a = ? AND account_b = ? LIMIT 1', { a, b }) ~= nil

    local changed = DB.Update([[
        INSERT INTO account_links (account_a, account_b, identifier_type) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE times_seen = times_seen + 1, last_seen = CURRENT_TIMESTAMP
    ]], { a, b, identifierType })

    if changed == INSERTED then
        Core.Log({
            account_id = accountId,
            target_account_id = otherAccountId,
            category = 'security',
            action = 'multi_account',
            reason = silent and 'Beim Serverstart aus dem Log nachgetragen' or nil,
            data = { type = identifierType },
        })
        -- Nur beim ersten Treffer zwischen zwei Accounts melden, nicht fuer jede weitere Lizenz
        if not pairKnown and not silent then
            notifyAdmins(('Warnung: Login %d nutzt %s wie Login %d.'):format(accountId, TYPE_TEXT[identifierType] or identifierType, otherAccountId))
        end
        return true
    end
    return false
end

-- Alle offenen Warnungen, unabhaengig davon, wer online ist
function MultiAccount.ListActive(limit)
    return DB.Query([[
        SELECT account_a, account_b,
               GROUP_CONCAT(identifier_type ORDER BY identifier_type SEPARATOR ',') AS types,
               SUM(times_seen) AS times_seen,
               UNIX_TIMESTAMP(MIN(first_seen)) AS first_seen,
               UNIX_TIMESTAMP(MAX(last_seen)) AS last_seen
        FROM account_links
        WHERE dismissed_at IS NULL
        GROUP BY account_a, account_b
        ORDER BY MAX(last_seen) DESC
        LIMIT ?
    ]], { limit }) or {}
end

function MultiAccount.CountActive()
    return DB.Scalar([[
        SELECT COUNT(*) FROM (
            SELECT 1 FROM account_links WHERE dismissed_at IS NULL GROUP BY account_a, account_b
        ) AS pairs
    ]]) or 0
end

-- Alte Treffer aus dem Log nachtragen (Konflikte, die vor dieser Version passiert sind)
function MultiAccount.Backfill()
    local rows = DB.Query([[
        SELECT DISTINCT account_id, target_account_id,
               JSON_UNQUOTE(JSON_EXTRACT(data, '$.type')) AS identifier_type
        FROM audit_log
        WHERE category = 'security' AND action = 'identifier_conflict'
          AND account_id IS NOT NULL AND target_account_id IS NOT NULL
    ]]) or {}

    local added = 0
    for _, row in ipairs(rows) do
        local a, b = pair(row.account_id, row.target_account_id)
        local known = DB.Scalar(
            'SELECT id FROM account_links WHERE account_a = ? AND account_b = ? AND identifier_type = ?',
            { a, b, row.identifier_type }
        )
        -- Schon bekannte Treffer nicht noch einmal zaehlen, sonst steigt "gesehen" bei jedem Neustart
        if not known and MultiAccount.Record(row.account_id, row.target_account_id, row.identifier_type, { silent = true }) then
            added = added + 1
        end
    end
    if added > 0 then
        Platform.Print('warn', ('%d Multi-Account-Treffer aus dem Log nachgetragen.'):format(added))
    end
end

-- Tabelle beim Start selbst anlegen, falls die Migration noch nicht ausgefuehrt wurde
local CREATE_TABLE = [[
    CREATE TABLE IF NOT EXISTS account_links (
        id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        account_a       INT UNSIGNED NOT NULL,
        account_b       INT UNSIGNED NOT NULL,
        identifier_type VARCHAR(32) NOT NULL,
        first_seen      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        times_seen      INT UNSIGNED NOT NULL DEFAULT 1,
        dismissed_by    INT UNSIGNED NULL,
        dismissed_at    TIMESTAMP NULL DEFAULT NULL,
        UNIQUE KEY uniq_pair (account_a, account_b, identifier_type),
        INDEX idx_b (account_b)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

DB.Ready(function()
    if DB.Query(CREATE_TABLE) == nil then
        Platform.Print('error', 'Tabelle account_links konnte nicht angelegt werden. Bitte 003_account_links.sql ausfuehren.')
        return
    end
    -- Nur solange die Tabelle leer ist. Danach wuerde jeder Neustart das ganze audit_log lesen.
    if (tonumber(DB.Scalar('SELECT COUNT(*) FROM account_links')) or 0) == 0 then
        MultiAccount.Backfill()
    end
end)

-- Alle Verknuepfungen eines Accounts, gruppiert nach dem anderen Account
function MultiAccount.ForAccount(accountId)
    local rows = DB.Query([[
        SELECT account_a, account_b, identifier_type, times_seen, dismissed_by,
               UNIX_TIMESTAMP(first_seen) AS first_seen,
               UNIX_TIMESTAMP(last_seen) AS last_seen,
               UNIX_TIMESTAMP(dismissed_at) AS dismissed_at
        FROM account_links
        WHERE account_a = ? OR account_b = ?
        ORDER BY first_seen ASC
    ]], { accountId, accountId }) or {}

    local byOther, list = {}, {}
    for _, row in ipairs(rows) do
        local other = row.account_a == accountId and row.account_b or row.account_a
        local entry = byOther[other]
        if not entry then
            entry = { otherAccountId = other, types = {}, timesSeen = 0, firstSeen = row.first_seen, lastSeen = row.last_seen, active = false }
            byOther[other] = entry
            list[#list + 1] = entry
        end
        entry.types[#entry.types + 1] = row.identifier_type
        entry.timesSeen = entry.timesSeen + (row.times_seen or 0)
        if (row.last_seen or 0) > (entry.lastSeen or 0) then
            entry.lastSeen = row.last_seen
        end
        if row.dismissed_at == nil then
            entry.active = true
        else
            entry.dismissedBy = row.dismissed_by
            entry.dismissedAt = row.dismissed_at
        end
    end
    return list
end

-- Menge der Account-IDs (aus der Liste), die eine aktive Warnung haben
function MultiAccount.ActiveFor(accountIds)
    local result = {}
    if #accountIds == 0 then
        return result
    end
    local marks = string.rep('?', #accountIds, ', ')
    local params = {}
    for _, id in ipairs(accountIds) do params[#params + 1] = id end
    for _, id in ipairs(accountIds) do params[#params + 1] = id end

    local rows = DB.Query(([[
        SELECT account_a, account_b FROM account_links
        WHERE dismissed_at IS NULL AND (account_a IN (%s) OR account_b IN (%s))
    ]]):format(marks, marks), params) or {}

    for _, row in ipairs(rows) do
        result[row.account_a] = true
        result[row.account_b] = true
    end
    return result
end

-- Warnung zwischen zwei Accounts aus- oder wieder einblenden
function MultiAccount.SetDismissed(accountId, otherAccountId, dismissed, actorAccountId)
    local a, b = pair(accountId, otherAccountId)
    local changed
    if dismissed then
        changed = DB.Update(
            'UPDATE account_links SET dismissed_by = ?, dismissed_at = CURRENT_TIMESTAMP WHERE account_a = ? AND account_b = ? AND dismissed_at IS NULL',
            { actorAccountId, a, b }
        )
    else
        changed = DB.Update(
            'UPDATE account_links SET dismissed_by = NULL, dismissed_at = NULL WHERE account_a = ? AND account_b = ?',
            { a, b }
        )
    end
    if changed == nil then
        return false, 'db_error'
    end
    if changed == 0 then
        return false, 'not_found'
    end

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = accountId,
        target_account_id = otherAccountId,
        category = 'admin',
        action = dismissed and 'multi_account_dismissed' or 'multi_account_restored',
    })
    return true
end
