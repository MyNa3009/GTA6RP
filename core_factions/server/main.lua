-- Grundlage von core_factions auf dem Server: Organisationen, Rechte, Raenge, wer gerade spielt, Dienst, Kasse.
-- Der Server entscheidet alles. Der Client bekommt nur seinen eigenen Stand (Organisation, Rang, Dienst, Rechte).
-- Andere Scripts (z. B. core_ems) fragen ueber die Exports am Ende dieser Datei.

-- Braucht Core 1.11.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.11.0'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'CallExport', 'Emit', 'Export', 'GetPlayerPosition', 'GetVehicleInfo', 'DeleteNetworkedVehicle',
    'JsonDecode', 'JsonEncode', 'Notify', 'OnEvent', 'OnResourceStop', 'Print', 'RegisterCommand', 'SetInterval', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_factions: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    FactionsDisabled = true
    return
end

Factions = { Ready = false }

local CORE = 'core'
local CFG = Config.Factions
local STATE_EVENT = 'core_factions:state'

------------------------------------------------------------------------
-- Organisationen aus der Config
------------------------------------------------------------------------

Orgs = {}
for id, def in pairs(CFG.Organizations) do
    local ranks = math.floor(tonumber(def.ranks) or 0)
    if ranks < 2 or ranks > 99 then
        Platform.Print('error', ('core_factions: Organisation %s braucht zwischen 2 und 99 Raengen.'):format(id))
    else
        Orgs[id] = {
            id = id,
            label = def.label or id,
            short = def.short or id:upper(),
            ranks = ranks,
            leaderRank = def.leaderRank or ranks,
            viceRank = def.viceRank or (ranks - 1),
            dnPrefix = def.dnPrefix or '',
            platePrefix = def.platePrefix or id:upper():sub(1, 4),
            rankNames = def.rankNames or {},
            vehicles = def.vehicles or {},
            logo = def.logo,
            theme = def.theme or {},
        }
    end
end

function Factions.Org(id)
    return type(id) == 'string' and Orgs[id] or nil
end

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

-- Text pruefen und kuerzen (Nutzereingaben). Gibt nil zurueck, wenn nichts Brauchbares uebrig bleibt.
function Factions.Text(value, maxLength)
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

function Factions.Int(value, min, max)
    value = tonumber(value)
    if not value or value ~= value or value ~= math.floor(value) or value < min or value > max then
        return nil
    end
    return value
end

function Factions.Decode(value, fallback)
    if type(value) ~= 'string' or value == '' then
        return fallback
    end
    local ok, decoded = pcall(Platform.JsonDecode, value)
    if not ok or type(decoded) ~= 'table' then
        return fallback
    end
    return decoded
end

function Factions.Encode(value)
    return Platform.JsonEncode(value)
end

function Factions.Core(name, ...)
    return Platform.CallExport(CORE, name, ...)
end

function Factions.Log(entry)
    entry.category = entry.category or 'faction'
    Factions.Core('Log', entry)
end

------------------------------------------------------------------------
-- Rechte: feste aus der Config plus angemeldete von anderen Scripts
------------------------------------------------------------------------

local permissionList = {}     -- { key, group, label, minRank, faction }
local permissionByKey = {}

