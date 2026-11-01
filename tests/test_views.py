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
def call(src, name, data):
    env.tick(100)
    return env.icall(src, name, data)
def slots(lst):
    return {e['slot']: (e['name'], e['count']) for e in (lst or [])}

env = Env(inventory=True)
for s in (1, 2, 3):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1998-07-14', 'gender': 'female'})['data']['characterId']
jonas = env.call(3, 'char_create', {'firstname': 'Jonas', 'lastname': 'Lehmkuhl', 'dateOfBirth': '1990-03-02', 'gender': 'male'})['data']['characterId']
env.command(0, f'setrank {fab} chief')
for s, c in ((1, fab), (2, mira), (3, jonas)): env.call(s, 'char_select', {'id': c})
env.tick(300)
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[2] = [101.0, 100.0, 30.0]; env.positions[3] = [150.0, 100.0, 30.0]
env.command(1, 'aduty'); env.command(1, f'giveitem {mira} weapon_pistol'); env.command(1, f'giveitem {mira} lockpick 3'); env.command(1, 'aduty')

print('Durchsuchen')
r = call(1, 'view_search', {'target': 2})
check('Ohne Hände oben geht es nicht', r['error'] == 'not_searchable', r)
call(2, 'inv_handsup', {'up': True})
r = call(1, 'view_search', {'target': 3})
check('Zu weit weg', r['error'] in ('too_far', 'not_searchable'), r)
r = call(1, 'view_search', {'target': 2})
check('Hände oben: Durchsuchen startet', r['ok'], r)
check('Mira merkt es', 'durchsucht dich' in last(2), last(2))
o = call(1, 'inv_open', {})['data']['other']
items = slots(o['items'])
check('Fenster zeigt Miras Taschen und Waffe', o['kind'] == 'search' and any(v[0] == 'lockpick' for v in items.values()) and any(v[0] == 'weapon_pistol' for v in items.values()), items)
check('Keine Kleidung und keine Dokumente', not any(k.startswith('doc_') or k in ('shirt', 'pants', 'shoes') for k in items), list(items))
lp = [k for k, v in items.items() if v[0] == 'lockpick'][0]
r = call(1, 'inv_move', {'from': {'inv': 'other', 'slot': lp}, 'to': {'inv': 'self', 'slot': '6'}})
check('Dietriche nehmen', r['ok'] and slots(r['data']['state']['items']).get('6') == ('lockpick', 3) and lp not in slots(r['data']['other']['items']), r.get('error'))
check('Mira bekommt den neuen Stand', len(env.events_for(2, 'core_inventory:changed')) >= 1)
r = call(1, 'inv_move', {'from': {'inv': 'self', 'slot': '1'}, 'to': {'inv': 'other', 'slot': '9'}})
check('Nichts hineinlegen', r['error'] == 'not_allowed', r.get('error'))
r = call(1, 'inv_move', {'from': {'inv': 'other', 'slot': 'doc_id'}, 'to': {'inv': 'self', 'slot': '7'}})
check('Ausweis nicht nehmbar', r['error'] in ('not_allowed', 'bound'), r.get('error'))
r = call(1, 'inv_move', {'from': {'inv': 'other', 'slot': 'shirt'}, 'to': {'inv': 'self', 'slot': '7'}})
check('Kleidung nicht nehmbar', r['error'] == 'not_allowed')
call(2, 'inv_handsup', {'up': False})
gun = [k for k, v in slots(call(1, 'inv_open', {})['data']['other']['items']).items() if v[0] == 'weapon_pistol'][0]
r = call(1, 'inv_move', {'from': {'inv': 'other', 'slot': gun}, 'to': {'inv': 'self', 'slot': '7'}})
check('Hände runter: Durchsuchung vorbei', r['error'] == 'search_ended' and r['data'].get('other') is None, r.get('error'))
env.inv.eval('Views.SetCuffed')(2, True)
r = call(1, 'view_search', {'target': 2})
r = call(1, 'inv_move', {'from': {'inv': 'other', 'slot': gun}, 'to': {'inv': 'self', 'slot': '7'}})
check('Gefesselt: Waffe abnehmen', r['ok'] and slots(r['data']['state']['items']).get('7', ('',))[0] == 'weapon_pistol', r.get('error'))
call(1, 'view_close', {})
check('Schließen beendet die Sitzung', call(1, 'inv_open', {})['data'].get('other') is None)

