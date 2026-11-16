"""Test fuer core_phone gegen MariaDB: eSIM und Handy als Item, Kontakte, Nachrichten (auch offline, Standort, loeschen),
Anrufe (klingeln, annehmen, ablehnen, verpasst, besetzt, nicht erreichbar), Bank-App, Notruf-App, Admin-Ansicht, Exports, Log."""
import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env

ok = fail = 0


def check(label, condition, info=None):
    global ok, fail
    if condition:
        ok += 1
        print('  ok   ', label)
    else:
        fail += 1
        print('  FEHLER', label, info if info is not None else '')


EXTRA = ['core_lib', 'core_factions', 'core_dispatch', 'core_bank', 'core_phone']
env = Env(inventory=True, debug=True, extra=EXTRA)
for name in EXTRA:
    env.runtimes[name].execute('Config.Network.MaxRequestsPerSecond = 0')
env.inv.execute('Config.Network.MaxRequestsPerSecond = 0')
phone = env.runtimes['core_phone']
bank = env.runtimes['core_bank']
phone.execute('Config.Phone.MessageCooldownMs = 0')
P = lambda src, name, data=None: env.rcall('core_phone', src, name, data)

people = {1: ('Lena', 'Hoffmann'), 2: ('Paul', 'Krüger'), 3: ('Mira', 'Schulz'), 4: ('Tom', 'Becker'), 5: ('Sara', 'Yilmaz')}
ids = {}
for src, (first, last) in people.items():
    env.connect(src, [f'license:{src}'])
    env.call(src, 'auth_register', {'email': f'{src}@t.de', 'password': 'passwort123'})
    ids[src] = env.call(src, 'char_create', {'firstname': first, 'lastname': last, 'dateOfBirth': '1990-01-01', 'gender': 'male'})['data']['characterId']
for src in people:
    env.call(src, 'char_select', {'id': ids[src]})
    env.positions[src] = [100.0 + src, 200.0, 30.0]
env.tick(4000)


def items(cid, name='phone'):
    return env.to_py(env.inv.eval(f"Platform.CallExport('core_inventory', 'GetItemCount', {cid}, '{name}')")) or 0


def give(cid, count=1):
    env.inv.eval(f"Platform.CallExport('core_inventory', 'AddItem', {cid}, 'phone', {count})")


def take(cid):
    env.inv.eval(f"Platform.CallExport('core_inventory', 'RemoveItem', {cid}, 'phone', {items(cid)})")


def pushes(src, kind=None):
    return [d for d in env.events_for(src, 'core_phone:event') if kind is None or d.get('type') == kind]


def notes(src):
    return [d.get('text', '') for d in env.events_for(src, 'core:notify')]


def calls(cid):
    return env.sql('SELECT * FROM phone_calls WHERE owner_id = %s ORDER BY id', (cid,))


print('eSIM und Handy als Item')
num = {r['character_id']: r['number'] for r in env.sql('SELECT character_id, number FROM phone_numbers')}
check('jeder Charakter hat beim Einloggen eine Nummer mit 6 Ziffern', len(num) == 5 and all(len(n) == 6 and n.isdigit() and n[0] != '0' for n in num.values()), num)
check('Nummern sind verschieden', len(set(num.values())) == 5)
check('wer kein Handy hatte, hat einmal eins bekommen', all(items(ids[s]) == 1 for s in people), [items(ids[s]) for s in people])
check('Meldung mit Nummer und Taste', any('Du hast ein Handy bekommen' in t and num[ids[1]] in t and 'F1' in t for t in notes(1)), notes(1)[-2:])
o = P(1, 'phone_open')
d = o['data'] if o['ok'] else {}
check('Handy öffnen: Nummer, Name, leer, Apps Bank und Notruf', o['ok'] and d['number'] == num[ids[1]] and d['name'] == 'Lena Hoffmann' and not d['contacts']
      and not d['threads'] and d['unread'] == 0 and d['missed'] == 0 and d['apps'] == {'bank': True, 'dispatch': True} and d.get('admin') is None, o)
