-- Bans und A-Jail. Die Core legt beide Tabellen beim Start auch selbst an.

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
