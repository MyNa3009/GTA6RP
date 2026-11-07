# core_lib 1.0.0

Bibliothek für alle Scripts des Servers, ähnlich wie ox_lib, aber im Design des Servers und mit mehr Minigames. Dazu das **G-Menü**: ein Interaktionsmenü, über das später fast alles läuft, immer in Kategorien geteilt (`Person`, `Fahrzeug`, `Organisation > Leader > Entlassen`).

Alles, was die Core schon kann, bleibt in der Core und wird nicht doppelt gebaut: Callbacks (`Network.Call`), Tasten (`Platform.RegisterKeyCommand`), Meldungen (`core:notify`), Logging (`exports.core:Log`).

## Installation

1. Ordner `core_lib` neben `core` und `core_inventory` legen.
2. In der `server.cfg` unter `ensure core_inventory` ergänzen: `ensure core_lib`
3. Server neu starten.

Braucht Core 1.8.0. Ist die Core älter, meldet sich die `core_lib` mit "Core ist zu alt" und macht nichts. Ohne `core_inventory` läuft alles, nur die Einträge Ausweis zeigen, Durchsuchen, Geld geben und Kofferraum fehlen im G-Menü.

## Was drin ist

| Bereich | Funktionen | Bei ox_lib |
|---|---|---|
| G-Menü | `lib.addInteraction`, `lib.removeInteraction`, `lib.setInteractionCategory`, `lib.openInteractionMenu` | Radialmenü |
| Kontextmenüs | `lib.registerContext`, `lib.showContext`, `lib.hideContext`, `lib.getOpenContextMenu` | gleich |
| Fortschritt | `lib.progressBar`, `lib.progressCircle`, `lib.cancelProgress`, `lib.progressActive` | gleich |
| Minigames | `lib.skillCheck`, `lib.lockpick`, `lib.hack`, `lib.wires`, `lib.cancelMinigame`, auf dem Server `lib.minigame` | nur Skillcheck |
| Dialoge | `lib.inputDialog`, `lib.alertDialog`, `lib.closeDialog` | gleich |
| Hinweis | `lib.showTextUI`, `lib.hideTextUI`, `lib.isTextUIOpen` | gleich |
| Zonen | `lib.points.new`, `lib.zones.sphere`, `lib.zones.box`, `lib.zones.poly` | gleich |
| Cache | `lib.cache`, `lib.onCache` | gleich |
| Meldungen | `lib.notify` (geht an die Benachrichtigungen der Core) | gleich |

## Einbinden in ein eigenes Script

Im fxmanifest nach der Bridge der Core:

```lua
dependencies { 'core', 'core_lib' }

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    '@core_lib/init.lua',
    '@core_lib/modules/zones.lua',   -- nur wenn du Zonen brauchst
    '@core_lib/modules/cache.lua',   -- nur wenn du den Cache brauchst
    'client/main.lua',
}

server_scripts {
    '@core/bridge/platform/fivem_server.lua',
    '@core/bridge/network/fivem_server.lua',
    '@core_lib/init.lua',
    'server/main.lua',
}
```

Danach gibt es die Tabelle `lib`. Alles mit Ergebnis (`lib.progressBar`, `lib.skillCheck`, `lib.inputDialog` ...) wartet, bis das Ergebnis da ist. Darum nur in einem Thread aufrufen: in einem Befehl, einem Ereignis, einer Menü-Aktion oder in `Platform.Async`.

## G-Menü

**Bedienung:** Taste `G` (im Spiel änderbar unter Einstellungen > Tastenbelegung > FiveM > "Interaktionsmenü öffnen") oder `/interaktion`. Links erscheint das Menü:

- Oben die Kategorien als Reiter, mit Pfeil links und rechts oder per Klick wechseln.
- Zahlen `1` bis `9` führen die Zeile sofort aus, Pfeil hoch und runter wählt, `Enter` führt aus.
- Unterkategorien öffnen sich mit `Enter` oder Pfeil rechts, zurück geht es mit `Esc`, `Backspace` oder Pfeil links.
- `/` springt in die Suche. Sie durchsucht die ganze Kategorie mit allen Unterkategorien und zeigt den Pfad dazu.
- `G` oder `Esc` auf der obersten Ebene schließt.
- Oben steht die nächste Person ("Nächste Person: ID 17 · 1,2 m"). Stehen mehrere Personen in der Nähe, fragt das Menü bei Aktionen mit einer Person "Wen meinst du?".