take(ids[5])
check('ohne Handy im Inventar: no_phone', P(5, 'phone_open')['error'] == 'no_phone' and P(5, 'phone_home')['error'] == 'no_phone'
      and P(5, 'phone_message_send', {'number': num[ids[1]], 'text': 'Hallo'})['error'] == 'no_phone')
env.lua.globals().DropPlayer(5, 'Test')
env.tick(300)
env.connect(5, ['license:5'])
env.call(5, 'auth_login', {'email': '5@t.de', 'password': 'passwort123'})
env.call(5, 'char_select', {'id': ids[5]})
env.positions[5] = [105.0, 200.0, 30.0]
env.tick(4000)
check('neu einloggen: gleiche Nummer, kein zweites geschenktes Handy', env.sql('SELECT number FROM phone_numbers WHERE character_id = %s', (ids[5],))[0]['number'] == num[ids[5]]
      and items(ids[5]) == 0)
give(ids[5])
check('neues Handy geholt: gleiche Nummer (eSIM hängt an der Person)', P(5, 'phone_open')['data']['number'] == num[ids[5]])

print('Kontakte')
r = P(1, 'phone_contact_save', {'name': '  Paul\n Krüger ', 'number': num[ids[2]][:3] + ' ' + num[ids[2]][3:]})
check('Kontakt anlegen: Name bereinigt, Nummer ohne Leerzeichen', r['ok'] and r['data']['contacts'] == [{'id': r['data']['contacts'][0]['id'], 'name': 'Paul Krüger', 'number': num[ids[2]]}], r)
paul_contact = r['data']['contacts'][0]['id']
check('ohne Name: invalid_name', P(1, 'phone_contact_save', {'name': '  ', 'number': num[ids[3]]})['error'] == 'invalid_name')
check('falsche Nummer: invalid_number', P(1, 'phone_contact_save', {'name': 'Mira', 'number': '12'})['error'] == 'invalid_number')
check('Nummer doppelt: contact_exists', P(1, 'phone_contact_save', {'name': 'Paul 2', 'number': num[ids[2]]})['error'] == 'contact_exists')
P(1, 'phone_contact_save', {'name': 'Mira', 'number': num[ids[3]]})
r = P(1, 'phone_contact_save', {'id': paul_contact, 'name': 'Paul (Werkstatt)', 'number': num[ids[2]]})
check('Kontakt ändern, Liste nach Namen sortiert', r['ok'] and [c['name'] for c in r['data']['contacts']] == ['Mira', 'Paul (Werkstatt)'], r)
check('fremden Kontakt ändern: not_found', P(2, 'phone_contact_save', {'id': paul_contact, 'name': 'X', 'number': num[ids[3]]})['error'] == 'not_found')
phone.execute('Config.Phone.MaxContacts = 2')
check('Kontakte voll: contacts_full', P(1, 'phone_contact_save', {'name': 'Tom', 'number': num[ids[4]]})['error'] == 'contacts_full')
phone.execute('Config.Phone.MaxContacts = 100')
check('fremden Kontakt löschen: not_found', P(2, 'phone_contact_delete', {'id': paul_contact})['error'] == 'not_found')
r = P(1, 'phone_contact_delete', {'id': paul_contact})
check('Kontakt löschen', r['ok'] and [c['name'] for c in r['data']['contacts']] == ['Mira'])

print('Nachrichten')
r = P(1, 'phone_message_send', {'number': num[ids[2]], 'text': '  Bist du\n an der Werkstatt?  '})
check('Nachricht senden', r['ok'] and r['data']['message']['text'] == 'Bist du an der Werkstatt?' and r['data']['message']['direction'] == 'out', r)
got = pushes(2, 'message')
check('Paul bekommt Bescheid aufs Handy', got and got[-1] == {'type': 'message', 'number': num[ids[1]], 'kind': 'text', 'text': 'Bist du an der Werkstatt?', 'silent': False} and 'name' not in got[-1], got)
h = P(2, 'phone_home')['data']
check('bei Paul: ein Chat, eine ungelesene', h['unread'] == 1 and len(h['threads']) == 1 and h['threads'][0]['number'] == num[ids[1]] and h['threads'][0]['unread'] == 1
      and h['threads'][0]['direction'] == 'in', h['threads'])
