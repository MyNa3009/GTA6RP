# Core 1.7.9 (Testserver)

Eigene Core: Datenbank-, Identity-, Netzwerk- und Plattform-Bridge, permanente IDs, Login-Screen mit Registrierung, Charakterauswahl mit Erstellen und Löschen, Spawn mit letzter Position, eigenes Todes-System, ID über dem Kopf, Geld mit Bargeld und Bank, Teamränge mit Rechten, persönliche Admin-Keys, Admin-Dienst, Admin-Menü mit Befehlsliste, Admin-Werkzeuge, Tickets, Beobachten, A-Jail, Noclip, Bans für Accounts und Charaktere, zentrales Logging.

## Permanente ID

Jeder Charakter hat eine eigene permanente ID. Die steht über dem Kopf, in der Charakterauswahl und gilt in allen Befehlen (`/revive 17`, `/ajail 17 …`, `/ban 17 …`). Der Login (E-Mail) hat eine eigene Login-Nummer, dem mehrere Charaktere gehören. Multi-Account-Erkennung und Login-Bans gelten für den ganzen Login. Der Teamrang gilt nur für den einen Charakter: Twinks eines Admins sind normale Spieler, und in der Charakterauswahl hat niemand Admin-Rechte.

## Update von 1.7.8

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Im Admin-Dienst bist du unsterblich: Die Unverwundbarkeit wird laufend neu gesetzt (Ped und Spieler) und hält auch nach Beobachten, Wiederbeleben oder Sperren. Hunger und Durst machen im Dienst keinen Schaden.
3. Noclip: Ohne Tastendruck bleibst du genau an deiner Position. Schwerkraft, Geschwindigkeit und Einfrieren werden jeden Frame erzwungen, damit man nicht nach ein paar Sekunden nach unten driftet.
4. Neu: Das Aussehen im Dienst lässt sich mit `/admin` einstellen (Recht `admin.duty`, nur im Dienst, wird mit Dienstende nicht zurückgesetzt, aber beim Ausloggen). `/admin tarnung` wie ein normaler Spieler (kein roter Tag, nicht durchsichtig), `/admin tag an|aus`, `/admin alpha 0-255`, `/admin reset`. `/admin` ohne Wort öffnet weiter das Menü. Jede Änderung steht im Log (`duty_look`).

## Update von 1.7.7

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Admin-Menü fast im Vollbild (bis 2200 × 1300 px). Hinweise zur Person (aktive Strafen, neuer PC, verknüpfte Logins, Twinks) stehen ab 1600 px Breite in einer eigenen Spalte rechts statt über den Reitern. Ohne Hinweise nutzt die Akte die ganze Breite.
3. Tickets: Das Admin-Fenster wächst mit dem Bildschirm, das Spieler-Fenster ist etwas größer.
4. Alle UIs: lesbarere Grautöne, kein Gewicht 800 mehr, Abstände auf dem 4px-Raster, feinere Ränder in der Charakterauswahl, größere Symbole bei Hunger und Durst.
5. Die Farbe `info` (Blau) gibt es nicht mehr. Wer `Config.UI.Colors` angepasst hat, kann die Zeile löschen, sie wird ignoriert.

## Update von 1.7.6

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Bewusstlos-Bildschirm: feines Karo-Raster im roten Schein unten, läuft nach oben und zu den Seiten aus.

## Update von 1.7.5

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Bewusstlos-Bildschirm: Die Figur mit den Verletzungen ist weg. Rechts steht dafür "Getötet von ID 17", wenn ein Spieler getötet hat. Bei Sturz, Ertrinken oder eigener Schuld fehlt die Zeile. `data/body_gta5.lua` und `Config.Death.HitWindowSeconds` gibt es nicht mehr.

## Update von 1.7.4

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Neuer Bewusstlos-Bildschirm: großer Titel mit Puls, Taste zum Krankenhaus als Knopf, Leiste unten für die Wartezeit.
3. Links eine Figur mit den Treffern der letzten 3 Minuten vor dem Tod (Kopf, Oberkörper, Arme, Beine, `Config.Death.HitWindowSeconds`). Rechts Ursache, Uhrzeit und wie lange man schon bewusstlos ist.
4. Das Spielbild wird grau und dunkler, solange man bewusstlos ist (`Config.Death.ScreenEffect`, Effekt in `data/effects_gta5.lua`). Neue GTA-Daten: `data/body_gta5.lua` (Knochen zu Körperzone).

## Update von 1.7.3

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Positionen speichern: Bei sehr vielen Spielern wird die Pause zwischen zwei Spielern kürzer, damit eine Runde höchstens das halbe Intervall dauert.
3. ID über dem Kopf: Die Sichtlinie wird pro Spieler nur noch einmal pro Sekunde neu geprüft. Bei vielen Spielern auf einem Fleck spart das etwa drei Viertel der Prüfungen.

## Update von 1.7.2

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. `spawnmanager` steht jetzt unter `dependencies`. Er muss laufen (bei txAdmin standardmäßig an).
3. Das Recht `player.rename` kommt jetzt auch im Admin-Menü an.
4. Die Unverwundbarkeit aus dem Admin-Dienst endet jetzt auch dann, wenn die Meldung über das Dienstende nicht ankommt. Andere Scripts, die jemanden unverwundbar machen, werden dabei nicht überschrieben.

## Update von 1.7.1

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Die eingebaute Geldanzeige oben rechts ist jetzt standardmäßig aus (`Config.Money.Hud = false`). Geld wird weiter gebucht, `/geld` zeigt den Kontostand, und ein eigenes HUD bekommt die Werte über `exports.core:GetMoney()` oder `core:moneyChanged`. Mit `true` ist sie wieder da.

## Update von 1.7.0

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Noclip folgt jetzt der Maus: Schaust du nach unten und drückst W, fliegst du nach unten, schaust du nach oben, nach oben (`Config.Noclip.FollowCameraPitch = true`). Mit `false` fliegt W wie vorher immer waagerecht.

## Update von 1.6.0

