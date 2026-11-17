# GTA6RP

Eigene Core und Inventar für einen deutschen GTA 6 RP-Server. Bis es eine GTA 6 RP-Plattform gibt, läuft alles auf einem FiveM-Testserver (txAdmin, MariaDB, oxmysql).

| Ordner | Version | Inhalt |
|---|---|---|
| [`core/`](core/README.md) | 1.20.0 | Login, Charaktere mit permanenter ID, Geld, Tod, Hunger und Durst, Teamränge mit Rechten und persönlichen Admin-Keys, Admin-Menü, Tickets, Bans, A-Jail, zentrales Logging |
| [`core_inventory/`](core_inventory/README.md) | 1.5.2 | Inventar mit Plätzen und Gewicht, Kleidung, Rucksack, Waffen mit Register, Ausweis und Lizenzen, Durchsuchen, Kofferraum, Lager-Schnittstelle, `/invsee` |
| [`core_lib/`](core_lib/README.md) | 1.4.3 | Bibliothek für alle Scripts: G-Menü (Interaktionsmenü mit Kategorien), Kontextmenüs, Fortschrittsbalken, Minigames (Skillcheck, Schloss knacken, Hacken, Kabel verbinden), Dialoge, TextUI, Zonen |
| [`core_factions/`](core_factions/README.md) | 1.3.1 | Organisationen: 30 Ränge, Rechte und Gehalt pro Rang, Divisionen, Abteilungen, Prüfungen, Erklärungen, Leitstelle mit Suche, Bonus, Archiv, Protokolle pro ID, Kasse, Dienst an der Umkleide, Dienstfahrzeuge ab Rang, Organisationsmenü in den Farben der Organisation |
| [`core_ems/`](core_ems/README.md) | 1.4.2 | Rettungsdienst: Hochholen, Versorgen, Verbandskasten für alle, Verkauf, Behandlung, Krankheiten mit Stadien und Ansteckung, Krankenversicherung, Medizinische Datenbank mit Korrektur durch Leitung und Admins |
| [`core_dispatch/`](core_dispatch/README.md) | 1.3.0 | Notrufe per `/dispatch` und im Bewusstlos-Bildschirm, Alarm am Bildschirmrand, MDT mit Funkstatus (FMS 0 bis 8), Disponieren, Nachricht an den Anrufer, Archiv und Statistik |
| [`core_bank/`](core_bank/README.md) | 1.0.3 | Bank: Konto mit Kontonummer, Ein- und Auszahlen, Überweisen, Kontoauszug, Schulden (Strafen, Rechnungen, Gebühren) mit Frist, Mahngebühr und Einzug, Bankautomaten, Admin-Ansicht, Schnittstelle für das Handy |
| [`core_phone/`](core_phone/README.md) | 1.1.0 | Handy als Item mit eSIM: Telefon mit Gesprächen, Nachrichten mit Standort, Kontakte, Bank-App (Konto, Überweisen, Schulden), Notruf-App, Lautlos und Flugmodus, Hintergründe, Admin-Ansicht |
| [`tests/`](tests/README.md) | | Tests für die Serverlogik aller Resources |

Das Inventar 1.5.2 braucht mindestens die Core 1.8.2, die `core_lib` 1.4.0 die Core 1.9.0, `core_ems` die Core 1.10.3 und `core_factions` 1.3.0, `core_factions` die Core 1.11.0 `core_dispatch` die Core 1.15.0 und die `core_lib` und `core_bank` die Core 1.16.0 und die `core_lib`. `core_phone` braucht die Core 1.20.0 und das Inventar 1.5.2, für seine Apps `core_bank` 1.0.3 und `core_dispatch` 1.3.0. Empfohlen ist immer die neueste Core, darum alle Ordner zusammen aktualisieren. Die Farben aller UIs stehen seit Core 1.12.1 einmal in `Config.UI.Colors` der Core, Organisationen bringen ihre eigenen im `theme` in `core_factions` mit.

## Installation

1. `core/database/schema.sql` in der Datenbank ausführen. Die Tabellen des Inventars legt das Inventar beim Start selbst an.
2. Die Ordner `core`, `core_inventory`, `core_lib`, `core_factions`, `core_ems`, `core_dispatch`, `core_bank` und `core_phone` nach `resources/[core]/` kopieren.
3. In der eigenen `server.cfg` nach der Datenbank-Verbindung ergänzen:

```cfg
# Testbefehle der Core. Auf einem Live-Server immer "false".
set core_debug "true"

ensure oxmysql
ensure core
ensure core_inventory
ensure core_lib
ensure core_factions
ensure core_ems
ensure core_dispatch
ensure core_bank
ensure core_phone
```

4. Server neu starten.
5. In der txAdmin-Konsole `setrank <deine ID> chief` und `adminkey <deine ID>` eingeben. Mit dem Key schaltest du im Spiel per `/aduty` deine Admin-Rechte frei.

Für ein Update steht in der README jeder Resource ein Abschnitt `Update von x.y.z` mit allen Schritten.

## Aufbau

Damit der Umzug auf GTA 6 später möglich ist, gilt in jeder Resource:

- **FiveM-Natives nur in `core/bridge/`.** Alle anderen Dateien nutzen `Platform`, `Network`, `DB` und `Identity`. Inventar und `core_lib` haben keine eigene Bridge, sie laden die der Core.
- **GTA-5-Daten nur in `data/`** (Dateien `*_gta5.lua`): Waffen, Modelle, Koordinaten, Kleidung.
- **Der Server entscheidet.** Werte im Client sind nur Anzeige.
- **Die permanente Charakter-ID** ist der Schlüssel in allen Tabellen, Befehlen und Logs.
- **Alles wird geloggt**, Admins sehen alles.

Beim Umzug werden nur `bridge/` und `data/` ersetzt.

## Sicherheit

Die echte `server.cfg`, Zugangsdaten und Datenbank-Sicherungen kommen nie ins Repo. Die `.gitignore` schließt sie aus.