Angezeigt wird nur, was gerade passt. Ohne Fahrzeug gibt es keinen Reiter Fahrzeug, ohne Person in der Nähe keine Einträge, die eine Person brauchen. Ist nichts zu tun, kommt die Meldung "Hier gibt es gerade nichts zu tun."

**Eingebaut:**

| Kategorie | Einträge |
|---|---|
| Person | Ausweis zeigen (Personalausweis, Führerschein, Waffenschein, Dienstausweis, Flugschein, Bootsschein, Angelschein), Durchsuchen, Geld geben |
| Fahrzeug, am Steuer | Motor (an oder aus), Licht, Türen (einzeln und "Alle schließen", nur Türen, die es gibt), Fenster, Sitz wechseln |
| Fahrzeug, als Mitfahrer | eigenes Fenster, Sitz wechseln |
| Fahrzeug, zu Fuß daneben | Kofferraum öffnen |

Sitz wechseln geht bis 5 km/h (`Config.Lib.Interact.SeatChangeMaxKmh`). Abschließen gehört später zum Schlüssel-Script.

### Eigene Einträge

```lua
-- Beispiel: Organisations-Script (Client)
lib.setInteractionCategory('Organisation/Leader', { icon = 'crown', order = 10 })

lib.addInteraction({
    id = 'org_fire',
    path = 'Organisation/Leader',          -- Reiter "Organisation", Unterkategorie "Leader"
    label = 'Entlassen',
    description = 'Entlässt die Person aus deiner Organisation.',
    icon = 'user-minus',
    target = 'player',                     -- nur mit Person in der Nähe
    canShow = function(ctx) return MyOrg ~= nil and MyOrg.isLeader end,
    onSelect = function(ctx)
        local answer = lib.alertDialog({
            header = ('ID %d entlassen?'):format(ctx.player.characterId),
            content = 'Rang, Dienstausweis und Zugriff auf Fahrzeuge der Organisation gehen verloren.',
            confirmLabel = 'Entlassen',
            danger = true,
        })
        if answer == 'confirm' then
            Network.Call('org_fire', { target = ctx.player.serverId })   -- der Server prüft Rang und Distanz selbst
        end
    end,
})
```

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `id` | ja | eindeutig, bis 64 Zeichen. Gleiche ID nochmal = Eintrag ersetzen (nur aus derselben Resource) |
| `path` | ja | `'Organisation/Leader'` oder `{ 'Organisation', 'Leader' }`. Erster Teil = Reiter, bis 4 Ebenen |
| `label` | ja | Text der Zeile, bis 48 Zeichen |
| `onSelect` oder `event` | ja | Funktion `function(ctx)` oder Name eines lokalen Ereignisses, das `ctx` bekommt |
| `description` | | zweite Zeile, gedämpft |
| `icon` | | Name aus der Icon-Liste unten |
| `order` | | Reihenfolge, kleiner = weiter oben (Standard 100) |
| `target` | | `'player'`: nur mit Person in der Nähe, `ctx.player` ist gesetzt |
| `vehicle` | | `'inside'` (im Fahrzeug), `'driver'` (am Steuer), `'outside'` (zu Fuß neben einem Fahrzeug) |
| `canShow` | | `function(ctx) return true end`, schnell und ohne Warten |
| `state` | | `function(ctx) return 'an' end`, kurzer Zustand rechts in der Zeile |
| `keepOpen` | | Menü bleibt nach der Aktion offen und wird neu aufgebaut (z. B. Türen auf und zu) |

`ctx` (Stand beim Öffnen):

| Feld | Inhalt |
|---|---|
| `ctx.player` | gewählte oder nächste Person `{ serverId, characterId, distance }` |
| `ctx.players` | alle Personen in der Nähe, nächste zuerst |
| `ctx.vehicle` | `{ handle, inside, seat, isDriver, engine, lights, speedKmh, freeSeats }` im Fahrzeug, `{ handle, inside = false }` zu Fuß daneben |

`lib.setInteractionCategory(pfad, { icon, order })` legt Icon und Reihenfolge einer Kategorie oder Unterkategorie fest. Die Reiter Person (10), Fahrzeug (20) und Organisation (30) stehen fest in der Config. Unterkategorien stehen vor den einzelnen Einträgen. Einträge einer Resource verschwinden, wenn sie stoppt.

