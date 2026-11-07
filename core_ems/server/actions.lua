-- Aktionen der Mediziner aus dem G-Menue: Hochholen, Versorgen, Verkaufen, Untersuchen und Behandeln,
-- Krankenversicherung, Ausweis verlangen. Mediziner brauchen dafuer keinen Verbandskasten.
-- Dazu fuer alle anderen: mit einem gekauften Verbandskasten hochholen, oder ihn selbst benutzen.
-- Jede Aktion prueft: Mediziner im Dienst mit Recht, Ziel online und in Reichweite, Zustand (bewusstlos oder nicht).
-- Geld zahlt die Person nach ihrer Zustimmung, alles geht in die Kasse des Rettungsdiensts.

if EmsDisabled then
    return
end

local CFG = Config.Ems
local DEFS = CFG.Diseases
local DIAGNOSE_KEEP_MS = 120000

local SELL = {}
for _, entry in ipairs(CFG.Sell) do
    SELL[entry.item] = entry
end

local diagnosed = {}   -- [source] = { target, at }, damit Behandeln nicht ohne Untersuchung und Wartezeit geht

-- Preis mit Krankenversicherung (Behandlung und Verkauf)
local function discounted(price, insured)
    if insured then
        return math.floor(price * CFG.Insurance.InsuredFactor + 0.5)
    end
    return price
end

local function medicName(source)
    return Ems.NameOf(source) or 'Rettungsdienst'
end

local function accountOf(source)
    return Ems.Core('GetAccountId', source)
end

local function itemLabel(item)
    local defs = Ems.Inventory('GetItemDefs') or {}
    return defs[item] and defs[item].label or item
end

local function register(name, permission, handler)
    Network.RegisterCallback(name, function(source, data)
        if not Ems.Ready or not Ems.CharacterOf(source) then
            return { ok = false, error = 'no_character' }
        end
        if permission then
            local allowed, err = Ems.CanMedic(source, permission)
            if not allowed then
                return { ok = false, error = err }
            end
        end
        local ok, result = pcall(handler, source, type(data) == 'table' and data or {})
        if not ok then
            Platform.Print('error', ('core_ems: Fehler in %s: %s'):format(name, tostring(result)))
            return { ok = false, error = 'server_error' }
        end
        return result
    end)
end

------------------------------------------------------------------------
-- Hochholen
------------------------------------------------------------------------

local FAIL_TEXT = {
    minigame_failed = 'Das hat nicht geklappt. Versuch es nochmal.',
    too_far = 'Die Person ist zu weit weg.',
    not_dead = 'Die Person ist nicht bewusstlos.',
    hospital_only = 'Die Person muss ins Krankenhaus, vor Ort geht das nicht.',
    no_medkit = 'Du brauchst einen Verbandskasten. Den verkauft der Rettungsdienst.',
    is_dead = 'Die Person ist bewusstlos. Erst hochholen.',
}

local function fail(source, code)
    Platform.Notify(source, FAIL_TEXT[code] or 'Das hat nicht geklappt.', 'error')
end

