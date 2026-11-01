import os
import sys, json; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)
def last(env, src):
    n = [d['text'] for s, n, d in env.events if s == src and n == 'core:notify']
    return n[-1] if n else ''
def slots(state, key='items'):
    return {e['slot']: (e['name'], e['count']) for e in (state.get(key) or [])}
def call(env, src, name, data):
    env.tick(100)
    return env.icall(src, name, data)

env = Env(inventory=True)
for s in (1, 2, 3):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
jonas = env.call(3, 'char_create', {'firstname': 'Jonas', 'lastname': 'Lehmkuhl', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
fab2 = env.call(1, 'char_create', {'firstname': 'Twink', 'lastname': 'Fabian', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
env.command(0, f'setrank {fab} chief')
for s, c in ((1, fab), (2, mira), (3, jonas)): env.call(s, 'char_select', {'id': c})
env.tick(300)
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[2] = [101.5, 100.0, 30.0]; env.positions[3] = [140.0, 100.0, 30.0]
check('Beim Einloggen: Liste der Haufen', any(n == 'core_inventory:drops' for s, n, d in env.events if s == 1))

print('Benutzen')
env.command(1, 'aduty'); env.command(1, f'giveitem {fab} bandage 2'); env.command(1, f'giveitem {fab} jacket_bomber')
st = call(env, 1, 'inv_open', {})['data']['state']
b = [k for k, v in slots(st).items() if v[0] == 'bandage'][0]
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': b})
eff = env.events_for(1, 'core_inventory:effect')
check('Verband: einer weniger, Gesundheit +25, Meldung', r['ok'] and slots(r['data']['state'])[b] == ('bandage', 1) and eff and eff[-1]['health'] == 25 and 'Verband' in last(env, 1), (r, eff))
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': '1'})
check('Wasser trinken', r['ok'] and slots(r['data']['state'])['1'] == ('water', 1))
j = [k for k, v in slots(r['data']['state']).items() if v[0] == 'jacket_bomber'][0]
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': j})
check('Jacke benutzen = anziehen', r['ok'] and slots(r['data']['state']).get('jacket') == ('jacket_bomber', 1))
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': 'jacket'})
check('Angezogene Jacke benutzen = ausziehen', r['ok'] and 'jacket' not in slots(r['data']['state']))
r = call(env, 1, 'inv_use', {'inv': 'self', 'slot': '9'})
check('Leerer Platz', r['error'] == 'empty_slot')

print('Geben')
r = call(env, 1, 'inv_give', {'from': {'inv': 'self', 'slot': '2'}, 'count': 1, 'target': 3})
check('Zu weit weg (40 m)', r['error'] == 'too_far')
r = call(env, 1, 'inv_give', {'from': {'inv': 'self', 'slot': '2'}, 'count': 1, 'target': 2})
st2 = call(env, 2, 'inv_open', {})['data']['state']
check('1 Brot an Mira', r['ok'] and slots(r['data']['state'])['2'] == ('bread', 1) and slots(st2)['2'] == ('bread', 3), (slots(r['data']['state']), slots(st2)))
check('Beide bekommen eine Meldung', 'ID 2' in last(env, 1) and f'ID {fab} hat dir 1x Brot' in last(env, 2), (last(env, 1), last(env, 2)))
r = call(env, 1, 'inv_give', {'from': {'inv': 'self', 'slot': '2'}, 'count': 5, 'target': 2})
check('Mehr als vorhanden', r['error'] == 'invalid_count')
r = call(env, 1, 'inv_give', {'from': {'inv': 'self', 'slot': 'jacket'}, 'target': 2})
check('Aus der Ausrüstung nicht direkt', r['error'] in ('invalid_slot', 'empty_slot'))
env.buckets[2] = 5
r = call(env, 1, 'inv_give', {'from': {'inv': 'self', 'slot': '2'}, 'count': 1, 'target': 2})
check('Andere Dimension zählt als zu weit', r['error'] == 'too_far')
env.buckets[2] = 0
env.command(1, f'giveitem {mira} water 26')
r = call(env, 1, 'inv_give', {'from': {'inv': 'self', 'slot': '1'}, 'count': 1, 'target': 2})
check('Mira kann nicht mehr tragen', r['error'] in ('target_too_heavy', 'target_full') and slots(r['data']['state'])['1'] == ('water', 1), r.get('error'))

print('Boden')
r = call(env, 1, 'inv_move', {'from': {'inv': 'self', 'slot': '2'}, 'to': {'inv': 'drop'}})
d = r['data'].get('drop')
check('Brot auf den Boden: neuer Haufen', r['ok'] and d and slots({'items': d['items']}) == {'1': ('bread', 1)} and '2' not in slots(r['data']['state']), r)
check('Alle in der Nähe sehen den Haufen', any(n == 'core_inventory:drops' and len(dd) == 1 for s, n, dd in env.events if s == 3))
r = call(env, 1, 'inv_move', {'from': {'inv': 'self', 'slot': '1'}, 'to': {'inv': 'drop'}})
check('Zweites Ablegen kommt auf denselben Haufen', r['ok'] and len(r['data']['drop']['items']) == 2)
r = call(env, 3, 'inv_open', {})
check('Jonas (40 m weg) sieht den Haufen im Inventar nicht', r['ok'] and not r['data'].get('drop'))
r = call(env, 3, 'inv_move', {'from': {'inv': 'drop', 'id': d['id'], 'slot': '1'}, 'to': {'inv': 'self', 'slot': '9'}})
check('Jonas kann nicht aus der Ferne aufheben', r['error'] == 'drop_gone')
r = call(env, 2, 'inv_open', {})
check('Mira (1,5 m) sieht ihn', r['data'].get('drop') and r['data']['drop']['id'] == d['id'])
r = call(env, 2, 'inv_move', {'from': {'inv': 'drop', 'id': d['id'], 'slot': '1'}, 'to': {'inv': 'self', 'slot': '10'}})
check('Mira hebt das Brot auf', r['ok'] and slots(r['data']['state'])['10'] == ('bread', 1))
r = call(env, 2, 'inv_move', {'from': {'inv': 'drop', 'id': d['id'], 'slot': '2'}, 'to': {'inv': 'self', 'slot': '9'}})
check('Wasser passt Mira nicht mehr (zu schwer)', r['error'] == 'too_heavy')
r = call(env, 1, 'inv_move', {'from': {'inv': 'drop', 'id': d['id'], 'slot': '2'}, 'to': {'inv': 'self', 'slot': '1'}})
check('Fabian hebt sein Wasser auf, Haufen ist weg', r['ok'] and not r['data'].get('drop'))
check('Leerer Haufen verschwindet für alle', [dd for s, n, dd in env.events if s == 3 and n == 'core_inventory:drops'][-1] in ([], {}))

print('Ablauf nach 30 Minuten')
r = call(env, 1, 'inv_move', {'from': {'inv': 'self', 'slot': '1'}, 'to': {'inv': 'drop'}})
env.tick(31 * 60 * 1000)
r = call(env, 1, 'inv_open', {})
check('Nach 30 Minuten ist der Haufen weg', not r['data'].get('drop'))

print('Twinks')
env.command(1, 'aduty')
env.command(1, 'relog'); env.call(1, 'auth_login', {'email': '1@t.de', 'password': 'passwort123'}); env.call(1, 'char_select', {'id': fab2}); env.tick(300)
env.positions[1] = [101.0, 100.0, 30.0]
r = call(env, 2, 'inv_give', {'from': {'inv': 'self', 'slot': '10'}, 'count': 1, 'target': 1})
check('Fremder Charakter: normal geben', r['ok'])

print('Log und Akte')
env.flush_log()
acts = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category='item'")]
check('Im Log: benutzen, geben, ablegen, aufheben, abgelaufen', all(a in acts for a in ('use', 'give', 'drop', 'pickup', 'drop_expired')), set(acts))
env.command(1, 'relog'); env.call(1, 'auth_login', {'email': '1@t.de', 'password': 'passwort123'}); env.call(1, 'char_select', {'id': fab}); env.tick(300)
r = env.call(1, 'admin_profile', {'characterId': mira})
check('Akte weiß, dass es ein Inventar gibt', r['ok'] and r['data']['inventory'] is True)
r = env.call(1, 'admin_inventory', {'characterId': mira})
check('Inventar in der Akte', r['ok'] and r['data']['items']['water']['label'] == 'Wasser' and len(r['data']['state']['items']) > 0, r.get('error'))
r = env.call(1, 'admin_inventory', {'characterId': 9999})
check('Unbekannter Charakter', r['error'] == 'character_not_found')
r = env.call(3, 'admin_inventory', {'characterId': mira})
check('Spieler darf nicht', r['error'] == 'no_permission')
print(f'\n{ok} ok, {fail} Fehler')
