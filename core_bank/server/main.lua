-- Grundlage von core_bank auf dem Server: wer spielt, Hilfen fuer Texte und Betraege, Log, Meldungen, Start.
-- Das Geld liegt in der Core. core_bank bucht nur ueber deren Exports und fuehrt Kontonummer, Kontoauszug und Schulden.
-- Der Server entscheidet alles: Betraege, Grenzen, Abstand zur Filiale oder zum Automaten.

-- Braucht Core 1.16.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.16.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Emit', 'Export', 'GetCallingResource', 'GetPlayerPosition', 'GetResourceVersion', 'IsResourceStarted',
    'Notify', 'OnEvent', 'Print', 'RegisterCommand', 'SetInterval', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_bank: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    BankDisabled = true
    return
end

Bank = { Ready = false }

local CORE = 'core'
local FACTIONS = 'core_factions'
local CHANGED_EVENT = 'core_bank:changed'

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

function Bank.Core(name, ...)
    return Platform.CallExport(CORE, name, ...)
end

function Bank.HasFactions()
    return Platform.IsResourceStarted(FACTIONS)
end

function Bank.Factions(name, ...)
    return Platform.CallExport(FACTIONS, name, ...)
end

-- Nutzertext: Steuerzeichen raus, Leerraum aussen weg, auf maxLength Zeichen kuerzen. Leer: nil
function Bank.Text(value, maxLength)
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

-- Ganzer Betrag von 1 bis max, sonst nil
function Bank.Amount(value, max)
    value = tonumber(value)
    if not value or value ~= value or value ~= math.floor(value) or value < 1 or value > max then
        return nil
    end
    return math.floor(value)
end

-- Warum ist eine Buchung der Core fehlgeschlagen? Ueber Exports kommt im Spiel oft nur der erste Rueckgabewert an,
-- der Fehlercode fehlt dann. In dem Fall selbst nachsehen, ob einfach zu wenig Geld da war.
-- account: 'bank' (ueber die permanente ID) oder 'cash' (ueber source, Bargeld liegt evtl. im Inventar).
function Bank.Why(err, account, who, amount)
    if type(err) == 'string' then
        return err
    end
    local have
    if account == 'cash' then
        have = tonumber(Bank.Core('GetMoney', who, 'cash'))
    else
        have = tonumber(Bank.Core('GetBankByCharacter', who))
    end
    if have and have < amount then
        return account == 'cash' and 'not_enough_cash' or 'not_enough_money'
    end
    return 'server_error'
end

function Bank.Money(amount)
    local text = tostring(math.floor(amount))
    local formatted = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (formatted:gsub('^%.', '')) .. ' $'
end

-- Login eines Charakters, damit der Eintrag in seiner Akte im Admin-Menue steht (die Akte sucht ueber den Login)
local accountOf = {}   -- [permanente ID] = Login-Nummer

local function accountIdOf(characterId)
    if accountOf[characterId] == nil then
        accountOf[characterId] = tonumber(Bank.Core('GetCharacterAccount', characterId)) or false
    end
    return accountOf[characterId] or nil
end

function Bank.Log(entry)
    entry.category = 'bank'
    entry.resource = entry.resource or 'core_bank'
    if entry.character_id and not entry.account_id then
        entry.account_id = accountIdOf(entry.character_id)
    end
    Bank.Core('Log', entry)
end

------------------------------------------------------------------------
-- Wer spielt gerade
------------------------------------------------------------------------

local active = {}     -- [source] = permanente ID
local bySource = {}   -- [permanente ID] = source

function Bank.CharacterOf(source)
    return active[tonumber(source)]
end

function Bank.SourceOf(characterId)
    return bySource[tonumber(characterId)]
end

-- Name eines Charakters, auch offline. nil, wenn es ihn nicht gibt.
function Bank.NameOf(characterId)
    local record = Bank.Core('GetCharacterRecord', characterId)
    if type(record) ~= 'table' then
        return nil
    end
    return ('%s %s'):format(record.firstname, record.lastname)
end

-- Meldung an den Charakter, wenn er gerade spielt
function Bank.Notify(characterId, text, kind)
    local source = bySource[characterId]
    if source then
        Platform.Notify(source, text, kind or 'info')
    end
end

-- Stand hat sich geaendert: offene UI des Charakters laedt neu, andere Scripts (Handy) hoeren auf das Server-Ereignis.
-- what: 'account' (Kontostand, Buchungen) oder 'debts'
function Bank.Changed(characterId, what)
    local source = bySource[characterId]
    if source then
        Network.SendToClient(source, CHANGED_EVENT, { what = what })
    end
    Platform.Emit(CHANGED_EVENT, characterId, what)
end

-- OnLoaded setzt debts.lua (Schulden pruefen), OnUnloaded setzt sessions.lua (offene Sitzung beenden)
function Bank.OnLoaded() end
function Bank.OnUnloaded() end

local function onLoaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if not source or not characterId then
        return
    end
    while not Bank.Ready do
        Platform.Wait(100)
    end
    active[source], bySource[characterId] = characterId, source
    -- Jeder Charakter hat ein Konto: Kontonummer beim ersten Einloggen anlegen
    Bank.NumberOf(characterId)
    Bank.OnLoaded(source, characterId)
end

local function onUnloaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if source then
        characterId = characterId or active[source]
        Bank.OnUnloaded(source, characterId)
        active[source] = nil
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

-- "1.16.0" >= "1.9.3"? Vergleicht Zahl fuer Zahl, nicht als Text.
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

-- Wird von debts.lua gesetzt: Rechte bei core_factions anmelden
function Bank.RegisterPermissions() end

Platform.OnEvent('onResourceStart', function(resource)
    if resource == FACTIONS then
        Platform.Async(function()
            Platform.Wait(500)
            Bank.RegisterPermissions()
        end)
    end
end)

DB.Ready(function()
    for _, statement in ipairs(BankSchema) do
        if DB.Query(statement) == nil then
            Platform.Print('error', 'core_bank: Tabellen konnten nicht angelegt werden. Bitte database/bank.sql ausfuehren.')
            return
        end
    end
    -- Die neuen Exports der Core (Bank ueber die permanente ID) gibt es erst ab REQUIRED_CORE
    local coreVersion = Platform.GetResourceVersion(CORE)
    if not versionAtLeast(coreVersion, REQUIRED_CORE) then
        Platform.Print('error', ('core_bank: Core %s ist zu alt, gebraucht wird mindestens %s. Ordner core ersetzen und Server neu starten.'):format(tostring(coreVersion), REQUIRED_CORE))
        return
    end
    Bank.RegisterPermissions()
    Bank.Ready = true
    for source, characterId in pairs(Bank.Core('GetActiveCharacters') or {}) do
        onLoaded(source, characterId)
    end
end)
