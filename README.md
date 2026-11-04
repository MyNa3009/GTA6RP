# GTA6RP

Eigene Core und Inventar für einen deutschen GTA 6 RP-Server. Bis es eine GTA 6 RP-Plattform gibt, läuft alles auf einem FiveM-Testserver (txAdmin, MariaDB, oxmysql).

| Ordner | Version | Inhalt |
|---|---|---|
| [`core/`](core/README.md) | 1.7.7 | Login, Charaktere mit permanenter ID, Geld, Tod, Hunger und Durst, Teamränge mit Rechten und persönlichen Admin-Keys, Admin-Menü, Tickets, Bans, A-Jail, zentrales Logging |
| [`core_inventory/`](core_inventory/README.md) | 1.1.0 | Inventar mit Plätzen und Gewicht, Kleidung, Rucksack, Waffen mit Register, Ausweis und Lizenzen, Durchsuchen, Kofferraum, Lager-Schnittstelle, `/invsee` |
| [`tests/`](tests/README.md) | | Tests für die Serverlogik beider Resources |

Das Inventar 1.1.0 braucht mindestens die Core 1.6.0, empfohlen ist die neueste. Beide Ordner werden darum immer zusammen aktualisiert.

## Installation

1. `core/database/schema.sql` in der Datenbank ausführen. Die Tabellen des Inventars legt das Inventar beim Start selbst an.
2. Die Ordner `core` und `core_inventory` nach `resources/[core]/` kopieren.
3. In der eigenen `server.cfg` nach der Datenbank-Verbindung ergänzen:

```cfg
# Testbefehle der Core. Auf einem Live-Server immer "false".
set core_debug "true"

ensure oxmysql
ensure core
ensure core_inventory
```

4. Server neu starten.
5. In der txAdmin-Konsole `setrank <deine ID> chief` und `adminkey <deine ID>` eingeben. Mit dem Key schaltest du im Spiel per `/aduty` deine Admin-Rechte frei.

Für ein Update steht in der README jeder Resource ein Abschnitt `Update von x.y.z` mit allen Schritten.

## Aufbau

Damit der Umzug auf GTA 6 später möglich ist, gilt in jeder Resource:

- **FiveM-Natives nur in `core/bridge/`.** Alle anderen Dateien nutzen `Platform`, `Network`, `DB` und `Identity`. Das Inventar hat keine eigene Bridge, es lädt die der Core.
- **GTA-5-Daten nur in `data/`** (Dateien `*_gta5.lua`): Waffen, Modelle, Koordinaten, Kleidung.
- **Der Server entscheidet.** Werte im Client sind nur Anzeige.
- **Die permanente Charakter-ID** ist der Schlüssel in allen Tabellen, Befehlen und Logs.
- **Alles wird geloggt**, Admins sehen alles.

Beim Umzug werden nur `bridge/` und `data/` ersetzt.

## Sicherheit

Die echte `server.cfg`, Zugangsdaten und Datenbank-Sicherungen kommen nie ins Repo. Die `.gitignore` schließt sie aus.
