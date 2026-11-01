-- Core 0.3.0: Charakterauswahl
-- Einmal in phpMyAdmin bei der Datenbank "fivem" unter SQL ausfuehren.

ALTER TABLE characters
    ADD COLUMN gender ENUM('male', 'female') NOT NULL DEFAULT 'male' AFTER date_of_birth,
    ADD COLUMN deleted_at TIMESTAMP NULL DEFAULT NULL AFTER last_played,
    ADD INDEX idx_name (firstname, lastname);
