-- Client der Core: Ablauf Login, Charakterauswahl, Spawn.
-- Die Sperre hier ist nur fuer das Bild. Was wirklich erlaubt ist, entscheidet der Server.

local state = {
    loggedIn = false,
    character = nil,  -- { id, gender } waehrend gespielt wird
    dead = false,
    uiReady = {},     -- [ui] = true, sobald die UI-Datei geladen ist
    pending = {},     -- [ui] = { action, payload }, wenn die UI noch nicht bereit war
}

------------------------------------------------------------------------
-- UI oeffnen, auch wenn sie noch laedt
------------------------------------------------------------------------

-- focus = false fuer Anzeigen ohne Maus und Tastatur (z. B. Bewusstlos-Anzeige)
local function uiOpen(ui, action, payload, focus)
    focus = focus ~= false
    if state.uiReady[ui] then
        Platform.UiSend(action, payload)
        if focus then Platform.UiFocus(true) end
    else
        state.pending[ui] = { action = action, payload = payload, focus = focus }
    end
end

local function uiClose(ui, action)
    state.pending[ui] = nil
    Platform.UiSend(action)
end

Platform.UiOn('ui_ready', function(data)
    local ui = data.ui
    if type(ui) ~= 'string' then
        return { ok = false, error = 'invalid_ui' }
    end

    state.uiReady[ui] = true
    local pending = state.pending[ui]
    if pending then
        state.pending[ui] = nil
        Platform.UiSend(pending.action, pending.payload)
        if pending.focus then Platform.UiFocus(true) end
    end
    return { ok = true }
end)

------------------------------------------------------------------------
-- Login
------------------------------------------------------------------------

local function openLogin(status)
    uiOpen('login', 'login_open', {
        serverName = Config.UI.ServerName,
        colors = Config.UI.Colors,
        mode = (status.email or status.emailHint) and 'login' or 'register',
        email = status.email,
        emailHint = status.emailHint,
        players = status.players,
        passwordMinLength = Config.Accounts.PasswordMinLength,
        passwordMaxLength = Config.Accounts.PasswordMaxLength,
    })
end

------------------------------------------------------------------------
-- Charakterauswahl
------------------------------------------------------------------------

-- notice: Hinweis-Code oben in der Auswahl, z. B. 'character_banned'
local function openCharacters(notice)
    local result = Network.Call('char_list', {})
    local ok = result and result.ok

    uiOpen('char', 'char_open', {
        serverName = Config.UI.ServerName,
        colors = Config.UI.Colors,
        currency = Config.UI.Currency,
        maxCharacters = Config.Characters.MaxPerAccount,
        rules = {
            nameMinLength = Config.Characters.NameMinLength,
            nameMaxLength = Config.Characters.NameMaxLength,
            minAge = Config.Characters.MinAge,
            maxAge = Config.Characters.MaxAge,
        },
        characters = (ok and result.data and result.data.characters) or {},
        error = (not ok) and (result and result.error or 'server_error') or nil,
        notice = notice,
    })
end

local function finishLogin()
    state.loggedIn = true
    Platform.Wait(Config.UI.SuccessDelayMs)
    uiClose('login', 'login_close')
    openCharacters()
end

local function handleAuth(callbackName, data)
    local result = Network.Call(callbackName, {
        email = data.email,
        password = data.password,
    })
    if result and result.ok then
        Platform.Async(finishLogin)
    end
    return result
end

Platform.UiOn('login_submit', function(data)
    return handleAuth('auth_login', data)
end)

Platform.UiOn('login_register', function(data)
    return handleAuth('auth_register', data)
end)

Platform.UiOn('login_disconnect', function()
    return Network.Call('auth_disconnect', {})
end)

------------------------------------------------------------------------
-- Charakter-Aktionen aus der UI
------------------------------------------------------------------------

Platform.UiOn('char_create', function(data)
    return Network.Call('char_create', {
        firstname = data.firstname,
        lastname = data.lastname,
        dateOfBirth = data.dateOfBirth,
        gender = data.gender,
    })
end)

Platform.UiOn('char_reload', function()
    Platform.Async(openCharacters)
    return { ok = true }
end)

Platform.UiOn('char_delete', function(data)
    return Network.Call('char_delete', { id = data.id })
end)

local function spawnCharacter(spawn)
    state.character = { id = spawn.id, gender = spawn.gender }
    uiClose('char', 'char_close')
    Platform.UiFocus(false)
    Platform.SpawnCharacter(Models[spawn.gender] or Models.male, spawn.position)
    Platform.DisableAutoRespawn()
    Platform.SetPlayerLocked(false)
    MoneyHud.Show(spawn.money)
    NeedsHud.Show(spawn.needs)
    JailHud.OnSpawn(spawn.jail)
end

Platform.UiOn('char_play', function(data)
    local result = Network.Call('char_select', { id = data.id })
    if result and result.ok and result.data then
        Platform.Async(function()
            spawnCharacter(result.data)
        end)
    end
    return result
end)

-- Alles beenden, was zum gespielten Charakter gehoert
local function leaveCharacter()
    Noclip.Stop(true)
    AdminVehicles.Reset()
    AdminToolsClient.Reset()
    AdminEsp.Reset()
    SpectateClient.Reset()
    TicketsClient.Close()
    JailHud.Reset()
    Death.Reset()
    MoneyHud.Hide()
    NeedsHud.Hide()
    AdminMenu.Close()
    AdminKeyPrompt.Close()
    state.character = nil
    Platform.SetPlayerLocked(true)
end

local function backToLogin(status)
    leaveCharacter()
    state.loggedIn = false
    uiClose('char', 'char_close')
    openLogin(status or {})
end

Platform.UiOn('char_logout', function()
    local result = Network.Call('auth_logout', {})
    if result and result.ok then
        Platform.Async(function()
            backToLogin(result.data)
        end)
    end
    return result
end)

------------------------------------------------------------------------
-- /relog: Server hat abgemeldet, zurueck zum Login-Screen
------------------------------------------------------------------------

Network.On('core:auth:relog', function(data)
    backToLogin(data)
end)

-- Server hat den Charakter beendet (z. B. Charakter-Ban): zurueck in die Auswahl
Network.On('core:char:return', function(data)
    Platform.Async(function()
        leaveCharacter()
        openCharacters(type(data) == 'table' and data.notice or nil)
    end)
end)

------------------------------------------------------------------------
-- Spawn und Respawn
------------------------------------------------------------------------

-- spawnmanager erzeugt beim Spawnen einen neuen Ped, darum Sperre erneut setzen
Platform.OnSpawned(function()
    if not state.character then
        Platform.SetPlayerLocked(true)
    end
end)

-- Nur vor der Charakterwahl spawnt spawnmanager. Danach regelt client/death.lua den Tod.
Platform.SetRespawnHandler(function()
    if state.character then
        return
    end
    Platform.SpawnCharacter(Models.male, SpawnData.default)
    Platform.SetPlayerLocked(true)
end)

------------------------------------------------------------------------
-- Fuer andere Client-Dateien (death.lua)
------------------------------------------------------------------------

Client = {
    state = state,
    uiOpen = uiOpen,
    uiClose = uiClose,
}

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------

Platform.Async(function()
    Platform.WaitForSession()
    Platform.SetPlayerLocked(true)

    local status = Network.Call('auth_status', {})
    local data = (status and status.ok and status.data) or {}

    if data.loggedIn then
        state.loggedIn = true
        openCharacters()
        return
    end

    openLogin(data)
end)
