"""Test fuer core_bank gegen MariaDB: Konto mit Kontonummer, Filiale und Bankautomat mit Abstand und Grenzen,
Einzahlen, Auszahlen, Ueberweisen (auch offline), Kontoauszug mit fremden Buchungen, Schulden mit Frist, Mahngebuehr
und Einzug, Rechnung einer Organisation mit Zustimmung, Admin-Ansicht, Exports fuer andere Scripts, Log."""
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


env = Env(inventory=True, debug=True, extra=['core_lib', 'core_factions', 'core_bank'])
for name in ('core_lib', 'core_factions', 'core_bank'):
    env.runtimes[name].execute('Config.Network.MaxRequestsPerSecond = 0')
env.inv.execute('Config.Network.MaxRequestsPerSecond = 0')
bank = env.runtimes['core_bank']
factions = env.runtimes['core_factions']
B = lambda src, name, data=None: env.rcall('core_bank', src, name, data)
F = lambda src, name, data=None: env.rcall('core_factions', src, name, data)

BRANCH = [149.9, -1040.5, 29.4]      # Filiale 1, Legion Square
ATM = [-56.0, -1752.0, 29.4]
LOCKER = [298.6, -598.3, 43.3]
FAR = [1500.0, 1500.0, 50.0]
people = {1: ('Lena', 'Hoffmann'), 2: ('Paul', 'Krüger'), 3: ('Mira', 'Schulz'), 4: ('Tom', 'Becker'), 5: ('Sara', 'Yilmaz')}
ids = {}
for src, (first, last) in people.items():
    env.connect(src, [f'license:{src}'])
    env.call(src, 'auth_register', {'email': f'{src}@t.de', 'password': 'passwort123'})
    ids[src] = env.call(src, 'char_create', {'firstname': first, 'lastname': last, 'dateOfBirth': '1990-01-01', 'gender': 'male'})['data']['characterId']
env.sql('UPDATE characters SET cash = 3000 WHERE id = %s', (ids[1],))
for src in people:
    env.call(src, 'char_select', {'id': ids[src]})
env.tick(1500)
for src in people:
    env.positions[src] = list(FAR)


def money(src, account):
    return env.to_py(env.lua.eval(f"Core.GetMoney({src}, '{account}')"))


def bank_of(cid):
    return int(env.sql('SELECT bank FROM characters WHERE id = %s', (cid,))[0]['bank'])


def notes(src):
    return [d.get('text', '') for d in env.events_for(src, 'core:notify')]


def rows(cid):
    return env.sql('SELECT * FROM bank_transactions WHERE character_id = %s ORDER BY id', (cid,))


def debt(debt_id):
    return env.sql('SELECT * FROM bank_debts WHERE id = %s', (debt_id,))[0]


def lua_debt(cid, fields):
    """Debts.Add in der Resource aufrufen, gibt Nummer und Fehlercode zurueck."""
    result = bank.eval(f'table.pack(Debts.Add({cid}, {fields}))')
    return result[1], result[2]


def cash_balance():
    return env.to_py(factions.eval("Factions.GetBalance('ems')")) or 0


print('Konto und Sitzung')
numbers = {r['character_id']: r['number'] for r in env.sql('SELECT character_id, number FROM bank_accounts')}
check('jeder Charakter hat beim Einloggen eine Kontonummer mit 8 Ziffern', len(numbers) == 5 and all(len(n) == 8 and n.isdigit() for n in numbers.values()), numbers)
check('Kontonummern sind verschieden', len(set(numbers.values())) == 5)
check('ohne Sitzung: no_session', B(1, 'bank_overview')['error'] == 'no_session')
check('Filiale zu weit weg: too_far', B(1, 'bank_open', {'channel': 'bank', 'branch': 1})['error'] == 'too_far')
check('unbekannte Filiale: invalid_input', B(1, 'bank_open', {'channel': 'bank', 'branch': 99})['error'] == 'invalid_input')
check('unbekannter Kanal: invalid_input', B(1, 'bank_open', {'channel': 'handy'})['error'] == 'invalid_input')
env.positions[1] = list(BRANCH)
o = B(1, 'bank_open', {'channel': 'bank', 'branch': 1})
ov = o['data']['overview'] if o['ok'] else {}
check('Filiale: Konto mit Name, Nummer, Kontostand und Bargeld', o['ok'] and ov['name'] == 'Lena Hoffmann' and ov['number'] == numbers[ids[1]]
      and ov['balance'] == 2500 and ov['cash'] == 3000 and ov['debts'] == {'count': 0, 'total': 0, 'overdue': 0}, o)
