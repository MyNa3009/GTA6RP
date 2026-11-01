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
def free(state):
    used = {e['slot'] for e in state['items']}
    return [str(i) for i in range(6, 11) if str(i) not in used][0]
def mv(env, src, f, t, count=None, fi='self', ti='self'):
    d = {'from': {'inv': fi, 'slot': f}, 'to': {'inv': ti, 'slot': t}}
    if count is not None: d['count'] = count
    env.tick(100)  # kein Mensch zieht schneller als 10 Mal pro Sekunde
    return env.icall(src, 'inv_move', d)

env = Env(inventory=True)
for s in (1, 2):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.command(0, f'setrank {fab} chief')

print('Laden und Startitems')
r = env.icall(1, 'inv_open', {})
check('Ohne Charakter kein Inventar', r['error'] == 'no_character')
env.call(1, 'char_select', {'id': fab}); env.call(2, 'char_select', {'id': mira})
env.tick(200)
r = env.icall(1, 'inv_open', {})
st = r['data']['state']
pockets = {k: v for k, v in slots(st).items() if k.isdigit() and v[0] != 'cash'}
check('Startitems: 2 Wasser, 2 Brot in Platz 1 und 2', pockets == {'1': ('water', 2), '2': ('bread', 2)}, slots(st))
check('Gewicht 1,5 kg von 15 kg', st['weight'] == 1500 and st['maxWeight'] == 15000)
check('Layout: 10 Plätze, 5 Schnellzugriff, Rucksack bis 25, 12 Ausrüstung', r['data']['layout']['slots'] == 10 and r['data']['layout']['hotbar'] == 5 and r['data']['layout']['bagSlots'] == 25 and len(r['data']['layout']['equip']) == 12)
check('Gespeichert', env.sql("SELECT COUNT(*) n FROM inventories WHERE id = %s", (f'char:{fab}',))[0]['n'] == 1)

print('Admin-Befehle')
env.command(1, f'giveitem {mira} water 12')
check('Ohne Dienst nicht', 'Admin-Dienst' in last(env, 1))
env.command(1, 'aduty')
env.command(1, f'giveitem {mira} water 12')
st = env.icall(2, 'inv_open', {})['data']['state']
check('/giveitem stapelt: 10 + 4 Wasser', slots(st)['1'] == ('water', 10) and sorted(c for n, c in slots(st).values() if n == 'water') == [4, 10], slots(st))
check('Spieler bekommt Bescheid', '12x Wasser' in last(env, 2))
env.command(1, f'giveitem {mira} laserschwert')
check('Unbekanntes Item', 'gibt es nicht' in last(env, 1))
env.command(1, 'giveitem 9999 water')
check('Unbekannter Charakter', 'Diesen Charakter gibt es nicht' in last(env, 1))
env.command(1, f'removeitem {mira} water 5')
st = env.icall(2, 'inv_open', {})['data']['state']
check('/removeitem nimmt 5 Wasser', sum(c for n, c in slots(st).values() if n == 'water') == 9)
env.command(1, f'removeitem {mira} bread 99')
check('Zu wenig zum Abnehmen', 'So viele' in last(env, 1))
env.command(2, f'giveitem {mira} water')
check('Spieler ohne Recht', 'keine Rechte' in last(env, 2))

print('Verschieben')
st = env.icall(1, 'inv_open', {})['data']['state']
r = mv(env, 1, '1', '7')
check('Wasser in Platz 7', r['ok'] and slots(r['data']['state'])['7'] == ('water', 2))
r = mv(env, 1, '7', '8', 1)
check('Teilen: 1 bleibt, 1 nach Platz 8', slots(r['data']['state'])['7'] == ('water', 1) and slots(r['data']['state'])['8'] == ('water', 1))
r = mv(env, 1, '8', '7')
check('Zusammenlegen', slots(r['data']['state'])['7'] == ('water', 2) and '8' not in slots(r['data']['state']))
r = mv(env, 1, '7', '2')
check('Tauschen mit Brot', slots(r['data']['state'])['2'] == ('water', 2) and slots(r['data']['state'])['7'] == ('bread', 2))
r = mv(env, 1, '2', '11')
check('Platz 11 gibt es nicht (nur eine Reihe Taschen)', r['error'] == 'invalid_slot')
r = mv(env, 1, '2', 'jacket')
check('Wasser nicht in den Jacken-Platz', r['error'] == 'wrong_slot')
r = mv(env, 1, '2', '7', 5)
check('Mehr als vorhanden', r['error'] == 'invalid_count')

