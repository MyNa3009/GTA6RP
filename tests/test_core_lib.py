"""Tests fuer die core_lib ohne Datenbank: echte Lua-Dateien (Client und Server), Bridge als Attrappe.

Prueft G-Menue (Pfade, Kategorien, Personen, Fahrzeug), Kontextmenues, Dialoge, Fortschritt, Minigames und
die Zeitpruefung der Minigames auf dem Server. Die Zeit laeuft virtuell, Platform.Wait wartet nicht wirklich.
"""
import os
import sys

import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, 'core')
LIB = os.path.join(ROOT, 'core_lib')

CLIENT_FILES = ['client/main.lua', 'client/progress.lua', 'client/minigames.lua', 'client/dialogs.lua', 'client/textui.lua',
                'client/menu.lua', 'client/interact.lua', 'client/interact_person.lua', 'client/interact_vehicle.lua']

ok = fail = 0


def check(label, condition, info=None):
    global ok, fail
    if condition:
        ok += 1
        print('  ok   ', label)
    else:
        fail += 1
        print('  FEHLER', label, info if info is not None else '')


# Attrappe der Bridge: zeichnet Aufrufe auf, Threads laufen als Koroutinen mit virtueller Zeit
PRELUDE = r'''
Calls = {}
local function record(name, ...)
    Calls[#Calls + 1] = { name = name, args = table.pack(...) }
end

Now = 0
local threads = {}
Platform, Network = {}, {}
function Platform.Print(level, msg) record('Print', level, msg) end
function Platform.Async(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = Now } end
function Platform.Wait(ms) coroutine.yield(ms or 0) end
function Platform.GetTime() return Now end
function Tick(ms)
    local target = Now + ms
    repeat
        local ran = false
        for i = #threads, 1, -1 do
            local t = threads[i]
            if t.wake <= Now then
                local okay, wait = coroutine.resume(t.co)
                if not okay then record('ThreadError', wait) end
                if coroutine.status(t.co) == 'dead' then table.remove(threads, i) else t.wake = Now + math.max(1, wait or 0) ran = true end
            end
        end
        local nextWake = target
        for _, t in ipairs(threads) do if t.wake < nextWake then nextWake = t.wake end end
        if nextWake > Now then Now = math.min(nextWake, target) end
    until Now >= target and not ran
end

UiHandlers, Exports, Events, Commands = {}, {}, {}, {}
function Platform.UiOn(name, fn) UiHandlers[name] = fn end
function Platform.UiSend(action, data) record('UiSend', action, data) end
function Platform.UiFocus(on, cursor) record('UiFocus', on, cursor) end
function Platform.Export(name, fn) Exports[name] = fn end
function Platform.OnEvent(name, fn) Events[name] = Events[name] or {}; table.insert(Events[name], fn) end
function Platform.Emit(name, ...) record('Emit', name, ...) for _, fn in ipairs(Events[name] or {}) do fn(...) end end
StopHandlers = {}
function Platform.OnResourceStop(fn) table.insert(StopHandlers, fn) end
Calling = nil
function Platform.GetCallingResource() return Calling end
function Platform.GetResourceName() return 'core_lib' end
function Platform.RegisterKeyCommand(name, desc, key, fn) Commands[name] = { key = key, fn = fn } end
Started = { core_inventory = true }
function Platform.IsResourceStarted(name) return Started[name] == true end
function Platform.CallExport(res, name, ...) record('CallExport', res, name, ...) if name == 'GiveItem' then return true end return nil end
function Platform.GetActionLabel(a) return a == 'cancel' and 'X' or a end
Pressed = {}
function Platform.IsActionPressed(a) return Pressed[a] == true end
Dead = false
function Platform.IsOwnPedDead() return Dead end
Paused = false
function Platform.IsPauseMenuOpen() return Paused end
for _, name in ipairs({ 'DisableActionsThisFrame', 'ClearOwnTasks', 'StopOwnAnim', 'DeleteLocalProp' }) do
    Platform[name] = function(...) record(name, ...) end
end
function Platform.PlayOwnAnim(...) record('PlayOwnAnim', ...) return true end
function Platform.PlayOwnScenario(...) record('PlayOwnScenario', ...) return true end
function Platform.AttachPropToOwnPed(...) record('AttachProp', ...) return 77 end
function Platform.GetOwnServerId() return 1 end

Nearby = {}
function Platform.GetNearbyPlayers(dist, self) return Nearby end
Sight = nil        -- Spieler, den man anschaut: { serverId, distance }
function Platform.GetPlayerInSight(dist, angle, onFoot)
    if not Sight or (onFoot and Sight.inVehicle) then return nil end
    return { serverId = Sight.serverId, ped = 1, distance = Sight.distance }
end
function Platform.DrawPlayerRing(serverId, style) record('DrawPlayerRing', serverId, style.type) return true end
Public = {}
function Network.GetPlayerPublic(id, key) return Public[id] and Public[id][key] end
NetOn = {}
function Network.On(name, fn) NetOn[name] = fn end
function Network.Call(name, data) record('NetCall', name, data) return { ok = true } end

Vehicle = nil      -- Stand im Fahrzeug
NearVehicle = nil  -- Fahrzeug, auf das man zu Fuss schaut: { handle, distance, plate, locked, center, freeSeats }
Doors = {}         -- [index] = { valid, open }
Windows = {}       -- [index] = { valid, down }
function Platform.GetOwnVehicleState() return Vehicle end
function Platform.GetVehicleInSightOnFoot()
    if Vehicle or not NearVehicle then return nil end
    return { vehicle = NearVehicle.handle, distance = NearVehicle.distance }
end
function Platform.GetVehicleOutsideState(v)
    if not NearVehicle or v ~= NearVehicle.handle then return nil end
    return { plate = NearVehicle.plate or '', locked = NearVehicle.locked == true, distance = NearVehicle.center or 2.0,
        freeSeats = NearVehicle.freeSeats or {} }
end
function Platform.SetEntityOutline(e, on) record('Outline', e, on) return true end
function Platform.SetVehicleDoorFromOutside(v, i, open) record('DoorOutside', v, i, open) Doors[i].open = open return true end
function Platform.EnterVehicleSeat(v, seat) record('EnterSeat', v, seat) return true end
function Platform.IsOwnVehicle(v) return Vehicle ~= nil and v == Vehicle.vehicle end
function Platform.SetVehicleEngine(v, on) record('SetVehicleEngine', v, on) Vehicle.engine = on return true end
function Platform.SetVehicleLights(v, on) record('SetVehicleLights', v, on) return true end
function Platform.HasVehicleDoor(v, i) return Doors[i] ~= nil and Doors[i].valid end
function Platform.IsVehicleDoorOpen(v, i) return Doors[i] ~= nil and Doors[i].open end
function Platform.SetVehicleDoor(v, i, open) record('SetVehicleDoor', v, i, open) Doors[i].open = open return true end
function Platform.CloseAllVehicleDoors(v) record('CloseAllVehicleDoors', v) for _, d in pairs(Doors) do d.open = false end return true end
function Platform.HasVehicleWindow(v, i) return Windows[i] ~= nil and Windows[i].valid end
function Platform.IsVehicleWindowDown(v, i) return Windows[i] ~= nil and Windows[i].down end
function Platform.SetVehicleWindow(v, i, down) record('SetVehicleWindow', v, i, down) Windows[i].down = down return true end
function Platform.MoveToSeat(v, seat) record('MoveToSeat', v, seat) return true end
'''