-- Pruefen und sofort antworten, das Minigame laeuft danach im Hintergrund (kann laenger dauern als eine Anfrage)
register('ems_revive', 'ems.revive', function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    local dead, hospitalOnly = Ems.Core('IsDead', target)
    if not dead then
        return { ok = false, error = 'not_dead' }
    end
    if hospitalOnly then
        return { ok = false, error = 'hospital_only' }
    end
    if not Ems.Lock(target) then
        return { ok = false, error = 'target_busy' }
    end
    Platform.Async(function()
        local success = lib.minigame(source, 'skillcheck', { difficulty = CFG.Revive.Difficulty, keys = CFG.Revive.Keys })
        Ems.Unlock(target)
        if not success then
            return fail(source, 'minigame_failed')
        end
        -- Nach dem Minigame neu pruefen: noch da, noch in Reichweite?
        if not Ems.CharacterOf(target) or not Ems.Near(source, target, CFG.TargetDistance) then
            return fail(source, 'too_far')
        end
        local ok, reviveError = Ems.Core('Revive', target, accountOf(source), 'Rettungsdienst')
        if not ok then
            return fail(source, reviveError or 'not_dead')
        end
        Ems.Record(Ems.CharacterOf(target), 'revive', 'Vor Ort hochgeholt', medicName(source))
        Ems.Log({ actor_account_id = accountOf(source), character_id = Ems.CharacterOf(target), action = 'revive', data = { medic = Ems.CharacterOf(source) } })
        Platform.Notify(target, 'Der Rettungsdienst hat dich hochgeholt.', 'success')
        Platform.Notify(source, 'Person hochgeholt.', 'success')
    end)
    return { ok = true }
end)

------------------------------------------------------------------------
-- Versorgen (Mediziner, ohne Verbandskasten)
------------------------------------------------------------------------

register('ems_heal', 'ems.heal', function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    if Ems.Core('IsDead', target) then
        return { ok = false, error = 'is_dead' }
    end
    if not Ems.Lock(target) then
        return { ok = false, error = 'target_busy' }
    end
    Platform.Async(function()
        local success = lib.minigame(source, 'skillcheck', { difficulty = CFG.Heal.Difficulty, keys = CFG.Heal.Keys })
        Ems.Unlock(target)
        if not success then
            return fail(source, 'minigame_failed')
        end
        if not Ems.CharacterOf(target) or not Ems.Near(source, target, CFG.TargetDistance) then
            return fail(source, 'too_far')
        end
        if Ems.Core('IsDead', target) then
            return fail(source, 'is_dead')
        end
        Ems.Core('Heal', target, CFG.Heal.Amount)
        Ems.Record(Ems.CharacterOf(target), 'heal', 'Verletzungen versorgt', medicName(source))
        Ems.Log({ actor_account_id = accountOf(source), character_id = Ems.CharacterOf(target), action = 'heal', data = { medic = Ems.CharacterOf(source) } })
        Platform.Notify(target, 'Der Rettungsdienst hat dich versorgt.', 'success')
        Platform.Notify(source, 'Person versorgt.', 'success')
    end)
    return { ok = true }
end)

------------------------------------------------------------------------
-- Verbandskasten (alle, die keine Mediziner sind)
------------------------------------------------------------------------

local function medkitCount(source)
    return tonumber(Ems.Inventory('GetItemCount', Ems.CharacterOf(source), 'medkit')) or 0
end

-- Mit einem Verbandskasten eine bewusstlose Person hochholen. Kein Recht noetig, aber ein Verbandskasten.
-- Nach einem Zusammenbruch durch Krankheit geht das nicht (nur Krankenhaus).
register('ems_medkit_revive', nil, function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    local dead, hospitalOnly = Ems.Core('IsDead', target)
    if not dead then
        return { ok = false, error = 'not_dead' }
    end
    if hospitalOnly then
        return { ok = false, error = 'hospital_only' }
    end
    if medkitCount(source) < 1 then
        return { ok = false, error = 'no_medkit' }
    end
    if not Ems.Lock(target) then
        return { ok = false, error = 'target_busy' }
    end
    Platform.Async(function()
        local success = lib.minigame(source, 'skillcheck', { difficulty = CFG.Medkit.Difficulty, keys = CFG.Medkit.Keys })
        Ems.Unlock(target)
        if not success then
            return Platform.Notify(source, 'Das hat nicht geklappt. Der Verbandskasten ist noch da.', 'error')
        end
        if not Ems.CharacterOf(target) or not Ems.Near(source, target, CFG.TargetDistance) then
            return fail(source, 'too_far')
        end
        if not Ems.Inventory('RemoveItem', Ems.CharacterOf(source), 'medkit', 1) then
            return fail(source, 'no_medkit')
        end
        local ok, reviveError = Ems.Core('Revive', target, accountOf(source), 'Verbandskasten')
        if not ok then
            -- Kasten zurueck, wenn das Hochholen doch nicht ging (z. B. inzwischen im Krankenhaus)
            Ems.Inventory('AddItem', Ems.CharacterOf(source), 'medkit', 1)
            return fail(source, reviveError or 'not_dead')
        end
        local helper = Ems.NameOf(source)
        Ems.Record(Ems.CharacterOf(target), 'revive', 'Mit Verbandskasten hochgeholt', helper)
        Ems.Log({ actor_account_id = accountOf(source), character_id = Ems.CharacterOf(target), action = 'medkit_revive',
            data = { helper = Ems.CharacterOf(source) } })
        Platform.Notify(target, 'Jemand hat dich mit einem Verbandskasten hochgeholt.', 'success')
        Platform.Notify(source, 'Person hochgeholt. Der Verbandskasten ist verbraucht.', 'success')
    end)
    return { ok = true }
end)

