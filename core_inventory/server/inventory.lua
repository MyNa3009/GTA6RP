-- Inventar-Logik: Plaetze, Gewicht, Stapeln, Ausruestung, Rucksack, Speichern.
-- Plattformunabhaengig: nur Datenbank (DB), Platform und die Item-Liste.
--
-- Aufbau eines Charakter-Inventars (id "char:<permanente ID>"):
--   Plaetze "1" bis "10"  Taschen, 1 bis 5 sind der Schnellzugriff
--   "mask" ... "shoes"    Kleidung (zaehlt nicht zum Gewicht)
--   "weapon"              Waffe in der Hand
--   "backpack"            Rucksack (Level 1 bis 4). Sein Inhalt ist ein eigenes Inventar "bag:<id>" und reist mit dem Rucksack.
--                         Wie viele Plaetze und kg er hat, bestimmt sein Level (Config.Inventory.Backpacks).

Inventory = { Ready = false }

local CREATE_TABLE = [[
    CREATE TABLE IF NOT EXISTS inventories (
        id         VARCHAR(64) NOT NULL PRIMARY KEY,   -- char:17, bag:65a3f2c1
        data       JSON NOT NULL,                      -- { "slots": { "1": { "name": "water", "count": 2 } } }
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

local CFG = Config.Inventory
local LOAD_WAIT_MS = 20

local EQUIP = {}          -- [slotId] = { label, clothing }
local NO_WEIGHT = {}      -- getragene Kleidung und der Rucksack selbst
for _, slot in ipairs(CFG.EquipSlots) do
    EQUIP[slot.id] = slot
    if slot.clothing or slot.id == 'backpack' then
        NO_WEIGHT[slot.id] = true
    end
end

-- Groesstes Rucksack-Level: so viele Plaetze zeigt das Fenster, und so gross ist ein Rucksack ohne Level
local MAX_BAG = { slots = 0, maxWeight = 0, level = 0 }
for level, bag in pairs(CFG.Backpacks) do
    if bag.slots > MAX_BAG.slots then
        MAX_BAG = { slots = bag.slots, maxWeight = bag.maxWeight, level = level }
    end
end
Inventory.MaxBagSlots = MAX_BAG.slots

-- Dokumente: eigene Plaetze, gebunden an den Charakter, wiegen nichts
local DOC_SLOT = {}       -- [slotId] = item
local DOC_SLOT_OF = {}    -- [item] = slotId
for _, slot in ipairs(CFG.Documents.Slots) do
    DOC_SLOT[slot.id] = slot.item
    DOC_SLOT_OF[slot.item] = slot.id
    NO_WEIGHT[slot.id] = true
end
Inventory.DocumentSlotOf = function(item) return DOC_SLOT_OF[item] end

local function isDocument(name)
    local def = ItemDef(name)
    return def ~= nil and def.document ~= nil
end
Inventory.IsDocument = isDocument

local cache = {}          -- [id] = Inventar im Speicher
local loading = {}        -- [id] = true, solange es aus der Datenbank geladen wird

DB.Ready(function()
    if DB.Query(CREATE_TABLE) == nil then
        Platform.Print('error', 'Tabelle inventories konnte nicht angelegt werden. Bitte database/inventory.sql ausfuehren.')
        return
    end
    Inventory.Ready = true
end)

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

local function copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[k] = copy(v)
    end
    return result
end

local function isEmptyMeta(meta)
    return meta == nil or next(meta) == nil
end

-- Nur Items ohne eigene Metadaten (Seriennummer, Aussehen ...) duerfen zusammen in einen Platz
local function canStack(a, b)
    local def = ItemDef(a.name)
    return a.name == b.name and def and (def.stack or 1) > 1 and isEmptyMeta(a.meta) and isEmptyMeta(b.meta)
end

local function stackSize(name)
    local def = ItemDef(name)
    return def and def.stack or 1
end

local function isBagItem(name)
    local def = ItemDef(name)
    return def ~= nil and def.equip == 'backpack'
end

-- Plaetze und kg eines Rucksack-Items nach seinem Level
local function bagCapacity(name)
    local def = ItemDef(name)
    local level = def and tonumber(def.bagLevel)
    local bag = level and CFG.Backpacks[level]
    if bag then
        return { slots = bag.slots, maxWeight = bag.maxWeight, level = level }
    end
    return MAX_BAG
end

-- Kofferraum und Lager: Groesse kommt von aussen (Fahrzeugklasse, Lager-Script)
local FIXED_CAPACITY = { trunk = true, stash = true }

local function slotLimit(inv)
    if FIXED_CAPACITY[inv.kind] then
        return inv.capacity and inv.capacity.slots or 0
    end
    if inv.kind == 'bag' then
        return (inv.capacity or MAX_BAG).slots
    elseif inv.kind == 'drop' then
        return CFG.Drops.Slots
    end
    return CFG.Slots
end
Inventory.SlotLimit = slotLimit

local function isPocket(inv, slot)
    local n = tonumber(slot)
    return n ~= nil and n == math.floor(n) and n >= 1 and n <= slotLimit(inv) and tostring(n) == slot
end

function Inventory.IsValidSlot(inv, slot)
    if type(slot) ~= 'string' then
        return false
    end
    if isPocket(inv, slot) then
        return true
    end
    return inv.kind == 'character' and (EQUIP[slot] ~= nil or DOC_SLOT[slot] ~= nil)
end

-- Gewicht eines Eintrags. Ein Rucksack wiegt sein eigenes Gewicht plus seinen Inhalt.
local function entryWeight(entry)
    local def = ItemDef(entry.name)
    local weight = (def and def.weight or 0) * entry.count
    if entry.meta and tonumber(entry.meta.contentWeight) then
        weight = weight + tonumber(entry.meta.contentWeight)
    end
    return weight
end

local function weightOf(inv, slots)
    local total = 0
    for slot, entry in pairs(slots or inv.slots) do
        if not (inv.kind == 'character' and NO_WEIGHT[slot]) then
            total = total + entryWeight(entry)
        end
    end
    return total
end
Inventory.Weight = weightOf

function Inventory.MaxWeight(inv)
    if FIXED_CAPACITY[inv.kind] then
        return inv.capacity and inv.capacity.maxWeight or 0
    end
    if inv.kind == 'bag' then
        return (inv.capacity or MAX_BAG).maxWeight
    elseif inv.kind == 'drop' then
        return math.huge
    end
    return CFG.MaxWeight
end

-- Passt das Item in diesen Platz? (nur die Art, nicht das Gewicht)
local function fitsSlot(inv, slot, entry)
    if not Inventory.IsValidSlot(inv, slot) then
        return false, 'invalid_slot'
    end
    local def = ItemDef(entry.name)
    if not def then
        return false, 'unknown_item'
    end
    if inv.kind == 'bag' and def.equip == 'backpack' then
        return false, 'bag_in_bag'
    end
    if EQUIP[slot] and inv.kind == 'character' and def.equip ~= slot then
        return false, 'wrong_slot'
    end
    -- Kleidung ist fuer ein Koerpermodell gemacht (ClothingLooks), inv.gender setzt api.lua beim Einloggen
    local look = ClothingLooks and ClothingLooks[entry.name]
    if EQUIP[slot] and inv.gender and look and not look[inv.gender] then
        return false, 'wrong_gender'
    end
    return true
end

-- Seriennummer fuer Waffen, z. B. "SN-7KQ4-X2MD". Ohne leicht verwechselbare Zeichen (0/O, 1/I).
local SERIAL_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

local function newSerial()
    local parts = {}
    for i = 1, 8 do
        local n = math.random(1, #SERIAL_CHARS)
        parts[i] = SERIAL_CHARS:sub(n, n)
    end
    return ('SN-%s-%s'):format(table.concat(parts, '', 1, 4), table.concat(parts, '', 5, 8))
end

-- Interne Kennung jeder Waffe (auch illegaler), damit Server und Client wissen, welche gerade in der Hand ist
local function newWeaponId()
    return ('%x%06x'):format(os.time(), math.random(0, 0xFFFFFF))
end

-- Neue Waffe: leeres Magazin, interne Kennung und bei legalen Waffen eine Seriennummer.
-- meta.illegal = true beim Anlegen heisst: ohne Seriennummer (Schwarzmarkt, Crafting).
-- Gibt die Metadaten zurueck und, falls eine neue Seriennummer vergeben wurde, diese.
local function withWeaponMeta(name, meta)
    local def = ItemDef(name)
    if not (def and def.weapon) then
        return meta
    end
    meta = meta or {}
    meta.uid = meta.uid or newWeaponId()
    local created = nil
    if meta.illegal then
        meta.illegal = nil
        meta.serial = nil
    elseif not meta.serial then
        meta.serial = newSerial()
        created = meta.serial
    end
    if def.weapon.ammo then
        meta.ammo = math.max(0, math.floor(tonumber(meta.ammo) or 0))
    end
    return meta, created
end

-- Wird gesetzt von api.lua: neue legale Waffe ins Register (Seriennummer, Item, Besitzer)
Inventory.OnWeaponRegistered = nil
Inventory.WithWeaponMeta = withWeaponMeta

local function newBagId()
    return ('%x%06x'):format(os.time(), math.random(0, 0xFFFFFF))
end

------------------------------------------------------------------------
-- Laden und Speichern
------------------------------------------------------------------------

-- Gibt die Plaetze und Merker (flags, z. B. "Startoutfit schon bekommen") zurueck
local function decode(text)
    local data = Platform.JsonDecode(text)
    local slots = {}
    local flags = type(data) == 'table' and type(data.flags) == 'table' and data.flags or {}
    if type(data) == 'table' and type(data.slots) == 'table' then
        for slot, entry in pairs(data.slots) do
            if type(entry) == 'table' and ItemAliases[entry.name] then
                entry.name = ItemAliases[entry.name]
            end
            if type(entry) == 'table' and ItemDef(entry.name) and tonumber(entry.count) and entry.count > 0 then
                slots[tostring(slot)] = { name = entry.name, count = math.floor(entry.count), meta = type(entry.meta) == 'table' and entry.meta or nil }
            end
        end
    end
    return slots, flags
end

local function encode(inv)
    local slots = {}
    for slot, entry in pairs(inv.slots) do
        slots[slot] = { name = entry.name, count = entry.count, meta = not isEmptyMeta(entry.meta) and entry.meta or nil }
    end
    local flags = inv.flags and next(inv.flags) and inv.flags or nil
    return Platform.JsonEncode({ slots = next(slots) and slots or nil, flags = flags })
end

-- Laedt ein Inventar (aus dem Speicher oder der Datenbank). kind: 'character' oder 'bag'
function Inventory.Load(id, kind)
    if cache[id] then
        return cache[id]
    end
    while loading[id] do
        Platform.Wait(LOAD_WAIT_MS)
    end
    if cache[id] then
        return cache[id]
    end
    loading[id] = true
    local row = DB.Single('SELECT data FROM inventories WHERE id = ?', { id })
    local slots, flags = {}, {}
    if row then
        slots, flags = decode(row.data)
    end
    local inv = { id = id, kind = kind, slots = slots, flags = flags, dirty = false, isNew = row == nil }
    cache[id] = inv
    loading[id] = nil
    return inv
end

function Inventory.Save(inv)
    if not inv or inv.transient then
        return false
    end
    inv.dirty = false
    local ok = DB.Update(
        'INSERT INTO inventories (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { inv.id, encode(inv) }
    )
    if ok == nil then
        inv.dirty = true
        Platform.Print('error', ('Inventar %s konnte nicht gespeichert werden.'):format(inv.id))
        return false
    end
    inv.isNew = false
    return true
end

-- Aus dem Speicher nehmen (vorher speichern)
function Inventory.Unload(inv)
    if not inv then
        return
    end
    if inv.dirty then
        Inventory.Save(inv)
    end
    cache[inv.id] = nil
end

function Inventory.MarkDirty(inv)
    inv.dirty = true
end

-- Alle geaenderten Inventare, verteilt, damit nicht alles im selben Moment schreibt
function Inventory.SaveDirty(spreadMs)
    for _, inv in pairs(cache) do
        if inv.dirty and not inv.transient then
            Inventory.Save(inv)
            if spreadMs and spreadMs > 0 then
                Platform.Wait(spreadMs)
            end
        end
    end
end

-- Beim Stoppen: ohne Warten in die Warteschlange der Datenbank
function Inventory.SaveAllNow()
    for _, inv in pairs(cache) do
        if inv.dirty and not inv.transient then
            DB.Fire(
                'INSERT INTO inventories (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
                { inv.id, encode(inv) }
            )
            inv.dirty = false
        end
    end
end

function Inventory.Cached(id)
    return cache[id]
end

------------------------------------------------------------------------
-- Charakter und Rucksack
------------------------------------------------------------------------

function Inventory.CharacterId(characterId)
    return 'char:' .. tostring(characterId)
end

function Inventory.ForCharacter(characterId)
    return Inventory.Load(Inventory.CharacterId(characterId), 'character')
end

-- Inhalt des angelegten Rucksacks oder nil
function Inventory.Bag(charInv)
    local backpack = charInv.slots.backpack
    if not backpack then
        return nil
    end
    backpack.meta = backpack.meta or {}
    if not backpack.meta.bagId then
        backpack.meta.bagId = newBagId()
        charInv.dirty = true
    end
    local bag = Inventory.Load('bag:' .. backpack.meta.bagId, 'bag')
    bag.capacity = bagCapacity(backpack.name)
    return bag
end

-- Gewicht des Rucksack-Inhalts am Rucksack merken, damit er mit Inhalt wiegt, wenn man ihn ablegt oder weitergibt
local function syncBagWeight(charInv, bag)
    local backpack = charInv.slots.backpack
    if backpack and bag then
        local weight = weightOf(bag)
        backpack.meta = backpack.meta or {}
        if backpack.meta.contentWeight ~= weight then
            backpack.meta.contentWeight = weight > 0 and weight or nil
            charInv.dirty = true
        end
    end
end

------------------------------------------------------------------------
-- Zaehlen, Hinzufuegen, Entfernen (fuer Befehle und andere Scripts)
------------------------------------------------------------------------

-- Taschen zuerst, dann Rucksack, dann Ausruestung
local function containers(charInv)
    local list = { charInv }
    local bag = Inventory.Bag(charInv)
    if bag then
        list[#list + 1] = bag
    end
    return list
end

local function sortedSlots(inv)
    local list = {}
    for i = 1, slotLimit(inv) do
        list[#list + 1] = tostring(i)
    end
    return list
end

function Inventory.Count(charInv, name)
    local total = 0
    for _, inv in ipairs(containers(charInv)) do
        for _, entry in pairs(inv.slots) do
            if entry.name == name then
                total = total + entry.count
            end
        end
    end
    return total
end

-- Fuegt count Stueck hinzu: erst auf passende Stapel, dann in freie Plaetze, Taschen vor Rucksack.
-- Alles oder nichts. Gibt true oder false und 'too_heavy' / 'no_space' / 'unknown_item' zurueck.
function Inventory.Add(charInv, name, count, meta)
    local def = ItemDef(name)
    count = math.floor(tonumber(count) or 0)
    if not def then
        return false, 'unknown_item'
    end
    -- Dokumente gehen direkt in ihren Platz, nur bei Charakteren und nur einmal
    if def.document then
        local slot = DOC_SLOT_OF[name]
        if charInv.kind ~= 'character' or not slot then
            return false, 'bound'
        end
        if charInv.slots[slot] then
            charInv.slots[slot].meta = copy(meta) or charInv.slots[slot].meta
            charInv.dirty = true
            return true
        end
        charInv.slots[slot] = { name = name, count = 1, meta = copy(meta) }
        charInv.dirty = true
        return true
    end
    if count < 1 then
        return false, 'invalid_count'
    end
    if not isEmptyMeta(meta) and count > 1 then
        -- Items mit eigenen Daten einzeln anlegen
        for _ = 1, count do
            local ok, err = Inventory.Add(charInv, name, 1, copy(meta))
            if not ok then
                return false, err
            end
        end
        return true
    end

    local plan, weights, remaining = {}, {}, count
    local blockedByWeight = false
    local unit = def.weight or 0
    local stack = def.stack or 1
    local probe = { name = name, count = 1, meta = meta }

    local function capacity(inv)
        if unit <= 0 then
            return math.huge
        end
        local free = Inventory.MaxWeight(inv) - (weights[inv.id] or weightOf(inv))
        return math.max(0, math.floor(free / unit))
    end

    local function place(inv, slot, amount, existing)
        plan[#plan + 1] = { inv = inv, slot = slot, amount = amount, existing = existing }
        weights[inv.id] = (weights[inv.id] or weightOf(inv)) + unit * amount
        remaining = remaining - amount
    end

    local boxes = containers(charInv)
    -- 1. Auf vorhandene Stapel
    if stack > 1 and isEmptyMeta(meta) then
        for _, inv in ipairs(boxes) do
            for _, slot in ipairs(sortedSlots(inv)) do
                local entry = inv.slots[slot]
                if remaining > 0 and entry and canStack(entry, probe) and entry.count < stack then
                    local amount = math.min(remaining, stack - entry.count, capacity(inv))
                    if amount > 0 then
                        place(inv, slot, amount, true)
                    elseif capacity(inv) == 0 then
                        blockedByWeight = true
                    end
                end
            end
        end
    end
    -- 2. In freie Plaetze
    for _, inv in ipairs(boxes) do
        for _, slot in ipairs(sortedSlots(inv)) do
            if remaining <= 0 then
                break
            end
            if not inv.slots[slot] and fitsSlot(inv, slot, probe) then
                local used = false
                for _, step in ipairs(plan) do
                    if step.inv == inv and step.slot == slot then
                        used = true
                    end
                end
                if not used then
                    local amount = math.min(remaining, stack, capacity(inv))
                    if amount > 0 then
                        place(inv, slot, amount, false)
                    else
                        blockedByWeight = true
                    end
                end
            end
        end
    end

    if remaining > 0 then
        return false, blockedByWeight and 'too_heavy' or 'no_space'
    end
    local registered = {}
    for _, step in ipairs(plan) do
        if step.existing then
            step.inv.slots[step.slot].count = step.inv.slots[step.slot].count + step.amount
        else
            local itemMeta, serial = withWeaponMeta(name, copy(meta))
            step.inv.slots[step.slot] = { name = name, count = step.amount, meta = itemMeta }
            if serial then
                registered[#registered + 1] = serial
            end
        end
        step.inv.dirty = true
    end
    if #registered > 0 and Inventory.OnWeaponRegistered and charInv.kind == 'character' then
        for _, serial in ipairs(registered) do
            Inventory.OnWeaponRegistered(serial, name, tonumber(charInv.id:match('^char:(%d+)$')))
        end
    end
    if def.equip == 'backpack' then
        Inventory.EnsureBagIds(charInv)
    end
    syncBagWeight(charInv, Inventory.Bag(charInv))
    return true
end

-- Jeder Rucksack bekommt beim Anlegen eine eigene Inhalts-ID
function Inventory.EnsureBagIds(charInv)
    for _, entry in pairs(charInv.slots) do
        if isBagItem(entry.name) then
            entry.meta = entry.meta or {}
            if not entry.meta.bagId then
                entry.meta.bagId = newBagId()
                charInv.dirty = true
            end
        end
    end
end

-- Entfernt count Stueck: Taschen, dann Rucksack, dann Ausruestung. Alles oder nichts.
function Inventory.Remove(charInv, name, count)
    count = math.floor(tonumber(count) or 0)
    if count < 1 then
        return false, 'invalid_count'
    end
    if Inventory.Count(charInv, name) < count then
        return false, 'not_enough'
    end
    local remaining = count
    local bag = Inventory.Bag(charInv)
    local order = {}
    for _, slot in ipairs(sortedSlots(charInv)) do order[#order + 1] = { charInv, slot } end
    if bag then
        for _, slot in ipairs(sortedSlots(bag)) do order[#order + 1] = { bag, slot } end
    end
    for _, slot in ipairs(CFG.EquipSlots) do order[#order + 1] = { charInv, slot.id } end
    for _, slot in ipairs(CFG.Documents.Slots) do order[#order + 1] = { charInv, slot.id } end

    for _, pair in ipairs(order) do
        local inv, slot = pair[1], pair[2]
        local entry = inv.slots[slot]
        if remaining > 0 and entry and entry.name == name then
            local amount = math.min(remaining, entry.count)
            entry.count = entry.count - amount
            remaining = remaining - amount
            if entry.count <= 0 then
                inv.slots[slot] = nil
            end
            inv.dirty = true
        end
    end
    syncBagWeight(charInv, Inventory.Bag(charInv))
    return true
end

------------------------------------------------------------------------
-- Verschieben (Ziehen und Ablegen im Inventar)
------------------------------------------------------------------------

-- ref: { inv = 'self' | 'bag' | 'drop', slot = '3' | 'jacket' }. Ein Haufen am Boden kommt ueber extra.drop.
local function resolve(charInv, ref, extra)
    if type(ref) ~= 'table' or type(ref.slot) ~= 'string' then
        return nil
    end
    if ref.inv == 'bag' then
        return Inventory.Bag(charInv)
    end
    if ref.inv == 'drop' then
        return extra and extra.drop or nil
    end
    -- Zweites Fenster: fremdes Inventar (Durchsuchen, Kofferraum, /invsee) und dessen Rucksack
    if ref.inv == 'other' then
        return extra and extra.other or nil
    end
    if ref.inv == 'otherbag' then
        return extra and extra.otherBag or nil
    end
    if ref.inv == 'self' or ref.inv == nil then
        return charInv
    end
    return nil
end

-- Verschiebt, teilt, stapelt oder tauscht. Gibt true oder false und einen Fehlercode zurueck.
-- Fehlercodes: invalid_slot, empty_slot, invalid_count, wrong_slot, bag_in_bag, too_heavy, no_bag, stack_full
function Inventory.Move(charInv, from, to, count, extra)
    local fromInv, toInv = resolve(charInv, from, extra), resolve(charInv, to, extra)
    if not fromInv or not toInv then
        return false, 'no_bag'
    end
    if not Inventory.IsValidSlot(fromInv, from.slot) or not Inventory.IsValidSlot(toInv, to.slot) then
        return false, 'invalid_slot'
    end
    local source = fromInv.slots[from.slot]
    if not source then
        return false, 'empty_slot'
    end
    if fromInv == toInv and from.slot == to.slot then
        return true
    end
    -- Dokumente bleiben, wo sie sind; in Dokument-Plaetze kommt nichts anderes
    if isDocument(source.name) or DOC_SLOT[to.slot] then
        return false, 'bound'
    end
    count = count == nil and source.count or math.floor(tonumber(count) or 0)
    if count < 1 or count > source.count then
        return false, 'invalid_count'
    end
    -- Den Rucksack nicht in seinen eigenen Inhalt legen
    if from.slot == 'backpack' and fromInv == charInv and toInv.kind == 'bag' then
        return false, 'bag_in_bag'
    end
    if extra and extra.other and from.slot == 'backpack' and fromInv == extra.other and toInv.kind == 'bag' then
        return false, 'bag_in_bag'
    end
    -- Rucksaecke nicht in Rucksaecke, auch nicht ueber das zweite Fenster
    if toInv.kind == 'bag' and isBagItem(source.name) then
        return false, 'bag_in_bag'
    end

    -- Auf Kopien planen, erst am Ende uebernehmen
    local fromSlots = copy(fromInv.slots)
    local toSlots = fromSlots
    if fromInv ~= toInv then
        toSlots = copy(toInv.slots)
    end
    local target = toSlots[to.slot]
    local moving = { name = source.name, count = count, meta = copy(source.meta) }

    local ok, err = fitsSlot(toInv, to.slot, moving)
    if not ok then
        return false, err
    end

    if not target then
        toSlots[to.slot] = moving
        fromSlots[from.slot].count = source.count - count
        if fromSlots[from.slot].count <= 0 then fromSlots[from.slot] = nil end
    elseif canStack(target, moving) then
        local amount = math.min(count, stackSize(target.name) - target.count)
        if amount <= 0 then
            return false, 'stack_full'
        end
        toSlots[to.slot].count = target.count + amount
        fromSlots[from.slot].count = source.count - amount
        if fromSlots[from.slot].count <= 0 then fromSlots[from.slot] = nil end
    else
        -- Tauschen geht nur mit dem ganzen Stapel
        if count ~= source.count then
            return false, 'invalid_count'
        end
        local back = copy(target)
        ok, err = fitsSlot(fromInv, from.slot, back)
        if not ok then
            return false, err
        end
        if isBagItem(back.name) and fromInv.kind == 'bag' then
            return false, 'bag_in_bag'
        end
        toSlots[to.slot] = moving
        fromSlots[from.slot] = back
    end

    -- Gewicht: jedes Inventar, das schwerer wird, muss danach unter seiner Grenze liegen
    for _, pair in ipairs({ { fromInv, fromSlots }, { toInv, toSlots } }) do
        local inv, slots = pair[1], pair[2]
        local before, after = weightOf(inv), weightOf(inv, slots)
        if after > before and after > Inventory.MaxWeight(inv) then
            return false, 'too_heavy'
        end
    end

    fromInv.slots = fromSlots
    toInv.slots = toSlots
    fromInv.dirty, toInv.dirty = true, true
    local other, otherBag = extra and extra.other, extra and extra.otherBag
    for _, bag in ipairs({ fromInv, toInv }) do
        if bag.kind == 'bag' then
            syncBagWeight((otherBag and bag == otherBag) and other or charInv, bag)
        end
    end
    if charInv.slots.backpack then
        Inventory.EnsureBagIds(charInv)
    end
    if other and other.kind == 'character' and other.slots.backpack then
        Inventory.EnsureBagIds(other)
    end
    return true
end

------------------------------------------------------------------------
-- Ansicht fuer den Client und die Akte
------------------------------------------------------------------------

local function publicMeta(meta)
    if isEmptyMeta(meta) then
        return nil
    end
    -- Interne Felder (Rucksack-ID) bleiben auf dem Server
    local result = {}
    for k, v in pairs(meta) do
        if k ~= 'bagId' and k ~= 'homeSlot' and k ~= 'uid' then
            result[k] = v
        end
    end
    return next(result) and result or nil
end

local function listOf(inv)
    local list = {}
    for slot, entry in pairs(inv.slots) do
        list[#list + 1] = { slot = slot, name = entry.name, count = entry.count, meta = publicMeta(entry.meta) }
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end

Inventory.ListOf = function(inv)
    return listOf(inv)
end

-- Eintrag aus einem Platz nehmen (fuer Geben): Taschen oder Rucksack, nie Ausruestung
function Inventory.Take(charInv, ref, count)
    local inv = resolve(charInv, ref)
    if not inv or not Inventory.IsValidSlot(inv, ref.slot) or EQUIP[ref.slot] then
        return nil, 'invalid_slot'
    end
    local entry = inv.slots[ref.slot]
    if not entry then
        return nil, 'empty_slot'
    end
    if isDocument(entry.name) then
        return nil, 'bound'
    end
    count = count == nil and entry.count or math.floor(tonumber(count) or 0)
    if count < 1 or count > entry.count then
        return nil, 'invalid_count'
    end
    return { inv = inv, slot = ref.slot, entry = entry, count = count }
end

-- Nach erfolgreichem Geben: aus dem Platz entfernen
function Inventory.Commit(charInv, taken)
    taken.entry.count = taken.entry.count - taken.count
    if taken.entry.count <= 0 then
        taken.inv.slots[taken.slot] = nil
    end
    taken.inv.dirty = true
    if taken.inv.kind == 'bag' then
        syncBagWeight(charInv, taken.inv)
    end
end

-- Nach einer Config-Aenderung (z. B. weniger Taschenplaetze): Items auf Plaetzen, die es nicht mehr gibt,
-- in freie Taschenplaetze oder den Rucksack legen. Das Gewicht wird dabei nicht geprueft, es geht nur um Platz.
-- Gibt zurueck, was nirgends mehr hinpasst.
function Inventory.Relocate(charInv)
    local stray = {}
    for slot, entry in pairs(charInv.slots) do
        if not Inventory.IsValidSlot(charInv, slot) then
            stray[#stray + 1] = slot
        elseif EQUIP[slot] then
            -- Teil passt nicht (mehr) in diesen Platz: in seinen eigenen Platz, wenn frei, sonst wie die anderen
            local def = ItemDef(entry.name)
            if def and def.equip ~= slot then
                if def.equip and EQUIP[def.equip] and not charInv.slots[def.equip] then
                    charInv.slots[def.equip] = entry
                    charInv.slots[slot] = nil
                    charInv.dirty = true
                else
                    stray[#stray + 1] = slot
                end
            end
        end
    end
    if #stray == 0 then
        return {}
    end
    table.sort(stray, function(a, b) return (tonumber(a) or math.huge) < (tonumber(b) or math.huge) end)
    local bag = Inventory.Bag(charInv)
    local leftover = {}
    for _, slot in ipairs(stray) do
        local entry = charInv.slots[slot]
        charInv.slots[slot] = nil
        charInv.dirty = true
        local target = Inventory.FreePocket(charInv)
        if target then
            charInv.slots[target] = entry
        else
            local placed = false
            if bag and not isBagItem(entry.name) then
                for i = 1, slotLimit(bag) do
                    local key = tostring(i)
                    if not bag.slots[key] then
                        bag.slots[key] = entry
                        bag.dirty = true
                        placed = true
                        break
                    end
                end
            end
            if not placed then
                leftover[#leftover + 1] = entry
            end
        end
    end
    syncBagWeight(charInv, bag)
    return leftover
end

-- Freier Taschenplatz oder nil
function Inventory.FreePocket(charInv)
    for i = 1, CFG.Slots do
        if not charInv.slots[tostring(i)] then
            return tostring(i)
        end
    end
    return nil
end

Inventory.EquipSlot = function(slot)
    return EQUIP[slot]
end

function Inventory.State(charInv)
    local bag = Inventory.Bag(charInv)
    return {
        items = listOf(charInv),
        bag = bag and listOf(bag) or nil,
        weight = weightOf(charInv),
        maxWeight = Inventory.MaxWeight(charInv),
        bagWeight = bag and weightOf(bag) or nil,
        bagMaxWeight = bag and Inventory.MaxWeight(bag) or nil,
        bagSlots = bag and slotLimit(bag) or nil,
        bagLevel = bag and bag.capacity and bag.capacity.level or nil,
    }
end
