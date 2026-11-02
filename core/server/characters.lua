-- Charaktere: auflisten, erstellen, loeschen, auswaehlen, speichern.
-- Kennt nur Daten. Alles GTA-5-Spezifische (Modelle, Spawnpunkte) liegt in data/.

Characters = {}

local GENDERS = { male = true, female = true }
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local MS_PER_SECOND = 1000

-- Bindestrich und Apostroph, z. B. "Anna-Lena" oder "O'Brien"
local NAME_SEPARATORS = { [45] = true, [39] = true }

local LIST_SQL = [[
    SELECT id, firstname, lastname,
           DATE_FORMAT(date_of_birth, '%Y-%m-%d') AS date_of_birth,
           gender, job, job_grade, cash, bank,
           UNIX_TIMESTAMP(last_played) AS last_played
    FROM characters
    WHERE account_id = ? AND deleted_at IS NULL
    ORDER BY id ASC
]]

------------------------------------------------------------------------
-- Pruefungen
------------------------------------------------------------------------

local function isLeapYear(year)
    return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

-- 'YYYY-MM-DD' -> Jahr, Monat, Tag oder nil
local function parseDate(value)
    if type(value) ~= 'string' then
        return nil
    end
    local y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then
        return nil
    end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 then
        return nil
    end
    local maxDay = DAYS_IN_MONTH[m]
    if m == 2 and isLeapYear(y) then
        maxDay = 29
    end
    if d < 1 or d > maxDay then
        return nil
    end
    return y, m, d
end

local function ageOf(y, m, d)
    local now = os.date('*t')
    local age = now.year - y
    if now.month < m or (now.month == m and now.day < d) then
        age = age - 1
    end
    return age
end

-- Buchstaben A bis Z und lateinische Sonderzeichen wie Umlaute, keine Zahlen oder Symbole
local function isNameLetter(cp)
    return (cp >= 65 and cp <= 90)
        or (cp >= 97 and cp <= 122)
        or (cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7)
end

-- Gibt den bereinigten Namen zurueck oder nil, wenn er nicht erlaubt ist
function Characters.NormalizeName(value)
    if type(value) ~= 'string' then
        return nil
    end

    local name = value:match('^%s*(.-)%s*$')
    local length = utf8.len(name)
    if not length or length < Config.Characters.NameMinLength or length > Config.Characters.NameMaxLength then
        return nil
    end

    -- Erstes und letztes Zeichen muessen Buchstaben sein, keine zwei Trennzeichen hintereinander
    local previousWasSeparator = true
    for _, cp in utf8.codes(name) do
        if NAME_SEPARATORS[cp] then
            if previousWasSeparator then
                return nil
            end
            previousWasSeparator = true
        elseif isNameLetter(cp) then
            previousWasSeparator = false
        else
            return nil
        end
    end
    if previousWasSeparator then
        return nil
    end

    -- Ersten Buchstaben gross schreiben (nur A bis Z, Umlaute bleiben wie eingegeben)
    return name:sub(1, 1):upper() .. name:sub(2)
end

-- Gibt 'YYYY-MM-DD' zurueck oder nil plus Fehlercode
function Characters.ValidateBirthDate(value)
    local y, m, d = parseDate(value)
    if not y then
        return nil, 'invalid_date_of_birth'
    end
    local age = ageOf(y, m, d)
    if age < Config.Characters.MinAge then
        return nil, 'too_young'
    end
    if age > Config.Characters.MaxAge then
        return nil, 'too_old'
    end
    return ('%04d-%02d-%02d'):format(y, m, d)
end

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------

local function toClient(row)
    return {
        id = row.id,
        firstname = row.firstname,
        lastname = row.lastname,
        dateOfBirth = row.date_of_birth,
        gender = row.gender,
        job = row.job,
        jobGrade = row.job_grade,
        cash = row.cash,
        bank = row.bank,
        lastPlayed = row.last_played and math.floor(tonumber(row.last_played) * MS_PER_SECOND) or nil,
    }
end

function Characters.List(accountId)
    local rows = DB.Query(LIST_SQL, { accountId })
    if not rows then
        return nil
    end
    local bans = Bans.ActiveCharacterBans(accountId)
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = toClient(row)
        list[i].ban = Bans.ToClient(bans[row.id])
    end
    return list
end

local function fullName(character)
    return ('%s %s'):format(character.firstname, character.lastname)
end

