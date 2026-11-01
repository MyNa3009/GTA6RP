-- Hunger und Durst (0 bis 100). Der Server rechnet und speichert, der Client zeigt an und zieht bei 0 Gesundheit ab.
-- Andere Scripts: exports.core:GetNeeds(source), exports.core:AddNeeds(source, { hunger = 25, thirst = 40 }),
-- exports.core:SetNeeds(source, { hunger = 100, thirst = 100 }).

Needs = {}

local CFG = Config.Needs
local MAX = 100
local UPDATE_EVENT = 'core:needs:update'
local SECONDS_PER_MINUTE = 60
local SAVE_EVERY_TICKS = 6 -- bei 10 s pro Tick jede Minute

local NEEDS_COLUMNS = {
    'ALTER TABLE characters ADD COLUMN IF NOT EXISTS hunger DECIMAL(5,2) NOT NULL DEFAULT 100.00 AFTER job_grade',
    'ALTER TABLE characters ADD COLUMN IF NOT EXISTS thirst DECIMAL(5,2) NOT NULL DEFAULT 100.00 AFTER hunger',
}

Needs.Ready = false

DB.Ready(function()
    for _, statement in ipairs(NEEDS_COLUMNS) do
        if DB.Query(statement) == nil then
            Platform.Print('error', 'Spalten characters.hunger und thirst fehlen. Bitte 010_needs.sql ausfuehren.')
            return
        end
    end
    Needs.Ready = true
end)

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function clamp(value)
    value = tonumber(value) or MAX
    if value ~= value then
        return MAX
    end
    return math.max(0, math.min(MAX, value))
end

-- Fuer Client und Exports: ganze Zahlen reichen
local function view(needs)
    return { hunger = math.floor(needs.hunger + 0.5), thirst = math.floor(needs.thirst + 0.5) }
end

local function send(player)
    local needs = player.character.needs
    local shown = view(needs)
    needs.sentHunger, needs.sentThirst = shown.hunger, shown.thirst
    Network.SendToClient(player.source, UPDATE_EVENT, shown)
end

local function save(characterId, needs)
    DB.Update('UPDATE characters SET hunger = ?, thirst = ? WHERE id = ?', { needs.hunger, needs.thirst, characterId })
    needs.dirty = false
end

local function paused(player)
    if player.character.diedAt then
        return true
    end
    if CFG.PauseOnAdminDuty and player.adminDuty then
        return true
    end
    if CFG.PauseInJail and player.jail then
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Laden und Speichern (aus characters.lua)
------------------------------------------------------------------------

-- row kommt aus dem SELECT in Characters.Select
function Needs.Load(player, row)
    player.character.needs = { hunger = clamp(row.hunger), thirst = clamp(row.thirst), dirty = false }
    return view(player.character.needs)
end

function Needs.Unload(player)
    local needs = player.character and player.character.needs
    if needs and needs.dirty then
        save(player.characterId, needs)
    end
end

------------------------------------------------------------------------
-- Aendern
------------------------------------------------------------------------

local function playerOf(source)
    local player = Core.GetPlayer(tonumber(source))
    if player and player.character and player.character.needs then
        return player
    end
    return nil
end

function Needs.Get(source)
    local player = playerOf(source)
    return player and view(player.character.needs) or nil
end

-- Setzt Werte (fehlende Felder bleiben). Gibt die neuen Werte zurueck oder nil.
function Needs.Set(source, values)
    local player = playerOf(source)
    if not player or type(values) ~= 'table' then
        return nil
    end
    local needs = player.character.needs
    if values.hunger ~= nil then needs.hunger = clamp(values.hunger) end
    if values.thirst ~= nil then needs.thirst = clamp(values.thirst) end
    needs.dirty = true
    send(player)
    return view(needs)
end

-- Zaehlt dazu (auch negativ). Gibt die neuen Werte zurueck oder nil.
function Needs.Add(source, values)
    local player = playerOf(source)
    if not player or type(values) ~= 'table' then
        return nil
    end
    local needs = player.character.needs
    return Needs.Set(source, {
        hunger = needs.hunger + (tonumber(values.hunger) or 0),
        thirst = needs.thirst + (tonumber(values.thirst) or 0),
    })
end

-- Nach Krankenhaus und Wiederbeleben: nicht sofort wieder bei 0 anfangen
function Needs.AfterRespawn(source)
    local player = playerOf(source)
    if not player then
        return
    end
    local needs = player.character.needs
    Needs.Set(source, { hunger = math.max(needs.hunger, CFG.AfterRespawn), thirst = math.max(needs.thirst, CFG.AfterRespawn) })
end

function Needs.Fill(source)
    return Needs.Set(source, { hunger = MAX, thirst = MAX })
end

------------------------------------------------------------------------
-- Abfall ueber die Zeit
------------------------------------------------------------------------

local hungerPerTick = MAX / (CFG.HungerMinutes * SECONDS_PER_MINUTE) * CFG.TickSeconds
local thirstPerTick = MAX / (CFG.ThirstMinutes * SECONDS_PER_MINUTE) * CFG.TickSeconds
local tick = 0

local function step()
    tick = tick + 1
    local saveNow = tick % SAVE_EVERY_TICKS == 0
    for _, player in pairs(Core.Players) do
        local needs = player.character and player.character.needs
        if needs then
            if not paused(player) and (needs.hunger > 0 or needs.thirst > 0) then
                needs.hunger = math.max(0, needs.hunger - hungerPerTick)
                needs.thirst = math.max(0, needs.thirst - thirstPerTick)
                needs.dirty = true
                local shown = view(needs)
                -- Nur senden, wenn sich die angezeigte Zahl aendert (etwa jede Minute)
                if shown.hunger ~= needs.sentHunger or shown.thirst ~= needs.sentThirst then
                    send(player)
                end
            end
            if saveNow and needs.dirty then
                save(player.characterId, needs)
            end
        end
    end
end

if CFG.Enabled then
    Platform.SetInterval(CFG.TickSeconds * 1000, step)
end

-- Beim Stoppen der Core alles sichern
Platform.OnResourceStop(function()
    for _, player in pairs(Core.Players) do
        local needs = player.character and player.character.needs
        if needs and needs.dirty then
            DB.Fire('UPDATE characters SET hunger = ?, thirst = ? WHERE id = ?', { needs.hunger, needs.thirst, player.characterId })
        end
    end
end)

------------------------------------------------------------------------
-- Fuer andere Resources (Inventar, spaeteres HUD)
------------------------------------------------------------------------

Platform.Export('GetNeeds', Needs.Get)
Platform.Export('SetNeeds', Needs.Set)
Platform.Export('AddNeeds', Needs.Add)
