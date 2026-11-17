# core_phone 1.1.0

Handy für die eigene Core. Das Handy ist ein Item im Inventar, die Nummer kommt von einer eSIM, die an der Person hängt. Mit dem Handy ruft man an, schreibt Nachrichten, schickt seinen Standort, verwaltet Kontakte, sieht sein Konto, überweist, bezahlt Schulden und setzt einen Notruf ab. Ist das Handy zu, zeigt eine kleine Zeile unten rechts Anrufe und neue Nachrichten.

Bank und Notruf sind Apps auf den Daten von `core_bank` und `core_dispatch`. Das Handy bucht und entscheidet dort nichts selbst.

## Update von 1.0.0

1. Ordner `core_phone` ersetzen und neu starten. Die neue Spalte `wallpaper` legt das Script beim Start selbst an, nichts von Hand ausführen.
2. **Neues Aussehen:** Das Handy sieht jetzt aus wie ein echtes Smartphone, mit Rahmen, Seitentasten, Kamera-Insel, großer Uhr, App-Leiste unten und Mitteilungen oben im Handy. Die Farben kommen wie immer aus `Config.UI.Colors` der Core.
3. **Hintergründe:** In den Einstellungen gibt es vier Hintergründe (Sphären, Eklipse, Wellen, Glut). Die Wahl bleibt gespeichert. Welche es gibt, steht in `Config.Phone.Wallpapers`. Neue erzeugt `tools/wallpapers.py`.
4. Kontakt anlegen, Überweisen und Forderung bezahlen öffnen sich als Blatt von unten, Löschen fragt in einem Dialog nach. Fehler stehen direkt am Feld.
5. Die Taste zum Öffnen (`F1`) schließt das Handy auch wieder.

## Installation

1. Braucht Core 1.20.0 und `core_inventory` 1.5.2. Für die Bank-App `core_bank` ab 1.0.3, für die Notruf-App `core_dispatch` ab 1.3.0. Fehlt eins davon, fehlt nur die App.
2. Ordner `core_phone` nach `resources/[core]/` kopieren. Die Tabellen legt das Script beim Start selbst an, das SQL steht zusätzlich in `database/phone.sql`.
3. In der `server.cfg` nach `core_bank` und `core_dispatch`: `ensure core_phone`
4. Server neu starten. Jeder Charakter bekommt beim nächsten Einloggen seine eSIM mit Nummer und einmal ein Handy geschenkt.

Für Gespräche braucht der Server Sprache: entweder `pma-voice` oder die eingebaute Sprache von FiveM (Mumble). Ohne Sprache klingelt es, aber man hört sich nicht.

## Handy und eSIM

- **Das Handy ist das Item `phone`.** Ohne das Item im Inventar geht nichts: nicht öffnen, nicht anrufen, nicht schreiben. Wer angerufen wird und kein Handy dabei hat, ist nicht erreichbar.
- **Die eSIM hängt an der Person, nicht am Gerät.** Nummer, Kontakte, Nachrichten und Anrufliste bleiben, wenn das Handy weg ist. Ein neues Handy hat sofort wieder alles. Wer ein fremdes Handy einsteckt, sieht darauf seine eigenen Daten, nicht die des Vorbesitzers.
- Die Nummer hat 6 Ziffern und wird beim ersten Einloggen vergeben. Sie steht in den Einstellungen des Handys.
- Solange es keinen Laden gibt, bekommt jeder Charakter einmal ein Handy geschenkt (`StarterPhone`). Weitere Handys geben Admins mit `/giveitem 17 phone` oder später ein Shop über `exports.core_inventory:AddItem`.

## Für Spieler

Öffnen mit `F1` (im Spiel änderbar), mit `/handy` oder durch Benutzen des Items im Inventar. `F1` schließt es wieder. `Escape` geht einen Schritt zurück und schließt am Ende. Der Strich unten im Handy führt zum Startbildschirm. Pfeiltasten, `Enter` und `Rücktaste` bedienen alles ohne Maus.