-- Selbst benutzt (Inventar): Minigame, dann heilen. Ohne Erfolg bleibt der Kasten im Inventar.
local function useMedkitSelf(source)
    if medkitCount(source) < 1 then
        return false, 'no_medkit'
    end
    if not lib.minigame(source, 'skillcheck', { difficulty = CFG.Medkit.Difficulty, keys = CFG.Medkit.Keys }) then
        return false, 'minigame_failed'
    end
    if Ems.Core('IsDead', source) then
        return false, 'is_dead'
    end
    if not Ems.Inventory('RemoveItem', Ems.CharacterOf(source), 'medkit', 1) then
        return false, 'no_medkit'
    end
    Ems.Core('Heal', source, CFG.Medkit.HealSelf)
    Ems.Record(Ems.CharacterOf(source), 'medkit', 'Verbandskasten selbst angewendet')
    return true
end

local selfBusy = {}
Platform.OnEvent('core_inventory:itemUsed', function(source, characterId, item)
    if item ~= 'medkit' or selfBusy[source] then
        return
    end
    selfBusy[source] = true
    Platform.Async(function()
        local ok, err = useMedkitSelf(source)
        selfBusy[source] = nil
        if ok then
            Platform.Notify(source, 'Du hast dich verarztet.', 'success')
        elseif err == 'minigame_failed' then
            Platform.Notify(source, 'Das hat nicht geklappt. Der Verbandskasten ist noch da.', 'error')
        end
    end)
end)

------------------------------------------------------------------------
-- Verkaufen
------------------------------------------------------------------------

