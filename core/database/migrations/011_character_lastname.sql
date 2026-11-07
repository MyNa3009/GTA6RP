-- 1.10.0: Suche nach Nachnamen (Medizinische Datenbank, spaeter MDT). Die Core legt den Index beim Start auch selbst an.

CREATE INDEX IF NOT EXISTS idx_lastname ON characters (lastname);
