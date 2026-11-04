-- Ausweis und Lizenzen: Register in der Datenbank, Items in der Reihe "Dokumente", Zeigen.
-- Das Register ist die Wahrheit. Das Item ist nur, was man in der Tasche hat, und wird beim Einloggen abgeglichen.
--
-- Andere Scripts (Fahrschule, Amt, Waffenladen, spaeter das G-Menue):
--   exports.core_inventory:IssueLicense(characterId, 'driver', 'B', actorAccountId)    -> true | false, fehler
--   exports.core_inventory:RevokeLicense(characterId, 'driver', nil, grund, actorAccountId)
--   exports.core_inventory:HasLicense(characterId, 'driver', 'C')                       -> true, wenn gueltig
--   exports.core_inventory:GetLicenses(characterId)                                     -> Liste mit Status
--   exports.core_inventory:ShowDocument(source, 'id', zielServerId)                     -> true | false, fehler
--
-- Orga-Script (beim Beitritt, Befoerderung und Austritt):
--   exports.core_inventory:IssueServiceCard(characterId, { org = 'LSPD', label = 'Los Santos Police Department',
--       rank = 'Officer II', number = 'LSPD-482' }, actorAccountId)                       -> true | false, fehler
--     label ist optional (sonst aus Config.Inventory.Documents.ServiceOrgs), number optional (sonst die permanente ID).
--     Nochmal aufrufen aendert Dienstgrad oder Orga. Der Dienstausweis laeuft nicht ab.
--   exports.core_inventory:RevokeServiceCard(characterId, grund, actorAccountId)          -> Item weg, im Register entzogen
--   exports.core_inventory:HasLicense(characterId, 'service')                            -> true, solange er gilt

Documents = {}

local CORE = 'core'
local CFG = Config.Inventory.Documents
local SECONDS_PER_DAY = 86400
local SERVICE = 'service'
local SERVICE_TEXT_MAX = 48   -- Orga, Dienstgrad und Dienstnummer werden auf diese Laenge gekuerzt
local SERVICE_ORG_MAX = 12

