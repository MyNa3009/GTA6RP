-- Organisationsmenue und Aktionen am Ziel aus dem G-Menue. Jede Anfrage prueft Rechte und Werte neu.
--   Uebersicht: Leader, eigener Rang, Daten, Nachricht vom Leader, Mitgliederzahlen, Divisionen, Kasse (mit Recht)
--   Divisionen: Ranggruppen (Highcommand, Command ...) mit ihren Mitgliedern, anlegen nur Leader und Vice
--   Erklaerungen: Pruefungen, Raenge mit Aufgaben und Rechten, Regeln, Ablaeufe. Bearbeiten nur Leader und Vice
--   Anpassung: Rangnamen, Rechte, Gehalt und Aufgaben pro Rang, Abteilungen, Pruefungen (nur Vice Leader und Leader)
--   Fahrzeuge ab Rang (nur Vice Leader und Leader)
--   Leitstelle: alle Mitarbeiter, Bearbeiten nach Rechten, Bonus (Leader und Vice)
--   Archiv: ehemalige Mitarbeiter
-- Admins oeffnen mit /orgaview jede Organisation: factions.view nur lesen, factions.manage wie der Leader.

if FactionsDisabled then
    return
end

FactionMenu = {}

local CFG = Config.Factions
local TARGET_DISTANCE = 5.0

local adminView = {}   -- [source] = { faction, manage }, solange ein Admin eine fremde Organisation offen hat

------------------------------------------------------------------------
-- Wer schaut gerade (Mitglied oder Admin)
------------------------------------------------------------------------

-- ctx: { faction, org, rank, characterId, name, accountId, source, admin, manage, readOnly }
local function context(source)
    local view = adminView[source]
    if view then
        local org = Orgs[view.faction]
        return {
            faction = view.faction, org = org, rank = view.manage and org.leaderRank or 0,
            characterId = Factions.CharacterOf(source), name = ('Admin %s'):format(Factions.NameOf(source) or ''),
            accountId = Factions.AccountOf(source), source = source, admin = true, manage = view.manage, readOnly = not view.manage,
        }
    end
    local member = Factions.MemberOf(source)
    if not member then
        return nil
    end
    return {
        faction = member.faction, org = Orgs[member.faction], rank = member.rank, characterId = member.characterId,
        name = member.name, accountId = Factions.AccountOf(source), source = source, member = member,
    }
end

local function can(ctx, key)
    if ctx.admin then
        return ctx.manage or key:match('%.view$') ~= nil
    end
    return Factions.RankHas(ctx.faction, ctx.rank, key)
end

-- Vice Leader und Leader: Tab 2 und Tab 3
local function canStructure(ctx)
    if ctx.admin then
        return ctx.manage
    end
    return ctx.rank >= ctx.org.viceRank
end

-- Darf ctx an diesem Mitglied etwas aendern? Nur an niedrigeren Raengen (Admins mit manage immer).
local function above(ctx, member)
    if ctx.admin then
        return ctx.manage
    end
    return member.rank < ctx.rank
end

-- Eintrag im Protokoll der Organisation, ctx ist der Handelnde (Mitglied oder Admin)
local function protocol(ctx, area, action, text, target, targetName)
    Factions.Protocol(ctx.faction, { area = area, action = action, text = text, target = target, targetName = targetName,
        actor = { source = ctx.source, characterId = ctx.characterId, name = ctx.name, admin = ctx.admin } })
end

local function register(name, handler)
    Network.RegisterCallback(name, function(source, data)
        if not Factions.Ready or not Factions.CharacterOf(source) then
            return { ok = false, error = 'no_character' }
        end
        if type(data) ~= 'table' then
            data = {}
        end
        local ok, result = pcall(handler, source, data)
        if not ok then
            Platform.Print('error', ('core_factions: Fehler in %s: %s'):format(name, tostring(result)))
            return { ok = false, error = 'server_error' }
        end
        return result
    end)
end

local function withContext(name, handler)
    register(name, function(source, data)
        local ctx = context(source)
        if not ctx then
            return { ok = false, error = 'not_member' }
        end
        return handler(source, ctx, data)
    end)
end

function FactionMenu.OpenAsAdmin(source, faction, manage)
    adminView[source] = { faction = faction, manage = manage == true }
end

function FactionMenu.Forget(source)
    adminView[source] = nil
end

------------------------------------------------------------------------
-- Tab 1: Uebersicht
------------------------------------------------------------------------

local function settings(faction)
    return DB.Single("SELECT message, message_by, DATE_FORMAT(message_at, '%Y-%m-%d %H:%i') AS message_at, balance FROM faction_settings WHERE faction = ?", { faction }) or {}
end

-- Wer gerade im Dienst ist (hoechster Rang zuerst)
local function onDutyList(faction)
    local list = {}
    for _, source in ipairs(Factions.OnDutyList(faction)) do
        local member = Factions.MemberOf(source)
        if member then
            list[#list + 1] = { name = member.name, dn = member.dn, rank = member.rank, rankName = Factions.RankName(faction, member.rank) }
        end
    end
    table.sort(list, function(a, b) return a.rank > b.rank end)
    return list
end

-- Divisionen mit Anzahl Mitglieder und wie viele davon im Dienst sind
local function divisionSummary(faction, counts, duty)
    local list = {}
    for _, division in ipairs(Members.Divisions(faction)) do
        local count, onDuty = 0, 0
        for rank = division.minRank, division.maxRank do
            count = count + (counts[rank] or 0)
        end
        for _, entry in ipairs(duty) do
            if entry.rank >= division.minRank and entry.rank <= division.maxRank then
                onDuty = onDuty + 1
            end
        end
        list[#list + 1] = { id = division.id, name = division.name, minRank = division.minRank, maxRank = division.maxRank,
            minRankName = Factions.RankName(faction, division.minRank), maxRankName = Factions.RankName(faction, division.maxRank),
            count = count, onDuty = onDuty }
    end
    return list
end

local function overview(ctx)
    local row = settings(ctx.faction)
    local member = ctx.member
    local counts, total = Members.CountByRank(ctx.faction)
    local duty = onDutyList(ctx.faction)
    local lastPromotion = member and Members.PromotedSinceHire(Members.LastPromotions(ctx.faction)[member.characterId], member.hiredAt) or nil
    return {
        org = { id = ctx.faction, label = ctx.org.label, short = ctx.org.short, ranks = ctx.org.ranks,
            leaderRank = ctx.org.leaderRank, viceRank = ctx.org.viceRank, logo = ctx.org.logo, theme = ctx.org.theme },
        me = {
            name = member and member.name or ctx.name,
            rank = member and member.rank or nil,
            rankName = member and Factions.RankName(ctx.faction, member.rank) or nil,
            dn = member and member.dn or nil,
            hiredAt = member and member.hiredAt or nil,
            lastPromotedAt = lastPromotion,
            salary = member and Factions.RankSalary(ctx.faction, member.rank) or nil,
            admin = ctx.admin or nil,
            readOnly = ctx.readOnly or nil,
        },
        salaryInterval = CFG.Salary.IntervalMinutes,
        leader = Members.LeaderName(ctx.faction),
        message = row.message and { text = row.message, by = row.message_by, at = row.message_at } or nil,
        balance = can(ctx, 'cash.view') and tonumber(row.balance) or nil,
        onDuty = duty,
        counts = { members = total, onDuty = #duty },
        divisions = divisionSummary(ctx.faction, counts, duty),
        access = {
            structure = canStructure(ctx),
            leitstelle = can(ctx, 'leitstelle.view'),
            archive = can(ctx, 'archive.view'),
            message = can(ctx, 'message.edit'),
            cash = can(ctx, 'cash.manage'),
            divisions = can(ctx, 'leitstelle.view'),
            info = true,
            logs = can(ctx, 'logs.view'),
        },
    }
end

register('faction_menu_open', function(source, data)
    -- Normales Oeffnen beendet eine Admin-Ansicht
    if not data.admin then
        adminView[source] = nil
    end
    local ctx = context(source)
    if not ctx then
        return { ok = false, error = 'not_member' }
    end
    return { ok = true, data = overview(ctx) }
end)

register('faction_menu_close', function(source)
    adminView[source] = nil
    return { ok = true }
end)

withContext('faction_message_save', function(source, ctx, data)
    if ctx.readOnly or not can(ctx, 'message.edit') then
        return { ok = false, error = 'no_permission' }
    end
    local text = Factions.Text(data.text, CFG.TextMax.message)
    DB.Update('UPDATE faction_settings SET message = ?, message_by = ?, message_at = CURRENT_TIMESTAMP WHERE faction = ?',
        DB.Args(text, ctx.name, ctx.faction))
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'message', data = { faction = ctx.faction, text = text } })
    protocol(ctx, 'anpassung', 'message', text and 'Nachricht vom Leader geändert' or 'Nachricht vom Leader gelöscht')
    return { ok = true, data = overview(ctx) }
end)

