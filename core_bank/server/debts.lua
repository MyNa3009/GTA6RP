-- Schulden: Strafen, Rechnungen und Gebuehren eines Charakters.
-- Andere Scripts legen sie mit exports.core_bank:AddDebt an. Bezahlt wird vom Bankkonto, das Geld geht an den
-- Glaeubiger: in die Kasse der Organisation (core_factions) oder an den Staat (weg).
-- Nach der Frist kommt einmal die Mahngebuehr dazu, und die Bank zieht vom Konto ein, soweit Geld da ist.
-- Erledigte und erlassene Schulden bleiben stehen, nichts wird geloescht.

if BankDisabled then
    return
end

Debts = {}

local CFG = Config.Bank.Debts
local STATE = 'state'
local KINDS = CFG.Kinds
local NAME_MAX = 101
local LABEL_MAX = 64
local REASON_MAX = 120
local HOUR_MIN = 1
local MINUTE_MS = 60000
local OWN = 'bank'

local ROW_SQL = "SELECT id, character_id, kind, creditor, creditor_label, title, amount, fee, paid, status, issued_by, resource, "
    .. "DATE_FORMAT(due_at, '%Y-%m-%d %H:%i') AS due, due_at <= NOW() AS overdue, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at, "
    .. "DATE_FORMAT(closed_at, '%Y-%m-%d %H:%i') AS closed, closed_by, close_reason FROM bank_debts"

local function flag(value)
    return value == 1 or value == true
end

local function publicDebt(row)
    local amount, fee, paid = tonumber(row.amount), tonumber(row.fee), tonumber(row.paid)
    local open = row.status == 'open'
    return {
        id = row.id, characterId = row.character_id, kind = row.kind, kindLabel = KINDS[row.kind] or KINDS.other,
        creditor = row.creditor, creditorLabel = row.creditor_label, title = row.title,
        amount = amount, fee = fee, paid = paid, rest = open and (amount + fee - paid) or 0,
        status = row.status, overdue = open and flag(row.overdue), due = row.due, at = row.at, issuedBy = row.issued_by,
        closed = row.closed, closedBy = row.closed_by, closeReason = row.close_reason,
    }
end

function Debts.Get(debtId)
    debtId = tonumber(debtId)
    local row = debtId and DB.Single(ROW_SQL .. ' WHERE id = ?', { math.floor(debtId) })
    return row and publicDebt(row) or nil
end

-- Kurzform fuer die Startseite: { count, total, overdue }
function Debts.Summary(characterId)
    local row = DB.Single("SELECT COUNT(*) AS n, COALESCE(SUM(amount + fee - paid), 0) AS total, COALESCE(SUM(due_at <= NOW()), 0) AS overdue FROM bank_debts WHERE character_id = ? AND status = 'open'",
        { characterId }) or {}
    return { count = tonumber(row.n) or 0, total = tonumber(row.total) or 0, overdue = tonumber(row.overdue) or 0 }
end

