-- Apps, die andere Scripts brauchen: Bank (core_bank) und Notruf (core_dispatch).
-- Das Handy ruft nur deren Exports auf. Betraege, Grenzen und Regeln prueft das jeweilige Script selbst.

if PhoneDisabled then
    return
end

local CFG = Config.Phone
local BANK = 'core_bank'
local DISPATCH = 'core_dispatch'

local function bank(name, ...)
    return Platform.CallExport(BANK, name, ...)
end

local function bankOn()
    return CFG.Bank.Enabled and Platform.IsResourceStarted(BANK)
end

-- Ganzer Betrag ab 1, sonst nil
local function amountOf(value)
    value = tonumber(value)
    if not value or value ~= value or value ~= math.floor(value) or value < 1 then
        return nil
    end
    return math.floor(value)
end

local function overview(characterId)
    local data = bank('GetOverview', characterId, CFG.Bank.RecentCount)
    if type(data) ~= 'table' then
        return nil
    end
    data.recipients = bank('GetRecipients', characterId) or {}
    return data
end

------------------------------------------------------------------------
-- Bank
------------------------------------------------------------------------

Phone.Register('phone_bank', {}, function(source, data, ctx)
    local result = not ctx.admin and bankOn() and overview(ctx.characterId)
    if not result then
        return { ok = false, error = 'no_bank' }
    end
    return { ok = true, data = { overview = result } }
end)

-- Empfaenger pruefen, bevor ueberwiesen wird
Phone.Register('phone_bank_lookup', {}, function(source, data, ctx)
    if ctx.admin or not bankOn() then
        return { ok = false, error = 'no_bank' }
    end
    local target = bank('LookupAccount', data.number)
    if type(target) ~= 'table' then
        return { ok = false, error = 'unknown_account' }
    end
    if target.characterId == ctx.characterId then
        return { ok = false, error = 'same_account' }
    end
    return { ok = true, data = { name = target.name, number = target.number } }
end)

Phone.Register('phone_bank_transfer', { write = true }, function(source, data, ctx)
    if not bankOn() then
        return { ok = false, error = 'no_bank' }
    end
    local amount = amountOf(data.amount)
    if not amount then
        return { ok = false, error = 'invalid_amount' }
    end
    local target = bank('LookupAccount', data.number)
    if type(target) ~= 'table' then
        return { ok = false, error = 'unknown_account' }
    end
    if target.characterId == ctx.characterId then
        return { ok = false, error = 'same_account' }
    end
    local account = bank('GetAccount', ctx.characterId)
    if type(account) ~= 'table' then
        return { ok = false, error = 'no_bank' }
    end
    if account.balance < amount then
        return { ok = false, error = 'not_enough_money' }
    end
    local result, err = bank('Transfer', ctx.characterId, target.number, amount, data.purpose,
        { channel = 'phone', actorAccountId = Phone.Core('GetAccountId', source) })
    if type(result) ~= 'table' then
        return { ok = false, error = type(err) == 'string' and err or 'server_error' }
    end
    return { ok = true, data = { to = result.to, overview = overview(ctx.characterId) } }
end)

Phone.Register('phone_bank_debts', {}, function(source, data, ctx)
    local result = not ctx.admin and bankOn() and bank('GetDebts', ctx.characterId, { status = 'open' })
    if type(result) ~= 'table' then
        return { ok = false, error = 'no_bank' }
    end
    return { ok = true, data = { debts = result.debts or {} } }
end)

-- data: { id, amount? } (ohne Betrag der ganze Rest)
Phone.Register('phone_bank_pay', { write = true }, function(source, data, ctx)
    if not bankOn() then
        return { ok = false, error = 'no_bank' }
    end
    local debt = bank('GetDebt', data.id)
    if type(debt) ~= 'table' or debt.characterId ~= ctx.characterId then
        return { ok = false, error = 'not_found' }
    end
    if debt.status ~= 'open' then
        return { ok = false, error = 'debt_closed' }
    end
    local amount = data.amount == nil and debt.rest or amountOf(data.amount)
    if not amount or amount > debt.rest then
        return { ok = false, error = 'invalid_amount' }
    end
    local account = bank('GetAccount', ctx.characterId)
    if type(account) ~= 'table' then
        return { ok = false, error = 'no_bank' }
    end
    if account.balance < amount then
        return { ok = false, error = 'not_enough_money' }
    end
    local result, err = bank('PayDebt', ctx.characterId, debt.id, amount, { channel = 'phone', actorAccountId = Phone.Core('GetAccountId', source) })
    if type(result) ~= 'table' then
        return { ok = false, error = type(err) == 'string' and err or 'server_error' }
    end
    local open = bank('GetDebts', ctx.characterId, { status = 'open' })
    return { ok = true, data = { debt = result.debt, paid = result.paid, debts = type(open) == 'table' and open.debts or {}, overview = overview(ctx.characterId) } }
end)

------------------------------------------------------------------------
-- Notruf
------------------------------------------------------------------------

local function dispatchOn()
    return CFG.Dispatch.Enabled and Platform.IsResourceStarted(DISPATCH)
end

Phone.Register('phone_dispatch', {}, function(source, data, ctx)
    local info = not ctx.admin and dispatchOn() and Platform.CallExport(DISPATCH, 'GetServices')
    if type(info) ~= 'table' then
        return { ok = false, error = 'no_dispatch' }
    end
    return { ok = true, data = info }
end)

-- data: { service, text }. Die Leitstelle prueft Text, Wartezeit und Sperren und nimmt die Position selbst.
Phone.Register('phone_dispatch_send', { write = true }, function(source, data)
    if not dispatchOn() then
        return { ok = false, error = 'no_dispatch' }
    end
    local result = Platform.CallExport(DISPATCH, 'SendCallFrom', source, { service = data.service, text = data.text })
    if type(result) ~= 'table' then
        return { ok = false, error = 'server_error' }
    end
    return result
end)
