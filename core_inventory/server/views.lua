-- Zweites Fenster: ein fremdes Inventar neben dem eigenen.
--   search  Durchsuchen: Person hat die Haende oben oder ist gefesselt. Nur nehmen, nichts hineinlegen.
--   trunk   Kofferraum: am Heck, Fahrzeug offen, immer nur eine Person. Nehmen und hineinlegen.
--   admin   /invsee: alles, auch offline.
--   stash   Lager aus einem anderen Script (Fraktion, Wohnung, Spind). Mehrere Personen gleichzeitig.
--
-- Fuer das spaetere G-Menue (Server):
--   exports.core_inventory:OpenSearch(source, zielServerId)        -> true | false, fehler
--   exports.core_inventory:OpenTrunk(source, netId, fahrzeugklasse)
--   exports.core_inventory:SetCuffed(source, true|false)            (vom Fessel-Script)
--   exports.core_inventory:IsHandsUp(source), IsCuffed(source)
--
-- Fuer Lager-Scripts (das Script prueft selbst, wer darf):
--   exports.core_inventory:OpenStash(source, 'lspd_waffen', { label = 'Waffenkammer LSPD', slots = 50, maxWeight = 200000,
--       position = { x = 452.1, y = -980.2, z = 30.7 }, distance = 3.0, canPut = true })   -> true | false, fehler

Views = {}

local CORE = 'core'
local CFG = Config.Inventory

local views = {}          -- [source] = Sitzung
local handsUp = {}        -- [source] = true
local cuffed = {}         -- [source] = true
local trunkUsers = {}     -- [Kennzeichen] = source
local stashUsers = {}     -- [Lager-ID] = Anzahl offener Fenster
local STASH_ID_MAX = 48

-- Plaetze, die man beim Durchsuchen sieht und nehmen darf (Taschen kommen dazu)
local SEARCH_SLOTS = { weapon = true }

local function log(source, action, data, extra)
    local entry = {
        actor_account_id = Platform.CallExport(CORE, 'GetAccountId', source),
        account_id = Platform.CallExport(CORE, 'GetAccountId', source),
        character_id = InventoryApi_ActiveCharacter(source),
        category = 'item',
        action = action,
        data = data,
    }
    for k, v in pairs(extra or {}) do
        entry[k] = v
    end
    Platform.CallExport(CORE, 'Log', entry)
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function near(source, position, maxDistance)
    local own = Platform.GetPlayerPosition(source)
    return own ~= nil and position ~= nil and distance(own, position) <= maxDistance
end

------------------------------------------------------------------------
-- Haende hoch und Fesseln
------------------------------------------------------------------------

Network.RegisterCallback('inv_handsup', function(source, data)
    if not InventoryApi_ActiveCharacter(source) then
        return { ok = false, error = 'no_character' }
    end
    handsUp[source] = type(data) == 'table' and data.up == true or nil
    return { ok = true }
end)

function Views.SetCuffed(source, value)
    source = tonumber(source)
    if source then
        cuffed[source] = value and true or nil
    end
end

local function searchable(target)
    return handsUp[target] == true or cuffed[target] == true
end

------------------------------------------------------------------------
-- Was das Fenster vom fremden Inventar zeigt
------------------------------------------------------------------------

