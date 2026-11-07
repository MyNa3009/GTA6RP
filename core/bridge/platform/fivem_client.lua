-- Plattform-Bridge (Client) fuer FiveM.
-- Nur hier duerfen Client-Natives und NUI-Funktionen stehen.

Platform = {}

local LEVEL_COLORS = {
    info  = '^5',
    ok    = '^2',
    warn  = '^3',
    error = '^1',
}

local SESSION_POLL_MS = 100

function Platform.Print(level, message)
    print(('%s[core] %s^7'):format(LEVEL_COLORS[level] or '^7', message))
end

function Platform.Async(fn)
    CreateThread(fn)
end

function Platform.Wait(ms)
    Wait(ms)
end

function Platform.WaitForSession()
    while not NetworkIsSessionStarted() do
        Wait(SESSION_POLL_MS)
    end
end

------------------------------------------------------------------------
-- Spieler
------------------------------------------------------------------------

-- Gesperrt: eingefroren, unsichtbar, unverwundbar, keine Steuerung, keine Minimap
function Platform.SetPlayerLocked(locked)
    local playerId = PlayerId()
    local ped = PlayerPedId()

    FreezeEntityPosition(ped, locked)
    SetEntityVisible(ped, not locked, false)
    SetEntityInvincible(ped, locked)
    SetPlayerControl(playerId, not locked, 0)
    DisplayRadar(not locked)
end

function Platform.OnSpawned(handler)
    AddEventHandler('playerSpawned', handler)
end

-- Spawnt den Spieler mit Modell (Name aus data/models_*.lua) an einer Position und wartet, bis er steht
function Platform.SpawnCharacter(model, position)
    local done = promise.new()

    exports.spawnmanager:spawnPlayer({
        x = position.x + 0.0,
        y = position.y + 0.0,
        z = position.z + 0.0,
        heading = (position.heading or 0) + 0.0,
        model = GetHashKey(model),
        skipFade = false,
    }, function()
        done:resolve(true)
    end)

    Citizen.Await(done)

    -- Standard-Aussehen, bis es ein eigenes Appearance-System gibt
    local ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)
    SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)
end

-- Wird nach dem Tod statt des normalen spawnmanager-Respawns aufgerufen
function Platform.SetRespawnHandler(handler)
    exports.spawnmanager:setAutoSpawnCallback(handler)
end

-- Ab dem Spawn des Charakters regelt die Core den Tod selbst: kein Auto-Respawn, kein Schwarzbild
function Platform.DisableAutoRespawn()
    exports.spawnmanager:setAutoSpawn(false)
    SetFadeOutAfterDeath(false)
end

function Platform.GetTime()
    return GetGameTimer()
end

------------------------------------------------------------------------
-- Tod
------------------------------------------------------------------------

local DEATH_POLL_MS = 250
local FADE_MS = 400
local COLLISION_TIMEOUT_MS = 5000
local DRIVER_SEAT = -1

local function playerServerIdFromPed(ped)
    if ped == 0 or not DoesEntityExist(ped) then
        return nil
    end
    if IsEntityAVehicle(ped) then
        ped = GetPedInVehicleSeat(ped, DRIVER_SEAT)
    end
    if ped == 0 or not IsEntityAPed(ped) or not IsPedAPlayer(ped) then
        return nil
    end
    local index = NetworkGetPlayerIndexFromPed(ped)
    if index == -1 then
        return nil
    end
    return GetPlayerServerId(index)
end

-- Bildeffekt im Spiel an oder aus (Name aus data/effects_gta5.lua)
function Platform.SetScreenEffect(name, on)
    if not name then
        return
    end
    if on then
        AnimpostfxPlay(name, 0, true)
    else
        AnimpostfxStop(name)
    end
end

-- Ruft handler({ killerServerId?, weapon }) einmal pro Tod auf
function Platform.OnDeath(handler)
    CreateThread(function()
        local wasDead = false
        while true do
            Wait(DEATH_POLL_MS)
            local ped = PlayerPedId()
            local dead = IsEntityDead(ped)
            if dead and not wasDead then
                wasDead = true
                local killer = playerServerIdFromPed(GetPedSourceOfDeath(ped))
                if killer == GetPlayerServerId(PlayerId()) then
                    killer = nil
                end
                local info = { killerServerId = killer, weapon = GetPedCauseOfDeath(ped) }
                CreateThread(function()
                    handler(info)
                end)
            elseif not dead then
                wasDead = false
            end
        end
    end)
end

local function healAfterResurrect()
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    AnimpostfxStopAll()
    SetFadeOutAfterDeath(false)
end

-- Wiederbeleben an Ort und Stelle, Aussehen bleibt erhalten
function Platform.ReviveInPlace()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    healAfterResurrect()
end

-- Kurz abblenden, an der Position wiederbeleben, aufblenden. Bleibt nie dauerhaft schwarz.
function Platform.RespawnAt(position)
    local x, y, z = position.x + 0.0, position.y + 0.0, position.z + 0.0
    local heading = (position.heading or 0) + 0.0

    DoScreenFadeOut(FADE_MS)
    local fadeTimeout = GetGameTimer() + FADE_MS * 3
    while not IsScreenFadedOut() and GetGameTimer() < fadeTimeout do
        Wait(0)
    end

    RequestCollisionAtCoord(x, y, z)
    NetworkResurrectLocalPlayer(x, y, z, heading, true, false)
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, heading)
    healAfterResurrect()

    local collisionTimeout = GetGameTimer() + COLLISION_TIMEOUT_MS
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < collisionTimeout do
        Wait(0)
    end

    DoScreenFadeIn(FADE_MS)
end

------------------------------------------------------------------------
-- Tasten (GTA-5-Controls)
------------------------------------------------------------------------

local ACTIONS = {
    respawn       = { control = 38, label = 'E' },      -- INPUT_PICKUP
    noclipForward = { control = 32, label = 'W' },      -- INPUT_MOVE_UP_ONLY
    noclipBack    = { control = 33, label = 'S' },      -- INPUT_MOVE_DOWN_ONLY
    noclipLeft    = { control = 34, label = 'A' },      -- INPUT_MOVE_LEFT_ONLY
    noclipRight   = { control = 35, label = 'D' },      -- INPUT_MOVE_RIGHT_ONLY
    noclipUp      = { control = 22, label = 'Leertaste' }, -- INPUT_JUMP
    noclipDown    = { control = 36, label = 'Strg' },   -- INPUT_DUCK
    noclipFast    = { control = 21, label = 'Shift' },  -- INPUT_SPRINT
    noclipSlow    = { control = 19, label = 'Alt' },    -- INPUT_CHARACTER_WHEEL
    cancel        = { control = 73, label = 'X' },      -- INPUT_VEH_DUCK, Abbrechen (z. B. Fortschrittsbalken der core_lib)
}
local CONTROL_GROUP = 0

-- Im Noclip gesperrt, damit der Ped nicht springt, rennt oder in Deckung geht
local NOCLIP_BLOCKED_CONTROLS = { 19, 21, 22, 23, 30, 31, 32, 33, 34, 35, 36, 44, 71, 72, 75 }
-- Im A-Jail gesperrt: schiessen, zielen, schlagen, Waffenrad
local COMBAT_CONTROLS = { 24, 25, 37, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }

-- Funktioniert auch, wenn das Spiel die Steuerung gerade sperrt (z. B. im Tod)
function Platform.IsActionPressed(action)
    local entry = ACTIONS[action]
    return entry ~= nil and IsDisabledControlPressed(CONTROL_GROUP, entry.control)
end

