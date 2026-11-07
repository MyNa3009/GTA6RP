"""Test fuer die Bridge-Funktionen rund um das Fahrzeug von aussen (Core 1.9.0) mit nachgebauten FiveM-Natives.

Prueft: Fahrzeug im Blick zu Fuss (Abstand zur Karosserie, nicht hinter der Figur, nicht aus dem Fahrzeug),
Umrandung, Stand von aussen, Tueren von aussen (Schloss, Abstand, Kontrolle) und Einsteigen.
"""
import os
import sys

import lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ok = fail = 0


def check(label, condition, info=None):
    global ok, fail
    if condition:
        ok += 1
        print('  ok   ', label)
    else:
        fail += 1
        print('  FEHLER', label, info if info is not None else '')


lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local V = {}
V.__index = V
function vector3(x, y, z) return setmetatable({ x = x + 0.0, y = y + 0.0, z = z + 0.0 }, V) end
V.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return vector3(a.x * b, a.y * b, a.z * b) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

Calls = {}
local function record(name, ...) Calls[#Calls + 1] = { name = name, args = { ... } } end
PedPos = vector3(0, 0, 1)
InVehicle = 0
CamPos = vector3(0, -3, 2)
CamRot = vector3(0, 0, 0)        -- schaut nach Norden (+y)
Hit = nil                         -- { coords, entity }
Vehicles = { [50] = { pos = vector3(0, 4, 1), lock = 1, plate = ' LS 4821 ', seats = { [-1] = 0, [0] = 0, [1] = 7 }, max = 4, control = true, doors = { [0] = true } } }
Waited = 0

function PlayerPedId() return 1 end
function GetEntityCoords(e) if e == 1 then return PedPos end return Vehicles[e].pos end
function GetVehiclePedIsIn() return InVehicle end
function GetGameplayCamCoord() return CamPos end
function GetGameplayCamRot() return CamRot end
function StartExpensiveSynchronousShapeTestLosProbe(...) record('Ray', ...) return 1 end
function GetShapeTestResult() local h = rawget(_G, 'Hit') if h then return 2, 1, h.coords, vector3(0, 0, 1), h.entity end return 2, 0, vector3(0, 0, 0), vector3(0, 0, 0), 0 end
function IsEntityAVehicle(e) return Vehicles[e] ~= nil end
function DoesEntityExist(e) return e == 1 or Vehicles[e] ~= nil end
function SetEntityDrawOutline(e, on) record('Outline', e, on) end
function SetEntityDrawOutlineColor(r, g, b, a) record('OutlineColor', r, g, b, a) end
function SetEntityDrawOutlineShader(s) record('OutlineShader', s) end
function GetVehicleMaxNumberOfPassengers(v) return Vehicles[v].max end
function IsVehicleSeatFree(v, s) return (Vehicles[v].seats[s] or 0) == 0 end
function GetVehicleNumberPlateText(v) return Vehicles[v].plate end
function GetVehicleDoorLockStatus(v) return Vehicles[v].lock end
function NetworkHasControlOfEntity(v) return Vehicles[v].control end
function NetworkRequestControlOfEntity(v) record('RequestControl', v) if Vehicles[v].grantAfter then Vehicles[v].grantAfter = Vehicles[v].grantAfter - 1 if Vehicles[v].grantAfter <= 0 then Vehicles[v].control = true end end end
function Wait(ms) Waited = Waited + ms end
function GetIsDoorValid(v, i) return Vehicles[v].doors[i] == true end
function IsVehicleDoorDamaged() return false end
function SetVehicleDoorOpen(v, i) record('DoorOpen', v, i) end
function SetVehicleDoorShut(v, i) record('DoorShut', v, i) end
function TaskEnterVehicle(ped, v, timeout, seat, speed, flag) record('Enter', v, seat, flag) end

setmetatable(_G, { __index = function(t, k) if type(k) == 'string' and k:match('^%u') then return function() return 0 end end end })
function CreateThread(fn) end
Citizen = { CreateThread = CreateThread, Wait = Wait }
exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
json = { encode = function() return '' end, decode = function() return {} end }
''')
with open(os.path.join(ROOT, 'core/bridge/platform/fivem_client.lua'), encoding='utf-8') as f:
    lua.eval('function(src) local fn, err = load(src, "@fivem_client.lua") if not fn then error(err) end return fn end')(f.read())()
P = lua.globals().Platform


def calls(name):
    return [[c.args[i] for i in range(1, len(c.args) + 1)] for c in lua.globals().Calls.values() if c.name == name]


print('Fahrzeug im Blick')
check('nichts getroffen: nil', P.GetVehicleInSightOnFoot(3.5) is None)
lua.execute('Hit = { coords = vector3(0, 2.5, 1), entity = 50 }')
seen = P.GetVehicleInSightOnFoot(3.5)
check('Karosserie 2,5 m vor der Figur: gefunden', seen is not None and seen.vehicle == 50 and abs(seen.distance - 2.5) < 0.01, seen and seen.distance)
ray = calls('Ray')[-1]
check('Strahl aus der Kamera bis 3,5 m (+1 m) hinter die Figur, verdeckt durch Karte und Objekte',
      abs(ray[3]) < 0.01 and abs(ray[4] - 4.5) < 0.01 and ray[6] == 19, ray)
lua.execute('Hit = { coords = vector3(0, 4.2, 1), entity = 50 }')
check('Karosserie 4,2 m weg: zu weit', P.GetVehicleInSightOnFoot(3.5) is None)
lua.execute('Hit = { coords = vector3(0, -2.5, 1), entity = 50 }')
check('Fahrzeug zwischen Kamera und Figur (hinter einem): kein Ziel', P.GetVehicleInSightOnFoot(3.5) is None)
lua.execute('Hit = { coords = vector3(0, 2, 1), entity = 99 }')
check('Treffer ist kein Fahrzeug (Wand): nil', P.GetVehicleInSightOnFoot(3.5) is None)
lua.execute('Hit = { coords = vector3(0, 2, 1), entity = 50 }; InVehicle = 50')
check('selbst im Fahrzeug: nil', P.GetVehicleInSightOnFoot(3.5) is None)
lua.execute('InVehicle = 0')

print('Umrandung')
style = lua.table_from({'shader': 0, 'alpha': 255, 'color': lua.table_from({'r': 232, 'g': 64, 'b': 190})})
check('an: true', P.SetEntityOutline(50, True, style) is True)
check('Farbe und Shader gesetzt, Umrandung an', calls('OutlineColor')[-1] == [232, 64, 190, 255] and calls('OutlineShader')[-1] == [0] and calls('Outline')[-1] == [50, True])
P.SetEntityOutline(50, False)
check('aus ohne Stil', calls('Outline')[-1] == [50, False])
check('nicht vorhandenes Fahrzeug: false', P.SetEntityOutline(404, True, style) is False)

print('Stand von aussen')
st = P.GetVehicleOutsideState(50)
seats = [st.freeSeats[i] for i in range(1, len(st.freeSeats) + 1)]
check('Kennzeichen ohne Leerzeichen', st.plate == 'LS 4821', st.plate)
check('offen, 4 m zur Mitte', st.locked is False and abs(st.distance - 4.0) < 0.01, st.distance)
check('freie Sitze (4 Mitfahrer, Sitz 1 belegt)', seats == [-1, 0, 2, 3], seats)
check('kein Fahrzeug: nil', P.GetVehicleOutsideState(404) is None)

print('Tueren von aussen')
check('Fahrertuer auf', P.SetVehicleDoorFromOutside(50, 0, True, 6.0) == (True,) or P.SetVehicleDoorFromOutside(50, 0, True, 6.0) is True)
check('SetVehicleDoorOpen gerufen', calls('DoorOpen')[-1] == [50, 0])
check('Tuer, die es nicht gibt', P.SetVehicleDoorFromOutside(50, 3, True, 6.0) == (False, 'no_door'))
check('zu weit weg', P.SetVehicleDoorFromOutside(50, 0, False, 3.0) == (False, 'too_far'))
lua.execute('Vehicles[50].lock = 2')
check('abgeschlossen', P.SetVehicleDoorFromOutside(50, 0, False, 6.0) == (False, 'locked'))
lua.execute('Vehicles[50].lock = 1; Vehicles[50].control = false; Vehicles[50].grantAfter = 3; Waited = 0')
check('Kontrolle nach kurzem Warten: Tuer zu', P.SetVehicleDoorFromOutside(50, 0, False, 6.0) is True and calls('DoorShut')[-1] == [50, 0])
check('hat dabei gewartet (3 Anfragen, 150 ms)', lua.globals().Waited == 150, lua.globals().Waited)
lua.execute('Vehicles[50].control = false; Vehicles[50].grantAfter = nil; Waited = 0')
check('keine Kontrolle: nach 600 ms aufgeben', P.SetVehicleDoorFromOutside(50, 0, True, 6.0) == (False, 'no_control') and lua.globals().Waited == 600)
lua.execute('Vehicles[50].control = true')

print('Einsteigen')
check('Beifahrersitz', P.EnterVehicleSeat(50, 0, 6.0) is True and calls('Enter')[-1] == [50, 0, 1])
check('belegter Sitz', P.EnterVehicleSeat(50, 1, 6.0) == (False, 'seat_taken'))
check('zu weit', P.EnterVehicleSeat(50, 0, 2.0) == (False, 'too_far'))
lua.execute('Vehicles[50].lock = 2')
check('abgeschlossen', P.EnterVehicleSeat(50, 0, 6.0) == (False, 'locked'))
check('kein Fahrzeug', P.EnterVehicleSeat(404, 0, 6.0) == (False, 'not_found'))

print('Liegende Person im Blick')
lua.execute('''
Hit = nil
PedPos = vector3(0, 0, 1); CamPos = vector3(0, -3, 2); CamRot = vector3(-30, 0, 0)
Other = { pos = vector3(0, 2, 0.1), dead = true, los = false }
function PlayerId() return 0 end
function GetActivePlayers() return { 0, 1 } end
function GetPlayerPed(p) if p == 0 then return 1 end return 77 end
function GetPlayerServerId(p) return p == 1 and 2 or 1 end
function IsEntityVisible() return true end
function IsPedInAnyVehicle() return false end
local baseCoords = GetEntityCoords
function GetEntityCoords(e) if e == 77 then return Other.pos end return baseCoords(e) end
function IsEntityDead(e) return e == 77 and Other.dead end
function IsPedFatallyInjured(e) return e == 77 and Other.dead end
function IsPedRagdoll(e) return false end
function HasEntityClearLosToEntity(a, b) return Other.los end
''')
seen = P.GetPlayerInSight(3.0, 12, True)
check('bewusstlos am Boden, Blick auf den Körper: gefunden', seen is not None and seen.serverId == 2 and seen.down is True, seen)
lua.execute('Other.dead = false; Other.los = true')
check('stehend an derselben Stelle (Ziel auf Brusthöhe): nicht getroffen', P.GetPlayerInSight(3.0, 12, True) is None)
lua.execute('Other.dead = true; Hit = { coords = vector3(0, 0, 1), entity = 0 }; Other.los = false')
check('Wand dazwischen: nicht gefunden', P.GetPlayerInSight(3.0, 12, True) is None)
lua.execute('Hit = nil')

print('Zur Person drehen')
lua.execute('''
Heading = nil
function GetPlayerFromServerId(id) return id == 2 and 1 or -1 end
function SetEntityHeading(e, h) if e == 1 then Heading = h end end
function GetHeadingFromVector_2d(x, y) return (math.deg(math.atan(-x, y)) + 360) % 360 end
PedPos = vector3(0, 0, 1); Other.pos = vector3(2, 0, 0.1)
''')
check('dreht sich zur Person rechts daneben (270 Grad)', P.FacePlayer(2) is True and abs(lua.globals().Heading - 270) < 0.01, lua.globals().Heading)
check('unbekannte Person: false', P.FacePlayer(9) is False)

print('Lokale Ereignisse')
lua.execute('Emitted = nil; function TriggerEvent(...) Emitted = table.pack(...) end')
lua.execute("Platform.Emit('core_lib:select', 'core_ems:i:medkit', { player = { serverId = 2 } })")
em = lua.globals().Emitted
check('Emit gibt alle Werte weiter (Schlüssel und Kontext)', em.n == 3 and em[2] == 'core_ems:i:medkit' and em[3].player.serverId == 2, em and em.n)

print(f'\n{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
