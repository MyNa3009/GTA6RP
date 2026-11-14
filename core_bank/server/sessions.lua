-- Anfragen aus den UIs. Eine Sitzung beginnt mit bank_open und sagt, wo die Person steht:
--   bank   Filiale: alles (Konto, Einzahlen, Auszahlen, Ueberweisen, Kontoauszug, Schulden)
--   atm    Bankautomat: Kontostand, Auszahlen und Einzahlen mit Grenzen
--   admin  Admin-Ansicht eines beliebigen Kontos, nur lesen (siehe admin.lua)
-- Der Server prueft bei jeder Anfrage neu, ob die Person noch am Schalter oder Automaten steht.
-- Bankautomaten sind Objekte der Spielwelt, ihre Position kennt nur der Client. Der Server prueft darum, dass die
-- Person an der gemeldeten Stelle steht. Mehr als Kontostand, Ein- und Auszahlen gibt es dort nicht.

if BankDisabled then
    return
end

local CFG = Config.Bank
local ATM = CFG.Atm
local BRANCH_TOLERANCE = 1.0   -- Meter Spielraum zum Abstand im Client
local ATM_TOLERANCE = 1.5
local POLL_MS = 50

local sessions = {}   -- [source] = { channel, subject, place = { x, y, z }, range, admin, canManage, name }
local busy = {}       -- [source] = true, solange eine Buchung laeuft

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function coords(value)
    if type(value) ~= 'table' then
        return nil
    end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function near(source, place, range)
    local position = Platform.GetPlayerPosition(source)
    return position ~= nil and distance(position, place) <= range
end

function Bank.Session(source)
    return sessions[tonumber(source)]
end

-- Was die UI nach jeder Aktion neu anzeigt
local function view(source, session)
    local atm = session.channel == 'atm'
    local overview = Bank.Overview(session.subject, atm and ATM.RecentCount or CFG.RecentCount)
    if not overview then
        return nil
    end
    if not session.admin then
        overview.cash = tonumber(Bank.Core('GetMoney', source, 'cash')) or 0
    end
    if atm then
        overview.atmRemaining = Bank.AtmRemaining(session.subject)
    elseif not session.admin then
        overview.recipients = Bank.Recipients(session.subject)
    end
    return overview
end
Bank.View = view

-- Callback anmelden. options: { channels = { bank = true, ... }, mutate = true (immer nur eine Buchung gleichzeitig) }
-- handler(source, data, session) gibt { ok, data, error } zurueck.
function Bank.RegisterCall(name, options, handler)
    Network.RegisterCallback(name, function(source, data)
        if not Bank.Ready or not Bank.CharacterOf(source) then
            return { ok = false, error = 'no_character' }
        end
        local session = sessions[source]
        if not session then
            return { ok = false, error = 'no_session' }
        end
        if not options.channels[session.channel] then
            return { ok = false, error = 'not_here' }
        end
        if session.place and not near(source, session.place, session.range) then
            sessions[source] = nil
            return { ok = false, error = 'too_far' }
        end
        if not session.admin and Bank.Core('IsDead', source) == true then
            return { ok = false, error = 'is_dead' }
        end
        if options.mutate then
            if busy[source] then
                return { ok = false, error = 'busy' }
            end
            busy[source] = true
        end
        local ok, result = pcall(handler, source, type(data) == 'table' and data or {}, session)
        if options.mutate then
            busy[source] = nil
        end
        if not ok then
            Platform.Print('error', ('core_bank: Fehler in %s: %s'):format(name, tostring(result)))
            return { ok = false, error = 'server_error' }
        end
        return result
    end)
end

local function fail(err)
    return { ok = false, error = err or 'server_error' }
end

------------------------------------------------------------------------
-- Sitzung
------------------------------------------------------------------------

-- Wird von admin.lua gesetzt: Admin-Sitzung pruefen und anlegen
function Bank.OpenAdmin()
    return nil, 'no_permission'
end