function Platform.GetActionLabel(action)
    local entry = ACTIONS[action]
    return entry and entry.label or action
end

-- Jeden Frame aufrufen, solange es gelten soll
function Platform.DisableCombatThisFrame()
    for _, control in ipairs(COMBAT_CONTROLS) do
        DisableControlAction(CONTROL_GROUP, control, true)
    end
    DisablePlayerFiring(PlayerId(), true)
end

------------------------------------------------------------------------
-- Noclip
------------------------------------------------------------------------

local noclipEntity = nil
local LOOK_UP_DOWN_CONTROL = 2 -- INPUT_LOOK_UD (Maus hoch und runter)
local NOCLIP_TELEPORT_DISTANCE = 3.0 -- weiter weg gilt als Teleport, nicht als Abdriften
local noclipPosition = nil
local noclipCamPitch = nil -- gemerkte Kamera-Neigung, solange die Maus nicht bewegt wird -- gemerkte Position im Noclip, damit nichts den Spieler wegtreibt

-- Fliegt mit dem Fahrzeug, wenn man am Steuer sitzt, sonst mit dem Ped
local function noclipTarget()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, DRIVER_SEAT) == ped then
        return vehicle, true
    end
    return ped, false
end

-- Von hier aus wird beim Verlassen des Noclips der Boden gesucht: erst direkt unter einem,
-- dann von weiter oben (falls man unter der Karte steckt)
local NOCLIP_GROUND_PROBES = { 1.0, 50.0 }
local NOCLIP_GROUND_TOP = 1000.0

local function noclipGround(x, y, z)
    for _, offset in ipairs(NOCLIP_GROUND_PROBES) do
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + offset, false)
        if found then
            return groundZ
        end
    end
    local found, groundZ = GetGroundZFor_3dCoord(x, y, NOCLIP_GROUND_TOP, false)
    return found and groundZ or nil
end

-- invisible = true: fuer alle anderen unsichtbar (Ped und Fahrzeug)
-- toGround = true: beim Ausschalten auf den Boden darunter setzen, auch aus der Luft
function Platform.SetNoclip(enabled, invisible, toGround)
    local entity, isVehicle
    if enabled then
        entity, isVehicle = noclipTarget()
        noclipEntity = entity
    else
        entity = noclipEntity or PlayerPedId()
        isVehicle = IsEntityAVehicle(entity)
        noclipEntity = nil
    end
    if not DoesEntityExist(entity) then
        return
    end
    FreezeEntityPosition(entity, enabled)
    SetEntityCollision(entity, not enabled, not enabled)
    -- Ohne Schwerkraft und ohne Restgeschwindigkeit kann nichts nach unten ziehen
    SetEntityHasGravity(entity, not enabled)
    noclipCamPitch = nil
    if enabled then
        SetEntityVelocity(entity, 0.0, 0.0, 0.0)
        noclipPosition = GetEntityCoords(entity)
    else
        noclipPosition = nil
    end
    if isVehicle then
        SetEntityInvincible(entity, enabled)
    end
    if invisible or not enabled then
        local visible = not (enabled and invisible)
        SetEntityVisible(entity, visible, false)
        if isVehicle then
            SetEntityVisible(PlayerPedId(), visible, false)
        end
    end
    if not enabled and toGround then
        local coords = GetEntityCoords(entity)
        local groundZ = noclipGround(coords.x, coords.y, coords.z)
        if groundZ then
            SetEntityCoordsNoOffset(entity, coords.x, coords.y, groundZ, false, false, false)
            if isVehicle then
                SetVehicleOnGroundProperly(entity)
            end
        end
    end
    if not enabled then
        -- Ohne diesen Anstoss bleibt ein Fahrzeug manchmal in der Luft stehen
        ActivatePhysics(entity)
    end
end

-- Jeden Frame: sich selbst trotz Unsichtbarkeit sehen
function Platform.ShowNoclipLocallyThisFrame()
    if noclipEntity and DoesEntityExist(noclipEntity) then
        SetEntityLocallyVisible(noclipEntity)
        if noclipEntity ~= PlayerPedId() then
            SetEntityLocallyVisible(PlayerPedId())
        end
    end
end

function Platform.DisableNoclipControlsThisFrame()
    for _, control in ipairs(NOCLIP_BLOCKED_CONTROLS) do
        DisableControlAction(CONTROL_GROUP, control, true)
    end
end

function Platform.GetFrameTime()
    return GetFrameTime()
end

-- forward, right, up: -1, 0 oder 1. distance: Meter in diesem Frame. Richtung kommt von der Kamera.
-- followPitch = false: W und S fliegen waagerecht, egal wohin die Kamera nach oben oder unten schaut
function Platform.NoclipMove(forward, right, up, distance, followPitch)
    local entity = noclipEntity
    if not entity or not DoesEntityExist(entity) then
        return
    end
    local rotation = GetGameplayCamRot(2)
    local heading = math.rad(rotation.z)
    local pitch = followPitch and math.rad(rotation.x) or 0.0

    local dirX = -math.sin(heading) * math.cos(pitch)
    local dirY = math.cos(heading) * math.cos(pitch)
    local dirZ = math.sin(pitch)
    local rightX, rightY = math.cos(heading), math.sin(heading)

    local coords = noclipPosition or GetEntityCoords(entity)
    local x = coords.x + (dirX * forward + rightX * right) * distance
    local y = coords.y + (dirY * forward + rightY * right) * distance
    local z = coords.z + (dirZ * forward + up) * distance

    SetEntityCoordsNoOffset(entity, x, y, z, true, true, true)
    SetEntityHeading(entity, rotation.z)
    noclipPosition = vector3(x, y, z)
end

-- Jeden Frame im Noclip: Der Spieler bleibt genau da, wo er ist.
-- Andere Scripts, Ragdoll oder das Spiel selbst koennen das Einfrieren aufheben (dann faellt man langsam nach unten).
function Platform.NoclipHold()
    local entity = noclipEntity
    if not entity or not DoesEntityExist(entity) then
        return
    end
    if not IsEntityPositionFrozen(entity) then
        FreezeEntityPosition(entity, true)
    end
    SetEntityCollision(entity, false, false)
    SetEntityHasGravity(entity, false)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)

    -- GTA kippt die Kamera von selbst langsam nach unten, sobald man die Maus nicht bewegt.
    -- Mit W fliegt man dahin, wohin die Kamera zeigt, also ging es dann von allein abwaerts.
    -- Darum bleibt die Neigung genau so, wie du sie mit der Maus zuletzt eingestellt hast.
    local lookUpDown = GetDisabledControlNormal(CONTROL_GROUP, LOOK_UP_DOWN_CONTROL)
    if noclipCamPitch == nil or lookUpDown ~= 0.0 then
        noclipCamPitch = GetGameplayCamRelativePitch()
    else
        SetGameplayCamRelativePitch(noclipCamPitch, 1.0)
    end

    if noclipPosition then
        local coords = GetEntityCoords(entity)
        local drift = #(coords - noclipPosition)
        if drift > NOCLIP_TELEPORT_DISTANCE then
            -- Versetzt (z. B. /tp im Noclip): neue Position uebernehmen
            noclipPosition = coords
        elseif drift > 0.05 then
            SetEntityCoordsNoOffset(entity, noclipPosition.x, noclipPosition.y, noclipPosition.z, true, true, true)
        end
    end
end

------------------------------------------------------------------------
-- Andere Spieler und Text in der Welt
------------------------------------------------------------------------

local HEAD_BONE = 31086 -- SKEL_Head
local LOS_FLAGS = 17    -- Karte und Objekte

