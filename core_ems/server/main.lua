-- Grundlage von core_ems auf dem Server: wer spielt, Rechte ueber core_factions, Krankenakte, Bezahlen, Zustimmung.
-- Der Server entscheidet alles. Der Client spielt nur Symptome und Animationen ab.

-- Braucht Core 1.10.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.10.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Emit', 'Export', 'GetPlayerPosition', 'GetPlayerDimension', 'GetTime',
    'IsResourceStarted', 'Notify', 'OnEvent', 'OnResourceStop', 'Print', 'RegisterCommand', 'SetInterval', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_ems: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    EmsDisabled = true
    return
end

Ems = { Ready = false }

local CORE = 'core'
local FACTIONS = 'core_factions'
local INVENTORY = 'core_inventory'
local CFG = Config.Ems
local POLL_MS = 50
local RECORD_TEXT_MAX = 255

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

function Ems.Core(name, ...)
    return Platform.CallExport(CORE, name, ...)
end

function Ems.Factions(name, ...)
    return Platform.CallExport(FACTIONS, name, ...)
end

function Ems.Inventory(name, ...)
    return Platform.CallExport(INVENTORY, name, ...)
end

function Ems.Log(entry)
    entry.category = entry.category or 'ems'
    Ems.Core('Log', entry)
end

-- Eintrag im Protokoll des Rettungsdiensts (Organisationsmenue, Tab Protokolle). area: 'einsatz' oder 'datenbank'.
-- entry: { action, text, actorSource, actorName, target (permanente ID), admin }
function Ems.Protocol(area, entry)
    if Platform.IsResourceStarted(FACTIONS) then
        entry.area = area
        Ems.Factions('AddProtocol', CFG.Faction, entry)
    end
end

function Ems.Text(value, maxLength)
    if type(value) ~= 'string' then
        return nil
    end
    value = value:gsub('[%c]', ' '):match('^%s*(.-)%s*$')
    if value == '' or not utf8.len(value) then
        return nil
    end
    if utf8.len(value) > maxLength then
        value = value:sub(1, utf8.offset(value, maxLength + 1) - 1)
    end
    return value
end

function Ems.Money(amount)
    local text = tostring(math.floor(amount))
    local formatted = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (formatted:gsub('^%.', '')) .. ' $'
end

------------------------------------------------------------------------
-- Wer spielt gerade
------------------------------------------------------------------------

local active = {}     -- [source] = permanente ID
local bySource = {}   -- [permanente ID] = source

function Ems.CharacterOf(source)
    return active[tonumber(source)]
end

function Ems.SourceOf(characterId)
    return bySource[tonumber(characterId)]
end

function Ems.Active()
    return active
end

function Ems.NameOf(source)
    local info = Ems.Core('GetCharacterInfo', source)
    if type(info) ~= 'table' then
        return nil
    end
    return ('%s %s'):format(info.firstname, info.lastname)
end

-- Werden von diseases.lua ueberschrieben
function Ems.OnLoaded() end
function Ems.OnUnloaded() end

local function onLoaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if not source or not characterId then
        return
    end
    while not Ems.Ready do
        Platform.Wait(100)
    end
    active[source], bySource[characterId] = characterId, source
    Ems.OnLoaded(source, characterId)
end

local function onUnloaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if source then
        Ems.OnUnloaded(source, characterId or active[source])
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
-- Rechte ueber core_factions
------------------------------------------------------------------------

local function registerPermissions()
    if Platform.IsResourceStarted(FACTIONS) then
        Ems.Factions('RegisterPermissions', CFG.Faction, CFG.Permissions)
    end
end

Platform.OnEvent('onResourceStart', function(resource)
    if resource == FACTIONS then
        Platform.Async(function()
            Platform.Wait(500)
            registerPermissions()
        end)
    end
end)

-- Mediziner im Dienst mit diesem Recht? Gibt true oder false und einen Fehlercode zurueck.
function Ems.CanMedic(source, key)
    if not Platform.IsResourceStarted(FACTIONS) then
        return false, 'no_permission'
    end
    local member = Ems.Factions('GetMember', source)
    if type(member) ~= 'table' or member.faction ~= CFG.Faction then
        return false, 'not_medic'
    end
    if not member.onDuty then
        return false, 'not_on_duty'
    end
    if Ems.Factions('HasPermission', source, key, true) ~= true then
        return false, 'no_permission'
    end
    return true
end

------------------------------------------------------------------------
-- Abstand und Ziel
------------------------------------------------------------------------

