-- Anbindung an die Core: wer spielt gerade, Anfragen vom Client, Admin-Befehle, Exports.

-- Braucht Core 1.6.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.6.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Emit', 'Export', 'GetPlayerDimension', 'GetVehicleInfo', 'GetPlayerPosition', 'Notify', 'OnEvent', 'OnResourceStop', 'Print', 'RegisterCommand', 'SetInterval', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    return
end

local CONSOLE = 0
local CORE = 'core'
local CFG = Config.Inventory

local handleStray       -- weiter unten: Items auf Plaetzen, die es nicht mehr gibt
local syncWeapon        -- weiter unten: Waffe in der Hand an den Client melden
local lastWeapon = {}   -- [source] = "item|seriennummer|munition", zuletzt an den Client gemeldet
local lastCash = {}     -- [source] = Bargeld, zuletzt an die Core gemeldet
local afterChange       -- weiter unten: Waffe, Bargeld und Kleidung nach jeder Aenderung abgleichen
local lastOutfit = {}   -- [source] = Kleidung, zuletzt an den Client gemeldet
local giveStartOutfit   -- weiter unten: Startoutfit einmal anziehen
local migrateCash       -- weiter unten: Bargeld aus der alten Spalte ins Inventar
local active = {}       -- [source] = permanente ID
local bySource = {}     -- [permanente ID] = source

------------------------------------------------------------------------
-- Wer spielt gerade (kommt von der Core)
------------------------------------------------------------------------

local function giveStartItems(inv)
    for _, item in ipairs(CFG.StartItems) do
        local ok, err = Inventory.Add(inv, item.name, item.count)
        if not ok then
            Platform.Print('warn', ('Startitem %s nicht vergeben: %s'):format(item.name, tostring(err)))
        end
    end
    Inventory.Save(inv)
end

local function onCharacterLoaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if not source or not characterId then
        return
    end
    active[source], bySource[characterId] = characterId, source
    local inv = Inventory.ForCharacter(characterId)
    local info = Platform.CallExport(CORE, 'GetCharacterInfo', source)
    inv.gender = type(info) == 'table' and info.gender or nil
    if inv.isNew then
        giveStartItems(inv)
        Platform.CallExport(CORE, 'Log', {
            account_id = Platform.CallExport(CORE, 'GetAccountId', source),
            character_id = characterId,
            category = 'item',
            action = 'start_items',
            data = { items = CFG.StartItems },
        })
    end
    Inventory.Bag(inv) -- Rucksack-Inhalt gleich mitladen
    handleStray(source, characterId, inv)
    migrateCash(source, characterId, inv)
    giveStartOutfit(source, characterId, inv)
    Documents.Sync(inv, characterId)
    lastWeapon[source], lastCash[source], lastOutfit[source] = nil, nil, nil
    afterChange(source)
    -- Haufen am Boden in seiner Dimension zeigen
    Network.SendToClient(source, 'core_inventory:drops', Drops.List(Platform.GetPlayerDimension(source)))
end

local function onCharacterUnloaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if source then
        active[source] = nil
        lastWeapon[source], lastCash[source], lastOutfit[source] = nil, nil, nil
    end
    if not characterId then
        return
    end
    bySource[characterId] = nil
    local inv = Inventory.Cached(Inventory.CharacterId(characterId))
    if inv then
        local bag = inv.slots.backpack and inv.slots.backpack.meta and inv.slots.backpack.meta.bagId
        if bag then
            Inventory.Unload(Inventory.Cached('bag:' .. bag))
        end
        Inventory.Unload(inv)
    end
end

Platform.OnEvent('core:characterLoaded', function(source, info)
    if type(info) == 'table' then
        Platform.Async(function()
            onCharacterLoaded(source, info.characterId)
        end)
    end
end)

Platform.OnEvent('core:characterUnloaded', function(source, characterId)
    onCharacterUnloaded(source, characterId)
end)

