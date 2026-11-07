-- Minigames: Skillcheck, Schloss knacken, Hacken, Kabel verbinden. Ergebnis true (geschafft) oder false.
-- Das Ergebnis aus dem Client ist nur Komfort. Haengt etwas Wertvolles daran, startet der Server das Minigame
-- (exports.core_lib:StartMinigame) und prueft selbst Zeit und Distanz.
if LibDisabled then return end

Minigames = {}

local CFG = Config.Lib.Minigames
local UI = 'game'

-- Grenzen fuer Optionen anderer Scripts: { min, max }
local LIMITS = {
    lockpick = { pins = { 3, 8 }, attempts = { 1, 10 }, zone = { 0.06, 0.4 }, speed = { 0.3, 3 }, timeLimitMs = { 3000, 300000 } },
    hack     = { grid = { 3, 6 }, startLength = { 2, 8 }, rounds = { 1, 6 }, stepMs = { 250, 1500 }, timeLimitMs = { 3000, 120000 } },
    wires    = { count = { 3, 6 }, timeLimitMs = { 3000, 120000 } },
    skill    = { area = { 10, 120 }, speed = { 0.2, 2.5 } },
}
-- Minigames mit Maus (Raster, Kabel). Die anderen gehen nur mit Tasten, dann bleibt der Mauszeiger weg.
local NEEDS_CURSOR = { hack = true, wires = true }
local KEY_PATTERN = '^[%w]$'

local active = nil   -- { id, kind }

local function clamp(value, range, fallback)
    value = tonumber(value)
    if not value or value ~= value then
        return fallback
    end
    return math.max(range[1], math.min(range[2], value))
end

local function readKeys(keys)
    local list = {}
    if type(keys) == 'table' then
        for _, key in ipairs(keys) do
            if type(key) == 'string' and key:match(KEY_PATTERN) then
                list[#list + 1] = key:upper()
            end
        end
    end
    if #list == 0 then
        for _, key in ipairs(CFG.SkillCheck.Keys) do
            list[#list + 1] = key:upper()
        end
    end
    return list
end

-- difficulty: 'easy' | 'medium' | 'hard' | { area, speed } oder eine Liste davon (mehrere Runden)
local function readStages(difficulty, keys)
    local list = difficulty
    if type(difficulty) ~= 'table' or difficulty.area or difficulty.speed then
        list = { difficulty or 'medium' }
    end
    local stages = {}
    for i = 1, math.min(#list, CFG.SkillCheck.MaxStages) do
        local entry = list[i]
        local stage
        if type(entry) == 'string' then
            stage = CFG.SkillCheck.Difficulties[entry]
        elseif type(entry) == 'table' then
            stage = {
                area = clamp(entry.area, LIMITS.skill.area, CFG.SkillCheck.Difficulties.medium.area),
                speed = clamp(entry.speed, LIMITS.skill.speed, CFG.SkillCheck.Difficulties.medium.speed),
            }
        end
        if not stage then
            return nil
        end
        stages[#stages + 1] = { area = stage.area, speed = stage.speed, key = keys[math.random(#keys)] }
    end
    return #stages > 0 and stages or nil
end

local function readOptions(kind, options)
    options = type(options) == 'table' and options or {}
    if kind == 'lockpick' then
        local c, l = CFG.Lockpick, LIMITS.lockpick
        return {
            pins = math.floor(clamp(options.pins, l.pins, c.Pins)),
            attempts = math.floor(clamp(options.attempts, l.attempts, c.Attempts)),
            zone = clamp(options.zone, l.zone, c.ZoneSize),
            speed = clamp(options.speed, l.speed, c.Speed),
            timeLimitMs = math.floor(clamp(options.timeLimitMs, l.timeLimitMs, c.TimeLimitMs)),
        }
    elseif kind == 'hack' then
        local c, l = CFG.Hack, LIMITS.hack
        return {
            grid = math.floor(clamp(options.grid, l.grid, c.GridSize)),
            startLength = math.floor(clamp(options.startLength, l.startLength, c.StartLength)),
            rounds = math.floor(clamp(options.rounds, l.rounds, c.Rounds)),
            stepMs = math.floor(clamp(options.stepMs, l.stepMs, c.StepMs)),
            timeLimitMs = math.floor(clamp(options.timeLimitMs, l.timeLimitMs, c.TimeLimitMs)),
        }
    elseif kind == 'wires' then
        local c, l = CFG.Wires, LIMITS.wires
        return {
            count = math.floor(clamp(options.count, l.count, c.Count)),
            timeLimitMs = math.floor(clamp(options.timeLimitMs, l.timeLimitMs, c.TimeLimitMs)),
        }
    elseif kind == 'skillcheck' then
        local stages = readStages(options.difficulty, readKeys(options.keys))
        return stages and { stages = stages } or nil
    end
    return nil
end

-- kind: 'skillcheck' | 'lockpick' | 'hack' | 'wires'. Gibt die Nummer zurueck oder nil und einen Fehlercode.
function Minigames.Start(kind, options)
    if active then
        return nil, 'busy'
    end
    if Platform.IsOwnPedDead() then
        return nil, 'dead'
    end
    local data = readOptions(kind, options)
    if not data then
        return nil, 'invalid_input'
    end
    local id = Lib.NewRequest()
    active = { id = id, kind = kind }
    Ui.Send(UI, 'game_open', { id = id, kind = kind, options = data })
    Ui.Focus(UI, true, NEEDS_CURSOR[kind] == true)
    return id
end

local function finish(success)
    local entry = active
    if not entry then
        return
    end
    active = nil
    Ui.Focus(UI, false)
    Ui.Send(UI, 'game_close', {})
    Lib.Finish(entry.id, success == true)
end

-- Laufendes Minigame abbrechen (Ergebnis false)
function Minigames.Cancel()
    if not active then
        return false
    end
    finish(false)
    return true
end

function Minigames.IsActive()
    return active ~= nil
end

Platform.UiOn('game_result', function(data)
    if not active or tonumber(data.id) ~= active.id then
        return { ok = false, error = 'not_active' }
    end
    finish(data.success == true)
    return { ok = true }
end)

-- Wer bewusstlos wird, verliert das Minigame
local DEAD_CHECK_MS = 500
Platform.Async(function()
    while true do
        Platform.Wait(DEAD_CHECK_MS)
        if active and Platform.IsOwnPedDead() then
            finish(false)
        end
    end
end)

------------------------------------------------------------------------
-- Vom Server gestartet (exports.core_lib:StartMinigame)
------------------------------------------------------------------------

Network.On('core_lib:minigame', function(data)
    if type(data) ~= 'table' or type(data.id) ~= 'number' then
        return
    end
    Platform.Async(function()
        local id = Minigames.Start(data.kind, data.options)
        local success = id and Lib.Await(id) or false
        Network.Call('lib_minigame_result', { id = data.id, success = success == true })
    end)
end)

Platform.Export('StartSkillCheck', function(difficulty, keys)
    return Minigames.Start('skillcheck', { difficulty = difficulty, keys = keys })
end)
Platform.Export('StartLockpick', function(options) return Minigames.Start('lockpick', options) end)
Platform.Export('StartHack', function(options) return Minigames.Start('hack', options) end)
Platform.Export('StartWires', function(options) return Minigames.Start('wires', options) end)
Platform.Export('CancelMinigame', Minigames.Cancel)
Platform.Export('IsMinigameActive', Minigames.IsActive)