t = P(2, 'phone_thread', {'number': num[ids[1]]})
check('Chat öffnen: Nachricht da, danach gelesen', t['ok'] and len(t['data']['messages']) == 1 and t['data']['messages'][0]['direction'] == 'in' and t['data']['unread'] == 0
      and P(2, 'phone_home')['data']['unread'] == 0, t)
P(2, 'phone_message_send', {'number': num[ids[1]], 'text': 'Ja, komm vorbei.'})
t = P(1, 'phone_thread', {'number': num[ids[2]]})
check('Chat bei Lena: beide Nachrichten in der richtigen Reihenfolge', [m['direction'] for m in t['data']['messages']] == ['out', 'in'] and len(t['data']['messages'][0]['at']) == 16, t)
check('ungültig: leerer Text, falsche Nummer, eigene Nummer, unbekannte Nummer',
      P(1, 'phone_message_send', {'number': num[ids[2]], 'text': '   '})['error'] == 'invalid_text'
      and P(1, 'phone_message_send', {'number': '123', 'text': 'Hallo'})['error'] == 'invalid_number'
      and P(1, 'phone_message_send', {'number': num[ids[1]], 'text': 'Hallo'})['error'] == 'own_number'
      and P(1, 'phone_message_send', {'number': next(str(n) for n in range(100000, 100100) if str(n) not in num.values()), 'text': 'Hallo'})['error'] == 'unknown_number')
long_text = 'a' * 400
check('zu lang: auf 300 Zeichen gekürzt', len(P(1, 'phone_message_send', {'number': num[ids[2]], 'text': long_text})['data']['message']['text']) == 300)
env.positions[1] = [215.5, -810.25, 30.7]
r = P(1, 'phone_message_send', {'number': num[ids[2]], 'location': True, 'text': 'egal'})
m = r['data']['message'] if r['ok'] else {}
check('Standort senden: Position kommt vom Server', r['ok'] and m['kind'] == 'location' and abs(m['x'] - 215.5) < 0.01 and abs(m['y'] + 810.25) < 0.01 and m['text'] == 'Standort', r)
phone.execute('Config.Phone.MessageCooldownMs = 800')
P(1, 'phone_message_send', {'number': num[ids[2]], 'text': 'eins'})
check('zu schnell hintereinander: too_fast', P(1, 'phone_message_send', {'number': num[ids[2]], 'text': 'zwei'})['error'] == 'too_fast')
env.tick(900)
check('nach der Pause geht es wieder', P(1, 'phone_message_send', {'number': num[ids[2]], 'text': 'zwei'})['ok'])
phone.execute('Config.Phone.MessageCooldownMs = 0')
phone.execute('Config.Phone.ThreadPage = 3')
t1 = P(2, 'phone_thread', {'number': num[ids[1]]})['data']
t2 = P(2, 'phone_thread', {'number': num[ids[1]], 'before': t1['messages'][0]['id']})['data']
check('Chat seitenweise: 3 neueste, davor die älteren', len(t1['messages']) == 3 and t1['more'] is True and t1['messages'][-1]['text'] == 'zwei'
      and t2['messages'][-1]['id'] < t1['messages'][0]['id'], (t1, t2))
phone.execute('Config.Phone.ThreadPage = 30')
env.lua.globals().DropPlayer(3, 'Test')
env.tick(300)
before = len(pushes(3))
check('an Mira, die offline ist: wird gespeichert', P(1, 'phone_message_send', {'number': num[ids[3]], 'text': 'Meld dich, wenn du da bist.'})['ok']
      and env.sql("SELECT COUNT(*) AS n FROM phone_messages WHERE owner_id = %s AND direction = 'in' AND read_at IS NULL", (ids[3],))[0]['n'] == 1 and len(pushes(3)) == before)
