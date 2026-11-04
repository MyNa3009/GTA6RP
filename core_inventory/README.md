# core_inventory 1.1.0

Inventar für die eigene Core: Plätze plus Gewicht, Kleidungsplätze, Waffe in der Hand, Rucksack mit eigenem Inhalt, Schnellzugriff, Ausweis und Lizenzen, Durchsuchen, Kofferraum, Lager-Schnittstelle, `/invsee`. Eigene Resource, damit man sie neu starten kann, ohne dass alle aus dem Spiel fliegen.

## Stand

| Etappe | Inhalt | Stand |
|---|---|---|
| 1 | Server-Logik: Plätze, Gewicht, Stapeln, Teilen, Tauschen, Kleidung an- und ausziehen, Rucksack, Speichern, `/giveitem`, `/removeitem`, Log | fertig |
| 2 | Inventar-Fenster (F2), Ziehen und Ablegen, Schnellzugriff 1 bis 5, geben, auf den Boden legen, Reiter "Inventar" in der Akte | fertig |
| 3 | Waffen mit Seriennummer und Munition, Bargeld als Item, Kleidung sichtbar am Charakter, Startoutfit | fertig |
| 4 | Legale und illegale Waffen mit Register, Ausweis und Lizenzen, Durchsuchen, Kofferraum, Lager-Schnittstelle, `/invsee`, Hände hoch | fertig |
| 5 | G-Interaktionsmenü (eigenes Script, nutzt die Exports unten) | später |

## Installation

1. Ordner `core_inventory` neben `core` in den resources-Ordner legen.
2. In der `server.cfg` direkt unter `ensure core` eine Zeile ergänzen: `ensure core_inventory`
3. Server neu starten. Die Tabellen `inventories`, `weapon_registry` und `licenses` legt die Resource selbst an (`database/inventory.sql` geht auch von Hand).

Die Core muss mindestens 1.6.0 sein. Ist sie älter, meldet sich das Inventar beim Start mit "Core ist zu alt" und macht nichts.

**Update von älteren Versionen:** Beide Ordner (`core` und `core_inventory`) ersetzen, Server neu starten. Die neuen Tabellen entstehen beim Start von selbst.

Ab 1.1.0: Neuer **Dienstausweis** (Reihe "Dokumente", siebter Platz). Alle Dokumente sehen aus wie echte Karten im Scheckkartenformat (fiktiver State of San Andreas), mit Foto, Siegel, Unterschrift und Stempel bei abgelaufen oder entzogen. Neue Item-Bilder für alle Dokumente. Die Spalte `licenses.details` legt das Inventar beim Start selbst an.

Ab 1.0.2: Haufen am Boden schicken nur noch Änderungen (neuer Haufen, Haufen weg) statt jedes Mal die ganze Liste. Items in einem Haufen umlegen schickt gar nichts mehr. Wer die Dimension wechselt, bekommt innerhalb von 2 Sekunden die Haufen der neuen Dimension.

Ab 1.0.1: `/invsee`, `/givelicense`, `/revokelicense` und `/licenses` stehen in der Befehlsliste des Admin-Menüs. Mit Core 1.7.0 verschwinden sie auch aus den Chat-Vorschlägen aller, die sie nicht benutzen dürfen.

Ab 1.0.0 beim ersten Einloggen jedes Charakters:
- Jeder bekommt seinen Personalausweis in die Reihe "Dokumente".
- Waffen, die schon im Inventar liegen, behalten ihre Seriennummer und gelten als legal. Ins Register kommen sie, sobald sie neu vergeben werden.

Ab 0.6.0 beim ersten Einloggen jedes Charakters:
- Bargeld zieht aus `characters.cash` als Item `cash` ins Inventar (Log `item.cash_migrated`). Die Bank bleibt in der Core.
- Jeder Charakter bekommt einmal das Startoutfit angezogen, sonst stünde er nach dem Update in Unterwäsche da (Log `item.start_outfit`).

