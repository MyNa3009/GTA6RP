# core_dispatch 1.0.0

Notrufe und MDT für die eigene Core. Jeder setzt mit `/dispatch Text` einen Notruf ab. Die Einheiten im Dienst bekommen einen Alarm am Bildschirmrand und arbeiten den Einsatz im MDT ab: übernehmen, Route setzen, dem Anrufer antworten, Notizen, abschließen mit Ergebnis und Bericht. Dazu Funkstatus wie beim echten FMS (0 bis 8), Disponieren für die Leitstelle, Archiv und Statistik. Als erster Dienst ist der Rettungsdienst (`ems` aus `core_factions`) eingerichtet. LSPD und andere kommen als weiterer Eintrag in `config.lua` dazu.

## Installation

1. Braucht Core 1.12.0 und `core_factions` 1.3.0.
2. Ordner `core_dispatch` nach `resources/[core]/` kopieren. Die Tabellen legt das Script beim Start selbst an, das SQL steht zusätzlich in `database/dispatch.sql`.
3. In der `server.cfg` nach `core_factions`: `ensure core_dispatch`
4. Die Rechte erscheinen im Organisationsmenü unter Anpassung in der Gruppe "Leitstelle (MDT)".

## Für alle: Notruf absetzen

| Eingabe | Was passiert |
|---|---|
| `/dispatch Person bewusstlos am Pier` | Notruf an den Rettungsdienst. Position schickt der Server mit, den Ortsnamen das Spiel |
| `/dispatch ems Unfall auf der Route 68` | Dienst über das erste Wort wählen (`ems`, `rd`, `medic`, `rettung`). Das Wort fällt weg |
| `/dispatch` | Formular: Dienst wählen, Schnellwahl (Person bewusstlos, Verkehrsunfall ...), ohne Namen melden, eigene Notrufe mit den Antworten der Leitstelle, Notruf zurückziehen |

- Die Antwort sagt die Einsatznummer (z. B. `EMS 26/0042`) und wie viele Einheiten im Dienst sind. Ist niemand im Dienst, bleibt der Notruf offen.
- Sobald jemand übernimmt, bekommt der Anrufer eine Meldung, ebenso jede Nachricht der Leitstelle und den Abschluss.
- Wer bewusstlos ist, kann trotzdem einen Notruf absetzen. Der bekommt dann mindestens "Dringend" und den Vermerk "bewusstlos".
- "Ohne meinen Namen melden": Die Einheiten sehen den Namen nicht, Admins schon.
- Spam-Schutz: 60 Sekunden zwischen zwei Notrufen, höchstens 2 offene pro Person. Schließt eine Einheit einen Notruf als "Missbrauch", ist die Person 30 Minuten gesperrt.

## Für Einheiten: MDT

Öffnen mit `F6`, `/mdt` oder `/dispatch` ohne Text (im Dienst). Den letzten Alarm übernimmt man ohne MDT mit `J`.

| Bereich | Inhalt |
|---|---|
| Funkstatus | Tastenfeld wie im RTW. 1 und 2 frei, 3 Einsatz übernommen, 4 am Einsatzort, 5 Sprechwunsch, 6 nicht einsatzbereit, 7 Patient aufgenommen, 8 am Krankenhaus. 0 ist der Notruf der Einheit selbst (zweimal drücken) und erzeugt sofort einen Einsatz "Einheit in Not" mit Lebensgefahr für alle. Dazu der eigene Funkrufname (z. B. `RTW 1/83-1`) |
| Einheiten | Wer im Dienst ist, mit Status als Ziffer, Funkrufname, Dienstnummer und aktuellem Einsatz. Status 0 und 5 stehen oben |
| Einsätze | Offene und laufende Einsätze nach Priorität und Alter, mit Entfernung. Filter: alle, offen, meine |
| Einsatz | Meldung, Anrufer, Ort, Entfernung, Zeit bis Übernahme und Ankunft. Übernehmen oder freigeben, Route setzen, Priorität, Nachricht an den Anrufer, Notiz für alle, Abschluss mit Ergebnis und Bericht, kompletter Verlauf |
| Leitstelle (dispatch.manage) | Nächste Einheiten zum Einsatz, freie zuerst, mit Entfernung vom Server. Zuweisen und abziehen. Jeden Einsatz abschließen |
| Archiv (dispatch.archive) | Abgeschlossene Einsätze, Suche nach Nummer, ID des Anrufers oder Stichwort, Filter nach Ergebnis. Statistik: Einsätze heute, Ø Zeit bis Übernahme und Ankunft, Missbrauch, die letzten 7 Tage |

