-- Verwarnungen. Die Core legt die Tabelle beim Start auch selbst an.

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
    INDEX idx_warns_account (account_id, revoked_at),
    INDEX idx_warns_unseen (character_id, seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