-- Neustart des Inventars, waehrend schon gespielt wird: alle laufenden Charaktere einlesen
DB.Ready(function()
    while not Inventory.Ready do
        Platform.Wait(100)
    end
    local list = Platform.CallExport(CORE, 'GetActiveCharacters') or {}
    for source, characterId in pairs(list) do
        onCharacterLoaded(source, characterId)
    end
end)

-- Core neu gestartet: alle sind wieder im Login
Platform.OnEvent('onResourceStop', function(resource)
    if resource == CORE then
        for source, characterId in pairs(active) do
            onCharacterUnloaded(source, characterId)
        end
    end
end)

Platform.OnResourceStop(function()
    Inventory.SaveAllNow()
end)

Platform.SetInterval(CFG.SaveIntervalMs, function()
    Inventory.SaveDirty(20)
end)

------------------------------------------------------------------------
-- Anfragen vom Client (nur mit gespieltem Charakter)
------------------------------------------------------------------------

local function register(name, handler)
    Network.RegisterCallback(name, function(source, data)
        local characterId = active[source]
        if not characterId or not Inventory.Ready then
            return { ok = false, error = 'no_character' }
        end
        local result = handler(source, Inventory.ForCharacter(characterId), data)
        afterChange(source)
        return result
    end)
end

-- Item-Liste fuer die UI (nur was sie zum Anzeigen braucht)
local function itemDefs()
    local list = {}
    for name, def in pairs(Items) do
        list[name] = { label = def.label, weight = def.weight, stack = def.stack or 1, equip = def.equip, description = def.description, money = def.money, weapon = def.weapon ~= nil or nil, document = def.document }
    end
    return list
end

local function position(source)
    return Platform.GetPlayerPosition(source)
end

local function dimension(source)
    return Platform.GetPlayerDimension(source)
end

-- Haufen in Reichweite oder nil
local function nearbyDrop(source)
    local pos = position(source)
    if not pos then
        return nil
    end
    return Drops.Nearest(pos, dimension(source), CFG.Drops.PickupDistance)
end

local function dropView(drop)
    return drop and { id = drop.id, items = Inventory.ListOf(drop.inv) } or nil
end

-- Alle in derselben Dimension bekommen die neue Liste der Haufen
local function broadcastDrops(dim)
    local list = Drops.List(dim)
    for source in pairs(active) do
        if dimension(source) == dim then
            Network.SendToClient(source, 'core_inventory:drops', list)
        end
    end
end

local function itemLog(source, characterId, action, data, extra)
    local entry = {
        actor_account_id = Platform.CallExport(CORE, 'GetAccountId', source),
        account_id = Platform.CallExport(CORE, 'GetAccountId', source),
        character_id = characterId,
        category = 'item',
        action = action,
        data = data,
    }
    for k, v in pairs(extra or {}) do
        entry[k] = v
    end
    Platform.CallExport(CORE, 'Log', entry)
end

-- Was nach einer Config-Aenderung keinen Platz mehr hat, kommt als Beutel neben den Spieler.
-- Kurz warten, bis er gespawnt ist, sonst stimmt die Position noch nicht.
local STRAY_DROP_DELAY_MS = 5000