**Wichtig:** Das Menü zeigt nur an. Jede Aktion mit Folgen (entlassen, Geld, Items) prüft der Server selbst: Rechte, Distanz mit der Position vom Server, Zustand.

## Kontextmenüs

```lua
lib.registerContext({
    id = 'garage_pillbox',
    title = 'Garage Pillbox',
    options = {
        { title = 'Fahrzeuge', icon = 'car', menu = 'garage_pillbox_cars' },
        { title = 'Stellplatzgebühr', readOnly = true, metadata = { Preis = '150 $', Fällig = 'jeden Montag' } },
    },
})
lib.registerContext({
    id = 'garage_pillbox_cars',
    title = 'Fahrzeuge',
    options = {
        { title = 'Sultan RS', description = 'LS 4821 · Tank 72 %', progress = 72, icon = 'car',
          onSelect = function(plate) TriggerSpawn(plate) end, args = 'LS 4821' },
    },
})
lib.showContext('garage_pillbox')
```

Option: `title` (Pflicht), `description`, `icon`, `disabled`, `readOnly`, `keepOpen`, `progress` (0 bis 100), `metadata` (Liste `{ label, value }` oder Tabelle), `menu` (anderes Kontextmenü als Untermenü), `onSelect` oder `event` und `args`. Bis 60 Optionen, Untermenüs bis 6 Ebenen tief, Schleifen werden abgefangen.

## Fortschritt

```lua
local done = lib.progressBar({
    duration = 6000,
    label = 'Reifen wechseln',
    canCancel = true,                                -- mit X abbrechen (Standard)
    disable = { move = true, car = true, combat = true },
    anim = { dict = 'mini@repair', clip = 'fixing_a_player' },   -- oder { scenario = 'WORLD_HUMAN_WELDING' }
    prop = { model = 'prop_tool_wrench', bone = 57005, pos = { x = 0.1, y = 0.0, z = 0.0 }, rot = { x = 0, y = 0, z = 0 } },
})
if done then ... end
```

`lib.progressCircle` hat dieselben Felder und zeigt einen Kreis. Ergebnis `true` (fertig) oder `false` (abgebrochen, bewusstlos, `lib.cancelProgress()`). Es läuft immer nur einer. Animations-Namen und Knochen-IDs sind GTA-5-Daten und gehören im eigenen Script nach `data/`.

## Minigames

```lua
lib.skillCheck('medium')                              -- eine Runde, Taste E
lib.skillCheck({ 'easy', 'easy', 'hard' }, { 'w', 'a', 's', 'd' })   -- drei Runden, zufällige Taste
lib.skillCheck({ area = 30, speed = 1.2 })            -- eigene Werte (Grad, Umdrehungen pro Sekunde)
lib.lockpick({ pins = 6, attempts = 2 })              -- Stifte setzen, wenn sie im markierten Bereich stehen
lib.hack({ grid = 5, rounds = 4 })                    -- Folge merken und nachgeben
lib.wires({ count = 5 })                              -- Kabel nach Form und Farbe verbinden
```

Alle liefern `true` oder `false`. `Esc` gibt auf. Standardwerte und Grenzen stehen in `Config.Lib.Minigames`.

| Minigame | Optionen | Bedienung |
|---|---|---|
| Skillcheck | Schwierigkeit `easy`, `medium`, `hard` oder `{ area, speed }`, auch als Liste. Tasten als zweiter Wert | die angezeigte Taste, wenn der Zeiger im markierten Bereich ist |
| Schloss knacken | `pins` (3 bis 8), `attempts`, `zone`, `speed`, `timeLimitMs` | Leertaste, E, Enter oder Klick |
| Hacken | `grid` (3 bis 6), `startLength`, `rounds`, `stepMs`, `timeLimitMs` | Klick oder Pfeiltasten und Enter |
| Kabel | `count` (3 bis 6), `timeLimitMs` | Klick links, dann rechts, oder Pfeiltasten und Enter |

**Für Wertvolles den Server entscheiden lassen.** Ein Ergebnis aus dem Client kann ein Cheater fälschen. Darum gibt es das Minigame auch vom Server:

```lua
-- Server, z. B. Tresor knacken
local success, err = lib.minigame(source, 'lockpick', { pins = 7 })
if success then
    -- Distanz und Zustand trotzdem selbst prüfen, dann Beute geben
end
```

