import os
import sys, json; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)
def last(src):
    n = [d['text'] for s, n, d in env.events if s == src and n == 'core:notify']
    return n[-1] if n else ''
def cash_items(src):
    env.tick(100)
    st = env.icall(src, 'inv_open', {})['data']['state']
    return sum(e['count'] for e in st['items'] + (st.get('bag') or []) if e['name'] == 'cash')
money = lambda src: env.to_py(env.lua.eval(f'Core.GetMoney({src}, "cash")'))
col = lambda cid: env.sql('SELECT cash FROM characters WHERE id=%s', (cid,))[0]['cash']

env = Env(inventory=True, debug=True)
for s in (1, 2):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.command(0, f'setrank {fab} chief')
env.sql('UPDATE characters SET cash = 1240 WHERE id = %s', (mira,))
start = env.sql('SELECT cash FROM characters WHERE id=%s', (fab,))[0]['cash']

print('Umzug aus der alten Spalte')
r1 = env.call(1, 'char_select', {'id': fab}); r2 = env.call(2, 'char_select', {'id': mira}); env.tick(300)
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[2] = [101.0, 100.0, 30.0]
check('1240 $ liegen jetzt als Item im Inventar', cash_items(2) == 1240, cash_items(2))
check('Alte Spalte ist leer', col(mira) == 0, col(mira))
check('Core kennt den Betrag (GetMoney)', money(2) == 1240, money(2))
ups = env.events_for(2, 'core:money:update')
check('Geldanzeige bekommt 1240 $', ups and ups[-1]['cash'] == 1240, ups[-1:])
env.flush_log()
check('Umzug steht im Log', 'cash_migrated' in [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category='item'")])

print('Buchungen der Core')
env.command(1, 'aduty')
env.command(1, f'givemoney cash {fab} 500')
check('/givemoney cash legt Item dazu', cash_items(1) == start + 500 and money(1) == start + 500, (start, cash_items(1), money(1)))
n = len(env.events_for(1, 'core:money:update'))
env.command(1, f'givemoney cash {fab} 250')
ups = env.events_for(1, 'core:money:update')[n:]
check('Anzeige genau einmal mit +250', len(ups) == 1 and ups[0]['changed']['amount'] == 250, ups)
env.command(1, f'removemoney cash {fab} 100')
check('/removemoney cash nimmt vom Item', cash_items(1) == start + 650 and money(1) == start + 650)
env.command(1, f'removemoney cash {fab} 99999')
check('Zu wenig: nichts passiert', cash_items(1) == start + 650 and 'Nicht genug' in last(1), last(1))
env.command(1, 'aduty')
env.flush_log()
row = env.sql("SELECT balance_before, balance_after FROM audit_log WHERE category='money' AND action='remove' ORDER BY id DESC LIMIT 1")[0]
check('Geld-Log mit Stand vorher und nachher', row['balance_before'] == start + 750 and row['balance_after'] == start + 650, row)

print('Spieler geben Bargeld')
env.tick(1100)
env.command(1, f'geben {mira} 150')
check('/geben: Fabian -150, Mira 1390', cash_items(1) == start + 500 and cash_items(2) == 1390 and money(2) == 1390, (cash_items(1), cash_items(2)))
st = env.icall(1, 'inv_open', {})['data']['state']
cslot = [e['slot'] for e in st['items'] if e['name'] == 'cash'][0]
env.tick(100)
r = env.icall(1, 'inv_give', {'from': {'inv': 'self', 'slot': cslot}, 'count': 200, 'target': 2})
check('Im Inventar geben: Core zieht nach', r['ok'] and money(1) == start + 300 and money(2) == 1590, (money(1), money(2)))
env.tick(100)
r = env.icall(1, 'inv_move', {'from': {'inv': 'self', 'slot': cslot}, 'to': {'inv': 'drop'}})
check('Bargeld auf den Boden: Anzeige 0', r['ok'] and money(1) == 0, money(1))
check('Bargeld wiegt nichts', r['data']['state']['weight'] == env.icall(1, 'inv_open', {})['data']['state']['weight'])

print('Offline')
env.command(2, 'relog'); env.tick(200)
env.command(1, 'aduty'); env.command(1, f'givemoney cash {mira} 10'); env.command(1, 'aduty')
data = json.loads(env.sql("SELECT data FROM inventories WHERE id = %s", (f'char:{mira}',))[0]['data'])
check('Offline: direkt im gespeicherten Inventar', sum(e['count'] for e in data['slots'].values() if e['name'] == 'cash') == 1600)
r = env.call(1, 'admin_profile', {'characterId': mira})
chars = {c['id']: c for c in r['data']['characters']}
print('Akte')
r = env.call(1, 'admin_profile', {'characterId': mira})
chars = {c['id']: c for c in r['data']['characters']}
check('Akte zeigt das Bargeld aus dem Inventar', chars[mira]['cash'] == 1600, chars[mira].get('cash'))
print(f'\n{ok} ok, {fail} Fehler')