local LICENSE_TABLE = [[
    CREATE TABLE IF NOT EXISTS licenses (
        id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        character_id  INT UNSIGNED NOT NULL,
        type          VARCHAR(16) NOT NULL,
        classes       VARCHAR(32) NULL,
        issued_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expires_at    TIMESTAMP NULL DEFAULT NULL,
        revoked_at    TIMESTAMP NULL DEFAULT NULL,
        revoked_by    INT UNSIGNED NULL,
        revoke_reason VARCHAR(255) NULL,
        UNIQUE KEY uniq_character_type (character_id, type)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]]

-- Ab 1.1.0: Angaben des Dienstausweises (JSON)
local DETAILS_COLUMN = 'ALTER TABLE licenses ADD COLUMN IF NOT EXISTS details VARCHAR(255) NULL AFTER classes'

DB.Ready(function()
    if DB.Query(LICENSE_TABLE) == nil then
        Platform.Print('error', 'Tabelle licenses konnte nicht angelegt werden. Bitte database/inventory.sql ausfuehren.')
        return
    end
    if DB.Query(DETAILS_COLUMN) == nil then
        Platform.Print('error', 'Spalte licenses.details fehlt. Bitte database/inventory.sql ausfuehren.')
    end
end)

-- Typ -> Item und Anzeigename, z. B. driver -> license_driver
local TYPES = {}
for _, slot in ipairs(CFG.Slots) do
    local def = ItemDef(slot.item)
    if def and def.document then
        TYPES[def.document] = { item = slot.item, label = def.label }
    end
end
Documents.Types = TYPES

local function log(entry)
    entry.category = 'item'
    Platform.CallExport(CORE, 'Log', entry)
end

------------------------------------------------------------------------
-- Register lesen
------------------------------------------------------------------------

local function splitClasses(text)
    local list = {}
    for class in tostring(text or ''):gmatch('[^,]+') do
        list[#list + 1] = class
    end
    return list
end

local function statusOf(row, now)
    if row.revoked then
        return 'revoked'
    end
    if row.expires and row.expires <= now then
        return 'expired'
    end
    return 'valid'
end

local function readRows(characterId)
    local rows = DB.Query([[
        SELECT type, classes, details, UNIX_TIMESTAMP(issued_at) AS issued, UNIX_TIMESTAMP(expires_at) AS expires,
               UNIX_TIMESTAMP(revoked_at) AS revoked, revoke_reason
        FROM licenses WHERE character_id = ?
    ]], { characterId }) or {}
    local now = os.time()
    local list = {}
    for _, row in ipairs(rows) do
        local entry = {
            type = row.type,
            label = TYPES[row.type] and TYPES[row.type].label or row.type,
            classes = splitClasses(row.classes),
            issuedAt = tonumber(row.issued),
            expiresAt = tonumber(row.expires),
            revokedAt = tonumber(row.revoked),
            revokeReason = row.revoke_reason,
        }
        local details = row.details and Platform.JsonDecode(row.details)
        if type(details) == 'table' then
            entry.details = details
        end
        entry.status = statusOf({ revoked = entry.revokedAt, expires = entry.expiresAt }, now)
        list[#list + 1] = entry
    end
    return list
end

function Documents.Licenses(characterId)
    return readRows(tonumber(characterId))
end

local function findRow(characterId, licenseType)
    for _, row in ipairs(readRows(characterId)) do
        if row.type == licenseType then
            return row
        end
    end
    return nil
end

function Documents.Has(characterId, licenseType, class)
    local row = findRow(tonumber(characterId), licenseType)
    if not row or row.status ~= 'valid' then
        return false
    end
    if class then
        for _, own in ipairs(row.classes) do
            if own == class then
                return true
            end
        end
        return false
    end
    return true
end

------------------------------------------------------------------------
-- Item mit dem Register abgleichen
------------------------------------------------------------------------

local function itemMeta(row)
    local details = row.details or {}
    return {
        classes = #row.classes > 0 and table.concat(row.classes, ',') or nil,
        expires = row.expiresAt,
        status = row.status ~= 'valid' and row.status or nil,
        org = details.org,
        rank = details.rank,
    }
end

-- Inventar eines Charakters passend zum Register: Ausweis immer, Lizenzen solange nicht entzogen
function Documents.Sync(inv, characterId)
    if not inv.slots[Inventory.DocumentSlotOf('id_card')] then
        Inventory.Add(inv, 'id_card', 1)
    end
    local seen = {}
    for _, row in ipairs(readRows(characterId)) do
        local info = TYPES[row.type]
        if info then
            seen[info.item] = true
            local slot = Inventory.DocumentSlotOf(info.item)
            if row.status == 'revoked' then
                if inv.slots[slot] then
                    inv.slots[slot] = nil
                    inv.dirty = true
                end
            else
                Inventory.Add(inv, info.item, 1, itemMeta(row))
            end
        end
    end
    -- Lizenz-Item ohne Eintrag im Register (z. B. per /giveitem): entfernen, nur das Register stellt aus
    for _, slot in ipairs(CFG.Slots) do
        local entry = inv.slots[slot.id]
        if entry and slot.item ~= 'id_card' and not seen[slot.item] then
            inv.slots[slot.id] = nil
            inv.dirty = true
        end
    end
end

------------------------------------------------------------------------
-- Ausstellen und Entziehen
------------------------------------------------------------------------

-- class nur beim Fuehrerschein (B oder C). Bei gueltiger Lizenz: verlaengern bzw. Klasse dazu.
function Documents.Issue(characterId, licenseType, class, actorAccountId)
    characterId = tonumber(characterId)
    local info = TYPES[licenseType]
    if not characterId or not info or licenseType == 'id' then
        return false, 'unknown_license'
    end
    if licenseType == SERVICE then
        return false, 'use_service'
    end
    if not Platform.CallExport(CORE, 'GetCharacterAccount', characterId) then
        return false, 'unknown_character'
    end
    local row = findRow(characterId, licenseType)
    local classes = {}
    if row and row.status ~= 'revoked' then
        classes = row.classes
    end
    if licenseType == 'driver' then
        class = class and class:upper() or nil
        local def = class and CFG.DriverClasses[class]
        if not def then
            return false, 'unknown_class'
        end
        local has = {}
        for _, own in ipairs(classes) do has[own] = true end
        if def.requires and not has[def.requires] then
            return false, 'needs_class'
        end
        if not has[class] then
            classes[#classes + 1] = class
        end
        table.sort(classes)
    end
    local expires = os.time() + CFG.LicenseDays * SECONDS_PER_DAY
    local ok = DB.Update([[
        INSERT INTO licenses (character_id, type, classes, expires_at) VALUES (?, ?, ?, FROM_UNIXTIME(?))
        ON DUPLICATE KEY UPDATE classes = VALUES(classes), expires_at = VALUES(expires_at), issued_at = CURRENT_TIMESTAMP,
            revoked_at = NULL, revoked_by = NULL, revoke_reason = NULL
    ]], DB.Args(characterId, licenseType, #classes > 0 and table.concat(classes, ',') or nil, expires))
    if ok == nil then
        return false, 'db_error'
    end
    InventoryApi_WithCharacter(characterId, function(inv)
        Documents.Sync(inv, characterId)
    end)
    local online = InventoryApi_SourceOf(characterId)
    if online then
        Network.SendToClient(online, 'core_inventory:changed', {})
    end
    log({ actor_account_id = actorAccountId, account_id = Platform.CallExport(CORE, 'GetCharacterAccount', characterId), character_id = characterId,
        action = 'license_issue', data = { type = licenseType, label = info.label, classes = classes, expires = expires } })
    return true
end

-- class beim Fuehrerschein: nur diese Klasse entziehen (C zuerst, B nimmt C mit)
function Documents.Revoke(characterId, licenseType, class, reason, actorAccountId)
    characterId = tonumber(characterId)
    local info = TYPES[licenseType]
    local row = characterId and info and findRow(characterId, licenseType)
    if not row or row.status == 'revoked' then
        return false, 'no_license'
    end
    local remaining = {}
    class = class and class:upper() or nil
    if licenseType == 'driver' and class then
        for _, own in ipairs(row.classes) do
            local def = CFG.DriverClasses[own]
            if own ~= class and not (def and def.requires == class) then
                remaining[#remaining + 1] = own
            end
        end
    end
    local ok
    if #remaining > 0 then
        ok = DB.Update('UPDATE licenses SET classes = ? WHERE character_id = ? AND type = ?', { table.concat(remaining, ','), characterId, licenseType })
    else
        ok = DB.Update('UPDATE licenses SET revoked_at = CURRENT_TIMESTAMP, revoked_by = ?, revoke_reason = ? WHERE character_id = ? AND type = ?',
            DB.Args(actorAccountId, reason, characterId, licenseType))
    end
    if ok == nil then
        return false, 'db_error'
    end
    InventoryApi_WithCharacter(characterId, function(inv)
        Documents.Sync(inv, characterId)
    end)
    local online = InventoryApi_SourceOf(characterId)
    if online then
        Network.SendToClient(online, 'core_inventory:changed', {})
    end
    log({ actor_account_id = actorAccountId, account_id = Platform.CallExport(CORE, 'GetCharacterAccount', characterId), character_id = characterId,
        action = 'license_revoke', reason = reason, data = { type = licenseType, label = info.label, class = class, remaining = remaining } })
    return true
end

------------------------------------------------------------------------
-- Dienstausweis
------------------------------------------------------------------------

local function cleanText(value, maxLength)
    if type(value) ~= 'string' and type(value) ~= 'number' then
        return nil
    end
    local text = tostring(value):gsub('[%c]', ''):match('^%s*(.-)%s*$')
    if text == '' then
        return nil
    end
    return text:sub(1, maxLength)
end

-- service: { org, label?, rank, number? }. Beitritt und Befoerderung, laeuft nicht ab.
function Documents.IssueService(characterId, service, actorAccountId)
    characterId = tonumber(characterId)
    if not characterId or type(service) ~= 'table' then
        return false, 'invalid_service'
    end
    if not Platform.CallExport(CORE, 'GetCharacterAccount', characterId) then
        return false, 'unknown_character'
    end
    local org = cleanText(service.org, SERVICE_ORG_MAX)
    local rank = cleanText(service.rank, SERVICE_TEXT_MAX)
    if not org or not rank then
        return false, 'invalid_service'
    end
    org = org:upper()
    local details = {
        org = org,
        label = cleanText(service.label, SERVICE_TEXT_MAX) or CFG.ServiceOrgs[org] or org,
        rank = rank,
        number = cleanText(service.number, SERVICE_TEXT_MAX) or tostring(characterId),
    }
    local ok = DB.Update([[
        INSERT INTO licenses (character_id, type, details, expires_at) VALUES (?, ?, ?, NULL)
        ON DUPLICATE KEY UPDATE details = VALUES(details), expires_at = NULL, issued_at = CURRENT_TIMESTAMP,
            revoked_at = NULL, revoked_by = NULL, revoke_reason = NULL
    ]], { characterId, SERVICE, Platform.JsonEncode(details) })
    if ok == nil then
        return false, 'db_error'
    end
    InventoryApi_WithCharacter(characterId, function(inv)
        Documents.Sync(inv, characterId)
    end)
    local online = InventoryApi_SourceOf(characterId)
    if online then
        Network.SendToClient(online, 'core_inventory:changed', {})
    end
    log({ actor_account_id = actorAccountId, account_id = Platform.CallExport(CORE, 'GetCharacterAccount', characterId), character_id = characterId,
        action = 'service_issue', data = details })
    return true
end

function Documents.RevokeService(characterId, reason, actorAccountId)
    return Documents.Revoke(characterId, SERVICE, nil, cleanText(reason, 255), actorAccountId)
end

------------------------------------------------------------------------
-- Zeigen
------------------------------------------------------------------------

-- Was auf der Karte steht. Name und Daten sind immer aktuell aus der Core.
function Documents.Card(characterId, licenseType)
    local record = Platform.CallExport(CORE, 'GetCharacterRecord', characterId)
    local info = TYPES[licenseType]
    if not record or not info then
        return nil
    end
    local card = {
        type = licenseType,
        title = info.label,
        firstname = record.firstname,
        lastname = record.lastname,
        dateOfBirth = record.dateOfBirth,
        gender = record.gender,
        number = characterId,
        issuer = CFG.Issuer,
    }
    if licenseType ~= 'id' then
        local row = findRow(characterId, licenseType)
        if not row then
            return nil
        end
        card.status = row.status
        card.issuedAt = row.issuedAt
        card.expiresAt = row.expiresAt
        card.revokedAt = row.revokedAt
        if licenseType == SERVICE and row.details then
            card.org = row.details.org
            card.orgLabel = row.details.label
            card.rank = row.details.rank
            card.serviceNumber = row.details.number
        end
        card.classes = {}
        for _, class in ipairs(row.classes) do
            local def = CFG.DriverClasses[class]
            card.classes[#card.classes + 1] = { id = class, label = def and def.label or class }
        end
    end
    return card
end

-- source zeigt sein Dokument der Person targetSource. Pruefungen: hat es, steht nah genug, gleiche Dimension.
function Documents.Show(source, licenseType, targetSource)
    local characterId = InventoryApi_ActiveCharacter(source)
    local targetCharacter = InventoryApi_ActiveCharacter(targetSource)
    if not characterId then
        return false, 'no_character'
    end
    if not targetCharacter or targetSource == source then
        return false, 'target_offline'
    end
    local info = TYPES[licenseType]
    local inv = info and Inventory.Cached(Inventory.CharacterId(characterId))
    if not inv or not inv.slots[Inventory.DocumentSlotOf(info.item)] then
        return false, 'no_document'
    end
    local a, b = Platform.GetPlayerPosition(source), Platform.GetPlayerPosition(targetSource)
    if not a or not b or Platform.GetPlayerDimension(source) ~= Platform.GetPlayerDimension(targetSource) then
        return false, 'too_far'
    end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    if dx * dx + dy * dy + dz * dz > CFG.ShowDistance * CFG.ShowDistance then
        return false, 'too_far'
    end
    local card = Documents.Card(characterId, licenseType)
    if not card then
        return false, 'no_document'
    end
    Network.SendToClient(targetSource, 'core_inventory:document', { card = card, from = source, seconds = CFG.ShowSeconds })
    Platform.Notify(source, ('Du zeigst ID %d deinen %s.'):format(targetCharacter, info.label), 'info')
    log({ account_id = Platform.CallExport(CORE, 'GetAccountId', source), character_id = characterId, action = 'show_document',
        target_account_id = Platform.CallExport(CORE, 'GetAccountId', targetSource), data = { type = licenseType, target = targetCharacter } })
    return true
end

------------------------------------------------------------------------
-- Schnittstellen
------------------------------------------------------------------------

Platform.Export('IssueLicense', Documents.Issue)
Platform.Export('RevokeLicense', Documents.Revoke)
Platform.Export('HasLicense', Documents.Has)
Platform.Export('GetLicenses', Documents.Licenses)
Platform.Export('ShowDocument', Documents.Show)
Platform.Export('IssueServiceCard', Documents.IssueService)
Platform.Export('RevokeServiceCard', Documents.RevokeService)

-- Fehlertexte fuer Befehle
local ERRORS = {
    unknown_license = 'Unbekannte Lizenz. Möglich: fuehrerschein, waffenschein, flugschein, bootsschein, angelschein, dienstausweis.',
    use_service = 'Den Dienstausweis stellt das Orga-Script aus: /givelicense <ID> dienstausweis <Orga> <Dienstgrad>.',
    invalid_service = 'Beim Dienstausweis Orga und Dienstgrad angeben, z. B. /givelicense 17 dienstausweis LSPD Officer II.',
    unknown_character = 'Diesen Charakter gibt es nicht.',
    unknown_class = 'Beim Führerschein die Klasse angeben: B (PKW) oder C (LKW und Transporter).',
    needs_class = 'Für Klasse C braucht die Person zuerst Klasse B.',
    no_license = 'Die Person hat diese Lizenz nicht (oder sie ist schon entzogen).',
    db_error = 'Datenbankfehler, siehe Serverkonsole.',
}
Documents.Errors = ERRORS

-- Befehlsnamen auf Deutsch -> Typ
local COMMAND_TYPES = { fuehrerschein = 'driver', waffenschein = 'weapon', flugschein = 'pilot', bootsschein = 'boat', angelschein = 'fishing', dienstausweis = SERVICE }

local function dateText(timestamp)
    return timestamp and os.date('%d.%m.%Y', timestamp) or '-'
end

Platform.RegisterCommand('givelicense', function(source, args)
    local allowed, actorAccountId = Platform.CallExport(CORE, 'AuthorizeCommand', source, 'givelicense', 'items.manage', args, true)
    if not allowed then
        return
    end
    local characterId, licenseType = tonumber(args[1]), COMMAND_TYPES[(args[2] or ''):lower()]
    if characterId and args[2] and not licenseType then
        Platform.Notify(source, ERRORS.unknown_license, 'error')
        return
    end
    if not characterId or not licenseType then
        Platform.Notify(source, 'Benutzung: /givelicense <permanente ID> <fuehrerschein|waffenschein|flugschein|bootsschein|angelschein> [B|C] oder /givelicense <ID> dienstausweis <Orga> <Dienstgrad>', 'info')
        return
    end
    -- Dienstausweis zum Testen: /givelicense 17 dienstausweis LSPD Officer II
    if licenseType == SERVICE then
        local rank = table.concat(args, ' ', 4)
        local ok, err = Documents.IssueService(characterId, { org = args[3], rank = rank }, actorAccountId)
        if not ok then
            Platform.Notify(source, ERRORS[err] or tostring(err), 'error')
            return
        end
        Platform.Notify(source, ('Dienstausweis (%s, %s) für ID %d ausgestellt.'):format(args[3]:upper(), rank, characterId), 'success')
        local target = InventoryApi_SourceOf(characterId)
        if target then
            Platform.Notify(target, 'Du hast einen Dienstausweis bekommen.', 'success')
        end
        return
    end
    local ok, err = Documents.Issue(characterId, licenseType, args[3], actorAccountId)
    if not ok then
        Platform.Notify(source, ERRORS[err] or tostring(err), 'error')
        return
    end
    local label = TYPES[licenseType].label .. (licenseType == 'driver' and (' Klasse ' .. args[3]:upper()) or '')
    Platform.Notify(source, ('%s für ID %d ausgestellt, gültig %d Tage.'):format(label, characterId, CFG.LicenseDays), 'success')
    local target = InventoryApi_SourceOf(characterId)
    if target then
        Platform.Notify(target, ('Du hast einen %s bekommen.'):format(label), 'success')
    end
end)

Platform.RegisterCommand('revokelicense', function(source, args)
    local allowed, actorAccountId = Platform.CallExport(CORE, 'AuthorizeCommand', source, 'revokelicense', 'items.manage', args, true)
    if not allowed then
        return
    end
    local characterId, licenseType = tonumber(args[1]), COMMAND_TYPES[(args[2] or ''):lower()]
    if not characterId or not licenseType then
        Platform.Notify(source, 'Benutzung: /revokelicense <permanente ID> <lizenz> [B|C] [Grund], z. B. /revokelicense 17 fuehrerschein C Trunkenheitsfahrt', 'info')
        return
    end
    local class, first = nil, 3
    if licenseType == 'driver' and args[3] and CFG.DriverClasses[args[3]:upper()] then
        class, first = args[3], 4
    end
    local reason = table.concat(args, ' ', first)
    local ok, err = Documents.Revoke(characterId, licenseType, class, reason ~= '' and reason or nil, actorAccountId)
    if not ok then
        Platform.Notify(source, ERRORS[err] or tostring(err), 'error')
        return
    end
    local label = TYPES[licenseType].label .. (class and (' Klasse ' .. class:upper()) or '')
    Platform.Notify(source, ('%s von ID %d entzogen.'):format(label, characterId), 'success')
    local target = InventoryApi_SourceOf(characterId)
    if target then
        Platform.Notify(target, ('Dir wurde der %s entzogen.'):format(label), 'error')
    end
end)

Platform.RegisterCommand('licenses', function(source, args)
    local allowed = Platform.CallExport(CORE, 'AuthorizeCommand', source, 'licenses', 'items.manage', args, false)
    if not allowed then
        return
    end
    local characterId = tonumber(args[1])
    if not characterId then
        Platform.Notify(source, 'Benutzung: /licenses <permanente ID>', 'info')
        return
    end
    local rows = Documents.Licenses(characterId)
    if #rows == 0 then
        Platform.Notify(source, ('ID %d hat keine Lizenzen.'):format(characterId), 'info')
        return
    end
    local STATUS = { valid = 'gültig bis %s', expired = 'abgelaufen seit %s', revoked = 'entzogen am %s' }
    local parts = {}
    for _, row in ipairs(rows) do
        local when = row.status == 'revoked' and row.revokedAt or row.expiresAt
        local classes = #row.classes > 0 and (' ' .. table.concat(row.classes, ',')) or ''
        if row.details then
            classes = (' %s, %s'):format(row.details.org or '?', row.details.rank or '?')
        end
        local status = (row.status == 'valid' and not when) and 'gültig' or STATUS[row.status]:format(dateText(when))
        parts[#parts + 1] = ('%s%s: %s'):format(row.label, classes, status)
    end
    Platform.Notify(source, ('ID %d: %s'):format(characterId, table.concat(parts, ' | ')), 'info')
end)

-- Zeigen aus dem Inventar (Rechtsklick) oder vorlaeufig per /zeigen
Network.RegisterCallback('doc_show', function(source, data)
    if type(data) ~= 'table' then
        return { ok = false, error = 'invalid' }
    end
    local ok, err = Documents.Show(source, data.type, tonumber(data.target))
    return { ok = ok, error = err }
end)