def load(lua, path):
    with open(path, encoding='utf-8') as f:
        source = f.read()
    loader = lua.eval('function(src, name) local f, err = load(src, "@" .. name) if not f then error(err) end return f end')
    loader(source, os.path.relpath(path, ROOT))()


def client_env():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(PRELUDE)
    load(lua, os.path.join(CORE, 'shared/config.lua'))
    load(lua, os.path.join(LIB, 'config.lua'))
    load(lua, os.path.join(LIB, 'data/vehicle_gta5.lua'))
    load(lua, os.path.join(LIB, 'data/target_gta5.lua'))
    for name in CLIENT_FILES:
        load(lua, os.path.join(LIB, name))
    return lua


def calls(lua, name):
    result = []
    for entry in lua.globals().Calls.values():
        if entry.name == name:
            args = entry.args
            result.append([args[i] for i in range(1, args.n + 1)])
    return result


def clear(lua):
    lua.execute('Calls = {}')


def last_ui(lua, action):
    for args in reversed(calls(lua, 'UiSend')):
        if args[0] == action:
            return args[1]
    return None


def ui(lua, name, data):
    table = lua.table_from(data) if isinstance(data, dict) else data
    return lua.globals().UiHandlers[name](table)


def tabs_of(payload):
    return [tab.label for tab in payload.tabs.values()] if payload and payload.tabs else []


def find(nodes, label):
    for node in nodes.values():
        if node.label == label:
            return node
    return None


def to_list(table):
    return [table[i] for i in range(1, len(table) + 1)] if table else []


# ----------------------------------------------------------------------
print('Laden')
lua = client_env()
g = lua.globals()
check('Versionspruefung besteht, Lib ist da', g.Lib is not None and g.LibDisabled is None)
early = g.Exports['ShowTextUI']('Vor dem Laden')
check('Nachricht vor ui_ready wird nicht gesendet', not [a for a in calls(lua, 'UiSend') if a[0] == 'textui_open'])
for name in ['menu', 'dialog', 'game', 'progress', 'textui']:
    reply = ui(lua, 'ui_ready', {'ui': name})
c = reply.data.colors
check('ui_ready liefert die Logo-Farben der Lib (TextUI)', reply.ok and (c.base, c.ink, c.accent, c.signal) == ('24 15 36', '253 241 233', '232 64 190', '240 84 96'))
lua.execute("Config.Lib.Colors.signal = nil")
check('fehlt ein Wert in Config.Lib.Colors, gilt der der Core', ui(lua, 'ui_ready', {'ui': 'dialog'}).data.colors.signal == '220 82 72')
lua.execute("Config.Lib.Colors.signal = '240 84 96'")
menu_colors = ui(lua, 'ui_ready', {'ui': 'menu'}).data.colors
check('Menue hat die Logo-Farben (Aubergine, Creme, Magenta, Pfirsich)',
      (menu_colors.base, menu_colors.ink, menu_colors.accent, menu_colors.mark) == ('24 15 36', '253 241 233', '232 64 190', '244 152 105'))
lua.globals().Tick(10)
check('wartende Nachricht nach ui_ready gesendet', [a for a in calls(lua, 'UiSend') if a[0] == 'textui_open'])
g.Exports['HideTextUI']()
check('Taste G und Befehl /interaktion angemeldet', g.Commands['interaktion'] is not None and g.Commands['interaktion'].key == 'G')
for name in ['AddInteraction', 'StartProgress', 'StartSkillCheck', 'StartLockpick', 'StartHack', 'StartWires', 'StartInput', 'StartAlert',
             'RegisterContext', 'ShowContext', 'ShowTextUI', 'GetResult', 'OpenInteractionMenu']:
    check(f'Export {name}', g.Exports[name] is not None)

# ----------------------------------------------------------------------
print('G-Menue: Eintraege anmelden')
add = g.Exports['AddInteraction']
g.Calling = 'org_script'
noop = lua.eval('function(ctx) Selected = ctx end')
res = add(lua.table_from({'id': 'org_fire', 'path': 'Organisation/Leader', 'label': 'Entlassen', 'icon': 'user-minus', 'target': 'player', 'onSelect': noop}))
check('Eintrag mit Pfad Organisation/Leader', res == (True,) or res is True, res)
check('ohne Pfad abgelehnt', add(lua.table_from({'id': 'x', 'label': 'X', 'onSelect': noop}))[1] == 'invalid_input')
check('ohne Aktion abgelehnt', add(lua.table_from({'id': 'x', 'path': 'A', 'label': 'X'}))[1] == 'no_action')
check('falsches target abgelehnt', add(lua.table_from({'id': 'x', 'path': 'A', 'label': 'X', 'target': 'auto', 'onSelect': noop}))[1] == 'invalid_target')
check('zu tiefer Pfad abgelehnt', add(lua.table_from({'id': 'x', 'path': 'A/B/C/D/E', 'label': 'X', 'onSelect': noop}))[1] == 'invalid_input')
check('Pfad als Liste geht', add(lua.table_from({'id': 'org_duty', 'path': lua.table_from(['Organisation']), 'label': 'Dienst', 'event': 'org:duty', 'order': 5})) in ((True,), True))
add(lua.table_from({'id': 'org_hire', 'path': 'Organisation / Leader', 'label': 'Einstellen', 'target': 'player', 'selectKey': 'org_script:i:org_hire', 'order': 1}))
g.Calling = 'anderes_script'
check('fremde ID wird nicht ueberschrieben', add(lua.table_from({'id': 'org_fire', 'path': 'A', 'label': 'X', 'onSelect': noop}))[1] == 'id_taken')
check('fremde Resource kann nicht entfernen', g.Exports['RemoveInteraction']('org_fire') is False)
g.Calling = None

