-- Nachrichten: Chats zwischen zwei Nummern, auch wenn der Empfaenger offline ist. Dazu Standort senden.
-- Jede Nachricht steht beim Absender und beim Empfaenger. Loescht jemand einen Chat, verschwindet nur seine
-- Ansicht, Admins sehen sie weiter.

if PhoneDisabled then
    return
end

Messages = {}

local CFG = Config.Phone
local LOCATION_TEXT = 'Standort'
local SENDER_MAX = 12
local TIME = "DATE_FORMAT(created_at, '%Y-%m-%d %H:%i')"

local lastSent = {}   -- [source] = Zeitpunkt der letzten Nachricht (ms)

local function flag(value)
    return value == 1 or value == true
end

function Messages.Unread(characterId)
    return tonumber(DB.Scalar("SELECT COUNT(*) FROM phone_messages WHERE owner_id = ? AND direction = 'in' AND read_at IS NULL AND hidden = 0", { characterId })) or 0
end

-- Liste der Chats, neuester zuerst: { number, text, kind, direction, at, unread, hidden? }. Zweiter Wert: ungelesene insgesamt.
-- admin: auch geloeschte Chats
function Messages.Threads(characterId, admin)
    local visible = admin and '' or ' AND hidden = 0'
    local rows = DB.Query(([[
        SELECT m.other_number, m.direction, m.kind, m.text, m.hidden, DATE_FORMAT(m.created_at, '%%Y-%%m-%%d %%H:%%i') AS at, t.unread
        FROM phone_messages m
        JOIN (SELECT MAX(id) AS last, SUM(direction = 'in' AND read_at IS NULL) AS unread
              FROM phone_messages WHERE owner_id = ?%s GROUP BY other_number) t ON m.id = t.last
        ORDER BY m.id DESC LIMIT ?]]):format(visible), { characterId, CFG.ThreadsShown }) or {}
    local list, total = {}, 0
    for _, row in ipairs(rows) do
        local unread = tonumber(row.unread) or 0
        total = total + unread
        list[#list + 1] = { number = row.other_number, text = row.text, kind = row.kind, direction = row.direction, at = row.at,
            unread = unread, hidden = flag(row.hidden) or nil }
    end
    return list, total
end

local function publicMessage(row)
    return { id = row.id, direction = row.direction, kind = row.kind, text = row.text, at = row.at,
        x = row.kind == 'location' and tonumber(row.x) or nil, y = row.kind == 'location' and tonumber(row.y) or nil,
        hidden = flag(row.hidden) or nil }
end

-- Absender eines Chats: eine Nummer oder der Name eines Dienstes (z. B. "Bank", kommt aus SendServiceMessage)
local function threadKey(value)
    local number = Numbers.Normalize(value)
    if number then
        return number
    end
    if type(value) == 'string' and #value <= SENDER_MAX and value:match('^[%a][%w ]*$') then
        return value
    end
    return nil
end

