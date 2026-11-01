-- Identity-Bridge fuer FiveM.
-- Liefert Identifier als { license = '...', discord = '...' } und meldet Join und Leave.

Identity = {}

-- IP-Adressen sind keine stabilen Identifier und werden hier bewusst ausgelassen
local IGNORED_TYPES = {
    ip = true,
}

function Identity.GetAll(source)
    local result = {}
    local count = GetNumPlayerIdentifiers(source)

    for index = 0, count - 1 do
        local identifier = GetPlayerIdentifier(source, index)
        if identifier then
            local idType, value = identifier:match('^([%w_]+):(.+)$')
            if idType and not IGNORED_TYPES[idType] then
                result[idType] = value
            end
        end
    end

    return result
end

-- Hardware-Tokens des PCs (FiveM liefert mehrere pro Geraet). Gleicher PC = mindestens ein gleicher Token.
function Identity.GetTokens(source)
    local tokens = {}
    local count = GetNumPlayerTokens(source) or 0
    for index = 0, count - 1 do
        local token = GetPlayerToken(source, index)
        if token and token ~= '' then
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

-- IP-Adresse ohne Port oder nil
function Identity.GetIp(source)
    local endpoint = GetPlayerEndpoint(source)
    if type(endpoint) ~= 'string' or endpoint == '' then
        return nil
    end
    return endpoint:match('^%[?([^%]]+)%]?:%d+$') or endpoint
end

function Identity.OnJoining(handler)
    AddEventHandler('playerJoining', function()
        local src = tonumber(source) or source
        CreateThread(function()
            handler(src)
        end)
    end)
end

-- Vor dem Betreten des Servers. handler(source, identifiers, tokens) gibt nil zurueck (darf rein)
-- oder einen Text, mit dem die Verbindung abgelehnt wird.
function Identity.OnConnecting(handler)
    AddEventHandler('playerConnecting', function(_, _, deferrals)
        local src = tonumber(source) or source
        deferrals.defer()
        CreateThread(function()
            Wait(0)
            deferrals.update('Account wird geprüft…')
            local ok, message = pcall(handler, src, Identity.GetAll(src), Identity.GetTokens(src))
            if not ok then
                print(('^1[core] Fehler beim Pruefen der Verbindung: %s^7'):format(tostring(message)))
                deferrals.done()
            elseif type(message) == 'string' then
                deferrals.done(message)
            else
                deferrals.done()
            end
        end)
    end)
end

function Identity.OnDropped(handler)
    AddEventHandler('playerDropped', function(reason)
        local src = tonumber(source) or source
        handler(src, reason)
    end)
end