env.connect(3, ['license:3'])
env.call(3, 'auth_login', {'email': '3@t.de', 'password': 'passwort123'})
env.call(3, 'char_select', {'id': ids[3]})
env.positions[3] = [103.0, 200.0, 30.0]
env.tick(2500)
check('Mira loggt ein: Nachricht wartet im Handy', P(3, 'phone_open')['data']['unread'] == 1)
check('Flugmodus an', P(4, 'phone_settings', {'airplane': True})['data'] == {'silent': False, 'airplane': True})
check('im Flugmodus senden: airplane', P(4, 'phone_message_send', {'number': num[ids[1]], 'text': 'Hallo'})['error'] == 'airplane')
before = len(pushes(4))
check('an jemanden im Flugmodus: gespeichert, aber kein Bescheid', P(1, 'phone_message_send', {'number': num[ids[4]], 'text': 'Ruf zurück.'})['ok'] and len(pushes(4)) == before
      and P(4, 'phone_home')['data']['unread'] == 1)
P(4, 'phone_settings', {'airplane': False, 'silent': True})
P(1, 'phone_message_send', {'number': num[ids[4]], 'text': 'Noch da?'})
check('lautlos: Bescheid kommt mit silent', pushes(4, 'message')[-1]['silent'] is True)
check('Einstellungen bleiben gespeichert', env.sql('SELECT silent, airplane FROM phone_numbers WHERE character_id = %s', (ids[4],))[0] == {'silent': 1, 'airplane': 0})
P(4, 'phone_settings', {'silent': False})
r = P(2, 'phone_thread_delete', {'number': num[ids[1]]})
check('Paul löscht den Chat: bei ihm weg', r['ok'] and not r['data']['threads'] and not P(2, 'phone_thread', {'number': num[ids[1]]})['data']['messages'])
check('bei Lena bleibt er stehen', len(P(1, 'phone_thread', {'number': num[ids[2]]})['data']['messages']) >= 5)
check('in der Datenbank nur markiert', env.sql('SELECT COUNT(*) AS n FROM phone_messages WHERE owner_id = %s AND hidden = 1', (ids[2],))[0]['n'] >= 5)
P(1, 'phone_message_send', {'number': num[ids[2]], 'text': 'Neuer Anfang'})
check('neue Nachricht danach: Chat ist wieder da, nur mit der neuen', [m['text'] for m in P(2, 'phone_thread', {'number': num[ids[1]]})['data']['messages']] == ['Neuer Anfang'])

P(2, 'phone_contact_save', {'name': 'Lena', 'number': num[ids[1]]})
P(1, 'phone_message_send', {'number': num[ids[2]], 'text': 'Kennst du mich?'})
check('Bescheid nennt den Namen, unter dem der Empfänger die Nummer gespeichert hat', pushes(2, 'message')[-1].get('name') == 'Lena')
env.inv.eval(f"Platform.Emit('core_inventory:itemUsed', 2, {ids[2]}, 'phone', nil)")
env.inv.eval(f"Platform.Emit('core_inventory:itemUsed', 2, {ids[2]}, 'water', nil)")
check('Handy im Inventar benutzen: öffnet es beim Spieler', len(pushes(2, 'open')) == 1)

print('Anrufe')
r = P(1, 'phone_call_start', {'number': num[ids[2]]})
check('Lena ruft Paul an: wählt', r['ok'] and r['data']['call']['state'] == 'dialing' and r['data']['call']['number'] == num[ids[2]], r)
inc = pushes(2, 'call')[-1]
check('bei Paul klingelt es, mit Name aus seinen Kontakten', inc['call']['state'] == 'incoming' and inc['call']['number'] == num[ids[1]] and inc['call']['silent'] is False and inc['call']['name'] == 'Lena', inc)
check('Stand beim Öffnen des Handys', P(2, 'phone_home')['data']['call']['state'] == 'incoming')
check('während es klingelt kein zweiter Anruf: in_call', P(1, 'phone_call_start', {'number': num[ids[3]]})['error'] == 'in_call')
check('Anrufer kann nicht selbst annehmen: no_call', P(1, 'phone_call_answer')['error'] == 'no_call')
r = P(4, 'phone_call_start', {'number': num[ids[2]]})
check('Tom ruft Paul an: besetzt', r['error'] == 'line_busy' and calls(ids[4])[-1]['status'] == 'busy' and pushes(2, 'missed')[-1]['number'] == num[ids[4]], r)
r = P(2, 'phone_call_answer')
a, b = pushes(1, 'call')[-1]['call'], pushes(2, 'call')[-1]['call']
check('Paul nimmt an: beide aktiv, jeder kennt den Partner und denselben Sprachkanal', r['ok'] and a['state'] == 'active' and b['state'] == 'active'
      and a['partner'] == 2 and b['partner'] == 1 and a['channel'] == b['channel'] > 10000, (a, b))