1. Den Ordner `core` ersetzen und neu starten. Keine Migration, die Tabelle `admin_keys` legt die Core selbst an.
2. **Admin-Keys.** Jedes Teammitglied braucht jetzt einen eigenen Key. Bis es ihn eingegeben hat, hat es keine Rechte, wie ein Spieler. Darum nach dem Update als Erstes in der txAdmin-Konsole `adminkey <deine ID>` eingeben. Die Konsole zeigt den Key einmal an. Danach im Spiel `/aduty`, Key eingeben, und im Admin-Menü in der Akte jedes Teammitglieds einen Key erstellen. Ausschalten geht mit `Config.AdminKeys.Enabled = false`.
3. Neue Rechte in `Config.Ranks`: `vehicle.delete` (ab Junior) und `admin.keys` (ab Senior). Wer die Config angepasst hat, trägt sie nach.
4. `/dv` braucht jetzt `vehicle.delete` statt `vehicle.spawn` und geht auch außerhalb des Admin-Diensts. Der Server prüft, dass das Fahrzeug wirklich in der Nähe ist.
5. Noclip: Man ist jetzt auch für sich selbst unsichtbar (`Config.Noclip.VisibleForSelf`) und landet beim Ausschalten auf dem Boden darunter, auch aus der Luft (`Config.Noclip.GroundOnExit`).
6. Befehlsliste im Admin-Menü und Chat-Vorschläge zeigen nur noch Befehle, die man wirklich benutzen darf.

## Update von 1.5.2

1. Den Ordner `core` ersetzen und neu starten. Keine Migration.
2. Neu für das Inventar 1.0.0: Kopfbild für den Ausweis, Fahrzeug-Infos für den Kofferraum, Hände-hoch-Animation. `core_inventory` 1.0.0 braucht mindestens diese Core.
3. Neuer Export `exports.core:GetCharacterRecord(characterId)`: Vorname, Nachname, Geburtsdatum, Geschlecht, auch offline.

## Update von 1.5.1

1. Den Ordner `core` ersetzen und neu starten.
2. Hunger und Durst: Die Leisten sind jetzt immer zu sehen (außer im Pausemenü), auch wenn ein anderes Script die Minimap ausblendet. Nur mit Minimap: `Config.Needs.HideWithMinimap = true`.
3. Fehlersuche: `/hungerdurst` schreibt den Stand der Anzeige in die F8-Konsole.

## Update von 1.5.0

1. Den Ordner `core` ersetzen und neu starten. Keine neue Migration.
2. Neu: `/namechange 17 Vorname Nachname` ändert den Namen eines Charakters, auch offline. Recht `player.rename` (ab Administrator), nur im Admin-Dienst, nicht bei gleichem oder höherem Rang. Doppelte Namen werden abgelehnt. Steht im Log (`character.namechange`) mit altem und neuem Namen.

## Update von 1.4.1

1. Den Ordner `core` ersetzen und neu starten. Keine neue Migration. Zusammen mit `core_inventory` 0.6.0 einspielen.
2. **Bargeld liegt jetzt im Inventar** (`Config.Money.CashInventory = 'core_inventory'`). Alle Geld-Exports und Befehle bleiben gleich, die Core bucht das Bargeld nur dort. Die Bank bleibt in der Core.
3. Neu in der Client-Bridge: Waffe in die Hand und Munition lesen, Kleidung setzen.
4. Die Akte zeigt bei Waffen die Seriennummer und die Munition.

## Update von 1.4.0

1. Den Ordner `core` ersetzen und neu starten. Nur Texte im Log der Akte für das Umräumen im Inventar (ab `core_inventory` 0.5.0).

## Update von 1.3.1

1. Den Ordner `core` ersetzen und neu starten. Die Spalten `hunger` und `thirst` legt die Core beim Start selbst an (`010_needs.sql` geht auch von Hand).
2. Neu: Hunger und Durst, siehe "Hunger und Durst" unten. Einstellungen in `Config.Needs`.
3. `/heal` füllt jetzt auch Hunger und Durst auf.

## Update von 1.3.0

1. Den Ordner `core` ersetzen und neu starten. Keine neue Migration.
2. Neu in der Bridge: `Platform.BlockWeaponWheelThisFrame()` für das Inventar (Waffenrad sperren).
3. Beim Start steht die Version in der Konsole: `[core] Core 1.3.1, Datenbank verbunden, …`

## Update von 1.2.0

1. Den Ordner `core` ersetzen und neu starten. Keine neue Migration.
2. Neu in der Akte: Reiter "Inventar" mit Taschen, Kleidung und Rucksack des gewählten Charakters. Erscheint nur, wenn `core_inventory` läuft. Jedes Ansehen steht im Log (`admin.view_inventory`).
3. Items an eigene Charaktere geben wird als Twink-Interaktion gemeldet (`Config.Twinks.Interactions.item_give`, Standard `warn`).

## Update von 1.1.0

1. Den Ordner `core` ersetzen und neu starten.
2. Neu: Schnittstelle für andere Resources (siehe "Für andere Resources" unten), neues Recht `items.manage` (ab Senior Administrator).
3. Für das Inventar zusätzlich `core_inventory` installieren, siehe dessen README.

## Update von 1.0.2

1. Den Ordner `core` ersetzen und neu starten. Die Core legt `audit_log_archive` selbst an (`009_log_archive.sql` geht auch von Hand).
2. Ab jetzt wandern Log-Einträge älter als 90 Tage jede Nacht zwischen 5 und 6 Uhr ins Archiv. Einmal sofort geht in der txAdmin-Konsole mit `logarchive`.
3. Backups einrichten, siehe Abschnitt "Backups".
4. Charakterauswahl ist ruhiger gestaltet (Zeilen statt Avatar-Kreise, keine Icon-Schrift mehr). Der Login bleibt wie er war.

## Update von 1.0.1

1. Den Ordner `core` ersetzen und neu starten.
2. Wer `shared/config.lua` angepasst hat: `Config.AdminDuty.TagFormat` heißt jetzt `TagLines` (eine Zeile pro Eintrag, Platzhalter `{rank}`, `{name}`, `{id}`), `Config.Overhead.Label` nutzt `{id}` statt `%d`.

## Update von 1.0.0