# ----------------------------------------------------------------------
print('G-Menue: Oeffnen ohne Person und ohne Fahrzeug')
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('nur Organisation (Person und Fahrzeug passen gerade nicht)', tabs_of(payload) == ['Organisation'], tabs_of(payload))
org = payload.tabs[1]['items']
check('Dienst steht oben, ohne Person sichtbar', to_list(org) and org[1].label == 'Leader' or find(org, 'Dienst') is not None)
leader = find(org, 'Leader')
check('Leader ist leer, weil alle Eintraege eine Person brauchen', leader is None, leader)
check('Fokus mit Maus', calls(lua, 'UiFocus')[-1] == [True, True])
g.Menu.Close()

print('G-Menue: zwei Personen in der Naehe, angeschaut wird ID 342')
lua.execute("Nearby = { { serverId = 4, distance = 1.23 }, { serverId = 9, distance = 2.61 } }; Public = { [4] = { coreId = 17 }, [9] = { coreId = 342 } }")
lua.globals().Tick(200)
check('ohne Hinschauen kein Ziel und kein Kreis', not calls(lua, 'DrawPlayerRing') and g.Exports['GetInteractionTarget']() is None)
lua.execute("Sight = { serverId = 9, distance = 2.61 }")
lua.globals().Tick(200)
check('angeschaut: Kreis am Boden unter ID 342 (Markertyp aus data/)', calls(lua, 'DrawPlayerRing') and calls(lua, 'DrawPlayerRing')[-1] == [9, 27], calls(lua, 'DrawPlayerRing')[-1:])
check('Ziel als Export', g.Exports['GetInteractionTarget']().characterId == 342)
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('Kategorien Person und Organisation in fester Reihenfolge', tabs_of(payload) == ['Person', 'Organisation'], tabs_of(payload))
check('Mitte nennt die angeschaute Person, nicht die naechste', payload.subtitle == 'Person: ID 342 · 2,6 m', payload.subtitle)
check('keine Personenliste mehr', payload.players is None)
person = payload.tabs[1]['items']
check('Person: Ausweis zeigen (Gruppe), Durchsuchen, Geld geben', [n.label for n in to_list(person)] == ['Ausweis zeigen', 'Durchsuchen', 'Geld geben'], [n.label for n in to_list(person)])
docs = find(person, 'Ausweis zeigen').children
check('sieben Dokumente in der Gruppe', len(to_list(docs)) == 7)
leader = find(payload.tabs[2]['items'], 'Leader')
check('Leader-Gruppe mit Einstellen vor Entlassen', [n.label for n in to_list(leader.children)] == ['Einstellen', 'Entlassen'], leader and [n.label for n in to_list(leader.children)])
lua.execute("Sight = { serverId = 4, distance = 1.23 }")
lua.globals().Tick(300)
check('bei offenem Menue bleibt das Ziel, auch wenn man wegschaut', calls(lua, 'DrawPlayerRing')[-1][0] == 9)
clear(lua)
reply = ui(lua, 'menu_select', {'id': 'e:person_search'})
lua.globals().Tick(10)
check('Durchsuchen direkt bei der angeschauten Person', reply.ok and calls(lua, 'CallExport')[-1] == ['core_inventory', 'SearchPlayer', 9], calls(lua, 'CallExport'))
check('Menue zu nach der Aktion', g.Menu.IsOpen() is False and calls(lua, 'UiFocus')[-1][0] is False)
lua.globals().Tick(300)
check('Menue zu: neues Blickziel ID 17', g.Exports['GetInteractionTarget']().characterId == 17)
g.Interact.Open()
lua.execute("Nearby = { { serverId = 9, distance = 2.0 } }")
reply = ui(lua, 'menu_select', {'id': 'e:person_search'})
check('Person weggegangen: abgelehnt', reply.ok is False and reply.error == 'player_gone')
g.Menu.Close()
lua.execute("Sight = { serverId = 9, distance = 2.0 }; Public[9] = nil")
lua.globals().Tick(300)
check('Person ohne Charakter ist kein Ziel', g.Exports['GetInteractionTarget']() is None)
lua.execute("Public[9] = { coreId = 342 }")

print('G-Menue: Aktion einer anderen Resource ueber init.lua (selectKey)')
lua.execute("Nearby = { { serverId = 4, distance = 1.0 } }; Sight = { serverId = 4, distance = 1.0 }")
g.Interact.Open()
clear(lua)
reply = ui(lua, 'menu_select', {'id': 'e:org_hire'})
emits = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:select']
check('eine Person: direkt ausgefuehrt, Ereignis mit Schluessel', emits and emits[-1][1] == 'org_script:i:org_hire' and emits[-1][2].player.characterId == 17, emits)

print('G-Menue: Funktion einer anderen Resource')
g.Interact.Open()
ui(lua, 'menu_select', {'id': 'e:org_fire'})
lua.globals().Tick(10)
check('onSelect bekommt die Person', g.Selected is not None and g.Selected.player.serverId == 4)