register('ems_sell_list', 'ems.sell', function()
    local list = {}
    for _, entry in ipairs(CFG.Sell) do
        list[#list + 1] = { item = entry.item, label = itemLabel(entry.item), price = entry.price }
    end
    return { ok = true, data = { items = list, max = CFG.SellMaxCount } }
end)

register('ems_sell', 'ems.sell', function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    local entry = SELL[data.item]
    local count = tonumber(data.count)
    if not entry or not count or count ~= math.floor(count) or count < 1 or count > CFG.SellMaxCount then
        return { ok = false, error = 'invalid_input' }
    end
    local label = itemLabel(entry.item)
    local insured = Ems.InsuredUntil(Ems.CharacterOf(target)) ~= nil
    local total = discounted(entry.price * count, insured)
    local accepted, consentError = Ems.Consent(source, target, ('Willst du %dx %s für %s kaufen?'):format(count, label, Ems.Money(total)),
        insured and 'Mit Krankenversicherung günstiger.' or 'Der Rettungsdienst verkauft dir etwas.')
    if not accepted then
        return { ok = false, error = consentError }
    end
    if not Ems.Near(source, target, CFG.TargetDistance) then
        return { ok = false, error = 'too_far' }
    end
    local reason = ('Rettungsdienst: %dx %s'):format(count, label)
    local account, payError = Ems.Pay(target, total, reason)
    if not account then
        return { ok = false, error = payError }
    end
    local added, addError = Ems.Inventory('AddItem', Ems.CharacterOf(target), entry.item, count)
    if not added then
        Ems.Refund(target, account, total, reason)
        Platform.Print('warn', ('core_ems: Verkauf an ID %s fehlgeschlagen: %s'):format(tostring(Ems.CharacterOf(target)), tostring(addError)))
        return { ok = false, error = 'target_full' }
    end
    Ems.ToCash(total, reason, source, { item = entry.item, count = count, buyer = Ems.CharacterOf(target) })
    Ems.Log({ actor_account_id = accountOf(source), character_id = Ems.CharacterOf(target), action = 'sell',
        amount = total, data = { item = entry.item, count = count, medic = Ems.CharacterOf(source), account = account } })
    Platform.Notify(target, ('Du hast %dx %s für %s gekauft.'):format(count, label, Ems.Money(total)), 'success')
    return { ok = true, data = { total = total } }
end)

------------------------------------------------------------------------
-- Untersuchen und Behandeln
------------------------------------------------------------------------

local function priceFor(disease, insured)
    return discounted(DEFS[disease].price or 0, insured)
end

register('ems_diagnose', 'ems.treat', function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    if Ems.Core('IsDead', target) then
        return { ok = false, error = 'is_dead' }
    end
    local characterId = Ems.CharacterOf(target)
    local insured = Ems.InsuredUntil(characterId)
    local list = {}
    for _, entry in ipairs(Diseases.Active(characterId)) do
        local def = DEFS[entry.disease]
        list[#list + 1] = {
            disease = entry.disease,
            label = def.label,
            stage = entry.stage,
            stages = def.cure == 'treatment' and def.stages - 1 or def.stages,
            cure = def.cure,
            series = entry.series,
            needed = def.treatments,
            waitMinutes = entry.gapLeft > 0 and def.cure == 'treatment' and math.ceil(entry.gapLeft / 60) or nil,
            price = priceFor(entry.disease, insured ~= nil),
        }
    end
    diagnosed[source] = { target = target, at = Platform.GetTime() }
    local names = {}
    for _, entry in ipairs(list) do
        names[#names + 1] = Diseases.StageText(DEFS[entry.disease], entry.stage)
    end
    Ems.Record(characterId, 'diagnosis', #names > 0 and ('Untersucht: %s'):format(table.concat(names, '; ')) or 'Untersucht: ohne Befund', medicName(source))
    return { ok = true, data = { diseases = list, insured = insured, treatMs = CFG.TreatDurationMs } }
end)

register('ems_treat', 'ems.treat', function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    local diagnosis = diagnosed[source]
    local now = Platform.GetTime()
    if not diagnosis or diagnosis.target ~= target or now - diagnosis.at > DIAGNOSE_KEEP_MS then
        return { ok = false, error = 'not_diagnosed' }
    end
    -- Der Fortschrittsbalken beim Mediziner muss gelaufen sein
    if now - diagnosis.at < CFG.TreatDurationMs then
        return { ok = false, error = 'too_fast' }
    end
    local characterId = Ems.CharacterOf(target)
    local disease = type(data.disease) == 'string' and data.disease or nil
    if not disease or not DEFS[disease] or not Diseases.Find(characterId, disease) then
        return { ok = false, error = 'not_sick' }
    end
    local price = priceFor(disease, Ems.InsuredUntil(characterId) ~= nil)
    local label = DEFS[disease].label
    local accepted, consentError = Ems.Consent(source, target, ('Behandlung gegen %s für %s?'):format(label, Ems.Money(price)),
        price > 0 and 'Mit Krankenversicherung zahlst du weniger.' or 'Kostenlos.')
    if not accepted then
        return { ok = false, error = consentError }
    end
    local reason = ('Rettungsdienst: Behandlung %s'):format(label)
    local account, payError = Ems.Pay(target, price, reason)
    if not account then
        return { ok = false, error = payError }
    end
    local treated, result, extra = Diseases.Treat(characterId, disease, medicName(source))
    if not treated then
        Ems.Refund(target, account, price, reason)
        return { ok = false, error = result, data = extra }
    end
    diagnosed[source] = nil
    Ems.ToCash(price, reason, source, { disease = disease, patient = characterId })
    Ems.Log({ actor_account_id = accountOf(source), character_id = characterId, action = 'treat', amount = price,
        data = { disease = disease, result = result, medic = Ems.CharacterOf(source) } })
    if not result.cured then
        Platform.Notify(target, ('Behandlung %d von %d gegen %s. Komm in der nächsten Stunde wieder.'):format(result.series, result.needed, label), 'info')
    end
    return { ok = true, data = result }
end)

------------------------------------------------------------------------
-- Krankenversicherung
------------------------------------------------------------------------

register('ems_insurance', 'ems.insurance', function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    local characterId = Ems.CharacterOf(target)
    local current = Ems.InsuredUntil(characterId)
    local price, days = CFG.Insurance.Price, CFG.Insurance.Days
    local accepted, consentError = Ems.Consent(source, target, ('Krankenversicherung für %d Tage, %s?'):format(days, Ems.Money(price)),
        current and ('Gilt noch bis %s, wird verlängert.'):format(current) or 'Behandlungen werden damit günstiger.')
    if not accepted then
        return { ok = false, error = consentError }
    end
    local reason = 'Rettungsdienst: Krankenversicherung'
    local account, payError = Ems.Pay(target, price, reason)
    if not account then
        return { ok = false, error = payError }
    end
    local name = medicName(source)
    DB.Update('INSERT INTO ems_insurance (character_id, valid_until, sold_by) VALUES (?, DATE_ADD(NOW(), INTERVAL ? DAY), ?) ON DUPLICATE KEY UPDATE valid_until = DATE_ADD(GREATEST(valid_until, NOW()), INTERVAL ? DAY), sold_by = VALUES(sold_by), sold_at = CURRENT_TIMESTAMP',
        { characterId, days, name, days })
    local untilDate = Ems.InsuredUntil(characterId)
    Ems.Record(characterId, 'insurance', ('Krankenversicherung bis %s'):format(untilDate or '?'), name)
    Ems.ToCash(price, reason, source, { patient = characterId })
    Ems.Log({ actor_account_id = accountOf(source), character_id = characterId, action = 'insurance', amount = price,
        data = { days = days, validUntil = untilDate, medic = Ems.CharacterOf(source) } })
    Platform.Notify(target, ('Du bist jetzt bis %s krankenversichert.'):format(untilDate or '?'), 'success')
    return { ok = true, data = { validUntil = untilDate } }
end)

------------------------------------------------------------------------
-- Ausweis verlangen: die Person entscheidet, ob sie ihn zeigt
------------------------------------------------------------------------

register('ems_request_id', 'ems.records', function(source, data)
    local target, err = Ems.Target(source, data)
    if not target then
        return { ok = false, error = err }
    end
    local accepted, consentError = Ems.Consent(source, target, 'Willst du deinen Personalausweis zeigen?', 'Der Rettungsdienst möchte ihn sehen.')
    if not accepted then
        return { ok = false, error = consentError }
    end
    local shown, showError = Ems.Inventory('ShowDocument', target, 'id', source, { skipConsent = true })
    if not shown then
        return { ok = false, error = showError == 'no_document' and 'no_id_card' or (showError or 'server_error') }
    end
    return { ok = true }
end)

Platform.OnEvent('core:characterUnloaded', function(source)
    diagnosed[tonumber(source) or source] = nil
end)