check('Name der Bank und Grenzen kommen mit', o['data']['bankName'] == 'Fleeca Bank' and o['data']['purposeMax'] == 60 and o['data'].get('atm') is None, o['data'])

print('Einzahlen und Auszahlen in der Filiale')
r = B(1, 'bank_deposit', {'amount': 400})
check('400 einzahlen: Konto 2900, Bargeld 2600', r['ok'] and r['data']['overview']['balance'] == 2900 and r['data']['overview']['cash'] == 2600
      and bank_of(ids[1]) == 2900 and money(1, 'cash') == 2600, r)
last = rows(ids[1])[-1]
check('im Kontoauszug: Einzahlung in der Filiale, +400, Stand 2900', last['kind'] == 'deposit' and last['amount'] == 400 and last['balance'] == 2900
      and last['channel'] == 'bank' and last['text'] == 'Einzahlung in der Filiale', last)
for bad in (0, -5, 1.5, 'abc', None, 10 ** 12):
    check(f'ungültiger Betrag {bad!r}: invalid_amount', B(1, 'bank_deposit', {'amount': bad})['error'] == 'invalid_amount')
check('mehr als Bargeld: not_enough_cash', B(1, 'bank_deposit', {'amount': 5000})['error'] == 'not_enough_cash' and bank_of(ids[1]) == 2900)
r = B(1, 'bank_withdraw', {'amount': 900})
check('900 auszahlen: Konto 2000, Bargeld 3500', r['ok'] and bank_of(ids[1]) == 2000 and money(1, 'cash') == 3500
      and rows(ids[1])[-1]['amount'] == -900 and rows(ids[1])[-1]['kind'] == 'withdraw', r)
check('mehr als Kontostand: not_enough_money', B(1, 'bank_withdraw', {'amount': 2001})['error'] == 'not_enough_money' and bank_of(ids[1]) == 2000)
check('nur eine Zeile je Buchung (kein doppelter Eintrag durch das Ereignis der Core)', len(rows(ids[1])) == 2, rows(ids[1]))
env.positions[1] = list(FAR)
check('weggegangen: too_far, Sitzung ist zu', B(1, 'bank_deposit', {'amount': 10})['error'] == 'too_far' and B(1, 'bank_overview')['error'] == 'no_session')
env.positions[1] = list(BRANCH)
B(1, 'bank_open', {'channel': 'bank', 'branch': 1})

print('Überweisen')
check('Kontonummer mit falscher Länge: invalid_number', B(1, 'bank_lookup', {'number': '1234'})['error'] == 'invalid_number')
unknown = next(str(n) for n in range(10000000, 10000100) if str(n) not in numbers.values())
check('unbekannte Kontonummer: unknown_account', B(1, 'bank_lookup', {'number': unknown})['error'] == 'unknown_account')
check('eigene Kontonummer: same_account', B(1, 'bank_lookup', {'number': numbers[ids[1]]})['error'] == 'same_account')
spaced = numbers[ids[2]][:4] + ' ' + numbers[ids[2]][4:]
r = B(1, 'bank_lookup', {'number': spaced})
check('Empfänger prüfen (mit Leerzeichen getippt): Paul Krüger', r['ok'] and r['data'] == {'name': 'Paul Krüger', 'number': numbers[ids[2]]}, r)
r = B(1, 'bank_transfer', {'number': spaced, 'amount': 750, 'purpose': '  Miete\nNovember  '})
check('750 an Paul: Lena 1250, Paul 3250', r['ok'] and r['data']['overview']['balance'] == 1250 and bank_of(ids[1]) == 1250 and bank_of(ids[2]) == 3250
      and r['data']['to']['name'] == 'Paul Krüger', r)
out, inc = rows(ids[1])[-1], rows(ids[2])[-1]
check('Kontoauszug Lena: Überweisung an Paul mit Zweck', out['kind'] == 'transfer_out' and out['amount'] == -750 and out['text'] == 'Miete November'
      and out['other_name'] == 'Paul Krüger' and out['other_number'] == numbers[ids[2]] and out['balance'] == 1250, out)
check('Kontoauszug Paul: Eingang von Lena', inc['kind'] == 'transfer_in' and inc['amount'] == 750 and inc['other_name'] == 'Lena Hoffmann'
      and inc['other_number'] == numbers[ids[1]] and inc['balance'] == 3250, inc)
