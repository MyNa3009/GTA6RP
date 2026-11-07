-- Einstiegspunkt der Core: Spieler laden, Login-Zustand, oeffentliche API, Testbefehle.

Core = Core or {}
Core.Players = {}

local DEBUG = Platform.GetConvar('core_debug', 'false') == 'true'
local LOAD_WAIT_MS = 50

------------------------------------------------------------------------
-- Spieler laden und entladen
------------------------------------------------------------------------

local function loadPlayer(source)
    local player = {
        source = source,
        name = Platform.GetPlayerName(source),
        accountId = nil,      -- erst nach erfolgreichem Login gesetzt
        knownAccountId = nil, -- Account, der zu den Identifiern dieses Geraets passt
        loggedIn = false,
        loading = true,
    }
    Core.Players[source] = player

    player.knownAccountId = Accounts.FindByIdentifiers(Identity.GetAll(source))
    player.loading = false

    Core.Log({
        account_id = player.knownAccountId,
        category = 'connection',
        action = 'join',
        data = { name = player.name },
    })

    if player.knownAccountId then
        Platform.Print('info', ('%s verbunden, bekannter Account %d, wartet auf Login'):format(player.name, player.knownAccountId))
    else
        Platform.Print('info', ('%s verbunden, noch kein Account'):format(player.name))
    end

    return player
end

-- Gibt den Spieler zurueck und laedt ihn bei Bedarf (z. B. nach Neustart der Core)
function Core.EnsurePlayer(source)
    local player = Core.Players[source] or loadPlayer(source)
    while player.loading do
        Platform.Wait(LOAD_WAIT_MS)
    end
    return player
end

Identity.OnJoining(function(source)
    Core.EnsurePlayer(source)
end)

Identity.OnDropped(function(source, reason)
    local player = Core.Players[source]
    if player then
        AdminDuty.Clear(player, 'Verbindung getrennt')
        Characters.Unload(player, 'Verbindung getrennt')
        Core.Log({
            actor_account_id = player.accountId,
            account_id = player.accountId or player.knownAccountId,
            category = 'connection',
            action = 'leave',
            data = { reason = reason, loggedIn = player.loggedIn },
        })
    end
    Core.Players[source] = nil
end)

------------------------------------------------------------------------
-- Oeffentliche API (andere Scripts benutzen nur das)
------------------------------------------------------------------------

function Core.GetPlayer(source)
    return Core.Players[source]
end

-- Eingeloggter Spieler mit dieser permanenten ID oder nil
function Core.GetPlayerByAccount(accountId)
    for _, player in pairs(Core.Players) do
        if player.loggedIn and player.accountId == accountId then
            return player
        end
    end
    return nil
end

-- Spieler, der gerade diesen Charakter (permanente ID) spielt, oder nil
function Core.GetPlayerByCharacter(characterId)
    characterId = tonumber(characterId)
    if not characterId then
        return nil
    end
    for _, player in pairs(Core.Players) do
        if player.characterId == characterId then
            return player
        end
    end
    return nil
end

-- Ziel eines Befehls: permanente ID aus dem Argument, ohne Argument man selbst.
-- Gibt die Server-ID zurueck oder nil und einen Fehlertext.
function Core.ResolveTarget(source, arg)
    if arg == nil or arg == '' then
        if source == 0 then
            return nil, 'Aus der Konsole bitte eine permanente ID angeben.'
        end
        return source
    end
    local player = Core.GetPlayerByCharacter(arg)
    if not player then
        return nil, 'Niemand mit dieser permanenten ID ist gerade im Spiel.'
    end
    return player.source
end

function Core.IsLoggedIn(source)
    local player = Core.Players[source]
    return player ~= nil and player.loggedIn == true
end

-- Der Charakter, mit dem gerade gespielt wird, oder nil
function Core.GetCharacter(source)
    local player = Core.Players[source]
    return player and player.character or nil
end

function Core.SetLoggedIn(source, accountId)
    local player = Core.EnsurePlayer(source)
    player.accountId = accountId
    player.knownAccountId = accountId
    -- Rang kommt erst mit dem Charakter, in der Auswahl gilt der Standardrang
    player.rank = Permissions.DefaultId()
    player.loggedIn = true
end