env.tick(7000)
check('Dauer läuft', P(1, 'phone_home')['data']['call']['seconds'] == 7)
check('Paul legt auf', P(2, 'phone_call_end')['ok'])
end = pushes(1, 'call')[-1]
check('beide bekommen das Ende mit Dauer', end.get('call') is None and end['ended'] == {'reason': 'ended', 'seconds': 7} and pushes(2, 'call')[-1]['ended']['reason'] == 'ended', end)
l1, l2 = calls(ids[1])[-1], calls(ids[2])[-1]
check('Anrufliste: bei Lena ausgehend, bei Paul eingehend, 7 Sekunden', l1['direction'] == 'out' and l1['status'] == 'answered' and l1['seconds'] == 7 and l1['other_number'] == num[ids[2]]
      and l2['direction'] == 'in' and l2['status'] == 'answered' and l2['seconds'] == 7 and l2['other_number'] == num[ids[1]], (l1, l2))
check('nichts mehr zum Auflegen: no_call', P(1, 'phone_call_end')['error'] == 'no_call' and P(1, 'phone_home')['data'].get('call') is None)
P(1, 'phone_call_start', {'number': num[ids[2]]})
P(2, 'phone_call_end')
check('Paul lehnt ab', pushes(1, 'call')[-1]['ended']['reason'] == 'declined' and calls(ids[1])[-1]['status'] == 'declined' and calls(ids[2])[-1]['status'] == 'declined')
P(1, 'phone_call_start', {'number': num[ids[2]]})
P(1, 'phone_call_end')
check('Lena bricht ab: bei Paul verpasst', pushes(2, 'call')[-1]['ended']['reason'] == 'cancelled' and calls(ids[2])[-1]['status'] == 'missed')
P(1, 'phone_call_start', {'number': num[ids[2]]})
env.tick(29000)
check('nach 29 Sekunden klingelt es noch', P(2, 'phone_home')['data']['call']['state'] == 'incoming')
env.tick(2000)
check('nach 30 Sekunden: verpasst', pushes(2, 'call')[-1]['ended']['reason'] == 'timeout' and P(2, 'phone_home')['data'].get('call') is None and calls(ids[2])[-1]['status'] == 'missed')
h = P(2, 'phone_home')['data']
check('Paul sieht 3 verpasste (besetzt, abgebrochen, nicht rangegangen)', h['missed'] == 3 and h['calls'][0]['status'] == 'missed' and h['calls'][0]['number'] == num[ids[1]], (h['missed'], h['calls'][:2]))
check('Anrufliste angesehen: Zähler auf 0', P(2, 'phone_calls_seen')['data']['missed'] == 0 and P(2, 'phone_calls')['data']['missed'] == 0)
check('falsche, eigene, unbekannte Nummer', P(1, 'phone_call_start', {'number': '12'})['error'] == 'invalid_number'
      and P(1, 'phone_call_start', {'number': num[ids[1]]})['error'] == 'own_number'
      and P(1, 'phone_call_start', {'number': next(str(n) for n in range(100000, 100100) if str(n) not in num.values())})['error'] == 'unknown_number')