1. Den Ordner `core` ersetzen und neu starten. Nichts weiter zu tun.
2. Befehlsliste im Admin-Menü wird jetzt wirklich angezeigt, Ticket-Fenster neu gestaltet.

## Update von 0.9.9

1. Den Ordner `core` ersetzen und neu starten. Die Core legt die Tabellen `tickets` und `ticket_messages` selbst an (`008_tickets.sql` geht auch von Hand).
2. Neue Rechte `tickets.manage` (ab Assistant) und `player.spectate` (ab Junior) in `Config.Ranks`.

## Update von 0.9.8

1. Den Ordner `core` ersetzen und neu starten. Nichts weiter zu tun.
2. Noclip fliegt mit W und S jetzt immer waagerecht (`Config.Noclip.FollowCameraPitch`), Shift ist schneller (350 m/s).

## Update von 0.9.7

1. Den Ordner `core` ersetzen und neu starten. Keine neuen Tabellen.
2. Neue Rechte `admin.esp` (ab Assistant) und `player.kill` (ab Administrator) in `Config.Ranks`.
3. Tasten sind jetzt für deutsche Tastaturen eingestellt (`Config.Keyboard.Layout = 'de'`). Noclip liegt wirklich auf Z, nicht mehr auf Y. Weil die Tasten unter neuen Einträgen in den GTA-Einstellungen stehen, gilt das auch für alle, die schon mal auf dem Server waren. Wer sich eine Taste selbst umgelegt hatte, muss das einmal neu machen.

## Update von 0.9.6

1. Den Ordner `core` ersetzen und neu starten. Keine neuen Tabellen.
2. Neue Rechte in `Config.Ranks`. Wer die Config angepasst hat, trägt die neuen Rechte bei den Rängen nach. Welcher Befehl welches Recht braucht, steht in der Testtabelle.
3. Dimensionen brauchen OneSync, das läuft auf dem Testserver schon.

## Update von 0.9.5

1. Den Ordner `core` ersetzen und neu starten. Die Core ergänzt die Spalten selbst (`007_character_ranks.sql` geht auch von Hand).
2. Teamränge gelten jetzt pro Charakter. Beim ersten Start bekommt der zuletzt gespielte Charakter jedes Logins dessen alten Rang, alle anderen Charaktere sind Spieler.
3. Verwarnen geht erst ab Server Administrator.

## Update von 0.9.4

Den Ordner `core` ersetzen und neu starten. Die Tabelle `warns` legt die Core selbst an (`006_warns.sql` geht auch von Hand). Meldungen kommen jetzt oben rechts statt im Chat.

## Update von 0.9.3

Den Ordner `core` ersetzen und neu starten. `/geldgeben` und `/geldnehmen` heißen jetzt `/givemoney` und `/removemoney`.

## Update von 0.9.2

Den Ordner `core` ersetzen und neu starten. Die Tabellen `account_devices`, `account_ips` und `device_alerts` legt die Core selbst an (`005_devices.sql` geht auch von Hand).

## Update von 0.9.1

Den Ordner `core` ersetzen und neu starten. Keine neuen Tabellen.

## Update von 0.9.0

1. Den Ordner `core` ersetzen und neu starten. Keine neuen Tabellen.
2. Die ID über dem Kopf ist ab jetzt die Charakter-ID. Deine eigene siehst du mit `/meineid`.
3. `/setrank` nimmt jetzt die permanente ID eines Charakters und setzt den Rang für dessen ganzen Login.
4. Alte A-Jails ohne Charakter werden beim Start beendet.

## Update von 0.8.x

1. Den Ordner `core` ersetzen. Die Tabellen `bans` und `admin_jails` legt die Core beim Start selbst an (`004_punishments.sql` geht aber auch von Hand).
2. Server über txAdmin neu starten.

## Update von 0.7.x

1. Den Ordner `core` ersetzen. Die Tabellen `account_links`, `bans` und `admin_jails` legt die Core beim Start selbst an.
2. Server über txAdmin neu starten.

## Update von 0.2.x

1. In phpMyAdmin bei der Datenbank `fivem` unter **SQL** nacheinander `database/migrations/002_characters.sql`, `003_account_links.sql` und `004_punishments.sql` ausführen.
2. Den Ordner `core` ersetzen.
3. Server über txAdmin neu starten.

## Neuinstallation

1. `database/schema.sql` in phpMyAdmin ausführen (enthält schon alle Spalten).
2. Den Ordner `core` nach `resources/[core]/core` kopieren.
3. In der `server.cfg`:

```cfg
set core_debug "true"

ensure oxmysql
ensure core
```

## Test