-- Kasse: einzahlen aus dem eigenen Bargeld, auszahlen ins eigene Bargeld
withContext('faction_cash', function(source, ctx, data)
    if ctx.readOnly or not can(ctx, 'cash.manage') then
        return { ok = false, error = 'no_permission' }
    end
    local amount = Factions.Int(data.amount, 1, 1000000000)
    if not amount or (data.action ~= 'deposit' and data.action ~= 'withdraw') then
        return { ok = false, error = 'invalid_amount' }
    end
    local reason = ('Kasse %s'):format(ctx.org.short)
    if data.action == 'deposit' then
        local balance = Factions.Core('RemoveMoney', source, 'cash', amount, reason, { data = { faction = ctx.faction } })
        if not balance then
            return { ok = false, error = 'not_enough_money' }
        end
        if not Factions.Deposit(ctx.faction, amount, { actorSource = source, reason = 'Einzahlung' }) then
            Factions.Core('AddMoney', source, 'cash', amount, reason .. ' (zurück)')
            return { ok = false, error = 'server_error' }
        end
    else
        if not Factions.Withdraw(ctx.faction, amount, { actorSource = source, reason = 'Auszahlung' }) then
            return { ok = false, error = 'not_enough_money' }
        end
        if not Factions.Core('AddMoney', source, 'cash', amount, reason, { data = { faction = ctx.faction } }) then
            Factions.Deposit(ctx.faction, amount, { reason = 'Auszahlung fehlgeschlagen, zurück' })
            return { ok = false, error = 'server_error' }
        end
    end
    return { ok = true, data = overview(ctx) }
end)

------------------------------------------------------------------------
-- Tab 2: Raenge, Rechte, Abteilungen, Pruefungen
------------------------------------------------------------------------

-- Darf ctx Name und Rechte dieses Rangs aendern? Leader: alle bis auf die eigenen Rechte. Vice: nur unter sich.
local function canEditRank(ctx, rank)
    if not canStructure(ctx) or ctx.readOnly then
        return false
    end
    if ctx.admin or ctx.rank >= ctx.org.leaderRank then
        return true
    end
    return rank < ctx.org.viceRank
end