function Platform.GetOwnServerId()
    return GetPlayerServerId(PlayerId())
end

-- Liste { serverId, ped, distance } aller sichtbaren Spieler im Umkreis
function Platform.GetNearbyPlayers(maxDistance, includeSelf)
    local me = PlayerId()
    local myCoords = GetEntityCoords(PlayerPedId())
    local result = {}

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me or includeSelf then
            local ped = GetPlayerPed(player)
            if ped ~= 0 then
                local distance = #(GetEntityCoords(ped) - myCoords)
                if distance <= maxDistance then
                    result[#result + 1] = { serverId = GetPlayerServerId(player), ped = ped, distance = distance }
                end
            end
        end
    end

    return result
end

-- Kopfbild eines Spielers fuer Ausweise. Gibt { handle, url } zurueck oder nil (zu weit weg, Zeit abgelaufen).
-- Die url ist im NUI als Bild nutzbar. Danach Platform.ReleaseHeadshot(handle) aufrufen.
local HEADSHOT_TIMEOUT_MS = 3000

function Platform.GetPlayerHeadshot(serverId)
    local player = GetPlayerFromServerId(serverId)
    local ped = player ~= -1 and GetPlayerPed(player) or 0
    if ped == 0 then
        return nil
    end
    local handle = RegisterPedheadshot(ped)
    local timeout = GetGameTimer() + HEADSHOT_TIMEOUT_MS
    while not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle) do
        if GetGameTimer() > timeout then
            UnregisterPedheadshot(handle)
            return nil
        end
        Wait(0)
    end
    local txd = GetPedheadshotTxdString(handle)
    return { handle = handle, url = ('https://nui-img/%s/%s'):format(txd, txd) }
end

function Platform.ReleaseHeadshot(handle)
    if handle then
        UnregisterPedheadshot(handle)
    end
end

-- Spieler, den man gerade anschaut (Mitte der Kamera), in maxDistance Metern. Gibt { serverId, ped, distance } oder nil.
-- Gewaehlt wird, wer am naechsten an der Blickrichtung steht, hoechstens maxAngle Grad daneben und mit freier Sicht.
-- Ueber den Winkel statt per Strahl, weil ein duenner Strahl Personen oft verfehlt (seit Core 1.8.0).
local SIGHT_AIM_HEIGHT = 0.3   -- Brusthoehe ueber dem Mittelpunkt des Peds

function Platform.GetPlayerInSight(maxDistance, maxAngle)
    local me = PlayerId()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local camera = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local limit = math.cos(math.rad(maxAngle))
    local best, bestDot = nil, limit

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local ped = GetPlayerPed(player)
            if ped ~= 0 and IsEntityVisible(ped) then
                local coords = GetEntityCoords(ped)
                local distance = #(coords - myCoords)
                if distance <= maxDistance then
                    local toPed = coords + vector3(0.0, 0.0, SIGHT_AIM_HEIGHT) - camera
                    local length = #toPed
                    local dot = length > 0 and (toPed.x * forward.x + toPed.y * forward.y + toPed.z * forward.z) / length or -1
                    if dot > bestDot and HasEntityClearLosToEntity(myPed, ped, LOS_FLAGS) then
                        best = { serverId = GetPlayerServerId(player), ped = ped, distance = distance }
                        bestDot = dot
                    end
                end
            end
        end
    end
    return best
end

-- Kreis am Boden unter einem Spieler (Server-ID). Jeden Frame aufrufen, solange er sichtbar sein soll.
-- style: { type, size, zOffset, rotate, color = { r, g, b }, alpha }. Werte kommen aus data/ der aufrufenden Resource.
function Platform.DrawPlayerRing(serverId, style)
    local player = GetPlayerFromServerId(serverId)
    local ped = player ~= -1 and GetPlayerPed(player) or 0
    if ped == 0 then
        return false
    end
    local coords = GetEntityCoords(ped)
    local color = style.color
    DrawMarker(style.type, coords.x, coords.y, coords.z + style.zOffset,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        style.size, style.size, style.size,
        color.r, color.g, color.b, style.alpha,
        false, false, 2, style.rotate == true, nil, nil, false)
    return true
end

function Platform.HasLineOfSight(ped)
    local myPed = PlayerPedId()
    return ped == myPed or HasEntityClearLosToEntity(myPed, ped, LOS_FLAGS)
end

function Platform.IsPedVisible(ped)
    return DoesEntityExist(ped) and IsEntityVisible(ped)
end

function Platform.GetOwnPed()
    return PlayerPedId()
end

-- Durchsichtigkeit nur in der eigenen Ansicht, darum setzt jeder Client sie selbst
function Platform.SetPedAlpha(ped, alpha)
    if DoesEntityExist(ped) and GetEntityAlpha(ped) ~= alpha then
        SetEntityAlpha(ped, alpha, false)
    end
end

function Platform.ResetPedAlpha(ped)
    if DoesEntityExist(ped) then
        ResetEntityAlpha(ped)
    end
end

-- Sowohl Ped als auch Spieler: Manche Scripts setzen nur eines davon zurueck
function Platform.SetInvincible(enabled)
    SetEntityInvincible(PlayerPedId(), enabled)
    SetPlayerInvincible(PlayerId(), enabled)
end

-- style: { Scale, HeightOffset, Color = { r, g, b, a }, Glow = { r, g, b, a }? }
-- Text in der Welt. lines: Liste von Zeilen, jede Zeile ein Text oder eine Liste von Teilen { text, tone }.
-- tone: 'normal', 'muted', 'accent', 'info', 'warning', 'danger'. Nur hier stehen die GTA-Farbcodes.
-- Einmal vorbereiten (z. B. alle 250 ms), dann jeden Frame mit DrawTextAbovePed zeichnen.
local TONE_CODES = {
    normal  = '~s~', -- Standardfarbe aus dem Stil
    muted   = '~c~',
    accent  = '~y~',
    info    = '~b~',
    warning = '~o~',
    danger  = '~r~',
}
local LINE_BREAK = '~n~'

-- Namen und Texte duerfen keine eigenen GTA-Codes einschleusen
local function plain(text)
    return (tostring(text or ''):gsub('~[^~]*~', ''):gsub('~', ''))
end