check('Paul bekommt eine Meldung', any('Geldeingang' in t and '750 $' in t and 'Lena Hoffmann' in t for t in notes(2)), notes(2)[-2:])
check('ohne Zweck steht "Überweisung"', B(1, 'bank_transfer', {'number': numbers[ids[2]], 'amount': 50})['ok'] and rows(ids[1])[-1]['text'] == 'Überweisung')
check('mehr als Kontostand: not_enough_money', B(1, 'bank_transfer', {'number': numbers[ids[2]], 'amount': 99999})['error'] == 'not_enough_money'
      and bank_of(ids[1]) == 1200 and bank_of(ids[2]) == 3300)
check('an sich selbst: same_account', B(1, 'bank_transfer', {'number': numbers[ids[1]], 'amount': 10})['error'] == 'same_account')
check('über der Grenze: invalid_amount', B(1, 'bank_transfer', {'number': numbers[ids[2]], 'amount': 1000001})['error'] == 'invalid_amount')
env.lua.globals().DropPlayer(5, 'Test')
env.tick(200)
r = B(1, 'bank_transfer', {'number': numbers[ids[5]], 'amount': 200, 'purpose': 'Schulden zurück'})
check('an Sara, die offline ist: kommt an', r['ok'] and bank_of(ids[5]) == 2700 and rows(ids[5])[-1]['kind'] == 'transfer_in', r)
rec = B(1, 'bank_overview')['data']['overview']['recipients']
check('letzte Empfänger: Sara zuerst, dann Paul, jeder einmal', [x['name'] for x in rec] == ['Sara Yilmaz', 'Paul Krüger'], rec)

print('Buchungen anderer Scripts stehen im Kontoauszug')
env.command(0, f'givemoney bank {ids[1]} 300')
env.tick(300)
last = rows(ids[1])[-1]
check('Admin-Buchung der Core: Gutschrift mit Grund', last['kind'] == 'credit' and last['amount'] == 300 and 'givemoney' in last['text'] and last['balance'] == 1300, last)
env.command(0, f'removemoney bank {ids[1]} 100')
env.tick(300)
check('Abbuchung der Core: Lastschrift', rows(ids[1])[-1]['kind'] == 'debit' and rows(ids[1])[-1]['amount'] == -100 and bank_of(ids[1]) == 1200)
s = B(1, 'bank_statement', {'page': 1})
check('Kontoauszug: neueste zuerst, mit Datum', s['ok'] and s['data']['entries'][0]['kind'] == 'debit' and len(s['data']['entries'][0]['at']) == 16
      and s['data']['more'] is False, s['data']['entries'][:1])
check('Filter Eingänge und Ausgänge', all(e['amount'] > 0 for e in B(1, 'bank_statement', {'filter': 'in'})['data']['entries'])
      and all(e['amount'] < 0 for e in B(1, 'bank_statement', {'filter': 'out'})['data']['entries']))
bank.execute('Config.Bank.PageSize = 3')
p1, p2 = B(1, 'bank_statement', {'page': 1})['data'], B(1, 'bank_statement', {'page': 2})['data']
check('seitenweise: 3 je Seite, mehr vorhanden', len(p1['entries']) == 3 and p1['more'] is True and p2['entries'][0]['id'] < p1['entries'][-1]['id'], (p1, p2))
bank.execute('Config.Bank.PageSize = 20')

print('Bankautomat')
B(1, 'bank_close')
env.positions[1] = [ATM[0] + 1.0, ATM[1], ATM[2]]
check('Automat zu weit weg gemeldet: too_far', B(1, 'bank_open', {'channel': 'atm', 'atm': {'x': 500, 'y': 500, 'z': 30}})['error'] == 'too_far')
check('Automat ohne Position: invalid_input', B(1, 'bank_open', {'channel': 'atm', 'atm': {'x': 'a'}})['error'] == 'invalid_input')
o = B(1, 'bank_open', {'channel': 'atm', 'atm': {'x': ATM[0], 'y': ATM[1], 'z': ATM[2]}})
check('Automat: Kontostand, Grenzen, noch 20.000 heute', o['ok'] and o['data']['overview']['balance'] == 1200 and o['data']['atm']['withdrawMax'] == 5000
      and o['data']['overview']['atmRemaining'] == 20000 and 'recipients' not in o['data']['overview'], o)
