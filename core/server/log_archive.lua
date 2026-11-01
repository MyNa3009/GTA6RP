-- Log-Archiv: Eintraege aus audit_log, die aelter als Config.Log.ArchiveAfterDays sind, wandern nachts in audit_log_archive.
-- So bleibt die Akte schnell, und nichts geht verloren. Admins koennen das Archiv in der Akte weiter durchsuchen.
-- Verschoben wird in kleinen Portionen mit Pause dazwischen, damit der Server nicht haengt.

LogArchive = { Ready = false, Table = 'audit_log_archive' }

local CONSOLE = 0
local CHECK_INTERVAL_MS = 10 * 60 * 1000 -- alle 10 Minuten nachsehen, ob es Zeit ist
local SECONDS_PER_DAY = 86400

DB.Ready(function()
    -- Gleiche Spalten und Indizes wie audit_log, damit die Akte das Archiv genauso schnell lesen kann
    if DB.Query('CREATE TABLE IF NOT EXISTS audit_log_archive LIKE audit_log') == nil then
        Platform.Print('error', 'Tabelle audit_log_archive konnte nicht angelegt werden. Bitte 009_log_archive.sql ausfuehren.')
        return
    end
    LogArchive.Ready = true
end)

local running = false

-- Verschiebt alles, was alt genug ist. Gibt die Anzahl verschobener Eintraege zurueck oder nil bei Fehler.
function LogArchive.Run(reason)
    local days = tonumber(Config.Log.ArchiveAfterDays)
    if not LogArchive.Ready or running or not days or days <= 0 then
        return 0
    end
    running = true

    -- Grenze einmal festlegen, damit Kopieren und Loeschen genau dieselben Zeilen meinen
    local cutoff = os.time() - math.floor(days) * SECONDS_PER_DAY
    local batchSize = math.floor(Config.Log.ArchiveBatchSize)
    local moved, failed = 0, false

    while true do
        local maxId = DB.Scalar(
            ('SELECT MAX(id) FROM (SELECT id FROM audit_log WHERE created_at < FROM_UNIXTIME(?) ORDER BY id LIMIT %d) AS batch'):format(batchSize),
            { cutoff }
        )
        if not maxId then
            break
        end
        local copied = DB.Update(
            'INSERT IGNORE INTO audit_log_archive SELECT * FROM audit_log WHERE id <= ? AND created_at < FROM_UNIXTIME(?)',
            { maxId, cutoff }
        )
        if copied == nil then
            failed = true
            break
        end
        -- Nur loeschen, was sicher im Archiv angekommen ist
        local deleted = DB.Update(
            'DELETE l FROM audit_log l JOIN audit_log_archive a ON a.id = l.id WHERE l.id <= ? AND l.created_at < FROM_UNIXTIME(?)',
            { maxId, cutoff }
        )
        if deleted == nil then
            failed = true
            break
        end
        moved = moved + deleted
        if deleted < batchSize then
            break
        end
        Platform.Wait(Config.Log.ArchivePauseMs)
    end

    running = false
    if failed then
        Platform.Print('error', ('Log-Archiv abgebrochen nach %d Eintraegen. Naechster Versuch beim naechsten Lauf.'):format(moved))
    elseif moved > 0 then
        Platform.Print('info', ('Log-Archiv: %d Eintraege aelter als %d Tage verschoben.'):format(moved, days))
    end
    if moved > 0 or failed then
        Core.Log({ category = 'admin', action = 'log_archived', reason = reason, data = { count = moved, days = days, failed = failed or nil } })
    end
    return not failed and moved or nil
end

-- Einmal pro Nacht zur eingestellten Stunde (Serverzeit)
local lastRunDay = nil

Platform.SetInterval(CHECK_INTERVAL_MS, function()
    if not LogArchive.Ready then
        return
    end
    local today = os.date('%Y-%m-%d')
    if lastRunDay ~= today and tonumber(os.date('%H')) == Config.Log.ArchiveHour then
        lastRunDay = today
        LogArchive.Run('Nachtlauf')
    end
end)

-- logarchive (nur Konsole): sofort laufen lassen, z. B. nach einem Update
Platform.RegisterCommand('logarchive', function(source)
    if source ~= CONSOLE then
        Platform.Notify(source, 'Das geht nur in der Server-Konsole.', 'error')
        return
    end
    local moved = LogArchive.Run('Konsole')
    if moved == nil then
        Platform.Print('error', 'Log-Archiv fehlgeschlagen, Details stehen oben.')
    else
        Platform.Print('ok', ('Log-Archiv fertig: %d Eintraege verschoben.'):format(moved))
    end
end)
