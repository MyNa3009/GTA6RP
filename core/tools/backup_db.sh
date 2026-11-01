#!/usr/bin/env bash
# Sichert die Datenbank der Core als gepackte SQL-Datei. Gedacht fuer einen taeglichen Cronjob.
# Zugangsdaten stehen NICHT hier, sondern in einer geschuetzten Datei (siehe README, Abschnitt Backups).
#
# Einstellbar ueber Umgebungsvariablen:
#   DB_NAME       Name der Datenbank            (Standard: fivem)
#   BACKUP_DIR    Ordner fuer die Sicherungen   (Standard: /var/backups/fivem)
#   KEEP_DAYS     so viele Tage aufheben        (Standard: 14)
#   CREDENTIALS   Datei mit Benutzer und Passwort (Standard: /etc/fivem-backup.cnf)

set -euo pipefail

DB_NAME="${DB_NAME:-fivem}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/fivem}"
KEEP_DAYS="${KEEP_DAYS:-14}"
CREDENTIALS="${CREDENTIALS:-/etc/fivem-backup.cnf}"
LOG_FILE="$BACKUP_DIR/backup.log"

# Sicherungen sind nur fuer den Besitzer lesbar, sie enthalten E-Mails und Passwort-Hashes
umask 077
mkdir -p "$BACKUP_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

if [ ! -r "$CREDENTIALS" ]; then
    log "FEHLER: $CREDENTIALS fehlt oder ist nicht lesbar."
    exit 1
fi

# MariaDB liefert mariadb-dump, aeltere Versionen nur mysqldump
DUMP="$(command -v mariadb-dump || command -v mysqldump || true)"
if [ -z "$DUMP" ]; then
    log "FEHLER: weder mariadb-dump noch mysqldump gefunden."
    exit 1
fi

stamp="$(date +%Y-%m-%d_%H%M)"
target="$BACKUP_DIR/${DB_NAME}_${stamp}.sql.gz"
partial="$target.part"

# --single-transaction: der Server laeuft weiter, die Sicherung ist trotzdem ein einheitlicher Stand
if "$DUMP" --defaults-extra-file="$CREDENTIALS" \
        --single-transaction --quick --no-tablespaces \
        --routines --triggers --events --hex-blob \
        --default-character-set=utf8mb4 \
        "$DB_NAME" | gzip -6 > "$partial"; then
    gzip -t "$partial"
    mv "$partial" "$target"
    log "OK $target ($(du -h "$target" | cut -f1))"
else
    rm -f "$partial"
    log "FEHLER beim Sichern von $DB_NAME."
    exit 1
fi

# Alte Sicherungen loeschen, die neueste bleibt immer
removed="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${DB_NAME}_*.sql.gz" -mtime +"$KEEP_DAYS" -print -delete | wc -l)"
if [ "$removed" -gt 0 ]; then
    log "$removed alte Sicherung(en) geloescht (aelter als $KEEP_DAYS Tage)."
fi