check('Automat: höchstens 5 letzte Buchungen', len(o['data']['overview']['recent']) == 5)
r = B(1, 'bank_withdraw', {'amount': 200})
check('200 abheben am Automaten', r['ok'] and bank_of(ids[1]) == 1000 and rows(ids[1])[-1]['channel'] == 'atm'
      and rows(ids[1])[-1]['text'] == 'Auszahlung am Bankautomaten' and r['data']['overview']['atmRemaining'] == 19800, r)
check('über 5.000 auf einmal: over_limit', B(1, 'bank_withdraw', {'amount': 5001})['error'] == 'over_limit')
bank.execute('Config.Bank.Atm.DailyWithdraw = 500')
check('Tagesgrenze erreicht: daily_limit', B(1, 'bank_withdraw', {'amount': 400})['error'] == 'daily_limit' and bank_of(ids[1]) == 1000)
check('bis zur Tagesgrenze geht', B(1, 'bank_withdraw', {'amount': 300})['ok'] and B(1, 'bank_overview')['data']['overview']['atmRemaining'] == 0)
bank.execute('Config.Bank.Atm.DailyWithdraw = 20000')
check('einzahlen am Automaten', B(1, 'bank_deposit', {'amount': 300})['ok'] and bank_of(ids[1]) == 1000 and rows(ids[1])[-1]['text'] == 'Einzahlung am Bankautomaten')
check('über 10.000 einzahlen: over_limit', B(1, 'bank_deposit', {'amount': 10001})['error'] == 'over_limit')
bank.execute('Config.Bank.Atm.Deposit = false')
check('Einzahlen am Automaten abgeschaltet: not_here', B(1, 'bank_deposit', {'amount': 10})['error'] == 'not_here')
bank.execute('Config.Bank.Atm.Deposit = true')
check('Überweisen, Kontoauszug und Schulden gibt es am Automaten nicht', B(1, 'bank_transfer', {'number': numbers[ids[2]], 'amount': 10})['error'] == 'not_here'
      and B(1, 'bank_statement')['error'] == 'not_here' and B(1, 'bank_debts')['error'] == 'not_here' and B(1, 'bank_debt_pay', {'id': 1})['error'] == 'not_here')
B(1, 'bank_close')

print('Schulden')
env.positions[1] = list(BRANCH)
B(1, 'bank_open', {'channel': 'bank', 'branch': 1})
d1, err = lua_debt(ids[1], "{ amount = 600, title = 'Rotlicht überfahren', kind = 'fine' }")
row = debt(d1)
check('Strafe des Staats anlegen', d1 and row['kind'] == 'fine' and row['creditor'] == 'state' and row['creditor_label'] == 'Staat San Andreas'
      and row['amount'] == 600 and row['status'] == 'open' and row['resource'] == 'core_bank', row)
check('Lena bekommt eine Meldung mit Frist', any('Neue Strafe über 600 $' in t and 'Rotlicht' in t for t in notes(1)), notes(1)[-1:])
check('Frist 72 Stunden', 71 <= env.sql('SELECT TIMESTAMPDIFF(HOUR, NOW(), due_at) AS h FROM bank_debts WHERE id = %s', (d1,))[0]['h'] <= 72)
check('ungültig: Betrag 0, ohne Titel, unbekannte ID', lua_debt(ids[1], "{ amount = 0, title = 'x' }")[1] == 'invalid_amount'
      and lua_debt(ids[1], "{ amount = 5 }")[1] == 'invalid_input' and lua_debt(99999, "{ amount = 5, title = 'x' }")[1] == 'not_found')
d2, _ = lua_debt(ids[1], "{ amount = 250, title = 'Behandlung Bluthochdruck', kind = 'invoice', creditor = 'ems', dueHours = 24 }")
check('Rechnung des EMS: Name der Organisation als Gläubiger', debt(d2)['creditor'] == 'ems' and debt(d2)['creditor_label'] == 'Emergency Medical Service', debt(d2))
o = B(1, 'bank_overview')['data']['overview']
check('Übersicht: 2 offen, zusammen 850', o['debts'] == {'count': 2, 'total': 850, 'overdue': 0}, o['debts'])
lst = B(1, 'bank_debts')['data']
check('Liste: nach Frist sortiert, Rechnung (24 h) zuerst', [d['id'] for d in lst['debts']] == [d2, d1] and lst['debts'][0]['kindLabel'] == 'Rechnung'
      and lst['debts'][0]['rest'] == 250 and lst['debts'][0]['overdue'] is False, lst)
