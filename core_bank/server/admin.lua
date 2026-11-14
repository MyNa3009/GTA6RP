-- Admins sehen alles: /konto <ID> zeigt Konto, Kontoauszug und Schulden jeder Person, auch offline.
-- Geld bewegen geht in dieser Ansicht nicht, dafuer gibt es /givemoney und /removemoney der Core.
-- Mit dem Recht aus Admin.ManagePermission: Forderung eintragen (auch per /schuld) oder erlassen.
-- Jeder Blick in ein fremdes Konto und jede Aenderung wird geloggt.

if BankDisabled then
    return
end

local CFG = Config.Bank
local ADMIN = CFG.Admin
local REASON_MAX = 120

local function adminName(source)
    local characterId = Bank.CharacterOf(source)
    return ('Admin %s'):format(characterId and Bank.NameOf(characterId) or '')
end

-- Korrigieren nur im Admin-Dienst, wenn die Core das fuer Admin-Aktionen verlangt
local function canManage(source)
    if Bank.Core('HasPermission', source, ADMIN.ManagePermission) ~= true then
        return false
    end
    return not Config.Admin.RequireDutyForActions or Bank.Core('IsOnDuty', source) == true
end

function Bank.OpenAdmin(source, data)
    if Bank.Core('HasPermission', source, ADMIN.ViewPermission) ~= true then
        return nil, 'no_permission'
    end
    local subject = tonumber(data.characterId)
    if not subject or not Bank.Account(math.floor(subject)) then
        return nil, 'not_found'
    end
    subject = math.floor(subject)
    Bank.Log({ actor_account_id = Bank.Core('GetAccountId', source), character_id = subject, action = 'admin_view' })
    return { channel = 'admin', subject = subject, admin = true, canManage = canManage(source), name = adminName(source) }
end

local ADMIN_ONLY = { admin = true }

Bank.RegisterCall('bank_debt_add', { channels = ADMIN_ONLY, mutate = true }, function(source, data, session)
    if not canManage(source) then
        return { ok = false, error = 'no_permission' }
    end
    local id, err = Debts.Add(session.subject, { amount = data.amount, title = data.title, kind = data.kind, dueHours = data.dueHours,
        issuedById = Bank.CharacterOf(source), issuedBy = session.name, actorAccountId = Bank.Core('GetAccountId', source), data = { admin = true } })
    if not id then
        return { ok = false, error = err }
    end
    return { ok = true, data = { debt = Debts.Get(id), overview = Bank.View(source, session) } }
end)

Bank.RegisterCall('bank_debt_cancel', { channels = ADMIN_ONLY, mutate = true }, function(source, data, session)
    if not canManage(source) then
        return { ok = false, error = 'no_permission' }
    end
    local debt = Debts.Get(data.id)
    if not debt or debt.characterId ~= session.subject then
        return { ok = false, error = 'not_found' }
    end
    local fresh, err = Debts.Cancel(debt.id, { by = session.name, reason = Bank.Text(data.reason, REASON_MAX), actorAccountId = Bank.Core('GetAccountId', source) })
    if not fresh then
        return { ok = false, error = err }
    end
    return { ok = true, data = { debt = fresh, overview = Bank.View(source, session) } }
end)

-- /schuld <ID> <Betrag> <Grund>   Forderung des Staats eintragen (Strafe)
Platform.RegisterCommand('schuld', function(source, args)
    local allowed, accountId = Bank.Core('AuthorizeCommand', source, 'schuld', ADMIN.ManagePermission, args, true)
    if not allowed then
        return
    end
    local characterId, amount = tonumber(args[1]), tonumber(args[2])
    local title = Bank.Text(table.concat(args, ' ', 3), CFG.Debts.TitleMaxLength)
    if not characterId or not amount or not title then
        Platform.Notify(source, 'Benutzung: /schuld <ID> <Betrag> <Grund>, z. B. /schuld 17 500 Rotlicht überfahren', 'error')
        return
    end
    local id, err = Debts.Add(math.floor(characterId), { amount = amount, title = title, kind = 'fine',
        issuedById = source ~= 0 and Bank.CharacterOf(source) or nil, issuedBy = source ~= 0 and adminName(source) or 'Konsole',
        actorAccountId = accountId, data = { admin = true } })
    if not id then
        Platform.Notify(source, err == 'not_found' and 'Keinen Charakter mit dieser permanenten ID gefunden.'
            or err == 'invalid_amount' and ('Ungültiger Betrag. Erlaubt: 1 bis %d.'):format(CFG.Debts.MaxAmount)
            or ('Das hat nicht geklappt (%s).'):format(tostring(err)), 'error')
        return
    end
    Platform.Notify(source, ('Strafe Nr. %d über %s für ID %d eingetragen.'):format(id, Bank.Money(amount), math.floor(characterId)), 'success')
end)

-- In der Befehlsliste des Admin-Menues zeigen
DB.Ready(function()
    Bank.Core('AddCommandHelp', {
        title = 'Bank',
        entries = {
            { usage = ('/%s 17'):format(ADMIN.Command), text = 'Konto, Kontoauszug und Schulden von ID 17 ansehen, auch offline. Jeder Blick wird geloggt.', permission = ADMIN.ViewPermission },
            { usage = '/schuld 17 500 Rotlicht überfahren', text = 'Strafe des Staats eintragen. Erlassen geht in der Ansicht von /konto.', permission = ADMIN.ManagePermission },
        },
    })
end)
