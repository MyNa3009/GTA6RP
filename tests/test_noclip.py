"""Test fuer den Noclip der Bridge (freie Kamera wie bei txAdmin) mit nachgebauten FiveM-Natives.

Prueft Richtung (W fliegt dahin, wohin die Kamera schaut), Q und E, Shift und Alt, Maus,
Nachziehen des Peds alle 100 Frames, Teleport im Noclip, Abschalten (Ped an der Kamera, sichtbar, Fallschutz).
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
-- vector3 wie in FiveM
local V = {}
V.__index = V
function vector3(x, y, z) return setmetatable({ x = x + 0.0, y = y + 0.0, z = z + 0.0 }, V) end
V.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
    if type(a) == 'number' then a, b = b, a end
    return vector3(a.x * b, a.y * b, a.z * b)
end
V.__unm = function(a) return vector3(-a.x, -a.y, -a.z) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

-- Spielzustand
Controls = {}             -- [control] = Wert 0..1
PedPos = vector3(100, 200, 30)
PedHeading = 0
Visible, Invincible, Frozen = true, false, false
CamRot = vector3(0, 0, 0)  -- Gameplay-Kamera beim Einschalten
FrameTime = 1 / 60
Calls = {}
local function record(name, ...) Calls[#Calls + 1] = { name = name, args = { ... } } end

function GetDisabledControlNormal(group, control) return Controls[control] or 0.0 end
function IsUsingKeyboard() return true end
function GetFrameTime() return FrameTime end
function IsPauseMenuActive() return false end
function PlayerPedId() return 1 end
function PlayerId() return 0 end
function GetEntityCoords(e) return vector3(PedPos.x, PedPos.y, PedPos.z) end
function SetEntityCoords(e, x, y, z) if e == 1 then PedPos = vector3(x, y, z) end record('SetEntityCoords', e, x, y, z) end
function SetEntityHeading(e, h) if e == 1 then PedHeading = h end end
function SetEntityVisible(e, v) if e == 1 then Visible = v end end
function SetEntityInvincible(e, v) if e == 1 then Invincible = v end end
function FreezeEntityPosition(e, v) if e == 1 then Frozen = v end end
function GetVehiclePedIsIn() return 0 end
function GetGameplayCamCoord() return vector3(PedPos.x, PedPos.y - 3, PedPos.z + 1) end
function GetGameplayCamRot() return CamRot end
CamPos = nil
function CreateCam() record('CreateCam') return 7 end
function SetCamCoord(c, x, y, z) CamPos = vector3(x, y, z) end
function SetCamRot(c, x, y, z) CamRotNow = vector3(x, y, z) end
function RenderScriptCams(on) record('RenderScriptCams', on) end
function DestroyCam() record('DestroyCam') end
function GetEntityHeightAboveGround() return HeightAboveGround or 0.5 end
function ApplyForceToEntity(...) record('ApplyForce', ...) end
function SetPlayerFallDistance(p, d) record('FallDistance', d) end
function IsPedFalling() return false end
function RequestScaleformMovie() return 5 end
function HasScaleformMovieLoaded() return true end
function GetControlInstructionalButton(g, c) return '~INPUT_' .. c .. '~' end

-- alles andere: tut nichts
setmetatable(_G, { __index = function(t, k)
    if type(k) == 'string' and k:match('^%u') then return function() return 0 end end
end })

-- Threads mit virtuellen Frames
local threads = {}
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait() coroutine.yield() end
function Frames(n)
    for _ = 1, n do
        for i = #threads, 1, -1 do
            local co = threads[i]
            local okay, err = coroutine.resume(co)
            if not okay then error(err) end
            if coroutine.status(co) == 'dead' then table.remove(threads, i) end
        end
    end
end
Citizen = { CreateThread = CreateThread, Wait = Wait }
exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
json = { encode = function() return '' end, decode = function() return {} end }
''')

with open(os.path.join(ROOT, 'core/bridge/platform/fivem_client.lua'), encoding='utf-8') as f:
    lua.eval('function(src) local fn, err = load(src, "@fivem_client.lua") if not fn then error(err) end return fn end')(f.read())()

g = lua.globals()
settings = lua.table_from({'BaseSpeed': 0.85, 'FastMultiplier': 6, 'SlowMultiplier': 6, 'LookSensitivity': 5,
                           'GamepadLookSensitivity': 2, 'Fov': 50.0, 'Easing': True, 'EasingMs': 250, 'ShowKeys': True})
labels = lua.table_from({'slower': 'Langsamer', 'faster': 'Schneller', 'down': 'Runter', 'up': 'Hoch',
                         'leftRight': 'Links/Rechts', 'forwardBack': 'Vor/Zurück'})
pos = lambda v: (round(v.x, 2), round(v.y, 2), round(v.z, 2))

print('Einschalten')
g.Platform.SetNoclip(True, settings, labels)
g.Frames(1)
check('unsichtbar, unverwundbar, eingefroren', g.Visible is False and g.Invincible is True and g.Frozen is True)
check('Kamera startet am Ped', pos(g.CamPos) == (100, 200, 30), pos(g.CamPos))
check('Noclip aktiv', g.Platform.IsNoclipActive() is True)

print('Fliegen')
lua.execute('Controls[31] = -1.0')            # W
g.Frames(60)
check('W eine Sekunde: 51 m nach Norden (0.85 x 60)', abs(g.CamPos.y - 251.0) < 0.2 and abs(g.CamPos.x - 100) < 0.01, pos(g.CamPos))
check('Ped steht noch am Start (wird nur alle 100 Frames nachgezogen)', pos(g.PedPos) == (100, 200, 30), pos(g.PedPos))
g.Frames(45)
check('nach 100 Frames: Ped zur Kamera gezogen (Stand von Frame 101)', abs(g.PedPos.y - (200 + 0.85 * 100)) < 0.2, (pos(g.PedPos), pos(g.CamPos)))
lua.execute('Controls[31] = 0; Controls[152] = 1.0')   # Q
start_z = g.CamPos.z
g.Frames(60)
check('Q: hoch', abs(g.CamPos.z - start_z - 51.0) < 0.2, g.CamPos.z - start_z)
lua.execute('Controls[152] = 0; Controls[153] = 1.0')  # E
g.Frames(60)
check('E: wieder runter', abs(g.CamPos.z - start_z) < 0.2)
lua.execute('Controls[153] = 0; Controls[31] = -1.0; Controls[21] = 1.0')  # W + Shift
y0 = g.CamPos.y
g.Frames(60)
check('Shift: 6x schneller (306 m/s)', abs(g.CamPos.y - y0 - 306.0) < 0.5, g.CamPos.y - y0)
lua.execute('Controls[21] = 0; Controls[19] = 1.0')   # W + Alt
y0 = g.CamPos.y
g.Frames(60)
check('Alt: 6x langsamer (8,5 m/s)', abs(g.CamPos.y - y0 - 8.5) < 0.1, g.CamPos.y - y0)
lua.execute('Controls[19] = 0; Controls[31] = 0; Controls[2] = -1.0')  # Maus nach oben
g.Frames(10)
check('Maus hoch: Kamera neigt nach oben, hoechstens 90 Grad', abs(g.CamRotNow.x - 50.0) < 0.01, g.CamRotNow.x)
g.Frames(20)
check('Neigung bleibt bei 90 Grad stehen', abs(g.CamRotNow.x - 90.0) < 0.01, g.CamRotNow.x)
lua.execute('Controls[2] = 0; Controls[31] = -1.0')
z0 = g.CamPos.z
g.Frames(60)
check('W bei Blick nach oben: fliegt senkrecht hoch', abs(g.CamPos.z - z0 - 51.0) < 0.2, g.CamPos.z - z0)
lua.execute('Controls[31] = 0; Controls[2] = 1.0')
g.Frames(18)
lua.execute('Controls[2] = 0')
before = pos(g.CamPos)
g.Frames(120)
check('ohne Tasten bleibt die Kamera genau stehen (kein Abdriften)', pos(g.CamPos) == before, (before, pos(g.CamPos)))

print('Teleport im Noclip')
lua.execute('PedPos = vector3(-500, 800, 40)')
g.Frames(2)
check('Kamera springt mit, wenn ein Script den Ped versetzt', pos(g.CamPos) == (-500, 800, 40), pos(g.CamPos))

print('Ausschalten aus der Luft')
lua.execute('Controls[152] = 1.0')
g.Frames(30)
lua.execute('Controls[152] = 0; HeightAboveGround = 25; Calls = {}')
cam = pos(g.CamPos)
g.Platform.SetNoclip(False, lua.table_from({'protectFall': True}))
check('Ped sofort an der Kamera, nicht erst im naechsten Frame', pos(g.PedPos) == cam, (pos(g.PedPos), cam))
check('sichtbar und beweglich', g.Visible is True and g.Frozen is False)
check('Kamera weg', any(c.name == 'DestroyCam' for c in g.Calls.values()))
g.Frames(3)
forces = [c for c in g.Calls.values() if c.name == 'ApplyForce']
check('Fallschutz: Kraft nach unten wie bei txAdmin (1,64 x Hoehe + 3,57)', forces and abs(-forces[0].args[5] - (1.6428571428571428 * 25 + 3.5714285714285836)) < 0.01, forces and forces[0].args[5])
check('Noclip aus', g.Platform.IsNoclipActive() is False)

print('Stilles Ausschalten (A-Jail, Beobachten)')
g.Platform.SetNoclip(True, settings, labels)
g.Frames(2)
lua.execute('Calls = {}')
g.Platform.SetNoclip(False, lua.table_from({'protectFall': False}))
lua.execute('PedPos = vector3(1690, 2600, 45)')     # Teleport ins A-Jail direkt danach
g.Frames(150)
check('Teleport danach bleibt bestehen', pos(g.PedPos) == (1690, 2600, 45), pos(g.PedPos))
check('kein Fallschutz', not [c for c in g.Calls.values() if c.name == 'ApplyForce'])

print(f'\n{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
