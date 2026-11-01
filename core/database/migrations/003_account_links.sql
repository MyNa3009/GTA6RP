-- Core 0.8.0: Erkennung mehrerer Accounts mit derselben Rockstar-Lizenz
-- Einmal in phpMyAdmin bei der Datenbank "fivem" unter SQL ausfuehren.

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