Network.RegisterCallback('bank_open', function(source, data)
    if not Bank.Ready or not Bank.CharacterOf(source) then
        return fail('no_character')
    end
    data = type(data) == 'table' and data or {}
    local session, err
    if data.channel == 'bank' then
        local branch = BankBranches[math.floor(tonumber(data.branch) or 0)]
        if not branch then
            return fail('invalid_input')
        end
        session = { channel = 'bank', subject = Bank.CharacterOf(source), place = { x = branch.x, y = branch.y, z = branch.z },
            range = CFG.BranchDistance + BRANCH_TOLERANCE }
    elseif data.channel == 'atm' then
        local place = coords(data.atm)
        if not place then
            return fail('invalid_input')
        end
        session = { channel = 'atm', subject = Bank.CharacterOf(source), place = place, range = ATM.Distance + ATM_TOLERANCE }
    elseif data.channel == 'admin' then
        session, err = Bank.OpenAdmin(source, data)
        if not session then
            return fail(err)
        end
    else
        return fail('invalid_input')
    end

    if session.place and not near(source, session.place, session.range) then
        return fail('too_far')
    end
    if not session.admin and Bank.Core('IsDead', source) == true then
        return fail('is_dead')
    end
    local overview = view(source, session)
    if not overview then
        return fail('not_found')
    end
    sessions[source] = session
    return { ok = true, data = {
        channel = session.channel, bankName = CFG.Name, overview = overview,
        admin = session.admin or nil, canManage = session.canManage or nil,
        purposeMax = CFG.PurposeMaxLength, transferMax = CFG.TransferMax, titleMax = CFG.Debts.TitleMaxLength,
        debtMax = CFG.Debts.MaxAmount, dueHours = CFG.Debts.DueHours, maxDueHours = CFG.Debts.MaxDueHours,
        atm = session.channel == 'atm' and { withdrawMax = ATM.WithdrawMax, depositMax = ATM.DepositMax, deposit = ATM.Deposit == true,
            daily = ATM.DailyWithdraw > 0 and ATM.DailyWithdraw or nil, quick = ATM.QuickAmounts } or nil,
    } }
end)

Network.RegisterCallback('bank_close', function(source)
    sessions[source] = nil
    busy[source] = nil
    return { ok = true }
end)

function Bank.OnUnloaded(source)
    sessions[source] = nil
    busy[source] = nil
end

------------------------------------------------------------------------
-- Konto
------------------------------------------------------------------------

local ALL = { bank = true, atm = true, admin = true }
local OWN = { bank = true, atm = true }
local BRANCH = { bank = true }
local READ = { bank = true, admin = true }

Bank.RegisterCall('bank_overview', { channels = ALL }, function(source, data, session)
    local overview = view(source, session)
    if not overview then
        return fail('not_found')
    end
    return { ok = true, data = { overview = overview } }
end)

Bank.RegisterCall('bank_statement', { channels = READ }, function(source, data, session)
    return { ok = true, data = Bank.Statement(session.subject, { page = data.page, filter = data.filter }) }
end)

Bank.RegisterCall('bank_deposit', { channels = OWN, mutate = true }, function(source, data, session)
    local balance, err = Bank.Deposit(source, data.amount, session.channel)
    if not balance then
        return fail(err)
    end
    return { ok = true, data = { overview = view(source, session) } }
end)

Bank.RegisterCall('bank_withdraw', { channels = OWN, mutate = true }, function(source, data, session)
    local balance, err = Bank.Withdraw(source, data.amount, session.channel)
    if not balance then
        return fail(err)
    end
    return { ok = true, data = { overview = view(source, session) } }
end)

-- Empfaenger pruefen, bevor ueberwiesen wird
Bank.RegisterCall('bank_lookup', { channels = BRANCH }, function(source, data, session)
    if not Bank.NormalizeNumber(data.number) then
        return fail('invalid_number')
    end
    local target = Bank.Lookup(data.number)
    if not target then
        return fail('unknown_account')
    end
    if target.characterId == session.subject then
        return fail('same_account')
    end
    return { ok = true, data = { name = target.name, number = target.number } }
end)

Bank.RegisterCall('bank_transfer', { channels = BRANCH, mutate = true }, function(source, data, session)
    local result, err = Bank.Transfer(session.subject, data.number, data.amount, data.purpose,
        { channel = 'bank', actorAccountId = Bank.Core('GetAccountId', source) })
    if not result then
        return fail(err)
    end
    return { ok = true, data = { to = result.to, overview = view(source, session) } }
end)

------------------------------------------------------------------------
-- Schulden
------------------------------------------------------------------------

Bank.RegisterCall('bank_debts', { channels = READ }, function(source, data, session)
    return { ok = true, data = Debts.List(session.subject, { status = data.status, page = data.page }) }
end)

