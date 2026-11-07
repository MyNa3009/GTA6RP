-- G-Menue (Interaktionsmenue): ein Menue fuer fast alles, immer in Kategorien geteilt.
-- Scripts haengen Eintraege mit AddInteraction an einen Pfad, z. B. 'Organisation/Leader'. Der erste Teil ist
-- die Kategorie im Kreis, jeder weitere Teil eine Unterkategorie. Was gerade nicht passt (kein Fahrzeug, keine
-- Person angeschaut, keine Berechtigung ueber canShow), wird gar nicht angezeigt. Der Server prueft trotzdem selbst.
-- Ziel ist immer die Person, die man anschaut: Unter ihr laeuft ein Kreis am Boden, dann drueckt man G.
if LibDisabled then return end

Interact = {}

local CFG = Config.Lib.Interact
local ID_LENGTH = 64
local LABEL_LENGTH = 48
local DESCRIPTION_LENGTH = 160
local SEGMENT_LENGTH = 32
local ICON_LENGTH = 32
local STATE_LENGTH = 16
local PATH_SEPARATOR = '/'
local TARGETS = { none = true, player = true }
local VEHICLE_MODES = { inside = true, driver = true, outside = true }
local DISTANCE_ROUNDING = 10

local entries = {}      -- [id] = Eintrag
local count = 0
local categories = {}   -- [pfad] = { icon, order, label }
local session = nil     -- Stand beim Oeffnen: { ctx, players, nodes = { [nodeId] = entry } }

------------------------------------------------------------------------
-- Eintraege anmelden
------------------------------------------------------------------------

