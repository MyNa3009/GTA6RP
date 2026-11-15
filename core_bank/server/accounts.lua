-- Konto: Kontonummer, Kontoauszug, Einzahlen, Auszahlen, Ueberweisen.
-- Jede Buchung auf dem Bankkonto landet im Kontoauszug: eigene Buchungen traegt core_bank selbst ein,
-- Buchungen anderer Scripts (Gehalt, Bonus, Admin) kommen ueber das Ereignis core:moneyBooked der Core.
-- Ob jemand in der Filiale oder am Automaten steht, prueft sessions.lua. Hier gelten nur Betraege und Grenzen.

if BankDisabled then
    return
end

local CFG = Config.Bank
local ATM = CFG.Atm
local NUMBER_LENGTH = 8
local NUMBER_MIN, NUMBER_MAX = 10000000, 99999999
local NUMBER_TRIES = 20
local TEXT_MAX = 160
local CHANNELS = { bank = true, atm = true, phone = true, system = true }
-- Kennzeichen an Buchungen der Core, die core_bank selbst in den Kontoauszug schreibt
local OWN = 'bank'

local TEXT = {
    deposit = { bank = 'Einzahlung in der Filiale', atm = 'Einzahlung am Bankautomaten' },
    withdraw = { bank = 'Auszahlung in der Filiale', atm = 'Auszahlung am Bankautomaten' },
    refund = 'Auszahlung zurückgebucht, kein Platz für Bargeld',
    transfer = 'Überweisung',
    booking = 'Buchung',
}

------------------------------------------------------------------------
-- Kontonummer
------------------------------------------------------------------------

-- Nur Ziffern, genau 8 Stellen. Sonst nil.
function Bank.NormalizeNumber(value)
    if type(value) == 'number' then
        value = ('%d'):format(value)
    end
    if type(value) ~= 'string' then
        return nil
    end
    value = value:gsub('%D', '')
    if #value ~= NUMBER_LENGTH then
        return nil
    end
    return value
end

-- Kontonummer eines Charakters. Legt das Konto beim ersten Mal an. nil, wenn es den Charakter nicht gibt.
function Bank.NumberOf(characterId)
    local number = DB.Scalar('SELECT number FROM bank_accounts WHERE character_id = ?', { characterId })
    if number then
        return number
    end
    if not Bank.NameOf(characterId) then
        return nil
    end
    for _ = 1, NUMBER_TRIES do
        local candidate = ('%d'):format(math.random(NUMBER_MIN, NUMBER_MAX))
        DB.Update('INSERT IGNORE INTO bank_accounts (character_id, number) VALUES (?, ?)', { characterId, candidate })
        number = DB.Scalar('SELECT number FROM bank_accounts WHERE character_id = ?', { characterId })
        if number then
            Bank.Log({ character_id = characterId, action = 'account_open', data = { number = number } })
            return number
        end
    end
    Platform.Print('error', ('core_bank: Fuer ID %d konnte keine freie Kontonummer gefunden werden.'):format(characterId))
    return nil
end

-- Wem gehoert die Kontonummer? Gibt { characterId, name, number } zurueck oder nil.
function Bank.Lookup(number)
    number = Bank.NormalizeNumber(number)
    if not number then
        return nil
    end
    local characterId = tonumber(DB.Scalar('SELECT character_id FROM bank_accounts WHERE number = ?', { number }))
    local name = characterId and Bank.NameOf(characterId)
    if not name then
        return nil
    end
    return { characterId = characterId, name = name, number = number }
end

------------------------------------------------------------------------
-- Kontoauszug
------------------------------------------------------------------------

local ROW_SQL = "SELECT id, kind, amount, balance, text, other_name, other_number, channel, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at FROM bank_transactions"
local FILTERS = { all = '', ['in'] = ' AND amount > 0', out = ' AND amount < 0' }

local function publicRow(row)
    return { id = row.id, kind = row.kind, amount = tonumber(row.amount), balance = tonumber(row.balance), text = row.text,
        other = row.other_name, otherNumber = row.other_number, channel = row.channel, at = row.at }
end

