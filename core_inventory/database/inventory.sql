-- Inventar: eine Zeile pro Charakter (char:<permanente ID>), Rucksack (bag:<id>) und Kofferraum (trunk:<Kennzeichen>).
-- Die Resource legt die Tabelle beim Start auch selbst an.

CREATE TABLE IF NOT EXISTS inventories (
    id         VARCHAR(64) NOT NULL PRIMARY KEY,   -- char:17, bag:65a3f2c1
    data       JSON NOT NULL,                      -- { "slots": { "1": { "name": "water", "count": 2 } } }
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Waffenregister: legale Waffen (mit Seriennummer) und ihr erster Besitzer
CREATE TABLE IF NOT EXISTS weapon_registry (
    serial        VARCHAR(16) NOT NULL PRIMARY KEY,
    item          VARCHAR(64) NOT NULL,
    character_id  INT UNSIGNED NULL,
    registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_character (character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Lizenzregister: gilt als Wahrheit, das Item im Inventar wird beim Einloggen danach abgeglichen
CREATE TABLE IF NOT EXISTS licenses (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id  INT UNSIGNED NOT NULL,
    type          VARCHAR(16) NOT NULL,                -- driver, weapon, pilot, boat, fishing
    classes       VARCHAR(32) NULL,                    -- Fuehrerschein: B,C
    issued_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at    TIMESTAMP NULL DEFAULT NULL,
    revoked_at    TIMESTAMP NULL DEFAULT NULL,
    revoked_by    INT UNSIGNED NULL,
    revoke_reason VARCHAR(255) NULL,
    UNIQUE KEY uniq_character_type (character_id, type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
