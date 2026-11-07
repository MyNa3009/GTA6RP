CREATE TABLE IF NOT EXISTS accounts (
    id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    email             VARCHAR(255) NOT NULL UNIQUE,
    password_hash     VARCHAR(255) NOT NULL,
    email_verified_at TIMESTAMP NULL,
    admin_rank        VARCHAR(32) NOT NULL DEFAULT 'player', -- alt, seit 0.9.6 steht der Rang am Charakter
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at     TIMESTAMP NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS account_identifiers (
    account_id INT UNSIGNED NOT NULL,
    type       VARCHAR(32)  NOT NULL,
    value      VARCHAR(128) NOT NULL,
    first_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (type, value),
    INDEX idx_account (account_id),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS characters (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id    INT UNSIGNED NOT NULL,
    admin_rank    VARCHAR(32) NOT NULL DEFAULT 'player', -- Teamrang gilt pro Charakter
    firstname     VARCHAR(50) NOT NULL,
    lastname      VARCHAR(50) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender        ENUM('male', 'female') NOT NULL DEFAULT 'male',
    cash          BIGINT NOT NULL DEFAULT 0,
    bank          BIGINT NOT NULL DEFAULT 0,
    job           VARCHAR(50) NOT NULL DEFAULT 'unemployed',
    job_grade     TINYINT UNSIGNED NOT NULL DEFAULT 0,
    hunger        DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    thirst        DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    platform_data JSON NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_played   TIMESTAMP NULL,
    deleted_at    TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_account (account_id),
    INDEX idx_name (firstname, lastname),
    INDEX idx_lastname (lastname),
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS audit_log (
    id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    created_at        TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    actor_account_id  INT UNSIGNED NULL,
    account_id        INT UNSIGNED NULL,
    character_id      INT UNSIGNED NULL,
    category          VARCHAR(32) NOT NULL,
    action            VARCHAR(64) NOT NULL,
    amount            BIGINT NULL,
    balance_before    BIGINT NULL,
    balance_after     BIGINT NULL,
    target_account_id INT UNSIGNED NULL,
    resource          VARCHAR(64) NULL,
    reason            VARCHAR(255) NULL,
    data              JSON NULL,
    INDEX idx_account_time (account_id, created_at),
    INDEX idx_actor_time (actor_account_id, created_at),
    INDEX idx_category_time (category, created_at),
    INDEX idx_target (target_account_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS account_links (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_a       INT UNSIGNED NOT NULL,   -- immer die kleinere ID
    account_b       INT UNSIGNED NOT NULL,   -- immer die groessere ID
    identifier_type VARCHAR(32) NOT NULL,    -- z. B. license (Rockstar / Social Club)
    first_seen      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    times_seen      INT UNSIGNED NOT NULL DEFAULT 1,
    dismissed_by    INT UNSIGNED NULL,       -- Admin, der die Warnung ausgeblendet hat
    dismissed_at    TIMESTAMP NULL DEFAULT NULL,
    UNIQUE KEY uniq_pair (account_a, account_b, identifier_type),
    INDEX idx_b (account_b)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS bans (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id   INT UNSIGNED NOT NULL,
    character_id INT UNSIGNED NULL,           -- NULL = ganzer Account, sonst nur dieser Charakter
    reason       VARCHAR(255) NOT NULL,
    banned_by    INT UNSIGNED NULL,           -- NULL = Konsole
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at   TIMESTAMP NULL DEFAULT NULL, -- NULL = permanent
    lifted_at    TIMESTAMP NULL DEFAULT NULL,
    lifted_by    INT UNSIGNED NULL,
    lift_reason  VARCHAR(255) NULL,
    INDEX idx_bans_account (account_id),
    INDEX idx_bans_character (character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS admin_jails (
    id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id        INT UNSIGNED NOT NULL,
    character_id      INT UNSIGNED NULL,      -- Charakter, mit dem gespielt wurde (nur zur Info)
    reason            VARCHAR(255) NOT NULL,
    minutes           INT UNSIGNED NOT NULL,
    remaining_seconds INT UNSIGNED NOT NULL,  -- laeuft nur, solange der Spieler online ist
    jailed_by         INT UNSIGNED NULL,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    released_at       TIMESTAMP NULL DEFAULT NULL,
    released_by       INT UNSIGNED NULL,      -- NULL und released_at gesetzt = Zeit abgesessen
    release_reason    VARCHAR(255) NULL,
    INDEX idx_jails_account (account_id, released_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS account_devices (
    account_id INT UNSIGNED NOT NULL,
    token      VARCHAR(128) NOT NULL,
    first_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, token),
    INDEX idx_devices_token (token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS account_ips (
    account_id INT UNSIGNED NOT NULL,
    ip         VARCHAR(45) NOT NULL,
    first_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (account_id, ip),
    INDEX idx_ips_last_seen (last_seen)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_alerts (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id   INT UNSIGNED NOT NULL,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip           VARCHAR(45) NULL,
    ip_known     TINYINT(1) NOT NULL DEFAULT 0,
    dismissed_by INT UNSIGNED NULL,
    dismissed_at TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_alerts_account (account_id, dismissed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS warns (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id    INT UNSIGNED NOT NULL,
    character_id  INT UNSIGNED NOT NULL,
    reason        VARCHAR(255) NOT NULL,
    warned_by     INT UNSIGNED NULL,           -- NULL = Konsole
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    seen_at       TIMESTAMP NULL DEFAULT NULL, -- wann der Spieler sie gesehen hat
    revoked_at    TIMESTAMP NULL DEFAULT NULL,
    revoked_by    INT UNSIGNED NULL,
    revoke_reason VARCHAR(255) NULL,
    ban_id        INT UNSIGNED NULL DEFAULT NULL, -- Auto-Ban, den diese Verwarnung ausgeloest hat
    INDEX idx_warns_account (account_id, revoked_at),
    INDEX idx_warns_unseen (character_id, seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tickets (
    id                   INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_id           INT UNSIGNED NOT NULL,
    character_id         INT UNSIGNED NOT NULL,
    character_name       VARCHAR(64) NOT NULL,
    category             VARCHAR(16) NOT NULL,
    subject              VARCHAR(120) NOT NULL,
    status               ENUM('open', 'claimed', 'closed') NOT NULL DEFAULT 'open',
    claimed_by           INT UNSIGNED NULL,     -- Login des Admins
    claimed_by_character INT UNSIGNED NULL,     -- permanente ID des Admins
    claimed_by_name      VARCHAR(64) NULL,
    claimed_at           TIMESTAMP NULL DEFAULT NULL,
    closed_by            INT UNSIGNED NULL,
    closed_at            TIMESTAMP NULL DEFAULT NULL,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_tickets_status (status, updated_at),
    INDEX idx_tickets_character (character_id, created_at),
    INDEX idx_tickets_claimer (claimed_by_character, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ticket_messages (
    id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    ticket_id           INT UNSIGNED NOT NULL,
    author_account_id   INT UNSIGNED NULL,
    author_character_id INT UNSIGNED NULL,
    author_name         VARCHAR(64) NOT NULL,
    role                ENUM('player', 'admin', 'system') NOT NULL,
    body                VARCHAR(600) NOT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ticket_messages (ticket_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Archiv fuer Log-Eintraege aelter als Config.Log.ArchiveAfterDays
CREATE TABLE IF NOT EXISTS audit_log_archive LIKE audit_log;
