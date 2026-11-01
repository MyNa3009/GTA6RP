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
def items(src):
    st = call(src, 'inv_open', {})['data']['state']
    return {e['slot']: e for e in st['items']}

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

print('Ausweis')
it = items(2)
check('Jeder hat beim Start den Personalausweis', it.get('doc_id', {}).get('name') == 'id_card', list(it))
check('Ausweis wiegt nichts', call(2, 'inv_open', {})['data']['state']['weight'] == 1500)
r = call(2, 'inv_move', {'from': {'inv': 'self', 'slot': 'doc_id'}, 'to': {'inv': 'self', 'slot': '9'}})
check('Ausweis lässt sich nicht verschieben', r['error'] == 'bound', r.get('error'))
r = call(2, 'inv_move', {'from': {'inv': 'self', 'slot': 'doc_id'}, 'to': {'inv': 'drop'}})
check('Nicht auf den Boden', r['error'] == 'bound')
r = call(2, 'inv_give', {'from': {'inv': 'self', 'slot': 'doc_id'}, 'count': 1, 'target': 1})
check('Nicht weitergeben', r['error'] == 'bound', r.get('error'))
r = call(2, 'inv_move', {'from': {'inv': 'self', 'slot': '1'}, 'to': {'inv': 'self', 'slot': 'doc_driver'}})
check('Nichts anderes in Dokument-Plätze', r['error'] == 'bound')

print('Lizenzen')
env.command(1, 'aduty')
env.command(1, f'givelicense {mira} fuehrerschein C')
check('Klasse C ohne B geht nicht', 'zuerst Klasse B' in last(1), last(1))
env.command(1, f'givelicense {mira} fuehrerschein B')
check('Führerschein B ausgestellt', 'ausgestellt' in last(1) and 'Führerschein' in last(2), (last(1), last(2)))
env.command(1, f'givelicense {mira} fuehrerschein C')
it = items(2)
check('Item mit Klassen B,C und Ablaufdatum', it.get('doc_driver', {}).get('meta', {}).get('classes') == 'B,C' and it['doc_driver']['meta'].get('expires'), it.get('doc_driver'))
check('Ablauf in 30 Tagen', abs(it['doc_driver']['meta']['expires'] - (env.lua.eval('os.time()') + 30 * 86400)) < 5)
env.command(1, f'givelicense {mira} waffenschein')
check('Waffenschein', 'doc_weapon' in items(2))
check('HasLicense C', env.inv.eval(f"Documents.Has({mira}, 'driver', 'C')") is True)
env.command(1, f'givelicense {mira} laserschwert')
check('Unbekannte Lizenz', 'Unbekannte Lizenz' in last(1))
env.command(1, f'giveitem {jonas} license_pilot')
env.command(3, 'relog'); env.call(3, 'auth_login', {'email': '3@t.de', 'password': 'passwort123'}); env.call(3, 'char_select', {'id': jonas}); env.tick(300)
check('Lizenz-Item ohne Register wird entfernt (nur Register stellt aus)', 'doc_pilot' not in items(3))

print('Entziehen und Ablauf')
env.command(1, f'revokelicense {mira} fuehrerschein C Trunkenheitsfahrt')
it = items(2)
check('Nur Klasse C entzogen', it['doc_driver']['meta']['classes'] == 'B', it['doc_driver'].get('meta'))
env.command(1, f'revokelicense {mira} waffenschein Schusswaffengebrauch')
check('Waffenschein entzogen: Item weg', 'doc_weapon' not in items(2) and 'entzogen' in last(2))
rows = {r['type']: r for r in env.to_py(env.inv.eval(f'Documents.Licenses({mira})'))}
check('Register: entzogen mit Grund', rows['weapon']['status'] == 'revoked' and rows['weapon']['revokeReason'] == 'Schusswaffengebrauch', rows['weapon'])
env.command(1, f'licenses {mira}')
check('/licenses zeigt den Stand', 'Führerschein B: gültig bis' in last(1) and 'Waffenschein: entzogen am' in last(1), last(1))
env.sql("UPDATE licenses SET expires_at = NOW() - INTERVAL 1 DAY WHERE character_id = %s AND type = 'driver'", (mira,))
check('Abgelaufen: HasLicense false', env.inv.eval(f"Documents.Has({mira}, 'driver', 'B')") is False)
env.command(2, 'relog'); env.call(2, 'auth_login', {'email': '2@t.de', 'password': 'passwort123'}); env.call(2, 'char_select', {'id': mira}); env.tick(300)
it = items(2)
check('Abgelaufener Führerschein bleibt, Status abgelaufen', it.get('doc_driver', {}).get('meta', {}).get('status') == 'expired', it.get('doc_driver'))
env.command(1, f'givelicense {mira} fuehrerschein B')
check('Neu ausstellen verlängert', items(2)['doc_driver']['meta'].get('status') is None)
env.command(1, 'aduty')

print('Zeigen')
env.positions[2] = [101.0, 100.0, 30.0]
r = call(2, 'doc_show', {'type': 'id', 'target': 1}) if False else None
env.tick(100)
r = env.icall(2, 'doc_show', {'type': 'id', 'target': 1})
ev = env.events_for(1, 'core_inventory:document')
card = ev[-1]['card'] if ev else {}
check('Fabian sieht Miras Ausweis', r['ok'] and card.get('firstname') == 'Mira' and card.get('dateOfBirth') == '1998-07-14' and card.get('number') == mira and card.get('gender') == 'female', (r, card))
check('Foto kommt vom Zeigenden (Server-ID)', ev[-1].get('from') == 2)
check('Mira bekommt Bestätigung', 'Du zeigst ID' in last(2))
check('Nur Fabian bekommt die Karte', not env.events_for(3, 'core_inventory:document'))
env.tick(100)
r = env.icall(2, 'doc_show', {'type': 'id', 'target': 3})
check('Zu weit weg', r['error'] == 'too_far')
env.tick(100)
r = env.icall(2, 'doc_show', {'type': 'driver', 'target': 1})
card = env.events_for(1, 'core_inventory:document')[-1]['card']
check('Führerschein mit Klassen und Status', card['classes'][0]['id'] == 'B' and card['status'] == 'valid', card)
env.tick(100)
r = env.icall(2, 'doc_show', {'type': 'weapon', 'target': 1})
check('Entzogenen Waffenschein kann man nicht zeigen', r['error'] == 'no_document')
env.flush_log()
acts = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE category='item'")]
check('Log: ausgestellt, entzogen, gezeigt', all(a in acts for a in ('license_issue', 'license_revoke', 'show_document')), set(acts))
print(f'\n{ok} ok, {fail} Fehler')