take(ids[3])
check('Mira hat ihr Handy nicht dabei: unreachable, bei ihr verpasst', P(1, 'phone_call_start', {'number': num[ids[3]]})['error'] == 'unreachable'
      and calls(ids[1])[-1]['status'] == 'unreachable' and calls(ids[3])[-1]['status'] == 'missed')
give(ids[3])
P(3, 'phone_settings', {'airplane': True})
check('Flugmodus: unreachable, selbst anrufen geht auch nicht', P(1, 'phone_call_start', {'number': num[ids[3]]})['error'] == 'unreachable'
      and P(3, 'phone_call_start', {'number': num[ids[1]]})['error'] == 'airplane')
P(3, 'phone_settings', {'airplane': False})
P(1, 'phone_call_start', {'number': num[ids[3]]})
P(3, 'phone_call_answer')
env.tick(3000)
env.lua.globals().DropPlayer(3, 'Test')
env.tick(300)
check('Mira verlässt den Server im Gespräch: Lena bekommt das Ende, 3 Sekunden stehen in der Liste', pushes(1, 'call')[-1]['ended']['reason'] == 'left'
      and calls(ids[1])[-1]['status'] == 'answered' and calls(ids[1])[-1]['seconds'] == 3 and P(1, 'phone_home')['data'].get('call') is None)
check('Mira ist offline: unreachable', P(1, 'phone_call_start', {'number': num[ids[3]]})['error'] == 'unreachable')

print('Bank-App')
acc = {r['character_id']: r['number'] for r in env.sql('SELECT character_id, number FROM bank_accounts')}
r = P(1, 'phone_bank')
check('Übersicht: Kontostand, Kontonummer, Schulden in Kurzform', r['ok'] and r['data']['overview']['balance'] == 2500 and r['data']['overview']['number'] == acc[ids[1]]
      and r['data']['overview']['debts']['count'] == 0 and not r['data']['overview']['recipients'], r)
r = P(1, 'phone_bank_lookup', {'number': acc[ids[2]]})
check('Empfänger prüfen', r['ok'] and r['data'] == {'name': 'Paul Krüger', 'number': acc[ids[2]]}, r)
check('eigenes und unbekanntes Konto', P(1, 'phone_bank_lookup', {'number': acc[ids[1]]})['error'] == 'same_account' and P(1, 'phone_bank_lookup', {'number': '1234'})['error'] == 'unknown_account')
r = P(1, 'phone_bank_transfer', {'number': acc[ids[2]], 'amount': 400, 'purpose': 'Reifen'})
row = env.sql('SELECT * FROM bank_transactions WHERE character_id = %s ORDER BY id DESC LIMIT 1', (ids[1],))[0]
check('400 überweisen: Kanal Handy im Kontoauszug', r['ok'] and r['data']['overview']['balance'] == 2100 and r['data']['to']['name'] == 'Paul Krüger'
      and row['channel'] == 'phone' and row['amount'] == -400 and row['text'] == 'Reifen', (r, row))
check('letzter Empfänger steht in der App', r['data']['overview']['recipients'] == [{'name': 'Paul Krüger', 'number': acc[ids[2]]}])
check('zu viel: not_enough_money, ungültig: invalid_amount', P(1, 'phone_bank_transfer', {'number': acc[ids[2]], 'amount': 99999})['error'] == 'not_enough_money'
      and P(1, 'phone_bank_transfer', {'number': acc[ids[2]], 'amount': 1.5})['error'] == 'invalid_amount'
      and P(1, 'phone_bank_transfer', {'number': acc[ids[2]], 'amount': -4})['error'] == 'invalid_amount')