Der Server misst die Zeit selbst. Ist das Ergebnis schneller da, als ein Mensch es schaffen kann (`Config.Lib.Minigames.Server.MinDurationMs`), zählt es als nicht geschafft und steht im Log (`security.minigame_too_fast`, mit Resource). Pro Spieler läuft höchstens ein Minigame vom Server, wer offline geht oder nach 3 Minuten nicht antwortet, hat verloren.

## Dialoge

```lua
local values = lib.inputDialog('Rechnung ausstellen', {
    { type = 'number', label = 'Betrag', min = 1, max = 50000, required = true, description = 'In Dollar, ohne Cent.' },
    { type = 'select', label = 'Grund', required = true, options = { { value = 'repair', label = 'Reparatur' }, { value = 'tow', label = 'Abschleppen' } } },
    { type = 'textarea', label = 'Notiz', maxLength = 200 },
    { type = 'slider', label = 'Rabatt in Prozent', min = 0, max = 30, step = 5, default = 10 },
    { type = 'checkbox', label = 'Kopie an die Werkstattkasse', default = true },
}, { confirmLabel = 'Ausstellen' })
-- values = { 1250, 'repair', nil, 10, true } oder nil bei Abbruch

local answer = lib.alertDialog({ header = 'Fahrzeug verschrotten?', content = 'Das kann niemand rückgängig machen.', confirmLabel = 'Verschrotten', danger = true })
-- 'confirm' oder 'cancel'
```

Feldtypen: `input` (`minLength`, `maxLength`, `password`), `number` und `slider` (`min`, `max`, `step`), `textarea` (`maxLength`), `select` (`options`), `checkbox`. Alle haben `label`, `description`, `placeholder`, `required`, `disabled`, `default`. Die Lib kürzt Texte und begrenzt Zahlen, eine ungültige Auswahl wird `nil`. Was der Spieler eingibt, prüft der Server trotzdem noch einmal.

## Hinweis (TextUI)

```lua
lib.showTextUI('Werkbank benutzen', { key = 'E', position = 'left' })   -- left, right, top, bottom
lib.hideTextUI()
```

Derselbe Hinweis wird nur einmal geschickt, darum darf man ihn in einer Schleife aufrufen.

## Zonen und Punkte

Mit `'@core_lib/modules/zones.lua'` im fxmanifest. Läuft in deiner eigenen Resource, ein Thread prüft alle 300 ms die Position. Nur wenn du in einem Punkt mit `nearby` oder einer Zone mit `inside` stehst, läuft zusätzlich ein Thread jeden Frame.

```lua
local point = lib.points.new({ coords = { x = 452.1, y = -980.2, z = 30.7 }, distance = 2.0,
    onEnter = function() lib.showTextUI('Waffenkammer öffnen', { key = 'E' }) end,
    onExit = function() lib.hideTextUI() end,
    nearby = function(self) if Platform.IsActionPressed('respawn') then ... end end })

local zone = lib.zones.box({ coords = { x = -211.4, y = -1324.6, z = 30.9 }, size = { x = 6, y = 10, z = 4 }, rotation = 90,
    onEnter = function() ... end, onExit = function() ... end })
lib.zones.sphere({ coords = { ... }, radius = 5 })
lib.zones.poly({ points = { { x = 0, y = 0 }, { x = 10, y = 0 }, { x = 10, y = 8 } }, minZ = 20, maxZ = 35 })
zone:remove()
```

Koordinaten sind GTA-5-Daten und gehören im eigenen Script nach `data/*_gta5.lua`.

## Cache

Mit `'@core_lib/modules/cache.lua'` im fxmanifest. Wird alle 250 ms gelesen: `lib.cache.vehicle`, `seat`, `isDriver`, `coords`, `serverId`, `characterId`, `dead`. Bei Änderungen: `lib.onCache('vehicle', function(neu, alt) end)` (geht für `vehicle`, `seat`, `isDriver`, `characterId`, `dead`).

## Exports

Wer `init.lua` nicht nutzen will, ruft die Exports direkt. Die Start-Exports warten nicht, sie geben eine Nummer zurück (oder `nil` und einen Fehlercode). Das Ergebnis kommt als lokales Ereignis `core_lib:done (nummer, ergebnis)` oder über `GetResult(nummer)`.

