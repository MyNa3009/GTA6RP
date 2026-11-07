-- core_lib auf dem Server: Minigames, die der Server startet und auswertet.
-- Der Server merkt sich, wann er das Minigame geschickt hat. Kommt das Ergebnis schneller, als ein Mensch es schaffen
-- kann, zaehlt es als nicht geschafft und landet im Log. So kann ein Cheater nicht einfach "geschafft" melden,
-- ohne zu spielen. Wer etwas Wertvolles an ein Minigame haengt, nutzt immer diesen Weg.

local REQUIRED_CORE = '1.8.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Export', 'GetCallingResource', 'GetTime', 'Notify',
    'Print', 'SetInterval', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_lib: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Server-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    return
end

local CORE = 'core'
local CFG = Config.Lib.Minigames.Server
local KINDS = { skillcheck = true, lockpick = true, hack = true, wires = true }

local nextId = 0
local requests = {}   -- [id] = { source, kind, startedAt, resource, done, success }
local bySource = {}   -- [source] = id, hoechstens ein Minigame pro Spieler

local function log(entry)
    Platform.CallExport(CORE, 'Log', entry)
end

local function finish(id, success)
    local request = requests[id]
    if not request or request.done then
        return
    end
    request.done = true
    request.success = success == true
    if bySource[request.source] == id then
        bySource[request.source] = nil
    end
end

-- Startet ein Minigame beim Spieler. options wie im Client (Skillcheck: { difficulty, keys }).
-- Gibt die Nummer zurueck oder nil und einen Fehlercode. Ergebnis mit GetMinigameResult(id) oder lib.minigame (init.lua).
local function startMinigame(source, kind, options)
    source = tonumber(source)
    if not source or not KINDS[kind] then
        return nil, 'invalid_input'
    end
    if not Platform.CallExport(CORE, 'GetCharacterId', source) then
        return nil, 'no_character'
    end
    if bySource[source] then
        return nil, 'busy'
    end
    nextId = nextId + 1
    local id = nextId
    requests[id] = {
        source = source,
        kind = kind,
        startedAt = Platform.GetTime(),
        resource = Platform.GetCallingResource() or 'core_lib',
        done = false,
    }
    bySource[source] = id
    Network.SendToClient(source, 'core_lib:minigame', { id = id, kind = kind, options = type(options) == 'table' and options or {} })
    return id
end

-- nil, solange es laeuft. Danach true oder false (einmal abrufbar, dann vergessen).
local function getResult(id)
    local request = requests[tonumber(id)]
    if not request then
        return false
    end
    if not request.done then
        return nil
    end
    requests[tonumber(id)] = nil
    return request.success
end

-- Ergebnis vom Client. Nur fuer das eigene, laufende Minigame.
Network.RegisterCallback('lib_minigame_result', function(source, data)
    local id = tonumber(data.id)
    local request = id and requests[id]
    if not request or request.source ~= source or request.done then
        return { ok = false, error = 'not_active' }
    end
    local success = data.success == true
    local elapsed = Platform.GetTime() - request.startedAt
    local minimum = CFG.MinDurationMs[request.kind] or 0
    if success and elapsed < minimum then
        success = false
        log({
            category = 'security',
            action = 'minigame_too_fast',
            actor_account_id = Platform.CallExport(CORE, 'GetAccountId', source),
            account_id = Platform.CallExport(CORE, 'GetAccountId', source),
            character_id = Platform.CallExport(CORE, 'GetCharacterId', source),
            data = { kind = request.kind, elapsedMs = elapsed, minimumMs = minimum, resource = request.resource },
        })
    end
    finish(id, success)
    return { ok = true }
end)

-- Abgelaufene Anfragen und verlassene Spieler aufraeumen (zaehlen als nicht geschafft)
Platform.SetInterval(CFG.CleanupIntervalMs, function()
    local now = Platform.GetTime()
    for id, request in pairs(requests) do
        if not request.done and (now - request.startedAt > CFG.RequestTimeoutMs or not Platform.CallExport(CORE, 'GetCharacterId', request.source)) then
            finish(id, false)
        elseif request.done and now - request.startedAt > CFG.RequestTimeoutMs * 2 then
            -- Ergebnis wurde nie abgeholt
            requests[id] = nil
        end
    end
end)

Platform.Export('StartMinigame', startMinigame)
Platform.Export('GetMinigameResult', getResult)
Platform.Export('Notify', function(source, text, kind)
    Platform.Notify(source, text, kind)
end)