local function readPath(path)
    local segments = {}
    if type(path) == 'string' then
        for part in path:gmatch('[^' .. PATH_SEPARATOR .. ']+') do
            segments[#segments + 1] = part
        end
    elseif type(path) == 'table' then
        for _, part in ipairs(path) do
            segments[#segments + 1] = part
        end
    end
    if #segments == 0 or #segments > CFG.MaxDepth then
        return nil
    end
    for i, part in ipairs(segments) do
        part = Lib.Text(type(part) == 'string' and part:match('^%s*(.-)%s*$') or part, SEGMENT_LENGTH)
        if not part then
            return nil
        end
        segments[i] = part
    end
    return segments
end

-- def: {
--   id = 'org_fire',                      eindeutig, Pflicht
--   path = 'Organisation/Leader',         Kategorie und Unterkategorien, Pflicht
--   label = 'Mitglied entlassen',         Pflicht
--   description, icon, order,             optional
--   target = 'none' | 'player',           'player': nur, wenn man eine Person anschaut, ctx.player ist gesetzt
--   vehicle = 'inside' | 'driver' | 'outside',  nur im Fahrzeug, nur am Steuer, nur zu Fuss neben einem Fahrzeug
--   canShow = function(ctx) return true end,     schnell, ohne Warten. Auch fuer Berechtigungen: false = nicht da
--   state = function(ctx) return 'an' end,      kurzer Text rechts im Eintrag
--   keepOpen = false,                     Menue bleibt nach der Aktion offen und wird neu aufgebaut
--   onSelect = function(ctx) end | event = 'resource:event',
-- }
function Interact.Add(def, owner)
    owner = owner or Platform.GetCallingResource() or Platform.GetResourceName()
    if type(def) ~= 'table' then
        return false, 'invalid_input'
    end
    local id = Lib.Text(def.id, ID_LENGTH)
    local label = Lib.Text(def.label, LABEL_LENGTH)
    local path = readPath(def.path)
    if not id or not label or not path then
        return false, 'invalid_input'
    end
    if def.target ~= nil and not TARGETS[def.target] then
        return false, 'invalid_target'
    end
    if def.vehicle ~= nil and not VEHICLE_MODES[def.vehicle] then
        return false, 'invalid_vehicle'
    end
    local exists = entries[id] ~= nil
    if not exists and count >= CFG.MaxEntries then
        return false, 'too_many'
    end
    if exists and entries[id].owner ~= owner then
        return false, 'id_taken'
    end
    local action = Menu.ReadAction(def, owner)
    if not action.onSelect and not action.selectKey and not action.event then
        return false, 'no_action'
    end
    entries[id] = {
        id = id,
        owner = owner,
        path = path,
        label = label,
        description = Lib.Text(def.description, DESCRIPTION_LENGTH),
        icon = Lib.Text(def.icon, ICON_LENGTH),
        order = tonumber(def.order) or 100,
        target = def.target or 'none',
        vehicle = def.vehicle,
        canShow = def.canShow,
        state = def.state,
        keepOpen = def.keepOpen == true,
        action = action,
    }
    if not exists then
        count = count + 1
    end
    return true
end

function Interact.Remove(id)
    local entry = entries[id]
    if not entry then
        return false
    end
    entries[id] = nil
    count = count - 1
    return true
end

-- Aussehen und Reihenfolge einer Kategorie oder Unterkategorie: SetCategory('Organisation/Leader', { icon, order })
function Interact.SetCategory(path, options)
    local segments = readPath(path)
    if not segments or type(options) ~= 'table' then
        return false
    end
    categories[table.concat(segments, PATH_SEPARATOR)] = {
        icon = Lib.Text(options.icon, ICON_LENGTH),
        order = tonumber(options.order),
    }
    return true
end

for _, category in ipairs(CFG.Categories) do
    Interact.SetCategory(category.name, { icon = category.icon, order = category.order })
end

-- Eintraege einer gestoppten Resource entfernen
Platform.OnResourceStop(function(resource)
    for id, entry in pairs(entries) do
        if entry.owner == resource then
            Interact.Remove(id)
        end
    end
end)

------------------------------------------------------------------------
-- Stand beim Oeffnen
------------------------------------------------------------------------

local TARGET = Config.Lib.Interact.Target
local RING = LibTargetData.Ring

local target = nil        -- angeschaute Person { serverId, characterId, distance }, sonst nil
local ringRunning = false

local function round(distance)
    return math.floor(distance * DISTANCE_ROUNDING + 0.5) / DISTANCE_ROUNDING
end

local function readColor(rgb)
    local r, g, b = tostring(rgb or ''):match('^(%d+)%s+(%d+)%s+(%d+)$')
    return { r = tonumber(r) or 255, g = tonumber(g) or 255, b = tonumber(b) or 255 }
end

local RING_STYLE = {
    type = RING.type,
    size = RING.size,
    zOffset = RING.zOffset,
    rotate = RING.rotate,
    color = readColor(TARGET.Color),
    alpha = TARGET.Alpha,
}

-- Wen schaut man gerade an? Nur Spieler mit Charakter (permanente ID).
local function findTarget()
    if Platform.IsOwnPedDead() then
        return nil
    end
    local seen = Platform.GetPlayerInSight(CFG.PlayerDistance, TARGET.MaxAngle)
    if not seen then
        return nil
    end
    local characterId = Network.GetPlayerPublic(seen.serverId, 'coreId')
    if not characterId then
        return nil
    end
    return { serverId = seen.serverId, characterId = characterId, distance = round(seen.distance) }
end

-- Ist die Person noch in Reichweite? (fuer Aktionen bei offenem Menue)
local function inRange(serverId)
    for _, entry in ipairs(Platform.GetNearbyPlayers(CFG.PlayerDistance + TARGET.KeepTolerance, false)) do
        if entry.serverId == serverId then
            return true
        end
    end
    return false
end

-- Zeichnet den Kreis jeden Frame, aber nur solange es ein Ziel gibt
local function startRing()
    if ringRunning then
        return
    end
    ringRunning = true
    Platform.Async(function()
        while target do
            if not Platform.DrawPlayerRing(target.serverId, RING_STYLE) then
                target = nil
                break
            end
            Platform.Wait(0)
        end
        ringRunning = false
    end)
end

local function setTarget(value)
    target = value
    if target then
        startRing()
    end
end

-- ctx: { player (angeschaute Person), players ({ player } oder leer),
--        vehicle = { handle, inside, seat, isDriver, engine, lights, speedKmh, freeSeats } }
local function buildContext()
    local ctx = { player = target, players = target and { target } or {} }
    local state = Platform.GetOwnVehicleState()
    if state then
        ctx.vehicle = {
            handle = state.vehicle,
            inside = true,
            seat = state.seat,
            isDriver = state.isDriver,
            engine = state.engine,
            lights = state.lights,
            speedKmh = state.speedKmh,
            freeSeats = state.freeSeats,
        }
    else
        -- Zu Fuss: das Fahrzeug, auf das man schaut
        local seen = Platform.GetVehicleInSight(CFG.VehicleDistance)
        if seen then
            ctx.vehicle = { handle = seen, inside = false }
        end
    end
    return ctx
end

local function call(fn, ctx, entry, what)
    local ok, result = pcall(fn, ctx)
    if not ok then
        Platform.Print('error', ('core_lib: %s von "%s" (%s) ist fehlerhaft: %s'):format(what, entry.id, entry.owner, tostring(result)))
        return nil, false
    end
    return result, true
end

local function isVisible(entry, ctx)
    if entry.target == 'player' and not ctx.player then
        return false
    end
    if entry.vehicle then
        local vehicle = ctx.vehicle
        if not vehicle then
            return false
        end
        if entry.vehicle == 'inside' and not vehicle.inside then return false end
        if entry.vehicle == 'driver' and not vehicle.isDriver then return false end
        if entry.vehicle == 'outside' and vehicle.inside then return false end
    end
    if entry.canShow then
        local result, ok = call(entry.canShow, ctx, entry, 'canShow')
        return ok and result == true
    end
    return true
end

------------------------------------------------------------------------
-- Baum fuer die UI
------------------------------------------------------------------------

local function categoryInfo(key)
    return categories[key] or {}
end

local function sortNodes(list)
    table.sort(list, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.label < b.label
    end)
    for _, node in ipairs(list) do
        node.order = nil
        local children = node.children or node.items
        if children then
            sortNodes(children)
        end
    end
end

local function personLabel(player)
    local distance = (tostring(player.distance):gsub('%.', ','))
    return ('ID %d · %s m'):format(player.characterId, distance)
end

local function buildTree(ctx)
    local nodes = {}
    local roots = {}          -- [name] = Reiter
    local groups = {}         -- [pfad] = Knoten
    local tabs = {}

    local function groupFor(path)
        local key = path[1]
        local tab = roots[key]
        if not tab then
            local info = categoryInfo(key)
            tab = { id = 'g:' .. key, label = key, icon = info.icon, order = info.order or 1000, items = {} }
            roots[key] = tab
            tabs[#tabs + 1] = tab
        end
        local list = tab.items
        for depth = 2, #path do
            key = key .. PATH_SEPARATOR .. path[depth]
            local group = groups[key]
            if not group then
                local info = categoryInfo(key)
                group = { id = 'g:' .. key, label = path[depth], title = path[depth], icon = info.icon,
                    order = info.order or 0, children = {} }
                groups[key] = group
                list[#list + 1] = group
            end
            list = group.children
        end
        return list
    end

    for id, entry in pairs(entries) do
        if isVisible(entry, ctx) then
            local badge = nil
            if entry.state then
                badge = Lib.Text(call(entry.state, ctx, entry, 'state'), STATE_LENGTH)
            end
            local nodeId = 'e:' .. id
            nodes[nodeId] = entry
            local list = groupFor(entry.path)
            list[#list + 1] = {
                id = nodeId,
                label = entry.label,
                description = entry.description,
                icon = entry.icon,
                badge = badge,
                target = entry.target == 'player' and 'player' or nil,
                order = entry.order,
            }
        end
    end

    -- Leere Unterkategorien gibt es nicht, weil Gruppen nur fuer sichtbare Eintraege entstehen
    sortNodes(tabs)
    return tabs, nodes
end

local function payload(ctx, tabs)
    local subtitle = ctx.player and ('Person: ' .. personLabel(ctx.player)) or nil
    return { mode = 'interact', title = 'Interaktion', subtitle = subtitle, tabs = tabs }
end

------------------------------------------------------------------------
-- Oeffnen, Auswahl, Neuaufbau
------------------------------------------------------------------------

local onSelectNode   -- weiter unten: Auswahl in der UI

local function refresh()
    if not session or not Menu.IsOpen('interact') then
        return
    end
    local ctx = buildContext()
    local tabs, nodes = buildTree(ctx)
    session.ctx, session.nodes = ctx, nodes
    if #tabs == 0 then
        Menu.Close('interact')
        return
    end
    Menu.Update('interact', payload(ctx, tabs))
end

function Interact.Open()
    if Menu.IsOpen('interact') then
        Menu.Close('interact')
        return
    end
    if Platform.IsOwnPedDead() then
        Lib.Notify('Bewusstlos kannst du nichts tun.', 'error')
        return
    end
    -- Das Ziel beim Druecken auf G gilt, bis das Menue zu ist
    setTarget(findTarget())
    local ctx = buildContext()
    local tabs, nodes = buildTree(ctx)
    if #tabs == 0 then
        Lib.Notify('Hier gibt es gerade nichts zu tun.', 'info')
        return
    end
    session = { ctx = ctx, nodes = nodes }
    Menu.Open('interact', payload(ctx, tabs), {
        select = onSelectNode,
        closed = function()
            session = nil
        end,
    })
end

-- Kopie des Stands fuer die Aktion: ohne Funktionen, mit der gewaehlten Person
local function actionContext(ctx, player)
    return { player = player, players = ctx.players, vehicle = ctx.vehicle }
end

onSelectNode = function(data)
    if not session then
        return { ok = false, error = 'not_open' }
    end
    local entry = session.nodes[data.id]
    if not entry or not entries[entry.id] then
        return { ok = false, error = 'not_found' }
    end
    local ctx = session.ctx
    local player = ctx.player
    if entry.target == 'player' and (not player or not inRange(player.serverId)) then
        return { ok = false, error = 'player_gone' }
    end

    local value = actionContext(ctx, player)
    if entry.keepOpen then
        Menu.RunAction(entry.action, value)
        Platform.Async(function()
            Platform.Wait(CFG.RefreshDelayMs)
            refresh()
        end)
        return { ok = true, data = { close = false } }
    end
    Menu.Close('interact')
    Menu.RunAction(entry.action, value)
    return { ok = true, data = { close = true } }
end

Platform.RegisterKeyCommand(CFG.Command, 'Interaktionsmenü öffnen', CFG.Key, function()
    Interact.Open()
end)

-- Blickziel suchen, solange das Menue zu ist. Bei offenem Menue bleibt das Ziel, bis die Person zu weit weg ist.
Platform.Async(function()
    while true do
        if Menu.IsOpen('interact') then
            if target and not inRange(target.serverId) then
                target = nil
            end
        elseif not Menu.IsOpen() then
            setTarget(findTarget())
        elseif target then
            target = nil
        end
        Platform.Wait(TARGET.IntervalMs)
    end
end)

Platform.Export('GetInteractionTarget', function()
    return target and { serverId = target.serverId, characterId = target.characterId, distance = target.distance } or nil
end)

Platform.Export('AddInteraction', function(def) return Interact.Add(def) end)
Platform.Export('RemoveInteraction', function(id)
    local entry = entries[id]
    local caller = Platform.GetCallingResource()
    if entry and caller and entry.owner ~= caller then
        return false
    end
    return Interact.Remove(id)
end)
Platform.Export('SetInteractionCategory', Interact.SetCategory)
Platform.Export('OpenInteractionMenu', Interact.Open)
Platform.Export('CloseInteractionMenu', function() return Menu.Close('interact') end)
