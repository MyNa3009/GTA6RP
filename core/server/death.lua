-- Tod, Krankenhaus und Wiederbeleben.
-- Der Client meldet den Tod, der Server merkt sich die Zeit und entscheidet, wann es ins Krankenhaus geht.
-- Andere Scripts (Rettungsdienst, Krankheiten) nutzen die Exports Revive, Collapse, IsDead und Heal.
-- "Nur Krankenhaus" (hospitalOnly): nach einem Zusammenbruch, z. B. durch eine Krankheit im letzten Stadium,
-- darf vor Ort niemand hochholen ausser einem Admin. Es gilt bis zum naechsten Krankenhaus.

local REVIVE_EVENT = 'core:death:revive'
-- Oeffentlicher Wert fuer alle Clients (z. B. G-Menue "Hochholen"): true = bewusstlos, 'hospital' = nur Krankenhaus.
-- Der Server setzt ihn, weil der Zustand des Spielmodells bei anderen Spielern nicht immer zuverlaessig ankommt.
local DOWN_KEY = 'down'

local function setDown(source, character)
    if character and character.diedAt then
        Network.SetPlayerPublic(source, DOWN_KEY, character.hospitalOnly and 'hospital' or true)
    else
        Network.SetPlayerPublic(source, DOWN_KEY, nil)
    end
end
Core.SetDownState = setDown
local COLLAPSE_EVENT = 'core:death:collapse'
local HEAL_EVENT = 'core:heal'
local COLLAPSE_REPORT_SECONDS = 30   -- so lange nach dem Zusammenbruch zaehlt eine Todesmeldung noch dazu
local REASON_MAX_LENGTH = 120

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
        return { ok = true, data = { respawnInSeconds = remainingSeconds(character), killerId = character.deathKillerId,
            hospitalOnly = character.hospitalOnly == true } }
    end

    character.diedAt = os.time()

    -- Zusammenbruch, den ein Script ausgeloest hat (Krankheit)
    local collapse = character.pendingCollapse
    character.pendingCollapse = nil
    if collapse and os.time() - collapse.at <= COLLAPSE_REPORT_SECONDS then
        character.hospitalOnly = collapse.hospitalOnly or nil
        character.collapseReason = collapse.reason
    end
    setDown(source, character)

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
    return { ok = true, data = { respawnInSeconds = Config.Death.HospitalAfterSeconds, killerId = character.deathKillerId,
        hospitalOnly = character.hospitalOnly == true, collapseReason = character.collapseReason } }
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

    local hospitalOnly, collapseReason = character.hospitalOnly == true, character.collapseReason
    character.diedAt = nil
    character.deathKillerId = nil
    character.hospitalOnly = nil
    character.collapseReason = nil
    setDown(source, character)
    Needs.AfterRespawn(source)
    local position = Jail.RespawnPosition(player) or SpawnData.respawn
    Core.Log({
        actor_account_id = player.accountId,
        account_id = player.accountId,
        character_id = character.id,
        category = 'death',
        action = 'hospital',
        data = { position = position, jailed = player.jail ~= nil or nil, hospitalOnly = hospitalOnly or nil },
    })
    -- Fuer andere Scripts, z. B. Krankheiten (nach dem Krankenhaus eine Stufe zurueck)
    Platform.Emit('core:characterRespawned', source, character.id, { hospitalOnly = hospitalOnly, reason = collapseReason })

    return { ok = true, data = { position = position } }
end)

-- Wiederbeleben vor Ort (Rettungsdienst, Admin-Menue, /revive). Gibt true oder false und einen Fehlercode zurueck.
-- options.force: auch bei "nur Krankenhaus" (nur fuer Admins)
function Core.Revive(source, actorAccountId, reason, options)
    local player = Core.GetPlayer(source)
    local character = player and player.character
    if not character then
        return false, 'no_character'
    end
    if character.hospitalOnly and not (options and options.force) then
        return false, 'hospital_only'
    end

    local wasDead = character.diedAt ~= nil
    character.diedAt = nil
    character.deathKillerId = nil
    character.hospitalOnly = nil
    character.collapseReason = nil
    character.pendingCollapse = nil
    setDown(source, character)
    Needs.AfterRespawn(source)
    Network.SendToClient(source, REVIVE_EVENT, {})

    Core.Log({
        actor_account_id = actorAccountId,
        account_id = player.accountId,
        character_id = character.id,
        category = 'death',
        action = 'revive',
        reason = reason,
        data = { wasDead = wasDead, forced = options and options.force or nil },
    })
    Platform.Emit('core:characterRevived', source, character.id, actorAccountId)
    return true
end

-- Zusammenbruch, ausgeloest von einem Script (z. B. Krankheit im letzten Stadium). Der Client faellt um,
-- seine Todesmeldung uebernimmt dann hospitalOnly. Gibt true oder false und einen Fehlercode zurueck.
function Core.Collapse(source, reason, hospitalOnly)
    local player = Core.GetPlayer(source)
    local character = player and player.character
    if not character then
        return false, 'no_character'
    end
    reason = type(reason) == 'string' and reason:sub(1, REASON_MAX_LENGTH) or nil
    if character.diedAt then
        if hospitalOnly then
            character.hospitalOnly = true
            character.collapseReason = reason
            setDown(source, character)
        end
        return true
    end
    character.pendingCollapse = { at = os.time(), reason = reason, hospitalOnly = hospitalOnly == true }
    Network.SendToClient(source, COLLAPSE_EVENT, { reason = reason })
    Core.Log({
        account_id = player.accountId,
        character_id = character.id,
        category = 'death',
        action = 'collapse',
        reason = reason,
        data = { hospitalOnly = hospitalOnly == true or nil, resource = Platform.GetCallingResource() },
    })
    return true
end

-- Gesundheit geben (z. B. Verbandskasten vom Rettungsdienst). amount: Punkte, GTA zaehlt 100 von leer bis voll.
function Core.Heal(source, amount)
    local player = Core.GetPlayer(source)
    local character = player and player.character
    amount = tonumber(amount)
    if not character or character.diedAt or not amount or amount <= 0 then
        return false
    end
    Network.SendToClient(source, HEAL_EVENT, { amount = math.floor(amount) })
    return true
end

-- Bewusstlos? Zweiter Wert: nur Krankenhaus moeglich
function Core.IsDead(source)
    local character = Core.GetCharacter(source)
    if not character then
        return false, false
    end
    return character.diedAt ~= nil, character.hospitalOnly == true
end

Platform.Export('IsDead', Core.IsDead)
Platform.Export('Revive', function(source, actorAccountId, reason)
    return Core.Revive(source, actorAccountId, reason)
end)
Platform.Export('Collapse', Core.Collapse)
Platform.Export('Heal', Core.Heal)

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

    if not Core.Revive(target, actorAccountId, 'Befehl /revive', { force = true }) then
        Platform.Notify(source, 'Dieser Spieler spielt gerade keinen Charakter.', 'error')
        return
    end
    Platform.Notify(source, args[1] and ('ID %s wiederbelebt.'):format(args[1]) or 'Du wurdest wiederbelebt.', 'success')
end, { requireDuty = true })
