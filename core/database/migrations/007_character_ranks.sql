-- Teamrang pro Charakter statt pro Login und Verknuepfung Verwarnung zu Auto-Ban (0.9.6).
-- Die Core macht das beim Start auch selbst und uebertraegt alte Login-Raenge auf den zuletzt gespielten Charakter.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS admin_rank VARCHAR(32) NOT NULL DEFAULT 'player' AFTER account_id;
ALTER TABLE warns ADD COLUMN IF NOT EXISTS ban_id INT UNSIGNED NULL DEFAULT NULL;