debt_id = bank.eval(f"Debts.Add({ids[1]}, {{ amount = 300, title = 'Rotlicht überfahren', kind = 'fine' }})")
other_debt = bank.eval(f"Debts.Add({ids[2]}, {{ amount = 50, title = 'Parken', kind = 'fine' }})")
r = P(1, 'phone_bank_debts')
check('Schulden in der App', r['ok'] and len(r['data']['debts']) == 1 and r['data']['debts'][0]['title'] == 'Rotlicht überfahren' and r['data']['debts'][0]['rest'] == 300, r)
check('fremde Forderung bezahlen: not_found', P(1, 'phone_bank_pay', {'id': other_debt})['error'] == 'not_found')
r = P(1, 'phone_bank_pay', {'id': debt_id, 'amount': 100})
check('100 anzahlen: Rest 200, Konto 2000', r['ok'] and r['data']['debt']['rest'] == 200 and r['data']['overview']['balance'] == 2000 and r['data']['debts'][0]['rest'] == 200, r)
check('mehr als der Rest: invalid_amount', P(1, 'phone_bank_pay', {'id': debt_id, 'amount': 201})['error'] == 'invalid_amount')
r = P(1, 'phone_bank_pay', {'id': debt_id})
check('Rest bezahlen: erledigt, Liste leer', r['ok'] and r['data']['debt']['status'] == 'paid' and not r['data']['debts'] and r['data']['overview']['balance'] == 1800, r)
check('schon erledigt: debt_closed', P(1, 'phone_bank_pay', {'id': debt_id})['error'] == 'debt_closed')
big = bank.eval(f"Debts.Add({ids[1]}, {{ amount = 5000, title = 'Sachbeschädigung', kind = 'fine' }})")
check('zu wenig auf dem Konto: not_enough_money', P(1, 'phone_bank_pay', {'id': big})['error'] == 'not_enough_money')

print('Notruf-App')
r = P(1, 'phone_dispatch')
check('Dienste mit Einheiten im Dienst', r['ok'] and r['data']['services'] == [{'key': 'ems', 'label': 'Rettungsdienst', 'units': 0}] and r['data']['default'] == 'ems' and r['data']['textMin'] > 0, r)
check('zu kurzer Text: Fehler der Leitstelle kommt durch', P(1, 'phone_dispatch_send', {'service': 'ems', 'text': 'ab'})['error'] == 'text_too_short')
r = P(1, 'phone_dispatch_send', {'service': 'ems', 'text': 'Autounfall am Legion Square, eine Person verletzt'})
row = env.sql('SELECT * FROM dispatch_calls ORDER BY id DESC LIMIT 1')
check('Notruf geht an die Leitstelle, mit Position vom Server', r['ok'] and r['data']['service'] == 'Rettungsdienst' and row and row[0]['caller_id'] == ids[1]
      and 'Autounfall' in row[0]['text'] and abs(row[0]['x'] - 215.5) < 0.01, (r, row))
check('gleich noch einer: Wartezeit der Leitstelle', P(1, 'phone_dispatch_send', {'service': 'ems', 'text': 'Noch ein Notruf hinterher'})['error'] == 'cooldown')

print('Admin-Ansicht')
check('ohne Rechte: no_permission', P(2, 'phone_open', {'characterId': ids[1]})['error'] == 'no_permission')
env.command(0, f'setrank {ids[4]} assistant')
a = P(4, 'phone_open', {'characterId': ids[2]})
ad = a['data'] if a['ok'] else {}
check('Assistant sieht Pauls Handy: Name, Nummer, nur lesen, keine Apps', a['ok'] and ad['admin'] is True and ad['name'] == 'Paul Krüger' and ad['number'] == num[ids[2]]
      and ad['apps'] == {'bank': False, 'dispatch': False} and ad.get('call') is None, a)
t = P(4, 'phone_thread', {'number': num[ids[1]]})['data']
check('Admin sieht auch den gelöschten Chat, markiert', len(t['messages']) >= 6 and t['messages'][0].get('hidden') is True and t['messages'][-1].get('hidden') is None, t['messages'][:1])
unread_before = env.sql("SELECT COUNT(*) AS n FROM phone_messages WHERE owner_id = %s AND read_at IS NULL", (ids[4],))[0]['n']
check('Admin-Blick markiert nichts als gelesen und ändert nichts', P(4, 'phone_message_send', {'number': num[ids[1]], 'text': 'Als Paul'})['error'] == 'read_only'
      and P(4, 'phone_contact_save', {'name': 'X', 'number': num[ids[3]]})['error'] == 'read_only' and P(4, 'phone_thread_delete', {'number': num[ids[1]]})['error'] == 'read_only'
      and P(4, 'phone_call_start', {'number': num[ids[1]]})['error'] == 'read_only' and P(4, 'phone_bank')['error'] == 'no_bank')
