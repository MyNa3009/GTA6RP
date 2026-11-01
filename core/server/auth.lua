-- Login und Registrierung ueber den Login-Screen.
-- Der Server entscheidet alles, die UI zeigt nur an.

local attempts = {} -- [source] = { count = number, lockedUntil = number }

local function getLock(source)
    local entry = attempts[source]
    if entry and entry.lockedUntil and entry.lockedUntil > os.time() then
        return entry.lockedUntil - os.time()
    end
    return nil
end

local function registerFailure(source, accountId)
    local entry = attempts[source] or { count = 0 }
    entry.count = entry.count + 1

    if entry.count >= Config.Login.MaxAttempts then
        entry.count = 0
        entry.lockedUntil = os.time() + Config.Login.LockSeconds
        Core.Log({
            account_id = accountId,
            category = 'security',
            action = 'login_locked',
            data = { name = Platform.GetPlayerName(source), seconds = Config.Login.LockSeconds },
        })
    end

    attempts[source] = entry
end

local function lockedResponse(seconds)
    return { ok = false, error = 'too_many_attempts', data = { retryIn = seconds } }
end

local function finish(source, accountId)
    attempts[source] = nil
    Core.SetLoggedIn(source, accountId)
    Platform.Print('ok', ('%s eingeloggt als Account %d'):format(Platform.GetPlayerName(source), accountId))
    return { ok = true, data = { accountId = accountId } }
end

------------------------------------------------------------------------

-- Daten fuer den Login-Screen
-- Die volle E-Mail geht nur an das Geraet, dessen Identifier zu diesem Account gehoeren
local function buildStatus(player)
    local emailHint, email = nil, nil
    if not player.loggedIn and player.knownAccountId then
        if Config.Accounts.RememberEmail then
            email = Accounts.GetEmail(player.knownAccountId)
        else
            emailHint = Accounts.GetEmailHint(player.knownAccountId)
        end
    end
    return {
        loggedIn = player.loggedIn,
        hasCharacter = player.characterId ~= nil,
        email = email,
        emailHint = emailHint,
        players = {
            online = Platform.GetPlayerCount(),
            max = Platform.GetMaxPlayers(),
        },
    }
end

Core.RegisterCallback('auth_status', function(source)
    return { ok = true, data = buildStatus(Core.EnsurePlayer(source)) }
end, { public = true })

-- Ausloggen aus der Charakterauswahl, zurueck zum Login
Core.RegisterCallback('auth_logout', function(source)
    if not Core.Logout(source, 'Ausloggen in der Charakterauswahl') then
        return { ok = false, error = 'not_logged_in' }
    end
    return { ok = true, data = buildStatus(Core.Players[source]) }
end)

Core.RegisterCallback('auth_login', function(source, data)
    local player = Core.EnsurePlayer(source)
    if player.loggedIn then
        return { ok = false, error = 'already_logged_in' }
    end

    local lockedFor = getLock(source)
    if lockedFor then
        return lockedResponse(lockedFor)
    end

    local accountId, err, ban = Accounts.Login(source, data.email, data.password)
    if err == 'banned' then
        return { ok = false, error = 'banned', data = Bans.ToClient(ban) }
    end
    if not accountId then
        registerFailure(source, player.knownAccountId)
        lockedFor = getLock(source)
        if lockedFor then
            return lockedResponse(lockedFor)
        end
        return { ok = false, error = err }
    end

    return finish(source, accountId)
end, { public = true })

Core.RegisterCallback('auth_register', function(source, data)
    local player = Core.EnsurePlayer(source)
    if player.loggedIn then
        return { ok = false, error = 'already_logged_in' }
    end

    local lockedFor = getLock(source)
    if lockedFor then
        return lockedResponse(lockedFor)
    end

    local accountId, err = Accounts.Register(source, data.email, data.password)
    if not accountId then
        return { ok = false, error = err }
    end

    return finish(source, accountId)
end, { public = true })

Core.RegisterCallback('auth_disconnect', function(source)
    Core.Log({
        account_id = Core.EnsurePlayer(source).knownAccountId,
        category = 'connection',
        action = 'left_at_login',
    })
    Platform.DropPlayer(source, 'Du hast die Verbindung beim Login getrennt.')
    return { ok = true }
end, { public = true })

Identity.OnDropped(function(source)
    attempts[source] = nil
end)

------------------------------------------------------------------------
-- /relog: abmelden und zurueck zum Login-Screen
------------------------------------------------------------------------

local RELOG_EVENT = 'core:auth:relog'

Platform.RegisterCommand('relog', function(source)
    if source == 0 then
        Platform.Print('warn', 'Dieser Befehl geht nur ingame.')
        return
    end

    if not Core.Logout(source, 'Befehl /relog') then
        Platform.Notify(source, 'Du bist nicht eingeloggt.', 'error')
        return
    end

    Network.SendToClient(source, RELOG_EVENT, buildStatus(Core.Players[source]))
    Platform.Print('info', ('%s hat sich ueber /relog abgemeldet'):format(Platform.GetPlayerName(source)))
end)
