-- Anrufe: klingeln, annehmen, auflegen, Anrufliste. Der Stand eines Gespraechs lebt im Speicher des Servers,
-- die Anrufliste in der Datenbank. Die Sprache schaltet der Client ueber die Bridge (Platform.SetCallPartner).

if PhoneDisabled then
    return
end

Calls = {}

local CFG = Config.Phone
local VOICE_CHANNEL_BASE = 10000   -- Sprachkanal eines Gespraechs = Basis + laufende Nummer
local SECOND_MS = 1000

local calls = {}    -- [id] = { id, from, to (source), fromId, toId, fromNumber, toNumber, state = 'ringing' | 'active', answeredAt }
local callOf = {}   -- [source] = id
local nextId = 0

local function addLog(ownerId, otherNumber, direction, status, seconds)
    DB.Insert('INSERT INTO phone_calls (owner_id, other_number, direction, status, seconds, seen) VALUES (?, ?, ?, ?, ?, ?)',
        { ownerId, otherNumber, direction, status, seconds or 0, (direction == 'in' and status == 'missed') and 0 or 1 })
end

-- Stand des Gespraechs aus Sicht von source, fuer die UI. nil, wenn keins laeuft.
function Calls.StateOf(source)
    local call = calls[callOf[source] or 0]
    if not call then
        return nil
    end
    local caller = call.from == source
    local state = { id = call.id, number = caller and call.toNumber or call.fromNumber }
    if call.state == 'active' then
        state.state = 'active'
        state.seconds = os.time() - call.answeredAt
        state.partner = caller and call.to or call.from
        state.channel = VOICE_CHANNEL_BASE + call.id
    else
        state.state = caller and 'dialing' or 'incoming'
    end
    return state
end

local function push(call, ended)
    for _, side in ipairs({ { call.from, call.fromId }, { call.to, call.toId } }) do
        Phone.Push(side[2], { type = 'call', call = not ended and Calls.StateOf(side[1]) or nil, ended = ended })
    end
end

-- Gespraech beenden. reason: declined, cancelled, timeout, ended, left
local function finish(call, reason)
    if not calls[call.id] then
        return
    end
    local seconds = call.state == 'active' and (os.time() - call.answeredAt) or 0
    calls[call.id] = nil
    callOf[call.from], callOf[call.to] = nil, nil
    if call.state == 'active' then
        addLog(call.fromId, call.toNumber, 'out', 'answered', seconds)
        addLog(call.toId, call.fromNumber, 'in', 'answered', seconds)
        Phone.Log({ character_id = call.fromId, action = 'call', data = { otherNumber = call.toNumber, target = call.toId, seconds = seconds, status = 'answered' } })
    elseif reason == 'declined' then
        addLog(call.fromId, call.toNumber, 'out', 'declined')
        addLog(call.toId, call.fromNumber, 'in', 'declined')
    else
        addLog(call.fromId, call.toNumber, 'out', 'missed')
        addLog(call.toId, call.fromNumber, 'in', 'missed')
    end
    push(call, { reason = reason, seconds = seconds })
end

