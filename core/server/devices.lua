-- Geraete: Accountsharing und Multi-Accounts ueber den PC erkennen.
-- Bei jedem Login merkt sich die Core die Hardware-Tokens des PCs. Meldet sich ein Login
-- an einem PC an, von dem kein einziger Token bekannt ist, gibt es eine rote Warnung.
-- Gleiche Tokens bei verschiedenen Logins zaehlen als Multi-Account (Typ hardware).
-- IP-Adressen sind nur Zusatzinfo fuer Admins mit data.private und werden nach Config.Devices.IpRetentionDays geloescht.

Devices = {}
Devices.Ready = false

local SECONDS_PER_DAY = 86400
local MS_PER_SECOND = 1000
local CLEANUP_INTERVAL_MS = 6 * 60 * 60 * 1000 -- alle 6 Stunden alte IPs loeschen

local CREATE = {
    [[
    CREATE TABLE IF NOT EXISTS account_devices (
        account_id INT UNSIGNED NOT NULL,
        token      VARCHAR(128) NOT NULL,
        first_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (account_id, token),
        INDEX idx_devices_token (token)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS account_ips (
        account_id INT UNSIGNED NOT NULL,
        ip         VARCHAR(45) NOT NULL,
        first_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (account_id, ip),
        INDEX idx_ips_last_seen (last_seen)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
    CREATE TABLE IF NOT EXISTS device_alerts (
        id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        account_id   INT UNSIGNED NOT NULL,
        created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        ip           VARCHAR(45) NULL,        -- nur mit data.private sichtbar, wird mit den IPs geloescht
        ip_known     TINYINT(1) NOT NULL DEFAULT 0, -- IP war schon bekannt (z. B. gleicher Haushalt)
        dismissed_by INT UNSIGNED NULL,
        dismissed_at TIMESTAMP NULL DEFAULT NULL,
        INDEX idx_alerts_account (account_id, dismissed_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
}

local function cleanupIps()
    local days = Config.Devices.IpRetentionDays
    DB.Update('DELETE FROM account_ips WHERE last_seen < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? DAY)', { days })
    DB.Update('UPDATE device_alerts SET ip = NULL WHERE ip IS NOT NULL AND created_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL ? DAY)', { days })
end

DB.Ready(function()
    for _, sql in ipairs(CREATE) do
        if DB.Query(sql) == nil then
            Platform.Print('error', 'Geraete-Tabellen konnten nicht angelegt werden. Bitte 005_devices.sql ausfuehren.')
            return
        end
    end
    Devices.Ready = true
    cleanupIps()
end)

Platform.SetInterval(CLEANUP_INTERVAL_MS, function()
    if Devices.Ready then
        cleanupIps()
    end
end)

------------------------------------------------------------------------
-- Beim Login
------------------------------------------------------------------------

local function placeholders(count)
    return string.rep('?', count, ', ')
end

local function displayName(accountId)
    return DB.Scalar([[
        SELECT CONCAT(firstname, ' ', lastname) FROM characters
        WHERE account_id = ? AND deleted_at IS NULL
        ORDER BY last_played IS NULL, last_played DESC LIMIT 1
    ]], { accountId })
end

-- Tokens und IP speichern, ohne zu warnen (z. B. bei einem Login-Versuch trotz Ban)
function Devices.Remember(source, accountId)
    if not Devices.Ready or not Config.Devices.Enabled then
        return
    end
    for _, token in ipairs(Identity.GetTokens(source)) do
        DB.Update([[
            INSERT INTO account_devices (account_id, token) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE last_seen = CURRENT_TIMESTAMP
        ]], { accountId, token })
    end
    local ip = Identity.GetIp(source)
    if ip and Config.Devices.StoreIp then
        DB.Update([[
            INSERT INTO account_ips (account_id, ip) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE last_seen = CURRENT_TIMESTAMP
        ]], { accountId, ip })
    end
end

-- Nach jedem erfolgreichen Login und jeder Registrierung
function Devices.OnLogin(source, accountId)
    if not Devices.Ready or not Config.Devices.Enabled then
        return
    end
    local tokens = Identity.GetTokens(source)
    local ip = Identity.GetIp(source)

    if #tokens > 0 then
        local knownCount = DB.Scalar('SELECT COUNT(*) FROM account_devices WHERE account_id = ?', { accountId }) or 0
        local params = { accountId }
        for _, token in ipairs(tokens) do params[#params + 1] = token end
        local overlap = DB.Scalar(
            ('SELECT COUNT(*) FROM account_devices WHERE account_id = ? AND token IN (%s)'):format(placeholders(#tokens)),
            params
        ) or 0

        -- Login kennt schon Geraete, aber keins davon ist dieser PC: Accountsharing moeglich
        if tonumber(knownCount) > 0 and tonumber(overlap) == 0 then
            local ipKnown = ip ~= nil and DB.Scalar('SELECT 1 FROM account_ips WHERE account_id = ? AND ip = ?', { accountId, ip }) ~= nil
            local alertId = DB.Insert(
                'INSERT INTO device_alerts (account_id, ip, ip_known) VALUES (?, ?, ?)',
                DB.Args(accountId, Config.Devices.StoreIp and ip or nil, ipKnown and 1 or 0)
            )
            Core.Log({
                account_id = accountId,
                category = 'security',
                action = 'new_device',
                data = { alertId = alertId, ipKnown = ipKnown, name = Platform.GetPlayerName(source) },
            })
            local name = displayName(accountId)
            MultiAccount.NotifyAdmins(('Warnung: Login %d%s hat sich an einem neuen PC angemeldet (Accountsharing?).%s'):format(
                accountId, name and (' (' .. name .. ')') or '', ipKnown and ' Die IP war schon bekannt.' or ''))
        end

        -- Andere Logins, die schon an diesem PC waren
        if Config.Devices.HardwareMultiAccount then
            local others = DB.Query(
                ('SELECT DISTINCT account_id FROM account_devices WHERE account_id <> ? AND token IN (%s)'):format(placeholders(#tokens)),
                params
            ) or {}
            for _, row in ipairs(others) do
                MultiAccount.Record(accountId, row.account_id, 'hardware')
            end
        end
    end

    Devices.Remember(source, accountId)
end

------------------------------------------------------------------------
-- Fuer das Admin-Menue
------------------------------------------------------------------------

local function alertToClient(row, private)
    return {
        id = row.id,
        accountId = row.account_id,
        createdAt = row.created_at and tonumber(row.created_at) * MS_PER_SECOND or nil,
        ip = private and row.ip or nil,
        ipKnown = row.ip_known == 1 or row.ip_known == true,
        dismissedBy = row.dismissed_by,
        dismissedAt = row.dismissed_at and tonumber(row.dismissed_at) * MS_PER_SECOND or nil,
        active = row.dismissed_at == nil,
    }
end

local ALERT_FIELDS = [[
    id, account_id, ip, ip_known, dismissed_by,
    UNIX_TIMESTAMP(created_at) AS created_at, UNIX_TIMESTAMP(dismissed_at) AS dismissed_at
]]

-- Geraete-Infos fuer die Akte. private = Recht data.private (IPs sehen)
function Devices.ForAccount(accountId, private)
    if not Devices.Ready then
        return { known = false, alerts = {} }
    end
    local alerts = {}
    for i, row in ipairs(DB.Query('SELECT ' .. ALERT_FIELDS .. ' FROM device_alerts WHERE account_id = ? ORDER BY id DESC', { accountId }) or {}) do
        alerts[i] = alertToClient(row, private)
    end
    local tokenCount = tonumber(DB.Scalar('SELECT COUNT(*) FROM account_devices WHERE account_id = ?', { accountId })) or 0

    local ips = nil
    if private then
        ips = {}
        local rows = DB.Query([[
            SELECT ip, UNIX_TIMESTAMP(first_seen) AS first_seen, UNIX_TIMESTAMP(last_seen) AS last_seen
            FROM account_ips WHERE account_id = ? ORDER BY last_seen DESC
        ]], { accountId }) or {}
        for i, row in ipairs(rows) do
            ips[i] = {
                ip = row.ip,
                firstSeen = tonumber(row.first_seen) * MS_PER_SECOND,
                lastSeen = tonumber(row.last_seen) * MS_PER_SECOND,
            }
        end
    end

    return {
        known = tokenCount > 0,
        -- Jede Warnung steht fuer einen weiteren PC, dazu der erste
        deviceCount = tokenCount > 0 and (#alerts + 1) or 0,
        alerts = alerts,
        ips = ips,
        ipRetentionDays = Config.Devices.IpRetentionDays,
    }
end

-- Offene Warnungen aller Logins (fuer die Warnungen-Liste)
function Devices.ListActive(limit, private)
    if not Devices.Ready then return {} end
    local list = {}
    local rows = DB.Query('SELECT ' .. ALERT_FIELDS .. ' FROM device_alerts WHERE dismissed_at IS NULL ORDER BY id DESC LIMIT ?', { limit }) or {}
    for i, row in ipairs(rows) do
        list[i] = alertToClient(row, private)
    end
    return list
end

function Devices.CountActive()
    if not Devices.Ready then return 0 end
    return tonumber(DB.Scalar('SELECT COUNT(*) FROM device_alerts WHERE dismissed_at IS NULL')) or 0
end

-- [accountId] = true fuer Logins mit offener Geraete-Warnung
function Devices.ActiveFor(accountIds)
    local result = {}
    if not Devices.Ready or #accountIds == 0 then
        return result
    end
    local rows = DB.Query(
        ('SELECT DISTINCT account_id FROM device_alerts WHERE dismissed_at IS NULL AND account_id IN (%s)'):format(placeholders(#accountIds)),
        accountIds
    ) or {}
    for _, row in ipairs(rows) do
        result[row.account_id] = true
    end
    return result
end

function Devices.SetDismissed(accountId, alertId, dismissed, actorAccountId)
    if not Devices.Ready then return false, 'not_ready' end
    local changed
    if dismissed then
        changed = DB.Update(
            'UPDATE device_alerts SET dismissed_by = ?, dismissed_at = CURRENT_TIMESTAMP WHERE id = ? AND account_id = ? AND dismissed_at IS NULL',
            DB.Args(actorAccountId, alertId, accountId)
        )
    else
        changed = DB.Update(
            'UPDATE device_alerts SET dismissed_by = NULL, dismissed_at = NULL WHERE id = ? AND account_id = ?',
            { alertId, accountId }
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
        category = 'admin',
        action = dismissed and 'device_alert_dismissed' or 'device_alert_restored',
        data = { alertId = alertId },
    })
    return true
end