before = cash_balance()
r = B(1, 'bank_debt_pay', {'id': d2, 'amount': 100})
check('100 anzahlen: Rest 150, Konto 900', r['ok'] and r['data']['debt']['rest'] == 150 and r['data']['debt']['status'] == 'open' and bank_of(ids[1]) == 900, r)
check('Geld geht in die Kasse des EMS', cash_balance() == before + 100, (before, cash_balance()))
check('im Kontoauszug: Rechnung, Gläubiger EMS', rows(ids[1])[-1]['kind'] == 'debt' and rows(ids[1])[-1]['amount'] == -100
      and rows(ids[1])[-1]['other_name'] == 'Emergency Medical Service' and rows(ids[1])[-1]['text'] == 'Rechnung: Behandlung Bluthochdruck', rows(ids[1])[-1])
check('mehr als der Rest: invalid_amount', B(1, 'bank_debt_pay', {'id': d2, 'amount': 151})['error'] == 'invalid_amount')
r = B(1, 'bank_debt_pay', {'id': d2})
check('ohne Betrag: Rest bezahlen, erledigt', r['ok'] and r['data']['debt']['status'] == 'paid' and r['data']['paid'] == 150 and bank_of(ids[1]) == 750
      and debt(d2)['closed_at'] is not None and cash_balance() == before + 250, r)
check('erledigte nicht noch einmal: debt_closed', B(1, 'bank_debt_pay', {'id': d2})['error'] == 'debt_closed')
check('fremde Schuld: not_found', B(2, 'bank_overview')['error'] == 'no_session' and B(1, 'bank_debt_pay', {'id': 999})['error'] == 'not_found')
d3, _ = lua_debt(ids[2], "{ amount = 100, title = 'Parken im Halteverbot', kind = 'fine' }")
check('Schuld einer anderen Person bezahlen: not_found', B(1, 'bank_debt_pay', {'id': d3})['error'] == 'not_found')
check('Strafe (600) bei 750 auf dem Konto bezahlen', B(1, 'bank_debt_pay', {'id': d1})['ok'] and bank_of(ids[1]) == 150)
check('Staat: Geld ist weg, Kasse unverändert', cash_balance() == before + 250)
closed = B(1, 'bank_debts', {'status': 'closed'})['data']['debts']
check('erledigte Liste: beide, neueste zuerst', [d['id'] for d in closed] == [d2, d1] and closed[0]['status'] == 'paid' and closed[0]['closed'], closed)
d4, _ = lua_debt(ids[1], "{ amount = 400, title = 'Zu schnell gefahren', kind = 'fine' }")
check('zu wenig auf dem Konto: not_enough_money, nichts gebucht', B(1, 'bank_debt_pay', {'id': d4})['error'] == 'not_enough_money'
      and bank_of(ids[1]) == 150 and debt(d4)['paid'] == 0)

print('Frist: Mahngebühr und Einzug')
env.sql('UPDATE bank_debts SET due_at = NOW() - INTERVAL 1 HOUR WHERE id = %s', (d4,))
env.sql('UPDATE characters SET bank = 700 WHERE id = %s', (ids[1],))
env.lua.execute(f"Core.GetCharacter(1).money.bank = 700")
bank.execute('Debts.Sweep()')
env.tick(100)
row = debt(d4)
check('nach der Frist: 10 % Mahngebühr (40), einmal', row['fee'] == 40 and row['reminded_at'] is not None, row)
check('Einzug: 200 vom Konto, 500 bleiben stehen', row['paid'] == 200 and row['status'] == 'open' and bank_of(ids[1]) == 500, (row['paid'], bank_of(ids[1])))
check('im Kontoauszug als Einzug', rows(ids[1])[-1]['kind'] == 'collect' and rows(ids[1])[-1]['amount'] == -200, rows(ids[1])[-1])
check('Meldungen: Frist abgelaufen und Einzug', any('Frist abgelaufen' in t and 'Mahngebühr 40 $' in t for t in notes(1))
      and any('eingezogen' in t and 'Offen bleiben 240 $' in t for t in notes(1)), notes(1)[-2:])
