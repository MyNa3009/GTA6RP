-- Tabellen von core_phone. Das Script legt sie beim Start selbst an (CREATE TABLE IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS phone_numbers (
    character_id  INT UNSIGNED PRIMARY KEY,             -- permanente ID, ihr gehoert die eSIM
    number        VARCHAR(12) NOT NULL,                 -- Handynummer, nur Ziffern
    silent        TINYINT(1) NOT NULL DEFAULT 0,        -- lautlos
    airplane      TINYINT(1) NOT NULL DEFAULT 0,        -- Flugmodus: nicht erreichbar
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_number (number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS phone_contacts (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id  INT UNSIGNED NOT NULL,                -- wessen Kontakt
    number        VARCHAR(12) NOT NULL,
    name          VARCHAR(64) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_owner_number (character_id, number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS phone_messages (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    owner_id      INT UNSIGNED NOT NULL,                -- wessen Ansicht (permanente ID)
    other_number  VARCHAR(12) NOT NULL,                 -- mit wem
    direction     VARCHAR(3) NOT NULL,                  -- in, out
    kind          VARCHAR(8) NOT NULL DEFAULT 'text',   -- text, location
    text          VARCHAR(600) NOT NULL,
    x             FLOAT NULL,                           -- Standort
    y             FLOAT NULL,
    read_at       TIMESTAMP NULL,
    hidden        TINYINT(1) NOT NULL DEFAULT 0,        -- vom Besitzer geloescht, Admins sehen es weiter
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_thread (owner_id, other_number, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS phone_calls (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    owner_id      INT UNSIGNED NOT NULL,                -- wessen Anrufliste
    other_number  VARCHAR(12) NOT NULL,
    direction     VARCHAR(3) NOT NULL,                  -- in, out
    status        VARCHAR(12) NOT NULL,                 -- answered, missed, declined, unreachable, busy
    seconds       INT UNSIGNED NOT NULL DEFAULT 0,      -- Dauer des Gespraechs
    seen          TINYINT(1) NOT NULL DEFAULT 0,        -- verpasster Anruf schon gesehen
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_owner (owner_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