Automatisch:
- Übernehmen setzt Status 3 und die Route zum Einsatz. Kommt man bis auf 40 m heran, springt der Status auf 4.
- Abschließen und Freigeben setzen Status 1.
- Neuer Alarm: Ton und Karte am rechten Rand. Lebensgefahr und "Einheit in Not" mit eigenem Ton.
- Blips für alle offenen Einsätze, der eigene mit Route.
- Wer den Dienst beendet, wird aus seinem Einsatz genommen. Ist niemand mehr dran, ist der Einsatz wieder offen.

Status geht auch per Befehl: `/status 2`.

## Rechte (pro Rang im Organisationsmenü)

| Recht | Startwert | Was |
|---|---|---|
| `dispatch.view` | ab Rang 1 | Alarme bekommen, MDT nutzen, Einsätze übernehmen und bearbeiten, an denen man dran ist |
| `dispatch.manage` | ab Rang 18 | Disponieren: Einheiten zuweisen und abziehen, jeden Einsatz bearbeiten und abschließen |
| `dispatch.archive` | ab Rang 6 | Archiv und Statistik |

Alles nur im Dienst.

## Admin

| Befehl | Recht | Wirkung |
|---|---|---|
| `/mdt ems` | `factions.view` | MDT eines Dienstes ansehen, auch anonyme Anrufer. Solange es offen ist, kommen neue Einsätze live dazu |
| `/mdt ems` | `factions.manage` | Zusätzlich wie die Leitstelle arbeiten: zuweisen, Nachricht, abschließen (z. B. Spam-Notrufe) |

Jeder Notruf, jede Übernahme, jede Zuweisung, jede Nachricht an den Anrufer und jeder Abschluss steht im Protokoll der Organisation (Bereich Einsatz, beim Anrufer und bei der Einheit). Funkstatus-Wechsel stehen im Bereich Dienst. Dazu das zentrale Log der Core (Kategorie `dispatch`).

## Einstellungen

Alles in `config.lua`: Dienste, Befehle, Tasten (`J`, `F6`), Textlängen, Spam-Schutz, Sperre bei Missbrauch, Prioritäten, Funkstatus mit Texten, Ergebnisse, Ankunftsentfernung, Rechte mit Startwerten. Blips in `data/blips_gta5.lua`.

Weiteren Dienst anlegen (z. B. LSPD, sobald es in `core_factions` steht):

```lua
{ key = 'lspd', faction = 'lspd', label = 'Polizei', prefix = 'LSPD', words = { 'lspd', 'pd', 'polizei', 'police' } },
```

## Für andere Scripts

```lua
-- Server: Notruf ohne Formular, z. B. stiller Alarm einer Bank oder ein Handy
exports.core_dispatch:SendCall('ems', { text = 'Stiller Alarm in der Fleeca Bank', pos = { x = 150.0, y = -1040.0, z = 29.0 },
    priority = 2, location = 'Legion Square', callerId = permanenteId, callerName = 'Fleeca Bank' })   -- gibt die Einsatznummer zurück
```

Ereignisse an den Client: `core_dispatch:call`, `core_dispatch:units`, `core_dispatch:self`, `core_dispatch:talk`, `core_dispatch:mine`.

Fehlercodes: `text_too_short`, `cooldown`, `too_many_open`, `blocked`, `no_position`, `invalid_service`, `not_member`, `not_on_duty`, `no_permission`, `not_unit`, `not_found`, `already_assigned`, `not_assigned`, `invalid_status`, `invalid_priority`, `invalid_result`, `no_caller`, `invalid_input`, `db_error`.

## Testen

`tests/test_dispatch.py` gegen MariaDB (siehe `tests/README.md`). Im Browser: `html/dispatch.html` (MDT), `?view=form` (Notruf), `?view=alert` (Alarm), `?rank=1` (ohne Leitstelle und Archiv), `?tab=archive`.

Nur im Spiel prüfbar: Ortsnamen, Töne, Blips und Route, automatisch "am Einsatzort" auf echten Wegen, Tasten `J` und `F6`.
