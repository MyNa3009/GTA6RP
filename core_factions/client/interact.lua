-- Eintraege im G-Menue unter Organisation. Sichtbar ist nur, wofuer man Rechte hat (Stand vom Server).
--   Organisation/Organisationsmenü            eigenes Menue mit den 5 Tabs
--   Organisation/Leitung/Einstellen           angeschaute Person (Recht members.hire, sie muss zustimmen)
--   Organisation/Leitung/Befördern            angeschaute Person (Recht members.rank)
--   Organisation/Leitung/Degradieren          angeschaute Person (Recht members.rank)
--   Organisation/Leitung/Entlassen            angeschaute Person (Recht members.fire, mit Grund)
--   Organisation/Kündigen                     selbst austreten (nicht der Leader)

if FactionsDisabled then
    return
end

local CFG = Config.Factions

local function isMember()
    return FactionClient.state.member == true
end

local function can(key)
    return function()
        return FactionClient.Can(key)
    end
end

local function call(name, data)
    local result = Network.Call(name, data)
    if not result or not result.ok then
        FactionClient.Error(result and result.error)
        return nil
    end
    return result
end

lib.setInteractionCategory('Organisation/Leitung', { icon = 'crown', order = 20 })

lib.addInteraction({
    id = 'menu',
    path = 'Organisation',
    label = 'Organisationsmenü',
    description = 'Übersicht, Leitstelle, Ränge und Archiv',
    icon = 'list',
    order = 10,
    canShow = isMember,
    onSelect = function()
        FactionClient.OpenMenu(false)
    end,
})

lib.addInteraction({
    id = 'hire',
    path = 'Organisation/Leitung',
    label = 'Einstellen',
    description = 'Die Person muss zustimmen',
    icon = 'user-plus',
    order = 10,
    target = 'player',
    canShow = can('members.hire'),
    onSelect = function(ctx)
        if call('faction_target_hire', { serverId = ctx.player.serverId }) then
            FactionClient.Notify(('ID %d eingestellt.'):format(ctx.player.characterId), 'success')
        end
    end,
})

for _, entry in ipairs({ { id = 'promote', label = 'Befördern', icon = 'arrow-up', delta = 1, order = 20 },
    { id = 'demote', label = 'Degradieren', icon = 'arrow-down', delta = -1, order = 30 } }) do
    lib.addInteraction({
        id = entry.id,
        path = 'Organisation/Leitung',
        label = entry.label,
        description = 'Nur Mitglieder unter deinem Rang',
        icon = entry.icon,
        order = entry.order,
        target = 'player',
        canShow = can('members.rank'),
        onSelect = function(ctx)
            local result = call('faction_target_rank', { serverId = ctx.player.serverId, delta = entry.delta })
            if result then
                FactionClient.Notify(('ID %d ist jetzt %s.'):format(ctx.player.characterId, result.data.rankName), 'success')
            end
        end,
    })
end

lib.addInteraction({
    id = 'fire',
    path = 'Organisation/Leitung',
    label = 'Entlassen',
    description = 'Kommt mit Grund ins Archiv',
    icon = 'user-minus',
    order = 40,
    target = 'player',
    canShow = can('members.fire'),
    onSelect = function(ctx)
        local values = lib.inputDialog(('ID %d entlassen'):format(ctx.player.characterId), {
            { type = 'input', label = 'Grund', required = true, maxLength = CFG.TextMax.reason,
              description = 'Steht im Mitarbeiter-Archiv.' },
        }, { confirmLabel = 'Entlassen', danger = true })
        if not values or not values[1] then
            return
        end
        if call('faction_target_fire', { serverId = ctx.player.serverId, reason = values[1] }) then
            FactionClient.Notify(('ID %d entlassen.'):format(ctx.player.characterId), 'success')
        end
    end,
})

lib.addInteraction({
    id = 'leave',
    path = 'Organisation',
    label = 'Kündigen',
    description = 'Selbst austreten',
    icon = 'arrow-left',
    order = 90,
    canShow = function()
        return isMember() and not FactionClient.state.isLeader
    end,
    onSelect = function()
        local state = FactionClient.state
        local answer = lib.alertDialog({
            header = ('%s verlassen?'):format(state.label),
            content = 'Rang, Dienstausweis und Zugriff auf die Fahrzeuge gehen verloren. Du kommst ins Mitarbeiter-Archiv.',
            confirmLabel = 'Kündigen',
            danger = true,
        })
        if answer == 'confirm' and call('faction_leave', {}) then
            FactionClient.Notify(('Du hast bei %s gekündigt.'):format(state.label), 'info')
        end
    end,
})