local function lineText(line)
    if type(line) ~= 'table' then
        return plain(line)
    end
    local parts = {}
    for _, part in ipairs(line) do
        if type(part) == 'table' then
            parts[#parts + 1] = (TONE_CODES[part.tone] or TONE_CODES.normal) .. plain(part.text)
        else
            parts[#parts + 1] = TONE_CODES.normal .. plain(part)
        end
    end
    return table.concat(parts)
end

function Platform.PrepareWorldText(lines)
    if type(lines) ~= 'table' then
        return plain(lines)
    end
    local out = {}
    for _, line in ipairs(lines) do
        out[#out + 1] = lineText(line)
    end
    return table.concat(out, LINE_BREAK)
end

-- text: Ergebnis von Platform.PrepareWorldText
function Platform.DrawTextAbovePed(ped, text, style)
    if not DoesEntityExist(ped) then
        return
    end
    local head = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
    local color = style.Color

    SetDrawOrigin(head.x, head.y, head.z + style.HeightOffset, 0)
    SetTextScale(0.0, style.Scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(color[1], color[2], color[3], color[4])
    if style.Glow then
        local glow = style.Glow
        SetTextEdge(2, glow[1], glow[2], glow[3], glow[4])
        SetTextDropshadow(0, glow[1], glow[2], glow[3], glow[4])
    else
        SetTextOutline()
    end
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

------------------------------------------------------------------------
-- Teleport, Befehle, Meldungen
------------------------------------------------------------------------

local TELEPORT_COLLISION_TIMEOUT_MS = 3000
local GROUND_PROBE_HEIGHT = 50.0 -- von so weit oben wird der Boden gesucht

local GROUND_SCAN_TOP = 950.0   -- ohne bekannte Hoehe von hier aus nach unten suchen
local GROUND_SCAN_STEP = 50.0

-- Boden unter x, y finden. Erst direkt, sonst schrittweise von oben, weil die Karte erst geladen werden muss.
local function findGround(ped, x, y, z)
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + GROUND_PROBE_HEIGHT, false)
    if found then
        return groundZ
    end
    for height = GROUND_SCAN_TOP, 0, -GROUND_SCAN_STEP do
        SetEntityCoordsNoOffset(ped, x, y, height, false, false, false)
        RequestCollisionAtCoord(x, y, height)
        Wait(0)
        found, groundZ = GetGroundZFor_3dCoord(x, y, height, false)
        if found then
            return groundZ
        end
    end
    return nil
end

-- position.ground = true: danach auf den Boden setzen, falls die Hoehe nicht genau stimmt
function Platform.TeleportTo(position)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        ClearPedTasksImmediately(ped) -- aus dem Fahrzeug, sonst wird das Fahrzeug mitgenommen
    end
    local x, y, z = position.x + 0.0, position.y + 0.0, position.z + 0.0
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    if position.heading then
        SetEntityHeading(ped, position.heading + 0.0)
    end
    local timeout = GetGameTimer() + TELEPORT_COLLISION_TIMEOUT_MS
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        Wait(0)
    end
    if position.ground then
        local groundZ = findGround(ped, x, y, z)
        if groundZ then
            SetEntityCoordsNoOffset(ped, x, y, groundZ, false, false, false)
        end
    end
end

-- Befehl im Chat plus Taste, die jeder Spieler in den GTA-Einstellungen aendern kann
-- Chat-Befehl mit Argumenten, z. B. /car adder. handler(args) laeuft in einem eigenen Thread.
function Platform.RegisterClientCommand(name, handler)
    RegisterCommand(name, function(_, args)
        CreateThread(function()
            handler(args or {})
        end)
    end, false)
end

-- FiveM benennt Tasten nach ihrer Lage auf einer englischen Tastatur (QWERTY).
-- Auf einer deutschen Tastatur liegen Y und Z vertauscht.
local LAYOUT_SWAPS = {
    de = { Y = 'Z', Z = 'Y' },
}

local function physicalKey(key)
    local swaps = LAYOUT_SWAPS[Config.Keyboard and Config.Keyboard.Layout or 'de']
    local upper = key:upper()
    return swaps and swaps[upper] or upper
end

-- Die Taste haengt an einem eigenen Befehl "core_key_<name>". FiveM merkt sich Tastenbelegungen pro Befehl,
-- ein neuer Name sorgt dafuer, dass eine geaenderte Standardtaste auch bei allen ankommt, die schon mal da waren.
local KEY_COMMAND_PREFIX = 'core_key_'

------------------------------------------------------------------------
-- Chat-Vorschlaege (Resource chat): Befehle ohne Recht ausblenden. Nur Anzeige, der Server prueft jeden Aufruf.
-- Der Chat fuegt nach jedem Resource-Start alle Befehle neu hinzu, darum wird danach erneut entfernt.
------------------------------------------------------------------------

local SUGGESTION_REAPPLY_MS = 500
local hiddenCommands = {}   -- Liste ohne "/"
local keyCommands = {}      -- Hilfsbefehle der Tasten (core_key_...), die braucht im Chat niemand
local reapplyPending = false

local function removeSuggestions()
    for _, name in ipairs(hiddenCommands) do
        TriggerEvent('chat:removeSuggestion', '/' .. name)
    end
    for _, name in ipairs(keyCommands) do
        TriggerEvent('chat:removeSuggestion', '/' .. name)
    end
end

local function scheduleRemove()
    if reapplyPending then
        return
    end
    reapplyPending = true
    SetTimeout(SUGGESTION_REAPPLY_MS, function()
        reapplyPending = false
        removeSuggestions()
    end)
end

AddEventHandler('chat:addSuggestions', scheduleRemove)
AddEventHandler('chat:addSuggestion', scheduleRemove)

function Platform.SetHiddenCommands(names)
    -- Vorher ausgeblendete, jetzt erlaubte Befehle kommen beim naechsten Neuaufbau des Chats zurueck
    local wasHidden = {}
    for _, name in ipairs(hiddenCommands) do
        wasHidden[name] = true
    end
    hiddenCommands = {}
    local now = {}
    for _, name in ipairs(type(names) == 'table' and names or {}) do
        if type(name) == 'string' then
            hiddenCommands[#hiddenCommands + 1] = name
            now[name] = true
        end
    end
    for name in pairs(wasHidden) do
        if not now[name] then
            TriggerEvent('chat:addSuggestion', '/' .. name, '')
        end
    end
    removeSuggestions()
end

-- Der Befehl selbst reicht seine Argumente (Liste von Woertern) an handler weiter, die Taste nicht
function Platform.RegisterKeyCommand(name, description, defaultKey, handler)
    RegisterCommand(name, function(_, args)
        CreateThread(function()
            handler(args or {})
        end)
    end, false)
    if defaultKey then
        local keyCommand = KEY_COMMAND_PREFIX .. name
        keyCommands[#keyCommands + 1] = keyCommand
        RegisterCommand(keyCommand, function()
            CreateThread(handler)
        end, false)
        RegisterKeyMapping(keyCommand, description, 'keyboard', physicalKey(defaultKey))
    end
end

function Platform.Notify(message)
    TriggerEvent('chat:addMessage', { args = { 'Core', message } })
end

------------------------------------------------------------------------
-- Fahrzeuge
------------------------------------------------------------------------

local VEHICLE_SPAWN_OFFSET = 2.0 -- Meter vor dem Spieler, falls er nicht einsteigen kann
local KMH_PER_MS = 3.6

function Platform.IsVehicleModel(model)
    local hash = GetHashKey(model)
    return IsModelInCdimage(hash) and IsModelAVehicle(hash)
end

-- Fahrzeug, in dem man am Steuer sitzt, oder nil
function Platform.GetDrivenVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, DRIVER_SEAT) == ped then
        return vehicle
    end
    return nil
end

-- Fahrzeug, in dem man sitzt, sonst das naechste im Umkreis
function Platform.GetVehicleNearby(radius)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        return vehicle
    end
    local coords = GetEntityCoords(ped)
    local best, bestDistance = nil, radius
    for _, candidate in ipairs(GetGamePool('CVehicle')) do
        local distance = #(GetEntityCoords(candidate) - coords)
        if distance <= bestDistance then
            best, bestDistance = candidate, distance
        end
    end
    return best
end

function Platform.GetVehicleInfo(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then
        return nil
    end
    return {
        netId = NetworkGetEntityIsNetworked(vehicle) and VehToNet(vehicle) or nil,
        model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)),
        plate = GetVehicleNumberPlateText(vehicle),
    }
end

-- Spawnt das Fahrzeug und setzt den Spieler ans Steuer. Gibt das Fahrzeug oder nil und einen Fehlercode zurueck.
function Platform.SpawnVehicle(model, plate, timeoutMs)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        return nil, 'invalid_model'
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + timeoutMs
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            return nil, 'model_timeout'
        end
        Wait(0)
    end

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, VEHICLE_SPAWN_OFFSET, 0.0)
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    SetModelAsNoLongerNeeded(hash)
    if vehicle == 0 then
        return nil, 'spawn_failed'
    end
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetPedIntoVehicle(ped, vehicle, DRIVER_SEAT)
    return vehicle
end

-- Boost: einmal setzen, danach jeden Frame die Motorleistung erhoehen
function Platform.SetVehicleBoost(vehicle, percent, topSpeedKmh)
    if not DoesEntityExist(vehicle) then
        return
    end
    if percent > 0 then
        ModifyVehicleTopSpeed(vehicle, percent + 0.0)
        SetVehicleMaxSpeed(vehicle, topSpeedKmh / KMH_PER_MS)
    else
        ModifyVehicleTopSpeed(vehicle, 0.0)
        SetVehicleMaxSpeed(vehicle, 0.0)
        SetVehicleCheatPowerIncrease(vehicle, 1.0)
    end
end

function Platform.ApplyVehicleBoostThisFrame(vehicle, percent)
    SetVehicleCheatPowerIncrease(vehicle, 1.0 + percent / 100)
end

function Platform.VehicleExists(vehicle)
    return vehicle ~= nil and DoesEntityExist(vehicle)
end

------------------------------------------------------------------------
-- Admin-Werkzeuge: heilen, Weste, einfrieren, Waffen, Fahrzeuge reparieren
------------------------------------------------------------------------

function Platform.HealSelf()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
end

-- Bewusstlos machen, auch wenn man gerade unverwundbar ist. Danach greift das Todes-System.
function Platform.KillSelf()
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetEntityHealth(ped, 0)
end

-- Gesundheit (0 bis 100), Weste und ob bewusstlos, fuer den Erkennungsmodus
local HEALTH_OFFSET = 100 -- GTA zaehlt Gesundheit von 100 (tot) bis 200 (voll)

function Platform.GetPedStatus(ped)
    if not DoesEntityExist(ped) then
        return nil
    end
    local health = GetEntityHealth(ped) - HEALTH_OFFSET
    local maxHealth = GetEntityMaxHealth(ped) - HEALTH_OFFSET
    return {
        health = maxHealth > 0 and math.max(0, math.floor(health / maxHealth * 100 + 0.5)) or 0,
        armor = GetPedArmour(ped),
        dead = IsEntityDead(ped),
    }
end

function Platform.SetArmor(value)
    SetPedArmour(PlayerPedId(), value)
end

local frozenEntities = {}

-- Ped und, wenn man am Steuer sitzt, das Fahrzeug festhalten
function Platform.SetFrozen(on)
    for _, entity in ipairs(frozenEntities) do
        if DoesEntityExist(entity) then
            FreezeEntityPosition(entity, false)
        end
    end
    frozenEntities = {}
    if not on then
        return
    end
    local ped = PlayerPedId()
    frozenEntities[1] = ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, DRIVER_SEAT) == ped then
        frozenEntities[2] = vehicle
    end
    for _, entity in ipairs(frozenEntities) do
        FreezeEntityPosition(entity, true)
    end
end

-- Erlaubt bleiben: Kamera, Chat, Funk (Push to Talk) und das Pausemenue
local FROZEN_ALLOWED_CONTROLS = { 1, 2, 199, 200, 245, 246, 249 }

-- Jeden Frame aufrufen, solange man eingefroren ist
function Platform.DisableControlsWhileFrozenThisFrame()
    DisableAllControlActions(CONTROL_GROUP)
    for _, control in ipairs(FROZEN_ALLOWED_CONTROLS) do
        EnableControlAction(CONTROL_GROUP, control, true)
    end
end

-- Waffenrad (Tab), Mausrad und Zifferntasten fuer Waffen sperren. Jeden Frame aufrufen.
-- Die eigenen Tasten 1 bis 5 (RegisterKeyMapping) laufen trotzdem, sie haengen nicht an diesen Controls.
local WEAPON_CONTROLS = {
    37,                                     -- INPUT_SELECT_WEAPON (Waffenrad, Tab)
    12, 13, 14, 15, 16, 17,                 -- Waffenrad bewegen, naechste und vorige Waffe (Mausrad)
    99, 100, 115, 116,                      -- Waffe wechseln im Fahrzeug
    157, 158, 159, 160, 161, 162, 163, 164, 165, -- INPUT_SELECT_WEAPON_* (Zifferntasten)
}
local HUD_WEAPON_WHEEL, HUD_WEAPON_WHEEL_STATS = 19, 20

function Platform.BlockWeaponWheelThisFrame()
    BlockWeaponWheelThisFrame()
    HideHudComponentThisFrame(HUD_WEAPON_WHEEL)
    HideHudComponentThisFrame(HUD_WEAPON_WHEEL_STATS)
    for i = 1, #WEAPON_CONTROLS do
        DisableControlAction(0, WEAPON_CONTROLS[i], true)
    end
end

-- Kleidung am eigenen Charakter (GTA: Komponenten und Props mit drawable und texture)
function Platform.SetOwnComponent(component, drawable, texture)
    SetPedComponentVariation(PlayerPedId(), component, drawable, texture or 0, 0)
end

function Platform.SetOwnProp(prop, drawable, texture)
    SetPedPropIndex(PlayerPedId(), prop, drawable, texture or 0, true)
end

function Platform.ClearOwnProp(prop)
    ClearPedProp(PlayerPedId(), prop)
end

-- Aendert sich das Modell (Spawn), muss die Kleidung neu gesetzt werden
function Platform.GetOwnModel()
    return GetEntityModel(PlayerPedId())
end

-- Waffe aus dem Inventar in die Hand: genau diese Munition, nichts dazu
function Platform.EquipWeapon(name, ammo)
    local ped = PlayerPedId()
    local hash = GetHashKey(name)
    if not HasPedGotWeapon(ped, hash, false) then
        GiveWeaponToPed(ped, hash, 0, false, true)
    end
    SetPedAmmo(ped, hash, math.max(0, math.floor(ammo or 0)))
    SetCurrentPedWeapon(ped, hash, true)
end

function Platform.UnequipWeapon(name)
    local ped = PlayerPedId()
    RemoveWeaponFromPed(ped, GetHashKey(name))
end

function Platform.HasWeapon(name)
    return HasPedGotWeapon(PlayerPedId(), GetHashKey(name), false)
end

-- Munition dieser Waffe oder nil, wenn man sie nicht hat
function Platform.GetWeaponAmmo(name)
    local ped = PlayerPedId()
    local hash = GetHashKey(name)
    if not HasPedGotWeapon(ped, hash, false) then
        return nil
    end
    return GetAmmoInPedWeapon(ped, hash)
end

function Platform.GiveWeapon(name, ammo)
    GiveWeaponToPed(PlayerPedId(), GetHashKey(name), ammo, false, true)
end

function Platform.RemoveWeapon(name)
    RemoveWeaponFromPed(PlayerPedId(), GetHashKey(name))
end

local RAY_VEHICLES = 2       -- Shape-Test nur gegen Fahrzeuge
local RAY_SEE_THROUGH = 7

-- Fahrzeug, in dem man sitzt, sonst das, auf das die Kamera zeigt
function Platform.GetVehicleInSight(maxDistance)
    local ped = PlayerPedId()
    local own = GetVehiclePedIsIn(ped, false)
    if own ~= 0 then
        return own
    end
    local from = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local direction = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local to = from + direction * maxDistance
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, RAY_VEHICLES, ped, RAY_SEE_THROUGH)
    local _, hit, _, _, entity = GetShapeTestResult(handle)
    if hit == 1 and entity ~= 0 and IsEntityAVehicle(entity) then
        return entity
    end
    return nil