Ab 0.5.0 gibt es nur noch 10 Taschenplätze. Beim ersten Einloggen räumt das Inventar selbst um: Items von den Plätzen 11 bis 30 rücken in freie Taschenplätze, dann in den Rucksack. Was nicht mehr passt, liegt als Beutel neben dem Spieler (Log `item.relocate_drop`). Der alte Rucksack wird automatisch zu `backpack_4`.

## Aufbau

- **Taschen:** 10 Plätze, 15 kg. Plätze 1 bis 5 sind der Schnellzugriff (linke Spalte), 6 bis 10 die eine Reihe Taschen.
- **Rucksack Level 1 bis 4:** Level 1 bis 3 geben je eine Reihe frei, Level 4 zwei Reihen auf einmal.

  | Level | Item | Plätze | Gewicht |
  |---|---|---|---|
  | 1 | `backpack_1` | 5 | 10 kg |
  | 2 | `backpack_2` | 10 | 15 kg |
  | 3 | `backpack_3` | 15 | 20 kg |
  | 4 | `backpack_4` | 25 | 30 kg |

  Gesperrte Reihen zeigt das Fenster mit Schloss. Einstellen in `Config.Inventory.Backpacks`. Der Inhalt gehört zum Rucksack. Legt man ihn ab oder gibt ihn weiter, reist der Inhalt mit und der Rucksack wiegt entsprechend.
- **Kleidung:** Maske, Kopfbedeckung, Brille, Ohrringe, Jacke, T-Shirt, Uhr, Handschuhe, Hose, Schuhe. Getragene Kleidung zählt nicht zum Gewicht.
- **Waffe in der Hand:** eigener Platz, zählt zum Gewicht.
- **Speichern:** Geänderte Inventare werden alle 5 Sekunden gespeichert, beim Ausloggen sofort, beim Stoppen der Resource auch.
- **Startitems:** Jeder neue Charakter bekommt sie einmal (`Config.Inventory.StartItems`).
- **Neustart:** Wird `core_inventory` neu gestartet, während gespielt wird, liest sie alle laufenden Charaktere neu ein.

## Waffen

- **Legal und illegal:** Es ist dasselbe Item. Eine legale Waffe hat eine **Seriennummer** (z. B. `SN-7KQ4-X2MD`) und steht im Waffenregister (Tabelle `weapon_registry`, mit dem ersten Besitzer). Eine illegale Waffe hat keine. Im Fenster steht beim Drüberfahren "Seriennummer …" oder "Keine Seriennummer".
- `/giveitem 17 weapon_pistol` gibt eine legale Waffe, `/giveitem 17 weapon_pistol illegal` eine illegale. Andere Scripts: `exports.core_inventory:AddItem(17, 'weapon_pistol', 1, { illegal = true })`.
- Register abfragen (für ein MDT): `exports.core_inventory:GetWeaponBySerial('SN-7KQ4-X2MD')` gibt Item, ersten Besitzer und Datum.
- Jede Waffe hat ihre **Munition**. Sie steht in der Akte und im Fenster.
- **In der Hand** ist nur, was im Waffenplatz liegt. Liegt eine Waffe im Schnellzugriff, zieht die Taste sie und steckt sie beim zweiten Drücken wieder an denselben Platz.
- **68 Waffen** aus GTA 5, alle mit Bild: 18 Nahkampfwaffen und Taser, 16 Pistolen und Revolver, 7 Maschinenpistolen, 10 Gewehre, 9 Schrotflinten, 5 Scharfschützengewehre, 3 Maschinengewehre. Namen wie in GTA, z. B. `weapon_carbinerifle`, `weapon_pistol_mk2`. Nicht dabei: Werfer, Minigun, Strahlenwaffen und Wurfwaffen.
- **Munition** gibt es pro Kaliber: `ammo_pistol`, `ammo_smg`, `ammo_rifle`, `ammo_shotgun`, `ammo_sniper`, `ammo_mg`. Benutzen lädt so viel, wie in die Waffe in der Hand passt (Pistolen, MPs und Gewehre bis 250, Schrot und Scharfschützen bis 100, MGs bis 500).
- Neue Waffe: in `data/items.lua` eintragen (mit Kaliber), in `data/weapons_gta5.lua` den GTA-Namen, Bild dazulegen.
- Der Server nimmt vom Spiel nur weniger Munition an, nie mehr. Mehr gibt es nur über Munitions-Items.
- Nahkampfwaffen und der Taser zählen keine Munition.
- `/gun` aus der Core bleibt eine reine Testwaffe ohne Item.

