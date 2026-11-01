-- 1.4.0: Hunger und Durst pro Charakter (0 bis 100). Die Core legt die Spalten beim Start auch selbst an.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS hunger DECIMAL(5,2) NOT NULL DEFAULT 100.00 AFTER job_grade;
ALTER TABLE characters ADD COLUMN IF NOT EXISTS thirst DECIMAL(5,2) NOT NULL DEFAULT 100.00 AFTER hunger;