print('Kofferraum')
env.inv.execute("VEH = { [55] = { plate = ' LS 1234 ', locked = false, position = { x = 102.0, y = 100.0, z = 30.0 } }, [56] = { plate = 'ZU 99', locked = true, position = { x = 101.0, y = 100.0, z = 30.0 } } }")
env.inv.execute("Platform.GetVehicleInfo = function(id) return VEH[id] end")
r = call(1, 'view_trunk', {'netId': 56, 'class': 1})
check('Abgeschlossen: zu', r['error'] == 'vehicle_locked')
r = call(1, 'view_trunk', {'netId': 55, 'class': 8})
check('Motorrad: kein Kofferraum', r['error'] == 'no_trunk')
r = call(1, 'view_trunk', {'netId': 55, 'class': 1})
o = call(1, 'inv_open', {})['data']['other']
check('Limousine: 20 Plätze, 100 kg, Kennzeichen', r['ok'] and o['slots'] == 20 and o['maxWeight'] == 100000 and 'LS 1234' in o['title'], o)
r = call(1, 'inv_move', {'from': {'inv': 'self', 'slot': '6'}, 'to': {'inv': 'other', 'slot': '1'}})
check('Hineinlegen', r['ok'] and slots(r['data']['other']['items']).get('1') == ('lockpick', 3), r.get('error'))
r = call(3, 'view_trunk', {'netId': 55, 'class': 1})
check('Nur eine Person gleichzeitig', r['error'] in ('trunk_busy', 'too_far'), r)
env.positions[3] = [103.0, 100.0, 30.0]
r = call(3, 'view_trunk', {'netId': 55, 'class': 1})
check('Zweite Person: belegt', r['error'] == 'trunk_busy', r)
call(1, 'view_close', {})
data = json.loads(env.sql("SELECT data FROM inventories WHERE id = 'trunk:LS 1234'")[0]['data'])
check('Gespeichert am Kennzeichen', any(e['name'] == 'lockpick' for e in data['slots'].values()) and data['flags']['trunkClass'] == 1, data)
r = call(3, 'view_trunk', {'netId': 55, 'class': 20})
o = call(3, 'inv_open', {})['data']['other']
check('Größe bleibt beim ersten Öffnen (keine LKW-Größe erschleichen)', o['slots'] == 20, o['slots'])
r = call(3, 'inv_move', {'from': {'inv': 'other', 'slot': '1'}, 'to': {'inv': 'self', 'slot': '6'}})
check('Jonas nimmt die Dietriche', r['ok'])
env.inv.execute("VEH[55].locked = true")
r = call(3, 'inv_move', {'from': {'inv': 'self', 'slot': '6'}, 'to': {'inv': 'other', 'slot': '1'}})
check('Abgeschlossen während offen: Fenster zu', r['error'] == 'trunk_closed' and r['data'].get('other') is None)

print('/invsee')
env.command(1, f'invsee {mira}')
check('Ohne Dienst nicht', 'Admin-Dienst' in last(1))
env.command(1, 'aduty'); env.command(1, f'invsee {mira}')
o = call(1, 'inv_open', {})['data']['other']
check('Admin sieht alles, auch Kleidung und Ausweis', o['kind'] == 'admin' and 'doc_id' in slots(o['items']) and 'shirt' in slots(o['items']), list(slots(o['items'])))
r = call(1, 'inv_move', {'from': {'inv': 'self', 'slot': '1'}, 'to': {'inv': 'other', 'slot': '8'}})
check('Admin legt hinein', r['ok'] and slots(r['data']['other']['items']).get('8', ('',))[0] == 'water', r.get('error'))
env.command(2, 'relog'); env.tick(200)
env.command(1, f'invsee {mira}')
o = call(1, 'inv_open', {})['data']['other']
check('Auch offline', o and 'doc_id' in slots(o['items']))
call(1, 'view_close', {})
check('Offline-Inventar wieder entladen', env.inv.eval(f"Inventory.Cached('char:{mira}')") is None)
env.flush_log()
acts = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category IN ('item','admin')")]
check('Log: durchsucht, genommen, Kofferraum, invsee', all(a in acts for a in ('search_open', 'search_take', 'trunk_put', 'trunk_take', 'invsee', 'admin_move')), set(acts))

