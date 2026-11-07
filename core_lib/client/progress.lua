-- Fortschrittsbalken und -kreis: Zeit laeuft, Animation und Prop am Ped, Steuerung gesperrt, mit X abbrechen.
-- Ergebnis: true (fertig) oder false (abgebrochen, bewusstlos, Script hat abgebrochen).
if LibDisabled then return end

Progress = {}

local CFG = Config.Lib.Progress
local UI = 'progress'
local STYLES = { bar = true, circle = true }
local MAX_PROPS = 2
local DISABLE_KEYS = { 'move', 'car', 'combat', 'mouse' }

local active = nil   -- { id, endsAt, canCancel, useWhileDead, disable, anim, props, cancelled }

local function cleanup(entry)
    if entry.anim then
        if entry.anim.scenario then
            Platform.ClearOwnTasks()
        else
            Platform.StopOwnAnim(entry.anim.dict, entry.anim.clip)
        end
    end
    for _, object in ipairs(entry.props) do
        Platform.DeleteLocalProp(object)
    end
end

local function readAnim(anim)
    if type(anim) ~= 'table' then
        return nil
    end
    if type(anim.scenario) == 'string' then
        return { scenario = anim.scenario }
    end
    if type(anim.dict) == 'string' and type(anim.clip) == 'string' then
        return {
            dict = anim.dict,
            clip = anim.clip,
            loop = anim.loop ~= false,
            upperBody = anim.upperBody == true,
            controllable = anim.controllable == true,
        }
    end
    return nil
end

local function readProps(prop)
    if type(prop) ~= 'table' then
        return {}
    end
    local list = prop.model and { prop } or prop
    local result = {}
    for i = 1, math.min(#list, MAX_PROPS) do
        local entry = list[i]
        if type(entry) == 'table' and (type(entry.model) == 'string' or type(entry.model) == 'number') then
            result[#result + 1] = entry
        end
    end
    return result
end

-- options: { duration, label, style = 'bar' | 'circle', canCancel, useWhileDead, disable = { move, car, combat, mouse },
--            anim = { dict, clip, loop, upperBody, controllable } | { scenario }, prop = { model, bone, pos, rot } | { ... } }
-- Gibt die Nummer zurueck oder nil und einen Fehlercode.
function Progress.Start(options)
    if active then
        return nil, 'busy'
    end
    if type(options) ~= 'table' then
        return nil, 'invalid_input'
    end
    local duration = tonumber(options.duration)
    if not duration or duration ~= duration then
        return nil, 'invalid_input'
    end
    duration = math.floor(math.max(CFG.MinDurationMs, math.min(CFG.MaxDurationMs, duration)))
    if options.useWhileDead ~= true and Platform.IsOwnPedDead() then
        return nil, 'dead'
    end

    local disable = {}
    if type(options.disable) == 'table' then
        for _, key in ipairs(DISABLE_KEYS) do
            disable[key] = options.disable[key] == true
        end
    end

    local id = Lib.NewRequest()
    local entry = {
        id = id,
        endsAt = Platform.GetTime() + duration,
        canCancel = options.canCancel ~= false,
        useWhileDead = options.useWhileDead == true,
        disable = disable,
        anim = readAnim(options.anim),
        props = {},
        cancelled = false,
    }
    active = entry

    Platform.Async(function()
        if entry.anim then
            if entry.anim.scenario then
                Platform.PlayOwnScenario(entry.anim.scenario)
            else
                Platform.PlayOwnAnim(entry.anim.dict, entry.anim.clip, entry.anim)
            end
        end
        for _, prop in ipairs(readProps(options.prop)) do
            local object = Platform.AttachPropToOwnPed(prop.model, prop.bone, prop.pos, prop.rot)
            if object then
                entry.props[#entry.props + 1] = object
            end
        end
    end)

    Ui.Send(UI, 'progress_open', {
        label = Lib.Text(options.label, CFG.MaxLabelLength) or '',
        style = STYLES[options.style] and options.style or 'bar',
        duration = duration,
        cancelKey = entry.canCancel and Platform.GetActionLabel('cancel') or nil,
    })

    -- Laeuft jeden Frame, aber nur solange der Balken sichtbar ist: Steuerung sperren und Abbrechen lesen
    Platform.Async(function()
        local completed = false
        while true do
            if entry.cancelled then
                break
            end
            if Platform.GetTime() >= entry.endsAt then
                completed = true
                break
            end
            if not entry.useWhileDead and Platform.IsOwnPedDead() then
                break
            end
            if entry.canCancel and Platform.IsActionPressed('cancel') then
                break
            end
            Platform.DisableActionsThisFrame(entry.disable)
            Platform.Wait(0)
        end
        active = nil
        cleanup(entry)
        Ui.Send(UI, 'progress_close', { completed = completed })
        Lib.Finish(entry.id, completed)
    end)

    return id
end

-- Laufenden Balken abbrechen (Ergebnis false)
function Progress.Cancel()
    if active then
        active.cancelled = true
        return true
    end
    return false
end

function Progress.IsActive()
    return active ~= nil
end

Platform.Export('StartProgress', Progress.Start)
Platform.Export('CancelProgress', Progress.Cancel)
Platform.Export('IsProgressActive', Progress.IsActive)
