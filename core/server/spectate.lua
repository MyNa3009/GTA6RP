-- Beobachten (/spec <ID>): der Admin wird unsichtbar und sieht durch die Augen des Spielers.
-- Danach geht es zurueck an die alte Stelle und in die alte Dimension. Start und Ende stehen in der Akte des Beobachteten.

Spectate = {}

local CONSOLE = 0
local EVENT = 'core:admin:spectate'
local PERMISSION = 'player.spectate'

local ERRORS = {
    no_permission = 'Dafür hast du keine Rechte.',
    duty_required = 'Das geht nur im Admin-Dienst. Starte ihn mit /aduty.',
    no_character = 'Das geht nur mit einem Charakter.',
    target_offline = 'Niemand mit dieser permanenten ID ist gerade im Spiel.',
    self = 'Dich selbst kannst du nicht beobachten.',
    jailed = 'Im A-Jail geht das nicht.',
    frozen = 'Eingefroren geht das nicht.',
    no_position = 'Deine Position konnte nicht gelesen werden.',
}
Spectate.ERRORS = ERRORS

local function nameOf(player)
    local character = player and player.character
    return character and ('%s %s'):format(character.firstname, character.lastname) or '?'
end

local function log(admin, target, action, data)
    Core.Log({
        actor_account_id = admin.accountId,
        account_id = target and target.accountId or admin.accountId,
        character_id = target and target.characterId or admin.characterId,
        category = 'admin',
        action = action,
        data = data,
    })
end

-- Gibt true zurueck oder nil und einen Fehlercode
function Spectate.Start(source, target)
    local admin = Core.GetPlayer(source)
    if not admin or not admin.character then return nil, 'no_character' end
    if not Core.HasPermission(source, PERMISSION) then return nil, 'no_permission' end
    if Config.Admin.RequireDutyForActions and not admin.adminDuty then return nil, 'duty_required' end
    if admin.jail then return nil, 'jailed' end
    if admin.frozen then return nil, 'frozen' end
    if not target or not target.character then return nil, 'target_offline' end
    if target.source == source then return nil, 'self' end

    local current = admin.spectate
    if not current then
        local position = Platform.GetPlayerPosition(source)
        if not position then return nil, 'no_position' end
        current = { returnPosition = position, returnDimension = Dimensions.Get(admin), since = os.time() }
    elseif current.target ~= target.source then
        -- Wechsel zu jemand anderem: alte Beobachtung im Log abschliessen, Rueckweg bleibt
        local old = Core.GetPlayer(current.target)
        if old then
            log(admin, old, 'spectate_stop', { seconds = os.time() - current.since, switched = true })
        end
        current.since = os.time()
    end
    current.target = target.source
    current.characterId = target.characterId
    admin.spectate = current

    Core.StopNoclip(admin, 'Beobachten')
    if Dimensions.Get(admin) ~= Dimensions.Get(target) then
        Dimensions.Set(admin, Dimensions.Get(target), source, 'Beobachten')
    end
    Network.SendToClient(source, EVENT, {
        on = true,
        serverId = target.source,
        characterId = target.characterId,
        name = nameOf(target),
        position = Platform.GetPlayerPosition(target.source),
    })
    log(admin, target, 'spectate_start', { position = Platform.GetPlayerPosition(target.source) })
    return true
end

-- Beenden: zurueck an die alte Stelle. reason nur fuers Log.
-- stay = true: nicht zurueck teleportieren, weil gleich ein anderer Teleport kommt (z. B. /tp)
function Spectate.Stop(admin, reason, stay)
    if not admin or not admin.spectate then
        return false
    end
    local current = admin.spectate
    admin.spectate = nil
    local target = Core.GetPlayer(current.target)
    if not stay and Dimensions.Get(admin) ~= current.returnDimension then
        Dimensions.Set(admin, current.returnDimension, admin.source, 'Beobachten beendet')
    end
    Network.SendToClient(admin.source, EVENT, { on = false, position = not stay and current.returnPosition or nil })
    log(admin, target and target.characterId == current.characterId and target or nil, 'spectate_stop', {
        seconds = os.time() - current.since,
        characterId = current.characterId,
        reason = reason,
    })
    return true
end

-- Der Beobachtete loggt aus oder verlaesst den Server
function Spectate.OnTargetGone(target)
    for _, player in pairs(Core.Players) do
        if player.spectate and player.spectate.target == target.source then
            Spectate.Stop(player, 'Spieler weg')
            Platform.Notify(player.source, ('ID %d hat das Spiel verlassen, du bist zurück.'):format(target.characterId or 0), 'info')
        end
    end
end

-- /spec <permanente ID>   beobachten (oder zu jemand anderem wechseln)
-- /spec                   beenden
Core.RegisterAdminCommand('spec', PERMISSION, function(source, args)
    if source == CONSOLE then
        Platform.Print('warn', 'Beobachten geht nur ingame.')
        return
    end
    local admin = Core.GetPlayer(source)
    if not args[1] then
        if Spectate.Stop(admin, 'Befehl /spec') then
            Platform.Notify(source, 'Beobachten beendet.', 'info')
        else
            Platform.Notify(source, 'Benutzung: /spec <permanente ID>. Nochmal /spec beendet das Beobachten.', 'info')
        end
        return
    end
    if not args[1]:match('^%d+$') then
        Platform.Notify(source, 'Benutzung: /spec <permanente ID>', 'info')
        return
    end
    local target = Core.GetPlayerByCharacter(args[1])
    local ok, err = Spectate.Start(source, target)
    if not ok then
        Platform.Notify(source, ERRORS[err] or tostring(err), 'error')
        return
    end
    Platform.Notify(source, ('Du beobachtest ID %d (%s). /spec beendet das Beobachten.'):format(target.characterId, nameOf(target)), 'success')
end, { requireDuty = true })

-- Spectate-Ende ueber die Client-Taste oder wenn der Client den Spieler nicht findet
Core.RegisterCallback('admin_spectate_stop', function(source)
    local admin = Core.GetPlayer(source)
    return { ok = Spectate.Stop(admin, 'Client') == true }
end)
