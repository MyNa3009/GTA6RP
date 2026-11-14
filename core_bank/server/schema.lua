-- Tabellen von core_bank. Werden beim Start angelegt, das gleiche SQL steht in database/bank.sql.

BankSchema = {
    [[
CREATE TABLE IF NOT EXISTS bank_accounts (
    character_id  INT UNSIGNED PRIMARY KEY,             -- permanente ID
    number        CHAR(8) NOT NULL,                     -- Kontonummer, 8 Ziffern
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_number (number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS bank_transactions (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id  INT UNSIGNED NOT NULL,                -- wessen Konto
    kind          VARCHAR(16) NOT NULL,                 -- deposit, withdraw, transfer_in, transfer_out, debt, collect, credit, debit, refund
    amount        BIGINT NOT NULL,                      -- mit Vorzeichen: + Eingang, - Ausgang
    balance       BIGINT NOT NULL,                      -- Kontostand danach
    text          VARCHAR(160) NOT NULL,                -- Verwendungszweck oder Grund
    other_id      INT UNSIGNED NULL,                    -- Gegenkonto: permanente ID
    other_name    VARCHAR(101) NULL,                    -- Gegenkonto: Name oder Glaeubiger
    other_number  CHAR(8) NULL,
    channel       VARCHAR(8) NOT NULL DEFAULT 'system', -- bank, atm, phone, system
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_character (character_id, id),
    INDEX idx_character_kind (character_id, kind, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS bank_debts (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id  INT UNSIGNED NOT NULL,                -- Schuldner, permanente ID
    kind          VARCHAR(16) NOT NULL DEFAULT 'other', -- fine (Strafe), invoice (Rechnung), fee (Gebuehr), other
    creditor      VARCHAR(32) NOT NULL DEFAULT 'state', -- state oder Organisation aus core_factions
    creditor_label VARCHAR(64) NOT NULL,
    title         VARCHAR(120) NOT NULL,                -- wofuer
    amount        BIGINT UNSIGNED NOT NULL,             -- urspruenglicher Betrag
    fee           BIGINT UNSIGNED NOT NULL DEFAULT 0,   -- Mahngebuehr
    paid          BIGINT UNSIGNED NOT NULL DEFAULT 0,   -- schon bezahlt
    status        VARCHAR(12) NOT NULL DEFAULT 'open',  -- open, paid, cancelled
    issued_by_id  INT UNSIGNED NULL,                    -- wer ausgestellt hat (permanente ID)
    issued_by     VARCHAR(101) NULL,
    resource      VARCHAR(48) NULL,                     -- Script, das die Forderung angelegt hat
    due_at        TIMESTAMP NOT NULL,
    reminded_at   TIMESTAMP NULL,                       -- Mahngebuehr berechnet
    checked_at    TIMESTAMP NULL,                       -- letzter Versuch, vom Konto einzuziehen
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at     TIMESTAMP NULL,
    closed_by     VARCHAR(101) NULL,
    close_reason  VARCHAR(120) NULL,
    INDEX idx_character (character_id, status, id),
    INDEX idx_due (status, due_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
}
