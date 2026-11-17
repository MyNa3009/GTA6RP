-- eSIM und Kontakte: Jeder Charakter hat genau eine Handynummer. Sie wird beim ersten Einloggen aktiviert
-- und bleibt, auch wenn das Geraet wechselt. Dazu Oeffnen des Handys (Startseite) und die Einstellungen.

if PhoneDisabled then
    return
end

Numbers = {}

local CFG = Config.Phone
local INVENTORY = 'core_inventory'
local BANK = 'core_bank'
local DISPATCH = 'core_dispatch'
local NUMBER_TRIES = 30
local STARTER_WAIT_MS = 1500   -- das Inventar laedt den Charakter auf dasselbe Ereignis hin

local cache = {}   -- [permanente ID] = { number, silent, airplane }

local function flag(value)
    return value == 1 or value == true
end

-- Nur Ziffern in der richtigen Laenge. Sonst nil.
function Numbers.Normalize(value)
    if type(value) == 'number' then
        value = ('%d'):format(value)
    end
    if type(value) ~= 'string' then
        return nil
    end
    value = value:gsub('%D', '')
    if #value ~= CFG.NumberDigits then
        return nil
    end
    return value
end

-- Nur Hintergruende aus der Config gelten, alles andere wird zum Standard (dem ersten)
local function wallpaperOf(value)
    for _, id in ipairs(CFG.Wallpapers) do
        if id == value then
            return id
        end
    end
    return CFG.Wallpapers[1]
end

-- eSIM eines Charakters: { number, silent, airplane, wallpaper } oder nil, wenn noch keine aktiviert ist
function Numbers.Get(characterId)
    if cache[characterId] then
        return cache[characterId]
    end
    local row = DB.Single('SELECT number, silent, airplane, wallpaper FROM phone_numbers WHERE character_id = ?', { characterId })
    if not row then
        return nil
    end
    cache[characterId] = { number = row.number, silent = flag(row.silent), airplane = flag(row.airplane), wallpaper = wallpaperOf(row.wallpaper) }
    return cache[characterId]
end

-- eSIM aktivieren, falls noch keine da ist. Gibt die eSIM und "neu angelegt" zurueck, nil wenn es den Charakter nicht gibt.
function Numbers.Ensure(characterId)
    local sim = Numbers.Get(characterId)
    if sim then
        return sim, false
    end
    if not Phone.NameOf(characterId) then
        return nil
    end
    local low, high = 10 ^ (CFG.NumberDigits - 1), 10 ^ CFG.NumberDigits - 1
    for _ = 1, NUMBER_TRIES do
        local candidate = ('%d'):format(math.random(math.floor(low), math.floor(high)))
        DB.Update('INSERT IGNORE INTO phone_numbers (character_id, number) VALUES (?, ?)', { characterId, candidate })
        sim = Numbers.Get(characterId)
        if sim then
            Phone.Log({ character_id = characterId, action = 'sim_activate', data = { number = sim.number } })
            return sim, true
        end
    end
    Platform.Print('error', ('core_phone: Fuer ID %d konnte keine freie Nummer gefunden werden.'):format(characterId))
    return nil
end

-- Wem gehoert die Nummer? Permanente ID oder nil.
function Numbers.Owner(number)
    number = Numbers.Normalize(number)
    return number and tonumber(DB.Scalar('SELECT character_id FROM phone_numbers WHERE number = ?', { number })) or nil
end

-- Beim Einloggen: eSIM aktivieren. Wer dabei noch kein Handy hat, bekommt einmal eins.
function Phone.OnLoaded(source, characterId)
    local sim, created = Numbers.Ensure(characterId)
    if not sim or not created or not CFG.StarterPhone or not CFG.Item or not Platform.IsResourceStarted(INVENTORY) then
        return
    end
    Platform.Wait(STARTER_WAIT_MS)
    if Phone.CharacterOf(source) ~= characterId or Phone.HasDevice(characterId) then
        return
    end
    if Platform.CallExport(INVENTORY, 'AddItem', characterId, CFG.Item, 1) then
        Phone.Log({ character_id = characterId, action = 'starter_phone', data = { item = CFG.Item } })
        Platform.Notify(source, ('Du hast ein Handy bekommen. Deine Nummer: %s. Öffnen mit %s.'):format(sim.number, CFG.Key), 'success')
    end
