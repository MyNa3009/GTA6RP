-- 1.1.0: Archiv fuer alte Log-Eintraege. Die Core legt die Tabelle beim Start auch selbst an.
-- Gleiche Spalten und Indizes wie audit_log.

CREATE TABLE IF NOT EXISTS audit_log_archive LIKE audit_log;
