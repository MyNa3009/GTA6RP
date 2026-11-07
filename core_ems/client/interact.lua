-- Eintraege im G-Menue unter Rettungsdienst. Nur im Dienst und nur mit Recht sichtbar (Stand von core_factions).
-- Ziel ist immer die Person, die man anschaut.
--   Rettungsdienst/Hochholen                    bewusstlose Person, Skillcheck mit Z
--   Rettungsdienst/Versorgen                    wache Person, Minigame, heilt (ohne Verbandskasten)
--   Person/Hochholen                            fuer alle anderen: bewusstlose Person, verbraucht einen Verbandskasten
--   Rettungsdienst/Untersuchen und behandeln    zeigt die Krankheiten, Behandlung nach Zustimmung
--   Rettungsdienst/Verkaufen                    Verbände, Kästen, Tabletten
--   Rettungsdienst/Krankenversicherung          verkaufen oder verlängern
--   Rettungsdienst/Ausweis verlangen            die Person entscheidet, ob sie ihn zeigt
--   Rettungsdienst/Medizinische Datenbank       ohne Ziel

if EmsDisabled then
    return
end

local CATEGORY = 'Rettungsdienst'

local function can(key)
    return function()
        return EmsClient.Can(key)
    end
end

-- Ist die angeschaute Person bewusstlos? (nur Anzeige)
local function targetDead(ctx)
    local ped = ctx.player and Platform.GetPlayerPedByServerId(ctx.player.serverId)
    local status = ped and Platform.GetPedStatus(ped)
    return status ~= nil and status.dead == true
end

local function canWithTarget(key, wantDead)
    return function(ctx)
        return EmsClient.Can(key) and targetDead(ctx) == wantDead
    end
end

local function money(amount)
    local text = tostring(math.floor(amount)):reverse():gsub('(%d%d%d)', '%1.'):reverse()
    return (text:gsub('^%.', '')) .. ' $'
end

lib.setInteractionCategory(CATEGORY, { icon = 'heart-pulse', order = 25 })

lib.addInteraction({
    id = 'revive',
    path = CATEGORY,
    label = 'Hochholen',
    description = 'Taste Z im markierten Bereich',
    icon = 'heart-pulse',
    order = 10,
    target = 'player',
    canShow = canWithTarget('ems.revive', true),
    onSelect = function(ctx)
        EmsClient.Call('ems_revive', { serverId = ctx.player.serverId })
    end,
})

lib.addInteraction({
    id = 'heal',
    path = CATEGORY,
    label = 'Versorgen',
    description = 'Heilt Verletzungen, Taste E im markierten Bereich',
    icon = 'package',
    order = 20,
    target = 'player',
    canShow = canWithTarget('ems.heal', false),
    onSelect = function(ctx)
        EmsClient.Call('ems_heal', { serverId = ctx.player.serverId })
    end,
})

-- Fuer alle, die nicht als Mediziner hochholen koennen. Ob ein Verbandskasten da ist, prueft der Server
-- und sagt sonst, wo es einen gibt.
lib.addInteraction({
    id = 'medkit_revive',
    path = 'Person',
    label = 'Hochholen',
    description = 'Verbraucht einen Verbandskasten, Taste Z',
    icon = 'heart-pulse',
    order = 5,
    target = 'player',
    canShow = function(ctx)
        return targetDead(ctx) and not EmsClient.Can('ems.revive')
    end,
    onSelect = function(ctx)
        EmsClient.Call('ems_medkit_revive', { serverId = ctx.player.serverId })
    end,
})

local function stageText(entry)
    return ('Stadium %d von %d'):format(entry.stage, entry.stages)
end

local function treat(ctx, entry, treatMs)
    local done = lib.progressBar({ label = ('Behandlung: %s'):format(entry.label), duration = treatMs, canCancel = true,
        anim = SymptomData.treatAnim, disable = { move = true, combat = true } })
    if not done then
        return
    end
    local result = EmsClient.Call('ems_treat', { serverId = ctx.player.serverId, disease = entry.disease })
    if not result then
        return
    end
    if result.cured then
        EmsClient.Notify(('%s geheilt.'):format(entry.label), 'success')
    else
        EmsClient.Notify(('Behandlung %d von %d. Die nächste in frühestens 10 Minuten, innerhalb einer Stunde.'):format(result.series, result.needed), 'success')
    end