end

------------------------------------------------------------------------
-- Kontakte
------------------------------------------------------------------------

-- Wie hat characterId diese Nummer gespeichert? Name oder nil.
function Numbers.ContactName(characterId, number)
    return DB.Scalar('SELECT name FROM phone_contacts WHERE character_id = ? AND number = ?', { characterId, number })
end

function Numbers.Contacts(characterId)
    local list = {}
    for _, row in ipairs(DB.Query('SELECT id, name, number FROM phone_contacts WHERE character_id = ? ORDER BY name LIMIT ?', { characterId, CFG.MaxContacts }) or {}) do
        list[#list + 1] = { id = row.id, name = row.name, number = row.number }
    end
    return list
end

Phone.Register('phone_contact_save', { write = true }, function(source, data, ctx)
    local name = Phone.Text(data.name, CFG.ContactNameMax)
    local number = Numbers.Normalize(data.number)
    if not name then
        return { ok = false, error = 'invalid_name' }
    end
    if not number then
        return { ok = false, error = 'invalid_number' }
    end
    local id = tonumber(data.id)
    local same = tonumber(DB.Scalar('SELECT id FROM phone_contacts WHERE character_id = ? AND number = ?', { ctx.characterId, number }))
    if same and same ~= id then
        return { ok = false, error = 'contact_exists' }
    end
    if id then
        if DB.Scalar('SELECT id FROM phone_contacts WHERE id = ? AND character_id = ?', { math.floor(id), ctx.characterId }) == nil then
            return { ok = false, error = 'not_found' }
        end
        DB.Update('UPDATE phone_contacts SET name = ?, number = ? WHERE id = ? AND character_id = ?', { name, number, math.floor(id), ctx.characterId })
    else
        local count = tonumber(DB.Scalar('SELECT COUNT(*) FROM phone_contacts WHERE character_id = ?', { ctx.characterId })) or 0
        if count >= CFG.MaxContacts then
            return { ok = false, error = 'contacts_full' }
        end
        DB.Insert('INSERT INTO phone_contacts (character_id, number, name) VALUES (?, ?, ?)', { ctx.characterId, number, name })
    end
    return { ok = true, data = { contacts = Numbers.Contacts(ctx.characterId) } }
end)

Phone.Register('phone_contact_delete', { write = true }, function(source, data, ctx)
    local id = tonumber(data.id)
    local row = id and DB.Single('SELECT id, name, number FROM phone_contacts WHERE id = ? AND character_id = ?', { math.floor(id), ctx.characterId })
    if not row then
        return { ok = false, error = 'not_found' }
    end
    DB.Update('DELETE FROM phone_contacts WHERE id = ? AND character_id = ?', { row.id, ctx.characterId })
    Phone.Log({ character_id = ctx.characterId, action = 'contact_delete', data = { name = row.name, otherNumber = row.number } })
    return { ok = true, data = { contacts = Numbers.Contacts(ctx.characterId) } }
end)

------------------------------------------------------------------------
-- Handy oeffnen: alles fuer die Startseite
------------------------------------------------------------------------

local function apps()
    return {
        bank = CFG.Bank.Enabled and Platform.IsResourceStarted(BANK) or false,
        dispatch = CFG.Dispatch.Enabled and Platform.IsResourceStarted(DISPATCH) or false,
    }
end

function Numbers.Home(source, characterId, admin)
    local sim = Numbers.Get(characterId)
    if not sim then
        return nil
    end
    local threads, unread = Messages.Threads(characterId, admin)
    return {
        number = sim.number, name = Phone.NameOf(characterId), characterId = characterId,
        silent = sim.silent, airplane = sim.airplane, wallpaper = wallpaperOf(sim.wallpaper), wallpapers = CFG.Wallpapers,
        contacts = Numbers.Contacts(characterId), threads = threads, unread = unread,
        calls = Calls.List(characterId), missed = Calls.Missed(characterId),
        call = not admin and Calls.StateOf(source) or nil,
        apps = admin and { bank = false, dispatch = false } or apps(),
        admin = admin or nil,
        limits = { number = CFG.NumberDigits, name = CFG.ContactNameMax, message = CFG.MessageMax, contacts = CFG.MaxContacts },
        volume = CFG.Volume,
    }
end

-- data.characterId: Admin-Ansicht (nur lesen). Ohne: das eigene Handy.
Network.RegisterCallback('phone_open', function(source, data)
    local own = Phone.Ready and Phone.CharacterOf(source)
    if not own then
        return { ok = false, error = 'no_character' }
    end
    data = type(data) == 'table' and data or {}
    local subject = tonumber(data.characterId)
    if subject then
        subject = math.floor(subject)
        if Phone.Core('HasPermission', source, CFG.Admin.ViewPermission) ~= true then
            return { ok = false, error = 'no_permission' }
        end
        if not Numbers.Get(subject) then
            return { ok = false, error = 'not_found' }
        end
        Phone.SetViewing(source, subject)
        Phone.Log({ actor_account_id = Phone.Core('GetAccountId', source), character_id = subject, action = 'admin_view' })
        return { ok = true, data = Numbers.Home(source, subject, true) }
    end
    Phone.SetViewing(source, nil)
    if not CFG.AllowWhenDead and Phone.Core('IsDead', source) == true then
        return { ok = false, error = 'is_dead' }
    end
    if not Phone.HasDevice(own) then
        return { ok = false, error = 'no_phone' }
    end
    if not Numbers.Ensure(own) then
        return { ok = false, error = 'server_error' }
    end
    return { ok = true, data = Numbers.Home(source, own, false) }
end)

Network.RegisterCallback('phone_close', function(source)
    Phone.SetViewing(source, nil)
    return { ok = true }
end)

-- Startseite neu laden (nach einer Nachricht oder einem Anruf von aussen)
Phone.Register('phone_home', {}, function(source, data, ctx)
    local home = Numbers.Home(source, ctx.characterId, ctx.admin)
    if not home then
        return { ok = false, error = 'not_found' }
    end
    return { ok = true, data = home }
end)

Phone.Register('phone_settings', { write = true }, function(source, data, ctx)
    local sim = Numbers.Get(ctx.characterId)
    if not sim then
        return { ok = false, error = 'not_found' }
    end
    if type(data.silent) == 'boolean' then
        sim.silent = data.silent
    end
    if type(data.airplane) == 'boolean' then
        sim.airplane = data.airplane
    end
    if type(data.wallpaper) == 'string' then
        if wallpaperOf(data.wallpaper) ~= data.wallpaper then
            return { ok = false, error = 'invalid_wallpaper' }
        end
        sim.wallpaper = data.wallpaper
    end
    sim.wallpaper = wallpaperOf(sim.wallpaper)
    DB.Update('UPDATE phone_numbers SET silent = ?, airplane = ?, wallpaper = ? WHERE character_id = ?',
        { sim.silent and 1 or 0, sim.airplane and 1 or 0, sim.wallpaper, ctx.characterId })
    return { ok = true, data = { silent = sim.silent, airplane = sim.airplane, wallpaper = sim.wallpaper } }
end)

-- Handy im Inventar benutzt: beim Spieler oeffnen
Platform.OnEvent('core_inventory:itemUsed', function(source, characterId, name)
    if name == CFG.Item and Phone.CharacterOf(source) == tonumber(characterId) then
        Phone.Push(tonumber(characterId), { type = 'open' })
    end
end)

------------------------------------------------------------------------
-- Fuer andere Scripts
------------------------------------------------------------------------

-- Handynummer eines Charakters (nil, solange keine eSIM aktiviert ist)
Platform.Export('GetNumber', function(characterId)
    characterId = tonumber(characterId)
    local sim = characterId and Numbers.Get(characterId)
    return sim and sim.number or nil
end)
-- Permanente ID zur Nummer oder nil
Platform.Export('GetNumberOwner', Numbers.Owner)
-- Hat der Charakter (online) sein Handy dabei?
Platform.Export('HasPhone', function(characterId)
    characterId = tonumber(characterId)
    return characterId ~= nil and Phone.SourceOf(characterId) ~= nil and Phone.HasDevice(characterId)
end)
