import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)

env = Env(inventory=True)
for s in (1, 2):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.command(0, f'setrank {fab} chief')
r1 = env.call(1, 'char_select', {'id': fab})
r2 = env.call(2, 'char_select', {'id': mira})
print('Laden')
check('Spawn bringt Hunger und Durst mit', r1['data'].get('needs') == {'hunger': 100, 'thirst': 100}, r1['data'].get('needs'))
get = lambda src: env.to_py(env.lua.eval(f'Needs.Get({src})'))
def db(cid):
    with env.db.cursor() as c:
        c.execute('SELECT hunger, thirst FROM characters WHERE id=%s', (cid,)); return c.fetchone()

print('Abfall')
env.tick(30 * 60 * 1000)  # 30 Minuten
n = get(2)
check('Nach 30 min Hunger etwa 75', abs(n['hunger'] - 75) <= 1, n)
check('Nach 30 min Durst etwa 67', abs(n['thirst'] - 67) <= 1, n)
ups = env.events_for(2, 'core:needs:update')
check('Updates nur bei ganzer Zahl (statt 180 Ticks)', 40 < len(ups) <= 60, len(ups))
row = db(mira)
check('Wird jede Minute gespeichert', abs(float(row['hunger']) - 75) <= 2, row)

print('Pausen')
env.command(1, 'aduty')
before = get(1)
env.tick(10 * 60 * 1000)
check('Im Admin-Dienst kein Abfall', get(1) == before, (before, get(1)))
env.command(1, 'aduty')
env.call(2, 'death_report', {'weapon': 0})
before = get(2)
env.tick(5 * 60 * 1000)
check('Bewusstlos kein Abfall', get(2) == before, (before, get(2)))

print('Wiederbeleben')
env.lua.execute('Core.Players[2].character.needs.hunger = 3; Core.Players[2].character.needs.thirst = 0')
env.lua.execute('Core.Players[2].character.diedAt = os.time() - 999')
r = env.call(2, 'death_respawn')
n = get(2)
check('Krankenhaus setzt mindestens 40', r['ok'] and n == {'hunger': 40, 'thirst': 40}, (r, n))

print('Exports und Items')
n = env.to_py(env.lua.eval('Needs.Add(2, { hunger = 25 })'))
check('AddNeeds +25 Hunger', n['hunger'] == 65 and n['thirst'] == 40, n)
n = env.to_py(env.lua.eval('Needs.Add(2, { thirst = 500 })'))
check('Nie ueber 100', n['thirst'] == 100, n)
n = env.to_py(env.lua.eval('Needs.Set(2, { hunger = -5 })'))
check('Nie unter 0', n['hunger'] == 0, n)
check('Unbekannte Quelle gibt nil', env.lua.eval('Needs.Get(99)') is None)

env.command(1, 'aduty'); env.command(1, f'giveitem {mira} water 1'); env.command(1, f'giveitem {mira} sandwich 1'); env.command(1, 'aduty')
env.lua.execute('Needs.Set(2, { hunger = 10, thirst = 10 })')
inv = env.icall(2, 'inv_open', {})
slots = {e['slot']: e['name'] for e in inv['data']['state']['items']}
wslot = [k for k, v in slots.items() if v == 'water'][0]
sslot = [k for k, v in slots.items() if v == 'sandwich'][0]
env.tick(100); env.icall(2, 'inv_use', {'inv': 'self', 'slot': wslot})
env.tick(100); env.icall(2, 'inv_use', {'inv': 'self', 'slot': sslot})
n = get(2)
check('Wasser +40 Durst, Sandwich +40 Hunger', n == {'hunger': 50, 'thirst': 50}, n)

print('Heal und Ausloggen')
env.command(1, 'aduty'); env.command(1, f'heal {mira}'); env.command(1, 'aduty')
check('/heal fuellt beides auf', get(2) == {'hunger': 100, 'thirst': 100}, get(2))
env.lua.execute('Needs.Set(2, { hunger = 33, thirst = 44 })')
env.call(2, 'char_relog') if False else env.lua.execute('Characters.Unload(Core.Players[2], "Test")')
row = db(mira)
check('Ausloggen speichert sofort', float(row['hunger']) == 33 and float(row['thirst']) == 44, row)
r = env.call(2, 'char_select', {'id': mira})
check('Wieder einloggen laedt die Werte', r['data'].get('needs') == {'hunger': 33, 'thirst': 44}, r['data'].get('needs'))
print(f'{ok} ok, {fail} Fehler')
