-- Zentrales Logging der Core.
-- Jede Aenderung an Geld, Items, Accounts usw. ruft Core.Log auf.
-- Eintraege werden gesammelt und regelmaessig gebuendelt gespeichert.

Core = Core or {}

local COLUMNS = {
    'created_at',
    'actor_account_id',
    'account_id',
    'character_id',
    'category',
    'action',
    'amount',
    'balance_before',
    'balance_after',
    'target_account_id',
    'resource',
    'reason',
    'data',
}

local MAX_REASON_LENGTH = 255

local queue = {}
local flushing = false

local function buildInsert(batch)
    local rows, params, paramCount = {}, {}, 0

    for rowIndex, entry in ipairs(batch) do
        local placeholders = {}
        for columnIndex, column in ipairs(COLUMNS) do
            local value = entry[column]
            if value == nil then
                -- NULL direkt ins SQL, damit die Parameterliste keine Luecken hat
                placeholders[columnIndex] = 'NULL'
            else
                placeholders[columnIndex] = '?'
                paramCount = paramCount + 1
                params[paramCount] = value
            end
        end
        rows[rowIndex] = '(' .. table.concat(placeholders, ', ') .. ')'
    end

    local sql = ('INSERT INTO audit_log (%s) VALUES %s'):format(
        table.concat(COLUMNS, ', '),
        table.concat(rows, ', ')
    )
    return sql, params
end

local function requeue(batch)
    local free = Config.Log.MaxQueueSize - #queue
    if free <= 0 then
        Platform.Print('error', ('Log-Puffer voll, %d Eintraege verloren.'):format(#batch))
        return
    end

    local restored = {}
    for i = 1, math.min(#batch, free) do
        restored[#restored + 1] = batch[i]
    end
    for _, entry in ipairs(queue) do
        restored[#restored + 1] = entry
    end
    queue = restored
end

local function flush()
    if flushing or #queue == 0 then
        return
    end
    flushing = true

    local batch = queue
    queue = {}

    local sql, params = buildInsert(batch)
    local result = DB.Insert(sql, params)

    if result == nil then
        Platform.Print('warn', ('%d Log-Eintraege konnten nicht gespeichert werden, neuer Versuch spaeter.'):format(#batch))
        requeue(batch)
    end

    flushing = false
end

function Core.Log(entry)
    if type(entry) ~= 'table' or type(entry.category) ~= 'string' or type(entry.action) ~= 'string' then
        Platform.Print('warn', 'Core.Log ohne category oder action aufgerufen, Eintrag verworfen.')
        return
    end

    entry.created_at = entry.created_at or os.date('%Y-%m-%d %H:%M:%S')
    entry.resource = entry.resource or Platform.GetCallingResource()

    if type(entry.data) == 'table' then
        entry.data = Platform.JsonEncode(entry.data)
    end

    -- Spalte reason ist auf 255 Zeichen begrenzt
    if type(entry.reason) == 'string' and #entry.reason > MAX_REASON_LENGTH then
        entry.reason = entry.reason:sub(1, MAX_REASON_LENGTH)
    end

    queue[#queue + 1] = entry

    if #queue >= Config.Log.MaxBatchSize then
        Platform.Async(flush)
    end
end

Platform.SetInterval(Config.Log.FlushIntervalMs, flush)

-- Beim Stoppen der Core alles Uebrige ohne Warten wegschicken
Platform.OnResourceStop(function()
    if #queue == 0 then
        return
    end
    local sql, params = buildInsert(queue)
    queue = {}
    DB.Fire(sql, params)
end)