| Schritt | Erwartet |
|---|---|
| Irgendein Befehl, z. B. `/meineid` | Kurze Zeile oben rechts unter der Geldanzeige. Vor dem Text steht "Erledigt" (gold), "Fehler" oder "Warnung" (rot), Hinweise ohne Wort. Gleiche Meldung mehrmals: `×2` |
| Joinen | Login-Screen in der Mitte, bei bekanntem Gerät steht die E-Mail schon drin und der Cursor im Passwortfeld (`Config.Accounts.RememberEmail`) |
| Einloggen | Charakterauswahl erscheint |
| Ohne Charakter | Formular "Dein erster Charakter" |
| Charakter erstellen | Erscheint in der Liste, Eintrag `character / create` im Log |
| Spielen | Spawn am Startpunkt (erstes Mal) bzw. an der letzten Position |
| `/relog` | Position wird gespeichert, zurück zum Login |
| Reconnecten, gleicher Charakter | Spawn an der letzten Position |
| Charakter löschen | Verschwindet aus der Liste, bleibt in der Datenbank mit `deleted_at` |
| Sterben | Kein Blackscreen, man bleibt liegen, Anzeige "Du bist bewusstlos" mit Countdown |
| Nach dem Countdown E halten | Kurz abblenden, Aufwachen am Krankenhaus aus `data/spawn_gta5.lua` |
| `/revive` oder `/revive 17` | Wiederbeleben an Ort und Stelle, 17 = permanente ID (Recht `player.revive`) |
| Zweiter Spieler in der Nähe | Über seinem Kopf steht `ID: <permanente ID>` seines Charakters, über dem eigenen nicht |
| Zweiten Charakter erstellen und spielen | Neue permanente ID über dem Kopf |
| Nach dem Spawn | Keine Geldanzeige (Standard). Mit `Config.Money.Hud = true` oben rechts Bargeld und Bank |
| `/geld` | Chat: eigener Kontostand |
| `/givemoney cash 17 500` oder `/givemoney bank 17 2500` | Geld für ID 17, auch wenn sie offline ist. Online: `+500 $` in der Anzeige (Recht `money.manage`) |
| `/removemoney cash 17 200` | Geld weg, bei zu wenig: "Nicht genug Geld." |
| `/ueberweisen 17 250` | Bank an ID 17, beide Anzeigen ändern sich (nur Debug-Modus) |
| `/geben 17 50` | Bargeld an ID 17 (nur Debug-Modus) |
| txAdmin-Konsole: `setrank 1 chief` | Charakter 1 ist Chief Administrator, seine Twinks bleiben Spieler |
| Admin spielt seinen Twink | Kein Admin-Menü, kein `/aduty`, Rang "Spieler" |
| `/rang` | Chat: eigener Teamrang |
| `/raenge` | Chat: alle Rang-IDs für `/setrank` |
| `/setrank 7 junior` | Nur mit `ranks.manage`, nur unterhalb des eigenen Rangs |
| Befehl ohne Recht | "Dafür hast du keine Rechte.", Eintrag `security / command_denied` |
| txAdmin-Konsole: `adminkey 1` | Konsole zeigt den Admin-Key für ID 1, nur dieses eine Mal |
| Teammitglied ohne Key: `/ban 17 1d Test` | "Gib zuerst deinen Admin-Key ein: /aduty", keine Rechte bis zur Eingabe |
| Erstes `/aduty` oder F10 | Fenster "Admin-Key". Richtiger Key: Rechte frei bis Relog oder Disconnect, bei `/aduty` startet der Dienst gleich mit |
| Fünfmal falscher Key | 15 Minuten gesperrt, Meldung an alle mit `admin.keys`, Einträge `admin_key_failed` und `admin_key_locked` |
| Akte eines Teammitglieds, Übersicht | Bereich "Admin-Key": erstellen, neu erstellen oder löschen (Recht `admin.keys`, nur Ränge unter dir, nie eigene Charaktere). Der neue Key steht nur einmal da, der alte gilt sofort nicht mehr |
| Chat: `/` tippen als Spieler | Keine Admin-Befehle in den Vorschlägen |
| `/aduty` | Admin-Dienst an oder aus: durchsichtig, unsterblich, Rang + Name + ID rot über dem Kopf. Mit `/admin tarnung` unauffällig wie ein Spieler |
| `/revive`, `/givemoney` ohne Dienst | "Das geht nur im Admin-Dienst." |
| F10 oder `/admin` | Admin-Menü (Recht `admin.menu`) |
| Spieler anklicken | Akte des Charakters, mit Login-Nummer, allen Charakteren derselben Person und allen Log-Einträgen. Einträge anderer Charaktere sind mit "Als Name (ID x)" markiert |
| Wiederbeleben, Zu Spieler, Holen | Nur im Dienst und mit Recht, jede Aktion im Log |
| Akte, Tab Tode | "Getötet von Name (ID 9) · Waffe: Pistole", beim Täter "Hat jemanden getötet · Opfer: Name (ID 12)" |
| Akte, Tab Geld | "Von Name (ID 23)", "An Name (ID 9)", "Gebucht durch Name (ID 1)" |
| Zweiter Account mit derselben Rockstar-Lizenz | Rote Warnung in beiden Akten, "Multi-Account" in der Spielerliste, Chat-Meldung an Admins. Egal ob der andere Account online ist |
| Admin-Menü, Reiter Alle | Jeder Charakter als eigene Zeile, auch offline, zuletzt gespielt zuerst, seitenweise nachladen |
| Admin-Menü, Reiter Warnungen | Alle offenen Multi-Account-Warnungen, auch wenn beide offline sind |
| Serverstart | Alte Treffer aus dem Log werden einmalig nachgetragen |
| Warnung ausblenden / Wieder anzeigen | Recht `accounts.links`, beides im Log |
| `audit_log`, Kategorie `money` | Jede Buchung mit Kontostand vorher und nachher |
| `/warn 17 RDM am Würfelpark` | ID 17 sieht "Verwarnung … (1 von 3)" 20 Sekunden lang rot oben rechts. Offline: beim nächsten Spielen. Recht `player.warn` (ab Server Administrator) |
| `/warn 17 30 RDM` | Verwarnung plus 30 Minuten A-Jail |
| Dritte aktive Verwarnung eines Charakters | Automatisch 7 Tage Charakter-Ban, Admins bekommen eine rote Meldung. Die drei Verwarnungen zählen danach nicht mehr (`Config.Warns`). Verwarnungen zählen 90 Tage |
| `/bring 17` | ID 17 wird zu dir geholt (nicht aus dem A-Jail). Recht `player.teleport` |
| `/tp 17` | Du teleportierst dich zu ID 17 |
| `/tp 215.3 -810.2 30.7` oder `/tp 215.3, -810.2` | Zu Koordinaten, ohne Höhe direkt auf den Boden |
| `/tp` ohne alles | Zu einem zufälligen anderen Spieler |
| `/goto 17` | Wie `/tp 17` |
| Ziele bei den Werkzeugen | `17` (permanente ID), `r 20` oder `r20` (alle im Umkreis von 20 m, nur in deiner Dimension), `all` (alle im Spiel, Recht `admin.mass` ab Server Administrator). Ohne Ziel bist du selbst gemeint, wo das Sinn ergibt |
| `/freeze 17`, `/freeze r 20`, `/freeze all` | Eingefroren: kein Laufen, Fahren, Schießen, kein Noclip. Kamera, Chat und Funk gehen. Nur niedrigere Ränge. Recht `player.freeze` (ab Junior) |
| `/unfreeze 17`, `/unfreeze r 20`, `/unfreeze all` | Wieder frei. Ausloggen taut auch auf |
| `/heal`, `/heal 17`, `/heal r 20`, `/heal all` | Volle Gesundheit. Bewusstlose werden übersprungen, dafür `/revive`. Recht `player.heal` (ab Junior) |
| `/armor`, `/armor 17`, `/armor r 20 50`, `/armor all` | Weste, ohne Wert 100 |
| `/fixcars` | Repariert das Fahrzeug, in dem du sitzt oder auf das du schaust (bis 30 m). Recht `vehicle.fix` (ab Junior) |
| `/fixcars r 30` | Alle Fahrzeuge im Umkreis von 30 m |
| `/cartp 17`, `/cartp 215 -810` | Am Steuer: mit dem Fahrzeug und allen Insassen teleportieren. Recht `player.teleport` |
| `/dim`, `/dim 5`, `/dim 0` | Eigene Dimension anzeigen oder wechseln, 0 ist die normale Welt. Recht `admin.dimension` (ab Junior) |
| `/setdim 17 5` | ID 17 in Dimension 5. Nicht im A-Jail, nur niedrigere Ränge. Recht `player.dimension` (ab Administrator) |
| Dimension und Teleport | `/tp`, `/goto` und `/bring` nehmen die Dimension mit, damit man sich sieht. A-Jail und Ausloggen setzen auf 0 zurück. Im Admin-Menü steht "Dim 5" neben dem Namen |
| `/dm 17 Komm bitte in den Warteraum` | ID 17 sieht in der Bildschirmmitte eine goldene "Teamnachricht von <Name>". Recht `admin.message` (ab Assistant) |
| `/dm r 30 Alle kurz herhören`, `/dm all Neustart in 5 Minuten` | An alle im Umkreis (ohne dich selbst) oder an alle im Spiel (`all` braucht `admin.mass`) |
| `/silentk 17 Cheat-Verdacht` | ID 17 fliegt und sieht nur einen Verbindungsabbruch. Der echte Grund und wer es war steht in der Akte unter "Still gekickt". Grund optional. Recht `player.silentkick` (ab Server Administrator) |
| `/gun`, `/gun 17 carbinerifle 120`, `/gun r 20 pistol`, `/gun all` | Waffe geben, ohne Angabe Pistole mit 250 Schuss. Namen wie `pistol`, `combatpistol`, `smg`, `pumpshotgun`, `carbinerifle` (Liste in `data/weapons_gta5.lua`). Nicht im A-Jail. Recht `weapon.give` (ab Server Administrator) |
| `/regun 17`, `/regun 17 pistol`, `/regun r 20` | Nimmt die Waffen wieder weg, die ein Admin mit `/gun` gegeben hat. Andere Waffen bleiben. Charakterwechsel nimmt sie auch weg |
| `/kill`, `/kill 17`, `/kill r 20`, `/kill all` | Bewusstlos machen, danach greift das normale Todes-System. Ohne Ziel du selbst. Übersprungen: höhere Ränge, Admins im Dienst, schon Bewusstlose. Recht `player.kill` (ab Administrator) |
| `/dm 17 …` beim Empfänger | Die Teamnachricht steht groß in der Bildschirmmitte, höchstens zwei auf einmal |
| `Tab` im Admin-Dienst | Erkennungsmodus: über jedem Spieler bis 150 m, auch durch Wände: permanente ID, Name, Login, Server-ID, Rang, Gesundheit, Weste, Entfernung und in Farbe "Offene Warnung", "Verwarnungen 2 von 3", A-Jail, Eingefroren, Bewusstlos, Im Admin-Dienst, Dimension. Nochmal Tab oder Dienstende schaltet ab. Recht `admin.esp` (ab Assistant), An und Aus im Log |
| `/report` (jeder Spieler) | Ticket-Fenster: Kategorie wählen, Nachricht schreiben, senden. Ein offenes Ticket pro Charakter. Zwischen zwei Nachrichten 25 Sekunden Pause, der Knopf zählt runter |
| Neues Ticket | Alle Teammitglieder im Dienst bekommen "Neues Ticket #12 von Mira Brandt (ID 3): Bug oder Fehler. Übernehmen mit /claim 12" |
| `/claim 12` oder "Übernehmen" | Ticket gehört dir, der Spieler bekommt Bescheid, das Fenster öffnet sich. Ein anderer Admin kann es nicht übernehmen, solange du online bist. Recht `tickets.manage` (ab Assistant), nur im Dienst |
| `/tickets` oder Knopf "Tickets" im Admin-Menü | Team-Ansicht: Offen, Meine, Geschlossen, Suche nach permanenter ID. Die Zahl am Knopf zeigt, wie viele noch niemand übernommen hat |
| Im Ticket als Admin | Schreiben ohne Pause. "Hingehen" teleportiert zum Spieler, "Beobachten" startet `/spec`, "Freigeben" gibt es wieder ab, "Schließen" beendet es |
| Ticket geschlossen | Spieler sieht den Verlauf weiter, kann aber nicht mehr schreiben und muss für ein neues Anliegen ein neues Ticket erstellen. "Wieder öffnen" kann nur das Team, wer öffnet, übernimmt es |
| Nachrichten | Jede Nachricht mit Name, permanenter ID und Uhrzeit, live bei allen, die das Ticket offen haben. Übernehmen, Freigeben, Schließen und Öffnen stehen als graue Zeile im Verlauf und im Log (Kategorie `ticket`) |
| `/spec 17` | ID 17 unsichtbar beobachten. Du wechselst automatisch in seine Dimension. `/spec 18` wechselt, `/spec` beendet und bringt dich zurück an die alte Stelle. Geht der Spieler offline, endet es von selbst. Recht `player.spectate` (ab Junior), Start und Ende in der Akte des Beobachteten |
| Admin-Menü, Knopf "Befehle" | Alle Befehle mit kurzer Erklärung und ab welchem Rang. Was du nicht darfst, ist ausgegraut. Oben suchen, z. B. nach "ticket" |
| Akte | Jede dieser Aktionen steht bei jeder betroffenen Person, auch bei `r` und `all`
| `/unwarn 15 Einspruch` | Verwarnung 15 zurückgenommen, die Warn-ID steht in der Akte unter Strafen |
| `/kick 17 Bitte Mikro fixen` | ID 17 fliegt mit Grund und Rang des Admins. Recht `player.kick` (ab Administrator) |
| Im A-Jail | Oben in der Mitte ohne Kasten: "A-Jail, noch", große Restzeit, dünne Linie, Grund |
| Akte | Buttons "Verwarnen" und "Kicken", Verwarnungen im Reiter Strafen mit "Zurücknehmen" |
| Mehr als 20 Anfragen pro Sekunde von einem Spieler | Werden abgelehnt, einmal pro Minute als `security / rate_limited` im Log |
| Login an einem zweiten PC (Freund loggt sich ein) | Rote Chat-Meldung an alle Admins, rote Warnung "Anmeldung an einem neuen PC" in der Akte und unter Warnungen. Ausblenden mit Recht `accounts.links` |
| Zweiter Login am selben PC | Multi-Account-Warnung "gleicher PC", auch mit anderer Rockstar-Lizenz |
| Login gebannt, neuer Rockstar-Account am selben PC | Verbindung abgelehnt (`Config.Bans.BlockHardware`) |
| Akte, Übersicht | Bekannte PCs, IP-Adressen nur mit Recht `data.private`, IPs werden nach 30 Tagen gelöscht |
| Überweisung zwischen eigenen Charakteren | Geht durch, landet blau unter "Twink-Interaktionen" in der Akte und im Reiter Twinks (`Config.Twinks`, auf `block` stellen zum Sperren) |
| `Z` (deutsche Tastatur) oder `/nc` im Admin-Dienst | Noclip: W fliegt dahin, wohin man schaut, auch nach oben und unten. A S D, Leertaste hoch, Strg runter, Shift sehr schnell, Alt langsam. Unsichtbar für alle, auch für einen selbst. Beim Ausschalten auf dem Boden darunter. Recht `admin.noclip` (ab Junior) |
| `/car adder` | Fahrzeug spawnt, man sitzt am Steuer, Kennzeichen `ADMIN`. Recht `vehicle.spawn` (ab Server Administrator), nur im Dienst |
| `/dv` | Löscht das Fahrzeug, in dem man sitzt, sonst das nächste in 6 m. Recht `vehicle.delete` (ab Junior), auch ohne Dienst |
| `/boost 300` am Steuer | Fahrzeug bis zu 300 % schneller, bis 500 km/h. `/boost 0` schaltet ab. Recht `vehicle.boost` (ab Senior Administrator) |
| `/nc` ohne Dienst | "Noclip geht nur im Admin-Dienst." Dienstende schaltet Noclip automatisch aus |
| `/ajail 17 30 Trollen` | Charakter 17 sitzt 30 Minuten im A-Jail, oben in der Mitte läuft die Restzeit. Andere Charaktere derselben Person spielen normal. Recht `player.ajail` |
| Im A-Jail rauslaufen, Noclip, Auto | Nach spätestens einer Sekunde zurück, jeder Fluchtversuch im Log |
| Im A-Jail sterben | Aufwachen im A-Jail, nicht im Krankenhaus |
| Im A-Jail `/relog`, gleicher Charakter | Wieder im A-Jail. Die Zeit läuft nur, solange dieser Charakter gespielt wird |
| `/ajail` bei Offline-Spieler | Beim nächsten Spielen direkt im A-Jail |
| `/unjail 17` | Sofort raus, Spawn vor dem Gefängnistor. Auch offline |
| `/ban 17 3d Powergaming` | Nur Charakter 17 gesperrt: zurück in die Auswahl, dort "Gesperrt", nicht spielbar, nicht löschbar. Dauer: `30m`, `12h`, `7d`, `2w` oder `perm`. Recht `player.ban` (ab Server Administrator) |
| `/loginban 17 7d Cheating` | Der ganze Login von ID 17 (alle Charaktere) wird sofort gekickt und kommt nicht mehr rein, egal ob im Spiel, in der Auswahl oder im Login |
| Login gebannt, zweiter Login mit derselben Lizenz | Auch abgelehnt (`Config.Bans.BlockIdentifiers`) |
| `/unban 17`, `/loginunban 17` | Entbannt. Recht `player.unban` (ab Senior Administrator) |
| Admin-Menü, Akte | Buttons "A-Jail" und "Bannen" (auch offline), Kasten "Aktive Strafen" mit Entbannen und Entlassen, Reiter "Strafen" mit allen Bans und A-Jails |
| Sich selbst bestrafen | Nur mit `core_debug`, zum Alleine-Testen. Einen Login-Ban auf dich selbst hebst du in der txAdmin-Konsole mit `loginunban <ID>` auf |