end

function Platform.VehicleFromNetId(netId)
    if not NetworkDoesNetworkIdExist(netId) then
        return nil
    end
    local vehicle = NetToVeh(netId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end
    return vehicle
end

-- Kofferraum: naechstes Fahrzeug mit Abstand zum Kofferraum. GTA kennt den Knochen "boot",
-- bei Fahrzeugen mit Kofferraum vorne liegt er vorne. Fehlt er, gilt das Heck.
local DOOR_TRUNK = 5
local LOCK_LOCKED_FROM = 2

function Platform.GetNearestVehicleTrunk(maxDistance)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= 0 then
        return nil
    end
    local me = GetEntityCoords(ped)
    local best, bestDistance = nil, maxDistance
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local distance = #(GetEntityCoords(vehicle) - me)
        if distance < bestDistance then
            best, bestDistance = vehicle, distance
        end
    end
    if not best or not NetworkGetEntityIsNetworked(best) then
        return nil
    end
    local trunk
    local bone = GetEntityBoneIndexByName(best, 'boot')
    if bone ~= -1 then
        trunk = GetWorldPositionOfEntityBone(best, bone)
    else
        local minimum = GetModelDimensions(GetEntityModel(best))
        trunk = GetOffsetFromEntityInWorldCoords(best, 0.0, minimum.y, 0.0)
    end
    return {
        vehicle = best,
        netId = NetworkGetNetworkIdFromEntity(best),
        class = GetVehicleClass(best),
        trunkDistance = #(trunk - me),
        locked = GetVehicleDoorLockStatus(best) >= LOCK_LOCKED_FROM,
    }
end

function Platform.SetVehicleTrunkOpen(vehicle, open)
    if not vehicle or not DoesEntityExist(vehicle) then
        return
    end
    if open then
        SetVehicleDoorOpen(vehicle, DOOR_TRUNK, false, false)
    else
        SetVehicleDoorShut(vehicle, DOOR_TRUNK, false)
    end
end

function Platform.GetDistanceToEntity(entity)
    if not entity or not DoesEntityExist(entity) then
        return nil
    end
    return #(GetEntityCoords(entity) - GetEntityCoords(PlayerPedId()))
end

function Platform.IsOwnPedInVehicle()
    return GetVehiclePedIsIn(PlayerPedId(), false) ~= 0
end

-- Haende hoch: Oberkoerper-Animation in Schleife, laufen bleibt moeglich
local HANDS_UP_DICT, HANDS_UP_ANIM = 'missminuteman_1ig_2', 'handsup_base'
local ANIM_UPPER_BODY_LOOP = 49
local ANIM_LOAD_TIMEOUT_MS = 2000

function Platform.SetHandsUp(on)
    local ped = PlayerPedId()
    if not on then
        StopAnimTask(ped, HANDS_UP_DICT, HANDS_UP_ANIM, 2.0)
        return true
    end
    RequestAnimDict(HANDS_UP_DICT)
    local timeout = GetGameTimer() + ANIM_LOAD_TIMEOUT_MS
    while not HasAnimDictLoaded(HANDS_UP_DICT) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end
    TaskPlayAnim(ped, HANDS_UP_DICT, HANDS_UP_ANIM, 4.0, 4.0, -1, ANIM_UPPER_BODY_LOOP, 0.0, false, false, false)
    RemoveAnimDict(HANDS_UP_DICT)
    return true
end

function Platform.IsHandsUpPlaying()
    return IsEntityPlayingAnim(PlayerPedId(), HANDS_UP_DICT, HANDS_UP_ANIM, 3)
end

-- Mit Haenden oben nicht schiessen, zielen oder schlagen. Jeden Frame aufrufen.
local COMBAT_CONTROLS = { 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 }

function Platform.BlockCombatThisFrame()
    DisablePlayerFiring(PlayerId(), true)
    for i = 1, #COMBAT_CONTROLS do
        DisableControlAction(0, COMBAT_CONTROLS[i], true)
    end
end

function Platform.RepairVehicle(vehicle)
    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehiclePetrolTankHealth(vehicle, 1000.0)
    SetVehicleUndriveable(vehicle, false)
end

-- Fahrzeug mit allen Insassen versetzen. position.ground = true: danach auf den Boden setzen.
function Platform.TeleportVehicleTo(vehicle, position)
    local x, y, z = position.x + 0.0, position.y + 0.0, position.z + 0.0
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoords(vehicle, x, y, z, false, false, false, false)
    if position.heading then
        SetEntityHeading(vehicle, position.heading + 0.0)
    end
    local timeout = GetGameTimer() + TELEPORT_COLLISION_TIMEOUT_MS
    while not HasCollisionLoadedAroundEntity(vehicle) and GetGameTimer() < timeout do
        Wait(0)
    end
    if position.ground then
        local groundZ = findGround(vehicle, x, y, z)
        if groundZ then
            SetEntityCoords(vehicle, x, y, groundZ, false, false, false, false)
        end
    end
    SetVehicleOnGroundProperly(vehicle)
end

------------------------------------------------------------------------
-- Beobachten (Spectate)
------------------------------------------------------------------------

-- Ped eines anderen Spielers oder nil, wenn er nicht in Reichweite geladen ist
function Platform.GetPlayerPedByServerId(serverId)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then
        return nil
    end
    local ped = GetPlayerPed(player)
    if ped == 0 or not DoesEntityExist(ped) then
        return nil
    end
    return ped
end

function Platform.GetEntityPosition(entity)
    local coords = GetEntityCoords(entity)
    return { x = coords.x, y = coords.y, z = coords.z }
end

-- Eigenen Ped verstecken: unsichtbar fuer alle, ohne Kollision, festgehalten, unverwundbar
function Platform.SetSpectatorHidden(hidden)
    local ped = PlayerPedId()
    if hidden and IsPedInAnyVehicle(ped, false) then
        ClearPedTasksImmediately(ped)
    end
    FreezeEntityPosition(ped, hidden)
    SetEntityCollision(ped, not hidden, not hidden)
    SetEntityVisible(ped, not hidden, false)
    SetEntityInvincible(ped, hidden)
end

-- Eigenen Ped ohne Warten versetzen (der Ped ist dabei versteckt)
function Platform.MoveOwnPedTo(position)
    SetEntityCoordsNoOffset(PlayerPedId(), position.x + 0.0, position.y + 0.0, position.z + 0.0, false, false, false)
end

-- Kamera auf einen anderen Ped setzen, nil beendet
function Platform.SetSpectating(ped)
    if ped then
        NetworkSetInSpectatorMode(true, ped)
    else
        NetworkSetInSpectatorMode(false, PlayerPedId())
    end
end

------------------------------------------------------------------------
-- Fuer andere Resources (Inventar): lokale Ereignisse, Gesundheit, Gegenstaende in der Welt
------------------------------------------------------------------------

-- Ereignis im eigenen Client, z. B. Platform.Emit('core:notify', { text = '...', type = 'info' })
function Platform.Emit(event, data)
    TriggerEvent(event, data)
end

-- Gesundheit erhoehen (GTA: 100 bewusstlos bis 200 voll), nie ueber das Maximum
function Platform.AddHealth(amount)
    local ped = PlayerPedId()
    if IsEntityDead(ped) then
        return
    end
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + math.floor(amount)))
end

