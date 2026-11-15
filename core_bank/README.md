# core_bank 1.0.3

Bank für die eigene Core. Jeder Charakter hat ein Girokonto mit Kontonummer. In der Filiale zahlt man ein und aus, überweist, liest den Kontoauszug und begleicht Schulden. An jedem Bankautomaten der Spielwelt gibt es schnelles Bargeld mit Grenzen. Schulden sind Strafen, Rechnungen und Gebühren mit Frist: Danach kommt eine Mahngebühr dazu, und die Bank zieht vom Konto ein. Alle Daten gibt es als Export, damit später das Handy dasselbe zeigen kann.

Das Geld selbst liegt weiter in der Core (Bankkonto am Charakter). `core_bank` bucht nur über deren Exports und führt Kontonummer, Kontoauszug und Schulden.

## Update von 1.0.2

1. Erst Core 1.18.1, dann den Ordner `core_bank` ersetzen und neu starten. Keine Migration.
2. **Fehler behoben:** Wer eine Forderung bezahlen, Geld auszahlen oder überweisen wollte und zu wenig auf dem Konto hatte, bekam "Fehler auf dem Server". Jetzt steht dort "Auf dem Konto ist nicht genug Geld". Genauso beim Einzahlen mit zu wenig Bargeld.
3. Grund: Über Exports kommt im Spiel oft nur der erste Rückgabewert an, der Fehlercode der Core fehlte. `core_bank` prüft das jetzt selbst nach.

## Update von 1.0.1

1. Erst Core 1.17.1, dann den Ordner `core_bank` ersetzen und neu starten. Keine Migration.
2. **Fehler behoben:** Die Bewegung am Bankautomaten lief nach dem Schließen weiter. Jetzt endet sie beim Schließen, beim Bewusstlos-Werden und beim Neustart der Resource.

## Update von 1.0.0

1. Erst Core 1.17.0, dann den Ordner `core_bank` ersetzen und neu starten. Keine Migration.
2. **Bank im Admin-Menü:** Die Akte im Admin-Menü der Core hat den Reiter "Bank" mit Konto, Schulden und Kontoauszug. Von dort öffnet ein Knopf die Ansicht von `/konto`.
3. Die Einträge der Bank im Log tragen jetzt den Login der Person. Dadurch stehen sie in ihrer Akte. Einträge von vor dem Update tauchen dort nicht auf.

## Installation

1. Braucht Core 1.16.0 und `core_lib`. Mit `core_factions` gehen Rechnungen in die Kasse der Organisation, ohne läuft alles andere trotzdem.
2. Ordner `core_bank` nach `resources/[core]/` kopieren. Die Tabellen legt das Script beim Start selbst an, das SQL steht zusätzlich in `database/bank.sql`.
3. In der `server.cfg` nach `core_lib` und `core_factions`: `ensure core_bank`
4. Server neu starten. Jeder Charakter bekommt beim nächsten Einloggen seine Kontonummer.

## Für Spieler

### Filiale

An jedem Schalter (Blip "Bank" auf der Karte) mit `E`. Die Orte stehen in `data/banks_gta5.lua`.

| Bereich | Was geht |
|---|---|
| Übersicht | Kontostand, Bargeld ein- und auszahlen ohne Grenze, letzte Buchungen, Hinweis auf offene Forderungen |
| Überweisen | Kontonummer, Betrag, Verwendungszweck. Erst wird der Empfänger geprüft und mit Namen gezeigt, dann überwiesen. Geht auch, wenn der Empfänger offline ist. Die letzten Empfänger stehen daneben |
| Kontoauszug | Jede Buchung mit Datum, Gegenkonto, Betrag und Kontostand. Filter für Eingänge und Ausgänge |
| Schulden | Offene und erledigte Forderungen mit Gläubiger, Frist und Mahngebühr. Bezahlen vom Konto, auch in Teilen |

Die Kontonummer hat 8 Ziffern und steht links im Fenster. Man gibt sie im RP selbst weiter.

### Bankautomat

Jeder Automat der Spielwelt funktioniert mit `E`, auch in MLOs (Modelle in `data/atms_gta5.lua`).