print('G-Menue: Fahrzeug am Steuer')
lua.execute('''Nearby = {}; Sight = nil
Vehicle = { vehicle = 501, seat = -1, isDriver = true, engine = true, lights = false, speedKmh = 0, freeSeats = { 0, 1 } }
Doors = { [0] = { valid = true, open = false }, [1] = { valid = true, open = false }, [4] = { valid = true, open = false }, [5] = { valid = true, open = true } }
Windows = { [0] = { valid = true, down = false }, [1] = { valid = true, down = false } }''')
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('nur Fahrzeug und Organisation', tabs_of(payload) == ['Fahrzeug', 'Organisation'], tabs_of(payload))
car = payload.tabs[1]['items']
labels = [n.label for n in to_list(car)]
check('Motor, Licht, Tueren, Fenster, Sitz wechseln', labels == ['Motor', 'Licht', 'Türen', 'Fenster', 'Sitz wechseln'], labels)
check('Motor zeigt "an"', find(car, 'Motor').badge == 'an')
doors = [ (n.label, n.badge) for n in to_list(find(car, 'Türen').children)]
check('nur vorhandene Tueren, Kofferraum offen, "Alle schließen" da', doors == [('Fahrertür', 'zu'), ('Beifahrertür', 'zu'), ('Motorhaube', 'zu'), ('Kofferraum', 'offen'), ('Alle schließen', None)], doors)
seats = [n.label for n in to_list(find(car, 'Sitz wechseln').children)]
check('freie Sitze', seats == ['Beifahrersitz', 'Hinten links'], seats)
check('kein Kofferraum-Eintrag von aussen, wenn man drin sitzt', find(car, 'Kofferraum öffnen') is None)
clear(lua)
reply = ui(lua, 'menu_select', {'id': 'e:vehicle_engine'})
lua.globals().Tick(10)
check('Motor aus, Menue bleibt offen', reply.data.close is False and calls(lua, 'SetVehicleEngine') == [[501, False]] and g.Menu.IsOpen())
lua.globals().Tick(200)
update = last_ui(lua, 'menu_update')
check('Neuaufbau nach keepOpen zeigt "aus"', update and find(update.tabs[1]['items'], 'Motor').badge == 'aus')
ui(lua, 'menu_select', {'id': 'e:vehicle_doors_close'})
lua.globals().Tick(10)
check('Alle Tueren schliessen', calls(lua, 'CloseAllVehicleDoors') == [[501]])
lua.execute('Vehicle.speedKmh = 40')
lua.globals().Tick(200)
g.Menu.Close()
clear(lua)
g.Interact.Open()
car = last_ui(lua, 'menu_open').tabs[1]['items']
check('bei 40 km/h kein Sitzwechsel', find(car, 'Sitz wechseln') is None)
g.Menu.Close()

print('G-Menue: Mitfahrer')
lua.execute('Vehicle = { vehicle = 501, seat = 0, isDriver = false, engine = true, lights = false, speedKmh = 0, freeSeats = { 1 } }')
clear(lua)
g.Interact.Open()
car = last_ui(lua, 'menu_open').tabs[1]['items']
check('Mitfahrer: kein Motor, keine Tueren', find(car, 'Motor') is None and find(car, 'Türen') is None)
check('Mitfahrer: nur das eigene Fenster', [n.label for n in to_list(find(car, 'Fenster').children)] == ['Fenster vorne rechts'])
g.Menu.Close()

print('G-Menue: zu Fuss ein Fahrzeug anschauen')
lua.execute("""Vehicle = nil
Doors = { [0] = { valid = true, open = false }, [1] = { valid = true, open = false }, [5] = { valid = true, open = false } }
NearVehicle = { handle = 777, distance = 2.04, plate = 'LS 4821', locked = false, freeSeats = { -1, 1 } }""")
clear(lua)
lua.globals().Tick(200)
check('angeschautes Fahrzeug leuchtet (Umrandung an)', calls(lua, 'Outline') == [[777, True]], calls(lua, 'Outline'))
check('kein Kreis am Boden fuer ein Fahrzeug', not calls(lua, 'DrawPlayerRing'))
check('Fahrzeug als Export', g.Exports['GetInteractionVehicle']().handle == 777)
lua.globals().Tick(600)
check('Umrandung wird nicht jedes Mal neu gesetzt', len(calls(lua, 'Outline')) == 1)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('Fahrzeug zuerst, dann Organisation', tabs_of(payload) == ['Fahrzeug', 'Organisation'], tabs_of(payload))
check('Mitte nennt Kennzeichen und Abstand', payload.subtitle == 'Fahrzeug: LS 4821 · 2,0 m', payload.subtitle)
car = payload.tabs[1]['items']
check('von aussen: Einsteigen, Tueren, Kofferraum-Inhalt', [n.label for n in to_list(car)] == ['Einsteigen', 'Türen', 'Kofferraum-Inhalt'], [n.label for n in to_list(car)])
check('keine Bedienung von drinnen (Motor, Licht, Fenster)', find(car, 'Motor') is None and find(car, 'Fenster') is None)
seats = [n.label for n in to_list(find(car, 'Einsteigen').children)]
check('Einsteigen nur auf freie Sitze', seats == ['Fahrersitz', 'Hinten links'], seats)
doors = [(n.label, n.badge) for n in to_list(find(car, 'Türen').children)]
check('Tueren von aussen mit Zustand, ohne "Alle schließen"', doors == [('Fahrertür', 'zu'), ('Beifahrertür', 'zu'), ('Kofferraum', 'zu')], doors)
clear(lua)
reply = ui(lua, 'menu_select', {'id': 'e:vehicle_outside_door_front_left'})
lua.globals().Tick(10)
check('Fahrertuer von aussen auf, Menue bleibt offen', reply.data.close is False and calls(lua, 'DoorOutside') == [[777, 0, True]])
lua.globals().Tick(200)
update = last_ui(lua, 'menu_update')
check('Neuaufbau nach der Aktion zeigt "offen"', update and find(find(update.tabs[1]['items'], 'Türen').children, 'Fahrertür').badge == 'offen')
lua.execute("NearVehicle.center = 9")
reply = ui(lua, 'menu_select', {'id': 'e:vehicle_outside_door_front_left'})
check('Fahrzeug zu weit weg: abgelehnt', reply.ok is False and reply.error == 'vehicle_gone', reply.error)
lua.execute("NearVehicle.center = 2")
clear(lua)
reply = ui(lua, 'menu_select', {'id': 'e:vehicle_enter_1'})
lua.globals().Tick(10)
check('Einsteigen hinten links, Menue zu', calls(lua, 'EnterSeat') == [[777, 1]] and g.Menu.IsOpen() is False)
g.Interact.Open()
ui(lua, 'menu_select', {'id': 'e:vehicle_trunk'})
lua.globals().Tick(10)
check('Kofferraum-Inhalt ueber das Inventar', calls(lua, 'CallExport')[-1] == ['core_inventory', 'OpenNearestTrunk'])