local function addPermission(def, faction)
    if type(def) ~= 'table' or type(def.key) ~= 'string' or type(def.label) ~= 'string' then
        return false
    end
    if permissionByKey[def.key] then
        return true
    end
    local entry = { key = def.key, group = def.group or 'Sonstiges', label = def.label, minRank = tonumber(def.minRank), faction = faction }
    permissionByKey[def.key] = entry
    permissionList[#permissionList + 1] = entry
    return true
end

for _, def in ipairs(CFG.Permissions) do
    addPermission(def, nil)
end

-- Andere Scripts melden ihre Rechte an, z. B. core_ems: { { key = 'ems.revive', group = 'Rettungsdienst', label = 'Hochholen', minRank = 1 } }
function Factions.RegisterPermissions(faction, list)
    if not Orgs[faction] or type(list) ~= 'table' then
        return false
    end
    for _, def in ipairs(list) do
        addPermission(def, faction)
    end
    return true
end

-- Alle Rechte, die in dieser Organisation gelten (Reihenfolge wie angemeldet)
function Factions.PermissionsOf(faction)
    local list = {}
    for _, def in ipairs(permissionList) do
        if def.faction == nil or def.faction == faction then
            list[#list + 1] = def
        end
    end
    return list
end

------------------------------------------------------------------------
-- Raenge: Namen und Rechte (Datenbank, sonst Config)
------------------------------------------------------------------------

local rankRows = {}   -- [faction][rank] = { name, permissions = { [key] = bool }, salary, tasks }

function Factions.LoadRanks()
    rankRows = {}
    for id in pairs(Orgs) do
        rankRows[id] = {}
    end
    for _, row in ipairs(DB.Query('SELECT faction, `rank`, name, permissions, salary, tasks FROM faction_ranks') or {}) do
        if rankRows[row.faction] then
            rankRows[row.faction][row.rank] = { name = row.name, permissions = Factions.Decode(row.permissions, {}),
                salary = tonumber(row.salary) or 0, tasks = row.tasks }
        end
    end
end

function Factions.RankName(faction, rank)
    local org = Orgs[faction]
    if not org then
        return tostring(rank)
    end
    local row = rankRows[faction] and rankRows[faction][rank]
    return row and row.name or org.rankNames[rank] or ('Rang %d'):format(rank)
end

-- Hat dieser Rang das Recht? Der Leader hat immer alles.
function Factions.RankHas(faction, rank, key)
    local org = Orgs[faction]
    local def = permissionByKey[key]
    if not org or not def or (def.faction and def.faction ~= faction) then
        return false
    end
    if rank >= org.leaderRank then
        return true
    end
    local row = rankRows[faction] and rankRows[faction][rank]
    if row and row.permissions[key] ~= nil then
        return row.permissions[key] == true
    end
    return rank >= (def.minRank or org.leaderRank)
end

function Factions.RankPermissions(faction, rank)
    local set = {}
    for _, def in ipairs(Factions.PermissionsOf(faction)) do
        if Factions.RankHas(faction, rank, def.key) then
            set[def.key] = true
        end
    end
    return set
end

-- Gehalt pro Auszahlung und Aufgaben (Text fuer Erklaerungen) eines Rangs
function Factions.RankSalary(faction, rank)
    local row = rankRows[faction] and rankRows[faction][rank]
    return row and row.salary or 0
end

function Factions.RankTasks(faction, rank)
    local row = rankRows[faction] and rankRows[faction][rank]
    return row and row.tasks or nil
end

-- extra (optional): { salary, tasks }. Fehlt ein Wert, bleibt der bisherige.
function Factions.SaveRank(faction, rank, name, permissions, extra)
    extra = extra or {}
    local salary = extra.salary or Factions.RankSalary(faction, rank)
    local tasks = extra.tasks
    if tasks == nil then
        tasks = Factions.RankTasks(faction, rank)
    elseif tasks == false then
        tasks = nil
    end
    local ok = DB.Update('INSERT INTO faction_ranks (faction, `rank`, name, permissions, salary, tasks) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), permissions = VALUES(permissions), salary = VALUES(salary), tasks = VALUES(tasks)',
        DB.Args(faction, rank, name, Factions.Encode(permissions), salary, tasks))
    if ok == nil then
        return false
    end
    rankRows[faction][rank] = { name = name, permissions = permissions, salary = salary, tasks = tasks }
    return true
end

------------------------------------------------------------------------
-- Wer spielt gerade, Mitglieder im Speicher
------------------------------------------------------------------------

local active = {}      -- [source] = permanente ID
local bySource = {}    -- [permanente ID] = source
local members = {}     -- [permanente ID] = Mitglied (nur, solange online)
local duty = {}        -- [source] = Organisation, solange im Dienst

local function decodeMember(row)
    if not row then
        return nil
    end
    return {
        characterId = row.character_id,
        faction = row.faction,
        rank = row.rank,
        name = row.name,
        dn = row.dn,
        strikes = row.strikes,
        vacationDays = row.vacation_days,
        departments = Factions.Decode(row.departments, {}),
        exams = Factions.Decode(row.exams, {}),
        hiredAt = row.hired_at,
        hiredBy = row.hired_by,
        lastBonusAt = row.last_bonus_at,
    }
end
Factions.DecodeMember = decodeMember

local MEMBER_COLUMNS = "character_id, faction, `rank`, name, dn, strikes, vacation_days, departments, exams, DATE_FORMAT(hired_at, '%Y-%m-%d') AS hired_at, hired_by, DATE_FORMAT(last_bonus_at, '%Y-%m-%d') AS last_bonus_at"
Factions.MemberColumns = MEMBER_COLUMNS

-- Mitglied laden (online aus dem Speicher, sonst aus der Datenbank). nil, wenn in keiner Organisation.
function Factions.GetMember(characterId)
    characterId = tonumber(characterId)
    if not characterId then
        return nil
    end
    if bySource[characterId] then
        return members[characterId]
    end
    return decodeMember(DB.Single('SELECT ' .. MEMBER_COLUMNS .. ' FROM faction_members WHERE character_id = ?', { characterId }))
end

-- Nach einer Aenderung: Speicher neu fuellen und den Stand an den Spieler schicken
function Factions.Refresh(characterId)
    local source = bySource[characterId]
    if not source then
        return
    end
    members[characterId] = decodeMember(DB.Single('SELECT ' .. MEMBER_COLUMNS .. ' FROM faction_members WHERE character_id = ?', { characterId }))
    local member = members[characterId]
    if duty[source] and (not member or member.faction ~= duty[source]) then
        duty[source] = nil
    end
    Factions.PushState(source)
end

function Factions.CharacterOf(source)
    return active[tonumber(source)]
end

function Factions.SourceOf(characterId)
    return bySource[tonumber(characterId)]
end

function Factions.MemberOf(source)
    local characterId = active[tonumber(source)]
    return characterId and members[characterId] or nil
end

function Factions.NameOf(source)
    local info = Factions.Core('GetCharacterInfo', source)
    if type(info) ~= 'table' then
        return nil
    end
    return ('%s %s'):format(info.firstname, info.lastname)
end

function Factions.AccountOf(source)
    return Factions.Core('GetAccountId', source)
end

-- Eigener Stand fuer den Client (nur Anzeige, der Server prueft jede Aktion selbst)
function Factions.PushState(source)
    local member = Factions.MemberOf(source)
    local state = { member = false }
    if member then
        local org = Orgs[member.faction]
        local permissions = {}
        for key in pairs(Factions.RankPermissions(member.faction, member.rank)) do
            permissions[#permissions + 1] = key
        end
        table.sort(permissions)
        state = {
            member = true,
            faction = member.faction,
            label = org.label,
            short = org.short,
            rank = member.rank,
            rankName = Factions.RankName(member.faction, member.rank),
            isLeader = member.rank >= org.leaderRank,
            isVice = member.rank >= org.viceRank,
            onDuty = duty[source] == member.faction,
            permissions = permissions,
        }
    end
    Network.SendToClient(source, STATE_EVENT, state)
end

-- Rangnamen oder Rechte haben sich geaendert: alle online Mitglieder dieser Organisation neu informieren
function Factions.PushFaction(faction)
    for source, characterId in pairs(active) do
        local member = members[characterId]
        if member and member.faction == faction then
            Factions.PushState(source)
        end
    end
end

local function onCharacterLoaded(source, characterId)
    source, characterId = tonumber(source), tonumber(characterId)
    if not source or not characterId then
        return
    end
    while not Factions.Ready do
        Platform.Wait(100)
    end
    active[source], bySource[characterId] = characterId, source
    members[characterId] = decodeMember(DB.Single('SELECT ' .. MEMBER_COLUMNS .. ' FROM faction_members WHERE character_id = ?', { characterId }))
    -- Name fuer Listen aktuell halten (z. B. nach einer Umbenennung)
    local member = members[characterId]
    local name = Factions.NameOf(source)
    if member and name and name ~= member.name then
        DB.Update('UPDATE faction_members SET name = ? WHERE character_id = ?', { name, characterId })
        member.name = name
    end
    Factions.PushState(source)
end

local function onCharacterUnloaded(source, characterId)
    source = tonumber(source)
    if source then
        if duty[source] then
            Factions.SetDuty(source, false, 'logout')
        end
        active[source] = nil
    end
    characterId = tonumber(characterId)
    if characterId then
        bySource[characterId] = nil
        members[characterId] = nil
    end
    Factions.ForgetPay(source)
    Factions.OnUnloaded(source)
end

-- places.lua haengt sich hier ein (ausgeparkte Fahrzeuge vergessen)
function Factions.OnUnloaded() end

Platform.OnEvent('core:characterLoaded', function(source, info)
    if type(info) == 'table' then
        Platform.Async(function()
            onCharacterLoaded(source, info.characterId)
        end)
    end
end)

Platform.OnEvent('core:characterUnloaded', function(source, characterId)
    onCharacterUnloaded(source, characterId)
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == CORE then
        for source, characterId in pairs(active) do
            onCharacterUnloaded(source, characterId)
        end
    end
end)

------------------------------------------------------------------------
-- Dienst
------------------------------------------------------------------------

function Factions.IsOnDuty(source, faction)
    local current = duty[tonumber(source)]
    return current ~= nil and (faction == nil or current == faction)
end

local DUTY_REASONS = { logout = 'ausgeloggt', removed = 'nicht mehr in der Organisation' }

function Factions.SetDuty(source, on, reason)
    local member = Factions.MemberOf(source)
    if on and not member then
        return false, 'not_member'
    end
    local faction = on and member.faction or duty[source]
    if not faction then
        return false, 'not_on_duty'
    end
    duty[source] = on and member.faction or nil
    Factions.Log({
        account_id = Factions.AccountOf(source),
        character_id = active[source],
        action = on and 'duty_on' or 'duty_off',
        data = { faction = faction, reason = reason },
    })
    local why = DUTY_REASONS[reason]
    Factions.Protocol(faction, { area = 'dienst', action = on and 'duty_on' or 'duty_off', actorSource = source, target = active[source],
        text = (on and 'Dienst angetreten' or 'Dienst beendet') .. (why and (' (' .. why .. ')') or '') })
    Platform.Emit('core_factions:duty', source, faction, on == true)
    if active[source] then
        Factions.PushState(source)
    end
    return true
end

------------------------------------------------------------------------
-- Gehalt: nach je Salary.IntervalMinutes im Dienst, aus der Kasse aufs Konto
------------------------------------------------------------------------

local PAY_TICK_SECONDS = 60
local paySeconds = {}   -- [source] = Sekunden im Dienst seit dem letzten Gehalt (Pause beim Dienstende, weg beim Ausloggen)

function Factions.ForgetPay(source)
    if source then
        paySeconds[source] = nil
    end
end

local function money(amount)
    local text = tostring(math.floor(amount)):reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return text .. ' $'
end
Factions.Money = money

function Factions.PaySalary(source, faction)
    local member = Factions.MemberOf(source)
    local org = Orgs[faction]
    if not member or member.faction ~= faction then
        return false, 'not_member'
    end
    local amount = Factions.RankSalary(faction, member.rank)
    if amount <= 0 then
        return false, 'no_salary'
    end
    if not Factions.Withdraw(faction, amount, { actorSource = source, reason = 'Gehalt', data = { rank = member.rank }, target = member.characterId,
        protocolActor = false, protocolText = ('Gehalt %s als %s'):format(money(amount), Factions.RankName(faction, member.rank)) }) then
        Platform.Notify(source, ('Kein Gehalt: Die Kasse von %s reicht nicht.'):format(org.short), 'warning')
        return false, 'not_enough_money'
    end
    if not Factions.Core('AddMoney', source, 'bank', amount, ('Gehalt %s'):format(org.short), { data = { faction = faction, rank = member.rank } }) then
        Factions.Deposit(faction, amount, { reason = 'Gehalt fehlgeschlagen, zurück' })
        return false, 'server_error'
    end
    Platform.Notify(source, ('Gehalt von %s: %s aufs Konto.'):format(org.short, money(amount)), 'success')
    return true
end

Platform.SetInterval(PAY_TICK_SECONDS * 1000, function()
    local interval = CFG.Salary.IntervalMinutes * 60
    for source, faction in pairs(duty) do
        paySeconds[source] = (paySeconds[source] or 0) + PAY_TICK_SECONDS
        if paySeconds[source] >= interval then
            paySeconds[source] = paySeconds[source] - interval
            Factions.PaySalary(source, faction)
        end
    end
end)

function Factions.OnDutyList(faction)
    local list = {}
    for source, current in pairs(duty) do
        if current == faction then
            list[#list + 1] = source
        end
    end
    return list
end

------------------------------------------------------------------------
-- Rechte eines Spielers
------------------------------------------------------------------------

-- options.duty: nur im Dienst. Gibt true oder false und einen Fehlercode zurueck.
function Factions.Can(source, key, options)
    local member = Factions.MemberOf(source)
    if not member then
        return false, 'not_member'
    end
    if not Factions.RankHas(member.faction, member.rank, key) then
        return false, 'no_permission'
    end
    if options and options.duty and duty[tonumber(source)] ~= member.faction then
        return false, 'not_on_duty'
    end
    return true, member
end

------------------------------------------------------------------------
-- Kasse der Organisation
------------------------------------------------------------------------

local MAX_AMOUNT = 1000000000

local function validAmount(amount)
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount <= 0 or amount > MAX_AMOUNT then
        return nil
    end
    return amount
end

function Factions.GetBalance(faction)
    return tonumber(DB.Scalar('SELECT balance FROM faction_settings WHERE faction = ?', { faction })) or 0
end

-- Kasse im Protokoll. info.protocolText ersetzt den Text, info.target ist die Person, die es betrifft (z. B. Gehalt),
-- info.protocolActor = false: ohne Handelnden (Gehalt zahlt das System).
local function protocolCash(faction, action, verb, amount, balance, info)
    local text = info.protocolText or ('%s %s%s'):format(Factions.Money(amount), verb, info.reason and (' (' .. info.reason .. ')') or '')
    Factions.Protocol(faction, { area = 'kasse', action = action, target = info.target,
        actorSource = info.protocolActor ~= false and info.actorSource or nil,
        text = ('%s, Kasse jetzt %s'):format(text, Factions.Money(balance)) })
end

-- Geld in die Kasse. info: { reason, actorSource, data }. Gibt den neuen Stand oder nil und einen Fehlercode zurueck.
function Factions.Deposit(faction, amount, info)
    amount = validAmount(amount)
    if not Orgs[faction] or not amount then
        return nil, 'invalid_input'
    end
    if DB.Update('UPDATE faction_settings SET balance = balance + ? WHERE faction = ?', { amount, faction }) ~= 1 then
        return nil, 'db_error'
    end
    local balance = Factions.GetBalance(faction)
    info = info or {}
    Factions.Log({
        actor_account_id = info.actorSource and Factions.AccountOf(info.actorSource) or nil,
        character_id = info.actorSource and active[info.actorSource] or nil,
        action = 'cash_in',
        amount = amount,
        balance_before = balance - amount,
        balance_after = balance,
        reason = info.reason,
        data = { faction = faction, resource = Platform.GetCallingResource(), extra = info.data },
    })
    protocolCash(faction, 'cash_in', 'eingezahlt', amount, balance, info)
    return balance
end

-- Geld aus der Kasse, nur wenn genug da ist
function Factions.Withdraw(faction, amount, info)
    amount = validAmount(amount)
    if not Orgs[faction] or not amount then
        return nil, 'invalid_input'
    end
    if DB.Update('UPDATE faction_settings SET balance = balance - ? WHERE faction = ? AND balance >= ?', { amount, faction, amount }) ~= 1 then
        return nil, 'not_enough_money'
    end
    local balance = Factions.GetBalance(faction)
    info = info or {}
    Factions.Log({
        actor_account_id = info.actorSource and Factions.AccountOf(info.actorSource) or nil,
        character_id = info.actorSource and active[info.actorSource] or nil,
        action = 'cash_out',
        amount = amount,
        balance_before = balance + amount,
        balance_after = balance,
        reason = info.reason,
        data = { faction = faction, resource = Platform.GetCallingResource(), extra = info.data },
    })
    protocolCash(faction, 'cash_out', 'ausgezahlt', amount, balance, info)
    return balance
end

------------------------------------------------------------------------
-- Start: Tabellen, Raenge, schon spielende Charaktere
------------------------------------------------------------------------

local function createTables()
    for _, statement in ipairs(FactionSchema) do
        if DB.Query(statement) == nil then
            return false
        end
    end
    return true
end
Factions.CreateTables = createTables

DB.Ready(function()
    if not Factions.CreateTables() then
        Platform.Print('error', 'core_factions: Tabellen konnten nicht angelegt werden. Bitte database/factions.sql ausfuehren.')
        return
    end
    for id in pairs(Orgs) do
        DB.Update('INSERT IGNORE INTO faction_settings (faction) VALUES (?)', { id })
    end
    Factions.LoadRanks()
    Factions.Ready = true
    local list = Factions.Core('GetActiveCharacters') or {}
    for source, characterId in pairs(list) do
        onCharacterLoaded(source, characterId)
    end
end)

------------------------------------------------------------------------
-- Schnittstellen fuer andere Scripts
------------------------------------------------------------------------

-- Mitglied eines Spielers: { faction, label, rank, rankName, dn, onDuty } oder nil
Platform.Export('GetMember', function(source)
    local member = Factions.MemberOf(source)
    if not member then
        return nil
    end
    return {
        characterId = member.characterId,
        faction = member.faction,
        label = Orgs[member.faction].label,
        rank = member.rank,
        rankName = Factions.RankName(member.faction, member.rank),
        dn = member.dn,
        onDuty = duty[tonumber(source)] == member.faction,
    }
end)
Platform.Export('IsOnDuty', Factions.IsOnDuty)
-- Recht pruefen, optional nur im Dienst: HasPermission(source, 'ems.revive', true)
Platform.Export('HasPermission', function(source, key, needsDuty)
    return (Factions.Can(source, key, { duty = needsDuty == true }))
end)
Platform.Export('RegisterPermissions', Factions.RegisterPermissions)
Platform.Export('GetOnDuty', Factions.OnDutyList)
-- Aussehen und Namen einer Organisation fuer andere UIs (z. B. MDT von core_dispatch):
-- { id, label, short, ranks, logo = 'nui://core_factions/html/logos/ems.png' oder nil, theme = { base, ink, accent, mark, signal } }
-- signal ist dieselbe Farbe wie mark: die zweite Farbe der Organisation ist auch ihre Warnfarbe.
Platform.Export('GetOrg', function(faction)
    local org = Factions.Org(faction)
    if not org then
        return nil
    end
    return {
        id = org.id, label = org.label, short = org.short, ranks = org.ranks,
        logo = org.logo and ('nui://core_factions/html/%s'):format(org.logo) or nil,
        theme = { base = org.theme.base, ink = org.theme.ink, accent = org.theme.accent, mark = org.theme.mark, signal = org.theme.mark },
    }
end)
Platform.Export('GetBalance', Factions.GetBalance)
Platform.Export('Deposit', Factions.Deposit)
Platform.Export('Withdraw', Factions.Withdraw)