-- Export fuer andere Resources im Client, z. B. exports.core:GetNeeds()
function Platform.Export(name, fn)
    exports(name, fn)
end

-- Lage der Minimap als Anteil des Bildschirms (0 bis 1), damit HUDs daneben andocken koennen
function Platform.GetMinimapRect()
    local safezone = GetSafeZoneSize()
    local margin = (1.0 / 20.0) * (math.abs(safezone - 1.0) * 10)
    local aspect = GetAspectRatio(false)
    local resX, resY = GetActiveScreenResolution()
    local width = (resX / (4 * aspect)) / resX
    local height = (resY / 5.674) / resY
    local left = margin
    local bottom = 1.0 - margin
    return { left = left, right = left + width, top = bottom - height, bottom = bottom, resX = resX, resY = resY }
end

function Platform.IsPauseMenuOpen()
    return IsPauseMenuActive()
end

-- Minimap gerade zu sehen (kein Pausemenue, Radar nicht ausgeblendet)
function Platform.IsMinimapVisible()
    return not IsPauseMenuActive() and not IsRadarHidden()
end

function Platform.IsOwnPedDead()
    return IsEntityDead(PlayerPedId())
end

function Platform.GetOwnPosition()
    local coords = GetEntityCoords(PlayerPedId())
    return { x = coords.x, y = coords.y, z = coords.z }