print('G-Menue: abgeschlossenes Fahrzeug')
lua.execute("NearVehicle.locked = true")
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('abgeschlossen: keine Kategorie Fahrzeug', 'Fahrzeug' not in tabs_of(payload), tabs_of(payload))
check('Mitte sagt "abgeschlossen"', payload.subtitle == 'Fahrzeug: LS 4821 · abgeschlossen · 2,0 m', payload.subtitle)
g.Menu.Close()
lua.execute("NearVehicle.locked = false; Started.core_inventory = false")
clear(lua)
g.Interact.Open()
car = last_ui(lua, 'menu_open').tabs[1]['items']
check('ohne Inventar kein Kofferraum-Inhalt, Tueren bleiben', find(car, 'Kofferraum-Inhalt') is None and find(car, 'Türen') is not None)
g.Menu.Close()
lua.execute("Started.core_inventory = true")

print('G-Menue: Umrandung wandert mit')
clear(lua)
lua.execute("NearVehicle = { handle = 888, distance = 1.5, plate = 'LS 0042', freeSeats = {} }")
lua.globals().Tick(200)
check('anderes Fahrzeug: alte Umrandung aus, neue an', calls(lua, 'Outline') == [[777, False], [888, True]], calls(lua, 'Outline'))
lua.execute("Sight = { serverId = 9, distance = 1.0 }; Public[9] = { coreId = 342 }; Nearby = { { serverId = 9, distance = 1.0 } }")
clear(lua)
lua.globals().Tick(200)
check('Person geht vor: Umrandung aus, Kreis an', calls(lua, 'Outline') == [[888, False]] and calls(lua, 'DrawPlayerRing'))
lua.execute("Sight.inVehicle = true")
clear(lua)
lua.globals().Tick(200)
check('Person sitzt im Fahrzeug: das Fahrzeug ist das Ziel', g.Exports['GetInteractionTarget']() is None and calls(lua, 'Outline') == [[888, True]], calls(lua, 'Outline'))
lua.execute("Vehicle = { vehicle = 888, seat = -1, isDriver = true, engine = true, lights = false, speedKmh = 0, freeSeats = {} }")
clear(lua)
lua.globals().Tick(200)
check('selbst eingestiegen: keine Umrandung mehr', calls(lua, 'Outline') == [[888, False]], calls(lua, 'Outline'))
lua.execute("Vehicle = nil; Sight = nil; Nearby = {}; NearVehicle = nil")
lua.globals().Tick(200)

print('G-Menue: fehlerhaftes canShow und gestoppte Resource')
g.Calling = 'kaputt'
add(lua.table_from({'id': 'broken', 'path': 'Organisation', 'label': 'Kaputt', 'canShow': lua.eval('function() error("boom") end'), 'event': 'x'}))
g.Calling = None
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('Fehler in canShow: Eintrag fehlt, Menue geht trotzdem auf', payload is not None and find(payload.tabs[1]['items'], 'Kaputt') is None)
check('Fehler wird gemeldet', any('canShow' in str(a[1]) for a in calls(lua, 'Print')))
g.Menu.Close()
for fn in g.StopHandlers.values():
    fn('org_script')
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('Eintraege gestoppter Resource weg', payload is None or 'Organisation' not in tabs_of(payload) or find(payload.tabs[1]['items'], 'Dienst') is None)
check('ohne Eintraege kein Menue, sondern Hinweis', payload is None and any(a[0] == 'core:notify' for a in calls(lua, 'Emit')), tabs_of(payload))
g.Menu.Close()

print('G-Menue: ohne Berechtigung gar nicht da (canShow)')
g.Calling = 'org2'
add(lua.table_from({'id': 'lead_hire', 'path': 'Leader', 'label': 'Einstellen', 'event': 'x', 'canShow': lua.eval('function() return false end')}))
add(lua.table_from({'id': 'org_radio', 'path': 'Organisation', 'label': 'Funk', 'event': 'x', 'canShow': lua.eval('function() return true end')}))
g.Calling = None
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('Kategorie ohne erlaubte Eintraege fehlt im Kreis', 'Leader' not in tabs_of(payload), tabs_of(payload))
check('erlaubter Eintrag ist da, ohne Schloss', find(payload.tabs[1]['items'], 'Funk') is not None and find(payload.tabs[1]['items'], 'Funk').locked is None)
g.Menu.Close()
for fn in g.StopHandlers.values():
    fn('org2')
check('Menue holt eigene Farben', ui(lua, 'ui_ready', {'ui': 'menu'}).data.colors.mark == '244 152 105')

print('G-Menue: Pausemenue und Fahrzeug')
lua.execute("Nearby = { { serverId = 4, distance = 1.0 } }; Sight = { serverId = 4, distance = 1.0 }; Paused = true")
clear(lua)
g.Interact.Open()
check('im Pausemenue geht das G-Menue nicht auf', last_ui(lua, 'menu_open') is None and g.Menu.IsOpen() is False)
lua.execute("Paused = false; Vehicle = { vehicle = 501, seat = -1, isDriver = true, engine = true, lights = false, speedKmh = 0, freeSeats = {} }")
lua.globals().Tick(300)
check('im Fahrzeug: kein Blickziel, kein Kreis', g.Exports['GetInteractionTarget']() is None)
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('im Fahrzeug: keine Kategorie Person, Fahrzeug schon', 'Person' not in tabs_of(payload) and 'Fahrzeug' in tabs_of(payload), tabs_of(payload))
check('im Fahrzeug: keine Person in der Mitte', payload.subtitle is None)
g.Menu.Close()
lua.execute("Vehicle = nil; Sight = nil; Nearby = {}")
lua.globals().Tick(300)

print('G-Menue: bewusstlos')
lua.execute('Dead = true')
clear(lua)
g.Interact.Open()
check('bewusstlos: kein Menue', last_ui(lua, 'menu_open') is None)
lua.execute('Dead = false')