Bank.RegisterCall('bank_debt_pay', { channels = BRANCH, mutate = true }, function(source, data, session)
    local result, err = Debts.Pay(session.subject, data.id, data.amount, { channel = 'bank', actorAccountId = Bank.Core('GetAccountId', source) })
    if not result then
        return fail(err)
    end
    return { ok = true, data = { debt = result.debt, paid = result.paid, overview = view(source, session) } }
end)

------------------------------------------------------------------------
-- Forderung ausstellen (G-Menue, Person anschauen): Rechnung mit Zustimmung, Strafe ohne
------------------------------------------------------------------------

local CONSENT_REASONS = {
    declined = 'consent_declined', timeout = 'consent_timeout', target_busy = 'target_busy',
    target_offline = 'target_offline', no_character = 'target_offline', cancelled = 'consent_declined',
}

local function consent(source, target, title, text)
    local id, err = Bank.Core('StartConsent', source, target, { title = title, text = text })
    if not id then
        return false, CONSENT_REASONS[err] or 'consent_declined'
    end
    Platform.Notify(source, Config.Consent and Config.Consent.WaitingText or 'Warte, bis die Person zustimmt…', 'info')
    while true do
        local accepted, reason = Bank.Core('GetConsentResult', id)
        if accepted == true then
            return true
        end
        if accepted == false then
            return false, CONSENT_REASONS[reason] or 'consent_declined'
        end
        Platform.Wait(POLL_MS)
    end
end

-- Darf ich ausstellen, und was? Fuer das G-Menue.
Network.RegisterCallback('bank_issuer', function(source)
    if not Bank.Ready or not Bank.CharacterOf(source) then
        return fail('no_character')
    end
    local faction, issuer = Debts.IssuerOf(source)
    if not faction then
        return fail(issuer)
    end
    return { ok = true, data = { label = issuer.label, kind = issuer.kind, max = issuer.max, titleMax = CFG.Debts.TitleMaxLength } }
end)

Network.RegisterCallback('bank_issue', function(source, data)
    local characterId = Bank.Ready and Bank.CharacterOf(source)
    if not characterId then
        return fail('no_character')
    end
    data = type(data) == 'table' and data or {}
    local faction, issuer = Debts.IssuerOf(source)
    if not faction then
        return fail(issuer)
    end
    local target = tonumber(data.serverId)
    local targetCharacter = target and target ~= source and Bank.CharacterOf(target)
    if not targetCharacter then
        return fail('target_offline')
    end
    local own, other = Platform.GetPlayerPosition(source), Platform.GetPlayerPosition(target)
    if not own or not other or distance(own, other) > CFG.Debts.IssueDistance then
        return fail('too_far')
    end
    local amount = Bank.Amount(data.amount, issuer.max)
    local title = Bank.Text(data.title, CFG.Debts.TitleMaxLength)
    if not amount then
        return fail('invalid_amount')
    end
    if not title then
        return fail('invalid_input')
    end
    if busy[source] then
        return fail('busy')
    end
    busy[source] = true
    local ok, result = pcall(function()
        local kindLabel = CFG.Debts.Kinds[issuer.kind] or CFG.Debts.Kinds.other
        if issuer.consent then
            local accepted, reason = consent(source, target, kindLabel, ('%s über %s annehmen? %s'):format(kindLabel, Bank.Money(amount), title))
            if not accepted then
                return fail(reason)
            end
        end
        local name = Bank.NameOf(characterId)
        local id, err = Debts.Add(targetCharacter, { amount = amount, title = title, kind = issuer.kind, creditor = faction,
            dueHours = issuer.dueHours, issuedById = characterId, issuedBy = name, actorAccountId = Bank.Core('GetAccountId', source) })
        if not id then
            return fail(err)
        end
        Bank.Factions('AddProtocol', faction, { area = 'kasse', action = 'debt_issue', actorSource = source, target = targetCharacter,
            text = ('%s über %s ausgestellt: %s'):format(kindLabel, Bank.Money(amount), title) })
        local debt = Debts.Get(id)
        return { ok = true, data = { id = id, due = debt and debt.due or nil, kindLabel = kindLabel } }
    end)
    busy[source] = nil
    if not ok then
        Platform.Print('error', ('core_bank: Fehler in bank_issue: %s'):format(tostring(result)))
        return fail('server_error')
    end
    return result
end)
