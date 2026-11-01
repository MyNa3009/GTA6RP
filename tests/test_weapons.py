import os
import sys, re; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)
def items(state, key='items'):
    return {e['slot']: e for e in (state.get(key) or [])}
def call(env, src, name, data):
    env.tick(100)
    return env.icall(src, name, data)
def weapon_events(src):
    return env.events_for(src, 'core_inventory:weapon')

env = Env(inventory=True)
for s in (1, 2):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.command(0, f'setrank {fab} chief')
env.call(1, 'char_select', {'id': fab}); env.call(2, 'char_select', {'id': mira}); env.tick(300)
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[2] = [101.0, 100.0, 30.0]

print('Seriennummer')
env.command(1, 'aduty'); env.command(1, f'giveitem {fab} weapon_pistol 2'); env.command(1, f'giveitem {fab} ammo_pistol 100'); env.command(1, f'giveitem {fab} ammo_rifle 10'); env.command(1, 'aduty')
st = call(env, 1, 'inv_open', {})['data']['state']
guns = [e for e in st['items'] if e['name'] == 'weapon_pistol']
serials = [g['meta']['serial'] for g in guns]
check('Zwei Pistolen, zwei Plätze', len(guns) == 2)
check('Jede hat eine eigene Seriennummer im Format SN-XXXX-XXXX', len(set(serials)) == 2 and all(re.match(r'^SN-[A-Z2-9]{4}-[A-Z2-9]{4}$', s) for s in serials), serials)
check('Neue Waffe ist leer', all(g['meta']['ammo'] == 0 for g in guns))

# Pistole in Platz 1 legen, damit Taste 1 sie zieht
gslot = guns[0]['slot']; serial = guns[0]['meta']['serial']
r = call(env, 1, 'inv_move', {'from': {'inv': 'self', 'slot': gslot}, 'to': {'inv': 'self', 'slot': '1'}})
check('Pistole in den Schnellzugriff', r['ok'] and items(r['data']['state'])['1']['name'] == 'weapon_pistol', r.get('error'))

print('Ziehen und Wegstecken')
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': '1'})
st = r['data']['state']
check('Taste 1: Pistole in der Hand', r['ok'] and items(st)['weapon']['meta']['serial'] == serial and '1' not in items(st), r.get('error'))
check('homeSlot bleibt auf dem Server', 'homeSlot' not in items(st)['weapon']['meta'])
ev = weapon_events(1)
check('Client bekommt die Waffe', ev and ev[-1].get('item') == 'weapon_pistol' and ev[-1].get('id') and ev[-1].get('ammo') == 0, ev[-1:] )
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': '1'})
st = r['data']['state']
check('Taste 1 nochmal: zurück in Platz 1', r['ok'] and 'weapon' not in items(st) and items(st)['1']['meta']['serial'] == serial, r.get('error'))
check('Client: Waffe weg', weapon_events(1)[-1] in ({}, [], None) or not weapon_events(1)[-1].get('item'), weapon_events(1)[-1])
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': '1'})

print('Munition')
ammo_slot = [e['slot'] for e in r['data']['state']['items'] if e['name'] == 'ammo_pistol'][0]
rifle_slot = [e['slot'] for e in r['data']['state']['items'] if e['name'] == 'ammo_rifle'][0]
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': rifle_slot})
check('Gewehrmunition passt nicht in die Pistole', r['error'] == 'wrong_ammo')
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': ammo_slot})
st = r['data']['state']
check('100 Schuss geladen, Munition-Item weg', r['ok'] and items(st)['weapon']['meta']['ammo'] == 100 and not any(e['name'] == 'ammo_pistol' for e in st['items']), r.get('error'))
check('Client bekommt neue Munition', weapon_events(1)[-1].get('ammo') == 100)
env.command(1, 'aduty'); env.command(1, f'giveitem {fab} ammo_pistol 200'); env.command(1, 'aduty')
st = call(env, 1, 'inv_open', {})['data']['state']
ammo_slot = [e['slot'] for e in st['items'] if e['name'] == 'ammo_pistol'][0]
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': ammo_slot})
st = r['data']['state']
check('Nur bis 250 geladen, Rest bleibt', items(st)['weapon']['meta']['ammo'] == 250 and items(st)[ammo_slot]['count'] == 50, (items(st)['weapon']['meta'], items(st).get(ammo_slot)))
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': ammo_slot})
check('Volle Waffe', r['error'] == 'weapon_full')