## Bargeld

- Item `cash`, wiegt nichts, ein Platz fasst beliebig viel. Es zeigt sich als Betrag ("1.240 $").
- Alles, was die Core mit Bargeld macht (`/givemoney cash`, `/geben`, `exports.core:AddMoney`), landet im Inventar. Geben, Ablegen und Aufheben im Inventar zieht die Geldanzeige sofort nach.
- Läuft `core_inventory` nicht, bucht die Core wieder in der alten Spalte. Ausschalten mit `Config.Money.CashInventory = nil` in der Core.

## Kleidung

- **Jedes Teil ist ein eigenes Item** mit eigenem Bild, zum Beispiel `jacket_bomber` (Bomberjacke) oder `pants_jeans` (Jeans). Was im Kleidungsplatz liegt, trägt der Charakter. Ein leerer Platz heißt "nichts an".
- **T-Shirt und Jacke:** Ohne Jacke ist das T-Shirt das Oberteil. Mit Jacke trägt man es darunter.
- **Neues Teil anlegen** (Nummern und Bilder kommen aus [FiveM-ClothingData](https://github.com/Colbss/FiveM-ClothingData), Game Build 3407):
  1. Im Ordner `images/mp_m_freemode_01/` (männlich) oder `images/mp_f_freemode_01/` (weiblich) der Sammlung das Teil suchen, zum Beispiel `mp_m_luxe_01/D_11_4_1.webp`. Aufbau: `D` = Kleidung, `P` = Zubehör, dann Platz-Nummer, Teil, Farbe.
  2. In `tools/kleidung_auswahl.json` einen Eintrag ergänzen: Item-Name, Platz, Anzeigename, Gewicht und für `male` und/oder `female` die Bild-Angabe ohne `.webp`, bei Oberteilen dazu `arms`.
  3. `python tools/kleidung.py <Pfad zu FiveM-ClothingData-master>` ausführen (braucht Python und `pip install pillow`). Das schreibt `data/clothing_catalog_gta5.lua` und `images/<item>.png`.
  4. Resource neu starten.
- Die Bilder der Sammlung (200 MB) gehören nicht in die Resource, nur die erzeugten PNGs.
- **Platz-Nummern in den Bildnamen:** Maske `D_1`, Oberteil und T-Shirt `D_11`, Unterhemd `D_8`, Handschuhe `D_3`, Hose `D_4`, Schuhe `D_6`, Kopfbedeckung `P_0`, Brille `P_1`, Ohrringe `P_2`, Uhr `P_6`.
- **Plätze:** `mask`, `hat`, `glasses`, `ears`, `jacket`, `shirt`, `watch`, `gloves`, `pants`, `shoes`.
- **Startoutfit** pro Geschlecht in `Config.Inventory.StartOutfit` (Item-Namen).
- **Bitte im Spiel prüfen:** Die Arme zu Oberteilen (`arms`) und die "nichts an"-Werte in `ClothingNaked` (`data/clothing_gta5.lua`) habe ich nicht im Spiel gesehen. Passen Arme nicht zum Oberteil, in der Auswahl `arms` ändern und neu erzeugen.
- Alte allgemeine Kleidung (`clothing_jacket` und so weiter) wird beim Laden automatisch zum passenden neuen Teil.

## Ausweis und Lizenzen

- Dokumente liegen in einer eigenen Reihe **"Dokumente"** im Fenster. Man kann sie nicht verschieben, ablegen, geben oder stehlen. Weg sind sie nur, wenn eine Behörde sie entzieht.
- **Personalausweis:** bekommt jeder Charakter beim Start. Er zeigt Foto, Name, Geburtsdatum, Geschlecht und die Ausweisnummer (= permanente ID). Er läuft nie ab.
- **Lizenzen:** Führerschein (Klasse B für PKW, Klasse C für LKW und Transporter, C braucht B), Waffenschein, Flugschein, Bootsschein, Angelschein. Gültig 30 Tage (`Config.Inventory.Documents.LicenseDays`). Abgelaufene bleiben im Inventar mit "Abgelaufen".
- **Dienstausweis:** kommt vom Orga-Script beim Beitritt (`IssueServiceCard`, unten). Er zeigt Orga, Dienstgrad, Dienstnummer, Foto und Name und läuft nicht ab. Nochmal ausstellen ändert Dienstgrad oder Orga. Beim Austritt entzieht ihn das Orga-Script: Item weg, im Register "entzogen" mit Grund. Volle Orga-Namen stehen in `Config.Inventory.Documents.ServiceOrgs`.
- **Aussehen:** Jedes Dokument ist eine Karte im Scheckkartenformat mit Aussteller (`Config.Inventory.Documents.Issuer`, Standard "State of San Andreas"), Foto, kleinem Zweitfoto, Siegel als Wasserzeichen und Unterschrift. Abgelaufene und entzogene Dokumente tragen einen roten Stempel. Der Dienstausweis hat oben ein dunkles Band mit der Orga.
- **Register:** Tabelle `licenses` ist die Wahrheit. Das Item wird beim Einloggen danach abgeglichen. Entzogen heißt: Item weg, im Register steht "entzogen" mit Grund und wer es war.
- **Zeigen:** Rechtsklick auf das Dokument, "Zeigen", dann die Person. Nur diese Person sieht die Karte, 10 Sekunden lang rechts am Rand. Vorläufig auch `/zeigen ausweis` (oder `fuehrerschein`, `waffenschein`, `flugschein`, `bootsschein`, `angelschein`, `dienstausweis`) an die nächste Person. Später übernimmt das G-Menü.

| Befehl | Wer | Was |
|---|---|---|
| `/givelicense 17 fuehrerschein B` | Admin im Dienst | Lizenz ausstellen oder verlängern. Klasse nur beim Führerschein. |
| `/givelicense 17 dienstausweis LSPD Officer II` | Admin im Dienst | Dienstausweis zum Testen ausstellen. Orga-Kürzel, dann Dienstgrad. |
| `/revokelicense 17 fuehrerschein C Grund` | Admin im Dienst | Entziehen. Klasse optional: nur C, oder B (nimmt C mit). Auch `dienstausweis`. |
| `/licenses 17` | Admin im Dienst | Alle Lizenzen mit Stand |

Fahrschule, Amt oder Waffenladen stellen über die Exports aus (unten).

## Durchsuchen, Kofferraum, Lager, /invsee

Alles öffnet das Inventar mit einem **zweiten Fenster** rechts. Ziehen, Doppelklick oder Rechtsklick "Nehmen" holt Items in die eigenen Taschen.

- **Hände hoch:** Taste X (im Spiel änderbar). Mit Händen oben kann man nicht schießen. Bei Tod oder Einsteigen gehen sie von selbst runter.
- **Durchsuchen:** nur wenn die Person die Hände oben hat oder gefesselt ist, bis 2 m. Man sieht Taschen, Rucksack und die Waffe in der Hand. Nur nehmen, nichts hineinlegen. Kleidung und Dokumente bleiben. Die Person bekommt eine Meldung. Nimmt sie die Hände runter oder geht man weg, ist die Durchsuchung vorbei. Vorläufig `/durchsuchen` (nächste Person).
- **Kofferraum:** am Kofferraum stehen (meist hinten, bei manchen Sportwagen vorne), Fahrzeug offen. Immer nur eine Person. Die Größe hängt an der Fahrzeugklasse (`data/trunks_gta5.lua`, z. B. Limousine 20 Plätze und 100 kg), Motorräder und Fahrräder haben keinen. Der Inhalt gehört zum Kennzeichen. Wird abgeschlossen oder man geht weg, geht er zu. Vorläufig `/kofferraum`.
- **Lager:** kommt aus dem Lager-Script (Fraktion, Wohnung, Spind). Das Script prüft, wer darf, und gibt Name, Größe und Position vor. Mehrere Personen gleichzeitig gehen. Siehe Exports.
- **Shops:** haben ihre eigene Oberfläche. Sie geben Items über `AddItem` (alles oder nichts, also erst geben, dann Geld abbuchen) und nehmen Geld über die Core.
- **`/invsee 17`:** Admin im Dienst (Recht `items.manage`). Zeigt alles, auch Kleidung und Dokumente, auch wenn die Person offline ist. Man kann nehmen und hineinlegen, jede Änderung steht im Log.

Im Log (Kategorie `item`): `search_open`, `search_take`, `trunk_open`, `trunk_take`, `trunk_put`, `stash_open`, `stash_take`, `stash_put`, `admin_move`, dazu `admin.invsee`.

## Bedienen

| Was | Wie |
|---|---|
| Öffnen und schließen | F2, schließen auch mit Esc. Die Taste kann jeder Spieler unter Einstellungen, Tastenbelegung, FiveM ändern. |
| Aufbau | Links der Schnellzugriff (Plätze 1 bis 5), daneben Taschen und Rucksack, rechts "Dich anziehen" und "Boden". Ohne Rucksack sind dessen Plätze gesperrt. |
| Verschieben | Item mit der Maus auf einen anderen Platz ziehen. Gleiche Items stapeln sich, sonst tauschen sie. |
| Aktionen | Rechtsklick auf ein Item: Anzahl, Benutzen oder Anziehen, Geben, Ablegen, Hälfte abteilen |
| Infos | Maus kurz auf einem Item lassen: Name, Anzahl, Gewicht, Beschreibung |
| Hälfte nehmen | Beim Ziehen Shift halten |
| Anzahl wählen | Rechtsklick, oben im Menü die Anzahl eintragen, dann Ablegen oder Geben |
| Benutzen | Doppelklick, Enter oder Rechtsklick und "Benutzen". Bei Kleidung steht dort "Anziehen", im Kleidungsplatz "Ausziehen". Aus dem Beutel am Boden heißt es "Aufheben". |
| Anziehen | Kleidung in ihren Platz links ziehen. Ein Rucksack in den Rucksack-Platz schaltet die rechte Spalte frei. |
| Schnellzugriff | Tasten 1 bis 5 benutzen die Items aus der linken Spalte, ohne das Fenster. Unten blendet kurz die Leiste ein. |
| Waffenrad | Ist gesperrt (Tab, Mausrad, Zifferntasten), damit 1 bis 5 nur den Schnellzugriff steuern. Abschalten mit `BlockWeaponWheel = false` in der Config. |
| Geben | Rechtsklick, "Geben", dann die Person aus der Liste. Nur bis 3 m und in der gleichen Dimension. An eigene Charaktere geht nichts, das wird gemeldet. |
| Dokument zeigen | Rechtsklick auf das Dokument, "Zeigen", Person wählen |
| Hände hoch | X |
| Auf den Boden | Item in "Boden" ziehen oder Rechtsklick und "Ablegen". Es entsteht ein Beutel, den alle sehen. In der Nähe steht "F2 Aufheben". Nach 30 Minuten verschwindet er (steht im Log). |

Haufen am Boden liegen nur im Speicher. Nach einem Neustart sind sie weg, darum nach 30 Minuten löschen statt dauerhaft halten.

## Testen

| Was | Erwartet |
|---|---|
| Neuer Charakter | 2 Wasser, 2 Brot, steht im Log (Kategorie `item`) |
| `/giveitem 17 water 12` (im Dienst, ab Senior Administrator) | Wasser wird auf Stapel zu je 10 verteilt, Spieler bekommt eine Meldung |
| `/giveitem 17 water 100` | "zu schwer", nichts wird gegeben (alles oder nichts) |
| `/giveitem 17 sandwich 3` bei Offline-Charakter | Geht, steht direkt in der Datenbank |
| `/removeitem 17 water 5` | Nimmt aus Taschen, dann Rucksack, dann Ausrüstung |
| Admin-Menü, "Befehle" | Gruppe "Inventar" mit beiden Befehlen |
| F2, Wasser auf Platz 7 ziehen | Wasser liegt auf 7, Gewicht oben bleibt gleich |
| Taste 1 mit Wasser auf Platz 1 | Leiste unten, ein Wasser weniger, Meldung |
| `/giveitem 17 backpack_2`, dann in den Rucksack-Platz ziehen | Zwei Reihen frei, zwei mit Schloss, oben "Level 2" und 15 kg |
| Item in "Boden" ziehen, weggehen, zurückkommen | Beutel liegt da, "F2 Aufheben", im Fenster unter "Boden" |
| Geben an zweiten Spieler | Beide bekommen eine Meldung, Log `item.give` |
| Admin-Menü, Akte, Reiter "Inventar" | Gleicher Inhalt wie im Fenster, Log `admin.view_inventory` |
| Neuer Charakter, F2 | Personalausweis in "Dokumente", lässt sich nicht ziehen |
| `/zeigen ausweis` neben zweitem Spieler | Nur der zweite Spieler sieht die Karte mit Foto, 10 Sekunden |
| `/givelicense 17 fuehrerschein C` ohne B | Abgelehnt: C braucht B |
| `/giveitem 17 weapon_pistol illegal`, Maus auf die Waffe | "Keine Seriennummer" |
| Spieler 2 drückt X, Spieler 1 `/durchsuchen` | Fenster rechts mit Taschen und Waffe, Spieler 2 bekommt eine Meldung. Hineinziehen geht nicht. |
| Spieler 2 nimmt die Hände runter, Spieler 1 nimmt etwas | "Die Durchsuchung ist vorbei", Fenster rechts weg |
| Am Heck eines offenen Autos `/kofferraum` | Klappe geht auf, Fenster "Kofferraum KENNZEICHEN", beim Schließen geht sie zu |
| Zweiter Spieler gleichzeitig `/kofferraum` | "Jemand anderes schaut gerade in den Kofferraum." |
| Auto abschließen, wieder öffnen | Inhalt ist noch da (am Kennzeichen) |
| `/invsee 17` (Spieler offline) | Alles sichtbar, auch Kleidung und Dokumente, Änderungen im Log |

## Items und Bilder

Alle Items stehen in `data/items.lua`. Neues Item = neuer Eintrag, kein Code nötig. Gewicht in Gramm.

Essen und Trinken: `use = { remove = 1, hunger = 25 }` oder `thirst = 40` füllt Hunger und Durst der Core auf. Jetzt: Wasser 40 Durst, Brot 25 Hunger, Sandwich 40 Hunger.

Bilder kommen nach `images/`:
- PNG, 128 × 128 Pixel, durchsichtiger Hintergrund
- Dateiname = Item-Name, z. B. `water.png`, `jacket_bomber.png`
- Fehlt ein Bild, zeigt der Platz den Anfangsbuchstaben. Neue Bilder brauchen nur einen Neustart der Resource.
- Nur Bilder für Items aus `data/items.lua` hineinlegen, nicht die ganze Sammlung. Alles in `images/` lädt jeder Spieler beim Verbinden herunter.

Die jetzigen Bilder stammen aus der Community-Sammlung MK-Items von TinySprite-Scripts. Für Kopfbedeckung, Brille, Ohrringe, Jacke, T-Shirt, Handschuhe und Hose gab es dort nichts Passendes, die zeigen noch den Buchstaben. Die Rucksäcke sind vorerst Sporttaschen, echte Rucksäcke gab es in der Sammlung nicht.

Jetzige Item-Namen: `id_card`, `license_driver`, `license_weapon`, `license_pilot`, `license_boat`, `license_fishing`, `cash`, `water`, `bread`, `sandwich`, `bandage`, `lockpick`, `phone`, `backpack_1` bis `backpack_4`, `mask_balaclava`, `hat_beanie`, `glasses_sun`, `ears_studs`, `jacket_bomber`, `shirt_white`, `watch_gold`, `gloves_leather`, `pants_jeans`, `pants_cargo`, `shoes_sneaker`, alle Waffen (`weapon_*`, siehe `data/items.lua`) und `ammo_pistol`, `ammo_smg`, `ammo_rifle`, `ammo_shotgun`, `ammo_sniper`, `ammo_mg`.

## Für andere Scripts

```lua
exports.core_inventory:AddItem(characterId, 'water', 2)        -- true oder false, 'too_heavy' | 'no_space' | 'unknown_item'
exports.core_inventory:RemoveItem(characterId, 'water', 1)     -- true oder false, 'not_enough'
exports.core_inventory:GetItemCount(characterId, 'water')      -- Zahl
exports.core_inventory:GetInventory(characterId)               -- { items, bag, weight, maxWeight, ... }
```
Alles geht mit der permanenten ID und auch, wenn der Charakter offline ist. Wer Items vergibt, loggt selbst über `exports.core:Log`.

```lua
-- Lizenzen (Fahrschule, Amt, Waffenladen)
exports.core_inventory:IssueLicense(characterId, 'driver', 'B', actorAccountId)          -- true oder false, fehler
exports.core_inventory:RevokeLicense(characterId, 'driver', nil, 'Grund', actorAccountId)
exports.core_inventory:HasLicense(characterId, 'driver', 'C')                             -- true, wenn gültig
exports.core_inventory:GetLicenses(characterId)                                           -- Liste mit Stand
exports.core_inventory:GetWeaponBySerial('SN-7KQ4-X2MD')                                  -- Register

-- Dienstausweis (Orga-Script): beim Beitritt und bei Befoerderung, beim Austritt entziehen
exports.core_inventory:IssueServiceCard(characterId, {
    org = 'LSPD',                            -- Kuerzel, Pflicht
    label = 'Los Santos Police Department',  -- optional, sonst aus Config ServiceOrgs
    rank = 'Officer II',                     -- Pflicht
    number = 'LSPD-482',                     -- optional, sonst die permanente ID
}, actorAccountId)                                                                        -- true oder false, fehler
exports.core_inventory:RevokeServiceCard(characterId, 'Aus dem LSPD ausgetreten', actorAccountId)
exports.core_inventory:HasLicense(characterId, 'service')                                 -- true, solange gültig

-- Lager (Server). Das Script prüft vorher, wer darf.
exports.core_inventory:OpenStash(source, 'lspd_waffen', {
    label = 'Waffenkammer LSPD', slots = 50, maxWeight = 200000,       -- Gewicht in Gramm, bis 100 Plätze
    position = { x = 452.1, y = -980.2, z = 30.7 }, distance = 3.0,    -- optional: weggehen schließt
    canPut = true,                                                     -- false: nur nehmen
})

-- Für das G-Menü (Server)
exports.core_inventory:OpenSearch(source, zielServerId)               -- true oder false, fehler
exports.core_inventory:OpenTrunk(source, netId, fahrzeugklasse)
exports.core_inventory:ShowDocument(source, 'id', zielServerId)
exports.core_inventory:SetCuffed(source, true)                        -- vom Fessel-Script
exports.core_inventory:IsCuffed(source), exports.core_inventory:IsHandsUp(source)

-- Für das G-Menü (Client)
exports.core_inventory:SearchPlayer(serverId)
exports.core_inventory:OpenNearestTrunk()
exports.core_inventory:ShowDocument('driver', serverId)
exports.core_inventory:IsHandsUp()
```

Fehler beim Öffnen: `not_searchable`, `too_far`, `target_offline`, `vehicle_locked`, `trunk_busy`, `no_trunk`, `no_vehicle`, `invalid_stash`, `no_character`.

## Regeln

Wie in der Core: Diese Resource hat keine eigene Bridge. Sie lädt `@core/bridge/...` und `@core/shared/config.lua`, damit es nur eine Stelle mit FiveM-Natives und eine Config für Farben und Tastatur gibt. Von der Core nutzt sie nur die Exports und die Ereignisse `core:characterLoaded` und `core:characterUnloaded`.
