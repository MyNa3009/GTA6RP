-- Tabellen von core_dispatch. Legt das Script beim Start selbst an, hier zum Nachlesen oder fuer Hand-Installation.

CREATE TABLE IF NOT EXISTS dispatch_calls (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    service       VARCHAR(32) NOT NULL,                 -- Schluessel aus Config.Dispatch.Services
    faction       VARCHAR(32) NOT NULL,
    number        VARCHAR(24) NOT NULL,                 -- Einsatznummer, z. B. "EMS 26/0042"
    kind          VARCHAR(16) NOT NULL DEFAULT 'call',  -- call (Notruf), unit (Einheit in Not)
    priority      TINYINT UNSIGNED NOT NULL DEFAULT 1,
    status        VARCHAR(16) NOT NULL DEFAULT 'open',  -- open, active, closed
    caller_id     INT UNSIGNED NULL,                    -- permanente ID
    caller_name   VARCHAR(101) NULL,
    anonymous     TINYINT(1) NOT NULL DEFAULT 0,        -- Name fuer Einheiten verborgen (Admins sehen ihn)
    caller_down   TINYINT(1) NOT NULL DEFAULT 0,        -- Anrufer war beim Notruf bewusstlos
    text          VARCHAR(240) NOT NULL,
    location      VARCHAR(80) NULL,                     -- Ortsname, nur Anzeige
    x             FLOAT NOT NULL,
    y             FLOAT NOT NULL,
    z             FLOAT NOT NULL,
    units         TEXT NULL,                            -- JSON: { { id, name } } zuletzt zugewiesen
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accepted_at   TIMESTAMP NULL,                       -- erste Einheit
    arrived_at    TIMESTAMP NULL,                       -- erste Einheit am Einsatzort
    closed_at     TIMESTAMP NULL,
    closed_by     VARCHAR(101) NULL,
    result        VARCHAR(16) NULL,
    report        VARCHAR(600) NULL,
    INDEX idx_service_status (service, status),
    INDEX idx_service_created (service, created_at),
    INDEX idx_caller (caller_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS dispatch_events (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    call_id       INT UNSIGNED NOT NULL,
    kind          VARCHAR(16) NOT NULL,                 -- created, accept, release, assign, status, arrive, note, message, priority, close
    actor_id      INT UNSIGNED NULL,
    actor_name    VARCHAR(101) NULL,
    text          VARCHAR(600) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_call (call_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS dispatch_units (
    character_id  INT UNSIGNED PRIMARY KEY,             -- permanente ID
    callsign      VARCHAR(16) NULL,                     -- Funkrufname, z. B. "RTW 1/83-1"
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS dispatch_blocks (
    character_id  INT UNSIGNED PRIMARY KEY,             -- permanente ID
    until         TIMESTAMP NOT NULL,
    reason        VARCHAR(120) NULL,
    by_name       VARCHAR(101) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