local function ranksPayload(ctx)
    local list = {}
    for rank = ctx.org.ranks, 1, -1 do
        local permissions = {}
        for key in pairs(Factions.RankPermissions(ctx.faction, rank)) do
            permissions[#permissions + 1] = key
        end
        table.sort(permissions)
        list[#list + 1] = {
            rank = rank,
            name = Factions.RankName(ctx.faction, rank),
            permissions = permissions,
            salary = Factions.RankSalary(ctx.faction, rank),
            tasks = Factions.RankTasks(ctx.faction, rank),
            editable = canEditRank(ctx, rank),
            fixedPermissions = rank >= ctx.org.leaderRank or nil,
        }
    end
    local defs = {}
    for _, def in ipairs(Factions.PermissionsOf(ctx.faction)) do
        defs[#defs + 1] = { key = def.key, group = def.group, label = def.label,
            grantable = ctx.admin and ctx.manage or Factions.RankHas(ctx.faction, ctx.rank, def.key) }
    end
    return {
        ranks = list,
        permissions = defs,
        departments = Members.Departments(ctx.faction),
        exams = Members.Exams(ctx.faction),
        limits = { departments = CFG.MaxDepartments, departmentRanks = CFG.MaxDepartmentRanks, exams = CFG.MaxExams,
            rankName = CFG.TextMax.rankName, department = CFG.TextMax.department, exam = CFG.TextMax.exam,
            examDescription = CFG.TextMax.examDescription, rankTasks = CFG.TextMax.rankTasks,
            salary = CFG.Salary.Max, salaryInterval = CFG.Salary.IntervalMinutes },
        canEdit = canStructure(ctx) and not ctx.readOnly,
    }
end

withContext('faction_ranks', function(source, ctx)
    if not canStructure(ctx) and not ctx.admin then
        return { ok = false, error = 'no_permission' }
    end
    return { ok = true, data = ranksPayload(ctx) }
end)

withContext('faction_rank_save', function(source, ctx, data)
    local rank = Factions.Int(data.rank, 1, ctx.org.ranks)
    if not rank then
        return { ok = false, error = 'invalid_rank' }
    end
    if not canEditRank(ctx, rank) then
        return { ok = false, error = 'no_permission' }
    end
    local name = Factions.Text(data.name, CFG.TextMax.rankName)
    if not name then
        return { ok = false, error = 'invalid_name' }
    end
    local wanted = {}
    if type(data.permissions) == 'table' then
        for _, key in ipairs(data.permissions) do
            if type(key) == 'string' then
                wanted[key] = true
            end
        end
    end
    -- Nur Rechte aendern, die man selbst hat. Der hoechste Rang hat immer alles, da zaehlt nur der Name.
    local stored = {}
    local isTop = rank >= ctx.org.leaderRank
    for _, def in ipairs(Factions.PermissionsOf(ctx.faction)) do
        local current = Factions.RankHas(ctx.faction, rank, def.key)
        local mayChange = not isTop and (ctx.admin and ctx.manage or Factions.RankHas(ctx.faction, ctx.rank, def.key))
        if mayChange then
            stored[def.key] = wanted[def.key] == true
        else
            stored[def.key] = current
        end
    end
    -- Gehalt (0 bis Salary.Max) und Aufgaben (Text fuer Erklaerungen). Fehlen sie, bleiben die bisherigen.
    local salary = Factions.RankSalary(ctx.faction, rank)
    if data.salary ~= nil then
        salary = Factions.Int(data.salary, 0, CFG.Salary.Max)
        if not salary then
            return { ok = false, error = 'invalid_salary' }
        end
    end
    local tasks = nil
    if data.tasks ~= nil then
        tasks = Factions.Text(data.tasks, CFG.TextMax.rankTasks) or false
    end
    -- Was sich aendert, fuers Protokoll (vor dem Speichern lesen)
    local changes = {}
    local oldName = Factions.RankName(ctx.faction, rank)
    if oldName ~= name then
        changes[#changes + 1] = ('Name %s statt %s'):format(name, oldName)
    end
    local added, removed = {}, {}
    for _, def in ipairs(Factions.PermissionsOf(ctx.faction)) do
        local before = Factions.RankHas(ctx.faction, rank, def.key) == true
        if stored[def.key] and not before then
            added[#added + 1] = def.label
        elseif not stored[def.key] and before then
            removed[#removed + 1] = def.label
        end
    end
    if #added > 0 then
        changes[#changes + 1] = 'Rechte dazu: ' .. table.concat(added, ', ')
    end
    if #removed > 0 then
        changes[#changes + 1] = 'Rechte weg: ' .. table.concat(removed, ', ')
    end
    local oldSalary = Factions.RankSalary(ctx.faction, rank)
    if oldSalary ~= salary then
        changes[#changes + 1] = ('Gehalt %s statt %s'):format(Factions.Money(salary), Factions.Money(oldSalary))
    end
    if tasks ~= nil and (tasks or nil) ~= Factions.RankTasks(ctx.faction, rank) then
        changes[#changes + 1] = 'Aufgaben geändert'
    end
    if not Factions.SaveRank(ctx.faction, rank, name, stored, { salary = salary, tasks = tasks }) then
        return { ok = false, error = 'db_error' }
    end
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'rank_settings',
        data = { faction = ctx.faction, rank = rank, name = name, permissions = stored, salary = salary, tasks = tasks or nil } })
    if #changes > 0 then
        protocol(ctx, 'anpassung', 'rank_settings', ('Rang %d: %s'):format(rank, table.concat(changes, '; ')))
    end
    Factions.PushFaction(ctx.faction)
    return { ok = true, data = ranksPayload(ctx) }
end)

-- Abteilungsleitung: wer in dieser Abteilung den hoechsten internen Rang hat. Darf deren Rangnamen aendern.
local function leadsDepartment(ctx, department)
    if not ctx.member then
        return false
    end
    for _, entry in ipairs(ctx.member.departments) do
        if entry.id == department.id and entry.rank >= #department.ranks then
            return true
        end
    end
    return false
end

local function cleanRanks(list)
    if type(list) ~= 'table' then
        return nil
    end
    local ranks = {}
    for _, value in ipairs(list) do
        local name = Factions.Text(value, CFG.TextMax.rankName)
        if name then
            ranks[#ranks + 1] = name
        end
        if #ranks >= CFG.MaxDepartmentRanks then
            break
        end
    end
    return #ranks > 0 and ranks or nil
end

withContext('faction_department_save', function(source, ctx, data)
    if ctx.readOnly then
        return { ok = false, error = 'no_permission' }
    end
    local ranks = cleanRanks(data.ranks)
    if not ranks then
        return { ok = false, error = 'invalid_ranks' }
    end
    local id = tonumber(data.id)
    if id then
        local department = Members.ById(Members.Departments(ctx.faction))[id]
        if not department then
            return { ok = false, error = 'not_found' }
        end
        -- Abteilungsleitung darf nur die Rangnamen aendern, die Anzahl bleibt
        local structure = canStructure(ctx)
        if not structure and not (leadsDepartment(ctx, department) and #ranks == #department.ranks) then
            return { ok = false, error = 'no_permission' }
        end
        local name = structure and Factions.Text(data.name, CFG.TextMax.department) or department.name
        if not name then
            return { ok = false, error = 'invalid_name' }
        end
        DB.Update('UPDATE faction_departments SET name = ?, ranks = ? WHERE id = ? AND faction = ?', { name, Factions.Encode(ranks), id, ctx.faction })
    else
        if not canStructure(ctx) then
            return { ok = false, error = 'no_permission' }
        end
        local name = Factions.Text(data.name, CFG.TextMax.department)
        if not name then
            return { ok = false, error = 'invalid_name' }
        end
        if #Members.Departments(ctx.faction) >= CFG.MaxDepartments then
            return { ok = false, error = 'limit_reached' }
        end
        id = DB.Insert('INSERT INTO faction_departments (faction, name, ranks) VALUES (?, ?, ?)', { ctx.faction, name, Factions.Encode(ranks) })
    end
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'department_save',
        data = { faction = ctx.faction, id = id, ranks = ranks } })
    local saved = Members.ById(Members.Departments(ctx.faction))[id]
    protocol(ctx, 'anpassung', 'department_save', ('Abteilung %s gespeichert, Ränge: %s'):format(saved and saved.name or tostring(id), table.concat(ranks, ', ')))
    return { ok = true, data = ranksPayload(ctx) }
end)

withContext('faction_department_delete', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local id = tonumber(data.id)
    local department = id and Members.ById(Members.Departments(ctx.faction))[id]
    if not id or DB.Update('UPDATE faction_departments SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND faction = ? AND deleted_at IS NULL', { id, ctx.faction }) ~= 1 then
        return { ok = false, error = 'not_found' }
    end
    protocol(ctx, 'anpassung', 'department_delete', ('Abteilung %s gelöscht'):format(department and department.name or tostring(id)))
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'department_delete', data = { faction = ctx.faction, id = id } })
    return { ok = true, data = ranksPayload(ctx) }
end)

withContext('faction_exam_save', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local name = Factions.Text(data.name, CFG.TextMax.exam)
    if not name then
        return { ok = false, error = 'invalid_name' }
    end
    -- Beschreibung fuer die Erklaerungen (optional). Fehlt sie in der Anfrage, bleibt die bisherige.
    local description = Factions.Text(data.description, CFG.TextMax.examDescription)
    local id = tonumber(data.id)
    if id then
        local exists = DB.Scalar('SELECT COUNT(*) FROM faction_exams WHERE id = ? AND faction = ? AND deleted_at IS NULL', { id, ctx.faction })
        if (tonumber(exists) or 0) ~= 1 then
            return { ok = false, error = 'not_found' }
        end
        if data.description ~= nil then
            DB.Update('UPDATE faction_exams SET name = ?, description = ? WHERE id = ? AND faction = ?', DB.Args(name, description, id, ctx.faction))
        else
            DB.Update('UPDATE faction_exams SET name = ? WHERE id = ? AND faction = ?', { name, id, ctx.faction })
        end
    else
        if #Members.Exams(ctx.faction) >= CFG.MaxExams then
            return { ok = false, error = 'limit_reached' }
        end
        id = DB.Insert('INSERT INTO faction_exams (faction, name, description) VALUES (?, ?, ?)', DB.Args(ctx.faction, name, description))
    end
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'exam_save', data = { faction = ctx.faction, id = id, name = name } })
    protocol(ctx, 'anpassung', 'exam_save', ('Prüfung %s gespeichert'):format(name))
    return { ok = true, data = ranksPayload(ctx) }
end)

withContext('faction_exam_delete', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local id = tonumber(data.id)
    local exam = id and Members.ById(Members.Exams(ctx.faction))[id]
    if not id or DB.Update('UPDATE faction_exams SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND faction = ? AND deleted_at IS NULL', { id, ctx.faction }) ~= 1 then
        return { ok = false, error = 'not_found' }
    end
    protocol(ctx, 'anpassung', 'exam_delete', ('Prüfung %s gelöscht'):format(exam and exam.name or tostring(id)))
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'exam_delete', data = { faction = ctx.faction, id = id } })
    return { ok = true, data = ranksPayload(ctx) }
end)

