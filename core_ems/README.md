# core_ems 1.1.1

Rettungsdienst (EMS) für die eigene Core: Hochholen mit Minigame, Verbandskasten, Verkauf von Verbänden, Verbandskästen und Tabletten, Untersuchen und Behandeln, Krankheiten mit Stadien, Krankenversicherung und die Medizinische Datenbank. Ränge, Rechte, Dienst und Kasse kommen aus `core_factions` (Organisation `ems`).

## Update von 1.1.0

1. Erst Core 1.10.2, dann den Ordner `core_ems` ersetzen und neu starten.
2. Fehler behoben: "Hochholen" fehlte im G-Menü, weil `core_ems` "bewusstlos" nur am Spielmodell erkannt hat. Jetzt gilt der Zustand vom Server. Nach einem Zusammenbruch durch Krankheit (nur Krankenhaus) erscheint "Hochholen" gar nicht erst.

## Update von 1.0.0

1. Den Ordner `core_ems` ersetzen und neu starten. Keine Migration.
2. Mediziner brauchen keinen Verbandskasten mehr, weder zum Hochholen noch zum Versorgen. "Verbandskasten anwenden" heißt jetzt **Versorgen** (Recht `ems.heal` statt `ems.medkit`). Wer das Recht im Organisationsmenü angepasst hatte, stellt es einmal neu ein.
3. Der Verbandskasten ist jetzt für alle anderen: Unter **Person, Hochholen** holt man mit ihm eine bewusstlose Person hoch (Skillcheck mit Z). Er wird nur verbraucht, wenn es klappt. Kaufen kann man ihn beim Rettungsdienst. Ohne Kasten sagt das Spiel, wo es einen gibt.
4. Nach einem Zusammenbruch durch Krankheit hilft auch der Verbandskasten nicht, dann geht nur das Krankenhaus.

## Installation

1. Braucht Core 1.10.0, `core_lib`, `core_factions` und `core_inventory` 1.4.0 (Tabletten und Verbandskasten als Items).
2. Ordner `core_ems` nach `resources/[core]/` kopieren. Die Tabellen legt das Script beim Start selbst an, das SQL steht zusätzlich in `database/ems.sql`.
3. In der `server.cfg` nach `core_factions`: `ensure core_ems`

## Ablauf für Mediziner

Alles geht nur im Dienst (Umkleide am Krankenhaus, `E`) und nur mit dem passenden Recht. Was man nicht darf, steht nicht im G-Menü.

| G-Menü, Rettungsdienst | Was passiert |
|---|---|
| Hochholen | Nur bei bewusstlosen Personen. Skillcheck mit `Z` (drei Runden), ohne Verbandskasten. Geht nicht, wenn jemand an einer Krankheit zusammengebrochen ist |
| Versorgen | Minigame mit `E`, dann volle Gesundheit. Ohne Verbandskasten |
| Untersuchen und behandeln | Zeigt Krankheiten, Stadium, Behandlungen und Preis. Behandeln nach einem Fortschrittsbalken und Zustimmung der Person |
| Verkaufen | Verbände, Verbandskästen, Tabletten zu festen Preisen |
| Krankenversicherung | Verkaufen oder verlängern (30 Tage) |
| Ausweis verlangen | Die Person entscheidet mit Y oder N, ob sie ihren Personalausweis zeigt |
| Medizinische Datenbank | Jede Person suchen (Name oder ID), Krankenakte, Versicherung, Verlauf, eigene Einträge |

**Alle anderen** holen eine bewusstlose Person über das G-Menü (Person, Hochholen) mit einem Verbandskasten hoch, den sie beim Rettungsdienst gekauft haben. Skillcheck mit `Z`, der Kasten wird nur bei Erfolg verbraucht. Selbst benutzt (Inventar) heilt er ein Stück.

Die Person stimmt jedem Kauf und jeder Behandlung zu (Y/N). Sie zahlt bar, sonst vom Konto. Alles Geld geht in die Kasse des EMS, nicht an den Mediziner. Preise stehen fest in `config.lua`, ein Preis vom Client wird nie angenommen.

**Krankenversicherung:** Gilt 30 Tage, danach neu kaufen. Mit Versicherung kosten Behandlungen und alles, was der Rettungsdienst verkauft, die Hälfte (`Insurance.InsuredFactor`).

## Krankheiten

