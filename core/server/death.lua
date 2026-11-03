-- Tod, Krankenhaus und Wiederbeleben.
-- Der Client meldet den Tod, der Server merkt sich die Zeit und entscheidet, wann es ins Krankenhaus geht.

local REVIVE_EVENT = 'core:death:revive'

local function remainingSeconds(character)
    return math.max(0, character.diedAt + Config.Death.HospitalAfterSeconds - os.time())
end

Core.RegisterCallback('death_report', function(source, data)
    local player = Core.GetPlayer(source)
    local character = player and player.character
    if not character then
        return { ok = false, error = 'no_character' }
    end

    -- Schon gemeldet: nur die Restzeit zurueckgeben
    if character.diedAt then
        return { ok = true, data = { respawnInSeconds = remainingSeconds(character), killerId = character.deathKillerId } }
    end

    character.diedAt = os.time()

    local killerId = tonumber(data.killer)
    local killer = killerId and killerId ~= source and Core.GetPlayer(killerId) or nil
    local killerCharacter = killer and killer.character or nil
    local weapon = tonumber(data.weapon)

    -- Namen werden zum Zeitpunkt des Todes mitgespeichert, damit sie auch spaeter noch stimmen
    Core.Log({
        actor_account_id = killer and killer.accountId or nil,
        account_id = player.accountId,
        character_id = character.id,
        target_account_id = killer and killer.accountId or nil,
        category = 'death',
        action = 'died',
        data = {
            victimName = ('%s %s'):format(character.firstname, character.lastname),
            killerAccountId = killer and killer.accountId or nil,
            killerServerId = killer and killerId or nil,
            killerCharacterId = killer and killer.characterId or nil,
            killerName = killerCharacter and ('%s %s'):format(killerCharacter.firstname, killerCharacter.lastname) or nil,
            killerOnDuty = killer and killer.adminDuty ~= nil or nil,
            weapon = weapon and math.floor(weapon) % 4294967296 or nil,
            weaponName = WeaponLabel(weapon),
            position = Platform.GetPlayerPosition(source),
        },
    })

    -- Permanente ID des Taeters fuer den Bewusstlos-Bildschirm (nicht der Name)
    character.deathKillerId = killer and killer.characterId or nil
    return { ok = true, data = { respawnInSeconds = Config.Death.HospitalAfterSeconds, killerId = character.deathKillerId } }
end)

Core.RegisterCallback('death_respawn', function(source)
    local player = Core.GetPlayer(source)
    local character = player and player.character
    if not character or not character.diedAt then
        return { ok = false, error = 'not_dead' }
    end

    local remaining = remainingSeconds(character)
    if remaining > 0 then
        return { ok = false, error = 'too_early', data = { retryIn = remaining } }
    end

    character.diedAt = nil
    character.deathKillerId = nil
    Needs.AfterRespawn(source)
    local position = Jail.RespawnPosition(player) or SpawnData.respawn
    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = character.id,
        category = 'death',
        action = 'hospital',
        data = { position = position, jailed = player.jail ~= nil or nil },
    })

    return { ok = true, data = { position = position } }
end)

-- Fuer spaetere Systeme (Rettungsdienst, Admin-Menue)
function Core.Revive(source, actorAccountId, reason)
    local player = Core.GetPlayer(source)
    local character = player and player.character
    if not character then
        return false
    end

    local wasDead = character.diedAt ~= nil
    character.diedAt = nil
    character.deathKillerId = nil
    Needs.AfterRespawn(source)
    Network.SendToClient(source, REVIVE_EVENT, {})

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = player.accountId,
        character_id = character.id,
        category = 'death',
        action = 'revive',
        reason = reason,
        data = { wasDead = wasDead },
    })
    return true
end

------------------------------------------------------------------------
-- Befehl (Recht player.revive)
------------------------------------------------------------------------

-- /revive         sich selbst wiederbeleben
-- /revive 17      Charakter mit permanenter ID 17 wiederbeleben
Core.RegisterAdminCommand('revive', 'player.revive', function(source, args, actorAccountId)
    local target, err = Core.ResolveTarget(source, args[1])
    if not target then
        Platform.Notify(source, err, 'error')
        return
    end

    if not Core.Revive(target, actorAccountId, 'Befehl /revive') then
        Platform.Notify(source, 'Dieser Spieler spielt gerade keinen Charakter.', 'error')
        return
    end
    Platform.Notify(source, args[1] and ('ID %s wiederbelebt.'):format(args[1]) or 'Du wurdest wiederbelebt.', 'success')
end, { requireDuty = true })
