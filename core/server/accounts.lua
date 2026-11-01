-- Accounts und permanente IDs.
-- Die ID gehoert dem Account in der Datenbank. Plattform-Identifier werden nur verknuepft.

Core = Core or {}
Accounts = {}

local EMAIL_PATTERN = '^[%w%._%+%-]+@[%w%.%-]+%.%a%a+$'

local function normalizeEmail(email)
    return (email or ''):lower():match('^%s*(.-)%s*$')
end

function Accounts.FindByIdentifiers(identifiers)
    local clauses, params = {}, {}

    for idType, value in pairs(identifiers) do
        clauses[#clauses + 1] = '(type = ? AND value = ?)'
        params[#params + 1] = idType
        params[#params + 1] = value
    end

    if #clauses == 0 then
        return nil
    end

    local sql = 'SELECT account_id FROM account_identifiers WHERE '
        .. table.concat(clauses, ' OR ')
        .. ' ORDER BY first_seen ASC LIMIT 1'

    local row = DB.Single(sql, params)
    return row and row.account_id or nil
end

function Accounts.LinkIdentifiers(accountId, identifiers)
    for idType, value in pairs(identifiers) do
        local owner = DB.Scalar(
            'SELECT account_id FROM account_identifiers WHERE type = ? AND value = ?',
            { idType, value }
        )

        if owner == nil then
            DB.Insert(
                'INSERT INTO account_identifiers (account_id, type, value) VALUES (?, ?, ?)',
                { accountId, idType, value }
            )
        elseif owner == accountId then
            DB.Update(
                'UPDATE account_identifiers SET last_seen = CURRENT_TIMESTAMP WHERE type = ? AND value = ?',
                { idType, value }
            )
        else
            -- Gleicher Identifier, anderer Account: moeglicher Multi-Account
            Core.Log({
                account_id = accountId,
                target_account_id = owner,
                category = 'security',
                action = 'identifier_conflict',
                data = { type = idType },
            })
            MultiAccount.Record(accountId, owner, idType)
        end
    end
end

function Accounts.Register(source, email, password)
    email = normalizeEmail(email)
    password = password or ''

    if #email > Config.Accounts.EmailMaxLength or not email:match(EMAIL_PATTERN) then
        return nil, 'invalid_email'
    end
    if #password < Config.Accounts.PasswordMinLength then
        return nil, 'password_too_short'
    end
    if #password > Config.Accounts.PasswordMaxLength then
        return nil, 'password_too_long'
    end

    local identifiers = Identity.GetAll(source)
    local existing = Accounts.FindByIdentifiers(identifiers)
    if Config.Accounts.OneAccountPerDevice and existing then
        Core.Log({
            account_id = existing,
            category = 'security',
            action = 'register_blocked',
            data = { email = email },
        })
        return nil, 'already_registered'
    end

    if DB.Scalar('SELECT id FROM accounts WHERE email = ?', { email }) then
        return nil, 'email_taken'
    end

    local accountId = DB.Insert(
        'INSERT INTO accounts (email, password_hash, last_login_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
        { email, Platform.HashPassword(password) }
    )
    if not accountId then
        return nil, 'db_error'
    end

    Accounts.LinkIdentifiers(accountId, identifiers)
    Devices.OnLogin(source, accountId)

    Core.Log({
        actor_account_id = accountId,
        account_id = accountId,
        category = 'account',
        action = 'register',
    })

    return accountId
end

function Accounts.GetEmail(accountId)
    return DB.Scalar('SELECT email FROM accounts WHERE id = ?', { accountId })
end

-- Zeigt nur einen Teil der Adresse, z. B. 'fa•••@gmail.com'
function Accounts.GetEmailHint(accountId)
    local email = DB.Scalar('SELECT email FROM accounts WHERE id = ?', { accountId })
    if not email then
        return nil
    end
    local localPart, domain = email:match('^(.-)@(.+)$')
    if not localPart then
        return nil
    end
    return localPart:sub(1, 2) .. '•••@' .. domain
end

function Accounts.Login(source, email, password)
    email = normalizeEmail(email)
    password = password or ''

    if #password == 0 or #password > Config.Accounts.PasswordMaxLength then
        return nil, 'wrong_credentials'
    end

    local row = DB.Single('SELECT id, password_hash FROM accounts WHERE email = ?', { email })

    if not row or not Platform.VerifyPassword(password, row.password_hash) then
        Core.Log({
            account_id = row and row.id or nil,
            category = 'account',
            action = 'login_failed',
            data = { email = email },
        })
        return nil, 'wrong_credentials'
    end

    -- Gebannt: auch wenn das Geraet nicht zum Account gehoert (dann greift die Pruefung beim Verbinden nicht)
    local ban = Bans.ActiveForAccount(row.id)
    if ban then
        Accounts.LinkIdentifiers(row.id, Identity.GetAll(source))
        Devices.Remember(source, row.id)
        Core.Log({
            account_id = row.id,
            category = 'security',
            action = 'login_banned',
            data = { banId = ban.id },
        })
        return nil, 'banned', ban
    end

    DB.Update('UPDATE accounts SET last_login_at = CURRENT_TIMESTAMP WHERE id = ?', { row.id })
    Accounts.LinkIdentifiers(row.id, Identity.GetAll(source))
    Devices.OnLogin(source, row.id)

    Core.Log({
        actor_account_id = row.id,
        account_id = row.id,
        category = 'account',
        action = 'login',
    })

    return row.id
end