o = B(1, 'bank_overview')['data']['overview']
check('Übersicht: 1 überfällig, 240 offen', o['debts'] == {'count': 1, 'total': 240, 'overdue': 1}, o['debts'])
bank.execute('Debts.Sweep()')
check('nächster Lauf: keine zweite Gebühr, nichts mehr zu holen', debt(d4)['fee'] == 40 and debt(d4)['paid'] == 200 and bank_of(ids[1]) == 500)
env.sql('UPDATE characters SET bank = 5000 WHERE id = %s', (ids[1],))
env.lua.execute(f"Core.GetCharacter(1).money.bank = 5000")
bank.execute('Debts.Sweep()')
check('wieder Geld da: Rest eingezogen, erledigt', debt(d4)['status'] == 'paid' and debt(d4)['closed_by'] == 'Einzug der Bank' and bank_of(ids[1]) == 4760, debt(d4))
env.sql('UPDATE bank_debts SET due_at = NOW() - INTERVAL 1 HOUR WHERE id = %s', (d3,))
env.lua.globals().DropPlayer(2, 'Test')
env.tick(200)
bank.execute('Debts.Sweep()')
check('Einzug geht auch offline (Paul): 110 mit Gebühr', debt(d3)['status'] == 'paid' and debt(d3)['fee'] == 10 and bank_of(ids[2]) == 3300 - 110, (debt(d3), bank_of(ids[2])))
bank.execute('Config.Bank.Debts.AutoCollect = false')
d5, _ = lua_debt(ids[1], "{ amount = 100, title = 'Ruhestörung', kind = 'fine' }")
env.sql('UPDATE bank_debts SET due_at = NOW() - INTERVAL 1 HOUR WHERE id = %s', (d5,))
bank.execute('Debts.Sweep()')
check('Einzug abgeschaltet: nur Mahngebühr', debt(d5)['fee'] == 10 and debt(d5)['paid'] == 0 and bank_of(ids[1]) == 4760)
bank.execute('Config.Bank.Debts.AutoCollect = true')

print('Organisation stellt eine Rechnung aus (G-Menü)')
env.command(0, f'setorga {ids[3]} ems 5')
env.tick(600)
env.positions[3] = list(LOCKER)
check('nicht im Dienst: not_on_duty', B(3, 'bank_issuer')['error'] == 'not_on_duty')
check('Mira tritt den Dienst an', F(3, 'faction_duty')['data']['onDuty'] is True)
check('kein Mitglied: no_permission', B(1, 'bank_issuer')['error'] == 'no_permission')
r = B(3, 'bank_issuer')
check('Mira darf Rechnungen ausstellen (Rang 5, Recht ab 3)', r['ok'] and r['data']['kind'] == 'invoice' and r['data']['max'] == 25000, r)
env.positions[1] = [LOCKER[0] + 1.5, LOCKER[1], LOCKER[2]]
env.consent[1] = 'no'
check('Lena lehnt ab: consent_declined, keine Schuld', B(3, 'bank_issue', {'serverId': 1, 'amount': 320, 'title': 'Transport ins Krankenhaus'})['error'] == 'consent_declined'
      and len(env.sql("SELECT id FROM bank_debts WHERE creditor = 'ems' AND status = 'open'")) == 0)
env.consent[1] = 'yes'
r = B(3, 'bank_issue', {'serverId': 1, 'amount': 320, 'title': 'Transport ins Krankenhaus'})
issued = debt(r['data']['id']) if r['ok'] else {}
check('Lena stimmt zu: Rechnung über 320 an das EMS, ausgestellt von Mira', r['ok'] and issued['creditor'] == 'ems' and issued['kind'] == 'invoice'
      and issued['amount'] == 320 and issued['issued_by'] == 'Mira Schulz' and issued['issued_by_id'] == ids[3], r)
question = [d for s, n, d in env.events if n == 'core:consent' and s == 1][-1]
check('die Frage nennt Betrag und Grund', '320 $' in question['text'] and 'Transport' in question['text'], question)
check('über der Grenze der Organisation: invalid_amount', B(3, 'bank_issue', {'serverId': 1, 'amount': 25001, 'title': 'x y'})['error'] == 'invalid_amount')
check('ohne Grund: invalid_input', B(3, 'bank_issue', {'serverId': 1, 'amount': 10, 'title': '   '})['error'] == 'invalid_input')
check('sich selbst: target_offline', B(3, 'bank_issue', {'serverId': 3, 'amount': 10, 'title': 'Test'})['error'] == 'target_offline')
env.positions[1] = list(BRANCH)
check('zu weit weg: too_far', B(3, 'bank_issue', {'serverId': 1, 'amount': 10, 'title': 'Test'})['error'] == 'too_far')
env.tick(300)
logs = env.sql("SELECT area, text, actor_name, target_id FROM faction_logs WHERE faction = 'ems' AND action = 'debt_issue'")
check('im Protokoll der Organisation (Kasse): wer, an wen, was', len(logs) == 1 and logs[0]['area'] == 'kasse' and 'Rechnung über 320 $' in logs[0]['text']
      and logs[0]['actor_name'] == 'Mira Schulz' and logs[0]['target_id'] == ids[1], logs)

