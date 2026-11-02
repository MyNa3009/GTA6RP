-- Haufen am Boden: abgelegte Items. Nur im Speicher, nach Config.Inventory.Drops.LifetimeMinutes verschwinden sie.
-- Jeder Haufen ist ein Inventar der Art 'drop' mit Position und Dimension.

Drops = {}

local CFG = Config.Inventory.Drops
local CLEANUP_INTERVAL_MS = 60 * 1000
local SECONDS_PER_MINUTE = 60

local drops = {}   -- [id] = { id, inv, position, dimension, expiresAt }
local nextId = 0

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Drops.Create(position, dimension)
    nextId = nextId + 1
    local id = nextId
    drops[id] = {
        id = id,
        inv = { id = 'drop:' .. id, kind = 'drop', slots = {}, transient = true },
        position = { x = position.x, y = position.y, z = position.z },
        dimension = dimension or 0,
        expiresAt = os.time() + CFG.LifetimeMinutes * SECONDS_PER_MINUTE,
    }
    return drops[id]
end

function Drops.Get(id)
    return drops[tonumber(id)]
end

-- Naechster Haufen im Umkreis oder nil
function Drops.Nearest(position, dimension, radius)
    local best, bestDistance = nil, radius
    for _, drop in pairs(drops) do
        if drop.dimension == (dimension or 0) then
            local d = distance(drop.position, position)
            if d <= bestDistance then
                best, bestDistance = drop, d
            end
        end
    end
    return best
end

function Drops.InReach(drop, position, dimension)
    return drop ~= nil and drop.dimension == (dimension or 0) and distance(drop.position, position) <= CFG.PickupDistance
end

function Drops.IsEmpty(drop)
    return next(drop.inv.slots) == nil
end

-- Leere Haufen weg, neue Ablaufzeit fuer veraenderte. Gibt true zurueck, wenn der Haufen entfernt wurde.
function Drops.Touch(drop)
    if Drops.IsEmpty(drop) then
        drops[drop.id] = nil
        return true
    end
    drop.expiresAt = os.time() + CFG.LifetimeMinutes * SECONDS_PER_MINUTE
    return false
end

-- Was der Client von einem Haufen braucht
function Drops.Public(drop)
    return { id = drop.id, x = drop.position.x, y = drop.position.y, z = drop.position.z }
end

function Drops.List(dimension)
    local list = {}
    for _, drop in pairs(drops) do
        if drop.dimension == (dimension or 0) then
            list[#list + 1] = Drops.Public(drop)
        end
    end
    return list
end

-- Abgelaufene und leere Haufen entfernen. Gibt alle entfernten zurueck, volle mit expired = true (fuers Log).
function Drops.Expire()
    local now, removed = os.time(), {}
    for id, drop in pairs(drops) do
        local empty = Drops.IsEmpty(drop)
        if empty or drop.expiresAt <= now then
            drops[id] = nil
            removed[#removed + 1] = { drop = drop, expired = not empty }
        end
    end
    return removed
end

Drops.CleanupIntervalMs = CLEANUP_INTERVAL_MS