| Client | Gibt zurück |
|---|---|
| `StartProgress(optionen)` | Nummer |
| `StartSkillCheck(schwierigkeit, tasten)`, `StartLockpick(o)`, `StartHack(o)`, `StartWires(o)` | Nummer |
| `StartInput(titel, felder, optionen)`, `StartAlert(optionen)` | Nummer |
| `GetResult(nummer)` | `true, ergebnis` oder `false` |
| `CancelProgress()`, `CancelMinigame()`, `CloseDialog()` | true oder false |
| `RegisterContext(def)`, `ShowContext(id)`, `HideContext()`, `GetOpenContext()` | |
| `ShowTextUI(text, optionen)`, `HideTextUI()`, `IsTextUIOpen()` | |
| `AddInteraction(def)`, `RemoveInteraction(id)`, `SetInteractionCategory(pfad, o)`, `OpenInteractionMenu()`, `CloseInteractionMenu()` | |
| `Notify(text, typ, dauer)` | |

| Server | Gibt zurück |
|---|---|
| `StartMinigame(source, art, optionen)` | Nummer oder nil und Fehlercode |
| `GetMinigameResult(nummer)` | nil (läuft), dann einmal true oder false |
| `Notify(source, text, typ)` | |

**Fehlercodes:** `busy` (läuft schon etwas), `invalid_input`, `dead`, `no_character`, `not_found`, `id_taken` (ID gehört einer anderen Resource), `invalid_target`, `invalid_vehicle`, `no_action`, `too_many`.

## Icons

`user`, `users`, `id-card`, `search`, `banknote`, `car`, `power`, `light`, `door`, `window`, `seat`, `package`, `close`, `building`, `crown`, `user-minus`, `user-plus`, `arrow-up`, `arrow-down`, `shield`, `wrench`, `phone`, `file`, `lock`, `unlock`, `key`, `settings`, `list`, `map-pin`, `hand`, `check`. Ein unbekannter Name zeigt einfach kein Icon. Neue Icons kommen als `<g id="i-name">` in `html/menu.html` (Strichstärke 1.5, 24er Raster).

## Config

Alles in `config.lua` unter `Config.Lib`: Taste und Befehl des G-Menüs, Abstand für Personen und Fahrzeuge, feste Kategorien, Dokumente, Grenzen für Geld geben, Schwierigkeiten und Grenzen der Minigames, Mindestzeiten auf dem Server. Die Farben aller UIs kommen aus `Config.UI.Colors` der Core.

## Aufbau

```
core_lib/
  init.lua              lib-Tabelle für andere Resources (Client und Server)
  modules/              zones.lua, cache.lua, laufen in der Resource, die sie einbindet
  config.lua            Config.Lib
  data/vehicle_gta5.lua Türen, Fenster, Sitze (GTA-5-Indizes)
  client/               main (UI, Fokus, Ergebnisse), progress, minigames, dialogs, textui, menu (Kontextmenüs),
                        interact (G-Menü), interact_person, interact_vehicle
  server/main.lua       Minigames vom Server mit Zeitprüfung
  html/                 index (Shell), menu, progress, game, dialog, textui
```

FiveM-Natives stehen nur in der Bridge der Core. Jede UI läuft im Browser mit Beispieldaten: `html/menu.html`, `html/dialog.html?kind=alert`, `html/game.html?kind=skillcheck` (oder `lockpick`, `hack`, `wires`), `html/progress.html?style=circle`, `html/textui.html?pos=right`.

## Noch nicht drin

Von ox_lib fehlen noch: Radialmenü (das G-Menü ersetzt es), Listenmenü mit Seitenwahl (`lib.showMenu`), Sprachdateien (`locale`), Raycast und Timer. Das kommt, wenn ein Script es braucht.

## Testen

```bash
python3 tests/test_core_lib.py      # ohne Datenbank, 123 Prüfungen
python3 tests/test_give_item.py     # Geld geben im Inventar, braucht die Test-Datenbank
```

Nur im Spiel prüfbar: Animationen und Props im Fortschrittsbalken, das Sperren der Steuerung, Motor, Licht, Türen, Fenster und Sitzwechsel am echten Fahrzeug, die Tastatur ohne Mauszeiger bei Skillcheck und Schloss, und ob `G` mit einer anderen Taste kollidiert.
