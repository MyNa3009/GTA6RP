-- Datenbank-Bridge fuer oxmysql.
-- Nur diese Datei kennt oxmysql. Alle anderen Teile der Core benutzen DB.*

DB = {}

-- Fuer Parameter, die nil sein koennen: DB.Args(a, b, c).
-- Lua-Listen mit Luecken kommen bei oxmysql nicht sicher an, darum setzt die Bridge fuer nil direkt NULL ins SQL.
-- Nur fuer Werte in INSERT und SET benutzen, "WHERE x = NULL" trifft nie.
function DB.Args(...)
    return table.pack(...)
end

local function normalize(sql, params)
    if type(params) ~= 'table' or params.n == nil then
        return sql, params or {}
    end
    local values, index = {}, 0
    local rewritten = sql:gsub('%?', function()
        index = index + 1
        local value = params[index]
        if value == nil then
            return 'NULL'
        end
        values[#values + 1] = value
        return '?'
    end)
    return rewritten, values
end

local function run(method, sql, params)
    sql, params = normalize(sql, params)
    local ok, result = pcall(method, sql, params)
    if not ok then
        Platform.Print('error', ('Datenbankfehler: %s\nSQL: %s'):format(tostring(result), sql))
        return nil, result
    end
    return result
end

-- Alle Zeilen als Liste
function DB.Query(sql, params)
    return run(MySQL.query.await, sql, params)
end

-- Erste Zeile oder nil
function DB.Single(sql, params)
    return run(MySQL.single.await, sql, params)
end

-- Erster Wert der ersten Zeile oder nil
function DB.Scalar(sql, params)
    return run(MySQL.scalar.await, sql, params)
end

-- Gibt die neue ID zurueck
function DB.Insert(sql, params)
    return run(MySQL.insert.await, sql, params)
end

-- Gibt die Anzahl geaenderter Zeilen zurueck
function DB.Update(sql, params)
    return run(MySQL.update.await, sql, params)
end

-- Ohne Warten, z. B. beim Herunterfahren
function DB.Fire(sql, params)
    MySQL.query(sql, params or {})
end

function DB.Ready(fn)
    MySQL.ready(fn)
end