print('Kleidung')
env.command(1, f'giveitem {fab} hat_beanie')
env.command(1, f'giveitem {fab} shoes_sneaker')
st = env.icall(1, 'inv_open', {})['data']['state']
jacket = [k for k, v in slots(st).items() if v[0] == 'hat_beanie'][0]
w_before = st['weight']
r = mv(env, 1, jacket, 'hat')
check('Kopfbedeckung anziehen', r['ok'] and slots(r['data']['state'])['hat'] == ('hat_beanie', 1))
check('Getragen zählt nicht zum Gewicht', r['data']['state']['weight'] == w_before - 120, (w_before, r['data']['state']['weight']))
shoes = [k for k, v in slots(r['data']['state']).items() if v[0] == 'shoes_sneaker'][0]
r = mv(env, 1, shoes, 'hat')
check('Schuhe nicht in den Jacken-Platz', r['error'] == 'wrong_slot')
to = free(r['data']['state'])
r = mv(env, 1, 'hat', to)
check('Kopfbedeckung ausziehen', r['ok'] and slots(r['data']['state'])[to] == ('hat_beanie', 1))

print('Rucksack')
env.command(1, f'giveitem {fab} backpack_1')
st = env.icall(1, 'inv_open', {})['data']['state']
bp = [k for k, v in slots(st).items() if v[0] == 'backpack_1'][0]
r = mv(env, 1, bp, 'backpack')
check('Level 1: 5 Plätze, 10 kg', r['ok'] and r['data']['state']['bagSlots'] == 5 and r['data']['state']['bagMaxWeight'] == 10000 and r['data']['state']['bagLevel'] == 1, r['data']['state'])
r = mv(env, 1, '2', '6', None, 'self', 'bag')
check('Level 1: Platz 6 im Rucksack gesperrt', r['error'] == 'invalid_slot', r)
r = mv(env, 1, 'backpack', free(r['data']['state']))
check('Level 1 wieder ablegen', r['ok'] and r['data']['state'].get('bag') is None)
env.command(1, f'removeitem {fab} backpack_1')
env.command(1, f'giveitem {fab} backpack_4')
st = env.icall(1, 'inv_open', {})['data']['state']
bp = [k for k, v in slots(st).items() if v[0] == 'backpack_4'][0]
r = mv(env, 1, '2', '1', None, 'self', 'bag')
check('Ohne Rucksack kein Rucksack-Inhalt', r['error'] == 'no_bag')
r = mv(env, 1, bp, 'backpack')
check('Level 4 anlegen: 25 Plätze (zwei Reihen mehr als Level 3), 30 kg', r['ok'] and r['data']['state'].get('bag') is not None and r['data']['state']['bagMaxWeight'] == 30000 and r['data']['state']['bagSlots'] == 25, r)
r = mv(env, 1, '2', '1', None, 'self', 'bag')
check('Wasser in den Rucksack', r['ok'] and slots(r['data']['state'], 'bag')['1'] == ('water', 2))
check('Gewicht verteilt sich', r['data']['state']['bagWeight'] == 1000)
r = mv(env, 1, 'backpack', '2', None, 'self', 'bag')
check('Rucksack nicht in sich selbst', r['error'] == 'bag_in_bag')
to = free(r['data']['state'])
r = mv(env, 1, 'backpack', to)
st = r['data']['state']
check('Rucksack ablegen: Inhalt reist mit, wiegt mit', r['ok'] and st.get('bag') is None and slots(st)[to] == ('backpack_4', 1) and st['weight'] >= 1200 + 1000, st['weight'])
r = mv(env, 1, to, 'backpack')
check('Wieder anlegen: Wasser ist noch drin', slots(r['data']['state'], 'bag').get('1') == ('water', 2))