# ----------------------------------------------------------------------
print('Geld geben (Dialog und Inventar)')
lua.execute("Nearby = { { serverId = 4, distance = 1.0 } }; Sight = { serverId = 4, distance = 1.0 }")
g.Interact.Open()
clear(lua)
ui(lua, 'menu_select', {'id': 'e:person_give_cash'})
lua.globals().Tick(10)
dialog = last_ui(lua, 'dialog_open')
check('Dialog fuer den Betrag', dialog is not None and dialog.title == 'Geld geben an ID 17' and dialog.fields[1].type == 'number')
reply = ui(lua, 'dialog_submit', {'id': dialog.id, 'values': lua.table_from([None])})
check('leerer Pflichtbetrag abgelehnt', reply.ok is False and reply.error == 'required')
reply = ui(lua, 'dialog_submit', {'id': dialog.id, 'values': lua.table_from([5000000])})
lua.globals().Tick(100)
check('zu hoher Betrag auf das Maximum begrenzt', calls(lua, 'CallExport')[-1] == ['core_inventory', 'GiveItem', 4, 'cash', 1000000], calls(lua, 'CallExport'))

# ----------------------------------------------------------------------
print('Dialoge')
inp = g.Exports['StartInput']
check('ohne Felder abgelehnt', inp('Titel', lua.table_from([]))[1] == 'invalid_input')
check('unbekannter Feldtyp abgelehnt', inp('Titel', lua.table_from([lua.table_from({'type': 'farbe', 'label': 'X'})]))[1] == 'invalid_input')
fields = lua.table_from([
    lua.table_from({'type': 'input', 'label': 'Name', 'maxLength': 5}),
    lua.table_from({'type': 'number', 'label': 'Menge', 'min': 1, 'max': 10}),
    lua.table_from({'type': 'select', 'label': 'Grund', 'options': lua.table_from([lua.table_from({'value': 'a', 'label': 'A'}), 'b'])}),
    lua.table_from({'type': 'checkbox', 'label': 'Ja'}),
])
clear(lua)
did = inp('Rechnung', fields)
check('zweiter Dialog gleichzeitig abgelehnt', inp('Noch einer', fields)[1] == 'busy')
ui(lua, 'dialog_submit', {'id': did, 'values': lua.table_from(['Fabian Nandes', -3, 'z', 'x'])})
done = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:done' and a[1] == did]
values = done[-1][2] if done else None
check('Text gekuerzt, Zahl begrenzt, falsche Auswahl nil, Checkbox false',
      values is not None and values[1] == 'Fabia' and values[2] == 1 and values[3] is None and values[4] is False, values and to_list(values))
aid = g.Exports['StartAlert'](lua.table_from({'header': 'Entlassen?', 'content': 'ID 342', 'danger': True}))
ui(lua, 'dialog_submit', {'id': aid, 'confirmed': True})
done = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:done' and a[1] == aid]
check('Bestaetigung liefert "confirm"', done and done[-1][2] == 'confirm')

# ----------------------------------------------------------------------
print('Fortschritt')
start = g.Exports['StartProgress']
check('ohne Dauer abgelehnt', start(lua.table_from({'label': 'X'}))[1] == 'invalid_input')
clear(lua)
pid = start(lua.table_from({'duration': 2000, 'label': 'Reifen wechseln', 'disable': lua.table_from({'move': True}),
                            'anim': lua.table_from({'dict': 'mini@repair', 'clip': 'fixing_a_player'}), 'prop': lua.table_from({'model': 'prop_tool_wrench'})}))
check('zweiter Balken gleichzeitig abgelehnt', start(lua.table_from({'duration': 1000}))[1] == 'busy')
lua.globals().Tick(1000)
check('Animation und Prop gestartet', calls(lua, 'PlayOwnAnim') and calls(lua, 'AttachProp'))
check('Steuerung gesperrt', calls(lua, 'DisableActionsThisFrame') and calls(lua, 'DisableActionsThisFrame')[-1][0].move is True)
lua.globals().Tick(1100)
done = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:done' and a[1] == pid]
check('nach 2 s fertig (true), Prop entfernt, Animation gestoppt', done and done[-1][2] is True and calls(lua, 'DeleteLocalProp') == [[77]] and calls(lua, 'StopOwnAnim'))
clear(lua)
pid = start(lua.table_from({'duration': 5000}))
lua.globals().Tick(500)
lua.execute("Pressed.cancel = true")
lua.globals().Tick(50)
lua.execute("Pressed.cancel = nil")
done = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:done' and a[1] == pid]
check('mit X abgebrochen (false)', done and done[-1][2] is False)
pid = start(lua.table_from({'duration': 5000, 'canCancel': False}))
lua.execute("Pressed.cancel = true")
lua.globals().Tick(5100)
lua.execute("Pressed.cancel = nil")
done = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:done' and a[1] == pid]
check('canCancel = false: X wirkt nicht', done and done[-1][2] is True)

# ----------------------------------------------------------------------
print('Minigames')
check('unbekannte Schwierigkeit abgelehnt', g.Exports['StartSkillCheck']('mega')[1] == 'invalid_input')
clear(lua)
mid = g.Exports['StartLockpick'](lua.table_from({'pins': 50, 'attempts': 0, 'speed': 'schnell'}))
opened = last_ui(lua, 'game_open')
check('Optionen begrenzt (Stifte 8, Versuche 1, Tempo Standard)', opened.options.pins == 8 and opened.options.attempts == 1 and opened.options.speed == 0.9, (opened.options.pins, opened.options.attempts, opened.options.speed))
check('Schloss ohne Mauszeiger', calls(lua, 'UiFocus')[-1] == [True, False])
check('nur ein Minigame gleichzeitig', g.Exports['StartHack']()[1] == 'busy')
reply = ui(lua, 'game_result', {'id': mid + 1, 'success': True})
check('falsche Nummer abgelehnt', reply.ok is False)
ui(lua, 'game_result', {'id': mid, 'success': True})
done = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:done' and a[1] == mid]
check('Ergebnis geschafft, Fokus weg', done and done[-1][2] is True and calls(lua, 'UiFocus')[-1][0] is False)
clear(lua)
sid = g.Exports['StartSkillCheck'](lua.table_from(['easy', 'hard']), lua.table_from(['w', 'a', 'Strg']))
stages = last_ui(lua, 'game_open').options.stages
check('Skillcheck: zwei Runden, Tasten nur W oder A', len(to_list(stages)) == 2 and all(s.key in ('W', 'A') for s in to_list(stages)))
lua.execute('Dead = true')
lua.globals().Tick(600)
lua.execute('Dead = false')
done = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:done' and a[1] == sid]
check('bewusstlos: Minigame verloren', done and done[-1][2] is False)

