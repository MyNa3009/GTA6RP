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
    cancel        = { control = 73, label = 'X' },      -- INPUT_VEH_DUCK, Abbrechen (z. B. Fortschrittsbalken der core_lib)
    interact      = { control = 38, label = 'E' },      -- INPUT_PICKUP, an einem Punkt etwas tun (seit Core 1.10.0)
    emergency     = { control = 74, label = 'H' },      -- INPUT_VEH_HEADLIGHT, Zusatzaktion im Bewusstlos-Bildschirm (seit Core 1.15.0). Nicht G: das ist das G-Menue.
}
local CONTROL_GROUP = 0

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
-- Noclip wie bei txAdmin (seit Core 1.8.1)
-- Freie Kamera, der Ped (und das Fahrzeug) wird alle 100 Frames hinterhergezogen. Nachgebaut nach txAdmin
-- (resource/menu/client/cl_player_mode.lua und vendor/freecam, MIT, Copyright 2019-2025 Take-Two Interactive
-- Software, Inc. und Copyright 2021 Deltanic, https://github.com/Deltanic/fivem-freecam).
-- Tasten wie dort: W A S D, Q hoch, E runter, Shift 6x schneller, Alt 6x langsamer, Maus schaut.
------------------------------------------------------------------------

local NOCLIP_CONTROLS = {
    LOOK_X = 1,                 -- INPUT_LOOK_LR
    LOOK_Y = 2,                 -- INPUT_LOOK_UD
    MOVE_X = 30,                -- INPUT_MOVE_LR (A D)
    MOVE_Y = 31,                -- INPUT_MOVE_UD (W S)
    MOVE_Z = { 152, 153 },      -- INPUT_PARACHUTE_BRAKE_LEFT (Q hoch), INPUT_PARACHUTE_BRAKE_RIGHT (E runter)
    MOVE_FAST = 21,             -- INPUT_SPRINT (Shift)
    MOVE_SLOW = 19,             -- INPUT_CHARACTER_WHEEL (Alt)
}
-- Mit Controller: RT schneller, LT langsamer (wie bei txAdmin)
local NOCLIP_GAMEPAD_FAST = 71  -- INPUT_VEH_ACCELERATE
local NOCLIP_GAMEPAD_SLOW = 72  -- INPUT_VEH_BRAKE
local NOCLIP_PED_SYNC_FRAMES = 100        -- so oft wird der Ped zur Kamera gezogen
local NOCLIP_TELEPORT_DISTANCE = 3.0      -- weiter weg gesetzt (z. B. /tp im Noclip): Kamera springt mit
local NOCLIP_PITCH_LIMIT = 90.0
local NOCLIP_FALL_MIN_HEIGHT = 4.0        -- darunter kein Fall-Schutz
local NOCLIP_FALL_DISTANCE = 9000.0
local NOCLIP_FALL_AWAIT_MS = 1000
local NOCLIP_FALL_STEP_MS = 25
local NOCLIP_FALL_POLL_MS = 50
local NOCLIP_FALL_SETTLE_MS = 750
local NOCLIP_VEHICLE_ALPHA = 125
local NOCLIP_VEHICLE_ALPHA_MS = 2000
-- Aus txAdmin (lineare Regression ueber zwei Messpunkte): Kraft nach unten, damit hohe Faelle nicht ewig dauern
local NOCLIP_FALL_COEFFICIENT = 1.6428571428571428
local NOCLIP_FALL_INTERCEPT = 3.5714285714285836
local NOCLIP_SCALEFORM_CLEAR_SPACE = 200
local NOCLIP_SCALEFORM_BACKGROUND_ALPHA = 80

local noclip = {
    active = false,
    camera = nil,
    pos = nil, rot = nil, vecX = nil, vecY = nil,
    vehicle = 0,
    settings = nil,
    labels = nil,
}

local function clamp(x, low, high)
    return math.min(math.max(x, low), high)
end

local function eulerToMatrix(rotX, rotY, rotZ)
    local radX, radY, radZ = math.rad(rotX), math.rad(rotY), math.rad(rotZ)
    local sinX, sinY, sinZ = math.sin(radX), math.sin(radY), math.sin(radZ)
    local cosX, cosY, cosZ = math.cos(radX), math.cos(radY), math.cos(radZ)
    local vecX = vector3(cosY * cosZ, cosY * sinZ, -sinY)
    local vecY = vector3(cosZ * sinX * sinY - cosX * sinZ, cosX * cosZ - sinX * sinY * sinZ, cosY * sinX)
    return vecX, vecY
end

local function isGamepad()
    return not IsUsingKeyboard(2)
end

local function controlNormal(control)
    if type(control) == 'table' then
        return GetDisabledControlNormal(CONTROL_GROUP, control[1]) - GetDisabledControlNormal(CONTROL_GROUP, control[2])
    end
    return GetDisabledControlNormal(CONTROL_GROUP, control)
end

local function setCamPosition(x, y, z)
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    SetCamCoord(noclip.camera, x, y, z)
    LockMinimapPosition(x, y)
    noclip.pos = vector3(x, y, z)
end

local function setCamRotation(x, y, z)
    local rotX = clamp(x, -NOCLIP_PITCH_LIMIT, NOCLIP_PITCH_LIMIT)
    local rotY = y % 360
    local rotZ = z % 360
    noclip.vecX, noclip.vecY = eulerToMatrix(rotX, rotY, rotZ)
    LockMinimapAngle(math.floor(rotZ))
    SetCamRot(noclip.camera, rotX, rotY, rotZ, 2)
    noclip.rot = vector3(rotX, rotY, rotZ)
end

local function speedMultiplier()
    local s = noclip.settings
    local gamepad = isGamepad()
    local fastNormal = controlNormal(gamepad and NOCLIP_GAMEPAD_FAST or NOCLIP_CONTROLS.MOVE_FAST)
    local slowNormal = controlNormal(gamepad and NOCLIP_GAMEPAD_SLOW or NOCLIP_CONTROLS.MOVE_SLOW)
    local fast = 1 + ((s.FastMultiplier - 1) * fastNormal)
    local slow = 1 + ((s.SlowMultiplier - 1) * slowNormal)
    return s.BaseSpeed * fast / slow * (GetFrameTime() * 60)
end

-- Ein Frame Kamera, Rechnung wie bei txAdmin. Gibt Position und Blickrichtung zurueck.
local function updateCamera()
    if IsPauseMenuActive() then
        return nil
    end
    local s = noclip.settings
    local sensitivity = isGamepad() and s.GamepadLookSensitivity or s.LookSensitivity
    local speed = speedMultiplier()
    local lookX = controlNormal(NOCLIP_CONTROLS.LOOK_X)
    local lookY = controlNormal(NOCLIP_CONTROLS.LOOK_Y)
    local moveX = controlNormal(NOCLIP_CONTROLS.MOVE_X)
    local moveY = controlNormal(NOCLIP_CONTROLS.MOVE_Y)
    local moveZ = controlNormal(NOCLIP_CONTROLS.MOVE_Z)

    local rot = noclip.rot
    local rotX = rot.x + (-lookY * sensitivity)
    local rotZ = rot.z + (-lookX * sensitivity)

    local pos = noclip.pos
    pos = pos + (noclip.vecX * moveX * speed)
    pos = pos + (noclip.vecY * -moveY * speed)
    pos = pos + (vector3(0.0, 0.0, 1.0) * moveZ * speed)

    setCamPosition(pos.x, pos.y, pos.z)
    setCamRotation(rotX, rot.y, rotZ)
    return noclip.pos, noclip.rot.z
end

local function makeInstructionalScaleform(keys)
    local scaleform = RequestScaleformMovie('instructional_buttons')
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(10)
    end
    BeginScaleformMovieMethod(scaleform, 'CLEAR_ALL')
    EndScaleformMovieMethod()
    BeginScaleformMovieMethod(scaleform, 'SET_CLEAR_SPACE')
    ScaleformMovieMethodAddParamInt(NOCLIP_SCALEFORM_CLEAR_SPACE)
    EndScaleformMovieMethod()
    for index, key in ipairs(keys) do
        BeginScaleformMovieMethod(scaleform, 'SET_DATA_SLOT')
        ScaleformMovieMethodAddParamInt(index - 1)
        ScaleformMovieMethodAddParamPlayerNameString(GetControlInstructionalButton(CONTROL_GROUP, key[2], true))
        BeginTextCommandScaleformString('STRING')
        AddTextComponentSubstringKeyboardDisplay(key[1])
        EndTextCommandScaleformString()
        EndScaleformMovieMethod()
    end
    BeginScaleformMovieMethod(scaleform, 'DRAW_INSTRUCTIONAL_BUTTONS')
    EndScaleformMovieMethod()
    BeginScaleformMovieMethod(scaleform, 'SET_BACKGROUND_COLOUR')
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(NOCLIP_SCALEFORM_BACKGROUND_ALPHA)
    EndScaleformMovieMethod()
    return scaleform
end

-- Nach dem Noclip in der Luft: schnell nach unten, ohne Ragdoll und ohne Schaden bis zur Landung (wie txAdmin)
local function protectFall()
    CreateThread(function()
        local ped = PlayerPedId()
        local height = GetEntityHeightAboveGround(ped)
        if height == nil or height < NOCLIP_FALL_MIN_HEIGHT then
            return
        end
        local player = PlayerId()
        SetEntityInvincible(ped, true)
        SetPlayerFallDistance(player, NOCLIP_FALL_DISTANCE)
        local force = NOCLIP_FALL_COEFFICIENT * height + NOCLIP_FALL_INTERCEPT
        ApplyForceToEntity(ped, 3, 0.0, 0.0, -force, 0.0, 0.0, 0.0, 0, true, true, true, false, true)

        local waited = 0
        while not IsPedFalling(ped) do
            if waited >= NOCLIP_FALL_AWAIT_MS then
                SetEntityInvincible(ped, false)
                SetPlayerFallDistance(player, -1)
                return
            end
            waited = waited + NOCLIP_FALL_STEP_MS
            Wait(NOCLIP_FALL_STEP_MS)
        end
        repeat
            Wait(NOCLIP_FALL_POLL_MS)
        until not IsPedFalling(ped)
        Wait(NOCLIP_FALL_SETTLE_MS)
        SetEntityInvincible(ped, false)
        SetPlayerFallDistance(player, -1)
    end)
end

local function startNoclipThreads()
    local ped = PlayerPedId()

    -- Kamera und Ped
    CreateThread(function()
        local start = GetEntityCoords(ped)
        setCamPosition(start.x, start.y, start.z)
        local lastSet = start
        local frame = 0
        local loopPos, loopRotZ

        local function updatePed(pos, rotZ)
            if pos == nil or rotZ == nil then
                return
            end
            SetEntityCoords(ped, pos.x, pos.y, pos.z, false, false, false, false)
            SetEntityHeading(ped, rotZ)
            local vehicle = noclip.vehicle
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                SetEntityCoords(vehicle, pos.x, pos.y, pos.z, false, false, false, false)
                SetEntityHeading(vehicle, rotZ)
            end
            lastSet = pos
        end

        while noclip.active do
            -- Hat ein anderes Script den Ped versetzt (/tp, /goto), springt die Kamera mit
            local coords = GetEntityCoords(ped)
            if #(coords - lastSet) > NOCLIP_TELEPORT_DISTANCE then
                setCamPosition(coords.x, coords.y, coords.z)
                lastSet = coords
            end
            local pos, rotZ = updateCamera()
            if pos then
                loopPos, loopRotZ = pos, rotZ
            end
            frame = frame + 1
            if frame > NOCLIP_PED_SYNC_FRAMES then
                frame = 0
                updatePed(loopPos, loopRotZ)
            end
            Wait(0)
        end
        -- Den letzten Stand setzt Platform.SetNoclip(false) sofort selbst, damit ein Teleport danach gilt
    end)

    -- Sich selbst nicht sehen (die Kamera steckt im Ped) und Tastenhinweise unten rechts
    CreateThread(function()
        local labels = noclip.labels
        local scaleform = noclip.settings.ShowKeys and makeInstructionalScaleform({
            { labels.slower, NOCLIP_CONTROLS.MOVE_SLOW },
            { labels.faster, NOCLIP_CONTROLS.MOVE_FAST },
            { labels.down, NOCLIP_CONTROLS.MOVE_Z[2] },
            { labels.up, NOCLIP_CONTROLS.MOVE_Z[1] },
            { labels.leftRight, NOCLIP_CONTROLS.MOVE_X },
            { labels.forwardBack, NOCLIP_CONTROLS.MOVE_Y },
        })
        while noclip.active do
            SetEntityLocallyInvisible(ped)
            local vehicle = noclip.vehicle
            if vehicle ~= 0 then
                if DoesEntityExist(vehicle) then
                    SetEntityLocallyInvisible(vehicle)
                else
                    noclip.vehicle = 0
                end
            end
            if scaleform then
                DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
            end
            Wait(0)
        end
        if scaleform then
            SetScaleformMovieAsNoLongerNeeded(scaleform)
        end
    end)
end

-- enabled: an oder aus. Wirkt sofort, ohne Warten.
-- Einschalten: settings = Config.Noclip, labels = Texte der Tastenhinweise { slower, faster, down, up, leftRight, forwardBack }
-- Ausschalten: settings = { protectFall = true } fuer den Fallschutz aus der Luft (wie txAdmin). Ohne ihn,
-- wenn danach sowieso teleportiert wird (A-Jail, Beobachten).
function Platform.SetNoclip(enabled, settings, labels)
    enabled = enabled == true
    if enabled == noclip.active then
        return
    end
    local ped = PlayerPedId()

    if enabled then
        noclip.settings = settings
        noclip.labels = labels
        SetEntityVisible(ped, false, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        noclip.vehicle = GetVehiclePedIsIn(ped, false)
        local vehicle = noclip.vehicle
        if vehicle ~= 0 then
            NetworkSetEntityInvisibleToNetwork(vehicle, true)
            SetEntityCollision(vehicle, false, false)
            SetEntityVisible(vehicle, false, false)
            FreezeEntityPosition(vehicle, true)
            SetVehicleCanBreak(vehicle, false)
            SetVehicleWheelsCanBreak(vehicle, false)
        end

        local pos = GetGameplayCamCoord()
        local rot = GetGameplayCamRot(2)
        noclip.camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(noclip.camera, clamp(settings.Fov, 0.0, 90.0))
        setCamPosition(pos.x, pos.y, pos.z)
        setCamRotation(rot.x, 0.0, rot.z)
        RenderScriptCams(true, settings.Easing, settings.EasingMs, true, true)
        noclip.active = true
        startNoclipThreads()
        return
    end

    -- Aus: Ped an die Kamera, Kamera weg, Ped wieder sichtbar und beweglich
    noclip.active = false
    local hadVehicle = noclip.vehicle ~= 0 and DoesEntityExist(noclip.vehicle)
    local easing = noclip.settings and noclip.settings.Easing or false
    local easingMs = noclip.settings and noclip.settings.EasingMs or 0
    if noclip.pos and noclip.rot then
        SetEntityCoords(ped, noclip.pos.x, noclip.pos.y, noclip.pos.z, false, false, false, false)
        SetEntityHeading(ped, noclip.rot.z)
    end
    if noclip.camera then
        DestroyCam(noclip.camera, false)
        noclip.camera = nil
    end
    ClearFocus()
    UnlockMinimapAngle()
    UnlockMinimapPosition()
    RenderScriptCams(false, easing, easingMs, true, true)
    SetGameplayCamRelativeHeading(0.0)

    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)

    if hadVehicle then
        local vehicle = noclip.vehicle
        local coords = GetEntityCoords(ped)
        NetworkSetEntityInvisibleToNetwork(vehicle, false)
        SetEntityCoords(vehicle, coords.x, coords.y, coords.z, false, false, false, false)
        SetVehicleOnGroundProperly(vehicle)
        SetEntityCollision(vehicle, true, true)
        SetEntityVisible(vehicle, true, false)
        FreezeEntityPosition(vehicle, false)
        SetEntityAlpha(vehicle, NOCLIP_VEHICLE_ALPHA, false)
        SetPedIntoVehicle(ped, vehicle, DRIVER_SEAT)
        CreateThread(function()
            Wait(NOCLIP_VEHICLE_ALPHA_MS)
            ResetEntityAlpha(vehicle)
            SetVehicleCanBreak(vehicle, true)
            SetVehicleWheelsCanBreak(vehicle, true)
        end)
    elseif settings and settings.protectFall then
        protectFall()
    end
    noclip.vehicle = 0
end

function Platform.IsNoclipActive()
    return noclip.active
end

function Platform.GetFrameTime()
    return GetFrameTime()
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
-- onFootOnly (seit Core 1.9.0): Personen in einem Fahrzeug zaehlen nicht, dann gilt das Fahrzeug als Ziel.
local SIGHT_AIM_HEIGHT = 0.3   -- Brusthoehe ueber dem Mittelpunkt des Peds
-- Liegende Personen (bewusstlos, Ragdoll): Mittelpunkt liegt am Boden, darum mehrere Punkte am Koerper pruefen
local SIGHT_DOWN_HEIGHTS = { 0.3, 0.0, -0.4 }
local SIGHT_MAP_ONLY = 1                -- Strahl: nur Karte
local SIGHT_IGNORE_SEE_THROUGH = 7      -- Strahl: Glas und Aehnliches ignorieren
local SIGHT_BODY_HEIGHT = 0.2

local function isDown(ped)
    return IsEntityDead(ped) or IsPedFatallyInjured(ped) or IsPedRagdoll(ped)
end

-- Bester Winkel (Kosinus) zwischen Blickrichtung und einem der Zielpunkte am Koerper
local function aimDot(coords, heights, camera, forward)
    local best = -1
    for _, height in ipairs(heights) do
        local toPed = coords + vector3(0.0, 0.0, height) - camera
        local length = #toPed
        if length > 0 then
            local dot = (toPed.x * forward.x + toPed.y * forward.y + toPed.z * forward.z) / length
            if dot > best then
                best = dot
            end
        end
    end
    return best
end

-- Freie Sicht? Bei liegenden Personen zusaetzlich ein Strahl zum Koerper, weil die Pruefung zum Modell dort oft fehlschlaegt.
local function canSee(myPed, ped, coords, camera, down)
    if HasEntityClearLosToEntity(myPed, ped, LOS_FLAGS) then
        return true
    end
    if not down then
        return false
    end
    local handle = StartExpensiveSynchronousShapeTestLosProbe(camera.x, camera.y, camera.z, coords.x, coords.y, coords.z + SIGHT_BODY_HEIGHT,
        SIGHT_MAP_ONLY, myPed, SIGHT_IGNORE_SEE_THROUGH)
    local _, hit = GetShapeTestResult(handle)
    return hit ~= 1
end

function Platform.GetPlayerInSight(maxDistance, maxAngle, onFootOnly)
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
            if ped ~= 0 and IsEntityVisible(ped) and not (onFootOnly and IsPedInAnyVehicle(ped, false)) then
                local coords = GetEntityCoords(ped)
                local distance = #(coords - myCoords)
                if distance <= maxDistance then
                    local down = isDown(ped)
                    local dot = aimDot(coords, down and SIGHT_DOWN_HEIGHTS or { SIGHT_AIM_HEIGHT }, camera, forward)
                    if dot > bestDot and canSee(myPed, ped, coords, camera, down) then
                        best = { serverId = GetPlayerServerId(player), ped = ped, distance = distance, down = down }
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

-- Leuchtende Umrandung um ein Objekt oder Fahrzeug, nur in der eigenen Ansicht (seit Core 1.9.0).
-- style: { color = { r, g, b }, alpha, shader }. FiveM kennt nur eine Farbe fuer alle Umrandungen,
-- darum setzt jedes Einschalten Farbe und Shader neu. Zum Ausschalten reicht SetEntityOutline(entity, false).
function Platform.SetEntityOutline(entity, on, style)
    if not entity or not DoesEntityExist(entity) then
        return false
    end
    if on then
        local color = style.color
        SetEntityDrawOutlineShader(style.shader)
        SetEntityDrawOutlineColor(color.r, color.g, color.b, style.alpha)
    end
    SetEntityDrawOutline(entity, on == true)
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

-- Spawnt das Fahrzeug an einer festen Stelle (z. B. Garage einer Organisation) und setzt den Spieler ans Steuer
-- (seit Core 1.10.0). position: { x, y, z, heading }. Gibt das Fahrzeug und seine Netz-ID oder nil und einen Fehlercode.
function Platform.SpawnVehicleAt(model, plate, position, timeoutMs)
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
    local vehicle = CreateVehicle(hash, position.x + 0.0, position.y + 0.0, position.z + 0.0, (position.heading or 0.0) + 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    if vehicle == 0 then
        return nil, 'spawn_failed'
    end
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleNumberPlateText(vehicle, plate)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetPedIntoVehicle(PlayerPedId(), vehicle, DRIVER_SEAT)
    return vehicle, VehToNet(vehicle)
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

-- Fahrzeug, auf das man zu Fuss schaut (seit Core 1.9.0, G-Menue der core_lib). Gibt { vehicle, distance } oder nil.
-- Der Strahl geht aus der Kamera an der eigenen Figur vorbei nach vorne. Waende und Objekte verdecken,
-- Fahrzeuge hinter der eigenen Figur zaehlen nicht. distance ist der Abstand zur Karosserie, nicht zur Mitte.
local SIGHT_RAY_FLAGS = 1 + 2 + 16   -- Karte, Fahrzeuge, Objekte
local SIGHT_BEHIND_TOLERANCE = 1.0   -- so weit hinter der eigenen Figur zaehlt ein Treffer noch

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

function Platform.GetVehicleInSightOnFoot(maxDistance)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= 0 then
        return nil
    end
    local from = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local direction = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local myCoords = GetEntityCoords(ped)
    local pedAlong = dot(myCoords - from, direction)
    local to = from + direction * (math.max(pedAlong, 0.0) + maxDistance + SIGHT_BEHIND_TOLERANCE)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, SIGHT_RAY_FLAGS, ped, RAY_SEE_THROUGH)
    local _, hit, hitCoords, _, entity = GetShapeTestResult(handle)
    if hit ~= 1 or entity == 0 or not IsEntityAVehicle(entity) then
        return nil
    end
    if dot(hitCoords - from, direction) < pedAlong - SIGHT_BEHIND_TOLERANCE then
        return nil
    end
    local distance = #(hitCoords - myCoords)
    if distance > maxDistance then
        return nil
    end
    return { vehicle = entity, distance = distance }
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
-- Lokales Ereignis an alle Resources dieses Clients, mit beliebig vielen Werten (seit Core 1.10.1 wie auf dem Server).
-- Vorher kam nur der erste Wert an: Menue-Aktionen anderer Resources bekamen keinen Kontext und Ergebnisse
-- (Fortschritt, Dialoge) kamen leer an.
function Platform.Emit(event, ...)
    TriggerEvent(event, ...)
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
    sprint = { 21 },                                                 -- nur rennen (seit Core 1.10.0, z. B. Atemnot)
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

-- Eigene Figur sofort zu einem Spieler drehen (z. B. vor dem Hochholen), seit Core 1.10.3. Gibt true oder false zurueck.
function Platform.FacePlayer(serverId)
    local player = GetPlayerFromServerId(tonumber(serverId) or -1)
    local other = player ~= -1 and GetPlayerPed(player) or 0
    if other == 0 then
        return false
    end
    local ped = PlayerPedId()
    local from, to = GetEntityCoords(ped), GetEntityCoords(other)
    SetEntityHeading(ped, GetHeadingFromVector_2d(to.x - from.x, to.y - from.y))
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

------------------------------------------------------------------------
-- Fahrzeug von aussen (seit Core 1.9.0, fuer das G-Menue der core_lib)
------------------------------------------------------------------------

local CONTROL_TIMEOUT_MS = 600
local CONTROL_STEP_MS = 50
local ENTER_TIMEOUT_MS = 10000   -- so lange darf die Figur zur Tuer laufen
local ENTER_SPEED = 1.0          -- gehen
local ENTER_FLAGS = 1            -- normal einsteigen, nach Unterbrechung weitermachen

local function distanceToVehicle(vehicle)
    return #(GetEntityCoords(vehicle) - GetEntityCoords(PlayerPedId()))
end

-- Stand eines Fahrzeugs von aussen oder nil: { plate, locked, distance (zur Mitte), freeSeats = { seat, ... } }
function Platform.GetVehicleOutsideState(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then
        return nil
    end
    local free = {}
    for index = DRIVER_SEAT, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if IsVehicleSeatFree(vehicle, index) then
            free[#free + 1] = index
        end
    end
    local plate = GetVehicleNumberPlateText(vehicle) or ''
    return {
        plate = plate:match('^%s*(.-)%s*$'),
        locked = GetVehicleDoorLockStatus(vehicle) >= LOCK_LOCKED_FROM,
        distance = distanceToVehicle(vehicle),
        freeSeats = free,
    }
end

-- Kurz die Kontrolle ueber ein Fahrzeug holen, damit Aenderungen fuer alle sichtbar sind. Wartet, nur im Thread.
local function requestControl(entity)
    local waited = 0
    while not NetworkHasControlOfEntity(entity) do
        if waited >= CONTROL_TIMEOUT_MS or not DoesEntityExist(entity) then
            return false
        end
        NetworkRequestControlOfEntity(entity)
        Wait(CONTROL_STEP_MS)
        waited = waited + CONTROL_STEP_MS
    end
    return true
end

-- Tuer von aussen oeffnen oder schliessen. Nur offen, wenn nicht abgeschlossen und nah genug (Abstand zur Mitte).
-- Gibt true oder false und 'no_door' | 'locked' | 'too_far' | 'no_control'. Wartet, nur im Thread.
function Platform.SetVehicleDoorFromOutside(vehicle, index, open, maxDistance)
    local state = Platform.GetVehicleOutsideState(vehicle)
    if not state or not Platform.HasVehicleDoor(vehicle, index) then
        return false, 'no_door'
    end
    if state.locked then
        return false, 'locked'
    end
    if state.distance > maxDistance then
        return false, 'too_far'
    end
    if not requestControl(vehicle) then
        return false, 'no_control'
    end
    if open then
        SetVehicleDoorOpen(vehicle, index, false, false)
    else
        SetVehicleDoorShut(vehicle, index, false)
    end
    return true
end

-- Zu Fuss in einen bestimmten Sitz einsteigen. Die Figur laeuft selbst zur passenden Tuer.
-- Gibt true oder false und 'not_found' | 'locked' | 'too_far' | 'seat_taken'.
function Platform.EnterVehicleSeat(vehicle, seat, maxDistance)
    seat = tonumber(seat)
    local state = Platform.GetVehicleOutsideState(vehicle)
    if not state or not seat then
        return false, 'not_found'
    end
    if state.locked then
        return false, 'locked'
    end
    if state.distance > maxDistance then
        return false, 'too_far'
    end
    if not IsVehicleSeatFree(vehicle, seat) then
        return false, 'seat_taken'
    end
    TaskEnterVehicle(PlayerPedId(), vehicle, ENTER_TIMEOUT_MS, seat, ENTER_SPEED, ENTER_FLAGS, 0)
    return true
end

------------------------------------------------------------------------
-- Karte, Bildschirm und Koerper (seit Core 1.10.0, fuer Organisationen und Krankheiten)
------------------------------------------------------------------------

local BLIP_DEFAULT_SCALE = 0.8
local FADE_WAIT_STEP_MS = 10
local FADE_WAIT_MAX_MS = 3000
local WALK_LOAD_TIMEOUT_MS = 2000
local WALK_BLEND = 0.25
local RAIN_FROM = 0.2           -- ab diesem Regen gilt man draussen als nass

-- Blip auf der Karte. options: { coords = { x, y, z }, sprite, color, scale, label, shortRange }. Gibt den Blip zurueck.
function Platform.AddBlip(options)
    local c = options.coords
    local blip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, (c.z or 0) + 0.0)
    SetBlipSprite(blip, options.sprite)
    SetBlipColour(blip, options.color or 0)
    SetBlipScale(blip, (options.scale or BLIP_DEFAULT_SCALE) + 0.0)
    SetBlipAsShortRange(blip, options.shortRange ~= false)
    if options.label then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(options.label)
        EndTextCommandSetBlipName(blip)
    end
    return blip
end

function Platform.RemoveBlip(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
end

-- Markierung am Boden an einer festen Stelle, jeden Frame aufrufen.
-- style: { type, size, height, color = { r, g, b }, alpha, zOffset, rotate }
function Platform.DrawMarkerAt(coords, style)
    local color = style.color
    DrawMarker(style.type, coords.x + 0.0, coords.y + 0.0, coords.z + (style.zOffset or 0.0),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        style.size, style.size, style.height or style.size,
        color.r, color.g, color.b, style.alpha,
        false, false, 2, style.rotate == true, nil, nil, false)
end

-- Bildschirm kurz schwarz (Ohnmacht, Blackout) und wieder auf. Bleibt nie dauerhaft schwarz. Wartet, nur im Thread.
function Platform.Blackout(fadeMs, holdMs)
    if IsScreenFadedOut() or IsScreenFadingOut() then
        return false
    end
    DoScreenFadeOut(fadeMs)
    local waited = 0
    while not IsScreenFadedOut() and waited < FADE_WAIT_MAX_MS do
        Wait(FADE_WAIT_STEP_MS)
        waited = waited + FADE_WAIT_STEP_MS
    end
    Wait(holdMs)
    DoScreenFadeIn(fadeMs)
    return true
end

-- Kamera wackeln (Schwindel, Kopfschmerzen). name kommt aus den Daten, intensity 0 bis 1. Ohne name: aufhoeren.
function Platform.ShakeCamera(name, intensity)
    if not name then
        StopGameplayCamShaking(true)
        return
    end
    ShakeGameplayCam(name, (intensity or 0.5) + 0.0)
end

-- Kurz umkippen (Ohnmacht, Schwindel). Nicht im Fahrzeug und nicht bewusstlos.
function Platform.RagdollOwnPed(durationMs)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
        return false
    end
    SetPedToRagdoll(ped, durationMs, durationMs, 0, false, false, false)
    return true
end

-- Gangart (z. B. muede, wackelig). Ohne clipset: normale Gangart.
function Platform.SetOwnWalkStyle(clipset)
    local ped = PlayerPedId()
    if not clipset then
        ResetPedMovementClipset(ped, WALK_BLEND)
        return true
    end
    RequestAnimSet(clipset)
    local timeout = GetGameTimer() + WALK_LOAD_TIMEOUT_MS
    while not HasAnimSetLoaded(clipset) do
        if GetGameTimer() > timeout then
            return false
        end
        Wait(0)
    end
    SetPedMovementClipset(ped, clipset, WALK_BLEND)
    return true
end

-- Minimap aus und wieder an (z. B. Orientierungslosigkeit)
function Platform.SetMinimapHidden(hidden)
    DisplayRadar(not hidden)
end

-- Was die eigene Figur gerade erlebt, fuer Ausloeser von Krankheiten. Nur ein Hinweis, der Server entscheidet.
-- { wet, raining, sprinting, shooting, aiming, inVehicle, indoors }
function Platform.GetOwnExposure()
    local ped = PlayerPedId()
    local inVehicle = IsPedInAnyVehicle(ped, false)
    local indoors = GetInteriorFromEntity(ped) ~= 0
    local raining = GetRainLevel() >= RAIN_FROM
    return {
        wet = IsEntityInWater(ped) or (raining and not inVehicle and not indoors),
        raining = raining,
        sprinting = IsPedSprinting(ped),
        shooting = IsPedShooting(ped),
        aiming = IsPlayerFreeAiming(PlayerId()),
        inVehicle = inVehicle,
        indoors = indoors,
    }
end

------------------------------------------------------------------------
-- Karte und Ton fuer Einsaetze (seit Core 1.12.0, fuer core_dispatch)
------------------------------------------------------------------------

-- Toene der UI als eigene Namen. GTA-5-Sounds stehen nur hier.
local UI_SOUNDS = {
    alert  = { 'Event_Message_Purple', 'GTAO_FM_Events_Soundset' },   -- neuer Einsatz
    urgent = { 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET' },             -- Lebensgefahr, Einheit in Not
    click  = { 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    done   = { 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET' },
}

-- Kurzer Ton: 'alert', 'urgent', 'click', 'done'. Unbekannte Namen werden ignoriert.
function Platform.PlayUiSound(name)
    local sound = UI_SOUNDS[name]
    if sound then
        PlaySoundFrontend(-1, sound[1], sound[2], true)
    end
end

-- Wegpunkt auf der Karte setzen (GPS-Route im Spiel) und wieder entfernen
function Platform.SetWaypoint(coords)
    SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
end

function Platform.ClearWaypoint()
    SetWaypointOff()
end

-- Route zu einem Blip an oder aus, auf Wunsch blinkend (z. B. zugewiesener Einsatz)
function Platform.SetBlipRoute(blip, enabled, flashing)
    if blip and DoesBlipExist(blip) then
        SetBlipRoute(blip, enabled == true)
        SetBlipFlashes(blip, flashing == true)
    end
end

-- Ortsname an einer Stelle: "Straße / Kreuzung, Gegend". Nur Anzeige.
function Platform.GetLocationName(coords)
    local x, y, z = coords.x + 0.0, coords.y + 0.0, (coords.z or 0) + 0.0
    local streetHash, crossingHash = GetStreetNameAtCoord(x, y, z)
    local street = streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or nil
    local crossing = crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil
    local zone = GetLabelText(GetNameOfZone(x, y, z))
    if zone == 'NULL' then
        zone = nil
    end
    local parts = {}
    if street and street ~= '' then
        parts[1] = (crossing and crossing ~= '') and (street .. ' / ' .. crossing) or street
    end
    if zone and zone ~= '' then
        parts[#parts + 1] = zone
    end
    return table.concat(parts, ', ')
end
