-- Punkte und Zonen fuer andere Resources (wie lib.points und lib.zones bei ox_lib).
-- Im fxmanifest nach der Bridge der Core und init.lua in die client_scripts: '@core_lib/modules/zones.lua'
-- Alles laeuft in der eigenen Resource. Ein Thread prueft die Position alle CHECK_MS. Nur wenn man in einem Punkt
-- mit nearby oder einer Zone mit inside steht, laeuft zusaetzlich ein Thread jeden Frame.
--
--   local point = lib.points.new({ coords = { x = 0, y = 0, z = 70 }, distance = 3, onEnter = fn, onExit = fn, nearby = fn })
--   local zone = lib.zones.box({ coords = { x, y, z }, size = { x = 4, y = 6, z = 3 }, rotation = 45, onEnter = fn, onExit = fn, inside = fn })
--   lib.zones.sphere({ coords, radius }), lib.zones.poly({ points = { { x, y }, ... }, minZ, maxZ })
--   point:remove(), zone:remove(), zone:contains({ x, y, z })

lib = lib or {}
if lib.points then
    return
end

local CHECK_MS = 300

local items = {}      -- [id] = Punkt oder Zone
local nextId = 0
local loopRunning = false
local tickRunning = false
local insideTick = {} -- [id] = Eintrag, solange man drin ist und es jeden Frame etwas tun will

local function run(entry, name)
    local fn = entry[name]
    if type(fn) ~= 'function' then
        return
    end
    local ok, err = pcall(fn, entry)
    if not ok then
        Platform.Print('error', ('Zone %d (%s): %s'):format(entry.id, name, tostring(err)))
    end
end

local function vec(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'userdata' then
        return nil
    end
    local x, y, z = tonumber(value.x or value[1]), tonumber(value.y or value[2]), tonumber(value.z or value[3])
    if not x or not y then
        return nil
    end
    return { x = x, y = y, z = z or 0.0 }
end

local function startTick()
    if tickRunning then
        return
    end
    tickRunning = true
    Platform.Async(function()
        while next(insideTick) do
            for _, entry in pairs(insideTick) do
                run(entry, entry.kind == 'point' and 'nearby' or 'inside')
            end
            Platform.Wait(0)
        end
        tickRunning = false
    end)
end

local function startLoop()
    if loopRunning then
        return
    end
    loopRunning = true
    Platform.Async(function()
        while next(items) do
            local position = Platform.GetOwnPosition()
            for id, entry in pairs(items) do
                local isInside = entry:contains(position)
                if isInside and not entry.isInside then
                    entry.isInside = true
                    run(entry, 'onEnter')
                    if entry.kind == 'point' and entry.nearby or entry.kind ~= 'point' and entry.inside then
                        insideTick[id] = entry
                        startTick()
                    end
                elseif not isInside and entry.isInside then
                    entry.isInside = false
                    insideTick[id] = nil
                    run(entry, 'onExit')
                end
            end
            Platform.Wait(CHECK_MS)
        end
        loopRunning = false
    end)
end

local function add(entry)
    nextId = nextId + 1
    entry.id = nextId
    entry.isInside = false
    entry.remove = function(self)
        items[self.id] = nil
        insideTick[self.id] = nil
        if self.isInside then
            self.isInside = false
            run(self, 'onExit')
        end
    end
    items[entry.id] = entry
    startLoop()
    return entry
end

local function copyOptions(options)
    local entry = {}
    for k, v in pairs(options) do
        entry[k] = v
    end
    return entry
end

------------------------------------------------------------------------
-- Punkte: Abstand zu einer Stelle
------------------------------------------------------------------------

lib.points = {}

function lib.points.new(options)
    local coords = type(options) == 'table' and vec(options.coords)
    local distance = type(options) == 'table' and tonumber(options.distance)
    if not coords or not distance or distance <= 0 then
        return nil, 'invalid_input'
    end
    local entry = copyOptions(options)
    entry.kind = 'point'
    entry.coords = coords
    entry.distance = distance
    entry.contains = function(self, position)
        local dx, dy, dz = position.x - self.coords.x, position.y - self.coords.y, position.z - self.coords.z
        self.currentDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
        return self.currentDistance <= self.distance
    end
    return add(entry)
end

------------------------------------------------------------------------
-- Zonen: Kugel, Quader (gedreht), Vieleck
------------------------------------------------------------------------

lib.zones = {}

function lib.zones.sphere(options)
    local coords = type(options) == 'table' and vec(options.coords)
    local radius = type(options) == 'table' and tonumber(options.radius)
    if not coords or not radius or radius <= 0 then
        return nil, 'invalid_input'
    end
    local entry = copyOptions(options)
    entry.kind = 'sphere'
    entry.coords, entry.radius = coords, radius
    entry.contains = function(self, position)
        local dx, dy, dz = position.x - self.coords.x, position.y - self.coords.y, position.z - self.coords.z
        return dx * dx + dy * dy + dz * dz <= self.radius * self.radius
    end
    return add(entry)
end

-- size: { x = Breite, y = Laenge, z = Hoehe }, rotation in Grad um die Hochachse
function lib.zones.box(options)
    local coords = type(options) == 'table' and vec(options.coords)
    local size = type(options) == 'table' and vec(options.size)
    if not coords or not size or size.x <= 0 or size.y <= 0 then
        return nil, 'invalid_input'
    end
    local entry = copyOptions(options)
    entry.kind = 'box'
    entry.coords, entry.size = coords, size
    local angle = math.rad(-(tonumber(options.rotation) or 0))
    local cos, sin = math.cos(angle), math.sin(angle)
    local height = size.z > 0 and size.z or math.huge
    entry.contains = function(self, position)
        local dx, dy = position.x - self.coords.x, position.y - self.coords.y
        local localX = dx * cos - dy * sin
        local localY = dx * sin + dy * cos
        return math.abs(localX) <= self.size.x / 2 and math.abs(localY) <= self.size.y / 2
            and math.abs(position.z - self.coords.z) <= height / 2
    end
    return add(entry)
end

-- points: Ecken { x, y } im Uhrzeigersinn oder dagegen. minZ und maxZ optional.
function lib.zones.poly(options)
    if type(options) ~= 'table' or type(options.points) ~= 'table' or #options.points < 3 then
        return nil, 'invalid_input'
    end
    local corners = {}
    for i, point in ipairs(options.points) do
        local corner = vec(point)
        if not corner then
            return nil, 'invalid_input'
        end
        corners[i] = corner
    end
    local entry = copyOptions(options)
    entry.kind = 'poly'
    entry.points = corners
    local minZ, maxZ = tonumber(options.minZ) or -math.huge, tonumber(options.maxZ) or math.huge
    entry.contains = function(self, position)
        if position.z < minZ or position.z > maxZ then
            return false
        end
        -- Strahl-Test: wie oft schneidet eine Linie nach rechts die Kanten?
        local inside = false
        local list = self.points
        local j = #list
        for i = 1, #list do
            local a, b = list[i], list[j]
            if (a.y > position.y) ~= (b.y > position.y)
                and position.x < (b.x - a.x) * (position.y - a.y) / (b.y - a.y) + a.x then
                inside = not inside
            end
            j = i
        end
        return inside
    end
    return add(entry)
end