print('Minigame vom Server')
clear(lua)
lua.globals().NetOn['core_lib:minigame'](lua.table_from({'id': 12, 'kind': 'wires', 'options': lua.table_from({'count': 4})}))
lua.globals().Tick(10)
gid = last_ui(lua, 'game_open').id
ui(lua, 'game_result', {'id': gid, 'success': True})
lua.globals().Tick(100)
net = calls(lua, 'NetCall')
check('Ergebnis geht an den Server', net and net[-1][0] == 'lib_minigame_result' and net[-1][1].id == 12 and net[-1][1].success is True)

# ----------------------------------------------------------------------
print('Kontextmenues')
reg = g.Exports['RegisterContext']
g.Calling = 'garage'
reg(lua.table_from([
    lua.table_from({'id': 'garage', 'title': 'Garage Pillbox', 'options': lua.table_from([
        lua.table_from({'title': 'Fahrzeuge', 'menu': 'garage_cars', 'icon': 'car'}),
        lua.table_from({'title': 'Gebühr', 'readOnly': True, 'metadata': lua.table_from({'Preis': '150 $'})}),
        lua.table_from({'title': 'Schleife', 'menu': 'garage_loop'}),
    ])}),
    lua.table_from({'id': 'garage_cars', 'title': 'Fahrzeuge', 'options': lua.table_from([
        lua.table_from({'title': 'Sultan RS', 'description': 'LS 4821', 'progress': 72, 'selectKey': 'garage:c:garage_cars:1', 'args': 'sultan'}),
    ])}),
    lua.table_from({'id': 'garage_loop', 'title': 'Schleife', 'options': lua.table_from([
        lua.table_from({'title': 'Zurück zur Garage', 'menu': 'garage'}),
    ])}),
]))
g.Calling = None
clear(lua)
check('Kontextmenue zeigen', g.Exports['ShowContext']('garage') is True)
ctx = last_ui(lua, 'menu_open')
items = ctx['items']
check('Untermenue eingesetzt', items[1].children[1].label == 'Sultan RS' and items[1].children[1].progress == 72)
check('Metadaten als Liste', items[2].metadata[1].label == 'Preis' and items[2].metadata[1].value == '150 $')
loop = items[3].children[1]
check('Schleife A > B > A wird nicht endlos aufgebaut', loop.children is None)
check('unbekanntes Menue', g.Exports['ShowContext']('gibtsnicht')[1] == 'not_found')
clear(lua)
reply = ui(lua, 'menu_select', {'id': items[1].children[1].id})
emits = [a for a in calls(lua, 'Emit') if a[0] == 'core_lib:select']
check('Auswahl geht mit args an die Resource', emits and emits[-1][1] == 'garage:c:garage_cars:1' and emits[-1][2] == 'sultan')
check('readOnly ist nicht waehlbar', ui(lua, 'menu_select', {'id': items[2].id}).ok is False)
g.Exports['ShowContext']('garage')
for fn in g.StopHandlers.values():
    fn('garage')
check('Resource gestoppt: Menue zu und weg', g.Menu.IsOpen() is False and g.Exports['ShowContext']('garage')[1] == 'not_found')

# ----------------------------------------------------------------------
print('TextUI')
clear(lua)
show = g.Exports['ShowTextUI']
show('Werkbank benutzen', lua.table_from({'key': 'E'}))
show('Werkbank benutzen', lua.table_from({'key': 'E'}))
check('gleicher Hinweis nur einmal gesendet', len([a for a in calls(lua, 'UiSend') if a[0] == 'textui_open']) == 1)
check('leerer Text abgelehnt', show('') is False)
g.Exports['HideTextUI']()
check('ausblenden', calls(lua, 'UiSend')[-1][0] == 'textui_close')

# ----------------------------------------------------------------------
print('init.lua (so nutzen andere Scripts die Lib)')
lua.execute('''
local original = Platform.CallExport
function Platform.CallExport(res, name, ...)
    if res == 'core_lib' then return Exports[name](...) end
    return original(res, name, ...)
end
Platform.GetResourceName = function() return 'werkstatt' end
''')
load(lua, os.path.join(LIB, 'init.lua'))
lua.execute('''
Results = {}
Platform.Async(function() Results.progress = lib.progressBar({ duration = 1500, label = 'Reparieren' }) end)
''')
lua.globals().Tick(1700)
check('lib.progressBar wartet und liefert true', g.Results.progress is True)
lua.execute('''
Platform.Async(function() Results.input = lib.inputDialog('Rechnung', { { type = 'number', label = 'Betrag', required = true } }) end)
''')
lua.globals().Tick(10)
dialog = last_ui(lua, 'dialog_open')
ui(lua, 'dialog_submit', {'id': dialog.id, 'values': lua.table_from([250])})
lua.globals().Tick(100)
check('lib.inputDialog liefert die Werte', g.Results.input is not None and g.Results.input[1] == 250)
lua.execute('''
Platform.Async(function() Results.alert = lib.alertDialog({ header = 'Sicher?' }) end)
''')
lua.globals().Tick(10)
ui(lua, 'dialog_submit', {'id': last_ui(lua, 'dialog_open').id, 'confirmed': False})
lua.globals().Tick(100)
check('lib.alertDialog liefert "cancel"', g.Results.alert == 'cancel')
lua.execute('''
Platform.Async(function() Results.skill = lib.skillCheck({ 'easy', 'easy' }, { 'e' }) end)
''')
lua.globals().Tick(10)
ui(lua, 'game_result', {'id': last_ui(lua, 'game_open').id, 'success': False})
lua.globals().Tick(100)
check('lib.skillCheck liefert false', g.Results.skill is False)
lua.execute('''
Waited = nil
lib.addInteraction({ id = 'werk_repair', path = 'Werkstatt/Service', label = 'Reparieren', vehicle = 'outside',
    onSelect = function(ctx) Results.waitedInAction = lib.progressBar({ duration = 800 }) end })
''')
lua.execute("Sight = nil; NearVehicle = { handle = 900, distance = 2.0, plate = 'WERK 1', freeSeats = {} }")
clear(lua)
g.Interact.Open()
payload = last_ui(lua, 'menu_open')
check('eigener Reiter Werkstatt mit Unterkategorie Service', 'Werkstatt' in tabs_of(payload), tabs_of(payload))
ui(lua, 'menu_select', {'id': 'e:werk_repair'})
lua.globals().Tick(1000)
check('Aktion laeuft in der eigenen Resource und darf warten (Fortschritt darin)', g.Results.waitedInAction is True)
lua.execute('NearVehicle = nil')

