# Tests

Die Tests laden die echten Server-Dateien von Core und Inventar in Lua (über `lupa`), ersetzen die FiveM-Natives durch Attrappen und laufen gegen eine echte MariaDB. Sie rufen die Callbacks so auf, wie es ein Client tun würde, auch mit falschen Werten.

## Achtung

Die Tests **löschen alle Tabellen** der Datenbank, mit der sie verbunden sind. Darum brechen sie ab, wenn der Name der Datenbank nicht "test" enthält. Nie gegen die Datenbank des Servers laufen lassen.

## Einrichten

```bash
pip install lupa pymysql
```

Eine eigene Test-Datenbank anlegen:

```sql
CREATE DATABASE core_test CHARACTER SET utf8mb4;
CREATE USER 'core_test'@'localhost' IDENTIFIED BY 'ein_eigenes_passwort';
GRANT ALL ON core_test.* TO 'core_test'@'localhost';
```

Die Verbindung kommt aus Umgebungsvariablen:

| Variable | Standard |
|---|---|
| `CORE_TEST_DB_HOST` | `localhost` |
| `CORE_TEST_DB_USER` | `core_test` |
| `CORE_TEST_DB_PASSWORD` | leer |
| `CORE_TEST_DB_NAME` | `core_test` |

## Ausführen

```bash
export CORE_TEST_DB_PASSWORD=ein_eigenes_passwort
python3 tests/test_views.py
for t in tests/test_*.py; do echo "$t: $(python3 $t | tail -1)"; done
```

Jeder Test endet mit einer Zeile wie `43 ok, 0 Fehler`.

Admin-Keys sind in den Tests aus, damit die Rechte-Tests ohne Key-Eingabe laufen. Nur `test_admin_keys.py` schaltet sie mit `Env(admin_keys=True)` ein.

`test_core_lib.py` braucht keine Datenbank. Er lädt die Client- und Server-Dateien der `core_lib` mit einer nachgebauten Bridge und lässt die Zeit virtuell laufen (G-Menü, Kontextmenüs, Dialoge, Fortschritt, Minigames, Zonen, `init.lua`).

Syntax aller Lua-Dateien prüfen:

```bash
python3 tests/syntax.py core core_inventory core_lib
```

## Was die Tests nicht abdecken

Alles, was nur im Spiel sichtbar ist: Animationen, Positionen (Kofferraum, Spawn), Kleidung am Charakter, Tastenbelegung. Das wird auf dem Testserver geprüft.

`test_noclip.py` braucht keine Datenbank. Er lädt die Client-Bridge mit nachgebauten FiveM-Natives und prüft den Noclip (Richtung, Q und E, Shift und Alt, Nachziehen des Peds, Teleport, Ausschalten mit Fallschutz).

`test_vehicle_target.py` braucht auch keine Datenbank. Er prüft die Bridge-Funktionen für das Fahrzeug von außen: Fahrzeug im Blick (Abstand zur Karosserie, nicht hinter der eigenen Figur, nicht aus dem Fahrzeug), Umrandung, Stand von außen, Türen von außen (Schloss, Abstand, Kontrolle über das Fahrzeug) und Einsteigen.