handleStray = function(source, characterId, inv)
    local leftover = Inventory.Relocate(inv)
    if #leftover > 0 then
        Inventory.Save(inv)
    end
    if #leftover == 0 then
        return
    end
    Platform.Async(function()
        Platform.Wait(STRAY_DROP_DELAY_MS)
        local pos, dim = position(source), dimension(source)
        local items = {}
        for _, entry in ipairs(leftover) do
            items[#items + 1] = { item = entry.name, count = entry.count }
        end
        if not pos then
            itemLog(source, characterId, 'relocate_lost', { items = items })
            return
        end
        local drop = Drops.Create(pos, dim)
        for i, entry in ipairs(leftover) do
            drop.inv.slots[tostring(i)] = entry
        end
        itemLog(source, characterId, 'relocate_drop', { items = items, dropId = drop.id })
        Platform.Notify(source, 'Dein Inventar ist kleiner geworden. Was nicht mehr passte, liegt als Beutel neben dir.', 'info')
        broadcastDrops(dim)
    end)
end

-- Waffe in der Hand (Waffenplatz) an den Client melden, aber nur wenn sich etwas geaendert hat
syncWeapon = function(source)
    local characterId = source and active[source]
    if not characterId then
        return
    end
    local inv = Inventory.Cached(Inventory.CharacterId(characterId))
    local entry = inv and inv.slots.weapon
    local meta = entry and entry.meta or {}
    local id = meta.uid or meta.serial
    local key = entry and ('%s|%s|%s'):format(entry.name, tostring(id), tostring(meta.ammo)) or ''
    if lastWeapon[source] == key then
        return
    end
    lastWeapon[source] = key
    if entry then
        Network.SendToClient(source, 'core_inventory:weapon', { item = entry.name, id = id, ammo = meta.ammo })
    else
        Network.SendToClient(source, 'core_inventory:weapon', {})
    end
end

-- Bargeld an die Core melden, damit Geldanzeige und exports.core:GetMoney stimmen
local function syncCash(source)
    local characterId = source and active[source]
    local inv = characterId and Inventory.Cached(Inventory.CharacterId(characterId))
    if not inv then
        return
    end
    local cash = Inventory.Count(inv, 'cash')
    if lastCash[source] == cash then
        return
    end
    lastCash[source] = cash
    Platform.CallExport(CORE, 'SyncCash', source, cash)
end

-- Getragene Kleidung an den Client: welches Item in welchem Platz. Das Aussehen steht in data/clothing_*.lua.
local function syncOutfit(source)
    local characterId = source and active[source]
    local inv = characterId and Inventory.Cached(Inventory.CharacterId(characterId))
    if not inv then
        return
    end
    local worn, parts = {}, {}
    for _, slot in ipairs(CFG.EquipSlots) do
        local entry = slot.clothing and inv.slots[slot.id]
        if entry then
            worn[slot.id] = entry.name
            parts[#parts + 1] = slot.id .. '=' .. entry.name
        end
    end
    local key = (inv.gender or '?') .. '|' .. table.concat(parts, ',')
    if lastOutfit[source] == key then
        return
    end
    lastOutfit[source] = key
    Network.SendToClient(source, 'core_inventory:outfit', { gender = inv.gender, worn = worn })
end

afterChange = function(source, exceptViewer)
    syncWeapon(source)
    syncCash(source)
    syncOutfit(source)
    -- Wer dieses Inventar gerade im zweiten Fenster hat, sieht es neu
    Views.Touched(source, exceptViewer)
end

-- Startoutfit einmal pro Charakter. Bestehende Charaktere bekommen es auch, damit niemand
-- nach dem Update in Unterwaesche dasteht. Belegte Plaetze bleiben, wie sie sind.
giveStartOutfit = function(source, characterId, inv)
    if inv.flags.startOutfit then
        return
    end
    local outfit = CFG.StartOutfit and CFG.StartOutfit[inv.gender or 'male']
    if not outfit then
        return
    end
    local given = {}
    for _, item in ipairs(outfit) do
        local def = ItemDef(item)
        local look = ClothingLooks and ClothingLooks[item]
        if def and def.equip and not inv.slots[def.equip] and (not look or look[inv.gender or 'male']) then
            inv.slots[def.equip] = { name = item, count = 1 }
            given[#given + 1] = item
        end
    end
    inv.flags.startOutfit = true
    inv.dirty = true
    Inventory.Save(inv)
    if #given > 0 then
        itemLog(source, characterId, 'start_outfit', { items = given })
    end
end

-- Bis 0.5 lag Bargeld in characters.cash. Beim Einloggen ins Inventar holen, nur wenn es ganz passt.
migrateCash = function(source, characterId, inv)
    local amount = tonumber(Platform.CallExport(CORE, 'GetLegacyCash', characterId)) or 0
    if amount <= 0 then
        return
    end
    local ok = Inventory.Add(inv, 'cash', amount)
    if not ok then
        Platform.Notify(source, 'Dein Bargeld passt nicht ins Inventar. Mach einen Platz frei und logge neu ein.', 'error')
        return
    end
    if not Platform.CallExport(CORE, 'ClearLegacyCash', characterId, amount) then
        Inventory.Remove(inv, 'cash', amount)
        return
    end
    Inventory.Save(inv)
    itemLog(source, characterId, 'cash_migrated', { amount = amount })
end

local function snapshot(inv, slot, count)
    local entry = inv and inv.slots[slot]
    if not entry then
        return nil
    end
    local def = ItemDef(entry.name)
    return { item = entry.name, label = def and def.label, count = count or entry.count }
end

local function reply(ok, err, source, inv, drop)
    return { ok = ok, error = err, data = { state = Inventory.State(inv), drop = dropView(drop or nearbyDrop(source)), other = Views.StateFor(source) } }
end

register('inv_open', function(source, inv)
    return {
        ok = true,
        data = {
            items = itemDefs(),
            state = Inventory.State(inv),
            drop = dropView(nearbyDrop(source)),
            other = Views.StateFor(source),
            layout = {
                slots = CFG.Slots,
                hotbar = CFG.HotbarSlots,
                bagSlots = Inventory.MaxBagSlots,
                dropSlots = CFG.Drops.Slots,
                equip = CFG.EquipSlots,
                documents = CFG.Documents.Slots,
                giveDistance = CFG.GiveDistance,
            },
        },
    }
end)

-- Verschieben, auch zum und vom Boden. to.inv = 'drop' ohne id legt einen neuen Haufen an (oder auf den naechsten).
register('inv_move', function(source, inv, data)
    local from, to = data.from, data.to
    if type(from) ~= 'table' or type(to) ~= 'table' then
        return reply(false, 'invalid_slot', source, inv)
    end
    -- Zweites Fenster (Durchsuchen, Kofferraum, /invsee)
    if from.inv == 'other' or from.inv == 'otherbag' or to.inv == 'other' or to.inv == 'otherbag' then
        local ok, err = Views.Move(source, inv, data)
        return reply(ok, err, source, inv)
    end
    local drop, created = nil, false
    if from.inv == 'drop' or to.inv == 'drop' then
        local pos, dim = position(source), dimension(source)
        if not pos then
            return reply(false, 'no_position', source, inv)
        end
        local ref = from.inv == 'drop' and from or to
        drop = ref.id and Drops.Get(ref.id) or nil
        if ref.id and not Drops.InReach(drop, pos, dim) then
            return reply(false, 'drop_gone', source, inv)
        end
        if not drop then
            if from.inv == 'drop' then
                return reply(false, 'drop_gone', source, inv)
            end
            drop = Drops.Nearest(pos, dim, CFG.Drops.MergeDistance)
            if not drop then
                drop, created = Drops.Create(pos, dim), true
            end
        end
        -- Ohne Platzangabe: erster freier Platz im Haufen
        if to.inv == 'drop' and not tonumber(to.slot) then
            to = { inv = 'drop', slot = nil }
            for i = 1, Inventory.SlotLimit(drop.inv) do
                if not drop.inv.slots[tostring(i)] then
                    to.slot = tostring(i)
                    break
                end
            end
            if not to.slot then
                return reply(false, 'no_space', source, inv, drop)
            end
        end
    end

    local fromInv = from.inv == 'drop' and drop.inv or (from.inv == 'bag' and Inventory.Bag(inv) or inv)
    local moved = snapshot(fromInv, from.slot, data.count)
    local ok, err = Inventory.Move(inv, from, to, data.count, { drop = drop and drop.inv })
    if drop then
        if created and not ok then
            Drops.Touch(drop)
        end
        if ok then
            Drops.Touch(drop)
            if moved then
                local characterId = active[source]
                if to.inv == 'drop' then
                    itemLog(source, characterId, 'drop', moved, { amount = moved.count })
                elseif from.inv == 'drop' then
                    itemLog(source, characterId, 'pickup', moved, { amount = moved.count })
                end
            end
            broadcastDrops(drop.dimension)
        end
    end
    return reply(ok, err, source, inv, drop and Drops.Get(drop.id) or nil)
end)

-- Benutzen: Kleidung und Rucksack an- oder ablegen, sonst die Wirkung aus data/items.lua
-- Munition in die Waffe in der Hand laden: so viel wie passt, aus dem benutzten Stapel
local function loadAmmo(source, inv, ref, entry, def)
    local held = inv.slots.weapon
    local weapon = held and ItemDef(held.name)
    if not weapon or not weapon.weapon then
        return false, 'no_weapon'
    end
    if weapon.weapon.ammo ~= def.ammoType then
        return false, 'wrong_ammo'
    end
    held.meta = held.meta or {}
    local current = math.floor(tonumber(held.meta.ammo) or 0)
    local amount = math.min(entry.count, (weapon.weapon.maxAmmo or entry.count) - current)
    if amount <= 0 then
        return false, 'weapon_full'
    end
    local taken = Inventory.Take(inv, ref, amount)
    if not taken then
        return false, 'not_enough'
    end
    Inventory.Commit(inv, taken)
    held.meta.ammo = current + amount
    inv.dirty = true
    itemLog(source, active[source], 'load_ammo', { item = entry.name, weapon = held.name, serial = held.meta.serial, amount = amount, ammo = held.meta.ammo })
    Platform.Notify(source, ('%d Schuss geladen, jetzt %d.'):format(amount, held.meta.ammo), 'info')
    return true
end

local function useItem(source, inv, ref)
    if type(ref) ~= 'table' or (ref.inv ~= 'self' and ref.inv ~= 'bag' and ref.inv ~= nil) then
        return false, 'invalid_slot'
    end
    ref.inv = ref.inv or 'self'
    local container = ref.inv == 'bag' and Inventory.Bag(inv) or inv
    if not container or not Inventory.IsValidSlot(container, tostring(ref.slot)) then
        return false, 'invalid_slot'
    end
    ref.slot = tostring(ref.slot)
    local entry = container.slots[ref.slot]
    local held = inv.slots.weapon
    -- Leerer Platz, aus dem die Waffe in der Hand kam: wieder wegstecken (Taste 1 bis 5 zweimal)
    if not entry and container == inv and held and held.meta and held.meta.homeSlot == ref.slot then
        return Inventory.Move(inv, { inv = 'self', slot = 'weapon' }, { inv = 'self', slot = ref.slot })
    end
    if not entry then
        return false, 'empty_slot'
    end
    local def = ItemDef(entry.name)

    -- Angezogen oder in der Hand: zurueck (Waffe dorthin, wo sie herkam), sonst in einen freien Taschenplatz
    if container == inv and Inventory.EquipSlot(ref.slot) then
        local home = ref.slot == 'weapon' and entry.meta and entry.meta.homeSlot
        local free = (home and not inv.slots[home] and Inventory.IsValidSlot(inv, home)) and home or Inventory.FreePocket(inv)
        if not free then
            return false, 'no_space'
        end
        return Inventory.Move(inv, ref, { inv = 'self', slot = free })
    end
    -- Waffe ziehen: merken, aus welchem Platz sie kam
    if def.equip == 'weapon' then
        local ok, err = Inventory.Move(inv, ref, { inv = 'self', slot = 'weapon' })
        if ok and container == inv and inv.slots.weapon then
            inv.slots.weapon.meta = inv.slots.weapon.meta or {}
            inv.slots.weapon.meta.homeSlot = ref.slot
            inv.dirty = true
        end
        return ok, err
    end
    -- Ausruestung: anziehen
    if def.equip then
        return Inventory.Move(inv, ref, { inv = 'self', slot = def.equip })
    end
    local use = def.use
    if not use then
        return false, 'not_usable'
    end
    local characterId = active[source]
    local name, meta = entry.name, entry.meta
    if use.loadAmmo then
        return loadAmmo(source, inv, ref, entry, def)
    end
    if use.remove and use.remove > 0 then
        local taken = Inventory.Take(inv, ref, use.remove)
        if not taken then
            return false, 'not_enough'
        end
        Inventory.Commit(inv, taken)
    end
    if use.health then
        Network.SendToClient(source, 'core_inventory:effect', { health = use.health })
    end
    if use.hunger or use.thirst then
        Platform.CallExport(CORE, 'AddNeeds', source, { hunger = use.hunger, thirst = use.thirst })
    end
    if use.message then
        Platform.Notify(source, use.message, 'info')
    end
    itemLog(source, characterId, 'use', { item = name, label = def.label })
    Platform.Emit('core_inventory:itemUsed', source, characterId, name, meta)
    return true
end

-- Munitionsstand vom Client: darf nur sinken. Nachladen geht nur ueber das Inventar.
register('inv_ammo', function(source, inv, data)
    local held = inv.slots.weapon
    local ammo = math.floor(tonumber(data.ammo) or -1)
    local heldId = held and held.meta and (held.meta.uid or held.meta.serial)
    if not heldId or heldId ~= data.id or ammo < 0 then
        return { ok = false, error = 'no_weapon' }
    end
    if ammo < (tonumber(held.meta.ammo) or 0) then
        held.meta.ammo = ammo
        inv.dirty = true
        -- Der Client kennt den Stand schon, nicht noch einmal schicken
        lastWeapon[source] = ('%s|%s|%s'):format(held.name, tostring(heldId), tostring(ammo))
    end
    return { ok = true }
end)

register('inv_use', function(source, inv, data)
    local ok, err = useItem(source, inv, { inv = data.inv, slot = data.slot })
    return reply(ok, err, source, inv)
end)

-- Geben an einen Spieler in der Naehe
register('inv_give', function(source, inv, data)
    local target = tonumber(data.target)
    local targetCharacter = target and active[target]
    if not targetCharacter or target == source then
        return reply(false, 'target_offline', source, inv)
    end
    local a, b = position(source), position(target)
    if not a or not b or dimension(source) ~= dimension(target) then
        return reply(false, 'too_far', source, inv)
    end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    if math.sqrt(dx * dx + dy * dy + dz * dz) > CFG.GiveDistance then
        return reply(false, 'too_far', source, inv)
    end
    local taken, err = Inventory.Take(inv, data.from, data.count)
    if not taken then
        return reply(false, err, source, inv)
    end
    local def = ItemDef(taken.entry.name)
    local characterId = active[source]
    local info = { item = taken.entry.name, label = def.label, count = taken.count, toCharacterId = targetCharacter, fromCharacterId = characterId }

    -- Zwischen eigenen Charakteren: wie bei Geld melden oder sperren (Config.Twinks der Core)
    local allowed = Platform.CallExport(CORE, 'ReportTwinkInteraction', characterId, targetCharacter, 'item_give',
        { label = 'Item gegeben', item = taken.entry.name, itemLabel = def.label, count = taken.count })
    if allowed == false then
        return reply(false, 'twink_blocked', source, inv)
    end

    local targetInv = Inventory.ForCharacter(targetCharacter)
    local ok, addErr = Inventory.Add(targetInv, taken.entry.name, taken.count, taken.entry.meta)
    if not ok then
        return reply(false, addErr == 'too_heavy' and 'target_too_heavy' or 'target_full', source, inv)
    end
    Inventory.Commit(inv, taken)

    itemLog(source, characterId, 'give', info, {
        amount = taken.count,
        target_account_id = Platform.CallExport(CORE, 'GetAccountId', target),
    })
    Platform.Notify(source, ('Du hast ID %d %dx %s gegeben.'):format(targetCharacter, taken.count, def.label), 'success')
    Platform.Notify(target, ('ID %d hat dir %dx %s gegeben.'):format(characterId, taken.count, def.label), 'info')
    Network.SendToClient(target, 'core_inventory:changed', {})
    afterChange(target)
    return reply(true, nil, source, inv)
end)

-- Haufen in derselben Dimension, z. B. nach dem Einloggen
register('inv_drops', function(source)
    return { ok = true, data = Drops.List(dimension(source)) }
end)

-- Abgelaufene Haufen entfernen und ins Log schreiben
Platform.SetInterval(Drops.CleanupIntervalMs, function()
    local removed = Drops.Expire()
    local dims = {}
    for _, drop in ipairs(removed) do
        Platform.CallExport(CORE, 'Log', {
            category = 'item',
            action = 'drop_expired',
            data = { items = Inventory.ListOf(drop.inv), position = drop.position },
        })
        dims[drop.dimension] = true
    end
    for dim in pairs(dims) do
        broadcastDrops(dim)
    end
end)

------------------------------------------------------------------------
-- Fuer andere Scripts (exports.core_inventory:...)
------------------------------------------------------------------------

-- Charakter laden, auch wenn er offline ist. Gibt das Inventar und ob es danach wieder entladen werden soll.
local function withCharacter(characterId, fn)
    characterId = tonumber(characterId)
    if not characterId or not Inventory.Ready then
        return false, 'not_ready'
    end
    local online = bySource[characterId] ~= nil
    local inv = Inventory.ForCharacter(characterId)
    local results = table.pack(fn(inv))
    if online then
        afterChange(bySource[characterId])
    end
    if not online then
        local bagId = inv.slots.backpack and inv.slots.backpack.meta and inv.slots.backpack.meta.bagId
        if bagId then
            Inventory.Unload(Inventory.Cached('bag:' .. bagId))
        end
        Inventory.Unload(inv)
    end
    return table.unpack(results, 1, results.n)
end

-- Fuer documents.lua und spaetere Teile: Inventar eines Charakters bearbeiten (auch offline)
function InventoryApi_WithCharacter(characterId, fn)
    return withCharacter(characterId, fn)
end

function InventoryApi_AfterChange(source, exceptViewer)
    afterChange(source, exceptViewer)
end

function InventoryApi_ActiveCharacter(source)
    return source and active[source] or nil
end

function InventoryApi_SourceOf(characterId)
    return bySource[tonumber(characterId)]
end

function InventoryApi_AddItem(characterId, name, count, meta)
    return withCharacter(characterId, function(inv)
        return Inventory.Add(inv, name, count, meta)
    end)
end

function InventoryApi_RemoveItem(characterId, name, count)
    return withCharacter(characterId, function(inv)
        return Inventory.Remove(inv, name, count)
    end)
end

function InventoryApi_Count(characterId, name)
    return withCharacter(characterId, function(inv)
        return Inventory.Count(inv, name)
    end)
end

Platform.Export('AddItem', InventoryApi_AddItem)
Platform.Export('RemoveItem', InventoryApi_RemoveItem)
Platform.Export('GetItemCount', InventoryApi_Count)
-- Fuer die Akte: Anzeige-Namen und Aufbau
Platform.Export('GetItemDefs', function()
    return itemDefs()
end)
Platform.Export('GetLayout', function()
    return { slots = CFG.Slots, hotbar = CFG.HotbarSlots, bagSlots = Inventory.MaxBagSlots, equip = CFG.EquipSlots }
end)
Platform.Export('GetInventory', function(characterId)
    return withCharacter(characterId, function(inv)
        return Inventory.State(inv)
    end)
end)

------------------------------------------------------------------------
-- Admin-Befehle (Recht items.manage, Pruefung und Log macht die Core)
------------------------------------------------------------------------

local ERRORS = {
    unknown_item = 'Dieses Item gibt es nicht. Namen stehen in data/items.lua.',
    invalid_count = 'Gib eine Anzahl ab 1 an.',
    too_heavy = 'Das ist zu schwer für das Inventar.',
    no_space = 'Im Inventar ist kein Platz mehr.',
    not_enough = 'So viele hat die Person nicht.',
    not_ready = 'Das Inventar ist noch nicht bereit.',
}

local function adminItemCommand(name, usage, apply, logAction, doneText, targetText)
    Platform.RegisterCommand(name, function(source, args)
        local allowed, actorAccountId = Platform.CallExport(CORE, 'AuthorizeCommand', source, name, 'items.manage', args, true)
        if not allowed then
            return
        end
        local characterId, itemName = tonumber(args[1]), args[2] and args[2]:lower() or nil
        -- "illegal" am Ende: Waffe ohne Seriennummer
        local illegal = args[#args] and args[#args]:lower() == 'illegal'
        local countArg = args[3] and args[3]:lower() ~= 'illegal' and args[3] or nil
        local count = countArg and math.floor(tonumber(countArg) or 0) or 1
        if not characterId or not itemName then
            Platform.Notify(source, usage, 'info')
            return
        end
        local def = ItemDef(itemName)
        if not def then
            Platform.Notify(source, ERRORS.unknown_item, 'error')
            return
        end
        if count < 1 or count > CFG.MaxCountPerCommand then
            Platform.Notify(source, ('Gib eine Anzahl von 1 bis %d an.'):format(CFG.MaxCountPerCommand), 'error')
            return
        end
        local accountId = Platform.CallExport(CORE, 'GetCharacterAccount', characterId)
        if not accountId then
            Platform.Notify(source, 'Diesen Charakter gibt es nicht.', 'error')
            return
        end

        if illegal and not def.weapon then
            Platform.Notify(source, 'Nur Waffen können illegal sein.', 'error')
            return
        end
        local ok, err = apply(characterId, itemName, count, illegal and { illegal = true } or nil)
        if not ok then
            Platform.Notify(source, ERRORS[err] or tostring(err), 'error')
            return
        end
        Platform.CallExport(CORE, 'Log', {
            actor_account_id = actorAccountId,
            account_id = accountId,
            character_id = characterId,
            category = 'item',
            action = logAction,
            amount = count,
            data = { item = itemName, label = def.label, illegal = illegal or nil, console = source == CONSOLE or nil },
        })
        Platform.Notify(source, doneText:format(count, def.label, characterId), 'success')
        local target = bySource[characterId]
        if target then
            Platform.Notify(target, targetText:format(count, def.label), 'info')
            Network.SendToClient(target, 'core_inventory:changed', {})
        end
    end)
end

adminItemCommand('giveitem', 'Benutzung: /giveitem <permanente ID> <item> [anzahl], z. B. /giveitem 17 water 3',
    InventoryApi_AddItem, 'admin_give', '%dx %s an ID %d gegeben.', 'Ein Teammitglied hat dir %dx %s gegeben.')
adminItemCommand('removeitem', 'Benutzung: /removeitem <permanente ID> <item> [anzahl], z. B. /removeitem 17 water 1',
    InventoryApi_RemoveItem, 'admin_remove', '%dx %s von ID %d entfernt.', 'Ein Teammitglied hat dir %dx %s abgenommen.')

-- In der Befehlsliste des Admin-Menues zeigen
DB.Ready(function()
    Platform.CallExport(CORE, 'AddCommandHelp', {
        title = 'Inventar',
        entries = {
            { usage = '/giveitem 17 water 3', text = 'Items geben. Geht auch offline. Namen stehen in data/items.lua.', permission = 'items.manage' },
            { usage = '/giveitem 17 weapon_pistol illegal', text = 'Illegale Waffe ohne Seriennummer geben. Legale Waffen kommen ins Waffenregister.', permission = 'items.manage' },
            { usage = '/removeitem 17 water 1', text = 'Items abnehmen, auch angezogene Kleidung.', permission = 'items.manage' },
        },
    })
end)