Alle Krankheiten stehen in der Datenbank (`ems_diseases`), auch geheilte (für die Krankenakte). Die Uhr läuft nur, solange man online und wach ist.

| Krankheit | Heilung | Stadien | Symptome (steigend) |
|---|---|---|---|
| Erkältung | Tablette (ein Stadium pro Tablette) oder Mediziner | 3 | Husten, Niesen, verschwommene Sicht, kein Rennen |
| Kopfschmerzen | Tablette oder Mediziner | 3 | Kopfschmerz, Wackeln, kurze Blackouts (1 s) |
| Magen-Darm | Tablette oder Mediziner | 3 | Übelkeit, Erbrechen, Stolpern, wackeliger Gang, mehr Hunger und Durst |
| Bluthochdruck | nur Mediziner, 3 Behandlungen | 3 + Endstadium | Wackeln, Blackouts bis 2,5 s, Stolpern, kein Rennen |
| Demenz | nur Mediziner, 3 Behandlungen | 3 + Endstadium | Vergesslichkeit, Minimap weg, Blackouts, verwirrter Gang |

- **Tabletten:** einfach im Inventar benutzen. Eine zweite innerhalb von 5 Minuten bringt nichts.
- **Bluthochdruck und Demenz:** drei Behandlungen innerhalb einer Stunde, mindestens 10 Minuten Abstand. Klappt das nicht, verfällt die Serie. Ohne Behandlung wird es jede Stunde schlimmer.
- **Endstadium:** Man bricht zusammen. Hochholen vor Ort geht nicht, nur das Krankenhaus (Admins mit `/revive` schon). Danach steht die Krankheit wieder auf Stadium 2 und muss weiter behandelt werden.
- **Krank werden:** kleine Chance pro Minute online. Dazu: nass werden (Erkältung), Stress wie Rennen, Zielen, Schießen (Kopfschmerzen, Bluthochdruck), Essen (Magen-Darm).
- **Ansteckung:** Erkältung (3 m) und Magen-Darm (2 m) springen auf Leute in der Nähe über, je höher das Stadium, desto eher. Die Positionen prüft der Server.
- Höchstens 2 Krankheiten gleichzeitig. Nach einer Heilung ist man eine Stunde lang immun gegen dieselbe.

Alle Werte (Chancen, Zeiten, Stadien, Symptome, Preise) stehen in `config.lua` unter `Diseases`, Animationen und Kamera-Effekte in `data/symptoms_gta5.lua`.

## Admin

| Befehl | Recht | Wirkung |
|---|---|---|
| `/krankheit <ID> <krankheit> [stadium]` | `player.heal` (ab Junior Administrator) | Krankheit geben: `cold`, `headache`, `stomach`, `hypertension`, `dementia` |
| `/heilen <ID> [krankheit]` | `player.heal` | Alle oder eine Krankheit heilen |

Admins mit `factions.view` öffnen auch die Medizinische Datenbank. Jeder Blick in eine Akte wird geloggt (Kategorie `ems`, Aktion `records_view`), ebenso jeder Verkauf, jede Behandlung und jedes Hochholen.

## Für andere Scripts

```lua
-- Server
exports.core_ems:GetDiseases(characterId)               -- { { disease, label, stage } }
exports.core_ems:AddDisease(characterId, 'cold', 1)     -- z. B. verdorbenes Essen, Event
exports.core_ems:CureDisease(characterId, 'cold')

-- Client
exports.core_ems:GetDiseases()                          -- eigene Krankheiten (nur Anzeige, z. B. HUD)
```

Fehlercodes: `not_medic`, `not_on_duty`, `no_permission`, `too_far`, `not_dead`, `is_dead`, `hospital_only`, `target_busy`, `no_medkit` (nur beim Hochholen mit Verbandskasten), `not_diagnosed`, `too_fast`, `too_soon`, `not_sick`, `not_enough_money`, `target_full`, `consent_declined`, `consent_timeout`, `no_id_card`, `not_found`, `invalid_input`.

## Testen

`tests/test_ems.py` gegen MariaDB (siehe `tests/README.md`). Im Browser: `html/records.html` (mit `?id=311` eine andere Akte, mit `?empty` ohne Auswahl).

Nur im Spiel prüfbar: Symptome (Husten-Animation, Wackeln, Blackouts, Gangart, Stolpern), Animation beim Behandeln, wie stark sich die Symptome anfühlen.