## Hunger und Durst

- Werte von 0 bis 100 pro Charakter, gespeichert in der Datenbank (jede Minute und beim Ausloggen).
- Voll bis leer: Hunger 2 Stunden, Durst 1,5 Stunden echte Spielzeit (`Config.Needs.HungerMinutes`, `ThirstMinutes`).
- Bei 0 gehen alle 10 Sekunden 2 Gesundheit weg, bei beiden 0 doppelt so viel. Von voll bis bewusstlos dauert das etwa 8 Minuten.
- Kein Abfall, solange man bewusstlos ist, im Admin-Dienst oder im A-Jail.
- Nach Krankenhaus oder Wiederbeleben mindestens 40, damit man nicht sofort wieder umfällt.
- Anzeige: zwei schmale Leisten rechts neben der Minimap, ab 20 rot. Im Pausemenü ausgeblendet.

Für ein späteres HUD-Script:

```lua
-- Server
exports.core:GetNeeds(source)                            -- { hunger, thirst } oder nil
exports.core:AddNeeds(source, { hunger = 25, thirst = 40 })
exports.core:SetNeeds(source, { hunger = 100 })
-- Client
exports.core:GetNeeds()                                  -- { hunger, thirst } oder nil
AddEventHandler('core:needsChanged', function(needs) end) -- bei jeder Aenderung, nil beim Ausloggen
```
Eigenes HUD: `Config.Needs.Hud = false` schaltet die eingebauten Leisten ab, der Rest läuft weiter.