print('Zonen und Punkte (modules/zones.lua)')
lua.execute("Pos = { x = 0, y = 0, z = 0 }; function Platform.GetOwnPosition() return { x = Pos.x, y = Pos.y, z = Pos.z } end")
load(lua, os.path.join(LIB, 'modules/zones.lua'))
lua.execute('''
Seen = {}
Box = lib.zones.box({ coords = { x = 10, y = 0, z = 0 }, size = { x = 2, y = 8, z = 4 }, rotation = 90,
    onEnter = function() Seen[#Seen + 1] = 'box_in' end, onExit = function() Seen[#Seen + 1] = 'box_out' end })
Poly = lib.zones.poly({ points = { { x = 0, y = 0 }, { x = 4, y = 0 }, { x = 4, y = 4 }, { x = 0, y = 4 } }, minZ = -1, maxZ = 3 })
Point = lib.points.new({ coords = { x = 0, y = 0, z = 0 }, distance = 2, nearby = function() Seen.ticks = (Seen.ticks or 0) + 1 end })
''')
zone = g.Box
check('gedrehter Quader: 3 m entlang x drin (wegen 90 Grad)', zone.contains(zone, lua.table_from({'x': 13, 'y': 0, 'z': 0})) is True)
check('gedrehter Quader: 3 m entlang y draussen', zone.contains(zone, lua.table_from({'x': 10, 'y': 3, 'z': 0})) is False)
check('Vieleck: Punkt innen', g.Poly.contains(g.Poly, lua.table_from({'x': 2, 'y': 2, 'z': 0})) is True)
check('Vieleck: Punkt aussen und zu hoch', g.Poly.contains(g.Poly, lua.table_from({'x': 5, 'y': 2, 'z': 0})) is False and g.Poly.contains(g.Poly, lua.table_from({'x': 2, 'y': 2, 'z': 5})) is False)
lua.globals().Tick(400)
check('im Punkt: nearby laeuft jeden Frame', (g.Seen.ticks or 0) > 10, g.Seen.ticks)
lua.execute('Pos = { x = 13, y = 0, z = 0 }')
lua.globals().Tick(400)
ticks = g.Seen.ticks
lua.globals().Tick(400)
check('Quader betreten, Punkt verlassen: nearby stoppt', g.Seen[1] == 'box_in' and g.Seen.ticks == ticks)
lua.execute('Box:remove()')
check('remove ruft onExit', g.Seen[2] == 'box_out')
check('ungueltige Zone abgelehnt', lua.eval("select(2, lib.zones.sphere({ coords = { x = 0 } }))") == 'invalid_input')

# ----------------------------------------------------------------------
print('Server: Minigames mit Zeitpruefung')
s = lupa.LuaRuntime(unpack_returned_tuples=True)
s.execute(r'''
Calls, Exports, Callbacks, Sent, Characters = {}, {}, {}, {}, { [1] = 17, [2] = 18 }
Now = 0
Platform, Network = {}, {}
function Platform.Print(...) end
function Platform.Async(fn) fn() end
function Platform.Wait() end
function Platform.GetTime() return Now end
function Platform.Export(n, fn) Exports[n] = fn end
function Platform.GetCallingResource() return 'bank' end
function Platform.Notify() end
Intervals = {}
function Platform.SetInterval(ms, fn) Intervals[#Intervals + 1] = fn end
Logs = {}
function Platform.CallExport(res, name, a)
    if name == 'GetCharacterId' then return Characters[a] end
    if name == 'GetAccountId' then return Characters[a] and Characters[a] + 1000 end
    if name == 'Log' then Logs[#Logs + 1] = a end
end
function Network.SendToClient(src, ev, data) Sent[#Sent + 1] = { src = src, ev = ev, data = data } end
function Network.RegisterCallback(n, fn) Callbacks[n] = fn end
''')
load(s, os.path.join(CORE, 'shared/config.lua'))
load(s, os.path.join(LIB, 'config.lua'))
load(s, os.path.join(LIB, 'server/main.lua'))
sg = s.globals()
startm = sg.Exports['StartMinigame']
check('ohne Charakter abgelehnt', startm(3, 'hack')[1] == 'no_character')
check('unbekanntes Minigame abgelehnt', startm(1, 'tetris')[1] == 'invalid_input')
mid = startm(1, 'lockpick', s.table_from({'pins': 4}))
check('an den Spieler geschickt', sg.Sent[1].src == 1 and sg.Sent[1].ev == 'core_lib:minigame' and sg.Sent[1].data.kind == 'lockpick')
check('zweites Minigame fuer denselben Spieler abgelehnt', startm(1, 'hack')[1] == 'busy')
check('laeuft noch: nil', sg.Exports['GetMinigameResult'](mid) is None)
check('fremder Spieler kann nicht antworten', sg.Callbacks['lib_minigame_result'](2, s.table_from({'id': mid, 'success': True})).ok is False)
s.execute('Now = 400')
sg.Callbacks['lib_minigame_result'](1, s.table_from({'id': mid, 'success': True}))
check('zu schnell "geschafft": zaehlt nicht', sg.Exports['GetMinigameResult'](mid) is False)
check('und steht im Log', sg.Logs[1].action == 'minigame_too_fast' and sg.Logs[1].data.resource == 'bank')
mid = startm(1, 'lockpick')
s.execute('Now = 10000')
sg.Callbacks['lib_minigame_result'](1, s.table_from({'id': mid, 'success': True}))
check('nach echter Spielzeit geschafft', sg.Exports['GetMinigameResult'](mid) is True)
check('Ergebnis nur einmal abrufbar', sg.Exports['GetMinigameResult'](mid) is False)
mid = startm(2, 'wires')
s.execute('Characters[2] = nil')
for fn in sg.Intervals.values():
    fn()
check('Spieler weg: nicht geschafft', sg.Exports['GetMinigameResult'](mid) is False)

print(f'{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