-- Chat mit einer Nummer, aelteste zuerst. data: { number, before? (id, fuer aeltere Seiten) }
Phone.Register('phone_thread', {}, function(source, data, ctx)
    local number = threadKey(data.number)
    if not number then
        return { ok = false, error = 'invalid_number' }
    end
    local sql = 'SELECT id, direction, kind, text, x, y, hidden, ' .. TIME .. ' AS at FROM phone_messages WHERE owner_id = ? AND other_number = ?'
    local args = { ctx.characterId, number }
    if not ctx.admin then
        sql = sql .. ' AND hidden = 0'
    end
    local before = tonumber(data.before)
    if before then
        sql = sql .. ' AND id < ?'
        args[#args + 1] = math.floor(before)
    end
    args[#args + 1] = CFG.ThreadPage + 1
    local rows = DB.Query(sql .. ' ORDER BY id DESC LIMIT ?', args) or {}
    local messages = {}
    for i = math.min(#rows, CFG.ThreadPage), 1, -1 do
        messages[#messages + 1] = publicMessage(rows[i])
    end
    if not ctx.admin then
        DB.Update("UPDATE phone_messages SET read_at = NOW() WHERE owner_id = ? AND other_number = ? AND direction = 'in' AND read_at IS NULL", { ctx.characterId, number })
    end
    return { ok = true, data = { number = number, messages = messages, more = #rows > CFG.ThreadPage, unread = Messages.Unread(ctx.characterId) } }
end)

-- Nachricht speichern (beide Ansichten) und dem Empfaenger Bescheid geben. Gibt die Zeile des Absenders zurueck.
local function deliver(fromId, fromNumber, toId, toNumber, kind, text, pos)
    local x, y = pos and pos.x or nil, pos and pos.y or nil
    local id = DB.Insert("INSERT INTO phone_messages (owner_id, other_number, direction, kind, text, x, y, read_at) VALUES (?, ?, 'out', ?, ?, ?, ?, NOW())",
        DB.Args(fromId, toNumber, kind, text, x, y))
    DB.Insert("INSERT INTO phone_messages (owner_id, other_number, direction, kind, text, x, y) VALUES (?, ?, 'in', ?, ?, ?, ?)",
        DB.Args(toId, fromNumber, kind, text, x, y))
    -- Bescheid nur, wenn das Handy dabei und nicht im Flugmodus ist. Die Nachricht wartet sonst im Chat.
    local sim = Numbers.Get(toId)
    if Phone.SourceOf(toId) and sim and not sim.airplane and Phone.HasDevice(toId) then
        Phone.Push(toId, { type = 'message', number = fromNumber, name = Numbers.ContactName(toId, fromNumber), kind = kind, text = text, silent = sim.silent })
    end
    return id
end

-- data: { number, text } oder { number, location = true } (Standort nimmt der Server selbst)
Phone.Register('phone_message_send', { write = true }, function(source, data, ctx)
    local sim = Numbers.Get(ctx.characterId)
    if not sim then
        return { ok = false, error = 'not_found' }
    end
    if sim.airplane then
        return { ok = false, error = 'airplane' }
    end
    local number = Numbers.Normalize(data.number)
    if not number then
        return { ok = false, error = 'invalid_number' }
    end
    if number == sim.number then
        return { ok = false, error = 'own_number' }
    end
    local kind, text, pos = 'text', Phone.Text(data.text, CFG.MessageMax), nil
    if data.location == true then
        pos = Platform.GetPlayerPosition(source)
        if not pos then
            return { ok = false, error = 'server_error' }
        end
        kind, text = 'location', LOCATION_TEXT
    elseif not text then
        return { ok = false, error = 'invalid_text' }
    end
    local now = Platform.GetTime()
    if lastSent[source] and now - lastSent[source] < CFG.MessageCooldownMs then
        return { ok = false, error = 'too_fast' }
    end
    local target = Numbers.Owner(number)
    if not target then
        return { ok = false, error = 'unknown_number' }
    end
    lastSent[source] = now
    local id = deliver(ctx.characterId, sim.number, target, number, kind, text, pos)
    local row = DB.Single('SELECT id, direction, kind, text, x, y, hidden, ' .. TIME .. ' AS at FROM phone_messages WHERE id = ?', { id })
    return { ok = true, data = { number = number, message = row and publicMessage(row) or nil } }
end)

-- Chat loeschen: nur die eigene Ansicht, fuer Admins bleibt er sichtbar
Phone.Register('phone_thread_delete', { write = true }, function(source, data, ctx)
    local number = threadKey(data.number)
    if not number then
        return { ok = false, error = 'invalid_number' }
    end
    local count = DB.Update('UPDATE phone_messages SET hidden = 1, read_at = COALESCE(read_at, NOW()) WHERE owner_id = ? AND other_number = ? AND hidden = 0', { ctx.characterId, number }) or 0
    if count > 0 then
        Phone.Log({ character_id = ctx.characterId, action = 'thread_delete', data = { otherNumber = number, count = count } })
    end
    local threads, unread = Messages.Threads(ctx.characterId, false)
    return { ok = true, data = { threads = threads, unread = unread } }
end)

function Phone.ForgetSource(source)
    lastSent[source] = nil
end

------------------------------------------------------------------------
-- Fuer andere Scripts
------------------------------------------------------------------------

-- Nachricht eines Dienstes an einen Charakter, z. B. exports.core_phone:SendServiceMessage(17, 'Bank', 'Deine Rechnung ist faellig.')
-- sender: kurzer Name aus Buchstaben (hoechstens 12 Zeichen), darauf kann man nicht antworten. Gibt true oder false zurueck.
Platform.Export('SendServiceMessage', function(characterId, sender, text)
    characterId = tonumber(characterId)
    sender = type(sender) == 'string' and threadKey(sender) or nil
    text = Phone.Text(text, CFG.MessageMax)
    if not characterId or not sender or Numbers.Normalize(sender) or not text or not Numbers.Get(characterId) then
        return false
    end
    DB.Insert("INSERT INTO phone_messages (owner_id, other_number, direction, kind, text) VALUES (?, ?, 'in', 'text', ?)", { characterId, sender, text })
    local sim = Numbers.Get(characterId)
    if Phone.SourceOf(characterId) and not sim.airplane and Phone.HasDevice(characterId) then
        Phone.Push(characterId, { type = 'message', number = sender, kind = 'text', text = text, silent = sim.silent })
    end
    return true
end)