-- Meldet den Spieler ab, der bekannte Account bleibt fuer den Login-Hinweis erhalten
function Core.Logout(source, reason)
    local player = Core.Players[source]
    if not player or not player.loggedIn then
        return false
    end

    AdminDuty.Clear(player, reason)
    Characters.Unload(player, reason)

    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        category = 'account',
        action = 'logout',
        reason = reason,
    })

    player.accountId = nil
    player.rank = nil
    player.loggedIn = false
    return true
end

-- Jeder Callback verlangt standardmaessig einen eingeloggten Spieler.
-- Nur Login und Registrierung setzen options.public = true.
function Core.RegisterCallback(name, handler, options)
    local public = options and options.public == true

    Network.RegisterCallback(name, function(source, data)
        if not public and not Core.IsLoggedIn(source) then
            Core.Log({
                category = 'security',
                action = 'callback_without_login',
                resource = Platform.GetCallingResource(),
                data = { callback = name, name = Platform.GetPlayerName(source) },
            })
            return { ok = false, error = 'not_logged_in' }
        end
        return handler(source, data)
    end)
end

-- Kurzinfo zum gespielten Charakter fuer andere Resources (keine Tabellen aus dem Inneren der Core)
function Core.CharacterInfo(player)
    local character = player and player.character
    if not character then
        return nil
    end
    return {
        characterId = player.characterId,
        accountId = player.accountId,
        firstname = character.firstname,
        lastname = character.lastname,
        gender = character.gender,
    }
end

------------------------------------------------------------------------
-- Schnittstelle fuer andere Resources (exports.core:...)
------------------------------------------------------------------------

Platform.Export('GetCharacterInfo', function(source)
    return Core.CharacterInfo(Core.GetPlayer(source))
end)
Platform.Export('GetCharacterId', function(source)
    local player = Core.GetPlayer(source)
    return player and player.characterId or nil
end)
Platform.Export('GetAccountId', function(source)
    local player = Core.GetPlayer(source)
    return player and player.accountId or nil
end)
Platform.Export('GetSourceByCharacter', function(characterId)
    local player = Core.GetPlayerByCharacter(characterId)
    return player and player.source or nil
end)
-- Login eines Charakters, auch offline. nil, wenn es ihn nicht gibt oder er geloescht ist.
-- Stammdaten eines Charakters (auch offline), z. B. fuer Ausweis und spaeteres MDT
Platform.Export('GetCharacterRecord', function(characterId)
    local row = DB.Single(
        "SELECT id, firstname, lastname, DATE_FORMAT(date_of_birth, '%Y-%m-%d') AS date_of_birth, gender FROM characters WHERE id = ? AND deleted_at IS NULL",
        { tonumber(characterId) }
    )
    if not row then
        return nil
    end
    return { characterId = row.id, firstname = row.firstname, lastname = row.lastname, dateOfBirth = row.date_of_birth, gender = row.gender }
end)

