import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)
def state(src):
    env.tick(100)
    return env.icall(src, 'inv_open', {})['data']['state']
def cash_slots(src):
    return {e['slot']: e['count'] for e in state(src)['items'] if e['name'] == 'cash'}
money = lambda src: env.to_py(env.lua.eval(f'Core.GetMoney({src}, "cash")'))
def give(src, item, count, target):
    env.tick(100)
    return env.icall(src, 'inv_give_item', {'item': item, 'count': count, 'target': target})

# Geld geben aus dem G-Menue der core_lib: Item ohne Platzangabe (inv_give_item, Export GiveItem im Client)
env = Env(inventory=True, debug=True)
for s in (1, 2):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.sql('UPDATE characters SET cash = 1000 WHERE id = %s', (fab,))
env.sql('UPDATE characters SET cash = 0 WHERE id = %s', (mira,))
env.call(1, 'char_select', {'id': fab}); env.call(2, 'char_select', {'id': mira}); env.tick(300)
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[2] = [101.0, 100.0, 30.0]

print('Bargeld geben ohne Platz')
check('Start: 1000 $ bei Fabian', money(1) == 1000, money(1))
r = give(1, 'cash', 300, 2)
check('300 $ gegeben', r['ok'] and money(1) == 700 and money(2) == 300, (r, money(1), money(2)))
env.flush_log()
row = env.sql("SELECT action, amount FROM audit_log WHERE category='item' AND action='give' ORDER BY id DESC LIMIT 1")
check('steht als Geben im Log', row and row[0]['amount'] == 300, row)
check('Antwort enthaelt den neuen Stand', r['data']['state'] is not None)

print('Fehlerfaelle')
check('mehr als vorhanden', give(1, 'cash', 5000, 2)['error'] == 'not_enough_own')
check('0 $', give(1, 'cash', 0, 2)['error'] == 'invalid_count')
check('Kommazahl', give(1, 'cash', 1.5, 2)['error'] == 'invalid_count')
check('Text statt Zahl', give(1, 'cash', 'viel', 2)['error'] == 'invalid_count')
check('unbekanntes Item', give(1, 'goldbarren_xyz', 1, 2)['error'] == 'invalid_count')
check('Dokument geht nicht (zeigt man nur)', give(1, 'id_card', 1, 2)['error'] == 'invalid_count')
check('an sich selbst', give(1, 'cash', 10, 1)['error'] == 'target_offline')
check('an niemanden', give(1, 'cash', 10, 77)['error'] == 'target_offline')
env.positions[2] = [130.0, 100.0, 30.0]
check('zu weit weg', give(1, 'cash', 10, 2)['error'] == 'too_far')
env.positions[2] = [101.0, 100.0, 30.0]
check('nach den Fehlern unveraendert', money(1) == 700 and money(2) == 300, (money(1), money(2)))

print('Auf zwei Plaetze verteilt')
slots = cash_slots(1)
src_slot = list(slots)[0]
used = {e['slot'] for e in state(1)['items']}
free_slot = [str(i) for i in range(1, 11) if str(i) not in used][0]
env.tick(100)
env.icall(1, 'inv_move', {'from': {'inv': 'self', 'slot': src_slot}, 'to': {'inv': 'self', 'slot': free_slot}, 'count': 300})
check('jetzt 400 und 300 auf zwei Plaetzen', sorted(cash_slots(1).values()) == [300, 400], cash_slots(1))
check('600 $ liegen nicht auf einem Platz', give(1, 'cash', 600, 2)['error'] == 'split_stacks')
r = give(1, 'cash', 350, 2)
check('350 $ vom groesseren Stapel', r['ok'] and money(1) == 350 and money(2) == 650, (money(1), money(2)))
print(f'\n{ok} ok, {fail} Fehler')