print('Munitionsstand vom Client')
n = len(weapon_events(1))
r = call(env, 1, 'inv_ammo', {'id': ev[-1]['id'], 'ammo': 230})
st = call(env, 1, 'inv_open', {})['data']['state']
check('Schießen: 230 übernommen', r['ok'] and items(st)['weapon']['meta']['ammo'] == 230)
check('Kein unnötiges Zurückschicken', len(weapon_events(1)) == n, weapon_events(1)[n:])
r = call(env, 1, 'inv_ammo', {'id': ev[-1]['id'], 'ammo': 999})
st = call(env, 1, 'inv_open', {})['data']['state']
check('Mehr Munition vom Client wird ignoriert', items(st)['weapon']['meta']['ammo'] == 230)
r = call(env, 1, 'inv_ammo', {'id': 'falsch', 'ammo': 1})
check('Falsche Seriennummer', r['error'] == 'no_weapon')

print('Weitergeben und Speichern')
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': 'weapon'})
st = r['data']['state']
gslot = [e['slot'] for e in st['items'] if (e.get('meta') or {}).get('serial') == serial][0]
check('Wegstecken behält die Munition', items(st)[gslot]['meta']['ammo'] == 230)
r = call(env, 1, 'inv_give', {'from': {'inv': 'self', 'slot': gslot}, 'count': 1, 'target': 2})
st2 = call(env, 2, 'inv_open', {})['data']['state']
g2 = [e for e in st2['items'] if (e.get('meta') or {}).get('serial') == serial]
check('Mira bekommt dieselbe Waffe mit Seriennummer und Munition', r['ok'] and g2 and g2[0]['meta']['serial'] == serial and g2[0]['meta']['ammo'] == 230, g2)
env.command(2, 'relog'); env.tick(200)
import json
data = json.loads(env.sql("SELECT data FROM inventories WHERE id = %s", (f'char:{mira}',))[0]['data'])
check('Seriennummer steht in der Datenbank', any((e.get('meta') or {}).get('serial') == serial for e in data['slots'].values()))
env.flush_log()
acts = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category='item'")]
check('Nachladen steht im Log', 'load_ammo' in acts, set(acts))
print('Legal und illegal')
reg = env.sql('SELECT serial, item, character_id FROM weapon_registry')
check('Legale Waffen stehen im Register mit erstem Besitzer', len(reg) == 2 and all(r['character_id'] == fab for r in reg) and serial in [r['serial'] for r in reg], reg)
check('Register-Abfrage per Export', env.to_py(env.inv.eval(f"Registry.Weapon('{serial}')"))['characterId'] == fab)
env.command(1, 'aduty'); env.command(1, f'giveitem {fab} weapon_smg illegal'); env.command(1, f'giveitem {fab} water illegal'); env.command(1, 'aduty')
st = call(env, 1, 'inv_open', {})['data']['state']
smg = [e for e in st['items'] if e['name'] == 'weapon_smg']
check('Illegale MP ohne Seriennummer', smg and 'serial' not in (smg[0].get('meta') or {}) and smg[0]['meta']['ammo'] == 0, smg)
check('Illegale Waffe nicht im Register', len(env.sql('SELECT serial FROM weapon_registry')) == 2)
check('Nur Waffen können illegal sein', 'Nur Waffen' in [d['text'] for s, n, d in env.events if s == 1 and n == 'core:notify'][-2], [d['text'] for s, n, d in env.events if s == 1 and n == 'core:notify'][-3:])
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': smg[0]['slot']})
ev = weapon_events(1)[-1]
check('Illegale Waffe in die Hand (über interne Kennung)', r['ok'] and ev.get('item') == 'weapon_smg' and ev.get('id'), ev)
r = call(env, 1, 'inv_ammo', {'id': ev['id'], 'ammo': 0})
check('Munitionsabgleich auch ohne Seriennummer', r['ok'])
print(f'\n{ok} ok, {fail} Fehler')
