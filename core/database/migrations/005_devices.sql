-- Geraete (Hardware-Tokens, IPs) und Warnungen bei neuem PC. Die Core legt die Tabellen beim Start auch selbst an.

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
