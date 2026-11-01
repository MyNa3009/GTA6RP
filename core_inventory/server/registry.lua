-- Register: legale Waffen (Seriennummer gehoert einem Charakter) und Lizenzen.
-- Fuer ein spaeteres Polizei-MDT: abfragen, auch wenn das Item weg ist.

Registry = { Ready = false }

local TABLES = {
    [[CREATE TABLE IF NOT EXISTS weapon_registry (
        serial        VARCHAR(16) NOT NULL PRIMARY KEY,
        item          VARCHAR(64) NOT NULL,
        character_id  INT UNSIGNED NULL,
        registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_character (character_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}

DB.Ready(function()
    for _, statement in ipairs(TABLES) do
        if DB.Query(statement) == nil then
            Platform.Print('error', 'Register-Tabellen konnten nicht angelegt werden. Bitte database/inventory.sql ausfuehren.')
            return
        end
    end
    Registry.Ready = true
end)

------------------------------------------------------------------------
-- Waffen
------------------------------------------------------------------------

-- Neue legale Waffe: Seriennummer auf den ersten Besitzer eintragen
Inventory.OnWeaponRegistered = function(serial, item, characterId)
    DB.Fire('INSERT IGNORE INTO weapon_registry (serial, item, character_id) VALUES (?, ?, ?)', { serial, item, characterId })
end

-- { serial, item, characterId, registeredAt } oder nil
function Registry.Weapon(serial)
    if type(serial) ~= 'string' then
        return nil
    end
    local row = DB.Single('SELECT serial, item, character_id, UNIX_TIMESTAMP(registered_at) AS registered FROM weapon_registry WHERE serial = ?', { serial:upper() })
    if not row then
        return nil
    end
    return { serial = row.serial, item = row.item, characterId = row.character_id, registeredAt = tonumber(row.registered) }
end

Platform.Export('GetWeaponBySerial', Registry.Weapon)