- Auszahlen bis 5.000 $ auf einmal und 20.000 $ in 24 Stunden.
- Einzahlen bis 10.000 $ auf einmal.
- Beträge über die Schnellwahl, das Ziffernfeld oder direkt auf der Tastatur. `Enter` bestätigt, Pfeil links und rechts wechselt zwischen Auszahlen und Einzahlen.
- Überweisen, Kontoauszug und Schulden gibt es nur in der Filiale. Der Automat zeigt aber, ob Forderungen offen sind.

### Schulden

- Jede Forderung hat eine Frist, ohne Angabe 72 Stunden. Beim Ausstellen und beim Einloggen kommt eine Meldung.
- Bezahlt wird in der Filiale vom Konto. Das Geld geht an den Gläubiger: in die Kasse der Organisation oder an den Staat.
- Nach der Frist kommt einmal die Mahngebühr dazu (10 % vom offenen Rest). Ab dann zieht die Bank vom Konto ein, soweit Geld da ist. 500 $ bleiben dabei immer auf dem Konto. Der Rest bleibt offen, bis wieder Geld da ist.
- Der Einzug läuft alle 10 Minuten und beim Einloggen, auch für Charaktere, die offline sind.

### Rechnung oder Strafe ausstellen

Mitglieder einer Organisation aus `Debts.Issuers` stellen im Dienst über das G-Menü eine Forderung aus: Person anschauen, Organisation, Forderung ausstellen. Eingerichtet ist der Rettungsdienst mit Rechnungen bis 25.000 $ ab Rang 3. Bei einer Rechnung muss die Person zustimmen, bei einer Strafe (`consent = false`) nicht. Das Recht steht im Organisationsmenü unter Anpassung in der Gruppe "Bank", jede Forderung im Protokoll unter Kasse.

## Für Admins

| Befehl | Recht | Was passiert |
|---|---|---|
| `/konto 17` | `player.view` | Konto, Kontoauszug und Schulden von ID 17 ansehen, auch offline. Geld bewegt man hier nicht, dafür gibt es `/givemoney` und `/removemoney` |
| `/schuld 17 500 Rotlicht überfahren` | `money.manage`, im Admin-Dienst | Strafe des Staats eintragen |

Dieselben Daten stehen im Admin-Menü in der Akte der Person unter dem Reiter "Bank". Der Knopf "In der Bank öffnen" führt von dort in die Ansicht von `/konto`.

In der Ansicht von `/konto` können Admins mit `money.manage` im Admin-Dienst Forderungen eintragen und mit Grund erlassen. Schon Bezahltes bleibt beim Gläubiger. Jeder Blick in ein Konto und jede Änderung steht im Log (Kategorie `bank`).

## Einstellen

Alles steht in `config.lua` unter `Config.Bank`:

- `Name`: Name der Bank in beiden UIs.
- `Colors`: nur Farben, die von `Config.UI.Colors` der Core abweichen sollen.
- `BranchDistance`, `TransferMax`, `PurposeMaxLength`, `PageSize`.
- `Atm`: Abstand, `WithdrawMax`, `DailyWithdraw` (0 = ohne Grenze), `Deposit`, `DepositMax`, `QuickAmounts`.
- `Debts`: `DueHours`, `LateFeePercent` (0 = keine Mahngebühr), `AutoCollect`, `CollectKeep`, `SweepMinutes`, Bezeichnungen der Arten.
- `Debts.Issuers`: welche Organisation ausstellen darf, mit Art, Recht, Mindestrang, Höchstbetrag und Zustimmung. Für das LSPD die auskommentierte Zeile einschalten.
- `Admin`: Befehl und Rechte.

## Für andere Scripts

Alle Exports laufen auf dem Server und nehmen die permanente ID. Sie funktionieren auch, wenn der Charakter offline ist. Ob ein Spieler etwas darf, prüft das aufrufende Script selbst.