## Backups

Das Skript `tools/backup_db.sh` sichert die Datenbank jede Nacht als gepackte Datei, prüft sie und löscht Sicherungen, die älter als 14 Tage sind. Der Server läuft dabei weiter. Einmal einrichten, als root auf dem Ubuntu-Server:

1. Eigenen Datenbank-Benutzer nur zum Lesen anlegen (Passwort selbst ausdenken):
   ```sql
   CREATE USER 'backup'@'localhost' IDENTIFIED BY 'HIER_EIN_LANGES_PASSWORT';
   GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES, EVENT ON fivem.* TO 'backup'@'localhost';
   ```
2. Zugangsdaten in eine Datei, die nur root lesen kann:
   ```bash
   printf '[client]\nuser=backup\npassword=HIER_EIN_LANGES_PASSWORT\n' > /etc/fivem-backup.cnf
   chmod 600 /etc/fivem-backup.cnf
   ```
3. Skript an einen festen Ort kopieren und einmal von Hand testen:
   ```bash
   mkdir -p /opt/fivem-tools && cp tools/backup_db.sh /opt/fivem-tools/ && chmod 700 /opt/fivem-tools/backup_db.sh
   /opt/fivem-tools/backup_db.sh
   ```
   Danach liegt in `/var/backups/fivem` eine Datei wie `fivem_2026-10-31_0430.sql.gz`, und `backup.log` sagt `OK`.