Phone.Register('phone_call_start', { write = true }, function(source, data, ctx)
    local sim = Numbers.Get(ctx.characterId)
    if not sim then
        return { ok = false, error = 'not_found' }
    end
    if callOf[source] then
        return { ok = false, error = 'in_call' }
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
    local targetId = Numbers.Owner(number)
    if not targetId then
        return { ok = false, error = 'unknown_number' }
    end
    local target = Phone.SourceOf(targetId)
    local targetSim = Numbers.Get(targetId)
    -- Nicht erreichbar: offline, Handy nicht dabei, Flugmodus oder bewusstlos. Der Anruf steht trotzdem als verpasst da.
    if not target or not targetSim or targetSim.airplane or not Phone.HasDevice(targetId)
        or (not CFG.AllowWhenDead and Phone.Core('IsDead', target) == true) then
        addLog(ctx.characterId, number, 'out', 'unreachable')
        addLog(targetId, sim.number, 'in', 'missed')
        return { ok = false, error = 'unreachable' }
    end
    if callOf[target] then
        addLog(ctx.characterId, number, 'out', 'busy')
        addLog(targetId, sim.number, 'in', 'missed')
        Phone.Push(targetId, { type = 'missed', number = sim.number, name = Numbers.ContactName(targetId, sim.number), silent = targetSim.silent })
        return { ok = false, error = 'line_busy' }
    end

    nextId = nextId + 1
    local call = { id = nextId, from = source, to = target, fromId = ctx.characterId, toId = targetId,
        fromNumber = sim.number, toNumber = number, state = 'ringing' }
    calls[call.id] = call
    callOf[source], callOf[target] = call.id, call.id
    local incoming = Calls.StateOf(target)
    incoming.silent = targetSim.silent
    incoming.name = Numbers.ContactName(targetId, sim.number)
    Phone.Push(targetId, { type = 'call', call = incoming })

    -- Niemand geht ran: nach der Klingelzeit ist der Anruf verpasst
    Platform.Async(function()
        Platform.Wait(CFG.RingSeconds * SECOND_MS)
        if calls[call.id] == call and call.state == 'ringing' then
            finish(call, 'timeout')
        end
    end)
    return { ok = true, data = { call = Calls.StateOf(source) } }
end)

Phone.Register('phone_call_answer', { write = true }, function(source)
    local call = calls[callOf[source] or 0]
    if not call or call.to ~= source or call.state ~= 'ringing' then
        return { ok = false, error = 'no_call' }
    end
    call.state = 'active'
    call.answeredAt = os.time()
    push(call)
    return { ok = true, data = { call = Calls.StateOf(source) } }
end)

-- Auflegen, ablehnen oder Anruf abbrechen. Geht immer, auch bewusstlos oder ohne Handy.
Network.RegisterCallback('phone_call_end', function(source)
    local call = calls[callOf[source] or 0]
    if not call then
        return { ok = false, error = 'no_call' }
    end
    local reason = call.state == 'active' and 'ended' or (call.to == source and 'declined' or 'cancelled')
    finish(call, reason)
    return { ok = true }
end)

function Phone.OnUnloaded(source)
    local call = calls[callOf[source] or 0]
    if call then
        finish(call, 'left')
    end
    Phone.ForgetSource(source)
end

------------------------------------------------------------------------
-- Anrufliste
------------------------------------------------------------------------

function Calls.List(characterId)
    local list = {}
    for _, row in ipairs(DB.Query("SELECT id, other_number, direction, status, seconds, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at FROM phone_calls WHERE owner_id = ? ORDER BY id DESC LIMIT ?",
        { characterId, CFG.CallsShown }) or {}) do
        list[#list + 1] = { id = row.id, number = row.other_number, direction = row.direction, status = row.status, seconds = tonumber(row.seconds) or 0, at = row.at }
    end
    return list
end

-- Verpasste Anrufe, die noch nicht gesehen wurden
function Calls.Missed(characterId)
    return tonumber(DB.Scalar('SELECT COUNT(*) FROM phone_calls WHERE owner_id = ? AND seen = 0', { characterId })) or 0
end

Phone.Register('phone_calls', {}, function(source, data, ctx)
    return { ok = true, data = { calls = Calls.List(ctx.characterId), missed = Calls.Missed(ctx.characterId) } }
end)

-- Anrufliste angesehen: Zaehler der verpassten Anrufe zuruecksetzen
Phone.Register('phone_calls_seen', { write = true }, function(source, data, ctx)
    DB.Update('UPDATE phone_calls SET seen = 1 WHERE owner_id = ? AND seen = 0', { ctx.characterId })
    return { ok = true, data = { missed = 0 } }
end)