end

lib.addInteraction({
    id = 'treat',
    path = CATEGORY,
    label = 'Untersuchen und behandeln',
    description = 'Zeigt Krankheiten und Preise',
    icon = 'search',
    order = 30,
    target = 'player',
    canShow = canWithTarget('ems.treat', false),
    onSelect = function(ctx)
        local data = EmsClient.Call('ems_diagnose', { serverId = ctx.player.serverId })
        if not data then
            return
        end
        local options = {}
        if data.insured then
            options[#options + 1] = { title = 'Krankenversichert', description = ('Bis %s, Behandlungen günstiger'):format(data.insured), readOnly = true }
        end
        if #data.diseases == 0 then
            options[#options + 1] = { title = 'Ohne Befund', description = 'Die Person ist gesund.', readOnly = true }
        end
        for _, entry in ipairs(data.diseases) do
            local detail = stageText(entry)
            if entry.cure == 'treatment' then
                detail = ('%s · Behandlung %d von %d'):format(detail, entry.series, entry.needed)
            else
                detail = ('%s · Tablette hilft auch'):format(detail)
            end
            options[#options + 1] = {
                title = ('%s · %s'):format(entry.label, money(entry.price)),
                description = entry.waitMinutes and ('%s · nächste in %d Min.'):format(detail, entry.waitMinutes) or detail,
                icon = 'heart-pulse',
                disabled = entry.waitMinutes ~= nil,
                onSelect = function(chosen)
                    Platform.Async(function()
                        treat(ctx, chosen, data.treatMs)
                    end)
                end,
                args = entry,
            }
        end
        lib.registerContext({ id = 'core_ems_treat', title = ('Befund ID %d'):format(ctx.player.characterId), options = options })
        lib.showContext('core_ems_treat')
    end,
})

lib.addInteraction({
    id = 'sell',
    path = CATEGORY,
    label = 'Verkaufen',
    description = 'Verbände, Verbandskästen, Tabletten',
    icon = 'banknote',
    order = 40,
    target = 'player',
    canShow = can('ems.sell'),
    onSelect = function(ctx)
        local data = EmsClient.Call('ems_sell_list', {})
        if not data then
            return
        end
        local options = {}
        for _, entry in ipairs(data.items) do
            options[#options + 1] = { value = entry.item, label = ('%s · %s'):format(entry.label, money(entry.price)) }
        end
        local values = lib.inputDialog(('Verkaufen an ID %d'):format(ctx.player.characterId), {
            { type = 'select', label = 'Was', required = true, options = options },
            { type = 'number', label = 'Anzahl', required = true, min = 1, max = data.max, default = 1 },
        }, { confirmLabel = 'Anbieten' })
        if not values or not values[1] or not values[2] then
            return
        end
        local result = EmsClient.Call('ems_sell', { serverId = ctx.player.serverId, item = values[1], count = values[2] })
        if result then
            EmsClient.Notify(('Verkauft für %s. Das Geld geht in die Kasse.'):format(money(result.total)), 'success')
        end
    end,
})

lib.addInteraction({
    id = 'insurance',
    path = CATEGORY,
    label = 'Krankenversicherung',
    description = 'Verkaufen oder verlängern',
    icon = 'shield',
    order = 50,
    target = 'player',
    canShow = can('ems.insurance'),
    onSelect = function(ctx)
        local result = EmsClient.Call('ems_insurance', { serverId = ctx.player.serverId })
        if result then
            EmsClient.Notify(('Versichert bis %s.'):format(result.validUntil or '?'), 'success')
        end
    end,
})

lib.addInteraction({
    id = 'request_id',
    path = CATEGORY,
    label = 'Ausweis verlangen',
    description = 'Für die Medizinische Datenbank',
    icon = 'id-card',
    order = 60,
    target = 'player',
    canShow = can('ems.records'),
    onSelect = function(ctx)
        EmsClient.Call('ems_request_id', { serverId = ctx.player.serverId })
    end,
})

lib.addInteraction({
    id = 'records',
    path = CATEGORY,
    label = 'Medizinische Datenbank',
    description = 'Akten, Versicherung, Verlauf',
    icon = 'file',
    order = 70,
    canShow = can('ems.records'),
    onSelect = function(ctx)
        EmsClient.OpenRecords(nil)
    end,
})