| App | Was geht |
|---|---|
| Telefon | Anrufliste mit verpassten Anrufen in Rot, Ziffernfeld (auch über die Tastatur, `Enter` ruft an). Klingelt 30 Sekunden, danach steht der Anruf als verpasst da |
| Nachrichten | Chats mit Nummer oder Kontaktname, ungelesene mit Zähler. Text bis 300 Zeichen, Standort senden, aus einem Standort einen Wegpunkt machen, Chat löschen. Nachrichten kommen auch an, wenn die Person offline ist |
| Kontakte | Bis zu 100 Kontakte mit Suche. Aus dem Kontakt anrufen oder schreiben. Unbekannte Nummern lassen sich aus dem Ziffernfeld und aus dem Chat speichern |
| Bank | Kontostand, Kontonummer, letzte Buchungen, Überweisen mit Prüfung des Empfängers, offene Forderungen ansehen und vom Konto bezahlen, auch in Teilen. Bargeld gibt es weiter nur in der Filiale und am Automaten |
| Notruf | Dienst wählen (mit Anzeige, wie viele Einheiten im Dienst sind), beschreiben, absenden. Der Standort geht mit. Es gelten dieselben Regeln wie bei `/dispatch` |
| Einstellungen | Eigene Nummer, Lautlos, Flugmodus, Hintergrund |

- **Gespräch:** Beim Anruf erscheint der Bildschirm mit Annehmen und Ablehnen. Während des Gesprächs kann man mit "Zum Handy" weiter das Handy bedienen, das Gespräch läuft als Leiste oben weiter. Auflegen geht immer. Wer bewusstlos wird oder den Server verlässt, legt automatisch auf.
- **Handy zu:** Ein Anruf erscheint unten rechts als Zeile mit der Taste zum Öffnen. Neue Nachrichten und verpasste Anrufe stehen dort ein paar Sekunden.
- **Lautlos:** kein Klingeln und kein Ton, die Anzeige kommt trotzdem.
- **Flugmodus:** nicht erreichbar, kein Senden. Nachrichten warten im Chat, Anrufe stehen als verpasst in der Liste.
- **Besetzt:** Wer gerade telefoniert, bekommt den zweiten Anruf als verpasst gemeldet.
- **Dienste:** Absender mit einem Namen statt einer Nummer (zum Beispiel "Bank") sind Nachrichten anderer Scripts. Darauf kann man nicht antworten.
- Bewusstlos geht das Handy nicht. Den Notruf gibt es dann im Bewusstlos-Bildschirm.

## Für Admins

| Befehl | Recht | Was |
|---|---|---|
| `/handy 17` | `player.view` | Handy der ID 17 ansehen, nur lesen: Kontakte, Anrufliste, alle Chats. Vom Spieler gelöschte Chats bleiben sichtbar und sind markiert. Geht auch, wenn die Person offline ist |
| `/nummer 482103` | `player.view` | Wem gehört die Nummer |

Die Rechte gelten wie überall erst nach `/aduty`. Jede Ansicht steht im Log (`phone.admin_view`).

Nachrichten liegen in der Datenbank (`phone_messages`) und werden nie entfernt, nur ausgeblendet. Im Log der Core (Kategorie `phone`, auch in der Akte im Admin-Menü) stehen: eSIM aktiviert, Handy geschenkt, jedes Gespräch mit Dauer, gelöschte Chats und Kontakte, Admin-Ansichten. Überweisungen und Zahlungen vom Handy loggt `core_bank` mit dem Kanal `phone`, Notrufe `core_dispatch`.

## Einstellen

Alles in `config.lua`:

| Wert | Standard | Bedeutung |
|---|---|---|
| `Key`, `Command` | `F1`, `handy` | Taste und Befehl zum Öffnen |
| `Item` | `phone` | Item, das man braucht. `nil` = Handy geht ohne Item |
| `StarterPhone` | `true` | Einmal ein Handy schenken, wenn die eSIM angelegt wird |
| `AllowWhenDead` | `false` | Handy auch bewusstlos |
| `NumberDigits` | `6` | Länge der Nummer |
| `MaxContacts`, `ContactNameMax` | `100`, `32` | Grenzen der Kontakte |
| `MessageMax`, `MessageCooldownMs` | `300`, `800` | Länge einer Nachricht und Pause zwischen zwei Nachrichten |
| `ThreadPage`, `ThreadsShown`, `CallsShown` | `30`, `40`, `40` | Nachrichten pro Seite, Chats und Anrufe in der Liste |
| `RingSeconds` | `30` | So lange klingelt es |
| `Volume` | `0.25` | Lautstärke der Töne, 0 bis 1 |
| `Wallpapers` | 4 Stück | Hintergründe zur Auswahl, der erste ist der Standard |
| `Bank.Enabled`, `Dispatch.Enabled` | `true` | Apps ein- und ausschalten |
| `Admin.ViewPermission` | `player.view` | Recht für `/handy <ID>` und `/nummer` |
| `Colors` | leer | Nur Farben eintragen, die von `Config.UI.Colors` der Core abweichen sollen |