print('Lager')
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[3] = [101.0, 100.0, 30.0]
opt = "{ label = 'Waffenkammer LSPD', slots = 12, maxWeight = 50000, position = { x = 100.0, y = 101.0, z = 30.0 }, distance = 3.0 }"
r = env.inv.eval(f"{{ Views.OpenStash(1, 'lspd', {opt}) }}")
check('Lager öffnet', r[1] == True, list(r.values()))
o = call(1, 'inv_open', {})['data']['other']
check('Titel und Größe vom Script', o['kind'] == 'stash' and o['title'] == 'Waffenkammer LSPD' and o['slots'] == 12 and o['maxWeight'] == 50000, o)
env.inv.eval(f"Views.OpenStash(3, 'lspd', {opt})")
check('Zweite Person gleichzeitig', call(3, 'inv_open', {})['data']['other']['kind'] == 'stash')
own = slots(call(1, 'inv_open', {})['data']['state']['items'])
src = [k for k in own if k.isdigit() and own[k][0] != 'cash'][0]
put = own[src][0]
env.events.clear()
r = call(1, 'inv_move', {'from': {'inv': 'self', 'slot': src}, 'to': {'inv': 'other', 'slot': '1'}})
check('Ins Lager legen', r['ok'] and slots(r['data']['other']['items']).get('1', ('',))[0] == put, r.get('error'))
check('Andere Person am Lager sieht es neu', len(env.events_for(3, 'core_inventory:changed')) >= 1)
r = call(3, 'inv_open', {})['data']['other']
check('Gleicher Inhalt bei Person 2', slots(r['items']).get('1', ('',))[0] == put)
call(1, 'view_close', {})
check('Noch geladen, solange jemand dran ist', env.inv.eval("Inventory.Cached('stash:lspd')") is not None)
env.positions[3] = [120.0, 100.0, 30.0]
r = call(3, 'inv_move', {'from': {'inv': 'other', 'slot': '1'}, 'to': {'inv': 'self', 'slot': '9'}})
check('Weggegangen: Lager zu', r['error'] == 'stash_closed', r.get('error'))
check('Danach entladen und gespeichert', env.inv.eval("Inventory.Cached('stash:lspd')") is None and len(env.sql("SELECT id FROM inventories WHERE id = 'stash:lspd'")) == 1)
r = env.inv.eval("{ Views.OpenStash(1, 'kaputt', { slots = 0, maxWeight = 10 }) }")
check('Falsche Größe abgelehnt', r[1] == False and r[2] == 'invalid_stash')
r = env.inv.eval("{ Views.OpenStash(1, 'ansicht', { slots = 5, maxWeight = 1000, canPut = false }) }")
own = slots(call(1, 'inv_open', {})['data']['state']['items'])
r = call(1, 'inv_move', {'from': {'inv': 'self', 'slot': list(k for k in own if k.isdigit())[0]}, 'to': {'inv': 'other', 'slot': '1'}})
check('canPut = false: nur nehmen', r['error'] == 'not_allowed')
call(1, 'view_close', {})

print('Mitziehen')
env.call(2, 'auth_login', {'email': '2@t.de', 'password': 'passwort123'}); env.call(2, 'char_select', {'id': mira}); env.tick(300)
env.positions[2] = [101.0, 100.0, 30.0]; env.positions[1] = [100.0, 100.0, 30.0]
env.inv.eval('Views.SetCuffed')(2, True)
env.positions[2] = [101.0, 100.0, 30.0]
env.inv.eval('Views.SetCuffed')(2, True)
call(1, 'view_search', {'target': 2})
env.events.clear()
own = slots(call(2, 'inv_open', {})['data']['state']['items'])
src = [k for k in own if k.isdigit()][0]
call(2, 'inv_move', {'from': {'inv': 'self', 'slot': src}, 'to': {'inv': 'self', 'slot': '10'}})
check('Durchsuchende Person sieht Änderung sofort', len(env.events_for(1, 'core_inventory:changed')) >= 1)
env.flush_log()
acts = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category = 'item'")]
check('Log: Lager', all(a in acts for a in ('stash_open', 'stash_put')), set(acts))

print(f'\n{ok} ok, {fail} Fehler')
