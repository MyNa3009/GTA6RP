-- Admin-Befehle fuer Organisationen. Pruefung des Rechts und Log macht die Core (AuthorizeCommand).
--   /setorga <ID> <orga> <rang>    einstellen oder Rang setzen, auch den Leader (factions.manage)
--   /removeorga <ID> [grund]       aus der Organisation entfernen, kommt ins Archiv (factions.manage)
--   /orgaview <orga>               Organisationsmenue einer Organisation ansehen (factions.view, mit factions.manage bearbeiten)

if FactionsDisabled then
    return
end

local CORE = 'core'
local CONSOLE = 0

local function authorize(source, name, permission, args)
    return Platform.CallExport(CORE, 'AuthorizeCommand', source, name, permission, args, false)
end

local function adminActor(source, accountId)
    local name = source ~= CONSOLE and Factions.NameOf(source) or 'Konsole'
    return { source = source, characterId = Factions.CharacterOf(source), name = ('Admin %s'):format(name or ''), accountId = accountId, admin = true }
end

local function orgList()
    local ids = {}
    for id in pairs(Orgs) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return table.concat(ids, ', ')
end

local ERRORS = {
    already_member = 'Die Person ist schon in einer anderen Organisation. Erst mit /removeorga entfernen.',
    unknown_character = 'Diesen Charakter gibt es nicht.',
    invalid_rank = 'Diesen Rang gibt es in der Organisation nicht.',
    not_member = 'Die Person ist in keiner Organisation.',
    db_error = 'Datenbankfehler, siehe Serverkonsole.',
}

Platform.RegisterCommand('setorga', function(source, args)
    local allowed, accountId = authorize(source, 'setorga', 'factions.manage', args)
    if not allowed then
        return
    end
    local characterId, faction, rank = tonumber(args[1]), args[2] and args[2]:lower(), tonumber(args[3])
    local org = Factions.Org(faction)
    if not characterId or not org or not rank then
        Platform.Notify(source, ('Benutzung: /setorga <ID> <orga> <rang>. Organisationen: %s'):format(orgList()), 'error')
        return
    end
    local member = Factions.GetMember(characterId)
    local ok, err
    if member and member.faction == faction then
        ok, err = Members.SetRank(faction, characterId, rank, adminActor(source, accountId))
    else
        ok, err = Members.Hire(faction, characterId, rank, adminActor(source, accountId))
    end
    if not ok then
        Platform.Notify(source, ERRORS[err] or ('Das hat nicht geklappt (%s).'):format(tostring(err)), 'error')
        return
    end
    Platform.Notify(source, ('ID %d ist jetzt %s bei %s.'):format(characterId, Factions.RankName(faction, rank), org.short), 'success')
end)

Platform.RegisterCommand('removeorga', function(source, args)
    local allowed, accountId = authorize(source, 'removeorga', 'factions.manage', args)
    if not allowed then
        return
    end
    local characterId = tonumber(args[1])
    local member = characterId and Factions.GetMember(characterId)
    if not member then
        Platform.Notify(source, characterId and ERRORS.not_member or 'Benutzung: /removeorga <ID> [Grund]', 'error')
        return
    end
    local reason = table.concat(args, ' ', 2)
    local ok, err = Members.Remove(member.faction, characterId, 'admin', reason ~= '' and reason or 'Vom Admin entfernt', adminActor(source, accountId))
    if not ok then
        Platform.Notify(source, ERRORS[err] or ('Das hat nicht geklappt (%s).'):format(tostring(err)), 'error')
        return
    end
    Platform.Notify(source, ('ID %d aus %s entfernt.'):format(characterId, Orgs[member.faction].short), 'success')
end)

Platform.RegisterCommand('orgaview', function(source, args)
    if source == CONSOLE then
        return
    end
    local allowed = authorize(source, 'orgaview', 'factions.view', args)
    if not allowed then
        return
    end
    local faction = args[1] and args[1]:lower()
    if not Factions.Org(faction) then
        Platform.Notify(source, ('Benutzung: /orgaview <orga>. Organisationen: %s'):format(orgList()), 'error')
        return
    end
    local manage = Platform.CallExport(CORE, 'HasPermission', source, 'factions.manage') == true
    FactionMenu.OpenAsAdmin(source, faction, manage)
    Network.SendToClient(source, 'core_factions:open_admin', { faction = faction })
end)

-- In der Befehlsliste des Admin-Menues zeigen
DB.Ready(function()
    Platform.CallExport(CORE, 'AddCommandHelp', {
        title = 'Organisationen',
        entries = {
            { usage = '/orgaview ems', text = 'Organisationsmenü einer Organisation ansehen. Mit factions.manage auch bearbeiten wie der Leader.', permission = 'factions.view' },
            { usage = '/setorga 17 ems 30', text = 'Person einstellen oder Rang setzen, auch den Leader. Die Person muss nicht online sein.', permission = 'factions.manage' },
            { usage = '/removeorga 17 Grund', text = 'Person aus ihrer Organisation entfernen. Sie kommt ins Archiv.', permission = 'factions.manage' },
        },
    })
end)