------------------------------------------------------------------------
-- Tab 3: Fahrzeuge ab Rang
------------------------------------------------------------------------

-- Fahrzeuge der Organisation mit dem Rang, ab dem sie erlaubt sind (Datenbank vor Config)
function FactionMenu.Vehicles(faction)
    local org = Orgs[faction]
    local overrides = {}
    for _, row in ipairs(DB.Query('SELECT model, min_rank FROM faction_vehicles WHERE faction = ?', { faction }) or {}) do
        overrides[row.model] = row.min_rank
    end
    local list = {}
    for _, vehicle in ipairs(org.vehicles) do
        list[#list + 1] = { model = vehicle.model, label = vehicle.label or vehicle.model, minRank = overrides[vehicle.model] or vehicle.minRank or 1 }
    end
    return list
end

local function vehiclesPayload(ctx)
    local list = FactionMenu.Vehicles(ctx.faction)
    for _, vehicle in ipairs(list) do
        vehicle.rankName = Factions.RankName(ctx.faction, vehicle.minRank)
    end
    return { vehicles = list, canEdit = canStructure(ctx) and not ctx.readOnly }
end

withContext('faction_vehicles', function(source, ctx)
    if not canStructure(ctx) and not ctx.admin then
        return { ok = false, error = 'no_permission' }
    end
    return { ok = true, data = vehiclesPayload(ctx) }
end)

withContext('faction_vehicle_save', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local known = false
    for _, vehicle in ipairs(ctx.org.vehicles) do
        if vehicle.model == data.model then
            known = true
        end
    end
    local minRank = Factions.Int(data.minRank, 1, ctx.org.ranks)
    if not known or not minRank then
        return { ok = false, error = 'invalid_input' }
    end
    DB.Update('INSERT INTO faction_vehicles (faction, model, min_rank) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE min_rank = VALUES(min_rank)',
        { ctx.faction, data.model, minRank })
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'vehicle_rank',
        data = { faction = ctx.faction, model = data.model, minRank = minRank } })
    local label = data.model
    for _, vehicle in ipairs(ctx.org.vehicles) do
        if vehicle.model == data.model then
            label = vehicle.label or vehicle.model
        end
    end
    protocol(ctx, 'anpassung', 'vehicle_rank', ('Fahrzeug %s ab Rang %d (%s)'):format(label, minRank, Factions.RankName(ctx.faction, minRank)))
    return { ok = true, data = vehiclesPayload(ctx) }
end)

------------------------------------------------------------------------
-- Tab 4: Leitstelle
------------------------------------------------------------------------