check('unbekannte ID: not_found', P(4, 'phone_open', {'characterId': 99999})['error'] == 'not_found')
check('Mira ist offline: geht trotzdem', P(4, 'phone_open', {'characterId': ids[3]})['data']['name'] == 'Mira Schulz')
P(4, 'phone_close')
own = P(4, 'phone_open')
check('danach wieder das eigene Handy', own['ok'] and own['data']['number'] == num[ids[4]] and own['data'].get('admin') is None and unread_before == 2)
env.command(4, f'nummer {num[ids[1]][:3]} {num[ids[1]][3:]}')
check('/nummer: wem gehört sie', any(f'gehört ID {ids[1]} (Lena Hoffmann)' in t for t in notes(4)), notes(4)[-1:])
before = len(notes(2))
env.command(2, f'nummer {num[ids[1]]}')
check('/nummer ohne Rechte: keine Auskunft', not any('gehört ID' in t for t in notes(2)[before:]))

print('Zustand und Exports')
P(2, 'phone_call_start', {'number': num[ids[1]]})
env.call(1, 'death_report', {})
check('bewusstlos: Handy geht nicht', P(1, 'phone_open')['error'] == 'is_dead' and P(1, 'phone_call_answer')['error'] == 'is_dead'
      and P(1, 'phone_message_send', {'number': num[ids[2]], 'text': 'Hilfe'})['error'] == 'is_dead')
check('Auflegen geht immer', P(1, 'phone_call_end')['ok'] and pushes(2, 'call')[-1]['ended']['reason'] == 'declined')
check('Bewusstlose sind nicht erreichbar', P(2, 'phone_call_start', {'number': num[ids[1]]})['error'] == 'unreachable')
other = env.runtimes['core_factions']
check('Export GetNumber und GetNumberOwner', other.eval(f"exports.core_phone:GetNumber({ids[2]})") == num[ids[2]]
      and other.eval(f"exports.core_phone:GetNumberOwner('{num[ids[2]]}')") == ids[2] and other.eval("exports.core_phone:GetNumber(99999)") is None)
check('Export HasPhone', other.eval(f"exports.core_phone:HasPhone({ids[2]})") is True and other.eval(f"exports.core_phone:HasPhone({ids[3]})") is False)
check('Export SendServiceMessage', other.eval(f"exports.core_phone:SendServiceMessage({ids[2]}, 'Bank', 'Deine Rechnung ist fällig.')") is True
      and pushes(2, 'message')[-1]['number'] == 'Bank' and other.eval(f"exports.core_phone:SendServiceMessage({ids[2]}, '123456', 'x')") is False)
t = P(2, 'phone_thread', {'number': 'Bank'})
check('Dienst-Nachricht steht als eigener Chat da, antworten geht nicht', t['ok'] and t['data']['messages'][0]['text'] == 'Deine Rechnung ist fällig.'
      and P(2, 'phone_message_send', {'number': 'Bank', 'text': 'Danke'})['error'] == 'invalid_number')

print('Log')
env.flush_log()
actions = {l['action'] for l in env.sql("SELECT action FROM audit_log WHERE category = 'phone'")}
check('Kategorie phone: eSIM, Erstausstattung, Telefonat, Chat gelöscht, Kontakt gelöscht, Admin-Blick',
      {'sim_activate', 'starter_phone', 'call', 'thread_delete', 'contact_delete', 'admin_view'} <= actions, actions)
acc1 = env.sql('SELECT account_id FROM characters WHERE id = %s', (ids[1],))[0]['account_id']
lg = env.call(4, 'admin_logs', {'accountId': acc1, 'category': 'phone', 'page': 0})
check('steht in der Akte der Person', lg['ok'] and {'sim_activate', 'call'} <= {e['action'] for e in lg['data']['entries']}, lg)

print(f'\n{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