4. Jede Nacht um 4:30 Uhr, vor dem Log-Archiv um 5 Uhr: `crontab -e` und diese Zeile eintragen:
   ```
   30 4 * * * /opt/fivem-tools/backup_db.sh > /dev/null 2>&1
   ```

Ordner, Aufbewahrung und Datenbankname lassen sich über `BACKUP_DIR`, `KEEP_DAYS` und `DB_NAME` ändern. Die Sicherungen liegen auf demselben Server. Fällt die Festplatte aus, sind sie mit weg. Darum ab und zu eine Datei auf einen anderen Rechner kopieren, zum Beispiel mit `scp`.

**Zurückspielen**

Erst in eine Test-Datenbank, damit nichts kaputtgeht:
```bash
mysql -e "CREATE DATABASE fivem_pruefen"
gunzip -c /var/backups/fivem/fivem_2026-10-31_0430.sql.gz | mysql fivem_pruefen
```
Passt alles: Server in txAdmin stoppen, dann dieselbe Datei in `fivem` einspielen (`gunzip -c … | mysql fivem`), Server starten, `fivem_pruefen` wieder löschen.

## Log-Archiv

- Einträge in `audit_log`, die älter als 90 Tage sind, wandern jede Nacht zwischen 5 und 6 Uhr (Serverzeit) nach `audit_log_archive`. Verschoben wird in Portionen zu 5000 mit kurzer Pause, der Server hängt dabei nicht.
- In der Akte steht am Ende jedes Log-Reiters "Ältere Einträge im Archiv ansehen". Das Archiv lässt sich dort genauso seitenweise durchblättern.
- `logarchive` in der txAdmin-Konsole startet es sofort.
- Einstellen in `Config.Log`: `ArchiveAfterDays` (0 schaltet ab), `ArchiveHour`, `ArchiveBatchSize`, `ArchivePauseMs`.

## Einstellen

- `shared/config.lua`
  - `Config.UI`: Farben, Servername, Währung
  - `Config.Characters`: Anzahl Plätze, Namenslänge, Mindest- und Höchstalter, Startgeld, Speicherintervall
  - `Config.Ranks`: Teamränge und ihre Rechte, jeder Rang erbt die Rechte darunter
  - `Config.AdminKeys`: Admin-Keys an oder aus, Fehlversuche bis zur Sperre, Dauer der Sperre
  - `Config.Admin`: Taste fürs Menü, Dienstpflicht für Aktionen, Einträge pro Seite
  - `Config.AdminDuty`: Durchsichtigkeit, Unverwundbarkeit, Farbe und Leuchten des Namens, Reichweite
  - `Config.Money`: Höchstbetrag pro Buchung, Geldanzeige an oder aus
  - `Config.Death`: Wartezeit bis zum Krankenhaus, Haltedauer der Taste
  - `Config.Overhead`: ID über dem Kopf (Reichweite, Sichtprüfung, Größe, Farbe, `ShowOwn` zum Alleine-Testen)
  - `Config.Login`, `Config.Accounts`: Login-Sperre, Passwortlänge, welche Identifier als Multi-Account zählen
  - `Config.Notify`: wie viele Meldungen gleichzeitig, wie lange je Art
  - `Config.Warns`: wie lange Verwarnungen zählen, ab wie vielen Admins gewarnt werden
  - `Config.Network.MaxRequestsPerSecond`: Spam-Schutz
  - `Config.Noclip`: Geschwindigkeiten, Unsichtbarkeit (auch für sich selbst), Landen auf dem Boden, Standardtaste
  - `Config.Devices`: Erkennung neuer PCs, Multi-Account über den PC, IP speichern und wie lange
  - `Config.Twinks`: welche Interaktionen zwischen eigenen Charakteren erlaubt (`warn`) oder gesperrt (`block`) sind
  - `Config.Vehicles`: Kennzeichen, Löschradius, höchster Boost, Höchstgeschwindigkeit
  - `Config.Keyboard`: deutsche (`de`) oder englische (`us`) Tastatur, alle Standardtasten sind so geschrieben, wie sie auf der Tastatur stehen
  - `Config.AdminEsp`: Taste, Reichweite, wie oft nachgeladen wird, Schriftgröße
  - `Config.Tickets`: Pause für Spieler (25 Sekunden), Länge der Nachrichten, Kategorien, ob auch Admins außerhalb des Diensts neue Tickets gemeldet bekommen
  - `Config.AdminTools`: größter Umkreis, Standardweste, Standardwaffe und Munition, höchste Dimension, Länge von `/dm`, Text beim stillen Kick
  - `Config.Punish`, `Config.Bans`, `Config.Jail`: Länge des Grunds, längster Ban, welche Identifier beim Verbinden gesperrt werden, Text für Entbannungsanträge, längstes A-Jail, Kampfsperre