| Export | Gibt zurück |
|---|---|
| `GetAccount(characterId)` | `{ characterId, name, number, balance }` oder nil |
| `GetOverview(characterId, anzahl)` | Konto, dazu `recent` (letzte Buchungen) und `debts = { count, total, overdue }`. Das ist die Startseite fürs Handy |
| `GetTransactions(characterId, { page, filter })` | `{ entries, page, more }`, `filter` ist `all`, `in` oder `out` |
| `GetRecipients(characterId)` | `{ { name, number } }`, die letzten Empfänger |
| `LookupAccount(kontonummer)` | `{ characterId, name, number }` oder nil |
| `Transfer(vonCharacterId, kontonummer, betrag, zweck, { channel })` | `{ balance, to = { name, number } }`, sonst nil und ein Fehlercode. `channel` ist `phone`, `bank`, `atm` oder `system` |
| `AddDebt(characterId, { amount, title, kind, creditor, dueHours, issuedBy, issuedById })` | Nummer der Forderung, sonst nil und ein Fehlercode. `kind`: `fine`, `invoice`, `fee`, `other`. `creditor`: `state` oder eine Organisation |
| `GetDebts(characterId, { status, page })` | `{ debts, page, more }`, `status` ist `open` oder `closed` |
| `GetDebt(nummer)`, `GetDebtSummary(characterId)` | eine Forderung bzw. `{ count, total, overdue }` |
| `PayDebt(characterId, nummer, betrag, { channel })` | `{ debt, balance, paid }`, ohne Betrag der ganze Rest. Sonst nil und ein Fehlercode |
| `CancelDebt(nummer, { by, reason })` | die erlassene Forderung, sonst nil und ein Fehlercode |

Beispiel für eine Strafe aus einem LSPD-Script:

```lua
local id, err = exports.core_bank:AddDebt(characterId, {
    amount = 600, title = 'Rotlicht überfahren', kind = 'fine',
    creditor = 'lspd', issuedById = officerCharacterId, issuedBy = 'Lena Hoffmann',
})
```

Ereignisse auf dem Server:

- `core_bank:booked (characterId, buchung)` nach jeder Buchung im Kontoauszug.
- `core_bank:debtChanged (characterId, forderung, was)` mit `added`, `partial`, `paid`, `overdue` oder `cancelled`.
- `core_bank:changed (characterId, was)` mit `account` oder `debts`. Dasselbe geht als Push an den Client, damit offene UIs neu laden.

Buchungen anderer Scripts über die Core (Gehalt, Bonus, Kauf, `/givemoney`) erscheinen von selbst im Kontoauszug, mit dem Grund der Buchung als Text.

Fehlercodes: `no_session`, `too_far`, `is_dead`, `not_here`, `busy`, `invalid_amount`, `invalid_input`, `invalid_number`, `unknown_account`, `same_account`, `not_enough_money`, `not_enough_cash`, `no_space`, `over_limit`, `daily_limit`, `twink_blocked`, `not_found`, `debt_closed`, `no_permission`, `not_on_duty`, `target_offline`, `consent_declined`, `consent_timeout`.

## Aufbau

- `server/accounts.lua`: Kontonummer, Kontoauszug, Ein- und Auszahlen, Überweisen.
- `server/debts.lua`: Schulden, Mahngebühr, Einzug.
- `server/sessions.lua`: Anfragen aus den UIs. Der Server prüft bei jeder Anfrage, ob die Person noch am Schalter oder Automaten steht.
- `server/admin.lua`: Admin-Ansicht und `/schuld`.
- `html/bank.html` und `html/atm.html`: die beiden UIs, `html/index.html` ist die Shell.
- `data/banks_gta5.lua`, `data/atms_gta5.lua`: Filialen und Automaten-Modelle. Beim Umzug auf GTA 6 werden nur diese beiden Dateien ersetzt.

Bankautomaten sind Objekte der Spielwelt, ihre Position kennt nur der Client. Der Server prüft darum, dass die Person an der gemeldeten Stelle steht. Mehr als Kontostand, Ein- und Auszahlen des eigenen Geldes gibt es dort nicht.

## Test

`python3 tests/test_bank.py` prüft die Serverlogik gegen MariaDB. Die UIs laufen im Browser mit Testdaten: `html/bank.html` (auch `?admin`, `?admin&manage`, `?leer`) und `html/atm.html`.

Nur im Spiel prüfbar:

- Ob die Schalter in `data/banks_gta5.lua` genau am Tresen liegen.
- Ob jeder Automat erkannt wird und der Abstand von 1,6 m passt.
- Die Bewegung am Automaten und der Blip auf der Karte.