print('Gewicht')
env.command(1, f'giveitem {fab} water 100')
check('100 Wasser (50 kg) passen nicht', 'zu schwer' in last(env, 1) or 'kein Platz' in last(env, 1), last(env, 1))
st = env.icall(1, 'inv_open', {})['data']['state']
check('Alles oder nichts: nichts dazu', sum(c for n, c in slots(st).values() if n == 'water') == 0 and slots(st, 'bag')['1'] == ('water', 2), slots(st))
env.command(1, f'giveitem {fab} water 60')
st = env.icall(1, 'inv_open', {})['data']['state']
check('60 Wasser: Taschen bis 15 kg, Rest in den Rucksack', st['weight'] <= 15000 and st['bagWeight'] <= 30000 and sum(c for n, c in slots(st).values() if n == 'water') + sum(c for n, c in slots(st, 'bag').values() if n == 'water') == 62, (st['weight'], st['bagWeight']))

print('Alte Inventare (30 Plätze, ein Rucksack)')
jonas_acc = 3
env.connect(3, ['license:3']); env.call(3, 'auth_register', {'email': '3@t.de', 'password': 'passwort123'})
jonas = env.call(3, 'char_create', {'firstname': 'Jonas', 'lastname': 'Lehmkuhl', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
old = {str(i): {'name': 'lockpick', 'count': 1} for i in range(1, 31)}
old.update({f'x{i}': {'name': 'lockpick', 'count': 1} for i in range(1, 6)})
old['backpack'] = {'name': 'backpack', 'count': 1, 'meta': {'bagId': 'alt1'}}
env.sql("INSERT INTO inventories (id, data) VALUES (%s, %s)", (f'char:{jonas}', json.dumps({'slots': old})))
env.sql("INSERT INTO inventories (id, data) VALUES (%s, %s)", ('bag:alt1', json.dumps({'slots': {'1': {'name': 'bread', 'count': 1}}})))
env.positions[3] = [200.0, 200.0, 30.0]
env.call(3, 'char_select', {'id': jonas}); env.tick(200)
st = env.icall(3, 'inv_open', {})['data']['state']
check('Alter Rucksack wird Level 4', slots(st).get('backpack') == ('backpack_4', 1) and st['bagLevel'] == 4, slots(st).get('backpack'))
pocket = [k for k in slots(st) if k.isdigit()]
check('Taschen haben nur noch Plätze 1 bis 10', sorted(int(k) for k in pocket) == list(range(1, 11)), pocket)
check('Rest in den Rucksack (alter Inhalt bleibt)', len(slots(st, 'bag')) == 25 and slots(st, 'bag')['1'] == ('bread', 1), len(slots(st, 'bag')))
env.tick(6000)
drops = env.to_py(env.inv.eval('Drops.List(0)'))
check('Was nicht passt (1 Dietrich), liegt als Beutel daneben', len(drops) == 1, drops)
env.flush_log()
acts = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category='item' AND character_id=%s", (jonas,))]
check('Steht im Log', 'relocate_drop' in acts, acts)

print('Offline, Speichern, Neustart')
env.command(2, 'relog'); env.tick(200)
check('Ausloggen speichert und entlädt', env.inv.eval(f"Inventory.Cached('char:{mira}')") is None)
env.command(1, f'giveitem {mira} sandwich 3')
check('/giveitem geht offline', 'an ID' in last(env, 1))
data = json.loads(env.sql("SELECT data FROM inventories WHERE id = %s", (f'char:{mira}',))[0]['data'])
check('Offline direkt in der Datenbank', any(e['name'] == 'sandwich' and e['count'] == 3 for e in data['slots'].values()))
env.tick(6000)
rows = env.sql("SELECT data FROM inventories WHERE id = %s", (f'char:{fab}',))
check('Fabians Inventar regelmäßig gespeichert', 'shoes_sneaker' in rows[0]['data'])
env.flush_log()
acts = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category='item'")]
check('Im Log: Startitems, Geben, Abnehmen', 'start_items' in acts and 'admin_give' in acts and 'admin_remove' in acts, set(acts))
r = env.call(1, 'admin_overview', {})
titles = [g['title'] for g in r['data']['commands']]
check('Befehlsliste zeigt Gruppe Inventar', 'Inventar' in titles, titles)
print(f'\n{ok} ok, {fail} Fehler')
