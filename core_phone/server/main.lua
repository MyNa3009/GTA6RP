-- Grundlage von core_phone auf dem Server: wer spielt, wer ein Handy dabei hat, Hilfen fuer Texte, Log, Start.
-- Der Server entscheidet alles: wer wen erreicht, was gespeichert wird, ob jemand sein Handy dabei hat.
-- Die eSIM (Nummer, Kontakte, Nachrichten, Anrufliste) haengt an der permanenten ID, das Geraet ist nur das Item.

-- Braucht Core 1.20.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.20.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Emit', 'Export', 'GetCallingResource', 'GetPlayerPosition', 'GetResourceVersion',
    'IsResourceStarted', 'Notify', 'OnEvent', 'Print', 'RegisterCommand', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_phone: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    PhoneDisabled = true
    return
end

Phone = { Ready = false }

local CFG = Config.Phone
local CORE = 'core'
local INVENTORY = 'core_inventory'
local PUSH_EVENT = 'core_phone:event'

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

function Phone.Core(name, ...)
    return Platform.CallExport(CORE, name, ...)
end

-- Nutzertext: Steuerzeichen raus, Leerraum aussen weg, auf maxLength Zeichen kuerzen. Leer: nil
function Phone.Text(value, maxLength)
    if type(value) ~= 'string' then
        return nil
    end
    value = value:gsub('[%c]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if value == '' or not utf8.len(value) then
        return nil
    end
    if utf8.len(value) > maxLength then
        value = value:sub(1, utf8.offset(value, maxLength + 1) - 1)
    end
    return value
end

-- Login eines Charakters, damit der Eintrag in seiner Akte im Admin-Menue steht
local accountOf = {}

function Phone.Log(entry)
    entry.category = 'phone'
    entry.resource = entry.resource or 'core_phone'
    local characterId = entry.character_id
    if characterId and not entry.account_id then
        if accountOf[characterId] == nil then
            accountOf[characterId] = tonumber(Phone.Core('GetCharacterAccount', characterId)) or false
        end
        entry.account_id = accountOf[characterId] or nil
    end
    Phone.Core('Log', entry)
end

------------------------------------------------------------------------
-- Wer spielt gerade
------------------------------------------------------------------------

local active = {}     -- [source] = permanente ID
local bySource = {}   -- [permanente ID] = source
local viewing = {}    -- [source] = permanente ID, deren Handy ein Admin gerade ansieht
local busy = {}       -- [source] = true, solange eine Aenderung laeuft

function Phone.CharacterOf(source)
    return active[tonumber(source)]
end

function Phone.SourceOf(characterId)
    return bySource[tonumber(characterId)]
end

-- Name eines Charakters, auch offline. nil, wenn es ihn nicht gibt.
function Phone.NameOf(characterId)
    local record = Phone.Core('GetCharacterRecord', characterId)
    if type(record) ~= 'table' then
        return nil
    end
    return ('%s %s'):format(record.firstname, record.lastname)
end

-- Hat die Person ihr Handy dabei? Ohne Inventar oder ohne Config.Phone.Item zaehlt jeder als ausgestattet.
function Phone.HasDevice(characterId)
    if not CFG.Item or not Platform.IsResourceStarted(INVENTORY) then
        return true
    end
    return (tonumber(Platform.CallExport(INVENTORY, 'GetItemCount', characterId, CFG.Item)) or 0) > 0
end

-- Nachricht an das Handy eines Charakters, wenn er gerade spielt. Gibt true zurueck, wenn er online ist.
function Phone.Push(characterId, payload)
    local source = bySource[characterId]
    if not source then
        return false
    end
    Network.SendToClient(source, PUSH_EVENT, payload)
    return true
end

function Phone.SetViewing(source, characterId)
    viewing[source] = characterId
end

-- Werden von numbers.lua und calls.lua gesetzt
function Phone.OnLoaded() end
function Phone.OnUnloaded() end

-- Callback anmelden. options: { write = true (aendert etwas: nicht in der Admin-Ansicht, nur eins gleichzeitig) }
-- handler(source, data, ctx) mit ctx = { characterId (wessen Handy), admin (Admin-Ansicht) }, gibt { ok, data, error } zurueck.
function Phone.Register(name, options, handler)
    Network.RegisterCallback(name, function(source, data)
        local own = Phone.Ready and active[source]
        if not own then
            return { ok = false, error = 'no_character' }
        end
        local subject = viewing[source]
        if subject and options.write then
            return { ok = false, error = 'read_only' }
        end
        if not subject then
            if not CFG.AllowWhenDead and Phone.Core('IsDead', source) == true then
                return { ok = false, error = 'is_dead' }
            end
            if not Phone.HasDevice(own) then
                return { ok = false, error = 'no_phone' }
            end
        end
        if options.write then
            if busy[source] then
                return { ok = false, error = 'busy' }
            end
            busy[source] = true
        end
        local ok, result = pcall(handler, source, type(data) == 'table' and data or {}, { characterId = subject or own, admin = subject ~= nil })
        if options.write then
            busy[source] = nil
        end
        if not ok then
            Platform.Print('error', ('core_phone: Fehler in %s: %s'):format(name, tostring(result)))
            return { ok = false, error = 'server_error' }
        end
        return result
    end)
end

local function onLoaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if not source or not characterId then
        return
    end
    while not Phone.Ready do
        Platform.Wait(100)
    end
    active[source], bySource[characterId] = characterId, source
    Phone.OnLoaded(source, characterId)
end

local function onUnloaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if source then
        characterId = characterId or active[source]
        Phone.OnUnloaded(source, characterId)
        active[source], viewing[source], busy[source] = nil, nil, nil
    end
    if characterId then
        bySource[characterId] = nil
    end
end

Platform.OnEvent('core:characterLoaded', function(source, info)
    if type(info) == 'table' then
        Platform.Async(function()
            onLoaded(source, info.characterId)
        end)
    end
end)

Platform.OnEvent('core:characterUnloaded', function(source, characterId)
    onUnloaded(source, characterId)
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == CORE then
        for source, characterId in pairs(active) do
            onUnloaded(source, characterId)
        end
    end
end)

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------

-- "1.20.0" >= "1.9.3"? Vergleicht Zahl fuer Zahl, nicht als Text.
local function versionAtLeast(have, need)
    if type(have) ~= 'string' then
        return false
    end
    local a, b = {}, {}
    for part in have:gmatch('%d+') do a[#a + 1] = tonumber(part) end
    for part in need:gmatch('%d+') do b[#b + 1] = tonumber(part) end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then
            return x > y
        end
    end
    return true
end

DB.Ready(function()
    for _, statement in ipairs(PhoneSchema) do
        if DB.Query(statement) == nil then
            Platform.Print('error', 'core_phone: Tabellen konnten nicht angelegt werden. Bitte database/phone.sql ausfuehren.')
            return
        end
    end
    local coreVersion = Platform.GetResourceVersion(CORE)
    if not versionAtLeast(coreVersion, REQUIRED_CORE) then
        Platform.Print('error', ('core_phone: Core %s ist zu alt, gebraucht wird mindestens %s. Ordner core ersetzen und Server neu starten.'):format(tostring(coreVersion), REQUIRED_CORE))
        return
    end
    Phone.Ready = true
    for source, characterId in pairs(Phone.Core('GetActiveCharacters') or {}) do
        onLoaded(source, characterId)
    end
end)