end

local PROP_LOAD_TIMEOUT_MS = 2000

-- Objekt nur fuer diesen Client (nicht vernetzt), z. B. ein Beutel fuer Items am Boden
function Platform.CreateLocalProp(model, position)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then
        return nil
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + PROP_LOAD_TIMEOUT_MS
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(0)
    end
    if not HasModelLoaded(hash) then
        return nil
    end
    local object = CreateObject(hash, position.x + 0.0, position.y + 0.0, position.z + 0.0, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if object == 0 then
        return nil
    end
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    SetEntityCollision(object, false, false)
    return object
end

function Platform.DeleteLocalProp(object)
    if object and DoesEntityExist(object) then
        DeleteObject(object)
    end
end

-- Text an einer Stelle in der Welt, jeden Frame aufrufen (Text vorher mit Platform.PrepareWorldText bauen)
function Platform.DrawWorldText(position, text, style)
    local color = style.Color
    SetDrawOrigin(position.x + 0.0, position.y + 0.0, position.z + (style.HeightOffset or 0.0), 0)
    SetTextScale(0.0, style.Scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

------------------------------------------------------------------------
-- UI (NUI)
------------------------------------------------------------------------

function Platform.UiSend(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end

-- Fokus (Maus und Tastatur) fuer die UI. Solange er gewollt ist, wird er bei Verlust neu gesetzt:
-- Beim Join nimmt das Schliessen des Ladebildschirms den Fokus wieder weg, dann haette man im Login keine Maus.
local FOCUS_WATCH_MS = 250
local wantFocus = false
local wantCursor = true   -- false: nur Tastatur fuer die UI, ohne Mauszeiger (z. B. Minigames mit Tasten)
local focusWatchRunning = false

-- cursor (optional, Standard true): Mauszeiger anzeigen. Ohne Zeiger bekommt die UI nur die Tastatur.
function Platform.UiFocus(enabled, cursor)
    local hadFocus = wantFocus
    local hadCursor = wantCursor
    wantFocus = enabled == true
    wantCursor = cursor ~= false
    if wantFocus and hadFocus and hadCursor ~= wantCursor then
        SetNuiFocus(true, wantCursor)
    elseif wantFocus and hadFocus then
        -- Wechsel von einer UI zur naechsten (z. B. Login zur Charakterauswahl): Der Mauszeiger
        -- verschwindet sonst, weil die alte UI unter ihm ausgeblendet wird. Kurz aus und wieder an zeigt ihn neu.
        SetNuiFocus(false, false)
        CreateThread(function()
            Wait(0)
            if wantFocus then
                SetNuiFocus(true, wantCursor)
            end
        end)
    else
        SetNuiFocus(wantFocus, wantFocus and wantCursor)
    end
    if not wantFocus or focusWatchRunning then
        return
    end
    focusWatchRunning = true
    CreateThread(function()
        while wantFocus do
            Wait(FOCUS_WATCH_MS)
            if wantFocus and not IsNuiFocused() then
                SetNuiFocus(true, wantCursor)
            end
        end
        focusWatchRunning = false
    end)
end

-- Handler bekommt die Daten aus der UI und gibt { ok, data, error } zurueck
function Platform.UiOn(event, handler)
    RegisterNUICallback(event, function(data, cb)
        CreateThread(function()
            local ok, result = pcall(handler, data or {})
            if not ok then
                Platform.Print('error', ('Fehler im UI-Callback %s: %s'):format(event, tostring(result)))
                result = { ok = false, error = 'client_error' }
            end
            cb(result or { ok = true })
        end)
    end)
end

------------------------------------------------------------------------
-- Ressourcen (seit Core 1.8.0, fuer core_lib und andere Addons)
------------------------------------------------------------------------

-- Name der Resource, die gerade einen Export dieser Resource aufruft, sonst nil
function Platform.GetCallingResource()
    local name = GetInvokingResource()
    return name
end

-- handler(resourceName), wenn eine Resource auf diesem Client stoppt
function Platform.OnResourceStop(handler)
    AddEventHandler('onClientResourceStop', handler)
end

function Platform.OnEvent(event, handler)
    AddEventHandler(event, handler)
end

function Platform.IsResourceStarted(name)
    return GetResourceState(name) == 'started'
end

function Platform.GetResourceName()
    return GetCurrentResourceName()
end

-- Export einer anderen Resource aufrufen. Gibt nil zurueck, wenn sie nicht laeuft oder einen Fehler wirft.
function Platform.CallExport(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then
        return nil
    end
    local args = table.pack(...)
    local results = table.pack(pcall(function()
        local target = exports[resource]
        return target[name](target, table.unpack(args, 1, args.n))
    end))
    if not results[1] then
        Platform.Print('error', ('Export %s:%s fehlgeschlagen: %s'):format(resource, name, tostring(results[2])))
        return nil
    end
    return table.unpack(results, 2, results.n)
end

------------------------------------------------------------------------
-- Steuerung sperren (seit Core 1.8.0)
------------------------------------------------------------------------

-- Gruppen von GTA-5-Controls. Die Logik kennt nur die Namen.
local CONTROL_GROUPS = {
    move   = { 30, 31, 32, 33, 34, 35, 36, 21, 22, 44 },             -- laufen, rennen, springen, Deckung
    car    = { 63, 64, 71, 72, 75, 59, 60 },                         -- lenken, Gas, Bremse, aussteigen
    combat = { 24, 25, 37, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264 },
    mouse  = { 1, 2, 106 },                                          -- umsehen
}

-- groups: { move = true, car = true, combat = true, mouse = true }. Jeden Frame aufrufen.
function Platform.DisableActionsThisFrame(groups)
    for name, on in pairs(groups) do
        local list = on and CONTROL_GROUPS[name]
        if list then
            for i = 1, #list do
                DisableControlAction(CONTROL_GROUP, list[i], true)
            end
        end
    end
    if groups.combat then
        DisablePlayerFiring(PlayerId(), true)
    end
end

------------------------------------------------------------------------
-- Animationen und Props am eigenen Ped (seit Core 1.8.0)
------------------------------------------------------------------------

local ANIM_FLAG_LOOP = 1
local ANIM_FLAG_UPPER_BODY = 16
local ANIM_FLAG_CONTROLLABLE = 32
local ANIM_BLEND = 3.0
local PROP_ATTACH_TIMEOUT_MS = 2000

-- Spielt eine Animation am eigenen Ped. options: { loop, upperBody, controllable, durationMs }. Gibt true oder false zurueck.
function Platform.PlayOwnAnim(dict, clip, options)
    options = options or {}
    if type(dict) ~= 'string' or type(clip) ~= 'string' or not DoesAnimDictExist(dict) then
        return false
    end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + ANIM_LOAD_TIMEOUT_MS
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end
    local flags = 0
    if options.loop ~= false then flags = flags + ANIM_FLAG_LOOP end
    if options.upperBody then flags = flags + ANIM_FLAG_UPPER_BODY end
    if options.controllable then flags = flags + ANIM_FLAG_CONTROLLABLE end
    TaskPlayAnim(PlayerPedId(), dict, clip, ANIM_BLEND, ANIM_BLEND, tonumber(options.durationMs) or -1, flags, 0.0, false, false, false)
    RemoveAnimDict(dict)
    return true
end

function Platform.StopOwnAnim(dict, clip)
    if type(dict) == 'string' and type(clip) == 'string' then
        StopAnimTask(PlayerPedId(), dict, clip, ANIM_BLEND)
    end
end

-- Szenario (z. B. 'WORLD_HUMAN_HAMMERING') am eigenen Ped
function Platform.PlayOwnScenario(name)
    if type(name) ~= 'string' then
        return false
    end
    TaskStartScenarioInPlace(PlayerPedId(), name, 0, true)
    return true
end

function Platform.ClearOwnTasks()
    ClearPedTasks(PlayerPedId())
end

-- Objekt an einem Knochen des eigenen Peds. bone ist die GTA-Knochen-ID, pos und rot { x, y, z }.
-- Gibt das Objekt zurueck (spaeter mit Platform.DeleteLocalProp entfernen) oder nil.
function Platform.AttachPropToOwnPed(model, bone, pos, rot)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then
        return nil
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + PROP_ATTACH_TIMEOUT_MS
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            return nil
        end
        Wait(0)
    end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local object = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if object == 0 then
        return nil
    end
    pos, rot = pos or {}, rot or {}
    AttachEntityToEntity(object, ped, GetPedBoneIndex(ped, tonumber(bone) or 0),
        (pos.x or 0.0) + 0.0, (pos.y or 0.0) + 0.0, (pos.z or 0.0) + 0.0,
        (rot.x or 0.0) + 0.0, (rot.y or 0.0) + 0.0, (rot.z or 0.0) + 0.0,
        true, true, false, true, 1, true)
    SetEntityCollision(object, false, false)
    return object
end

------------------------------------------------------------------------
-- Fahrzeug, in dem man sitzt (seit Core 1.8.0, fuer das G-Menue der core_lib)
-- Tueren und Fenster werden ueber die GTA-Indizes aus data/vehicle_gta5.lua der core_lib angesprochen.
------------------------------------------------------------------------

local KMH_PER_METER_SECOND = 3.6
local MAX_DOOR_INDEX = 7
local WINDOW_BONES = { [0] = 'window_lf', [1] = 'window_rf', [2] = 'window_lr', [3] = 'window_rr' }
local windowsDown = {}   -- [vehicle] = { [index] = true }, GTA kennt den Zustand nicht selbst

-- Stand des eigenen Fahrzeugs oder nil, wenn man nicht in einem sitzt
-- { vehicle, seat, isDriver, engine, lights, speedKmh, freeSeats = { seat, ... } }
function Platform.GetOwnVehicleState()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        return nil
    end
    local seat = nil
    local maxSeat = GetVehicleMaxNumberOfPassengers(vehicle) - 1
    local free = {}
    for index = DRIVER_SEAT, maxSeat do
        local occupant = GetPedInVehicleSeat(vehicle, index)
        if occupant == ped then
            seat = index
        elseif occupant == 0 then
            free[#free + 1] = index
        end
    end
    local _, lightsOn, highBeams = GetVehicleLightsState(vehicle)
    return {
        vehicle = vehicle,
        seat = seat,
        isDriver = seat == DRIVER_SEAT,
        engine = GetIsVehicleEngineRunning(vehicle),
        lights = lightsOn == 1 or highBeams == 1,
        speedKmh = GetEntitySpeed(vehicle) * KMH_PER_METER_SECOND,
        freeSeats = free,
    }
end

-- Fahrzeug fuer die naechsten Aufrufe noch gueltig?
function Platform.IsOwnVehicle(vehicle)
    return vehicle ~= nil and DoesEntityExist(vehicle) and GetVehiclePedIsIn(PlayerPedId(), false) == vehicle
end

function Platform.SetVehicleEngine(vehicle, on)
    if not Platform.IsOwnVehicle(vehicle) then return false end
    SetVehicleEngineOn(vehicle, on == true, false, true)
    -- Ohne das startet GTA den Motor beim naechsten Gasgeben von selbst wieder
    SetVehicleUndriveable(vehicle, on ~= true)
    return true
end

-- Licht: an (true) oder aus (false). GTA schaltet sonst nach Tageszeit.
function Platform.SetVehicleLights(vehicle, on)
    if not Platform.IsOwnVehicle(vehicle) then return false end
    SetVehicleLights(vehicle, on and 3 or 1) -- 3 = immer an, 1 = immer aus
    return true
end

function Platform.HasVehicleDoor(vehicle, index)
    index = tonumber(index)
    if not vehicle or not DoesEntityExist(vehicle) or not index or index < 0 or index > MAX_DOOR_INDEX then
        return false
    end
    return GetIsDoorValid(vehicle, index) and not IsVehicleDoorDamaged(vehicle, index)
end

function Platform.IsVehicleDoorOpen(vehicle, index)
    return Platform.HasVehicleDoor(vehicle, index) and GetVehicleDoorAngleRatio(vehicle, index) > 0.0
end

function Platform.SetVehicleDoor(vehicle, index, open)
    if not Platform.IsOwnVehicle(vehicle) or not Platform.HasVehicleDoor(vehicle, index) then return false end
    if open then
        SetVehicleDoorOpen(vehicle, index, false, false)
    else
        SetVehicleDoorShut(vehicle, index, false)
    end
    return true
end

function Platform.CloseAllVehicleDoors(vehicle)
    if not Platform.IsOwnVehicle(vehicle) then return false end
    SetVehicleDoorsShut(vehicle, false)
    return true
end

function Platform.HasVehicleWindow(vehicle, index)
    local bone = WINDOW_BONES[tonumber(index)]
    return bone ~= nil and vehicle ~= nil and DoesEntityExist(vehicle) and GetEntityBoneIndexByName(vehicle, bone) ~= -1
end

function Platform.IsVehicleWindowDown(vehicle, index)
    local state = windowsDown[vehicle]
    return state ~= nil and state[tonumber(index)] == true
end

function Platform.SetVehicleWindow(vehicle, index, down)
    index = tonumber(index)
    if not Platform.IsOwnVehicle(vehicle) or not Platform.HasVehicleWindow(vehicle, index) then return false end
    windowsDown[vehicle] = windowsDown[vehicle] or {}
    if down then
        RollDownWindow(vehicle, index)
        windowsDown[vehicle][index] = true
    else
        RollUpWindow(vehicle, index)
        windowsDown[vehicle][index] = nil
    end
    -- Nicht mehr existierende Fahrzeuge vergessen
    for handle in pairs(windowsDown) do
        if not DoesEntityExist(handle) then
            windowsDown[handle] = nil
        end
    end
    return true
end

-- Auf einen freien Sitz desselben Fahrzeugs wechseln
function Platform.MoveToSeat(vehicle, seat)
    seat = tonumber(seat)
    if not Platform.IsOwnVehicle(vehicle) or not seat or not IsVehicleSeatFree(vehicle, seat) then
        return false
    end
    SetPedIntoVehicle(PlayerPedId(), vehicle, seat)
    return true
end