function Ems.Near(source, target, maxDistance)
    local a, b = Platform.GetPlayerPosition(source), Platform.GetPlayerPosition(target)
    if not a or not b or Platform.GetPlayerDimension(source) ~= Platform.GetPlayerDimension(target) then
        return false
    end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz <= maxDistance * maxDistance
end

-- Ziel aus der Anfrage: online, nicht man selbst, in Reichweite
function Ems.Target(source, data)
    local target = type(data) == 'table' and tonumber(data.serverId)
    if not target or target == source or not active[target] then
        return nil, 'target_offline'
    end
    if not Ems.Near(source, target, CFG.TargetDistance) then
        return nil, 'too_far'
    end
    return target
end

------------------------------------------------------------------------
-- Krankenakte
------------------------------------------------------------------------

function Ems.Record(characterId, kind, text, actorName)
    DB.Insert('INSERT INTO ems_records (character_id, kind, text, actor_name) VALUES (?, ?, ?, ?)',
        DB.Args(characterId, kind, Ems.Text(text, RECORD_TEXT_MAX) or kind, actorName))
end

------------------------------------------------------------------------
-- Versicherung
------------------------------------------------------------------------

-- Gibt das Ablaufdatum (Text) zurueck, wenn die Versicherung noch gilt, sonst nil
function Ems.InsuredUntil(characterId)
    return DB.Scalar("SELECT DATE_FORMAT(valid_until, '%Y-%m-%d') FROM ems_insurance WHERE character_id = ? AND valid_until > NOW()", { characterId })
end

------------------------------------------------------------------------
-- Zustimmung und Bezahlen
------------------------------------------------------------------------

local CONSENT_REASONS = {
    declined = 'consent_declined', timeout = 'consent_timeout', target_busy = 'target_busy',
    target_offline = 'target_offline', no_character = 'no_character', cancelled = 'consent_declined',
}

-- Fragt target (Ja mit Y, Nein mit N). Gibt true oder false und einen Fehlercode zurueck.
function Ems.Consent(source, target, title, text)
    local id, err = Ems.Core('StartConsent', source, target, { title = title, text = text })
    if not id then
        return false, CONSENT_REASONS[err] or 'consent_declined'
    end
    Platform.Notify(source, Config.Consent and Config.Consent.WaitingText or 'Warte, bis die Person zustimmt…', 'info')
    while true do
        local accepted, reason = Ems.Core('GetConsentResult', id)
        if accepted == true then
            return true
        end
        if accepted == false then
            return false, CONSENT_REASONS[reason] or 'consent_declined'
        end
        Platform.Wait(POLL_MS)
    end
end

-- target zahlt (bar, sonst vom Konto). Gibt das Konto zurueck oder nil und not_enough_money.
function Ems.Pay(target, amount, reason)
    if amount <= 0 then
        return 'none'
    end
    for _, account in ipairs(CFG.PayFrom) do
        if Ems.Core('RemoveMoney', target, account, amount, reason, { data = { faction = CFG.Faction } }) then
            return account
        end
    end
    return nil, 'not_enough_money'
end

-- Zurueckzahlen, wenn danach etwas schiefgeht
function Ems.Refund(target, account, amount, reason)
    if account and account ~= 'none' and amount > 0 then
        Ems.Core('AddMoney', target, account, amount, reason .. ' (zurück)')
    end
end

-- Alles Geld geht in die Kasse des Rettungsdiensts
-- Animation beim Spieler waehrend eines Minigames am Patienten. kind = 'revive' | 'heal', ohne kind: aufhoeren.
function Ems.Anim(source, kind, target)
    Network.SendToClient(source, 'core_ems:anim', { kind = kind, target = target })
end

function Ems.ToCash(amount, reason, actorSource, data)
    if amount > 0 and Platform.IsResourceStarted(FACTIONS) then
        Ems.Factions('Deposit', CFG.Faction, amount, { actorSource = actorSource, reason = reason, data = data })
    end
end

------------------------------------------------------------------------
-- Sperre pro Ziel (nicht zwei Mediziner gleichzeitig an derselben Person)
------------------------------------------------------------------------

local busy = {}

function Ems.Lock(target)
    if busy[target] then
        return false
    end
    busy[target] = true
    return true
end

function Ems.Unlock(target)
    busy[target] = nil
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------

DB.Ready(function()
    for _, statement in ipairs(EmsSchema) do
        if DB.Query(statement) == nil then
            Platform.Print('error', 'core_ems: Tabellen konnten nicht angelegt werden. Bitte database/ems.sql ausfuehren.')
            return
        end
    end
    registerPermissions()
    Ems.Ready = true
    for source, characterId in pairs(Ems.Core('GetActiveCharacters') or {}) do
        onLoaded(source, characterId)
    end
end)