-- Personen suchen (z. B. Medizinische Datenbank, spaeter MDT): permanente ID genau oder Name ab Anfang.
-- "Max Mus" findet Max Mustermann. Hoechstens limit Treffer (1 bis 50), nur nicht geloeschte Charaktere.
local SEARCH_MAX = 50
local SEARCH_TEXT_MAX = 50
Platform.Export('SearchCharacters', function(text, limit)
    limit = math.max(1, math.min(SEARCH_MAX, math.floor(tonumber(limit) or 20)))
    text = type(text) == 'string' and text:sub(1, SEARCH_TEXT_MAX):match('^%s*(.-)%s*$') or ''
    local select = "SELECT id, firstname, lastname, DATE_FORMAT(date_of_birth, '%Y-%m-%d') AS date_of_birth, gender FROM characters"
    local rows
    local id = tonumber(text)
    if id then
        rows = DB.Query(select .. ' WHERE id = ? AND deleted_at IS NULL', { math.floor(id) })
    elseif text == '' then
        rows = DB.Query(select .. ' WHERE deleted_at IS NULL ORDER BY id DESC LIMIT ?', { limit })
    else
        local escaped = text:gsub('[%%_\\]', '\\%0')
        local first, last = escaped:match('^(%S+)%s+(.+)$')
        if first then
            rows = DB.Query(select .. ' WHERE firstname LIKE ? AND lastname LIKE ? AND deleted_at IS NULL ORDER BY lastname, firstname LIMIT ?',
                { first .. '%', last .. '%', limit })
        else
            rows = DB.Query(select .. ' WHERE id IN (SELECT id FROM (SELECT id FROM characters WHERE firstname LIKE ? UNION SELECT id FROM characters WHERE lastname LIKE ?) AS hits) AND deleted_at IS NULL ORDER BY lastname, firstname LIMIT ?',
                { escaped .. '%', escaped .. '%', limit })
        end
    end
    local list = {}
    for _, row in ipairs(rows or {}) do
        list[#list + 1] = { characterId = row.id, firstname = row.firstname, lastname = row.lastname, dateOfBirth = row.date_of_birth, gender = row.gender }
    end
    return list
end)

Platform.Export('GetCharacterAccount', function(characterId)
    characterId = tonumber(characterId)
    if not characterId then
        return nil
    end
    return DB.Scalar('SELECT account_id FROM characters WHERE id = ? AND deleted_at IS NULL', { math.floor(characterId) })
end)
Platform.Export('IsOnDuty', function(source)
    return Core.IsOnDuty(source)
end)
Platform.Export('AuthorizeCommand', function(source, name, permission, args, requireDuty)
    return Core.AuthorizeCommand(source, name, permission, args, requireDuty)
end)
-- Alle gerade gespielten Charaktere: { [source] = characterId }
Platform.Export('GetActiveCharacters', function()
    local list = {}
    for source, player in pairs(Core.Players) do
        if player.characterId then
            list[source] = player.characterId
        end
    end
    return list
end)
Platform.Export('GetPlayer', Core.GetPlayer)
Platform.Export('IsLoggedIn', Core.IsLoggedIn)
Platform.Export('GetCharacter', Core.GetCharacter)
Platform.Export('Log', Core.Log)

------------------------------------------------------------------------
-- Start: Datenbank pruefen und schon verbundene Spieler laden
------------------------------------------------------------------------

DB.Ready(function()
    local accountCount = DB.Scalar('SELECT COUNT(*) FROM accounts')
    if accountCount == nil then
        Platform.Print('error', 'Datenbank nicht erreichbar oder Tabelle accounts fehlt.')
        return
    end

    Platform.Print('ok', ('Core %s, Datenbank verbunden, %d Accounts vorhanden.'):format(Platform.GetResourceVersion() or '?', accountCount))
    -- Seit 1.10.0: Suche nach Nachnamen (SearchCharacters). Migration 011 macht dasselbe.
    DB.Query('CREATE INDEX IF NOT EXISTS idx_lastname ON characters (lastname)')
    if DEBUG then
        Platform.Print('warn', 'Debug-Modus aktiv: Testbefehle sind freigeschaltet.')
    end

    for _, source in ipairs(Platform.GetPlayers()) do
        Core.EnsurePlayer(source)
    end
end)

------------------------------------------------------------------------
-- Testbefehle, nur mit set core_debug "true"
------------------------------------------------------------------------

if not DEBUG then
    return
end

local function requireLoggedIn(source)
    if source == 0 then
        Platform.Print('warn', 'Dieser Befehl geht nur ingame.')
        return nil
    end
    if not Core.IsLoggedIn(source) then
        Platform.Notify(source, 'Du bist nicht eingeloggt.', 'error')
        return nil
    end
    return Core.Players[source]
end

Platform.RegisterCommand('meineid', function(source)
    local player = requireLoggedIn(source)
    if not player then return end
    if player.characterId then
        Platform.Notify(source, ('Deine permanente ID ist %d (Login %d).'):format(player.characterId, player.accountId), 'info')
    else
        Platform.Notify(source, ('Du spielst gerade keinen Charakter. Dein Login hat die Nummer %d.'):format(player.accountId), 'info')
    end
end)

Platform.RegisterCommand('logtest', function(source)
    local player = requireLoggedIn(source)
    if not player then return end

    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        category = 'test',
        action = 'logtest',
        reason = 'Manueller Test ueber /logtest',
        data = { name = player.name },
    })
    Platform.Notify(source, ('Log-Eintrag erstellt, wird in spaetestens %d Sekunden gespeichert.'):format(Config.Log.FlushIntervalMs // 1000), 'info')
end)
