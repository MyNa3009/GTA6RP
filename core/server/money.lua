-- Geld: Bargeld und Bank.
-- Regeln:
--   1. Kein Script aendert Geld direkt in der Datenbank, alles laeuft ueber Core.*Money.
--   2. Jede Buchung wird mit Kontostand vorher und nachher geloggt.
--   3. Abbuchen klappt nur, wenn genug da ist (bedingtes UPDATE), und pro Charakter
--      laeuft immer nur eine Buchung gleichzeitig. So kann nichts doppelt oder ins Minus gehen.

Money = {}

local ACCOUNTS = { cash = 'cash', bank = 'bank' } -- erlaubte Konten = Spaltennamen
local LOCK_WAIT_MS = 10
local UPDATE_EVENT = 'core:money:update'
local DEBUG = Platform.GetConvar('core_debug', 'false') == 'true'

local locks = {}
local transferCounter = 0

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------

-- Gibt einen ganzen, positiven Betrag zurueck oder nil
local function normalizeAmount(amount)
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount == math.huge then
        return nil
    end
    amount = math.floor(amount)
    if amount <= 0 or amount > Config.Money.MaxAmount then
        return nil
    end
    return amount
end

-- Fuehrt fn aus, waehrend die Charaktere gesperrt sind (immer in gleicher Reihenfolge, damit sich nichts blockiert)
local function withLocks(characterIds, fn)
    local ids = {}
    for _, id in ipairs(characterIds) do
        ids[#ids + 1] = id
    end
    table.sort(ids)

    for _, id in ipairs(ids) do
        while locks[id] do
            Platform.Wait(LOCK_WAIT_MS)
        end
        locks[id] = true
    end

    local ok, result, err = pcall(fn)

    for _, id in ipairs(ids) do
        locks[id] = nil
    end

    if not ok then
        Platform.Print('error', ('Fehler bei einer Geldbuchung: %s'):format(tostring(result)))
        return nil, 'server_error'
    end
    return result, err
end

------------------------------------------------------------------------
-- Bargeld im Inventar: laeuft core_inventory, liegt das Bargeld dort als Item "cash"
------------------------------------------------------------------------

local CASH_ITEM = 'cash'

local function cashInventory()
    local resource = Config.Money.CashInventory
    if resource and Platform.IsResourceStarted(resource) then
        return resource
    end
    return nil
end

local function characterExists(characterId)
    return DB.Scalar('SELECT id FROM characters WHERE id = ? AND deleted_at IS NULL', { characterId }) ~= nil
end

local function inventoryCash(resource, characterId)
    return tonumber(Platform.CallExport(resource, 'GetItemCount', characterId, CASH_ITEM))
end

local function applyInventoryCash(resource, characterId, delta)
    if not characterExists(characterId) then
        return nil, 'not_found'
    end
    local ok, err
    if delta > 0 then
        ok, err = Platform.CallExport(resource, 'AddItem', characterId, CASH_ITEM, delta)
        if not ok then
            return nil, (err == 'too_heavy' or err == 'no_space') and 'no_space' or 'db_error'
        end
    else
        ok = Platform.CallExport(resource, 'RemoveItem', characterId, CASH_ITEM, -delta)
        if not ok then
            return nil, 'not_enough_money'
        end
    end
    local balance = inventoryCash(resource, characterId)
    if balance == nil then
        return nil, 'db_error'
    end
    return balance
end

local function readBalance(characterId, column)
    local resource = column == 'cash' and cashInventory()
    if resource then
        return inventoryCash(resource, characterId)
    end
    return DB.Scalar(
        ('SELECT %s FROM characters WHERE id = ? AND deleted_at IS NULL'):format(column),
        { characterId }
    )
end

-- delta > 0 bucht dazu, delta < 0 bucht ab (nur wenn genug da ist). Gibt den neuen Kontostand zurueck.
local function applyDelta(characterId, column, delta)
    local resource = column == 'cash' and cashInventory()
    if resource then
        return applyInventoryCash(resource, characterId, delta)
    end
    local changed
    if delta > 0 then
        changed = DB.Update(
            ('UPDATE characters SET %s = %s + ? WHERE id = ? AND deleted_at IS NULL'):format(column, column),
            { delta, characterId }
        )
    else
        changed = DB.Update(
            ('UPDATE characters SET %s = %s - ? WHERE id = ? AND deleted_at IS NULL AND %s >= ?'):format(column, column, column),
            { -delta, characterId, -delta }
        )
    end

    if changed == nil then
        return nil, 'db_error'
    end
    if changed == 0 then
        if delta < 0 and readBalance(characterId, column) ~= nil then
            return nil, 'not_enough_money'
        end
        return nil, 'not_found'
    end

    local balance = readBalance(characterId, column)
    if balance == nil then
        return nil, 'db_error'
    end
    return balance
end

local function findOnlineByCharacter(characterId)
    for _, player in pairs(Core.Players) do
        if player.characterId == characterId then
            return player
        end
    end
    return nil
end

-- Haelt den Zwischenspeicher am Spieler aktuell und schickt die Anzeige an den Client
local function sync(characterId, column, balance, delta)
    local player = findOnlineByCharacter(characterId)
    if not player or not player.character then
        return
    end
    -- Bargeld im Inventar: das Inventar hat die Anzeige schon ueber SyncCash aktualisiert
    if player.character.money[column] == balance then
        return
    end
    player.character.money[column] = balance
    Network.SendToClient(player.source, UPDATE_EVENT, {
        cash = player.character.money.cash,
        bank = player.character.money.bank,
        changed = { account = column, amount = delta },
    })
end

local function accountOf(characterId)
    return DB.Scalar('SELECT account_id FROM characters WHERE id = ?', { characterId })
end

local function nameOf(characterId)
    local row = DB.Single('SELECT firstname, lastname FROM characters WHERE id = ?', { characterId })
    return row and ('%s %s'):format(row.firstname, row.lastname) or nil
end

------------------------------------------------------------------------
-- Buchungen ueber die Charakter-ID (funktioniert auch offline)
------------------------------------------------------------------------

-- options: { actorAccountId?, data? }
local function book(characterId, account, delta, reason, options)
    local column = ACCOUNTS[account]
    if not column then
        return nil, 'invalid_account'
    end
    options = options or {}

    local balance, err = withLocks({ characterId }, function()
        return applyDelta(characterId, column, delta)
    end)
    if not balance then
        return nil, err
    end

    local data = options.data or {}
    data.account = column

    Core.Log({
        actor_account_id = options.actorAccountId,
        account_id = accountOf(characterId),
        character_id = characterId,
        category = 'money',
        action = delta > 0 and 'add' or 'remove',
        amount = math.abs(delta),
        balance_before = balance - delta,
        balance_after = balance,
        reason = reason,
        data = data,
    })

    sync(characterId, column, balance, delta)
    return balance
end

function Money.AddByCharacter(characterId, account, amount, reason, options)
    amount = normalizeAmount(amount)
    if not amount then
        return nil, 'invalid_amount'
    end
    return book(characterId, account, amount, reason, options)
end

function Money.RemoveByCharacter(characterId, account, amount, reason, options)
    amount = normalizeAmount(amount)
    if not amount then
        return nil, 'invalid_amount'
    end
    return book(characterId, account, -amount, reason, options)
end

function Money.TransferByCharacter(fromCharacterId, toCharacterId, account, amount, reason, options)
    local column = ACCOUNTS[account]
    if not column then
        return nil, 'invalid_account'
    end
    amount = normalizeAmount(amount)
    if not amount then
        return nil, 'invalid_amount'
    end
    if fromCharacterId == toCharacterId then
        return nil, 'same_character'
    end
    options = options or {}

    -- Twinks (Charaktere derselben Person): je nach Config blockieren oder nach der Buchung melden
    local twinkBlock = Twinks.Mode('money_transfer') == 'block'
    if twinkBlock and not Twinks.Check(fromCharacterId, toCharacterId, 'money_transfer', { amount = amount, account = column }) then
        return nil, 'twink_blocked'
    end

    transferCounter = transferCounter + 1
    local transferId = ('%d-%d'):format(os.time(), transferCounter)

    local result, err = withLocks({ fromCharacterId, toCharacterId }, function()
        local fromBalance, removeError = applyDelta(fromCharacterId, column, -amount)
        if not fromBalance then
            return nil, removeError
        end

        local toBalance, addError = applyDelta(toCharacterId, column, amount)
        if not toBalance then
            -- Empfaenger gibt es nicht oder Datenbankfehler: Geld zurueckbuchen
            local refunded = applyDelta(fromCharacterId, column, amount)
            if not refunded then
                Platform.Print('error', ('Ueberweisung %s: Rueckbuchung fehlgeschlagen, bitte pruefen!'):format(transferId))
            end
            Core.Log({
                actor_account_id = options.actorAccountId,
                character_id = fromCharacterId,
                category = 'money',
                action = 'transfer_failed',
                amount = amount,
                reason = reason,
                data = { account = column, transferId = transferId, toCharacterId = toCharacterId, refunded = refunded ~= nil, error = addError },
            })
            return nil, addError
        end

        return { from = fromBalance, to = toBalance }
    end)

    if not result then
        return nil, err
    end

    local fromAccount = accountOf(fromCharacterId)
    local toAccount = accountOf(toCharacterId)
    local fromName = nameOf(fromCharacterId)
    local toName = nameOf(toCharacterId)

    Core.Log({
        actor_account_id = options.actorAccountId,
        account_id = fromAccount,
        character_id = fromCharacterId,
        target_account_id = toAccount,
        category = 'money',
        action = 'transfer_out',
        amount = amount,
        balance_before = result.from + amount,
        balance_after = result.from,
        reason = reason,
        data = { account = column, transferId = transferId, toCharacterId = toCharacterId, toName = toName },
    })
    Core.Log({
        actor_account_id = options.actorAccountId,
        account_id = toAccount,
        character_id = toCharacterId,
        target_account_id = fromAccount,
        category = 'money',
        action = 'transfer_in',
        amount = amount,
        balance_before = result.to - amount,
        balance_after = result.to,
        reason = reason,
        data = { account = column, transferId = transferId, fromCharacterId = fromCharacterId, fromName = fromName },
    })

    sync(fromCharacterId, column, result.from, -amount)
    sync(toCharacterId, column, result.to, amount)
    if not twinkBlock then
        Twinks.Check(fromCharacterId, toCharacterId, 'money_transfer', { amount = amount, account = column, transferId = transferId, reason = reason })
    end
    return result.from
end

------------------------------------------------------------------------
-- Oeffentliche API ueber die Server-ID (Spieler muss einen Charakter spielen)
------------------------------------------------------------------------

local function characterIdOf(source)
    local player = Core.GetPlayer(source)
    return player and player.characterId or nil
end

-- Gibt den Kontostand zurueck oder nil
function Core.GetMoney(source, account)
    local character = Core.GetCharacter(source)
    local column = ACCOUNTS[account]
    if not character or not column then
        return nil
    end
    return character.money[column]
end

-- Alle geben bei Erfolg den neuen Kontostand zurueck, sonst nil und einen Fehlercode
function Core.AddMoney(source, account, amount, reason, options)
    local characterId = characterIdOf(source)
    if not characterId then
        return nil, 'no_character'
    end
    return Money.AddByCharacter(characterId, account, amount, reason, options)
end

function Core.RemoveMoney(source, account, amount, reason, options)
    local characterId = characterIdOf(source)
    if not characterId then
        return nil, 'no_character'
    end
    return Money.RemoveByCharacter(characterId, account, amount, reason, options)
end

function Core.TransferMoney(fromSource, toSource, account, amount, reason, options)
    local fromId = characterIdOf(fromSource)
    local toId = characterIdOf(toSource)
    if not fromId or not toId then
        return nil, 'no_character'
    end
    return Money.TransferByCharacter(fromId, toId, account, amount, reason, options)
end

-- Bargeld beim Laden des Charakters: aus dem Inventar, sonst aus der Spalte
function Money.CashOnSelect(characterId, columnCash)
    local resource = cashInventory()
    if resource then
        return inventoryCash(resource, characterId) or 0
    end
    return columnCash
end

-- Das Inventar meldet, dass sich das Bargeld geaendert hat (Geben, Ablegen, Aufheben)
Platform.Export('SyncCash', function(source, balance)
    local player = Core.GetPlayer(tonumber(source))
    balance = tonumber(balance)
    if not player or not player.character or not balance then
        return
    end
    local before = player.character.money.cash or 0
    if before == balance then
        return
    end
    player.character.money.cash = balance
    Network.SendToClient(player.source, UPDATE_EVENT, {
        cash = balance,
        bank = player.character.money.bank,
        changed = { account = 'cash', amount = balance - before },
    })
end)

-- Umzug: Bargeld aus der alten Spalte ins Inventar (macht core_inventory beim Einloggen)
Platform.Export('GetLegacyCash', function(characterId)
    return tonumber(DB.Scalar('SELECT cash FROM characters WHERE id = ? AND deleted_at IS NULL', { characterId })) or 0
end)

Platform.Export('ClearLegacyCash', function(characterId, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return false
    end
    local changed = DB.Update('UPDATE characters SET cash = cash - ? WHERE id = ? AND cash >= ?', { amount, characterId, amount })
    return changed ~= nil and changed > 0
end)

Platform.Export('GetMoney', Core.GetMoney)
Platform.Export('AddMoney', Core.AddMoney)
Platform.Export('RemoveMoney', Core.RemoveMoney)
Platform.Export('TransferMoney', Core.TransferMoney)

------------------------------------------------------------------------
-- Befehle
------------------------------------------------------------------------

local ACCOUNT_ALIASES = { bar = 'cash', bargeld = 'cash', cash = 'cash', bank = 'bank' }

local ERROR_TEXT = {
    invalid_amount = ('Ungültiger Betrag. Erlaubt: 1 bis %d.'):format(Config.Money.MaxAmount),
    invalid_account = 'Konto muss "cash" oder "bank" sein.',
    not_enough_money = 'Nicht genug Geld.',
    no_space = 'Im Inventar ist kein Platz für Bargeld.',
    no_character = 'Der Spieler spielt gerade keinen Charakter.',
    not_found = 'Keinen Charakter mit dieser permanenten ID gefunden.',
    same_character = 'Du kannst dir nicht selbst Geld schicken.',
    twink_blocked = 'Geld zwischen deinen eigenen Charakteren ist nicht erlaubt.',
    db_error = 'Datenbankfehler, siehe Serverkonsole.',
    server_error = 'Serverfehler, siehe Serverkonsole.',
}

local function errorText(err)
    return ERROR_TEXT[err] or tostring(err)
end

local function formatMoney(value)
    local text = tostring(math.floor(value or 0))
    local formatted = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (formatted:gsub('^%.', '')) .. ' $'
end

-- /geld (fuer alle)
Platform.RegisterCommand('geld', function(source)
    local cash, bank = Core.GetMoney(source, 'cash'), Core.GetMoney(source, 'bank')
    if not cash then
        Platform.Notify(source, errorText('no_character'), 'error')
        return
    end
    Platform.Notify(source, ('Bargeld: %s, Bank: %s'):format(formatMoney(cash), formatMoney(bank)), 'info')
end)

-- /givemoney <cash|bank> <permanente ID> <betrag>     z. B. /givemoney bank 17 2500
-- /removemoney <cash|bank> <permanente ID> <betrag>   (Recht money.manage, geht auch, wenn die ID offline ist)
local function adminBooking(source, args, actorAccountId, fn, command)
    local account = ACCOUNT_ALIASES[(args[1] or ''):lower()]
    local characterId = tonumber(args[2])
    if not account or not characterId or not args[3] then
        Platform.Notify(source, ('Benutzung: /%s <cash|bank> <permanente ID> <betrag>, z. B. /%s bank 17 2500'):format(command, command), 'info')
        return
    end
    local balance, err = fn(characterId, account, args[3], ('Admin-Befehl /%s'):format(command), { actorAccountId = actorAccountId })
    if not balance then
        Platform.Notify(source, errorText(err), 'error')
        return
    end
    Platform.Notify(source, ('Neuer Kontostand (%s) von ID %d: %s'):format(account, characterId, formatMoney(balance)), 'success')
end

Core.RegisterAdminCommand('givemoney', 'money.manage', function(source, args, actorAccountId)
    adminBooking(source, args, actorAccountId, Money.AddByCharacter, 'givemoney')
end, { requireDuty = true })

Core.RegisterAdminCommand('removemoney', 'money.manage', function(source, args, actorAccountId)
    adminBooking(source, args, actorAccountId, Money.RemoveByCharacter, 'removemoney')
end, { requireDuty = true })

-- Ab hier nur Testbefehle. Spaeter laufen Ueberweisungen ueber Bank oder Handy.
if not DEBUG then
    return
end

-- /ueberweisen 17 250   (Bank an ID 17)     /geben 17 50   (Bargeld an ID 17)
local function playerTransfer(source, args, account, verb)
    if source == 0 or not tonumber(args[1]) then
        Platform.Notify(source, ('Benutzung: /%s <permanente ID> <Betrag>'):format(verb), 'info')
        return
    end
    local target, targetError = Core.ResolveTarget(source, args[1])
    if not target then
        Platform.Notify(source, targetError, 'error')
        return
    end
    local actor = Core.GetPlayer(source)
    local balance, err = Core.TransferMoney(source, target, account, args[2], ('Testbefehl /%s'):format(verb), { actorAccountId = actor and actor.accountId })
    if not balance then
        Platform.Notify(source, errorText(err), 'error')
        return
    end
    Platform.Notify(source, ('Gesendet. Dein neuer Kontostand: %s'):format(formatMoney(balance)), 'success')
end

Platform.RegisterCommand('ueberweisen', function(source, args)
    playerTransfer(source, args, 'bank', 'ueberweisen')
end)

Platform.RegisterCommand('geben', function(source, args)
    playerTransfer(source, args, 'cash', 'geben')
end)