- `data/spawn_gta5.lua`: Startpunkt und Respawn-Punkt
- `data/models_gta5.lua`: Spielermodelle
- `data/weapons_gta5.lua`: Waffennamen und Todesursachen für Log und Akte, Waffen für `/gun`
- `data/jail_gta5.lua`: Ort des A-Jails, Radius und Ausgang (Standard: Hof von Bolingbroke)

## Aufbau der UI

`html/index.html` ist die Shell und lädt jede UI als eigene Datei in einem iframe. Eventnamen beginnen mit dem UI-Namen (`login_open`, `char_open`). Jede UI lässt sich direkt im Browser öffnen und läuft dort mit Beispieldaten.

## Für andere Resources

Andere Resources (z. B. `core_inventory`) nutzen die Bridge und die Config der Core mit `@core/bridge/...` und `@core/shared/config.lua` im fxmanifest. Die Netzwerk-Events tragen den Resource-Namen (`core_inventory:cb:request`), dadurch kommen sich die Resources nicht in die Quere.

Exports (`exports.core:...`):

| Export | Gibt zurück |
|---|---|
| `GetCharacterInfo(source)` | `{ characterId, accountId, firstname, lastname, gender }` oder nil |
| `GetCharacterId(source)`, `GetAccountId(source)` | permanente ID bzw. Login |
| `GetSourceByCharacter(characterId)` | Server-ID, wenn online |
| `GetCharacterAccount(characterId)` | Login eines Charakters, auch offline, nil wenn es ihn nicht gibt |
| `GetActiveCharacters()` | `{ [source] = characterId }` aller, die gerade spielen |
| `HasPermission(source, recht)`, `IsOnDuty(source)` | true oder false |
| `AuthorizeCommand(source, name, recht, args, requireDuty)` | true und Login, sonst false. Prüft, meldet und loggt wie die Admin-Befehle der Core |
| `AddCommandHelp({ title, entries })` | Eigene Gruppe in der Befehlsliste des Admin-Menüs |
| `Log(eintrag)` | Eintrag ins zentrale Log |

Ereignisse auf dem Server: `core:characterLoaded (source, info)` und `core:characterUnloaded (source, characterId, grund)`.

Im Client: `exports.core:GetMoney()` gibt `{ cash, bank }` oder nil zurück. Das lokale Ereignis `core:moneyChanged` kommt bei jeder Buchung mit `{ cash, bank, changed }`, beim Ausloggen mit nil. Beides ist nur für die Anzeige. Ein Cheater kann diese Werte auf seinem eigenen Client fälschen, darum prüft der Server bei jedem Kauf selbst, ob genug Geld da ist. Kein Script darf den Geldstand vom Client an den Server schicken und ihm dort glauben.

## Regeln

### Performance

- Keine Schleife mit `Wait(0)`, außer sie zeichnet oder liest Tasten, und dann nur solange es nötig ist (Noclip, A-Jail, Boost am Steuer). Sonst ein Intervall in Millisekunden.
- Client-Schleifen, die gerade nichts zu tun haben, schlafen länger (Überkopf-Anzeige ohne Spieler in der Nähe, Boost ohne Fahrer).
- Datenbank nur, wenn sich etwas geändert hat (Position nur nach Bewegung) und nie für alle Spieler gleichzeitig (Speichern wird verteilt).
- Abfragen auf `audit_log` immer über einen Index. Kein `OR` über mehrere Spalten, stattdessen `UNION` der IDs und danach über den Primärschlüssel nachschlagen.
- Listen im Admin-Menü immer seitenweise. Zusatzprüfungen (Bans, A-Jail) nur für die Zeilen der Seite.
- Logs sammeln und alle 5 Sekunden gesammelt schreiben (`Core.Log`), nie einzeln pro Ereignis.
- Wächter (Bans, A-Jail) prüfen mit einer Abfrage für alle Spieler, nicht eine pro Spieler.

- FiveM-Natives nur in `bridge/`, GTA-5-Daten nur in `data/`.
- Keine GTA-Textcodes (`~r~`, `~n~` usw.) außerhalb der Bridge. Text über Köpfen wird als Zeilen aus Teilen `{ text, tone }` beschrieben und mit `Platform.PrepareWorldText` vorbereitet. Farbrollen: `normal`, `muted`, `accent`, `info`, `warning`, `danger`.
- oxmysql nur in `bridge/database`.
- Datenbank-Parameter, die `nil` sein können, immer mit `DB.Args(a, b, c)` übergeben, sonst kommen Lücken bei oxmysql falsch an.
- Meldungen an Spieler immer über `Platform.Notify(source, text, 'success' | 'error' | 'info' | 'warning')` auf dem Server oder `Notify.Show(text, typ)` im Client, nie über den Chat.
- Neue Server-Callbacks immer über `Core.RegisterCallback`. Die verlangen automatisch einen eingeloggten Spieler.
- Admin-Befehle immer über `Core.RegisterAdminCommand(name, recht, fn)`. Scripts fragen nach Rechten (`Core.HasPermission(source, 'player.ban')`), nie nach Rängen. `HasPermission` ist für Teammitglieder ohne eingegebenen Admin-Key immer `false`.
- Neue Befehle mit Recht gehören in die Befehlsliste (`server/admin_help.lua` oder `AddCommandHelp`). Daraus berechnet die Core auch, welche Chat-Vorschläge ein Spieler sieht.
- Jede Änderung an Accounts, Charakteren, Geld, Items usw. ruft `Core.Log` auf.
- Interaktionen zwischen zwei Charakteren (Items geben, Fahrzeug verkaufen) in Scripts mit `exports.core:ReportTwinkInteraction(charA, charB, 'item_give', { item = 'phone' })` melden. Gibt `false` zurück, wenn die Config die Interaktion sperrt.
- Geld nur über `Core.AddMoney`, `Core.RemoveMoney`, `Core.TransferMoney`, niemals direkt per SQL. Aufrufe immer aus einem Thread (Callback, Befehl, `CreateThread`), weil die Buchung auf die Datenbank wartet.
- Geloeschte Daten werden markiert, nicht entfernt, damit Admins sie weiter sehen.
- Testbefehle nur mit `set core_debug "true"`, niemals auf einem Live-Server.
- Das Speichern der Position braucht OneSync (bei txAdmin standardmäßig an).
