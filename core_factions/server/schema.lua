-- Tabellen von core_factions. Gleicher Inhalt wie database/factions.sql (der Test prueft, dass beide gleich sind).
-- Werden beim Start angelegt, falls sie fehlen.

FactionSchema = {
    [[
CREATE TABLE IF NOT EXISTS faction_members (
    character_id  INT UNSIGNED NOT NULL PRIMARY KEY,           -- permanente ID
    faction       VARCHAR(32) NOT NULL,
    `rank`        TINYINT UNSIGNED NOT NULL,
    name          VARCHAR(101) NOT NULL,                       -- Name zum Zeitpunkt des letzten Logins (fuer Listen)
    dn            VARCHAR(16) NULL,                            -- Dienstnummer
    strikes       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    vacation_days SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    departments   JSON NOT NULL,                               -- [{ "id": 3, "rank": 2 }]
    exams         JSON NOT NULL,                               -- [{ "id": 1, "at": "2026-11-07", "by": "Max Muster" }]
    hired_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hired_by      INT UNSIGNED NULL,
    INDEX idx_faction_rank (faction, `rank`),
    UNIQUE INDEX idx_faction_dn (faction, dn)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_settings (
    faction     VARCHAR(32) NOT NULL PRIMARY KEY,
    message     TEXT NULL,
    message_by  VARCHAR(101) NULL,
    message_at  TIMESTAMP NULL,
    balance     BIGINT NOT NULL DEFAULT 0,
    next_dn     INT UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_ranks (
    faction     VARCHAR(32) NOT NULL,
    `rank`      TINYINT UNSIGNED NOT NULL,
    name        VARCHAR(32) NOT NULL,
    permissions JSON NOT NULL,                                 -- { "members.hire": true, "ems.revive": false }
    PRIMARY KEY (faction, `rank`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_vehicles (
    faction     VARCHAR(32) NOT NULL,
    model       VARCHAR(32) NOT NULL,
    min_rank    TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (faction, model)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_departments (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    faction     VARCHAR(32) NOT NULL,
    name        VARCHAR(32) NOT NULL,
    ranks       JSON NOT NULL,                                 -- ["Mitglied", "Ausbilder", "Leitung"]
    deleted_at  TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_faction (faction)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_exams (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    faction     VARCHAR(32) NOT NULL,
    name        VARCHAR(40) NOT NULL,
    deleted_at  TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_faction (faction)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_history (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    faction       VARCHAR(32) NOT NULL,
    character_id  INT UNSIGNED NOT NULL,
    action        VARCHAR(16) NOT NULL,                        -- hire, rank, fire, leave
    rank_from     TINYINT UNSIGNED NULL,
    rank_to       TINYINT UNSIGNED NULL,
    rank_name     VARCHAR(32) NULL,
    leader_name   VARCHAR(101) NULL,
    actor_name    VARCHAR(101) NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_member (faction, character_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_archive (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    faction       VARCHAR(32) NOT NULL,
    character_id  INT UNSIGNED NOT NULL,
    name          VARCHAR(101) NOT NULL,
    dn            VARCHAR(16) NULL,
    last_rank     VARCHAR(32) NOT NULL,
    ranks         JSON NOT NULL,                               -- [{ "rank": 3, "name": "...", "at": "...", "leader": "..." }]
    exams         JSON NOT NULL,                               -- [{ "name": "...", "at": "...", "by": "..." }]
    hired_at      TIMESTAMP NULL,
    left_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_reason   VARCHAR(120) NULL,
    left_by       VARCHAR(101) NULL,
    kind          VARCHAR(8) NOT NULL,                         -- fire, leave, admin
    INDEX idx_faction_left (faction, left_at),
    INDEX idx_character (character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_divisions (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    faction     VARCHAR(32) NOT NULL,
    name        VARCHAR(32) NOT NULL,
    min_rank    TINYINT UNSIGNED NOT NULL,
    max_rank    TINYINT UNSIGNED NOT NULL,
    INDEX idx_faction (faction)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_info (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    faction     VARCHAR(32) NOT NULL,
    category    VARCHAR(16) NOT NULL,
    title       VARCHAR(60) NOT NULL,
    body        TEXT NOT NULL,
    sort        SMALLINT NOT NULL DEFAULT 0,
    updated_by  VARCHAR(101) NULL,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_faction (faction, category, sort)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    [[
CREATE TABLE IF NOT EXISTS faction_logs (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    faction       VARCHAR(32) NOT NULL,
    area          VARCHAR(16) NOT NULL,                        -- leitstelle, einsatz, datenbank, kasse, dienst, anpassung
    action        VARCHAR(32) NOT NULL,
    actor_id      INT UNSIGNED NULL,                           -- permanente ID, wer es getan hat (nil: System)
    actor_name    VARCHAR(101) NULL,
    actor_admin   TINYINT(1) NOT NULL DEFAULT 0,
    target_id     INT UNSIGNED NULL,                           -- permanente ID, wen es betrifft
    target_name   VARCHAR(101) NULL,
    text          VARCHAR(500) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_faction (faction, id),
    INDEX idx_area (faction, area, id),
    INDEX idx_target (faction, target_id, id),
    INDEX idx_actor (faction, actor_id, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]],
    -- Spalten seit core_factions 1.1.0 (bestehende Installationen bekommen sie hier dazu)
    [[ALTER TABLE faction_ranks ADD COLUMN IF NOT EXISTS salary INT UNSIGNED NOT NULL DEFAULT 0]],
    [[ALTER TABLE faction_ranks ADD COLUMN IF NOT EXISTS tasks VARCHAR(300) NULL]],
    [[ALTER TABLE faction_exams ADD COLUMN IF NOT EXISTS description TEXT NULL]],
    [[ALTER TABLE faction_members ADD COLUMN IF NOT EXISTS last_bonus_at TIMESTAMP NULL]],
    -- seit core_factions 1.2.0: Archiv-Eintraege kann ein Admin ausblenden (bleiben fuer Admins sichtbar)
    [[ALTER TABLE faction_archive ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMP NULL]],
    [[ALTER TABLE faction_archive ADD COLUMN IF NOT EXISTS hidden_by VARCHAR(101) NULL]],
}