local function filtered(inv, allow)
    local list = {}
    for _, entry in ipairs(Inventory.ListOf(inv)) do
        if allow(entry.slot) then
            list[#list + 1] = entry
        end
    end
    return list
end

function Views.StateFor(source)
    local view = views[source]
    if not view then
        return nil
    end
    local inv = view.inv
    local state = {
        kind = view.kind,
        title = view.title,
        canPut = view.canPut,
        weight = Inventory.Weight(inv),
        maxWeight = Inventory.MaxWeight(inv),
        slots = Inventory.SlotLimit(inv),
    }
    if view.kind == 'trunk' then
        state.items = Inventory.ListOf(inv)
        return state
    end
    -- Person: Taschen und Waffe, beim Admin auch Kleidung und Dokumente (nur ansehen)
    local admin = view.kind == 'admin'
    state.items = filtered(inv, function(slot)
        return tonumber(slot) ~= nil or SEARCH_SLOTS[slot] or (admin and Inventory.EquipSlot(slot) ~= nil) or (admin and slot:sub(1, 4) == 'doc_')
    end)
    state.weaponSlot = true
    state.equip = admin and CFG.EquipSlots or nil
    state.documents = admin and CFG.Documents.Slots or nil
    local bag = Inventory.Bag(inv)
    view.bag = bag
    if bag then
        state.bag = { items = Inventory.ListOf(bag), slots = Inventory.SlotLimit(bag), weight = Inventory.Weight(bag), maxWeight = Inventory.MaxWeight(bag) }
    end
    return state
end

------------------------------------------------------------------------
-- Oeffnen und Schliessen
------------------------------------------------------------------------

function Views.Close(source)
    local view = views[source]
    if not view then
        return
    end
    views[source] = nil
    if view.plate and trunkUsers[view.plate] == source then
        trunkUsers[view.plate] = nil
    end
    if view.kind == 'stash' then
        Inventory.Save(view.inv)
        local left = (stashUsers[view.inv.id] or 1) - 1
        stashUsers[view.inv.id] = left > 0 and left or nil
        if left <= 0 then
            Inventory.Unload(view.inv)
        end
    end
    if view.target then
        Platform.Notify(view.target, 'Die Durchsuchung ist beendet.', 'info')
    end
    -- Offline-Inventar wieder aus dem Speicher (vorher speichern), aber nur, wenn die Person nicht inzwischen eingeloggt ist
    if view.offline and not InventoryApi_SourceOf(view.characterId) then
        if view.bag then
            Inventory.Unload(view.bag)
        end
        Inventory.Unload(view.inv)
    elseif view.kind == 'trunk' then
        Inventory.Save(view.inv)
        Inventory.Unload(view.inv)
    end
end

function Views.OpenSearch(source, target)
    target = tonumber(target)
    local characterId = InventoryApi_ActiveCharacter(source)
    local targetCharacter = target and InventoryApi_ActiveCharacter(target)
    if not characterId then
        return false, 'no_character'
    end
    if not targetCharacter or target == source then
        return false, 'target_offline'
    end
    if Platform.GetPlayerDimension(source) ~= Platform.GetPlayerDimension(target) or not near(source, Platform.GetPlayerPosition(target), CFG.Search.Distance) then
        return false, 'too_far'
    end
    if not searchable(target) then
        return false, 'not_searchable'
    end
    Views.Close(source)
    views[source] = {
        kind = 'search', target = target, characterId = targetCharacter, canPut = false,
        inv = Inventory.ForCharacter(targetCharacter), title = ('ID %d durchsuchen'):format(targetCharacter),
    }
    Platform.Notify(target, ('ID %d durchsucht dich.'):format(characterId), 'info')
    log(source, 'search_open', { target = targetCharacter }, { target_account_id = Platform.CallExport(CORE, 'GetAccountId', target) })
    return true
end

local function normalizePlate(plate)
    return type(plate) == 'string' and plate:upper():gsub('^%s+', ''):gsub('%s+$', '') or nil
end

function Views.OpenTrunk(source, netId, vehicleClass)
    if not InventoryApi_ActiveCharacter(source) then
        return false, 'no_character'
    end
    local vehicle = Platform.GetVehicleInfo(tonumber(netId))
    if not vehicle then
        return false, 'no_vehicle'
    end
    local plate = normalizePlate(vehicle.plate)
    if not plate or plate == '' then
        return false, 'no_vehicle'
    end
    if not near(source, vehicle.position, CFG.Trunk.Distance) then
        return false, 'too_far'
    end
    if vehicle.locked then
        return false, 'vehicle_locked'
    end
    if trunkUsers[plate] and trunkUsers[plate] ~= source then
        return false, 'trunk_busy'
    end
    local inv = Inventory.Load('trunk:' .. plate, 'trunk')
    -- Die Groesse gilt ab dem ersten Oeffnen fuer dieses Kennzeichen (der Client meldet die Klasse)
    inv.flags = inv.flags or {}
    if inv.flags.trunkClass == nil then
        if not TrunkSizes[tonumber(vehicleClass) or -1] then
            Inventory.Unload(inv)
            return false, 'no_trunk'
        end
        inv.flags.trunkClass = tonumber(vehicleClass)
        inv.dirty = true
    end
    local size = TrunkSizes[inv.flags.trunkClass]
    if not size then
        return false, 'no_trunk'
    end
    inv.capacity = { slots = size.slots, maxWeight = size.maxWeight }
    Views.Close(source)
    trunkUsers[plate] = source
    views[source] = { kind = 'trunk', plate = plate, netId = tonumber(netId), canPut = true, inv = inv, title = ('Kofferraum %s'):format(plate) }
    log(source, 'trunk_open', { plate = plate })
    return true
end

function Views.OpenStash(source, stashId, options)
    if not InventoryApi_ActiveCharacter(source) then
        return false, 'no_character'
    end
    options = type(options) == 'table' and options or {}
    local slots, maxWeight = math.floor(tonumber(options.slots) or 0), math.floor(tonumber(options.maxWeight) or 0)
    if type(stashId) ~= 'string' or stashId == '' or #stashId > STASH_ID_MAX
        or slots < 1 or slots > CFG.Stash.MaxSlots or maxWeight < 1 then
        return false, 'invalid_stash'
    end
    local position = type(options.position) == 'table' and options.position or nil
    local maxDistance = tonumber(options.distance) or CFG.Stash.Distance
    if position and not near(source, position, maxDistance) then
        return false, 'too_far'
    end
    local inv = Inventory.Load('stash:' .. stashId, 'stash')
    inv.capacity = { slots = slots, maxWeight = maxWeight }
    Views.Close(source)
    stashUsers[inv.id] = (stashUsers[inv.id] or 0) + 1
    views[source] = {
        kind = 'stash', stash = stashId, canPut = options.canPut ~= false, inv = inv, position = position, distance = maxDistance,
        title = type(options.label) == 'string' and options.label ~= '' and options.label or 'Lager',
    }
    log(source, 'stash_open', { stash = stashId })
    return true
end

function Views.OpenAdmin(source, characterId)
    characterId = tonumber(characterId)
    local online = InventoryApi_SourceOf(characterId)
    Views.Close(source)
    views[source] = {
        kind = 'admin', characterId = characterId, canPut = true, offline = online == nil, target = nil, targetSource = online,
        inv = Inventory.ForCharacter(characterId), title = ('Inventar von ID %d'):format(characterId),
    }
    return true
end

------------------------------------------------------------------------
-- Verschieben zwischen eigenem und fremdem Inventar
------------------------------------------------------------------------

local OTHER = { other = true, otherbag = true }

-- Darf diese Bewegung in dieser Sitzung sein? Gibt nil oder einen Fehler zurueck.
local function allowed(view, source, from, to)
    local fromOther, toOther = OTHER[from.inv], OTHER[to.inv]
    if view.kind == 'admin' then
        return nil
    end
    if view.kind == 'search' then
        if toOther or not fromOther then
            return 'not_allowed'
        end
        if from.inv == 'other' and not (tonumber(from.slot) or SEARCH_SLOTS[from.slot]) then
            return 'not_allowed'
        end
        if not searchable(view.target) or Platform.GetPlayerDimension(source) ~= Platform.GetPlayerDimension(view.target)
            or not near(source, Platform.GetPlayerPosition(view.target), CFG.Search.Distance) then
            return 'search_ended'
        end
        return nil
    end
    if view.kind == 'trunk' then
        if from.inv == 'otherbag' or to.inv == 'otherbag' then
            return 'invalid_slot'
        end
        local vehicle = Platform.GetVehicleInfo(view.netId)
        if not vehicle or vehicle.locked or not near(source, vehicle.position, CFG.Trunk.Distance) then
            return 'trunk_closed'
        end
        return nil
    end
    if view.kind == 'stash' then
        if from.inv == 'otherbag' or to.inv == 'otherbag' then
            return 'invalid_slot'
        end
        if OTHER[to.inv] and not OTHER[from.inv] and not view.canPut then
            return 'not_allowed'
        end
        if view.position and not near(source, view.position, view.distance) then
            return 'stash_closed'
        end
        return nil
    end
    return 'not_allowed'
end

function Views.Move(source, inv, data)
    local view = views[source]
    local from, to = data.from, data.to
    if not view then
        return false, 'view_closed'
    end
    local err = allowed(view, source, from, to)
    if err then
        if err == 'search_ended' or err == 'trunk_closed' or err == 'stash_closed' then
            Views.Close(source)
        end
        return false, err
    end
    local fromInv = from.inv == 'other' and view.inv or (from.inv == 'otherbag' and Inventory.Bag(view.inv)) or (from.inv == 'bag' and Inventory.Bag(inv)) or inv
    local entry = fromInv and fromInv.slots[tostring(from.slot)]
    local ok, moveErr = Inventory.Move(inv, from, to, data.count, { other = view.inv, otherBag = (view.kind == 'search' or view.kind == 'admin') and Inventory.Bag(view.inv) or nil })
    if not ok then
        return false, moveErr
    end
    local amount = data.count or (entry and entry.count)
    local info = entry and { item = entry.name, label = ItemDef(entry.name) and ItemDef(entry.name).label, serial = entry.meta and entry.meta.serial } or nil
    local action = view.kind == 'search' and 'search_take'
        or view.kind == 'trunk' and (OTHER[from.inv] and 'trunk_take' or 'trunk_put')
        or view.kind == 'stash' and (OTHER[from.inv] and 'stash_take' or 'stash_put')
        or 'admin_move'
    local extra = { amount = amount }
    if view.characterId then
        extra.target_account_id = Platform.CallExport(CORE, 'GetCharacterAccount', view.characterId)
    end
    if info then
        info.plate = view.plate
        info.stash = view.stash
        info.target = view.characterId
    end
    log(source, action, info, extra)
    -- Die andere Person sieht ihr Inventar sofort neu (Waffe aus der Hand, Bargeld-Anzeige)
    local targetSource = view.target or (view.characterId and InventoryApi_SourceOf(view.characterId))
    if targetSource then
        Network.SendToClient(targetSource, 'core_inventory:changed', {})
        InventoryApi_AfterChange(targetSource, source)
    end
    -- Andere am selben Lager sehen es sofort
    if view.kind == 'stash' then
        for viewer, other in pairs(views) do
            if viewer ~= source and other.inv == view.inv then
                Network.SendToClient(viewer, 'core_inventory:changed', {})
            end
        end
    end
    if view.kind == 'trunk' or view.kind == 'stash' then
        Inventory.Save(view.inv)
    end
    return true
end

Network.RegisterCallback('view_close', function(source)
    Views.Close(source)
    return { ok = true }
end)

-- Das Inventar dieser Person hat sich geaendert (sie selbst, Geben, Admin): wer es offen hat, sieht es neu
function Views.Touched(source, exceptViewer)
    local characterId = InventoryApi_ActiveCharacter(source)
    if not characterId then
        return
    end
    for viewer, view in pairs(views) do
        if viewer ~= exceptViewer and viewer ~= source and view.characterId == characterId then
            Network.SendToClient(viewer, 'core_inventory:changed', {})
        end
    end
end

------------------------------------------------------------------------
-- Aufraeumen
------------------------------------------------------------------------

Platform.OnEvent('core:characterUnloaded', function(source)
    source = tonumber(source)
    if not source then
        return
    end
    Views.Close(source)
    handsUp[source], cuffed[source] = nil, nil
    -- Wer gerade diese Person durchsucht, verliert das Fenster
    for viewer, view in pairs(views) do
        if view.target == source or view.targetSource == source then
            Views.Close(viewer)
            Network.SendToClient(viewer, 'core_inventory:view_closed', {})
        end
    end
end)

------------------------------------------------------------------------
-- Schnittstellen
------------------------------------------------------------------------

Platform.Export('OpenSearch', function(source, target)
    local ok, err = Views.OpenSearch(source, target)
    if ok then
        Network.SendToClient(source, 'core_inventory:view', { kind = 'search', target = tonumber(target) })
    end
    return ok, err
end)
Platform.Export('OpenTrunk', function(source, netId, vehicleClass)
    local ok, err = Views.OpenTrunk(source, netId, vehicleClass)
    if ok then
        Network.SendToClient(source, 'core_inventory:view', { kind = 'trunk', netId = tonumber(netId) })
    end
    return ok, err
end)
Platform.Export('OpenStash', function(source, stashId, options)
    local ok, err = Views.OpenStash(source, stashId, options)
    if ok then
        local view = views[source]
        Network.SendToClient(source, 'core_inventory:view', { kind = 'stash', position = view.position, distance = view.distance })
    end
    return ok, err
end)
Platform.Export('SetCuffed', Views.SetCuffed)
Platform.Export('IsCuffed', function(source) return cuffed[tonumber(source)] == true end)
Platform.Export('IsHandsUp', function(source) return handsUp[tonumber(source)] == true end)

Network.RegisterCallback('view_search', function(source, data)
    local ok, err = Views.OpenSearch(source, type(data) == 'table' and data.target)
    return { ok = ok, error = err }
end)

Network.RegisterCallback('view_trunk', function(source, data)
    data = type(data) == 'table' and data or {}
    local ok, err = Views.OpenTrunk(source, data.netId, data.class)
    return { ok = ok, error = err }
end)

-- /invsee ID: Inventar ansehen und bearbeiten, auch offline
Platform.RegisterCommand('invsee', function(source, args)
    local allowedCmd, actorAccountId = Platform.CallExport(CORE, 'AuthorizeCommand', source, 'invsee', 'items.manage', args, true)
    if not allowedCmd then
        return
    end
    local characterId = tonumber(args[1])
    if not characterId or source == 0 then
        Platform.Notify(source, 'Benutzung: /invsee <permanente ID> (nur ingame)', 'info')
        return
    end
    local accountId = Platform.CallExport(CORE, 'GetCharacterAccount', characterId)
    if not accountId then
        Platform.Notify(source, 'Diesen Charakter gibt es nicht.', 'error')
        return
    end
    if not InventoryApi_ActiveCharacter(source) then
        Platform.Notify(source, 'Das geht nur mit einem Charakter.', 'error')
        return
    end
    Views.OpenAdmin(source, characterId)
    Platform.CallExport(CORE, 'Log', {
        actor_account_id = actorAccountId, account_id = accountId, character_id = characterId,
        category = 'admin', action = 'invsee', data = { online = InventoryApi_SourceOf(characterId) ~= nil },
    })
    Network.SendToClient(source, 'core_inventory:view', { kind = 'admin' })
end)
