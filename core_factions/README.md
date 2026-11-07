# core_factions 1.0.0

Organisationen für die eigene Core: Ränge, Rechte pro Rang, Dienst an der Umkleide, Dienstfahrzeuge ab Rang, Abteilungen mit eigenen Rängen, Prüfungen, Leitstelle, Mitarbeiter-Archiv und eine Kasse. Alles läuft über ein Organisationsmenü mit fünf Tabs und das G-Menü. Als erste Organisation ist der Rettungsdienst (EMS) eingerichtet, LSPD und andere kommen später in dieselbe Config.

## Installation

1. Braucht Core 1.10.0, `core_lib` und `core_inventory` (für den Dienstausweis).
2. Ordner `core_factions` nach `resources/[core]/` kopieren. Die Tabellen legt das Script beim Start selbst an, das SQL steht zusätzlich in `database/factions.sql`.
3. In der `server.cfg` nach `core_lib`: `ensure core_factions`
4. Die Leitung setzt ein Admin: `/setorga <ID> ems 30` (Leader) und `/setorga <ID> ems 29` (Vice Leader). Alles Weitere macht die Leitung im Spiel.

## Ränge und Rechte

- Das EMS hat 30 Ränge. 30 ist der Leader, 29 der Vice Leader.
- Der Leader hat immer alle Rechte. Er kann dem Vice Leader Rechte wegnehmen, der Vice Leader ihm nicht.
- Leader und Vice Leader ändern Rangnamen, Rechte pro Rang, Fahrzeuge ab Rang, Abteilungen und Prüfungen. Jemand anderes kann das nicht, auch nicht mit Rechten.
- Wer in der Leitstelle was ändern darf (Einstellen, Entlassen, Befördern, Dienstnummer, Strikes, Urlaubstage, Abteilungen, Prüfungen), legt die Leitung pro Rang in Tab 2 fest. Die Startwerte stehen in `config.lua` unter `Permissions`.
- Rechte anderer Scripts (z. B. `ems.revive` aus `core_ems`) erscheinen im selben Tab in einer eigenen Gruppe.

## Das Organisationsmenü

Öffnen über das G-Menü (Organisation, Organisationsmenü) oder `/orga`. Jeder Tab erscheint nur, wenn man ihn sehen darf.

| Tab | Inhalt |
|---|---|
| Übersicht | Leader der Organisation, eigener Rang, Einstellungsdatum, Dienstnummer, Nachricht vom Leader, wer gerade im Dienst ist, Kasse (mit Recht) |
| Anpassung | Rangnamen und Rechte pro Rang, Abteilungen (jeweils bis zu 5 eigene Ränge), Prüfungen. Nur Leader und Vice Leader |
| Fahrzeuge | Welches Dienstfahrzeug ab welchem Rang. Nur Leader und Vice Leader |
| Leitstelle | Eine Zeile pro Mitarbeiter: Name, ID, Dienstnummer, Rang, Strikes, Urlaubstage, Abteilungen, Prüfungen. Bearbeiten je nach Recht |
| Archiv | Alle ehemaligen Mitarbeiter mit Grund, allen Rängen, unter welchem Leader sie die hatten, und ihren Prüfungen |

## G-Menü

Unter Organisation, immer mit der Person, die man anschaut:

- Organisationsmenü
- Leitung: Einstellen (die Person muss zustimmen), Befördern, Degradieren, Entlassen (mit Grund). Die Einträge erscheinen nur mit dem passenden Recht.
- Kündigen (selbst austreten, nicht als Leader)

## Dienst und Garage

- Am Krankenhaus gibt es einen Blip. An der Umkleide drückt man `E` und tritt den Dienst an oder beendet ihn. Umziehen kommt, wenn Kleidung als Item fertig ist.
- An der Garage parkt man im Dienst ein Fahrzeug aus, das der eigene Rang fahren darf, und wieder ein. Höchstens ein Fahrzeug pro Person gleichzeitig. Kennzeichen `EMS 4821`.
- Orte in `data/places_gta5.lua`, Fahrzeuge und Grenzen in `config.lua`.

## Admin

| Befehl | Recht | Wirkung |
|---|---|---|
| `/setorga <ID> <orga> <rang>` | `factions.manage` (ab Senior Administrator) | Einstellen oder Rang setzen, auch den Leader. Geht offline |
| `/removeorga <ID> [grund]` | `factions.manage` | Entfernen, kommt ins Archiv |
| `/orgaview <orga>` | `factions.view` (ab Administrator Assistant) | Organisationsmenü einer Organisation ansehen, mit `factions.manage` bearbeiten |

Alles wird geloggt (Kategorie `faction`).

## Für andere Scripts

```lua
-- Server
exports.core_factions:GetMember(source)                       -- { faction, rank, rankName, dn, onDuty, ... } oder nil
exports.core_factions:IsOnDuty(source, 'ems')
exports.core_factions:HasPermission(source, 'ems.revive', true)   -- true = nur im Dienst
exports.core_factions:RegisterPermissions('ems', { { key = 'ems.revive', group = 'Rettungsdienst', label = 'Hochholen', minRank = 1 } })
exports.core_factions:GetOnDuty('ems')                        -- Liste der Leute im Dienst
exports.core_factions:GetBalance('ems')
exports.core_factions:Deposit('ems', 250, { actorSource = source, reason = 'Verkauf' })
exports.core_factions:Withdraw('ems', 250, { actorSource = source, reason = 'Einkauf' })

-- Client
exports.core_factions:GetState()                              -- eigene Organisation, Rang, Dienst, Rechte
exports.core_factions:HasPermission('ems.revive', true)
exports.core_factions:IsOnDuty('ems')
exports.core_factions:OpenMenu()
```

Ereignisse: `core_factions:duty` (Server, `source, faction, onDuty`), `core_factions:stateChanged` (Client).

Fehlercodes: `not_member`, `not_on_duty`, `no_permission`, `rank_too_low`, `already_member`, `leader_cannot_leave`, `target_offline`, `too_far`, `vehicle_limit`, `not_faction_vehicle`, `no_vehicle`, `invalid_rank`, `invalid_ranks`, `invalid_name`, `invalid_model`, `invalid_field`, `invalid_amount`, `not_enough_money`, `limit_reached`, `not_found`, `db_error`.

## Testen

`tests/test_factions.py` gegen MariaDB (siehe `tests/README.md`). Im Browser: `html/orgmenu.html?tab=leitstelle` (auch `overview`, `structure`, `vehicles`, `archive`).

Nur im Spiel prüfbar: Blip und Markierungen, Ausparken an der richtigen Stelle, Setzen ans Steuer.