local function membersPayload(ctx)
    local departments = Members.ById(Members.Departments(ctx.faction))
    local exams = Members.ById(Members.Exams(ctx.faction, true))
    local promotions = Members.LastPromotions(ctx.faction)
    local divisions = Members.Divisions(ctx.faction)
    local today = os.date('%Y-%m-%d')
    local rows = {}
    for _, member in ipairs(Members.List(ctx.faction)) do
        local deps = {}
        for _, entry in ipairs(member.departments) do
            local department = departments[entry.id]
            if department then
                deps[#deps + 1] = { id = entry.id, name = department.name, rank = entry.rank, rankName = department.ranks[entry.rank] }
            end
        end
        local passed = {}
        for _, entry in ipairs(member.exams) do
            local exam = exams[entry.id]
            passed[#passed + 1] = { id = entry.id, name = exam and exam.name or '?', at = entry.at, by = entry.by }
        end
        local source = Factions.SourceOf(member.characterId)
        rows[#rows + 1] = {
            characterId = member.characterId,
            name = member.name,
            dn = member.dn,
            rank = member.rank,
            rankName = Factions.RankName(ctx.faction, member.rank),
            strikes = member.strikes,
            vacationDays = member.vacationDays,
            departments = deps,
            exams = passed,
            hiredAt = member.hiredAt,
            lastPromotedAt = Members.PromotedSinceHire(promotions[member.characterId], member.hiredAt),
            bonusToday = member.lastBonusAt == today or nil,
            division = (Members.DivisionOf(divisions, member.rank) or {}).name,
            online = source ~= nil or nil,
            onDuty = source and Factions.IsOnDuty(source, ctx.faction) or nil,
            above = above(ctx, member) or nil,
            self = member.characterId == ctx.characterId or nil,
        }
    end
    local edit = {}
    if not ctx.readOnly then
        for _, key in ipairs({ 'members.hire', 'members.fire', 'members.rank', 'members.dn', 'members.strikes',
            'members.vacation', 'members.departments', 'members.exams' }) do
            edit[key:sub(9)] = can(ctx, key) or nil
        end
        edit.bonus = canStructure(ctx) or nil
    end
    local leads = {}
    for _, department in pairs(departments) do
        if leadsDepartment(ctx, department) then
            leads[#leads + 1] = department.id
        end
    end
    -- Raenge, die man vergeben darf: unter dem eigenen (Admin mit manage: alle ausser dem Leader)
    local maxRank = ctx.admin and (ctx.org.leaderRank - 1) or (ctx.rank - 1)
    local ranks = {}
    for rank = 1, ctx.org.ranks do
        ranks[#ranks + 1] = { rank = rank, name = Factions.RankName(ctx.faction, rank), assignable = rank <= maxRank or nil }
    end
    return {
        members = rows,
        edit = edit,
        departments = Members.Departments(ctx.faction),
        exams = Members.Exams(ctx.faction),
        leads = leads,
        ranks = ranks,
        limits = { strikes = CFG.MaxStrikes, vacation = CFG.MaxVacationDays, dn = CFG.TextMax.dn, reason = CFG.TextMax.reason,
            bonus = CFG.Bonus.Max },
    }
end

withContext('faction_members', function(source, ctx)
    if not can(ctx, 'leitstelle.view') then
        return { ok = false, error = 'no_permission' }
    end
    return { ok = true, data = membersPayload(ctx) }
end)

-- Ziel muss in derselben Organisation sein und darf nicht ueber einem stehen
local function targetMember(ctx, characterId)
    local member = Factions.GetMember(characterId)
    if not member or member.faction ~= ctx.faction then
        return nil, 'not_member'
    end
    return member
end

local function actorOf(ctx)
    return { source = ctx.source, characterId = ctx.characterId, name = ctx.name, accountId = ctx.accountId, admin = ctx.admin }
end

local function today()
    return os.date('%Y-%m-%d')
end

withContext('faction_member_update', function(source, ctx, data)
    if ctx.readOnly then
        return { ok = false, error = 'no_permission' }
    end
    local member, err = targetMember(ctx, data.characterId)
    if not member then
        return { ok = false, error = err }
    end
    local field, value = data.field, nil
    local selfEdit = member.characterId == ctx.characterId

    if field == 'departments' then
        -- Ganze Liste { { id, rank } }. Mit Recht: alles. Als Abteilungsleitung: nur die eigene Abteilung.
        local departments = Members.ById(Members.Departments(ctx.faction))
        if type(data.value) ~= 'table' then
            return { ok = false, error = 'invalid_input' }
        end
        value = {}
        local seen = {}
        for _, entry in ipairs(data.value) do
            local id = type(entry) == 'table' and tonumber(entry.id)
            local department = id and departments[id]
            local rank = department and Factions.Int(entry.rank, 1, #department.ranks)
            if department and rank and not seen[id] then
                seen[id] = true
                value[#value + 1] = { id = id, rank = rank }
            end
        end
        if not (can(ctx, 'members.departments') and above(ctx, member)) then
            -- Abteilungsleitung: nur die eigene Abteilung, nicht bei sich selbst
            if selfEdit then
                return { ok = false, error = 'no_permission' }
            end
            local before, after = {}, {}
            for _, entry in ipairs(member.departments) do before[entry.id] = entry.rank end
            for _, entry in ipairs(value) do after[entry.id] = entry.rank end
            for id in pairs(departments) do
                if before[id] ~= after[id] and not leadsDepartment(ctx, departments[id]) then
                    return { ok = false, error = 'no_permission' }
                end
            end
        end
    else
        local permission = ({ dn = 'members.dn', strikes = 'members.strikes', vacation = 'members.vacation', exams = 'members.exams' })[field]
        if not permission then
            return { ok = false, error = 'invalid_field' }
        end
        if not can(ctx, permission) or not above(ctx, member) then
            return { ok = false, error = 'no_permission' }
        end
        if field == 'dn' then
            value = Factions.Text(data.value, CFG.TextMax.dn)
            if data.value ~= nil and data.value ~= '' and not value then
                return { ok = false, error = 'invalid_input' }
            end
        elseif field == 'strikes' then
            value = Factions.Int(data.value, 0, CFG.MaxStrikes)
        elseif field == 'vacation' then
            value = Factions.Int(data.value, 0, CFG.MaxVacationDays)
        elseif field == 'exams' then
            -- Eine Pruefung eintragen (add) oder austragen (remove)
            local exam = Members.ById(Members.Exams(ctx.faction))[tonumber(data.examId)]
            if not exam or (data.value ~= 'add' and data.value ~= 'remove') then
                return { ok = false, error = 'invalid_input' }
            end
            value = {}
            for _, entry in ipairs(member.exams) do
                if entry.id ~= exam.id then
                    value[#value + 1] = entry
                end
            end
            if data.value == 'add' then
                value[#value + 1] = { id = exam.id, at = today(), by = ctx.name }
            end
        end
        if value == nil and field ~= 'dn' then
            return { ok = false, error = 'invalid_input' }
        end
    end

    local ok, setError = Members.SetField(ctx.faction, member.characterId, field, value, actorOf(ctx))
    if not ok then
        return { ok = false, error = setError }
    end
    return { ok = true, data = membersPayload(ctx) }
end)

withContext('faction_member_rank', function(source, ctx, data)
    if ctx.readOnly or not can(ctx, 'members.rank') then
        return { ok = false, error = 'no_permission' }
    end
    local member, err = targetMember(ctx, data.characterId)
    if not member then
        return { ok = false, error = err }
    end
    local maxRank = ctx.admin and (ctx.org.leaderRank - 1) or (ctx.rank - 1)
    local rank = Factions.Int(data.rank, 1, maxRank)
    if not above(ctx, member) or not rank then
        return { ok = false, error = 'no_permission' }
    end
    local ok, setError = Members.SetRank(ctx.faction, member.characterId, rank, actorOf(ctx))
    if not ok then
        return { ok = false, error = setError }
    end
    return { ok = true, data = membersPayload(ctx) }
end)

withContext('faction_member_fire', function(source, ctx, data)
    if ctx.readOnly or not can(ctx, 'members.fire') then
        return { ok = false, error = 'no_permission' }
    end
    local member, err = targetMember(ctx, data.characterId)
    if not member then
        return { ok = false, error = err }
    end
    if not above(ctx, member) or member.characterId == ctx.characterId then
        return { ok = false, error = 'no_permission' }
    end
    local ok, removeError = Members.Remove(ctx.faction, member.characterId, ctx.admin and 'admin' or 'fire', data.reason, actorOf(ctx))
    if not ok then
        return { ok = false, error = removeError }
    end
    local targetSource = Factions.SourceOf(member.characterId)
    if targetSource then
        Platform.Notify(targetSource, ('Du wurdest aus %s entlassen.'):format(ctx.org.label), 'warning')
    end
    return { ok = true, data = membersPayload(ctx) }
end)

-- Einstellen: Person muss online sein und zustimmen
local function hire(source, ctx, targetSource)
    if ctx.readOnly or not can(ctx, 'members.hire') then
        return { ok = false, error = 'no_permission' }
    end
    local characterId = Factions.CharacterOf(targetSource)
    if not characterId or targetSource == source then
        return { ok = false, error = 'target_offline' }
    end
    if Factions.GetMember(characterId) then
        return { ok = false, error = 'already_member' }
    end
    local accepted, consentError = FactionConsent(source, targetSource, ('Willst du %s beitreten?'):format(ctx.org.label),
        ('Einstellung als %s'):format(Factions.RankName(ctx.faction, 1)))
    if not accepted then
        return { ok = false, error = consentError }
    end
    local ok, err = Members.Hire(ctx.faction, characterId, 1, actorOf(ctx))
    if not ok then
        return { ok = false, error = err }
    end
    Platform.Notify(targetSource, ('Willkommen bei %s.'):format(ctx.org.label), 'success')
    return { ok = true }
end

withContext('faction_hire', function(source, ctx, data)
    local targetSource = Factions.SourceOf(tonumber(data.characterId))
    if not targetSource then
        return { ok = false, error = 'target_offline' }
    end
    local result = hire(source, ctx, targetSource)
    if result.ok then
        result.data = membersPayload(ctx)
    end
    return result
end)

-- Bonus aus der Kasse aufs Konto (auch offline). Nur Leader und Vice, hoechstens Bonus.Max, einmal pro Tag je Person.
withContext('faction_member_bonus', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local member, err = targetMember(ctx, data.characterId)
    if not member then
        return { ok = false, error = err }
    end
    if member.characterId == ctx.characterId then
        return { ok = false, error = 'no_permission' }
    end
    local amount = Factions.Int(data.amount, 1, CFG.Bonus.Max)
    if not amount then
        return { ok = false, error = 'invalid_amount' }
    end
    local reason = Factions.Text(data.reason, CFG.TextMax.reason)
    -- Erst den Tag belegen, damit zwei gleichzeitige Anfragen nicht beide durchgehen
    local before = DB.Scalar('SELECT last_bonus_at FROM faction_members WHERE character_id = ?', { member.characterId })
    if DB.Update('UPDATE faction_members SET last_bonus_at = CURRENT_TIMESTAMP WHERE character_id = ? AND faction = ? AND (last_bonus_at IS NULL OR last_bonus_at < CURDATE())',
        { member.characterId, ctx.faction }) ~= 1 then
        return { ok = false, error = 'bonus_today' }
    end
    local function undo()
        DB.Update('UPDATE faction_members SET last_bonus_at = ? WHERE character_id = ?', DB.Args(before, member.characterId))
    end
    if not Factions.Withdraw(ctx.faction, amount, { actorSource = source, reason = 'Bonus', data = { to = member.characterId, reason = reason },
        target = member.characterId, protocolText = ('Bonus %s an %s%s'):format(Factions.Money(amount), member.name, reason and (': ' .. reason) or '') }) then
        undo()
        return { ok = false, error = 'not_enough_money' }
    end
    if not Factions.Core('AddBankByCharacter', member.characterId, amount, ('Bonus %s'):format(ctx.org.short),
        { actorAccountId = ctx.accountId, data = { faction = ctx.faction, by = ctx.characterId, reason = reason } }) then
        Factions.Deposit(ctx.faction, amount, { reason = 'Bonus fehlgeschlagen, zurück' })
        undo()
        return { ok = false, error = 'server_error' }
    end
    Factions.Log({ actor_account_id = ctx.accountId, character_id = member.characterId, action = 'bonus', amount = amount, reason = reason,
        data = { faction = ctx.faction, by = ctx.characterId } })
    Factions.Refresh(member.characterId)
    local targetSource = Factions.SourceOf(member.characterId)
    if targetSource then
        Platform.Notify(targetSource, ('Bonus von %s: %s aufs Konto.%s'):format(ctx.org.short, Factions.Money(amount),
            reason and (' ' .. reason) or ''), 'success')
    end
    return { ok = true, data = membersPayload(ctx) }
end)

------------------------------------------------------------------------
-- Divisionen: Ranggruppen (Highcommand, Command, Supervisor ...) mit ihren Mitgliedern
------------------------------------------------------------------------

local function divisionsPayload(ctx)
    local divisions = Members.Divisions(ctx.faction)
    local groups, byId = {}, {}
    for _, division in ipairs(divisions) do
        local group = { id = division.id, name = division.name, minRank = division.minRank, maxRank = division.maxRank,
            minRankName = Factions.RankName(ctx.faction, division.minRank), maxRankName = Factions.RankName(ctx.faction, division.maxRank),
            members = {} }
        groups[#groups + 1] = group
        byId[division.id] = group
    end
    local rest = { id = 0, name = 'Ohne Division', members = {} }
    for _, member in ipairs(Members.List(ctx.faction)) do
        local division = Members.DivisionOf(divisions, member.rank)
        local target = division and byId[division.id] or rest
        local source = Factions.SourceOf(member.characterId)
        target.members[#target.members + 1] = {
            characterId = member.characterId, name = member.name, dn = member.dn, rank = member.rank,
            rankName = Factions.RankName(ctx.faction, member.rank),
            online = source ~= nil or nil, onDuty = source and Factions.IsOnDuty(source, ctx.faction) or nil,
        }
    end
    if #rest.members > 0 then
        groups[#groups + 1] = rest
    end
    local ranks = {}
    for rank = ctx.org.ranks, 1, -1 do
        ranks[#ranks + 1] = { rank = rank, name = Factions.RankName(ctx.faction, rank) }
    end
    return { divisions = groups, ranks = ranks, canEdit = canStructure(ctx) and not ctx.readOnly,
        limits = { divisions = CFG.MaxDivisions, name = CFG.TextMax.division } }
end

withContext('faction_divisions', function(source, ctx)
    if not can(ctx, 'leitstelle.view') then
        return { ok = false, error = 'no_permission' }
    end
    return { ok = true, data = divisionsPayload(ctx) }
end)

withContext('faction_division_save', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local name = Factions.Text(data.name, CFG.TextMax.division)
    local minRank = Factions.Int(data.minRank, 1, ctx.org.ranks)
    local maxRank = Factions.Int(data.maxRank, 1, ctx.org.ranks)
    if not name then
        return { ok = false, error = 'invalid_name' }
    end
    if not minRank or not maxRank or minRank > maxRank then
        return { ok = false, error = 'invalid_ranks' }
    end
    local id = tonumber(data.id)
    local list = Members.Divisions(ctx.faction)
    if id and not Members.ById(list)[id] then
        return { ok = false, error = 'not_found' }
    end
    if not id and #list >= CFG.MaxDivisions then
        return { ok = false, error = 'limit_reached' }
    end
    -- Rangbereiche duerfen sich nicht ueberschneiden, sonst waere jemand in zwei Divisionen
    for _, other in ipairs(list) do
        if other.id ~= id and minRank <= other.maxRank and maxRank >= other.minRank then
            return { ok = false, error = 'division_overlap', data = { name = other.name } }
        end
    end
    if id then
        DB.Update('UPDATE faction_divisions SET name = ?, min_rank = ?, max_rank = ? WHERE id = ? AND faction = ?', { name, minRank, maxRank, id, ctx.faction })
    else
        id = DB.Insert('INSERT INTO faction_divisions (faction, name, min_rank, max_rank) VALUES (?, ?, ?, ?)', { ctx.faction, name, minRank, maxRank })
    end
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'division_save',
        data = { faction = ctx.faction, id = id, name = name, minRank = minRank, maxRank = maxRank } })
    protocol(ctx, 'anpassung', 'division_save', ('Division %s: Rang %d bis %d'):format(name, minRank, maxRank))
    return { ok = true, data = divisionsPayload(ctx) }
end)

withContext('faction_division_delete', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local id = tonumber(data.id)
    local division = id and Members.ById(Members.Divisions(ctx.faction))[id]
    if not id or DB.Update('DELETE FROM faction_divisions WHERE id = ? AND faction = ?', { id, ctx.faction }) ~= 1 then
        return { ok = false, error = 'not_found' }
    end
    protocol(ctx, 'anpassung', 'division_delete', ('Division %s gelöscht'):format(division and division.name or tostring(id)))
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'division_delete', data = { faction = ctx.faction, id = id } })
    return { ok = true, data = divisionsPayload(ctx) }
end)

------------------------------------------------------------------------
-- Erklaerungen: Pruefungen, Raenge mit Aufgaben und Rechten, Regeln und Ablaeufe der Leitung
------------------------------------------------------------------------

local CATEGORY_KEYS = {}
for _, category in ipairs(CFG.InfoCategories) do
    CATEGORY_KEYS[category.key] = true
end

local function infoPayload(ctx)
    local labels = {}
    for _, def in ipairs(Factions.PermissionsOf(ctx.faction)) do
        labels[def.key] = def.label
    end
    -- Raenge mit Aufgaben, Gehalt und Rechten (nur Raenge, bei denen etwas steht oder ein Recht dazukommt)
    local ranks = {}
    local previous = {}
    for rank = 1, ctx.org.ranks do
        local current = Factions.RankPermissions(ctx.faction, rank)
        local new = {}
        for key in pairs(current) do
            if not previous[key] then
                new[#new + 1] = labels[key] or key
            end
        end
        table.sort(new)
        local tasks = Factions.RankTasks(ctx.faction, rank)
        local salary = Factions.RankSalary(ctx.faction, rank)
        ranks[#ranks + 1] = { rank = rank, name = Factions.RankName(ctx.faction, rank), tasks = tasks, salary = salary,
            newPermissions = new }
        previous = current
    end
    local exams = {}
    for _, exam in ipairs(Members.Exams(ctx.faction)) do
        exams[#exams + 1] = { id = exam.id, name = exam.name, description = exam.description }
    end
    return {
        categories = CFG.InfoCategories,
        sections = Members.Info(ctx.faction),
        exams = exams,
        ranks = ranks,
        divisions = Members.Divisions(ctx.faction),
        salaryInterval = CFG.Salary.IntervalMinutes,
        canEdit = canStructure(ctx) and not ctx.readOnly,
        limits = { sections = CFG.MaxInfoSections, title = CFG.TextMax.infoTitle, body = CFG.TextMax.infoBody,
            examDescription = CFG.TextMax.examDescription, rankTasks = CFG.TextMax.rankTasks },
    }
end

withContext('faction_info', function(source, ctx)
    return { ok = true, data = infoPayload(ctx) }
end)

withContext('faction_info_save', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local category = CATEGORY_KEYS[data.category] and data.category or nil
    local title = Factions.Text(data.title, CFG.TextMax.infoTitle)
    local body = Factions.Text(data.body, CFG.TextMax.infoBody)
    local sort = Factions.Int(data.sort or 0, -999, 999) or 0
    if not category or not title or not body then
        return { ok = false, error = 'invalid_input' }
    end
    local id = tonumber(data.id)
    if id then
        if DB.Update('UPDATE faction_info SET category = ?, title = ?, body = ?, sort = ?, updated_by = ? WHERE id = ? AND faction = ?',
            { category, title, body, sort, ctx.name, id, ctx.faction }) ~= 1 then
            return { ok = false, error = 'not_found' }
        end
    else
        local count = tonumber(DB.Scalar('SELECT COUNT(*) FROM faction_info WHERE faction = ?', { ctx.faction })) or 0
        if count >= CFG.MaxInfoSections then
            return { ok = false, error = 'limit_reached' }
        end
        id = DB.Insert('INSERT INTO faction_info (faction, category, title, body, sort, updated_by) VALUES (?, ?, ?, ?, ?, ?)',
            { ctx.faction, category, title, body, sort, ctx.name })
    end
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'info_save',
        data = { faction = ctx.faction, id = id, category = category, title = title } })
    protocol(ctx, 'anpassung', 'info_save', ('Erklärung %s gespeichert'):format(title))
    return { ok = true, data = infoPayload(ctx) }
end)

withContext('faction_info_delete', function(source, ctx, data)
    if ctx.readOnly or not canStructure(ctx) then
        return { ok = false, error = 'no_permission' }
    end
    local id = tonumber(data.id)
    local title = id and DB.Scalar('SELECT title FROM faction_info WHERE id = ? AND faction = ?', { id, ctx.faction })
    if not id or DB.Update('DELETE FROM faction_info WHERE id = ? AND faction = ?', { id, ctx.faction }) ~= 1 then
        return { ok = false, error = 'not_found' }
    end
    protocol(ctx, 'anpassung', 'info_delete', ('Erklärung %s gelöscht'):format(title or tostring(id)))
    Factions.Log({ actor_account_id = ctx.accountId, character_id = ctx.characterId, action = 'info_delete', data = { faction = ctx.faction, id = id } })
    return { ok = true, data = infoPayload(ctx) }
end)

------------------------------------------------------------------------
-- Tab 5: Archiv
------------------------------------------------------------------------

withContext('faction_archive', function(source, ctx, data)
    if not can(ctx, 'archive.view') then
        return { ok = false, error = 'no_permission' }
    end
    local page = Factions.Int(data.page or 1, 1, 10000) or 1
    local size = CFG.ArchivePageSize
    local search = Factions.Text(data.search, 50)
    local rows
    local columns = "id, character_id, name, dn, last_rank, ranks, exams, DATE_FORMAT(hired_at, '%Y-%m-%d') AS hired_at, DATE_FORMAT(left_at, '%Y-%m-%d') AS left_at, left_reason, left_by, kind, hidden_by"
    -- Von einem Admin ausgeblendete Eintraege sehen nur Admins (markiert)
    local visible = ctx.admin and '' or ' AND hidden_at IS NULL'
    if search and tonumber(search) then
        rows = DB.Query('SELECT ' .. columns .. ' FROM faction_archive WHERE character_id = ? AND faction = ?' .. visible .. ' ORDER BY left_at DESC, id DESC LIMIT ?',
            { tonumber(search), ctx.faction, size + 1 })
    elseif search then
        rows = DB.Query('SELECT ' .. columns .. ' FROM faction_archive WHERE faction = ? AND name LIKE ?' .. visible .. ' ORDER BY left_at DESC, id DESC LIMIT ? OFFSET ?',
            { ctx.faction, '%' .. search:gsub('[%%_\\]', '\\%0') .. '%', size + 1, (page - 1) * size })
    else
        rows = DB.Query('SELECT ' .. columns .. ' FROM faction_archive WHERE faction = ?' .. visible .. ' ORDER BY left_at DESC, id DESC LIMIT ? OFFSET ?',
            { ctx.faction, size + 1, (page - 1) * size })
    end
    rows = rows or {}
    local list = {}
    for index, row in ipairs(rows) do
        if index > size then
            break
        end
        list[#list + 1] = {
            id = row.id, characterId = row.character_id, name = row.name, dn = row.dn, lastRank = row.last_rank,
            ranks = Factions.Decode(row.ranks, {}), exams = Factions.Decode(row.exams, {}),
            hiredAt = row.hired_at, leftAt = row.left_at, reason = row.left_reason, by = row.left_by, kind = row.kind,
            hiddenBy = row.hidden_by,
        }
    end
    return { ok = true, data = { entries = list, page = page, hasMore = #rows > size, canEdit = (ctx.admin and ctx.manage) or nil } }
end)

-- Nur Admins mit factions.manage: Grund im Archiv korrigieren, Eintrag ausblenden oder wieder zeigen.
-- Ausgeblendet heisst nicht geloescht: Admins sehen den Eintrag weiter, markiert.
withContext('faction_archive_update', function(source, ctx, data)
    if not (ctx.admin and ctx.manage) then
        return { ok = false, error = 'no_permission' }
    end
    local id = tonumber(data.id)
    local row = id and DB.Single('SELECT character_id, name, left_reason, hidden_at IS NOT NULL AS hidden FROM faction_archive WHERE id = ? AND faction = ?', { id, ctx.faction })
    if not row then
        return { ok = false, error = 'not_found' }
    end
    local text
    if data.reason ~= nil then
        local reason = Factions.Text(data.reason, CFG.TextMax.reason)
        DB.Update('UPDATE faction_archive SET left_reason = ? WHERE id = ?', DB.Args(reason, id))
        text = ('Archiv: Grund %s statt %s'):format(reason or 'leer', row.left_reason or 'leer')
    elseif data.hidden == true or data.hidden == false then
        if data.hidden then
            DB.Update('UPDATE faction_archive SET hidden_at = CURRENT_TIMESTAMP, hidden_by = ? WHERE id = ?', { ctx.name, id })
        else
            DB.Update('UPDATE faction_archive SET hidden_at = NULL, hidden_by = NULL WHERE id = ?', { id })
        end
        text = data.hidden and 'Archiv-Eintrag ausgeblendet' or 'Archiv-Eintrag wieder sichtbar'
    else
        return { ok = false, error = 'invalid_input' }
    end
    Factions.Log({ actor_account_id = ctx.accountId, character_id = row.character_id, action = 'archive_update',
        data = { faction = ctx.faction, id = id, reason = data.reason, hidden = data.hidden } })
    protocol(ctx, 'leitstelle', 'archive_update', text, row.character_id, row.name)
    return { ok = true }
end)

------------------------------------------------------------------------
-- Protokolle: alles, was passiert ist, pro permanenter ID (Recht logs.view, Admins mit factions.view)
------------------------------------------------------------------------

withContext('faction_logs', function(source, ctx, data)
    if not can(ctx, 'logs.view') then
        return { ok = false, error = 'no_permission' }
    end
    local characterId = Factions.Int(data.characterId, 1, 4294967295)
    local role = (data.role == 'target' or data.role == 'actor') and data.role or 'all'
    local page = Protocol.Page(ctx.faction, { characterId = characterId, role = role, area = data.area, before = data.before })
    page.areas = CFG.Protocol.Areas
    page.person = characterId and { id = characterId, name = Protocol.NameOf(characterId) } or nil
    return { ok = true, data = page }
end)

------------------------------------------------------------------------
-- Aus dem G-Menue: an der Person, die man anschaut
------------------------------------------------------------------------

local function nearTarget(source, targetSource)
    local a, b = Platform.GetPlayerPosition(source), Platform.GetPlayerPosition(targetSource)
    if not a or not b then
        return false
    end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz <= TARGET_DISTANCE * TARGET_DISTANCE
end

local function targetFromData(source, data)
    local targetSource = tonumber(data.serverId)
    if not targetSource or targetSource == source or not Factions.CharacterOf(targetSource) then
        return nil, 'target_offline'
    end
    if not nearTarget(source, targetSource) then
        return nil, 'too_far'
    end
    return targetSource
end

register('faction_target_hire', function(source, data)
    adminView[source] = nil
    local ctx = context(source)
    if not ctx then
        return { ok = false, error = 'not_member' }
    end
    local targetSource, err = targetFromData(source, data)
    if not targetSource then
        return { ok = false, error = err }
    end
    return hire(source, ctx, targetSource)
end)

-- Befoerdern (+1) oder degradieren (-1)
register('faction_target_rank', function(source, data)
    adminView[source] = nil
    local ctx = context(source)
    if not ctx or not can(ctx, 'members.rank') then
        return { ok = false, error = 'no_permission' }
    end
    local targetSource, err = targetFromData(source, data)
    if not targetSource then
        return { ok = false, error = err }
    end
    local member = targetMember(ctx, Factions.CharacterOf(targetSource))
    if not member then
        return { ok = false, error = 'not_member' }
    end
    local delta = tonumber(data.delta) == -1 and -1 or 1
    local rank = member.rank + delta
    if not above(ctx, member) or rank < 1 or rank >= ctx.rank then
        return { ok = false, error = 'no_permission' }
    end
    local ok, setError = Members.SetRank(ctx.faction, member.characterId, rank, actorOf(ctx))
    if not ok then
        return { ok = false, error = setError }
    end
    Platform.Notify(targetSource, ('Neuer Rang: %s'):format(Factions.RankName(ctx.faction, rank)), delta > 0 and 'success' or 'warning')
    return { ok = true, data = { rankName = Factions.RankName(ctx.faction, rank) } }
end)

register('faction_target_fire', function(source, data)
    adminView[source] = nil
    local ctx = context(source)
    if not ctx or not can(ctx, 'members.fire') then
        return { ok = false, error = 'no_permission' }
    end
    local targetSource, err = targetFromData(source, data)
    if not targetSource then
        return { ok = false, error = err }
    end
    local member = targetMember(ctx, Factions.CharacterOf(targetSource))
    if not member then
        return { ok = false, error = 'not_member' }
    end
    if not above(ctx, member) then
        return { ok = false, error = 'no_permission' }
    end
    local ok, removeError = Members.Remove(ctx.faction, member.characterId, 'fire', data.reason, actorOf(ctx))
    if not ok then
        return { ok = false, error = removeError }
    end
    Platform.Notify(targetSource, ('Du wurdest aus %s entlassen.'):format(ctx.org.label), 'warning')
    return { ok = true }
end)

-- Selbst kuendigen. Der Leader kann das nicht (Uebergabe macht ein Admin).
register('faction_leave', function(source)
    local member = Factions.MemberOf(source)
    if not member then
        return { ok = false, error = 'not_member' }
    end
    if member.rank >= Orgs[member.faction].leaderRank then
        return { ok = false, error = 'leader_cannot_leave' }
    end
    local ok, err = Members.Remove(member.faction, member.characterId, 'leave', 'Selbst gekündigt',
        { source = source, characterId = member.characterId, name = member.name, accountId = Factions.AccountOf(source) })
    if not ok then
        return { ok = false, error = err }
    end
    return { ok = true }
end)

Platform.OnEvent('core:characterUnloaded', function(source)
    adminView[tonumber(source) or source] = nil
end)