print('Admin-Ansicht')
check('ohne Rechte: no_permission', B(3, 'bank_open', {'channel': 'admin', 'characterId': ids[1]})['error'] == 'no_permission')
env.command(0, f'setrank {ids[4]} assistant')
a = B(4, 'bank_open', {'channel': 'admin', 'characterId': ids[1]})
check('Assistant sieht Lenas Konto, darf nichts ändern', a['ok'] and a['data']['admin'] is True and a['data'].get('canManage') is None
      and a['data']['overview']['name'] == 'Lena Hoffmann' and a['data']['overview']['balance'] == 4760 and 'cash' not in a['data']['overview'], a)
check('unbekannte ID: not_found', B(4, 'bank_open', {'channel': 'admin', 'characterId': 99999})['error'] == 'not_found')
B(4, 'bank_open', {'channel': 'admin', 'characterId': ids[1]})
check('Admin liest Kontoauszug und Schulden', B(4, 'bank_statement')['ok'] and len(B(4, 'bank_debts')['data']['debts']) == 2)
check('Admin-Ansicht bewegt kein Geld', B(4, 'bank_deposit', {'amount': 10})['error'] == 'not_here' and B(4, 'bank_withdraw', {'amount': 10})['error'] == 'not_here'
      and B(4, 'bank_transfer', {'number': numbers[ids[2]], 'amount': 10})['error'] == 'not_here' and B(4, 'bank_debt_pay', {'id': d5})['error'] == 'not_here')
check('ohne Recht: Forderung eintragen und erlassen no_permission', B(4, 'bank_debt_add', {'amount': 50, 'title': 'Test'})['error'] == 'no_permission'
      and B(4, 'bank_debt_cancel', {'id': d5})['error'] == 'no_permission')
env.command(0, f'setrank {ids[4]} senior')
a = B(4, 'bank_open', {'channel': 'admin', 'characterId': ids[1]})
check('Senior ohne Admin-Dienst: nur lesen', a['ok'] and a['data'].get('canManage') is None and B(4, 'bank_debt_cancel', {'id': d5})['error'] == 'no_permission', a['data'].get('canManage'))
env.command(4, 'aduty')
a = B(4, 'bank_open', {'channel': 'admin', 'characterId': ids[1]})
check('Senior im Admin-Dienst: darf korrigieren', a['ok'] and a['data']['canManage'] is True)
r = B(4, 'bank_debt_cancel', {'id': d5, 'reason': 'Falscher Fahrer'})
check('erlassen: mit Grund und Admin-Name', r['ok'] and debt(d5)['status'] == 'cancelled' and debt(d5)['closed_by'] == 'Admin Tom Becker'
      and debt(d5)['close_reason'] == 'Falscher Fahrer' and any('erlassen' in t for t in notes(1)), debt(d5))
check('Schuld einer anderen Person in dieser Ansicht: not_found', B(4, 'bank_debt_cancel', {'id': d3})['error'] == 'not_found')
r = B(4, 'bank_debt_add', {'amount': 900, 'title': 'Sachbeschädigung am Rathaus', 'kind': 'fine', 'dueHours': 48})
check('Forderung eintragen: als Admin gekennzeichnet', r['ok'] and r['data']['debt']['issuedBy'] == 'Admin Tom Becker' and r['data']['debt']['amount'] == 900
      and r['data']['overview']['debts']['count'] == 2, r)
env.command(4, f'schuld {ids[2]} 500 Rotlicht überfahren')
row = env.sql('SELECT * FROM bank_debts WHERE character_id = %s ORDER BY id DESC LIMIT 1', (ids[2],))[0]
check('/schuld 500 für Paul (offline): Strafe des Staats', row['amount'] == 500 and row['title'] == 'Rotlicht überfahren' and row['kind'] == 'fine'
      and row['issued_by'] == 'Admin Tom Becker', row)
before_count = len(env.sql('SELECT id FROM bank_debts'))
env.command(3, f'schuld {ids[2]} 500 Test')
check('/schuld ohne Rechte: nichts passiert', len(env.sql('SELECT id FROM bank_debts')) == before_count)
B(4, 'bank_close')

