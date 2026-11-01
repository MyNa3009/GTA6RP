-- 1.0.0: Tickets (/report). Die Core legt die Tabellen beim Start auch selbst an.

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
