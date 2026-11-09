-- Tabellen von core_ems. Gleicher Inhalt wie database/ems.sql (der Test prueft, dass beide gleich sind).
-- Werden beim Start angelegt, falls sie fehlen.

EmsSchema = {
    [[
CREATE TABLE IF NOT EXISTS ems_diseases (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id  INT UNSIGNED NOT NULL,
    disease       VARCHAR(24) NOT NULL,
    stage         TINYINT UNSIGNED NOT NULL DEFAULT 1,
    worsen_in     INT NOT NULL DEFAULT 0,
    series        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    series_left   INT NOT NULL DEFAULT 0,
    gap_left      INT NOT NULL DEFAULT 0,
    started_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cured_at      TIMESTAMP NULL DEFAULT NULL,
    cured_by      VARCHAR(101) NULL,
    INDEX idx_character_active (character_id, cured_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS ems_records (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id  INT UNSIGNED NOT NULL,
    kind          VARCHAR(16) NOT NULL,          -- onset, worse, better, cured, treatment, pill, revive, medkit, collapse, hospital, insurance, diagnosis, note
    text          VARCHAR(255) NOT NULL,
    actor_name    VARCHAR(101) NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_character (character_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS ems_insurance (
    character_id  INT UNSIGNED NOT NULL PRIMARY KEY,
    valid_until   DATETIME NOT NULL,
    sold_by       VARCHAR(101) NULL,
    sold_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Seit core_ems 1.4.0: Eintraege korrigieren und als geloescht markieren (Leitung mit ems.records.manage, Admins)
    [[ALTER TABLE ems_records ADD COLUMN IF NOT EXISTS edited_at TIMESTAMP NULL]],
    [[ALTER TABLE ems_records ADD COLUMN IF NOT EXISTS edited_by VARCHAR(101) NULL]],
    [[ALTER TABLE ems_records ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL]],
    [[ALTER TABLE ems_records ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(101) NULL]],
}
