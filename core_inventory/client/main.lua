-- Inventar auf dem Client: Fenster (F2), Schnellzugriff 1 bis 5, Haufen am Boden, Wirkung von Items.
-- Was erlaubt ist, entscheidet der Server. Der Client zeigt an und leitet weiter.

-- Braucht Core 1.6.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.6.0'
local missingBridge = {}
for _, name in ipairs({ 'AddHealth', 'Async', 'BlockWeaponWheelThisFrame', 'CreateLocalProp', 'DeleteLocalProp', 'ClearOwnProp', 'DrawWorldText', 'Emit', 'EquipWeapon', 'GetOwnModel', 'Export', 'GetPlayerHeadshot', 'RegisterClientCommand', 'ReleaseHeadshot', 'OnSpawned', 'SetOwnComponent', 'SetOwnProp', 'GetWeaponAmmo', 'HasWeapon', 'UnequipWeapon', 'GetNearbyPlayers', 'GetOwnPosition', 'IsOwnPedDead', 'BlockCombatThisFrame', 'GetDistanceToEntity', 'GetNearestVehicleTrunk', 'GetPlayerPedByServerId', 'IsHandsUpPlaying', 'IsOwnPedInVehicle', 'SetHandsUp', 'SetVehicleTrunkOpen', 'VehicleFromNetId', 'PrepareWorldText', 'RegisterKeyCommand', 'UiFocus', 'UiOn', 'UiSend', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Client-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    return
end

local CFG = Config.Inventory

local ERROR_TEXT = {
    no_character = 'Das Inventar geht nur mit einem Charakter.',
    timeout = 'Der Server antwortet nicht.',
    dead = 'Bewusstlos kannst du nicht ins Inventar schauen.',
}

local isOpen = false
local uiReady = false
local pending = nil          -- Nachricht, falls die UI noch laedt
local defs = nil             -- Item-Liste vom Server (fuer den Schnellzugriff)
local lastState = nil
local drops = {}             -- { id, x, y, z }
local props = {}             -- [dropId] = Objekt

local flushAmmo              -- weiter unten: Munitionsstand an den Server, bevor sich das Inventar aendert
local view = nil             -- zweites Fenster: { kind = 'search' | 'trunk' | 'admin', vehicle, target }
local endView                -- weiter unten

local PROP_CHECK_MS = 1000
local HINT_STYLE = { Scale = 0.32, HeightOffset = 0.35, Color = { 255, 255, 255, 220 } }
local HINT_IDLE_MS = 500

local function notify(text, kind)
    Platform.Emit('core:notify', { text = text, type = kind or 'info' })
end

local function send(action, data)
    if uiReady then
        Platform.UiSend(action, data)
    else
        pending = { action = action, data = data }
    end
end

Platform.UiOn('ui_ready', function()
    uiReady = true
    if pending then
        Platform.UiSend(pending.action, pending.data)
        pending = nil
    end
    return { ok = true }
end)

-- Spieler in der Naehe mit ihrer permanenten ID (fuer "Geben"). Namen kennt man im RP nicht.
local function nearbyPlayers()
    local list = {}
    for _, entry in ipairs(Platform.GetNearbyPlayers(CFG.GiveDistance, false)) do
        local id = Network.GetPlayerPublic(entry.serverId, 'coreId')
        if id then
            list[#list + 1] = { serverId = entry.serverId, characterId = id, distance = math.floor(entry.distance * 10 + 0.5) / 10 }
        end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

------------------------------------------------------------------------
-- Oeffnen und Schliessen
------------------------------------------------------------------------

local function open()
    if isOpen then
        return
    end
    if Platform.IsOwnPedDead() then
        notify(ERROR_TEXT.dead, 'error')
        return
    end
    local result = Network.Call('inv_open', {})
    if not result or not result.ok then
        local code = result and result.error or 'timeout'
        notify(ERROR_TEXT[code] or ('Inventar nicht verfügbar: ' .. tostring(code)), 'error')
        return
    end
    defs = result.data.items
    lastState = result.data.state
    isOpen = true
    if view and not result.data.other then
        endView(false)
    end
    send('inv_open', {
        colors = Config.UI.Colors,
        items = result.data.items,
        state = result.data.state,
        drop = result.data.drop,
        other = result.data.other,
        layout = result.data.layout,
        players = nearbyPlayers(),
    })
    Platform.UiFocus(true)
end

local function close()
    if not isOpen then
        return
    end
    isOpen = false
    Platform.UiSend('inv_close', {})
    Platform.UiFocus(false)
    if view then
        endView(true)
    end
end

Platform.RegisterKeyCommand('inventar', 'Inventar öffnen', CFG.OpenKey, function()
    if isOpen then
        close()
    else
        open()
    end
end)

Platform.UiOn('inv_close', function()
    close()
    return { ok = true }
end)

-- Diese Anfragen gehen unveraendert an den Server, die Antwort enthaelt den neuen Stand
for _, name in ipairs({ 'inv_move', 'inv_use', 'inv_give' }) do
    Platform.UiOn(name, function(data)
        flushAmmo()
        local result = Network.Call(name, data)
        if result and result.data and result.data.state then
            lastState = result.data.state
            -- Der Server hat das zweite Fenster beendet (Haende runter, abgeschlossen, zu weit weg)
            if view and not result.data.other then
                endView(false)
            end
        end
        return result
    end)
end

Platform.UiOn('inv_players', function()
    return { ok = true, data = { players = nearbyPlayers() } }
end)

------------------------------------------------------------------------
-- Schnellzugriff: Tasten 1 bis 5 benutzen Platz 1 bis 5
------------------------------------------------------------------------

local function useHotbar(slot)
    if isOpen or Platform.IsOwnPedDead() then
        return
    end
    if not defs then
        local result = Network.Call('inv_open', {})
        if not result or not result.ok then
            return
        end
        defs = result.data.items
        lastState = result.data.state
    end
    flushAmmo()
    local result = Network.Call('inv_use', { inv = 'self', slot = tostring(slot) })
    if result and result.data and result.data.state then
        lastState = result.data.state
    end
    send('inv_hotbar', { colors = Config.UI.Colors, items = defs, state = lastState, slot = slot, error = result and not result.ok and result.error or nil })
end

for i = 1, CFG.HotbarSlots do
    Platform.RegisterKeyCommand('schnellzugriff' .. i, ('Schnellzugriff %d'):format(i), tostring(i), function()
        useHotbar(i)
    end)
end

------------------------------------------------------------------------
-- Vom Server
------------------------------------------------------------------------

-- Inventar hat sich von aussen geaendert (Admin, Geben)
Network.On('core_inventory:changed', function()
    if not isOpen then
        defs = nil
        return
    end
    Platform.Async(function()
        local result = Network.Call('inv_open', {})
        if result and result.ok then
            lastState = result.data.state
            if view and not result.data.other then
                endView(false)
            end
            Platform.UiSend('inv_state', { state = result.data.state, drop = result.data.drop, other = result.data.other })
        end
    end)
end)

Network.On('core_inventory:effect', function(data)
    if type(data) == 'table' and tonumber(data.health) then
        Platform.AddHealth(tonumber(data.health))
    end
end)

-- Komplette Liste: beim Einloggen und nach einem Dimensionswechsel
Network.On('core_inventory:drops', function(list)
    drops = type(list) == 'table' and list or {}
end)

-- Danach nur noch Aenderungen: { add = { { id, x, y, z } }, remove = { id } }
Network.On('core_inventory:drops_changed', function(change)
    if type(change) ~= 'table' then
        return
    end
    local gone = {}
    for _, id in ipairs(type(change.remove) == 'table' and change.remove or {}) do
        gone[id] = true
    end
    local list = {}
    for _, drop in ipairs(drops) do
        if not gone[drop.id] then
            list[#list + 1] = drop
        end
    end
    for _, drop in ipairs(type(change.add) == 'table' and change.add or {}) do
        if type(drop) == 'table' and tonumber(drop.id) and tonumber(drop.x) then
            list[#list + 1] = drop
        end
    end
    drops = list
end)

------------------------------------------------------------------------
-- Haufen am Boden: Beutel zeigen, Hinweis in der Naehe
------------------------------------------------------------------------

local function distanceTo(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Beutel in Sichtweite anlegen, alte wegraeumen
Platform.Async(function()
    while true do
        Platform.Wait(PROP_CHECK_MS)
        local me = Platform.GetOwnPosition()
        local wanted = {}
        for _, drop in ipairs(drops) do
            if distanceTo(me, drop) <= CFG.Drops.ShowDistance then
                wanted[drop.id] = drop
            end
        end
        for id, object in pairs(props) do
            if not wanted[id] then
                Platform.DeleteLocalProp(object)
                props[id] = nil
            end
        end
        for id, drop in pairs(wanted) do
            if not props[id] then
                props[id] = Platform.CreateLocalProp(DropPropModel, drop) or false
            end
        end
    end
end)

-- Hinweis "F2: Aufheben" nur, wenn man direkt davor steht
local hintText = Platform.PrepareWorldText({ { { text = CFG.OpenKey, tone = 'accent' }, { text = '  Aufheben', tone = 'normal' } } })

Platform.Async(function()
    while true do
        local near = nil
        if #drops > 0 and not isOpen then
            local me = Platform.GetOwnPosition()
            for _, drop in ipairs(drops) do
                if distanceTo(me, drop) <= CFG.Drops.PickupDistance then
                    near = drop
                    break
                end
            end
        end
        if near then
            Platform.DrawWorldText(near, hintText, HINT_STYLE)
            Platform.Wait(0)
        else
            Platform.Wait(HINT_IDLE_MS)
        end
    end
end)

------------------------------------------------------------------------
-- Waffenrad sperren: Waffen kommen nur noch ueber das Inventar
------------------------------------------------------------------------

if CFG.BlockWeaponWheel then
    Platform.Async(function()
        while true do
            Platform.BlockWeaponWheelThisFrame()
            Platform.Wait(0)
        end
    end)
end

------------------------------------------------------------------------
-- Waffe in der Hand: kommt nur aus dem Waffenplatz des Inventars
------------------------------------------------------------------------

local WEAPON_CHECK_MS = 250
local AMMO_REPORT_MS = 1000
local UNTRACKED_AMMO = 100 -- Nahkampf und Taser: Munition wird nicht gezaehlt

local held = nil   -- { item, game, id, ammo, tracked, reported }

local function reportAmmo()
    if held and held.tracked and held.ammo ~= held.reported then
        held.reported = held.ammo
        Network.Call('inv_ammo', { id = held.id, ammo = held.ammo })
    end
end

-- Vor jedem Verschieben, Benutzen oder Geben: sonst koennte man durch schnelles Wegstecken Munition sparen
flushAmmo = function()
    if held and held.tracked then
        local ammo = Platform.GetWeaponAmmo(held.game)
        if ammo and ammo < held.ammo then
            held.ammo = ammo
        end
        reportAmmo()
    end
end

Network.On('core_inventory:weapon', function(data)
    data = type(data) == 'table' and data or {}
    local game = data.item and WeaponModels[data.item]
    if held and (not game or held.id ~= data.id) then
        Platform.UnequipWeapon(held.game)
        held = nil
    end
    if not game then
        return
    end
    local tracked = data.ammo ~= nil
    local ammo = tracked and math.max(0, math.floor(tonumber(data.ammo) or 0)) or UNTRACKED_AMMO
    if held then
        -- Gleiche Waffe, neue Munition (nachgeladen)
        held.ammo, held.reported = ammo, ammo
        Platform.EquipWeapon(held.game, ammo)
        return
    end
    held = { item = data.item, game = game, id = data.id, ammo = ammo, reported = ammo, tracked = tracked }
    Platform.EquipWeapon(game, ammo)
end)

-- Munition mitzaehlen und die Waffe nach Tod oder Wiederbeleben neu in die Hand geben
Platform.Async(function()
    local sinceReport = 0
    while true do
        Platform.Wait(WEAPON_CHECK_MS)
        if held then
            if not Platform.IsOwnPedDead() and not Platform.HasWeapon(held.game) then
                Platform.EquipWeapon(held.game, held.ammo)
            elseif held.tracked then
                local ammo = Platform.GetWeaponAmmo(held.game)
                if ammo and ammo < held.ammo then
                    held.ammo = ammo
                end
            end
            sinceReport = sinceReport + WEAPON_CHECK_MS
            if sinceReport >= AMMO_REPORT_MS then
                sinceReport = 0
                reportAmmo()
            end
        end
    end
end)

------------------------------------------------------------------------
-- Kleidung am Charakter: was in den Kleidungsplaetzen liegt, traegt er. Leere Plaetze = "nichts" aus data/clothing_*.lua
------------------------------------------------------------------------

local MODEL_CHECK_MS = 2000

local outfit = nil       -- { gender, worn = { [slot] = { drawable, texture, arms } } }
local outfitModel = nil  -- Modell, auf dem die Kleidung zuletzt gesetzt wurde

-- Aussehen eines Items fuer das Modell oder nil
local function lookOf(item, gender)
    local looks = item and ClothingLooks[item]
    return looks and looks[gender] or nil
end

local function setComponent(component, value)
    if value then
        Platform.SetOwnComponent(component, value[1], value[2] or 0)
    end
end

local function applyOutfit()
    if not outfit then
        return
    end
    local gender = outfit.gender or 'male'
    local naked = ClothingNaked[gender] or ClothingNaked.male
    local worn = {}
    for slot, item in pairs(outfit.worn or {}) do
        worn[slot] = lookOf(item, gender)
    end

    -- Alles ausser Oberteil, T-Shirt und Armen: Teil oder "nichts"
    for slot, target in pairs(ClothingSlots) do
        if slot ~= 'jacket' and slot ~= 'shirt' and slot ~= 'gloves' then
            local look = worn[slot]
            if target.component then
                setComponent(target.component, look or naked[slot])
            elseif look then
                Platform.SetOwnProp(target.prop, look[1], look[2] or 0)
            else
                Platform.ClearOwnProp(target.prop)
            end
        end
    end

    -- Oberkoerper: Jacke oben, T-Shirt darunter. Ohne Jacke ist das T-Shirt das Oberteil.
    local jacket, shirt = worn.jacket, worn.shirt
    local top, under = naked.jacket, naked.shirt
    if jacket then
        top = jacket
        under = shirt and shirt.under or naked.shirt
    elseif shirt then
        top = shirt
    end
    setComponent(ClothingTopComponent, top)
    setComponent(ClothingSlots.shirt.component, under)

    -- Arme: Handschuhe gehen vor, sonst die Arme, die zum Oberteil passen
    if worn.gloves then
        setComponent(ClothingArmsComponent, worn.gloves)
    else
        local arms = top and top[3]
        setComponent(ClothingArmsComponent, { arms or naked.gloves[1], 0 })
    end
    outfitModel = Platform.GetOwnModel()
end

Network.On('core_inventory:outfit', function(data)
    if type(data) ~= 'table' then
        return
    end
    outfit = { gender = data.gender, worn = type(data.worn) == 'table' and data.worn or {} }
    applyOutfit()
end)

-- Nach dem Spawnen setzt GTA die Standardkleidung: danach wieder anziehen
Platform.OnSpawned(function()
    applyOutfit()
end)

Platform.Async(function()
    while true do
        Platform.Wait(MODEL_CHECK_MS)
        if outfit and Platform.GetOwnModel() ~= outfitModel then
            applyOutfit()
        end
    end
end)

------------------------------------------------------------------------
-- Dokumente zeigen: vorlaeufig /zeigen, spaeter das G-Menue ueber exports.core_inventory:ShowDocument
------------------------------------------------------------------------

local DOC_CFG = CFG.Documents
local DOC_COMMAND_TYPES = { ausweis = 'id', personalausweis = 'id', fuehrerschein = 'driver', waffenschein = 'weapon',
    flugschein = 'pilot', bootsschein = 'boat', angelschein = 'fishing', dienstausweis = 'service' }

-- Zeigt einer bestimmten Person (Server-ID) das Dokument. Fuer das G-Menue: die Person, auf die man zeigt.
local function showDocument(docType, target)
    local result = Network.Call('doc_show', { type = docType, target = target })
    if result and not result.ok then
        local texts = { too_far = 'Die Person steht zu weit weg.', no_document = 'Das Dokument hast du nicht.', target_offline = 'Die Person ist nicht mehr da.' }
        notify(texts[result.error] or 'Das hat nicht geklappt.', 'error')
    end
    return result
end
Platform.Export('ShowDocument', showDocument)

-- Ein Item ohne Platzangabe an eine Person (Server-ID) geben, z. B. Bargeld aus dem G-Menue der core_lib.
-- Gibt true oder false zurueck. Fehler meldet das Inventar selbst.
local GIVE_ERROR_TEXT = {
    not_enough_own = 'So viel hast du nicht dabei.',
    split_stacks = 'So viel liegt nicht auf einem Platz. Leg es im Inventar erst zusammen.',
    invalid_count = 'Ungültige Menge.',
    too_far = 'Die Person steht zu weit weg.',
    target_offline = 'Die Person ist nicht mehr da.',
    target_full = 'Die Person hat keinen Platz mehr.',
    target_too_heavy = 'Das ist der Person zu schwer.',
    twink_blocked = 'An eigene Charaktere kann man nichts geben.',
    no_character = 'Das geht nur mit einem Charakter.',
    timeout = 'Der Server antwortet nicht.',
}

local function giveItem(target, item, count)
    if Platform.IsOwnPedDead() then
        return false
    end
    local result = Network.Call('inv_give_item', { target = tonumber(target), item = item, count = tonumber(count) })
    if not result or not result.ok then
        local code = result and result.error or 'timeout'
        notify(GIVE_ERROR_TEXT[code] or 'Das hat nicht geklappt.', 'error')
        return false
    end
    if result.data and result.data.state then
        lastState = result.data.state
        if isOpen then
            send('inv_state', { state = lastState })
        end
    end
    return true
end
Platform.Export('GiveItem', giveItem)

-- Vorlaeufig: naechste Person in Reichweite
Platform.RegisterClientCommand('zeigen', function(args)
    local docType = DOC_COMMAND_TYPES[(args[1] or ''):lower()]
    if not docType then
        notify('Benutzung: /zeigen ausweis | fuehrerschein | waffenschein | flugschein | bootsschein | angelschein | dienstausweis', 'info')
        return
    end
    local nearest = nil
    for _, entry in ipairs(Platform.GetNearbyPlayers(DOC_CFG.ShowDistance, false)) do
        if not nearest or entry.distance < nearest.distance then
            nearest = entry
        end
    end
    if not nearest then
        notify('Niemand steht nah genug bei dir.', 'error')
        return
    end
    showDocument(docType, nearest.serverId)
end)

-- Jemand zeigt mir ein Dokument: Kopfbild der Person aufnehmen und die Karte anzeigen
local headshot = nil
local showToken = 0

Network.On('core_inventory:document', function(data)
    if type(data) ~= 'table' or type(data.card) ~= 'table' then
        return
    end
    showToken = showToken + 1
    local token = showToken
    Platform.Async(function()
        if headshot then
            Platform.ReleaseHeadshot(headshot.handle)
            headshot = nil
        end
        -- Jedes Dokument hat ein Foto, wie echte Karten
        local shot = Platform.GetPlayerHeadshot(tonumber(data.from))
        if token ~= showToken then
            if shot then Platform.ReleaseHeadshot(shot.handle) end
            return
        end
        headshot = shot
        send('inv_document', { colors = Config.UI.Colors, card = data.card, photo = shot and shot.url or nil, seconds = data.seconds or DOC_CFG.ShowSeconds })
        Platform.Wait((data.seconds or DOC_CFG.ShowSeconds) * 1000 + 500)
        if token == showToken and headshot then
            Platform.ReleaseHeadshot(headshot.handle)
            headshot = nil
        end
    end)
end)

-- Aus dem Inventar: Rechtsklick auf ein Dokument, "Zeigen", Person waehlen
Platform.UiOn('inv_show', function(data)
    return showDocument(data.type, tonumber(data.target))
end)

------------------------------------------------------------------------
-- Zweites Fenster: Durchsuchen, Kofferraum, /invsee
-- Vorlaeufig /durchsuchen und /kofferraum, spaeter das G-Menue ueber
-- exports.core_inventory:SearchPlayer(serverId) und exports.core_inventory:OpenNearestTrunk()
------------------------------------------------------------------------

local SEARCH_CFG, TRUNK_CFG = CFG.Search, CFG.Trunk
local VIEW_CHECK_MS = 500
local VIEW_LEAVE_MARGIN = 1.0      -- etwas Spielraum, bevor das Fenster beim Weggehen zugeht

local VIEW_ERROR_TEXT = {
    not_searchable = 'Die Person muss die Hände oben haben oder gefesselt sein.',
    too_far = 'Du stehst zu weit weg.',
    target_offline = 'Die Person ist nicht mehr da.',
    vehicle_locked = 'Das Fahrzeug ist abgeschlossen.',
    trunk_busy = 'Jemand anderes schaut gerade in den Kofferraum.',
    no_trunk = 'Dieses Fahrzeug hat keinen Kofferraum.',
    no_vehicle = 'Hier ist kein Fahrzeug.',
    not_allowed = 'Das darfst du nicht.',
    no_character = 'Das geht nur mit einem Charakter.',
    invalid_stash = 'Dieses Lager ist falsch eingerichtet.',
    timeout = 'Der Server antwortet nicht.',
}

local function viewError(result)
    local code = result and result.error or 'timeout'
    notify(VIEW_ERROR_TEXT[code] or 'Das hat nicht geklappt.', 'error')
end

-- Fenster beenden. notifyServer = false, wenn der Server es schon beendet hat.
endView = function(notifyServer)
    local ended = view
    view = nil
    if not ended then
        return
    end
    if ended.vehicle then
        Platform.SetVehicleTrunkOpen(ended.vehicle, false)
    end
    if notifyServer then
        Platform.Async(function()
            Network.Call('view_close', {})
        end)
    end
end

-- Inventar mit zweitem Fenster oeffnen oder, wenn es schon offen ist, neu laden
local function showView()
    if isOpen then
        local result = Network.Call('inv_open', {})
        if result and result.ok then
            lastState = result.data.state
            Platform.UiSend('inv_state', { state = result.data.state, drop = result.data.drop, other = result.data.other })
        end
    else
        open()
    end
    if view and not isOpen then
        endView(true)
    end
end

-- Beim Weggehen geht das Fenster zu
local function watchView()
    Platform.Async(function()
        while view do
            Platform.Wait(VIEW_CHECK_MS)
            local current = view
            if not current then
                return
            end
            local limit, distance
            if current.kind == 'trunk' and current.vehicle then
                limit, distance = TRUNK_CFG.Distance, Platform.GetDistanceToEntity(current.vehicle)
            elseif current.kind == 'stash' and current.position then
                local own = Platform.GetOwnPosition()
                local dx, dy, dz = own.x - current.position.x, own.y - current.position.y, own.z - current.position.z
                limit, distance = current.distance or CFG.Stash.Distance, math.sqrt(dx * dx + dy * dy + dz * dz)
            elseif current.kind == 'search' then
                limit, distance = SEARCH_CFG.Distance, Platform.GetDistanceToEntity(Platform.GetPlayerPedByServerId(current.target))
            else
                return
            end
            if (not distance or distance > limit + VIEW_LEAVE_MARGIN or Platform.IsOwnPedDead()) and view == current then
                endView(true)
                if isOpen then
                    local texts = { trunk = 'Du hast dich vom Kofferraum entfernt.', stash = 'Du hast dich vom Lager entfernt.', search = 'Du hast dich von der Person entfernt.' }
                    notify(texts[current.kind], 'info')
                    Platform.UiSend('inv_state', { state = lastState, other = false })
                end
                return
            end
        end
    end)
end

-- Der Server hat das alte Fenster beim Oeffnen des neuen schon beendet
local function startView(entry)
    if view then
        endView(false)
    end
    view = entry
    if entry.vehicle then
        Platform.SetVehicleTrunkOpen(entry.vehicle, true)
    end
    showView()
    watchView()
end

local function nearestPlayer(maxDistance)
    local nearest = nil
    for _, entry in ipairs(Platform.GetNearbyPlayers(maxDistance, false)) do
        if not nearest or entry.distance < nearest.distance then
            nearest = entry
        end
    end
    return nearest
end

-- Eine bestimmte Person durchsuchen (Server-ID). Fuer das G-Menue.
local function searchPlayer(target)
    target = tonumber(target)
    if not target or Platform.IsOwnPedDead() then
        return false
    end
    local result = Network.Call('view_search', { target = target })
    if not result or not result.ok then
        viewError(result)
        return false
    end
    startView({ kind = 'search', target = target })
    return true
end

-- Den Kofferraum des naechsten Fahrzeugs oeffnen. Fuer das G-Menue.
local function openNearestTrunk()
    if Platform.IsOwnPedDead() then
        return false
    end
    local trunk = Platform.GetNearestVehicleTrunk(TRUNK_CFG.Distance)
    if not trunk then
        viewError({ error = Platform.IsOwnPedInVehicle() and 'not_allowed' or 'no_vehicle' })
        return false
    end
    if trunk.trunkDistance > TRUNK_CFG.HeckDistance then
        notify('Stell dich direkt an den Kofferraum.', 'info')
        return false
    end
    if trunk.locked then
        viewError({ error = 'vehicle_locked' })
        return false
    end
    local result = Network.Call('view_trunk', { netId = trunk.netId, class = trunk.class })
    if not result or not result.ok then
        viewError(result)
        return false
    end
    startView({ kind = 'trunk', vehicle = trunk.vehicle })
    return true
end

Platform.Export('SearchPlayer', searchPlayer)
Platform.Export('OpenNearestTrunk', openNearestTrunk)

Platform.RegisterClientCommand('durchsuchen', function()
    local nearest = nearestPlayer(SEARCH_CFG.Distance)
    if not nearest then
        notify('Niemand steht nah genug bei dir.', 'error')
        return
    end
    searchPlayer(nearest.serverId)
end)

Platform.RegisterClientCommand('kofferraum', function()
    openNearestTrunk()
end)

-- Vom Server geoeffnet (Exports OpenSearch, OpenTrunk, OpenStash oder /invsee)
Network.On('core_inventory:view', function(data)
    data = type(data) == 'table' and data or {}
    Platform.Async(function()
        local entry = { kind = data.kind or 'admin', target = tonumber(data.target), position = data.position, distance = tonumber(data.distance) }
        if entry.kind == 'trunk' and data.netId then
            entry.vehicle = Platform.VehicleFromNetId(tonumber(data.netId))
        end
        startView(entry)
    end)
end)

-- Vom Server beendet (Person hat sich ausgeloggt)
Network.On('core_inventory:view_closed', function()
    if not view then
        return
    end
    endView(false)
    if isOpen then
        notify('Das andere Inventar ist nicht mehr verfügbar.', 'info')
        Platform.UiSend('inv_state', { state = lastState, other = false })
    end
end)

------------------------------------------------------------------------
-- Haende hoch (Taste X): erlaubt das Durchsuchen
------------------------------------------------------------------------

local HANDS_CHECK_MS = 250
local handsUp = false

local function setHandsUp(on)
    if on == handsUp then
        return
    end
    if on and (Platform.IsOwnPedDead() or Platform.IsOwnPedInVehicle()) then
        return
    end
    handsUp = on
    if on and not Platform.SetHandsUp(true) then
        handsUp = false
        return
    end
    if not on then
        Platform.SetHandsUp(false)
    end
    Network.Call('inv_handsup', { up = on })
    if not on then
        return
    end
    -- Solange die Haende oben sind: nicht schiessen, und bei Tod oder Einsteigen wieder runter
    Platform.Async(function()
        while handsUp do
            Platform.BlockCombatThisFrame()
            Platform.Wait(0)
        end
    end)
    Platform.Async(function()
        while handsUp do
            Platform.Wait(HANDS_CHECK_MS)
            if handsUp and (Platform.IsOwnPedDead() or Platform.IsOwnPedInVehicle() or not Platform.IsHandsUpPlaying()) then
                setHandsUp(false)
            end
        end
    end)
end

Platform.RegisterKeyCommand('haendehoch', 'Hände hoch', SEARCH_CFG.HandsUpKey, function()
    if isOpen then
        return
    end
    setHandsUp(not handsUp)
end)

Platform.Export('IsHandsUp', function() return handsUp end)