print('Zustand und Exports')
r = env.call(1, 'death_report', {'killer': 3, 'weapon': 0, 'indirect': True, 'byVehicle': True})
check('Tod nach Anfahren: "Getötet von" nennt die ID des Fahrers', r['ok'] and r['data']['killerId'] == ids[3], r)
env.flush_log()
died = env.sql("SELECT data FROM audit_log WHERE category = 'death' AND character_id = %s ORDER BY id DESC LIMIT 1", (ids[1],))[0]['data']
check('im Log steht: indirekt und mit Fahrzeug', '"killerIndirect":true' in died.replace(' ', '') and '"killerByVehicle":true' in died.replace(' ', '')
      and '"killerName":"Mira Schulz"' in died.replace(': ', ':'), died)
check('bewusstlos: is_dead', B(1, 'bank_overview')['error'] == 'is_dead')
B(1, 'bank_close')
check('bewusstlos öffnen: is_dead', B(1, 'bank_open', {'channel': 'bank', 'branch': 1})['error'] == 'is_dead')
acc = env.to_py(factions.eval(f"exports.core_bank:GetAccount({ids[5]})"))
check('Export GetAccount (offline): Name, Nummer, Kontostand', acc == {'characterId': ids[5], 'name': 'Sara Yilmaz', 'number': numbers[ids[5]], 'balance': 2700}, acc)
ovw = env.to_py(factions.eval(f"exports.core_bank:GetOverview({ids[1]}, 3)"))
check('Export GetOverview: wie in der Filiale, für das Handy', ovw['balance'] == bank_of(ids[1]) and len(ovw['recent']) == 3 and ovw['debts']['count'] == 2, ovw)
tr = env.to_py(factions.eval(f"exports.core_bank:GetTransactions({ids[1]}, {{ page = 1, filter = 'in' }})"))
check('Export GetTransactions', tr['entries'] and all(e['amount'] > 0 for e in tr['entries']))
res = factions.eval(f"table.pack(exports.core_bank:Transfer({ids[1]}, '{numbers[ids[2]]}', 60, 'Vom Handy', {{ channel = 'phone' }}))")
check('Export Transfer mit Kanal phone', res[1] is not None and rows(ids[1])[-1]['channel'] == 'phone' and rows(ids[1])[-1]['amount'] == -60, env.to_py(res))
new_id = factions.eval(f"exports.core_bank:AddDebt({ids[5]}, {{ amount = 75, title = 'Mahnung Bücherei', kind = 'fee' }})")
check('Export AddDebt aus einem anderen Script: resource steht dran', new_id and debt(new_id)['resource'] == 'core_factions' and debt(new_id)['kind'] == 'fee', debt(new_id) if new_id else None)
summary = env.to_py(factions.eval(f"exports.core_bank:GetDebtSummary({ids[5]})"))
check('Export GetDebtSummary', summary == {'count': 1, 'total': 75, 'overdue': 0}, summary)
paid = env.to_py(factions.eval(f"exports.core_bank:PayDebt({ids[5]}, {new_id}, 25, {{ channel = 'phone' }})"))
check('Export PayDebt (Teilzahlung vom Handy)', paid and paid['debt']['rest'] == 50 and paid['paid'] == 25, paid)
cancelled = env.to_py(factions.eval(f"exports.core_bank:CancelDebt({new_id}, {{ by = 'Bücherei', reason = 'Kulanz' }})"))
check('Export CancelDebt', cancelled and cancelled['status'] == 'cancelled' and debt(new_id)['closed_by'] == 'Bücherei', cancelled)
changed = env.events_for(1, 'core_bank:changed')
check('offene UI bekommt Bescheid bei jeder Änderung', {'what': 'account'} in changed and {'what': 'debts'} in changed, changed[-3:])

print('Log')
env.flush_log()
actions = {l['action'] for l in env.sql("SELECT action FROM audit_log WHERE category = 'bank'")}
check('Kategorie bank: Konto, Schulden, Einzug, Erlass, Admin-Blick', {'account_open', 'debt_add', 'debt_pay', 'debt_collect', 'debt_overdue', 'debt_cancel', 'admin_view'} <= actions, actions)
money_logs = env.sql("SELECT reason FROM audit_log WHERE category = 'money' AND character_id = %s", (ids[1],))
check('jede Geldbewegung steht im Geld-Log der Core', any('Einzahlung in der Filiale' in (l['reason'] or '') for l in money_logs)
      and any('Überweisung: Miete November' in (l['reason'] or '') for l in money_logs), [l['reason'] for l in money_logs][:6])

print(f'\n{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