-- Buchung in den Kontoauszug. entry: { kind, amount (mit Vorzeichen), balance, text, otherId, otherName, otherNumber, channel }
function Bank.Record(characterId, entry)
    local channel = CHANNELS[entry.channel] and entry.channel or 'system'
    local id = DB.Insert('INSERT INTO bank_transactions (character_id, kind, amount, balance, text, other_id, other_name, other_number, channel) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        DB.Args(characterId, entry.kind, entry.amount, entry.balance, Bank.Text(entry.text, TEXT_MAX) or TEXT.booking,
            entry.otherId, entry.otherName, entry.otherNumber, channel))
    Platform.Emit('core_bank:booked', characterId, { id = id, kind = entry.kind, amount = entry.amount, balance = entry.balance,
        text = entry.text, other = entry.otherName, channel = channel })
    Bank.Changed(characterId, 'account')
    return id
end

-- Die letzten Buchungen, neueste zuerst
function Bank.Recent(characterId, limit)
    local list = {}
    for _, row in ipairs(DB.Query(ROW_SQL .. ' WHERE character_id = ? ORDER BY id DESC LIMIT ?', { characterId, limit }) or {}) do
        list[#list + 1] = publicRow(row)
    end
    return list
end

-- Seite des Kontoauszugs. options: { page (ab 1), filter = 'all' | 'in' | 'out' }. Gibt { entries, page, more } zurueck.
function Bank.Statement(characterId, options)
    options = type(options) == 'table' and options or {}
    local page = math.max(1, math.floor(tonumber(options.page) or 1))
    local filter = FILTERS[options.filter] or ''
    local size = CFG.PageSize
    local rows = DB.Query(ROW_SQL .. ' WHERE character_id = ?' .. filter .. ' ORDER BY id DESC LIMIT ? OFFSET ?',
        { characterId, size + 1, (page - 1) * size }) or {}
    local entries = {}
    for i = 1, math.min(#rows, size) do
        entries[i] = publicRow(rows[i])
    end
    return { entries = entries, page = page, more = #rows > size }
end

-- Wem wurde zuletzt ueberwiesen: { { name, number } }, jeder nur einmal
function Bank.Recipients(characterId)
    local list = {}
    local rows = DB.Query("SELECT other_name, other_number, MAX(id) AS last FROM bank_transactions WHERE character_id = ? AND kind = 'transfer_out' AND other_number IS NOT NULL GROUP BY other_number, other_name ORDER BY last DESC LIMIT ?",
        { characterId, CFG.RecentRecipients }) or {}
    for _, row in ipairs(rows) do
        list[#list + 1] = { name = row.other_name, number = row.other_number }
    end
    return list
end

function Bank.Balance(characterId)
    return tonumber(Bank.Core('GetBankByCharacter', characterId))
end

-- Konto eines Charakters, auch offline: { characterId, name, number, balance } oder nil
function Bank.Account(characterId)
    characterId = tonumber(characterId)
    local name = characterId and Bank.NameOf(characterId)
    local number = name and Bank.NumberOf(characterId)
    if not number then
        return nil
    end
    return { characterId = characterId, name = name, number = number, balance = Bank.Balance(characterId) or 0 }
end

-- Alles fuer die Startseite (Filiale, Automat, spaeter Handy): Konto, letzte Buchungen, Schulden in Kurzform
function Bank.Overview(characterId, recentCount)
    local account = Bank.Account(characterId)
    if not account then
        return nil
    end
    account.recent = Bank.Recent(characterId, recentCount or CFG.RecentCount)
    account.debts = Debts.Summary(characterId)
    return account
end

-- Buchungen anderer Scripts auf dem Bankkonto (Gehalt, Bonus, Kauf, Admin): in den Kontoauszug uebernehmen
Platform.OnEvent('core:moneyBooked', function(entry)
    if type(entry) ~= 'table' or entry.account ~= 'bank' or not tonumber(entry.characterId) or not tonumber(entry.amount) then
        return
    end
    if type(entry.data) == 'table' and entry.data[OWN] == true then
        return
    end
    local other = type(entry.other) == 'table' and entry.other or {}
    local kind = entry.kind == 'transfer_in' and 'transfer_in' or entry.kind == 'transfer_out' and 'transfer_out'
        or (tonumber(entry.amount) > 0 and 'credit' or 'debit')
    Platform.Async(function()
        while not Bank.Ready do
            Platform.Wait(100)
        end
        Bank.Record(tonumber(entry.characterId), { kind = kind, amount = math.floor(tonumber(entry.amount)), balance = math.floor(tonumber(entry.balance) or 0),
            text = Bank.Text(entry.reason, TEXT_MAX) or TEXT.booking, otherId = tonumber(other.characterId), otherName = Bank.Text(other.name, 101),
            channel = 'system' })
    end)
end)

------------------------------------------------------------------------
-- Einzahlen und Auszahlen (nur mit der Person am Schalter oder Automaten, wegen des Bargelds)
------------------------------------------------------------------------

local function ownData(extra)
    local data = extra or {}
    data[OWN] = true
    return data
end

-- So viel darf die Person in den naechsten 24 Stunden noch am Automaten abheben. nil = ohne Grenze.
function Bank.AtmRemaining(characterId)
    if ATM.DailyWithdraw <= 0 then
        return nil
    end
    local used = tonumber(DB.Scalar("SELECT COALESCE(SUM(-amount), 0) FROM bank_transactions WHERE character_id = ? AND kind IN ('withdraw', 'refund') AND channel = 'atm' AND created_at > NOW() - INTERVAL 24 HOUR",
        { characterId })) or 0
    return math.max(0, ATM.DailyWithdraw - used)
end

-- Bargeld aufs Konto. Gibt den neuen Kontostand oder nil und einen Fehlercode zurueck.
function Bank.Deposit(source, amount, channel)
    local characterId = Bank.CharacterOf(source)
    if not characterId then
        return nil, 'no_character'
    end
    local atm = channel == 'atm'
    if atm and not ATM.Deposit then
        return nil, 'not_here'
    end
    amount = Bank.Amount(amount, Config.Money.MaxAmount)
    if not amount then
        return nil, 'invalid_amount'
    end
    if atm and amount > ATM.DepositMax then
        return nil, 'over_limit'
    end
    local text = TEXT.deposit[atm and 'atm' or 'bank']
    local cash, cashError = Bank.Core('RemoveMoney', source, 'cash', amount, text, { data = ownData({ channel = channel }) })
    if not cash then
        cashError = Bank.Why(cashError, 'cash', source, amount)
        return nil, cashError == 'not_enough_money' and 'not_enough_cash' or cashError
    end
    local balance, bankError = Bank.Core('AddMoney', source, 'bank', amount, text, { data = ownData({ channel = channel }) })
    if not balance then
        Bank.Core('AddMoney', source, 'cash', amount, text .. ' (zurück)', { data = ownData() })
        return nil, bankError or 'server_error'
    end
    Bank.Record(characterId, { kind = 'deposit', amount = amount, balance = balance, text = text, channel = channel })
    return balance
end

-- Vom Konto in bar. Gibt den neuen Kontostand oder nil und einen Fehlercode zurueck.
function Bank.Withdraw(source, amount, channel)
    local characterId = Bank.CharacterOf(source)
    if not characterId then
        return nil, 'no_character'
    end
    local atm = channel == 'atm'
    amount = Bank.Amount(amount, Config.Money.MaxAmount)
    if not amount then
        return nil, 'invalid_amount'
    end
    if atm then
        if amount > ATM.WithdrawMax then
            return nil, 'over_limit'
        end
        local remaining = Bank.AtmRemaining(characterId)
        if remaining and amount > remaining then
            return nil, 'daily_limit'
        end
    end
    local text = TEXT.withdraw[atm and 'atm' or 'bank']
    local balance, bankError = Bank.Core('RemoveMoney', source, 'bank', amount, text, { data = ownData({ channel = channel }) })
    if not balance then
        return nil, Bank.Why(bankError, 'bank', characterId, amount)
    end
    Bank.Record(characterId, { kind = 'withdraw', amount = -amount, balance = balance, text = text, channel = channel })
    local cash, cashError = Bank.Core('AddMoney', source, 'cash', amount, text, { data = ownData({ channel = channel }) })
    if not cash then
        -- Kein Platz im Inventar: zurueck aufs Konto, damit nichts verloren geht
        local back = Bank.Core('AddMoney', source, 'bank', amount, TEXT.refund, { data = ownData() })
        if back then
            Bank.Record(characterId, { kind = 'refund', amount = amount, balance = back, text = TEXT.refund, channel = channel })
        else
            Platform.Print('error', ('core_bank: Auszahlung von %d an ID %d konnte nicht zurueckgebucht werden, bitte pruefen!'):format(amount, characterId))
        end
        -- Ohne Fehlercode ist es fast immer ein volles Inventar
        return nil, cashError or 'no_space'
    end
    return balance
end

------------------------------------------------------------------------
-- Ueberweisen (geht auch, wenn der Empfaenger offline ist)
------------------------------------------------------------------------

-- Gibt { balance, to = { name, number } } zurueck oder nil und einen Fehlercode.
-- info: { channel, actorAccountId }
function Bank.Transfer(fromCharacterId, toNumber, amount, purpose, info)
    info = type(info) == 'table' and info or {}
    fromCharacterId = tonumber(fromCharacterId)
    local fromNumber = fromCharacterId and Bank.NumberOf(fromCharacterId)
    if not fromNumber then
        return nil, 'no_character'
    end
    if not Bank.NormalizeNumber(toNumber) then
        return nil, 'invalid_number'
    end
    local target = Bank.Lookup(toNumber)
    if not target then
        return nil, 'unknown_account'
    end
    if target.characterId == fromCharacterId then
        return nil, 'same_account'
    end
    amount = Bank.Amount(amount, math.min(CFG.TransferMax, Config.Money.MaxAmount))
    if not amount then
        return nil, 'invalid_amount'
    end
    purpose = Bank.Text(purpose, CFG.PurposeMaxLength) or TEXT.transfer
    local channel = CHANNELS[info.channel] and info.channel or 'system'

    local fromBalance, err, toBalance = Bank.Core('TransferBankByCharacter', fromCharacterId, target.characterId, amount,
        ('Überweisung: %s'):format(purpose), { actorAccountId = info.actorAccountId, data = ownData({ channel = channel, purpose = purpose }) })
    if not fromBalance then
        return nil, Bank.Why(err, 'bank', fromCharacterId, amount)
    end

    local fromName = Bank.NameOf(fromCharacterId)
    Bank.Record(fromCharacterId, { kind = 'transfer_out', amount = -amount, balance = fromBalance, text = purpose,
        otherId = target.characterId, otherName = target.name, otherNumber = target.number, channel = channel })
    Bank.Record(target.characterId, { kind = 'transfer_in', amount = amount, balance = tonumber(toBalance) or Bank.Balance(target.characterId) or 0,
        text = purpose, otherId = fromCharacterId, otherName = fromName, otherNumber = fromNumber, channel = channel })
    Bank.Notify(target.characterId, ('Geldeingang: %s von %s. %s'):format(Bank.Money(amount), fromName or 'unbekannt', purpose), 'success')
    return { balance = fromBalance, to = { name = target.name, number = target.number } }
end

------------------------------------------------------------------------
-- Fuer andere Scripts (Handy, Shops, Organisationen)
------------------------------------------------------------------------

Platform.Export('GetAccount', Bank.Account)
Platform.Export('GetOverview', function(characterId, recentCount)
    characterId = tonumber(characterId)
    return characterId and Bank.Overview(characterId, tonumber(recentCount)) or nil
end)
Platform.Export('GetTransactions', function(characterId, options)
    characterId = tonumber(characterId)
    return characterId and Bank.Statement(characterId, options) or nil
end)
Platform.Export('GetRecipients', function(characterId)
    characterId = tonumber(characterId)
    return characterId and Bank.Recipients(characterId) or nil
end)
Platform.Export('LookupAccount', Bank.Lookup)
Platform.Export('Transfer', Bank.Transfer)
