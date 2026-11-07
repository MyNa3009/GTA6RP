-- Symptome der eigenen Krankheiten: Husten, Kopfschmerzen, Uebelkeit, Erbrechen, verschwommene Sicht, Wackeln,
-- kurze Blackouts, Stolpern, Minimap weg, Vergesslichkeit, langsamer Gang, kein Rennen.
-- Welche Symptome in welchem Stadium und wie oft, steht in der Config. Bewusstlos passiert nichts.

if EmsDisabled then
    return
end

local CFG = Config.Ems
local DATA = SymptomData
local CHECK_MS = 1000
local JITTER = 0.3                  -- every +/- 30 Prozent, damit es nicht wie ein Takt wirkt
local MS_PER_SECOND = 1000

local MESSAGES = {
    cough    = 'Du musst husten.',
    sneeze   = 'Hatschi. Die Nase läuft.',
    headache = 'Dir dröhnt der Kopf.',
    nausea   = 'Dir ist übel.',
    vomit    = 'Dir wird schlecht.',
    blackout = 'Dir wird kurz schwarz vor Augen.',
    stumble  = 'Dir wird schwindelig.',
    forget   = { 'Wo wolltest du gerade hin?', 'Was wolltest du hier nochmal?', 'Du hast kurz vergessen, was du tun wolltest.' },
    minimap  = 'Du weißt gerade nicht mehr, wo du bist.',
}

local timers = {}       -- [krankheit .. stadium .. index] = naechster Zeitpunkt
local continuous = { nosprint = false, walk = nil }
local currentWalk = nil
local running = {}      -- laufende Effekte, die wieder aufhoeren muessen

local function now()
    return Platform.GetTime()
end

local function nextIn(every)
    local spread = every * JITTER
    return now() + math.floor((every + (math.random() * 2 - 1) * spread) * MS_PER_SECOND)
end

local function message(kind)
    local text = MESSAGES[kind]
    if type(text) == 'table' then
        text = text[math.random(#text)]
    end
    if text then
        EmsClient.Notify(text, 'warning')
    end
end

local function anim(kind)
    local entry = DATA.anims[kind]
    if entry and not Platform.IsOwnPedInVehicle() then
        Platform.PlayOwnAnim(entry.dict, entry.clip, { loop = false, upperBody = kind ~= 'vomit', controllable = kind ~= 'vomit', durationMs = entry.ms })
    end
end

-- Effekt fuer eine Weile an, danach wieder aus. Gleicher Effekt laeuft nicht doppelt.
local function forSeconds(key, seconds, on, off)
    if running[key] then
        return
    end
    running[key] = true
    on()
    Platform.Async(function()
        Platform.Wait(math.floor(seconds * MS_PER_SECOND))
        off()
        running[key] = nil
    end)
end

local ACTIONS = {
    cough = function() anim('cough') message('cough') end,
    sneeze = function() anim('sneeze') message('sneeze') end,
    headache = function() anim('headache') message('headache') end,
    nausea = function() message('nausea') end,
    vomit = function() anim('vomit') message('vomit') end,
    blur = function(symptom)
        forSeconds('blur', symptom.seconds or 5, function() Platform.SetScreenEffect(DATA.effects.blur, true) end,
            function() Platform.SetScreenEffect(DATA.effects.blur, false) end)
    end,
    shake = function(symptom)
        forSeconds('shake', symptom.seconds or 6, function() Platform.ShakeCamera(DATA.shake, symptom.intensity or 0.3) end,
            function() Platform.ShakeCamera(nil) end)
    end,
    blackout = function(symptom)
        if running.blackout then
            return
        end
        running.blackout = true
        message('blackout')
        Platform.Async(function()
            Platform.Blackout(DATA.fadeMs, symptom.ms or 1000)
            running.blackout = nil
        end)
    end,
    stumble = function(symptom)
        if Platform.RagdollOwnPed(symptom.ms or 2000) then
            message('stumble')
        end
    end,
    minimap = function(symptom)
        message('minimap')
        forSeconds('minimap', symptom.seconds or 20, function() Platform.SetMinimapHidden(true) end,
            function() Platform.SetMinimapHidden(false) end)
    end,
    forget = function() message('forget') end,
}

local function setWalk(style)
    if style == currentWalk then
        return
    end
    currentWalk = style
    Platform.SetOwnWalkStyle(style and DATA.walks[style] or nil)
end

-- Alles aus (geheilt, bewusstlos, Resource gestoppt)
local function clearAll()
    setWalk(nil)
    continuous.nosprint = false
    Platform.ShakeCamera(nil)
    Platform.SetScreenEffect(DATA.effects.blur, false)
    Platform.SetMinimapHidden(false)
end

-- Ein Durchgang pro Sekunde: faellige Symptome ausloesen, durchgehende setzen
Platform.Async(function()
    while true do
        Platform.Wait(CHECK_MS)
        local list = EmsClient.diseases
        if #list == 0 or Platform.IsOwnPedDead() then
            if currentWalk or continuous.nosprint then
                clearAll()
            end
        else
            local walk, nosprint = nil, false
            local seen = {}
            for _, entry in ipairs(list) do
                local def = CFG.Diseases[entry.disease]
                local symptoms = def and def.symptoms and def.symptoms[entry.stage] or {}
                for index, symptom in ipairs(symptoms) do
                    if symptom.kind == 'nosprint' then
                        nosprint = true
                    elseif symptom.kind == 'walk' then
                        walk = symptom.style
                    elseif symptom.every and ACTIONS[symptom.kind] then
                        local key = ('%s:%d:%d'):format(entry.disease, entry.stage, index)
                        seen[key] = true
                        if not timers[key] then
                            timers[key] = nextIn(symptom.every)
                        elseif now() >= timers[key] then
                            timers[key] = nextIn(symptom.every)
                            ACTIONS[symptom.kind](symptom)
                        end
                    end
                end
            end
            for key in pairs(timers) do
                if not seen[key] then
                    timers[key] = nil
                end
            end
            setWalk(walk)
            continuous.nosprint = nosprint
        end
    end
end)

-- Rennen sperren braucht jeden Frame, laeuft nur solange noetig
local SPRINT_GROUPS = { sprint = true }
Platform.Async(function()
    while true do
        if continuous.nosprint then
            Platform.DisableActionsThisFrame(SPRINT_GROUPS)
            Platform.Wait(0)
        else
            Platform.Wait(CHECK_MS)
        end
    end
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == Platform.GetResourceName() then
        clearAll()
    end
end)