function Characters.Create(player, data)
    local firstname = Characters.NormalizeName(data.firstname)
    if not firstname then
        return nil, 'invalid_firstname'
    end
    local lastname = Characters.NormalizeName(data.lastname)
    if not lastname then
        return nil, 'invalid_lastname'
    end
    local dateOfBirth, dateError = Characters.ValidateBirthDate(data.dateOfBirth)
    if not dateOfBirth then
        return nil, dateError
    end
    if not GENDERS[data.gender] then
        return nil, 'invalid_gender'
    end

    local count = DB.Scalar(
        'SELECT COUNT(*) FROM characters WHERE account_id = ? AND deleted_at IS NULL',
        { player.accountId }
    )
    if count == nil then
        return nil, 'db_error'
    end
    if count >= Config.Characters.MaxPerAccount then
        return nil, 'max_characters'
    end

    if Config.Characters.UniqueNames then
        local existing = DB.Scalar(
            'SELECT id FROM characters WHERE firstname = ? AND lastname = ? AND deleted_at IS NULL LIMIT 1',
            { firstname, lastname }
        )
        if existing then
            return nil, 'name_taken'
        end
    end

    local characterId = DB.Insert(
        'INSERT INTO characters (account_id, firstname, lastname, date_of_birth, gender, cash, bank) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { player.accountId, firstname, lastname, dateOfBirth, data.gender, Config.Characters.StartCash, Config.Characters.StartBank }
    )
    if not characterId then
        return nil, 'db_error'
    end

    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = characterId,
        category = 'character',
        action = 'create',
        data = {
            name = ('%s %s'):format(firstname, lastname),
            dateOfBirth = dateOfBirth,
            gender = data.gender,
            startCash = Config.Characters.StartCash,
            startBank = Config.Characters.StartBank,
        },
    })

    -- Startgeld als eigene Buchungen, damit die Geld-Historie bei 0 beginnt
    for account, amount in pairs({ cash = Config.Characters.StartCash, bank = Config.Characters.StartBank }) do
        if amount > 0 then
            Core.Log({
                account_id = player.accountId,
                character_id = characterId,
                category = 'money',
                action = 'add',
                amount = amount,
                balance_before = 0,
                balance_after = amount,
                reason = 'Startgeld',
                data = { account = account },
            })
        end
    end

    return characterId
end

-- Geloeschte Charaktere bleiben in der Datenbank (deleted_at), damit Admins sie weiter sehen
function Characters.Delete(player, characterId)
    local row = DB.Single(
        'SELECT id, firstname, lastname FROM characters WHERE id = ? AND account_id = ? AND deleted_at IS NULL',
        { characterId, player.accountId }
    )
    if not row then
        return false, 'not_found'
    end
    -- Sonst koennte man einen gesperrten Charakter loeschen und den Platz neu belegen
    if Bans.ActiveForCharacter(row.id) then
        return false, 'character_banned'
    end

    local changed = DB.Update(
        'UPDATE characters SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND account_id = ? AND deleted_at IS NULL',
        { characterId, player.accountId }
    )
    if not changed or changed == 0 then
        return false, 'db_error'
    end

    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = characterId,
        category = 'character',
        action = 'delete',
        data = { name = fullName(row) },
    })

    return true
end

function Characters.Select(player, characterId)
    local row = DB.Single(
        'SELECT id, firstname, lastname, gender, job, job_grade, cash, bank, hunger, thirst, platform_data FROM characters WHERE id = ? AND account_id = ? AND deleted_at IS NULL',
        { characterId, player.accountId }
    )
    if not row then
        return nil, 'not_found'
    end

    local ban = Bans.ActiveForCharacter(row.id)
    if ban then
        Core.Log({
            actor_account_id = player.accountId,
            account_id = player.accountId,
            character_id = row.id,
            category = 'security',
            action = 'banned_character_select',
            data = { banId = ban.id },
        })
        return nil, 'character_banned', ban
    end

    local platformData = Platform.JsonDecode(row.platform_data)
    if type(platformData) ~= 'table' then
        platformData = {}
    end

    player.characterId = row.id
    player.rank = Permissions.LoadCharacterRank(row.id)
    player.character = {
        id = row.id,
        firstname = row.firstname,
        lastname = row.lastname,
        gender = row.gender,
        job = row.job,
        jobGrade = row.job_grade,
        -- Nur Zwischenspeicher fuer Anzeigen. Aendern ausschliesslich ueber Core.*Money.
        money = { cash = Money.CashOnSelect(row.id, row.cash), bank = row.bank },
        platformData = platformData,
    }
    local needs = Needs.Load(player, row)

    DB.Update('UPDATE characters SET last_played = CURRENT_TIMESTAMP WHERE id = ?', { row.id })

    -- Permanente ID (= Charakter-ID) fuer die Anzeige ueber dem Kopf
    Network.SetPlayerPublic(player.source, 'coreId', row.id)

    local position = platformData.position
    local firstSpawn = type(position) ~= 'table' or tonumber(position.x) == nil
    if firstSpawn then
        position = SpawnData.default
    end

    -- A-Jail gilt fuer den ganzen Account. Wer entlassen wurde, waehrend er offline war, steht vor dem Tor.
    local jail = Jail.Load(player)
    if jail then
        position = JailData.cell
    elseif Jail.IsInside(position) then
        position = JailData.release
    end

    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = row.id,
        category = 'character',
        action = 'select',
        data = { name = fullName(row), position = position, firstSpawn = firstSpawn, jailed = jail ~= nil or nil },
    })

    return {
        id = row.id,
        gender = row.gender,
        position = position,
        firstSpawn = firstSpawn,
        money = { cash = player.character.money.cash, bank = row.bank },
        needs = needs,
        jail = Jail.ClientInfo(jail),
    }
end

