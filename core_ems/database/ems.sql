-- Tabellen von core_ems. Werden beim Start auch selbst angelegt (CREATE TABLE IF NOT EXISTS).

-- Krankheiten je Charakter. Geheilte bleiben mit cured_at stehen (Krankenakte).
-- Zeiten in Sekunden Online-Zeit: worsen_in (bis es schlimmer wird), series_left (Rest des Behandlungsfensters),
-- gap_left (bis zur naechsten Behandlung oder Tablette).
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Krankenakte: alles, was medizinisch passiert ist
CREATE TABLE IF NOT EXISTS ems_records (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id  INT UNSIGNED NOT NULL,
    kind          VARCHAR(16) NOT NULL,          -- onset, worse, better, cured, treatment, pill, revive, medkit, collapse, hospital, insurance, diagnosis, note
    text          VARCHAR(255) NOT NULL,
    actor_name    VARCHAR(101) NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_character (character_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Krankenversicherung
CREATE TABLE IF NOT EXISTS ems_insurance (
    character_id  INT UNSIGNED NOT NULL PRIMARY KEY,
    valid_until   DATETIME NOT NULL,
    sold_by       VARCHAR(101) NULL,
    sold_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