Die Töne (Klingeln, Freizeichen, Nachricht, Auflegen) erzeugt die UI selbst. Es gibt keine Sounddateien und keine GTA-Sounds.

## Für andere Scripts

```lua
-- Server
exports.core_phone:GetNumber(characterId)          -- '482103' oder nil, auch offline
exports.core_phone:GetNumberOwner('482103')        -- permanente ID oder nil
exports.core_phone:HasPhone(characterId)           -- true, wenn die Person online ist und ihr Handy dabei hat

-- Nachricht eines Dienstes. Der Absender ist ein Name (Buchstaben, höchstens 12 Zeichen), darauf kann man nicht antworten.
exports.core_phone:SendServiceMessage(characterId, 'Bank', 'Deine Rechnung ist seit heute überfällig.')   -- true oder false
```

Ereignis an den Client: `core_phone:event` mit `{ type = 'open' | 'message' | 'call' | 'missed', ... }`.

Fehlercodes: `no_character`, `no_phone`, `is_dead`, `read_only`, `busy`, `no_permission`, `not_found`, `invalid_name`, `invalid_number`, `invalid_text`, `invalid_amount`, `own_number`, `unknown_number`, `contact_exists`, `contacts_full`, `too_fast`, `airplane`, `in_call`, `no_call`, `unreachable`, `line_busy`, `no_bank`, `unknown_account`, `same_account`, `not_enough_money`, `debt_closed`, `no_dispatch`, `server_error`, dazu die Codes von `core_dispatch` beim Notruf.

Der Vertrag zwischen Client und UI steht oben in `html/phone.html`.

## Aufbau

- `server/numbers.lua`: eSIM, Nummer, Kontakte, Startdaten des Handys, Admin-Ansicht.
- `server/messages.lua`: Chats. Jede Nachricht liegt zweimal in der Tabelle, einmal pro Seite. So kann jeder seinen Chat löschen, ohne dass er beim anderen verschwindet.
- `server/calls.lua`: Gespräche im Speicher, Anrufliste in der Datenbank.
- `server/apps.lua`: Bank und Notruf über die Exports von `core_bank` und `core_dispatch`.
- `server/admin.lua`: `/nummer` und die Einträge in der Befehlsliste.
- `client/main.lua`: Öffnen und Schließen, Anfragen der UI weiterreichen, Sprache im Gespräch.
- `html/phone.html`: die UI. Die Hintergründe darin erzeugt `tools/wallpapers.py` aus den Farben des Servers.
- `data/phone_gta5.lua`: die Haltung mit dem Handy in der Hand. Beim Umzug auf GTA 6 wird nur diese Datei ersetzt.

Der Server prüft bei jeder Anfrage, ob die Person einen Charakter spielt, bei Bewusstsein ist und das Handy im Inventar hat. Der Standort einer Standort-Nachricht und eines Notrufs kommt immer vom Server.

## Test

`python3 tests/test_phone.py` prüft die Serverlogik gegen MariaDB. Die UI läuft im Browser mit Testdaten: `html/phone.html`, dazu `?screen=phone|log|contacts|messages|thread|bank|debts|dispatch|settings`, `?wp=sphaeren|eklipse|wellen|glut`, `?admin`, `?leer`, `?anruf=incoming|dialing|active` und `?zu&anruf=incoming` oder `?zu&nachricht` für die Zeile bei geschlossenem Handy.

Nur im Spiel prüfbar:

- **Sprache im Gespräch.** Mit `pma-voice` läuft das Gespräch über `setCallChannel`, ohne über die Lautstärke des Partners in Mumble. Beides ist ungetestet: zu zweit anrufen, auseinander laufen, auflegen und prüfen, dass man sich danach nicht mehr hört.
- Ob die Töne im Spiel zu hören sind und die Lautstärke passt.
- Die Haltung mit dem Handy, und dass sie beim Schließen endet.
- Die Taste `F1` und ob sie mit einem anderen Script kollidiert.
- Solange das Handy offen ist, hat es den Mauszeiger. Laufen und Fahren geht in der Zeit nicht.