-- options: { status = 'open' | 'closed', page }. Gibt { debts, page, more } zurueck, offene nach Frist, erledigte neueste zuerst.
function Debts.List(characterId, options)
    options = type(options) == 'table' and options or {}
    local closed = options.status == 'closed'
    local page = math.max(1, math.floor(tonumber(options.page) or 1))
    local size = CFG.PageSize
    local where = closed and " WHERE character_id = ? AND status IN ('paid', 'cancelled') ORDER BY id DESC"
        or " WHERE character_id = ? AND status = 'open' ORDER BY due_at ASC, id ASC"
    local rows = DB.Query(ROW_SQL .. where .. ' LIMIT ? OFFSET ?', { characterId, size + 1, (page - 1) * size }) or {}
    local debts = {}
    for i = 1, math.min(#rows, size) do
        debts[i] = publicDebt(rows[i])
    end
    return { debts = debts, page = page, more = #rows > size }
end

-- Glaeubiger pruefen: 'state' oder eine Organisation aus core_factions. Gibt Schluessel und Anzeigename zurueck.
local function creditorOf(info)
    local creditor = type(info.creditor) == 'string' and info.creditor or STATE
    if creditor == STATE then
        return STATE, Bank.Text(info.creditorLabel, LABEL_MAX) or CFG.StateLabel
    end
    if not creditor:match('^[%w_]+$') or #creditor > 32 then
        return nil
    end
    local org = Bank.HasFactions() and Bank.Factions('GetOrg', creditor)
    if type(org) == 'table' then
        return creditor, Bank.Text(org.label, LABEL_MAX) or creditor
    end
    -- Unbekannte Organisation: als Name stehen lassen, das Geld geht dann an niemanden
    return creditor, Bank.Text(info.creditorLabel, LABEL_MAX) or creditor
end

local function changed(characterId, debt, what)
    Bank.Changed(characterId, 'debts')
    Platform.Emit('core_bank:debtChanged', characterId, debt, what)
end

-- Neue Forderung. info: { amount, title, kind?, creditor?, creditorLabel?, dueHours?, issuedById?, issuedBy?, actorAccountId?, data? }
-- Gibt die Nummer der Forderung zurueck oder nil und einen Fehlercode.
function Debts.Add(characterId, info)
    characterId = tonumber(characterId)
    info = type(info) == 'table' and info or {}
    if not characterId or not Bank.NameOf(characterId) then
        return nil, 'not_found'
    end
    local amount = Bank.Amount(info.amount, CFG.MaxAmount)
    local title = Bank.Text(info.title, CFG.TitleMaxLength)
    if not amount then
        return nil, 'invalid_amount'
    end
    if not title then
        return nil, 'invalid_input'
    end
    local kind = KINDS[info.kind] and info.kind or 'other'
    local creditor, creditorLabel = creditorOf(info)
    if not creditor then
        return nil, 'invalid_input'
    end
    local hours = math.floor(tonumber(info.dueHours) or CFG.DueHours)
    hours = math.max(HOUR_MIN, math.min(CFG.MaxDueHours, hours))
    local resource = Platform.GetCallingResource()

    local id = DB.Insert('INSERT INTO bank_debts (character_id, kind, creditor, creditor_label, title, amount, issued_by_id, issued_by, resource, due_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? HOUR))',
        DB.Args(characterId, kind, creditor, creditorLabel, title, amount, tonumber(info.issuedById), Bank.Text(info.issuedBy, NAME_MAX), resource, hours))
    if not id then
        return nil, 'db_error'
    end
    Bank.Log({ actor_account_id = info.actorAccountId, character_id = characterId, action = 'debt_add', amount = amount, reason = title,
        data = { debtId = id, kind = kind, creditor = creditor, dueHours = hours, issuedBy = info.issuedBy, issuedById = info.issuedById, resource = resource, extra = info.data } })
    local debt = Debts.Get(id)
    Bank.Notify(characterId, ('Neue %s über %s: %s. Zahlbar in der Bank bis %s.'):format(KINDS[kind], Bank.Money(amount), title, debt and debt.due or '?'), 'warning')
    changed(characterId, debt, 'added')
    return id
end

-- Geld an den Glaeubiger weitergeben
local function payOut(debt, amount)
    if debt.creditor == STATE or not Bank.HasFactions() then
        return
    end
    Bank.Factions('Deposit', debt.creditor, amount, {
        reason = ('%s von ID %d: %s'):format(debt.kindLabel, debt.characterId, debt.title),
        data = { debtId = debt.id, resource = 'core_bank' },
    })
end

-- Zahlung vom Bankkonto. amount ohne Angabe: der ganze Rest. info: { channel, auto (Einzug der Bank), actorAccountId }
-- Gibt { debt, balance, paid } zurueck oder nil und einen Fehlercode.
function Debts.Pay(characterId, debtId, amount, info)
    info = type(info) == 'table' and info or {}
    characterId = tonumber(characterId)
    local debt = Debts.Get(debtId)
    if not characterId or not debt or debt.characterId ~= characterId then
        return nil, 'not_found'
    end
    if debt.status ~= 'open' then
        return nil, 'debt_closed'
    end
    if amount == nil then
        amount = debt.rest
    end
    amount = Bank.Amount(amount, debt.rest)
    if not amount then
        return nil, 'invalid_amount'
    end

    -- Erst schauen, ob genug auf dem Konto ist, dann gibt es eine klare Meldung
    local have = Bank.Balance(characterId)
    if have and have < amount then
        return nil, 'not_enough_money'
    end

    local text = ('%s: %s'):format(debt.kindLabel, debt.title)
    local balance, err = Bank.Core('RemoveBankByCharacter', characterId, amount, text,
        { actorAccountId = info.actorAccountId, data = { [OWN] = true, debtId = debt.id, auto = info.auto or nil } })
    if not balance then
        return nil, Bank.Why(err, 'bank', characterId, amount)
    end

    local newPaid = debt.paid + amount
    local done = newPaid >= debt.amount + debt.fee
    -- Nur buchen, wenn sich seit dem Lesen nichts geaendert hat (zwei Zahlungen gleichzeitig)
    local updated = DB.Update("UPDATE bank_debts SET paid = ?, status = ?, closed_at = IF(? = 1, NOW(), NULL), closed_by = ? WHERE id = ? AND status = 'open' AND paid = ?",
        DB.Args(newPaid, done and 'paid' or 'open', done and 1 or 0, done and (info.auto and 'Einzug der Bank' or 'Schuldner') or nil, debt.id, debt.paid))
    if updated ~= 1 then
        Bank.Core('AddBankByCharacter', characterId, amount, text .. ' (zurück)', { data = { [OWN] = true } })
        return nil, 'busy'
    end

    Bank.Record(characterId, { kind = info.auto and 'collect' or 'debt', amount = -amount, balance = balance, text = text,
        otherName = debt.creditorLabel, channel = info.channel or 'system' })
    payOut(debt, amount)
    Bank.Log({ actor_account_id = info.actorAccountId, character_id = characterId, action = info.auto and 'debt_collect' or 'debt_pay', amount = amount,
        balance_before = balance + amount, balance_after = balance, reason = debt.title,
        data = { debtId = debt.id, creditor = debt.creditor, rest = debt.rest - amount, channel = info.channel } })
    local fresh = Debts.Get(debt.id)
    changed(characterId, fresh, done and 'paid' or 'partial')
    return { debt = fresh, balance = balance, paid = amount }
end

-- Forderung erlassen. Schon Bezahltes bleibt beim Glaeubiger. info: { by, reason, actorAccountId }
function Debts.Cancel(debtId, info)
    info = type(info) == 'table' and info or {}
    local debt = Debts.Get(debtId)
    if not debt then
        return nil, 'not_found'
    end
    if debt.status ~= 'open' then
        return nil, 'debt_closed'
    end
    local reason = Bank.Text(info.reason, REASON_MAX)
    if DB.Update("UPDATE bank_debts SET status = 'cancelled', closed_at = NOW(), closed_by = ?, close_reason = ? WHERE id = ? AND status = 'open'",
        DB.Args(Bank.Text(info.by, NAME_MAX), reason, debt.id)) ~= 1 then
        return nil, 'busy'
    end
    Bank.Log({ actor_account_id = info.actorAccountId, character_id = debt.characterId, action = 'debt_cancel', amount = debt.rest, reason = reason or debt.title,
        data = { debtId = debt.id, by = info.by, paid = debt.paid, resource = Platform.GetCallingResource() } })
    local fresh = Debts.Get(debt.id)
    Bank.Notify(debt.characterId, ('%s erlassen: %s.'):format(debt.kindLabel, debt.title), 'success')
    changed(debt.characterId, fresh, 'cancelled')
    return fresh
end

------------------------------------------------------------------------
-- Frist: Mahngebuehr und Einzug
------------------------------------------------------------------------

-- Mahngebuehr einmal nach der Frist. Gibt die Forderung mit Gebuehr zurueck.
local function remind(row)
    local rest = tonumber(row.amount) - tonumber(row.paid)
    local fee = CFG.LateFeePercent > 0 and math.ceil(rest * CFG.LateFeePercent / 100) or 0
    if DB.Update("UPDATE bank_debts SET fee = ?, reminded_at = NOW() WHERE id = ? AND status = 'open' AND reminded_at IS NULL", { fee, row.id }) ~= 1 then
        return
    end
    Bank.Log({ character_id = row.character_id, action = 'debt_overdue', amount = fee, reason = row.title, data = { debtId = row.id, rest = rest } })
    local text = fee > 0 and ('Frist abgelaufen: %s. Mahngebühr %s, offen sind jetzt %s.'):format(row.title, Bank.Money(fee), Bank.Money(rest + fee))
        or ('Frist abgelaufen: %s. Offen sind %s.'):format(row.title, Bank.Money(rest))
    Bank.Notify(row.character_id, text, 'warning')
    changed(row.character_id, Debts.Get(row.id), 'overdue')
end

-- Ueberfaellige Forderung vom Konto einziehen, soweit Geld da ist
local function collect(row)
    DB.Update('UPDATE bank_debts SET checked_at = NOW() WHERE id = ?', { row.id })
    local balance = Bank.Balance(row.character_id)
    local rest = tonumber(row.amount) + tonumber(row.fee) - tonumber(row.paid)
    local amount = balance and math.min(rest, balance - CFG.CollectKeep) or 0
    if amount < 1 then
        return
    end
    local result = Debts.Pay(row.character_id, row.id, amount, { auto = true, channel = 'system' })
    if result then
        local left = result.debt and result.debt.rest or 0
        Bank.Notify(row.character_id, left > 0
            and ('Die Bank hat %s eingezogen: %s. Offen bleiben %s.'):format(Bank.Money(amount), row.title, Bank.Money(left))
            or ('Die Bank hat %s eingezogen: %s. Die Forderung ist erledigt.'):format(Bank.Money(amount), row.title), 'warning')
    end
end

local OVERDUE_SQL = "SELECT id, character_id, title, amount, fee, paid FROM bank_debts WHERE status = 'open' AND due_at <= NOW()"

-- Ein Lauf: erst mahnen, dann einziehen. characterId: nur diese Person (beim Einloggen), sonst alle.
function Debts.Sweep(characterId)
    local filter, args = '', {}
    if characterId then
        filter, args = ' AND character_id = ?', { characterId }
    end
    local limitArgs = { table.unpack(args) }
    limitArgs[#limitArgs + 1] = CFG.SweepLimit
    for _, row in ipairs(DB.Query(OVERDUE_SQL .. ' AND reminded_at IS NULL' .. filter .. ' ORDER BY due_at ASC LIMIT ?', limitArgs) or {}) do
        remind(row)
    end
    if not CFG.AutoCollect then
        return
    end
    -- Am laengsten nicht gepruefte zuerst, damit leere Konten die anderen nicht blockieren
    for _, row in ipairs(DB.Query(OVERDUE_SQL .. ' AND reminded_at IS NOT NULL' .. filter .. ' ORDER BY checked_at IS NOT NULL, checked_at ASC LIMIT ?', limitArgs) or {}) do
        collect(row)
    end
end

local sweeping = false
local function sweepAll()
    if sweeping or not Bank.Ready then
        return
    end
    sweeping = true
    local ok, err = pcall(Debts.Sweep)
    sweeping = false
    if not ok then
        Platform.Print('error', ('core_bank: Fehler beim Pruefen der Schulden: %s'):format(tostring(err)))
    end
end

Platform.SetInterval(CFG.SweepMinutes * MINUTE_MS, sweepAll)

-- Beim Einloggen: ueberfaellige Schulden dieser Person sofort pruefen und an offene erinnern
function Bank.OnLoaded(source, characterId)
    local ok, err = pcall(Debts.Sweep, characterId)
    if not ok then
        Platform.Print('error', ('core_bank: Fehler beim Pruefen der Schulden von ID %d: %s'):format(characterId, tostring(err)))
    end
    local summary = Debts.Summary(characterId)
    if summary.count > 0 then
        Platform.Notify(source, ('Du hast %d offene %s über %s. Bezahlen kannst du in jeder Filiale der Bank.'):format(
            summary.count, summary.count == 1 and 'Forderung' or 'Forderungen', Bank.Money(summary.total)), 'warning')
    end
end

------------------------------------------------------------------------
-- Forderungen aus dem Spiel: Organisationen stellen Rechnungen oder Strafen aus (G-Menue)
------------------------------------------------------------------------

function Bank.RegisterPermissions()
    if not Bank.HasFactions() then
        return
    end
    for faction, issuer in pairs(CFG.Issuers) do
        Bank.Factions('RegisterPermissions', faction, {
            { key = issuer.permission, group = 'Bank', label = issuer.label, minRank = issuer.minRank or 1 },
        })
    end
end

-- Darf source Forderungen ausstellen? Gibt Organisation und Einstellung zurueck, sonst nil und einen Fehlercode.
function Debts.IssuerOf(source)
    if not Bank.HasFactions() then
        return nil, 'no_permission'
    end
    local member = Bank.Factions('GetMember', source)
    local issuer = type(member) == 'table' and CFG.Issuers[member.faction]
    if not issuer then
        return nil, 'no_permission'
    end
    if not member.onDuty then
        return nil, 'not_on_duty'
    end
    if Bank.Factions('HasPermission', source, issuer.permission, true) ~= true then
        return nil, 'no_permission'
    end
    return member.faction, issuer
end

------------------------------------------------------------------------
-- Fuer andere Scripts
------------------------------------------------------------------------

Platform.Export('AddDebt', Debts.Add)
Platform.Export('GetDebt', Debts.Get)
Platform.Export('GetDebts', function(characterId, options)
    characterId = tonumber(characterId)
    return characterId and Debts.List(characterId, options) or nil
end)
Platform.Export('GetDebtSummary', function(characterId)
    characterId = tonumber(characterId)
    return characterId and Debts.Summary(characterId) or nil
end)
Platform.Export('PayDebt', Debts.Pay)
Platform.Export('CancelDebt', Debts.Cancel)