-- Speichert die aktuelle Position im platform_data des Charakters
function Characters.SavePosition(player)
    if not player or not player.character then
        return nil
    end

    local position = Platform.GetPlayerPosition(player.source)
    if not position then
        return nil
    end

    player.character.platformData.position = position
    DB.Update(
        'UPDATE characters SET platform_data = ? WHERE id = ?',
        { Platform.JsonEncode(player.character.platformData), player.characterId }
    )
    return position
end

-- Beim Ausloggen, Relog oder Verbindungsabbruch
function Characters.Unload(player, reason)
    if not player or not player.characterId then
        return
    end

    -- Andere Resources speichern zuerst, solange der Charakter noch bekannt ist
    Platform.Emit('core:characterUnloaded', player.source, player.characterId, reason)
    Core.StopNoclip(player, reason)
    Jail.Unload(player)
    AdminTools.OnUnload(player)
    Needs.Unload(player)
    local position = Characters.SavePosition(player)

    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = player.characterId,
        category = 'character',
        action = 'unload',
        reason = reason,
        -- dead = true heisst: hat das Spiel waehrend der Bewusstlosigkeit verlassen
        data = { position = position, dead = player.character.diedAt ~= nil },
    })

    Network.SetPlayerPublic(player.source, 'coreId', nil)
    player.characterId = nil
    player.character = nil
    player.rank = Permissions.DefaultId()
end

-- Nur speichern, wenn sich der Charakter bewegt hat. Wer AFK steht, kostet keine Datenbank-Abfrage.
local SAVE_MIN_DISTANCE = 2.0 -- Meter
local SAVE_SPREAD_MS = 50     -- hoechstens so viel Pause zwischen zwei Spielern, damit nicht alle im selben Moment schreiben
local SAVE_ROUND_SHARE = 0.5  -- eine Runde darf hoechstens die Haelfte des Intervalls dauern, auch bei sehr vielen Spielern

local function movedSinceSave(player)
    local saved = player.character and player.character.platformData.position
    local now = Platform.GetPlayerPosition(player.source)
    if not now then
        return false
    end
    if type(saved) ~= 'table' or not tonumber(saved.x) then
        return true
    end
    local dx, dy, dz = now.x - saved.x, now.y - saved.y, now.z - saved.z
    return dx * dx + dy * dy + dz * dz >= SAVE_MIN_DISTANCE * SAVE_MIN_DISTANCE
end

Platform.SetInterval(Config.Characters.SavePositionIntervalMs, function()
    local due = {}
    for _, player in pairs(Core.Players) do
        if player.characterId and movedSinceSave(player) then
            due[#due + 1] = player
        end
    end
    -- Viele Spieler: kuerzere Pause, damit die Runde fertig ist, bevor die naechste ansteht
    local pause = #due > 0 and math.min(SAVE_SPREAD_MS, math.floor(Config.Characters.SavePositionIntervalMs * SAVE_ROUND_SHARE / #due)) or 0
    for _, player in ipairs(due) do
        -- Kann inzwischen ausgeloggt sein
        if player.characterId then
            Characters.SavePosition(player)
        end
        Platform.Wait(pause)
    end
end)

------------------------------------------------------------------------
-- Callbacks (verlangen automatisch einen eingeloggten Spieler)
------------------------------------------------------------------------

local function listResponse(player, extra)
    local list = Characters.List(player.accountId)
    if not list then
        return { ok = false, error = 'db_error' }
    end
    local data = extra or {}
    data.characters = list
    return { ok = true, data = data }
end

local function alreadyPlaying(player)
    if player.characterId then
        return { ok = false, error = 'already_playing' }
    end
    return nil
end

Core.RegisterCallback('char_list', function(source)
    return listResponse(Core.GetPlayer(source))
end)

Core.RegisterCallback('char_create', function(source, data)
    local player = Core.GetPlayer(source)
    local blocked = alreadyPlaying(player)
    if blocked then return blocked end

    local characterId, err = Characters.Create(player, data)
    if not characterId then
        return { ok = false, error = err }
    end
    return listResponse(player, { characterId = characterId })
end)

Core.RegisterCallback('char_delete', function(source, data)
    local player = Core.GetPlayer(source)
    local blocked = alreadyPlaying(player)
    if blocked then return blocked end

    local ok, err = Characters.Delete(player, tonumber(data.id))
    if not ok then
        return { ok = false, error = err }
    end
    return listResponse(player)
end)

Core.RegisterCallback('char_select', function(source, data)
    local player = Core.GetPlayer(source)
    local blocked = alreadyPlaying(player)
    if blocked then return blocked end

    local spawn, err, ban = Characters.Select(player, tonumber(data.id))
    if not spawn then
        return { ok = false, error = err, data = ban and { ban = Bans.ToClient(ban) } or nil }
    end
    Platform.Print('info', ('%s spielt jetzt Charakter %d'):format(Platform.GetPlayerName(source), spawn.id))
    Moderation.DeliverWarnsLater(player)
    -- Fuer andere Resources (Inventar usw.)
    Platform.Emit('core:characterLoaded', source, Core.CharacterInfo(player))
    return { ok = true, data = spawn }
end)
